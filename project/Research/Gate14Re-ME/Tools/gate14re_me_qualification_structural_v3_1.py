#!/usr/bin/env python3
"""Fail-closed structural validator for Gate14Re-ME output schema v3 (tool v3.1).

This tool validates raw identities, scalar types, source bindings, D3-v3.1
window semantics, fixed per-lane/per-process cardinalities, one-to-one D3
joins, accepted-superblock receipts, and the complete process-ledger/process-
identity chain.  It never aggregates endpoints, compares algorithms, ranks
algorithms, or adjudicates a winner.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, Sequence, Tuple


TOOL_SCHEMA = "gate14re-me-qualification-structural-tool-v3.1"
VALIDATION_SCHEMA = "gate14re-me-qualification-structural-validation-v3.1"
OUTPUT_SCHEMA_ID = "gate14re-me-load-qualification-output-schema-v3"
EXPECTED_SCHEMA_SHA256 = "e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c"
D3_COUNTER_ID = "GC.Alloc-Begin-owner-thread-window-v3.1"
D3_SEMANTIC_VERSION = "3.1"
D3_CONTRACT_RELATIVE_PATH = (
    "Research/Gate14Re-ME/Execution/v3/"
    "d3-cumulative-managed-allocation-contract.qualified.v1.json"
)
D3_CONTRACT_SHA256 = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"
ALLOWED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
RUNNER_METHOD = "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run"
TRUSTED_IDENTITY_RULE_SHA256 = "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06"
TIMESTAMP_COMPARATOR_SHA256 = "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27"
MEASUREMENT_POINT_IDS = (
    "after-initialization",
    "after-initial-queries",
    *(f"after-event-group-{index}" for index in range(24)),
)
RAW_TABLE_ORDER = (
    "oracle-agent-checks",
    "oracle-event-checks",
    "operations",
    "event-groups",
    "d3-windows",
    "persistent-state",
    "process-resources",
    "empty-boundary",
    "replacement-ledger",
    "failures-and-voids",
)
PROHIBITED_D3_SNAPSHOT_FIELDS = {
    "allocationCounterStart",
    "allocationCounterEnd",
    "eventGroupManagedAllocatedBytes",
    "allocatedBytes",
}
INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1


class StructuralError(RuntimeError):
    """A fail-closed structural validation error."""


@dataclass(frozen=True)
class RowEnvelope:
    table_id: str
    path: Path
    line_number: int
    row: Dict[str, Any]

    @property
    def location(self) -> str:
        return f"{self.path}:{self.line_number}"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def read_json(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        raise StructuralError(f"missing JSON file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise StructuralError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise StructuralError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    if not path.is_file():
        raise StructuralError(f"missing JSONL file: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise StructuralError(
                    f"invalid JSONL: {path}:{line_number}: {exc}"
                ) from exc
            if not isinstance(value, dict):
                raise StructuralError(
                    f"JSON object required: {path}:{line_number}"
                )
            yield line_number, value


def within(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise StructuralError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise StructuralError(
            f"{label} SHA-256 mismatch: expected {expected}; actual {actual}"
        )


def resolve_project_file(value: str | Path, project_root: Path, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = project_root / path
    path = path.resolve()
    if not within(path, project_root) or not path.is_file():
        raise StructuralError(f"{label} is missing or outside project: {path}")
    return path


def require_fields(row: Mapping[str, Any], required: Iterable[str], location: str) -> None:
    missing = [field for field in required if field not in row]
    if missing:
        raise StructuralError(f"missing required fields {missing}: {location}")


def require_string(value: Any, location: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value):
        raise StructuralError(f"string required: {location}")
    return value


def require_bool(value: Any, location: str) -> bool:
    if not isinstance(value, bool):
        raise StructuralError(f"boolean required: {location}")
    return value


def require_int(value: Any, location: str, *, minimum: int | None = None) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise StructuralError(f"integer required (bool rejected): {location}")
    if value < INT64_MIN or value > INT64_MAX:
        raise StructuralError(f"signed-int64 overflow: {location}")
    if minimum is not None and value < minimum:
        raise StructuralError(f"integer below {minimum}: {location}")
    return value


def require_number(
    value: Any, location: str, *, minimum: float | None = None
) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise StructuralError(f"finite number required (bool rejected): {location}")
    result = float(value)
    if not math.isfinite(result):
        raise StructuralError(f"finite number required: {location}")
    if minimum is not None and result < minimum:
        raise StructuralError(f"number below {minimum}: {location}")
    return result


def validate_flat_scalars(row: Mapping[str, Any], location: str) -> None:
    for field, value in row.items():
        if value is None or isinstance(value, (str, bool)):
            continue
        if isinstance(value, int):
            require_int(value, f"{location}:{field}")
            continue
        if isinstance(value, float):
            require_number(value, f"{location}:{field}")
            continue
        raise StructuralError(
            f"raw row must contain only flat JSON scalar values: {location}:{field}"
        )


def load_specs(schema_path: Path, schema_sha256: str) -> Dict[str, Dict[str, Any]]:
    require_hash(schema_path, schema_sha256, "output schema")
    if schema_sha256 != EXPECTED_SCHEMA_SHA256:
        raise StructuralError("output-schema hash is not the frozen schema-v3 hash")
    schema = read_json(schema_path)
    if schema.get("schema") != OUTPUT_SCHEMA_ID or schema.get("version") != 3:
        raise StructuralError("unexpected output-schema identity/version")
    d3_binding = schema.get("d3Binding")
    if not isinstance(d3_binding, dict):
        raise StructuralError("output schema lacks d3Binding")
    expected_binding = {
        "endpointId": "D3",
        "semanticVersion": D3_SEMANTIC_VERSION,
        "counterId": D3_COUNTER_ID,
        "contractRelativePath": D3_CONTRACT_RELATIVE_PATH,
        "contractSha256": D3_CONTRACT_SHA256,
        "primaryRawTable": "d3-windows",
        "primaryRawField": "managedAllocationBytes",
        "rateDerivedField": "managedAllocationRateBytesPerSecond",
    }
    for field, expected in expected_binding.items():
        if d3_binding.get(field) != expected:
            raise StructuralError(f"output-schema D3 binding mismatch: {field}")
    if set(d3_binding.get("oldSnapshotDifferenceFieldsProhibited", ())) != PROHIBITED_D3_SNAPSHOT_FIELDS:
        raise StructuralError("output-schema retired D3 field prohibition mismatch")
    specs: Dict[str, Dict[str, Any]] = {}
    for item in schema.get("rawTables", []):
        if not isinstance(item, dict):
            raise StructuralError("raw-table specification must be an object")
        table_id = item.get("tableId")
        if not isinstance(table_id, str) or table_id in specs:
            raise StructuralError(f"invalid or duplicate raw-table specification: {table_id}")
        specs[table_id] = item
    if tuple(specs) != RAW_TABLE_ORDER:
        raise StructuralError("raw-table order or membership differs from schema v3")
    expected_receipts = {
        "_control/launch-receipt.v2.json",
        "oracle-pass-receipt.v1.json",
        "lane-receipt.v2.json",
        "accepted-superblock-receipt.v1.json",
        "empty-boundary-receipt.v2.json",
        "instrument-csharp-receipt.v2.json",
        "instrument-export-receipt.v2.json",
        "_control/acquisition-complete.v2.json",
        "delivery-manifest.v2.json",
    }
    if set(schema.get("receipts", ())) != expected_receipts:
        raise StructuralError("output-schema receipt path/version set mismatch")
    terminal = schema.get("terminalControlPlane")
    if not isinstance(terminal, dict):
        raise StructuralError("output schema lacks terminalControlPlane")
    closure = terminal.get("fullQualificationClosure")
    expected_closure = {
        "laneReceipts": 972,
        "emptyBoundaryReceipts": 12,
        "acceptedSuperblockReceipts": 162,
        "eventGroupRows": 23328,
        "laneD3WindowRows": 24300,
        "instrumentD3WindowRows": 1,
        "emptyBoundaryD3WindowRows": 12000,
        "processResourceRows": 25272,
        "processResourceRowsPerLane": 26,
        "persistentStateMeasurementPointsPerLane": 26,
        "processLedgerRows": 1147,
        "processIdentityReceipts": 1147,
        "supervisorFinalProcessOrdinal": 1147,
    }
    if closure != expected_closure:
        raise StructuralError("output-schema full terminal closure contract mismatch")
    return specs


def discover_sources(raw_root: Path, spec: Mapping[str, Any]) -> List[Path]:
    file_name = require_string(spec.get("fileName"), f"schema:{spec.get('tableId')}:fileName")
    paths = sorted(
        (path for path in raw_root.rglob(file_name) if path.is_file()),
        key=lambda path: path.relative_to(raw_root).as_posix(),
    )
    if not paths:
        raise StructuralError(
            f"no source file found for table {spec.get('tableId')}: {file_name}"
        )
    return paths


def validate_source_binding(
    row: Mapping[str, Any], project_root: Path, location: str
) -> None:
    relative = require_string(row.get("sourceRelativePath"), f"{location}:sourceRelativePath")
    expected_sha = require_string(row.get("sourceSha256"), f"{location}:sourceSha256")
    if len(expected_sha) != 64 or any(c not in "0123456789abcdef" for c in expected_sha):
        raise StructuralError(f"lowercase SHA-256 required: {location}:sourceSha256")
    source_path = resolve_project_file(relative, project_root, "row-bound source")
    canonical_relative = source_path.relative_to(project_root).as_posix()
    if relative.replace("\\", "/") != canonical_relative:
        raise StructuralError(f"non-canonical sourceRelativePath: {location}")
    require_hash(source_path, expected_sha, f"row-bound source at {location}")


def load_tables(
    raw_root: Path,
    project_root: Path,
    specs: Mapping[str, Mapping[str, Any]],
    identity_binding_sha256: str,
) -> Dict[str, List[RowEnvelope]]:
    tables: Dict[str, List[RowEnvelope]] = {}
    for table_id in RAW_TABLE_ORDER:
        spec = specs[table_id]
        required = tuple(spec.get("requiredFields", ()))
        envelopes: List[RowEnvelope] = []
        seen: set[str] = set()
        for path in discover_sources(raw_root, spec):
            for line_number, row in read_jsonl(path):
                envelope = RowEnvelope(table_id, path, line_number, row)
                require_fields(row, required, envelope.location)
                validate_flat_scalars(row, envelope.location)
                record_id = require_string(
                    row.get("recordId"), f"{envelope.location}:recordId"
                )
                if record_id in seen:
                    raise StructuralError(
                        f"duplicate recordId in {table_id}: {record_id}"
                    )
                seen.add(record_id)
                lane = row.get("anonymousLaneId")
                if lane not in (None, ""):
                    if lane not in ALLOWED_LANES:
                        raise StructuralError(
                            f"invalid anonymous lane: {envelope.location}"
                        )
                    if row.get("identityBindingSha256") != identity_binding_sha256:
                        raise StructuralError(
                            f"anonymous identity-binding swap: {envelope.location}"
                        )
                if bool(spec.get("sourcePathAndShaRequired")):
                    validate_source_binding(row, project_root, envelope.location)
                envelopes.append(envelope)
        tables[table_id] = envelopes
    return tables


def require_no_retired_d3_fields(envelope: RowEnvelope) -> None:
    present = sorted(PROHIBITED_D3_SNAPSHOT_FIELDS.intersection(envelope.row))
    if present:
        raise StructuralError(
            f"retired D3 snapshot field(s) {present}: {envelope.location}"
        )


def validate_d3_row(envelope: RowEnvelope) -> None:
    row = envelope.row
    require_no_retired_d3_fields(envelope)
    string_fields = (
        "recordId",
        "inputId",
        "superblockId",
        "anonymousLaneId",
        "identityBindingSha256",
        "measurementScope",
        "d3CounterId",
        "d3SemanticVersion",
        "invalidReasonCode",
        "d3ContractRelativePath",
        "d3ContractSha256",
        "sourceRelativePath",
        "sourceSha256",
    )
    int_fields = (
        "eventGroupIndex",
        "processOrdinal",
        "iterationIndex",
        "managedAllocationBytes",
        "managedAllocationEventCount",
        "foreignThreadAllocationBytes",
        "foreignThreadAllocationEventCount",
        "invalidMetadataEventCount",
        "counterOverflowCount",
        "ownerNativeThreadId",
        "observerNativeThreadId",
        "windowStartStopwatchTicks",
        "windowEndStopwatchTicks",
        "windowElapsedStopwatchTicks",
        "stopwatchFrequency",
        "beginReturnCode",
        "endReturnCode",
    )
    bool_fields = (
        "managedAllocationRateValid",
        "pluginReady",
        "markerSeen",
        "metadataAbiValid",
        "ownerThreadMatched",
        "counterValid",
    )
    for field in string_fields:
        require_string(row.get(field), f"{envelope.location}:{field}", allow_empty=True)
    for field in int_fields:
        require_int(row.get(field), f"{envelope.location}:{field}")
    for field in bool_fields:
        require_bool(row.get(field), f"{envelope.location}:{field}")
    rate = require_number(
        row.get("managedAllocationRateBytesPerSecond"),
        f"{envelope.location}:managedAllocationRateBytesPerSecond",
        minimum=0.0,
    )
    if row.get("d3CounterId") != D3_COUNTER_ID:
        raise StructuralError(f"D3 counter identity mismatch: {envelope.location}")
    if row.get("d3SemanticVersion") != D3_SEMANTIC_VERSION:
        raise StructuralError(f"D3 semantic version mismatch: {envelope.location}")
    if row.get("d3ContractRelativePath") != D3_CONTRACT_RELATIVE_PATH:
        raise StructuralError(f"D3 contract path mismatch: {envelope.location}")
    if row.get("d3ContractSha256") != D3_CONTRACT_SHA256:
        raise StructuralError(f"D3 contract hash mismatch: {envelope.location}")
    for field in (
        "managedAllocationBytes",
        "managedAllocationEventCount",
        "foreignThreadAllocationBytes",
        "foreignThreadAllocationEventCount",
        "invalidMetadataEventCount",
        "counterOverflowCount",
        "windowStartStopwatchTicks",
        "windowEndStopwatchTicks",
        "windowElapsedStopwatchTicks",
    ):
        if row[field] < 0:
            raise StructuralError(f"negative D3 value {field}: {envelope.location}")
    if row["ownerNativeThreadId"] <= 0 or row["observerNativeThreadId"] <= 0:
        raise StructuralError(f"invalid D3 native thread id: {envelope.location}")
    if row["ownerNativeThreadId"] != row["observerNativeThreadId"]:
        raise StructuralError(f"D3 owner/observer thread mismatch: {envelope.location}")
    if row["invalidMetadataEventCount"] != 0 or row["counterOverflowCount"] != 0:
        raise StructuralError(f"invalid metadata or counter overflow: {envelope.location}")
    if row["beginReturnCode"] != 0 or row["endReturnCode"] != 0:
        raise StructuralError(f"D3 native begin/end failure: {envelope.location}")
    for field in (
        "pluginReady",
        "markerSeen",
        "metadataAbiValid",
        "ownerThreadMatched",
        "counterValid",
    ):
        if row[field] is not True:
            raise StructuralError(f"D3 validity gate failed ({field}): {envelope.location}")
    if row["invalidReasonCode"] != "":
        raise StructuralError(f"valid D3 row has invalidReasonCode: {envelope.location}")
    if row["stopwatchFrequency"] <= 0 or row["windowElapsedStopwatchTicks"] <= 0:
        raise StructuralError(f"invalid D3 stopwatch denominator: {envelope.location}")
    if row["windowEndStopwatchTicks"] < row["windowStartStopwatchTicks"]:
        raise StructuralError(f"D3 stopwatch regression: {envelope.location}")
    if row["windowEndStopwatchTicks"] - row["windowStartStopwatchTicks"] != row["windowElapsedStopwatchTicks"]:
        raise StructuralError(f"D3 elapsed-tick arithmetic mismatch: {envelope.location}")
    expected_rate = (
        row["managedAllocationBytes"]
        * row["stopwatchFrequency"]
        / row["windowElapsedStopwatchTicks"]
    )
    if row["managedAllocationBytes"] == 0:
        if rate != 0.0 or row["managedAllocationRateValid"] is not False:
            raise StructuralError(f"D3 zero policy mismatch: {envelope.location}")
    else:
        tolerance = max(1e-9, abs(expected_rate) * 1e-12)
        if row["managedAllocationRateValid"] is not True or rate <= 0.0 or abs(rate - expected_rate) > tolerance:
            raise StructuralError(f"D3 allocation-rate formula mismatch: {envelope.location}")

    scope = row["measurementScope"]
    if scope == "planner-initialization":
        if row["anonymousLaneId"] not in ALLOWED_LANES or (row["eventGroupIndex"], row["processOrdinal"], row["iterationIndex"]) != (-1, -1, -1):
            raise StructuralError(f"invalid planner-initialization D3 keys: {envelope.location}")
    elif scope == "event-group":
        if row["anonymousLaneId"] not in ALLOWED_LANES or not 0 <= row["eventGroupIndex"] < 24 or row["processOrdinal"] != -1 or row["iterationIndex"] != -1:
            raise StructuralError(f"invalid event-group D3 keys: {envelope.location}")
    elif scope == "empty-boundary":
        if row["anonymousLaneId"] != "" or row["identityBindingSha256"] != "" or row["eventGroupIndex"] != -1 or not 0 <= row["processOrdinal"] < 12 or not 0 <= row["iterationIndex"] < 1000:
            raise StructuralError(f"invalid empty-boundary D3 keys: {envelope.location}")
    elif scope == "instrument-self-test-positive-control":
        if row["eventGroupIndex"] != -1:
            raise StructuralError(f"invalid D3 self-test keys: {envelope.location}")
    else:
        raise StructuralError(f"unknown D3 measurement scope: {envelope.location}")


def validate_event_row(envelope: RowEnvelope) -> None:
    row = envelope.row
    require_no_retired_d3_fields(envelope)
    for field in (
        "recordId", "inputId", "superblockId", "designRegion", "anonymousLaneId",
        "identityBindingSha256", "changeTopology", "graphProfile", "contextStratumId",
        "eventGroupId", "phase", "d3WindowRecordId", "d3CounterId",
        "missingOrIneligibleReasonCode", "sourceRelativePath", "sourceSha256",
    ):
        require_string(row.get(field), f"{envelope.location}:{field}", allow_empty=(field == "missingOrIneligibleReasonCode"))
    for field in (
        "gridEdge", "agentCount", "changedCellCount", "sameTickAtomicPartitions",
        "eventGroupIndex", "cycleIndex", "gridContainsCalls", "gridIsWalkableCalls",
        "gridGetTraversalCostCalls", "gridAccessorCallsTotal", "repairOperationCount",
        "planOperationCount", "succeededPlanCount", "noPathPlanCount",
        "budgetExceededOperationCount",
    ):
        require_int(row.get(field), f"{envelope.location}:{field}", minimum=0)
    elapsed = require_number(row.get("eventGroupElapsedMilliseconds"), f"{envelope.location}:eventGroupElapsedMilliseconds", minimum=0.0)
    for field in ("d3CounterValid", "eligible", "finitePositiveElapsed", "counterValid"):
        require_bool(row.get(field), f"{envelope.location}:{field}")
    if not 0 <= row["eventGroupIndex"] < 24:
        raise StructuralError(f"invalid eventGroupIndex: {envelope.location}")
    if row["d3CounterId"] != D3_COUNTER_ID:
        raise StructuralError(f"event-group D3 counter mismatch: {envelope.location}")
    if row["gridAccessorCallsTotal"] != row["gridContainsCalls"] + row["gridIsWalkableCalls"] + row["gridGetTraversalCostCalls"]:
        raise StructuralError(f"D2 component total mismatch: {envelope.location}")
    if elapsed <= 0.0 or row["finitePositiveElapsed"] is not True:
        raise StructuralError(f"event-group elapsed validity mismatch: {envelope.location}")
    if row["d3CounterValid"] is not True or row["counterValid"] is not True:
        raise StructuralError(f"event-group D3 validity mismatch: {envelope.location}")
    if row["eligible"] is not True or row["budgetExceededOperationCount"] != 0 or row["missingOrIneligibleReasonCode"] != "":
        raise StructuralError(f"accepted event-group is ineligible: {envelope.location}")


def validate_empty_row(envelope: RowEnvelope) -> None:
    row = envelope.row
    require_no_retired_d3_fields(envelope)
    for field in ("recordId", "d3WindowRecordId", "d3CounterId", "sourceRelativePath", "sourceSha256"):
        require_string(row.get(field), f"{envelope.location}:{field}")
    for field in ("processOrdinal", "iterationIndex", "stopwatchStartTicks", "stopwatchEndTicks"):
        require_int(row.get(field), f"{envelope.location}:{field}", minimum=0)
    require_number(row.get("elapsedMilliseconds"), f"{envelope.location}:elapsedMilliseconds", minimum=0.0)
    require_bool(row.get("d3CounterValid"), f"{envelope.location}:d3CounterValid")
    require_bool(row.get("plannerInvoked"), f"{envelope.location}:plannerInvoked")
    if not 0 <= row["processOrdinal"] < 12 or not 0 <= row["iterationIndex"] < 1000:
        raise StructuralError(f"invalid empty-boundary keys: {envelope.location}")
    if row["stopwatchEndTicks"] < row["stopwatchStartTicks"]:
        raise StructuralError(f"empty-boundary stopwatch regression: {envelope.location}")
    if row["d3CounterId"] != D3_COUNTER_ID or row["d3CounterValid"] is not True:
        raise StructuralError(f"empty-boundary D3 identity/validity mismatch: {envelope.location}")
    if row["plannerInvoked"] is not False:
        raise StructuralError(f"planner invoked in empty-boundary row: {envelope.location}")


def validate_receipts_and_cardinality(
    raw_root: Path,
    tables: Mapping[str, Sequence[RowEnvelope]],
    identity_binding_sha256: str,
    profile: str,
) -> Dict[str, int]:
    event_by_parent: Dict[Path, List[RowEnvelope]] = {}
    d3_by_parent: Dict[Path, List[RowEnvelope]] = {}
    empty_by_parent: Dict[Path, List[RowEnvelope]] = {}
    state_by_parent: Dict[Path, List[RowEnvelope]] = {}
    resources_by_parent: Dict[Path, List[RowEnvelope]] = {}
    for envelope in tables["event-groups"]:
        event_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["d3-windows"]:
        d3_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["empty-boundary"]:
        empty_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["persistent-state"]:
        state_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["process-resources"]:
        resources_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)

    lane_receipts = sorted(raw_root.rglob("lane-receipt.v2.json"))
    empty_receipts = sorted(raw_root.rglob("empty-boundary-receipt.v2.json"))
    expected_lanes = 1 if profile == "synthetic-known-answer" else 972
    expected_empty = 1 if profile == "synthetic-known-answer" else 12
    if len(lane_receipts) != expected_lanes:
        raise StructuralError(
            f"{profile} requires {expected_lanes} lane receipt(s); found {len(lane_receipts)}"
        )
    if len(empty_receipts) != expected_empty:
        raise StructuralError(
            f"{profile} requires {expected_empty} empty-boundary receipt(s); found {len(empty_receipts)}"
        )

    seen_lane_keys: set[Tuple[str, str, str]] = set()
    for receipt_path in lane_receipts:
        receipt = read_json(receipt_path)
        parent = receipt_path.parent.resolve()
        if receipt.get("schema") != "gate14re-me-qualification-lane-receipt-v2" or receipt.get("status") != "COMPLETE_RAW_LANE":
            raise StructuralError(f"invalid lane receipt identity/status: {receipt_path}")
        lane = receipt.get("anonymousLaneId")
        if lane not in ALLOWED_LANES or parent.name != lane:
            raise StructuralError(f"lane receipt path/identity mismatch: {receipt_path}")
        if receipt.get("identityBindingSha256") != identity_binding_sha256:
            raise StructuralError(f"lane receipt identity-binding mismatch: {receipt_path}")
        if receipt.get("d3ContractSha256") != D3_CONTRACT_SHA256:
            raise StructuralError(f"lane receipt D3 contract mismatch: {receipt_path}")
        if receipt.get("completed") is not True or receipt.get("instrumentValid") is not True:
            raise StructuralError(f"lane receipt is not complete/instrument-valid: {receipt_path}")
        key = (
            require_string(receipt.get("inputId"), f"{receipt_path}:inputId"),
            require_string(receipt.get("superblockId"), f"{receipt_path}:superblockId"),
            str(lane),
        )
        if key in seen_lane_keys:
            raise StructuralError(f"duplicate lane receipt key: {key}")
        seen_lane_keys.add(key)
        events = event_by_parent.get(parent, [])
        d3_rows = d3_by_parent.get(parent, [])
        if len(events) != 24 or len(d3_rows) != 25:
            raise StructuralError(f"lane requires 24 event rows and 25 D3 windows: {parent}")
        if receipt.get("eventGroupRows") != 24 or receipt.get("d3WindowRows") != 25:
            raise StructuralError(f"lane receipt row-count mismatch: {receipt_path}")
        indices = {envelope.row.get("eventGroupIndex") for envelope in events}
        if indices != set(range(24)):
            raise StructuralError(f"lane event-group index coverage mismatch: {parent}")
        for envelope in events:
            row = envelope.row
            if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != key:
                raise StructuralError(f"event-group lane identity mismatch: {envelope.location}")
        init_rows = [e for e in d3_rows if e.row.get("measurementScope") == "planner-initialization"]
        event_d3_rows = [e for e in d3_rows if e.row.get("measurementScope") == "event-group"]
        if len(init_rows) != 1 or len(event_d3_rows) != 24:
            raise StructuralError(f"lane D3 scope cardinality mismatch: {parent}")
        if {e.row.get("eventGroupIndex") for e in event_d3_rows} != set(range(24)):
            raise StructuralError(f"lane D3 event index coverage mismatch: {parent}")
        for envelope in d3_rows:
            row = envelope.row
            if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != key:
                raise StructuralError(f"D3 lane identity mismatch: {envelope.location}")

        resources = resources_by_parent.get(parent, [])
        states = state_by_parent.get(parent, [])
        if len(resources) != 26:
            raise StructuralError(f"lane requires 26 process-resource rows: {parent}")
        if receipt.get("processResourceRows") != len(resources):
            raise StructuralError(f"lane receipt process-resource count mismatch: {receipt_path}")
        if receipt.get("persistentStateRows") != len(states):
            raise StructuralError(f"lane receipt persistent-state count mismatch: {receipt_path}")

        expected_points = set(MEASUREMENT_POINT_IDS)
        resource_points = [envelope.row.get("measurementPointId") for envelope in resources]
        if set(resource_points) != expected_points or len(resource_points) != len(set(resource_points)):
            raise StructuralError(f"lane process-resource measurement-point coverage mismatch: {parent}")
        state_points = {envelope.row.get("measurementPointId") for envelope in states}
        if state_points != expected_points:
            raise StructuralError(f"lane persistent-state measurement-point coverage mismatch: {parent}")

        expected_event_index = {
            "after-initialization": -1,
            "after-initial-queries": -1,
            **{f"after-event-group-{index}": index for index in range(24)},
        }
        for envelope in resources:
            row = envelope.row
            point = row.get("measurementPointId")
            if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != key:
                raise StructuralError(f"process-resource lane identity mismatch: {envelope.location}")
            if row.get("eventGroupIndex") != expected_event_index.get(point):
                raise StructuralError(f"process-resource measurement-point/index mismatch: {envelope.location}")
            require_int(row.get("processId"), f"{envelope.location}:processId", minimum=1)
            for field in (
                "privateMemoryBytes",
                "workingSetBytes",
                "managedMemoryBytes",
                "peakWorkingSetBytes",
            ):
                require_int(row.get(field), f"{envelope.location}:{field}", minimum=0)
            require_string(row.get("capturedAtUtc"), f"{envelope.location}:capturedAtUtc")

        state_groups: Dict[str, List[RowEnvelope]] = {}
        for envelope in states:
            row = envelope.row
            point = row.get("measurementPointId")
            if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != key:
                raise StructuralError(f"persistent-state lane identity mismatch: {envelope.location}")
            if row.get("eventGroupIndex") != expected_event_index.get(point):
                raise StructuralError(f"persistent-state measurement-point/index mismatch: {envelope.location}")
            if row.get("sizingFormulaId") != "gate14re-me-persistent-state-logical-capacity-v1":
                raise StructuralError(f"persistent-state sizing formula mismatch: {envelope.location}")
            if row.get("valid") is not True or row.get("invalidReasonCode") != "":
                raise StructuralError(f"invalid persistent-state row: {envelope.location}")
            require_string(row.get("persistentContainerName"), f"{envelope.location}:persistentContainerName")
            require_string(row.get("containerKind"), f"{envelope.location}:containerKind")
            for field in (
                "persistentContainerCapacity",
                "persistentContainerBytesPerElement",
                "persistentContainerCapacityBytes",
                "persistentPrimitiveArrayBytes",
                "persistentStateBytesTotal",
            ):
                require_int(row.get(field), f"{envelope.location}:{field}", minimum=0)
            state_groups.setdefault(str(point), []).append(envelope)
        for point, envelopes in state_groups.items():
            names = [str(item.row["persistentContainerName"]) for item in envelopes]
            if len(names) != len(set(names)):
                raise StructuralError(f"duplicate persistent-state component at {parent}:{point}")
            component_sum = sum(int(item.row["persistentContainerCapacityBytes"]) for item in envelopes)
            totals = {int(item.row["persistentStateBytesTotal"]) for item in envelopes}
            if totals != {component_sum}:
                raise StructuralError(f"persistent-state total mismatch at {parent}:{point}")

    seen_process_ordinals: set[int] = set()
    for receipt_path in empty_receipts:
        receipt = read_json(receipt_path)
        parent = receipt_path.parent.resolve()
        if receipt.get("schema") != "gate14re-me-empty-boundary-receipt-v2" or receipt.get("status") != "COMPLETE_EMPTY_BOUNDARY_RAW":
            raise StructuralError(f"invalid empty-boundary receipt identity/status: {receipt_path}")
        ordinal = require_int(receipt.get("processOrdinal"), f"{receipt_path}:processOrdinal", minimum=0)
        if ordinal in seen_process_ordinals or not 0 <= ordinal < 12:
            raise StructuralError(f"invalid/duplicate empty-boundary process ordinal: {receipt_path}")
        seen_process_ordinals.add(ordinal)
        if receipt.get("rawIterationRows") != 1000 or receipt.get("d3WindowRows") != 1000 or receipt.get("plannerInvoked") is not False or receipt.get("d3ContractSha256") != D3_CONTRACT_SHA256:
            raise StructuralError(f"empty-boundary receipt binding/count mismatch: {receipt_path}")
        rows = empty_by_parent.get(parent, [])
        d3_rows = d3_by_parent.get(parent, [])
        if len(rows) != 1000 or len(d3_rows) != 1000:
            raise StructuralError(f"empty-boundary requires 1000 rows and 1000 D3 windows: {parent}")
        if {e.row.get("iterationIndex") for e in rows} != set(range(1000)):
            raise StructuralError(f"empty-boundary iteration coverage mismatch: {parent}")
        if {e.row.get("iterationIndex") for e in d3_rows} != set(range(1000)):
            raise StructuralError(f"empty-boundary D3 iteration coverage mismatch: {parent}")
        if any(e.row.get("processOrdinal") != ordinal for e in rows + d3_rows):
            raise StructuralError(f"empty-boundary process identity mismatch: {parent}")

    return {
        "laneReceipts": len(lane_receipts),
        "emptyBoundaryReceipts": len(empty_receipts),
        "processResourceRows": len(tables["process-resources"]),
        "persistentStateMeasurementPointLanePairs": sum(
            len({envelope.row.get("measurementPointId") for envelope in rows})
            for rows in state_by_parent.values()
        ),
    }


def validate_terminal_control_plane(
    raw_root: Path,
    project_root: Path,
    output_schema_sha256: str,
    identity_binding_sha256: str,
    profile: str,
) -> Dict[str, int]:
    if profile == "qualification-full":
        expected = {
            "superblocks": 162,
            "lanes": 972,
            "oracle": 162,
            "empty": 12,
            "processes": 1147,
        }
    else:
        expected = {
            "superblocks": 1,
            "lanes": 1,
            "oracle": 1,
            "empty": 1,
            "processes": 4,
        }

    accepted_paths = sorted(raw_root.rglob("accepted-superblock-receipt.v1.json"))
    if len(accepted_paths) != expected["superblocks"]:
        raise StructuralError(
            f"{profile} requires {expected['superblocks']} accepted-superblock receipt(s); "
            f"found {len(accepted_paths)}"
        )
    accepted_ids: set[str] = set()
    for path in accepted_paths:
        receipt = read_json(path)
        if (
            receipt.get("schema") != "gate14re-me-accepted-superblock-receipt-v1"
            or receipt.get("status") != "ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK"
        ):
            raise StructuralError(f"invalid accepted-superblock receipt identity/status: {path}")
        superblock_id = require_string(
            receipt.get("plannedSuperblockId"), f"{path}:plannedSuperblockId"
        )
        if superblock_id in accepted_ids or path.parent.name != superblock_id:
            raise StructuralError(f"duplicate or path-mismatched accepted superblock: {path}")
        accepted_ids.add(superblock_id)
        if receipt.get("instanceId") != superblock_id:
            raise StructuralError(f"accepted-superblock planned/instance identity mismatch: {path}")
        if receipt.get("isReplacement") is not False:
            raise StructuralError(f"accepted superblock is marked as a replacement: {path}")
        expected_lane_count = 6 if profile == "qualification-full" else 1
        if receipt.get("acceptedAnonymousLanes") != expected_lane_count:
            raise StructuralError(f"accepted-superblock lane count mismatch: {path}")
        if profile == "synthetic-known-answer" and receipt.get("syntheticKnownAnswer") is not True:
            raise StructuralError(f"synthetic accepted-superblock marker missing: {path}")
        lane_receipts = list(path.parent.glob("ALG-*/lane-receipt.v2.json"))
        if len(lane_receipts) != expected_lane_count:
            raise StructuralError(f"accepted-superblock receipt does not close its lane set: {path}")

    oracle_paths = sorted(raw_root.rglob("oracle-pass-receipt.v1.json"))
    if len(oracle_paths) != expected["oracle"]:
        raise StructuralError(
            f"{profile} requires {expected['oracle']} oracle receipt(s); found {len(oracle_paths)}"
        )
    oracle_ids: set[str] = set()
    for path in oracle_paths:
        receipt = read_json(path)
        if (
            receipt.get("schema") != "gate14re-me-oracle-pass-receipt-v1"
            or receipt.get("status") != "PASS_ALGORITHM_NEUTRAL_GEOMETRY"
        ):
            raise StructuralError(f"invalid oracle receipt identity/status: {path}")
        superblock_id = require_string(receipt.get("superblockId"), f"{path}:superblockId")
        if superblock_id in oracle_ids or path.parent.name != superblock_id:
            raise StructuralError(f"duplicate or path-mismatched oracle receipt: {path}")
        oracle_ids.add(superblock_id)
    if oracle_ids != accepted_ids:
        raise StructuralError("oracle and accepted-superblock identity sets differ")

    instrument_path = raw_root / "instruments/csharp/instrument-csharp-receipt.v2.json"
    instrument = read_json(instrument_path)
    if (
        instrument.get("schema") != "gate14re-me-instrument-qualification-receipt-v2"
        or instrument.get("status") != "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING"
    ):
        raise StructuralError("invalid instrument C# receipt identity/status")
    for field in (
        "gridReadProxyKnownAnswerPassed",
        "gridReadProxySemanticInvariancePassed",
        "d3V31PluginReadinessPassed",
        "d3V31OneMiBPositiveControlPassed",
        "d3V31RateFormulaPassed",
        "persistentStateSizerSyntheticFixturePassed",
        "clockMonotonicityPassed",
    ):
        if instrument.get(field) is not True:
            raise StructuralError(f"instrument C# receipt gate failed: {field}")
    if instrument.get("d3ContractSha256") != D3_CONTRACT_SHA256:
        raise StructuralError("instrument C# receipt D3 contract mismatch")

    launch_path = raw_root / "_control/launch-receipt.v2.json"
    launch = read_json(launch_path)
    if (
        launch.get("schema") != "gate14re-me-qualification-launch-receipt-v2"
        or launch.get("status") != "AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED"
    ):
        raise StructuralError("invalid qualification launch receipt identity/status")
    if launch.get("outputSchemaSha256") != output_schema_sha256:
        raise StructuralError("launch receipt output-schema hash mismatch")
    if launch.get("d3ContractSha256") != D3_CONTRACT_SHA256:
        raise StructuralError("launch receipt D3 contract hash mismatch")
    if launch.get("identityBindingSha256") != identity_binding_sha256:
        raise StructuralError("launch receipt sealed identity hash mismatch")
    if launch.get("structuralToolSha256") != sha256_file(Path(__file__).resolve()):
        raise StructuralError("launch receipt structural-tool hash mismatch")

    acquisition_path = raw_root / "_control/acquisition-complete.v2.json"
    acquisition = read_json(acquisition_path)
    if (
        acquisition.get("schema") != "gate14re-me-qualification-acquisition-complete-v2"
        or acquisition.get("status") != "QUALIFICATION_RAW_STRUCTURAL_VALIDATION_PENDING"
    ):
        raise StructuralError("invalid acquisition-complete receipt identity/status")
    expected_acquisition = {
        "plannedSuperblocks": expected["superblocks"],
        "acceptedSuperblocks": expected["superblocks"],
        "plannedAlgorithmLanes": expected["lanes"],
        "acceptedAlgorithmLanes": expected["lanes"],
        "unityProcessCount": expected["processes"],
        "wholeSuperblockReplacements": 0,
    }
    for field, value in expected_acquisition.items():
        if acquisition.get(field) != value:
            raise StructuralError(f"acquisition-complete terminal count mismatch: {field}")
    for field in ("formalCollectionAuthorized", "formalAnalysisAuthorized", "rankingOrWinnerComputed"):
        if acquisition.get(field) is not False:
            raise StructuralError(f"acquisition-complete authorization boundary mismatch: {field}")

    for table_name in ("replacement-ledger.raw.v1.jsonl", "failures-and-voids.raw.v1.jsonl"):
        path = raw_root / "_control" / table_name
        if list(read_jsonl(path)):
            raise StructuralError(f"terminal control ledger must be empty: {table_name}")

    ledger_path = raw_root / "_control/process-ledger.raw.v2.jsonl"
    ledger_rows = [row for _, row in read_jsonl(ledger_path)]
    if len(ledger_rows) != expected["processes"]:
        raise StructuralError(
            f"{profile} requires {expected['processes']} process-ledger rows; found {len(ledger_rows)}"
        )
    expected_modes = (
        ["instrument-self-test"]
        + ["oracle"] * expected["oracle"]
        + ["empty-boundary"] * expected["empty"]
        + ["lane"] * expected["lanes"]
    )
    identity_paths = sorted(raw_root.rglob("process-*.identity.v2.json"))
    if len(identity_paths) != expected["processes"]:
        raise StructuralError(
            f"{profile} requires {expected['processes']} process-identity receipts; "
            f"found {len(identity_paths)}"
        )
    identity_resolved = {path.resolve() for path in identity_paths}
    linked_identity_paths: set[Path] = set()
    seen_process_composites: set[Tuple[int, str]] = set()
    for ordinal, (ledger, expected_mode) in enumerate(zip(ledger_rows, expected_modes)):
        location = f"{ledger_path}:{ordinal + 1}"
        if ledger.get("schema") != "gate14re-me-process-ledger-row-v2":
            raise StructuralError(f"process-ledger schema mismatch: {location}")
        if ledger.get("ordinal") != ordinal or ledger.get("mode") != expected_mode:
            raise StructuralError(f"process-ledger ordinal/mode sequence mismatch: {location}")
        if ledger.get("state") != "EXITED_ZERO_TRUSTED_IDENTITY" or ledger.get("exitCode") != 0:
            raise StructuralError(f"process-ledger exit state mismatch: {location}")
        pid = require_int(ledger.get("processId"), f"{location}:processId", minimum=1)
        creation = require_string(ledger.get("creationTimeUtc"), f"{location}:creationTimeUtc")
        composite = (pid, creation)
        if composite in seen_process_composites:
            raise StructuralError(f"duplicate PID/creation-time composite in ledger: {location}")
        seen_process_composites.add(composite)
        require_string(ledger.get("exitedAtUtc"), f"{location}:exitedAtUtc")
        identity_relative = require_string(
            ledger.get("identityReceiptRelativePath"),
            f"{location}:identityReceiptRelativePath",
        )
        identity_sha = require_string(
            ledger.get("identityReceiptSha256"),
            f"{location}:identityReceiptSha256",
        )
        identity_path = resolve_project_file(identity_relative, project_root, "process identity receipt")
        if not within(identity_path, raw_root) or identity_path not in identity_resolved:
            raise StructuralError(f"process identity receipt is outside or absent from raw root: {location}")
        if identity_path in linked_identity_paths:
            raise StructuralError(f"process identity receipt linked more than once: {identity_path}")
        linked_identity_paths.add(identity_path)
        require_hash(identity_path, identity_sha, f"process identity receipt at {location}")
        identity = read_json(identity_path)
        if (
            identity.get("schema") != "gate14re-me-qualified-unity-process-identity-receipt-v2"
            or identity.get("status")
            != "PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT"
        ):
            raise StructuralError(f"invalid process identity receipt identity/status: {identity_path}")
        if (
            identity.get("ordinal") != ordinal
            or identity.get("mode") != expected_mode
            or identity.get("processId") != pid
            or identity.get("creationTimeUtc") != creation
            or identity.get("exitCode") != 0
            or identity.get("executeMethod") != RUNNER_METHOD
        ):
            raise StructuralError(f"process identity/ledger composite mismatch: {identity_path}")
        for field in ("executablePath", "exactCommandLine", "outputRelativePath"):
            require_string(identity.get(field), f"{identity_path}:{field}")
        if (
            identity.get("naturalExit") is not True
            or identity.get("signalOrForcedTerminationSent") is not False
            or identity.get("retryPerformed") is not False
        ):
            raise StructuralError(f"process identity natural-exit policy mismatch: {identity_path}")
        if identity.get("trustedIdentityRuleSha256") != TRUSTED_IDENTITY_RULE_SHA256:
            raise StructuralError(f"process identity trusted-rule hash mismatch: {identity_path}")
        if identity.get("timestampComparatorSha256") != TIMESTAMP_COMPARATOR_SHA256:
            raise StructuralError(f"process identity timestamp-comparator hash mismatch: {identity_path}")
        for field in ("prelaunchFingerprint", "liveConcurrentFingerprint", "postExitFingerprint"):
            if not isinstance(identity.get(field), dict):
                raise StructuralError(f"process identity phase fingerprint missing: {identity_path}:{field}")
    if linked_identity_paths != identity_resolved:
        raise StructuralError("process identity receipt set is not exactly closed by the process ledger")

    return {
        "acceptedSuperblockReceipts": len(accepted_paths),
        "oraclePassReceipts": len(oracle_paths),
        "instrumentCsharpReceipts": 1,
        "processLedgerRows": len(ledger_rows),
        "processIdentityReceipts": len(identity_paths),
        "supervisorFinalProcessOrdinal": len(ledger_rows),
    }


def validate_d3_joins(tables: Mapping[str, Sequence[RowEnvelope]]) -> Dict[str, int]:
    d3_by_id: Dict[str, RowEnvelope] = {}
    for envelope in tables["d3-windows"]:
        validate_d3_row(envelope)
        d3_by_id[str(envelope.row["recordId"])] = envelope
    referenced: Dict[str, str] = {}
    event_joins = 0
    empty_joins = 0
    for envelope in tables["event-groups"]:
        validate_event_row(envelope)
        record_id = str(envelope.row["d3WindowRecordId"])
        if record_id in referenced:
            raise StructuralError(
                f"D3 window joined more than once: {record_id}; first {referenced[record_id]}"
            )
        target = d3_by_id.get(record_id)
        if target is None:
            raise StructuralError(f"event-group D3 join target missing: {envelope.location}")
        left = envelope.row
        right = target.row
        if right.get("measurementScope") != "event-group" or (
            left.get("inputId"), left.get("superblockId"), left.get("anonymousLaneId"), left.get("eventGroupIndex")
        ) != (
            right.get("inputId"), right.get("superblockId"), right.get("anonymousLaneId"), right.get("eventGroupIndex")
        ):
            raise StructuralError(f"event-group D3 join key mismatch: {envelope.location}")
        referenced[record_id] = envelope.location
        event_joins += 1
    for envelope in tables["empty-boundary"]:
        validate_empty_row(envelope)
        record_id = str(envelope.row["d3WindowRecordId"])
        if record_id in referenced:
            raise StructuralError(
                f"D3 window joined more than once: {record_id}; first {referenced[record_id]}"
            )
        target = d3_by_id.get(record_id)
        if target is None:
            raise StructuralError(f"empty-boundary D3 join target missing: {envelope.location}")
        left = envelope.row
        right = target.row
        if right.get("measurementScope") != "empty-boundary" or (
            left.get("processOrdinal"), left.get("iterationIndex")
        ) != (right.get("processOrdinal"), right.get("iterationIndex")):
            raise StructuralError(f"empty-boundary D3 join key mismatch: {envelope.location}")
        referenced[record_id] = envelope.location
        empty_joins += 1
    for record_id, envelope in d3_by_id.items():
        if envelope.row.get("measurementScope") in {"event-group", "empty-boundary"} and record_id not in referenced:
            raise StructuralError(
                f"unreferenced join-required D3 window: {envelope.location}"
            )
    return {"eventGroupD3Joins": event_joins, "emptyBoundaryD3Joins": empty_joins}


def validate_operations_semantics(tables: Mapping[str, Sequence[RowEnvelope]]) -> None:
    for envelope in tables["operations"]:
        value = envelope.row.get("managedAllocatedBytes")
        require_int(value, f"{envelope.location}:managedAllocatedBytes", minimum=0)
        if envelope.row.get("nativeMetricsSemanticsId") in (None, ""):
            raise StructuralError(
                f"operations diagnostic semantics identity missing: {envelope.location}"
            )


def validate_raw_package(
    *,
    project_root: Path,
    raw_root: Path,
    output_schema_path: Path,
    output_schema_sha256: str,
    d3_contract_path: Path,
    d3_contract_sha256: str,
    identity_binding_sha256: str,
    profile: str,
) -> Dict[str, Any]:
    project_root = project_root.resolve()
    raw_root = raw_root.resolve()
    if not raw_root.is_dir() or not within(raw_root, project_root):
        raise StructuralError("raw root is missing or outside the project")
    if profile == "synthetic-known-answer":
        permitted = (
            project_root
            / "Research/Verification/Gate14Re-ME/"
            "qualification-execution-terminal-chain-corrigendum-attempt-002"
        ).resolve()
        if not within(raw_root, permitted):
            raise StructuralError("synthetic profile raw root is outside the authorized verification attempt")
    require_hash(d3_contract_path, d3_contract_sha256, "D3 contract")
    if d3_contract_sha256 != D3_CONTRACT_SHA256:
        raise StructuralError("D3 contract hash is not the qualified D3-v3.1 hash")
    d3_contract = read_json(d3_contract_path)
    if d3_contract.get("semanticVersion") != D3_SEMANTIC_VERSION and d3_contract.get("version") != D3_SEMANTIC_VERSION:
        contract_text = canonical_json(d3_contract)
        if D3_SEMANTIC_VERSION not in contract_text or D3_COUNTER_ID not in contract_text:
            raise StructuralError("qualified D3 contract identity/version mismatch")
    specs = load_specs(output_schema_path, output_schema_sha256)
    tables = load_tables(raw_root, project_root, specs, identity_binding_sha256)
    receipt_counts = validate_receipts_and_cardinality(
        raw_root, tables, identity_binding_sha256, profile
    )
    join_counts = validate_d3_joins(tables)
    validate_operations_semantics(tables)
    terminal_counts = validate_terminal_control_plane(
        raw_root,
        project_root,
        output_schema_sha256,
        identity_binding_sha256,
        profile,
    )
    if profile == "qualification-full":
        expected_counts = {
            "eventGroupRows": (len(tables["event-groups"]), 23328),
            "eventGroupD3Joins": (join_counts["eventGroupD3Joins"], 23328),
            "emptyBoundaryD3Joins": (join_counts["emptyBoundaryD3Joins"], 12000),
            "d3WindowRows": (len(tables["d3-windows"]), 36301),
            "processResourceRows": (receipt_counts["processResourceRows"], 25272),
            "persistentStateMeasurementPointLanePairs": (
                receipt_counts["persistentStateMeasurementPointLanePairs"],
                25272,
            ),
        }
    else:
        expected_counts = {
            "eventGroupRows": (len(tables["event-groups"]), 24),
            "eventGroupD3Joins": (join_counts["eventGroupD3Joins"], 24),
            "emptyBoundaryD3Joins": (join_counts["emptyBoundaryD3Joins"], 1000),
            "d3WindowRows": (len(tables["d3-windows"]), 1026),
            "processResourceRows": (receipt_counts["processResourceRows"], 26),
            "persistentStateMeasurementPointLanePairs": (
                receipt_counts["persistentStateMeasurementPointLanePairs"],
                26,
            ),
        }
    for label, (actual, expected) in expected_counts.items():
        if actual != expected:
            raise StructuralError(
                f"{profile} terminal cardinality mismatch for {label}: "
                f"expected {expected}; actual {actual}"
            )
    return {
        "schema": VALIDATION_SCHEMA,
        "studyId": "Gate14Re-ME",
        "status": "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE",
        "profile": profile,
        "outputSchemaSha256": output_schema_sha256,
        "d3ContractSha256": d3_contract_sha256,
        "identityBindingSha256": identity_binding_sha256,
        "tableRows": {table_id: len(tables[table_id]) for table_id in RAW_TABLE_ORDER},
        **receipt_counts,
        **join_counts,
        **terminal_counts,
        "terminalControlPlaneClosed": True,
        "supervisorFinalProcessOrdinalAsserted": True,
        "d3WindowRecordIdsUnique": True,
        "d3JoinsOneToOneAndComplete": True,
        "retiredSnapshotFieldsAbsent": True,
        "operationManagedAllocatedBytesTreatedAsD3": False,
        "crossAlgorithmEffectsComputed": False,
        "rankingOrWinnerComputed": False,
        "qualificationReusedForFormalInference": False,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--project-root", required=True)
    validate.add_argument("--raw-root", "--measured-root", dest="raw_root", required=True)
    validate.add_argument("--output-schema", required=True)
    validate.add_argument("--output-schema-sha256", required=True)
    validate.add_argument("--d3-contract", required=True)
    validate.add_argument("--d3-contract-sha256", required=True)
    validate.add_argument("--identity-binding-sha256", required=True)
    validate.add_argument(
        "--profile",
        choices=("qualification-full", "synthetic-known-answer"),
        default="qualification-full",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        project_root = Path(args.project_root).resolve()
        result = validate_raw_package(
            project_root=project_root,
            raw_root=Path(args.raw_root),
            output_schema_path=resolve_project_file(args.output_schema, project_root, "output schema"),
            output_schema_sha256=args.output_schema_sha256,
            d3_contract_path=resolve_project_file(args.d3_contract, project_root, "D3 contract"),
            d3_contract_sha256=args.d3_contract_sha256,
            identity_binding_sha256=args.identity_binding_sha256,
            profile=args.profile,
        )
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except StructuralError as exc:
        print(
            json.dumps(
                {"schema": VALIDATION_SCHEMA, "status": "FAIL_CLOSED", "reason": str(exc)},
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

