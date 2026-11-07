#!/usr/bin/env python3
"""Attempt-002 overlay for two legacy-to-v5 control-ledger source mappings.

This wrapper imports the sealed attempt-001 recovery adapter, preserves all of
its recovery-aware validation and frozen-base delegation, and adds exactly two
in-memory source-discovery mappings:

* replacement-ledger.raw.v1.jsonl -> _control/replacement-ledger.raw.v5.jsonl
* failures-and-voids.raw.v1.jsonl -> _control/failures-and-voids.raw.v5.jsonl

No source file is created, renamed, copied, edited, or deleted.  All scientific
raw-table, provenance, cardinality, join, typed-Parquet, and round-trip checks
remain delegated to the byte-bound frozen acceptance implementation.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Mapping, Sequence, Tuple


ADAPTER_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-acceptance-adapter-v2"
VALIDATION_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-acceptance-validation-v2"
AUTH_SCHEMA = "gate14re-me-formal-st-read-only-acceptance-authorization-v2"
CONTRACT_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-compatible-acceptance-contract-v2"

V1_ADAPTER = Path(
    "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/"
    "formal-st-read-only-acceptance-attempt-001/"
    "gate14re_me_formal_st_acceptance_attempt003_adapter_v1.py"
)
V1_ADAPTER_SHA256 = "b4a5774bcbbdc7b3b76bb5fc2050f61c8b90ecfb0ef9c3bac01d1a1501e79da9"

CONTROL_LEDGER_MAPPINGS: Dict[str, Dict[str, Any]] = {
    "replacement-ledger": {
        "legacyFileName": "replacement-ledger.raw.v1.jsonl",
        "sealedRelativePath": "_control/replacement-ledger.raw.v5.jsonl",
        "expectedRows": 0,
        "expectedSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    },
    "failures-and-voids": {
        "legacyFileName": "failures-and-voids.raw.v1.jsonl",
        "sealedRelativePath": "_control/failures-and-voids.raw.v5.jsonl",
        "expectedRows": 2,
        "expectedSha256": "fc36def2d515396256767a4105112bc3ac51e56b85d981a08e04bab610d5bd3b",
    },
}


class OverlayError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(8 * 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise OverlayError(message)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False)


def load_v1_adapter() -> Any:
    require(V1_ADAPTER.is_file(), f"missing sealed v1 adapter: {V1_ADAPTER}")
    require(
        sha256_file(V1_ADAPTER) == V1_ADAPTER_SHA256,
        "sealed v1 adapter SHA-256 mismatch",
    )
    spec = importlib.util.spec_from_file_location(
        "gate14re_me_formal_st_acceptance_attempt003_adapter_v1_sealed",
        V1_ADAPTER,
    )
    require(spec is not None and spec.loader is not None, "unable to load sealed v1 adapter")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def configure_v1(v1: Any) -> None:
    wrapper_path = Path(__file__).resolve(strict=True)
    v1.__file__ = os.fspath(wrapper_path)
    v1.ADAPTER_SCHEMA = ADAPTER_SCHEMA
    v1.VALIDATION_SCHEMA = VALIDATION_SCHEMA
    v1.AUTH_SCHEMA = AUTH_SCHEMA
    v1.CONTRACT_SCHEMA = CONTRACT_SCHEMA

    original_validate = v1.validate_recovery_compatibility
    original_loader = v1.load_base_tool

    def validate_recovery_compatibility_v2(args: Any) -> Tuple[Dict[str, Any], Dict[str, Path]]:
        receipt, paths = original_validate(args)
        receipt = dict(receipt)
        scope = list(receipt.get("compatibilityProjectionScope", []))
        scope.extend(
            [
                "legacy replacement-ledger table source mapped in memory to the sealed v5 control ledger; zero rows required",
                "legacy failures-and-voids table source mapped in memory to the sealed v5 control ledger; exactly two resolved technical rows retained",
            ]
        )
        receipt["schema"] = VALIDATION_SCHEMA
        receipt["compatibilityProjectionScope"] = scope
        receipt["controlLedgerSourceMappings"] = CONTROL_LEDGER_MAPPINGS
        receipt["priorAcceptanceAttempt001RetryPerformed"] = False
        receipt["acceptanceAttempt"] = "attempt-002"
        return receipt, paths

    def load_base_tool_v2(path: Path) -> Any:
        base = original_loader(path)
        original_discover = base.discover_table_sources
        original_write_json = base.write_json

        def discover_table_sources_v2(
            raw_root: Path,
            table_id: str,
            spec: Mapping[str, Any],
            sealed_entries: Mapping[str, Mapping[str, Any]],
        ) -> Sequence[Path]:
            mapping = CONTROL_LEDGER_MAPPINGS.get(table_id)
            if mapping is None:
                return original_discover(raw_root, table_id, spec, sealed_entries)
            legacy_name = mapping["legacyFileName"]
            if spec.get("fileName") != legacy_name:
                raise base.DeliveryError(
                    f"control-ledger compatibility source contract mismatch for {table_id}: "
                    f"{spec.get('fileName')} != {legacy_name}"
                )
            root = Path(raw_root).resolve(strict=True)
            relative = mapping["sealedRelativePath"]
            actual = (root / relative).resolve(strict=False)
            try:
                actual.relative_to(root)
            except ValueError as exc:
                raise base.DeliveryError(
                    f"mapped control-ledger source escapes measured root: {table_id}: {relative}"
                ) from exc
            if not actual.is_file():
                raise base.DeliveryError(f"mapped control-ledger source is missing: {table_id}: {relative}")
            if relative not in sealed_entries:
                raise base.DeliveryError(
                    f"mapped control-ledger source absent from sealed inventory: {table_id}: {relative}"
                )
            return [actual]

        def write_json_v2(path_to_write: Path, value: Mapping[str, Any]) -> None:
            target = Path(path_to_write)
            payload: Mapping[str, Any] = value
            if target.name == "recovery-compatibility-validation.v1.json":
                target = target.with_name("recovery-compatibility-validation.v2.json")
                enriched = dict(value)
                enriched["schema"] = VALIDATION_SCHEMA
                enriched["controlLedgerSourceMappings"] = CONTROL_LEDGER_MAPPINGS
                enriched["acceptanceAttempt"] = "attempt-002"
                payload = enriched
            original_write_json(target, payload)

        base.discover_table_sources = discover_table_sources_v2
        base.write_json = write_json_v2
        return base

    v1.validate_recovery_compatibility = validate_recovery_compatibility_v2
    v1.load_base_tool = load_base_tool_v2


def load_minimal_sealed_entries(v1: Any, manifest_path: Path, raw_root: Path) -> Dict[str, Dict[str, Any]]:
    manifest = v1.read_json(manifest_path, "acquisition freeze manifest")
    require(
        manifest.get("schema") == "gate14re-me-formal-st-acquisition-freeze-manifest-v5"
        and manifest.get("status") == "SEALED_ACQUISITION_RAW_ACCEPTANCE_PENDING"
        and manifest.get("artifactCount") == 108007,
        "acquisition freeze manifest header mismatch",
    )
    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list), "acquisition freeze manifest artifacts are malformed")
    wanted = {item["sealedRelativePath"] for item in CONTROL_LEDGER_MAPPINGS.values()}
    selected: Dict[str, Dict[str, Any]] = {}
    for item in artifacts:
        if not isinstance(item, dict):
            continue
        relative = item.get("relativePath")
        if relative not in wanted:
            continue
        require(relative not in selected, f"duplicate mapped control-ledger seal entry: {relative}")
        length = item.get("lengthBytes")
        digest = item.get("sha256")
        require(isinstance(length, int) and length >= 0, f"invalid sealed byte length: {relative}")
        require(isinstance(digest, str) and len(digest) == 64, f"invalid sealed SHA-256: {relative}")
        source = raw_root / relative
        require(source.is_file(), f"mapped source missing during preflight: {relative}")
        require(source.stat().st_size == length, f"mapped source byte length mismatch: {relative}")
        require(sha256_file(source) == digest, f"mapped source SHA-256 mismatch: {relative}")
        selected[relative] = {"bytes": length, "sha256": digest}
    require(set(selected) == wanted, "mapped control-ledger entries are incomplete in the acquisition seal")
    return selected


def run_mapping_preflight(v1: Any) -> int:
    args = v1.parse_args()
    receipt, paths = v1.validate_recovery_compatibility(args)
    base = v1.load_base_tool(paths["base_tool"])
    schema_path = Path(args.output_schema).resolve(strict=True)
    specs = base.load_specs(schema_path)
    sealed_entries = load_minimal_sealed_entries(
        v1,
        Path(args.seal_manifest).resolve(strict=True),
        paths["raw_root"],
    )
    profiles = []
    for table_id in ("replacement-ledger", "failures-and-voids"):
        sources = base.discover_table_sources(
            paths["raw_root"], table_id, specs[table_id], sealed_entries
        )
        profile = base.first_pass_profile(
            paths["raw_root"],
            table_id,
            specs[table_id],
            sources,
            sealed_entries,
            {},
            {"d3": set(), "event": set(), "empty": set()},
        )
        expected_rows = CONTROL_LEDGER_MAPPINGS[table_id]["expectedRows"]
        require(len(sources) == 1, f"mapped source cardinality mismatch: {table_id}")
        require(profile.row_count == expected_rows, f"mapped row cardinality mismatch: {table_id}")
        profiles.append(
            {
                "tableId": table_id,
                "legacyFileName": CONTROL_LEDGER_MAPPINGS[table_id]["legacyFileName"],
                "sealedRelativePath": CONTROL_LEDGER_MAPPINGS[table_id]["sealedRelativePath"],
                "sourceCount": len(sources),
                "rowCount": profile.row_count,
                "sourceBytes": profile.source_bytes,
                "sourceManifestDigest": profile.source_manifest_digest,
                "sealedSha256": CONTROL_LEDGER_MAPPINGS[table_id]["expectedSha256"],
            }
        )
    result = {
        "schema": "gate14re-me-formal-st-control-ledger-source-mapping-preflight-v1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_EXACT_TWO_CONTROL_LEDGER_SOURCE_MAPPINGS",
        "acceptanceAttempt": "attempt-002",
        "sourceAcquisitionAttempt": "attempt-003",
        "tables": profiles,
        "sourceMeasuredRootWriteBack": False,
        "formalAnalysisAuthorized": False,
        "formalAnalysisPerformed": False,
        "effectInterpretationPerformed": False,
        "baseRecoveryCompatibilityPreflightStatus": receipt["status"],
    }
    print(canonical_json(result))
    return 0


def main() -> int:
    mapping_flag = "--control-table-mapping-preflight-only" in sys.argv
    if mapping_flag:
        sys.argv = [item for item in sys.argv if item != "--control-table-mapping-preflight-only"]
        if "--preflight-only" in sys.argv or "--control-validation-only" in sys.argv:
            raise OverlayError("mapping preflight cannot be combined with another preflight mode")
    v1 = load_v1_adapter()
    configure_v1(v1)
    if mapping_flag:
        return run_mapping_preflight(v1)
    return int(v1.main())


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        failure = {
            "schema": ADAPTER_SCHEMA,
            "status": "FAIL_CLOSED_CONTROL_LEDGER_SOURCE_MAPPING_OVERLAY",
            "errorType": type(exc).__name__,
            "error": str(exc),
            "sourceMutationPerformed": False,
            "formalAnalysisPerformed": False,
            "sameAttemptRetryPermitted": False,
        }
        print(canonical_json(failure), file=sys.stderr)
        raise SystemExit(2)
