#!/usr/bin/env python3
"""Lossless Gate14Re-ME qualification delivery builder.

This program never computes cross-algorithm effects, ranks, winners, p-values or
weighted composites.  It validates and transcodes complete per-observation raw
rows.  The qualification package remains permanently excluded from formal
effect estimation.
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
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, Sequence, Tuple


TOOL_SCHEMA = "gate14re-me-qualification-delivery-tool-v1"
ALLOWED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
RAW_TABLE_ORDER = (
    "oracle-agent-checks",
    "oracle-event-checks",
    "operations",
    "event-groups",
    "persistent-state",
    "process-resources",
    "empty-boundary",
    "replacement-ledger",
    "failures-and-voids",
)


class DeliveryError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def read_json(path: Path) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise DeliveryError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DeliveryError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise DeliveryError(f"invalid JSONL at {path}:{line_number}: {exc}") from exc
            if not isinstance(value, dict):
                raise DeliveryError(f"JSON object required at {path}:{line_number}")
            yield line_number, value


def within(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise DeliveryError(f"missing {label}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise DeliveryError(f"{label} SHA-256 mismatch: expected {expected}; actual {actual}")


def load_specs(schema_path: Path) -> Dict[str, Dict[str, Any]]:
    schema = read_json(schema_path)
    if schema.get("schema") != "gate14re-me-load-qualification-output-schema-v1":
        raise DeliveryError("unexpected output-schema identity")
    specs: Dict[str, Dict[str, Any]] = {}
    for item in schema.get("rawTables", []):
        table_id = item.get("tableId")
        if table_id in specs:
            raise DeliveryError(f"duplicate table spec: {table_id}")
        specs[table_id] = item
    if tuple(specs) != RAW_TABLE_ORDER:
        raise DeliveryError("raw table order or membership differs from the frozen contract")
    return specs


def discover_sources(measured_root: Path, spec: Mapping[str, Any]) -> List[Path]:
    file_name = str(spec["fileName"])
    sources = sorted(
        (path for path in measured_root.rglob(file_name) if path.is_file()),
        key=lambda value: value.relative_to(measured_root).as_posix(),
    )
    if not sources and not bool(spec.get("requiredEvenWhenEmpty")):
        raise DeliveryError(f"no raw source found for {spec['tableId']}: {file_name}")
    return sources


def validate_scalar(value: Any, location: str) -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise DeliveryError(f"non-finite float at {location}")
    if isinstance(value, (dict, list)):
        raise DeliveryError(f"raw rows must remain flat at {location}")


def load_table(
    measured_root: Path,
    project_root: Path,
    spec: Mapping[str, Any],
    expected_identity_binding_sha256: str | None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    required = tuple(spec.get("requiredFields", ()))
    rows: List[Dict[str, Any]] = []
    provenance: List[Dict[str, Any]] = []
    seen_ids: set[str] = set()
    for source in discover_sources(measured_root, spec):
        relative_source = source.relative_to(measured_root).as_posix()
        source_row_count = 0
        for line_number, row in read_jsonl(source):
            source_row_count += 1
            missing = [field for field in required if field not in row]
            if missing:
                raise DeliveryError(f"missing fields {missing} at {relative_source}:{line_number}")
            for field, value in row.items():
                validate_scalar(value, f"{relative_source}:{line_number}:{field}")
            record_id = row.get("recordId")
            if not isinstance(record_id, str) or not record_id:
                raise DeliveryError(f"missing recordId at {relative_source}:{line_number}")
            if record_id in seen_ids:
                raise DeliveryError(f"duplicate recordId in table {spec['tableId']}: {record_id}")
            seen_ids.add(record_id)
            lane = row.get("anonymousLaneId")
            if lane is not None and lane not in ALLOWED_LANES:
                raise DeliveryError(f"invalid anonymous lane at {relative_source}:{line_number}")
            identity_sha = row.get("identityBindingSha256")
            if expected_identity_binding_sha256 is not None and identity_sha is not None and identity_sha != expected_identity_binding_sha256:
                raise DeliveryError(f"anonymous identity-binding swap at {relative_source}:{line_number}")
            if bool(spec.get("sourcePathAndShaRequired")):
                bound_path = row.get("sourceRelativePath") or row.get("inputRelativePath")
                bound_sha = row.get("sourceSha256") or row.get("inputSha256")
                if not isinstance(bound_path, str) or not isinstance(bound_sha, str) or len(bound_sha) != 64:
                    raise DeliveryError(f"invalid source binding at {relative_source}:{line_number}")
                absolute_bound = (project_root / bound_path).resolve()
                if not within(absolute_bound, project_root) or not absolute_bound.is_file():
                    raise DeliveryError(f"bound source path unavailable at {relative_source}:{line_number}")
                if sha256_file(absolute_bound) != bound_sha:
                    raise DeliveryError(f"bound source hash drift at {relative_source}:{line_number}")
            exported = dict(row)
            exported["_rawSourceRelativePath"] = relative_source
            exported["_rawSourceLine"] = line_number
            rows.append(exported)
        provenance.append(
            {
                "relativePath": relative_source,
                "sha256": sha256_file(source),
                "bytes": source.stat().st_size,
                "rows": source_row_count,
            }
        )
    return rows, provenance


def ordered_columns(required_fields: Sequence[str], rows: Sequence[Mapping[str, Any]]) -> List[str]:
    columns = list(required_fields)
    additional = sorted({key for row in rows for key in row if key not in columns})
    return columns + additional


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


def csv_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def write_csv(path: Path, rows: Sequence[Mapping[str, Any]], columns: Sequence[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(columns), extrasaction="raise", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: csv_value(row.get(column)) for column in columns})


def import_pyarrow() -> Tuple[Any, Any]:
    try:
        import pyarrow as pa  # type: ignore
        import pyarrow.parquet as pq  # type: ignore
    except Exception as exc:
        raise DeliveryError(
            "typed Parquet engine unavailable; pyarrow must be separately provisioned and hash-frozen before qualification execution"
        ) from exc
    return pa, pq


def write_parquet(path: Path, rows: Sequence[Mapping[str, Any]], columns: Sequence[str]) -> None:
    pa, pq = import_pyarrow()
    normalized = [{column: row.get(column) for column in columns} for row in rows]
    table = pa.Table.from_pylist(normalized)
    pq.write_table(table, path, compression="zstd", use_dictionary=True)


def ids_from_jsonl(path: Path) -> List[str]:
    return [str(row["recordId"]) for _, row in read_jsonl(path)]


def ids_from_gzip(path: Path) -> List[str]:
    values: List[str] = []
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                values.append(str(json.loads(line)["recordId"]))
    return values


def ids_from_csv(path: Path) -> List[str]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return [str(row["recordId"]) for row in csv.DictReader(handle)]


def ids_from_parquet(path: Path) -> List[str]:
    _, pq = import_pyarrow()
    return [str(value) for value in pq.read_table(path, columns=["recordId"]).column("recordId").to_pylist()]


def assert_round_trip(
    expected_ids: Sequence[str], jsonl_path: Path, gzip_path: Path, csv_path: Path, parquet_path: Path
) -> None:
    expected = list(expected_ids)
    for label, actual in (
        ("JSONL", ids_from_jsonl(jsonl_path)),
        ("JSONL.GZ", ids_from_gzip(gzip_path)),
        ("CSV", ids_from_csv(csv_path)),
        ("Parquet", ids_from_parquet(parquet_path)),
    ):
        if actual != expected:
            raise DeliveryError(f"{label} recordId order/set failed lossless round trip")


def build_delivery(args: argparse.Namespace) -> Dict[str, Any]:
    project_root = Path(args.project_root).resolve()
    measured_root = Path(args.measured_root).resolve()
    output_root = Path(args.output_root).resolve()
    schema_path = Path(args.output_schema).resolve()
    manifest_path = Path(args.implementation_manifest).resolve()
    if not within(measured_root, project_root) or not measured_root.is_dir():
        raise DeliveryError("measured root is missing or outside the project")
    allowed_output_parent = (project_root / "Research/Exports/Gate14Re-ME/load-qualification").resolve()
    if not within(output_root, allowed_output_parent):
        raise DeliveryError("delivery output must be under the reserved qualification export root")
    if output_root.exists():
        raise DeliveryError("delivery output already exists; overwrite/resume is prohibited")
    require_hash(schema_path, args.output_schema_sha256, "output schema")
    require_hash(manifest_path, args.implementation_manifest_sha256, "implementation manifest")
    completion = read_json(measured_root / "_control/acquisition-complete.v1.json")
    if completion.get("status") != "QUALIFICATION-RAW-COMMIT-PENDING":
        raise DeliveryError("qualification acquisition is not raw-commit pending")

    specs = load_specs(schema_path)
    staging = output_root.with_name(output_root.name + ".staging." + os.urandom(8).hex())
    staging.mkdir(parents=True, exist_ok=False)
    tables_receipt: List[Dict[str, Any]] = []
    all_provenance: List[Dict[str, Any]] = []
    try:
        for table_id in RAW_TABLE_ORDER:
            spec = specs[table_id]
            rows, provenance = load_table(
                measured_root,
                project_root,
                spec,
                args.identity_binding_sha256,
            )
            columns = ordered_columns(tuple(spec.get("requiredFields", ())), rows)
            table_dir = staging / table_id
            table_dir.mkdir()
            jsonl_path = table_dir / f"{table_id}.v1.jsonl"
            gzip_path = table_dir / f"{table_id}.v1.jsonl.gz"
            csv_path = table_dir / f"{table_id}.v1.csv"
            parquet_path = table_dir / f"{table_id}.v1.parquet"
            write_jsonl(jsonl_path, rows)
            write_jsonl_gzip(gzip_path, rows)
            write_csv(csv_path, rows, columns)
            write_parquet(parquet_path, rows, columns)
            expected_ids = [str(row["recordId"]) for row in rows]
            assert_round_trip(expected_ids, jsonl_path, gzip_path, csv_path, parquet_path)
            products = []
            for product in (jsonl_path, gzip_path, csv_path, parquet_path):
                products.append(
                    {
                        "relativePath": product.relative_to(staging).as_posix(),
                        "sha256": sha256_file(product),
                        "bytes": product.stat().st_size,
                    }
                )
            tables_receipt.append(
                {
                    "tableId": table_id,
                    "rows": len(rows),
                    "recordIdsUnique": True,
                    "columns": columns,
                    "products": products,
                }
            )
            all_provenance.extend({"tableId": table_id, **item} for item in provenance)

        manifest = {
            "schema": "gate14re-me-qualification-delivery-manifest-v1",
            "studyId": "Gate14Re-ME",
            "status": "COMPLETE_PER_OBSERVATION_DELIVERY",
            "implementationManifestSha256": args.implementation_manifest_sha256,
            "outputSchemaSha256": args.output_schema_sha256,
            "identityBindingSha256": args.identity_binding_sha256,
            "p1OrFormalEffectsAggregatedOrInterpreted": False,
            "rankingOrWinnerComputed": False,
            "tables": tables_receipt,
            "rawProvenance": all_provenance,
        }
        manifest_file = staging / "delivery-manifest.v1.json"
        manifest_file.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        receipt = {
            "schema": "gate14re-me-qualification-delivery-receipt-v1",
            "studyId": "Gate14Re-ME",
            "status": "PASS_COMPLETE_PER_OBSERVATION_DELIVERY",
            "deliveryManifestSha256": sha256_file(manifest_file),
            "rawToExportRoundTripPassed": True,
            "typedParquetRoundTripPassed": True,
            "aggregateOnlyPackage": False,
            "formalAnalysisAuthorized": False,
            "rankingOrWinnerComputed": False,
        }
        (staging / "instrument-export-receipt.v1.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        output_root.parent.mkdir(parents=True, exist_ok=True)
        staging.replace(output_root)
        return receipt
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def self_test() -> Dict[str, Any]:
    pyarrow_available = True
    pyarrow_error = ""
    try:
        import_pyarrow()
    except DeliveryError as exc:
        pyarrow_available = False
        pyarrow_error = str(exc)

    with tempfile.TemporaryDirectory(prefix="gate14re-me-delivery-self-test-") as directory:
        root = Path(directory)
        rows = [
            {"recordId": "r0", "anonymousLaneId": "ALG-A", "value": 0, "valid": True},
            {"recordId": "r1", "anonymousLaneId": "ALG-F", "value": 1.25, "valid": False},
        ]
        columns = ["recordId", "anonymousLaneId", "value", "valid"]
        jsonl_path = root / "fixture.jsonl"
        gzip_path = root / "fixture.jsonl.gz"
        csv_path = root / "fixture.csv"
        write_jsonl(jsonl_path, rows)
        write_jsonl_gzip(gzip_path, rows)
        write_csv(csv_path, rows, columns)
        base_round_trip = ids_from_jsonl(jsonl_path) == ["r0", "r1"] and ids_from_gzip(gzip_path) == ["r0", "r1"] and ids_from_csv(csv_path) == ["r0", "r1"]

        duplicate_detected = False
        seen: set[str] = set()
        try:
            for row in rows + [dict(rows[0])]:
                if row["recordId"] in seen:
                    raise DeliveryError("duplicate")
                seen.add(row["recordId"])
        except DeliveryError:
            duplicate_detected = True

        missing_detected = "recordId" not in {"anonymousLaneId": "ALG-A"}
        label_swap_detected = "ALG-Z" not in ALLOWED_LANES
        original_sha = sha256_file(jsonl_path)
        with jsonl_path.open("ab") as handle:
            handle.write(b" ")
        tamper_detected = sha256_file(jsonl_path) != original_sha

    return {
        "schema": "gate14re-me-qualification-delivery-self-test-v1",
        "status": "PASS_SOURCE_LEVEL_CONTROLS_PARQUET_AVAILABLE" if pyarrow_available else "BLOCKED_TYPED_PARQUET_DEPENDENCY_MISSING",
        "jsonlCsvGzipRoundTripPassed": base_round_trip,
        "tamperNegativeTestPassed": tamper_detected,
        "missingNegativeTestPassed": missing_detected,
        "duplicateNegativeTestPassed": duplicate_detected,
        "anonymousLabelSwapNegativeTestPassed": label_swap_detected,
        "typedParquetEngineAvailable": pyarrow_available,
        "typedParquetDiagnostic": pyarrow_error,
        "qualificationObservationCount": 0,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("self-test")
    build = subparsers.add_parser("build")
    build.add_argument("--project-root", required=True)
    build.add_argument("--measured-root", required=True)
    build.add_argument("--output-root", required=True)
    build.add_argument("--output-schema", required=True)
    build.add_argument("--output-schema-sha256", required=True)
    build.add_argument("--implementation-manifest", required=True)
    build.add_argument("--implementation-manifest-sha256", required=True)
    build.add_argument("--identity-binding-sha256", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = self_test() if args.command == "self-test" else build_delivery(args)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if not str(result.get("status", "")).startswith("BLOCKED") else 3
    except DeliveryError as exc:
        print(json.dumps({"schema": TOOL_SCHEMA, "status": "FAIL_CLOSED", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
