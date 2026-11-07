#!/usr/bin/env python3
"""Create the Gate 13R-PR2-MP2 non-executing readiness checkpoint."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any


SAVED_UTC = "2026-10-09T06:36:00.0000000Z"
SAVED_SHANGHAI = "2026-10-09T14:36:00+08:00"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def binding(project: Path, relative: str) -> dict[str, Any]:
    path = project / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"relativePath": relative, "rawBytes": path.stat().st_size, "sha256": sha256_file(path)}


def atomic_create(path: Path, data: bytes) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13r-pr2-mp2-readiness-", dir=str(path.parent))
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


def stable_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    formal_root = project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3"
    formal_receipt = project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
    formal_status = project / "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"
    if formal_root.exists() or formal_receipt.exists() or formal_status.exists() or (project / "Temp/UnityLockfile").exists():
        raise ValueError("FORMAL-ATTEMPT3-OR-UNITY-LOCK-MUST-REMAIN-ABSENT")

    attempt_audit_rel = "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/final-validation-audit.json"
    attempt_audit = json.loads((project / attempt_audit_rel).read_text(encoding="utf-8-sig"))
    if attempt_audit.get("passed") is not True:
        raise ValueError("FINAL-VALIDATION-AUDIT-NOT-PASSED")

    main_audit_rel = "Research/Gate13R_PR2_MP2_Final_Validation_Audit.v1.json"
    main_audit_path = project / main_audit_rel
    atomic_create(main_audit_path, (project / attempt_audit_rel).read_bytes())

    active_relatives = (
        "Research/Gate13R_PR2_MP2_Authorization.v1.json",
        "Research/Gate13R_PR2_MP2_PreWrite_Preservation_Audit.v1.json",
        "Research/Gate13R_PR2_MP2_Specification.v1.md",
        "Research/Gate13R_PR2_MP2_Test_Design.v1.md",
        "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json",
        "Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json",
        "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json",
        "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl",
        "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json",
        "Research/Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json",
        "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json",
        "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json",
        "Research/Gate13R_PR2_MP2_Provenance.v4.json",
        "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1",
        "Research/New-Gate13RPR2MP2BlockPlanV4.py",
        "Research/Gate13RPR2MP2MemoryPolicyV2.psm1",
        "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs",
        main_audit_rel,
        "Research/Overall_Project_Plan.md",
        "Research/Next_Session_Checkpoint.md",
    )
    validation_relatives = (
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/static-unit-determinism-summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/unity-memory-policy-self-test.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/telemetry-probe.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/blocks/positive-le128.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/blocks/negative-native-eq256.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/blocks/negative-telemetry.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/blocks/negative-persistence.summary.json",
        "Research/Verification/Gate13R_PR2_MP2/v1/attempt-4/post-validation-frozen-input-audit.json",
        attempt_audit_rel,
    )
    failed_attempts = {
        f"attempt-{index}": {
            name: binding(project, f"Research/Verification/Gate13R_PR2_MP2/v1/attempt-{index}/{name}")
            for name in ("failure-receipt.json", "checkpoint.json", "partial-output-manifest.json")
        }
        for index in (1, 2, 3)
    }
    checkpoint = {
        "schemaVersion": 1,
        "checkpointId": "gate13r-pr2-mp2-nonexecuting-readiness-v1",
        "savedAtUtc": SAVED_UTC,
        "savedAtAsiaShanghai": SAVED_SHANGHAI,
        "statusTokens": [
            "GATE13R-PR2-MP2-PASSED",
            "POLICY-FROZEN-PROSPECTIVE",
            "ACTIVE-CANDIDATE-V4",
            "VALIDATION-ATTEMPT4-PASSED",
            "S48-H48-SCHEDULE-UNCHANGED",
            "TWO-STAGE-COMMIT-PRESERVED",
            "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
            "FORMAL-ROOT-ABSENT",
            "FORMAL-RECEIPT-ABSENT",
            "FORMAL-ANALYSIS-NOT-AUTHORIZED",
            "GATE14R-NOT-AUTHORIZED",
        ],
        "activeArtifacts": {relative: binding(project, relative) for relative in active_relatives},
        "validationEvidence": {relative: binding(project, relative) for relative in validation_relatives},
        "preservedFailedValidationAttempts": failed_attempts,
        "formalDesign": {
            "designId": "gate13r-pr2-rq-aligned-s48-h48-v1",
            "campaignCount": 74,
            "sharedCampaignCount": 32,
            "blocksPerSharedCampaign": 48,
            "heterogeneousScenarioCount": 21,
            "matchedSuperblocksPerHeterogeneousScenario": 48,
            "matchedSuperblockCount": 1008,
            "processCount": 3552,
            "sampleCount": 10176,
            "maximumConcurrentUnityEditors": 1,
            "schedule": binding(project, "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"),
            "scheduleManifest": binding(project, "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json"),
        },
        "memoryPolicy": attempt_audit["memoryPolicy"],
        "validationSummary": {
            "staticPassed": "69/69",
            "memoryPolicyFixturesPassed": "22/22",
            "telemetrySequenceFixturesPassed": "8/8",
            "independentPsapiCimProbePassed": True,
            "positiveCompleteBlockPassed": True,
            "expectedNegativeNativeHardPassed": True,
            "expectedNegativeTelemetryPassed": True,
            "expectedNegativePersistencePassed": True,
            "frozenInputPostAuditPassed": True,
        },
        "twoStageCommit": {
            "phaseARequiredState": ["RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"],
            "phaseBReadOnly": True,
            "ordinaryAnalysisFailureMayTriggerUnityRerun": False,
            "rawContractViolationRequiresUserDecision": True,
        },
        "authorizationBoundary": {
            "formalAttempt3RootCreated": False,
            "formalAttempt3ExecutionReceiptCreated": False,
            "formalAttempt3StatusCreated": False,
            "formalAttempt3MeasuredCampaignExecuted": False,
            "formalStatisticalAnalysisExecuted": False,
            "gate14RExecuted": False,
            "nextAuthorizationPromptRelativePath": "Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.md",
        },
        "nextAction": "WAIT-FOR-SEPARATE-GATE13R-PR2-FORMAL-ATTEMPT3-AUTHORIZATION",
        "passed": True,
    }
    json_rel = "Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json"
    md_rel = "Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.md"
    json_bytes = stable_json(checkpoint)
    atomic_create(project / json_rel, json_bytes)
    candidate_hash = checkpoint["activeArtifacts"]["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"]["sha256"]
    adapter_hash = checkpoint["activeArtifacts"]["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json"]["sha256"]
    provenance_hash = checkpoint["activeArtifacts"]["Research/Gate13R_PR2_MP2_Provenance.v4.json"]["sha256"]
    audit_hash = checkpoint["activeArtifacts"][main_audit_rel]["sha256"]
    markdown = f"""# Gate 13R-PR2-MP2 non-executing readiness checkpoint

状态：`GATE13R-PR2-MP2-PASSED / POLICY-FROZEN-PROSPECTIVE / ACTIVE-CANDIDATE-V4 / FORMAL-ATTEMPT3-NOT-AUTHORIZED`

MP2 已完成前瞻性 memory-policy 冻结、formal-attempt-3 candidate config/adapter 和 validation-only readiness。它没有创建 formal root、execution receipt、status 或 measured sample，也没有运行正式统计分析或 Gate 14R。

## 活动身份

- candidate config SHA-256：`{candidate_hash}`；
- candidate adapter SHA-256：`{adapter_hash}`；
- provenance SHA-256：`{provenance_hash}`；
- final validation audit SHA-256：`{audit_hash}`；
- active schedule SHA-256：`df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae`。

## 冻结 policy

- max grid `<=128`：512 MiB advisory / 640 MiB hard；
- max grid `==256`：640 MiB advisory / 768 MiB hard；
- managed cleanup：128 MiB alert / 256 MiB sample+block emergency；
- host：4 GiB absolute / 2 GiB relative / 8 GiB available floor；
- native crossing：whole-block/process attribution；hard crossing 持久化后禁止下一个 block。

## 验证

- static/unit/deterministic 69/69；
- Unity threshold fixtures 22/22；telemetry sequence fixtures 8/8；
- PSAPI/CIM telemetry probe passed；
- positive complete block passed；
- native-hard、telemetry、persistence 三个 expected-negative blocks passed；
- two-stage raw/analysis commit passed；
- frozen input post-audit passed；
- attempts 1–3 的失败证据均独立保存。

## 停止边界

formal attempt 3 仍需用户单独授权。授权前不得创建 `Research/FormalRuns/Gate13R_RQAligned_S48H48/v3`、`Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json` 或 execution status，不得启动 measured Unity block、正式统计分析或 Gate 14R。

下一授权模板：`Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.md`。
"""
    atomic_create(project / md_rel, markdown.encode("utf-8"))
    print(json.dumps({"passed": True, "json": {"path": json_rel, "sha256": sha256_file(project / json_rel)}, "markdown": {"path": md_rel, "sha256": sha256_file(project / md_rel)}, "mainAudit": {"path": main_audit_rel, "sha256": sha256_file(main_audit_path)}}, sort_keys=True))


if __name__ == "__main__":
    main()
