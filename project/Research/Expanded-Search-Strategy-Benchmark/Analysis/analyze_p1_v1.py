#!/usr/bin/env python3
"""Frozen Gate13R-AX2 P1 analysis implementation.

The experimental unit is one shared-goal campaign.  Each campaign first pools
its 48 complete Williams blocks on the log scale; inference then uses 32 paired
campaign-level log geometric means.  The script reports all four algorithms'
raw P1 geometric means and the four preregistered A*-family/flow-field ratios.
It does not declare a winner.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import pathlib
import statistics
import sys
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Sequence, Tuple


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"
ALGORITHMS = ("BiA*-R", "LPA*", "C-FF", "IDFF")
CONTRASTS = (
    ("BiA*-R/C-FF", "BiA*-R", "C-FF"),
    ("BiA*-R/IDFF", "BiA*-R", "IDFF"),
    ("LPA*/C-FF", "LPA*", "C-FF"),
    ("LPA*/IDFF", "LPA*", "IDFF"),
)


class AnalysisError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AnalysisError(message)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path: pathlib.Path) -> Any:
    require(path.is_file(), f"Required JSON is missing: {path}")
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise AnalysisError(f"Invalid JSON at {path}: {exc}") from exc


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def write_text_new(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(text)


def geometric_mean(values: Iterable[float]) -> float:
    materialized = list(values)
    require(materialized, "Geometric mean requires at least one observation.")
    for value in materialized:
        require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0.0, "P1 values must be finite and strictly positive.")
    return math.exp(math.fsum(math.log(value) for value in materialized) / len(materialized))


def beta_continued_fraction(a: float, b: float, x: float) -> float:
    maximum_iterations = 500
    epsilon = 3.0e-14
    floor = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < floor:
        d = floor
    d = 1.0 / d
    h = d
    for iteration in range(1, maximum_iterations + 1):
        doubled = 2 * iteration
        numerator = iteration * (b - iteration) * x / ((qam + doubled) * (a + doubled))
        d = 1.0 + numerator * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + numerator / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        h *= d * c
        numerator = -(a + iteration) * (qab + iteration) * x / ((a + doubled) * (qap + doubled))
        d = 1.0 + numerator * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + numerator / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= epsilon:
            return h
    raise AnalysisError("Incomplete-beta continued fraction failed to converge.")


def regularized_incomplete_beta(x: float, a: float, b: float) -> float:
    require(0.0 <= x <= 1.0 and a > 0.0 and b > 0.0, "Invalid incomplete-beta arguments.")
    if x == 0.0:
        return 0.0
    if x == 1.0:
        return 1.0
    log_term = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
    front = math.exp(log_term)
    if x < (a + 1.0) / (a + b + 2.0):
        return front * beta_continued_fraction(a, b, x) / a
    return 1.0 - front * beta_continued_fraction(b, a, 1.0 - x) / b


def student_t_cdf(value: float, degrees_of_freedom: int) -> float:
    require(degrees_of_freedom > 0 and math.isfinite(value), "Invalid Student t arguments.")
    if value == 0.0:
        return 0.5
    x = degrees_of_freedom / (degrees_of_freedom + value * value)
    tail_twice = regularized_incomplete_beta(x, degrees_of_freedom / 2.0, 0.5)
    return 1.0 - 0.5 * tail_twice if value > 0.0 else 0.5 * tail_twice


def student_t_ppf(probability: float, degrees_of_freedom: int) -> float:
    require(0.0 < probability < 1.0, "Student t probability must lie strictly between zero and one.")
    if probability == 0.5:
        return 0.0
    if probability < 0.5:
        return -student_t_ppf(1.0 - probability, degrees_of_freedom)
    lower = 0.0
    upper = 1.0
    while student_t_cdf(upper, degrees_of_freedom) < probability:
        upper *= 2.0
        require(upper < 1.0e6, "Student t quantile bracketing failed.")
    for _ in range(120):
        midpoint = (lower + upper) / 2.0
        if student_t_cdf(midpoint, degrees_of_freedom) < probability:
            lower = midpoint
        else:
            upper = midpoint
    return (lower + upper) / 2.0


def holm_adjust(p_values: Mapping[str, float]) -> Dict[str, float]:
    ordered = sorted(p_values.items(), key=lambda item: (item[1], item[0]))
    count = len(ordered)
    adjusted: Dict[str, float] = {}
    running = 0.0
    for index, (name, value) in enumerate(ordered):
        candidate = min(1.0, (count - index) * value)
        running = max(running, candidate)
        adjusted[name] = running
    return adjusted


def analyze_observations(observations: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    require(len(observations) == 32 * 48 * 4, f"Expected 6144 observations, found {len(observations)}.")
    values: Dict[Tuple[int, int, str], float] = {}
    campaign_ids: Dict[int, str] = {}
    for index, observation in enumerate(observations, start=1):
        campaign = observation.get("campaignOrdinal")
        block = observation.get("campaignBlockOrdinal")
        algorithm = observation.get("algorithmId")
        value = observation.get("p1")
        require(isinstance(campaign, int) and 1 <= campaign <= 32, f"Observation {index} has an invalid campaign ordinal.")
        require(isinstance(block, int) and 1 <= block <= 48, f"Observation {index} has an invalid block ordinal.")
        require(algorithm in ALGORITHMS, f"Observation {index} has an invalid algorithm.")
        require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0.0, f"Observation {index} P1 is not finite-positive.")
        campaign_id = observation.get("campaignId")
        require(isinstance(campaign_id, str) and campaign_id, f"Observation {index} campaign ID is missing.")
        campaign_ids.setdefault(campaign, campaign_id)
        require(campaign_ids[campaign] == campaign_id, f"Campaign {campaign} maps to multiple IDs.")
        key = (campaign, block, algorithm)
        require(key not in values, f"Duplicate observation for {key}.")
        values[key] = float(value)
    require(sorted(campaign_ids) == list(range(1, 33)), "Campaign ordinals are not exactly 1..32.")
    for campaign in range(1, 33):
        for block in range(1, 49):
            for algorithm in ALGORITHMS:
                require((campaign, block, algorithm) in values, f"Missing observation for campaign {campaign}, block {block}, algorithm {algorithm}.")
    raw_geometric_means = {
        algorithm: geometric_mean(values[(campaign, block, algorithm)] for campaign in range(1, 33) for block in range(1, 49))
        for algorithm in ALGORITHMS
    }
    campaign_geometric_means: Dict[int, Dict[str, float]] = {}
    for campaign in range(1, 33):
        campaign_geometric_means[campaign] = {
            algorithm: geometric_mean(values[(campaign, block, algorithm)] for block in range(1, 49))
            for algorithm in ALGORITHMS
        }
    degrees_of_freedom = 31
    critical_95 = student_t_ppf(0.975, degrees_of_freedom)
    critical_simultaneous = student_t_ppf(1.0 - 0.0125 / 2.0, degrees_of_freedom)
    contrast_results: List[Dict[str, Any]] = []
    raw_p_values: Dict[str, float] = {}
    for contrast_id, numerator, denominator in CONTRASTS:
        differences = [
            math.log(campaign_geometric_means[campaign][numerator]) - math.log(campaign_geometric_means[campaign][denominator])
            for campaign in range(1, 33)
        ]
        mean = statistics.fmean(differences)
        standard_deviation = statistics.stdev(differences)
        standard_error = standard_deviation / math.sqrt(len(differences))
        if standard_error == 0.0:
            t_statistic = math.copysign(math.inf, mean) if mean != 0.0 else 0.0
            p_value = 0.0 if mean != 0.0 else 1.0
        else:
            t_statistic = mean / standard_error
            p_value = 2.0 * (1.0 - student_t_cdf(abs(t_statistic), degrees_of_freedom))
        raw_p_values[contrast_id] = p_value
        contrast_results.append({
            "contrastId": contrast_id,
            "numeratorAlgorithmId": numerator,
            "denominatorAlgorithmId": denominator,
            "campaignCount": 32,
            "geometricMeanRatio": math.exp(mean),
            "logRatioMean": mean,
            "logRatioStandardDeviation": standard_deviation,
            "logRatioStandardError": standard_error,
            "tStatistic": t_statistic,
            "degreesOfFreedom": degrees_of_freedom,
            "rawTwoSidedPValue": p_value,
            "confidenceInterval95": [math.exp(mean - critical_95 * standard_error), math.exp(mean + critical_95 * standard_error)],
            "simultaneousBonferroniConfidenceInterval98_75": [
                math.exp(mean - critical_simultaneous * standard_error),
                math.exp(mean + critical_simultaneous * standard_error),
            ],
        })
    adjusted = holm_adjust(raw_p_values)
    for result in contrast_results:
        result["holmAdjustedPValue"] = adjusted[result["contrastId"]]
        result["holmFamilywiseRejectAt0_05"] = adjusted[result["contrastId"]] <= 0.05
    return {
        "experimentalUnit": "shared-goal campaign",
        "campaignCount": 32,
        "blocksPerCampaign": 48,
        "observationCount": len(observations),
        "rawP1GeometricMeanMillisecondsPerEvent": raw_geometric_means,
        "campaignP1GeometricMeansMillisecondsPerEvent": [
            {
                "campaignOrdinal": campaign,
                "campaignId": campaign_ids[campaign],
                "values": campaign_geometric_means[campaign],
            }
            for campaign in range(1, 33)
        ],
        "contrasts": contrast_results,
        "multiplicity": {
            "family": [contrast[0] for contrast in CONTRASTS],
            "twoSidedAlpha": 0.05,
            "pValueAdjustment": "Holm",
            "simultaneousIntervalMethod": "Bonferroni",
            "perContrastSimultaneousAlpha": 0.0125,
            "simultaneousConfidenceLevel": 0.9875,
        },
        "winnerDeclared": False,
    }


def observations_from_raw(root: pathlib.Path) -> List[Dict[str, Any]]:
    receipt = load_json(root / "_commit" / "raw-complete-receipt.v1.json")
    require(receipt.get("designId") == DESIGN_ID and receipt.get("status") == "FORMAL-RAW-COMPLETE", "P1 analysis requires a Gate13R-AX2 FORMAL-RAW-COMPLETE receipt.")
    accepted_dir = root / "_control" / "accepted-blocks"
    accepted_paths = sorted(accepted_dir.glob("*.v1.json"))
    require(len(accepted_paths) == 1536, "P1 analysis requires exactly 1536 accepted blocks.")
    observations: List[Dict[str, Any]] = []
    for path in accepted_paths:
        accepted = load_json(path)
        attempt = root / pathlib.PurePosixPath(accepted["attemptRelativePath"])
        complete = load_json(attempt / "block-complete.v1.json")
        require(len(complete.get("samples", [])) == 4, f"Block {complete.get('blockId')} is not complete.")
        for sample in complete["samples"]:
            result = load_json(attempt / pathlib.PurePosixPath(sample["workloadResultRelativePath"]))
            observations.append({
                "campaignOrdinal": complete["campaignOrdinal"],
                "campaignId": complete["campaignId"],
                "campaignBlockOrdinal": complete["campaignBlockOrdinal"],
                "algorithmId": sample["algorithmId"],
                "p1": result["dynamicHandlingMillisecondsPerScheduledEvent"],
            })
    return observations


def render_markdown(result: Mapping[str, Any]) -> str:
    lines = [
        "# Gate13R-AX2 P1 analysis",
        "",
        f"Generated: {result['analyzedAtUtc']}",
        "",
        "This report implements the frozen P1 analysis. It reports geometric means and preregistered contrasts; it does not declare a winner.",
        "",
        "## Raw P1 geometric means",
        "",
        "| Algorithm | Geometric mean (ms/event) |",
        "|---|---:|",
    ]
    for algorithm in ALGORITHMS:
        lines.append(f"| {algorithm} | {result['analysis']['rawP1GeometricMeanMillisecondsPerEvent'][algorithm]:.9g} |")
    lines.extend([
        "",
        "## Preregistered paired campaign-level contrasts",
        "",
        "| Contrast | GM ratio | 95% CI | Simultaneous 98.75% CI | Holm-adjusted p |",
        "|---|---:|---:|---:|---:|",
    ])
    for contrast in result["analysis"]["contrasts"]:
        ci95 = contrast["confidenceInterval95"]
        cisim = contrast["simultaneousBonferroniConfidenceInterval98_75"]
        lines.append(
            f"| {contrast['contrastId']} | {contrast['geometricMeanRatio']:.6g} | "
            f"[{ci95[0]:.6g}, {ci95[1]:.6g}] | [{cisim[0]:.6g}, {cisim[1]:.6g}] | "
            f"{contrast['holmAdjustedPValue']:.6g} |"
        )
    lines.extend(["", "No winner is declared by this implementation.", ""])
    return "\n".join(lines)


def command_analyze(args: argparse.Namespace) -> int:
    root = args.measured_root.resolve()
    require("/research/formalruns/gate13r-ax2/" in str(root).replace("\\", "/").lower(), "Analysis input is outside Gate13R-AX2 FormalRuns.")
    observations = observations_from_raw(root)
    result = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-P1-ANALYSIS",
        "designId": DESIGN_ID,
        "status": "P1-ANALYSIS-COMPLETE",
        "analyzedAtUtc": utc_now(),
        "analysis": analyze_observations(observations),
        "winnerDeclared": False,
        "originalGate13RRawOrAnalysisReadOrModified": False,
    }
    output_root = args.output_root.resolve()
    require(not output_root.exists(), "Analysis output root already exists; overwrite is forbidden.")
    output_root.mkdir(parents=True)
    json_path = output_root / "p1-analysis.v1.json"
    markdown_path = output_root / "p1-analysis.v1.md"
    write_json_new(json_path, result)
    write_text_new(markdown_path, render_markdown(result))
    print(json.dumps({"status": result["status"], "json": str(json_path), "markdown": str(markdown_path), "winnerDeclared": False}, sort_keys=True))
    return 0


def command_selftest(args: argparse.Namespace) -> int:
    assertions = 0
    critical_95 = student_t_ppf(0.975, 31)
    require(abs(critical_95 - 2.039513446) < 1.0e-6, f"Student t critical value differs: {critical_95}")
    assertions += 1
    require(abs(student_t_cdf(critical_95, 31) - 0.975) < 1.0e-10, "Student t CDF/PPF round trip failed.")
    assertions += 1
    synthetic: List[Dict[str, Any]] = []
    factors = {"BiA*-R": 0.80, "LPA*": 0.90, "C-FF": 1.00, "IDFF": 1.10}
    for campaign in range(1, 33):
        campaign_factor = 1.0 + campaign / 200.0
        for block in range(1, 49):
            block_factor = 1.0 + ((block % 7) - 3) / 1000.0
            for algorithm in ALGORITHMS:
                synthetic.append({
                    "campaignOrdinal": campaign,
                    "campaignId": f"synthetic-c{campaign:02d}",
                    "campaignBlockOrdinal": block,
                    "algorithmId": algorithm,
                    "p1": campaign_factor * block_factor * factors[algorithm],
                })
    result = analyze_observations(synthetic)
    assertions += 1
    require(abs(result["rawP1GeometricMeanMillisecondsPerEvent"]["BiA*-R"] / result["rawP1GeometricMeanMillisecondsPerEvent"]["C-FF"] - 0.8) < 1.0e-12, "Synthetic raw geometric-mean ratio differs.")
    assertions += 1
    contrast = next(item for item in result["contrasts"] if item["contrastId"] == "LPA*/IDFF")
    require(abs(contrast["geometricMeanRatio"] - 0.9 / 1.1) < 1.0e-12, "Synthetic paired contrast differs.")
    assertions += 1
    require(result["winnerDeclared"] is False, "Analysis implementation must not declare a winner.")
    assertions += 1
    broken = list(synthetic)
    broken[0] = dict(broken[0], p1=0.0)
    try:
        analyze_observations(broken)
    except AnalysisError:
        assertions += 1
        invalid_zero_rejected = True
    else:
        raise AnalysisError("Selftest failed to reject zero P1.")
    missing = synthetic[:-1]
    try:
        analyze_observations(missing)
    except AnalysisError:
        assertions += 1
        missing_observation_rejected = True
    else:
        raise AnalysisError("Selftest failed to reject a missing observation.")
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-P1-ANALYSIS-SELFTEST",
        "designId": DESIGN_ID,
        "status": "PASS",
        "validatedAtUtc": utc_now(),
        "assertionCount": assertions,
        "studentTCritical95Df31": critical_95,
        "syntheticObservationCount": len(synthetic),
        "invalidZeroRejected": invalid_zero_rejected,
        "missingObservationRejected": missing_observation_rejected,
        "rawGeometricMeansImplemented": True,
        "campaignPairedContrastsImplemented": True,
        "holmMultiplicityImplemented": True,
        "simultaneousIntervalsImplemented": True,
        "winnerDeclared": False,
        "formalDataRead": False,
        "originalGate13RRawOrAnalysisReadOrModified": False,
    }
    write_json_new(args.receipt.resolve(), receipt)
    print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), "assertionCount": assertions}, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    analyze = subparsers.add_parser("analyze")
    analyze.add_argument("--measured-root", type=pathlib.Path, required=True)
    analyze.add_argument("--output-root", type=pathlib.Path, required=True)
    analyze.set_defaults(handler=command_analyze)
    selftest = subparsers.add_parser("selftest")
    selftest.add_argument("--receipt", type=pathlib.Path, required=True)
    selftest.set_defaults(handler=command_selftest)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.handler(args)
    except (AnalysisError, OSError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
