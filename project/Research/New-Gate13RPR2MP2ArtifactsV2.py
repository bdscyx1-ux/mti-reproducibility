#!/usr/bin/env python3
"""Generate the deterministic Gate 13R-PR2-MP2 prospective policy overlay.

This generator never creates a formal run root or execution receipt. It only reads
the frozen PR2 v2 schedule/config and canonical scenario sources, then writes a
versioned non-executing artifact set to an explicitly selected directory.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


POLICY_ID = "gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1"
OVERLAY_ID = "gate13r-pr2-mp2-s48-h48-schedule-policy-overlay-v2"
FROZEN_AT_UTC = "2026-10-09T05:41:37.9696416Z"
FROZEN_AT_SHANGHAI = "2026-10-09T13:41:37.9745416+08:00"
MIB = 1024 * 1024
GIB = 1024 * MIB

EXPECTED_INPUTS = {
    "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json": "87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e",
    "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
    "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json": "b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724",
    "Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json": "9e81530bcf6d32dd1792c8bd693d72988bef6f37e59a1ad154019ca228908e56",
    "Research/Gate13R_PR2_Formal_Preparation_Schema.v2.json": "940bfca8cb3e677deadff2600471eeaec9e99ff6bab9a06a625a0f30365a9d1e",
    "Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json": "669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc",
    "Research/Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json": "7d6e028197c45d0e989a34268961a97a97e9ea50bd96008fd31b556eca0601cf",
    "Research/Gate13R_PR2_MP1_v2_Memory_Policy_Recommendation.v1.json": "90661dc14db20bf233c50395fa1bc41ae653bc673034b6e62c6e226963217e7a",
}

IMPLEMENTATION_FILES = [
    "Research/Gate13R_PR2_MP2_Specification.v1.md",
    "Research/Gate13R_PR2_MP2_Test_Design.v1.md",
    "Research/Gate13R_PR2_MP2_Authorization.v1.json",
    "Research/Gate13R_PR2_MP2_PreWrite_Preservation_Audit.v1.json",
    "Research/Gate13RPR2MP2MemoryPolicyV2.psm1",
    "Research/New-Gate13RPR2MP2BlockPlanV2.py",
    "Research/Run-Gate13RPR2MP2FormalBlockV2.ps1",
    "Research/Test-Gate13RPR2MP2V2.py",
    "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def stable_jsonl_bytes(values: Iterable[Any]) -> bytes:
    return b"".join(
        (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        for value in values
    )


def atomic_create(path: Path, data: bytes, replace: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not replace:
        raise FileExistsError(path)
    fd, temporary_name = tempfile.mkstemp(prefix=".g13r-pr2-mp2-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary_name, path)
        else:
            # Refuse an overwrite that appeared after the initial existence check.
            try:
                os.link(temporary_name, path)
                os.unlink(temporary_name)
            except FileExistsError:
                raise
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def tier_for_dimensions(width: Any, height: Any) -> dict[str, Any]:
    if isinstance(width, bool) or isinstance(height, bool) or not isinstance(width, int) or not isinstance(height, int):
        raise ValueError("MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-NONINTEGER")
    if width <= 0 or height <= 0:
        raise ValueError("MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-NONPOSITIVE")
    maximum = max(width, height)
    if maximum not in (32, 64, 128, 256):
        raise ValueError(f"MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-UNSUPPORTED:{maximum}")
    if maximum <= 128:
        return {
            "tierId": "MP2-NATIVE-LE128",
            "canonicalMaximumGridDimension": maximum,
            "nativeAdvisoryBytes": 512 * MIB,
            "nativeHardBytes": 640 * MIB,
        }
    return {
        "tierId": "MP2-NATIVE-EQ256",
        "canonicalMaximumGridDimension": maximum,
        "nativeAdvisoryBytes": 640 * MIB,
        "nativeHardBytes": 768 * MIB,
    }


def file_binding(project: Path, relative: str) -> dict[str, Any]:
    path = project / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"relativePath": relative, "rawBytes": path.stat().st_size, "sha256": sha256_file(path)}


def parse_schedule(schedule_path: Path) -> tuple[list[dict[str, Any]], list[bytes]]:
    records: list[dict[str, Any]] = []
    raw_lines: list[bytes] = []
    for line in schedule_path.read_bytes().splitlines(keepends=True):
        if not line.strip():
            continue
        raw_lines.append(line)
        records.append(json.loads(line.decode("utf-8-sig")))
    return records, raw_lines


def validate_schedule(records: list[dict[str, Any]]) -> dict[str, Any]:
    if len(records) != 3552:
        raise ValueError(f"schedule process count is {len(records)}, expected 3552")
    ordinals = [int(record["globalProcessOrdinal"]) for record in records]
    if ordinals != list(range(1, 3553)):
        raise ValueError("schedule global process ordinal/order mismatch")
    block_ids = {record["blockId"] for record in records}
    run_ids = {entry["runId"] for record in records for entry in record["entries"]}
    campaigns = {record["campaignId"] for record in records}
    if len(block_ids) != 3552 or len(run_ids) != 10176 or len(campaigns) != 74:
        raise ValueError("schedule cardinality or unique identity mismatch")
    superblocks: dict[str, list[dict[str, Any]]] = defaultdict(list)
    abba_by_scenario: dict[str, Counter[str]] = defaultdict(Counter)
    for record in records:
        matched = record.get("matchedSuperblock")
        if matched:
            superblocks[str(matched["matchedSuperblockId"])].append(record)
            abba_by_scenario[str(record["scenarioId"])][str(matched["cohortOrder"])] += 1
    if len(superblocks) != 1008 or any(len(value) != 2 for value in superblocks.values()):
        raise ValueError("matched-superblock identity mismatch")
    # Each order occurs twice per matched superblock (one record per cohort process),
    # therefore record counts are 48/48 and superblock quotas are 24/24 per scenario.
    for scenario, counts in abba_by_scenario.items():
        if counts != Counter({"AB": 48, "BA": 48}):
            raise ValueError(f"heterogeneous AB/BA record quota mismatch for {scenario}: {dict(counts)}")
    return {
        "campaignCount": len(campaigns),
        "processCount": len(records),
        "sampleCount": len(run_ids),
        "matchedSuperblockCount": len(superblocks),
        "heterogeneousScenarioCount": len(abba_by_scenario),
    }


def build(project: Path) -> dict[str, bytes]:
    input_bindings: dict[str, dict[str, Any]] = {}
    for relative, expected in EXPECTED_INPUTS.items():
        binding = file_binding(project, relative)
        if binding["sha256"] != expected:
            raise ValueError(f"frozen input SHA-256 mismatch: {relative}")
        input_bindings[relative] = binding

    implementation_bindings = {relative: file_binding(project, relative) for relative in IMPLEMENTATION_FILES}
    config_path = project / "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json"
    schedule_path = project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    active_config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    records, raw_schedule_lines = parse_schedule(schedule_path)
    schedule_summary = validate_schedule(records)

    scenario_records: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        scenario_records[str(record["scenarioRelativePath"])].append(record)

    scenario_entries: list[dict[str, Any]] = []
    scenario_lookup: dict[str, dict[str, Any]] = {}
    campaign_to_tier: dict[str, str] = {}
    for relative in sorted(scenario_records):
        path = project / relative
        source_bytes = path.read_bytes()
        source_sha = sha256_bytes(source_bytes)
        scenario = json.loads(source_bytes.decode("utf-8-sig"))
        associated = scenario_records[relative]
        schedule_ids = {str(record["scenarioId"]) for record in associated}
        schedule_hashes = {str(record["scenarioSha256"]).lower() for record in associated}
        if len(schedule_ids) != 1 or len(schedule_hashes) != 1:
            raise ValueError(f"ambiguous schedule mapping: {relative}")
        scenario_id = next(iter(schedule_ids))
        if str(scenario.get("scenarioId")) != scenario_id:
            raise ValueError(f"scenario ID mismatch: {relative}")
        if schedule_hashes != {source_sha}:
            raise ValueError(f"scenario SHA-256 mismatch: {relative}")
        tier = tier_for_dimensions(scenario.get("gridWidth"), scenario.get("gridHeight"))
        campaigns = sorted({str(record["campaignId"]) for record in associated})
        for campaign_id in campaigns:
            previous = campaign_to_tier.setdefault(campaign_id, tier["tierId"])
            if previous != tier["tierId"]:
                raise ValueError(f"campaign maps to multiple tiers: {campaign_id}")
        entry = {
            "scenarioId": scenario_id,
            "scenarioRelativePath": relative.replace("\\", "/"),
            "scenarioSourceSha256": source_sha,
            "gridWidth": int(scenario["gridWidth"]),
            "gridHeight": int(scenario["gridHeight"]),
            **tier,
            "managedAlertBytes": 128 * MIB,
            "managedSampleEmergencyBytes": 256 * MIB,
            "managedBlockEmergencyBytes": 256 * MIB,
            "hostAbsoluteNativeEmergencyBytes": 4 * GIB,
            "hostRelativeNativeGrowthEmergencyBytes": 2 * GIB,
            "hostAvailablePhysicalMemoryFloorBytes": 8 * GIB,
            "campaignIds": campaigns,
            "scheduleRecordCount": len(associated),
        }
        scenario_entries.append(entry)
        scenario_lookup[relative] = entry

    if len(scenario_entries) != 53 or len(campaign_to_tier) != 74:
        raise ValueError("scenario/campaign policy mapping cardinality mismatch")

    policy_registry = {
        "schemaVersion": 1,
        "registryId": "gate13r-pr2-mp2-memory-policy-registry-v2",
        "policyId": POLICY_ID,
        "frozenAtUtc": FROZEN_AT_UTC,
        "frozenAtAsiaShanghai": FROZEN_AT_SHANGHAI,
        "status": "FROZEN-PROSPECTIVE / NON-EXECUTING / FORMAL-ATTEMPT3-NOT-AUTHORIZED",
        "evidenceRole": "PILOT-INFORMED / EXCLUDED-FROM-FORMAL-ANALYSIS",
        "nativeResidency": {
            "metric": "max(workingSetDeltaFromBlockBaselineBytes, privateMemoryDeltaFromBlockBaselineBytes)",
            "eligibleStages": ["after-forced-cleanup", "post-block-pre-exit"],
            "rawAfterWorkloadRule": "DIAGNOSTIC-ONLY-EXCEPT-HOST-EMERGENCY",
            "exactThresholdPasses": True,
            "attributionScope": "WHOLE-BLOCK-PROCESS",
            "adaptiveRelaxationAllowed": False,
            "tiers": [
                {"tierId": "MP2-NATIVE-LE128", "allowedMaximumGridDimensions": [32, 64, 128], "advisoryBytes": 512 * MIB, "hardBytes": 640 * MIB},
                {"tierId": "MP2-NATIVE-EQ256", "allowedMaximumGridDimensions": [256], "advisoryBytes": 640 * MIB, "hardBytes": 768 * MIB},
            ],
            "unknownOrAmbiguousRule": "CONFIGURATION-HARD-FAIL-BEFORE-MEASURED-LAUNCH",
            "advisoryRule": "DURABLY-RECORD-AND-CONTINUE",
            "hardRule": "DURABLY-RECORD-AND-FORBID-NEXT-BLOCK",
        },
        "retainedManaged": {
            "boundary": "AFTER-FORCED-CLEANUP",
            "sampleAlertBytes": 128 * MIB,
            "sampleEmergencyBytes": 256 * MIB,
            "blockEmergencyBytes": 256 * MIB,
            "exactThresholdPasses": True,
        },
        "hostSafety": {
            "absoluteNativeEmergencyBytes": 4 * GIB,
            "relativeNativeGrowthEmergencyBytes": 2 * GIB,
            "availablePhysicalMemoryFloorBytes": 8 * GIB,
            "exactThresholdPasses": True,
            "telemetryOverflowOrUnverifiableSustainedGrowth": "FAIL-CLOSED",
        },
        "failurePrecedence": "DURABLE-UNITY-BLOCK-CAUSE-BEFORE-EXIT-TIMEOUT-AND-SECONDARY-LOCK-EVIDENCE",
        "twoStageCommit": "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE; VERSIONED-READ-ONLY-ANALYSIS",
        "noAutomaticRetryResumeTopUpMerge": True,
    }

    scenario_mapping = {
        "schemaVersion": 1,
        "mappingId": "gate13r-pr2-mp2-canonical-scenario-policy-mapping-v2",
        "policyId": POLICY_ID,
        "sourceScheduleSha256": EXPECTED_INPUTS["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"],
        "scenarioCount": len(scenario_entries),
        "campaignCount": len(campaign_to_tier),
        "scheduleRecordCount": len(records),
        "tierCounts": {
            "scenario": dict(sorted(Counter(entry["tierId"] for entry in scenario_entries).items())),
            "campaign": dict(sorted(Counter(campaign_to_tier.values()).items())),
            "process": dict(sorted(Counter(scenario_lookup[str(record["scenarioRelativePath"])]["tierId"] for record in records).items())),
        },
        "scenarios": scenario_entries,
    }

    overlay_records: list[dict[str, Any]] = []
    for record, raw_line in zip(records, raw_schedule_lines):
        mapping = scenario_lookup[str(record["scenarioRelativePath"])]
        overlay_records.append({
            "schemaVersion": 1,
            "overlayId": OVERLAY_ID,
            "policyId": POLICY_ID,
            "sourceScheduleRecordSha256": sha256_bytes(raw_line),
            "globalProcessOrdinal": int(record["globalProcessOrdinal"]),
            "blockId": str(record["blockId"]),
            "campaignId": str(record["campaignId"]),
            "scenarioId": str(record["scenarioId"]),
            "scenarioRelativePath": str(record["scenarioRelativePath"]).replace("\\", "/"),
            "scenarioSourceSha256": mapping["scenarioSourceSha256"],
            "comparisonCohortId": str(record["comparisonCohortId"]),
            "expectedRunIds": [str(entry["runId"]) for entry in record["entries"]],
            "tierId": mapping["tierId"],
            "canonicalMaximumGridDimension": mapping["canonicalMaximumGridDimension"],
            "nativeAdvisoryBytes": mapping["nativeAdvisoryBytes"],
            "nativeHardBytes": mapping["nativeHardBytes"],
            "managedAlertBytes": 128 * MIB,
            "managedSampleEmergencyBytes": 256 * MIB,
            "managedBlockEmergencyBytes": 256 * MIB,
            "hostAbsoluteNativeEmergencyBytes": 4 * GIB,
            "hostRelativeNativeGrowthEmergencyBytes": 2 * GIB,
            "hostAvailablePhysicalMemoryFloorBytes": 8 * GIB,
            "attributionScope": "WHOLE-BLOCK-PROCESS",
        })

    overlay_bytes = stable_jsonl_bytes(overlay_records)
    overlay_manifest = {
        "schemaVersion": 1,
        "manifestId": "gate13r-pr2-mp2-schedule-policy-overlay-manifest-v2",
        "overlayId": OVERLAY_ID,
        "policyId": POLICY_ID,
        "sourceSchedule": input_bindings["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"],
        "overlayRelativePath": "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl",
        "overlayRawBytes": len(overlay_bytes),
        "overlaySha256": sha256_bytes(overlay_bytes),
        **schedule_summary,
        "scenarioCount": len(scenario_entries),
        "tierProcessCounts": dict(sorted(Counter(record["tierId"] for record in overlay_records).items())),
        "identityInvariant": "ONE-TO-ONE-WITH-ACTIVE-PR2-V2-SCHEDULE; ORDER/RUN/OUTPUT-IDENTITIES-UNCHANGED",
    }

    amendment = {
        "schemaVersion": 1,
        "amendmentId": "gate13r-pr2-mp2-forward-memory-policy-amendment-v2",
        "frozenAtUtc": FROZEN_AT_UTC,
        "status": "FROZEN-PROSPECTIVE / NON-EXECUTING",
        "baseConfig": input_bindings["Research/Gate13R_PR2_Formal_Campaign_Config.v2.json"],
        "baseSchedule": input_bindings["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"],
        "supersedesForFutureAttemptOnly": "fixed-512-MiB-native-hard-eligibility-rule",
        "doesNotRewriteHistoricalEvidence": True,
        "unchangedDesign": {
            "campaignCount": 74,
            "processCount": 3552,
            "sampleCount": 10176,
            "strictSerial": True,
            "oneFreshUnityProcessPerCompleteWilliamsBlock": True,
            "matchedSuperblockCount": 1008,
            "heterogeneousAbBaQuotaPerScenario": "24/24",
            "scheduleIdentityChanged": False,
        },
        "policyId": POLICY_ID,
        "formalAttempt3Authorized": False,
        "formalRootCreationAuthorized": False,
        "formalExecutionReceiptCreationAuthorized": False,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }

    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "gate13r-pr2-mp2-artifacts-schema-v2",
        "title": "Gate 13R-PR2-MP2 policy mapping and candidate config schema",
        "type": "object",
        "$defs": {
            "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "tierId": {"enum": ["MP2-NATIVE-LE128", "MP2-NATIVE-EQ256"]},
            "scenarioMapping": {
                "type": "object",
                "required": ["scenarioId", "scenarioRelativePath", "scenarioSourceSha256", "canonicalMaximumGridDimension", "tierId", "nativeAdvisoryBytes", "nativeHardBytes"],
                "properties": {
                    "scenarioId": {"type": "string", "minLength": 1},
                    "scenarioRelativePath": {"type": "string", "minLength": 1},
                    "scenarioSourceSha256": {"$ref": "#/$defs/sha256"},
                    "canonicalMaximumGridDimension": {"enum": [32, 64, 128, 256]},
                    "tierId": {"$ref": "#/$defs/tierId"},
                    "nativeAdvisoryBytes": {"type": "integer", "minimum": 1},
                    "nativeHardBytes": {"type": "integer", "minimum": 1}
                },
                "additionalProperties": True
            }
        },
        "required": ["schemaVersion"],
        "properties": {"schemaVersion": {"const": 1}},
        "additionalProperties": True,
    }

    generated: dict[str, bytes] = {
        "Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json": stable_json_bytes(policy_registry),
        "Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json": stable_json_bytes(amendment),
        "Gate13R_PR2_MP2_Schema.v2.json": stable_json_bytes(schema),
        "Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json": stable_json_bytes(scenario_mapping),
        "Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl": overlay_bytes,
        "Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json": stable_json_bytes(overlay_manifest),
    }

    generated_bindings = {
        name: {"relativePath": f"Research/{name}", "rawBytes": len(data), "sha256": sha256_bytes(data)}
        for name, data in generated.items()
    }

    formal_config_amendment = {
        "schemaVersion": 1,
        "amendmentId": "gate13r-pr2-mp2-formal-attempt3-candidate-config-amendment-v2",
        "baseConfig": input_bindings["Research/Gate13R_PR2_Formal_Campaign_Config.v2.json"],
        "memoryPolicyAmendment": generated_bindings["Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json"],
        "memoryPolicyRegistry": generated_bindings["Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"],
        "scenarioPolicyMapping": generated_bindings["Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"],
        "schedulePolicyOverlay": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"],
        "schedulePolicyOverlayManifest": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json"],
        "scheduleIdentityChanged": False,
        "formalAttempt3MeasuredCampaignAuthorized": False,
        "formalAttempt3RootCreationAuthorized": False,
        "formalAttempt3ExecutionReceiptCreationAuthorized": False,
    }
    generated["Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json"] = stable_json_bytes(formal_config_amendment)
    generated_bindings["Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json"] = {
        "relativePath": "Research/Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json",
        "rawBytes": len(generated["Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json"]),
        "sha256": sha256_bytes(generated["Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json"]),
    }

    candidate = copy.deepcopy(active_config)
    candidate["schemaVersion"] = 2
    candidate["configId"] = "gate13r-pr2-rq-aligned-s48-h48-mp2-attempt3-candidate-v2"
    candidate["configKind"] = "gate13r-pr2-mp2-nonexecuting-formal-attempt3-candidate-config-v2"
    candidate["generatedAtUtc"] = FROZEN_AT_UTC
    candidate["formalExecutionAuthorized"] = False
    candidate["formalRootCreated"] = False
    candidate["formalTimingExecuted"] = False
    candidate["formalRoot"] = {
        "relativePath": "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3",
        "resolvedAtPreparation": str((project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").resolve()).replace("\\", "/"),
        "mustRemainAbsentDuringMP2": True,
        "creationAuthorized": False,
        "createNewRequiredAfterSeparateAuthorization": True,
    }
    candidate["memoryEligibility"] = {
        "policyId": POLICY_ID,
        "registry": generated_bindings["Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"],
        "scenarioMapping": generated_bindings["Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"],
        "scheduleOverlay": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"],
        "scheduleOverlayManifest": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json"],
        "nativeResidencyMetric": "max(workingSetDeltaFromBlockBaselineBytes,privateMemoryDeltaFromBlockBaselineBytes)",
        "tierLe128": {"advisoryBytes": 512 * MIB, "hardBytes": 640 * MIB},
        "tierEq256": {"advisoryBytes": 640 * MIB, "hardBytes": 768 * MIB},
        "managed": {"alertBytes": 128 * MIB, "sampleEmergencyBytes": 256 * MIB, "blockEmergencyBytes": 256 * MIB},
        "hostSafety": {"absoluteNativeEmergencyBytes": 4 * GIB, "relativeNativeGrowthEmergencyBytes": 2 * GIB, "availablePhysicalMemoryFloorBytes": 8 * GIB},
        "rawAfterWorkloadTransientDiagnosticOnlyExceptHostEmergency": True,
        "hardCrossingForbidsNextBlock": True,
        "attributionScope": "WHOLE-BLOCK-PROCESS",
        "exactThresholdPasses": True,
    }
    candidate["mp2AuthorizationBoundary"] = {
        "nonExecuting": True,
        "validationOnlyUnityAuthorized": True,
        "formalAttempt3MeasuredCampaignAuthorized": False,
        "formalAttempt3RootCreationAuthorized": False,
        "formalAttempt3ExecutionReceiptCreationAuthorized": False,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }
    candidate["mp2Bindings"] = {
        "authorization": implementation_bindings["Research/Gate13R_PR2_MP2_Authorization.v1.json"],
        "specification": implementation_bindings["Research/Gate13R_PR2_MP2_Specification.v1.md"],
        "testDesign": implementation_bindings["Research/Gate13R_PR2_MP2_Test_Design.v1.md"],
        "formalConfigAmendment": generated_bindings["Gate13R_PR2_MP2_Formal_Config_Amendment.v2.json"],
        "policyRegistry": generated_bindings["Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"],
        "scenarioMapping": generated_bindings["Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"],
        "scheduleOverlay": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"],
        "executionAdapter": implementation_bindings["Research/Run-Gate13RPR2MP2FormalBlockV2.ps1"],
        "blockPlanBuilder": implementation_bindings["Research/New-Gate13RPR2MP2BlockPlanV2.py"],
        "unityCommand": implementation_bindings["Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs"],
        "policyModule": implementation_bindings["Research/Gate13RPR2MP2MemoryPolicyV2.psm1"],
    }
    candidate_bytes = stable_json_bytes(candidate)
    generated["Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v2.json"] = candidate_bytes
    candidate_binding = {
        "relativePath": "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v2.json",
        "rawBytes": len(candidate_bytes),
        "sha256": sha256_bytes(candidate_bytes),
    }

    adapter_descriptor = {
        "schemaVersion": 1,
        "adapterId": "gate13r-pr2-mp2-formal-attempt3-candidate-block-adapter-v2",
        "status": "IMPLEMENTED-NOT-AUTHORIZED-FOR-FORMAL-LAUNCH",
        "candidateConfig": candidate_binding,
        "schedule": input_bindings["Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"],
        "overlay": generated_bindings["Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"],
        "powerShellWrapper": implementation_bindings["Research/Run-Gate13RPR2MP2FormalBlockV2.ps1"],
        "blockPlanBuilder": implementation_bindings["Research/New-Gate13RPR2MP2BlockPlanV2.py"],
        "unityCommand": implementation_bindings["Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs"],
        "policyModule": implementation_bindings["Research/Gate13RPR2MP2MemoryPolicyV2.psm1"],
        "formalModeRequiresSeparateAttempt3Receipt": True,
        "validationModeRequiresIndependentVerificationRoot": True,
        "createsFormalRoot": False,
        "createsFormalReceipt": False,
    }
    generated["Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v2.json"] = stable_json_bytes(adapter_descriptor)

    output_bindings = {
        name: {"relativePath": f"Research/{name}", "rawBytes": len(data), "sha256": sha256_bytes(data)}
        for name, data in generated.items()
    }
    provenance = {
        "schemaVersion": 1,
        "provenanceId": "gate13r-pr2-mp2-nonexecuting-formal-attempt3-readiness-provenance-v2",
        "generatedAtUtc": FROZEN_AT_UTC,
        "generatedAtAsiaShanghai": FROZEN_AT_SHANGHAI,
        "status": "NON-EXECUTING / FORMAL-CAMPAIGN-NOT-AUTHORIZED",
        "inputs": input_bindings,
        "implementation": implementation_bindings,
        "outputsExcludingThisProvenance": output_bindings,
        "scheduleValidation": schedule_summary,
        "mappingValidation": {
            "scenarioCount": len(scenario_entries),
            "campaignCount": len(campaign_to_tier),
            "processCount": len(overlay_records),
            "uniqueTierPerScenarioCampaignProcess": True,
        },
        "randomSeedsUsed": [],
        "formalAttempt3RootCreated": False,
        "formalAttempt3ReceiptCreated": False,
        "formalAttempt3MeasuredCampaignExecuted": False,
        "formalStatisticalAnalysisExecuted": False,
        "gate14RExecuted": False,
    }
    generated["Gate13R_PR2_MP2_Provenance.v2.json"] = stable_json_bytes(provenance)
    return generated


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--replace", action="store_true", help="Replace files only in an explicitly disposable validation directory.")
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output = Path(args.output_dir).resolve()
    formal_v3 = (project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").resolve()
    receipt_v3 = project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
    if formal_v3.exists() or receipt_v3.exists():
        raise SystemExit("MP2 fail closed: formal attempt-3 root or receipt exists")
    artifacts = build(project)
    for name, data in artifacts.items():
        atomic_create(output / name, data, args.replace)
    summary = {
        "passed": True,
        "outputDirectory": str(output),
        "artifactCount": len(artifacts),
        "artifacts": {name: {"rawBytes": len(data), "sha256": sha256_bytes(data)} for name, data in sorted(artifacts.items())},
        "formalAttempt3RootCreated": False,
        "formalAttempt3ReceiptCreated": False,
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
