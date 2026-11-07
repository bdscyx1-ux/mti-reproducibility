#!/usr/bin/env python3
"""Independent fail-closed validator for the Gate14Re MQ formal-v2 freeze.

This validator never imports or runs algorithm code.  It verifies only frozen
scientific rules, power selection, schedule/input geometry, file identities,
and implementation bindings.  It refuses to overwrite its output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STUDY = "Gate14Re-MQ-CFF-IDFF"
DESIGN = "gate14re-mq-cff-idff-formal-v2"
SCHEDULE_SEED = 141420273
PROCESS_COUNT = 864
BLOCK_COUNT = 36
CONDITIONS = 24
LANES = 16
MIPE_LOG = -0.10536051565782628

PATHS = {
    "authorized_design": "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/formal-mq-authorized-design.v2.json",
    "power_result": "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-result.v2.json",
    "power_seal": "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-selection-seal-receipt.v2.json",
    "schedule": "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule.v2.jsonl",
    "schedule_summary": "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule-summary.v2.json",
    "blocks": "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-block-input-assignments.v2.jsonl",
    "source_manifest": "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-input-source-manifest.v2.json",
    "identity_map": "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/opaque-algorithm-identity-map.v2.json",
    "science_contract": "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-scientific-and-analysis-contract.v2.json",
    "execution_contract": "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-execution-contract.v2.json",
    "fairness": "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/fairness-and-topology-binding.v2.json",
    "budget": "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-resource-budget.v2.json",
    "implementation_manifest": "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-implementation-manifest.v2_2.json",
    "formal_runner": "Assets/_Scripts/Research/Editor/Gate14ReMQFormalRunnerV2.cs",
    "collection_supervisor": "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_0.ps1",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"Expected JSON object: {path}")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL row is not an object: {path}:{line_number}")
            rows.append(value)
    return rows


def bound(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"Bound path escapes project root: {relative}") from exc
    require(path.is_file(), f"Bound file is missing: {relative}")
    return path


def verify_reference(root: Path, reference: dict[str, Any], label: str) -> None:
    path = bound(root, str(reference["relativePath"]))
    require(path.stat().st_size == int(reference["bytes"]), f"{label} byte count mismatch")
    require(sha256(path) == str(reference["sha256"]), f"{label} SHA-256 mismatch")


def validate_science(root: Path, documents: dict[str, dict[str, Any]]) -> dict[str, Any]:
    design = documents["authorized_design"]
    require(design.get("schema") == "gate14re-mq-cff-idff-authorized-formal-design-rules-v2", "Authorized-design schema mismatch")
    require(design.get("status") == "FROZEN_BEFORE_IDENTITY_BLIND_POWER_B_PENDING", "Authorized-design status mismatch")

    power = documents["power_result"]
    require(power.get("schema") == "gate14re-mq-cff-idff-identity-blind-power-result-v2", "Power-result schema mismatch")
    require(power.get("status") == "PASS_IDENTITY_BLIND_PRIMARY_POWER_B_SELECTED_ELIGIBLE_FOR_FINAL_FREEZE", "Power-result status mismatch")
    require(power.get("primaryFamily") == ["P1", "P2", "P3", "P4"], "Primary family must be exactly P1-P4")
    require(power.get("keySecondaryFamily") == ["S1", "S2"], "Key-secondary family must be exactly S1-S2")
    require(power.get("keySecondaryUsedForBSelection") is False, "Key secondary entered B selection")
    require(power.get("selectedB") == 36, "Selected B is not 36")
    require(abs(float(power["mipe"]["ratio"]) - 0.9) < 1e-15, "MIPE ratio drift")
    require(abs(float(power["mipe"]["logScaleExact"]) - MIPE_LOG) < 1e-15, "MIPE log threshold drift")
    candidates = power.get("candidateResults", [])
    require([row.get("B") for row in candidates] == [36, 72, 108, 144], "B candidate set/order mismatch")
    selected = candidates[0]
    require(all(float(row["wilson95Lower"]) >= 0.90 for row in selected["primaryResults"]), "B36 fails primary power rule")
    require(selected.get("passesFrozenPrimaryPowerCriterion") is True, "B36 pass marker missing")
    require(float(selected["worstPrimaryWilson95Lower"]) >= 0.90, "B36 worst-primary lower bound below 0.90")
    require(selected.get("keySecondaryUsedForBSelection") is False, "B36 secondary selection flag invalid")

    seal = documents["power_seal"]
    require(seal.get("schema") == "gate14re-mq-cff-idff-power-selection-seal-receipt-v2", "Power-seal schema mismatch")
    require(seal.get("status") == "PASS_B36_SELECTED_AND_SEALED" and seal.get("selectedB") == 36, "Power seal mismatch")
    require(seal["selectionRule"]["selectedUsingHypotheses"] == ["P1", "P2", "P3", "P4"], "Power-seal primary set mismatch")
    require(seal["selectionRule"]["keySecondaryExcludedFromSelection"] == ["S1", "S2"], "Power-seal secondary exclusion mismatch")
    require(seal["sevenDayGate"]["triggered"] is False and float(seal["sevenDayGate"]["conservativeHours"]) < 168, "Seven-day gate invalid")

    science = documents["science_contract"]
    require(science.get("schema") == "gate14re-mq-formal-scientific-and-analysis-contract-v2", "Science-contract schema mismatch")
    require(science.get("status") == "FROZEN_FINAL_B36_SCIENTIFIC_DESIGN_FORMAL_COLLECTION_NOT_AUTHORIZED", "Science-contract status mismatch")
    require(science.get("selectedB") == 36, "Science-contract B mismatch")
    require(science.get("confirmatoryPrimaryFamily") == ["P1", "P2", "P3", "P4"], "Science primary family mismatch")
    require(science.get("keySecondaryFamily") == ["S1", "S2"], "Science secondary family mismatch")
    require(science["keySecondaryFormerIds"] == {"S1": "P5", "S2": "P6"}, "Former P5/P6 mapping mismatch")
    require(science["keySecondaryInference"]["usedForBSelection"] is False, "Science contract lets secondary choose B")
    require(science["keySecondaryInference"]["poweredGuarantee"] is False, "Science contract incorrectly guarantees secondary power")
    require(science["otherSecondary"]["movementTransferSentinelIncluded"] is False, "Movement-transfer sentinel was not omitted")
    require(science["correctness"]["allInputAndOracleHashesHardBound"] is True, "Input/oracle hard binding missing")
    require(science["correctness"]["everyMeasuredQueryComparedWithFrozenAlgorithmNeutralOracleAfterBatch"] is True, "Per-query oracle gate missing")
    require(science["correctness"]["oracleComparisonInsideMeasuredBatch"] is False, "Oracle comparison contaminates measured batch")
    require(science.get("formalCollectionAuthorized") is False and science.get("formalAnalysisAuthorized") is False, "Science contract authorizes execution or analysis")
    for label, reference in science["prerequisites"].items():
        verify_reference(root, reference, f"science prerequisite {label}")

    return {
        "selectedB": 36,
        "worstPrimaryWilson95Lower": selected["worstPrimaryWilson95Lower"],
        "conservativePlanningHours": seal["sevenDayGate"]["conservativeHours"],
        "primaryFamily": ["P1", "P2", "P3", "P4"],
        "keySecondaryFamily": ["S1", "S2"],
    }


def validate_schedule(rows: list[dict[str, Any]]) -> dict[str, Any]:
    require(len(rows) == PROCESS_COUNT, "Schedule row count is not 864")
    position_counts: Counter[tuple[int, int]] = Counter()
    carryover: set[tuple[int, int]] = set()
    expected_ids = [
        "ST-DIRECT-LARGE-L3", "MQ-LARGE-L3-W1", "MQ-LARGE-L3-W2", "MQ-LARGE-L3-W4", "MQ-LARGE-L3-W8",
        "ST-DIRECT-HIGH-FREQUENCY", "MQ-HIGH-FREQUENCY-W1", "MQ-HIGH-FREQUENCY-W2", "MQ-HIGH-FREQUENCY-W4", "MQ-HIGH-FREQUENCY-W8",
        "MQ-DUAL-CCD-W8-4PLUS4", "MQ-DUAL-CCD-W16-8PLUS8",
    ]
    expected_workers = [1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 8, 16]
    for block in range(BLOCK_COUNT):
        subset = rows[block * CONDITIONS : (block + 1) * CONDITIONS]
        require({int(row["positionWithinBlock"]) for row in subset} == set(range(CONDITIONS)), f"Block {block} position permutation invalid")
        require({int(row["conditionIndex"]) for row in subset} == set(range(CONDITIONS)), f"Block {block} condition permutation invalid")
        order = [None] * CONDITIONS
        for within, row in enumerate(subset):
            ordinal = block * CONDITIONS + within
            require(row.get("schema") == "gate14re-mq-formal-process-schedule-row-v2", f"Schedule schema mismatch at {ordinal}")
            require(int(row["processOrdinal"]) == ordinal and int(row["blockOrdinal"]) == block, f"Schedule ordinal mismatch at {ordinal}")
            require(row["blockId"] == f"MQV2-B{block + 1:03d}" and int(row["inputAssignmentRowOrdinal"]) == block, f"Schedule block binding mismatch at {ordinal}")
            require(int(row["scheduleSeed"]) == SCHEDULE_SEED and row.get("replacement") is None, f"Schedule seed/replacement mismatch at {ordinal}")
            condition = int(row["conditionIndex"])
            position = int(row["positionWithinBlock"])
            slot_within = condition % 12
            require(row["opaqueAlgorithmSlot"] == ("OPAQUE-A" if condition < 12 else "OPAQUE-B"), f"Opaque slot mismatch at {ordinal}")
            require(int(row["withinAlgorithmConditionIndex"]) == slot_within, f"Within-algorithm condition mismatch at {ordinal}")
            require(row["conditionId"] == expected_ids[slot_within] and int(row["workerCount"]) == expected_workers[slot_within], f"Condition matrix mismatch at {ordinal}")
            require(row["executorMode"] == ("direct" if slot_within in (0, 5) else "managed"), f"Executor mode mismatch at {ordinal}")
            require(row.get("analysisRole") in {"overhead-sentinel", "primary-slope", "key-secondary"}, f"Analysis role mismatch at {ordinal}")
            position_counts[(condition, position)] += 1
            order[position] = condition
        carryover.update(zip(order[:-1], order[1:]))
    values = list(position_counts.values())
    require(len(values) == CONDITIONS * CONDITIONS and min(values) == 1 and max(values) == 2, "Condition-position balance is not 1/2")
    require(len(carryover) == 552, "Directed carryover coverage mismatch")
    return {
        "rows": len(rows),
        "blocks": BLOCK_COUNT,
        "conditionPositionMinimum": min(values),
        "conditionPositionMaximum": max(values),
        "distinctDirectedCarryoverPairs": len(carryover),
    }


def validate_blocks(root: Path, rows: list[dict[str, Any]]) -> dict[str, Any]:
    require(len(rows) == BLOCK_COUNT, "Block-input row count is not 36")
    cell_counts: Counter[str] = Counter()
    cell_sources: dict[str, Counter[str]] = defaultdict(Counter)
    aliases: set[str] = set()
    distinct_sources: set[str] = set()
    verified: dict[str, str] = {}
    reference_count = 0
    for block_index, row in enumerate(rows):
        require(row.get("schema") == "gate14re-mq-formal-block-input-assignment-row-v2", f"Block schema mismatch at {block_index}")
        require(int(row["blockOrdinal"]) == block_index and row["blockId"] == f"MQV2-B{block_index + 1:03d}", f"Block identity mismatch at {block_index}")
        require(int(row["scheduleSeed"]) == SCHEDULE_SEED and int(row["laneCount"]) == LANES, f"Block seed/lane count mismatch at {block_index}")
        inputs = row.get("inputs", [])
        require(len(inputs) == LANES, f"Block {block_index} input count is not 16")
        block_cells: set[str] = set()
        for lane, binding in enumerate(inputs):
            require(int(binding["laneOrdinal"]) == lane, f"Lane ordinal mismatch in block {block_index}")
            alias = str(binding["formalInputAlias"])
            require(alias not in aliases, f"Duplicate formal input alias: {alias}")
            aliases.add(alias)
            cell = str(binding["cellId"])
            require(cell not in block_cells, f"Duplicate cell in block {block_index}: {cell}")
            block_cells.add(cell)
            expected_cell = f"G{int(binding['gridEdge'])}-N{int(binding['agentCount'])}-F{int(binding['changedCellCount'])}"
            require(cell == expected_cell, f"Cell identity mismatch: {alias}")
            source = str(binding["sourceInputId"])
            cell_counts[cell] += 1
            cell_sources[cell][source] += 1
            distinct_sources.add(source)
            reference_count += 1
            for path_key, hash_key in (
                ("sourceRelativePath", "sourceSha256"),
                ("oracleCacheBindingRelativePath", "oracleCacheBindingSha256"),
                ("oraclePassReceiptRelativePath", "oraclePassReceiptSha256"),
                ("oracleAgentTableRelativePath", "oracleAgentTableSha256"),
                ("oracleEventTableRelativePath", "oracleEventTableSha256"),
            ):
                relative = str(binding[path_key])
                expected = str(binding[hash_key])
                previous = verified.get(relative)
                require(previous in (None, expected), f"Conflicting hash bindings for {relative}")
                if previous is None:
                    require(sha256(bound(root, relative)) == expected, f"Input/oracle SHA-256 mismatch: {relative}")
                    verified[relative] = expected
        require(len(block_cells) == LANES, f"Block {block_index} does not contain 16 distinct cells")
    require(len(cell_counts) == 36 and set(cell_counts.values()) == {16}, "Cell coverage is not 36 cells x 16 appearances")
    for cell, counts in cell_sources.items():
        require(len(counts) == 3 and sorted(counts.values()) == [5, 5, 6], f"Source balance is not 5/5/6 for {cell}")
    require(len(distinct_sources) == 108, "Distinct source input count is not 108")
    return {
        "blockRows": len(rows),
        "inputReferences": reference_count,
        "distinctInputs": len(distinct_sources),
        "distinctCells": len(cell_counts),
        "uniqueFilesHashed": len(verified),
    }


def validate_manifest(root: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    require(manifest.get("schema") == "gate14re-mq-formal-implementation-manifest-v2", "Implementation-manifest schema mismatch")
    require(manifest.get("status") == "FROZEN_IMPLEMENTATION_AND_SCHEDULE_READY_FOR_SEPARATE_LAUNCH_AUTHORIZATION", "Implementation-manifest status mismatch")
    require(manifest.get("studyId") == STUDY and manifest.get("designId") == DESIGN, "Implementation-manifest study/design mismatch")
    artifacts = manifest.get("artifacts", [])
    require(len(artifacts) >= 15, "Implementation manifest contains fewer than 15 files")
    seen: set[str] = set()
    for row in artifacts:
        relative = str(row["relativePath"])
        require(relative not in seen, f"Duplicate implementation-manifest path: {relative}")
        seen.add(relative)
        path = bound(root, relative)
        require(path.stat().st_size == int(row["bytes"]), f"Implementation byte mismatch: {relative}")
        require(sha256(path) == str(row["sha256"]), f"Implementation SHA-256 mismatch: {relative}")
    required = {
        "Assets/_Scripts/Research/Editor/Gate14ReMQFormalRunnerV2.cs",
        "Assets/_Scripts/Research/Editor/Gate14ReMQFormalReadinessV2.cs",
        "Assets/_Scripts/Research/MQ/v2/Gate14ReMQFormalPerformanceKernelV2.cs",
        "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_0.ps1",
        PATHS["schedule"], PATHS["blocks"], PATHS["identity_map"], PATHS["science_contract"],
        PATHS["execution_contract"], PATHS["fairness"], PATHS["budget"],
    }
    require(required.issubset(seen), f"Implementation manifest misses required files: {sorted(required - seen)}")
    return {"artifactCount": len(artifacts)}


def validate_launcher_runner_interface(files: dict[str, Path]) -> dict[str, Any]:
    runner = files["formal_runner"].read_text(encoding="utf-8-sig")
    supervisor = files["collection_supervisor"].read_text(encoding="utf-8-sig")
    runner_markers = [
        'Path.Combine(measuredRoot, "raw", "blocks", row.blockId,',
        '"process-" + row.processOrdinal.ToString("D4", CultureInfo.InvariantCulture)',
        'Required(arguments, "--g14mq-output-dir")',
        'IsSha256(authorization.unityExecutableSha256)',
        'unityExecutableSha256 = context.Authorization.unityExecutableSha256',
    ]
    supervisor_markers = [
        "Join-Path $MeasuredRoot 'raw/blocks'",
        "$scheduledRow = $scheduleRows[$ordinal]",
        "Join-Path $rawBlocksRoot ([string]$scheduledRow.blockId)",
        "'process-{0:D4}' -f $ordinal",
        "'--g14mq-output-dir', $outputDirectory",
        "authorization.unityExecutableSha256 -eq $UnityExecutableSha256",
        "terminal.unityExecutableSha256 -eq $UnityExecutableSha256",
        "terminal.laneEvidenceSha256",
        "terminal.batchEvidenceSha256",
        "terminal.outputManifestSha256",
    ]
    for marker in runner_markers:
        require(marker in runner, f"Formal runner output-interface marker missing: {marker}")
    for marker in supervisor_markers:
        require(marker in supervisor, f"Collection supervisor output-interface marker missing: {marker}")
    require("Join-Path $processRoot $directoryName" not in supervisor, "Legacy incompatible supervisor output topology remains")
    return {
        "status": "PASS_EXACT_SUPERVISOR_RUNNER_OUTPUT_TOPOLOGY_COMPATIBILITY",
        "measuredOutputShape": "raw/blocks/<blockId>/process-<ordinal:D4>",
        "runnerMarkersChecked": len(runner_markers),
        "supervisorMarkersChecked": len(supervisor_markers),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    require(root.is_dir(), "Project root is missing")
    require(output.parent.is_dir(), "Validation output parent must already exist")
    require(not output.exists(), "Validation output must be new")
    formal_root = root / "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2"
    require(not formal_root.exists(), "Formal MQ measured root exists before launch authorization")

    files = {name: bound(root, relative) for name, relative in PATHS.items()}
    documents = {name: load_json(path) for name, path in files.items() if path.suffix == ".json"}
    require(all(documents[name].get("studyId") == STUDY for name in ("authorized_design", "power_result", "power_seal", "identity_map", "science_contract", "execution_contract", "fairness", "budget", "implementation_manifest")), "Study ID mismatch")
    require(all(documents[name].get("designId") == DESIGN for name in ("authorized_design", "power_result", "power_seal", "identity_map", "science_contract", "execution_contract", "fairness", "budget", "implementation_manifest")), "Design ID mismatch")

    science_summary = validate_science(root, documents)
    schedule_rows = load_jsonl(files["schedule"])
    schedule_summary = validate_schedule(schedule_rows)
    blocks_summary = validate_blocks(root, load_jsonl(files["blocks"]))
    manifest_summary = validate_manifest(root, documents["implementation_manifest"])
    launcher_runner_interface = validate_launcher_runner_interface(files)

    identity = documents["identity_map"]
    require(identity.get("status") == "FROZEN_AFTER_IDENTITY_BLIND_POWER_SELECTION", "Identity-map status mismatch")
    require(identity.get("mappingOpenedOnlyAfterPowerSelectionSealed") is True, "Identity map opened before seal")
    require(identity.get("formalEffectDataRead") is False and identity.get("formalAnalysisStarted") is False, "Formal effect data was read or analysis started")
    require({row["opaqueAlgorithmSlot"] for row in identity["algorithms"]} == {"OPAQUE-A", "OPAQUE-B"}, "Opaque algorithm slots mismatch")
    verify_reference(root, identity["powerSelectionSeal"], "identity-map power seal")
    for algorithm in identity["algorithms"]:
        require(sha256(bound(root, algorithm["implementationRelativePath"])) == algorithm["implementationSha256"], "Algorithm implementation binding drift")

    execution = documents["execution_contract"]
    require(execution.get("status") == "FROZEN_EXECUTION_CONTRACT_REQUIRES_SEPARATE_LAUNCH_AUTHORIZATION", "Execution-contract status mismatch")
    require(execution["cardinality"] == {"matchedBlocks": 36, "lanesPerBlock": 16, "algorithms": 2, "conditionsPerAlgorithm": 12, "freshUnityProcesses": 864}, "Execution cardinality mismatch")
    require(execution["requiredFutureAuthorization"]["separateUserLaunchAuthorization"] is True, "Separate launch authorization gate missing")
    require(execution["requiredFutureAuthorization"]["formalCollectionCurrentlyAuthorized"] is False and execution["requiredFutureAuthorization"]["formalAnalysisCurrentlyAuthorized"] is False, "Execution contract currently authorizes collection/analysis")
    for key in ("schedule", "blockInputs", "sourceManifest", "identityMap", "fairness", "resourceBudget", "scientificContract"):
        verify_reference(root, execution[key], f"execution-contract {key}")

    budget = documents["budget"]
    require(budget.get("selectedB") == 36 and budget.get("freshUnityProcessCount") == 864, "Budget B/process count mismatch")
    require(float(budget["stressPlanningHours"]) < 168 and budget["sevenDayGateTriggered"] is False, "Budget triggers seven-day gate")
    require(budget.get("maximumConcurrentMeasuredUnityProcesses") == 1 and int(budget["perProcessHardTimeoutSeconds"]) == 1800, "Budget concurrency/timeout mismatch")

    summary_file = documents["schedule_summary"]
    require(summary_file.get("status") == "PASS_DETERMINISTIC_COUNTERBALANCED_B36_SCHEDULE", "Schedule-summary status mismatch")
    require(summary_file.get("formalCollectionStarted") is False and summary_file.get("formalAnalysisStarted") is False, "Schedule summary reports execution/analysis")
    require(summary_file["scheduleSha256"] == sha256(files["schedule"]) and summary_file["blockInputAssignmentsSha256"] == sha256(files["blocks"]), "Schedule-summary hash binding mismatch")

    receipt = {
        "schema": "gate14re-mq-formal-independent-freeze-validation-v2",
        "studyId": STUDY,
        "designId": DESIGN,
        "status": "PASS_INDEPENDENT_STATIC_VALIDATION_READY_FOR_ALGORITHM_FREE_READINESS",
        "validatedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "science": science_summary,
        "schedule": schedule_summary,
        "blocks": blocks_summary,
        "implementation": manifest_summary,
        "launcherRunnerInterface": launcher_runner_interface,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "algorithmsInstantiated": 0,
        "files": [
            {"role": name, "relativePath": PATHS[name], "bytes": files[name].stat().st_size, "sha256": sha256(files[name])}
            for name in sorted(files)
        ],
    }
    payload = json.dumps(receipt, ensure_ascii=False, indent=2) + "\n"
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(payload)
    print(json.dumps({"status": receipt["status"], "output": str(output), "sha256": sha256(output)}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
