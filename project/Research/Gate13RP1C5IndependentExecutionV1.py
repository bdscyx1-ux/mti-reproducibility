#!/usr/bin/env python3
"""Fail-closed serial executor for Gate 13R P1-C5 independent Phase A.

No resume, retry, replacement, top-up, reordering, Phase B analysis, M1-M5, or
Gate 14R action is implemented by this program.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


CONTRACT_REL = "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json"
FORMAL_ROOT_REL = "Research/FormalRuns/Gate13R_P1C5_Independent/v1"
RECEIPT_REL = "Research/Gate13R_P1C5_Independent_Execution_Receipt.v1.json"
SCHEDULE_REL = "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl"
PLAN_BUILDER_REL = "Research/New-Gate13RP1C5IndependentBlockPlanV1.py"
BLOCK_WRAPPER_REL = "Research/Run-Gate13RP1C5IndependentBlockV1.ps1"
EXPECTED_PROCESSES = 1600
EXPECTED_SAMPLES = 3200


class ExecutionError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def atomic_replace_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".g13r-p1c5-status-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(json_bytes(value))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def create_json(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    if not path.parent.is_dir():
        raise FileNotFoundError(path.parent)
    data = json_bytes(value)
    descriptor, temporary = tempfile.mkstemp(prefix=".g13r-p1c5-create-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ExecutionError(f"expected JSON object: {path}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for line_number, line in enumerate(stream, start=1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ExecutionError(f"non-object JSONL record at {path}:{line_number}")
            yield value


def project_path(project: Path, relative: str) -> Path:
    candidate = (project / relative).resolve()
    try:
        candidate.relative_to(project)
    except ValueError as error:
        raise ExecutionError(f"path escapes project: {relative}") from error
    return candidate


def verify_binding(project: Path, binding: dict[str, Any], label: str) -> Path:
    path = project_path(project, str(binding["relativePath"]))
    if not path.is_file():
        raise ExecutionError(f"bound {label} is missing: {path}")
    actual = sha256_file(path)
    if actual != str(binding["sha256"]):
        raise ExecutionError(f"bound {label} SHA-256 mismatch: {path}")
    return path


def load_contract(project: Path, expected_sha256: str) -> tuple[Path, dict[str, Any]]:
    path = project / CONTRACT_REL
    if not path.is_file():
        raise ExecutionError(f"execution contract is missing: {path}")
    actual = sha256_file(path)
    if actual != expected_sha256:
        raise ExecutionError("execution contract SHA-256 mismatch")
    contract = load_json(path)
    if contract.get("contractKind") != "GATE13R-P1C5-INDEPENDENT-FROZEN-EXECUTION-CONTRACT":
        raise ExecutionError("execution contract identity mismatch")
    if contract.get("status") != "FROZEN-PRELAUNCH-NOT-EXECUTED":
        raise ExecutionError("execution contract status does not permit a first launch")
    if contract.get("formalRootRelativePath") != FORMAL_ROOT_REL:
        raise ExecutionError("formal root differs from frozen contract")
    if contract.get("receiptRelativePath") != RECEIPT_REL:
        raise ExecutionError("receipt path differs from frozen contract")
    if contract.get("phaseBAnalysisAuthorized") is not False:
        raise ExecutionError("Phase B must remain unauthorized at Phase A launch")
    if contract.get("gate14RAuthorized") is not False or contract.get("m1ThroughM5Authorized") is not False:
        raise ExecutionError("Gate 14R and M1-M5 must remain unauthorized")
    if contract.get("automaticRetryAuthorized") is not False or contract.get("automaticResumeAuthorized") is not False:
        raise ExecutionError("automatic retry/resume must remain unauthorized")
    bindings = contract.get("bindings")
    if not isinstance(bindings, dict) or not bindings:
        raise ExecutionError("contract bindings are missing")
    for label, binding in bindings.items():
        verify_binding(project, binding, label)
    return path, contract


def load_schedule(project: Path, contract: dict[str, Any]) -> list[dict[str, Any]]:
    schedule_path = project / SCHEDULE_REL
    schedule_binding = contract["bindings"]["schedule"]
    if sha256_file(schedule_path) != schedule_binding["sha256"]:
        raise ExecutionError("schedule hash mismatch")
    records = list(iter_jsonl(schedule_path))
    if len(records) != EXPECTED_PROCESSES:
        raise ExecutionError(f"expected {EXPECTED_PROCESSES} process records, found {len(records)}")
    seen_blocks: set[str] = set()
    seen_runs: set[str] = set()
    campaign_counts: dict[str, int] = {}
    for ordinal, record in enumerate(records, start=1):
        if int(record.get("globalProcessOrdinal", 0)) != ordinal:
            raise ExecutionError(f"schedule ordinal mismatch at line {ordinal}")
        if record.get("comparisonCohortId") != "p1-c5-shared-goal-v1":
            raise ExecutionError(f"unexpected cohort at line {ordinal}")
        if record.get("freshProcessRequired") is not True or int(record.get("maximumBlocksInProcess", 0)) != 1:
            raise ExecutionError(f"fresh-process invariant failed at line {ordinal}")
        entries = record.get("entries")
        if not isinstance(entries, list) or len(entries) != 2:
            raise ExecutionError(f"paired-block cardinality failed at line {ordinal}")
        expected_order = ["C-FF", "IDFF"] if int(record["williamsRowIndex"]) == 0 else ["IDFF", "C-FF"]
        if [entry.get("algorithmId") for entry in entries] != expected_order:
            raise ExecutionError(f"AB/BA order mismatch at line {ordinal}")
        block_id = str(record["blockId"])
        if block_id in seen_blocks:
            raise ExecutionError(f"duplicate block identity: {block_id}")
        seen_blocks.add(block_id)
        for entry in entries:
            run_id = str(entry["runId"])
            if run_id in seen_runs:
                raise ExecutionError(f"duplicate run identity: {run_id}")
            seen_runs.add(run_id)
        campaign = str(record["campaignId"])
        campaign_counts[campaign] = campaign_counts.get(campaign, 0) + 1
    if len(campaign_counts) != 32 or set(campaign_counts.values()) != {50}:
        raise ExecutionError("schedule must contain exactly 32 campaigns with 50 blocks each")
    if len(seen_runs) != EXPECTED_SAMPLES:
        raise ExecutionError("schedule sample cardinality mismatch")
    return records


def validate_prelaunch(
    project: Path,
    contract_sha256: str,
    *,
    require_targets_absent: bool,
) -> dict[str, Any]:
    contract_path, contract = load_contract(project, contract_sha256)
    records = load_schedule(project, contract)
    formal_root = project / FORMAL_ROOT_REL
    receipt = project / RECEIPT_REL
    targets_absent = not formal_root.exists() and not receipt.exists()
    if require_targets_absent and not targets_absent:
        raise ExecutionError("fresh formal root and receipt must both be absent")
    if (project / "Temp/UnityLockfile").exists():
        raise ExecutionError("Unity project lock is present")
    return {
        "passed": True,
        "contractPath": str(contract_path),
        "contractSha256": contract_sha256,
        "formalTargetsAbsent": targets_absent,
        "processCount": len(records),
        "sampleCount": sum(len(record["entries"]) for record in records),
        "campaignCount": len({record["campaignId"] for record in records}),
        "blocksPerCampaign": 50,
        "automaticRetryAuthorized": False,
        "automaticResumeAuthorized": False,
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
        "unityInvoked": False,
    }


def verify_preflight_report(path: Path, expected_sha256: str, contract_sha256: str) -> dict[str, Any]:
    if not path.is_file() or sha256_file(path) != expected_sha256:
        raise ExecutionError("preflight report path/hash mismatch")
    report = load_json(path)
    if report.get("passed") is not True or report.get("unityInvoked") is not False:
        raise ExecutionError("preflight report did not pass as a no-Unity audit")
    if report.get("formalTargetsAbsent") is not True:
        raise ExecutionError("preflight did not establish fresh target absence")
    if report.get("executionContractSha256") != contract_sha256:
        raise ExecutionError("preflight report is not bound to this contract")
    return report


def status_value(started_at: str, completed: int, total: int, current: dict[str, Any] | None, status: str) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "statusKind": "gate13r-p1c5-independent-phase-a-status-v1",
        "studyId": "Gate13R-P1C5-Independent-v1",
        "status": status,
        "startedAtUtc": started_at,
        "updatedAtUtc": utc_now(),
        "completedUnityProcesses": completed,
        "eligibleUnityProcesses": completed,
        "totalUnityProcesses": total,
        "completedAlgorithmSamples": completed * 2,
        "totalAlgorithmSamples": total * 2,
        "currentGlobalProcessOrdinal": None if current is None else current["globalProcessOrdinal"],
        "currentCampaignId": None if current is None else current["campaignId"],
        "currentBlockId": None if current is None else current["blockId"],
        "currentOrderLabel": None if current is None else current["orderLabel"],
        "automaticRetryCount": 0,
        "automaticResumeCount": 0,
        "phaseBAnalysisExecuted": False,
        "gate14RExecuted": False,
        "m1ThroughM5Executed": False,
    }


def verify_completed_block(
    formal_root: Path,
    output: Path,
    plan_path: Path,
    record: dict[str, Any],
    seen_process_identities: set[tuple[int, str]],
) -> dict[str, Any]:
    manifest_path = output / "block-manifest.json"
    checkpoint_path = output / "block-checkpoint.json"
    if not manifest_path.is_file() or not checkpoint_path.is_file():
        raise ExecutionError(f"block terminal artifacts are missing: {record['blockId']}")
    manifest = load_json(manifest_path)
    checkpoint = load_json(checkpoint_path)
    if manifest.get("manifestKind") != "gate13r-p1c5-independent-formal-block-manifest-v1":
        raise ExecutionError("block manifest identity mismatch")
    if manifest.get("executionDesignId") != "gate13r-p1c5-independent-confirmatory-study-v1":
        raise ExecutionError("block design identity mismatch")
    for key in ("blockId", "campaignId", "comparisonCohortId"):
        if str(manifest.get(key)) != str(record.get(key)):
            raise ExecutionError(f"block manifest {key} mismatch")
    if manifest.get("completed") is not True or manifest.get("formalCampaign") is not True:
        raise ExecutionError("block is not formally complete")
    if manifest.get("hardMemoryRulesPassed") is not True or manifest.get("nativeHardCrossed") is not False:
        raise ExecutionError("block failed a hard memory rule")
    if int(manifest.get("expectedSampleCount", 0)) != 2 or int(manifest.get("completedSampleCount", 0)) != 2:
        raise ExecutionError("block sample cardinality mismatch")
    if checkpoint.get("status") != "block-completed":
        raise ExecutionError("block checkpoint is not terminal-complete")
    if manifest.get("blockPlanSha256") != sha256_file(plan_path):
        raise ExecutionError("block manifest plan hash mismatch")
    samples = manifest.get("samples")
    if not isinstance(samples, list) or [item.get("algorithmId") for item in samples] != [entry["algorithmId"] for entry in record["entries"]]:
        raise ExecutionError("block sample order mismatch")
    if [item.get("runId") for item in samples] != [entry["runId"] for entry in record["entries"]]:
        raise ExecutionError("block run identity mismatch")
    identity = (int(manifest["processId"]), str(manifest["processStartTimeUtc"]))
    if identity in seen_process_identities:
        raise ExecutionError("fresh Unity process identity was reused")
    seen_process_identities.add(identity)
    for sample in samples:
        if int(sample["processId"]) != identity[0] or sample.get("completed") is not True:
            raise ExecutionError("sample process/completion identity mismatch")
        if sample.get("memoryGateVerdict") != "PASS":
            raise ExecutionError("sample memory gate did not pass")
        for relative_key, sha_key in (
            ("manifestRelativePath", "manifestSha256"),
            ("summaryRelativePath", "summarySha256"),
            ("workloadResultRelativePath", "workloadResultSha256"),
        ):
            candidate = (output / str(sample[relative_key])).resolve()
            try:
                candidate.relative_to(output.resolve())
            except ValueError as error:
                raise ExecutionError("sample payload path escapes block") from error
            if not candidate.is_file() or sha256_file(candidate) != sample[sha_key]:
                raise ExecutionError(f"sample payload hash mismatch: {candidate}")
    return {
        "schemaVersion": 1,
        "commitKind": "gate13r-p1c5-independent-block-eligibility-commit-v1",
        "committedAtUtc": utc_now(),
        "globalProcessOrdinal": record["globalProcessOrdinal"],
        "blockId": record["blockId"],
        "campaignId": record["campaignId"],
        "orderLabel": record["orderLabel"],
        "blockPlanRelativePath": plan_path.relative_to(formal_root).as_posix(),
        "blockPlanSha256": sha256_file(plan_path),
        "blockManifestRelativePath": manifest_path.relative_to(formal_root).as_posix(),
        "blockManifestSha256": sha256_file(manifest_path),
        "processId": identity[0],
        "processStartTimeUtc": identity[1],
        "formalStatisticalEligibility": True,
    }


def write_raw_commit(formal_root: Path, schedule_sha256: str, completed: int) -> dict[str, Any]:
    manifest_path = formal_root / "_control/raw-payload-manifest.jsonl"
    payload_files = sorted(
        path for path in (formal_root / "campaigns").rglob("*") if path.is_file()
    )
    lines: list[bytes] = []
    total_bytes = 0
    for path in payload_files:
        size = path.stat().st_size
        total_bytes += size
        item = {
            "relativePath": path.relative_to(formal_root).as_posix(),
            "bytes": size,
            "sha256": sha256_file(path),
        }
        lines.append((json.dumps(item, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))
    if manifest_path.exists():
        raise ExecutionError("raw payload manifest already exists")
    manifest_path.write_bytes(b"".join(lines))
    complete = {
        "schemaVersion": 1,
        "commitKind": "gate13r-p1c5-independent-raw-data-complete-v1",
        "status": "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE",
        "committedAtUtc": utc_now(),
        "completedUnityProcesses": completed,
        "completedAlgorithmSamples": completed * 2,
        "scheduleSha256": schedule_sha256,
        "payloadFileCount": len(payload_files),
        "payloadBytes": total_bytes,
        "payloadManifestRelativePath": manifest_path.relative_to(formal_root).as_posix(),
        "payloadManifestSha256": sha256_file(manifest_path),
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
    }
    create_json(formal_root / "raw-data-complete.json", complete)
    return complete


def run(args: argparse.Namespace) -> int:
    project = Path(args.project_root).resolve()
    preflight_path = Path(args.preflight_report).resolve()
    validate_prelaunch(project, args.contract_sha256, require_targets_absent=True)
    verify_preflight_report(preflight_path, args.preflight_report_sha256, args.contract_sha256)
    schedule = load_schedule(project, load_contract(project, args.contract_sha256)[1])
    formal_root = project / FORMAL_ROOT_REL
    receipt_path = project / RECEIPT_REL
    formal_root.mkdir(parents=True, exist_ok=False)
    control_root = formal_root / "_control"
    for directory in (
        control_root,
        control_root / "plans",
        control_root / "block-wrapper-logs",
        control_root / "block-eligibility-commits",
    ):
        directory.mkdir(exist_ok=True)
    receipt = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-p1c5-independent-phase-a-execution-receipt-v1",
        "studyId": "Gate13R-P1C5-Independent-v1",
        "createdAtUtc": utc_now(),
        "executionContractRelativePath": CONTRACT_REL,
        "executionContractSha256": args.contract_sha256,
        "preflightReportPath": str(preflight_path),
        "preflightReportSha256": args.preflight_report_sha256,
        "scheduleRelativePath": SCHEDULE_REL,
        "scheduleSha256": sha256_file(project / SCHEDULE_REL),
        "unityPath": str(Path(args.unity_path).resolve()),
        "powershellPath": str(Path(args.powershell_path).resolve()),
        "blockTimeoutSeconds": args.block_timeout_seconds,
        "overallTimeoutSeconds": args.overall_timeout_seconds,
        "automaticRetryAuthorized": False,
        "automaticResumeAuthorized": False,
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
    }
    create_json(receipt_path, receipt)
    started_at = utc_now()
    status_path = control_root / "execution-status.json"
    atomic_replace_json(status_path, status_value(started_at, 0, len(schedule), schedule[0], "ACQUISITION-RUNNING"))
    deadline = time.monotonic() + args.overall_timeout_seconds
    seen_process_identities: set[tuple[int, str]] = set()
    completed = 0
    try:
        for record in schedule:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ExecutionError("overall hard timeout reached before next block")
            effective_timeout = min(args.block_timeout_seconds, max(1, int(remaining)))
            ordinal = int(record["globalProcessOrdinal"])
            plan_path = control_root / "plans" / f"p{ordinal:04d}.json"
            output = project_path(formal_root, str(record["outputRelativePath"]))
            atomic_replace_json(status_path, status_value(started_at, completed, len(schedule), record, "ACQUISITION-RUNNING"))
            builder_command = [
                sys.executable,
                str(project / PLAN_BUILDER_REL),
                "--project-root", str(project),
                "--global-process-ordinal", str(ordinal),
                "--output", str(plan_path),
                "--receipt", str(receipt_path),
            ]
            builder = subprocess.run(builder_command, capture_output=True, text=True, check=False)
            if builder.returncode != 0:
                raise ExecutionError(f"block-plan builder failed at ordinal {ordinal}: {builder.stderr.strip()}")
            wrapper_command = [
                str(Path(args.powershell_path).resolve()),
                "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", str(project / BLOCK_WRAPPER_REL),
                "-ProjectPath", str(project),
                "-BlockPlanPath", str(plan_path),
                "-OutputDirectory", str(output),
                "-AllowedRoot", str(formal_root),
                "-ExecutionReceiptPath", str(receipt_path),
                "-UnityPath", str(Path(args.unity_path).resolve()),
                "-TimeoutSeconds", str(effective_timeout),
            ]
            wrapper = subprocess.run(wrapper_command, capture_output=True, text=True, check=False)
            (control_root / "block-wrapper-logs" / f"p{ordinal:04d}.stdout.txt").write_text(wrapper.stdout, encoding="utf-8")
            (control_root / "block-wrapper-logs" / f"p{ordinal:04d}.stderr.txt").write_text(wrapper.stderr, encoding="utf-8")
            if wrapper.returncode != 0:
                raise ExecutionError(f"block wrapper failed at ordinal {ordinal} with exit {wrapper.returncode}")
            commit = verify_completed_block(formal_root, output, plan_path, record, seen_process_identities)
            create_json(control_root / "block-eligibility-commits" / f"p{ordinal:04d}.json", commit)
            completed += 1
        raw_commit = write_raw_commit(formal_root, sha256_file(project / SCHEDULE_REL), completed)
        atomic_replace_json(status_path, status_value(started_at, completed, len(schedule), None, raw_commit["status"]))
        print(json.dumps({"passed": True, "status": raw_commit["status"], "completedUnityProcesses": completed, "rawCommit": str(formal_root / "raw-data-complete.json")}, sort_keys=True))
        return 0
    except BaseException as error:
        failure = {
            "schemaVersion": 1,
            "failureKind": "gate13r-p1c5-independent-phase-a-hard-failure-v1",
            "failedAtUtc": utc_now(),
            "exceptionType": type(error).__name__,
            "message": str(error),
            "completedUnityProcesses": completed,
            "automaticRetryAttempted": False,
            "automaticResumeAttempted": False,
            "userActionRequired": True,
        }
        failure_path = control_root / "failure.json"
        if not failure_path.exists():
            create_json(failure_path, failure)
        atomic_replace_json(status_path, status_value(started_at, completed, len(schedule), None, "HARD-FAILURE-USER-ACTION-REQUIRED"))
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--project-root", required=True)
    validate_parser.add_argument("--contract-sha256", required=True)
    validate_parser.add_argument("--output", default="")
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--project-root", required=True)
    run_parser.add_argument("--contract-sha256", required=True)
    run_parser.add_argument("--preflight-report", required=True)
    run_parser.add_argument("--preflight-report-sha256", required=True)
    run_parser.add_argument("--unity-path", required=True)
    run_parser.add_argument("--powershell-path", required=True)
    run_parser.add_argument("--block-timeout-seconds", type=int, required=True)
    run_parser.add_argument("--overall-timeout-seconds", type=int, required=True)
    args = parser.parse_args(argv)
    if args.command == "validate":
        project = Path(args.project_root).resolve()
        result = validate_prelaunch(project, args.contract_sha256, require_targets_absent=True)
        if args.output:
            output = Path(args.output).resolve()
            if output.exists():
                raise FileExistsError(output)
            output.parent.mkdir(parents=True, exist_ok=True)
            create_json(output, result)
        print(json.dumps(result, sort_keys=True))
        return 0
    if args.block_timeout_seconds <= 0 or args.overall_timeout_seconds <= 0:
        raise ExecutionError("timeouts must be positive")
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
