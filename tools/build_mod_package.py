#!/usr/bin/env python3
"""Build a deterministic AgForward FS25 runtime ZIP.

The repository intentionally contains many offline-only research/model modules.
A test ZIP must therefore include only files explicitly promoted to the runtime
surface rather than sweeping the whole ``src`` tree.

Runtime promotion sources:
- ``modDesc.xml`` itself;
- every ``<extraSourceFiles><sourceFile ...>`` entry;
- localization files matching ``<l10n filenamePrefix=...>``;
- common modDesc file references such as ``iconFilename`` when present;
- ``LICENSE`` when present;
- optional paths/globs listed in ``runtime_package_manifest.txt``.

The archive is rooted at ``modDesc.xml`` and uses deterministic timestamps and
ordering. This is packaging validation only; it does not replace GIANTS
TestRunner or an in-game load test.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import os
from pathlib import Path, PurePosixPath
import sys
import xml.etree.ElementTree as ET
import zipfile

PACKAGE_NAME = "FS25_AgForwardFinance.zip"
DETERMINISTIC_TIME = (2026, 1, 1, 0, 0, 0)
OPTIONAL_MANIFEST = "runtime_package_manifest.txt"

# These directories are development authority only and may never be explicitly
# promoted through the optional runtime manifest.
FORBIDDEN_PACKAGE_PREFIXES = {
    ".git",
    ".github",
    "docs",
    "tests",
    "tools",
}


def normalize_repo_path(value: str) -> str:
    """Return a safe repository-relative POSIX path."""
    raw = value.replace("\\", "/").strip()
    if not raw:
        raise ValueError("empty package path")
    pure = PurePosixPath(raw)
    if pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"unsafe repository path: {value!r}")
    normalized = pure.as_posix().lstrip("./")
    if not normalized:
        raise ValueError(f"invalid repository path: {value!r}")
    return normalized


def _resolve_file(repo_root: Path, relative: str) -> Path:
    normalized = normalize_repo_path(relative)
    path = (repo_root / normalized).resolve()
    root = repo_root.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path escapes repository: {relative!r}") from exc
    return path


def parse_moddesc(repo_root: Path) -> tuple[ET.Element, list[str]]:
    moddesc = repo_root / "modDesc.xml"
    if not moddesc.is_file():
        raise ValueError("modDesc.xml is missing from repository root")

    try:
        root = ET.parse(moddesc).getroot()
    except ET.ParseError as exc:
        raise ValueError(f"modDesc.xml is not valid XML: {exc}") from exc

    source_files: list[str] = []
    extra = root.find("extraSourceFiles")
    if extra is not None:
        for node in extra.findall("sourceFile"):
            filename = node.attrib.get("filename") or node.attrib.get("file")
            if filename:
                source_files.append(normalize_repo_path(filename))

    return root, source_files


def _add_required_file(repo_root: Path, selected: dict[str, Path], relative: str, description: str) -> None:
    normalized = normalize_repo_path(relative)
    path = _resolve_file(repo_root, normalized)
    if not path.is_file():
        raise ValueError(f"{description} missing on disk: {normalized}")
    selected[normalized] = path


def _collect_localization(repo_root: Path, moddesc_root: ET.Element, selected: dict[str, Path]) -> None:
    l10n = moddesc_root.find("l10n")
    if l10n is None:
        return
    prefix = (l10n.attrib.get("filenamePrefix") or "").strip()
    if not prefix:
        return

    normalized_prefix = normalize_repo_path(prefix)
    prefix_path = _resolve_file(repo_root, normalized_prefix)
    pattern = str(prefix_path) + "_*.xml"
    matches = sorted(Path(item) for item in glob.glob(pattern))
    if not matches:
        raise ValueError(f"no localization files found for filenamePrefix: {normalized_prefix}")

    for path in matches:
        if not path.is_file():
            continue
        relative = path.resolve().relative_to(repo_root.resolve()).as_posix()
        selected[relative] = path.resolve()


def _collect_simple_moddesc_references(repo_root: Path, moddesc_root: ET.Element, selected: dict[str, Path]) -> None:
    """Collect common direct file references currently used by FS modDesc files.

    Lua/XML resources loaded indirectly by code should be explicitly listed in
    ``runtime_package_manifest.txt`` once they are promoted.
    """
    for tag in ("iconFilename",):
        for node in moddesc_root.findall(f".//{tag}"):
            text = (node.text or "").strip()
            if text:
                _add_required_file(repo_root, selected, text, f"modDesc {tag}")


def _manifest_entries(repo_root: Path) -> list[str]:
    manifest = repo_root / OPTIONAL_MANIFEST
    if not manifest.is_file():
        return []

    entries: list[str] = []
    for line_number, raw_line in enumerate(manifest.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            entries.append(normalize_repo_path(line))
        except ValueError as exc:
            raise ValueError(f"{OPTIONAL_MANIFEST}:{line_number}: {exc}") from exc
    return entries


def _collect_manifest_resources(repo_root: Path, selected: dict[str, Path]) -> None:
    root = repo_root.resolve()
    for entry in _manifest_entries(repo_root):
        first = PurePosixPath(entry).parts[0]
        if first in FORBIDDEN_PACKAGE_PREFIXES:
            raise ValueError(f"runtime manifest may not include development path: {entry}")

        # Allow explicit globs for GUI/assets while still requiring every match to
        # remain inside the repository.
        has_glob = any(character in entry for character in "*?[")
        if has_glob:
            matches = sorted(Path(item) for item in glob.glob(str(root / entry), recursive=True))
            file_matches = [path for path in matches if path.is_file()]
            if not file_matches:
                raise ValueError(f"runtime manifest pattern matched no files: {entry}")
            for path in file_matches:
                resolved = path.resolve()
                try:
                    relative = resolved.relative_to(root).as_posix()
                except ValueError as exc:
                    raise ValueError(f"runtime manifest match escaped repository: {path}") from exc
                selected[relative] = resolved
        else:
            _add_required_file(repo_root, selected, entry, "runtime manifest resource")


def collect_runtime_files(repo_root: Path) -> list[Path]:
    repo_root = repo_root.resolve()
    moddesc_root, source_files = parse_moddesc(repo_root)
    selected: dict[str, Path] = {"modDesc.xml": repo_root / "modDesc.xml"}

    for source in source_files:
        _add_required_file(repo_root, selected, source, "modDesc sourceFile")

    _collect_localization(repo_root, moddesc_root, selected)
    _collect_simple_moddesc_references(repo_root, moddesc_root, selected)
    _collect_manifest_resources(repo_root, selected)

    license_file = repo_root / "LICENSE"
    if license_file.is_file():
        selected["LICENSE"] = license_file.resolve()

    # Deterministic ordering, with modDesc first for human-readable manifests.
    names = sorted(selected)
    if "modDesc.xml" in names:
        names.remove("modDesc.xml")
        names.insert(0, "modDesc.xml")
    return [selected[name] for name in names]


def validate_package_inputs(repo_root: Path, files: list[Path]) -> list[str]:
    errors: list[str] = []
    root = repo_root.resolve()
    relative_files: set[str] = set()

    for path in files:
        resolved = path.resolve()
        try:
            relative = resolved.relative_to(root).as_posix()
        except ValueError:
            errors.append(f"package file escapes repository: {path}")
            continue
        if relative in relative_files:
            errors.append(f"duplicate package path: {relative}")
        relative_files.add(relative)

    if "modDesc.xml" not in relative_files:
        errors.append("modDesc.xml would not be included at ZIP root")

    try:
        _, source_files = parse_moddesc(repo_root)
    except ValueError as exc:
        return [str(exc)]

    for source in source_files:
        if source not in relative_files:
            errors.append(f"modDesc sourceFile excluded from package: {source}")

    for relative in relative_files:
        parts = PurePosixPath(relative).parts
        if parts and parts[0] in FORBIDDEN_PACKAGE_PREFIXES:
            errors.append(f"development file would leak into package: {relative}")

    return errors


def write_deterministic_zip(repo_root: Path, files: list[Path], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            relative = path.resolve().relative_to(repo_root.resolve()).as_posix()
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
        if set(expected_files) != name_set:
            missing = sorted(set(expected_files) - name_set)
            extra = sorted(name_set - set(expected_files))
            if missing:
                errors.append("built ZIP missing expected files: " + ", ".join(missing))
            if extra:
                errors.append("built ZIP contains unexpected files: " + ", ".join(extra))
        for name in names:
            path = PurePosixPath(name)
            if path.parts and path.parts[0] in FORBIDDEN_PACKAGE_PREFIXES:
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
    files = collect_runtime_files(repo_root)
    errors = validate_package_inputs(repo_root, files)
    if errors:
        raise ValueError("; ".join(errors))

    write_deterministic_zip(repo_root, files, output_path)
    expected = [path.resolve().relative_to(repo_root).as_posix() for path in files]
    zip_errors = validate_built_zip(output_path, expected)
    if zip_errors:
        output_path.unlink(missing_ok=True)
        raise ValueError("; ".join(zip_errors))

    return {
        "path": str(output_path),
        "fileCount": len(files),
        "sizeBytes": output_path.stat().st_size,
        "sha256": sha256(output_path),
        "manifest": expected,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Repository root")
    parser.add_argument("--output", type=Path, default=None, help="Output ZIP path")
    parser.add_argument("--list", action="store_true", help="Print the selected runtime manifest")
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
    if args.list:
        for name in result["manifest"]:
            print(name)
    print("Only explicitly promoted runtime resources were packaged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
