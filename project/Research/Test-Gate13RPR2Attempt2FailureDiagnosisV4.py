#!/usr/bin/env python3
"""Validation-only tests for the V4 source-evidence repair."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
ENTRY = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV4.py"
PRESERVED_V3 = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV3.py"
PRESERVED_V3_SHA256 = "8f84de107e87d51682574c3b38d00f96305674473408a36f909e1d7fd4c4f44d"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("fd1_v4", ENTRY)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    evidence = module.extract_enforcement_source_evidence_v4(
        PROJECT / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV4.cs"
    )
    tests = [
        {"name": "v3-preserved", "passed": module.V3.CORE.sha256_file(PRESERVED_V3) == PRESERVED_V3_SHA256},
        {"name": "explicit-managed-deferred-fixture", "passed": evidence["explicitNonFinalManagedFixturePresent"] is True},
        {"name": "explicit-final-native-fixtures", "passed": evidence["explicitFinalNativeFixturesPresent"] is True},
        {"name": "production-final-boundary-conditions", "passed": evidence["productionFinalBoundaryConditionsPresent"] is True},
        {"name": "no-unity-command", "passed": not any(token in ENTRY.read_text(encoding="utf-8") for token in ("Unity.exe", "Start-Process", "subprocess.run", "subprocess.Popen"))},
        {"name": "no-attempt3-root", "passed": "Gate13R_RQAligned_S48H48/v3" not in ENTRY.read_text(encoding="utf-8")},
    ]
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-enforcement-boundary-v4-repair-test-summary",
        "passed": all(item["passed"] for item in tests),
        "passedCount": sum(item["passed"] for item in tests),
        "failedCount": sum(not item["passed"] for item in tests),
        "tests": tests,
        "unityInvoked": False,
        "formalAnalysisPerformed": False,
        "attempt3Created": False,
    }
    if args.output:
        module.V3.CORE.atomic_write_json(Path(args.output).resolve(), result)
    print(json.dumps(result, sort_keys=True, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
