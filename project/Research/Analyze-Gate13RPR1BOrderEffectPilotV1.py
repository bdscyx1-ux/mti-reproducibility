#!/usr/bin/env python3
"""Analyze the frozen Gate 13R-PR1B mirrored AB/BA supplemental pilot.

This module uses only the Python standard library so its execution environment is
easy to reproduce.  It never launches Unity and never reads Gate 12R v4 samples.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import statistics
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple


PLAN_ID = "gate13r-pr1b-balanced-mirrored-order-effect-pilot-v1"
DESIGN_ID = "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1"
SCENARIOS = (
    "core-r01-s1-hetero",
    "core-r07-s2-hetero",
    "goal-count-g32-hetero",
)
CONTRASTS = {
    "C1": ("C-FF", "A*-R"),
    "C2": ("C-FF", "D*L"),
    "C3": ("IDFF", "A*-R"),
    "C4": ("IDFF", "D*L"),
}
CONTINUOUS_METRICS = ("P1", "P2", "P3", "P4")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def canonical_json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def write_atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = canonical_json_text(value)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def finite_positive(value: Any, label: str) -> float:
    result = float(value)
    require(math.isfinite(result) and result > 0.0, f"{label} must be finite and positive")
    return result


def mean(values: Sequence[float]) -> float:
    require(len(values) > 0, "mean requires values")
    return math.fsum(values) / len(values)


def sample_sd(values: Sequence[float]) -> float:
    require(len(values) >= 2, "sample SD requires at least two values")
    return statistics.stdev(values)


def percentile_linear(sorted_values: Sequence[float], probability: float) -> float:
    require(len(sorted_values) > 0, "percentile requires values")
    require(0.0 <= probability <= 1.0, "invalid percentile probability")
    if len(sorted_values) == 1:
        return float(sorted_values[0])
    position = probability * (len(sorted_values) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return float(sorted_values[lower])
    fraction = position - lower
    return float(sorted_values[lower] * (1.0 - fraction) + sorted_values[upper] * fraction)


def pearson(x: Sequence[float], y: Sequence[float]) -> float | None:
    require(len(x) == len(y), "correlation vectors differ in length")
    if len(x) < 2:
        return None
    mx, my = mean(x), mean(y)
    cross = math.fsum((a - mx) * (b - my) for a, b in zip(x, y))
    sx = math.fsum((a - mx) ** 2 for a in x)
    sy = math.fsum((b - my) ** 2 for b in y)
    if sx <= 0.0 or sy <= 0.0:
        return None
    return cross / math.sqrt(sx * sy)


def stable_seed(base: int, key: str) -> int:
    return base + int(hashlib.sha256(key.encode("utf-8")).hexdigest()[:12], 16)


def bootstrap_mean_ci(values: Sequence[float], replicates: int, seed: int) -> List[float]:
    require(len(values) > 0 and replicates > 0, "invalid bootstrap inputs")
    rng = random.Random(seed)
    n = len(values)
    estimates = [mean([values[rng.randrange(n)] for _ in range(n)]) for _ in range(replicates)]
    estimates.sort()
    return [percentile_linear(estimates, 0.025), percentile_linear(estimates, 0.975)]


def stratified_equal_scenario_bootstrap_ci(
    by_scenario: Mapping[str, Sequence[float]], replicates: int, seed: int
) -> List[float]:
    require(set(by_scenario) == set(SCENARIOS), "pooled bootstrap scenario set mismatch")
    rng = random.Random(seed)
    estimates: List[float] = []
    for _ in range(replicates):
        scenario_means: List[float] = []
        for scenario in SCENARIOS:
            values = by_scenario[scenario]
            require(len(values) == 32, f"{scenario} must have 32 mirrored pairs")
            scenario_means.append(mean([values[rng.randrange(len(values))] for _ in range(len(values))]))
        estimates.append(mean(scenario_means))
    estimates.sort()
    return [percentile_linear(estimates, 0.025), percentile_linear(estimates, 0.975)]


def classify_interval(point: float, low: float, high: float, bound: float) -> str:
    require(low <= point <= high and bound > 0.0, "invalid classification interval")
    if low >= -bound and high <= bound:
        return "ORDER-EFFECT-BOUNDED"
    excludes_zero = low > 0.0 or high < 0.0
    if excludes_zero and abs(point) > bound:
        return "MATERIAL-ORDER-EFFECT"
    if excludes_zero and abs(point) <= bound:
        return "DETECTABLE-BUT-BELOW-BOUND"
    return "INCONCLUSIVE"


def summarize_differences(
    values: Sequence[float],
    ab_log_ratios: Sequence[float],
    ba_log_ratios: Sequence[float],
    waves: Sequence[int],
    t_critical: float,
    bound: float,
    replicates: int,
    seed: int,
) -> Dict[str, Any]:
    require(len(values) == len(ab_log_ratios) == len(ba_log_ratios) == len(waves), "summary vectors differ")
    n = len(values)
    require(n in (32, 96), f"unexpected diagnostic cluster count: {n}")
    point = mean(values)
    sd = sample_sd(values)
    se = sd / math.sqrt(n)
    low, high = point - t_critical * se, point + t_critical * se
    bootstrap = bootstrap_mean_ci(values, replicates, seed)
    return {
        "nMirroredPairs": n,
        "meanOrderEffectLog": point,
        "sampleSdLog": sd,
        "standardError": se,
        "tCritical": t_critical,
        "t95CiLog": [low, high],
        "multiplicativeOrderEffect": math.exp(point),
        "t95CiMultiplicative": [math.exp(low), math.exp(high)],
        "bootstrap95CiLog": bootstrap,
        "bootstrap95CiMultiplicative": [math.exp(bootstrap[0]), math.exp(bootstrap[1])],
        "abGeometricSystemRatio": math.exp(mean(ab_log_ratios)),
        "baGeometricSystemRatio": math.exp(mean(ba_log_ratios)),
        "waveCorrelation": pearson([float(v) for v in values], [float(v) for v in waves]),
        "absoluteLogBound": bound,
        "multiplicativeBound": math.exp(bound),
        "classification": classify_interval(point, low, high, bound),
    }


def metrics_from_workload(workload: Mapping[str, Any]) -> Dict[str, Any]:
    scheduled = int(workload["scheduledEventCount"])
    require(scheduled > 0, "scheduledEventCount must be positive")
    dynamic_allocated = int(workload["dynamicManagedAllocatedBytes"])
    require(dynamic_allocated >= 0, "dynamicManagedAllocatedBytes is negative")
    plan_count = int(workload["planOperationCount"])
    repair_count = int(workload["repairOperationCount"])
    exceeded = int(workload["budgetExceededOperationCount"])
    exceeded_plan = int(workload["budgetExceededPlanCount"])
    require(plan_count >= 0 and repair_count >= 0 and exceeded >= 0 and exceeded_plan >= 0, "negative P5 count")
    require(exceeded_plan <= plan_count and exceeded_plan <= exceeded, "invalid plan-overrun count")
    exceeded_repair = exceeded - exceeded_plan
    require(exceeded_repair <= repair_count, "invalid derived repair-overrun count")
    eligible = plan_count + repair_count
    require(eligible > 0 and exceeded <= eligible, "invalid overall P5 denominator/count")
    return {
        "P1": finite_positive(workload["dynamicHandlingMillisecondsPerScheduledEvent"], "P1"),
        "P2": finite_positive(workload["dynamicHandlingP95Milliseconds"], "P2"),
        "P3": finite_positive(workload["totalPlannerElapsedMillisecondsPerAgent"], "P3"),
        "P4": finite_positive(dynamic_allocated / scheduled, "P4"),
        "P5": {
            "eligibleOverall": eligible,
            "exceededOverall": exceeded,
            "eligiblePlan": plan_count,
            "exceededPlan": exceeded_plan,
            "eligibleRepair": repair_count,
            "exceededRepair": exceeded_repair,
        },
    }


def load_process_samples(project: Path, entry: Mapping[str, Any], seen_runs: set[str], seen_processes: set[int]) -> Dict[str, Any]:
    output = project / Path(str(entry["outputRelativePath"]).replace("/", os.sep))
    block_manifest_path = output / "block-manifest.json"
    require(block_manifest_path.is_file(), f"block manifest missing: {block_manifest_path}")
    require(sha256_file(block_manifest_path) == entry["blockManifestSha256"], "block manifest hash mismatch")
    block = read_json(block_manifest_path)
    require(block.get("completed") is True, "block is not complete")
    require(block.get("formalCampaign") is False, "formal block found in supplemental pilot")
    require(block.get("executionDesignId") == DESIGN_ID, "block design mismatch")
    require(block.get("hardMemoryRulesPassed") is True, "block memory gate failed")
    require(block.get("oneBlockPerUnityProcess") is True, "one-block process invariant failed")
    require(block.get("oneSamplePerAlgorithmPerProcess") is True, "one-algorithm occurrence invariant failed")
    require(block.get("allSamplesShareProcessId") is True, "process identity invariant failed")
    require(block.get("orderMatchesBlockPlan") is True, "Williams order invariant failed")
    require(int(block["block"]) == int(entry["block"]), "block ordinal mismatch")
    require(block["comparisonCohortId"] == entry["comparisonCohortId"], "cohort mismatch")
    require(block["scenarioSourceSha256"] == entry["scenarioSha256"], "scenario hash mismatch")
    process_id = int(block["processId"])
    require(process_id not in seen_processes, f"duplicate Unity process identity: {process_id}")
    seen_processes.add(process_id)
    samples = list(block["samples"])
    require(len(samples) == 2 and int(block["completedSampleCount"]) == 2, "heterogeneous block must contain two samples")
    algorithms: Dict[str, Any] = {}
    for sample in samples:
        require(sample.get("completed") is True, "sample is incomplete")
        run_id = str(sample["runId"])
        require(run_id not in seen_runs, f"duplicate run ID: {run_id}")
        seen_runs.add(run_id)
        sample_dir = output / Path(str(sample["outputRelativePath"]).replace("/", os.sep))
        result_path = output / Path(str(sample["workloadResultRelativePath"]).replace("/", os.sep))
        manifest_path = output / Path(str(sample["manifestRelativePath"]).replace("/", os.sep))
        summary_path = output / Path(str(sample["summaryRelativePath"]).replace("/", os.sep))
        require(sample_dir.is_dir() and result_path.is_file() and manifest_path.is_file() and summary_path.is_file(), "sample evidence missing")
        require(sha256_file(result_path) == sample["workloadResultSha256"], "workload hash mismatch")
        require(sha256_file(manifest_path) == sample["manifestSha256"], "sample manifest hash mismatch")
        require(sha256_file(summary_path) == sample["summarySha256"], "sample summary hash mismatch")
        workload = read_json(result_path)
        sample_manifest = read_json(manifest_path)
        sample_summary = read_json(summary_path)
        algorithm = str(sample["algorithmId"])
        require(algorithm == workload["algorithmId"] == sample_manifest["algorithmId"] == sample_summary["algorithmId"], "algorithm identity mismatch")
        require(workload.get("completed") is True and sample_manifest.get("completed") is True and sample_summary.get("completed") is True, "completion gate failed")
        require(sample_manifest.get("plannerResetCompleted") is True, "planner reset gate failed")
        require(sample_manifest.get("loggerDisposed") is True, "logger disposal gate failed")
        require(sample_manifest.get("sampleStateCreatedFresh") is True, "fresh sample-state gate failed")
        require(sample_manifest.get("canonicalScenarioReferenceVerified") is True, "canonical scenario reference gate failed")
        require(int(sample_manifest["processId"] if "processId" in sample_manifest else sample["processId"]) == process_id, "sample process ID mismatch")
        require(algorithm not in algorithms, "duplicate algorithm within cohort process")
        algorithms[algorithm] = {
            "runId": run_id,
            "position": int(sample["position"]),
            "predecessorAlgorithmId": str(sample["predecessorAlgorithmId"]),
            "metrics": metrics_from_workload(workload),
        }
    expected = {"A*-R", "D*L"} if entry["comparisonCohortId"].startswith("per-agent") else {"C-FF", "IDFF"}
    require(set(algorithms) == expected, "cohort algorithm set mismatch")
    return {"processId": process_id, "algorithms": algorithms}


def build_analysis(project: Path, pilot_root: Path, plan_path: Path, provenance_path: Path) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    plan = read_json(plan_path)
    provenance = read_json(provenance_path)
    execution_path = pilot_root / "pilot-execution-manifest.json"
    execution = read_json(execution_path)
    require(plan.get("planId") == PLAN_ID and plan.get("formalCampaign") is False, "plan identity/boundary mismatch")
    require(execution.get("completed") is True and execution.get("formalCampaign") is False, "execution manifest boundary mismatch")
    require(execution.get("excludedFromFormalAnalysis") is True, "execution exclusion flag missing")
    require(execution.get("pilotPlanSha256") == sha256_file(plan_path), "execution/plan hash binding mismatch")
    require(execution.get("provenanceSha256") == sha256_file(provenance_path), "execution/provenance hash binding mismatch")
    measured_entries = [row for row in execution["entries"] if row["role"] == "measured-non-formal-pilot"]
    warmup_entries = [row for row in execution["entries"] if row["role"] == "excluded-warmup"]
    require(len(measured_entries) == 384 and len(warmup_entries) == 12, "execution cardinality mismatch")
    require(int(execution["measuredSampleCount"]) == 768, "measured sample count mismatch")
    seen_runs: set[str] = set()
    seen_processes: set[int] = set()
    processes: Dict[Tuple[str, int, str, str], Dict[str, Any]] = {}
    for entry in sorted(measured_entries, key=lambda row: int(row["ordinal"])):
        require(entry.get("completed") is True and entry.get("formalCampaign") is False, "invalid measured execution entry")
        key = (str(entry["scenarioId"]), int(entry["block"]), str(entry["superblockOrder"]), str(entry["comparisonCohortId"]))
        require(key not in processes, f"duplicate process schedule key: {key}")
        loaded = load_process_samples(project, entry, seen_runs, seen_processes)
        processes[key] = {"entry": entry, **loaded}
    require(len(seen_runs) == 768 and len(seen_processes) == 384, "unique run/process cardinality mismatch")

    superblocks: Dict[Tuple[str, int, str], Dict[str, Any]] = {}
    for scenario in SCENARIOS:
        for block in range(1, 33):
            for order in ("AB", "BA"):
                pa = processes[(scenario, block, order, "per-agent-heterogeneous-goal-v1")]
                gf = processes[(scenario, block, order, "grouped-field-heterogeneous-goal-v1")]
                pa_ordinal = int(pa["entry"]["ordinal"])
                gf_ordinal = int(gf["entry"]["ordinal"])
                if order == "AB":
                    require(gf_ordinal == pa_ordinal + 1, "AB processes are not adjacent/in order")
                else:
                    require(pa_ordinal == gf_ordinal + 1, "BA processes are not adjacent/in order")
                algorithms = {**pa["algorithms"], **gf["algorithms"]}
                require(set(algorithms) == {"A*-R", "D*L", "C-FF", "IDFF"}, "superblock algorithm set mismatch")
                logs: Dict[str, Dict[str, float]] = {}
                for metric in CONTINUOUS_METRICS:
                    logs[metric] = {}
                    for contrast, (numerator, denominator) in CONTRASTS.items():
                        nv = float(algorithms[numerator]["metrics"][metric])
                        dv = float(algorithms[denominator]["metrics"][metric])
                        logs[metric][contrast] = math.log(nv / dv)
                superblocks[(scenario, block, order)] = {
                    "logs": logs,
                    "algorithms": algorithms,
                    "processOrdinals": [pa_ordinal, gf_ordinal],
                }

    pairs: List[Dict[str, Any]] = []
    for scenario in SCENARIOS:
        for block in range(1, 33):
            ab = superblocks[(scenario, block, "AB")]
            ba = superblocks[(scenario, block, "BA")]
            differences: Dict[str, Dict[str, float]] = {}
            for metric in CONTINUOUS_METRICS:
                differences[metric] = {
                    contrast: ab["logs"][metric][contrast] - ba["logs"][metric][contrast]
                    for contrast in CONTRASTS
                }
            pairs.append({
                "mirroredPairId": f"{scenario}::b{block:03d}",
                "scenarioId": scenario,
                "block": block,
                "firstSuperblockOrder": "AB" if block % 2 == 1 else "BA",
                "differences": differences,
                "abLogs": ab["logs"],
                "baLogs": ba["logs"],
            })
    require(len(pairs) == 96, "mirrored-pair reconstruction mismatch")

    bound = float(plan["orderEffectAnalysis"]["orderBiasAbsoluteLogBound"])
    replicates = int(plan["orderEffectAnalysis"]["bootstrapReplicates"])
    base_seed = int(plan["orderEffectAnalysis"]["bootstrapSeed"])
    scenario_rows: List[Dict[str, Any]] = []
    pooled_rows: List[Dict[str, Any]] = []
    for metric in CONTINUOUS_METRICS:
        for contrast in CONTRASTS:
            by_scenario: Dict[str, List[float]] = {}
            ab_by_scenario: Dict[str, List[float]] = {}
            ba_by_scenario: Dict[str, List[float]] = {}
            waves_by_scenario: Dict[str, List[int]] = {}
            for scenario in SCENARIOS:
                subset = [row for row in pairs if row["scenarioId"] == scenario]
                values = [float(row["differences"][metric][contrast]) for row in subset]
                ab_values = [float(row["abLogs"][metric][contrast]) for row in subset]
                ba_values = [float(row["baLogs"][metric][contrast]) for row in subset]
                waves = [int(row["block"]) for row in subset]
                by_scenario[scenario] = values
                ab_by_scenario[scenario] = ab_values
                ba_by_scenario[scenario] = ba_values
                waves_by_scenario[scenario] = waves
                stats = summarize_differences(
                    values, ab_values, ba_values, waves,
                    float(plan["orderEffectAnalysis"]["scenarioT31Critical"]), bound,
                    replicates, stable_seed(base_seed, f"scenario|{scenario}|{metric}|{contrast}"),
                )
                scenario_rows.append({"scenarioId": scenario, "metricId": metric, "contrastId": contrast, **stats})
            pooled_values = [value for scenario in SCENARIOS for value in by_scenario[scenario]]
            pooled_ab = [value for scenario in SCENARIOS for value in ab_by_scenario[scenario]]
            pooled_ba = [value for scenario in SCENARIOS for value in ba_by_scenario[scenario]]
            pooled_waves = [value for scenario in SCENARIOS for value in waves_by_scenario[scenario]]
            stats = summarize_differences(
                pooled_values, pooled_ab, pooled_ba, pooled_waves,
                float(plan["orderEffectAnalysis"]["pooledT95Critical"]), bound,
                1, stable_seed(base_seed, f"pooled-placeholder|{metric}|{contrast}"),
            )
            stratified = stratified_equal_scenario_bootstrap_ci(
                by_scenario, replicates, stable_seed(base_seed, f"pooled|{metric}|{contrast}")
            )
            stats["bootstrap95CiLog"] = stratified
            stats["bootstrap95CiMultiplicative"] = [math.exp(stratified[0]), math.exp(stratified[1])]
            stats["pooling"] = "EQUAL-SCENARIO/STRATIFIED-WHOLE-MIRRORED-PAIR-BOOTSTRAP"
            pooled_rows.append({"metricId": metric, "contrastId": contrast, **stats})

    p5_by_order_algorithm: List[Dict[str, Any]] = []
    total_overruns = 0
    for order in ("AB", "BA"):
        for algorithm in ("A*-R", "D*L", "C-FF", "IDFF"):
            counts = {"eligibleOverall": 0, "exceededOverall": 0, "eligiblePlan": 0, "exceededPlan": 0, "eligibleRepair": 0, "exceededRepair": 0}
            for scenario in SCENARIOS:
                for block in range(1, 33):
                    p5 = superblocks[(scenario, block, order)]["algorithms"][algorithm]["metrics"]["P5"]
                    for key in counts:
                        counts[key] += int(p5[key])
            total_overruns += counts["exceededOverall"]
            p5_by_order_algorithm.append({
                "order": order,
                "algorithmId": algorithm,
                **counts,
                "overallRate": counts["exceededOverall"] / counts["eligibleOverall"],
                "planRate": counts["exceededPlan"] / counts["eligiblePlan"] if counts["eligiblePlan"] else None,
                "repairRate": counts["exceededRepair"] / counts["eligibleRepair"] if counts["eligibleRepair"] else None,
            })

    decision_scenario = [row for row in scenario_rows if row["metricId"] == "P1"]
    decision_pooled = [row for row in pooled_rows if row["metricId"] == "P1"]
    pooled_all_bounded = all(row["classification"] == "ORDER-EFFECT-BOUNDED" for row in decision_pooled)
    scenario_all_bounded = all(row["classification"] == "ORDER-EFFECT-BOUNDED" for row in decision_scenario)
    scenario_any_material = any(row["classification"] == "MATERIAL-ORDER-EFFECT" for row in decision_scenario)
    if pooled_all_bounded and scenario_all_bounded:
        recommendation = "H32-SUPPORTED"
    elif pooled_all_bounded and not scenario_any_material:
        recommendation = "H40-RECOMMENDED"
    else:
        recommendation = "H48-RECOMMENDED"

    generated_at = str(execution["completedAtUtc"])
    analysis = {
        "schemaVersion": 1,
        "analysisKind": "gate13r-pr1b-balanced-mirrored-order-effect-analysis-v1",
        "generatedAtUtc": generated_at,
        "status": "NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS",
        "formalInference": False,
        "formalCampaignAuthorized": False,
        "source": {
            "pilotRoot": str(pilot_root).replace("\\", "/"),
            "pilotPlanSha256": sha256_file(plan_path),
            "provenanceSha256": sha256_file(provenance_path),
            "executionManifestSha256": sha256_file(execution_path),
            "measuredMirroredPairs": 96,
            "measuredMatchedSuperblocks": 192,
            "measuredUnityProcesses": 384,
            "measuredAlgorithmSamples": 768,
            "uniqueRunIds": len(seen_runs),
            "uniqueUnityProcessIds": len(seen_processes),
        },
        "estimand": "AB_LOG_SYSTEM_RATIO_MINUS_BA_LOG_SYSTEM_RATIO",
        "orderBiasBound": {
            "absoluteLog": bound,
            "multiplicative": math.exp(bound),
            "identity": "EXECUTION-ORDER-DIAGNOSTIC-NOT-ALGORITHM-PRACTICAL-MARGIN",
        },
        "scenarioRows": scenario_rows,
        "pooledEqualScenarioRows": pooled_rows,
        "p5": {
            "rows": p5_by_order_algorithm,
            "totalOverrunEvents": total_overruns,
            "verdict": "ZERO-EVENT / ORDER-RATIO-NOT-ESTIMABLE" if total_overruns == 0 else "DESCRIPTIVE-COUNT-RATES-ONLY",
            "pseudocountUsed": False,
        },
        "decision": {
            "decisionMetricId": "P1",
            "scenarioCellCount": len(decision_scenario),
            "pooledCellCount": len(decision_pooled),
            "scenarioClassificationCounts": {name: sum(row["classification"] == name for row in decision_scenario) for name in (
                "ORDER-EFFECT-BOUNDED", "MATERIAL-ORDER-EFFECT", "DETECTABLE-BUT-BELOW-BOUND", "INCONCLUSIVE"
            )},
            "pooledClassificationCounts": {name: sum(row["classification"] == name for row in decision_pooled) for name in (
                "ORDER-EFFECT-BOUNDED", "MATERIAL-ORDER-EFFECT", "DETECTABLE-BUT-BELOW-BOUND", "INCONCLUSIVE"
            )},
            "heterogeneousSampleConfigurationRecommendation": recommendation,
            "recommendationIsFrozenFormalDesign": False,
            "sharedS48Changed": False,
            "requiresSeparateFormalAuthorization": True,
        },
        "prohibitedClaims": [
            "FORMAL-ALGORITHM-SUPERIORITY",
            "PURE-ALGORITHM-CAUSAL-EFFECT-ACROSS-HETEROGENEOUS-FAMILIES",
            "POOLING-WITH-GATE12R-V4-OR-FUTURE-FORMAL-DATA",
            "FORMAL-ALPHA-CONSUMPTION",
        ],
    }
    analysis_text = canonical_json_text(analysis).encode("utf-8")
    analysis_sha = hashlib.sha256(analysis_text).hexdigest()
    pilot_manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr1b-balanced-mirrored-order-effect-pilot-manifest-v1",
        "completedAtUtc": generated_at,
        "completed": True,
        "status": "NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS / ORDER-EFFECT-PILOT-COMPLETE",
        "pilotPlanSha256": sha256_file(plan_path),
        "provenanceSha256": sha256_file(provenance_path),
        "executionManifestSha256": sha256_file(execution_path),
        "analysisSha256": analysis_sha,
        "measuredMirroredPairs": 96,
        "measuredMatchedSuperblocks": 192,
        "measuredBlockProcesses": 384,
        "measuredSamples": 768,
        "uniqueRunIds": len(seen_runs),
        "uniqueUnityProcessIds": len(seen_processes),
        "partialMeasuredPairs": 0,
        "automaticRetryCount": 0,
        "automaticResumeCount": 0,
        "recommendation": recommendation,
        "formalCampaign": False,
        "excludedFromFormalAnalysis": True,
        "gate13rFormalAuthorized": False,
        "gate14rAuthorized": False,
    }
    return analysis, pilot_manifest


def self_test() -> Dict[str, Any]:
    bound = math.log(1.10)
    checks: List[Tuple[str, bool]] = []
    checks.append(("bounded", classify_interval(0.0, -0.05, 0.05, bound) == "ORDER-EFFECT-BOUNDED"))
    checks.append(("material", classify_interval(0.12, 0.10, 0.14, bound) == "MATERIAL-ORDER-EFFECT"))
    checks.append(("detectable-below", classify_interval(0.05, 0.01, 0.11, bound) == "DETECTABLE-BUT-BELOW-BOUND"))
    checks.append(("inconclusive", classify_interval(0.03, -0.08, 0.12, bound) == "INCONCLUSIVE"))
    algorithms_ab = {"A*-R": 10.0, "D*L": 5.0, "C-FF": 2.0, "IDFF": 1.0}
    algorithms_ba = {"A*-R": 8.0, "D*L": 4.0, "C-FF": 2.0, "IDFF": 1.0}
    c1_ab = math.log(algorithms_ab["C-FF"] / algorithms_ab["A*-R"])
    c1_ba = math.log(algorithms_ba["C-FF"] / algorithms_ba["A*-R"])
    checks.append(("contrast-direction", math.isclose(c1_ab - c1_ba, math.log(0.8), rel_tol=0.0, abs_tol=1e-12)))
    values = [float(i) / 100.0 for i in range(32)]
    first = bootstrap_mean_ci(values, 1000, 17)
    second = bootstrap_mean_ci(values, 1000, 17)
    checks.append(("bootstrap-deterministic", first == second))
    p5 = metrics_from_workload({
        "scheduledEventCount": 5,
        "dynamicManagedAllocatedBytes": 100,
        "dynamicHandlingMillisecondsPerScheduledEvent": 2.0,
        "dynamicHandlingP95Milliseconds": 3.0,
        "totalPlannerElapsedMillisecondsPerAgent": 4.0,
        "planOperationCount": 10,
        "repairOperationCount": 2,
        "budgetExceededOperationCount": 0,
        "budgetExceededPlanCount": 0,
    })["P5"]
    checks.append(("zero-event-retained", p5["eligibleOverall"] == 12 and p5["exceededOverall"] == 0))
    passed = all(value for _, value in checks)
    return {
        "schemaVersion": 1,
        "testKind": "gate13r-pr1b-order-effect-analyzer-self-test-v1",
        "checks": [{"id": name, "passed": value} for name, value in checks],
        "passed": passed,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project")
    parser.add_argument("--pilot-root")
    parser.add_argument("--plan")
    parser.add_argument("--provenance")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--self-test-output")
    parser.add_argument("--verify-existing", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        result = self_test()
        if args.self_test_output:
            write_atomic_json(Path(args.self_test_output).resolve(), result)
        else:
            sys.stdout.write(canonical_json_text(result))
        return 0 if result["passed"] else 1
    require(args.project and args.pilot_root and args.plan and args.provenance, "analysis paths are required")
    project = Path(args.project).resolve()
    pilot_root = Path(args.pilot_root).resolve()
    plan_path = Path(args.plan).resolve()
    provenance_path = Path(args.provenance).resolve()
    analysis, manifest = build_analysis(project, pilot_root, plan_path, provenance_path)
    analysis_path = pilot_root / "order-effect-analysis.json"
    manifest_path = pilot_root / "pilot-manifest.json"
    if args.verify_existing:
        require(analysis_path.is_file() and manifest_path.is_file(), "existing analysis outputs are missing")
        require(read_json(analysis_path) == analysis, "deterministic analysis verification failed")
        require(read_json(manifest_path) == manifest, "deterministic pilot-manifest verification failed")
        sys.stdout.write(canonical_json_text({"passed": True, "analysisSha256": sha256_file(analysis_path), "pilotManifestSha256": sha256_file(manifest_path)}))
        return 0
    require(not analysis_path.exists() and not manifest_path.exists(), "create-new analysis output already exists")
    write_atomic_json(analysis_path, analysis)
    write_atomic_json(manifest_path, manifest)
    sys.stdout.write(canonical_json_text({"passed": True, "analysisSha256": sha256_file(analysis_path), "pilotManifestSha256": sha256_file(manifest_path), "recommendation": manifest["recommendation"]}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:
        sys.stderr.write(f"Gate13R PR1B analysis failed: {exc}\n")
        raise
