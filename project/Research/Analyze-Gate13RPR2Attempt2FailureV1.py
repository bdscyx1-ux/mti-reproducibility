#!/usr/bin/env python3
"""Non-executing, read-only failure diagnostics for Gate 13R-PR2 attempt 2."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import statistics
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STATUS_TOKENS = [
    "NON-EXECUTING",
    "FAILURE-DIAGNOSTIC-ONLY",
    "PARTIAL-FORMAL-ATTEMPT-EXCLUDED-FROM-FORMAL-ANALYSIS",
    "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
    "GATE14R-NOT-AUTHORIZED",
]
EXPECTED_RECEIPT_SHA256 = "a21466228b1e91dd8670093953b28333e235c9ff031b54fe385301c93ee8365e"
EXPECTED_PREWRITE_TREE_SHA256 = "be2623906d741b39e87f7c1d033d21443d2776f62ed709b4c4ef296220ce5f04"
FAILED_EVAL_SHA256 = "7e91da24abee3ae3b440391457b9dac7ede0228718f2aeeb5ff55804425dc6a3"
MIB = 1024 * 1024
THRESHOLD_MIB = [512, 640, 768, 1024]


class DiagnosticError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            block = stream.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def canonical_line(relative_path: str, byte_length: int, sha256: str) -> bytes:
    normalized = relative_path.replace("\\", "/")
    return f"{normalized}\t{byte_length}\t{sha256.lower()}\n".encode("utf-8")


def atomic_write_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def atomic_write_json(path: Path, value: Any) -> None:
    atomic_write_bytes(path, json_bytes(value))


def atomic_write_text(path: Path, value: str) -> None:
    atomic_write_bytes(path, value.replace("\r\n", "\n").encode("utf-8"))


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def ensure_outside(source_root: Path, output: Path) -> None:
    source = source_root.resolve()
    candidate = output.resolve()
    if candidate == source or source in candidate.parents:
        raise DiagnosticError(f"Output must be outside the failed root: {candidate}")


def build_file_manifest(root: Path) -> tuple[list[dict[str, Any]], str, int]:
    root = root.resolve()
    files = sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    casefolded: set[str] = set()
    records: list[dict[str, Any]] = []
    tree = hashlib.sha256()
    raw_bytes = 0
    for path in files:
        relative = path.relative_to(root).as_posix()
        collision_key = relative.casefold()
        if collision_key in casefolded:
            raise DiagnosticError(f"Duplicate/case-colliding path: {relative}")
        casefolded.add(collision_key)
        before = path.stat()
        digest = sha256_file(path)
        after = path.stat()
        if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
            raise DiagnosticError(f"File changed while hashing: {relative}")
        record = {
            "relativePath": relative,
            "bytes": before.st_size,
            "sha256": digest,
            "lastWriteTimeUtc": datetime.fromtimestamp(before.st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"),
            "readOnly": not os.access(path, os.W_OK),
        }
        records.append(record)
        raw_bytes += before.st_size
        tree.update(canonical_line(relative, before.st_size, digest))
    return records, tree.hexdigest(), raw_bytes


def r7_quantile(values: Iterable[float], probability: float) -> float | None:
    ordered = sorted(float(value) for value in values)
    if not ordered:
        return None
    if not 0 <= probability <= 1:
        raise ValueError("probability must be in [0, 1]")
    h = (len(ordered) - 1) * probability
    lower = math.floor(h)
    upper = math.ceil(h)
    if lower == upper:
        return ordered[lower]
    weight = h - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def finite_number(value: Any, name: str, *, nonnegative: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise DiagnosticError(f"{name} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise DiagnosticError(f"{name} must be finite")
    if nonnegative and number < 0:
        raise DiagnosticError(f"{name} must be non-negative")
    return number


def iso_to_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def describe(values: Iterable[float]) -> dict[str, Any]:
    finite = [float(value) for value in values if math.isfinite(float(value))]
    if not finite:
        return {"n": 0, "mean": None, "sd": None, "min": None, "p50": None, "p90": None, "p95": None, "p99": None, "max": None}
    return {
        "n": len(finite),
        "mean": statistics.fmean(finite),
        "sd": statistics.stdev(finite) if len(finite) > 1 else 0.0,
        "min": min(finite),
        "p50": r7_quantile(finite, 0.50),
        "p90": r7_quantile(finite, 0.90),
        "p95": r7_quantile(finite, 0.95),
        "p99": r7_quantile(finite, 0.99),
        "max": max(finite),
    }


def threshold_summary(values: Iterable[float], limit: int) -> dict[str, Any]:
    materialized = [float(value) for value in values]
    return {
        "limitBytes": limit,
        "limitMiB": limit / MIB,
        "n": len(materialized),
        "exceededCount": sum(value > limit for value in materialized),
        "equalCount": sum(value == limit for value in materialized),
        "oneByteOverWouldFail": True,
        "atOrAbove80PercentCount": sum(value >= 0.80 * limit for value in materialized),
        "atOrAbove90PercentCount": sum(value >= 0.90 * limit for value in materialized),
        "atOrAbove95PercentCount": sum(value >= 0.95 * limit for value in materialized),
    }


def grid_size_from(*values: str) -> str:
    for value in values:
        match = re.search(r"(?:^|[-_])g(\d+)(?:$|[-_])", value or "", flags=re.IGNORECASE)
        if match:
            return f"g{int(match.group(1))}"
    return "UNCLASSIFIED"


def normalize_memory_record(path: Path, failed_root: Path, plan_by_block: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], list[str]]:
    source = read_json(path)
    errors: list[str] = []
    required_strings = ["runId", "blockId", "campaignId", "scenarioId", "comparisonCohortId", "algorithmId", "predecessorAlgorithmId"]
    for field in required_strings:
        if not isinstance(source.get(field), str) or not source[field]:
            errors.append(f"missing-or-invalid-{field}")
    before = source.get("telemetryBeforeSample") or {}
    raw = source.get("telemetryRawAfterWorkload") or {}
    after = source.get("telemetryAfterCleanup") or {}
    for label, telemetry in (("before", before), ("raw", raw), ("after", after)):
        for field in ("processId", "workingSetBytes", "privateMemoryBytes", "managedMemoryBytes", "processAgeMilliseconds"):
            try:
                finite_number(telemetry.get(field), f"{label}.{field}", nonnegative=True)
            except DiagnosticError as exc:
                errors.append(str(exc))
        if not isinstance(telemetry.get("processStartTimeUtc"), str):
            errors.append(f"{label}.processStartTimeUtc missing")
    identities = {(item.get("processId"), item.get("processStartTimeUtc")) for item in (before, raw, after)}
    if len(identities) != 1:
        errors.append("telemetry-composite-process-identity-mismatch")
    try:
        sample_delta = finite_number(source.get("sampleRetainedManagedGrowthBytes"), "sampleRetainedManagedGrowthBytes")
        block_managed = finite_number(source.get("blockRetainedManagedGrowthBytesAtSampleBoundary"), "blockRetainedManagedGrowthBytesAtSampleBoundary")
        block_working = finite_number(source.get("blockWorkingSetGrowthBytesAtSampleBoundary"), "blockWorkingSetGrowthBytesAtSampleBoundary")
        block_private = finite_number(source.get("blockPrivateMemoryGrowthBytesAtSampleBoundary"), "blockPrivateMemoryGrowthBytesAtSampleBoundary")
        expected_sample_delta = finite_number(after.get("managedMemoryBytes"), "after.managedMemoryBytes") - finite_number(before.get("managedMemoryBytes"), "before.managedMemoryBytes")
        if sample_delta != expected_sample_delta:
            errors.append("sample-managed-delta-formula-mismatch")
        baselines = {
            "managed": finite_number(after.get("managedMemoryBytes"), "after.managedMemoryBytes") - block_managed,
            "workingSet": finite_number(after.get("workingSetBytes"), "after.workingSetBytes") - block_working,
            "privateMemory": finite_number(after.get("privateMemoryBytes"), "after.privateMemoryBytes") - block_private,
        }
        for name, value in baselines.items():
            if value < 0:
                errors.append(f"negative-derived-block-baseline-{name}")
    except DiagnosticError as exc:
        errors.append(str(exc))
        sample_delta = block_managed = block_working = block_private = math.nan
        baselines = {"managed": math.nan, "workingSet": math.nan, "privateMemory": math.nan}
    block_id = str(source.get("blockId") or "")
    plan = plan_by_block.get(block_id)
    if plan is None:
        errors.append("block-plan-missing")
        global_ordinal = None
        williams_row = None
    else:
        global_ordinal = plan.get("globalProcessOrdinal")
        williams_row = plan.get("williamsRowIndex")
        candidates = [entry for entry in plan.get("entries", []) if entry.get("runId") == source.get("runId")]
        if len(candidates) != 1:
            errors.append("run-plan-identity-mismatch")
        else:
            entry = candidates[0]
            for field in ("position", "algorithmId", "predecessorAlgorithmId"):
                if entry.get(field) != source.get(field):
                    errors.append(f"plan-{field}-mismatch")
    row = {
        "relativePath": path.relative_to(failed_root).as_posix(),
        "runId": source.get("runId"),
        "blockId": block_id,
        "globalProcessOrdinal": global_ordinal,
        "campaignId": source.get("campaignId"),
        "scenarioId": source.get("scenarioId"),
        "gridSize": grid_size_from(str(source.get("scenarioId") or ""), str(source.get("campaignId") or "")),
        "comparisonCohortId": source.get("comparisonCohortId"),
        "blockOrdinal": source.get("block"),
        "williamsRowIndex": williams_row,
        "position": source.get("position"),
        "algorithmId": source.get("algorithmId"),
        "predecessorAlgorithmId": source.get("predecessorAlgorithmId"),
        "processId": after.get("processId"),
        "processStartTimeUtc": after.get("processStartTimeUtc"),
        "processAgeMilliseconds": after.get("processAgeMilliseconds"),
        "telemetrySourceId": after.get("sourceId"),
        "sampleRetainedManagedGrowthBytes": sample_delta,
        "blockRetainedManagedGrowthBytesAtSampleBoundary": block_managed,
        "blockWorkingSetGrowthBytesAtSampleBoundary": block_working,
        "blockPrivateMemoryGrowthBytesAtSampleBoundary": block_private,
        "workingSetAfterCleanupBytes": after.get("workingSetBytes"),
        "privateMemoryAfterCleanupBytes": after.get("privateMemoryBytes"),
        "managedMemoryAfterCleanupBytes": after.get("managedMemoryBytes"),
        "blockBaselineManagedBytes": baselines["managed"],
        "blockBaselineWorkingSetBytes": baselines["workingSet"],
        "blockBaselinePrivateMemoryBytes": baselines["privateMemory"],
        "sampleManagedAlertThresholdBytes": source.get("sampleManagedAlertThresholdBytes"),
        "sampleManagedEmergencyStopBytes": source.get("sampleManagedEmergencyStopBytes"),
        "blockManagedHardLimitBytes": source.get("blockRetainedManagedGrowthHardLimitBytes"),
        "blockWorkingSetHardLimitBytes": source.get("blockWorkingSetGrowthHardLimitBytes"),
        "blockPrivateMemoryHardLimitBytes": source.get("blockPrivateMemoryGrowthHardLimitBytes"),
        "verdict": source.get("verdict"),
        "reasonCode": source.get("reasonCode"),
        "formalCampaign": source.get("formalCampaign"),
        "completedEvaluation": source.get("completed"),
        "valid": len(errors) == 0,
        "validationErrors": sorted(set(errors)),
    }
    return row, errors


def group_metric(rows: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[str(row.get(key, "UNCLASSIFIED"))].append(row)
    output = []
    for value in sorted(groups):
        members = groups[value]
        output.append(
            {
                "groupField": key,
                "groupValue": value,
                "evaluationCount": len(members),
                "blockCount": len({member["blockId"] for member in members}),
                "blockManagedGrowthBytes": describe(member["blockRetainedManagedGrowthBytesAtSampleBoundary"] for member in members),
                "blockWorkingSetGrowthBytes": describe(member["blockWorkingSetGrowthBytesAtSampleBoundary"] for member in members),
                "blockPrivateMemoryGrowthBytes": describe(member["blockPrivateMemoryGrowthBytesAtSampleBoundary"] for member in members),
                "sampleRetainedManagedGrowthBytes": describe(member["sampleRetainedManagedGrowthBytes"] for member in members),
            }
        )
    return output


def block_maxima(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[row["blockId"]].append(row)
    output: list[dict[str, Any]] = []
    for block_id in sorted(groups, key=lambda value: min((row.get("globalProcessOrdinal") or 10**9) for row in groups[value])):
        members = groups[block_id]
        representative = members[0]
        output.append(
            {
                "blockId": block_id,
                "globalProcessOrdinal": representative.get("globalProcessOrdinal"),
                "campaignId": representative.get("campaignId"),
                "scenarioId": representative.get("scenarioId"),
                "gridSize": representative.get("gridSize"),
                "comparisonCohortId": representative.get("comparisonCohortId"),
                "evaluationCount": len(members),
                "maximumPositionObserved": max(int(row.get("position") or 0) for row in members),
                "maximumBlockManagedGrowthBytes": max(row["blockRetainedManagedGrowthBytesAtSampleBoundary"] for row in members),
                "maximumBlockWorkingSetGrowthBytes": max(row["blockWorkingSetGrowthBytesAtSampleBoundary"] for row in members),
                "maximumBlockPrivateMemoryGrowthBytes": max(row["blockPrivateMemoryGrowthBytesAtSampleBoundary"] for row in members),
                "hardFailObserved": any(row.get("verdict") == "HARD-FAIL" for row in members),
                "partialBlock": block_id == "g13rpr2-c52-b0022",
            }
        )
    return output


def candidate_counts(blocks: list[dict[str, Any]], threshold_mib: int) -> dict[str, Any]:
    limit = threshold_mib * MIB
    working = [row["maximumBlockWorkingSetGrowthBytes"] for row in blocks]
    private = [row["maximumBlockPrivateMemoryGrowthBytes"] for row in blocks]
    return {
        "candidateThresholdMiB": threshold_mib,
        "candidateThresholdBytes": limit,
        "observedBlockCount": len(blocks),
        "workingSetExceededBlockCount": sum(value > limit for value in working),
        "privateMemoryExceededBlockCount": sum(value > limit for value in private),
        "eitherExceededBlockCount": sum((w > limit) or (p > limit) for w, p in zip(working, private)),
        "bothExceededBlockCount": sum((w > limit) and (p > limit) for w, p in zip(working, private)),
        "workingSetNearMissAtOrAbove90PercentCount": sum(value >= 0.90 * limit for value in working),
        "privateMemoryNearMissAtOrAbove90PercentCount": sum(value >= 0.90 * limit for value in private),
        "attempt2DispositionUnaffected": True,
        "candidateStatus": "UNFROZEN / USER-DECISION-REQUIRED",
    }


def generate_manifest(args: argparse.Namespace) -> None:
    project_root = Path(args.project_root).resolve()
    failed_root = Path(args.failed_root).resolve()
    output = Path(args.output).resolve()
    ensure_outside(failed_root, output)
    if sha256_file(project_root / "Research/Gate13R_PR2_Formal_Execution_Receipt.v2.json") != EXPECTED_RECEIPT_SHA256:
        raise DiagnosticError("Execution receipt SHA-256 mismatch")
    records, tree_sha256, raw_bytes = build_file_manifest(failed_root)
    if tree_sha256 != EXPECTED_PREWRITE_TREE_SHA256:
        raise DiagnosticError(f"Failed-root canonical tree mismatch: {tree_sha256}")
    payload = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-attempt2-full-partial-output-evidence-manifest-v1",
        "capturedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "formalRoot": str(failed_root),
        "fileCount": len(records),
        "rawBytes": raw_bytes,
        "canonicalTreeFormula": "ordinal-relative-forward-slash + TAB + byteLength + TAB + lowercase-sha256 + LF; UTF-8 no BOM",
        "canonicalTreeSha256": tree_sha256,
        "executionReceiptSha256": EXPECTED_RECEIPT_SHA256,
        "disposition": "PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS / NO-RESUME / NO-TOP-UP / NO-MERGE",
        "files": records,
    }
    atomic_write_json(output, payload)
    print(json.dumps({"passed": True, "fileCount": len(records), "rawBytes": raw_bytes, "canonicalTreeSha256": tree_sha256, "output": str(output)}, sort_keys=True))


def generate_analysis(args: argparse.Namespace) -> None:
    project_root = Path(args.project_root).resolve()
    failed_root = Path(args.failed_root).resolve()
    output_root = Path(args.output_root).resolve()
    ensure_outside(failed_root, output_root)
    manifest = read_json(Path(args.manifest).resolve())
    if manifest.get("canonicalTreeSha256") != EXPECTED_PREWRITE_TREE_SHA256 or manifest.get("fileCount") != 28020:
        raise DiagnosticError("Evidence manifest identity mismatch")
    status = read_json(project_root / "Research/Gate13R_PR2_Formal_Execution_Status.v2.json")
    checkpoint = read_json(failed_root / "formal-checkpoint.json")
    block_failure_path = failed_root / "campaigns/c52-grid-scale-g256-shared--shared/blocks/b0022/block-failure.json"
    quiescence_path = failed_root / "campaigns/c52-grid-scale-g256-shared--shared/blocks/b0022.lock-hygiene/g13rpr2-c52-b0022.quiescence-failure.json"
    block_failure = read_json(block_failure_path)
    quiescence = read_json(quiescence_path)
    launch = read_json(project_root / "Research/Verification/Gate13R_PR2_Formal_Execution_Attempt2/v1/launch-receipt.json")
    plans: dict[str, dict[str, Any]] = {}
    for plan_path in sorted((failed_root / "_plans").glob("p*.json")):
        plan = read_json(plan_path)
        block_id = str(plan.get("blockId") or "")
        if not block_id or block_id in plans:
            raise DiagnosticError(f"Duplicate or missing block ID in plan: {plan_path}")
        plans[block_id] = plan
    manifest_paths = {record["relativePath"]: record for record in manifest["files"]}
    evaluation_relatives = sorted(path for path in manifest_paths if path.endswith("/memory-gate-evaluation.json"))
    rows: list[dict[str, Any]] = []
    validation_errors: list[dict[str, Any]] = []
    for relative in evaluation_relatives:
        row, errors = normalize_memory_record(failed_root / Path(relative), failed_root, plans)
        rows.append(row)
        if errors:
            validation_errors.append({"relativePath": relative, "errors": sorted(set(errors))})
    valid_rows = [row for row in rows if row["valid"]]
    blocks = block_maxima(valid_rows)
    failed_relative = "campaigns/c52-grid-scale-g256-shared--shared/blocks/b0022/runs/p04-cff/memory-gate-evaluation.json"
    if sha256_file(failed_root / failed_relative) != FAILED_EVAL_SHA256:
        raise DiagnosticError("Failed memory evaluation SHA-256 mismatch")
    failed_rows = [row for row in rows if row["runId"] == "g13rpr2-c52-b0022-p04-cff"]
    if len(failed_rows) != 1:
        raise DiagnosticError("Expected exactly one failed C-FF memory evaluation")
    failed_row = failed_rows[0]
    failed_expected = {
        "sampleRetainedManagedGrowthBytes": 2080768,
        "blockRetainedManagedGrowthBytesAtSampleBoundary": 89227264,
        "blockWorkingSetGrowthBytesAtSampleBoundary": 614866944,
        "blockPrivateMemoryGrowthBytesAtSampleBoundary": 641327104,
        "verdict": "HARD-FAIL",
        "reasonCode": "HARD-FAIL-BLOCK-WORKING-SET-512MIB+HARD-FAIL-BLOCK-PRIVATE-MEMORY-512MIB",
    }
    for key, expected in failed_expected.items():
        if failed_row.get(key) != expected:
            raise DiagnosticError(f"Failed-row expected fact mismatch for {key}")
    summary_count = sum(path.endswith("/sample-summary.json") for path in manifest_paths)
    block_manifest_count = sum(path.endswith("/block-manifest.json") for path in manifest_paths)
    block_failure_count = sum(path.endswith("/block-failure.json") for path in manifest_paths)
    inventory = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-memory-telemetry-inventory-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "formalRootCanonicalTreeSha256": manifest["canonicalTreeSha256"],
        "memoryEvaluationCount": len(rows),
        "validMemoryEvaluationCount": len(valid_rows),
        "invalidMemoryEvaluationCount": len(validation_errors),
        "representedBlockCount": len(blocks),
        "completedBlockProcessCount": int(status["completedProcessCount"]),
        "completedSampleCount": int(status["completedSampleCount"]),
        "sampleSummaryFileCount": summary_count,
        "blockManifestFileCount": block_manifest_count,
        "blockFailureFileCount": block_failure_count,
        "blockPlanCount": len(plans),
        "verdictCounts": dict(sorted(Counter(str(row.get("verdict")) for row in rows).items())),
        "telemetrySourceCounts": dict(sorted(Counter(str(row.get("telemetrySourceId")) for row in rows).items())),
        "formalCampaignTrueCount": sum(row.get("formalCampaign") is True for row in rows),
        "failedBlockPartialEvaluationCount": sum(row["blockId"] == "g13rpr2-c52-b0022" for row in rows),
        "validationErrors": validation_errors,
        "normalizedRows": rows,
        "scopeProhibitions": ["NO-C1-C5-INFERENCE", "NO-P1-P5-PERFORMANCE-INFERENCE", "NO-FORMAL-SAMPLE-SIZE", "NO-GATE14R"],
    }
    metric_map = {
        "sampleRetainedManagedGrowthBytes": [row["sampleRetainedManagedGrowthBytes"] for row in valid_rows],
        "blockRetainedManagedGrowthBytesAtSampleBoundary": [row["blockRetainedManagedGrowthBytesAtSampleBoundary"] for row in valid_rows],
        "blockWorkingSetGrowthBytesAtSampleBoundary": [row["blockWorkingSetGrowthBytesAtSampleBoundary"] for row in valid_rows],
        "blockPrivateMemoryGrowthBytesAtSampleBoundary": [row["blockPrivateMemoryGrowthBytesAtSampleBoundary"] for row in valid_rows],
        "workingSetAfterCleanupBytes": [row["workingSetAfterCleanupBytes"] for row in valid_rows],
        "privateMemoryAfterCleanupBytes": [row["privateMemoryAfterCleanupBytes"] for row in valid_rows],
        "managedMemoryAfterCleanupBytes": [row["managedMemoryAfterCleanupBytes"] for row in valid_rows],
        "processAgeMilliseconds": [row["processAgeMilliseconds"] for row in valid_rows],
    }
    block_working = [block["maximumBlockWorkingSetGrowthBytes"] for block in blocks]
    block_private = [block["maximumBlockPrivateMemoryGrowthBytes"] for block in blocks]
    block_managed = [block["maximumBlockManagedGrowthBytes"] for block in blocks]
    threshold_distribution = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-memory-threshold-distribution-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "quantileMethod": "R-7 linear interpolation",
        "independentOperationalUnit": "one fresh Unity Williams-block process",
        "evaluationBoundaryDistributions": {name: describe(values) for name, values in metric_map.items()},
        "blockMaximumDistributions": {
            "managedGrowthBytes": describe(block_managed),
            "workingSetGrowthBytes": describe(block_working),
            "privateMemoryGrowthBytes": describe(block_private),
        },
        "currentPolicy": {
            "managed": threshold_summary(block_managed, 256 * MIB),
            "workingSet": threshold_summary(block_working, 512 * MIB),
            "privateMemory": threshold_summary(block_private, 512 * MIB),
        },
        "candidateNativeThresholds": [candidate_counts(blocks, value) for value in THRESHOLD_MIB],
        "blockMaxima": blocks,
        "observedPrefixCaveat": "Collection stopped at global process ordinal 934; unobserved schedule records are not imputed and candidate counts cannot establish full-matrix safety.",
    }
    factor_output = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-factor-position-predecessor-memory-sensitivity-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "groups": {
            key: group_metric(valid_rows, key)
            for key in ("gridSize", "scenarioId", "campaignId", "algorithmId", "position", "predecessorAlgorithmId", "williamsRowIndex")
        },
        "failedObservation": failed_row,
        "failedWorkingSetBlockMaxPercentileWithinObservedBlocks": sum(value <= failed_row["blockWorkingSetGrowthBytesAtSampleBoundary"] for value in block_working) / len(block_working),
        "failedPrivateMemoryBlockMaxPercentileWithinObservedBlocks": sum(value <= failed_row["blockPrivateMemoryGrowthBytesAtSampleBoundary"] for value in block_private) / len(block_private),
        "interpretationBoundary": "Group summaries are operational memory diagnostics only; algorithm and position are not independent because block growth accumulates within the frozen Williams order.",
    }
    started = iso_to_datetime(launch["orchestratorStartTimeUtc"])
    primary_time = iso_to_datetime(block_failure["failedAtUtc"])
    secondary_time = iso_to_datetime(quiescence["savedAtUtc"])
    terminal_time = iso_to_datetime(status["savedAtUtc"])
    timeline = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-primary-secondary-failure-timeline-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "events": [
            {"order": 1, "atUtc": started.isoformat().replace("+00:00", "Z"), "kind": "FORMAL-ATTEMPT2-LAUNCHED"},
            {"order": 2, "atUtc": primary_time.isoformat().replace("+00:00", "Z"), "kind": "PRIMARY-MEMORY-ELIGIBILITY-HARD-FAIL", "reason": block_failure["memoryGateReasonCode"]},
            {"order": 3, "atUtc": secondary_time.isoformat().replace("+00:00", "Z"), "kind": "SECONDARY-POST-EXIT-QUIESCENCE-FAIL", "reason": "Unity exited, zero Unity processes, zero-byte UnityLockfile remained"},
            {"order": 4, "atUtc": terminal_time.isoformat().replace("+00:00", "Z"), "kind": "ORCHESTRATOR-FAILED-NO-RETRY"},
        ],
        "launchToPrimaryFailureSeconds": (primary_time - started).total_seconds(),
        "primaryToSecondaryFailureSeconds": (secondary_time - primary_time).total_seconds(),
        "secondaryToTerminalStatusSeconds": (terminal_time - secondary_time).total_seconds(),
        "primaryFailure": block_failure,
        "secondaryFailure": quiescence,
        "outerStatusError": status.get("error"),
        "outerStatusMasksPrimaryCause": "Post-exit quiescence failed" in str(status.get("error")),
        "requiredCandidateSemantics": "Preserve primary block/Unity cause and separately append secondary quiescence cause; both fail closed and neither permits continuation.",
    }
    prewrite = read_json(project_root / "Research/Gate13R_PR2_Attempt2_Failure_PreWrite_Audit.v1.json")
    lock_output = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-lock-hygiene-diagnosis-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "preCleanupEvidence": prewrite["staleLock"],
        "quiescenceEvidence": quiescence,
        "primaryFailureAlreadyDurableBeforeQuiescence": primary_time < secondary_time,
        "unityProcessWasDeadAtQuiescence": quiescence.get("ownedProcessAlive") is False and quiescence.get("unityProcessCount") == 0,
        "staleLockWasExclusivelyOpenable": prewrite["staleLock"]["exclusiveReadWriteAvailable"],
        "diagnosis": "Secondary hygiene failure caused by a persistent zero-byte project lock after abnormal Unity exit; it did not cause the earlier memory eligibility failure.",
        "causeMaskingConfirmed": True,
        "cleanupChangesAttemptDisposition": False,
    }
    numeric_candidates = [candidate_counts(blocks, value) for value in THRESHOLD_MIB]
    policy_candidates = []
    for item in numeric_candidates:
        threshold = item["candidateThresholdMiB"]
        policy_candidates.append(
            {
                **item,
                "policyId": f"native-block-delta-hard-{threshold}mib-candidate",
                "scientificMeaning": "Maximum process working-set/private-memory growth from fresh block baseline.",
                "falseFailRisk": "Higher for large scenarios when Unity residency growth is expected; unknown for the unobserved suffix.",
                "falsePassRisk": "Increases as the threshold rises and may admit genuine runaway native/process growth.",
                "instrumentationAmendmentRequired": threshold != 512,
                "targetedPilotRequired": threshold != 512,
                "status": "UNFROZEN / USER-DECISION-REQUIRED",
            }
        )
    policy_candidates.extend(
        [
            {
                "policyId": "absolute-process-memory-cap-candidate",
                "scientificMeaning": "Absolute working-set/private-memory safety cap independent of baseline delta.",
                "candidateValue": None,
                "benefit": "Directly protects the 32 GiB host from absolute process exhaustion.",
                "risk": "Can hide persistent per-block growth below the cap and needs independent hardware/OS calibration.",
                "instrumentationAmendmentRequired": True,
                "targetedPilotRequired": True,
                "status": "UNFROZEN / USER-DECISION-REQUIRED",
            },
            {
                "policyId": "scenario-size-aware-envelope-candidate",
                "scientificMeaning": "Prospectively frozen native/process-memory envelope indexed by scenario scale.",
                "candidateValue": None,
                "benefit": "Can separate expected g256 residency from unexpected within-scale growth.",
                "risk": "Post-hoc envelopes would overfit this failed prefix; an independent balanced pilot is mandatory.",
                "instrumentationAmendmentRequired": True,
                "targetedPilotRequired": True,
                "status": "UNFROZEN / USER-DECISION-REQUIRED",
            },
            {
                "policyId": "managed-hard-native-advisory-plus-ram-cap-candidate",
                "scientificMeaning": "Retain managed-memory hard eligibility while treating native deltas as diagnostics under an independent absolute RAM safety cap.",
                "candidateValue": None,
                "benefit": "Avoids equating normal Unity residency with managed retention while retaining host safety.",
                "risk": "Could miss a native leak unless the absolute cap and trend rule are independently validated.",
                "instrumentationAmendmentRequired": True,
                "targetedPilotRequired": True,
                "status": "UNFROZEN / USER-DECISION-REQUIRED",
            },
        ]
    )
    matrix = {
        "schemaVersion": 1,
        "resultKind": "gate13r-pr2-attempt2-memory-policy-decision-matrix-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "hostPhysicalRamGiB": 32,
        "executionTopology": "strict serial; maximum one Unity Editor; one fresh process per Williams block",
        "observedBlockCount": len(blocks),
        "failedAttemptDispositionImmutable": True,
        "candidatePolicies": policy_candidates,
        "verdict": "TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED",
        "reason": "The observed prefix contains the first hard failure and does not cover the remaining matrix; it cannot distinguish expected g256 Unity residency from a reproducible runaway process without a prospective balanced diagnostic run.",
        "selectionStatus": "MEMORY-POLICY-UNFROZEN / USER-DECISION-REQUIRED",
    }
    outputs = {
        "memory-telemetry-inventory.json": inventory,
        "memory-threshold-distribution.json": threshold_distribution,
        "factor-position-predecessor-sensitivity.json": factor_output,
        "primary-secondary-failure-timeline.json": timeline,
        "lock-hygiene-diagnosis.json": lock_output,
        "memory-policy-decision-matrix.json": matrix,
    }
    for name, value in outputs.items():
        atomic_write_json(output_root / name, value)
    report = f"""# Gate 13R-PR2 attempt 2 failure diagnostic report v1

Status: `{' / '.join(STATUS_TOKENS)}`

- Memory evaluations: {len(rows)} total; {len(valid_rows)} valid; {len(validation_errors)} invalid.
- Represented fresh Unity blocks: {len(blocks)} (933 complete plus one failed partial block expected).
- Primary failure: `{block_failure['memoryGateReasonCode']}` at `{block_failure['failedAtUtc']}`.
- Secondary failure: persistent zero-byte UnityLockfile after Unity exit at `{quiescence['savedAtUtc']}`.
- Failed block working-set growth: {failed_row['blockWorkingSetGrowthBytesAtSampleBoundary'] / MIB:.3f} MiB.
- Failed block private-memory growth: {failed_row['blockPrivateMemoryGrowthBytesAtSampleBoundary'] / MIB:.3f} MiB.
- Failed block retained managed growth: {failed_row['blockRetainedManagedGrowthBytesAtSampleBoundary'] / MIB:.3f} MiB.
- Candidate policy status: `UNFROZEN / USER-DECISION-REQUIRED`.
- Diagnostic verdict: `TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED`.

This report is operational failure evidence only. It contains no algorithm superiority inference and cannot be merged into a formal Gate 13R analysis.
"""
    atomic_write_text(output_root / "diagnostic-report.md", report)
    evidence_files = sorted(path for path in output_root.iterdir() if path.is_file() and path.name != "evidence-manifest.json")
    evidence = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-attempt2-failure-diagnosis-output-evidence-manifest-v1",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "files": [
            {"relativePath": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
            for path in evidence_files
        ],
    }
    atomic_write_json(output_root / "evidence-manifest.json", evidence)
    print(json.dumps({"passed": not validation_errors, "evaluationCount": len(rows), "validCount": len(valid_rows), "blockCount": len(blocks), "verdict": matrix["verdict"], "outputRoot": str(output_root)}, sort_keys=True))
    if validation_errors:
        raise DiagnosticError(f"Found {len(validation_errors)} invalid memory evaluations")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    manifest_parser = subparsers.add_parser("manifest")
    manifest_parser.add_argument("--project-root", required=True)
    manifest_parser.add_argument("--failed-root", required=True)
    manifest_parser.add_argument("--output", required=True)
    manifest_parser.add_argument("--timestamp", required=True)
    analyze_parser = subparsers.add_parser("analyze")
    analyze_parser.add_argument("--project-root", required=True)
    analyze_parser.add_argument("--failed-root", required=True)
    analyze_parser.add_argument("--manifest", required=True)
    analyze_parser.add_argument("--output-root", required=True)
    analyze_parser.add_argument("--timestamp", required=True)
    args = parser.parse_args()
    if args.command == "manifest":
        generate_manifest(args)
    elif args.command == "analyze":
        generate_analysis(args)
    else:
        raise DiagnosticError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    main()
