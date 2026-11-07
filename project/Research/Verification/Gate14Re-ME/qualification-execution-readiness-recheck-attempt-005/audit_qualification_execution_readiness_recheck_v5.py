#!/usr/bin/env python3
"""Read-only Gate14Re-ME qualification execution readiness recheck, attempt-005.

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
    "qualification-execution-readiness-recheck-attempt-005"
)
ATTEMPT_ROOT = (PROJECT_ROOT / ATTEMPT_REL).resolve()
AUTHORIZATION_ID = "gate14re-me-qualification-execution-readiness-recheck-until-pass-3bb50249-7ac1-49e5-af37-839465bc47bd"
ATTEMPT_ID = "qualification-execution-readiness-recheck-attempt-005"
STATUS_35_REL = pathlib.PurePosixPath("Research/Gate14Re-ME/Gate14Re_ME_Status.v35.json")

USER_AUTHORIZATION_TEXT = "授权`qualification execution-readiness recheck`  阶段直至attempt通过"

PINNED_PYTHON = pathlib.Path(
    r"C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)
PINNED_POWERSHELL = pathlib.Path(
    r"C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
)
PINNED_POWERSHELL_SHA256 = "362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139"
PINNED_POWERSHELL_VERSION = "7.6.5"

RESERVED_ROOTS = [
    "Research/PilotRuns/Gate14Re-ME/load-qualification",
    "Research/Exports/Gate14Re-ME/load-qualification",
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
    "readinessRecheckAttempt003": {
        "relativePath": "Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-003",
        "receipt": "terminal-readiness-receipt.v1.json",
        "receiptSha256": "fb94db25887dc30a8765980bb4c6d735388266da9285e82c0a441f1dcd9bb653",
        "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V3_FROZEN_EXECUTION_UNAUTHORIZED",
    },
    "loadQualificationExecutionAttempt001": {
        "relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-001",
        "receipt": "failure-receipt.v1.json",
        "receiptSha256": "9f4d79f100bfe41018bb9972c6cf085ac275845391a1a1450cc1ff7bffd2822d",
        "status": "FAILED_CLOSED_PRELAUNCH_FROZEN_POWERSHELL_RUNTIME_INCOMPATIBLE",
    },
    "powerShellHostBindingAttempt003": {
        "relativePath": "Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-003",
        "receipt": "terminal-pass-receipt.v1.json",
        "receiptSha256": "3ac34ef5e92af59648828e719add81a0d42078bfbd4ff4a9f1eb5b1613af6418",
        "status": "PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING",
    },
    "powerShellHostBindingAttempt004": {
        "relativePath": "Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-004",
        "receipt": "terminal-pass-receipt.v1.json",
        "receiptSha256": "7389f1151a7bfc4d7ce8adb27450210f7f3dfa051d4e44538256da4f9b5270dd",
        "status": "PASS_FROZEN_POWERSHELL_HOST_BINDING_READONLY_CLOSURE",
    },
    "readinessRecheckAttempt004": {
        "relativePath": "Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-004",
        "receipt": "terminal-readiness-receipt.v1.json",
        "receiptSha256": "4edafd87ffe927ccf8d9c38c73c486141ee311e291f1d20f5bb82b358f6cc56b",
        "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V4_HOST_BOUND_EXECUTION_UNAUTHORIZED",
    },
    "loadQualificationExecutionAttempt002": {
        "relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-002",
        "receipt": "failure-receipt.v1.json",
        "receiptSha256": "83882d9bcfba2cc08c86c87da9e8ae2fb920b32814b7b1fee165e59025323c10",
        "status": "FAILED_CLOSED_PREFLIGHT_SUPERVISOR_MANIFEST_STATE_GUARD_MISMATCH",
    },
    "supervisorManifestGuardAttempt001": {
        "relativePath": "Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-001",
        "receipt": "failure-receipt.v1.json",
        "receiptSha256": "1cb8861ca48098cff1556f9a83c501b5700aaade337980c6b9a0865753583412",
        "status": "FAILED_CLOSED_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM",
    },
    "supervisorManifestGuardAttempt002": {
        "relativePath": "Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-002",
        "receipt": "terminal-pass-receipt.v1.json",
        "receiptSha256": "499f23b98f6e6e75053451d583acb6205020ec34978e6f0f8454b32a25a03ac8",
        "status": "PASS_FROZEN_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM",
    },
}

EXPECTED_HASHES = {
    "statusV34": ("Research/Gate14Re-ME/Gate14Re_ME_Status.v34.json", "305af9bba1a078eebe9e6219289b51edbb130b7576b58cd6c2f76692e049abcf"),
    "statusV31": ("Research/Gate14Re-ME/Gate14Re_ME_Status.v31.json", "27e766ac61ce77321a6e01ed772398d19135e5dc57e70419bf849292b2ad5529"),
    "outputSchemaV3": ("Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json", "e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c"),
    "outputSchemaV2": ("Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json", "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb"),
    "structuralV31": ("Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py", "85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e"),
    "deliveryV22": ("Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2_2.py", "197b14309670fc38e26b421c458fbd4fc05abe8ba61f7f715497bbcffb19eb98"),
    "supervisorV3": ("Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3.ps1", "e672d2bc3e584192d1f9850ed2bb76538ba11fead80e1ce94670febd9fb45035"),
    "supervisorV31": ("Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_1.ps1", "33764e996f9a2fe8ff5487eabd5b455a931b82f0923b8ac083b4aef9dc7242dc"),
    "executionContractV32": ("Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_2.json", "10c5689a3fccfbc5faef13d83a3b1db3026b8931581b510fbee9be1cd3a0e9d0"),
    "implementationManifestV32": ("Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_2.json", "83ef4c7081a77f7093e9f37f53b786f628459c404ca9e89b78d6e93ce64d2514"),
    "executionContractV33": ("Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_3.json", "6e35abb3f36f956f0f685f816e2b2a7c1ce2aa513a86bd16d575964bd619802a"),
    "implementationManifestV33": ("Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_3.json", "a85968ee3c759c5f0c3c3bf3a5d9c3bda7c3cfca7628f3e983cb64142bfe4579"),
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
    "hostBindingAttempt003KnownAnswer": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-003/powershell-known-answer-receipt.v1.json", "d105d621077d301aa99d925a215887f827213a8d3725a194ba2a9e515194a158"),
    "hostBindingAttempt003Terminal": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-003/terminal-pass-receipt.v1.json", "3ac34ef5e92af59648828e719add81a0d42078bfbd4ff4a9f1eb5b1613af6418"),
    "hostBindingAttempt003Freeze": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-003/freeze-manifest.v1.json", "f884b5bce36f82c3f5e8424a4da29910252a9155953abb7a589b4c1ca18e3cc5"),
    "hostBindingAttempt004Closure": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-004/readonly-freeze-closure-receipt.v1.json", "77c5bedd45260efa90325763ccb8ef2371c85a53bf3c60ad0139465ae816bc6a"),
    "hostBindingAttempt004Terminal": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-004/terminal-pass-receipt.v1.json", "7389f1151a7bfc4d7ce8adb27450210f7f3dfa051d4e44538256da4f9b5270dd"),
    "hostBindingAttempt004Freeze": ("Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-004/freeze-manifest.v1.json", "767af99ec1774ea0d10436badbb00bea096dd3db20ececb3256e734d7216a589"),
    "readinessAttempt004Terminal": ("Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-004/terminal-readiness-receipt.v1.json", "4edafd87ffe927ccf8d9c38c73c486141ee311e291f1d20f5bb82b358f6cc56b"),
    "readinessAttempt004Audit": ("Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-004/readiness-recheck-audit.v4.json", "6818b49c722ee28981e2a39ceb7fcfa02431e1ceecb133ea5811542a7ecb4dbb"),
    "loadExecutionAttempt002Failure": ("Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-002/failure-receipt.v1.json", "83882d9bcfba2cc08c86c87da9e8ae2fb920b32814b7b1fee165e59025323c10"),
    "guardAttempt001Failure": ("Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-001/failure-receipt.v1.json", "1cb8861ca48098cff1556f9a83c501b5700aaade337980c6b9a0865753583412"),
    "guardAttempt001Freeze": ("Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-001/freeze-manifest.v1.json", "103066173a69eb94500dc148e737fb9a1d23b5ea9f794c20ab10ce06634268f5"),
    "guardAttempt002KnownAnswer": ("Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-002/exact-predicate-known-answer-receipt.v1.json", "870b2fc9dfb18202b422a60ba50d738c011e0767c9031d4c85d51aa4a1c19397"),
    "guardAttempt002Terminal": ("Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-002/terminal-pass-receipt.v1.json", "499f23b98f6e6e75053451d583acb6205020ec34978e6f0f8454b32a25a03ac8"),
    "guardAttempt002Freeze": ("Research/Verification/Gate14Re-ME/supervisor-manifest-acceptance-guard-corrigendum-attempt-002/freeze-manifest.v1.json", "9d2114efdeb11ca48ebd11f39ee0acff1027787be78e450ad46a896153e461a3"),
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
        [str(PINNED_POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
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
        [str(PINNED_POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
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


def powershell_host_probe() -> dict[str, Any]:
    command = r"""
$ErrorActionPreference='Stop'
$cmd=Get-Command ConvertFrom-Json -ErrorAction Stop
[pscustomobject]@{
  processPath=[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  version=$PSVersionTable.PSVersion.ToString()
  convertFromJsonDepth=($null -ne $cmd.Parameters['Depth'])
  convertFromJsonDateKind=($null -ne $cmd.Parameters['DateKind'])
  dateKindStringPreserved=((('{"timestamp":"2024-06-11T11:26:54.0000000Z"}' | ConvertFrom-Json -Depth 100 -DateKind String).timestamp) -ceq '2024-06-11T11:26:54.0000000Z')
} | ConvertTo-Json -Depth 8 -Compress
"""
    completed = subprocess.run(
        [str(PINNED_POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return json.loads(completed.stdout.strip())


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
    if project_file(STATUS_35_REL).exists():
        raise RuntimeError("Status v35 already exists; exclusive attempt would overwrite prior evidence")

    if not PINNED_POWERSHELL.is_file() or sha256_file(PINNED_POWERSHELL) != PINNED_POWERSHELL_SHA256:
        raise RuntimeError("exact frozen PowerShell 7.6.5 host runtime is missing or hash-drifted; no host process was started")

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
            f"RETENTION::{label}::STATUS_HASH_AND_INVENTORY_CAPTURED",
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
        reason="One or more Status v34, supervisor v3.1, contract/manifest v3.3, retained host-bound execution, terminal-chain, planning, instrument, identity, runtime, or corrigendum receipt hashes drifted.",
    )

    read_only_bindings = {
        label: is_read_only(project_file(EXPECTED_HASHES[label][0]))
        for label in (
            "statusV34", "supervisorV31", "executionContractV33", "implementationManifestV33",
            "statusV31", "executionContractV32", "implementationManifestV32",
            "hostBindingAttempt003KnownAnswer", "hostBindingAttempt003Terminal", "hostBindingAttempt003Freeze",
            "hostBindingAttempt004Closure", "hostBindingAttempt004Terminal", "hostBindingAttempt004Freeze",
            "readinessAttempt004Terminal", "readinessAttempt004Audit", "loadExecutionAttempt002Failure",
            "guardAttempt001Failure", "guardAttempt001Freeze", "guardAttempt002KnownAnswer",
            "guardAttempt002Terminal", "guardAttempt002Freeze",
        )
    }
    check(
        "FREEZE::HOST_BOUND_STATUS_CONTRACT_MANIFEST_AND_RECEIPTS_READ_ONLY",
        all(read_only_bindings.values()),
        read_only_bindings,
        {label: True for label in read_only_bindings},
        domain="freeze-state",
        reason="A current Status v34/supervisor v3.1/contract v3.3/manifest v3.3 binding or retained PowerShell/guard/readiness evidence file is no longer read-only.",
    )

    status34 = load_json(EXPECTED_HASHES["statusV34"][0])
    status34_binding = status34.get("supervisorManifestAcceptanceGuardCorrigendumAttempt002", {})
    status34_assets = status34.get("adoptedCorrectedBindings", {})
    status34_auth = status34.get("authorizationState", {})
    status34_science = status34.get("scientificBoundary", {})
    status34_ok = (
        status34.get("schema") == "gate14re-me-status-v34"
        and status34.get("version") == 34
        and status34.get("status") == "SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM_ATTEMPT_002_PASS_EXECUTION_READINESS_RECHECK_AUTHORIZATION_PENDING"
        and status34_binding.get("passed") is True
        and status34_binding.get("terminalReceiptSha256") == EXPECTED_HASHES["guardAttempt002Terminal"][1]
        and status34_binding.get("knownAnswerSha256") == EXPECTED_HASHES["guardAttempt002KnownAnswer"][1]
        and status34_binding.get("checksPassed") == 304
        and status34_binding.get("negativeCasesRejected") == 6
        and status34_assets.get("supervisorSha256") == EXPECTED_HASHES["supervisorV31"][1]
        and status34_assets.get("executionContractSha256") == EXPECTED_HASHES["executionContractV33"][1]
        and status34_assets.get("implementationManifestSha256") == EXPECTED_HASHES["implementationManifestV33"][1]
        and status34_assets.get("manifestGeneration") == 4
        and status34_assets.get("executionReadinessStatus") == "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE"
        and all(status34_auth.get(field) is False for field in (
            "readinessRecheckAuthorized", "newQualificationExecutionAttemptAuthorized",
            "qualificationExecutionAuthorized", "unityInvocationAuthorized",
            "qualificationMeasuredRootCreationAuthorized", "deliveryRootCreationAuthorized",
            "formalCollectionAuthorized", "formalAnalysisAuthorized", "rankingAuthorized",
            "weightingAuthorized", "winnerAdjudicationAuthorized",
        ))
        and status34_science.get("unityInvocationCount") == 0
        and status34_science.get("qualificationObservationCount") == 0
        and status34_science.get("formalObservationCount") == 0
    )
    check(
        "STATUS::V34_GUARD_CORRECTED_PENDING_READINESS_STATE",
        status34_ok,
        {"schema": status34.get("schema"), "version": status34.get("version"), "status": status34.get("status"), "authorizationState": status34_auth, "guardCorrigendum": status34_binding, "adoptedCorrectedBindings": status34_assets},
        "Status v34 guard corrigendum PASS with supervisor v3.1, contract/manifest v3.3, readiness awaiting authorization, and qualification execution/root creation/Unity unauthorized",
        domain="status",
        reason="Status v34 no longer expresses the exact guard-corrected pre-readiness state.",
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

    contract = load_json(EXPECTED_HASHES["executionContractV33"][0])
    contract_header_ok = (
        contract.get("schema") == "gate14re-me-load-qualification-execution-contract-v3"
        and contract.get("version") == 3
        and contract.get("revision") == "3.3"
        and contract.get("status") == "FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED"
        and contract.get("entryPoint", {}).get("supervisorSha256") == EXPECTED_HASHES["supervisorV31"][1]
        and contract.get("entryPoint", {}).get("runnerSha256") == EXPECTED_HASHES["runnerV2"][1]
        and contract.get("entryPoint", {}).get("runnerExecuteMethod") == "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run"
        and contract.get("entryPoint", {}).get("receiptGeneration") == 2
        and contract.get("entryPoint", {}).get("supervisorGeneration") == 3
        and contract.get("entryPoint", {}).get("supervisorRevision") == "3.1"
    )
    check(
        "CONTRACT::V3_3_HEADER_ENTRY_POINT_AND_INERT_STATE",
        contract_header_ok,
        {"schema": contract.get("schema"), "status": contract.get("status"), "version": contract.get("version"), "revision": contract.get("revision"), "entryPoint": contract.get("entryPoint")},
        "frozen execution contract v3.3 bound to supervisor-v3.1 and RunnerV2 with receipt generation 2",
        domain="execution-contract",
        reason="Execution contract v3.3 header, revision, status, or entry point drifted.",
    )

    contract_host = contract.get("supervisorHostRuntime", {})
    contract_host_ok = (
        contract.get("hostBindingCorrigendumAuthorizationId") == "gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-003"
        and contract.get("hostBindingCorrigendumAttemptId") == "supervisor-powershell-host-binding-corrigendum-attempt-003"
        and contract_host.get("executablePath") == PINNED_POWERSHELL.as_posix()
        and contract_host.get("sha256") == PINNED_POWERSHELL_SHA256
        and contract_host.get("version") == PINNED_POWERSHELL_VERSION
        and contract_host.get("commandPrefix") == ["-NoLogo", "-NoProfile", "-NonInteractive", "-File"]
        and contract_host.get("requiredCmdlet") == "ConvertFrom-Json"
        and contract_host.get("requiredParameters") == ["Depth", "DateKind"]
        and contract_host.get("requiredInvocationForm") == "ConvertFrom-Json -Depth 100 -DateKind String"
        and contract_host.get("exactExecutablePathHashAndVersionRequired") is True
        and contract_host.get("externalSupervisorLaunchMustUseExactExecutable") is True
        and contract_host.get("mismatchDisposition") == "FAIL_CLOSED_BEFORE_ROOT_CREATION_OR_UNITY_LAUNCH"
    )
    check(
        "CONTRACT::V3_3_EXACT_POWERSHELL_7_6_5_HOST_BINDING",
        contract_host_ok,
        {"authorizationId": contract.get("hostBindingCorrigendumAuthorizationId"), "attemptId": contract.get("hostBindingCorrigendumAttemptId"), "supervisorHostRuntime": contract_host},
        {"executablePath": PINNED_POWERSHELL.as_posix(), "sha256": PINNED_POWERSHELL_SHA256, "version": PINNED_POWERSHELL_VERSION, "commandPrefix": ["-NoLogo", "-NoProfile", "-NonInteractive", "-File"], "failClosedBeforeRootOrUnity": True},
        domain="execution-contract",
        reason="Execution contract v3.3 does not bind the exact frozen PowerShell 7.6.5 host runtime and fail-closed launch policy.",
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
        reason="Execution contract v3.3 does not retain the exact fourteen frozen scientific and terminal bindings.",
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

    guard_authorization_id = "gate14re-me-supervisor-manifest-acceptance-guard-corrigendum-auto-repair-until-pass-263a2c10-45da-4ede-ae8e-684baf3e9057"
    guard_status = "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE"
    contract_guard = contract.get("supervisorManifestAcceptanceGuardCorrigendum", {})
    contract_guard_ok = (
        contract_guard.get("authorizationId") == guard_authorization_id
        and contract_guard.get("attemptId") == "supervisor-manifest-acceptance-guard-corrigendum-attempt-001"
        and contract_guard.get("sourceSupervisorRelativePath") == EXPECTED_HASHES["supervisorV3"][0]
        and contract_guard.get("sourceSupervisorSha256") == EXPECTED_HASHES["supervisorV3"][1]
        and contract_guard.get("correctedSupervisorRelativePath") == EXPECTED_HASHES["supervisorV31"][0]
        and contract_guard.get("correctedSupervisorSha256") == EXPECTED_HASHES["supervisorV31"][1]
        and contract_guard.get("changedPredicateCount") == 1
        and contract_guard.get("acceptedManifestGeneration") == 4
        and contract_guard.get("acceptedManifestSchemaV3") == "gate14re-me-qualification-current-implementation-manifest-v3"
        and contract_guard.get("acceptedExecutionReadinessStatus") == guard_status
        and contract_guard.get("exactPredicateOfflineKnownAnswerRequired") is True
        and all(contract_guard.get(field) is False for field in (
            "scientificDesignChanged", "runnerV2Changed", "compiledAssembliesChanged",
            "inputSchemaChanged", "scheduleChanged", "sealedIdentityChanged",
            "instrumentContractChanged", "algorithmImplementationsChanged",
            "structuralV31Changed", "deliveryV22Changed",
            "qualificationMeasuredRootCreationAuthorized", "deliveryRootCreationAuthorized",
            "qualificationExecutionAuthorized", "formalCollectionAuthorized",
            "formalAnalysisAuthorized", "rankingAuthorized", "winnerAdjudicationAuthorized",
        ))
        and contract_guard.get("unityInvocationCount") == 0
        and "supervisor v3.1" in str(contract.get("activationRule", ""))
        and "v3.3 contract" in str(contract.get("activationRule", ""))
        and "separate offline execution-readiness PASS" in str(contract.get("activationRule", ""))
        and "separate exact-hash qualification execution authorization" in str(contract.get("activationRule", ""))
    )
    check(
        "CONTRACT::SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM_EXACT_AND_INERT",
        contract_guard_ok,
        {"guard": contract_guard, "activationRule": contract.get("activationRule")},
        "one predicate change binds supervisor v3.1 to manifest generation 4/schema/status; scientific assets unchanged; no Unity/root/execution authorization; separate readiness PASS then separate execution authorization required",
        domain="execution-contract",
        reason="Execution contract v3.3 guard corrigendum or its two-gate inert activation rule is incomplete or drifted.",
    )

    manifest = load_json(EXPECTED_HASHES["implementationManifestV33"][0])
    artifacts = list(manifest.get("artifacts", []))
    manifest_audit = declared_file_audit(artifacts)
    artifact_paths = {str(item.get("relativePath")) for item in artifacts}
    manifest_state_ok = (
        manifest.get("manifestGeneration") == 4
        and manifest.get("manifestRevision") == "3.3"
        and manifest.get("manifestSchemaV3") == "gate14re-me-qualification-current-implementation-manifest-v3"
        and manifest.get("executionReadinessStatus") == "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE"
        and manifest.get("legacyRunnerCompatibility", {}).get("runnerV2SourceRemainsByteIdentical") is True
        and manifest.get("legacyRunnerCompatibility", {}).get("compiledAssembliesRemainByteIdentical") is True
        and manifest.get("terminalChainCorrigendum", {}).get("outputReceiptPathsCorrectedToRuntimeV2") is True
        and manifest.get("terminalChainCorrigendum", {}).get("structuralV3ClosesProcessResourcesPersistentPointsAcceptedReceiptsLedgerAndIdentities") is True
        and manifest.get("terminalChainCorrigendum", {}).get("supervisorV3ExplicitFinalProcessOrdinal1147") is True
        and manifest.get("terminalChainCorrigendum", {}).get("deliveryV22PreservesV2DeliveryFormat") is True
        and len(artifacts) == 50
        and manifest_audit["allPathsUnique"]
        and manifest_audit["mismatchCount"] == 0
        and all(relative in artifact_paths for relative, _ in expected_binding_values.values())
        and EXPECTED_HASHES["supervisorV31"][0] in artifact_paths
        and EXPECTED_HASHES["executionContractV33"][0] in artifact_paths
    )
    check(
        "MANIFEST::V3_3_FIFTY_ARTIFACTS_EXACT_TERMINAL_CORRECTED_HOST_BOUND_AND_GUARD_CORRECTED",
        manifest_state_ok,
        {"manifestGeneration": manifest.get("manifestGeneration"), "manifestRevision": manifest.get("manifestRevision"), "executionReadinessStatus": manifest.get("executionReadinessStatus"), "artifactAudit": manifest_audit, "terminalChainCorrigendum": manifest.get("terminalChainCorrigendum")},
        {"manifestGeneration": 4, "manifestRevision": "3.3", "artifactCount": 50, "mismatchCount": 0, "terminalChainCorrected": True, "powerShellHostBound": True, "supervisorManifestGuardCorrected": True},
        domain="implementation-manifest",
        reason="Implementation manifest v3.3 or one of its fifty declared artifacts drifted.",
    )

    manifest_host = manifest.get("supervisorPowerShellHostBindingCorrigendum", {})
    manifest_host_ok = (
        manifest_host.get("authorizationId") == "gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-003"
        and manifest_host.get("attemptId") == "supervisor-powershell-host-binding-corrigendum-attempt-003"
        and manifest_host.get("exactExecutablePath") == PINNED_POWERSHELL.as_posix()
        and manifest_host.get("exactExecutableSha256") == PINNED_POWERSHELL_SHA256
        and manifest_host.get("exactPowerShellVersion") == PINNED_POWERSHELL_VERSION
        and all(manifest_host.get(field) is True for field in (
            "convertFromJsonDepthPresent", "convertFromJsonDateKindPresent", "jsonKnownAnswerPassed",
            "jsonlKnownAnswerPassed", "dateTimeOffsetStringPreservationPassed", "exceptionFailClosedPassed",
            "supervisorParameterBindingPassed",
        ))
        and all(manifest_host.get(field) is False for field in (
            "supervisorV3Changed", "runnerV2Changed", "compiledAssembliesChanged", "scientificAssetsChanged",
            "qualificationExecutionAuthorized",
        ))
        and manifest_host.get("unityInvocationCount") == 0
    )
    check(
        "MANIFEST::V3_3_POWERSHELL_HOST_CORRIGENDUM_EXACT",
        manifest_host_ok,
        manifest_host,
        "attempt-003 exact PowerShell 7.6.5 path/hash/version; JSON/JSONL/DateKind/fail-closed/supervisor binding PASS; no Unity or scientific asset change; execution unauthorized",
        domain="implementation-manifest",
        reason="Implementation manifest v3.3 PowerShell host binding corrigendum is incomplete or drifted.",
    )

    manifest_guard = manifest.get("supervisorManifestAcceptanceGuardCorrigendum", {})
    manifest_guard_ok = (
        manifest.get("schema") == "gate14re-me-qualification-implementation-manifest-v1"
        and manifest.get("status") == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED"
        and manifest_guard.get("authorizationId") == guard_authorization_id
        and manifest_guard.get("attemptId") == "supervisor-manifest-acceptance-guard-corrigendum-attempt-001"
        and manifest_guard.get("retainedFailureRelativePath") == EXPECTED_HASHES["loadExecutionAttempt002Failure"][0]
        and manifest_guard.get("retainedFailureSha256") == EXPECTED_HASHES["loadExecutionAttempt002Failure"][1]
        and manifest_guard.get("sourceSupervisorRelativePath") == EXPECTED_HASHES["supervisorV3"][0]
        and manifest_guard.get("sourceSupervisorSha256") == EXPECTED_HASHES["supervisorV3"][1]
        and manifest_guard.get("correctedSupervisorRelativePath") == EXPECTED_HASHES["supervisorV31"][0]
        and manifest_guard.get("correctedSupervisorSha256") == EXPECTED_HASHES["supervisorV31"][1]
        and manifest_guard.get("changedPredicateCount") == 1
        and manifest_guard.get("acceptedManifestGeneration") == 4
        and manifest_guard.get("acceptedManifestSchemaV3") == "gate14re-me-qualification-current-implementation-manifest-v3"
        and manifest_guard.get("acceptedExecutionReadinessStatus") == guard_status
        and manifest_guard.get("exactPredicateOfflineKnownAnswerRequired") is True
        and all(manifest_guard.get(field) is False for field in (
            "scientificDesignChanged", "runnerV2Changed", "compiledAssembliesChanged",
            "scientificAssetsChanged", "qualificationMeasuredRootCreated", "deliveryRootCreated",
            "readinessRecheckAuthorized", "qualificationExecutionAuthorized",
            "formalCollectionAuthorized", "formalAnalysisAuthorized", "rankingAuthorized",
            "winnerAdjudicationAuthorized",
        ))
        and manifest_guard.get("unityInvocationCount") == 0
        and manifest_guard.get("qualificationObservationCount") == 0
        and manifest_guard.get("formalObservationCount") == 0
    )
    check(
        "MANIFEST::V3_3_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM_EXACT",
        manifest_guard_ok,
        {"compatibilitySchema": manifest.get("schema"), "compatibilityStatus": manifest.get("status"), "guard": manifest_guard},
        "legacy RunnerV2 compatibility fields retained; exactly one supervisor predicate corrected; manifest generation/schema/readiness accepted; scientific assets unchanged and execution unauthorized",
        domain="implementation-manifest",
        reason="Implementation manifest v3.3 guard corrigendum, retained failure binding, compatibility fields, or authorization boundary is incomplete or drifted.",
    )

    expected_predicate = (
        "$manifest.manifestGeneration -eq 4 -and "
        "$manifest.manifestSchemaV3 -eq 'gate14re-me-qualification-current-implementation-manifest-v3' -and "
        "$manifest.executionReadinessStatus -eq 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE'"
    )
    expected_condition_line = (
        f"Require-Condition ({expected_predicate}) "
        "'Authoritative implementation manifest v3 state is not adopted.'"
    )
    source_supervisor_lines = project_file(EXPECTED_HASHES["supervisorV3"][0]).read_text(encoding="utf-8-sig").splitlines()
    corrected_supervisor_lines = project_file(EXPECTED_HASHES["supervisorV31"][0]).read_text(encoding="utf-8-sig").splitlines()
    maximum_supervisor_lines = max(len(source_supervisor_lines), len(corrected_supervisor_lines))
    changed_line_numbers = [
        index + 1
        for index in range(maximum_supervisor_lines)
        if (source_supervisor_lines[index] if index < len(source_supervisor_lines) else None)
        != (corrected_supervisor_lines[index] if index < len(corrected_supervisor_lines) else None)
    ]
    line_540 = corrected_supervisor_lines[539].strip() if len(corrected_supervisor_lines) >= 540 else None
    exact_predicate_source_ok = (
        changed_line_numbers == [540]
        and line_540 == expected_condition_line
        and "\n".join(corrected_supervisor_lines).count(expected_condition_line) == 1
    )
    check(
        "SUPERVISOR::V3_1_EXACT_LINE_540_PREDICATE_AND_SINGLE_LINE_DIFF",
        exact_predicate_source_ok,
        {"changedLineNumbers": changed_line_numbers, "line540": line_540, "exactConditionCount": "\n".join(corrected_supervisor_lines).count(expected_condition_line)},
        {"changedLineNumbers": [540], "line540": expected_condition_line, "exactConditionCount": 1},
        domain="supervisor-acceptance-guard",
        reason="Supervisor v3.1 is not a one-line line-540 correction with the exact frozen manifest acceptance predicate.",
    )

    def accepts_manifest(candidate: Mapping[str, Any]) -> bool:
        return (
            candidate.get("manifestGeneration") == 4
            and candidate.get("manifestSchemaV3") == "gate14re-me-qualification-current-implementation-manifest-v3"
            and candidate.get("executionReadinessStatus") == guard_status
        )

    manifest_v32 = load_json(EXPECTED_HASHES["implementationManifestV32"][0])
    negative_guard_fixtures: dict[str, dict[str, Any]] = {
        "wrongGeneration": {**manifest, "manifestGeneration": 3},
        "wrongSchema": {**manifest, "manifestSchemaV3": "wrong-schema"},
        "staleStatus": {**manifest, "executionReadinessStatus": "FROZEN_CURRENT_IMPLEMENTATION_COMPILED_AND_TERMINAL_CHAIN_CORRECTED_OFFLINE"},
        "missingGeneration": {key: value for key, value in manifest.items() if key != "manifestGeneration"},
        "missingSchema": {key: value for key, value in manifest.items() if key != "manifestSchemaV3"},
        "missingStatus": {key: value for key, value in manifest.items() if key != "executionReadinessStatus"},
    }
    negative_guard_results = {label: accepts_manifest(value) for label, value in negative_guard_fixtures.items()}
    predicate_semantics_ok = (
        accepts_manifest(manifest_v32)
        and accepts_manifest(manifest)
        and all(result is False for result in negative_guard_results.values())
    )
    check(
        "SUPERVISOR::EXACT_MANIFEST_ACCEPTANCE_PREDICATE_POSITIVE_AND_NEGATIVE_SEMANTICS",
        predicate_semantics_ok,
        {"manifestV32Accepted": accepts_manifest(manifest_v32), "manifestV33Accepted": accepts_manifest(manifest), "negativeFixtureAcceptance": negative_guard_results},
        {"manifestV32Accepted": True, "manifestV33Accepted": True, "negativeFixtureAcceptance": {label: False for label in negative_guard_fixtures}},
        domain="supervisor-acceptance-guard",
        reason="The corrected predicate does not accept both authoritative generation-4 manifests or fail closed for every frozen negative case.",
    )

    guard_known = load_json(EXPECTED_HASHES["guardAttempt002KnownAnswer"][0])
    guard_terminal = load_json(EXPECTED_HASHES["guardAttempt002Terminal"][0])
    guard_freeze = load_json(EXPECTED_HASHES["guardAttempt002Freeze"][0])
    expected_negative_cases = [
        "wrong generation", "wrong schema", "stale readiness status",
        "missing generation", "missing schema", "missing readiness status",
    ]
    known_answer_ok = (
        guard_known.get("schema") == "gate14re-me-supervisor-manifest-acceptance-guard-corrigendum-exact-predicate-known-answer-receipt-v1"
        and guard_known.get("status") == "PASS_EXACT_SUPERVISOR_MANIFEST_ACCEPTANCE_PREDICATE_OFFLINE"
        and guard_known.get("passed") is True
        and guard_known.get("terminal") is True
        and guard_known.get("authoritativeManifestV32AcceptedBySourcePredicate") is False
        and guard_known.get("authoritativeManifestV32AcceptedByCorrectedPredicate") is True
        and guard_known.get("successorManifestV33AcceptedByCorrectedPredicate") is True
        and guard_known.get("negativeCasesRejected") == expected_negative_cases
        and guard_known.get("checksPassed") == 304
        and guard_terminal.get("status") == "PASS_FROZEN_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM"
        and guard_terminal.get("passed") is True
        and guard_terminal.get("terminal") is True
        and guard_terminal.get("exactPredicateKnownAnswer", {}).get("sha256") == EXPECTED_HASHES["guardAttempt002KnownAnswer"][1]
        and guard_terminal.get("exactPredicateKnownAnswer", {}).get("checksPassed") == 304
        and guard_terminal.get("exactPredicateKnownAnswer", {}).get("negativeCasesRejected") == 6
        and guard_terminal.get("frozenSuccessorBindings", {}).get("supervisorSha256") == EXPECTED_HASHES["supervisorV31"][1]
        and guard_terminal.get("frozenSuccessorBindings", {}).get("executionContractSha256") == EXPECTED_HASHES["executionContractV33"][1]
        and guard_terminal.get("frozenSuccessorBindings", {}).get("implementationManifestSha256") == EXPECTED_HASHES["implementationManifestV33"][1]
        and guard_terminal.get("readinessRecheckAuthorized") is False
        and guard_terminal.get("qualificationExecutionAuthorized") is False
        and guard_freeze.get("status") == "FROZEN_TERMINAL_PASS_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM"
        and guard_freeze.get("predicateEvidence", {}).get("checksPassed") == 304
        and guard_freeze.get("predicateEvidence", {}).get("negativeCasesRejected") == 6
        and guard_freeze.get("scientificBoundary", {}).get("unityInvocationCount") == 0
    )
    check(
        "CORRIGENDUM::ATTEMPT_002_304_CHECK_TERMINAL_PASS_AND_FREEZE_CLOSED",
        known_answer_ok,
        {"knownAnswerStatus": guard_known.get("status"), "checksPassed": guard_known.get("checksPassed"), "negativeCasesRejected": guard_known.get("negativeCasesRejected"), "terminalStatus": guard_terminal.get("status"), "frozenSuccessorBindings": guard_terminal.get("frozenSuccessorBindings"), "freezeStatus": guard_freeze.get("status")},
        "304-check exact-predicate known-answer PASS; six negative cases rejected; supervisor v3.1/contract v3.3/manifest v3.3 bound; terminal and read-only freeze PASS; execution still unauthorized",
        domain="supervisor-acceptance-guard",
        reason="The supervisor-manifest acceptance guard corrigendum PASS chain is incomplete, drifted, or no longer frozen.",
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
    runtime_ok = (
        runtime_ok
        and runtime_bindings.get("powershellExecutable") == PINNED_POWERSHELL.as_posix()
        and runtime_bindings.get("powershellExecutableSha256") == PINNED_POWERSHELL_SHA256
        and runtime_bindings.get("powershellVersion") == PINNED_POWERSHELL_VERSION
        and runtime_bindings.get("powershellSupervisorCommandPrefix") == ["-NoLogo", "-NoProfile", "-NonInteractive", "-File"]
    )
    check(
        "RUNTIME::UNITY_PYTHON_POWERSHELL_EXECUTABLE_HASHES",
        runtime_ok,
        runtime_observed,
        "Unity, Python, and exact PowerShell 7.6.5 executable identities match the v3.3 implementation manifest",
        domain="runtime",
        reason="A frozen executable identity drifted.",
    )

    host_probe = powershell_host_probe()
    host_probe_path = pathlib.Path(str(host_probe.get("processPath", ""))).resolve()
    pinned_host_path = PINNED_POWERSHELL.resolve()
    host_probe_ok = (
        host_probe_path == pinned_host_path
        and sha256_file(pinned_host_path) == PINNED_POWERSHELL_SHA256
        and host_probe.get("version") == PINNED_POWERSHELL_VERSION
        and host_probe.get("convertFromJsonDepth") is True
        and host_probe.get("convertFromJsonDateKind") is True
        and host_probe.get("dateKindStringPreserved") is True
    )
    check(
        "RUNTIME::LIVE_READ_ONLY_POWERSHELL_7_6_5_HOST_PROBE",
        host_probe_ok,
        {**host_probe, "resolvedProcessPath": host_probe_path.as_posix(), "actualSha256": sha256_file(pinned_host_path) if pinned_host_path.is_file() else None},
        {"resolvedProcessPath": pinned_host_path.as_posix(), "sha256": PINNED_POWERSHELL_SHA256, "version": PINNED_POWERSHELL_VERSION, "ConvertFromJsonDepth": True, "ConvertFromJsonDateKind": True, "DateKindStringPreserved": True},
        domain="runtime",
        reason="The live read-only PowerShell probe did not execute under the exact frozen 7.6.5 host or lacked the required JSON semantics.",
    )

    host_known = load_json(EXPECTED_HASHES["hostBindingAttempt003KnownAnswer"][0])
    host_terminal = load_json(EXPECTED_HASHES["hostBindingAttempt003Terminal"][0])
    host_freeze = load_json(EXPECTED_HASHES["hostBindingAttempt003Freeze"][0])
    host_closure = load_json(EXPECTED_HASHES["hostBindingAttempt004Closure"][0])
    host_closure_terminal = load_json(EXPECTED_HASHES["hostBindingAttempt004Terminal"][0])
    host_closure_freeze = load_json(EXPECTED_HASHES["hostBindingAttempt004Freeze"][0])
    known_checks = list(host_known.get("checks", []))
    known_scope = host_known.get("scopeEvidence", {})
    host_evidence_ok = (
        host_known.get("status") == "PASS_POWERSHELL_7_6_5_JSON_JSONL_FAIL_CLOSED_AND_SUPERVISOR_BINDING"
        and host_known.get("passed") is True
        and len(known_checks) == 222
        and all(item.get("passed") is True for item in known_checks)
        and host_known.get("hostRuntime", {}).get("processPath") == PINNED_POWERSHELL.as_posix()
        and host_known.get("hostRuntime", {}).get("sha256") == PINNED_POWERSHELL_SHA256
        and host_known.get("hostRuntime", {}).get("version") == PINNED_POWERSHELL_VERSION
        and host_known.get("hostRuntime", {}).get("convertFromJsonDepth") is True
        and host_known.get("hostRuntime", {}).get("convertFromJsonDateKind") is True
        and host_terminal.get("status") == "PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING"
        and host_terminal.get("passed") is True
        and host_terminal.get("terminal") is True
        and host_terminal.get("executionContract", {}).get("sha256") == EXPECTED_HASHES["executionContractV32"][1]
        and host_terminal.get("implementationManifest", {}).get("sha256") == EXPECTED_HASHES["implementationManifestV32"][1]
        and host_terminal.get("exactHostRuntime", {}).get("executablePath") == PINNED_POWERSHELL.as_posix()
        and host_terminal.get("exactHostRuntime", {}).get("sha256") == PINNED_POWERSHELL_SHA256
        and host_terminal.get("exactHostRuntime", {}).get("version") == PINNED_POWERSHELL_VERSION
        and host_freeze.get("status") == "FROZEN_TERMINAL_PASS_EVIDENCE"
        and host_closure.get("status") == "PASS_ATTEMPT_003_CONTENT_PRESERVED_AND_READONLY_FREEZE_CLOSED"
        and host_closure.get("passed") is True
        and host_closure.get("attempt003AllReadOnly") is True
        and host_closure.get("retainedBindings", {}).get("executionContractV32Sha256") == EXPECTED_HASHES["executionContractV32"][1]
        and host_closure.get("retainedBindings", {}).get("implementationManifestV32Sha256") == EXPECTED_HASHES["implementationManifestV32"][1]
        and host_closure.get("retainedBindings", {}).get("statusV31Sha256") == EXPECTED_HASHES["statusV31"][1]
        and host_closure_terminal.get("status") == "PASS_FROZEN_POWERSHELL_HOST_BINDING_READONLY_CLOSURE"
        and host_closure_terminal.get("passed") is True
        and host_closure_freeze.get("status") == "FROZEN_TERMINAL_PASS_READONLY_CLOSURE_EVIDENCE"
        and all(known_scope.get(field) == 0 for field in (
            "unityInvocationCount", "instrumentInvocationCount", "oracleInvocationCount",
            "emptyBoundaryInvocationCount", "algorithmLaneExecutionCount", "qualificationObservationCount",
            "formalObservationCount",
        ))
        and all(known_scope.get(field) is False for field in (
            "formalCollectionPerformed", "formalAnalysisPerformed", "rankingPerformed", "weightingPerformed",
            "winnerAdjudicationPerformed",
        ))
    )
    check(
        "HOST_BINDING::ATTEMPT_003_PASS_AND_ATTEMPT_004_READONLY_CLOSURE",
        host_evidence_ok,
        {
            "knownAnswerStatus": host_known.get("status"),
            "knownAnswerChecks": len(known_checks),
            "knownAnswerFailedChecks": sum(1 for item in known_checks if item.get("passed") is not True),
            "terminalStatus": host_terminal.get("status"),
            "freezeStatus": host_freeze.get("status"),
            "closureStatus": host_closure.get("status"),
            "closureTerminalStatus": host_closure_terminal.get("status"),
            "closureFreezeStatus": host_closure_freeze.get("status"),
            "hostRuntime": host_known.get("hostRuntime"),
            "scopeEvidence": known_scope,
        },
        "222/222 PowerShell host known-answer checks PASS; terminal PASS; all attempt-003 evidence read-only closed by attempt-004; exact v3.2 contract/manifest/Status v31 bindings; no Unity, observation, analysis, ranking, weighting, or winner activity",
        domain="host-binding-evidence",
        reason="The retained PowerShell 7.6.5 host binding PASS or its independent read-only closure is incomplete or drifted.",
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

    supervisor_rel = EXPECTED_HASHES["supervisorV31"][0]
    supervisor_path = project_file(supervisor_rel)
    supervisor_text = read_text(supervisor_rel)
    ps_errors = powershell_parse_errors(supervisor_path)
    check(
        "SUPERVISOR::V3_1_POWERSHELL_AST_CLEAN",
        not ps_errors,
        {"parseErrors": ps_errors},
        {"parseErrors": []},
        domain="supervisor-v3.1",
        reason="Supervisor-v3.1 no longer parses as PowerShell.",
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
        "SUPERVISOR::V3_1_STATIC_SERIAL_FRESH_1147_TERMINAL_STATE_MACHINE",
        supervisor_flow_ok,
        {"orderedTokenPositions": dict(zip(ordered_tokens, positions)), "processOrdinalInitialized": "$processOrdinal = 0" in supervisor_text, "singleIncrementSiteCount": supervisor_text.count("$script:processOrdinal++"), "parallelPrimitivesAbsent": all(token not in supervisor_text for token in ("Start-Job", "Start-ThreadJob", "ForEach-Object -Parallel")), "terminationSignalsAbsent": "Stop-Process" not in supervisor_text and ".Kill(" not in supervisor_text},
        "ordered instrument/oracle/empty/lane phases; one ordinal increment per fresh process; exact final 1147 assertion; structural then delivery; no parallelism, retry, or signal",
        domain="supervisor-v3.1",
        reason="Supervisor-v3.1 static control flow no longer proves the required serial fresh-process and terminal-chain ordering.",
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
        reason="Execution contract v3.3 post-acquisition terminal chain is incomplete or reordered.",
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
        "RETENTION::ALL_BOUND_PRIOR_ATTEMPTS_BYTE_AND_ATTRIBUTE_IDENTICAL",
        all(item["identical"] for item in retention_comparison.values()),
        retention_comparison,
        "all retained attempt inventories, hashes, lengths, paths, and read-only attributes are identical before and after",
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
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-authorization-receipt-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "status": "AUTHORIZED_READ_ONLY_NO_UNITY_READINESS_RECHECK_UNTIL_FIRST_PASS",
        "authorizedAtUtc": started,
        "authorizationSource": "direct user request",
        "userAuthorizationTextExact": USER_AUTHORIZATION_TEXT,
        "attemptSequenceScope": {
            "firstAttemptId": ATTEMPT_ID,
            "subsequentFreshAttemptsAuthorizedAfterFrozenFailure": True,
            "sameStageOnly": True,
            "stopImmediatelyAtFirstTerminalPass": True,
            "qualificationExecutionAttemptAuthorized": False,
        },
        "allowed": [
            "create and freeze this independent attempt-005 evidence directory",
            "read and hash the explicitly bound frozen source, contract, status, planning, runtime, identity and prior-attempt evidence",
            "parse Python/PowerShell/JSON/JSONL statically without executing the qualification supervisor or algorithm code",
            "inspect read-only host/process/storage metadata",
            "after any frozen failed recheck, repair only the readiness audit implementation/evidence closure and create a fresh sequential recheck attempt under this same authorization",
            "freeze a terminal readiness PASS receipt and Status v35 only if every check passes, then stop and request separate qualification-execution authorization",
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
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-stage-contract-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "status": "FROZEN_READ_ONLY_NO_UNITY_RECHECK_CONTRACT",
        "createdAtUtc": started,
        "authoritativeInputStatus": {"relativePath": EXPECTED_HASHES["statusV34"][0], "sha256": EXPECTED_HASHES["statusV34"][1]},
        "authoritativeSupervisor": {"relativePath": EXPECTED_HASHES["supervisorV31"][0], "sha256": EXPECTED_HASHES["supervisorV31"][1]},
        "authoritativeExecutionContract": {"relativePath": EXPECTED_HASHES["executionContractV33"][0], "sha256": EXPECTED_HASHES["executionContractV33"][1]},
        "authoritativeImplementationManifest": {"relativePath": EXPECTED_HASHES["implementationManifestV33"][0], "sha256": EXPECTED_HASHES["implementationManifestV33"][1]},
        "authoritativeGuardCorrigendumTerminalReceipt": {"relativePath": EXPECTED_HASHES["guardAttempt002Terminal"][0], "sha256": EXPECTED_HASHES["guardAttempt002Terminal"][1]},
        "authoritativeGuardPredicateKnownAnswer": {"relativePath": EXPECTED_HASHES["guardAttempt002KnownAnswer"][0], "sha256": EXPECTED_HASHES["guardAttempt002KnownAnswer"][1], "checksPassed": 304},
        "authoritativePowerShellHostRuntime": {"executablePath": PINNED_POWERSHELL.as_posix(), "sha256": PINNED_POWERSHELL_SHA256, "version": PINNED_POWERSHELL_VERSION},
        "retainedAttempts": RETAINED_ATTEMPTS,
        "auditMode": "READ_ONLY_STATIC_AND_EXISTING_OFFLINE_KNOWN_ANSWER",
        "passRule": "Every recorded check must pass; otherwise freeze this attempt, do not create Status v35, and use a new sequential attempt under the same authorization until the first PASS.",
        "claimBoundary": "PASS establishes prospective execution readiness of the frozen chain only. It does not assert that any of the 1,147 qualification processes or any qualification observation has run.",
        "mutationBoundary": [str(ATTEMPT_REL), str(STATUS_35_REL) + " on PASS only"],
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
        "schema": "gate14re-me-qualification-execution-readiness-recheck-audit-v5",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "designId": "gate14re-me-load-qualification-planning-v2",
        "authorizationId": AUTHORIZATION_ID,
        "attemptId": ATTEMPT_ID,
        "startedAtUtc": started,
        "completedAtUtc": completed,
        "mode": "READ_ONLY_NO_UNITY_STATIC_AND_EXISTING_OFFLINE_EVIDENCE",
        "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V5_GUARD_CORRECTED_HOST_BOUND" if passed else "FAIL_CLOSED_QUALIFICATION_EXECUTION_READINESS_RECHECK_V5_GUARD_CORRECTED_HOST_BOUND",
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
    audit_path = write_json_exclusive(ATTEMPT_ROOT / "readiness-recheck-audit.v5.json", audit)

    status_path: pathlib.Path | None = None
    adoption_path: pathlib.Path | None = None
    if passed:
        terminal_receipt = {
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "designId": "gate14re-me-load-qualification-planning-v2",
            "authorizationId": AUTHORIZATION_ID,
            "attemptId": ATTEMPT_ID,
            "status": "PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V5_GUARD_CORRECTED_HOST_BOUND_EXECUTION_UNAUTHORIZED",
            "passed": True,
            "terminal": True,
            "completedAtUtc": completed,
            "authoritativeBindings": {
                "statusV34": {"relativePath": EXPECTED_HASHES["statusV34"][0], "sha256": EXPECTED_HASHES["statusV34"][1]},
                "supervisorV31": {"relativePath": EXPECTED_HASHES["supervisorV31"][0], "sha256": EXPECTED_HASHES["supervisorV31"][1]},
                "executionContractV33": {"relativePath": EXPECTED_HASHES["executionContractV33"][0], "sha256": EXPECTED_HASHES["executionContractV33"][1]},
                "implementationManifestV33": {"relativePath": EXPECTED_HASHES["implementationManifestV33"][0], "sha256": EXPECTED_HASHES["implementationManifestV33"][1]},
                "guardAttempt002KnownAnswer": {"relativePath": EXPECTED_HASHES["guardAttempt002KnownAnswer"][0], "sha256": EXPECTED_HASHES["guardAttempt002KnownAnswer"][1], "checksPassed": 304},
                "guardAttempt002Terminal": {"relativePath": EXPECTED_HASHES["guardAttempt002Terminal"][0], "sha256": EXPECTED_HASHES["guardAttempt002Terminal"][1]},
                "powerShellHostRuntime": {"executablePath": PINNED_POWERSHELL.as_posix(), "sha256": PINNED_POWERSHELL_SHA256, "version": PINNED_POWERSHELL_VERSION},
                "hostBindingAttempt003Terminal": {"relativePath": EXPECTED_HASHES["hostBindingAttempt003Terminal"][0], "sha256": EXPECTED_HASHES["hostBindingAttempt003Terminal"][1]},
                "hostBindingAttempt004ReadOnlyClosure": {"relativePath": EXPECTED_HASHES["hostBindingAttempt004Closure"][0], "sha256": EXPECTED_HASHES["hostBindingAttempt004Closure"][1]},
            },
            "readinessAudit": {"relativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(), "sha256": sha256_file(audit_path), "totalChecks": len(checks), "passedChecks": len(checks), "failedChecks": 0},
            "resolvedRetainedAttempt002Blockers": [
                "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT",
                "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE",
                "SUPERVISOR::EXACT_MANIFEST_ACCEPTANCE_PREDICATE",
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
                "newQualificationExecutionAttemptAuthorized": False,
                "qualificationExecutionAuthorized": False,
                "unityInvocationAuthorized": False,
                "qualificationMeasuredRootCreationAuthorized": False,
                "deliveryRootCreationAuthorized": False,
                "formalCollectionAuthorized": False,
                "formalAnalysisAuthorized": False,
                "rankingAuthorized": False,
                "weightingAuthorized": False,
                "winnerAdjudicationAuthorized": False,
                "separateExecutionAuthorizationRequired": True,
            },
        }
        terminal_path = write_json_exclusive(ATTEMPT_ROOT / "terminal-readiness-receipt.v1.json", terminal_receipt)

        status35 = {
            "schema": "gate14re-me-status-v35",
            "studyId": "Gate14Re-ME",
            "status": "QUALIFICATION_EXECUTION_READINESS_RECHECK_PASS_EXECUTION_AUTHORIZATION_PENDING",
            "version": 35,
            "updatedAtUtc": completed,
            "previousVersionedStatus": {"relativePath": EXPECTED_HASHES["statusV34"][0], "sha256": EXPECTED_HASHES["statusV34"][1], "retained": True, "reclassified": False},
            "readinessRecheckAttempt005": {
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
                "supervisorV31Sha256": EXPECTED_HASHES["supervisorV31"][1],
                "executionContractV33Sha256": EXPECTED_HASHES["executionContractV33"][1],
                "implementationManifestV33Sha256": EXPECTED_HASHES["implementationManifestV33"][1],
                "guardAttempt002KnownAnswerSha256": EXPECTED_HASHES["guardAttempt002KnownAnswer"][1],
                "guardAttempt002TerminalSha256": EXPECTED_HASHES["guardAttempt002Terminal"][1],
                "powerShellHostRuntimePath": PINNED_POWERSHELL.as_posix(),
                "powerShellHostRuntimeSha256": PINNED_POWERSHELL_SHA256,
                "powerShellHostRuntimeVersion": PINNED_POWERSHELL_VERSION,
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
            "nextRequiredAction": "Obtain a separate authorization for one new qualification execution attempt bound to this attempt-005 readiness receipt, supervisor v3.1, execution contract v3.3, implementation manifest v3.3, guard-corrigendum terminal receipt, and the exact PowerShell 7.6.5 host runtime before creating any qualification measured/delivery root or starting Unity. Formal collection, formal analysis, cross-algorithm effects, ranking, weighting, and winner adjudication remain separately unauthorized.",
        }
        status_path = write_json_exclusive(project_file(STATUS_35_REL), status35)
        adoption = {
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-status-adoption-receipt-v1",
            "studyId": "Gate14Re-ME",
            "authorizationId": AUTHORIZATION_ID,
            "status": "PASS_STATUS_V35_ADOPTED_NEW_QUALIFICATION_EXECUTION_AUTHORIZATION_PENDING",
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
            "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-failure-receipt-v1",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "designId": "gate14re-me-load-qualification-planning-v2",
            "authorizationId": AUTHORIZATION_ID,
            "attemptId": ATTEMPT_ID,
            "status": "FAILED_CLOSED_QUALIFICATION_EXECUTION_READINESS_RECHECK_V5_GUARD_CORRECTED_HOST_BOUND",
            "passed": False,
            "terminal": True,
            "completedAtUtc": completed,
            "readinessAudit": {"relativePath": audit_path.relative_to(PROJECT_ROOT).as_posix(), "sha256": sha256_file(audit_path), **audit["summary"]},
            "hardStopReasons": hard_stop_reasons,
            "disposition": {
                "qualificationExecutionAuthorized": False,
                "measuredOrDeliveryRootCreationAllowed": False,
                "unityRestartOrRetryAllowed": False,
                "newReadinessRecheckAttemptUnderSameAuthorizationAllowed": True,
                "formalCollectionAnalysisRankingOrWinnerAllowed": False,
                "statusV35Created": False,
            },
        }
        write_json_exclusive(ATTEMPT_ROOT / "failure-receipt.v1.json", failure)

    manifest_items: list[dict[str, Any]] = []
    for path in sorted((p for p in ATTEMPT_ROOT.iterdir() if p.is_file() and p.name != "freeze-manifest.v1.json"), key=lambda p: p.name.lower()):
        manifest_items.append({"role": "attempt-evidence", "relativePath": path.relative_to(PROJECT_ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    if status_path is not None:
        manifest_items.append({"role": "adopted-status-v35", "relativePath": status_path.relative_to(PROJECT_ROOT).as_posix(), "bytes": status_path.stat().st_size, "sha256": sha256_file(status_path)})
    freeze_manifest = {
        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-freeze-manifest-v1",
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
        "statusV35Sha256": sha256_file(status_path) if status_path is not None else None,
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
                        "schema": "gate14re-me-qualification-execution-readiness-recheck-attempt-005-emergency-failure-v1",
                        "studyId": "Gate14Re-ME",
                        "authorizationId": AUTHORIZATION_ID,
                        "status": "FAILED_CLOSED_AUDIT_TOOL_EXCEPTION",
                        "completedAtUtc": utc_now(),
                        "exceptionType": type(exc).__name__,
                        "exception": str(exc),
                        "qualificationExecutionAuthorized": False,
                    },
                )
                freeze_targets = [path for path in ATTEMPT_ROOT.rglob("*") if path.is_file()]
                status_candidate = project_file(STATUS_35_REL)
                if status_candidate.is_file():
                    freeze_targets.append(status_candidate)
                for path in freeze_targets:
                    try:
                        os.chmod(path, stat.S_IREAD)
                    except Exception:
                        pass
            except Exception:
                pass
        print(json.dumps({"status": "FAILED_CLOSED_AUDIT_TOOL_EXCEPTION", "exceptionType": type(exc).__name__, "exception": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(3)
