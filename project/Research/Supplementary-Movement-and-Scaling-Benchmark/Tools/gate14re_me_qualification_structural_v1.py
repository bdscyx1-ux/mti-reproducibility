#!/usr/bin/env python3
"""Structural-only validator for future Gate14Re-ME qualification raw data.

The validator checks identities, hashes, paths, schemas and cardinalities.  It
does not aggregate endpoints, compare lanes, rank algorithms, declare a winner,
or reuse qualification observations in formal inference.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, Sequence, Tuple


EXPECTED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}


class StructuralError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        raise StructuralError(f"missing file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise StructuralError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise StructuralError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise StructuralError(f"invalid JSONL: {path}:{line_number}: {exc}") from exc
            if not isinstance(value, dict):
                raise StructuralError(f"JSON object required: {path}:{line_number}")
            yield line_number, value


def require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise StructuralError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise StructuralError(f"{label} SHA-256 mismatch: expected {expected}; actual {actual}")


def resolve_project_file(argument: str, project_root: Path, label: str) -> Path:
    path = Path(argument)
    if not path.is_absolute():
        path = project_root / path
    path = path.resolve()
    try:
        path.relative_to(project_root)
    except ValueError as exc:
        raise StructuralError(f"{label} resolves outside the project: {path}") from exc
    if not path.is_file():
        raise StructuralError(f"missing {label}: {path}")
    return path


def require_fields(row: Mapping[str, Any], required: Sequence[str], location: str) -> None:
    missing = [field for field in required if field not in row]
    if missing:
        raise StructuralError(f"missing required fields {missing}: {location}")


def validate_record_ids(paths: Iterable[Path], table_name: str) -> Tuple[int, set[str]]:
    count = 0
    identifiers: set[str] = set()
    for path in paths:
        for line_number, row in read_jsonl(path):
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id:
                raise StructuralError(f"missing recordId in {table_name}: {path}:{line_number}")
            if record_id in identifiers:
                raise StructuralError(f"duplicate recordId in {table_name}: {record_id}")
            identifiers.add(record_id)
            count += 1
    return count, identifiers


def validate_lane_directory(
    path: Path,
    expected_identity_sha: str,
    table_specs: Mapping[str, Mapping[str, Any]],
    expected_input: Mapping[str, str],
    expected_manifest_sha: str,
    expected_budget_sha: str,
    expected_fairness_sha: str,
    expected_oracle_relative: str,
    expected_oracle_sha: str,
) -> Dict[str, int]:
    required = {
        "operations.raw.v1.jsonl",
        "event-groups.raw.v1.jsonl",
        "persistent-state.raw.v1.jsonl",
        "process-resources.raw.v1.jsonl",
        "lane-receipt.v1.json",
    }
    missing = sorted(name for name in required if not (path / name).is_file())
    if missing:
        raise StructuralError(f"lane missing files at {path}: {missing}")
    receipt = read_json(path / "lane-receipt.v1.json")
    if receipt.get("status") != "COMPLETE_RAW_LANE" or not receipt.get("completed") or not receipt.get("instrumentValid"):
        raise StructuralError(f"lane receipt is not structurally complete: {path}")
    lane = receipt.get("anonymousLaneId")
    if lane not in EXPECTED_LANES or path.name != lane:
        raise StructuralError(f"lane identity/path mismatch: {path}")
    if receipt.get("superblockId") != path.parent.name or not isinstance(receipt.get("inputId"), str) or not receipt.get("inputId"):
        raise StructuralError(f"lane input/superblock receipt mismatch: {path}")
    if (receipt.get("inputId") != expected_input.get("inputId") or
            receipt.get("inputRelativePath") != expected_input.get("relativePath") or
            receipt.get("inputSha256") != expected_input.get("sha256")):
        raise StructuralError(f"lane input path/hash/id differs from the frozen schedule: {path}")
    if (receipt.get("implementationManifestSha256") != expected_manifest_sha or
            receipt.get("resourceBudgetSha256") != expected_budget_sha or
            receipt.get("fairnessBindingSha256") != expected_fairness_sha or
            receipt.get("oracleReceiptRelativePath") != expected_oracle_relative or
            receipt.get("oracleReceiptSha256") != expected_oracle_sha):
        raise StructuralError(f"lane receipt provenance binding mismatch: {path}")
    if receipt.get("identityBindingSha256") != expected_identity_sha:
        raise StructuralError(f"lane identity-binding hash mismatch: {path}")

    event_rows = list(read_jsonl(path / "event-groups.raw.v1.jsonl"))
    if len(event_rows) != 24:
        raise StructuralError(f"lane must have exactly 24 event rows: {path}")
    event_indices: set[int] = set()
    for line_number, row in event_rows:
        require_fields(row, table_specs["event-groups"].get("requiredFields", ()), f"{path}:{line_number}")
        if (row.get("anonymousLaneId") != lane or row.get("identityBindingSha256") != expected_identity_sha or row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
            raise StructuralError(f"event row identity mismatch: {path}:{line_number}")
        index = row.get("eventGroupIndex")
        if not isinstance(index, int) or index < 0 or index > 23 or index in event_indices:
            raise StructuralError(f"invalid event-group index: {path}:{line_number}")
        event_indices.add(index)
        for field in ("eventGroupElapsedMilliseconds", "eventGroupManagedAllocatedBytes", "gridAccessorCallsTotal"):
            value = row.get(field)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(float(value)) or float(value) < 0:
                raise StructuralError(f"invalid nonnegative structural value {field}: {path}:{line_number}")
        if row.get("gridAccessorCallsTotal") != row.get("gridContainsCalls", 0) + row.get("gridIsWalkableCalls", 0) + row.get("gridGetTraversalCostCalls", 0):
            raise StructuralError(f"D2 component total mismatch: {path}:{line_number}")
        if row.get("eventGroupManagedAllocatedBytes") != row.get("allocationCounterEnd", 0) - row.get("allocationCounterStart", 0):
            raise StructuralError(f"D3 counter-difference mismatch: {path}:{line_number}")
        if (row.get("eligible") is not True or row.get("finitePositiveElapsed") is not True or
                row.get("counterValid") is not True or row.get("budgetExceededOperationCount") != 0):
            raise StructuralError(f"accepted lane contains an ineligible event group: {path}:{line_number}")

    resources = list(read_jsonl(path / "process-resources.raw.v1.jsonl"))
    if len(resources) != 26:
        raise StructuralError(f"lane must have exactly 26 process-resource rows: {path}")
    resource_ids: set[str] = set()
    for line_number, row in resources:
        require_fields(row, table_specs["process-resources"].get("requiredFields", ()), f"{path}:{line_number}")
        if (row.get("anonymousLaneId") != lane or row.get("identityBindingSha256") != expected_identity_sha or row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
            raise StructuralError(f"process-resource identity mismatch: {path}:{line_number}")
        record_id = row.get("recordId")
        if not isinstance(record_id, str) or not record_id or record_id in resource_ids:
            raise StructuralError(f"invalid/duplicate process-resource recordId: {path}:{line_number}")
        resource_ids.add(record_id)
        for field in ("privateMemoryBytes", "workingSetBytes", "managedMemoryBytes", "peakWorkingSetBytes"):
            value = row.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise StructuralError(f"invalid process-resource value {field}: {path}:{line_number}")
    state = list(read_jsonl(path / "persistent-state.raw.v1.jsonl"))
    measurement_points = {row.get("measurementPointId") for _, row in state}
    if len(measurement_points) != 26:
        raise StructuralError(f"D4 must cover exactly 26 measurement points: {path}")
    for line_number, row in state:
        require_fields(row, table_specs["persistent-state"].get("requiredFields", ()), f"{path}:{line_number}")
        if (row.get("anonymousLaneId") != lane or row.get("identityBindingSha256") != expected_identity_sha or row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
            raise StructuralError(f"D4 identity mismatch: {path}:{line_number}")
        capacity = row.get("persistentContainerCapacity")
        bytes_per_element = row.get("persistentContainerBytesPerElement")
        capacity_bytes = row.get("persistentContainerCapacityBytes")
        if not all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in (capacity, bytes_per_element, capacity_bytes)):
            raise StructuralError(f"invalid D4 integer capacity: {path}:{line_number}")
        if capacity * bytes_per_element != capacity_bytes:
            raise StructuralError(f"D4 formula mismatch: {path}:{line_number}")
        if row.get("valid") is not True or not isinstance(row.get("persistentStateBytesTotal"), int) or row.get("persistentStateBytesTotal") < 0:
            raise StructuralError(f"invalid D4 validity/total: {path}:{line_number}")
    operation_rows = list(read_jsonl(path / "operations.raw.v1.jsonl"))
    operation_ids: set[str] = set()
    for line_number, row in operation_rows:
        require_fields(row, table_specs["operations"].get("requiredFields", ()), f"{path}:{line_number}")
        if (row.get("anonymousLaneId") != lane or row.get("identityBindingSha256") != expected_identity_sha or row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
            raise StructuralError(f"operation identity mismatch: {path}:{line_number}")
        record_id = row.get("recordId")
        if not isinstance(record_id, str) or not record_id or record_id in operation_ids:
            raise StructuralError(f"invalid/duplicate operation recordId: {path}:{line_number}")
        operation_ids.add(record_id)
        if row.get("budgetExceeded") is not False:
            raise StructuralError(f"accepted lane contains a budget-exceeded operation: {path}:{line_number}")
        if row.get("operationType") in {"initial_query", "post_event_query"} and row.get("oraclePathCostMatch") is not True:
            raise StructuralError(f"accepted lane contains an oracle-mismatched query: {path}:{line_number}")
        if row.get("operationType") in {"initialize", "repair"} and row.get("status") != "Succeeded":
            raise StructuralError(f"accepted lane contains a failed initialize/repair operation: {path}:{line_number}")
    operation_count = len(operation_rows)
    if operation_count != receipt.get("operationRows"):
        raise StructuralError(f"operation receipt count mismatch: {path}")
    if len(event_rows) != receipt.get("eventGroupRows") or len(resources) != receipt.get("processResourceRows") or len(state) != receipt.get("persistentStateRows"):
        raise StructuralError(f"lane receipt row count mismatch: {path}")
    return {"eventRows": len(event_rows), "operationRows": operation_count, "stateRows": len(state), "resourceRows": len(resources)}


def validate(args: argparse.Namespace) -> Dict[str, Any]:
    project_root = Path(args.project_root).resolve()
    measured_root = Path(args.measured_root)
    if not measured_root.is_absolute():
        measured_root = project_root / measured_root
    measured_root = measured_root.resolve()
    if not measured_root.is_dir():
        raise StructuralError("measured root is missing")
    try:
        measured_root.relative_to(project_root)
    except ValueError as exc:
        raise StructuralError("measured root is outside the project") from exc
    schedule_path = resolve_project_file(args.schedule, project_root, "schedule")
    manifest_path = resolve_project_file(args.implementation_manifest, project_root, "implementation manifest")
    output_schema_path = resolve_project_file(args.output_schema, project_root, "output schema")
    require_hash(schedule_path, args.schedule_sha256, "schedule")
    require_hash(manifest_path, args.implementation_manifest_sha256, "implementation manifest")
    require_hash(output_schema_path, args.output_schema_sha256, "output schema")
    output_schema = read_json(output_schema_path)
    if output_schema.get("schema") != "gate14re-me-load-qualification-output-schema-v1":
        raise StructuralError("unexpected output-schema identity")
    table_specs = {item.get("tableId"): item for item in output_schema.get("rawTables", [])}
    expected_tables = {
        "oracle-agent-checks", "oracle-event-checks", "operations", "event-groups",
        "persistent-state", "process-resources", "empty-boundary", "replacement-ledger",
        "failures-and-voids",
    }
    if set(table_specs) != expected_tables:
        raise StructuralError("output-schema raw table membership mismatch")
    implementation_manifest = read_json(manifest_path)
    if (implementation_manifest.get("schema") != "gate14re-me-qualification-implementation-manifest-v1" or
            implementation_manifest.get("status") != "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED"):
        raise StructuralError("unexpected implementation-manifest identity/status")
    manifest_artifacts = {
        item.get("relativePath"): item
        for item in implementation_manifest.get("artifacts", [])
        if isinstance(item, dict)
    }
    runner_relative = "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs"
    runner_binding = manifest_artifacts.get(runner_relative)
    if not isinstance(runner_binding, dict) or not isinstance(runner_binding.get("sha256"), str):
        raise StructuralError("runner source binding missing from implementation manifest")
    oracle_relative = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs"
    oracle_binding = manifest_artifacts.get(oracle_relative)
    if not isinstance(oracle_binding, dict) or not isinstance(oracle_binding.get("sha256"), str):
        raise StructuralError("oracle source binding missing from implementation manifest")

    launch = read_json(measured_root / "_control/launch-receipt.v1.json")
    complete = read_json(measured_root / "_control/acquisition-complete.v1.json")
    if launch.get("status") != "AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED":
        raise StructuralError("invalid launch receipt")
    if launch.get("scheduleSha256") != args.schedule_sha256 or launch.get("implementationManifestSha256") != args.implementation_manifest_sha256:
        raise StructuralError("launch receipt is not bound to the validated schedule/implementation manifest")
    if complete.get("status") != "QUALIFICATION-RAW-COMMIT-PENDING":
        raise StructuralError("acquisition is not raw-commit pending")
    if complete.get("plannedSuperblocks") != 162 or complete.get("plannedAlgorithmLanes") != 972:
        raise StructuralError("completion cardinality declaration mismatch")
    if complete.get("formalCollectionAuthorized") or complete.get("formalAnalysisAuthorized"):
        raise StructuralError("qualification receipt improperly authorizes formal work")

    csharp_instrument = read_json(measured_root / "instruments/csharp/instrument-csharp-receipt.v1.json")
    if csharp_instrument.get("status") != "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING":
        raise StructuralError("C# instrument qualification did not pass")
    for field in (
        "gridReadProxyKnownAnswerPassed",
        "gridReadProxySemanticInvariancePassed",
        "allocationCounterPositiveControlPassed",
        "persistentStateSizerSyntheticFixturePassed",
        "clockMonotonicityPassed",
    ):
        if csharp_instrument.get(field) is not True:
            raise StructuralError(f"instrument control failed: {field}")
    if csharp_instrument.get("implementationManifestSha256") != args.implementation_manifest_sha256:
        raise StructuralError("instrument receipt implementation-manifest binding mismatch")

    primary_schedule_rows = [json.loads(line) for line in schedule_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if len(primary_schedule_rows) != 162:
        raise StructuralError("schedule must contain exactly 162 primary superblocks")
    for ordinal, row in enumerate(primary_schedule_rows):
        if row.get("schema") != "gate14re-me-load-qualification-schedule-row-v1" or row.get("ordinal") != ordinal:
            raise StructuralError(f"schedule schema/ordinal mismatch at row {ordinal}")
    primary_ids = {row["superblockId"] for row in primary_schedule_rows}
    if len(primary_ids) != 162:
        raise StructuralError("schedule has duplicate primary superblock IDs")
    schedule_by_primary = {row["superblockId"]: row for row in primary_schedule_rows}
    configured_replacements: Dict[str, str] = {}
    scheduled_inputs: Dict[str, Dict[str, str]] = {}
    scheduled_input_ids: set[str] = set()
    primary_input_paths: set[str] = set()
    replacement_input_paths: set[str] = set()
    for row in primary_schedule_rows:
        input_path = resolve_project_file(str(row.get("inputRelativePath", "")), project_root, "scheduled primary input")
        input_relative = input_path.relative_to(project_root).as_posix()
        if row.get("inputRelativePath", "").replace("\\", "/") != input_relative or input_relative in primary_input_paths:
            raise StructuralError(f"primary input path is non-canonical or duplicated: {row['superblockId']}")
        primary_input_paths.add(input_relative)
        require_hash(input_path, str(row.get("inputSha256", "")), f"primary input {row['superblockId']}")
        input_bundle = read_json(input_path)
        input_id = input_bundle.get("inputId")
        if (input_bundle.get("schema") != "gate14re-me-qualification-input-bundle-v1" or
                input_bundle.get("studyId") != "Gate14Re-ME" or
                input_bundle.get("protocolId") != "gate14re-me-load-qualification-v1" or
                input_bundle.get("superblockId") != row["superblockId"] or
                not isinstance(input_id, str) or not input_id or input_id in scheduled_input_ids):
            raise StructuralError(f"primary input identity/schema mismatch or duplicate inputId: {row['superblockId']}")
        scheduled_input_ids.add(input_id)
        scheduled_inputs[row["superblockId"]] = {
            "inputId": input_id,
            "relativePath": input_relative,
            "sha256": str(row.get("inputSha256")),
        }
        replacement = row.get("replacement")
        if replacement is not None:
            replacement_id = replacement.get("superblockId")
            if not isinstance(replacement_id, str) or not replacement_id:
                raise StructuralError(f"invalid replacement in schedule row: {row['superblockId']}")
            configured_replacements[row["superblockId"]] = replacement_id
            replacement_path = resolve_project_file(str(replacement.get("inputRelativePath", "")), project_root, "scheduled replacement input")
            replacement_relative = replacement_path.relative_to(project_root).as_posix()
            if (replacement.get("inputRelativePath", "").replace("\\", "/") != replacement_relative or
                    replacement_relative in primary_input_paths or replacement_relative in replacement_input_paths):
                raise StructuralError(f"replacement input path is non-canonical or not unique/disjoint: {row['superblockId']}")
            replacement_input_paths.add(replacement_relative)
            require_hash(replacement_path, str(replacement.get("inputSha256", "")), f"replacement input {row['superblockId']}")
            replacement_bundle = read_json(replacement_path)
            replacement_input_id = replacement_bundle.get("inputId")
            if (replacement_bundle.get("schema") != "gate14re-me-qualification-input-bundle-v1" or
                    replacement_bundle.get("studyId") != "Gate14Re-ME" or
                    replacement_bundle.get("protocolId") != "gate14re-me-load-qualification-v1" or
                    replacement_bundle.get("superblockId") != replacement_id or
                    not isinstance(replacement_input_id, str) or not replacement_input_id or replacement_input_id in scheduled_input_ids):
                raise StructuralError(f"replacement input identity/schema mismatch or duplicate inputId: {row['superblockId']}")
            scheduled_input_ids.add(replacement_input_id)
            scheduled_inputs[replacement_id] = {
                "inputId": replacement_input_id,
                "relativePath": replacement_relative,
                "sha256": str(replacement.get("inputSha256")),
            }
    if primary_input_paths.intersection(replacement_input_paths):
        raise StructuralError("replacement input paths are not disjoint from all primary input paths")
    if len(set(configured_replacements.values())) != len(configured_replacements) or primary_ids.intersection(configured_replacements.values()):
        raise StructuralError("replacement superblock IDs are not unique/disjoint")

    replacement_ledger = measured_root / "_control/replacement-ledger.raw.v1.jsonl"
    failure_void_ledger = measured_root / "_control/failures-and-voids.raw.v1.jsonl"
    replacement_rows = list(read_jsonl(replacement_ledger))
    void_rows = list(read_jsonl(failure_void_ledger))
    replacement_by_planned: Dict[str, str] = {}
    replacement_record_ids: set[str] = set()
    for line_number, row in replacement_rows:
        require_fields(row, table_specs["replacement-ledger"].get("requiredFields", ()), f"{replacement_ledger}:{line_number}")
        record_id = row.get("recordId")
        planned = row.get("plannedSuperblockId")
        replacement = row.get("replacementSuperblockId")
        if not isinstance(record_id, str) or not record_id or record_id in replacement_record_ids:
            raise StructuralError(f"invalid/duplicate replacement recordId: {replacement_ledger}:{line_number}")
        replacement_record_ids.add(record_id)
        if planned in replacement_by_planned or configured_replacements.get(planned) != replacement or row.get("replacementOrdinal") != 1:
            raise StructuralError(f"replacement ledger does not match frozen schedule: {replacement_ledger}:{line_number}")
        replacement_by_planned[str(planned)] = str(replacement)
    void_record_ids: set[str] = set()
    voided_primary_instances: set[str] = set()
    for line_number, row in void_rows:
        require_fields(row, table_specs["failures-and-voids"].get("requiredFields", ()), f"{failure_void_ledger}:{line_number}")
        record_id = row.get("recordId")
        if not isinstance(record_id, str) or not record_id or record_id in void_record_ids:
            raise StructuralError(f"invalid/duplicate void recordId: {failure_void_ledger}:{line_number}")
        void_record_ids.add(record_id)
        if row.get("isReplacement") is False and row.get("instanceId") == row.get("plannedSuperblockId"):
            voided_primary_instances.add(str(row.get("plannedSuperblockId")))
    if set(replacement_by_planned) - voided_primary_instances:
        raise StructuralError("replacement ledger lacks the corresponding primary whole-superblock void")

    oracle_receipts = sorted(measured_root.glob("oracle/*/oracle-pass-receipt.v1.json"))
    observed_primary_oracle = {path.parent.name for path in oracle_receipts if path.parent.name in primary_ids}
    if observed_primary_oracle != primary_ids:
        raise StructuralError("primary oracle receipt coverage mismatch")
    observed_oracle_ids = {path.parent.name for path in oracle_receipts}
    expected_oracle_ids = primary_ids.union(replacement_by_planned.values())
    if observed_oracle_ids != expected_oracle_ids:
        raise StructuralError("oracle receipts include missing or unbound replacement inputs")
    oracle_agent_ids: set[str] = set()
    oracle_event_ids: set[str] = set()
    for path in oracle_receipts:
        receipt = read_json(path)
        if receipt.get("status") != "PASS_ALGORITHM_NEUTRAL_GEOMETRY" or receipt.get("allGeometryChecksPassed") is not True:
            raise StructuralError(f"oracle receipt failed: {path}")
        if receipt.get("superblockId") != path.parent.name or not isinstance(receipt.get("inputId"), str) or not receipt.get("inputId"):
            raise StructuralError(f"oracle receipt input/superblock identity mismatch: {path}")
        if receipt.get("oracleSourceRelativePath") != oracle_relative or receipt.get("oracleSourceSha256") != oracle_binding.get("sha256"):
            raise StructuralError(f"oracle receipt source binding mismatch: {path}")
        expected_input = scheduled_inputs.get(path.parent.name)
        if (expected_input is None or receipt.get("inputId") != expected_input.get("inputId") or
                receipt.get("inputRelativePath") != expected_input.get("relativePath") or
                receipt.get("inputSha256") != expected_input.get("sha256")):
            raise StructuralError(f"oracle receipt input path/hash/id differs from the frozen schedule: {path}")
        agent_path = path.parent / "oracle-agent-checks.raw.v1.jsonl"
        event_path = path.parent / "oracle-event-checks.raw.v1.jsonl"
        agent_rows = list(read_jsonl(agent_path))
        event_rows = list(read_jsonl(event_path))
        if len(agent_rows) != receipt.get("agentRowCount") or len(event_rows) != receipt.get("eventGroupRowCount") or len(event_rows) != 24:
            raise StructuralError(f"oracle raw/receipt cardinality mismatch: {path.parent}")
        for line_number, row in agent_rows:
            require_fields(row, table_specs["oracle-agent-checks"].get("requiredFields", ()), f"{agent_path}:{line_number}")
            if (row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or
                    row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
                raise StructuralError(f"oracle-agent input/superblock mismatch: {agent_path}:{line_number}")
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id or record_id in oracle_agent_ids:
                raise StructuralError(f"invalid/duplicate oracle-agent recordId: {agent_path}:{line_number}")
            oracle_agent_ids.add(record_id)
        for line_number, row in event_rows:
            require_fields(row, table_specs["oracle-event-checks"].get("requiredFields", ()), f"{event_path}:{line_number}")
            if (row.get("superblockId") != receipt.get("superblockId") or row.get("inputId") != receipt.get("inputId") or
                    row.get("sourceRelativePath") != expected_input.get("relativePath") or row.get("sourceSha256") != expected_input.get("sha256")):
                raise StructuralError(f"oracle-event input/superblock mismatch: {event_path}:{line_number}")
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id or record_id in oracle_event_ids:
                raise StructuralError(f"invalid/duplicate oracle-event recordId: {event_path}:{line_number}")
            oracle_event_ids.add(record_id)

    empty_receipts = sorted(measured_root.glob("raw/empty-boundary/*/empty-boundary-receipt.v1.json"))
    if len(empty_receipts) != 12:
        raise StructuralError("exactly 12 empty-boundary process receipts are required")
    empty_rows = 0
    ordinals: set[int] = set()
    empty_record_ids: set[str] = set()
    for path in empty_receipts:
        receipt = read_json(path)
        if receipt.get("status") != "COMPLETE_EMPTY_BOUNDARY_RAW" or receipt.get("plannerInvoked") is not False or receipt.get("rawIterationRows") != 1000:
            raise StructuralError(f"invalid empty-boundary receipt: {path}")
        if receipt.get("implementationManifestSha256") != args.implementation_manifest_sha256 or receipt.get("resourceBudgetSha256") != launch.get("resourceBudgetSha256"):
            raise StructuralError(f"empty-boundary receipt provenance binding mismatch: {path}")
        ordinals.add(receipt.get("processOrdinal"))
        rows = list(read_jsonl(path.parent / "empty-boundary.raw.v1.jsonl"))
        if len(rows) != 1000:
            raise StructuralError(f"invalid empty-boundary row count: {path.parent}")
        for line_number, row in rows:
            require_fields(row, table_specs["empty-boundary"].get("requiredFields", ()), f"{path.parent}:{line_number}")
            if row.get("plannerInvoked") is not False:
                raise StructuralError(f"planner invoked in empty-boundary row: {path.parent}:{line_number}")
            if row.get("sourceRelativePath") != runner_relative or row.get("sourceSha256") != runner_binding.get("sha256"):
                raise StructuralError(f"empty-boundary source binding mismatch: {path.parent}:{line_number}")
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id or record_id in empty_record_ids:
                raise StructuralError(f"invalid/duplicate empty-boundary recordId: {path.parent}:{line_number}")
            empty_record_ids.add(record_id)
        empty_rows += len(rows)
    if ordinals != set(range(12)) or empty_rows != 12000:
        raise StructuralError("empty-boundary ordinal/cardinality mismatch")

    accepted_receipts = sorted(measured_root.glob("raw/superblocks/*/accepted-superblock-receipt.v1.json"))
    if len(accepted_receipts) != 162:
        raise StructuralError(f"exactly 162 accepted-superblock receipts are required; found {len(accepted_receipts)}")
    accepted_roots: List[Path] = []
    accepted_by_planned: Dict[str, str] = {}
    for receipt_path in accepted_receipts:
        receipt = read_json(receipt_path)
        if receipt.get("status") != "ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK" or receipt.get("acceptedAnonymousLanes") != 6:
            raise StructuralError(f"invalid accepted-superblock receipt: {receipt_path}")
        planned = receipt.get("plannedSuperblockId")
        instance = receipt.get("instanceId")
        if planned not in schedule_by_primary or planned in accepted_by_planned or instance != receipt_path.parent.name:
            raise StructuralError(f"accepted-superblock planned/instance binding mismatch: {receipt_path}")
        expected_replacement = configured_replacements.get(str(planned))
        if instance == planned:
            if receipt.get("isReplacement") is not False or planned in replacement_by_planned:
                raise StructuralError(f"primary accepted receipt conflicts with replacement ledger: {receipt_path}")
        elif instance == expected_replacement:
            if receipt.get("isReplacement") is not True or replacement_by_planned.get(str(planned)) != instance:
                raise StructuralError(f"replacement accepted receipt lacks exact ledger binding: {receipt_path}")
        else:
            raise StructuralError(f"accepted instance is absent from its frozen schedule row: {receipt_path}")
        accepted_by_planned[str(planned)] = str(instance)
        accepted_roots.append(receipt_path.parent)
    if set(accepted_by_planned) != primary_ids or set(replacement_by_planned) != {planned for planned, instance in accepted_by_planned.items() if instance != planned}:
        raise StructuralError("accepted-superblock coverage or replacement correspondence mismatch")
    lane_dirs = sorted(lane for root in accepted_roots for lane in root.iterdir() if lane.is_dir() and lane.name in EXPECTED_LANES)
    if len(lane_dirs) != 972:
        raise StructuralError(f"exactly 972 accepted fresh lanes are required; found {len(lane_dirs)}")
    superblock_to_lanes: Dict[str, set[str]] = {}
    totals = Counter()
    for lane_dir in lane_dirs:
        superblock = lane_dir.parent.name
        superblock_to_lanes.setdefault(superblock, set()).add(lane_dir.name)
        if lane_dir.parent.name not in scheduled_inputs:
            raise StructuralError(f"accepted lane input is absent from the frozen schedule: {lane_dir}")
        oracle_receipt_path = measured_root / "oracle" / lane_dir.parent.name / "oracle-pass-receipt.v1.json"
        totals.update(validate_lane_directory(
            lane_dir,
            args.identity_binding_sha256,
            table_specs,
            scheduled_inputs[lane_dir.parent.name],
            args.implementation_manifest_sha256,
            str(launch.get("resourceBudgetSha256")),
            str(launch.get("fairnessBindingSha256")),
            oracle_receipt_path.relative_to(project_root).as_posix(),
            sha256_file(oracle_receipt_path),
        ))
    if len(superblock_to_lanes) != 162:
        raise StructuralError(f"exactly 162 accepted complete superblocks are required; found {len(superblock_to_lanes)}")
    for superblock, lanes in superblock_to_lanes.items():
        if lanes != EXPECTED_LANES:
            raise StructuralError(f"incomplete six-lane superblock: {superblock}")
    if totals["eventRows"] != 23328 or totals["resourceRows"] != 25272:
        raise StructuralError("accepted event/resource cardinality mismatch")

    per_planned = Counter(str(row.get("plannedSuperblockId")) for _, row in replacement_rows)
    if any(value > 1 for value in per_planned.values()):
        raise StructuralError("more than one whole-superblock replacement was recorded")

    return {
        "schema": "gate14re-me-qualification-structural-validation-v1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE",
        "acceptedSuperblocks": 162,
        "acceptedAnonymousLanes": 972,
        "eventGroupRows": totals["eventRows"],
        "operationRows": totals["operationRows"],
        "persistentStateRows": totals["stateRows"],
        "processResourceRows": totals["resourceRows"],
        "emptyBoundaryRows": empty_rows,
        "wholeSuperblockReplacements": len(replacement_rows),
        "crossAlgorithmEffectsComputed": False,
        "rankingOrWinnerComputed": False,
        "qualificationReusedForFormalInference": False,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("validate", nargs="?")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--measured-root", required=True)
    parser.add_argument("--schedule", required=True)
    parser.add_argument("--schedule-sha256", required=True)
    parser.add_argument("--implementation-manifest", required=True)
    parser.add_argument("--implementation-manifest-sha256", required=True)
    parser.add_argument("--output-schema", required=True)
    parser.add_argument("--output-schema-sha256", required=True)
    parser.add_argument("--identity-binding-sha256", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    try:
        result = validate(parse_args(sys.argv[1:] if argv is None else argv))
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except StructuralError as exc:
        print(json.dumps({"schema": "gate14re-me-qualification-structural-validation-v1", "status": "FAIL_CLOSED", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
