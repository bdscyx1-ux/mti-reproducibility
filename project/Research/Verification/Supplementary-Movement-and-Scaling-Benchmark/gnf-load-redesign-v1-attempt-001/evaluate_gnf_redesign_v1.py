#!/usr/bin/env python3
"""Deterministic, timing-only G/N/F maximum-level redesign evaluation.

This script intentionally reads no algorithm outcome observations.  It uses only
the frozen load grid, per-cell process-wall summaries, gap summaries, and the
prior parameterized runtime formula.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


SCHEMA = "gate14re-me-gnf-load-redesign-candidate-runtime-estimates-v1"
OLD_LEVELS = {"G": [64, 128, 256], "N": [8, 32, 128, 512], "F": [1, 9, 81, 225]}
FIXED_LEVELS = {"G": [64, 128], "N": [8, 32, 128], "F": [1, 9, 81]}
CANDIDATES = [
    ("ORIGINAL_REFERENCE", 256, 512, 225),
    ("MILD", 224, 384, 196),
    ("BALANCED", 192, 256, 144),
    ("STRONG", 160, 192, 100),
]
ALGORITHM_COUNT = 6
CELLS_PER_ALGORITHM = 48
LANES_PER_B = ALGORITHM_COUNT * CELLS_PER_ALGORITHM
B_VALUE = 36
PLANNING_HEADROOM = 1.20
SEVEN_DAY_HOURS = 168.0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path):
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def dump_json(path: Path, value) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def axis_weights(target: int, observed: list[int]) -> list[tuple[int, float]]:
    if target in observed:
        return [(target, 1.0)]
    for lower, upper in zip(observed, observed[1:]):
        if lower < target < upper:
            x = math.log2(target)
            lo = math.log2(lower)
            hi = math.log2(upper)
            upper_weight = (x - lo) / (hi - lo)
            return [(lower, 1.0 - upper_weight), (upper, upper_weight)]
    raise RuntimeError(f"target {target} is outside interpolation envelope {observed}")


def interpolate_log_duration(
    lookup: dict[tuple[str, int, int, int], dict[str, float]],
    algorithm: str,
    g: int,
    n: int,
    f: int,
    field: str,
) -> float:
    weighted_log = 0.0
    total_weight = 0.0
    for source_g, weight_g in axis_weights(g, OLD_LEVELS["G"]):
        for source_n, weight_n in axis_weights(n, OLD_LEVELS["N"]):
            for source_f, weight_f in axis_weights(f, OLD_LEVELS["F"]):
                weight = weight_g * weight_n * weight_f
                value = lookup[(algorithm, source_g, source_n, source_f)][field]
                require(math.isfinite(value) and value > 0.0, f"invalid {field} at source cell")
                weighted_log += weight * math.log(value)
                total_weight += weight
    require(abs(total_weight - 1.0) < 1e-12, "interpolation weights do not sum to one")
    return math.exp(weighted_log)


def validate_candidate(candidate_id: str, g: int, n: int, f: int) -> None:
    if candidate_id == "ORIGINAL_REFERENCE":
        require((g, n, f) == (256, 512, 225), "reference maximum mismatch")
        return
    require(128 < g < 256 and g % 32 == 0, f"{candidate_id}: invalid G maximum")
    require(128 < n < 512 and n % 64 == 0, f"{candidate_id}: invalid N maximum")
    require(81 < f < 225 and int(math.isqrt(f)) ** 2 == f, f"{candidate_id}: invalid F maximum")
    require(f >= 16 and f < g * g, f"{candidate_id}: infeasible changed-cell maximum")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = root / "pre-computation-freeze-manifest.v1.json"
    manifest = load_json(manifest_path)
    require(manifest["schema"] == "gate14re-me-gnf-load-redesign-pre-computation-freeze-manifest-v1", "freeze manifest schema mismatch")

    for item in manifest["files"]:
        path = Path(item["absolutePath"])
        require(path.is_file(), f"missing frozen input: {path}")
        require(sha256(path) == item["sha256"], f"frozen hash mismatch: {path}")

    source_by_role = {item["role"]: Path(item["absolutePath"]) for item in manifest["files"]}
    timing_csv = source_by_role["algorithm-gnf-runtime-cells"]
    gap_json = load_json(source_by_role["time-component-identifiability"])
    prior_prediction = load_json(source_by_role["formal-st-runtime-prediction"])

    lookup: dict[tuple[str, int, int, int], dict[str, float]] = {}
    algorithms: set[str] = set()
    with timing_csv.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = csv.DictReader(stream)
        require(rows.fieldnames is not None, "timing CSV has no header")
        for row in rows:
            if row["designRegion"] != "core":
                continue
            algorithm = row["algorithmId"]
            g, n, f = int(row["G"]), int(row["N"]), int(row["F"])
            key = (algorithm, g, n, f)
            require(key not in lookup, f"duplicate core timing cell {key}")
            require(int(row["n"]) == 3, f"unexpected replicate count at {key}")
            lookup[key] = {
                "p50": float(row["processWallP50Milliseconds"]),
                "maximum": float(row["processWallMaximumMilliseconds"]),
            }
            algorithms.add(algorithm)

    algorithms_sorted = sorted(algorithms)
    require(len(algorithms_sorted) == ALGORITHM_COUNT, "algorithm cardinality mismatch")
    require(len(lookup) == ALGORITHM_COUNT * CELLS_PER_ALGORITHM, "core timing cell cardinality mismatch")
    for algorithm in algorithms_sorted:
        for g in OLD_LEVELS["G"]:
            for n in OLD_LEVELS["N"]:
                for f in OLD_LEVELS["F"]:
                    require((algorithm, g, n, f) in lookup, "incomplete observed factorial")

    gaps = gap_json["directlyMeasured"]["interProcessGapBeforeLane"]
    gap_p50 = float(gaps["p50Milliseconds"])
    gap_p99 = float(gaps["p99Milliseconds"])
    require(gaps["n"] == 972 and gap_p50 > 0 and gap_p99 > 0, "gap evidence mismatch")

    results = []
    per_candidate_cells = {}
    for candidate_id, gmax, nmax, fmax in CANDIDATES:
        validate_candidate(candidate_id, gmax, nmax, fmax)
        target_levels = {
            "G": FIXED_LEVELS["G"] + [gmax],
            "N": FIXED_LEVELS["N"] + [nmax],
            "F": FIXED_LEVELS["F"] + [fmax],
        }
        point_sum = 0.0
        conservative_sum = 0.0
        high_corner_rows = []
        for algorithm in algorithms_sorted:
            for g in target_levels["G"]:
                for n in target_levels["N"]:
                    for f in target_levels["F"]:
                        point = interpolate_log_duration(lookup, algorithm, g, n, f, "p50")
                        conservative = interpolate_log_duration(lookup, algorithm, g, n, f, "maximum")
                        point_sum += point
                        conservative_sum += conservative
                        if (g, n, f) == (gmax, nmax, fmax):
                            high_corner_rows.append({
                                "algorithmId": algorithm,
                                "estimatedP50Milliseconds": round(point, 6),
                                "estimatedMaximumMilliseconds": round(conservative, 6),
                            })

        point_hours_per_b = (point_sum + LANES_PER_B * gap_p50) / 3_600_000.0
        conservative_hours_per_b = (conservative_sum + LANES_PER_B * gap_p99) / 3_600_000.0
        planning_hours_per_b = conservative_hours_per_b * PLANNING_HEADROOM
        b36_point = point_hours_per_b * B_VALUE
        b36_conservative = conservative_hours_per_b * B_VALUE
        b36_planning = planning_hours_per_b * B_VALUE
        top_ratio = (gmax / 256.0) ** 2 * (nmax / 512.0) * (fmax / 225.0)
        result = {
            "candidateId": candidate_id,
            "GLevels": target_levels["G"],
            "NLevels": target_levels["N"],
            "FLevels": target_levels["F"],
            "GMaximum": gmax,
            "NMaximum": nmax,
            "FMaximum": fmax,
            "coreCells": CELLS_PER_ALGORITHM,
            "lanesPerB": LANES_PER_B,
            "unchangedCoreCells": 18 if candidate_id != "ORIGINAL_REFERENCE" else 48,
            "coreCellsWithAtLeastOneChangedMaximum": 30 if candidate_id != "ORIGINAL_REFERENCE" else 0,
            "highCornerStructuralProxyRatioToOriginal": round(top_ratio, 6),
            "highCornerStructuralProxyReductionPercent": round((1.0 - top_ratio) * 100.0, 3),
            "pointHoursPerB": round(point_hours_per_b, 6),
            "conservativeHoursPerB": round(conservative_hours_per_b, 6),
            "planningHoursPerBWith20PercentHeadroom": round(planning_hours_per_b, 6),
            "B36PointHours": round(b36_point, 3),
            "B36ConservativeHours": round(b36_conservative, 3),
            "B36PlanningHours": round(b36_planning, 3),
            "B36PlanningDays": round(b36_planning / 24.0, 3),
            "belowSevenDayGate": b36_planning < SEVEN_DAY_HOURS,
        }
        results.append(result)
        per_candidate_cells[candidate_id] = high_corner_rows

    original = results[0]
    prior_b36 = next(row for row in prior_prediction["rows"] if int(row["B"]) == 36)
    require(abs(original["B36PointHours"] - float(prior_b36["pointHours"])) <= 0.01, "reference point estimate does not replay")
    require(abs(original["B36ConservativeHours"] - float(prior_b36["conservativeHours"])) <= 0.01, "reference conservative estimate does not replay")
    require(abs(original["B36PlanningHours"] - float(prior_b36["planningWith20PercentHeadroomHours"])) <= 0.01, "reference planning estimate does not replay")

    for result in results:
        result["B36PlanningReductionVersusOriginalPercent"] = round(
            (1.0 - result["B36PlanningHours"] / original["B36PlanningHours"]) * 100.0, 3
        )

    recommended = next((row for row in results[1:] if row["belowSevenDayGate"]), None)
    recommendation_status = "PROPOSED_PENDING_USER_APPROVAL_AND_NEW_QUALIFICATION"
    if recommended is None:
        recommendation_status = "NO_PREDECLARED_CANDIDATE_MEETS_SEVEN_DAY_GATE"

    inventory_path = root / "input-file-inventory.v1.jsonl"
    with inventory_path.open("w", encoding="utf-8", newline="\n") as stream:
        for item in sorted(manifest["files"], key=lambda x: x["role"]):
            path = Path(item["absolutePath"])
            record = {
                "schema": "gate14re-me-gnf-load-redesign-input-file-v1",
                "role": item["role"],
                "absolutePath": str(path).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": item["sha256"],
            }
            stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")

    json_output = {
        "schema": SCHEMA,
        "studyId": "Gate14Re-ME",
        "redesignAttemptId": "gnf-load-redesign-v1-attempt-001",
        "status": "PASS_TIMING_ONLY_CANDIDATE_EVALUATION",
        "model": {
            "inputCoordinates": "log2(G), log2(N), log2(F)",
            "outputCoordinate": "natural log process-wall duration",
            "method": "multilinear interpolation within the observed old factorial envelope",
            "pointStatistic": "cell process-wall P50",
            "conservativeStatistic": "cell process-wall maximum",
            "gapP50Milliseconds": gap_p50,
            "gapP99Milliseconds": gap_p99,
            "planningHeadroomMultiplier": PLANNING_HEADROOM,
            "decisionGateHours": SEVEN_DAY_HOURS,
            "warning": "Planning surrogate only. New maxima are unobserved and require a new qualification."
        },
        "candidateResults": results,
        "estimatedHighCornerByAlgorithm": per_candidate_cells,
        "recommendationStatus": recommendation_status,
        "recommendedCandidateId": recommended["candidateId"] if recommended else None,
        "scientificBoundary": "No algorithm outcome observation, effect metric, rank, weight, or winner was read or produced."
    }
    dump_json(root / "candidate-runtime-estimates.v1.json", json_output)

    csv_fields = [
        "candidateId", "GMaximum", "NMaximum", "FMaximum",
        "highCornerStructuralProxyRatioToOriginal", "highCornerStructuralProxyReductionPercent",
        "pointHoursPerB", "conservativeHoursPerB", "planningHoursPerBWith20PercentHeadroom",
        "B36PointHours", "B36ConservativeHours", "B36PlanningHours", "B36PlanningDays",
        "B36PlanningReductionVersusOriginalPercent", "belowSevenDayGate",
    ]
    with (root / "candidate-runtime-estimates.v1.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=csv_fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(results)

    recommended_output = {
        "schema": "gate14re-me-recommended-gnf-design-v1",
        "studyId": "Gate14Re-ME",
        "redesignAttemptId": "gnf-load-redesign-v1-attempt-001",
        "status": recommendation_status,
        "candidate": recommended,
        "preserved": {
            "factorial": "3 x 4 x 4 = 48 core cells",
            "lowerGLevels": FIXED_LEVELS["G"],
            "lowerNLevels": FIXED_LEVELS["N"],
            "lowerFLevels": FIXED_LEVELS["F"],
            "coreSeedsPerCell": 3,
            "stressContextStrata": 18,
            "algorithmCount": 6,
            "strictSerialFreshProcessExecution": True,
        },
        "requiredBeforeExecution": [
            "explicit user approval of the exact proposed G, N, and F values",
            "new versioned scientific design and gate refreeze",
            "new planning inputs, schedule, identity binding, manifests, and implementation hashes",
            "read-only readiness validation",
            "new qualification evidence, measured, and delivery roots starting at ordinal 0"
        ],
        "notAuthorizedByThisArtifact": [
            "editing old frozen artifacts",
            "starting a new qualification",
            "starting formal ST, MQ, or MT",
            "changing formal sample size or scientific endpoints"
        ]
    }
    dump_json(root / "recommended-gnf-design.v1.json", recommended_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
