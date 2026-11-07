#!/usr/bin/env python3
"""Run the Gate14Re-ME verification-only exporter known-answer controls."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Mapping, Sequence


EXPECTED_OUTPUT_RELATIVE = Path("Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/python-export")
EXPECTED_PACKAGES_RELATIVE = Path("Research/Gate14Re-ME/Runtime/v1/python-packages")
EXPECTED_RUNTIME_MANIFEST_RELATIVE = Path("Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json")
EXPECTED_IMPLEMENTATION_MANIFEST_SHA256 = "9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4"
EXPECTED_DELIVERY_RELATIVE = Path("Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v1.py")


class KnownAnswerError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise KnownAnswerError(f"JSON object required: {path}")
    return value


def require_hash(path: Path, expected: str, label: str) -> None:
    if len(expected) != 64 or sha256_file(path) != expected.lower():
        raise KnownAnswerError(f"{label} SHA-256 mismatch")


def within(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def verify_authorization(value: Mapping[str, Any]) -> None:
    if value.get("schema") != "gate14re-me-runtime-qualification-authorization-v1" or value.get("studyId") != "Gate14Re-ME" or value.get("status") != "AUTHORIZED_RUNTIME_QUALIFICATION_ONLY":
        raise KnownAnswerError("runtime authorization identity/status mismatch")
    allowed = value.get("authorizedScope", {})
    if not all(allowed.get(key) is True for key in (
        "installTypedParquetEngine", "freezeTypedParquetEngine", "compileFrozenUnityImplementation",
        "runD2GridReadProxyKnownAnswer", "runD3AllocationCounterKnownAnswer",
        "runD4PersistentStateSizerKnownAnswer", "runClockMonotonicityKnownAnswer", "runDataExporterKnownAnswer",
    )):
        raise KnownAnswerError("runtime authorization positive scope incomplete")
    prohibited = value.get("prohibitedScope", {})
    if not all(prohibited.get(key) is False for key in (
        "qualificationScheduleGeneration", "qualificationInputGeneration", "anonymousIdentityMapGeneration",
        "qualificationMeasuredRootCreation", "algorithmLaneExecution", "formalInputGeneration",
        "formalMeasuredRootCreation", "formalCollection", "formalAnalysis", "algorithmRanking", "winnerAdjudication",
    )):
        raise KnownAnswerError("runtime authorization widens into prohibited scope")


def require_prohibited_roots_absent(project_root: Path) -> None:
    for relative in (
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ):
        if (project_root / relative).exists():
            raise KnownAnswerError(f"prohibited root exists: {relative}")


def load_source_namespace(path: Path, name: str) -> Dict[str, Any]:
    namespace: Dict[str, Any] = {"__name__": name, "__file__": str(path)}
    exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), namespace)
    return namespace


def write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    temporary = path.with_name(path.name + f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--runtime-authorization", required=True)
    parser.add_argument("--runtime-authorization-sha256", required=True)
    parser.add_argument("--implementation-manifest", required=True)
    parser.add_argument("--implementation-manifest-sha256", required=True)
    parser.add_argument("--runtime-manifest", required=True)
    parser.add_argument("--runtime-manifest-sha256", required=True)
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        project_root = Path(args.project_root).resolve()
        authorization_path = Path(args.runtime_authorization).resolve()
        implementation_manifest_path = Path(args.implementation_manifest).resolve()
        runtime_manifest_path = Path(args.runtime_manifest).resolve()
        output_dir = Path(args.output_dir).resolve()
        if output_dir != (project_root / EXPECTED_OUTPUT_RELATIVE).resolve() or not within(output_dir, project_root):
            raise KnownAnswerError("export known-answer output differs from the exact verification-only path")
        if output_dir.exists():
            raise KnownAnswerError("export known-answer output already exists; overwrite/resume is prohibited")
        if runtime_manifest_path != (project_root / EXPECTED_RUNTIME_MANIFEST_RELATIVE).resolve():
            raise KnownAnswerError("runtime manifest path mismatch")
        require_hash(authorization_path, args.runtime_authorization_sha256, "runtime authorization")
        require_hash(implementation_manifest_path, args.implementation_manifest_sha256, "implementation manifest")
        require_hash(runtime_manifest_path, args.runtime_manifest_sha256, "typed-Parquet runtime manifest")
        if args.implementation_manifest_sha256.lower() != EXPECTED_IMPLEMENTATION_MANIFEST_SHA256:
            raise KnownAnswerError("unexpected frozen implementation manifest")
        authorization = read_json(authorization_path)
        verify_authorization(authorization)
        if authorization.get("priorSourceFreeze", {}).get("implementationManifestSha256") != EXPECTED_IMPLEMENTATION_MANIFEST_SHA256:
            raise KnownAnswerError("authorization implementation binding mismatch")
        require_prohibited_roots_absent(project_root)

        freeze_tool_path = project_root / "Research/Gate14Re-ME/Tools/freeze_gate14re_me_typed_parquet_runtime_v1.py"
        freeze_namespace = load_source_namespace(freeze_tool_path, "gate14re_me_runtime_freeze_verify")
        freeze_namespace["verify_manifest"](project_root, runtime_manifest_path)

        packages_root = (project_root / EXPECTED_PACKAGES_RELATIVE).resolve()
        sys.path.insert(0, str(packages_root))
        import pyarrow as pa  # type: ignore
        import pyarrow.parquet as pq  # type: ignore

        if pa.__version__ != "25.0.1" or not within(Path(pa.__file__), packages_root):
            raise KnownAnswerError("pyarrow version or import origin mismatch")
        implementation_manifest = read_json(implementation_manifest_path)
        delivery_entries = [entry for entry in implementation_manifest.get("artifacts", []) if entry.get("relativePath") == EXPECTED_DELIVERY_RELATIVE.as_posix()]
        if len(delivery_entries) != 1:
            raise KnownAnswerError("frozen delivery source is absent from implementation manifest")
        delivery_path = (project_root / EXPECTED_DELIVERY_RELATIVE).resolve()
        require_hash(delivery_path, str(delivery_entries[0].get("sha256", "")), "frozen delivery source")
        delivery = load_source_namespace(delivery_path, "gate14re_me_frozen_delivery_known_answer")
        base = delivery["self_test"]()
        if base.get("status") != "PASS_SOURCE_LEVEL_CONTROLS_PARQUET_AVAILABLE" or base.get("typedParquetEngineAvailable") is not True:
            raise KnownAnswerError("frozen delivery source did not discover the frozen typed-Parquet engine")
        for field in (
            "jsonlCsvGzipRoundTripPassed", "tamperNegativeTestPassed", "missingNegativeTestPassed",
            "duplicateNegativeTestPassed", "anonymousLabelSwapNegativeTestPassed",
        ):
            if base.get(field) is not True:
                raise KnownAnswerError(f"delivery source-level control failed: {field}")

        output_dir.mkdir(parents=False, exist_ok=False)
        rows = [
            {"recordId": "known-r0", "anonymousLaneId": "ALG-A", "valueInt": 0, "valueFloat": 0.0, "valid": True, "nullableText": None},
            {"recordId": "known-r1", "anonymousLaneId": "ALG-F", "valueInt": 7, "valueFloat": 1.25, "valid": False, "nullableText": "x"},
        ]
        columns = ["recordId", "anonymousLaneId", "valueInt", "valueFloat", "valid", "nullableText"]
        jsonl_path = output_dir / "known-answer.v1.jsonl"
        gzip_path = output_dir / "known-answer.v1.jsonl.gz"
        csv_path = output_dir / "known-answer.v1.csv"
        parquet_path = output_dir / "known-answer.v1.parquet"
        delivery["write_jsonl"](jsonl_path, rows)
        delivery["write_jsonl_gzip"](gzip_path, rows)
        delivery["write_csv"](csv_path, rows, columns)
        delivery["write_parquet"](parquet_path, rows, columns)
        delivery["assert_round_trip"](["known-r0", "known-r1"], jsonl_path, gzip_path, csv_path, parquet_path)
        table = pq.read_table(parquet_path)
        expected_schema = {
            "recordId": "string",
            "anonymousLaneId": "string",
            "valueInt": "int64",
            "valueFloat": "double",
            "valid": "bool",
            "nullableText": "string",
        }
        actual_schema = {field.name: str(field.type) for field in table.schema}
        if actual_schema != expected_schema or table.num_rows != 2 or table.column("nullableText").null_count != 1:
            raise KnownAnswerError("typed-Parquet schema, row count, or null preservation mismatch")
        products = []
        for path in (jsonl_path, gzip_path, csv_path, parquet_path):
            products.append({"relativePath": path.relative_to(project_root).as_posix(), "sha256": sha256_file(path), "bytes": path.stat().st_size})
        receipt = {
            "schema": "gate14re-me-runtime-export-known-answer-receipt-v1",
            "studyId": "Gate14Re-ME",
            "authorizationId": authorization["authorizationId"],
            "status": "PASS_TYPED_PARQUET_AND_EXPORT_KNOWN_ANSWER",
            "pyarrowVersion": pa.__version__,
            "pyarrowImportRelativePath": Path(pa.__file__).resolve().relative_to(project_root).as_posix(),
            "typedParquetRoundTripPassed": True,
            "typedParquetSchemaPassed": True,
            "typedParquetNullPreservationPassed": True,
            "jsonlCsvGzipRoundTripPassed": True,
            "tamperNegativeTestPassed": True,
            "missingNegativeTestPassed": True,
            "duplicateNegativeTestPassed": True,
            "anonymousLabelSwapNegativeTestPassed": True,
            "knownAnswerRows": 2,
            "expectedParquetSchema": expected_schema,
            "products": products,
            "implementationManifestSha256": args.implementation_manifest_sha256.lower(),
            "runtimeManifestSha256": args.runtime_manifest_sha256.lower(),
            "runtimeAuthorizationSha256": args.runtime_authorization_sha256.lower(),
            "qualificationScheduleRows": 0,
            "qualificationInputs": 0,
            "anonymousIdentityMappings": 0,
            "qualificationObservationCount": 0,
            "algorithmLanes": 0,
            "formalObservationCount": 0,
            "formalAnalysisPerformed": False,
            "rankingOrWinnerComputed": False,
            "createdAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        write_json_atomic(output_dir / "export-runtime-receipt.v1.json", receipt)
        print(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"schema": "gate14re-me-runtime-export-known-answer-receipt-v1", "status": "FAIL_CLOSED", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
