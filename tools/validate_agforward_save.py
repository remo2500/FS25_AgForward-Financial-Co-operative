#!/usr/bin/env python3
"""Offline validator for AgForward schema-v3 financial-state XML.

Use this on copies of agForwardFinance.xml / agForwardFinance.backup.xml after
future in-game tests. It complements, but does not replace, AgForward's in-game
IntegrityService.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SUPPORTED_SCHEMA = 3
ID_PATTERN = re.compile(r"^AGF-([A-Z0-9_]+)-(\d+)$")
REVOLVING_PRODUCTS = {"operatingLine", "cropInputLine"}

MONEY_ATTRS = {
    "amount", "principal", "interest", "fees", "originalPrincipal",
    "principalBalance", "creditLimit", "accruedInterest", "accruedFees",
    "scheduledPayment", "balloonAmount"
}


def finite_number(value: str) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def parse(path: Path) -> tuple[ET.Element | None, str | None]:
    try:
        return ET.parse(path).getroot(), None
    except (OSError, ET.ParseError) as exc:
        return None, str(exc)


def first_child(root: ET.Element, name: str) -> ET.Element | None:
    for child in root:
        if child.tag == name:
            return child
    return None


def validate(path: Path) -> dict:
    root, parse_error = parse(path)
    report = {
        "path": str(path),
        "valid": False,
        "schemaVersion": None,
        "saveGeneration": None,
        "errors": [],
        "warnings": [],
        "counts": {},
        "maxObservedIds": {},
    }

    if root is None:
        report["errors"].append(f"XML parse failed: {parse_error}")
        return report
    if root.tag != "agForwardFinance":
        report["errors"].append(f"Unexpected root element: {root.tag}")
        return report

    try:
        schema = int(root.attrib.get("schemaVersion", "0"))
    except ValueError:
        schema = 0
    try:
        generation = int(root.attrib.get("saveGeneration", "0"))
    except ValueError:
        generation = -1

    report["schemaVersion"] = schema
    report["saveGeneration"] = generation

    if schema <= 0:
        report["errors"].append("Missing/invalid schemaVersion")
    elif schema > SUPPORTED_SCHEMA:
        report["warnings"].append(
            f"Save schema {schema} is newer than validator schema {SUPPORTED_SCHEMA}; do not overwrite with an older build"
        )
    if generation < 0:
        report["errors"].append("Invalid saveGeneration")

    # Gather declared ID counters.
    counters: dict[str, int] = {}
    id_counters = first_child(root, "idCounters")
    if id_counters is not None:
        for node in id_counters.findall("counter"):
            scope = node.attrib.get("scope")
            try:
                value = int(node.attrib.get("value", "0"))
            except ValueError:
                value = -1
            if not scope:
                report["errors"].append("ID counter without scope")
            elif value < 0:
                report["errors"].append(f"Invalid ID counter {scope}={value}")
            elif scope in counters:
                report["errors"].append(f"Duplicate ID counter scope: {scope}")
            else:
                counters[scope] = value

    liabilities_node = first_child(root, "liabilities")
    liabilities = liabilities_node.findall("liability") if liabilities_node is not None else []
    ledger_node = first_child(root, "ledger")
    transactions_parent = first_child(ledger_node, "transactions") if ledger_node is not None else None
    transactions = transactions_parent.findall("transaction") if transactions_parent is not None else []

    report["counts"]["liabilities"] = len(liabilities)
    report["counts"]["transactions"] = len(transactions)

    liability_ids: set[str] = set()
    transaction_ids: set[str] = set()
    group_totals: dict[str, float] = {}
    observed_max: dict[str, int] = {}

    def observe_id(value: str | None, context: str) -> None:
        if not value:
            return
        match = ID_PATTERN.match(value)
        if not match:
            report["warnings"].append(f"Non-standard AgForward ID at {context}: {value}")
            return
        scope, number_text = match.groups()
        number = int(number_text)
        observed_max[scope] = max(observed_max.get(scope, 0), number)

    # Liability checks.
    for index, node in enumerate(liabilities):
        context = f"liability[{index}]"
        liability_id = node.attrib.get("id")
        if not liability_id:
            report["errors"].append(f"{context}: missing id")
            continue
        if liability_id in liability_ids:
            report["errors"].append(f"{context}: duplicate liability id {liability_id}")
        liability_ids.add(liability_id)
        observe_id(liability_id, context)

        try:
            farm_id = int(node.attrib.get("farmId", "0"))
        except ValueError:
            farm_id = 0
        if farm_id <= 0:
            report["errors"].append(f"{context}: invalid farmId {node.attrib.get('farmId')!r}")

        product_type = node.attrib.get("productType")
        principal = finite_number(node.attrib.get("principalBalance", "0"))
        credit_limit = finite_number(node.attrib.get("creditLimit", "0"))
        accrued_interest = finite_number(node.attrib.get("accruedInterest", "0"))
        accrued_fees = finite_number(node.attrib.get("accruedFees", "0"))
        for label, value in (
            ("principalBalance", principal),
            ("creditLimit", credit_limit),
            ("accruedInterest", accrued_interest),
            ("accruedFees", accrued_fees),
        ):
            if value is None:
                report["errors"].append(f"{context}: non-finite/invalid {label}")
            elif value < -0.005:
                report["errors"].append(f"{context}: negative {label}={value}")

        if product_type in REVOLVING_PRODUCTS and principal is not None and credit_limit is not None:
            if principal - credit_limit > 0.005:
                report["errors"].append(
                    f"{context}: revolving principal {principal:.2f} exceeds credit limit {credit_limit:.2f}"
                )

    # Transaction checks.
    for index, node in enumerate(transactions):
        context = f"transaction[{index}]"
        tx_id = node.attrib.get("id")
        if not tx_id:
            report["errors"].append(f"{context}: missing id")
            continue
        if tx_id in transaction_ids:
            report["errors"].append(f"{context}: duplicate transaction id {tx_id}")
        transaction_ids.add(tx_id)
        observe_id(tx_id, context)

        group_id = node.attrib.get("groupId")
        observe_id(group_id, context + ".groupId")

        amount = finite_number(node.attrib.get("amount", "0"))
        if amount is None:
            report["errors"].append(f"{context}: invalid amount")
            amount = 0.0
        if group_id:
            group_totals[group_id] = group_totals.get(group_id, 0.0) + amount

        liability_id = node.attrib.get("liabilityId")
        if schema >= 2 and liability_id and liability_id not in liability_ids:
            report["errors"].append(f"{context}: unresolved liabilityId {liability_id}")

        for attr in MONEY_ATTRS:
            if attr in node.attrib:
                number = finite_number(node.attrib[attr])
                if number is None:
                    report["errors"].append(f"{context}: invalid numeric {attr}={node.attrib[attr]!r}")

    # Linked draw/purchase groups should reconcile immediate economic cash to zero.
    # Not all future groups must be zero-sum, so only enforce groups that contain
    # both creditDraw and inputPurchase.
    grouped_types: dict[str, set[str]] = {}
    for node in transactions:
        group_id = node.attrib.get("groupId")
        if group_id:
            grouped_types.setdefault(group_id, set()).add(node.attrib.get("type", ""))
    for group_id, types in grouped_types.items():
        if {"creditDraw", "inputPurchase"}.issubset(types):
            total = group_totals.get(group_id, 0.0)
            if abs(total) > 0.005:
                report["errors"].append(f"CILOC/input group {group_id} does not reconcile to zero: {total:.2f}")

    # Persisted counters must be at least every observed ID.
    for scope, observed in observed_max.items():
        report["maxObservedIds"][scope] = observed
        declared = counters.get(scope)
        if declared is None:
            report["warnings"].append(f"No persisted counter for observed ID scope {scope}; loader must advance it from records")
        elif declared < observed:
            report["errors"].append(
                f"ID counter {scope}={declared} is below observed maximum {observed}; ID reuse risk"
            )

    settlement = first_child(root, "settlement")
    if schema >= 3:
        if settlement is None:
            report["warnings"].append("Schema v3 file has no settlement node")
        elif "engineVersion" not in settlement.attrib:
            report["warnings"].append("Settlement node has no engineVersion")

    report["valid"] = not report["errors"]
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate AgForward save-state XML")
    parser.add_argument("files", nargs="+", type=Path, help="Primary and/or backup AgForward XML files")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    args = parser.parse_args()

    reports = [validate(path) for path in args.files]
    if args.json:
        print(json.dumps(reports, indent=2))
    else:
        for report in reports:
            status = "PASS" if report["valid"] else "FAIL"
            print(f"{report['path']}: {status} schema={report['schemaVersion']} generation={report['saveGeneration']}")
            for warning in report["warnings"]:
                print(f"  WARNING: {warning}")
            for error in report["errors"]:
                print(f"  ERROR: {error}")
            print(f"  counts: {report['counts']}")

        if len(reports) == 2 and all(r["valid"] for r in reports):
            generations = [r["saveGeneration"] for r in reports]
            if generations[0] != generations[1]:
                print(f"WARNING: valid copies have different generations: {generations}")
            else:
                print(f"Primary/recovery generation agreement: {generations[0]}")

    return 0 if all(report["valid"] for report in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
