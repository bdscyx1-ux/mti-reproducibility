#!/usr/bin/env python3
"""Gate14Re-ME formal-ST v5 four-comparator domain-rule analysis.

This tool consumes only the frozen typed-Parquet acceptance package. It retains
superblock as the independent unit, keeps the full 35-hypothesis family, and
uses A*-R, BiA*-R, D*L, and LPA* as the four domain-gating comparators. C-FF is
retained as a formally tested, fully reported non-gating comparator. The tool
deliberately emits no rank, score, or winner field.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import statistics
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from itertools import combinations
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, MutableMapping, Sequence, Tuple

import numpy as np


STUDY_ID = "Gate14Re-ME"
TOOL_SCHEMA = "gate14re-me-formal-st-confirmatory-analysis-v1.2-four-comparator-domain-rule"
ALGORITHMS = ("A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF")
TARGET = "IDFF"
DOMAIN_GATE_COMPARATORS = ("A*-R", "BiA*-R", "D*L", "LPA*")
NON_GATE_COMPARATORS = ("C-FF",)
COMPARATORS = DOMAIN_GATE_COMPARATORS + NON_GATE_COMPARATORS
DOMAINS = (
    "D1_DYNAMIC_LATENCY",
    "D2_GRID_READ_WORK",
    "D3_DYNAMIC_ALLOCATION",
    "D4_PERSISTENT_STATE_BYTES",
    "D5_AGENT_COUNT_SCALING",
    "D6_CHANGE_FOOTPRINT_SCALING",
    "D7_GRID_SIZE_SCALING",
)
ALPHA = 0.05
MIPE_LOG = math.log(0.9)
CONFIRMATORY_HYPOTHESES = 35
CONFIRMATORY_PRIMITIVES = 40  # D1 has two primitive estimands for each of five comparisons.
EXPECTED_ROWS = {
    "event-groups": 186_624,
    "d3-windows": 206_401,
    "persistent-state": 1_246_752,
    "operations": 15_829_344,
    "oracle-event-checks": 31_104,
    "oracle-agent-checks": 4_741_632,
    "process-resources": 202_176,
    "empty-boundary": 12_000,
    "failures-and-voids": 2,
    "replacement-ledger": 0,
}
D3_COUNTER_ID = "GC.Alloc-Begin-owner-thread-window-v3.1"
D3_SEMANTIC_VERSION = "3.1"
D3_CONTRACT_RELATIVE = "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json"
D3_CONTRACT_SHA256 = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"
D4_FORMULA_ID = "gate14re-me-persistent-state-logical-capacity-v1"
NORMAL = statistics.NormalDist()


class AnalysisError(RuntimeError):
    """Fail-closed analysis exception."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def require_file(path: Path, expected_sha256: str, label: str) -> None:
    if not path.is_file():
        raise AnalysisError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected_sha256.lower():
        raise AnalysisError(f"{label} SHA-256 mismatch: {actual} != {expected_sha256.lower()}")


def read_json(path: Path, label: str) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise AnalysisError(f"unable to read {label}: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AnalysisError(f"{label} is not a JSON object: {path}")
    return value


def read_jsonl(path: Path, label: str) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise AnalysisError(f"{label} row is not an object: {line_number}")
                rows.append(value)
    except AnalysisError:
        raise
    except Exception as exc:
        raise AnalysisError(f"unable to read {label}: {path}: {exc}") from exc
    return rows


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    if path.exists() or temporary.exists():
        raise AnalysisError(f"refusing to overwrite output file: {path}")
    with temporary.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def write_json(path: Path, value: Any) -> None:
    atomic_write_text(path, pretty_json(value))


def write_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    atomic_write_text(path, "".join(canonical_json(dict(row)) + "\n" for row in rows))


def finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise AnalysisError(f"{label} is not numeric")
    result = float(value)
    if not math.isfinite(result):
        raise AnalysisError(f"{label} is non-finite")
    return result


def quantile(values: Sequence[float], probability: float) -> float:
    if not values:
        raise AnalysisError("quantile requested for an empty sequence")
    ordered = sorted(float(value) for value in values)
    position = probability * (len(ordered) - 1)
    low = int(math.floor(position))
    high = int(math.ceil(position))
    if low == high:
        return ordered[low]
    fraction = position - low
    return ordered[low] * (1.0 - fraction) + ordered[high] * fraction


def nearest_rank(values: Sequence[float], probability: float) -> float:
    if not values:
        raise AnalysisError("nearest-rank quantile requested for an empty sequence")
    ordered = sorted(float(value) for value in values)
    rank = max(1, int(math.ceil(probability * len(ordered))))
    return ordered[rank - 1]


def describe(values: Sequence[float]) -> Dict[str, Any]:
    data = [float(value) for value in values]
    if not data or any(not math.isfinite(value) for value in data):
        raise AnalysisError("descriptive summary received empty or non-finite data")
    return {
        "n": len(data),
        "mean": float(statistics.fmean(data)),
        "sd": float(statistics.stdev(data)) if len(data) > 1 else 0.0,
        "minimum": min(data),
        "p05": quantile(data, 0.05),
        "p25": quantile(data, 0.25),
        "median": quantile(data, 0.5),
        "p75": quantile(data, 0.75),
        "p95": quantile(data, 0.95),
        "maximum": max(data),
    }


def _beta_continued_fraction(a: float, b: float, x: float) -> float:
    maximum_iterations = 300
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
    result = d
    for iteration in range(1, maximum_iterations + 1):
        m2 = 2 * iteration
        numerator = iteration * (b - iteration) * x / ((qam + m2) * (a + m2))
        d = 1.0 + numerator * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + numerator / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        result *= d * c
        numerator = -(a + iteration) * (qab + iteration) * x / ((a + m2) * (qap + m2))
        d = 1.0 + numerator * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + numerator / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        result *= delta
        if abs(delta - 1.0) <= epsilon:
            return result
    raise AnalysisError("incomplete-beta continued fraction did not converge")


def regularized_incomplete_beta(a: float, b: float, x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    log_front = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
    front = math.exp(log_front)
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _beta_continued_fraction(a, b, x) / a
    return 1.0 - front * _beta_continued_fraction(b, a, 1.0 - x) / b


def t_cdf(value: float, degrees_freedom: float) -> float:
    if not math.isfinite(value) or degrees_freedom <= 0:
        raise AnalysisError("invalid Student-t CDF input")
    x = degrees_freedom / (degrees_freedom + value * value)
    tail = 0.5 * regularized_incomplete_beta(degrees_freedom / 2.0, 0.5, x)
    return 1.0 - tail if value >= 0 else tail


def t_ppf(probability: float, degrees_freedom: float) -> float:
    if not 0.0 < probability < 1.0:
        raise AnalysisError("invalid Student-t quantile probability")
    if probability == 0.5:
        return 0.0
    if probability < 0.5:
        return -t_ppf(1.0 - probability, degrees_freedom)
    low, high = 0.0, 1.0
    while t_cdf(high, degrees_freedom) < probability:
        high *= 2.0
        if high > 1.0e6:
            raise AnalysisError("unable to bracket Student-t quantile")
    for _ in range(120):
        middle = (low + high) / 2.0
        if t_cdf(middle, degrees_freedom) < probability:
            low = middle
        else:
            high = middle
    return (low + high) / 2.0


def distribution_cdf(value: float, inference: str, degrees_freedom: float | None) -> float:
    if inference == "normal-z":
        return NORMAL.cdf(value)
    if inference == "cluster-t" and degrees_freedom is not None:
        return t_cdf(value, degrees_freedom)
    raise AnalysisError(f"unknown inference distribution: {inference}")


def distribution_quantile(probability: float, inference: str, degrees_freedom: float | None) -> float:
    if inference == "normal-z":
        return NORMAL.inv_cdf(probability)
    if inference == "cluster-t" and degrees_freedom is not None:
        return t_ppf(probability, degrees_freedom)
    raise AnalysisError(f"unknown inference distribution: {inference}")


def holm_adjust(p_values: Sequence[float]) -> List[float]:
    m = len(p_values)
    order = sorted(range(m), key=lambda index: (p_values[index], index))
    adjusted = [1.0] * m
    running = 0.0
    for rank, index in enumerate(order):
        candidate = min(1.0, (m - rank) * float(p_values[index]))
        running = max(running, candidate)
        adjusted[index] = running
    return adjusted


def _group_indices(clusters: Sequence[str]) -> List[np.ndarray]:
    grouped: MutableMapping[str, List[int]] = defaultdict(list)
    for index, cluster in enumerate(clusters):
        grouped[str(cluster)].append(index)
    return [np.asarray(indices, dtype=np.int64) for _, indices in sorted(grouped.items())]


def fit_cluster_robust(X: np.ndarray, y: np.ndarray, clusters: Sequence[str], columns: Sequence[str], reason: str) -> Dict[str, Any]:
    n, p = X.shape
    groups = _group_indices(clusters)
    cluster_count = len(groups)
    xtx = X.T @ X
    if np.linalg.matrix_rank(xtx) != p:
        raise AnalysisError("cluster-robust fallback design matrix is rank deficient")
    bread = np.linalg.inv(xtx)
    beta = bread @ (X.T @ y)
    residual = y - X @ beta
    meat = np.zeros((p, p), dtype=float)
    for indices in groups:
        score = X[indices].T @ residual[indices]
        meat += np.outer(score, score)
    correction = (cluster_count / (cluster_count - 1.0)) * ((n - 1.0) / (n - p))
    covariance = correction * bread @ meat @ bread
    if np.any(np.diag(covariance) < -1.0e-12) or not np.all(np.isfinite(covariance)):
        raise AnalysisError("cluster-robust covariance is invalid")
    return {
        "estimator": "same-formula OLS with superblock-cluster-robust CR1 covariance",
        "fallbackUsed": True,
        "fallbackReason": reason,
        "inference": "cluster-t",
        "degreesFreedom": float(cluster_count - 1),
        "beta": beta,
        "covariance": covariance,
        "columns": list(columns),
        "nRows": n,
        "independentSuperblocks": cluster_count,
        "rank": int(np.linalg.matrix_rank(X)),
        "conditionNumber": float(np.linalg.cond(xtx)),
    }


def fit_random_intercept_reml(X: np.ndarray, y: np.ndarray, clusters: Sequence[str], columns: Sequence[str]) -> Dict[str, Any]:
    n, p = X.shape
    groups = _group_indices(clusters)
    if len(groups) < 2 or any(len(indices) != 6 for indices in groups):
        raise AnalysisError("mixed model requires complete six-lane superblock clusters")
    if np.linalg.matrix_rank(X) != p:
        raise AnalysisError("mixed model design matrix is rank deficient")
    xtx = X.T @ X
    xty = X.T @ y
    yty = float(y.T @ y)
    group_summaries = [(X[idx].sum(axis=0), float(y[idx].sum()), len(idx)) for idx in groups]

    def evaluate(lam: float) -> Tuple[float, np.ndarray, np.ndarray, float, float]:
        information = xtx.copy()
        rhs = xty.copy()
        y_weighted_y = yty
        log_determinant_v = 0.0
        for x_sum, y_sum, size in group_summaries:
            coefficient = 0.0 if lam == 0.0 else lam / (1.0 + size * lam)
            information -= coefficient * np.outer(x_sum, x_sum)
            rhs -= coefficient * x_sum * y_sum
            y_weighted_y -= coefficient * y_sum * y_sum
            log_determinant_v += math.log1p(size * lam)
        sign, logdet_information = np.linalg.slogdet(information)
        condition = float(np.linalg.cond(information))
        if sign <= 0 or not math.isfinite(condition) or condition > 1.0e13:
            raise AnalysisError("mixed-model information matrix is invalid or ill-conditioned")
        beta = np.linalg.solve(information, rhs)
        residual_sum = y_weighted_y - 2.0 * float(beta.T @ rhs) + float(beta.T @ information @ beta)
        if not math.isfinite(residual_sum) or residual_sum <= 0.0:
            raise AnalysisError("mixed-model weighted residual sum of squares is invalid")
        residual_df = n - p
        objective = log_determinant_v + logdet_information + residual_df * math.log(residual_sum / residual_df)
        return objective, beta, information, residual_sum, condition

    candidates: List[Tuple[float, float]] = [(evaluate(0.0)[0], 0.0)]
    grid = np.linspace(-12.0, 12.0, 49)
    for theta in grid:
        lam = math.exp(float(theta))
        try:
            candidates.append((evaluate(lam)[0], lam))
        except AnalysisError:
            continue
    if len(candidates) < 3:
        raise AnalysisError("mixed-model variance profile has too few finite evaluations")
    best_objective, best_lambda = min(candidates, key=lambda item: item[0])
    if best_lambda > 0.0:
        best_theta_index = min(range(len(grid)), key=lambda index: abs(math.exp(float(grid[index])) - best_lambda))
        if best_theta_index == len(grid) - 1:
            raise AnalysisError("mixed-model variance profile minimizes at the upper search boundary")
        left = float(grid[max(0, best_theta_index - 1)])
        right = float(grid[min(len(grid) - 1, best_theta_index + 1)])
        golden = (math.sqrt(5.0) - 1.0) / 2.0
        x1 = right - golden * (right - left)
        x2 = left + golden * (right - left)
        f1 = evaluate(math.exp(x1))[0]
        f2 = evaluate(math.exp(x2))[0]
        for _ in range(100):
            if f1 > f2:
                left, x1, f1 = x1, x2, f2
                x2 = left + golden * (right - left)
                f2 = evaluate(math.exp(x2))[0]
            else:
                right, x2, f2 = x2, x1, f1
                x1 = right - golden * (right - left)
                f1 = evaluate(math.exp(x1))[0]
        optimized_lambda = math.exp((left + right) / 2.0)
        optimized_objective = evaluate(optimized_lambda)[0]
        if optimized_objective < best_objective:
            best_objective, best_lambda = optimized_objective, optimized_lambda
    objective, beta, information, residual_sum, condition = evaluate(best_lambda)
    sigma2 = residual_sum / (n - p)
    covariance = sigma2 * np.linalg.inv(information)
    tau2 = best_lambda * sigma2
    if not np.all(np.isfinite(beta)) or not np.all(np.isfinite(covariance)):
        raise AnalysisError("mixed-model estimates are non-finite")
    return {
        "estimator": "random-intercept REML mixed-effects model paired by superblock",
        "fallbackUsed": False,
        "fallbackReason": None,
        "inference": "normal-z",
        "degreesFreedom": None,
        "beta": beta,
        "covariance": covariance,
        "columns": list(columns),
        "nRows": n,
        "independentSuperblocks": len(groups),
        "rank": int(np.linalg.matrix_rank(X)),
        "conditionNumber": condition,
        "variance": {
            "residual": float(sigma2),
            "superblockRandomIntercept": float(tau2),
            "varianceRatio": float(best_lambda),
            "intraclassCorrelation": float(tau2 / (tau2 + sigma2)),
            "restrictedProfileObjective": float(objective),
            "boundaryZero": best_lambda == 0.0,
        },
    }


def fit_prespecified_model(X: np.ndarray, y: np.ndarray, clusters: Sequence[str], columns: Sequence[str]) -> Dict[str, Any]:
    try:
        return fit_random_intercept_reml(X, y, clusters, columns)
    except Exception as exc:
        return fit_cluster_robust(X, y, clusters, columns, str(exc))


def contrast(model: Mapping[str, Any], vector: np.ndarray) -> Dict[str, float]:
    beta = np.asarray(model["beta"], dtype=float)
    covariance = np.asarray(model["covariance"], dtype=float)
    estimate = float(vector @ beta)
    variance = float(vector @ covariance @ vector)
    if variance <= 0.0 or not math.isfinite(variance):
        raise AnalysisError("contrast variance is nonpositive or non-finite")
    standard_error = math.sqrt(variance)
    statistic = estimate / standard_error
    cdf = distribution_cdf(statistic, str(model["inference"]), model.get("degreesFreedom"))
    return {
        "estimate": estimate,
        "standardError": standard_error,
        "statistic": statistic,
        "oneSidedLowerP": min(1.0, max(0.0, cdf)),
        "twoSidedP": min(1.0, max(0.0, 2.0 * min(cdf, 1.0 - cdf))),
    }


def strip_model_arrays(model: Mapping[str, Any]) -> Dict[str, Any]:
    result = {key: value for key, value in model.items() if key not in {"beta", "covariance"}}
    result["coefficients"] = {
        str(name): float(value) for name, value in zip(model["columns"], np.asarray(model["beta"], dtype=float))
    }
    result["standardErrors"] = {
        str(name): float(math.sqrt(max(0.0, value)))
        for name, value in zip(model["columns"], np.diag(np.asarray(model["covariance"], dtype=float)))
    }
    return result


def import_pyarrow(pyarrow_root: Path) -> Tuple[Any, Any, str]:
    if not pyarrow_root.is_dir():
        raise AnalysisError(f"frozen PyArrow package root is missing: {pyarrow_root}")
    sys.path.insert(0, str(pyarrow_root))
    try:
        import pyarrow as pa  # type: ignore
        import pyarrow.parquet as pq  # type: ignore
    except Exception as exc:
        raise AnalysisError(f"unable to import frozen PyArrow runtime: {exc}") from exc
    return pa, pq, str(pa.__version__)


def parquet_batches(pq: Any, path: Path, columns: Sequence[str], batch_size: int = 65_536) -> Iterator[Dict[str, List[Any]]]:
    parquet = pq.ParquetFile(path)
    for batch in parquet.iter_batches(batch_size=batch_size, columns=list(columns), use_threads=False):
        yield {name: batch.column(index).to_pylist() for index, name in enumerate(columns)}


def validate_acceptance_package(
    package_root: Path,
    terminal_final: Path,
    terminal_final_sha256: str,
    terminal_receipt_sha256: str,
    acceptance_manifest_sha256: str,
    file_manifest_sha256: str,
) -> Tuple[Dict[str, Any], Dict[str, Any], Dict[str, Dict[str, Any]]]:
    require_file(terminal_final, terminal_final_sha256, "acceptance terminal-final receipt")
    terminal = read_json(terminal_final, "acceptance terminal-final receipt")
    if (
        terminal.get("schema") != "gate14re-me-formal-st-acceptance-terminal-receipt-v5"
        or terminal.get("status") != "PASS_READ_ONLY_FORMAL_ST_ACCEPTANCE"
        or terminal.get("acceptedSuperblocks") != 1296
        or terminal.get("namedAlgorithmLanes") != 7776
        or terminal.get("eventGroupRows") != 186624
        or terminal.get("typedParquetFullRoundTrip") is not True
        or terminal.get("sourceMeasuredRootWriteBack") is not False
        or terminal.get("formalAnalysisPerformed") is not False
    ):
        raise AnalysisError("acceptance terminal-final identity/status mismatch")
    terminal_receipt_path = package_root / "terminal-receipt.v5.json"
    acceptance_manifest_path = package_root / "acceptance-manifest.v5.json"
    file_manifest_path = package_root / "file-manifest.v5.jsonl"
    require_file(terminal_receipt_path, terminal_receipt_sha256, "acceptance terminal receipt")
    require_file(acceptance_manifest_path, acceptance_manifest_sha256, "acceptance manifest")
    require_file(file_manifest_path, file_manifest_sha256, "acceptance file manifest")
    if terminal.get("terminalReceiptSha256") != terminal_receipt_sha256:
        raise AnalysisError("terminal-final does not bind the supplied acceptance terminal receipt")
    if terminal.get("deliveryManifestSha256") != acceptance_manifest_sha256:
        raise AnalysisError("terminal-final does not bind the supplied acceptance manifest")
    if terminal.get("fileManifestSha256") != file_manifest_sha256:
        raise AnalysisError("terminal-final does not bind the supplied file manifest")
    manifest = read_json(acceptance_manifest_path, "acceptance manifest")
    compatibility = read_json(package_root / "recovery-compatibility-validation.v2.json", "recovery compatibility validation")
    if (
        manifest.get("status") != "PASS_NECESSARY_CONTROL_RAW_AND_TYPED_PARQUET_ROUND_TRIP"
        or manifest.get("tableCount") != 10
        or manifest.get("totalRows") != 22_456_035
        or manifest.get("sealedInventoryReplay", {}).get("allCurrentHashesMatchSeal") is not True
        or manifest.get("joinCriticalIdentityValidation", {}).get("oneToOneCompleteForRequiredLinks") is not True
        or manifest.get("controlPlaneValidation", {}).get("pass") is not True
    ):
        raise AnalysisError("acceptance manifest status/cardinality/seal replay mismatch")
    if manifest.get("tableRowCounts") != EXPECTED_ROWS:
        raise AnalysisError("acceptance manifest table row counts differ from the frozen formal dataset")
    control = manifest.get("controlPlaneValidation", {})
    if (
        control.get("processLedgerRows") != 7843
        or control.get("trustedProcessIdentityReceipts") != 7843
        or control.get("acceptedSuperblocks") != 1296
        or control.get("laneReceipts") != 7776
        or control.get("failureLedgerRows") != 2
        or control.get("replacementLedgerRows") != 0
    ):
        raise AnalysisError("acceptance control-plane validation does not match attempt-003 recovery-v2 closure")
    if (
        compatibility.get("status") != "PASS_FROZEN_VALIDATOR_WITH_AUTHORIZED_RECOVERY_COMPATIBILITY"
        or compatibility.get("failureResolutionV1Validated") is not True
        or compatibility.get("failureResolutionV2Validated") is not True
        or compatibility.get("preservedTechnicalFailureRows") != 2
        or compatibility.get("replacementRows") != 0
        or compatibility.get("replayedAlgorithmLanes") != 0
        or compatibility.get("formalAnalysisPerformed") is not False
    ):
        raise AnalysisError("authorized recovery compatibility validation mismatch")

    file_rows = read_jsonl(file_manifest_path, "acceptance file manifest")
    seen: set[str] = set()
    for row in file_rows:
        relative = row.get("relativePath")
        expected_hash = row.get("sha256")
        expected_bytes = row.get("bytes")
        if not isinstance(relative, str) or not isinstance(expected_hash, str) or not isinstance(expected_bytes, int):
            raise AnalysisError("malformed acceptance file-manifest row")
        if relative in seen:
            raise AnalysisError(f"duplicate acceptance file-manifest path: {relative}")
        seen.add(relative)
        path = (package_root / relative).resolve(strict=False)
        try:
            path.relative_to(package_root.resolve())
        except ValueError as exc:
            raise AnalysisError(f"acceptance file-manifest path escapes package root: {relative}") from exc
        if not path.is_file() or path.stat().st_size != expected_bytes or sha256_file(path) != expected_hash:
            raise AnalysisError(f"acceptance package file differs from its frozen manifest: {relative}")

    tables: Dict[str, Dict[str, Any]] = {}
    for table in manifest.get("tables", []):
        if not isinstance(table, dict) or not isinstance(table.get("tableId"), str):
            raise AnalysisError("malformed table entry in acceptance manifest")
        table_id = str(table["tableId"])
        if table_id in tables or table.get("rows") != EXPECTED_ROWS.get(table_id):
            raise AnalysisError(f"duplicate or cardinality-mismatched table manifest: {table_id}")
        typed = table.get("typedParquet", {})
        relative = typed.get("relativePath")
        if typed.get("completeValueTypeOrderRoundTripPass") is not True or not isinstance(relative, str):
            raise AnalysisError(f"typed-Parquet round-trip status mismatch: {table_id}")
        parquet_path = package_root / relative
        require_file(parquet_path, str(typed.get("sha256")), f"{table_id} typed Parquet")
        tables[table_id] = table
    if set(tables) != set(EXPECTED_ROWS):
        raise AnalysisError("acceptance manifest table set mismatch")
    return terminal, manifest, tables


def load_schedule_and_identity(
    schedule_path: Path,
    schedule_sha256: str,
    identity_path: Path,
    identity_sha256: str,
) -> Tuple[List[Dict[str, Any]], Dict[Tuple[str, str], Dict[str, Any]]]:
    require_file(schedule_path, schedule_sha256, "formal schedule")
    require_file(identity_path, identity_sha256, "algorithm identity binding")
    identity = read_json(identity_path, "algorithm identity binding")
    if (
        identity.get("status") != "AUTHORIZED_REUSE_OF_QUALIFIED_SIX_ALGORITHM_BIJECTION_FOR_FORMAL_ST"
        or tuple(identity.get("namedAlgorithms", [])) != ALGORITHMS
        or identity.get("authorizationBoundary", {}).get("algorithmRankingAuthorized") is not False
    ):
        raise AnalysisError("algorithm identity binding status or cohort mismatch")
    bijection = {
        str(row.get("anonymousLaneId")): str(row.get("algorithmId"))
        for row in identity.get("bijection", [])
        if isinstance(row, dict)
    }
    if len(bijection) != 6 or set(bijection.values()) != set(ALGORITHMS):
        raise AnalysisError("algorithm identity binding is not a six-algorithm bijection")
    schedule = read_jsonl(schedule_path, "formal schedule")
    if len(schedule) != 1296:
        raise AnalysisError(f"formal schedule row count mismatch: {len(schedule)}")
    lane_map: Dict[Tuple[str, str], Dict[str, Any]] = {}
    superblocks: set[str] = set()
    for ordinal, row in enumerate(schedule):
        if (
            row.get("schema") != "gate14re-me-formal-st-schedule-row-v5"
            or row.get("ordinal") != ordinal
            or row.get("replacement") is not None
        ):
            raise AnalysisError(f"formal schedule schema/ordinal/replacement mismatch at {ordinal}")
        superblock = row.get("superblockId")
        order = row.get("algorithmOrder")
        if not isinstance(superblock, str) or superblock in superblocks or not isinstance(order, list) or len(order) != 6:
            raise AnalysisError(f"formal schedule superblock/order mismatch at {ordinal}")
        superblocks.add(superblock)
        for position, lane in enumerate(order):
            if not isinstance(lane, dict):
                raise AnalysisError(f"formal schedule lane is malformed at {ordinal}/{position}")
            anonymous = lane.get("anonymousLaneId")
            algorithm = lane.get("algorithmId")
            key = (superblock, str(anonymous))
            if (
                not isinstance(anonymous, str)
                or not isinstance(algorithm, str)
                or bijection.get(anonymous) != algorithm
                or lane.get("identityBindingSha256") != identity_sha256
                or key in lane_map
            ):
                raise AnalysisError(f"formal schedule lane/identity mismatch at {ordinal}/{position}")
            lane_map[key] = {
                "algorithm": algorithm,
                "position": position,
                "scheduleOrdinal": ordinal,
                "identityBindingSha256": identity_sha256,
            }
    if len(lane_map) != 7776:
        raise AnalysisError("formal schedule does not contain exactly 7776 lane assignments")
    return schedule, lane_map


def aggregate_event_groups(
    pq: Any,
    path: Path,
    lane_map: Mapping[Tuple[str, str], Mapping[str, Any]],
) -> Tuple[List[Dict[str, Any]], Dict[str, Tuple[Tuple[str, str], int]], Dict[str, Any]]:
    columns = (
        "recordId", "superblockId", "anonymousLaneId", "identityBindingSha256",
        "gridEdge", "agentCount", "changedCellCount", "changeTopology", "graphProfile",
        "sameTickAtomicPartitions", "contextStratumId", "eventGroupIndex",
        "eventGroupElapsedMilliseconds", "d3WindowRecordId", "d3CounterValid",
        "gridContainsCalls", "gridIsWalkableCalls", "gridGetTraversalCostCalls",
        "gridAccessorCallsTotal", "budgetExceededOperationCount", "eligible",
        "missingOrIneligibleReasonCode", "finitePositiveElapsed", "counterValid",
    )
    lanes: Dict[Tuple[str, str], Dict[str, Any]] = {}
    d3_links: Dict[str, Tuple[Tuple[str, str], int]] = {}
    record_ids: set[str] = set()
    rows = 0
    d1_valid = True
    d2_valid = True
    for batch in parquet_batches(pq, path, columns):
        for index in range(len(batch["recordId"])):
            rows += 1
            superblock = str(batch["superblockId"][index])
            anonymous = str(batch["anonymousLaneId"][index])
            key = (superblock, anonymous)
            scheduled = lane_map.get(key)
            if scheduled is None:
                raise AnalysisError(f"event-group row is not scheduled: {key}")
            record_id = str(batch["recordId"][index])
            if record_id in record_ids:
                raise AnalysisError(f"duplicate event-group recordId: {record_id}")
            record_ids.add(record_id)
            event_index = int(batch["eventGroupIndex"][index])
            if event_index < 0 or event_index >= 24:
                raise AnalysisError(f"event-group index is outside 0..23: {record_id}")
            identity_sha = str(batch["identityBindingSha256"][index])
            if identity_sha != scheduled["identityBindingSha256"]:
                raise AnalysisError(f"event-group identity binding mismatch: {record_id}")
            factors = {
                "gridEdge": int(batch["gridEdge"][index]),
                "agentCount": int(batch["agentCount"][index]),
                "changedCellCount": int(batch["changedCellCount"][index]),
                "changeTopology": str(batch["changeTopology"][index]),
                "graphProfile": str(batch["graphProfile"][index]),
                "sameTickAtomicPartitions": int(batch["sameTickAtomicPartitions"][index]),
                "contextStratumId": str(batch["contextStratumId"][index]),
            }
            lane = lanes.get(key)
            if lane is None:
                lane = {
                    "superblockId": superblock,
                    "anonymousLaneId": anonymous,
                    "algorithm": str(scheduled["algorithm"]),
                    "executionPosition": int(scheduled["position"]),
                    "scheduleOrdinal": int(scheduled["scheduleOrdinal"]),
                    **factors,
                    "elapsed": [None] * 24,
                    "gridContains": [None] * 24,
                    "gridWalkable": [None] * 24,
                    "gridTraversal": [None] * 24,
                    "gridTotal": [None] * 24,
                    "d3Links": [None] * 24,
                }
                lanes[key] = lane
            elif any(lane[name] != value for name, value in factors.items()):
                raise AnalysisError(f"design factors vary within lane: {key}")
            if lane["elapsed"][event_index] is not None:
                raise AnalysisError(f"duplicate event-group index within lane: {key}/{event_index}")
            elapsed = finite_number(batch["eventGroupElapsedMilliseconds"][index], f"{record_id}.elapsed")
            contains = int(batch["gridContainsCalls"][index])
            walkable = int(batch["gridIsWalkableCalls"][index])
            traversal = int(batch["gridGetTraversalCostCalls"][index])
            total = int(batch["gridAccessorCallsTotal"][index])
            if contains < 0 or walkable < 0 or traversal < 0 or total != contains + walkable + traversal:
                d2_valid = False
            if (
                elapsed <= 0.0
                or batch["eligible"][index] is not True
                or batch["finitePositiveElapsed"][index] is not True
                or batch["counterValid"][index] is not True
                or batch["d3CounterValid"][index] is not True
                or int(batch["budgetExceededOperationCount"][index]) != 0
                or str(batch["missingOrIneligibleReasonCode"][index]) != ""
            ):
                d1_valid = False
            link = str(batch["d3WindowRecordId"][index])
            if link in d3_links:
                raise AnalysisError(f"event-group D3 link is not one-to-one: {link}")
            d3_links[link] = (key, event_index)
            lane["elapsed"][event_index] = elapsed
            lane["gridContains"][event_index] = contains
            lane["gridWalkable"][event_index] = walkable
            lane["gridTraversal"][event_index] = traversal
            lane["gridTotal"][event_index] = total
            lane["d3Links"][event_index] = link
    if rows != EXPECTED_ROWS["event-groups"] or len(record_ids) != rows or len(lanes) != 7776 or len(d3_links) != rows:
        raise AnalysisError("event-group row, identity, lane, or D3-link cardinality mismatch")
    output: List[Dict[str, Any]] = []
    for key, lane in lanes.items():
        if any(value is None for name in ("elapsed", "gridContains", "gridWalkable", "gridTraversal", "gridTotal", "d3Links") for value in lane[name]):
            raise AnalysisError(f"lane lacks one or more of 24 event-group rows: {key}")
        elapsed = [float(value) for value in lane.pop("elapsed")]
        lane["d1GeometricMeanMilliseconds"] = math.exp(statistics.fmean(math.log(value) for value in elapsed))
        lane["d1NearestRankP95Milliseconds"] = nearest_rank(elapsed, 0.95)
        lane["d2GridAccessorCalls"] = int(sum(lane.pop("gridTotal")))
        lane["d2GridContainsCalls"] = int(sum(lane.pop("gridContains")))
        lane["d2GridIsWalkableCalls"] = int(sum(lane.pop("gridWalkable")))
        lane["d2GridGetTraversalCostCalls"] = int(sum(lane.pop("gridTraversal")))
        if lane["d2GridAccessorCalls"] <= 0:
            d2_valid = False
        output.append(lane)
    output.sort(key=lambda row: (row["scheduleOrdinal"], row["executionPosition"]))
    gates = {
        "D1EventGroupValidity": d1_valid,
        "D2GridCounterValidity": d2_valid,
        "eventGroupRows": rows,
        "lanes": len(output),
        "rowsPerLane": 24,
        "uniqueD3Links": len(d3_links),
    }
    return output, d3_links, gates


def attach_d3_allocations(
    pq: Any,
    path: Path,
    lanes: List[Dict[str, Any]],
    d3_links: Mapping[str, Tuple[Tuple[str, str], int]],
) -> Dict[str, Any]:
    columns = (
        "recordId", "superblockId", "anonymousLaneId", "identityBindingSha256",
        "measurementScope", "eventGroupIndex", "d3CounterId", "d3SemanticVersion",
        "managedAllocationBytes", "managedAllocationEventCount", "foreignThreadAllocationBytes",
        "foreignThreadAllocationEventCount", "invalidMetadataEventCount", "counterOverflowCount",
        "ownerNativeThreadId", "observerNativeThreadId", "windowElapsedStopwatchTicks",
        "stopwatchFrequency", "managedAllocationRateBytesPerSecond", "managedAllocationRateValid",
        "beginReturnCode", "endReturnCode", "pluginReady", "markerSeen", "metadataAbiValid",
        "ownerThreadMatched", "counterValid", "invalidReasonCode", "d3ContractRelativePath",
        "d3ContractSha256",
    )
    lane_by_key = {(str(row["superblockId"]), str(row["anonymousLaneId"])): row for row in lanes}
    allocations: Dict[Tuple[str, str], List[int | None]] = {key: [None] * 24 for key in lane_by_key}
    seen: set[str] = set()
    scope_counts: Counter[str] = Counter()
    rows = 0
    valid = True
    for batch in parquet_batches(pq, path, columns):
        for index in range(len(batch["recordId"])):
            rows += 1
            record_id = str(batch["recordId"][index])
            if record_id in seen:
                raise AnalysisError(f"duplicate D3 recordId: {record_id}")
            seen.add(record_id)
            scope = str(batch["measurementScope"][index])
            scope_counts[scope] += 1
            managed_bytes = int(batch["managedAllocationBytes"][index])
            managed_events = int(batch["managedAllocationEventCount"][index])
            foreign_bytes = int(batch["foreignThreadAllocationBytes"][index])
            foreign_events = int(batch["foreignThreadAllocationEventCount"][index])
            elapsed_ticks = int(batch["windowElapsedStopwatchTicks"][index])
            frequency = int(batch["stopwatchFrequency"][index])
            rate = finite_number(batch["managedAllocationRateBytesPerSecond"][index], f"{record_id}.allocationRate")
            row_valid = (
                batch["d3CounterId"][index] == D3_COUNTER_ID
                and batch["d3SemanticVersion"][index] == D3_SEMANTIC_VERSION
                and managed_bytes >= 0 and managed_events >= 0 and foreign_bytes >= 0 and foreign_events >= 0
                and int(batch["invalidMetadataEventCount"][index]) == 0
                and int(batch["counterOverflowCount"][index]) == 0
                and int(batch["ownerNativeThreadId"][index]) != 0
                and batch["ownerNativeThreadId"][index] == batch["observerNativeThreadId"][index]
                and elapsed_ticks >= 0 and frequency > 0
                and int(batch["beginReturnCode"][index]) == 0 and int(batch["endReturnCode"][index]) == 0
                and batch["pluginReady"][index] is True and batch["markerSeen"][index] is True
                and batch["metadataAbiValid"][index] is True and batch["ownerThreadMatched"][index] is True
                and batch["counterValid"][index] is True and str(batch["invalidReasonCode"][index]) == ""
                and batch["d3ContractRelativePath"][index] == D3_CONTRACT_RELATIVE
                and batch["d3ContractSha256"][index] == D3_CONTRACT_SHA256
            )
            if managed_bytes > 0 and elapsed_ticks > 0:
                expected_rate = managed_bytes * float(frequency) / elapsed_ticks
                tolerance = max(1.0e-9, abs(expected_rate) * 1.0e-12)
                row_valid = row_valid and batch["managedAllocationRateValid"][index] is True and abs(rate - expected_rate) <= tolerance
            elif managed_bytes == 0:
                row_valid = row_valid and batch["managedAllocationRateValid"][index] is False and rate == 0.0
            else:
                row_valid = False
            valid = valid and row_valid
            if scope == "event-group":
                linked = d3_links.get(record_id)
                if linked is None:
                    raise AnalysisError(f"event-group D3 record is not linked exactly once: {record_id}")
                key, expected_event_index = linked
                if (
                    str(batch["superblockId"][index]) != key[0]
                    or str(batch["anonymousLaneId"][index]) != key[1]
                    or int(batch["eventGroupIndex"][index]) != expected_event_index
                    or allocations[key][expected_event_index] is not None
                ):
                    raise AnalysisError(f"event-group D3 lane/index identity mismatch: {record_id}")
                allocations[key][expected_event_index] = managed_bytes
    expected_scopes = {
        "planner-initialization": 7776,
        "event-group": 186624,
        "empty-boundary": 12000,
        "instrument-self-test-positive-control": 1,
    }
    if rows != EXPECTED_ROWS["d3-windows"] or len(seen) != rows or dict(scope_counts) != expected_scopes:
        raise AnalysisError(f"D3 row/scope cardinality mismatch: rows={rows}; scopes={dict(scope_counts)}")
    if set(record_id for record_id, _ in d3_links.items()) - seen:
        raise AnalysisError("one or more required event-group D3 links are missing")
    for key, values in allocations.items():
        if any(value is None for value in values):
            raise AnalysisError(f"lane lacks one or more of 24 event-group D3 windows: {key}")
        lane_by_key[key]["d3TotalManagedAllocationBytes"] = int(sum(int(value) for value in values if value is not None))
    return {
        "D3CounterValidity": valid,
        "rows": rows,
        "scopeCounts": dict(scope_counts),
        "eventGroupLinksComplete": True,
        "lanes": len(allocations),
    }


def attach_persistent_state(
    pq: Any,
    path: Path,
    lanes: List[Dict[str, Any]],
) -> Dict[str, Any]:
    columns = (
        "recordId", "superblockId", "anonymousLaneId", "measurementPointId", "eventGroupIndex",
        "persistentContainerName", "containerKind", "persistentContainerCapacity",
        "persistentContainerBytesPerElement", "persistentContainerCapacityBytes",
        "persistentPrimitiveArrayBytes", "persistentStateBytesTotal", "sizingFormulaId",
        "valid", "invalidReasonCode",
    )
    lane_by_key = {(str(row["superblockId"]), str(row["anonymousLaneId"])): row for row in lanes}
    points: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
    record_ids: set[str] = set()
    rows = 0
    valid = True
    for batch in parquet_batches(pq, path, columns):
        for index in range(len(batch["recordId"])):
            rows += 1
            record_id = str(batch["recordId"][index])
            if record_id in record_ids:
                raise AnalysisError(f"duplicate persistent-state recordId: {record_id}")
            record_ids.add(record_id)
            lane_key = (str(batch["superblockId"][index]), str(batch["anonymousLaneId"][index]))
            if lane_key not in lane_by_key:
                raise AnalysisError(f"persistent-state row is not a scheduled lane: {lane_key}")
            point_id = str(batch["measurementPointId"][index])
            point_key = (lane_key[0], lane_key[1], point_id)
            name = str(batch["persistentContainerName"][index])
            kind = str(batch["containerKind"][index])
            capacity = int(batch["persistentContainerCapacity"][index])
            bytes_per = int(batch["persistentContainerBytesPerElement"][index])
            capacity_bytes = int(batch["persistentContainerCapacityBytes"][index])
            primitive_bytes = int(batch["persistentPrimitiveArrayBytes"][index])
            total = int(batch["persistentStateBytesTotal"][index])
            event_index = int(batch["eventGroupIndex"][index])
            row_valid = (
                batch["sizingFormulaId"][index] == D4_FORMULA_ID
                and batch["valid"][index] is True
                and str(batch["invalidReasonCode"][index]) == ""
                and capacity >= 0 and bytes_per >= 0 and capacity_bytes >= 0 and total >= 0
                and capacity_bytes == capacity * bytes_per
                and primitive_bytes == (capacity_bytes if kind == "array" else 0)
            )
            valid = valid and row_valid
            point = points.get(point_key)
            if point is None:
                point = {"eventGroupIndex": event_index, "total": total, "sum": 0, "components": set()}
                points[point_key] = point
            if point["eventGroupIndex"] != event_index or point["total"] != total or name in point["components"]:
                raise AnalysisError(f"persistent-state measurement-point consistency mismatch: {point_key}")
            point["components"].add(name)
            point["sum"] += capacity_bytes
    if rows != EXPECTED_ROWS["persistent-state"] or len(record_ids) != rows or len(points) != 202176:
        raise AnalysisError("persistent-state row, identity, or measurement-point cardinality mismatch")
    point_totals: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    point_ids: Dict[Tuple[str, str], set[str]] = defaultdict(set)
    for (superblock, lane, point_id), point in points.items():
        lane_key = (superblock, lane)
        point_ids[lane_key].add(point_id)
        point_totals[lane_key].append(int(point["total"]))
        expected_event = -1
        if point_id.startswith("after-event-group-"):
            try:
                expected_event = int(point_id.rsplit("-", 1)[1])
            except ValueError:
                valid = False
        elif point_id not in {"after-initialization", "after-initial-queries"}:
            valid = False
        if point["eventGroupIndex"] != expected_event or point["sum"] != point["total"] or not point["components"]:
            valid = False
    expected_ids = {"after-initialization", "after-initial-queries"} | {f"after-event-group-{index}" for index in range(24)}
    for lane_key, lane in lane_by_key.items():
        if point_ids.get(lane_key) != expected_ids or len(point_totals.get(lane_key, [])) != 26:
            raise AnalysisError(f"persistent-state measurement-point coverage mismatch: {lane_key}")
        lane["d4MaxPersistentStateBytes"] = max(point_totals[lane_key])
    return {
        "D4SizingFormulaValidity": valid,
        "rows": rows,
        "measurementPoints": len(points),
        "measurementPointsPerLane": 26,
        "lanes": len(point_ids),
        "sizingFormulaId": D4_FORMULA_ID,
    }


def validate_operations_and_oracle(pq: Any, operations_path: Path, oracle_event_path: Path) -> Dict[str, Any]:
    operation_columns = ("operationType", "status", "failureReasonCode", "budgetExceeded", "oracleReachable", "oraclePathCostMatch")
    operation_rows = 0
    correctness_valid = True
    operation_types: Counter[str] = Counter()
    statuses: Counter[str] = Counter()
    for batch in parquet_batches(pq, operations_path, operation_columns, batch_size=131_072):
        for index in range(len(batch["operationType"])):
            operation_rows += 1
            operation_type = str(batch["operationType"][index])
            status = str(batch["status"][index])
            operation_types[operation_type] += 1
            statuses[status] += 1
            row_valid = batch["budgetExceeded"][index] is False and batch["oraclePathCostMatch"][index] is True
            if operation_type in {"initialize", "repair"}:
                row_valid = row_valid and status == "Succeeded"
            elif operation_type in {"initial_query", "post_event_query"}:
                expected = "Succeeded" if batch["oracleReachable"][index] is True else "NoPath"
                row_valid = row_valid and status == expected
            else:
                row_valid = False
            correctness_valid = correctness_valid and row_valid
    if operation_rows != EXPECTED_ROWS["operations"]:
        raise AnalysisError(f"operations cardinality mismatch: {operation_rows}")

    oracle_columns = (
        "minimumAffectedAgentsPassed", "bottleneckHalfAgentsRuleApplicable",
        "bottleneckHalfAgentsPassed", "restoreGridBytesPassed", "restoreOraclePassed",
    )
    oracle_rows = 0
    oracle_valid = True
    for batch in parquet_batches(pq, oracle_event_path, oracle_columns):
        for index in range(len(batch["minimumAffectedAgentsPassed"])):
            oracle_rows += 1
            row_valid = (
                batch["minimumAffectedAgentsPassed"][index] is True
                and batch["restoreGridBytesPassed"][index] is True
                and batch["restoreOraclePassed"][index] is True
            )
            if batch["bottleneckHalfAgentsRuleApplicable"][index] is True:
                row_valid = row_valid and batch["bottleneckHalfAgentsPassed"][index] is True
            oracle_valid = oracle_valid and row_valid
    if oracle_rows != EXPECTED_ROWS["oracle-event-checks"]:
        raise AnalysisError(f"oracle-event cardinality mismatch: {oracle_rows}")
    return {
        "correctnessOracle": correctness_valid and oracle_valid,
        "operationRows": operation_rows,
        "operationTypes": dict(operation_types),
        "operationStatuses": dict(statuses),
        "oracleEventRows": oracle_rows,
        "allOperationOracleMatches": correctness_valid,
        "allOracleEventChecksPass": oracle_valid,
    }


def build_design_matrix(lanes: Sequence[Mapping[str, Any]]) -> Tuple[np.ndarray, List[str], Dict[str, int], Dict[str, float]]:
    center_n = statistics.fmean(math.log2(value) for value in (32, 64, 128))
    center_f = statistics.fmean(math.log2(value) for value in (1, 9, 25, 81))
    center_g2 = statistics.fmean(math.log2(value * value) for value in (64, 96, 128))
    columns = ["Intercept"]
    columns += [f"algorithm[{algorithm}]" for algorithm in COMPARATORS]
    columns += ["centeredLog2N", "centeredLog2F", "centeredLog2G2"]
    columns += ["changeTopology[dispersed]", "changeTopology[bottleneck]"]
    columns += ["graphProfile[eight_way_uniform_sparse]"]
    columns += ["sameTickAtomicPartitions[4]", "sameTickAtomicPartitions[16]"]
    columns += [f"executionPosition[{position}]" for position in range(1, 6)]
    for algorithm in COMPARATORS:
        columns += [
            f"algorithm[{algorithm}]:centeredLog2N",
            f"algorithm[{algorithm}]:centeredLog2F",
            f"algorithm[{algorithm}]:centeredLog2G2",
        ]
    indices = {name: index for index, name in enumerate(columns)}
    X = np.zeros((len(lanes), len(columns)), dtype=float)
    allowed_topology = {"compact", "dispersed", "bottleneck"}
    allowed_graph = {"four_way_weighted_dense", "eight_way_uniform_sparse"}
    for row_index, lane in enumerate(lanes):
        algorithm = str(lane["algorithm"])
        topology = str(lane["changeTopology"])
        graph = str(lane["graphProfile"])
        partitions = int(lane["sameTickAtomicPartitions"])
        position = int(lane["executionPosition"])
        if algorithm not in ALGORITHMS or topology not in allowed_topology or graph not in allowed_graph or partitions not in {1, 4, 16} or position not in range(6):
            raise AnalysisError(f"lane contains an out-of-contract design level: {lane['superblockId']}/{lane['anonymousLaneId']}")
        cn = math.log2(int(lane["agentCount"])) - center_n
        cf = math.log2(int(lane["changedCellCount"])) - center_f
        cg = math.log2(int(lane["gridEdge"]) ** 2) - center_g2
        X[row_index, indices["Intercept"]] = 1.0
        if algorithm != TARGET:
            X[row_index, indices[f"algorithm[{algorithm}]"]] = 1.0
            X[row_index, indices[f"algorithm[{algorithm}]:centeredLog2N"]] = cn
            X[row_index, indices[f"algorithm[{algorithm}]:centeredLog2F"]] = cf
            X[row_index, indices[f"algorithm[{algorithm}]:centeredLog2G2"]] = cg
        X[row_index, indices["centeredLog2N"]] = cn
        X[row_index, indices["centeredLog2F"]] = cf
        X[row_index, indices["centeredLog2G2"]] = cg
        if topology != "compact":
            X[row_index, indices[f"changeTopology[{topology}]"]] = 1.0
        if graph != "four_way_weighted_dense":
            X[row_index, indices[f"graphProfile[{graph}]"]] = 1.0
        if partitions != 1:
            X[row_index, indices[f"sameTickAtomicPartitions[{partitions}]"]] = 1.0
        if position != 0:
            X[row_index, indices[f"executionPosition[{position}]"]] = 1.0
    if np.linalg.matrix_rank(X) != X.shape[1]:
        raise AnalysisError("prespecified fixed-effect design matrix is rank deficient")
    return X, columns, indices, {"log2N": center_n, "log2F": center_f, "log2G2": center_g2}


def algorithm_contrast(indices: Mapping[str, int], first: str, second: str, axis: str | None = None) -> np.ndarray:
    vector = np.zeros(len(indices), dtype=float)
    if axis is None:
        if first != TARGET:
            vector[indices[f"algorithm[{first}]"]] += 1.0
        if second != TARGET:
            vector[indices[f"algorithm[{second}]"]] -= 1.0
    else:
        suffix = {"N": "centeredLog2N", "F": "centeredLog2F", "G2": "centeredLog2G2"}[axis]
        if first != TARGET:
            vector[indices[f"algorithm[{first}]:{suffix}"]] += 1.0
        if second != TARGET:
            vector[indices[f"algorithm[{second}]:{suffix}"]] -= 1.0
    return vector


def transformed_interval_payload(
    result: Mapping[str, float],
    model: Mapping[str, Any],
    simultaneous_primitives: int,
    ratio_scale: bool,
) -> Dict[str, Any]:
    estimate = float(result["estimate"])
    standard_error = float(result["standardError"])
    marginal_q = distribution_quantile(1.0 - ALPHA / 2.0, str(model["inference"]), model.get("degreesFreedom"))
    simultaneous_q = distribution_quantile(
        1.0 - ALPHA / (2.0 * simultaneous_primitives),
        str(model["inference"]),
        model.get("degreesFreedom"),
    )
    marginal = [estimate - marginal_q * standard_error, estimate + marginal_q * standard_error]
    simultaneous = [estimate - simultaneous_q * standard_error, estimate + simultaneous_q * standard_error]
    payload: Dict[str, Any] = {
        "estimateModelScale": estimate,
        "standardError": standard_error,
        "statistic": float(result["statistic"]),
        "oneSidedLowerP": float(result["oneSidedLowerP"]),
        "twoSidedP": float(result["twoSidedP"]),
        "marginalTwoSided95IntervalModelScale": marginal,
        "simultaneousTwoSidedBonferroniIntervalModelScale": simultaneous,
        "simultaneousPrimitiveFamilySize": simultaneous_primitives,
        "simultaneousUpperBelowNull": simultaneous[1] < 0.0,
        "directionFavorable": estimate < 0.0,
        "reachesMipe": estimate <= MIPE_LOG,
        "inferenceDistribution": model["inference"],
        "degreesFreedom": model.get("degreesFreedom"),
    }
    if ratio_scale:
        payload.update(
            {
                "ratioEstimate": math.exp(estimate),
                "marginalTwoSided95RatioInterval": [math.exp(marginal[0]), math.exp(marginal[1])],
                "simultaneousTwoSidedBonferroniRatioInterval": [math.exp(simultaneous[0]), math.exp(simultaneous[1])],
                "nullBoundaryRatio": 1.0,
                "mipeRatioThreshold": 0.9,
            }
        )
    else:
        payload.update(
            {
                "perAxisUnitMultiplicativeFactor": math.exp(estimate),
                "marginalTwoSided95FactorInterval": [math.exp(marginal[0]), math.exp(marginal[1])],
                "simultaneousTwoSidedBonferroniFactorInterval": [math.exp(simultaneous[0]), math.exp(simultaneous[1])],
                "nullBoundarySlopeDifference": 0.0,
                "mipeSlopeThreshold": MIPE_LOG,
            }
        )
    return payload


def model_for_domain(domain: str) -> Tuple[str, str | None, bool]:
    mapping = {
        "D2_GRID_READ_WORK": ("D2", None, True),
        "D3_DYNAMIC_ALLOCATION": ("D3", None, True),
        "D4_PERSISTENT_STATE_BYTES": ("D4", None, True),
        "D5_AGENT_COUNT_SCALING": ("D1_GEOMETRIC_MEAN", "N", False),
        "D6_CHANGE_FOOTPRINT_SCALING": ("D1_GEOMETRIC_MEAN", "F", False),
        "D7_GRID_SIZE_SCALING": ("D1_GEOMETRIC_MEAN", "G2", False),
    }
    return mapping[domain]


def non_gating_comparator_summary(row: Mapping[str, Any]) -> Dict[str, Any]:
    """Return a machine-readable C-FF result plus a concrete Chinese explanation."""
    passed = bool(row["rejectAtFamilywiseAlpha0.05"])
    summary: Dict[str, Any] = {
        "comparator": str(row["comparator"]),
        "hypothesisId": str(row["hypothesisId"]),
        "passed": passed,
        "holmAdjustedOneSidedP": float(row["holmAdjustedOneSidedP"]),
        "directionFavorable": bool(row["directionFavorable"]),
        "simultaneousIntervalFavorable": bool(row["simultaneousIntervalFavorable"]),
        "reachesPrespecifiedMipe": bool(row["reachesPrespecifiedMipe"]),
        "failureExplanationZhCN": None,
    }
    if "components" in row:
        geo = row["components"]["equalDesignGeometricMeanRatio"]
        p95 = row["components"]["equalDesignNearestRankP95Ratio"]
        summary["data"] = {
            "equalDesignGeometricMeanRatio": geo["ratioEstimate"],
            "equalDesignGeometricMeanSimultaneousInterval": geo["simultaneousTwoSidedBonferroniRatioInterval"],
            "equalDesignNearestRankP95Ratio": p95["ratioEstimate"],
            "equalDesignNearestRankP95SimultaneousInterval": p95["simultaneousTwoSidedBonferroniRatioInterval"],
        }
        if not passed:
            summary["failureExplanationZhCN"] = (
                f"C-FF 比较未通过：GM 比率 {geo['ratioEstimate']:.6g}，同时区间 "
                f"[{geo['simultaneousTwoSidedBonferroniRatioInterval'][0]:.6g}, "
                f"{geo['simultaneousTwoSidedBonferroniRatioInterval'][1]:.6g}]；P95 比率 "
                f"{p95['ratioEstimate']:.6g}，同时区间 "
                f"[{p95['simultaneousTwoSidedBonferroniRatioInterval'][0]:.6g}, "
                f"{p95['simultaneousTwoSidedBonferroniRatioInterval'][1]:.6g}]。"
                "D1 是 GM 与 P95 的交并检验；P95 比率及其同时区间高于 1，"
                "因此复合比较假设未通过。"
            )
    else:
        component = row["component"]
        if "ratioEstimate" in component:
            interval = component["simultaneousTwoSidedBonferroniRatioInterval"]
            estimate = float(component["ratioEstimate"])
            summary["data"] = {
                "ratioEstimate": estimate,
                "simultaneousInterval": interval,
                "nullBoundary": 1.0,
            }
            if not passed:
                summary["failureExplanationZhCN"] = (
                    f"C-FF 比较未通过：IDFF/C-FF 比率 {estimate:.6g}，同时区间 "
                    f"[{interval[0]:.6g}, {interval[1]:.6g}]，Holm 调整单侧 p="
                    f"{row['holmAdjustedOneSidedP']:.6g}。较低为优，但比率及区间未全部低于 1。"
                )
        else:
            interval = component["simultaneousTwoSidedBonferroniIntervalModelScale"]
            estimate = float(component["estimateModelScale"])
            summary["data"] = {
                "slopeDifferenceEstimate": estimate,
                "simultaneousInterval": interval,
                "nullBoundary": 0.0,
            }
            if not passed:
                relationship = "点估计方向不利于 IDFF" if estimate >= 0.0 else "点估计方向有利于 IDFF，但同时区间跨越 0"
                summary["failureExplanationZhCN"] = (
                    f"C-FF 比较未通过：IDFF−C-FF 斜率差 {estimate:.6g}，同时区间 "
                    f"[{interval[0]:.6g}, {interval[1]:.6g}]，Holm 调整单侧 p="
                    f"{row['holmAdjustedOneSidedP']:.6g}；{relationship}。"
                )
    return summary


def build_confirmatory_results(
    models: Mapping[str, Mapping[str, Any]],
    indices: Mapping[str, int],
    domain_gates: Mapping[str, bool],
    global_correctness: bool,
) -> Dict[str, Any]:
    hypotheses: List[Dict[str, Any]] = []
    primitive_count = 0
    for domain in DOMAINS:
        for comparator in COMPARATORS:
            vector_axis: str | None = None
            if domain == "D1_DYNAMIC_LATENCY":
                geo = contrast(models["D1_GEOMETRIC_MEAN"], algorithm_contrast(indices, TARGET, comparator))
                p95 = contrast(models["D1_NEAREST_RANK_P95"], algorithm_contrast(indices, TARGET, comparator))
                geo_payload = transformed_interval_payload(geo, models["D1_GEOMETRIC_MEAN"], CONFIRMATORY_PRIMITIVES, True)
                p95_payload = transformed_interval_payload(p95, models["D1_NEAREST_RANK_P95"], CONFIRMATORY_PRIMITIVES, True)
                primitive_count += 2
                raw_p = max(float(geo["oneSidedLowerP"]), float(p95["oneSidedLowerP"]))
                direction = geo_payload["directionFavorable"] and p95_payload["directionFavorable"]
                interval_favorable = geo_payload["simultaneousUpperBelowNull"] and p95_payload["simultaneousUpperBelowNull"]
                reaches_mipe = geo_payload["reachesMipe"] and p95_payload["reachesMipe"]
                payload: Dict[str, Any] = {
                    "components": {
                        "equalDesignGeometricMeanRatio": geo_payload,
                        "equalDesignNearestRankP95Ratio": p95_payload,
                    },
                    "intersectionUnionOneSidedP": raw_p,
                }
            else:
                model_id, vector_axis, ratio_scale = model_for_domain(domain)
                result = contrast(models[model_id], algorithm_contrast(indices, TARGET, comparator, vector_axis))
                component = transformed_interval_payload(result, models[model_id], CONFIRMATORY_PRIMITIVES, ratio_scale)
                primitive_count += 1
                raw_p = float(result["oneSidedLowerP"])
                direction = bool(component["directionFavorable"])
                interval_favorable = bool(component["simultaneousUpperBelowNull"])
                reaches_mipe = bool(component["reachesMipe"])
                payload = {"component": component}
            hypotheses.append(
                {
                    "hypothesisId": f"{domain}:{TARGET}_vs_{comparator}",
                    "domainId": domain,
                    "target": TARGET,
                    "comparator": comparator,
                    "direction": "lower_is_better",
                    "domainMeasurementGateValid": bool(domain_gates[domain]),
                    "globalCorrectnessGateValid": bool(global_correctness),
                    "rawCompositeOneSidedP": raw_p,
                    "directionFavorable": direction,
                    "simultaneousIntervalFavorable": interval_favorable,
                    "reachesPrespecifiedMipe": reaches_mipe,
                    **payload,
                }
            )
    if len(hypotheses) != CONFIRMATORY_HYPOTHESES or primitive_count != CONFIRMATORY_PRIMITIVES:
        raise AnalysisError("confirmatory family cardinality does not equal 35 hypotheses / 40 primitives")
    adjusted = holm_adjust([float(row["rawCompositeOneSidedP"]) for row in hypotheses])
    for row, adjusted_p in zip(hypotheses, adjusted):
        row["holmAdjustedOneSidedP"] = adjusted_p
        row["rejectAtFamilywiseAlpha0.05"] = (
            row["domainMeasurementGateValid"]
            and row["globalCorrectnessGateValid"]
            and adjusted_p < ALPHA
            and row["directionFavorable"]
            and row["simultaneousIntervalFavorable"]
        )
    domain_results: List[Dict[str, Any]] = []
    for domain in DOMAINS:
        members = [row for row in hypotheses if row["domainId"] == domain]
        gating_members = [row for row in members if row["comparator"] in DOMAIN_GATE_COMPARATORS]
        non_gating_members = [row for row in members if row["comparator"] in NON_GATE_COMPARATORS]
        if len(gating_members) != 4 or len(non_gating_members) != 1:
            raise AnalysisError(f"four-comparator domain rule cardinality mismatch: {domain}")
        gate_valid = bool(domain_gates[domain]) and bool(global_correctness)
        all_pass = gate_valid and all(bool(row["rejectAtFamilywiseAlpha0.05"]) for row in gating_members)
        all_five_pass = gate_valid and all(bool(row["rejectAtFamilywiseAlpha0.05"]) for row in members)
        comparator_advantage = False
        if gate_valid:
            for row in gating_members:
                components = list(row.get("components", {}).values()) or [row.get("component", {})]
                if components and all(float(component["simultaneousTwoSidedBonferroniIntervalModelScale"][0]) > 0.0 for component in components):
                    comparator_advantage = True
                    break
        classification = (
            "MEASUREMENT_INVALID" if not gate_valid else
            "IDFF_ADVANTAGE" if all_pass else
            "COMPARATOR_ADVANTAGE" if comparator_advantage else
            "UNRESOLVED"
        )
        domain_results.append(
            {
                "domainId": domain,
                "valid": gate_valid,
                "classification": classification,
                "idffAdvantageAgainstAllFourDomainGateComparators": all_pass,
                "allFiveComparatorsPassing": all_five_pass,
                "domainGateComparators": list(DOMAIN_GATE_COMPARATORS),
                "comparatorsRequired": 4,
                "comparatorsPassing": sum(bool(row["rejectAtFamilywiseAlpha0.05"]) for row in gating_members),
                "nonGatingComparatorOutcome": non_gating_comparator_summary(non_gating_members[0]),
                "invalidDomainRemovedFromDenominator": False,
            }
        )
    supported = sum(row["classification"] == "IDFF_ADVANTAGE" for row in domain_results)
    primary_pass = bool(global_correctness) and supported >= 4
    return {
        "schema": "gate14re-me-formal-st-confirmatory-results-v1",
        "studyId": STUDY_ID,
        "family": {
            "hypotheses": CONFIRMATORY_HYPOTHESES,
            "primitiveContrasts": CONFIRMATORY_PRIMITIVES,
            "alpha": ALPHA,
            "pValueMultiplicity": "Holm strong FWER over 35 composite hypotheses",
            "intervalMultiplicity": "two-sided Bonferroni simultaneous intervals over 40 primitive contrasts",
            "D1IntersectionUnion": "maximum of geometric-mean and nearest-rank-P95 one-sided p-values",
            "minimumPracticallyImportantEffectRole": "reporting flag only; null boundary unchanged",
            "domainGateComparators": list(DOMAIN_GATE_COMPARATORS),
            "nonGatingComparators": list(NON_GATE_COMPARATORS),
            "domainPassRule": "valid hard gates and all four domain-gating comparator hypotheses pass",
            "nonGatingComparatorReporting": "C-FF remains in the 35-hypothesis Holm family and must be reported with concrete failure data and explanation when not passed",
        },
        "hypotheses": hypotheses,
        "domains": domain_results,
        "primaryClaim": {
            "claimId": "MAJORITY_OF_ENDPOINT_DOMAINS_SUPPORT_IDFF_UNDER_FOUR_COMPARATOR_DOMAIN_RULE",
            "supportedDomains": supported,
            "requiredDomains": 4,
            "denominatorDomains": 7,
            "pass": primary_pass,
            "rankingOrWinnerClaim": False,
            "domainGateComparators": list(DOMAIN_GATE_COMPARATORS),
            "nonGatingComparators": list(NON_GATE_COMPARATORS),
        },
    }


def build_exploratory_results(models: Mapping[str, Mapping[str, Any]], indices: Mapping[str, int]) -> Dict[str, Any]:
    domains: List[Dict[str, Any]] = []
    pairs = list(combinations(ALGORITHMS, 2))
    for domain in DOMAINS:
        rows: List[Dict[str, Any]] = []
        raw_p_values: List[float] = []
        for first, second in pairs:
            if domain == "D1_DYNAMIC_LATENCY":
                vector = algorithm_contrast(indices, first, second)
                geo = contrast(models["D1_GEOMETRIC_MEAN"], vector)
                p95 = contrast(models["D1_NEAREST_RANK_P95"], vector)
                components = {
                    "equalDesignGeometricMeanRatio": transformed_interval_payload(geo, models["D1_GEOMETRIC_MEAN"], 30, True),
                    "equalDesignNearestRankP95Ratio": transformed_interval_payload(p95, models["D1_NEAREST_RANK_P95"], 30, True),
                }
                raw_p = max(float(geo["twoSidedP"]), float(p95["twoSidedP"]))
                row = {"first": first, "second": second, "components": components, "rawCompositeTwoSidedP": raw_p}
            else:
                model_id, axis, ratio_scale = model_for_domain(domain)
                result = contrast(models[model_id], algorithm_contrast(indices, first, second, axis))
                component = transformed_interval_payload(result, models[model_id], 15, ratio_scale)
                raw_p = float(result["twoSidedP"])
                row = {"first": first, "second": second, "component": component, "rawTwoSidedP": raw_p}
            rows.append(row)
            raw_p_values.append(raw_p)
        adjusted = holm_adjust(raw_p_values)
        for row, adjusted_p in zip(rows, adjusted):
            row["exploratoryHolmAdjustedTwoSidedP"] = adjusted_p
        domains.append(
            {
                "domainId": domain,
                "pairCount": 15,
                "pairOrder": "fixed contract cohort order; not performance order",
                "multiplicity": "separate exploratory Holm family within this domain",
                "pairs": rows,
            }
        )
    return {
        "schema": "gate14re-me-formal-st-exploratory-pair-matrices-v1",
        "studyId": STUDY_ID,
        "orderedOrRanked": False,
        "winnerFieldPresent": False,
        "domains": domains,
    }


def build_descriptive_results(lanes: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    endpoints = {
        "D1_GEOMETRIC_MEAN_MILLISECONDS": "d1GeometricMeanMilliseconds",
        "D1_NEAREST_RANK_P95_MILLISECONDS": "d1NearestRankP95Milliseconds",
        "D2_GRID_ACCESSOR_CALLS": "d2GridAccessorCalls",
        "D2_GRID_CONTAINS_CALLS": "d2GridContainsCalls",
        "D2_GRID_IS_WALKABLE_CALLS": "d2GridIsWalkableCalls",
        "D2_GRID_GET_TRAVERSAL_COST_CALLS": "d2GridGetTraversalCostCalls",
        "D3_TOTAL_MANAGED_ALLOCATION_BYTES": "d3TotalManagedAllocationBytes",
        "D4_MAX_PERSISTENT_STATE_BYTES": "d4MaxPersistentStateBytes",
    }
    by_algorithm: List[Dict[str, Any]] = []
    for algorithm in ALGORITHMS:
        selected = [lane for lane in lanes if lane["algorithm"] == algorithm]
        if len(selected) != 1296:
            raise AnalysisError(f"descriptive independent lane count mismatch for {algorithm}: {len(selected)}")
        by_algorithm.append(
            {
                "algorithm": algorithm,
                "independentSuperblocks": 1296,
                "algorithmLanes": 1296,
                "missingLanes": 0,
                "endpoints": {
                    endpoint: describe([float(lane[field]) for lane in selected])
                    for endpoint, field in endpoints.items()
                },
            }
        )
    condition_groups: MutableMapping[Tuple[Any, ...], List[Mapping[str, Any]]] = defaultdict(list)
    for lane in lanes:
        key = (
            lane["algorithm"], lane["gridEdge"], lane["agentCount"], lane["changedCellCount"],
            lane["changeTopology"], lane["graphProfile"], lane["sameTickAtomicPartitions"],
        )
        condition_groups[key].append(lane)
    conditions: List[Dict[str, Any]] = []
    for key in sorted(condition_groups, key=lambda item: (ALGORITHMS.index(item[0]),) + tuple(item[1:])):
        selected = condition_groups[key]
        conditions.append(
            {
                "algorithm": key[0], "gridEdge": key[1], "agentCount": key[2], "changedCellCount": key[3],
                "changeTopology": key[4], "graphProfile": key[5], "sameTickAtomicPartitions": key[6],
                "nSuperblocks": len(selected),
                "endpoints": {endpoint: describe([float(lane[field]) for lane in selected]) for endpoint, field in endpoints.items()},
            }
        )
    return {
        "schema": "gate14re-me-formal-st-descriptive-summaries-v1",
        "studyId": STUDY_ID,
        "independentUnit": "superblock",
        "independentN": 1296,
        "algorithmLaneCount": 7776,
        "missingness": {"missingAlgorithmLanes": 0, "ineligibleAlgorithmLanes": 0},
        "algorithmOrder": "frozen contract cohort order; not a performance ordering",
        "byAlgorithm": by_algorithm,
        "byCompleteDesignCondition": conditions,
    }


def validate_control_ledgers(pq: Any, package_root: Path, tables: Mapping[str, Mapping[str, Any]]) -> Dict[str, Any]:
    failure_path = package_root / str(tables["failures-and-voids"]["typedParquet"]["relativePath"])
    replacement_path = package_root / str(tables["replacement-ledger"]["typedParquet"]["relativePath"])
    failures: List[Dict[str, Any]] = []
    columns = ("recordId", "plannedSuperblockId", "isReplacement", "status", "schema")
    for batch in parquet_batches(pq, failure_path, columns):
        for index in range(len(batch["recordId"])):
            failures.append({name: batch[name][index] for name in columns})
    if len(failures) != 2:
        raise AnalysisError(f"preserved technical failure ledger row count mismatch: {len(failures)}")
    expected_superblocks = {"formal-sb-1241", "formal-sb-1242"}
    if (
        {str(row["plannedSuperblockId"]) for row in failures} != expected_superblocks
        or any(row["isReplacement"] is not False for row in failures)
        or len({str(row["recordId"]) for row in failures}) != 2
    ):
        raise AnalysisError("preserved technical failure rows differ from the authorized recovery evidence")
    replacement_rows = pq.ParquetFile(replacement_path).metadata.num_rows
    if replacement_rows != 0:
        raise AnalysisError(f"replacement ledger is nonempty: {replacement_rows}")
    return {
        "preservedTechnicalFailureRows": 2,
        "preservedTechnicalFailureSuperblocks": sorted(expected_superblocks),
        "preservedTechnicalFailureRecordIds": sorted(str(row["recordId"]) for row in failures),
        "failureResolutionReceiptsValidatedByAcceptance": ["v1", "v2"],
        "replacementRows": 0,
        "replayedAlgorithmLanes": 0,
    }


def fit_all_models(
    lanes: Sequence[Mapping[str, Any]],
    X: np.ndarray,
    columns: Sequence[str],
) -> Dict[str, Dict[str, Any]]:
    clusters = [str(lane["superblockId"]) for lane in lanes]
    outcomes = {
        "D1_GEOMETRIC_MEAN": np.asarray([math.log(float(lane["d1GeometricMeanMilliseconds"])) for lane in lanes]),
        "D1_NEAREST_RANK_P95": np.asarray([math.log(float(lane["d1NearestRankP95Milliseconds"])) for lane in lanes]),
        "D2": np.asarray([math.log(float(lane["d2GridAccessorCalls"])) for lane in lanes]),
        "D3": np.asarray([math.log1p(float(lane["d3TotalManagedAllocationBytes"])) for lane in lanes]),
        "D4": np.asarray([math.log1p(float(lane["d4MaxPersistentStateBytes"])) for lane in lanes]),
    }
    models: Dict[str, Dict[str, Any]] = {}
    for model_id, outcome in outcomes.items():
        if not np.all(np.isfinite(outcome)):
            raise AnalysisError(f"model outcome contains non-finite values: {model_id}")
        models[model_id] = fit_prespecified_model(X, outcome, clusters, columns)
    return models


def build_report(
    confirmatory: Mapping[str, Any],
    hard_gates: Mapping[str, Any],
    models: Mapping[str, Mapping[str, Any]],
) -> str:
    lines = [
        "# Gate14Re-ME formal ST v5 四比较器域规则正式分析报告",
        "",
        "## 分析边界",
        "",
        "本报告仅分析 read-only acceptance attempt-002 所冻结的 attempt-003 采集数据。独立单位为 superblock（N=1296）；7776 条算法 lane、事件组、查询和操作均不被当作独立样本。源数据未修改；本次按用户授权将域通过规则改为 A*-R、BiA*-R、D*L、LPA* 四个门控比较算法全部通过。C-FF 仍保留在正式 35 假设家族内，但不参与域通过门控；其未通过时必须报告具体数据和原因。未运行 MQ、MT，未生成排名、综合分数或赢家字段。",
        "",
        "正式假设家族仍为 7 个域 × IDFF 对 5 个比较算法，共 35 个复合假设；单侧较低为优，Holm 强 FWER α=0.05。D1 每个比较采用几何均值与最近秩 P95 的交并检验（p 值取两者较大值）。40 个原始对比同时报告双侧 Bonferroni 区间。MIPE 仅作实用重要性标记，不改变零假设。",
        "",
        "## 硬门控",
        "",
    ]
    for name, value in hard_gates.items():
        if isinstance(value, bool):
            lines.append(f"- {name}: {'PASS' if value else 'FAIL'}")
    lines += ["", "## 四比较器域判定", "", "| 域 | 有效 | 分类 | 通过门控比较数/4 | C-FF 非门控比较 |", "|---|---:|---|---:|---:|"]
    for row in confirmatory["domains"]:
        cff = row["nonGatingComparatorOutcome"]
        lines.append(
            f"| {row['domainId']} | {'是' if row['valid'] else '否'} | {row['classification']} | "
            f"{row['comparatorsPassing']}/4 | {'通过' if cff['passed'] else '未通过'} |"
        )
    claim = confirmatory["primaryClaim"]
    lines += [
        "",
        "## 新多数判据",
        "",
        f"域通过 = 硬门控有效 AND 对 A*-R、BiA*-R、D*L、LPA* 四个门控比较算法的假设全部通过。支持域为 {claim['supportedDomains']}/7；阈值为至少 4/7。判据状态：{'PASS' if claim['pass'] else 'NOT_PASS'}。这不是算法排名或赢家判定。",
        "",
        "## C-FF 非门控比较结果",
        "",
        "C-FF 不参与域通过计数，但仍保留在 35 个正式复合假设和 Holm 校正家族中。",
        "",
    ]
    for row in confirmatory["domains"]:
        cff = row["nonGatingComparatorOutcome"]
        if cff["passed"]:
            lines.append(f"- {row['domainId']}: C-FF 比较通过。")
        else:
            lines.append(f"- {row['domainId']}: {cff['failureExplanationZhCN']}")
    lines += [
        "",
        "## IDFF–比较算法的确认性结果",
        "",
        "下表保持冻结域与比较算法顺序，不按效果或显著性排序。比率域报告 IDFF/比较算法；斜率域报告 IDFF−比较算法的每轴单位差异。C-FF 行为正式检验结果，但不参与四比较器域门控。",
        "",
        "| 域 | 比较算法 | 估计 | 同时区间 | Holm 调整 p | 方向有利 | 达到 MIPE | 假设通过 |",
        "|---|---|---:|---|---:|---:|---:|---:|",
    ]
    for row in confirmatory["hypotheses"]:
        if "components" in row:
            components = row["components"]
            geo = components["equalDesignGeometricMeanRatio"]
            p95 = components["equalDesignNearestRankP95Ratio"]
            estimate_text = f"GM {geo['ratioEstimate']:.6g}; P95 {p95['ratioEstimate']:.6g}"
            interval_text = (
                f"GM [{geo['simultaneousTwoSidedBonferroniRatioInterval'][0]:.6g}, {geo['simultaneousTwoSidedBonferroniRatioInterval'][1]:.6g}]; "
                f"P95 [{p95['simultaneousTwoSidedBonferroniRatioInterval'][0]:.6g}, {p95['simultaneousTwoSidedBonferroniRatioInterval'][1]:.6g}]"
            )
        else:
            component = row["component"]
            if "ratioEstimate" in component:
                estimate_text = f"{component['ratioEstimate']:.6g}"
                interval_text = f"[{component['simultaneousTwoSidedBonferroniRatioInterval'][0]:.6g}, {component['simultaneousTwoSidedBonferroniRatioInterval'][1]:.6g}]"
            else:
                estimate_text = f"{component['estimateModelScale']:.6g}"
                interval_text = f"[{component['simultaneousTwoSidedBonferroniIntervalModelScale'][0]:.6g}, {component['simultaneousTwoSidedBonferroniIntervalModelScale'][1]:.6g}]"
        lines.append(
            f"| {row['domainId']} | {row['comparator']} | {estimate_text} | {interval_text} | "
            f"{row['holmAdjustedOneSidedP']:.6g} | {'是' if row['directionFavorable'] else '否'} | "
            f"{'是' if row['reachesPrespecifiedMipe'] else '否'} | {'是' if row['rejectAtFamilywiseAlpha0.05'] else '否'} |"
        )
    lines += ["", "## 模型执行状态", ""]
    for model_id, model in models.items():
        lines.append(
            f"- {model_id}: {model['estimator']}; fallback={'yes' if model['fallbackUsed'] else 'no'}; "
            f"n={model['nRows']}; superblocks={model['independentSuperblocks']}"
        )
    lines += [
        "",
        "完整数值、区间、门控、描述性分布和 15 对探索矩阵见同目录 JSON/JSONL 文件。探索矩阵按每个域单独做 Holm 校正，固定顺序展示，不用于排名。",
        "",
    ]
    return "\n".join(lines)


def write_file_manifest(output_root: Path, excluded: Iterable[str]) -> Tuple[Path, str, List[Dict[str, Any]]]:
    excluded_set = set(excluded)
    rows: List[Dict[str, Any]] = []
    for path in sorted((item for item in output_root.rglob("*") if item.is_file()), key=lambda item: item.relative_to(output_root).as_posix()):
        relative = path.relative_to(output_root).as_posix()
        if relative in excluded_set:
            continue
        rows.append(
            {
                "schema": "gate14re-me-formal-st-analysis-file-row-v1",
                "relativePath": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    manifest_path = output_root / "file-manifest.v1.jsonl"
    write_jsonl(manifest_path, rows)
    return manifest_path, sha256_file(manifest_path), rows


def reverify_acceptance_manifest(package_root: Path, file_manifest_sha256: str) -> Dict[str, Any]:
    manifest_path = package_root / "file-manifest.v5.jsonl"
    require_file(manifest_path, file_manifest_sha256, "acceptance file manifest after analysis")
    rows = read_jsonl(manifest_path, "acceptance file manifest after analysis")
    for row in rows:
        path = package_root / str(row["relativePath"])
        if path.stat().st_size != int(row["bytes"]) or sha256_file(path) != str(row["sha256"]):
            raise AnalysisError(f"accepted source package changed during analysis: {row['relativePath']}")
    return {"files": len(rows), "allHashesStillMatch": True, "sourceWriteBack": False}


def self_test() -> Dict[str, Any]:
    if DOMAIN_GATE_COMPARATORS != ("A*-R", "BiA*-R", "D*L", "LPA*") or NON_GATE_COMPARATORS != ("C-FF",):
        raise AnalysisError("four-comparator domain rule self-test failed")
    adjusted = holm_adjust([0.001, 0.01, 0.03])
    if not all(abs(a - b) < 1.0e-12 for a, b in zip(adjusted, [0.003, 0.02, 0.03])):
        raise AnalysisError(f"Holm self-test failed: {adjusted}")
    if nearest_rank(list(range(1, 25)), 0.95) != 23:
        raise AnalysisError("nearest-rank P95 self-test failed")
    if abs(t_cdf(0.0, 10.0) - 0.5) > 1.0e-12 or abs(t_ppf(0.975, 10.0) - 2.2281388519649385) > 1.0e-7:
        raise AnalysisError("Student-t self-test failed")
    rng = np.random.default_rng(20261030)
    clusters = [f"g{group:04d}" for group in range(120) for _ in range(6)]
    X = np.column_stack(
        [
            np.ones(720),
            np.tile([0, 1, 0, 0, 0, 0], 120),
            np.tile([-1, -0.6, -0.2, 0.2, 0.6, 1.0], 120),
        ]
    )
    group_effect = np.repeat(rng.normal(0.0, 0.35, 120), 6)
    y = X @ np.asarray([2.0, -0.2, 0.1]) + group_effect + rng.normal(0.0, 0.1, 720)
    model = fit_random_intercept_reml(X, y, clusters, ["Intercept", "Algorithm", "Axis"])
    if model["fallbackUsed"] or abs(float(model["beta"][1]) + 0.2) > 0.05:
        raise AnalysisError("mixed-effects synthetic self-test failed")
    fallback = fit_cluster_robust(X, y, clusters, ["Intercept", "Algorithm", "Axis"], "synthetic")
    if not fallback["fallbackUsed"] or fallback["degreesFreedom"] != 119.0:
        raise AnalysisError("cluster-robust fallback self-test failed")
    return {
        "schema": "gate14re-me-formal-st-analysis-self-test-v1",
        "status": "PASS_SYNTHETIC_STATISTICAL_SELF_TEST",
        "holm": True,
        "nearestRankP95": True,
        "studentT": True,
        "mixedEffects": True,
        "clusterRobustFallback": True,
        "fourComparatorDomainRule": True,
        "cFFRetainedAsNonGatingFormalComparator": True,
        "formalObservationsRead": False,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--project-root")
    parser.add_argument("--package-root")
    parser.add_argument("--output-root")
    parser.add_argument("--pyarrow-root")
    parser.add_argument("--runtime-manifest")
    parser.add_argument("--runtime-manifest-sha256")
    parser.add_argument("--terminal-final")
    parser.add_argument("--terminal-final-sha256")
    parser.add_argument("--terminal-receipt-sha256")
    parser.add_argument("--acceptance-manifest-sha256")
    parser.add_argument("--file-manifest-sha256")
    parser.add_argument("--schedule")
    parser.add_argument("--schedule-sha256")
    parser.add_argument("--identity-binding")
    parser.add_argument("--identity-binding-sha256")
    parser.add_argument("--analysis-contract")
    parser.add_argument("--analysis-contract-sha256")
    parser.add_argument("--endpoint-contract")
    parser.add_argument("--endpoint-contract-sha256")
    parser.add_argument("--scientific-design")
    parser.add_argument("--scientific-design-sha256")
    parser.add_argument("--authorization-receipt")
    parser.add_argument("--authorization-receipt-sha256")
    parser.add_argument("--execution-contract")
    parser.add_argument("--execution-contract-sha256")
    parser.add_argument("--tool-sha256")
    return parser.parse_args()


def required_path(value: str | None, label: str, directory: bool = False) -> Path:
    if not value:
        raise AnalysisError(f"missing required argument: {label}")
    path = Path(value).resolve(strict=False)
    if directory and not path.is_dir():
        raise AnalysisError(f"missing {label} directory: {path}")
    if not directory and not path.is_file():
        raise AnalysisError(f"missing {label} file: {path}")
    return path


def required_text(value: str | None, label: str) -> str:
    if not value:
        raise AnalysisError(f"missing required argument: {label}")
    return value


def formal_main(args: argparse.Namespace) -> int:
    started_at = utc_now()
    started = time.perf_counter()
    project_root = required_path(args.project_root, "project root", directory=True)
    package_root = required_path(args.package_root, "accepted package root", directory=True)
    output_text = required_text(args.output_root, "output root")
    output_root = Path(output_text).resolve(strict=False)
    if output_root.exists():
        raise AnalysisError(f"output root must be fresh and absent: {output_root}")
    output_root.parent.mkdir(parents=True, exist_ok=True)
    output_root.mkdir(exist_ok=False)
    failure_path = output_root / "failure-receipt.v1.json"
    try:
        tool_sha = required_text(args.tool_sha256, "tool SHA-256").lower()
        require_file(Path(__file__).resolve(), tool_sha, "formal analysis tool")
        runtime_manifest_path = required_path(args.runtime_manifest, "runtime manifest")
        terminal_final_path = required_path(args.terminal_final, "acceptance terminal-final")
        schedule_path = required_path(args.schedule, "formal schedule")
        identity_path = required_path(args.identity_binding, "algorithm identity binding")
        analysis_contract_path = required_path(args.analysis_contract, "analysis contract")
        endpoint_contract_path = required_path(args.endpoint_contract, "endpoint/MIPE contract")
        scientific_design_path = required_path(args.scientific_design, "scientific design")
        authorization_path = required_path(args.authorization_receipt, "analysis authorization receipt")
        execution_contract_path = required_path(args.execution_contract, "analysis execution contract")
        pyarrow_root = required_path(args.pyarrow_root, "PyArrow package root", directory=True)

        bindings = {
            "toolSha256": tool_sha,
            "runtimeManifestSha256": required_text(args.runtime_manifest_sha256, "runtime manifest SHA-256").lower(),
            "acceptanceTerminalFinalSha256": required_text(args.terminal_final_sha256, "terminal-final SHA-256").lower(),
            "acceptanceTerminalReceiptSha256": required_text(args.terminal_receipt_sha256, "terminal receipt SHA-256").lower(),
            "acceptanceManifestSha256": required_text(args.acceptance_manifest_sha256, "acceptance manifest SHA-256").lower(),
            "acceptanceFileManifestSha256": required_text(args.file_manifest_sha256, "file manifest SHA-256").lower(),
            "scheduleSha256": required_text(args.schedule_sha256, "schedule SHA-256").lower(),
            "identityBindingSha256": required_text(args.identity_binding_sha256, "identity binding SHA-256").lower(),
            "analysisContractSha256": required_text(args.analysis_contract_sha256, "analysis contract SHA-256").lower(),
            "endpointContractSha256": required_text(args.endpoint_contract_sha256, "endpoint contract SHA-256").lower(),
            "scientificDesignSha256": required_text(args.scientific_design_sha256, "scientific design SHA-256").lower(),
            "authorizationReceiptSha256": required_text(args.authorization_receipt_sha256, "authorization receipt SHA-256").lower(),
            "executionContractSha256": required_text(args.execution_contract_sha256, "execution contract SHA-256").lower(),
        }
        require_file(runtime_manifest_path, bindings["runtimeManifestSha256"], "frozen PyArrow runtime manifest")
        require_file(analysis_contract_path, bindings["analysisContractSha256"], "frozen analysis contract")
        require_file(endpoint_contract_path, bindings["endpointContractSha256"], "frozen endpoint/MIPE contract")
        require_file(scientific_design_path, bindings["scientificDesignSha256"], "frozen scientific design")
        require_file(authorization_path, bindings["authorizationReceiptSha256"], "analysis authorization receipt")
        require_file(execution_contract_path, bindings["executionContractSha256"], "analysis execution contract")
        analysis_contract = read_json(analysis_contract_path, "frozen analysis contract")
        endpoint_contract = read_json(endpoint_contract_path, "frozen endpoint/MIPE contract")
        scientific_design = read_json(scientific_design_path, "frozen scientific design")
        authorization = read_json(authorization_path, "analysis authorization receipt")
        execution_contract = read_json(execution_contract_path, "analysis execution contract")
        if (
            analysis_contract.get("schema") != "gate14re-me-formal-st-analysis-contract-v5.1-four-comparator-domain-rule"
            or analysis_contract.get("confirmatoryFamily", {}).get("hypotheses") != 35
            or analysis_contract.get("confirmatoryFamily", {}).get("multiplicity") != "Holm strong FWER"
            or tuple(analysis_contract.get("confirmatoryFamily", {}).get("domainGateComparators", [])) != DOMAIN_GATE_COMPARATORS
            or tuple(analysis_contract.get("confirmatoryFamily", {}).get("nonGatingComparators", [])) != NON_GATE_COMPARATORS
            or endpoint_contract.get("ratioThreshold") != 0.9
            or scientific_design.get("design", {}).get("plannedIndependentSuperblocks") != 1296
            or scientific_design.get("primaryClaim", {}).get("minimumSupportedDomains") != 4
        ):
            raise AnalysisError("frozen scientific/analysis contract identity mismatch")
        if (
            authorization.get("status") != "AUTHORIZED_FORMAL_ST_ANALYSIS_ATTEMPT_003_FOUR_COMPARATOR_DOMAIN_RULE"
            or authorization.get("sourceAcceptanceAttempt") != "attempt-002"
            or authorization.get("scope", {}).get("fourComparatorDomainRuleAuthorized") is not True
            or authorization.get("scope", {}).get("cFFFormalNonGatingReportingAuthorized") is not True
            or authorization.get("rankingOrWinnerAuthorized") is not False
            or authorization.get("mqAuthorized") is not False
            or authorization.get("mtAuthorized") is not False
        ):
            raise AnalysisError("analysis authorization scope mismatch")
        if (
            execution_contract.get("status") != "FROZEN_AUTHORIZED_FORMAL_ST_ANALYSIS_ATTEMPT_003_FOUR_COMPARATOR_DOMAIN_RULE"
            or Path(str(execution_contract.get("outputRoot"))).resolve(strict=False) != output_root
            or execution_contract.get("toolSha256") != tool_sha
            or execution_contract.get("authorizationReceiptSha256") != bindings["authorizationReceiptSha256"]
            or execution_contract.get("analysisContractSha256") != bindings["analysisContractSha256"]
        ):
            raise AnalysisError("analysis execution contract binding mismatch")

        runtime_manifest = read_json(runtime_manifest_path, "frozen PyArrow runtime manifest")
        pa, pq, pyarrow_version = import_pyarrow(pyarrow_root)
        if (
            runtime_manifest.get("status") != "FROZEN_TYPED_PARQUET_RUNTIME"
            or pyarrow_version != str(runtime_manifest.get("distribution", {}).get("version"))
        ):
            raise AnalysisError("frozen PyArrow runtime version mismatch")

        terminal, acceptance_manifest, tables = validate_acceptance_package(
            package_root,
            terminal_final_path,
            bindings["acceptanceTerminalFinalSha256"],
            bindings["acceptanceTerminalReceiptSha256"],
            bindings["acceptanceManifestSha256"],
            bindings["acceptanceFileManifestSha256"],
        )
        schedule, lane_map = load_schedule_and_identity(
            schedule_path, bindings["scheduleSha256"], identity_path, bindings["identityBindingSha256"]
        )
        control_ledgers = validate_control_ledgers(pq, package_root, tables)
        table_path = lambda table_id: package_root / str(tables[table_id]["typedParquet"]["relativePath"])
        lanes, d3_links, event_gates = aggregate_event_groups(pq, table_path("event-groups"), lane_map)
        d3_gate = attach_d3_allocations(pq, table_path("d3-windows"), lanes, d3_links)
        d4_gate = attach_persistent_state(pq, table_path("persistent-state"), lanes)
        correctness = validate_operations_and_oracle(
            pq, table_path("operations"), table_path("oracle-event-checks")
        )
        X, fixed_effect_columns, indices, centers = build_design_matrix(lanes)
        models = fit_all_models(lanes, X, fixed_effect_columns)
        domain_gates = {
            "D1_DYNAMIC_LATENCY": bool(event_gates["D1EventGroupValidity"]),
            "D2_GRID_READ_WORK": bool(event_gates["D2GridCounterValidity"]),
            "D3_DYNAMIC_ALLOCATION": bool(d3_gate["D3CounterValidity"]),
            "D4_PERSISTENT_STATE_BYTES": bool(d4_gate["D4SizingFormulaValidity"]),
            "D5_AGENT_COUNT_SCALING": bool(event_gates["D1EventGroupValidity"]),
            "D6_CHANGE_FOOTPRINT_SCALING": bool(event_gates["D1EventGroupValidity"]),
            "D7_GRID_SIZE_SCALING": bool(event_gates["D1EventGroupValidity"]),
        }
        confirmatory = build_confirmatory_results(models, indices, domain_gates, bool(correctness["correctnessOracle"]))
        exploratory = build_exploratory_results(models, indices)
        descriptive = build_descriptive_results(lanes)
        source_reverification = reverify_acceptance_manifest(package_root, bindings["acceptanceFileManifestSha256"])
        hard_gates = {
            "completeAcceptedDelivery": True,
            "sourcePackageUnchangedDuringAnalysis": source_reverification["allHashesStillMatch"],
            "correctnessOracle": bool(correctness["correctnessOracle"]),
            "D1MeasurementValidity": domain_gates["D1_DYNAMIC_LATENCY"],
            "D2CounterValidity": domain_gates["D2_GRID_READ_WORK"],
            "D3CounterValidity": domain_gates["D3_DYNAMIC_ALLOCATION"],
            "D4SizingFormulaValidity": domain_gates["D4_PERSISTENT_STATE_BYTES"],
            "preservedFailureResolutionCompatibility": control_ledgers["preservedTechnicalFailureRows"] == 2,
            "zeroReplacement": control_ledgers["replacementRows"] == 0,
        }
        input_audit = {
            "schema": "gate14re-me-formal-st-analysis-input-audit-v1",
            "studyId": STUDY_ID,
            "status": "PASS_FROZEN_ACCEPTANCE_INPUT_AUDIT",
            "sourceAcceptanceAttempt": "attempt-002",
            "sourceAcquisitionAttempt": "attempt-003",
            "analysisAttempt": "attempt-003",
            "domainGateComparators": list(DOMAIN_GATE_COMPARATORS),
            "nonGatingComparators": list(NON_GATE_COMPARATORS),
            "bindings": bindings,
            "acceptanceTerminalStatus": terminal["status"],
            "acceptanceManifestStatus": acceptance_manifest["status"],
            "tableRowCounts": acceptance_manifest["tableRowCounts"],
            "scheduleRows": len(schedule),
            "scheduledAlgorithmLanes": len(lane_map),
            "controlLedgers": control_ledgers,
            "eventGroupValidation": event_gates,
            "d3Validation": d3_gate,
            "d4Validation": d4_gate,
            "correctnessValidation": correctness,
            "sourcePackageReverification": source_reverification,
            "sourceRootsModified": False,
        }
        lane_rows = [
            {
                "schema": "gate14re-me-formal-st-lane-estimand-v1",
                "superblockId": lane["superblockId"],
                "anonymousLaneId": lane["anonymousLaneId"],
                "algorithm": lane["algorithm"],
                "executionPosition": lane["executionPosition"],
                "scheduleOrdinal": lane["scheduleOrdinal"],
                "gridEdge": lane["gridEdge"],
                "agentCount": lane["agentCount"],
                "changedCellCount": lane["changedCellCount"],
                "changeTopology": lane["changeTopology"],
                "graphProfile": lane["graphProfile"],
                "sameTickAtomicPartitions": lane["sameTickAtomicPartitions"],
                "contextStratumId": lane["contextStratumId"],
                "d1GeometricMeanMilliseconds": lane["d1GeometricMeanMilliseconds"],
                "d1NearestRankP95Milliseconds": lane["d1NearestRankP95Milliseconds"],
                "d2GridAccessorCalls": lane["d2GridAccessorCalls"],
                "d2GridContainsCalls": lane["d2GridContainsCalls"],
                "d2GridIsWalkableCalls": lane["d2GridIsWalkableCalls"],
                "d2GridGetTraversalCostCalls": lane["d2GridGetTraversalCostCalls"],
                "d3TotalManagedAllocationBytes": lane["d3TotalManagedAllocationBytes"],
                "d4MaxPersistentStateBytes": lane["d4MaxPersistentStateBytes"],
                "independentUnit": False,
            }
            for lane in lanes
        ]
        model_diagnostics = {
            "schema": "gate14re-me-formal-st-model-diagnostics-v1",
            "studyId": STUDY_ID,
            "fixedEffectColumns": fixed_effect_columns,
            "axisCenters": centers,
            "executionPositionCoding": "categorical with position 0 reference",
            "algorithmReference": TARGET,
            "models": {model_id: strip_model_arrays(model) for model_id, model in models.items()},
            "modelSelectionByPValueDirectionOrWinner": False,
        }

        write_json(output_root / "analysis-input-audit.v1.json", input_audit)
        write_json(output_root / "hard-gates.v1.json", {"schema": "gate14re-me-formal-st-hard-gates-v1", **hard_gates})
        write_jsonl(output_root / "lane-estimands.v1.jsonl", lane_rows)
        write_json(output_root / "descriptive-summaries.v1.json", descriptive)
        write_json(output_root / "model-fit-diagnostics.v1.json", model_diagnostics)
        write_json(output_root / "confirmatory-results.v1.json", confirmatory)
        write_json(output_root / "exploratory-pair-matrices.v1.json", exploratory)
        report_text = build_report(confirmatory, hard_gates, models)
        atomic_write_text(output_root / "formal-st-analysis-report.zh-CN.v1.md", report_text)
        canonical_tree = [
            {"schema": "gate14re-me-formal-st-analysis-canonical-node-v1", "path": "input/acceptance-attempt-002", "sha256": bindings["acceptanceTerminalFinalSha256"]},
            {"schema": "gate14re-me-formal-st-analysis-canonical-node-v1", "path": "contract/analysis-v5.1-four-comparator-domain-rule", "sha256": bindings["analysisContractSha256"]},
            {"schema": "gate14re-me-formal-st-analysis-canonical-node-v1", "path": "contract/endpoint-mipe-v5.0", "sha256": bindings["endpointContractSha256"]},
            {"schema": "gate14re-me-formal-st-analysis-canonical-node-v1", "path": "result/confirmatory", "sha256": sha256_file(output_root / "confirmatory-results.v1.json")},
            {"schema": "gate14re-me-formal-st-analysis-canonical-node-v1", "path": "result/exploratory", "sha256": sha256_file(output_root / "exploratory-pair-matrices.v1.json")},
        ]
        write_jsonl(output_root / "analysis-canonical-tree.v1.jsonl", canonical_tree)
        analysis_manifest = {
            "schema": "gate14re-me-formal-st-analysis-manifest-v1",
            "studyId": STUDY_ID,
            "status": "PASS_FORMAL_ST_FOUR_COMPARATOR_DOMAIN_RULE_ANALYSIS_EXECUTED",
            "analysisAttempt": "attempt-003",
            "sourceAcceptanceAttempt": "attempt-002",
            "sourceAcquisitionAttempt": "attempt-003",
            "independentUnit": "superblock",
            "independentN": 1296,
            "algorithmLanes": 7776,
            "confirmatoryHypotheses": 35,
            "confirmatoryPrimitiveContrasts": 40,
            "bindings": bindings,
            "hardGates": hard_gates,
            "primaryClaim": confirmatory["primaryClaim"],
            "modelFallbacks": {model_id: bool(model["fallbackUsed"]) for model_id, model in models.items()},
            "boundaries": {
                "sourceRootsModified": False,
                "scientificDesignModified": True,
                "domainAggregationRuleModified": True,
                "domainGateComparators": list(DOMAIN_GATE_COMPARATORS),
                "nonGatingComparators": list(NON_GATE_COMPARATORS),
                "formalAnalysisPerformed": True,
                "rankingOrWinnerComputed": False,
                "aggregateScoreComputed": False,
                "mqPerformed": False,
                "mtPerformed": False,
            },
            "startedAtUtc": started_at,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
        }
        manifest_path = output_root / "analysis-manifest.v1.json"
        write_json(manifest_path, analysis_manifest)
        manifest_sha = sha256_file(manifest_path)
        file_manifest_path, file_manifest_sha, file_rows = write_file_manifest(
            output_root, excluded={"file-manifest.v1.jsonl", "analysis-terminal-receipt.v1.json", "failure-receipt.v1.json"}
        )
        terminal_receipt = {
            "schema": "gate14re-me-formal-st-analysis-terminal-receipt-v1",
            "studyId": STUDY_ID,
            "status": "PASS_FORMAL_ST_FOUR_COMPARATOR_DOMAIN_RULE_ANALYSIS",
            "analysisAttempt": "attempt-003",
            "analysisManifestRelativePath": manifest_path.relative_to(output_root).as_posix(),
            "analysisManifestSha256": manifest_sha,
            "fileManifestRelativePath": file_manifest_path.relative_to(output_root).as_posix(),
            "fileManifestSha256": file_manifest_sha,
            "fileManifestRows": len(file_rows),
            "primaryClaim": confirmatory["primaryClaim"],
            "sourceAcceptanceAttempt": "attempt-002",
            "sourceAcquisitionAttempt": "attempt-003",
            "sourceRootsModified": False,
            "rankingOrWinnerComputed": False,
            "mqPerformed": False,
            "mtPerformed": False,
            "completedAtUtc": utc_now(),
        }
        terminal_path = output_root / "analysis-terminal-receipt.v1.json"
        write_json(terminal_path, terminal_receipt)
        print(canonical_json(terminal_receipt))
        return 0
    except Exception as exc:
        failure = {
            "schema": "gate14re-me-formal-st-analysis-failure-receipt-v1",
            "studyId": STUDY_ID,
            "status": "FAIL_CLOSED_FORMAL_ST_ANALYSIS",
            "errorType": type(exc).__name__,
            "error": str(exc),
            "sourceRootsModified": False,
            "retryPerformed": False,
            "rankingOrWinnerComputed": False,
            "mqPerformed": False,
            "mtPerformed": False,
            "createdAtUtc": utc_now(),
        }
        if not failure_path.exists():
            write_json(failure_path, failure)
        print(canonical_json(failure), file=sys.stderr)
        return 1


def main() -> int:
    args = parse_args()
    if args.self_test:
        print(canonical_json(self_test()))
        return 0
    try:
        return formal_main(args)
    except Exception as exc:
        print(canonical_json({"status": "FAIL_CLOSED_BEFORE_OUTPUT_ROOT", "errorType": type(exc).__name__, "error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())





