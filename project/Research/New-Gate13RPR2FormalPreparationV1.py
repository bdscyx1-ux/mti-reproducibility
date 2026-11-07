#!/usr/bin/env python3
"""Deterministically generate Gate 13R-PR2 non-executing S48/H48 artifacts.

This generator only reads frozen upstream evidence and writes design artifacts. It
contains no editor-launch or experiment-execution path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[1]
RESEARCH_ROOT = PROJECT_ROOT / "Research"

AUTH_PATH = RESEARCH_ROOT / "Gate13R_PR2_NonExecuting_Formal_Preparation_Authorization.v1.json"
AMENDMENT_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Amendment.v1.json"
SPEC_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Specification.v1.md"
TEST_DESIGN_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Test_Design.v1.md"
SCHEMA_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Schema.v1.json"
PREWRITE_PATH = RESEARCH_ROOT / "Gate13R_PR2_PreWrite_Preservation_Audit.v1.json"
SNAPSHOT_PATH = RESEARCH_ROOT / "Gate13R_PR2_Preparation_Environment_Snapshot.v1.json"

MATRIX_PATH = RESEARCH_ROOT / "FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json"
BUNDLE_PATH = RESEARCH_ROOT / "FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json"
PRESET_PATH = RESEARCH_ROOT / "PlayableExperiments/Gate11R_5pct/v1/algorithm-preset-catalog.json"
PR1_AMENDMENT_PATH = RESEARCH_ROOT / "Gate13R_RQAligned_Preregistration_Amendment.v1.json"
METRIC_REGISTRY_PATH = RESEARCH_ROOT / "Gate13R_RQAligned_Metric_Registry.v1.json"
CONTRAST_REGISTRY_PATH = RESEARCH_ROOT / "Gate13R_RQAligned_Contrast_Registry.v1.json"
DECISION_TABLE_PATH = RESEARCH_ROOT / "Analysis/Gate13R_RQAligned_Preregistration/v1/wallclock-storage-decision-table.json"
PR1B_PLAN_PATH = RESEARCH_ROOT / "Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json"
PR1B_READINESS_PATH = RESEARCH_ROOT / "Gate13R_PR1B_v4_CompositeProcessIdentity_Recovery_Readiness_Checkpoint.v1.json"
PR1B_RECOVERY_PATH = RESEARCH_ROOT / "Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1/recovered-order-effect-analysis.json"

CONFIG_NAME = "Gate13R_PR2_Formal_Campaign_Config.v1.json"
SCHEDULE_NAME = "Gate13R_PR2_Formal_Williams_Matched_Schedule.v1.jsonl"
MANIFEST_NAME = "Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v1.json"
PREFLIGHT_NAME = "Gate13R_PR2_Storage_WallClock_Preflight.v1.json"
PROVENANCE_NAME = "Gate13R_PR2_Formal_Preparation_Provenance.v1.json"
SUMMARY_NAME = "Gate13R_PR2_Formal_Preparation_Generation_Summary.v1.json"

OFFICIAL_RELATIVE = {
    "config": f"Research/{CONFIG_NAME}",
    "schedule": f"Research/{SCHEDULE_NAME}",
    "manifest": f"Research/{MANIFEST_NAME}",
    "preflight": f"Research/{PREFLIGHT_NAME}",
    "provenance": f"Research/{PROVENANCE_NAME}",
    "summary": f"Research/{SUMMARY_NAME}",
}

SHARED_COHORT = "four-algorithm-shared-goal-v1"
PER_AGENT_COHORT = "per-agent-heterogeneous-goal-v1"
GROUPED_COHORT = "grouped-field-heterogeneous-goal-v1"
ALGORITHM_SLUG = {"A*-R": "astar-r", "D*L": "dstar-l", "C-FF": "cff", "IDFF": "idff"}
FORMAL_DESIGN_ID = "gate13r-rq-aligned-s48-h48-strict-serial-v1"
EXECUTION_DESIGN_ID = "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1"
FORMAL_ROOT_RELATIVE = "Research/FormalRuns/Gate13R_RQAligned_S48H48/v1"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def compact_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_identity(path: Path) -> dict[str, Any]:
    return {
        "relativePath": path.relative_to(PROJECT_ROOT).as_posix(),
        "rawBytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def atomic_write(path: Path, data: bytes) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite versioned artifact: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def preset_lookup(preset_catalog: dict[str, Any]) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for preset in preset_catalog["presets"]:
        key = (preset["campaignId"], preset["algorithmId"])
        require(key not in result, f"Duplicate preset identity: {key}")
        result[key] = preset
    return result


def build_entry(
    campaign: dict[str, Any],
    preset_map: dict[tuple[str, str], dict[str, Any]],
    block_id: str,
    output_relative_path: str,
    position: int,
    algorithm_id: str,
    predecessor: str,
) -> dict[str, Any]:
    preset = preset_map[(campaign["campaignId"], algorithm_id)]
    slug = ALGORITHM_SLUG[algorithm_id]
    run_id = f"{block_id}-p{position:02d}-{slug}"
    return {
        "algorithmId": algorithm_id,
        "childDirectory": f"runs/p{position:02d}-{slug}",
        "position": position,
        "predecessorAlgorithmId": predecessor,
        "presetAssetGuid": preset["presetAssetGuid"],
        "presetAssetPath": preset["presetAssetPath"],
        "presetId": preset["presetId"],
        "presetSha256": preset["presetSha256"],
        "runId": run_id,
        "sampleOutputRelativePath": f"{output_relative_path}/runs/p{position:02d}-{slug}",
    }


def base_record(
    campaign: dict[str, Any],
    campaign_ordinal: int,
    block_ordinal: int,
    row_index: int,
    global_ordinal: int,
    preset_map: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any]:
    block_id = f"g13rpr2-c{campaign_ordinal:02d}-b{block_ordinal:04d}"
    output_relative_path = (
        f"campaigns/c{campaign_ordinal:02d}-{campaign['campaignId']}/blocks/b{block_ordinal:04d}"
    )
    row_map = {int(row["rowIndex"]): row["algorithms"] for row in campaign["williamsRows"]}
    algorithms = row_map[row_index]
    entries = []
    predecessor = "NONE"
    for position, algorithm_id in enumerate(algorithms, start=1):
        entries.append(
            build_entry(
                campaign,
                preset_map,
                block_id,
                output_relative_path,
                position,
                algorithm_id,
                predecessor,
            )
        )
        predecessor = algorithm_id
    return {
        "blockId": block_id,
        "campaignBlockOrdinal": block_ordinal,
        "campaignId": campaign["campaignId"],
        "campaignOrdinal": campaign_ordinal,
        "comparisonCohortId": campaign["comparisonCohortId"],
        "entries": entries,
        "expectedSampleCount": len(entries),
        "freshProcessRequired": True,
        "globalProcessOrdinal": global_ordinal,
        "maximumBlocksInProcess": 1,
        "outputRelativePath": output_relative_path,
        "processIdentityPolicy": "assign-os-pid-plus-process-start-time-at-formal-execution",
        "profileAssetGuid": campaign["profileAssetGuid"],
        "profileAssetPath": campaign["profileAssetPath"],
        "profileSha256": campaign["profileSha256"],
        "scenarioFingerprintSha256": campaign["scenarioFingerprintSha256"],
        "scenarioId": campaign["scenarioId"],
        "scenarioRelativePath": campaign["scenarioRelativePath"],
        "scenarioSha256": campaign["scenarioSha256"],
        "scheduleKind": "gate13r-pr2-rq-aligned-s48-h48-process-record-v1",
        "schemaVersion": 1,
        "sceneAssetPath": campaign["sceneAssetPath"],
        "williamsRowIndex": row_index,
    }


def build_schedule(
    matrix: dict[str, Any], preset_map: dict[tuple[str, str], dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    campaigns = matrix["campaigns"]
    campaign_ordinal = {campaign["campaignId"]: index for index, campaign in enumerate(campaigns, start=1)}
    campaign_summary: dict[str, dict[str, Any]] = {
        campaign["campaignId"]: {
            "processOrdinals": [],
            "rowCounts": Counter(),
            "sampleCount": 0,
        }
        for campaign in campaigns
    }
    records: list[dict[str, Any]] = []
    global_ordinal = 0

    shared_campaigns = [campaign for campaign in campaigns if campaign["comparisonCohortId"] == SHARED_COHORT]
    for shared_index, campaign in enumerate(shared_campaigns):
        ordinal = campaign_ordinal[campaign["campaignId"]]
        for block_ordinal in range(1, 49):
            row_index = (block_ordinal - 1 + shared_index) % 4
            global_ordinal += 1
            record = base_record(campaign, ordinal, block_ordinal, row_index, global_ordinal, preset_map)
            record["matchedSuperblock"] = None
            records.append(record)
            summary = campaign_summary[campaign["campaignId"]]
            summary["processOrdinals"].append(global_ordinal)
            summary["rowCounts"][row_index] += 1
            summary["sampleCount"] += 4

    per_agent_by_scenario = {
        campaign["scenarioId"]: campaign
        for campaign in campaigns
        if campaign["comparisonCohortId"] == PER_AGENT_COHORT
    }
    grouped_by_scenario = {
        campaign["scenarioId"]: campaign
        for campaign in campaigns
        if campaign["comparisonCohortId"] == GROUPED_COHORT
    }
    hetero_scenarios = [
        campaign["scenarioId"]
        for campaign in campaigns
        if campaign["comparisonCohortId"] == PER_AGENT_COHORT
    ]
    require(set(hetero_scenarios) == set(grouped_by_scenario), "Heterogeneous cohort scenario mismatch")

    for scenario_index, scenario_id in enumerate(hetero_scenarios, start=1):
        per_agent = per_agent_by_scenario[scenario_id]
        grouped = grouped_by_scenario[scenario_id]
        require(per_agent["scenarioSha256"] == grouped["scenarioSha256"], "Matched scenario hash mismatch")
        require(
            per_agent["scenarioFingerprintSha256"] == grouped["scenarioFingerprintSha256"],
            "Matched scenario fingerprint mismatch",
        )
        rotation = (scenario_index - 1) % 4
        for superblock_ordinal in range(1, 49):
            pattern_index = (superblock_ordinal - 1 + rotation) % 4
            cohort_order = "AB" if pattern_index in (0, 2) else "BA"
            row_index = 0 if pattern_index in (0, 1) else 1
            superblock_id = f"g13rpr2-h{scenario_index:02d}-m{superblock_ordinal:04d}"
            pair_ordinals = [global_ordinal + 1, global_ordinal + 2]
            ordered_campaigns = [per_agent, grouped] if cohort_order == "AB" else [grouped, per_agent]
            for process_position, campaign in enumerate(ordered_campaigns, start=1):
                global_ordinal += 1
                ordinal = campaign_ordinal[campaign["campaignId"]]
                record = base_record(
                    campaign,
                    ordinal,
                    superblock_ordinal,
                    row_index,
                    global_ordinal,
                    preset_map,
                )
                cohort_role = "A-PER-AGENT" if campaign["comparisonCohortId"] == PER_AGENT_COHORT else "B-GROUPED-FIELD"
                record["matchedSuperblock"] = {
                    "cohortOrder": cohort_order,
                    "cohortProcessPosition": process_position,
                    "cohortRole": cohort_role,
                    "deterministicInputIdentity": {
                        "repetitionOrdinal": superblock_ordinal,
                        "scenarioFingerprintSha256": campaign["scenarioFingerprintSha256"],
                        "scenarioId": scenario_id,
                        "scenarioSha256": campaign["scenarioSha256"],
                    },
                    "matchedSuperblockId": superblock_id,
                    "matchedSuperblockOrdinal": superblock_ordinal,
                    "pairGlobalProcessOrdinals": pair_ordinals,
                    "scenarioOrdinal": scenario_index,
                }
                records.append(record)
                summary = campaign_summary[campaign["campaignId"]]
                summary["processOrdinals"].append(global_ordinal)
                summary["rowCounts"][row_index] += 1
                summary["sampleCount"] += 2

    require(global_ordinal == 3552, f"Unexpected process count: {global_ordinal}")
    return records, campaign_summary


def campaign_config_entry(
    campaign: dict[str, Any],
    ordinal: int,
    summary: dict[str, Any],
    preset_map: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any]:
    presets = []
    for algorithm_id in campaign["eligibleAlgorithmIds"]:
        preset = preset_map[(campaign["campaignId"], algorithm_id)]
        presets.append(
            {
                "algorithmId": algorithm_id,
                "presetAssetGuid": preset["presetAssetGuid"],
                "presetAssetPath": preset["presetAssetPath"],
                "presetId": preset["presetId"],
                "presetSha256": preset["presetSha256"],
            }
        )
    return {
        "algorithmPresets": presets,
        "blockCount": len(summary["processOrdinals"]),
        "campaignId": campaign["campaignId"],
        "campaignOrdinal": ordinal,
        "comparisonCohortId": campaign["comparisonCohortId"],
        "eligibleAlgorithmIds": campaign["eligibleAlgorithmIds"],
        "globalProcessEndOrdinal": max(summary["processOrdinals"]),
        "globalProcessOrdinals": summary["processOrdinals"],
        "globalProcessStartOrdinal": min(summary["processOrdinals"]),
        "processOrdinalsContiguous": all(
            right == left + 1
            for left, right in zip(summary["processOrdinals"], summary["processOrdinals"][1:])
        ),
        "profileAssetGuid": campaign["profileAssetGuid"],
        "profileAssetPath": campaign["profileAssetPath"],
        "profileSha256": campaign["profileSha256"],
        "sampleCount": summary["sampleCount"],
        "scenarioFingerprintSha256": campaign["scenarioFingerprintSha256"],
        "scenarioId": campaign["scenarioId"],
        "scenarioRelativePath": campaign["scenarioRelativePath"],
        "scenarioSha256": campaign["scenarioSha256"],
        "sceneAssetPath": campaign["sceneAssetPath"],
        "williamsRowCounts": [
            {"count": summary["rowCounts"][int(row["rowIndex"])], "rowIndex": int(row["rowIndex"])}
            for row in campaign["williamsRows"]
        ],
        "williamsRows": campaign["williamsRows"],
    }


def build_manifest(records: list[dict[str, Any]], schedule_data: bytes) -> dict[str, Any]:
    position_balance: Counter[tuple[str, str, int]] = Counter()
    row_balance: Counter[tuple[str, int]] = Counter()
    order_balance: Counter[tuple[str, str]] = Counter()
    order_row_balance: Counter[tuple[str, str, str, int]] = Counter()
    matched_ids: set[str] = set()
    run_ids: set[str] = set()
    block_ids: set[str] = set()
    output_paths: set[str] = set()
    sample_count = 0
    for record in records:
        cohort = record["comparisonCohortId"]
        row_balance[(cohort, record["williamsRowIndex"])] += 1
        block_ids.add(record["blockId"])
        output_paths.add(record["outputRelativePath"])
        for entry in record["entries"]:
            sample_count += 1
            run_ids.add(entry["runId"])
            output_paths.add(entry["sampleOutputRelativePath"])
            position_balance[(cohort, entry["algorithmId"], entry["position"])] += 1
        matched = record["matchedSuperblock"]
        if matched is not None:
            matched_ids.add(matched["matchedSuperblockId"])
            if matched["cohortProcessPosition"] == 1:
                scenario_id = record["scenarioId"]
                order = matched["cohortOrder"]
                order_balance[(scenario_id, order)] += 1
                order_row_balance[(scenario_id, order, "per-agent", record["williamsRowIndex"])] += 1
                order_row_balance[(scenario_id, order, "grouped-field", record["williamsRowIndex"])] += 1
    require(len(block_ids) == len(records), "Duplicate block ID")
    require(len(run_ids) == sample_count, "Duplicate run ID")
    require(len(output_paths) == len(records) + sample_count, "Duplicate output path")
    return {
        "campaignCount": 74,
        "formalCampaignExecuted": False,
        "formalDesignId": FORMAL_DESIGN_ID,
        "formalExecutionAuthorized": False,
        "heterogeneousMatchedSuperblockCount": len(matched_ids),
        "manifestKind": "gate13r-pr2-rq-aligned-s48-h48-schedule-manifest-v1",
        "orderBalanceByScenario": [
            {"AB": order_balance[(scenario_id, "AB")], "BA": order_balance[(scenario_id, "BA")], "scenarioId": scenario_id}
            for scenario_id in sorted({key[0] for key in order_balance})
        ],
        "orderRowBalanceByScenario": [
            {
                "cohort": cohort,
                "cohortOrder": order,
                "count": count,
                "rowIndex": row,
                "scenarioId": scenario_id,
            }
            for (scenario_id, order, cohort, row), count in sorted(order_row_balance.items())
        ],
        "positionBalance": [
            {
                "algorithmId": algorithm,
                "comparisonCohortId": cohort,
                "count": count,
                "position": position,
            }
            for (cohort, algorithm, position), count in sorted(position_balance.items())
        ],
        "processRecordCount": len(records),
        "rowBalance": [
            {"comparisonCohortId": cohort, "count": count, "rowIndex": row}
            for (cohort, row), count in sorted(row_balance.items())
        ],
        "sampleIdentityCount": sample_count,
        "scheduleRawBytes": len(schedule_data),
        "scheduleRelativePath": OFFICIAL_RELATIVE["schedule"],
        "scheduleSha256": sha256_bytes(schedule_data),
        "schemaVersion": 1,
        "uniqueness": {
            "blockIdCount": len(block_ids),
            "outputPathCount": len(output_paths),
            "runIdCount": len(run_ids),
        },
    }


def find_s48_h48_projection(decision_table: dict[str, Any]) -> dict[str, Any]:
    candidates: Iterable[dict[str, Any]]
    if isinstance(decision_table, list):
        candidates = decision_table
    else:
        candidates = (
            decision_table.get("candidateDesigns")
            or decision_table.get("candidates")
            or decision_table.get("designs")
            or []
        )
    for candidate in candidates:
        candidate_id = str(candidate.get("candidateId") or candidate.get("designId") or candidate.get("id") or "")
        if candidate_id.upper().replace("/", "-") == "S48-H48":
            return candidate
        if candidate.get("sharedBlocksPerCampaign") == 48 and candidate.get("heterogeneousMatchedSuperblocksPerScenario") == 48:
            return candidate
    raise ValueError("S48/H48 projection not found in decision table")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-directory", default=str(RESEARCH_ROOT))
    arguments = parser.parse_args()
    output_directory = Path(arguments.output_directory).resolve()
    require("FormalRuns" not in output_directory.parts, "Output directory must not be a formal run root")

    required_paths = [
        AUTH_PATH,
        AMENDMENT_PATH,
        SPEC_PATH,
        TEST_DESIGN_PATH,
        SCHEMA_PATH,
        PREWRITE_PATH,
        SNAPSHOT_PATH,
        MATRIX_PATH,
        BUNDLE_PATH,
        PRESET_PATH,
        PR1_AMENDMENT_PATH,
        METRIC_REGISTRY_PATH,
        CONTRAST_REGISTRY_PATH,
        DECISION_TABLE_PATH,
        PR1B_PLAN_PATH,
        PR1B_READINESS_PATH,
        PR1B_RECOVERY_PATH,
    ]
    for required_path in required_paths:
        require(required_path.is_file(), f"Missing required input: {required_path}")

    auth = load_json(AUTH_PATH)
    amendment = load_json(AMENDMENT_PATH)
    snapshot = load_json(SNAPSHOT_PATH)
    matrix = load_json(MATRIX_PATH)
    bundle = load_json(BUNDLE_PATH)
    presets = load_json(PRESET_PATH)
    decision_table = load_json(DECISION_TABLE_PATH)
    pr1b_plan = load_json(PR1B_PLAN_PATH)
    projection = find_s48_h48_projection(decision_table)

    require(auth["selectedCandidate"]["candidateId"] == "S48-H48", "Authorization candidate mismatch")
    require(amendment["selectedDesign"]["candidateId"] == "S48-H48", "Amendment candidate mismatch")
    require(matrix["scenarioCount"] == 53, "Gate 11R scenario count mismatch")
    require(matrix["campaignCount"] == 74, "Gate 11R campaign count mismatch")
    require(matrix["eligibilityCount"] == 212, "Gate 11R eligibility count mismatch")
    require(presets["presetCount"] == 212, "Gate 11R preset count mismatch")
    require(sha256_file(BUNDLE_PATH) == "5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc", "Bundle hash mismatch")
    require(sha256_file(MATRIX_PATH) == "cc5f020003f3fad75bd82ebb2c26df521fd639ff0ee5376132853120dbc16aa3", "Matrix hash mismatch")

    preset_map = preset_lookup(presets)
    records, campaign_summaries = build_schedule(matrix, preset_map)
    schedule_data = b"".join(compact_json_bytes(record) for record in records)
    manifest = build_manifest(records, schedule_data)

    campaign_entries = [
        campaign_config_entry(campaign, ordinal, campaign_summaries[campaign["campaignId"]], preset_map)
        for ordinal, campaign in enumerate(matrix["campaigns"], start=1)
    ]
    memory_policy = pr1b_plan["memoryEligibility"]
    config = {
        "bindings": {
            "amendment": file_identity(AMENDMENT_PATH),
            "authorization": file_identity(AUTH_PATH),
            "contrastRegistry": file_identity(CONTRAST_REGISTRY_PATH),
            "decisionTable": file_identity(DECISION_TABLE_PATH),
            "gate11BundleManifest": file_identity(BUNDLE_PATH),
            "gate11Matrix": file_identity(MATRIX_PATH),
            "gate11PresetCatalog": file_identity(PRESET_PATH),
            "metricRegistry": file_identity(METRIC_REGISTRY_PATH),
            "pr1Amendment": file_identity(PR1_AMENDMENT_PATH),
            "pr1bReadiness": file_identity(PR1B_READINESS_PATH),
            "pr1bRecoveredOrderEffect": file_identity(PR1B_RECOVERY_PATH),
            "preWritePreservationAudit": file_identity(PREWRITE_PATH),
            "schema": file_identity(SCHEMA_PATH),
            "specification": file_identity(SPEC_PATH),
            "testDesign": file_identity(TEST_DESIGN_PATH),
        },
        "campaigns": campaign_entries,
        "cohortDesign": [
            {
                "blockProcessCount": 1536,
                "blocksPerCampaign": 48,
                "campaignCount": 32,
                "comparisonCohortId": SHARED_COHORT,
                "sampleCount": 6144,
                "samplesPerBlock": 4,
            },
            {
                "AB": 24,
                "BA": 24,
                "blockProcessCount": 1008,
                "blocksPerCampaign": 48,
                "campaignCount": 21,
                "comparisonCohortId": PER_AGENT_COHORT,
                "matchedSuperblocksPerScenario": 48,
                "sampleCount": 2016,
                "samplesPerBlock": 2,
            },
            {
                "AB": 24,
                "BA": 24,
                "blockProcessCount": 1008,
                "blocksPerCampaign": 48,
                "campaignCount": 21,
                "comparisonCohortId": GROUPED_COHORT,
                "matchedSuperblocksPerScenario": 48,
                "sampleCount": 2016,
                "samplesPerBlock": 2,
            },
        ],
        "configId": "gate13r-pr2-formal-campaign-rq-aligned-s48-h48-v1",
        "configKind": "gate13r-pr2-rq-aligned-s48-h48-formal-campaign-config-v1",
        "executionDesignId": EXECUTION_DESIGN_ID,
        "failurePolicy": {
            "automaticResumeAllowed": False,
            "automaticRetryAllowed": False,
            "failClosed": True,
            "partialAttemptMergeAllowed": False,
            "partialBlockEligible": False,
            "stopAfterFirstFailedBlock": True,
            "stopAfterFirstFailedSample": True,
            "topUpAllowed": False,
        },
        "formalCampaignConfigured": True,
        "formalDesignId": FORMAL_DESIGN_ID,
        "formalExecutionAuthorized": False,
        "formalRoot": {
            "createNewRequired": True,
            "mustBeAbsentBeforeAuthorizedLaunch": True,
            "relativePath": FORMAL_ROOT_RELATIVE,
            "resolvedAtPreparation": (PROJECT_ROOT / FORMAL_ROOT_RELATIVE).resolve().as_posix(),
        },
        "formalRootCreated": False,
        "formalTimingExecuted": False,
        "generatedAtUtc": auth["authorizedAtUtc"],
        "memoryEligibility": memory_policy,
        "playable": {
            "formalTimingIsolationRequired": True,
            "obsRecordingExcludedFromTiming": True,
            "playableMappingsRetainedFromGate11R": True,
        },
        "processSemantics": {
            "crossBlockReuseAllowed": False,
            "crossCampaignReuseAllowed": False,
            "laneCount": 1,
            "matchedSuperblockProcesses": 2,
            "maximumConcurrentUnityEditorProcesses": 1,
            "maximumWilliamsBlocksPerUnityProcess": 1,
            "oneFreshUnityEditorProcessPerCompleteWilliamsBlock": True,
            "oneOccurrencePerEligibleAlgorithmPerProcess": True,
            "parallelFallbackAllowed": False,
            "perSampleCompleteResetRequired": True,
            "strictSerial": True,
        },
        "resourceProjection": {
            "conservativeSummedP95Hours": 26.45538207066667,
            "minimumLaunchFreeBytes": 57397541440,
            "projectedP95RawBytes": 9631912320,
            "projectedSafetyBytes": 14447868480,
            "reserveBytes": 42949672960,
            "safetyMultiplier": 1.5,
            "serialP50Hours": 20.808185450666667,
        },
        "schedule": {
            "manifestRelativePath": OFFICIAL_RELATIVE["manifest"],
            "scheduleRawBytes": len(schedule_data),
            "scheduleRelativePath": OFFICIAL_RELATIVE["schedule"],
            "scheduleSha256": sha256_bytes(schedule_data),
        },
        "schemaVersion": 1,
        "scientificContract": amendment["scientificContract"],
        "totals": {
            "campaignCount": 74,
            "eligibleCellCount": 212,
            "heterogeneousMatchedSuperblockCount": 1008,
            "processCount": 3552,
            "sampleCount": 10176,
            "scenarioCount": 53,
        },
    }
    config_data = canonical_json_bytes(config)
    manifest["configRelativePath"] = OFFICIAL_RELATIVE["config"]
    manifest["configRawBytes"] = len(config_data)
    manifest["configSha256"] = sha256_bytes(config_data)
    manifest_data = canonical_json_bytes(manifest)

    projection_expected = {
        "conservativeSummedP95Hours": 26.45538207066667,
        "minimumLaunchFreeBytes": 57397541440,
        "projectedP95RawBytes": 9631912320,
        "projectedSafetyBytes": 14447868480,
        "reserveBytes": 42949672960,
        "safetyMultiplier": 1.5,
        "serialP50Hours": 20.808185450666667,
    }
    preflight = {
        "candidateDecisionTableRecord": projection,
        "formalLaunchAuthorized": False,
        "formalLaunchRecheckRequired": True,
        "preflightKind": "gate13r-pr2-preparation-storage-wallclock-preflight-v1",
        "preparationObservation": {
            "activePowerSchemeGuid": snapshot["environment"]["activePowerSchemeGuid"],
            "freeBytesAtPreparation": snapshot["environment"]["workspaceDriveFreeBytes"],
            "formalExecutionReceiptAbsent": snapshot["authorizationBoundAbsenceChecks"]["formalExecutionReceiptCount"] == 0,
            "formalRootAbsent": not snapshot["authorizationBoundAbsenceChecks"]["formalRootExists"],
            "freeSpaceGatePassedAtPreparation": snapshot["environment"]["workspaceDriveFreeBytes"] >= projection_expected["minimumLaunchFreeBytes"],
            "observedAtUtc": snapshot["observedAtUtc"],
            "unityEditorProcessCount": snapshot["environment"]["unityEditorProcessCount"],
        },
        "projection": projection_expected,
        "recheckBeforeFormalRootCreation": [
            "frozen-input-hashes",
            "environment-and-os",
            "power-and-thermal-state",
            "license-and-network-reachability",
            "unity-lock-hygiene",
            "raw-byte-storage-and-free-space",
            "formal-root-absence",
            "formal-execution-receipt-absence",
        ],
        "schemaVersion": 1,
        "status": "PREPARATION-PASS-NOT-LAUNCH-AUTHORIZATION",
    }
    preflight_data = canonical_json_bytes(preflight)

    output_paths = {
        "config": output_directory / CONFIG_NAME,
        "schedule": output_directory / SCHEDULE_NAME,
        "manifest": output_directory / MANIFEST_NAME,
        "preflight": output_directory / PREFLIGHT_NAME,
        "provenance": output_directory / PROVENANCE_NAME,
        "summary": output_directory / SUMMARY_NAME,
    }
    atomic_write(output_paths["schedule"], schedule_data)
    atomic_write(output_paths["config"], config_data)
    atomic_write(output_paths["manifest"], manifest_data)
    atomic_write(output_paths["preflight"], preflight_data)

    source_identities = [file_identity(path) for path in required_paths]
    source_identities.append(file_identity(SCRIPT_PATH))
    generated_core = [
        {
            "logicalName": logical_name,
            "officialRelativePath": OFFICIAL_RELATIVE[logical_name],
            "rawBytes": output_paths[logical_name].stat().st_size,
            "sha256": sha256_file(output_paths[logical_name]),
        }
        for logical_name in ("config", "schedule", "manifest", "preflight")
    ]
    provenance = {
        "deterministicSerialization": {
            "json": "UTF-8, sorted keys, two-space indent, LF, final LF",
            "jsonl": "UTF-8, sorted keys, compact separators, one LF-terminated record per process",
        },
        "formalCampaignAuthorized": False,
        "generatedAtUtc": auth["authorizedAtUtc"],
        "generatedCoreArtifacts": generated_core,
        "generatorId": "new-gate13r-pr2-formal-preparation-v1",
        "inputArtifacts": source_identities,
        "nonExecuting": True,
        "provenanceId": "gate13r-pr2-formal-preparation-provenance-v1",
        "schemaVersion": 1,
        "selectedCandidate": "S48-H48",
    }
    provenance_data = canonical_json_bytes(provenance)
    atomic_write(output_paths["provenance"], provenance_data)

    summary = {
        "artifactIdentities": [
            {
                "logicalName": logical_name,
                "officialRelativePath": OFFICIAL_RELATIVE[logical_name],
                "rawBytes": output_paths[logical_name].stat().st_size,
                "sha256": sha256_file(output_paths[logical_name]),
            }
            for logical_name in ("config", "schedule", "manifest", "preflight", "provenance")
        ],
        "formalCampaignAuthorized": False,
        "formalRootCreated": False,
        "generatedAtUtc": auth["authorizedAtUtc"],
        "generationId": "gate13r-pr2-s48-h48-generation-v1",
        "processRecordCount": len(records),
        "sampleIdentityCount": sum(len(record["entries"]) for record in records),
        "schemaVersion": 1,
        "status": "GENERATED-NON-EXECUTING",
    }
    atomic_write(output_paths["summary"], canonical_json_bytes(summary))

    print(
        json.dumps(
            {
                "outputDirectory": output_directory.as_posix(),
                "processRecordCount": len(records),
                "sampleIdentityCount": summary["sampleIdentityCount"],
                "status": summary["status"],
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
