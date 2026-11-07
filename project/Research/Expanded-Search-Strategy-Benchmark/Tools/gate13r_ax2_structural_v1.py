#!/usr/bin/env python3
"""Structural-only validation for Gate13R-AX2.

This module deliberately does not aggregate or interpret P1.  It opens the P1
field only to enforce the frozen finite-and-strictly-positive schema.
"""

from __future__ import annotations

import argparse
import collections
import copy
import datetime as dt
import hashlib
import json
import math
import os
import pathlib
import re
import sys
import tempfile
from typing import Any, Dict, Iterable, List, Mapping, Sequence


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"
COHORT_ID = "gate13r-ax2-shared-goal-v1"
SCHEDULE_KIND = "gate13r-ax2-formal-williams-block-schedule-record-v1"
ALGORITHMS = ("BiA*-R", "LPA*", "C-FF", "IDFF")
WILLIAMS_BASE = (0, 1, 3, 2)
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$")


class StructuralError(RuntimeError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise StructuralError(message)


def load_json(path: pathlib.Path) -> Any:
    require(path.is_file(), f"Required JSON file is missing: {path}")
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise StructuralError(f"Invalid UTF-8 JSON at {path}: {exc}") from exc


def load_schedule(path: pathlib.Path, expected_sha256: str) -> List[Dict[str, Any]]:
    require(HEX64.fullmatch(expected_sha256) is not None, "Expected schedule SHA-256 is malformed.")
    require(path.is_file(), f"Schedule is missing: {path}")
    actual = sha256_file(path)
    require(actual == expected_sha256, f"Schedule SHA-256 mismatch: expected {expected_sha256}, got {actual}.")
    records: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, start=1):
            require(bool(line.strip()), f"Schedule contains a blank line at {line_number}.")
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                raise StructuralError(f"Schedule JSONL line {line_number} is invalid: {exc}") from exc
            require(isinstance(value, dict), f"Schedule line {line_number} is not an object.")
            records.append(value)
    return records


def expected_williams_row(row_index: int) -> List[str]:
    require(row_index in range(4), "Williams row index is outside 0..3.")
    return [ALGORITHMS[(base + row_index) % 4] for base in WILLIAMS_BASE]


def validate_schedule_record(record: Mapping[str, Any], line_number: int | None = None) -> None:
    where = f"schedule line {line_number}" if line_number is not None else "schedule record"
    require(record.get("schemaVersion") == 1, f"{where}: schemaVersion mismatch.")
    require(record.get("scheduleKind") == SCHEDULE_KIND, f"{where}: scheduleKind mismatch.")
    require(record.get("designId") == DESIGN_ID, f"{where}: designId mismatch.")
    require(record.get("comparisonCohortId") == COHORT_ID, f"{where}: cohort mismatch.")
    block_id = record.get("blockId")
    campaign_id = record.get("campaignId")
    require(isinstance(block_id, str) and SAFE_ID.fullmatch(block_id) is not None, f"{where}: unsafe blockId.")
    require(isinstance(campaign_id, str) and SAFE_ID.fullmatch(campaign_id) is not None, f"{where}: unsafe campaignId.")
    campaign = record.get("campaignOrdinal")
    block = record.get("campaignBlockOrdinal")
    global_block = record.get("globalBlockOrdinal")
    row = record.get("williamsRowIndex")
    require(isinstance(campaign, int) and 1 <= campaign <= 32, f"{where}: campaign ordinal mismatch.")
    require(isinstance(block, int) and 1 <= block <= 48, f"{where}: campaign block ordinal mismatch.")
    require(isinstance(global_block, int) and global_block == (campaign - 1) * 48 + block, f"{where}: global block ordinal mismatch.")
    require(row == (block - 1) % 4, f"{where}: Williams row rotation mismatch.")
    require(record.get("expectedSampleCount") == 4, f"{where}: expected sample count mismatch.")
    entries = record.get("entries")
    require(isinstance(entries, list) and len(entries) == 4, f"{where}: exactly four entries are required.")
    expected = expected_williams_row(row)
    seen_runs: set[str] = set()
    for index, entry in enumerate(entries):
        require(isinstance(entry, dict), f"{where}: entry {index + 1} is not an object.")
        predecessor = "NONE" if index == 0 else expected[index - 1]
        require(entry.get("position") == index + 1, f"{where}: entry position mismatch.")
        require(entry.get("algorithmId") == expected[index], f"{where}: algorithm order mismatch.")
        require(entry.get("predecessorAlgorithmId") == predecessor, f"{where}: predecessor mismatch.")
        run_id = entry.get("runId")
        require(isinstance(run_id, str) and SAFE_ID.fullmatch(run_id) is not None and run_id not in seen_runs, f"{where}: unsafe or duplicate runId.")
        seen_runs.add(run_id)
        child = entry.get("childDirectory")
        require(isinstance(child, str) and child and not pathlib.PurePath(child).is_absolute(), f"{where}: child directory is unsafe.")
        require(".." not in pathlib.PurePosixPath(child.replace("\\", "/")).parts, f"{where}: child directory escapes its root.")


def find_schedule_record(records: Sequence[Mapping[str, Any]], block_id: str) -> Mapping[str, Any]:
    matches = [record for record in records if record.get("blockId") == block_id]
    require(len(matches) == 1, f"Expected exactly one schedule record for {block_id}, found {len(matches)}.")
    validate_schedule_record(matches[0])
    return matches[0]


def validate_full_schedule(
    project_root: pathlib.Path,
    schedule_path: pathlib.Path,
    expected_sha256: str,
) -> Dict[str, Any]:
    records = load_schedule(schedule_path, expected_sha256)
    require(len(records) == 1536, f"Expected 1536 schedule records, found {len(records)}.")
    block_ids: set[str] = set()
    campaign_ids: Dict[int, str] = {}
    campaign_counts: collections.Counter[int] = collections.Counter()
    row_counts: collections.Counter[int] = collections.Counter()
    position_counts: Dict[str, collections.Counter[int]] = {name: collections.Counter() for name in ALGORITHMS}
    scenario_paths: Dict[str, str] = {}
    scenario_hashes: Dict[str, str] = {}
    for line_number, record in enumerate(records, start=1):
        validate_schedule_record(record, line_number)
        require(record["globalBlockOrdinal"] == line_number, f"Schedule line {line_number}: execution order is discontinuous.")
        require(record["blockId"] not in block_ids, f"Schedule line {line_number}: duplicate blockId.")
        block_ids.add(record["blockId"])
        campaign = record["campaignOrdinal"]
        campaign_counts[campaign] += 1
        row_counts[record["williamsRowIndex"]] += 1
        previous_campaign_id = campaign_ids.setdefault(campaign, record["campaignId"])
        require(previous_campaign_id == record["campaignId"], f"Campaign ordinal {campaign} maps to multiple IDs.")
        scenario_paths.setdefault(record["scenarioId"], record["scenarioRelativePath"])
        require(scenario_paths[record["scenarioId"]] == record["scenarioRelativePath"], "Scenario path drift within schedule.")
        scenario_hashes.setdefault(record["scenarioId"], record["scenarioSha256"])
        require(scenario_hashes[record["scenarioId"]] == record["scenarioSha256"], "Scenario SHA drift within schedule.")
        for entry in record["entries"]:
            position_counts[entry["algorithmId"]][entry["position"]] += 1
    require(sorted(campaign_ids) == list(range(1, 33)), "Campaign ordinals are not exactly 1..32.")
    require(all(campaign_counts[index] == 48 for index in range(1, 33)), "Each campaign must contain exactly 48 blocks.")
    require(all(row_counts[index] == 384 for index in range(4)), "Williams rows are not globally balanced.")
    for algorithm in ALGORITHMS:
        require(all(position_counts[algorithm][position] == 384 for position in range(1, 5)), f"Position balance failed for {algorithm}.")
    for scenario_id, relative in scenario_paths.items():
        candidate = (project_root / pathlib.PurePosixPath(relative)).resolve()
        require(candidate.is_relative_to(project_root.resolve()), f"Scenario path escapes project root: {relative}")
        require(candidate.is_file(), f"Frozen scenario is missing: {relative}")
        require(sha256_file(candidate) == scenario_hashes[scenario_id], f"Frozen scenario SHA mismatch: {relative}")
    return {
        "scheduleSha256": expected_sha256,
        "recordCount": len(records),
        "campaignCount": len(campaign_ids),
        "blocksPerCampaign": 48,
        "sampleCount": len(records) * 4,
        "scenarioFileCount": len(scenario_paths),
        "williamsRowCounts": {str(index): row_counts[index] for index in range(4)},
        "perAlgorithmPositionCounts": {
            algorithm: {str(position): position_counts[algorithm][position] for position in range(1, 5)}
            for algorithm in ALGORITHMS
        },
    }


def resolve_relative(root: pathlib.Path, relative: str, label: str) -> pathlib.Path:
    require(isinstance(relative, str) and relative, f"{label} path is missing.")
    pure = pathlib.PurePosixPath(relative.replace("\\", "/"))
    require(not pure.is_absolute() and ".." not in pure.parts, f"{label} path is unsafe: {relative}")
    candidate = (root / pure).resolve()
    require(candidate.is_relative_to(root.resolve()), f"{label} path escapes its root: {relative}")
    return candidate


def require_fields(value: Mapping[str, Any], fields: Iterable[str], label: str) -> None:
    missing = [field for field in fields if field not in value]
    require(not missing, f"{label} is missing fields: {', '.join(missing)}")


def validate_reference(sample_root: pathlib.Path, reference: Any, label: str) -> pathlib.Path:
    require(isinstance(reference, dict), f"{label} reference is not an object.")
    require_fields(reference, ("relativePath", "sha256", "bytes"), label)
    path = resolve_relative(sample_root, reference["relativePath"], label)
    require(path.is_file(), f"{label} file is missing: {path}")
    require(isinstance(reference["bytes"], int) and path.stat().st_size == reference["bytes"], f"{label} byte count mismatch.")
    require(isinstance(reference["sha256"], str) and HEX64.fullmatch(reference["sha256"]) is not None, f"{label} SHA-256 is malformed.")
    require(sha256_file(path) == reference["sha256"], f"{label} SHA-256 mismatch.")
    return path


def validate_block(
    attempt_root: pathlib.Path,
    schedule_path: pathlib.Path,
    schedule_sha256: str,
    schema_path: pathlib.Path,
    schema_sha256: str,
    contract_sha256: str,
    block_id: str,
    expected_process_id: int | None,
) -> Dict[str, Any]:
    require(attempt_root.is_dir(), f"Block attempt directory is missing: {attempt_root}")
    require(schema_path.is_file() and sha256_file(schema_path) == schema_sha256, "Output-schema binding mismatch.")
    schema = load_json(schema_path)
    require(schema.get("artifactKind") == "GATE13R-AX2-OUTPUT-SCHEMA" and schema.get("designId") == DESIGN_ID, "Output schema identity mismatch.")
    require(HEX64.fullmatch(contract_sha256) is not None, "Execution-contract SHA-256 is malformed.")
    records = load_schedule(schedule_path, schedule_sha256)
    record = find_schedule_record(records, block_id)
    require(not (attempt_root / "block-failure.v1.json").exists(), "A failed block cannot be accepted.")
    complete_path = attempt_root / "block-complete.v1.json"
    complete = load_json(complete_path)
    required_block = (
        "schemaVersion", "artifactKind", "designId", "blockId", "campaignId",
        "campaignBlockOrdinal", "globalBlockOrdinal", "williamsRowIndex", "comparisonCohortId",
        "scenarioId", "scenarioSha256", "scenarioFingerprintSha256", "scheduleSha256",
        "outputSchemaSha256", "executionContractSha256", "processId", "processStartUtc",
        "expectedSampleCount", "completedSampleCount", "oneFreshProcessForCompleteBlock",
        "strictSerialWilliamsOrder", "noPerAlgorithmRetryResumeTopUpMergeSkipReorder", "samples", "completed",
    )
    require_fields(complete, required_block, "block-complete receipt")
    require(complete["schemaVersion"] == 1 and complete["artifactKind"] == "GATE13R-AX2-BLOCK-COMPLETE", "Block receipt schema mismatch.")
    for key in ("designId", "blockId", "campaignId", "campaignBlockOrdinal", "globalBlockOrdinal", "williamsRowIndex", "comparisonCohortId", "scenarioId", "scenarioSha256", "scenarioFingerprintSha256"):
        require(complete[key] == record[key], f"Block receipt {key} does not match schedule.")
    require(complete["scheduleSha256"] == schedule_sha256, "Block schedule binding mismatch.")
    require(complete["outputSchemaSha256"] == schema_sha256, "Block output-schema binding mismatch.")
    require(complete["executionContractSha256"] == contract_sha256, "Block execution-contract binding mismatch.")
    if expected_process_id is not None:
        require(complete["processId"] == expected_process_id, "Block process identity does not match supervisor observation.")
    require(complete["expectedSampleCount"] == 4 and complete["completedSampleCount"] == 4, "Block sample cardinality mismatch.")
    require(complete["oneFreshProcessForCompleteBlock"] is True, "Fresh-process block invariant is false.")
    require(complete["strictSerialWilliamsOrder"] is True, "Serial Williams order invariant is false.")
    require(complete["noPerAlgorithmRetryResumeTopUpMergeSkipReorder"] is True, "Forbidden per-algorithm action invariant is false.")
    require(complete["completed"] is True, "Block receipt is not complete.")
    samples = complete["samples"]
    require(isinstance(samples, list) and len(samples) == 4, "Block sample references must contain exactly four entries.")
    seen_sample_dirs: set[pathlib.Path] = set()
    for index, (entry, sample_ref) in enumerate(zip(record["entries"], samples), start=1):
        require(isinstance(sample_ref, dict), f"Sample reference {index} is not an object.")
        require(sample_ref.get("position") == index, f"Sample reference {index} position mismatch.")
        require(sample_ref.get("algorithmId") == entry["algorithmId"], f"Sample reference {index} algorithm mismatch.")
        require(sample_ref.get("runId") == entry["runId"], f"Sample reference {index} runId mismatch.")
        sample_root = resolve_relative(attempt_root, sample_ref.get("sampleDirectory"), f"sample {index}")
        require(sample_root.is_dir() and sample_root not in seen_sample_dirs, f"Sample directory {index} is missing or duplicated.")
        seen_sample_dirs.add(sample_root)
        manifest_path = resolve_relative(attempt_root, sample_ref.get("manifestRelativePath"), f"sample {index} manifest")
        result_path = resolve_relative(attempt_root, sample_ref.get("workloadResultRelativePath"), f"sample {index} workload")
        require(manifest_path.is_file() and result_path.is_file(), f"Sample {index} manifest/workload file is missing.")
        require(sha256_file(manifest_path) == sample_ref.get("manifestSha256"), f"Sample {index} manifest hash mismatch.")
        require(sha256_file(result_path) == sample_ref.get("workloadResultSha256"), f"Sample {index} workload hash mismatch.")
        manifest = load_json(manifest_path)
        require_fields(manifest, schema["sampleManifestRequiredFields"], f"sample {index} manifest")
        for key in ("designId", "blockId", "campaignId", "campaignBlockOrdinal", "globalBlockOrdinal", "williamsRowIndex", "comparisonCohortId", "scenarioId", "scenarioSha256", "scenarioFingerprintSha256"):
            expected_value = DESIGN_ID if key == "designId" else (block_id if key == "blockId" else record[key])
            require(manifest[key] == expected_value, f"Sample {index} manifest {key} mismatch.")
        require(manifest["position"] == index and manifest["runId"] == entry["runId"], f"Sample {index} position/runId mismatch.")
        require(manifest["algorithmId"] == entry["algorithmId"] and manifest["predecessorAlgorithmId"] == entry["predecessorAlgorithmId"], f"Sample {index} Williams identity mismatch.")
        require(manifest["scheduleSha256"] == schedule_sha256 and manifest["outputSchemaSha256"] == schema_sha256 and manifest["executionContractSha256"] == contract_sha256, f"Sample {index} frozen binding mismatch.")
        require(manifest["processId"] == complete["processId"] and manifest["processStartUtc"] == complete["processStartUtc"], f"Sample {index} process identity mismatch.")
        require(manifest["freshPlannerInstance"] is True and manifest["plannerResetCompleted"] is True and manifest["workloadCompleted"] is True and manifest["completed"] is True, f"Sample {index} completion invariant failed.")
        manifest_p1 = manifest["p1RawGeometricMeanInputMillisecondsPerScheduledEvent"]
        require(isinstance(manifest_p1, (int, float)) and not isinstance(manifest_p1, bool) and math.isfinite(manifest_p1) and manifest_p1 > 0.0, f"Sample {index} P1 fails finite-positive schema validation.")
        canonical_path = validate_reference(sample_root, manifest["canonicalScenario"], f"sample {index} canonical scenario")
        operations_path = validate_reference(sample_root, manifest["operationsLog"], f"sample {index} operations log")
        referenced_result_path = validate_reference(sample_root, manifest["workloadResult"], f"sample {index} workload result")
        require(referenced_result_path == result_path.resolve(), f"Sample {index} workload reference path mismatch.")
        require(canonical_path.name == "scenario.canonical.json" and operations_path.name == "operations.v1.jsonl", f"Sample {index} required filename mismatch.")
        result = load_json(result_path)
        require_fields(result, schema["workloadResultRequiredFields"], f"sample {index} workload result")
        require(result["runId"] == entry["runId"] and result["scenarioId"] == record["scenarioId"] and result["algorithmId"] == entry["algorithmId"], f"Sample {index} workload identity mismatch.")
        require(result["comparisonCohortId"] == COHORT_ID and result["completed"] is True, f"Sample {index} workload cohort/completion mismatch.")
        p1 = result["dynamicHandlingMillisecondsPerScheduledEvent"]
        require(isinstance(p1, (int, float)) and not isinstance(p1, bool) and math.isfinite(p1) and p1 > 0.0, f"Sample {index} workload P1 fails finite-positive schema validation.")
        require(p1 == manifest_p1, f"Sample {index} P1 alias mismatch.")
        require(result["scheduledEventCount"] == manifest["scheduledEventCount"] and isinstance(result["scheduledEventCount"], int) and result["scheduledEventCount"] > 0, f"Sample {index} scheduled-event cardinality mismatch.")
        with operations_path.open("r", encoding="utf-8") as stream:
            operation_lines = [line for line in stream if line.strip()]
        require(operation_lines, f"Sample {index} operations log is empty.")
        for operation_line_number, line in enumerate(operation_lines, start=1):
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError as exc:
                raise StructuralError(f"Sample {index} operation line {operation_line_number} is invalid JSON: {exc}") from exc
            require(isinstance(parsed, dict), f"Sample {index} operation line {operation_line_number} is not an object.")
    return {
        "blockId": block_id,
        "processId": complete["processId"],
        "processStartUtc": complete["processStartUtc"],
        "sampleCount": 4,
        "algorithmIdsInObservedOrder": [sample["algorithmId"] for sample in samples],
        "manifestCount": 4,
        "workloadResultCount": 4,
        "p1SchemaChecksPassed": 4,
        "p1AggregatedOrInterpreted": False,
        "blockCompleteSha256": sha256_file(complete_path),
    }


def run_selftest() -> Dict[str, Any]:
    assertions = 0
    row_expectations = [
        ["BiA*-R", "LPA*", "IDFF", "C-FF"],
        ["LPA*", "C-FF", "BiA*-R", "IDFF"],
        ["C-FF", "IDFF", "LPA*", "BiA*-R"],
        ["IDFF", "BiA*-R", "C-FF", "LPA*"],
    ]
    for index, expected in enumerate(row_expectations):
        require(expected_williams_row(index) == expected, f"Selftest Williams row {index} differs.")
        assertions += 1
    template = {
        "schemaVersion": 1,
        "scheduleKind": SCHEDULE_KIND,
        "designId": DESIGN_ID,
        "blockId": "g13rax2-c01-b0001",
        "campaignId": "core-r01-s1-shared--shared",
        "campaignOrdinal": 1,
        "comparisonCohortId": COHORT_ID,
        "campaignBlockOrdinal": 1,
        "globalBlockOrdinal": 1,
        "williamsRowIndex": 0,
        "expectedSampleCount": 4,
        "entries": [],
    }
    for index, algorithm in enumerate(row_expectations[0], start=1):
        template["entries"].append({
            "position": index,
            "algorithmId": algorithm,
            "predecessorAlgorithmId": "NONE" if index == 1 else row_expectations[0][index - 2],
            "runId": f"g13rax2-c01-b0001-p{index:02d}",
            "childDirectory": f"runs/p{index:02d}",
        })
    validate_schedule_record(template)
    assertions += 1
    mutations = [
        ("wrong-order", lambda value: value["entries"].__setitem__(0, {**value["entries"][0], "algorithmId": "IDFF"})),
        ("wrong-global", lambda value: value.__setitem__("globalBlockOrdinal", 2)),
        ("unsafe-child", lambda value: value["entries"][0].__setitem__("childDirectory", "../escape")),
        ("wrong-cohort", lambda value: value.__setitem__("comparisonCohortId", "wrong")),
    ]
    rejected: List[str] = []
    for name, mutate in mutations:
        candidate = copy.deepcopy(template)
        mutate(candidate)
        try:
            validate_schedule_record(candidate)
        except StructuralError:
            rejected.append(name)
            assertions += 1
        else:
            raise StructuralError(f"Selftest failed to reject {name}.")
    with tempfile.TemporaryDirectory(prefix="gate13r-ax2-structural-") as temp_name:
        root = pathlib.Path(temp_name)
        inside = resolve_relative(root, "runs/p01", "selftest")
        require(inside.is_relative_to(root.resolve()), "Selftest containment failed.")
        assertions += 1
        try:
            resolve_relative(root, "../escape", "selftest")
        except StructuralError:
            rejected.append("path-escape")
            assertions += 1
        else:
            raise StructuralError("Selftest failed to reject a path escape.")
        payload = b"gate13r-ax2\n"
        require(len(sha256_bytes(payload)) == 64, "Selftest SHA-256 length failed.")
        assertions += 1
    return {
        "assertionCount": assertions,
        "negativeCasesRejected": rejected,
        "p1AggregatedOrInterpreted": False,
    }


def command_validate_schedule(args: argparse.Namespace) -> int:
    details = validate_full_schedule(args.project_root.resolve(), args.schedule.resolve(), args.schedule_sha256.lower())
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-STRUCTURAL-SCHEDULE-VALIDATION",
        "designId": DESIGN_ID,
        "status": "PASS",
        "validatedAtUtc": utc_now(),
        "details": details,
        "formalCollectionStarted": False,
        "originalGate13RRawOrAnalysisReadOrModified": False,
    }
    write_json_new(args.receipt.resolve(), receipt)
    print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), **details}, sort_keys=True))
    return 0


def command_validate_block(args: argparse.Namespace) -> int:
    details = validate_block(
        args.attempt_root.resolve(), args.schedule.resolve(), args.schedule_sha256.lower(),
        args.schema.resolve(), args.schema_sha256.lower(), args.contract_sha256.lower(),
        args.block_id, args.expected_process_id,
    )
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-STRUCTURAL-BLOCK-VALIDATION",
        "designId": DESIGN_ID,
        "status": "PASS",
        "validatedAtUtc": utc_now(),
        "attemptRoot": str(args.attempt_root.resolve()),
        "details": details,
        "p1AggregatedOrInterpreted": False,
    }
    write_json_new(args.receipt.resolve(), receipt)
    print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), **details}, sort_keys=True))
    return 0


def command_selftest(args: argparse.Namespace) -> int:
    details = run_selftest()
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-STRUCTURAL-SELFTEST",
        "designId": DESIGN_ID,
        "status": "PASS",
        "validatedAtUtc": utc_now(),
        **details,
    }
    write_json_new(args.receipt.resolve(), receipt)
    print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), **details}, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    schedule = subparsers.add_parser("validate-schedule")
    schedule.add_argument("--project-root", type=pathlib.Path, required=True)
    schedule.add_argument("--schedule", type=pathlib.Path, required=True)
    schedule.add_argument("--schedule-sha256", required=True)
    schedule.add_argument("--receipt", type=pathlib.Path, required=True)
    schedule.set_defaults(handler=command_validate_schedule)
    block = subparsers.add_parser("validate-block")
    block.add_argument("--attempt-root", type=pathlib.Path, required=True)
    block.add_argument("--schedule", type=pathlib.Path, required=True)
    block.add_argument("--schedule-sha256", required=True)
    block.add_argument("--schema", type=pathlib.Path, required=True)
    block.add_argument("--schema-sha256", required=True)
    block.add_argument("--contract-sha256", required=True)
    block.add_argument("--block-id", required=True)
    block.add_argument("--expected-process-id", type=int)
    block.add_argument("--receipt", type=pathlib.Path, required=True)
    block.set_defaults(handler=command_validate_block)
    selftest = subparsers.add_parser("selftest")
    selftest.add_argument("--receipt", type=pathlib.Path, required=True)
    selftest.set_defaults(handler=command_selftest)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except (StructuralError, OSError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
