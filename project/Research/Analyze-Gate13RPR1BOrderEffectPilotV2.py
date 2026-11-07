#!/usr/bin/env python3
"""Versioned PR1B v2 analysis wrapper with immutable v1 estimands plus memory-alert sensitivity."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import math
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple


PLAN_ID = "gate13r-pr1b-balanced-mirrored-order-effect-memory-v2-pilot-v1"
POLICY_ID = "gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1"
EVALUATION_KIND = "gate13r-pr1b-v2-memory-gate-evaluation-v1"


def load_v1(project: Path):
    path = project / "Research" / "Analyze-Gate13RPR1BOrderEffectPilotV1.py"
    spec = importlib.util.spec_from_file_location("gate13r_pr1b_analyzer_v1_frozen", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load frozen PR1B v1 analyzer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.PLAN_ID = PLAN_ID
    return module


def read_json(v1, path: Path) -> Any:
    return v1.read_json(path)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def memory_records(v1, project: Path, execution: Mapping[str, Any]) -> Tuple[List[Dict[str, Any]], Dict[Tuple[str, int, str, str], Dict[str, Any]]]:
    rows: List[Dict[str, Any]] = []
    processes: Dict[Tuple[str, int, str, str], Dict[str, Any]] = {}
    for entry in sorted((e for e in execution["entries"] if e["role"] == "measured-non-formal-pilot"), key=lambda e: int(e["ordinal"])):
        output = project / Path(str(entry["outputRelativePath"]).replace("/", os.sep))
        block_path = output / "block-manifest.json"
        block = read_json(v1, block_path)
        require(block.get("completed") is True and block.get("hardMemoryRulesPassed") is True, "ineligible block in completed v2 execution")
        require(block.get("memoryGatePolicyId") == POLICY_ID, "memory policy mismatch")
        algorithms: Dict[str, Dict[str, Any]] = {}
        block_alerts = 0
        position_one_alert = False
        for sample in block["samples"]:
            evaluation_path = output / Path(str(sample["memoryGateEvaluationRelativePath"]).replace("/", os.sep))
            require(evaluation_path.is_file(), f"missing memory evaluation: {evaluation_path}")
            require(v1.sha256_file(evaluation_path) == sample["memoryGateEvaluationSha256"], "memory evaluation hash mismatch")
            evaluation = read_json(v1, evaluation_path)
            require(evaluation.get("evaluationKind") == EVALUATION_KIND and evaluation.get("completed") is True, "memory evaluation identity/completion mismatch")
            require(evaluation.get("telemetryValid") is True and evaluation.get("sampleEmergencyStopPassed") is True, "ineligible memory evaluation")
            require(evaluation.get("verdict") in ("PASS", "MEMORY-ALERT-128MIB"), "unexpected passing memory verdict")
            result_path = output / Path(str(sample["workloadResultRelativePath"]).replace("/", os.sep))
            workload = read_json(v1, result_path)
            alert = bool(evaluation["sampleMemoryAlert128MiB"])
            if alert:
                block_alerts += 1
                position_one_alert = position_one_alert or int(sample["position"]) == 1
            algorithm = str(sample["algorithmId"])
            algorithms[algorithm] = {
                "metrics": v1.metrics_from_workload(workload),
                "alert": alert,
                "position": int(sample["position"]),
                "predecessor": str(sample["predecessorAlgorithmId"]),
                "processAgeMs": float(evaluation["telemetryAfterCleanup"]["processAgeMilliseconds"]),
                "sampleManagedGrowthBytes": int(evaluation["sampleRetainedManagedGrowthBytes"]),
                "blockManagedGrowthBytes": int(evaluation["blockRetainedManagedGrowthBytesAtSampleBoundary"]),
                "workingSetGrowthBytes": int(evaluation["blockWorkingSetGrowthBytesAtSampleBoundary"]),
                "privateMemoryGrowthBytes": int(evaluation["blockPrivateMemoryGrowthBytesAtSampleBoundary"]),
            }
            rows.append({
                "scenarioId": str(entry["scenarioId"]), "block": int(entry["block"]), "wave": int(entry["wave"]),
                "superblockOrder": str(entry["superblockOrder"]), "pairProcessPosition": int(entry["pairProcessPosition"]),
                "cohort": str(entry["comparisonCohortId"]), "algorithmId": algorithm,
                "position": int(sample["position"]), "predecessor": str(sample["predecessorAlgorithmId"]),
                "alert": alert, "processAgeMs": algorithms[algorithm]["processAgeMs"],
                "sampleManagedGrowthBytes": algorithms[algorithm]["sampleManagedGrowthBytes"],
                "blockManagedGrowthBytes": algorithms[algorithm]["blockManagedGrowthBytes"],
                "workingSetGrowthBytes": algorithms[algorithm]["workingSetGrowthBytes"],
                "privateMemoryGrowthBytes": algorithms[algorithm]["privateMemoryGrowthBytes"],
            })
        require(block_alerts == int(block["memoryAlertSampleCount"]), "block alert aggregation mismatch")
        key = (str(entry["scenarioId"]), int(entry["block"]), str(entry["superblockOrder"]), str(entry["comparisonCohortId"]))
        processes[key] = {"algorithms": algorithms, "anyAlert": block_alerts > 0, "positionOneAlert": position_one_alert, "entry": entry}
    require(len(rows) == 768 and len(processes) == 384, "v2 memory record cardinality mismatch")
    return rows, processes


def build_pairs(v1, processes: Mapping[Tuple[str, int, str, str], Dict[str, Any]]) -> List[Dict[str, Any]]:
    pairs: List[Dict[str, Any]] = []
    for scenario in v1.SCENARIOS:
        for block in range(1, 33):
            order_data: Dict[str, Any] = {}
            pair_alert = False
            for order in ("AB", "BA"):
                pa = processes[(scenario, block, order, "per-agent-heterogeneous-goal-v1")]
                gf = processes[(scenario, block, order, "grouped-field-heterogeneous-goal-v1")]
                pair_alert = pair_alert or pa["anyAlert"] or gf["anyAlert"]
                algorithms = {**pa["algorithms"], **gf["algorithms"]}
                logs: Dict[str, Dict[str, float]] = {}
                for metric in v1.CONTINUOUS_METRICS:
                    logs[metric] = {}
                    for contrast, (numerator, denominator) in v1.CONTRASTS.items():
                        nv = float(algorithms[numerator]["metrics"][metric])
                        dv = float(algorithms[denominator]["metrics"][metric])
                        require(math.isfinite(nv) and math.isfinite(dv) and nv > 0.0 and dv > 0.0, "non-positive/non-finite sensitivity endpoint")
                        logs[metric][contrast] = math.log(nv / dv)
                order_data[order] = logs
            differences = {metric: {contrast: order_data["AB"][metric][contrast] - order_data["BA"][metric][contrast] for contrast in v1.CONTRASTS} for metric in v1.CONTINUOUS_METRICS}
            pairs.append({"scenarioId": scenario, "block": block, "anyAlert": pair_alert, "differences": differences})
    require(len(pairs) == 96, "memory sensitivity mirrored-pair cardinality mismatch")
    return pairs


def stratified_subset_bootstrap_ci(v1, by_scenario: Mapping[str, Sequence[float]], replicates: int, seed: int) -> List[float]:
    import random
    rng = random.Random(seed)
    draws: List[float] = []
    scenarios = list(v1.SCENARIOS)
    for _ in range(replicates):
        scenario_means: List[float] = []
        for scenario in scenarios:
            values = list(by_scenario[scenario])
            require(len(values) >= 2, "subset bootstrap requires at least two pairs per scenario")
            scenario_means.append(sum(values[rng.randrange(len(values))] for _ in values) / len(values))
        draws.append(sum(scenario_means) / len(scenario_means))
    draws.sort()
    return [v1.percentile_linear(draws, 0.025), v1.percentile_linear(draws, 0.975)]


def subset_rows(v1, pairs: Sequence[Mapping[str, Any]], plan: Mapping[str, Any]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    no_alert = [pair for pair in pairs if not pair["anyAlert"]]
    scenario_rows: List[Dict[str, Any]] = []
    pooled_rows: List[Dict[str, Any]] = []
    base_seed = int(plan["orderEffectAnalysis"]["bootstrapSeed"])
    replicates = int(plan["orderEffectAnalysis"]["bootstrapReplicates"])
    for metric in v1.CONTINUOUS_METRICS:
        for contrast in v1.CONTRASTS:
            by_scenario: Dict[str, List[float]] = {}
            for scenario in v1.SCENARIOS:
                values = [float(row["differences"][metric][contrast]) for row in no_alert if row["scenarioId"] == scenario]
                by_scenario[scenario] = values
                if len(values) >= 2:
                    bootstrap = v1.bootstrap_mean_ci(values, replicates, v1.stable_seed(base_seed, f"v2-no-alert|{scenario}|{metric}|{contrast}"))
                    scenario_rows.append({"scenarioId": scenario, "metricId": metric, "contrastId": contrast, "nCompleteMirroredPairs": len(values), "meanLogOrderEffect": v1.mean(values), "bootstrap95CiLog": bootstrap, "bootstrap95CiMultiplicative": [math.exp(bootstrap[0]), math.exp(bootstrap[1])], "role": "SENSITIVITY-ONLY-NOT-PRIMARY", "estimable": True})
                else:
                    scenario_rows.append({"scenarioId": scenario, "metricId": metric, "contrastId": contrast, "nCompleteMirroredPairs": len(values), "role": "SENSITIVITY-ONLY-NOT-PRIMARY", "estimable": False, "reasonCode": "INSUFFICIENT-NO-ALERT-PAIRS"})
            if all(len(by_scenario[scenario]) >= 2 for scenario in v1.SCENARIOS):
                values = [value for scenario in v1.SCENARIOS for value in by_scenario[scenario]]
                bootstrap = stratified_subset_bootstrap_ci(v1, by_scenario, replicates, v1.stable_seed(base_seed, f"v2-no-alert-pooled|{metric}|{contrast}"))
                pooled_rows.append({"metricId": metric, "contrastId": contrast, "nCompleteMirroredPairs": len(values), "scenarioPairCounts": {scenario: len(by_scenario[scenario]) for scenario in v1.SCENARIOS}, "meanLogOrderEffect": v1.mean([v1.mean(by_scenario[s]) for s in v1.SCENARIOS]), "bootstrap95CiLog": bootstrap, "bootstrap95CiMultiplicative": [math.exp(bootstrap[0]), math.exp(bootstrap[1])], "role": "SENSITIVITY-ONLY-NOT-PRIMARY", "estimable": True})
            else:
                pooled_rows.append({"metricId": metric, "contrastId": contrast, "scenarioPairCounts": {scenario: len(by_scenario[scenario]) for scenario in v1.SCENARIOS}, "role": "SENSITIVITY-ONLY-NOT-PRIMARY", "estimable": False, "reasonCode": "INSUFFICIENT-SCENARIO-SUPPORT"})
    return scenario_rows, pooled_rows


def alert_diagnostics(rows: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    alert_rows = [row for row in rows if row["alert"]]
    def counts(key: str) -> Dict[str, int]:
        return dict(sorted(Counter(str(row[key]) for row in alert_rows).items()))
    carryover = [row for row in rows if int(row["position"]) == 2 and any(a["scenarioId"] == row["scenarioId"] and a["block"] == row["block"] and a["superblockOrder"] == row["superblockOrder"] and a["cohort"] == row["cohort"] and int(a["position"]) == 1 and a["alert"] for a in rows)]
    return {
        "sampleCount": len(rows), "alertSampleCount": len(alert_rows), "alertRate": len(alert_rows) / len(rows),
        "byScenario": counts("scenarioId"), "byCohort": counts("cohort"), "byAlgorithm": counts("algorithmId"),
        "byPosition": counts("position"), "byPredecessor": counts("predecessor"), "bySuperblockOrder": counts("superblockOrder"),
        "byPairProcessPosition": counts("pairProcessPosition"), "byWave": counts("wave"),
        "postAlertPosition2SampleCount": len(carryover),
        "postAlertPosition2MeanProcessAgeMs": sum(float(row["processAgeMs"]) for row in carryover) / len(carryover) if carryover else None,
        "postAlertPosition2MeanSampleManagedGrowthBytes": sum(int(row["sampleManagedGrowthBytes"]) for row in carryover) / len(carryover) if carryover else None,
    }


def build_analysis(project: Path, pilot_root: Path, plan_path: Path, provenance_path: Path) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    v1 = load_v1(project)
    plan = read_json(v1, plan_path)
    require(plan.get("planId") == PLAN_ID and plan.get("formalCampaign") is False, "v2 plan identity/boundary mismatch")
    require(plan["memoryEligibility"]["policyId"] == POLICY_ID, "v2 plan policy mismatch")
    analysis, manifest = v1.build_analysis(project, pilot_root, plan_path, provenance_path)
    execution = read_json(v1, pilot_root / "pilot-execution-manifest.json")
    rows, processes = memory_records(v1, project, execution)
    pairs = build_pairs(v1, processes)
    scenario_sensitivity, pooled_sensitivity = subset_rows(v1, pairs, plan)
    alert_pair_count = sum(bool(pair["anyAlert"]) for pair in pairs)
    analysis["schemaVersion"] = 2
    analysis["analysisKind"] = "gate13r-pr1b-v2-memory-aware-balanced-mirrored-order-effect-analysis-v1"
    analysis["memoryEligibility"] = {"policyId": POLICY_ID, "primaryAnalysisSet": "ALL-COMPLETE-ELIGIBLE-PAIRS-INCLUDING-MEMORY-ALERTS", "alertPairsExcludedFromPrimary": False, "completeMirroredPairCount": 96, "alertMirroredPairCount": alert_pair_count, "noAlertMirroredPairCount": 96 - alert_pair_count}
    analysis["memoryAlertDiagnostics"] = alert_diagnostics(rows)
    analysis["noAlertSensitivity"] = {"role": "SENSITIVITY-ONLY-NOT-PRIMARY", "mayReplacePrimary": False, "scenarioRows": scenario_sensitivity, "pooledEqualScenarioRows": pooled_sensitivity}
    analysis_bytes = v1.canonical_json_text(analysis).encode("utf-8")
    manifest["schemaVersion"] = 2
    manifest["manifestKind"] = "gate13r-pr1b-v2-memory-aware-balanced-mirrored-order-effect-pilot-manifest-v1"
    manifest["analysisSha256"] = hashlib.sha256(analysis_bytes).hexdigest()
    manifest["memoryGatePolicyId"] = POLICY_ID
    manifest["memoryAlertSampleCount"] = int(analysis["memoryAlertDiagnostics"]["alertSampleCount"])
    manifest["memoryAlertMirroredPairCount"] = alert_pair_count
    manifest["primaryAnalysisIncludesAlerts"] = True
    return analysis, manifest


def self_test(project: Path) -> Dict[str, Any]:
    v1 = load_v1(project)
    base = v1.self_test()
    pairs = []
    for scenario in v1.SCENARIOS:
        for block in range(1, 33):
            pairs.append({"scenarioId": scenario, "block": block, "anyAlert": block == 1, "differences": {metric: {contrast: 0.01 * block for contrast in v1.CONTRASTS} for metric in v1.CONTINUOUS_METRICS}})
    plan = {"orderEffectAnalysis": {"bootstrapSeed": 13012026, "bootstrapReplicates": 200}}
    first = subset_rows(v1, pairs, plan)
    second = subset_rows(v1, pairs, plan)
    checks = list(base["checks"]) + [
        {"id": "no-alert-excludes-only-alert-pairs", "passed": all(row.get("nCompleteMirroredPairs") == 31 for row in first[0])},
        {"id": "no-alert-bootstrap-deterministic", "passed": first == second},
        {"id": "primary-role-not-replaced", "passed": all(row.get("role") == "SENSITIVITY-ONLY-NOT-PRIMARY" for row in first[0] + first[1])},
    ]
    return {"schemaVersion": 2, "testKind": "gate13r-pr1b-v2-order-effect-analyzer-self-test-v1", "checks": checks, "passed": all(bool(row["passed"]) for row in checks)}


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--pilot-root")
    parser.add_argument("--plan")
    parser.add_argument("--provenance")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--self-test-output")
    parser.add_argument("--verify-existing", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    project = Path(args.project).resolve()
    v1 = load_v1(project)
    if args.self_test:
        result = self_test(project)
        if args.self_test_output:
            v1.write_atomic_json(Path(args.self_test_output).resolve(), result)
        else:
            sys.stdout.write(v1.canonical_json_text(result))
        return 0 if result["passed"] else 1
    require(args.pilot_root and args.plan and args.provenance, "analysis paths are required")
    pilot_root = Path(args.pilot_root).resolve()
    analysis, manifest = build_analysis(project, pilot_root, Path(args.plan).resolve(), Path(args.provenance).resolve())
    analysis_path = pilot_root / "order-effect-analysis.json"
    manifest_path = pilot_root / "pilot-manifest.json"
    if args.verify_existing:
        require(analysis_path.is_file() and manifest_path.is_file(), "existing analysis outputs are missing")
        require(read_json(v1, analysis_path) == analysis, "deterministic v2 analysis verification failed")
        require(read_json(v1, manifest_path) == manifest, "deterministic v2 pilot manifest verification failed")
        sys.stdout.write(v1.canonical_json_text({"passed": True, "analysisSha256": v1.sha256_file(analysis_path), "pilotManifestSha256": v1.sha256_file(manifest_path)}))
        return 0
    require(not analysis_path.exists() and not manifest_path.exists(), "create-new v2 analysis output already exists")
    v1.write_atomic_json(analysis_path, analysis)
    v1.write_atomic_json(manifest_path, manifest)
    sys.stdout.write(v1.canonical_json_text({"passed": True, "analysisSha256": v1.sha256_file(analysis_path), "pilotManifestSha256": v1.sha256_file(manifest_path), "recommendation": manifest["recommendation"]}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:
        sys.stderr.write(f"Gate13R PR1B v2 analysis failed: {exc}\n")
        raise
