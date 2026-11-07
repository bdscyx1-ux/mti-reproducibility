#!/usr/bin/env python3
"""Gate14Re-ME streaming essential delivery/round-trip verifier v4.0.

This implementation is deliberately independent from acquisition.  It consumes a
sealed, already structurally validated raw root read-only and writes only to a new
acceptance output root.  It keeps complete raw JSONL as the immutable canonical
record and creates one typed Parquet view per raw table.

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


TOOL_SCHEMA = "gate14re-me-streaming-essential-delivery-tool-v4"
RESULT_SCHEMA = "gate14re-me-streaming-essential-delivery-result-v4"
MANIFEST_SCHEMA = "gate14re-me-streaming-essential-delivery-manifest-v4"
TABLE_SCHEMA = "gate14re-me-streaming-essential-delivery-table-v4"
FAILURE_SCHEMA = "gate14re-me-streaming-essential-delivery-failure-v4"
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
    if schema.get("schema") != "gate14re-me-load-qualification-output-schema-v3":
        raise DeliveryError("feasibility profile requires the frozen attempt-009 output schema v3")
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
    for line_number, row in read_jsonl(manifest_path):
        if row.get("schema") != "gate14re-me-paused-seal-file-row-v1":
            raise DeliveryError(f"unexpected seal manifest row schema: {manifest_path}:{line_number}")
        if row.get("root") != "measured":
            raise DeliveryError(f"unexpected seal manifest root: {manifest_path}:{line_number}")
        relative = row.get("relativePath")
        expected_sha = row.get("sha256")
        expected_bytes = row.get("bytes")
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
            "lastWriteTimeUtc": row.get("lastWriteTimeUtc"),
        }
        entries[relative] = entry
        total_bytes += expected_bytes

    current_paths = {
        path.relative_to(raw_root).as_posix()
        for path in raw_root.rglob("*")
        if path.is_file()
    }
    if current_paths != set(entries):
        missing = sorted(set(entries) - current_paths)[:20]
        extra = sorted(current_paths - set(entries))[:20]
        raise DeliveryError(f"sealed inventory membership mismatch: missing={missing}; extra={extra}")
    return entries, {
        "files": len(entries),
        "bytes": total_bytes,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "allCurrentHashesMatchSeal": True,
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
        for line_number, row in read_jsonl(source):
            location = f"{relative}:{line_number}"
            if any(field in row for field in RESERVED_PROVENANCE_FIELDS):
                raise DeliveryError(f"reserved provenance field present in raw row: {location}")
            missing = [field for field in required if field not in row]
            if missing:
                raise DeliveryError(f"missing required field(s) {missing}: {location}")
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
                "schema": "gate14re-me-streaming-essential-delivery-file-row-v4",
                "relativePath": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    manifest_path = root / "file-manifest.v4.jsonl"
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
    parser.add_argument("--offline-validation-result", required=True)
    parser.add_argument("--offline-validation-result-sha256", required=True)
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
    failure_path = output_root / "failure-receipt.v4.json"
    try:
        if args.batch_size < 256 or args.batch_size > 65536:
            raise DeliveryError("batch size must be in [256, 65536]")
        project_root = resolve_existing(args.project_root, "project root", want_dir=True)
        raw_root = resolve_existing(args.raw_root, "raw root", want_dir=True)
        schema_path = resolve_existing(args.output_schema, "output schema")
        seal_manifest = resolve_existing(args.seal_manifest, "seal manifest")
        seal_terminal = resolve_existing(args.seal_terminal, "seal terminal")
        offline_result_path = resolve_existing(args.offline_validation_result, "offline validation result")
        runtime_manifest_path = resolve_existing(args.runtime_manifest, "runtime manifest")
        pyarrow_root = resolve_existing(args.pyarrow_root, "PyArrow root", want_dir=True)

        require_file(schema_path, args.output_schema_sha256, "output schema")
        require_file(seal_manifest, args.seal_manifest_sha256, "seal manifest")
        require_file(seal_terminal, args.seal_terminal_sha256, "seal terminal")
        require_file(offline_result_path, args.offline_validation_result_sha256, "offline validation result")
        require_file(runtime_manifest_path, args.runtime_manifest_sha256, "runtime manifest")

        seal_receipt = read_json(seal_terminal, "seal terminal")
        if seal_receipt.get("status") != "PASS_PAUSED_SEAL_CREATED_QUALIFICATION_NOT_PASS":
            raise DeliveryError("unexpected attempt-009 seal terminal status")
        offline_result = read_json(offline_result_path, "offline validation result")
        if (
            offline_result.get("status") != "PASS_OFFLINE_NECESSARY_RAW_VALIDATION"
            or offline_result.get("offlineNecessaryRawValidationPass") is not True
            or offline_result.get("boundaries", {}).get("sourceRootsModified") is not False
        ):
            raise DeliveryError("offline necessary validation is not a clean PASS")
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
        phase_started = time.perf_counter()
        profiles: List[TableProfile] = []
        for table_id in RAW_TABLE_ORDER:
            sources = discover_table_sources(raw_root, table_id, specs[table_id], sealed_entries)
            profiles.append(first_pass_profile(raw_root, table_id, specs[table_id], sources, sealed_entries))
        profile_seconds = round(time.perf_counter() - phase_started, 3)

        tables: List[Dict[str, Any]] = []
        total_rows = 0
        for profile in profiles:
            parquet_path = output_root / "typed-parquet" / profile.table_id / f"{profile.table_id}.v4.parquet"
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
                output_root / "table-receipts" / f"{profile.table_id}.table-receipt.v4.json",
                table_receipt,
            )
            tables.append(table_receipt)
            total_rows += profile.row_count

        manifest = {
            "schema": MANIFEST_SCHEMA,
            "version": 4,
            "status": "PASS_STREAMING_ESSENTIAL_TYPED_PARQUET_BUILD_AND_ROUND_TRIP",
            "studyId": "Gate14Re-ME",
            "profile": "LEGACY_ATTEMPT_009_FEASIBILITY_READ_ONLY",
            "sourceRawRoot": raw_root.as_posix(),
            "outputRoot": output_root.as_posix(),
            "canonicalRecord": "SEALED_RAW_JSONL",
            "derivedRequiredView": "TYPED_PARQUET_ONLY",
            "omittedRedundantGatingViews": ["duplicate-canonical-JSONL", "CSV", "JSONL.GZ"],
            "tableCount": len(tables),
            "totalRows": total_rows,
            "tables": tables,
            "bindings": {
                "outputSchemaSha256": args.output_schema_sha256,
                "sealManifestSha256": args.seal_manifest_sha256,
                "sealTerminalSha256": args.seal_terminal_sha256,
                "offlineNecessaryValidationResultSha256": args.offline_validation_result_sha256,
                "typedParquetRuntimeManifestSha256": args.runtime_manifest_sha256,
            },
            "sealedInventoryReplay": seal_replay,
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
                "attempt009QualificationTerminalPassClaimed": False,
            },
            "createdAtUtc": utc_now(),
        }
        manifest_path = output_root / "delivery-manifest.v4.json"
        write_json(manifest_path, manifest)
        manifest_sha = sha256_file(manifest_path)

        result = {
            "schema": RESULT_SCHEMA,
            "version": 4,
            "status": "PASS_FEASIBILITY_STREAMING_ESSENTIAL_ACCEPTANCE",
            "studyId": "Gate14Re-ME",
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "sourceAttempt": "load-qualification-execution-attempt-009",
            "sourceRawRoot": raw_root.as_posix(),
            "outputRoot": output_root.as_posix(),
            "tables": len(tables),
            "rows": total_rows,
            "typedParquetBuildPass": True,
            "typedParquetRoundTripPass": True,
            "deliveryManifestRelativePath": manifest_path.relative_to(output_root).as_posix(),
            "deliveryManifestSha256": manifest_sha,
            "qualificationTerminalPassClaimed": False,
            "sourceRootsModified": False,
        }
        result_path = output_root / "terminal-receipt.v4.json"
        write_json(result_path, result)
        file_manifest_path, file_manifest_sha = write_file_manifest(
            output_root,
            excluded={"file-manifest.v4.jsonl", "terminal-final.v4.json"},
        )
        terminal_final = dict(result)
        terminal_final.update(
            {
                "schema": "gate14re-me-streaming-essential-delivery-terminal-v4",
                "status": "PASS_FEASIBILITY_STREAMING_ESSENTIAL_ACCEPTANCE_FROZEN",
                "fileManifestRelativePath": file_manifest_path.relative_to(output_root).as_posix(),
                "fileManifestSha256": file_manifest_sha,
                "terminalReceiptSha256": sha256_file(result_path),
            }
        )
        write_json(output_root / "terminal-final.v4.json", terminal_final)
        print(canonical_json(terminal_final))
        return 0
    except Exception as exc:
        failure = {
            "schema": FAILURE_SCHEMA,
            "version": 4,
            "status": "FAIL_CLOSED_STREAMING_ESSENTIAL_ACCEPTANCE",
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
