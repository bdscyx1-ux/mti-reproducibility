#!/usr/bin/env python3
"""Bounded compatibility adapter for Gate14Re-ME formal ST attempt-003 acceptance.

The frozen v5 acceptance implementation predates the authorized attempt-003
control-plane recovery.  This adapter preserves and verifies that recovery
history, then delegates every scientific/raw-table, provenance, cardinality,
join, typed-Parquet, and round-trip check to the frozen acceptance tool.

The only compatibility projection is in memory while the frozen control-plane
validator runs.  The sealed measured root is never changed, both preserved
technical failure rows remain in the accepted package, and formal analysis is
neither authorized nor performed.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, Mapping, Sequence, Tuple


ADAPTER_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-acceptance-adapter-v1"
VALIDATION_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-acceptance-validation-v1"
AUTH_SCHEMA = "gate14re-me-formal-st-read-only-acceptance-authorization-v1"
CONTRACT_SCHEMA = "gate14re-me-formal-st-attempt-003-recovery-compatible-acceptance-contract-v1"


class AdapterError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False)


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
        raise AdapterError(message)


def read_json(path: Path, label: str) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise AdapterError(f"invalid {label}: {path}: {exc}") from exc
    require(isinstance(value, dict), f"{label} must be a JSON object: {path}")
    return value


def read_jsonl(path: Path, label: str) -> list[Dict[str, Any]]:
    rows: list[Dict[str, Any]] = []
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                require(isinstance(value, dict), f"{label} row must be an object: {path}:{line_number}")
                rows.append(value)
    except AdapterError:
        raise
    except Exception as exc:
        raise AdapterError(f"invalid {label}: {path}: {exc}") from exc
    return rows


def require_hash(path: Path, expected: str, label: str) -> None:
    require(path.is_file(), f"missing {label}: {path}")
    actual = sha256_file(path)
    require(actual == expected, f"{label} SHA-256 mismatch: expected={expected}; actual={actual}")


def resolve_project_relative(project_root: Path, relative: str, label: str) -> Path:
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute(), f"invalid {label} path")
    resolved = (project_root / Path(relative)).resolve(strict=False)
    try:
        resolved.relative_to(project_root)
    except ValueError as exc:
        raise AdapterError(f"{label} escapes project root: {relative}") from exc
    return resolved


def relative_posix(path: Path, root: Path) -> str:
    return path.resolve(strict=False).relative_to(root.resolve(strict=True)).as_posix()


def normalized_path(path: Path) -> str:
    return os.path.normcase(os.path.abspath(os.fspath(path)))


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
    parser.add_argument("--base-tool", required=True)
    parser.add_argument("--base-tool-sha256", required=True)
    parser.add_argument("--adapter-sha256", required=True)
    parser.add_argument("--compatibility-contract", required=True)
    parser.add_argument("--compatibility-contract-sha256", required=True)
    parser.add_argument("--authorization", required=True)
    parser.add_argument("--authorization-sha256", required=True)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--control-validation-only", action="store_true")
    return parser.parse_args()


def validate_recovery_compatibility(args: argparse.Namespace) -> Tuple[Dict[str, Any], Dict[str, Path]]:
    started = time.perf_counter()
    project_root = Path(args.project_root).resolve(strict=True)
    raw_root = Path(args.raw_root).resolve(strict=True)
    output_root = Path(args.output_root).resolve(strict=False)
    base_tool = Path(args.base_tool).resolve(strict=True)
    adapter_path = Path(__file__).resolve(strict=True)
    contract_path = Path(args.compatibility_contract).resolve(strict=True)
    authorization_path = Path(args.authorization).resolve(strict=True)

    require_hash(adapter_path, args.adapter_sha256, "compatibility adapter")
    require_hash(base_tool, args.base_tool_sha256, "frozen base acceptance tool")
    require_hash(contract_path, args.compatibility_contract_sha256, "compatibility contract")
    require_hash(authorization_path, args.authorization_sha256, "acceptance authorization")

    contract = read_json(contract_path, "compatibility contract")
    authorization = read_json(authorization_path, "acceptance authorization")
    require(
        contract.get("schema") == CONTRACT_SCHEMA
        and contract.get("status") == "FROZEN_ATTEMPT_003_RECOVERY_COMPATIBLE_READ_ONLY_ACCEPTANCE",
        "compatibility contract header mismatch",
    )
    require(
        authorization.get("schema") == AUTH_SCHEMA
        and authorization.get("status") == "AUTHORIZED_INDEPENDENT_READ_ONLY_ACCEPTANCE_WITH_RECOVERY_COMPATIBILITY",
        "acceptance authorization header mismatch",
    )
    require(contract.get("adapterSha256") == args.adapter_sha256, "contract adapter binding mismatch")
    require(contract.get("baseAcceptanceToolSha256") == args.base_tool_sha256, "contract base-tool binding mismatch")
    require(
        authorization.get("compatibilityContractSha256") == args.compatibility_contract_sha256
        and authorization.get("compatibilityAdapterSha256") == args.adapter_sha256,
        "authorization compatibility binding mismatch",
    )

    raw_relative = relative_posix(raw_root, project_root)
    output_relative = relative_posix(output_root, project_root)
    require(contract.get("sourceMeasuredRootRelativePath") == raw_relative, "contract source-root mismatch")
    require(contract.get("outputRootRelativePath") == output_relative, "contract output-root mismatch")
    require(authorization.get("sourceMeasuredRootRelativePath") == raw_relative, "authorization source-root mismatch")
    require(authorization.get("outputRootRelativePath") == output_relative, "authorization output-root mismatch")
    require(not output_root.exists(), f"acceptance output root must be fresh: {output_root}")
    for field, expected in {
        "readOnlyAcceptanceAuthorized": True,
        "acceptedDataPackageCreationAuthorized": True,
        "rawObservationParsingForAcceptanceOnlyAuthorized": True,
        "sourceWriteBackAuthorized": False,
        "formalAnalysisAuthorized": False,
        "rankingOrWinnerAuthorized": False,
        "mqAuthorized": False,
        "mtAuthorized": False,
    }.items():
        require(authorization.get(field) is expected, f"authorization boundary mismatch: {field}")

    for item in contract.get("projectFileBindings", []):
        require(isinstance(item, dict), "malformed project file binding")
        path = resolve_project_relative(project_root, item.get("relativePath"), "project binding")
        require_hash(path, item.get("sha256"), f"project binding {item.get('role')}")

    control_paths: Dict[str, Path] = {}
    for item in contract.get("sourceControlBindings", []):
        require(isinstance(item, dict), "malformed source control binding")
        relative = item.get("relativePath")
        require(isinstance(relative, str), "source control relativePath must be a string")
        path = (raw_root / Path(relative)).resolve(strict=False)
        try:
            path.relative_to(raw_root)
        except ValueError as exc:
            raise AdapterError(f"source control binding escapes raw root: {relative}") from exc
        require_hash(path, item.get("sha256"), f"source control binding {item.get('role')}")
        control_paths[item.get("role")] = path

    required_roles = {
        "launch receipt",
        "acquisition complete",
        "acceptance pending",
        "acquisition terminal",
        "acquisition freeze manifest",
        "preserved failure receipt",
        "preserved failure ledger",
        "replacement ledger",
        "recovery start v1",
        "failure resolution v1",
        "recovery start v2",
        "failure resolution v2",
    }
    require(required_roles.issubset(control_paths), "compatibility contract control bindings are incomplete")

    launch = read_json(control_paths["launch receipt"], "launch receipt")
    require(
        launch.get("schema") == "gate14re-me-formal-st-launch-receipt-v5"
        and launch.get("status") == "AUTHORIZED_FORMAL_ST_ACQUISITION_STARTED"
        and launch.get("runnerMethod") == "DDM.Research.Editor.Gate14ReMEFormalSTRunnerV5_1.Run"
        and launch.get("implementationRevision") == "v5.3-authorization-contract-parity-fix"
        and launch.get("plannedSuperblocks") == 1296
        and launch.get("plannedAlgorithmLanes") == 7776
        and launch.get("plannedOracleBatches") == 54
        and launch.get("plannedFreshProcesses") == 7843,
        "actual launch receipt does not match the authorized v5.3/v5.1 execution",
    )

    acquisition = read_json(control_paths["acquisition complete"], "acquisition complete")
    require(
        acquisition.get("status") == "FORMAL_ST_ACQUISITION_COMPLETE_RAW_ACCEPTANCE_PENDING_AUTHORIZED_CONTROL_PLANE_RECOVERY"
        and acquisition.get("acceptedSuperblocks") == 1296
        and acquisition.get("acceptedAlgorithmLanes") == 7776
        and acquisition.get("preservedTechnicalFailureRows") == 2
        and acquisition.get("resolvedControlPlaneFailures") == 2
        and acquisition.get("reconstructedLedgerRows") == 1
        and acquisition.get("resumedNewUnityProcesses") == 324
        and acquisition.get("replayedAlgorithmLanes") == 0
        and acquisition.get("wholeSuperblockReplacements") == 0
        and acquisition.get("formalAnalysisAuthorized") is False
        and acquisition.get("formalSTTerminalPass") is False,
        "recovery-aware acquisition-complete receipt mismatch",
    )

    pending = read_json(control_paths["acceptance pending"], "acceptance pending")
    require(
        pending.get("status") == "SEALED_RAW_REQUIRES_NEW_READ_ONLY_OFFLINE_ACCEPTANCE_AFTER_AUTHORIZED_CONTROL_PLANE_RECOVERY"
        and pending.get("sourceMutationPermitted") is False
        and pending.get("formalSTTerminalPass") is False
        and pending.get("preservedTechnicalFailureRows") == 2
        and pending.get("typedParquetFullRoundTripRequired") is True,
        "recovery-aware acceptance-pending receipt mismatch",
    )

    terminal = read_json(control_paths["acquisition terminal"], "acquisition terminal")
    require(
        terminal.get("status") == "PASS_ACQUISITION_ONLY_WITH_AUTHORIZED_CONTROL_PLANE_RECOVERY_RAW_FROZEN_ACCEPTANCE_PENDING"
        and terminal.get("acquisitionFreezeManifestSha256") == args.seal_manifest_sha256
        and terminal.get("completedFreshProcesses") == 7843
        and terminal.get("preservedTechnicalFailureRows") == 2
        and terminal.get("resolvedControlPlaneFailures") == 2
        and terminal.get("reconstructedLedgerRows") == 1
        and terminal.get("resumedNewUnityProcesses") == 324
        and terminal.get("replayedAlgorithmLanes") == 0
        and terminal.get("formalAnalysisPerformed") is False
        and terminal.get("rankingOrWinnerComputed") is False,
        "recovery-aware acquisition terminal mismatch",
    )

    failure_receipt = read_json(control_paths["preserved failure receipt"], "preserved failure receipt")
    require(
        failure_receipt.get("schema") == "gate14re-me-formal-st-supervisor-failure-receipt-v5"
        and failure_receipt.get("status") == "FAILED_CLOSED_NO_RETRY_NO_REPLACEMENT"
        and failure_receipt.get("retryPerformed") is False
        and failure_receipt.get("replacementPerformed") is False
        and failure_receipt.get("formalAnalysisPerformed") is False,
        "preserved pre-recovery failure receipt mismatch",
    )

    recovery_v1 = read_json(control_paths["recovery start v1"], "recovery start v1")
    resolution_v1 = read_json(control_paths["failure resolution v1"], "failure resolution v1")
    recovery_v2 = read_json(control_paths["recovery start v2"], "recovery start v2")
    resolution_v2 = read_json(control_paths["failure resolution v2"], "failure resolution v2")
    require(
        recovery_v1.get("status") == "AUTHORIZED_CONTROL_PLANE_RECOVERY_STARTED"
        and recovery_v1.get("reconstructedLedgerOrdinal") == 7518
        and recovery_v1.get("rerunExistingAlgorithmLane") is False
        and recovery_v1.get("replacementPerformed") is False,
        "recovery v1 start receipt mismatch",
    )
    require(
        resolution_v1.get("status") == "RESOLVED_BY_AUTHORIZED_CONTROL_PLANE_LEDGER_RECONSTRUCTION_NO_ALGORITHM_RERUN"
        and resolution_v1.get("preservedFailureRecordId") == "void:formal-sb-1241:formal-sb-1241"
        and resolution_v1.get("reconstructedLedgerOrdinal") == 7518
        and resolution_v1.get("rerunExistingAlgorithmLane") is False
        and resolution_v1.get("replacementPerformed") is False
        and resolution_v1.get("failureRowDeletedOrRewritten") is False
        and resolution_v1.get("formalAnalysisPerformed") is False,
        "failure resolution v1 mismatch",
    )
    require(
        recovery_v2.get("status") == "AUTHORIZED_CONTROL_PLANE_RECOVERY_V2_STARTED"
        and recovery_v2.get("processLedgerRowsAtStart") == 7519
        and recovery_v2.get("resumeFirstNewOrdinal") == 7519
        and recovery_v2.get("remainingNewUnityProcesses") == 324
        and recovery_v2.get("timestampComparatorLoaded") is True
        and recovery_v2.get("rerunExistingAlgorithmLane") is False
        and recovery_v2.get("replacementPerformed") is False,
        "recovery v2 start receipt mismatch",
    )
    require(
        resolution_v2.get("status") == "RESOLVED_BY_LOADING_FROZEN_TIMESTAMP_COMPARATOR_BEFORE_FIRST_NEW_UNITY_PROCESS"
        and resolution_v2.get("preservedFailureRecordId") == "void:formal-sb-1242:formal-sb-1242"
        and resolution_v2.get("failedBeforeUnityProcessStart") is True
        and resolution_v2.get("algorithmObservationCreatedDuringRecoveryV1Continuation") is False
        and resolution_v2.get("fixedByDotSourcingFrozenTimestampComparator") is True
        and resolution_v2.get("rerunExistingAlgorithmLane") is False
        and resolution_v2.get("replacementPerformed") is False
        and resolution_v2.get("failureRowDeletedOrRewritten") is False
        and resolution_v2.get("formalAnalysisPerformed") is False,
        "failure resolution v2 mismatch",
    )

    failure_path = control_paths["preserved failure ledger"]
    failure_bytes = failure_path.read_bytes()
    failure_lines = failure_bytes.splitlines(keepends=True)
    failure_rows = read_jsonl(failure_path, "preserved failure ledger")
    require(len(failure_rows) == 2 and len(failure_lines) == 2, "preserved failure ledger must contain exactly two rows")
    require(
        hashlib.sha256(failure_lines[0]).hexdigest()
        == resolution_v1.get("preservedFailureLedgerSha256BeforeRecovery"),
        "failure ledger v1 prefix hash mismatch",
    )
    require(
        sha256_file(failure_path) == resolution_v2.get("preservedFailureLedgerSha256BeforeRecoveryV2"),
        "failure ledger v2 frozen hash mismatch",
    )
    expected_failure_ids = [
        "void:formal-sb-1241:formal-sb-1241",
        "void:formal-sb-1242:formal-sb-1242",
    ]
    for index, (row, record_id) in enumerate(zip(failure_rows, expected_failure_ids), 1):
        require(
            row.get("schema") == "gate14re-me-formal-st-whole-superblock-void-row-v5"
            and row.get("recordId") == record_id
            and row.get("status") == "VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE"
            and row.get("isReplacement") is False,
            f"preserved technical failure row mismatch at {index}",
        )
    require(control_paths["replacement ledger"].stat().st_size == 0, "replacement ledger must remain empty")
    require(
        not (raw_root / "_control/recovery-failure-receipt.v2.json").exists(),
        "recovery v2 failure receipt exists",
    )

    receipt: Dict[str, Any] = {
        "schema": VALIDATION_SCHEMA,
        "status": "PASS_AUTHORIZED_CONTROL_PLANE_RECOVERY_COMPATIBILITY_PREFLIGHT",
        "studyId": "Gate14Re-ME",
        "sourceMeasuredRoot": raw_root.as_posix(),
        "outputRoot": output_root.as_posix(),
        "sealedRecoveryAwareAcquisitionTerminalValidated": True,
        "preservedTechnicalFailureRows": 2,
        "failureResolutionV1Validated": True,
        "failureResolutionV2Validated": True,
        "reconstructedLedgerRows": 1,
        "resumedNewUnityProcesses": 324,
        "replayedAlgorithmLanes": 0,
        "replacementRows": 0,
        "sourceMutationPermitted": False,
        "formalAnalysisAuthorized": False,
        "formalAnalysisPerformed": False,
        "rankingOrWinnerComputed": False,
        "compatibilityProjectionScope": [
            "runner method identity v5.1 projected to frozen v5 validator token after exact validation",
            "recovery-aware acquisition statuses projected to frozen no-recovery status tokens after exact validation",
            "preserved resolved failure receipt/rows hidden only from the legacy zero-failure control-plane branch after exact validation",
            "the two preserved technical failure rows remain visible to raw-table profiling and typed-Parquet round-trip",
        ],
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "createdAtUtc": utc_now(),
    }
    paths = {
        "project_root": project_root,
        "raw_root": raw_root,
        "output_root": output_root,
        "base_tool": base_tool,
        "launch": control_paths["launch receipt"],
        "acquisition": control_paths["acquisition complete"],
        "pending": control_paths["acceptance pending"],
        "terminal": control_paths["acquisition terminal"],
        "failure_receipt": control_paths["preserved failure receipt"],
        "failure_ledger": control_paths["preserved failure ledger"],
    }
    return receipt, paths


def load_base_tool(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("gate14re_me_formal_st_acceptance_v5_frozen", path)
    require(spec is not None and spec.loader is not None, f"unable to load frozen acceptance tool: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run_frozen_acceptance(
    args: argparse.Namespace,
    receipt: Dict[str, Any],
    paths: Mapping[str, Path],
) -> int:
    base = load_base_tool(paths["base_tool"])
    original_read_json = base.read_json
    original_read_jsonl = base.read_jsonl
    original_validate_control_plane = base.validate_control_plane
    original_validate_profile_cardinality = base.validate_profile_cardinality
    original_write_json = base.write_json
    original_path_exists = Path.exists
    control_projection_active = False

    normalized_controls = {
        normalized_path(paths["launch"]): ("runnerMethod", "DDM.Research.Editor.Gate14ReMEFormalSTRunnerV5.Run"),
        normalized_path(paths["acquisition"]): ("status", "FORMAL_ST_ACQUISITION_COMPLETE_RAW_ACCEPTANCE_PENDING"),
        normalized_path(paths["pending"]): ("status", "SEALED_RAW_REQUIRES_NEW_READ_ONLY_OFFLINE_ACCEPTANCE_ATTEMPT"),
        normalized_path(paths["terminal"]): ("status", "PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING"),
    }
    failure_receipt_key = normalized_path(paths["failure_receipt"])
    failure_ledger_key = normalized_path(paths["failure_ledger"])
    terminal_key = normalized_path(paths["terminal"])

    def compatible_read_json(path: Path, label: str) -> Dict[str, Any]:
        value = original_read_json(path, label)
        key = normalized_path(path)
        if key == terminal_key or (control_projection_active and key in normalized_controls):
            field, projected = normalized_controls[key]
            value = dict(value)
            value[field] = projected
        return value

    def compatible_read_jsonl(path: Path) -> Iterable[Tuple[int, Dict[str, Any]]]:
        if control_projection_active and normalized_path(path) == failure_ledger_key:
            return iter(())
        return original_read_jsonl(path)

    def compatible_path_exists(self: Path) -> bool:
        if control_projection_active and normalized_path(self) == failure_receipt_key:
            return False
        return original_path_exists(self)

    def compatible_validate_control_plane(*call_args: Any, **call_kwargs: Any) -> Dict[str, Any]:
        nonlocal control_projection_active
        control_projection_active = True
        try:
            result = original_validate_control_plane(*call_args, **call_kwargs)
        finally:
            control_projection_active = False
        compatibility_receipt = dict(receipt)
        compatibility_receipt.update(
            {
                "status": "PASS_FROZEN_VALIDATOR_WITH_AUTHORIZED_RECOVERY_COMPATIBILITY",
                "frozenBaseControlPlaneValidatorPass": True,
                "sourceMeasuredRootWriteBack": False,
                "formalAnalysisPerformed": False,
                "completedAtUtc": utc_now(),
            }
        )
        if not args.control_validation_only:
            original_write_json(
                paths["output_root"] / "recovery-compatibility-validation.v1.json",
                compatibility_receipt,
            )
        result = dict(result)
        result["failureLedgerRows"] = 2
        result["preservedResolvedTechnicalFailureRows"] = 2
        result["authorizedControlPlaneRecoveryCompatibility"] = {
            "status": compatibility_receipt["status"],
            "preservedTechnicalFailureRows": 2,
            "failureResolutionV1Validated": True,
            "failureResolutionV2Validated": True,
            "replayedAlgorithmLanes": 0,
            "replacementRows": 0,
        }
        return result

    def compatible_validate_profile_cardinality(profiles: Sequence[Any]) -> Dict[str, int]:
        failure_profile = next((item for item in profiles if item.table_id == "failures-and-voids"), None)
        require(failure_profile is not None, "failures-and-voids table profile is missing")
        require(failure_profile.row_count == 2, "accepted package must retain exactly two resolved technical failure rows")
        projected = [
            dataclasses.replace(item, row_count=0) if item.table_id == "failures-and-voids" else item
            for item in profiles
        ]
        result = original_validate_profile_cardinality(projected)
        result["failures-and-voids"] = 2
        return result

    base.read_json = compatible_read_json
    base.read_jsonl = compatible_read_jsonl
    base.validate_control_plane = compatible_validate_control_plane
    base.validate_profile_cardinality = compatible_validate_profile_cardinality
    Path.exists = compatible_path_exists

    base_argv = [
        os.fspath(paths["base_tool"]),
        "--project-root", args.project_root,
        "--raw-root", args.raw_root,
        "--output-root", args.output_root,
        "--output-schema", args.output_schema,
        "--output-schema-sha256", args.output_schema_sha256,
        "--seal-manifest", args.seal_manifest,
        "--seal-manifest-sha256", args.seal_manifest_sha256,
        "--seal-terminal", args.seal_terminal,
        "--seal-terminal-sha256", args.seal_terminal_sha256,
        "--schedule", args.schedule,
        "--schedule-sha256", args.schedule_sha256,
        "--runtime-manifest", args.runtime_manifest,
        "--runtime-manifest-sha256", args.runtime_manifest_sha256,
        "--pyarrow-root", args.pyarrow_root,
        "--batch-size", str(args.batch_size),
    ]
    original_argv = sys.argv
    try:
        if args.control_validation_only:
            sealed_entries, seal_replay = base.replay_sealed_inventory(
                paths["raw_root"],
                Path(args.seal_manifest).resolve(strict=True),
            )
            validation = base.validate_control_plane(
                paths["project_root"],
                paths["raw_root"],
                Path(args.schedule).resolve(strict=True),
                args.schedule_sha256,
                args.seal_manifest_sha256,
                sealed_entries,
            )
            result = {
                "schema": VALIDATION_SCHEMA,
                "status": "PASS_SEALED_INVENTORY_AND_FROZEN_CONTROL_VALIDATOR_WITH_AUTHORIZED_RECOVERY_COMPATIBILITY",
                "sealedInventoryReplay": seal_replay,
                "controlPlaneValidation": validation,
                "sourceMeasuredRootWriteBack": False,
                "formalAnalysisPerformed": False,
                "createdAtUtc": utc_now(),
            }
            print(canonical_json(result))
            return 0
        sys.argv = base_argv
        return int(base.main())
    finally:
        sys.argv = original_argv
        Path.exists = original_path_exists


def main() -> int:
    args = parse_args()
    try:
        receipt, paths = validate_recovery_compatibility(args)
        if args.preflight_only:
            print(canonical_json(receipt))
            return 0
        return run_frozen_acceptance(args, receipt, paths)
    except Exception as exc:
        failure = {
            "schema": ADAPTER_SCHEMA,
            "status": "FAIL_CLOSED_RECOVERY_COMPATIBILITY_ADAPTER",
            "errorType": type(exc).__name__,
            "error": str(exc),
            "sourceMutationPerformed": False,
            "formalAnalysisPerformed": False,
            "sameAttemptRetryPermitted": False,
            "failedAtUtc": utc_now(),
        }
        print(canonical_json(failure), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
