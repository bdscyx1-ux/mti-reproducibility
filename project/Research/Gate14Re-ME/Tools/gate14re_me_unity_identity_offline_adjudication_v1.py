#!/usr/bin/env python3
"""Deterministic offline adjudication of frozen Gate14Re-ME attempt-004 evidence.

This program has no process-launch or deletion capability.  It reads only the
source-freeze manifest and the project-local evidence named by that manifest,
then writes a new attempt-005 evidence package and status v17.  It never opens
the Unity executable itself and never changes attempt-004.
"""

from __future__ import annotations

import argparse
import ast
import ctypes
import ctypes.wintypes as wintypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import traceback
from typing import Any, Iterable


STUDY_ID = "Gate14Re-ME"
AUTHORIZATION_ID = (
    "gate14re-me-unity-executable-identity-rule-offline-evidence-adjudication-attempt-005"
)
ATTEMPT004_AUTHORIZATION_ID = (
    "gate14re-me-unity-executable-identity-rule-repair-attempt-004"
)
EXPECTED_UNITY_PATH = "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe"
EXPECTED_UNITY_SHA256 = (
    "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf"
)
EXPECTED_ATTEMPT004_ORCHESTRATOR_SHA256 = (
    "3317558dd838137c7fba783262d465b967da60e232e6a64c10d1af1acf23a747"
)
EXPECTED_ATTEMPT004_FAILURE_SHA256 = (
    "883f688d7d07a10bab4a5bbd2e186d2b74108bf0f01d65d61d84fc80ba8c543c"
)
EXPECTED_STATUS_V16_SHA256 = (
    "6e7b993b64fccc114038bf70b56721ed2c0568c454d2a90852d9d5eeabaa9d1e"
)
EXPECTED_ATTEMPT004_FILE_COUNT = 34
EXPECTED_ATTEMPT004_INVENTORY_DIGEST = (
    "cc345167106631a73b437ead78acc315856851c25ee100937daf13b1e02fa10c"
)
EXPECTED_EXECUTE_METHOD = (
    "DDM.Research.Editor.UnityExecutableIdentityAuditAttempt001."
    "Gate14ReMEUnityExecutableIdentityAuditV1.Run"
)
ATTEMPT004_REL = (
    "Research/Verification/Gate14Re-ME/"
    "unity-executable-identity-rule-repair-attempt-004"
)
STAGE_REL = (
    "Research/Verification/Gate14Re-ME/"
    "unity-executable-identity-rule-offline-adjudication-attempt-005"
)
STATUS_V16_REL = "Research/Gate14Re-ME/Gate14Re_ME_Status.v16.json"
STATUS_V17_REL = "Research/Gate14Re-ME/Gate14Re_ME_Status.v17.json"
ATTEMPT004_ORCHESTRATOR_REL = (
    "Research/Gate14Re-ME/Tools/Invoke-Gate14ReMEUnityExecutableIdentityAuditV4.ps1"
)


class AdjudicationError(RuntimeError):
    """A fail-closed adjudication error."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def parse_utc(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def write_json_exclusive(path: Path, value: Any) -> None:
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(payload)


def normalize_path(value: str | Path) -> str:
    return os.path.abspath(os.fspath(value)).replace("\\", "/").casefold()


def project_path(project_root: Path, relative_path: str) -> Path:
    if os.path.isabs(relative_path):
        raise AdjudicationError(f"Expected project-relative path, got: {relative_path}")
    resolved = (project_root / Path(relative_path.replace("/", os.sep))).resolve()
    if os.path.commonpath((str(project_root), str(resolved))) != str(project_root):
        raise AdjudicationError(f"Path escapes project root: {relative_path}")
    return resolved


def is_read_only(path: Path) -> bool:
    info = path.stat()
    attributes = getattr(info, "st_file_attributes", 0)
    readonly_flag = getattr(stat, "FILE_ATTRIBUTE_READONLY", 1)
    return bool(attributes & readonly_flag)


def set_read_only(path: Path) -> None:
    os.chmod(path, stat.S_IREAD)


def inventory(root: Path) -> tuple[list[dict[str, Any]], str]:
    rows: list[dict[str, Any]] = []
    for path in sorted(
        (p for p in root.rglob("*") if p.is_file()),
        key=lambda p: p.relative_to(root).as_posix().casefold(),
    ):
        relative = path.relative_to(root).as_posix()
        rows.append(
            {
                "relativePath": relative,
                "lengthBytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "readOnly": is_read_only(path),
            }
        )
    digest_payload = "".join(
        f"{row['relativePath']}\t{row['lengthBytes']}\t{row['sha256']}\n"
        for row in rows
    ).encode("utf-8")
    return rows, sha256_bytes(digest_payload)


def get_hash(fingerprint: dict[str, Any], method: str) -> str | None:
    for item in fingerprint.get("fullFileHashes", []):
        if item.get("method") == method and item.get("succeeded") is True:
            return str(item.get("sha256", "")).lower()
    return None


def optional_hash(fingerprint: dict[str, Any], method: str) -> str | None:
    return get_hash(fingerprint, method)


def compare_chunks(left: list[dict[str, Any]], right: list[dict[str, Any]]) -> list[dict[str, Any]]:
    mismatches: list[dict[str, Any]] = []
    maximum = max(len(left), len(right))
    for index in range(maximum):
        lhs = left[index] if index < len(left) else None
        rhs = right[index] if index < len(right) else None
        equal = (
            lhs is not None
            and rhs is not None
            and int(lhs.get("chunkIndex", -1)) == int(rhs.get("chunkIndex", -2))
            and int(lhs.get("offsetBytes", -1)) == int(rhs.get("offsetBytes", -2))
            and int(lhs.get("lengthBytes", -1)) == int(rhs.get("lengthBytes", -2))
            and str(lhs.get("sha256", "")).lower()
            == str(rhs.get("sha256", "")).lower()
        )
        if not equal:
            mismatches.append(
                {
                    "chunkIndex": index,
                    "left": lhs,
                    "right": rhs,
                }
            )
    return mismatches


def structure_projection(fingerprint: dict[str, Any]) -> dict[str, Any]:
    file_identity = fingerprint.get("fileIdentity", {})
    pe_identity = fingerprint.get("peIdentity", {})
    return {
        "path": normalize_path(fingerprint.get("path", "")),
        "lengthBytes": int(fingerprint.get("lengthBytes", -1)),
        "creationTimeUtc": str(fingerprint.get("creationTimeUtc", "")),
        "lastWriteTimeUtc": str(fingerprint.get("lastWriteTimeUtc", "")),
        "attributes": str(fingerprint.get("attributes", "")),
        "fileIdentitySucceeded": file_identity.get("succeeded") is True,
        "fileIdentityNormalizedPath": normalize_path(file_identity.get("normalizedPath", "")),
        "fileIdentityFinalPath": normalize_path(file_identity.get("finalPath", "")),
        "volumeSerialHex": str(file_identity.get("volumeSerialHex", "")).lower(),
        "fileIndexHex": str(file_identity.get("fileIndexHex", "")).lower(),
        "peIdentitySucceeded": pe_identity.get("succeeded") is True,
        "peHeaderOffset": int(pe_identity.get("peHeaderOffset", -1)),
        "optionalHeaderMagicHex": str(pe_identity.get("optionalHeaderMagicHex", "")).lower(),
        "checksumFieldOffset": int(pe_identity.get("checksumFieldOffset", -1)),
        "checksumHex": str(pe_identity.get("checksumHex", "")).lower(),
        "securityDirectoryFieldOffset": int(pe_identity.get("securityDirectoryFieldOffset", -1)),
        "certificateTableFileOffset": int(pe_identity.get("certificateTableFileOffset", -1)),
        "certificateTableSizeBytes": int(pe_identity.get("certificateTableSizeBytes", -1)),
    }


def pair_value(arguments: list[str], key: str) -> str | None:
    positions = [index for index, value in enumerate(arguments) if value == key]
    if len(positions) != 1:
        return None
    index = positions[0]
    return arguments[index + 1] if index + 1 < len(arguments) else None


def add_check(
    checks: list[dict[str, Any]],
    check_id: str,
    passed: bool,
    detail: Any,
    authoritative: bool = True,
) -> None:
    checks.append(
        {
            "checkId": check_id,
            "authoritative": authoritative,
            "passed": bool(passed),
            "detail": detail,
        }
    )


def verify_no_process_or_delete_primitives(source_path: Path) -> tuple[bool, list[str]]:
    tree = ast.parse(source_path.read_text(encoding="utf-8"), filename=str(source_path))
    forbidden_imports = {"subprocess", "multiprocessing"}
    forbidden_calls = {
        "system",
        "popen",
        "startfile",
        "spawnl",
        "spawnle",
        "spawnlp",
        "spawnlpe",
        "spawnv",
        "spawnve",
        "spawnvp",
        "spawnvpe",
        "execl",
        "execle",
        "execlp",
        "execlpe",
        "execv",
        "execve",
        "execvp",
        "execvpe",
        "remove",
        "removedirs",
        "unlink",
        "rmdir",
        "rmtree",
    }
    findings: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name.split(".")[0] in forbidden_imports:
                    findings.append(f"import:{alias.name}@{node.lineno}")
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] in forbidden_imports:
                findings.append(f"from-import:{node.module}@{node.lineno}")
        elif isinstance(node, ast.Call):
            name = None
            if isinstance(node.func, ast.Name):
                name = node.func.id
            elif isinstance(node.func, ast.Attribute):
                name = node.func.attr
            if name and name.casefold() in forbidden_calls:
                findings.append(f"call:{name}@{node.lineno}")
    return not findings, findings


def unity_process_ids() -> list[int]:
    """Enumerate process metadata via Win32 Toolhelp; never starts or signals a process."""

    if os.name != "nt":
        raise AdjudicationError("Attempt-005 is frozen for the authorized Windows host.")

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * 260),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    create_snapshot = kernel32.CreateToolhelp32Snapshot
    create_snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    create_snapshot.restype = wintypes.HANDLE
    process_first = kernel32.Process32FirstW
    process_first.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    process_first.restype = wintypes.BOOL
    process_next = kernel32.Process32NextW
    process_next.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    process_next.restype = wintypes.BOOL
    close_handle = kernel32.CloseHandle
    close_handle.argtypes = [wintypes.HANDLE]
    close_handle.restype = wintypes.BOOL

    snapshot = create_snapshot(0x00000002, 0)
    invalid_handle = ctypes.c_void_p(-1).value
    if snapshot == invalid_handle:
        raise ctypes.WinError(ctypes.get_last_error())
    matches: list[int] = []
    try:
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        success = process_first(snapshot, ctypes.byref(entry))
        while success:
            if str(entry.szExeFile).casefold() == "unity.exe":
                matches.append(int(entry.th32ProcessID))
            success = process_next(snapshot, ctypes.byref(entry))
    finally:
        close_handle(snapshot)
    return sorted(matches)


def all_true(checks: Iterable[dict[str, Any]], *, authoritative_only: bool = True) -> bool:
    selected = (
        check for check in checks if not authoritative_only or check.get("authoritative") is True
    )
    return all(check.get("passed") is True for check in selected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--source-freeze-manifest", required=True)
    parser.add_argument("--source-freeze-manifest-sha256", required=True)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    source_manifest_path = Path(args.source_freeze_manifest).resolve()
    stage_root = project_path(project_root, STAGE_REL)
    status_v17_path = project_path(project_root, STATUS_V17_REL)
    checks: list[dict[str, Any]] = []
    attempt004_inventory_before: list[dict[str, Any]] = []
    attempt004_digest_before = ""
    created_stage = False

    try:
        if stage_root.exists():
            raise AdjudicationError(f"Attempt-005 output root already exists: {stage_root}")
        if status_v17_path.exists():
            raise AdjudicationError(f"Status v17 already exists: {status_v17_path}")
        if sha256_file(source_manifest_path) != args.source_freeze_manifest_sha256.lower():
            raise AdjudicationError("Attempt-005 source-freeze manifest SHA-256 mismatch.")

        source_manifest = load_json(source_manifest_path)
        if not (
            source_manifest.get("schema")
            == "gate14re-me-unity-identity-offline-adjudication-source-freeze-manifest-v1"
            and source_manifest.get("studyId") == STUDY_ID
            and source_manifest.get("authorizationId") == AUTHORIZATION_ID
            and source_manifest.get("status")
            == "FROZEN_PREEXECUTION_OFFLINE_ADJUDICATION_SOURCES"
        ):
            raise AdjudicationError("Attempt-005 source-freeze manifest header mismatch.")

        for binding in source_manifest.get("bindings", []):
            path = project_path(project_root, str(binding["relativePath"]))
            if not path.is_file():
                raise AdjudicationError(f"Missing source binding: {binding['relativePath']}")
            if path.stat().st_size != int(binding["lengthBytes"]):
                raise AdjudicationError(f"Source binding length mismatch: {binding['relativePath']}")
            if sha256_file(path) != str(binding["sha256"]).lower():
                raise AdjudicationError(f"Source binding SHA-256 mismatch: {binding['relativePath']}")
            if not is_read_only(path):
                raise AdjudicationError(f"Source binding is not read-only: {binding['relativePath']}")

        runtime = source_manifest.get("runtime", {})
        runtime_path = Path(str(runtime.get("absolutePath", ""))).resolve()
        if not runtime_path.is_file():
            raise AdjudicationError("Frozen Python runtime is missing.")
        if runtime_path.stat().st_size != int(runtime.get("lengthBytes", -1)):
            raise AdjudicationError("Frozen Python runtime length mismatch.")
        if sha256_file(runtime_path) != str(runtime.get("sha256", "")).lower():
            raise AdjudicationError("Frozen Python runtime SHA-256 mismatch.")
        if normalize_path(runtime_path) != normalize_path(sys.executable):
            raise AdjudicationError("Running Python executable differs from frozen runtime.")

        source_path = Path(__file__).resolve()
        primitive_safe, primitive_findings = verify_no_process_or_delete_primitives(source_path)
        add_check(
            checks,
            "attempt005-adjudicator-has-no-process-launch-or-delete-primitives",
            primitive_safe,
            {"findings": primitive_findings},
        )

        entry_unity_pids = unity_process_ids()
        add_check(
            checks,
            "no-unity-process-at-offline-adjudication-entry",
            len(entry_unity_pids) == 0,
            {"unityProcessIds": entry_unity_pids},
        )

        prohibited_roots = [
            "Research/QualificationRuns/Gate14Re-ME",
            "Research/PilotRuns/Gate14Re-ME",
            "Research/FormalRuns/Gate14Re-ME",
            "Research/MeasuredRuns/Gate14Re-ME",
        ]
        present_prohibited_roots = [
            relative for relative in prohibited_roots if project_path(project_root, relative).exists()
        ]
        add_check(
            checks,
            "no-gate14re-me-measured-root-present",
            len(present_prohibited_roots) == 0,
            {"present": present_prohibited_roots},
        )

        attempt004_root = project_path(project_root, ATTEMPT004_REL)
        attempt004_inventory_before, attempt004_digest_before = inventory(attempt004_root)
        expected_inventory = source_manifest.get("retainedAttempt004Inventory", {})
        add_check(
            checks,
            "attempt004-complete-inventory-frozen",
            len(attempt004_inventory_before) == EXPECTED_ATTEMPT004_FILE_COUNT
            and len(attempt004_inventory_before) == int(expected_inventory.get("fileCount", -1))
            and attempt004_digest_before == EXPECTED_ATTEMPT004_INVENTORY_DIGEST
            and attempt004_digest_before == expected_inventory.get("digestSha256")
            and all(row["readOnly"] for row in attempt004_inventory_before),
            {
                "fileCount": len(attempt004_inventory_before),
                "digestSha256": attempt004_digest_before,
                "allReadOnly": all(row["readOnly"] for row in attempt004_inventory_before),
            },
        )
        expected_entries = expected_inventory.get("entries", [])
        add_check(
            checks,
            "attempt004-inventory-entry-list-exact",
            [
                {key: row[key] for key in ("relativePath", "lengthBytes", "sha256")}
                for row in attempt004_inventory_before
            ]
            == expected_entries,
            {"expectedEntryCount": len(expected_entries)},
        )

        failure_path = attempt004_root / "failure-receipt.v1.json"
        status_v16_path = project_path(project_root, STATUS_V16_REL)
        orchestrator_v4_path = project_path(project_root, ATTEMPT004_ORCHESTRATOR_REL)
        add_check(
            checks,
            "attempt004-failure-receipt-byte-binding",
            sha256_file(failure_path) == EXPECTED_ATTEMPT004_FAILURE_SHA256,
            {"sha256": sha256_file(failure_path)},
        )
        add_check(
            checks,
            "status-v16-byte-binding",
            sha256_file(status_v16_path) == EXPECTED_STATUS_V16_SHA256,
            {"sha256": sha256_file(status_v16_path)},
        )
        add_check(
            checks,
            "attempt004-orchestrator-byte-binding",
            sha256_file(orchestrator_v4_path) == EXPECTED_ATTEMPT004_ORCHESTRATOR_SHA256,
            {"sha256": sha256_file(orchestrator_v4_path)},
        )

        failure = load_json(failure_path)
        status_v16 = load_json(status_v16_path)
        add_check(
            checks,
            "attempt004-failure-outcome-retained",
            failure.get("schema")
            == "gate14re-me-unity-executable-identity-rule-repair-failure-receipt-v1"
            and failure.get("studyId") == STUDY_ID
            and failure.get("authorizationId") == ATTEMPT004_AUTHORIZATION_ID
            and failure.get("status") == "FAILED_CLOSED_UNITY_EXECUTABLE_IDENTITY_RULE_REPAIR"
            and failure.get("classification") == "NOT_ADJUDICATED"
            and int(failure.get("unityInvocationCount", -1)) == 1
            and failure.get("retryPerformed") is False
            and failure.get("signalOrForcedTerminationSent") is False,
            {
                "status": failure.get("status"),
                "classification": failure.get("classification"),
                "unityInvocationCount": failure.get("unityInvocationCount"),
                "retryPerformed": failure.get("retryPerformed"),
                "signalOrForcedTerminationSent": failure.get("signalOrForcedTerminationSent"),
            },
        )
        add_check(
            checks,
            "status-v16-retains-attempt004-failure",
            status_v16.get("schema") == "gate14re-me-status-v16"
            and status_v16.get("status") == "UNITY_EXECUTABLE_IDENTITY_RULE_REPAIR_FAILED_CLOSED"
            and int(status_v16.get("version", -1)) == 16
            and status_v16.get("identityRuleRepair", {}).get("passed") is False
            and status_v16.get("identityRuleRepair", {}).get("classification")
            == "NOT_ADJUDICATED"
            and status_v16.get("identityRuleRepair", {}).get("failureReceiptSha256")
            == EXPECTED_ATTEMPT004_FAILURE_SHA256,
            {
                "status": status_v16.get("status"),
                "version": status_v16.get("version"),
                "identityRuleRepair": status_v16.get("identityRuleRepair"),
            },
        )

        pre = load_json(attempt004_root / "external-prelaunch-fingerprint.v1.json")
        concurrent = load_json(attempt004_root / "external-concurrent-fingerprint.v1.json")
        post = load_json(attempt004_root / "external-post-exit-fingerprint.v1.json")
        external = [pre, concurrent, post]
        expected_phases = [
            "EXTERNAL_PRELAUNCH",
            "EXTERNAL_WHILE_AUTHORIZED_PID_ALIVE",
            "EXTERNAL_POST_EXIT",
        ]
        add_check(
            checks,
            "external-fingerprint-headers-and-chronology",
            all(
                item.get("schema") == "gate14re-me-external-unity-executable-fingerprint-v1"
                and item.get("studyId") == STUDY_ID
                and item.get("authorizationId") == ATTEMPT004_AUTHORIZATION_ID
                and item.get("phase") == expected_phases[index]
                for index, item in enumerate(external)
            )
            and parse_utc(pre["capturedAtUtc"])
            < parse_utc(concurrent["capturedAtUtc"])
            < parse_utc(post["capturedAtUtc"]),
            {"phases": [item.get("phase") for item in external]},
        )

        hash_methods = ("powershell-get-filehash", "dotnet-sha256-filestream")
        external_hashes = [
            {method: get_hash(item, method) for method in hash_methods} for item in external
        ]
        external_hashes_trusted = all(
            item.get("independentHashMethodsAgree") is True
            and all(hashes[method] == EXPECTED_UNITY_SHA256 for method in hash_methods)
            for item, hashes in zip(external, external_hashes)
        )
        add_check(
            checks,
            "external-full-file-sha256-authoritative",
            external_hashes_trusted,
            {"expectedSha256": EXPECTED_UNITY_SHA256, "phases": external_hashes},
        )

        chunks_pre_concurrent = compare_chunks(pre.get("chunkHashes", []), concurrent.get("chunkHashes", []))
        chunks_pre_post = compare_chunks(pre.get("chunkHashes", []), post.get("chunkHashes", []))
        add_check(
            checks,
            "external-64kib-chunk-sets-stable",
            all(int(item.get("chunkSizeBytes", -1)) == 65536 for item in external)
            and len(pre.get("chunkHashes", [])) > 0
            and not chunks_pre_concurrent
            and not chunks_pre_post,
            {
                "chunkCounts": [len(item.get("chunkHashes", [])) for item in external],
                "preToConcurrentMismatchCount": len(chunks_pre_concurrent),
                "preToPostExitMismatchCount": len(chunks_pre_post),
            },
        )

        external_paths_stable = all(
            normalize_path(item.get("path", "")) == normalize_path(EXPECTED_UNITY_PATH)
            and normalize_path(item.get("fileIdentity", {}).get("normalizedPath", ""))
            == normalize_path(EXPECTED_UNITY_PATH)
            and item.get("reparsePoint") is False
            for item in external
        )
        file_ids = [item.get("fileIdentity", {}).get("fileIdHex") for item in external]
        file_low64 = [item.get("fileIdentity", {}).get("fileIndexLow64Hex") for item in external]
        external_file_id_stable = (
            all(item.get("fileIdentity", {}).get("succeeded") is True for item in external)
            and len(set(file_ids)) == 1
            and len(set(file_low64)) == 1
            and bool(file_ids[0])
            and bool(file_low64[0])
        )
        add_check(
            checks,
            "external-path-and-ntfs-file-id-stable",
            external_paths_stable and external_file_id_stable,
            {"paths": [item.get("path") for item in external], "fileIds": file_ids, "low64": file_low64},
        )

        pe_fields = (
            "peHeaderOffset",
            "optionalHeaderMagicHex",
            "checksumFieldOffset",
            "checksumHex",
            "securityDirectoryFieldOffset",
            "certificateTableFileOffset",
            "certificateTableSizeBytes",
        )
        pe_values = [tuple(item.get("peIdentity", {}).get(field) for field in pe_fields) for item in external]
        external_pe_stable = (
            all(item.get("peIdentity", {}).get("succeeded") is True for item in external)
            and len(set(pe_values)) == 1
        )
        signer_values = [
            (
                item.get("authenticode", {}).get("status"),
                item.get("authenticode", {}).get("signerSubject"),
                item.get("authenticode", {}).get("signerThumbprint"),
            )
            for item in external
        ]
        external_signer_stable = (
            all(value[0] == "Valid" for value in signer_values)
            and len(set(signer_values)) == 1
            and bool(signer_values[0][2])
        )
        metadata_values = [
            (
                item.get("lengthBytes"),
                item.get("creationTimeUtc"),
                item.get("lastWriteTimeUtc"),
                item.get("attributes"),
            )
            for item in external
        ]
        metadata_stable = len(set(metadata_values)) == 1
        add_check(
            checks,
            "external-pe-authenticode-and-metadata-stable",
            external_pe_stable and external_signer_stable and metadata_stable,
            {
                "peStable": external_pe_stable,
                "signerStable": external_signer_stable,
                "metadataStable": metadata_stable,
                "signerThumbprint": signer_values[0][2],
                "lengthBytes": metadata_values[0][0],
            },
        )

        launch = load_json(attempt004_root / "process-launch-receipt.v1.json")
        ready = load_json(attempt004_root / "unity-output/in-process-ready-snapshot.v1.json")
        probe = load_json(attempt004_root / "unity-output/unity-identity-probe-receipt.v1.json")

        add_check(
            checks,
            "historical-process-launch-receipt-valid",
            launch.get("schema") == "gate14re-me-unity-executable-identity-probe-launch-receipt-v1"
            and launch.get("studyId") == STUDY_ID
            and launch.get("authorizationId") == ATTEMPT004_AUTHORIZATION_ID
            and launch.get("status")
            == "ONE_ISOLATED_ALGORITHM_FREE_UNITY_IDENTITY_RULE_REPAIR_PROBE_LAUNCHED"
            and int(launch.get("invocationOrdinal", -1)) == 1
            and int(launch.get("processId", -1)) > 0
            and normalize_path(launch.get("executablePath", "")) == normalize_path(EXPECTED_UNITY_PATH)
            and launch.get("executeMethod") == EXPECTED_EXECUTE_METHOD
            and launch.get("schemaCompatibilitySelfCheckInvoked") is False
            and launch.get("retryAuthorized") is False,
            {
                "processId": launch.get("processId"),
                "creationTimeUtc": launch.get("creationTimeUtc"),
                "executeMethod": launch.get("executeMethod"),
            },
        )

        add_check(
            checks,
            "ready-and-probe-receipt-headers-valid",
            ready.get("schema") == "gate14re-me-unity-executable-identity-ready-snapshot-v2"
            and ready.get("studyId") == STUDY_ID
            and ready.get("authorizationId") == ATTEMPT004_AUTHORIZATION_ID
            and ready.get("status") == "IN_PROCESS_IDENTITY_SNAPSHOT_READY"
            and ready.get("schemaCompatibilitySelfCheckInvoked") is False
            and ready.get("algorithmCodeLoadedByAuditProject") is False
            and probe.get("schema") == "gate14re-me-unity-executable-identity-probe-receipt-v2"
            and probe.get("studyId") == STUDY_ID
            and probe.get("authorizationId") == ATTEMPT004_AUTHORIZATION_ID
            and probe.get("status")
            == "PASS_ALGORITHM_FREE_UNITY_IDENTITY_PROBE_EXTERNAL_ADJUDICATION_PENDING"
            and probe.get("passed") is True
            and probe.get("terminal") is True
            and probe.get("authorizationHeaderPassed") is True
            and probe.get("freezeManifestHeaderPassed") is True,
            {
                "readyStatus": ready.get("status"),
                "probeStatus": probe.get("status"),
                "passed": probe.get("passed"),
                "terminal": probe.get("terminal"),
            },
        )

        ready_process = ready.get("process", {})
        probe_process = probe.get("process", {})
        pid = int(launch.get("processId", -1))
        process_start_delta_ms = abs(
            (parse_utc(ready_process.get("processStartTimeUtc", "1970-01-01T00:00:00Z"))
             - parse_utc(launch.get("creationTimeUtc", "1970-01-01T00:00:00Z"))).total_seconds()
            * 1000.0
        )
        all_paths = [
            launch.get("executablePath", ""),
            ready_process.get("editorApplicationPath", ""),
            ready_process.get("processMainModulePath", ""),
            ready_process.get("queryFullProcessImageNamePath", ""),
            probe_process.get("editorApplicationPath", ""),
            probe_process.get("processMainModulePath", ""),
            probe_process.get("queryFullProcessImageNamePath", ""),
        ]
        paths_agree = all(normalize_path(value) == normalize_path(EXPECTED_UNITY_PATH) for value in all_paths)
        process_identity = (
            int(ready_process.get("processId", -2)) == pid
            and int(probe_process.get("processId", -3)) == pid
            and ready_process.get("processStartTimeUtc") == probe_process.get("processStartTimeUtc")
            and process_start_delta_ms <= 1000.0
            and ready_process.get("allExecutablePathsEqual") is True
            and probe_process.get("allExecutablePathsEqual") is True
            and paths_agree
        )
        add_check(
            checks,
            "historical-pid-start-time-and-path-composite-identity",
            process_identity,
            {
                "processId": pid,
                "processStartDeltaMilliseconds": process_start_delta_ms,
                "paths": all_paths,
            },
        )

        ready_args = [str(value) for value in ready_process.get("environmentCommandLineArgs", [])]
        probe_args = [str(value) for value in probe_process.get("environmentCommandLineArgs", [])]
        command_line = str(launch.get("commandLine", ""))
        expected_project = str((attempt004_root / "isolated-unity-audit-project").resolve())
        expected_output = str((attempt004_root / "unity-output").resolve())
        command_line_identity = (
            ready_args == probe_args
            and len(ready_args) > 0
            and normalize_path(ready_args[0]) == normalize_path(EXPECTED_UNITY_PATH)
            and pair_value(ready_args, "-executeMethod") == EXPECTED_EXECUTE_METHOD
            and normalize_path(pair_value(ready_args, "-projectPath") or "")
            == normalize_path(expected_project)
            and normalize_path(pair_value(ready_args, "--g14me-identity-output-dir") or "")
            == normalize_path(expected_output)
            and pair_value(ready_args, "--g14me-authorized-unity-sha256")
            == EXPECTED_UNITY_SHA256
            and EXPECTED_EXECUTE_METHOD in command_line
            and expected_project.casefold() in command_line.casefold()
            and "Gate14ReMEInputSchemaCompatibilitySelfCheckV1" not in command_line
            and "Gate14ReMELoadQualificationRunner" not in command_line
            and "Gate14ReMEQualificationPlanner" not in command_line
            and "Gate14ReMEReferenceOracle" not in command_line
        )
        add_check(
            checks,
            "historical-exact-command-line-identity",
            command_line_identity,
            {
                "argumentCount": len(ready_args),
                "executeMethod": pair_value(ready_args, "-executeMethod"),
                "projectPath": pair_value(ready_args, "-projectPath"),
            },
        )

        ready_initial = ready.get("initialExecutableFingerprint", {})
        probe_initial = probe.get("initialExecutableFingerprint", {})
        probe_after = probe.get("afterHoldExecutableFingerprint", {})
        ready_projection = structure_projection(ready_initial)
        probe_initial_projection = structure_projection(probe_initial)
        probe_after_projection = structure_projection(probe_after)
        in_process_matches_external_id = (
            ready_projection["fileIndexHex"] == str(file_low64[1]).lower()
            and probe_initial_projection["fileIndexHex"] == str(file_low64[1]).lower()
            and probe_after_projection["fileIndexHex"] == str(file_low64[1]).lower()
        )
        in_process_structural_stable = (
            ready_projection == probe_initial_projection == probe_after_projection
            and ready_projection["path"] == normalize_path(EXPECTED_UNITY_PATH)
            and ready_projection["fileIdentitySucceeded"]
            and ready_projection["peIdentitySucceeded"]
            and in_process_matches_external_id
            and probe.get("inProcessStructuralIdentityStableAcrossHold") is True
        )
        add_check(
            checks,
            "in-process-structural-identity-stable-and-matches-external-file-id",
            in_process_structural_stable,
            {
                "reportedStable": probe.get("inProcessStructuralIdentityStableAcrossHold"),
                "fileIndexHex": ready_projection["fileIndexHex"],
                "externalFileIndexLow64Hex": file_low64[1],
            },
        )

        known_ready = ready.get("sha256KnownAnswers", {})
        known_probe = probe.get("sha256KnownAnswers", {})
        known_answer_passed = (
            known_ready.get("allPassed") is True
            and known_probe.get("allPassed") is True
            and known_ready == known_probe
            and known_probe.get("abcExpectedSha256")
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            and known_probe.get("abcActualSha256") == known_probe.get("abcExpectedSha256")
            and known_probe.get("zeroStreamActualSha256")
            == known_probe.get("zeroStreamExpectedSha256")
        )
        add_check(
            checks,
            "sha256-known-answers-passed",
            known_answer_passed,
            known_probe,
        )

        prohibited_probe_activity_absent = (
            probe.get("schemaCompatibilitySelfCheckInvoked") is False
            and probe.get("plannerInvoked") is False
            and probe.get("algorithmLaneExecuted") is False
            and probe.get("measuredRootCreated") is False
            and probe.get("inProcessFileReadHashesAuthoritative") is False
        )
        add_check(
            checks,
            "probe-reports-no-prohibited-activity-and-byte-reads-nonauthoritative",
            prohibited_probe_activity_absent,
            {
                "schemaCompatibilitySelfCheckInvoked": probe.get("schemaCompatibilitySelfCheckInvoked"),
                "plannerInvoked": probe.get("plannerInvoked"),
                "algorithmLaneExecuted": probe.get("algorithmLaneExecuted"),
                "measuredRootCreated": probe.get("measuredRootCreated"),
                "inProcessFileReadHashesAuthoritative": probe.get("inProcessFileReadHashesAuthoritative"),
            },
        )

        probe_bindings_valid = True
        probe_binding_results: list[dict[str, Any]] = []
        for binding in probe.get("bindings", []):
            binding_path = Path(str(binding.get("relativePath", ""))).resolve()
            matched = (
                binding_path.is_file()
                and binding_path.stat().st_size == int(binding.get("lengthBytes", -1))
                and sha256_file(binding_path) == str(binding.get("expectedSha256", "")).lower()
                and binding.get("actualSha256") == binding.get("expectedSha256")
                and binding.get("matched") is True
            )
            probe_bindings_valid = probe_bindings_valid and matched
            probe_binding_results.append(
                {
                    "role": binding.get("role"),
                    "path": str(binding_path).replace("\\", "/"),
                    "matched": matched,
                }
            )
        add_check(
            checks,
            "unity-probe-source-and-parent-bindings-still-match",
            len(probe_binding_results) == 11 and probe_bindings_valid,
            {"bindingCount": len(probe_binding_results), "bindings": probe_binding_results},
        )

        orchestrator_lines = orchestrator_v4_path.read_text(encoding="utf-8-sig").splitlines()
        control_flow_proof = (
            len(orchestrator_lines) >= 597
            and "Unity identity probe exited nonzero" in orchestrator_lines[584]
            and "Unity identity-probe receipt is not a terminal internal pass" in orchestrator_lines[587]
            and "Get-ExternalFingerprint" in orchestrator_lines[593]
            and "external-post-exit-fingerprint.v1.json" in orchestrator_lines[594]
            and "Remove-IsolatedUnityTransientCaches" in orchestrator_lines[596]
            and "Remove-IsolatedUnityTransientCaches" in str(failure.get("stackTrace", ""))
            and "line 382" in str(failure.get("stackTrace", ""))
            and "line 597" in str(failure.get("stackTrace", ""))
            and failure.get("exceptionType")
            == "System.Management.Automation.PropertyNotFoundException"
            and "property 'Sum' cannot be found" in str(failure.get("exactFailure", ""))
            and parse_utc(probe["completedAtUtc"]) <= parse_utc(post["capturedAtUtc"])
            <= parse_utc(failure["failedAtUtc"])
        )
        add_check(
            checks,
            "normal-exit-and-post-exit-persistence-proven-before-cleanup-failure",
            control_flow_proof,
            {
                "probeCompletedAtUtc": probe.get("completedAtUtc"),
                "postExitCapturedAtUtc": post.get("capturedAtUtc"),
                "attempt004FailedAtUtc": failure.get("failedAtUtc"),
                "exceptionType": failure.get("exceptionType"),
            },
        )

        diagnostic = {
            "initialOpenReadSha256": optional_hash(ready_initial, "sha256-create-file-open-read"),
            "afterHoldOpenReadSha256": optional_hash(probe_after, "sha256-create-file-open-read"),
            "initialSharedFileStreamSha256": optional_hash(ready_initial, "sha256-create-shared-filestream"),
            "afterHoldSharedFileStreamSha256": optional_hash(probe_after, "sha256-create-shared-filestream"),
            "initialFileReadAllBytesSha256": optional_hash(ready_initial, "sha256-create-read-all-bytes"),
            "afterHoldFileReadAllBytesSha256": optional_hash(probe_after, "sha256-create-read-all-bytes"),
            "fullFingerprintStableAcrossHold": probe.get("inProcessFingerprintStableAcrossHold"),
            "fileReadAllBytesStableAcrossHold": probe.get("readAllBytesHashStableAcrossHoldDiagnostic"),
            "authoritative": False,
            "effectOnAdjudication": "NONE_DIAGNOSTIC_ONLY",
        }
        add_check(
            checks,
            "in-process-byte-read-observations-retained-as-diagnostic-only",
            probe.get("inProcessFileReadHashesAuthoritative") is False,
            diagnostic,
            authoritative=False,
        )

        prefreeze_unity_pids = unity_process_ids()
        add_check(
            checks,
            "no-unity-process-before-attempt005-terminal-freeze",
            len(prefreeze_unity_pids) == 0,
            {"unityProcessIds": prefreeze_unity_pids},
        )

        attempt004_inventory_after, attempt004_digest_after = inventory(attempt004_root)
        add_check(
            checks,
            "attempt004-evidence-unchanged-during-offline-adjudication",
            attempt004_inventory_after == attempt004_inventory_before
            and attempt004_digest_after == attempt004_digest_before,
            {
                "beforeFileCount": len(attempt004_inventory_before),
                "afterFileCount": len(attempt004_inventory_after),
                "beforeDigestSha256": attempt004_digest_before,
                "afterDigestSha256": attempt004_digest_after,
            },
        )

        if args.preflight_only:
            preflight_passed = all_true(checks)
            print(
                json.dumps(
                    {
                        "schema": "gate14re-me-unity-identity-offline-adjudication-preflight-v1",
                        "studyId": STUDY_ID,
                        "authorizationId": AUTHORIZATION_ID,
                        "status": "PASS_READ_ONLY_PREFLIGHT"
                        if preflight_passed
                        else "FAILED_READ_ONLY_PREFLIGHT",
                        "passed": preflight_passed,
                        "writesPerformed": False,
                        "unityInvocationCount": 0,
                        "checks": checks,
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
            )
            return 0 if preflight_passed else 2

        if not all_true(checks):
            failed_ids = [
                check["checkId"]
                for check in checks
                if check.get("authoritative") is True and check.get("passed") is not True
            ]
            raise AdjudicationError(
                "Authoritative frozen-evidence checks failed: " + ", ".join(failed_ids)
            )

        stage_root.mkdir(parents=False, exist_ok=False)
        created_stage = True
        completed_at = utc_now()
        audit = {
            "schema": "gate14re-me-unity-identity-offline-evidence-adjudication-v1",
            "studyId": STUDY_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "PASS_OFFLINE_FROZEN_EVIDENCE_ADJUDICATION",
            "completedAtUtc": completed_at,
            "passed": True,
            "terminal": True,
            "attempt004Outcome": {
                "retained": True,
                "status": failure.get("status"),
                "classification": failure.get("classification"),
                "reclassified": False,
                "modified": False,
            },
            "attempt005Execution": {
                "mode": "OFFLINE_EVIDENCE_ONLY",
                "unityInvocationCount": 0,
                "processLaunchPrimitivePresent": False,
                "deleteOrCleanupPrimitivePresent": False,
                "retryCount": 0,
                "criteriaRelaxed": False,
            },
            "classification": "EXTERNAL_COMPOSITE_IDENTITY_AUTHORITATIVE_IN_PROCESS_READS_DIAGNOSTIC",
            "authoritativeChecks": checks,
            "diagnosticOnlyInProcessByteReads": diagnostic,
            "retainedAttempt004Inventory": {
                "rootRelativePath": ATTEMPT004_REL,
                "fileCount": len(attempt004_inventory_after),
                "digestSha256": attempt004_digest_after,
                "allReadOnly": all(row["readOnly"] for row in attempt004_inventory_after),
            },
            "scientificBoundary": {
                "schemaCompatibilitySelfCheckInvocations": 0,
                "scheduleRowsGenerated": 0,
                "qualificationInputsGenerated": 0,
                "anonymousIdentityMappingsGenerated": 0,
                "measuredRootCreated": False,
                "plannerInvocations": 0,
                "algorithmLaneExecutions": 0,
                "formalCollectionPerformed": False,
                "formalAnalysisPerformed": False,
                "algorithmRankingPerformed": False,
                "winnerAdjudicationPerformed": False,
            },
        }
        audit_path = stage_root / "offline-evidence-adjudication.v1.json"
        write_json_exclusive(audit_path, audit)

        rule = {
            "schema": "gate14re-me-unity-executable-identity-verification-rule-v1",
            "studyId": STUDY_ID,
            "ruleId": "gate14re-me-unity-2022.3.30f1c1-external-three-phase-composite-process-identity-v3",
            "status": "FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION",
            "frozenAtUtc": utc_now(),
            "authorizationId": AUTHORIZATION_ID,
            "sourceAttempt": {
                "authorizationId": ATTEMPT004_AUTHORIZATION_ID,
                "outcomeRetained": "FAILED_CLOSED_NOT_ADJUDICATED",
                "reclassified": False,
                "evidenceInventoryDigestSha256": attempt004_digest_after,
            },
            "applicability": {
                "host": os.environ.get("COMPUTERNAME"),
                "unityVersion": "2022.3.30f1c1",
                "unityExecutablePath": EXPECTED_UNITY_PATH,
                "unityExecutableExpectedSha256": EXPECTED_UNITY_SHA256,
                "ntfsFileIdHex": file_ids[0],
                "ntfsFileIndexLow64Hex": file_low64[0],
                "fileLengthBytes": pre.get("lengthBytes"),
                "creationTimeUtc": pre.get("creationTimeUtc"),
                "lastWriteTimeUtc": pre.get("lastWriteTimeUtc"),
                "signerSubject": signer_values[0][1],
                "signerThumbprint": signer_values[0][2],
            },
            "authoritativeIdentitySources": [
                "two mutually agreeing external full-file SHA-256 implementations at prelaunch, live-concurrent and post-exit phases",
                "stable external 64 KiB chunk sets, normalized regular-file path, NTFS file identity, PE identity, Authenticode signer, length and timestamps",
                "historical live PID, creation time, executable path, exact command line, execute method and isolated project",
                "in-process EditorApplication.applicationPath, Process.MainModule and QueryFullProcessImageName path agreement plus stable structural identity",
                "terminal algorithm-free Unity probe receipt, SHA-256 known answers, natural exit-code-zero control-flow gate and persisted post-exit fingerprint",
            ],
            "nonAuthoritativeIdentitySources": [
                "in-process File.OpenRead SHA-256",
                "in-process shared FileStream SHA-256",
                "in-process File.ReadAllBytes SHA-256 and its cross-hold stability",
                "in-process chunk digests and their agreement with external reads",
                "process name without PID, creation time, executable path and exact command line",
            ],
            "requirements": {
                "externalThreePhaseExpectedSha256AndIndependentMethodAgreement": True,
                "external64KiBChunksPathFileIdPeSignerAndMetadataStable": True,
                "pidCreationTimePathCommandLineAndExecuteMethodBound": True,
                "inProcessPathSourcesAndStructuralIdentityStable": True,
                "knownAnswersPassed": True,
                "normalExitAndPostExitReconfirmationRequired": True,
                "inProcessSelfHashesRequiredForAuthorization": False,
                "fileReadAllBytesRole": "DIAGNOSTIC_ONLY",
                "anyAuthoritativeMismatchDisposition": "FAIL_CLOSED_NO_ADOPTION",
            },
            "evidenceClassification": audit["classification"],
            "explanationBoundary": (
                "This rule establishes launch identity only. It does not reclassify attempt-004, "
                "explain process-local byte-read differences, certify Unity correctness, qualify D3, "
                "or authorize schema compatibility, qualification, an algorithm lane, collection, "
                "analysis, ranking or winner adjudication."
            ),
            "evidenceBindings": {
                "offlineAdjudication": {
                    "relativePath": f"{STAGE_REL}/offline-evidence-adjudication.v1.json",
                    "sha256": sha256_file(audit_path),
                },
                "attempt004FailureReceipt": {
                    "relativePath": f"{ATTEMPT004_REL}/failure-receipt.v1.json",
                    "sha256": EXPECTED_ATTEMPT004_FAILURE_SHA256,
                },
                "attempt004StatusV16": {
                    "relativePath": STATUS_V16_REL,
                    "sha256": EXPECTED_STATUS_V16_SHA256,
                },
                "attempt004ExternalPrelaunchFingerprint": {
                    "relativePath": f"{ATTEMPT004_REL}/external-prelaunch-fingerprint.v1.json",
                    "sha256": sha256_file(attempt004_root / "external-prelaunch-fingerprint.v1.json"),
                },
                "attempt004ExternalConcurrentFingerprint": {
                    "relativePath": f"{ATTEMPT004_REL}/external-concurrent-fingerprint.v1.json",
                    "sha256": sha256_file(attempt004_root / "external-concurrent-fingerprint.v1.json"),
                },
                "attempt004ExternalPostExitFingerprint": {
                    "relativePath": f"{ATTEMPT004_REL}/external-post-exit-fingerprint.v1.json",
                    "sha256": sha256_file(attempt004_root / "external-post-exit-fingerprint.v1.json"),
                },
                "attempt004ProcessLaunchReceipt": {
                    "relativePath": f"{ATTEMPT004_REL}/process-launch-receipt.v1.json",
                    "sha256": sha256_file(attempt004_root / "process-launch-receipt.v1.json"),
                },
                "attempt004ReadySnapshot": {
                    "relativePath": f"{ATTEMPT004_REL}/unity-output/in-process-ready-snapshot.v1.json",
                    "sha256": sha256_file(attempt004_root / "unity-output/in-process-ready-snapshot.v1.json"),
                },
                "attempt004UnityProbeReceipt": {
                    "relativePath": f"{ATTEMPT004_REL}/unity-output/unity-identity-probe-receipt.v1.json",
                    "sha256": sha256_file(attempt004_root / "unity-output/unity-identity-probe-receipt.v1.json"),
                },
            },
        }
        rule_path = stage_root / "trusted-launch-identity-rule.v1.json"
        write_json_exclusive(rule_path, rule)

        terminal = {
            "schema": "gate14re-me-unity-identity-offline-adjudication-terminal-receipt-v1",
            "studyId": STUDY_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "PASS_TRUSTED_LAUNCH_IDENTITY_RULE_FROZEN_BY_OFFLINE_ADJUDICATION",
            "completedAtUtc": utc_now(),
            "passed": True,
            "terminal": True,
            "attempt005UnityInvocationCount": 0,
            "attempt004OutcomeRetained": "FAILED_CLOSED_NOT_ADJUDICATED",
            "classification": audit["classification"],
            "trustedIdentityRule": {
                "relativePath": f"{STAGE_REL}/trusted-launch-identity-rule.v1.json",
                "sha256": sha256_file(rule_path),
            },
            "offlineAdjudication": {
                "relativePath": f"{STAGE_REL}/offline-evidence-adjudication.v1.json",
                "sha256": sha256_file(audit_path),
            },
            "attempt004EvidenceUnchanged": True,
            "automaticRetryCount": 0,
            "criteriaRelaxed": False,
            "scientificBoundary": audit["scientificBoundary"],
            "nextAuthorizationRequired": (
                "A new, separate authorization is required before any schema-compatibility self-check, "
                "qualification planning, schedule/input/identity-map generation, measured-root creation, "
                "planner, algorithm lane, collection, analysis, ranking or winner adjudication."
            ),
        }
        terminal_path = stage_root / "terminal-receipt.v1.json"
        write_json_exclusive(terminal_path, terminal)

        status_v17 = {
            "schema": "gate14re-me-status-v17",
            "studyId": STUDY_ID,
            "status": "UNITY_EXECUTABLE_TRUSTED_LAUNCH_IDENTITY_RULE_FROZEN_OFFLINE_ADJUDICATION",
            "version": 17,
            "updatedAtUtc": utc_now(),
            "previousVersionedStatus": {
                "relativePath": STATUS_V16_REL,
                "lengthBytes": status_v16_path.stat().st_size,
                "sha256": EXPECTED_STATUS_V16_SHA256,
                "retained": True,
                "status": status_v16.get("status"),
            },
            "attempt004": {
                "authorizationId": ATTEMPT004_AUTHORIZATION_ID,
                "status": "FAILED_CLOSED_UNITY_EXECUTABLE_IDENTITY_RULE_REPAIR",
                "classification": "NOT_ADJUDICATED",
                "retainedUnchanged": True,
                "reclassified": False,
                "evidenceFileCount": len(attempt004_inventory_after),
                "evidenceInventoryDigestSha256": attempt004_digest_after,
            },
            "offlineEvidenceAdjudication": {
                "authorizationId": AUTHORIZATION_ID,
                "status": terminal["status"],
                "classification": audit["classification"],
                "unityInvocationCount": 0,
                "trustedRuleRelativePath": f"{STAGE_REL}/trusted-launch-identity-rule.v1.json",
                "trustedRuleSha256": sha256_file(rule_path),
                "terminalReceiptRelativePath": f"{STAGE_REL}/terminal-receipt.v1.json",
                "terminalReceiptSha256": sha256_file(terminal_path),
            },
            "scientificBoundary": audit["scientificBoundary"],
            "authorizationState": {
                "offlineIdentityEvidenceAdjudicationAuthorizationConsumed": True,
                "trustedLaunchIdentityRuleFrozen": True,
                "schemaCompatibilitySelfCheckAuthorized": False,
                "qualificationPlanningAuthorized": False,
                "scheduleGenerationAuthorized": False,
                "inputGenerationAuthorized": False,
                "anonymousIdentityMapGenerationAuthorized": False,
                "measuredRootCreationAuthorized": False,
                "plannerAuthorized": False,
                "algorithmLaneExecutionAuthorized": False,
                "formalCollectionAuthorized": False,
                "formalAnalysisAuthorized": False,
                "rankingAuthorized": False,
                "winnerAdjudicationAuthorized": False,
            },
            "nextRequiredAction": (
                "Separately authorize the next minimum stage. The frozen trusted launch-identity rule "
                "may be consumed by a future expressly authorized Unity stage, but attempt-005 itself "
                "authorizes no Unity launch or scientific qualification activity."
            ),
        }
        write_json_exclusive(status_v17_path, status_v17)

        stage_files = []
        for path in sorted((p for p in stage_root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(project_root).as_posix()):
            stage_files.append(
                {
                    "relativePath": path.relative_to(project_root).as_posix(),
                    "lengthBytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
        evidence_manifest = {
            "schema": "gate14re-me-unity-identity-offline-adjudication-evidence-freeze-manifest-v1",
            "studyId": STUDY_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "FROZEN_TERMINAL_OFFLINE_IDENTITY_ADJUDICATION_EVIDENCE",
            "frozenAtUtc": utc_now(),
            "sourceFreezeManifest": {
                "relativePath": source_manifest_path.relative_to(project_root).as_posix(),
                "sha256": args.source_freeze_manifest_sha256.lower(),
            },
            "statusV17": {
                "relativePath": STATUS_V17_REL,
                "lengthBytes": status_v17_path.stat().st_size,
                "sha256": sha256_file(status_v17_path),
            },
            "attempt004RetainedEvidence": {
                "rootRelativePath": ATTEMPT004_REL,
                "fileCount": len(attempt004_inventory_after),
                "inventoryDigestSha256": attempt004_digest_after,
                "unchanged": True,
            },
            "evidenceFiles": stage_files,
        }
        evidence_manifest_path = stage_root / "source-and-evidence-freeze-manifest.v1.json"
        write_json_exclusive(evidence_manifest_path, evidence_manifest)

        for path in [
            project_path(
                project_root,
                "Research/Gate14Re-ME/Gate14Re_ME_Unity_Executable_Identity_Rule_Offline_Evidence_Adjudication_Attempt_005_Authorization.v1.json",
            ),
            project_path(
                project_root,
                "Research/Gate14Re-ME/Gate14Re_ME_Unity_Executable_Identity_Rule_Offline_Evidence_Adjudication_Attempt_005_Plan.v1.md",
            ),
            source_path,
            source_manifest_path,
            status_v17_path,
            *[p for p in stage_root.rglob("*") if p.is_file()],
        ]:
            set_read_only(path)

        print(json.dumps(terminal, ensure_ascii=False, separators=(",", ":")))
        return 0
    except Exception as exc:
        failure_time = utc_now()
        if args.preflight_only:
            print(
                json.dumps(
                    {
                        "schema": "gate14re-me-unity-identity-offline-adjudication-preflight-v1",
                        "studyId": STUDY_ID,
                        "authorizationId": AUTHORIZATION_ID,
                        "status": "ERROR_READ_ONLY_PREFLIGHT",
                        "passed": False,
                        "writesPerformed": False,
                        "unityInvocationCount": 0,
                        "exceptionType": type(exc).__name__,
                        "exactFailure": str(exc),
                        "checks": checks,
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
                file=sys.stderr,
            )
            return 1
        if not created_stage and not stage_root.exists():
            stage_root.mkdir(parents=False, exist_ok=False)
            created_stage = True
        failure_receipt = {
            "schema": "gate14re-me-unity-identity-offline-adjudication-failure-receipt-v1",
            "studyId": STUDY_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "FAILED_CLOSED_OFFLINE_IDENTITY_EVIDENCE_ADJUDICATION",
            "failedAtUtc": failure_time,
            "exceptionType": type(exc).__name__,
            "exactFailure": str(exc),
            "stackTrace": traceback.format_exc(),
            "attempt005UnityInvocationCount": 0,
            "attempt004OutcomeRetained": "FAILED_CLOSED_NOT_ADJUDICATED",
            "attempt004EvidenceDigestBeforeFailure": attempt004_digest_before or None,
            "authoritativeChecksCompleted": checks,
            "automaticRetryDisposition": (
                "A transparent versioned tool-repair retry is authorized only if this is an attempt-005 "
                "tooling defect or transient read failure. A deterministic frozen-evidence mismatch "
                "must remain failed closed and cannot be relaxed."
            ),
            "criteriaRelaxed": False,
        }
        failure_path_out = stage_root / "failure-receipt.v1.json"
        if not failure_path_out.exists():
            write_json_exclusive(failure_path_out, failure_receipt)
        if not status_v17_path.exists():
            write_json_exclusive(
                status_v17_path,
                {
                    "schema": "gate14re-me-status-v17",
                    "studyId": STUDY_ID,
                    "status": "UNITY_EXECUTABLE_IDENTITY_OFFLINE_EVIDENCE_ADJUDICATION_FAILED_CLOSED",
                    "version": 17,
                    "updatedAtUtc": failure_time,
                    "previousVersionedStatus": {
                        "relativePath": STATUS_V16_REL,
                        "sha256": sha256_file(project_path(project_root, STATUS_V16_REL))
                        if project_path(project_root, STATUS_V16_REL).is_file()
                        else None,
                        "retained": True,
                    },
                    "attempt004Reclassified": False,
                    "attempt005UnityInvocationCount": 0,
                    "failureReceiptRelativePath": f"{STAGE_REL}/failure-receipt.v1.json",
                    "failureReceiptSha256": sha256_file(failure_path_out),
                    "nextRequiredAction": (
                        "Apply the user's bounded retry rule only for a transparent adjudicator/tool read "
                        "defect. Do not alter frozen evidence or weaken an authoritative identity criterion."
                    ),
                },
            )
        for path in [p for p in stage_root.rglob("*") if p.is_file()]:
            set_read_only(path)
        set_read_only(status_v17_path)
        print(f"Gate14Re-ME attempt-005 failed closed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
