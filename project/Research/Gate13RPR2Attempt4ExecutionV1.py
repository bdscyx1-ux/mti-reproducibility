#!/usr/bin/env python3
"""Gate 13R-PR2 formal attempt 4 block-committed, boundary-resumable executor.

Scientific inputs and Unity command remain frozen.  This control-plane version
adds prospective per-block formal-eligibility commits and bounded automatic
resume only at an unambiguous committed block boundary.  It never performs
formal statistical analysis, Gate 14R, top-up, cross-attempt merge, or an
automatic measured retry of a partial/failed block.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import traceback
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterable

import jsonschema
import psutil

import Gate13RPR2Attempt3ExecutionV1 as base


SCRIPT_ID = "gate13r-pr2-formal-attempt4-block-commit-auto-resume-orchestrator-v1"
FORMAL_ROOT_REL = "Research/FormalRuns/Gate13R_RQAligned_S48H48/v4"
RECEIPT_REL = "Research/Gate13R_PR2_Formal_Execution_Receipt.v4.json"
STATUS_REL = "Research/Gate13R_PR2_Formal_Execution_Status.v4.json"
STATUS_SCHEMA_REL = "Research/Gate13R_PR2_Attempt4_Operational_Status_Schema.v1.json"
CONTRACT_REL = "Research/Gate13R_PR2_Attempt4_Execution_Contract.v1.json"
AUTHORIZATION_REL = "Research/Gate13R_PR2_Attempt4_Execution_Authorization.v1.json"
PROTOCOL_REL = "Research/Gate13R_RQAligned_Preregistration_BlockwiseEligibility_AutoResume_Amendment.v1.md"
USER_AUTH_REL = "Research/Gate13R_PR2_Attempt4_Restart_BlockwiseEligibility_AutoResume_User_Authorization.v1.txt"
PYTHON_REL = "Research/Gate13RPR2Attempt4ExecutionV1.py"
LAUNCHER_REL = "Research/Run-Gate13RPR2FormalAttempt4V1.ps1"
BLOCK_WRAPPER_REL = "Research/Run-Gate13RPR2MP2FormalBlockV4.ps1"
SCHEDULE_REL = "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
OVERLAY_REL = "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"
TOTAL_PROCESSES = 3552
TOTAL_SAMPLES = 10176
TOTAL_CAMPAIGNS = 74
TOTAL_SCENARIOS = 53
TOTAL_MATCHED_SUPERBLOCKS = 1008
MAX_AUTO_RESUMES = 3
MINIMUM_FREE_BYTES = 57_397_541_440
RAW_COMPLETE = "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE"
TERMINAL_PARTIAL = "FAILED-PARTIAL-FORMAL-BLOCKS-RETAINED-NO-AUTO-RETRY"

# The frozen plan format is reused, but its receipt binding is attempt-4.
base.RECEIPT_REL = RECEIPT_REL


class ContractError(RuntimeError):
    pass


class UnsafeResume(ContractError):
    pass


def utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def project_path(project: Path, relative: str) -> Path:
    return base.project_path(project, relative)


def read_json_retry(path: Path) -> Any:
    last: BaseException | None = None
    for delay in (0, 2, 5):
        if delay:
            time.sleep(delay)
        try:
            return base.read_json(path)
        except (OSError, json.JSONDecodeError) as error:
            last = error
    raise ContractError(f"READ-RETRY-EXHAUSTED:{path}:{type(last).__name__}:{last}")


def load_contract(project: Path) -> dict[str, Any]:
    contract_path = project_path(project, CONTRACT_REL)
    contract = read_json_retry(contract_path)
    if (
        contract.get("contractId") != "gate13r-pr2-formal-attempt4-block-eligibility-auto-resume-v1"
        or contract.get("formalAttemptOrdinal") != 4
        or contract.get("formalRootRelativePath") != FORMAL_ROOT_REL
        or contract.get("perCompletedBlockFormalEligibility") is not True
        or contract.get("automaticResume", {}).get("authorized") is not True
        or int(contract.get("automaticResume", {}).get("maximumCount", -1)) != MAX_AUTO_RESUMES
        or contract.get("automaticMeasuredRetryAuthorized") is not False
        or contract.get("phaseBFormalStatisticalAnalysisAuthorized") is not False
        or contract.get("gate14RAuthorized") is not False
    ):
        raise ContractError("ATTEMPT4-EXECUTION-CONTRACT")
    for relative, expected in sorted(contract["frozenBindings"].items()):
        path = project_path(project, relative)
        actual = base.sha256_file(path) if path.is_file() else None
        if actual != expected:
            raise ContractError(f"ATTEMPT4-FROZEN-HASH:{relative}:{actual}:{expected}")
    authorization = read_json_retry(project_path(project, AUTHORIZATION_REL))
    if (
        authorization.get("authorizationId") != "gate13r-pr2-formal-attempt4-fresh-restart-blockwise-eligibility-auto-resume-v1"
        or authorization.get("formalAttempt4PhaseAAcquisitionAuthorized") is not True
        or authorization.get("automaticResumeAuthorized") is not True
        or authorization.get("phaseBFormalStatisticalAnalysisAuthorized") is not False
        or authorization.get("gate14RAuthorized") is not False
        or authorization.get("executionContractSha256") != base.sha256_file(project_path(project, CONTRACT_REL))
    ):
        raise ContractError("ATTEMPT4-AUTHORIZATION-CONTRACT")
    return contract


def status_template(project: Path, receipt_sha: str, started_at: str) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "statusKind": "gate13r-pr2-formal-attempt4-operational-status-v1",
        "savedAtUtc": utc_now(),
        "status": "PRELAUNCH",
        "formalAttemptOrdinal": 4,
        "formalRoot": str(project_path(project, FORMAL_ROOT_REL)),
        "executionReceiptSha256": receipt_sha,
        "candidateConfigSha256": "c8d3e9965ae72798e2366c0187a96e578df306bb68196f54039c421672b78042",
        "scheduleSha256": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
        "startedAtUtc": started_at,
        "lastDurableCheckpointAtUtc": started_at,
        "completedProcessCount": 0,
        "completedSampleCount": 0,
        "eligibleProcessCount": 0,
        "eligibleSampleCount": 0,
        "totalProcessCount": TOTAL_PROCESSES,
        "totalSampleCount": TOTAL_SAMPLES,
        "currentGlobalProcessOrdinal": None,
        "currentCampaignId": None,
        "currentScenarioId": None,
        "currentCohort": None,
        "currentBlockId": None,
        "currentMatchedSuperblockId": None,
        "currentABBAOrder": None,
        "currentWilliamsRow": None,
        "currentUnityProcessId": None,
        "currentUnityProcessStartedAtUtc": None,
        "currentUnityBlockStartedAtUtc": None,
        "latestWorkingSetBytes": None,
        "latestPrivateMemoryBytes": None,
        "latestAvailablePhysicalMemoryBytes": None,
        "outputFileCount": 0,
        "rawBytes": 0,
        "advisoryCrossingCount": 0,
        "rawDataComplete": False,
        "analysisAuthorized": False,
        "gate14RAuthorized": False,
        "perCompletedBlockFormalEligibility": True,
        "automaticResumeAuthorized": True,
        "automaticResumeCount": 0,
        "maximumAutomaticResumeCount": MAX_AUTO_RESUMES,
        "automaticMeasuredRetryAttempted": False,
        "automaticTopUpAttempted": False,
        "partialAttemptMergeAttempted": False,
        "lastBlockEligibilityCommitPath": None,
        "lastBlockEligibilityCommitSha256": None,
        "errorReasonCode": None,
        "failureCheckpointPath": None,
        "statusPublicationFailureCount": 0,
    }


def apply_record(status: dict[str, Any], record: dict[str, Any]) -> None:
    matched_id, order = base.matched_identity(record)
    status.update(
        {
            "currentGlobalProcessOrdinal": int(record["globalProcessOrdinal"]),
            "currentCampaignId": str(record["campaignId"]),
            "currentScenarioId": str(record["scenarioId"]),
            "currentCohort": str(record["comparisonCohortId"]),
            "currentBlockId": str(record["blockId"]),
            "currentMatchedSuperblockId": matched_id,
            "currentABBAOrder": order,
            "currentWilliamsRow": int(record["williamsRowIndex"]) + 1,
        }
    )


class StatusPublisher:
    def __init__(self, project: Path, receipt_sha: str, started_at: str, control_root: Path, *, resume_count: int = 0) -> None:
        self.project = project
        self.path = project_path(project, STATUS_REL)
        self.schema = read_json_retry(project_path(project, STATUS_SCHEMA_REL))
        self.control_root = control_root
        self.value = status_template(project, receipt_sha, started_at)
        if self.path.is_file():
            try:
                candidate = read_json_retry(self.path)
                if candidate.get("executionReceiptSha256") == receipt_sha and candidate.get("formalAttemptOrdinal") == 4:
                    self.value = candidate
            except Exception:
                pass
        self.value["automaticResumeCount"] = resume_count

    def durable_checkpoint(self, when: str | None = None) -> None:
        self.value["lastDurableCheckpointAtUtc"] = when or utc_now()

    def publish(self, *, create: bool = False) -> bool:
        self.value["savedAtUtc"] = utc_now()
        jsonschema.validate(self.value, self.schema)
        if create:
            base.atomic_json(self.path, self.value, replace=False)
            return True
        failures: list[str] = []
        for delay in (0, 2, 5):
            if delay:
                time.sleep(delay)
            try:
                base.atomic_json(self.path, self.value, replace=True)
                return True
            except OSError as error:
                failures.append(f"{type(error).__name__}:{error}")
        self.value["statusPublicationFailureCount"] = int(self.value.get("statusPublicationFailureCount", 0)) + 1
        event_root = self.control_root / "status-publication-events"
        event = {
            "schemaVersion": 1,
            "eventKind": "gate13r-pr2-attempt4-status-publication-failure-v1",
            "savedAtUtc": utc_now(),
            "nonScientificControlPlaneFailure": True,
            "blockEligibilityUnaffected": True,
            "retryDelaysSeconds": [0, 2, 5],
            "errors": failures,
            "statusSnapshot": self.value,
        }
        try:
            base.atomic_json(event_root / f"event-{datetime.now(UTC).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex}.json", event, replace=False)
        except Exception:
            pass
        return False


def block_paths(formal_root: Path, control_root: Path, record: dict[str, Any]) -> dict[str, Path]:
    ordinal = int(record["globalProcessOrdinal"])
    output = project_path(formal_root, str(record["outputRelativePath"]))
    return {
        "output": output,
        "manifest": output / "block-manifest.json",
        "summary": Path(str(output) + ".summary.json"),
        "plan": formal_root / "_plans" / f"p{ordinal:06d}.json",
        "identity": control_root / "process-identities" / f"p{ordinal:06d}.json",
        "commit": control_root / "block-eligibility-commits" / f"p{ordinal:06d}.json",
        "stdout": control_root / "block-wrapper-logs" / f"p{ordinal:06d}.stdout.log",
        "stderr": control_root / "block-wrapper-logs" / f"p{ordinal:06d}.stderr.log",
    }


def verify_plan(project: Path, record: dict[str, Any], policy: dict[str, Any], path: Path, receipt_sha: str) -> dict[str, Any]:
    expected = base.make_plan(project, record, policy, formal=True, receipt_sha256=receipt_sha)
    actual = read_json_retry(path)
    if actual != expected:
        raise ContractError(f"ATTEMPT4-PLAN-MISMATCH:{record['globalProcessOrdinal']}")
    return actual


def verify_completed_block(
    *, project: Path, formal_root: Path, record: dict[str, Any], plan_path: Path, observed: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any], list[Path]]:
    output = project_path(formal_root, str(record["outputRelativePath"]))
    manifest_path = output / "block-manifest.json"
    summary_path = Path(str(output) + ".summary.json")
    if not manifest_path.is_file() or not summary_path.is_file():
        raise ContractError(f"BLOCK-EVIDENCE-MISSING:{record['globalProcessOrdinal']}")
    manifest = read_json_retry(manifest_path)
    summary = read_json_retry(summary_path)
    if (
        int(manifest.get("schemaVersion", -1)) != 5
        or manifest.get("manifestKind") != "gate13r-pr2-mp2-formal-attempt3-candidate-block-manifest-v1"
        or manifest.get("completed") is not True
        or manifest.get("hardMemoryRulesPassed") is not True
        or manifest.get("formalCampaign") is not True
        or manifest.get("validationOnly") is not False
        or manifest.get("blockId") != record["blockId"]
        or int(manifest.get("completedSampleCount", -1)) != int(record["expectedSampleCount"])
        or manifest.get("blockPlanSha256") != base.sha256_file(plan_path)
    ):
        raise ContractError(f"BLOCK-MANIFEST-CONTRACT:{record['globalProcessOrdinal']}")
    if (
        summary.get("summaryKind") != "gate13r-pr2-mp2-block-wrapper-validation-summary-v3"
        or summary.get("mode") != "FormalAttempt4"
        or summary.get("expectedOutcome") != "Pass"
        or summary.get("passed") is not True
        or summary.get("formalCampaign") is not True
        or summary.get("validationOnly") is not False
        or int(summary.get("formalAttemptOrdinal", -1)) != 4
        or summary.get("automaticRetryAttempted") is not False
        or summary.get("automaticResumeAttempted") is not False
        or summary.get("blockId") != record["blockId"]
        or summary.get("blockPlanSha256") != base.sha256_file(plan_path)
    ):
        raise ContractError(f"BLOCK-WRAPPER-SUMMARY-CONTRACT:{record['globalProcessOrdinal']}")
    if int(summary.get("unityProcessId", -1)) != int(observed["pid"]) or int(manifest.get("processId", -1)) != int(observed["pid"]):
        raise ContractError(f"BLOCK-PROCESS-ID-MISMATCH:{record['globalProcessOrdinal']}")
    manifest_started = datetime.fromisoformat(str(manifest["processStartTimeUtc"]).replace("Z", "+00:00"))
    observed_started = datetime.fromisoformat(str(observed["startTimeUtc"]).replace("Z", "+00:00"))
    if abs((manifest_started - observed_started).total_seconds()) > 2.0:
        raise ContractError(f"BLOCK-PROCESS-START-MISMATCH:{record['globalProcessOrdinal']}")
    samples = list(manifest.get("samples") or [])
    expected_entries = list(record["entries"])
    if len(samples) != len(expected_entries):
        raise ContractError(f"BLOCK-SAMPLE-CARDINALITY:{record['globalProcessOrdinal']}")
    for expected, sample in zip(expected_entries, samples, strict=True):
        for key in ("position", "algorithmId", "predecessorAlgorithmId", "runId"):
            if str(sample.get(key)) != str(expected.get(key)):
                raise ContractError(f"BLOCK-SAMPLE-IDENTITY:{record['globalProcessOrdinal']}:{key}")
        if sample.get("completed") is not True or sample.get("formalCampaign") is not True:
            raise ContractError(f"BLOCK-SAMPLE-ELIGIBILITY:{sample.get('runId')}")
        for path_key, hash_key in (
            ("manifestRelativePath", "manifestSha256"),
            ("summaryRelativePath", "summarySha256"),
            ("workloadResultRelativePath", "workloadResultSha256"),
            ("memoryGateEvaluationRelativePath", "memoryGateEvaluationSha256"),
        ):
            child = (output / Path(str(sample[path_key]))).resolve()
            try:
                child.relative_to(output.resolve())
            except ValueError as error:
                raise ContractError(f"SAMPLE-PATH-ESCAPE:{sample['runId']}:{path_key}") from error
            if not child.is_file() or base.sha256_file(child) != str(sample[hash_key]):
                raise ContractError(f"SAMPLE-FILE-HASH:{sample['runId']}:{path_key}")
            child_json = read_json_retry(child) if child.suffix.lower() == ".json" else None
            if path_key != "workloadResultRelativePath" and (
                not isinstance(child_json, dict) or child_json.get("formalCampaign") is not True
            ):
                raise ContractError(f"SAMPLE-FORMAL-CAMPAIGN-FLAG:{sample['runId']}:{path_key}")
    files = base.raw_files_for_block(output)
    if not files:
        raise ContractError(f"BLOCK-RAW-FILES-EMPTY:{record['globalProcessOrdinal']}")
    return manifest, summary, files


def make_identity(record: dict[str, Any], observed: dict[str, Any], manifest: dict[str, Any], summary_path: Path) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "identityKind": "gate13r-pr2-formal-attempt4-block-process-identity-v1",
        "savedAtUtc": utc_now(),
        "globalProcessOrdinal": int(record["globalProcessOrdinal"]),
        "blockId": record["blockId"],
        "campaignId": record["campaignId"],
        "scenarioId": record["scenarioId"],
        "processId": int(observed["pid"]),
        "processStartTimeUtc": observed["startTimeUtc"],
        "manifestProcessStartTimeUtc": manifest["processStartTimeUtc"],
        "wrapperSummarySha256": base.sha256_file(summary_path),
        "blockManifestSha256": base.sha256_file(Path(str(summary_path).removesuffix(".summary.json")) / "block-manifest.json"),
        "freshProcess": True,
        "maximumBlocksInProcess": 1,
        "formalAttemptOrdinal": 4,
    }


def execute_block(
    *, project: Path, formal_root: Path, receipt_path: Path, record: dict[str, Any], plan_path: Path,
    unity_path: Path, powershell_path: Path, block_timeout_seconds: int, status: StatusPublisher, control_root: Path
) -> dict[str, Any]:
    ordinal = int(record["globalProcessOrdinal"])
    paths = block_paths(formal_root, control_root, record)
    paths["output"].parent.mkdir(parents=True, exist_ok=True)
    paths["stdout"].parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(powershell_path), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", str(project_path(project, BLOCK_WRAPPER_REL)), "-ProjectPath", str(project),
        "-BlockPlanPath", str(plan_path), "-OutputDirectory", str(paths["output"]),
        "-AllowedRoot", str(formal_root), "-Mode", "FormalAttempt4", "-ExecutionReceiptPath", str(receipt_path),
        "-UnityPath", str(unity_path), "-ExpectedOutcome", "Pass", "-TimeoutSeconds", str(block_timeout_seconds),
    ]
    environment = os.environ.copy()
    environment["PSModulePath"] = base.EXPECTED_NATIVE_PSMODULEPATH
    wrapper_started = time.time()
    observed: dict[str, Any] | None = None
    concurrency_violation = False
    with paths["stdout"].open("xb") as stdout, paths["stderr"].open("xb") as stderr:
        child = subprocess.Popen(command, cwd=str(project), env=environment, stdout=stdout, stderr=stderr, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        last_publish = 0.0
        while child.poll() is None:
            owned = base.find_owned_unity(project, wrapper_started)
            all_unity = base.current_unity_processes()
            if len(all_unity) > 1 or len(owned) > 1:
                concurrency_violation = True
            if len(owned) == 1:
                try:
                    telemetry = base.process_telemetry(owned[0])
                    if observed is None:
                        observed = telemetry.copy()
                        apply_record(status.value, record)
                        status.value["currentUnityBlockStartedAtUtc"] = telemetry["startTimeUtc"]
                    status.value.update(
                        {
                            "status": "ACQUISITION-RUNNING",
                            "currentUnityProcessId": telemetry["pid"],
                            "currentUnityProcessStartedAtUtc": telemetry["startTimeUtc"],
                            "latestWorkingSetBytes": telemetry["workingSetBytes"],
                            "latestPrivateMemoryBytes": telemetry["privateMemoryBytes"],
                            "latestAvailablePhysicalMemoryBytes": telemetry["availablePhysicalMemoryBytes"],
                        }
                    )
                    now = time.monotonic()
                    if now - last_publish >= 5.0:
                        status.publish()
                        last_publish = now
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            time.sleep(0.5)
        exit_code = int(child.returncode)
    if concurrency_violation:
        raise ContractError(f"UNITY-CONCURRENCY-VIOLATION:{ordinal}")
    if observed is None:
        raise ContractError(f"OWNED-UNITY-PROCESS-NOT-OBSERVED:{ordinal}:wrapper-exit={exit_code}")
    if exit_code != 0:
        raise ContractError(f"BLOCK-WRAPPER-NONZERO:{ordinal}:{exit_code}")
    manifest, summary, files = verify_completed_block(
        project=project, formal_root=formal_root, record=record, plan_path=plan_path, observed=observed
    )
    identity = make_identity(record, observed, manifest, paths["summary"])
    base.atomic_json(paths["identity"], identity, replace=False)
    return {"manifest": manifest, "summary": summary, "files": files, "identity": identity}


def files_tree(files: Iterable[Path], root: Path) -> tuple[int, int, str]:
    ordered = sorted({path.resolve() for path in files}, key=lambda item: item.as_posix())
    digest = hashlib.sha256()
    raw_bytes = 0
    for path in ordered:
        relative = path.relative_to(root.resolve()).as_posix()
        length = path.stat().st_size
        file_hash = base.sha256_file(path)
        digest.update(f"{relative}\0{length}\0{file_hash}\n".encode("utf-8"))
        raw_bytes += length
    return len(ordered), raw_bytes, digest.hexdigest()


def create_block_commit(
    *, formal_root: Path, control_root: Path, receipt_sha: str, record: dict[str, Any], result: dict[str, Any], recovered: bool
) -> tuple[Path, dict[str, Any]]:
    paths = block_paths(formal_root, control_root, record)
    file_count, raw_bytes, tree_hash = files_tree(result["files"], formal_root)
    identity_hash = base.sha256_file(paths["identity"])
    commit = {
        "schemaVersion": 1,
        "commitKind": "gate13r-pr2-attempt4-completed-block-formal-eligibility-commit-v1",
        "committedAtUtc": utc_now(),
        "formalAttemptOrdinal": 4,
        "executionReceiptSha256": receipt_sha,
        "globalProcessOrdinal": int(record["globalProcessOrdinal"]),
        "blockId": record["blockId"],
        "campaignId": record["campaignId"],
        "scenarioId": record["scenarioId"],
        "comparisonCohortId": record["comparisonCohortId"],
        "matchedSuperblock": record.get("matchedSuperblock"),
        "williamsRowIndex": int(record["williamsRowIndex"]),
        "expectedSampleCount": int(record["expectedSampleCount"]),
        "completedSampleCount": int(record["expectedSampleCount"]),
        "outputRelativePath": record["outputRelativePath"],
        "blockPlanSha256": base.sha256_file(paths["plan"]),
        "blockManifestSha256": base.sha256_file(paths["manifest"]),
        "wrapperSummarySha256": base.sha256_file(paths["summary"]),
        "processIdentitySha256": identity_hash,
        "blockRawFileCount": file_count,
        "blockRawBytes": raw_bytes,
        "blockRawCanonicalTreeSha256": tree_hash,
        "formalStatisticalEligibility": True,
        "eligibilityScope": "BLOCK-LEVEL; ESTIMAND-SPECIFIC-COMPLETENESS-STILL-REQUIRED",
        "resultIndependentAutomaticInclusion": True,
        "recoveredCompleteUncommittedBlock": recovered,
        "automaticMeasuredRetry": False,
        "immutable": True,
    }
    base.atomic_json(paths["commit"], commit, replace=False)
    return paths["commit"], commit


def load_and_verify_identity(path: Path, record: dict[str, Any]) -> dict[str, Any]:
    identity = read_json_retry(path)
    if (
        identity.get("identityKind") != "gate13r-pr2-formal-attempt4-block-process-identity-v1"
        or int(identity.get("formalAttemptOrdinal", -1)) != 4
        or int(identity.get("globalProcessOrdinal", -1)) != int(record["globalProcessOrdinal"])
        or identity.get("blockId") != record["blockId"]
    ):
        raise ContractError(f"ATTEMPT4-PROCESS-IDENTITY:{record['globalProcessOrdinal']}")
    return identity


def verify_block_commit(
    *, project: Path, formal_root: Path, control_root: Path, receipt_sha: str,
    record: dict[str, Any], policy: dict[str, Any]
) -> dict[str, Any]:
    paths = block_paths(formal_root, control_root, record)
    commit = read_json_retry(paths["commit"])
    if (
        commit.get("commitKind") != "gate13r-pr2-attempt4-completed-block-formal-eligibility-commit-v1"
        or commit.get("formalStatisticalEligibility") is not True
        or commit.get("resultIndependentAutomaticInclusion") is not True
        or commit.get("automaticMeasuredRetry") is not False
        or commit.get("executionReceiptSha256") != receipt_sha
        or int(commit.get("globalProcessOrdinal", -1)) != int(record["globalProcessOrdinal"])
        or commit.get("blockId") != record["blockId"]
        or int(commit.get("completedSampleCount", -1)) != int(record["expectedSampleCount"])
    ):
        raise ContractError(f"BLOCK-COMMIT-CONTRACT:{record['globalProcessOrdinal']}")
    verify_plan(project, record, policy, paths["plan"], receipt_sha)
    identity = load_and_verify_identity(paths["identity"], record)
    observed = {"pid": int(identity["processId"]), "startTimeUtc": identity["processStartTimeUtc"]}
    manifest, summary, files = verify_completed_block(
        project=project, formal_root=formal_root, record=record, plan_path=paths["plan"], observed=observed
    )
    file_count, raw_bytes, tree_hash = files_tree(files, formal_root)
    checks = {
        "blockPlanSha256": base.sha256_file(paths["plan"]),
        "blockManifestSha256": base.sha256_file(paths["manifest"]),
        "wrapperSummarySha256": base.sha256_file(paths["summary"]),
        "processIdentitySha256": base.sha256_file(paths["identity"]),
        "blockRawFileCount": file_count,
        "blockRawBytes": raw_bytes,
        "blockRawCanonicalTreeSha256": tree_hash,
    }
    for key, expected in checks.items():
        if commit.get(key) != expected:
            raise ContractError(f"BLOCK-COMMIT-HASH-OR-COUNT:{record['globalProcessOrdinal']}:{key}")
    return {"commit": commit, "manifest": manifest, "summary": summary, "files": files}


def artifact_state(formal_root: Path, control_root: Path, record: dict[str, Any]) -> str:
    paths = block_paths(formal_root, control_root, record)
    if paths["commit"].is_file():
        return "committed"
    complete = paths["manifest"].is_file() and paths["summary"].is_file()
    any_measured = paths["output"].exists() or paths["summary"].exists()
    any_execution_control = paths["identity"].exists() or paths["stdout"].exists() or paths["stderr"].exists()
    if complete:
        return "complete-uncommitted"
    if any_measured or any_execution_control:
        return "partial-or-ambiguous"
    return "not-started"


def promote_complete_uncommitted(
    *, project: Path, formal_root: Path, control_root: Path, receipt_sha: str,
    record: dict[str, Any], policy: dict[str, Any]
) -> dict[str, Any]:
    paths = block_paths(formal_root, control_root, record)
    verify_plan(project, record, policy, paths["plan"], receipt_sha)
    if paths["identity"].is_file():
        identity = load_and_verify_identity(paths["identity"], record)
        observed = {"pid": int(identity["processId"]), "startTimeUtc": identity["processStartTimeUtc"]}
    else:
        manifest = read_json_retry(paths["manifest"])
        summary = read_json_retry(paths["summary"])
        observed = {"pid": int(summary["unityProcessId"]), "startTimeUtc": str(manifest["processStartTimeUtc"])}
        verified_manifest, _, _ = verify_completed_block(
            project=project, formal_root=formal_root, record=record, plan_path=paths["plan"], observed=observed
        )
        identity = make_identity(record, observed, verified_manifest, paths["summary"])
        base.atomic_json(paths["identity"], identity, replace=False)
    manifest, summary, files = verify_completed_block(
        project=project, formal_root=formal_root, record=record, plan_path=paths["plan"], observed=observed
    )
    result = {"manifest": manifest, "summary": summary, "files": files, "identity": identity}
    commit_path, commit = create_block_commit(
        formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha, record=record, result=result, recovered=True
    )
    return {"commitPath": str(commit_path), "commit": commit, "result": result}


def ensure_no_later_artifacts(formal_root: Path, control_root: Path, schedule: list[dict[str, Any]], start_index: int) -> None:
    for record in schedule[start_index:]:
        paths = block_paths(formal_root, control_root, record)
        if any(paths[key].exists() for key in ("output", "summary", "plan", "identity", "commit", "stdout", "stderr")):
            raise UnsafeResume(f"LATER-ORDINAL-ARTIFACT:{record['globalProcessOrdinal']}")


def reconstruct_frontier(
    *, project: Path, formal_root: Path, control_root: Path, receipt_sha: str,
    schedule: list[dict[str, Any]], overlay: list[dict[str, Any]], allow_promotion: bool
) -> dict[str, Any]:
    completed = 0
    samples = 0
    files = 0
    raw_bytes = 0
    advisories = 0
    last_commit_path: Path | None = None
    promoted: int | None = None
    for index, (record, policy) in enumerate(zip(schedule, overlay, strict=True)):
        paths = block_paths(formal_root, control_root, record)
        if not paths["commit"].is_file():
            state = artifact_state(formal_root, control_root, record)
            ensure_no_later_artifacts(formal_root, control_root, schedule, index + 1)
            if state == "partial-or-ambiguous":
                raise UnsafeResume(f"PARTIAL-OR-AMBIGUOUS-NEXT-BLOCK:{record['globalProcessOrdinal']}")
            if state == "complete-uncommitted" and allow_promotion:
                promoted_result = promote_complete_uncommitted(
                    project=project, formal_root=formal_root, control_root=control_root,
                    receipt_sha=receipt_sha, record=record, policy=policy
                )
                promoted = int(record["globalProcessOrdinal"])
                verified = verify_block_commit(
                    project=project, formal_root=formal_root, control_root=control_root,
                    receipt_sha=receipt_sha, record=record, policy=policy
                )
            elif state == "complete-uncommitted":
                return {
                    "completedProcessCount": completed, "completedSampleCount": samples,
                    "outputFileCount": files, "rawBytes": raw_bytes, "advisoryCrossingCount": advisories,
                    "nextGlobalProcessOrdinal": int(record["globalProcessOrdinal"]),
                    "nextArtifactState": state, "promotionRequired": True, "promotedGlobalProcessOrdinal": None,
                    "lastCommitPath": None if last_commit_path is None else str(last_commit_path),
                }
            else:
                return {
                    "completedProcessCount": completed, "completedSampleCount": samples,
                    "outputFileCount": files, "rawBytes": raw_bytes, "advisoryCrossingCount": advisories,
                    "nextGlobalProcessOrdinal": int(record["globalProcessOrdinal"]),
                    "nextArtifactState": state, "promotionRequired": False, "promotedGlobalProcessOrdinal": promoted,
                    "lastCommitPath": None if last_commit_path is None else str(last_commit_path),
                }
        else:
            verified = verify_block_commit(
                project=project, formal_root=formal_root, control_root=control_root,
                receipt_sha=receipt_sha, record=record, policy=policy
            )
        commit = verified["commit"]
        completed += 1
        samples += int(commit["completedSampleCount"])
        files += int(commit["blockRawFileCount"])
        raw_bytes += int(commit["blockRawBytes"])
        advisories += int(verified["manifest"].get("nativeAdvisoryBoundaryCount", 0))
        last_commit_path = paths["commit"]
    return {
        "completedProcessCount": completed, "completedSampleCount": samples,
        "outputFileCount": files, "rawBytes": raw_bytes, "advisoryCrossingCount": advisories,
        "nextGlobalProcessOrdinal": None, "nextArtifactState": "all-committed",
        "promotionRequired": False, "promotedGlobalProcessOrdinal": promoted,
        "lastCommitPath": None if last_commit_path is None else str(last_commit_path),
    }


def environment_snapshot() -> dict[str, Any]:
    value = base.environment_snapshot()
    value["snapshotKind"] = "gate13r-pr2-formal-attempt4-environment-snapshot-v1"
    return value


def validate_prelaunch(project: Path, *, require_targets_absent: bool = True) -> dict[str, Any]:
    project = project.resolve()
    contract = load_contract(project)
    schedule, overlay, schedule_summary = base.validate_schedule(project)
    if schedule_summary.get("processCount") != TOTAL_PROCESSES or schedule_summary.get("sampleCount") != TOTAL_SAMPLES:
        raise ContractError("ATTEMPT4-SCHEDULE-CARDINALITY")
    candidate = read_json_retry(project_path(project, "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"))
    if (
        candidate.get("configId") != "gate13r-pr2-rq-aligned-s48-h48-mp2-attempt3-candidate-v4"
        or int(candidate["totals"]["processCount"]) != TOTAL_PROCESSES
        or int(candidate["totals"]["sampleCount"]) != TOTAL_SAMPLES
        or candidate["processSemantics"]["strictSerial"] is not True
        or int(candidate["processSemantics"]["maximumConcurrentUnityEditorProcesses"]) != 1
    ):
        raise ContractError("ATTEMPT4-CANDIDATE-CONTRACT")
    attempt3_status = read_json_retry(project_path(project, "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"))
    if attempt3_status.get("status") != "FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE":
        raise ContractError("ATTEMPT3-HISTORICAL-TERMINAL-NOT-PRESERVED")
    targets = [project_path(project, FORMAL_ROOT_REL), project_path(project, RECEIPT_REL), project_path(project, STATUS_REL)]
    target_state = [{"path": str(path), "exists": path.exists()} for path in targets]
    if require_targets_absent and any(item["exists"] for item in target_state):
        raise ContractError("FORMAL-ATTEMPT4-TARGET-PREEXISTS")
    if require_targets_absent and base.current_unity_processes():
        raise ContractError("UNITY-PROCESS-PRESENT-PRELAUNCH")
    if require_targets_absent and (project / "Temp/UnityLockfile").exists():
        raise ContractError("UNITY-LOCK-PRESENT-PRELAUNCH")
    free_bytes = shutil.disk_usage(project.anchor).free
    if require_targets_absent and free_bytes < MINIMUM_FREE_BYTES:
        raise ContractError("INSUFFICIENT-H-DRIVE-FREE-BYTES")
    selected = (1, 48, 1536, 1537, 1538, 2000, 3552)
    plans = []
    for ordinal in selected:
        plan = base.make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
        plans.append({"globalProcessOrdinal": ordinal, "blockId": plan["blockId"], "validationPlanSha256": hashlib.sha256(base.json_bytes(plan)).hexdigest()})
    return {
        "schemaVersion": 1,
        "validationKind": "gate13r-pr2-formal-attempt4-prelaunch-core-validation-v1",
        "validatedAtUtc": utc_now(),
        "passed": True,
        "contractSha256": base.sha256_file(project_path(project, CONTRACT_REL)),
        "authorizationSha256": base.sha256_file(project_path(project, AUTHORIZATION_REL)),
        "frozenBindingCount": len(contract["frozenBindings"]),
        "schedule": schedule_summary,
        "selectedDeterministicPlanReconstructions": plans,
        "formalTargets": target_state,
        "formalTargetsAbsent": not any(item["exists"] for item in target_state),
        "attempt3HistoricalTerminalPreserved": True,
        "attempt3DataReuseAuthorized": False,
        "perCompletedBlockFormalEligibility": True,
        "automaticResumeAuthorized": True,
        "maximumAutomaticResumeCount": MAX_AUTO_RESUMES,
        "automaticMeasuredRetryAuthorized": False,
        "unityProcessCount": len(base.current_unity_processes()),
        "projectLockAbsent": not (project / "Temp/UnityLockfile").exists(),
        "hDriveAvailableFreeBytes": free_bytes,
        "minimumLaunchFreeBytes": MINIMUM_FREE_BYTES,
        "phaseBFormalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }


def create_receipt(
    *, project: Path, prelaunch_final_audit: Path, unity_path: Path, powershell_path: Path
) -> tuple[Path, str, str]:
    core = validate_prelaunch(project, require_targets_absent=True)
    audit = read_json_retry(prelaunch_final_audit)
    if (
        audit.get("passed") is not True
        or audit.get("formalTargetsAbsent") is not True
        or audit.get("orchestratorSha256") != base.sha256_file(project_path(project, PYTHON_REL))
        or audit.get("launcherSha256") != base.sha256_file(project_path(project, LAUNCHER_REL))
        or audit.get("blockWrapperSha256") != base.sha256_file(project_path(project, BLOCK_WRAPPER_REL))
        or audit.get("executionContractSha256") != base.sha256_file(project_path(project, CONTRACT_REL))
    ):
        raise ContractError("ATTEMPT4-FINAL-PRELAUNCH-AUDIT")
    if os.environ.get("PSModulePath", "") != base.EXPECTED_NATIVE_PSMODULEPATH:
        raise ContractError("ATTEMPT4-NATIVE-PSMODULEPATH-MISMATCH")
    environment = environment_snapshot()
    if environment["unityProcessCount"] != 0 or environment["hDriveFreeBytes"] < MINIMUM_FREE_BYTES:
        raise ContractError("ATTEMPT4-FINAL-ENVIRONMENT-GATE")
    started_at = utc_now()
    formal_root = project_path(project, FORMAL_ROOT_REL)
    receipt_path = project_path(project, RECEIPT_REL)
    status_path = project_path(project, STATUS_REL)
    contract = read_json_retry(project_path(project, CONTRACT_REL))
    receipt = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-formal-attempt4-phase-a-execution-receipt-v1",
        "receiptId": "gate13r-pr2-formal-attempt4-fresh-from-ordinal1-block-committed-auto-resumable-v1",
        "createdAtUtc": started_at,
        "formalAttemptOrdinal": 4,
        "formalRoot": str(formal_root),
        "formalOperationalStatus": str(status_path),
        "authorization": base.binding(project, AUTHORIZATION_REL),
        "executionContract": base.binding(project, CONTRACT_REL),
        "protocolAmendment": base.binding(project, PROTOCOL_REL),
        "userAuthorization": base.binding(project, USER_AUTH_REL),
        "prelaunchFinalAudit": {"resolvedAbsolutePath": str(prelaunch_final_audit), "sha256": base.sha256_file(prelaunch_final_audit), "passed": True},
        "activeBindings": {relative: {"relativePath": relative, "sha256": digest} for relative, digest in sorted(contract["frozenBindings"].items())},
        "executionImplementation": {
            "orchestrator": base.binding(project, PYTHON_REL),
            "launcher": base.binding(project, LAUNCHER_REL),
            "blockWrapper": base.binding(project, BLOCK_WRAPPER_REL),
            "frozenUnityCommand": base.binding(project, base.UNITY_COMMAND_REL),
            "frozenScientificEngine": base.binding(project, "Research/Gate13RPR2Attempt3ExecutionV1.py"),
        },
        "runtime": {
            "pythonExecutable": sys.executable,
            "pythonVersion": sys.version,
            "nativeWindowsPowerShell": str(powershell_path),
            "psModulePath": os.environ.get("PSModulePath"),
            "unityExecutable": str(unity_path),
            "unityExecutableSha256": base.sha256_file(unity_path),
        },
        "formalDesign": {
            "campaignCount": TOTAL_CAMPAIGNS, "scenarioCount": TOTAL_SCENARIOS,
            "processCount": TOTAL_PROCESSES, "sampleCount": TOTAL_SAMPLES,
            "matchedSuperblockCount": TOTAL_MATCHED_SUPERBLOCKS,
            "strictSerial": True, "maximumConcurrentUnityEditorProcesses": 1,
            "maximumBlocksPerUnityEditorProcess": 1,
        },
        "environmentAtCommit": environment,
        "freshRestartFromGlobalOrdinal": 1,
        "attempt3ObservationReuseAuthorized": False,
        "perCompletedBlockFormalEligibility": True,
        "automaticResumeAuthorized": True,
        "maximumAutomaticResumeCount": MAX_AUTO_RESUMES,
        "automaticResumeBoundary": "LAST-CONTIGUOUS-BLOCK-ELIGIBILITY-COMMIT",
        "automaticMeasuredRetryAuthorized": False,
        "automaticTopUpAuthorized": False,
        "partialAttemptMergeAuthorized": False,
        "phaseBFormalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "immutable": True,
        "prelaunchCoreValidation": core,
    }
    base.atomic_json(receipt_path, receipt, replace=False)
    receipt_sha = base.sha256_file(receipt_path)
    formal_root.mkdir(parents=False, exist_ok=False)
    return receipt_path, receipt_sha, started_at


def validate_receipt(project: Path) -> tuple[Path, str, dict[str, Any]]:
    receipt_path = project_path(project, RECEIPT_REL)
    receipt = read_json_retry(receipt_path)
    if (
        receipt.get("receiptId") != "gate13r-pr2-formal-attempt4-fresh-from-ordinal1-block-committed-auto-resumable-v1"
        or int(receipt.get("formalAttemptOrdinal", -1)) != 4
        or receipt.get("formalRoot") != str(project_path(project, FORMAL_ROOT_REL))
        or receipt.get("perCompletedBlockFormalEligibility") is not True
        or receipt.get("automaticResumeAuthorized") is not True
        or receipt.get("automaticMeasuredRetryAuthorized") is not False
        or receipt.get("phaseBFormalStatisticalAnalysisAuthorized") is not False
    ):
        raise ContractError("ATTEMPT4-RECEIPT-CONTRACT")
    load_contract(project)
    return receipt_path, base.sha256_file(receipt_path), receipt


def wait_for_quiescence(project: Path, timeout_seconds: int) -> None:
    deadline = time.monotonic() + timeout_seconds
    while base.current_unity_processes() or (project / "Temp/UnityLockfile").exists():
        if time.monotonic() >= deadline:
            raise UnsafeResume("AUTO-RESUME-QUIESCENCE-TIMEOUT")
        time.sleep(2)


def resume_event_paths(control_root: Path) -> list[Path]:
    root = control_root / "resume-events"
    if not root.is_dir():
        return []
    # Count only primary rNN.json events.  Promotion receipts are deliberately
    # named rNN-promotion.json and must not consume another resume allowance.
    return sorted(path for path in root.glob("r[0-9][0-9].json") if path.stem[1:].isdigit())


def session_failure_paths(control_root: Path) -> list[Path]:
    root = control_root / "session-failures"
    return sorted(root.glob("failure-*.json")) if root.is_dir() else []


def record_outer_run_failure(project: Path, error: BaseException) -> None:
    """Best-effort append-only evidence for supervisor-level run failures."""
    formal_root = project_path(project, FORMAL_ROOT_REL)
    receipt_path = project_path(project, RECEIPT_REL)
    control_root = formal_root / "_control"
    if not formal_root.is_dir() or not receipt_path.is_file() or not control_root.is_dir():
        return
    value = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-attempt4-orchestrator-session-failure-v1",
        "savedAtUtc": utc_now(),
        "formalAttemptOrdinal": 4,
        "executionReceiptSha256": base.sha256_file(receipt_path),
        "automaticResumeCountAtFailure": len(resume_event_paths(control_root)),
        "failureSignature": base.failure_signature(error),
        "errorType": type(error).__name__,
        "errorMessage": str(error),
        "unityProcessCount": len(base.current_unity_processes()),
        "projectUnityLockPresent": (project / "Temp/UnityLockfile").exists(),
        "automaticMeasuredRetry": False,
    }
    root = control_root / "session-failures"
    root.mkdir(parents=True, exist_ok=True)
    base.atomic_json(
        root / f"failure-{datetime.now(UTC).strftime('%Y%m%dT%H%M%S%fZ')}-{uuid.uuid4().hex}.json",
        value,
        replace=False,
    )


def write_session_start(control_root: Path, resume_count: int, frontier: dict[str, Any]) -> Path:
    session_number = resume_count + 1
    path = control_root / "execution-sessions" / f"s{session_number:02d}-start.json"
    value = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-attempt4-execution-session-start-v1",
        "savedAtUtc": utc_now(),
        "sessionNumber": session_number,
        "automaticResumeCount": resume_count,
        "completedProcessCountAtStart": frontier["completedProcessCount"],
        "completedSampleCountAtStart": frontier["completedSampleCount"],
        "firstExecutableGlobalOrdinal": frontier["nextGlobalProcessOrdinal"],
        "promotedGlobalProcessOrdinal": frontier.get("promotedGlobalProcessOrdinal"),
        "automaticMeasuredRetry": False,
    }
    base.atomic_json(path, value, replace=False)
    return path


def preserve_hard_failure(
    *, project: Path, formal_root: Path, control_root: Path, receipt_sha: str,
    status: StatusPublisher, frontier: dict[str, Any], record: dict[str, Any] | None, error: BaseException
) -> None:
    failure_root = control_root / "hard-failures"
    failure_path = failure_root / f"failure-{datetime.now(UTC).strftime('%Y%m%dT%H%M%S%fZ')}.json"
    reason = f"{type(error).__name__}:{error}"
    value = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-attempt4-measured-hard-failure-v1",
        "savedAtUtc": utc_now(),
        "executionReceiptSha256": receipt_sha,
        "status": TERMINAL_PARTIAL,
        "completedProcessCount": int(frontier["completedProcessCount"]),
        "completedSampleCount": int(frontier["completedSampleCount"]),
        "eligibleProcessCount": int(frontier["completedProcessCount"]),
        "eligibleSampleCount": int(frontier["completedSampleCount"]),
        "currentGlobalProcessOrdinal": None if record is None else int(record["globalProcessOrdinal"]),
        "currentBlockId": None if record is None else record["blockId"],
        "failureSignature": base.failure_signature(error),
        "error": "".join(traceback.format_exception(type(error), error, error.__traceback__)),
        "automaticResumeAllowed": False,
        "automaticMeasuredRetryAllowed": False,
        "committedBlocksRetainFormalStatisticalEligibility": True,
        "formalStatisticalAnalysisExecuted": False,
        "gate14RExecuted": False,
    }
    base.atomic_json(failure_path, value, replace=False)
    prohibit_path = control_root / "resume-prohibited.json"
    if not prohibit_path.exists():
        base.atomic_json(
            prohibit_path,
            {
                "schemaVersion": 1,
                "stateKind": "gate13r-pr2-attempt4-auto-resume-prohibited-v1",
                "savedAtUtc": utc_now(),
                "failureReceipt": str(failure_path),
                "failureSignature": value["failureSignature"],
                "reason": reason,
                "automaticMeasuredRetry": False,
                "immutable": True,
            },
            replace=False,
        )
    commits = sorted((control_root / "block-eligibility-commits").glob("p*.json"))
    manifest_path = control_root / "partial-formal-eligibility-manifest.json"
    manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-attempt4-partial-formal-block-eligibility-manifest-v1",
        "createdAtUtc": utc_now(),
        "executionReceiptSha256": receipt_sha,
        "status": TERMINAL_PARTIAL,
        "eligibleProcessCount": len(commits),
        "eligibleSampleCount": sum(int(read_json_retry(path)["completedSampleCount"]) for path in commits),
        "blockCommits": [
            {"relativePath": path.relative_to(formal_root).as_posix(), "sha256": base.sha256_file(path)} for path in commits
        ],
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }
    if not manifest_path.exists():
        base.atomic_json(manifest_path, manifest, replace=False)
    status.value.update(
        {
            "status": TERMINAL_PARTIAL,
            "completedProcessCount": int(frontier["completedProcessCount"]),
            "completedSampleCount": int(frontier["completedSampleCount"]),
            "eligibleProcessCount": int(frontier["completedProcessCount"]),
            "eligibleSampleCount": int(frontier["completedSampleCount"]),
            "errorReasonCode": reason,
            "failureCheckpointPath": str(failure_path),
        }
    )
    status.durable_checkpoint()
    status.publish()


def idempotent_commit_value(path: Path, fresh: dict[str, Any], timestamp_key: str) -> dict[str, Any]:
    """Reuse only an existing commit timestamp; verify every other byte anew."""
    if path.exists():
        existing = read_json_retry(path)
        if not isinstance(existing, dict) or timestamp_key not in existing:
            raise ContractError(f"COMMIT-TARGET-TIMESTAMP-MISSING:{path}:{timestamp_key}")
        fresh[timestamp_key] = existing[timestamp_key]
    return fresh


def raw_commit(
    *, project: Path, formal_root: Path, control_root: Path, receipt_sha: str,
    schedule: list[dict[str, Any]], overlay: list[dict[str, Any]], schedule_summary: dict[str, Any],
    status: StatusPublisher, resume_count: int
) -> dict[str, Any]:
    frontier = reconstruct_frontier(
        project=project, formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
        schedule=schedule, overlay=overlay, allow_promotion=False
    )
    if frontier["completedProcessCount"] != TOTAL_PROCESSES or frontier["completedSampleCount"] != TOTAL_SAMPLES:
        raise ContractError("RAW-COMMIT-INCOMPLETE-COUNTS")
    if base.current_unity_processes() or (project / "Temp/UnityLockfile").exists():
        raise ContractError("RAW-COMMIT-NOT-QUIESCENT")
    verified = base.verify_all_blocks(
        project=project, formal_root=formal_root, schedule=schedule,
        process_identity_root=control_root / "process-identities",
        progress=lambda _: status.publish(),
    )
    commits = sorted((control_root / "block-eligibility-commits").glob("p*.json"))
    if len(commits) != TOTAL_PROCESSES:
        raise ContractError("RAW-COMMIT-BLOCK-ELIGIBILITY-CARDINALITY")
    commit_manifest_path = formal_root / "block-formal-eligibility-manifest.json"
    commit_manifest = idempotent_commit_value(commit_manifest_path, {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-attempt4-block-formal-eligibility-manifest-v1",
        "createdAtUtc": utc_now(),
        "executionReceiptSha256": receipt_sha,
        "processCount": TOTAL_PROCESSES,
        "sampleCount": TOTAL_SAMPLES,
        "allCompletedBlocksFormallyEligible": True,
        "automaticResumeCount": resume_count,
        "blockCommits": [
            {"relativePath": path.relative_to(formal_root).as_posix(), "sha256": base.sha256_file(path)} for path in commits
        ],
    }, "createdAtUtc")
    base.atomic_create_or_verify(commit_manifest_path, commit_manifest)
    end_snapshot_path = formal_root / "environment-end-snapshot.json"
    end_snapshot = read_json_retry(end_snapshot_path) if end_snapshot_path.exists() else environment_snapshot()
    base.atomic_create_or_verify(end_snapshot_path, end_snapshot)
    block_manifest_path = formal_root / "raw-block-evidence-manifest.json"
    block_manifest = idempotent_commit_value(block_manifest_path, {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-formal-attempt4-block-evidence-manifest-v1",
        "createdAtUtc": utc_now(),
        "executionReceiptSha256": receipt_sha,
        "processCount": verified["processCount"],
        "sampleCount": verified["sampleCount"],
        "uniqueRunIdCount": verified["uniqueRunIdCount"],
        "blocks": verified["blockEvidence"],
    }, "createdAtUtc")
    base.atomic_create_or_verify(block_manifest_path, block_manifest)
    campaigns_root = formal_root / "campaigns"
    first = base.payload_snapshot(campaigns_root, progress=lambda _: status.publish())
    payload_manifest_path = formal_root / "raw-payload-file-manifest.jsonl"
    if not payload_manifest_path.exists():
        base.write_jsonl_atomic(payload_manifest_path, first["records"])
    else:
        expected_payload_manifest = "".join(
            json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
            for record in first["records"]
        ).encode("utf-8")
        if payload_manifest_path.read_bytes() != expected_payload_manifest:
            raise ContractError("RAW-PAYLOAD-FILE-MANIFEST-EXISTS-DIFFERENT")
    base.set_read_only(path for path in campaigns_root.rglob("*") if path.is_file())
    second = base.payload_snapshot(campaigns_root, progress=lambda _: status.publish())
    if (first["fileCount"], first["rawBytes"], first["canonicalTreeSha256"]) != (second["fileCount"], second["rawBytes"], second["canonicalTreeSha256"]):
        raise ContractError("RAW-TREE-MUTATION-DURING-FREEZE")
    raw_execution_path = formal_root / "raw-execution-manifest.json"
    raw_execution = idempotent_commit_value(raw_execution_path, {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-s48-h48-formal-raw-execution-manifest-attempt4-v1",
        "createdAtUtc": utc_now(),
        "terminalTokens": ["RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"],
        "formalAttemptOrdinal": 4,
        "executionReceiptSha256": receipt_sha,
        "campaignCount": TOTAL_CAMPAIGNS,
        "scenarioCount": TOTAL_SCENARIOS,
        "processCount": TOTAL_PROCESSES,
        "sampleCount": TOTAL_SAMPLES,
        "matchedSuperblockCount": TOTAL_MATCHED_SUPERBLOCKS,
        "scheduleSummary": schedule_summary,
        "rawPayloadRootRelativePath": "campaigns",
        "rawPayloadFileCount": second["fileCount"],
        "rawPayloadOriginalBytes": second["rawBytes"],
        "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
        "blockFormalEligibilityManifestSha256": base.sha256_file(commit_manifest_path),
        "rawBlockEvidenceManifestSha256": base.sha256_file(block_manifest_path),
        "environmentEndSnapshotSha256": base.sha256_file(end_snapshot_path),
        "perCompletedBlockFormalEligibility": True,
        "automaticResumeCount": resume_count,
        "phaseBFormalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }, "createdAtUtc")
    base.atomic_create_or_verify(raw_execution_path, raw_execution)
    freeze_path = formal_root / "raw-data-freeze-receipt.json"
    freeze = idempotent_commit_value(freeze_path, {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-s48-h48-formal-raw-data-freeze-receipt-attempt4-v1",
        "committedAtUtc": utc_now(),
        "status": "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE",
        "formalAttemptOrdinal": 4,
        "formalRoot": str(formal_root),
        "executionReceiptSha256": receipt_sha,
        "rawExecutionManifestSha256": base.sha256_file(raw_execution_path),
        "rawPayloadFileManifestSha256": base.sha256_file(payload_manifest_path),
        "blockFormalEligibilityManifestSha256": base.sha256_file(commit_manifest_path),
        "rawPayloadFileCount": second["fileCount"],
        "rawPayloadOriginalBytes": second["rawBytes"],
        "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
        "allPayloadFilesReadOnly": True,
        "allCompletedBlocksFormallyEligible": True,
        "analysisPending": True,
        "analysisAuthorized": False,
        "gate14RAuthorized": False,
    }, "committedAtUtc")
    base.atomic_create_or_verify(freeze_path, freeze)
    final_audit_path = formal_root / "formal-raw-ready-for-separate-analysis-authorization-audit.json"
    final_audit = idempotent_commit_value(final_audit_path, {
        "schemaVersion": 1,
        "auditKind": "gate13r-pr2-formal-attempt4-raw-ready-for-separate-analysis-authorization-v1",
        "savedAtUtc": utc_now(),
        "passed": True,
        "statusTokens": ["FORMAL-RAW-DATA-COMPLETE", "ALL-COMPLETED-BLOCKS-FORMALLY-ELIGIBLE", "ANALYSIS-PENDING", "IMMUTABLE", "FORMAL-STATISTICAL-ANALYSIS-NOT-AUTHORIZED", "GATE14R-NOT-AUTHORIZED"],
        "executionReceiptSha256": receipt_sha,
        "rawDataFreezeReceiptSha256": base.sha256_file(freeze_path),
        "processCount": TOTAL_PROCESSES,
        "sampleCount": TOTAL_SAMPLES,
        "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
        "automaticResumeCount": resume_count,
        "phaseBAnalysisExecuted": False,
        "gate14RExecuted": False,
    }, "savedAtUtc")
    base.atomic_create_or_verify(final_audit_path, final_audit)
    base.set_read_only((end_snapshot_path, block_manifest_path, commit_manifest_path, payload_manifest_path, raw_execution_path, freeze_path, final_audit_path))
    status.value.update(
        {
            "status": RAW_COMPLETE,
            "completedProcessCount": TOTAL_PROCESSES,
            "completedSampleCount": TOTAL_SAMPLES,
            "eligibleProcessCount": TOTAL_PROCESSES,
            "eligibleSampleCount": TOTAL_SAMPLES,
            "currentGlobalProcessOrdinal": None,
            "currentCampaignId": None,
            "currentScenarioId": None,
            "currentCohort": None,
            "currentBlockId": None,
            "currentMatchedSuperblockId": None,
            "currentABBAOrder": None,
            "currentWilliamsRow": None,
            "currentUnityProcessId": None,
            "currentUnityProcessStartedAtUtc": None,
            "currentUnityBlockStartedAtUtc": None,
            "latestWorkingSetBytes": None,
            "latestPrivateMemoryBytes": None,
            "latestAvailablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
            "outputFileCount": int(second["fileCount"]),
            "rawBytes": int(second["rawBytes"]),
            "rawDataComplete": True,
            "errorReasonCode": None,
            "failureCheckpointPath": None,
        }
    )
    status.durable_checkpoint()
    status.publish()
    return {"rawPayloadFileCount": second["fileCount"], "rawPayloadOriginalBytes": second["rawBytes"], "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"], "rawDataFreezeReceipt": str(freeze_path), "finalAudit": str(final_audit_path)}


def initialize_roots(formal_root: Path) -> Path:
    control_root = formal_root / "_control"
    for path in (
        control_root,
        formal_root / "_plans",
        control_root / "process-identities",
        control_root / "block-eligibility-commits",
        control_root / "block-wrapper-logs",
        control_root / "block-events",
        control_root / "execution-sessions",
        control_root / "session-failures",
        control_root / "resume-events",
        control_root / "status-publication-events",
        control_root / "raw-commit-attempts",
    ):
        path.mkdir(parents=True, exist_ok=True)
    return control_root


def inspect_resume(project: Path, *, quiescence_timeout_seconds: int) -> dict[str, Any]:
    formal_root = project_path(project, FORMAL_ROOT_REL)
    if not formal_root.is_dir() or not project_path(project, RECEIPT_REL).is_file():
        raise UnsafeResume("ATTEMPT4-NOT-COMMITTED")
    control_root = formal_root / "_control"
    if (control_root / "resume-prohibited.json").exists():
        raise UnsafeResume("ATTEMPT4-RESUME-PROHIBITED")
    status_path = project_path(project, STATUS_REL)
    if status_path.is_file():
        terminal_status = read_json_retry(status_path).get("status")
        if terminal_status in {RAW_COMPLETE, TERMINAL_PARTIAL, "USER-ACTION-REQUIRED"}:
            raise UnsafeResume(f"ATTEMPT4-TERMINAL-STATUS:{terminal_status}")
    events = resume_event_paths(control_root)
    if len(events) >= MAX_AUTO_RESUMES:
        raise UnsafeResume("ATTEMPT4-AUTO-RESUME-LIMIT")
    failures = session_failure_paths(control_root)
    if len(failures) >= 2:
        latest = read_json_retry(failures[-1]).get("failureSignature")
        previous = read_json_retry(failures[-2]).get("failureSignature")
        if latest and latest == previous:
            raise UnsafeResume(f"ATTEMPT4-REPEATED-SESSION-FAILURE-SIGNATURE:{latest}")
    wait_for_quiescence(project, quiescence_timeout_seconds)
    receipt_path, receipt_sha, receipt = validate_receipt(project)
    schedule, overlay, _ = base.validate_schedule(project)
    frontier = reconstruct_frontier(
        project=project, formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
        schedule=schedule, overlay=overlay, allow_promotion=False
    )
    return {
        "schemaVersion": 1,
        "decisionKind": "gate13r-pr2-attempt4-auto-resume-inspection-v1",
        "inspectedAtUtc": utc_now(),
        "decision": "AUTO-RESUME-SAFE",
        "automaticResumeCountBefore": len(events),
        "automaticResumeCountAfter": len(events) + 1,
        "maximumAutomaticResumeCount": MAX_AUTO_RESUMES,
        "frontier": frontier,
        "promotionRequired": frontier["promotionRequired"],
        "automaticMeasuredRetry": False,
        "receiptSha256": receipt_sha,
        "receiptCreatedAtUtc": receipt["createdAtUtc"],
    }


def run_or_resume(args: argparse.Namespace) -> int:
    project = Path(args.project_root).resolve()
    unity_path = Path(args.unity_path).resolve()
    powershell_path = Path(args.powershell_path).resolve()
    prelaunch_final_audit = Path(args.prelaunch_final_audit).resolve()
    if not unity_path.is_file() or not powershell_path.is_file() or not prelaunch_final_audit.is_file():
        raise ContractError("ATTEMPT4-RUNTIME-INPUT-MISSING")
    formal_root = project_path(project, FORMAL_ROOT_REL)
    first_session = not formal_root.exists()
    if first_session:
        receipt_path, receipt_sha, started_at = create_receipt(
            project=project, prelaunch_final_audit=prelaunch_final_audit,
            unity_path=unity_path, powershell_path=powershell_path
        )
        control_root = initialize_roots(formal_root)
        resume_count = 0
        status = StatusPublisher(project, receipt_sha, started_at, control_root, resume_count=0)
        status.publish(create=True)
        core = validate_prelaunch(project, require_targets_absent=False)
        base.atomic_json(control_root / "launch-core-validation.json", core, replace=False)
    else:
        decision = inspect_resume(project, quiescence_timeout_seconds=int(args.resume_quiescence_timeout_seconds))
        receipt_path, receipt_sha, receipt = validate_receipt(project)
        started_at = str(receipt["createdAtUtc"])
        control_root = initialize_roots(formal_root)
        resume_count = int(decision["automaticResumeCountAfter"])
        event_path = control_root / "resume-events" / f"r{resume_count:02d}.json"
        decision["resumeEventKind"] = "gate13r-pr2-attempt4-bounded-auto-resume-event-v1"
        base.atomic_json(event_path, decision, replace=False)
        status = StatusPublisher(project, receipt_sha, started_at, control_root, resume_count=resume_count)
        status.value["status"] = "AUTO-RESUME-VALIDATING"
        status.publish()
    schedule, overlay, schedule_summary = base.validate_schedule(project)
    frontier = reconstruct_frontier(
        project=project, formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
        schedule=schedule, overlay=overlay, allow_promotion=not first_session
    )
    if not first_session and frontier.get("promotedGlobalProcessOrdinal") is not None:
        resume_event = read_json_retry(control_root / "resume-events" / f"r{resume_count:02d}.json")
        resume_event["promotedGlobalProcessOrdinal"] = frontier["promotedGlobalProcessOrdinal"]
        # Preserve the original inspection event and add a separate promotion receipt.
        base.atomic_json(
            control_root / "resume-events" / f"r{resume_count:02d}-promotion.json",
            {
                "schemaVersion": 1,
                "receiptKind": "gate13r-pr2-attempt4-complete-uncommitted-block-promotion-v1",
                "savedAtUtc": utc_now(),
                "resumeEvent": f"r{resume_count:02d}.json",
                "promotedGlobalProcessOrdinal": frontier["promotedGlobalProcessOrdinal"],
                "automaticMeasuredRetry": False,
            },
            replace=False,
        )
    session_path = write_session_start(control_root, resume_count, frontier)
    status.value.update(
        {
            "status": "ACQUISITION-RUNNING" if first_session else "AUTO-RESUME-RUNNING",
            "automaticResumeCount": resume_count,
            "completedProcessCount": int(frontier["completedProcessCount"]),
            "completedSampleCount": int(frontier["completedSampleCount"]),
            "eligibleProcessCount": int(frontier["completedProcessCount"]),
            "eligibleSampleCount": int(frontier["completedSampleCount"]),
            "outputFileCount": int(frontier["outputFileCount"]),
            "rawBytes": int(frontier["rawBytes"]),
            "advisoryCrossingCount": int(frontier["advisoryCrossingCount"]),
        }
    )
    if frontier["lastCommitPath"]:
        last_commit = Path(frontier["lastCommitPath"])
        status.value["lastBlockEligibilityCommitPath"] = str(last_commit)
        status.value["lastBlockEligibilityCommitSha256"] = base.sha256_file(last_commit)
    status.durable_checkpoint()
    status.publish()
    next_ordinal = frontier["nextGlobalProcessOrdinal"]
    if next_ordinal is not None:
        for record, policy in zip(schedule[next_ordinal - 1 :], overlay[next_ordinal - 1 :], strict=True):
            ordinal = int(record["globalProcessOrdinal"])
            paths = block_paths(formal_root, control_root, record)
            expected_plan = base.make_plan(project, record, policy, formal=True, receipt_sha256=receipt_sha)
            if paths["plan"].exists():
                verify_plan(project, record, policy, paths["plan"], receipt_sha)
            else:
                base.atomic_json(paths["plan"], expected_plan, replace=False)
            before_path = control_root / "block-events" / f"p{ordinal:06d}-before.json"
            base.atomic_json(
                before_path,
                {
                    "schemaVersion": 1,
                    "eventKind": "gate13r-pr2-attempt4-before-block-v1",
                    "savedAtUtc": utc_now(),
                    "globalProcessOrdinal": ordinal,
                    "blockId": record["blockId"],
                    "completedProcessCountBefore": int(frontier["completedProcessCount"]),
                    "automaticResumeCount": resume_count,
                },
                replace=False,
            )
            apply_record(status.value, record)
            status.value["status"] = "ACQUISITION-RUNNING"
            status.durable_checkpoint()
            status.publish()
            try:
                result = execute_block(
                    project=project, formal_root=formal_root, receipt_path=receipt_path, record=record,
                    plan_path=paths["plan"], unity_path=unity_path, powershell_path=powershell_path,
                    block_timeout_seconds=int(args.block_timeout_seconds), status=status, control_root=control_root
                )
            except BaseException as error:
                preserve_hard_failure(
                    project=project, formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
                    status=status, frontier=frontier, record=record, error=error
                )
                raise
            commit_path, commit = create_block_commit(
                formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
                record=record, result=result, recovered=False
            )
            frontier["completedProcessCount"] += 1
            frontier["completedSampleCount"] += int(record["expectedSampleCount"])
            frontier["outputFileCount"] += int(commit["blockRawFileCount"])
            frontier["rawBytes"] += int(commit["blockRawBytes"])
            frontier["advisoryCrossingCount"] += int(result["manifest"].get("nativeAdvisoryBoundaryCount", 0))
            frontier["lastCommitPath"] = str(commit_path)
            status.value.update(
                {
                    "completedProcessCount": int(frontier["completedProcessCount"]),
                    "completedSampleCount": int(frontier["completedSampleCount"]),
                    "eligibleProcessCount": int(frontier["completedProcessCount"]),
                    "eligibleSampleCount": int(frontier["completedSampleCount"]),
                    "outputFileCount": int(frontier["outputFileCount"]),
                    "rawBytes": int(frontier["rawBytes"]),
                    "advisoryCrossingCount": int(frontier["advisoryCrossingCount"]),
                    "lastBlockEligibilityCommitPath": str(commit_path),
                    "lastBlockEligibilityCommitSha256": base.sha256_file(commit_path),
                }
            )
            status.durable_checkpoint()
            status.publish()
    if int(frontier["completedProcessCount"]) != TOTAL_PROCESSES or int(frontier["completedSampleCount"]) != TOTAL_SAMPLES:
        raise ContractError("ATTEMPT4-ACQUISITION-TERMINAL-CARDINALITY")
    status.value["status"] = "ACQUISITION-COMPLETE-COMMIT-PENDING"
    status.durable_checkpoint()
    status.publish()
    signatures: list[str] = []
    commit_result: dict[str, Any] | None = None
    for attempt in range(1, 4):
        attempt_root = control_root / "raw-commit-attempts" / f"attempt-{attempt}"
        attempt_root.mkdir(parents=True, exist_ok=True)
        try:
            if attempt > 1:
                status.value["status"] = "RAW-COMMIT-RECOVERY"
                status.publish()
            commit_result = raw_commit(
                project=project, formal_root=formal_root, control_root=control_root, receipt_sha=receipt_sha,
                schedule=schedule, overlay=overlay, schedule_summary=schedule_summary, status=status,
                resume_count=resume_count
            )
            base.atomic_json(attempt_root / "pass-receipt.json", {"schemaVersion": 1, "receiptKind": "gate13r-pr2-attempt4-raw-commit-pass-v1", "attempt": attempt, "savedAtUtc": utc_now(), "passed": True, "result": commit_result}, replace=False)
            break
        except Exception as error:
            signature = base.failure_signature(error)
            signatures.append(signature)
            base.atomic_json(attempt_root / "failure-receipt.json", {"schemaVersion": 1, "receiptKind": "gate13r-pr2-attempt4-raw-commit-failure-v1", "attempt": attempt, "savedAtUtc": utc_now(), "passed": False, "failureSignature": signature, "error": "".join(traceback.format_exception(type(error), error, error.__traceback__)), "unityRerunAuthorized": False}, replace=False)
            if signatures.count(signature) >= 2 or attempt >= 3:
                status.value["status"] = "USER-ACTION-REQUIRED"
                status.value["errorReasonCode"] = f"RAW-COMMIT:{type(error).__name__}:{error}"
                status.publish()
                prohibit_path = control_root / "resume-prohibited.json"
                if not prohibit_path.exists():
                    base.atomic_json(
                        prohibit_path,
                        {
                            "schemaVersion": 1,
                            "stateKind": "gate13r-pr2-attempt4-raw-commit-auto-resume-prohibited-v1",
                            "savedAtUtc": utc_now(),
                            "failureSignature": signature,
                            "rawCommitAttempt": attempt,
                            "sameSignatureCount": signatures.count(signature),
                            "automaticUnityRerun": False,
                            "automaticResume": False,
                            "userActionRequired": True,
                            "immutable": True,
                        },
                        replace=False,
                    )
                raise
            if base.current_unity_processes() or (project / "Temp/UnityLockfile").exists():
                raise ContractError("RAW-COMMIT-RECOVERY-NOT-QUIESCENT") from error
            time.sleep(2)
    if commit_result is None:
        raise ContractError("RAW-COMMIT-NO-SUCCESS-RESULT")
    base.atomic_json(
        control_root / "execution-sessions" / f"s{resume_count + 1:02d}-end.json",
        {"schemaVersion": 1, "receiptKind": "gate13r-pr2-attempt4-execution-session-end-v1", "savedAtUtc": utc_now(), "sessionStart": str(session_path), "status": RAW_COMPLETE, "completedProcessCount": TOTAL_PROCESSES, "completedSampleCount": TOTAL_SAMPLES},
        replace=False,
    )
    print(json.dumps({"passed": True, "status": RAW_COMPLETE, "result": commit_result}, ensure_ascii=False, sort_keys=True))
    return 0


def command_validate(args: argparse.Namespace) -> int:
    result = validate_prelaunch(Path(args.project_root), require_targets_absent=not args.allow_targets)
    if args.output:
        base.atomic_json(Path(args.output), result, replace=False)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def command_plan(args: argparse.Namespace) -> int:
    project = Path(args.project_root).resolve()
    schedule, overlay, _ = base.validate_schedule(project)
    ordinal = int(args.ordinal)
    if not 1 <= ordinal <= TOTAL_PROCESSES:
        raise ContractError(f"ORDINAL-OUT-OF-RANGE:{ordinal}")
    plan = base.make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
    if args.output:
        base.atomic_json(Path(args.output), plan, replace=False)
    print(json.dumps(plan, ensure_ascii=False, sort_keys=True))
    return 0


def command_inspect(args: argparse.Namespace) -> int:
    result = inspect_resume(Path(args.project_root).resolve(), quiescence_timeout_seconds=int(args.resume_quiescence_timeout_seconds))
    if args.output:
        base.atomic_json(Path(args.output), result, replace=False)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("--project-root", required=True)
    validate.add_argument("--output")
    validate.add_argument("--allow-targets", action="store_true")
    validate.set_defaults(func=command_validate)
    plan = sub.add_parser("plan")
    plan.add_argument("--project-root", required=True)
    plan.add_argument("--ordinal", type=int, required=True)
    plan.add_argument("--output")
    plan.set_defaults(func=command_plan)
    inspect = sub.add_parser("inspect-resume")
    inspect.add_argument("--project-root", required=True)
    inspect.add_argument("--resume-quiescence-timeout-seconds", type=int, default=3600)
    inspect.add_argument("--output")
    inspect.set_defaults(func=command_inspect)
    run = sub.add_parser("run")
    run.add_argument("--project-root", required=True)
    run.add_argument("--prelaunch-final-audit", required=True)
    run.add_argument("--unity-path", required=True)
    run.add_argument("--powershell-path", required=True)
    run.add_argument("--block-timeout-seconds", type=int, default=3600)
    run.add_argument("--resume-quiescence-timeout-seconds", type=int, default=3600)
    run.set_defaults(func=run_or_resume)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except BaseException as error:
        if getattr(args, "command", None) == "run":
            try:
                record_outer_run_failure(Path(args.project_root).resolve(), error)
            except Exception as ledger_error:
                print(f"SESSION-FAILURE-LEDGER:{type(ledger_error).__name__}:{ledger_error}", file=sys.stderr)
        print(f"{type(error).__name__}:{error}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
