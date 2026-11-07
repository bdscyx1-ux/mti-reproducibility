#!/usr/bin/env python3
"""Freeze the repaired Gate14Re MQ v2.4 design/implementation/readiness chain."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ARTIFACTS = [
    ("user-authorization", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/user-authorization-receipt.v2.json"),
    ("authorized-scientific-design", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/formal-mq-authorized-design.v2.json"),
    ("scientific-rule-freeze-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/terminal-receipt.v2.json"),
    ("identity-blind-power-result", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-result.v2.json"),
    ("identity-blind-power-validation", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/post-execution-validation-receipt.v2.json"),
    ("power-selection-seal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-selection-seal-receipt.v2.json"),
    ("power-attempt-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/terminal-receipt.v2.json"),
    ("scientific-and-analysis-contract", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-scientific-and-analysis-contract.v2.json"),
    ("resource-budget", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-resource-budget.v2.json"),
    ("fairness-and-topology-binding", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/fairness-and-topology-binding.v2.json"),
    ("execution-contract", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-execution-contract.v2.json"),
    ("implementation-manifest", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-implementation-manifest.v2_4.json"),
    ("repaired-collection-supervisor", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_2.ps1"),
    ("superseded-collection-supervisor", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_1.ps1"),
    ("historical-collection-supervisor", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_0.ps1"),
    ("prior-repair-user-authorization", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-control-corrigendum-v2_1-attempt-001/user-authorization-receipt.v2_1.json"),
    ("prior-supervisor-control-fix-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-control-corrigendum-v2_1-attempt-001/supervisor-control-fix-receipt.v2_1.json"),
    ("repair-user-authorization", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-process-identity-corrigendum-v2_2-attempt-001/user-authorization-receipt.v2_2.json"),
    ("process-identity-fix-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-process-identity-corrigendum-v2_2-attempt-001/process-identity-fix-receipt.v2_2.json"),
    ("failed-collection-attempt-001-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/terminal-receipt.v2.json"),
    ("failed-collection-attempt-001-failure", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/failure-receipt.v2.json"),
    ("failed-collection-attempt-001-seal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/failure-seal-manifest.v2.json"),
    ("failed-collection-attempt-002-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-002/terminal-receipt.v2.json"),
    ("failed-collection-attempt-002-failure", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-002/failure-receipt.v2.json"),
    ("failed-collection-attempt-002-seal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-002/failure-seal-manifest.v2.json"),
    ("formal-schedule", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule.v2.jsonl"),
    ("formal-schedule-summary", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule-summary.v2.json"),
    ("formal-block-input-assignments", "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-block-input-assignments.v2.jsonl"),
    ("formal-input-source-manifest", "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-input-source-manifest.v2.json"),
    ("opaque-algorithm-identity-map", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/opaque-algorithm-identity-map.v2.json"),
    ("algorithm-free-compile-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/compile-readiness-v2_2-attempt-001/compile-terminal.v2.json"),
    ("algorithm-free-compile-log", "Research/Verification/Gate14Re-MQ-CFF-IDFF/compile-readiness-v2_2-attempt-001/unity-compile.log"),
    ("attempt-001-invalidation-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-freeze-v2-corrigendum-attempt-001/invalidation-receipt.v2.json"),
    ("attempt-002-supersession-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-freeze-v2-supersession-attempt-002/supersession-receipt.v2.json"),
    ("prelaunch-attempt-003-failure-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/prelaunch-readiness-v2-attempt-003/failure-receipt.v2.json"),
    ("prelaunch-attempt-003-unity-log", "Research/Verification/Gate14Re-MQ-CFF-IDFF/prelaunch-readiness-v2-attempt-003/unity-readiness.log"),
    ("independent-static-validation", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-implementation-static-validation-v2_2-attempt-001/validation-receipt.v2.json"),
    ("algorithm-free-prelaunch-readiness", "Research/Verification/Gate14Re-MQ-CFF-IDFF/prelaunch-readiness-v2_2-attempt-001/readiness-terminal.v2.json"),
    ("algorithm-free-prelaunch-log", "Research/Verification/Gate14Re-MQ-CFF-IDFF/prelaunch-readiness-v2_2-attempt-001/unity-readiness.log"),
    ("fresh-target-readiness-source", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalReadinessV2_1.cs"),
    ("fresh-target-readiness-meta", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalReadinessV2_1.cs.meta"),
    ("finalization-tool", "Research/Gate14Re-MQ-CFF-IDFF/Tools/v2/finalize_formal_readiness_v2_2.py"),
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"Expected JSON object: {path}")
    return value


def write_new(path: Path, value: dict[str, Any]) -> None:
    require(not path.exists(), f"Refusing to overwrite evidence: {path}")
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    output_root = Path(args.output_root).resolve()
    require(root.is_dir(), "Project root is missing")
    require(not output_root.exists(), "Final freeze root must be new")
    try:
        output_root.relative_to(root)
    except ValueError as exc:
        raise RuntimeError("Final freeze root escapes project root") from exc
    require((root / "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/attempt-002").is_dir(), "Sealed attempt-002 measured root is missing")
    require(not (root / "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/attempt-003").exists(), "Successor attempt-003 measured root already exists")

    rows: list[dict[str, Any]] = []
    files: dict[str, Path] = {}
    for role, relative in ARTIFACTS:
        path = (root / relative).resolve()
        require(path.is_file(), f"Freeze artifact is missing: {relative}")
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise RuntimeError(f"Freeze artifact escapes project root: {relative}") from exc
        files[role] = path
        rows.append({"role": role, "relativePath": relative, "bytes": path.stat().st_size, "sha256": sha256(path)})

    implementation = load_json(files["implementation-manifest"])
    require(implementation.get("implementationRevision") == "v2.4" and implementation.get("collectionSupervisorRevision") == "v2.2", "Repaired implementation revision mismatch")
    require(implementation.get("prospectiveRepair", {}).get("firstEligibleSuccessorAttempt") == 3, "Implementation manifest successor attempt mismatch")
    require(implementation.get("prospectiveRepair", {}).get("automaticSuccessorCollectionAuthorizedAfterAllGatesPass") is True, "Implementation manifest omits continuing collection authorization")

    repair_authorization = load_json(files["repair-user-authorization"])
    repair_receipt = load_json(files["process-identity-fix-receipt"])
    failed_collection_001 = load_json(files["failed-collection-attempt-001-terminal"])
    failed_collection_002 = load_json(files["failed-collection-attempt-002-terminal"])
    require(repair_authorization.get("status") == "AUTHORIZED_ALL_MINIMAL_PROSPECTIVE_TECHNICAL_REPAIRS_REFREEZE_AND_AUTOMATIC_SUCCESSOR_FORMAL_COLLECTION_UNTIL_COLLECTION_TERMINAL", "Repair authorization mismatch")
    require(repair_authorization.get("formalCollectionAuthorized") is True and repair_authorization.get("formalAnalysisAuthorized") is False and repair_authorization.get("firstEligibleSuccessorAttempt") == 3, "Repair authorization crosses collection/analysis boundary")
    require(repair_receipt.get("status") == "PASS_MINIMAL_PROSPECTIVE_PROCESS_IDENTITY_ACQUISITION_AND_FRESH_TARGET_READINESS_FIX", "Process-identity repair receipt mismatch")
    require(repair_receipt["supervisorRepair"]["previousSha256"] == sha256(files["superseded-collection-supervisor"]), "Old supervisor hash drift")
    require(repair_receipt["supervisorRepair"]["repairedSha256"] == sha256(files["repaired-collection-supervisor"]), "Repaired supervisor hash drift")
    require(repair_receipt["scope"]["scientificDesignChanged"] is False and repair_receipt["scope"]["scheduleChanged"] is False, "Repair changes scientific design or schedule")
    require(failed_collection_001.get("status") == "FAIL_CLOSED_SUPERVISOR_PREFLIGHT_NO_MEASURED_ROOT_NO_FORMAL_OBSERVATIONS" and failed_collection_001.get("attemptReusable") is False, "Failed collection attempt-001 disposition mismatch")
    require(failed_collection_002.get("status") == "FAIL_CLOSED_ORDINAL_0_PROCESS_IDENTITY_NO_COMPLETED_MEASURED_PROCESS_NO_FORMAL_OBSERVATIONS" and failed_collection_002.get("attemptReusable") is False, "Failed collection attempt-002 disposition mismatch")
    require(failed_collection_002.get("completedMeasuredUnityProcesses") == 0 and failed_collection_002.get("formalObservationsCreated") == 0, "Failed collection attempt-002 evidence boundary mismatch")

    compile_receipt = load_json(files["algorithm-free-compile-terminal"])
    require(compile_receipt.get("status") == "PASS_ALGORITHM_FREE_COMPILE_AND_BURST_COMPLETION_GUARDED", "Compile receipt is not PASS")
    require(compile_receipt.get("finalCompilationDone") is True and compile_receipt.get("algorithmsInstantiated") == 0, "Compile receipt boundary mismatch")
    require(compile_receipt.get("formalCollectionStarted") is False and compile_receipt.get("formalAnalysisStarted") is False, "Compile receipt reports execution")

    static_receipt = load_json(files["independent-static-validation"])
    require(static_receipt.get("status") == "PASS_INDEPENDENT_STATIC_VALIDATION_READY_FOR_ALGORITHM_FREE_READINESS", "Independent validation is not PASS")
    require(static_receipt["science"]["selectedB"] == 36 and static_receipt["schedule"]["rows"] == 864, "Independent validation cardinality mismatch")
    require(static_receipt["launcherRunnerInterface"]["status"] == "PASS_EXACT_SUPERVISOR_RUNNER_OUTPUT_TOPOLOGY_COMPATIBILITY", "Supervisor/runner output topology compatibility did not pass")
    require(static_receipt["launcherRunnerInterface"]["runnerMarkersChecked"] >= 5, "Runner launch-evidence markers are incomplete")
    require(static_receipt["launcherRunnerInterface"]["supervisorMarkersChecked"] >= 10, "Supervisor launch-evidence markers are incomplete")
    require(static_receipt["launcherRunnerInterface"]["supervisorProcessIdentityFix"] == {
        "status": "PASS_ONLY_GET_PROCESS_IDENTITY_CHANGED_WITH_BOUNDED_COMPLETE_IDENTITY_POLL",
        "changedFunctionBlocks": 1,
        "identityMarkersChecked": 8,
        "emptySetCountFixRetainedCallSites": 3,
        "unwrappedEmptySetCallSitesRemaining": 0,
        "allOtherSupervisorTextEquivalent": True,
        "previousSupervisorSha256": sha256(files["superseded-collection-supervisor"]),
        "repairedSupervisorSha256": sha256(files["repaired-collection-supervisor"]),
    }, "Static validation did not prove the minimal supervisor repair")
    require(static_receipt["launcherRunnerInterface"]["freshTargetReadinessFix"]["status"] == "PASS_EXPLICIT_SUCCESSOR_ROOT_MUST_BE_NEW_WITHIN_RESERVED_NAMESPACE", "Static validation did not prove the fresh-target readiness repair")
    require(static_receipt.get("formalCollectionStarted") is False and static_receipt.get("formalAnalysisStarted") is False, "Independent validation reports execution")

    readiness = load_json(files["algorithm-free-prelaunch-readiness"])
    require(readiness.get("status") == "PASS_ALGORITHM_FREE_PRELAUNCH_READINESS_FORMAL_MQ_NOT_STARTED", "Prelaunch readiness is not PASS")
    require(readiness["validation"] == {
        "scheduleRows": 864,
        "blockRows": 36,
        "sourceInputReferences": 576,
        "distinctSourceInputs": 108,
        "distinctStructuralCells": 36,
        "oracleCacheBindingsVerified": 576,
        "minimumConditionPositionCount": 1,
        "maximumConditionPositionCount": 2,
    }, "Prelaunch readiness validation summary mismatch")
    require(readiness.get("burstFinalCompilationDone") is True and readiness.get("algorithmsInstantiated") == 0 and readiness.get("measuredProcessesStarted") == 0, "Readiness compile/execution boundary mismatch")
    require(readiness.get("formalCollectionStarted") is False and readiness.get("formalAnalysisStarted") is False, "Readiness reports formal execution")
    require(readiness.get("separateCollectionAuthorizationRequired") is True, "Separate collection authorization gate missing")
    require(readiness["implementationManifest"]["sha256"] == sha256(files["implementation-manifest"]), "Readiness implementation-manifest binding mismatch")
    require(readiness.get("nextMeasuredRootRelativePath") == "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/attempt-003" and readiness.get("nextMeasuredRootWasAbsent") is True, "Readiness did not bind the fresh attempt-003 measured root")

    failed_prelaunch = load_json(files["prelaunch-attempt-003-failure-receipt"])
    require(failed_prelaunch.get("status") == "FAILED_BEFORE_READINESS_METHOD_ARGUMENT_VECTOR_CONSTRUCTION", "Attempt-003 failure disposition mismatch")
    require(failed_prelaunch.get("readinessMethodInvoked") is False and failed_prelaunch.get("formalCollectionStarted") is False, "Attempt-003 crossed the readiness/collection boundary")

    supersession = load_json(files["attempt-002-supersession-receipt"])
    require(supersession.get("status") == "ATTEMPT_002_PRESERVED_SUPERSEDED_BY_LAUNCH_EVIDENCE_HARDENING", "Attempt-002 supersession disposition mismatch")
    require(supersession["scope"]["scientificDesignChanged"] is False and supersession["scope"]["collectionWasStarted"] is False, "Attempt-002 supersession scope mismatch")

    power = load_json(files["identity-blind-power-result"])
    require(power.get("selectedB") == 36 and power.get("keySecondaryUsedForBSelection") is False, "Power-selection disposition mismatch")
    require(float(power["candidateResults"][0]["worstPrimaryWilson95Lower"]) >= 0.90, "B36 primary power lower bound below 0.90")
    require(power.get("sevenDayGateTriggered") is False, "Seven-day gate triggered")

    output_root.mkdir(parents=True)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    validation_path = output_root / "final-freeze-validation-receipt.v2.json"
    validation = {
        "schema": "gate14re-mq-formal-final-freeze-validation-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "PASS_FINAL_REPAIRED_IMPLEMENTATION_SCHEDULE_AND_PRELAUNCH_READINESS",
        "validatedAtUtc": now,
        "selectedB": 36,
        "freshUnityProcessesPlanned": 864,
        "matchedBlocks": 36,
        "lanesPerBlock": 16,
        "confirmatoryPrimaryFamily": ["P1", "P2", "P3", "P4"],
        "keySecondaryFamily": ["S1", "S2"],
        "keySecondaryFormerIds": {"S1": "P5", "S2": "P6"},
        "keySecondaryUsedForBSelection": False,
        "movementTransferSentinelIncluded": False,
        "allCorrectnessAndOracleHardGatesRetained": True,
        "implementationRevision": "v2.4",
        "collectionSupervisorRevision": "v2.2",
        "supervisorChangedFunctionBlocks": 1,
        "processIdentityPollTimeoutMilliseconds": 10000,
        "priorEmptySetFixRetainedCallSites": 3,
        "scientificDesignChangedByRepair": False,
        "scheduleChangedByRepair": False,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "sealedFailedAttempt002MeasuredRootExists": True,
        "nextAttempt003MeasuredRootExists": False,
        "separateCollectionLaunchAuthorizationRequired": True,
        "continuingUserAuthorizationSatisfiesLaunchApproval": True,
        "formalCollectionAttempt003Authorized": True,
    }
    write_new(validation_path, validation)
    rows.append({
        "role": "final-freeze-validation",
        "relativePath": validation_path.relative_to(root).as_posix(),
        "bytes": validation_path.stat().st_size,
        "sha256": sha256(validation_path),
    })

    manifest_path = output_root / "final-freeze-manifest.v2.json"
    manifest = {
        "schema": "gate14re-mq-formal-final-freeze-manifest-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_REPAIRED_IMPLEMENTATION_READY_AND_USER_AUTHORIZED_FOR_AUTOMATIC_FORMAL_MQ_COLLECTION_ATTEMPT_003",
        "artifactCount": len(rows),
        "artifacts": rows,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "createdAtUtc": now,
    }
    write_new(manifest_path, manifest)

    terminal_path = output_root / "terminal-receipt.v2.json"
    terminal = {
        "schema": "gate14re-mq-formal-design-implementation-readiness-terminal-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "PASS_REPAIRED_SUPERVISOR_V2_2_READY_AND_USER_AUTHORIZED_FOR_AUTOMATIC_FORMAL_MQ_COLLECTION_ATTEMPT_003",
        "completedAtUtc": now,
        "selectedB": 36,
        "freshUnityProcessesPlanned": 864,
        "conservativePlanningHours": 11.988586,
        "sevenDayGateTriggered": False,
        "implementationManifestSha256": sha256(files["implementation-manifest"]),
        "repairedSupervisorSha256": sha256(files["repaired-collection-supervisor"]),
        "supersededSupervisorSha256": sha256(files["superseded-collection-supervisor"]),
        "repairAuthorizationSha256": sha256(files["repair-user-authorization"]),
        "processIdentityFixReceiptSha256": sha256(files["process-identity-fix-receipt"]),
        "failedCollectionAttempt001TerminalSha256": sha256(files["failed-collection-attempt-001-terminal"]),
        "failedCollectionAttempt002TerminalSha256": sha256(files["failed-collection-attempt-002-terminal"]),
        "failedCollectionAttempt002FailureSha256": sha256(files["failed-collection-attempt-002-failure"]),
        "failedCollectionAttempt002SealSha256": sha256(files["failed-collection-attempt-002-seal"]),
        "compileTerminalSha256": sha256(files["algorithm-free-compile-terminal"]),
        "independentValidationSha256": sha256(files["independent-static-validation"]),
        "prelaunchReadinessSha256": sha256(files["algorithm-free-prelaunch-readiness"]),
        "attempt002SupersessionReceiptSha256": sha256(files["attempt-002-supersession-receipt"]),
        "prelaunchAttempt003FailureReceiptSha256": sha256(files["prelaunch-attempt-003-failure-receipt"]),
        "finalFreezeValidationSha256": sha256(validation_path),
        "finalFreezeManifestSha256": sha256(manifest_path),
        "formalCollectionAuthorized": True,
        "formalCollectionStarted": False,
        "formalAnalysisAuthorized": False,
        "formalAnalysisStarted": False,
        "formalCollectionAttempt003Authorized": True,
        "nextRequiredAction": "create a fresh attempt-003 execution authorization and fresh evidence/measured roots, then launch exactly once under the continuing user authorization",
    }
    write_new(terminal_path, terminal)
    print(json.dumps({
        "status": terminal["status"],
        "root": str(output_root),
        "validationSha256": sha256(validation_path),
        "manifestSha256": sha256(manifest_path),
        "terminalSha256": sha256(terminal_path),
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
