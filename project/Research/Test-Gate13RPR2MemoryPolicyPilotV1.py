#!/usr/bin/env python3
"""Static, schema, schedule, formula, and no-Unity validation for MP1."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


UPSTREAM = {
    "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json": "388b7a1921fe07daf97827353f402c365b0f208a9dc62cbbff2d4b5ea2829b7d",
    "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json": "f192265e12155d0e56e1aa94e18cea1305b66e2fbc0eeb0eeb6ad9618aeb3c3a",
    "Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json": "11cf507ad3daee5c4d17adf3d7349e50b73a925f58fdb175e2b68315240eff5b",
    "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/evidence-manifest.json": "73e34e3910a38462d8dc3a125eaf88e2c800b8f1808206db054fbe50e4f24c46",
    "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v2/evidence-manifest.json": "847e93f13fe7e46eea154741d3e93421ff7c4df389b1a7a2e10cb1b676e4eb3b",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite {value}")))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    checks: list[dict[str, Any]] = []

    def check(identity: str, condition: bool, detail: str = "") -> None:
        checks.append({"id": identity, "passed": bool(condition), "detail": detail})
        if not condition:
            raise RuntimeError(f"{identity}: {detail}")

    for relative, expected in UPSTREAM.items():
        check(f"upstream-hash:{relative}", sha256_file(project / relative) == expected, expected)
    prewrite = read_json(project / "Research/Gate13R_PR2_MP1_PreWrite_Preservation_Audit.v1.json")
    check("prewrite-attempt2-identity", prewrite["passed"] is True and prewrite["attempt2FormalRoot"]["canonicalOrdinalTreeSha256"] == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e")
    required_json = [
        "Research/Gate13R_PR2_MP1_Authorization.v1.json",
        "Research/Gate13R_PR2_MP1_Instrumentation_Contract.v1.json",
        "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json",
        "Research/Gate13R_PR2_MP1_Output_Schema.v1.json",
        "Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json",
        "Research/Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json",
        "Research/Gate13R_PR2_MP1_Config_Schema.v1.json",
        "Research/Gate13R_PR2_MP1_Pilot_Config.v1.json",
    ]
    for relative in required_json:
        check(f"json-parse:{relative}", isinstance(read_json(project / relative), dict))

    schedule_path = project / "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl"
    rows = [json.loads(line) for line in schedule_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    check("schedule-count", len(rows) == 96, str(len(rows)))
    check("sample-count", sum(len(row["entries"]) for row in rows) == 384)
    check("global-ordinals", [row["globalProcessOrdinal"] for row in rows] == list(range(1, 97)))
    check("unique-block-id", len({row["blockId"] for row in rows}) == 96)
    run_ids = [entry["runId"] for row in rows for entry in row["entries"]]
    check("unique-run-id", len(set(run_ids)) == 384)
    check("zero-warmup", all(row["measured"] is True and row["warmup"] is False for row in rows))
    expected_counts = {"grid-scale-g032-shared": 16, "grid-scale-g064-shared": 16, "grid-scale-g128-shared": 16, "grid-scale-g256-shared": 48}
    check("scenario-block-counts", Counter(row["scenarioId"] for row in rows) == Counter(expected_counts))
    by_scenario: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_scenario[row["scenarioId"]].append(row)
        check(f"complete-block:{row['blockId']}", sorted(entry["algorithmId"] for entry in row["entries"]) == ["A*-R", "C-FF", "D*L", "IDFF"])
        check(f"contiguous-position:{row['blockId']}", [entry["position"] for entry in row["entries"]] == [1, 2, 3, 4])
        check(f"predecessor:{row['blockId']}", all(entry["predecessorAlgorithmId"] == ("NONE" if index == 0 else row["entries"][index - 1]["algorithmId"]) for index, entry in enumerate(row["entries"])))
    for scenario_id, scenario_rows in by_scenario.items():
        quota = len(scenario_rows) // 4
        check(f"row-balance:{scenario_id}", Counter(row["williamsRowIndex"] for row in scenario_rows) == Counter({0: quota, 1: quota, 2: quota, 3: quota}))
        for algorithm in ("A*-R", "D*L", "C-FF", "IDFF"):
            positions = Counter(entry["position"] for row in scenario_rows for entry in row["entries"] if entry["algorithmId"] == algorithm)
            check(f"position-balance:{scenario_id}:{algorithm}", positions == Counter({1: quota, 2: quota, 3: quota, 4: quota}), str(positions))

    generator_path = project / "Research/New-Gate13RPR2MemoryPolicyPilotV1.py"
    spec = importlib.util.spec_from_file_location("mp1_generator", generator_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    regenerated, regenerated_balance = module.build_schedule(project)
    regenerated_bytes = module.jsonl_bytes(regenerated)
    check("deterministic-regeneration", hashlib.sha256(regenerated_bytes).hexdigest() == sha256_file(schedule_path))
    check("regenerated-balance", bool(regenerated_balance))

    policy = read_json(project / "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json")
    # Registry stores native candidate values in bytes; detect accidental MiB-as-bytes immediately.
    expected_bytes = [value * 1024 * 1024 for value in (512, 640, 768, 1024)]
    actual_bytes = [item["thresholdBytes"] for item in policy["nativeDeltaCandidates"]]
    check("candidate-thresholds", actual_bytes == expected_bytes, str(actual_bytes))
    check("managed-boundaries", policy["managedPilotRules"] == {"sampleRetainedAlertBytes": 134217728, "sampleRetainedEmergencyHardFailBytes": 268435456, "blockRetainedHardFailBytes": 268435456})
    check("host-safety-boundaries", policy["hostSafetyRules"]["absoluteWorkingSetHardFailBytes"] == 4294967296 and policy["hostSafetyRules"]["relativeWorkingSetGrowthHardFailBytes"] == 2147483648 and policy["hostSafetyRules"]["availablePhysicalMemoryFloorBytes"] == 8589934592)

    command = (project / "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs").read_text(encoding="utf-8-sig")
    check("new-command-identity", "class Gate13RPR2MemoryPolicyPilotBatchCommandV1" in command)
    check("native-candidates-diagnostic", "diagnosticNative512MiBExceeded" in command and "HARD-FAIL-BLOCK-WORKING-SET-512MIB" not in command)
    check("stage-identities", all(token in command for token in ["unity-command-entry-project-loaded", "before-scenario-load", "after-scenario-load-before-first-sample", "sample-before", "sample-raw-after-workload", "sample-after-cleanup", "post-block-pre-exit"]))
    check("managed-emergency", "HARD-FAIL-SAMPLE-EMERGENCY-256MIB" in command and "HARD-FAIL-BLOCK-MANAGED-256MIB" in command)
    check("absolute-relative-free-safety", all(token in command for token in ["HARD-FAIL-MP1-ABSOLUTE-NATIVE-4GIB", "HARD-FAIL-MP1-RELATIVE-NATIVE-2GIB", "HARD-FAIL-MP1-AVAILABLE-PHYSICAL-BELOW-8GIB"]))
    wrapper = (project / "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1").read_text(encoding="utf-8-sig")
    check("failure-precedence-wrapper", wrapper.find("Invoke-Gate10RPostExitQuiescenceV3") < wrapper.find("Resolve-G13RPR2MP1FailurePrecedence") and "DURABLE-UNITY-BLOCK-FAILURE" in (project / "Research/Gate13RPR2MemoryPolicyPilotV1.psm1").read_text(encoding="utf-8-sig"))
    check("no-auto-retry", all(token in wrapper for token in ["automaticRetryAttempted = $false", "automaticResumeAttempted = $false", "topUpAttempted = $false", "partialMergeAttempted = $false"]))
    analysis = (project / "Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py").read_text(encoding="utf-8-sig")
    check("analysis-no-unity-launch", "Start-Process" not in analysis and "Unity.exe" not in analysis and "subprocess" not in analysis)
    check("analysis-whole-block-bootstrap", "complete-fresh-unity-williams-block" in analysis and "BOOTSTRAP_REPLICATES = 20_000" in analysis)
    check("formal-attempt3-absent", not (project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").exists() and not (project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json").exists())
    check("measured-pilot-root-absent", not (project / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1").exists())

    summary = {"schemaVersion": 1, "summaryKind": "gate13r-pr2-mp1-static-unit-validation-v1", "checkCount": len(checks), "passedCheckCount": sum(item["passed"] for item in checks), "checks": checks, "passed": all(item["passed"] for item in checks)}
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(output)
    fd, temporary = tempfile.mkstemp(prefix=".mp1-test-", dir=str(output.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"passed": summary["passed"], "checkCount": summary["checkCount"], "output": str(output)}, sort_keys=True))


if __name__ == "__main__":
    main()
