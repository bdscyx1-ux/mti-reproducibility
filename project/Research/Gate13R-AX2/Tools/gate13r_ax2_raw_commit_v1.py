#!/usr/bin/env python3
"""Independent structural raw commit for Gate13R-AX2.

The commit validates cardinality, frozen bindings, process/block receipts, paths,
schemas, and hashes.  It never aggregates or interprets P1 and never produces an
algorithm comparison.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import stat
import sys
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class RawCommitError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RawCommitError(message)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def load_json(path: pathlib.Path) -> Any:
    require(path.is_file(), f"Required JSON is missing: {path}")
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise RawCommitError(f"Invalid JSON at {path}: {exc}") from exc


def import_structural_tool(path: pathlib.Path):
    require(path.is_file(), f"Structural tool is missing: {path}")
    specification = importlib.util.spec_from_file_location("gate13r_ax2_structural_v1", path)
    require(specification is not None and specification.loader is not None, "Unable to load structural tool.")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def relative_posix(path: pathlib.Path, root: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def walk_raw_files(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] == "_commit":
            continue
        yield path


def build_file_manifest(root: pathlib.Path) -> Tuple[List[Dict[str, Any]], str]:
    entries: List[Dict[str, Any]] = []
    tree_digest = hashlib.sha256()
    for path in walk_raw_files(root):
        entry = {
            "relativePath": relative_posix(path, root),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        encoded = (json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        tree_digest.update(encoded)
        entries.append(entry)
    require(entries, "Raw root contains no files.")
    return entries, tree_digest.hexdigest()


def set_read_only(root: pathlib.Path) -> int:
    count = 0
    for path in sorted(root.rglob("*"), reverse=True):
        if path.is_file():
            current = path.stat().st_mode
            path.chmod(current & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
            count += 1
    return count


def validate_binding(path: pathlib.Path, expected_sha256: str, label: str) -> None:
    require(HEX64.fullmatch(expected_sha256) is not None, f"{label} expected SHA-256 is malformed.")
    require(path.is_file(), f"{label} is missing: {path}")
    actual = sha256_file(path)
    require(actual == expected_sha256, f"{label} SHA-256 mismatch: expected {expected_sha256}, got {actual}.")


def validate_formal_authorization(args: argparse.Namespace) -> Dict[str, Any]:
    require(args.authorization is not None and args.authorization_sha256 is not None, "Formal commit requires an authorization receipt binding.")
    require(args.final_readiness is not None and args.final_readiness_sha256 is not None, "Formal commit requires a final-readiness binding.")
    validate_binding(args.authorization.resolve(), args.authorization_sha256.lower(), "Authorization receipt")
    validate_binding(args.final_readiness.resolve(), args.final_readiness_sha256.lower(), "Final readiness receipt")
    authorization = load_json(args.authorization.resolve())
    readiness = load_json(args.final_readiness.resolve())
    require(authorization.get("designId") == DESIGN_ID, "Authorization design identity mismatch.")
    require(authorization.get("formalCollectionAuthorized") is True, "Authorization receipt does not authorize formal collection.")
    require(readiness.get("designId") == DESIGN_ID and readiness.get("status") == "FINAL-READINESS-PASS", "Final readiness status/design mismatch.")
    return {
        "authorizationPath": str(args.authorization.resolve()),
        "authorizationSha256": args.authorization_sha256.lower(),
        "authorizationId": authorization.get("authorizationId"),
        "finalReadinessPath": str(args.final_readiness.resolve()),
        "finalReadinessSha256": args.final_readiness_sha256.lower(),
    }


def validate_collection(args: argparse.Namespace, structural) -> Dict[str, Any]:
    root = args.measured_root.resolve()
    require(root.is_dir(), f"Measured root is missing: {root}")
    normalized = str(root).replace("\\", "/").lower()
    if args.mode == "formal":
        require("/research/formalruns/gate13r-ax2/" in normalized, "Formal raw commit root is outside Gate13R-AX2 FormalRuns.")
        require(args.expected_blocks == 1536, "Formal raw commit requires exactly 1536 blocks.")
    else:
        require("/research/verification/gate13r-ax2/" in normalized, "Verification raw commit root is outside Gate13R-AX2 verification space.")
        require(1 <= args.expected_blocks < 1536, "Verification raw commit block count must be between 1 and 1535.")
    require(not (root / "_commit").exists(), "A raw commit directory already exists; overwrite/recommit is forbidden.")
    failure_path = root / "_control" / "failure-receipt.v1.json"
    require(not failure_path.exists(), "Collection has a failure receipt and cannot be committed.")
    acquisition = load_json(root / "_control" / "acquisition-complete.v1.json")
    require(acquisition.get("designId") == DESIGN_ID, "Acquisition completion design mismatch.")
    require(acquisition.get("status") in ("VERIFICATION-ACQUISITION-COMPLETE", "FORMAL-ACQUISITION-COMPLETE"), "Acquisition is not complete.")
    require(acquisition.get("acceptedBlocks") == args.expected_blocks, "Acquisition accepted-block count mismatch.")
    require(acquisition.get("acceptedAnonymousSamples") == args.expected_blocks * 4, "Acquisition sample count mismatch.")
    require(acquisition.get("noPerAlgorithmRetryResumeTopUpMergeSkipReorder") is True, "Acquisition receipt does not affirm forbidden-action invariant.")
    schedule_records = structural.load_schedule(args.schedule.resolve(), args.schedule_sha256.lower())
    schedule_by_id = {record["blockId"]: record for record in schedule_records}
    accepted_dir = root / "_control" / "accepted-blocks"
    require(accepted_dir.is_dir(), "Accepted-block receipt directory is missing.")
    accepted_paths = sorted(accepted_dir.glob("*.v1.json"))
    require(len(accepted_paths) == args.expected_blocks, f"Expected {args.expected_blocks} accepted-block receipts, found {len(accepted_paths)}.")
    observed_block_ids: set[str] = set()
    process_keys: set[Tuple[int, str]] = set()
    replacement_count = 0
    accepted_attempt_paths: List[str] = []
    for accepted_path in accepted_paths:
        receipt = load_json(accepted_path)
        require(receipt.get("artifactKind") == "GATE13R-AX2-ACCEPTED-BLOCK", f"Accepted receipt kind mismatch: {accepted_path}")
        block_id = receipt.get("blockId")
        require(isinstance(block_id, str) and block_id in schedule_by_id and block_id not in observed_block_ids, f"Accepted receipt has an unknown/duplicate blockId: {block_id}")
        observed_block_ids.add(block_id)
        require(receipt.get("attemptNumber") in (1, 2), f"Accepted block {block_id} has an invalid attempt number.")
        replacement_count += 1 if receipt.get("attemptNumber") == 2 else 0
        attempt_relative = receipt.get("attemptRelativePath")
        attempt_root = structural.resolve_relative(root, attempt_relative, f"accepted block {block_id}")
        require(attempt_root.is_dir(), f"Accepted block attempt is missing: {attempt_root}")
        process_id = receipt.get("processId")
        process_start = receipt.get("processStartUtc")
        require(isinstance(process_id, int) and process_id > 0 and isinstance(process_start, str) and process_start, f"Accepted block {block_id} process identity is malformed.")
        require((process_id, process_start) not in process_keys, f"Accepted block {block_id} reuses a process identity.")
        process_keys.add((process_id, process_start))
        structural_receipt = structural.resolve_relative(root, receipt.get("structuralReceiptRelativePath"), f"accepted block {block_id} structural receipt")
        require(structural_receipt.is_file() and sha256_file(structural_receipt) == receipt.get("structuralReceiptSha256"), f"Accepted block {block_id} structural receipt binding mismatch.")
        validation = structural.validate_block(
            attempt_root, args.schedule.resolve(), args.schedule_sha256.lower(),
            args.schema.resolve(), args.schema_sha256.lower(), args.contract_sha256.lower(),
            block_id, process_id,
        )
        require(validation["sampleCount"] == 4 and validation["p1AggregatedOrInterpreted"] is False, f"Accepted block {block_id} structural validation result is invalid.")
        accepted_attempt_paths.append(attempt_relative)
    require(replacement_count == acquisition.get("wholeBlockReplacements"), "Whole-block replacement ledger mismatch.")
    require(replacement_count <= args.expected_blocks, "Replacement count exceeds one per accepted block.")
    all_process_receipts = sorted((root / "_control" / "process-receipts").glob("*.v1.json"))
    require(len(all_process_receipts) == acquisition.get("launchedProcesses"), "Process-receipt count does not match acquisition ledger.")
    for path in all_process_receipts:
        receipt = load_json(path)
        require(receipt.get("artifactKind") == "GATE13R-AX2-PROCESS-RECEIPT", f"Process receipt kind mismatch: {path}")
        require(receipt.get("freshProcessForCompleteBlockAttempt") is True, f"Process receipt fresh-process invariant failed: {path}")
        require(receipt.get("perAlgorithmRetryResumeTopUpMergeSkipReorder") is False, f"Process receipt forbidden-action invariant failed: {path}")
    expected_first = {record["blockId"] for record in schedule_records[: args.expected_blocks]}
    require(observed_block_ids == expected_first, "Accepted blocks are not the exact frozen schedule prefix for this acquisition.")
    return {
        "measuredRoot": str(root),
        "expectedBlocks": args.expected_blocks,
        "completeBlocks": len(observed_block_ids),
        "anonymousSamples": len(observed_block_ids) * 4,
        "freshProcessReceipts": len(all_process_receipts),
        "wholeBlockReplacements": replacement_count,
        "uniqueAcceptedProcessIdentities": len(process_keys),
        "acceptedAttemptPaths": accepted_attempt_paths,
        "p1AggregatedOrInterpreted": False,
        "perAlgorithmRetryResumeTopUpMergeSkipReorder": 0,
    }


def command_commit(args: argparse.Namespace) -> int:
    args.schedule_sha256 = args.schedule_sha256.lower()
    args.schema_sha256 = args.schema_sha256.lower()
    args.contract_sha256 = args.contract_sha256.lower()
    args.structural_tool_sha256 = args.structural_tool_sha256.lower()
    validate_binding(args.schedule.resolve(), args.schedule_sha256, "Schedule")
    validate_binding(args.schema.resolve(), args.schema_sha256, "Output schema")
    validate_binding(args.contract.resolve(), args.contract_sha256, "Execution contract")
    validate_binding(args.structural_tool.resolve(), args.structural_tool_sha256, "Structural tool")
    authorization = None
    if args.mode == "formal":
        authorization = validate_formal_authorization(args)
    structural = import_structural_tool(args.structural_tool.resolve())
    collection = validate_collection(args, structural)
    root = args.measured_root.resolve()
    commit_root = root / "_commit"
    commit_root.mkdir(parents=False, exist_ok=False)
    entries, tree_sha256 = build_file_manifest(root)
    manifest_path = commit_root / "raw-manifest.v1.jsonl"
    with manifest_path.open("xb") as stream:
        for entry in entries:
            stream.write((json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))
    canonical_tree = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-RAW-CANONICAL-TREE",
        "designId": DESIGN_ID,
        "mode": args.mode,
        "fileCount": len(entries),
        "canonicalTreeSha256": tree_sha256,
        "manifestRelativePath": "_commit/raw-manifest.v1.jsonl",
        "manifestSha256": sha256_file(manifest_path),
        "entries": entries,
    }
    canonical_tree_path = commit_root / "canonical-tree.v1.json"
    write_json_new(canonical_tree_path, canonical_tree)
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-RAW-COMPLETE-RECEIPT",
        "designId": DESIGN_ID,
        "status": "FORMAL-RAW-COMPLETE" if args.mode == "formal" else "VERIFICATION-RAW-COMPLETE",
        "committedAtUtc": utc_now(),
        "mode": args.mode,
        "collection": collection,
        "bindings": {
            "scheduleSha256": args.schedule_sha256,
            "outputSchemaSha256": args.schema_sha256,
            "executionContractSha256": args.contract_sha256,
            "structuralToolSha256": args.structural_tool_sha256,
            "authorization": authorization,
        },
        "manifest": {
            "relativePath": "_commit/raw-manifest.v1.jsonl",
            "sha256": sha256_file(manifest_path),
            "fileCount": len(entries),
        },
        "canonicalTree": {
            "relativePath": "_commit/canonical-tree.v1.json",
            "sha256": sha256_file(canonical_tree_path),
            "treeSha256": tree_sha256,
        },
        "state": [
            "IMMUTABLE",
            "P1-ANALYSIS-PENDING" if args.mode == "formal" else "NONFORMAL-VALIDATION-COMPLETE",
        ],
        "p1AggregatedOrInterpreted": False,
        "originalGate13RRawOrAnalysisReadOrModified": False,
    }
    receipt_path = commit_root / "raw-complete-receipt.v1.json"
    write_json_new(receipt_path, receipt)
    read_only_files = set_read_only(root)
    print(json.dumps({
        "status": receipt["status"],
        "rawCompleteReceipt": str(receipt_path),
        "rawCompleteReceiptSha256": sha256_file(receipt_path),
        "fileCount": len(entries),
        "readOnlyFiles": read_only_files,
        "p1AggregatedOrInterpreted": False,
    }, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    commit = subparsers.add_parser("commit")
    commit.add_argument("--mode", choices=("verification", "formal"), required=True)
    commit.add_argument("--project-root", type=pathlib.Path, required=True)
    commit.add_argument("--measured-root", type=pathlib.Path, required=True)
    commit.add_argument("--schedule", type=pathlib.Path, required=True)
    commit.add_argument("--schedule-sha256", required=True)
    commit.add_argument("--schema", type=pathlib.Path, required=True)
    commit.add_argument("--schema-sha256", required=True)
    commit.add_argument("--contract", type=pathlib.Path, required=True)
    commit.add_argument("--contract-sha256", required=True)
    commit.add_argument("--structural-tool", type=pathlib.Path, required=True)
    commit.add_argument("--structural-tool-sha256", required=True)
    commit.add_argument("--expected-blocks", type=int, required=True)
    commit.add_argument("--authorization", type=pathlib.Path)
    commit.add_argument("--authorization-sha256")
    commit.add_argument("--final-readiness", type=pathlib.Path)
    commit.add_argument("--final-readiness-sha256")
    commit.set_defaults(handler=command_commit)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.handler(args)
    except (RawCommitError, OSError, ValueError, getattr(sys.modules.get("gate13r_ax2_structural_v1"), "StructuralError", RuntimeError)) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
