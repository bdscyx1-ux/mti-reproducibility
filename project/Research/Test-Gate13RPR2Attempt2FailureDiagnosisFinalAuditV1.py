#!/usr/bin/env python3
"""Final validation-only audit for Gate 13R-PR2-FD1."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import stat
from pathlib import Path
from typing import Any


PROJECT = Path(__file__).resolve().parents[1]
CORE_PATH = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV1.py"
SPEC = importlib.util.spec_from_file_location("gate13r_pr2_fd1_audit_core", CORE_PATH)
CORE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CORE)

EXPECTED_TREE = "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e"
EXPECTED_COUNT = 28020
EXPECTED_BYTES = 8536611302


def read_json(path: Path) -> Any:
    return CORE.read_json(path)


def is_read_only(path: Path) -> bool:
    attributes = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attributes & getattr(stat, "FILE_ATTRIBUTE_READONLY", 1))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--failed-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timestamp", required=True)
    args = parser.parse_args()
    failed_root = Path(args.failed_root).resolve()
    checks: list[dict[str, Any]] = []

    def check(name: str, condition: bool, evidence: Any = None) -> None:
        checks.append({"name": name, "passed": bool(condition), "evidence": evidence})
        if not condition:
            raise CORE.DiagnosticError(f"Final audit failed: {name}: {evidence}")

    records, tree, raw_bytes = CORE.build_file_manifest(failed_root)
    check("failed-root-file-count", len(records) == EXPECTED_COUNT, len(records))
    check("failed-root-raw-bytes", raw_bytes == EXPECTED_BYTES, raw_bytes)
    check("failed-root-canonical-tree", tree == EXPECTED_TREE, tree)
    not_read_only = [record["relativePath"] for record in records if not is_read_only(failed_root / record["relativePath"])]
    check("failed-root-all-files-read-only", not not_read_only, {"notReadOnlyCount": len(not_read_only), "first": not_read_only[:5]})

    frozen_manifest = read_json(PROJECT / "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Frozen_Input_Manifest.v1.json")
    mismatches = []
    for item in frozen_manifest.get("inputs", []):
        path = PROJECT / item["relativePath"]
        actual = CORE.sha256_file(path) if path.is_file() else None
        if actual != item["sha256"]:
            mismatches.append({"relativePath": item["relativePath"], "expected": item["sha256"], "actual": actual})
    check("frozen-key-inputs-byte-identical", not mismatches, mismatches)

    output_root = PROJECT / "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v2"
    output_manifest = read_json(output_root / "evidence-manifest.json")
    output_mismatches = []
    for item in output_manifest.get("files", []):
        path = output_root / item["relativePath"]
        actual = CORE.sha256_file(path) if path.is_file() else None
        if actual != item["sha256"] or (path.stat().st_size if path.is_file() else None) != item["bytes"]:
            output_mismatches.append(item["relativePath"])
    check("v2-analysis-output-manifest-self-verifies", not output_mismatches, output_mismatches)

    deterministic = read_json(PROJECT / "Research/Verification/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/enforcement-boundary-deterministic-regeneration-summary.json")
    check("deterministic-regeneration", deterministic.get("passed") is True and deterministic.get("fileCount") == 5, deterministic)
    for branch in ("BoundaryDeterminismA", "BoundaryDeterminismB"):
        comparison_root = PROJECT / "Research/Verification/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1" / branch
        differences = []
        for path in output_root.iterdir():
            if path.is_file() and CORE.sha256_file(path) != CORE.sha256_file(comparison_root / path.name):
                differences.append(path.name)
        check(f"v2-output-equals-{branch}", not differences, differences)

    test_summaries = [
        "synthetic-test-summary.json",
        "canonical-order-v2-test-summary.json",
        "enforcement-boundary-v3-test-summary.json",
        "enforcement-boundary-v4-repair-test-summary.json",
        "failure-precedence-candidate-ps51-test-summary.json",
        "failure-precedence-candidate-currentps-test-summary.json",
        "failure-precedence-native-ps51-parser-summary.json",
    ]
    test_root = PROJECT / "Research/Verification/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1"
    failed_tests = []
    for name in test_summaries:
        summary = read_json(test_root / name)
        if summary.get("passed") is not True:
            failed_tests.append(name)
    check("all-validation-only-test-summaries-pass", not failed_tests, failed_tests)

    inventory = read_json(PROJECT / "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-telemetry-inventory.json")
    check("memory-evaluation-cardinality", inventory.get("memoryEvaluationCount") == 3736, inventory.get("memoryEvaluationCount"))
    check("memory-evaluations-all-valid", inventory.get("validMemoryEvaluationCount") == 3736 and inventory.get("invalidMemoryEvaluationCount") == 0, None)
    check("complete-block-cardinality", inventory.get("completedBlockProcessCount") == 933 and inventory.get("representedBlockCount") == 934, None)
    check("complete-sample-cardinality", inventory.get("completedSampleCount") == 3732, inventory.get("completedSampleCount"))

    boundary = read_json(output_root / "memory-enforcement-boundary-diagnostic.json")
    check("first-crossing-position-one", boundary["firstObservedNativeThresholdCrossing"]["position"] == 1, boundary["firstObservedNativeThresholdCrossing"])
    check("final-enforcement-position-four", boundary["hardGateEnforcementPoint"]["position"] == 4, boundary["hardGateEnforcementPoint"])
    check("algorithm-cause-not-identifiable", boundary["identifiability"]["algorithmCause"] == "NOT-IDENTIFIABLE", boundary["identifiability"])

    check("stale-lock-absent", not (PROJECT / "Temp/UnityLockfile").exists(), None)
    check("attempt3-formal-root-absent", not (PROJECT / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").exists(), None)
    check("attempt3-execution-receipt-absent", not (PROJECT / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json").exists(), None)
    check("attempt2-raw-data-freeze-receipt-absent", not (failed_root / "raw-data-freeze-receipt.json").exists(), None)

    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-failure-diagnosis-final-validation-only-audit-v1",
        "completedAtUtc": args.timestamp,
        "passed": True,
        "passedCount": len(checks),
        "failedCount": 0,
        "checks": checks,
        "failedRoot": {
            "absolutePath": str(failed_root),
            "fileCount": len(records),
            "rawBytes": raw_bytes,
            "canonicalTreeSha256": tree,
            "allFilesReadOnly": True,
        },
        "unityInvoked": False,
        "formalAnalysisPerformed": False,
        "attempt3Created": False,
        "gate14RStarted": False,
    }
    CORE.atomic_write_json(Path(args.output).resolve(), result)
    print(json.dumps({"passed": True, "passedCount": len(checks), "failedRootTreeSha256": tree}, sort_keys=True))


if __name__ == "__main__":
    main()
