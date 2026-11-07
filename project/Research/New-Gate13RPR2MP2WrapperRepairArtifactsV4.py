#!/usr/bin/env python3
"""Create deterministic MP2 V4 candidate bindings for the lock-hygiene wrapper repair.

The policy, scenario mapping, schedule overlay, Unity command, and frozen schedule
remain byte-identical. This generator only supersedes the V2 execution-wrapper
binding after validation attempt 2 exposed a role-specific acceptance defect.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any


FROZEN_AT_UTC = "2026-10-09T06:23:00.0000000Z"

EXPECTED_INPUTS = {
    "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v2.json": "95bd85dd0ac506055e5a417c4df8092f6f1e33deb2c04f26c5db094518c6bd59",
    "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v2.json": "262f4d896f13156bc0018a71303ee9e3e954ab503409fa60df1f1f0c7ce0e818",
    "Research/Gate13R_PR2_MP2_Provenance.v2.json": "c6c7f90596708183debace5063d322903c9ce39ac9ff0998783b4067fe1cd010",
    "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl": "c87cc7eab158dc7a111867364b9c06c2314f44c644ef2a4b8e33348bd1876d13",
    "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json": "1070821ef6264510eb2e7427d7887aaca08bb5d2e7854d48f61a6c8e1285490f",
    "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json": "5dd5daf640831ea49d5fa9e0bb1a318e71669ee9e426bf346f7eebc36f0c5055",
    "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/failure-receipt.json": "ab58b5a7f7176b0ec18022cb9bdbd630fcc92169c4adf177074641e8ff4dadef",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/checkpoint.json": "0e7ade1b1e69624fdec04981c1fad665125cfcb9819e6325a419ee5d94ed8caf",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/partial-output-manifest.json": "20d18158d7bc57037f2c0bc57b494c1ff8ea45030301719b8de4bc4347ab50e8",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/failure-receipt.json": "3099ec62b371355368a8b1353d643e82ae200dca1434ff4b7bf462a7f24c9735",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/checkpoint.json": "fb46898ad0d9fd16019b5ded49004b6576dbc6aaa8924aa8618946710f074c6f",
    "Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/partial-output-manifest.json": "a233ba0e297d5b12841275b8e0e983ef96bd7c4e143db5b606d6212cdb27989c",
}

IMPLEMENTATION_FILES = (
    "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1",
    "Research/New-Gate13RPR2MP2BlockPlanV4.py",
    "Research/New-Gate13RPR2MP2WrapperRepairArtifactsV4.py",
    "Research/Test-Gate13RPR2MP2V4.py",
    "Research/Gate13RPR2MP2MemoryPolicyV2.psm1",
    "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def binding(project: Path, relative: str) -> dict[str, Any]:
    path = project / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"relativePath": relative, "rawBytes": path.stat().st_size, "sha256": sha256_file(path)}


def generated_binding(relative: str, data: bytes) -> dict[str, Any]:
    return {"relativePath": relative, "rawBytes": len(data), "sha256": sha256_bytes(data)}


def atomic_create(path: Path, data: bytes) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13r-pr2-mp2-v3-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def build(project: Path) -> dict[str, bytes]:
    input_bindings: dict[str, dict[str, Any]] = {}
    for relative, expected in EXPECTED_INPUTS.items():
        item = binding(project, relative)
        if item["sha256"] != expected:
            raise ValueError(f"frozen input SHA-256 mismatch: {relative}")
        input_bindings[relative] = item
    implementation = {relative: binding(project, relative) for relative in IMPLEMENTATION_FILES}

    repair = {
        "schemaVersion": 1,
        "amendmentId": "gate13r-pr2-mp2-expected-negative-lock-hygiene-wrapper-repair-v1",
        "frozenAtUtc": FROZEN_AT_UTC,
        "status": "VERSIONED-VALIDATION-ONLY-REPAIR / POLICY-UNCHANGED / FORMAL-CAMPAIGN-NOT-AUTHORIZED",
        "failedAttempt": {
            "attemptId": "gate13r-pr2-mp2-validation-attempt-2",
            "failureCode": "EXPECTED-NEGATIVE-CONTROLLED-LOCK-CLEANUP-REJECTED-BY-WRAPPER",
            "failureReceipt": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/failure-receipt.json"],
            "checkpoint": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/checkpoint.json"],
            "partialOutputManifest": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-2/partial-output-manifest.json"],
        },
        "generatorValidationHistory": {
            "attemptId": "gate13r-pr2-mp2-validation-attempt-3",
            "failureCode": "FROZEN-V2-PROVENANCE-SHA256-TRANSCRIPTION-MISMATCH",
            "failureReceipt": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/failure-receipt.json"],
            "checkpoint": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/checkpoint.json"],
            "partialOutputManifest": input_bindings["Research/Verification/Gate13R_PR2_MP2/v1/attempt-3/partial-output-manifest.json"],
            "candidateArtifactsCreated": False,
            "scientificContractChanged": False,
        },
        "rootCause": "The V2 wrapper required natural-lock-absence for every role although the frozen Gate10R lock-hygiene module explicitly returns a passed controlled-expected-negative-cleanup outcome for eligible expected-negative exits.",
        "repair": {
            "positiveRoleAcceptedModes": ["natural-lock-absence"],
            "expectedNegativeRoleAcceptedModes": ["natural-lock-absence", "controlled-expected-negative-cleanup"],
            "passedTrueRequired": True,
            "exactLiteralLockCleanupOnly": True,
            "recursiveCleanupAllowed": False,
            "wildcardCleanupAllowed": False,
            "otherRoleRelaxationAllowed": False,
        },
        "unchangedContracts": [
            "memory-policy thresholds and precedence",
            "S48/H48 schedule and identities",
            "one fresh Unity process per complete block",
            "two-stage raw/analysis commit",
            "no auto retry/resume/top-up/merge",
            "formal attempt-3 root/receipt absence",
        ],
        "supersedesForFutureUse": input_bindings["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v2.json"],
    }
    repair_name = "Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json"
    repair_bytes = stable_json_bytes(repair)
    repair_binding = generated_binding(f"Research/{repair_name}", repair_bytes)

    base_candidate = json.loads((project / "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v2.json").read_text(encoding="utf-8-sig"))
    candidate = copy.deepcopy(base_candidate)
    candidate["configId"] = "gate13r-pr2-rq-aligned-s48-h48-mp2-attempt3-candidate-v4"
    candidate["configKind"] = "gate13r-pr2-mp2-nonexecuting-formal-attempt3-candidate-config-v4"
    candidate["generatedAtUtc"] = FROZEN_AT_UTC
    candidate["mp2Bindings"]["executionAdapter"] = implementation["Research/Run-Gate13RPR2MP2FormalBlockV3.ps1"]
    candidate["mp2Bindings"]["blockPlanBuilder"] = implementation["Research/New-Gate13RPR2MP2BlockPlanV4.py"]
    candidate["mp2Bindings"]["wrapperRepairAmendment"] = repair_binding
    candidate["validationRepairHistory"] = {
        "attempt1": "FAILED-STATIC-RAW-STAGE-REASON; PRESERVED",
        "attempt2": "FAILED-WRAPPER-LOCK-HYGIENE-ACCEPTANCE; PRESERVED",
        "attempt3": "FAILED-PREWRITE-FROZEN-HASH-TRANSCRIPTION; PRESERVED",
        "activeRepair": repair_binding,
        "policyOrScientificContractChanged": False,
    }
    candidate_name = "Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"
    candidate_bytes = stable_json_bytes(candidate)
    candidate_binding = generated_binding(f"Research/{candidate_name}", candidate_bytes)

    adapter = {
        "schemaVersion": 1,
        "adapterId": "gate13r-pr2-mp2-formal-attempt3-candidate-block-adapter-v4",
        "status": "IMPLEMENTED-NOT-AUTHORIZED-FOR-FORMAL-LAUNCH",
        "candidateConfig": candidate_binding,
        "schedule": input_bindings["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"],
        "overlay": input_bindings["Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"],
        "powerShellWrapper": implementation["Research/Run-Gate13RPR2MP2FormalBlockV3.ps1"],
        "blockPlanBuilder": implementation["Research/New-Gate13RPR2MP2BlockPlanV4.py"],
        "unityCommand": implementation["Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs"],
        "policyModule": implementation["Research/Gate13RPR2MP2MemoryPolicyV2.psm1"],
        "wrapperRepairAmendment": repair_binding,
        "createsFormalRoot": False,
        "createsFormalReceipt": False,
        "formalModeRequiresSeparateAttempt3Receipt": True,
        "validationModeRequiresIndependentVerificationRoot": True,
    }
    adapter_name = "Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json"
    adapter_bytes = stable_json_bytes(adapter)
    adapter_binding = generated_binding(f"Research/{adapter_name}", adapter_bytes)

    provenance = {
        "schemaVersion": 1,
        "provenanceId": "gate13r-pr2-mp2-nonexecuting-formal-attempt3-readiness-provenance-v4",
        "generatedAtUtc": FROZEN_AT_UTC,
        "status": "NON-EXECUTING / FORMAL-CAMPAIGN-NOT-AUTHORIZED",
        "inputs": input_bindings,
        "implementation": implementation,
        "outputsExcludingThisProvenance": {
            repair_name: repair_binding,
            candidate_name: candidate_binding,
            adapter_name: adapter_binding,
        },
        "scheduleValidation": {"campaignCount": 74, "processCount": 3552, "sampleCount": 10176, "matchedSuperblockCount": 1008},
        "repairBoundary": "ROLE-SPECIFIC-EXPECTED-NEGATIVE-LOCK-HYGIENE-ACCEPTANCE-ONLY",
        "formalAttempt3RootCreated": False,
        "formalAttempt3ReceiptCreated": False,
        "formalAttempt3MeasuredCampaignExecuted": False,
        "formalStatisticalAnalysisExecuted": False,
        "gate14RExecuted": False,
    }
    provenance_name = "Gate13R_PR2_MP2_Provenance.v4.json"
    provenance_bytes = stable_json_bytes(provenance)
    return {
        repair_name: repair_bytes,
        candidate_name: candidate_bytes,
        adapter_name: adapter_bytes,
        provenance_name: provenance_bytes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output = Path(args.output_dir).resolve()
    generated = build(project)
    for name, data in generated.items():
        atomic_create(output / name, data)
    print(json.dumps({"passed": True, "fileCount": len(generated), "files": {name: sha256_bytes(data) for name, data in sorted(generated.items())}}, sort_keys=True))


if __name__ == "__main__":
    main()
