#!/usr/bin/env python3
"""Read-only Gate14Re-ME qualification execution readiness recheck, attempt-003.

This audit is deliberately non-executing.  It may read and hash frozen assets,
parse source files, inspect process/host metadata, and write evidence only inside
its own attempt directory plus the next versioned Gate14Re-ME status on PASS.
It must never start Unity, create a measured/delivery root, run a planner or an
algorithm lane, or compute a cross-algorithm statistic, rank, or winner.
"""

from __future__ import annotations

import ast
import collections
import datetime as dt
import hashlib
import json
import math
import os
import pathlib
import stat
import subprocess
import sys
from typing import Any, Iterable, Mapping, Sequence


PROJECT_ROOT = pathlib.Path(r"H:\DDM_Final_Project").resolve()
ATTEMPT_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-readiness-recheck-attempt-003"
)
ATTEMPT_ROOT = (PROJECT_ROOT / ATTEMPT_REL).resolve()
AUTHORIZATION_ID = "gate14re-me-qualification-execution-readiness-recheck-attempt-003"
ATTEMPT_ID = "qualification-execution-readiness-recheck-attempt-003"
STATUS_29_REL = pathlib.PurePosixPath("Research/Gate14Re-ME/Gate14Re_ME_Status.v29.json")

USER_AUTHORIZATION_TEXT = (
    "单独授权 Gate14Re‑ME qualification execution readiness recheck attempt‑003："
    "完整保留 qualification execution readiness freeze attempt‑002、terminal-chain corrigendum attempt‑001 "
    "与 attempt‑002 的全部状态和证据，不删除、不修改、不改判；仅允许以只读、无 Unity 的方式，依据 Status v28 "
    "核对 output schema v3、structural‑v3.1、delivery‑v2.2、supervisor‑v3、execution contract v3.1、"
    "implementation manifest v3.1、RunnerV2、compiled assemblies、input schema v2、planning schema binding v2、"
    "planning assets、162 行 Williams schedule、sealed identity、D2、D3‑v3.1、D4、clock、typed‑Parquet runtime、"
    "trusted Unity identity rule、attempt‑007 timestamp comparator、运行预算、零 replacement fail‑stop、预期 "
    "1,147 个串行 fresh Unity processes，以及完整逐条 structural/delivery 终局。只有所有路径、哈希、cardinality、"
    "receipt 版本、进程账本、进程身份和最终 ordinal 检查全部通过时，才允许冻结独立 terminal readiness PASS receipt。"
    "不得启动 Unity，不得创建 qualification measured root 或正式 delivery root，不得运行 planner、算法 lane、资格或"
    "正式采集、正式分析、排名或赢家裁决；失败时保留全部证据并 fail closed。"
)

PINNED_PYTHON = pathlib.Path(
    r"C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)
PINNED_POWERSHELL = pathlib.Path(
    r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
)

RESERVED_ROOTS = [
    "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001",
    "Research/Exports/Gate14Re-ME/load-qualification/attempt-001",
    "Research/FormalRuns/Gate14Re-ME",
]

RETAINED_ATTEMPTS = {
    "readinessAttempt002": {
        "relativePath": "Research/Verification/Gate14Re-ME/qualification-execution-readiness-freeze-attempt-002",
        "receipt": "failure-receipt.v1.json",
        "receiptSha256": "ac58c5110fcf500e520ba8dcac7406c05601f12e99595cf1a4a3cb9c496a3e9b",
        "status": "FAILED_CLOSED_QUALIFICATION_EXECUTION_READINESS_TERMINAL_CHAIN_INCOMPLETE",
    },
    "terminalCorrigendumAttempt001": {
        "relativePath": "Research/Verification/Gate14Re-ME/qualification-execution-terminal-chain-corrigendum-attempt-001",
        "receipt": "failure-receipt.v1.json",
        "receiptSha256": "b195c99e01bc20900762b3752ff6172a64fac4bb914609bf1ba83d832ed99340",
        "status": "FAILED_CLOSED_TERMINAL_CHAIN_CORRIGENDUM",
    },
    "terminalCorrigendumAttempt002": {
        "relativePath": "Research/Verification/Gate14Re-ME/qualification-execution-terminal-chain-corrigendum-attempt-002",
        "receipt": "terminal-pass-receipt.v1.json",
        "receiptSha256": "bf7e157f6f25ea19d6cd898745476cd6c88569fbc99c1d614abd76945ca33cad",
        "status": "PASS_TERMINAL_CHAIN_CORRIGENDUM_OFFLINE_ONLY",
    },
}

EXPECTED_HASHES = {
    "statusV28": ("Research/Gate14Re-ME/Gate14Re_ME_Status.v28.json", "e8bc1bdca534d9f6c90ba0db689f17c3a165a9c64fb4318517e44551ff159640"),
    "outputSchemaV3": ("Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json", "e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c"),
    "outputSchemaV2": ("Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json", "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb"),
    "structuralV31": ("Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py", "85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e"),
    "deliveryV22": ("Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2_2.py", "197b14309670fc38e26b421c458fbd4fc05abe8ba61f7f715497bbcffb19eb98"),
    "supervisorV3": ("Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3.ps1", "e672d2bc3e584192d1f9850ed2bb76538ba11fead80e1ce94670febd9fb45035"),
    "executionContractV31": ("Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_1.json", "f1fa4b7c10ebdbfacc6a4f82a68d4ae1ca0a94fa18af929d6a74eb0ad39cf801"),
    "implementationManifestV31": ("Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_1.json", "af0b370258c2bce8b51cd6215c5c790dda6727a3a3eb581fa21713950d53bdf6"),
    "runnerV2": ("Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs", "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73"),
    "editorAssembly": ("Library/ScriptAssemblies/Assembly-CSharp-Editor.dll", "abef0c3232d02818e60a5603600fbc8899dba2fbe383e73b255a04eab01b5e88"),
    "runtimeAssembly": ("Library/ScriptAssemblies/Assembly-CSharp.dll", "c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1"),
    "inputSchemaV2": ("Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json", "1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117"),
    "planningSchemaBindingV2": ("Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json", "abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7"),
    "instrumentContractV3": ("Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json", "c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312"),
    "d3V31": ("Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json", "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"),
    "resourceBudget": ("Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json", "bef0f0c143f325eb7b3ad9e5401cc89bc7d6ff3938287a9b049e985aac04e887"),
    "scheduleSchema": ("Research/Gate14Re-ME/Execution/v1/load-qualification-schedule-schema.v1.json", "8a96a5a53d22617ef90134ac1a57e3b7115e5ea7ce03a6739c632fd52119f8a5"),
    "fairnessBinding": ("Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json", "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71"),
    "typedParquetRuntime": ("Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json", "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e"),
    "completeRawDeliveryContract": ("Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json", "1e3a70d6be62554027ca639b6a3c7d896fd232906d627962d8c296e9e884c8dd"),
    "trustedIdentityRule": ("Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json", "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06"),
    "timestampComparator": ("Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1", "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27"),
    "timestampKnownAnswer": ("Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/known-answer-receipt.v1.json", "ad64fb2bce32f2e6206f6f1f80baa30f273be212075603ee631f61b560cc1b63"),
    "planningAssetsManifest": ("Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json", "7e0cbe77cb8bb8f84642856c6356d318f708e168b52a92e6e348cdf948169aca"),
    "planningTerminal": ("Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/terminal-receipt.v1.json", "7ca501b6c7f40dde2958aac6c9cd37984ff788a55dadf1df494a9e2a0e4f05f3"),
    "schedule": ("Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl", "328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471"),
    "sealedIdentity": ("Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json", "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08"),
    "compileIdentityReceipt": ("Research/Verification/Gate14Re-ME/qualification-execution-binding-supervisor-v2-repair-attempt-002/compile-identity-receipt.v1.json", "07118a3b4be7e9cd0b044d073426d8db24ba116498d548c3bbfa42df2cdf9937"),
    "schemaBridgeValidation": ("Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/validation-receipt.v1.json", "404970e8026f37b1d527b42b127ed657e5bd1a0ac757897903221c80daee174c"),
    "runtimeAttempt001Failure": ("Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/failure-receipt.v1.json", "8a508261f9c779ff3d3e3481d5eaf28ebc9d4c513cb69fdc8d30456b3ad9b49a"),
    "runtimeInstrumentReceipt": ("Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/csharp-instruments/instrument-runtime-receipt.v1.json", "be76050b64107f57b5b1086b3fcd318aa3d964c23f5f8dd9935798ff51f5b231"),
    "terminalAttempt002Pass": ("Research/Verification/Gate14Re-ME/qualification-execution-terminal-chain-corrigendum-attempt-002/terminal-pass-receipt.v1.json", "bf7e157f6f25ea19d6cd898745476cd6c88569fbc99c1d614abd76945ca33cad"),
    "terminalAttempt002Freeze": ("Research/Verification/Gate14Re-ME/qualification-execution-terminal-chain-corrigendum-attempt-002/freeze-manifest.v1.json", "e8e768b0f7a619059eea7259b23714af954b667d6853eda1c704a9d1c3b8be74"),
    "terminalAttempt002StatusAdoption": ("Research/Verification/Gate14Re-ME/qualification-execution-terminal-chain-corrigendum-attempt-002/status-adoption-receipt.v1.json", "8d4c55e899cefe88eeb02371d26117fe65707ceb909fbf2ac6417236c95bfbe8"),
}

EXPECTED_ALGORITHMS = {"A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"}
EXPECTED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
EXPECTED_CARDINALITIES = {
    "coreSuperblocks": 144,
    "stressSuperblocks": 18,
    "totalSuperblocks": 162,
    "algorithmLanesPerSuperblock": 6,
    "freshAlgorithmProcesses": 972,
    "oracleProcesses": 162,
    "emptyBoundaryProcesses": 12,
    "instrumentSelfTestProcesses": 1,
    "expectedTotalUnityProcessesWithoutFailure": 1147,
    "eventGroupsPerLane": 24,
    "eventGroupRows": 23328,
    "d3WindowsPerLane": 25,
    "processResourceRows": 25272,
    "emptyBoundaryRows": 12000,
    "persistentStateMeasurementPointsPerLane": 26,
    "acceptedSuperblockReceipts": 162,
    "processLedgerRows": 1147,
    "processIdentityReceipts": 1147,
    "supervisorFinalProcessOrdinal": 1147,
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def write_json_exclusive(path: pathlib.Path, value: Any) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return path


def project_file(relative: str | pathlib.PurePosixPath) -> pathlib.Path:
    candidate = (PROJECT_ROOT / pathlib.PurePosixPath(str(relative))).resolve()
    try:
        candidate.relative_to(PROJECT_ROOT)
    except ValueError as exc:
        raise RuntimeError(f"path escapes project root: {relative}") from exc
    return candidate


def load_json(relative: str | pathlib.PurePosixPath) -> dict[str, Any]:
    path = project_file(relative)
    with path.open("r", encoding="utf-8-sig") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise RuntimeError(f"expected JSON object: {relative}")
    return value


def read_text(relative: str | pathlib.PurePosixPath) -> str:
    return project_file(relative).read_text(encoding="utf-8-sig")


def read_jsonl(relative: str | pathlib.PurePosixPath) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with project_file(relative).open("r", encoding="utf-8-sig") as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip():
                raise RuntimeError(f"blank JSONL row at {relative}:{line_no}")
            row = json.loads(line)
            if not isinstance(row, dict):
                raise RuntimeError(f"non-object JSONL row at {relative}:{line_no}")
            rows.append(row)
    return rows


def is_read_only(path: pathlib.Path) -> bool:
    attrs = getattr(path.stat(), "st_file_attributes", 0)
    mask = getattr(stat, "FILE_ATTRIBUTE_READONLY", 1)
    return bool(attrs & mask)


def inventory(root: pathlib.Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.as_posix().lower()):
        items.append(
            {
                "relativePath": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "readOnly": is_read_only(path),
            }
        )
    return items


def inventory_digest(items: Iterable[dict[str, Any]]) -> str:
    payload = canonical_json(list(items)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def declared_file_audit(entries: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    mismatches: list[dict[str, Any]] = []
    paths: list[str] = []
    read_only = 0
    for entry in entries:
        relative = str(entry.get("relativePath", ""))
        paths.append(relative)
        path = project_file(relative)
        expected_bytes = entry.get("bytes", entry.get("lengthBytes"))
        expected_hash = entry.get("sha256")
        observed: dict[str, Any] = {"relativePath": relative}
        if not path.is_file():
            observed["missing"] = True
            mismatches.append(observed)
            continue
        observed.update({"bytes": path.stat().st_size, "sha256": sha256_file(path)})
        if is_read_only(path):
            read_only += 1
        if observed["bytes"] != expected_bytes or observed["sha256"] != expected_hash:
            observed.update({"expectedBytes": expected_bytes, "expectedSha256": expected_hash})
            mismatches.append(observed)
    return {
        "entryCount": len(entries),
        "uniquePathCount": len(set(paths)),
        "allPathsUnique": len(paths) == len(set(paths)),
        "readOnlyFileCount": read_only,
        "mismatchCount": len(mismatches),
        "mismatches": mismatches,
    }


def system_probe() -> dict[str, Any]:
    command = r"""
$ErrorActionPreference='Stop'
$unity=@(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | ForEach-Object {
  [pscustomobject]@{processId=$_.ProcessId;creationDate=[string]$_.CreationDate;executablePath=[string]$_.ExecutablePath;commandLine=[string]$_.CommandLine}
})
$os=Get-CimInstance Win32_OperatingSystem
$cs=Get-CimInstance Win32_ComputerSystem
$drive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='H:'"
[pscustomobject]@{
  observedAtUtc=[DateTime]::UtcNow.ToString('o')
  unityProcessCount=$unity.Count
  unityProcesses=$unity
  operatingSystemVersion=[string]$os.Version
  logicalProcessors=[int]$cs.NumberOfLogicalProcessors
  totalVisibleMemoryBytes=[int64]$os.TotalVisibleMemorySize*1024
  driveHFreeBytes=[int64]$drive.FreeSpace
  driveHTotalBytes=[int64]$drive.Size
} | ConvertTo-Json -Depth 8 -Compress
"""
    completed = subprocess.run(
        [str(PINNED_POWERSHELL), "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return json.loads(completed.stdout.strip())


def powershell_parse_errors(path: pathlib.Path) -> list[str]:
    command = (
        "$tokens=$null;$errors=$null;"
        f"[void][System.Management.Automation.Language.Parser]::ParseFile('{str(path).replace("'", "''")}',[ref]$tokens,[ref]$errors);"
        "@($errors|ForEach-Object{$_.Message})|ConvertTo-Json -Compress"
    )
    completed = subprocess.run(
        [str(PINNED_POWERSHELL), "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    raw = completed.stdout.strip()
    if not raw:
        return []
    value = json.loads(raw)
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return [str(item) for item in value]


def root_states() -> dict[str, bool]:
    return {relative: project_file(relative).exists() for relative in RESERVED_ROOTS}


def main() -> int:
    started = utc_now()
    checks: list[dict[str, Any]] = []
    hard_stop_reasons: list[dict[str, str]] = []

    def check(
        check_id: str,
        passed: bool,
        observed: Any,
        expected: Any,
        *,
        domain: str,
        reason: str,
    ) -> None:
        checks.append(
            {
                "checkId": check_id,
                "domain": domain,
                "passed": bool(passed),
                "observed": observed,
                "expected": expected,
            }
        )
        if not passed:
            hard_stop_reasons.append(
                {"blockerId": check_id, "reason": reason, "disposition": "FAIL_CLOSED_NO_QUALIFICATION_EXECUTION"}
            )

    if ATTEMPT_ROOT.resolve() != project_file(ATTEMPT_REL):
        raise RuntimeError("attempt root resolution mismatch")
    if project_file(STATUS_29_REL).exists():
        raise RuntimeError("Status v29 already exists; exclusive attempt would overwrite prior evidence")

    pre_system = system_probe()
    pre_roots = root_states()
    check(
        "BOUNDARY::UNITY_ABSENT_AT_START",
        pre_system.get("unityProcessCount") == 0,
        {"unityProcessCount": pre_system.get("unityProcessCount")},
        {"unityProcessCount": 0},
        domain="authorization-boundary",
        reason="Unity was already active at the start of the no-Unity readiness recheck.",
    )
    check(
        "BOUNDARY::PROHIBITED_ROOTS_ABSENT_AT_START",
        not any(pre_roots.values()),
        pre_roots,
        {relative: False for relative in RESERVED_ROOTS},
        domain="authorization-boundary",
        reason="A qualification measured, delivery, or formal root existed before this authorized readiness recheck.",
    )

    retained_before: dict[str, list[dict[str, Any]]] = {}
    for label, binding in RETAINED_ATTEMPTS.items():
        root = project_file(binding["relativePath"])
        items = inventory(root) if root.is_dir() else []
        retained_before[label] = items
        receipt_path = root / binding["receipt"]
        receipt = json.loads(receipt_path.read_text(encoding="utf-8-sig")) if receipt_path.is_file() else {}
        passed = (
            root.is_dir()
            and bool(items)
            and receipt_path.is_file()
            and sha256_file(receipt_path) == binding["receiptSha256"]
            and receipt.get("status") == binding["status"]
        )
        check(
            f"RETENTION::{label}::STATUS_HASH_AND_READ_ONLY",
            passed,
            {
                "fileCount": len(items),
                "inventoryDigestSha256": inventory_digest(items),
                "receiptSha256": sha256_file(receipt_path) if receipt_path.is_file() else None,
                "receiptStatus": receipt.get("status"),
                "readOnlyFiles": sum(1 for item in items if item["readOnly"]),
            },
            {"receiptSha256": binding["receiptSha256"], "receiptStatus": binding["status"], "nonEmptyEvidenceInventory": True, "preservationVerifiedBy": "before/after full inventory equality"},
            domain="retention",
            reason=f"Retained evidence or its authoritative terminal receipt was missing or drifted: {label}.",
        )

    observed_hashes: dict[str, dict[str, Any]] = {}
    hash_ok = True
    for label, (relative, expected_hash) in EXPECTED_HASHES.items():
        path = project_file(relative)
        actual = sha256_file(path) if path.is_file() else None
        observed_hashes[label] = {
            "relativePath": relative,
            "expectedSha256": expected_hash,
            "actualSha256": actual,
            "exists": path.is_file(),
        }
        hash_ok = hash_ok and actual == expected_hash
    check(
        "HASHES::ALL_FROZEN_BINDINGS_EXACT",
        hash_ok,
        {"bindingCount": len(observed_hashes), "mismatches": [v for v in observed_hashes.values() if v["actualSha256"] != v["expectedSha256"]]},
        {"bindingCount": len(EXPECTED_HASHES), "mismatches": []},
        domain="hashes",
        reason="One or more Status v28, v3 terminal-chain, planning, instrument, identity, runtime, or retained receipt hashes drifted.",
    )

    status28 = load_json(EXPECTED_HASHES["statusV28"][0])
    status28_ok = (
        status28.get("schema") == "gate14re-me-status-v28"
        and status28.get("version") == 28
        and status28.get("status") == "QUALIFICATION_EXECUTION_TERMINAL_CHAIN_CORRIGENDUM_PASS_READINESS_RECHECK_PENDING"
        and status28.get("authorizationState", {}).get("qualificationExecutionAuthorized") is False
        and status28.get("authorizationState", {}).get("measuredOrFormalDeliveryRootCreationAuthorized") is False
        and status28.get("terminalChainCorrigendumAttempt002", {}).get("passed") is True
        and status28.get("scientificBoundary", {}).get("unityInvocations") == 0
        and status28.get("scientificBoundary", {}).get("qualificationObservations") == 0
    )
    check(
        "STATUS::V28_AUTHORITATIVE_PENDING_STATE",
        status28_ok,
        {"schema": status28.get("schema"), "version": status28.get("version"), "status": status28.get("status"), "authorizationState": status28.get("authorizationState")},
        "Status v28 terminal-chain PASS with readiness recheck pending and execution/root creation unauthorized",
        domain="status",
        reason="Status v28 no longer expresses the exact authorized pre-readiness state.",
    )

    previous_audit = load_json(
        "Research/Verification/Gate14Re-ME/qualification-execution-readiness-freeze-attempt-002/readiness-audit.v2.json"
    )
    prior_pass_ids = [str(item.get("checkId")) for item in previous_audit.get("checks", []) if item.get("passed") is True]
    prior_fail_ids = [str(item.get("checkId")) for item in previous_audit.get("checks", []) if item.get("passed") is False]
    check(
        "RETENTION::READINESS_ATTEMPT002_35_PASS_2_FAIL_VERDICT_EXACT",
        len(prior_pass_ids) == 35
        and prior_fail_ids == [
            "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT",
            "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE",
        ],
        {"priorPassCount": len(prior_pass_ids), "priorFailedCheckIds": prior_fail_ids},
        {"priorPassCount": 35, "priorFailedCheckIds": ["TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT", "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE"]},
        domain="retention",
        reason="The retained attempt-002 readiness verdict was altered or no longer has its exact 35-pass/2-fail structure.",
    )

    contract = load_json(EXPECTED_HASHES["executionContractV31"][0])
    contract_header_ok = (
        contract.get("schema") == "gate14re-me-load-qualification-execution-contract-v3"
        and contract.get("version") == 3
        and contract.get("status") == "FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED"
        and contract.get("entryPoint", {}).get("supervisorSha256") == EXPECTED_HASHES["supervisorV3"][1]
        and contract.get("entryPoint", {}).get("runnerSha256") == EXPECTED_HASHES["runnerV2"][1]
        and contract.get("entryPoint", {}).get("runnerExecuteMethod") == "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run"
        and contract.get("entryPoint", {}).get("receiptGeneration") == 2
        and contract.get("entryPoint", {}).get("supervisorGeneration") == 3
    )
    check(
        "CONTRACT::V3_1_HEADER_ENTRY_POINT_AND_INERT_STATE",
        contract_header_ok,
        {"schema": contract.get("schema"), "status": contract.get("status"), "version": contract.get("version"), "entryPoint": contract.get("entryPoint")},
        "frozen v3/v3.1 entry point bound to supervisor-v3 and RunnerV2 with receipt generation 2",
        domain="execution-contract",
        reason="Execution contract v3.1 header, status, or entry point drifted.",
    )

    expected_binding_values = {
        "inputValidationSchema": EXPECTED_HASHES["inputSchemaV2"],
        "planningSchemaBinding": EXPECTED_HASHES["planningSchemaBindingV2"],
        "instrumentContract": EXPECTED_HASHES["instrumentContractV3"],
        "outputSchema": EXPECTED_HASHES["outputSchemaV3"],
        "qualifiedD3V31": EXPECTED_HASHES["d3V31"],
        "planningAssetsManifest": EXPECTED_HASHES["planningAssetsManifest"],
        "schedule": EXPECTED_HASHES["schedule"],
        "sealedIdentityBinding": EXPECTED_HASHES["sealedIdentity"],
        "trustedUnityIdentityRule": EXPECTED_HASHES["trustedIdentityRule"],
        "timestampComparator": EXPECTED_HASHES["timestampComparator"],
        "typedParquetRuntime": EXPECTED_HASHES["typedParquetRuntime"],
        "completeRawDeliveryContract": EXPECTED_HASHES["completeRawDeliveryContract"],
        "structuralV3": EXPECTED_HASHES["structuralV31"],
        "deliveryV21": EXPECTED_HASHES["deliveryV22"],
    }
    contract_bindings = contract.get("frozenBindings", {})
    binding_mismatches: list[dict[str, Any]] = []
    for key, (relative, digest) in expected_binding_values.items():
        observed = contract_bindings.get(key, {})
        if observed.get("relativePath") != relative or observed.get("sha256") != digest:
            binding_mismatches.append({"binding": key, "observed": observed, "expected": {"relativePath": relative, "sha256": digest}})
    check(
        "CONTRACT::FOURTEEN_FROZEN_BINDINGS_EXACT",
        set(contract_bindings) == set(expected_binding_values) and not binding_mismatches,
        {"bindingCount": len(contract_bindings), "bindingKeys": sorted(contract_bindings), "mismatches": binding_mismatches},
        {"bindingCount": 14, "bindingKeys": sorted(expected_binding_values), "mismatches": []},
        domain="execution-contract",
        reason="Execution contract v3.1 does not retain the exact fourteen frozen bindings.",
    )

    cardinalities = contract.get("expectedCardinalities", {})
    formula_ok = (
        cardinalities == EXPECTED_CARDINALITIES
        and 1 + 162 + 12 + 162 * 6 == 1147
        and 162 * 6 == 972
        and 972 * 24 == 23328
        and 972 * 25 == 24300
        and 972 * 26 == 25272
    )
    check(
        "CARDINALITY::CONTRACT_FORMULAS_AND_1147_TOTAL",
        formula_ok,
        cardinalities,
        EXPECTED_CARDINALITIES,
        domain="cardinality",
        reason="The frozen cardinalities or their process/raw-row formulas no longer close exactly.",
    )

    order = contract.get("executionOrder", {})
    order_ok = (
        order.get("maximumConcurrentUnityProcesses") == 1
        and order.get("instrumentSelfTestBeforeAnyOracleOrLane") is True
        and order.get("all162AlgorithmNeutralOracleProcessesBeforeAnyLane") is True
        and order.get("twelveFreshEmptyBoundaryProcessesBeforeAnyLane") is True
        and order.get("strictWilliamsSixLaneOrderWithinEachSuperblock") is True
        and order.get("oneFreshUnityProcessPerAlgorithmLane") is True
        and order.get("zeroReplacementPolicy") == "ZERO_REPLACEMENT_FAIL_STOP"
        and order.get("wholeSuperblockReplacementAssetsGeneratedOrConsumed") is False
        and order.get("perAlgorithmRetryResumeTopUpMergeSkipOrReorderProhibited") is True
    )
    check(
        "EXECUTION::STRICT_SERIAL_FRESH_ORDER_AND_ZERO_REPLACEMENT",
        order_ok,
        order,
        "one process at a time; 1 instrument, 162 oracle, 12 empty, then 972 Williams-ordered fresh lane processes; zero replacement fail-stop",
        domain="execution-control",
        reason="Execution order or zero-replacement fail-stop semantics drifted.",
    )

    authorization = contract.get("currentAuthorization", {})
    execution_flags = [
        "unityInvocationAuthorized", "qualificationMeasuredRootCreationAuthorized", "deliveryRootCreationAuthorized",
        "qualificationExecutionAuthorized", "replacementAssetGenerationAuthorized", "formalCollectionAuthorized",
        "formalAnalysisAuthorized", "rankingAuthorized", "winnerAdjudicationAuthorized",
    ]
    check(
        "CONTRACT::EXECUTION_AND_ANALYSIS_REMAIN_UNAUTHORIZED",
        all(authorization.get(field) is False for field in execution_flags),
        {field: authorization.get(field) for field in execution_flags},
        {field: False for field in execution_flags},
        domain="authorization-boundary",
        reason="The frozen contract unexpectedly authorizes Unity, root creation, qualification execution, collection, analysis, ranking, or winner adjudication.",
    )

    manifest = load_json(EXPECTED_HASHES["implementationManifestV31"][0])
    artifacts = list(manifest.get("artifacts", []))
    manifest_audit = declared_file_audit(artifacts)
    artifact_paths = {str(item.get("relativePath")) for item in artifacts}
    manifest_state_ok = (
        manifest.get("manifestGeneration") == 3
        and manifest.get("manifestSchemaV3") == "gate14re-me-qualification-current-implementation-manifest-v3"
        and manifest.get("executionReadinessStatus") == "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_AND_TERMINAL_CHAIN_CORRECTED_OFFLINE"
        and manifest.get("legacyRunnerCompatibility", {}).get("runnerV2SourceRemainsByteIdentical") is True
        and manifest.get("legacyRunnerCompatibility", {}).get("compiledAssembliesRemainByteIdentical") is True
        and manifest.get("terminalChainCorrigendum", {}).get("outputReceiptPathsCorrectedToRuntimeV2") is True
        and manifest.get("terminalChainCorrigendum", {}).get("structuralV3ClosesProcessResourcesPersistentPointsAcceptedReceiptsLedgerAndIdentities") is True
        and manifest.get("terminalChainCorrigendum", {}).get("supervisorV3ExplicitFinalProcessOrdinal1147") is True
        and manifest.get("terminalChainCorrigendum", {}).get("deliveryV22PreservesV2DeliveryFormat") is True
        and len(artifacts) == 48
        and manifest_audit["allPathsUnique"]
        and manifest_audit["mismatchCount"] == 0
        and all(relative in artifact_paths for relative, _ in expected_binding_values.values())
    )
    check(
        "MANIFEST::V3_1_FORTY_EIGHT_ARTIFACTS_EXACT_AND_TERMINAL_CORRECTED",
        manifest_state_ok,
        {"manifestGeneration": manifest.get("manifestGeneration"), "executionReadinessStatus": manifest.get("executionReadinessStatus"), "artifactAudit": manifest_audit, "terminalChainCorrigendum": manifest.get("terminalChainCorrigendum")},
        {"manifestGeneration": 3, "artifactCount": 48, "mismatchCount": 0, "terminalChainCorrected": True},
        domain="implementation-manifest",
        reason="Implementation manifest v3.1 or one of its forty-eight declared artifacts drifted.",
    )

    runtime_bindings = manifest.get("runtimeBindings", {})
    runtime_paths = {
        "unity": (pathlib.Path(str(runtime_bindings.get("unityExecutable", ""))), runtime_bindings.get("unityExecutableSha256")),
        "python": (pathlib.Path(str(runtime_bindings.get("pythonExecutable", ""))), runtime_bindings.get("pythonExecutableSha256")),
        "powershell": (pathlib.Path(str(runtime_bindings.get("powershellExecutable", ""))), runtime_bindings.get("powershellExecutableSha256")),
    }
    runtime_observed: dict[str, Any] = {}
    runtime_ok = True
    for name, (path, expected_hash) in runtime_paths.items():
        actual = sha256_file(path) if path.is_file() else None
        runtime_observed[name] = {"path": path.as_posix(), "expectedSha256": expected_hash, "actualSha256": actual}
        runtime_ok = runtime_ok and actual == expected_hash
    check(
        "RUNTIME::UNITY_PYTHON_POWERSHELL_EXECUTABLE_HASHES",
        runtime_ok,
        runtime_observed,
        "all three executable identities match the v3.1 implementation manifest",
        domain="runtime",
        reason="A frozen executable identity drifted.",
    )

    compile_receipt = load_json(EXPECTED_HASHES["compileIdentityReceipt"][0])
    compile_ok = (
        compile_receipt.get("status") == "PASS_CURRENT_PROJECT_COMPILED_ALGORITHM_FREE_TRUSTED_IDENTITY"
        and compile_receipt.get("unityInvocationCount") == 1
        and compile_receipt.get("executeMethod") is None
        and compile_receipt.get("naturalExit") is True
        and compile_receipt.get("exitCode") == 0
        and compile_receipt.get("signalOrForcedTerminationSent") is False
        and compile_receipt.get("retryPerformed") is False
        and compile_receipt.get("currentProjectCompiled") is True
        and compile_receipt.get("compilerFailureMarkersFound") == 0
        and compile_receipt.get("measuredRootCreated") is False
        and compile_receipt.get("deliveryRootCreated") is False
        and compile_receipt.get("plannerInvocations") == 0
        and compile_receipt.get("algorithmLaneExecutions") == 0
        and compile_receipt.get("editorAssembly", {}).get("sha256") == EXPECTED_HASHES["editorAssembly"][1]
        and compile_receipt.get("runtimeAssembly", {}).get("sha256") == EXPECTED_HASHES["runtimeAssembly"][1]
    )
    check(
        "COMPILE_IDENTITY::RUNNERV2_ASSEMBLIES_ALGORITHM_FREE_PASS",
        compile_ok,
        {key: compile_receipt.get(key) for key in ("status", "unityInvocationCount", "executeMethod", "naturalExit", "exitCode", "signalOrForcedTerminationSent", "retryPerformed", "currentProjectCompiled", "compilerFailureMarkersFound", "measuredRootCreated", "deliveryRootCreated", "plannerInvocations", "algorithmLaneExecutions")},
        "one retained algorithm-free compile identity PASS; exact assemblies; natural zero exit; no measured/delivery root or algorithm activity",
        domain="compiled-assemblies",
        reason="The retained compile/identity receipt no longer proves the exact algorithm-free RunnerV2 assemblies.",
    )

    input_schema = load_json(EXPECTED_HASHES["inputSchemaV2"][0])
    planning_binding = load_json(EXPECTED_HASHES["planningSchemaBindingV2"][0])
    input_props = input_schema.get("properties", {})
    event_items = input_props.get("eventGroups", {}).get("items", {})
    event_item_ref = event_items.get("$ref")
    event_item_schema = (
        input_schema.get("$defs", {}).get("eventGroup", {})
        if event_item_ref == "#/$defs/eventGroup"
        else event_items
    )
    input_ok = (
        input_schema.get("$id") == "gate14re-me-qualification-input-validation-schema-v2"
        and "eventGroups" in input_schema.get("required", [])
        and "topology" in event_item_schema.get("required", [])
        and planning_binding.get("schema") == "gate14re-me-load-qualification-planning-schema-binding-v2"
        and planning_binding.get("version") == 2
        and planning_binding.get("selectedInputValidationSchema", {}).get("sha256") == EXPECTED_HASHES["inputSchemaV2"][1]
        and planning_binding.get("corrigendum", {}).get("field") == "eventGroups[*].topology"
        and planning_binding.get("corrigendum", {}).get("declared") is True
        and planning_binding.get("corrigendum", {}).get("required") is True
        and planning_binding.get("corrigendum", {}).get("scientificDesignChanged") is False
    )
    check(
        "INPUT::SCHEMA_V2_AND_PLANNING_BINDING_V2_EXACT",
        input_ok,
        {"inputSchemaId": input_schema.get("$id"), "eventGroupItemsRef": event_item_ref, "eventGroupRequired": event_item_schema.get("required"), "bindingSchema": planning_binding.get("schema"), "selectedSchema": planning_binding.get("selectedInputValidationSchema"), "corrigendum": planning_binding.get("corrigendum")},
        "input schema v2 requires eventGroups[*].topology and planning binding v2 selects its exact hash without scientific-design change",
        domain="input-contract",
        reason="Input schema v2 or planning schema binding v2 is inconsistent or drifted.",
    )

    output_v2 = load_json(EXPECTED_HASHES["outputSchemaV2"][0])
    output_v3 = load_json(EXPECTED_HASHES["outputSchemaV3"][0])
    unchanged_sections = ["retentionRule", "identityRule", "d3Binding", "rawTables", "deliveryViews", "requiredRoundTripChecks"]
    unchanged = {key: output_v3.get(key) == output_v2.get(key) for key in unchanged_sections}
    output_header_ok = (
        output_v3.get("schema") == "gate14re-me-load-qualification-output-schema-v3"
        and output_v3.get("version") == 3
        and output_v3.get("status") == "FROZEN_COMPLETE_PER_OBSERVATION_D3_V3_1_TERMINAL_CHAIN_CORRIGENDUM"
        and output_v3.get("supersedes", {}).get("sha256") == EXPECTED_HASHES["outputSchemaV2"][1]
        and all(unchanged.values())
        and output_v3.get("corrigendum", {}).get("receiptPathVersionCorrectionOnly") is True
        and output_v3.get("corrigendum", {}).get("rawTableDefinitionsChanged") is False
        and output_v3.get("corrigendum", {}).get("metricSemanticsChanged") is False
        and output_v3.get("corrigendum", {}).get("scientificThresholdsChanged") is False
    )
    check(
        "OUTPUT_SCHEMA::V3_CORRIGENDUM_ONLY_SCIENTIFIC_CONTENT_UNCHANGED",
        output_header_ok,
        {"schema": output_v3.get("schema"), "version": output_v3.get("version"), "status": output_v3.get("status"), "unchangedSections": unchanged, "corrigendum": output_v3.get("corrigendum")},
        "v3 corrects receipt/terminal control only; raw tables, D3, delivery views, round trips, metrics, and thresholds remain byte-equivalent as JSON values",
        domain="output-schema",
        reason="Output schema v3 changes scientific content or fails to bind its superseded v2 schema.",
    )

    expected_receipts = {
        "_control/launch-receipt.v2.json", "oracle-pass-receipt.v1.json", "lane-receipt.v2.json",
        "accepted-superblock-receipt.v1.json", "empty-boundary-receipt.v2.json",
        "instrument-csharp-receipt.v2.json", "instrument-export-receipt.v2.json",
        "_control/acquisition-complete.v2.json", "delivery-manifest.v2.json",
    }
    receipt_set = set(output_v3.get("receipts", []))
    check(
        "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT_RESOLVED",
        receipt_set == expected_receipts,
        {"receipts": sorted(receipt_set), "missing": sorted(expected_receipts - receipt_set), "unexpected": sorted(receipt_set - expected_receipts)},
        {"receipts": sorted(expected_receipts), "missing": [], "unexpected": []},
        domain="terminal-chain",
        reason="The exact v2 runtime receipt set is not aligned with output schema v3.",
    )

    terminal_plane = output_v3.get("terminalControlPlane", {})
    closure = terminal_plane.get("fullQualificationClosure", {})
    expected_closure = {
        "laneReceipts": 972,
        "emptyBoundaryReceipts": 12,
        "acceptedSuperblockReceipts": 162,
        "eventGroupRows": 23328,
        "laneD3WindowRows": 24300,
        "instrumentD3WindowRows": 1,
        "emptyBoundaryD3WindowRows": 12000,
        "processResourceRows": 25272,
        "processResourceRowsPerLane": 26,
        "persistentStateMeasurementPointsPerLane": 26,
        "processLedgerRows": 1147,
        "processIdentityReceipts": 1147,
        "supervisorFinalProcessOrdinal": 1147,
    }
    terminal_plane_ok = (
        closure == expected_closure
        and terminal_plane.get("acceptedSuperblockReceipts", {}).get("expectedQualificationFull") == 162
        and terminal_plane.get("processLedger", {}).get("expectedQualificationFullRows") == 1147
        and terminal_plane.get("processLedger", {}).get("qualificationModeCounts") == {"instrument-self-test": 1, "oracle": 162, "empty-boundary": 12, "lane": 972}
        and terminal_plane.get("processLedger", {}).get("strictZeroBasedOrdinalCoverage") is True
        and terminal_plane.get("processLedger", {}).get("identityReceiptHashLinkRequired") is True
        and terminal_plane.get("processIdentityReceipts", {}).get("expectedQualificationFull") == 1147
        and terminal_plane.get("processIdentityReceipts", {}).get("naturalExitRequired") is True
        and terminal_plane.get("processIdentityReceipts", {}).get("zeroExitRequired") is True
        and terminal_plane.get("processIdentityReceipts", {}).get("signalOrForcedTerminationProhibited") is True
        and terminal_plane.get("processIdentityReceipts", {}).get("retryProhibited") is True
    )
    check(
        "TERMINAL::FULL_CARDINALITY_LEDGER_IDENTITY_AND_ORDINAL_SCHEMA_CLOSURE",
        terminal_plane_ok,
        terminal_plane,
        {"fullQualificationClosure": expected_closure, "ledgerModes": {"instrument-self-test": 1, "oracle": 162, "empty-boundary": 12, "lane": 972}, "naturalZeroExitNoSignalNoRetry": True},
        domain="terminal-chain",
        reason="Output schema v3 does not close the full cardinality, accepted receipt, process ledger, identity receipt, or final ordinal chain.",
    )

    structural_text = read_text(EXPECTED_HASHES["structuralV31"][0])
    delivery_text = read_text(EXPECTED_HASHES["deliveryV22"][0])
    structural_ast = ast.parse(structural_text)
    delivery_ast = ast.parse(delivery_text)
    structural_functions = {node.name for node in ast.walk(structural_ast) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    delivery_functions = {node.name for node in ast.walk(delivery_ast) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    structural_tokens = [
        "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE", "validate_terminal_control_plane",
        "accepted-superblock-receipt.v1.json", "process-ledger.raw.v2.jsonl",
        "gate14re-me-qualified-unity-process-identity-receipt-v2", "processResourceRows",
        "persistentStateMeasurementPointLanePairs", "supervisorFinalProcessOrdinal",
        "rankingOrWinnerComputed", "crossAlgorithmEffectsComputed",
    ]
    structural_ok = (
        "validate_terminal_control_plane" in structural_functions
        and all(token in structural_text for token in structural_tokens)
        and "qualification-full" in structural_text
        and "synthetic-known-answer" in structural_text
        and "scipy" not in structural_text
        and "statsmodels" not in structural_text
        and "numpy" not in structural_text
    )
    check(
        "STRUCTURAL::V3_1_PARSE_BIND_AND_NO_INFERENCE",
        structural_ok,
        {"functionCount": len(structural_functions), "requiredFunctionPresent": "validate_terminal_control_plane" in structural_functions, "missingTokens": [token for token in structural_tokens if token not in structural_text], "statisticalImportsAbsent": all(name not in structural_text for name in ("scipy", "statsmodels", "numpy"))},
        "AST parses; validates full terminal plane and declares no cross-algorithm effects, ranking, or winner",
        domain="structural-v3.1",
        reason="Structural-v3.1 no longer exposes the full raw terminal closure or has acquired an inference dependency.",
    )

    delivery_tokens = [
        "gate14re-me-qualification-delivery-manifest-v2", "delivery-manifest.v2.json",
        "instrument-export-receipt.v2.json", "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY",
        "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY", "typed-parquet",
        "recordId order/uniqueness mismatch", "aggregateOnlyPackage",
    ]
    delivery_ok = (
        {"build_delivery", "verify_delivery", "round_trip_validate", "write_parquet"}.issubset(delivery_functions)
        and all(token in delivery_text for token in delivery_tokens)
        and "gate14re_me_qualification_structural_v3_1" in delivery_text
        and "scipy" not in delivery_text
        and "statsmodels" not in delivery_text
    )
    check(
        "DELIVERY::V2_2_PARSE_V3_ADAPTER_AND_LOSSLESS_FOUR_FORMAT_CHAIN",
        delivery_ok,
        {"functionCount": len(delivery_functions), "requiredFunctionsPresent": sorted({"build_delivery", "verify_delivery", "round_trip_validate", "write_parquet"} & delivery_functions), "missingTokens": [token for token in delivery_tokens if token not in delivery_text], "importsStructuralV31": "gate14re_me_qualification_structural_v3_1" in delivery_text},
        "AST parses; schema-v3 structural adapter; JSONL/CSV/JSONL.GZ/typed-Parquet lossless delivery; v2 manifest/receipt contract",
        domain="delivery-v2.2",
        reason="Delivery-v2.2 no longer parses, binds structural-v3.1, or preserves the complete per-observation four-format chain.",
    )

    supervisor_rel = EXPECTED_HASHES["supervisorV3"][0]
    supervisor_path = project_file(supervisor_rel)
    supervisor_text = read_text(supervisor_rel)
    ps_errors = powershell_parse_errors(supervisor_path)
    check(
        "SUPERVISOR::V3_POWERSHELL_AST_CLEAN",
        not ps_errors,
        {"parseErrors": ps_errors},
        {"parseErrors": []},
        domain="supervisor-v3",
        reason="Supervisor-v3 no longer parses as PowerShell.",
    )

    mutation_marker = "# A later, separately authorized invocation reaches this mutation boundary."
    main_body = supervisor_text.split(mutation_marker, 1)[1] if mutation_marker in supervisor_text else ""
    ordered_tokens = [
        "Invoke-VerifiedFreshUnityProcess -Mode 'instrument-self-test'",
        "Invoke-VerifiedFreshUnityProcess -Mode 'oracle'",
        "Invoke-VerifiedFreshUnityProcess -Mode 'empty-boundary'",
        "Invoke-Superblock -Record $record",
        "Require-Condition ($processOrdinal -eq 1147)",
        "_control/acquisition-complete.v2.json",
        "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE",
        "'build'",
        "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY",
        "'verify'",
        "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY",
        "_control/qualification-complete.v2.json",
    ]
    positions = [main_body.find(token) for token in ordered_tokens]
    supervisor_flow_ok = (
        main_body
        and all(pos >= 0 for pos in positions)
        and positions == sorted(positions)
        and "$processOrdinal = 0" in supervisor_text
        and "$script:processOrdinal++" in supervisor_text
        and "Fresh process output already exists" in supervisor_text
        and "process-ledger.raw.v2.jsonl" in supervisor_text
        and "process-identities" in supervisor_text
        and "PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT" in supervisor_text
        and "WaitForExit" in supervisor_text
        and "signalOrForcedTerminationSent = $false" in supervisor_text
        and "retryPerformed = $false" in supervisor_text
        and "Start-Job" not in supervisor_text
        and "Start-ThreadJob" not in supervisor_text
        and "ForEach-Object -Parallel" not in supervisor_text
        and "Stop-Process" not in supervisor_text
        and ".Kill(" not in supervisor_text
    )
    check(
        "SUPERVISOR::V3_STATIC_SERIAL_FRESH_1147_TERMINAL_STATE_MACHINE",
        supervisor_flow_ok,
        {"orderedTokenPositions": dict(zip(ordered_tokens, positions)), "processOrdinalInitialized": "$processOrdinal = 0" in supervisor_text, "singleIncrementSiteCount": supervisor_text.count("$script:processOrdinal++"), "parallelPrimitivesAbsent": all(token not in supervisor_text for token in ("Start-Job", "Start-ThreadJob", "ForEach-Object -Parallel")), "terminationSignalsAbsent": "Stop-Process" not in supervisor_text and ".Kill(" not in supervisor_text},
        "ordered instrument/oracle/empty/lane phases; one ordinal increment per fresh process; exact final 1147 assertion; structural then delivery; no parallelism, retry, or signal",
        domain="supervisor-v3",
        reason="Supervisor-v3 static control flow no longer proves the required serial fresh-process and terminal-chain ordering.",
    )

    runtime_receipt_tokens = {
        "_control/launch-receipt.v2.json": "_control/launch-receipt.v2.json",
        "oracle-pass-receipt.v1.json": "oracle-pass-receipt.v1.json",
        "lane-receipt.v2.json": "lane-receipt.v2.json",
        "accepted-superblock-receipt.v1.json": "accepted-superblock-receipt.v1.json",
        "empty-boundary-receipt.v2.json": "empty-boundary-receipt.v2.json",
        "instrument-csharp-receipt.v2.json": "instrument-csharp-receipt.v2.json",
        "instrument-export-receipt.v2.json": "instrument-export-receipt.v2.json",
        "_control/acquisition-complete.v2.json": "_control/acquisition-complete.v2.json",
        "delivery-manifest.v2.json": "delivery-manifest.v2.json",
    }
    runtime_receipts_present = {
        receipt: (token in supervisor_text or token in delivery_text)
        for receipt, token in runtime_receipt_tokens.items()
    }
    stale_corrected = [
        "_control/launch-receipt.v1.json", "_control/acquisition-complete.v1.json",
        "instrument-export-receipt.v1.json", "delivery-manifest.v1.json",
    ]
    stale_present = [token for token in stale_corrected if token in supervisor_text or token in delivery_text]
    check(
        "TERMINAL::RUNTIME_RECEIPT_VERSIONS_MATCH_SCHEMA_V3",
        all(runtime_receipts_present.values()) and not stale_present,
        {"runtimeReceiptPresence": runtime_receipts_present, "staleCorrectedReceiptTokensPresent": stale_present},
        {"runtimeReceiptPresence": {key: True for key in runtime_receipt_tokens}, "staleCorrectedReceiptTokensPresent": []},
        domain="terminal-chain",
        reason="Supervisor/delivery runtime receipt paths do not match output schema v3 exactly.",
    )

    terminal_pass = load_json(EXPECTED_HASHES["terminalAttempt002Pass"][0])
    negative_fixtures = terminal_pass.get("structuralNegativeFixtures", [])
    structural_positive = terminal_pass.get("structuralPositive", {})
    delivery_known = terminal_pass.get("deliveryKnownAnswer", {})
    known_answer_ok = (
        terminal_pass.get("status") == "PASS_TERMINAL_CHAIN_CORRIGENDUM_OFFLINE_ONLY"
        and terminal_pass.get("passed") is True
        and structural_positive.get("status") == "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE"
        and structural_positive.get("outputSchemaSha256") == EXPECTED_HASHES["outputSchemaV3"][1]
        and structural_positive.get("d3ContractSha256") == EXPECTED_HASHES["d3V31"][1]
        and structural_positive.get("terminalControlPlaneClosed") is True
        and structural_positive.get("supervisorFinalProcessOrdinalAsserted") is True
        and structural_positive.get("crossAlgorithmEffectsComputed") is False
        and structural_positive.get("rankingOrWinnerComputed") is False
        and len(negative_fixtures) == 6
        and all(item.get("passed") is True for item in negative_fixtures)
        and delivery_known.get("tables") == 10
        and delivery_known.get("products") == 40
        and delivery_known.get("buildStatus") == "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY"
        and delivery_known.get("verifyStatus") == "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY"
        and delivery_known.get("missingProductNegativePassed") is True
        and terminal_pass.get("scientificBoundary", {}).get("unityInvocationCount") == 0
        and terminal_pass.get("scientificBoundary", {}).get("plannerInvocationCount") == 0
        and terminal_pass.get("scientificBoundary", {}).get("algorithmLaneExecutionCount") == 0
    )
    check(
        "KNOWN_ANSWER::TERMINAL_CHAIN_POSITIVE_SIX_NEGATIVES_AND_40_PRODUCTS",
        known_answer_ok,
        {"status": terminal_pass.get("status"), "structuralPositive": structural_positive, "negativeFixtures": negative_fixtures, "deliveryKnownAnswer": delivery_known, "scientificBoundary": terminal_pass.get("scientificBoundary")},
        "schema-v3 structural positive, six fail-closed negatives, 10 tables x 4 lossless products, no Unity/planner/lane",
        domain="terminal-known-answer",
        reason="The retained terminal-chain known-answer evidence is incomplete, drifted, or no longer terminal PASS.",
    )

    planning_manifest = load_json(EXPECTED_HASHES["planningAssetsManifest"][0])
    planning_entries = list(planning_manifest.get("artifacts", []))
    planning_audit = declared_file_audit(planning_entries)
    input_entries = [entry for entry in planning_entries if entry.get("role") == "qualification-input-bundle"]
    check(
        "PLANNING::ONE_HUNDRED_SEVENTY_THREE_ARTIFACTS_AND_162_INPUTS_EXACT",
        planning_manifest.get("status") == "FROZEN_PLANNING_ASSETS_PASS"
        and planning_manifest.get("artifactCount") == 173
        and len(planning_entries) == 173
        and len(input_entries) == 162
        and planning_manifest.get("allPathsUnique") is True
        and planning_manifest.get("allHashesAndLengthsMatchedAtFreeze") is True
        and planning_manifest.get("identityBindingRemainsSealed") is True
        and planning_manifest.get("partialPlanningAssetsMayBeAdopted") is False
        and planning_audit["allPathsUnique"]
        and planning_audit["mismatchCount"] == 0,
        {"status": planning_manifest.get("status"), "declaredArtifactCount": planning_manifest.get("artifactCount"), "inputBundleCount": len(input_entries), "artifactAudit": planning_audit, "identityBindingRemainsSealed": planning_manifest.get("identityBindingRemainsSealed")},
        {"status": "FROZEN_PLANNING_ASSETS_PASS", "artifactCount": 173, "inputBundleCount": 162, "mismatchCount": 0, "identityBindingRemainsSealed": True},
        domain="planning-assets",
        reason="Frozen planning assets are missing, duplicated, changed, or no longer bind all 162 inputs.",
    )

    schedule_rows = read_jsonl(EXPECTED_HASHES["schedule"][0])
    ordinals = [row.get("ordinal") for row in schedule_rows]
    superblocks = [row.get("superblockId") for row in schedule_rows]
    input_paths = [row.get("inputRelativePath") for row in schedule_rows]
    input_hashes = [row.get("inputSha256") for row in schedule_rows]
    position_counts: collections.Counter[tuple[str, int]] = collections.Counter()
    adjacency_counts: collections.Counter[tuple[str, str]] = collections.Counter()
    sequence_counts: collections.Counter[tuple[str, ...]] = collections.Counter()
    row_shape_ok = True
    input_hash_ok = True
    replacement_null = True
    identity_hash_only = True
    for row in schedule_rows:
        order_items = list(row.get("algorithmOrder", []))
        algorithms = [str(item.get("algorithmId")) for item in order_items]
        lanes = [str(item.get("anonymousLaneId")) for item in order_items]
        if len(order_items) != 6 or set(algorithms) != EXPECTED_ALGORITHMS or set(lanes) != EXPECTED_LANES:
            row_shape_ok = False
        for pos, algorithm in enumerate(algorithms):
            position_counts[(algorithm, pos)] += 1
        for left, right in zip(algorithms, algorithms[1:]):
            adjacency_counts[(left, right)] += 1
        sequence_counts[tuple(algorithms)] += 1
        if row.get("replacement") is not None:
            replacement_null = False
        if any(item.get("identityBindingSha256") != EXPECTED_HASHES["sealedIdentity"][1] for item in order_items):
            identity_hash_only = False
        path = project_file(str(row.get("inputRelativePath", "")))
        if not path.is_file() or sha256_file(path) != row.get("inputSha256"):
            input_hash_ok = False
    expected_position = {(algorithm, pos): 27 for algorithm in EXPECTED_ALGORITHMS for pos in range(6)}
    expected_adjacency = {(left, right): 27 for left in EXPECTED_ALGORITHMS for right in EXPECTED_ALGORITHMS if left != right}
    core_count = sum(1 for value in superblocks if isinstance(value, str) and value.startswith("G14ME-QSB-C"))
    stress_count = sum(1 for value in superblocks if isinstance(value, str) and value.startswith("G14ME-QSB-S"))
    schedule_ok = (
        len(schedule_rows) == 162
        and ordinals == list(range(162))
        and len(set(superblocks)) == 162
        and len(set(input_paths)) == 162
        and len(set(input_hashes)) == 162
        and core_count == 144
        and stress_count == 18
        and row_shape_ok
        and input_hash_ok
        and replacement_null
        and identity_hash_only
        and dict(position_counts) == expected_position
        and dict(adjacency_counts) == expected_adjacency
        and len(sequence_counts) == 6
        and set(sequence_counts.values()) == {27}
    )
    check(
        "PLANNING::162_ROW_SIX_ALGORITHM_WILLIAMS_BALANCE_UNIQUENESS_AND_ZERO_REPLACEMENT",
        schedule_ok,
        {"rows": len(schedule_rows), "ordinalCoverage": ordinals == list(range(162)), "uniqueSuperblocks": len(set(superblocks)), "uniqueInputPaths": len(set(input_paths)), "uniqueInputHashes": len(set(input_hashes)), "core": core_count, "stress": stress_count, "rowShape": row_shape_ok, "inputHashesExact": input_hash_ok, "replacementFieldsAllNull": replacement_null, "identityHashBindingsExact": identity_hash_only, "positionCountsAll27": dict(position_counts) == expected_position, "orderedAdjacencyCountsAll27": dict(adjacency_counts) == expected_adjacency, "distinctWilliamsSequences": len(sequence_counts), "eachSequenceCount": sorted(set(sequence_counts.values()))},
        {"rows": 162, "ordinals": "0..161", "uniqueSuperblocks": 162, "uniqueInputs": 162, "core": 144, "stress": 18, "sixAlgorithmsAndLanesPerRow": True, "positionsPerAlgorithm": 27, "orderedAdjacencyPerPair": 27, "sixSequencesEach": 27, "replacement": None},
        domain="planning-schedule",
        reason="The 162-row schedule fails uniqueness, six-algorithm, Williams, input-hash, sealed-identity-hash, or zero-replacement checks.",
    )

    sealed_path = project_file(EXPECTED_HASHES["sealedIdentity"][0])
    check(
        "IDENTITY::SEALED_BINDING_HASHED_NOT_OPENED",
        sealed_path.is_file()
        and sha256_file(sealed_path) == EXPECTED_HASHES["sealedIdentity"][1]
        and is_read_only(sealed_path)
        and contract_bindings.get("sealedIdentityBinding", {}).get("mustRemainSealedDuringQualification") is True,
        {"relativePath": EXPECTED_HASHES["sealedIdentity"][0], "sha256": sha256_file(sealed_path), "readOnly": is_read_only(sealed_path), "mustRemainSealed": contract_bindings.get("sealedIdentityBinding", {}).get("mustRemainSealedDuringQualification"), "contentParsedByThisAudit": False, "mappingDisclosed": False},
        {"sha256": EXPECTED_HASHES["sealedIdentity"][1], "readOnly": True, "mustRemainSealed": True, "contentParsedByThisAudit": False, "mappingDisclosed": False},
        domain="sealed-identity",
        reason="The sealed identity binding drifted, lost its read-only freeze, or ceased to be contractually sealed.",
    )

    fairness = load_json(EXPECTED_HASHES["fairnessBinding"][0])
    fairness_algorithms = fairness.get("algorithms", [])
    fairness_mismatches: list[dict[str, Any]] = []
    for item in fairness_algorithms:
        for path_key, hash_key in (("implementationRelativePath", "implementationSha256"), ("specificationRelativePath", "specificationSha256")):
            path = project_file(str(item.get(path_key, "")))
            actual = sha256_file(path) if path.is_file() else None
            if actual != item.get(hash_key):
                fairness_mismatches.append({"algorithmId": item.get("algorithmId"), "path": item.get(path_key), "expectedSha256": item.get(hash_key), "actualSha256": actual})
    fairness_ok = (
        fairness.get("status") == "FROZEN_SIX_ALGORITHM_BINDING"
        and {item.get("algorithmId") for item in fairness_algorithms} == EXPECTED_ALGORITHMS
        and len(fairness_algorithms) == 6
        and not fairness_mismatches
        and fairness.get("sameByteIdenticalInputBundle") is True
        and fairness.get("oneFreshProcessPerAlgorithmLane") is True
        and fairness.get("sameDynamicBoundary") is True
        and fairness.get("sameOracle") is True
    )
    check(
        "FAIRNESS::SIX_ALGORITHM_SOURCE_AND_SPEC_BINDINGS_EXACT",
        fairness_ok,
        {"status": fairness.get("status"), "algorithmIds": sorted(str(item.get("algorithmId")) for item in fairness_algorithms), "mismatches": fairness_mismatches, "sameInput": fairness.get("sameByteIdenticalInputBundle"), "freshProcess": fairness.get("oneFreshProcessPerAlgorithmLane"), "sameBoundary": fairness.get("sameDynamicBoundary"), "sameOracle": fairness.get("sameOracle")},
        {"algorithmIds": sorted(EXPECTED_ALGORITHMS), "mismatches": [], "sameInputFreshProcessBoundaryOracle": True},
        domain="fairness-binding",
        reason="One of the six algorithm source/specification bindings or fairness invariants drifted.",
    )

    runtime_failure = load_json(EXPECTED_HASHES["runtimeAttempt001Failure"][0])
    runtime_instrument = load_json(EXPECTED_HASHES["runtimeInstrumentReceipt"][0])
    csharp_known = runtime_failure.get("csharpKnownAnswer", {})
    d2_d4_clock_ok = (
        runtime_failure.get("status") == "FAIL_CLOSED_D3_ALLOCATION_COUNTER_POSITIVE_CONTROL"
        and csharp_known.get("receiptSha256") == EXPECTED_HASHES["runtimeInstrumentReceipt"][1]
        and csharp_known.get("d2GridReadProxyKnownAnswerPassed") is True
        and csharp_known.get("d2SemanticInvariancePassed") is True
        and csharp_known.get("d4PersistentStateSizerSyntheticFixturePassed") is True
        and csharp_known.get("clockMonotonicityPassed") is True
        and csharp_known.get("clockSamples") == 10000
        and runtime_instrument.get("gridReadProxyKnownAnswerPassed") is True
        and runtime_instrument.get("persistentStateSizerSyntheticFixturePassed") is True
        and runtime_instrument.get("clockMonotonicityPassed") is True
    )
    check(
        "INSTRUMENTS::D2_D4_AND_CLOCK_RETAINED_PASS_WITH_OLD_D3_FAILURE_UNCHANGED",
        d2_d4_clock_ok,
        {"retainedOverallStatus": runtime_failure.get("status"), "D2": {"gridReadProxy": csharp_known.get("d2GridReadProxyKnownAnswerPassed"), "semanticInvariance": csharp_known.get("d2SemanticInvariancePassed")}, "D4": csharp_known.get("d4PersistentStateSizerSyntheticFixturePassed"), "clock": {"monotonic": csharp_known.get("clockMonotonicityPassed"), "samples": csharp_known.get("clockSamples")}, "oldD3PositiveControlPassed": csharp_known.get("d3AllocationCounterPositiveControlPassed")},
        "retained original attempt remains FAIL_CLOSED for old D3, while its independent D2, D4, and 10,000-sample clock subtests remain PASS",
        domain="instrumentation",
        reason="The retained D2, D4, or clock known-answer evidence drifted or no longer passes.",
    )

    d3 = load_json(EXPECTED_HASHES["d3V31"][0])
    d3_bindings = d3.get("frozenImplementationBindings", {})
    d3_mismatches: list[dict[str, Any]] = []
    for key, value in d3_bindings.items():
        if key.endswith("RelativePath"):
            hash_key = key[:-12] + "Sha256"
            if hash_key in d3_bindings:
                path = project_file(str(value))
                actual = sha256_file(path) if path.is_file() else None
                if actual != d3_bindings.get(hash_key):
                    d3_mismatches.append({"binding": key, "relativePath": value, "expectedSha256": d3_bindings.get(hash_key), "actualSha256": actual})
    d3_known = load_json(str(d3_bindings.get("knownAnswerReceiptRelativePath")))
    d3_cycle = load_json(str(d3_bindings.get("knownAnswerCycleReceiptRelativePath")))
    d3_ok = (
        d3.get("status") == "QUALIFIED_FROZEN_D3_V3_1"
        and str(d3.get("semanticVersion")) == "3.1"
        and d3.get("qualifiedKnownAnswerCriteria", {}).get("allCriteriaPassed") is True
        and not d3_mismatches
        and d3_known.get("status") == "PASS_D3_V3_1_TRUE_CUMULATIVE_MANAGED_ALLOCATION_QUALIFICATION"
        and d3_cycle.get("status") == "PASS_D3_V3_1_STRICT_JSON_KNOWN_ANSWER"
    )
    check(
        "D3::V3_1_TRUE_CUMULATIVE_MANAGED_ALLOCATION_QUALIFIED",
        d3_ok,
        {"status": d3.get("status"), "semanticVersion": d3.get("semanticVersion"), "allCriteriaPassed": d3.get("qualifiedKnownAnswerCriteria", {}).get("allCriteriaPassed"), "bindingMismatches": d3_mismatches, "knownAnswerStatus": d3_known.get("status"), "cycleStatus": d3_cycle.get("status")},
        "qualified D3-v3.1 exact source/binary/wrapper/harness and terminal known-answer evidence",
        domain="D3-v3.1",
        reason="Qualified D3-v3.1 bindings or known-answer evidence drifted or ceased to be terminal PASS.",
    )

    typed_manifest = load_json(EXPECTED_HASHES["typedParquetRuntime"][0])
    typed_entries = list(typed_manifest.get("installedFiles", [])) + list(typed_manifest.get("wheelArtifacts", []))
    typed_audit = declared_file_audit(typed_entries)
    distribution = typed_manifest.get("distribution", {})
    typed_ok = (
        typed_manifest.get("status") == "FROZEN_TYPED_PARQUET_RUNTIME"
        and typed_manifest.get("installedFileCount") == 762
        and len(typed_manifest.get("installedFiles", [])) == 762
        and typed_manifest.get("wheelArtifactCount") == 1
        and len(typed_manifest.get("wheelArtifacts", [])) == 1
        and typed_audit["allPathsUnique"]
        and typed_audit["mismatchCount"] == 0
        and distribution == {"name": "pyarrow", "platform": "win_amd64", "pythonAbi": "cp312", "version": "25.0.1"}
    )
    check(
        "RUNTIME::TYPED_PARQUET_763_DECLARED_FILES_EXACT",
        typed_ok,
        {"status": typed_manifest.get("status"), "distribution": distribution, **typed_audit},
        {"installedFiles": 762, "wheelArtifacts": 1, "distribution": {"name": "pyarrow", "platform": "win_amd64", "pythonAbi": "cp312", "version": "25.0.1"}, "mismatchCount": 0},
        domain="typed-parquet-runtime",
        reason="Frozen typed-Parquet runtime is incomplete, drifted, or has the wrong distribution identity.",
    )

    identity_rule = load_json(EXPECTED_HASHES["trustedIdentityRule"][0])
    timestamp_receipt = load_json(EXPECTED_HASHES["timestampKnownAnswer"][0])
    identity_req = identity_rule.get("requirements", {})
    identity_ok = (
        identity_rule.get("status") == "FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION"
        and identity_rule.get("evidenceClassification") == "EXTERNAL_COMPOSITE_IDENTITY_AUTHORITATIVE_IN_PROCESS_READS_DIAGNOSTIC"
        and identity_req.get("externalThreePhaseExpectedSha256AndIndependentMethodAgreement") is True
        and identity_req.get("external64KiBChunksPathFileIdPeSignerAndMetadataStable") is True
        and identity_req.get("pidCreationTimePathCommandLineAndExecuteMethodBound") is True
        and identity_req.get("normalExitAndPostExitReconfirmationRequired") is True
        and identity_req.get("inProcessSelfHashesRequiredForAuthorization") is False
        and identity_req.get("fileReadAllBytesRole") == "DIAGNOSTIC_ONLY"
        and timestamp_receipt.get("status") == "PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER"
    )
    check(
        "IDENTITY::TRUSTED_RULE_AND_ATTEMPT007_TIMESTAMP_COMPARATOR_PASS",
        identity_ok,
        {"ruleStatus": identity_rule.get("status"), "classification": identity_rule.get("evidenceClassification"), "requirements": identity_req, "timestampComparatorStatus": timestamp_receipt.get("status")},
        "three-phase external identity plus process composite, natural exit, diagnostic-only in-process reads, and attempt-007 comparator PASS",
        domain="unity-identity",
        reason="Trusted Unity identity rule or attempt-007 timestamp comparator evidence drifted.",
    )

    budget = load_json(EXPECTED_HASHES["resourceBudget"][0])
    timeout_fields = [
        "eventGroupHardTimeoutMilliseconds", "laneWallClockHardTimeoutMilliseconds", "oracleInputHardTimeoutMilliseconds",
        "instrumentProcessHardTimeoutMilliseconds", "emptyBoundaryProcessHardTimeoutMilliseconds",
        "plannerOperationBudgetMilliseconds", "repairOperationBudgetMilliseconds", "initializationOperationBudgetMilliseconds",
    ]
    reservations = int(budget.get("qualificationReservedStorageBytes", 0)) + int(budget.get("formalRawAndDeliveryReservedStorageBytes", 0))
    budget_ok = (
        budget.get("status") == "FROZEN_PREEXECUTION_BUDGETS"
        and budget.get("maximumConcurrentUnityProcesses") == 1
        and all(isinstance(budget.get(field), int) and budget.get(field) > 0 for field in timeout_fields)
        and int(pre_system.get("totalVisibleMemoryBytes", 0)) >= int(budget.get("laneAssignedCommittedMemoryBytes", 0))
        and int(pre_system.get("driveHFreeBytes", 0)) >= reservations
        and pre_system.get("logicalProcessors") == budget.get("hostSnapshot", {}).get("logicalProcessors")
        and pre_system.get("operatingSystemVersion") == budget.get("hostSnapshot", {}).get("operatingSystemVersion")
    )
    check(
        "BUDGET::CURRENT_HOST_QUALIFIES_WITH_BOTH_RESERVATIONS",
        budget_ok,
        {"status": budget.get("status"), "positiveTimeoutFields": all(isinstance(budget.get(field), int) and budget.get(field) > 0 for field in timeout_fields), "maximumConcurrentUnityProcesses": budget.get("maximumConcurrentUnityProcesses"), "visibleMemoryBytes": pre_system.get("totalVisibleMemoryBytes"), "requiredAssignedMemoryBytes": budget.get("laneAssignedCommittedMemoryBytes"), "driveHFreeBytes": pre_system.get("driveHFreeBytes"), "requiredCombinedReservationsBytes": reservations, "logicalProcessors": pre_system.get("logicalProcessors"), "expectedLogicalProcessors": budget.get("hostSnapshot", {}).get("logicalProcessors"), "operatingSystemVersion": pre_system.get("operatingSystemVersion"), "expectedOperatingSystemVersion": budget.get("hostSnapshot", {}).get("operatingSystemVersion")},
        "positive frozen time/memory budgets, concurrency 1, same host class, and H: free space at least both frozen reservations",
        domain="runtime-budget",
        reason="Current host no longer satisfies the frozen runtime budget and storage reservations.",
    )

    data_delivery = load_json(EXPECTED_HASHES["completeRawDeliveryContract"][0])
    bridge = load_json(EXPECTED_HASHES["schemaBridgeValidation"][0])
    delivery_views = output_v3.get("deliveryViews", {})
    raw_tables = [item.get("tableId") for item in output_v3.get("rawTables", [])]
    expected_tables = [
        "oracle-agent-checks", "oracle-event-checks", "operations", "event-groups", "d3-windows",
        "persistent-state", "process-resources", "empty-boundary", "replacement-ledger", "failures-and-voids",
    ]
    delivery_gate_ok = (
        raw_tables == expected_tables
        and delivery_views.get("aggregateOnlyAllowed") is False
        and delivery_views.get("rowIdentityPreservedAcrossViews") is True
        and delivery_views.get("rowOrderManifested") is True
        and bridge.get("status") == "PASS_SCHEMA_V2_TOOLING_BRIDGE_VALIDATION"
        and bridge.get("positiveDeliveryCheck", {}).get("aggregateOnlyPackage") is False
        and bridge.get("positiveDeliveryCheck", {}).get("completeValueTypeOrderRoundTripPassed") is True
        and bridge.get("positiveDeliveryCheck", {}).get("typedParquetRoundTripPassed") is True
        and data_delivery.get("hardCondition", {}).get("completePerObservationRawDataDeliverable") is True
        and data_delivery.get("hardCondition", {}).get("mandatoryForPrecollectionReadiness") is True
        and data_delivery.get("hardCondition", {}).get("mandatoryBeforeAnyFormalAnalysisAuthorizationCanBeExercised") is True
        and data_delivery.get("rawFieldRetention", {}).get("aggregationOnlyStorageForbidden") is True
    )
    check(
        "DELIVERY::COMPLETE_PER_OBSERVATION_HARD_GATE_AND_BRIDGE",
        delivery_gate_ok,
        {"rawTables": raw_tables, "deliveryViews": delivery_views, "bridgeStatus": bridge.get("status"), "bridgeDelivery": bridge.get("positiveDeliveryCheck"), "hardCondition": data_delivery.get("hardCondition"), "aggregationOnlyStorageForbidden": data_delivery.get("rawFieldRetention", {}).get("aggregationOnlyStorageForbidden")},
        "ten raw tables; every-row four-format delivery; exact identity/order; bridge PASS; complete-per-observation hard gate; no aggregate-only substitute",
        domain="complete-raw-delivery",
        reason="Complete per-observation deliverability is no longer a verified hard gate.",
    )

    post_chain = contract.get("postAcquisitionTerminalChain", [])
    post_chain_ok = (
        len(post_chain) == 5
        and "acquisition-complete.v2" in post_chain[0]
        and "structural-v3" in post_chain[1]
        and "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE" in post_chain[1]
        and "delivery-v2.2" in post_chain[2]
        and "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY" in post_chain[3]
        and "qualification-complete.v2" in post_chain[4]
        and "no analysis" in post_chain[4]
    )
    check(
        "TERMINAL::POST_ACQUISITION_STRUCTURAL_DELIVERY_FINAL_RECEIPT_CHAIN",
        post_chain_ok,
        post_chain,
        "acquisition-complete.v2 -> structural-v3 PASS -> delivery-v2.2 build -> delivery-v2.2 verify -> qualification-complete.v2 no-analysis freeze",
        domain="terminal-chain",
        reason="Execution contract v3.1 post-acquisition terminal chain is incomplete or reordered.",
    )

    retained_after: dict[str, list[dict[str, Any]]] = {}
    for label, binding in RETAINED_ATTEMPTS.items():
        retained_after[label] = inventory(project_file(binding["relativePath"]))
    retention_comparison = {
        label: {
            "beforeFileCount": len(retained_before[label]),
            "afterFileCount": len(retained_after[label]),
            "beforeDigestSha256": inventory_digest(retained_before[label]),
            "afterDigestSha256": inventory_digest(retained_after[label]),
            "identical": retained_before[label] == retained_after[label],
        }
        for label in RETAINED_ATTEMPTS
    }
    check(
        "RETENTION::ALL_THREE_PRIOR_ATTEMPTS_BYTE_AND_ATTRIBUTE_IDENTICAL",
        all(item["identical"] for item in retention_comparison.values()),
        retention_comparison,
        "all three retained attempt inventories, hashes, lengths, paths, and read-only attributes are identical before and after",
        domain="retention",
        reason="A retained readiness or terminal-chain attempt changed during the recheck.",
    )

    post_system = system_probe()
    post_roots = root_states()
    check(
        "BOUNDARY::UNITY_ABSENT_AT_END",
        post_system.get("unityProcessCount") == 0,
        {"unityProcessCount": post_system.get("unityProcessCount")},
        {"unityProcessCount": 0},
        domain="authorization-boundary",
        reason="Unity was active at the end of the no-Unity readiness recheck.",
    )
    check(
        "BOUNDARY::PROHIBITED_ROOTS_ABSENT_AT_END",
        not any(post_roots.values()),
        post_roots,
        {relative: False for relative in RESERVED_ROOTS},
        domain="authorization-boundary",
        reason="The readiness recheck created a measured, delivery, or formal root.",
    )

    passed = all(item["passed"] for item in checks)
    completed = utc_now()

    authorization_receipt = {
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-authorization-receipt-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "status": "AUTHORIZED_READ_ONLY_NO_UNITY_READINESS_RECHECK",
        "authorizedAtUtc": started,
        "authorizationSource": "user-selected response annotation",
        "userAuthorizationTextExact": USER_AUTHORIZATION_TEXT,
        "allowed": [
            "create and freeze this independent attempt-003 evidence directory",
            "read and hash the explicitly bound frozen source, contract, status, planning, runtime, identity and prior-attempt evidence",
            "parse Python/PowerShell/JSON/JSONL statically without executing the qualification supervisor or algorithm code",
            "inspect read-only host/process/storage metadata",
            "freeze a terminal readiness PASS receipt and Status v29 only if every check passes",
        ],
        "prohibited": [
            "starting Unity",
            "creating qualification measured, delivery, or formal roots",
            "running any planner or algorithm lane",
            "producing qualification or formal observations",
            "formal collection or formal analysis",
            "cross-algorithm effects, ranking, weighting, or winner adjudication",
            "opening or disclosing the sealed identity mapping",
            "deleting, modifying, or reclassifying prior attempts",
        ],
    }
    authorization_path = write_json_exclusive(ATTEMPT_ROOT / "authorization-receipt.v1.json", authorization_receipt)

    stage_contract = {
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-stage-contract-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "status": "FROZEN_READ_ONLY_NO_UNITY_RECHECK_CONTRACT",
        "createdAtUtc": started,
        "authoritativeInputStatus": {"relativePath": EXPECTED_HASHES["statusV28"][0], "sha256": EXPECTED_HASHES["statusV28"][1]},
        "retainedAttempts": RETAINED_ATTEMPTS,
        "auditMode": "READ_ONLY_STATIC_AND_EXISTING_OFFLINE_KNOWN_ANSWER",
        "passRule": "Every recorded check must pass; otherwise freeze failure evidence and do not create Status v29.",
        "claimBoundary": "PASS establishes prospective execution readiness of the frozen chain only. It does not assert that any of the 1,147 qualification processes or any qualification observation has run.",
        "mutationBoundary": [str(ATTEMPT_REL), str(STATUS_29_REL) + " on PASS only"],
        "scientificBoundary": {
            "unityInvocationCount": 0,
            "plannerInvocationCount": 0,
            "algorithmLaneExecutionCount": 0,
            "qualificationObservationCount": 0,
            "formalObservationCount": 0,
            "formalAnalysisPerformed": False,
            "rankingOrWinnerComputed": False,
            "sealedIdentityMappingOpened": False,
        },
    }
    stage_path = write_json_exclusive(ATTEMPT_ROOT / "stage-contract.v1.json", stage_contract)

    audit = {
        "schema": "gate14re-me-qualification-execution-readiness-recheck-audit-v3",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "designId": "gate14re-me-load-qualification-planning-v2",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "startedAtUtc": started,
        "completedAtUtc": completed,
        "mode": "READ_ONLY_NO_UNITY_STATIC_AND_EXISTING_OFFLINE_EVIDENCE",
        "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V3" if passed else "FAIL_CLOSED_QUALIFICATION_EXECUTION_READINESS_RECHECK_V3",
        "passed": passed,
        "summary": {
            "totalChecks": len(checks),
            "passedChecks": sum(1 for item in checks if item["passed"]),
            "failedChecks": sum(1 for item in checks if not item["passed"]),
        },
        "checks": checks,
        "hardStopReasons": hard_stop_reasons,
        "retainedEvidenceInventories": retention_comparison,
        "hostProbeStart": pre_system,
        "hostProbeEnd": post_system,
        "scientificBoundary": {
            "unityInvocationCount": 0,
            "plannerInvocationCount": 0,
            "algorithmLaneExecutionCount": 0,
            "qualificationMeasuredRootCreated": False,
            "deliveryRootCreated": False,
            "qualificationObservationCount": 0,
            "formalObservationCount": 0,
            "formalCollectionPerformed": False,
            "formalAnalysisPerformed": False,
            "crossAlgorithmEffectsComputed": False,
            "rankingOrWinnerComputed": False,
            "sealedIdentityMappingOpened": False,
        },
    }
    audit_path = write_json_exclusive(ATTEMPT_ROOT / "readiness-recheck-audit.v3.json", audit)

    status_path: pathlib.Path | None = None
    adoption_path: pathlib.Path | None = None
    if passed:
        terminal_receipt = {
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "designId": "gate14re-me-load-qualification-planning-v2",
            "authorizationId": AUTHORIZATION_ID,
            "attemptId": ATTEMPT_ID,
            "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V3_FROZEN_EXECUTION_UNAUTHORIZED",
            "passed": True,
            "terminal": True,
            "completedAtUtc": completed,
            "readinessAudit": {"relativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(), "sha256": sha256_file(audit_path), "totalChecks": len(checks), "passedChecks": len(checks), "failedChecks": 0},
            "resolvedRetainedAttempt002Blockers": [
                "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT",
                "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE",
            ],
            "verifiedProspectiveClosure": {
                "qualificationSuperblocks": 162,
                "algorithmLaneProcesses": 972,
                "oracleProcesses": 162,
                "emptyBoundaryProcesses": 12,
                "instrumentProcesses": 1,
                "totalSerialFreshUnityProcesses": 1147,
                "eventGroupRows": 23328,
                "laneD3WindowRows": 24300,
                "emptyBoundaryD3WindowRows": 12000,
                "instrumentD3WindowRows": 1,
                "processResourceRows": 25272,
                "persistentStateMeasurementPointsPerLane": 26,
                "acceptedSuperblockReceipts": 162,
                "processLedgerRows": 1147,
                "processIdentityReceipts": 1147,
                "supervisorFinalProcessOrdinal": 1147,
            },
            "verificationMeaning": "Static frozen-chain and existing offline known-answer readiness only; no qualification process ledger or observation exists yet.",
            "scientificBoundary": audit["scientificBoundary"],
            "activation": {
                "qualificationExecutionAuthorized": False,
                "unityInvocationAuthorized": False,
                "qualificationMeasuredRootCreationAuthorized": False,
                "deliveryRootCreationAuthorized": False,
                "formalCollectionAuthorized": False,
                "formalAnalysisAuthorized": False,
                "rankingAuthorized": False,
                "winnerAdjudicationAuthorized": False,
                "separateExecutionAuthorizationRequired": True,
            },
        }
        terminal_path = write_json_exclusive(ATTEMPT_ROOT / "terminal-readiness-receipt.v1.json", terminal_receipt)

        status29 = {
            "schema": "gate14re-me-status-v29",
            "studyId": "Gate14Re-ME",
            "status": "QUALIFICATION_EXECUTION_READINESS_RECHECK_PASS_EXECUTION_AUTHORIZATION_PENDING",
            "version": 29,
            "updatedAtUtc": completed,
            "previousVersionedStatus": {"relativePath": EXPECTED_HASHES["statusV28"][0], "sha256": EXPECTED_HASHES["statusV28"][1], "retained": True, "reclassified": False},
            "readinessRecheckAttempt003": {
                "authorizationId": AUTHORIZATION_ID,
                "passed": True,
                "terminalReceiptRelativePath": terminal_path.relative_to(PROJECT_ROOT).as_posix(),
                "terminalReceiptSha256": sha256_file(terminal_path),
                "auditRelativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(),
                "auditSha256": sha256_file(audit_path),
                "totalChecks": len(checks),
                "passedChecks": len(checks),
                "failedChecks": 0,
                "verificationMode": "READ_ONLY_NO_UNITY_STATIC_AND_EXISTING_OFFLINE_EVIDENCE",
            },
            "verifiedFrozenBindings": {
                "outputSchemaV3Sha256": EXPECTED_HASHES["outputSchemaV3"][1],
                "structuralV31Sha256": EXPECTED_HASHES["structuralV31"][1],
                "deliveryV22Sha256": EXPECTED_HASHES["deliveryV22"][1],
                "supervisorV3Sha256": EXPECTED_HASHES["supervisorV3"][1],
                "executionContractV31Sha256": EXPECTED_HASHES["executionContractV31"][1],
                "implementationManifestV31Sha256": EXPECTED_HASHES["implementationManifestV31"][1],
                "runnerV2Sha256": EXPECTED_HASHES["runnerV2"][1],
                "compiledEditorAssemblySha256": EXPECTED_HASHES["editorAssembly"][1],
                "compiledRuntimeAssemblySha256": EXPECTED_HASHES["runtimeAssembly"][1],
                "inputSchemaV2Sha256": EXPECTED_HASHES["inputSchemaV2"][1],
                "planningSchemaBindingV2Sha256": EXPECTED_HASHES["planningSchemaBindingV2"][1],
                "planningAssetsManifestSha256": EXPECTED_HASHES["planningAssetsManifest"][1],
                "scheduleSha256": EXPECTED_HASHES["schedule"][1],
                "sealedIdentitySha256": EXPECTED_HASHES["sealedIdentity"][1],
                "d3V31Sha256": EXPECTED_HASHES["d3V31"][1],
                "typedParquetRuntimeManifestSha256": EXPECTED_HASHES["typedParquetRuntime"][1],
                "trustedUnityIdentityRuleSha256": EXPECTED_HASHES["trustedIdentityRule"][1],
                "timestampComparatorSha256": EXPECTED_HASHES["timestampComparator"][1],
            },
            "prospectiveQualificationClosure": terminal_receipt["verifiedProspectiveClosure"],
            "scientificBoundary": audit["scientificBoundary"],
            "authorizationState": terminal_receipt["activation"],
            "nextRequiredAction": "Obtain a separate exact-hash qualification execution authorization before creating the qualification measured/delivery roots or starting Unity. Formal collection, formal analysis, cross-algorithm effects, ranking and winner adjudication remain separately unauthorized.",
        }
        status_path = write_json_exclusive(project_file(STATUS_29_REL), status29)
        adoption = {
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-status-adoption-receipt-v1",
            "studyId": "Gate14Re-ME",
            "authorizationId": AUTHORIZATION_ID,
            "status": "PASS_STATUS_V29_ADOPTED_EXECUTION_AUTHORIZATION_PENDING",
            "terminalReceiptRelativePath": terminal_path.relative_to(PROJECT_ROOT).as_posix(),
            "terminalReceiptSha256": sha256_file(terminal_path),
            "readinessAuditRelativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(),
            "readinessAuditSha256": sha256_file(audit_path),
            "statusRelativePath": status_path.relative_to(PROJECT_ROOT).as_posix(),
            "statusSha256": sha256_file(status_path),
            "qualificationExecutionAuthorized": False,
            "formalCollectionAnalysisRankingOrWinnerAuthorized": False,
            "adoptedAtUtc": completed,
        }
        adoption_path = write_json_exclusive(ATTEMPT_ROOT / "status-adoption-receipt.v1.json", adoption)
    else:
        failure = {
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-failure-receipt-v1",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "designId": "gate14re-me-load-qualification-planning-v2",
            "authorizationId": AUTHORIZATION_ID,
            "attemptId": ATTEMPT_ID,
            "status": "FAILED_CLOSED_QUALIFICATION_EXECUTION_READINESS_RECHECK_V3",
            "passed": False,
            "terminal": True,
            "completedAtUtc": completed,
            "readinessAudit": {"relativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(), "sha256": sha256_file(audit_path), **audit["summary"]},
            "hardStopReasons": hard_stop_reasons,
            "disposition": {
                "qualificationExecutionAuthorized": False,
                "measuredOrDeliveryRootCreationAllowed": False,
                "unityRestartOrRetryAllowed": False,
                "formalCollectionAnalysisRankingOrWinnerAllowed": False,
                "statusV29Created": False,
            },
        }
        write_json_exclusive(ATTEMPT_ROOT / "failure-receipt.v1.json", failure)

    manifest_items: list[dict[str, Any]] = []
    for path in sorted((p for p in ATTEMPT_ROOT.iterdir() if p.is_file() and p.name != "freeze-manifest.v1.json"), key=lambda p: p.name.lower()):
        manifest_items.append({"role": "attempt-evidence", "relativePath": path.relative_to(PROJECT_ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    if status_path is not None:
        manifest_items.append({"role": "adopted-status-v29", "relativePath": status_path.relative_to(PROJECT_ROOT).as_posix(), "bytes": status_path.stat().st_size, "sha256": sha256_file(status_path)})
    freeze_manifest = {
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-freeze-manifest-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "status": "FROZEN_TERMINAL_PASS_READINESS_RECHECK_EVIDENCE" if passed else "FROZEN_FAILED_CLOSED_READINESS_RECHECK_EVIDENCE",
        "createdAtUtc": utc_now(),
        "artifactCount": len(manifest_items),
        "artifacts": manifest_items,
        "manifestExcludesItselfToAvoidCircularHash": True,
        "retainedAttemptsIdentical": all(item["identical"] for item in retention_comparison.values()),
        "unityInvocationCount": 0,
        "prohibitedRootsCreated": False,
        "qualificationObservations": 0,
        "formalObservations": 0,
        "analysisRankingOrWinnerComputed": False,
    }
    manifest_path = write_json_exclusive(ATTEMPT_ROOT / "freeze-manifest.v1.json", freeze_manifest)

    freeze_targets = [path for path in ATTEMPT_ROOT.iterdir() if path.is_file()]
    if status_path is not None:
        freeze_targets.append(status_path)
    for path in freeze_targets:
        os.chmod(path, stat.S_IREAD)
    if not all(is_read_only(path) for path in freeze_targets):
        raise RuntimeError("read-only freeze did not apply to every attempt/status artifact")

    result = {
        "status": "PASS" if passed else "FAIL_CLOSED",
        "checks": len(checks),
        "passedChecks": sum(1 for item in checks if item["passed"]),
        "failedChecks": sum(1 for item in checks if not item["passed"]),
        "auditSha256": sha256_file(audit_path),
        "freezeManifestSha256": sha256_file(manifest_path),
        "statusV29Sha256": sha256_file(status_path) if status_path is not None else None,
        "unityInvocationCount": 0,
        "prohibitedRootsCreated": False,
    }
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0 if passed else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        emergency_path = ATTEMPT_ROOT / "emergency-failure-receipt.v1.json"
        if not emergency_path.exists():
            try:
                write_json_exclusive(
                    emergency_path,
                    {
                        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-003-emergency-failure-v1",
                        "studyId": "Gate14Re-ME",
                        "authorizationId": AUTHORIZATION_ID,
                        "status": "FAILED_CLOSED_AUDIT_TOOL_EXCEPTION",
                        "completedAtUtc": utc_now(),
                        "exceptionType": type(exc).__name__,
                        "exception": str(exc),
                        "qualificationExecutionAuthorized": False,
                    },
                )
            except Exception:
                pass
        print(json.dumps({"status": "FAILED_CLOSED_AUDIT_TOOL_EXCEPTION", "exceptionType": type(exc).__name__, "exception": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(3)
