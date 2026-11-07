#!/usr/bin/env python3
"""Runtime planning surrogate for the proposed 3 x 3 x 4 G/N/F window."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


OLD = {"G": [64, 128, 256], "N": [8, 32, 128, 512], "F": [1, 9, 81, 225]}
EXPECTED = {"G": [64, 96, 128], "N": [32, 64, 128], "F": [1, 9, 25, 81]}
ALGORITHM_COUNT = 6
CORE_CELLS = 36
LANES_PER_B = 216
B = 36
CORE_QUALIFICATION_B = 3
STRESS_SUPERBLOCKS = 18
QUALIFICATION_ORACLE_PROCESSES = 126
QUALIFICATION_LANES = 756
QUALIFICATION_TOTAL_PROCESSES = 895
HEADROOM = 1.20


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


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


def axis_weights(target: int, observed: list[int]) -> list[tuple[int, float]]:
    if target in observed:
        return [(target, 1.0)]
    for lower, upper in zip(observed, observed[1:]):
        if lower < target < upper:
            x, lo, hi = math.log2(target), math.log2(lower), math.log2(upper)
            upper_weight = (x - lo) / (hi - lo)
            return [(lower, 1.0 - upper_weight), (upper, upper_weight)]
    raise RuntimeError(f"target {target} outside interpolation envelope {observed}")


def interpolate(lookup, algorithm, g, n, f, field):
    weighted_log = 0.0
    total_weight = 0.0
    for source_g, wg in axis_weights(g, OLD["G"]):
        for source_n, wn in axis_weights(n, OLD["N"]):
            for source_f, wf in axis_weights(f, OLD["F"]):
                weight = wg * wn * wf
                value = lookup[(algorithm, source_g, source_n, source_f)][field]
                require(math.isfinite(value) and value > 0.0, "invalid timing value")
                weighted_log += weight * math.log(value)
                total_weight += weight
    require(abs(total_weight - 1.0) < 1e-12, "interpolation weights do not sum to one")
    return math.exp(weighted_log)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    freeze = load_json(root / "runtime-freeze-manifest.v2.json")
    require(freeze["schema"] == "gate14re-me-gnf-window-runtime-freeze-manifest-v2", "freeze schema mismatch")
    for item in freeze["files"]:
        path = Path(item["absolutePath"])
        require(path.is_file(), f"missing frozen input: {path}")
        require(path.stat().st_size == int(item["bytes"]), f"size mismatch: {path}")
        require(sha256(path) == item["sha256"], f"hash mismatch: {path}")
    by_role = {item["role"]: Path(item["absolutePath"]) for item in freeze["files"]}

    design = load_json(by_role["selected-gnf-design"])
    levels = design["levels"]
    require(levels == EXPECTED, "selected levels mismatch")
    structure = design["structure"]
    require(int(structure["coreCells"]) == CORE_CELLS, "core-cell mismatch")
    require(int(structure["qualificationTotalFreshProcesses"]) == QUALIFICATION_TOTAL_PROCESSES, "process-count mismatch")

    named_rows = []
    with by_role["algorithm-gnf-runtime-cells"].open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["designRegion"] == "core":
                named_rows.append(row)
    names = sorted({row["algorithmId"] for row in named_rows})
    require(len(names) == ALGORITHM_COUNT, "algorithm cardinality mismatch")
    anonymous = {name: f"A{index + 1}" for index, name in enumerate(names)}
    lookup = {}
    for row in named_rows:
        key = (anonymous[row["algorithmId"]], int(row["G"]), int(row["N"]), int(row["F"]))
        require(key not in lookup and int(row["n"]) == 3, "timing cell mismatch")
        lookup[key] = {
            "p50": float(row["processWallP50Milliseconds"]),
            "maximum": float(row["processWallMaximumMilliseconds"]),
        }
    require(len(lookup) == ALGORITHM_COUNT * 48, "old timing lookup cardinality mismatch")

    gap = load_json(by_role["time-component-identifiability"])["directlyMeasured"]["interProcessGapBeforeLane"]
    gap_p50 = float(gap["p50Milliseconds"])
    gap_p99 = float(gap["p99Milliseconds"])
    require(int(gap["n"]) == 972, "old gap evidence mismatch")

    point_per_b = 0.0
    conservative_per_b = 0.0
    high_point = []
    high_conservative = []
    algorithms = sorted(set(anonymous.values()))
    for algorithm in algorithms:
        for g in levels["G"]:
            for n in levels["N"]:
                for f in levels["F"]:
                    p50 = interpolate(lookup, algorithm, g, n, f, "p50")
                    maximum = interpolate(lookup, algorithm, g, n, f, "maximum")
                    point_per_b += p50
                    conservative_per_b += maximum
                    if (g, n, f) == (128, 128, 81):
                        high_point.append(p50)
                        high_conservative.append(maximum)

    require(len(high_point) == ALGORITHM_COUNT, "high-corner cardinality mismatch")
    point_hours_per_b = (point_per_b + LANES_PER_B * gap_p50) / 3_600_000.0
    conservative_hours_per_b = (conservative_per_b + LANES_PER_B * gap_p99) / 3_600_000.0
    formal_point = point_hours_per_b * B
    formal_conservative = conservative_hours_per_b * B
    formal_planning = formal_conservative * HEADROOM

    old_runtime = load_json(by_role["anonymous-runtime-prediction"])
    throughput = old_runtime["throughput"]
    fixed_non_lane_hours = float(throughput["fullElapsedHours"]) - float(throughput["lanePhaseElapsedHours"])
    require(fixed_non_lane_hours > 0.0, "fixed non-lane remainder invalid")
    stress_point = STRESS_SUPERBLOCKS * sum(high_point)
    stress_conservative = STRESS_SUPERBLOCKS * sum(high_conservative)
    qualification_point_lane_hours = (
        CORE_QUALIFICATION_B * point_per_b + stress_point + QUALIFICATION_LANES * gap_p50
    ) / 3_600_000.0
    qualification_conservative_lane_hours = (
        CORE_QUALIFICATION_B * conservative_per_b + stress_conservative + QUALIFICATION_LANES * gap_p99
    ) / 3_600_000.0
    qualification_point = fixed_non_lane_hours + qualification_point_lane_hours
    qualification_conservative = fixed_non_lane_hours + qualification_conservative_lane_hours
    qualification_planning = qualification_conservative * HEADROOM

    output = {
        "schema": "gate14re-me-selected-window-runtime-estimate-v2",
        "studyId": "Gate14Re-ME",
        "designAttemptId": "gnf-discrimination-window-design-v2-attempt-001",
        "status": "PASS_PLANNING_SURROGATE_NEW_LEVELS_NOT_YET_QUALIFIED",
        "levels": levels,
        "structure": {
            "coreCells": CORE_CELLS,
            "qualificationOracleProcesses": QUALIFICATION_ORACLE_PROCESSES,
            "qualificationAlgorithmLanes": QUALIFICATION_LANES,
            "qualificationTotalFreshProcesses": QUALIFICATION_TOTAL_PROCESSES,
            "formalB36AlgorithmProcesses": B * LANES_PER_B,
        },
        "method": {
            "inputCoordinates": "log2(G), log2(N), log2(F)",
            "outputCoordinate": "natural log process-wall duration",
            "gapP50Milliseconds": gap_p50,
            "gapP99Milliseconds": gap_p99,
            "fixedOldNonLaneRemainderHoursRetained": round(fixed_non_lane_hours, 6),
            "planningHeadroomMultiplier": HEADROOM,
            "algorithmIdentitiesEmitted": False,
        },
        "highCorner": {
            "G": 128,
            "N": 128,
            "F": 81,
            "maximumAcrossAnonymousAlgorithmsP50Seconds": round(max(high_point) / 1000.0, 6),
            "maximumAcrossAnonymousAlgorithmsConservativeSeconds": round(max(high_conservative) / 1000.0, 6),
            "observedCellWorstProcessWallSeconds": 117.611215,
        },
        "newQualification": {
            "pointHours": round(qualification_point, 3),
            "conservativeHours": round(qualification_conservative, 3),
            "planningWith20PercentHeadroomHours": round(qualification_planning, 3),
        },
        "formalSTB36": {
            "pointHours": round(formal_point, 3),
            "conservativeHours": round(formal_conservative, 3),
            "planningWith20PercentHeadroomHours": round(formal_planning, 3),
            "planningDays": round(formal_planning / 24.0, 3),
            "belowSevenDayDecisionGate": formal_planning < 168.0,
        },
        "boundary": [
            "G96, N64, and F25 are interpolated planning points and remain unqualified.",
            "The old fixed non-lane remainder is retained in full even though the new oracle count is lower.",
            "No new qualification or formal execution was started."
        ],
        "rankingOrWinnerProduced": False,
    }
    dump_json(root / "selected-window-runtime-estimate.v2.json", output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
