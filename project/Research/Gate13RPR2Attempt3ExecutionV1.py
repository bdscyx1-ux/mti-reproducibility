#!/usr/bin/env python3
"""Gate 13R-PR2 formal attempt-3 Phase-A execution and raw-data commit.

This versioned orchestrator binds the frozen MP2 V4 candidate and v2 schedule
to the already-validated MP2 V3 block wrapper.  It never performs Phase-B
statistical analysis, never launches Gate 14R, and has no measured retry,
resume, top-up, merge, skip, replacement, or adaptive-stopping path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import traceback
import uuid
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable, Iterable

import jsonschema
import psutil


SCRIPT_ID = "gate13r-pr2-formal-attempt3-phase-a-orchestrator-v1"
FORMAL_ROOT_REL = "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3"
RECEIPT_REL = "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
STATUS_REL = "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"
SCHEDULE_REL = "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
OVERLAY_REL = "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"
STATUS_SCHEMA_REL = "Research/Gate13R_PR2_Attempt3_Operational_Status_Schema.v1.json"
PYTHON_REL = "Research/Gate13RPR2Attempt3ExecutionV1.py"
LAUNCHER_REL = "Research/Run-Gate13RPR2FormalAttempt3V2.ps1"
PROVENANCE_REL = "Research/Gate13R_PR2_Attempt3_Formal_Execution_Adapter_Provenance.v2.json"
BLOCK_WRAPPER_REL = "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1"
PLAN_BUILDER_REL = "Research/New-Gate13RPR2MP2BlockPlanV4.py"
UNITY_COMMAND_REL = "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs"
TOTAL_PROCESSES = 3552
TOTAL_SAMPLES = 10176
TOTAL_CAMPAIGNS = 74
TOTAL_SCENARIOS = 53
TOTAL_MATCHED_SUPERBLOCKS = 1008
MINIMUM_FREE_BYTES = 57_397_541_440
EXPECTED_NATIVE_PSMODULEPATH = ";".join(
    (
        r"C:\Users\bdscy\Documents\WindowsPowerShell\Modules",
        r"C:\Program Files\WindowsPowerShell\Modules",
        r"C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules",
    )
)
RAW_COMPLETE = "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE"
TERMINAL_FAILURE = "FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE"


FROZEN_HASHES: dict[str, str] = {
    "Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md": "35652dfb462191c10abca3c426fb3e9aeefe8f37beaee28358704568ca133bc5",
    "Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json": "88333a15f3e5deb0eb7998bf15a5f1976df5de9a0382350016aa8623ad4680f8",
    "Research/Gate13R_PR2_MP2_Final_Validation_Audit.v1.json": "bbf41f14682a85e061799a5cb9daed2122d6f8631a878b22bb714ede161bbe9e",
    "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json": "526a7fc6ff67e3c2ac0201f1f88dcc08b9af155e0a25d0332fd4aab189aa809c",
    "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Terminal_Audit.v3.json": "6290bcab9b051af1215bd3658cf88be91fbeec65729f8eed4ff3a5bfe9f59c9b",
    "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Evidence_Manifest.v5.json": "79f5cfd08b4f00559271e8889b88c9bd4991840ff9141815bb03e83c7a4d03bd",
    "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json": "c8d3e9965ae72798e2366c0187a96e578df306bb68196f54039c421672b78042",
    "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json": "2cad63b1c89608b2053552ef8c1261603f81231365689ba232d950fc279c4f62",
    "Research/Gate13R_PR2_MP2_Provenance.v4.json": "0f2c666ac4dc324687073fcdd913833e4d7d72dc8ad88bfaa5b1184bcfb7c37f",
    "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json": "87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e",
    SCHEDULE_REL: "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
    "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json": "b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724",
    "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json": "1070821ef6264510eb2e7427d7887aaca08bb5d2e7854d48f61a6c8e1285490f",
    "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json": "5dd5daf640831ea49d5fa9e0bb1a318e71669ee9e426bf346f7eebc36f0c5055",
    OVERLAY_REL: "c87cc7eab158dc7a111867364b9c06c2314f44c644ef2a4b8e33348bd1876d13",
    "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json": "772d876aa4396e4229397e611011b5562024b90ebc5b5bf36ee85680184672c0",
    "Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json": "4825f4a7863be74ff3691a129c77b92b58da75bac4041c2f265737c207bdbe69",
    "Research/Gate13R_PR2_MP2_Specification.v1.md": "283055b35cd60c8014ea181e029ec169c6f19eccb4bab9220d46f799b18fce71",
    "Research/Gate13R_PR2_MP2_Test_Design.v1.md": "45cfd1d5a12fa551d62b9cde4506dac71e2fd1a0c227a6d899d67d12f71db5d3",
    "Research/Gate13RPR2MP2MemoryPolicyV2.psm1": "7f9e7252fc4a158573ca67f54baa7fa4a0d0c981f3240aa706d46a96d283ffc4",
    "Research/Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json": "f1b556b3052c865640651bec58751a61dd3823422027fcbef0bf4fdd3a25dd8a",
    BLOCK_WRAPPER_REL: "fc0c42b858afb8e8d80c6f10544a0d7fb75694ae8c57910d205cea721731ff13",
    PLAN_BUILDER_REL: "11365fb3c694ae2fab6c9d3c3cb3c93f3cbe3e6f2f7a30373730f5a236ce8785",
    UNITY_COMMAND_REL: "21f86b21a49c936edd5e65fde750d269a54be984186d9c802cbc2804b2691c75",
    "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json": "805200a362440918682317f3ecf4fdb35fa441a1459457700a0f5f2a43a113df",
    "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md": "1641c22ddcb788f46ee1b2956f3bf8c8e13312459b5c22b139396001823085a5",
    "Research/Gate13R_PR2_Attempt3_Monitoring_Config.v2.json": "b88da3901a2c2cc494140a8cd2e3f37b546f637935bc940a8941a850d42770c6",
    STATUS_SCHEMA_REL: "3aff68ac8e041838283f8e28b72b388ab4de50abe3b357f59bb3e3597f74d89b",
    "Research/Gate13R_PR2_Attempt3_Progress_Snapshot_Schema.v1.json": "5131b2f172f57377e184f164587e59cff73cb40228bdfb3ba60716704e3295df",
    "Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v1.json": "2aa5d0e5a11a1e38a05d9e3e82a65dc227e98b953cc4e2678e73eaa96aec1a3d",
    "Research/Gate13RPR2Attempt3MonitoringRecoveryV2.py": "6d1cd6b1f0542c2985fb0c11d3da6caee6c0413f0c5fe13f335897fef8f4c162",
    "Research/Get-Gate13RPR2Attempt3OperationalProgressV2.ps1": "8b9c3733aae86b4adbe03c9bc7806931947746d864854d438bf2a67d09f537c5",
    "Research/Gate13R_PR2_Attempt3_Execution_User_Authorization.v1.txt": "f276061a6cacc79bb91b7aacc50b58ec48f13d3afeb6dd75a1789901425f5dd9",
    "Research/Gate13R_PR2_Attempt3_Execution_PreWrite_Preservation_Audit.v1.json": "95ffb69e7a21ccc490d288741ca328c24a5aef7d167e1c69b9f0a16761e594b4",
    "Research/Gate13R_PR2_Attempt3_Execution_Authorization.v1.json": "b32e6f3887f86c88909b2f2b77d8d36a9c9e4c6bf985b4c075ab53b5a67033de",
    "Research/Gate13R_PR2_Attempt3_Formal_Execution_Prelaunch_Test_Design.v1.md": "ffddc60c1f083c617994ed16b700e72917fc57310a9a63477a82dd6662b967c0",
}

AUTOMATION_PATH = Path(
    r"C:\Users\bdscy\.codex\automations\gate13r-attempt3-hourly-progress\automation.toml"
)
AUTOMATION_SHA256 = "c66d41527f075137b2829a291fb303e1d81af940925e739fa3c898cb8f52b0e4"


class ContractError(RuntimeError):
    """A fail-closed execution or raw-contract violation."""


def utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path, chunk_size: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _flush_parent(parent: Path) -> None:
    if os.name != "nt":
        descriptor = os.open(parent, os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def atomic_json(path: Path, value: Any, *, replace: bool) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".g13tmp-{uuid.uuid4().hex}"
    try:
        with temporary.open("xb") as handle:
            handle.write(json_bytes(value))
            handle.flush()
            os.fsync(handle.fileno())
        if not replace and path.exists():
            raise ContractError(f"CREATE-NEW-TARGET-EXISTS:{path}")
        os.replace(temporary, path)
        _flush_parent(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_text(path: Path, text: str, *, replace: bool) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".g13tmp-{uuid.uuid4().hex}"
    try:
        with temporary.open("xb") as handle:
            handle.write(text.encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
        if not replace and path.exists():
            raise ContractError(f"CREATE-NEW-TARGET-EXISTS:{path}")
        os.replace(temporary, path)
        _flush_parent(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def canonical_windows(path: Path) -> str:
    return str(path.resolve())


def project_path(project: Path, relative: str) -> Path:
    candidate = (project / Path(relative)).resolve()
    try:
        candidate.relative_to(project.resolve())
    except ValueError as error:
        raise ContractError(f"PROJECT-PATH-ESCAPE:{relative}") from error
    return candidate


def binding(project: Path, relative: str) -> dict[str, Any]:
    path = project_path(project, relative)
    return {
        "relativePath": relative,
        "sha256": sha256_file(path),
        "rawBytes": path.stat().st_size,
    }


def assert_hashes(project: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for relative, expected in FROZEN_HASHES.items():
        path = project_path(project, relative)
        actual = sha256_file(path) if path.is_file() else None
        passed = actual == expected
        results.append(
            {
                "relativePath": relative,
                "expectedSha256": expected,
                "actualSha256": actual,
                "passed": passed,
            }
        )
        if not passed:
            raise ContractError(f"FROZEN-HASH-MISMATCH:{relative}:{actual}:{expected}")
    if not AUTOMATION_PATH.is_file() or sha256_file(AUTOMATION_PATH) != AUTOMATION_SHA256:
        raise ContractError("HEARTBEAT-AUTOMATION-HASH-MISMATCH")
    automation_text = AUTOMATION_PATH.read_text(encoding="utf-8")
    for token in (
        'id = "gate13r-attempt3-hourly-progress"',
        'status = "ACTIVE"',
        'rrule = "FREQ=MINUTELY;INTERVAL=5"',
        "Get-Gate13RPR2Attempt3OperationalProgressV2.ps1",
    ):
        if token not in automation_text:
            raise ContractError(f"HEARTBEAT-AUTOMATION-CONTRACT-MISSING:{token}")
    results.append(
        {
            "absolutePath": str(AUTOMATION_PATH),
            "expectedSha256": AUTOMATION_SHA256,
            "actualSha256": sha256_file(AUTOMATION_PATH),
            "passed": True,
        }
    )
    return results


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                raise ContractError(f"BLANK-JSONL-LINE:{path}:{line_number}")
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ContractError(f"JSONL-RECORD-NOT-OBJECT:{path}:{line_number}")
            records.append(value)
    return records


def validate_schedule(
    project: Path,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    schedule = load_jsonl(project_path(project, SCHEDULE_REL))
    overlay = load_jsonl(project_path(project, OVERLAY_REL))
    if len(schedule) != TOTAL_PROCESSES or len(overlay) != TOTAL_PROCESSES:
        raise ContractError(f"PROCESS-CARDINALITY:{len(schedule)}:{len(overlay)}")
    block_ids: set[str] = set()
    outputs: set[str] = set()
    run_ids: set[str] = set()
    campaigns: set[str] = set()
    scenarios: set[str] = set()
    matched: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    cell_counts: Counter[tuple[str, str, str, int]] = Counter()
    abba: Counter[tuple[str, str]] = Counter()
    sample_count = 0
    shared_processes = 0
    heterogeneous_processes = 0
    for index, (record, policy) in enumerate(zip(schedule, overlay, strict=True), 1):
        if int(record.get("globalProcessOrdinal", -1)) != index:
            raise ContractError(f"NONCONTIGUOUS-GLOBAL-ORDINAL:{index}")
        for key in ("globalProcessOrdinal", "blockId", "campaignId", "scenarioId", "scenarioRelativePath"):
            if str(record.get(key)) != str(policy.get(key)):
                raise ContractError(f"SCHEDULE-OVERLAY-MISMATCH:{index}:{key}")
        expected_runs = [str(entry["runId"]) for entry in record["entries"]]
        if expected_runs != [str(value) for value in policy["expectedRunIds"]]:
            raise ContractError(f"SCHEDULE-OVERLAY-RUN-MISMATCH:{index}")
        block_id = str(record["blockId"])
        output = str(record["outputRelativePath"])
        if block_id in block_ids or output in outputs:
            raise ContractError(f"DUPLICATE-BLOCK-OR-OUTPUT:{index}:{block_id}")
        block_ids.add(block_id)
        outputs.add(output)
        entries = list(record["entries"])
        if int(record["expectedSampleCount"]) != len(entries):
            raise ContractError(f"SAMPLE-COUNT-IN-RECORD:{index}")
        if record.get("freshProcessRequired") is not True or int(record.get("maximumBlocksInProcess", -1)) != 1:
            raise ContractError(f"PROCESS-REUSE-CONTRACT:{index}")
        positions = [int(entry["position"]) for entry in entries]
        if positions != list(range(1, len(entries) + 1)):
            raise ContractError(f"POSITION-CONTRACT:{index}")
        algorithms = [str(entry["algorithmId"]) for entry in entries]
        if len(set(algorithms)) != len(algorithms):
            raise ContractError(f"ALGORITHM-DUPLICATE-IN-BLOCK:{index}")
        for run_id in expected_runs:
            if run_id in run_ids:
                raise ContractError(f"DUPLICATE-RUN-ID:{run_id}")
            run_ids.add(run_id)
        sample_count += len(entries)
        campaigns.add(str(record["campaignId"]))
        scenarios.add(str(record["scenarioId"]))
        match = record.get("matchedSuperblock")
        if match is None:
            shared_processes += 1
            if len(entries) != 4 or set(algorithms) != {"A*-R", "D*L", "C-FF", "IDFF"}:
                raise ContractError(f"SHARED-BLOCK-CONTRACT:{index}")
        else:
            heterogeneous_processes += 1
            if len(entries) != 2:
                raise ContractError(f"HETEROGENEOUS-BLOCK-CONTRACT:{index}")
            matched_id = str(match["matchedSuperblockId"])
            matched[matched_id].append(record)
            order = str(match["cohortOrder"])
            if order not in {"AB", "BA"}:
                raise ContractError(f"ABBA-ORDER:{index}")
            scenario_id = str(record["scenarioId"])
            cohort = str(record["comparisonCohortId"])
            row = int(record["williamsRowIndex"])
            cell_counts[(scenario_id, cohort, order, row)] += 1
            abba[(scenario_id, order)] += 1
    if sample_count != TOTAL_SAMPLES or len(run_ids) != TOTAL_SAMPLES:
        raise ContractError(f"TOTAL-SAMPLES:{sample_count}:{len(run_ids)}")
    if len(campaigns) != TOTAL_CAMPAIGNS or len(scenarios) != TOTAL_SCENARIOS:
        raise ContractError(f"CAMPAIGN-SCENARIO-CARDINALITY:{len(campaigns)}:{len(scenarios)}")
    if shared_processes != 1536 or heterogeneous_processes != 2016:
        raise ContractError(f"COHORT-PROCESS-CARDINALITY:{shared_processes}:{heterogeneous_processes}")
    if len(matched) != TOTAL_MATCHED_SUPERBLOCKS:
        raise ContractError(f"MATCHED-SUPERBLOCK-CARDINALITY:{len(matched)}")
    for matched_id, records in matched.items():
        if len(records) != 2:
            raise ContractError(f"MATCHED-SUPERBLOCK-PAIR-CARDINALITY:{matched_id}:{len(records)}")
        first, second = records
        if first["scenarioId"] != second["scenarioId"]:
            raise ContractError(f"MATCHED-SUPERBLOCK-SCENARIO:{matched_id}")
        roles = {str(item["matchedSuperblock"]["cohortRole"]) for item in records}
        if roles != {"A-PER-AGENT", "B-GROUPED-FIELD"}:
            raise ContractError(f"MATCHED-SUPERBLOCK-ROLES:{matched_id}:{roles}")
        expected_pair = [int(value) for value in first["matchedSuperblock"]["pairGlobalProcessOrdinals"]]
        actual_pair = [int(first["globalProcessOrdinal"]), int(second["globalProcessOrdinal"])]
        if expected_pair != actual_pair:
            raise ContractError(f"MATCHED-SUPERBLOCK-ORDINALS:{matched_id}")
    heterogeneous_scenarios = {key[0] for key in abba}
    if len(heterogeneous_scenarios) != 21:
        raise ContractError(f"HETEROGENEOUS-SCENARIOS:{len(heterogeneous_scenarios)}")
    for scenario_id in heterogeneous_scenarios:
        if abba[(scenario_id, "AB")] != 48 or abba[(scenario_id, "BA")] != 48:
            # Each superblock order is represented by both cohort processes.
            raise ContractError(f"ABBA-PROCESS-QUOTA:{scenario_id}:{abba[(scenario_id, 'AB')]}:{abba[(scenario_id, 'BA')]}")
    if not cell_counts or set(cell_counts.values()) != {12}:
        raise ContractError(f"ORDER-WILLIAMS-CELL-COUNT:{sorted(set(cell_counts.values()))}")
    summary = {
        "scenarioCount": len(scenarios),
        "campaignCount": len(campaigns),
        "processCount": len(schedule),
        "sampleCount": sample_count,
        "runIdCount": len(run_ids),
        "sharedProcessCount": shared_processes,
        "heterogeneousProcessCount": heterogeneous_processes,
        "matchedSuperblockCount": len(matched),
        "heterogeneousScenarioCount": len(heterogeneous_scenarios),
        "abbaSuperblocksPerScenario": "24/24",
        "abbaProcessRecordsPerScenario": "48/48",
        "orderByWilliamsRowCountPerCell": 12,
        "uniqueBlockAndOutputIdentity": True,
    }
    return schedule, overlay, summary


def _scenario_dimensions(project: Path, record: dict[str, Any]) -> tuple[int, int]:
    scenario_path = project_path(project, str(record["scenarioRelativePath"]))
    if sha256_file(scenario_path) != str(record["scenarioSha256"]):
        raise ContractError(f"SCENARIO-HASH:{record['scenarioId']}")
    scenario = read_json(scenario_path)
    return int(scenario["gridWidth"]), int(scenario["gridHeight"])


def make_plan(
    project: Path,
    record: dict[str, Any],
    policy: dict[str, Any],
    *,
    formal: bool,
    receipt_sha256: str = "",
) -> dict[str, Any]:
    for key in ("globalProcessOrdinal", "blockId", "campaignId", "scenarioId", "scenarioRelativePath"):
        if str(record[key]) != str(policy[key]):
            raise ContractError(f"PLAN-SCHEDULE-OVERLAY:{record['globalProcessOrdinal']}:{key}")
    grid_width, grid_height = _scenario_dimensions(project, record)
    if max(grid_width, grid_height) != int(policy["canonicalMaximumGridDimension"]):
        raise ContractError(f"PLAN-SCENARIO-DIMENSION:{record['globalProcessOrdinal']}")
    return {
        "schemaVersion": 3,
        "planId": "gate13r-pr2-mp2-block-plan-v1",
        "designId": "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1",
        "globalProcessOrdinal": int(record["globalProcessOrdinal"]),
        "blockId": record["blockId"],
        "campaignId": record["campaignId"],
        "scenarioId": record["scenarioId"],
        "scenarioRelativePath": record["scenarioRelativePath"],
        "scenarioSourceSha256": record["scenarioSha256"],
        "comparisonCohortId": record["comparisonCohortId"],
        "block": int(record["campaignBlockOrdinal"]),
        "williamsRowIndex": int(record["williamsRowIndex"]),
        "formalCampaign": formal,
        "validationOnly": not formal,
        "analysisRole": "formal-timing" if formal else "validation-only",
        "verificationInjectedFailurePosition": 0,
        "validationInjectedNativeHardPosition": 0,
        "validationInjectedTelemetryFailurePosition": 0,
        "validationInjectedPersistenceFailurePosition": 0,
        "formalConfigRelativePath": "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json",
        "formalConfigSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"],
        "specificationRelativePath": "Research/Gate13R_PR2_MP2_Specification.v1.md",
        "specificationSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Specification.v1.md"],
        "testDesignRelativePath": "Research/Gate13R_PR2_MP2_Test_Design.v1.md",
        "testDesignSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Test_Design.v1.md"],
        "amendmentRelativePath": "Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json",
        "amendmentSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json"],
        "commandRelativePath": UNITY_COMMAND_REL,
        "commandSha256": FROZEN_HASHES[UNITY_COMMAND_REL],
        "provenanceRelativePath": "Research/Gate13R_PR2_MP2_Provenance.v4.json",
        "provenanceSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Provenance.v4.json"],
        "executionReceiptRelativePath": RECEIPT_REL if formal else "",
        "executionReceiptSha256": receipt_sha256 if formal else "",
        "memoryPolicyId": policy["policyId"],
        "policyTierId": policy["tierId"],
        "gridWidth": grid_width,
        "gridHeight": grid_height,
        "canonicalMaximumGridDimension": int(policy["canonicalMaximumGridDimension"]),
        "nativeAdvisoryThresholdBytes": int(policy["nativeAdvisoryBytes"]),
        "nativeHardThresholdBytes": int(policy["nativeHardBytes"]),
        "hostAbsoluteNativeEmergencyBytes": int(policy["hostAbsoluteNativeEmergencyBytes"]),
        "hostRelativeNativeGrowthEmergencyBytes": int(policy["hostRelativeNativeGrowthEmergencyBytes"]),
        "hostAvailablePhysicalMemoryFloorBytes": int(policy["hostAvailablePhysicalMemoryFloorBytes"]),
        "memoryPolicyRegistryRelativePath": "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json",
        "memoryPolicyRegistrySha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"],
        "scenarioPolicyMappingRelativePath": "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json",
        "scenarioPolicyMappingSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"],
        "schedulePolicyOverlayRelativePath": OVERLAY_REL,
        "schedulePolicyOverlaySha256": FROZEN_HASHES[OVERLAY_REL],
        "entries": [
            {
                "position": int(entry["position"]),
                "algorithmId": entry["algorithmId"],
                "predecessorAlgorithmId": entry["predecessorAlgorithmId"],
                "runId": entry["runId"],
                "directory": entry["childDirectory"],
            }
            for entry in record["entries"]
        ],
    }


def current_unity_processes() -> list[psutil.Process]:
    values: list[psutil.Process] = []
    for process in psutil.process_iter(("pid", "name", "create_time", "cmdline")):
        try:
            if str(process.info.get("name") or "").lower() in {"unity", "unity.exe"}:
                values.append(process)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return values


def process_telemetry(process: psutil.Process) -> dict[str, Any]:
    process.cpu_percent(interval=None)
    memory = process.memory_info()
    try:
        full = process.memory_full_info()
    except (psutil.AccessDenied, AttributeError):
        full = memory
    private = getattr(full, "private", getattr(memory, "private", getattr(memory, "vms", 0)))
    return {
        "pid": int(process.pid),
        "startTimeUtc": datetime.fromtimestamp(process.create_time(), UTC).isoformat().replace("+00:00", "Z"),
        "workingSetBytes": int(memory.rss),
        "privateMemoryBytes": int(private),
        "availablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
        "commandLine": " ".join(process.cmdline()),
    }


def status_template(
    *, project: Path, receipt_sha: str, started_at: str, state: str = "PRELAUNCH"
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "statusKind": "gate13r-pr2-formal-attempt3-operational-status-v1",
        "savedAtUtc": utc_now(),
        "status": state,
        "formalAttemptOrdinal": 3,
        "formalRoot": canonical_windows(project_path(project, FORMAL_ROOT_REL)),
        "executionReceiptSha256": receipt_sha,
        "candidateConfigSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"],
        "scheduleSha256": FROZEN_HASHES[SCHEDULE_REL],
        "startedAtUtc": started_at,
        "lastDurableCheckpointAtUtc": started_at,
        "completedProcessCount": 0,
        "completedSampleCount": 0,
        "totalProcessCount": TOTAL_PROCESSES,
        "totalSampleCount": TOTAL_SAMPLES,
        "currentGlobalProcessOrdinal": None,
        "currentCampaignId": None,
        "currentScenarioId": None,
        "currentCohort": None,
        "currentBlockId": None,
        "currentMatchedSuperblockId": None,
        "currentABBAOrder": None,
        "currentWilliamsRow": None,
        "currentUnityProcessId": None,
        "currentUnityProcessStartedAtUtc": None,
        "currentUnityBlockStartedAtUtc": None,
        "latestWorkingSetBytes": None,
        "latestPrivateMemoryBytes": None,
        "latestAvailablePhysicalMemoryBytes": None,
        "outputFileCount": 0,
        "rawBytes": 0,
        "advisoryCrossingCount": 0,
        "rawDataComplete": False,
        "analysisAuthorized": False,
        "gate14RAuthorized": False,
        "automaticMeasuredRetryAttempted": False,
        "automaticResumeAttempted": False,
        "automaticTopUpAttempted": False,
        "partialAttemptMergeAttempted": False,
        "errorReasonCode": None,
        "failureCheckpointPath": None,
    }


def matched_identity(record: dict[str, Any]) -> tuple[str | None, str | None]:
    value = record.get("matchedSuperblock")
    if not isinstance(value, dict):
        return None, None
    return str(value["matchedSuperblockId"]), str(value["cohortOrder"])


def apply_record_to_status(status: dict[str, Any], record: dict[str, Any]) -> None:
    matched_id, order = matched_identity(record)
    status.update(
        {
            "currentGlobalProcessOrdinal": int(record["globalProcessOrdinal"]),
            "currentCampaignId": str(record["campaignId"]),
            "currentScenarioId": str(record["scenarioId"]),
            "currentCohort": str(record["comparisonCohortId"]),
            "currentBlockId": str(record["blockId"]),
            "currentMatchedSuperblockId": matched_id,
            "currentABBAOrder": order,
            "currentWilliamsRow": int(record["williamsRowIndex"]) + 1,
        }
    )


class StatusPublisher:
    def __init__(self, project: Path, receipt_sha: str, started_at: str) -> None:
        self.project = project
        self.path = project_path(project, STATUS_REL)
        self.schema = read_json(project_path(project, STATUS_SCHEMA_REL))
        self.value = status_template(project=project, receipt_sha=receipt_sha, started_at=started_at)

    def publish(self, *, create: bool = False) -> None:
        self.value["savedAtUtc"] = utc_now()
        jsonschema.validate(self.value, self.schema)
        atomic_json(self.path, self.value, replace=not create)

    def durable_checkpoint(self, when: str | None = None) -> None:
        self.value["lastDurableCheckpointAtUtc"] = when or utc_now()


def root_checkpoint(
    path: Path,
    *,
    status: str,
    receipt_sha: str,
    completed_processes: int,
    completed_samples: int,
    record: dict[str, Any] | None,
    error: str | None = None,
) -> dict[str, Any]:
    matched_id, order = matched_identity(record or {})
    value = {
        "schemaVersion": 1,
        "checkpointKind": "gate13r-pr2-formal-attempt3-phase-a-checkpoint-v1",
        "savedAtUtc": utc_now(),
        "status": status,
        "executionReceiptSha256": receipt_sha,
        "formalAttemptOrdinal": 3,
        "completedProcessCount": completed_processes,
        "completedSampleCount": completed_samples,
        "expectedProcessCount": TOTAL_PROCESSES,
        "expectedSampleCount": TOTAL_SAMPLES,
        "currentGlobalProcessOrdinal": None if record is None else int(record["globalProcessOrdinal"]),
        "currentCampaignId": None if record is None else str(record["campaignId"]),
        "currentScenarioId": None if record is None else str(record["scenarioId"]),
        "currentCohort": None if record is None else str(record["comparisonCohortId"]),
        "currentBlockId": None if record is None else str(record["blockId"]),
        "currentMatchedSuperblockId": matched_id,
        "currentABBAOrder": order,
        "automaticMeasuredRetryAttempted": False,
        "automaticResumeAttempted": False,
        "automaticTopUpAttempted": False,
        "partialAttemptMergeAttempted": False,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "error": error,
    }
    atomic_json(path, value, replace=path.exists())
    return value


def raw_files_for_block(output_directory: Path) -> list[Path]:
    files: list[Path] = []
    if output_directory.is_dir():
        files.extend(path for path in output_directory.rglob("*") if path.is_file())
    for suffix in (".summary.json", ".Unity.log"):
        sidecar = Path(str(output_directory) + suffix)
        if sidecar.is_file():
            files.append(sidecar)
    lock_root = Path(str(output_directory) + ".lock-hygiene")
    if lock_root.is_dir():
        files.extend(path for path in lock_root.rglob("*") if path.is_file())
    unique = {path.resolve(): path.resolve() for path in files}
    return sorted(unique.values(), key=lambda item: item.as_posix())


def verify_completed_block(
    *,
    project: Path,
    formal_root: Path,
    record: dict[str, Any],
    observed_process: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], list[Path]]:
    output_directory = project_path(formal_root, str(record["outputRelativePath"]))
    manifest_path = output_directory / "block-manifest.json"
    summary_path = Path(str(output_directory) + ".summary.json")
    if not manifest_path.is_file() or not summary_path.is_file():
        raise ContractError(f"BLOCK-EVIDENCE-MISSING:{record['globalProcessOrdinal']}")
    manifest = read_json(manifest_path)
    summary = read_json(summary_path)
    if (
        int(manifest.get("schemaVersion", -1)) != 5
        or manifest.get("manifestKind") != "gate13r-pr2-mp2-formal-attempt3-candidate-block-manifest-v1"
        or manifest.get("completed") is not True
        or manifest.get("hardMemoryRulesPassed") is not True
        or manifest.get("formalCampaign") is not True
        or manifest.get("validationOnly") is not False
        or manifest.get("blockId") != record["blockId"]
        or int(manifest.get("completedSampleCount", -1)) != int(record["expectedSampleCount"])
    ):
        raise ContractError(f"BLOCK-MANIFEST-CONTRACT:{record['globalProcessOrdinal']}")
    if (
        summary.get("summaryKind") != "gate13r-pr2-mp2-block-wrapper-validation-summary-v2"
        or summary.get("mode") != "FormalAttempt3"
        or summary.get("expectedOutcome") != "Pass"
        or summary.get("passed") is not True
        or summary.get("formalCampaign") is not True
        or summary.get("validationOnly") is not False
        or summary.get("automaticRetryAttempted") is not False
        or summary.get("automaticResumeAttempted") is not False
        or summary.get("blockId") != record["blockId"]
    ):
        raise ContractError(f"BLOCK-WRAPPER-SUMMARY-CONTRACT:{record['globalProcessOrdinal']}")
    if int(summary.get("unityProcessId", -1)) != int(observed_process["pid"]):
        raise ContractError(f"BLOCK-PROCESS-ID-MISMATCH:{record['globalProcessOrdinal']}")
    if int(manifest.get("processId", -1)) != int(observed_process["pid"]):
        raise ContractError(f"MANIFEST-PROCESS-ID-MISMATCH:{record['globalProcessOrdinal']}")
    manifest_started = datetime.fromisoformat(str(manifest["processStartTimeUtc"]).replace("Z", "+00:00"))
    observed_started = datetime.fromisoformat(str(observed_process["startTimeUtc"]).replace("Z", "+00:00"))
    if abs((manifest_started - observed_started).total_seconds()) > 2.0:
        raise ContractError(f"BLOCK-PROCESS-START-MISMATCH:{record['globalProcessOrdinal']}")
    samples = list(manifest.get("samples") or [])
    expected_entries = list(record["entries"])
    if len(samples) != len(expected_entries):
        raise ContractError(f"BLOCK-SAMPLE-CARDINALITY:{record['globalProcessOrdinal']}")
    for expected, sample in zip(expected_entries, samples, strict=True):
        for key in ("position", "algorithmId", "predecessorAlgorithmId", "runId"):
            if str(sample.get(key)) != str(expected.get(key)):
                raise ContractError(f"BLOCK-SAMPLE-IDENTITY:{record['globalProcessOrdinal']}:{key}")
        if sample.get("completed") is not True or sample.get("formalCampaign") is not True:
            raise ContractError(f"BLOCK-SAMPLE-ELIGIBILITY:{sample.get('runId')}")
        for path_key, hash_key in (
            ("manifestRelativePath", "manifestSha256"),
            ("summaryRelativePath", "summarySha256"),
            ("workloadResultRelativePath", "workloadResultSha256"),
            ("memoryGateEvaluationRelativePath", "memoryGateEvaluationSha256"),
        ):
            child = (output_directory / Path(str(sample[path_key]))).resolve()
            try:
                child.relative_to(output_directory.resolve())
            except ValueError as error:
                raise ContractError(f"SAMPLE-PATH-ESCAPE:{sample['runId']}:{path_key}") from error
            if not child.is_file() or sha256_file(child) != str(sample[hash_key]):
                raise ContractError(f"SAMPLE-FILE-HASH:{sample['runId']}:{path_key}")
            child_json = read_json(child) if child.suffix.lower() == ".json" else None
            if path_key != "workloadResultRelativePath" and (
                not isinstance(child_json, dict) or child_json.get("formalCampaign") is not True
            ):
                raise ContractError(f"SAMPLE-FORMAL-CAMPAIGN-FLAG:{sample['runId']}:{path_key}")
    files = raw_files_for_block(output_directory)
    if not files:
        raise ContractError(f"BLOCK-RAW-FILES-EMPTY:{record['globalProcessOrdinal']}")
    return manifest, summary, files


def find_owned_unity(project: Path, wrapper_started: float) -> list[psutil.Process]:
    result: list[psutil.Process] = []
    project_token = str(project.resolve()).lower()
    for process in current_unity_processes():
        try:
            if process.create_time() + 2.0 < wrapper_started:
                continue
            command = " ".join(process.cmdline()).lower()
            if project_token in command:
                result.append(process)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return result


def execute_block(
    *,
    project: Path,
    formal_root: Path,
    receipt_path: Path,
    record: dict[str, Any],
    plan_path: Path,
    unity_path: Path,
    powershell_path: Path,
    block_timeout_seconds: int,
    status: StatusPublisher,
    control_root: Path,
) -> dict[str, Any]:
    ordinal = int(record["globalProcessOrdinal"])
    output_directory = project_path(formal_root, str(record["outputRelativePath"]))
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    logs_root = control_root / "block-wrapper-logs"
    logs_root.mkdir(parents=True, exist_ok=True)
    stdout_path = logs_root / f"p{ordinal:06d}.stdout.log"
    stderr_path = logs_root / f"p{ordinal:06d}.stderr.log"
    command = [
        str(powershell_path),
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(project_path(project, BLOCK_WRAPPER_REL)),
        "-ProjectPath",
        str(project),
        "-BlockPlanPath",
        str(plan_path),
        "-OutputDirectory",
        str(output_directory),
        "-AllowedRoot",
        str(formal_root),
        "-Mode",
        "FormalAttempt3",
        "-ExecutionReceiptPath",
        str(receipt_path),
        "-UnityPath",
        str(unity_path),
        "-ExpectedOutcome",
        "Pass",
        "-TimeoutSeconds",
        str(block_timeout_seconds),
    ]
    environment = os.environ.copy()
    environment["PSModulePath"] = EXPECTED_NATIVE_PSMODULEPATH
    wrapper_started = time.time()
    observed: dict[str, Any] | None = None
    concurrency_violation = False
    with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
        child = subprocess.Popen(
            command,
            cwd=str(project),
            env=environment,
            stdout=stdout,
            stderr=stderr,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        last_publish = 0.0
        while child.poll() is None:
            owned = find_owned_unity(project, wrapper_started)
            all_unity = current_unity_processes()
            if len(all_unity) > 1 or len(owned) > 1:
                concurrency_violation = True
            if len(owned) == 1:
                try:
                    telemetry = process_telemetry(owned[0])
                    if observed is None:
                        observed = telemetry.copy()
                        apply_record_to_status(status.value, record)
                        status.value["currentUnityBlockStartedAtUtc"] = telemetry["startTimeUtc"]
                    status.value["status"] = "ACQUISITION-RUNNING"
                    status.value["currentUnityProcessId"] = telemetry["pid"]
                    status.value["currentUnityProcessStartedAtUtc"] = telemetry["startTimeUtc"]
                    status.value["latestWorkingSetBytes"] = telemetry["workingSetBytes"]
                    status.value["latestPrivateMemoryBytes"] = telemetry["privateMemoryBytes"]
                    status.value["latestAvailablePhysicalMemoryBytes"] = telemetry["availablePhysicalMemoryBytes"]
                    now = time.monotonic()
                    if now - last_publish >= 5.0:
                        status.publish()
                        last_publish = now
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            time.sleep(0.5)
        exit_code = int(child.returncode)
    if concurrency_violation:
        raise ContractError(f"UNITY-CONCURRENCY-VIOLATION:{ordinal}")
    if observed is None:
        raise ContractError(f"OWNED-UNITY-PROCESS-NOT-OBSERVED:{ordinal}:wrapper-exit={exit_code}")
    if exit_code != 0:
        raise ContractError(f"BLOCK-WRAPPER-NONZERO:{ordinal}:{exit_code}")
    manifest, summary, files = verify_completed_block(
        project=project,
        formal_root=formal_root,
        record=record,
        observed_process=observed,
    )
    identity = {
        "schemaVersion": 1,
        "identityKind": "gate13r-pr2-formal-attempt3-block-process-identity-v1",
        "savedAtUtc": utc_now(),
        "globalProcessOrdinal": ordinal,
        "blockId": record["blockId"],
        "campaignId": record["campaignId"],
        "scenarioId": record["scenarioId"],
        "processId": int(observed["pid"]),
        "processStartTimeUtc": observed["startTimeUtc"],
        "manifestProcessStartTimeUtc": manifest["processStartTimeUtc"],
        "wrapperSummarySha256": sha256_file(Path(str(output_directory) + ".summary.json")),
        "blockManifestSha256": sha256_file(output_directory / "block-manifest.json"),
        "freshProcess": True,
        "maximumBlocksInProcess": 1,
    }
    identity_path = control_root / "process-identities" / f"p{ordinal:06d}.json"
    atomic_json(identity_path, identity, replace=False)
    return {
        "manifest": manifest,
        "summary": summary,
        "files": files,
        "identity": identity,
        "stdoutPath": stdout_path,
        "stderrPath": stderr_path,
    }


def inventory_files(root: Path) -> dict[str, Any]:
    files = sorted((path for path in root.rglob("*") if path.is_file()), key=lambda item: item.as_posix()) if root.exists() else []
    raw_bytes = sum(path.stat().st_size for path in files)
    last = max(files, key=lambda item: item.stat().st_mtime_ns) if files else None
    return {
        "fileCount": len(files),
        "rawBytes": raw_bytes,
        "lastWriteTimeUtc": None
        if last is None
        else datetime.fromtimestamp(last.stat().st_mtime, UTC).isoformat().replace("+00:00", "Z"),
        "lastWrittenRelativePath": None if last is None else last.relative_to(root).as_posix(),
    }


def verify_all_blocks(
    *,
    project: Path,
    formal_root: Path,
    schedule: list[dict[str, Any]],
    process_identity_root: Path,
    progress: Callable[[int], None] | None = None,
) -> dict[str, Any]:
    seen_runs: set[str] = set()
    process_count = 0
    sample_count = 0
    block_evidence: list[dict[str, Any]] = []
    for record in schedule:
        ordinal = int(record["globalProcessOrdinal"])
        output_directory = project_path(formal_root, str(record["outputRelativePath"]))
        manifest_path = output_directory / "block-manifest.json"
        summary_path = Path(str(output_directory) + ".summary.json")
        identity_path = process_identity_root / f"p{ordinal:06d}.json"
        if not manifest_path.is_file() or not summary_path.is_file() or not identity_path.is_file():
            raise ContractError(f"RAW-CONTRACT-MISSING-BLOCK-EVIDENCE:{ordinal}")
        manifest = read_json(manifest_path)
        summary = read_json(summary_path)
        identity = read_json(identity_path)
        if (
            manifest.get("completed") is not True
            or manifest.get("hardMemoryRulesPassed") is not True
            or manifest.get("formalCampaign") is not True
            or manifest.get("validationOnly") is not False
            or manifest.get("blockId") != record["blockId"]
            or summary.get("passed") is not True
            or summary.get("formalCampaign") is not True
            or summary.get("validationOnly") is not False
            or int(identity.get("globalProcessOrdinal", -1)) != ordinal
            or identity.get("blockId") != record["blockId"]
        ):
            raise ContractError(f"RAW-CONTRACT-BLOCK-EVIDENCE:{ordinal}")
        samples = list(manifest.get("samples") or [])
        if len(samples) != int(record["expectedSampleCount"]):
            raise ContractError(f"RAW-CONTRACT-SAMPLE-CARDINALITY:{ordinal}")
        for expected, sample in zip(record["entries"], samples, strict=True):
            if str(sample.get("runId")) != str(expected["runId"]):
                raise ContractError(f"RAW-CONTRACT-RUN-ID:{ordinal}")
            run_id = str(sample["runId"])
            if run_id in seen_runs:
                raise ContractError(f"RAW-CONTRACT-DUPLICATE-RUN:{run_id}")
            seen_runs.add(run_id)
            for path_key, hash_key in (
                ("manifestRelativePath", "manifestSha256"),
                ("summaryRelativePath", "summarySha256"),
                ("workloadResultRelativePath", "workloadResultSha256"),
                ("memoryGateEvaluationRelativePath", "memoryGateEvaluationSha256"),
            ):
                child = (output_directory / str(sample[path_key])).resolve()
                if not child.is_file() or sha256_file(child) != str(sample[hash_key]):
                    raise ContractError(f"RAW-CONTRACT-SAMPLE-HASH:{run_id}:{path_key}")
            sample_count += 1
        block_evidence.append(
            {
                "globalProcessOrdinal": ordinal,
                "blockId": record["blockId"],
                "campaignId": record["campaignId"],
                "scenarioId": record["scenarioId"],
                "expectedSampleCount": int(record["expectedSampleCount"]),
                "blockManifestRelativePath": manifest_path.relative_to(formal_root).as_posix(),
                "blockManifestSha256": sha256_file(manifest_path),
                "wrapperSummaryRelativePath": summary_path.relative_to(formal_root).as_posix(),
                "wrapperSummarySha256": sha256_file(summary_path),
                "processIdentityRelativePath": identity_path.relative_to(formal_root).as_posix(),
                "processIdentitySha256": sha256_file(identity_path),
            }
        )
        process_count += 1
        if progress and (process_count % 25 == 0 or process_count == TOTAL_PROCESSES):
            progress(process_count)
    if process_count != TOTAL_PROCESSES or sample_count != TOTAL_SAMPLES or len(seen_runs) != TOTAL_SAMPLES:
        raise ContractError(f"RAW-CONTRACT-FINAL-CARDINALITY:{process_count}:{sample_count}:{len(seen_runs)}")
    return {
        "processCount": process_count,
        "sampleCount": sample_count,
        "uniqueRunIdCount": len(seen_runs),
        "blockEvidence": block_evidence,
    }


def payload_snapshot(
    campaigns_root: Path,
    *,
    progress: Callable[[int], None] | None = None,
) -> dict[str, Any]:
    if not campaigns_root.is_dir():
        raise ContractError("RAW-PAYLOAD-CAMPAIGNS-ROOT-MISSING")
    files = sorted((path for path in campaigns_root.rglob("*") if path.is_file()), key=lambda item: item.as_posix())
    records: list[dict[str, Any]] = []
    tree = hashlib.sha256()
    raw_bytes = 0
    for index, path in enumerate(files, 1):
        relative = path.relative_to(campaigns_root).as_posix()
        length = path.stat().st_size
        digest = sha256_file(path)
        row = f"{relative}\0{length}\0{digest}\n".encode("utf-8")
        tree.update(row)
        records.append({"relativePath": relative, "rawBytes": length, "sha256": digest})
        raw_bytes += length
        if progress and (index % 100 == 0 or index == len(files)):
            progress(index)
    return {
        "root": canonical_windows(campaigns_root),
        "fileCount": len(records),
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": tree.hexdigest(),
        "records": records,
    }


def set_read_only(paths: Iterable[Path]) -> None:
    for path in paths:
        if os.name == "nt":
            os.chmod(path, 0o444)
        else:
            os.chmod(path, path.stat().st_mode & ~0o222)


def write_jsonl_atomic(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n" for row in rows)
    atomic_text(path, text, replace=False)


def environment_snapshot() -> dict[str, Any]:
    temperatures: list[float] = []
    temperature_error: str | None = None
    try:
        command = [
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "@(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { ([double]$_.CurrentTemperature/10.0)-273.15 }) | ConvertTo-Json -Compress",
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        if result.returncode == 0 and result.stdout.strip():
            parsed = json.loads(result.stdout)
            temperatures = [float(value) for value in (parsed if isinstance(parsed, list) else [parsed])]
        elif result.returncode != 0:
            temperature_error = result.stderr.strip() or f"exit-{result.returncode}"
    except Exception as error:  # diagnostic only; availability is recorded
        temperature_error = f"{type(error).__name__}:{error}"
    return {
        "schemaVersion": 1,
        "snapshotKind": "gate13r-pr2-formal-attempt3-environment-snapshot-v1",
        "capturedAtUtc": utc_now(),
        "computerName": os.environ.get("COMPUTERNAME"),
        "userName": os.environ.get("USERNAME"),
        "cpuLogicalCount": psutil.cpu_count(logical=True),
        "cpuPhysicalCount": psutil.cpu_count(logical=False),
        "cpuLoadPercent": psutil.cpu_percent(interval=1.0),
        "totalPhysicalMemoryBytes": int(psutil.virtual_memory().total),
        "availablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
        "hDriveFreeBytes": int(shutil.disk_usage("H:\\").free),
        "unityProcessCount": len(current_unity_processes()),
        "temperatureCelsius": temperatures,
        "thermalStatus": "available" if temperatures else "unavailable-under-preregistered-policy",
        "thermalQueryError": temperature_error,
    }


def atomic_create_or_verify(path: Path, value: Any) -> None:
    expected = json_bytes(value)
    if path.exists():
        if path.read_bytes() != expected:
            raise ContractError(f"COMMIT-TARGET-EXISTS-DIFFERENT:{path}")
        return
    atomic_json(path, value, replace=False)


def raw_commit(
    *,
    project: Path,
    formal_root: Path,
    receipt_sha: str,
    schedule: list[dict[str, Any]],
    schedule_summary: dict[str, Any],
    status: StatusPublisher,
    checkpoint_path: Path,
    completed_processes: int,
    completed_samples: int,
    control_root: Path,
) -> dict[str, Any]:
    if completed_processes != TOTAL_PROCESSES or completed_samples != TOTAL_SAMPLES:
        raise ContractError("RAW-COMMIT-INCOMPLETE-COUNTS")
    if current_unity_processes():
        raise ContractError("RAW-COMMIT-UNITY-PROCESS-PRESENT")
    if (project / "Temp/UnityLockfile").exists():
        raise ContractError("RAW-COMMIT-UNITY-LOCK-PRESENT")
    process_identity_root = control_root / "process-identities"

    def verify_progress(_: int) -> None:
        status.value["status"] = "ACQUISITION-COMPLETE-COMMIT-PENDING"
        status.publish()

    verified = verify_all_blocks(
        project=project,
        formal_root=formal_root,
        schedule=schedule,
        process_identity_root=process_identity_root,
        progress=verify_progress,
    )
    end_snapshot_path = formal_root / "environment-end-snapshot.json"
    end_snapshot = read_json(end_snapshot_path) if end_snapshot_path.exists() else environment_snapshot()
    if int(end_snapshot["unityProcessCount"]) != 0 or (project / "Temp/UnityLockfile").exists():
        raise ContractError("RAW-COMMIT-END-QUIESCENCE")
    atomic_create_or_verify(end_snapshot_path, end_snapshot)

    block_manifest_path = formal_root / "raw-block-evidence-manifest.json"
    block_manifest = (
        read_json(block_manifest_path)
        if block_manifest_path.exists()
        else {
            "schemaVersion": 1,
            "manifestKind": "gate13r-pr2-formal-attempt3-block-evidence-manifest-v1",
            "createdAtUtc": utc_now(),
            "executionReceiptSha256": receipt_sha,
            "processCount": verified["processCount"],
            "sampleCount": verified["sampleCount"],
            "uniqueRunIdCount": verified["uniqueRunIdCount"],
            "blocks": verified["blockEvidence"],
        }
    )
    atomic_create_or_verify(block_manifest_path, block_manifest)

    def payload_progress(_: int) -> None:
        status.value["status"] = "ACQUISITION-COMPLETE-COMMIT-PENDING"
        status.publish()

    campaigns_root = formal_root / "campaigns"
    first = payload_snapshot(campaigns_root, progress=payload_progress)
    payload_manifest_path = formal_root / "raw-payload-file-manifest.jsonl"
    if not payload_manifest_path.exists():
        write_jsonl_atomic(payload_manifest_path, first["records"])
    set_read_only(path for path in campaigns_root.rglob("*") if path.is_file())
    second = payload_snapshot(campaigns_root, progress=payload_progress)
    if (
        first["fileCount"] != second["fileCount"]
        or first["rawBytes"] != second["rawBytes"]
        or first["canonicalTreeSha256"] != second["canonicalTreeSha256"]
    ):
        raise ContractError("RAW-TREE-MUTATION-DURING-FREEZE")
    writable = [path for path in campaigns_root.rglob("*") if path.is_file() and os.access(path, os.W_OK)]
    if writable:
        # On Windows os.access may reflect ACLs rather than the DOS read-only bit.
        writable = [path for path in writable if not bool(path.stat().st_file_attributes & 1)]
    if writable:
        raise ContractError(f"RAW-PAYLOAD-NOT-READONLY:{len(writable)}")

    raw_execution_path = formal_root / "raw-execution-manifest.json"
    raw_execution = (
        read_json(raw_execution_path)
        if raw_execution_path.exists()
        else {
            "schemaVersion": 1,
            "manifestKind": "gate13r-pr2-s48-h48-formal-raw-execution-manifest-attempt3-v1",
            "createdAtUtc": utc_now(),
            "terminalTokens": ["RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"],
            "formalAttemptOrdinal": 3,
            "executionReceiptSha256": receipt_sha,
            "candidateConfigSha256": FROZEN_HASHES["Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"],
            "scheduleSha256": FROZEN_HASHES[SCHEDULE_REL],
            "scheduleManifestSha256": FROZEN_HASHES["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json"],
            "campaignCount": TOTAL_CAMPAIGNS,
            "scenarioCount": TOTAL_SCENARIOS,
            "processCount": verified["processCount"],
            "sampleCount": verified["sampleCount"],
            "matchedSuperblockCount": TOTAL_MATCHED_SUPERBLOCKS,
            "sharedBlockProcessCount": 1536,
            "heterogeneousBlockProcessCount": 2016,
            "abBaQuotaPerHeterogeneousScenario": "24/24",
            "orderByWilliamsRowCountPerCell": 12,
            "scheduleSummary": schedule_summary,
            "rawPayloadRootRelativePath": "campaigns",
            "rawPayloadFileCount": second["fileCount"],
            "rawPayloadOriginalBytes": second["rawBytes"],
            "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
            "rawBlockEvidenceManifestSha256": sha256_file(block_manifest_path),
            "environmentEndSnapshotSha256": sha256_file(end_snapshot_path),
            "formalStatisticalAnalysisAuthorized": False,
            "gate14RAuthorized": False,
            "ordinaryAnalysisFailureMayTriggerUnityRerun": False,
        }
    )
    atomic_create_or_verify(raw_execution_path, raw_execution)
    freeze_receipt_path = formal_root / "raw-data-freeze-receipt.json"
    freeze_receipt = (
        read_json(freeze_receipt_path)
        if freeze_receipt_path.exists()
        else {
            "schemaVersion": 1,
            "receiptKind": "gate13r-pr2-s48-h48-formal-raw-data-freeze-receipt-attempt3-v1",
            "committedAtUtc": utc_now(),
            "status": "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE",
            "formalRoot": canonical_windows(formal_root),
            "formalAttemptOrdinal": 3,
            "executionReceiptSha256": receipt_sha,
            "rawExecutionManifestSha256": sha256_file(raw_execution_path),
            "rawPayloadFileManifestSha256": sha256_file(payload_manifest_path),
            "rawBlockEvidenceManifestSha256": sha256_file(block_manifest_path),
            "environmentEndSnapshotSha256": sha256_file(end_snapshot_path),
            "rawPayloadFileCount": second["fileCount"],
            "rawPayloadOriginalBytes": second["rawBytes"],
            "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
            "allPayloadFilesReadOnly": True,
            "analysisPending": True,
            "analysisAuthorized": False,
            "ordinaryAuditOrAnalysisFailureMayTriggerUnityRerun": False,
            "automaticRetryResumeTopUpMergeAllowed": False,
            "gate14RAuthorized": False,
        }
    )
    atomic_create_or_verify(freeze_receipt_path, freeze_receipt)
    final_audit_path = formal_root / "formal-raw-ready-for-separate-analysis-authorization-audit.json"
    final_audit = (
        read_json(final_audit_path)
        if final_audit_path.exists()
        else {
            "schemaVersion": 1,
            "auditKind": "gate13r-pr2-formal-attempt3-raw-ready-for-separate-analysis-authorization-v1",
            "savedAtUtc": utc_now(),
            "passed": True,
            "statusTokens": [
                "FORMAL-RAW-DATA-COMPLETE",
                "ANALYSIS-PENDING",
                "IMMUTABLE",
                "FORMAL-RAW-READY-FOR-SEPARATE-ANALYSIS-AUTHORIZATION",
                "FORMAL-STATISTICAL-ANALYSIS-NOT-AUTHORIZED",
                "GATE14R-NOT-AUTHORIZED",
            ],
            "executionReceiptSha256": receipt_sha,
            "rawDataFreezeReceiptSha256": sha256_file(freeze_receipt_path),
            "processCount": TOTAL_PROCESSES,
            "sampleCount": TOTAL_SAMPLES,
            "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
            "phaseBAnalysisExecuted": False,
            "gate14RExecuted": False,
        }
    )
    atomic_create_or_verify(final_audit_path, final_audit)
    set_read_only(
        (
            end_snapshot_path,
            block_manifest_path,
            payload_manifest_path,
            raw_execution_path,
            freeze_receipt_path,
            final_audit_path,
        )
    )
    root_checkpoint(
        checkpoint_path,
        status=RAW_COMPLETE,
        receipt_sha=receipt_sha,
        completed_processes=TOTAL_PROCESSES,
        completed_samples=TOTAL_SAMPLES,
        record=None,
    )
    status.value.update(
        {
            "status": RAW_COMPLETE,
            "completedProcessCount": TOTAL_PROCESSES,
            "completedSampleCount": TOTAL_SAMPLES,
            "currentGlobalProcessOrdinal": None,
            "currentCampaignId": None,
            "currentScenarioId": None,
            "currentCohort": None,
            "currentBlockId": None,
            "currentMatchedSuperblockId": None,
            "currentABBAOrder": None,
            "currentWilliamsRow": None,
            "currentUnityProcessId": None,
            "currentUnityProcessStartedAtUtc": None,
            "currentUnityBlockStartedAtUtc": None,
            "latestWorkingSetBytes": None,
            "latestPrivateMemoryBytes": None,
            "latestAvailablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
            "outputFileCount": int(second["fileCount"]),
            "rawBytes": int(second["rawBytes"]),
            "rawDataComplete": True,
            "errorReasonCode": None,
            "failureCheckpointPath": None,
        }
    )
    status.durable_checkpoint()
    status.publish()
    return {
        "rawPayloadFileCount": second["fileCount"],
        "rawPayloadOriginalBytes": second["rawBytes"],
        "rawPayloadCanonicalTreeSha256": second["canonicalTreeSha256"],
        "rawDataFreezeReceipt": str(freeze_receipt_path),
        "finalAudit": str(final_audit_path),
    }


def failure_signature(error: BaseException) -> str:
    return sha256_text(f"{type(error).__name__}:{error}")


def preserve_failure(
    *,
    project: Path,
    formal_root: Path,
    control_root: Path,
    status: StatusPublisher,
    checkpoint_path: Path,
    receipt_sha: str,
    completed_processes: int,
    completed_samples: int,
    record: dict[str, Any] | None,
    error: BaseException,
    acquisition_complete: bool,
) -> None:
    message = "".join(traceback.format_exception(type(error), error, error.__traceback__))
    reason = f"{type(error).__name__}:{error}"
    snapshot = inventory_files(formal_root / "campaigns")
    failure_checkpoint_path = control_root / "formal-failure-checkpoint.json"
    root_checkpoint(
        failure_checkpoint_path,
        status="USER-ACTION-REQUIRED" if acquisition_complete else TERMINAL_FAILURE,
        receipt_sha=receipt_sha,
        completed_processes=completed_processes,
        completed_samples=completed_samples,
        record=record,
        error=message,
    )
    partial = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-formal-attempt3-partial-or-uncommitted-output-manifest-v1",
        "savedAtUtc": utc_now(),
        "status": "USER-ACTION-REQUIRED" if acquisition_complete else TERMINAL_FAILURE,
        "allMeasuredProcessesCompleted": acquisition_complete,
        "completedProcessCount": completed_processes,
        "completedSampleCount": completed_samples,
        "currentGlobalProcessOrdinal": None if record is None else int(record["globalProcessOrdinal"]),
        "currentCampaignId": None if record is None else record["campaignId"],
        "currentBlockId": None if record is None else record["blockId"],
        "fileCount": snapshot["fileCount"],
        "originalBytes": snapshot["rawBytes"],
        "lastWriteTimeUtc": snapshot["lastWriteTimeUtc"],
        "lastWrittenRelativePath": snapshot["lastWrittenRelativePath"],
        "failureSignature": failure_signature(error),
        "automaticMeasuredRetryAllowed": False,
        "automaticResumeAllowed": False,
        "topUpAllowed": False,
        "partialAttemptMergeAllowed": False,
        "unityRerunAllowedForOrdinaryPostAcquisitionToolFailure": False,
        "error": message,
    }
    atomic_json(formal_root / "partial-output-manifest.json", partial, replace=(formal_root / "partial-output-manifest.json").exists())
    atomic_text(control_root / "failure.log", message, replace=(control_root / "failure.log").exists())
    status.value.update(
        {
            "status": "USER-ACTION-REQUIRED" if acquisition_complete else TERMINAL_FAILURE,
            "completedProcessCount": completed_processes,
            "completedSampleCount": completed_samples,
            "currentUnityProcessId": None,
            "currentUnityProcessStartedAtUtc": None,
            "currentUnityBlockStartedAtUtc": None,
            "latestWorkingSetBytes": None,
            "latestPrivateMemoryBytes": None,
            "latestAvailablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
            "outputFileCount": snapshot["fileCount"],
            "rawBytes": snapshot["rawBytes"],
            "rawDataComplete": False,
            "errorReasonCode": reason,
            "failureCheckpointPath": canonical_windows(failure_checkpoint_path),
        }
    )
    status.durable_checkpoint()
    status.publish()


def validate_prelaunch(project: Path, *, require_targets_absent: bool = True) -> dict[str, Any]:
    project = project.resolve()
    hash_audit = assert_hashes(project)
    schedule, overlay, schedule_summary = validate_schedule(project)
    candidate = read_json(project_path(project, "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"))
    if (
        candidate.get("configId") != "gate13r-pr2-rq-aligned-s48-h48-mp2-attempt3-candidate-v4"
        or candidate.get("formalExecutionAuthorized") is not False
        or int(candidate["totals"]["processCount"]) != TOTAL_PROCESSES
        or int(candidate["totals"]["sampleCount"]) != TOTAL_SAMPLES
        or candidate["processSemantics"]["strictSerial"] is not True
        or int(candidate["processSemantics"]["maximumConcurrentUnityEditorProcesses"]) != 1
    ):
        raise ContractError("ACTIVE-CANDIDATE-CONTRACT")
    authorization = read_json(project_path(project, "Research/Gate13R_PR2_Attempt3_Execution_Authorization.v1.json"))
    if (
        authorization.get("authorizationId") != "gate13r-pr2-formal-attempt3-active-v2-monitored-bounded-recovery-v1"
        or authorization["authorizedScope"]["oneFreshFormalAttempt3PhaseARawAcquisitionAuthorizedAfterAllPrelaunchGates"] is not True
        or authorization["authorizedScope"]["formalStatisticalAnalysisAuthorized"] is not False
        or authorization["authorizedScope"]["gate14RAuthorized"] is not False
    ):
        raise ContractError("ATTEMPT3-AUTHORIZATION-CONTRACT")
    roots = [
        project_path(project, FORMAL_ROOT_REL),
        project_path(project, RECEIPT_REL),
        project_path(project, STATUS_REL),
    ]
    target_state = [{"path": str(path), "exists": path.exists()} for path in roots]
    if require_targets_absent and any(item["exists"] for item in target_state):
        raise ContractError("FORMAL-ATTEMPT3-TARGET-PREEXISTS")
    if require_targets_absent and current_unity_processes():
        raise ContractError("UNITY-PROCESS-PRESENT-PRELAUNCH")
    if require_targets_absent and (project / "Temp/UnityLockfile").exists():
        raise ContractError("UNITY-LOCK-PRESENT-PRELAUNCH")
    if require_targets_absent and shutil.disk_usage(project.anchor).free < MINIMUM_FREE_BYTES:
        raise ContractError("INSUFFICIENT-H-DRIVE-FREE-BYTES")
    selected = (1, 48, 1537, 2000, 3552)
    plan_hashes: list[dict[str, Any]] = []
    for ordinal in selected:
        plan = make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
        plan_hashes.append(
            {
                "globalProcessOrdinal": ordinal,
                "blockId": plan["blockId"],
                "validationPlanSha256": hashlib.sha256(json_bytes(plan)).hexdigest(),
            }
        )
    return {
        "schemaVersion": 1,
        "validationKind": "gate13r-pr2-formal-attempt3-prelaunch-core-validation-v1",
        "validatedAtUtc": utc_now(),
        "passed": True,
        "frozenHashAudit": hash_audit,
        "schedule": schedule_summary,
        "selectedDeterministicPlanReconstructions": plan_hashes,
        "formalTargets": target_state,
        "formalTargetsAbsent": not any(item["exists"] for item in target_state),
        "unityProcessCount": len(current_unity_processes()),
        "projectLockAbsent": not (project / "Temp/UnityLockfile").exists(),
        "hDriveAvailableFreeBytes": shutil.disk_usage(project.anchor).free,
        "minimumLaunchFreeBytes": MINIMUM_FREE_BYTES,
        "phaseBFormalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }


def create_receipt(
    *,
    project: Path,
    prelaunch_final_audit: Path,
    unity_path: Path,
    powershell_path: Path,
) -> tuple[Path, str, str]:
    formal_root = project_path(project, FORMAL_ROOT_REL)
    receipt_path = project_path(project, RECEIPT_REL)
    status_path = project_path(project, STATUS_REL)
    for path in (formal_root, receipt_path, status_path):
        if path.exists():
            raise ContractError(f"FORMAL-TARGET-PREEXISTS:{path}")
    audit = read_json(prelaunch_final_audit)
    if audit.get("passed") is not True or audit.get("formalRootAbsent") is not True or audit.get("formalExecutionReceiptAbsent") is not True or audit.get("formalStatusAbsent") is not True:
        raise ContractError("FINAL-PRELAUNCH-AUDIT-NOT-PASSED-OR-TARGETS-NOT-ABSENT")
    if current_unity_processes() or (project / "Temp/UnityLockfile").exists():
        raise ContractError("FINAL-COMMIT-UNITY-NOT-QUIESCENT")
    if shutil.disk_usage(project.anchor).free < MINIMUM_FREE_BYTES:
        raise ContractError("FINAL-COMMIT-STORAGE-GATE")
    if os.environ.get("PSModulePath", "") != EXPECTED_NATIVE_PSMODULEPATH:
        raise ContractError("FORMAL-ORCHESTRATOR-NATIVE-PSMODULEPATH-MISMATCH")
    started_at = utc_now()
    environment = environment_snapshot()
    if environment["unityProcessCount"] != 0 or environment["hDriveFreeBytes"] < MINIMUM_FREE_BYTES:
        raise ContractError("FINAL-ENVIRONMENT-GATE")
    receipt = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-formal-attempt3-phase-a-execution-receipt-v1",
        "receiptId": "gate13r-pr2-formal-attempt3-phase-a-one-shot-v1",
        "createdAtUtc": started_at,
        "formalAttemptOrdinal": 3,
        "formalRoot": canonical_windows(formal_root),
        "formalOperationalStatus": canonical_windows(status_path),
        "authorization": binding(project, "Research/Gate13R_PR2_Attempt3_Execution_Authorization.v1.json"),
        "authorizationPrompt": binding(project, "Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md"),
        "userAuthorization": binding(project, "Research/Gate13R_PR2_Attempt3_Execution_User_Authorization.v1.txt"),
        "preWritePreservationAudit": binding(project, "Research/Gate13R_PR2_Attempt3_Execution_PreWrite_Preservation_Audit.v1.json"),
        "prelaunchFinalAudit": {
            "resolvedAbsolutePath": canonical_windows(prelaunch_final_audit),
            "sha256": sha256_file(prelaunch_final_audit),
            "passed": True,
        },
        "activeBindings": {relative: {"relativePath": relative, "sha256": digest} for relative, digest in sorted(FROZEN_HASHES.items())},
        "executionImplementation": {
            "orchestrator": binding(project, PYTHON_REL),
            "launcher": binding(project, LAUNCHER_REL),
            "provenance": binding(project, PROVENANCE_REL),
            "blockWrapper": binding(project, BLOCK_WRAPPER_REL),
            "blockPlanBuilderReference": binding(project, PLAN_BUILDER_REL),
            "unityCommand": binding(project, UNITY_COMMAND_REL),
        },
        "runtime": {
            "pythonExecutable": sys.executable,
            "pythonVersion": sys.version,
            "nativeWindowsPowerShell": canonical_windows(powershell_path),
            "psModulePath": os.environ.get("PSModulePath"),
            "unityExecutable": canonical_windows(unity_path),
            "unityExecutableSha256": sha256_file(unity_path),
        },
        "formalDesign": {
            "campaignCount": TOTAL_CAMPAIGNS,
            "scenarioCount": TOTAL_SCENARIOS,
            "processCount": TOTAL_PROCESSES,
            "sampleCount": TOTAL_SAMPLES,
            "matchedSuperblockCount": TOTAL_MATCHED_SUPERBLOCKS,
            "strictSerial": True,
            "maximumConcurrentUnityEditorProcesses": 1,
            "maximumBlocksPerUnityEditorProcess": 1,
        },
        "environmentAtCommit": environment,
        "twoStageCommitRequired": True,
        "phaseBFormalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "automaticMeasuredRetryAuthorized": False,
        "automaticResumeAuthorized": False,
        "automaticTopUpAuthorized": False,
        "partialAttemptMergeAuthorized": False,
        "immutable": True,
    }
    atomic_json(receipt_path, receipt, replace=False)
    receipt_sha = sha256_file(receipt_path)
    formal_root.mkdir(parents=False, exist_ok=False)
    return receipt_path, receipt_sha, started_at


def run_formal(args: argparse.Namespace) -> int:
    project = Path(args.project_root).resolve()
    unity_path = Path(args.unity_path).resolve()
    powershell_path = Path(args.powershell_path).resolve()
    prelaunch_final_audit = Path(args.prelaunch_final_audit).resolve()
    if not unity_path.is_file() or not powershell_path.is_file() or not prelaunch_final_audit.is_file():
        raise ContractError("FORMAL-RUNTIME-INPUT-MISSING")
    core = validate_prelaunch(project, require_targets_absent=True)
    schedule, overlay, schedule_summary = validate_schedule(project)
    receipt_path, receipt_sha, started_at = create_receipt(
        project=project,
        prelaunch_final_audit=prelaunch_final_audit,
        unity_path=unity_path,
        powershell_path=powershell_path,
    )
    formal_root = project_path(project, FORMAL_ROOT_REL)
    control_root = formal_root / "_control"
    plans_root = formal_root / "_plans"
    control_root.mkdir(exist_ok=False)
    plans_root.mkdir(exist_ok=False)
    status = StatusPublisher(project, receipt_sha, started_at)
    status.publish(create=True)
    checkpoint_path = control_root / "formal-checkpoint.json"
    root_checkpoint(
        checkpoint_path,
        status="FORMAL-ATTEMPT3-COMMITTED-BEFORE-FIRST-BLOCK",
        receipt_sha=receipt_sha,
        completed_processes=0,
        completed_samples=0,
        record=None,
    )
    atomic_json(control_root / "launch-core-validation.json", core, replace=False)
    completed_processes = 0
    completed_samples = 0
    output_files = 0
    output_bytes = 0
    advisory_count = 0
    current_record: dict[str, Any] | None = None
    acquisition_complete = False
    try:
        for record, policy in zip(schedule, overlay, strict=True):
            current_record = record
            ordinal = int(record["globalProcessOrdinal"])
            if ordinal != completed_processes + 1:
                raise ContractError(f"SCHEDULE-ADVANCEMENT-CONTRACT:{ordinal}:{completed_processes}")
            plan = make_plan(project, record, policy, formal=True, receipt_sha256=receipt_sha)
            plan_path = plans_root / f"p{ordinal:06d}.json"
            atomic_json(plan_path, plan, replace=False)
            root_checkpoint(
                checkpoint_path,
                status="BEFORE-BLOCK",
                receipt_sha=receipt_sha,
                completed_processes=completed_processes,
                completed_samples=completed_samples,
                record=record,
            )
            status.durable_checkpoint()
            result = execute_block(
                project=project,
                formal_root=formal_root,
                receipt_path=receipt_path,
                record=record,
                plan_path=plan_path,
                unity_path=unity_path,
                powershell_path=powershell_path,
                block_timeout_seconds=int(args.block_timeout_seconds),
                status=status,
                control_root=control_root,
            )
            completed_processes += 1
            completed_samples += int(record["expectedSampleCount"])
            block_files = result["files"]
            output_files += len(block_files)
            output_bytes += sum(path.stat().st_size for path in block_files)
            advisory_count += int(result["manifest"].get("nativeAdvisoryBoundaryCount", 0))
            root_checkpoint(
                checkpoint_path,
                status="BLOCK-COMPLETED",
                receipt_sha=receipt_sha,
                completed_processes=completed_processes,
                completed_samples=completed_samples,
                record=record,
            )
            status.value.update(
                {
                    "completedProcessCount": completed_processes,
                    "completedSampleCount": completed_samples,
                    "outputFileCount": output_files,
                    "rawBytes": output_bytes,
                    "advisoryCrossingCount": advisory_count,
                }
            )
            status.durable_checkpoint()
            status.publish()
        if completed_processes != TOTAL_PROCESSES or completed_samples != TOTAL_SAMPLES:
            raise ContractError(f"ACQUISITION-TERMINAL-CARDINALITY:{completed_processes}:{completed_samples}")
        acquisition_complete = True
        root_checkpoint(
            checkpoint_path,
            status="ACQUISITION-COMPLETE-COMMIT-PENDING-NO-UNITY-RERUN",
            receipt_sha=receipt_sha,
            completed_processes=completed_processes,
            completed_samples=completed_samples,
            record=None,
        )
        status.value.update(
            {
                "status": "ACQUISITION-COMPLETE-COMMIT-PENDING",
                "completedProcessCount": completed_processes,
                "completedSampleCount": completed_samples,
                "currentGlobalProcessOrdinal": None,
                "currentCampaignId": None,
                "currentScenarioId": None,
                "currentCohort": None,
                "currentBlockId": None,
                "currentMatchedSuperblockId": None,
                "currentABBAOrder": None,
                "currentWilliamsRow": None,
                "currentUnityProcessId": None,
                "currentUnityProcessStartedAtUtc": None,
                "currentUnityBlockStartedAtUtc": None,
                "latestWorkingSetBytes": None,
                "latestPrivateMemoryBytes": None,
                "latestAvailablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
            }
        )
        status.durable_checkpoint()
        status.publish()
        signatures: list[str] = []
        commit_result: dict[str, Any] | None = None
        for attempt in range(1, 4):
            attempt_root = control_root / "raw-commit-attempts" / f"attempt-{attempt}"
            attempt_root.mkdir(parents=True, exist_ok=False)
            try:
                if attempt > 1:
                    status.value["status"] = "RAW-COMMIT-RECOVERY"
                    status.publish()
                commit_result = raw_commit(
                    project=project,
                    formal_root=formal_root,
                    receipt_sha=receipt_sha,
                    schedule=schedule,
                    schedule_summary=schedule_summary,
                    status=status,
                    checkpoint_path=checkpoint_path,
                    completed_processes=completed_processes,
                    completed_samples=completed_samples,
                    control_root=control_root,
                )
                atomic_json(
                    attempt_root / "pass-receipt.json",
                    {
                        "schemaVersion": 1,
                        "receiptKind": "gate13r-pr2-formal-attempt3-raw-commit-pass-v1",
                        "attempt": attempt,
                        "savedAtUtc": utc_now(),
                        "passed": True,
                        "result": commit_result,
                    },
                    replace=False,
                )
                break
            except Exception as commit_error:
                signature = failure_signature(commit_error)
                signatures.append(signature)
                atomic_json(
                    attempt_root / "failure-receipt.json",
                    {
                        "schemaVersion": 1,
                        "receiptKind": "gate13r-pr2-formal-attempt3-raw-commit-failure-v1",
                        "attempt": attempt,
                        "savedAtUtc": utc_now(),
                        "passed": False,
                        "failureSignature": signature,
                        "error": "".join(traceback.format_exception(type(commit_error), commit_error, commit_error.__traceback__)),
                        "unityRerunAuthorized": False,
                    },
                    replace=False,
                )
                if signatures.count(signature) >= 2 or attempt >= 3:
                    raise
                if current_unity_processes() or (project / "Temp/UnityLockfile").exists():
                    raise ContractError("COMMIT-RECOVERY-QUIESCENCE-FAILED") from commit_error
                first = payload_snapshot(formal_root / "campaigns")
                time.sleep(2)
                second = payload_snapshot(formal_root / "campaigns")
                if (
                    first["fileCount"],
                    first["rawBytes"],
                    first["canonicalTreeSha256"],
                ) != (
                    second["fileCount"],
                    second["rawBytes"],
                    second["canonicalTreeSha256"],
                ):
                    raise ContractError("COMMIT-RECOVERY-RAW-TREE-NOT-STABLE") from commit_error
        if commit_result is None:
            raise ContractError("RAW-COMMIT-NO-SUCCESS-RESULT")
        print(json.dumps({"passed": True, "status": RAW_COMPLETE, "result": commit_result}, ensure_ascii=False, sort_keys=True))
        return 0
    except BaseException as error:
        preserve_failure(
            project=project,
            formal_root=formal_root,
            control_root=control_root,
            status=status,
            checkpoint_path=checkpoint_path,
            receipt_sha=receipt_sha,
            completed_processes=completed_processes,
            completed_samples=completed_samples,
            record=current_record,
            error=error,
            acquisition_complete=acquisition_complete,
        )
        raise


def command_validate(args: argparse.Namespace) -> int:
    result = validate_prelaunch(Path(args.project_root), require_targets_absent=not args.allow_targets)
    if args.output:
        atomic_json(Path(args.output), result, replace=False)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def command_plan(args: argparse.Namespace) -> int:
    project = Path(args.project_root).resolve()
    schedule, overlay, _ = validate_schedule(project)
    ordinal = int(args.ordinal)
    if not 1 <= ordinal <= TOTAL_PROCESSES:
        raise ContractError(f"ORDINAL-OUT-OF-RANGE:{ordinal}")
    plan = make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
    result = {
        "passed": True,
        "noUnityLaunched": True,
        "formalTargetsCreated": False,
        "globalProcessOrdinal": ordinal,
        "blockId": plan["blockId"],
        "planSha256": hashlib.sha256(json_bytes(plan)).hexdigest(),
        "plan": plan if args.include_plan else None,
    }
    if args.output:
        atomic_json(Path(args.output), result, replace=False)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--project-root", required=True)
    validate.add_argument("--output", default="")
    validate.add_argument("--allow-targets", action="store_true")
    validate.set_defaults(handler=command_validate)
    plan = subparsers.add_parser("plan")
    plan.add_argument("--project-root", required=True)
    plan.add_argument("--ordinal", type=int, required=True)
    plan.add_argument("--output", default="")
    plan.add_argument("--include-plan", action="store_true")
    plan.set_defaults(handler=command_plan)
    formal = subparsers.add_parser("run")
    formal.add_argument("--project-root", required=True)
    formal.add_argument("--prelaunch-final-audit", required=True)
    formal.add_argument("--unity-path", default=r"H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe")
    formal.add_argument(
        "--powershell-path",
        default=r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
    )
    formal.add_argument("--block-timeout-seconds", type=int, default=3600)
    formal.set_defaults(handler=run_formal)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.handler(args))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ContractError, OSError, ValueError, KeyError, json.JSONDecodeError, jsonschema.ValidationError) as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2)
