#!/usr/bin/env python3
"""Gate 13R-PR1B v4 read-only composite-process-identity analysis recovery.

This versioned module never starts Unity and never writes beneath the frozen
pilot root.  It validates OS process identities as (PID, process start UTC),
then delegates unchanged statistical calculations to the frozen V1/V4
analyzers through a narrowly scoped runtime identity adapter.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import random
import statistics
import sys
import tempfile
import traceback
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, MutableSet, Sequence, Tuple


EXPECTED_SOURCE_TREE_SHA256 = "4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed"
EXPECTED_PLAN_SHA256 = "40a44a9f43c9b2cbe63905a0ec347b8295aea5e8f8b3e9bf34b0800bcc471784"
EXPECTED_PROVENANCE_SHA256 = "993f554a03bc52493c3fea116f1206f14746db89e4c14c59d8e4e15befbef320"
EXPECTED_PLAN_ID = "gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1"
EXPECTED_POLICY_ID = "gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1"
EXPECTED_ANALYSIS_KIND = "gate13r-pr1b-v4-composite-process-identity-read-only-analysis-recovery-v1"
RECOVERY_STATUS = (
    "ANALYSIS-RECOVERY-FROM-COMPLETE-FAILED-NONFORMAL-PILOT / "
    "PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS"
)
FROZEN_PILOT_STATUS = (
    "FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / NON-FORMAL / "
    "COMPLETE-RAW-EXECUTION / POST-EXECUTION-ANALYZER-FAILED / "
    "EXCLUDED-FROM-FORMAL-ANALYSIS"
)
FORMAL_ROOT_RELATIVE = "Research/FormalRuns/Gate13R_RQAligned/v1"
ALLOWED_ANALYSIS_PARENT_RELATIVE = "Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery"


class ContractError(ValueError):
    def __init__(self, reason_code: str, message: str):
        super().__init__(f"{reason_code}: {message}")
        self.reason_code = reason_code
        self.message = message


def require(condition: bool, reason_code: str, message: str) -> None:
    if not condition:
        raise ContractError(reason_code, message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def canonical_json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def write_atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def write_atomic_json(path: Path, value: Any) -> None:
    write_atomic_text(path, canonical_json_text(value))


def utc_now_text() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def shanghai_now_text() -> str:
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="microseconds")


def resolve_within(path: Path, parent: Path, reason_code: str, label: str) -> Path:
    resolved = path.resolve()
    base = parent.resolve()
    try:
        resolved.relative_to(base)
    except ValueError as exc:
        raise ContractError(reason_code, f"{label} escapes allowed parent: {resolved}") from exc
    return resolved


def tree_identity(root: Path) -> Dict[str, Any]:
    resolved = root.resolve()
    require(resolved.is_dir(), "TREE-ROOT-MISSING", f"tree root missing: {resolved}")
    files = sorted((p for p in resolved.rglob("*") if p.is_file()), key=lambda p: str(p).casefold())
    rows: List[str] = []
    raw_bytes = 0
    last_write_ns = 0
    for path in files:
        stat = path.stat()
        raw_bytes += stat.st_size
        last_write_ns = max(last_write_ns, stat.st_mtime_ns)
        relative = path.relative_to(resolved).as_posix()
        rows.append(f"{relative}\t{stat.st_size}\t{sha256_file(path)}")
    last_write = datetime.fromtimestamp(last_write_ns / 1_000_000_000, timezone.utc) if last_write_ns else None
    return {
        "resolvedAbsolutePath": resolved.as_posix(),
        "fileCount": len(files),
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": sha256_bytes("\n".join(rows).encode("utf-8")),
        "lastWriteUtc": last_write.isoformat(timespec="microseconds").replace("+00:00", "Z") if last_write else None,
        "algorithm": "case-insensitive sorted relativePath<TAB>rawBytes<TAB>lowercaseSha256 joined with LF; SHA-256 over UTF-8",
    }


def parse_timestamp(value: Any, label: str, require_utc: bool = False) -> datetime:
    require(isinstance(value, str) and value.strip() != "", "PROCESS-START-MISSING" if "processStart" in label else "TIMESTAMP-MISSING", f"{label} is missing")
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00" if text.endswith("Z") else text)
    except (TypeError, ValueError) as exc:
        raise ContractError("PROCESS-START-MALFORMED" if "processStart" in label else "TIMESTAMP-MALFORMED", f"{label} is malformed: {text}") from exc
    require(parsed.tzinfo is not None, "PROCESS-START-NON-UTC" if "processStart" in label else "TIMESTAMP-NON-UTC", f"{label} has no timezone")
    if require_utc:
        require(parsed.utcoffset() == timedelta(0), "PROCESS-START-NON-UTC", f"{label} is not UTC")
    return parsed.astimezone(timezone.utc)


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, "MODULE-LOAD-FAILED", f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_frozen_v4(project: Path):
    return load_module(project / "Research" / "Analyze-Gate13RPR1BOrderEffectPilotV4.py", "gate13r_pr1b_frozen_v4_for_recovery")


def record_error_codes(records: Sequence[Mapping[str, Any]], execution_end: datetime) -> List[str]:
    errors: List[str] = []
    seen_os: Dict[Tuple[int, str], str] = {}
    seen_block_evidence: set[Tuple[int, str, str]] = set()
    block_to_os: Dict[str, Tuple[int, str]] = {}
    seen_runs: set[str] = set()
    seen_schedule: set[str] = set()
    by_pid: Dict[int, List[Mapping[str, Any]]] = defaultdict(list)
    for record in records:
        pid = int(record["processId"])
        start_text = str(record["processStartTimeUtc"])
        block_id = str(record["blockId"])
        start = record["start"]
        end = record["end"]
        if start > execution_end:
            errors.append("PROCESS-START-FUTURE")
        if start > end:
            errors.append("PROCESS-TIME-ORDER-IMPOSSIBLE")
        os_key = (pid, start_text)
        block_key = (pid, start_text, block_id)
        if os_key in seen_os:
            errors.append("DUPLICATE-OS-PROCESS-IDENTITY")
            if seen_os[os_key] != block_id:
                errors.append("PROCESS-IDENTITY-MULTIPLE-BLOCKS")
        else:
            seen_os[os_key] = block_id
        if block_key in seen_block_evidence:
            errors.append("DUPLICATE-BLOCK-EVIDENCE-IDENTITY")
        else:
            seen_block_evidence.add(block_key)
        if block_id in block_to_os and block_to_os[block_id] != os_key:
            errors.append("BLOCK-MULTIPLE-PROCESS-IDENTITIES")
        else:
            block_to_os[block_id] = os_key
        schedule_key = str(record["scheduleKey"])
        if schedule_key in seen_schedule:
            errors.append("DUPLICATE-SCHEDULE-KEY")
        else:
            seen_schedule.add(schedule_key)
        for run_id in record["runIds"]:
            if run_id in seen_runs:
                errors.append("DUPLICATE-RUN-ID")
            else:
                seen_runs.add(run_id)
        if any(int(sample_pid) != pid for sample_pid in record["samplePids"]):
            errors.append("SAMPLE-BLOCK-PID-MISMATCH")
        by_pid[pid].append(record)
    for pid, group in by_pid.items():
        ordered = sorted(group, key=lambda row: (row["start"], row["end"], str(row["blockId"])))
        for previous, current in zip(ordered, ordered[1:]):
            if previous["end"] > current["start"]:
                errors.append("PID-LIFETIME-OVERLAP")
    return sorted(set(errors))


def validate_records(records: Sequence[Mapping[str, Any]], execution_end: datetime) -> Dict[str, Any]:
    errors = record_error_codes(records, execution_end)
    require(not errors, errors[0] if errors else "IDENTITY-UNKNOWN", ", ".join(errors))
    pid_counts = Counter(int(row["processId"]) for row in records)
    return {
        "totalProcessRecords": len(records),
        "distinctNumericPidCount": len(pid_counts),
        "numericPidReuseGroupCount": sum(count > 1 for count in pid_counts.values()),
        "largestNumericPidMultiplicity": max(pid_counts.values(), default=0),
        "uniqueOsProcessIdentityCount": len({(int(r["processId"]), str(r["processStartTimeUtc"])) for r in records}),
        "uniqueBlockEvidenceIdentityCount": len({(int(r["processId"]), str(r["processStartTimeUtc"]), str(r["blockId"])) for r in records}),
        "uniqueBlockIdCount": len({str(r["blockId"]) for r in records}),
        "uniqueRunIdCount": len({run for r in records for run in r["runIds"]}),
        "uniqueScheduleKeyCount": len({str(r["scheduleKey"]) for r in records}),
        "samePidLifetimeOverlapCount": 0,
        "verdict": "COMPOSITE-PROCESS-IDENTITY-VALID",
    }


def sample_evidence_audit(project: Path, output: Path, block: Mapping[str, Any], block_pid: int, role: str) -> Tuple[List[str], List[int], List[str]]:
    run_ids: List[str] = []
    sample_pids: List[int] = []
    algorithms: List[str] = []
    samples = list(block["samples"])
    require(len(samples) == 2 and int(block["completedSampleCount"]) == 2, "SAMPLE-CARDINALITY-MISMATCH", "block must contain two completed samples")
    for sample in samples:
        require(sample.get("completed") is True, "SAMPLE-INCOMPLETE", "sample incomplete")
        sample_pid = int(sample["processId"])
        sample_pids.append(sample_pid)
        require(sample_pid == block_pid, "SAMPLE-BLOCK-PID-MISMATCH", "sample entry PID differs from block PID")
        run_id = str(sample["runId"])
        run_ids.append(run_id)
        algorithms.append(str(sample["algorithmId"]))
        sample_dir = resolve_within(output / Path(str(sample["outputRelativePath"]).replace("/", os.sep)), output, "SAMPLE-PATH-ESCAPE", "sample directory")
        result_path = resolve_within(output / Path(str(sample["workloadResultRelativePath"]).replace("/", os.sep)), output, "SAMPLE-PATH-ESCAPE", "workload result")
        manifest_path = resolve_within(output / Path(str(sample["manifestRelativePath"]).replace("/", os.sep)), output, "SAMPLE-PATH-ESCAPE", "sample manifest")
        summary_path = resolve_within(output / Path(str(sample["summaryRelativePath"]).replace("/", os.sep)), output, "SAMPLE-PATH-ESCAPE", "sample summary")
        require(sample_dir.is_dir(), "SAMPLE-EVIDENCE-MISSING", f"sample directory missing: {sample_dir}")
        for path, expected, label in (
            (result_path, sample["workloadResultSha256"], "workload"),
            (manifest_path, sample["manifestSha256"], "manifest"),
            (summary_path, sample["summarySha256"], "summary"),
        ):
            require(path.is_file(), "SAMPLE-EVIDENCE-MISSING", f"{label} missing: {path}")
            require(sha256_file(path) == str(expected), "SAMPLE-EVIDENCE-HASH-MISMATCH", f"{label} hash mismatch: {path}")
        # Deliberately do not parse workload-result values during the pre-analysis audit.
        sample_manifest = read_json(manifest_path)
        sample_summary = read_json(summary_path)
        require(sample_manifest.get("completed") is True and sample_summary.get("completed") is True, "SAMPLE-INCOMPLETE", "sample manifest/summary incomplete")
        require(str(sample_manifest["runId"]) == run_id == str(sample_summary["runId"]), "RUN-IDENTITY-MISMATCH", "run ID mismatch")
        require(str(sample_manifest["algorithmId"]) == str(sample["algorithmId"]) == str(sample_summary["algorithmId"]), "ALGORITHM-IDENTITY-MISMATCH", "algorithm mismatch")
        require(int(sample_summary["processId"]) == block_pid, "SAMPLE-BLOCK-PID-MISMATCH", "sample summary PID differs from block PID")
        for key in ("plannerResetCompleted", "loggerDisposed", "sampleStateCreatedFresh", "canonicalScenarioReferenceVerified"):
            require(sample_manifest.get(key) is True, "RESET-OR-SCENARIO-GATE-FAILED", f"{key} is not true")
        evaluation_path = resolve_within(output / Path(str(sample["memoryGateEvaluationRelativePath"]).replace("/", os.sep)), output, "SAMPLE-PATH-ESCAPE", "memory evaluation")
        require(evaluation_path.is_file(), "MEMORY-EVALUATION-MISSING", f"memory evaluation missing: {evaluation_path}")
        require(sha256_file(evaluation_path) == str(sample["memoryGateEvaluationSha256"]), "MEMORY-EVALUATION-HASH-MISMATCH", "memory evaluation hash mismatch")
        evaluation = read_json(evaluation_path)
        require(evaluation.get("evaluationKind") == "gate13r-pr1b-v2-memory-gate-evaluation-v1", "MEMORY-POLICY-MISMATCH", "memory evaluation kind mismatch")
        require(evaluation.get("completed") is True and evaluation.get("telemetryValid") is True, "MEMORY-EVALUATION-INELIGIBLE", "memory evaluation incomplete/invalid")
        require(evaluation.get("sampleEmergencyStopPassed") is True, "MEMORY-HARD-GATE-FAILED", "sample memory emergency gate failed")
        require(evaluation.get("verdict") in ("PASS", "MEMORY-ALERT-128MIB"), "MEMORY-HARD-GATE-FAILED", "unexpected memory verdict")
    expected = {"A*-R", "D*L"} if str(block["comparisonCohortId"]).startswith("per-agent") else {"C-FF", "IDFF"}
    require(set(algorithms) == expected, "COHORT-ALGORITHM-SET-MISMATCH", f"unexpected algorithm set for {role}")
    require(sorted(int(s["position"]) for s in samples) == [1, 2], "WILLIAMS-POSITION-MISMATCH", "sample positions must be 1 and 2")
    return run_ids, sample_pids, algorithms


def load_structural_record(project: Path, pilot_root: Path, entry: Mapping[str, Any], execution_end: datetime) -> Dict[str, Any]:
    output = resolve_within(project / Path(str(entry["outputRelativePath"]).replace("/", os.sep)), pilot_root, "BLOCK-PATH-ESCAPE", "block output")
    block_path = output / "block-manifest.json"
    require(block_path.is_file(), "BLOCK-MANIFEST-MISSING", f"block manifest missing: {block_path}")
    require(sha256_file(block_path) == str(entry["blockManifestSha256"]), "BLOCK-MANIFEST-HASH-MISMATCH", f"block manifest hash mismatch: {block_path}")
    wrapper_path = resolve_within(project / Path(str(entry["wrapperSummaryRelativePath"]).replace("/", os.sep)), pilot_root, "WRAPPER-PATH-ESCAPE", "wrapper summary")
    require(wrapper_path.is_file(), "WRAPPER-SUMMARY-MISSING", f"wrapper summary missing: {wrapper_path}")
    require(sha256_file(wrapper_path) == str(entry["wrapperSummarySha256"]), "WRAPPER-SUMMARY-HASH-MISMATCH", "wrapper summary hash mismatch")
    block = read_json(block_path)
    wrapper = read_json(wrapper_path)
    require(entry.get("completed") is True and entry.get("formalCampaign") is False, "EXECUTION-ENTRY-INELIGIBLE", "execution entry incomplete/formal")
    require(block.get("completed") is True and block.get("formalCampaign") is False, "BLOCK-INELIGIBLE", "block incomplete/formal")
    require(wrapper.get("passed") is True and int(wrapper["exitCode"]) == 0 and wrapper.get("timedOut") is False, "WRAPPER-INELIGIBLE", "wrapper did not pass cleanly")
    for key in ("hardMemoryRulesPassed", "oneBlockPerUnityProcess", "oneSamplePerAlgorithmPerProcess", "allSamplesShareProcessId", "orderMatchesBlockPlan", "canonicalScenarioReferenceValidationPassed"):
        require(block.get(key) is True, "BLOCK-GATE-FAILED", f"block gate failed: {key}")
    require(str(block["executionDesignId"]) == "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1", "EXECUTION-DESIGN-MISMATCH", "block execution design mismatch")
    require(str(block["memoryGatePolicyId"]) == EXPECTED_POLICY_ID, "MEMORY-POLICY-MISMATCH", "block memory policy mismatch")
    require(str(block["blockId"]) == str(entry["blockId"]) == str(wrapper["blockId"]), "BLOCK-IDENTITY-MISMATCH", "block ID mismatch")
    require(int(block["block"]) == int(entry["block"]), "BLOCK-ORDINAL-MISMATCH", "block ordinal mismatch")
    require(str(block["comparisonCohortId"]) == str(entry["comparisonCohortId"]), "COHORT-MISMATCH", "comparison cohort mismatch")
    require(str(block["scenarioSourceSha256"]) == str(entry["scenarioSha256"]), "SCENARIO-HASH-MISMATCH", "scenario hash mismatch")
    pid = int(block["processId"])
    require(pid == int(entry["processId"]) == int(wrapper["unityProcessId"]), "PROCESS-PID-MISMATCH", "entry/block/wrapper PID mismatch")
    start_text = str(block.get("processStartTimeUtc") or "")
    start = parse_timestamp(block.get("processStartTimeUtc"), "processStartTimeUtc", require_utc=True)
    block_started = parse_timestamp(block.get("startedAtUtc"), "block.startedAtUtc")
    block_completed = parse_timestamp(block.get("completedAtUtc"), "block.completedAtUtc")
    wrapper_started = parse_timestamp(wrapper.get("startedAt"), "wrapper.startedAt")
    wrapper_completed = parse_timestamp(wrapper.get("completedAt"), "wrapper.completedAt")
    require(start <= execution_end, "PROCESS-START-FUTURE", "process start occurs after frozen execution completion")
    require(wrapper_started <= start <= block_started <= block_completed <= wrapper_completed, "PROCESS-TIME-ORDER-IMPOSSIBLE", "wrapper/process/block timestamps are not ordered")
    run_ids, sample_pids, algorithms = sample_evidence_audit(project, output, block, pid, str(entry["role"]))
    schedule_key = "|".join((str(entry["role"]), str(entry["scenarioId"]), str(int(entry["block"])), str(entry["superblockOrder"]), str(entry["comparisonCohortId"])))
    return {
        "role": str(entry["role"]),
        "ordinal": int(entry["ordinal"]),
        "scenarioId": str(entry["scenarioId"]),
        "block": int(entry["block"]),
        "superblockOrder": str(entry["superblockOrder"]),
        "comparisonCohortId": str(entry["comparisonCohortId"]),
        "processId": pid,
        "processStartTimeUtc": start_text,
        "blockId": str(block["blockId"]),
        "start": start,
        "end": wrapper_completed,
        "runIds": run_ids,
        "samplePids": sample_pids,
        "algorithms": algorithms,
        "scheduleKey": schedule_key,
        "outputRelativePath": str(entry["outputRelativePath"]),
    }


def audit_provenance(project: Path, provenance: Mapping[str, Any]) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    mismatches = 0
    for item in provenance.get("boundFiles", []):
        relative = str(item["relativePath"])
        path = resolve_within(project / Path(relative.replace("/", os.sep)), project, "PROVENANCE-PATH-ESCAPE", "provenance-bound file")
        present = path.is_file()
        actual = sha256_file(path) if present else None
        passed = present and actual == str(item["sha256"]) and path.stat().st_size == int(item["rawBytes"])
        mismatches += 0 if passed else 1
        rows.append({"relativePath": relative, "expectedSha256": str(item["sha256"]), "actualSha256": actual, "passed": passed})
    require(len(rows) == 77 and mismatches == 0, "PROVENANCE-BOUND-FILE-MISMATCH", f"bound files={len(rows)}, mismatches={mismatches}")
    return {"boundFileCount": len(rows), "mismatchCount": mismatches, "passed": True, "files": rows}


def audit_pilot_structure(project: Path, pilot_root: Path, plan_path: Path, provenance_path: Path, expected_tree: str) -> Dict[str, Any]:
    tree_before = tree_identity(pilot_root)
    require(tree_before["canonicalTreeSha256"] == expected_tree, "FROZEN-SOURCE-TREE-MISMATCH", "source tree differs before structural audit")
    require(sha256_file(plan_path) == EXPECTED_PLAN_SHA256, "PLAN-HASH-MISMATCH", "frozen plan hash mismatch")
    require(sha256_file(provenance_path) == EXPECTED_PROVENANCE_SHA256, "PROVENANCE-HASH-MISMATCH", "frozen provenance hash mismatch")
    plan = read_json(plan_path)
    provenance = read_json(provenance_path)
    require(plan.get("planId") == EXPECTED_PLAN_ID and plan.get("formalCampaign") is False, "PLAN-IDENTITY-MISMATCH", "plan identity/boundary mismatch")
    analysis_contract = plan["orderEffectAnalysis"]
    require(int(analysis_contract["bootstrapReplicates"]) == 20000 and int(analysis_contract["bootstrapSeed"]) == 13012026, "STATISTICAL-CONTRACT-MISMATCH", "bootstrap contract changed")
    require(math.isclose(float(analysis_contract["orderBiasAbsoluteLogBound"]), math.log(1.10), rel_tol=0.0, abs_tol=1e-15), "STATISTICAL-CONTRACT-MISMATCH", "order-effect bound changed")
    execution_path = pilot_root / "pilot-execution-manifest.json"
    execution = read_json(execution_path)
    require(execution.get("completed") is True and execution.get("formalCampaign") is False and execution.get("excludedFromFormalAnalysis") is True, "EXECUTION-BOUNDARY-MISMATCH", "execution boundary mismatch")
    require(str(execution["pilotPlanSha256"]) == EXPECTED_PLAN_SHA256 and str(execution["provenanceSha256"]) == EXPECTED_PROVENANCE_SHA256, "EXECUTION-BINDING-MISMATCH", "execution plan/provenance binding mismatch")
    execution_end = parse_timestamp(execution.get("completedAtUtc"), "execution.completedAtUtc")
    entries = sorted(list(execution["entries"]), key=lambda row: int(row["ordinal"]))
    records = [load_structural_record(project, pilot_root, entry, execution_end) for entry in entries]
    identity = validate_records(records, execution_end)
    measured = [r for r in records if r["role"] == "measured-non-formal-pilot"]
    warmup = [r for r in records if r["role"] == "excluded-warmup"]
    measured_runs = {run for row in measured for run in row["runIds"]}
    total_runs = {run for row in records for run in row["runIds"]}
    measured_pairs = {(r["scenarioId"], r["block"]) for r in measured}
    measured_superblocks = {(r["scenarioId"], r["block"], r["superblockOrder"]) for r in measured}
    require(len(warmup) == 12 and len(measured) == 384 and len(records) == 396, "EXECUTION-CARDINALITY-MISMATCH", "block-process cardinality mismatch")
    require(len(measured_runs) == 768 and len(total_runs) == 792, "RUN-CARDINALITY-MISMATCH", "run ID cardinality mismatch")
    require(len(measured_pairs) == 96 and len(measured_superblocks) == 192, "PAIR-CARDINALITY-MISMATCH", "mirrored-pair/superblock cardinality mismatch")
    require(identity["uniqueOsProcessIdentityCount"] == 396 and identity["uniqueBlockEvidenceIdentityCount"] == 396, "COMPOSITE-IDENTITY-CARDINALITY-MISMATCH", "composite identity cardinality mismatch")
    provenance_audit = audit_provenance(project, provenance)
    require(not (project / Path(FORMAL_ROOT_RELATIVE.replace("/", os.sep))).exists(), "FORMAL-ROOT-PRESENT", "reserved formal root must remain absent")
    require(not (project / "Temp" / "UnityLockfile").exists(), "UNITY-LOCKFILE-PRESENT", "Unity lockfile present")
    tree_after = tree_identity(pilot_root)
    require(tree_after == tree_before, "FROZEN-SOURCE-WRITTEN", "source tree changed during structural audit")
    pid_groups = Counter(int(r["processId"]) for r in records)
    return {
        "schemaVersion": 1,
        "auditKind": "gate13r-pr1b-v4-composite-process-identity-structural-preanalysis-audit-v1",
        "status": "PASSED / VALIDATION-ONLY / NO-WORKLOAD-METRIC-ANALYSIS",
        "passed": True,
        "sourceTreeBefore": tree_before,
        "sourceTreeAfter": tree_after,
        "counts": {
            "warmupBlockProcesses": len(warmup),
            "warmupSamples": sum(len(r["runIds"]) for r in warmup),
            "measuredBlockProcesses": len(measured),
            "measuredSamples": len(measured_runs),
            "totalBlockProcesses": len(records),
            "totalSamples": len(total_runs),
            "measuredMirroredPairs": len(measured_pairs),
            "measuredMatchedSuperblocks": len(measured_superblocks),
        },
        "processIdentityAudit": identity,
        "numericPidReuse": {
            "distinctPidValues": len(pid_groups),
            "reuseGroupCount": sum(v > 1 for v in pid_groups.values()),
            "largestMultiplicity": max(pid_groups.values()),
            "samePidLifetimeOverlapCount": 0,
        },
        "provenanceAudit": provenance_audit,
        "workloadMetricValuesReadForAnalysis": False,
        "unityInvoked": False,
        "formalRootPresent": False,
        "recoveryRootPresent": False,
        "recordIndex": [
            {
                "role": r["role"],
                "ordinal": r["ordinal"],
                "blockId": r["blockId"],
                "processId": r["processId"],
                "processStartTimeUtc": r["processStartTimeUtc"],
                "scheduleKey": r["scheduleKey"],
                "runIds": r["runIds"],
                "outputRelativePath": r["outputRelativePath"],
            }
            for r in records
        ],
    }


def synthetic_record(pid: int, start_text: str, end_text: str, block: str, schedule: str, run: str, sample_pid: int | None = None) -> Dict[str, Any]:
    start = parse_timestamp(start_text, "processStartTimeUtc", require_utc=True)
    end = parse_timestamp(end_text, "synthetic.endUtc")
    return {
        "processId": pid,
        "processStartTimeUtc": start_text,
        "blockId": block,
        "start": start,
        "end": end,
        "scheduleKey": schedule,
        "runIds": [run],
        "samplePids": [pid if sample_pid is None else sample_pid],
    }


def expect_timestamp_error(value: Any, expected: str, execution_end: datetime | None = None, impossible_end: str | None = None) -> bool:
    try:
        start = parse_timestamp(value, "processStartTimeUtc", require_utc=True)
        if execution_end is not None and start > execution_end:
            raise ContractError("PROCESS-START-FUTURE", "synthetic future time")
        if impossible_end is not None and start > parse_timestamp(impossible_end, "synthetic.endUtc"):
            raise ContractError("PROCESS-TIME-ORDER-IMPOSSIBLE", "synthetic impossible order")
    except ContractError as exc:
        return exc.reason_code == expected
    return False


def run_self_test(project: Path, expected_path: Path) -> Dict[str, Any]:
    expected = read_json(expected_path)
    execution_end = parse_timestamp("2026-01-01T00:10:00Z", "synthetic.executionEndUtc")
    a = synthetic_record(100, "2026-01-01T00:00:00Z", "2026-01-01T00:01:00Z", "b1", "s1", "r1")
    b = synthetic_record(100, "2026-01-01T00:02:00Z", "2026-01-01T00:03:00Z", "b2", "s2", "r2")
    checks: Dict[str, bool] = {}
    checks["legal-sequential-pid-reuse"] = validate_records([a, b], execution_end)["numericPidReuseGroupCount"] == 1
    overlap = synthetic_record(100, "2026-01-01T00:00:30Z", "2026-01-01T00:02:00Z", "b3", "s3", "r3")
    checks["illegal-overlapping-pid-reuse"] = "PID-LIFETIME-OVERLAP" in record_error_codes([a, overlap], execution_end)
    same_os_other_block = dict(a, blockId="b9", scheduleKey="s9", runIds=["r9"])
    duplicate_exact = dict(a, scheduleKey="s8", runIds=["r8"])
    checks["duplicate-os-process-identity"] = "DUPLICATE-OS-PROCESS-IDENTITY" in record_error_codes([a, same_os_other_block], execution_end)
    checks["duplicate-block-evidence-identity"] = "DUPLICATE-BLOCK-EVIDENCE-IDENTITY" in record_error_codes([a, duplicate_exact], execution_end)
    checks["one-process-identity-multiple-blocks"] = "PROCESS-IDENTITY-MULTIPLE-BLOCKS" in record_error_codes([a, same_os_other_block], execution_end)
    same_block_other_identity = synthetic_record(101, "2026-01-01T00:04:00Z", "2026-01-01T00:05:00Z", "b1", "s4", "r4")
    checks["one-block-multiple-process-identities"] = "BLOCK-MULTIPLE-PROCESS-IDENTITIES" in record_error_codes([a, same_block_other_identity], execution_end)
    checks["missing-process-start"] = expect_timestamp_error(None, "PROCESS-START-MISSING")
    checks["non-utc-process-start"] = expect_timestamp_error("2026-01-01T08:00:00+08:00", "PROCESS-START-NON-UTC")
    checks["malformed-process-start"] = expect_timestamp_error("not-a-time", "PROCESS-START-MALFORMED")
    checks["future-process-start"] = expect_timestamp_error("2026-01-01T00:11:00Z", "PROCESS-START-FUTURE", execution_end=execution_end)
    checks["impossible-process-time-order"] = expect_timestamp_error("2026-01-01T00:04:00Z", "PROCESS-TIME-ORDER-IMPOSSIBLE", impossible_end="2026-01-01T00:03:00Z")
    pid_mismatch = dict(a, samplePids=[999], scheduleKey="s5", runIds=["r5"])
    checks["sample-block-pid-mismatch"] = "SAMPLE-BLOCK-PID-MISMATCH" in record_error_codes([pid_mismatch], execution_end)
    duplicate_run = dict(b, runIds=["r1"])
    duplicate_schedule = dict(b, scheduleKey="s1")
    checks["duplicate-run-id"] = "DUPLICATE-RUN-ID" in record_error_codes([a, duplicate_run], execution_end)
    checks["duplicate-schedule-key"] = "DUPLICATE-SCHEDULE-KEY" in record_error_codes([a, duplicate_schedule], execution_end)

    v4 = load_frozen_v4(project)
    v1 = v4.load_v1(project)
    frozen_v1 = v1.self_test()
    frozen_v4 = v4.self_test(project)
    checks["frozen-v1-self-test"] = bool(frozen_v1["passed"])
    checks["frozen-v4-self-test"] = bool(frozen_v4["passed"])
    values = [float(i - 16) / 1000.0 for i in range(32)]
    first = v1.bootstrap_mean_ci(values, 20000, 13012026)
    second = v1.bootstrap_mean_ci(values, 20000, 13012026)
    checks["bootstrap-20000-deterministic"] = first == second

    expected_ids = [str(row["id"]) for row in expected["checks"]]
    require(set(checks) == set(expected_ids), "SYNTHETIC-FIXTURE-ID-MISMATCH", "actual and expected synthetic check IDs differ")
    rows = []
    for expected_row in expected["checks"]:
        check_id = str(expected_row["id"])
        rows.append({"id": check_id, "passed": bool(checks[check_id]), "expected": expected_row.get("expected"), "expectedReasonCode": expected_row.get("expectedReasonCode")})
    passed = all(row["passed"] for row in rows)
    return {
        "schemaVersion": 1,
        "testKind": "gate13r-pr1b-v4-composite-process-identity-synthetic-validation-v1",
        "passed": passed,
        "checkCount": len(rows),
        "passedCheckCount": sum(row["passed"] for row in rows),
        "checks": rows,
        "bootstrap": {"replicates": 20000, "seed": 13012026, "first95Ci": first, "second95Ci": second, "byteIdentical": first == second},
        "unityInvoked": False,
        "realPilotMetricValuesRead": False,
    }


def patched_v1_for_composite_identity(project: Path, identity_by_output: Mapping[str, Tuple[int, str, str]]):
    v4 = load_frozen_v4(project)
    v1 = v4.load_v1(project)
    original = v1.load_process_samples

    def load_process_samples_composite(project_arg: Path, entry: Mapping[str, Any], seen_runs: MutableSet[str], seen_processes: MutableSet[Any]) -> Dict[str, Any]:
        local_numeric_pid: set[int] = set()
        loaded = original(project_arg, entry, seen_runs, local_numeric_pid)
        relative = str(entry["outputRelativePath"])
        require(relative in identity_by_output, "IDENTITY-INDEX-MISSING", f"no audited identity for {relative}")
        composite = identity_by_output[relative]
        require(composite not in seen_processes, "DUPLICATE-BLOCK-EVIDENCE-IDENTITY", f"duplicate audited block identity: {composite}")
        seen_processes.add(composite)
        loaded["processStartTimeUtc"] = composite[1]
        loaded["blockEvidenceIdentityKey"] = list(composite)
        return loaded

    v1.load_process_samples = load_process_samples_composite
    v4.load_v1 = lambda _project: v1
    return v1, v4


def grouped_diagnostics(v1, rows: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    def grouped(key: str) -> List[Dict[str, Any]]:
        buckets: Dict[str, List[Mapping[str, Any]]] = defaultdict(list)
        for row in rows:
            buckets[str(row[key])].append(row)
        return [
            {
                "level": level,
                "n": len(group),
                "meanProcessAgeMilliseconds": statistics.fmean(float(r["processAgeMs"]) for r in group),
                "meanSampleManagedGrowthBytes": statistics.fmean(float(r["sampleManagedGrowthBytes"]) for r in group),
                "memoryAlertCount": sum(bool(r["alert"]) for r in group),
            }
            for level, group in sorted(buckets.items())
        ]

    waves = [float(row["wave"]) for row in rows]
    ages = [float(row["processAgeMs"]) for row in rows]
    managed = [float(row["sampleManagedGrowthBytes"]) for row in rows]
    return {
        "sampleCount": len(rows),
        "byPosition": grouped("position"),
        "byPredecessor": grouped("predecessor"),
        "byAlgorithm": grouped("algorithmId"),
        "byPairProcessPosition": grouped("pairProcessPosition"),
        "processAgeWaveCorrelation": v1.pearson(ages, waves),
        "sampleManagedGrowthWaveCorrelation": v1.pearson(managed, waves),
        "metricOrderEffectWaveCorrelationsLocation": "scenarioRows and pooledEqualScenarioRows[*].waveCorrelation",
        "interpretation": "DESCRIPTIVE-PILOT-DIAGNOSTIC-ONLY",
    }


def validate_recovery_schema(analysis: Mapping[str, Any], schema: Mapping[str, Any]) -> None:
    for key in schema["required"]:
        require(key in analysis, "RECOVERY-SCHEMA-REQUIRED-FIELD-MISSING", f"missing analysis field: {key}")
    require(int(analysis["schemaVersion"]) == 4, "RECOVERY-SCHEMA-MISMATCH", "schema version mismatch")
    require(str(analysis["analysisKind"]) == EXPECTED_ANALYSIS_KIND, "RECOVERY-SCHEMA-MISMATCH", "analysis kind mismatch")
    require(str(analysis["status"]) == RECOVERY_STATUS, "RECOVERY-SCHEMA-MISMATCH", "status mismatch")
    require(analysis["formalInference"] is False, "RECOVERY-SCHEMA-MISMATCH", "formalInference must be false")
    require(len(analysis["scenarioRows"]) == 48 and len(analysis["pooledEqualScenarioRows"]) == 16, "RECOVERY-SCHEMA-MISMATCH", "analysis row cardinality mismatch")
    require("FORMAL-ALGORITHM-SUPERIORITY" in analysis["prohibitedClaims"], "RECOVERY-SCHEMA-MISMATCH", "formal superiority prohibition missing")


def build_recovered_analysis(project: Path, pilot_root: Path, plan_path: Path, provenance_path: Path, structural_audit: Mapping[str, Any], schema: Mapping[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    index = structural_audit["recordIndex"]
    measured_index = [row for row in index if row["role"] == "measured-non-formal-pilot"]
    identity_by_output = {
        str(row["outputRelativePath"]): (int(row["processId"]), str(row["processStartTimeUtc"]), str(row["blockId"]))
        for row in measured_index
    }
    require(len(identity_by_output) == 384, "IDENTITY-INDEX-CARDINALITY-MISMATCH", "measured identity index must contain 384 blocks")
    v1, v4 = patched_v1_for_composite_identity(project, identity_by_output)
    analysis, _legacy_manifest = v4.build_analysis(project, pilot_root, plan_path, provenance_path)
    execution = read_json(pilot_root / "pilot-execution-manifest.json")
    rows, _processes = v4.memory_records(v1, project, execution)
    analysis["schemaVersion"] = 4
    analysis["analysisKind"] = EXPECTED_ANALYSIS_KIND
    analysis["status"] = RECOVERY_STATUS
    analysis["formalInference"] = False
    analysis["formalCampaignAuthorized"] = False
    analysis["gate14rAuthorized"] = False
    analysis["frozenPilotTerminalStatus"] = FROZEN_PILOT_STATUS
    analysis["source"]["sourceTreeSha256"] = structural_audit["sourceTreeBefore"]["canonicalTreeSha256"]
    analysis["source"]["uniqueMeasuredOsProcessIdentities"] = 384
    analysis["source"]["uniqueMeasuredBlockEvidenceIdentities"] = 384
    analysis["source"]["distinctMeasuredNumericPids"] = len({int(row["processId"]) for row in measured_index})
    analysis["source"]["recoveryReadsFrozenPilotOnly"] = True
    analysis["source"]["recoveryWritesFrozenPilot"] = False
    analysis["processIdentityAudit"] = structural_audit["processIdentityAudit"]
    analysis["processIdentityAudit"]["definition"] = {
        "osProcessIdentity": ["processId", "processStartTimeUtc"],
        "blockEvidenceIdentity": ["processId", "processStartTimeUtc", "blockId"],
        "numericPidReuseRule": "LEGAL-ONLY-AFTER-PRIOR-HALF-OPEN-LIFETIME-ENDS",
    }
    analysis["executionDiagnostics"] = grouped_diagnostics(v1, rows)
    p1_rows = [row for row in analysis["scenarioRows"] + analysis["pooledEqualScenarioRows"] if row["metricId"] == "P1"]
    classifications = Counter(str(row["classification"]) for row in p1_rows)
    if classifications.get("MATERIAL-ORDER-EFFECT", 0) > 0:
        verdict = "PILOT-LEVEL-ORDER-EFFECT-IDENTIFIABLE / MATERIAL-ORDER-EFFECT-PRESENT"
    elif classifications.get("INCONCLUSIVE", 0) > 0:
        verdict = "PILOT-LEVEL-ORDER-EFFECT-IDENTIFIABLE / SOME-CELLS-INCONCLUSIVE"
    elif classifications.get("DETECTABLE-BUT-BELOW-BOUND", 0) > 0:
        verdict = "PILOT-LEVEL-ORDER-EFFECT-IDENTIFIABLE / DETECTABLE-BELOW-BOUND"
    else:
        verdict = "PILOT-LEVEL-ORDER-EFFECT-IDENTIFIABLE / ORDER-EFFECT-BOUNDED"
    analysis["pilotLevelOrderEffectIdentifiability"] = {
        "verdict": verdict,
        "p1ClassificationCountsAcrossScenarioAndPooledRows": dict(sorted(classifications.items())),
        "pilotDiagnosticOnly": True,
        "formalClaimAllowed": False,
        "pureAlgorithmCausalClaimAllowed": False,
    }
    analysis["recoveryContract"] = {
        "bootstrapReplicates": 20000,
        "bootstrapSeed": 13012026,
        "bootstrapUnit": "complete-mirrored-order-pair",
        "pooledWeighting": "equal-scenario",
        "confidenceLevel": 0.95,
        "orderBiasAbsoluteLogBound": math.log(1.10),
        "identityRepairOnly": True,
        "scientificContractChanged": False,
    }
    validate_recovery_schema(analysis, schema)
    analysis_sha = sha256_bytes(canonical_json_text(analysis).encode("utf-8"))
    manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr1b-v4-read-only-analysis-recovery-manifest-v1",
        "status": RECOVERY_STATUS,
        "analysisRecoveryCompleted": True,
        "sourcePilotRemainsFailed": True,
        "sourcePilotStatus": FROZEN_PILOT_STATUS,
        "sourcePilotTreeSha256": structural_audit["sourceTreeBefore"]["canonicalTreeSha256"],
        "analysisSha256": analysis_sha,
        "measuredMirroredPairs": 96,
        "measuredMatchedSuperblocks": 192,
        "measuredBlockProcesses": 384,
        "measuredSamples": 768,
        "uniqueMeasuredOsProcessIdentities": 384,
        "uniqueMeasuredBlockEvidenceIdentities": 384,
        "numericPidReuseAcceptedOnlyWhenNonOverlapping": True,
        "automaticRecoveryRetryCount": 0,
        "unityInvoked": False,
        "newSamplesGenerated": 0,
        "formalCampaign": False,
        "excludedFromFormalAnalysis": True,
        "gate13rFormalAuthorized": False,
        "gate14rAuthorized": False,
    }
    return analysis, manifest


def evidence_manifest(root: Path, excluded_names: Iterable[str] = ()) -> Dict[str, Any]:
    excluded = set(excluded_names)
    files = []
    for path in sorted((p for p in root.rglob("*") if p.is_file() and p.name not in excluded), key=lambda p: str(p).casefold()):
        files.append({"relativePath": path.relative_to(root).as_posix(), "rawBytes": path.stat().st_size, "sha256": sha256_file(path)})
    return {"schemaVersion": 1, "manifestKind": "gate13r-pr1b-v4-analysis-recovery-evidence-manifest-v1", "fileCount": len(files), "files": files}


def recover_once(project: Path, pilot_root: Path, plan_path: Path, provenance_path: Path, preflight_path: Path, output_root: Path, schema_path: Path, expected_tree: str) -> Dict[str, Any]:
    allowed_parent = (project / Path(ALLOWED_ANALYSIS_PARENT_RELATIVE.replace("/", os.sep))).resolve()
    output_root = resolve_within(output_root, allowed_parent, "RECOVERY-OUTPUT-ESCAPE", "recovery output root")
    require(not output_root.exists(), "RECOVERY-OUTPUT-ALREADY-EXISTS", "one-shot recovery root already exists")
    preflight = read_json(preflight_path)
    require(preflight.get("passed") is True, "PREFLIGHT-NOT-PASSED", "validation-only preflight did not pass")
    require(preflight["sourceTreeAfter"]["canonicalTreeSha256"] == expected_tree, "PREFLIGHT-SOURCE-HASH-MISMATCH", "preflight source hash mismatch")
    require(not (project / Path(FORMAL_ROOT_RELATIVE.replace("/", os.sep))).exists(), "FORMAL-ROOT-PRESENT", "formal root present")
    source_before = tree_identity(pilot_root)
    require(source_before["canonicalTreeSha256"] == expected_tree, "FROZEN-SOURCE-TREE-MISMATCH", "source tree differs before recovery")
    schema = read_json(schema_path)
    output_root.mkdir(parents=True, exist_ok=False)
    started_at = utc_now_text()
    write_atomic_json(output_root / "analysis-recovery-start-receipt.json", {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr1b-v4-analysis-recovery-start-receipt-v1",
        "startedAtUtc": started_at,
        "status": "RECOVERY-STARTED / ONE-SHOT / NO-AUTOMATIC-RETRY",
        "sourcePilotTreeBefore": source_before,
        "preflightSha256": sha256_file(preflight_path),
        "unityInvocationAuthorized": False,
        "formalCampaignAuthorized": False,
    })
    try:
        analysis, manifest = build_recovered_analysis(project, pilot_root, plan_path, provenance_path, preflight, schema)
        write_atomic_json(output_root / "recovered-order-effect-analysis.json", analysis)
        write_atomic_json(output_root / "analysis-recovery-manifest.json", manifest)
        source_after = tree_identity(pilot_root)
        require(source_after == source_before, "FROZEN-SOURCE-WRITTEN", "frozen source changed during recovery")
        preservation = {
            "schemaVersion": 1,
            "auditKind": "gate13r-pr1b-v4-source-preservation-after-recovery-v1",
            "passed": True,
            "before": source_before,
            "after": source_after,
            "byteIdentical": True,
            "sourceWrites": 0,
        }
        write_atomic_json(output_root / "source-preservation-after.json", preservation)
        completed_at = utc_now_text()
        receipt = {
            "schemaVersion": 1,
            "receiptKind": "gate13r-pr1b-v4-read-only-analysis-recovery-receipt-v1",
            "startedAtUtc": started_at,
            "completedAtUtc": completed_at,
            "completedAtAsiaShanghai": shanghai_now_text(),
            "status": RECOVERY_STATUS,
            "passed": True,
            "recoveryAttemptOrdinal": 1,
            "automaticRetryCount": 0,
            "sourcePilotRemainsFailed": True,
            "sourcePilotTreeBefore": source_before,
            "sourcePilotTreeAfter": source_after,
            "analysisSha256": sha256_file(output_root / "recovered-order-effect-analysis.json"),
            "manifestSha256": sha256_file(output_root / "analysis-recovery-manifest.json"),
            "unityInvoked": False,
            "newSamplesGenerated": 0,
            "pilotRetriedOrResumed": False,
            "formalCampaignAuthorized": False,
            "gate14rAuthorized": False,
        }
        write_atomic_json(output_root / "analysis-recovery-receipt.json", receipt)
        checkpoint = {
            "schemaVersion": 1,
            "checkpointId": "gate13r-pr1b-v4-composite-process-identity-analysis-recovery-passed-v1",
            "status": "COMPOSITE-PROCESS-IDENTITY-VALIDATED / READ-ONLY-ANALYSIS-RECOVERY-COMPLETE / PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED",
            "passed": True,
            "completedAtUtc": completed_at,
            "nextAuthorizationRequired": True,
            "nextAllowedStage": "GATE13R-PR2-OR-OTHER-SEPARATELY-AUTHORIZED-WORK",
        }
        write_atomic_json(output_root / "analysis-recovery-checkpoint.json", checkpoint)
        write_atomic_text(output_root / "analysis-recovery.log", "Gate13R PR1B v4 read-only analysis recovery completed.\nUnity invocations: 0\nNew samples: 0\nAutomatic retries: 0\nFrozen source writes: 0\n")
        manifest_value = evidence_manifest(output_root, {"evidence-manifest.json"})
        write_atomic_json(output_root / "evidence-manifest.json", manifest_value)
        return {
            "passed": True,
            "outputRoot": output_root.as_posix(),
            "analysisSha256": receipt["analysisSha256"],
            "manifestSha256": receipt["manifestSha256"],
            "sourceTreeSha256": source_after["canonicalTreeSha256"],
            "identifiabilityVerdict": analysis["pilotLevelOrderEffectIdentifiability"]["verdict"],
            "recommendation": analysis["decision"]["heterogeneousSampleConfigurationRecommendation"],
        }
    except Exception as exc:
        source_after = tree_identity(pilot_root)
        failure = {
            "schemaVersion": 1,
            "receiptKind": "gate13r-pr1b-v4-read-only-analysis-recovery-failure-receipt-v1",
            "failedAtUtc": utc_now_text(),
            "status": "FAILED-NO-AUTOMATIC-RECOVERY-RETRY / SOURCE-PILOT-REMAINS-FROZEN",
            "passed": False,
            "reasonCode": exc.reason_code if isinstance(exc, ContractError) else "UNEXPECTED-RECOVERY-EXCEPTION",
            "message": str(exc),
            "sourcePilotTreeBefore": source_before,
            "sourcePilotTreeAfter": source_after,
            "sourceByteIdentical": source_after == source_before,
            "unityInvoked": False,
            "newSamplesGenerated": 0,
            "automaticRetryCount": 0,
        }
        write_atomic_json(output_root / "analysis-recovery-failure-receipt.json", failure)
        write_atomic_json(output_root / "analysis-recovery-checkpoint.json", {"schemaVersion": 1, "status": "FAILED-NO-AUTOMATIC-RETRY", "passed": False, "reasonCode": failure["reasonCode"]})
        write_atomic_text(output_root / "analysis-recovery.log", traceback.format_exc())
        write_atomic_json(output_root / "partial-output-manifest.json", evidence_manifest(output_root, {"partial-output-manifest.json"}))
        raise


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--expected-fixture")
    parser.add_argument("--audit-structure", action="store_true")
    parser.add_argument("--recover", action="store_true")
    parser.add_argument("--pilot-root")
    parser.add_argument("--plan")
    parser.add_argument("--provenance")
    parser.add_argument("--preflight-report")
    parser.add_argument("--schema")
    parser.add_argument("--output")
    parser.add_argument("--output-root")
    parser.add_argument("--expected-tree-sha256", default=EXPECTED_SOURCE_TREE_SHA256)
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    project = Path(args.project).resolve()
    modes = sum(bool(value) for value in (args.self_test, args.audit_structure, args.recover))
    require(modes == 1, "CLI-MODE-INVALID", "choose exactly one mode")
    if args.self_test:
        require(args.expected_fixture and args.output, "CLI-ARGUMENT-MISSING", "self-test paths missing")
        result = run_self_test(project, Path(args.expected_fixture).resolve())
        write_atomic_json(Path(args.output).resolve(), result)
        sys.stdout.write(canonical_json_text({"passed": result["passed"], "checkCount": result["checkCount"], "passedCheckCount": result["passedCheckCount"]}))
        return 0 if result["passed"] else 1
    require(args.pilot_root and args.plan and args.provenance, "CLI-ARGUMENT-MISSING", "pilot/plan/provenance paths missing")
    pilot_root = Path(args.pilot_root).resolve()
    plan_path = Path(args.plan).resolve()
    provenance_path = Path(args.provenance).resolve()
    if args.audit_structure:
        require(args.output, "CLI-ARGUMENT-MISSING", "audit output missing")
        result = audit_pilot_structure(project, pilot_root, plan_path, provenance_path, args.expected_tree_sha256)
        write_atomic_json(Path(args.output).resolve(), result)
        sys.stdout.write(canonical_json_text({"passed": True, "processIdentityAudit": result["processIdentityAudit"], "counts": result["counts"]}))
        return 0
    require(args.preflight_report and args.output_root and args.schema, "CLI-ARGUMENT-MISSING", "recovery paths missing")
    result = recover_once(project, pilot_root, plan_path, provenance_path, Path(args.preflight_report).resolve(), Path(args.output_root).resolve(), Path(args.schema).resolve(), args.expected_tree_sha256)
    sys.stdout.write(canonical_json_text(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:
        code = exc.reason_code if isinstance(exc, ContractError) else "UNEXPECTED"
        sys.stderr.write(f"Gate13R PR1B v4 recovery failed [{code}]: {exc}\n")
        raise
