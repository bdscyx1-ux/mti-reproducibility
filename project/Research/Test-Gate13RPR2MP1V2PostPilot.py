#!/usr/bin/env python3
"""Validation-only terminal audit for Gate 13R-PR2-MP1 attempt 2 / v2."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT = Path(r"H:\DDM_Final_Project")
RESEARCH = PROJECT / "Research"

EXPECTED_HASHES = {
    "Gate13R_PR2_MP1_Provenance.v2_4.json": "dc0c48e38db09d8d96e62e0b30642e0ec93a95aaa672ed253f5fb9affffdd6fd",
    "Gate13R_PR2_MP1_PrePilot_Final_Audit.v2.json": "ff9f546c341650f7b01783fb87158f20025fe787fb1a118d7d0c1a1138034067",
    "Gate13R_PR2_MP1_PrePilot_Readiness_Checkpoint.v2.json": "2d38fe1bd892c65547e406e663f1b24fc33dab6a6d0f838d081796bed84670ae",
    "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-execution-receipt.json": "afcf84f30f32691047b5ec1ff9bec78fb98802d02de090305437e9154cb78a69",
    "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-checkpoint.json": "c0a4ae0fa9bdeea82892aa0c2f1985959d77b46d988786a860d1b42612057ecd",
    "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-raw-freeze-receipt.json": "f5851d2b47a7a77323dba6388df0c06bbbeb9db5b6dfc6f67a92dc79acd0c050",
    "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-raw-tree-manifest.json": "3f9ae6c969c8ff6e92a0c3c694613beb95b4bde99541a666d83837d301437ddf",
    "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-raw-execution-manifest.json": "b54766969f374346d774ba06735d3ab6627642f43deb81dc76ec7f54f4088980",
    "Analysis/Gate13R_PR2_MP1/v2/attempt-1/stage-separated-memory-analysis.json": "9676878b0cc88fa4b7230016c55e63ec2c42940a214c8c3eff245ce16d78f119",
    "Analysis/Gate13R_PR2_MP1/v2/attempt-1/memory-policy-decision-matrix.json": "05bcfa7324ba7afcef8cfba081f8407431144d932007bdfeb09a2b0bd2cc2441",
    "Analysis/Gate13R_PR2_MP1/v2/attempt-1/evidence-manifest.json": "29de1d6df9b12f8ede92f56914cb6cabc9f7a6cc246389d78de097c0bed990eb",
    "Gate13R_PR2_MP1_v2_PostPilot_Frozen_Root_Audit.v2.json": "40566cbc17d3b66160957ff72e488fa17c4ffaecbc163cc1feff39f1e52eb69e",
    "Gate13R_PR2_MP1_v2_Memory_Policy_Recommendation.v1.json": "90661dc14db20bf233c50395fa1bc41ae653bc673034b6e62c6e226963217e7a",
    "Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json": "7d6e028197c45d0e989a34268961a97a97e9ea50bd96008fd31b556eca0601cf",
    "Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.md": "c421c9b75b0bdfdf7c6a707909493c14029d840579486646acf0f300ec1cf878",
    "Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md": "063476899e32f439b0936c4da100219f86b24b17e42df09a0ab4c2cb12ef8215",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def readonly(path: Path) -> bool:
    return bool(path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY)


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-final-audit-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def unity_process_count() -> int:
    command = "@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count"
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return int(completed.stdout.strip() or "0")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: Any = None) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    actual_hashes: dict[str, str] = {}
    for relative, expected in EXPECTED_HASHES.items():
        path = RESEARCH / relative
        actual = sha256_file(path) if path.is_file() else "MISSING"
        actual_hashes[relative] = actual
        check(f"sha256:{relative}", actual == expected, {"expected": expected, "actual": actual})

    checkpoint = read_json(RESEARCH / "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-checkpoint.json")
    freeze = read_json(RESEARCH / "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-raw-freeze-receipt.json")
    analysis = read_json(RESEARCH / "Analysis/Gate13R_PR2_MP1/v2/attempt-1/stage-separated-memory-analysis.json")
    matrix = read_json(RESEARCH / "Analysis/Gate13R_PR2_MP1/v2/attempt-1/memory-policy-decision-matrix.json")
    evidence = read_json(RESEARCH / "Analysis/Gate13R_PR2_MP1/v2/attempt-1/evidence-manifest.json")
    post_audit = read_json(RESEARCH / "Gate13R_PR2_MP1_v2_PostPilot_Frozen_Root_Audit.v2.json")
    recommendation = read_json(RESEARCH / "Gate13R_PR2_MP1_v2_Memory_Policy_Recommendation.v1.json")
    readiness = read_json(RESEARCH / "Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json")

    check("checkpoint-phase-a-state", checkpoint.get("status") == "PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE")
    check("checkpoint-cardinality", checkpoint.get("completedBlockCount") == 96 and checkpoint.get("completedSampleCount") == 384)
    check("checkpoint-raw-tree", checkpoint.get("rawTreeSha256") == "13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93")
    check("checkpoint-no-retry-resume-topup-merge", checkpoint.get("automaticRetryAuthorized") is False and checkpoint.get("automaticResumeAuthorized") is False and checkpoint.get("topUpAuthorized") is False and checkpoint.get("partialMergeAuthorized") is False)
    check("raw-freeze-cardinality", freeze.get("rawFileCount") == 3360 and freeze.get("rawBytes") == 2607785161)
    check("raw-freeze-readonly", freeze.get("allRawFilesReadOnly") is True)
    check("raw-freeze-no-unity-rerun-on-analysis-failure", freeze.get("ordinaryAnalysisFailureMayRerunUnity") is False)

    raw_files = [path for path in (RESEARCH / "PilotRuns/Gate13R_PR2_MemoryPolicy/v2/raw").rglob("*") if path.is_file()]
    check("raw-files-current-cardinality", len(raw_files) == 3360 and sum(path.stat().st_size for path in raw_files) == 2607785161)
    check("raw-files-current-readonly", len(raw_files) == 3360 and all(readonly(path) for path in raw_files))

    check("analysis-cardinality", analysis.get("blockCount") == 96 and analysis.get("sampleCount") == 384 and analysis.get("stageRecordCount") == 1824)
    check("analysis-raw-tree", analysis.get("rawTreeSha256") == checkpoint.get("rawTreeSha256"))
    check("analysis-scientific-boundary", analysis.get("formalInferencePerformed") is False and analysis.get("gate14RPerformed") is False)
    check("analysis-evidence-readonly", evidence.get("rawAccess") == "READ-ONLY" and evidence.get("rawTreeSha256Before") == evidence.get("rawTreeSha256After") == checkpoint.get("rawTreeSha256"))
    check("analysis-no-unity", evidence.get("unityInvoked") is False)
    analysis_files = [path for path in (RESEARCH / "Analysis/Gate13R_PR2_MP1/v2/attempt-1").rglob("*") if path.is_file()]
    check("analysis-root-readonly", len(analysis_files) == 3 and all(readonly(path) for path in analysis_files))
    check("decision-matrix-unfrozen", matrix.get("candidateStatus") == "UNFROZEN / REQUIRES-SEPARATE-FORMAL-ATTEMPT3-AUTHORIZATION" and matrix.get("formalConfigModified") is False and matrix.get("formalAttempt3Started") is False)
    check("postpilot-integrity-passed", post_audit.get("passed") is True and all(post_audit.get("checks", {}).values()))
    check("pilot-v1-identity", post_audit.get("pilotV1", {}).get("canonicalTreeSha256") == "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265")
    check("formal-attempt2-identity", post_audit.get("formalAttempt2", {}).get("canonicalTreeSha256") == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e")

    policy = recommendation.get("candidatePolicy", {})
    check("recommendation-unfrozen", recommendation.get("status") == "RECOMMENDED-BUT-UNFROZEN / REQUIRES-SEPARATE-MP2-NONEXECUTING-AUTHORIZATION" and policy.get("selectionStatus") == "RECOMMENDED-BUT-UNFROZEN")
    check("native-advisory-exact", policy.get("nativeAdvisoryEnvelope") == [
        {"condition": "maxGridDimension <= 128", "thresholdMiB": 512, "thresholdBytes": 536870912},
        {"condition": "maxGridDimension == 256", "thresholdMiB": 640, "thresholdBytes": 671088640},
    ])
    check("native-hard-exact", policy.get("nativeHardEligibilityCeiling") == [
        {"condition": "maxGridDimension <= 128", "thresholdMiB": 640, "thresholdBytes": 671088640},
        {"condition": "maxGridDimension == 256", "thresholdMiB": 768, "thresholdBytes": 805306368},
    ])
    check("managed-policy-retained", policy.get("retainedManagedPolicy", {}).get("sampleAlertBytes") == 134217728 and policy.get("retainedManagedPolicy", {}).get("sampleEmergencyBytes") == 268435456 and policy.get("retainedManagedPolicy", {}).get("blockEmergencyBytes") == 268435456)
    check("host-safety-retained", policy.get("hostSafetyPolicy", {}).get("absoluteWorkingSetOrPrivateMemoryEmergencyGiB") == 4 and policy.get("hostSafetyPolicy", {}).get("relativeWorkingSetOrPrivateGrowthEmergencyGiB") == 2 and policy.get("hostSafetyPolicy", {}).get("availablePhysicalMemoryFloorGiB") == 8)
    check("recommendation-not-formal", recommendation.get("scientificBoundary", {}).get("algorithmSuperiorityInference") is False and recommendation.get("scientificBoundary", {}).get("formalEffectInference") is False and recommendation.get("authorizationBoundary", {}).get("policyFrozenForFormalUse") is False)

    required_tokens = {
        "MP1-V2-PILOT-PASSED",
        "RAW-DATA-COMPLETE",
        "RAW-IMMUTABLE",
        "DIAGNOSTIC-ANALYSIS-ATTEMPT1-PASSED",
        "FORWARD-MEMORY-POLICY-RECOMMENDED-BUT-UNFROZEN",
        "MP2-NONEXECUTING-AUTHORIZATION-REQUIRED",
        "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
        "FORMAL-ANALYSIS-NOT-AUTHORIZED",
        "GATE14R-NOT-AUTHORIZED",
    }
    check("readiness-status-tokens", required_tokens.issubset(set(readiness.get("statusTokens", []))))
    check("readiness-boundary", readiness.get("authorizationBoundary") == {
        "pilotV1RetryResumeTopUpMergeAuthorized": False,
        "newUnityPilotAuthorized": False,
        "formalAttempt3Authorized": False,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    })

    plan_text = (RESEARCH / "Overall_Project_Plan.md").read_text(encoding="utf-8-sig")
    checkpoint_text = (RESEARCH / "Next_Session_Checkpoint.md").read_text(encoding="utf-8-sig")
    prompt_text = (RESEARCH / "Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md").read_text(encoding="utf-8-sig")
    check("overall-plan-updated", "版本：4.8" in plan_text and "MP1 attempt 2 / v2" in plan_text and "Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md" in plan_text)
    check("next-checkpoint-updated", "MP1-V2-PILOT-PASSED" in checkpoint_text and "13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93" in checkpoint_text)
    check("next-prompt-nonexecuting-boundary", "不授权 Gate 13R-PR2 formal attempt 3 measured campaign" in prompt_text and "不得创建 `Research/FormalRuns/Gate13R_RQAligned_S48H48/v3`" in prompt_text)

    check("formal-attempt3-root-absent", not (RESEARCH / "FormalRuns/Gate13R_RQAligned_S48H48/v3").exists())
    check("formal-attempt3-receipt-absent", not (RESEARCH / "Gate13R_PR2_Formal_Execution_Receipt.v3.json").exists())
    check("unity-lock-absent", not (PROJECT / "Temp/UnityLockfile").exists())
    running_unity = unity_process_count()
    check("unity-process-count-zero", running_unity == 0, running_unity)

    passed = all(item["passed"] for item in checks)
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-mp1-v2-postpilot-terminal-validation-summary-v1",
        "capturedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "labels": ["VALIDATION-ONLY", "NON-FORMAL", "NO-UNITY-LAUNCH", "FORMAL-ATTEMPT3-NOT-AUTHORIZED"],
        "assertionCount": len(checks),
        "passedAssertionCount": sum(1 for item in checks if item["passed"]),
        "failedAssertionCount": sum(1 for item in checks if not item["passed"]),
        "checks": checks,
        "keyFileSha256": actual_hashes,
        "dynamicFileSha256": {
            "Overall_Project_Plan.md": sha256_file(RESEARCH / "Overall_Project_Plan.md"),
            "Next_Session_Checkpoint.md": sha256_file(RESEARCH / "Next_Session_Checkpoint.md"),
            "Gate13R_PR2_MP1_v2_Run_Passport.md": sha256_file(RESEARCH / "Gate13R_PR2_MP1_v2_Run_Passport.md"),
            "Gate13R_PR2_MP1_v2_Run_Passport_run_ledger.yaml": sha256_file(RESEARCH / "Gate13R_PR2_MP1_v2_Run_Passport_run_ledger.yaml"),
        },
        "formalAnalysisPerformed": False,
        "gate14RPerformed": False,
        "unityInvokedByThisAudit": False,
        "passed": passed,
    }
    output = Path(args.output).resolve()
    atomic_create(output, result)
    print(json.dumps({"passed": passed, "assertions": len(checks), "output": str(output)}, sort_keys=True))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
