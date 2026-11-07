#!/usr/bin/env python3
"""Gate 13R-PR2 attempt-4 Phase B formal analysis implementation.

This module is intentionally inert unless it receives a separate, explicit
Phase-B *execution* authorization bound to the frozen contract.  Importing the
module and running ``--self-test`` never opens formal outcome files.

The implementation is standard-library only, writes exclusively to a sibling
staging directory below the contract-selected analysis parent, and commits the
finished output directory with a single rename.  It never launches Unity and
contains no Gate-14R analysis path.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import statistics
import sys
import uuid
from collections import Counter, defaultdict
from pathlib import Path
from statistics import NormalDist
from typing import Any, Iterable


ANALYZER_ID = "gate13r-pr2-attempt4-phaseb-analyzer-v1"
CONTRACT_KIND = "GATE13R-PR2-ATTEMPT4-PHASEB-FROZEN-EXECUTION-CONTRACT"
EXECUTION_AUTHORIZATION_KIND = "GATE13R-PR2-ATTEMPT4-PHASEB-FORMAL-ANALYSIS-EXECUTION"
ALPHA = 0.05
SHARED_COHORT = "four-algorithm-shared-goal-v1"
PER_AGENT_COHORT = "per-agent-heterogeneous-goal-v1"
GROUPED_FIELD_COHORT = "grouped-field-heterogeneous-goal-v1"
EXPECTED_ALGORITHMS = ("A*-R", "D*L", "IDFF", "C-FF")
CONTINUOUS_METRICS = ("P1", "P2", "P3-PER-AGENT", "P4")
CONTRASTS: tuple[dict[str, str], ...] = (
    {"id": "C1", "numerator": "C-FF", "denominator": "A*-R", "sidedness": "directional"},
    {"id": "C2", "numerator": "C-FF", "denominator": "D*L", "sidedness": "directional"},
    {"id": "C3", "numerator": "IDFF", "denominator": "A*-R", "sidedness": "directional"},
    {"id": "C4", "numerator": "IDFF", "denominator": "D*L", "sidedness": "directional"},
    {"id": "C5", "numerator": "IDFF", "denominator": "C-FF", "sidedness": "two-sided"},
)
P3_SCALE_LEVELS = (1, 8, 32, 128, 512)
P3_SCALE_PATTERN = re.compile(r"^agent-scale-a(001|008|032|128|512)-shared$")
OUTPUT_FILENAMES = (
    "analysis-input-audit.json",
    "schedule-coverage-and-missingness.json",
    "shared-primary-p1-analysis.json",
    "shared-supportive-p2-p5-analysis.json",
    "heterogeneous-secondary-analysis.json",
)


class AnalysisError(RuntimeError):
    """Fail-closed error for authorization, provenance, or analysis violations."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AnalysisError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        value = json.load(handle)
    require(isinstance(value, dict), f"JSON root must be an object: {path}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            value = json.loads(stripped)
            require(isinstance(value, dict), f"JSONL row {line_number} must be an object: {path}")
            yield value


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def resolve_relative(root: Path, relative_path: str, label: str) -> Path:
    require(isinstance(relative_path, str) and relative_path.strip() != "", f"{label}: empty path")
    candidate = (root / Path(relative_path.replace("/", os.sep))).resolve()
    resolved_root = root.resolve()
    require(candidate == resolved_root or candidate.is_relative_to(resolved_root), f"{label}: path escapes root")
    return candidate


def verified_bound_file(project_root: Path, binding: dict[str, Any], label: str) -> Path:
    require(isinstance(binding, dict), f"{label}: binding is not an object")
    path = resolve_relative(project_root, str(binding.get("relativePath", "")), label)
    require(path.is_file(), f"{label}: missing file {path}")
    expected_hash = str(binding.get("sha256", "")).lower()
    require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"{label}: invalid SHA-256")
    actual_hash = sha256_file(path)
    require(actual_hash == expected_hash, f"{label}: SHA-256 mismatch")
    return path


def finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def approximately_equal(left: float, right: float) -> bool:
    return math.isclose(left, right, rel_tol=1e-9, abs_tol=1e-9)


def sample_sd(values: list[float]) -> float | None:
    return statistics.stdev(values) if len(values) >= 2 else None


def regularized_gamma_p(shape: float, x: float) -> float:
    require(shape > 0 and x >= 0, "invalid incomplete-gamma arguments")
    if x == 0:
        return 0.0
    epsilon = 1e-14
    maximum_iterations = 10000
    if x < shape + 1.0:
        term = 1.0 / shape
        total = term
        ap = shape
        for _ in range(maximum_iterations):
            ap += 1.0
            term *= x / ap
            total += term
            if abs(term) <= abs(total) * epsilon:
                break
        return total * math.exp(-x + shape * math.log(x) - math.lgamma(shape))
    tiny = 1e-300
    b = x + 1.0 - shape
    c = 1.0 / tiny
    d = 1.0 / b
    h = d
    for index in range(1, maximum_iterations + 1):
        coefficient = -index * (index - shape)
        b += 2.0
        d = coefficient * d + b
        if abs(d) < tiny:
            d = tiny
        c = b + coefficient / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= epsilon:
            break
    q_value = math.exp(-x + shape * math.log(x) - math.lgamma(shape)) * h
    return 1.0 - q_value


def chi_square_ppf(probability: float, degrees_freedom: int) -> float:
    require(0.0 < probability < 1.0 and degrees_freedom > 0, "invalid chi-square quantile request")
    low = 0.0
    high = float(degrees_freedom)
    while regularized_gamma_p(degrees_freedom / 2.0, high / 2.0) < probability:
        high *= 2.0
    for _ in range(180):
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
    degrees_freedom = len(values) - 1
    return sd * math.sqrt(degrees_freedom / chi_square_ppf(0.10, degrees_freedom))


def holm_adjust(raw_p_values: list[float]) -> list[float]:
    count = len(raw_p_values)
    ordered = sorted(enumerate(raw_p_values), key=lambda pair: pair[1])
    adjusted = [1.0] * count
    running = 0.0
    for rank, (index, value) in enumerate(ordered):
        running = max(running, (count - rank) * value)
        adjusted[index] = min(1.0, running)
    return adjusted


def normal_p_value(estimate: float, standard_error: float, sidedness: str) -> float:
    if standard_error <= 0:
        if estimate == 0:
            return 1.0
        if sidedness == "directional":
            return 0.0 if estimate < 0 else 1.0
        return 0.0
    z_value = estimate / standard_error
    if sidedness == "directional":
        return NormalDist().cdf(z_value)
    return min(1.0, 2.0 * (1.0 - NormalDist().cdf(abs(z_value))))


def continuous_stats(values: list[float], sidedness: str, label: str) -> dict[str, Any]:
    if len(values) < 2:
        return {
            "estimability": "NOT-ESTIMABLE",
            "reasonCode": "FEWER-THAN-TWO-INDEPENDENT-UNITS",
            "nIndependentUnits": len(values),
            "estimandLabel": label,
        }
    point = statistics.fmean(values)
    standard_deviation = statistics.stdev(values)
    standard_error = standard_deviation / math.sqrt(len(values))
    z95 = NormalDist().inv_cdf(0.975)
    z_simultaneous = NormalDist().inv_cdf(1.0 - ALPHA / (2.0 * len(CONTRASTS)))
    ci95 = [point - z95 * standard_error, point + z95 * standard_error]
    ci_simultaneous = [
        point - z_simultaneous * standard_error,
        point + z_simultaneous * standard_error,
    ]
    return {
        "estimability": "ESTIMABLE",
        "estimandLabel": label,
        "nIndependentUnits": len(values),
        "pointLogScale": point,
        "geometricRatio": math.exp(point),
        "sampleSdLogScale": standard_deviation,
        "sigmaUpper90LogScale": sigma_upper_90(values),
        "standardError": standard_error,
        "unadjusted95CiLogScale": ci95,
        "unadjusted95CiRatioScale": [math.exp(ci95[0]), math.exp(ci95[1])],
        "bonferroniCompatible99CiLogScale": ci_simultaneous,
        "bonferroniCompatible99CiRatioScale": [
            math.exp(ci_simultaneous[0]),
            math.exp(ci_simultaneous[1]),
        ],
        "rawNormalApproximationPValue": normal_p_value(point, standard_error, sidedness),
        "sidedness": sidedness,
    }


def scalar_stats(values: list[float], label: str) -> dict[str, Any]:
    if len(values) < 2:
        return {
            "estimability": "NOT-ESTIMABLE",
            "reasonCode": "FEWER-THAN-TWO-INDEPENDENT-UNITS",
            "nIndependentUnits": len(values),
            "estimandLabel": label,
        }
    point = statistics.fmean(values)
    standard_deviation = statistics.stdev(values)
    standard_error = standard_deviation / math.sqrt(len(values))
    z95 = NormalDist().inv_cdf(0.975)
    return {
        "estimability": "ESTIMABLE-SUPPORTIVE",
        "estimandLabel": label,
        "nIndependentUnits": len(values),
        "pointEstimate": point,
        "sampleSd": standard_deviation,
        "sigmaUpper90": sigma_upper_90(values),
        "standardError": standard_error,
        "unadjusted95Ci": [point - z95 * standard_error, point + z95 * standard_error],
    }


def linear_slope(x_values: list[float], y_values: list[float]) -> float:
    require(len(x_values) == len(y_values) and len(x_values) >= 2, "invalid slope inputs")
    x_mean = statistics.fmean(x_values)
    y_mean = statistics.fmean(y_values)
    denominator = sum((value - x_mean) ** 2 for value in x_values)
    require(denominator > 0, "slope x values have zero variance")
    return sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, y_values)) / denominator


def exact_zero_event_upper_95(denominator: int) -> float | None:
    if denominator <= 0:
        return None
    return 1.0 - 0.05 ** (1.0 / denominator)


def raw_metadata_identity(raw_root: Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    count = 0
    total_bytes = 0
    for path in sorted((item for item in raw_root.rglob("*") if item.is_file()), key=lambda p: p.as_posix()):
        stat_result = path.stat()
        relative = path.relative_to(raw_root).as_posix()
        line = f"{relative}\t{stat_result.st_size}\t{stat_result.st_mtime_ns}\n".encode("utf-8")
        digest.update(line)
        count += 1
        total_bytes += stat_result.st_size
    return {"fileCount": count, "rawBytes": total_bytes, "metadataSha256": digest.hexdigest()}


def verify_payload_files(raw_root: Path, manifest_path: Path, expected_count: int, expected_bytes: int) -> dict[str, Any]:
    count = 0
    total_bytes = 0
    seen: set[str] = set()
    for entry in iter_jsonl(manifest_path):
        relative = str(entry.get("relativePath", ""))
        require(relative not in seen, f"duplicate raw payload path: {relative}")
        seen.add(relative)
        path = resolve_relative(raw_root, relative, "raw payload")
        require(path.is_file(), f"missing raw payload file: {relative}")
        expected_size = int(entry.get("rawBytes", -1))
        actual_size = path.stat().st_size
        require(actual_size == expected_size, f"raw payload byte mismatch: {relative}")
        require(sha256_file(path) == str(entry.get("sha256", "")).lower(), f"raw payload SHA mismatch: {relative}")
        count += 1
        total_bytes += actual_size
    require(count == expected_count, f"raw payload count {count} != {expected_count}")
    require(total_bytes == expected_bytes, f"raw payload bytes {total_bytes} != {expected_bytes}")
    return {"verifiedFileCount": count, "verifiedRawBytes": total_bytes, "allPayloadSha256Verified": True}


def verify_execution_authorization(
    project_root: Path,
    contract_path: Path,
    contract: dict[str, Any],
    authorization_path: Path,
) -> tuple[dict[str, Any], Path, str]:
    require(contract.get("contractKind") == CONTRACT_KIND, "wrong Phase B contract kind")
    require(contract.get("contractStatus") == "FROZEN-AWAITING-SEPARATE-EXECUTION-AUTHORIZATION", "contract is not frozen-awaiting-authorization")
    boundary = contract.get("authorizationBoundary", {})
    require(boundary.get("phaseBExecutionAuthorizedByThisContract") is False, "contract must not self-authorize execution")
    require(boundary.get("gate14RAuthorized") is False, "contract unexpectedly authorizes Gate 14R")

    expected_auth_path = resolve_relative(
        project_root,
        str(contract["separateExecutionAuthorization"]["expectedRelativePath"]),
        "expected execution authorization",
    )
    require(authorization_path.resolve() == expected_auth_path, "authorization path does not equal frozen expected path")
    require(authorization_path.is_file(), "separate Phase B execution authorization is absent")
    authorization = load_json(authorization_path)
    require(authorization.get("authorizationKind") == EXECUTION_AUTHORIZATION_KIND, "wrong execution authorization kind")
    require(authorization.get("phaseBFormalStatisticalAnalysisAuthorized") is True, "Phase B execution is not explicitly authorized")
    require(authorization.get("formalOutcomeDataLoadingAuthorized") is True, "formal outcome loading is not explicitly authorized")
    require(authorization.get("gate14RAuthorized") is False, "Gate 14R must remain unauthorized")
    require(authorization.get("rawRootMutationAuthorized") is False, "raw mutation must remain unauthorized")
    require(authorization.get("unityLaunchOrControlAuthorized") is False, "Unity launch/control must remain unauthorized")
    require(isinstance(authorization.get("exactUserExecutionAuthorization"), str) and authorization["exactUserExecutionAuthorization"].strip(), "missing exact user execution authorization")
    contract_hash = sha256_file(contract_path)
    require(str(authorization.get("contractSha256", "")).lower() == contract_hash, "execution authorization does not bind this contract SHA-256")
    require(str(authorization.get("contractRelativePath", "")).replace("\\", "/") == contract_path.relative_to(project_root).as_posix(), "execution authorization contract path mismatch")
    frozen_timestamp = str(authorization.get("frozenOutputTimestampUtc", ""))
    require(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", frozen_timestamp) is not None, "invalid frozenOutputTimestampUtc")
    output_root = resolve_relative(project_root, str(contract["output"]["rootRelativePath"]), "analysis output root")
    require(str(authorization.get("outputRootRelativePath", "")).replace("\\", "/") == output_root.relative_to(project_root).as_posix(), "execution authorization output root mismatch")
    require(not output_root.exists(), "analysis output root already exists; overwrite is forbidden")
    return authorization, output_root, frozen_timestamp


def derive_metrics(result: dict[str, Any], sample: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    if result.get("completed") is not True or sample.get("completed") is not True:
        reasons.append("SAMPLE-NOT-COMPLETE")

    scheduled = finite_number(result.get("scheduledEventCount"))
    dynamic_total = finite_number(result.get("dynamicHandlingTotalMilliseconds"))
    p1_reported = finite_number(result.get("dynamicHandlingMillisecondsPerScheduledEvent"))
    p2 = finite_number(result.get("dynamicHandlingP95Milliseconds"))
    agents = finite_number(result.get("agentCount"))
    total_time = finite_number(result.get("totalPlannerElapsedMilliseconds"))
    p3_reported = finite_number(result.get("totalPlannerElapsedMillisecondsPerAgent"))
    allocated = finite_number(result.get("dynamicManagedAllocatedBytes"))

    continuous: dict[str, dict[str, Any]] = {}
    if scheduled is None or scheduled <= 0 or dynamic_total is None or dynamic_total < 0:
        continuous["P1"] = {"eligible": False, "reasonCode": "INVALID-P1-NUMERATOR-OR-DENOMINATOR"}
    else:
        value = dynamic_total / scheduled
        if p1_reported is None or not approximately_equal(value, p1_reported):
            continuous["P1"] = {"eligible": False, "reasonCode": "P1-DERIVED-FIELD-MISMATCH"}
        else:
            continuous["P1"] = {"eligible": not reasons, "value": value, "reasonCode": reasons[0] if reasons else None}

    if p2 is None or p2 < 0:
        continuous["P2"] = {"eligible": False, "reasonCode": "INVALID-P2-EVENT-P95"}
    else:
        continuous["P2"] = {"eligible": not reasons, "value": p2, "reasonCode": reasons[0] if reasons else None}

    if agents is None or agents <= 0 or total_time is None or total_time < 0:
        continuous["P3-PER-AGENT"] = {"eligible": False, "reasonCode": "INVALID-P3-NUMERATOR-OR-DENOMINATOR"}
    else:
        value = total_time / agents
        if p3_reported is None or not approximately_equal(value, p3_reported):
            continuous["P3-PER-AGENT"] = {"eligible": False, "reasonCode": "P3-DERIVED-FIELD-MISMATCH"}
        else:
            continuous["P3-PER-AGENT"] = {"eligible": not reasons, "value": value, "reasonCode": reasons[0] if reasons else None}

    if scheduled is None or scheduled <= 0 or allocated is None or allocated < 0:
        continuous["P4"] = {"eligible": False, "reasonCode": "INVALID-P4-NUMERATOR-OR-DENOMINATOR"}
    else:
        continuous["P4"] = {"eligible": not reasons, "value": allocated / scheduled, "reasonCode": reasons[0] if reasons else None}

    plan_denominator = result.get("planOperationCount")
    repair_denominator = result.get("repairOperationCount")
    overall_numerator = result.get("budgetExceededOperationCount")
    plan_numerator = result.get("budgetExceededPlanCount")
    p5_valid = all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in (plan_denominator, repair_denominator, overall_numerator, plan_numerator))
    repair_numerator = None
    if p5_valid:
        repair_numerator = overall_numerator - plan_numerator
        p5_valid = (
            plan_numerator <= plan_denominator
            and repair_numerator >= 0
            and repair_numerator <= repair_denominator
            and overall_numerator <= plan_denominator + repair_denominator
        )
    p5 = {
        "eligible": bool(p5_valid and not reasons),
        "reasonCode": None if p5_valid and not reasons else (reasons[0] if reasons else "INVALID-P5-COUNT-IDENTITY"),
    }
    if p5_valid:
        p5["counts"] = {
            "OVERALL": [overall_numerator, plan_denominator + repair_denominator],
            "PLAN": [plan_numerator, plan_denominator],
            "REPAIR": [repair_numerator, repair_denominator],
        }
    return {"continuous": continuous, "P5": p5, "agentCount": int(agents) if agents is not None else None}


def load_and_verify_schedule(path: Path, expected_processes: int, expected_samples: int) -> list[dict[str, Any]]:
    schedule = list(iter_jsonl(path))
    require(len(schedule) == expected_processes, "schedule process count mismatch")
    ordinals = [int(row.get("globalProcessOrdinal", -1)) for row in schedule]
    require(sorted(ordinals) == list(range(1, expected_processes + 1)), "schedule global ordinals are not exact and contiguous")
    require(len({str(row.get("blockId")) for row in schedule}) == expected_processes, "duplicate schedule blockId")
    sample_count = sum(len(row.get("entries", [])) for row in schedule)
    require(sample_count == expected_samples, "schedule sample count mismatch")
    return sorted(schedule, key=lambda row: int(row["globalProcessOrdinal"]))


def load_formal_blocks(
    raw_root: Path,
    schedule: list[dict[str, Any]],
    eligibility_manifest: dict[str, Any],
    evidence_manifest: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    evidence_by_ordinal = {int(item["globalProcessOrdinal"]): item for item in evidence_manifest.get("blocks", [])}
    commit_references = eligibility_manifest.get("blockCommits", [])
    require(len(evidence_by_ordinal) == len(schedule), "raw evidence process count mismatch")
    require(len(commit_references) == len(schedule), "eligibility commit count mismatch")
    commits_by_ordinal: dict[int, dict[str, Any]] = {}
    for reference in commit_references:
        commit_path = resolve_relative(raw_root, str(reference.get("relativePath", "")), "eligibility commit")
        require(commit_path.is_file(), f"missing eligibility commit: {commit_path}")
        require(sha256_file(commit_path) == str(reference.get("sha256", "")).lower(), "eligibility commit SHA mismatch")
        commit = load_json(commit_path)
        ordinal = int(commit.get("globalProcessOrdinal", -1))
        require(ordinal not in commits_by_ordinal, "duplicate eligibility commit ordinal")
        commits_by_ordinal[ordinal] = commit

    blocks: list[dict[str, Any]] = []
    run_ids: set[str] = set()
    for schedule_row in schedule:
        ordinal = int(schedule_row["globalProcessOrdinal"])
        evidence = evidence_by_ordinal.get(ordinal)
        commit = commits_by_ordinal.get(ordinal)
        require(evidence is not None and commit is not None, f"missing evidence or commit for ordinal {ordinal}")
        require(commit.get("formalStatisticalEligibility") is True, f"block {ordinal} is not formally eligible")
        require(commit.get("immutable") is True, f"block {ordinal} is not immutable")
        require(commit.get("resultIndependentAutomaticInclusion") is True, f"block {ordinal} lacks result-independent inclusion")
        for key in ("blockId", "campaignId", "scenarioId"):
            require(str(schedule_row.get(key)) == str(evidence.get(key)) == str(commit.get(key)), f"{key} mismatch at ordinal {ordinal}")
        block_path = resolve_relative(raw_root, str(evidence.get("blockManifestRelativePath", "")), "block manifest")
        require(block_path.is_file(), f"missing block manifest for ordinal {ordinal}")
        block_hash = sha256_file(block_path)
        require(block_hash == str(evidence.get("blockManifestSha256", "")).lower(), f"block manifest SHA mismatch at ordinal {ordinal}")
        require(block_hash == str(commit.get("blockManifestSha256", "")).lower(), f"commit block manifest SHA mismatch at ordinal {ordinal}")
        block = load_json(block_path)
        require(block.get("completed") is True and block.get("formalCampaign") is True, f"incomplete/nonformal block at ordinal {ordinal}")
        require(block.get("hardMemoryRulesPassed") is True, f"hard memory gate failed at ordinal {ordinal}")
        require(int(block.get("completedSampleCount", -1)) == int(schedule_row.get("expectedSampleCount", -2)), f"completed sample count mismatch at ordinal {ordinal}")
        entries = schedule_row.get("entries", [])
        samples = block.get("samples", [])
        require(len(entries) == len(samples), f"sample array mismatch at ordinal {ordinal}")
        samples_by_algorithm = {str(item.get("algorithmId")): item for item in samples}
        require(len(samples_by_algorithm) == len(samples), f"duplicate sample algorithm at ordinal {ordinal}")
        loaded_samples: dict[str, Any] = {}
        for entry in entries:
            algorithm = str(entry.get("algorithmId"))
            sample = samples_by_algorithm.get(algorithm)
            require(sample is not None, f"missing {algorithm} sample at ordinal {ordinal}")
            for key in ("runId", "position", "predecessorAlgorithmId"):
                require(str(sample.get(key)) == str(entry.get(key)), f"sample {key} mismatch at ordinal {ordinal}/{algorithm}")
            run_id = str(sample.get("runId"))
            require(run_id not in run_ids, f"duplicate runId: {run_id}")
            run_ids.add(run_id)
            result_path = resolve_relative(block_path.parent, str(sample.get("workloadResultRelativePath", "")), "workload result")
            require(result_path.is_file(), f"missing workload result at ordinal {ordinal}/{algorithm}")
            require(sha256_file(result_path) == str(sample.get("workloadResultSha256", "")).lower(), f"workload SHA mismatch at ordinal {ordinal}/{algorithm}")
            result = load_json(result_path)
            require(str(result.get("runId")) == run_id, f"workload runId mismatch at ordinal {ordinal}/{algorithm}")
            require(str(result.get("algorithmId")) == algorithm, f"workload algorithm mismatch at ordinal {ordinal}/{algorithm}")
            require(str(result.get("scenarioId")) == str(schedule_row.get("scenarioId")), f"workload scenario mismatch at ordinal {ordinal}/{algorithm}")
            loaded_samples[algorithm] = {
                "entry": entry,
                "sample": sample,
                "result": result,
                "metrics": derive_metrics(result, sample),
            }
        blocks.append({"schedule": schedule_row, "commit": commit, "evidence": evidence, "block": block, "samples": loaded_samples})
    return blocks, {"uniqueRunIdCount": len(run_ids), "verifiedBlockCount": len(blocks)}


def log_ratio_from_block(block: dict[str, Any], metric_id: str, numerator: str, denominator: str) -> tuple[float | None, str | None]:
    samples = block["samples"]
    if numerator not in samples or denominator not in samples:
        return None, "ALGORITHM-NOT-PRESENT-IN-BLOCK"
    numerator_metric = samples[numerator]["metrics"]["continuous"][metric_id]
    denominator_metric = samples[denominator]["metrics"]["continuous"][metric_id]
    if not numerator_metric.get("eligible"):
        return None, f"NUMERATOR-{numerator_metric.get('reasonCode', 'INELIGIBLE')}"
    if not denominator_metric.get("eligible"):
        return None, f"DENOMINATOR-{denominator_metric.get('reasonCode', 'INELIGIBLE')}"
    numerator_value = float(numerator_metric["value"])
    denominator_value = float(denominator_metric["value"])
    if numerator_value <= 0 or denominator_value <= 0:
        return None, "NONPOSITIVE-PAIR-NO-PSEUDOCOUNT"
    return math.log(numerator_value) - math.log(denominator_value), None


def log_ratio_across_blocks(
    numerator_block: dict[str, Any],
    denominator_block: dict[str, Any],
    metric_id: str,
    numerator: str,
    denominator: str,
) -> tuple[float | None, str | None]:
    numerator_metric = numerator_block["samples"].get(numerator, {}).get("metrics", {}).get("continuous", {}).get(metric_id)
    denominator_metric = denominator_block["samples"].get(denominator, {}).get("metrics", {}).get("continuous", {}).get(metric_id)
    if not numerator_metric or not denominator_metric:
        return None, "ALGORITHM-NOT-PRESENT-IN-MATCHED-SUPERBLOCK"
    if not numerator_metric.get("eligible"):
        return None, f"NUMERATOR-{numerator_metric.get('reasonCode', 'INELIGIBLE')}"
    if not denominator_metric.get("eligible"):
        return None, f"DENOMINATOR-{denominator_metric.get('reasonCode', 'INELIGIBLE')}"
    numerator_value = float(numerator_metric["value"])
    denominator_value = float(denominator_metric["value"])
    if numerator_value <= 0 or denominator_value <= 0:
        return None, "NONPOSITIVE-PAIR-NO-PSEUDOCOUNT"
    return math.log(numerator_value) - math.log(denominator_value), None


def shared_continuous_analysis(shared_blocks: list[dict[str, Any]], metric_id: str) -> dict[str, Any]:
    campaigns: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for block in shared_blocks:
        campaigns[str(block["schedule"]["campaignId"])].append(block)
    contrast_outputs: list[dict[str, Any]] = []
    for contrast in CONTRASTS:
        campaign_rows: list[dict[str, Any]] = []
        campaign_estimates: list[float] = []
        for campaign_id in sorted(campaigns):
            values: list[float] = []
            missing = Counter()
            for block in campaigns[campaign_id]:
                value, reason = log_ratio_from_block(block, metric_id, contrast["numerator"], contrast["denominator"])
                if value is None:
                    missing[reason or "UNKNOWN"] += 1
                else:
                    values.append(value)
            row: dict[str, Any] = {
                "campaignId": campaign_id,
                "eligibleBlockCount": len(values),
                "missingBlockCount": sum(missing.values()),
                "missingReasonCounts": dict(sorted(missing.items())),
            }
            if values:
                estimate = statistics.fmean(values)
                row["campaignMeanLogRatio"] = estimate
                row["campaignGeometricRatio"] = math.exp(estimate)
                campaign_estimates.append(estimate)
            else:
                row["estimability"] = "NOT-ESTIMABLE-NO-ELIGIBLE-BLOCKS"
            campaign_rows.append(row)
        matrix = continuous_stats(campaign_estimates, contrast["sidedness"], "EQUAL-WEIGHT-FROZEN-SHARED-CAMPAIGN-MEANS")
        matrix["expectedCampaignCount"] = 32
        matrix["eligibleCampaignCount"] = len(campaign_estimates)
        matrix["missingCampaignCount"] = 32 - len(campaign_estimates)
        matrix["rawEligibleBlockCount"] = sum(row["eligibleBlockCount"] for row in campaign_rows)
        matrix["rawMissingBlockCount"] = sum(row["missingBlockCount"] for row in campaign_rows)
        contrast_outputs.append({"contrast": contrast, "campaignRows": campaign_rows, "matrixEstimate": matrix})
    return {"metricId": metric_id, "contrasts": contrast_outputs}


def apply_p1_multiplicity(p1_analysis: dict[str, Any]) -> None:
    rows = p1_analysis["contrasts"]
    require(len(rows) == len(CONTRASTS), "P1 contrast family is not complete")
    raw_p_values: list[float] = []
    for row in rows:
        matrix = row["matrixEstimate"]
        require(matrix.get("estimability") == "ESTIMABLE", f"P1 {row['contrast']['id']} is not estimable")
        raw_p_values.append(float(matrix["rawNormalApproximationPValue"]))
    adjusted = holm_adjust(raw_p_values)
    for row, adjusted_value in zip(rows, adjusted):
        matrix = row["matrixEstimate"]
        matrix["holmAdjustedPValue"] = adjusted_value
        contrast_id = row["contrast"]["id"]
        if contrast_id in {"C1", "C2", "C3", "C4"}:
            favorable = float(matrix["pointLogScale"]) < 0
            simultaneous_upper_below_one = float(matrix["bonferroniCompatible99CiRatioScale"][1]) < 1.0
            passes_holm = adjusted_value < ALPHA
            matrix["directionalSuperiorityCriteria"] = {
                "correctnessAndStructuralGatesPassed": True,
                "favorableDirection": favorable,
                "holmAdjustedPValueBelow0_05": passes_holm,
                "simultaneousUpperRatioBoundBelow1": simultaneous_upper_below_one,
                "verdict": "SUPERIORITY-CRITERIA-SATISFIED" if favorable and passes_holm and simultaneous_upper_below_one else "SUPERIORITY-NOT-ESTABLISHED",
            }
        else:
            matrix["conclusionConstraint"] = "TWO-SIDED-REPORT-ONLY-NO-POSTHOC-WINNER-LABEL"


def aggregate_p5(blocks: list[dict[str, Any]], grouping_key: str) -> dict[str, Any]:
    group_totals: dict[str, dict[str, dict[str, list[int]]]] = defaultdict(
        lambda: defaultdict(lambda: {"OVERALL": [0, 0], "PLAN": [0, 0], "REPAIR": [0, 0]})
    )
    ineligible = Counter()
    for block in blocks:
        group_value = str(block["schedule"].get(grouping_key, ""))
        for algorithm, loaded in block["samples"].items():
            p5 = loaded["metrics"]["P5"]
            if not p5.get("eligible"):
                ineligible[f"{algorithm}|{p5.get('reasonCode', 'UNKNOWN')}"] += 1
                continue
            for stratum, counts in p5["counts"].items():
                group_totals[group_value][algorithm][stratum][0] += int(counts[0])
                group_totals[group_value][algorithm][stratum][1] += int(counts[1])

    def render_counts(counts: list[int]) -> dict[str, Any]:
        numerator, denominator = counts
        return {
            "numerator": numerator,
            "denominator": denominator,
            "rate": numerator / denominator if denominator > 0 else None,
            "exactOneSided95UpperIfZeroEvents": exact_zero_event_upper_95(denominator) if numerator == 0 else None,
        }

    rendered_groups: list[dict[str, Any]] = []
    matrix_totals: dict[str, dict[str, list[int]]] = defaultdict(lambda: {"OVERALL": [0, 0], "PLAN": [0, 0], "REPAIR": [0, 0]})
    for group_value in sorted(group_totals):
        algorithms: dict[str, Any] = {}
        for algorithm in sorted(group_totals[group_value]):
            algorithms[algorithm] = {}
            for stratum in ("OVERALL", "PLAN", "REPAIR"):
                counts = group_totals[group_value][algorithm][stratum]
                algorithms[algorithm][stratum] = render_counts(counts)
                matrix_totals[algorithm][stratum][0] += counts[0]
                matrix_totals[algorithm][stratum][1] += counts[1]
        rendered_groups.append({grouping_key: group_value, "algorithms": algorithms})
    return {
        "metricId": "P5",
        "role": "SUPPORTIVE-COUNT-RATE-NO-CONTINUOUS-LOG-RATIO-INFERENCE",
        "groups": rendered_groups,
        "matrixTotals": {
            algorithm: {stratum: render_counts(counts) for stratum, counts in strata.items()}
            for algorithm, strata in sorted(matrix_totals.items())
        },
        "ineligibleSampleReasonCounts": dict(sorted(ineligible.items())),
        "pseudocountUsed": False,
        "allZeroSuperiorityConclusionAllowed": False,
    }


def p3_scaling_analysis(shared_blocks: list[dict[str, Any]]) -> dict[str, Any]:
    by_level_and_block: dict[tuple[int, int], dict[str, dict[str, Any]]] = {}
    structural_reasons = Counter()
    for block in shared_blocks:
        scenario_id = str(block["schedule"]["scenarioId"])
        match = P3_SCALE_PATTERN.fullmatch(scenario_id)
        if not match:
            continue
        frozen_level = int(match.group(1))
        ordinal = int(block["schedule"]["campaignBlockOrdinal"])
        for algorithm, loaded in block["samples"].items():
            actual_level = loaded["metrics"].get("agentCount")
            metric = loaded["metrics"]["continuous"]["P3-PER-AGENT"]
            if actual_level != frozen_level:
                structural_reasons["AGENT-COUNT-DOES-NOT-MATCH-FROZEN-SCENARIO-ID"] += 1
                continue
            if not metric.get("eligible") or float(metric.get("value", 0.0)) <= 0:
                structural_reasons[metric.get("reasonCode") or "NONPOSITIVE-P3-NO-PSEUDOCOUNT"] += 1
                continue
            by_level_and_block.setdefault((frozen_level, ordinal), {})[algorithm] = loaded

    x_values = [math.log(level) for level in P3_SCALE_LEVELS]
    slopes_by_algorithm: dict[str, list[float]] = {algorithm: [] for algorithm in EXPECTED_ALGORITHMS}
    slopes_by_block: dict[int, dict[str, float]] = defaultdict(dict)
    missing_replicates: list[dict[str, Any]] = []
    for ordinal in range(1, 49):
        for algorithm in EXPECTED_ALGORITHMS:
            y_values: list[float] = []
            complete = True
            for level in P3_SCALE_LEVELS:
                loaded = by_level_and_block.get((level, ordinal), {}).get(algorithm)
                if loaded is None:
                    complete = False
                    break
                y_values.append(math.log(float(loaded["metrics"]["continuous"]["P3-PER-AGENT"]["value"])))
            if not complete:
                missing_replicates.append({"campaignBlockOrdinal": ordinal, "algorithmId": algorithm, "reasonCode": "INCOMPLETE-FIVE-LEVEL-FROZEN-SCALE"})
                continue
            slope = linear_slope(x_values, y_values)
            slopes_by_algorithm[algorithm].append(slope)
            slopes_by_block[ordinal][algorithm] = slope

    algorithm_rows = [
        {"algorithmId": algorithm, "slopeSummary": scalar_stats(slopes_by_algorithm[algorithm], "LOG-PER-AGENT-TIME-ON-LOG-AGENT-COUNT")}
        for algorithm in EXPECTED_ALGORITHMS
    ]
    contrast_rows: list[dict[str, Any]] = []
    for contrast in CONTRASTS:
        values = [
            rows[contrast["numerator"]] - rows[contrast["denominator"]]
            for _, rows in sorted(slopes_by_block.items())
            if contrast["numerator"] in rows and contrast["denominator"] in rows
        ]
        contrast_rows.append({
            "contrast": contrast,
            "slopeDifferenceSummary": scalar_stats(values, "NUMERATOR-SLOPE-MINUS-DENOMINATOR-SLOPE"),
        })
    return {
        "estimand": "P3-AGENT-COUNT-SCALING-SLOPE-DISTINCT-FROM-P3-PER-AGENT",
        "role": "SUPPORTIVE",
        "frozenAgentCountLevels": list(P3_SCALE_LEVELS),
        "xScale": "NATURAL-LOG-AGENT-COUNT",
        "yScale": "NATURAL-LOG-TOTAL-PLANNER-ELAPSED-MILLISECONDS-PER-AGENT",
        "replicateUnit": "MATCHED-CAMPAIGN-BLOCK-ORDINAL-ACROSS-FIVE-LEVELS",
        "algorithmSlopes": algorithm_rows,
        "contrastSlopeDifferences": contrast_rows,
        "missingReplicates": missing_replicates,
        "structuralReasonCounts": dict(sorted(structural_reasons.items())),
        "crossScenarioFamilySubstitutionUsed": False,
    }


def build_matched_superblocks(heterogeneous_blocks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for block in heterogeneous_blocks:
        matched = block["schedule"].get("matchedSuperblock")
        require(isinstance(matched, dict), "heterogeneous block lacks matchedSuperblock")
        grouped[str(matched.get("matchedSuperblockId"))].append(block)
    superblocks: list[dict[str, Any]] = []
    for identifier in sorted(grouped):
        pair = grouped[identifier]
        require(len(pair) == 2, f"matched superblock {identifier} does not have two processes")
        by_cohort = {str(item["schedule"]["comparisonCohortId"]): item for item in pair}
        require(set(by_cohort) == {PER_AGENT_COHORT, GROUPED_FIELD_COHORT}, f"matched superblock {identifier} cohort mismatch")
        per_agent = by_cohort[PER_AGENT_COHORT]
        grouped_field = by_cohort[GROUPED_FIELD_COHORT]
        left = per_agent["schedule"]["matchedSuperblock"]
        right = grouped_field["schedule"]["matchedSuperblock"]
        for shared_key in (
            "cohortOrder",
            "deterministicInputIdentity",
            "matchedSuperblockId",
            "matchedSuperblockOrdinal",
            "pairGlobalProcessOrdinals",
            "scenarioOrdinal",
        ):
            require(left.get(shared_key) == right.get(shared_key), f"matched superblock {shared_key} differs for {identifier}")
        require(str(left.get("cohortRole")) == "A-PER-AGENT", f"per-agent cohort role mismatch for {identifier}")
        require(str(right.get("cohortRole")) == "B-GROUPED-FIELD", f"grouped-field cohort role mismatch for {identifier}")
        expected_positions = {"AB": (1, 2), "BA": (2, 1)}
        order = str(left.get("cohortOrder"))
        require(order in expected_positions, f"invalid cohort order for {identifier}")
        per_agent_position, grouped_field_position = expected_positions[order]
        require(int(left.get("cohortProcessPosition", -1)) == per_agent_position, f"per-agent process position mismatch for {identifier}")
        require(int(right.get("cohortProcessPosition", -1)) == grouped_field_position, f"grouped-field process position mismatch for {identifier}")
        ordinals = sorted([int(per_agent["schedule"]["globalProcessOrdinal"]), int(grouped_field["schedule"]["globalProcessOrdinal"])])
        require(ordinals[1] == ordinals[0] + 1, f"matched superblock {identifier} is not adjacent")
        require(ordinals == sorted(int(value) for value in left.get("pairGlobalProcessOrdinals", [])), f"matched pair ordinals mismatch for {identifier}")
        require(str(per_agent["schedule"]["scenarioId"]) == str(grouped_field["schedule"]["scenarioId"]), f"scenario mismatch for {identifier}")
        require(left.get("cohortOrder") in {"AB", "BA"}, f"invalid cohort order for {identifier}")
        superblocks.append({
            "matchedSuperblockId": identifier,
            "scenarioId": str(per_agent["schedule"]["scenarioId"]),
            "order": str(left["cohortOrder"]),
            "perAgent": per_agent,
            "groupedField": grouped_field,
        })
    return superblocks


def heterogeneous_continuous_analysis(superblocks: list[dict[str, Any]], metric_id: str) -> dict[str, Any]:
    specifications = list(CONTRASTS) + [
        {"id": "DIAGNOSTIC-DSTAR-L-OVER-ASTAR-R", "numerator": "D*L", "denominator": "A*-R", "sidedness": "two-sided"}
    ]
    rows: list[dict[str, Any]] = []
    for contrast in specifications:
        by_scenario: dict[str, list[float]] = defaultdict(list)
        by_order: dict[str, list[float]] = defaultdict(list)
        missing = Counter()
        for superblock in superblocks:
            if contrast["id"] in {"C1", "C2", "C3", "C4"}:
                value, reason = log_ratio_across_blocks(
                    superblock["groupedField"],
                    superblock["perAgent"],
                    metric_id,
                    contrast["numerator"],
                    contrast["denominator"],
                )
            elif contrast["id"] == "C5":
                value, reason = log_ratio_from_block(
                    superblock["groupedField"], metric_id, contrast["numerator"], contrast["denominator"]
                )
            else:
                value, reason = log_ratio_from_block(
                    superblock["perAgent"], metric_id, contrast["numerator"], contrast["denominator"]
                )
            if value is None:
                missing[reason or "UNKNOWN"] += 1
            else:
                by_scenario[superblock["scenarioId"]].append(value)
                by_order[superblock["order"]].append(value)
        scenario_rows = []
        scenario_estimates = []
        for scenario_id in sorted(by_scenario):
            estimate = statistics.fmean(by_scenario[scenario_id])
            scenario_estimates.append(estimate)
            scenario_rows.append({
                "scenarioId": scenario_id,
                "eligibleMatchedSuperblockCount": len(by_scenario[scenario_id]),
                "scenarioMeanLogRatio": estimate,
                "scenarioGeometricRatio": math.exp(estimate),
            })
        rows.append({
            "contrast": contrast,
            "matrixSecondaryEstimate": continuous_stats(scenario_estimates, contrast["sidedness"], "EQUAL-WEIGHT-FROZEN-HETEROGENEOUS-SCENARIO-MEANS"),
            "scenarioRows": scenario_rows,
            "orderStrata": {
                order: continuous_stats(values, contrast["sidedness"], f"MATCHED-SUPERBLOCKS-ORDER-{order}")
                for order, values in sorted(by_order.items())
            },
            "eligibleMatchedSuperblockCount": sum(len(values) for values in by_scenario.values()),
            "missingMatchedSuperblockCount": sum(missing.values()),
            "missingReasonCounts": dict(sorted(missing.items())),
            "role": "SECONDARY-OR-DIAGNOSTIC-NOT-IN-P1-HOLM-FAMILY",
        })
    return {"metricId": metric_id, "contrasts": rows}


def build_coverage(blocks: list[dict[str, Any]], superblocks: list[dict[str, Any]]) -> dict[str, Any]:
    process_counts = Counter(str(block["schedule"]["comparisonCohortId"]) for block in blocks)
    sample_counts = Counter()
    metric_eligibility: dict[str, Counter[str]] = {metric: Counter() for metric in CONTINUOUS_METRICS}
    p5_counts = Counter()
    for block in blocks:
        for algorithm, loaded in block["samples"].items():
            sample_counts[algorithm] += 1
            for metric in CONTINUOUS_METRICS:
                item = loaded["metrics"]["continuous"][metric]
                metric_eligibility[metric]["eligible" if item.get("eligible") else f"ineligible:{item.get('reasonCode', 'UNKNOWN')}"] += 1
            p5 = loaded["metrics"]["P5"]
            p5_counts["eligible" if p5.get("eligible") else f"ineligible:{p5.get('reasonCode', 'UNKNOWN')}"] += 1
    order_counts = Counter(superblock["order"] for superblock in superblocks)
    return {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-PHASEB-SCHEDULE-COVERAGE-AND-MISSINGNESS",
        "completedEligibleTotalBlockProcesses": [len(blocks), len(blocks), 3552],
        "completedEligibleTotalSamples": [sum(sample_counts.values()), sum(sample_counts.values()), 10176],
        "processCountsByCohort": dict(sorted(process_counts.items())),
        "sampleCountsByAlgorithm": dict(sorted(sample_counts.items())),
        "continuousMetricEligibilityCounts": {metric: dict(sorted(counts.items())) for metric, counts in metric_eligibility.items()},
        "p5EligibilityCounts": dict(sorted(p5_counts.items())),
        "matchedSuperblockCount": len(superblocks),
        "matchedSuperblockOrderCounts": dict(sorted(order_counts.items())),
        "missingnessPolicy": "RETAIN-ALL-REASONS-NO-PSEUDOCOUNT-NO-SELECTIVE-EXCLUSION",
    }


def run_self_test() -> dict[str, Any]:
    adjusted = holm_adjust([0.001, 0.02, 0.03, 0.2, 0.8])
    require(all(approximately_equal(a, b) for a, b in zip(adjusted, [0.005, 0.08, 0.09, 0.4, 0.8])), "Holm self-test failed")
    require(approximately_equal(linear_slope([0.0, 1.0, 2.0], [1.0, 3.0, 5.0]), 2.0), "slope self-test failed")
    require(approximately_equal(exact_zero_event_upper_95(100) or 0.0, 1.0 - 0.05 ** 0.01), "zero-event bound self-test failed")
    stats = continuous_stats([-0.2, -0.1, -0.3], "directional", "SYNTHETIC")
    require(stats.get("estimability") == "ESTIMABLE" and float(stats["geometricRatio"]) < 1.0, "continuous stats self-test failed")
    return {
        "analyzerId": ANALYZER_ID,
        "selfTest": "PASS",
        "formalRawOpened": False,
        "formalAnalysisExecuted": False,
        "gate14RExecuted": False,
    }


def run_analysis(project_root: Path, contract_path: Path, authorization_path: Path) -> dict[str, Any]:
    project_root = project_root.resolve()
    contract_path = contract_path.resolve()
    authorization_path = authorization_path.resolve()
    require(contract_path.is_file(), "frozen Phase B contract is missing")
    contract = load_json(contract_path)
    authorization, output_root, frozen_timestamp = verify_execution_authorization(
        project_root, contract_path, contract, authorization_path
    )

    for label, binding in contract["implementationBindings"].items():
        verified_bound_file(project_root, binding, f"implementation binding {label}")
    input_paths = {
        label: verified_bound_file(project_root, binding, f"frozen input {label}")
        for label, binding in contract["frozenInputBindings"].items()
    }
    raw_root = resolve_relative(project_root, str(contract["rawInput"]["rootRelativePath"]), "frozen raw root")
    require(raw_root.is_dir(), "frozen raw root is missing")
    require(output_root != raw_root and not output_root.is_relative_to(raw_root), "analysis output cannot be inside raw root")

    freeze_receipt = load_json(input_paths["rawDataFreezeReceipt"])
    final_audit = load_json(input_paths["formalRawReadyAudit"])
    require(freeze_receipt.get("allCompletedBlocksFormallyEligible") is True, "freeze receipt eligibility is not true")
    require(freeze_receipt.get("allPayloadFilesReadOnly") is True, "freeze receipt payload read-only flag is not true")
    require(freeze_receipt.get("analysisAuthorized") is False and freeze_receipt.get("analysisPending") is True, "freeze receipt Phase B boundary changed")
    require(freeze_receipt.get("gate14RAuthorized") is False, "freeze receipt Gate 14R boundary changed")
    require(final_audit.get("passed") is True, "formal raw-ready audit did not pass")
    require(final_audit.get("phaseBAnalysisExecuted") is False, "formal raw-ready audit says Phase B already executed")
    require(final_audit.get("gate14RExecuted") is False, "formal raw-ready audit says Gate 14R executed")

    before_metadata = raw_metadata_identity(raw_root)
    payload_verification = verify_payload_files(
        raw_root,
        input_paths["rawPayloadFileManifest"],
        int(contract["rawInput"]["expectedOutputFileCount"]),
        int(contract["rawInput"]["expectedRawBytes"]),
    )
    schedule = load_and_verify_schedule(
        input_paths["formalSchedule"],
        int(contract["design"]["expectedProcessCount"]),
        int(contract["design"]["expectedSampleCount"]),
    )
    eligibility_manifest = load_json(input_paths["blockFormalEligibilityManifest"])
    evidence_manifest = load_json(input_paths["rawBlockEvidenceManifest"])
    blocks, block_audit = load_formal_blocks(raw_root, schedule, eligibility_manifest, evidence_manifest)
    shared_blocks = [block for block in blocks if block["schedule"]["comparisonCohortId"] == SHARED_COHORT]
    heterogeneous_blocks = [block for block in blocks if block["schedule"]["comparisonCohortId"] in {PER_AGENT_COHORT, GROUPED_FIELD_COHORT}]
    require(len(shared_blocks) == 1536 and len(heterogeneous_blocks) == 2016, "cohort process count mismatch")
    superblocks = build_matched_superblocks(heterogeneous_blocks)
    require(len(superblocks) == 1008, "matched superblock count mismatch")

    input_audit = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-PHASEB-ANALYSIS-INPUT-AUDIT",
        "generatedAtUtc": frozen_timestamp,
        "analyzerId": ANALYZER_ID,
        "contractSha256": sha256_file(contract_path),
        "executionAuthorizationSha256": sha256_file(authorization_path),
        "rawRootRelativePath": raw_root.relative_to(project_root).as_posix(),
        "rawRootCanonicalTreeSha256": contract["rawInput"]["canonicalRawTreeSha256"],
        "payloadVerification": payload_verification,
        "blockVerification": block_audit,
        "processCount": len(blocks),
        "sampleCount": sum(len(block["samples"]) for block in blocks),
        "matchedSuperblockCount": len(superblocks),
        "phaseBExecutionAuthorizationPresentAndBound": True,
        "rawRootMutationAuthorized": False,
        "gate14RAuthorized": False,
        "M1ThroughM5LoadedOrDerived": False,
    }
    coverage = build_coverage(blocks, superblocks)
    coverage["generatedAtUtc"] = frozen_timestamp

    p1 = shared_continuous_analysis(shared_blocks, "P1")
    apply_p1_multiplicity(p1)
    shared_primary = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-SHARED-CONFIRMATORY-P1",
        "generatedAtUtc": frozen_timestamp,
        "metric": p1,
        "familyWiseAlpha": ALPHA,
        "multiplicityMethod": "HOLM",
        "simultaneousCiMethod": "BONFERRONI-COMPATIBLE-99-PERCENT-FOR-FIVE-CONTRASTS",
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    supportive_continuous = [shared_continuous_analysis(shared_blocks, metric) for metric in ("P2", "P3-PER-AGENT", "P4")]
    shared_supportive = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-SHARED-SUPPORTIVE-P2-P5",
        "generatedAtUtc": frozen_timestamp,
        "continuousMetrics": supportive_continuous,
        "p3ScalingSlope": p3_scaling_analysis(shared_blocks),
        "p5CountsAndRates": aggregate_p5(shared_blocks, "campaignId"),
        "confirmatoryPromotionAllowed": False,
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    heterogeneous_secondary = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-HETEROGENEOUS-SECONDARY",
        "generatedAtUtc": frozen_timestamp,
        "matchedSuperblockCount": len(superblocks),
        "continuousMetrics": [heterogeneous_continuous_analysis(superblocks, metric) for metric in CONTINUOUS_METRICS],
        "p5CountsAndRates": aggregate_p5(heterogeneous_blocks, "scenarioId"),
        "confirmatoryPromotionAllowed": False,
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    after_metadata = raw_metadata_identity(raw_root)
    require(before_metadata == after_metadata, "frozen raw-root metadata changed during analysis; fail closed")
    input_audit["rawMetadataIdentityBefore"] = before_metadata
    input_audit["rawMetadataIdentityAfter"] = after_metadata
    input_audit["rawMetadataUnchangedDuringAnalysis"] = True

    output_parent = output_root.parent
    require(output_parent == project_root or output_parent.is_relative_to(project_root), "output parent escapes project")
    output_parent.mkdir(parents=True, exist_ok=True)
    staging = output_parent / f".{output_root.name}.staging-{uuid.uuid4().hex}"
    require(not staging.exists(), "staging path collision")
    staging.mkdir(parents=False, exist_ok=False)
    try:
        payloads = {
            "analysis-input-audit.json": input_audit,
            "schedule-coverage-and-missingness.json": coverage,
            "shared-primary-p1-analysis.json": shared_primary,
            "shared-supportive-p2-p5-analysis.json": shared_supportive,
            "heterogeneous-secondary-analysis.json": heterogeneous_secondary,
        }
        for filename in OUTPUT_FILENAMES:
            write_json(staging / filename, payloads[filename])
        manifest_entries = [
            {"relativePath": filename, "rawBytes": (staging / filename).stat().st_size, "sha256": sha256_file(staging / filename)}
            for filename in OUTPUT_FILENAMES
        ]
        output_manifest = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-PR2-ATTEMPT4-PHASEB-ANALYSIS-MANIFEST",
            "generatedAtUtc": frozen_timestamp,
            "contractSha256": sha256_file(contract_path),
            "executionAuthorizationSha256": sha256_file(authorization_path),
            "artifacts": manifest_entries,
            "gate14RAuthorized": False,
        }
        write_json(staging / "phase-b-analysis-manifest.json", output_manifest)
        receipt = {
            "schemaVersion": 1,
            "receiptKind": "GATE13R-PR2-ATTEMPT4-PHASEB-ANALYSIS-COMPLETION",
            "generatedAtUtc": frozen_timestamp,
            "status": "PHASEB-FORMAL-ANALYSIS-COMPLETE-GATE14R-NOT-AUTHORIZED",
            "contractSha256": sha256_file(contract_path),
            "executionAuthorizationSha256": sha256_file(authorization_path),
            "analysisManifestSha256": sha256_file(staging / "phase-b-analysis-manifest.json"),
            "rawRootUnchanged": True,
            "phaseBFormalStatisticalAnalysisExecuted": True,
            "gate14RAuthorized": False,
            "gate14RExecuted": False,
            "M1ThroughM5LoadedOrDerived": False,
            "nextGate": "SEPARATE-REVIEW-AND-SEPARATE-GATE14R-AUTHORIZATION-IF-EVER-GRANTED",
        }
        write_json(staging / "phase-b-execution-receipt.json", receipt)
        require(not output_root.exists(), "analysis output appeared during staging; refusing overwrite")
        os.replace(staging, output_root)
    except BaseException:
        if staging.exists() and staging.parent == output_parent and staging.name.startswith(f".{output_root.name}.staging-"):
            shutil.rmtree(staging)
        raise
    return {
        "status": "PHASEB-FORMAL-ANALYSIS-COMPLETE-GATE14R-NOT-AUTHORIZED",
        "outputRoot": str(output_root),
        "phaseBFormalStatisticalAnalysisExecuted": True,
        "gate14RAuthorized": False,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gate 13R-PR2 attempt-4 frozen Phase B analyzer")
    parser.add_argument("--self-test", action="store_true", help="run synthetic-only tests; opens no formal input")
    parser.add_argument("--project-root", type=Path)
    parser.add_argument("--contract", type=Path)
    parser.add_argument("--authorization", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if arguments.self_test:
            print(json.dumps(run_self_test(), ensure_ascii=False, sort_keys=True))
            return 0
        require(arguments.project_root is not None, "--project-root is required")
        require(arguments.contract is not None, "--contract is required")
        require(arguments.authorization is not None, "--authorization is required")
        result = run_analysis(arguments.project_root, arguments.contract, arguments.authorization)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except AnalysisError as error:
        print(json.dumps({
            "status": "REFUSED-FAIL-CLOSED",
            "reason": str(error),
            "phaseBFormalStatisticalAnalysisExecuted": False,
            "gate14RAuthorized": False,
        }, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
