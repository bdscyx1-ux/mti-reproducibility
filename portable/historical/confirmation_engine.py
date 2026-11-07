#!/usr/bin/env python3
"""Frozen read-only Phase B analysis for Gate 13R P1-C5 independent study.

The program cannot run without a separate, post-acquisition Phase B authorization.
It never writes inside the formal raw root.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import statistics
import tempfile
from pathlib import Path
from typing import Any, Iterable


CONTRACT_REL = "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json"
RAW_ROOT_REL = "Research/FormalRuns/Gate13R_P1C5_Independent/v1"
SCHEDULE_REL = "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl"
ANALYSIS_ROOT_REL = "Research/Analysis/Gate13R_P1C5_Independent/v1"
ENDPOINT_FIELD = "dynamicHandlingMillisecondsPerScheduledEvent"
EXPECTED_PROCESSES = 1600


class AnalysisError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AnalysisError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    require(isinstance(value, dict), f"expected JSON object: {path}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for line_number, line in enumerate(stream, start=1):
            if line.strip():
                value = json.loads(line)
                require(isinstance(value, dict), f"non-object JSONL record at {path}:{line_number}")
                yield value


def beta_continued_fraction(a: float, b: float, x: float) -> float:
    maximum_iterations = 400
    epsilon = 3.0e-14
    tiny = 1.0e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
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
    raise AnalysisError("incomplete-beta continued fraction did not converge")


def regularized_incomplete_beta(a: float, b: float, x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x))
    if x < (a + 1.0) / (a + b + 2.0):
        return front * beta_continued_fraction(a, b, x) / a
    return 1.0 - front * beta_continued_fraction(b, a, 1.0 - x) / b


def student_t_cdf(value: float, degrees_freedom: float) -> float:
    if value == 0.0:
        return 0.5
    x = degrees_freedom / (degrees_freedom + value * value)
    tail = 0.5 * regularized_incomplete_beta(degrees_freedom / 2.0, 0.5, x)
    return 1.0 - tail if value > 0 else tail


def student_t_ppf(probability: float, degrees_freedom: float) -> float:
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


def atomic_create(path: Path, data: bytes) -> None:
    if path.exists():
        raise FileExistsError(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".g13r-p1c5-analysis-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def verify_authorization(project: Path, authorization_path: Path, contract_sha: str, raw_commit_sha: str) -> dict[str, Any]:
    authorization = load_json(authorization_path)
    require(authorization.get("authorizationKind") == "GATE13R-P1C5-INDEPENDENT-PHASEB-FORMAL-ANALYSIS-AUTHORIZATION", "Phase B authorization identity mismatch")
    require(authorization.get("authorized") is True, "Phase B authorization is not affirmative")
    require(authorization.get("executionContractSha256") == contract_sha, "Phase B authorization contract binding mismatch")
    require(authorization.get("rawDataCompleteSha256") == raw_commit_sha, "Phase B authorization raw-commit binding mismatch")
    require(authorization.get("analyzerSha256") == sha256_file(ORIGINAL_ANALYZER), "Phase B authorization analyzer binding mismatch")
    require(authorization.get("gate14RAuthorized") is False, "Gate 14R must remain unauthorized")
    require(authorization.get("m1ThroughM5Authorized") is False, "M1-M5 must remain unauthorized")
    return authorization


def verify_payload_manifest(raw_root: Path, raw_commit: dict[str, Any]) -> None:
    manifest_path = (raw_root / str(raw_commit["payloadManifestRelativePath"])).resolve()
    require(manifest_path.is_file(), "raw payload manifest is missing")
    require(sha256_file(manifest_path) == raw_commit["payloadManifestSha256"], "raw payload manifest hash mismatch")
    expected: set[str] = set()
    total_bytes = 0
    for item in iter_jsonl(manifest_path):
        relative = str(item["relativePath"])
        candidate = (raw_root / relative).resolve()
        require(candidate.is_file(), f"raw payload file is missing: {relative}")
        require(candidate.stat().st_size == int(item["bytes"]), f"raw payload byte count mismatch: {relative}")
        require(sha256_file(candidate) == item["sha256"], f"raw payload hash mismatch: {relative}")
        expected.add(relative)
        total_bytes += int(item["bytes"])
    observed = {path.relative_to(raw_root).as_posix() for path in (raw_root / "campaigns").rglob("*") if path.is_file()}
    require(observed == expected, "raw campaign payload set differs from the immutable manifest")
    require(len(expected) == int(raw_commit["payloadFileCount"]), "raw payload file count mismatch")
    require(total_bytes == int(raw_commit["payloadBytes"]), "raw payload total bytes mismatch")


def sample_p1(manifest: dict[str, Any], algorithm_id: str) -> float:
    candidates = [item for item in manifest["samples"] if item.get("algorithmId") == algorithm_id]
    require(len(candidates) == 1, f"expected exactly one {algorithm_id} sample")
    value = float(candidates[0][ENDPOINT_FIELD])
    require(math.isfinite(value) and value > 0.0, f"invalid positive P1 value for {algorithm_id}")
    return value


def run_analysis(project: Path, contract_sha: str, authorization_path: Path) -> dict[str, Any]:
    contract_path = project / CONTRACT_REL
    require(contract_path.is_file() and sha256_file(contract_path) == contract_sha, "execution contract binding mismatch")
    contract = load_json(contract_path)
    require(contract.get("contractKind") == "GATE13R-P1C5-INDEPENDENT-FROZEN-EXECUTION-CONTRACT", "contract identity mismatch")
    analyzer_binding = contract["bindings"]["phaseBAnalyzer"]
    require(analyzer_binding["sha256"] == sha256_file(ORIGINAL_ANALYZER), "analyzer differs from frozen contract")
    schedule_path = project / SCHEDULE_REL
    require(sha256_file(schedule_path) == contract["bindings"]["schedule"]["sha256"], "schedule differs from frozen contract")
    schedule = list(iter_jsonl(schedule_path))
    require(len(schedule) == EXPECTED_PROCESSES, "schedule process count mismatch")
    raw_root = project / RAW_ROOT_REL
    raw_commit_path = raw_root / "raw-data-complete.json"
    require(raw_commit_path.is_file(), "raw-data-complete commit is missing")
    raw_commit_sha = sha256_file(raw_commit_path)
    raw_commit = load_json(raw_commit_path)
    require(raw_commit.get("status") == "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE", "raw root is not in the analysis-pending terminal state")
    require(int(raw_commit.get("completedUnityProcesses", 0)) == EXPECTED_PROCESSES, "raw process count mismatch")
    require(int(raw_commit.get("completedAlgorithmSamples", 0)) == EXPECTED_PROCESSES * 2, "raw sample count mismatch")
    require(raw_commit.get("scheduleSha256") == sha256_file(schedule_path), "raw commit schedule binding mismatch")
    verify_authorization(project, authorization_path, contract_sha, raw_commit_sha)
    verify_selected_payload(raw_root, raw_commit)

    strata: dict[tuple[str, str], list[float]] = {}
    campaign_values: dict[str, list[float]] = {}
    order_values: dict[str, list[float]] = {"AB": [], "BA": []}
    seen_process: set[tuple[int, str]] = set()
    for record in schedule:
        ordinal = int(record["globalProcessOrdinal"])
        output = raw_root / str(record["outputRelativePath"])
        manifest_path = output / "block-manifest.json"
        commit_path = raw_root / "_control/block-eligibility-commits" / f"p{ordinal:04d}.json"
        require(manifest_path.is_file() and commit_path.is_file(), f"missing block/commit at ordinal {ordinal}")
        manifest = load_json(manifest_path)
        commit = load_json(commit_path)
        require(commit.get("formalStatisticalEligibility") is True, f"block is not eligible at ordinal {ordinal}")
        require(commit.get("blockManifestSha256") == sha256_file(manifest_path), f"block commit hash mismatch at ordinal {ordinal}")
        require(manifest.get("blockId") == record["blockId"] and manifest.get("campaignId") == record["campaignId"], f"block identity mismatch at ordinal {ordinal}")
        require(manifest.get("completed") is True and manifest.get("hardMemoryRulesPassed") is True, f"block did not pass at ordinal {ordinal}")
        identity = (int(manifest["processId"]), str(manifest["processStartTimeUtc"]))
        require(identity not in seen_process, f"Unity process identity reused at ordinal {ordinal}")
        seen_process.add(identity)
        log_ratio = math.log(sample_p1(manifest, "IDFF") / sample_p1(manifest, "C-FF"))
        campaign = str(record["campaignId"])
        order = str(record["orderLabel"])
        strata.setdefault((campaign, order), []).append(log_ratio)
        campaign_values.setdefault(campaign, []).append(log_ratio)
        order_values[order].append(log_ratio)

    require(len(strata) == 64, "expected exactly 64 campaign-order strata")
    require({len(values) for values in strata.values()} == {25}, "each campaign-order stratum must contain exactly 25 blocks")
    stratum_weight = 1.0 / 64.0
    means = [statistics.fmean(values) for values in strata.values()]
    theta = statistics.fmean(means)
    variance_terms = [stratum_weight * stratum_weight * statistics.variance(values) / len(values) for values in strata.values()]
    variance = sum(variance_terms)
    require(variance > 0.0 and math.isfinite(variance), "estimated variance is not positive finite")
    standard_error = math.sqrt(variance)
    denominator = sum(term * term / (len(values) - 1) for term, values in zip(variance_terms, strata.values()))
    degrees_freedom = variance * variance / denominator
    critical = student_t_ppf(0.975, degrees_freedom)
    lower_log = theta - critical * standard_error
    upper_log = theta + critical * standard_error
    statistic_value = theta / standard_error
    p_value = 2.0 * min(student_t_cdf(statistic_value, degrees_freedom), 1.0 - student_t_cdf(statistic_value, degrees_freedom))
    ratio = math.exp(theta)
    lower_ratio, upper_ratio = math.exp(lower_log), math.exp(upper_log)
    if upper_ratio < 1.0:
        decision = "IDFF-LOWER-P1-CONFIRMED"
    elif lower_ratio > 1.0:
        decision = "CFF-LOWER-P1-CONFIRMED"
    else:
        decision = "UNRESOLVED"

    result = {
        "schemaVersion": 1,
        "analysisKind": "gate13r-p1c5-independent-confirmatory-phase-b-v1",
        "studyId": "Gate13R-P1C5-Independent-v1",
        "endpoint": "P1",
        "endpointField": ENDPOINT_FIELD,
        "contrast": "IDFF/C-FF",
        "lowerIsBetter": True,
        "alphaTwoSided": 0.05,
        "familySize": 1,
        "multiplicityAdjustment": "none-single-prespecified-confirmatory-contrast",
        "independentUnit": "fresh Unity process paired block",
        "campaignCount": 32,
        "campaignOrderStratumCount": 64,
        "blocksPerStratum": 25,
        "pairedBlockCount": EXPECTED_PROCESSES,
        "algorithmSampleCount": EXPECTED_PROCESSES * 2,
        "estimateLogRatio": theta,
        "standardErrorLogRatio": standard_error,
        "degreesFreedomWelchSatterthwaite": degrees_freedom,
        "testStatistic": statistic_value,
        "pValueTwoSided": p_value,
        "geometricMeanRatio": ratio,
        "confidenceLevel": 0.95,
        "confidenceIntervalRatio": [lower_ratio, upper_ratio],
        "decision": decision,
        "orderDiagnostics": {
            order: {"pairedBlockCount": len(values), "geometricMeanRatio": math.exp(statistics.fmean(values))}
            for order, values in order_values.items()
        },
        "campaignDiagnostics": [
            {"campaignId": campaign, "pairedBlockCount": len(values), "geometricMeanRatio": math.exp(statistics.fmean(values))}
            for campaign, values in sorted(campaign_values.items())
        ],
        "executionContractSha256": contract_sha,
        "rawDataCompleteSha256": raw_commit_sha,
        "rawRootReadOnly": True,
        "attempt4RawDataMerged": False,
        "gate14RExecuted": False,
        "m1ThroughM5Executed": False,
    }
    output_root = project / ANALYSIS_ROOT_REL
    output_root.mkdir(parents=True, exist_ok=False)
    result_path = output_root / "confirmatory-p1-c5-result.json"
    report_path = output_root / "confirmatory-p1-c5-report.md"
    atomic_create(result_path, json_bytes(result))
    report = (
        "# Gate 13R P1–C5 独立专项确认性结果\n\n"
        f"- 判定：`{decision}`\n"
        f"- IDFF/C-FF P1 几何均值比：`{ratio:.12g}`\n"
        f"- 双侧 95% CI：`[{lower_ratio:.12g}, {upper_ratio:.12g}]`\n"
        f"- 双侧 p 值：`{p_value:.12g}`\n"
        f"- 独立成对 blocks：`{EXPECTED_PROCESSES}`；固定 campaigns：`32`；每个 campaign-order 层：`25`。\n\n"
        "该结论仅适用于冻结的 32-campaign 有限矩阵；未执行 Gate 14R 或 M1–M5。\n"
    ).encode("utf-8")
    atomic_create(report_path, report)
    return {"passed": True, "decision": decision, "resultPath": str(result_path), "reportPath": str(report_path)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--execution-contract-sha256", required=True)
    parser.add_argument("--authorization", required=True)
    args = parser.parse_args()
    result = run_analysis(Path(args.project_root).resolve(), args.execution_contract_sha256, Path(args.authorization).resolve())
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()

# Offline adapter: original telemetry remains archived; verify every extracted outcome
# against the original immutable manifest, without claiming a full telemetry replay.
def verify_selected_payload(raw_root, raw_commit):
    manifest = raw_root / raw_commit['payloadManifestRelativePath']
    require(sha256_file(manifest)==raw_commit['payloadManifestSha256'], 'payload manifest hash mismatch')
    rows=list(iter_jsonl(manifest))
    require(len(rows)==raw_commit['payloadFileCount'], 'manifest file count mismatch')
    require(sum(int(r['bytes']) for r in rows)==raw_commit['payloadBytes'], 'manifest byte count mismatch')
    selected={r['relativePath']:r for r in rows if r['relativePath'].endswith(('block-manifest.json','workload-result.json'))}
    require(len([r for r in selected if r.endswith('block-manifest.json')])==1600,'missing block manifests')
    for rel,r in selected.items():
        p=raw_root/rel
        require(p.stat().st_size==r['bytes'] and sha256_file(p)==r['sha256'],'selected payload differs: '+rel)
