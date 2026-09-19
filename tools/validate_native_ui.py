#!/usr/bin/env python3
"""Validate the offline AgForward GUI against its native-FS25 design contract.

This is a static guard only. It does not prove that GIANTS profiles still exist
or that the layout renders correctly at runtime.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "gui" / "AgForwardFrame.xml"
MOD_DESC = ROOT / "modDesc.xml"

APPROVED_NATIVE_PROFILES = {
    "baseReference",
    "emptyPanel",
    "fs25_menuContainer",
    "fs25_menuHeaderPanel",
    "fs25_menuHeaderIconBg",
    "fs25_menuHeaderIcon",
    "fs25_menuHeaderTitle",
    "fs25_shopMoneyBoxBg",
    "fs25_shopMoneyBox",
    "fs25_shopBalance",
    "fs25_shopMoney",
    "fs25_subCategorySelectorTabbedBox",
    "fs25_subCategorySelectorTabbedTab",
    "fs25_subCategorySelectorTabbedTabBg",
    "fs25_subCategorySelectorTabbed",
    "fs25_subCategorySelectorTabbedContainer",
    "fs25_lineSeparatorTopHighlighted",
    "fs25_statisticsHeaderBox",
    "fs25_textDefault",
    "fs25_financesList",
    "fs25_financesListItem",
    "fs25_financesListItemBg",
}

COLOR_PROPERTY_PREFIXES = (
    "textColor",
    "textSelectedColor",
    "textFocusedColor",
    "textDisabledColor",
    "imageColor",
    "imageSelectedColor",
    "imageFocusedColor",
    "imageDisabledColor",
    "imageHighlightedColor",
)

REQUIRED_IDS = {
    "currentBalanceText",
    "subCategoryPaging",
    "overviewCashValue",
    "overviewEquityValue",
    "overviewDebtValue",
    "overviewWorkingCapitalValue",
    "overviewDSCRValue",
    "overviewFCCRValue",
    "overviewDebtAssetsValue",
    "overviewDataQualityValue",
    "obligationList",
    "facilityList",
    "reportList",
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []

    try:
        root = ET.parse(LAYOUT).getroot()
    except (ET.ParseError, OSError) as exc:
        print(f"AgForward native UI validation FAILED: {exc}")
        return 1

    if root.tag != "GUI":
        fail(errors, "AgForwardFrame.xml root must be <GUI>")

    profiles = root.find("GUIProfiles")
    if profiles is None:
        fail(errors, "GUIProfiles block is required for native-derived sizing profiles")
        custom_profiles: dict[str, str | None] = {}
    else:
        custom_profiles = {}
        for profile in profiles.findall("Profile"):
            name = profile.attrib.get("name", "").strip()
            extends = profile.attrib.get("extends")
            if not name:
                fail(errors, "custom Profile without name")
                continue
            if name.startswith("fs25_"):
                fail(errors, f"custom profile must not shadow GIANTS profile: {name}")
            if name in custom_profiles:
                fail(errors, f"duplicate custom profile: {name}")
            custom_profiles[name] = extends

            for child in list(profile):
                if child.tag in COLOR_PROPERTY_PREFIXES:
                    value = child.attrib.get("value", "")
                    if value and not value.startswith("$preset_fs25_"):
                        fail(errors, f"{name}.{child.tag} must use an FS25 preset, got {value!r}")

    for name, extends in custom_profiles.items():
        if extends is None:
            fail(errors, f"custom profile {name} must inherit from a native/base or AgForward native-derived profile")
        elif extends not in APPROVED_NATIVE_PROFILES and extends not in custom_profiles:
            fail(errors, f"custom profile {name} extends unapproved profile {extends}")

    seen_ids: set[str] = set()
    for element in root.iter():
        if element.tag == "Profile":
            continue
        profile = element.attrib.get("profile")
        if profile and profile not in APPROVED_NATIVE_PROFILES and profile not in custom_profiles:
            fail(errors, f"element {element.tag} uses unapproved profile {profile}")

        element_id = element.attrib.get("id")
        if element_id:
            base_id = element_id.split("[", 1)[0]
            seen_ids.add(base_id)

        for attribute, value in element.attrib.items():
            if attribute in COLOR_PROPERTY_PREFIXES and value and not value.startswith("$preset_fs25_"):
                fail(errors, f"element {element.tag} {attribute} must use FS25 preset, got {value!r}")

    missing_ids = sorted(REQUIRED_IDS - seen_ids)
    if missing_ids:
        fail(errors, "missing required control IDs: " + ", ".join(missing_ids))

    tabs = [node for node in root.iter("Button") if node.attrib.get("id", "").startswith("subCategoryTabs[")]
    pages = [node for node in root.iter("GuiElement") if node.attrib.get("id", "").startswith("subCategoryPages[")]
    if len(tabs) != 8:
        fail(errors, f"expected 8 native secondary-navigation tabs, found {len(tabs)}")
    if len(pages) != 8:
        fail(errors, f"expected 8 subcategory pages, found {len(pages)}")

    mod_text = MOD_DESC.read_text(encoding="utf-8")
    if "gui/AgForwardFrame.xml" in mod_text or "AgForwardNativeMenuFrame.lua" in mod_text:
        fail(errors, "offline UI must not be promoted in modDesc.xml before runtime gate")

    if errors:
        print("AgForward native UI validation FAILED")
        for error in errors:
            print(f" - {error}")
        return 1

    print("AgForward native UI validation PASSED")
    print("Note: profile existence, scaling, focus graph, icon UVs and rendering still require FS25 runtime validation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
