#!/usr/bin/env python3
"""Analyze an FS25 log for AgForward runtime validation markers.

This helper is intentionally conservative. It does not prove gameplay correctness;
it turns a future disposable-save test log into a quick, reproducible first-pass
report for initialization, persistence, safe mode, Red Tape, and Lua errors.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

AGF_LINE = re.compile(r"AgForward", re.IGNORECASE)
LUA_ERROR = re.compile(r"(?:Error:\s*Running LUA method|LUA call stack|attempt to|stack traceback)", re.IGNORECASE)


def analyze(text: str) -> dict:
    lines = text.splitlines()
    agf_lines = [(idx + 1, line) for idx, line in enumerate(lines) if AGF_LINE.search(line)]
    error_lines = [(idx + 1, line) for idx, line in enumerate(lines) if LUA_ERROR.search(line)]

    initialization = [item for item in agf_lines if "initialized" in item[1].lower()]
    safe_mode = [item for item in agf_lines if "safe mode" in item[1].lower() or "read_only" in item[1].lower() or "read-only" in item[1].lower()]
    new_state = [item for item in agf_lines if "new_state" in item[1].lower() or "starting a new agforward save" in item[1].lower() or "new_save" in item[1].lower()]
    loaded = [item for item in agf_lines if "loaded financial state" in item[1].lower() or "save: loaded" in item[1].lower()]
    recovered = [item for item in agf_lines if "recover" in item[1].lower()]
    red_tape = [item for item in agf_lines if "red tape" in item[1].lower()]
    compatibility = [item for item in agf_lines if "compat" in item[1].lower() or "overlapping" in item[1].lower()]
    save_failures = [
        item for item in agf_lines
        if any(token in item[1].lower() for token in (
            "write_failed", "save failed", "could not save", "integrity_failed",
            "no_valid_financial_copy", "newer_save_schema"
        ))
    ]

    critical = []
    if error_lines:
        critical.append("Lua/runtime error markers found in log")
    if len(initialization) > 1:
        critical.append(f"AgForward initialized {len(initialization)} times in one log")
    if save_failures:
        critical.append("AgForward save/integrity failure marker found")

    observations = []
    if not initialization:
        observations.append("No AgForward initialization marker found")
    if new_state:
        observations.append("AgForward reported a new financial state")
    if loaded:
        observations.append("AgForward reported loading persisted financial state")
    if recovered:
        observations.append("AgForward recovery/backup marker found")
    if safe_mode:
        observations.append("AgForward entered or referenced read-only safe mode")
    if red_tape:
        observations.append("Red Tape integration/detection marker found")
    if compatibility:
        observations.append("Compatibility/overlapping-mod marker found")

    return {
        "status": "FAIL" if critical else ("WARN" if not initialization else "PASS_FIRST_PASS"),
        "critical_findings": critical,
        "observations": observations,
        "counts": {
            "agforward_lines": len(agf_lines),
            "initialization_lines": len(initialization),
            "lua_error_markers": len(error_lines),
            "safe_mode_lines": len(safe_mode),
            "recovery_lines": len(recovered),
            "save_failure_lines": len(save_failures),
        },
        "agforward_lines": [{"line": no, "text": line} for no, line in agf_lines],
        "error_lines": [{"line": no, "text": line} for no, line in error_lines],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze FS25 log.txt for AgForward runtime markers")
    parser.add_argument("log", type=Path, help="Path to FS25 log.txt")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of human-readable text")
    args = parser.parse_args()

    try:
        text = args.log.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"Could not read log: {exc}")
        return 2

    report = analyze(text)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"AgForward runtime log analysis: {report['status']}")
        for finding in report["critical_findings"]:
            print(f"CRITICAL: {finding}")
        for observation in report["observations"]:
            print(f"- {observation}")
        print("Counts:")
        for key, value in report["counts"].items():
            print(f"  {key}: {value}")
        if report["agforward_lines"]:
            print("AgForward lines:")
            for item in report["agforward_lines"]:
                print(f"  L{item['line']}: {item['text']}")

    return 1 if report["status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
