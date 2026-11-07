#!/usr/bin/env python3
"""Gate 14Re Formal Phase A structural raw-commit auditor.

This program is intentionally outcome-blind.  It is allowed to:

* verify frozen file identities and acquisition control receipts;
* validate block-output JSON against the frozen JSON Schema;
* verify identity fields, path bindings, hashes, and cardinalities; and
* produce a content-hash tree, manifest, and immutable raw-complete marker.

It must never extract, aggregate, compare, print, or interpret M1--M5 values.
Schema validation necessarily parses each JSON document, but the program only
retains structural identity/cardinality facts and never emits instance values.
Player logs are hashed as opaque bytes and are never opened as text.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import stat
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError, ValidationError


WORKSPACE = Path(r"H:\DDM_Final_Project")
FORMAL_ROOT = WORKSPACE / "Research/FormalRuns/Gate14Re/PhaseA/attempt-001"
VERIFY_ROOT = (
    WORKSPACE
    / "Research/Verification/Gate14Re/formal-phase-a-raw-commit-attempt-001"
)

PLAN = WORKSPACE / "Research/Gate14Re/Execution/Gate14Re_Formal_Block_Plan.v1.json"
EXECUTION_CONTRACT = (
    WORKSPACE / "Research/Gate14Re/Execution/Gate14Re_Formal_Execution_Contract.v2.json"
)
OUTPUT_SCHEMA = (
    WORKSPACE / "Research/Gate14Re/Execution/Gate14Re_Formal_Block_Output_Schema.v2.json"
)
AUTHORIZATION = (
    WORKSPACE / "Research/Gate14Re/Execution/Gate14Re_Formal_PhaseA_Authorization.v2.json"
)
SUPERVISOR = (
    WORKSPACE / "Research/Gate14Re/Execution/Run-Gate14ReFormalPhaseA.v1.ps1"
)
LAUNCH_READINESS = (
    WORKSPACE
    / "Research/Verification/Gate14Re/formal-executor-implementation-attempt-001"
    / "formal-phase-a-launch-readiness.v1.json"
)
EXTERNAL_LAUNCH_RECEIPT = (
    WORKSPACE
    / "Research/Verification/Gate14Re/formal-executor-implementation-attempt-001"
    / "formal-phase-a-live-launch-attempt-002/external-launch-receipt.v1.json"
)
BUILD_ROOT = (
    WORKSPACE
    / "Research/Verification/Gate14Re/formal-executor-implementation-attempt-001"
    / "standalone-build-attempt-003"
)
BUILD_RECEIPT = BUILD_ROOT / "build-receipt.v2.json"
FORMAL_EXE = BUILD_ROOT / "Gate14ReFormalRunner.exe"
ASSEMBLY_CSHARP = BUILD_ROOT / "Gate14ReFormalRunner_Data/Managed/Assembly-CSharp.dll"
BUILD_TREE = BUILD_ROOT.parent / "standalone-build-attempt-003.canonical-tree.v1.jsonl"
BUILD_FREEZE_RECEIPT = (
    BUILD_ROOT.parent / "standalone-build-attempt-003.build-freeze-receipt.v1.json"
)

SCRIPT_PATH = Path(__file__).resolve()

EXPECTED = {
    "authorization_id": "gate14re-phase-a-attempt-001-b87e10a8-9d42-4512-8f4d-4b371eb7f75b",
    "authorization_sha256": "98a842ef9fe996ac7566ae2ceed17394e189e187d8184ccd34ff44999fa66dc1",
    "plan_sha256": "9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d",
    "execution_contract_sha256": "6309d031e00fcf53380e74343adff5863c88aa1c11cb72542cd352a2f19c2bd3",
    "output_schema_sha256": "0c248a4046df959bae078f360ba5d4dfc322d603dc0bdd8e920b492db11325c2",
    "executable_sha256": "88b1b04971f8b712ddd0f18bca4f7296d287fdd6cdadef57c155d37b9ef0928c",
    "assembly_sha256": "2f763a06d43a5777d6ce47cdba998d5482e82557ad35ee72f9e07dcd193b2961",
    "build_receipt_sha256": "d110c97ca2f2f3d5a38490497ebfcf714d976c75b2397a68d46787e29c51ec9a",
    "build_tree_sha256": "c4da85e66f9898834bc30b5e5618021458405f9a5962266c4d336479202abd46",
    "build_freeze_sha256": "9df8bf66fa7df1d23e3454be5b23cdb99b907fa3e1848942b3845f56373c7199",
    "supervisor_sha256": "3c0bcf6f228656d58fde5a22f07846bb26b29351ffb7a71f4d6ae30ee5530b49",
    "launch_readiness_sha256": "7eda9cb08751d5915f962b6a204b5ad937908c7b08f186d098e630baeda1569f",
    "external_launch_sha256": "a2c5b64b4a20f81b3eda26281c30cffab7cba5d927b819f2e40e5ba9b98ed713",
    "launch_receipt_initial_sha256": "5a9c5606bcd9c17360db3f4941c9af1b5826e7e61c2bf8d8148edbf0fdd97ec2",
    "planned_blocks": 1536,
    "planned_algorithm_lane_samples": 6144,
    "fixed_b": 48,
}

CONTROL_PRECOMMIT_FILES = {
    "_control/accepted-blocks.v1.jsonl",
    "_control/acquisition-complete.v1.json",
    "_control/execution-status.json",
    "_control/launch-receipt.v1.json",
}
TREE_REL = "_control/raw-commit-canonical-tree.v1.jsonl"
MANIFEST_REL = "_control/raw-commit-manifest.v1.json"
RAW_COMPLETE_REL = "raw-data-complete.json"
AUDIT_RECEIPT = VERIFY_ROOT / "structural-audit-receipt.v1.json"
FAILURE_RECEIPT = VERIFY_ROOT / "failure-receipt.v1.json"

FILE_ATTRIBUTE_READONLY = 0x00000001
INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF


class AuditError(RuntimeError):
    """A fail-closed structural audit error with no outcome values."""


def require(condition: bool, code: str, detail: str = "") -> None:
    if not condition:
        suffix = f": {detail}" if detail else ""
        raise AuditError(f"{code}{suffix}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def no_duplicate_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AuditError("DUPLICATE_JSON_KEY", key)
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    require(path.is_file(), "MISSING_JSON", path.as_posix())
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            return json.load(handle, object_pairs_hook=no_duplicate_object_pairs)
    except AuditError:
        raise
    except Exception as exc:  # Error text contains location, not instance data.
        raise AuditError("INVALID_JSON", f"{path.as_posix()} ({type(exc).__name__})") from exc


def canonical_json_bytes(value: Any, *, pretty: bool = False) -> bytes:
    if pretty:
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)
    else:
        text = json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        )
    return (text + "\n").encode("utf-8")


def atomic_create(path: Path, payload: bytes) -> None:
    require(not path.exists(), "COMMIT_TARGET_ALREADY_EXISTS", path.as_posix())
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".gate14re-raw-commit-", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def get_attributes(path: Path) -> int:
    if os.name != "nt":
        return 0
    get_attrs = ctypes.windll.kernel32.GetFileAttributesW
    get_attrs.argtypes = [ctypes.c_wchar_p]
    get_attrs.restype = ctypes.c_uint32
    value = int(get_attrs(str(path)))
    require(value != INVALID_FILE_ATTRIBUTES, "GET_ATTRIBUTES_FAILED", path.as_posix())
    return value


def set_readonly(path: Path) -> None:
    if os.name != "nt":
        os.chmod(path, stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        return
    attrs = get_attributes(path)
    set_attrs = ctypes.windll.kernel32.SetFileAttributesW
    set_attrs.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32]
    set_attrs.restype = ctypes.c_int
    ok = set_attrs(str(path), attrs | FILE_ATTRIBUTE_READONLY)
    require(bool(ok), "SET_READONLY_FAILED", path.as_posix())


def clear_readonly(path: Path) -> None:
    if not path.exists():
        return
    if os.name != "nt":
        os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
        return
    attrs = get_attributes(path)
    set_attrs = ctypes.windll.kernel32.SetFileAttributesW
    set_attrs.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32]
    set_attrs.restype = ctypes.c_int
    set_attrs(str(path), attrs & ~FILE_ATTRIBUTE_READONLY)


def is_readonly(path: Path) -> bool:
    if os.name == "nt":
        return bool(get_attributes(path) & FILE_ATTRIBUTE_READONLY)
    return not bool(path.stat().st_mode & stat.S_IWUSR)


def relative(path: Path, root: Path = FORMAL_ROOT) -> str:
    return path.relative_to(root).as_posix()


def assert_file_hash(path: Path, expected: str, code: str) -> None:
    require(path.is_file(), f"{code}_MISSING", path.as_posix())
    actual = sha256_file(path)
    require(actual == expected, f"{code}_HASH_MISMATCH", path.as_posix())


def validate_frozen_bindings() -> dict[str, Any]:
    bindings = [
        (PLAN, EXPECTED["plan_sha256"], "PLAN"),
        (EXECUTION_CONTRACT, EXPECTED["execution_contract_sha256"], "EXECUTION_CONTRACT"),
        (OUTPUT_SCHEMA, EXPECTED["output_schema_sha256"], "OUTPUT_SCHEMA"),
        (AUTHORIZATION, EXPECTED["authorization_sha256"], "AUTHORIZATION"),
        (SUPERVISOR, EXPECTED["supervisor_sha256"], "SUPERVISOR"),
        (LAUNCH_READINESS, EXPECTED["launch_readiness_sha256"], "LAUNCH_READINESS"),
        (EXTERNAL_LAUNCH_RECEIPT, EXPECTED["external_launch_sha256"], "EXTERNAL_LAUNCH"),
        (BUILD_RECEIPT, EXPECTED["build_receipt_sha256"], "BUILD_RECEIPT"),
        (FORMAL_EXE, EXPECTED["executable_sha256"], "FORMAL_EXE"),
        (ASSEMBLY_CSHARP, EXPECTED["assembly_sha256"], "ASSEMBLY_CSHARP"),
        (BUILD_TREE, EXPECTED["build_tree_sha256"], "BUILD_TREE"),
        (BUILD_FREEZE_RECEIPT, EXPECTED["build_freeze_sha256"], "BUILD_FREEZE"),
    ]
    for path, expected_hash, code in bindings:
        assert_file_hash(path, str(expected_hash), code)

    require(is_readonly(AUTHORIZATION), "AUTHORIZATION_NOT_READONLY")
    authorization = load_json(AUTHORIZATION)
    require(authorization.get("status") == "AUTHORIZED", "AUTHORIZATION_NOT_AUTHORIZED")
    require(
        authorization.get("authorizationId") == EXPECTED["authorization_id"],
        "AUTHORIZATION_ID_MISMATCH",
    )
    require(
        authorization.get("userExplicitlyAuthorizedFormalPhaseA") is True,
        "USER_AUTHORIZATION_FLAG_FALSE",
    )
    require(authorization.get("formalRoot") == FORMAL_ROOT.as_posix(), "FORMAL_ROOT_BINDING_MISMATCH")

    launch_path = FORMAL_ROOT / "_control/launch-receipt.v1.json"
    assert_file_hash(
        launch_path,
        str(EXPECTED["launch_receipt_initial_sha256"]),
        "ROOT_LAUNCH_RECEIPT",
    )
    launch = load_json(launch_path)
    require(launch.get("authorizationId") == EXPECTED["authorization_id"], "LAUNCH_AUTH_ID_MISMATCH")
    require(launch.get("authorizationSha256") == EXPECTED["authorization_sha256"], "LAUNCH_AUTH_HASH_MISMATCH")
    require(launch.get("planSha256") == EXPECTED["plan_sha256"], "LAUNCH_PLAN_HASH_MISMATCH")
    require(launch.get("executableSha256") == EXPECTED["executable_sha256"], "LAUNCH_EXE_HASH_MISMATCH")
    require(launch.get("assemblyCSharpSha256") == EXPECTED["assembly_sha256"], "LAUNCH_ASSEMBLY_HASH_MISMATCH")
    require(launch.get("buildReceiptSha256") == EXPECTED["build_receipt_sha256"], "LAUNCH_BUILD_RECEIPT_HASH_MISMATCH")
    require(launch.get("buildCanonicalTreeSha256") == EXPECTED["build_tree_sha256"], "LAUNCH_BUILD_TREE_HASH_MISMATCH")
    require(launch.get("buildFreezeReceiptSha256") == EXPECTED["build_freeze_sha256"], "LAUNCH_BUILD_FREEZE_HASH_MISMATCH")
    require(launch.get("supervisorSha256") == EXPECTED["supervisor_sha256"], "LAUNCH_SUPERVISOR_HASH_MISMATCH")
    require(launch.get("plannedBlocks") == EXPECTED["planned_blocks"], "LAUNCH_BLOCK_COUNT_MISMATCH")
    require(launch.get("fixedB") == EXPECTED["fixed_b"], "LAUNCH_FIXED_B_MISMATCH")
    require(launch.get("formalAnalysisStarted") is False, "FORMAL_ANALYSIS_ALREADY_STARTED")
    require(launch.get("phaseBStarted") is False, "PHASE_B_ALREADY_STARTED")

    return {"authorization": authorization, "launch": launch}


def validate_acquisition_control() -> dict[str, Any]:
    failure = FORMAL_ROOT / "_control/failure-receipt.v1.json"
    require(not failure.exists(), "FAILURE_RECEIPT_PRESENT")
    require(not (FORMAL_ROOT / RAW_COMPLETE_REL).exists(), "RAW_COMPLETE_ALREADY_EXISTS")
    require(not (FORMAL_ROOT / TREE_REL).exists(), "RAW_TREE_ALREADY_EXISTS")
    require(not (FORMAL_ROOT / MANIFEST_REL).exists(), "RAW_MANIFEST_ALREADY_EXISTS")

    status = load_json(FORMAL_ROOT / "_control/execution-status.json")
    complete = load_json(FORMAL_ROOT / "_control/acquisition-complete.v1.json")
    for obj, label in ((status, "STATUS"), (complete, "ACQUISITION_COMPLETE")):
        require(obj.get("status") == "FORMAL-PHASE-A-ACQUISITION-COMPLETE", f"{label}_STATE_MISMATCH")
        require(obj.get("nextState") == "FORMAL-PHASE-A-RAW-COMMIT-PENDING", f"{label}_NEXT_STATE_MISMATCH")
        require(obj.get("acceptedBlocks") == EXPECTED["planned_blocks"], f"{label}_ACCEPTED_COUNT_MISMATCH")
        require(obj.get("plannedBlocks") == EXPECTED["planned_blocks"], f"{label}_PLANNED_COUNT_MISMATCH")
        require(obj.get("launchedProcesses") == EXPECTED["planned_blocks"], f"{label}_PROCESS_COUNT_MISMATCH")
        require(obj.get("wholeBlockReplacements") == 0, f"{label}_REPLACEMENTS_NOT_ZERO")
        require(obj.get("processRetryResumeTopUpMergeSkipOrReorder") is False, f"{label}_FORBIDDEN_PROCESS_ACTION")
        require(obj.get("formalAnalysisStarted") is False, f"{label}_FORMAL_ANALYSIS_STARTED")
        require(obj.get("phaseBStarted") is False, f"{label}_PHASE_B_STARTED")
    require(complete.get("fixedB") == EXPECTED["fixed_b"], "COMPLETE_FIXED_B_MISMATCH")
    return {"status": status, "complete": complete}


def validate_plan() -> tuple[dict[str, Any], list[dict[str, Any]], dict[int, dict[str, Any]]]:
    plan = load_json(PLAN)
    require(plan.get("schema") == "gate14re-formal-block-plan-v1", "PLAN_SCHEMA_MISMATCH")
    require(plan.get("studyId") == "Gate14Re", "PLAN_STUDY_ID_MISMATCH")
    require(plan.get("status") == "FROZEN_NONEXECUTING", "PLAN_NOT_FROZEN")
    require(plan.get("fixedB") == EXPECTED["fixed_b"], "PLAN_FIXED_B_MISMATCH")
    require(plan.get("plannedValidProcesses") == EXPECTED["planned_blocks"], "PLAN_PROCESS_COUNT_MISMATCH")
    blocks = plan.get("blocks")
    require(isinstance(blocks, list), "PLAN_BLOCKS_NOT_ARRAY")
    require(len(blocks) == EXPECTED["planned_blocks"], "PLAN_BLOCK_COUNT_MISMATCH")

    by_sequence: dict[int, dict[str, Any]] = {}
    ids: set[str] = set()
    lane_counts: Counter[str] = Counter()
    module_counts: Counter[str] = Counter()
    cell_rows: dict[tuple[Any, ...], Counter[int]] = defaultdict(Counter)
    for expected_sequence, block in enumerate(blocks, start=1):
        require(isinstance(block, dict), "PLAN_BLOCK_NOT_OBJECT", str(expected_sequence))
        sequence = block.get("sequence")
        block_id = block.get("blockId")
        require(sequence == expected_sequence, "PLAN_SEQUENCE_NOT_CONTIGUOUS", str(expected_sequence))
        require(isinstance(block_id, str) and block_id, "PLAN_BLOCK_ID_INVALID", str(expected_sequence))
        require(block_id not in ids, "PLAN_DUPLICATE_BLOCK_ID", block_id)
        require(block.get("maximumWholeBlockReplacements") == 1, "PLAN_REPLACEMENT_LIMIT_MISMATCH", block_id)
        labels = block.get("algorithmLabelsInOrder")
        algorithms = block.get("algorithmIdsInOrder")
        require(isinstance(labels, list) and len(labels) == 4 and len(set(labels)) == 4, "PLAN_LABEL_ORDER_INVALID", block_id)
        require(isinstance(algorithms, list) and len(algorithms) == 4 and len(set(algorithms)) == 4, "PLAN_ALGORITHM_ORDER_INVALID", block_id)
        lane = block.get("lane")
        module = block.get("module")
        require(lane in {"movement", "m4"}, "PLAN_LANE_INVALID", block_id)
        require(module in {"A", "Q"}, "PLAN_MODULE_INVALID", block_id)
        ids.add(block_id)
        by_sequence[sequence] = block
        lane_counts[lane] += 1
        module_counts[module] += 1
        cell = (module, block.get("conditionId"), block.get("unitCount"), lane)
        cell_rows[cell][int(block.get("williamsRow"))] += 1

    require(lane_counts == Counter({"movement": 768, "m4": 768}), "PLAN_LANE_COUNTS_MISMATCH")
    require(module_counts == Counter({"A": 768, "Q": 768}), "PLAN_MODULE_COUNTS_MISMATCH")
    require(len(cell_rows) == 32, "PLAN_DESIGN_CELL_COUNT_MISMATCH", str(len(cell_rows)))
    for cell, row_counts in cell_rows.items():
        require(sum(row_counts.values()) == 48, "PLAN_CELL_BLOCK_COUNT_MISMATCH", repr(cell))
        require(row_counts == Counter({1: 12, 2: 12, 3: 12, 4: 12}), "PLAN_WILLIAMS_BALANCE_MISMATCH", repr(cell))
    return plan, blocks, by_sequence


def validate_ledger(blocks_by_sequence: dict[int, dict[str, Any]]) -> dict[int, dict[str, Any]]:
    ledger_path = FORMAL_ROOT / "_control/accepted-blocks.v1.jsonl"
    require(ledger_path.is_file(), "ACCEPTED_LEDGER_MISSING")
    accepted: dict[int, dict[str, Any]] = {}
    with ledger_path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            require(raw_line.endswith("\n") or line_number == EXPECTED["planned_blocks"], "LEDGER_LINE_TERMINATION_INVALID", str(line_number))
            line = raw_line.strip()
            require(bool(line), "LEDGER_EMPTY_LINE", str(line_number))
            try:
                row = json.loads(line, object_pairs_hook=no_duplicate_object_pairs)
            except AuditError:
                raise
            except Exception as exc:
                raise AuditError("LEDGER_JSON_INVALID", str(line_number)) from exc
            require(isinstance(row, dict), "LEDGER_ROW_NOT_OBJECT", str(line_number))
            sequence = row.get("sequence")
            require(sequence == line_number, "LEDGER_SEQUENCE_MISMATCH", str(line_number))
            require(sequence in blocks_by_sequence, "LEDGER_SEQUENCE_NOT_IN_PLAN", str(line_number))
            block = blocks_by_sequence[sequence]
            block_id = block["blockId"]
            require(row.get("blockId") == block_id, "LEDGER_BLOCK_ID_MISMATCH", str(line_number))
            require(row.get("acceptedAttempt") == 1, "LEDGER_ACCEPTED_ATTEMPT_NOT_ONE", str(line_number))
            require(row.get("replacement") is False, "LEDGER_REPLACEMENT_TRUE", str(line_number))
            expected_output = f"blocks/{sequence:04d}_{block_id}/attempt-001/block-output.json"
            require(row.get("outputRelativePath") == expected_output, "LEDGER_OUTPUT_PATH_MISMATCH", str(line_number))
            output_hash = row.get("outputSha256")
            require(isinstance(output_hash, str) and len(output_hash) == 64, "LEDGER_OUTPUT_HASH_INVALID", str(line_number))
            require(sequence not in accepted, "LEDGER_DUPLICATE_SEQUENCE", str(line_number))
            accepted[sequence] = row
    require(len(accepted) == EXPECTED["planned_blocks"], "LEDGER_ROW_COUNT_MISMATCH", str(len(accepted)))
    return accepted


def sanitized_schema_error(exc: ValidationError) -> str:
    instance_path = "$"
    for part in exc.absolute_path:
        instance_path += f"[{part}]" if isinstance(part, int) else f".{part}"
    schema_path = "/".join(str(part) for part in exc.absolute_schema_path)
    return f"validator={exc.validator};instancePath={instance_path};schemaPath={schema_path}"


def validate_block_outputs(
    blocks: list[dict[str, Any]],
    accepted: dict[int, dict[str, Any]],
    schema: dict[str, Any],
) -> tuple[set[str], dict[str, str], dict[str, int]]:
    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as exc:
        raise AuditError("FROZEN_OUTPUT_SCHEMA_INVALID", type(exc).__name__) from exc
    validator = Draft202012Validator(schema)

    expected_files = set(CONTROL_PRECOMMIT_FILES)
    expected_dirs = {"_control", "blocks", "logs"}
    hash_cache: dict[str, str] = {}
    movement_blocks = 0
    m4_blocks = 0
    algorithm_lane_samples = 0
    movement_units_structurally_counted = 0
    m4_frame_intervals_structurally_counted = 0

    expected_log_names: set[str] = set()
    for block in blocks:
        sequence = int(block["sequence"])
        block_id = str(block["blockId"])
        block_dir_rel = f"blocks/{sequence:04d}_{block_id}"
        attempt_dir_rel = f"{block_dir_rel}/attempt-001"
        output_rel = f"{attempt_dir_rel}/block-output.json"
        receipt_rel = f"{attempt_dir_rel}/process-receipt.v1.json"
        log_rel = f"logs/{sequence:04d}_{block_id}_attempt-001.player.log"
        expected_dirs.update({block_dir_rel, attempt_dir_rel})
        expected_files.update({output_rel, receipt_rel, log_rel})
        expected_log_names.add(Path(log_rel).name)

        output_path = FORMAL_ROOT / Path(output_rel)
        receipt_path = FORMAL_ROOT / Path(receipt_rel)
        log_path = FORMAL_ROOT / Path(log_rel)
        require(output_path.is_file(), "BLOCK_OUTPUT_MISSING", output_rel)
        require(receipt_path.is_file(), "PROCESS_RECEIPT_MISSING", receipt_rel)
        require(log_path.is_file(), "PLAYER_LOG_MISSING", log_rel)
        require(log_path.stat().st_size > 0, "PLAYER_LOG_EMPTY", log_rel)

        output_hash = sha256_file(output_path)
        hash_cache[output_rel] = output_hash
        ledger_row = accepted[sequence]
        require(output_hash == ledger_row["outputSha256"], "OUTPUT_HASH_LEDGER_MISMATCH", output_rel)

        process_receipt = load_json(receipt_path)
        require(process_receipt.get("schema") == "gate14re-formal-block-process-receipt-v1", "PROCESS_RECEIPT_SCHEMA_MISMATCH", receipt_rel)
        require(process_receipt.get("studyId") == "Gate14Re", "PROCESS_RECEIPT_STUDY_MISMATCH", receipt_rel)
        require(process_receipt.get("blockId") == block_id, "PROCESS_RECEIPT_BLOCK_ID_MISMATCH", receipt_rel)
        require(process_receipt.get("blockSequence") == sequence, "PROCESS_RECEIPT_SEQUENCE_MISMATCH", receipt_rel)
        require(process_receipt.get("attempt") == 1, "PROCESS_RECEIPT_ATTEMPT_MISMATCH", receipt_rel)
        require(process_receipt.get("replacement") is False, "PROCESS_RECEIPT_REPLACEMENT_TRUE", receipt_rel)
        require(process_receipt.get("exitCode") == 0, "PROCESS_RECEIPT_EXIT_NONZERO", receipt_rel)
        require(process_receipt.get("timedOut") is False, "PROCESS_RECEIPT_TIMED_OUT", receipt_rel)
        require(process_receipt.get("completeOutputValidated") is True, "PROCESS_RECEIPT_OUTPUT_NOT_VALIDATED", receipt_rel)
        require(process_receipt.get("outputRelativePath") == output_rel, "PROCESS_RECEIPT_OUTPUT_PATH_MISMATCH", receipt_rel)
        require(process_receipt.get("outputSha256") == output_hash, "PROCESS_RECEIPT_OUTPUT_HASH_MISMATCH", receipt_rel)
        require(process_receipt.get("perAlgorithmRetryOrResume") is False, "PROCESS_RECEIPT_PER_ALGORITHM_RETRY", receipt_rel)

        # Parse only for JSON-Schema, identity, and cardinality checks.  No
        # outcome value is selected, retained, aggregated, printed, or compared.
        output = load_json(output_path)
        try:
            validator.validate(output)
        except ValidationError as exc:
            raise AuditError(
                "BLOCK_OUTPUT_SCHEMA_VIOLATION",
                f"{output_rel};{sanitized_schema_error(exc)}",
            ) from exc

        identity_expectations = {
            "schema": "gate14re-formal-block-output-v2",
            "studyId": "Gate14Re",
            "status": "COMPLETE",
            "blockId": block_id,
            "blockSequence": sequence,
            "module": block["module"],
            "lane": block["lane"],
            "conditionId": block["conditionId"],
            "scenarioId": block["scenarioId"],
            "scenarioSha256": block["scenarioSha256"],
            "unitCount": block["unitCount"],
            "blockIndex": block["blockIndex"],
            "williamsRow": block["williamsRow"],
            "planSha256": EXPECTED["plan_sha256"],
            "executableSha256": EXPECTED["executable_sha256"],
            "assemblyCSharpSha256": EXPECTED["assembly_sha256"],
            "buildReceiptSha256": EXPECTED["build_receipt_sha256"],
            "authorizationId": EXPECTED["authorization_id"],
            "completeFourAlgorithmBlock": True,
            "formalObservationProduced": True,
            "formalPhaseA": True,
        }
        for key, expected_value in identity_expectations.items():
            require(output.get(key) == expected_value, "BLOCK_IDENTITY_BINDING_MISMATCH", f"{output_rel};field={key}")

        lane = block["lane"]
        samples = output["movement"] if lane == "movement" else output["m4"]
        other_samples = output["m4"] if lane == "movement" else output["movement"]
        require(len(samples) == 4 and len(other_samples) == 0, "BLOCK_LANE_SAMPLE_CARDINALITY_MISMATCH", output_rel)
        for index, sample in enumerate(samples):
            expected_position = index + 1
            require(sample.get("orderPosition") == expected_position, "SAMPLE_ORDER_POSITION_MISMATCH", f"{output_rel};position={expected_position}")
            require(sample.get("algorithmLabel") == block["algorithmLabelsInOrder"][index], "SAMPLE_LABEL_ORDER_MISMATCH", f"{output_rel};position={expected_position}")
            require(sample.get("productionAlgorithmId") == block["algorithmIdsInOrder"][index], "SAMPLE_ALGORITHM_ORDER_MISMATCH", f"{output_rel};position={expected_position}")
            require(sample.get("unitCount") == block["unitCount"], "SAMPLE_UNIT_COUNT_BINDING_MISMATCH", f"{output_rel};position={expected_position}")
            if lane == "movement":
                units = sample.get("units")
                require(isinstance(units, list) and len(units) == block["unitCount"], "MOVEMENT_UNIT_CARDINALITY_MISMATCH", f"{output_rel};position={expected_position}")
                movement_units_structurally_counted += len(units)
            else:
                intervals = sample.get("frameIntervalsSeconds")
                require(isinstance(intervals, list) and len(intervals) == 1800, "M4_INTERVAL_CARDINALITY_MISMATCH", f"{output_rel};position={expected_position}")
                require(sample.get("unitsWithEnabledRenderer") == block["unitCount"], "M4_RENDERED_UNIT_CARDINALITY_MISMATCH", f"{output_rel};position={expected_position}")
                m4_frame_intervals_structurally_counted += len(intervals)
        algorithm_lane_samples += len(samples)
        movement_blocks += int(lane == "movement")
        m4_blocks += int(lane == "m4")
        del output

        if sequence % 128 == 0 or sequence == EXPECTED["planned_blocks"]:
            print(f"STRUCTURAL_BLOCKS_VALIDATED={sequence}/{EXPECTED['planned_blocks']}", flush=True)

    require(movement_blocks == 768, "MOVEMENT_BLOCK_COUNT_MISMATCH", str(movement_blocks))
    require(m4_blocks == 768, "M4_BLOCK_COUNT_MISMATCH", str(m4_blocks))
    require(algorithm_lane_samples == EXPECTED["planned_algorithm_lane_samples"], "ALGORITHM_LANE_SAMPLE_COUNT_MISMATCH", str(algorithm_lane_samples))

    actual_files = {
        relative(path)
        for path in FORMAL_ROOT.rglob("*")
        if path.is_file()
    }
    actual_dirs = {
        relative(path)
        for path in FORMAL_ROOT.rglob("*")
        if path.is_dir()
    }
    symlinks = [relative(path) for path in FORMAL_ROOT.rglob("*") if path.is_symlink()]
    require(not symlinks, "SYMLINKS_FORBIDDEN", symlinks[0] if symlinks else "")
    missing_files = sorted(expected_files - actual_files)
    extra_files = sorted(actual_files - expected_files)
    missing_dirs = sorted(expected_dirs - actual_dirs)
    extra_dirs = sorted(actual_dirs - expected_dirs)
    require(not missing_files, "EXPECTED_FILES_MISSING", missing_files[0] if missing_files else "")
    require(not extra_files, "UNEXPECTED_FILES_PRESENT", extra_files[0] if extra_files else "")
    require(not missing_dirs, "EXPECTED_DIRECTORIES_MISSING", missing_dirs[0] if missing_dirs else "")
    require(not extra_dirs, "UNEXPECTED_DIRECTORIES_PRESENT", extra_dirs[0] if extra_dirs else "")

    actual_log_names = {path.name for path in (FORMAL_ROOT / "logs").iterdir() if path.is_file()}
    require(actual_log_names == expected_log_names, "PLAYER_LOG_NAME_SET_MISMATCH")
    require(len(expected_files) == 4612, "PRECOMMIT_FILE_COUNT_INTERNAL_MISMATCH", str(len(expected_files)))

    counts = {
        "preCommitFiles": len(expected_files),
        "movementBlocks": movement_blocks,
        "m4Blocks": m4_blocks,
        "algorithmLaneSamples": algorithm_lane_samples,
        # These are cardinalities only, not performance outcomes.
        "movementUnitRecords": movement_units_structurally_counted,
        "m4FrameIntervalRecords": m4_frame_intervals_structurally_counted,
        "playerLogs": len(expected_log_names),
    }
    return expected_files, hash_cache, counts


def build_canonical_tree(
    expected_files: Iterable[str], hash_cache: dict[str, str]
) -> tuple[bytes, list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    raw_bytes = 0
    for index, rel in enumerate(sorted(expected_files), start=1):
        path = FORMAL_ROOT / Path(rel)
        size = path.stat().st_size
        digest = hash_cache.get(rel)
        if digest is None:
            digest = sha256_file(path)
        records.append({"bytes": size, "relativePath": rel, "sha256": digest})
        raw_bytes += size
        if index % 512 == 0 or index == 4612:
            print(f"CANONICAL_TREE_FILES_HASHED={index}/4612", flush=True)
    payload = b"".join(canonical_json_bytes(record) for record in records)
    return payload, records, raw_bytes


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_failure_receipt(reason: str) -> None:
    if FAILURE_RECEIPT.exists():
        return
    payload = {
        "schema": "gate14re-formal-phase-a-raw-commit-failure-receipt-v1",
        "studyId": "Gate14Re",
        "status": "FAIL_CLOSED",
        "formalRoot": FORMAL_ROOT.as_posix(),
        "failureUtc": utc_now(),
        "reason": reason,
        "formalAnalysisStarted": False,
        "phaseBStarted": False,
        "gate15Started": False,
        "outcomeValuesReported": False,
        "automaticRetryAuthorized": False,
    }
    atomic_create(FAILURE_RECEIPT, canonical_json_bytes(payload, pretty=True))
    set_readonly(FAILURE_RECEIPT)


def commit_raw(
    counts: dict[str, int],
    tree_payload: bytes,
    raw_bytes: int,
) -> dict[str, Any]:
    tree_path = FORMAL_ROOT / TREE_REL
    manifest_path = FORMAL_ROOT / MANIFEST_REL
    raw_complete_path = FORMAL_ROOT / RAW_COMPLETE_REL

    auditor_hash = sha256_file(SCRIPT_PATH)
    tree_hash = hashlib.sha256(tree_payload).hexdigest()
    atomic_create(tree_path, tree_payload)
    require(sha256_file(tree_path) == tree_hash, "WRITTEN_TREE_HASH_MISMATCH")

    manifest = {
        "schema": "gate14re-formal-phase-a-raw-commit-manifest-v1",
        "studyId": "Gate14Re",
        "status": "PASS",
        "formalRoot": FORMAL_ROOT.as_posix(),
        "commitUtc": utc_now(),
        "authorizationId": EXPECTED["authorization_id"],
        "fixedB": EXPECTED["fixed_b"],
        "acceptedBlocks": EXPECTED["planned_blocks"],
        "plannedBlocks": EXPECTED["planned_blocks"],
        "launchedProcesses": EXPECTED["planned_blocks"],
        "wholeBlockReplacements": 0,
        "processRetryResumeTopUpMergeSkipOrReorder": False,
        "structuralCounts": counts,
        "frozenBindings": {
            "authorizationSha256": EXPECTED["authorization_sha256"],
            "planSha256": EXPECTED["plan_sha256"],
            "executionContractSha256": EXPECTED["execution_contract_sha256"],
            "outputSchemaSha256": EXPECTED["output_schema_sha256"],
            "executableSha256": EXPECTED["executable_sha256"],
            "assemblyCSharpSha256": EXPECTED["assembly_sha256"],
            "buildReceiptSha256": EXPECTED["build_receipt_sha256"],
            "buildCanonicalTreeSha256": EXPECTED["build_tree_sha256"],
            "buildFreezeReceiptSha256": EXPECTED["build_freeze_sha256"],
            "supervisorSha256": EXPECTED["supervisor_sha256"],
            "externalLaunchReceiptSha256": EXPECTED["external_launch_sha256"],
        },
        "canonicalTree": {
            "path": TREE_REL,
            "records": counts["preCommitFiles"],
            "rawBytes": raw_bytes,
            "treeBytes": len(tree_payload),
            "sha256": tree_hash,
            "scope": "all pre-commit formal-root payload files; commit artifacts are separately bound",
        },
        "auditor": {
            "path": SCRIPT_PATH.relative_to(WORKSPACE).as_posix(),
            "sha256": auditor_hash,
            "schemaValidation": "draft-2020-12; sanitized structural errors only",
        },
        "outcomeBoundary": {
            "blockOutputsUsedOnlyFor": [
                "JSON-Schema validation",
                "frozen identity binding",
                "cardinality validation",
                "SHA-256 hashing",
            ],
            "playerLogsTreatedAsOpaqueBytes": True,
            "m1ThroughM5ExtractedAggregatedComparedInterpretedOrReported": False,
        },
        "formalAnalysisStarted": False,
        "phaseBStarted": False,
        "gate15Started": False,
    }
    manifest_payload = canonical_json_bytes(manifest, pretty=True)
    atomic_create(manifest_path, manifest_payload)
    manifest_hash = sha256_file(manifest_path)

    raw_complete = {
        "schema": "gate14re-formal-phase-a-raw-complete-receipt-v1",
        "studyId": "Gate14Re",
        "status": "FORMAL-PHASE-A-RAW-COMPLETE",
        "nextState": "FORMAL-ANALYSIS-PENDING",
        "immutability": "WINDOWS-READONLY-PLUS-SHA256-FROZEN",
        "hardwareWormOrAclImmutabilityClaimed": False,
        "formalRoot": FORMAL_ROOT.as_posix(),
        "commitUtc": utc_now(),
        "authorizationId": EXPECTED["authorization_id"],
        "fixedB": EXPECTED["fixed_b"],
        "acceptedBlocks": EXPECTED["planned_blocks"],
        "algorithmLaneSamples": EXPECTED["planned_algorithm_lane_samples"],
        "launchedProcesses": EXPECTED["planned_blocks"],
        "wholeBlockReplacements": 0,
        "processRetryResumeTopUpMergeSkipOrReorder": False,
        "rawCommitManifest": {
            "path": MANIFEST_REL,
            "sha256": manifest_hash,
        },
        "canonicalTree": {
            "path": TREE_REL,
            "records": counts["preCommitFiles"],
            "rawBytes": raw_bytes,
            "sha256": tree_hash,
        },
        "preCommitPayloadFiles": counts["preCommitFiles"],
        "postCommitRootFiles": counts["preCommitFiles"] + 3,
        "allRootFilesReadOnly": True,
        "formalAnalysisStarted": False,
        "winnerAdjudicationStarted": False,
        "phaseBStarted": False,
        "gate15Started": False,
        "m1ThroughM5ResultsReported": False,
    }
    raw_payload = canonical_json_bytes(raw_complete, pretty=True)

    # Freeze the auditor and every root file that exists before the final marker.
    set_readonly(SCRIPT_PATH)
    for path in sorted((p for p in FORMAL_ROOT.rglob("*") if p.is_file()), key=lambda p: relative(p)):
        set_readonly(path)
    pre_marker_files = [p for p in FORMAL_ROOT.rglob("*") if p.is_file()]
    require(all(is_readonly(path) for path in pre_marker_files), "PRE_MARKER_READONLY_VERIFICATION_FAILED")

    # Build the final marker outside the formal root, freeze it, then atomically
    # move it into place.  This prevents an unfrozen success marker from being
    # visible inside the formal root.
    pending_marker = VERIFY_ROOT / ".raw-data-complete.pending.json"
    if pending_marker.exists():
        clear_readonly(pending_marker)
        pending_marker.unlink()
    atomic_create(pending_marker, raw_payload)
    set_readonly(pending_marker)
    require(is_readonly(pending_marker), "PENDING_MARKER_NOT_READONLY")
    require(not raw_complete_path.exists(), "RAW_COMPLETE_RACE_DETECTED")
    os.replace(pending_marker, raw_complete_path)
    require(is_readonly(raw_complete_path), "RAW_COMPLETE_NOT_READONLY")

    # Directory ReadOnly attributes are documentary on Windows; file-level
    # ReadOnly plus the canonical SHA-256 tree is the enforced mechanism.
    directories = sorted(
        (path for path in FORMAL_ROOT.rglob("*") if path.is_dir()),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for directory in directories:
        set_readonly(directory)
    set_readonly(FORMAL_ROOT)

    all_files = [path for path in FORMAL_ROOT.rglob("*") if path.is_file()]
    require(len(all_files) == counts["preCommitFiles"] + 3, "POST_COMMIT_FILE_COUNT_MISMATCH", str(len(all_files)))
    require(all(is_readonly(path) for path in all_files), "POST_COMMIT_READONLY_VERIFICATION_FAILED")

    raw_complete_hash = sha256_file(raw_complete_path)
    audit_receipt = {
        "schema": "gate14re-formal-phase-a-structural-audit-receipt-v1",
        "studyId": "Gate14Re",
        "status": "PASS",
        "terminalState": "FORMAL-PHASE-A-RAW-COMPLETE / FORMAL-ANALYSIS-PENDING / IMMUTABLE",
        "formalRoot": FORMAL_ROOT.as_posix(),
        "completedUtc": utc_now(),
        "acceptedBlocks": EXPECTED["planned_blocks"],
        "algorithmLaneSamples": EXPECTED["planned_algorithm_lane_samples"],
        "launchedProcesses": EXPECTED["planned_blocks"],
        "wholeBlockReplacements": 0,
        "canonicalTreeSha256": tree_hash,
        "canonicalTreeRecords": counts["preCommitFiles"],
        "canonicalTreeRawBytes": raw_bytes,
        "manifestSha256": manifest_hash,
        "rawCompleteReceiptSha256": raw_complete_hash,
        "auditorSha256": auditor_hash,
        "allFormalRootFilesReadOnly": True,
        "m1ThroughM5ResultsReported": False,
        "formalAnalysisAuthorized": False,
        "winnerAdjudicationAuthorized": False,
        "phaseBAuthorized": False,
        "gate15Authorized": False,
    }
    atomic_create(AUDIT_RECEIPT, canonical_json_bytes(audit_receipt, pretty=True))
    set_readonly(AUDIT_RECEIPT)
    require(is_readonly(AUDIT_RECEIPT), "AUDIT_RECEIPT_NOT_READONLY")

    return {
        "status": audit_receipt["terminalState"],
        "acceptedBlocks": EXPECTED["planned_blocks"],
        "algorithmLaneSamples": EXPECTED["planned_algorithm_lane_samples"],
        "launchedProcesses": EXPECTED["planned_blocks"],
        "wholeBlockReplacements": 0,
        "preCommitFiles": counts["preCommitFiles"],
        "postCommitFiles": counts["preCommitFiles"] + 3,
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": tree_hash,
        "manifestSha256": manifest_hash,
        "rawCompleteReceiptSha256": raw_complete_hash,
        "auditReceiptSha256": sha256_file(AUDIT_RECEIPT),
        "allFormalRootFilesReadOnly": True,
        "m1ThroughM5ResultsReported": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("validate", "commit"), required=True)
    args = parser.parse_args()

    require(FORMAL_ROOT.is_dir(), "FORMAL_ROOT_MISSING", FORMAL_ROOT.as_posix())
    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    validate_frozen_bindings()
    validate_acquisition_control()
    _, blocks, blocks_by_sequence = validate_plan()
    accepted = validate_ledger(blocks_by_sequence)
    schema = load_json(OUTPUT_SCHEMA)
    expected_files, hash_cache, counts = validate_block_outputs(blocks, accepted, schema)
    tree_payload, _, raw_bytes = build_canonical_tree(expected_files, hash_cache)

    validation_summary = {
        "status": "PASS",
        "mode": args.mode,
        "acceptedBlocks": EXPECTED["planned_blocks"],
        "algorithmLaneSamples": EXPECTED["planned_algorithm_lane_samples"],
        "preCommitFiles": counts["preCommitFiles"],
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": hashlib.sha256(tree_payload).hexdigest(),
        "m1ThroughM5ResultsReported": False,
    }
    if args.mode == "validate":
        print(json.dumps(validation_summary, sort_keys=True), flush=True)
        return 0

    result = commit_raw(counts, tree_payload, raw_bytes)
    print(json.dumps(result, sort_keys=True), flush=True)
    return 0


if __name__ == "__main__":
    success_marker = FORMAL_ROOT / RAW_COMPLETE_REL
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        reason = f"{type(exc).__name__}: {exc}"
        # If a final marker was moved in but a later verification failed, move
        # our newly created marker out of the formal root before recording the
        # fail-closed receipt.  Pre-existing experimental payload is untouched.
        if success_marker.exists():
            try:
                clear_readonly(success_marker)
                invalidated = VERIFY_ROOT / "invalidated-raw-data-complete.v1.json"
                if not invalidated.exists():
                    os.replace(success_marker, invalidated)
                    set_readonly(invalidated)
            except Exception:
                pass
        try:
            write_failure_receipt(reason)
        except Exception:
            pass
        print(json.dumps({"status": "FAIL_CLOSED", "reason": reason}, sort_keys=True), file=sys.stderr, flush=True)
        raise SystemExit(1)
