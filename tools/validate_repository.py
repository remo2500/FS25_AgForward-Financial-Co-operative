#!/usr/bin/env python3
"""Static repository validation for AgForward.

This intentionally does not claim to replace GIANTS TestRunner or an in-game
runtime test. It catches packaging/document hygiene failures before a build is
handed to FS25.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD_DESC = ROOT / "modDesc.xml"


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)


def parse_xml(path: Path, errors: list[str]) -> ET.Element | None:
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, OSError) as exc:
        fail(f"XML parse failed: {path.relative_to(ROOT)}: {exc}", errors)
        return None


def validate_mod_desc(errors: list[str]) -> None:
    root = parse_xml(MOD_DESC, errors)
    if root is None:
        return

    if root.tag != "modDesc":
        fail("modDesc.xml root must be <modDesc>", errors)

    version_node = root.find("version")
    version = (version_node.text or "").strip() if version_node is not None else ""
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", version):
        fail(f"Unexpected mod version format: {version!r}", errors)

    extra = root.find("extraSourceFiles")
    if extra is None:
        fail("modDesc.xml has no <extraSourceFiles>", errors)
        return

    seen: set[str] = set()
    sources: list[str] = []
    for source in extra.findall("sourceFile"):
        filename = source.attrib.get("filename", "").strip()
        if not filename:
            fail("sourceFile entry without filename", errors)
            continue
        if filename in seen:
            fail(f"Duplicate sourceFile entry: {filename}", errors)
        seen.add(filename)
        sources.append(filename)
        path = ROOT / filename
        if not path.is_file():
            fail(f"Missing sourceFile: {filename}", errors)

    if not sources:
        fail("No Lua source files registered in modDesc.xml", errors)
    elif sources[-1] != "src/AgForwardFinance.lua":
        fail("src/AgForwardFinance.lua must load last so dependencies already exist", errors)

    required_order = [
        "src/core/RuntimeStateService.lua",
        "src/core/Currency.lua",
        "src/ledger/Transaction.lua",
        "src/ledger/Ledger.lua",
        "src/liabilities/Liability.lua",
        "src/liabilities/LiabilityRegistry.lua",
        "src/ledger/FinancialOperationCoordinator.lua",
        "src/ledger/AccountingService.lua",
        "src/core/IntegrityService.lua",
        "src/core/SaveService.lua",
        "src/AgForwardFinance.lua",
    ]
    positions = {name: idx for idx, name in enumerate(sources)}
    missing = [name for name in required_order if name not in positions]
    if missing:
        fail("Required Phase 0 source registrations missing: " + ", ".join(missing), errors)
    else:
        for left, right in zip(required_order, required_order[1:]):
            if positions[left] >= positions[right]:
                fail(f"Source dependency order invalid: {left} must load before {right}", errors)

    l10n = root.find("l10n")
    if l10n is not None:
        prefix = l10n.attrib.get("filenamePrefix")
        if prefix:
            english = ROOT / f"{prefix}_en.xml"
            if not english.is_file():
                fail(f"Missing English localization file: {english.relative_to(ROOT)}", errors)
            else:
                parse_xml(english, errors)


def validate_expected_files(errors: list[str]) -> None:
    required = [
        "README.md",
        "LICENSE",
        "docs/AGFORWARD_CURRENT_AUTHORITY.md",
        "docs/AGFORWARD_TECHNICAL_SPECIFICATION.md",
        "docs/DONOR_REFERENCE_REAUDIT.md",
        "docs/PHASE0_FOUNDATION_HARDENING.md",
        "docs/SAVE_SCHEMA_V3.md",
    ]
    for name in required:
        if not (ROOT / name).is_file():
            fail(f"Missing governing file: {name}", errors)


def validate_no_packaged_artifacts(errors: list[str]) -> None:
    for path in ROOT.rglob("*.zip"):
        if ".git" not in path.parts:
            fail(f"Packaged ZIP should not be committed: {path.relative_to(ROOT)}", errors)


def validate_lua_text(errors: list[str]) -> None:
    """Cheap hygiene checks only; not a Lua parser.

    Compatibility detection is allowed to contain donor mod *names*. What we
    reject here are obvious source/path imports that would indicate donor code
    or assets were accidentally wired into AgForward production Lua.
    """
    suspicious_path_fragments = (
        "FS25_BankCredit/",
        "FS25_FinanceYourFleet/",
        "FS25_AgriCreditSolutions/",
        "FS25_FieldLeasing/",
        "FS25_EconomicHistory/",
        "FS25_TradeInMenu/",
    )

    for path in ROOT.rglob("*.lua"):
        text = path.read_text(encoding="utf-8")
        if "\t" in text:
            # Tabs are legal; warn through stdout rather than failing.
            print(f"warning: tab characters in {path.relative_to(ROOT)}")
        if any(fragment in text for fragment in suspicious_path_fragments):
            fail(f"Possible donor source/path import in production Lua: {path.relative_to(ROOT)}", errors)


def main() -> int:
    errors: list[str] = []
    validate_mod_desc(errors)
    validate_expected_files(errors)
    validate_no_packaged_artifacts(errors)
    validate_lua_text(errors)

    if errors:
        print("AgForward static validation FAILED")
        for error in errors:
            print(f" - {error}")
        return 1

    print("AgForward static validation PASSED")
    print("Note: GIANTS TestRunner and in-game runtime validation are still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
