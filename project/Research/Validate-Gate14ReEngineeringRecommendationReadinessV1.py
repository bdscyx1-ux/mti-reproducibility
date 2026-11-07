#!/usr/bin/env python3
"""Independent pre-outcome readiness validator for Gate14Re engineering recommendation v1."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat
from typing import Any


PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parents[1]
CONTRACT_REL = "Research/Gate14Re/EngineeringRecommendation/Gate14Re_Engineering_Recommendation_Contract.v1.json"
READINESS_REL = "Research/Verification/Gate14Re/engineering-recommendation-readiness-attempt-001/final-readiness.v1.json"


def require(condition: bool, code: str) -> None:
    if not condition:
        raise RuntimeError(code)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def is_read_only(path: Path) -> bool:
    attrs = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attrs & getattr(stat, "FILE_ATTRIBUTE_READONLY", 1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(PROJECT_ROOT_DEFAULT))
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    contract_path = root / CONTRACT_REL
    require(contract_path.is_file(), "CONTRACT_MISSING")
    contract = load_json(contract_path)
    require(contract.get("schema") == "gate14re-engineering-recommendation-contract-v1", "CONTRACT_SCHEMA")
    require(contract.get("status") == "FROZEN_BEFORE_DERIVED_OUTCOME_ACCESS", "CONTRACT_STATUS")
    require(contract["formalConclusionBoundary"]["originalWinnerAdjudication"] == "NO_UNIQUE_WINNER", "ORIGINAL_CONCLUSION_BOUNDARY")
    require(contract["formalConclusionBoundary"]["originalRawMayBeModified"] is False, "RAW_WRITE_BOUNDARY")
    require(contract["formalConclusionBoundary"]["originalPhaseBMayBeModified"] is False, "PHASEB_WRITE_BOUNDARY")
    require(contract["authorizationScope"]["anonymousReadOnlyAnalysisAuthorized"] is True, "ANONYMOUS_SCOPE")
    require(contract["authorizationScope"]["unblindingAuthorized"] is False, "UNBLIND_SCOPE")
    require(contract["authorizationScope"]["finalProductionRecommendationAuthorized"] is False, "FINAL_SCOPE")
    require(contract["preparationBoundary"]["formalBlockOutputOpenedOrParsedBeforeContractFreeze"] is False, "PREOUTCOME_BOUNDARY")
    require(contract["preparationBoundary"]["scientificChoicesPending"] == [], "PENDING_CHOICES")

    plan = contract["narrativePlan"]
    plan_path = root / plan["path"]
    require(plan_path.is_file() and plan_path.stat().st_size == int(plan["bytes"]), "PLAN_BINDING")
    require(sha256_file(plan_path) == plan["sha256"], "PLAN_HASH")

    analyzer = contract["analyzer"]
    analyzer_path = root / analyzer["path"]
    require(analyzer_path.is_file() and analyzer_path.stat().st_size == int(analyzer["bytes"]), "ANALYZER_BINDING")
    require(sha256_file(analyzer_path) == analyzer["sha256"] == contract["analyzerSha256"], "ANALYZER_HASH")

    bindings = contract["frozenInputBindings"]
    for key, binding in bindings.items():
        path = root / binding["path"]
        require(path.is_file(), "INPUT_MISSING_" + key)
        require(sha256_file(path) == binding["sha256"], "INPUT_HASH_" + key)
        require(is_read_only(path), "INPUT_NOT_READONLY_" + key)

    custody = contract["labelCustody"]
    commitment_path = root / custody["commitmentPath"]
    payload_path = root / custody["payloadPath"]
    entropy_path = root / custody["entropyPath"]
    require(sha256_file(commitment_path) == custody["commitmentSha256"], "CUSTODY_COMMITMENT_HASH")
    require(sha256_file(payload_path) == custody["payloadSha256"], "CUSTODY_PAYLOAD_HASH")
    require(sha256_file(entropy_path) == custody["entropySha256"], "CUSTODY_ENTROPY_HASH")
    require(all(is_read_only(path) for path in (commitment_path, payload_path, entropy_path)), "CUSTODY_NOT_READONLY")
    commitment = load_json(commitment_path)
    require(commitment.get("status") == "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED", "CUSTODY_STATUS")
    require(commitment.get("plaintextMappingPersisted") is False, "CUSTODY_PLAINTEXT")
    require(commitment.get("mappingReleased") is False and commitment.get("unblindingAuthorized") is False, "CUSTODY_RELEASE")
    require(commitment.get("mappingCommitmentSha256") == custody["mappingCommitmentSha256"], "CUSTODY_MAPPING_COMMITMENT")

    for row in contract["staticEngineeringTiebreak"]["sourceBindings"]:
        path = root / row["path"]
        require(path.is_file() and sha256_file(path) == row["sha256"], "STATIC_SOURCE_BINDING")

    validation = contract["software"]["syntheticValidationReceipt"]
    validation_path = root / validation["path"]
    require(validation_path.is_file() and sha256_file(validation_path) == validation["sha256"], "SYNTHETIC_VALIDATION_BINDING")
    validation_receipt = load_json(validation_path)
    require(validation_receipt.get("status") == "PASS", "SYNTHETIC_VALIDATION_STATUS")
    require(validation_receipt.get("formalRawOpened") is False and validation_receipt.get("formalOutcomeAccessed") is False, "SYNTHETIC_OUTCOME_BOUNDARY")

    require(not (root / contract["analysisRoot"]).exists(), "ANALYSIS_ROOT_PREEXISTS")
    receipt = {
        "schema": "gate14re-engineering-recommendation-final-readiness-v1",
        "studyId": "Gate14Re",
        "status": "PASS_READY_FOR_ONE_ANONYMOUS_READ_ONLY_ANALYSIS",
        "validatedUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "contractPath": CONTRACT_REL,
        "contractSha256": sha256_file(contract_path),
        "planPath": plan["path"],
        "planSha256": plan["sha256"],
        "analyzerPath": analyzer["path"],
        "analyzerSha256": analyzer["sha256"],
        "validatorPath": Path(__file__).resolve().relative_to(root).as_posix(),
        "validatorSha256": sha256_file(Path(__file__).resolve()),
        "syntheticValidationReceiptSha256": validation["sha256"],
        "custodyCommitmentSha256": custody["commitmentSha256"],
        "rawCanonicalTreeSha256": bindings["rawCanonicalTree"]["sha256"],
        "originalPhaseBReceiptSha256": bindings["phaseBReceipt"]["sha256"],
        "formalBlockOutputOpenedOrParsed": False,
        "derivedOutcomeAccessed": False,
        "labelMappingReleased": False,
        "unblindingAuthorized": False,
        "finalProductionRecommendationAuthorized": False,
        "newUnityAcquisitionAuthorized": False,
        "scientificChoicesPending": [],
    }
    output = root / READINESS_REL
    require(not output.exists(), "READINESS_ALREADY_EXISTS")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream:
        stream.write(canonical(receipt))
        stream.flush()
        os.fsync(stream.fileno())
    print(json.dumps({"status": "PASS", "readiness": READINESS_REL}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
