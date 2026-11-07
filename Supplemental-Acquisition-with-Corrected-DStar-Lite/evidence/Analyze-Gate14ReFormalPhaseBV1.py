#!/usr/bin/env python3
"""Gate 14Re Phase B formal analysis and winner adjudication.

This analyzer is deliberately read-only with respect to the immutable Phase A
root.  It verifies the frozen SHA-256 tree before parsing formal block outputs,
implements the pre-outcome Phase B contract, and creates exactly one analysis
root without overwriting an existing artifact.

The program has three entry paths:

* ``--self-test`` runs pure-synthetic known-answer checks only;
* ``--formal`` performs the authorized formal Phase B analysis once;
* ``--verify-existing`` recomputes the result payloads in memory and compares
  them with an existing committed analysis root without writing to that root.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import shutil
import stat
import statistics
import sys
import traceback
import uuid
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import numpy as np


SCRIPT_SCHEMA = "gate14re-formal-phase-b-analyzer-v1"
PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parents[1]

REL = {
    "contract": "Research/Gate14Re/Analysis/Gate14Re_Formal_PhaseB_Analysis_Contract.v1.json",
    "authorization": "Research/Gate14Re/Analysis/Gate14Re_Formal_PhaseB_Authorization.v1.json",
    "raw_root": "Research/FormalRuns/Gate14Re/PhaseA/attempt-001",
    "raw_complete": "Research/FormalRuns/Gate14Re/PhaseA/attempt-001/raw-data-complete.json",
    "raw_manifest": "Research/FormalRuns/Gate14Re/PhaseA/attempt-001/_control/raw-commit-manifest.v1.json",
    "raw_tree": "Research/FormalRuns/Gate14Re/PhaseA/attempt-001/_control/raw-commit-canonical-tree.v1.jsonl",
    "analysis_root": "Research/Analysis/Gate14Re/PhaseB/attempt-001",
    "verify_root": "Research/Verification/Gate14Re/formal-phase-b-analysis-implementation-attempt-001",
}

EXPECTED = {
    "contract_sha256": "208a9a4393d5a610c065a64f3dbb52747c0597d391a452b426d09e7d314272f2",
    "raw_complete_sha256": "0fa68436e37333c5ccbc3360a3fd49460b9a338add16f95dc4f307de33e696fa",
    "raw_manifest_sha256": "9758f4c42fec3afd941e2b453552d77d405482ea7c5944ed1bf1619aee7e48c8",
    "raw_tree_sha256": "0c1e0bc2c8b286aa866901fdb26fbafc87bb5490f4578250eb2f4e2401df72dc",
    "structural_audit_receipt_sha256": "8b85741cab21eca28588c5b21d4a556c5fd1203a80aba58ec540e5a421b96d89",
    "formal_plan_sha256": "9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d",
    "formal_executable_sha256": "88b1b04971f8b712ddd0f18bca4f7296d287fdd6cdadef57c155d37b9ef0928c",
    "assembly_sha256": "2f763a06d43a5777d6ce47cdba998d5482e82557ad35ee72f9e07dcd193b2961",
    "build_receipt_sha256": "d110c97ca2f2f3d5a38490497ebfcf714d976c75b2397a68d46787e29c51ec9a",
    "authorization_id": "gate14re-phase-a-attempt-001-b87e10a8-9d42-4512-8f4d-4b371eb7f75b",
    "tree_records": 4612,
    "tree_raw_bytes": 288232353,
    "block_outputs": 1536,
    "movement_blocks": 768,
    "m4_blocks": 768,
    "algorithm_lane_samples": 6144,
}

ALGORITHMS = ("A", "B", "C", "D")
PRODUCTION = {"A": "A*-R", "B": "D*L", "C": "C-FF", "D": "IDFF"}
CONDITIONS = tuple(f"C{i:02d}" for i in range(1, 9))
ANCHORS = ("C01", "C07")
UNIT_COUNTS = (1, 8, 32, 128, 512)
PAIR_FAMILY = (("A", "B"), ("A", "C"), ("A", "D"), ("B", "C"), ("B", "D"), ("C", "D"))


class AnalysisError(RuntimeError):
    """Fail-closed analysis error with a non-outcome-sensitive code."""

    def __init__(self, code: str, detail: str | None = None):
        self.code = code
        self.detail = detail or code
        super().__init__(f"{code}: {self.detail}")


def require(condition: bool, code: str, detail: str | None = None) -> None:
    if not condition:
        raise AnalysisError(code, detail)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical_json_bytes(value: Any, *, pretty: bool = True) -> bytes:
    if pretty:
        return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def atomic_create(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())


def write_json(path: Path, value: Any) -> None:
    atomic_create(path, canonical_json_bytes(value, pretty=True))


def is_read_only(path: Path) -> bool:
    attrs = getattr(path.stat(), "st_file_attributes", 0)
    flag = getattr(stat, "FILE_ATTRIBUTE_READONLY", 1)
    return bool(attrs & flag)


def set_read_only(path: Path) -> None:
    os.chmod(path, stat.S_IREAD)


def verify_exact_file(path: Path, expected_hash: str, code: str, *, require_read_only: bool = True) -> None:
    require(path.is_file(), f"{code}_MISSING", str(path))
    require(sha256_file(path) == expected_hash, f"{code}_HASH_MISMATCH", str(path))
    if require_read_only:
        require(is_read_only(path), f"{code}_NOT_READONLY", str(path))


def finite_float(value: Any, code: str) -> float:
    require(isinstance(value, (int, float)) and not isinstance(value, bool), code)
    out = float(value)
    require(math.isfinite(out), code)
    return out


def safe_exp(value: float) -> float:
    if value > 709:
        return float("inf")
    if value < -745:
        return 0.0
    return math.exp(value)


def json_number(value: float | int | None) -> float | int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    return float(value) if math.isfinite(float(value)) else None


# ---------------------------------------------------------------------------
# Student-t distribution: deterministic standard-library implementation.
# ---------------------------------------------------------------------------


def _beta_continued_fraction(a: float, b: float, x: float) -> float:
    max_iter = 500
    eps = 3.0e-14
    fpmin = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < fpmin:
        d = fpmin
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= eps:
            return h
    raise AnalysisError("BETA_CONTINUED_FRACTION_NONCONVERGENCE")


def regularized_beta(a: float, b: float, x: float) -> float:
    require(a > 0 and b > 0 and 0 <= x <= 1, "INVALID_BETA_ARGUMENT")
    if x == 0:
        return 0.0
    if x == 1:
        return 1.0
    log_bt = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
    bt = math.exp(log_bt)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _beta_continued_fraction(a, b, x) / a
    return 1.0 - bt * _beta_continued_fraction(b, a, 1.0 - x) / b


def t_cdf(t_value: float, degrees_freedom: float) -> float:
    require(degrees_freedom > 0 and math.isfinite(degrees_freedom), "INVALID_T_DF")
    if t_value == 0:
        return 0.5
    x = degrees_freedom / (degrees_freedom + t_value * t_value)
    tail_twice = regularized_beta(degrees_freedom / 2.0, 0.5, x)
    return 1.0 - 0.5 * tail_twice if t_value > 0 else 0.5 * tail_twice


def t_ppf(probability: float, degrees_freedom: float) -> float:
    require(0 < probability < 1, "INVALID_T_PROBABILITY")
    if probability == 0.5:
        return 0.0
    if probability < 0.5:
        return -t_ppf(1.0 - probability, degrees_freedom)
    lo, hi = 0.0, 1.0
    while t_cdf(hi, degrees_freedom) < probability:
        hi *= 2.0
        require(hi < 1.0e6, "T_QUANTILE_BRACKET_FAILURE")
    for _ in range(160):
        mid = (lo + hi) / 2.0
        if t_cdf(mid, degrees_freedom) < probability:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def two_sided_t_pvalue(t_value: float, degrees_freedom: float) -> float:
    return min(1.0, max(0.0, 2.0 * (1.0 - t_cdf(abs(t_value), degrees_freedom))))


def holm_adjust(pvalues: Sequence[float]) -> list[float]:
    m = len(pvalues)
    order = sorted(range(m), key=lambda idx: (pvalues[idx], idx))
    adjusted = [0.0] * m
    running = 0.0
    for rank, idx in enumerate(order):
        candidate = min(1.0, (m - rank) * float(pvalues[idx]))
        running = max(running, candidate)
        adjusted[idx] = running
    return adjusted


def wilson_interval(successes: int, total: int, confidence: float = 0.95) -> tuple[float, float]:
    require(0 <= successes <= total and total > 0, "INVALID_WILSON_COUNTS")
    # The 0.975 normal quantile is frozen to avoid a second numerical dependency.
    z = 1.959963984540054
    p = successes / total
    denom = 1.0 + z * z / total
    center = (p + z * z / (2.0 * total)) / denom
    radius = z * math.sqrt(p * (1.0 - p) / total + z * z / (4.0 * total * total)) / denom
    return max(0.0, center - radius), min(1.0, center + radius)


def sample_variance(values: Sequence[float]) -> float:
    require(len(values) >= 2, "VARIANCE_REQUIRES_TWO_VALUES")
    return statistics.variance(values)


def stratified_mean_statistics(
    strata: Mapping[str, Sequence[float]],
    *,
    ordinary_alpha: float = 0.05,
    simultaneous_family_size: int = 6,
) -> dict[str, Any]:
    require(strata, "NO_STRATA")
    names = sorted(strata)
    require(all(len(strata[name]) >= 2 for name in names), "INSUFFICIENT_STRATUM_N")
    condition_means = {name: statistics.fmean(strata[name]) for name in names}
    estimate = statistics.fmean(condition_means.values())
    c = float(len(names))
    variance_parts = [(sample_variance(strata[name]) / len(strata[name])) / (c * c) for name in names]
    total_variance = sum(variance_parts)
    if total_variance <= 0:
        standard_error = 0.0
        degrees_freedom = float("inf")
        statistic_value = 0.0 if estimate == 0 else math.copysign(float("inf"), estimate)
        pvalue = 1.0 if estimate == 0 else 0.0
        ordinary = (estimate, estimate)
        simultaneous = (estimate, estimate)
    else:
        standard_error = math.sqrt(total_variance)
        denom = sum((part * part) / (len(strata[name]) - 1) for part, name in zip(variance_parts, names))
        degrees_freedom = (total_variance * total_variance) / denom if denom > 0 else float("inf")
        statistic_value = estimate / standard_error
        pvalue = two_sided_t_pvalue(statistic_value, degrees_freedom)
        ordinary_critical = t_ppf(1.0 - ordinary_alpha / 2.0, degrees_freedom)
        bonf_alpha = ordinary_alpha / simultaneous_family_size
        simultaneous_critical = t_ppf(1.0 - bonf_alpha / 2.0, degrees_freedom)
        ordinary = (estimate - ordinary_critical * standard_error, estimate + ordinary_critical * standard_error)
        simultaneous = (
            estimate - simultaneous_critical * standard_error,
            estimate + simultaneous_critical * standard_error,
        )
    return {
        "estimateLog": estimate,
        "standardErrorLog": standard_error,
        "degreesOfFreedom": None if not math.isfinite(degrees_freedom) else degrees_freedom,
        "tStatistic": None if not math.isfinite(statistic_value) else statistic_value,
        "unadjustedTwoSidedP": pvalue,
        "ordinary95LogCI": list(ordinary),
        "ordinary95RatioCI": [safe_exp(ordinary[0]), safe_exp(ordinary[1])],
        "simultaneous95LogCI": list(simultaneous),
        "simultaneous95RatioCI": [safe_exp(simultaneous[0]), safe_exp(simultaneous[1])],
        "ratioEstimate": safe_exp(estimate),
        "strata": {name: {"n": len(strata[name]), "meanLogEffect": condition_means[name]} for name in names},
        "totalIndependentBlocks": sum(len(strata[name]) for name in names),
    }


def one_sample_log_summary(values: Sequence[float], confidence: float = 0.95) -> dict[str, Any]:
    require(len(values) >= 2 and all(math.isfinite(v) and v > 0 for v in values), "INVALID_POSITIVE_SUMMARY_VALUES")
    logs = [math.log(v) for v in values]
    mean_log = statistics.fmean(logs)
    se = math.sqrt(sample_variance(logs) / len(logs))
    critical = t_ppf(0.5 + confidence / 2.0, len(logs) - 1)
    lo, hi = mean_log - critical * se, mean_log + critical * se
    return {
        "nBlocks": len(values),
        "geometricMean": safe_exp(mean_log),
        "ordinary95CI": [safe_exp(lo), safe_exp(hi)],
        "arithmeticMedian": statistics.median(values),
        "minimum": min(values),
        "maximum": max(values),
    }


def pair_key(first: str, second: str) -> str:
    return f"{first}/{second}"


def orient_pair(result: Mapping[str, Any], first: str, second: str) -> dict[str, Any]:
    stored_first, stored_second = result["firstAlgorithm"], result["secondAlgorithm"]
    if stored_first == first and stored_second == second:
        return dict(result)
    require(stored_first == second and stored_second == first, "PAIR_ORIENTATION_MISMATCH")
    ordinary = result["ordinary95RatioCI"]
    simultaneous = result["simultaneous95RatioCI"]
    return {
        **dict(result),
        "firstAlgorithm": first,
        "secondAlgorithm": second,
        "pair": pair_key(first, second),
        "estimateLog": -float(result["estimateLog"]),
        "ratioEstimate": 1.0 / float(result["ratioEstimate"]),
        "ordinary95RatioCI": [1.0 / float(ordinary[1]), 1.0 / float(ordinary[0])],
        "simultaneous95RatioCI": [1.0 / float(simultaneous[1]), 1.0 / float(simultaneous[0])],
    }


# ---------------------------------------------------------------------------
# Input verification and extraction.
# ---------------------------------------------------------------------------


def read_tree(tree_path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with tree_path.open("r", encoding="utf-8") as stream:
        for line_no, line in enumerate(stream, 1):
            line = line.strip()
            require(bool(line), "EMPTY_CANONICAL_TREE_LINE", str(line_no))
            obj = json.loads(line)
            require(set(obj) == {"bytes", "relativePath", "sha256"}, "CANONICAL_TREE_RECORD_KEYS", str(line_no))
            records.append(obj)
    return records


def verify_raw_root(project_root: Path) -> tuple[Path, list[dict[str, Any]], dict[str, Any]]:
    contract_path = project_root / REL["contract"]
    authorization_path = project_root / REL["authorization"]
    raw_root = project_root / REL["raw_root"]
    raw_complete_path = project_root / REL["raw_complete"]
    raw_manifest_path = project_root / REL["raw_manifest"]
    raw_tree_path = project_root / REL["raw_tree"]
    audit_receipt = project_root / "Research/Verification/Gate14Re/formal-phase-a-raw-commit-attempt-001/structural-audit-receipt.v1.json"

    verify_exact_file(contract_path, EXPECTED["contract_sha256"], "ANALYSIS_CONTRACT")
    require(authorization_path.is_file(), "PHASE_B_AUTHORIZATION_MISSING")
    require(is_read_only(authorization_path), "PHASE_B_AUTHORIZATION_NOT_READONLY")
    authorization = load_json(authorization_path)
    require(authorization.get("schema") == "gate14re-formal-phase-b-authorization-v1", "PHASE_B_AUTHORIZATION_SCHEMA")
    require(authorization.get("formalResultAnalysisAuthorized") is True, "FORMAL_ANALYSIS_NOT_AUTHORIZED")
    require(authorization.get("winnerAdjudicationAuthorized") is True, "WINNER_ADJUDICATION_NOT_AUTHORIZED")
    require(authorization.get("phaseBFormalAnalysisAuthorized") is True, "PHASE_B_NOT_AUTHORIZED")
    require(authorization.get("gate15Authorized") is False, "GATE15_BOUNDARY_VIOLATION")
    require(authorization.get("analysisContractSha256") == EXPECTED["contract_sha256"], "AUTH_CONTRACT_BINDING_MISMATCH")
    require(authorization.get("rawCompleteSha256") == EXPECTED["raw_complete_sha256"], "AUTH_RAW_BINDING_MISMATCH")
    require(authorization.get("analyzerSha256") == sha256_file(Path(__file__).resolve()), "AUTH_ANALYZER_BINDING_MISMATCH")
    require(authorization.get("formalRawRoot") == REL["raw_root"], "AUTH_FORMAL_ROOT_BINDING_MISMATCH")
    require(authorization.get("analysisRoot") == REL["analysis_root"], "AUTH_ANALYSIS_ROOT_BINDING_MISMATCH")
    for prefix in ("syntheticValidationReceipt", "implementationManifest", "readinessCheckpoint"):
        relative = authorization.get(prefix + "Path")
        expected_hash = authorization.get(prefix + "Sha256")
        require(isinstance(relative, str) and relative and ".." not in Path(relative).parts, f"AUTH_{prefix.upper()}_PATH")
        require(isinstance(expected_hash, str) and len(expected_hash) == 64, f"AUTH_{prefix.upper()}_HASH")
        verify_exact_file(project_root / relative, expected_hash, f"AUTH_{prefix.upper()}")
    authorization = dict(authorization)
    authorization["_sha256"] = sha256_file(authorization_path)

    verify_exact_file(raw_complete_path, EXPECTED["raw_complete_sha256"], "RAW_COMPLETE")
    verify_exact_file(raw_manifest_path, EXPECTED["raw_manifest_sha256"], "RAW_MANIFEST")
    verify_exact_file(raw_tree_path, EXPECTED["raw_tree_sha256"], "RAW_TREE")
    verify_exact_file(audit_receipt, EXPECTED["structural_audit_receipt_sha256"], "STRUCTURAL_AUDIT_RECEIPT")

    raw_complete = load_json(raw_complete_path)
    require(raw_complete.get("status") == "FORMAL-PHASE-A-RAW-COMPLETE", "RAW_STATUS_NOT_COMPLETE")
    require(raw_complete.get("acceptedBlocks") == EXPECTED["block_outputs"], "RAW_ACCEPTED_BLOCK_COUNT")
    require(raw_complete.get("algorithmLaneSamples") == EXPECTED["algorithm_lane_samples"], "RAW_SAMPLE_COUNT")
    require(raw_complete.get("formalAnalysisStarted") is False, "RAW_ALREADY_MARKED_ANALYZED")
    require(raw_complete.get("phaseBStarted") is False, "RAW_ALREADY_MARKED_PHASE_B")
    require(raw_complete.get("winnerAdjudicationStarted") is False, "RAW_ALREADY_MARKED_WINNER_ADJUDICATION")

    records = read_tree(raw_tree_path)
    require(len(records) == EXPECTED["tree_records"], "RAW_TREE_RECORD_COUNT")
    require(sum(int(record["bytes"]) for record in records) == EXPECTED["tree_raw_bytes"], "RAW_TREE_BYTE_COUNT")
    relative_paths = [record["relativePath"] for record in records]
    require(relative_paths == sorted(relative_paths), "RAW_TREE_NOT_SORTED")
    require(len(set(relative_paths)) == len(relative_paths), "RAW_TREE_DUPLICATE_PATH")

    for record in records:
        relative = str(record["relativePath"])
        path = raw_root / Path(relative.replace("/", os.sep))
        require(path.is_file(), "RAW_TREE_FILE_MISSING", relative)
        require(path.stat().st_size == int(record["bytes"]), "RAW_TREE_FILE_SIZE_MISMATCH", relative)
        require(is_read_only(path), "RAW_TREE_FILE_NOT_READONLY", relative)
        require(sha256_file(path) == record["sha256"], "RAW_TREE_FILE_HASH_MISMATCH", relative)

    post_commit_files = [raw_complete_path, raw_manifest_path, raw_tree_path]
    root_files = [path for path in raw_root.rglob("*") if path.is_file()]
    require(len(root_files) == EXPECTED["tree_records"] + len(post_commit_files), "RAW_POST_COMMIT_FILE_COUNT")
    require(all(is_read_only(path) for path in root_files), "RAW_ROOT_CONTAINS_WRITABLE_FILE")
    return raw_root, records, authorization


def validate_block_identity(block: Mapping[str, Any], relative: str) -> None:
    require(block.get("schema") == "gate14re-formal-block-output-v2", "BLOCK_SCHEMA", relative)
    require(block.get("studyId") == "Gate14Re" and block.get("status") == "COMPLETE", "BLOCK_STATUS", relative)
    require(block.get("planSha256") == EXPECTED["formal_plan_sha256"], "BLOCK_PLAN_BINDING", relative)
    require(block.get("executableSha256") == EXPECTED["formal_executable_sha256"], "BLOCK_EXE_BINDING", relative)
    require(block.get("assemblyCSharpSha256") == EXPECTED["assembly_sha256"], "BLOCK_ASSEMBLY_BINDING", relative)
    require(block.get("buildReceiptSha256") == EXPECTED["build_receipt_sha256"], "BLOCK_BUILD_BINDING", relative)
    require(block.get("authorizationId") == EXPECTED["authorization_id"], "BLOCK_AUTHORIZATION_BINDING", relative)
    require(block.get("completeFourAlgorithmBlock") is True, "BLOCK_NOT_COMPLETE", relative)
    require(block.get("formalObservationProduced") is True and block.get("formalPhaseA") is True, "BLOCK_NOT_FORMAL", relative)
    require(block.get("conditionId") in CONDITIONS, "BLOCK_CONDITION", relative)
    require(block.get("unitCount") in UNIT_COUNTS, "BLOCK_UNIT_COUNT", relative)
    require(block.get("lane") in ("movement", "m4"), "BLOCK_LANE", relative)
    require(block.get("module") in ("A", "Q"), "BLOCK_MODULE", relative)
    require(isinstance(block.get("blockIndex"), int) and 1 <= block["blockIndex"] <= 48, "BLOCK_INDEX", relative)
    require(isinstance(block.get("blockSequence"), int) and 1 <= block["blockSequence"] <= 1536, "BLOCK_SEQUENCE", relative)
    samples = block["movement"] if block["lane"] == "movement" else block["m4"]
    other = block["m4"] if block["lane"] == "movement" else block["movement"]
    require(isinstance(samples, list) and len(samples) == 4 and isinstance(other, list) and len(other) == 0, "BLOCK_LANE_CARDINALITY", relative)
    labels = [sample.get("algorithmLabel") for sample in samples]
    require(set(labels) == set(ALGORITHMS) and len(set(labels)) == 4, "BLOCK_ALGORITHM_LABELS", relative)
    require(all(sample.get("productionAlgorithmId") == PRODUCTION[sample.get("algorithmLabel")] for sample in samples), "BLOCK_PRODUCTION_IDS", relative)
    require(sorted(sample.get("orderPosition") for sample in samples) == [1, 2, 3, 4], "BLOCK_ORDER_POSITIONS", relative)


def load_formal_blocks(raw_root: Path, records: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    block_records = [record for record in records if str(record["relativePath"]).endswith("/block-output.json")]
    require(len(block_records) == EXPECTED["block_outputs"], "BLOCK_OUTPUT_COUNT")
    blocks: list[dict[str, Any]] = []
    seen_sequences: set[int] = set()
    seen_ids: set[str] = set()
    for record in block_records:
        relative = str(record["relativePath"])
        block = load_json(raw_root / Path(relative.replace("/", os.sep)))
        validate_block_identity(block, relative)
        sequence = int(block["blockSequence"])
        block_id = str(block["blockId"])
        require(sequence not in seen_sequences, "DUPLICATE_BLOCK_SEQUENCE", str(sequence))
        require(block_id not in seen_ids, "DUPLICATE_BLOCK_ID", block_id)
        seen_sequences.add(sequence)
        seen_ids.add(block_id)
        block = dict(block)
        block["_relativePath"] = relative
        block["_sha256"] = record["sha256"]
        blocks.append(block)
    require(seen_sequences == set(range(1, 1537)), "BLOCK_SEQUENCE_COVERAGE")
    require(sum(block["lane"] == "movement" for block in blocks) == EXPECTED["movement_blocks"], "MOVEMENT_BLOCK_COUNT")
    require(sum(block["lane"] == "m4" for block in blocks) == EXPECTED["m4_blocks"], "M4_BLOCK_COUNT")
    return sorted(blocks, key=lambda block: int(block["blockSequence"]))


def sample_map(block: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    samples = block["movement"] if block["lane"] == "movement" else block["m4"]
    return {str(sample["algorithmLabel"]): sample for sample in samples}


# ---------------------------------------------------------------------------
# Formal estimands, eligibility, and winner adjudication.
# ---------------------------------------------------------------------------


def main_blocks(blocks: Sequence[Mapping[str, Any]], lane: str) -> list[Mapping[str, Any]]:
    selected = [
        block
        for block in blocks
        if block["module"] == "A" and block["lane"] == lane and int(block["unitCount"]) == 128
    ]
    require(len(selected) == 8 * 48, f"MAIN_{lane.upper()}_BLOCK_COUNT")
    for condition in CONDITIONS:
        condition_blocks = [block for block in selected if block["conditionId"] == condition]
        require(len(condition_blocks) == 48, f"MAIN_{lane.upper()}_{condition}_COUNT")
        require({int(block["blockIndex"]) for block in condition_blocks} == set(range(1, 49)), f"MAIN_{lane.upper()}_{condition}_INDEX_COVERAGE")
    return selected


def evaluate_eligibility(blocks: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    movement = main_blocks(blocks, "movement")
    m4 = main_blocks(blocks, "m4")
    m3: dict[str, Any] = {}
    m4_result: dict[str, Any] = {}
    m5: dict[str, Any] = {}

    for algorithm in ALGORITHMS:
        condition_results: dict[str, Any] = {}
        for condition in CONDITIONS:
            rows = [sample_map(block)[algorithm] for block in movement if block["conditionId"] == condition]
            require(len(rows) == 48, "M3_CELL_COUNT")
            completed = sum(sample.get("allUnitsArrived") is True for sample in rows)
            lo, hi = wilson_interval(completed, 48)
            condition_results[condition] = {
                "completedBlocks": completed,
                "plannedBlocks": 48,
                "completionProportion": completed / 48.0,
                "wilson95CI": [lo, hi],
                "passes45Of48": completed >= 45,
                "terminalReasonTotals": {
                    "activeAtCap": sum(int(sample.get("activeAtCapCount", 0)) for sample in rows),
                    "noPath": sum(int(sample.get("noPathCount", 0)) for sample in rows),
                    "budgetExceeded": sum(int(sample.get("budgetExceededCount", 0)) for sample in rows),
                    "invalidPlan": sum(int(sample.get("invalidPlanCount", 0)) for sample in rows),
                    "internalFailure": sum(int(sample.get("internalFailureCount", 0)) for sample in rows),
                },
            }
        m3[algorithm] = {
            "productionAlgorithmId": PRODUCTION[algorithm],
            "conditions": condition_results,
            "passesAllEightConditions": all(row["passes45Of48"] for row in condition_results.values()),
        }

        m4_conditions: dict[str, Any] = {}
        for condition in CONDITIONS:
            rows = [sample_map(block)[algorithm] for block in m4 if block["conditionId"] == condition]
            require(len(rows) == 48, "M4_CELL_COUNT")
            p95 = [finite_float(sample["nearestRankP95FrameTimeSeconds"], "INVALID_M4_P95") for sample in rows]
            require(all(value > 0 for value in p95), "NONPOSITIVE_M4_P95")
            median_p95 = statistics.median(p95)
            count_above_50 = sum(value > 0.050 for value in p95)
            m4_conditions[condition] = {
                "blockP95MedianSeconds": median_p95,
                "blockP95MedianMilliseconds": median_p95 * 1000.0,
                "blocksAbove50Milliseconds": count_above_50,
                "plannedBlocks": 48,
                "medianGateMaximumMilliseconds": 33.333,
                "tailCountGateMaximum": 3,
                "passes": median_p95 <= 0.033333 and count_above_50 <= 3,
            }
        m4_result[algorithm] = {
            "productionAlgorithmId": PRODUCTION[algorithm],
            "conditions": m4_conditions,
            "passesAllEightConditions": all(row["passes"] for row in m4_conditions.values()),
        }

        movement_rows = [sample_map(block)[algorithm] for block in movement]
        critical_count = sum(int(sample["m5CriticalViolationCount"]) for sample in movement_rows)
        affected_blocks = sum(int(sample["m5CriticalViolationCount"]) > 0 for sample in movement_rows)
        codes: dict[str, int] = defaultdict(int)
        for sample in movement_rows:
            for code in sample.get("m5CriticalViolationCodes", []):
                codes[str(code)] += 1
        m5[algorithm] = {
            "productionAlgorithmId": PRODUCTION[algorithm],
            "criticalViolationCount": critical_count,
            "affectedBlocks": affected_blocks,
            "criticalViolationCodes": dict(sorted(codes.items())),
            "passesZeroCriticalViolations": critical_count == 0,
        }

    eligible: list[str] = []
    summary: dict[str, Any] = {}
    for algorithm in ALGORITHMS:
        passed = (
            m3[algorithm]["passesAllEightConditions"]
            and m4_result[algorithm]["passesAllEightConditions"]
            and m5[algorithm]["passesZeroCriticalViolations"]
        )
        summary[algorithm] = {
            "productionAlgorithmId": PRODUCTION[algorithm],
            "M3Pass": m3[algorithm]["passesAllEightConditions"],
            "M4Pass": m4_result[algorithm]["passesAllEightConditions"],
            "M5Pass": m5[algorithm]["passesZeroCriticalViolations"],
            "eligible": passed,
        }
        if passed:
            eligible.append(algorithm)
    return {
        "schema": "gate14re-phase-b-eligibility-v1",
        "independentUnit": "complete block",
        "M3": m3,
        "M4": m4_result,
        "M5": m5,
        "summary": summary,
        "eligibleAlgorithms": eligible,
        "eligibleProductionAlgorithms": [PRODUCTION[label] for label in eligible],
    }


def build_pairwise(
    blocks: Sequence[Mapping[str, Any]],
    *,
    metric: str,
) -> dict[str, Any]:
    movement = main_blocks(blocks, "movement")
    pair_results: list[dict[str, Any]] = []
    included_by_condition: dict[str, int] = {}

    if metric == "M2":
        for condition in CONDITIONS:
            count = 0
            for block in movement:
                if block["conditionId"] != condition:
                    continue
                samples = sample_map(block)
                root_sufficient = block.get("m2CommonMaskSufficient") is True
                sample_flags = [samples[label].get("m2CommonMaskSufficient") is True for label in ALGORITHMS]
                require(len(set(sample_flags)) == 1 and sample_flags[0] == root_sufficient, "M2_COMMON_MASK_FLAG_DRIFT", str(block["blockId"]))
                if root_sufficient:
                    values = [finite_float(samples[label]["m2CommonMaskMeanPathLength"], "INVALID_M2_MEAN") for label in ALGORITHMS]
                    require(all(value > 0 for value in values), "NONPOSITIVE_M2_MEAN", str(block["blockId"]))
                    count += 1
            included_by_condition[condition] = count
        require(all(count >= 2 for count in included_by_condition.values()), "M2_INSUFFICIENT_CONDITION_BLOCKS")
    else:
        included_by_condition = {condition: 48 for condition in CONDITIONS}

    for first, second in PAIR_FAMILY:
        strata: dict[str, list[float]] = {condition: [] for condition in CONDITIONS}
        for block in movement:
            condition = str(block["conditionId"])
            samples = sample_map(block)
            if metric == "M1":
                first_value = finite_float(samples[first]["m1Seconds"], "INVALID_M1")
                second_value = finite_float(samples[second]["m1Seconds"], "INVALID_M1")
                require(first_value > 0 and second_value > 0, "NONPOSITIVE_M1")
            elif metric == "M2":
                if block.get("m2CommonMaskSufficient") is not True:
                    continue
                first_value = finite_float(samples[first]["m2CommonMaskMeanPathLength"], "INVALID_M2")
                second_value = finite_float(samples[second]["m2CommonMaskMeanPathLength"], "INVALID_M2")
                require(first_value > 0 and second_value > 0, "NONPOSITIVE_M2")
            else:
                raise AnalysisError("UNKNOWN_PAIRWISE_METRIC", metric)
            strata[condition].append(math.log(first_value) - math.log(second_value))
        stats = stratified_mean_statistics(strata)
        stats.update(
            {
                "pair": pair_key(first, second),
                "firstAlgorithm": first,
                "secondAlgorithm": second,
                "firstProductionAlgorithm": PRODUCTION[first],
                "secondProductionAlgorithm": PRODUCTION[second],
            }
        )
        pair_results.append(stats)

    holm = holm_adjust([float(result["unadjustedTwoSidedP"]) for result in pair_results])
    for result, adjusted in zip(pair_results, holm):
        result["holmAdjustedTwoSidedP"] = adjusted
    return {
        "schema": f"gate14re-phase-b-{metric.lower()}-pairwise-v1",
        "metric": metric,
        "effectOrientation": "first algorithm divided by second algorithm; lower is better",
        "conditionsEquallyWeighted": True,
        "independentUnit": "complete block",
        "pairedWithinBlock": True,
        "multiplicity": {
            "tests": "Holm step-down adjusted p-values across six unordered algorithm pairs",
            "decisionIntervals": "Bonferroni simultaneous 95% intervals across the same six pairs",
            "exactHolmRectangularIntervalsClaimed": False,
        },
        "includedBlocksByCondition": included_by_condition,
        "pairs": pair_results,
    }


def pair_lookup(payload: Mapping[str, Any]) -> dict[frozenset[str], Mapping[str, Any]]:
    return {
        frozenset((str(row["firstAlgorithm"]), str(row["secondAlgorithm"]))): row
        for row in payload["pairs"]
    }


def adjudicate_winner(
    eligibility: Mapping[str, Any],
    m1_pairwise: Mapping[str, Any],
    m2_pairwise: Mapping[str, Any],
) -> dict[str, Any]:
    eligible = list(eligibility["eligibleAlgorithms"])
    m1_lookup = pair_lookup(m1_pairwise)
    m2_lookup = pair_lookup(m2_pairwise)
    evidence: dict[str, Any] = {}
    result_class: str
    winner: str | None = None
    basis: str

    if not eligible:
        result_class = "NO_ELIGIBLE_ALGORITHM"
        basis = "No algorithm passed all M3, M4, and M5 engineering eligibility gates."
    elif len(eligible) == 1:
        winner = eligible[0]
        result_class = "SOLE_ELIGIBLE_RECOMMENDATION"
        basis = "Exactly one algorithm passed all engineering eligibility gates; no M1 superiority claim is made against ineligible algorithms."
    else:
        m1_winners: list[str] = []
        for candidate in eligible:
            comparisons: dict[str, Any] = {}
            passes = True
            for other in eligible:
                if other == candidate:
                    continue
                oriented = orient_pair(m1_lookup[frozenset((candidate, other))], candidate, other)
                upper = float(oriented["simultaneous95RatioCI"][1])
                comparisons[other] = {"ratioEstimate": oriented["ratioEstimate"], "simultaneousUpper": upper, "passesUpperBelow0_95": upper < 0.95}
                passes = passes and upper < 0.95
            evidence.setdefault(candidate, {})["M1UniqueRule"] = comparisons
            if passes:
                m1_winners.append(candidate)

        if len(m1_winners) == 1:
            candidate = m1_winners[0]
            guard_comparisons: dict[str, Any] = {}
            guard_pass = True
            for other in eligible:
                if other == candidate:
                    continue
                oriented = orient_pair(m2_lookup[frozenset((candidate, other))], candidate, other)
                upper = float(oriented["simultaneous95RatioCI"][1])
                guard_comparisons[other] = {"ratioEstimate": oriented["ratioEstimate"], "simultaneousUpper": upper, "passesUpperAtMost1_10": upper <= 1.10}
                guard_pass = guard_pass and upper <= 1.10
            evidence.setdefault(candidate, {})["M2Guard"] = guard_comparisons
            if guard_pass:
                winner = candidate
                result_class = "UNIQUE_M1_WINNER_WITH_M2_GUARD_PASS"
                basis = "One eligible algorithm met the simultaneous M1 margin versus every other eligible algorithm and passed every M2 guard comparison."
            else:
                result_class = "NO_UNIQUE_WINNER_M2_GUARD_FAILED"
                basis = "The unique M1 candidate did not pass every M2 trajectory-cost guard."
        else:
            tie_checks: list[dict[str, Any]] = []
            tie_pass = True
            for index, first in enumerate(eligible):
                for second in eligible[index + 1 :]:
                    oriented = orient_pair(m1_lookup[frozenset((first, second))], first, second)
                    lower, upper = map(float, oriented["simultaneous95RatioCI"])
                    passes = lower >= 0.95 and upper <= 1.05
                    tie_checks.append({"pair": pair_key(first, second), "simultaneous95RatioCI": [lower, upper], "whollyWithinTieBand": passes})
                    tie_pass = tie_pass and passes
            secondary_winners: list[str] = []
            if tie_pass:
                for candidate in eligible:
                    comparisons: dict[str, Any] = {}
                    passes = True
                    for other in eligible:
                        if other == candidate:
                            continue
                        oriented = orient_pair(m2_lookup[frozenset((candidate, other))], candidate, other)
                        upper = float(oriented["simultaneous95RatioCI"][1])
                        comparisons[other] = {"ratioEstimate": oriented["ratioEstimate"], "simultaneousUpper": upper, "passesUpperBelow1_00": upper < 1.0}
                        passes = passes and upper < 1.0
                    evidence.setdefault(candidate, {})["M2SecondaryRule"] = comparisons
                    if passes:
                        secondary_winners.append(candidate)
            if tie_pass and len(secondary_winners) == 1:
                winner = secondary_winners[0]
                result_class = "M2_SECONDARY_ENGINEERING_WINNER"
                basis = "No unique M1 winner was established, every eligible M1 comparison lay wholly inside the practical tie band, and one candidate met the simultaneous M2 secondary rule."
            else:
                result_class = "NO_UNIQUE_WINNER"
                basis = "The preregistered M1/M2 evidence did not uniquely select one eligible algorithm without forcing a ranking."
            evidence["M1TieBand"] = {"allEligiblePairsWhollyWithin0_95To1_05": tie_pass, "pairs": tie_checks}

    return {
        "schema": "gate14re-phase-b-winner-adjudication-v1",
        "status": result_class,
        "winnerAlgorithmLabel": winner,
        "winnerProductionAlgorithmId": PRODUCTION[winner] if winner else None,
        "eligibleAlgorithms": eligible,
        "eligibleProductionAlgorithms": [PRODUCTION[label] for label in eligible],
        "retainedCandidateAlgorithms": eligible if winner is None else [winner],
        "retainedCandidateProductionAlgorithms": [PRODUCTION[label] for label in (eligible if winner is None else [winner])],
        "basis": basis,
        "evidence": evidence,
        "forcedWinner": False,
        "postHocExpansionPerformed": False,
    }


# ---------------------------------------------------------------------------
# Quantity-effect models and descriptive summaries.
# ---------------------------------------------------------------------------


MODEL_COLUMNS = (
    "intercept",
    "anchor_C07",
    "log2_N_centered_at_128",
    "algorithm_B",
    "algorithm_C",
    "algorithm_D",
    "algorithm_B_by_log2_N",
    "algorithm_C_by_log2_N",
    "algorithm_D_by_log2_N",
)


def quantity_blocks(blocks: Sequence[Mapping[str, Any]], lane: str) -> list[Mapping[str, Any]]:
    selected = [
        block
        for block in blocks
        if block["lane"] == lane
        and block["conditionId"] in ANCHORS
        and (
            (block["module"] == "A" and int(block["unitCount"]) == 128)
            or (block["module"] == "Q" and int(block["unitCount"]) in (1, 8, 32, 512))
        )
    ]
    require(len(selected) == 2 * 5 * 48, f"QUANTITY_{lane.upper()}_BLOCK_COUNT")
    for anchor in ANCHORS:
        for unit_count in UNIT_COUNTS:
            cell = [block for block in selected if block["conditionId"] == anchor and int(block["unitCount"]) == unit_count]
            require(len(cell) == 48, f"QUANTITY_{lane.upper()}_{anchor}_N{unit_count}_COUNT")
            require({int(block["blockIndex"]) for block in cell} == set(range(1, 49)), f"QUANTITY_{lane.upper()}_{anchor}_N{unit_count}_INDEX")
    return selected


def design_row(anchor: str, unit_count: int, algorithm: str) -> list[float]:
    x = math.log2(unit_count) - 7.0
    return [
        1.0,
        1.0 if anchor == "C07" else 0.0,
        x,
        1.0 if algorithm == "B" else 0.0,
        1.0 if algorithm == "C" else 0.0,
        1.0 if algorithm == "D" else 0.0,
        x if algorithm == "B" else 0.0,
        x if algorithm == "C" else 0.0,
        x if algorithm == "D" else 0.0,
    ]


def fit_cluster_robust_model(rows: Sequence[Mapping[str, Any]], outcome_name: str) -> dict[str, Any]:
    require(rows, "EMPTY_MODEL_ROWS", outcome_name)
    x = np.asarray([row["x"] for row in rows], dtype=np.float64)
    y = np.asarray([row["y"] for row in rows], dtype=np.float64)
    require(np.isfinite(x).all() and np.isfinite(y).all(), "NONFINITE_MODEL_INPUT", outcome_name)
    n, k = x.shape
    require(k == len(MODEL_COLUMNS) and n > k, "MODEL_DIMENSION", outcome_name)
    xtx = x.T @ x
    require(np.linalg.matrix_rank(xtx) == k, "MODEL_RANK_DEFICIENT", outcome_name)
    xtx_inv = np.linalg.inv(xtx)
    beta = xtx_inv @ x.T @ y
    residual = y - x @ beta
    clusters: dict[str, list[int]] = defaultdict(list)
    for index, row in enumerate(rows):
        clusters[str(row["cluster"])].append(index)
    g = len(clusters)
    require(g > 1, "MODEL_REQUIRES_MULTIPLE_CLUSTERS", outcome_name)
    meat = np.zeros((k, k), dtype=np.float64)
    for indices in clusters.values():
        xi = x[indices, :]
        ui = residual[indices]
        score = xi.T @ ui
        meat += np.outer(score, score)
    correction = (g / (g - 1.0)) * ((n - 1.0) / (n - k))
    covariance = correction * xtx_inv @ meat @ xtx_inv
    covariance = (covariance + covariance.T) / 2.0
    require(np.isfinite(covariance).all(), "NONFINITE_MODEL_COVARIANCE", outcome_name)
    df = float(g - 1)

    def contrast(weights: Sequence[float], label: str, *, exponentiate: bool = False) -> dict[str, Any]:
        vector = np.asarray(weights, dtype=np.float64)
        estimate = float(vector @ beta)
        variance = float(vector @ covariance @ vector)
        require(variance >= -1.0e-12, "NEGATIVE_CONTRAST_VARIANCE", label)
        se = math.sqrt(max(0.0, variance))
        if se == 0:
            t_value = 0.0 if estimate == 0 else math.copysign(float("inf"), estimate)
            pvalue = 1.0 if estimate == 0 else 0.0
            lo = hi = estimate
        else:
            t_value = estimate / se
            pvalue = two_sided_t_pvalue(t_value, df)
            critical = t_ppf(0.975, df)
            lo, hi = estimate - critical * se, estimate + critical * se
        payload: dict[str, Any] = {
            "label": label,
            "estimate": estimate,
            "standardError": se,
            "degreesOfFreedom": df,
            "tStatistic": None if not math.isfinite(t_value) else t_value,
            "twoSidedP": pvalue,
            "ordinary95CI": [lo, hi],
        }
        if exponentiate:
            payload["ratioEstimate"] = safe_exp(estimate)
            payload["ratio95CI"] = [safe_exp(lo), safe_exp(hi)]
        return payload

    coefficients = []
    for index, name in enumerate(MODEL_COLUMNS):
        weights = [0.0] * k
        weights[index] = 1.0
        coefficients.append(contrast(weights, name, exponentiate=True))

    per_doubling: dict[str, Any] = {}
    base_index = MODEL_COLUMNS.index("log2_N_centered_at_128")
    interaction_index = {
        "B": MODEL_COLUMNS.index("algorithm_B_by_log2_N"),
        "C": MODEL_COLUMNS.index("algorithm_C_by_log2_N"),
        "D": MODEL_COLUMNS.index("algorithm_D_by_log2_N"),
    }
    for algorithm in ALGORITHMS:
        weights = [0.0] * k
        weights[base_index] = 1.0
        if algorithm != "A":
            weights[interaction_index[algorithm]] = 1.0
        per_doubling[algorithm] = contrast(weights, f"{algorithm}_per_N_doubling", exponentiate=True)
        per_doubling[algorithm]["productionAlgorithmId"] = PRODUCTION[algorithm]

    interactions: dict[str, Any] = {}
    for algorithm in ("B", "C", "D"):
        weights = [0.0] * k
        weights[interaction_index[algorithm]] = 1.0
        interactions[f"{algorithm}_vs_A"] = contrast(weights, f"{algorithm}_vs_A_slope_difference", exponentiate=True)
    return {
        "outcome": outcome_name,
        "formula": "outcome ~ intercept + anchor_C07 + log2_N_centered_at_128 + algorithm + algorithm_by_log2_N",
        "observations": n,
        "independentBlockClusters": g,
        "columns": list(MODEL_COLUMNS),
        "covariance": "CR1 cluster-robust sandwich by complete block",
        "degreesOfFreedom": df,
        "coefficients": coefficients,
        "perDoublingByAlgorithm": per_doubling,
        "algorithmByQuantityInteractionsRelativeToA": interactions,
        "residualRootMeanSquare": math.sqrt(float(np.mean(residual * residual))),
    }


def build_quantity_analysis(blocks: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    movement = quantity_blocks(blocks, "movement")
    m4 = quantity_blocks(blocks, "m4")
    model_rows: dict[str, list[dict[str, Any]]] = {
        "log_M1_seconds": [],
        "log_M2_common_mask_mean_path_length": [],
        "log_M4_block_median_frame_time_seconds": [],
        "log_M4_block_P95_frame_time_seconds": [],
    }
    curves_raw: dict[str, dict[tuple[str, int, str], list[float]]] = {
        "M1_seconds": defaultdict(list),
        "M2_common_mask_mean_path_length": defaultdict(list),
        "M4_block_median_frame_time_seconds": defaultdict(list),
        "M4_block_P95_frame_time_seconds": defaultdict(list),
    }
    completion_counts: dict[tuple[str, int, str], list[bool]] = defaultdict(list)
    critical_counts: dict[tuple[str, int, str], list[int]] = defaultdict(list)

    for block in movement:
        anchor = str(block["conditionId"])
        unit_count = int(block["unitCount"])
        samples = sample_map(block)
        root_m2_sufficient = block.get("m2CommonMaskSufficient") is True
        for algorithm in ALGORITHMS:
            sample = samples[algorithm]
            xrow = design_row(anchor, unit_count, algorithm)
            m1 = finite_float(sample["m1Seconds"], "INVALID_QUANTITY_M1")
            require(m1 > 0, "NONPOSITIVE_QUANTITY_M1")
            model_rows["log_M1_seconds"].append({"x": xrow, "y": math.log(m1), "cluster": block["blockId"]})
            curves_raw["M1_seconds"][(anchor, unit_count, algorithm)].append(m1)
            completion_counts[(anchor, unit_count, algorithm)].append(sample.get("allUnitsArrived") is True)
            critical_counts[(anchor, unit_count, algorithm)].append(int(sample["m5CriticalViolationCount"]))
            if root_m2_sufficient:
                m2 = finite_float(sample["m2CommonMaskMeanPathLength"], "INVALID_QUANTITY_M2")
                require(m2 > 0, "NONPOSITIVE_QUANTITY_M2")
                model_rows["log_M2_common_mask_mean_path_length"].append({"x": xrow, "y": math.log(m2), "cluster": block["blockId"]})
                curves_raw["M2_common_mask_mean_path_length"][(anchor, unit_count, algorithm)].append(m2)

    for block in m4:
        anchor = str(block["conditionId"])
        unit_count = int(block["unitCount"])
        samples = sample_map(block)
        for algorithm in ALGORITHMS:
            sample = samples[algorithm]
            xrow = design_row(anchor, unit_count, algorithm)
            median = finite_float(sample["medianFrameTimeSeconds"], "INVALID_QUANTITY_M4_MEDIAN")
            p95 = finite_float(sample["nearestRankP95FrameTimeSeconds"], "INVALID_QUANTITY_M4_P95")
            require(median > 0 and p95 > 0, "NONPOSITIVE_QUANTITY_M4")
            model_rows["log_M4_block_median_frame_time_seconds"].append({"x": xrow, "y": math.log(median), "cluster": block["blockId"]})
            model_rows["log_M4_block_P95_frame_time_seconds"].append({"x": xrow, "y": math.log(p95), "cluster": block["blockId"]})
            curves_raw["M4_block_median_frame_time_seconds"][(anchor, unit_count, algorithm)].append(median)
            curves_raw["M4_block_P95_frame_time_seconds"][(anchor, unit_count, algorithm)].append(p95)

    model_results = {
        name: fit_cluster_robust_model(rows, name)
        for name, rows in model_rows.items()
        if name != "log_M2_common_mask_mean_path_length" or len({row["cluster"] for row in rows}) > len(MODEL_COLUMNS)
    }

    curves: dict[str, list[dict[str, Any]]] = {}
    for outcome, cells in curves_raw.items():
        rows: list[dict[str, Any]] = []
        for anchor in ANCHORS:
            for unit_count in UNIT_COUNTS:
                for algorithm in ALGORITHMS:
                    values = cells.get((anchor, unit_count, algorithm), [])
                    if outcome == "M2_common_mask_mean_path_length" and len(values) < 2:
                        rows.append({
                            "anchor": anchor,
                            "unitCount": unit_count,
                            "algorithmLabel": algorithm,
                            "productionAlgorithmId": PRODUCTION[algorithm],
                            "nBlocks": len(values),
                            "status": "INCONCLUSIVE_INSUFFICIENT_COMMON_MASK_BLOCKS",
                        })
                    else:
                        require(len(values) == 48 or outcome == "M2_common_mask_mean_path_length", "QUANTITY_CURVE_CELL_COUNT")
                        summary = one_sample_log_summary(values)
                        rows.append({
                            "anchor": anchor,
                            "unitCount": unit_count,
                            "algorithmLabel": algorithm,
                            "productionAlgorithmId": PRODUCTION[algorithm],
                            "status": "ESTIMATED",
                            **summary,
                        })
        curves[outcome] = rows

    supportive: list[dict[str, Any]] = []
    for anchor in ANCHORS:
        for unit_count in UNIT_COUNTS:
            for algorithm in ALGORITHMS:
                completed = completion_counts[(anchor, unit_count, algorithm)]
                require(len(completed) == 48, "QUANTITY_COMPLETION_CELL_COUNT")
                count = sum(completed)
                lo, hi = wilson_interval(count, 48)
                critical = critical_counts[(anchor, unit_count, algorithm)]
                require(len(critical) == 48, "QUANTITY_CRITICAL_CELL_COUNT")
                supportive.append({
                    "anchor": anchor,
                    "unitCount": unit_count,
                    "algorithmLabel": algorithm,
                    "productionAlgorithmId": PRODUCTION[algorithm],
                    "completionBlocks": count,
                    "plannedBlocks": 48,
                    "completionProportion": count / 48.0,
                    "completionWilson95CI": [lo, hi],
                    "M5CriticalViolationCount": sum(critical),
                    "M5AffectedBlocks": sum(value > 0 for value in critical),
                })
    return {
        "schema": "gate14re-phase-b-quantity-effects-v1",
        "anchors": list(ANCHORS),
        "unitCounts": list(UNIT_COUNTS),
        "N128ReusedOnceFromModuleA": True,
        "independentUnit": "complete block",
        "models": model_results,
        "curves": curves,
        "supportiveM3M5": supportive,
        "selectionRole": "quantity effects describe scalability and applicability; winner adjudication remains at N=128",
    }


def descriptive_algorithm_summaries(blocks: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    movement = main_blocks(blocks, "movement")
    m4 = main_blocks(blocks, "m4")
    output: dict[str, Any] = {}
    for algorithm in ALGORITHMS:
        m1_condition: dict[str, Any] = {}
        m2_condition: dict[str, Any] = {}
        m4_condition: dict[str, Any] = {}
        for condition in CONDITIONS:
            movement_blocks = [block for block in movement if block["conditionId"] == condition]
            m1_values = [finite_float(sample_map(block)[algorithm]["m1Seconds"], "INVALID_DESCRIPTIVE_M1") for block in movement_blocks]
            m1_condition[condition] = one_sample_log_summary(m1_values)
            m2_values = [
                finite_float(sample_map(block)[algorithm]["m2CommonMaskMeanPathLength"], "INVALID_DESCRIPTIVE_M2")
                for block in movement_blocks
                if block.get("m2CommonMaskSufficient") is True
            ]
            m2_condition[condition] = one_sample_log_summary(m2_values) if len(m2_values) >= 2 else {"nBlocks": len(m2_values), "status": "INCONCLUSIVE"}
            render_blocks = [block for block in m4 if block["conditionId"] == condition]
            medians = [finite_float(sample_map(block)[algorithm]["medianFrameTimeSeconds"], "INVALID_DESCRIPTIVE_M4") for block in render_blocks]
            p95s = [finite_float(sample_map(block)[algorithm]["nearestRankP95FrameTimeSeconds"], "INVALID_DESCRIPTIVE_M4") for block in render_blocks]
            m4_condition[condition] = {
                "medianFrameTimeSeconds": one_sample_log_summary(medians),
                "P95FrameTimeSeconds": one_sample_log_summary(p95s),
            }
        output[algorithm] = {
            "productionAlgorithmId": PRODUCTION[algorithm],
            "M1ByCondition": m1_condition,
            "M2ByCondition": m2_condition,
            "M4ByCondition": m4_condition,
        }
    return {
        "schema": "gate14re-phase-b-descriptive-main-summaries-v1",
        "scope": "module A at N=128",
        "algorithms": output,
    }


# ---------------------------------------------------------------------------
# Reporting, fallacy scan, and immutable analysis commit.
# ---------------------------------------------------------------------------


def fmt(value: float | None, digits: int = 4) -> str:
    if value is None:
        return "NA"
    return f"{float(value):.{digits}f}"


def build_fallacy_scan(
    blocks: Sequence[Mapping[str, Any]],
    m1_pairwise: Mapping[str, Any],
) -> dict[str, Any]:
    # Check aggregate/stratum sign reversal for the six M1 effects.
    simpson_details: list[str] = []
    for row in m1_pairwise["pairs"]:
        overall = math.copysign(1.0, float(row["estimateLog"])) if float(row["estimateLog"]) != 0 else 0.0
        signs = {
            math.copysign(1.0, float(detail["meanLogEffect"])) if float(detail["meanLogEffect"]) != 0 else 0.0
            for detail in row["strata"].values()
        }
        nonzero_signs = {sign for sign in signs if sign != 0.0}
        if overall != 0 and len(nonzero_signs) == 1 and -overall in nonzero_signs:
            simpson_details.append(str(row["pair"]))

    checks = [
        {
            "fallacy": "Simpson's paradox",
            "severity": "RED_FLAG" if simpson_details else "NONE_DETECTED",
            "detail": "Aggregate M1 direction reversed every nonzero condition direction for: " + ", ".join(simpson_details) if simpson_details else "Condition-stratified and aggregate directions were checked; no complete all-condition reversal was detected.",
        },
        {
            "fallacy": "Ecological fallacy",
            "severity": "NONE_DETECTED",
            "detail": "Inference is explicitly restricted to repeated complete blocks in the eight fixed conditions; agent- or frame-level records are not treated as independent n.",
        },
        {
            "fallacy": "Berkson's paradox",
            "severity": "NONE_DETECTED",
            "detail": "All 1,536 preregistered valid blocks were committed; there was no outcome-based block selection and no whole-block replacement.",
        },
        {
            "fallacy": "Collider bias",
            "severity": "NONE_DETECTED",
            "detail": "The primary paired analysis does not condition on post-treatment performance variables; M2 missingness uses one shared four-algorithm mask rule.",
        },
        {
            "fallacy": "Base-rate neglect",
            "severity": "NOT_APPLICABLE",
            "detail": "The study is not a diagnostic-classification analysis. Reliability counts and denominators are reported directly.",
        },
        {
            "fallacy": "Regression to the mean",
            "severity": "NONE_DETECTED",
            "detail": "Conditions and blocks were not selected from extreme observed Gate 14Re outcomes, and prior-study effects were inadmissible.",
        },
        {
            "fallacy": "Survivorship bias",
            "severity": "NONE_DETECTED",
            "detail": "Algorithm noncompletion remains an outcome through the M1 cap and M3 terminal states; all complete formal blocks are retained.",
        },
        {
            "fallacy": "Look-elsewhere effect",
            "severity": "NONE_DETECTED",
            "detail": "The primary M1 family contains the six preregistered unordered algorithm pairs and uses Holm-adjusted p-values; no result-driven endpoint search was performed.",
        },
        {
            "fallacy": "Garden of forking paths",
            "severity": "NONE_DETECTED",
            "detail": "The Phase B contract, estimands, exclusions, multiplicity family, decision margins, and conservative simultaneous intervals were frozen before formal block outcomes were opened.",
        },
        {
            "fallacy": "Correlation is not causation",
            "severity": "SCOPE_NOTE",
            "detail": "Algorithm comparisons are controlled within-block interventions in fixed scenarios, but conclusions are not generalized to untested scenarios, hardware, or workloads.",
        },
        {
            "fallacy": "Reverse causality",
            "severity": "NOT_APPLICABLE",
            "detail": "Algorithm identity is assigned by the frozen Williams order and precedes the measured run; outcomes cannot determine algorithm identity.",
        },
    ]
    require(len(checks) == 11, "FALLACY_SCAN_COVERAGE")
    return {
        "schema": "gate14re-phase-b-statistical-validation-v1",
        "materialPassport": {
            "originSkill": "experiment-agent + nature-statistics",
            "originMode": "validate",
            "verificationStatus": "ANALYZED",
            "versionLabel": "gate14re_phase_b_validation_v1",
        },
        "overallConfidence": "RED_FLAG" if simpson_details else "SOLID",
        "coverage": "11/11",
        "checks": checks,
        "reproducibility": {
            "method": "deterministic synthetic known-answer tests plus post-commit in-memory recomputation available",
            "verdict": "ANALYZED_NOT_INDEPENDENTLY_REPLICATED",
        },
        "statisticalUnitAudit": {
            "independentUnit": "complete block",
            "technicalSubsamples": ["agents", "rendered frames", "ticks", "four within-block algorithm measurements"],
            "pairedStructureUsed": True,
            "multiplicityFamilyDefined": True,
            "missingDataRulePrespecified": True,
        },
    }


def build_markdown_report(
    eligibility: Mapping[str, Any],
    m1: Mapping[str, Any],
    m2: Mapping[str, Any],
    quantity: Mapping[str, Any],
    winner: Mapping[str, Any],
    validation: Mapping[str, Any],
) -> str:
    lines: list[str] = []
    lines.extend(
        [
            "# Gate 14Re Phase B 正式结果与赢家裁决",
            "",
            "## Material Passport",
            "",
            "- Origin Skill: experiment-agent + nature-statistics",
            "- Origin Mode: run + validate",
            "- Origin Date: 2026-10-15",
            "- Verification Status: ANALYZED",
            "- Version Label: gate14re_phase_b_formal_results_v1",
            "",
            "## 结论",
            "",
            f"- 裁决状态：`{winner['status']}`",
            f"- 推荐算法：`{winner['winnerProductionAlgorithmId'] or '无唯一赢家'}`",
            f"- 合格算法：{', '.join(winner['eligibleProductionAlgorithms']) if winner['eligibleProductionAlgorithms'] else '无'}",
            f"- 依据：{winner['basis']}",
            "- 本结论只适用于冻结的 8 个条件、N=128 主应用、指定硬件与渲染环境；数量研究用于说明扩展性，不改变 N=128 的赢家裁决。",
            "- 未启动 Gate 15V-R/OBS，也未执行任何事后扩样。",
            "",
            "## M3/M4/M5 工程资格",
            "",
            "| 标签 | 生产算法 | M3 | M4 | M5 | 合格 |",
            "|---|---|---:|---:|---:|---:|",
        ]
    )
    for algorithm in ALGORITHMS:
        row = eligibility["summary"][algorithm]
        lines.append(
            f"| {algorithm} | {row['productionAlgorithmId']} | {'PASS' if row['M3Pass'] else 'FAIL'} | {'PASS' if row['M4Pass'] else 'FAIL'} | {'PASS' if row['M5Pass'] else 'FAIL'} | {'YES' if row['eligible'] else 'NO'} |"
        )

    lines.extend(
        [
            "",
            "## M1 主比较（第一算法 / 第二算法；比率越低越好）",
            "",
            "| 比较 | 几何均值比 | 普通 95% CI | 同时 95% CI | Holm p |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    for row in m1["pairs"]:
        ordinary = row["ordinary95RatioCI"]
        simultaneous = row["simultaneous95RatioCI"]
        lines.append(
            f"| {row['firstProductionAlgorithm']} / {row['secondProductionAlgorithm']} | {fmt(row['ratioEstimate'])} | [{fmt(ordinary[0])}, {fmt(ordinary[1])}] | [{fmt(simultaneous[0])}, {fmt(simultaneous[1])}] | {fmt(row['holmAdjustedTwoSidedP'], 6)} |"
        )
    lines.extend(
        [
            "",
            "同时区间采用六比较 Bonferroni 95% 区间，作为 Holm 检验族的保守、可审计决策区间。它不会放宽赢家门槛；不把它误称为唯一的精确 Holm 矩形区间。",
            "",
            "## M2 轨迹代价护栏/次级比较",
            "",
            "| 比较 | 几何均值比 | 普通 95% CI | 同时 95% CI | Holm p |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    for row in m2["pairs"]:
        ordinary = row["ordinary95RatioCI"]
        simultaneous = row["simultaneous95RatioCI"]
        lines.append(
            f"| {row['firstProductionAlgorithm']} / {row['secondProductionAlgorithm']} | {fmt(row['ratioEstimate'])} | [{fmt(ordinary[0])}, {fmt(ordinary[1])}] | [{fmt(simultaneous[0])}, {fmt(simultaneous[1])}] | {fmt(row['holmAdjustedTwoSidedP'], 6)} |"
        )

    lines.extend(["", "## 单位数量效应（每次 N 加倍的比率）", ""])
    for outcome_name in (
        "log_M1_seconds",
        "log_M4_block_median_frame_time_seconds",
        "log_M4_block_P95_frame_time_seconds",
    ):
        model = quantity["models"][outcome_name]
        lines.extend(
            [
                f"### {outcome_name}",
                "",
                "| 标签 | 生产算法 | 每加倍比率 | 95% CI | p |",
                "|---|---|---:|---:|---:|",
            ]
        )
        for algorithm in ALGORITHMS:
            row = model["perDoublingByAlgorithm"][algorithm]
            ci = row["ratio95CI"]
            lines.append(
                f"| {algorithm} | {row['productionAlgorithmId']} | {fmt(row['ratioEstimate'])} | [{fmt(ci[0])}, {fmt(ci[1])}] | {fmt(row['twoSidedP'], 6)} |"
            )
        lines.append("")

    lines.extend(
        [
            "## 统计完整性",
            "",
            f"- 独立单位：完整 block；总计 1,536 个已提交 blocks。",
            "- 四算法为 block 内配对重复观测；单位、帧和 tick 均未被伪作独立样本。",
            "- 11 类统计谬误扫描覆盖：`{}`。".format(validation["coverage"]),
            "- 结果驱动排除、扩样、阈值变更：均未发生。",
            "- Phase A 原始根保持只读，Phase B 只写入独立分析根。",
            "",
            "## 边界",
            "",
            "Gate 15V-R/OBS 未获授权、未启动。若需要视频验证或观察性复核，应另行授权并以本次冻结赢家裁决为输入。",
            "",
        ]
    )
    return "\n".join(lines)


def compute_outputs(blocks: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    eligibility = evaluate_eligibility(blocks)
    m1 = build_pairwise(blocks, metric="M1")
    m2 = build_pairwise(blocks, metric="M2")
    winner = adjudicate_winner(eligibility, m1, m2)
    quantity = build_quantity_analysis(blocks)
    descriptive = descriptive_algorithm_summaries(blocks)
    validation = build_fallacy_scan(blocks, m1)
    report = build_markdown_report(eligibility, m1, m2, quantity, winner, validation)
    return {
        "eligibility.json": eligibility,
        "m1-primary-pairwise.json": m1,
        "m2-guard-secondary.json": m2,
        "quantity-effects.json": quantity,
        "main-descriptive-summaries.json": descriptive,
        "winner-adjudication.json": winner,
        "statistical-validation.json": validation,
        "Gate14Re_PhaseB_Formal_Results.zh-CN.md": report,
    }


def build_input_audit(
    records: Sequence[Mapping[str, Any]],
    authorization: Mapping[str, Any],
    analyzer_hash: str,
) -> dict[str, Any]:
    block_records = [record for record in records if str(record["relativePath"]).endswith("/block-output.json")]
    return {
        "schema": "gate14re-phase-b-analysis-input-audit-v1",
        "status": "PASS",
        "studyId": "Gate14Re",
        "formalRoot": REL["raw_root"],
        "rawCompleteSha256": EXPECTED["raw_complete_sha256"],
        "rawManifestSha256": EXPECTED["raw_manifest_sha256"],
        "rawCanonicalTreeSha256": EXPECTED["raw_tree_sha256"],
        "canonicalTreeRecords": len(records),
        "canonicalTreeRawBytes": sum(int(record["bytes"]) for record in records),
        "verifiedFormalBlockOutputs": len(block_records),
        "verifiedMovementBlocks": EXPECTED["movement_blocks"],
        "verifiedM4Blocks": EXPECTED["m4_blocks"],
        "verifiedAlgorithmLaneSamples": EXPECTED["algorithm_lane_samples"],
        "allRawFilesReadOnly": True,
        "analysisContractSha256": EXPECTED["contract_sha256"],
        "authorizationId": authorization["authorizationId"],
        "authorizationSha256": authorization["_sha256"],
        "analyzerSha256": analyzer_hash,
        "historicalOrPilotObservationsUsed": False,
        "rawRootModified": False,
        "gate15Started": False,
    }


def commit_analysis_root(
    project_root: Path,
    outputs: Mapping[str, Any],
    input_audit: Mapping[str, Any],
    authorization: Mapping[str, Any],
) -> dict[str, Any]:
    analysis_root = project_root / REL["analysis_root"]
    require(not analysis_root.exists(), "ANALYSIS_ROOT_ALREADY_EXISTS", str(analysis_root))
    analysis_root.parent.mkdir(parents=True, exist_ok=True)
    staging = analysis_root.parent / f".{analysis_root.name}.staging-{uuid.uuid4().hex}"
    require(not staging.exists(), "STAGING_ROOT_EXISTS")
    staging.mkdir(parents=False)
    try:
        write_json(staging / "analysis-input-audit.json", input_audit)
        for name, payload in outputs.items():
            path = staging / name
            if isinstance(payload, str):
                atomic_create(path, payload.encode("utf-8"))
            else:
                write_json(path, payload)

        payload_files = sorted(path for path in staging.rglob("*") if path.is_file())
        records: list[dict[str, Any]] = []
        for path in payload_files:
            records.append({
                "bytes": path.stat().st_size,
                "relativePath": path.relative_to(staging).as_posix(),
                "sha256": sha256_file(path),
            })
        tree_payload = b"".join(canonical_json_bytes(record, pretty=False) for record in records)
        atomic_create(staging / "analysis-canonical-tree.v1.jsonl", tree_payload)
        tree_hash = sha256_file(staging / "analysis-canonical-tree.v1.jsonl")

        winner = outputs["winner-adjudication.json"]
        manifest = {
            "schema": "gate14re-phase-b-analysis-manifest-v1",
            "studyId": "Gate14Re",
            "status": "PASS",
            "analysisRoot": REL["analysis_root"],
            "analysisContractSha256": EXPECTED["contract_sha256"],
            "authorizationId": authorization["authorizationId"],
            "authorizationSha256": authorization["_sha256"],
            "analyzerSha256": sha256_file(Path(__file__).resolve()),
            "rawCompleteSha256": EXPECTED["raw_complete_sha256"],
            "rawCanonicalTreeSha256": EXPECTED["raw_tree_sha256"],
            "payloadFiles": records,
            "payloadFileCount": len(records),
            "payloadRawBytes": sum(record["bytes"] for record in records),
            "canonicalTreeSha256": tree_hash,
            "winnerAdjudicationStatus": winner["status"],
            "winnerProductionAlgorithmId": winner["winnerProductionAlgorithmId"],
            "phaseBFormalAnalysisExecuted": True,
            "gate15Started": False,
        }
        write_json(staging / "analysis-manifest.v1.json", manifest)
        manifest_hash = sha256_file(staging / "analysis-manifest.v1.json")
        receipt = {
            "schema": "gate14re-phase-b-analysis-receipt-v1",
            "studyId": "Gate14Re",
            "status": "FORMAL-PHASE-B-ANALYSIS-COMPLETE",
            "completedUtc": utc_now(),
            "analysisRoot": REL["analysis_root"],
            "analysisManifestSha256": manifest_hash,
            "analysisCanonicalTreeSha256": tree_hash,
            "analysisContractSha256": EXPECTED["contract_sha256"],
            "authorizationId": authorization["authorizationId"],
            "authorizationSha256": authorization["_sha256"],
            "rawCompleteSha256": EXPECTED["raw_complete_sha256"],
            "rawCanonicalTreeSha256": EXPECTED["raw_tree_sha256"],
            "formalResultAnalysisExecuted": True,
            "winnerAdjudicationExecuted": True,
            "phaseBFormalAnalysisExecuted": True,
            "winnerAdjudicationStatus": winner["status"],
            "winnerProductionAlgorithmId": winner["winnerProductionAlgorithmId"],
            "postHocExpansionPerformed": False,
            "newUnityAcquisitionPerformed": False,
            "gate15Started": False,
            "rawRootModified": False,
        }
        write_json(staging / "analysis-receipt.v1.json", receipt)
        os.replace(staging, analysis_root)
        files = [path for path in analysis_root.rglob("*") if path.is_file()]
        for path in files:
            set_read_only(path)
        require(all(is_read_only(path) for path in files), "ANALYSIS_READONLY_FREEZE_FAILED")
        receipt_path = analysis_root / "analysis-receipt.v1.json"
        return {
            **receipt,
            "analysisReceiptSha256": sha256_file(receipt_path),
            "analysisRootFiles": len(files),
            "allAnalysisFilesReadOnly": True,
        }
    except Exception:
        if staging.exists():
            # Keep failure evidence recoverable but outside the committed analysis root.
            failure_staging = project_root / REL["verify_root"] / f"failed-staging-{staging.name.split('-')[-1]}"
            failure_staging.parent.mkdir(parents=True, exist_ok=True)
            if not failure_staging.exists():
                os.replace(staging, failure_staging)
        raise


# ---------------------------------------------------------------------------
# Synthetic validation and entry points.
# ---------------------------------------------------------------------------


def synthetic_block(
    *,
    sequence: int,
    lane: str,
    condition: str,
    unit_count: int,
    block_index: int,
    movement_values: Mapping[str, tuple[float, float, bool, int]] | None = None,
    m4_values: Mapping[str, tuple[float, float]] | None = None,
    module: str = "A",
) -> dict[str, Any]:
    base = {
        "blockId": f"synthetic-{sequence}",
        "blockSequence": sequence,
        "module": module,
        "lane": lane,
        "conditionId": condition,
        "unitCount": unit_count,
        "blockIndex": block_index,
        "m2CommonMaskSufficient": True,
        "movement": [],
        "m4": [],
    }
    if lane == "movement":
        require(movement_values is not None, "SYNTHETIC_MOVEMENT_VALUES")
        for algorithm in ALGORITHMS:
            m1, m2, arrived, critical = movement_values[algorithm]
            base["movement"].append(
                {
                    "algorithmLabel": algorithm,
                    "productionAlgorithmId": PRODUCTION[algorithm],
                    "allUnitsArrived": arrived,
                    "activeAtCapCount": 0 if arrived else unit_count,
                    "noPathCount": 0,
                    "budgetExceededCount": 0,
                    "invalidPlanCount": 0,
                    "internalFailureCount": 0,
                    "m1Seconds": m1,
                    "m2CommonMaskSufficient": True,
                    "m2CommonMaskMeanPathLength": m2,
                    "m5CriticalViolationCount": critical,
                    "m5CriticalViolationCodes": [] if critical == 0 else ["synthetic-critical"],
                }
            )
    else:
        require(m4_values is not None, "SYNTHETIC_M4_VALUES")
        for algorithm in ALGORITHMS:
            median, p95 = m4_values[algorithm]
            base["m4"].append(
                {
                    "algorithmLabel": algorithm,
                    "productionAlgorithmId": PRODUCTION[algorithm],
                    "medianFrameTimeSeconds": median,
                    "nearestRankP95FrameTimeSeconds": p95,
                }
            )
    return base


def run_self_test(receipt_path: Path | None) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        require(condition, "SELF_TEST_FAILED", name + (f": {detail}" if detail else ""))
        checks.append({"name": name, "status": "PASS", "detail": detail})

    check("t-cdf-zero", abs(t_cdf(0.0, 10.0) - 0.5) < 1.0e-14)
    critical = t_ppf(0.975, 10.0)
    check("t-ppf-known-answer", abs(critical - 2.2281388519649385) < 2.0e-10, repr(critical))
    check("t-cdf-roundtrip", abs(t_cdf(critical, 10.0) - 0.975) < 1.0e-12)
    adjusted = holm_adjust([0.01, 0.04, 0.03, 0.20])
    check("holm-known-answer", all(abs(a - b) < 1.0e-12 for a, b in zip(adjusted, [0.04, 0.09, 0.09, 0.20])), repr(adjusted))
    lo, hi = wilson_interval(45, 48)
    check("wilson-bounds", 0 < lo < 45 / 48 < hi < 1)

    strata = {condition: [math.log(0.90) + (index - 23.5) * 0.0001 for index in range(48)] for condition in CONDITIONS}
    stats_payload = stratified_mean_statistics(strata)
    check("stratified-ratio-known-answer", abs(stats_payload["ratioEstimate"] - 0.90) < 1.0e-12)
    check("simultaneous-wider-than-ordinary", stats_payload["simultaneous95RatioCI"][0] <= stats_payload["ordinary95RatioCI"][0] and stats_payload["simultaneous95RatioCI"][1] >= stats_payload["ordinary95RatioCI"][1])

    pair_payloads = []
    for first, second in PAIR_FAMILY:
        ratio = 0.90 if first == "A" else 1.0
        row = stratified_mean_statistics({condition: [math.log(ratio) + (index - 23.5) * 0.0001 for index in range(48)] for condition in CONDITIONS})
        row.update({"pair": pair_key(first, second), "firstAlgorithm": first, "secondAlgorithm": second})
        pair_payloads.append(row)
    pvals = holm_adjust([row["unadjustedTwoSidedP"] for row in pair_payloads])
    for row, pvalue in zip(pair_payloads, pvals):
        row["holmAdjustedTwoSidedP"] = pvalue
    m1 = {"pairs": pair_payloads}
    m2_rows = []
    for first, second in PAIR_FAMILY:
        row = stratified_mean_statistics({condition: [(index - 23.5) * 0.00005 for index in range(48)] for condition in CONDITIONS})
        row.update({"pair": pair_key(first, second), "firstAlgorithm": first, "secondAlgorithm": second})
        m2_rows.append(row)
    for row, pvalue in zip(m2_rows, holm_adjust([row["unadjustedTwoSidedP"] for row in m2_rows])):
        row["holmAdjustedTwoSidedP"] = pvalue
    eligibility = {"eligibleAlgorithms": list(ALGORITHMS), "eligibleProductionAlgorithms": [PRODUCTION[x] for x in ALGORITHMS]}
    winner = adjudicate_winner(eligibility, m1, {"pairs": m2_rows})
    check("synthetic-clear-winner", winner["winnerAlgorithmLabel"] == "A", winner["status"])

    tie_rows = []
    for first, second in PAIR_FAMILY:
        row = stratified_mean_statistics({condition: [(index - 23.5) * 0.00005 for index in range(48)] for condition in CONDITIONS})
        row.update({"pair": pair_key(first, second), "firstAlgorithm": first, "secondAlgorithm": second, "holmAdjustedTwoSidedP": 1.0})
        tie_rows.append(row)
    no_forced_winner = adjudicate_winner(eligibility, {"pairs": tie_rows}, {"pairs": tie_rows})
    check(
        "synthetic-no-forced-winner",
        no_forced_winner["winnerAlgorithmLabel"] is None and no_forced_winner["status"] == "NO_UNIQUE_WINNER",
        no_forced_winner["status"],
    )

    # Cluster-robust model known answer: deterministic coefficient construction.
    model_rows: list[dict[str, Any]] = []
    beta_true = np.asarray([1.0, 0.1, 0.2, 0.05, -0.03, 0.02, 0.01, -0.02, 0.03])
    cluster = 0
    for anchor in ANCHORS:
        for unit_count in UNIT_COUNTS:
            for replicate in range(12):
                cluster += 1
                block_id = f"g{cluster}"
                common_noise = (replicate - 5.5) * 0.0001
                for algorithm in ALGORITHMS:
                    xrow = np.asarray(design_row(anchor, unit_count, algorithm))
                    model_rows.append({"x": xrow.tolist(), "y": float(xrow @ beta_true + common_noise), "cluster": block_id})
    model = fit_cluster_robust_model(model_rows, "synthetic")
    estimates = [row["estimate"] for row in model["coefficients"]]
    check("cluster-model-known-coefficients", max(abs(a - b) for a, b in zip(estimates, beta_true)) < 1.0e-10)

    receipt = {
        "schema": "gate14re-phase-b-analyzer-synthetic-validation-receipt-v1",
        "status": "PASS",
        "analyzerSchema": SCRIPT_SCHEMA,
        "analyzerSha256": sha256_file(Path(__file__).resolve()),
        "analysisContractSha256": EXPECTED["contract_sha256"],
        "pythonVersion": sys.version,
        "numpyVersion": np.__version__,
        "checks": checks,
        "checkCount": len(checks),
        "formalRawOpened": False,
        "formalAnalysisRootCreated": False,
        "gate15Started": False,
        "completedUtc": utc_now(),
    }
    if receipt_path is not None:
        require(not receipt_path.exists(), "SELF_TEST_RECEIPT_EXISTS", str(receipt_path))
        write_json(receipt_path, receipt)
        set_read_only(receipt_path)
    return receipt


def write_failure_receipt(project_root: Path, error: BaseException, mode: str) -> Path | None:
    verify_root = project_root / REL["verify_root"]
    try:
        verify_root.mkdir(parents=True, exist_ok=True)
        suffix = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = verify_root / f"failure-receipt-{suffix}.json"
        payload = {
            "schema": "gate14re-phase-b-analysis-failure-receipt-v1",
            "status": "FAIL_CLOSED",
            "mode": mode,
            "failureCode": error.code if isinstance(error, AnalysisError) else type(error).__name__,
            "failureDetail": str(error),
            "traceback": traceback.format_exc().splitlines()[-30:],
            "analysisRootCommitted": (project_root / REL["analysis_root"]).exists(),
            "rawRootModified": False,
            "automaticRetryPerformed": False,
            "gate15Started": False,
            "failedUtc": utc_now(),
        }
        write_json(path, payload)
        set_read_only(path)
        return path
    except Exception:
        return None


def run_formal(project_root: Path) -> dict[str, Any]:
    analysis_root = project_root / REL["analysis_root"]
    require(not analysis_root.exists(), "ANALYSIS_ROOT_ALREADY_EXISTS", str(analysis_root))
    raw_root, records, authorization = verify_raw_root(project_root)
    blocks = load_formal_blocks(raw_root, records)
    outputs = compute_outputs(blocks)
    input_audit = build_input_audit(records, authorization, sha256_file(Path(__file__).resolve()))
    return commit_analysis_root(project_root, outputs, input_audit, authorization)


def verify_existing(project_root: Path) -> dict[str, Any]:
    analysis_root = project_root / REL["analysis_root"]
    require(analysis_root.is_dir(), "ANALYSIS_ROOT_MISSING")
    raw_root, records, _ = verify_raw_root(project_root)
    blocks = load_formal_blocks(raw_root, records)
    recomputed = compute_outputs(blocks)
    mismatches: list[str] = []
    for name, payload in recomputed.items():
        path = analysis_root / name
        require(path.is_file(), "ANALYSIS_OUTPUT_MISSING", name)
        expected = payload.encode("utf-8") if isinstance(payload, str) else canonical_json_bytes(payload, pretty=True)
        actual = path.read_bytes()
        if expected != actual:
            mismatches.append(name)
    require(not mismatches, "ANALYSIS_RECOMPUTATION_MISMATCH", ", ".join(mismatches))
    files = [path for path in analysis_root.rglob("*") if path.is_file()]
    require(all(is_read_only(path) for path in files), "ANALYSIS_ROOT_NOT_READONLY")
    return {
        "schema": "gate14re-phase-b-existing-analysis-verification-v1",
        "status": "PASS",
        "recomputedPayloads": len(recomputed),
        "byteExactPayloadMatches": len(recomputed),
        "analysisRootFiles": len(files),
        "allAnalysisFilesReadOnly": True,
        "rawRootModified": False,
        "gate15Started": False,
        "verifiedUtc": utc_now(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gate 14Re Phase B formal analyzer")
    parser.add_argument("--project-root", type=Path, default=PROJECT_ROOT_DEFAULT)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--formal", action="store_true")
    mode.add_argument("--verify-existing", action="store_true")
    parser.add_argument("--self-test-receipt", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = args.project_root.resolve()
    mode = "self-test" if args.self_test else "formal" if args.formal else "verify-existing"
    try:
        if args.self_test:
            result = run_self_test(args.self_test_receipt.resolve() if args.self_test_receipt else None)
        elif args.formal:
            result = run_formal(project_root)
        else:
            result = verify_existing(project_root)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False))
        return 0
    except Exception as error:
        failure = write_failure_receipt(project_root, error, mode)
        payload = {
            "status": "FAIL_CLOSED",
            "mode": mode,
            "failureCode": error.code if isinstance(error, AnalysisError) else type(error).__name__,
            "failureDetail": str(error),
            "failureReceipt": str(failure) if failure else None,
        }
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())




