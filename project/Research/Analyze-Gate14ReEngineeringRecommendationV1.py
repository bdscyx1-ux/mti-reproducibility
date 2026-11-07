#!/usr/bin/env python3
"""Gate 14Re read-only anonymous engineering recommendation analysis.

This is a post-hoc, decision-oriented analysis of the already immutable Gate
14Re Phase A raw data.  It never changes the original raw root or the formal
Phase B result.  Scientific and decision rules are frozen in a separate
contract before this program is allowed to parse formal block outputs.

Modes:

* ``--prepare-custody`` creates a randomized DPAPI CurrentUser label mapping
  without persisting the plaintext mapping;
* ``--self-test`` runs pure-synthetic known-answer checks;
* ``--formal`` verifies the immutable raw tree and creates one anonymous
  pre-adjudication root without overwrite;
* ``--verify-existing`` recomputes anonymous payloads in memory and compares
  them with the committed root.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
from ctypes import wintypes
import datetime as dt
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import statistics
import sys
import traceback
import uuid
from collections import defaultdict
from typing import Any, Mapping, Sequence


SCHEMA = "gate14re-engineering-recommendation-analyzer-v1"
PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parents[1]
SOURCE_LABELS = ("A", "B", "C", "D")
ANONYMOUS_LABELS = ("U17", "U29", "U43", "U61")
CONDITIONS = tuple(f"C{i:02d}" for i in range(1, 9))
ANCHORS = ("C01", "C07")
PAIR_FAMILY = (("A", "B"), ("A", "C"), ("A", "D"), ("B", "C"), ("B", "D"), ("C", "D"))
TICK_SECONDS = 0.02
CAP_TICKS = 9000

REL = {
    "contract": "Research/Gate14Re/EngineeringRecommendation/Gate14Re_Engineering_Recommendation_Contract.v1.json",
    "authorization": "Research/Gate14Re/EngineeringRecommendation/Gate14Re_Engineering_Recommendation_Authorization.v1.json",
    "custody_root": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1",
    "custody_commitment": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody-commitment.v1.json",
    "custody_payload": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody.payload.dpapi.bin",
    "custody_entropy": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody.entropy.v1.bin",
    "phaseb_analyzer": "Research/Analyze-Gate14ReFormalPhaseBV1.py",
    "phaseb_receipt": "Research/Analysis/Gate14Re/PhaseB/attempt-001/analysis-receipt.v1.json",
    "phaseb_tree": "Research/Analysis/Gate14Re/PhaseB/attempt-001/analysis-canonical-tree.v1.jsonl",
    "phaseb_eligibility": "Research/Analysis/Gate14Re/PhaseB/attempt-001/eligibility.json",
    "phaseb_winner": "Research/Analysis/Gate14Re/PhaseB/attempt-001/winner-adjudication.json",
    "status": "Research/Gate14Re/Gate14Re_Status.v6.json",
    "analysis_root": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001",
    "readiness": "Research/Verification/Gate14Re/engineering-recommendation-readiness-attempt-001/final-readiness.v1.json",
    "verification_root": "Research/Verification/Gate14Re/engineering-recommendation-readiness-attempt-001",
}

FORBIDDEN_IDENTITIES = ("A*-R", "D*L", "C-FF", "IDFF")
CRYPTPROTECT_UI_FORBIDDEN = 0x1


class AnalysisError(RuntimeError):
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
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any, *, pretty: bool = True) -> bytes:
    if pretty:
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
    else:
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"
    return text.encode("utf-8")


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


def finite(value: Any, code: str) -> float:
    require(isinstance(value, (int, float)) and not isinstance(value, bool), code)
    number = float(value)
    require(math.isfinite(number), code)
    return number


def verify_hash(path: Path, expected: str, code: str, *, read_only: bool = False) -> None:
    require(path.is_file(), f"{code}_MISSING", str(path))
    require(sha256_file(path) == expected, f"{code}_HASH_MISMATCH", str(path))
    if read_only:
        require(is_read_only(path), f"{code}_NOT_READONLY", str(path))


def import_phaseb(project_root: Path) -> Any:
    path = project_root / REL["phaseb_analyzer"]
    spec = importlib.util.spec_from_file_location("gate14re_phaseb_frozen", path)
    require(spec is not None and spec.loader is not None, "PHASEB_IMPORT_SPEC")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------------------------
# DPAPI label custody.
# ---------------------------------------------------------------------------


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_ubyte))]


def _blob(data: bytes) -> tuple[DATA_BLOB, Any]:
    buffer = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    return DATA_BLOB(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte))), buffer


def protect(data: bytes, entropy: bytes) -> bytes:
    crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    input_blob, input_buffer = _blob(data)
    entropy_blob, entropy_buffer = _blob(entropy)
    output_blob = DATA_BLOB()
    crypt32.CryptProtectData.argtypes = [ctypes.POINTER(DATA_BLOB), wintypes.LPCWSTR, ctypes.POINTER(DATA_BLOB), ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(DATA_BLOB)]
    crypt32.CryptProtectData.restype = wintypes.BOOL
    ok = crypt32.CryptProtectData(ctypes.byref(input_blob), "Gate14Re engineering recommendation label custody v1", ctypes.byref(entropy_blob), None, None, CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(output_blob))
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(output_blob.pbData, output_blob.cbData)
    finally:
        kernel32.LocalFree(output_blob.pbData)
        for index in range(len(input_buffer)):
            input_buffer[index] = 0
        for index in range(len(entropy_buffer)):
            entropy_buffer[index] = 0


def unprotect(data: bytes, entropy: bytes) -> bytes:
    crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    input_blob, input_buffer = _blob(data)
    entropy_blob, entropy_buffer = _blob(entropy)
    output_blob = DATA_BLOB()
    description = wintypes.LPWSTR()
    crypt32.CryptUnprotectData.argtypes = [ctypes.POINTER(DATA_BLOB), ctypes.POINTER(wintypes.LPWSTR), ctypes.POINTER(DATA_BLOB), ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(DATA_BLOB)]
    crypt32.CryptUnprotectData.restype = wintypes.BOOL
    ok = crypt32.CryptUnprotectData(ctypes.byref(input_blob), ctypes.byref(description), ctypes.byref(entropy_blob), None, None, CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(output_blob))
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(output_blob.pbData, output_blob.cbData)
    finally:
        if description:
            kernel32.LocalFree(description)
        kernel32.LocalFree(output_blob.pbData)
        for index in range(len(input_buffer)):
            input_buffer[index] = 0
        for index in range(len(entropy_buffer)):
            entropy_buffer[index] = 0


def prepare_custody(project_root: Path) -> dict[str, Any]:
    root = project_root / REL["custody_root"]
    require(not root.exists(), "CUSTODY_ROOT_ALREADY_EXISTS", str(root))
    root.mkdir(parents=True, exist_ok=False)
    shuffled = list(ANONYMOUS_LABELS)
    secrets.SystemRandom().shuffle(shuffled)
    custody_id = "gate14re-engineering-recommendation-v1-" + str(uuid.uuid4())
    secret = {
        "schema": "gate14re-engineering-recommendation-label-secret-v1",
        "studyId": "Gate14Re",
        "custodyId": custody_id,
        "mapping": [
            {"sourceLabel": source, "anonymousLabel": anonymous}
            for source, anonymous in zip(SOURCE_LABELS, shuffled, strict=True)
        ],
    }
    plaintext = bytearray(canonical_json_bytes(secret, pretty=False).rstrip(b"\n"))
    commitment = hashlib.sha256(plaintext).hexdigest()
    entropy = secrets.token_bytes(32)
    protected = protect(bytes(plaintext), entropy)
    for index in range(len(plaintext)):
        plaintext[index] = 0
    payload_path = project_root / REL["custody_payload"]
    entropy_path = project_root / REL["custody_entropy"]
    atomic_create(payload_path, protected)
    atomic_create(entropy_path, entropy)
    record = {
        "schema": "gate14re-engineering-recommendation-label-custody-commitment-v1",
        "studyId": "Gate14Re",
        "status": "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED",
        "custodyId": custody_id,
        "anonymousLabels": list(ANONYMOUS_LABELS),
        "sourceLabelCount": 4,
        "mappingCommitmentSha256": commitment,
        "protection": {
            "mechanism": "Windows DPAPI CryptProtectData",
            "scope": "CurrentUser on this host account",
            "uiForbidden": True,
            "payloadRelativePath": REL["custody_payload"],
            "payloadSha256": hashlib.sha256(protected).hexdigest(),
            "entropyRelativePath": REL["custody_entropy"],
            "entropySha256": hashlib.sha256(entropy).hexdigest(),
        },
        "plaintextMappingPersisted": False,
        "mappingReleased": False,
        "unblindingAuthorized": False,
        "proceduralBoundary": "DPAPI prevents ordinary inspection and accidental analysis-time disclosure; it is not an independent-human double-blind guarantee.",
    }
    commitment_path = project_root / REL["custody_commitment"]
    write_json(commitment_path, record)
    for path in (payload_path, entropy_path, commitment_path):
        set_read_only(path)
    return {"status": "PASS", "custodyId": custody_id, "mappingPersisted": False}


def load_mapping(project_root: Path, contract: Mapping[str, Any]) -> tuple[dict[str, str], dict[str, Any]]:
    commitment_path = project_root / REL["custody_commitment"]
    payload_path = project_root / REL["custody_payload"]
    entropy_path = project_root / REL["custody_entropy"]
    binding = contract["labelCustody"]
    verify_hash(commitment_path, binding["commitmentSha256"], "CUSTODY_COMMITMENT", read_only=True)
    verify_hash(payload_path, binding["payloadSha256"], "CUSTODY_PAYLOAD", read_only=True)
    verify_hash(entropy_path, binding["entropySha256"], "CUSTODY_ENTROPY", read_only=True)
    commitment = load_json(commitment_path)
    require(commitment.get("status") == "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED", "CUSTODY_STATUS")
    require(commitment.get("mappingReleased") is False and commitment.get("unblindingAuthorized") is False, "CUSTODY_RELEASE_BOUNDARY")
    plaintext = bytearray(unprotect(payload_path.read_bytes(), entropy_path.read_bytes()))
    try:
        require(hashlib.sha256(plaintext).hexdigest() == commitment["mappingCommitmentSha256"], "CUSTODY_PLAINTEXT_COMMITMENT")
        secret = json.loads(plaintext.decode("utf-8"))
    finally:
        for index in range(len(plaintext)):
            plaintext[index] = 0
    require(secret.get("custodyId") == commitment.get("custodyId"), "CUSTODY_ID_MISMATCH")
    rows = secret.get("mapping")
    require(isinstance(rows, list) and len(rows) == 4, "CUSTODY_MAPPING_COUNT")
    mapping = {str(row["sourceLabel"]): str(row["anonymousLabel"]) for row in rows}
    require(set(mapping) == set(SOURCE_LABELS), "CUSTODY_SOURCE_SET")
    require(set(mapping.values()) == set(ANONYMOUS_LABELS), "CUSTODY_ANONYMOUS_SET")
    return mapping, commitment


# ---------------------------------------------------------------------------
# Endpoint derivation and statistics.
# ---------------------------------------------------------------------------


def nearest_rank(sorted_values: Sequence[int], probability: float) -> int:
    require(bool(sorted_values) and 0.0 < probability <= 1.0, "INVALID_NEAREST_RANK_INPUT")
    index = max(1, math.ceil(probability * len(sorted_values))) - 1
    return int(sorted_values[index])


def movement_endpoints(sample: Mapping[str, Any]) -> dict[str, float]:
    units = sample.get("units")
    unit_count = int(sample.get("unitCount"))
    require(isinstance(units, list) and len(units) == unit_count, "MOVEMENT_UNIT_COUNT")
    agent_ids: set[int] = set()
    ticks: list[int] = []
    for unit in units:
        agent_id = int(unit.get("agentId"))
        require(agent_id not in agent_ids, "DUPLICATE_AGENT_ID")
        agent_ids.add(agent_id)
        if unit.get("arrived") is True:
            arrival = int(unit.get("arrivalTick"))
            require(0 <= arrival <= CAP_TICKS, "ARRIVAL_TICK_RANGE")
            ticks.append(arrival)
        else:
            ticks.append(CAP_TICKS)
    ordered = sorted(ticks)
    t50 = nearest_rank(ordered, 0.50)
    t95 = nearest_rank(ordered, 0.95)
    t99 = nearest_rank(ordered, 0.99)
    t100 = ordered[-1]
    return {
        "RMAT180Seconds": TICK_SECONDS * statistics.fmean(ordered),
        "T95Seconds": TICK_SECONDS * t95,
        "T99Seconds": TICK_SECONDS * t99,
        "T100MinusT50Seconds": TICK_SECONDS * (t100 - t50),
        "originalM1Seconds": finite(sample.get("m1Seconds"), "INVALID_ORIGINAL_M1"),
    }


def stratified_difference_statistics(phaseb: Any, strata: Mapping[str, Sequence[float]]) -> dict[str, Any]:
    require(set(strata) == set(CONDITIONS), "DIFFERENCE_STRATA_SET")
    require(all(len(strata[name]) == 48 for name in CONDITIONS), "DIFFERENCE_STRATUM_N")
    means = {name: statistics.fmean(strata[name]) for name in CONDITIONS}
    estimate = statistics.fmean(means.values())
    count = float(len(CONDITIONS))
    parts = [(statistics.variance(strata[name]) / len(strata[name])) / (count * count) for name in CONDITIONS]
    total_variance = sum(parts)
    if total_variance <= 0:
        se = 0.0
        df = float("inf")
        statistic_value = 0.0 if estimate == 0 else math.copysign(float("inf"), estimate)
        pvalue = 1.0 if estimate == 0 else 0.0
        ordinary = [estimate, estimate]
        simultaneous = [estimate, estimate]
    else:
        se = math.sqrt(total_variance)
        denominator = sum((part * part) / 47.0 for part in parts)
        df = (total_variance * total_variance) / denominator if denominator > 0 else float("inf")
        statistic_value = estimate / se
        pvalue = phaseb.two_sided_t_pvalue(statistic_value, df)
        ordinary_critical = phaseb.t_ppf(0.975, df)
        simultaneous_critical = phaseb.t_ppf(1.0 - 0.05 / (2.0 * 6.0), df)
        ordinary = [estimate - ordinary_critical * se, estimate + ordinary_critical * se]
        simultaneous = [estimate - simultaneous_critical * se, estimate + simultaneous_critical * se]
    if abs(estimate) <= 1.0e-12:
        direction = "EXACT_POINT_EQUALITY"
    elif estimate < 0:
        direction = "FIRST_LOWER_POINT_ESTIMATE"
    else:
        direction = "SECOND_LOWER_POINT_ESTIMATE"
    if simultaneous[1] < 0:
        simultaneous_relation = "FIRST_LOWER_SIMULTANEOUS_INTERVAL"
    elif simultaneous[0] > 0:
        simultaneous_relation = "SECOND_LOWER_SIMULTANEOUS_INTERVAL"
    else:
        simultaneous_relation = "DIRECTION_UNCERTAIN_AT_SIMULTANEOUS_95_PERCENT"
    return {
        "differenceEstimateSeconds": estimate,
        "standardErrorSeconds": se,
        "degreesOfFreedom": None if not math.isfinite(df) else df,
        "tStatistic": None if not math.isfinite(statistic_value) else statistic_value,
        "unadjustedTwoSidedP": pvalue,
        "ordinary95DifferenceCISeconds": ordinary,
        "simultaneous95DifferenceCISeconds": simultaneous,
        "pointDirection": direction,
        "simultaneousRelation": simultaneous_relation,
        "totalIndependentBlocks": 384,
        "conditionMeansSeconds": means,
    }


def equal_condition_arithmetic(values: Mapping[str, Sequence[float]]) -> float:
    require(set(values) == set(CONDITIONS), "ARITHMETIC_CONDITION_SET")
    return statistics.fmean(statistics.fmean(values[c]) for c in CONDITIONS)


def equal_condition_geometric(values: Mapping[str, Sequence[float]]) -> float:
    require(set(values) == set(CONDITIONS), "GEOMETRIC_CONDITION_SET")
    means: list[float] = []
    for condition in CONDITIONS:
        rows = list(values[condition])
        require(rows and all(math.isfinite(x) and x > 0 for x in rows), "NONPOSITIVE_GEOMETRIC_INPUT")
        means.append(statistics.fmean(math.log(x) for x in rows))
    return math.exp(statistics.fmean(means))


def rank_scalars(values: Mapping[str, float]) -> dict[str, int]:
    ordered = sorted(values, key=lambda label: (float(values[label]), label))
    ranks: dict[str, int] = {}
    previous_value: float | None = None
    previous_rank = 0
    for index, label in enumerate(ordered, 1):
        value = float(values[label])
        if previous_value is not None and math.isclose(value, previous_value, rel_tol=0.0, abs_tol=1.0e-12):
            ranks[label] = previous_rank
        else:
            ranks[label] = index
            previous_rank = index
            previous_value = value
    return ranks


def rank_tuples(values: Mapping[str, Sequence[float]]) -> dict[str, int]:
    def normalized(label: str) -> tuple[float, ...]:
        return tuple(float(x) for x in values[label])
    ordered = sorted(values, key=lambda label: (normalized(label), label))
    ranks: dict[str, int] = {}
    previous: tuple[float, ...] | None = None
    previous_rank = 0
    for index, label in enumerate(ordered, 1):
        current = normalized(label)
        equal = previous is not None and len(current) == len(previous) and all(math.isclose(a, b, rel_tol=0.0, abs_tol=1.0e-12) for a, b in zip(current, previous))
        if equal:
            ranks[label] = previous_rank
        else:
            ranks[label] = index
            previous_rank = index
            previous = current
    return ranks


def strip_identity_fields(value: Any, mapping: Mapping[str, str]) -> Any:
    if isinstance(value, list):
        return [strip_identity_fields(item, mapping) for item in value]
    if not isinstance(value, dict):
        return value
    out: dict[str, Any] = {}
    for key, item in value.items():
        if key in {"productionAlgorithmId", "firstProductionAlgorithm", "secondProductionAlgorithm", "eligibleProductionAlgorithms", "retainedCandidateProductionAlgorithms", "winnerProductionAlgorithmId"}:
            continue
        if key == "pair" and isinstance(item, str) and "/" in item:
            first, second = item.split("/", 1)
            require(first in mapping and second in mapping, "PAIR_LABEL_NOT_IN_CUSTODY")
            out["anonymousPair"] = f"{mapping[first]}/{mapping[second]}"
            continue
        if key in {"algorithmLabel", "firstAlgorithm", "secondAlgorithm", "winnerAlgorithm"} and isinstance(item, str) and item in mapping:
            replacement = {
                "algorithmLabel": "anonymousLabel",
                "firstAlgorithm": "firstAnonymousLabel",
                "secondAlgorithm": "secondAnonymousLabel",
                "winnerAlgorithm": "recommendedAnonymousLabel",
            }[key]
            out[replacement] = mapping[item]
        else:
            out[key] = strip_identity_fields(item, mapping)
    return out


def ensure_anonymous(value: Any) -> None:
    def walk(item: Any, path: str) -> None:
        if isinstance(item, dict):
            for key, child in item.items():
                require("productionalgorithm" not in key.lower(), "IDENTITY_KEY_LEAK", path + "/" + key)
                walk(child, path + "/" + key)
        elif isinstance(item, list):
            for index, child in enumerate(item):
                walk(child, path + f"/{index}")
        elif isinstance(item, str):
            require(item not in FORBIDDEN_IDENTITIES, "PRODUCTION_IDENTITY_LEAK", path)
            require(item not in SOURCE_LABELS, "SOURCE_LABEL_LEAK", path)
    walk(value, "$")


def compute_static_metrics(path: Path) -> dict[str, int]:
    source = path.read_text(encoding="utf-8-sig")
    without_blocks = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    logical_lines: list[str] = []
    for line in without_blocks.splitlines():
        cleaned = re.sub(r"//.*$", "", line).strip()
        if cleaned:
            logical_lines.append(cleaned)
    code = "\n".join(logical_lines)
    branch_tokens = len(re.findall(r"\b(?:if|for|foreach|while|switch|case|catch)\b|&&|\|\|", code))
    allocation_sites = len(re.findall(r"\bnew\s+[A-Za-z_]", code))
    public_surface = len(re.findall(r"\bpublic\b", code))
    return {
        "logicalSourceLines": len(logical_lines),
        "branchTokens": branch_tokens,
        "allocationSites": allocation_sites,
        "publicSurfaceTokens": public_surface,
        "sourceBytes": path.stat().st_size,
    }


def compute_outputs(project_root: Path, phaseb: Any, blocks: Sequence[Mapping[str, Any]], mapping: Mapping[str, str], contract: Mapping[str, Any]) -> dict[str, Any]:
    movement = phaseb.main_blocks(blocks, "movement")
    m4_blocks = phaseb.main_blocks(blocks, "m4")
    eligibility_raw = phaseb.evaluate_eligibility(blocks)
    eligible = list(eligibility_raw["eligibleAlgorithms"])

    endpoint_values: dict[str, dict[str, dict[str, list[float]]]] = {
        metric: {label: {condition: [] for condition in CONDITIONS} for label in SOURCE_LABELS}
        for metric in ("RMAT180Seconds", "T95Seconds", "T99Seconds", "T100MinusT50Seconds", "originalM1Seconds")
    }
    endpoint_by_block: dict[str, dict[str, dict[str, float]]] = {}
    for block in movement:
        samples = phaseb.sample_map(block)
        condition = str(block["conditionId"])
        per_algorithm: dict[str, dict[str, float]] = {}
        for label in SOURCE_LABELS:
            derived = movement_endpoints(samples[label])
            per_algorithm[label] = derived
            for metric, value in derived.items():
                endpoint_values[metric][label][condition].append(value)
        endpoint_by_block[str(block["blockId"])] = per_algorithm

    endpoint_aggregates: dict[str, dict[str, float]] = {
        metric: {label: equal_condition_arithmetic(endpoint_values[metric][label]) for label in SOURCE_LABELS}
        for metric in endpoint_values
    }
    movement_tuples = {
        label: (
            endpoint_aggregates["RMAT180Seconds"][label],
            endpoint_aggregates["T95Seconds"][label],
            endpoint_aggregates["T99Seconds"][label],
            endpoint_aggregates["T100MinusT50Seconds"][label],
            endpoint_aggregates["originalM1Seconds"][label],
        )
        for label in eligible
    }
    movement_ranks = rank_tuples(movement_tuples) if eligible else {}

    rmat_pairs: list[dict[str, Any]] = []
    for first, second in PAIR_FAMILY:
        strata: dict[str, list[float]] = {condition: [] for condition in CONDITIONS}
        for block in movement:
            condition = str(block["conditionId"])
            rows = endpoint_by_block[str(block["blockId"])]
            strata[condition].append(rows[first]["RMAT180Seconds"] - rows[second]["RMAT180Seconds"])
        stats = stratified_difference_statistics(phaseb, strata)
        stats.update({"firstAnonymousLabel": mapping[first], "secondAnonymousLabel": mapping[second]})
        rmat_pairs.append(stats)
    adjusted = phaseb.holm_adjust([float(row["unadjustedTwoSidedP"]) for row in rmat_pairs])
    for row, pvalue in zip(rmat_pairs, adjusted):
        row["holmAdjustedTwoSidedP"] = pvalue

    eligibility = {
        "schema": "gate14re-engineering-recommendation-anonymous-eligibility-v1",
        "source": "recomputed frozen Gate14Re Phase B eligibility rules",
        "anonymousAlgorithms": [],
    }
    for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item]):
        summary = eligibility_raw["summary"][label]
        eligibility["anonymousAlgorithms"].append({
            "anonymousLabel": mapping[label],
            "M3Pass": bool(summary["M3Pass"]),
            "M4Pass": bool(summary["M4Pass"]),
            "M5Pass": bool(summary["M5Pass"]),
            "eligible": bool(summary["eligible"]),
        })
    eligibility["eligibleAnonymousLabels"] = sorted(mapping[label] for label in eligible)

    movement_output = {
        "schema": "gate14re-engineering-recommendation-anonymous-movement-v1",
        "status": "POST_HOC_EXPLORATORY_NOT_CONFIRMATORY",
        "independentUnit": "complete input block",
        "agentsAreWithinBlockSubsamples": True,
        "scope": {"conditions": list(CONDITIONS), "unitCount": 128, "blocksPerCondition": 48},
        "endpointDefinitions": {
            "RMAT180Seconds": "0.02 * mean(min(arrivalTick, 9000)); non-arrivals assigned 9000 ticks",
            "T95Seconds": "nearest-rank 95th percentile of the same censored per-agent ticks",
            "T99Seconds": "nearest-rank 99th percentile of the same censored per-agent ticks",
            "T100MinusT50Seconds": "maximum minus nearest-rank median of censored ticks, multiplied by 0.02",
            "originalM1Seconds": "frozen original M1, descriptive fallback only",
        },
        "anonymousAggregates": [
            {
                "anonymousLabel": mapping[label],
                **{metric: endpoint_aggregates[metric][label] for metric in endpoint_aggregates},
                "movementRankAmongEligible": movement_ranks.get(label),
                "eligible": label in eligible,
            }
            for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item])
        ],
        "RMAT180Pairwise": {
            "effectOrientation": "first anonymous algorithm minus second anonymous algorithm in seconds; lower is better",
            "multiplicity": "Holm adjusted p-values and Bonferroni simultaneous 95% intervals across six pairs",
            "pairs": sorted(rmat_pairs, key=lambda row: (row["firstAnonymousLabel"], row["secondAnonymousLabel"])),
        },
        "interpretationBoundary": "A nonzero point estimate is reported with its direction even when uncertainty includes zero. This does not establish confirmatory superiority and does not change the original M1 result.",
    }

    m2_raw = phaseb.build_pairwise(blocks, metric="M2")
    m2_values: dict[str, dict[str, list[float]]] = {label: {condition: [] for condition in CONDITIONS} for label in SOURCE_LABELS}
    for block in movement:
        if block.get("m2CommonMaskSufficient") is not True:
            continue
        condition = str(block["conditionId"])
        samples = phaseb.sample_map(block)
        for label in SOURCE_LABELS:
            value = finite(samples[label]["m2CommonMaskMeanPathLength"], "INVALID_M2_AGGREGATE")
            require(value > 0, "NONPOSITIVE_M2_AGGREGATE")
            m2_values[label][condition].append(value)
    m2_aggregate = {label: equal_condition_geometric(m2_values[label]) for label in SOURCE_LABELS}
    m2_ranks = rank_scalars({label: m2_aggregate[label] for label in eligible}) if eligible else {}
    m2_output = {
        "schema": "gate14re-engineering-recommendation-anonymous-m2-v1",
        "independentUnit": "complete input block",
        "sharedCommonMaskRequired": True,
        "anonymousAggregates": [
            {
                "anonymousLabel": mapping[label],
                "equalConditionGeometricMeanPathLength": m2_aggregate[label],
                "pathRankAmongEligible": m2_ranks.get(label),
                "eligible": label in eligible,
            }
            for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item])
        ],
        "pairwise": strip_identity_fields(m2_raw, mapping),
    }

    m4_values: dict[str, dict[str, list[float]]] = {label: {condition: [] for condition in CONDITIONS} for label in SOURCE_LABELS}
    for block in m4_blocks:
        condition = str(block["conditionId"])
        samples = phaseb.sample_map(block)
        for label in SOURCE_LABELS:
            value = finite(samples[label]["nearestRankP95FrameTimeSeconds"], "INVALID_M4_AGGREGATE")
            require(value > 0, "NONPOSITIVE_M4_AGGREGATE")
            m4_values[label][condition].append(value)
    m4_aggregate = {label: equal_condition_geometric(m4_values[label]) for label in SOURCE_LABELS}
    m4_ranks = rank_scalars({label: m4_aggregate[label] for label in eligible}) if eligible else {}
    m4_output = {
        "schema": "gate14re-engineering-recommendation-anonymous-m4-v1",
        "independentUnit": "complete input block",
        "metric": "equal-condition geometric mean of block nearest-rank P95 frame time at N=128",
        "anonymousAggregates": [
            {
                "anonymousLabel": mapping[label],
                "P95FrameTimeSeconds": m4_aggregate[label],
                "renderRankAmongEligible": m4_ranks.get(label),
                "eligible": label in eligible,
            }
            for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item])
        ],
    }

    quantity_raw = phaseb.build_quantity_analysis(blocks)
    quantity_movement = phaseb.quantity_blocks(blocks, "movement")
    rmat_rows: list[dict[str, Any]] = []
    for block in quantity_movement:
        samples = phaseb.sample_map(block)
        for label in SOURCE_LABELS:
            rmat = movement_endpoints(samples[label])["RMAT180Seconds"]
            require(rmat > 0, "NONPOSITIVE_QUANTITY_RMAT")
            rmat_rows.append({
                "x": phaseb.design_row(str(block["conditionId"]), int(block["unitCount"]), label),
                "y": math.log(rmat),
                "cluster": block["blockId"],
            })
    rmat_model = phaseb.fit_cluster_robust_model(rmat_rows, "log_RMAT180_seconds")
    model_names = {
        "RMAT180": (rmat_model, "movement"),
        "M2": (quantity_raw["models"].get("log_M2_common_mask_mean_path_length"), "path"),
        "M4P95": (quantity_raw["models"]["log_M4_block_P95_frame_time_seconds"], "render"),
    }
    ratios: dict[str, dict[str, float]] = {label: {} for label in SOURCE_LABELS}
    ratio_intervals: dict[str, dict[str, list[float]]] = {label: {} for label in SOURCE_LABELS}
    available_models: list[str] = []
    for metric, (model, _) in model_names.items():
        if model is None:
            continue
        available_models.append(metric)
        for label in SOURCE_LABELS:
            row = model["perDoublingByAlgorithm"][label]
            ratios[label][metric] = finite(row["ratioEstimate"], "INVALID_SCALING_RATIO")
            ratio_intervals[label][metric] = [finite(x, "INVALID_SCALING_INTERVAL") for x in row["ratio95CI"]]
    require("RMAT180" in available_models and "M4P95" in available_models, "REQUIRED_SCALING_MODELS_MISSING")
    subranks: dict[str, dict[str, int]] = {}
    for metric in available_models:
        subranks[metric] = rank_scalars({label: ratios[label][metric] for label in eligible}) if eligible else {}
    scaling_burden = {
        label: statistics.fmean(subranks[metric][label] for metric in available_models)
        for label in eligible
    }
    scaling_ranks = rank_scalars(scaling_burden) if eligible else {}
    quantity_output = {
        "schema": "gate14re-engineering-recommendation-anonymous-quantity-scaling-v1",
        "anchors": list(ANCHORS),
        "unitCounts": [1, 8, 32, 128, 512],
        "metric": "per-doubling ratio from the frozen anchor-plus-log2N model; lower growth is better",
        "availableSubmetrics": available_models,
        "anonymousScaling": [
            {
                "anonymousLabel": mapping[label],
                "perDoublingRatios": ratios[label],
                "ordinary95RatioIntervals": ratio_intervals[label],
                "submetricRanksAmongEligible": {metric: subranks[metric].get(label) for metric in available_models},
                "meanSubmetricRank": scaling_burden.get(label),
                "scalingRankAmongEligible": scaling_ranks.get(label),
                "eligible": label in eligible,
            }
            for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item])
        ],
        "selectionRole": "engineering scaling dimension, not a new confirmatory hypothesis",
    }

    static_bindings = contract["staticEngineeringTiebreak"]["sourceBindings"]
    static_raw: dict[str, dict[str, int]] = {}
    for row in static_bindings:
        label = str(row["sourceLabel"])
        path = project_root / str(row["path"])
        verify_hash(path, str(row["sha256"]), "STATIC_SOURCE")
        static_raw[label] = compute_static_metrics(path)
    static_tuples = {
        label: (
            static_raw[label]["logicalSourceLines"],
            static_raw[label]["branchTokens"],
            static_raw[label]["allocationSites"],
            static_raw[label]["publicSurfaceTokens"],
            static_raw[label]["sourceBytes"],
        )
        for label in eligible
    }
    static_ranks = rank_tuples(static_tuples) if eligible else {}
    static_output = {
        "schema": "gate14re-engineering-recommendation-anonymous-static-tiebreak-v1",
        "role": "last-resort static maintainability proxy only",
        "metricOrder": ["logicalSourceLines", "branchTokens", "allocationSites", "publicSurfaceTokens", "sourceBytes"],
        "anonymousProfiles": [
            {
                "anonymousLabel": mapping[label],
                "metrics": static_raw[label],
                "staticBurdenRankAmongEligible": static_ranks.get(label),
                "eligible": label in eligible,
            }
            for label in sorted(SOURCE_LABELS, key=lambda item: mapping[item])
        ],
        "limitations": "These lexical source measures are transparent proxies, not direct measurements of long-term maintenance cost.",
    }

    decision_rows: list[dict[str, Any]] = []
    for label in eligible:
        score = 2 * movement_ranks[label] + m2_ranks[label] + scaling_ranks[label] + m4_ranks[label]
        decision_rows.append({
            "anonymousLabel": mapping[label],
            "movementRank": movement_ranks[label],
            "pathRank": m2_ranks[label],
            "scalingRank": scaling_ranks[label],
            "renderRank": m4_ranks[label],
            "decisionScore": score,
            "staticBurdenRank": static_ranks[label],
        })
    decision_rows.sort(key=lambda row: row["anonymousLabel"])
    recommendation_source: str | None = None
    recommendation_basis: str
    if not eligible:
        recommendation_basis = "NO_ELIGIBLE_ALGORITHM"
    elif len(eligible) == 1:
        recommendation_source = eligible[0]
        recommendation_basis = "SOLE_ELIGIBLE_ENGINEERING_RECOMMENDATION"
    else:
        scores = {label: 2 * movement_ranks[label] + m2_ranks[label] + scaling_ranks[label] + m4_ranks[label] for label in eligible}
        minimum = min(scores.values())
        candidates = [label for label in eligible if scores[label] == minimum]
        if len(candidates) == 1:
            recommendation_source = candidates[0]
            recommendation_basis = "UNIQUE_MINIMUM_FROZEN_DECISION_SCORE"
        else:
            lex = {
                label: (
                    *movement_tuples[label],
                    m2_aggregate[label],
                    scaling_burden[label],
                    m4_aggregate[label],
                    *static_tuples[label],
                )
                for label in candidates
            }
            ordered = sorted(candidates, key=lambda label: (lex[label], mapping[label]))
            first = ordered[0]
            exact = [label for label in ordered if all(math.isclose(a, b, rel_tol=0.0, abs_tol=1.0e-12) for a, b in zip(lex[label], lex[first]))]
            if len(exact) == 1:
                recommendation_source = first
                recommendation_basis = "FROZEN_LEXICOGRAPHIC_TIEBREAK"
            else:
                recommendation_basis = "EXACT_EVIDENCE_AND_STATIC_PROXY_EQUALITY_REQUIRES_USER_POLICY"
    decision = {
        "schema": "gate14re-engineering-recommendation-anonymous-preadjudication-v1",
        "status": "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING",
        "classification": "POST_HOC_READ_ONLY_COMPOSITE_ENGINEERING_RECOMMENDATION",
        "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
        "confirmatoryStatisticalWinnerClaimed": False,
        "weights": {"movementRank": 2, "pathRank": 1, "scalingRank": 1, "renderRank": 1},
        "scoreDirection": "lower is better",
        "tieBreakOrder": ["RMAT180", "T95", "T99", "T100MinusT50", "originalM1", "M2", "quantityScaling", "M4P95", "staticEngineeringBurden"],
        "rows": decision_rows,
        "recommendationAvailable": recommendation_source is not None,
        "provisionalRecommendedAnonymousLabel": mapping[recommendation_source] if recommendation_source is not None else None,
        "recommendationBasis": recommendation_basis,
        "productionIdentityReleased": False,
        "unblindingAuthorized": False,
        "finalProductionRecommendationAuthorized": False,
    }

    report_lines = [
        "# Gate 14Re 匿名综合工程预裁决",
        "",
        "状态：`ANONYMOUS PRE-ADJUDICATION COMPLETE / UNBLINDING PENDING`",
        "",
        "本分析是对已封存 Gate 14Re raw 的独立只读、事后工程决策分析。原正式结论 `NO_UNIQUE_WINNER` 保持不变；本分析不声称确认性统计优胜。",
        "",
        "## 裁决表",
        "",
        "| 匿名算法 | 合格 | 运动 rank | 路径 rank | 数量尺度 rank | 渲染 rank | DecisionScore | 静态负担 rank |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    eligible_anonymous = set(mapping[label] for label in eligible)
    by_anonymous = {row["anonymousLabel"]: row for row in decision_rows}
    for anonymous in sorted(ANONYMOUS_LABELS):
        row = by_anonymous.get(anonymous)
        if row is None:
            report_lines.append(f"| {anonymous} | NO | — | — | — | — | — | — |")
        else:
            report_lines.append(f"| {anonymous} | YES | {row['movementRank']} | {row['pathRank']} | {row['scalingRank']} | {row['renderRank']} | {row['decisionScore']} | {row['staticBurdenRank']} |")
    report_lines += [
        "",
        "## 匿名预裁决",
        "",
        f"- 推荐是否可用：{'YES' if decision['recommendationAvailable'] else 'NO'}",
        f"- 暂定匿名推荐：{decision['provisionalRecommendedAnonymousLabel'] or '无'}",
        f"- 裁决依据：`{decision['recommendationBasis']}`",
        "- 生产算法身份：未释放。",
        "- 下一步：只有在用户单独授权解盲与最终推荐后，才可解密标签映射并输出真实算法名称。",
        "",
        "## 推断边界",
        "",
        "RMAT 的六组匿名对比报告点估计、Holm 校正 p 值与 Bonferroni 同时 95% 区间。区间包含 0 时写作‘方向存在但不确定’，不写作统计平局，也不升级为统计优胜。T95、T99、M2、数量尺度、M4 和静态工程负担依冻结规则承担综合工程裁决作用。",
        "",
    ]
    report = "\n".join(report_lines)

    outputs: dict[str, Any] = {
        "anonymous-eligibility.json": eligibility,
        "anonymous-movement-resolution.json": movement_output,
        "anonymous-m2.json": m2_output,
        "anonymous-quantity-scaling.json": quantity_output,
        "anonymous-m4.json": m4_output,
        "anonymous-static-engineering.json": static_output,
        "anonymous-decision-workbook.json": decision,
        "Gate14Re_Anonymous_Engineering_PreAdjudication.zh-CN.md": report,
    }
    for payload in outputs.values():
        ensure_anonymous(payload)
    return outputs


# ---------------------------------------------------------------------------
# Input binding, commit, verification, and tests.
# ---------------------------------------------------------------------------


def load_authorized_context(project_root: Path) -> tuple[dict[str, Any], dict[str, Any], Any, dict[str, str], dict[str, Any]]:
    contract_path = project_root / REL["contract"]
    authorization_path = project_root / REL["authorization"]
    readiness_path = project_root / REL["readiness"]
    require(contract_path.is_file() and authorization_path.is_file() and readiness_path.is_file(), "CONTROL_FILE_MISSING")
    require(is_read_only(contract_path) and is_read_only(authorization_path) and is_read_only(readiness_path), "CONTROL_FILE_NOT_READONLY")
    contract = load_json(contract_path)
    authorization = load_json(authorization_path)
    contract_hash = sha256_file(contract_path)
    analyzer_hash = sha256_file(Path(__file__).resolve())
    require(contract.get("schema") == "gate14re-engineering-recommendation-contract-v1", "CONTRACT_SCHEMA")
    require(authorization.get("schema") == "gate14re-engineering-recommendation-authorization-v1", "AUTHORIZATION_SCHEMA")
    require(authorization.get("anonymousReadOnlyAnalysisAuthorized") is True, "ANONYMOUS_ANALYSIS_NOT_AUTHORIZED")
    require(authorization.get("unblindingAuthorized") is False, "UNBLINDING_BOUNDARY")
    require(authorization.get("finalProductionRecommendationAuthorized") is False, "FINAL_RECOMMENDATION_BOUNDARY")
    require(authorization.get("contractSha256") == contract_hash, "AUTH_CONTRACT_BINDING")
    require(authorization.get("analyzerSha256") == analyzer_hash, "AUTH_ANALYZER_BINDING")
    require(authorization.get("readinessSha256") == sha256_file(readiness_path), "AUTH_READINESS_BINDING")
    require(contract.get("analyzerSha256") == analyzer_hash, "CONTRACT_ANALYZER_BINDING")
    for key, relative in (("phaseBAnalyzer", REL["phaseb_analyzer"]), ("phaseBReceipt", REL["phaseb_receipt"]), ("phaseBCanonicalTree", REL["phaseb_tree"]), ("phaseBEligibility", REL["phaseb_eligibility"]), ("phaseBWinnerAdjudication", REL["phaseb_winner"]), ("gate14ReStatusV6", REL["status"])):
        binding = contract["frozenInputBindings"][key]
        require(binding["path"] == relative, f"{key.upper()}_PATH_BINDING")
        verify_hash(project_root / relative, binding["sha256"], key.upper(), read_only=True)
    phaseb = import_phaseb(project_root)
    mapping, commitment = load_mapping(project_root, contract)
    return contract, authorization, phaseb, mapping, commitment


def load_verified_blocks(project_root: Path, phaseb: Any) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    raw_root, records, original_authorization = phaseb.verify_raw_root(project_root)
    blocks = phaseb.load_formal_blocks(raw_root, records)
    return blocks, records, original_authorization


def build_input_audit(project_root: Path, contract: Mapping[str, Any], authorization: Mapping[str, Any], commitment: Mapping[str, Any], records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    return {
        "schema": "gate14re-engineering-recommendation-input-audit-v1",
        "studyId": "Gate14Re",
        "rawRoot": "Research/FormalRuns/Gate14Re/PhaseA/attempt-001",
        "rawCanonicalTreeSha256": contract["frozenInputBindings"]["rawCanonicalTree"]["sha256"],
        "rawCanonicalTreeRecords": len(records),
        "rawFilesVerifiedReadOnlyAndByHash": True,
        "originalPhaseBRootModified": False,
        "originalFormalConclusion": "NO_UNIQUE_WINNER",
        "analysisContractSha256": sha256_file(project_root / REL["contract"]),
        "authorizationSha256": sha256_file(project_root / REL["authorization"]),
        "custodyCommitmentSha256": sha256_file(project_root / REL["custody_commitment"]),
        "custodyId": commitment["custodyId"],
        "mappingReleased": False,
        "productionIdentityAccessedForReporting": False,
        "independentUnit": "complete input block",
        "agentAndFrameRecordsAreSubsamples": True,
        "newUnityAcquisitionPerformed": False,
    }


def payload_bytes(value: Any) -> bytes:
    return value.encode("utf-8") if isinstance(value, str) else canonical_json_bytes(value, pretty=True)


def commit_analysis(project_root: Path, outputs: Mapping[str, Any], input_audit: Mapping[str, Any], contract: Mapping[str, Any], authorization: Mapping[str, Any], commitment: Mapping[str, Any]) -> dict[str, Any]:
    final_root = project_root / REL["analysis_root"]
    require(not final_root.exists(), "ANALYSIS_ROOT_ALREADY_EXISTS", str(final_root))
    final_root.parent.mkdir(parents=True, exist_ok=True)
    staging = final_root.parent / (".attempt-001.staging-" + str(uuid.uuid4()))
    staging.mkdir(parents=False, exist_ok=False)
    try:
        write_json(staging / "analysis-input-audit.json", input_audit)
        for name, value in outputs.items():
            atomic_create(staging / name, payload_bytes(value))
        records: list[dict[str, Any]] = []
        for path in sorted((p for p in staging.rglob("*") if p.is_file()), key=lambda p: p.relative_to(staging).as_posix()):
            records.append({"relativePath": path.relative_to(staging).as_posix(), "bytes": path.stat().st_size, "sha256": sha256_file(path)})
        tree_payload = b"".join(canonical_json_bytes(record, pretty=False) for record in records)
        atomic_create(staging / "analysis-canonical-tree.v1.jsonl", tree_payload)
        tree_hash = sha256_file(staging / "analysis-canonical-tree.v1.jsonl")
        decision = outputs["anonymous-decision-workbook.json"]
        manifest = {
            "schema": "gate14re-engineering-recommendation-analysis-manifest-v1",
            "studyId": "Gate14Re",
            "status": "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING",
            "analysisRoot": REL["analysis_root"],
            "analysisContractSha256": sha256_file(project_root / REL["contract"]),
            "authorizationSha256": sha256_file(project_root / REL["authorization"]),
            "analyzerSha256": sha256_file(Path(__file__).resolve()),
            "custodyCommitmentSha256": sha256_file(project_root / REL["custody_commitment"]),
            "rawCanonicalTreeSha256": contract["frozenInputBindings"]["rawCanonicalTree"]["sha256"],
            "originalPhaseBReceiptSha256": contract["frozenInputBindings"]["phaseBReceipt"]["sha256"],
            "payloadRecords": len(records),
            "payloadBytes": sum(int(row["bytes"]) for row in records),
            "canonicalTreeSha256": tree_hash,
            "anonymousRecommendationAvailable": bool(decision["recommendationAvailable"]),
            "productionIdentityReleased": False,
            "confirmatoryStatisticalWinnerClaimed": False,
            "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
        }
        write_json(staging / "analysis-manifest.v1.json", manifest)
        manifest_hash = sha256_file(staging / "analysis-manifest.v1.json")
        receipt = {
            "schema": "gate14re-engineering-recommendation-analysis-receipt-v1",
            "studyId": "Gate14Re",
            "status": "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING",
            "completedUtc": utc_now(),
            "analysisRoot": REL["analysis_root"],
            "analysisManifestSha256": manifest_hash,
            "analysisCanonicalTreeSha256": tree_hash,
            "anonymousRecommendationAvailable": bool(decision["recommendationAvailable"]),
            "anonymousRecommendationProduced": decision["provisionalRecommendedAnonymousLabel"] is not None,
            "productionIdentityReleased": False,
            "unblindingAuthorized": False,
            "finalProductionRecommendationAuthorized": False,
            "rawRootModified": False,
            "originalPhaseBRootModified": False,
            "newUnityAcquisitionPerformed": False,
            "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
        }
        write_json(staging / "analysis-receipt.v1.json", receipt)
        for path in (p for p in staging.rglob("*") if p.is_file()):
            set_read_only(path)
        os.replace(staging, final_root)
        return {"status": "PASS", "analysisRoot": REL["analysis_root"], "anonymousPreAdjudicationComplete": True, "productionIdentityReleased": False}
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def run_formal(project_root: Path) -> dict[str, Any]:
    contract, authorization, phaseb, mapping, commitment = load_authorized_context(project_root)
    blocks, records, _ = load_verified_blocks(project_root, phaseb)
    outputs = compute_outputs(project_root, phaseb, blocks, mapping, contract)
    input_audit = build_input_audit(project_root, contract, authorization, commitment, records)
    ensure_anonymous(input_audit)
    return commit_analysis(project_root, outputs, input_audit, contract, authorization, commitment)


def verify_existing(project_root: Path) -> dict[str, Any]:
    contract, authorization, phaseb, mapping, commitment = load_authorized_context(project_root)
    blocks, records, _ = load_verified_blocks(project_root, phaseb)
    outputs = compute_outputs(project_root, phaseb, blocks, mapping, contract)
    input_audit = build_input_audit(project_root, contract, authorization, commitment, records)
    expected = {"analysis-input-audit.json": input_audit, **outputs}
    root = project_root / REL["analysis_root"]
    require(root.is_dir(), "EXISTING_ANALYSIS_ROOT_MISSING")
    for name, value in expected.items():
        path = root / name
        require(path.is_file(), "EXISTING_OUTPUT_MISSING", name)
        require(path.read_bytes() == payload_bytes(value), "EXISTING_OUTPUT_MISMATCH", name)
        require(is_read_only(path), "EXISTING_OUTPUT_NOT_READONLY", name)
    receipt = load_json(root / "analysis-receipt.v1.json")
    require(receipt.get("status") == "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING", "EXISTING_RECEIPT_STATUS")
    require(receipt.get("productionIdentityReleased") is False, "EXISTING_IDENTITY_RELEASE")
    return {"status": "PASS", "verifiedExisting": True, "productionIdentityReleased": False}


def run_self_test(receipt_path: Path | None) -> dict[str, Any]:
    units = [
        {"agentId": 0, "arrived": True, "arrivalTick": 100},
        {"agentId": 1, "arrived": True, "arrivalTick": 200},
        {"agentId": 2, "arrived": False, "arrivalTick": -1},
        {"agentId": 3, "arrived": True, "arrivalTick": 400},
    ]
    sample = {"unitCount": 4, "units": units, "m1Seconds": 180.0}
    endpoint = movement_endpoints(sample)
    require(math.isclose(endpoint["RMAT180Seconds"], 48.5), "SELFTEST_RMAT")
    require(math.isclose(endpoint["T95Seconds"], 180.0), "SELFTEST_T95")
    require(math.isclose(endpoint["T99Seconds"], 180.0), "SELFTEST_T99")
    require(rank_scalars({"x": 1.0, "y": 1.0, "z": 2.0}) == {"x": 1, "y": 1, "z": 3}, "SELFTEST_SCALAR_RANK")
    require(rank_tuples({"x": (1.0, 2.0), "y": (1.0, 3.0), "z": (2.0, 0.0)}) == {"x": 1, "y": 2, "z": 3}, "SELFTEST_TUPLE_RANK")
    payload = {
        "schema": "gate14re-engineering-recommendation-self-test-receipt-v1",
        "status": "PASS",
        "completedUtc": utc_now(),
        "assertions": 5,
        "formalRawOpened": False,
        "formalOutcomeAccessed": False,
    }
    if receipt_path is not None:
        write_json(receipt_path, payload)
    return payload


def write_failure(project_root: Path, mode: str, error: BaseException) -> Path | None:
    root = project_root / REL["verification_root"]
    root.mkdir(parents=True, exist_ok=True)
    path = root / ("failure-receipt." + str(uuid.uuid4()) + ".json")
    payload = {
        "schema": "gate14re-engineering-recommendation-failure-receipt-v1",
        "status": "FAIL_CLOSED",
        "mode": mode,
        "failedUtc": utc_now(),
        "errorType": type(error).__name__,
        "errorCode": error.code if isinstance(error, AnalysisError) else "UNEXPECTED_ERROR",
        "detail": str(error),
        "rawModified": False,
        "originalPhaseBModified": False,
        "unblindingPerformed": False,
    }
    try:
        write_json(path, payload)
        set_read_only(path)
        return path
    except BaseException:
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gate14Re read-only anonymous engineering recommendation analyzer")
    parser.add_argument("--project-root", default=str(PROJECT_ROOT_DEFAULT))
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--prepare-custody", action="store_true")
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--formal", action="store_true")
    modes.add_argument("--verify-existing", action="store_true")
    parser.add_argument("--receipt")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root).resolve()
    mode = "prepare-custody" if args.prepare_custody else "self-test" if args.self_test else "formal" if args.formal else "verify-existing"
    try:
        if args.prepare_custody:
            result = prepare_custody(project_root)
        elif args.self_test:
            result = run_self_test(Path(args.receipt).resolve() if args.receipt else None)
        elif args.formal:
            result = run_formal(project_root)
        else:
            result = verify_existing(project_root)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except BaseException as error:
        failure = None if args.self_test or args.prepare_custody else write_failure(project_root, mode, error)
        print(json.dumps({"status": "FAIL_CLOSED", "mode": mode, "error": str(error), "failureReceipt": str(failure) if failure else None}, ensure_ascii=False), file=sys.stderr)
        if not isinstance(error, AnalysisError):
            traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
