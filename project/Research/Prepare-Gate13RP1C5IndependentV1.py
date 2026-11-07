#!/usr/bin/env python3
"""Deterministically prepare the frozen Gate 13R P1-C5 independent study.

This program performs planning simulation and creates/validates the schedule only.
It never creates the formal raw root and never invokes Unity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from pathlib import Path
from typing import Any, Iterable


SOURCE_SCHEDULE_REL = "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
SOURCE_OVERLAY_REL = "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"
SOURCE_POWER_REL = "Research/Analysis/Gate13R_RQAligned_Preregistration/v1/candidate-design-sensitivity.json"
DESIGN_REL = "Research/Gate13R_P1C5_Independent_Design.v1.json"
SCHEDULE_REL = "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl"
OVERLAY_REL = "Research/Gate13R_P1C5_Independent_Schedule_Policy_Overlay.v1.jsonl"
SCHEDULE_MANIFEST_REL = "Research/Gate13R_P1C5_Independent_Schedule_Manifest.v1.json"
POWER_REPORT_REL = "Research/Gate13R_P1C5_Independent_Power_Simulation.v1.json"

CAMPAIGN_COUNT = 32
MINIMUM_BLOCKS_PER_CAMPAIGN = 50
ALPHA = 0.05
TARGET_POWER = 0.90
MDE_RATIO = 1.10
SIMULATION_REPLICATIONS = 200_000
SIMULATION_SEED = 13_125_010
PLANNING_SIGMA_UPPER = 1.1535914845489306
PLANNING_SIGMA_SOURCE_POINTER = (
    "/candidateRows/0/holmWorstThresholdPowerSensitivity/4/"
    "pilotResidualSigmaUpper90LogRatio"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def jsonl_bytes(values: Iterable[dict[str, Any]]) -> bytes:
    return b"".join(
        (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        for value in values
    )


def create_or_verify(path: Path, data: bytes) -> None:
    if path.exists():
        if path.read_bytes() != data:
            raise RuntimeError(f"frozen artifact exists with different bytes: {path}")
        return
    if not path.parent.is_dir():
        raise FileNotFoundError(path.parent)
    path.write_bytes(data)


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for line_number, line in enumerate(stream, start=1):
            if line.strip():
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise ValueError(f"JSONL record {line_number} is not an object: {path}")
                yield value


def beta_continued_fraction(a: float, b: float, x: float) -> float:
    maximum_iterations = 400
    epsilon = 3.0e-14
    tiny = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < tiny:
        d = tiny
    d = 1.0 / d
    h = d
    for iteration in range(1, maximum_iterations + 1):
        m2 = 2 * iteration
        aa = iteration * (b - iteration) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        h *= d * c
        aa = -(a + iteration) * (qab + iteration) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= epsilon:
            return h
    raise ArithmeticError("incomplete-beta continued fraction did not converge")


def regularized_incomplete_beta(a: float, b: float, x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log1p(-x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return front * beta_continued_fraction(a, b, x) / a
    return 1.0 - front * beta_continued_fraction(b, a, 1.0 - x) / b


def student_t_cdf(value: float, degrees_freedom: float) -> float:
    if degrees_freedom <= 0:
        raise ValueError("degrees of freedom must be positive")
    if value == 0.0:
        return 0.5
    x = degrees_freedom / (degrees_freedom + value * value)
    tail = 0.5 * regularized_incomplete_beta(degrees_freedom / 2.0, 0.5, x)
    return 1.0 - tail if value > 0 else tail


def student_t_ppf(probability: float, degrees_freedom: float) -> float:
    if not 0.0 < probability < 1.0:
        raise ValueError("probability must be between zero and one")
    if probability == 0.5:
        return 0.0
    if probability < 0.5:
        return -student_t_ppf(1.0 - probability, degrees_freedom)
    low, high = 0.0, 1.0
    while student_t_cdf(high, degrees_freedom) < probability:
        high *= 2.0
    for _ in range(100):
        midpoint = (low + high) / 2.0
        if student_t_cdf(midpoint, degrees_freedom) < probability:
            low = midpoint
        else:
            high = midpoint
    return (low + high) / 2.0


def wilson_lower(successes: int, trials: int, z: float = 1.6448536269514722) -> float:
    proportion = successes / trials
    denominator = 1.0 + z * z / trials
    center = proportion + z * z / (2.0 * trials)
    radius = z * math.sqrt(proportion * (1.0 - proportion) / trials + z * z / (4.0 * trials * trials))
    return (center - radius) / denominator


def simulate_rejection_rate(
    *, blocks_per_campaign: int, log_effect: float, seed: int
) -> dict[str, Any]:
    strata = CAMPAIGN_COUNT * 2
    observations_per_stratum = blocks_per_campaign // 2
    total_observations = CAMPAIGN_COUNT * blocks_per_campaign
    degrees_freedom = strata * (observations_per_stratum - 1)
    critical = student_t_ppf(1.0 - ALPHA / 2.0, degrees_freedom)
    noncentrality = math.sqrt(total_observations) * log_effect / PLANNING_SIGMA_UPPER
    generator = random.Random(seed)
    rejected = 0
    for _ in range(SIMULATION_REPLICATIONS):
        numerator = generator.gauss(noncentrality, 1.0)
        chi_square = generator.gammavariate(degrees_freedom / 2.0, 2.0)
        statistic = numerator / math.sqrt(chi_square / degrees_freedom)
        if abs(statistic) > critical:
            rejected += 1
    estimate = rejected / SIMULATION_REPLICATIONS
    return {
        "blocksPerCampaign": blocks_per_campaign,
        "campaignCount": CAMPAIGN_COUNT,
        "totalPairedBlocks": total_observations,
        "stratumCount": strata,
        "observationsPerCampaignOrderStratum": observations_per_stratum,
        "degreesFreedom": degrees_freedom,
        "criticalValue": critical,
        "trueLogRatio": log_effect,
        "noncentrality": noncentrality,
        "rejections": rejected,
        "replications": SIMULATION_REPLICATIONS,
        "estimate": estimate,
        "mcse": math.sqrt(estimate * (1.0 - estimate) / SIMULATION_REPLICATIONS),
        "oneSided95WilsonLower": wilson_lower(rejected, SIMULATION_REPLICATIONS),
        "seed": seed,
    }


def power_plan() -> dict[str, Any]:
    blocks_per_campaign = MINIMUM_BLOCKS_PER_CAMPAIGN
    iterations: list[dict[str, Any]] = []
    while True:
        if blocks_per_campaign % 2:
            raise AssertionError("AB/BA balance requires an even block count")
        negative = simulate_rejection_rate(
            blocks_per_campaign=blocks_per_campaign,
            log_effect=-math.log(MDE_RATIO),
            seed=SIMULATION_SEED + blocks_per_campaign * 10 + 1,
        )
        positive = simulate_rejection_rate(
            blocks_per_campaign=blocks_per_campaign,
            log_effect=math.log(MDE_RATIO),
            seed=SIMULATION_SEED + blocks_per_campaign * 10 + 2,
        )
        minimum_lower = min(negative["oneSided95WilsonLower"], positive["oneSided95WilsonLower"])
        iterations.append({
            "blocksPerCampaign": blocks_per_campaign,
            "negativeDirection": negative,
            "positiveDirection": positive,
            "minimumDirectionalOneSided95WilsonLower": minimum_lower,
            "targetPowerMet": minimum_lower >= TARGET_POWER,
        })
        if minimum_lower >= TARGET_POWER:
            break
        blocks_per_campaign += 2

    null = simulate_rejection_rate(
        blocks_per_campaign=blocks_per_campaign,
        log_effect=0.0,
        seed=SIMULATION_SEED + blocks_per_campaign * 10 + 3,
    )
    return {
        "schemaVersion": 1,
        "simulationKind": "gate13r-p1c5-independent-two-sided-power-freeze-v1",
        "deterministic": True,
        "distributionalPlanningModel": "homoscedastic-normal-log-ratio-with-pooled-within-campaign-order-variance",
        "alphaTwoSided": ALPHA,
        "targetPower": TARGET_POWER,
        "minimumDetectableRatioSymmetric": MDE_RATIO,
        "minimumDetectableLogMagnitude": math.log(MDE_RATIO),
        "planningSigmaUpperLogRatio": PLANNING_SIGMA_UPPER,
        "planningSigmaSource": {
            "relativePath": SOURCE_POWER_REL,
            "jsonPointer": PLANNING_SIGMA_SOURCE_POINTER,
            "selectionRule": "C5 pilot residual one-sided 90% upper sigma from the prospectively existing planning artifact",
        },
        "replicationsPerDirection": SIMULATION_REPLICATIONS,
        "baseSeed": SIMULATION_SEED,
        "minimumBlocksPerCampaign": MINIMUM_BLOCKS_PER_CAMPAIGN,
        "sampleSizeAdjustmentRule": "increase-by-two-only-if-minimum-directional-one-sided-95%-Wilson-lower-bound-is-below-0.90; never-decrease",
        "iterations": iterations,
        "selectedBlocksPerCampaign": blocks_per_campaign,
        "selectedTotalUnityProcesses": CAMPAIGN_COUNT * blocks_per_campaign,
        "selectedTotalAlgorithmSamples": CAMPAIGN_COUNT * blocks_per_campaign * 2,
        "selectedABBlocksPerCampaign": blocks_per_campaign // 2,
        "selectedBABlocksPerCampaign": blocks_per_campaign // 2,
        "nullTypeIErrorCheck": null,
        "passed": (
            iterations[-1]["targetPowerMet"]
            and abs(null["estimate"] - ALPHA) <= 0.005
        ),
    }


def select_source_campaigns(source_records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for record in source_records:
        if record.get("comparisonCohortId") != "four-algorithm-shared-goal-v1":
            continue
        campaign_id = str(record["campaignId"])
        if campaign_id not in selected:
            selected[campaign_id] = record
    records = sorted(selected.values(), key=lambda item: int(item["campaignOrdinal"]))
    if len(records) != CAMPAIGN_COUNT:
        raise RuntimeError(f"expected {CAMPAIGN_COUNT} frozen shared campaigns, found {len(records)}")
    return records


def algorithm_token(algorithm_id: str) -> str:
    return {"C-FF": "cff", "IDFF": "idff"}[algorithm_id]


def build_schedule(source_campaigns: list[dict[str, Any]], blocks_per_campaign: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    global_ordinal = 0
    for campaign_ordinal, source in enumerate(source_campaigns, start=1):
        source_campaign_ordinal = int(source["campaignOrdinal"])
        source_campaign_id = str(source["campaignId"])
        campaign_id = f"p1c5-{source_campaign_id}"
        source_entries = {str(entry["algorithmId"]): entry for entry in source["entries"]}
        if set(source_entries).issuperset({"C-FF", "IDFF"}) is False:
            raise RuntimeError(f"source campaign lacks C-FF/IDFF presets: {source_campaign_id}")
        for block in range(1, blocks_per_campaign + 1):
            global_ordinal += 1
            row_index = (block - 1) % 2
            order = ["C-FF", "IDFF"] if row_index == 0 else ["IDFF", "C-FF"]
            block_id = f"g13rp1c5-c{campaign_ordinal:02d}-b{block:04d}"
            output_relative = f"campaigns/c{campaign_ordinal:02d}-{campaign_id}/blocks/b{block:04d}"
            entries: list[dict[str, Any]] = []
            predecessor = "NONE"
            for position, algorithm_id in enumerate(order, start=1):
                source_entry = source_entries[algorithm_id]
                token = algorithm_token(algorithm_id)
                run_id = f"{block_id}-p{position:02d}-{token}"
                child_directory = f"runs/p{position:02d}-{token}"
                entries.append({
                    "position": position,
                    "algorithmId": algorithm_id,
                    "predecessorAlgorithmId": predecessor,
                    "runId": run_id,
                    "childDirectory": child_directory,
                    "sampleOutputRelativePath": f"{output_relative}/{child_directory}",
                    "presetId": source_entry["presetId"],
                    "presetAssetPath": source_entry["presetAssetPath"],
                    "presetAssetGuid": source_entry["presetAssetGuid"],
                    "presetSha256": source_entry["presetSha256"],
                })
                predecessor = algorithm_id
            records.append({
                "schemaVersion": 1,
                "scheduleKind": "gate13r-p1c5-independent-process-record-v1",
                "studyId": "Gate13R-P1C5-Independent-v1",
                "globalProcessOrdinal": global_ordinal,
                "campaignOrdinal": campaign_ordinal,
                "campaignId": campaign_id,
                "sourceCampaignOrdinal": source_campaign_ordinal,
                "sourceCampaignId": source_campaign_id,
                "scenarioId": source["scenarioId"],
                "scenarioRelativePath": source["scenarioRelativePath"],
                "scenarioSha256": source["scenarioSha256"],
                "scenarioFingerprintSha256": source["scenarioFingerprintSha256"],
                "sceneAssetPath": source["sceneAssetPath"],
                "profileAssetPath": source["profileAssetPath"],
                "profileAssetGuid": source["profileAssetGuid"],
                "profileSha256": source["profileSha256"],
                "comparisonCohortId": "p1-c5-shared-goal-v1",
                "campaignBlockOrdinal": block,
                "blockId": block_id,
                "williamsRowIndex": row_index,
                "orderLabel": "AB" if row_index == 0 else "BA",
                "outputRelativePath": output_relative,
                "expectedSampleCount": 2,
                "freshProcessRequired": True,
                "maximumBlocksInProcess": 1,
                "processIdentityPolicy": "assign-os-pid-plus-process-start-time-at-formal-execution",
                "matchedSuperblock": None,
                "entries": entries,
            })
    return records


def build_overlay(
    schedule: list[dict[str, Any]], source_overlay: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    by_scenario: dict[tuple[str, str], dict[str, Any]] = {}
    for item in source_overlay:
        key = (str(item["scenarioId"]), str(item["scenarioRelativePath"]))
        by_scenario.setdefault(key, item)
    result: list[dict[str, Any]] = []
    for record in schedule:
        key = (str(record["scenarioId"]), str(record["scenarioRelativePath"]))
        if key not in by_scenario:
            raise RuntimeError(f"no frozen MP2 mapping for scenario: {key}")
        source = by_scenario[key]
        result.append({
            "schemaVersion": 1,
            "overlayKind": "gate13r-p1c5-independent-schedule-policy-record-v1",
            "globalProcessOrdinal": record["globalProcessOrdinal"],
            "blockId": record["blockId"],
            "campaignId": record["campaignId"],
            "scenarioId": record["scenarioId"],
            "scenarioRelativePath": record["scenarioRelativePath"],
            "scenarioSourceSha256": record["scenarioSha256"],
            "expectedRunIds": [entry["runId"] for entry in record["entries"]],
            "policyId": source["policyId"],
            "tierId": source["tierId"],
            "canonicalMaximumGridDimension": source["canonicalMaximumGridDimension"],
            "nativeAdvisoryBytes": source["nativeAdvisoryBytes"],
            "nativeHardBytes": source["nativeHardBytes"],
            "hostAbsoluteNativeEmergencyBytes": source["hostAbsoluteNativeEmergencyBytes"],
            "hostRelativeNativeGrowthEmergencyBytes": source["hostRelativeNativeGrowthEmergencyBytes"],
            "hostAvailablePhysicalMemoryFloorBytes": source["hostAvailablePhysicalMemoryFloorBytes"],
        })
    return result


def verify_design(project: Path) -> dict[str, Any]:
    design = json.loads((project / DESIGN_REL).read_text(encoding="utf-8-sig"))
    required = {
        "alphaTwoSided": ALPHA,
        "targetPower": TARGET_POWER,
        "minimumDetectableRatioSymmetric": MDE_RATIO,
        "campaignCount": CAMPAIGN_COUNT,
        "minimumBlocksPerCampaign": MINIMUM_BLOCKS_PER_CAMPAIGN,
    }
    for key, expected in required.items():
        if design.get(key) != expected:
            raise RuntimeError(f"design mismatch for {key}: {design.get(key)!r} != {expected!r}")
    return design


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    design = verify_design(project)

    source_schedule_path = project / SOURCE_SCHEDULE_REL
    source_overlay_path = project / SOURCE_OVERLAY_REL
    source_power_path = project / SOURCE_POWER_REL
    for path in (source_schedule_path, source_overlay_path, source_power_path):
        if not path.is_file():
            raise FileNotFoundError(path)

    source_power = json.loads(source_power_path.read_text(encoding="utf-8-sig"))
    observed_sigma = source_power["candidateRows"][0]["holmWorstThresholdPowerSensitivity"][4]["pilotResidualSigmaUpper90LogRatio"]
    if not math.isclose(float(observed_sigma), PLANNING_SIGMA_UPPER, rel_tol=0.0, abs_tol=1e-15):
        raise RuntimeError("planning sigma source value changed")

    power = power_plan()
    if not power["passed"]:
        raise RuntimeError("deterministic power/type-I planning gate did not pass")
    if power["selectedBlocksPerCampaign"] < MINIMUM_BLOCKS_PER_CAMPAIGN:
        raise RuntimeError("power planning illegally reduced sample size")
    if power["selectedBlocksPerCampaign"] != int(design["selectedBlocksPerCampaignAfterSimulation"]):
        raise RuntimeError("design does not match deterministic selected block count")

    source_campaigns = select_source_campaigns(list(iter_jsonl(source_schedule_path)))
    schedule = build_schedule(source_campaigns, power["selectedBlocksPerCampaign"])
    overlay = build_overlay(schedule, list(iter_jsonl(source_overlay_path)))
    schedule_data = jsonl_bytes(schedule)
    overlay_data = jsonl_bytes(overlay)
    power_data = json_bytes(power)

    schedule_manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-p1c5-independent-schedule-manifest-v1",
        "studyId": "Gate13R-P1C5-Independent-v1",
        "campaignCount": CAMPAIGN_COUNT,
        "blocksPerCampaign": power["selectedBlocksPerCampaign"],
        "unityProcessCount": len(schedule),
        "algorithmSampleCount": sum(int(item["expectedSampleCount"]) for item in schedule),
        "abProcessCount": sum(item["orderLabel"] == "AB" for item in schedule),
        "baProcessCount": sum(item["orderLabel"] == "BA" for item in schedule),
        "scheduleRelativePath": SCHEDULE_REL,
        "scheduleSha256": sha256_bytes(schedule_data),
        "policyOverlayRelativePath": OVERLAY_REL,
        "policyOverlaySha256": sha256_bytes(overlay_data),
        "sourceScheduleRelativePath": SOURCE_SCHEDULE_REL,
        "sourceScheduleSha256": sha256_file(source_schedule_path),
        "sourcePolicyOverlayRelativePath": SOURCE_OVERLAY_REL,
        "sourcePolicyOverlaySha256": sha256_file(source_overlay_path),
        "powerReportRelativePath": POWER_REPORT_REL,
        "powerReportSha256": sha256_bytes(power_data),
        "freshUnityProcessPerCompletePairBlock": True,
        "attempt4RawDataMerged": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
    }

    create_or_verify(project / POWER_REPORT_REL, power_data)
    create_or_verify(project / SCHEDULE_REL, schedule_data)
    create_or_verify(project / OVERLAY_REL, overlay_data)
    create_or_verify(project / SCHEDULE_MANIFEST_REL, json_bytes(schedule_manifest))

    result = {
        "passed": True,
        "unityInvoked": False,
        "formalRawRootCreated": False,
        "selectedBlocksPerCampaign": power["selectedBlocksPerCampaign"],
        "unityProcessCount": len(schedule),
        "algorithmSampleCount": schedule_manifest["algorithmSampleCount"],
        "minimumDirectionalPowerLower": power["iterations"][-1]["minimumDirectionalOneSided95WilsonLower"],
        "scheduleSha256": schedule_manifest["scheduleSha256"],
        "policyOverlaySha256": schedule_manifest["policyOverlaySha256"],
        "powerReportSha256": schedule_manifest["powerReportSha256"],
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
