#!/usr/bin/env python3
"""One-time Gate 14Re engineering-recommendation unblinding.

This program does not read formal block outputs, recompute statistics, change
the frozen anonymous decision, or modify the original Phase A/Phase B roots.
It verifies the frozen authorization and commitments, performs exactly one
DPAPI decryption in ``--formal`` mode, maps the already committed anonymous
pre-adjudication to production identities, and commits a new read-only result
root.  ``--verify-existing`` verifies the released mapping by reconstructing
the committed plaintext; it deliberately does not decrypt the custody again.
"""

from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import traceback
import uuid
from typing import Any, Mapping, Sequence


SCHEMA = "gate14re-engineering-recommendation-unblinder-v1"
PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parents[1]
SOURCE_LABELS = ("A", "B", "C", "D")
ANONYMOUS_LABELS = ("U17", "U29", "U43", "U61")
CRYPTPROTECT_UI_FORBIDDEN = 0x1

REL = {
    "contract": "Research/Gate14Re/EngineeringRecommendation/Unblinding/v1/Gate14Re_Engineering_Recommendation_Unblinding_Contract.v1.json",
    "authorization": "Research/Gate14Re/EngineeringRecommendation/Unblinding/v1/Gate14Re_Engineering_Recommendation_Unblinding_Authorization.v1.json",
    "prompt": "Research/Gate14Re/EngineeringRecommendation/next-unblinding-and-final-recommendation-authorization-prompt.v1.md",
    "custody_commitment": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody-commitment.v1.json",
    "custody_payload": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody.payload.dpapi.bin",
    "custody_entropy": "Research/Gate14Re/EngineeringRecommendation/Blinding/v1/label-custody.entropy.v1.bin",
    "anonymous_receipt": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001/analysis-receipt.v1.json",
    "anonymous_manifest": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001/analysis-manifest.v1.json",
    "anonymous_tree": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001/analysis-canonical-tree.v1.jsonl",
    "anonymous_decision": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001/anonymous-decision-workbook.json",
    "anonymous_eligibility": "Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001/anonymous-eligibility.json",
    "phaseb_receipt": "Research/Analysis/Gate14Re/PhaseB/attempt-001/analysis-receipt.v1.json",
    "phaseb_tree": "Research/Analysis/Gate14Re/PhaseB/attempt-001/analysis-canonical-tree.v1.jsonl",
    "status": "Research/Gate14Re/Gate14Re_Status.v6.json",
    "design_contract": "Research/Gate14Re/Gate14Re_Design_Contract.v2.json",
    "output_root": "Research/Analysis/Gate14Re/EngineeringRecommendation/final-attempt-001",
    "verification_root": "Research/Verification/Gate14Re/engineering-recommendation-unblinding-attempt-001",
}


class UnblindingError(RuntimeError):
    def __init__(self, code: str, detail: str | None = None):
        self.code = code
        self.detail = detail or code
        super().__init__(f"{code}: {self.detail}")


def require(condition: bool, code: str, detail: str | None = None) -> None:
    if not condition:
        raise UnblindingError(code, detail)


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
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
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


def verify_hash(path: Path, expected: str, code: str, *, read_only: bool = True) -> None:
    require(path.is_file(), f"{code}_MISSING", str(path))
    actual = sha256_file(path)
    require(actual == expected, f"{code}_HASH_MISMATCH", f"{path}: {actual}")
    if read_only:
        require(is_read_only(path), f"{code}_NOT_READONLY", str(path))


def ensure_project_path(project_root: Path, path: Path, code: str) -> None:
    root = project_root.resolve()
    resolved = path.resolve()
    require(resolved == root or root in resolved.parents, code, str(resolved))


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_ubyte))]


def _blob(data: bytes) -> tuple[DATA_BLOB, Any]:
    buffer = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    return DATA_BLOB(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte))), buffer


def unprotect_once(data: bytes, entropy: bytes) -> bytes:
    """Perform the sole authorized DPAPI decrypt operation."""
    crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    input_blob, input_buffer = _blob(data)
    entropy_blob, entropy_buffer = _blob(entropy)
    output_blob = DATA_BLOB()
    description = wintypes.LPWSTR()
    crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(DATA_BLOB),
        ctypes.POINTER(wintypes.LPWSTR),
        ctypes.POINTER(DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(DATA_BLOB),
    ]
    crypt32.CryptUnprotectData.restype = wintypes.BOOL
    ok = crypt32.CryptUnprotectData(
        ctypes.byref(input_blob),
        ctypes.byref(description),
        ctypes.byref(entropy_blob),
        None,
        None,
        CRYPTPROTECT_UI_FORBIDDEN,
        ctypes.byref(output_blob),
    )
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


def binding_map(contract: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    rows = contract.get("frozenInputBindings")
    require(isinstance(rows, list) and rows, "CONTRACT_INPUT_BINDINGS")
    result: dict[str, Mapping[str, Any]] = {}
    for row in rows:
        require(isinstance(row, Mapping), "CONTRACT_INPUT_BINDING_ROW")
        name = str(row.get("name"))
        require(name not in result, "CONTRACT_INPUT_BINDING_DUPLICATE", name)
        result[name] = row
    return result


def verify_all_bindings(project_root: Path, contract: Mapping[str, Any]) -> None:
    for name, row in binding_map(contract).items():
        path = project_root / str(row["relativePath"])
        ensure_project_path(project_root, path, "INPUT_PATH_OUTSIDE_PROJECT")
        verify_hash(path, str(row["sha256"]), "INPUT_" + name.upper().replace("-", "_"), read_only=True)


def load_authorized_context(project_root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    contract_path = project_root / REL["contract"]
    authorization_path = project_root / REL["authorization"]
    require(contract_path.is_file(), "CONTRACT_MISSING")
    require(authorization_path.is_file(), "AUTHORIZATION_MISSING")
    require(is_read_only(contract_path), "CONTRACT_NOT_READONLY")
    require(is_read_only(authorization_path), "AUTHORIZATION_NOT_READONLY")
    contract = load_json(contract_path)
    authorization = load_json(authorization_path)
    require(contract.get("schema") == "gate14re-engineering-recommendation-unblinding-contract-v1", "CONTRACT_SCHEMA")
    require(contract.get("status") == "FROZEN_PRE_UNBLINDING", "CONTRACT_STATUS")
    require(contract.get("outputRoot") == REL["output_root"], "CONTRACT_OUTPUT_ROOT")
    require(authorization.get("schema") == "gate14re-engineering-recommendation-unblinding-authorization-v1", "AUTHORIZATION_SCHEMA")
    require(authorization.get("status") == "AUTHORIZED_ONCE", "AUTHORIZATION_STATUS")
    require(authorization.get("attemptId") == "attempt-001", "AUTHORIZATION_ATTEMPT")
    require(authorization.get("contractSha256") == sha256_file(contract_path), "AUTHORIZATION_CONTRACT_HASH")
    require(authorization.get("promptSha256") == contract["authorizedPrompt"]["sha256"], "AUTHORIZATION_PROMPT_HASH")
    scope = authorization.get("scope")
    require(isinstance(scope, Mapping), "AUTHORIZATION_SCOPE")
    for key in (
        "decryptLabelMappingOnce",
        "verifyMappingCommitment",
        "mapFrozenAnonymousPreadjudication",
        "writeVersionedReadOnlyOutputs",
        "preserveOriginalNoUniqueWinner",
    ):
        require(scope.get(key) is True, "AUTHORIZATION_REQUIRED_SCOPE", key)
    for key in (
        "modifyFormalRaw",
        "modifyOriginalPhaseB",
        "modifyAnonymousPreadjudication",
        "changeRulesOrWeights",
        "recomputeAnalysis",
        "collectOrTopUpData",
        "startGate15",
    ):
        require(scope.get(key) is False, "AUTHORIZATION_FORBIDDEN_SCOPE", key)
    require(contract["tool"]["relativePath"] == Path(__file__).resolve().relative_to(project_root).as_posix(), "CONTRACT_TOOL_PATH")
    require(contract["tool"]["sha256"] == sha256_file(Path(__file__).resolve()), "CONTRACT_TOOL_HASH")
    verify_all_bindings(project_root, contract)
    return contract, authorization


def verify_frozen_semantics(project_root: Path, contract: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, str]]:
    decision = load_json(project_root / REL["anonymous_decision"])
    eligibility = load_json(project_root / REL["anonymous_eligibility"])
    anonymous_receipt = load_json(project_root / REL["anonymous_receipt"])
    phaseb_receipt = load_json(project_root / REL["phaseb_receipt"])
    status = load_json(project_root / REL["status"])
    require(decision.get("status") == "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING", "ANONYMOUS_DECISION_STATUS")
    require(decision.get("provisionalRecommendedAnonymousLabel") == "U43", "ANONYMOUS_RECOMMENDATION_LABEL")
    require(decision.get("recommendationBasis") == "UNIQUE_MINIMUM_FROZEN_DECISION_SCORE", "ANONYMOUS_RECOMMENDATION_BASIS")
    require(decision.get("originalFormalConclusionPreserved") == "NO_UNIQUE_WINNER", "ANONYMOUS_ORIGINAL_CONCLUSION")
    require(decision.get("confirmatoryStatisticalWinnerClaimed") is False, "ANONYMOUS_CONFIRMATORY_CLAIM")
    require(decision.get("productionIdentityReleased") is False, "ANONYMOUS_ALREADY_UNBLINDED")
    require(decision.get("weights") == {"movementRank": 2, "pathRank": 1, "renderRank": 1, "scalingRank": 1}, "ANONYMOUS_WEIGHTS")
    rows = decision.get("rows")
    require(isinstance(rows, list) and len(rows) == 3, "ANONYMOUS_DECISION_ROWS")
    require({str(row.get("anonymousLabel")) for row in rows} == {"U17", "U29", "U43"}, "ANONYMOUS_DECISION_LABELS")
    require(anonymous_receipt.get("status") == "ANONYMOUS_PRE-ADJUDICATION_COMPLETE_UNBLINDING_PENDING", "ANONYMOUS_RECEIPT_STATUS")
    require(anonymous_receipt.get("productionIdentityReleased") is False, "ANONYMOUS_RECEIPT_IDENTITY")
    require(phaseb_receipt.get("status") == "FORMAL-PHASE-B-ANALYSIS-COMPLETE", "PHASEB_RECEIPT_STATUS")
    require(phaseb_receipt.get("winnerAdjudicationStatus") == "NO_UNIQUE_WINNER", "PHASEB_ORIGINAL_CONCLUSION")
    require(phaseb_receipt.get("winnerProductionAlgorithmId") is None, "PHASEB_WINNER_MUST_BE_NULL")
    require(status.get("status") == "FORMAL-PHASE-B-ANALYSIS-COMPLETE", "GATE14RE_STATUS")
    require(status.get("substatus") == "NO-UNIQUE-WINNER", "GATE14RE_SUBSTATUS")
    design = load_json(project_root / REL["design_contract"])
    algorithms = design.get("algorithms")
    require(isinstance(algorithms, list) and len(algorithms) == 4, "DESIGN_ALGORITHM_ROWS")
    production = {str(row["label"]): str(row["productionId"]) for row in algorithms}
    expected = contract["productionIdentityBinding"]["sourceToProduction"]
    require(production == expected, "PRODUCTION_IDENTITY_BINDING")
    require(set(production) == set(SOURCE_LABELS), "PRODUCTION_SOURCE_SET")
    require(set(production.values()) == {"A*-R", "D*L", "C-FF", "IDFF"}, "PRODUCTION_ID_SET")
    eligible_rows = eligibility.get("anonymousAlgorithms")
    require(isinstance(eligible_rows, list) and len(eligible_rows) == 4, "ELIGIBILITY_ROWS")
    require({str(row.get("anonymousLabel")) for row in eligible_rows} == set(ANONYMOUS_LABELS), "ELIGIBILITY_LABELS")
    return decision, eligibility, production


def decode_mapping_once(project_root: Path, contract: Mapping[str, Any]) -> tuple[dict[str, str], dict[str, Any]]:
    commitment = load_json(project_root / REL["custody_commitment"])
    require(commitment.get("status") == "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED", "CUSTODY_STATUS")
    require(commitment.get("mappingReleased") is False, "CUSTODY_RELEASE_STATE")
    require(commitment.get("unblindingAuthorized") is False, "CUSTODY_STORED_AUTH_STATE")
    require(commitment.get("mappingCommitmentSha256") == contract["labelCustody"]["mappingCommitmentSha256"], "CUSTODY_MAPPING_COMMITMENT_BINDING")
    payload = (project_root / REL["custody_payload"]).read_bytes()
    entropy = (project_root / REL["custody_entropy"]).read_bytes()
    plaintext = bytearray(unprotect_once(payload, entropy))
    try:
        actual_commitment = hashlib.sha256(plaintext).hexdigest()
        require(actual_commitment == commitment["mappingCommitmentSha256"], "PLAINTEXT_MAPPING_COMMITMENT")
        secret = json.loads(plaintext.decode("utf-8"))
    finally:
        for index in range(len(plaintext)):
            plaintext[index] = 0
    require(secret.get("schema") == "gate14re-engineering-recommendation-label-secret-v1", "SECRET_SCHEMA")
    require(secret.get("custodyId") == commitment.get("custodyId"), "SECRET_CUSTODY_ID")
    rows = secret.get("mapping")
    require(isinstance(rows, list) and len(rows) == 4, "SECRET_MAPPING_ROWS")
    source_to_anonymous = {str(row["sourceLabel"]): str(row["anonymousLabel"]) for row in rows}
    require(set(source_to_anonymous) == set(SOURCE_LABELS), "SECRET_SOURCE_SET")
    require(set(source_to_anonymous.values()) == set(ANONYMOUS_LABELS), "SECRET_ANONYMOUS_SET")
    return source_to_anonymous, commitment


def reconstruct_secret_commitment(source_to_anonymous: Mapping[str, str], custody_id: str) -> str:
    secret = {
        "schema": "gate14re-engineering-recommendation-label-secret-v1",
        "studyId": "Gate14Re",
        "custodyId": custody_id,
        "mapping": [
            {"sourceLabel": source, "anonymousLabel": source_to_anonymous[source]}
            for source in SOURCE_LABELS
        ],
    }
    return hashlib.sha256(canonical_json_bytes(secret, pretty=False)).hexdigest()


def mapped_payloads(
    project_root: Path,
    contract: Mapping[str, Any],
    authorization: Mapping[str, Any],
    decision: Mapping[str, Any],
    eligibility: Mapping[str, Any],
    production: Mapping[str, str],
    source_to_anonymous: Mapping[str, str],
    commitment: Mapping[str, Any],
) -> dict[str, Any]:
    anonymous_to_source = {anonymous: source for source, anonymous in source_to_anonymous.items()}
    anonymous_to_production = {anonymous: production[source] for anonymous, source in anonymous_to_source.items()}
    require(set(anonymous_to_production) == set(ANONYMOUS_LABELS), "RELEASED_ANONYMOUS_SET")
    recommendation_label = str(decision["provisionalRecommendedAnonymousLabel"])
    recommendation_production = anonymous_to_production[recommendation_label]
    decision_by_label = {str(row["anonymousLabel"]): dict(row) for row in decision["rows"]}
    eligibility_by_label = {str(row["anonymousLabel"]): dict(row) for row in eligibility["anonymousAlgorithms"]}

    mapping_rows: list[dict[str, Any]] = []
    mapped_decision_rows: list[dict[str, Any]] = []
    mapped_eligibility_rows: list[dict[str, Any]] = []
    for anonymous in ANONYMOUS_LABELS:
        source = anonymous_to_source[anonymous]
        production_id = anonymous_to_production[anonymous]
        elig = eligibility_by_label[anonymous]
        mapping_rows.append({
            "anonymousLabel": anonymous,
            "sourceLabel": source,
            "productionAlgorithmId": production_id,
            "eligible": bool(elig["eligible"]),
            "isFinalEngineeringRecommendation": anonymous == recommendation_label,
        })
        mapped_eligibility_rows.append({
            **elig,
            "sourceLabel": source,
            "productionAlgorithmId": production_id,
        })
        if anonymous in decision_by_label:
            mapped_decision_rows.append({
                **decision_by_label[anonymous],
                "sourceLabel": source,
                "productionAlgorithmId": production_id,
            })

    release = {
        "schema": "gate14re-engineering-recommendation-label-mapping-release-v1",
        "studyId": "Gate14Re",
        "attemptId": "attempt-001",
        "status": "MAPPING_RELEASED_AND_COMMITMENT_VERIFIED",
        "custodyId": commitment["custodyId"],
        "mappingCommitmentSha256": commitment["mappingCommitmentSha256"],
        "mappingCommitmentVerified": True,
        "dpapiDecryptOperationsThisAttempt": 1,
        "rows": mapping_rows,
    }
    final = {
        "schema": "gate14re-final-composite-engineering-recommendation-v1",
        "studyId": "Gate14Re",
        "attemptId": "attempt-001",
        "status": "FINAL-POST-HOC-COMPOSITE-ENGINEERING-RECOMMENDATION-COMPLETE",
        "classification": "POST_HOC_COMPOSITE_ENGINEERING_RECOMMENDATION",
        "recommendedAnonymousLabel": recommendation_label,
        "recommendedProductionAlgorithmId": recommendation_production,
        "recommendationBasis": decision["recommendationBasis"],
        "scoreDirection": decision["scoreDirection"],
        "weights": decision["weights"],
        "tieBreakOrder": decision["tieBreakOrder"],
        "mappedDecisionRows": mapped_decision_rows,
        "mappedEligibilityRows": mapped_eligibility_rows,
        "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
        "confirmatoryStatisticalWinnerClaimed": False,
        "confirmatoryStatisticalWinnerProductionAlgorithmId": None,
        "forcedWinnerClaimed": False,
        "rulesOrWeightsChanged": False,
        "analysisRecomputed": False,
        "newUnityAcquisitionPerformed": False,
        "gate15Started": False,
    }
    audit = {
        "schema": "gate14re-engineering-recommendation-unblinding-input-audit-v1",
        "studyId": "Gate14Re",
        "attemptId": "attempt-001",
        "authorizationId": authorization["authorizationId"],
        "contractSha256": sha256_file(project_root / REL["contract"]),
        "authorizationSha256": sha256_file(project_root / REL["authorization"]),
        "toolSha256": sha256_file(Path(__file__).resolve()),
        "allFrozenInputHashesVerifiedBeforeDecryption": True,
        "allFrozenInputFilesReadOnlyBeforeDecryption": True,
        "mappingCommitmentVerified": True,
        "formalRawOpened": False,
        "formalBlockOutputsOpened": False,
        "originalPhaseBResultsRecomputed": False,
        "anonymousAnalysisRecomputed": False,
        "onlyFrozenDecisionAndEligibilityMapped": True,
        "originalFormalConclusion": "NO_UNIQUE_WINNER",
        "originalFormalRawModified": False,
        "originalPhaseBModified": False,
        "anonymousPreadjudicationModified": False,
        "gate15Started": False,
    }
    report = render_report(final, release)
    return {
        "unblinding-input-audit.v1.json": audit,
        "label-mapping-release.v1.json": release,
        "final-engineering-recommendation.v1.json": final,
        "Gate14Re_Final_Engineering_Recommendation.zh-CN.v1.md": report,
    }


def render_report(final: Mapping[str, Any], release: Mapping[str, Any]) -> str:
    rows = final["mappedDecisionRows"]
    eligibility = {row["anonymousLabel"]: row for row in final["mappedEligibilityRows"]}
    mapping = {row["anonymousLabel"]: row for row in release["rows"]}
    table_lines = [
        "| 匿名标签 | 真实算法 | 资格 | movement rank | path rank | scaling rank | render rank | 冻结决策分数 | 静态负担 rank |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    by_label = {row["anonymousLabel"]: row for row in rows}
    for anonymous in ANONYMOUS_LABELS:
        prod = mapping[anonymous]["productionAlgorithmId"]
        eligible = "合格" if eligibility[anonymous]["eligible"] else "不合格"
        if anonymous in by_label:
            row = by_label[anonymous]
            values = [row["movementRank"], row["pathRank"], row["scalingRank"], row["renderRank"], row["decisionScore"], row["staticBurdenRank"]]
        else:
            values = ["—", "—", "—", "—", "—", "—"]
        table_lines.append(f"| {anonymous} | {prod} | {eligible} | {values[0]} | {values[1]} | {values[2]} | {values[3]} | {values[4]} | {values[5]} |")
    recommended = final["recommendedProductionAlgorithmId"]
    return "\n".join([
        "# Gate 14Re 最终综合工程推荐 v1",
        "",
        f"**最终综合工程推荐：`{recommended}`。**",
        "",
        "## 结论性质",
        "",
        "本结论是对既有 Gate 14Re 匿名预裁决进行标签解盲后的**事后综合工程推荐**，不是确认性统计赢家。Gate 14Re 原正式结论 `NO_UNIQUE_WINNER` 原样保留；本文件不改写、不替代该正式结论。",
        "",
        "## 冻结裁决映射",
        "",
        *table_lines,
        "",
        f"既有匿名预裁决把 `U43` 选为唯一最低冻结决策分数的候选；经 commitment 核验后的标签映射显示 `U43` 对应 `{recommended}`。因此最终综合工程推荐为 `{recommended}`。这里没有重算指标、改变权重、调整裁决树或新增样本。",
        "",
        "## 证据边界",
        "",
        "- 原确认性统计裁决：`NO_UNIQUE_WINNER`；没有确认性统计赢家。",
        "- 新增结论类型：`POST_HOC_COMPOSITE_ENGINEERING_RECOMMENDATION`。",
        "- 本步骤只解密并核对标签映射，再映射既有匿名排序、资格与冻结决策分数。",
        "- formal raw、原 Phase B、匿名预裁决、冻结规则、权重和结果均未修改。",
        "- 未重新分析、未补采、未启动 Gate 15V-R/OBS。",
        "- 静态工程负担仅保留为冻结的末位 tiebreak 信息；本次推荐由唯一最低冻结决策分数直接确定，并非由新的主观权重产生。",
        "",
    ])


def payload_bytes(value: Any) -> bytes:
    return value.encode("utf-8") if isinstance(value, str) else canonical_json_bytes(value, pretty=True)


def commit_outputs(
    project_root: Path,
    contract: Mapping[str, Any],
    authorization: Mapping[str, Any],
    payloads: Mapping[str, Any],
) -> dict[str, Any]:
    final_root = project_root / REL["output_root"]
    ensure_project_path(project_root, final_root, "OUTPUT_PATH_OUTSIDE_PROJECT")
    require(not final_root.exists(), "OUTPUT_ROOT_ALREADY_EXISTS", str(final_root))
    final_root.parent.mkdir(parents=True, exist_ok=True)
    staging = final_root.parent / (".final-attempt-001.staging-" + str(uuid.uuid4()))
    ensure_project_path(project_root, staging, "STAGING_PATH_OUTSIDE_PROJECT")
    staging.mkdir(parents=False, exist_ok=False)
    try:
        for name, value in payloads.items():
            atomic_create(staging / name, payload_bytes(value))
        records: list[dict[str, Any]] = []
        for path in sorted(staging.iterdir(), key=lambda item: item.name):
            if path.is_file():
                records.append({
                    "relativePath": path.name,
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        tree_payload = b"".join(canonical_json_bytes(record, pretty=False) + b"\n" for record in records)
        atomic_create(staging / "final-canonical-tree.v1.jsonl", tree_payload)
        tree_hash = sha256_file(staging / "final-canonical-tree.v1.jsonl")
        final = payloads["final-engineering-recommendation.v1.json"]
        manifest = {
            "schema": "gate14re-final-engineering-recommendation-manifest-v1",
            "studyId": "Gate14Re",
            "attemptId": "attempt-001",
            "status": "FINAL-POST-HOC-COMPOSITE-ENGINEERING-RECOMMENDATION-COMPLETE",
            "outputRoot": REL["output_root"],
            "contractSha256": sha256_file(project_root / REL["contract"]),
            "authorizationSha256": sha256_file(project_root / REL["authorization"]),
            "toolSha256": sha256_file(Path(__file__).resolve()),
            "anonymousAnalysisReceiptSha256": contract["anonymousPreadjudication"]["analysisReceiptSha256"],
            "anonymousDecisionWorkbookSha256": contract["anonymousPreadjudication"]["decisionWorkbookSha256"],
            "custodyCommitmentSha256": contract["labelCustody"]["commitmentFileSha256"],
            "mappingCommitmentSha256": contract["labelCustody"]["mappingCommitmentSha256"],
            "payloadRecords": len(records),
            "payloadBytes": sum(int(row["bytes"]) for row in records),
            "canonicalTreeSha256": tree_hash,
            "recommendedProductionAlgorithmId": final["recommendedProductionAlgorithmId"],
            "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
            "confirmatoryStatisticalWinnerClaimed": False,
        }
        write_json(staging / "final-manifest.v1.json", manifest)
        manifest_hash = sha256_file(staging / "final-manifest.v1.json")
        receipt = {
            "schema": "gate14re-engineering-recommendation-unblinding-receipt-v1",
            "studyId": "Gate14Re",
            "attemptId": "attempt-001",
            "authorizationId": authorization["authorizationId"],
            "status": "FINAL-ENGINEERING-RECOMMENDATION-COMPLETE / ORIGINAL-NO-UNIQUE-WINNER-PRESERVED / IMMUTABLE",
            "completedUtc": utc_now(),
            "outputRoot": REL["output_root"],
            "finalManifestSha256": manifest_hash,
            "finalCanonicalTreeSha256": tree_hash,
            "mappingCommitmentVerified": True,
            "dpapiDecryptOperations": 1,
            "recommendedProductionAlgorithmId": final["recommendedProductionAlgorithmId"],
            "recommendationClassification": "POST_HOC_COMPOSITE_ENGINEERING_RECOMMENDATION",
            "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
            "confirmatoryStatisticalWinnerClaimed": False,
            "rawRootModified": False,
            "originalPhaseBModified": False,
            "anonymousPreadjudicationModified": False,
            "rulesOrWeightsChanged": False,
            "analysisRecomputed": False,
            "newUnityAcquisitionPerformed": False,
            "gate15Started": False,
        }
        write_json(staging / "unblinding-receipt.v1.json", receipt)
        # Recheck every frozen binding after all release artifacts are built and
        # before the staging directory is atomically committed.
        verify_all_bindings(project_root, contract)
        for path in staging.iterdir():
            if path.is_file():
                set_read_only(path)
        os.replace(staging, final_root)
        for path in final_root.iterdir():
            if path.is_file():
                require(is_read_only(path), "COMMITTED_OUTPUT_NOT_READONLY", path.name)
        return {
            "status": "PASS",
            "outputRoot": REL["output_root"],
            "recommendedProductionAlgorithmId": final["recommendedProductionAlgorithmId"],
            "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
            "confirmatoryStatisticalWinnerClaimed": False,
        }
    except BaseException:
        if staging.exists() and staging.parent.resolve() == final_root.parent.resolve():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def run_formal(project_root: Path) -> dict[str, Any]:
    final_root = project_root / REL["output_root"]
    require(not final_root.exists(), "OUTPUT_ROOT_ALREADY_EXISTS", str(final_root))
    contract, authorization = load_authorized_context(project_root)
    decision, eligibility, production = verify_frozen_semantics(project_root, contract)
    source_to_anonymous, commitment = decode_mapping_once(project_root, contract)
    require(
        reconstruct_secret_commitment(source_to_anonymous, str(commitment["custodyId"]))
        == str(commitment["mappingCommitmentSha256"]),
        "RECONSTRUCTED_MAPPING_COMMITMENT",
    )
    payloads = mapped_payloads(
        project_root,
        contract,
        authorization,
        decision,
        eligibility,
        production,
        source_to_anonymous,
        commitment,
    )
    return commit_outputs(project_root, contract, authorization, payloads)


def verify_tree(root: Path, manifest: Mapping[str, Any]) -> None:
    tree_path = root / "final-canonical-tree.v1.jsonl"
    require(sha256_file(tree_path) == manifest["canonicalTreeSha256"], "VERIFY_TREE_HASH")
    records = [json.loads(line) for line in tree_path.read_text(encoding="utf-8").splitlines() if line]
    require(len(records) == manifest["payloadRecords"], "VERIFY_TREE_RECORD_COUNT")
    for row in records:
        path = root / str(row["relativePath"])
        require(path.is_file(), "VERIFY_PAYLOAD_MISSING", str(row["relativePath"]))
        require(path.stat().st_size == int(row["bytes"]), "VERIFY_PAYLOAD_BYTES", str(row["relativePath"]))
        require(sha256_file(path) == row["sha256"], "VERIFY_PAYLOAD_HASH", str(row["relativePath"]))
        require(is_read_only(path), "VERIFY_PAYLOAD_NOT_READONLY", str(row["relativePath"]))


def verify_existing(project_root: Path) -> dict[str, Any]:
    contract, authorization = load_authorized_context(project_root)
    decision, eligibility, production = verify_frozen_semantics(project_root, contract)
    root = project_root / REL["output_root"]
    require(root.is_dir(), "EXISTING_OUTPUT_ROOT_MISSING")
    release = load_json(root / "label-mapping-release.v1.json")
    rows = release.get("rows")
    require(isinstance(rows, list) and len(rows) == 4, "VERIFY_MAPPING_ROWS")
    source_to_anonymous = {str(row["sourceLabel"]): str(row["anonymousLabel"]) for row in rows}
    commitment = load_json(project_root / REL["custody_commitment"])
    require(
        reconstruct_secret_commitment(source_to_anonymous, str(commitment["custodyId"]))
        == str(commitment["mappingCommitmentSha256"]),
        "VERIFY_MAPPING_COMMITMENT",
    )
    expected = mapped_payloads(
        project_root,
        contract,
        authorization,
        decision,
        eligibility,
        production,
        source_to_anonymous,
        commitment,
    )
    for name, value in expected.items():
        path = root / name
        require(path.is_file(), "VERIFY_EXPECTED_OUTPUT_MISSING", name)
        require(path.read_bytes() == payload_bytes(value), "VERIFY_EXPECTED_OUTPUT_MISMATCH", name)
        require(is_read_only(path), "VERIFY_EXPECTED_OUTPUT_NOT_READONLY", name)
    manifest = load_json(root / "final-manifest.v1.json")
    receipt = load_json(root / "unblinding-receipt.v1.json")
    require(manifest.get("status") == "FINAL-POST-HOC-COMPOSITE-ENGINEERING-RECOMMENDATION-COMPLETE", "VERIFY_MANIFEST_STATUS")
    require(receipt.get("status") == "FINAL-ENGINEERING-RECOMMENDATION-COMPLETE / ORIGINAL-NO-UNIQUE-WINNER-PRESERVED / IMMUTABLE", "VERIFY_RECEIPT_STATUS")
    require(receipt.get("dpapiDecryptOperations") == 1, "VERIFY_DECRYPT_COUNT")
    require(receipt.get("confirmatoryStatisticalWinnerClaimed") is False, "VERIFY_CONFIRMATORY_CLAIM")
    require(receipt.get("originalFormalConclusionPreserved") == "NO_UNIQUE_WINNER", "VERIFY_ORIGINAL_CONCLUSION")
    require(receipt.get("finalManifestSha256") == sha256_file(root / "final-manifest.v1.json"), "VERIFY_MANIFEST_HASH")
    require(receipt.get("finalCanonicalTreeSha256") == sha256_file(root / "final-canonical-tree.v1.jsonl"), "VERIFY_CANONICAL_TREE_HASH")
    verify_tree(root, manifest)
    for path in root.iterdir():
        if path.is_file():
            require(is_read_only(path), "VERIFY_OUTPUT_NOT_READONLY", path.name)
    verify_all_bindings(project_root, contract)
    return {
        "status": "PASS",
        "verifiedExisting": True,
        "dpapiDecryptionPerformedDuringVerification": False,
        "recommendedProductionAlgorithmId": receipt["recommendedProductionAlgorithmId"],
        "originalFormalConclusionPreserved": "NO_UNIQUE_WINNER",
    }


def run_self_test(receipt_path: Path | None) -> dict[str, Any]:
    source_to_anonymous = {"A": "U29", "B": "U61", "C": "U17", "D": "U43"}
    production = {"A": "A*-R", "B": "D*L", "C": "C-FF", "D": "IDFF"}
    inverse = {anonymous: source for source, anonymous in source_to_anonymous.items()}
    require(inverse["U43"] == "D", "SELFTEST_INVERSION")
    require(production[inverse["U43"]] == "IDFF", "SELFTEST_PRODUCTION_MAPPING")
    secret = {
        "schema": "gate14re-engineering-recommendation-label-secret-v1",
        "studyId": "Gate14Re",
        "custodyId": "synthetic",
        "mapping": [
            {"sourceLabel": source, "anonymousLabel": source_to_anonymous[source]}
            for source in SOURCE_LABELS
        ],
    }
    digest = hashlib.sha256(canonical_json_bytes(secret, pretty=False)).hexdigest()
    require(reconstruct_secret_commitment(source_to_anonymous, "synthetic") == digest, "SELFTEST_COMMITMENT")
    payload = {
        "schema": "gate14re-engineering-recommendation-unblinding-self-test-receipt-v1",
        "status": "PASS",
        "completedUtc": utc_now(),
        "assertions": 3,
        "actualCustodyOpened": False,
        "dpapiDecryptionPerformed": False,
        "formalRawOpened": False,
        "anonymousOutcomeOpened": False,
    }
    if receipt_path is not None:
        write_json(receipt_path, payload)
        set_read_only(receipt_path)
    return payload


def write_failure(project_root: Path, mode: str, error: BaseException) -> Path | None:
    root = project_root / REL["verification_root"]
    ensure_project_path(project_root, root, "FAILURE_ROOT_OUTSIDE_PROJECT")
    root.mkdir(parents=True, exist_ok=True)
    path = root / ("unblinding-failure-receipt." + str(uuid.uuid4()) + ".json")
    payload = {
        "schema": "gate14re-engineering-recommendation-unblinding-failure-receipt-v1",
        "status": "FAIL_CLOSED",
        "mode": mode,
        "failedUtc": utc_now(),
        "errorType": type(error).__name__,
        "errorCode": error.code if isinstance(error, UnblindingError) else "UNEXPECTED_ERROR",
        "detail": str(error),
        "formalRawModified": False,
        "originalPhaseBModified": False,
        "anonymousPreadjudicationModified": False,
        "newAcquisitionPerformed": False,
        "gate15Started": False,
    }
    try:
        write_json(path, payload)
        set_read_only(path)
        return path
    except BaseException:
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="One-time Gate14Re final engineering recommendation unblinding")
    parser.add_argument("--project-root", default=str(PROJECT_ROOT_DEFAULT))
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--formal", action="store_true")
    modes.add_argument("--verify-existing", action="store_true")
    parser.add_argument("--receipt")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root).resolve()
    mode = "self-test" if args.self_test else "formal" if args.formal else "verify-existing"
    try:
        if args.self_test:
            result = run_self_test(Path(args.receipt).resolve() if args.receipt else None)
        elif args.formal:
            result = run_formal(project_root)
        else:
            result = verify_existing(project_root)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except BaseException as error:
        failure = None if args.self_test else write_failure(project_root, mode, error)
        print(
            json.dumps(
                {
                    "status": "FAIL_CLOSED",
                    "mode": mode,
                    "error": str(error),
                    "failureReceipt": str(failure) if failure else None,
                },
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        if not isinstance(error, UnblindingError):
            traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
