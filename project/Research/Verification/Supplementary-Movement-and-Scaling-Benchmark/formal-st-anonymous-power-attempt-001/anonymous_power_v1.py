#!/usr/bin/env python3
"""Prospective identity-blind nuisance-covariance power calculation for Gate14Re-ME.

This program intentionally never reads algorithmId or an identity mapping. It does
not serialize fitted coefficients, endpoint means, observed effects, directions,
ranks, weights, or a winner. Qualification observations are used only to estimate
an anonymous nuisance covariance for a predeclared power calculation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import stat
import sys
import traceback
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import NormalDist
from typing import Any, Iterable

import numpy as np
import pyarrow.parquet as pq


SCHEMA_VERSION = "gate14re-me-formal-st-anonymous-power-v1"
EXPECTED_HASHES = {
    "qualificationTerminalPass": "9ffc2c83896f1516eea969619ccc8c07f6be1bdab85cecead7224fc8f9cbeafa",
    "eventGroups": "d5ad31fcf9070399595ee628e7f6d17f13ef3bace9d8cc2575f757ef8860d8fe",
    "d3Windows": "be75d15e407e46845ed1b0209066da6adf853b2f90efc4a9068b6b7f6f87d7ea",
    "persistentState": "fdd051cd357d00d2db420b557e124d73a5dc1f719c5d0c95bdad22fd542c7ff3",
    "schedule": "8786f687a142900c0cf609817bbc1da957ec3ee9e09d12549e886fb892f026cb",
    "runtimePrediction": "2fd23a2c96ce5a743c8551466a2b9984639780c624ba802514cd09070c1e7f9f",
}
EXPECTED_CORE_SUPERBLOCKS = 108
EXPECTED_CORE_LANES = 648
EXPECTED_CORE_EVENT_GROUPS = 15552
EXPECTED_LANES_PER_SUPERBLOCK = 6
EXPECTED_EVENT_GROUPS_PER_LANE = 24
EXPECTED_CELLS = 36
EXPECTED_QUALIFICATION_B_PER_CELL = 3
OPAQUE_LABELS = tuple(f"ALG-{x}" for x in "ABCDEF")
CANDIDATE_B = (36, 72, 108, 144)
MIPE_LOG_RATIO = math.log(0.90)
ALPHA = 0.05
TARGET_POWER = 0.90
MONTE_CARLO_DRAWS = 200_000
MONTE_CARLO_BATCH = 20_000
BASE_SEED = 141_402_026
GENERATED_FILES = {
    "anonymous-structural-schedule.v1.jsonl",
    "input-inventory.v1.jsonl",
    "nuisance-summary.v1.json",
    "power-result.v1.json",
    "terminal-receipt.v1.json",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def make_read_only(path: Path) -> None:
    mode = path.stat().st_mode
    path.chmod(mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)


def write_json(path: Path, value: Any) -> None:
    if path.exists():
        raise RuntimeError(f"refusing to overwrite existing output: {path.name}")
    path.write_bytes(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8") + b"\n")
    make_read_only(path)


def write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    if path.exists():
        raise RuntimeError(f"refusing to overwrite existing output: {path.name}")
    with path.open("wb") as handle:
        for row in rows:
            handle.write(canonical_json_bytes(row))
    make_read_only(path)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def finite_float(value: Any, field: str) -> float:
    result = float(value)
    require(math.isfinite(result), f"non-finite {field}")
    return result


def positive_float(value: Any, field: str) -> float:
    result = finite_float(value, field)
    require(result > 0.0, f"non-positive {field}")
    return result


def nonnegative_int(value: Any, field: str) -> int:
    result = int(value)
    require(result >= 0, f"negative {field}")
    return result


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def verify_hash(path: Path, expected: str, label: str) -> dict[str, Any]:
    require(path.is_file(), f"missing required input {label}: {path}")
    actual = sha256_file(path)
    require(actual == expected, f"SHA-256 mismatch for {label}: expected {expected}, got {actual}")
    return {
        "schema": "gate14re-me-formal-st-power-input-inventory-row-v1",
        "label": label,
        "relativePath": None,
        "bytes": path.stat().st_size,
        "sha256": actual,
    }


def verify_pre_execution_freeze(output_root: Path) -> list[dict[str, Any]]:
    manifest_path = output_root / "pre-execution-freeze-manifest.v1.json"
    require(manifest_path.is_file(), "missing pre-execution freeze manifest")
    manifest = load_json(manifest_path)
    require(manifest.get("schema") == "gate14re-me-formal-st-anonymous-power-pre-execution-freeze-manifest-v1", "unexpected freeze manifest schema")
    rows = manifest.get("files")
    require(isinstance(rows, list) and rows, "empty freeze manifest")
    verified: list[dict[str, Any]] = []
    for row in rows:
        rel = str(row["relativePath"])
        path = output_root / rel
        require(path.is_file(), f"frozen file missing: {rel}")
        actual = sha256_file(path)
        require(actual == row["sha256"], f"frozen file hash mismatch: {rel}")
        require(path.stat().st_size == int(row["bytes"]), f"frozen file size mismatch: {rel}")
        verified.append({"relativePath": rel, "bytes": path.stat().st_size, "sha256": actual})
    return verified


def sanitize_schedule(schedule_path: Path, output_path: Path) -> tuple[dict[str, tuple[str, ...]], list[dict[str, Any]]]:
    schedule_map: dict[str, tuple[str, ...]] = {}
    sanitized_rows: list[dict[str, Any]] = []
    ordinals: list[int] = []
    with schedule_path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            # Deliberately access only the prospectively allowed structural keys.
            ordinal = int(row["ordinal"])
            superblock_id = str(row["superblockId"])
            order_container = row["algorithmOrder"]
            anonymous_order = tuple(str(entry["anonymousLaneId"]) for entry in order_container)
            require(len(anonymous_order) == EXPECTED_LANES_PER_SUPERBLOCK, f"schedule lane count mismatch at line {line_number}")
            require(len(set(anonymous_order)) == EXPECTED_LANES_PER_SUPERBLOCK, f"duplicate anonymous lane at line {line_number}")
            require(set(anonymous_order) == set(OPAQUE_LABELS), f"unexpected anonymous lane set at line {line_number}")
            require(superblock_id not in schedule_map, f"duplicate schedule superblock {superblock_id}")
            schedule_map[superblock_id] = anonymous_order
            ordinals.append(ordinal)
            sanitized_rows.append({
                "schema": "gate14re-me-anonymous-structural-schedule-row-v1",
                "ordinal": ordinal,
                "superblockId": superblock_id,
                "anonymousLaneOrder": list(anonymous_order),
            })
    require(ordinals == list(range(len(ordinals))), "schedule ordinals are not unique and strictly consecutive from zero")
    require(len(schedule_map) == 126, f"expected 126 qualification superblocks, got {len(schedule_map)}")
    write_jsonl(output_path, sanitized_rows)
    return schedule_map, sanitized_rows


def read_event_lane_summaries(event_path: Path, schedule_map: dict[str, tuple[str, ...]]) -> tuple[list[dict[str, Any]], dict[str, Any], set[str]]:
    columns = [
        "superblockId", "designRegion", "anonymousLaneId", "gridEdge", "agentCount",
        "changedCellCount", "changeTopology", "graphProfile", "sameTickAtomicPartitions",
        "contextStratumId", "eventGroupIndex", "eventGroupElapsedMilliseconds",
        "d3WindowRecordId", "d3CounterValid", "gridAccessorCallsTotal", "eligible",
        "finitePositiveElapsed", "counterValid",
    ]
    table = pq.read_table(event_path, columns=columns)
    require(table.num_rows == 18_144, f"event-group delivery row count mismatch: {table.num_rows}")
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    region_counts: dict[str, int] = defaultdict(int)
    for row in table.to_pylist():
        region = str(row["designRegion"]).strip()
        region_counts[region] += 1
        if "core" not in region.casefold():
            continue
        sb = str(row["superblockId"])
        lane = str(row["anonymousLaneId"])
        require(sb in schedule_map, f"event superblock absent from sanitized schedule: {sb}")
        require(lane in OPAQUE_LABELS, f"unexpected anonymous lane label: {lane}")
        grouped[(sb, lane)].append(row)
    require(sum(len(v) for v in grouped.values()) == EXPECTED_CORE_EVENT_GROUPS, "core event-group cardinality mismatch")
    require(len(grouped) == EXPECTED_CORE_LANES, "core lane cardinality mismatch")
    core_superblocks = {key[0] for key in grouped}
    require(len(core_superblocks) == EXPECTED_CORE_SUPERBLOCKS, "core superblock cardinality mismatch")
    core_d3_ids: set[str] = set()
    summaries: list[dict[str, Any]] = []
    cells_to_superblocks: dict[tuple[int, int, int], set[str]] = defaultdict(set)
    context_level_sets: dict[str, set[Any]] = {
        "changeTopology": set(),
        "graphProfile": set(),
        "sameTickAtomicPartitions": set(),
    }
    for (sb, lane), rows in sorted(grouped.items()):
        rows.sort(key=lambda item: int(item["eventGroupIndex"]))
        require(len(rows) == EXPECTED_EVENT_GROUPS_PER_LANE, f"event-group count mismatch for {sb}/{lane}")
        require([int(x["eventGroupIndex"]) for x in rows] == list(range(EXPECTED_EVENT_GROUPS_PER_LANE)), f"event-group ordinal mismatch for {sb}/{lane}")
        structural_fields = (
            "gridEdge", "agentCount", "changedCellCount", "changeTopology",
            "graphProfile", "sameTickAtomicPartitions", "contextStratumId",
        )
        for field in structural_fields:
            require(len({x[field] for x in rows}) == 1, f"within-lane {field} mismatch for {sb}/{lane}")
        elapsed: list[float] = []
        accesses: list[float] = []
        d3_ids: list[str] = []
        for row in rows:
            require(bool(row["eligible"]), f"ineligible core event group for {sb}/{lane}")
            require(bool(row["finitePositiveElapsed"]), f"invalid elapsed gate for {sb}/{lane}")
            require(bool(row["counterValid"]) and bool(row["d3CounterValid"]), f"invalid counter gate for {sb}/{lane}")
            elapsed.append(positive_float(row["eventGroupElapsedMilliseconds"], "eventGroupElapsedMilliseconds"))
            accesses.append(positive_float(row["gridAccessorCallsTotal"], "gridAccessorCallsTotal"))
            record_id = str(row["d3WindowRecordId"])
            require(record_id, f"empty d3WindowRecordId for {sb}/{lane}")
            require(record_id not in core_d3_ids, f"duplicate d3WindowRecordId {record_id}")
            core_d3_ids.add(record_id)
            d3_ids.append(record_id)
        sorted_elapsed = sorted(elapsed)
        p95_index = math.ceil(0.95 * len(sorted_elapsed)) - 1
        G = int(rows[0]["gridEdge"])
        N = int(rows[0]["agentCount"])
        F = int(rows[0]["changedCellCount"])
        require(G > 0 and N > 0 and F > 0, f"non-positive G/N/F for {sb}/{lane}")
        cell = (G, N, F)
        cells_to_superblocks[cell].add(sb)
        context = {
            "changeTopology": str(rows[0]["changeTopology"]),
            "graphProfile": str(rows[0]["graphProfile"]),
            "sameTickAtomicPartitions": int(rows[0]["sameTickAtomicPartitions"]),
        }
        for key, value in context.items():
            context_level_sets[key].add(value)
        anonymous_order = schedule_map[sb]
        require(lane in anonymous_order, f"lane absent from sanitized schedule order for {sb}/{lane}")
        summaries.append({
            "superblockId": sb,
            "anonymousLaneId": lane,
            "executionPosition": anonymous_order.index(lane) + 1,
            "G": G,
            "N": N,
            "F": F,
            **context,
            "d1GeometricMeanLog": float(np.mean(np.log(np.asarray(elapsed, dtype=np.float64)))),
            "d1P95Log": math.log(sorted_elapsed[p95_index]),
            "d2LogGeometricMean": float(np.mean(np.log(np.asarray(accesses, dtype=np.float64)))),
            "d3WindowRecordIds": d3_ids,
        })
    require(len(cells_to_superblocks) == EXPECTED_CELLS, f"expected 36 core GxNxF cells, got {len(cells_to_superblocks)}")
    require(all(len(value) == EXPECTED_QUALIFICATION_B_PER_CELL for value in cells_to_superblocks.values()), "core cell does not contain exactly three independent superblocks")
    require({x[0] for x in cells_to_superblocks} == {64, 96, 128}, "unexpected G levels")
    require({x[1] for x in cells_to_superblocks} == {32, 64, 128}, "unexpected N levels")
    require({x[2] for x in cells_to_superblocks} == {1, 9, 25, 81}, "unexpected F levels")
    structure = {
        "deliveredEventGroupRows": int(table.num_rows),
        "designRegionRowCounts": dict(sorted(region_counts.items())),
        "coreEventGroupRows": EXPECTED_CORE_EVENT_GROUPS,
        "coreLanes": len(summaries),
        "coreSuperblocks": len(core_superblocks),
        "coreCells": len(cells_to_superblocks),
        "coreSuperblocksPerCell": EXPECTED_QUALIFICATION_B_PER_CELL,
        "contextLevelCardinality": {key: len(value) for key, value in sorted(context_level_sets.items())},
    }
    return summaries, structure, core_d3_ids


def attach_d3(summaries: list[dict[str, Any]], d3_path: Path, expected_ids: set[str]) -> dict[str, Any]:
    columns = [
        "recordId", "superblockId", "anonymousLaneId", "measurementScope",
        "eventGroupIndex", "managedAllocationBytes", "counterValid",
    ]
    table = pq.read_table(d3_path, columns=columns)
    record_map: dict[str, dict[str, Any]] = {}
    for row in table.to_pylist():
        record_id = str(row["recordId"])
        if record_id not in expected_ids:
            continue
        require(record_id not in record_map, f"duplicate joined D3 recordId {record_id}")
        require("event" in str(row["measurementScope"]).casefold(), f"unexpected D3 measurement scope for {record_id}")
        require(bool(row["counterValid"]), f"invalid D3 counter for {record_id}")
        record_map[record_id] = row
    require(set(record_map) == expected_ids, "D3 join coverage mismatch")
    for summary in summaries:
        total = 0
        for expected_index, record_id in enumerate(summary.pop("d3WindowRecordIds")):
            row = record_map[record_id]
            require(str(row["superblockId"]) == summary["superblockId"], f"D3 superblock mismatch for {record_id}")
            require(str(row["anonymousLaneId"]) == summary["anonymousLaneId"], f"D3 anonymous lane mismatch for {record_id}")
            require(int(row["eventGroupIndex"]) == expected_index, f"D3 event-group ordinal mismatch for {record_id}")
            total += nonnegative_int(row["managedAllocationBytes"], "managedAllocationBytes")
        summary["d3Log1pTotal"] = math.log1p(total)
    return {
        "deliveredD3Rows": int(table.num_rows),
        "joinedCoreD3Rows": len(record_map),
        "joinCoverage": "COMPLETE",
    }


def attach_d4(summaries: list[dict[str, Any]], persistent_path: Path) -> dict[str, Any]:
    columns = [
        "superblockId", "anonymousLaneId", "measurementPointId", "eventGroupIndex",
        "persistentStateBytesTotal", "valid",
    ]
    table = pq.read_table(persistent_path, columns=columns)
    core_keys = {(x["superblockId"], x["anonymousLaneId"]) for x in summaries}
    values: dict[tuple[str, str], list[int]] = defaultdict(list)
    row_counts: dict[tuple[str, str], int] = defaultdict(int)
    for row in table.to_pylist():
        key = (str(row["superblockId"]), str(row["anonymousLaneId"]))
        if key not in core_keys:
            continue
        row_counts[key] += 1
        require(bool(row["valid"]), f"invalid persistent-state row for {key[0]}/{key[1]}")
        values[key].append(nonnegative_int(row["persistentStateBytesTotal"], "persistentStateBytesTotal"))
    require(set(values) == core_keys, "persistent-state core lane coverage mismatch")
    require(all(values[key] for key in core_keys), "empty persistent-state measurement set")
    for summary in summaries:
        key = (summary["superblockId"], summary["anonymousLaneId"])
        summary["d4Log1pMax"] = math.log1p(max(values[key]))
    return {
        "deliveredPersistentStateRows": int(table.num_rows),
        "joinedCorePersistentStateRows": sum(row_counts.values()),
        "coreLaneCoverage": len(values),
        "joinCoverage": "COMPLETE",
    }


def build_design(summaries: list[dict[str, Any]]) -> tuple[np.ndarray, np.ndarray, list[str], list[str], dict[str, Any]]:
    summaries.sort(key=lambda x: (x["superblockId"], int(x["executionPosition"])))
    labels = sorted({str(x["anonymousLaneId"]) for x in summaries})
    require(tuple(labels) == OPAQUE_LABELS, "unexpected opaque label set")
    cells = sorted({(int(x["G"]), int(x["N"]), int(x["F"])) for x in summaries})
    require(len(cells) == EXPECTED_CELLS, "design cell count changed during matrix construction")
    centers = {
        "N": float(np.mean([math.log2(cell[1]) for cell in cells])),
        "F": float(np.mean([math.log2(cell[2]) for cell in cells])),
        "G2": float(np.mean([math.log2(cell[0] * cell[0]) for cell in cells])),
    }
    categorical_fields = ["changeTopology", "graphProfile", "sameTickAtomicPartitions", "executionPosition"]
    levels = {field: sorted({x[field] for x in summaries}, key=lambda value: str(value)) for field in categorical_fields}
    columns: list[str] = []
    label_column: dict[tuple[str, str], int] = {}
    for label in labels:
        for term in ("intercept", "log2N", "log2F", "log2G2"):
            label_column[(label, term)] = len(columns)
            columns.append(f"opaque[{label}]:{term}")
    categorical_columns: dict[tuple[str, Any], int] = {}
    for field in categorical_fields:
        require(len(levels[field]) >= 2, f"factor {field} has fewer than two levels")
        for level in levels[field][1:]:
            categorical_columns[(field, level)] = len(columns)
            columns.append(f"shared:{field}[{level}]")
    X = np.zeros((len(summaries), len(columns)), dtype=np.float64)
    response_fields = ["d1GeometricMeanLog", "d1P95Log", "d2LogGeometricMean", "d3Log1pTotal", "d4Log1pMax"]
    Y = np.empty((len(summaries), len(response_fields)), dtype=np.float64)
    clusters: list[str] = []
    for i, row in enumerate(summaries):
        label = str(row["anonymousLaneId"])
        X[i, label_column[(label, "intercept")]] = 1.0
        X[i, label_column[(label, "log2N")]] = math.log2(int(row["N"])) - centers["N"]
        X[i, label_column[(label, "log2F")]] = math.log2(int(row["F"])) - centers["F"]
        X[i, label_column[(label, "log2G2")]] = math.log2(int(row["G"]) ** 2) - centers["G2"]
        for field in categorical_fields:
            value = row[field]
            if value != levels[field][0]:
                X[i, categorical_columns[(field, value)]] = 1.0
        for j, field in enumerate(response_fields):
            Y[i, j] = finite_float(row[field], field)
        clusters.append(str(row["superblockId"]))
    require(np.isfinite(X).all() and np.isfinite(Y).all(), "non-finite design or response matrix")
    rank = int(np.linalg.matrix_rank(X))
    require(rank == X.shape[1], f"design matrix is rank deficient: rank {rank}, columns {X.shape[1]}")
    design_meta = {
        "rows": int(X.shape[0]),
        "columns": int(X.shape[1]),
        "rank": rank,
        "independentClusters": len(set(clusters)),
        "opaqueLabels": labels,
        "axisCenters": centers,
        "factorLevelCardinality": {field: len(levels[field]) for field in categorical_fields},
        "responseCount": int(Y.shape[1]),
        "responseNames": ["D1_GEOMETRIC_MEAN", "D1_P95", "D2", "D3", "D4"],
    }
    return X, Y, clusters, columns, design_meta


def clustered_multivariate_covariance(X: np.ndarray, Y: np.ndarray, clusters: list[str]) -> tuple[np.ndarray, dict[str, Any]]:
    n, p = X.shape
    q = Y.shape[1]
    unique_clusters = sorted(set(clusters))
    g = len(unique_clusters)
    require(g > p, f"insufficient independent clusters for frozen nuisance model: clusters={g}, rank={p}")
    xtx_inv = np.linalg.inv(X.T @ X)
    coefficients = xtx_inv @ X.T @ Y
    residuals = Y - X @ coefficients
    meat = np.zeros((p * q, p * q), dtype=np.float64)
    cluster_array = np.asarray(clusters, dtype=object)
    for cluster in unique_clusters:
        mask = cluster_array == cluster
        score = X[mask].T @ residuals[mask]
        score_vector = np.asarray(score, dtype=np.float64).reshape(-1, order="F")
        meat += np.outer(score_vector, score_vector)
    bread = np.kron(np.eye(q, dtype=np.float64), xtx_inv)
    cr1 = (g / (g - 1.0)) * ((n - 1.0) / (n - p))
    covariance = cr1 * (bread @ meat @ bread.T)
    covariance = (covariance + covariance.T) / 2.0
    require(np.isfinite(covariance).all(), "non-finite clustered covariance")
    diagonal = np.diag(covariance)
    require(np.all(diagonal > 0.0), "non-positive clustered covariance diagonal")
    # Coefficients and residuals are intentionally not serialized.
    covariance_hash = sha256_bytes(np.asarray(covariance, dtype="<f8").tobytes(order="C"))
    del coefficients, residuals, meat, bread
    return covariance, {
        "estimator": "multivariate OLS superblock-clustered CR1 sandwich",
        "cr1Factor": cr1,
        "coefficientCovarianceDimension": int(covariance.shape[0]),
        "coefficientCovarianceSha256LittleEndianFloat64": covariance_hash,
        "fittedCoefficientsSerialized": False,
        "endpointMeansSerialized": False,
        "observedContrastsSerialized": False,
    }


def lower_chi_square_wilson_hilferty(df: int, probability: float) -> float:
    z = NormalDist().inv_cdf(probability)
    base = 1.0 - 2.0 / (9.0 * df) + z * math.sqrt(2.0 / (9.0 * df))
    require(base > 0.0, "invalid Wilson-Hilferty chi-square approximation")
    return df * base ** 3


def wilson_interval(successes: int, trials: int, z: float = 1.959963984540054) -> tuple[float, float]:
    p = successes / trials
    z2 = z * z
    denominator = 1.0 + z2 / trials
    center = (p + z2 / (2.0 * trials)) / denominator
    half = z * math.sqrt((p * (1.0 - p) / trials) + z2 / (4.0 * trials * trials)) / denominator
    return max(0.0, center - half), min(1.0, center + half)


def coefficient_index(response_index: int, design_column_index: int, p: int) -> int:
    return response_index * p + design_column_index


def build_contrast_matrix(target: str, labels: list[str], design_columns: list[str], p: int) -> tuple[np.ndarray, list[str]]:
    column_lookup = {name: i for i, name in enumerate(design_columns)}
    comparators = [label for label in labels if label != target]
    metric_specs = [
        ("D1_GEOMETRIC_MEAN", 0, "intercept"),
        ("D1_P95", 1, "intercept"),
        ("D2", 2, "intercept"),
        ("D3", 3, "intercept"),
        ("D4", 4, "intercept"),
        ("D5", 0, "log2N"),
        ("D6", 0, "log2F"),
        ("D7", 0, "log2G2"),
    ]
    rows: list[np.ndarray] = []
    row_names: list[str] = []
    for comparator in comparators:
        for metric, response_index, term in metric_specs:
            vector = np.zeros(p * 5, dtype=np.float64)
            target_col = column_lookup[f"opaque[{target}]:{term}"]
            comparator_col = column_lookup[f"opaque[{comparator}]:{term}"]
            vector[coefficient_index(response_index, target_col, p)] = 1.0
            vector[coefficient_index(response_index, comparator_col, p)] = -1.0
            rows.append(vector)
            row_names.append(f"{target}_vs_{comparator}:{metric}")
    matrix = np.vstack(rows)
    require(matrix.shape == (40, p * 5), "primitive contrast matrix cardinality mismatch")
    return matrix, row_names


def project_psd(matrix: np.ndarray) -> tuple[np.ndarray, dict[str, Any]]:
    matrix = (matrix + matrix.T) / 2.0
    eigenvalues, eigenvectors = np.linalg.eigh(matrix)
    max_eigenvalue = float(np.max(eigenvalues))
    floor = max(max_eigenvalue * 1e-12, 0.0)
    clipped = np.maximum(eigenvalues, floor)
    projected = (eigenvectors * clipped) @ eigenvectors.T
    projected = (projected + projected.T) / 2.0
    return projected, {
        "minimumEigenvalueBeforeProjection": float(np.min(eigenvalues)),
        "maximumEigenvalueBeforeProjection": max_eigenvalue,
        "projectionFloor": floor,
        "eigenvaluesRaisedToFloor": int(np.sum(eigenvalues < floor)),
    }


def primary_success_from_z(z_values: np.ndarray) -> np.ndarray:
    batch = z_values.shape[0]
    require(z_values.shape[1] == 40, "primitive z-statistic cardinality mismatch")
    domain_z = np.empty((batch, 7, 5), dtype=np.float64)
    for comparator_index in range(5):
        offset = comparator_index * 8
        domain_z[:, 0, comparator_index] = np.maximum(z_values[:, offset], z_values[:, offset + 1])
        for domain_index in range(1, 7):
            domain_z[:, domain_index, comparator_index] = z_values[:, offset + domain_index + 1]
    flattened = domain_z.reshape(batch, 35)
    order = np.argsort(flattened, axis=1)
    ordered_z = np.take_along_axis(flattened, order, axis=1)
    normal = NormalDist()
    critical = np.asarray([normal.inv_cdf(ALPHA / (35 - k)) for k in range(35)], dtype=np.float64)
    eligible_in_order = ordered_z <= critical[None, :]
    rejected_in_order = np.logical_and.accumulate(eligible_in_order, axis=1)
    rejected = np.zeros_like(rejected_in_order)
    np.put_along_axis(rejected, order, rejected_in_order, axis=1)
    domain_pass = rejected.reshape(batch, 7, 5).all(axis=2)
    return domain_pass.sum(axis=1) >= 4


def simulate_target_power(
    target: str,
    target_index: int,
    B: int,
    coefficient_covariance: np.ndarray,
    design_columns: list[str],
    labels: list[str],
    nuisance_inflation: float,
) -> tuple[dict[str, Any], dict[str, Any]]:
    p = len(design_columns)
    contrast, _ = build_contrast_matrix(target, labels, design_columns, p)
    contrast_covariance = contrast @ coefficient_covariance @ contrast.T
    contrast_covariance *= (EXPECTED_QUALIFICATION_B_PER_CELL / B) * nuisance_inflation
    contrast_covariance, psd_meta = project_psd(contrast_covariance)
    standard_errors = np.sqrt(np.diag(contrast_covariance))
    require(np.isfinite(standard_errors).all() and np.all(standard_errors > 0.0), "invalid contrast standard errors")
    eigenvalues, eigenvectors = np.linalg.eigh(contrast_covariance)
    eigenvalues = np.maximum(eigenvalues, 0.0)
    factor = eigenvectors * np.sqrt(eigenvalues)
    seed = BASE_SEED + B * 100 + target_index
    rng = np.random.default_rng(seed)
    alternative = np.full(40, MIPE_LOG_RATIO, dtype=np.float64)
    successes = 0
    completed = 0
    while completed < MONTE_CARLO_DRAWS:
        current = min(MONTE_CARLO_BATCH, MONTE_CARLO_DRAWS - completed)
        noise = rng.standard_normal((current, 40)) @ factor.T
        estimates = alternative[None, :] + noise
        z_values = estimates / standard_errors[None, :]
        successes += int(np.sum(primary_success_from_z(z_values)))
        completed += current
    power = successes / MONTE_CARLO_DRAWS
    lower, upper = wilson_interval(successes, MONTE_CARLO_DRAWS)
    result = {
        "opaqueTarget": target,
        "B": B,
        "seed": seed,
        "draws": MONTE_CARLO_DRAWS,
        "successes": successes,
        "power": power,
        "wilson95Lower": lower,
        "wilson95Upper": upper,
    }
    covariance_meta = {
        "opaqueTarget": target,
        "B": B,
        "contrastCovarianceSha256LittleEndianFloat64": sha256_bytes(np.asarray(contrast_covariance, dtype="<f8").tobytes(order="C")),
        "contrastCovarianceDimension": 40,
        "psdProjection": psd_meta,
    }
    return result, covariance_meta


def load_runtime_rows(path: Path) -> tuple[dict[int, dict[str, Any]], float]:
    value = load_json(path)
    threshold = float(value["sevenDayDecisionGateHours"])
    require(threshold == 168.0, "runtime prediction seven-day gate is not 168 hours")
    rows: dict[int, dict[str, Any]] = {}
    for row in value["rows"]:
        B = int(row["B"])
        if B in CANDIDATE_B:
            rows[B] = {
                "B": B,
                "formalSuperblocks": int(row["formalSuperblocks"]),
                "laneProcesses": int(row["laneProcesses"]),
                "planningWith20PercentHeadroomHours": finite_float(row["planningWith20PercentHeadroomHours"], "planningWith20PercentHeadroomHours"),
                "atOrAboveSevenDayGate": bool(row["atOrAboveSevenDayGate"]),
            }
    require(set(rows) == set(CANDIDATE_B), "runtime prediction does not cover every candidate B")
    for B, row in rows.items():
        require(row["atOrAboveSevenDayGate"] == (row["planningWith20PercentHeadroomHours"] >= threshold), f"runtime threshold flag mismatch for B={B}")
    return rows, threshold


def relative(project_root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def run(args: argparse.Namespace) -> int:
    started = utc_now()
    project_root = Path(args.project_root).resolve()
    output_root = Path(args.output_root).resolve()
    delivery_root = project_root / "Research/Exports/Gate14Re-ME/load-qualification/attempt-009"
    paths = {
        "qualificationTerminalPass": project_root / "Research/Verification/Gate14Re-ME/load-qualification-read-only-acceptance-attempt-001/qualification-terminal-pass-receipt.v1.json",
        "eventGroups": delivery_root / "typed-parquet/event-groups/event-groups.v4_2.parquet",
        "d3Windows": delivery_root / "typed-parquet/d3-windows/d3-windows.v4_2.parquet",
        "persistentState": delivery_root / "typed-parquet/persistent-state/persistent-state.v4_2.parquet",
        "schedule": project_root / "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl",
        "runtimePrediction": project_root / "Research/Verification/Gate14Re-ME/load-qualification-post-qualification-runtime-diagnostic-attempt-002/formal-st-runtime-prediction.v2.json",
    }
    require(output_root.is_dir(), "output root does not exist")
    for name in GENERATED_FILES:
        require(not (output_root / name).exists(), f"fresh-output gate failed; {name} already exists")
    frozen_files = verify_pre_execution_freeze(output_root)
    inventory: list[dict[str, Any]] = []
    for label, path in paths.items():
        row = verify_hash(path, EXPECTED_HASHES[label], label)
        row["relativePath"] = relative(project_root, path)
        inventory.append(row)
    for row in frozen_files:
        path = output_root / row["relativePath"]
        inventory.append({
            "schema": "gate14re-me-formal-st-power-input-inventory-row-v1",
            "label": f"frozen:{row['relativePath']}",
            "relativePath": relative(project_root, path),
            "bytes": row["bytes"],
            "sha256": row["sha256"],
        })

    schedule_output = output_root / "anonymous-structural-schedule.v1.jsonl"
    schedule_map, sanitized_rows = sanitize_schedule(paths["schedule"], schedule_output)
    inventory.append({
        "schema": "gate14re-me-formal-st-power-input-inventory-row-v1",
        "label": "generatedAnonymousStructuralSchedule",
        "relativePath": relative(project_root, schedule_output),
        "bytes": schedule_output.stat().st_size,
        "sha256": sha256_file(schedule_output),
    })
    write_jsonl(output_root / "input-inventory.v1.jsonl", inventory)

    summaries, event_structure, d3_ids = read_event_lane_summaries(paths["eventGroups"], schedule_map)
    d3_structure = attach_d3(summaries, paths["d3Windows"], d3_ids)
    d4_structure = attach_d4(summaries, paths["persistentState"])
    X, Y, clusters, design_columns, design_meta = build_design(summaries)
    coefficient_covariance, covariance_meta = clustered_multivariate_covariance(X, Y, clusters)
    df = design_meta["independentClusters"] - design_meta["rank"]
    require(df > 0, "non-positive nuisance uncertainty degrees of freedom")
    chi_square_lower = lower_chi_square_wilson_hilferty(df, 0.05)
    nuisance_inflation = df / chi_square_lower
    require(math.isfinite(nuisance_inflation) and nuisance_inflation > 1.0, "invalid nuisance uncertainty inflation")

    runtime_rows, seven_day_threshold = load_runtime_rows(paths["runtimePrediction"])
    candidate_results: list[dict[str, Any]] = []
    all_covariance_meta: list[dict[str, Any]] = []
    labels = design_meta["opaqueLabels"]
    for B in CANDIDATE_B:
        opaque_results: list[dict[str, Any]] = []
        for target_index, target in enumerate(labels):
            result, contrast_meta = simulate_target_power(
                target,
                target_index,
                B,
                coefficient_covariance,
                design_columns,
                labels,
                nuisance_inflation,
            )
            opaque_results.append(result)
            all_covariance_meta.append(contrast_meta)
        worst = min(opaque_results, key=lambda item: (item["wilson95Lower"], item["power"], item["opaqueTarget"]))
        passes = bool(worst["wilson95Lower"] >= TARGET_POWER)
        candidate_results.append({
            "B": B,
            "opaqueTargetResults": opaque_results,
            "worstOpaqueTarget": worst["opaqueTarget"],
            "worstPower": worst["power"],
            "worstWilson95Lower": worst["wilson95Lower"],
            "passesFrozenPowerCriterion": passes,
            "runtime": runtime_rows[B],
        })
    selected = next((row for row in candidate_results if row["passesFrozenPowerCriterion"]), None)
    selected_B = None if selected is None else int(selected["B"])
    selected_runtime = None if selected_B is None else runtime_rows[selected_B]
    seven_day_triggered = bool(selected_runtime and selected_runtime["planningWith20PercentHeadroomHours"] >= seven_day_threshold)
    if selected_B is None:
        status = "FAIL_CLOSED_NO_CANDIDATE_MEETS_POWER"
        disposition = "No final B may be frozen; scientific redesign or a separately authorized candidate grid is required."
    elif seven_day_triggered:
        status = "PASS_POWER_SELECTION_SEVEN_DAY_GATE_TRIGGERED"
        disposition = "Stop before formal ST freeze and submit a simplification proposal for explicit user authorization."
    else:
        status = "PASS_ANONYMOUS_POWER_FINAL_B_ELIGIBLE_FOR_FORMAL_FREEZE"
        disposition = "Selected B is eligible for the separately evidenced formal ST freeze under the already authorized sequence."

    nuisance_summary = {
        "schema": "gate14re-me-formal-st-identity-blind-nuisance-summary-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-anonymous-power-attempt-001",
        "status": "PASS_IDENTITY_BLIND_NUISANCE_ESTIMATION",
        "eventStructure": event_structure,
        "d3Structure": d3_structure,
        "d4Structure": d4_structure,
        "sanitizedScheduleRows": len(sanitized_rows),
        "designMatrix": design_meta,
        "covariance": covariance_meta,
        "nuisanceUncertainty": {
            "degreesOfFreedom": df,
            "lowerTailProbability": 0.05,
            "chiSquareLowerQuantileMethod": "Wilson-Hilferty approximation",
            "chiSquareLowerQuantile": chi_square_lower,
            "varianceInflationFactor": nuisance_inflation,
        },
        "outputSuppression": {
            "algorithmIdentityOpened": False,
            "algorithmIdRead": False,
            "fittedCoefficientsSerialized": False,
            "endpointMeansSerialized": False,
            "observedEffectsSerialized": False,
            "ranksWeightsOrWinnerSerialized": False,
        },
        "contrastCovarianceMetadata": all_covariance_meta,
    }
    write_json(output_root / "nuisance-summary.v1.json", nuisance_summary)

    power_result = {
        "schema": "gate14re-me-formal-st-anonymous-power-result-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-anonymous-power-attempt-001",
        "status": status,
        "createdAtUtc": utc_now(),
        "mipe": {
            "ratio": 0.9,
            "logRatioExact": MIPE_LOG_RATIO,
            "lowerIsBetter": True,
        },
        "targetPowerAtLeast": TARGET_POWER,
        "familywiseAlpha": ALPHA,
        "multiplicity": "Holm strong FWER across 35 domain-by-comparator hypotheses",
        "primaryClaimSuccess": "at least four of seven domains pass, and each passing domain rejects all five comparator hypotheses",
        "candidateResults": candidate_results,
        "selectionRule": "smallest B whose worst opaque-target Wilson 95% lower power bound is at least 0.90",
        "selectedB": selected_B,
        "selectedRuntime": selected_runtime,
        "sevenDayDecisionGateHours": seven_day_threshold,
        "sevenDayGateTriggered": seven_day_triggered,
        "disposition": disposition,
        "scientificBoundaries": {
            "movementTransferSentinel": "OMITTED",
            "correctnessAndOracleHardGates": "RETAINED",
            "formalCollectionStarted": False,
            "qualificationObservationsUsedAsFormalSamples": False,
            "identityMappingOpened": False,
            "algorithmEffectsRanksWeightsOrWinnerReported": False,
        },
    }
    write_json(output_root / "power-result.v1.json", power_result)

    terminal = {
        "schema": "gate14re-me-formal-st-anonymous-power-terminal-receipt-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-anonymous-power-attempt-001",
        "status": status,
        "startedAtUtc": started,
        "completedAtUtc": utc_now(),
        "selectedB": selected_B,
        "sevenDayGateTriggered": seven_day_triggered,
        "powerResult": {
            "relativePath": relative(project_root, output_root / "power-result.v1.json"),
            "sha256": sha256_file(output_root / "power-result.v1.json"),
        },
        "nuisanceSummary": {
            "relativePath": relative(project_root, output_root / "nuisance-summary.v1.json"),
            "sha256": sha256_file(output_root / "nuisance-summary.v1.json"),
        },
        "anonymousStructuralSchedule": {
            "relativePath": relative(project_root, schedule_output),
            "sha256": sha256_file(schedule_output),
        },
        "inputInventory": {
            "relativePath": relative(project_root, output_root / "input-inventory.v1.jsonl"),
            "sha256": sha256_file(output_root / "input-inventory.v1.jsonl"),
        },
        "formalCollectionStarted": False,
        "migrationPackageBuilt": False,
    }
    write_json(output_root / "terminal-receipt.v1.json", terminal)
    print(json.dumps({
        "status": status,
        "selectedB": selected_B,
        "sevenDayGateTriggered": seven_day_triggered,
        "powerResultSha256": sha256_file(output_root / "power-result.v1.json"),
        "terminalReceiptSha256": sha256_file(output_root / "terminal-receipt.v1.json"),
    }, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    try:
        return run(args)
    except Exception as error:
        output_root = Path(args.output_root).resolve()
        failure_path = output_root / "terminal-receipt.v1.json"
        failure = {
            "schema": "gate14re-me-formal-st-anonymous-power-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "attemptId": "formal-st-anonymous-power-attempt-001",
            "status": "FAIL_CLOSED_TECHNICAL_ERROR",
            "failedAtUtc": utc_now(),
            "errorType": type(error).__name__,
            "errorMessage": str(error),
            "tracebackSha256": sha256_bytes(traceback.format_exc().encode("utf-8")),
            "formalCollectionStarted": False,
            "migrationPackageBuilt": False,
        }
        if output_root.is_dir() and not failure_path.exists():
            write_json(failure_path, failure)
        print(json.dumps(failure, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
