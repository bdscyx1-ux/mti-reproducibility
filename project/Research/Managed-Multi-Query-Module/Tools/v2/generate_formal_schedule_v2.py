#!/usr/bin/env python3
"""Generate the prospective Gate14Re-MQ C-FF/IDFF formal-v2 inputs and schedule.

This generator never runs a navigation algorithm and never reads performance
observations.  It uses only frozen structural input metadata, source hashes, and
algorithm-neutral oracle-cache bindings.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


SEED = 141420273
B = 36
LANES_PER_BLOCK = 16
CONDITIONS_PER_ALGORITHM = 12
PROCESS_COUNT = B * 2 * CONDITIONS_PER_ALGORITHM
INPUT_ROOT_REL = (
    "Research/Verification/Gate14Re-ME/"
    "qualification-planning-asset-generation-v4-attempt-002/"
    "planning-assets/inputs/core"
)
ORACLE_ROOT_REL = "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-009/oracle"
POWER_RESULT_REL = (
    "Research/Verification/Gate14Re-MQ-CFF-IDFF/"
    "identity-blind-power-v2-attempt-001/power-result.v2.json"
)
POWER_SEAL_REL = (
    "Research/Verification/Gate14Re-MQ-CFF-IDFF/"
    "identity-blind-power-v2-attempt-001/power-selection-seal-receipt.v2.json"
)
AUTHORIZED_DESIGN_REL = (
    "Research/Verification/Gate14Re-MQ-CFF-IDFF/"
    "formal-design-rule-freeze-v2-attempt-001/formal-mq-authorized-design.v2.json"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel(project: Path, path: Path) -> str:
    return path.resolve().relative_to(project.resolve()).as_posix()


def read_json(path: Path):
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def json_bytes(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(json_bytes(value))


def write_jsonl(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in rows)
    path.write_text(data, encoding="utf-8", newline="")


def williams_base(n: int) -> list[int]:
    if n <= 0 or n % 2:
        raise ValueError("Williams base requires a positive even treatment count")
    result = [0]
    low, high = 1, n - 1
    while len(result) < n:
        result.append(low)
        low += 1
        if len(result) < n:
            result.append(high)
            high -= 1
    return result


def rotate_labels(sequence: list[int], amount: int, n: int) -> list[int]:
    return [int((value + amount) % n) for value in sequence]


def conditions() -> list[dict]:
    structural = [
        ("ST-DIRECT-LARGE-L3", "direct", "LARGE_L3_CCD", 1, "LARGE_L3_CCD-W1", "overhead-sentinel"),
        ("MQ-LARGE-L3-W1", "managed", "LARGE_L3_CCD", 1, "LARGE_L3_CCD-W1", "primary-slope"),
        ("MQ-LARGE-L3-W2", "managed", "LARGE_L3_CCD", 2, "LARGE_L3_CCD-W2", "primary-slope"),
        ("MQ-LARGE-L3-W4", "managed", "LARGE_L3_CCD", 4, "LARGE_L3_CCD-W4", "primary-slope"),
        ("MQ-LARGE-L3-W8", "managed", "LARGE_L3_CCD", 8, "LARGE_L3_CCD-W8", "primary-slope"),
        ("ST-DIRECT-HIGH-FREQUENCY", "direct", "HIGH_FREQUENCY_CCD", 1, "HIGH_FREQUENCY_CCD-W1", "overhead-sentinel"),
        ("MQ-HIGH-FREQUENCY-W1", "managed", "HIGH_FREQUENCY_CCD", 1, "HIGH_FREQUENCY_CCD-W1", "primary-slope"),
        ("MQ-HIGH-FREQUENCY-W2", "managed", "HIGH_FREQUENCY_CCD", 2, "HIGH_FREQUENCY_CCD-W2", "primary-slope"),
        ("MQ-HIGH-FREQUENCY-W4", "managed", "HIGH_FREQUENCY_CCD", 4, "HIGH_FREQUENCY_CCD-W4", "primary-slope"),
        ("MQ-HIGH-FREQUENCY-W8", "managed", "HIGH_FREQUENCY_CCD", 8, "HIGH_FREQUENCY_CCD-W8", "primary-slope"),
        ("MQ-DUAL-CCD-W8-4PLUS4", "managed", "DUAL_CCD_BALANCED", 8, "DUAL_CCD_BALANCED-W8", "key-secondary"),
        ("MQ-DUAL-CCD-W16-8PLUS8", "managed", "DUAL_CCD_BALANCED", 16, "DUAL_CCD_BALANCED-W16", "key-secondary"),
    ]
    rows = []
    for slot_index, slot in enumerate(("OPAQUE-A", "OPAQUE-B")):
        for within, item in enumerate(structural):
            rows.append(
                {
                    "conditionIndex": slot_index * CONDITIONS_PER_ALGORITHM + within,
                    "opaqueAlgorithmSlot": slot,
                    "withinAlgorithmConditionIndex": within,
                    "conditionId": item[0],
                    "executorMode": item[1],
                    "topologyRole": item[2],
                    "workerCount": item[3],
                    "affinityPlanId": item[4],
                    "analysisRole": item[5],
                }
            )
    return rows


def load_source_inputs(project: Path) -> tuple[list[dict], dict[tuple[int, int, int], list[dict]]]:
    input_root = project / INPUT_ROOT_REL
    files = sorted(input_root.glob("*.json"))
    if len(files) != 108:
        raise RuntimeError(f"Expected 108 frozen core inputs, found {len(files)}")
    all_rows: list[dict] = []
    by_cell: dict[tuple[int, int, int], list[dict]] = defaultdict(list)
    for ordinal, path in enumerate(files):
        value = read_json(path)
        required = (
            value.get("schema") == "gate14re-me-qualification-input-bundle-v1"
            and value.get("designRegion") == "core"
            and value.get("inputId")
            and value.get("superblockId")
        )
        if not required:
            raise RuntimeError(f"Invalid frozen core input: {path}")
        cell = (int(value["gridEdge"]), int(value["agentCount"]), int(value["changedCellCount"]))
        oracle_dir = project / ORACLE_ROOT_REL / value["superblockId"]
        cache_path = oracle_dir / "oracle-cache-binding-receipt.v4_1.json"
        pass_path = oracle_dir / "oracle-pass-receipt.v1.json"
        agent_path = oracle_dir / "oracle-agent-checks.raw.v1.jsonl"
        event_path = oracle_dir / "oracle-event-checks.raw.v1.jsonl"
        for member in (cache_path, pass_path, agent_path, event_path):
            if not member.is_file():
                raise RuntimeError(f"Missing frozen oracle member: {member}")
        cache = read_json(cache_path)
        if not (
            cache.get("status") == "PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V4_1"
            and cache.get("inputId") == value["inputId"]
            and cache.get("superblockId") == value["superblockId"]
            and cache.get("inputSha256") == sha256(path)
            and cache.get("oraclePassReceiptSha256") == sha256(pass_path)
            and cache.get("agentTableSha256") == sha256(agent_path)
            and cache.get("eventTableSha256") == sha256(event_path)
        ):
            raise RuntimeError(f"Oracle cache binding mismatch: {cache_path}")
        row = {
            "sourceOrdinal": ordinal,
            "sourceInputId": value["inputId"],
            "sourceSuperblockId": value["superblockId"],
            "gridEdge": cell[0],
            "agentCount": cell[1],
            "changedCellCount": cell[2],
            "sourceRelativePath": rel(project, path),
            "sourceSha256": sha256(path),
            "oracleCacheBindingRelativePath": rel(project, cache_path),
            "oracleCacheBindingSha256": sha256(cache_path),
            "oraclePassReceiptRelativePath": rel(project, pass_path),
            "oraclePassReceiptSha256": sha256(pass_path),
            "oracleAgentTableRelativePath": rel(project, agent_path),
            "oracleAgentTableSha256": sha256(agent_path),
            "oracleAgentTableRows": int(cache["agentTableRows"]),
            "oracleEventTableRelativePath": rel(project, event_path),
            "oracleEventTableSha256": sha256(event_path),
            "oracleEventTableRows": int(cache["eventTableRows"]),
        }
        all_rows.append(row)
        by_cell[cell].append(row)
    if len(by_cell) != 36 or any(len(items) != 3 for items in by_cell.values()):
        raise RuntimeError("Expected exactly 36 GxNxF cells with three frozen inputs per cell")
    return all_rows, by_cell


def make_blocks(by_cell: dict[tuple[int, int, int], list[dict]]) -> list[dict]:
    cells = sorted(by_cell)
    occurrences: Counter[tuple[int, int, int]] = Counter()
    replica_counts: dict[tuple[int, int, int], Counter[int]] = defaultdict(Counter)
    blocks = []
    for block_ordinal in range(B):
        selected_cells = [cells[(block_ordinal + offset) % len(cells)] for offset in range(LANES_PER_BLOCK)]
        if len(set(selected_cells)) != LANES_PER_BLOCK:
            raise RuntimeError("Block contains duplicate GxNxF cells")
        rng = random.Random(SEED + 1000 + block_ordinal)
        rng.shuffle(selected_cells)
        bindings = []
        for lane_ordinal, cell in enumerate(selected_cells):
            occurrence = occurrences[cell]
            cell_index = cells.index(cell)
            replica_index = (occurrence + cell_index) % 3
            source = by_cell[cell][replica_index]
            occurrences[cell] += 1
            replica_counts[cell][replica_index] += 1
            binding = dict(source)
            binding.update(
                {
                    "laneOrdinal": lane_ordinal,
                    "formalInputAlias": f"MQV2-B{block_ordinal + 1:03d}-L{lane_ordinal:02d}",
                    "cellId": f"G{cell[0]}-N{cell[1]}-F{cell[2]}",
                    "cellOccurrenceOrdinal": occurrence,
                    "sourceReplicaIndexWithinCell": replica_index,
                }
            )
            bindings.append(binding)
        blocks.append(
            {
                "schema": "gate14re-mq-formal-block-input-assignment-row-v2",
                "blockOrdinal": block_ordinal,
                "blockId": f"MQV2-B{block_ordinal + 1:03d}",
                "scheduleSeed": SEED,
                "laneCount": LANES_PER_BLOCK,
                "inputs": bindings,
            }
        )
    if set(occurrences.values()) != {16}:
        raise RuntimeError(f"Each GxNxF cell must appear exactly 16 times: {sorted(set(occurrences.values()))}")
    for cell, counts in replica_counts.items():
        if sorted(counts.values()) != [5, 5, 6]:
            raise RuntimeError(f"Cell {cell} is not 6/5/5 balanced across its three source inputs: {counts}")
    return blocks


def make_schedule(condition_rows: list[dict]) -> tuple[list[dict], dict]:
    n = len(condition_rows)
    if n != 24:
        raise RuntimeError("Formal condition cardinality must be 24")
    base = williams_base(n)
    reverse_base = list(reversed(base))
    rng = random.Random(SEED + 2000)
    reverse_rotations = sorted(rng.sample(list(range(n)), B - n))
    block_sequences = [rotate_labels(base, block, n) for block in range(n)]
    block_sequences.extend(rotate_labels(reverse_base, rotation, n) for rotation in reverse_rotations)
    if len(block_sequences) != B:
        raise RuntimeError("Counterbalanced block sequence count mismatch")

    rows = []
    position_counts = [[0 for _ in range(n)] for _ in range(n)]
    carryover = Counter()
    process_ordinal = 0
    for block_ordinal, sequence in enumerate(block_sequences):
        if sorted(sequence) != list(range(n)):
            raise RuntimeError("A block sequence is not a permutation of all conditions")
        for position, condition_index in enumerate(sequence):
            condition = condition_rows[condition_index]
            position_counts[condition_index][position] += 1
            if position > 0:
                carryover[(sequence[position - 1], condition_index)] += 1
            rows.append(
                {
                    "schema": "gate14re-mq-formal-process-schedule-row-v2",
                    "processOrdinal": process_ordinal,
                    "blockOrdinal": block_ordinal,
                    "blockId": f"MQV2-B{block_ordinal + 1:03d}",
                    "positionWithinBlock": position,
                    "conditionIndex": condition_index,
                    "opaqueAlgorithmSlot": condition["opaqueAlgorithmSlot"],
                    "withinAlgorithmConditionIndex": condition["withinAlgorithmConditionIndex"],
                    "conditionId": condition["conditionId"],
                    "executorMode": condition["executorMode"],
                    "topologyRole": condition["topologyRole"],
                    "workerCount": condition["workerCount"],
                    "affinityPlanId": condition["affinityPlanId"],
                    "analysisRole": condition["analysisRole"],
                    "inputAssignmentRowOrdinal": block_ordinal,
                    "scheduleSeed": SEED,
                    "replacement": None,
                }
            )
            process_ordinal += 1
    if process_ordinal != PROCESS_COUNT:
        raise RuntimeError("Formal process cardinality mismatch")
    flattened = [value for row in position_counts for value in row]
    if min(flattened) != 1 or max(flattened) != 2:
        raise RuntimeError("Every condition-position cell must occur once or twice across B=36")
    summary = {
        "baseSequence": base,
        "reverseBaseSequence": reverse_base,
        "reverseRotations": reverse_rotations,
        "positionCountMinimum": min(flattened),
        "positionCountMaximum": max(flattened),
        "distinctDirectedCarryoverPairs": len(carryover),
    }
    return rows, summary


def bound(project: Path, relative_path: str) -> dict:
    path = project / relative_path
    return {"relativePath": relative_path, "bytes": path.stat().st_size, "sha256": sha256(path)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--created-at-utc")
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    created = args.created_at_utc or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    for required in (POWER_RESULT_REL, POWER_SEAL_REL, AUTHORIZED_DESIGN_REL):
        if not (project / required).is_file():
            raise RuntimeError(f"Required frozen prerequisite is missing: {required}")
    power = read_json(project / POWER_RESULT_REL)
    if power.get("selectedB") != B or power.get("status") != "PASS_IDENTITY_BLIND_PRIMARY_POWER_B_SELECTED_ELIGIBLE_FOR_FINAL_FREEZE":
        raise RuntimeError("Frozen power result does not select B=36")

    source_rows, by_cell = load_source_inputs(project)
    block_rows = make_blocks(by_cell)
    condition_rows = conditions()
    schedule_rows, counterbalance_summary = make_schedule(condition_rows)

    formal_inputs_dir = project / "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2"
    execution_dir = project / "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2"
    design_dir = project / "Research/Gate14Re-MQ-CFF-IDFF/Design/v2"
    block_path = formal_inputs_dir / "formal-block-input-assignments.v2.jsonl"
    source_manifest_path = formal_inputs_dir / "formal-input-source-manifest.v2.json"
    schedule_path = execution_dir / "formal-process-schedule.v2.jsonl"
    identity_path = execution_dir / "opaque-algorithm-identity-map.v2.json"
    fairness_path = design_dir / "fairness-and-topology-binding.v2.json"
    budget_path = design_dir / "formal-mq-resource-budget.v2.json"
    science_path = design_dir / "formal-mq-scientific-and-analysis-contract.v2.json"
    execution_contract_path = design_dir / "formal-mq-execution-contract.v2.json"

    write_jsonl(block_path, block_rows)
    write_jsonl(schedule_path, schedule_rows)
    write_json(
        source_manifest_path,
        {
            "schema": "gate14re-mq-formal-input-source-manifest-v2",
            "studyId": "Gate14Re-MQ-CFF-IDFF",
            "designId": "gate14re-mq-cff-idff-formal-v2",
            "status": "FROZEN_REUSED_SOURCE_INPUTS_AND_ALGORITHM_NEUTRAL_ORACLE_CACHES",
            "sourceInputCount": len(source_rows),
            "structuralCellCount": len(by_cell),
            "sourceInputsPerCell": 3,
            "files": source_rows,
            "createdAtUtc": created,
        },
    )

    identity = {
        "schema": "gate14re-mq-formal-opaque-algorithm-identity-map-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_AFTER_IDENTITY_BLIND_POWER_SELECTION",
        "mappingOpenedOnlyAfterPowerSelectionSealed": True,
        "powerSelectionSeal": bound(project, POWER_SEAL_REL),
        "algorithms": [
            {
                "opaqueAlgorithmSlot": "OPAQUE-A",
                "algorithmId": "C-FF",
                "implementationRelativePath": "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
                "implementationSha256": sha256(project / "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs"),
            },
            {
                "opaqueAlgorithmSlot": "OPAQUE-B",
                "algorithmId": "IDFF",
                "implementationRelativePath": "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
                "implementationSha256": sha256(project / "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs"),
            },
        ],
        "formalEffectDataRead": False,
        "formalAnalysisStarted": False,
        "createdAtUtc": created,
    }
    write_json(identity_path, identity)

    fairness = {
        "schema": "gate14re-mq-formal-fairness-and-topology-binding-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_FAIRNESS_TOPOLOGY_AND_ASSIGNMENT",
        "host": {
            "processorFamily": "AMD-Ryzen-9-7950X3D",
            "physicalCoreCount": 16,
            "ccdCount": 2,
            "physicalCoresPerCcd": 8,
            "causalCcdAttributionPermitted": False,
        },
        "workerRules": {
            "hardWindowsCpuSetBinding": True,
            "oneLogicalSiblingPerPhysicalCore": True,
            "laneAssignment": "lane-ordinal-mod-worker-count",
            "outputRestore": "ascending-lane-ordinal",
            "onePrivateGridPerLane": True,
            "onePrivatePlannerPerLane": True,
            "plannerSharedAcrossThreads": False,
            "strictSerialFreshUnityProcesses": True,
            "maximumConcurrentMeasuredUnityProcesses": 1,
            "retry": False,
            "replacement": False,
            "partialBatchAcceptance": False,
        },
        "conditionMatrix": condition_rows,
        "boundPrerequisites": [
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/external-freeze-receipt.v1.json"),
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/terminal-receipt.v1.json"),
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/topology-snapshot.v1.json"),
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/affinity-plans.v1.json"),
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/external-freeze-receipt.v1.json"),
            bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/terminal-receipt.v1.json"),
        ],
        "boundSources": [
            bound(project, "Assets/_Scripts/Research/MQ/v1/WindowsCpuTopologyV1.cs"),
            bound(project, "Assets/_Scripts/Research/MQ/v1/ManagedMultiQueryExecutorV1.cs"),
            bound(project, "Assets/_Scripts/Research/MQ/v2/Gate14ReMQFormalPerformanceKernelV2.cs"),
            bound(project, "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs"),
            bound(project, "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs"),
            bound(project, "Assets/_Scripts/Research/Grid/ResearchNavigationGrid.cs"),
            bound(project, "Assets/_Scripts/Research/Navigation/NavigationContracts.cs"),
            bound(project, "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs"),
            bound(project, "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs"),
        ],
        "createdAtUtc": created,
    }
    write_json(fairness_path, fairness)

    budget = {
        "schema": "gate14re-mq-formal-resource-budget-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_RESOURCE_AND_TIMEOUT_GATES",
        "selectedB": B,
        "freshUnityProcessCount": PROCESS_COUNT,
        "nominalPlanningHours": 6.309782,
        "stressMultiplier": 1.9,
        "stressPlanningHours": 11.988586,
        "sevenDayThresholdHours": 168,
        "sevenDayGateTriggered": False,
        "perProcessHardTimeoutSeconds": 1800,
        "wholeAttemptHardCeilingHours": 168,
        "maximumConcurrentMeasuredUnityProcesses": 1,
        "failurePolicy": "fail closed; no retry, resume, top-up, replacement, merge, skip, or reorder",
        "runtimeSource": bound(project, "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-runtime-analysis-v2/engineering-runtime-diagnostics.v2.json"),
        "powerSource": bound(project, POWER_RESULT_REL),
        "createdAtUtc": created,
    }
    write_json(budget_path, budget)

    science = {
        "schema": "gate14re-mq-formal-scientific-and-analysis-contract-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_FINAL_B36_SCIENTIFIC_DESIGN_FORMAL_COLLECTION_NOT_AUTHORIZED",
        "paperRole": "supplemental managed multi-query deployment and scalability evidence strengthening the existing paper",
        "selectedB": B,
        "matchedBlock": {
            "privateWorkloadLanes": LANES_PER_BLOCK,
            "processesPerBlock": 24,
            "sameInputsAcrossAll24Processes": True,
            "primaryInferenceUnit": "complete matched block",
        },
        "endpoint": {
            "field": "batchWallSeconds",
            "direction": "lower-is-better",
            "transform": "natural-log",
            "singleCcdEstimand": "within-block equal-weight OLS slope of log(batchWallSeconds) on log2(workerCount) for W1 W2 W4 W8",
            "dualCcdEstimand": "within-block log(batchWallSeconds_W16 / batchWallSeconds_W8)",
        },
        "confirmatoryPrimaryFamily": ["P1", "P2", "P3", "P4"],
        "keySecondaryFamily": ["S1", "S2"],
        "keySecondaryFormerIds": {"S1": "P5", "S2": "P6"},
        "mipe": {"ratio": 0.90, "logScaleExact": -0.10536051565782628},
        "primaryInference": {
            "null": "estimand >= 0",
            "alternative": "estimand < 0",
            "oneSided": True,
            "familywiseAlpha": 0.05,
            "multiplicity": "Holm strong FWER across exactly P1-P4",
            "claimRule": "Holm-adjusted p<0.05, multiplicity-compatible confidence interval below zero, and point estimate <= -0.10536051565782628",
        },
        "keySecondaryInference": {
            "gate": "open only if all P1-P4 reject under the frozen primary Holm procedure",
            "familywiseAlphaWhenOpen": 0.05,
            "multiplicityWhenOpen": "Holm across exactly S1-S2",
            "claimRule": "when open: adjusted p<0.05, multiplicity-compatible confidence interval below zero, and point estimate <= -0.10536051565782628; otherwise descriptive only",
            "usedForBSelection": False,
            "poweredGuarantee": False,
            "failureInvalidatesPrimaryConclusions": False,
        },
        "otherSecondary": {
            "stDirectVersusMqW1": "descriptive implementation-overhead sentinel only",
            "crossAlgorithmInteractions": "exploratory estimates and intervals only",
            "algorithmWinnerOrRanking": False,
            "movementTransferSentinelIncluded": False,
        },
        "stopping": {
            "benefit": False,
            "futility": False,
            "adaptiveReestimation": False,
            "retry": False,
            "replacement": False,
            "topUp": False,
        },
        "correctness": {
            "allInputAndOracleHashesHardBound": True,
            "everyMeasuredQueryComparedWithFrozenAlgorithmNeutralOracleAfterBatch": True,
            "oracleComparisonInsideMeasuredBatch": False,
            "allAffinityBindingsObserved": True,
            "allLanesAndBatchesComplete": True,
            "correctnessWeightedWithPerformance": False,
        },
        "prerequisites": {
            "authorizedDesign": bound(project, AUTHORIZED_DESIGN_REL),
            "powerResult": bound(project, POWER_RESULT_REL),
            "powerSelectionSeal": bound(project, POWER_SEAL_REL),
        },
        "formalCollectionAuthorized": False,
        "formalAnalysisAuthorized": False,
        "createdAtUtc": created,
    }
    write_json(science_path, science)

    block_hash = sha256(block_path)
    schedule_hash = sha256(schedule_path)
    source_manifest_hash = sha256(source_manifest_path)
    identity_hash = sha256(identity_path)
    fairness_hash = sha256(fairness_path)
    budget_hash = sha256(budget_path)
    science_hash = sha256(science_path)

    execution_contract = {
        "schema": "gate14re-mq-formal-execution-contract-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_EXECUTION_CONTRACT_REQUIRES_SEPARATE_LAUNCH_AUTHORIZATION",
        "cardinality": {
            "matchedBlocks": B,
            "lanesPerBlock": LANES_PER_BLOCK,
            "algorithms": 2,
            "conditionsPerAlgorithm": CONDITIONS_PER_ALGORITHM,
            "freshUnityProcesses": PROCESS_COUNT,
        },
        "schedule": {**bound(project, rel(project, schedule_path)), "expectedSchema": "gate14re-mq-formal-process-schedule-row-v2"},
        "blockInputs": {**bound(project, rel(project, block_path)), "expectedSchema": "gate14re-mq-formal-block-input-assignment-row-v2"},
        "sourceManifest": bound(project, rel(project, source_manifest_path)),
        "identityMap": bound(project, rel(project, identity_path)),
        "fairness": bound(project, rel(project, fairness_path)),
        "resourceBudget": bound(project, rel(project, budget_path)),
        "scientificContract": bound(project, rel(project, science_path)),
        "processPolicy": {
            "freshUnityProcessPerScheduleRow": True,
            "strictSerial": True,
            "maximumConcurrentMeasuredUnityProcesses": 1,
            "ordinalOrder": "exactly 0..863",
            "noRetryResumeTopUpMergeSkipReorderReplacement": True,
            "trustedProcessIdentityRequired": True,
            "naturalExitCodeZeroRequired": True,
        },
        "attemptPolicy": {
            "measuredRootMustBeNew": True,
            "failurePreservedImmutable": True,
            "successRequires864TrustedNaturalZeroExits": True,
            "successRequiresAllOracleAndAffinityHardGates": True,
        },
        "requiredFutureAuthorization": {
            "separateUserLaunchAuthorization": True,
            "executionAuthorizationReceiptBoundToAllFrozenHashes": True,
            "formalCollectionCurrentlyAuthorized": False,
            "formalAnalysisCurrentlyAuthorized": False,
        },
        "createdAtUtc": created,
    }
    write_json(execution_contract_path, execution_contract)

    schedule_summary = {
        "schema": "gate14re-mq-formal-process-schedule-summary-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "PASS_DETERMINISTIC_COUNTERBALANCED_B36_SCHEDULE",
        "scheduleSeed": SEED,
        "matchedBlocks": B,
        "lanesPerBlock": LANES_PER_BLOCK,
        "processesPerBlock": 24,
        "freshUnityProcessCount": PROCESS_COUNT,
        "structuralCellCount": 36,
        "appearancesPerCell": 16,
        "sourceInputBalanceWithinCell": [5, 5, 6],
        "blockCellRule": "16 distinct cyclic GxNxF cells per block, lane order deterministically shuffled",
        "processOrderRule": "24 Williams-label rotations followed by 12 seeded distinct rotations of the reversed Williams base",
        "counterbalance": counterbalance_summary,
        "scheduleSha256": schedule_hash,
        "blockInputAssignmentsSha256": block_hash,
        "sourceManifestSha256": source_manifest_hash,
        "identityMapSha256": identity_hash,
        "fairnessBindingSha256": fairness_hash,
        "resourceBudgetSha256": budget_hash,
        "scientificContractSha256": science_hash,
        "executionContractSha256": sha256(execution_contract_path),
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "createdAtUtc": created,
    }
    write_json(execution_dir / "formal-process-schedule-summary.v2.json", schedule_summary)

    print(json.dumps({
        "status": "PASS_GENERATED_UNFROZEN_CANDIDATE",
        "B": B,
        "processes": PROCESS_COUNT,
        "scheduleSha256": schedule_hash,
        "blockAssignmentsSha256": block_hash,
        "sourceManifestSha256": source_manifest_hash,
        "identityMapSha256": identity_hash,
        "fairnessSha256": fairness_hash,
        "budgetSha256": budget_hash,
        "scienceSha256": science_hash,
        "executionContractSha256": sha256(execution_contract_path),
    }, indent=2))


if __name__ == "__main__":
    main()
