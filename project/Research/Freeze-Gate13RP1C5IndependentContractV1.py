#!/usr/bin/env python3
"""Create the prospective frozen execution contract without launching Unity."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CONTRACT_REL = "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json"
FORMAL_ROOT_REL = "Research/FormalRuns/Gate13R_P1C5_Independent/v1"
RECEIPT_REL = "Research/Gate13R_P1C5_Independent_Execution_Receipt.v1.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def binding(project: Path, relative: str) -> dict[str, str]:
    path = project / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"relativePath": relative, "sha256": sha256_file(path)}


def runtime_binding(path_text: str) -> dict[str, Any]:
    path = Path(path_text).resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"absolutePath": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--python-path", required=True)
    parser.add_argument("--unity-path", required=True)
    parser.add_argument("--powershell-path", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    contract_path = project / CONTRACT_REL
    formal_root = project / FORMAL_ROOT_REL
    receipt = project / RECEIPT_REL
    if contract_path.exists():
        raise FileExistsError(contract_path)
    if formal_root.exists() or receipt.exists():
        raise RuntimeError("formal raw root and receipt must be absent at prospective freeze")

    paths = {
        "design": "Research/Gate13R_P1C5_Independent_Design.v1.json",
        "userAuthorization": "Research/Gate13R_P1C5_Independent_User_Authorization.v1.json",
        "statisticalAnalysisPlan": "Research/Gate13R_P1C5_Independent_Statistical_Analysis_Plan.v1.md",
        "preparationProgram": "Research/Prepare-Gate13RP1C5IndependentV1.py",
        "powerSimulation": "Research/Gate13R_P1C5_Independent_Power_Simulation.v1.json",
        "schedule": "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl",
        "scheduleManifest": "Research/Gate13R_P1C5_Independent_Schedule_Manifest.v1.json",
        "schedulePolicyOverlay": "Research/Gate13R_P1C5_Independent_Schedule_Policy_Overlay.v1.jsonl",
        "unityCommand": "Assets/_Scripts/Research/Editor/Gate13RP1C5FormalBatchCommandV1.cs",
        "blockPlanBuilder": "Research/New-Gate13RP1C5IndependentBlockPlanV1.py",
        "blockWrapper": "Research/Run-Gate13RP1C5IndependentBlockV1.ps1",
        "phaseAOrchestrator": "Research/Gate13RP1C5IndependentExecutionV1.py",
        "phaseALauncher": "Research/Run-Gate13RP1C5IndependentV1.ps1",
        "phaseBAnalyzer": "Research/Analyze-Gate13RP1C5IndependentPhaseBV1.py",
        "preflightProgram": "Research/Test-Gate13RP1C5IndependentPreflightV1.py",
        "contractFreezer": "Research/Freeze-Gate13RP1C5IndependentContractV1.py",
        "memoryPolicyModule": "Research/Gate13RPR2MP2MemoryPolicyV2.psm1",
        "lockHygieneModule": "Research/Gate10RLockHygieneV3.psm1",
        "memoryPolicyRegistry": "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json",
        "scenarioPolicyMapping": "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json",
        "planningVarianceSource": "Research/Analysis/Gate13R_RQAligned_Preregistration/v1/candidate-design-sensitivity.json",
        "sourceSchedule": "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl",
        "sourceSchedulePolicyOverlay": "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl",
        "attempt4ExecutionContractPreservationReference": "Research/Gate13R_PR2_Attempt4_Execution_Contract.v1.json",
    }
    bindings = {label: binding(project, relative) for label, relative in paths.items()}
    power = json.loads((project / paths["powerSimulation"]).read_text(encoding="utf-8-sig"))
    schedule_manifest = json.loads((project / paths["scheduleManifest"]).read_text(encoding="utf-8-sig"))
    if power.get("passed") is not True or power.get("selectedBlocksPerCampaign") != 50:
        raise RuntimeError("power freeze did not retain 50 blocks per campaign")
    if schedule_manifest.get("unityProcessCount") != 1600 or schedule_manifest.get("algorithmSampleCount") != 3200:
        raise RuntimeError("schedule cardinality differs from the confirmed design")

    contract = {
        "schemaVersion": 1,
        "contractKind": "GATE13R-P1C5-INDEPENDENT-FROZEN-EXECUTION-CONTRACT",
        "contractId": "gate13r-p1c5-independent-confirmatory-study-execution-v1",
        "studyId": "Gate13R-P1C5-Independent-v1",
        "createdAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": "FROZEN-PRELAUNCH-NOT-EXECUTED",
        "formalRootRelativePath": FORMAL_ROOT_REL,
        "receiptRelativePath": RECEIPT_REL,
        "formalDesign": {
            "alphaTwoSided": 0.05,
            "targetPower": 0.90,
            "minimumDetectableRatioSymmetric": 1.10,
            "campaignCount": 32,
            "blocksPerCampaign": 50,
            "abBlocksPerCampaign": 25,
            "baBlocksPerCampaign": 25,
            "unityProcessCount": 1600,
            "algorithmSampleCount": 3200,
            "strictSerial": True,
            "maximumConcurrentUnityEditorProcesses": 1,
            "maximumBlocksPerUnityEditorProcess": 1,
            "independentExperimentalUnit": "fresh Unity process paired block",
            "scheduleSha256": bindings["schedule"]["sha256"],
            "powerSimulationSha256": bindings["powerSimulation"]["sha256"],
        },
        "powerAdjustmentOutcome": {
            "minimumBlocksPerCampaign": 50,
            "selectedBlocksPerCampaign": power["selectedBlocksPerCampaign"],
            "minimumDirectionalOneSided95WilsonLower": power["iterations"][-1]["minimumDirectionalOneSided95WilsonLower"],
            "sampleSizeIncreased": power["selectedBlocksPerCampaign"] > 50,
        },
        "phaseAAcquisitionAuthorizedByStudyScope": True,
        "exactLaunchCommandConfirmationPending": True,
        "automaticRetryAuthorized": False,
        "automaticResumeAuthorized": False,
        "topUpAuthorized": False,
        "replacementAuthorized": False,
        "reorderAuthorized": False,
        "crossStudyRawMergeAuthorized": False,
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
        "failurePolicy": "FAIL-CLOSED-STOP-NO-RETRY-NO-RESUME-USER-ACTION-REQUIRED",
        "missingBlockAnalysisPolicy": "NOT-ESTIMABLE-USER-ACTION-REQUIRED",
        "runtime": {
            "python": runtime_binding(args.python_path),
            "unity": runtime_binding(args.unity_path),
            "nativeWindowsPowerShell": runtime_binding(args.powershell_path),
            "blockTimeoutSeconds": 3600,
            "overallTimeoutSeconds": 64800,
            "hardTimeoutMayTerminateOnlyTheOwnedUnityProcess": True,
        },
        "monitorFilesRelativeToFormalRoot": [
            "_control/execution-status.json",
            "_control/failure.json",
            "raw-data-complete.json"
        ],
        "phaseB": {
            "implementationFrozenBeforePhaseA": True,
            "requiresSeparatePostAcquisitionAuthorization": True,
            "rawRootReadOnly": True,
            "analysisRootRelativePath": "Research/Analysis/Gate13R_P1C5_Independent/v1",
            "confirmatoryDecisionRule": {
                "ciEntirelyBelowOne": "IDFF-LOWER-P1-CONFIRMED",
                "ciEntirelyAboveOne": "CFF-LOWER-P1-CONFIRMED",
                "ciIncludesOne": "UNRESOLVED"
            }
        },
        "bindings": bindings,
    }
    contract_path.write_text(json.dumps(contract, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "contract": str(contract_path), "sha256": sha256_file(contract_path), "unityInvoked": False}, sort_keys=True))


if __name__ == "__main__":
    main()
