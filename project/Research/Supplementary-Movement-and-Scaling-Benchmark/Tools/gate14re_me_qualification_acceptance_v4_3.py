#!/usr/bin/env python3
"""Gate14Re-ME independent read-only streaming acceptance v4.2.

This implementation is deliberately independent from acquisition.  It consumes a
   sealed acquisition root read-only and writes only to a new acceptance output root.
   It independently validates the control plane, replays the acquisition seal, keeps
   complete raw JSONL as the immutable canonical record, and creates one typed
   Parquet view per raw table.

The implementation is bounded-memory:
* sealed files are hashed exactly once;
* the first raw pass discovers columns and scalar types without retaining rows;
* the second raw pass writes Parquet in bounded batches and computes an ordered
  canonical digest;
* the Parquet pass recomputes the same digest in bounded batches;
* no whole-table row list or record-id array is materialized.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import time
import traceback
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, MutableMapping, Sequence, Tuple


TOOL_SCHEMA = "gate14re-me-independent-streaming-acceptance-tool-v4.2"
RESULT_SCHEMA = "gate14re-me-independent-streaming-acceptance-result-v4.2"
MANIFEST_SCHEMA = "gate14re-me-independent-streaming-acceptance-manifest-v4.2"
TABLE_SCHEMA = "gate14re-me-independent-streaming-acceptance-table-v4.2"
FAILURE_SCHEMA = "gate14re-me-independent-streaming-acceptance-failure-v4.2"
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
RESERVED_PROVENANCE_FIELDS = ("_rawSourceRelativePath", "_rawSourceLine")
ALLOWED_TYPES = {"string", "bool", "int64", "float64"}


class DeliveryError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def oracle_batch_index_v41(ordinal: int) -> int:
    if ordinal < 0 or ordinal >= 126:
        raise DeliveryError(f"oracle batch assignment requires schedule ordinal 0..125: {ordinal}")
    if ordinal < 108:
        grid_index = ordinal // 36
        agent_index = (ordinal % 36) // 12
        changed_cell_index = (ordinal % 12) // 3
        replicate_index = ordinal % 3
        return (grid_index + agent_index + changed_cell_index + 2 * replicate_index) % 6
    return (ordinal - 108) % 6


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    )


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
    path.write_text(text + "\n", encoding="utf-8", newline="\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(8 * 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def require_file(path: Path, expected_sha: str, label: str) -> None:
    if not path.is_file():
        raise DeliveryError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected_sha:
        raise DeliveryError(
            f"{label} SHA-256 mismatch: expected={expected_sha}; actual={actual}; path={path}"
        )


def read_json(path: Path, label: str) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise DeliveryError(f"invalid {label} JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DeliveryError(f"{label} must be a JSON object: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise DeliveryError(f"JSON object required: {path}:{line_number}")
                yield line_number, value
    except DeliveryError:
        raise
    except Exception as exc:
        raise DeliveryError(f"invalid JSONL: {path}: {exc}") from exc


def relative_posix(path: Path, root: Path) -> str:
    try:
        return path.resolve(strict=True).relative_to(root.resolve(strict=True)).as_posix()
    except Exception as exc:
        raise DeliveryError(f"path escapes expected root: path={path}; root={root}") from exc


def scalar_type(value: Any, location: str) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        if value < -(2**63) or value > 2**63 - 1:
            raise DeliveryError(f"integer exceeds signed int64: {location}")
        return "int64"
    if isinstance(value, float):
        if not math.isfinite(value):
            raise DeliveryError(f"non-finite float prohibited: {location}")
        return "float64"
    if isinstance(value, str):
        return "string"
    raise DeliveryError(f"non-scalar JSON value prohibited: {location}: {type(value).__name__}")


def load_specs(schema_path: Path) -> Dict[str, Dict[str, Any]]:
    schema = read_json(schema_path, "output schema")
    if (
        schema.get("schema") != "gate14re-me-load-qualification-output-schema-v4.1"
        or schema.get("status") != "FROZEN_BOUNDED_WINDOW_STREAMING_ESSENTIAL_ACCEPTANCE_ORACLE_CACHE_V4_1"
    ):
        raise DeliveryError("acceptance requires the exact bounded-load oracle-cache output schema v4.1")
    specs: Dict[str, Dict[str, Any]] = {}
    for item in schema.get("rawTables", []):
        if not isinstance(item, dict):
            raise DeliveryError("raw table specification must be an object")
        table_id = item.get("tableId")
        if not isinstance(table_id, str) or table_id in specs:
            raise DeliveryError(f"invalid or duplicate table specification: {table_id}")
        specs[table_id] = item
    if tuple(specs) != RAW_TABLE_ORDER:
        raise DeliveryError("raw table order/membership mismatch")
    return specs


def replay_sealed_inventory(
    raw_root: Path,
    manifest_path: Path,
) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Any]]:
    started = time.perf_counter()
    entries: Dict[str, Dict[str, Any]] = {}
    total_bytes = 0
    manifest = read_json(manifest_path, "acquisition freeze manifest")
    if (
        manifest.get("schema") != "gate14re-me-qualification-acquisition-freeze-manifest-v4.1"
        or manifest.get("status") != "SEALED_ACQUISITION_RAW_ACCEPTANCE_PENDING"
    ):
        raise DeliveryError("unexpected acquisition freeze manifest identity/status")
    rows = manifest.get("artifacts")
    if not isinstance(rows, list) or manifest.get("artifactCount") != len(rows):
        raise DeliveryError("acquisition freeze manifest artifact cardinality mismatch")
    for line_number, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            raise DeliveryError(f"malformed acquisition freeze artifact: {line_number}")
        relative = row.get("relativePath")
        expected_sha = row.get("sha256")
        expected_bytes = row.get("lengthBytes")
        if not isinstance(relative, str) or not isinstance(expected_sha, str) or not isinstance(expected_bytes, int):
            raise DeliveryError(f"malformed seal manifest row: {manifest_path}:{line_number}")
        if relative in entries:
            raise DeliveryError(f"duplicate seal manifest path: {relative}")
        path = raw_root / Path(relative)
        if not path.is_file():
            raise DeliveryError(f"sealed file missing: {relative}")
        actual_bytes = path.stat().st_size
        if actual_bytes != expected_bytes:
            raise DeliveryError(
                f"sealed file byte mismatch: {relative}: expected={expected_bytes}; actual={actual_bytes}"
            )
        actual_sha = sha256_file(path)
        if actual_sha != expected_sha:
            raise DeliveryError(
                f"sealed file hash mismatch: {relative}: expected={expected_sha}; actual={actual_sha}"
            )
        entry = {
            "bytes": expected_bytes,
            "sha256": expected_sha,
        }
        entries[relative] = entry
        total_bytes += expected_bytes

    current_paths = {
        path.relative_to(raw_root).as_posix()
        for path in raw_root.rglob("*")
        if path.is_file()
    }
    allowed_post_manifest = {
        manifest_path.resolve().relative_to(raw_root.resolve()).as_posix(),
        "_control/acquisition-terminal-receipt.v4_1.json",
    }
    expected_paths = set(entries) | allowed_post_manifest
    if current_paths != expected_paths:
        missing = sorted(expected_paths - current_paths)[:20]
        extra = sorted(current_paths - expected_paths)[:20]
        raise DeliveryError(f"sealed inventory membership mismatch: missing={missing}; extra={extra}")
    return entries, {
        "files": len(entries),
        "bytes": total_bytes,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "allCurrentHashesMatchSeal": True,
    }


def validate_control_plane(
    project_root: Path,
    raw_root: Path,
    schedule_path: Path,
    schedule_sha256: str,
    seal_manifest_sha256: str,
    sealed_entries: Mapping[str, Mapping[str, Any]],
) -> Dict[str, Any]:
    started = time.perf_counter()
    require_file(schedule_path, schedule_sha256, "qualification schedule")
    schedule_rows = [row for _, row in read_jsonl(schedule_path)]
    if len(schedule_rows) != 126:
        raise DeliveryError(f"schedule row count mismatch: {len(schedule_rows)}")
    scheduled_ids: set[str] = set()
    schedule_by_id: Dict[str, Dict[str, Any]] = {}
    for ordinal, row in enumerate(schedule_rows):
        if (
            row.get("schema") != "gate14re-me-load-qualification-schedule-row-v4"
            or row.get("ordinal") != ordinal
            or row.get("replacement") is not None
        ):
            raise DeliveryError(f"schedule schema/ordinal/replacement mismatch at {ordinal}")
        superblock_id = row.get("superblockId")
        lanes = row.get("algorithmOrder")
        if not isinstance(superblock_id, str) or superblock_id in scheduled_ids:
            raise DeliveryError(f"invalid or duplicate scheduled superblock at {ordinal}")
        if not isinstance(lanes, list) or len(lanes) != 6:
            raise DeliveryError(f"schedule lane cardinality mismatch at {ordinal}")
        scheduled_ids.add(superblock_id)
        schedule_by_id[superblock_id] = row

    launch = read_json(raw_root / "_control/launch-receipt.v2.json", "launch receipt")
    if (
        launch.get("status") != "AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED"
        or launch.get("runnerMethod") != "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run"
        or launch.get("plannedSuperblocks") != 126
        or launch.get("plannedAlgorithmLanes") != 756
        or launch.get("plannedOracleBatches") != 6
        or launch.get("plannedFreshProcesses") != 775
        or launch.get("scheduleSha256") != schedule_sha256
    ):
        raise DeliveryError("launch receipt v4 acquisition binding mismatch")

    acquisition = read_json(raw_root / "_control/acquisition-complete.v4_1.json", "acquisition receipt")
    expected_acquisition = {
        "status": "ACQUISITION_COMPLETE_RAW_ACCEPTANCE_PENDING",
        "plannedSuperblocks": 126,
        "acceptedSuperblocks": 126,
        "plannedAlgorithmLanes": 756,
        "acceptedAlgorithmLanes": 756,
        "plannedOracleBatches": 6,
        "completedOracleBatches": 6,
        "algorithmNeutralOracleCaches": 126,
        "laneReferenceOracleEvaluations": 0,
        "unityProcessCount": 775,
        "wholeSuperblockReplacements": 0,
        "qualificationTerminalPass": False,
        "independentReadOnlyOfflineAcceptanceRequired": True,
    }
    for field, expected in expected_acquisition.items():
        if acquisition.get(field) != expected:
            raise DeliveryError(f"acquisition receipt mismatch: {field}")

    pending = read_json(raw_root / "_control/acceptance-pending.v4_1.json", "acceptance-pending receipt")
    if (
        pending.get("status") != "SEALED_RAW_REQUIRES_NEW_READ_ONLY_OFFLINE_ACCEPTANCE_ATTEMPT"
        or pending.get("sourceMutationPermitted") is not False
        or pending.get("qualificationTerminalPass") is not False
        or pending.get("typedParquetFullRoundTripRequired") is not True
    ):
        raise DeliveryError("acceptance-pending receipt mismatch")

    terminal = read_json(
        raw_root / "_control/acquisition-terminal-receipt.v4_1.json",
        "acquisition terminal receipt",
    )
    if (
        terminal.get("status") != "PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING"
        or terminal.get("acquisitionFreezeManifestSha256") != seal_manifest_sha256
        or terminal.get("completedFreshProcesses") != 775
        or terminal.get("qualificationTerminalPass") is not False
    ):
        raise DeliveryError("acquisition terminal receipt mismatch")

    if (raw_root / "_control/failure-receipt.v2.json").exists():
        raise DeliveryError("acquisition failure receipt exists")
    for ledger_name in (
        "_control/failures-and-voids.raw.v1.jsonl",
        "_control/replacement-ledger.raw.v1.jsonl",
    ):
        if any(True for _ in read_jsonl(raw_root / ledger_name)):
            raise DeliveryError(f"nonempty prohibited ledger: {ledger_name}")

    process_rows = [row for _, row in read_jsonl(raw_root / "_control/process-ledger.raw.v2.jsonl")]
    expected_modes = ["instrument-self-test"] + ["oracle-batch"] * 6 + ["empty-boundary"] * 12 + ["lane"] * 756
    if len(process_rows) != len(expected_modes):
        raise DeliveryError(f"process ledger cardinality mismatch: {len(process_rows)}")
    for ordinal, (row, mode) in enumerate(zip(process_rows, expected_modes)):
        if (
            row.get("schema") != "gate14re-me-process-ledger-row-v2"
            or row.get("ordinal") != ordinal
            or row.get("mode") != mode
            or row.get("state") != "EXITED_ZERO_TRUSTED_IDENTITY"
            or row.get("exitCode") != 0
        ):
            raise DeliveryError(f"process ledger row mismatch at ordinal {ordinal}")
        identity_relative = row.get("identityReceiptRelativePath")
        identity_sha = row.get("identityReceiptSha256")
        if not isinstance(identity_relative, str) or not isinstance(identity_sha, str):
            raise DeliveryError(f"process identity link malformed at ordinal {ordinal}")
        identity_path = project_root / Path(identity_relative)
        try:
            identity_sealed_relative = identity_path.resolve(strict=True).relative_to(raw_root.resolve(strict=True)).as_posix()
        except Exception as exc:
            raise DeliveryError(f"process identity escapes the sealed raw root at ordinal {ordinal}") from exc
        sealed_identity = sealed_entries.get(identity_sealed_relative)
        if sealed_identity is None or sealed_identity.get("sha256") != identity_sha:
            raise DeliveryError(f"process identity link differs from the already replayed seal at ordinal {ordinal}")
        identity = read_json(identity_path, f"process identity {ordinal}")
        if (
            identity.get("status") != "PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT"
            or identity.get("ordinal") != ordinal
            or identity.get("mode") != mode
            or identity.get("exitCode") != 0
            or identity.get("naturalExit") is not True
            or identity.get("signalOrForcedTerminationSent") is not False
            or identity.get("retryPerformed") is not False
        ):
            raise DeliveryError(f"trusted process identity mismatch at ordinal {ordinal}")

    def sealed_project_link(relative: Any, expected_sha: Any, label: str) -> Path:
        if not isinstance(relative, str) or not isinstance(expected_sha, str):
            raise DeliveryError(f"malformed sealed path/hash link: {label}")
        linked = (project_root / Path(relative)).resolve(strict=True)
        try:
            sealed_relative = linked.relative_to(raw_root.resolve(strict=True)).as_posix()
        except ValueError as exc:
            raise DeliveryError(f"sealed path/hash link escapes raw root: {label}: {relative}") from exc
        sealed = sealed_entries.get(sealed_relative)
        if sealed is None or sealed.get("sha256") != expected_sha:
            raise DeliveryError(f"sealed path/hash link differs from replayed inventory: {label}: {relative}")
        return linked

    accepted = list((raw_root / "raw/superblocks").glob("*/accepted-superblock-receipt.v1.json"))
    oracle = list((raw_root / "oracle").glob("*/oracle-pass-receipt.v1.json"))
    cache_bindings = list((raw_root / "oracle").glob("*/oracle-cache-binding-receipt.v4_1.json"))
    batches = list((raw_root / "oracle-batches").glob("batch-*/oracle-batch-receipt.v4_1.json"))
    lanes = list((raw_root / "raw/superblocks").glob("*/ALG-*/lane-receipt.v2.json"))
    lane_cache_links = list((raw_root / "raw/superblocks").glob("*/ALG-*/lane-oracle-cache-link.v4_1.json"))
    empty = list((raw_root / "raw/empty-boundary").glob("*/empty-boundary-receipt.v2.json"))
    if (
        len(accepted), len(oracle), len(cache_bindings), len(batches),
        len(lanes), len(lane_cache_links), len(empty)
    ) != (126, 126, 126, 6, 756, 756, 12):
        raise DeliveryError("receipt cardinality mismatch")
    for path in accepted:
        if read_json(path, "accepted-superblock receipt").get("status") != "ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK":
            raise DeliveryError(f"accepted-superblock status mismatch: {path}")
    for path in oracle:
        if read_json(path, "oracle receipt").get("status") != "PASS_ALGORITHM_NEUTRAL_GEOMETRY":
            raise DeliveryError(f"oracle status mismatch: {path}")

    cache_by_superblock: Dict[str, Dict[str, Any]] = {}
    cache_sha_by_superblock: Dict[str, str] = {}
    for path in cache_bindings:
        binding = read_json(path, "oracle cache-binding receipt")
        superblock_id = path.parent.name
        scheduled = schedule_by_id.get(superblock_id)
        if scheduled is None:
            raise DeliveryError(f"oracle cache binding is not scheduled: {superblock_id}")
        ordinal = scheduled.get("ordinal")
        if (
            binding.get("schema") != "gate14re-me-oracle-cache-binding-receipt-v4.1"
            or binding.get("status") != "PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V4_1"
            or binding.get("scheduleOrdinal") != ordinal
            or binding.get("batchIndex") != oracle_batch_index_v41(ordinal)
            or binding.get("superblockId") != superblock_id
            or binding.get("inputRelativePath") != scheduled.get("inputRelativePath")
            or binding.get("inputSha256") != scheduled.get("inputSha256")
            or binding.get("eventTableRows") != 24
        ):
            raise DeliveryError(f"oracle cache binding identity/cardinality mismatch: {path}")
        input_bundle = read_json(project_root / Path(scheduled["inputRelativePath"]), "scheduled input")
        if binding.get("agentTableRows") != int(input_bundle.get("agentCount", -1)) * 49:
            raise DeliveryError(f"oracle agent cache cardinality mismatch: {path}")
        expected_members = (
            ("oraclePassReceiptRelativePath", "oraclePassReceiptSha256", "oracle-pass receipt"),
            ("agentTableRelativePath", "agentTableSha256", "oracle agent table"),
            ("eventTableRelativePath", "eventTableSha256", "oracle event table"),
        )
        for relative_field, sha_field, label in expected_members:
            linked = sealed_project_link(binding.get(relative_field), binding.get(sha_field), f"{label} {superblock_id}")
            if linked.parent != path.parent:
                raise DeliveryError(f"oracle cache member is not in its exact superblock directory: {linked}")
        cache_by_superblock[superblock_id] = binding
        cache_sha_by_superblock[superblock_id] = sealed_entries[path.relative_to(raw_root).as_posix()]["sha256"]

    batch_seen: set[int] = set()
    batch_member_superblocks: set[str] = set()
    for path in batches:
        receipt = read_json(path, "oracle batch receipt")
        batch_index = receipt.get("batchIndex")
        members = receipt.get("members")
        if (
            receipt.get("schema") != "gate14re-me-oracle-batch-receipt-v4.1"
            or receipt.get("status") != "PASS_ORACLE_BATCH_COMPLETE_V4_1"
            or not isinstance(batch_index, int)
            or batch_index < 0
            or batch_index >= 6
            or batch_index in batch_seen
            or receipt.get("batchCount") != 6
            or receipt.get("assignmentRule") != "balanced-g-n-f-replicate-v4.1-formula"
            or receipt.get("inputCount") != 21
            or not isinstance(members, list)
            or len(members) != 21
        ):
            raise DeliveryError(f"oracle batch receipt mismatch: {path}")
        batch_seen.add(batch_index)
        for member in members:
            if not isinstance(member, dict):
                raise DeliveryError(f"malformed oracle batch member: {path}")
            superblock_id = member.get("superblockId")
            scheduled = schedule_by_id.get(superblock_id)
            if (
                scheduled is None
                or member.get("scheduleOrdinal") != scheduled.get("ordinal")
                or oracle_batch_index_v41(scheduled.get("ordinal")) != batch_index
                or superblock_id in batch_member_superblocks
                or member.get("cacheBindingReceiptSha256") != cache_sha_by_superblock.get(superblock_id)
            ):
                raise DeliveryError(f"oracle batch member binding mismatch: {path}: {superblock_id}")
            linked = sealed_project_link(
                member.get("cacheBindingReceiptRelativePath"),
                member.get("cacheBindingReceiptSha256"),
                f"oracle cache receipt {superblock_id}",
            )
            if linked != raw_root / "oracle" / str(superblock_id) / "oracle-cache-binding-receipt.v4_1.json":
                raise DeliveryError(f"oracle batch member cache path mismatch: {linked}")
            batch_member_superblocks.add(str(superblock_id))
    if batch_seen != set(range(6)) or batch_member_superblocks != scheduled_ids:
        raise DeliveryError("oracle batch coverage is not exactly six batches over all 126 scheduled inputs")

    for path in lanes:
        if read_json(path, "lane receipt").get("status") != "COMPLETE_RAW_LANE":
            raise DeliveryError(f"lane status mismatch: {path}")
    expected_lane_keys = {
        (superblock_id, str(lane.get("anonymousLaneId")))
        for superblock_id, scheduled in schedule_by_id.items()
        for lane in scheduled.get("algorithmOrder", [])
    }
    lane_receipt_keys = {(path.parent.parent.name, path.parent.name) for path in lanes}
    if lane_receipt_keys != expected_lane_keys:
        raise DeliveryError("lane receipt paths do not exactly cover the scheduled anonymous lanes")
    lane_link_keys: set[Tuple[str, str]] = set()
    for path in lane_cache_links:
        link = read_json(path, "lane oracle-cache link")
        superblock_id = path.parent.parent.name
        anonymous_lane = path.parent.name
        cache = cache_by_superblock.get(superblock_id)
        key = (superblock_id, anonymous_lane)
        scheduled_lane = next(
            (
                lane
                for lane in schedule_by_id[superblock_id].get("algorithmOrder", [])
                if lane.get("anonymousLaneId") == anonymous_lane
            ),
            None,
        ) if superblock_id in schedule_by_id else None
        if (
            cache is None
            or scheduled_lane is None
            or key in lane_link_keys
            or link.get("schema") != "gate14re-me-lane-oracle-cache-link-v4.1"
            or link.get("status") != "BOUND_TO_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V4_1"
            or link.get("superblockId") != superblock_id
            or link.get("inputId") != cache.get("inputId")
            or link.get("anonymousLaneId") != anonymous_lane
            or link.get("identityBindingSha256") != scheduled_lane.get("identityBindingSha256")
            or link.get("oracleCacheBindingSha256") != cache_sha_by_superblock.get(superblock_id)
            or link.get("agentTableRelativePath") != cache.get("agentTableRelativePath")
            or link.get("agentTableSha256") != cache.get("agentTableSha256")
            or link.get("agentTableRows") != cache.get("agentTableRows")
            or link.get("referenceOracleEvaluationsPerformedInsideLane") != 0
        ):
            raise DeliveryError(f"lane oracle-cache link mismatch: {path}")
        linked_cache = sealed_project_link(
            link.get("oracleCacheBindingRelativePath"),
            link.get("oracleCacheBindingSha256"),
            f"lane cache binding {superblock_id}/{anonymous_lane}",
        )
        if linked_cache != raw_root / "oracle" / superblock_id / "oracle-cache-binding-receipt.v4_1.json":
            raise DeliveryError(f"lane cache-binding path mismatch: {path}")
        lane_link_keys.add(key)
    if lane_link_keys != expected_lane_keys:
        raise DeliveryError("lane oracle-cache links do not exactly cover the scheduled anonymous lanes")
    for path in empty:
        if read_json(path, "empty-boundary receipt").get("status") != "COMPLETE_EMPTY_BOUNDARY_RAW":
            raise DeliveryError(f"empty-boundary status mismatch: {path}")
    accepted_ids = {path.parent.name for path in accepted}
    oracle_ids = {path.parent.name for path in oracle}
    cache_ids = {path.parent.name for path in cache_bindings}
    if accepted_ids != scheduled_ids or oracle_ids != scheduled_ids or cache_ids != scheduled_ids:
        raise DeliveryError("receipt-to-schedule superblock coverage mismatch")
    instrument = read_json(
        raw_root / "instruments/csharp/instrument-csharp-receipt.v2.json",
        "instrument receipt",
    )
    if instrument.get("status") != "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING":
        raise DeliveryError("instrument self-test receipt mismatch")

    return {
        "scheduleRows": len(schedule_rows),
        "acceptedSuperblocks": len(accepted),
        "oracleReceipts": len(oracle),
        "oracleBatchReceipts": len(batches),
        "oracleCacheBindingReceipts": len(cache_bindings),
        "laneReceipts": len(lanes),
        "laneOracleCacheLinks": len(lane_cache_links),
        "laneReferenceOracleEvaluations": 0,
        "emptyBoundaryReceipts": len(empty),
        "processLedgerRows": len(process_rows),
        "trustedProcessIdentityReceipts": len(process_rows),
        "failureLedgerRows": 0,
        "replacementLedgerRows": 0,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "pass": True,
    }


def discover_table_sources(
    raw_root: Path,
    table_id: str,
    spec: Mapping[str, Any],
    sealed_entries: Mapping[str, Mapping[str, Any]],
) -> List[Path]:
    file_name = spec.get("fileName")
    if not isinstance(file_name, str) or not file_name:
        raise DeliveryError(f"invalid fileName in schema for {table_id}")
    paths = sorted(
        (path for path in raw_root.rglob(file_name) if path.is_file()),
        key=lambda p: p.relative_to(raw_root).as_posix(),
    )
    if not paths:
        raise DeliveryError(f"no raw source files for {table_id}: {file_name}")
    for path in paths:
        relative = path.relative_to(raw_root).as_posix()
        if relative not in sealed_entries:
            raise DeliveryError(f"raw table source absent from sealed inventory: {relative}")
    return paths


@dataclass(frozen=True)
class TableProfile:
    table_id: str
    sources: Tuple[Path, ...]
    required_fields: Tuple[str, ...]
    columns: Tuple[str, ...]
    type_map: Dict[str, str]
    row_count: int
    source_bytes: int
    source_manifest_digest: str


def first_pass_profile(
    raw_root: Path,
    table_id: str,
    spec: Mapping[str, Any],
    sources: Sequence[Path],
    sealed_entries: Mapping[str, Mapping[str, Any]],
    source_bindings: MutableMapping[str, str],
    join_state: MutableMapping[str, set[str]],
) -> TableProfile:
    required = tuple(spec.get("requiredFields", ()))
    if not all(isinstance(field, str) and field for field in required):
        raise DeliveryError(f"invalid requiredFields for {table_id}")
    columns_seen: set[str] = set(required)
    observed_types: Dict[str, set[str]] = {field: set() for field in required}
    rows = 0
    source_bytes = 0
    source_manifest_digest = hashlib.sha256()
    for source in sources:
        relative = source.relative_to(raw_root).as_posix()
        seal = sealed_entries[relative]
        source_bytes += int(seal["bytes"])
        source_manifest_digest.update(
            (relative + "\0" + str(seal["bytes"]) + "\0" + str(seal["sha256"]) + "\n").encode("utf-8")
        )
        local_record_ids: set[str] = set()
        for line_number, row in read_jsonl(source):
            location = f"{relative}:{line_number}"
            if any(field in row for field in RESERVED_PROVENANCE_FIELDS):
                raise DeliveryError(f"reserved provenance field present in raw row: {location}")
            missing = [field for field in required if field not in row]
            if missing:
                raise DeliveryError(f"missing required field(s) {missing}: {location}")
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id or record_id in local_record_ids:
                raise DeliveryError(f"invalid or duplicate within-file recordId: {location}")
            local_record_ids.add(record_id)
            input_id = row.get("inputId")
            if isinstance(input_id, str) and input_id and not record_id.startswith(input_id + ":"):
                raise DeliveryError(f"recordId is outside its input namespace: {location}")
            if spec.get("sourcePathAndShaRequired") is True:
                source_relative = row.get("sourceRelativePath")
                source_sha = row.get("sourceSha256")
                if not isinstance(source_relative, str) or not isinstance(source_sha, str):
                    raise DeliveryError(f"malformed row source binding: {location}")
                previous = source_bindings.get(source_relative)
                if previous is not None and previous != source_sha:
                    raise DeliveryError(f"conflicting row source hash: {source_relative}")
                source_bindings[source_relative] = source_sha
            if table_id == "d3-windows":
                if record_id in join_state["d3"]:
                    raise DeliveryError(f"duplicate global D3 recordId: {location}")
                join_state["d3"].add(record_id)
            elif table_id == "event-groups":
                link = row.get("d3WindowRecordId")
                if not isinstance(link, str) or link in join_state["event"]:
                    raise DeliveryError(f"invalid or duplicate event-group D3 link: {location}")
                join_state["event"].add(link)
            elif table_id == "empty-boundary":
                link = row.get("d3WindowRecordId")
                if not isinstance(link, str) or link in join_state["empty"]:
                    raise DeliveryError(f"invalid or duplicate empty-boundary D3 link: {location}")
                join_state["empty"].add(link)
            for key, value in row.items():
                if not isinstance(key, str) or not key:
                    raise DeliveryError(f"invalid JSON object key: {location}")
                columns_seen.add(key)
                kind = scalar_type(value, f"{location}:{key}")
                if kind is not None:
                    observed_types.setdefault(key, set()).add(kind)
            rows += 1

    columns = tuple(list(required) + sorted(columns_seen - set(required)) + list(RESERVED_PROVENANCE_FIELDS))
    type_map: Dict[str, str] = {}
    for column in columns:
        if column == "_rawSourceRelativePath":
            kinds = {"string"}
        elif column == "_rawSourceLine":
            kinds = {"int64"}
        else:
            kinds = observed_types.get(column, set())
        if len(kinds) > 1:
            raise DeliveryError(
                f"column has inconsistent scalar types without coercion permission: {table_id}.{column}: {sorted(kinds)}"
            )
        kind = next(iter(kinds)) if kinds else "string"
        if kind not in ALLOWED_TYPES:
            raise DeliveryError(f"unsupported inferred type: {table_id}.{column}={kind}")
        type_map[column] = kind
    return TableProfile(
        table_id=table_id,
        sources=tuple(sources),
        required_fields=required,
        columns=columns,
        type_map=type_map,
        row_count=rows,
        source_bytes=source_bytes,
        source_manifest_digest=source_manifest_digest.hexdigest(),
    )


def validate_profile_cardinality(profiles: Sequence[TableProfile]) -> Dict[str, int]:
    by_id = {profile.table_id: profile for profile in profiles}
    expected_sources = {
        "oracle-agent-checks": 126,
        "oracle-event-checks": 126,
        "operations": 756,
        "event-groups": 756,
        "d3-windows": 769,
        "persistent-state": 756,
        "process-resources": 756,
        "empty-boundary": 12,
        "replacement-ledger": 1,
        "failures-and-voids": 1,
    }
    expected_rows = {
        "oracle-event-checks": 3024,
        "event-groups": 18144,
        "d3-windows": 30901,
        "process-resources": 19656,
        "empty-boundary": 12000,
        "replacement-ledger": 0,
        "failures-and-voids": 0,
    }
    for table_id, expected in expected_sources.items():
        actual = len(by_id[table_id].sources)
        if actual != expected:
            raise DeliveryError(f"raw source file cardinality mismatch for {table_id}: {actual} != {expected}")
    for table_id, expected in expected_rows.items():
        actual = by_id[table_id].row_count
        if actual != expected:
            raise DeliveryError(f"raw row cardinality mismatch for {table_id}: {actual} != {expected}")
    return {table_id: profile.row_count for table_id, profile in by_id.items()}


def validate_unique_source_bindings(project_root: Path, bindings: Mapping[str, str]) -> Dict[str, Any]:
    started = time.perf_counter()
    for relative, expected_sha in sorted(bindings.items()):
        path = (project_root / Path(relative)).resolve(strict=False)
        try:
            path.relative_to(project_root.resolve())
        except ValueError as exc:
            raise DeliveryError(f"row source path escapes project root: {relative}") from exc
        require_file(path, expected_sha, f"unique row source {relative}")
    return {
        "distinctSourceFiles": len(bindings),
        "eachDistinctSourceHashedOnce": True,
        "perRowSourceFileRehash": False,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def arrow_type(pa: Any, kind: str) -> Any:
    return {
        "string": pa.string(),
        "bool": pa.bool_(),
        "int64": pa.int64(),
        "float64": pa.float64(),
    }[kind]


def normalized_row(
    row: Mapping[str, Any],
    columns: Sequence[str],
    type_map: Mapping[str, str],
    relative: str,
    line_number: int,
) -> Dict[str, Any]:
    value = dict(row)
    value["_rawSourceRelativePath"] = relative
    value["_rawSourceLine"] = line_number
    result: Dict[str, Any] = {}
    for column in columns:
        item = value.get(column)
        kind = scalar_type(item, f"{relative}:{line_number}:{column}")
        if item is not None and kind != type_map[column]:
            raise DeliveryError(
                f"scalar type changed between passes: {relative}:{line_number}:{column}; "
                f"expected={type_map[column]}; actual={kind}"
            )
        result[column] = item
    extra = set(value) - set(columns)
    if extra:
        raise DeliveryError(f"new field(s) appeared between passes: {relative}:{line_number}: {sorted(extra)}")
    return result


def digest_row(digest: Any, row: Mapping[str, Any]) -> None:
    digest.update(canonical_json(row).encode("utf-8"))
    digest.update(b"\n")


def write_parquet_streaming(
    raw_root: Path,
    profile: TableProfile,
    output_path: Path,
    batch_size: int,
    pa: Any,
    pq: Any,
) -> Dict[str, Any]:
    started = time.perf_counter()
    output_path.parent.mkdir(parents=True, exist_ok=False)
    schema = pa.schema(
        [pa.field(column, arrow_type(pa, profile.type_map[column]), nullable=True) for column in profile.columns]
    )
    writer = pq.ParquetWriter(
        output_path,
        schema,
        compression="zstd",
        use_dictionary=False,
        write_statistics=True,
    )
    digest = hashlib.sha256()
    record_id_digest = hashlib.sha256()
    batch: List[Dict[str, Any]] = []
    rows = 0
    try:
        for source in profile.sources:
            relative = source.relative_to(raw_root).as_posix()
            for line_number, row in read_jsonl(source):
                normalized = normalized_row(row, profile.columns, profile.type_map, relative, line_number)
                digest_row(digest, normalized)
                record_id_digest.update((str(row.get("recordId")) + "\n").encode("utf-8"))
                batch.append(normalized)
                rows += 1
                if len(batch) >= batch_size:
                    writer.write_table(pa.Table.from_pylist(batch, schema=schema), row_group_size=batch_size)
                    batch.clear()
        if batch:
            writer.write_table(pa.Table.from_pylist(batch, schema=schema), row_group_size=batch_size)
            batch.clear()
    finally:
        writer.close()
    if rows != profile.row_count:
        raise DeliveryError(
            f"row count changed between profile and build: {profile.table_id}: "
            f"expected={profile.row_count}; actual={rows}"
        )
    return {
        "rows": rows,
        "canonicalOrderedRowSha256": digest.hexdigest(),
        "orderedRecordIdSha256": record_id_digest.hexdigest(),
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def verify_parquet_streaming(
    profile: TableProfile,
    parquet_path: Path,
    expected: Mapping[str, Any],
    batch_size: int,
    pa: Any,
    pq: Any,
) -> Dict[str, Any]:
    started = time.perf_counter()
    parquet = pq.ParquetFile(parquet_path)
    expected_schema = pa.schema(
        [pa.field(column, arrow_type(pa, profile.type_map[column]), nullable=True) for column in profile.columns]
    )
    if parquet.schema_arrow != expected_schema:
        raise DeliveryError(
            f"Parquet schema mismatch for {profile.table_id}: expected={expected_schema}; actual={parquet.schema_arrow}"
        )
    digest = hashlib.sha256()
    record_id_digest = hashlib.sha256()
    rows = 0
    for record_batch in parquet.iter_batches(batch_size=batch_size, columns=list(profile.columns)):
        for row in record_batch.to_pylist():
            digest_row(digest, row)
            record_id_digest.update((str(row.get("recordId")) + "\n").encode("utf-8"))
            rows += 1
    actual_digest = digest.hexdigest()
    actual_record_ids = record_id_digest.hexdigest()
    if rows != expected["rows"]:
        raise DeliveryError(f"Parquet row count mismatch for {profile.table_id}")
    if actual_digest != expected["canonicalOrderedRowSha256"]:
        raise DeliveryError(f"Parquet complete value/type/order digest mismatch for {profile.table_id}")
    if actual_record_ids != expected["orderedRecordIdSha256"]:
        raise DeliveryError(f"Parquet recordId order digest mismatch for {profile.table_id}")
    return {
        "rows": rows,
        "canonicalOrderedRowSha256": actual_digest,
        "orderedRecordIdSha256": actual_record_ids,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "roundTripPass": True,
    }


def write_file_manifest(root: Path, excluded: Iterable[str]) -> Tuple[Path, str]:
    excluded_set = set(excluded)
    rows: List[Dict[str, Any]] = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if relative in excluded_set:
            continue
        rows.append(
            {
                "schema": "gate14re-me-independent-streaming-acceptance-file-row-v4.2",
                "relativePath": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    manifest_path = root / "file-manifest.v4_2.jsonl"
    with manifest_path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(canonical_json(row) + "\n")
    return manifest_path, sha256_file(manifest_path)


def import_pyarrow(pyarrow_root: Path) -> Tuple[Any, Any, str]:
    if not pyarrow_root.is_dir():
        raise DeliveryError(f"PyArrow package root missing: {pyarrow_root}")
    sys.path.insert(0, str(pyarrow_root))
    try:
        import pyarrow as pa  # type: ignore
        import pyarrow.parquet as pq  # type: ignore
    except Exception as exc:
        raise DeliveryError(f"unable to import frozen PyArrow runtime: {exc}") from exc
    return pa, pq, str(pa.__version__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--raw-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--output-schema", required=True)
    parser.add_argument("--output-schema-sha256", required=True)
    parser.add_argument("--seal-manifest", required=True)
    parser.add_argument("--seal-manifest-sha256", required=True)
    parser.add_argument("--seal-terminal", required=True)
    parser.add_argument("--seal-terminal-sha256", required=True)
    parser.add_argument("--schedule", required=True)
    parser.add_argument("--schedule-sha256", required=True)
    parser.add_argument("--runtime-manifest", required=True)
    parser.add_argument("--runtime-manifest-sha256", required=True)
    parser.add_argument("--pyarrow-root", required=True)
    parser.add_argument("--batch-size", type=int, default=4096)
    return parser.parse_args()


def resolve_existing(path_text: str, label: str, want_dir: bool = False) -> Path:
    path = Path(path_text).resolve(strict=False)
    if want_dir and not path.is_dir():
        raise DeliveryError(f"missing {label} directory: {path}")
    if not want_dir and not path.is_file():
        raise DeliveryError(f"missing {label} file: {path}")
    return path


def main() -> int:
    args = parse_args()
    started_utc = utc_now()
    started = time.perf_counter()
    output_root = Path(args.output_root).resolve(strict=False)
    if output_root.exists():
        raise DeliveryError(f"output root must not already exist: {output_root}")
    output_root.mkdir(parents=True, exist_ok=False)
    failure_path = output_root / "failure-receipt.v4_2.json"
    try:
        if args.batch_size < 256 or args.batch_size > 65536:
            raise DeliveryError("batch size must be in [256, 65536]")
        project_root = resolve_existing(args.project_root, "project root", want_dir=True)
        raw_root = resolve_existing(args.raw_root, "raw root", want_dir=True)
        schema_path = resolve_existing(args.output_schema, "output schema")
        seal_manifest = resolve_existing(args.seal_manifest, "seal manifest")
        seal_terminal = resolve_existing(args.seal_terminal, "seal terminal")
        schedule_path = resolve_existing(args.schedule, "qualification schedule")
        runtime_manifest_path = resolve_existing(args.runtime_manifest, "runtime manifest")
        pyarrow_root = resolve_existing(args.pyarrow_root, "PyArrow root", want_dir=True)

        require_file(schema_path, args.output_schema_sha256, "output schema")
        require_file(seal_manifest, args.seal_manifest_sha256, "seal manifest")
        require_file(seal_terminal, args.seal_terminal_sha256, "seal terminal")
        require_file(schedule_path, args.schedule_sha256, "qualification schedule")
        require_file(runtime_manifest_path, args.runtime_manifest_sha256, "runtime manifest")

        seal_receipt = read_json(seal_terminal, "seal terminal")
        if (
            seal_receipt.get("status") != "PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING"
            or seal_receipt.get("acquisitionFreezeManifestSha256") != args.seal_manifest_sha256
            or seal_receipt.get("qualificationTerminalPass") is not False
        ):
            raise DeliveryError("unexpected acquisition terminal identity/status")
        runtime_manifest = read_json(runtime_manifest_path, "runtime manifest")
        if (
            runtime_manifest.get("schema") != "gate14re-me-typed-parquet-runtime-manifest-v1"
            or runtime_manifest.get("status") != "FROZEN_TYPED_PARQUET_RUNTIME"
        ):
            raise DeliveryError("frozen typed-Parquet runtime identity mismatch")

        pa, pq, pyarrow_version = import_pyarrow(pyarrow_root)
        if pyarrow_version != str(runtime_manifest.get("distribution", {}).get("version")):
            raise DeliveryError(
                f"PyArrow version mismatch: manifest={runtime_manifest.get('distribution', {}).get('version')}; "
                f"imported={pyarrow_version}"
            )
        specs = load_specs(schema_path)

        sealed_entries, seal_replay = replay_sealed_inventory(raw_root, seal_manifest)
        control_plane = validate_control_plane(
            project_root,
            raw_root,
            schedule_path,
            args.schedule_sha256,
            args.seal_manifest_sha256,
            sealed_entries,
        )
        phase_started = time.perf_counter()
        profiles: List[TableProfile] = []
        source_bindings: Dict[str, str] = {}
        join_state: Dict[str, set[str]] = {"d3": set(), "event": set(), "empty": set()}
        for table_id in RAW_TABLE_ORDER:
            sources = discover_table_sources(raw_root, table_id, specs[table_id], sealed_entries)
            profiles.append(
                first_pass_profile(
                    raw_root,
                    table_id,
                    specs[table_id],
                    sources,
                    sealed_entries,
                    source_bindings,
                    join_state,
                )
            )
        table_row_counts = validate_profile_cardinality(profiles)
        if not join_state["event"].issubset(join_state["d3"]):
            raise DeliveryError("event-group D3 join is incomplete")
        if not join_state["empty"].issubset(join_state["d3"]):
            raise DeliveryError("empty-boundary D3 join is incomplete")
        if len(join_state["event"]) != 18144 or len(join_state["empty"]) != 12000:
            raise DeliveryError("D3 join cardinality mismatch")
        source_binding_validation = validate_unique_source_bindings(project_root, source_bindings)
        profile_seconds = round(time.perf_counter() - phase_started, 3)

        tables: List[Dict[str, Any]] = []
        total_rows = 0
        for profile in profiles:
            parquet_path = output_root / "typed-parquet" / profile.table_id / f"{profile.table_id}.v4_2.parquet"
            built = write_parquet_streaming(
                raw_root, profile, parquet_path, args.batch_size, pa, pq
            )
            verified = verify_parquet_streaming(
                profile, parquet_path, built, args.batch_size, pa, pq
            )
            product_relative = parquet_path.relative_to(output_root).as_posix()
            table_receipt = {
                "schema": TABLE_SCHEMA,
                "tableId": profile.table_id,
                "rawSourceFiles": len(profile.sources),
                "rawSourceBytes": profile.source_bytes,
                "rawSourceManifestSha256": profile.source_manifest_digest,
                "rows": profile.row_count,
                "columns": list(profile.columns),
                "typeMap": profile.type_map,
                "canonicalOrderedRowSha256": built["canonicalOrderedRowSha256"],
                "orderedRecordIdSha256": built["orderedRecordIdSha256"],
                "typedParquet": {
                    "relativePath": product_relative,
                    "bytes": parquet_path.stat().st_size,
                    "sha256": sha256_file(parquet_path),
                    "compression": "zstd",
                    "pyarrowVersion": pyarrow_version,
                    "buildSeconds": built["elapsedSeconds"],
                    "roundTripVerifySeconds": verified["elapsedSeconds"],
                    "completeValueTypeOrderRoundTripPass": True,
                },
            }
            write_json(
                output_root / "table-receipts" / f"{profile.table_id}.table-receipt.v4_2.json",
                table_receipt,
            )
            tables.append(table_receipt)
            total_rows += profile.row_count

        manifest = {
            "schema": MANIFEST_SCHEMA,
            "version": "4.2",
            "status": "PASS_NECESSARY_CONTROL_RAW_AND_TYPED_PARQUET_ROUND_TRIP",
            "studyId": "Gate14Re-ME",
            "profile": "BOUNDED_GNF_V4_1_ORACLE_CACHE_INDEPENDENT_READ_ONLY_ACCEPTANCE",
            "sourceRawRoot": raw_root.as_posix(),
            "outputRoot": output_root.as_posix(),
            "canonicalRecord": "SEALED_RAW_JSONL",
            "derivedRequiredView": "TYPED_PARQUET_ONLY",
            "omittedRedundantGatingViews": ["duplicate-canonical-JSONL", "CSV", "JSONL.GZ"],
            "tableCount": len(tables),
            "totalRows": total_rows,
            "tables": tables,
            "tableRowCounts": table_row_counts,
            "bindings": {
                "outputSchemaSha256": args.output_schema_sha256,
                "sealManifestSha256": args.seal_manifest_sha256,
                "sealTerminalSha256": args.seal_terminal_sha256,
                "scheduleSha256": args.schedule_sha256,
                "typedParquetRuntimeManifestSha256": args.runtime_manifest_sha256,
            },
            "sealedInventoryReplay": seal_replay,
            "controlPlaneValidation": control_plane,
            "uniqueRowSourceValidation": source_binding_validation,
            "joinCriticalIdentityValidation": {
                "d3RecordIds": len(join_state["d3"]),
                "eventGroupD3Links": len(join_state["event"]),
                "emptyBoundaryD3Links": len(join_state["empty"]),
                "oneToOneCompleteForRequiredLinks": True,
            },
            "performance": {
                "batchSize": args.batch_size,
                "profilePassSeconds": profile_seconds,
                "wholeDatasetRowsRetainedInMemory": False,
                "recordIdArraysRetainedInManifest": False,
                "perRowSourceFileRehash": False,
                "sealedFilesHashedExactlyOnceInThisRun": True,
            },
            "boundaries": {
                "sourceRootsModified": False,
                "algorithmIdentityOpened": False,
                "algorithmEffectsComputed": False,
                "rankingOrWinnerComputed": False,
                "formalInferencePerformed": False,
                "qualificationTerminalPassRequiresThisFrozenAcceptance": True,
            },
            "createdAtUtc": utc_now(),
        }
        manifest_path = output_root / "acceptance-manifest.v4_2.json"
        write_json(manifest_path, manifest)
        manifest_sha = sha256_file(manifest_path)

        result = {
            "schema": RESULT_SCHEMA,
            "version": "4.2",
            "status": "PASS_INDEPENDENT_STREAMING_ESSENTIAL_ACCEPTANCE",
            "studyId": "Gate14Re-ME",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "sourceAttempt": raw_root.name,
            "sourceRawRoot": raw_root.as_posix(),
            "outputRoot": output_root.as_posix(),
            "tables": len(tables),
            "rows": total_rows,
            "typedParquetBuildPass": True,
            "typedParquetRoundTripPass": True,
            "deliveryManifestRelativePath": manifest_path.relative_to(output_root).as_posix(),
            "deliveryManifestSha256": manifest_sha,
            "qualificationTerminalPassEligible": True,
            "formalCollectionOrAnalysisPerformed": False,
            "sourceRootsModified": False,
        }
        result_path = output_root / "terminal-receipt.v4_2.json"
        write_json(result_path, result)
        file_manifest_path, file_manifest_sha = write_file_manifest(
            output_root,
            excluded={"file-manifest.v4_2.jsonl", "terminal-final.v4_2.json"},
        )
        terminal_final = dict(result)
        terminal_final.update(
            {
                "schema": "gate14re-me-independent-streaming-acceptance-terminal-v4.2",
                "status": "PASS_INDEPENDENT_STREAMING_ESSENTIAL_ACCEPTANCE_FROZEN",
                "fileManifestRelativePath": file_manifest_path.relative_to(output_root).as_posix(),
                "fileManifestSha256": file_manifest_sha,
                "terminalReceiptSha256": sha256_file(result_path),
            }
        )
        write_json(output_root / "terminal-final.v4_2.json", terminal_final)
        print(canonical_json(terminal_final))
        return 0
    except Exception as exc:
        failure = {
            "schema": FAILURE_SCHEMA,
            "version": "4.2",
            "status": "FAIL_CLOSED_INDEPENDENT_STREAMING_ESSENTIAL_ACCEPTANCE",
            "startedAtUtc": started_utc,
            "failedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "errorType": type(exc).__name__,
            "error": str(exc),
            "traceback": traceback.format_exc(),
            "sourceRootsModified": False,
            "sameAttemptRetryPermitted": False,
        }
        try:
            write_json(failure_path, failure)
        except Exception:
            pass
        print(canonical_json(failure), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
