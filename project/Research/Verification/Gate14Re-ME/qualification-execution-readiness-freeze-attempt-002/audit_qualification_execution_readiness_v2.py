#!/usr/bin/env python3
"""Gate14Re-ME qualification execution-readiness audit, attempt-002.

This is an offline, read-only audit of already-frozen implementation and
evidence.  Its only writes are evidence files beneath this attempt directory.
It never starts Unity, creates a measured/delivery root, invokes a planner or
algorithm lane, or computes scientific effects, ranks, or winners.
"""

from __future__ import annotations

import ast
import collections
import datetime as dt
import hashlib
import json
import os
import pathlib
import stat
import subprocess
import sys
from typing import Any, Iterable


PROJECT_ROOT = pathlib.Path(r"H:\DDM_Final_Project").resolve()
ATTEMPT_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-readiness-freeze-attempt-002"
)
ATTEMPT_ROOT = (PROJECT_ROOT / ATTEMPT_REL).resolve()
SCRIPT_PATH = pathlib.Path(__file__).resolve()

POWERSHELL = pathlib.Path(
    r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
)
PYTHON = pathlib.Path(
    r"C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)
UNITY = pathlib.Path(r"H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe")

READINESS_001_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-readiness-freeze-attempt-001"
)
REPAIR_001_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-binding-supervisor-v2-repair-attempt-001"
)
REPAIR_002_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-binding-supervisor-v2-repair-attempt-002"
)

MEASURED_REL = pathlib.PurePosixPath(
    "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001"
)
DELIVERY_REL = pathlib.PurePosixPath(
    "Research/Exports/Gate14Re-ME/load-qualification/attempt-001"
)
FORMAL_REL = pathlib.PurePosixPath("Research/FormalRuns/Gate14Re-ME")

SUPERVISOR_REL = pathlib.PurePosixPath(
    "Research/Gate14Re-ME/Execution/v2/Run-Gate14ReMELoadQualification.v2.ps1"
)
CONTRACT_REL = pathlib.PurePosixPath(
    "Research/Gate14Re-ME/Execution/v2/load-qualification-execution-contract.v2.json"
)
MANIFEST_REL = pathlib.PurePosixPath(
    "Research/Gate14Re-ME/Execution/v2/load-qualification-current-implementation-manifest.v2.json"
)
RUNNER_REL = pathlib.PurePosixPath(
    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs"
)
COMPILE_RECEIPT_REL = REPAIR_002_REL / "compile-identity-receipt.v1.json"
REPAIR_TERMINAL_REL = REPAIR_002_REL / "terminal-receipt.v1.json"
REPAIR_FREEZE_REL = REPAIR_002_REL / "source-and-evidence-freeze-manifest.v1.json"

EXPECTED_CORE_HASHES: dict[str, str] = {
    SUPERVISOR_REL.as_posix(): "a7e997f7b9d1c48753294b437566d40cf448106ef140e16a2780ce79b7059771",
    CONTRACT_REL.as_posix(): "bee4b5103cc83c1528322faa98c7227cf6e94a481c4fa1059be93ffa5844ce69",
    MANIFEST_REL.as_posix(): "53d1b7bd1fc12c6c13514c5180b4f59267c13bf90ea6809d1448038446af144f",
    RUNNER_REL.as_posix(): "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73",
    COMPILE_RECEIPT_REL.as_posix(): "07118a3b4be7e9cd0b044d073426d8db24ba116498d548c3bbfa42df2cdf9937",
    REPAIR_TERMINAL_REL.as_posix(): "e23e195906afe99b68a3734ea1561d7ac3df334764058f386cbc880df646de4c",
    REPAIR_FREEZE_REL.as_posix(): "3eae3dcde12d5230731445d5ff9ff31216329364624a79d2dcb7f3fdcf8b40e7",
    (READINESS_001_REL / "failure-receipt.v1.json").as_posix(): "feea3650801239a1e92ced9031b137f9c22f7e9a9a483d05a6456353f1827b57",
    (READINESS_001_REL / "source-and-evidence-freeze-manifest.v1.json").as_posix(): "d1d9f348fa6209f41e68d70d0522ddf2d89169ca552578ef2b5ab91ba5de60df",
    (REPAIR_001_REL / "failure-receipt.v1.json").as_posix(): "e5842af9ec3a6205aa9e9014ad1fddd6fab2f99696995577575c4ae4607d4c3e",
    (REPAIR_001_REL / "source-and-evidence-freeze-manifest.v1.json").as_posix(): "69dd2ba7f58d51b3de7b65cac74285661d4bfd63742c59778ec938a275bbde0a",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json": "7e0cbe77cb8bb8f84642856c6356d318f708e168b52a92e6e348cdf948169aca",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/terminal-receipt.v1.json": "7ca501b6c7f40dde2958aac6c9cd37984ff788a55dadf1df494a9e2a0e4f05f3",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl": "328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json": "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json": "1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json": "abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7",
    "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json": "c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312",
    "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json": "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb",
    "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json": "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json": "bef0f0c143f325eb7b3ad9e5401cc89bc7d6ff3938287a9b049e985aac04e887",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-schedule-schema.v1.json": "8a96a5a53d22617ef90134ac1a57e3b7115e5ea7ce03a6739c632fd52119f8a5",
    "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json": "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71",
    "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json": "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v2.py": "daa1fc48077cc0cb8c62221956355a35c74e8b946660b683f7178e2072e9bc0e",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2.py": "5e9f8d8c3403321fb9e1b2b3f67fef00a963bf85f25c66d98bc2c41971434ec4",
    "Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json": "1e3a70d6be62554027ca639b6a3c7d896fd232906d627962d8c296e9e884c8dd",
    "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json": "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06",
    "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/terminal-receipt.v1.json": "ab522787fba973f3441e4d32a2de97244a8b44540f74017d4d15d000af1253db",
    "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1": "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27",
    "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/known-answer-receipt.v1.json": "ad64fb2bce32f2e6206f6f1f80baa30f273be212075603ee631f61b560cc1b63",
    "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/freeze-receipt.v1.json": "cd3fee2954eb4f0c0e1fe126c16342cbee3de34bac1a3b7fbec747cd22c3b79b",
    "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/validation-receipt.v1.json": "404970e8026f37b1d527b42b127ed657e5bd1a0ac757897903221c80daee174c",
    "Library/ScriptAssemblies/Assembly-CSharp-Editor.dll": "abef0c3232d02818e60a5603600fbc8899dba2fbe383e73b255a04eab01b5e88",
    "Library/ScriptAssemblies/Assembly-CSharp.dll": "c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1",
}

EXPECTED_RUNTIME_HASHES = {
    str(UNITY): "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf",
    str(PYTHON): "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1",
    str(POWERSHELL): "8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e",
}

EXPECTED_ALGORITHMS = {"A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"}
EXPECTED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
IDENTITY_SHA256 = "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_json_exclusive(name: str, value: Any) -> pathlib.Path:
    path = ATTEMPT_ROOT / name
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return path


def load_json(relative: str | pathlib.PurePosixPath) -> dict[str, Any]:
    path = PROJECT_ROOT / pathlib.PurePosixPath(str(relative))
    with path.open("r", encoding="utf-8-sig") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {relative}")
    return value


def read_text(relative: str | pathlib.PurePosixPath) -> str:
    return (PROJECT_ROOT / pathlib.PurePosixPath(str(relative))).read_text(
        encoding="utf-8-sig"
    )


def project_file(relative: str) -> pathlib.Path:
    path = (PROJECT_ROOT / pathlib.PurePosixPath(relative)).resolve()
    path.relative_to(PROJECT_ROOT)
    if path.relative_to(PROJECT_ROOT).as_posix() != relative:
        raise ValueError(f"non-canonical project path: {relative}")
    return path


def is_read_only(path: pathlib.Path) -> bool:
    attributes = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attributes & getattr(stat, "FILE_ATTRIBUTE_READONLY", 1))


def inventory(root: pathlib.Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: str(p).lower()):
        result.append(
            {
                "relativePath": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "readOnly": is_read_only(path),
            }
        )
    return result


def inventory_digest(items: Iterable[dict[str, Any]]) -> str:
    return hashlib.sha256(canonical_json(list(items)).encode("utf-8")).hexdigest()


def system_probe() -> dict[str, Any]:
    command = r"""
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$os=Get-CimInstance Win32_OperatingSystem
$cs=Get-CimInstance Win32_ComputerSystem
$board=Get-CimInstance Win32_BaseBoard
$drive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='H:'"
[ordered]@{
 unityProcesses=@(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | ForEach-Object { [ordered]@{processId=$_.ProcessId;creationDate=[string]$_.CreationDate;executablePath=$_.ExecutablePath;commandLine=$_.CommandLine} })
 totalVisibleMemoryBytes=[int64]$os.TotalVisibleMemorySize*1024
 logicalProcessors=[int]$cs.NumberOfLogicalProcessors
 baseBoardManufacturer=[string]$board.Manufacturer
 baseBoardProduct=[string]$board.Product
 operatingSystemVersion=[string]$os.Version
 driveHTotalBytes=[int64]$drive.Size
 driveHFreeBytes=[int64]$drive.FreeSpace
} | ConvertTo-Json -Depth 8 -Compress
"""
    completed = subprocess.run(
        [str(POWERSHELL), "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        encoding="utf-8",
        errors="strict",
    )
    return json.loads(completed.stdout)


def parse_instant(value: Any) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ValueError("timestamp is missing")
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        raise ValueError("timestamp lacks an offset")
    return parsed.astimezone(dt.timezone.utc)


def declared_file_audit(entries: list[dict[str, Any]]) -> dict[str, Any]:
    mismatches: list[dict[str, Any]] = []
    paths: list[str] = []
    total_bytes = 0
    for item in entries:
        relative = item.get("relativePath")
        expected_hash = item.get("sha256")
        expected_bytes = item.get("bytes", item.get("lengthBytes"))
        if not isinstance(relative, str):
            mismatches.append({"relativePath": relative, "reason": "missing relativePath"})
            continue
        paths.append(relative)
        try:
            path = project_file(relative)
        except Exception as exc:
            mismatches.append({"relativePath": relative, "reason": str(exc)})
            continue
        if not path.is_file():
            mismatches.append({"relativePath": relative, "reason": "missing"})
            continue
        actual_bytes = path.stat().st_size
        total_bytes += actual_bytes
        actual_hash = sha256_file(path)
        if actual_bytes != expected_bytes or actual_hash != expected_hash:
            mismatches.append(
                {
                    "relativePath": relative,
                    "expectedBytes": expected_bytes,
                    "actualBytes": actual_bytes,
                    "expectedSha256": expected_hash,
                    "actualSha256": actual_hash,
                }
            )
    return {
        "declaredFiles": len(entries),
        "uniquePaths": len(set(paths)),
        "allPathsUnique": len(set(paths)) == len(paths),
        "totalBytesObserved": total_bytes,
        "mismatchCount": len(mismatches),
        "mismatches": mismatches[:25],
    }


def main() -> int:
    started = utc_now()
    checks: list[dict[str, Any]] = []
    hard_stops: list[dict[str, Any]] = []

    def check(
        check_id: str,
        passed: bool,
        observed: Any,
        expected: Any,
        *,
        domain: str,
        hard_stop_reason: str | None = None,
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
        if not passed and hard_stop_reason:
            hard_stops.append(
                {
                    "blockerId": check_id,
                    "reason": hard_stop_reason,
                    "disposition": "FAIL_CLOSED_NO_QUALIFICATION_EXECUTION",
                }
            )

    initial_files = sorted(
        p.name for p in ATTEMPT_ROOT.iterdir() if p.is_file()
    )
    if initial_files != [SCRIPT_PATH.name]:
        raise RuntimeError(f"attempt root was not pristine: {initial_files}")

    authorization = {
        "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-authorization-receipt-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": "gate14re-me-qualification-execution-readiness-freeze-attempt-002",
        "attemptId": "qualification-execution-readiness-freeze-attempt-002",
        "status": "AUTHORIZED_READ_ONLY_NO_UNITY_EXECUTION_READINESS_AUDIT",
        "authorizedAtUtc": started,
        "userAuthorizationTextExact": "单独授权 Gate14Re‑ME qualification execution readiness freeze attempt‑002：完整保留 qualification execution readiness freeze attempt‑001、execution binding supervisor v2 repair attempt‑001 和 attempt‑002 的全部状态与证据，不删除、不修改、不改判；仅允许以只读、无 Unity 的方式核对已冻结 supervisor v2、execution contract v2、current implementation manifest v2、RunnerV2、receipt v2、input schema v2、instrument contract v3、output schema v2、qualified D3‑v3.1、planning assets、sealed identity、typed‑Parquet runtime、trusted Unity identity rule、attempt‑007 timestamp comparator、structural‑v2、delivery‑v2、完整逐条数据交付合同和本次 compile identity receipt，验证所有路径、哈希、cardinality、六算法 Williams 顺序、零 replacement fail‑stop、运行时预算、预期 1147 个串行 fresh Unity processes 及终局 structural/delivery 链。只有全部检查通过时才允许冻结独立 terminal readiness PASS receipt；不得启动 Unity，不得创建 measured root 或 delivery root，不得运行 planner、算法 lane、资格或正式采集、正式分析、排名或赢家裁决。失败时保留全部证据并 fail closed。",
        "authorizedWrites": [ATTEMPT_REL.as_posix()],
        "unityInvocationMaximum": 0,
        "measuredOrDeliveryRootCreationAuthorized": False,
        "qualificationExecutionAuthorized": False,
        "formalCollectionOrAnalysisAuthorized": False,
        "rankingOrWinnerAdjudicationAuthorized": False,
    }
    write_json_exclusive("authorization-receipt.v1.json", authorization)

    stage_contract = {
        "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-stage-contract-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": authorization["authorizationId"],
        "attemptId": authorization["attemptId"],
        "mode": "READ_ONLY_OFFLINE_NO_UNITY_EXECUTION_READINESS_AUDIT",
        "passRule": "Every check must pass. A PASS terminal receipt is forbidden if any path, hash, cardinality, schedule, identity, budget, serial-process, zero-replacement, or terminal structural/delivery-chain check fails.",
        "retainedEvidenceRoots": [
            READINESS_001_REL.as_posix(),
            REPAIR_001_REL.as_posix(),
            REPAIR_002_REL.as_posix(),
        ],
        "expectedProcessFormula": {
            "instrumentSelfTest": 1,
            "oracle": 162,
            "emptyBoundary": 12,
            "algorithmLane": 972,
            "total": 1147,
            "maximumConcurrentUnityProcesses": 1,
        },
        "prohibitions": {
            "unityInvocations": 0,
            "measuredRootCreations": 0,
            "deliveryRootCreations": 0,
            "plannerInvocations": 0,
            "algorithmLaneExecutions": 0,
            "qualificationOrFormalObservations": 0,
            "analysisRankingOrWinner": False,
        },
        "failureDisposition": "Preserve evidence and fail closed without repair, retry, replacement, root creation, Unity launch, or execution authorization.",
    }
    write_json_exclusive("stage-contract.v1.json", stage_contract)

    retained_roots = {
        "readinessAttempt001": PROJECT_ROOT / READINESS_001_REL,
        "repairAttempt001": PROJECT_ROOT / REPAIR_001_REL,
        "repairAttempt002": PROJECT_ROOT / REPAIR_002_REL,
    }
    before_inventories = {name: inventory(path) for name, path in retained_roots.items()}
    before_digests = {name: inventory_digest(items) for name, items in before_inventories.items()}

    pre_system = system_probe()
    check(
        "BOUNDARY::UNITY_ABSENT_AT_START",
        len(pre_system.get("unityProcesses", [])) == 0,
        len(pre_system.get("unityProcesses", [])),
        0,
        domain="boundary",
        hard_stop_reason="Unity.exe was active at the beginning of the no-Unity audit.",
    )
    prohibited_roots = [MEASURED_REL, DELIVERY_REL, FORMAL_REL]
    existing_prohibited = [rel.as_posix() for rel in prohibited_roots if (PROJECT_ROOT / rel).exists()]
    check(
        "BOUNDARY::PROHIBITED_ROOTS_ABSENT_AT_START",
        not existing_prohibited,
        existing_prohibited,
        [],
        domain="boundary",
        hard_stop_reason="A prohibited measured, delivery, or formal root already exists.",
    )

    expected_counts = {"readinessAttempt001": 7, "repairAttempt001": 8, "repairAttempt002": 17}
    for name, items in before_inventories.items():
        check(
            f"RETENTION::{name}::FILE_COUNT",
            len(items) == expected_counts[name],
            len(items),
            expected_counts[name],
            domain="retained-evidence",
            hard_stop_reason=f"Retained evidence inventory changed for {name}.",
        )
        non_read_only = [item["relativePath"] for item in items if not item["readOnly"]]
        check(
            f"RETENTION::{name}::READ_ONLY",
            not non_read_only,
            non_read_only,
            [],
            domain="retained-evidence",
            hard_stop_reason=f"Retained evidence is no longer read-only for {name}.",
        )

    core_hash_mismatches: list[dict[str, Any]] = []
    for relative, expected in EXPECTED_CORE_HASHES.items():
        path = PROJECT_ROOT / pathlib.PurePosixPath(relative)
        actual = sha256_file(path) if path.is_file() else None
        if actual != expected:
            core_hash_mismatches.append(
                {"relativePath": relative, "expectedSha256": expected, "actualSha256": actual}
            )
    check(
        "HASHES::ALL_CORE_BINDINGS",
        not core_hash_mismatches,
        core_hash_mismatches,
        [],
        domain="hashes",
        hard_stop_reason="One or more explicitly frozen core artifacts drifted.",
    )

    runtime_mismatches: list[dict[str, Any]] = []
    for path_text, expected in EXPECTED_RUNTIME_HASHES.items():
        path = pathlib.Path(path_text)
        actual = sha256_file(path) if path.is_file() else None
        if actual != expected:
            runtime_mismatches.append(
                {"path": path_text.replace("\\", "/"), "expectedSha256": expected, "actualSha256": actual}
            )
    check(
        "HASHES::FROZEN_EXECUTABLES",
        not runtime_mismatches,
        runtime_mismatches,
        [],
        domain="hashes",
        hard_stop_reason="A frozen Unity, Python, or PowerShell executable drifted.",
    )

    contract = load_json(CONTRACT_REL)
    manifest = load_json(MANIFEST_REL)
    check(
        "CONTRACT::HEADER_AND_INERT_STATE",
        contract.get("schema") == "gate14re-me-load-qualification-execution-contract-v2"
        and contract.get("status") == "FROZEN_EXECUTION_BINDING_V2_QUALIFICATION_EXECUTION_UNAUTHORIZED"
        and "later separate exact-hash execution authorization" in str(contract.get("activationRule", "")),
        {"schema": contract.get("schema"), "status": contract.get("status"), "activationRule": contract.get("activationRule")},
        "frozen v2 and execution unauthorized pending a separate exact-hash authorization",
        domain="execution-contract",
        hard_stop_reason="Execution contract identity or inert authorization state is invalid.",
    )
    check(
        "MANIFEST::V2_AUTHORITATIVE_STATE_WITH_RUNNERV2_COMPATIBILITY",
        manifest.get("schema") == "gate14re-me-qualification-implementation-manifest-v1"
        and manifest.get("status") == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED"
        and manifest.get("manifestGeneration") == 2
        and manifest.get("manifestSchemaV2") == "gate14re-me-qualification-current-implementation-manifest-v2"
        and manifest.get("executionReadinessStatus") == "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_AND_ALGORITHM_FREE_IDENTITY_PROBED"
        and manifest.get("legacyRunnerCompatibility", {}).get("legacyStatusIsNotTheAuthoritativeExecutionReadinessState") is True,
        {
            "compatibilitySchema": manifest.get("schema"),
            "compatibilityStatus": manifest.get("status"),
            "manifestGeneration": manifest.get("manifestGeneration"),
            "authoritativeState": manifest.get("executionReadinessStatus"),
        },
        "RunnerV2 compatibility fields plus authoritative compiled generation-2 state",
        domain="implementation-manifest",
        hard_stop_reason="Current implementation manifest v2 compatibility or authoritative state is invalid.",
    )

    manifest_entries = manifest.get("artifacts", [])
    manifest_audit = declared_file_audit(manifest_entries if isinstance(manifest_entries, list) else [])
    check(
        "MANIFEST::FORTY_EIGHT_ARTIFACTS_EXACT",
        isinstance(manifest_entries, list)
        and len(manifest_entries) == 48
        and manifest_audit["allPathsUnique"]
        and manifest_audit["mismatchCount"] == 0,
        manifest_audit,
        {"declaredFiles": 48, "allPathsUnique": True, "mismatchCount": 0},
        domain="implementation-manifest",
        hard_stop_reason="Current implementation manifest does not resolve to 48 unique exact frozen artifacts.",
    )
    manifest_index = {
        item.get("relativePath"): item.get("sha256")
        for item in manifest_entries
        if isinstance(item, dict)
    }

    frozen_bindings = contract.get("frozenBindings", {})
    binding_mismatches: list[dict[str, Any]] = []
    for name, binding in frozen_bindings.items() if isinstance(frozen_bindings, dict) else []:
        if not isinstance(binding, dict):
            binding_mismatches.append({"name": name, "reason": "binding is not an object"})
            continue
        relative = binding.get("relativePath")
        expected_hash = binding.get("sha256")
        try:
            path = project_file(relative)
            actual_hash = sha256_file(path)
        except Exception as exc:
            binding_mismatches.append({"name": name, "relativePath": relative, "reason": str(exc)})
            continue
        if actual_hash != expected_hash or manifest_index.get(relative) != expected_hash:
            binding_mismatches.append(
                {
                    "name": name,
                    "relativePath": relative,
                    "contractSha256": expected_hash,
                    "actualSha256": actual_hash,
                    "manifestSha256": manifest_index.get(relative),
                }
            )
    check(
        "CONTRACT::FOURTEEN_FROZEN_BINDINGS_EXACT_AND_MANIFESTED",
        isinstance(frozen_bindings, dict)
        and len(frozen_bindings) == 14
        and len({v.get("relativePath") for v in frozen_bindings.values() if isinstance(v, dict)}) == 14
        and not binding_mismatches,
        {"bindings": len(frozen_bindings), "mismatches": binding_mismatches},
        {"bindings": 14, "uniquePaths": 14, "mismatches": []},
        domain="execution-contract",
        hard_stop_reason="Execution contract v2 frozen bindings are incomplete, non-unique, drifted, or absent from the current manifest.",
    )

    entry = contract.get("entryPoint", {})
    check(
        "EXECUTION::ENTRY_POINT_EXACT",
        entry.get("supervisorRelativePath") == SUPERVISOR_REL.as_posix()
        and entry.get("supervisorSha256") == EXPECTED_CORE_HASHES[SUPERVISOR_REL.as_posix()]
        and entry.get("runnerRelativePath") == RUNNER_REL.as_posix()
        and entry.get("runnerSha256") == EXPECTED_CORE_HASHES[RUNNER_REL.as_posix()]
        and entry.get("runnerExecuteMethod") == "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run"
        and entry.get("receiptGeneration") == 2,
        entry,
        "exact supervisor v2, RunnerV2, execute method, and receipt generation 2",
        domain="execution-binding",
        hard_stop_reason="Execution entry point does not exactly bind supervisor v2, RunnerV2, and receipt generation 2.",
    )

    compile_receipt = load_json(COMPILE_RECEIPT_REL)
    compile_ok = (
        compile_receipt.get("status") == "PASS_CURRENT_PROJECT_COMPILED_ALGORITHM_FREE_TRUSTED_IDENTITY"
        and compile_receipt.get("unityInvocationCount") == 1
        and compile_receipt.get("executeMethod") is None
        and compile_receipt.get("currentProjectCompiled") is True
        and compile_receipt.get("compilerFailureMarkersFound") == 0
        and compile_receipt.get("naturalExit") is True
        and compile_receipt.get("exitCode") == 0
        and compile_receipt.get("signalOrForcedTerminationSent") is False
        and compile_receipt.get("retryPerformed") is False
        and compile_receipt.get("measuredRootCreated") is False
        and compile_receipt.get("deliveryRootCreated") is False
        and compile_receipt.get("plannerInvocations") == 0
        and compile_receipt.get("algorithmLaneExecutions") == 0
        and compile_receipt.get("qualificationObservations") == 0
        and compile_receipt.get("formalObservations") == 0
        and compile_receipt.get("formalAnalysisPerformed") is False
        and compile_receipt.get("rankingOrWinnerComputed") is False
    )
    check(
        "COMPILE_IDENTITY::ALGORITHM_FREE_NATURAL_EXIT_PASS",
        compile_ok,
        {
            key: compile_receipt.get(key)
            for key in (
                "status", "unityInvocationCount", "executeMethod", "currentProjectCompiled",
                "compilerFailureMarkersFound", "naturalExit", "exitCode",
                "signalOrForcedTerminationSent", "retryPerformed", "measuredRootCreated",
                "deliveryRootCreated", "plannerInvocations", "algorithmLaneExecutions",
                "qualificationObservations", "formalObservations", "formalAnalysisPerformed",
                "rankingOrWinnerComputed",
            )
        },
        "one algorithm-free compile/identity invocation, natural exit zero, and no scientific execution",
        domain="compile-identity",
        hard_stop_reason="The frozen compile identity receipt does not prove an algorithm-free, natural-exit, no-observation compilation.",
    )

    assembly_results: list[dict[str, Any]] = []
    for field in ("editorAssembly", "runtimeAssembly"):
        item = compile_receipt.get(field, {})
        relative = item.get("relativePath")
        path = project_file(relative)
        assembly_results.append(
            {
                "role": field,
                "relativePath": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "matchesReceipt": path.stat().st_size == item.get("bytes")
                and sha256_file(path) == item.get("sha256"),
                "matchesManifest": manifest_index.get(relative) == item.get("sha256"),
            }
        )
    check(
        "COMPILE_IDENTITY::ASSEMBLIES_EXACT_AND_MANIFESTED",
        all(item["matchesReceipt"] and item["matchesManifest"] for item in assembly_results),
        assembly_results,
        "both compiled assemblies match receipt and manifest",
        domain="compile-identity",
        hard_stop_reason="A compiled Unity assembly does not match the compile receipt and current manifest.",
    )

    fingerprint_names = [
        "external-prelaunch-fingerprint.v1.json",
        "external-live-fingerprint.v1.json",
        "external-post-exit-fingerprint.v1.json",
    ]
    fingerprints = [load_json(REPAIR_002_REL / name) for name in fingerprint_names]
    fp_reference = fingerprints[0]
    stable_fields = [
        "path", "lengthBytes", "creationTimeUtc", "lastWriteTimeUtc", "attributes",
        "reparsePoint", "fileIdentity", "peIdentity", "authenticode", "fullFileHashes",
        "chunkSizeBytes", "chunkHashes",
    ]
    fingerprint_stable = all(
        all(item.get(field) == fp_reference.get(field) for field in stable_fields)
        for item in fingerprints[1:]
    )
    fingerprint_hashes_ok = all(
        item.get("independentHashMethodsAgree") is True
        and item.get("chunkSizeBytes") == 65536
        and {record.get("sha256") for record in item.get("fullFileHashes", [])}
        == {EXPECTED_RUNTIME_HASHES[str(UNITY)]}
        for item in fingerprints
    )
    timestamps_ok = all(
        parse_instant(item.get("creationTimeUtc")) == parse_instant(fp_reference.get("creationTimeUtc"))
        and parse_instant(item.get("lastWriteTimeUtc")) == parse_instant(fp_reference.get("lastWriteTimeUtc"))
        for item in fingerprints
    )
    check(
        "COMPILE_IDENTITY::THREE_PHASE_EXTERNAL_FINGERPRINT",
        fingerprint_stable and fingerprint_hashes_ok and timestamps_ok
        and [item.get("phase") for item in fingerprints]
        == ["EXTERNAL_PRELAUNCH", "EXTERNAL_LIVE_CONCURRENT", "EXTERNAL_POST_EXIT"],
        {
            "phases": [item.get("phase") for item in fingerprints],
            "stableAuthoritativeFields": fingerprint_stable,
            "independentHashesAgreeAndMatch": fingerprint_hashes_ok,
            "timestampInstantsEqual": timestamps_ok,
            "chunkCount": len(fp_reference.get("chunkHashes", [])),
        },
        "stable prelaunch/live/post-exit authoritative Unity identity",
        domain="compile-identity",
        hard_stop_reason="The compile probe's authoritative three-phase Unity fingerprint is incomplete or unstable.",
    )

    process_launch = load_json(REPAIR_002_REL / "process-launch-receipt.v1.json")
    check(
        "COMPILE_IDENTITY::PROCESS_COMPOSITE",
        process_launch.get("status") == "CAPTURED_EXACT_COMPOSITE_PROCESS_IDENTITY"
        and process_launch.get("processId") == compile_receipt.get("processId")
        and parse_instant(process_launch.get("creationTimeUtc")) == parse_instant(compile_receipt.get("creationTimeUtc"))
        and str(process_launch.get("executablePath", "")).replace("\\", "/")
        == str(UNITY).replace("\\", "/")
        and process_launch.get("executeMethod") is None
        and process_launch.get("projectPath") == str(PROJECT_ROOT).replace("\\", "/")
        and "-executeMethod" not in str(process_launch.get("exactCommandLine", "")),
        {
            "status": process_launch.get("status"),
            "processIdMatches": process_launch.get("processId") == compile_receipt.get("processId"),
            "creationInstantMatches": parse_instant(process_launch.get("creationTimeUtc")) == parse_instant(compile_receipt.get("creationTimeUtc")),
            "pathMatches": str(process_launch.get("executablePath", "")).replace("\\", "/") == str(UNITY).replace("\\", "/"),
            "executeMethod": process_launch.get("executeMethod"),
        },
        "PID, creation instant, path, exact command line, project path, and null executeMethod bound",
        domain="compile-identity",
        hard_stop_reason="The compile probe's composite process identity is not exact.",
    )

    trusted_rule = load_json(
        "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json"
    )
    trusted_requirements = trusted_rule.get("requirements", {})
    trusted_keys = [
        "externalThreePhaseExpectedSha256AndIndependentMethodAgreement",
        "external64KiBChunksPathFileIdPeSignerAndMetadataStable",
        "pidCreationTimePathCommandLineAndExecuteMethodBound",
        "inProcessPathSourcesAndStructuralIdentityStable",
        "knownAnswersPassed",
        "normalExitAndPostExitReconfirmationRequired",
    ]
    check(
        "IDENTITY::TRUSTED_RULE_AND_TIMESTAMP_COMPARATOR",
        trusted_rule.get("status") == "FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION"
        and all(trusted_requirements.get(key) is True for key in trusted_keys)
        and trusted_requirements.get("fileReadAllBytesRole") == "DIAGNOSTIC_ONLY"
        and trusted_requirements.get("anyAuthoritativeMismatchDisposition") == "FAIL_CLOSED_NO_ADOPTION"
        and load_json(
            "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/known-answer-receipt.v1.json"
        ).get("status") == "PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER",
        {
            "ruleStatus": trusted_rule.get("status"),
            "requirements": {key: trusted_requirements.get(key) for key in trusted_keys},
            "fileReadAllBytesRole": trusted_requirements.get("fileReadAllBytesRole"),
            "mismatchDisposition": trusted_requirements.get("anyAuthoritativeMismatchDisposition"),
        },
        "qualified fail-closed trusted identity rule and attempt-007 instant comparator",
        domain="trusted-identity",
        hard_stop_reason="Trusted Unity identity rule or timestamp comparator evidence is not terminally qualified.",
    )

    supervisor = read_text(SUPERVISOR_REL)
    runner = read_text(RUNNER_REL)
    supervisor_static = {
        "runnerV2Only": "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run" in supervisor
        and "Gate14ReMELoadQualificationRunnerV1.Run" not in supervisor,
        "receiptV2RunnerSet": all(
            token in supervisor and token in runner
            for token in (
                "lane-receipt.v2.json",
                "empty-boundary-receipt.v2.json",
                "instrument-csharp-receipt.v2.json",
            )
        ),
        "oldRunnerReceiptTokensAbsent": all(
            token not in supervisor
            for token in (
                "lane-receipt.v1.json",
                "empty-boundary-receipt.v1.json",
                "instrument-csharp-receipt.v1.json",
            )
        ),
        "threePhaseIdentity": all(token in supervisor for token in ("PRELAUNCH", "LIVE_CONCURRENT", "POST_EXIT")),
        "compositeIdentity": all(token in supervisor for token in ("CreationDate", "ExecutablePath", "CommandLine", "$expectedCommandLine")),
        "dateKindString": "-DateKind String" in supervisor,
        "naturalExit": "WaitForExit" in supervisor and "signalOrForcedTerminationAllowed" not in supervisor,
        "forcedStopAbsent": "Stop-Process" not in supervisor and ".Kill(" not in supervisor,
        "retryAbsent": "retryPerformed = $false" in supervisor,
        "zeroReplacement": "ZERO_REPLACEMENT_FAIL_STOP" in supervisor
        and "Whole superblock failed; zero-replacement fail-stop is frozen" in supervisor,
        "structuralTerminal": "PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE" in supervisor,
        "deliveryBuildTerminal": "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY" in supervisor,
        "deliveryVerifyTerminal": "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY" in supervisor,
    }
    check(
        "SUPERVISOR::STATIC_V2_STATE_MACHINE",
        all(supervisor_static.values()),
        supervisor_static,
        {key: True for key in supervisor_static},
        domain="supervisor",
        hard_stop_reason="Supervisor v2 does not statically retain every RunnerV2, receipt-v2, identity, no-signal, zero-retry, zero-replacement, and terminal-chain property.",
    )

    planning_manifest_rel = pathlib.PurePosixPath(
        "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json"
    )
    planning_manifest = load_json(planning_manifest_rel)
    planning_entries = planning_manifest.get("artifacts", [])
    planning_audit = declared_file_audit(planning_entries if isinstance(planning_entries, list) else [])
    check(
        "PLANNING::ONE_HUNDRED_SEVENTY_THREE_ARTIFACTS_EXACT",
        planning_manifest.get("status") == "FROZEN_PLANNING_ASSETS_PASS"
        and planning_manifest.get("artifactCount") == 173
        and isinstance(planning_entries, list)
        and len(planning_entries) == 173
        and planning_audit["allPathsUnique"]
        and planning_audit["mismatchCount"] == 0
        and planning_manifest.get("identityBindingRemainsSealed") is True,
        {"status": planning_manifest.get("status"), **planning_audit, "identityBindingRemainsSealed": planning_manifest.get("identityBindingRemainsSealed")},
        {"status": "FROZEN_PLANNING_ASSETS_PASS", "declaredFiles": 173, "allPathsUnique": True, "mismatchCount": 0, "identityBindingRemainsSealed": True},
        domain="planning-assets",
        hard_stop_reason="Planning assets are not a complete exact 173-artifact sealed freeze.",
    )

    schedule_rel = pathlib.PurePosixPath(
        "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl"
    )
    schedule_path = PROJECT_ROOT / schedule_rel
    schedule_rows = [
        json.loads(line)
        for line in schedule_path.read_text(encoding="utf-8-sig").splitlines()
        if line.strip()
    ]
    schedule_errors: list[str] = []
    seen_superblocks: set[str] = set()
    seen_inputs: set[str] = set()
    seen_input_ids: set[str] = set()
    seen_seeds: set[int] = set()
    context_counts: collections.Counter[str] = collections.Counter()
    algorithm_positions: collections.Counter[tuple[str, int]] = collections.Counter()
    lane_positions: collections.Counter[tuple[str, int]] = collections.Counter()
    algorithm_transitions: collections.Counter[tuple[str, str]] = collections.Counter()
    lane_transitions: collections.Counter[tuple[str, str]] = collections.Counter()
    algorithm_sequences: collections.Counter[tuple[str, ...]] = collections.Counter()
    lane_sequences: collections.Counter[tuple[str, ...]] = collections.Counter()
    mapping_fingerprints: set[str] = set()
    core_rows = 0
    stress_rows = 0
    for index, row in enumerate(schedule_rows):
        if row.get("ordinal") != index or row.get("schema") != "gate14re-me-load-qualification-schedule-row-v1":
            schedule_errors.append(f"row {index}: schema/ordinal")
        superblock = row.get("superblockId")
        input_relative = row.get("inputRelativePath")
        if superblock in seen_superblocks:
            schedule_errors.append(f"row {index}: duplicate superblock")
        if input_relative in seen_inputs:
            schedule_errors.append(f"row {index}: duplicate input path")
        seen_superblocks.add(superblock)
        seen_inputs.add(input_relative)
        if row.get("replacement") is not None:
            schedule_errors.append(f"row {index}: replacement is not null")
        lanes = row.get("algorithmOrder", [])
        algorithms = [item.get("algorithmId") for item in lanes]
        anonymous = [item.get("anonymousLaneId") for item in lanes]
        if len(lanes) != 6 or set(algorithms) != EXPECTED_ALGORITHMS or set(anonymous) != EXPECTED_LANES:
            schedule_errors.append(f"row {index}: six-algorithm/lane cohort")
        identity_hashes = {item.get("identityBindingSha256") for item in lanes}
        if identity_hashes != {IDENTITY_SHA256}:
            schedule_errors.append(f"row {index}: identity binding")
        mapping_fingerprints.add(
            hashlib.sha256(canonical_json(sorted(zip(algorithms, anonymous))).encode("utf-8")).hexdigest()
        )
        algorithm_sequences[tuple(algorithms)] += 1
        lane_sequences[tuple(anonymous)] += 1
        for position, value in enumerate(algorithms):
            algorithm_positions[(value, position)] += 1
        for position, value in enumerate(anonymous):
            lane_positions[(value, position)] += 1
        algorithm_transitions.update(zip(algorithms, algorithms[1:]))
        lane_transitions.update(zip(anonymous, anonymous[1:]))
        try:
            input_path = project_file(input_relative)
            if sha256_file(input_path) != row.get("inputSha256"):
                schedule_errors.append(f"row {index}: input hash")
            bundle = json.loads(input_path.read_text(encoding="utf-8-sig"))
        except Exception as exc:
            schedule_errors.append(f"row {index}: input load {exc}")
            continue
        if bundle.get("schema") != "gate14re-me-qualification-input-bundle-v1" or bundle.get("superblockId") != superblock:
            schedule_errors.append(f"row {index}: input identity")
        input_id = bundle.get("inputId")
        seed = bundle.get("seed")
        if input_id in seen_input_ids:
            schedule_errors.append(f"row {index}: duplicate inputId")
        if seed in seen_seeds:
            schedule_errors.append(f"row {index}: duplicate seed")
        seen_input_ids.add(input_id)
        seen_seeds.add(seed)
        groups = bundle.get("eventGroups", [])
        if len(groups) != 24 or any(group.get("topology") != bundle.get("changeTopology") for group in groups):
            schedule_errors.append(f"row {index}: event-group cardinality/topology")
        context_counts[str(bundle.get("contextStratumId"))] += 1
        if bundle.get("designRegion") == "core" and "/core/" in input_relative:
            core_rows += 1
        elif bundle.get("designRegion") == "stress" and "/stress/" in input_relative:
            stress_rows += 1
        else:
            schedule_errors.append(f"row {index}: design region/path")

    schedule_summary = {
        "rows": len(schedule_rows),
        "coreRows": core_rows,
        "stressRows": stress_rows,
        "uniqueSuperblocks": len(seen_superblocks),
        "uniqueInputPaths": len(seen_inputs),
        "uniqueInputIds": len(seen_input_ids),
        "uniqueSeeds": len(seen_seeds),
        "nullReplacements": sum(row.get("replacement") is None for row in schedule_rows),
        "identityBindingUniqueHashes": len({item.get("identityBindingSha256") for row in schedule_rows for item in row.get("algorithmOrder", [])}),
        "identityMappingFingerprints": len(mapping_fingerprints),
        "contextStrata": len(context_counts),
        "contextStratumFrequencies": sorted(set(context_counts.values())),
        "algorithmWilliamsSequences": len(algorithm_sequences),
        "algorithmSequenceFrequencies": sorted(set(algorithm_sequences.values())),
        "anonymousWilliamsSequences": len(lane_sequences),
        "anonymousSequenceFrequencies": sorted(set(lane_sequences.values())),
        "algorithmPositionFrequencies": sorted(set(algorithm_positions.values())),
        "anonymousPositionFrequencies": sorted(set(lane_positions.values())),
        "algorithmDirectedTransitionPairs": len(algorithm_transitions),
        "algorithmDirectedTransitionFrequencies": sorted(set(algorithm_transitions.values())),
        "anonymousDirectedTransitionPairs": len(lane_transitions),
        "anonymousDirectedTransitionFrequencies": sorted(set(lane_transitions.values())),
        "errors": schedule_errors[:25],
        "sealedNamedToAnonymousMappingDisclosedByAudit": False,
    }
    schedule_ok = (
        len(schedule_rows) == 162
        and core_rows == 144
        and stress_rows == 18
        and len(seen_superblocks) == len(seen_inputs) == len(seen_input_ids) == len(seen_seeds) == 162
        and not schedule_errors
        and len(mapping_fingerprints) == 1
        and len(context_counts) == 18
        and set(context_counts.values()) == {9}
        and len(algorithm_sequences) == len(lane_sequences) == 6
        and set(algorithm_sequences.values()) == set(lane_sequences.values()) == {27}
        and set(algorithm_positions.values()) == set(lane_positions.values()) == {27}
        and len(algorithm_transitions) == len(lane_transitions) == 30
        and set(algorithm_transitions.values()) == set(lane_transitions.values()) == {27}
    )
    check(
        "PLANNING::SIX_ALGORITHM_WILLIAMS_BALANCE_AND_UNIQUENESS",
        schedule_ok,
        schedule_summary,
        {
            "rows": 162, "coreRows": 144, "stressRows": 18,
            "allIdentifiersPathsAndSeedsUnique": True,
            "contexts": "18 strata x 9",
            "Williams": "6 sequences x 27; every treatment x position and every ordered adjacent pair occurs 27 times",
            "nullReplacements": 162,
            "oneSealedIdentityHashAndMapping": True,
        },
        domain="planning-assets",
        hard_stop_reason="Schedule/input cardinality, uniqueness, six-algorithm Williams balance, context balance, topology, or zero-replacement binding failed.",
    )

    sealed_identity = load_json(
        "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json"
    )
    check(
        "PLANNING::SEALED_IDENTITY_REMAINS_SEALED",
        sealed_identity.get("schema") == "gate14re-me-sealed-anonymous-identity-binding-v1"
        and sealed_identity.get("status") == "SEALED_UNTIL_QUALIFICATION_DECISION_FROZEN"
        and sha256_file(PROJECT_ROOT / pathlib.PurePosixPath(
            "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json"
        )) == IDENTITY_SHA256,
        {"status": sealed_identity.get("status"), "sha256": IDENTITY_SHA256, "mappingDisclosedByAudit": False},
        "sealed status and exact hash; mapping not disclosed",
        domain="planning-assets",
        hard_stop_reason="Anonymous identity binding is not exact and sealed.",
    )

    cardinality = contract.get("expectedCardinalities", {})
    formula_observed = {
        "totalSuperblocks": cardinality.get("coreSuperblocks", 0) + cardinality.get("stressSuperblocks", 0),
        "freshAlgorithmProcesses": cardinality.get("totalSuperblocks", 0) * cardinality.get("algorithmLanesPerSuperblock", 0),
        "expectedTotalUnityProcessesWithoutFailure": cardinality.get("instrumentSelfTestProcesses", 0)
        + cardinality.get("oracleProcesses", 0)
        + cardinality.get("emptyBoundaryProcesses", 0)
        + cardinality.get("freshAlgorithmProcesses", 0),
        "eventGroupRows": cardinality.get("freshAlgorithmProcesses", 0) * cardinality.get("eventGroupsPerLane", 0),
        "laneD3WindowRows": cardinality.get("freshAlgorithmProcesses", 0) * cardinality.get("d3WindowsPerLane", 0),
        "processResourceRows": cardinality.get("freshAlgorithmProcesses", 0) * 26,
        "emptyBoundaryRows": cardinality.get("emptyBoundaryProcesses", 0) * 1000,
    }
    expected_formula = {
        "totalSuperblocks": 162,
        "freshAlgorithmProcesses": 972,
        "expectedTotalUnityProcessesWithoutFailure": 1147,
        "eventGroupRows": 23328,
        "laneD3WindowRows": 24300,
        "processResourceRows": 25272,
        "emptyBoundaryRows": 12000,
    }
    formula_fields_match = all(formula_observed[key] == expected_formula[key] for key in expected_formula)
    contract_fields_match = (
        cardinality.get("totalSuperblocks") == 162
        and cardinality.get("freshAlgorithmProcesses") == 972
        and cardinality.get("expectedTotalUnityProcessesWithoutFailure") == 1147
        and cardinality.get("eventGroupRows") == 23328
        and cardinality.get("processResourceRows") == 25272
        and cardinality.get("emptyBoundaryRows") == 12000
    )
    check(
        "CARDINALITY::CONTRACT_FORMULAS",
        formula_fields_match and contract_fields_match,
        {"recomputed": formula_observed, "contract": cardinality},
        expected_formula,
        domain="cardinality",
        hard_stop_reason="Frozen execution cardinalities do not reconcile to 162 superblocks, 972 lanes, 1147 processes, or complete row counts.",
    )

    execution_order = contract.get("executionOrder", {})
    serial_source_tokens = {
        "oneInstrumentBeforeOracle": "Invoke-VerifiedFreshUnityProcess -Mode 'instrument-self-test'" in supervisor
        and supervisor.index("Invoke-VerifiedFreshUnityProcess -Mode 'instrument-self-test'")
        < supervisor.index("Invoke-VerifiedFreshUnityProcess -Mode 'oracle'"),
        "allOracleBeforeEmpty": supervisor.index("Invoke-VerifiedFreshUnityProcess -Mode 'oracle'")
        < supervisor.index("Invoke-VerifiedFreshUnityProcess -Mode 'empty-boundary'"),
        "allEmptyBeforeLane": supervisor.index("Invoke-VerifiedFreshUnityProcess -Mode 'empty-boundary'")
        < supervisor.index("Invoke-Superblock -Record $record"),
        "oneFreshProcessFunction": "Require-Condition (-not (Test-Path -LiteralPath $OutputDirectory))" in supervisor
        and "$script:processOrdinal++" in supervisor,
        "waitsForNaturalExitBeforeReturn": "$process.WaitForExit" in supervisor,
        "otherUnityMustBeAbsent": "Another Unity process is active; composite attribution is not unique." in supervisor,
    }
    check(
        "PROCESSES::EXPECTED_1147_STRICTLY_SERIAL_FRESH",
        execution_order.get("maximumConcurrentUnityProcesses") == 1
        and execution_order.get("instrumentSelfTestBeforeAnyOracleOrLane") is True
        and execution_order.get("all162AlgorithmNeutralOracleProcessesBeforeAnyLane") is True
        and execution_order.get("twelveFreshEmptyBoundaryProcessesBeforeAnyLane") is True
        and execution_order.get("strictWilliamsSixLaneOrderWithinEachSuperblock") is True
        and execution_order.get("oneFreshUnityProcessPerAlgorithmLane") is True
        and all(serial_source_tokens.values())
        and formula_observed["expectedTotalUnityProcessesWithoutFailure"] == 1147,
        {"contractOrder": execution_order, "sourceEvidence": serial_source_tokens, "expectedProcesses": formula_observed["expectedTotalUnityProcessesWithoutFailure"]},
        "1 instrument + 162 oracle + 12 empty-boundary + 972 lane = 1147 fresh Unity processes, concurrency exactly 1",
        domain="process-model",
        hard_stop_reason="The v2 chain does not statically bind exactly 1147 strictly serial fresh Unity processes.",
    )

    replacement_observed = {
        "scheduleRows": len(schedule_rows),
        "scheduleReplacementFieldsAllNull": all(row.get("replacement") is None for row in schedule_rows),
        "contractPolicy": execution_order.get("zeroReplacementPolicy"),
        "contractGeneratedOrConsumed": execution_order.get("wholeSuperblockReplacementAssetsGeneratedOrConsumed"),
        "manifestPolicy": manifest.get("replacementPolicy", {}).get("currentOperationalPolicy"),
        "manifestGenerated": manifest.get("replacementPolicy", {}).get("replacementAssetsGenerated"),
        "manifestConsumed": manifest.get("replacementPolicy", {}).get("replacementAssetsConsumed"),
        "supervisorThrowsOnWholeSuperblockFailure": "Whole superblock failed; zero-replacement fail-stop is frozen" in supervisor,
        "supervisorRequiresEmptyReplacementLedger": "Replacement ledger is not empty under the zero-replacement contract." in supervisor,
        "historicalBudgetCeiling": load_json(
            "Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json"
        ).get("maximumWholeSuperblockTechnicalReplacements"),
    }
    check(
        "REPLACEMENT::ZERO_REPLACEMENT_FAIL_STOP",
        replacement_observed["scheduleReplacementFieldsAllNull"]
        and replacement_observed["contractPolicy"] == "ZERO_REPLACEMENT_FAIL_STOP"
        and replacement_observed["contractGeneratedOrConsumed"] is False
        and replacement_observed["manifestPolicy"] == "ZERO_REPLACEMENT_FAIL_STOP"
        and replacement_observed["manifestGenerated"] == 0
        and replacement_observed["manifestConsumed"] == 0
        and replacement_observed["supervisorThrowsOnWholeSuperblockFailure"]
        and replacement_observed["supervisorRequiresEmptyReplacementLedger"],
        replacement_observed,
        "current v2 operational contract supersedes the historical ceiling of one with zero replacement and immediate fail-stop",
        domain="replacement-policy",
        hard_stop_reason="Current execution assets do not consistently enforce zero-replacement fail-stop.",
    )

    budget = load_json("Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json")
    total_reservations = int(budget.get("qualificationReservedStorageBytes", 0)) + int(
        budget.get("formalRawAndDeliveryReservedStorageBytes", 0)
    )
    budget_observed = {
        "status": budget.get("status"),
        "maximumConcurrentUnityProcesses": budget.get("maximumConcurrentUnityProcesses"),
        "laneAssignedCommittedMemoryBytes": budget.get("laneAssignedCommittedMemoryBytes"),
        "currentTotalVisibleMemoryBytes": pre_system.get("totalVisibleMemoryBytes"),
        "totalFrozenReservationsBytes": total_reservations,
        "currentDriveHFreeBytes": pre_system.get("driveHFreeBytes"),
        "currentFreeBytesAfterBothReservations": int(pre_system.get("driveHFreeBytes", 0)) - total_reservations,
        "logicalProcessors": pre_system.get("logicalProcessors"),
        "operatingSystemVersion": pre_system.get("operatingSystemVersion"),
        "baseBoard": f"{pre_system.get('baseBoardManufacturer')} {pre_system.get('baseBoardProduct')}",
        "positiveTimeoutFields": all(
            isinstance(budget.get(key), (int, float)) and budget.get(key) > 0
            for key in (
                "eventGroupHardTimeoutMilliseconds", "laneWallClockHardTimeoutMilliseconds",
                "oracleInputHardTimeoutMilliseconds", "instrumentProcessHardTimeoutMilliseconds",
                "emptyBoundaryProcessHardTimeoutMilliseconds", "plannerOperationBudgetMilliseconds",
                "repairOperationBudgetMilliseconds", "initializationOperationBudgetMilliseconds",
            )
        ),
    }
    budget_ok = (
        budget.get("status") == "FROZEN_PREEXECUTION_BUDGETS"
        and budget.get("maximumConcurrentUnityProcesses") == 1
        and budget_observed["positiveTimeoutFields"]
        and int(pre_system.get("totalVisibleMemoryBytes", 0)) >= int(budget.get("laneAssignedCommittedMemoryBytes", 0))
        and int(pre_system.get("driveHFreeBytes", 0)) >= total_reservations
        and pre_system.get("logicalProcessors") == budget.get("hostSnapshot", {}).get("logicalProcessors")
        and pre_system.get("operatingSystemVersion") == budget.get("hostSnapshot", {}).get("operatingSystemVersion")
    )
    check(
        "BUDGET::CURRENT_HOST_QUALIFIES",
        budget_ok,
        budget_observed,
        "frozen positive time/memory budgets, concurrency 1, same host class, and free H: space at least both frozen reservations",
        domain="runtime-budget",
        hard_stop_reason="Current host no longer satisfies the frozen runtime budget and storage reservations.",
    )

    typed_manifest = load_json("Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json")
    typed_entries = list(typed_manifest.get("installedFiles", [])) + list(typed_manifest.get("wheelArtifacts", []))
    typed_audit = declared_file_audit(typed_entries)
    distribution = typed_manifest.get("distribution", {})
    check(
        "RUNTIME::TYPED_PARQUET_763_FILES_EXACT",
        typed_manifest.get("status") == "FROZEN_TYPED_PARQUET_RUNTIME"
        and typed_manifest.get("installedFileCount") == 762
        and len(typed_manifest.get("installedFiles", [])) == 762
        and typed_manifest.get("wheelArtifactCount") == 1
        and len(typed_manifest.get("wheelArtifacts", [])) == 1
        and typed_audit["allPathsUnique"]
        and typed_audit["mismatchCount"] == 0
        and distribution.get("name") == "pyarrow"
        and distribution.get("version") == "25.0.1"
        and distribution.get("pythonAbi") == "cp312"
        and distribution.get("platform") == "win_amd64",
        {"status": typed_manifest.get("status"), "distribution": distribution, **typed_audit},
        {"installedFiles": 762, "wheelArtifacts": 1, "distribution": "pyarrow 25.0.1 cp312 win_amd64", "mismatchCount": 0},
        domain="typed-parquet-runtime",
        hard_stop_reason="Frozen typed-Parquet runtime is incomplete, drifted, or has the wrong distribution identity.",
    )

    d3 = load_json("Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json")
    d3_bindings = d3.get("frozenImplementationBindings", {})
    d3_mismatches: list[dict[str, Any]] = []
    for key, value in d3_bindings.items() if isinstance(d3_bindings, dict) else []:
        if key.endswith("RelativePath"):
            hash_key = key[:-12] + "Sha256"
            if hash_key in d3_bindings:
                path = project_file(value)
                actual = sha256_file(path)
                if actual != d3_bindings[hash_key]:
                    d3_mismatches.append({"binding": key, "relativePath": value, "actualSha256": actual, "expectedSha256": d3_bindings[hash_key]})
    d3_known = load_json(d3_bindings.get("knownAnswerReceiptRelativePath"))
    d3_cycle = load_json(d3_bindings.get("knownAnswerCycleReceiptRelativePath"))
    check(
        "D3::V3_1_TRUE_CUMULATIVE_ALLOCATION_QUALIFIED",
        d3.get("status") == "QUALIFIED_FROZEN_D3_V3_1"
        and str(d3.get("semanticVersion")) == "3.1"
        and d3.get("qualifiedKnownAnswerCriteria", {}).get("allCriteriaPassed") is True
        and not d3_mismatches
        and d3_known.get("status") == "PASS_D3_V3_1_TRUE_CUMULATIVE_MANAGED_ALLOCATION_QUALIFICATION"
        and d3_cycle.get("status") == "PASS_D3_V3_1_STRICT_JSON_KNOWN_ANSWER",
        {
            "status": d3.get("status"),
            "semanticVersion": d3.get("semanticVersion"),
            "allCriteriaPassed": d3.get("qualifiedKnownAnswerCriteria", {}).get("allCriteriaPassed"),
            "bindingMismatches": d3_mismatches,
            "knownAnswerStatus": d3_known.get("status"),
            "cycleStatus": d3_cycle.get("status"),
        },
        "qualified D3-v3.1 exact source/binary/wrapper/harness and terminal known-answer evidence",
        domain="D3-v3.1",
        hard_stop_reason="Qualified D3-v3.1 bindings or known-answer evidence drifted or ceased to be terminal PASS.",
    )

    output_schema = load_json("Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json")
    raw_table_ids = [item.get("tableId") for item in output_schema.get("rawTables", [])]
    expected_tables = [
        "oracle-agent-checks", "oracle-event-checks", "operations", "event-groups",
        "d3-windows", "persistent-state", "process-resources", "empty-boundary",
        "replacement-ledger", "failures-and-voids",
    ]
    delivery_views = output_schema.get("deliveryViews", {})
    bridge_validation = load_json(
        "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/validation-receipt.v1.json"
    )
    data_delivery_contract = load_json("Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json")
    check(
        "DELIVERY::COMPLETE_PER_OBSERVATION_HARD_GATE_AND_BRIDGE",
        output_schema.get("status") == "FROZEN_COMPLETE_PER_OBSERVATION_D3_V3_1_INTEGRATED"
        and raw_table_ids == expected_tables
        and delivery_views.get("aggregateOnlyAllowed") is False
        and delivery_views.get("rowIdentityPreservedAcrossViews") is True
        and bridge_validation.get("status") == "PASS_SCHEMA_V2_TOOLING_BRIDGE_VALIDATION"
        and bridge_validation.get("positiveDeliveryCheck", {}).get("aggregateOnlyPackage") is False
        and bridge_validation.get("positiveDeliveryCheck", {}).get("completeValueTypeOrderRoundTripPassed") is True
        and bridge_validation.get("positiveDeliveryCheck", {}).get("typedParquetRoundTripPassed") is True
        and data_delivery_contract.get("hardCondition", {}).get("completePerObservationRawDataDeliverable") is True
        and data_delivery_contract.get("hardCondition", {}).get("mandatoryForPrecollectionReadiness") is True,
        {
            "outputStatus": output_schema.get("status"),
            "rawTables": raw_table_ids,
            "deliveryViews": delivery_views,
            "bridgeStatus": bridge_validation.get("status"),
            "bridgeDelivery": bridge_validation.get("positiveDeliveryCheck"),
            "hardCondition": data_delivery_contract.get("hardCondition"),
        },
        "10 raw tables; complete JSONL/CSV/gzip/typed-Parquet row-preserving bridge; aggregation-only forbidden; delivery hard gate retained",
        domain="structural-delivery",
        hard_stop_reason="Complete per-observation delivery hard gate or schema-v2 bridge evidence is not terminally satisfied.",
    )

    structural_rel = pathlib.PurePosixPath("Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v2.py")
    delivery_rel = pathlib.PurePosixPath("Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2.py")
    structural_text = read_text(structural_rel)
    delivery_text = read_text(delivery_rel)
    ast.parse(structural_text, filename=structural_rel.as_posix())
    ast.parse(delivery_text, filename=delivery_rel.as_posix())
    terminal_tokens = {
        "structuralQualificationProfile": "qualification-full" in structural_text,
        "structuralPass": "PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE" in structural_text,
        "deliveryBuildPass": "PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY" in delivery_text,
        "deliveryVerifyPass": "PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY" in delivery_text,
        "typedParquetRuntimeHash": EXPECTED_CORE_HASHES["Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json"] in delivery_text,
        "outputSchemaHash": EXPECTED_CORE_HASHES["Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json"] in structural_text,
        "d3ContractHash": EXPECTED_CORE_HASHES["Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json"] in structural_text,
    }
    check(
        "TERMINAL::STRUCTURAL_AND_DELIVERY_SOURCES_PARSE_AND_BIND",
        all(terminal_tokens.values()),
        terminal_tokens,
        {key: True for key in terminal_tokens},
        domain="structural-delivery",
        hard_stop_reason="Structural-v2 or delivery-v2 cannot be parsed or lacks an exact terminal binding/status.",
    )

    actual_receipts = {
        "_control/launch-receipt.v2.json",
        "oracle-pass-receipt.v1.json",
        "lane-receipt.v2.json",
        "accepted-superblock-receipt.v1.json",
        "empty-boundary-receipt.v2.json",
        "instrument-csharp-receipt.v2.json",
        "instrument-export-receipt.v2.json",
        "_control/acquisition-complete.v2.json",
        "delivery-manifest.v2.json",
    }
    schema_receipts = set(output_schema.get("receipts", []))
    receipt_missing_from_schema = sorted(actual_receipts - schema_receipts)
    receipt_stale_in_schema = sorted(schema_receipts - actual_receipts)
    check(
        "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT",
        schema_receipts == actual_receipts,
        {
            "schemaReceiptCount": len(schema_receipts),
            "runtimeReceiptCount": len(actual_receipts),
            "runtimeReceiptsMissingFromSchema": receipt_missing_from_schema,
            "staleSchemaReceiptsNotProducedByV2Chain": receipt_stale_in_schema,
        },
        {"runtimeReceiptsMissingFromSchema": [], "staleSchemaReceiptsNotProducedByV2Chain": []},
        domain="structural-delivery",
        hard_stop_reason=(
            "Frozen output schema v2 still declares v1 launch, acquisition-complete, "
            "instrument-export, and delivery-manifest paths, while supervisor/delivery v2 "
            "produce the corresponding v2 paths. The terminal package is therefore not "
            "path/version-consistent with its frozen output schema."
        ),
    )

    terminal_closure_observed = {
        "validatesLaneReceipts972": "expected_lanes = 1 if profile == \"synthetic-known-answer\" else 972" in structural_text,
        "validatesEmptyReceipts12": "expected_empty = 1 if profile == \"synthetic-known-answer\" else 12" in structural_text,
        "validatesEventRows23328": "len(tables[\"event-groups\"]) != 23328" in structural_text,
        "validatesEmptyBoundaryRows12000": "emptyBoundaryD3Joins\"] != 12000" in structural_text,
        "validatesProcessResourceRows25272": "25272" in structural_text and "process-resources" in structural_text,
        "validatesPersistentStateMeasurementCoverage": "persistent-state" in structural_text and "measurementPointsPerLane" in structural_text,
        "validatesAcceptedSuperblockReceipts162": "accepted-superblock-receipt" in structural_text,
        "validatesProcessLedger1147": "process-ledger" in structural_text and "1147" in structural_text,
        "validatesProcessIdentityReceipts1147": "process-identit" in structural_text and "1147" in structural_text,
        "supervisorExplicitlyAssertsFinalProcessOrdinal1147": "Require-Condition ($processOrdinal -eq 1147)" in supervisor,
    }
    terminal_closure_ok = all(terminal_closure_observed.values())
    check(
        "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE",
        terminal_closure_ok,
        terminal_closure_observed,
        {key: True for key in terminal_closure_observed},
        domain="structural-delivery",
        hard_stop_reason=(
            "The terminal structural-v2 receipt does not re-establish the complete frozen "
            "cardinality/provenance chain: it omits the 25,272 process-resource rows, "
            "persistent-state measurement-point coverage, 162 accepted-superblock receipts, "
            "the 1,147-row process ledger and 1,147 process-identity receipts; supervisor v2 "
            "also writes processOrdinal without an explicit final equality assertion to 1,147."
        ),
    )

    after_inventories = {name: inventory(path) for name, path in retained_roots.items()}
    after_digests = {name: inventory_digest(items) for name, items in after_inventories.items()}
    retention_unchanged = before_inventories == after_inventories
    check(
        "RETENTION::ALL_THREE_PRIOR_ATTEMPTS_BYTE_IDENTICAL",
        retention_unchanged,
        {name: {"before": before_digests[name], "after": after_digests[name]} for name in retained_roots},
        "all before/after digests equal",
        domain="retained-evidence",
        hard_stop_reason="A retained prior attempt changed during this audit.",
    )

    post_system = system_probe()
    existing_prohibited_after = [rel.as_posix() for rel in prohibited_roots if (PROJECT_ROOT / rel).exists()]
    check(
        "BOUNDARY::UNITY_ABSENT_AT_END",
        len(post_system.get("unityProcesses", [])) == 0,
        len(post_system.get("unityProcesses", [])),
        0,
        domain="boundary",
        hard_stop_reason="Unity.exe was active at the end of the no-Unity audit.",
    )
    check(
        "BOUNDARY::PROHIBITED_ROOTS_ABSENT_AT_END",
        not existing_prohibited_after,
        existing_prohibited_after,
        [],
        domain="boundary",
        hard_stop_reason="This audit observed creation of a prohibited measured, delivery, or formal root.",
    )

    failed_checks = [item for item in checks if not item["passed"]]
    passed = not failed_checks
    completed = utc_now()
    audit = {
        "schema": "gate14re-me-qualification-execution-readiness-audit-v2",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "designId": "gate14re-me-load-qualification-planning-v2",
        "authorizationId": authorization["authorizationId"],
        "attemptId": authorization["attemptId"],
        "startedAtUtc": started,
        "completedAtUtc": completed,
        "mode": "READ_ONLY_OFFLINE_NO_UNITY",
        "status": "PASS_QUALIFICATION_EXECUTION_READINESS_V2" if passed else "FAIL_CLOSED_QUALIFICATION_EXECUTION_READINESS_V2",
        "passed": passed,
        "summary": {
            "totalChecks": len(checks),
            "passedChecks": len(checks) - len(failed_checks),
            "failedChecks": len(failed_checks),
            "hardStopReasons": len(hard_stops),
            "expectedSerialFreshUnityProcessesForLaterAuthorizedRun": 1147,
            "unityInvocationsByThisAudit": 0,
        },
        "checks": checks,
        "hardStopReasons": hard_stops,
        "retainedEvidence": {
            name: {
                "relativePath": retained_roots[name].relative_to(PROJECT_ROOT).as_posix(),
                "files": len(before_inventories[name]),
                "beforeDigest": before_digests[name],
                "afterDigest": after_digests[name],
                "unchanged": before_inventories[name] == after_inventories[name],
            }
            for name in retained_roots
        },
        "scientificBoundary": {
            "measuredRootCreated": False,
            "deliveryRootCreated": False,
            "unityInvocationCount": 0,
            "plannerInvocationCount": 0,
            "algorithmLaneExecutionCount": 0,
            "qualificationObservationCount": 0,
            "formalObservationCount": 0,
            "formalCollectionPerformed": False,
            "formalAnalysisPerformed": False,
            "rankingPerformed": False,
            "winnerAdjudicationPerformed": False,
            "sealedIdentityMappingDisclosed": False,
        },
    }
    audit_path = write_json_exclusive("readiness-audit.v2.json", audit)

    boundary = {
        "schema": "gate14re-me-qualification-execution-readiness-attempt-002-authorization-boundary-receipt-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": authorization["authorizationId"],
        "status": "PASS_AUTHORIZED_READ_ONLY_BOUNDARY",
        "completedAtUtc": completed,
        "unityProcessesAtStart": len(pre_system.get("unityProcesses", [])),
        "unityProcessesAtEnd": len(post_system.get("unityProcesses", [])),
        "unityInvocations": 0,
        "measuredRootCreated": False,
        "deliveryRootCreated": False,
        "plannerInvocations": 0,
        "algorithmLaneExecutions": 0,
        "qualificationObservations": 0,
        "formalObservations": 0,
        "formalCollectionPerformed": False,
        "formalAnalysisPerformed": False,
        "rankingPerformed": False,
        "winnerAdjudicationPerformed": False,
        "priorAttemptsModifiedOrReclassified": False,
        "sealedIdentityMappingDisclosed": False,
    }
    boundary_path = write_json_exclusive("authorization-boundary-receipt.v1.json", boundary)

    if passed:
        terminal = {
            "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-terminal-receipt-v2",
            "studyId": "Gate14Re-ME",
            "authorizationId": authorization["authorizationId"],
            "status": "PASS_QUALIFICATION_EXECUTION_READINESS_V2_FROZEN_EXECUTION_STILL_UNAUTHORIZED",
            "passed": True,
            "terminal": True,
            "completedAtUtc": completed,
            "readinessAuditSha256": sha256_file(audit_path),
            "authorizationBoundaryReceiptSha256": sha256_file(boundary_path),
            "expectedSerialFreshUnityProcesses": 1147,
            "qualificationExecutionAuthorized": False,
            "nextActionRequiresSeparateAuthorization": True,
        }
        write_json_exclusive("terminal-readiness-receipt.v2.json", terminal)
    else:
        failure = {
            "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-failure-receipt-v1",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "designId": "gate14re-me-load-qualification-planning-v2",
            "authorizationId": authorization["authorizationId"],
            "attemptId": authorization["attemptId"],
            "status": "FAILED_CLOSED_QUALIFICATION_EXECUTION_READINESS_TERMINAL_CHAIN_INCOMPLETE",
            "passed": False,
            "terminal": True,
            "completedAtUtc": completed,
            "readinessAudit": {
                "relativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(),
                "sha256": sha256_file(audit_path),
                "totalChecks": len(checks),
                "passedChecks": len(checks) - len(failed_checks),
                "failedChecks": len(failed_checks),
            },
            "hardStopReasons": hard_stops,
            "preservedPassEvidence": {
                "allCoreAndRuntimeHashesMatched": not any(item["checkId"].startswith("HASHES::") and not item["passed"] for item in checks),
                "planningAssetsAndWilliamsBalancePassed": all(item["passed"] for item in checks if item["domain"] == "planning-assets"),
                "expectedProcessFormula": "1 + 162 + 12 + 972 = 1147",
                "serialFreshProcessControlFlowPassed": next(item["passed"] for item in checks if item["checkId"] == "PROCESSES::EXPECTED_1147_STRICTLY_SERIAL_FRESH"),
                "zeroReplacementFailStopPassed": next(item["passed"] for item in checks if item["checkId"] == "REPLACEMENT::ZERO_REPLACEMENT_FAIL_STOP"),
                "runtimeBudgetPassed": next(item["passed"] for item in checks if item["checkId"] == "BUDGET::CURRENT_HOST_QUALIFIES"),
                "compileIdentityPassed": all(item["passed"] for item in checks if item["domain"] == "compile-identity"),
                "completePerObservationBridgeEvidencePassed": next(item["passed"] for item in checks if item["checkId"] == "DELIVERY::COMPLETE_PER_OBSERVATION_HARD_GATE_AND_BRIDGE"),
            },
            "scientificBoundary": audit["scientificBoundary"],
            "disposition": {
                "qualificationExecutionAuthorized": False,
                "measuredOrDeliveryRootCreationAllowed": False,
                "unityRestartOrRetryAllowed": False,
                "repairPerformed": False,
                "automaticNextAttemptCreated": False,
                "formalCollectionAnalysisRankingOrWinnerAllowed": False,
                "nextStepRequiresSeparateRepairAuthorization": True,
            },
        }
        write_json_exclusive("failure-receipt.v1.json", failure)

    attempt_files = [
        path for path in sorted(ATTEMPT_ROOT.iterdir(), key=lambda p: p.name.lower())
        if path.is_file() and path.name != "source-and-evidence-freeze-manifest.v1.json"
    ]
    freeze_manifest = {
        "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-source-and-evidence-freeze-manifest-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": authorization["authorizationId"],
        "attemptId": authorization["attemptId"],
        "status": "FROZEN_PASS_READINESS_EVIDENCE" if passed else "FROZEN_FAILED_CLOSED_READINESS_EVIDENCE",
        "createdAtUtc": utc_now(),
        "attemptFilesExcludingThisManifest": [
            {
                "relativePath": path.relative_to(PROJECT_ROOT).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in attempt_files
        ],
        "boundCurrentAssets": [
            {"relativePath": relative, "sha256": expected}
            for relative, expected in (
                (SUPERVISOR_REL.as_posix(), EXPECTED_CORE_HASHES[SUPERVISOR_REL.as_posix()]),
                (CONTRACT_REL.as_posix(), EXPECTED_CORE_HASHES[CONTRACT_REL.as_posix()]),
                (MANIFEST_REL.as_posix(), EXPECTED_CORE_HASHES[MANIFEST_REL.as_posix()]),
                (RUNNER_REL.as_posix(), EXPECTED_CORE_HASHES[RUNNER_REL.as_posix()]),
                (COMPILE_RECEIPT_REL.as_posix(), EXPECTED_CORE_HASHES[COMPILE_RECEIPT_REL.as_posix()]),
            )
        ],
        "retainedEvidenceInventoryDigests": {
            name: {"before": before_digests[name], "after": after_digests[name]}
            for name in retained_roots
        },
        "selfExcludedToAvoidCircularHash": True,
        "readOnlyFreezeAppliedAfterManifestCreation": True,
    }
    write_json_exclusive("source-and-evidence-freeze-manifest.v1.json", freeze_manifest)

    for path in ATTEMPT_ROOT.iterdir():
        if path.is_file():
            os.chmod(path, stat.S_IREAD)

    print(
        json.dumps(
            {
                "status": audit["status"],
                "passed": passed,
                "totalChecks": len(checks),
                "passedChecks": len(checks) - len(failed_checks),
                "failedChecks": len(failed_checks),
                "hardStopReasons": hard_stops,
                "attemptRoot": ATTEMPT_REL.as_posix(),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0 if passed else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        emergency = {
            "schema": "gate14re-me-qualification-execution-readiness-freeze-attempt-002-emergency-failure-v1",
            "studyId": "Gate14Re-ME",
            "status": "FAILED_CLOSED_AUDIT_TOOL_EXCEPTION",
            "failedAtUtc": utc_now(),
            "exceptionType": type(exc).__name__,
            "exactFailure": str(exc),
            "qualificationExecutionAuthorized": False,
            "unityInvocationsByAudit": 0,
        }
        try:
            write_json_exclusive("failure-receipt.v1.json", emergency)
        except Exception:
            pass
        print(json.dumps(emergency, ensure_ascii=False, indent=2), file=sys.stderr)
        raise SystemExit(3)
