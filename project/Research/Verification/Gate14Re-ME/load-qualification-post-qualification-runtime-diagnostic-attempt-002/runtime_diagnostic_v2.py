#!/usr/bin/env python3
"""Gate14Re-ME post-qualification descriptive runtime engineering diagnostic.

The program reads only structural timing/resource metadata and frozen design
bindings.  Named identity is deliberately loaded only after an anonymous
prediction has been written, hashed, and made read-only.  Algorithm outcomes,
scientific effects, rankings, weights, and winner adjudication are out of scope.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import stat
import statistics
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


PROJECT = Path(r"H:\DDM_Final_Project").resolve()
RAW = PROJECT / r"Research\PilotRuns\Gate14Re-ME\load-qualification\attempt-009"
EVIDENCE = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-execution-attempt-011"
ACCEPT_EVIDENCE = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-read-only-acceptance-attempt-001"
DELIVERY = PROJECT / r"Research\Exports\Gate14Re-ME\load-qualification\attempt-009"
DIAG = PROJECT / r"Research\Verification\Gate14Re-ME\load-qualification-post-qualification-runtime-diagnostic-attempt-002"
PLANNING = PROJECT / r"Research\Verification\Gate14Re-ME\qualification-planning-asset-generation-v4-attempt-002\planning-assets"

QUALIFICATION_PASS = ACCEPT_EVIDENCE / "qualification-terminal-pass-receipt.v1.json"
QUALIFICATION_PASS_SHA = "9ffc2c83896f1516eea969619ccc8c07f6be1bdab85cecead7224fc8f9cbeafa"
ACQUISITION_TERMINAL = RAW / r"_control\acquisition-terminal-receipt.v4_1.json"
ACQUISITION_TERMINAL_SHA = "2adade4fdbf952bb7883bc956246268a65e31715df95c23280647316980b7ae0"
ACCEPTANCE_TERMINAL = DELIVERY / "terminal-final.v4_2.json"
ACCEPTANCE_TERMINAL_SHA = "f9262cede92f9f9e86b239ea8d8ac202c25f49864625e149c4c8ca3c473656e2"
IDENTITY = PLANNING / r"identity\anonymous-identity-binding.sealed.v4.json"
IDENTITY_SHA = "77b88a23a559642d455edf0d4caad9a1f9c06b7ddf33703b8fd100f4a1878bd2"
SCHEDULE = PLANNING / r"schedule\bounded-qualification-williams-schedule.v4.jsonl"
SCHEDULE_SHA = "8786f687a142900c0cf609817bbc1da957ec3ee9e09d12549e886fb892f026cb"
RUNNER = PROJECT / r"Assets\_Scripts\Research\Editor\Gate14ReMELoadQualificationRunnerV4_2.cs"
RUNNER_SHA = "622d97031efe51a1ea89fc2da95e5b473c170b817d452e76d3b25d81b228140d"
FORMAL_SAMPLE_DECISION = PROJECT / r"Research\Gate14Re-ME\Execution\v4\formal-sample-size-decision.v4_1.json"
FORMAL_SAMPLE_DECISION_SHA = "952d64c34c9e7821386c36a60519a5003658e89b78dbb81f4c2233b702636980"
ANALYSIS_PLAN = DIAG / "analysis-plan.v2.json"
PREEXECUTION_FREEZE = DIAG / "pre-execution-freeze-manifest.v2.json"

EXPECTED_PROCESSES = 775
LANE_START_ORDINAL = 19
EXPECTED_LANES = 756
EXPECTED_SUPERBLOCKS = 126
EXPECTED_CORE_SUPERBLOCKS = 108
EXPECTED_CORE_GNF_CELLS = 36
EXPECTED_ALGORITHMS = 6


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
    try:
        with path.open("r", encoding="utf-8-sig") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise DiagnosticError(f"JSON object required: {path}:{line_number}")
                rows.append(value)
    except DiagnosticError:
        raise
    except Exception as exc:
        raise DiagnosticError(f"invalid JSONL: {path}: {exc}") from exc
    return rows


def write_json(path: Path, value: Mapping[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def write_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
    os.replace(temporary, path)


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]], fields: Sequence[str]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def make_read_only(path: Path) -> None:
    path.chmod(stat.S_IREAD)


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


def group_records(records: Sequence[Mapping[str, Any]], keys: Sequence[str]) -> dict[tuple[Any, ...], list[Mapping[str, Any]]]:
    groups: dict[tuple[Any, ...], list[Mapping[str, Any]]] = defaultdict(list)
    for record in records:
        groups[tuple(record[key] for key in keys)].append(record)
    return groups


def runtime_stats(label_fields: Mapping[str, Any], records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    process = describe_ms([float(row["processWallMs"]) for row in records])
    lane = describe_ms([float(row["laneBodyMs"]) for row in records])
    value: dict[str, Any] = {**label_fields, "n": len(records)}
    for prefix, source in (("processWall", process), ("inclusiveLaneBody", lane)):
        for key in ("minimumMilliseconds", "p50Milliseconds", "p90Milliseconds", "p95Milliseconds", "p99Milliseconds", "maximumMilliseconds"):
            value[prefix + key[0].upper() + key[1:]] = source.get(key)
    return value


def small_cell_stats(label_fields: Mapping[str, Any], records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    process = [float(row["processWallMs"]) for row in records]
    lane = [float(row["laneBodyMs"]) for row in records]
    return {
        **label_fields,
        "n": len(records),
        "processWallMinimumMilliseconds": round(min(process), 6),
        "processWallP50Milliseconds": round(quantile(process, 0.50), 6),
        "processWallMaximumMilliseconds": round(max(process), 6),
        "processWallRangeMilliseconds": round(max(process) - min(process), 6),
        "inclusiveLaneBodyMinimumMilliseconds": round(min(lane), 6),
        "inclusiveLaneBodyP50Milliseconds": round(quantile(lane, 0.50), 6),
        "inclusiveLaneBodyMaximumMilliseconds": round(max(lane), 6),
        "inclusiveLaneBodyRangeMilliseconds": round(max(lane) - min(lane), 6),
    }


def verify_preexecution_freeze() -> str:
    freeze = read_json(PREEXECUTION_FREEZE)
    if freeze.get("status") != "FROZEN_FOR_ONE_SHOT_EXECUTION":
        raise DiagnosticError("pre-execution freeze status mismatch")
    files = freeze.get("files")
    if not isinstance(files, list) or not files:
        raise DiagnosticError("pre-execution freeze file list missing")
    for row in files:
        path = Path(str(row.get("absolutePath", "")))
        if not path.is_file():
            raise DiagnosticError(f"frozen file missing: {path}")
        if path.stat().st_size != int(row.get("bytes", -1)):
            raise DiagnosticError(f"frozen byte-count mismatch: {path}")
        require_hash(path, str(row.get("sha256", "")), f"frozen file {path.name}")
    return sha256_file(PREEXECUTION_FREEZE)


def validate_activation() -> None:
    require_hash(QUALIFICATION_PASS, QUALIFICATION_PASS_SHA, "qualification terminal PASS receipt")
    receipt = read_json(QUALIFICATION_PASS)
    if receipt.get("status") != "PASS_QUALIFICATION_TERMINAL":
        raise DiagnosticError("qualification activation status mismatch")
    if receipt.get("algorithmIdentityStatus") != "SEALED_PENDING_PREFROZEN_POST_QUALIFICATION_DIAGNOSTIC_PLAN":
        raise DiagnosticError("qualification identity-seal state mismatch")
    require_hash(ACQUISITION_TERMINAL, ACQUISITION_TERMINAL_SHA, "acquisition terminal receipt")
    acquisition = read_json(ACQUISITION_TERMINAL)
    if acquisition.get("status") != "PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING":
        raise DiagnosticError("raw acquisition terminal state mismatch")
    require_hash(ACCEPTANCE_TERMINAL, ACCEPTANCE_TERMINAL_SHA, "acceptance terminal final")
    acceptance = read_json(ACCEPTANCE_TERMINAL)
    if (
        acceptance.get("status") != "PASS_INDEPENDENT_STREAMING_ESSENTIAL_ACCEPTANCE_FROZEN"
        or acceptance.get("typedParquetBuildPass") is not True
        or acceptance.get("typedParquetRoundTripPass") is not True
        or acceptance.get("sourceRootsModified") is not False
    ):
        raise DiagnosticError("independent acceptance terminal state mismatch")
    require_hash(RUNNER, RUNNER_SHA, "frozen RunnerV4_2 source")
    require_hash(FORMAL_SAMPLE_DECISION, FORMAL_SAMPLE_DECISION_SHA, "formal sample-size decision")


def load_structural_records(inventory: dict[Path, str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    ledger_path = RAW / r"_control\process-ledger.raw.v2.jsonl"
    launch_path = RAW / r"_control\launch-receipt.v2.json"
    failure_path = RAW / r"_control\failures-and-voids.raw.v1.jsonl"
    replacement_path = RAW / r"_control\replacement-ledger.raw.v1.jsonl"
    for path, purpose in (
        (ledger_path, "process-ledger"),
        (launch_path, "acquisition-launch-receipt"),
        (failure_path, "failure-ledger"),
        (replacement_path, "replacement-ledger"),
    ):
        inventory[path] = purpose
    if read_jsonl(failure_path) or read_jsonl(replacement_path):
        raise DiagnosticError("failure or replacement ledger is nonempty")
    ledger = read_jsonl(ledger_path)
    if len(ledger) != EXPECTED_PROCESSES or [row.get("ordinal") for row in ledger] != list(range(EXPECTED_PROCESSES)):
        raise DiagnosticError("process-ledger cardinality or ordinal mismatch")
    mode_counts = Counter(str(row.get("mode")) for row in ledger)
    if mode_counts != Counter({"instrument-self-test": 1, "oracle-batch": 6, "empty-boundary": 12, "lane": 756}):
        raise DiagnosticError(f"process-ledger mode counts mismatch: {dict(mode_counts)}")
    for row in ledger:
        if (
            row.get("schema") != "gate14re-me-process-ledger-row-v2"
            or row.get("state") != "EXITED_ZERO_TRUSTED_IDENTITY"
            or row.get("exitCode") != 0
        ):
            raise DiagnosticError("process-ledger trusted natural-exit state mismatch")
        row["_created"] = parse_dt(str(row["creationTimeUtc"]))
        row["_exited"] = parse_dt(str(row["exitedAtUtc"]))
        row["_wallMs"] = (row["_exited"] - row["_created"]).total_seconds() * 1000.0
        if row["_wallMs"] <= 0 or not math.isfinite(row["_wallMs"]):
            raise DiagnosticError("nonpositive or nonfinite process wall")

    lane_ledger = ledger[LANE_START_ORDINAL:]
    if len(lane_ledger) != EXPECTED_LANES or any(row.get("mode") != "lane" for row in lane_ledger):
        raise DiagnosticError("lane ledger phase mismatch")

    receipt_paths = sorted(RAW.rglob("lane-receipt.v2.json"))
    if len(receipt_paths) != EXPECTED_LANES:
        raise DiagnosticError("lane receipt cardinality mismatch")
    receipt_items: list[tuple[datetime, Path, dict[str, Any]]] = []
    for path in receipt_paths:
        receipt = read_json(path)
        if receipt.get("status") != "COMPLETE_RAW_LANE" or receipt.get("completed") is not True:
            raise DiagnosticError(f"incomplete lane receipt: {path}")
        receipt_items.append((parse_dt(str(receipt["createdAtUtc"])), path, receipt))
        inventory[path] = "lane-receipt-structural-timing"
    receipt_items.sort(key=lambda item: item[0])

    input_cache: dict[str, dict[str, Any]] = {}
    records: list[dict[str, Any]] = []
    for lane_index, ((receipt_time, receipt_path, receipt), ledger_row) in enumerate(zip(receipt_items, lane_ledger)):
        if not (ledger_row["_created"] <= receipt_time <= ledger_row["_exited"] + timedelta(seconds=1)):
            raise DiagnosticError(f"lane receipt/process chronological binding mismatch: {receipt_path}")
        input_relative = str(receipt["inputRelativePath"])
        if input_relative not in input_cache:
            input_path = (PROJECT / input_relative).resolve()
            require_hash(input_path, str(receipt["inputSha256"]), "frozen lane input")
            input_value = read_json(input_path)
            input_cache[input_relative] = {
                "path": input_path,
                "inputId": input_value["inputId"],
                "superblockId": input_value["superblockId"],
                "designRegion": input_value["designRegion"],
                "seed": input_value["seed"],
                "G": int(input_value["gridEdge"]),
                "N": int(input_value["agentCount"]),
                "F": int(input_value["changedCellCount"]),
                "changeTopology": input_value.get("changeTopology"),
                "graphProfile": input_value.get("graphProfile"),
                "contextStratumId": input_value.get("contextStratumId"),
            }
            inventory[input_path] = "frozen-input-structural-fields"
        structure = input_cache[input_relative]
        if (
            receipt.get("inputId") != structure["inputId"]
            or receipt.get("superblockId") != structure["superblockId"]
            or receipt_path.parent.name != receipt.get("anonymousLaneId")
            or receipt_path.parent.parent.name != receipt.get("superblockId")
        ):
            raise DiagnosticError(f"lane receipt/input/path identity mismatch: {receipt_path}")

        resource_path = receipt_path.parent / "process-resources.raw.v1.jsonl"
        resource_rows = read_jsonl(resource_path)
        if len(resource_rows) != 26:
            raise DiagnosticError(f"process-resource cardinality mismatch: {resource_path}")
        inventory[resource_path] = "lane-process-resource-structural-metadata"
        managed = [float(row.get("managedMemoryBytes", 0)) for row in resource_rows]
        private = [float(row.get("privateMemoryBytes", 0)) for row in resource_rows]
        working = [float(row.get("workingSetBytes", 0)) for row in resource_rows]
        peak = [float(row.get("peakWorkingSetBytes", 0)) for row in resource_rows]

        ordinal = int(ledger_row["ordinal"])
        previous = ledger[ordinal - 1]
        gap_before_ms = (ledger_row["_created"] - previous["_exited"]).total_seconds() * 1000.0
        process_wall_ms = float(ledger_row["_wallMs"])
        lane_body_ms = float(receipt["laneWallClockMilliseconds"])
        if (
            not math.isfinite(gap_before_ms)
            or gap_before_ms < 0
            or not math.isfinite(lane_body_ms)
            or lane_body_ms <= 0
            or lane_body_ms > process_wall_ms + 1000
        ):
            raise DiagnosticError(f"invalid process/lane/gap duration binding: {receipt_path}")
        order_stratum = "early" if lane_index < 252 else ("middle" if lane_index < 504 else "late")
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
            "G": structure["G"],
            "N": structure["N"],
            "F": structure["F"],
            "changeTopology": structure["changeTopology"],
            "graphProfile": structure["graphProfile"],
            "contextStratumId": structure["contextStratumId"],
            "processWallMs": process_wall_ms,
            "laneBodyMs": lane_body_ms,
            "gapBeforeMs": gap_before_ms,
            "managedMemoryMaxBytes": max(managed),
            "privateMemoryMaxBytes": max(private),
            "workingSetMaxBytes": max(working),
            "peakWorkingSetMaxBytes": max(peak),
            "orderStratum": order_stratum,
            "withinSuperblockPosition": lane_index % 6 + 1,
        })

    if len({(row["superblockId"], row["anonymousLaneId"]) for row in records}) != EXPECTED_LANES:
        raise DiagnosticError("anonymous lane identity is not one-to-one")
    if len({row["superblockId"] for row in records}) != EXPECTED_SUPERBLOCKS:
        raise DiagnosticError("superblock cardinality mismatch")
    launch = read_json(launch_path)
    return ledger, records, launch


def build_anonymous_prediction(
    ledger: list[dict[str, Any]],
    records: list[dict[str, Any]],
    launch: dict[str, Any],
) -> tuple[dict[str, Any], str, float, dict[str, Any]]:
    pooled_process = [float(row["processWallMs"]) for row in records]
    pooled_lane = [float(row["laneBodyMs"]) for row in records]
    pooled_gap = [float(row["gapBeforeMs"]) for row in records]
    pooled_p95 = quantile(pooled_process, 0.95)

    acquisition_start = parse_dt(str(launch["startedAtUtc"]))
    acquisition_end = ledger[-1]["_exited"]
    full_hours = (acquisition_end - acquisition_start).total_seconds() / 3600.0
    lane_hours = (ledger[-1]["_exited"] - ledger[LANE_START_ORDINAL]["_created"]).total_seconds() / 3600.0
    if full_hours <= 0 or lane_hours <= 0:
        raise DiagnosticError("invalid full or lane phase elapsed time")

    anonymous_summaries: list[dict[str, Any]] = []
    for key, group in sorted(group_records(records, ["anonymousLaneId"]).items()):
        row = runtime_stats({"anonymousLaneId": key[0]}, group)
        median = float(row["processWallP50Milliseconds"])
        row.update({
            "p95ToP50": rounded(float(row["processWallP95Milliseconds"]) / median),
            "p99ToP50": rounded(float(row["processWallP99Milliseconds"]) / median),
            "maximumToP50": rounded(float(row["processWallMaximumMilliseconds"]) / median),
            "countAbovePooledP95": sum(float(item["processWallMs"]) > pooled_p95 for item in group),
            "shareAbovePooledP95": round(sum(float(item["processWallMs"]) > pooled_p95 for item in group) / len(group), 6),
        })
        anonymous_summaries.append(row)
    if len(anonymous_summaries) != EXPECTED_ALGORITHMS or any(row["n"] != EXPECTED_SUPERBLOCKS for row in anonymous_summaries):
        raise DiagnosticError("anonymous-lane distribution closure mismatch")

    pooled_gnf: list[dict[str, Any]] = []
    for key, group in sorted(group_records(records, ["designRegion", "G", "N", "F"]).items()):
        pooled_gnf.append(runtime_stats({"designRegion": key[0], "G": key[1], "N": key[2], "F": key[3]}, group))
    core_gnf = [row for row in pooled_gnf if row["designRegion"] == "core"]
    if len(core_gnf) != EXPECTED_CORE_GNF_CELLS or any(row["n"] != 18 for row in core_gnf):
        raise DiagnosticError("anonymous core GNF closure mismatch")

    order_strata: list[dict[str, Any]] = []
    for stratum in ("early", "middle", "late"):
        group = [row for row in records if row["orderStratum"] == stratum]
        item = runtime_stats({"orderStratum": stratum}, group)
        item.update({
            "GCounts": dict(sorted(Counter(str(row["G"]) for row in group).items())),
            "NCounts": dict(sorted(Counter(str(row["N"]) for row in group).items())),
            "FCounts": dict(sorted(Counter(str(row["F"]) for row in group).items())),
            "coreCount": sum(row["designRegion"] == "core" for row in group),
            "stressCount": sum(row["designRegion"] == "stress" for row in group),
        })
        order_strata.append(item)

    final_exit = parse_dt(str(records[-1]["exitedAtUtc"]))
    trailing_hour = [row for row in records if final_exit - timedelta(hours=1) < parse_dt(str(row["exitedAtUtc"])) <= final_exit]
    recent_76 = records[-76:]
    recent_100 = records[-100:]

    core_records = [row for row in records if row["designRegion"] == "core"]
    if len(core_records) != EXPECTED_CORE_SUPERBLOCKS * EXPECTED_ALGORITHMS:
        raise DiagnosticError("core lane cardinality mismatch")
    core_by_anon_cell = group_records(core_records, ["anonymousLaneId", "G", "N", "F"])
    if len(core_by_anon_cell) != 216 or any(len(group) != 3 for group in core_by_anon_cell.values()):
        raise DiagnosticError("anonymous formal-ST prediction source-cell closure mismatch")
    gap_p50_s = quantile(pooled_gap, 0.50) / 1000.0
    gap_p99_s = quantile(pooled_gap, 0.99) / 1000.0
    point_seconds_per_b = sum(
        quantile([float(row["processWallMs"]) for row in group], 0.50) / 1000.0
        for group in core_by_anon_cell.values()
    ) + 216 * gap_p50_s
    conservative_seconds_per_b = sum(
        max(float(row["processWallMs"]) for row in group) / 1000.0
        for group in core_by_anon_cell.values()
    ) + 216 * gap_p99_s
    formal_rows: list[dict[str, Any]] = []
    for b_value in (36, 72, 108, 144):
        point_hours = point_seconds_per_b * b_value / 3600.0
        conservative_hours = conservative_seconds_per_b * b_value / 3600.0
        planning_hours = conservative_hours * 1.20
        formal_rows.append({
            "B": b_value,
            "formalSuperblocks": EXPECTED_CORE_GNF_CELLS * b_value,
            "laneProcesses": 216 * b_value,
            "pointHours": round(point_hours, 3),
            "pointDays": round(point_hours / 24.0, 3),
            "conservativeHours": round(conservative_hours, 3),
            "conservativeDays": round(conservative_hours / 24.0, 3),
            "planningWith20PercentHeadroomHours": round(planning_hours, 3),
            "planningWith20PercentHeadroomDays": round(planning_hours / 24.0, 3),
            "atOrAboveSevenDayGate": planning_hours >= 168.0,
        })

    lane_coverage = [float(row["laneBodyMs"]) / float(row["processWallMs"]) for row in records]
    process_tail = {int(row["laneIndex"]) for row in records if float(row["processWallMs"]) > pooled_p95}
    lane_p95 = quantile(pooled_lane, 0.95)
    lane_tail = {int(row["laneIndex"]) for row in records if float(row["laneBodyMs"]) > lane_p95}
    tail_overlap = len(process_tail & lane_tail) / len(process_tail) if process_tail else 0.0

    log_lane = [math.log1p(float(row["laneBodyMs"])) for row in records]
    load_associations = {
        "GvsLogInclusiveLaneBodyPearson": rounded(pearson([float(row["G"]) for row in records], log_lane)),
        "NvsLogInclusiveLaneBodyPearson": rounded(pearson([float(row["N"]) for row in records], log_lane)),
        "FvsLogInclusiveLaneBodyPearson": rounded(pearson([float(row["F"]) for row in records], log_lane)),
        "boundary": "Descriptive associations only; G, N, F, anonymous lane identity, context and order are not mutually randomized for causal attribution.",
    }

    sample_decision = read_json(FORMAL_SAMPLE_DECISION)
    anonymous = {
        "schema": "gate14re-me-anonymous-structural-runtime-prediction-v2",
        "studyId": "Gate14Re-ME",
        "status": "FROZEN_BEFORE_NAMED_IDENTITY_LOAD",
        "createdAtUtc": utc_now(),
        "sourceQualificationExecutionAttemptId": "load-qualification-execution-attempt-011",
        "sourceMeasuredAttempt": "attempt-009",
        "throughput": {
            "fullFreshProcesses": EXPECTED_PROCESSES,
            "fullElapsedHours": round(full_hours, 6),
            "fullFreshProcessesPerHour": round(EXPECTED_PROCESSES / full_hours, 6),
            "laneProcesses": EXPECTED_LANES,
            "lanePhaseElapsedHours": round(lane_hours, 6),
            "laneProcessesPerHour": round(EXPECTED_LANES / lane_hours, 6),
            "lastOneHourLaneCompletions": len(trailing_hour),
        },
        "pooled": {
            "processWall": describe_ms(pooled_process),
            "inclusiveLaneBody": describe_ms(pooled_lane),
            "interProcessGapBeforeLane": describe_ms(pooled_gap),
            "pooledProcessWallP95Milliseconds": round(pooled_p95, 6),
        },
        "anonymousLaneDistributions": anonymous_summaries,
        "pooledGnfCells": pooled_gnf,
        "recentTailSensitivity": {
            "orderStrata": order_strata,
            "last76Lanes": runtime_stats({"window": "last-76"}, recent_76),
            "last100Lanes": runtime_stats({"window": "last-100"}, recent_100),
            "trailingOneHour": runtime_stats({"window": "trailing-one-hour"}, trailing_hour) if trailing_hour else {"window": "trailing-one-hour", "n": 0},
            "trailingOneHourGCounts": dict(sorted(Counter(str(row["G"]) for row in trailing_hour).items())),
            "trailingOneHourNCounts": dict(sorted(Counter(str(row["N"]) for row in trailing_hour).items())),
            "trailingOneHourFCounts": dict(sorted(Counter(str(row["F"]) for row in trailing_hour).items())),
        },
        "timeComponentEvidence": {
            "processWallVsInclusiveLaneBodyPearson": rounded(pearson(pooled_process, pooled_lane)),
            "processWallP95TailOverlapWithInclusiveLaneBodyP95Tail": round(tail_overlap, 6),
            "inclusiveLaneBodyToProcessWallRatio": describe_number(lane_coverage),
            "pureAlgorithmCompute": "NOT_IDENTIFIABLE_NOT_DIRECTLY_MEASURED",
            "unityStartup": "NOT_IDENTIFIABLE_NO_TRUSTWORTHY_ABSOLUTE_WORKLOAD_START",
            "exitFinalization": "NOT_IDENTIFIABLE_NO_TRUSTWORTHY_ABSOLUTE_WORKLOAD_END",
        },
        "resourceMetadata": {
            "managedMemoryMaxBytes": describe_number([float(row["managedMemoryMaxBytes"]) for row in records]),
            "privateMemoryMaxBytes": describe_number([float(row["privateMemoryMaxBytes"]) for row in records]),
            "workingSetMaxBytes": describe_number([float(row["workingSetMaxBytes"]) for row in records]),
            "peakWorkingSetMaxBytes": describe_number([float(row["peakWorkingSetMaxBytes"]) for row in records]),
        },
        "loadAssociations": load_associations,
        "formalStParameterizedRuntime": {
            "status": "PARAMETERIZED_ONLY_FINAL_B_NOT_FROZEN_BY_THIS_DIAGNOSTIC",
            "formalSampleDecisionStatusAtDiagnosticFreeze": sample_decision.get("status"),
            "pointHoursPerB": round(point_seconds_per_b / 3600.0, 6),
            "conservativeHoursPerB": round(conservative_seconds_per_b / 3600.0, 6),
            "planningHoursPerBWith20PercentHeadroom": round(conservative_seconds_per_b * 1.20 / 3600.0, 6),
            "rows": formal_rows,
            "sevenDayDecisionGateHours": 168,
            "targetHostRecalibration": "Run the same frozen qualification on the target host, rebuild the 216 anonymous-lane x core-GNF P50/max cells and pooled lane-gap P50/P99, then replay these formulas before target-host formal authorization.",
            "scopeExclusions": ["input generation", "qualification oracle batches", "post-collection acceptance", "delivery construction", "formal analysis"],
        },
        "boundary": {
            "namedIdentityLoadedAtCreation": False,
            "algorithmObservationsReadOrComputed": False,
            "scientificEffectsReadOrComputed": False,
            "rankingWeightingOrWinnerComputed": False,
            "formalInferencePerformed": False,
        },
    }
    anonymous_path = DIAG / "anonymous-runtime-prediction.v2.json"
    write_json(anonymous_path, anonymous)
    anonymous_sha = sha256_file(anonymous_path)
    make_read_only(anonymous_path)
    freeze_receipt = {
        "schema": "gate14re-me-anonymous-runtime-prediction-freeze-receipt-v2",
        "status": "FROZEN_READ_ONLY_BEFORE_NAMED_IDENTITY_LOAD",
        "createdAtUtc": utc_now(),
        "relativePath": anonymous_path.name,
        "bytes": anonymous_path.stat().st_size,
        "sha256": anonymous_sha,
        "namedIdentityLoadedBeforeFreeze": False,
        "algorithmObservationsReadOrComputed": False,
    }
    freeze_path = DIAG / "anonymous-prediction-freeze-receipt.v2.json"
    write_json(freeze_path, freeze_receipt)
    make_read_only(freeze_path)
    return anonymous, anonymous_sha, pooled_p95, {
        "formalRows": formal_rows,
        "fullHours": full_hours,
        "laneHours": lane_hours,
        "trailingHourCount": len(trailing_hour),
        "tailOverlap": tail_overlap,
        "loadAssociations": load_associations,
    }


def load_named_schedule_after_anonymous_freeze(
    records: list[dict[str, Any]],
    anonymous_sha: str,
    inventory: dict[Path, str],
) -> tuple[list[str], str]:
    anonymous_path = DIAG / "anonymous-runtime-prediction.v2.json"
    if sha256_file(anonymous_path) != anonymous_sha or not bool(os.stat(anonymous_path).st_file_attributes & stat.FILE_ATTRIBUTE_READONLY):
        raise DiagnosticError("anonymous result is not hash-stable and read-only before named identity load")
    require_hash(IDENTITY, IDENTITY_SHA, "sealed identity mapping")
    require_hash(SCHEDULE, SCHEDULE_SHA, "frozen schedule")
    inventory[IDENTITY] = "named-identity-mapping-loaded-only-after-anonymous-freeze"
    inventory[SCHEDULE] = "named-schedule-loaded-only-after-anonymous-freeze"

    identity_unsealed_at = utc_now()
    identity = read_json(IDENTITY)
    lane_to_algorithm = {
        str(item["anonymousLaneId"]): str(item["algorithmId"])
        for item in identity.get("bijection", [])
    }
    if len(lane_to_algorithm) != EXPECTED_ALGORITHMS or len(set(lane_to_algorithm.values())) != EXPECTED_ALGORITHMS:
        raise DiagnosticError("sealed identity mapping is not a six-algorithm bijection")
    schedule_rows = read_jsonl(SCHEDULE)
    if len(schedule_rows) != EXPECTED_SUPERBLOCKS or [row.get("ordinal") for row in schedule_rows] != list(range(EXPECTED_SUPERBLOCKS)):
        raise DiagnosticError("schedule cardinality or ordinal mismatch")
    expected_sequence: list[tuple[str, str, str]] = []
    for row in schedule_rows:
        order = row.get("algorithmOrder")
        if not isinstance(order, list) or len(order) != EXPECTED_ALGORITHMS:
            raise DiagnosticError("schedule algorithm-order cardinality mismatch")
        for item in order:
            lane = str(item["anonymousLaneId"])
            algorithm = str(item["algorithmId"])
            if lane_to_algorithm.get(lane) != algorithm:
                raise DiagnosticError("schedule and sealed identity mapping mismatch")
            expected_sequence.append((str(row["superblockId"]), lane, algorithm))
    actual_sequence = [(str(row["superblockId"]), str(row["anonymousLaneId"])) for row in records]
    if [(sb, lane) for sb, lane, _ in expected_sequence] != actual_sequence:
        raise DiagnosticError("chronological lane records do not match the frozen schedule")
    for record, (_, lane, algorithm) in zip(records, expected_sequence):
        if record["anonymousLaneId"] != lane:
            raise DiagnosticError("lane mapping mismatch")
        record["algorithmId"] = algorithm
    return sorted(set(lane_to_algorithm.values())), identity_unsealed_at


def build_named_diagnostic(
    records: list[dict[str, Any]],
    algorithms: list[str],
    identity_unsealed_at: str,
    anonymous: dict[str, Any],
    anonymous_sha: str,
    pooled_p95: float,
    anonymous_context: dict[str, Any],
) -> tuple[dict[str, Any], bool]:
    named_groups = group_records(records, ["algorithmId"])
    superblock_groups = group_records(records, ["superblockId"])
    matched_max_count: Counter[str] = Counter()
    for group in superblock_groups.values():
        block_max = max(float(row["processWallMs"]) for row in group)
        for row in group:
            if abs(float(row["processWallMs"]) - block_max) <= 1e-9:
                matched_max_count[str(row["algorithmId"])] += 1

    algorithm_summaries: list[dict[str, Any]] = []
    for algorithm in algorithms:
        group = named_groups.get((algorithm,), [])
        if len(group) != EXPECTED_SUPERBLOCKS:
            raise DiagnosticError(f"named algorithm lane count mismatch: {algorithm}")
        row = runtime_stats({"algorithmId": algorithm}, group)
        median = float(row["processWallP50Milliseconds"])
        above_tail = sum(float(item["processWallMs"]) > pooled_p95 for item in group)
        row.update({
            "p95ToP50": rounded(float(row["processWallP95Milliseconds"]) / median),
            "p99ToP50": rounded(float(row["processWallP99Milliseconds"]) / median),
            "maximumToP50": rounded(float(row["processWallMaximumMilliseconds"]) / median),
            "countAbovePooledP95": above_tail,
            "shareAbovePooledP95": round(above_tail / len(group), 6),
            "matchedSuperblockTailFrequency": round(above_tail / EXPECTED_SUPERBLOCKS, 6),
            "matchedSuperblockMaximumCount": matched_max_count[algorithm],
            "matchedSuperblockMaximumFrequency": round(matched_max_count[algorithm] / EXPECTED_SUPERBLOCKS, 6),
        })
        algorithm_summaries.append(row)

    descriptor_names = (
        "p95ToP50",
        "p99ToP50",
        "maximumToP50",
        "shareAbovePooledP95",
        "matchedSuperblockMaximumFrequency",
    )
    descriptor_leaders = {
        name: max(algorithm_summaries, key=lambda row: float(row[name]))["algorithmId"]
        for name in descriptor_names
    }
    votes = Counter(descriptor_leaders.values()).most_common()
    if votes and (len(votes) == 1 or votes[0][1] > votes[1][1]):
        tail_assessment = str(votes[0][0])
        tail_reason = f"strict plurality across the five predeclared long-tail descriptors ({votes[0][1]}/5)"
    else:
        tail_assessment = "NO_SINGLE_DOMINANT_LONG_TAIL_ALGORITHM"
        tail_reason = "no strict plurality across the five predeclared long-tail descriptors"

    named_summary = {
        "schema": "gate14re-me-named-algorithm-engineering-runtime-summary-v2",
        "studyId": "Gate14Re-ME",
        "status": "POST_QUALIFICATION_DESCRIPTIVE_ENGINEERING_ONLY",
        "identityUnsealedAtUtc": identity_unsealed_at,
        "anonymousPredictionSha256": anonymous_sha,
        "identityBindingSha256": IDENTITY_SHA,
        "scheduleSha256": SCHEDULE_SHA,
        "pooledProcessWallP95Milliseconds": round(pooled_p95, 6),
        "algorithms": algorithm_summaries,
        "longTailAssessment": {
            "mostProminentAlgorithmOrNoSingleDominant": tail_assessment,
            "reason": tail_reason,
            "descriptorLeaders": descriptor_leaders,
            "descriptorLeaderVotes": dict(sorted(Counter(descriptor_leaders.values()).items())),
        },
        "boundary": "Runtime and long-tail engineering descriptors are not algorithm-quality, effect, rank, weight, or winner results.",
    }
    write_json(DIAG / "named-algorithm-runtime-summary.v2.json", named_summary)
    write_csv(DIAG / "named-algorithm-runtime-summary.v2.csv", algorithm_summaries, list(algorithm_summaries[0].keys()))

    gnf_rows: list[dict[str, Any]] = []
    for key, group in sorted(group_records(records, ["algorithmId", "designRegion", "G", "N", "F"]).items()):
        gnf_rows.append(small_cell_stats({
            "algorithmId": key[0], "designRegion": key[1], "G": key[2], "N": key[3], "F": key[4]
        }, group))
    core_gnf_rows = [row for row in gnf_rows if row["designRegion"] == "core"]
    if len(core_gnf_rows) != 216 or any(row["n"] != 3 for row in core_gnf_rows):
        raise DiagnosticError("named algorithm x core-GNF closure mismatch")
    write_csv(DIAG / "algorithm-gnf-runtime-cells.v2.csv", gnf_rows, list(gnf_rows[0].keys()))

    pooled_cell_rows: list[dict[str, Any]] = []
    for key, group in sorted(group_records(records, ["designRegion", "G", "N", "F"]).items()):
        pooled_cell_rows.append(runtime_stats({"designRegion": key[0], "G": key[1], "N": key[2], "F": key[3]}, group))
    slow_cells = {
        "schema": "gate14re-me-slow-gnf-engineering-cells-v2",
        "topPooledGnfCellsByP50ProcessWall": sorted(
            pooled_cell_rows, key=lambda row: float(row["processWallP50Milliseconds"]), reverse=True
        )[:12],
        "topNamedAlgorithmGnfCellsByP50ProcessWall": sorted(
            gnf_rows, key=lambda row: float(row["processWallP50Milliseconds"]), reverse=True
        )[:24],
        "smallCellWarning": "Named algorithm x core G x N x F cells have n=3; only n/minimum/P50/maximum/range are reported, and no cell P99 is interpreted as stable.",
        "scheduleConfoundingWarning": "Execution order and load composition are not orthogonal; cell and matched-superblock descriptions must be considered before attributing slowness to algorithm identity.",
    }
    write_json(DIAG / "slow-gnf-cells.v2.json", slow_cells)

    slowest_lanes = sorted(records, key=lambda row: float(row["processWallMs"]), reverse=True)[:30]
    write_csv(DIAG / "slowest-lanes.v2.csv", slowest_lanes, [
        "laneIndex", "processOrdinal", "algorithmId", "anonymousLaneId", "inputId", "superblockId",
        "designRegion", "seed", "G", "N", "F", "changeTopology", "processWallMs", "laneBodyMs",
        "gapBeforeMs", "orderStratum", "withinSuperblockPosition", "createdAtUtc", "exitedAtUtc",
    ])

    stratum_rows: list[dict[str, Any]] = []
    for stratum in ("early", "middle", "late"):
        group = [row for row in records if row["orderStratum"] == stratum]
        item = runtime_stats({"orderStratum": stratum}, group)
        item.update({
            "GCounts": dict(sorted(Counter(str(row["G"]) for row in group).items())),
            "NCounts": dict(sorted(Counter(str(row["N"]) for row in group).items())),
            "FCounts": dict(sorted(Counter(str(row["F"]) for row in group).items())),
            "stressCount": sum(row["designRegion"] == "stress" for row in group),
        })
        stratum_rows.append(item)
    named_strata = [
        runtime_stats({"algorithmId": key[0], "orderStratum": key[1]}, group)
        for key, group in sorted(group_records(records, ["algorithmId", "orderStratum"]).items())
    ]

    normalized_groups = group_records(records, ["algorithmId", "designRegion", "G", "N", "F"])
    normalized_by_stratum: dict[str, list[float]] = defaultdict(list)
    cross_stratum_groups = 0
    for group in normalized_groups.values():
        if len({str(row["orderStratum"]) for row in group}) < 2:
            continue
        cross_stratum_groups += 1
        median = quantile([float(row["processWallMs"]) for row in group], 0.50)
        for row in group:
            normalized_by_stratum[str(row["orderStratum"])].append(float(row["processWallMs"]) / median)
    normalized_summary = {
        key: describe_number(values) for key, values in sorted(normalized_by_stratum.items())
    }
    position_rows = [
        runtime_stats({"withinSuperblockPosition": position}, [row for row in records if row["withinSuperblockPosition"] == position])
        for position in range(1, 7)
    ]
    final_exit = parse_dt(str(records[-1]["exitedAtUtc"]))
    hourly_windows: list[dict[str, Any]] = []
    for offset in range(6):
        end = final_exit - timedelta(hours=offset)
        start = end - timedelta(hours=1)
        selected = [row for row in records if start < parse_dt(str(row["exitedAtUtc"])) <= end]
        hourly_windows.append({
            "hoursBeforeFinal": offset,
            "windowStartUtc": start.isoformat().replace("+00:00", "Z"),
            "windowEndUtc": end.isoformat().replace("+00:00", "Z"),
            "laneCompletions": len(selected),
            "GCounts": dict(sorted(Counter(str(row["G"]) for row in selected).items())),
            "NCounts": dict(sorted(Counter(str(row["N"]) for row in selected).items())),
            "FCounts": dict(sorted(Counter(str(row["F"]) for row in selected).items())),
        })
    order_sensitivity = {
        "schema": "gate14re-me-runtime-order-and-tail-sensitivity-v2",
        "pooledOrderStrata": stratum_rows,
        "namedAlgorithmOrderStrata": named_strata,
        "recentLast76": runtime_stats({"window": "last-76"}, records[-76:]),
        "recentLast100": runtime_stats({"window": "last-100"}, records[-100:]),
        "trailingHourlyCompletionWindows": hourly_windows,
        "withinSuperblockPositions": position_rows,
        "matchedAlgorithmGnfOrderComparison": {
            "groupDefinition": "algorithmId x designRegion x G x N x F",
            "groupsSpanningAtLeastTwoOrderStrata": cross_stratum_groups,
            "normalizedProcessWallByStratum": normalized_summary,
        },
        "confoundingWarning": "Execution order is structurally confounded with load composition. Time drift is descriptive and cannot by itself establish thermal throttling, cache, antivirus, disk, or memory-pressure causality.",
    }
    write_json(DIAG / "order-tail-sensitivity.v2.json", order_sensitivity)

    pooled_process = [float(row["processWallMs"]) for row in records]
    pooled_lane = [float(row["laneBodyMs"]) for row in records]
    pooled_gap = [float(row["gapBeforeMs"]) for row in records]
    process_tail = {int(row["laneIndex"]) for row in records if float(row["processWallMs"]) > quantile(pooled_process, 0.95)}
    lane_tail = {int(row["laneIndex"]) for row in records if float(row["laneBodyMs"]) > quantile(pooled_lane, 0.95)}
    overlap = len(process_tail & lane_tail) / len(process_tail) if process_tail else 0.0
    time_identifiability = {
        "schema": "gate14re-me-runtime-component-identifiability-v2",
        "runnerSourceSha256": RUNNER_SHA,
        "directlyMeasured": {
            "processWall": describe_ms(pooled_process),
            "inclusiveLaneBody": describe_ms(pooled_lane),
            "interProcessGapBeforeLane": describe_ms(pooled_gap),
            "inclusiveLaneBodyToProcessWallRatio": describe_number([
                float(row["laneBodyMs"]) / float(row["processWallMs"]) for row in records
            ]),
            "processWallVsInclusiveLaneBodyPearson": rounded(pearson(pooled_process, pooled_lane)),
            "processWallP95TailOverlapWithInclusiveLaneBodyP95Tail": round(overlap, 6),
        },
        "inclusiveLaneBodySemanticBoundary": "RunnerV4_2 starts the stopwatch at RunAlgorithmLane entry, before runner-hash verification, grid construction and planner creation, and stops it after initialization, queries, event groups, instrumentation/resource sampling and raw writes. It is an inclusive lane-body measure, not pure algorithm compute.",
        "notSeparatelyIdentifiable": {
            "pureAlgorithmCompute": "No trustworthy absolute algorithm/workload start and end timestamps exist; inclusive lane body also contains setup, oracle/cache use, instrumentation, serialization and raw I/O.",
            "unityStartup": "No trustworthy explicit workloadStartUtc exists.",
            "exitFinalization": "No trustworthy explicit workloadEndUtc exists.",
        },
        "resourceMetadata": anonymous["resourceMetadata"],
        "driverEvidenceBoundary": {
            "thermalThrottling": "not directly measured; candidate explanation only",
            "cacheState": "not directly measured; candidate explanation only",
            "antivirusActivity": "not directly measured; candidate explanation only",
            "diskPressureTimeSeries": "not directly measured; candidate explanation only",
            "hostMemoryPressure": "only bounded process structural samples are available; causal attribution is unsupported",
        },
        "interpretation": "Process-wall/lane-body concordance can localize a tail to the inclusive lane body rather than the inter-process gap, but it cannot isolate pure algorithm compute from the other in-lane components.",
    }
    write_json(DIAG / "time-component-identifiability.v2.json", time_identifiability)

    formal_prediction = {
        "schema": "gate14re-me-formal-st-parameterized-runtime-prediction-v2",
        **anonymous["formalStParameterizedRuntime"],
        "anonymousPredictionSha256": anonymous_sha,
        "boundary": "This engineering budget does not select B, change the scientific design, or authorize formal collection.",
    }
    write_json(DIAG / "formal-st-runtime-prediction.v2.json", formal_prediction)
    seven_day_gate = bool(formal_prediction["rows"][0]["atOrAboveSevenDayGate"])

    cause_summary = {
        "schema": "gate14re-me-load-runtime-cause-summary-v2",
        "status": "POST_QUALIFICATION_DESCRIPTIVE_ENGINEERING_DIAGNOSTIC_COMPLETE",
        "longTailAssessment": named_summary["longTailAssessment"],
        "loadAssociations": anonymous_context["loadAssociations"],
        "lastHourLaneCompletions": anonymous_context["trailingHourCount"],
        "processWallVsInclusiveLaneBodyPearson": time_identifiability["directlyMeasured"]["processWallVsInclusiveLaneBodyPearson"],
        "processWallP95TailOverlapWithInclusiveLaneBodyP95Tail": round(overlap, 6),
        "supportedConclusions": [
            "Observed process-wall tails can be compared directly with inclusive lane-body and strict-serial gap tails.",
            "G, N, F and order composition describe where slow lanes occur, subject to frozen-schedule confounding.",
            "The optimized independent streaming acceptance completed the full typed-Parquet value/type/order round trip without modifying source roots."
        ],
        "notSupportedAsCauses": ["thermal throttling", "cache state", "antivirus", "disk pressure", "host memory pressure"],
        "unidentifiable": ["pure algorithm compute", "Unity startup", "exit/finalization"],
        "scientificBoundary": "Not a formal effect comparison, ranking, weighting, or winner adjudication.",
    }
    write_json(DIAG / "load-runtime-cause-summary.v2.json", cause_summary)

    acceptance = read_json(ACCEPTANCE_TERMINAL)
    report_lines = [
        "# Gate14Re-ME attempt-011 qualification 后运行时工程诊断",
        "",
        "## 证据状态",
        "",
        f"- qualification：`PASS_QUALIFICATION_TERMINAL`；独立流式验收覆盖 {int(acceptance['rows']):,} 行并通过 typed-Parquet 全量值、类型和顺序往返，耗时 {float(acceptance['elapsedSeconds']):.3f} 秒。",
        f"- 全程 {EXPECTED_PROCESSES} 个 fresh processes 用时 {anonymous_context['fullHours']:.3f} 小时；{EXPECTED_LANES} 个 lanes 阶段用时 {anonymous_context['laneHours']:.3f} 小时，平均 {EXPECTED_LANES / anonymous_context['laneHours']:.3f} lanes/hour。",
        f"- 最后一个滚动小时完成 {anonymous_context['trailingHourCount']} 个 lanes。",
        f"- 冻结的五项长尾描述量结论：`{tail_assessment}`（{tail_reason}）。这是运行时间工程描述，不是算法效果排名或赢家。",
        "",
        "## 各算法进程墙钟分布（秒）",
        "",
        "| 算法 | n | P50 | P90 | P95 | P99 | 最大 | P95/P50 | P99/P50 | 最大/P50 | 超 pooled P95 | matched block 最慢频率 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    by_algorithm = {str(row["algorithmId"]): row for row in algorithm_summaries}
    for algorithm in algorithms:
        row = by_algorithm[algorithm]
        report_lines.append(
            f"| {algorithm} | {row['n']} | {row['processWallP50Milliseconds']/1000:.3f} | "
            f"{row['processWallP90Milliseconds']/1000:.3f} | {row['processWallP95Milliseconds']/1000:.3f} | "
            f"{row['processWallP99Milliseconds']/1000:.3f} | {row['processWallMaximumMilliseconds']/1000:.3f} | "
            f"{row['p95ToP50']:.3f} | {row['p99ToP50']:.3f} | {row['maximumToP50']:.3f} | "
            f"{row['shareAbovePooledP95']:.1%} | {row['matchedSuperblockMaximumFrequency']:.1%} |"
        )
    minimum_b = formal_prediction["rows"][0]
    report_lines.extend([
        "",
        "## 慢 G×N×F 与执行尾段",
        "",
        "慢 pooled G×N×F 与慢 algorithm×G×N×F 单元见 `slow-gnf-cells.v2.json`，全部具名单元见 `algorithm-gnf-runtime-cells.v2.csv`，最慢 30 条 lane 见 `slowest-lanes.v2.csv`。core 的 algorithm×G×N×F 每格只有 n=3，因此只报告 n、实际范围、P50 和最大值，不把 P99 当稳定总体估计。",
        "",
        "early/middle/late、近期窗口及同算法同 G×N×F 的顺序敏感性见 `order-tail-sensitivity.v2.json`。冻结 schedule 的负载组成与执行顺序存在混杂，随时间漂移不等于系统退化因果。热节流、缓存、杀毒、磁盘或内存压力缺少直接结构证据，只能列为候选解释。",
        "",
        "## 时间拆分可识别性",
        "",
        f"- process wall 与 inclusive lane-body 的 Pearson 相关为 {time_identifiability['directlyMeasured']['processWallVsInclusiveLaneBodyPearson']}；两者 P95 尾部重合率为 {overlap:.1%}。",
        "- 可直接识别：process wall、strict-serial inter-process gap、RunnerV4_2 inclusive lane-body。",
        "- 不可分别识别：纯算法 compute、Unity/startup、exit/finalization，因为没有可信绝对 workloadStartUtc/workloadEndUtc；不得以残差猜测。",
        "- inclusive lane-body 还含 grid 构造、planner 建立、oracle/cache 使用、instrumentation、资源采样、序列化与 raw 写盘，不能整体称为纯算法计算。",
        "",
        "## 正式 ST 参数化预算与 7 天门",
        "",
        f"按 B=36 的当前最小参数行，点估计 {minimum_b['pointHours']:.3f} 小时，保守估计 {minimum_b['conservativeHours']:.3f} 小时，含 20% 运行头寸为 {minimum_b['planningWith20PercentHeadroomHours']:.3f} 小时（{minimum_b['planningWith20PercentHeadroomDays']:.3f} 天）；168 小时门：{'触发' if seven_day_gate else '未触发'}。这只是工程预算，不是 B 决策或执行授权。",
        "",
        "## 边界",
        "",
        "这是 qualification 后的事后工程诊断，不是正式效果比较；未读取算法观测或质量指标，未估计效果方向，未排名、加权或裁决赢家，也不据此自动删除算法、改变科学问题、缩小样本、修改停止规则或启动 ST/MQ/MT。迁移包仍未构建。",
    ])
    (DIAG / "diagnostic-report.v2.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    return {
        "algorithmSummaries": algorithm_summaries,
        "tailAssessment": named_summary["longTailAssessment"],
        "slowCells": slow_cells,
        "timeIdentifiability": time_identifiability,
        "formalPrediction": formal_prediction,
    }, seven_day_gate


def main() -> int:
    started = time.perf_counter()
    started_utc = utc_now()
    DIAG.mkdir(parents=True, exist_ok=True)
    terminal_path = DIAG / "terminal-receipt.v2.json"
    if terminal_path.exists():
        raise DiagnosticError("one-shot diagnostic terminal receipt already exists")
    try:
        preexecution_freeze_sha = verify_preexecution_freeze()
        validate_activation()
        inventory: dict[Path, str] = {
            ANALYSIS_PLAN: "frozen-analysis-plan",
            DIAG / "field-boundary.v2.json": "frozen-field-boundary",
            DIAG / "diagnostic-authorization-receipt.v2.json": "user-authorization",
            DIAG / "runtime_diagnostic_v2.py": "diagnostic-implementation",
            DIAG / "Run-RuntimeDiagnostic.v2.ps1": "one-shot-diagnostic-launcher",
            PREEXECUTION_FREEZE: "diagnostic-pre-execution-freeze",
            QUALIFICATION_PASS: "terminal-qualification-pass-gate",
            ACQUISITION_TERMINAL: "raw-acquisition-terminal-receipt",
            ACCEPTANCE_TERMINAL: "independent-acceptance-terminal-final",
            RUNNER: "frozen-runner-timing-semantics",
            FORMAL_SAMPLE_DECISION: "preexisting-formal-sample-size-state",
        }
        ledger, records, launch = load_structural_records(inventory)
        anonymous, anonymous_sha, pooled_p95, anonymous_context = build_anonymous_prediction(ledger, records, launch)

        # The next call is the first point at which named identity or named schedule fields are loaded.
        algorithms, identity_unsealed_at = load_named_schedule_after_anonymous_freeze(records, anonymous_sha, inventory)
        named_result, seven_day_gate = build_named_diagnostic(
            records, algorithms, identity_unsealed_at, anonymous, anonymous_sha, pooled_p95, anonymous_context
        )

        candidate_path = DIAG / "st-major-simplification-candidate.v2.json"
        if seven_day_gate:
            candidate = {
                "schema": "gate14re-me-st-major-simplification-candidate-v2",
                "status": "PROPOSAL_ONLY_REQUIRES_EXPLICIT_FUTURE_SCIENTIFIC_AUTHORIZATION_AND_NEW_POWER_CONTRACTS",
                "trigger": "The current formal-ST planning budget at B=36 reaches or exceeds 168 hours.",
                "candidate": {
                    "retainAlgorithms": 6,
                    "retainGLevels": [64, 96, 128],
                    "retainNLevels": [32, 128],
                    "retainFLevels": [1, 81],
                    "coreCells": 12,
                    "reductionFrom36CoreCellsPercent": 66.667,
                    "principle": "retain all algorithms, all G levels and low/high N and F anchors while removing intermediate N and F combinations",
                },
                "lostInference": [
                    "No direct estimate at N=64.",
                    "No direct estimate at F=9 or F=25.",
                    "Reduced ability to estimate nonlinear intermediate-load behavior and higher-order interactions.",
                    "Power, multiplicity family, paired fairness, stopping rule, schedule and full-delivery cardinalities must be redesigned prospectively."
                ],
                "notAuthorized": ["automatic cell deletion", "automatic B change", "automatic formal ST collection", "automatic MQ or MT launch"],
            }
            write_json(candidate_path, candidate)

        inventory_rows: list[dict[str, Any]] = []
        for path, purpose in sorted(inventory.items(), key=lambda item: item[0].as_posix().lower()):
            if not path.is_file():
                raise DiagnosticError(f"diagnostic input missing at inventory freeze: {path}")
            inventory_rows.append({
                "schema": "gate14re-me-runtime-diagnostic-input-file-row-v2",
                "purpose": purpose,
                "absolutePath": path.as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
        inventory_path = DIAG / "input-file-inventory.v2.jsonl"
        write_jsonl(inventory_path, inventory_rows)

        output_names = [
            "analysis-plan.v2.json",
            "field-boundary.v2.json",
            "diagnostic-authorization-receipt.v2.json",
            "runtime_diagnostic_v2.py",
            "Run-RuntimeDiagnostic.v2.ps1",
            "pre-execution-freeze-manifest.v2.json",
            "anonymous-runtime-prediction.v2.json",
            "anonymous-prediction-freeze-receipt.v2.json",
            "named-algorithm-runtime-summary.v2.json",
            "named-algorithm-runtime-summary.v2.csv",
            "algorithm-gnf-runtime-cells.v2.csv",
            "slow-gnf-cells.v2.json",
            "slowest-lanes.v2.csv",
            "order-tail-sensitivity.v2.json",
            "time-component-identifiability.v2.json",
            "formal-st-runtime-prediction.v2.json",
            "load-runtime-cause-summary.v2.json",
            "diagnostic-report.v2.md",
            "input-file-inventory.v2.jsonl",
        ]
        if candidate_path.is_file():
            output_names.append(candidate_path.name)
        manifest_rows: list[dict[str, Any]] = []
        for name in sorted(output_names):
            path = DIAG / name
            if not path.is_file():
                raise DiagnosticError(f"expected diagnostic output missing: {name}")
            manifest_rows.append({
                "schema": "gate14re-me-runtime-diagnostic-file-row-v2",
                "relativePath": name,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
        manifest_path = DIAG / "diagnostic-file-manifest.v2.jsonl"
        write_jsonl(manifest_path, manifest_rows)

        terminal = {
            "schema": "gate14re-me-post-qualification-runtime-diagnostic-terminal-receipt-v2",
            "studyId": "Gate14Re-ME",
            "status": "PASS_POST_QUALIFICATION_DESCRIPTIVE_ENGINEERING_RUNTIME_DIAGNOSTIC",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "qualificationTerminalPassReceiptSha256": QUALIFICATION_PASS_SHA,
            "preExecutionFreezeManifestSha256": preexecution_freeze_sha,
            "anonymousPredictionSha256": anonymous_sha,
            "anonymousPredictionFrozenBeforeNamedIdentityLoad": True,
            "identityUnsealedAtUtc": identity_unsealed_at,
            "identityBindingSha256": IDENTITY_SHA,
            "scheduleSha256": SCHEDULE_SHA,
            "inputInventorySha256": sha256_file(inventory_path),
            "diagnosticManifestSha256": sha256_file(manifest_path),
            "freshProcessCount": EXPECTED_PROCESSES,
            "laneCount": EXPECTED_LANES,
            "superblockCount": EXPECTED_SUPERBLOCKS,
            "algorithmCount": EXPECTED_ALGORITHMS,
            "coreGnfCellCount": EXPECTED_CORE_GNF_CELLS,
            "sevenDayGateTriggeredAtB36": seven_day_gate,
            "longTailAssessment": named_result["tailAssessment"],
            "algorithmObservationsReadOrComputed": False,
            "scientificEffectsReadOrComputed": False,
            "rankingWeightingOrWinnerComputed": False,
            "formalAnalysisPerformed": False,
            "scientificDesignChanged": False,
            "stMqOrMtStarted": False,
            "migrationPackageBuilt": False,
            "sourceRootsModified": False,
        }
        write_json(terminal_path, terminal)
        print(json.dumps(terminal, ensure_ascii=False, sort_keys=True))
        return 0
    except Exception as exc:
        failure = {
            "schema": "gate14re-me-post-qualification-runtime-diagnostic-terminal-receipt-v2",
            "studyId": "Gate14Re-ME",
            "status": "FAIL_CLOSED_POST_QUALIFICATION_RUNTIME_DIAGNOSTIC",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "reason": str(exc),
            "algorithmObservationsReadOrComputed": False,
            "scientificEffectsReadOrComputed": False,
            "rankingWeightingOrWinnerComputed": False,
            "formalAnalysisPerformed": False,
            "scientificDesignChanged": False,
            "stMqOrMtStarted": False,
            "migrationPackageBuilt": False,
            "sourceRootsModified": False,
        }
        write_json(terminal_path, failure)
        print(json.dumps(failure, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
