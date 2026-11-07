#!/usr/bin/env python3
"""Fail-closed structural validator for Gate14Re-ME output schema v2.

This tool validates raw identities, scalar types, source bindings, D3-v3.1
window semantics, fixed per-lane/per-process cardinalities, and one-to-one D3
joins.  It never aggregates endpoints, compares algorithms, ranks algorithms,
or adjudicates a winner.
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


TOOL_SCHEMA = "gate14re-me-qualification-structural-tool-v2"
VALIDATION_SCHEMA = "gate14re-me-qualification-structural-validation-v2"
OUTPUT_SCHEMA_ID = "gate14re-me-load-qualification-output-schema-v2"
EXPECTED_SCHEMA_SHA256 = "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb"
D3_COUNTER_ID = "GC.Alloc-Begin-owner-thread-window-v3.1"
D3_SEMANTIC_VERSION = "3.1"
D3_CONTRACT_RELATIVE_PATH = (
    "Research/Gate14Re-ME/Execution/v3/"
    "d3-cumulative-managed-allocation-contract.qualified.v1.json"
)
D3_CONTRACT_SHA256 = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"
ALLOWED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
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
        raise StructuralError("output-schema hash is not the frozen schema-v2 hash")
    schema = read_json(schema_path)
    if schema.get("schema") != OUTPUT_SCHEMA_ID or schema.get("version") != 2:
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
        raise StructuralError("raw-table order or membership differs from schema v2")
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
    for envelope in tables["event-groups"]:
        event_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["d3-windows"]:
        d3_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)
    for envelope in tables["empty-boundary"]:
        empty_by_parent.setdefault(envelope.path.parent.resolve(), []).append(envelope)

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
            "schema-v2-tooling-bridge-attempt-001"
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
    if profile == "qualification-full":
        if len(tables["event-groups"]) != 23328:
            raise StructuralError("full qualification event-group cardinality mismatch")
        if join_counts["emptyBoundaryD3Joins"] != 12000:
            raise StructuralError("full qualification empty-boundary cardinality mismatch")
    return {
        "schema": VALIDATION_SCHEMA,
        "studyId": "Gate14Re-ME",
        "status": "PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE",
        "profile": profile,
        "outputSchemaSha256": output_schema_sha256,
        "d3ContractSha256": d3_contract_sha256,
        "identityBindingSha256": identity_binding_sha256,
        "tableRows": {table_id: len(tables[table_id]) for table_id in RAW_TABLE_ORDER},
        **receipt_counts,
        **join_counts,
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
