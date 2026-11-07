#!/usr/bin/env python3
"""Deterministically freeze the Gate 13R-PR2-MP1 targeted memory pilot design."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


CREATED_UTC = "2026-10-09T03:06:39.3350688Z"
DESIGN_ID = "gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1"
ALGORITHMS = ["A*-R", "D*L", "C-FF", "IDFF"]
SCENARIOS = [
    ("grid-scale-g032-shared", 32, 16),
    ("grid-scale-g064-shared", 64, 16),
    ("grid-scale-g128-shared", 128, 16),
    ("grid-scale-g256-shared", 256, 48),
]
DOCS = [
    "Research/Gate13R_PR2_MP1_Authorization.v1.json",
    "Research/Gate13R_PR2_MP1_PreWrite_Preservation_Audit.v1.json",
    "Research/Gate13R_PR2_MP1_Specification.v1.md",
    "Research/Gate13R_PR2_MP1_Test_Design.v1.md",
    "Research/Gate13R_PR2_MP1_Instrumentation_Contract.v1.json",
    "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json",
    "Research/Gate13R_PR2_MP1_Output_Schema.v1.json",
    "Research/Gate13R_PR2_MP1_Analysis_Plan.v1.md",
    "Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def jsonl_bytes(rows: list[dict[str, Any]]) -> bytes:
    return b"".join(
        (json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
        for row in rows
    )


def atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite frozen design artifact: {path}")
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def williams_row(row_index: int) -> list[str]:
    count = len(ALGORITHMS)
    base = [0] + [((step + 1) // 2 if step % 2 else count - (step // 2)) for step in range(1, count)]
    return [ALGORITHMS[(index + row_index) % count] for index in base]


def slug(algorithm: str) -> str:
    return {"A*-R": "astar-r", "D*L": "dstar-l", "C-FF": "cff", "IDFF": "idff"}[algorithm]


def build_schedule(project: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    catalog_path = project / "Research/FormalScenarios/Gate11R_5pct/v1/catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8-sig"))
    by_id = {item["scenarioId"]: item for item in catalog["scenarios"]}
    rows: list[dict[str, Any]] = []
    ordinal = 0
    row_counts: dict[str, Counter[int]] = defaultdict(Counter)
    position_counts: dict[str, Counter[str]] = defaultdict(Counter)
    predecessor_counts: dict[str, Counter[str]] = defaultdict(Counter)
    for scenario_id, grid_size, block_count in SCENARIOS:
        scenario = by_id[scenario_id]
        scenario_path = project / scenario["scenarioRelativePath"]
        actual_sha = sha256_file(scenario_path)
        if actual_sha != scenario["scenarioSha256"]:
            raise RuntimeError(f"Scenario hash mismatch: {scenario_id}")
        for block_ordinal in range(1, block_count + 1):
            ordinal += 1
            row_index = (block_ordinal - 1) % 4
            order = williams_row(row_index)
            scale_id = f"g{grid_size:03d}"
            block_id = f"g13rpr2-mp1-{scale_id}-b{block_ordinal:04d}"
            entries: list[dict[str, Any]] = []
            for index, algorithm in enumerate(order):
                position = index + 1
                predecessor = "NONE" if index == 0 else order[index - 1]
                position_counts[scenario_id][f"{algorithm}|p{position}"] += 1
                predecessor_counts[scenario_id][f"{predecessor}->{algorithm}"] += 1
                entries.append(
                    {
                        "position": position,
                        "algorithmId": algorithm,
                        "predecessorAlgorithmId": predecessor,
                        "runId": f"{block_id}-p{position:02d}-{slug(algorithm)}",
                        "directory": f"runs/p{position:02d}-{slug(algorithm)}",
                    }
                )
            row_counts[scenario_id][row_index] += 1
            rows.append(
                {
                    "schemaVersion": 1,
                    "designId": DESIGN_ID,
                    "planId": "gate13r-pr2-mp1-block-plan-v1",
                    "globalProcessOrdinal": ordinal,
                    "blockOrdinalWithinScenario": block_ordinal,
                    "blockId": block_id,
                    "campaignId": f"mp1-{scenario_id}",
                    "scenarioId": scenario_id,
                    "scaleId": scale_id,
                    "gridWidth": grid_size,
                    "gridHeight": grid_size,
                    "randomSeed": int(scenario["randomSeed"]),
                    "scenarioRelativePath": scenario["scenarioRelativePath"],
                    "scenarioSourceSha256": scenario["scenarioSha256"],
                    "scenarioFingerprintSha256": scenario["scenarioFingerprintSha256"],
                    "comparisonCohortId": "four-algorithm-shared-goal-v1",
                    "williamsRowIndex": row_index,
                    "williamsOrder": order,
                    "entries": entries,
                    "measured": True,
                    "warmup": False,
                    "formalCampaign": False,
                    "analysisRole": "memory-diagnostic-only",
                    "outputRelativePath": f"blocks/g{ordinal:04d}-{block_id}",
                }
            )

    if ordinal != 96 or sum(len(row["entries"]) for row in rows) != 384:
        raise RuntimeError("Frozen schedule cardinality mismatch")
    for scenario_id, _, block_count in SCENARIOS:
        expected_rows = block_count // 4
        if dict(row_counts[scenario_id]) != {0: expected_rows, 1: expected_rows, 2: expected_rows, 3: expected_rows}:
            raise RuntimeError(f"Williams row imbalance: {scenario_id}")
        for algorithm in ALGORITHMS:
            observed = [position_counts[scenario_id][f"{algorithm}|p{position}"] for position in range(1, 5)]
            if observed != [expected_rows] * 4:
                raise RuntimeError(f"Position imbalance: {scenario_id} {algorithm} {observed}")

    balance = {
        scenario_id: {
            "williamsRowCounts": {str(k): v for k, v in sorted(row_counts[scenario_id].items())},
            "algorithmPositionCounts": dict(sorted(position_counts[scenario_id].items())),
            "predecessorCounts": dict(sorted(predecessor_counts[scenario_id].items())),
        }
        for scenario_id, _, _ in SCENARIOS
    }
    return rows, balance


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    research = project / "Research"
    schedule_path = research / "Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl"
    manifest_path = research / "Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json"
    config_path = research / "Gate13R_PR2_MP1_Pilot_Config.v1.json"
    schema_path = research / "Gate13R_PR2_MP1_Config_Schema.v1.json"

    schedule, balance = build_schedule(project)
    schedule_payload = jsonl_bytes(schedule)
    schedule_sha = hashlib.sha256(schedule_payload).hexdigest()
    bound_docs = []
    for relative in DOCS:
        path = project / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        bound_docs.append({"relativePath": relative, "sha256": sha256_file(path), "bytes": path.stat().st_size})

    manifest = {
        "schemaVersion": 1,
        "manifestId": "gate13r-pr2-mp1-pilot-schedule-manifest-v1",
        "designId": DESIGN_ID,
        "createdAtUtc": CREATED_UTC,
        "scheduleRelativePath": "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl",
        "scheduleSha256": schedule_sha,
        "measuredProcessCount": 96,
        "measuredSampleCount": 384,
        "warmupProcessCount": 0,
        "maximumAuthorizedWarmupProcessCount": 8,
        "scenarioBlockCounts": {scenario_id: blocks for scenario_id, _, blocks in SCENARIOS},
        "balance": balance,
        "strictSerial": True,
        "maximumUnityConcurrency": 1,
        "oneFreshProcessPerCompleteBlock": True,
        "adaptiveChangesAllowed": False,
        "formalCampaign": False,
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
    }
    manifest_payload = json_bytes(manifest)
    manifest_sha = hashlib.sha256(manifest_payload).hexdigest()

    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "gate13r-pr2-mp1-pilot-config-schema-v1",
        "type": "object",
        "required": ["schemaVersion", "configId", "designId", "schedule", "matrix", "execution", "policy", "authorizationBoundary"],
        "properties": {
            "schemaVersion": {"const": 1},
            "configId": {"const": "gate13r-pr2-mp1-targeted-memory-pilot-config-v1"},
            "designId": {"const": DESIGN_ID},
            "formalCampaign": {"const": False},
        },
        "additionalProperties": True,
    }
    schema_payload = json_bytes(schema)
    schema_sha = hashlib.sha256(schema_payload).hexdigest()

    config = {
        "schemaVersion": 1,
        "configId": "gate13r-pr2-mp1-targeted-memory-pilot-config-v1",
        "designId": DESIGN_ID,
        "createdAtUtc": CREATED_UTC,
        "formalCampaign": False,
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
        "schema": {"relativePath": "Research/Gate13R_PR2_MP1_Config_Schema.v1.json", "sha256": schema_sha},
        "schedule": {
            "relativePath": "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl",
            "sha256": schedule_sha,
            "manifestRelativePath": "Research/Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json",
            "manifestSha256": manifest_sha,
        },
        "matrix": {
            "measuredProcesses": 96,
            "measuredSamples": 384,
            "warmupProcesses": 0,
            "authorizedWarmupCeiling": 8,
            "scenarioBlockCounts": {scenario_id: blocks for scenario_id, _, blocks in SCENARIOS},
        },
        "execution": {
            "topology": "strict-serial",
            "maximumUnityConcurrency": 1,
            "oneFreshUnityProcessPerCompleteWilliamsBlock": True,
            "oneOccurrencePerAlgorithmPerBlock": True,
            "perSampleCompleteReset": True,
            "automaticMeasuredRetry": False,
            "automaticMeasuredResume": False,
            "automaticMeasuredTopUp": False,
            "partialAttemptMerge": False,
            "pilotRoot": "H:\\DDM_Final_Project\\Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v1",
        },
        "policy": {
            "registryRelativePath": "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json",
            "registrySha256": next(item["sha256"] for item in bound_docs if item["relativePath"].endswith("Memory_Policy_Candidate_Registry.v1.json")),
        },
        "twoStageCommit": {
            "contractRelativePath": "Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json",
            "contractSha256": next(item["sha256"] for item in bound_docs if item["relativePath"].endswith("Two_Phase_Commit_Contract.v1.json")),
        },
        "boundDesignArtifacts": bound_docs,
        "activeDiagnosticUpstream": [
            {"relativePath": "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json", "sha256": "388b7a1921fe07daf97827353f402c365b0f208a9dc62cbbff2d4b5ea2829b7d"},
            {"relativePath": "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json", "sha256": "f192265e12155d0e56e1aa94e18cea1305b66e2fbc0eeb0eeb6ad9618aeb3c3a"},
            {"relativePath": "Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json", "sha256": "11cf507ad3daee5c4d17adf3d7349e50b73a925f58fdb175e2b68315240eff5b"},
            {"relativePath": "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/evidence-manifest.json", "sha256": "73e34e3910a38462d8dc3a125eaf88e2c800b8f1808206db054fbe50e4f24c46"},
            {"relativePath": "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v2/evidence-manifest.json", "sha256": "847e93f13fe7e46eea154741d3e93421ff7c4df389b1a7a2e10cb1b676e4eb3b"},
        ],
        "authorizationBoundary": {
            "formalAttempt3Authorized": False,
            "attempt2RetryResumeTopUpMergeAuthorized": False,
            "formalStatisticalAnalysisAuthorized": False,
            "gate14RAuthorized": False,
        },
    }

    atomic_write(schedule_path, schedule_payload)
    atomic_write(manifest_path, manifest_payload)
    atomic_write(schema_path, schema_payload)
    atomic_write(config_path, json_bytes(config))
    print(json.dumps({
        "passed": True,
        "scheduleSha256": schedule_sha,
        "scheduleManifestSha256": manifest_sha,
        "schemaSha256": schema_sha,
        "configSha256": sha256_file(config_path),
        "measuredProcesses": 96,
        "measuredSamples": 384,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
