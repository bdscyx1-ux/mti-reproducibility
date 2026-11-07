#!/usr/bin/env python3
"""Build a reporting-only raw-scale and formal-ratio provenance addendum.

The tool consumes only the frozen outputs of formal analysis attempt-004. It
does not refit a model, change an inference, or modify the source analysis.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple


STUDY_ID = "Gate14Re-ME"
ALGORITHMS = ("A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF")
COMPARATORS = ALGORITHMS[:-1]
TARGET = "IDFF"

ENDPOINTS: Tuple[Tuple[str, str, str, str, str], ...] = (
    (
        "D1_GEOMETRIC_MEAN_MILLISECONDS",
        "d1GeometricMeanMilliseconds",
        "ms",
        "log",
        "每条算法 lane 的24个 eventGroupElapsedMilliseconds 的几何均值",
    ),
    (
        "D1_NEAREST_RANK_P95_MILLISECONDS",
        "d1NearestRankP95Milliseconds",
        "ms",
        "log",
        "每条算法 lane 的24个 eventGroupElapsedMilliseconds 的最近秩P95",
    ),
    (
        "D2_GRID_ACCESSOR_CALLS",
        "d2GridAccessorCalls",
        "calls",
        "log",
        "每条算法 lane 的24个事件组 gridAccessorCallsTotal 之和；每组 total=contains+isWalkable+getTraversalCost",
    ),
    (
        "D2_GRID_CONTAINS_CALLS",
        "d2GridContainsCalls",
        "calls",
        "descriptive_only",
        "每条算法 lane 的24个事件组 gridContainsCalls 之和；为D2总调用数的组成项",
    ),
    (
        "D2_GRID_IS_WALKABLE_CALLS",
        "d2GridIsWalkableCalls",
        "calls",
        "descriptive_only",
        "每条算法 lane 的24个事件组 gridIsWalkableCalls 之和；为D2总调用数的组成项",
    ),
    (
        "D2_GRID_GET_TRAVERSAL_COST_CALLS",
        "d2GridGetTraversalCostCalls",
        "calls",
        "descriptive_only",
        "每条算法 lane 的24个事件组 gridGetTraversalCostCalls 之和；为D2总调用数的组成项",
    ),
    (
        "D3_TOTAL_MANAGED_ALLOCATION_BYTES",
        "d3TotalManagedAllocationBytes",
        "bytes",
        "log1p",
        "每条算法 lane 的24个 event-group D3 windows 的 managedAllocationBytes 之和",
    ),
    (
        "D4_MAX_PERSISTENT_STATE_BYTES",
        "d4MaxPersistentStateBytes",
        "bytes",
        "log1p",
        "每条算法 lane 的26个持久状态测量点 persistentStateBytesTotal 的最大值",
    ),
)

RATIO_MODELS: Tuple[Tuple[str, str, str, str], ...] = (
    ("D1_DYNAMIC_LATENCY", "D1_GEOMETRIC_MEAN_MILLISECONDS", "D1_GEOMETRIC_MEAN", "log"),
    ("D1_DYNAMIC_LATENCY", "D1_NEAREST_RANK_P95_MILLISECONDS", "D1_NEAREST_RANK_P95", "log"),
    ("D2_GRID_READ_WORK", "D2_GRID_ACCESSOR_CALLS", "D2", "log"),
    ("D3_DYNAMIC_ALLOCATION", "D3_TOTAL_MANAGED_ALLOCATION_BYTES", "D3", "log1p"),
    ("D4_PERSISTENT_STATE_BYTES", "D4_MAX_PERSISTENT_STATE_BYTES", "D4", "log1p"),
)

SLOPE_DOMAINS: Tuple[Tuple[str, str, str, Tuple[int, ...]], ...] = (
    ("D5_AGENT_COUNT_SCALING", "agentCount", "centeredLog2N", (32, 64, 128)),
    ("D6_CHANGE_FOOTPRINT_SCALING", "changedCellCount", "centeredLog2F", (1, 9, 25, 81)),
    ("D7_GRID_SIZE_SCALING", "gridEdge", "centeredLog2G2", (64, 96, 128)),
)


class AddendumError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_file(path: Path, expected_sha256: str, label: str) -> None:
    if not path.is_file():
        raise AddendumError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected_sha256.lower():
        raise AddendumError(f"{label} SHA-256 mismatch: {actual}")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise AddendumError(f"JSONL row is not an object: {path}:{line_number}")
            rows.append(value)
    return rows


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    path.write_text("".join(canonical_json(dict(row)) + "\n" for row in rows), encoding="utf-8")


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    if not rows:
        raise AddendumError(f"refusing to write empty CSV: {path.name}")
    fields = list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="raise")
        writer.writeheader()
        writer.writerows(rows)


def quantile(values: Sequence[float], probability: float) -> float:
    ordered = sorted(float(value) for value in values)
    position = probability * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def describe(values: Sequence[float], transform: str) -> Dict[str, Any]:
    data = [float(value) for value in values]
    if not data or any(not math.isfinite(value) for value in data):
        raise AddendumError("descriptive summary received empty or non-finite values")
    result: Dict[str, Any] = {
        "n": len(data),
        "mean": statistics.fmean(data),
        "sd": statistics.stdev(data) if len(data) > 1 else 0.0,
        "minimum": min(data),
        "p05": quantile(data, 0.05),
        "p25": quantile(data, 0.25),
        "median": quantile(data, 0.5),
        "p75": quantile(data, 0.75),
        "p95": quantile(data, 0.95),
        "maximum": max(data),
    }
    if transform == "log":
        if any(value <= 0.0 for value in data):
            raise AddendumError("log endpoint contains a nonpositive value")
        result["rawTransformCenter"] = math.exp(statistics.fmean(math.log(value) for value in data))
        result["rawTransformCenterDefinition"] = "exp(mean(log(Y)))"
    elif transform == "log1p":
        if any(value < 0.0 for value in data):
            raise AddendumError("log1p endpoint contains a negative value")
        result["rawTransformCenter"] = math.expm1(statistics.fmean(math.log1p(value) for value in data))
        result["rawTransformCenterDefinition"] = "expm1(mean(log1p(Y)))"
    else:
        result["rawTransformCenter"] = None
        result["rawTransformCenterDefinition"] = None
    return result


def approximately_equal(first: float, second: float) -> bool:
    return abs(first - second) <= max(1.0e-9, 1.0e-12 * max(abs(first), abs(second)))


def hypothesis_map(confirmatory: Mapping[str, Any]) -> Dict[Tuple[str, str], Mapping[str, Any]]:
    result: Dict[Tuple[str, str], Mapping[str, Any]] = {}
    for row in confirmatory["hypotheses"]:
        key = (str(row["domainId"]), str(row["comparator"]))
        if key in result:
            raise AddendumError(f"duplicate confirmatory hypothesis: {key}")
        result[key] = row
    return result


def endpoint_metadata() -> Dict[str, Dict[str, str]]:
    return {
        endpoint: {"field": field, "unit": unit, "transform": transform, "construction": construction}
        for endpoint, field, unit, transform, construction in ENDPOINTS
    }


def raw_algorithm_rows(
    lanes: Sequence[Mapping[str, Any]],
    descriptive: Mapping[str, Any],
) -> Tuple[List[Dict[str, Any]], Dict[Tuple[str, str], Dict[str, Any]]]:
    metadata = endpoint_metadata()
    grouped: Dict[str, List[Mapping[str, Any]]] = defaultdict(list)
    for lane in lanes:
        grouped[str(lane["algorithm"])].append(lane)
    existing = {str(row["algorithm"]): row for row in descriptive["byAlgorithm"]}
    rows: List[Dict[str, Any]] = []
    lookup: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for algorithm in ALGORITHMS:
        selected = grouped.get(algorithm, [])
        if len(selected) != 1296:
            raise AddendumError(f"expected 1296 lanes for {algorithm}, found {len(selected)}")
        for endpoint, info in metadata.items():
            summary = describe([float(lane[info["field"]]) for lane in selected], info["transform"])
            frozen = existing[algorithm]["endpoints"][endpoint]
            for name in ("n", "mean", "sd", "minimum", "p05", "p25", "median", "p75", "p95", "maximum"):
                if not approximately_equal(float(summary[name]), float(frozen[name])):
                    raise AddendumError(f"raw summary does not reproduce frozen descriptive value: {algorithm}/{endpoint}/{name}")
            payload = {
                "algorithm": algorithm,
                "endpoint": endpoint,
                "sourceField": info["field"],
                "unit": info["unit"],
                "sourceConstruction": info["construction"],
                "formalTransform": info["transform"],
                **summary,
            }
            rows.append(payload)
            lookup[(algorithm, endpoint)] = payload
    return rows, lookup


def raw_axis_rows(lanes: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for domain, field, _suffix, levels in SLOPE_DOMAINS:
        for level in levels:
            for algorithm in ALGORITHMS:
                values = [
                    float(lane["d1GeometricMeanMilliseconds"])
                    for lane in lanes
                    if str(lane["algorithm"]) == algorithm and int(lane[field]) == level
                ]
                summary = describe(values, "log")
                rows.append(
                    {
                        "domain": domain,
                        "axisField": field,
                        "axisLevel": level,
                        "algorithm": algorithm,
                        "endpoint": "D1_GEOMETRIC_MEAN_MILLISECONDS",
                        "unit": "ms",
                        **summary,
                    }
                )
    return rows


def ratio_rows(
    confirmatory: Mapping[str, Any],
    diagnostics: Mapping[str, Any],
    raw_lookup: Mapping[Tuple[str, str], Mapping[str, Any]],
) -> List[Dict[str, Any]]:
    hypotheses = hypothesis_map(confirmatory)
    rows: List[Dict[str, Any]] = []
    for domain, endpoint, model_id, transform in RATIO_MODELS:
        model = diagnostics["models"][model_id]
        coefficients = model["coefficients"]
        intercept = float(coefficients["Intercept"])
        for comparator in COMPARATORS:
            comparator_effect = float(coefficients[f"algorithm[{comparator}]"])
            eta_idff = intercept
            eta_comparator = intercept + comparator_effect
            adjusted_idff = math.exp(eta_idff) if transform == "log" else math.expm1(eta_idff)
            adjusted_comparator = math.exp(eta_comparator) if transform == "log" else math.expm1(eta_comparator)
            numerator = math.exp(eta_idff)
            denominator = math.exp(eta_comparator)
            recomputed_ratio = numerator / denominator
            hypothesis = hypotheses[(domain, comparator)]
            if domain == "D1_DYNAMIC_LATENCY":
                component_name = (
                    "equalDesignGeometricMeanRatio"
                    if endpoint == "D1_GEOMETRIC_MEAN_MILLISECONDS"
                    else "equalDesignNearestRankP95Ratio"
                )
                reported_ratio = float(hypothesis["components"][component_name]["ratioEstimate"])
            else:
                reported_ratio = float(hypothesis["component"]["ratioEstimate"])
            if not approximately_equal(recomputed_ratio, reported_ratio):
                raise AddendumError(f"formal ratio reproduction failed: {domain}/{endpoint}/{comparator}")
            raw_idff = raw_lookup[(TARGET, endpoint)]
            raw_comparator = raw_lookup[(comparator, endpoint)]
            formula = (
                "exp(eta_IDFF)/exp(eta_comparator) = adjusted_IDFF/adjusted_comparator"
                if transform == "log"
                else "exp(eta_IDFF)/exp(eta_comparator) = (adjusted_IDFF+1)/(adjusted_comparator+1)"
            )
            rows.append(
                {
                    "domain": domain,
                    "endpoint": endpoint,
                    "sourceField": raw_idff["sourceField"],
                    "unit": raw_idff["unit"],
                    "sourceConstruction": raw_idff["sourceConstruction"],
                    "model": model_id,
                    "transform": transform,
                    "comparator": comparator,
                    "idffRawN": raw_idff["n"],
                    "idffRawMean": raw_idff["mean"],
                    "idffRawMedian": raw_idff["median"],
                    "comparatorRawN": raw_comparator["n"],
                    "comparatorRawMean": raw_comparator["mean"],
                    "comparatorRawMedian": raw_comparator["median"],
                    "idffReferenceLinearPredictor": eta_idff,
                    "comparatorReferenceLinearPredictor": eta_comparator,
                    "idffReferenceAdjustedRawScale": adjusted_idff,
                    "comparatorReferenceAdjustedRawScale": adjusted_comparator,
                    "formalRatioNumerator": numerator,
                    "formalRatioDenominator": denominator,
                    "formalRatioFormula": formula,
                    "recomputedFormalRatio": recomputed_ratio,
                    "reportedFormalRatio": reported_ratio,
                    "absoluteReproductionError": abs(recomputed_ratio - reported_ratio),
                }
            )
    return rows


def slope_rows(
    confirmatory: Mapping[str, Any],
    diagnostics: Mapping[str, Any],
) -> List[Dict[str, Any]]:
    hypotheses = hypothesis_map(confirmatory)
    coefficients = diagnostics["models"]["D1_GEOMETRIC_MEAN"]["coefficients"]
    intercept = float(coefficients["Intercept"])
    center_map = {
        "centeredLog2N": float(diagnostics["axisCenters"]["log2N"]),
        "centeredLog2F": float(diagnostics["axisCenters"]["log2F"]),
        "centeredLog2G2": float(diagnostics["axisCenters"]["log2G2"]),
    }
    rows: List[Dict[str, Any]] = []
    for domain, axis_field, suffix, levels in SLOPE_DOMAINS:
        idff_slope = float(coefficients[suffix])
        center = center_map[suffix]
        for comparator in COMPARATORS:
            interaction = float(coefficients[f"algorithm[{comparator}]:{suffix}"])
            comparator_slope = idff_slope + interaction
            slope_difference = idff_slope - comparator_slope
            hypothesis = hypotheses[(domain, comparator)]
            component = hypothesis["component"]
            reported = float(component["estimateModelScale"])
            if not approximately_equal(slope_difference, reported):
                raise AddendumError(f"formal slope reproduction failed: {domain}/{comparator}")
            algorithm_effect = float(coefficients[f"algorithm[{comparator}]"])
            curve: List[Dict[str, Any]] = []
            for level in levels:
                modeled_axis = math.log2(level * level) if axis_field == "gridEdge" else math.log2(level)
                delta = modeled_axis - center
                eta_idff = intercept + idff_slope * delta
                eta_comparator = intercept + algorithm_effect + comparator_slope * delta
                curve.append(
                    {
                        "axisLevel": level,
                        "idffReferenceAdjustedMilliseconds": math.exp(eta_idff),
                        "comparatorReferenceAdjustedMilliseconds": math.exp(eta_comparator),
                    }
                )
            interval = component["simultaneousTwoSidedBonferroniIntervalModelScale"]
            rows.append(
                {
                    "domain": domain,
                    "sourceEndpoint": "D1_GEOMETRIC_MEAN_MILLISECONDS",
                    "sourceField": "d1GeometricMeanMilliseconds",
                    "axisField": axis_field,
                    "axisLevels": list(levels),
                    "modelAxis": suffix,
                    "comparator": comparator,
                    "idffSlopePerLog2AxisUnit": idff_slope,
                    "comparatorSlopePerLog2AxisUnit": comparator_slope,
                    "recomputedIdffMinusComparatorSlope": slope_difference,
                    "reportedIdffMinusComparatorSlope": reported,
                    "simultaneousInterval": interval,
                    "holmAdjustedOneSidedP": float(hypothesis["holmAdjustedOneSidedP"]),
                    "hypothesisPassed": bool(hypothesis["rejectAtFamilywiseAlpha0.05"]),
                    "referenceCurve": curve,
                    "absoluteReproductionError": abs(slope_difference - reported),
                }
            )
    return rows


def fmt(value: Any) -> str:
    if value is None:
        return "—"
    if isinstance(value, int):
        return str(value)
    return f"{float(value):.6g}"


def build_report(
    reference: Mapping[str, Any],
    raw_rows: Sequence[Mapping[str, Any]],
    axis_rows: Sequence[Mapping[str, Any]],
    ratios: Sequence[Mapping[str, Any]],
    slopes: Sequence[Mapping[str, Any]],
) -> str:
    lines = [
        "# Gate14Re-ME formal ST attempt-004 原始量纲与比率来源报告",
        "",
        "## 报告边界",
        "",
        "本文件是 reporting-only addendum：不重新拟合模型，不改变 attempt-004 的35个正式假设、Holm校正、同时区间、域通过值或总体结论。独立单位仍为1296个配对 superblock；每个算法各有1296条分析 lane。",
        "",
        "这里的“原始量纲数据”指正式分析直接使用的每-lane端点值，而不是把更底层的 event、query 或 measurement-point 行当作独立样本。完整7776条 per-lane值保存在 attempt-004 的 lane-estimands.v1.jsonl。",
        "",
        "## 从底层测量到正式比率",
        "",
        "- D1 GM：每条lane的24个 eventGroupElapsedMilliseconds 先计算几何均值；模型使用 log(D1 GM ms)。",
        "- D1 P95：每条lane的24个 eventGroupElapsedMilliseconds 先计算最近秩P95；模型使用 log(D1 P95 ms)。",
        "- D2：每条lane先对24个事件组的 gridAccessorCallsTotal 求和；每组 total=contains+isWalkable+getTraversalCost；模型使用 log(total calls)。",
        "- D3：每条lane先对24个 event-group D3 windows 的 managedAllocationBytes 求和；模型使用 log1p(total bytes)。",
        "- D4：每条lane从26个持久状态测量点取 persistentStateBytesTotal 最大值；模型使用 log1p(max bytes)。",
        "",
        "正式比率是同一个预设配对模型中的算法对比，不是下表原始算术均值的直接相除。D1/D2 的比率为 exp(η_IDFF−η_comparator)=调整后原始量纲值之比；D3/D4 因使用 log1p，正式比率为 exp(η_IDFF−η_comparator)=(调整后IDFF值+1)/(调整后比较算法值+1)。",
        "",
        "## 模型参考设计点",
        "",
        f"- 连续轴中心：N={fmt(reference['agentCountEquivalent'])}；F={fmt(reference['changedCellCountEquivalent'])}；G²={fmt(reference['gridAreaEquivalent'])}（对应G={fmt(reference['gridEdgeEquivalent'])}）。",
        "- 分类参考水平：changeTopology=compact；graphProfile=four_way_weighted_dense；sameTickAtomicPartitions=1；executionPosition=0。",
        "- 表中的模型调整分子/分母是固定效应线性预测值在上述参考点反变换后的值；随机截距设为0。算法比率在共享分类主效应下保持不变。",
        "",
        "## 正式比率的原始数据与分子/分母",
        "",
        "| 域/端点 | 比较算法 | IDFF原始均值/中位数 | 比较算法原始均值/中位数 | 模型调整IDFF | 模型调整比较算法 | 正式计算 | 正式比率 |",
        "|---|---|---:|---:|---:|---:|---|---:|",
    ]
    for row in ratios:
        if row["transform"] == "log":
            calculation = f"{fmt(row['formalRatioNumerator'])}/{fmt(row['formalRatioDenominator'])}"
        else:
            calculation = (
                f"({fmt(row['idffReferenceAdjustedRawScale'])}+1)/"
                f"({fmt(row['comparatorReferenceAdjustedRawScale'])}+1)"
            )
        lines.append(
            f"| {row['domain']} / {row['endpoint']} | {row['comparator']} | "
            f"{fmt(row['idffRawMean'])} / {fmt(row['idffRawMedian'])} | "
            f"{fmt(row['comparatorRawMean'])} / {fmt(row['comparatorRawMedian'])} | "
            f"{fmt(row['idffReferenceAdjustedRawScale'])} | {fmt(row['comparatorReferenceAdjustedRawScale'])} | "
            f"{calculation} | {fmt(row['reportedFormalRatio'])} |"
        )
    lines += [
        "",
        "## 各算法原始量纲分布",
        "",
        "每行 n=1296 个配对 superblock 中该算法对应的 lane。IQR 为P25–P75；P05–P95和最小–最大值用于展示分布范围。",
        "",
        "| 算法 | 端点 | 单位 | n | 均值 | 中位数 | IQR | P05–P95 | 最小–最大 | 原始变换中心 |",
        "|---|---|---|---:|---:|---:|---|---|---|---:|",
    ]
    for row in raw_rows:
        lines.append(
            f"| {row['algorithm']} | {row['endpoint']} | {row['unit']} | {row['n']} | {fmt(row['mean'])} | "
            f"{fmt(row['median'])} | [{fmt(row['p25'])}, {fmt(row['p75'])}] | "
            f"[{fmt(row['p05'])}, {fmt(row['p95'])}] | [{fmt(row['minimum'])}, {fmt(row['maximum'])}] | "
            f"{fmt(row['rawTransformCenter'])} |"
        )
    lines += [
        "",
        "## D5–D7斜率来源",
        "",
        "D5–D7不是比率检验，而是同一 log(D1 GM ms) 模型中的算法×轴交互。正式效应为 IDFF斜率−比较算法斜率；同时区间和Holm p沿用attempt-004。",
        "",
        "| 域 | 比较算法 | IDFF斜率 | 比较算法斜率 | 斜率差 | 同时区间 | Holm p | 通过 |",
        "|---|---|---:|---:|---:|---|---:|---:|",
    ]
    for row in slopes:
        interval = row["simultaneousInterval"]
        lines.append(
            f"| {row['domain']} | {row['comparator']} | {fmt(row['idffSlopePerLog2AxisUnit'])} | "
            f"{fmt(row['comparatorSlopePerLog2AxisUnit'])} | {fmt(row['reportedIdffMinusComparatorSlope'])} | "
            f"[{fmt(interval[0])}, {fmt(interval[1])}] | {fmt(row['holmAdjustedOneSidedP'])} | "
            f"{'是' if row['hypothesisPassed'] else '否'} |"
        )
    lines += [
        "",
        "## D5–D7各轴水平的原始量纲数据",
        "",
        "下表汇总作为斜率来源的 D1_GEOMETRIC_MEAN_MILLISECONDS，每个轴水平按算法分别展示；其他设计因素未在此描述表中调整。",
        "",
        "| 域 | 轴 | 水平 | 算法 | n | 均值(ms) | 中位数(ms) | IQR | P05–P95 |",
        "|---|---|---:|---|---:|---:|---:|---|---|",
    ]
    for row in axis_rows:
        lines.append(
            f"| {row['domain']} | {row['axisField']} | {row['axisLevel']} | {row['algorithm']} | {row['n']} | "
            f"{fmt(row['mean'])} | {fmt(row['median'])} | [{fmt(row['p25'])}, {fmt(row['p75'])}] | "
            f"[{fmt(row['p05'])}, {fmt(row['p95'])}] |"
        )
    lines += [
        "",
        "机器可读的完整数值见同目录 JSON 和 CSV。所有算法与域均按冻结合同顺序展示，不作排名或赢家判定。",
        "",
    ]
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--tool-sha256", required=True)
    parser.add_argument("--terminal-sha256", required=True)
    parser.add_argument("--confirmatory-sha256", required=True)
    parser.add_argument("--descriptive-sha256", required=True)
    parser.add_argument("--diagnostics-sha256", required=True)
    parser.add_argument("--lanes-sha256", required=True)
    parser.add_argument("--hard-gates-sha256", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    started = time.perf_counter()
    started_at = utc_now()
    analysis_root = Path(args.analysis_root).resolve(strict=True)
    output_root = Path(args.output_root).resolve(strict=False)
    if output_root.exists():
        raise AddendumError(f"output root must be fresh: {output_root}")
    require_file(Path(__file__).resolve(), args.tool_sha256, "reporting tool")
    inputs = {
        "analysis-terminal-receipt.v1.json": args.terminal_sha256,
        "confirmatory-results.v1.json": args.confirmatory_sha256,
        "descriptive-summaries.v1.json": args.descriptive_sha256,
        "model-fit-diagnostics.v1.json": args.diagnostics_sha256,
        "lane-estimands.v1.jsonl": args.lanes_sha256,
        "hard-gates.v1.json": args.hard_gates_sha256,
    }
    for name, digest in inputs.items():
        require_file(analysis_root / name, digest, name)
    terminal = read_json(analysis_root / "analysis-terminal-receipt.v1.json")
    confirmatory = read_json(analysis_root / "confirmatory-results.v1.json")
    descriptive = read_json(analysis_root / "descriptive-summaries.v1.json")
    diagnostics = read_json(analysis_root / "model-fit-diagnostics.v1.json")
    hard_gates = read_json(analysis_root / "hard-gates.v1.json")
    lanes = read_jsonl(analysis_root / "lane-estimands.v1.jsonl")
    if terminal.get("status") != "PASS_FORMAL_ST_ANY_FOUR_OF_FIVE_DOMAIN_RULE_ANALYSIS":
        raise AddendumError("source analysis terminal status mismatch")
    if len(confirmatory.get("hypotheses", [])) != 35 or len(lanes) != 7776:
        raise AddendumError("source analysis cardinality mismatch")
    if len({str(row["superblockId"]) for row in lanes}) != 1296:
        raise AddendumError("source lanes do not contain 1296 superblocks")
    if any(value is not True for key, value in hard_gates.items() if key != "schema"):
        raise AddendumError("one or more source hard gates are not true")

    raw_rows, raw_lookup = raw_algorithm_rows(lanes, descriptive)
    axis_rows = raw_axis_rows(lanes)
    ratios = ratio_rows(confirmatory, diagnostics, raw_lookup)
    slopes = slope_rows(confirmatory, diagnostics)
    if len(raw_rows) != 48 or len(axis_rows) != 60 or len(ratios) != 25 or len(slopes) != 15:
        raise AddendumError("reporting row cardinality mismatch")

    centers = diagnostics["axisCenters"]
    reference = {
        "centeredLog2N": float(centers["log2N"]),
        "centeredLog2F": float(centers["log2F"]),
        "centeredLog2G2": float(centers["log2G2"]),
        "agentCountEquivalent": 2.0 ** float(centers["log2N"]),
        "changedCellCountEquivalent": 2.0 ** float(centers["log2F"]),
        "gridAreaEquivalent": 2.0 ** float(centers["log2G2"]),
        "gridEdgeEquivalent": math.sqrt(2.0 ** float(centers["log2G2"])),
        "changeTopology": "compact",
        "graphProfile": "four_way_weighted_dense",
        "sameTickAtomicPartitions": 1,
        "executionPosition": 0,
        "randomIntercept": 0.0,
    }
    payload = {
        "schema": "gate14re-me-formal-st-raw-scale-ratio-provenance-v1",
        "studyId": STUDY_ID,
        "status": "PASS_REPORTING_ONLY_RAW_SCALE_AND_RATIO_PROVENANCE",
        "sourceAnalysisAttempt": "attempt-004",
        "sourceBindings": {name: digest.lower() for name, digest in inputs.items()},
        "independentUnit": "superblock",
        "independentN": 1296,
        "pairedAlgorithmsPerSuperblock": 6,
        "modelReferenceDesign": reference,
        "rawScaleByAlgorithm": raw_rows,
        "rawScaleByAxis": axis_rows,
        "formalRatioProvenance": ratios,
        "formalSlopeProvenance": slopes,
        "checks": {
            "frozenDescriptiveSummariesReproduced": True,
            "formalRatiosReproduced": 25,
            "formalSlopeContrastsReproduced": 15,
            "formalInferenceModified": False,
            "sourceAnalysisModified": False,
            "rankingOrWinnerComputed": False,
        },
        "createdAtUtc": utc_now(),
    }

    output_root.mkdir(parents=True, exist_ok=False)
    json_path = output_root / "raw-scale-and-ratio-provenance.v1.json"
    raw_csv = output_root / "raw-scale-by-algorithm.v1.csv"
    axis_csv = output_root / "raw-scale-by-axis.v1.csv"
    ratio_csv = output_root / "formal-ratio-provenance.v1.csv"
    slope_csv = output_root / "formal-slope-provenance.v1.csv"
    report_path = output_root / "formal-st-raw-scale-and-ratio-provenance.zh-CN.v1.md"
    write_json(json_path, payload)
    write_csv(raw_csv, raw_rows)
    write_csv(axis_csv, axis_rows)
    write_csv(ratio_csv, ratios)
    slope_flat = [
        {key: value for key, value in row.items() if key != "referenceCurve"}
        | {"referenceCurve": canonical_json(row["referenceCurve"])}
        for row in slopes
    ]
    write_csv(slope_csv, slope_flat)
    report_path.write_text(build_report(reference, raw_rows, axis_rows, ratios, slopes), encoding="utf-8")

    listed = [json_path, raw_csv, axis_csv, ratio_csv, slope_csv, report_path]
    manifest_rows = [
        {
            "schema": "gate14re-me-formal-st-reporting-addendum-file-v1",
            "relativePath": path.relative_to(output_root).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for path in listed
    ]
    manifest_path = output_root / "file-manifest.v1.jsonl"
    write_jsonl(manifest_path, manifest_rows)
    terminal_receipt = {
        "schema": "gate14re-me-formal-st-reporting-addendum-terminal-v1",
        "studyId": STUDY_ID,
        "status": "PASS_REPORTING_ONLY_RAW_SCALE_AND_RATIO_PROVENANCE",
        "sourceAnalysisAttempt": "attempt-004",
        "fileManifestSha256": sha256_file(manifest_path),
        "fileManifestRows": len(manifest_rows),
        "rawScaleByAlgorithmRows": len(raw_rows),
        "rawScaleByAxisRows": len(axis_rows),
        "formalRatioRows": len(ratios),
        "formalSlopeRows": len(slopes),
        "formalRatiosReproduced": 25,
        "formalSlopeContrastsReproduced": 15,
        "formalInferenceModified": False,
        "sourceAnalysisModified": False,
        "rankingOrWinnerComputed": False,
        "startedAtUtc": started_at,
        "completedAtUtc": utc_now(),
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }
    terminal_path = output_root / "reporting-addendum-terminal-receipt.v1.json"
    write_json(terminal_path, terminal_receipt)
    print(canonical_json(terminal_receipt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
