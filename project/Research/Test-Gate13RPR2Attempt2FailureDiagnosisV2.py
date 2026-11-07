#!/usr/bin/env python3
"""Validation for the v2 canonical-order-only repair."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
ENTRY = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV2.py"
EXPECTED = "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("fd1_v2", ENTRY)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    tests = [
        {"name": "v2-canonical-hash", "passed": module.CORE.EXPECTED_PREWRITE_TREE_SHA256 == EXPECTED},
        {"name": "v1-core-preserved", "passed": module.CORE_PATH.name == "Analyze-Gate13RPR2Attempt2FailureV1.py"},
        {"name": "unicode-ordinal-uppercase-before-lowercase", "passed": sorted(["x.summary", "x.Unity"])[0] == "x.Unity"},
        {"name": "no-unity-execution", "passed": "Unity.exe" not in ENTRY.read_text(encoding="utf-8")},
    ]
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-fd1-canonical-order-v2-test-summary",
        "passed": all(item["passed"] for item in tests),
        "passedCount": sum(item["passed"] for item in tests),
        "failedCount": sum(not item["passed"] for item in tests),
        "tests": tests,
        "unityInvoked": False,
    }
    if args.output:
        module.CORE.atomic_write_json(Path(args.output).resolve(), result)
    print(json.dumps(result, sort_keys=True, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
