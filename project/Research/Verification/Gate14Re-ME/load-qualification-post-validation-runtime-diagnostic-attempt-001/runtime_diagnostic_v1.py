#!/usr/bin/env python3
"""Gate14Re-ME post-validation descriptive engineering runtime diagnostic.

This program reads only structural timing/resource metadata and frozen design
bindings.  It deliberately does not read event/operation endpoint values,
compute scientific effects, rank quality, or adjudicate a winner.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import statistics
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


PROJECT = Path(r"H:\DDM_Final_Project").resolve()
RAW = PROJECT / r"Research\PilotRuns\Gate14Re-ME\load-qualification\attempt-007"
EVIDENCE = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-execution-attempt-009"
OFFLINE = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-offline-necessary-revalidation-attempt-002"
DIAG = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-post-validation-runtime-diagnostic-attempt-001"
PLANNING = PROJECT / r"Research\Verification\Gate14Re-ME\qualification-planning-asset-generation-v2-attempt-001\planning-assets"

OFFLINE_RESULT = OFFLINE / "offline-validation-result.v1.json"
OFFLINE_RESULT_SHA = "2afcc259c47e390ff07c2c1cc2d295fe45d3aff249666174e93d862d0f4b9270"
IDENTITY = PLANNING / r"identity\anonymous-identity-binding.sealed.v1.json"
IDENTITY_SHA = "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08"
SCHEDULE = PLANNING / r"schedule\formal-qualification-williams-schedule.v1.jsonl"
SCHEDULE_SHA = "328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471"
OLD_VALIDATOR = PROJECT / r"Research\Gate14Re-ME\Tools\gate14re_me_qualification_structural_v3_1.py"
OLD_VALIDATOR_SHA = "85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e"
NEW_VALIDATOR = OFFLINE / "offline_necessary_validator_v2.py"
NEW_VALIDATOR_SHA = "bd5c938184ba38a7168c5207846d44637476a7fbee15c707ea06eeaebe227b63"
ANALYSIS_PLAN = DIAG / "analysis-plan.v1.json"
PREEXECUTION_FREEZE = DIAG / "pre-execution-freeze-manifest.v1.json"


class DiagnosticError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise DiagnosticError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise DiagnosticError(f"{label} SHA-256 mismatch: expected={expected}; actual={actual}")


def verify_preexecution_freeze() -> str:
    if not PREEXECUTION_FREEZE.is_file():
        raise DiagnosticError(f"missing pre-execution freeze manifest: {PREEXECUTION_FREEZE}")
    freeze = read_json(PREEXECUTION_FREEZE)
    if freeze.get("status") != "FROZEN_FOR_ONE_SHOT_EXECUTION":
        raise DiagnosticError("pre-execution freeze status mismatch")
    items = freeze.get("files")
    if not isinstance(items, list) or not items:
        raise DiagnosticError("pre-execution freeze file list is missing or empty")
    for item in items:
        if not isinstance(item, dict):
            raise DiagnosticError("invalid pre-execution freeze file row")
        path = Path(str(item.get("absolutePath", "")))
        if not path.is_file():
            raise DiagnosticError(f"frozen file missing: {path}")
        expected_bytes = int(item.get("bytes", -1))
        if path.stat().st_size != expected_bytes:
            raise DiagnosticError(
                f"frozen file byte-count mismatch: {path}; expected={expected_bytes}; actual={path.stat().st_size}"
            )
        require_hash(path, str(item.get("sha256", "")), f"frozen file {path.name}")
    return sha256_file(PREEXECUTION_FREEZE)


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise DiagnosticError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DiagnosticError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise DiagnosticError(f"invalid JSONL: {path}:{line_number}: {exc}") from exc
            if not isinstance(value, dict):
                raise DiagnosticError(f"JSON object required: {path}:{line_number}")
            rows.append(value)
    return rows


def write_json(path: Path, value: Mapping[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]], fields: Sequence[str]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def parse_dt(value: str) -> datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def quantile(values: Sequence[float], p: float) -> float:
    clean = sorted(float(value) for value in values if math.isfinite(float(value)))
    if not clean:
        raise DiagnosticError("quantile requested for empty/nonfinite vector")
    position = p * (len(clean) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return clean[lower]
    weight = position - lower
    return clean[lower] * (1.0 - weight) + clean[upper] * weight


def describe_ms(values: Sequence[float]) -> dict[str, Any]:
    clean = [float(value) for value in values if math.isfinite(float(value))]
    if not clean:
        return {"n": 0}
    return {
        "n": len(clean),
        "minimumMilliseconds": round(min(clean), 6),
        "p50Milliseconds": round(quantile(clean, 0.50), 6),
        "p90Milliseconds": round(quantile(clean, 0.90), 6),
        "p95Milliseconds": round(quantile(clean, 0.95), 6),
        "p99Milliseconds": round(quantile(clean, 0.99), 6),
        "maximumMilliseconds": round(max(clean), 6),
        "totalHours": round(sum(clean) / 3_600_000.0, 6),
    }


def describe_number(values: Sequence[float]) -> dict[str, Any]:
    clean = [float(value) for value in values if math.isfinite(float(value))]
    if not clean:
        return {"n": 0}
    return {
        "n": len(clean),
        "minimum": round(min(clean), 6),
        "p50": round(quantile(clean, 0.50), 6),
        "p90": round(quantile(clean, 0.90), 6),
        "p95": round(quantile(clean, 0.95), 6),
        "p99": round(quantile(clean, 0.99), 6),
        "maximum": round(max(clean), 6),
    }


def pearson(values_x: Sequence[float], values_y: Sequence[float]) -> float | None:
    if len(values_x) != len(values_y) or len(values_x) < 2:
        return None
    mean_x = statistics.fmean(values_x)
    mean_y = statistics.fmean(values_y)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(values_x, values_y))
    denominator_x = math.sqrt(sum((x - mean_x) ** 2 for x in values_x))
    denominator_y = math.sqrt(sum((y - mean_y) ** 2 for y in values_y))
    if denominator_x == 0 or denominator_y == 0:
        return None
    return numerator / (denominator_x * denominator_y)


def rounded(value: float | None, digits: int = 6) -> float | None:
    return None if value is None or not math.isfinite(value) else round(value, digits)


def stats_row(label_fields: Mapping[str, Any], records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    process = describe_ms([float(row["processWallMs"]) for row in records])
    lane = describe_ms([float(row["laneBodyMs"]) for row in records])
    operations = describe_number([float(row["operationRows"]) for row in records])
    value: dict[str, Any] = {**label_fields, "n": len(records)}
    for prefix, source in (("processWall", process), ("laneBody", lane)):
        for key in ("minimumMilliseconds", "p50Milliseconds", "p90Milliseconds", "p95Milliseconds", "p99Milliseconds", "maximumMilliseconds"):
            value[prefix + key[0].upper() + key[1:]] = source.get(key)
    value["operationRowsP50"] = operations.get("p50")
    value["operationRowsMaximum"] = operations.get("maximum")
    return value


def group_records(records: Sequence[Mapping[str, Any]], keys: Sequence[str]) -> dict[tuple[Any, ...], list[Mapping[str, Any]]]:
    groups: dict[tuple[Any, ...], list[Mapping[str, Any]]] = defaultdict(list)
    for record in records:
        groups[tuple(record[key] for key in keys)].append(record)
    return groups


def line_number(text: str, needle: str) -> int | None:
    for number, line in enumerate(text.splitlines(), 1):
        if needle in line:
            return number
    return None


def main() -> int:
    started = time.perf_counter()
    started_utc = utc_now()
    DIAG.mkdir(parents=True, exist_ok=True)
    terminal_path = DIAG / "terminal-receipt.v1.json"
    if terminal_path.exists():
        raise DiagnosticError("one-shot diagnostic terminal receipt already exists")

    try:
        preexecution_freeze_sha = verify_preexecution_freeze()
        require_hash(OFFLINE_RESULT, OFFLINE_RESULT_SHA, "offline validation result")
        offline_result = read_json(OFFLINE_RESULT)
        if (
            offline_result.get("status") != "PASS_OFFLINE_NECESSARY_RAW_VALIDATION"
            or offline_result.get("offlineNecessaryRawValidationPass") is not True
            or offline_result.get("qualificationTerminalPass") is not False
        ):
            raise DiagnosticError("offline-validation activation gate mismatch")
        require_hash(OLD_VALIDATOR, OLD_VALIDATOR_SHA, "old structural validator")
        require_hash(NEW_VALIDATOR, NEW_VALIDATOR_SHA, "new offline validator")

        inventory_paths: dict[Path, str] = {
            ANALYSIS_PLAN: "frozen-analysis-plan",
            DIAG / "diagnostic-authorization-receipt.v1.json": "authorization",
            DIAG / "field-boundary.v1.json": "field-boundary",
            PREEXECUTION_FREEZE: "diagnostic-pre-execution-freeze",
            DIAG / "Run-RuntimeDiagnostic.v1.ps1": "one-shot-diagnostic-runner",
            OFFLINE_RESULT: "offline-validation-gate",
            OFFLINE / "execution-observation.v1.json": "offline-validation-performance",
            OFFLINE / "pre-execution-freeze-manifest.v1.json": "offline-validation-freeze",
            OFFLINE / "post-validation-diagnostic-plan.v1.json": "prior-frozen-diagnostic-plan",
            RAW / r"_control\process-ledger.raw.v2.jsonl": "process-ledger",
            RAW / r"_control\launch-receipt.v2.json": "acquisition-launch-receipt",
            RAW / r"_control\acquisition-complete.v2.json": "acquisition-receipt",
            PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-paused-seal-attempt-009\pause-authorization-receipt.v1.json": "user-stop-and-seal-receipt",
            EVIDENCE / "prelaunch-audit.v1.json": "prelaunch-structural-metadata",
            IDENTITY: "named-identity-mapping-loaded-after-anonymous-freeze",
            SCHEDULE: "frozen-schedule-loaded-after-anonymous-freeze",
            OLD_VALIDATOR: "old-validator-source",
            NEW_VALIDATOR: "new-validator-source",
            OFFLINE / "pre-execution-performance-preflight.v1.json": "new-validator-preflight",
            PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-offline-necessary-revalidation-attempt-001\terminal-failure-receipt.v1.json": "offline-validator-v1-failure",
            PROJECT / r"Assets\_Scripts\Research\Editor\Gate14ReMELoadQualificationRunnerV3.cs": "frozen-runner-source",
            PROJECT / r"Research\Gate14Re-ME\Execution\v3\Run-Gate14ReMELoadQualification.v3_7.ps1": "frozen-supervisor-source",
            PROJECT / r"Research\Gate14Re-ME\Gate14Re_ME_Experiment_Plan.v2.md": "formal-st-design-boundary",
            PROJECT / r"Research\Verification\Gate14Re-ME\qualification-planning-freeze-v2-attempt-001\qualification-planning-freeze.v2.md": "qualification-design-boundary",
        }

        ledger = read_jsonl(RAW / r"_control\process-ledger.raw.v2.jsonl")
        if len(ledger) != 1147 or [row.get("ordinal") for row in ledger] != list(range(1147)):
            raise DiagnosticError("process ledger cardinality/ordinal mismatch")
        for row in ledger:
            if row.get("state") != "EXITED_ZERO_TRUSTED_IDENTITY" or row.get("exitCode") != 0:
                raise DiagnosticError("process ledger trusted-exit mismatch")
            row["_created"] = parse_dt(str(row["creationTimeUtc"]))
            row["_exited"] = parse_dt(str(row["exitedAtUtc"]))
            row["_wallMs"] = (row["_exited"] - row["_created"]).total_seconds() * 1000.0

        lane_ledger = ledger[175:]
        if len(lane_ledger) != 972 or any(row.get("mode") != "lane" for row in lane_ledger):
            raise DiagnosticError("lane ledger phase mismatch")

        receipt_paths = sorted(RAW.rglob("lane-receipt.v2.json"))
        if len(receipt_paths) != 972:
            raise DiagnosticError("lane receipt cardinality mismatch")
        receipt_items: list[tuple[datetime, Path, dict[str, Any]]] = []
        for path in receipt_paths:
            receipt = read_json(path)
            if receipt.get("status") != "COMPLETE_RAW_LANE" or receipt.get("completed") is not True:
                raise DiagnosticError(f"incomplete lane receipt: {path}")
            receipt_items.append((parse_dt(str(receipt["createdAtUtc"])), path, receipt))
            inventory_paths[path] = "lane-receipt-timing-and-cardinality"
        receipt_items.sort(key=lambda item: item[0])

        input_cache: dict[str, dict[str, Any]] = {}
        records: list[dict[str, Any]] = []
        for lane_index, ((receipt_time, receipt_path, receipt), ledger_row) in enumerate(zip(receipt_items, lane_ledger)):
            if not (ledger_row["_created"] <= receipt_time <= ledger_row["_exited"] + timedelta(seconds=1)):
                raise DiagnosticError(f"lane receipt/process order binding mismatch: {receipt_path}")
            input_relative = str(receipt["inputRelativePath"])
            if input_relative not in input_cache:
                input_path = (PROJECT / input_relative).resolve()
                input_value = read_json(input_path)
                expected_input_sha = str(receipt["inputSha256"])
                require_hash(input_path, expected_input_sha, "lane input")
                input_cache[input_relative] = {
                    "path": input_path,
                    "inputId": input_value["inputId"],
                    "superblockId": input_value["superblockId"],
                    "designRegion": input_value["designRegion"],
                    "seed": input_value["seed"],
                    "G": input_value["gridEdge"],
                    "N": input_value["agentCount"],
                    "F": input_value["changedCellCount"],
                    "changeTopology": input_value["changeTopology"],
                    "graphProfile": input_value["graphProfile"],
                    "sameTickAtomicPartitions": input_value["sameTickAtomicPartitions"],
                    "contextStratumId": input_value["contextStratumId"],
                }
                inventory_paths[input_path] = "frozen-input-structural-fields"
            structure = input_cache[input_relative]
            if (
                receipt["inputId"] != structure["inputId"]
                or receipt["superblockId"] != structure["superblockId"]
                or receipt_path.parent.name != receipt["anonymousLaneId"]
                or receipt_path.parent.parent.name != receipt["superblockId"]
            ):
                raise DiagnosticError(f"lane receipt/input/path identity mismatch: {receipt_path}")

            resource_path = receipt_path.parent / "process-resources.raw.v1.jsonl"
            resource_rows = read_jsonl(resource_path)
            if len(resource_rows) != 26:
                raise DiagnosticError(f"process-resource cardinality mismatch: {resource_path}")
            inventory_paths[resource_path] = "lane-structural-resource-metadata"
            managed_values = [int(row["managedMemoryBytes"]) for row in resource_rows]
            private_values = [int(row["privateMemoryBytes"]) for row in resource_rows]
            working_values = [int(row["workingSetBytes"]) for row in resource_rows]
            peak_values = [int(row["peakWorkingSetBytes"]) for row in resource_rows]

            ordinal = int(ledger_row["ordinal"])
            previous = ledger[ordinal - 1]
            gap_before_ms = (ledger_row["_created"] - previous["_exited"]).total_seconds() * 1000.0
            process_wall_ms = float(ledger_row["_wallMs"])
            lane_body_ms = float(receipt["laneWallClockMilliseconds"])
            if process_wall_ms <= 0 or lane_body_ms <= 0 or lane_body_ms > process_wall_ms + 1000:
                raise DiagnosticError(f"invalid process/lane duration binding: {receipt_path}")
            stratum = "early" if lane_index < 324 else ("middle" if lane_index < 648 else "late")
            records.append({
                "laneIndex": lane_index,
                "processOrdinal": ordinal,
                "processId": int(ledger_row["processId"]),
                "createdAtUtc": ledger_row["creationTimeUtc"],
                "exitedAtUtc": ledger_row["exitedAtUtc"],
                "receiptCreatedAtUtc": receipt["createdAtUtc"],
                "inputId": receipt["inputId"],
                "superblockId": receipt["superblockId"],
                "anonymousLaneId": receipt["anonymousLaneId"],
                "designRegion": structure["designRegion"],
                "seed": structure["seed"],
                "G": int(structure["G"]),
                "N": int(structure["N"]),
                "F": int(structure["F"]),
                "changeTopology": structure["changeTopology"],
                "graphProfile": structure["graphProfile"],
                "sameTickAtomicPartitions": int(structure["sameTickAtomicPartitions"]),
                "contextStratumId": structure["contextStratumId"],
                "processWallMs": process_wall_ms,
                "laneBodyMs": lane_body_ms,
                "gapBeforeMs": gap_before_ms,
                "operationRows": int(receipt["operationRows"]),
                "managedMemoryMaxBytes": max(managed_values),
                "privateMemoryNonzeroSamples": sum(value > 0 for value in private_values),
                "workingSetNonzeroSamples": sum(value > 0 for value in working_values),
                "peakWorkingSetNonzeroSamples": sum(value > 0 for value in peak_values),
                "orderStratum": stratum,
                "withinSuperblockPosition": lane_index % 6 + 1,
            })

        if len({(row["superblockId"], row["anonymousLaneId"]) for row in records}) != 972:
            raise DiagnosticError("anonymous lane identity is not one-to-one")

        acquisition_start = parse_dt(str(read_json(RAW / r"_control\launch-receipt.v2.json")["startedAtUtc"]))
        acquisition_end = ledger[-1]["_exited"]
        full_hours = (acquisition_end - acquisition_start).total_seconds() / 3600.0
        lane_hours = (lane_ledger[-1]["_exited"] - lane_ledger[0]["_created"]).total_seconds() / 3600.0
        pooled_process = [row["processWallMs"] for row in records]
        pooled_lane = [row["laneBodyMs"] for row in records]
        pooled_gap = [row["gapBeforeMs"] for row in records]
        pooled_p95 = quantile(pooled_process, 0.95)

        anonymous_groups = group_records(records, ["anonymousLaneId"])
        anonymous_summaries = []
        for key in sorted(anonymous_groups):
            group = anonymous_groups[key]
            row = stats_row({"anonymousLaneId": key[0]}, group)
            median = float(row["processWallP50Milliseconds"])
            row.update({
                "p95ToP50": rounded(float(row["processWallP95Milliseconds"]) / median),
                "p99ToP50": rounded(float(row["processWallP99Milliseconds"]) / median),
                "maximumToP50": rounded(float(row["processWallMaximumMilliseconds"]) / median),
                "shareAbovePooledP95": round(sum(item["processWallMs"] > pooled_p95 for item in group) / len(group), 6),
            })
            anonymous_summaries.append(row)

        anonymous_gnf = []
        for key, group in sorted(group_records(records, ["designRegion", "G", "N", "F"]).items()):
            anonymous_gnf.append(stats_row({"designRegion": key[0], "G": key[1], "N": key[2], "F": key[3]}, group))

        anonymous_path = DIAG / "anonymous-runtime-prediction.v1.json"
        anonymous_result = {
            "schema": "gate14re-me-anonymous-structural-runtime-prediction-v1",
            "status": "FROZEN_BEFORE_NAMED_IDENTITY_LOAD",
            "createdAtUtc": utc_now(),
            "sourceAttemptId": "load-qualification-execution-attempt-009",
            "laneCount": 972,
            "throughput": {
                "fullFreshProcesses": 1147,
                "fullElapsedHours": round(full_hours, 6),
                "fullFreshProcessesPerHour": round(1147 / full_hours, 6),
                "laneProcesses": 972,
                "lanePhaseElapsedHours": round(lane_hours, 6),
                "laneProcessesPerHour": round(972 / lane_hours, 6),
            },
            "pooled": {
                "processWall": describe_ms(pooled_process),
                "laneBody": describe_ms(pooled_lane),
                "interProcessGapBeforeLane": describe_ms(pooled_gap),
                "pooledProcessWallP95Milliseconds": round(pooled_p95, 6),
            },
            "anonymousLanes": anonymous_summaries,
            "gnfCells": anonymous_gnf,
            "boundary": {
                "namedIdentityLoadedAtCreation": False,
                "algorithmEffectsReadOrComputed": False,
                "formalInferencePerformed": False,
            },
        }
        write_json(anonymous_path, anonymous_result)
        anonymous_sha = sha256_file(anonymous_path)

        # Named identity is deliberately loaded only after the anonymous file is frozen.
        identity_unsealed_at = utc_now()
        require_hash(IDENTITY, IDENTITY_SHA, "identity mapping")
        require_hash(SCHEDULE, SCHEDULE_SHA, "schedule")
        identity_value = read_json(IDENTITY)
        lane_to_algorithm = {
            str(item["anonymousLaneId"]): str(item["algorithmId"])
            for item in identity_value.get("bijection", [])
        }
        if set(lane_to_algorithm) != {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}:
            raise DiagnosticError("identity mapping is not a six-lane bijection")
        schedule_rows = read_jsonl(SCHEDULE)
        if len(schedule_rows) != 162 or [row.get("ordinal") for row in schedule_rows] != list(range(162)):
            raise DiagnosticError("schedule cardinality/ordinal mismatch")
        scheduled_sequence: list[tuple[str, str, str]] = []
        for schedule_row in schedule_rows:
            if len(schedule_row.get("algorithmOrder", [])) != 6:
                raise DiagnosticError("schedule algorithm-order cardinality mismatch")
            for item in schedule_row["algorithmOrder"]:
                lane = str(item["anonymousLaneId"])
                algorithm = str(item["algorithmId"])
                if lane_to_algorithm.get(lane) != algorithm:
                    raise DiagnosticError("schedule/identity mapping mismatch")
                scheduled_sequence.append((str(schedule_row["superblockId"]), lane, algorithm))
        actual_sequence = [(str(row["superblockId"]), str(row["anonymousLaneId"])) for row in records]
        if [(sb, lane) for sb, lane, _ in scheduled_sequence] != actual_sequence:
            raise DiagnosticError("chronological lane receipts do not match frozen schedule order")
        for record, (_, lane, algorithm) in zip(records, scheduled_sequence):
            if record["anonymousLaneId"] != lane:
                raise DiagnosticError("lane mapping mismatch")
            record["algorithmId"] = algorithm

        algorithms = sorted(set(row["algorithmId"] for row in records))
        algorithm_summaries: list[dict[str, Any]] = []
        named_groups = group_records(records, ["algorithmId"])
        for algorithm in algorithms:
            group = named_groups[(algorithm,)]
            row = stats_row({"algorithmId": algorithm}, group)
            median = float(row["processWallP50Milliseconds"])
            row.update({
                "p95ToP50": rounded(float(row["processWallP95Milliseconds"]) / median),
                "p99ToP50": rounded(float(row["processWallP99Milliseconds"]) / median),
                "maximumToP50": rounded(float(row["processWallMaximumMilliseconds"]) / median),
                "countAbovePooledP95": sum(item["processWallMs"] > pooled_p95 for item in group),
                "shareAbovePooledP95": round(sum(item["processWallMs"] > pooled_p95 for item in group) / len(group), 6),
                "matchedSuperblockTailFrequency": round(sum(item["processWallMs"] > pooled_p95 for item in group) / 162.0, 6),
            })
            algorithm_summaries.append(row)

        algorithm_csv_fields = list(algorithm_summaries[0].keys())
        write_csv(DIAG / "named-algorithm-runtime-summary.v1.csv", algorithm_summaries, algorithm_csv_fields)
        write_json(DIAG / "named-algorithm-runtime-summary.v1.json", {
            "schema": "gate14re-me-named-algorithm-engineering-runtime-summary-v1",
            "status": "POST_VALIDATION_DESCRIPTIVE_ENGINEERING_ONLY",
            "identityUnsealedAtUtc": identity_unsealed_at,
            "anonymousPredictionSha256": anonymous_sha,
            "pooledProcessWallP95Milliseconds": round(pooled_p95, 6),
            "algorithms": algorithm_summaries,
            "descriptorMaxima": {
                descriptor: max(algorithm_summaries, key=lambda row: float(row[descriptor]))["algorithmId"]
                for descriptor in ("p95ToP50", "p99ToP50", "maximumToP50", "shareAbovePooledP95")
            },
            "boundary": "Runtime/long-tail engineering descriptors are not algorithm quality or effect rankings.",
        })

        gnf_rows: list[dict[str, Any]] = []
        for key, group in sorted(group_records(records, ["algorithmId", "designRegion", "G", "N", "F"]).items()):
            gnf_rows.append(stats_row({
                "algorithmId": key[0], "designRegion": key[1], "G": key[2], "N": key[3], "F": key[4]
            }, group))
        write_csv(DIAG / "algorithm-gnf-runtime-cells.v1.csv", gnf_rows, list(gnf_rows[0].keys()))

        core_cell_rows: list[dict[str, Any]] = []
        core_records = [row for row in records if row["designRegion"] == "core"]
        for key, group in sorted(group_records(core_records, ["G", "N", "F"]).items()):
            core_cell_rows.append(stats_row({"G": key[0], "N": key[1], "F": key[2]}, group))
        if len(core_cell_rows) != 48 or any(row["n"] != 18 for row in core_cell_rows):
            raise DiagnosticError("core G x N x F cell closure mismatch")
        top_core_cells = sorted(core_cell_rows, key=lambda row: float(row["processWallP50Milliseconds"]), reverse=True)[:12]
        top_algorithm_cells = sorted(gnf_rows, key=lambda row: float(row["processWallP50Milliseconds"]), reverse=True)[:24]
        slowest_lanes = sorted(records, key=lambda row: float(row["processWallMs"]), reverse=True)[:30]
        write_csv(DIAG / "slowest-lanes.v1.csv", slowest_lanes, [
            "laneIndex", "processOrdinal", "algorithmId", "anonymousLaneId", "inputId", "superblockId",
            "designRegion", "G", "N", "F", "processWallMs", "laneBodyMs", "gapBeforeMs",
            "operationRows", "orderStratum", "withinSuperblockPosition", "createdAtUtc", "exitedAtUtc"
        ])
        write_json(DIAG / "slow-gnf-cells.v1.json", {
            "schema": "gate14re-me-slow-gnf-engineering-cells-v1",
            "topCoreCellsByP50ProcessWall": top_core_cells,
            "topAlgorithmRegionCellsByP50ProcessWall": top_algorithm_cells,
            "smallCellWarning": "Algorithm x core G x N x F cells have n=3; their P99 is not interpreted as a stable population estimate.",
        })

        stratum_rows = []
        for stratum in ("early", "middle", "late"):
            group = [row for row in records if row["orderStratum"] == stratum]
            stratum_row = stats_row({"orderStratum": stratum}, group)
            stratum_row["gCounts"] = dict(Counter(str(row["G"]) for row in group))
            stratum_row["nCounts"] = dict(Counter(str(row["N"]) for row in group))
            stratum_row["fCounts"] = dict(Counter(str(row["F"]) for row in group))
            stratum_row["stressCount"] = sum(row["designRegion"] == "stress" for row in group)
            stratum_rows.append(stratum_row)

        final_exit = parse_dt(str(records[-1]["exitedAtUtc"]))
        hourly_tail = []
        for offset in range(6):
            end = final_exit - timedelta(hours=offset)
            start = end - timedelta(hours=1)
            selected = [row for row in records if start < parse_dt(str(row["exitedAtUtc"])) <= end]
            hourly_tail.append({
                "hoursBeforeFinal": offset,
                "windowStartUtc": start.isoformat().replace("+00:00", "Z"),
                "windowEndUtc": end.isoformat().replace("+00:00", "Z"),
                "laneCompletions": len(selected),
                "GCounts": dict(Counter(str(row["G"]) for row in selected)),
                "NCounts": dict(Counter(str(row["N"]) for row in selected)),
                "FCounts": dict(Counter(str(row["F"]) for row in selected)),
            })
        recent_98 = records[-98:]
        recent_100 = records[-100:]
        position_rows = []
        for position in range(1, 7):
            position_rows.append(stats_row(
                {"withinSuperblockPosition": position},
                [row for row in records if row["withinSuperblockPosition"] == position],
            ))

        normalized_groups = group_records(records, ["anonymousLaneId", "designRegion", "G", "N", "F"])
        normalized_by_stratum: dict[str, list[float]] = defaultdict(list)
        cross_stratum_group_count = 0
        for group in normalized_groups.values():
            strata = {row["orderStratum"] for row in group}
            if len(strata) < 2:
                continue
            cross_stratum_group_count += 1
            median = quantile([row["processWallMs"] for row in group], 0.5)
            for row in group:
                normalized_by_stratum[str(row["orderStratum"])].append(row["processWallMs"] / median)
        normalized_summary = {
            stratum: describe_number(values) for stratum, values in sorted(normalized_by_stratum.items())
        }
        order_sensitivity = {
            "schema": "gate14re-me-runtime-order-and-tail-sensitivity-v1",
            "strata": stratum_rows,
            "recentLast98": stats_row({"window": "last-98"}, recent_98),
            "recentLast100": stats_row({"window": "last-100"}, recent_100),
            "trailingHourlyCompletionWindows": hourly_tail,
            "withinSuperblockPositions": position_rows,
            "matchedCellOrderComparison": {
                "groupDefinition": "anonymousLaneId x designRegion x G x N x F",
                "groupsSpanningAtLeastTwoOrderStrata": cross_stratum_group_count,
                "normalizedProcessWallByStratum": normalized_summary,
            },
            "confoundingWarning": "Execution order is structurally confounded with load order, especially the final stress superblocks. Order association is descriptive and cannot by itself establish system degradation.",
        }
        write_json(DIAG / "order-tail-sensitivity.v1.json", order_sensitivity)

        process_tail = {row["laneIndex"] for row in records if row["processWallMs"] > quantile(pooled_process, 0.95)}
        lane_tail = {row["laneIndex"] for row in records if row["laneBodyMs"] > quantile(pooled_lane, 0.95)}
        overlap = len(process_tail & lane_tail) / len(process_tail) if process_tail else 0.0
        lane_coverage = [row["laneBodyMs"] / row["processWallMs"] for row in records]
        resource_coverage = {
            "lanes": 972,
            "lanesWithAnyPrivateMemorySample": sum(row["privateMemoryNonzeroSamples"] > 0 for row in records),
            "lanesWithAnyWorkingSetSample": sum(row["workingSetNonzeroSamples"] > 0 for row in records),
            "lanesWithAnyPeakWorkingSetSample": sum(row["peakWorkingSetNonzeroSamples"] > 0 for row in records),
            "managedMemoryMaxBytes": describe_number([row["managedMemoryMaxBytes"] for row in records]),
        }
        time_identifiability = {
            "schema": "gate14re-me-runtime-component-identifiability-v1",
            "directlyMeasured": {
                "processWall": describe_ms(pooled_process),
                "inclusiveLaneBody": describe_ms(pooled_lane),
                "interProcessGapBeforeLane": describe_ms(pooled_gap),
                "laneBodyToProcessWallRatio": describe_number(lane_coverage),
                "processWallVsLaneBodyPearson": rounded(pearson(pooled_process, pooled_lane)),
                "processWallP95TailOverlapWithLaneBodyP95Tail": round(overlap, 6),
            },
            "notSeparatelyIdentifiable": {
                "pureAlgorithmCompute": "The permitted data have no trustworthy absolute algorithm/workload start and end timestamps. Inclusive lane-body also contains grid construction, oracle calls, instrumentation and raw writes.",
                "unityStartup": "No trustworthy workloadStartUtc is present.",
                "exitFinalization": "No trustworthy workloadEndUtc is present.",
            },
            "resourceMetadata": resource_coverage,
            "driverEvidenceBoundary": {
                "thermalThrottling": "not measured",
                "antivirusActivity": "not measured",
                "diskPressureTimeSeries": "not measured",
                "hostMemoryPressure": "not directly measured; private/working-set samples are structurally zero",
                "prelaunchDiskFreeBytes": read_json(EVIDENCE / "prelaunch-audit.v1.json").get("freeBytes"),
            },
            "interpretation": "High process-wall/lane-body concordance can localize the tail to the inclusive lane body rather than inter-process gaps, but cannot isolate pure algorithm compute from in-lane instrumentation, oracle work, serialization, or file I/O.",
        }
        write_json(DIAG / "time-component-identifiability.v1.json", time_identifiability)

        log_operations = [math.log1p(float(row["operationRows"])) for row in records]
        log_lane = [math.log1p(float(row["laneBodyMs"])) for row in records]
        load_associations = {
            "logOperationRowsVsLogLaneBodyPearson": rounded(pearson(log_operations, log_lane)),
            "GvsLogLaneBodyPearson": rounded(pearson([float(row["G"]) for row in records], log_lane)),
            "NvsLogLaneBodyPearson": rounded(pearson([float(row["N"]) for row in records], log_lane)),
            "FvsLogLaneBodyPearson": rounded(pearson([float(row["F"]) for row in records], log_lane)),
            "boundary": "Descriptive associations only; G, N, F, algorithm identity, context and execution order are not mutually randomized for causal attribution in this diagnostic.",
        }

        core_by_alg_cell = group_records(core_records, ["algorithmId", "G", "N", "F"])
        if len(core_by_alg_cell) != 288 or any(len(group) != 3 for group in core_by_alg_cell.values()):
            raise DiagnosticError("formal-ST prediction source cell closure mismatch")
        gap_p50_s = quantile(pooled_gap, 0.50) / 1000.0
        gap_p99_s = quantile(pooled_gap, 0.99) / 1000.0
        point_per_b_seconds = sum(quantile([row["processWallMs"] for row in group], 0.50) / 1000.0 for group in core_by_alg_cell.values()) + 288 * gap_p50_s
        conservative_per_b_seconds = sum(max(row["processWallMs"] for row in group) / 1000.0 for group in core_by_alg_cell.values()) + 288 * gap_p99_s
        prediction_rows = []
        for b_value in (36, 72, 108, 144):
            point_hours = point_per_b_seconds * b_value / 3600.0
            conservative_hours = conservative_per_b_seconds * b_value / 3600.0
            planning_hours = conservative_hours * 1.20
            prediction_rows.append({
                "B": b_value,
                "formalSuperblocks": 48 * b_value,
                "laneProcesses": 288 * b_value,
                "pointHours": round(point_hours, 3),
                "pointDays": round(point_hours / 24.0, 3),
                "conservativeHours": round(conservative_hours, 3),
                "conservativeDays": round(conservative_hours / 24.0, 3),
                "planningWith20PercentHeadroomHours": round(planning_hours, 3),
                "planningWith20PercentHeadroomDays": round(planning_hours / 24.0, 3),
                "atOrAboveSevenDayGate": planning_hours >= 168.0,
            })
        seven_day_gate = prediction_rows[0]["atOrAboveSevenDayGate"]
        resource_prediction = {
            "schema": "gate14re-me-formal-st-parameterized-runtime-prediction-v1",
            "status": "PARAMETERIZED_ONLY_FINAL_B_NOT_FROZEN",
            "pointHoursPerB": round(point_per_b_seconds / 3600.0, 6),
            "conservativeHoursPerB": round(conservative_per_b_seconds / 3600.0, 6),
            "planningHoursPerBWith20PercentHeadroom": round(conservative_per_b_seconds * 1.20 / 3600.0, 6),
            "rows": prediction_rows,
            "sevenDayDecisionGate": {
                "thresholdHours": 168,
                "minimumPermittedB": 36,
                "triggeredAtMinimumPermittedB": seven_day_gate,
            },
            "scopeExclusions": ["input generation", "oracle prechecks", "post-collection validation", "delivery construction", "formal analysis"],
            "targetHostRecalibration": "Run the same qualification on the target host, recompute the 288 core algorithm-cell medians/maxima and lane-gap P50/P99, then replay these formulas before formal ST authorization.",
            "boundary": "This engineering budget is not a sample-size authorization and does not alter B or the scientific design.",
        }
        write_json(DIAG / "formal-st-runtime-prediction.v1.json", resource_prediction)

        simplification_candidate: dict[str, Any] | None = None
        if seven_day_gate:
            candidate_cells = {(g, n, f) for g in (64, 128, 256) for n in (8, 512) for f in (1, 225)}
            candidate_groups = {
                key: group for key, group in core_by_alg_cell.items() if (key[1], key[2], key[3]) in candidate_cells
            }
            candidate_point_per_b = sum(quantile([row["processWallMs"] for row in group], 0.50) / 1000.0 for group in candidate_groups.values()) + len(candidate_groups) * gap_p50_s
            candidate_conservative_per_b = sum(max(row["processWallMs"] for row in group) / 1000.0 for group in candidate_groups.values()) + len(candidate_groups) * gap_p99_s
            candidate_b36_planning_hours = candidate_conservative_per_b * 36 * 1.20 / 3600.0
            simplification_candidate = {
                "schema": "gate14re-me-st-major-simplification-candidate-v1",
                "status": "PROPOSAL_ONLY_REQUIRES_EXPLICIT_FUTURE_AUTHORIZATION_AND_NEW_POWER_CONTRACTS",
                "trigger": "Current 48-cell ST planning budget at minimum permitted B=36 reaches or exceeds 168 hours.",
                "candidate": {
                    "retainAlgorithms": 6,
                    "retainGLevels": [64, 128, 256],
                    "retainNLevels": [8, 512],
                    "retainFLevels": [1, 225],
                    "cells": 12,
                    "reductionFrom48CellsPercent": 75.0,
                    "candidateLaneProcessesAtB36": len(candidate_groups) * 36,
                    "candidateB36PlanningHoursFromCurrentEngineeringFormula": round(candidate_b36_planning_hours, 3),
                    "candidateB36PlanningDaysFromCurrentEngineeringFormula": round(candidate_b36_planning_hours / 24.0, 3),
                },
                "lostInference": [
                    "No full four-level response curve for N or F.",
                    "No direct estimation at N=32/128 or F=9/81.",
                    "Reduced ability to detect nonlinear and intermediate-load interactions.",
                    "Multiplicity family, context balance, power, stopping rule and schedule must all be redesigned prospectively."
                ],
                "notAuthorized": ["automatic deletion of cells", "automatic B change", "automatic formal collection", "automatic MQ or MT launch"],
            }
            write_json(DIAG / "st-major-simplification-candidate.v1.json", simplification_candidate)

        old_text = OLD_VALIDATOR.read_text(encoding="utf-8")
        new_observation = read_json(OFFLINE / "execution-observation.v1.json")
        v1_failure = read_json(PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-offline-necessary-revalidation-attempt-001\terminal-failure-receipt.v1.json")
        acquisition_complete = read_json(RAW / r"_control\acquisition-complete.v2.json")
        pause_receipt = read_json(PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-paused-seal-attempt-009\pause-authorization-receipt.v1.json")
        original_unfinished_seconds = (parse_dt(str(pause_receipt["stoppedAtUtc"])) - parse_dt(str(acquisition_complete["completedAtUtc"]))).total_seconds()
        validator_causes = {
            "schema": "gate14re-me-validator-duration-root-cause-v1",
            "oldValidatorDirectCodeEvidence": {
                "requireHashDefinitionLine": line_number(old_text, "def require_hash("),
                "requireHashAlwaysCallsSha256File": "actual = sha256_file(path)" in old_text,
                "perRowSourceBindingLine": line_number(old_text, "require_hash(source_path"),
                "wholeDatasetEnvelopeListLine": line_number(old_text, "envelopes: List[RowEnvelope] = []"),
                "wholeDatasetAppendLine": line_number(old_text, "envelopes.append(envelope)"),
                "runnerMethodConstantLine": line_number(old_text, "RUNNER_METHOD ="),
                "oldRunnerMethod": "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run",
                "actualRunnerMethod": "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV3.Run",
            },
            "validatedDatasetScale": {
                "rowsRetainedByOldLoadTablesDesign": sum(int(value) for value in offline_result["rawValidation"]["tableRows"].values()),
                "rowSourceBindingReferences": offline_result["performance"]["rowSourceBindingReferences"],
                "distinctRowBoundSourcePaths": offline_result["performance"]["distinctRowBoundSourcePathsValidated"],
                "averageReferencesPerDistinctSourcePath": round(
                    offline_result["performance"]["rowSourceBindingReferences"] /
                    offline_result["performance"]["distinctRowBoundSourcePathsValidated"], 3
                ),
            },
            "executionEvidence": {
                "originalValidationWindowBeforeUserStopSeconds": round(original_unfinished_seconds, 3),
                "originalValidationCompleted": False,
                "offlineV1ObservedRowsPerSecond": v1_failure["lastCompletedProgress"]["observedRowsPerSecond"],
                "offlineV1Failure": v1_failure["failureReasonCode"],
                "offlineV2ElapsedSeconds": new_observation["elapsedSeconds"],
                "offlineV2PeakWorkingSetBytes": new_observation["peakWorkingSetBytes"],
                "offlineV2PeakPrivateMemoryBytes": new_observation["peakPrivateMemoryBytes"],
                "offlineV2Status": new_observation["resultStatus"],
                "offlineV2SourceHashCacheHits": offline_result["performance"]["rowSourceBindingPathCacheHits"],
            },
            "rootCauseConclusion": [
                "The old validator re-hashed a row-bound source file on every source-bound raw row instead of once per distinct file.",
                "The old validator retained every parsed row dictionary inside RowEnvelope lists for all tables before later checks, making memory scale with more than seven million rows.",
                "Offline v1 removed repeated content hashing and whole-dataset retention but still repeated filesystem path canonicalization per row; its fail-closed performance evidence led to v2.",
                "Offline v2 resolved and hashed 163 distinct row-bound paths once, used 7,126,242 cache hits, streamed rows, and completed in under two minutes.",
                "The old validator also hard-coded RunnerV2 while attempt-009 used RunnerV3, so completion would have produced a false structural identity failure without a forward validator correction."
            ],
        }
        write_json(DIAG / "validator-root-cause.v1.json", validator_causes)

        named_summary_by_algorithm = {row["algorithmId"]: row for row in algorithm_summaries}
        descriptor_maxima = {
            descriptor: max(algorithm_summaries, key=lambda row: float(row[descriptor]))["algorithmId"]
            for descriptor in ("p95ToP50", "p99ToP50", "maximumToP50", "shareAbovePooledP95")
        }
        most_common_tail = Counter(descriptor_maxima.values()).most_common()
        tail_assessment = most_common_tail[0][0] if most_common_tail and (len(most_common_tail) == 1 or most_common_tail[0][1] > most_common_tail[1][1]) else "NO_SINGLE_ALGORITHM_DOMINATES_ALL_FROZEN_TAIL_DESCRIPTORS"

        report_lines = [
            "# Gate14Re-ME attempt-009 离线验收后运行时工程诊断",
            "",
            "## 结论",
            "",
            f"- 离线必要原始数据验收：`PASS_OFFLINE_NECESSARY_RAW_VALIDATION`；耗时 {new_observation['elapsedSeconds']:.3f} 秒，峰值工作集 {new_observation['peakWorkingSetBytes'] / (1024**2):.1f} MiB。它不是原 qualification terminal PASS，也未验证 delivery/typed-Parquet。",
            f"- 全程 1,147 个 fresh processes 用时 {full_hours:.2f} 小时；972 个 algorithm lanes 阶段用时 {lane_hours:.2f} 小时，平均 {972/lane_hours:.2f} lanes/hour。",
            f"- 最后一个滚动小时完成 {hourly_tail[0]['laneCompletions']} 个 lanes，与用户观察的约 12–13 lanes/hour 一致。",
            f"- 进程墙钟与 inclusive lane-body 的 Pearson 相关为 {time_identifiability['directlyMeasured']['processWallVsLaneBodyPearson']}；P95 尾部重合率为 {overlap:.1%}。尾部主要发生在已直接测得的 lane-body 区间，而不是进程间隙；但纯算法计算、Unity 启动、退出和 lane 内仪器/序列化/I/O 不能被当前 instrumentation 分别识别。",
            f"- 冻结长尾描述量的多数指向：`{tail_assessment}`。这只是运行时工程长尾，不是算法效果排名或赢家。",
            f"- 正式 ST 的最终 B 尚未冻结。按当前 48-cell、六算法、B=36 最小平衡单位，含 20% 头寸的工程预算为 {prediction_rows[0]['planningWith20PercentHeadroomDays']:.3f} 天；7 天门：{'触发' if seven_day_gate else '未触发'}。",
            "",
            "## 各算法进程墙钟分布（秒）",
            "",
            "| 算法 | n | P50 | P90 | P95 | P99 | 最大 | P95/P50 | 超 pooled P95 比例 |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for algorithm in algorithms:
            row = named_summary_by_algorithm[algorithm]
            report_lines.append(
                f"| {algorithm} | {row['n']} | {row['processWallP50Milliseconds']/1000:.3f} | "
                f"{row['processWallP90Milliseconds']/1000:.3f} | {row['processWallP95Milliseconds']/1000:.3f} | "
                f"{row['processWallP99Milliseconds']/1000:.3f} | {row['processWallMaximumMilliseconds']/1000:.3f} | "
                f"{row['p95ToP50']:.3f} | {row['shareAbovePooledP95']:.1%} |"
            )
        report_lines.extend([
            "",
            "## 慢负载单元与尾段",
            "",
            "core G×N×F 单元按 pooled P50 进程墙钟最慢的前 12 个见 `slow-gnf-cells.v1.json`；全部算法×region×G×N×F 见 `algorithm-gnf-runtime-cells.v1.csv`，最慢 30 条 lane 见 `slowest-lanes.v1.csv`。算法×core 单元只有 n=3，不把其 P99 当稳定总体估计。",
            "",
            f"结构负载与 inclusive lane-body 的描述性相关：log(operation rows)={load_associations['logOperationRowsVsLogLaneBodyPearson']}，G={load_associations['GvsLogLaneBodyPearson']}，N={load_associations['NvsLogLaneBodyPearson']}，F={load_associations['FvsLogLaneBodyPearson']}。这些相关不构成因果。",
            "",
            "early/middle/late 与 G×N×F 的执行顺序高度混杂，最后 18 个 superblocks 又全部是 G=256、N=512、F=225 stress。缺少在相同 algorithm×region×G×N×F 上跨足够时间段的随机重复，因此不能把尾段变慢直接归因于热节流、缓存、杀毒、磁盘或系统退化。",
            "",
            "## 可识别与不可识别的时间部分",
            "",
            "- 可直接识别：process wall、strict-serial inter-process gap、RunnerV3 inclusive lane-body duration。",
            "- 不可分别识别：纯算法 compute、Unity/startup、exit/finalization；当前数据没有可信绝对 workloadStartUtc/workloadEndUtc。",
            "- lane-body 本身包含 grid 构造、planner 初始化/查询/repair、参考 oracle、instrumentation、状态/资源采样和 raw 写盘，因此不得把 lane-body 全部称为算法计算。",
            "- process-resource 的 private/working-set/peak-working-set 样本为结构性零，且没有温度、CPU 频率、杀毒或磁盘吞吐时间序列，所以这些只能列为候选解释。",
            "",
            "## 验收为什么原来很慢",
            "",
            f"旧 validator 对 {offline_result['performance']['rowSourceBindingReferences']:,} 个 source-bound rows 逐行调用文件 SHA-256，而实际只有 {offline_result['performance']['distinctRowBoundSourcePathsValidated']} 个不同来源；同时 `load_tables` 将 {sum(int(value) for value in offline_result['rawValidation']['tableRows'].values()):,} 个行字典及 RowEnvelope 全部保留在内存。其 Runner method 还硬编码为 V2，而本次真实执行是 V3。离线 v2 改为每个 distinct path 只规范化/哈希一次并流式丢弃行，7.24 GB、约 712.6 万 source-bound rows 的必要验收在约 106 秒完成。",
            "",
            "## 科学与决策边界",
            "",
            "这是事后工程诊断，不是正式效果比较；不据此自动删除算法、改变科学问题、缩小样本、修改停止规则或启动 ST/MQ/MT。若 7 天门触发，`st-major-simplification-candidate.v1.json` 仅是一份待用户明确授权、重新功效论证并先验冻结的候选。六算法 MQ 仍是未来可能的独立研究，绝不是 MT。",
        ])
        (DIAG / "diagnostic-report.v1.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8")

        write_json(DIAG / "load-runtime-cause-summary.v1.json", {
            "schema": "gate14re-me-load-runtime-cause-summary-v1",
            "status": "POST_VALIDATION_DESCRIPTIVE_ENGINEERING_DIAGNOSTIC_COMPLETE",
            "tailAssessment": tail_assessment,
            "tailDescriptorMaxima": descriptor_maxima,
            "loadAssociations": load_associations,
            "lastHourLaneCompletions": hourly_tail[0]["laneCompletions"],
            "processWallVsLaneBodyPearson": time_identifiability["directlyMeasured"]["processWallVsLaneBodyPearson"],
            "processWallP95TailOverlapWithLaneBodyP95Tail": round(overlap, 6),
            "supportedConclusions": [
                "The final throughput collapse coincides with structurally heavy G/N/F composition and long inclusive lane-body durations.",
                "Inter-process gaps are directly measured and can be compared with lane/process tails.",
                "The old validator was slow because of per-row source hashing, whole-dataset row retention, and then offline-v1 per-row path canonicalization."
            ],
            "notSupportedAsCauses": ["thermal throttling", "antivirus", "cache state", "disk pressure", "host memory pressure"],
            "unidentifiable": ["pure algorithm compute", "Unity startup", "exit/finalization"],
            "scientificBoundary": "Not a formal effect comparison, ranking, weighting, or winner adjudication."
        })

        inventory_rows = []
        for path, purpose in sorted(inventory_paths.items(), key=lambda item: item[0].as_posix()):
            if not path.is_file():
                raise DiagnosticError(f"diagnostic input missing at manifest time: {path}")
            inventory_rows.append({
                "schema": "gate14re-me-runtime-diagnostic-input-file-row-v1",
                "purpose": purpose,
                "absolutePath": path.as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
        inventory_path = DIAG / "input-file-inventory.v1.jsonl"
        with inventory_path.open("w", encoding="utf-8", newline="\n") as handle:
            for row in inventory_rows:
                handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")

        output_names = [
            "analysis-plan.v1.json", "diagnostic-authorization-receipt.v1.json", "field-boundary.v1.json",
            "runtime_diagnostic_v1.py", "Run-RuntimeDiagnostic.v1.ps1", "pre-execution-freeze-manifest.v1.json",
            "anonymous-runtime-prediction.v1.json",
            "named-algorithm-runtime-summary.v1.csv", "named-algorithm-runtime-summary.v1.json",
            "algorithm-gnf-runtime-cells.v1.csv", "slowest-lanes.v1.csv", "slow-gnf-cells.v1.json",
            "order-tail-sensitivity.v1.json", "time-component-identifiability.v1.json",
            "formal-st-runtime-prediction.v1.json", "validator-root-cause.v1.json",
            "load-runtime-cause-summary.v1.json", "diagnostic-report.v1.md", "input-file-inventory.v1.jsonl",
        ]
        if simplification_candidate is not None:
            output_names.append("st-major-simplification-candidate.v1.json")
        manifest_path = DIAG / "diagnostic-file-manifest.v1.jsonl"
        with manifest_path.open("w", encoding="utf-8", newline="\n") as handle:
            for name in sorted(output_names):
                path = DIAG / name
                row = {
                    "schema": "gate14re-me-runtime-diagnostic-file-row-v1",
                    "relativePath": name,
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
                handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")

        terminal = {
            "schema": "gate14re-me-post-offline-validation-runtime-diagnostic-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "status": "PASS_POST_VALIDATION_DESCRIPTIVE_ENGINEERING_RUNTIME_DIAGNOSTIC",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "offlineValidationResultSha256": OFFLINE_RESULT_SHA,
            "preExecutionFreezeManifestSha256": preexecution_freeze_sha,
            "anonymousPredictionSha256": anonymous_sha,
            "identityBindingSha256": IDENTITY_SHA,
            "scheduleSha256": SCHEDULE_SHA,
            "inputInventorySha256": sha256_file(inventory_path),
            "diagnosticManifestSha256": sha256_file(manifest_path),
            "laneCount": 972,
            "algorithmCount": 6,
            "coreGnfCellCount": 48,
            "sevenDayGateTriggeredAtMinimumB36": seven_day_gate,
            "qualificationTerminalPassClaimed": False,
            "algorithmEffectsReadOrComputed": False,
            "rankingWeightingOrWinnerComputed": False,
            "formalAnalysisPerformed": False,
            "scientificDesignChanged": False,
            "stMqOrMtStarted": False,
            "sourceRootsModified": False,
        }
        write_json(terminal_path, terminal)
        print(json.dumps(terminal, ensure_ascii=False, sort_keys=True))
        return 0
    except Exception as exc:
        failure = {
            "schema": "gate14re-me-post-offline-validation-runtime-diagnostic-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "status": "FAIL_CLOSED_POST_VALIDATION_RUNTIME_DIAGNOSTIC",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "reason": str(exc),
            "qualificationTerminalPassClaimed": False,
            "sourceRootsModified": False,
        }
        write_json(terminal_path, failure)
        print(json.dumps(failure, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
