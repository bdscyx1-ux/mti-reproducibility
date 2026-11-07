#!/usr/bin/env python3
"""Fail-closed final validation audit for Gate 13R-PR2-MP2.

This script reads only validation/upstream evidence and creates one audit file.
It never starts Unity or creates a formal root, receipt, status, or sample.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def binding(project: Path, relative: str) -> dict[str, Any]:
    path = project / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"relativePath": relative, "rawBytes": path.stat().st_size, "sha256": sha256_file(path)}


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13r-pr2-mp2-final-audit-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--attempt-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    attempt = Path(args.attempt_root).resolve()
    output = Path(args.output).resolve()
    require(attempt == (project / "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4").resolve(), "ATTEMPT-ROOT-IDENTITY")

    static = read_json(attempt / "static-unit-determinism-summary.json")
    self_test = read_json(attempt / "unity-memory-policy-self-test.summary.json")
    telemetry = read_json(attempt / "telemetry-probe.summary.json")
    post_audit = read_json(attempt / "post-validation-frozen-input-audit.json")
    block_names = ("positive-le128", "negative-native-eq256", "negative-telemetry", "negative-persistence")
    blocks = {name: read_json(attempt / "blocks" / f"{name}.summary.json") for name in block_names}

    require(static.get("passed") is True and static.get("testCount") == static.get("passedTestCount") == 69, "STATIC-69-OF-69")
    static_checks = {item["id"]: item.get("passed") for item in static.get("checks", [])}
    for check_id in (
        "schedule-process-cardinality", "overlay-process-cardinality", "scenario-cardinality", "campaign-cardinality",
        "schedule-overlay-one-to-one", "run-id-cardinality", "matched-superblock-cardinality", "heterogeneous-abba-record-quota",
        "two-stage-valid-transition", "two-stage-analysis-cannot-trigger-acquisition", "wrapper-role-specific-lock-acceptance",
        "wrapper-positive-lock-not-relaxed", "formal-attempt3-root-absent", "formal-attempt3-receipt-absent",
    ):
        require(static_checks.get(check_id) is True, f"STATIC-CHECK-{check_id}")
    require(self_test.get("passed") is True and self_test.get("fixtureCount") == self_test.get("fixturePassedCount") == 22, "UNITY-MEMORY-SELFTEST-22")
    require(self_test.get("telemetryValidationFixtureCount") == self_test.get("telemetryValidationPassedFixtureCount") == 8, "UNITY-TELEMETRY-SELFTEST-8")
    require(telemetry.get("passed") is True and telemetry.get("licenseSerialAssigned") is True, "PSAPI-CIM-TELEMETRY")
    require(telemetry.get("noValidLicenseError") is False and telemetry.get("inactiveHeadlessLicenseError") is False, "UNITY-LICENSE")
    expected = {
        "positive-le128": ("Pass", "natural-lock-absence"),
        "negative-native-eq256": ("NativeHard", "controlled-expected-negative-cleanup"),
        "negative-telemetry": ("TelemetryFailure", "controlled-expected-negative-cleanup"),
        "negative-persistence": ("PersistenceFailure", "controlled-expected-negative-cleanup"),
    }
    for name, (outcome, lock_mode) in expected.items():
        value = blocks[name]
        require(value.get("passed") is True and value.get("expectedOutcome") == outcome, f"BLOCK-{name}-OUTCOME")
        require(value.get("lockHygieneMode") == lock_mode and value.get("lockHygieneModeAccepted") is True, f"BLOCK-{name}-LOCK")
        require(value.get("formalCampaign") is False and value.get("validationOnly") is True, f"BLOCK-{name}-AUTHORIZATION")
    require(post_audit.get("passed") is True, "FROZEN-INPUT-POST-AUDIT")
    require(post_audit["pilotV2Raw"]["canonicalTreeSha256"] == "13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93", "MP1-V2-RAW-TREE")
    require(post_audit["formalAttempt2"]["canonicalTreeSha256"] == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e", "FORMAL-ATTEMPT2-TREE")
    require(post_audit["pilotV1"]["canonicalTreeSha256"] == "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265", "MP1-V1-TREE")

    formal_root = project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3"
    formal_receipt = project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
    formal_status = project / "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"
    require(not formal_root.exists(), "FORMAL-ATTEMPT3-ROOT-MUST-BE-ABSENT")
    require(not formal_receipt.exists(), "FORMAL-ATTEMPT3-RECEIPT-MUST-BE-ABSENT")
    require(not formal_status.exists(), "FORMAL-ATTEMPT3-STATUS-MUST-BE-ABSENT")
    require(not (project / "Temp/UnityLockfile").exists(), "UNITY-LOCK-MUST-BE-ABSENT")

    active_relatives = (
        "Research/Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json",
        "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json",
        "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json",
        "Research/Gate13R_PR2_MP2_Provenance.v4.json",
        "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1",
        "Research/New-Gate13RPR2MP2BlockPlanV4.py",
        "Research/Gate13RPR2MP2MemoryPolicyV2.psm1",
        "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs",
    )
    failed_relatives = tuple(
        f"Research/Verification/Gate13R_PR2_MP2/v1/attempt-{index}/{name}"
        for index in (1, 2, 3)
        for name in ("failure-receipt.json", "checkpoint.json", "partial-output-manifest.json")
    )
    result = {
        "schemaVersion": 1,
        "auditKind": "gate13r-pr2-mp2-nonexecuting-final-validation-audit-v1",
        "capturedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "statusTokens": [
            "MP2-POLICY-FROZEN", "FORMAL-ATTEMPT3-CANDIDATE-IMPLEMENTED", "VALIDATION-ONLY-PASSED",
            "TWO-STAGE-COMMIT-PRESERVED", "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
        ],
        "validation": {
            "static": binding(project, attempt.relative_to(project).as_posix() + "/static-unit-determinism-summary.json"),
            "memorySelfTest": binding(project, attempt.relative_to(project).as_posix() + "/unity-memory-policy-self-test.summary.json"),
            "telemetry": binding(project, attempt.relative_to(project).as_posix() + "/telemetry-probe.summary.json"),
            "blocks": {name: binding(project, attempt.relative_to(project).as_posix() + f"/blocks/{name}.summary.json") for name in block_names},
            "postFrozenInputAudit": binding(project, attempt.relative_to(project).as_posix() + "/post-validation-frozen-input-audit.json"),
        },
        "activeArtifacts": {relative: binding(project, relative) for relative in active_relatives},
        "preservedFailedAttempts": {relative: binding(project, relative) for relative in failed_relatives},
        "cardinality": {"canonicalScenarios": 53, "campaigns": 74, "processes": 3552, "samples": 10176, "matchedSuperblocks": 1008},
        "memoryPolicy": {
            "policyId": "gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1",
            "tierLe128": {"advisoryBytes": 536870912, "hardBytes": 671088640},
            "tierEq256": {"advisoryBytes": 671088640, "hardBytes": 805306368},
            "managedAlertBytes": 134217728,
            "managedSampleAndBlockEmergencyBytes": 268435456,
            "hostAbsoluteNativeEmergencyBytes": 4294967296,
            "hostRelativeNativeGrowthEmergencyBytes": 2147483648,
            "hostAvailablePhysicalMemoryFloorBytes": 8589934592,
            "crossingAttribution": "WHOLE-BLOCK-PROCESS",
        },
        "formalAttempt3": {"rootExists": False, "receiptExists": False, "statusExists": False, "measuredCampaignExecuted": False},
        "formalStatisticalAnalysisExecuted": False,
        "gate14RExecuted": False,
        "passed": True,
    }
    atomic_create(output, result)
    print(json.dumps({"passed": True, "output": str(output), "sha256": sha256_file(output)}, sort_keys=True))


if __name__ == "__main__":
    main()
