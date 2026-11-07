#!/usr/bin/env python3
"""Prospective identity-blind power calculation for formal MQ design v2.

P1-P4 are the confirmatory primary family and alone select B. S1-S2 are
gate-kept key secondary endpoints and never influence B selection. The program
does not access algorithmId, conditionId, batchId, inputId, or an identity map,
and it serializes neither qualification means nor observed effects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import traceback
from pathlib import Path
from statistics import NormalDist
from typing import Any

import numpy as np


ATTEMPT_ID = "identity-blind-power-v2-attempt-001"
STUDY_ID = "Gate14Re-MQ-CFF-IDFF"
DESIGN_ID = "gate14re-mq-cff-idff-formal-v2"
EXPECTED_HASHES = {
    "authorized-design": "79b4cbf309f278c2611955419ddb0d524915e4ddc6ae1596746cff1ec7bfa18a",
    "engineering-external-freeze": "c2bc8217e48bdb3248e97353538207f9386c2c866fd80e713fabadaf195df33b",
    "engineering-terminal": "d5429793cc940ad2e0a1c51fea760d2cbd43766849fb0d1f80f4752ba4c5d09e",
    "performance-lanes": "75430f9a2da0f82ec04d66778756b50ebc29d59b835d0f47b4dc8894b545dae0",
    "technical-batches": "3b1fc6a3c3b7a40faa4ce17b50e9f279ac7eb21cef08d4c42478589ae955443f",
    "engineering-runner": "5ea8e1d8d8efddfa3ac891258e68e56ba50a0b123374a9ad44e3ce8f44fc23f8",
    "runtime-budget": "2a2b2b9a89bf6c9282debe7ee44c983dd6b054692e7c6b80dd8886838ab147ac",
}
CONDITION_WORKERS = np.asarray([1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 8, 16] * 2, dtype=np.int64)
CANDIDATE_B = (36, 72, 108, 144)
MIPE = -0.10536051565782628
ALPHA = 0.05
TARGET = 0.90
BOOTSTRAP_DRAWS = 100_000
POWER_DRAWS = 200_000
BOOTSTRAP_SEED = 141420271
POWER_BASE_SEED = 141420272
MINIMUM_LOG_JITTER_SIGMA = 0.03
MODEL_RISK_VARIANCE_MULTIPLIER = 2.0


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, start=1):
            text = raw.strip()
            if not text:
                continue
            value = json.loads(text)
            require(isinstance(value, dict), f"JSONL object required at {path}:{line_number}")
            rows.append(value)
    return rows


def write_json(path: Path, value: Any) -> None:
    require(not path.exists(), f"fresh-output gate failed: {path.name}")
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=False)
        stream.write("\n")
    temporary.replace(path)


def verify_hash(path: Path, expected: str, role: str) -> dict[str, Any]:
    require(path.is_file(), f"missing input for {role}: {path}")
    actual = sha256_file(path)
    require(actual == expected, f"SHA-256 mismatch for {role}: {actual}")
    return {"role": role, "relativePath": None, "bytes": path.stat().st_size, "sha256": actual}


def relative(project_root: Path, path: Path) -> str:
    return path.resolve().relative_to(project_root.resolve()).as_posix()


def structural_estimands(log_batch: np.ndarray) -> np.ndarray:
    require(log_batch.ndim == 2 and log_batch.shape[1] == 24, "expected 24 structural batch columns")
    x = np.asarray([0.0, 1.0, 2.0, 3.0], dtype=np.float64)
    centered_x = x - np.mean(x)
    denominator = float(centered_x @ centered_x)

    def slope(columns: list[int]) -> np.ndarray:
        return (log_batch[:, columns] @ centered_x) / denominator

    return np.column_stack(
        [
            slope([1, 2, 3, 4]),
            slope([6, 7, 8, 9]),
            slope([13, 14, 15, 16]),
            slope([18, 19, 20, 21]),
            log_batch[:, 11] - log_batch[:, 10],
            log_batch[:, 23] - log_batch[:, 22],
        ]
    )


def read_opaque_timing(lane_path: Path, batch_path: Path) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    lane_rows = read_jsonl(lane_path)
    batch_rows = read_jsonl(batch_path)
    require(len(lane_rows) == 384, "performance lane cardinality must be 384")
    require(len(batch_rows) == 24, "technical batch cardinality must be 24")
    lane_timing = np.full((24, 16), np.nan, dtype=np.float64)
    for row in lane_rows:
        require(row.get("schema") == "gate14re-mq-performance-lane-evidence-v1", "lane schema mismatch")
        batch_ordinal = int(row["batchOrdinal"])
        lane_ordinal = int(row["laneOrdinal"])
        source_replica = int(row["sourceReplicaIndex"])
        require(0 <= batch_ordinal < 24 and 0 <= lane_ordinal < 16, "lane ordinal out of range")
        require(source_replica == lane_ordinal // 8, "sourceReplicaIndex structure mismatch")
        runtime = row["executorRuntime"]
        require(int(runtime["ordinal"]) == lane_ordinal, "executor ordinal mismatch")
        require(runtime["state"] == "COMPLETED", "non-completed qualification lane")
        require(bool(runtime["stayedOnConfiguredCpuSet"]), "qualification lane left configured CPU set")
        wall = float(runtime["wallMilliseconds"])
        require(math.isfinite(wall) and wall > 0.0, "invalid lane wall time")
        require(math.isnan(float(lane_timing[batch_ordinal, lane_ordinal])), "duplicate lane key")
        lane_timing[batch_ordinal, lane_ordinal] = wall
    require(np.isfinite(lane_timing).all(), "incomplete lane timing matrix")

    batch_wall = np.full(24, np.nan, dtype=np.float64)
    for batch_ordinal, row in enumerate(batch_rows):
        require(row.get("schema") == "gate14re-mq-managed-batch-runtime-v1", "batch schema mismatch")
        require(int(row["workerCount"]) == int(CONDITION_WORKERS[batch_ordinal]), "worker-count mismatch")
        require(int(row["laneCount"]) == 16, "batch lane count mismatch")
        require(int(row["completedLaneCount"]) == 16, "batch completed count mismatch")
        require(int(row["failedLaneCount"]) == 0 and int(row["skippedLaneCount"]) == 0, "batch failure gate")
        require(bool(row["succeeded"]) and row["status"] == "PASS_ALL_LANES_COMPLETED", "batch terminal gate")
        wall = float(row["batchWallMilliseconds"])
        require(math.isfinite(wall) and wall > 0.0, "invalid batch wall time")
        batch_wall[batch_ordinal] = wall
    return lane_timing, batch_wall, {
        "laneRows": len(lane_rows),
        "batchRows": len(batch_rows),
        "opaqueSlots": 2,
        "conditionsPerOpaqueSlot": 12,
        "sourceUnits": 8,
        "replicasPerSource": 2,
    }


def reconstruct_makespan(lane_values: np.ndarray, workers: int) -> float:
    require(lane_values.shape == (16,), "pseudo block must contain 16 lanes")
    totals = np.zeros(workers, dtype=np.float64)
    for lane_ordinal in range(16):
        totals[lane_ordinal % workers] += lane_values[lane_ordinal]
    result = float(np.max(totals))
    require(math.isfinite(result) and result > 0.0, "invalid reconstructed makespan")
    return result


def nuisance_covariance(lane_timing: np.ndarray, batch_wall: np.ndarray) -> tuple[np.ndarray, dict[str, Any]]:
    calibration = np.empty(24, dtype=np.float64)
    for batch in range(24):
        baseline = reconstruct_makespan(lane_timing[batch, :], int(CONDITION_WORKERS[batch]))
        calibration[batch] = batch_wall[batch] / baseline
    require(np.isfinite(calibration).all() and np.all(calibration > 0.0), "invalid batch calibration")

    log_lane = np.log(lane_timing)
    duplicate_noise = (log_lane[:, :8] - log_lane[:, 8:]) / math.sqrt(2.0)
    duplicate_noise -= float(np.mean(duplicate_noise))
    estimated_jitter_sigma = float(np.std(duplicate_noise, ddof=1))
    jitter_sigma = max(MINIMUM_LOG_JITTER_SIGMA, estimated_jitter_sigma)
    require(math.isfinite(jitter_sigma) and jitter_sigma > 0.0, "invalid identity-blind jitter")

    source_vectors = np.empty((8, 2, 24), dtype=np.float64)
    for source in range(8):
        source_vectors[source, 0, :] = lane_timing[:, source]
        source_vectors[source, 1, :] = lane_timing[:, source + 8]

    rng = np.random.default_rng(BOOTSTRAP_SEED)
    estimands = np.empty((BOOTSTRAP_DRAWS, 6), dtype=np.float64)
    completed = 0
    while completed < BOOTSTRAP_DRAWS:
        current = min(2000, BOOTSTRAP_DRAWS - completed)
        sampled_sources = rng.integers(0, 8, size=(current, 16), endpoint=False)
        sampled_replicas = rng.integers(0, 2, size=(current, 16), endpoint=False)
        log_batch = np.empty((current, 24), dtype=np.float64)
        for draw in range(current):
            selected = source_vectors[sampled_sources[draw], sampled_replicas[draw], :].T
            for batch in range(24):
                makespan = reconstruct_makespan(selected[batch, :], int(CONDITION_WORKERS[batch]))
                log_batch[draw, batch] = math.log(makespan * calibration[batch])
        log_batch += rng.normal(0.0, jitter_sigma, size=(current, 24))
        estimands[completed : completed + current, :] = structural_estimands(log_batch)
        completed += current

    centered = estimands - np.mean(estimands, axis=0, keepdims=True)
    covariance = np.cov(centered, rowvar=False, ddof=1)
    require(covariance.shape == (6, 6) and np.isfinite(covariance).all(), "invalid nuisance covariance")
    del estimands, centered

    df = 7
    z = NormalDist().inv_cdf(0.05)
    base = 1.0 - 2.0 / (9.0 * df) + z * math.sqrt(2.0 / (9.0 * df))
    require(base > 0.0, "invalid Wilson-Hilferty lower quantile")
    chi_square_lower = df * base**3
    small_source_inflation = df / chi_square_lower
    total_inflation = small_source_inflation * MODEL_RISK_VARIANCE_MULTIPLIER
    covariance *= total_inflation
    covariance = (covariance + covariance.T) / 2.0
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    maximum = float(np.max(eigenvalues))
    require(maximum > 0.0 and math.isfinite(maximum), "non-positive nuisance covariance")
    floor = maximum * 1e-10
    clipped = np.maximum(eigenvalues, floor)
    covariance = (eigenvectors * clipped) @ eigenvectors.T
    covariance = (covariance + covariance.T) / 2.0
    require(np.all(np.diag(covariance) > 0.0), "non-positive nuisance variance")
    return covariance, {
        "bootstrapDraws": BOOTSTRAP_DRAWS,
        "bootstrapSeed": BOOTSTRAP_SEED,
        "sourceUnits": 8,
        "replicasPerSource": 2,
        "pseudoBlockLanes": 16,
        "minimumLogJitterSigma": MINIMUM_LOG_JITTER_SIGMA,
        "pooledIdentityBlindJitterSigmaUsed": jitter_sigma,
        "smallSourceDegreesOfFreedom": df,
        "chiSquareLowerTailProbability": 0.05,
        "chiSquareLowerQuantileMethod": "Wilson-Hilferty approximation",
        "chiSquareLowerQuantile": chi_square_lower,
        "smallSourceVarianceInflation": small_source_inflation,
        "modelRiskVarianceMultiplier": MODEL_RISK_VARIANCE_MULTIPLIER,
        "totalVarianceInflation": total_inflation,
        "psdFloor": floor,
        "eigenvaluesRaisedToFloor": int(np.sum(eigenvalues < floor)),
        "covarianceDimension": 6,
        "covarianceSha256LittleEndianFloat64": sha256_bytes(np.asarray(covariance, dtype="<f8").tobytes(order="C")),
        "qualificationMeansSerialized": False,
        "observedEffectsSerialized": False,
    }


def wilson_interval(successes: int, trials: int, z: float = 1.959963984540054) -> tuple[float, float]:
    p = successes / trials
    z2 = z * z
    denominator = 1.0 + z2 / trials
    center = (p + z2 / (2.0 * trials)) / denominator
    half = z * math.sqrt((p * (1.0 - p) / trials) + z2 / (4.0 * trials * trials)) / denominator
    return max(0.0, center - half), min(1.0, center + half)


def holm_rejections(z_values: np.ndarray) -> np.ndarray:
    require(z_values.ndim == 2 and z_values.shape[1] >= 1, "Holm input must be a matrix")
    family_size = z_values.shape[1]
    order = np.argsort(z_values, axis=1)
    ordered = np.take_along_axis(z_values, order, axis=1)
    critical = np.asarray(
        [NormalDist().inv_cdf(ALPHA / (family_size - k)) for k in range(family_size)],
        dtype=np.float64,
    )
    eligible = ordered <= critical[None, :]
    rejected_ordered = np.logical_and.accumulate(eligible, axis=1)
    rejected = np.zeros_like(rejected_ordered)
    np.put_along_axis(rejected, order, rejected_ordered, axis=1)
    return rejected


def power_rows(successes: np.ndarray, labels: tuple[str, ...]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for index, label in enumerate(labels):
        success = int(successes[index])
        power = success / POWER_DRAWS
        lower, upper = wilson_interval(success, POWER_DRAWS)
        rows.append({
            "hypothesis": label,
            "draws": POWER_DRAWS,
            "rejections": success,
            "power": power,
            "wilson95Lower": lower,
            "wilson95Upper": upper,
        })
    return rows


def simulate_power(covariance: np.ndarray, B: int) -> dict[str, Any]:
    rng = np.random.default_rng(POWER_BASE_SEED + B)
    factor = np.linalg.cholesky(covariance)
    primary_successes = np.zeros(4, dtype=np.int64)
    secondary_successes = np.zeros(2, dtype=np.int64)
    gate_open_count = 0
    completed = 0
    while completed < POWER_DRAWS:
        current = min(1000, POWER_DRAWS - completed)
        noise = rng.standard_normal((current, B, 6)) @ factor.T
        blocks = MIPE + noise
        means = np.mean(blocks, axis=1)
        standard_errors = np.std(blocks, axis=1, ddof=1) / math.sqrt(B)
        require(np.isfinite(standard_errors).all() and np.all(standard_errors > 0.0), "invalid simulated standard error")
        z_values = means / standard_errors
        primary_rejected = holm_rejections(z_values[:, :4])
        gate_open = np.all(primary_rejected, axis=1)
        secondary_rejected = holm_rejections(z_values[:, 4:]) & gate_open[:, None]
        primary_successes += np.sum(primary_rejected, axis=0, dtype=np.int64)
        secondary_successes += np.sum(secondary_rejected, axis=0, dtype=np.int64)
        gate_open_count += int(np.sum(gate_open))
        completed += current
    primary_rows = power_rows(primary_successes, ("P1", "P2", "P3", "P4"))
    secondary_rows = power_rows(secondary_successes, ("S1", "S2"))
    worst = min(primary_rows, key=lambda row: (row["wilson95Lower"], row["power"], row["hypothesis"]))
    gate_power = gate_open_count / POWER_DRAWS
    gate_lower, gate_upper = wilson_interval(gate_open_count, POWER_DRAWS)
    return {
        "B": B,
        "seed": POWER_BASE_SEED + B,
        "primaryResults": primary_rows,
        "worstPrimary": worst["hypothesis"],
        "worstPrimaryPower": worst["power"],
        "worstPrimaryWilson95Lower": worst["wilson95Lower"],
        "passesFrozenPrimaryPowerCriterion": bool(worst["wilson95Lower"] >= TARGET),
        "primaryGateOpenPlanningProbability": {
            "draws": POWER_DRAWS,
            "opens": gate_open_count,
            "probability": gate_power,
            "wilson95Lower": gate_lower,
            "wilson95Upper": gate_upper,
        },
        "keySecondaryGatedPlanningResults": secondary_rows,
        "keySecondaryUsedForBSelection": False,
    }


def run(project_root: Path, output_root: Path) -> int:
    paths = {
        "authorized-design": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/formal-mq-authorized-design.v2.json",
        "engineering-external-freeze": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/external-freeze-receipt.v1.json",
        "engineering-terminal": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/terminal-receipt.v1.json",
        "performance-lanes": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/performance-lanes.raw.v1.jsonl",
        "technical-batches": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/technical-batches.raw.v1.jsonl",
        "engineering-runner": project_root / "Assets/_Scripts/Research/Editor/Gate14ReMQEngineeringQualificationV1.cs",
        "runtime-budget": project_root / "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-runtime-analysis-v2/engineering-runtime-diagnostics.v2.json",
    }
    require(output_root.is_dir(), "output root must already exist")
    computed_names = ("input-inventory.v2.json", "nuisance-summary.v2.json", "power-result.v2.json", "terminal-receipt.v2.json")
    for name in computed_names:
        require(not (output_root / name).exists(), f"fresh-output gate failed: {name}")

    inventory: list[dict[str, Any]] = []
    for role, path in paths.items():
        row = verify_hash(path, EXPECTED_HASHES[role], role)
        row["relativePath"] = relative(project_root, path)
        inventory.append(row)
    write_json(output_root / "input-inventory.v2.json", {
        "schema": "gate14re-mq-cff-idff-power-input-inventory-v2",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "attemptId": ATTEMPT_ID,
        "files": inventory,
    })

    lane_timing, batch_wall, structure = read_opaque_timing(paths["performance-lanes"], paths["technical-batches"])
    covariance, nuisance_metadata = nuisance_covariance(lane_timing, batch_wall)
    write_json(output_root / "nuisance-summary.v2.json", {
        "schema": "gate14re-mq-cff-idff-identity-blind-nuisance-summary-v2",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "attemptId": ATTEMPT_ID,
        "status": "PASS_IDENTITY_BLIND_NUISANCE_ESTIMATION",
        "structure": structure,
        "nuisance": nuisance_metadata,
        "outputSuppression": {
            "algorithmIdentityMapOpened": False,
            "algorithmIdAccessed": False,
            "conditionIdAccessed": False,
            "inputIdAccessed": False,
            "qualificationMeansSerialized": False,
            "observedEffectsDirectionsRanksWeightsOrWinnerSerialized": False,
        },
    })

    runtime = load_json(paths["runtime-budget"])["formalRuntimePlanning"]
    runtime_rows = {int(row["B"]): row for row in runtime["budgets"]}
    require(set(runtime_rows) == set(CANDIDATE_B), "runtime budget does not cover candidate B set")
    candidate_results: list[dict[str, Any]] = []
    for B in CANDIDATE_B:
        result = simulate_power(covariance, B)
        budget = runtime_rows[B]
        result["runtime"] = {
            "freshUnityProcessCount": int(budget["freshUnityProcessCount"]),
            "stressHoursAt1_9x": float(budget["stressHoursAt1_9x"]),
            "atOrAbove168Hours": bool(float(budget["stressHoursAt1_9x"]) >= 168.0),
        }
        candidate_results.append(result)
    selected = next((row for row in candidate_results if row["passesFrozenPrimaryPowerCriterion"]), None)
    selected_B = None if selected is None else int(selected["B"])
    seven_day_triggered = bool(selected is not None and selected["runtime"]["atOrAbove168Hours"])
    if selected_B is None:
        status = "FAIL_CLOSED_NO_CANDIDATE_MEETS_PRIMARY_POWER"
        disposition = "Stop without final implementation or schedule freeze and request a separately authorized redesign."
    elif seven_day_triggered:
        status = "PASS_PRIMARY_POWER_SELECTION_168_HOUR_GATE_TRIGGERED"
        disposition = "Stop before final implementation or schedule freeze and submit a simplification proposal."
    else:
        status = "PASS_IDENTITY_BLIND_PRIMARY_POWER_B_SELECTED_ELIGIBLE_FOR_FINAL_FREEZE"
        disposition = "Continue to implementation schedule freeze and prelaunch readiness under the current authorization."

    result_path = output_root / "power-result.v2.json"
    write_json(result_path, {
        "schema": "gate14re-mq-cff-idff-identity-blind-power-result-v2",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "attemptId": ATTEMPT_ID,
        "status": status,
        "mipe": {"ratio": 0.90, "logScaleExact": MIPE, "lowerIsBetter": True},
        "primaryFamily": ["P1", "P2", "P3", "P4"],
        "keySecondaryFamily": ["S1", "S2"],
        "targetPrimaryPowerAtLeast": TARGET,
        "familywiseAlpha": ALPHA,
        "multiplicity": "P1-P4 one-sided Holm; S1-S2 one-sided Holm only after all P1-P4 reject",
        "candidateResults": candidate_results,
        "selectionRule": "smallest B whose worst P1-P4 Wilson 95 percent lower power bound is at least 0.90",
        "keySecondaryUsedForBSelection": False,
        "selectedB": selected_B,
        "selectedRuntime": None if selected is None else selected["runtime"],
        "sevenDayGateHours": 168,
        "sevenDayGateTriggered": seven_day_triggered,
        "disposition": disposition,
        "boundaries": {
            "qualificationObservationsUsedAsFormalSamples": False,
            "identityMappingOpened": False,
            "namedAlgorithmEffectsComputedOrReported": False,
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
        },
    })
    terminal_path = output_root / "terminal-receipt.v2.json"
    write_json(terminal_path, {
        "schema": "gate14re-mq-cff-idff-identity-blind-power-terminal-receipt-v2",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "attemptId": ATTEMPT_ID,
        "status": status,
        "selectedB": selected_B,
        "sevenDayGateTriggered": seven_day_triggered,
        "powerResult": {"relativePath": relative(project_root, result_path), "sha256": sha256_file(result_path)},
        "nuisanceSummary": {"relativePath": relative(project_root, output_root / "nuisance-summary.v2.json"), "sha256": sha256_file(output_root / "nuisance-summary.v2.json")},
        "inputInventory": {"relativePath": relative(project_root, output_root / "input-inventory.v2.json"), "sha256": sha256_file(output_root / "input-inventory.v2.json")},
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
    })
    print(json.dumps({
        "status": status,
        "selectedB": selected_B,
        "sevenDayGateTriggered": seven_day_triggered,
        "powerResultSha256": sha256_file(result_path),
        "terminalReceiptSha256": sha256_file(terminal_path),
    }, sort_keys=True))
    return 0 if selected_B is not None else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    try:
        return run(Path(args.project_root).resolve(), Path(args.output_root).resolve())
    except Exception as error:
        output_root = Path(args.output_root).resolve()
        failure = {
            "schema": "gate14re-mq-cff-idff-identity-blind-power-terminal-receipt-v2",
            "studyId": STUDY_ID,
            "designId": DESIGN_ID,
            "attemptId": ATTEMPT_ID,
            "status": "FAIL_CLOSED_TECHNICAL_ERROR",
            "errorType": type(error).__name__,
            "errorMessage": str(error),
            "tracebackSha256": sha256_bytes(traceback.format_exc().encode("utf-8")),
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
        }
        if output_root.is_dir() and not (output_root / "terminal-receipt.v2.json").exists():
            write_json(output_root / "terminal-receipt.v2.json", failure)
        print(json.dumps(failure, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
