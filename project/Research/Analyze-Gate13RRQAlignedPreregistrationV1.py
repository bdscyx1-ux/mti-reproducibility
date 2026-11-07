#!/usr/bin/env python3
"""Gate 13R-PR1 read-only Gate 12R v4 reanalysis.

This program never starts Unity and never writes into any frozen upstream root.
It uses only the Python standard library and emits deterministic JSON when a
fixed timestamp is supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import locale
import math
import os
import random
import statistics
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from statistics import NormalDist
from typing import Any, Iterable


SCHEMA_VERSION = 1
ANALYZER_ID = "gate13r-rq-aligned-preregistration-analyzer-v1"
PILOT_REL = Path("Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4")
EXPECTED_BUNDLE_SHA = "5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc"
EXPECTED_BLOCKS = 384
EXPECTED_SAMPLES = 1152
EXPECTED_CAMPAIGNS = 12
FIXED_BOOTSTRAP_SEED = 13012026
FIXED_SIMULATION_SEED = 13122026
SIMULATION_REPLICATIONS = 20000
ALPHA = 0.05
CONTRASTS = [
    ("C1", "C-FF", "A*-R", "directional"),
    ("C2", "C-FF", "D*L", "directional"),
    ("C3", "IDFF", "A*-R", "directional"),
    ("C4", "IDFF", "D*L", "directional"),
    ("C5", "IDFF", "C-FF", "two-sided"),
]
CONTINUOUS_METRICS = ["P1", "P2", "P3", "P4"]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = canonical_json_bytes(value)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def mean(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def sample_sd(values: list[float]) -> float | None:
    return statistics.stdev(values) if len(values) >= 2 else None


def pearson(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3 or len(xs) != len(ys):
        return None
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    dx = [x - mx for x in xs]
    dy = [y - my for y in ys]
    denom = math.sqrt(sum(v * v for v in dx) * sum(v * v for v in dy))
    return None if denom == 0 else sum(a * b for a, b in zip(dx, dy)) / denom


def regularized_gamma_p(a: float, x: float) -> float:
    if a <= 0 or x < 0:
        raise ValueError("invalid gamma arguments")
    if x == 0:
        return 0.0
    eps = 1e-14
    fp_min = 1e-300
    if x < a + 1.0:
        ap = a
        term = 1.0 / a
        total = term
        for _ in range(10000):
            ap += 1.0
            term *= x / ap
            total += term
            if abs(term) < abs(total) * eps:
                break
        return total * math.exp(-x + a * math.log(x) - math.lgamma(a))
    b = x + 1.0 - a
    c = 1.0 / fp_min
    d = 1.0 / b
    h = d
    for i in range(1, 10000):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        if abs(d) < fp_min:
            d = fp_min
        c = b + an / c
        if abs(c) < fp_min:
            c = fp_min
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    q = math.exp(-x + a * math.log(x) - math.lgamma(a)) * h
    return 1.0 - q


def chi_square_ppf(probability: float, degrees_freedom: int) -> float:
    if not 0.0 < probability < 1.0 or degrees_freedom <= 0:
        raise ValueError("invalid chi-square quantile arguments")
    low, high = 0.0, max(1.0, float(degrees_freedom))
    while regularized_gamma_p(degrees_freedom / 2.0, high / 2.0) < probability:
        high *= 2.0
    for _ in range(160):
        middle = (low + high) / 2.0
        if regularized_gamma_p(degrees_freedom / 2.0, middle / 2.0) < probability:
            low = middle
        else:
            high = middle
    return (low + high) / 2.0


def sigma_upper_90(values: list[float]) -> float | None:
    sd = sample_sd(values)
    if sd is None:
        return None
    df = len(values) - 1
    return sd * math.sqrt(df / chi_square_ppf(0.10, df))


def holm_adjust(raw_p: list[float]) -> list[float]:
    m = len(raw_p)
    ordered = sorted(enumerate(raw_p), key=lambda pair: pair[1])
    adjusted = [1.0] * m
    running = 0.0
    for rank, (index, p_value) in enumerate(ordered):
        running = max(running, (m - rank) * p_value)
        adjusted[index] = min(1.0, running)
    return adjusted


def normal_p_value(estimate: float, se: float, sidedness: str) -> float:
    if se <= 0:
        if estimate == 0:
            return 1.0
        if sidedness == "directional":
            return 0.0 if estimate < 0 else 1.0
        return 0.0
    z = estimate / se
    if sidedness == "directional":
        return NormalDist().cdf(z)
    return min(1.0, 2.0 * (1.0 - NormalDist().cdf(abs(z))))


def log_contrast_stats(records: list[dict[str, Any]], sidedness: str) -> dict[str, Any]:
    values = [float(record["logRatio"]) for record in records]
    n = len(values)
    if n < 2:
        return {
            "nIndependentClusters": n,
            "estimability": "NOT-ESTIMABLE",
            "reasonCode": "FEWER-THAN-TWO-COMPLETE-CLUSTERS",
        }
    point = statistics.fmean(values)
    sd = statistics.stdev(values)
    se = sd / math.sqrt(n)
    z95 = NormalDist().inv_cdf(0.975)
    z_sim = NormalDist().inv_cdf(1.0 - ALPHA / (2.0 * len(CONTRASTS)))
    ci = [point - z95 * se, point + z95 * se]
    sim_ci = [point - z_sim * se, point + z_sim * se]
    predecessor = defaultdict(list)
    for record in records:
        predecessor[f"{record['numeratorPredecessor']}|{record['denominatorPredecessor']}"] .append(float(record["logRatio"]))
    return {
        "nIndependentClusters": n,
        "rawAlgorithmSampleCount": n * 2,
        "eligibleClusterCount": n,
        "missingClusterCount": 0,
        "failureClusterCount": 0,
        "estimator": "MEAN-PAIRED-NATURAL-LOG-RATIO",
        "transform": "NATURAL-LOG",
        "pointLogRatio": point,
        "geometricRatio": math.exp(point),
        "sampleSdLogRatio": sd,
        "sigmaUpper90LogRatio": sigma_upper_90(values),
        "standardError": se,
        "unadjusted95CiLog": ci,
        "unadjusted95CiRatio": [math.exp(ci[0]), math.exp(ci[1])],
        "bonferroniCompatible99CiLog": sim_ci,
        "bonferroniCompatible99CiRatio": [math.exp(sim_ci[0]), math.exp(sim_ci[1])],
        "rawNormalApproximationPValue": normal_p_value(point, se, sidedness),
        "sidedness": sidedness,
        "positionDeltaCorrelation": pearson(
            [float(r["numeratorPosition"] - r["denominatorPosition"]) for r in records], values
        ),
        "processAgeDeltaCorrelation": pearson(
            [float(r["numeratorProcessAgeMs"] - r["denominatorProcessAgeMs"]) for r in records], values
        ),
        "executionOrdinalCorrelation": pearson([float(r["executionOrdinal"]) for r in records], values),
        "predecessorStrata": [
            {"identity": key, "n": len(group), "meanLogRatio": statistics.fmean(group)}
            for key, group in sorted(predecessor.items())
        ],
        "estimability": "ESTIMABLE-FOR-PILOT-VARIANCE-PLANNING",
    }


def tree_identity(root: Path) -> dict[str, Any]:
    resolved = root.resolve()
    locale.setlocale(locale.LC_COLLATE, "")
    files = sorted((p for p in resolved.rglob("*") if p.is_file()), key=lambda p: locale.strxfrm(str(p)))
    lines: list[str] = []
    byte_count = 0
    for path in files:
        relative = path.relative_to(resolved).as_posix()
        size = path.stat().st_size
        byte_count += size
        lines.append(f"{relative}|{size}|{sha256_file(path)}")
    return {
        "path": resolved.as_posix(),
        "fileCount": len(files),
        "byteCount": byte_count,
        "treeSha256": sha256_bytes("\n".join(lines).encode("utf-8")),
    }


def derive_metrics(result: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    scheduled = result.get("scheduledEventCount")
    agent_count = result.get("agentCount")
    dynamic_total = result.get("dynamicHandlingTotalMilliseconds")
    total_planner = result.get("totalPlannerElapsedMilliseconds")
    dynamic_alloc = result.get("dynamicManagedAllocatedBytes")
    required = [
        "dynamicHandlingMillisecondsPerScheduledEvent",
        "dynamicHandlingP95Milliseconds",
        "totalPlannerElapsedMillisecondsPerAgent",
        "dynamicManagedAllocatedBytes",
        "scheduledEventCount",
        "budgetExceededOperationCount",
        "budgetExceededPlanCount",
        "planOperationCount",
        "repairOperationCount",
    ]
    for field in required:
        if field not in result:
            errors.append(f"MISSING-FIELD:{field}")
    if not finite_number(scheduled) or float(scheduled) <= 0:
        errors.append("INVALID-SCHEDULED-EVENT-COUNT")
    if not finite_number(agent_count) or float(agent_count) <= 0:
        errors.append("INVALID-AGENT-COUNT")
    p1 = result.get("dynamicHandlingMillisecondsPerScheduledEvent")
    if finite_number(dynamic_total) and finite_number(scheduled) and float(scheduled) > 0 and finite_number(p1):
        recomputed = float(dynamic_total) / float(scheduled)
        if not math.isclose(float(p1), recomputed, rel_tol=1e-9, abs_tol=1e-9):
            errors.append("P1-DERIVATION-MISMATCH")
    p3 = result.get("totalPlannerElapsedMillisecondsPerAgent")
    if finite_number(total_planner) and finite_number(agent_count) and float(agent_count) > 0 and finite_number(p3):
        recomputed = float(total_planner) / float(agent_count)
        if not math.isclose(float(p3), recomputed, rel_tol=1e-9, abs_tol=1e-9):
            errors.append("P3-DERIVATION-MISMATCH")
    p4 = None
    if finite_number(dynamic_alloc) and finite_number(scheduled) and float(scheduled) > 0:
        p4 = float(dynamic_alloc) / float(scheduled)
    bo = result.get("budgetExceededOperationCount")
    bp = result.get("budgetExceededPlanCount")
    po = result.get("planOperationCount")
    ro = result.get("repairOperationCount")
    p5 = None
    if all(finite_number(v) for v in (bo, bp, po, ro)):
        bo_i, bp_i, po_i, ro_i = (int(v) for v in (bo, bp, po, ro))
        derived_repair = bo_i - bp_i
        if min(bo_i, bp_i, po_i, ro_i) < 0 or derived_repair < 0 or derived_repair > ro_i:
            errors.append("P5-INVALID-DERIVED-REPAIR-COUNT")
        else:
            p5 = {
                "overallNumerator": bo_i,
                "overallDenominator": po_i + ro_i,
                "planNumerator": bp_i,
                "planDenominator": po_i,
                "repairNumerator": derived_repair,
                "repairDenominator": ro_i,
            }
    metrics = {
        "P1": float(p1) if finite_number(p1) else None,
        "P2": float(result["dynamicHandlingP95Milliseconds"]) if finite_number(result.get("dynamicHandlingP95Milliseconds")) else None,
        "P3": float(p3) if finite_number(p3) else None,
        "P4": p4,
        "P5": p5,
    }
    return metrics, errors


def load_pilot(project_root: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    pilot_root = project_root / PILOT_REL
    execution_path = pilot_root / "pilot-execution-manifest.json"
    pilot_manifest_path = pilot_root / "pilot-manifest.json"
    execution = load_json(execution_path)
    pilot_manifest = load_json(pilot_manifest_path)
    if sha256_file(execution_path) != str(pilot_manifest["executionManifestSha256"]).lower():
        raise RuntimeError("pilot execution manifest hash mismatch")
    entries = [entry for entry in execution["entries"] if entry.get("role") == "measured-non-formal-pilot"]
    if len(entries) != EXPECTED_BLOCKS:
        raise RuntimeError(f"expected {EXPECTED_BLOCKS} measured blocks, got {len(entries)}")
    samples: list[dict[str, Any]] = []
    run_ids: set[str] = set()
    campaign_ids: set[str] = set()
    block_ids: set[str] = set()
    process_identities: set[tuple[int, str]] = set()
    block_algorithm_sets: Counter[str] = Counter()
    for entry in entries:
        block_path = project_root / Path(entry["outputRelativePath"]) / "block-manifest.json"
        if not block_path.is_file():
            raise RuntimeError(f"missing block manifest: {block_path}")
        if sha256_file(block_path) != str(entry["blockManifestSha256"]).lower():
            raise RuntimeError(f"block manifest hash mismatch: {block_path}")
        block = load_json(block_path)
        block_id = str(block["blockId"])
        if block_id in block_ids:
            raise RuntimeError(f"duplicate block id: {block_id}")
        block_ids.add(block_id)
        campaign_ids.add(str(entry["campaignId"]))
        process_identity = (int(block["processId"]), str(block["processStartTimeUtc"]))
        if process_identity in process_identities:
            raise RuntimeError(f"Unity process identity reused across measured blocks: {process_identity}")
        process_identities.add(process_identity)
        if not all([
            block.get("completed"),
            block.get("oneBlockPerUnityProcess"),
            block.get("oneSamplePerAlgorithmPerProcess"),
            block.get("allSamplesShareProcessId"),
            block.get("orderMatchesBlockPlan"),
            block.get("canonicalScenarioReferenceValidationPassed"),
        ]):
            raise RuntimeError(f"incomplete or invalid block: {block_id}")
        if int(block["completedSampleCount"]) != int(block["expectedSampleCount"]):
            raise RuntimeError(f"partial block: {block_id}")
        algorithms = sorted(sample["algorithmId"] for sample in block["samples"])
        block_algorithm_sets["|".join(algorithms)] += 1
        for sample in block["samples"]:
            run_id = str(sample["runId"])
            if run_id in run_ids:
                raise RuntimeError(f"duplicate run id: {run_id}")
            run_ids.add(run_id)
            workload_path = block_path.parent / Path(sample["workloadResultRelativePath"])
            if sha256_file(workload_path) != str(sample["workloadResultSha256"]).lower():
                raise RuntimeError(f"workload result hash mismatch: {run_id}")
            result = load_json(workload_path)
            if result.get("runId") != run_id or result.get("algorithmId") != sample.get("algorithmId"):
                raise RuntimeError(f"workload identity mismatch: {run_id}")
            metrics, metric_errors = derive_metrics(result)
            samples.append({
                "runId": run_id,
                "blockId": block_id,
                "campaignId": str(entry["campaignId"]),
                "scenarioId": str(entry["scenarioId"]),
                "comparisonCohortId": str(entry["comparisonCohortId"]),
                "blockOrdinal": int(entry["block"]),
                "executionOrdinal": int(entry["ordinal"]),
                "wave": int(entry["wave"]),
                "waveSlot": int(entry["waveSlot"]),
                "wallSeconds": float(entry["wallSeconds"]),
                "rawBytes": int(entry["rawBytes"]),
                "algorithmId": str(sample["algorithmId"]),
                "position": int(sample["position"]),
                "predecessorAlgorithmId": str(sample["predecessorAlgorithmId"]),
                "processAgeBeforeMilliseconds": float(sample["processAgeBeforeMilliseconds"]),
                "agentCount": int(result["agentCount"]),
                "scheduledEventCount": int(result["scheduledEventCount"]),
                "completed": bool(result.get("completed")),
                "metrics": metrics,
                "metricErrors": metric_errors,
                "workloadResultRelativePath": workload_path.relative_to(project_root).as_posix(),
            })
    if len(samples) != EXPECTED_SAMPLES:
        raise RuntimeError(f"expected {EXPECTED_SAMPLES} measured samples, got {len(samples)}")
    if len(campaign_ids) != EXPECTED_CAMPAIGNS:
        raise RuntimeError(f"expected {EXPECTED_CAMPAIGNS} campaigns, got {len(campaign_ids)}")
    metadata = {
        "pilotRoot": pilot_root.as_posix(),
        "pilotManifestSha256": sha256_file(pilot_manifest_path),
        "executionManifestSha256": sha256_file(execution_path),
        "measuredBlockCount": len(entries),
        "measuredSampleCount": len(samples),
        "campaignCount": len(campaign_ids),
        "uniqueRunIdCount": len(run_ids),
        "uniqueUnityProcessIdentityCount": len(process_identities),
        "blockAlgorithmSets": dict(sorted(block_algorithm_sets.items())),
        "independentUnit": "ONE-FRESH-UNITY-EDITOR-PROCESS-PER-COMPLETE-WILLIAMS-BLOCK",
        "formalCampaign": False,
        "excludedFromFormalAnalysis": True,
    }
    return samples, metadata


def metric_observability(samples: list[dict[str, Any]], metadata: dict[str, Any], fixed_time: str) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for metric_id in CONTINUOUS_METRICS:
        values = [sample["metrics"][metric_id] for sample in samples]
        finite = [float(value) for value in values if finite_number(value)]
        rows.append({
            "metricId": metric_id,
            "expectedSampleCount": len(samples),
            "presentFiniteCount": len(finite),
            "missingOrNonfiniteCount": len(samples) - len(finite),
            "strictlyPositiveCount": sum(value > 0 for value in finite),
            "zeroCount": sum(value == 0 for value in finite),
            "negativeCount": sum(value < 0 for value in finite),
            "status": "OBSERVABLE" if len(finite) == len(samples) and not any(value < 0 for value in finite) else "INSTRUMENTATION-GAP",
        })
    p5_valid = [sample for sample in samples if sample["metrics"]["P5"] is not None]
    p5_errors = [error for sample in samples for error in sample["metricErrors"] if error.startswith("P5-")]
    rows.append({
        "metricId": "P5",
        "expectedSampleCount": len(samples),
        "validDerivedCount": len(p5_valid),
        "invalidDerivedCount": len(p5_errors),
        "overallZeroEventSampleCount": sum(s["metrics"]["P5"]["overallNumerator"] == 0 for s in p5_valid),
        "planZeroEventSampleCount": sum(s["metrics"]["P5"]["planNumerator"] == 0 for s in p5_valid),
        "repairZeroEventSampleCount": sum(s["metrics"]["P5"]["repairNumerator"] == 0 for s in p5_valid),
        "status": "OBSERVABLE-AS-COUNTS" if len(p5_valid) == len(samples) and not p5_errors else "INSTRUMENTATION-GAP",
    })
    metric_errors = [
        {"runId": sample["runId"], "errors": sample["metricErrors"]}
        for sample in samples if sample["metricErrors"]
    ]
    prospective = [
        {
            "metricId": f"M{index}",
            "status": "PROSPECTIVE-GATE14R/NOT-OBSERVED-IN-GATE12R/VARIANCE-NOT-ESTIMABLE-FROM-GATE12R",
            "variance": None,
            "power": None,
            "candidateNFormal": None,
        }
        for index in range(1, 6)
    ]
    gap = any(row["status"] == "INSTRUMENTATION-GAP" for row in rows) or bool(metric_errors)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "auditKind": "gate13r-rq-aligned-metric-observability-audit-v1",
        "generatedAtUtc": fixed_time,
        "source": metadata,
        "planningResourceMetrics": rows,
        "prospectiveGate14RMetrics": prospective,
        "metricDerivationErrors": metric_errors,
        "instrumentationGap": gap,
        "passed": not gap,
    }


def group_blocks(samples: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for sample in samples:
        groups[sample["blockId"]].append(sample)
    return groups


def make_record(numerator: dict[str, Any], denominator: dict[str, Any], metric_id: str) -> dict[str, Any] | None:
    nv = numerator["metrics"].get(metric_id)
    dv = denominator["metrics"].get(metric_id)
    if not finite_number(nv) or not finite_number(dv) or float(nv) <= 0 or float(dv) <= 0:
        return None
    return {
        "logRatio": math.log(float(nv)) - math.log(float(dv)),
        "numeratorPosition": numerator["position"],
        "denominatorPosition": denominator["position"],
        "numeratorPredecessor": numerator["predecessorAlgorithmId"],
        "denominatorPredecessor": denominator["predecessorAlgorithmId"],
        "numeratorProcessAgeMs": numerator["processAgeBeforeMilliseconds"],
        "denominatorProcessAgeMs": denominator["processAgeBeforeMilliseconds"],
        "executionOrdinal": numerator["executionOrdinal"],
        "wave": numerator["wave"],
        "blockOrdinal": numerator["blockOrdinal"],
        "scenarioId": numerator["scenarioId"],
        "campaignId": numerator["campaignId"],
    }


def apply_p1_holm(rows: list[dict[str, Any]]) -> None:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        if row.get("metricId") == "P1" and row.get("scope") in {"CAMPAIGN", "PILOT-ANCHOR-POOLED-DESCRIPTIVE"}:
            groups[str(row["scopeIdentity"])].append(row)
    for group in groups.values():
        if len(group) != 5 or any("rawNormalApproximationPValue" not in row["statistics"] for row in group):
            continue
        p_values = [float(row["statistics"]["rawNormalApproximationPValue"]) for row in group]
        adjusted = holm_adjust(p_values)
        for row, value in zip(group, adjusted):
            row["statistics"]["holmAdjustedPValue"] = value
            row["statistics"]["multiplicityStatus"] = "P1-FIVE-CONTRAST-HOLM-FAMILY"


def shared_reanalysis(samples: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, list[list[float]]]]:
    shared = [s for s in samples if s["comparisonCohortId"] == "four-algorithm-shared-goal-v1"]
    blocks = group_blocks(shared)
    contrast_records: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    covariance_vectors: dict[str, list[list[float]]] = defaultdict(list)
    for block_samples in blocks.values():
        by_algorithm = {sample["algorithmId"]: sample for sample in block_samples}
        if set(by_algorithm) != {"A*-R", "D*L", "C-FF", "IDFF"}:
            raise RuntimeError("shared block does not contain all four algorithms")
        for metric_id in CONTINUOUS_METRICS:
            vector: list[float] = []
            complete = True
            for contrast_id, numerator_id, denominator_id, _ in CONTRASTS:
                record = make_record(by_algorithm[numerator_id], by_algorithm[denominator_id], metric_id)
                if record is None:
                    complete = False
                    continue
                contrast_records[(metric_id, contrast_id, record["campaignId"])].append(record)
                contrast_records[(metric_id, contrast_id, "__POOLED__")].append(record)
                vector.append(float(record["logRatio"]))
            if complete and len(vector) == 5:
                covariance_vectors[metric_id].append(vector)
    rows: list[dict[str, Any]] = []
    for metric_id in CONTINUOUS_METRICS:
        for contrast_id, numerator_id, denominator_id, sidedness in CONTRASTS:
            campaign_keys = sorted(
                key[2] for key in contrast_records if key[0] == metric_id and key[1] == contrast_id and key[2] != "__POOLED__"
            )
            for campaign_id in campaign_keys:
                stats = log_contrast_stats(contrast_records[(metric_id, contrast_id, campaign_id)], sidedness)
                rows.append({
                    "comparisonScope": "SHARED-GOAL-FOUR-ALGORITHM",
                    "scope": "CAMPAIGN",
                    "scopeIdentity": campaign_id,
                    "metricId": metric_id,
                    "contrastId": contrast_id,
                    "numeratorAlgorithm": numerator_id,
                    "denominatorAlgorithm": denominator_id,
                    "pairing": "WITHIN-COMPLETE-WILLIAMS-BLOCK",
                    "independentUnit": "FRESH-UNITY-PROCESS-COMPLETE-WILLIAMS-BLOCK",
                    "statistics": stats,
                })
            pooled = log_contrast_stats(contrast_records[(metric_id, contrast_id, "__POOLED__")], sidedness)
            rows.append({
                "comparisonScope": "SHARED-GOAL-FOUR-ALGORITHM",
                "scope": "PILOT-ANCHOR-POOLED-DESCRIPTIVE",
                "scopeIdentity": f"ALL-SHARED-ANCHORS-{metric_id}",
                "metricId": metric_id,
                "contrastId": contrast_id,
                "numeratorAlgorithm": numerator_id,
                "denominatorAlgorithm": denominator_id,
                "pairing": "WITHIN-COMPLETE-WILLIAMS-BLOCK",
                "independentUnit": "FRESH-UNITY-PROCESS-COMPLETE-WILLIAMS-BLOCK",
                "warning": "Pilot anchors are not the full 32-campaign formal matrix.",
                "statistics": pooled,
            })
    apply_p1_holm(rows)
    return rows, covariance_vectors


def zero_event_upper_95(events: int, denominator: int) -> float | None:
    if denominator <= 0 or events != 0:
        return None
    return 1.0 - math.pow(0.05, 1.0 / denominator)


def p5_summary(samples: list[dict[str, Any]]) -> dict[str, Any]:
    by_scope: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for sample in samples:
        by_scope[(sample["comparisonCohortId"], sample["algorithmId"])].append(sample)
    rows = []
    for (cohort, algorithm), group in sorted(by_scope.items()):
        row: dict[str, Any] = {"comparisonCohortId": cohort, "algorithmId": algorithm, "sampleCount": len(group)}
        all_zero = True
        for stratum in ("overall", "plan", "repair"):
            numerator = sum(s["metrics"]["P5"][f"{stratum}Numerator"] for s in group)
            denominator = sum(s["metrics"]["P5"][f"{stratum}Denominator"] for s in group)
            if numerator:
                all_zero = False
            row[stratum] = {
                "events": numerator,
                "operations": denominator,
                "rate": numerator / denominator if denominator else None,
                "zeroEventExactOneSided95Upper": zero_event_upper_95(numerator, denominator),
            }
        row["sampleSizeVerdict"] = "NOT-ESTIMABLE-FROM-ZERO-EVENT-PILOT" if all_zero else "COUNT-MODEL-REQUIRED"
        rows.append(row)
    return {
        "metricId": "P5",
        "method": "RAW-COUNTS-WITH-ZERO-EVENT-EXACT-UPPER-BOUND",
        "noPseudoCount": True,
        "rows": rows,
    }


def heterogeneous_audit_and_reanalysis(samples: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    per = [s for s in samples if s["comparisonCohortId"] == "per-agent-heterogeneous-goal-v1"]
    grouped = [s for s in samples if s["comparisonCohortId"] == "grouped-field-heterogeneous-goal-v1"]
    per_blocks = group_blocks(per)
    grouped_blocks = group_blocks(grouped)
    per_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    grouped_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    for block in per_blocks.values():
        per_by_key[(block[0]["scenarioId"], block[0]["blockOrdinal"])] = block
    for block in grouped_blocks.values():
        grouped_by_key[(block[0]["scenarioId"], block[0]["blockOrdinal"])] = block
    keys = sorted(set(per_by_key) & set(grouped_by_key))
    pair_rows: list[dict[str, Any]] = []
    cross_records: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for key in keys:
        per_block = per_by_key[key]
        group_block = grouped_by_key[key]
        p0, g0 = per_block[0], group_block[0]
        same_wave = p0["wave"] == g0["wave"]
        delta = g0["executionOrdinal"] - p0["executionOrdinal"]
        order = "PER_AGENT_THEN_GROUPED" if delta > 0 else "GROUPED_THEN_PER_AGENT"
        adjacent = abs(delta) == 1
        pair_identity = f"{key[0]}::b{key[1]:03d}"
        pair_rows.append({
            "matchedSuperblockCandidateId": pair_identity,
            "scenarioId": key[0],
            "blockOrdinal": key[1],
            "sameWave": same_wave,
            "perAgentExecutionOrdinal": p0["executionOrdinal"],
            "groupedFieldExecutionOrdinal": g0["executionOrdinal"],
            "executionOrdinalDeltaGroupedMinusPerAgent": delta,
            "adjacent": adjacent,
            "cohortOrder": order,
        })
        per_alg = {s["algorithmId"]: s for s in per_block}
        group_alg = {s["algorithmId"]: s for s in group_block}
        for metric_id in CONTINUOUS_METRICS:
            for contrast_id, numerator_id, denominator_id, _ in CONTRASTS[:4]:
                record = make_record(group_alg[numerator_id], per_alg[denominator_id], metric_id)
                if record is None:
                    continue
                record.update({"order": order, "adjacent": adjacent, "pairIdentity": pair_identity})
                cross_records[(metric_id, contrast_id, "ALL")].append(record)
                cross_records[(metric_id, contrast_id, key[0])].append(record)
                cross_records[(metric_id, contrast_id, order)].append(record)
                if adjacent:
                    cross_records[(metric_id, contrast_id, "ADJACENT")].append(record)
    order_counts = Counter(row["cohortOrder"] for row in pair_rows)
    scenario_counts = Counter(row["scenarioId"] for row in pair_rows)
    same_wave_count = sum(row["sameWave"] for row in pair_rows)
    adjacent_count = sum(row["adjacent"] for row in pair_rows)
    analysis_rows: list[dict[str, Any]] = []
    for metric_id in CONTINUOUS_METRICS:
        for contrast_id, numerator_id, denominator_id, sidedness in CONTRASTS[:4]:
            all_records = cross_records[(metric_id, contrast_id, "ALL")]
            stats = log_contrast_stats(all_records, sidedness)
            sensitivity = {}
            for label in ("PER_AGENT_THEN_GROUPED", "GROUPED_THEN_PER_AGENT", "ADJACENT"):
                subset = cross_records[(metric_id, contrast_id, label)]
                sensitivity[label] = log_contrast_stats(subset, sidedness)
            analysis_rows.append({
                "comparisonScope": "HETEROGENEOUS-CROSS-FAMILY-SECONDARY-SYSTEM-TREATMENT",
                "metricId": metric_id,
                "contrastId": contrast_id,
                "numeratorSystem": f"GROUPED-FIELD/{numerator_id}",
                "denominatorSystem": f"PER-AGENT/{denominator_id}",
                "pairing": "RETROSPECTIVE-MATCHED-BY-SCENARIO-AND-BLOCK/SAME-WAVE",
                "causalInterpretation": "NOT-PURE-ALGORITHM-EFFECT",
                "formalUse": "PILOT-DESCRIPTIVE-ONLY",
                "statistics": stats,
                "orderAndAdjacencySensitivity": sensitivity,
            })
    # Within-family paired rows remain interpretable because both algorithms
    # share one complete process-reuse block.
    within_specs = [
        ("HETEROGENEOUS-GROUPED-FIELD-WITHIN-BLOCK", grouped_blocks, "C5", "IDFF", "C-FF", "TWO-SIDED-HEAD-TO-HEAD"),
        ("HETEROGENEOUS-PER-AGENT-WITHIN-BLOCK", per_blocks, "DIAGNOSTIC-DSTARL-ASTARR", "D*L", "A*-R", "DIAGNOSTIC-BASELINE"),
    ]
    for scope, source_blocks, contrast_id, numerator_id, denominator_id, role in within_specs:
        for metric_id in CONTINUOUS_METRICS:
            records: list[dict[str, Any]] = []
            for block_samples in source_blocks.values():
                by_algorithm = {sample["algorithmId"]: sample for sample in block_samples}
                record = make_record(by_algorithm[numerator_id], by_algorithm[denominator_id], metric_id)
                if record is not None:
                    records.append(record)
            analysis_rows.append({
                "comparisonScope": scope,
                "metricId": metric_id,
                "contrastId": contrast_id,
                "numeratorAlgorithm": numerator_id,
                "denominatorAlgorithm": denominator_id,
                "pairing": "WITHIN-COMPLETE-WILLIAMS-BLOCK",
                "role": role,
                "formalUse": "PILOT-VARIANCE-PLANNING-ONLY",
                "statistics": log_contrast_stats(records, "two-sided" if contrast_id == "C5" else "directional"),
            })
    reverse_n = order_counts.get("GROUPED_THEN_PER_AGENT", 0)
    verdict = "INSUFFICIENT-EVIDENCE-FOR-DECISION" if reverse_n < 16 else "SUPPLEMENTAL-HETERO-PILOT-RECOMMENDED"
    audit = {
        "schemaVersion": SCHEMA_VERSION,
        "auditKind": "gate13r-rq-aligned-heterogeneous-order-audit-v1",
        "candidateMatchedPairCount": len(pair_rows),
        "scenarioCount": len(scenario_counts),
        "pairsPerScenario": dict(sorted(scenario_counts.items())),
        "sameWaveCount": same_wave_count,
        "adjacentCount": adjacent_count,
        "cohortOrderCounts": dict(sorted(order_counts.items())),
        "identity": [
            "MATCHABLE-BY-SCENARIO-AND-BLOCK",
            "SAME-WAVE",
            "ORDER-IMBALANCED",
            "NOT-ABBA-BALANCED",
            "PILOT-DESCRIPTIVE-ONLY-FOR-CROSS-FAMILY-MEAN"
        ],
        "expectedFactsConfirmed": (
            len(pair_rows) == 96
            and same_wave_count == 96
            and adjacent_count == 89
            and order_counts.get("PER_AGENT_THEN_GROUPED", 0) == 89
            and order_counts.get("GROUPED_THEN_PER_AGENT", 0) == 7
        ),
        "supplementalPilotVerdict": verdict,
        "verdictBasis": "Only 7 reverse-order pairs; order and scenario/wave effects cannot be separated reliably. Effect direction was not used.",
        "pairs": pair_rows,
    }
    return audit, analysis_rows


def covariance_matrix(vectors: list[list[float]], center_by_chunks: int = 32) -> list[list[float]]:
    if not vectors:
        raise ValueError("no covariance vectors")
    centered: list[list[float]] = []
    for start in range(0, len(vectors), center_by_chunks):
        chunk = vectors[start:start + center_by_chunks]
        column_means = [statistics.fmean(row[column] for row in chunk) for column in range(len(chunk[0]))]
        centered.extend([[value - column_means[column] for column, value in enumerate(row)] for row in chunk])
    p = len(vectors[0])
    denom = max(1, len(centered) - math.ceil(len(centered) / center_by_chunks))
    return [
        [sum(row[i] * row[j] for row in centered) / denom for j in range(p)]
        for i in range(p)
    ]


def cholesky_with_jitter(matrix: list[list[float]]) -> tuple[list[list[float]], float]:
    n = len(matrix)
    max_diag = max(matrix[i][i] for i in range(n))
    for exponent in range(-14, 1):
        jitter = max(1e-16, max_diag * (10.0 ** exponent))
        lower = [[0.0] * n for _ in range(n)]
        valid = True
        for i in range(n):
            for j in range(i + 1):
                value = matrix[i][j] + (jitter if i == j else 0.0)
                value -= sum(lower[i][k] * lower[j][k] for k in range(j))
                if i == j:
                    if value <= 0:
                        valid = False
                        break
                    lower[i][j] = math.sqrt(value)
                else:
                    lower[i][j] = value / lower[j][j]
            if not valid:
                break
        if valid:
            return lower, jitter
    raise RuntimeError("covariance matrix cannot be regularized")


def simulate_fwer(covariance: list[list[float]], blocks_per_campaign: int, seed: int) -> dict[str, Any]:
    # Scaling does not change standardized null statistics, but it is retained
    # explicitly to document the candidate design.
    estimator_cov = [[value / (32.0 * blocks_per_campaign) for value in row] for row in covariance]
    lower, jitter = cholesky_with_jitter(estimator_cov)
    sd = [math.sqrt(estimator_cov[i][i] + jitter) for i in range(5)]
    rng = random.Random(seed + blocks_per_campaign)
    any_reject = 0
    coverage_hits = [0] * 5
    estimate_sums = [0.0] * 5
    for _ in range(SIMULATION_REPLICATIONS):
        z = [rng.gauss(0.0, 1.0) for _ in range(5)]
        estimates = [sum(lower[i][k] * z[k] for k in range(i + 1)) for i in range(5)]
        p_values = [NormalDist().cdf(estimates[i] / sd[i]) for i in range(4)]
        p_values.append(2.0 * (1.0 - NormalDist().cdf(abs(estimates[4] / sd[4]))))
        adjusted = holm_adjust(p_values)
        if any(value < ALPHA for value in adjusted):
            any_reject += 1
        for i, estimate in enumerate(estimates):
            estimate_sums[i] += estimate
            if abs(estimate) <= NormalDist().inv_cdf(0.975) * sd[i]:
                coverage_hits[i] += 1
    fwer = any_reject / SIMULATION_REPLICATIONS
    return {
        "replications": SIMULATION_REPLICATIONS,
        "seed": seed + blocks_per_campaign,
        "holmFamilyWiseTypeIError": fwer,
        "holmFamilyWiseTypeIErrorMcse": math.sqrt(fwer * (1.0 - fwer) / SIMULATION_REPLICATIONS),
        "unadjusted95CiCoverageByContrast": {
            CONTRASTS[i][0]: coverage_hits[i] / SIMULATION_REPLICATIONS for i in range(5)
        },
        "biasByContrast": {
            CONTRASTS[i][0]: estimate_sums[i] / SIMULATION_REPLICATIONS for i in range(5)
        },
        "covarianceJitter": jitter,
        "modelStable": fwer <= 0.055 and all(coverage_hits[i] / SIMULATION_REPLICATIONS >= 0.94 for i in range(5)),
    }


def simulate_power(sd_log_ratio: float, blocks_per_campaign: int, contrast_index: int, effect: float, seed: int) -> dict[str, Any]:
    se = sd_log_ratio / math.sqrt(32.0 * blocks_per_campaign)
    sidedness = CONTRASTS[contrast_index][3]
    critical_alpha = ALPHA / len(CONTRASTS)
    critical = NormalDist().inv_cdf(1.0 - critical_alpha) if sidedness == "directional" else NormalDist().inv_cdf(1.0 - critical_alpha / 2.0)
    true_log_ratio = math.log(1.0 - effect)
    rng = random.Random(seed + blocks_per_campaign * 1000 + contrast_index * 100 + round(effect * 100))
    rejected = 0
    total_estimate = 0.0
    for _ in range(SIMULATION_REPLICATIONS):
        estimate = true_log_ratio + rng.gauss(0.0, se)
        total_estimate += estimate
        z = estimate / se
        if (sidedness == "directional" and z < -critical) or (sidedness == "two-sided" and abs(z) > critical):
            rejected += 1
    power = rejected / SIMULATION_REPLICATIONS
    return {
        "relativeEffectScenario": effect,
        "trueLogRatio": true_log_ratio,
        "holmWorstThresholdAlpha": critical_alpha,
        "power": power,
        "powerMcse": math.sqrt(power * (1.0 - power) / SIMULATION_REPLICATIONS),
        "bias": total_estimate / SIMULATION_REPLICATIONS - true_log_ratio,
        "interpretation": "PLANNING-SCENARIO-NOT-FROZEN-PRACTICAL-MARGIN",
    }


def candidate_designs(project_root: Path, covariance_vectors: dict[str, list[list[float]]], hetero_rows: list[dict[str, Any]], fixed_time: str) -> tuple[dict[str, Any], dict[str, Any]]:
    old_plan = load_json(project_root / "Research/Gate13R_Serial_10pct_Formal_Plan.v1.json")
    budget = load_json(project_root / PILOT_REL / "budget-storage-projection.json")
    old_cohorts = {row["comparisonCohortId"]: row for row in old_plan["cohorts"]}
    budget_rows = {row["comparisonCohortId"]: row for row in budget["rows"]}
    shared_id = "four-algorithm-shared-goal-v1"
    per_id = "per-agent-heterogeneous-goal-v1"
    group_id = "grouped-field-heterogeneous-goal-v1"
    covariance = covariance_matrix(covariance_vectors["P1"])
    pooled_sd = [math.sqrt(max(0.0, covariance[i][i])) for i in range(5)]
    pooled_df = len(covariance_vectors["P1"]) - math.ceil(len(covariance_vectors["P1"]) / 32)
    sigma_upper_factor = math.sqrt(pooled_df / chi_square_ppf(0.10, pooled_df))
    pooled_sigma_upper = [value * sigma_upper_factor for value in pooled_sd]
    hetero_p1 = {
        row["contrastId"]: row
        for row in hetero_rows
        if row.get("comparisonScope") == "HETEROGENEOUS-CROSS-FAMILY-SECONDARY-SYSTEM-TREATMENT"
        and row.get("metricId") == "P1"
    }
    candidates = [(32, 32), (40, 32), (48, 32), (40, 40), (48, 40), (48, 48)]
    decision_rows: list[dict[str, Any]] = []
    sensitivity_rows: list[dict[str, Any]] = []
    for s_blocks, h_superblocks in candidates:
        shared_processes = 32 * s_blocks
        shared_samples = shared_processes * 4
        hetero_superblocks = 21 * h_superblocks
        per_processes = hetero_superblocks
        group_processes = hetero_superblocks
        hetero_processes = per_processes + group_processes
        hetero_samples = hetero_superblocks * 4
        total_processes = shared_processes + hetero_processes
        total_samples = shared_samples + hetero_samples
        p50_seconds = (
            shared_processes * float(old_cohorts[shared_id]["p50BlockWallSeconds"])
            + per_processes * float(old_cohorts[per_id]["p50BlockWallSeconds"])
            + group_processes * float(old_cohorts[group_id]["p50BlockWallSeconds"])
        )
        p95_seconds = (
            shared_processes * float(old_cohorts[shared_id]["p95BlockWallSeconds"])
            + per_processes * float(old_cohorts[per_id]["p95BlockWallSeconds"])
            + group_processes * float(old_cohorts[group_id]["p95BlockWallSeconds"])
        )
        raw_bytes = (
            shared_processes * int(budget_rows[shared_id]["p95BlockRawBytes"])
            + per_processes * int(budget_rows[per_id]["p95BlockRawBytes"])
            + group_processes * int(budget_rows[group_id]["p95BlockRawBytes"])
        )
        safety_bytes = math.ceil(raw_bytes * 1.5)
        reserve = 40 * 1024 ** 3
        candidate_id = f"S{s_blocks}/H{h_superblocks}"
        decision_rows.append({
            "candidateId": candidate_id,
            "sharedBlocksPerCampaign": s_blocks,
            "heterogeneousMatchedSuperblocksPerScenario": h_superblocks,
            "sharedProcesses": shared_processes,
            "sharedSamples": shared_samples,
            "heterogeneousMatchedSuperblocks": hetero_superblocks,
            "heterogeneousProcesses": hetero_processes,
            "heterogeneousSamples": hetero_samples,
            "totalUnityProcesses": total_processes,
            "totalAlgorithmSamples": total_samples,
            "abQuotaPerHeterogeneousScenario": h_superblocks // 2,
            "baQuotaPerHeterogeneousScenario": h_superblocks - h_superblocks // 2,
            "serialP50Hours": p50_seconds / 3600.0,
            "conservativeSummedP95Hours": p95_seconds / 3600.0,
            "projectedP95RawBytes": raw_bytes,
            "projectedRawBytesWith1p5Safety": safety_bytes,
            "storageReserveBytes": reserve,
            "minimumFreeBytes": safety_bytes + reserve,
            "failureLossExposure": "ONE-INCOMPLETE-BLOCK-OR-SUPERBLOCK; NO-AUTO-RESUME",
            "status": "CANDIDATE/UNFROZEN/NOT-AUTHORIZED-FOR-LAUNCH",
        })
        simulation = simulate_fwer(covariance, s_blocks, FIXED_SIMULATION_SEED)
        contrast_power = []
        for index, contrast in enumerate(CONTRASTS):
            contrast_power.append({
                "contrastId": contrast[0],
                "pilotResidualSdLogRatio": pooled_sd[index],
                "pilotResidualSigmaUpper90LogRatio": pooled_sigma_upper[index],
                "projectedStandardErrorUsingSigmaUpper": pooled_sigma_upper[index] / math.sqrt(32.0 * s_blocks),
                "projectedUnadjusted95CiWidthLogUsingSigmaUpper": 2.0 * NormalDist().inv_cdf(0.975) * pooled_sigma_upper[index] / math.sqrt(32.0 * s_blocks),
                "effectScenarios": [
                    simulate_power(pooled_sigma_upper[index], s_blocks, index, effect, FIXED_SIMULATION_SEED)
                    for effect in (0.05, 0.10, 0.15, 0.20)
                ],
            })
        hetero_projection = []
        for contrast_id, *_ in CONTRASTS[:4]:
            source = hetero_p1[contrast_id]
            stats = source["statistics"]
            sigma_upper = stats.get("sigmaUpper90LogRatio")
            order_sensitivity = source["orderAndAdjacencySensitivity"]
            ab = order_sensitivity["PER_AGENT_THEN_GROUPED"].get("pointLogRatio")
            ba = order_sensitivity["GROUPED_THEN_PER_AGENT"].get("pointLogRatio")
            hetero_projection.append({
                "contrastId": contrast_id,
                "pilotDescriptiveSigmaUpper90LogRatio": sigma_upper,
                "projectedStandardErrorUsingSigmaUpper": sigma_upper / math.sqrt(21.0 * h_superblocks) if sigma_upper is not None else None,
                "projectedUnadjusted95CiWidthLogUsingSigmaUpper": 2.0 * NormalDist().inv_cdf(0.975) * sigma_upper / math.sqrt(21.0 * h_superblocks) if sigma_upper is not None else None,
                "orderStratumMeanDifferenceLog": (ab - ba) if ab is not None and ba is not None else None,
                "interpretation": "SECONDARY-SYSTEM-TREATMENT/DESCRIPTIVE-PROJECTION/ORDER-IMBALANCED-PILOT",
            })
        sensitivity_rows.append({
            "candidateId": candidate_id,
            "sharedBlocksPerCampaign": s_blocks,
            "heterogeneousMatchedSuperblocksPerScenario": h_superblocks,
            "sharedPrimarySimulation": simulation,
            "holmWorstThresholdPowerSensitivity": contrast_power,
            "heterogeneousSecondaryProjection": hetero_projection,
            "heterogeneousSecondaryNote": "H controls descriptive matched-superblock stability; it is not pure-algorithm confirmatory power.",
        })
    baseline = {
        "candidateId": "OLD-144-204-108",
        "sharedBlocksPerCampaign": 144,
        "perAgentBlocksPerCampaign": 204,
        "groupedFieldBlocksPerCampaign": 108,
        "totalUnityProcesses": int(old_plan["totals"]["blockProcessCount"]),
        "totalAlgorithmSamples": int(old_plan["totals"]["sampleCount"]),
        "serialP50Hours": float(old_plan["totals"]["serialP50Hours"]),
        "conservativeSummedP95Hours": float(old_plan["totals"]["serialP95Hours"]),
        "projectedRawBytesWithSafety": int(old_plan["totals"]["projectedRawBytesWithSafety"]),
        "storageReserveBytes": int(old_plan["totals"]["storageReserveBytes"]),
        "status": "PRE-AMENDMENT-COMPARISON-BASELINE/SUPERSEDED-PENDING-RQ-ALIGNED-SAMPLE-DESIGN-DECISION/NOT-AUTHORIZED-FOR-LAUNCH",
    }
    recommendation = {
        "candidateId": "S48/H32",
        "status": "RECOMMENDED-FOR-USER-DECISION/UNFROZEN",
        "rationale": [
            "Preserves the complete 74-campaign matrix and multiples-of-four Williams balance.",
            "Uses the largest preregistered shared-primary block count while retaining the minimum preregistered H32 for secondary descriptive heterogeneity.",
            "Its conservative summed-p95 projection remains below the earlier 36-hour planning boundary.",
            "Does not rely on favorable observed pilot effect direction.",
            "Requires the user to choose a practical-effect margin and decide whether a balanced supplemental heterogeneous pilot is needed."
        ],
        "importantLimitation": "No S32-S48 candidate reaches 80% Holm-worst-threshold power for every contrast under the 10% effect planning scenario; C2 is the limiting contrast. This is not a launch recommendation.",
    }
    sensitivity = {
        "schemaVersion": SCHEMA_VERSION,
        "analysisKind": "gate13r-rq-aligned-candidate-design-sensitivity-v1",
        "generatedAtUtc": fixed_time,
        "simulationReplications": SIMULATION_REPLICATIONS,
        "simulationSeed": FIXED_SIMULATION_SEED,
        "covarianceMethod": "WITHIN-PILOT-CAMPAIGN-CENTERED-P1-FIVE-CONTRAST-COVARIANCE",
        "candidateRows": sensitivity_rows,
        "practicalEffectMarginDecisionTable": [
            {"relativeEffect": effect, "status": "PLANNING-SCENARIO/UNFROZEN", "scientificInterpretation": f"A {int(effect*100)}% lower P1 ratio for the numerator algorithm."}
            for effect in (0.05, 0.10, 0.15, 0.20)
        ],
        "coverageTarget": 0.95,
        "familyWiseAlpha": ALPHA,
        "finalSampleDesign": "UNFROZEN",
        "recommendedButUnfrozen": recommendation,
    }
    wallclock = {
        "schemaVersion": SCHEMA_VERSION,
        "analysisKind": "gate13r-rq-aligned-wallclock-storage-decision-table-v1",
        "generatedAtUtc": fixed_time,
        "assumptions": {
            "topology": "STRICT-SERIAL/MAX-UNITY-CONCURRENCY-1",
            "sharedCampaignCount": 32,
            "heterogeneousScenarioCount": 21,
            "heterogeneousProcessesPerMatchedSuperblock": 2,
            "storageSafetyMultiplier": 1.5,
            "storageReserveGiB": 40,
            "wallTimeIsEstimateOnly": True,
        },
        "candidates": decision_rows,
        "preAmendmentBaseline": baseline,
        "recommendedButUnfrozen": recommendation,
    }
    return sensitivity, wallclock


def estimability_matrix(shared_rows: list[dict[str, Any]], hetero_rows: list[dict[str, Any]], p5: dict[str, Any], fixed_time: str) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for metric_id in CONTINUOUS_METRICS:
        for contrast_id, numerator, denominator, _ in CONTRASTS:
            rows.append({
                "scope": "SHARED-GOAL-PRIMARY-SCOPE",
                "metricId": metric_id,
                "contrastId": contrast_id,
                "estimability": "ESTIMABLE-FOR-PILOT-VARIANCE-PLANNING",
                "formalInference": False,
                "reasonCode": "ONLY-SIX-SHARED-PILOT-ANCHORS-NOT-FULL-FORMAL-MATRIX",
            })
    rows.append({
        "scope": "SHARED-GOAL-PRIMARY-SCOPE",
        "metricId": "P3-SCALING-SLOPE",
        "contrastId": "C1-C5",
        "estimability": "NOT-ESTIMABLE-FROM-GATE12R-V4",
        "formalInference": False,
        "reasonCode": "INSUFFICIENT-CONTROLLED-AGENT-COUNT-LEVELS/FORMAL-DESIGN-MAPPING-AVAILABLE",
    })
    p5_zero = all(
        row["overall"]["events"] == 0 and row["plan"]["events"] == 0 and row["repair"]["events"] == 0
        for row in p5["rows"]
    )
    for contrast_id, *_ in CONTRASTS:
        rows.append({
            "scope": "SHARED-GOAL-PRIMARY-SCOPE",
            "metricId": "P5",
            "contrastId": contrast_id,
            "estimability": "NOT-ESTIMABLE-FROM-ZERO-EVENT-PILOT" if p5_zero else "ESTIMABLE-ONLY-WITH-COUNT-MODEL",
            "formalInference": False,
            "reasonCode": "ZERO-EVENTS-NO-PSEUDOCOUNT" if p5_zero else "SUPPORTIVE-COUNT-ENDPOINT",
        })
    for metric_id in CONTINUOUS_METRICS:
        for contrast_id, *_ in CONTRASTS[:4]:
            rows.append({
                "scope": "HETEROGENEOUS-CROSS-FAMILY",
                "metricId": metric_id,
                "contrastId": contrast_id,
                "estimability": "DESCRIPTIVE-MATCHED-VARIANCE-ONLY",
                "formalInference": False,
                "reasonCode": "ORDER-IMBALANCED-NOT-ABBA-BALANCED/SECONDARY-SYSTEM-TREATMENT",
            })
        rows.append({
            "scope": "HETEROGENEOUS-GROUPED-FIELD-WITHIN-BLOCK",
            "metricId": metric_id,
            "contrastId": "C5",
            "estimability": "ESTIMABLE-FOR-PILOT-VARIANCE-PLANNING",
            "formalInference": False,
            "reasonCode": "WITHIN-GROUPED-FIELD-BLOCK-PAIRED",
        })
    for index in range(1, 6):
        rows.append({
            "scope": "PROSPECTIVE-GATE14R",
            "metricId": f"M{index}",
            "contrastId": "C1-C5",
            "estimability": "NOT-OBSERVED-IN-GATE12R/VARIANCE-NOT-ESTIMABLE-FROM-GATE12R",
            "formalInference": False,
            "reasonCode": "FUTURE-GATE14R-MOVEMENT-CONTRACT-REQUIRED",
        })
    return {
        "schemaVersion": SCHEMA_VERSION,
        "matrixKind": "gate13r-rq-aligned-estimability-matrix-v1",
        "generatedAtUtc": fixed_time,
        "rows": rows,
    }


def self_test() -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def check(name: str, condition: bool, detail: Any = None) -> None:
        checks.append({"name": name, "passed": bool(condition), "detail": detail})
        if not condition:
            raise AssertionError(f"self-test failed: {name}: {detail}")

    check("log-ratio", math.isclose(math.log(2.0) - math.log(4.0), math.log(0.5), rel_tol=0, abs_tol=1e-15))
    check("back-transform", math.isclose(math.exp(math.log(0.5)), 0.5, rel_tol=0, abs_tol=1e-15))
    fixture = {
        "dynamicHandlingMillisecondsPerScheduledEvent": 1.0,
        "dynamicHandlingTotalMilliseconds": 4.0,
        "dynamicHandlingP95Milliseconds": 2.0,
        "scheduledEventCount": 4,
        "totalPlannerElapsedMilliseconds": 20.0,
        "totalPlannerElapsedMillisecondsPerAgent": 2.0,
        "agentCount": 10,
        "dynamicManagedAllocatedBytes": 1024,
        "budgetExceededOperationCount": 3,
        "budgetExceededPlanCount": 1,
        "planOperationCount": 10,
        "repairOperationCount": 5,
    }
    metrics, errors = derive_metrics(fixture)
    check("fixture-no-errors", not errors, errors)
    check("p4-formula", metrics["P4"] == 256.0, metrics["P4"])
    check("p5-overall", metrics["P5"]["overallNumerator"] / metrics["P5"]["overallDenominator"] == 0.2)
    check("p5-plan", metrics["P5"]["planNumerator"] / metrics["P5"]["planDenominator"] == 0.1)
    check("p5-repair", metrics["P5"]["repairNumerator"] / metrics["P5"]["repairDenominator"] == 0.4)
    invalid = dict(fixture)
    invalid["budgetExceededOperationCount"] = 0
    invalid["budgetExceededPlanCount"] = 1
    _, invalid_errors = derive_metrics(invalid)
    check("p5-invalid-rejected", "P5-INVALID-DERIVED-REPAIR-COUNT" in invalid_errors, invalid_errors)
    expected_upper = 1.0 - math.pow(0.05, 1.0 / 100.0)
    check("zero-event-upper", math.isclose(zero_event_upper_95(0, 100), expected_upper, rel_tol=0, abs_tol=1e-15))
    adjusted = holm_adjust([0.001, 0.02, 0.03, 0.2, 0.8])
    check("holm-values", all(math.isclose(a, b, abs_tol=1e-15) for a, b in zip(adjusted, [0.005, 0.08, 0.09, 0.4, 0.8])), adjusted)
    q = chi_square_ppf(0.10, 31)
    check("chi-square-quantile", abs(q - 21.43356) < 1e-4, q)
    shared_processes, shared_samples = 32 * 32, 32 * 32 * 4
    hetero_superblocks, hetero_processes, hetero_samples = 21 * 32, 21 * 32 * 2, 21 * 32 * 4
    check("candidate-s32-h32", (shared_processes, shared_samples, hetero_superblocks, hetero_processes, hetero_samples) == (1024, 4096, 672, 1344, 2688))
    return {"schemaVersion": 1, "testKind": "gate13r-rq-aligned-analyzer-self-test-v1", "checks": checks, "passed": True}


def run_analysis(project_root: Path, output_root: Path, fixed_time: str) -> dict[str, Any]:
    bundle_path = project_root / "Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json"
    if sha256_file(bundle_path) != EXPECTED_BUNDLE_SHA:
        raise RuntimeError("Gate11R bundle manifest hash mismatch")
    formal_root = project_root / "Research/FormalRuns/Gate13R_Serial_10pct/v2"
    if formal_root.exists():
        raise RuntimeError("forbidden formal root exists")
    samples, metadata = load_pilot(project_root)
    observability = metric_observability(samples, metadata, fixed_time)
    if not observability["passed"]:
        raise RuntimeError("P1-P5 instrumentation gap")
    shared_rows, covariance_vectors = shared_reanalysis(samples)
    hetero_audit, hetero_rows = heterogeneous_audit_and_reanalysis(samples)
    if not hetero_audit["expectedFactsConfirmed"]:
        raise RuntimeError("heterogeneous order audit does not match frozen expected facts")
    p5 = p5_summary(samples)
    reanalysis = {
        "schemaVersion": SCHEMA_VERSION,
        "analysisKind": "gate13r-rq-aligned-gate12r-v4-contrast-variance-reanalysis-v1",
        "generatedAtUtc": fixed_time,
        "source": metadata,
        "primaryEndpoint": "P1",
        "transform": "NATURAL-LOG-RATIO-FOR-STRICTLY-POSITIVE-P1-P4",
        "independentUnits": {
            "shared": "ONE-FRESH-UNITY-PROCESS-COMPLETE-WILLIAMS-BLOCK",
            "heterogeneousCrossFamily": "RETROSPECTIVE-MATCHED-TWO-PROCESS-SUPERBLOCK-CANDIDATE"
        },
        "sharedRows": shared_rows,
        "heterogeneousRows": hetero_rows,
        "p5CountAnalysis": p5,
        "p3ScalingSlope": {
            "estimability": "NOT-ESTIMABLE-FROM-GATE12R-V4",
            "reasonCode": "INSUFFICIENT-CONTROLLED-AGENT-COUNT-LEVELS",
            "formalDesignMapping": "AVAILABLE-IN-GATE11R-FULL-MATRIX",
        },
        "oldAnalysisScope": ["D*L-minus-A*-R", "IDFF-minus-C-FF"],
        "newC1C4IncludedInOldCandidateNFormal": False,
        "formalInference": False,
        "excludedFromFormalAnalysis": True,
    }
    estimability = estimability_matrix(shared_rows, hetero_rows, p5, fixed_time)
    sensitivity, wallclock = candidate_designs(project_root, covariance_vectors, hetero_rows, fixed_time)
    outputs = {
        "metric-observability-audit.json": observability,
        "gate12r-v4-contrast-variance-reanalysis.json": reanalysis,
        "heterogeneous-order-audit.json": {**hetero_audit, "generatedAtUtc": fixed_time},
        "estimability-matrix.json": estimability,
        "candidate-design-sensitivity.json": sensitivity,
        "wallclock-storage-decision-table.json": wallclock,
    }
    for name, value in outputs.items():
        atomic_write_json(output_root / name, value)
    return {
        "analyzerId": ANALYZER_ID,
        "outputRoot": output_root.as_posix(),
        "outputFiles": {name: sha256_file(output_root / name) for name in sorted(outputs)},
        "pilotMetadata": metadata,
        "instrumentationGap": observability["instrumentationGap"],
        "heterogeneousSupplementalPilotVerdict": hetero_audit["supplementalPilotVerdict"],
        "recommendedButUnfrozenCandidate": sensitivity["recommendedButUnfrozen"]["candidateId"],
        "formalCampaignAuthorized": False,
        "unityStarted": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--fixed-time-utc", default="2026-10-08T10:40:36.7028036Z")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--print-tree-identity", type=Path)
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), ensure_ascii=False, sort_keys=True))
        return 0
    if args.print_tree_identity:
        print(json.dumps(tree_identity(args.print_tree_identity), ensure_ascii=False, sort_keys=True))
        return 0
    if args.output_root is None:
        parser.error("--output-root is required unless --self-test or --print-tree-identity is used")
    result = run_analysis(args.project_root.resolve(), args.output_root.resolve(), args.fixed_time_utc)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
