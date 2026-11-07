#!/usr/bin/env python3
"""Create one V3 hash-bound MP2 block plan from the frozen schedule/overlay.

The builder never creates a formal root or formal receipt. Formal mode is usable only
after a separately authorized caller has already created both and passes their paths.
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
    fd, temporary = tempfile.mkstemp(prefix=".g13r-pr2-mp2-plan-", dir=str(path.parent))
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
    parser.add_argument("--mode", choices=("validation", "formal-attempt3"), required=True)
    parser.add_argument("--receipt", default="")
    parser.add_argument("--verification-failure-position", type=int, default=0)
    parser.add_argument("--native-hard-position", type=int, default=0)
    parser.add_argument("--telemetry-failure-position", type=int, default=0)
    parser.add_argument("--persistence-failure-position", type=int, default=0)
    args = parser.parse_args()

    project = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    formal_root = (project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").resolve()
    formal_receipt = (project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json").resolve()
    verification_root = (project / "Research/Verification/Gate13R_PR2_MP2").resolve()
    schedule_rel = "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    overlay_rel = "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"
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

    injections = [args.verification_failure_position, args.native_hard_position, args.telemetry_failure_position, args.persistence_failure_position]
    if any(value < 0 or value > len(schedule["entries"]) for value in injections):
        raise ValueError("validation injection position is outside the block")
    if args.mode == "formal-attempt3" and any(injections):
        raise ValueError("formal mode forbids validation injections")

    if args.mode == "validation":
        if formal_root.exists() or formal_receipt.exists():
            raise ValueError("MP2 validation requires formal attempt-3 root/receipt absence")
        if not is_within(output, verification_root):
            raise ValueError("validation plan must remain below the MP2 verification root")
        receipt_relative = ""
        receipt_sha = ""
    else:
        if not formal_root.is_dir() or not formal_receipt.is_file():
            raise ValueError("formal mode requires a pre-existing separately authorized attempt-3 root and receipt")
        if Path(args.receipt).resolve() != formal_receipt:
            raise ValueError("formal receipt identity mismatch")
        if not is_within(output, formal_root):
            raise ValueError("formal plan must remain below the attempt-3 root")
        receipt_relative = formal_receipt.relative_to(project).as_posix()
        receipt_sha = sha256_file(formal_receipt)

    config = binding(project, "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v3.json")
    specification = binding(project, "Research/Gate13R_PR2_MP2_Specification.v1.md")
    test_design = binding(project, "Research/Gate13R_PR2_MP2_Test_Design.v1.md")
    amendment = binding(project, "Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json")
    command = binding(project, "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs")
    provenance = binding(project, "Research/Gate13R_PR2_MP2_Provenance.v3.json")
    registry = binding(project, "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json")
    mapping = binding(project, "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json")
    overlay_binding = binding(project, overlay_rel)

    plan = {
        "schemaVersion": 3,
        "planId": "gate13r-pr2-mp2-block-plan-v1",
        "designId": "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1",
        "globalProcessOrdinal": int(schedule["globalProcessOrdinal"]),
        "blockId": schedule["blockId"],
        "campaignId": schedule["campaignId"],
        "scenarioId": schedule["scenarioId"],
        "scenarioRelativePath": schedule["scenarioRelativePath"],
        "scenarioSourceSha256": schedule["scenarioSha256"],
        "comparisonCohortId": schedule["comparisonCohortId"],
        "block": int(schedule["campaignBlockOrdinal"]),
        "williamsRowIndex": int(schedule["williamsRowIndex"]),
        "formalCampaign": args.mode == "formal-attempt3",
        "validationOnly": args.mode == "validation",
        "analysisRole": "formal-timing" if args.mode == "formal-attempt3" else "validation-only",
        "verificationInjectedFailurePosition": args.verification_failure_position,
        "validationInjectedNativeHardPosition": args.native_hard_position,
        "validationInjectedTelemetryFailurePosition": args.telemetry_failure_position,
        "validationInjectedPersistenceFailurePosition": args.persistence_failure_position,
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
    print(json.dumps({"passed": True, "output": str(output), "sha256": sha256_file(output), "blockId": plan["blockId"], "mode": args.mode}, sort_keys=True))


if __name__ == "__main__":
    main()
