#!/usr/bin/env python3
"""Create one receipt-gated P1-C5 block plan from the frozen schedule.

The builder never creates the formal root or execution receipt and cannot launch Unity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any


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


def read_record(path: Path, ordinal: int) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for index, line in enumerate(stream, start=1):
            if index == ordinal:
                value = json.loads(line)
                if int(value["globalProcessOrdinal"]) != ordinal:
                    raise ValueError("global process ordinal differs from line ordinal")
                return value
    raise IndexError(ordinal)


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    if not path.parent.is_dir():
        raise FileNotFoundError(path.parent)
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13r-p1c5-plan-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--global-process-ordinal", type=int, required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()

    project = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    formal_root = (project / "Research/FormalRuns/Gate13R_P1C5_Independent/v1").resolve()
    formal_receipt = (project / "Research/Gate13R_P1C5_Independent_Execution_Receipt.v1.json").resolve()
    schedule_rel = "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl"
    overlay_rel = "Research/Gate13R_P1C5_Independent_Schedule_Policy_Overlay.v1.jsonl"
    schedule = read_record(project / schedule_rel, args.global_process_ordinal)
    overlay = read_record(project / overlay_rel, args.global_process_ordinal)
    if any(str(schedule[key]) != str(overlay[key]) for key in ("globalProcessOrdinal", "blockId", "campaignId", "scenarioId", "scenarioRelativePath")):
        raise ValueError("schedule/overlay identity mismatch")
    if [entry["runId"] for entry in schedule["entries"]] != overlay["expectedRunIds"]:
        raise ValueError("schedule/overlay run identity mismatch")

    scenario_path = project / schedule["scenarioRelativePath"]
    scenario = json.loads(scenario_path.read_text(encoding="utf-8-sig"))
    if sha256_file(scenario_path) != overlay["scenarioSourceSha256"]:
        raise ValueError("scenario source hash mismatch")
    if max(int(scenario["gridWidth"]), int(scenario["gridHeight"])) != int(overlay["canonicalMaximumGridDimension"]):
        raise ValueError("scenario dimension mapping mismatch")

    if not formal_root.is_dir() or not formal_receipt.is_file():
        raise ValueError("formal mode requires the newly created study root and receipt")
    if Path(args.receipt).resolve() != formal_receipt:
        raise ValueError("formal receipt identity mismatch")
    if not is_within(output, formal_root):
        raise ValueError("formal plan must remain below the independent-study root")
    receipt_relative = formal_receipt.relative_to(project).as_posix()
    receipt_sha = sha256_file(formal_receipt)

    config = binding(project, "Research/Gate13R_P1C5_Independent_Design.v1.json")
    specification = binding(project, "Research/Gate13R_P1C5_Independent_Statistical_Analysis_Plan.v1.md")
    test_design = binding(project, "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json")
    amendment = binding(project, "Research/Gate13R_P1C5_Independent_User_Authorization.v1.json")
    command = binding(project, "Assets/_Scripts/Research/Editor/Gate13RP1C5FormalBatchCommandV1.cs")
    provenance = binding(project, "Research/Gate13R_P1C5_Independent_Power_Simulation.v1.json")
    registry = binding(project, "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json")
    mapping = binding(project, "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json")
    overlay_binding = binding(project, overlay_rel)

    plan = {
        "schemaVersion": 3,
        "planId": "gate13r-p1c5-independent-block-plan-v1",
        "designId": "gate13r-p1c5-independent-confirmatory-study-v1",
        "globalProcessOrdinal": int(schedule["globalProcessOrdinal"]),
        "blockId": schedule["blockId"],
        "campaignId": schedule["campaignId"],
        "scenarioId": schedule["scenarioId"],
        "scenarioRelativePath": schedule["scenarioRelativePath"],
        "scenarioSourceSha256": schedule["scenarioSha256"],
        "comparisonCohortId": schedule["comparisonCohortId"],
        "block": int(schedule["campaignBlockOrdinal"]),
        "williamsRowIndex": int(schedule["williamsRowIndex"]),
        "formalCampaign": True,
        "validationOnly": False,
        "analysisRole": "formal-timing",
        "verificationInjectedFailurePosition": 0,
        "validationInjectedNativeHardPosition": 0,
        "validationInjectedTelemetryFailurePosition": 0,
        "validationInjectedPersistenceFailurePosition": 0,
        "formalConfigRelativePath": config["relativePath"],
        "formalConfigSha256": config["sha256"],
        "specificationRelativePath": specification["relativePath"],
        "specificationSha256": specification["sha256"],
        "testDesignRelativePath": test_design["relativePath"],
        "testDesignSha256": test_design["sha256"],
        "amendmentRelativePath": amendment["relativePath"],
        "amendmentSha256": amendment["sha256"],
        "commandRelativePath": command["relativePath"],
        "commandSha256": command["sha256"],
        "provenanceRelativePath": provenance["relativePath"],
        "provenanceSha256": provenance["sha256"],
        "executionReceiptRelativePath": receipt_relative,
        "executionReceiptSha256": receipt_sha,
        "memoryPolicyId": overlay["policyId"],
        "policyTierId": overlay["tierId"],
        "gridWidth": int(scenario["gridWidth"]),
        "gridHeight": int(scenario["gridHeight"]),
        "canonicalMaximumGridDimension": int(overlay["canonicalMaximumGridDimension"]),
        "nativeAdvisoryThresholdBytes": int(overlay["nativeAdvisoryBytes"]),
        "nativeHardThresholdBytes": int(overlay["nativeHardBytes"]),
        "hostAbsoluteNativeEmergencyBytes": int(overlay["hostAbsoluteNativeEmergencyBytes"]),
        "hostRelativeNativeGrowthEmergencyBytes": int(overlay["hostRelativeNativeGrowthEmergencyBytes"]),
        "hostAvailablePhysicalMemoryFloorBytes": int(overlay["hostAvailablePhysicalMemoryFloorBytes"]),
        "memoryPolicyRegistryRelativePath": registry["relativePath"],
        "memoryPolicyRegistrySha256": registry["sha256"],
        "scenarioPolicyMappingRelativePath": mapping["relativePath"],
        "scenarioPolicyMappingSha256": mapping["sha256"],
        "schedulePolicyOverlayRelativePath": overlay_binding["relativePath"],
        "schedulePolicyOverlaySha256": overlay_binding["sha256"],
        "entries": [
            {
                "position": int(entry["position"]),
                "algorithmId": entry["algorithmId"],
                "predecessorAlgorithmId": entry["predecessorAlgorithmId"],
                "runId": entry["runId"],
                "directory": entry["childDirectory"],
            }
            for entry in schedule["entries"]
        ],
    }
    atomic_create(output, plan)
    print(json.dumps({"passed": True, "output": str(output), "sha256": sha256_file(output), "blockId": plan["blockId"], "mode": "formal-independent-study"}, sort_keys=True))


if __name__ == "__main__":
    main()
