#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import traceback
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


OUTPUT_NAMES = {
    "validation-result.v1.json",
    "freeze-manifest.v1.json",
    "terminal-receipt.v1.json",
    "final-evidence-freeze-manifest.v1.json",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as f:
        return json.load(f)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def readonly(path: Path) -> None:
    path.chmod(path.stat().st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)


def write_json(path: Path, value: Any) -> None:
    require(not path.exists(), f"refusing to overwrite {path.name}")
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    readonly(path)


def rel(project: Path, path: Path) -> str:
    return path.resolve().relative_to(project.resolve()).as_posix()


def inventory_row(project: Path, path: Path, role: str) -> dict[str, Any]:
    return {"role": role, "relativePath": rel(project, path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def validate_schedule(schedule: dict[str, Any]) -> dict[str, Any]:
    orders = schedule["williamsOrders"]
    algorithms = {"A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"}
    require(len(orders) == 6, "Williams order count is not six")
    require(all(set(order) == algorithms and len(order) == 6 for order in orders), "Williams row is not a six-algorithm permutation")
    base_predecessors = Counter()
    for order in orders:
        base_predecessors.update(zip(order[:-1], order[1:]))
    require(len(base_predecessors) == 30 and set(base_predecessors.values()) == {1}, "Williams directed predecessor balance failed")
    total_superblocks = 0
    overall_orders = Counter()
    overall_positions = Counter()
    overall_predecessors = Counter()
    for cell_ordinal in range(36):
        contexts = Counter()
        cell_orders = Counter()
        cell_positions = Counter()
        for replicate in range(36):
            context = replicate % 18
            pass_index = replicate // 18
            order_index = (context + cell_ordinal + (3 if pass_index else 0)) % 6
            order = orders[order_index]
            contexts[context] += 1
            cell_orders[order_index] += 1
            overall_orders[order_index] += 1
            for position, algorithm in enumerate(order, 1):
                cell_positions[(algorithm, position)] += 1
                overall_positions[(algorithm, position)] += 1
            overall_predecessors.update(zip(order[:-1], order[1:]))
            total_superblocks += 1
        require(set(contexts.values()) == {2} and len(contexts) == 18, f"context balance failed in cell {cell_ordinal}")
        require(set(cell_orders.values()) == {6} and len(cell_orders) == 6, f"order balance failed in cell {cell_ordinal}")
        require(set(cell_positions.values()) == {6} and len(cell_positions) == 36, f"position balance failed in cell {cell_ordinal}")
    require(total_superblocks == 1296, "formal schedule rule does not yield 1296 superblocks")
    require(set(overall_orders.values()) == {216}, "overall Williams order balance failed")
    require(set(overall_positions.values()) == {216} and len(overall_positions) == 36, "overall algorithm-position balance failed")
    require(set(overall_predecessors.values()) == {216} and len(overall_predecessors) == 30, "overall directed predecessor balance failed")
    return {
        "superblocks": total_superblocks,
        "contextStrataPerCell": 18,
        "repeatsPerContextPerCell": 2,
        "eachOrderPerCell": 6,
        "eachOrderOverall": 216,
        "eachAlgorithmPositionOverall": 216,
        "eachDirectedPredecessorPairOverall": 216,
    }


def run(project: Path, evidence: Path) -> int:
    started = utc_now()
    for name in OUTPUT_NAMES:
        require(not (evidence / name).exists(), f"fresh evidence gate failed: {name}")
    pre = load(evidence / "pre-validation-freeze-manifest.v1.json")
    require(pre["schema"] == "gate14re-me-formal-st-pre-validation-freeze-manifest-v1", "unexpected pre-validation manifest schema")
    for row in pre["files"]:
        path = project / row["relativePath"]
        require(path.is_file(), f"frozen input missing: {row['relativePath']}")
        require(path.stat().st_size == int(row["bytes"]), f"frozen input size mismatch: {row['relativePath']}")
        require(sha256(path) == row["sha256"], f"frozen input hash mismatch: {row['relativePath']}")

    v5 = project / "Research/Gate14Re-ME/Execution/v5"
    index = load(v5 / "formal-st-freeze-index.v5_0.json")
    require(index["schema"] == "gate14re-me-formal-st-freeze-index-v5.0", "unexpected v5 freeze index schema")
    contract_rows = []
    contracts: dict[str, Any] = {}
    for row in index["contracts"]:
        path = project / row["relativePath"]
        require(path.is_file(), f"v5 contract missing: {row['relativePath']}")
        require(path.stat().st_size == int(row["bytes"]), f"v5 contract size mismatch: {row['relativePath']}")
        require(sha256(path) == row["sha256"], f"v5 contract hash mismatch: {row['relativePath']}")
        contracts[path.name] = load(path)
        contract_rows.append(inventory_row(project, path, "formal-v5-contract"))

    prerequisite_rows = []
    for row in index["decisiveEvidence"]:
        path = project / row["relativePath"]
        require(path.is_file(), f"decisive evidence missing: {row['relativePath']}")
        require(sha256(path) == row["sha256"], f"decisive evidence hash mismatch: {row['relativePath']}")
        prerequisite_rows.append(inventory_row(project, path, row["role"]))

    design = contracts["formal-st-scientific-design.v5_0.json"]
    endpoint = contracts["formal-st-endpoint-mipe-contract.v5_0.json"]
    sample = contracts["formal-st-sample-size-decision.v5_0.json"]
    schedule = contracts["formal-st-schedule-contract.v5_0.json"]
    analysis = contracts["formal-st-analysis-contract.v5_0.json"]
    stop = contracts["formal-st-stopping-and-replacement-contract.v5_0.json"]
    resource = contracts["formal-st-resource-budget.v5_0.json"]
    fairness = contracts["formal-st-fairness-runtime-binding.v5_0.json"]
    implementation = contracts["formal-st-implementation-build-input-binding.v5_0.json"]
    execution = contracts["formal-st-execution-contract.v5_0.json"]
    delivery = contracts["formal-st-data-delivery-binding.v5_0.json"]
    amendment = contracts["formal-st-parameter-amendment.v5_0.json"]

    require(design["design"]["GGridEdgeLevels"] == [64, 96, 128], "G levels mismatch")
    require(design["design"]["NAgentCountLevels"] == [32, 64, 128], "N levels mismatch")
    require(design["design"]["FChangedCellLevels"] == [1, 9, 25, 81], "F levels mismatch")
    require(design["design"]["structuralCells"] == 36, "structural cell mismatch")
    require(design["design"]["BPerStructuralCell"] == 36, "design B mismatch")
    require(design["design"]["plannedIndependentSuperblocks"] == 1296, "superblock mismatch")
    require(design["design"]["plannedMeasuredAlgorithmLanes"] == 7776, "lane mismatch")
    require(design["design"]["plannedPrimaryEventGroupRows"] == 186624, "event-group mismatch")
    require(design["movementTransferSentinel"]["S5"] == "OMITTED", "S5 not omitted")
    require(not design["movementTransferSentinel"]["omissionRelaxesCorrectnessOrOracleGates"], "S5 omission relaxed hard gates")

    require(endpoint["ratioThreshold"] == 0.9, "ratio MIPE mismatch")
    require(abs(float(endpoint["logThresholdExact"]) + 0.10536051565782628) < 1e-15, "log MIPE mismatch")
    require(len(endpoint["domains"]) == 7, "endpoint domain count mismatch")
    require(endpoint["movementTransferSentinel"] == "OMITTED", "endpoint S5 mismatch")
    require(endpoint["correctnessAndOracleHardGates"] == "UNCHANGED_AND_MANDATORY", "endpoint hard gates changed")

    require(sample["candidateB"] == [36, 72, 108, 144], "candidate B grid mismatch")
    require(sample["selectedB"] == 36, "selected B is not 36")
    require(sample["targetPowerAtLeast"] == 0.9, "power target mismatch")
    require(not sample["runtimeGate"]["triggered"], "seven-day gate unexpectedly triggered")
    power_path = project / sample["powerEvidence"]["relativePath"]
    require(sha256(power_path) == sample["powerEvidence"]["sha256"], "power result hash mismatch")
    power = load(power_path)
    require(power["status"] == "PASS_ANONYMOUS_POWER_FINAL_B_ELIGIBLE_FOR_FORMAL_FREEZE", "power terminal status mismatch")
    require(power["selectedB"] == 36 and not power["sevenDayGateTriggered"], "power selection mismatch")
    b36 = next(row for row in power["candidateResults"] if row["B"] == 36)
    require(b36["passesFrozenPowerCriterion"], "B=36 did not pass frozen power criterion")
    require(len(b36["opaqueTargetResults"]) == 6, "opaque-target power cardinality mismatch")
    require(min(float(x["wilson95Lower"]) for x in b36["opaqueTargetResults"]) >= 0.9, "worst opaque-target lower power bound below 0.90")

    require(analysis["confirmatoryFamily"]["hypotheses"] == 35, "confirmatory hypothesis count mismatch")
    require(analysis["confirmatoryFamily"]["multiplicity"] == "Holm strong FWER", "multiplicity mismatch")
    require(analysis["confirmatoryFamily"]["primaryClaimPass"].startswith("at least four of seven"), "majority rule mismatch")
    require(not sample["fixedRules"]["formalAdaptiveExpansion"] and not sample["fixedRules"]["postOutcomeTopUp"], "adaptive expansion or top-up enabled")
    require(not stop["adaptiveRules"]["sampleSizeReestimation"] and not stop["adaptiveRules"]["postOutcomeTopUp"], "stopping contract allows sample-size adaptation")

    schedule_meta = validate_schedule(schedule)
    require(execution["measuredExecution"]["expectedMeasuredFreshUnityProcesses"] == 7776, "execution process count mismatch")
    require(execution["measuredExecution"]["maximumConcurrentMeasuredUnityProcesses"] == 1, "execution concurrency mismatch")
    require(delivery["acceptanceArchitecture"]["streamingBoundedMemory"], "acceptance is not streaming bounded-memory")
    require(not delivery["acceptanceArchitecture"]["retainAllRawRowsInMemory"], "acceptance retains all raw rows in memory")
    require(delivery["acceptanceArchitecture"]["typedParquetFullValueTypeOrderRoundTripGating"], "typed-Parquet round trip not gating")

    require(resource["runtime"]["planningHoursWith20PercentHeadroom"] == 83.493, "planning runtime mismatch")
    require(resource["runtime"]["planningHoursWith20PercentHeadroom"] < resource["runtime"]["sevenDayGateHours"], "runtime is not below seven-day gate")
    require(resource["storage"]["formalRawAndDeliveryReservedStorageBytes"] >= 2 * resource["storage"]["formalExpectedByBScalingBytes"], "storage reservation lacks twofold headroom")
    require(resource["storage"]["formalRawAndDeliveryReservedStorageBytes"] == amendment["resolvedParameters"]["formalRawAndDeliveryReservedStorageBytes"], "storage amendment mismatch")

    source_rows = []
    for item in fairness["algorithms"] + fairness["sharedBindings"] + implementation["qualifiedReusableComponents"]:
        path = project / item["relativePath"]
        require(path.is_file(), f"bound source missing: {item['relativePath']}")
        require(sha256(path) == item["sha256"], f"bound source hash mismatch: {item['relativePath']}")
        source_rows.append(inventory_row(project, path, "bound-source-or-contract"))
    for runtime_key, hash_key in (("UnityExecutable", "UnitySha256"), ("PowerShellExecutable", "PowerShellSha256"), ("PythonExecutable", "PythonSha256")):
        path = Path(fairness["runtime"][runtime_key])
        require(path.is_file(), f"runtime missing: {path}")
        require(sha256(path) == fairness["runtime"][hash_key], f"runtime hash mismatch: {path}")

    forbidden_roots = [
        project / "Research/FormalRuns/Gate14Re-ME/formal-st/v5",
        project / "Research/Exports/Gate14Re-ME/formal-st/v5",
        project / "Research/Packages/Gate14Re-ME/formal-st/v5",
        project / "Research/PackageStaging/Gate14Re-ME/formal-st/v5",
        project / "Research/PackageTests/Gate14Re-ME/formal-st/v5",
    ]
    require(all(not path.exists() for path in forbidden_roots), "a forbidden formal or package root already exists")
    free_bytes = shutil.disk_usage(project.anchor).free
    require(free_bytes >= resource["storage"]["formalRawAndDeliveryReservedStorageBytes"], "current host free space below frozen formal reservation")
    require(implementation["buildBoundary"]["formalV5SourceCopiesCreatedByThisFreeze"] == 0, "formal source copy unexpectedly recorded")
    require(not implementation["buildBoundary"]["packageStagingRootCreated"], "package staging unexpectedly recorded")
    require(not implementation["buildBoundary"]["installerOrCredentialCopied"], "installer or credential copy unexpectedly recorded")
    require(not implementation["buildBoundary"]["zipCreated"], "ZIP unexpectedly recorded")

    validation = {
        "schema": "gate14re-me-formal-st-design-freeze-validation-result-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-design-freeze-v5-attempt-001",
        "status": "PASS_FORMAL_ST_V5_NONEXECUTING_FREEZE",
        "validatedAtUtc": utc_now(),
        "design": {"G": [64, 96, 128], "N": [32, 64, 128], "F": [1, 9, 25, 81], "B": 36, "superblocks": 1296, "measuredLanes": 7776},
        "scheduleProof": schedule_meta,
        "power": {"candidateB": [36, 72, 108, 144], "selectedB": 36, "target": 0.9, "worstB36Wilson95Lower": min(float(x["wilson95Lower"]) for x in b36["opaqueTargetResults"]), "identityBlind": True},
        "runtime": {"planningHoursWith20PercentHeadroom": 83.493, "sevenDayGateHours": 168, "triggered": False},
        "storage": {"reservedBytes": resource["storage"]["formalRawAndDeliveryReservedStorageBytes"], "currentHostFreeBytes": free_bytes},
        "hardGates": {"correctnessOracleRetained": True, "completeRawDeliveryRetained": True, "S5": "OMITTED"},
        "boundary": {"formalInputs": 0, "formalScheduleRows": 0, "formalObservations": 0, "packageBuilt": False, "installerOrCredentialCopied": False, "zipCreated": False},
    }
    validation_path = evidence / "validation-result.v1.json"
    write_json(validation_path, validation)

    static_rows = []
    for row in pre["files"]:
        static_rows.append(inventory_row(project, project / row["relativePath"], "pre-validation-frozen-input"))
    freeze_manifest = {
        "schema": "gate14re-me-formal-st-design-freeze-manifest-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-design-freeze-v5-attempt-001",
        "status": "PASS_FORMAL_ST_V5_NONEXECUTING_FREEZE",
        "frozenAtUtc": utc_now(),
        "files": static_rows + contract_rows + prerequisite_rows + source_rows + [inventory_row(project, validation_path, "validation-result")],
    }
    freeze_path = evidence / "freeze-manifest.v1.json"
    write_json(freeze_path, freeze_manifest)
    terminal = {
        "schema": "gate14re-me-formal-st-design-freeze-terminal-receipt-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-design-freeze-v5-attempt-001",
        "status": "PASS_FORMAL_ST_V5_NONEXECUTING_FREEZE",
        "startedAtUtc": started,
        "completedAtUtc": utc_now(),
        "selectedB": 36,
        "planningHoursWith20PercentHeadroom": 83.493,
        "sevenDayGateTriggered": False,
        "freezeManifest": {"relativePath": rel(project, freeze_path), "sha256": sha256(freeze_path)},
        "validationResult": {"relativePath": rel(project, validation_path), "sha256": sha256(validation_path)},
        "formalCollectionStarted": False,
        "migrationPackageBuilt": False,
    }
    terminal_path = evidence / "terminal-receipt.v1.json"
    write_json(terminal_path, terminal)
    final_manifest = {
        "schema": "gate14re-me-formal-st-design-freeze-final-evidence-manifest-v1",
        "studyId": "Gate14Re-ME",
        "attemptId": "formal-st-design-freeze-v5-attempt-001",
        "status": "PASS_FORMAL_ST_V5_NONEXECUTING_FREEZE",
        "frozenAtUtc": utc_now(),
        "files": [inventory_row(project, path, "terminal-evidence") for path in sorted(evidence.iterdir()) if path.is_file() and path.name != "final-evidence-freeze-manifest.v1.json"],
        "formalCollectionStarted": False,
        "migrationPackageBuilt": False,
    }
    final_path = evidence / "final-evidence-freeze-manifest.v1.json"
    write_json(final_path, final_manifest)
    for row in index["contracts"]:
        readonly(project / row["relativePath"])
    readonly(v5 / "formal-st-freeze-index.v5_0.json")
    print(json.dumps({"status": terminal["status"], "selectedB": 36, "terminalSha256": sha256(terminal_path), "finalEvidenceFreezeSha256": sha256(final_path)}, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--evidence-root", required=True)
    args = parser.parse_args()
    try:
        return run(Path(args.project_root).resolve(), Path(args.evidence_root).resolve())
    except Exception as error:
        failure = {"schema":"gate14re-me-formal-st-design-freeze-terminal-receipt-v1","studyId":"Gate14Re-ME","attemptId":"formal-st-design-freeze-v5-attempt-001","status":"FAIL_CLOSED_FORMAL_ST_V5_FREEZE","failedAtUtc":utc_now(),"errorType":type(error).__name__,"errorMessage":str(error),"tracebackSha256":hashlib.sha256(traceback.format_exc().encode("utf-8")).hexdigest(),"formalCollectionStarted":False,"migrationPackageBuilt":False}
        path = Path(args.evidence_root).resolve() / "terminal-receipt.v1.json"
        if path.parent.is_dir() and not path.exists():
            write_json(path, failure)
        print(json.dumps(failure, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
