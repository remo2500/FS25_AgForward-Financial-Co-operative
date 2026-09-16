#!/usr/bin/env python3
"""Build a deterministic AgForward FS25 mod ZIP from the repository.

The archive is intentionally rooted at modDesc.xml (no extra repository folder),
excludes development-only material, and verifies every modDesc sourceFile before
writing. This is packaging validation only; it does not replace GIANTS TestRunner
or an in-game load test.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import sys
import xml.etree.ElementTree as ET
import zipfile

PACKAGE_NAME = "FS25_AgForwardFinance.zip"
DETERMINISTIC_TIME = (2026, 1, 1, 0, 0, 0)

EXCLUDED_TOP_LEVEL = {
    ".git",
    ".github",
    "docs",
    "tests",
    "tools",
}
EXCLUDED_ROOT_FILES = {
    ".gitignore",
    "README.md",
}
EXCLUDED_SUFFIXES = {
    ".pyc",
    ".pyo",
    ".log",
    ".tmp",
    ".bak",
}


def normalize_source_path(value: str) -> str:
    return value.replace("\\", "/").lstrip("./")


def parse_moddesc(repo_root: Path) -> tuple[list[str], list[str]]:
    moddesc = repo_root / "modDesc.xml"
    if not moddesc.is_file():
        raise ValueError("modDesc.xml is missing from repository root")

    try:
        root = ET.parse(moddesc).getroot()
    except ET.ParseError as exc:
        raise ValueError(f"modDesc.xml is not valid XML: {exc}") from exc

    source_files: list[str] = []
    for node in root.findall(".//sourceFile"):
        filename = node.attrib.get("filename") or node.attrib.get("file")
        if filename:
            source_files.append(normalize_source_path(filename))

    referenced_assets: list[str] = []
    for tag in ("iconFilename", "multiplayer/permissions/iconFilename"):
        for node in root.findall(f".//{tag.split('/')[-1]}"):
            if node.text and node.text.strip():
                referenced_assets.append(normalize_source_path(node.text.strip()))

    return source_files, referenced_assets


def should_include(relative: PurePosixPath) -> bool:
    if not relative.parts:
        return False
    if relative.parts[0] in EXCLUDED_TOP_LEVEL:
        return False
    if len(relative.parts) == 1 and relative.name in EXCLUDED_ROOT_FILES:
        return False
    if any(part == "__pycache__" for part in relative.parts):
        return False
    if relative.suffix.lower() in EXCLUDED_SUFFIXES:
        return False
    if relative.name.startswith(".") and relative.name not in {".keep"}:
        return False
    return True


def collect_files(repo_root: Path, output_path: Path) -> list[Path]:
    files: list[Path] = []
    output_resolved = output_path.resolve()
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        if path.resolve() == output_resolved:
            continue
        relative = PurePosixPath(path.relative_to(repo_root).as_posix())
        if should_include(relative):
            files.append(path)
    files.sort(key=lambda item: item.relative_to(repo_root).as_posix())
    return files


def validate_package_inputs(repo_root: Path, files: list[Path]) -> list[str]:
    errors: list[str] = []
    relative_files = {path.relative_to(repo_root).as_posix() for path in files}

    if "modDesc.xml" not in relative_files:
        errors.append("modDesc.xml would not be included at ZIP root")

    try:
        source_files, referenced_assets = parse_moddesc(repo_root)
    except ValueError as exc:
        return [str(exc)]

    for source in source_files:
        if not (repo_root / source).is_file():
            errors.append(f"modDesc sourceFile missing on disk: {source}")
        elif source not in relative_files:
            errors.append(f"modDesc sourceFile excluded from package: {source}")

    for asset in referenced_assets:
        if (repo_root / asset).is_file() and asset not in relative_files:
            errors.append(f"referenced asset excluded from package: {asset}")

    # Development-only folders must never leak into the released mod ZIP.
    for relative in relative_files:
        first = PurePosixPath(relative).parts[0]
        if first in EXCLUDED_TOP_LEVEL:
            errors.append(f"development file would leak into package: {relative}")

    return errors


def write_deterministic_zip(repo_root: Path, files: list[Path], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            relative = path.relative_to(repo_root).as_posix()
            data = path.read_bytes()
            info = zipfile.ZipInfo(relative, date_time=DETERMINISTIC_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)


def validate_built_zip(output_path: Path, expected_files: list[str]) -> list[str]:
    errors: list[str] = []
    with zipfile.ZipFile(output_path, "r") as archive:
        names = archive.namelist()
        name_set = set(names)
        if not names:
            errors.append("built ZIP is empty")
            return errors
        if "modDesc.xml" not in name_set:
            errors.append("built ZIP does not contain modDesc.xml at archive root")
        if len(names) != len(name_set):
            errors.append("built ZIP contains duplicate paths")
        for expected in expected_files:
            if expected not in name_set:
                errors.append(f"built ZIP missing expected file: {expected}")
        for name in names:
            path = PurePosixPath(name)
            if path.parts and path.parts[0] in EXCLUDED_TOP_LEVEL:
                errors.append(f"built ZIP contains development path: {name}")
            if name.startswith("/") or ".." in path.parts:
                errors.append(f"unsafe archive path: {name}")
    return errors


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(repo_root: Path, output_path: Path) -> dict:
    repo_root = repo_root.resolve()
    output_path = output_path.resolve()
    files = collect_files(repo_root, output_path)
    errors = validate_package_inputs(repo_root, files)
    if errors:
        raise ValueError("; ".join(errors))

    write_deterministic_zip(repo_root, files, output_path)
    expected = [path.relative_to(repo_root).as_posix() for path in files]
    zip_errors = validate_built_zip(output_path, expected)
    if zip_errors:
        output_path.unlink(missing_ok=True)
        raise ValueError("; ".join(zip_errors))

    return {
        "path": str(output_path),
        "fileCount": len(files),
        "sizeBytes": output_path.stat().st_size,
        "sha256": sha256(output_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Repository root")
    parser.add_argument("--output", type=Path, default=None, help="Output ZIP path")
    args = parser.parse_args()

    repo_root = args.repo.resolve()
    output = args.output.resolve() if args.output else repo_root / "dist" / PACKAGE_NAME
    try:
        result = build(repo_root, output)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"PACKAGE BUILD FAILED: {exc}", file=sys.stderr)
        return 1

    print(f"PACKAGE BUILD PASS: {result['path']}")
    print(f"files={result['fileCount']} size={result['sizeBytes']} sha256={result['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
