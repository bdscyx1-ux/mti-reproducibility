#!/usr/bin/env python3
"""V4 validation-only hard gates for Gate 13R-PR2 non-executing preparation."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import jsonschema
import psutil


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parents[1]
RESEARCH_ROOT = PROJECT_ROOT / "Research"
GENERATOR_PATH = RESEARCH_ROOT / "New-Gate13RPR2FormalPreparationV2.py"
ORCHESTRATOR_PATH = RESEARCH_ROOT / "Verification/Run-Gate13RPR2NonExecutingValidationV4.ps1"
SCHEMA_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Schema.v2.json"
MATRIX_PATH = RESEARCH_ROOT / "FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json"
PRESET_PATH = RESEARCH_ROOT / "PlayableExperiments/Gate11R_5pct/v1/algorithm-preset-catalog.json"
PREWRITE_PATH = RESEARCH_ROOT / "Gate13R_PR2_PreWrite_Preservation_Audit.v2.json"
AUTH_PATH = RESEARCH_ROOT / "Gate13R_PR2_NonExecuting_Formal_Preparation_Authorization.v1.json"
AMENDMENT_PATH = RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Amendment.v1.json"

OFFICIAL_FILES = {
    "config": RESEARCH_ROOT / "Gate13R_PR2_Formal_Campaign_Config.v2.json",
    "schedule": RESEARCH_ROOT / "Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl",
    "manifest": RESEARCH_ROOT / "Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json",
    "preflight": RESEARCH_ROOT / "Gate13R_PR2_Storage_WallClock_Preflight.v2.json",
    "provenance": RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Provenance.v2.json",
    "summary": RESEARCH_ROOT / "Gate13R_PR2_Formal_Preparation_Generation_Summary.v2.json",
}

SHARED = "four-algorithm-shared-goal-v1"
PER_AGENT = "per-agent-heterogeneous-goal-v1"
GROUPED = "grouped-field-heterogeneous-goal-v1"
FORMAL_ROOT = PROJECT_ROOT / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v1"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite validation evidence: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
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


def file_evidence(path: Path) -> dict[str, Any]:
    return {
        "relativePath": path.relative_to(PROJECT_ROOT).as_posix(),
        "rawBytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", required=True)
    arguments = parser.parse_args()
    output_root = Path(arguments.output_root).resolve()
    if "FormalRuns" in output_root.parts:
        raise ValueError("Validation root cannot be a formal run root")
    if output_root.exists():
        raise FileExistsError(f"Validation output root already exists: {output_root}")
    output_root.mkdir(parents=True)

    checks: list[dict[str, Any]] = []

    def check(name: str, condition: bool, expected: Any = None, actual: Any = None, detail: str | None = None) -> None:
        item: dict[str, Any] = {"name": name, "passed": bool(condition)}
        if expected is not None:
            item["expected"] = expected
        if actual is not None:
            item["actual"] = actual
        if detail is not None:
            item["detail"] = detail
        checks.append(item)

    try:
        schema = load_json(SCHEMA_PATH)
        matrix = load_json(MATRIX_PATH)
        preset_catalog = load_json(PRESET_PATH)
        prewrite = load_json(PREWRITE_PATH)
        authorization = load_json(AUTH_PATH)
        amendment = load_json(AMENDMENT_PATH)
        config = load_json(OFFICIAL_FILES["config"])
        manifest = load_json(OFFICIAL_FILES["manifest"])
        preflight = load_json(OFFICIAL_FILES["preflight"])
        generation_summary = load_json(OFFICIAL_FILES["summary"])

        records: list[dict[str, Any]] = []
        with OFFICIAL_FILES["schedule"].open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.endswith("\n"):
                    check(f"schedule-line-{line_number}-lf-terminated", False)
                records.append(json.loads(line))

        schema_wrapper = lambda definition: {
            "$schema": schema["$schema"],
            "$ref": f"#/$defs/{definition}",
            "$defs": schema["$defs"],
        }
        for name, instance, definition in (
            ("config", config, "formalConfig"),
            ("manifest", manifest, "scheduleManifest"),
            ("preflight", preflight, "resourcePreflight"),
        ):
            try:
                jsonschema.validate(instance=instance, schema=schema_wrapper(definition))
                check(f"schema-{name}", True)
            except Exception as error:
                check(f"schema-{name}", False, detail=str(error))
        schedule_validator = jsonschema.Draft202012Validator(schema_wrapper("scheduleRecord"))
        schedule_schema_errors = []
        for index, record in enumerate(records, start=1):
            errors = list(schedule_validator.iter_errors(record))
            if errors:
                schedule_schema_errors.append({"ordinal": index, "errors": [error.message for error in errors[:3]]})
        check("schema-all-schedule-records", not schedule_schema_errors, expected=0, actual=len(schedule_schema_errors), detail=json.dumps(schedule_schema_errors[:3]))

        check("matrix-scenario-count", matrix["scenarioCount"] == 53, 53, matrix["scenarioCount"])
        check("matrix-campaign-count", matrix["campaignCount"] == 74, 74, matrix["campaignCount"])
        check("matrix-eligibility-count", matrix["eligibilityCount"] == 212, 212, matrix["eligibilityCount"])
        check("preset-count", preset_catalog["presetCount"] == 212, 212, preset_catalog["presetCount"])

        campaigns = matrix["campaigns"]
        campaign_map = {campaign["campaignId"]: campaign for campaign in campaigns}
        campaign_ordinal = {campaign["campaignId"]: index for index, campaign in enumerate(campaigns, start=1)}
        preset_map = {(preset["campaignId"], preset["algorithmId"]): preset for preset in preset_catalog["presets"]}
        check("campaign-id-unique", len(campaign_map) == 74, 74, len(campaign_map))
        check("preset-identity-unique", len(preset_map) == 212, 212, len(preset_map))
        check("cohort-shared-count", sum(c["comparisonCohortId"] == SHARED for c in campaigns) == 32, 32, sum(c["comparisonCohortId"] == SHARED for c in campaigns))
        check("cohort-per-agent-count", sum(c["comparisonCohortId"] == PER_AGENT for c in campaigns) == 21, 21, sum(c["comparisonCohortId"] == PER_AGENT for c in campaigns))
        check("cohort-grouped-count", sum(c["comparisonCohortId"] == GROUPED for c in campaigns) == 21, 21, sum(c["comparisonCohortId"] == GROUPED for c in campaigns))

        check("process-record-count", len(records) == 3552, 3552, len(records))
        ordinals = [record["globalProcessOrdinal"] for record in records]
        check("global-process-ordinals-gapless", ordinals == list(range(1, 3553)))

        campaign_records: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
        matched_records: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
        block_ids: set[str] = set()
        run_ids: set[str] = set()
        output_paths: set[str] = set()
        duplicate_blocks = duplicate_runs = duplicate_outputs = 0
        entry_count = 0
        content_mismatches: list[str] = []
        for record in records:
            campaign_id = record["campaignId"]
            campaign = campaign_map.get(campaign_id)
            if campaign is None:
                content_mismatches.append(f"unknown-campaign:{campaign_id}")
                continue
            campaign_records[campaign_id].append(record)
            row_map = {int(row["rowIndex"]): row["algorithms"] for row in campaign["williamsRows"]}
            expected_algorithms = row_map.get(record["williamsRowIndex"])
            actual_algorithms = [entry["algorithmId"] for entry in record["entries"]]
            comparisons = [
                (record["campaignOrdinal"] == campaign_ordinal[campaign_id], "campaign-ordinal"),
                (record["comparisonCohortId"] == campaign["comparisonCohortId"], "cohort"),
                (record["scenarioId"] == campaign["scenarioId"], "scenario-id"),
                (record["scenarioSha256"] == campaign["scenarioSha256"], "scenario-sha"),
                (record["scenarioFingerprintSha256"] == campaign["scenarioFingerprintSha256"], "scenario-fingerprint"),
                (record["sceneAssetPath"] == campaign["sceneAssetPath"], "scene"),
                (record["profileAssetPath"] == campaign["profileAssetPath"], "profile"),
                (record["profileAssetGuid"] == campaign["profileAssetGuid"], "profile-guid"),
                (record["profileSha256"] == campaign["profileSha256"], "profile-sha"),
                (actual_algorithms == expected_algorithms, "williams-row"),
                (record["expectedSampleCount"] == len(record["entries"]), "sample-count"),
                (record["freshProcessRequired"] is True, "fresh-process"),
                (record["maximumBlocksInProcess"] == 1, "one-block-per-process"),
            ]
            for condition, label in comparisons:
                if not condition:
                    content_mismatches.append(f"{record['blockId']}:{label}")
            if record["blockId"] in block_ids:
                duplicate_blocks += 1
            block_ids.add(record["blockId"])
            if record["outputRelativePath"] in output_paths:
                duplicate_outputs += 1
            output_paths.add(record["outputRelativePath"])
            predecessor = "NONE"
            for expected_position, entry in enumerate(record["entries"], start=1):
                entry_count += 1
                preset = preset_map.get((campaign_id, entry["algorithmId"]))
                if entry["position"] != expected_position:
                    content_mismatches.append(f"{entry['runId']}:position")
                if entry["predecessorAlgorithmId"] != predecessor:
                    content_mismatches.append(f"{entry['runId']}:predecessor")
                predecessor = entry["algorithmId"]
                if preset is None:
                    content_mismatches.append(f"{entry['runId']}:missing-preset")
                else:
                    for key in ("presetId", "presetAssetPath", "presetAssetGuid", "presetSha256"):
                        if entry[key] != preset[key]:
                            content_mismatches.append(f"{entry['runId']}:{key}")
                if entry["runId"] in run_ids:
                    duplicate_runs += 1
                run_ids.add(entry["runId"])
                if entry["sampleOutputRelativePath"] in output_paths:
                    duplicate_outputs += 1
                output_paths.add(entry["sampleOutputRelativePath"])
            matched = record["matchedSuperblock"]
            if campaign["comparisonCohortId"] == SHARED:
                if matched is not None:
                    content_mismatches.append(f"{record['blockId']}:unexpected-match")
            else:
                if matched is None:
                    content_mismatches.append(f"{record['blockId']}:missing-match")
                else:
                    matched_records[matched["matchedSuperblockId"]].append(record)

        check("sample-identity-count", entry_count == 10176, 10176, entry_count)
        check("record-content-bindings", not content_mismatches, expected=0, actual=len(content_mismatches), detail=json.dumps(content_mismatches[:10]))
        check("unique-block-ids", duplicate_blocks == 0 and len(block_ids) == 3552, 3552, len(block_ids))
        check("unique-run-ids", duplicate_runs == 0 and len(run_ids) == 10176, 10176, len(run_ids))
        check("unique-output-paths", duplicate_outputs == 0 and len(output_paths) == 13728, 13728, len(output_paths))

        block_count_failures = {campaign_id: len(items) for campaign_id, items in campaign_records.items() if len(items) != 48}
        check("all-campaigns-have-48-blocks", not block_count_failures and len(campaign_records) == 74, expected="74 campaigns x 48", actual=block_count_failures)

        balance_failures: list[dict[str, Any]] = []
        for campaign in campaigns:
            campaign_id = campaign["campaignId"]
            items = campaign_records[campaign_id]
            row_counts = Counter(item["williamsRowIndex"] for item in items)
            expected_row_count = 12 if campaign["comparisonCohortId"] == SHARED else 24
            if any(row_counts[int(row["rowIndex"])] != expected_row_count for row in campaign["williamsRows"]):
                balance_failures.append({"campaignId": campaign_id, "kind": "row", "counts": dict(row_counts)})
            position_counts = Counter((entry["algorithmId"], entry["position"]) for item in items for entry in item["entries"])
            expected_position_count = 12 if campaign["comparisonCohortId"] == SHARED else 24
            for algorithm in campaign["eligibleAlgorithmIds"]:
                for position in range(1, len(campaign["eligibleAlgorithmIds"]) + 1):
                    if position_counts[(algorithm, position)] != expected_position_count:
                        balance_failures.append({"campaignId": campaign_id, "kind": "position", "algorithm": algorithm, "position": position, "count": position_counts[(algorithm, position)]})
        check("per-campaign-williams-and-position-balance", not balance_failures, expected=0, actual=len(balance_failures), detail=json.dumps(balance_failures[:10]))

        check("matched-superblock-count", len(matched_records) == 1008, 1008, len(matched_records))
        matched_failures: list[str] = []
        scenario_pair_counts: Counter[str] = Counter()
        scenario_order_counts: Counter[tuple[str, str]] = Counter()
        scenario_order_row_counts: Counter[tuple[str, str, int]] = Counter()
        scenario_cohort_row_counts: Counter[tuple[str, str, int]] = Counter()
        for matched_id, pair in matched_records.items():
            pair = sorted(pair, key=lambda item: item["globalProcessOrdinal"])
            if len(pair) != 2:
                matched_failures.append(f"{matched_id}:process-count-{len(pair)}")
                continue
            first, second = pair
            first_meta = first["matchedSuperblock"]
            second_meta = second["matchedSuperblock"]
            if second["globalProcessOrdinal"] != first["globalProcessOrdinal"] + 1:
                matched_failures.append(f"{matched_id}:noncontiguous")
            expected_ordinals = [first["globalProcessOrdinal"], second["globalProcessOrdinal"]]
            if first_meta["pairGlobalProcessOrdinals"] != expected_ordinals or second_meta["pairGlobalProcessOrdinals"] != expected_ordinals:
                matched_failures.append(f"{matched_id}:pair-ordinals")
            if first_meta["cohortProcessPosition"] != 1 or second_meta["cohortProcessPosition"] != 2:
                matched_failures.append(f"{matched_id}:process-position")
            if first["scenarioId"] != second["scenarioId"] or first["scenarioSha256"] != second["scenarioSha256"] or first["scenarioFingerprintSha256"] != second["scenarioFingerprintSha256"]:
                matched_failures.append(f"{matched_id}:scenario-identity")
            if first["campaignBlockOrdinal"] != second["campaignBlockOrdinal"] or first["williamsRowIndex"] != second["williamsRowIndex"]:
                matched_failures.append(f"{matched_id}:repetition-or-row")
            if first_meta["deterministicInputIdentity"] != second_meta["deterministicInputIdentity"]:
                matched_failures.append(f"{matched_id}:deterministic-input")
            order = first_meta["cohortOrder"]
            actual_roles = [first_meta["cohortRole"], second_meta["cohortRole"]]
            expected_roles = ["A-PER-AGENT", "B-GROUPED-FIELD"] if order == "AB" else ["B-GROUPED-FIELD", "A-PER-AGENT"]
            if actual_roles != expected_roles:
                matched_failures.append(f"{matched_id}:cohort-order")
            scenario_id = first["scenarioId"]
            row_index = first["williamsRowIndex"]
            scenario_pair_counts[scenario_id] += 1
            scenario_order_counts[(scenario_id, order)] += 1
            scenario_order_row_counts[(scenario_id, order, row_index)] += 1
            scenario_cohort_row_counts[(scenario_id, first["comparisonCohortId"], first["williamsRowIndex"])] += 1
            scenario_cohort_row_counts[(scenario_id, second["comparisonCohortId"], second["williamsRowIndex"])] += 1
        check("matched-superblock-identity-and-contiguity", not matched_failures, expected=0, actual=len(matched_failures), detail=json.dumps(matched_failures[:10]))
        hetero_scenarios = sorted(scenario_pair_counts)
        check("heterogeneous-scenario-count", len(hetero_scenarios) == 21, 21, len(hetero_scenarios))
        order_balance_failures = []
        for scenario_id in hetero_scenarios:
            if scenario_pair_counts[scenario_id] != 48:
                order_balance_failures.append(f"{scenario_id}:pairs={scenario_pair_counts[scenario_id]}")
            for order in ("AB", "BA"):
                if scenario_order_counts[(scenario_id, order)] != 24:
                    order_balance_failures.append(f"{scenario_id}:{order}={scenario_order_counts[(scenario_id, order)]}")
                for row_index in (0, 1):
                    if scenario_order_row_counts[(scenario_id, order, row_index)] != 12:
                        order_balance_failures.append(f"{scenario_id}:{order}:row{row_index}={scenario_order_row_counts[(scenario_id, order, row_index)]}")
            for cohort in (PER_AGENT, GROUPED):
                for row_index in (0, 1):
                    if scenario_cohort_row_counts[(scenario_id, cohort, row_index)] != 24:
                        order_balance_failures.append(f"{scenario_id}:{cohort}:row{row_index}={scenario_cohort_row_counts[(scenario_id, cohort, row_index)]}")
        check("heterogeneous-order-row-orthogonality", not order_balance_failures, expected=0, actual=len(order_balance_failures), detail=json.dumps(order_balance_failures[:10]))

        expected_totals = {
            "campaignCount": 74,
            "eligibleCellCount": 212,
            "heterogeneousMatchedSuperblockCount": 1008,
            "processCount": 3552,
            "sampleCount": 10176,
            "scenarioCount": 53,
        }
        check("config-totals", config["totals"] == expected_totals, expected_totals, config["totals"])
        check("config-campaign-count", len(config["campaigns"]) == 74, 74, len(config["campaigns"]))
        check("config-formal-flags", config["formalExecutionAuthorized"] is False and config["formalRootCreated"] is False and config["formalTimingExecuted"] is False)
        check("config-future-formal-root", config["formalRoot"]["relativePath"] == "Research/FormalRuns/Gate13R_RQAligned_S48H48/v1")
        process_semantics = config["processSemantics"]
        check("strict-serial-one-fresh-process", process_semantics["strictSerial"] is True and process_semantics["maximumConcurrentUnityEditorProcesses"] == 1 and process_semantics["maximumWilliamsBlocksPerUnityProcess"] == 1 and process_semantics["oneFreshUnityEditorProcessPerCompleteWilliamsBlock"] is True)
        check("no-cross-block-or-campaign-reuse", process_semantics["crossBlockReuseAllowed"] is False and process_semantics["crossCampaignReuseAllowed"] is False)
        check("per-sample-reset", process_semantics["perSampleCompleteResetRequired"] is True)
        failure_policy = config["failurePolicy"]
        check("formal-fail-closed-no-retry-resume-topup-merge", failure_policy["failClosed"] is True and failure_policy["automaticRetryAllowed"] is False and failure_policy["automaticResumeAllowed"] is False and failure_policy["topUpAllowed"] is False and failure_policy["partialAttemptMergeAllowed"] is False)

        scientific = config["scientificContract"]
        check("p1-sole-confirmatory-primary", scientific["primaryEndpoint"] == "P1-dynamicHandlingMillisecondsPerScheduledEvent")
        check("shared-c1-c5-holm-family", scientific["sharedConfirmatoryContrasts"] == ["C1", "C2", "C3", "C4", "C5"] and scientific["confirmatoryFamilyWiseAlpha"] == 0.05 and scientific["multiplicityMethod"] == "Holm")
        check("heterogeneous-secondary-system-treatment", scientific["heterogeneousCrossFamilyIdentity"] == "SECONDARY-SYSTEM-TREATMENT-CONTRAST")
        check("p2-p5-supportive", scientific["supportivePlanningEndpoints"] == ["P2", "P3", "P4", "P5"])
        check("m1-m5-prospective-gate14r", scientific["prospectiveGate14REndpoints"] == ["M1", "M2", "M3", "M4", "M5"])
        check("15pct-anchor-not-margin", scientific["planningEffectAnchorRelative"] == 0.15 and scientific["planningEffectAnchorIsPracticalMargin"] is False and scientific["practicalSuperiorityMargin"] is None)
        check("no-adaptive-stopping-or-per-campaign-guarantee", scientific["adaptiveStoppingAllowed"] is False and scientific["perCampaignPrecisionGuarantee"] is None)

        memory = config["memoryEligibility"]
        expected_memory = {
            "policyId": "gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1",
            "sampleAlertThresholdBytes": 134217728,
            "sampleEmergencyStopBytes": 268435456,
            "twoSampleBlockManagedGrowthHardLimitBytes": 268435456,
            "blockWorkingSetGrowthHardLimitBytes": 536870912,
            "blockPrivateMemoryGrowthHardLimitBytes": 536870912,
            "exactThresholdPasses": True,
            "alertSamplesRetained": True,
            "durableEvaluationBeforeDecisionRequired": True,
        }
        check("memory-policy-carried-forward-exactly", memory == expected_memory, expected_memory, memory)

        schedule_bytes = OFFICIAL_FILES["schedule"].read_bytes()
        config_bytes = OFFICIAL_FILES["config"].read_bytes()
        check("manifest-schedule-sha", manifest["scheduleSha256"] == hashlib.sha256(schedule_bytes).hexdigest())
        check("manifest-schedule-bytes", manifest["scheduleRawBytes"] == len(schedule_bytes), len(schedule_bytes), manifest["scheduleRawBytes"])
        check("manifest-config-sha", manifest["configSha256"] == hashlib.sha256(config_bytes).hexdigest())
        check("manifest-config-bytes", manifest["configRawBytes"] == len(config_bytes), len(config_bytes), manifest["configRawBytes"])
        check("manifest-counts", manifest["processRecordCount"] == 3552 and manifest["sampleIdentityCount"] == 10176 and manifest["heterogeneousMatchedSuperblockCount"] == 1008)
        check("manifest-formal-not-authorized", manifest["formalExecutionAuthorized"] is False and manifest["formalCampaignExecuted"] is False)

        expected_projection = {
            "conservativeSummedP95Hours": 26.45538207066667,
            "minimumLaunchFreeBytes": 57397541440,
            "projectedP95RawBytes": 9631912320,
            "projectedSafetyBytes": 14447868480,
            "reserveBytes": 42949672960,
            "safetyMultiplier": 1.5,
            "serialP50Hours": 20.808185450666667,
        }
        check("resource-projection-exact", preflight["projection"] == expected_projection, expected_projection, preflight["projection"])
        check("preflight-is-not-launch-authorization", preflight["formalLaunchAuthorized"] is False and preflight["formalLaunchRecheckRequired"] is True and preflight["status"] == "PREPARATION-PASS-NOT-LAUNCH-AUTHORIZATION")
        current_free = shutil.disk_usage(PROJECT_ROOT).free
        check("current-free-space-exceeds-minimum", current_free >= expected_projection["minimumLaunchFreeBytes"], expected_projection["minimumLaunchFreeBytes"], current_free)

        binding_failures = []
        for binding_name, binding in config["bindings"].items():
            path = PROJECT_ROOT / binding["relativePath"]
            if not path.is_file() or sha256_file(path) != binding["sha256"] or path.stat().st_size != binding["rawBytes"]:
                binding_failures.append(binding_name)
        check("all-config-input-bindings-current", not binding_failures, expected=0, actual=len(binding_failures), detail=json.dumps(binding_failures))

        prewrite_key_failures = []
        for item in prewrite["keyFiles"]:
            path = PROJECT_ROOT / item["relativePath"]
            if not path.is_file() or sha256_file(path) != item["sha256"]:
                prewrite_key_failures.append(item["relativePath"])
        check("prewrite-key-file-hashes-current", not prewrite_key_failures, expected=0, actual=len(prewrite_key_failures), detail=json.dumps(prewrite_key_failures))

        unity_processes = [
            {"pid": process.info["pid"], "name": process.info.get("name")}
            for process in psutil.process_iter(["pid", "name"])
            if (process.info.get("name") or "").lower() == "unity.exe"
        ]
        check("unity-process-count-zero", not unity_processes, expected=0, actual=len(unity_processes), detail=json.dumps(unity_processes))
        check("future-formal-root-absent", not FORMAL_ROOT.exists(), False, FORMAL_ROOT.exists())
        receipt_matches = list(RESEARCH_ROOT.glob("Gate13R_PR2*Formal*Execution*Receipt*"))
        check("formal-execution-receipt-absent", not receipt_matches, expected=0, actual=len(receipt_matches), detail=json.dumps([path.name for path in receipt_matches]))

        token_parts = [
            "sub" + "process",
            "os" + ".system",
            "P" + "open(",
            "Start" + "-Process",
            "Create" + "Process",
            "-batch" + "mode",
        ]
        source_scan_failures = []
        for source_path in (GENERATOR_PATH, SCRIPT_PATH, ORCHESTRATOR_PATH):
            source = source_path.read_text(encoding="utf-8")
            for token in token_parts:
                if token.lower() in source.lower():
                    source_scan_failures.append(f"{source_path.name}:{token}")
        check("static-no-process-launch-constructs", not source_scan_failures, expected=0, actual=len(source_scan_failures), detail=json.dumps(source_scan_failures))

        regeneration_root = output_root / "deterministic-regeneration"
        spec = importlib.util.spec_from_file_location("gate13r_pr2_generator_v2", GENERATOR_PATH)
        if spec is None or spec.loader is None:
            raise RuntimeError("Cannot import deterministic generator")
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        saved_argv = sys.argv[:]
        captured_stdout = io.StringIO()
        try:
            sys.argv = [str(GENERATOR_PATH), "--output-directory", str(regeneration_root)]
            with contextlib.redirect_stdout(captured_stdout):
                generator_result = generator.main()
        finally:
            sys.argv = saved_argv
        check("deterministic-regeneration-exit", generator_result == 0, 0, generator_result)
        regeneration_failures = []
        for logical_name, official_path in OFFICIAL_FILES.items():
            regenerated_path = regeneration_root / official_path.name
            if not regenerated_path.is_file() or regenerated_path.read_bytes() != official_path.read_bytes():
                regeneration_failures.append(logical_name)
        check("deterministic-regeneration-byte-identical", not regeneration_failures, expected=0, actual=len(regeneration_failures), detail=json.dumps(regeneration_failures))

        check("generation-summary-counts", generation_summary["processRecordCount"] == 3552 and generation_summary["sampleIdentityCount"] == 10176)
        check("generation-summary-boundary", generation_summary["formalCampaignAuthorized"] is False and generation_summary["formalRootCreated"] is False and generation_summary["status"] == "GENERATED-NON-EXECUTING")
        check("authorization-boundary", authorization["permissions"]["runGate13RFormalCampaign"] is False and authorization["permissions"]["runGate14R"] is False and authorization["permissions"]["launchUnityEditor"] is False)
        check("amendment-boundary", amendment["authorizationBoundary"]["formalCampaignAuthorized"] is False and amendment["authorizationBoundary"]["gate14RAuthorized"] is False)

    except Exception as error:
        check("unhandled-validation-exception", False, detail=f"{type(error).__name__}: {error}")

    failed = [item for item in checks if not item["passed"]]
    summary = {
        "authorizationBoundary": {
            "formalCampaignAuthorized": False,
            "formalExecutionReceiptCreated": False,
            "formalRootCreated": False,
            "gate14RAuthorized": False,
            "unityEditorLaunched": False,
        },
        "checkCount": len(checks),
        "checks": checks,
        "failedCheckCount": len(failed),
        "failedCheckNames": [item["name"] for item in failed],
        "passedCheckCount": len(checks) - len(failed),
        "schemaVersion": 1,
        "status": "PASS" if not failed else "FAIL",
        "validatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "validationId": "gate13r-pr2-nonexecuting-core-validation-v4",
    }
    summary_path = output_root / "core-validation-summary.json"
    atomic_json(summary_path, summary)

    evidence_paths = [summary_path, SCRIPT_PATH, GENERATOR_PATH, SCHEMA_PATH, *OFFICIAL_FILES.values()]
    regeneration_root = output_root / "deterministic-regeneration"
    if regeneration_root.exists():
        evidence_paths.extend(sorted(path for path in regeneration_root.iterdir() if path.is_file()))
    evidence_manifest = {
        "artifactCount": len(evidence_paths),
        "artifacts": [file_evidence(path) for path in evidence_paths],
        "formalCampaignAuthorized": False,
        "manifestId": "gate13r-pr2-core-validation-evidence-manifest-v4",
        "schemaVersion": 1,
        "status": summary["status"],
    }
    atomic_json(output_root / "core-validation-evidence-manifest.json", evidence_manifest)
    print(json.dumps({"checkCount": len(checks), "failedCheckCount": len(failed), "status": summary["status"]}, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
