#!/usr/bin/env python3
"""Deterministic formal MQ analysis for Gate14Re-MQ-CFF-IDFF.

The analyzer is deliberately batch-endpoint-only: it verifies every file in the
frozen acquisition manifest, but it never parses lane-level observation values.
Formal execution is single-use and creates a new result root without overwrite.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import statistics
import sys
import traceback
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import numpy as np


STUDY_ID = "Gate14Re-MQ-CFF-IDFF"
DESIGN_ID = "gate14re-mq-cff-idff-formal-v2"
EXPECTED_PROCESSES = 864
EXPECTED_BLOCKS = 36
PROCESSES_PER_BLOCK = 24
LANES_PER_PROCESS = 16
PRIMARY_IDS = ("P1", "P2", "P3", "P4")
SECONDARY_IDS = ("S1", "S2")
ALL_HYPOTHESIS_IDS = PRIMARY_IDS + SECONDARY_IDS
MIPE = -0.10536051565782628
ALPHA = 0.05
BOOTSTRAP_DRAWS = 100_000
BOOTSTRAP_SEED = 141_420_274

CONDITIONS = (
    "ST-DIRECT-LARGE-L3",
    "MQ-LARGE-L3-W1",
    "MQ-LARGE-L3-W2",
    "MQ-LARGE-L3-W4",
    "MQ-LARGE-L3-W8",
    "ST-DIRECT-HIGH-FREQUENCY",
    "MQ-HIGH-FREQUENCY-W1",
    "MQ-HIGH-FREQUENCY-W2",
    "MQ-HIGH-FREQUENCY-W4",
    "MQ-HIGH-FREQUENCY-W8",
    "MQ-DUAL-CCD-W8-4PLUS4",
    "MQ-DUAL-CCD-W16-8PLUS8",
)

HYPOTHESIS_SPEC = {
    "P1": ("OPAQUE-A", "LARGE_L3_CCD", "single-CCD log2-worker slope"),
    "P2": ("OPAQUE-A", "HIGH_FREQUENCY_CCD", "single-CCD log2-worker slope"),
    "P3": ("OPAQUE-B", "LARGE_L3_CCD", "single-CCD log2-worker slope"),
    "P4": ("OPAQUE-B", "HIGH_FREQUENCY_CCD", "single-CCD log2-worker slope"),
    "S1": ("OPAQUE-A", "DUAL_CCD_BALANCED", "W16-versus-W8 paired log ratio"),
    "S2": ("OPAQUE-B", "DUAL_CCD_BALANCED", "W16-versus-W8 paired log ratio"),
}


class AnalysisError(RuntimeError):
    def __init__(self, code: str, detail: str | None = None):
        self.code = code
        self.detail = detail or code
        super().__init__(f"{code}: {self.detail}")


def require(condition: bool, code: str, detail: str | None = None) -> None:
    if not condition:
        raise AnalysisError(code, detail)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def canonical_jsonl_bytes(rows: Iterable[Mapping[str, Any]]) -> bytes:
    return b"".join(
        (
            json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
            + "\n"
        ).encode("utf-8")
        for row in rows
    )


def atomic_create(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())


def write_json(path: Path, value: Any) -> None:
    atomic_create(path, canonical_json_bytes(value))


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise AnalysisError("INVALID_JSONL", f"{path}:{line_number}: {error}") from error
            require(isinstance(row, dict), "JSONL_ROW_NOT_OBJECT", f"{path}:{line_number}")
            rows.append(row)
    return rows


def resolve_inside(root: Path, relative_path: str, code: str) -> Path:
    rel = Path(relative_path)
    require(not rel.is_absolute(), code, relative_path)
    target = (root / rel).resolve()
    root_resolved = root.resolve()
    require(target == root_resolved or root_resolved in target.parents, code, relative_path)
    return target


def finite_positive(value: Any, code: str) -> float:
    require(isinstance(value, (int, float)) and not isinstance(value, bool), code)
    number = float(value)
    require(math.isfinite(number) and number > 0.0, code)
    return number


def json_number(value: float | int | None) -> float | int | None:
    if value is None or isinstance(value, int):
        return value
    return float(value) if math.isfinite(float(value)) else None


# Deterministic Student-t distribution implementation.
def _beta_continued_fraction(a: float, b: float, x: float) -> float:
    max_iter = 500
    eps = 3.0e-14
    fpmin = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < fpmin:
        d = fpmin
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= eps:
            return h
    raise AnalysisError("BETA_CONTINUED_FRACTION_NONCONVERGENCE")


def regularized_beta(a: float, b: float, x: float) -> float:
    require(a > 0 and b > 0 and 0 <= x <= 1, "INVALID_BETA_ARGUMENT")
    if x == 0:
        return 0.0
    if x == 1:
        return 1.0
    log_bt = (
        math.lgamma(a + b)
        - math.lgamma(a)
        - math.lgamma(b)
        + a * math.log(x)
        + b * math.log1p(-x)
    )
    bt = math.exp(log_bt)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _beta_continued_fraction(a, b, x) / a
    return 1.0 - bt * _beta_continued_fraction(b, a, 1.0 - x) / b


def t_cdf(t_value: float, degrees_freedom: float) -> float:
    require(degrees_freedom > 0 and math.isfinite(degrees_freedom), "INVALID_T_DF")
    if t_value == 0:
        return 0.5
    x = degrees_freedom / (degrees_freedom + t_value * t_value)
    twice_tail = regularized_beta(degrees_freedom / 2.0, 0.5, x)
    return 1.0 - 0.5 * twice_tail if t_value > 0 else 0.5 * twice_tail


def t_ppf(probability: float, degrees_freedom: float) -> float:
    require(0 < probability < 1, "INVALID_T_PROBABILITY")
    if probability == 0.5:
        return 0.0
    if probability < 0.5:
        return -t_ppf(1.0 - probability, degrees_freedom)
    lo, hi = 0.0, 1.0
    while t_cdf(hi, degrees_freedom) < probability:
        hi *= 2.0
        require(hi < 1.0e6, "T_QUANTILE_BRACKET_FAILURE")
    for _ in range(160):
        mid = (lo + hi) / 2.0
        if t_cdf(mid, degrees_freedom) < probability:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def holm_adjust(pvalues: Sequence[float]) -> list[float]:
    m = len(pvalues)
    order = sorted(range(m), key=lambda index: (float(pvalues[index]), index))
    adjusted = [0.0] * m
    running = 0.0
    for rank, index in enumerate(order):
        candidate = min(1.0, (m - rank) * float(pvalues[index]))
        running = max(running, candidate)
        adjusted[index] = running
    return adjusted


def one_sample_statistics(values: Sequence[float], family_size: int) -> dict[str, Any]:
    require(len(values) >= 2, "INSUFFICIENT_BLOCK_ESTIMANDS")
    n = len(values)
    mean = statistics.fmean(values)
    standard_deviation = statistics.stdev(values)
    standard_error = standard_deviation / math.sqrt(n)
    degrees_freedom = n - 1
    if standard_error == 0.0:
        t_statistic = -math.inf if mean < 0 else math.inf if mean > 0 else 0.0
        raw_p = 0.0 if mean < 0 else 1.0 if mean > 0 else 0.5
    else:
        t_statistic = mean / standard_error
        raw_p = t_cdf(t_statistic, degrees_freedom)
    ordinary_t = t_ppf(0.975, degrees_freedom)
    upper_t = t_ppf(0.95, degrees_freedom)
    decision_t = t_ppf(1.0 - ALPHA / family_size, degrees_freedom)
    ordinary_lower = mean - ordinary_t * standard_error
    ordinary_upper = mean + ordinary_t * standard_error
    one_sided_upper = mean + upper_t * standard_error
    decision_upper = mean + decision_t * standard_error
    ratio = math.exp(mean)
    return {
        "n": n,
        "meanLogEstimate": mean,
        "geometricRatio": ratio,
        "percentChange": 100.0 * (ratio - 1.0),
        "sampleStandardDeviation": standard_deviation,
        "standardError": standard_error,
        "degreesOfFreedom": degrees_freedom,
        "tStatistic": json_number(t_statistic),
        "rawOneSidedP": raw_p,
        "ordinaryTwoSided95CiLog": [ordinary_lower, ordinary_upper],
        "ordinaryTwoSided95CiRatio": [math.exp(ordinary_lower), math.exp(ordinary_upper)],
        "ordinaryOneSided95UpperLog": one_sided_upper,
        "ordinaryOneSided95UpperRatio": math.exp(one_sided_upper),
        "bonferroniFamilySize": family_size,
        "bonferroniOneSidedUpperLog": decision_upper,
        "bonferroniOneSidedUpperRatio": math.exp(decision_upper),
        "pointEstimateMeetsMipe": mean <= MIPE,
    }


def ordinary_log_summary(values: Sequence[float]) -> dict[str, Any]:
    require(len(values) >= 2, "INSUFFICIENT_DESCRIPTIVE_VALUES")
    n = len(values)
    mean = statistics.fmean(values)
    sd = statistics.stdev(values)
    se = sd / math.sqrt(n)
    critical = t_ppf(0.975, n - 1)
    lower = mean - critical * se
    upper = mean + critical * se
    return {
        "n": n,
        "meanLogEstimate": mean,
        "geometricEstimate": math.exp(mean),
        "ordinaryTwoSided95CiLog": [lower, upper],
        "ordinaryTwoSided95CiGeometric": [math.exp(lower), math.exp(upper)],
        "sampleStandardDeviationLog": sd,
        "standardErrorLog": se,
        "degreesOfFreedom": n - 1,
    }


def equal_weight_slope(worker_to_seconds: Mapping[int, float]) -> float:
    workers = (1, 2, 4, 8)
    require(set(worker_to_seconds) == set(workers), "SLOPE_WORKER_SET_MISMATCH")
    x = (0.0, 1.0, 2.0, 3.0)
    x_mean = 1.5
    y = [math.log(worker_to_seconds[worker]) for worker in workers]
    y_mean = statistics.fmean(y)
    numerator = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
    denominator = sum((xi - x_mean) ** 2 for xi in x)
    return numerator / denominator


def exact_signed_rank_lower_p(values: Sequence[float]) -> dict[str, Any]:
    nonzero = [(index, float(value)) for index, value in enumerate(values) if float(value) != 0.0]
    if not nonzero:
        return {"nNonzero": 0, "wPlus": 0.0, "exactLowerTailP": 1.0}
    sorted_values = sorted(nonzero, key=lambda item: (abs(item[1]), item[0]))
    rank2_by_original: dict[int, int] = {}
    cursor = 0
    while cursor < len(sorted_values):
        end = cursor + 1
        while end < len(sorted_values) and abs(sorted_values[end][1]) == abs(sorted_values[cursor][1]):
            end += 1
        first_rank = cursor + 1
        last_rank = end
        average_rank_times_two = first_rank + last_rank
        for position in range(cursor, end):
            rank2_by_original[sorted_values[position][0]] = average_rank_times_two
        cursor = end
    scaled_ranks = [rank2_by_original[index] for index, _ in nonzero]
    observed = sum(rank for rank, (_, value) in zip(scaled_ranks, nonzero) if value > 0)
    total = sum(scaled_ranks)
    ways = [0] * (total + 1)
    ways[0] = 1
    for rank in scaled_ranks:
        for current in range(total - rank, -1, -1):
            if ways[current]:
                ways[current + rank] += ways[current]
    numerator = sum(ways[: observed + 1])
    denominator = 1 << len(nonzero)
    return {
        "nNonzero": len(nonzero),
        "wPlus": observed / 2.0,
        "exactLowerTailP": numerator / denominator,
        "tieConditional": True,
    }


def studentized_bootstrap(
    matrix: np.ndarray,
    draws: int,
    seed: int,
    column_ids: Sequence[str],
) -> dict[str, Any]:
    require(matrix.ndim == 2, "BOOTSTRAP_MATRIX_DIMENSION")
    n, k = matrix.shape
    require(n >= 2 and k == len(column_ids), "BOOTSTRAP_MATRIX_SHAPE")
    original_means = matrix.mean(axis=0)
    original_se = matrix.std(axis=0, ddof=1) / math.sqrt(n)
    rng = np.random.Generator(np.random.PCG64(seed))
    pivot_parts: list[list[np.ndarray]] = [[] for _ in range(k)]
    invalid = np.zeros(k, dtype=np.int64)
    generated = 0
    chunk_size = 5_000
    while generated < draws:
        current = min(chunk_size, draws - generated)
        indices = rng.integers(0, n, size=(current, n), endpoint=False)
        samples = matrix[indices, :]
        sample_means = samples.mean(axis=1)
        sample_se = samples.std(axis=1, ddof=1) / math.sqrt(n)
        for column in range(k):
            valid = sample_se[:, column] > 0.0
            invalid[column] += int((~valid).sum())
            if np.any(valid):
                pivot_parts[column].append(
                    (sample_means[valid, column] - original_means[column]) / sample_se[valid, column]
                )
        generated += current
    results: dict[str, Any] = {}
    for column, hypothesis_id in enumerate(column_ids):
        require(original_se[column] > 0.0, "BOOTSTRAP_ZERO_ORIGINAL_SE", hypothesis_id)
        pivots = np.concatenate(pivot_parts[column])
        require(pivots.size >= int(draws * 0.99), "BOOTSTRAP_TOO_MANY_INVALID", hypothesis_id)
        lower_quantile, upper_quantile = np.quantile(pivots, [0.025, 0.975], method="linear")
        lower = float(original_means[column] - upper_quantile * original_se[column])
        upper = float(original_means[column] - lower_quantile * original_se[column])
        results[hypothesis_id] = {
            "drawsRequested": draws,
            "validStudentizedDraws": int(pivots.size),
            "invalidZeroSeDraws": int(invalid[column]),
            "twoSided95StudentizedCiLog": [lower, upper],
            "twoSided95StudentizedCiRatio": [math.exp(lower), math.exp(upper)],
        }
    return {
        "seed": seed,
        "bitGenerator": "PCG64",
        "resamplingUnit": "complete matched block",
        "columns": results,
    }


def leave_one_out(values: Sequence[float], block_ids: Sequence[str]) -> dict[str, Any]:
    require(len(values) == len(block_ids) and len(values) >= 3, "INVALID_LOO_INPUT")
    full = statistics.fmean(values)
    rows = []
    for index, block_id in enumerate(block_ids):
        retained = values[:index] + values[index + 1 :]
        estimate = statistics.fmean(retained)
        rows.append(
            {
                "omittedBlockId": block_id,
                "estimate": estimate,
                "shiftFromFull": estimate - full,
            }
        )
    maximum = max(rows, key=lambda row: (abs(row["shiftFromFull"]), row["omittedBlockId"]))
    return {
        "fullEstimate": full,
        "minimumLeaveOneOutEstimate": min(row["estimate"] for row in rows),
        "maximumLeaveOneOutEstimate": max(row["estimate"] for row in rows),
        "maximumAbsoluteShift": abs(maximum["shiftFromFull"]),
        "mostInfluentialOmittedBlockId": maximum["omittedBlockId"],
        "allLeaveOneOutEstimatesBelowZero": all(row["estimate"] < 0.0 for row in rows),
        "allLeaveOneOutEstimatesMeetMipe": all(row["estimate"] <= MIPE for row in rows),
        "rows": rows,
    }


def verify_bound_file(project_root: Path, binding: Mapping[str, Any], code: str) -> Path:
    path = resolve_inside(project_root, str(binding["relativePath"]), f"{code}_PATH")
    require(path.is_file(), f"{code}_MISSING", str(path))
    require(sha256_file(path) == str(binding["sha256"]).lower(), f"{code}_HASH_MISMATCH", str(path))
    return path


def verify_acquisition_manifest(measured_root: Path, manifest_path: Path) -> dict[str, Any]:
    manifest = load_json(manifest_path)
    require(manifest.get("schema") == "gate14re-mq-formal-acquisition-freeze-manifest-v2", "ACQUISITION_MANIFEST_SCHEMA")
    require(manifest.get("status") == "FROZEN_COMPLETE_RAW_FORMAL_MQ_COLLECTION", "ACQUISITION_MANIFEST_STATUS")
    require(manifest.get("formalAnalysisStarted") is False, "ACQUISITION_MANIFEST_ANALYSIS_ALREADY_STARTED")
    files = manifest.get("files")
    require(isinstance(files, list), "ACQUISITION_MANIFEST_FILES")
    require(int(manifest.get("fileCount", -1)) == len(files) == 4325, "ACQUISITION_MANIFEST_CARDINALITY")
    seen: set[str] = set()
    total_bytes = 0
    for entry in files:
        relative_path = str(entry.get("relativePath", ""))
        require(relative_path not in seen, "ACQUISITION_MANIFEST_DUPLICATE", relative_path)
        seen.add(relative_path)
        path = resolve_inside(measured_root, relative_path, "ACQUISITION_FILE_PATH")
        require(path.is_file(), "ACQUISITION_FILE_MISSING", relative_path)
        expected_bytes = int(entry.get("bytes", -1))
        actual_bytes = path.stat().st_size
        require(actual_bytes == expected_bytes, "ACQUISITION_FILE_SIZE_MISMATCH", relative_path)
        require(sha256_file(path) == str(entry.get("sha256", "")).lower(), "ACQUISITION_FILE_HASH_MISMATCH", relative_path)
        total_bytes += actual_bytes
    return {
        "schema": manifest["schema"],
        "status": manifest["status"],
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "allPathsUnique": True,
        "allSizesMatch": True,
        "allSha256Match": True,
    }


def verify_schedule(schedule_path: Path) -> list[dict[str, Any]]:
    rows = load_jsonl(schedule_path)
    require(len(rows) == EXPECTED_PROCESSES, "SCHEDULE_ROW_COUNT")
    require([int(row.get("processOrdinal", -1)) for row in rows] == list(range(EXPECTED_PROCESSES)), "SCHEDULE_ORDINALS")
    by_block: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        require(row.get("schema") == "gate14re-mq-formal-process-schedule-row-v2", "SCHEDULE_SCHEMA")
        require(row.get("replacement") is None, "SCHEDULE_REPLACEMENT")
        require(row.get("opaqueAlgorithmSlot") in {"OPAQUE-A", "OPAQUE-B"}, "SCHEDULE_SLOT")
        require(row.get("conditionId") in CONDITIONS, "SCHEDULE_CONDITION")
        by_block[int(row["blockOrdinal"])].append(row)
    require(set(by_block) == set(range(EXPECTED_BLOCKS)), "SCHEDULE_BLOCK_ORDINALS")
    for block_ordinal, block_rows in by_block.items():
        require(len(block_rows) == PROCESSES_PER_BLOCK, "SCHEDULE_BLOCK_SIZE", str(block_ordinal))
        for slot in ("OPAQUE-A", "OPAQUE-B"):
            slot_rows = [row for row in block_rows if row["opaqueAlgorithmSlot"] == slot]
            require(len(slot_rows) == len(CONDITIONS), "SCHEDULE_SLOT_SIZE", f"{block_ordinal}:{slot}")
            require({row["conditionId"] for row in slot_rows} == set(CONDITIONS), "SCHEDULE_CONDITION_SET", f"{block_ordinal}:{slot}")
    return rows


def validate_collection_terminal(terminal: Mapping[str, Any], final_seal: Mapping[str, Any]) -> None:
    require(terminal.get("status") == "PASS_FORMAL_MQ_COLLECTION_TERMINAL_FORMAL_ANALYSIS_NOT_AUTHORIZED", "COLLECTION_TERMINAL_STATUS")
    require(terminal.get("formalCollectionComplete") is True, "COLLECTION_NOT_COMPLETE")
    require(terminal.get("formalAnalysisStarted") is False, "COLLECTION_ANALYSIS_ALREADY_STARTED")
    require(terminal.get("algorithmObservationsReadOrInterpreted") is False, "COLLECTION_OBSERVATIONS_PREVIOUSLY_READ")
    require(int(terminal.get("completedFreshUnityProcesses", -1)) == EXPECTED_PROCESSES, "COLLECTION_PROCESS_COUNT")
    require(int(terminal.get("matchedBlocks", -1)) == EXPECTED_BLOCKS, "COLLECTION_BLOCK_COUNT")
    require(int(terminal.get("failureLedgerRows", -1)) == 0, "COLLECTION_FAILURE_ROWS")
    require(int(terminal.get("replacementLedgerRows", -1)) == 0, "COLLECTION_REPLACEMENT_ROWS")
    require(final_seal.get("formalCollectionComplete") is True, "COLLECTION_FINAL_SEAL_INCOMPLETE")
    require(final_seal.get("formalAnalysisStarted") is False, "COLLECTION_FINAL_SEAL_ANALYSIS_STARTED")
    require(final_seal.get("algorithmObservationsReadOrInterpreted") is False, "COLLECTION_FINAL_SEAL_OBSERVATIONS_READ")


def load_and_validate_batches(
    measured_root: Path,
    schedule_rows: Sequence[Mapping[str, Any]],
) -> tuple[dict[str, dict[str, dict[str, float]]], list[dict[str, Any]]]:
    data: dict[str, dict[str, dict[str, float]]] = defaultdict(lambda: defaultdict(dict))
    structural_rows: list[dict[str, Any]] = []
    for schedule in schedule_rows:
        ordinal = int(schedule["processOrdinal"])
        block_id = str(schedule["blockId"])
        slot = str(schedule["opaqueAlgorithmSlot"])
        condition = str(schedule["conditionId"])
        batch_path = measured_root / "raw" / "blocks" / block_id / f"process-{ordinal:04d}" / "formal-batch.raw.v2.json"
        require(batch_path.is_file(), "BATCH_FILE_MISSING", str(batch_path))
        batch = load_json(batch_path)
        require(batch.get("schema") == "gate14re-mq-formal-batch-evidence-v2", "BATCH_SCHEMA", str(batch_path))
        comparisons = {
            "processOrdinal": ordinal,
            "blockOrdinal": int(schedule["blockOrdinal"]),
            "blockId": block_id,
            "positionWithinBlock": int(schedule["positionWithinBlock"]),
            "opaqueAlgorithmSlot": slot,
            "conditionId": condition,
            "executorMode": str(schedule["executorMode"]),
            "topologyRole": str(schedule["topologyRole"]),
            "workerCount": int(schedule["workerCount"]),
        }
        for key, expected in comparisons.items():
            require(batch.get(key) == expected, "BATCH_SCHEDULE_MISMATCH", f"{ordinal}:{key}")
        require(int(batch.get("laneCount", -1)) == LANES_PER_PROCESS, "BATCH_LANE_COUNT", str(ordinal))
        require(batch.get("allAffinityBindingsObserved") is True, "BATCH_AFFINITY_GATE", str(ordinal))
        require(batch.get("allLanesComplete") is True, "BATCH_LANE_GATE", str(ordinal))
        require(batch.get("allOracleHardGatesPassed") is True, "BATCH_ORACLE_GATE", str(ordinal))
        seconds = finite_positive(batch.get("batchWallSeconds"), "BATCH_WALL_SECONDS")
        require(condition not in data[block_id][slot], "DUPLICATE_BATCH_CELL", f"{block_id}:{slot}:{condition}")
        data[block_id][slot][condition] = seconds
        structural_rows.append({**comparisons, "laneCount": LANES_PER_PROCESS})
    require(len(data) == EXPECTED_BLOCKS, "BATCH_BLOCK_COUNT")
    for block_id, slots in data.items():
        require(set(slots) == {"OPAQUE-A", "OPAQUE-B"}, "BATCH_SLOT_SET", block_id)
        for slot, cells in slots.items():
            require(set(cells) == set(CONDITIONS), "BATCH_CONDITION_SET", f"{block_id}:{slot}")
    return data, structural_rows


def compute_block_estimands(
    data: Mapping[str, Mapping[str, Mapping[str, float]]],
    identity: Mapping[str, str],
) -> tuple[list[dict[str, Any]], list[str], dict[str, list[float]]]:
    block_ids = sorted(data)
    values: dict[str, list[float]] = {hypothesis_id: [] for hypothesis_id in ALL_HYPOTHESIS_IDS}
    rows: list[dict[str, Any]] = []
    for block_id in block_ids:
        block_values: dict[str, float] = {}
        for hypothesis_id in ALL_HYPOTHESIS_IDS:
            slot, topology, estimand = HYPOTHESIS_SPEC[hypothesis_id]
            cells = data[block_id][slot]
            if topology == "LARGE_L3_CCD":
                worker_to_seconds = {
                    worker: cells[f"MQ-LARGE-L3-W{worker}"] for worker in (1, 2, 4, 8)
                }
                estimate = equal_weight_slope(worker_to_seconds)
            elif topology == "HIGH_FREQUENCY_CCD":
                worker_to_seconds = {
                    worker: cells[f"MQ-HIGH-FREQUENCY-W{worker}"] for worker in (1, 2, 4, 8)
                }
                estimate = equal_weight_slope(worker_to_seconds)
            else:
                estimate = math.log(
                    cells["MQ-DUAL-CCD-W16-8PLUS8"]
                    / cells["MQ-DUAL-CCD-W8-4PLUS4"]
                )
            values[hypothesis_id].append(estimate)
            block_values[hypothesis_id] = estimate
            rows.append(
                {
                    "schema": "gate14re-mq-formal-block-estimand-row-v1",
                    "blockId": block_id,
                    "hypothesisId": hypothesis_id,
                    "opaqueAlgorithmSlot": slot,
                    "algorithmId": identity[slot],
                    "topology": topology,
                    "estimand": estimand,
                    "logEstimate": estimate,
                    "geometricRatio": math.exp(estimate),
                }
            )
    return rows, block_ids, values


def apply_inference(
    values: Mapping[str, Sequence[float]],
    identity: Mapping[str, str],
) -> dict[str, Any]:
    results: dict[str, dict[str, Any]] = {}
    for hypothesis_id in PRIMARY_IDS:
        slot, topology, estimand = HYPOTHESIS_SPEC[hypothesis_id]
        row = one_sample_statistics(values[hypothesis_id], len(PRIMARY_IDS))
        row.update(
            {
                "hypothesisId": hypothesis_id,
                "opaqueAlgorithmSlot": slot,
                "algorithmId": identity[slot],
                "topology": topology,
                "estimand": estimand,
                "family": "confirmatory-primary",
            }
        )
        results[hypothesis_id] = row
    primary_adjusted = holm_adjust([results[hypothesis_id]["rawOneSidedP"] for hypothesis_id in PRIMARY_IDS])
    for hypothesis_id, adjusted in zip(PRIMARY_IDS, primary_adjusted):
        row = results[hypothesis_id]
        row["holmAdjustedOneSidedP"] = adjusted
        row["holmRejectedAtFamilywiseAlpha05"] = adjusted < ALPHA
        row["simultaneousUpperBoundBelowZero"] = row["bonferroniOneSidedUpperLog"] < 0.0
        row["confirmatoryClaimPassed"] = bool(
            row["holmRejectedAtFamilywiseAlpha05"]
            and row["simultaneousUpperBoundBelowZero"]
            and row["pointEstimateMeetsMipe"]
        )
    gate_open = all(results[hypothesis_id]["holmRejectedAtFamilywiseAlpha05"] for hypothesis_id in PRIMARY_IDS)
    for hypothesis_id in SECONDARY_IDS:
        slot, topology, estimand = HYPOTHESIS_SPEC[hypothesis_id]
        row = one_sample_statistics(values[hypothesis_id], len(SECONDARY_IDS))
        row.update(
            {
                "hypothesisId": hypothesis_id,
                "formerHypothesisId": "P5" if hypothesis_id == "S1" else "P6",
                "opaqueAlgorithmSlot": slot,
                "algorithmId": identity[slot],
                "topology": topology,
                "estimand": estimand,
                "family": "gated-key-secondary",
                "gateOpen": gate_open,
                "inferentiallyEligible": gate_open,
            }
        )
        results[hypothesis_id] = row
    secondary_adjusted = holm_adjust([results[hypothesis_id]["rawOneSidedP"] for hypothesis_id in SECONDARY_IDS])
    for hypothesis_id, adjusted in zip(SECONDARY_IDS, secondary_adjusted):
        row = results[hypothesis_id]
        row["holmAdjustedOneSidedP"] = adjusted
        row["holmRejectedAtFamilywiseAlpha05"] = bool(gate_open and adjusted < ALPHA)
        row["simultaneousUpperBoundBelowZero"] = row["bonferroniOneSidedUpperLog"] < 0.0
        row["keySecondaryClaimPassed"] = bool(
            gate_open
            and adjusted < ALPHA
            and row["simultaneousUpperBoundBelowZero"]
            and row["pointEstimateMeetsMipe"]
        )
        if not gate_open:
            row["reportingRole"] = "descriptive-only-because-primary-gate-closed"
        else:
            row["reportingRole"] = "gated-key-secondary-inference"
    return {
        "schema": "gate14re-mq-formal-confirmatory-and-secondary-results-v1",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "status": "ANALYZED_UNDER_FROZEN_V2_RULES",
        "familywiseAlpha": ALPHA,
        "mipeLogScale": MIPE,
        "primaryFamily": list(PRIMARY_IDS),
        "primaryGateForSecondariesOpen": gate_open,
        "keySecondaryFamily": list(SECONDARY_IDS),
        "results": [results[hypothesis_id] for hypothesis_id in ALL_HYPOTHESIS_IDS],
        "noAlgorithmRankingOrWinner": True,
    }


def condition_summaries(
    data: Mapping[str, Mapping[str, Mapping[str, float]]],
    identity: Mapping[str, str],
) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for slot in ("OPAQUE-A", "OPAQUE-B"):
        for condition in CONDITIONS:
            seconds = [data[block_id][slot][condition] for block_id in sorted(data)]
            log_summary = ordinary_log_summary([math.log(value) for value in seconds])
            rows.append(
                {
                    "opaqueAlgorithmSlot": slot,
                    "algorithmId": identity[slot],
                    "conditionId": condition,
                    "geometricMeanBatchWallSeconds": log_summary["geometricEstimate"],
                    "ordinaryTwoSided95CiBatchWallSeconds": log_summary["ordinaryTwoSided95CiGeometric"],
                    "medianBatchWallSeconds": statistics.median(seconds),
                    "minimumBatchWallSeconds": min(seconds),
                    "maximumBatchWallSeconds": max(seconds),
                    "nMatchedBlocks": len(seconds),
                }
            )
    return {
        "schema": "gate14re-mq-formal-condition-summaries-v1",
        "studyId": STUDY_ID,
        "endpoint": "batchWallSeconds",
        "intervalRole": "ordinary descriptive, not multiplicity-adjusted",
        "rows": rows,
    }


def descriptive_exploratory(
    data: Mapping[str, Mapping[str, Mapping[str, float]]],
    block_values: Mapping[str, Sequence[float]],
    block_ids: Sequence[str],
    identity: Mapping[str, str],
) -> dict[str, Any]:
    overhead_rows: list[dict[str, Any]] = []
    for slot in ("OPAQUE-A", "OPAQUE-B"):
        for topology, direct_condition, mq_condition in (
            ("LARGE_L3_CCD", "ST-DIRECT-LARGE-L3", "MQ-LARGE-L3-W1"),
            ("HIGH_FREQUENCY_CCD", "ST-DIRECT-HIGH-FREQUENCY", "MQ-HIGH-FREQUENCY-W1"),
        ):
            contrasts = [
                math.log(data[block_id][slot][mq_condition] / data[block_id][slot][direct_condition])
                for block_id in block_ids
            ]
            overhead_rows.append(
                {
                    "opaqueAlgorithmSlot": slot,
                    "algorithmId": identity[slot],
                    "topology": topology,
                    "estimand": "log(MQ-W1 batchWallSeconds / ST-direct batchWallSeconds)",
                    "summary": ordinary_log_summary(contrasts),
                    "role": "descriptive implementation-overhead sentinel only",
                }
            )
    slot_by_algorithm = {algorithm: slot for slot, algorithm in identity.items()}
    require(set(slot_by_algorithm) == {"C-FF", "IDFF"}, "IDENTITY_ALGORITHM_SET")
    cross_rows: list[dict[str, Any]] = []
    for first_id, second_id, topology in (
        ("P1", "P3", "LARGE_L3_CCD"),
        ("P2", "P4", "HIGH_FREQUENCY_CCD"),
        ("S1", "S2", "DUAL_CCD_BALANCED"),
    ):
        differences = [a - b for a, b in zip(block_values[first_id], block_values[second_id])]
        cross_rows.append(
            {
                "topology": topology,
                "contrast": "C-FF minus IDFF corresponding block estimand",
                "summary": ordinary_log_summary(differences),
                "role": "exploratory estimate and ordinary interval only; no ranking or winner inference",
            }
        )
    return {
        "schema": "gate14re-mq-formal-descriptive-and-exploratory-results-v1",
        "studyId": STUDY_ID,
        "stDirectVersusMqW1": overhead_rows,
        "crossAlgorithmInteractions": cross_rows,
        "algorithmRankingOrWinner": False,
        "causalCcdAttribution": False,
    }


def sensitivity_results(
    values: Mapping[str, Sequence[float]],
    block_ids: Sequence[str],
) -> dict[str, Any]:
    matrix = np.asarray([[values[hypothesis_id][index] for hypothesis_id in ALL_HYPOTHESIS_IDS] for index in range(len(block_ids))], dtype=np.float64)
    bootstrap = studentized_bootstrap(matrix, BOOTSTRAP_DRAWS, BOOTSTRAP_SEED, ALL_HYPOTHESIS_IDS)
    rows = []
    for hypothesis_id in ALL_HYPOTHESIS_IDS:
        rows.append(
            {
                "hypothesisId": hypothesis_id,
                "signedRank": exact_signed_rank_lower_p(values[hypothesis_id]),
                "leaveOneBlockOut": leave_one_out(list(values[hypothesis_id]), list(block_ids)),
                "bootstrap": bootstrap["columns"][hypothesis_id],
            }
        )
    return {
        "schema": "gate14re-mq-formal-sensitivity-analysis-v1",
        "studyId": STUDY_ID,
        "claimChanging": False,
        "bootstrapSeed": BOOTSTRAP_SEED,
        "bootstrapDraws": BOOTSTRAP_DRAWS,
        "rows": rows,
    }


def statistical_validation(confirmatory: Mapping[str, Any]) -> dict[str, Any]:
    fallacies = [
        ("Simpson's paradox", "NOTE", "Separate frozen topology-specific block estimands were analysed; no pooled topology effect was substituted."),
        ("Ecological fallacy", "NOTE", "Inference is explicitly at the complete matched-block level; lane and process rows are not independent n."),
        ("Berkson's paradox", "NOTE", "No outcome-based sample filtering was permitted; all 36 frozen complete blocks entered each estimand."),
        ("Collider bias", "NOTE", "The frozen primary analysis contains no post-treatment covariate adjustment."),
        ("Base-rate neglect", "NOTE", "Not applicable: the endpoint is continuous batch wall time, not a diagnostic classification rate."),
        ("Regression to the mean", "NOTE", "Not applicable: blocks were not selected by extreme outcome and the design is not an extreme-score pre/post study."),
        ("Survivorship bias", "NOTE", "All 36 frozen blocks and all 864 processes passed the acquisition hard gates; no completer-only subset was created."),
        ("Look-elsewhere effect", "NOTE", "P1-P4 were prespecified and Holm-adjusted; S1-S2 are separately gated and Holm-adjusted."),
        ("Garden of forking paths", "NOTE", "Estimator, test, multiplicity, interval companion, bootstrap seed/draw count and outputs were frozen before batch outcome parsing."),
        ("Correlation is not causation", "NOTE", "Claims are bounded to controlled within-algorithm worker scaling; causal CCD-mechanism attribution is prohibited."),
        ("Reverse causality", "NOTE", "Not applicable to the randomized, fixed-condition execution contrast."),
    ]
    return {
        "schema": "gate14re-mq-formal-statistical-validation-v1",
        "studyId": STUDY_ID,
        "verificationStatus": "ANALYZED",
        "overallConfidence": "SOLID",
        "independentUnit": "complete matched block",
        "nPerHypothesis": EXPECTED_BLOCKS,
        "technicalRowsTreatedAsIndependent": False,
        "multipleComparisonControl": "Holm P1-P4; gated Holm S1-S2; conservative Bonferroni one-sided simultaneous decision bounds",
        "primaryGateForSecondariesOpen": confirmatory["primaryGateForSecondariesOpen"],
        "fallacyScanCoverage": "11/11",
        "fallacyScan": [
            {"fallacy": name, "severity": severity, "detail": detail}
            for name, severity, detail in fallacies
        ],
        "reproducibility": {
            "method": "single authorized deterministic formal execution plus frozen synthetic known-answer validation",
            "verdict": "ANALYZED",
            "reasonNotRerun": "the analysis contract authorizes one formal execution and no overwrite; no second formal-data run was performed",
        },
        "algorithmRankingOrWinner": False,
    }


def format_p(value: float) -> str:
    if value < 0.0001:
        return f"{value:.3e}"
    return f"{value:.6f}"


def claim_text(row: Mapping[str, Any]) -> str:
    if row["family"] == "confirmatory-primary":
        if row["confirmatoryClaimPassed"]:
            return "PASS：统计支持且达到预设 MIPE"
        if row["holmRejectedAtFamilywiseAlpha05"]:
            return "未形成完整 claim：虽经 Holm 拒绝，但区间或 MIPE 门未同时满足"
        return "未拒绝无改善零假设"
    if not row["gateOpen"]:
        return "主族门未开启；仅描述"
    if row["keySecondaryClaimPassed"]:
        return "PASS：门控 secondary 统计支持且达到 MIPE"
    if row["holmRejectedAtFamilywiseAlpha05"]:
        return "未形成完整 claim：虽经 Holm 拒绝，但区间或 MIPE 门未同时满足"
    return "门已开启，但未拒绝无改善零假设"


def build_report(
    authorization_id: str,
    confirmatory: Mapping[str, Any],
    validation: Mapping[str, Any],
) -> str:
    lines = [
        "# Gate14Re-MQ-CFF-IDFF 正式 MQ 分析结果（v1）",
        "",
        "## Material Passport",
        "",
        "- Origin Skill: experiment-agent + nature-statistics",
        "- Origin Mode: run + validate",
        f"- Origin Date: {utc_now()}",
        "- Verification Status: ANALYZED",
        "- Version Label: gate14re_mq_formal_analysis_v1",
        f"- Authorization ID: {authorization_id}",
        "",
        "## 终局结论边界",
        "",
        "本报告只分析已封印的 MQ attempt-003。分析终端 PASS 表示数据完整性与冻结统计流程成功执行，不等同于所有科学假设均通过。未启动 formal ST、MT，未进行算法排名或赢家裁决。",
        "",
        "## 冻结设计读出",
        "",
        "- 独立分析单位：完整 matched block；每项假设 n=36。",
        "- 技术层级：864 个进程和每进程 16 条 lane 均不被当作独立 n。",
        "- 主族：P1–P4，单侧 one-sample Student t；Holm 强 FWER 0.05。",
        "- 决策区间：P1–P4 使用 Bonferroni 单侧同时上界（族置信度 95%）；S1–S2 在门开启时对应使用二项族上界。",
        "- 实际重要性：点估计必须不高于 log(0.9) 才达到 10% MIPE。",
        "",
        "## 主检验与门控 secondary",
        "",
        "| ID | 算法 | 拓扑 | 几何比 | 95% 普通区间 | Holm p | Bonferroni 上界（比值） | MIPE | 判定 |",
        "|---|---|---|---:|---:|---:|---:|:---:|---|",
    ]
    for row in confirmatory["results"]:
        ratio_ci = row["ordinaryTwoSided95CiRatio"]
        lines.append(
            "| {id} | {algorithm} | {topology} | {ratio:.6f} | [{lo:.6f}, {hi:.6f}] | {p} | {upper:.6f} | {mipe} | {decision} |".format(
                id=row["hypothesisId"],
                algorithm=row["algorithmId"],
                topology=row["topology"],
                ratio=row["geometricRatio"],
                lo=ratio_ci[0],
                hi=ratio_ci[1],
                p=format_p(row["holmAdjustedOneSidedP"]),
                upper=row["bonferroniOneSidedUpperRatio"],
                mipe="是" if row["pointEstimateMeetsMipe"] else "否",
                decision=claim_text(row),
            )
        )
    lines.extend(
        [
            "",
            f"S1–S2 门状态：{'OPEN' if confirmatory['primaryGateForSecondariesOpen'] else 'CLOSED'}。门控规则只取决于 P1–P4 是否全部经 Holm 拒绝；MIPE 仍逐项决定是否可形成实际重要性 claim。",
            "",
            "## 稳健性与审计",
            "",
            "- 已执行 100,000 次、固定种子 141420274 的 matched-block studentized bootstrap。",
            "- 已执行 exact conditional one-sample Wilcoxon signed-rank sensitivity 与 leave-one-block-out 影响诊断。",
            "- 稳健性分析不改变冻结 confirmatory 判定。",
            f"- 统计谬误扫描覆盖：{validation['fallacyScanCoverage']}；复现状态为 ANALYZED（单次正式执行约束下未进行第二次正式数据重跑）。",
            "",
            "## 论文使用边界",
            "",
            "可据本报告逐项表述 C-FF 与 IDFF 的单 CCD worker-scaling 证据，以及在门开启时的双 CCD W16/W8 secondary 证据。不得将跨算法描述性差异改写为排名、赢家或因果硬件机制结论。",
            "",
        ]
    )
    return "\n".join(lines)


def artifact_record(path: Path, root: Path, role: str) -> dict[str, Any]:
    return {
        "role": role,
        "relativePath": path.relative_to(root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def validate_authorization(
    project_root: Path,
    authorization_path: Path,
    expected_authorization_hash: str,
    evidence_root: Path,
    result_root: Path,
) -> dict[str, Any]:
    require(authorization_path.is_file(), "AUTHORIZATION_MISSING")
    require(authorization_path.parent.resolve() == evidence_root.resolve(), "AUTHORIZATION_EVIDENCE_ROOT_MISMATCH")
    require(sha256_file(authorization_path) == expected_authorization_hash.lower(), "AUTHORIZATION_HASH_MISMATCH")
    authorization = load_json(authorization_path)
    require(authorization.get("schema") == "gate14re-mq-formal-analysis-execution-authorization-v1", "AUTHORIZATION_SCHEMA")
    require(authorization.get("status") == "AUTHORIZED_FORMAL_MQ_ANALYSIS_ONLY", "AUTHORIZATION_STATUS")
    require(authorization.get("exactUserAuthorization") == "授权后续工作", "AUTHORIZATION_TEXT")
    scope = authorization.get("scope", {})
    require(scope.get("formalMqAnalysis") is True, "AUTHORIZATION_SCOPE_ANALYSIS")
    require(scope.get("formalSt") is False and scope.get("mt") is False, "AUTHORIZATION_SCOPE_ST_MT")
    require(scope.get("scientificDesignChange") is False, "AUTHORIZATION_SCOPE_DESIGN_CHANGE")
    require(scope.get("algorithmRankingOrWinner") is False, "AUTHORIZATION_SCOPE_RANKING")
    expected_result_root = resolve_inside(project_root, authorization["resultRoot"], "AUTHORIZATION_RESULT_ROOT")
    expected_evidence_root = resolve_inside(project_root, authorization["evidenceRoot"], "AUTHORIZATION_EVIDENCE_ROOT")
    require(expected_result_root == result_root.resolve(), "AUTHORIZATION_RESULT_ROOT_MISMATCH")
    require(expected_evidence_root == evidence_root.resolve(), "AUTHORIZATION_EVIDENCE_ROOT_MISMATCH")
    analyzer_binding = authorization["analyzer"]
    analyzer_path = verify_bound_file(project_root, analyzer_binding, "ANALYZER")
    require(analyzer_path.resolve() == Path(__file__).resolve(), "ANALYZER_SELF_PATH_MISMATCH")
    verify_bound_file(project_root, authorization["analysisContract"], "ANALYSIS_CONTRACT")
    verify_bound_file(project_root, authorization["implementationManifest"], "IMPLEMENTATION_MANIFEST")
    verify_bound_file(project_root, authorization["readinessReceipt"], "READINESS_RECEIPT")
    return authorization


def preflight(
    project_root: Path,
    authorization: Mapping[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, str], Path]:
    inputs = authorization["frozenInputs"]
    collection_terminal_path = verify_bound_file(project_root, inputs["collectionTerminalReceipt"], "COLLECTION_TERMINAL")
    collection_seal_path = verify_bound_file(project_root, inputs["collectionFinalEvidenceSeal"], "COLLECTION_FINAL_SEAL")
    acquisition_complete_path = verify_bound_file(project_root, inputs["acquisitionComplete"], "ACQUISITION_COMPLETE")
    acquisition_manifest_path = verify_bound_file(project_root, inputs["acquisitionFreezeManifest"], "ACQUISITION_MANIFEST")
    schedule_path = verify_bound_file(project_root, inputs["formalSchedule"], "FORMAL_SCHEDULE")
    identity_path = verify_bound_file(project_root, inputs["identityMap"], "IDENTITY_MAP")
    verify_bound_file(project_root, inputs["scientificAndAnalysisContract"], "SCIENTIFIC_CONTRACT")
    verify_bound_file(project_root, inputs["authorizedDesign"], "AUTHORIZED_DESIGN")
    collection_terminal = load_json(collection_terminal_path)
    collection_seal = load_json(collection_seal_path)
    validate_collection_terminal(collection_terminal, collection_seal)
    acquisition_complete = load_json(acquisition_complete_path)
    require(acquisition_complete.get("status") == "PASS_RAW_FORMAL_MQ_COLLECTION_COMPLETE_ANALYSIS_NOT_STARTED", "ACQUISITION_COMPLETE_STATUS")
    require(acquisition_complete.get("formalAnalysisStarted") is False, "ACQUISITION_COMPLETE_ANALYSIS_STARTED")
    require(int(acquisition_complete.get("completedFreshUnityProcesses", -1)) == EXPECTED_PROCESSES, "ACQUISITION_COMPLETE_COUNT")
    measured_root = resolve_inside(project_root, inputs["measuredRoot"], "MEASURED_ROOT_PATH")
    require(measured_root.is_dir(), "MEASURED_ROOT_MISSING")
    acquisition_audit = verify_acquisition_manifest(measured_root, acquisition_manifest_path)
    schedule_rows = verify_schedule(schedule_path)
    identity_document = load_json(identity_path)
    require(identity_document.get("schema") == "gate14re-mq-formal-opaque-algorithm-identity-map-v2", "IDENTITY_MAP_SCHEMA")
    identity = {
        str(row["opaqueAlgorithmSlot"]): str(row["algorithmId"])
        for row in identity_document.get("algorithms", [])
    }
    require(identity == {"OPAQUE-A": "C-FF", "OPAQUE-B": "IDFF"}, "IDENTITY_MAP_CONTENT")
    return acquisition_audit, schedule_rows, identity, measured_root


def formal_run(args: argparse.Namespace) -> dict[str, Any]:
    project_root = Path(args.project_root).resolve()
    evidence_root = Path(args.evidence_root).resolve()
    result_root = Path(args.result_root).resolve()
    authorization_path = Path(args.authorization).resolve()
    require(project_root.is_dir(), "PROJECT_ROOT_MISSING")
    require(evidence_root.is_dir(), "EVIDENCE_ROOT_MISSING")
    require(not result_root.exists(), "RESULT_ROOT_ALREADY_EXISTS", str(result_root))
    authorization = validate_authorization(
        project_root,
        authorization_path,
        args.authorization_sha256,
        evidence_root,
        result_root,
    )
    started_at = utc_now()
    acquisition_audit, schedule_rows, identity, measured_root = preflight(project_root, authorization)
    preanalysis_audit = {
        "schema": "gate14re-mq-formal-preanalysis-audit-v1",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "authorizationId": authorization["authorizationId"],
        "status": "PASS_PREANALYSIS_ALL_FROZEN_INPUTS_VERIFIED_OUTCOME_VALUES_NOT_YET_PARSED",
        "auditedAtUtc": utc_now(),
        "authorizationSha256": args.authorization_sha256.lower(),
        "acquisitionFreezeAudit": acquisition_audit,
        "scheduleRows": len(schedule_rows),
        "matchedBlocks": EXPECTED_BLOCKS,
        "identityMapSlotsVerified": sorted(identity),
        "batchOutcomeFilesParsedAtAuditTime": 0,
        "laneObservationValuesParsed": False,
        "formalStStarted": False,
        "mtStarted": False,
    }
    preanalysis_path = evidence_root / "preanalysis-audit.v1.json"
    write_json(preanalysis_path, preanalysis_audit)
    result_root.mkdir(parents=True, exist_ok=False)

    data, structural_rows = load_and_validate_batches(measured_root, schedule_rows)
    block_rows, block_ids, values = compute_block_estimands(data, identity)
    confirmatory = apply_inference(values, identity)
    condition_summary = condition_summaries(data, identity)
    exploratory = descriptive_exploratory(data, values, block_ids, identity)
    sensitivity = sensitivity_results(values, block_ids)
    validation = statistical_validation(confirmatory)

    output_paths: list[tuple[Path, str]] = []
    block_path = result_root / "block-estimands.v1.jsonl"
    atomic_create(block_path, canonical_jsonl_bytes(block_rows))
    output_paths.append((block_path, "matched-block-estimands"))
    confirmatory_path = result_root / "confirmatory-and-secondary-results.v1.json"
    write_json(confirmatory_path, confirmatory)
    output_paths.append((confirmatory_path, "confirmatory-and-gated-secondary-results"))
    condition_path = result_root / "descriptive-condition-summaries.v1.json"
    write_json(condition_path, condition_summary)
    output_paths.append((condition_path, "descriptive-condition-summaries"))
    exploratory_path = result_root / "descriptive-and-exploratory-results.v1.json"
    write_json(exploratory_path, exploratory)
    output_paths.append((exploratory_path, "descriptive-and-exploratory-results"))
    sensitivity_path = result_root / "sensitivity-analysis.v1.json"
    write_json(sensitivity_path, sensitivity)
    output_paths.append((sensitivity_path, "sensitivity-analysis"))
    validation_path = result_root / "statistical-validation.v1.json"
    write_json(validation_path, validation)
    output_paths.append((validation_path, "statistical-validation"))
    structural_path = result_root / "structural-input-index.v1.json"
    write_json(
        structural_path,
        {
            "schema": "gate14re-mq-formal-analysis-structural-input-index-v1",
            "studyId": STUDY_ID,
            "rows": structural_rows,
            "batchOutcomeValuesIncluded": False,
            "laneObservationValuesParsed": False,
        },
    )
    output_paths.append((structural_path, "structural-input-index-without-outcome-values"))
    report_path = result_root / "formal-mq-analysis-report.zh-CN.v1.md"
    atomic_create(report_path, build_report(authorization["authorizationId"], confirmatory, validation).encode("utf-8"))
    output_paths.append((report_path, "human-readable-formal-analysis-report"))

    manifest_path = result_root / "analysis-manifest.v1.json"
    manifest = {
        "schema": "gate14re-mq-formal-analysis-manifest-v1",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "authorizationId": authorization["authorizationId"],
        "status": "FROZEN_FORMAL_MQ_ANALYSIS_OUTPUTS",
        "createdAtUtc": utc_now(),
        "artifactCount": len(output_paths),
        "artifacts": [artifact_record(path, result_root, role) for path, role in output_paths],
        "formalStStarted": False,
        "mtStarted": False,
        "algorithmRankingOrWinner": False,
    }
    write_json(manifest_path, manifest)

    terminal_path = evidence_root / "analysis-terminal-receipt.v1.json"
    terminal = {
        "schema": "gate14re-mq-formal-analysis-terminal-receipt-v1",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "authorizationId": authorization["authorizationId"],
        "status": "PASS_FORMAL_MQ_ANALYSIS_TERMINAL",
        "startedAtUtc": started_at,
        "terminalAtUtc": utc_now(),
        "authorizationSha256": args.authorization_sha256.lower(),
        "preanalysisAuditSha256": sha256_file(preanalysis_path),
        "analysisManifestSha256": sha256_file(manifest_path),
        "resultRoot": result_root.relative_to(project_root).as_posix(),
        "matchedBlocks": EXPECTED_BLOCKS,
        "processesStructurallyBound": EXPECTED_PROCESSES,
        "laneObservationValuesParsed": False,
        "primaryGateForSecondariesOpen": confirmatory["primaryGateForSecondariesOpen"],
        "primaryClaimsPassed": [
            row["hypothesisId"]
            for row in confirmatory["results"]
            if row.get("confirmatoryClaimPassed") is True
        ],
        "keySecondaryClaimsPassed": [
            row["hypothesisId"]
            for row in confirmatory["results"]
            if row.get("keySecondaryClaimPassed") is True
        ],
        "formalStStarted": False,
        "mtStarted": False,
        "algorithmRankingOrWinner": False,
    }
    write_json(terminal_path, terminal)

    seal_path = evidence_root / "final-evidence-seal-manifest.v1.json"
    evidence_artifacts = [
        artifact_record(authorization_path, project_root, "analysis-execution-authorization"),
        artifact_record(preanalysis_path, project_root, "preanalysis-audit"),
        artifact_record(terminal_path, project_root, "analysis-terminal-receipt"),
        artifact_record(manifest_path, project_root, "analysis-output-manifest"),
    ]
    seal = {
        "schema": "gate14re-mq-formal-analysis-final-evidence-seal-v1",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "authorizationId": authorization["authorizationId"],
        "status": "SEALED_FORMAL_MQ_ANALYSIS_TERMINAL_PASS",
        "sealedAtUtc": utc_now(),
        "evidenceRoot": evidence_root.relative_to(project_root).as_posix(),
        "resultRoot": result_root.relative_to(project_root).as_posix(),
        "artifactCount": len(evidence_artifacts),
        "artifacts": evidence_artifacts,
        "analysisManifestArtifactsVerified": len(manifest["artifacts"]),
        "formalMqAnalysisComplete": True,
        "formalStStarted": False,
        "mtStarted": False,
        "algorithmRankingOrWinner": False,
    }
    write_json(seal_path, seal)
    return {
        "status": terminal["status"],
        "authorizationId": authorization["authorizationId"],
        "resultRoot": str(result_root),
        "evidenceRoot": str(evidence_root),
        "primaryGateForSecondariesOpen": confirmatory["primaryGateForSecondariesOpen"],
        "primaryClaimsPassed": terminal["primaryClaimsPassed"],
        "keySecondaryClaimsPassed": terminal["keySecondaryClaimsPassed"],
        "analysisManifestSha256": sha256_file(manifest_path),
        "terminalReceiptSha256": sha256_file(terminal_path),
        "finalEvidenceSealSha256": sha256_file(seal_path),
    }


def self_test() -> dict[str, Any]:
    require(abs(t_cdf(0.0, 35.0) - 0.5) < 1e-15, "SELFTEST_T_CDF_ZERO")
    require(abs(t_ppf(0.95, 35.0) - 1.689572457780265) < 1e-9, "SELFTEST_T_PPF")
    adjusted = holm_adjust([0.01, 0.03, 0.04, 0.20])
    require(all(abs(a - b) < 1e-15 for a, b in zip(adjusted, [0.04, 0.09, 0.09, 0.20])), "SELFTEST_HOLM")
    seconds = {worker: math.exp(2.0 - 0.1 * math.log2(worker)) for worker in (1, 2, 4, 8)}
    require(abs(equal_weight_slope(seconds) + 0.1) < 1e-14, "SELFTEST_SLOPE")
    signed_rank = exact_signed_rank_lower_p([-1.0, -2.0, -3.0, -4.0, -5.0])
    require(abs(signed_rank["exactLowerTailP"] - 1.0 / 32.0) < 1e-15, "SELFTEST_SIGNED_RANK")
    matrix = np.asarray(
        [[-0.1 * (row + 1) + 0.01 * column for column in range(6)] for row in range(8)],
        dtype=np.float64,
    )
    first = studentized_bootstrap(matrix, 2_000, 12345, ALL_HYPOTHESIS_IDS)
    second = studentized_bootstrap(matrix, 2_000, 12345, ALL_HYPOTHESIS_IDS)
    require(canonical_json_bytes(first) == canonical_json_bytes(second), "SELFTEST_BOOTSTRAP_DETERMINISM")
    return {
        "schema": "gate14re-mq-formal-analysis-self-test-v1",
        "status": "PASS",
        "checked": [
            "Student-t CDF and quantile",
            "Holm adjustment",
            "equal-weight log2-worker slope",
            "exact signed-rank lower tail",
            "PCG64 studentized-bootstrap determinism",
        ],
        "pythonVersion": sys.version.split()[0],
        "numpyVersion": np.__version__,
    }


def write_failure_receipt(
    evidence_root: Path | None,
    error: BaseException,
    args: argparse.Namespace,
) -> None:
    if evidence_root is None or not evidence_root.exists():
        return
    path = evidence_root / "failure-receipt.v1.json"
    if path.exists():
        return
    payload = {
        "schema": "gate14re-mq-formal-analysis-failure-receipt-v1",
        "studyId": STUDY_ID,
        "status": "FAIL_CLOSED_FORMAL_MQ_ANALYSIS_ATTEMPT",
        "failedAtUtc": utc_now(),
        "errorType": type(error).__name__,
        "errorCode": error.code if isinstance(error, AnalysisError) else None,
        "errorDetail": str(error),
        "resultRoot": getattr(args, "result_root", None),
        "retryWithinSameAttemptAuthorized": False,
        "formalStStarted": False,
        "mtStarted": False,
    }
    try:
        write_json(path, payload)
    except Exception:
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--project-root")
    parser.add_argument("--authorization")
    parser.add_argument("--authorization-sha256")
    parser.add_argument("--evidence-root")
    parser.add_argument("--result-root")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        print(json.dumps(self_test(), ensure_ascii=False, sort_keys=True, indent=2))
        return 0
    required = (
        args.project_root,
        args.authorization,
        args.authorization_sha256,
        args.evidence_root,
        args.result_root,
    )
    require(all(required), "MISSING_FORMAL_ARGUMENT")
    project_root = Path(args.project_root).resolve()
    evidence_root = Path(args.evidence_root).resolve()
    result_root = Path(args.result_root).resolve()
    authorization = validate_authorization(
        project_root,
        Path(args.authorization).resolve(),
        args.authorization_sha256,
        evidence_root,
        result_root,
    )
    if args.preflight_only:
        acquisition_audit, schedule_rows, identity, measured_root = preflight(project_root, authorization)
        print(
            json.dumps(
                {
                    "schema": "gate14re-mq-formal-analysis-preflight-only-v1",
                    "status": "PASS_NO_BATCH_OUTCOME_VALUES_PARSED",
                    "acquisitionAudit": acquisition_audit,
                    "scheduleRows": len(schedule_rows),
                    "identitySlots": sorted(identity),
                    "measuredRoot": str(measured_root),
                    "batchOutcomeValuesParsed": False,
                    "laneObservationValuesParsed": False,
                },
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
            )
        )
        return 0
    result = formal_run(args)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    evidence: Path | None = None
    parsed: argparse.Namespace | None = None
    try:
        parsed = parse_args()
        if parsed.self_test:
            print(json.dumps(self_test(), ensure_ascii=False, sort_keys=True, indent=2))
            raise SystemExit(0)
        required_values = (
            parsed.project_root,
            parsed.authorization,
            parsed.authorization_sha256,
            parsed.evidence_root,
            parsed.result_root,
        )
        require(all(required_values), "MISSING_FORMAL_ARGUMENT")
        evidence = Path(parsed.evidence_root).resolve()
        project = Path(parsed.project_root).resolve()
        result_path = Path(parsed.result_root).resolve()
        authorization_document = validate_authorization(
            project,
            Path(parsed.authorization).resolve(),
            parsed.authorization_sha256,
            evidence,
            result_path,
        )
        if parsed.preflight_only:
            audit, schedule, identity_mapping, measured = preflight(project, authorization_document)
            print(
                json.dumps(
                    {
                        "schema": "gate14re-mq-formal-analysis-preflight-only-v1",
                        "status": "PASS_NO_BATCH_OUTCOME_VALUES_PARSED",
                        "acquisitionAudit": audit,
                        "scheduleRows": len(schedule),
                        "identitySlots": sorted(identity_mapping),
                        "measuredRoot": str(measured),
                        "batchOutcomeValuesParsed": False,
                        "laneObservationValuesParsed": False,
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                    indent=2,
                )
            )
            raise SystemExit(0)
        print(json.dumps(formal_run(parsed), ensure_ascii=False, sort_keys=True, indent=2))
        raise SystemExit(0)
    except SystemExit:
        raise
    except BaseException as error:
        if parsed is not None:
            write_failure_receipt(evidence, error, parsed)
        print(f"FORMAL_ANALYSIS_FAILED: {error}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        raise SystemExit(1)
