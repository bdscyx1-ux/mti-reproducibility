#!/usr/bin/env python3
"""Lossless schema-v2-format delivery adapter for Gate14Re-ME schema v3.

The tool first runs the structural-v3 validator, then writes the unchanged v2
delivery format: complete canonical
JSONL, RFC 4180 CSV with canonical-JSON scalar cells, deterministic JSONL.GZ,
and explicitly typed Parquet.  Verification compares complete ordered rows and
scalar types, product hashes, raw provenance, and D3-v3.1 one-to-one joins.
No endpoint aggregation, algorithm comparison, ranking, or winner computation
is present.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import math
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, Sequence, Tuple

import gate14re_me_qualification_structural_v3 as structural


TOOL_SCHEMA = "gate14re-me-qualification-delivery-tool-v2.1-schema-v3-adapter"
MANIFEST_SCHEMA = "gate14re-me-qualification-delivery-manifest-v2"
RECEIPT_SCHEMA = "gate14re-me-qualification-delivery-receipt-v2"
TYPED_PARQUET_RUNTIME_SHA256 = "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e"
TYPE_NAMES = {"string", "bool", "int64", "float64"}


class DeliveryError(RuntimeError):
    """A fail-closed delivery construction or verification error."""


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
        raise DeliveryError(f"missing JSON file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise DeliveryError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DeliveryError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    if not path.is_file():
        raise DeliveryError(f"missing JSONL file: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise DeliveryError(f"invalid JSONL: {path}:{line_number}: {exc}") from exc
            if not isinstance(value, dict):
                raise DeliveryError(f"JSON object required: {path}:{line_number}")
            yield line_number, value


def require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise DeliveryError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise DeliveryError(
            f"{label} SHA-256 mismatch: expected {expected}; actual {actual}"
        )


def within(child: Path, parent: Path) -> bool:
    return structural.within(child, parent)


def resolve_project_file(value: str | Path, project_root: Path, label: str) -> Path:
    try:
        return structural.resolve_project_file(value, project_root, label)
    except structural.StructuralError as exc:
        raise DeliveryError(str(exc)) from exc


def import_pyarrow(
    project_root: Path,
    runtime_manifest_path: Path,
    runtime_manifest_sha256: str,
) -> Tuple[Any, Any, Dict[str, Any]]:
    require_hash(runtime_manifest_path, runtime_manifest_sha256, "typed-Parquet runtime manifest")
    if runtime_manifest_sha256 != TYPED_PARQUET_RUNTIME_SHA256:
        raise DeliveryError("typed-Parquet runtime manifest is not the frozen runtime hash")
    manifest = read_json(runtime_manifest_path)
    if manifest.get("schema") != "gate14re-me-typed-parquet-runtime-manifest-v1" or manifest.get("status") != "FROZEN_TYPED_PARQUET_RUNTIME":
        raise DeliveryError("unexpected typed-Parquet runtime manifest identity/status")
    distribution = manifest.get("distribution")
    if not isinstance(distribution, dict) or distribution.get("name") != "pyarrow" or distribution.get("version") != "25.0.1" or distribution.get("pythonAbi") != "cp312" or distribution.get("platform") != "win_amd64":
        raise DeliveryError("typed-Parquet runtime distribution binding mismatch")
    package_relative = manifest.get("packageRootRelativePath")
    if not isinstance(package_relative, str):
        raise DeliveryError("typed-Parquet runtime package root is missing")
    package_root = (project_root / package_relative).resolve()
    if not within(package_root, project_root) or not package_root.is_dir():
        raise DeliveryError("typed-Parquet runtime package root is missing or outside project")
    package_text = str(package_root)
    if package_text not in sys.path:
        sys.path.insert(0, package_text)
    try:
        import pyarrow as pa  # type: ignore
        import pyarrow.parquet as pq  # type: ignore
    except Exception as exc:
        raise DeliveryError(f"frozen typed-Parquet runtime import failed: {exc}") from exc
    if str(pa.__version__) != "25.0.1":
        raise DeliveryError(f"unexpected pyarrow version: {pa.__version__}")
    return pa, pq, manifest


def scalar_type(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        if value < structural.INT64_MIN or value > structural.INT64_MAX:
            raise DeliveryError("integer cannot be represented as signed int64")
        return "int64"
    if isinstance(value, float):
        if not math.isfinite(value):
            raise DeliveryError("non-finite float is prohibited")
        return "float64"
    if isinstance(value, str):
        return "string"
    raise DeliveryError(f"non-scalar value is prohibited: {type(value).__name__}")


def infer_type_map(
    rows: Sequence[Mapping[str, Any]], columns: Sequence[str]
) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for column in columns:
        observed = {scalar_type(row.get(column)) for row in rows}
        observed.discard(None)
        if len(observed) > 1:
            raise DeliveryError(
                f"column has inconsistent scalar types without coercion permission: {column}: {sorted(observed)}"
            )
        result[column] = next(iter(observed)) if observed else "string"
    return result


def ordered_columns(
    required_fields: Sequence[str], rows: Sequence[Mapping[str, Any]]
) -> List[str]:
    required = list(required_fields)
    additional = sorted({key for row in rows for key in row if key not in required})
    return required + additional


def exact_scalar_equal(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, float):
        if not math.isfinite(left) or not math.isfinite(right):
            return False
        if left == 0.0 and right == 0.0:
            return math.copysign(1.0, left) == math.copysign(1.0, right)
    return left == right


def exact_rows_equal(
    expected: Sequence[Mapping[str, Any]], actual: Sequence[Mapping[str, Any]]
) -> bool:
    if len(expected) != len(actual):
        return False
    for left, right in zip(expected, actual):
        if set(left) != set(right):
            return False
        if any(not exact_scalar_equal(left[key], right[key]) for key in left):
            return False
    return True


def write_jsonl(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(canonical_json(row))
            handle.write("\n")


def write_jsonl_gzip(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            for row in rows:
                compressed.write((canonical_json(row) + "\n").encode("utf-8"))


def write_csv(
    path: Path, rows: Sequence[Mapping[str, Any]], columns: Sequence[str]
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(columns),
            extrasaction="raise",
            lineterminator="\r\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({column: canonical_json(row.get(column)) for column in columns})


def arrow_type(pa: Any, type_name: str) -> Any:
    if type_name == "string":
        return pa.string()
    if type_name == "bool":
        return pa.bool_()
    if type_name == "int64":
        return pa.int64()
    if type_name == "float64":
        return pa.float64()
    raise DeliveryError(f"unsupported Arrow type: {type_name}")


def write_parquet(
    path: Path,
    rows: Sequence[Mapping[str, Any]],
    columns: Sequence[str],
    type_map: Mapping[str, str],
    pa: Any,
    pq: Any,
) -> None:
    schema = pa.schema([pa.field(column, arrow_type(pa, type_map[column])) for column in columns])
    normalized = [{column: row.get(column) for column in columns} for row in rows]
    table = pa.Table.from_pylist(normalized, schema=schema)
    pq.write_table(
        table,
        path,
        compression="zstd",
        use_dictionary=False,
        write_statistics=True,
    )


def read_gzip_rows(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        with gzip.open(path, "rt", encoding="utf-8", newline="") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise DeliveryError(f"JSON object required: {path}:{line_number}")
                rows.append(value)
    except DeliveryError:
        raise
    except Exception as exc:
        raise DeliveryError(f"invalid JSONL.GZ: {path}: {exc}") from exc
    return rows


def read_csv_rows(
    path: Path, columns: Sequence[str], type_map: Mapping[str, str]
) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != list(columns):
                raise DeliveryError(f"CSV column order mismatch: {path}")
            for line_number, encoded in enumerate(reader, 2):
                decoded: Dict[str, Any] = {}
                for column in columns:
                    token = encoded.get(column)
                    if token is None:
                        raise DeliveryError(f"CSV field missing: {path}:{line_number}:{column}")
                    value = json.loads(token)
                    observed = scalar_type(value)
                    if value is not None and observed != type_map[column]:
                        raise DeliveryError(
                            f"CSV scalar type mismatch: {path}:{line_number}:{column}"
                        )
                    decoded[column] = value
                rows.append(decoded)
    except DeliveryError:
        raise
    except Exception as exc:
        raise DeliveryError(f"invalid RFC 4180 CSV: {path}: {exc}") from exc
    return rows


def read_parquet_rows(
    path: Path,
    columns: Sequence[str],
    type_map: Mapping[str, str],
    pa: Any,
    pq: Any,
) -> List[Dict[str, Any]]:
    try:
        table = pq.read_table(path)
    except Exception as exc:
        raise DeliveryError(f"invalid Parquet file: {path}: {exc}") from exc
    if table.column_names != list(columns):
        raise DeliveryError(f"Parquet column order mismatch: {path}")
    for field in table.schema:
        expected = arrow_type(pa, type_map[field.name])
        if field.type != expected:
            raise DeliveryError(
                f"Parquet type mismatch for {field.name}: expected {expected}; actual {field.type}"
            )
    return table.to_pylist()


def round_trip_validate(
    expected: Sequence[Mapping[str, Any]],
    columns: Sequence[str],
    type_map: Mapping[str, str],
    jsonl_path: Path,
    csv_path: Path,
    gzip_path: Path,
    parquet_path: Path,
    pa: Any,
    pq: Any,
) -> None:
    canonical_expected = [{column: row.get(column) for column in columns} for row in expected]
    views = {
        "JSONL": [row for _, row in read_jsonl(jsonl_path)],
        "CSV": read_csv_rows(csv_path, columns, type_map),
        "JSONL.GZ": read_gzip_rows(gzip_path),
        "Parquet": read_parquet_rows(parquet_path, columns, type_map, pa, pq),
    }
    for label, actual in views.items():
        if not exact_rows_equal(canonical_expected, actual):
            raise DeliveryError(f"{label} complete value/type/order round trip failed")


def collect_rows_and_provenance(
    raw_root: Path,
    project_root: Path,
    specs: Mapping[str, Mapping[str, Any]],
    identity_binding_sha256: str,
) -> Tuple[Dict[str, List[Dict[str, Any]]], List[Dict[str, Any]]]:
    try:
        tables = structural.load_tables(raw_root, project_root, specs, identity_binding_sha256)
    except structural.StructuralError as exc:
        raise DeliveryError(str(exc)) from exc
    result: Dict[str, List[Dict[str, Any]]] = {}
    provenance: List[Dict[str, Any]] = []
    seen_sources: set[Tuple[str, str]] = set()
    for table_id in structural.RAW_TABLE_ORDER:
        rows: List[Dict[str, Any]] = []
        for envelope in tables[table_id]:
            if "_rawSourceRelativePath" in envelope.row or "_rawSourceLine" in envelope.row:
                raise DeliveryError(f"reserved delivery provenance field in raw row: {envelope.location}")
            exported = dict(envelope.row)
            exported["_rawSourceRelativePath"] = envelope.path.relative_to(raw_root).as_posix()
            exported["_rawSourceLine"] = envelope.line_number
            rows.append(exported)
            key = (table_id, str(envelope.path.resolve()))
            if key not in seen_sources:
                seen_sources.add(key)
                source_rows = sum(1 for _ in structural.read_jsonl(envelope.path))
                provenance.append(
                    {
                        "tableId": table_id,
                        "relativePath": envelope.path.relative_to(raw_root).as_posix(),
                        "sha256": sha256_file(envelope.path),
                        "bytes": envelope.path.stat().st_size,
                        "rows": source_rows,
                    }
                )
        for source in structural.discover_sources(raw_root, specs[table_id]):
            key = (table_id, str(source.resolve()))
            if key not in seen_sources:
                seen_sources.add(key)
                provenance.append(
                    {
                        "tableId": table_id,
                        "relativePath": source.relative_to(raw_root).as_posix(),
                        "sha256": sha256_file(source),
                        "bytes": source.stat().st_size,
                        "rows": 0,
                    }
                )
        result[table_id] = rows
    provenance.sort(key=lambda item: (item["tableId"], item["relativePath"]))
    return result, provenance


def allowed_output_root(project_root: Path, output_root: Path, profile: str) -> bool:
    if profile == "qualification-full":
        parent = (project_root / "Research/Exports/Gate14Re-ME/load-qualification").resolve()
    else:
        parent = (
            project_root
            / "Research/Verification/Gate14Re-ME/"
            "qualification-execution-terminal-chain-corrigendum-attempt-001"
        ).resolve()
    return within(output_root, parent)


def build_delivery(
    *,
    project_root: Path,
    raw_root: Path,
    output_root: Path,
    output_schema_path: Path,
    output_schema_sha256: str,
    d3_contract_path: Path,
    d3_contract_sha256: str,
    runtime_manifest_path: Path,
    runtime_manifest_sha256: str,
    identity_binding_sha256: str,
    profile: str,
) -> Dict[str, Any]:
    project_root = project_root.resolve()
    raw_root = raw_root.resolve()
    output_root = output_root.resolve()
    if not allowed_output_root(project_root, output_root, profile):
        raise DeliveryError("delivery output is outside the authorized root")
    if within(output_root, raw_root) or within(raw_root, output_root):
        raise DeliveryError("raw and delivery roots must be disjoint")
    if output_root.exists():
        raise DeliveryError("delivery output already exists; overwrite/resume is prohibited")
    try:
        structural_receipt = structural.validate_raw_package(
            project_root=project_root,
            raw_root=raw_root,
            output_schema_path=output_schema_path,
            output_schema_sha256=output_schema_sha256,
            d3_contract_path=d3_contract_path,
            d3_contract_sha256=d3_contract_sha256,
            identity_binding_sha256=identity_binding_sha256,
            profile=profile,
        )
        specs = structural.load_specs(output_schema_path, output_schema_sha256)
    except structural.StructuralError as exc:
        raise DeliveryError(str(exc)) from exc
    pa, pq, runtime_manifest = import_pyarrow(
        project_root, runtime_manifest_path, runtime_manifest_sha256
    )
    tables, provenance = collect_rows_and_provenance(
        raw_root, project_root, specs, identity_binding_sha256
    )
    staging = output_root.with_name(output_root.name + ".staging." + os.urandom(8).hex())
    if not allowed_output_root(project_root, staging, profile):
        raise DeliveryError("staging output is outside the authorized root")
    staging.parent.mkdir(parents=True, exist_ok=True)
    staging.mkdir(exist_ok=False)
    table_receipts: List[Dict[str, Any]] = []
    try:
        for table_id in structural.RAW_TABLE_ORDER:
            rows = tables[table_id]
            required_fields = tuple(specs[table_id].get("requiredFields", ()))
            columns = ordered_columns(
                required_fields + ("_rawSourceRelativePath", "_rawSourceLine"), rows
            )
            type_map = infer_type_map(rows, columns)
            table_dir = staging / table_id
            table_dir.mkdir()
            jsonl_path = table_dir / f"{table_id}.v2.jsonl"
            csv_path = table_dir / f"{table_id}.v2.csv"
            gzip_path = table_dir / f"{table_id}.v2.jsonl.gz"
            parquet_path = table_dir / f"{table_id}.v2.parquet"
            normalized = [{column: row.get(column) for column in columns} for row in rows]
            write_jsonl(jsonl_path, normalized)
            write_csv(csv_path, normalized, columns)
            write_jsonl_gzip(gzip_path, normalized)
            write_parquet(parquet_path, normalized, columns, type_map, pa, pq)
            round_trip_validate(
                normalized,
                columns,
                type_map,
                jsonl_path,
                csv_path,
                gzip_path,
                parquet_path,
                pa,
                pq,
            )
            products: List[Dict[str, Any]] = []
            for format_name, product in (
                ("canonical-jsonl", jsonl_path),
                ("rfc4180-csv-canonical-json-scalar-cells", csv_path),
                ("deterministic-jsonl-gzip", gzip_path),
                ("typed-parquet", parquet_path),
            ):
                products.append(
                    {
                        "format": format_name,
                        "relativePath": product.relative_to(staging).as_posix(),
                        "sha256": sha256_file(product),
                        "bytes": product.stat().st_size,
                    }
                )
            table_receipts.append(
                {
                    "tableId": table_id,
                    "rows": len(rows),
                    "columns": columns,
                    "columnTypes": type_map,
                    "recordIds": [str(row["recordId"]) for row in rows],
                    "canonicalRowsSha256": hashlib.sha256(
                        ("".join(canonical_json(row) + "\n" for row in normalized)).encode("utf-8")
                    ).hexdigest(),
                    "products": products,
                }
            )
        manifest = {
            "schema": MANIFEST_SCHEMA,
            "studyId": "Gate14Re-ME",
            "status": "COMPLETE_SCHEMA_V2_PER_OBSERVATION_DELIVERY",
            "profile": profile,
            "rawRootRelativePath": raw_root.relative_to(project_root).as_posix(),
            "outputSchemaRelativePath": output_schema_path.relative_to(project_root).as_posix(),
            "outputSchemaSha256": output_schema_sha256,
            "d3ContractRelativePath": d3_contract_path.relative_to(project_root).as_posix(),
            "d3ContractSha256": d3_contract_sha256,
            "typedParquetRuntimeManifestRelativePath": runtime_manifest_path.relative_to(project_root).as_posix(),
            "typedParquetRuntimeManifestSha256": runtime_manifest_sha256,
            "pyarrowVersion": str(runtime_manifest["distribution"]["version"]),
            "identityBindingSha256": identity_binding_sha256,
            "csvCellEncoding": "canonical-json-scalar",
            "jsonlGzipMtime": 0,
            "structuralValidation": structural_receipt,
            "tables": table_receipts,
            "rawProvenance": provenance,
            "aggregateOnlyPackage": False,
            "formalAnalysisAuthorized": False,
            "crossAlgorithmEffectsComputed": False,
            "rankingOrWinnerComputed": False,
        }
        manifest_path = staging / "delivery-manifest.v2.json"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        receipt = {
            "schema": RECEIPT_SCHEMA,
            "studyId": "Gate14Re-ME",
            "status": "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY",
            "deliveryManifestRelativePath": "delivery-manifest.v2.json",
            "deliveryManifestSha256": sha256_file(manifest_path),
            "completeValueTypeOrderRoundTripPassed": True,
            "typedParquetRoundTripPassed": True,
            "d3JoinsOneToOneAndComplete": True,
            "aggregateOnlyPackage": False,
            "formalAnalysisAuthorized": False,
            "crossAlgorithmEffectsComputed": False,
            "rankingOrWinnerComputed": False,
        }
        receipt_path = staging / "instrument-export-receipt.v2.json"
        receipt_path.write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        output_root.parent.mkdir(parents=True, exist_ok=True)
        staging.replace(output_root)
        return receipt
    except Exception:
        if staging.exists() and allowed_output_root(project_root, staging, profile):
            shutil.rmtree(staging, ignore_errors=True)
        raise


def validate_exported_d3_joins(
    tables: Mapping[str, Sequence[Mapping[str, Any]]], delivery_root: Path
) -> None:
    envelopes: Dict[str, List[structural.RowEnvelope]] = {
        table_id: [] for table_id in structural.RAW_TABLE_ORDER
    }
    for table_id in structural.RAW_TABLE_ORDER:
        for index, row in enumerate(tables[table_id], 1):
            clean = {
                key: value
                for key, value in row.items()
                if key not in {"_rawSourceRelativePath", "_rawSourceLine"}
            }
            envelopes[table_id].append(
                structural.RowEnvelope(table_id, delivery_root / table_id, index, clean)
            )
    try:
        structural.validate_d3_joins(envelopes)
        structural.validate_operations_semantics(envelopes)
    except structural.StructuralError as exc:
        raise DeliveryError(str(exc)) from exc


def verify_delivery(
    *,
    project_root: Path,
    delivery_root: Path,
    runtime_manifest_path: Path,
    runtime_manifest_sha256: str,
) -> Dict[str, Any]:
    project_root = project_root.resolve()
    delivery_root = delivery_root.resolve()
    if not delivery_root.is_dir() or not within(delivery_root, project_root):
        raise DeliveryError("delivery root is missing or outside project")
    manifest_path = delivery_root / "delivery-manifest.v2.json"
    receipt_path = delivery_root / "instrument-export-receipt.v2.json"
    manifest = read_json(manifest_path)
    receipt = read_json(receipt_path)
    if manifest.get("schema") != MANIFEST_SCHEMA or manifest.get("status") != "COMPLETE_SCHEMA_V2_PER_OBSERVATION_DELIVERY":
        raise DeliveryError("delivery manifest identity/status mismatch")
    if receipt.get("schema") != RECEIPT_SCHEMA or receipt.get("status") != "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY":
        raise DeliveryError("delivery receipt identity/status mismatch")
    if receipt.get("deliveryManifestSha256") != sha256_file(manifest_path):
        raise DeliveryError("delivery manifest hash mismatch in export receipt")
    if manifest.get("typedParquetRuntimeManifestSha256") != runtime_manifest_sha256:
        raise DeliveryError("delivery manifest typed-Parquet runtime hash mismatch")
    pa, pq, _ = import_pyarrow(
        project_root, runtime_manifest_path, runtime_manifest_sha256
    )
    table_items = manifest.get("tables")
    if not isinstance(table_items, list) or [item.get("tableId") for item in table_items] != list(structural.RAW_TABLE_ORDER):
        raise DeliveryError("delivery manifest table order/membership mismatch")
    tables: Dict[str, List[Dict[str, Any]]] = {}
    product_count = 0
    for item in table_items:
        table_id = str(item["tableId"])
        columns = item.get("columns")
        type_map = item.get("columnTypes")
        products = item.get("products")
        if not isinstance(columns, list) or not isinstance(type_map, dict) or not isinstance(products, list):
            raise DeliveryError(f"malformed table manifest: {table_id}")
        if set(type_map.values()) - TYPE_NAMES or set(type_map) != set(columns):
            raise DeliveryError(f"invalid table type map: {table_id}")
        by_format: Dict[str, Path] = {}
        for product in products:
            relative = product.get("relativePath")
            format_name = product.get("format")
            if not isinstance(relative, str) or not isinstance(format_name, str):
                raise DeliveryError(f"malformed product entry: {table_id}")
            path = (delivery_root / relative).resolve()
            if not within(path, delivery_root):
                raise DeliveryError(f"delivery product escapes root: {relative}")
            require_hash(path, str(product.get("sha256")), f"delivery product {relative}")
            if path.stat().st_size != product.get("bytes"):
                raise DeliveryError(f"delivery product byte count mismatch: {relative}")
            by_format[format_name] = path
            product_count += 1
        required_formats = {
            "canonical-jsonl",
            "rfc4180-csv-canonical-json-scalar-cells",
            "deterministic-jsonl-gzip",
            "typed-parquet",
        }
        if set(by_format) != required_formats:
            raise DeliveryError(f"delivery product format membership mismatch: {table_id}")
        canonical_rows = [row for _, row in read_jsonl(by_format["canonical-jsonl"])]
        if len(canonical_rows) != item.get("rows"):
            raise DeliveryError(f"delivery row count mismatch: {table_id}")
        expected_ids = [str(row.get("recordId")) for row in canonical_rows]
        if expected_ids != item.get("recordIds") or len(expected_ids) != len(set(expected_ids)):
            raise DeliveryError(f"delivery recordId order/uniqueness mismatch: {table_id}")
        canonical_digest = hashlib.sha256(
            ("".join(canonical_json(row) + "\n" for row in canonical_rows)).encode("utf-8")
        ).hexdigest()
        if canonical_digest != item.get("canonicalRowsSha256"):
            raise DeliveryError(f"canonical row digest mismatch: {table_id}")
        round_trip_validate(
            canonical_rows,
            columns,
            type_map,
            by_format["canonical-jsonl"],
            by_format["rfc4180-csv-canonical-json-scalar-cells"],
            by_format["deterministic-jsonl-gzip"],
            by_format["typed-parquet"],
            pa,
            pq,
        )
        tables[table_id] = canonical_rows
    for item in manifest.get("rawProvenance", []):
        relative = item.get("relativePath")
        raw_relative = manifest.get("rawRootRelativePath")
        if not isinstance(relative, str) or not isinstance(raw_relative, str):
            raise DeliveryError("malformed raw provenance entry")
        source = (project_root / raw_relative / relative).resolve()
        if not within(source, project_root / raw_relative):
            raise DeliveryError("raw provenance escapes raw root")
        require_hash(source, str(item.get("sha256")), f"raw provenance {relative}")
        if source.stat().st_size != item.get("bytes"):
            raise DeliveryError(f"raw provenance byte count mismatch: {relative}")
    validate_exported_d3_joins(tables, delivery_root)
    return {
        "schema": RECEIPT_SCHEMA,
        "studyId": "Gate14Re-ME",
        "status": "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY",
        "deliveryManifestSha256": sha256_file(manifest_path),
        "tables": len(table_items),
        "products": product_count,
        "completeValueTypeOrderRoundTripPassed": True,
        "typedParquetRoundTripPassed": True,
        "d3JoinsOneToOneAndComplete": True,
        "aggregateOnlyPackage": False,
        "crossAlgorithmEffectsComputed": False,
        "rankingOrWinnerComputed": False,
    }


def add_common_build_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--raw-root", "--measured-root", dest="raw_root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--output-schema", required=True)
    parser.add_argument("--output-schema-sha256", required=True)
    parser.add_argument("--d3-contract", required=True)
    parser.add_argument("--d3-contract-sha256", required=True)
    parser.add_argument("--typed-parquet-runtime-manifest", required=True)
    parser.add_argument("--typed-parquet-runtime-manifest-sha256", required=True)
    parser.add_argument("--identity-binding-sha256", required=True)
    parser.add_argument(
        "--profile",
        choices=("qualification-full", "synthetic-known-answer"),
        default="qualification-full",
    )


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build")
    add_common_build_arguments(build)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--project-root", required=True)
    verify.add_argument("--delivery-root", required=True)
    verify.add_argument("--typed-parquet-runtime-manifest", required=True)
    verify.add_argument("--typed-parquet-runtime-manifest-sha256", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        project_root = Path(args.project_root).resolve()
        if args.command == "build":
            result = build_delivery(
                project_root=project_root,
                raw_root=Path(args.raw_root),
                output_root=Path(args.output_root),
                output_schema_path=resolve_project_file(args.output_schema, project_root, "output schema"),
                output_schema_sha256=args.output_schema_sha256,
                d3_contract_path=resolve_project_file(args.d3_contract, project_root, "D3 contract"),
                d3_contract_sha256=args.d3_contract_sha256,
                runtime_manifest_path=resolve_project_file(args.typed_parquet_runtime_manifest, project_root, "typed-Parquet runtime manifest"),
                runtime_manifest_sha256=args.typed_parquet_runtime_manifest_sha256,
                identity_binding_sha256=args.identity_binding_sha256,
                profile=args.profile,
            )
        else:
            result = verify_delivery(
                project_root=project_root,
                delivery_root=Path(args.delivery_root),
                runtime_manifest_path=resolve_project_file(args.typed_parquet_runtime_manifest, project_root, "typed-Parquet runtime manifest"),
                runtime_manifest_sha256=args.typed_parquet_runtime_manifest_sha256,
            )
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (DeliveryError, structural.StructuralError) as exc:
        print(
            json.dumps(
                {"schema": TOOL_SCHEMA, "status": "FAIL_CLOSED", "reason": str(exc)},
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
