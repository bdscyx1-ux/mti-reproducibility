#!/usr/bin/env python3
"""Evaluate the predeclared balanced-axis G/N/F maximum proposals."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path


CANDIDATES = [
    ("ORIGINAL_REFERENCE", 256, 512, 225),
    ("PRIMARY_AXIS_BALANCED", 192, 192, 121),
    ("MARGIN_F144", 176, 192, 144),
    ("HIGHER_F_SPAN", 176, 192, 169),
    ("MAXIMUM_MARGIN", 160, 192, 100),
]
OLD_MAX = (256, 512, 225)
B = 36
LANES_PER_B = 288
QUALIFICATION_LANES = 972
HEADROOM = 1.20
GATE_HOURS = 168.0


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    freeze = load_json(root / "pre-computation-freeze-manifest.v2.json")
    require(freeze["schema"] == "gate14re-me-gnf-load-redesign-pre-computation-freeze-manifest-v2", "freeze schema mismatch")
    for item in freeze["files"]:
        path = Path(item["absolutePath"])
        require(path.is_file(), f"missing frozen input: {path}")
        require(path.stat().st_size == int(item["bytes"]), f"size mismatch: {path}")
        require(sha256(path) == item["sha256"], f"hash mismatch: {path}")
    by_role = {item["role"]: Path(item["absolutePath"]) for item in freeze["files"]}

    spec = importlib.util.spec_from_file_location("gnf_v1", by_role["v1-evaluation-script"])
    require(spec is not None and spec.loader is not None, "cannot load frozen v1 interpolation implementation")
    v1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(v1)

    core = {}
    stress = {}
    algorithms = set()
    with by_role["algorithm-gnf-runtime-cells"].open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            algorithm = row["algorithmId"]
            algorithms.add(algorithm)
            values = {
                "p50": float(row["processWallP50Milliseconds"]),
                "maximum": float(row["processWallMaximumMilliseconds"]),
            }
            if row["designRegion"] == "core":
                key = (algorithm, int(row["G"]), int(row["N"]), int(row["F"]))
                require(key not in core and int(row["n"]) == 3, f"invalid core cell {key}")
                core[key] = values
            elif row["designRegion"] == "stress":
                require(algorithm not in stress and int(row["n"]) == 18, f"invalid stress row {algorithm}")
                stress[algorithm] = values
            else:
                raise RuntimeError("unexpected design region")

    algorithms = sorted(algorithms)
    require(len(algorithms) == 6 and len(core) == 288 and len(stress) == 6, "timing cardinality mismatch")
    gap = load_json(by_role["time-component-identifiability"])["directlyMeasured"]["interProcessGapBeforeLane"]
    gap_p50 = float(gap["p50Milliseconds"])
    gap_p99 = float(gap["p99Milliseconds"])
    prior_prediction = load_json(by_role["formal-st-runtime-prediction"])
    anonymous = load_json(by_role["anonymous-runtime-prediction"])

    results = []
    high_corner_details = {}
    for candidate_id, gmax, nmax, fmax in CANDIDATES:
        if candidate_id != "ORIGINAL_REFERENCE":
            require(128 < gmax < 256 and 128 < nmax < 512 and 81 < fmax < 225, "new maximum is not strictly interior")
            require(fmax >= 16 and int(math.isqrt(fmax)) ** 2 == fmax, "F maximum must retain partition feasibility and be square")
        levels_g = [64, 128, gmax]
        levels_n = [8, 32, 128, nmax]
        levels_f = [1, 9, 81, fmax]
        formal_p50_sum = 0.0
        formal_max_sum = 0.0
        qualification_core_p50_sum = 0.0
        qualification_core_max_sum = 0.0
        qualification_stress_p50_sum = 0.0
        qualification_stress_max_sum = 0.0
        corner = []
        for algorithm in algorithms:
            for g in levels_g:
                for n in levels_n:
                    for f in levels_f:
                        p50 = v1.interpolate_log_duration(core, algorithm, g, n, f, "p50")
                        maximum = v1.interpolate_log_duration(core, algorithm, g, n, f, "maximum")
                        formal_p50_sum += p50
                        formal_max_sum += maximum
                        qualification_core_p50_sum += 3.0 * p50
                        qualification_core_max_sum += 3.0 * maximum
                        if (g, n, f) == (gmax, nmax, fmax):
                            old_core = core[(algorithm, *OLD_MAX)]
                            stress_p50_ratio = stress[algorithm]["p50"] / old_core["p50"]
                            stress_max_ratio = stress[algorithm]["maximum"] / old_core["maximum"]
                            qualification_stress_p50_sum += 18.0 * p50 * stress_p50_ratio
                            qualification_stress_max_sum += 18.0 * maximum * stress_max_ratio
                            corner.append({
                                "algorithmId": algorithm,
                                "estimatedCoreP50Milliseconds": round(p50, 6),
                                "estimatedCoreMaximumMilliseconds": round(maximum, 6),
                                "oldStressToCoreP50Ratio": round(stress_p50_ratio, 6),
                                "oldStressToCoreMaximumRatio": round(stress_max_ratio, 6),
                            })

        point_per_b = (formal_p50_sum + LANES_PER_B * gap_p50) / 3_600_000.0
        conservative_per_b = (formal_max_sum + LANES_PER_B * gap_p99) / 3_600_000.0
        b36_point = point_per_b * B
        b36_conservative = conservative_per_b * B
        b36_planning = b36_conservative * HEADROOM
        qualification_point = (
            qualification_core_p50_sum + qualification_stress_p50_sum + QUALIFICATION_LANES * gap_p50
        ) / 3_600_000.0
        qualification_conservative = (
            qualification_core_max_sum + qualification_stress_max_sum + QUALIFICATION_LANES * gap_p99
        ) / 3_600_000.0
        upper_ratios = {"G": gmax / 128.0, "N": nmax / 128.0, "F": fmax / 81.0}
        old_total_spans = {
            "D7_log2_GSquared": 2.0 * math.log2(256.0 / 64.0),
            "D5_log2_N": math.log2(512.0 / 8.0),
            "D6_log2_F": math.log2(225.0 / 1.0),
        }
        new_total_spans = {
            "D7_log2_GSquared": 2.0 * math.log2(gmax / 64.0),
            "D5_log2_N": math.log2(nmax / 8.0),
            "D6_log2_F": math.log2(fmax / 1.0),
        }
        span_retention = {
            key: round(new_total_spans[key] / old_total_spans[key], 6) for key in old_total_spans
        }
        structural_ratio = (gmax / 256.0) ** 2 * (nmax / 512.0) * (fmax / 225.0)
        results.append({
            "candidateId": candidate_id,
            "GLevels": levels_g,
            "NLevels": levels_n,
            "FLevels": levels_f,
            "GMaximum": gmax,
            "NMaximum": nmax,
            "FMaximum": fmax,
            "upperStepRatios": {key: round(value, 6) for key, value in upper_ratios.items()},
            "totalScalingAxisSpanRetention": span_retention,
            "highCornerStructuralProxyRatioToOriginal": round(structural_ratio, 6),
            "highCornerStructuralProxyReductionPercent": round((1.0 - structural_ratio) * 100.0, 3),
            "B36PointHours": round(b36_point, 3),
            "B36ConservativeHours": round(b36_conservative, 3),
            "B36PlanningHours": round(b36_planning, 3),
            "B36PlanningDays": round(b36_planning / 24.0, 3),
            "belowSevenDayGate": b36_planning < GATE_HOURS,
            "qualificationLaneStagePointHours": round(qualification_point, 3),
            "qualificationLaneStageConservativeHours": round(qualification_conservative, 3),
            "qualificationLaneStagePlanningHours": round(qualification_conservative * HEADROOM, 3),
        })
        high_corner_details[candidate_id] = corner

    reference = results[0]
    prior_b36 = next(row for row in prior_prediction["rows"] if int(row["B"]) == B)
    require(abs(reference["B36PointHours"] - float(prior_b36["pointHours"])) <= 0.01, "point replay mismatch")
    require(abs(reference["B36PlanningHours"] - float(prior_b36["planningWith20PercentHeadroomHours"])) <= 0.01, "planning replay mismatch")
    require(abs(reference["qualificationLaneStagePointHours"] - 25.025) <= 0.01, "qualification lane-stage reference replay mismatch")
    actual_lane_phase = float(anonymous["throughput"]["lanePhaseElapsedHours"])
    replay_ratio = actual_lane_phase / reference["qualificationLaneStagePointHours"]

    for row in results:
        row["B36PlanningReductionVersusOriginalPercent"] = round(
            (1.0 - row["B36PlanningHours"] / reference["B36PlanningHours"]) * 100.0, 3
        )
        row["qualificationLaneStagePointReplayCalibratedHours"] = round(
            row["qualificationLaneStagePointHours"] * replay_ratio, 3
        )

    ordered = results[1:]
    recommended = ordered[0] if ordered[0]["belowSevenDayGate"] else next(
        (row for row in ordered[1:] if row["belowSevenDayGate"]), None
    )
    status = "PROPOSED_PENDING_USER_APPROVAL_AND_NEW_QUALIFICATION" if recommended else "NO_V2_CANDIDATE_BELOW_SEVEN_DAY_GATE"

    output = {
        "schema": "gate14re-me-balanced-axis-candidate-evaluation-v2",
        "studyId": "Gate14Re-ME",
        "redesignAttemptId": "gnf-load-redesign-v2-attempt-001",
        "status": "PASS_TIMING_ONLY_V2_EVALUATION",
        "candidateResults": results,
        "highCornerEngineeringTimingEstimates": high_corner_details,
        "referenceReplay": {
            "actualOldLanePhaseHours": actual_lane_phase,
            "modeledOldLaneStagePointHours": reference["qualificationLaneStagePointHours"],
            "actualToModeledRatio": round(replay_ratio, 6),
        },
        "recommendedCandidateId": recommended["candidateId"] if recommended else None,
        "recommendationStatus": status,
        "warnings": [
            "All candidate timings are interpolated rather than measured.",
            "Qualification estimates cover the 972-lane stage and its gaps only; they exclude instrument, oracle, empty-boundary, validation, delivery, and finalization.",
            "No candidate is executable until an explicit approval, a new design/implementation refreeze, readiness PASS, and a fresh qualification from ordinal 0."
        ],
        "scientificOutcomeObservationsRead": False,
    }
    dump_json(root / "balanced-axis-candidate-evaluation.v2.json", output)

    csv_fields = [
        "candidateId", "GMaximum", "NMaximum", "FMaximum",
        "highCornerStructuralProxyRatioToOriginal", "highCornerStructuralProxyReductionPercent",
        "B36PointHours", "B36ConservativeHours", "B36PlanningHours", "B36PlanningDays",
        "B36PlanningReductionVersusOriginalPercent", "belowSevenDayGate",
        "qualificationLaneStagePointHours", "qualificationLaneStagePointReplayCalibratedHours",
        "qualificationLaneStageConservativeHours", "qualificationLaneStagePlanningHours",
    ]
    with (root / "balanced-axis-candidate-evaluation.v2.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=csv_fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(results)

    recommendation = {
        "schema": "gate14re-me-recommended-gnf-design-v2",
        "studyId": "Gate14Re-ME",
        "redesignAttemptId": "gnf-load-redesign-v2-attempt-001",
        "status": status,
        "recommendedCandidate": recommended,
        "highCornerStress": {
            "G": recommended["GMaximum"] if recommended else None,
            "N": recommended["NMaximum"] if recommended else None,
            "F": recommended["FMaximum"] if recommended else None,
        },
        "lowAnchorUnchanged": {"G": 64, "N": 8, "F": 1},
        "highAnchorMustChangeWithApprovedMaxima": True,
        "preservedCardinality": {
            "coreCells": 48,
            "coreSuperblocks": 144,
            "stressSuperblocks": 18,
            "totalSuperblocks": 162,
            "algorithmLanes": 972,
            "totalFreshProcesses": 1147,
        },
        "approvalAndRefreezeRequired": True,
        "newQualificationMustStartAtOrdinalZero": True,
        "oldSealedDataReusableAsNewQualificationSamples": False,
    }
    dump_json(root / "recommended-gnf-design.v2.json", recommendation)

    with (root / "input-file-inventory.v2.jsonl").open("w", encoding="utf-8", newline="\n") as stream:
        for item in sorted(freeze["files"], key=lambda value: value["role"]):
            record = {
                "schema": "gate14re-me-gnf-load-redesign-input-file-v2",
                "role": item["role"],
                "absolutePath": str(Path(item["absolutePath"])).replace("\\", "/"),
                "bytes": int(item["bytes"]),
                "sha256": item["sha256"],
            }
            stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
