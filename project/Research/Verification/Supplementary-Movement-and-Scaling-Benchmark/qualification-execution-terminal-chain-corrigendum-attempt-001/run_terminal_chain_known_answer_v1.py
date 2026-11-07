#!/usr/bin/env python3
"""Offline-only terminal-chain known-answer for Gate14Re-ME.

Creates a synthetic package solely inside this verification attempt, exercises
structural-v3 and the delivery-v2.1 schema-v3 adapter, and proves selected
terminal-chain omissions fail closed.  It never launches Unity or a planner.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List


PROJECT = Path(__file__).resolve().parents[4]
ATTEMPT = Path(__file__).resolve().parent
TOOLS = PROJECT / "Research/Gate14Re-ME/Tools"
sys.path.insert(0, str(TOOLS))

import gate14re_me_qualification_delivery_v2_1 as delivery  # noqa: E402
import gate14re_me_qualification_structural_v3 as structural  # noqa: E402


SCHEMA_PATH = PROJECT / "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json"
SCHEMA_SHA = "e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c"
D3_PATH = PROJECT / "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json"
D3_SHA = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"
RUNTIME_PATH = PROJECT / "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json"
RUNTIME_SHA = "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e"
STRUCTURAL_PATH = TOOLS / "gate14re_me_qualification_structural_v3.py"
STRUCTURAL_SHA = "99ac9391c6eea10d6d9aec6de4e21b36a990868f38986cbf124390289d9bc50e"
DELIVERY_PATH = TOOLS / "gate14re_me_qualification_delivery_v2_1.py"
DELIVERY_SHA = "88815a726db97c027079857a3a06e06f1981302ae6c83b9ba05d085d0f198c39"
SUPERVISOR_PATH = PROJECT / "Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3.ps1"
SUPERVISOR_SHA = "e672d2bc3e584192d1f9850ed2bb76538ba11fead80e1ce94670febd9fb45035"
CONTRACT_PATH = PROJECT / "Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3.json"
CONTRACT_SHA = "cdf05e68556899a640a99a7f793780020fd8b97e33bc257011d52720800e385e"
MANIFEST_PATH = PROJECT / "Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3.json"
MANIFEST_SHA = "ad3405e7c2c210ac6fe4b4ee54b82a7e532a36c240bd5744ab46c27173998c0f"
IDENTITY_SHA = "f5cb5febb214a520ad88fe5b592c1688ccae291ee8059615a90d1badff5c302c"
BASELINE_RAW = PROJECT / (
    "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/"
    "repair-cycle-001/synthetic-fixture/raw-package"
)
SOURCE_RELATIVE = (
    "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001/"
    "repair-cycle-001/synthetic-source/synthetic-input-source.v1.json"
)
SOURCE_SHA = "1db49bf411a8e1b8915091aacad53686f9e0a37fde55877bdc212d7ec7d76729"
WORK = ATTEMPT / "known-answer-work"
RAW = WORK / "synthetic-raw-package"
DELIVERY = WORK / "synthetic-delivery"
NEGATIVE_DELIVERY = WORK / "negative-delivery-missing-product"

RESERVED_ROOTS = (
    PROJECT / "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001",
    PROJECT / "Research/Exports/Gate14Re-ME/load-qualification/attempt-001",
    PROJECT / "Research/FormalRuns/Gate14Re-ME",
)

PRESERVED = {
    "Research/Verification/Gate14Re-ME/qualification-execution-readiness-freeze-attempt-002/failure-receipt.v1.json": "ac58c5110fcf500e520ba8dcac7406c05601f12e99595cf1a4a3cb9c496a3e9b",
    "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json": "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v2.py": "daa1fc48077cc0cb8c62221956355a35c74e8b946660b683f7178e2072e9bc0e",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2.py": "5e9f8d8c3403321fb9e1b2b3f67fef00a963bf85f25c66d98bc2c41971434ec4",
    "Research/Gate14Re-ME/Execution/v2/Run-Gate14ReMELoadQualification.v2.ps1": "a7e997f7b9d1c48753294b437566d40cf448106ef140e16a2780ce79b7059771",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-execution-contract.v2.json": "bee4b5103cc83c1528322faa98c7227cf6e94a481c4fa1059be93ffa5844ce69",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-current-implementation-manifest.v2.json": "53d1b7bd1fc12c6c13514c5180b4f59267c13bf90ea6809d1448038446af144f",
    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs": "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73",
    "Library/ScriptAssemblies/Assembly-CSharp-Editor.dll": "abef0c3232d02818e60a5603600fbc8899dba2fbe383e73b255a04eab01b5e88",
    "Library/ScriptAssemblies/Assembly-CSharp.dll": "c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1",
}


class KnownAnswerError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise KnownAnswerError(f"object JSON required: {path}")
    return value


def write_json(path: Path, value: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: Iterable[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8", newline="\n")


def relative(path: Path) -> str:
    return path.resolve().relative_to(PROJECT).as_posix()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def assert_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file() or sha256(path) != expected:
        raise KnownAnswerError(f"{label} hash mismatch: {path}")


def unity_process_count() -> int:
    command = (
        "$ErrorActionPreference='Stop'; "
        "@(Get-CimInstance Win32_Process -Filter \"Name = 'Unity.exe'\").Count"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
    )
    return int(result.stdout.strip())


def require_reserved_roots_absent() -> None:
    existing = [str(path) for path in RESERVED_ROOTS if path.exists()]
    if existing:
        raise KnownAnswerError(f"reserved root unexpectedly exists: {existing}")


def verify_preserved() -> None:
    for path, expected in PRESERVED.items():
        assert_hash(PROJECT / path, expected, f"preserved artifact {path}")


def verify_versioned_bindings() -> Dict[str, Any]:
    current = {
        SCHEMA_PATH: SCHEMA_SHA,
        STRUCTURAL_PATH: STRUCTURAL_SHA,
        DELIVERY_PATH: DELIVERY_SHA,
        SUPERVISOR_PATH: SUPERVISOR_SHA,
        CONTRACT_PATH: CONTRACT_SHA,
        MANIFEST_PATH: MANIFEST_SHA,
        D3_PATH: D3_SHA,
        RUNTIME_PATH: RUNTIME_SHA,
    }
    for path, expected in current.items():
        assert_hash(path, expected, f"versioned asset {relative(path)}")

    schema = read_json(SCHEMA_PATH)
    expected_receipts = {
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
    if set(schema.get("receipts", [])) != expected_receipts:
        raise KnownAnswerError("schema-v3 receipt path set mismatch")
    closure = schema.get("terminalControlPlane", {}).get("fullQualificationClosure", {})
    for field, value in {
        "processResourceRows": 25272,
        "persistentStateMeasurementPointsPerLane": 26,
        "acceptedSuperblockReceipts": 162,
        "processLedgerRows": 1147,
        "processIdentityReceipts": 1147,
        "supervisorFinalProcessOrdinal": 1147,
    }.items():
        if closure.get(field) != value:
            raise KnownAnswerError(f"schema-v3 closure mismatch: {field}")

    supervisor_text = SUPERVISOR_PATH.read_text(encoding="utf-8-sig")
    required_fragments = (
        "Require-Condition ($processOrdinal -eq 1147)",
        "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE",
        "structural-validation-receipt.v3.json",
        "identityBindingSha256 = $identityBindingSha256",
    )
    for fragment in required_fragments:
        if fragment not in supervisor_text:
            raise KnownAnswerError(f"supervisor-v3 required static binding missing: {fragment}")

    contract = read_json(CONTRACT_PATH)
    if contract.get("schema") != "gate14re-me-load-qualification-execution-contract-v3":
        raise KnownAnswerError("contract-v3 identity mismatch")
    if contract.get("entryPoint", {}).get("supervisorSha256") != SUPERVISOR_SHA:
        raise KnownAnswerError("contract-v3 supervisor binding mismatch")
    manifest = read_json(MANIFEST_PATH)
    if manifest.get("manifestGeneration") != 3:
        raise KnownAnswerError("manifest-v3 generation mismatch")
    index = {item["relativePath"]: item["sha256"] for item in manifest.get("artifacts", [])}
    for item in manifest.get("artifacts", []):
        artifact = PROJECT / item["relativePath"]
        assert_hash(artifact, item["sha256"], f"manifest artifact {item['relativePath']}")
        if artifact.stat().st_size != item["bytes"]:
            raise KnownAnswerError(f"manifest byte count mismatch: {item['relativePath']}")
    for binding in contract.get("frozenBindings", {}).values():
        path = PROJECT / binding["relativePath"]
        assert_hash(path, binding["sha256"], f"contract binding {binding['relativePath']}")
        if index.get(binding["relativePath"]) != binding["sha256"]:
            raise KnownAnswerError(f"manifest omits contract binding: {binding['relativePath']}")
    if index.get(relative(SUPERVISOR_PATH)) != SUPERVISOR_SHA:
        raise KnownAnswerError("manifest-v3 supervisor binding mismatch")
    if delivery.structural is not structural:
        raise KnownAnswerError("delivery-v2.1 is not bound to structural-v3")
    return {"manifestArtifacts": len(index), "contractBindings": len(contract["frozenBindings"])}


def build_synthetic_raw() -> None:
    if WORK.exists():
        raise KnownAnswerError("known-answer work directory already exists; one-shot rule")
    WORK.mkdir(parents=False)
    shutil.copytree(BASELINE_RAW, RAW)
    lane_root = RAW / "raw/superblocks/SYNTHETIC-SB-000/ALG-A"

    state_rows: List[Dict[str, Any]] = []
    resource_rows: List[Dict[str, Any]] = []
    for index, point in enumerate(structural.MEASUREMENT_POINT_IDS):
        event_index = -1 if index < 2 else index - 2
        state_rows.append({
            "recordId": f"synthetic-state-{index:02d}",
            "inputId": "SYNTHETIC-INPUT-000",
            "superblockId": "SYNTHETIC-SB-000",
            "anonymousLaneId": "ALG-A",
            "identityBindingSha256": IDENTITY_SHA,
            "measurementPointId": point,
            "eventGroupIndex": event_index,
            "persistentContainerName": "synthetic.capacity",
            "containerKind": "array",
            "persistentContainerCapacity": 128 + index,
            "persistentContainerBytesPerElement": 8,
            "persistentContainerCapacityBytes": (128 + index) * 8,
            "persistentPrimitiveArrayBytes": (128 + index) * 8,
            "persistentStateBytesTotal": (128 + index) * 8,
            "sizingFormulaId": "gate14re-me-persistent-state-logical-capacity-v1",
            "valid": True,
            "invalidReasonCode": "",
            "sourceRelativePath": SOURCE_RELATIVE,
            "sourceSha256": SOURCE_SHA,
        })
        resource_rows.append({
            "recordId": f"synthetic-resource-{index:02d}",
            "inputId": "SYNTHETIC-INPUT-000",
            "superblockId": "SYNTHETIC-SB-000",
            "anonymousLaneId": "ALG-A",
            "identityBindingSha256": IDENTITY_SHA,
            "measurementPointId": point,
            "eventGroupIndex": event_index,
            "processId": 9104,
            "privateMemoryBytes": 1000000 + index,
            "workingSetBytes": 900000 + index,
            "managedMemoryBytes": 800000 + index,
            "peakWorkingSetBytes": 950000 + index,
            "capturedAtUtc": "2026-10-17T00:00:00.0000000Z",
            "sourceRelativePath": SOURCE_RELATIVE,
            "sourceSha256": SOURCE_SHA,
        })
    write_jsonl(lane_root / "persistent-state.raw.v1.jsonl", state_rows)
    write_jsonl(lane_root / "process-resources.raw.v1.jsonl", resource_rows)
    lane_receipt = read_json(lane_root / "lane-receipt.v2.json")
    lane_receipt["persistentStateRows"] = 26
    lane_receipt["processResourceRows"] = 26
    write_json(lane_root / "lane-receipt.v2.json", lane_receipt)

    accepted_path = RAW / "raw/superblocks/SYNTHETIC-SB-000/accepted-superblock-receipt.v1.json"
    write_json(accepted_path, {
        "schema": "gate14re-me-accepted-superblock-receipt-v1",
        "studyId": "Gate14Re-ME",
        "status": "ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK",
        "plannedSuperblockId": "SYNTHETIC-SB-000",
        "instanceId": "SYNTHETIC-SB-000",
        "isReplacement": False,
        "acceptedAnonymousLanes": 1,
        "syntheticKnownAnswer": True,
        "createdAtUtc": "2026-10-17T00:00:00.0000000Z",
    })

    oracle_path = RAW / "oracle/SYNTHETIC-SB-000/oracle-pass-receipt.v1.json"
    write_json(oracle_path, {
        "schema": "gate14re-me-oracle-pass-receipt-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "status": "PASS_ALGORITHM_NEUTRAL_GEOMETRY",
        "inputId": "SYNTHETIC-INPUT-000",
        "superblockId": "SYNTHETIC-SB-000",
        "allGeometryChecksPassed": True,
        "createdAtUtc": "2026-10-17T00:00:00.0000000Z",
    })

    lane_d3 = read_jsonl(lane_root / "d3-windows.raw.v1.jsonl")[0]
    instrument_d3 = dict(lane_d3)
    instrument_d3.update({
        "recordId": "synthetic-instrument-d3-positive-control",
        "inputId": "",
        "superblockId": "",
        "anonymousLaneId": "",
        "identityBindingSha256": "",
        "measurementScope": "instrument-self-test-positive-control",
        "eventGroupIndex": -1,
        "processOrdinal": -1,
        "iterationIndex": -1,
        "managedAllocationBytes": 1048576,
        "managedAllocationEventCount": 1,
        "windowStartStopwatchTicks": 300000,
        "windowEndStopwatchTicks": 310000,
        "windowElapsedStopwatchTicks": 10000,
        "stopwatchFrequency": 10000000,
        "managedAllocationRateBytesPerSecond": 1048576000.0,
        "managedAllocationRateValid": True,
    })
    instrument_root = RAW / "instruments/csharp"
    write_jsonl(instrument_root / "d3-windows.raw.v1.jsonl", [instrument_d3])
    write_json(instrument_root / "instrument-csharp-receipt.v2.json", {
        "schema": "gate14re-me-instrument-qualification-receipt-v2",
        "studyId": "Gate14Re-ME",
        "status": "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING",
        "gridReadProxyKnownAnswerPassed": True,
        "gridReadProxySemanticInvariancePassed": True,
        "d3V31PluginReadinessPassed": True,
        "d3V31OneMiBPositiveControlPassed": True,
        "d3V31RateFormulaPassed": True,
        "persistentStateSizerSyntheticFixturePassed": True,
        "clockMonotonicityPassed": True,
        "rawToExportRoundTripPassed": False,
        "tamperNegativeTestPassed": False,
        "missingNegativeTestPassed": False,
        "duplicateNegativeTestPassed": False,
        "anonymousLabelSwapNegativeTestPassed": False,
        "d3ContractSha256": D3_SHA,
        "implementationManifestSha256": MANIFEST_SHA,
        "createdAtUtc": "2026-10-17T00:00:00.0000000Z",
    })

    control = RAW / "_control"
    identities = control / "process-identities"
    identities.mkdir(parents=True, exist_ok=True)
    modes = ("instrument-self-test", "oracle", "empty-boundary", "lane")
    output_paths = (
        "instruments/csharp",
        "oracle/SYNTHETIC-SB-000",
        "raw/empty-boundary/process-00",
        "raw/superblocks/SYNTHETIC-SB-000/ALG-A",
    )
    ledger: List[Dict[str, Any]] = []
    for ordinal, (mode, output_path) in enumerate(zip(modes, output_paths)):
        pid = 9101 + ordinal
        creation = f"2026-10-17T00:00:0{ordinal}.0000000Z"
        identity_path = identities / f"process-{ordinal:04d}.identity.v2.json"
        write_json(identity_path, {
            "schema": "gate14re-me-qualified-unity-process-identity-receipt-v2",
            "studyId": "Gate14Re-ME",
            "status": "PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT",
            "ordinal": ordinal,
            "mode": mode,
            "processId": pid,
            "creationTimeUtc": creation,
            "launchedAtUtc": creation,
            "exitedAtUtc": creation,
            "processStartDeltaMilliseconds": 0.0,
            "executablePath": "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe",
            "exactCommandLine": f'"H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe" -executeMethod {structural.RUNNER_METHOD} --g14me-mode {mode}',
            "exactCommandLineSha256": "0" * 64,
            "executeMethod": structural.RUNNER_METHOD,
            "outputRelativePath": relative(RAW / output_path),
            "exitCode": 0,
            "naturalExit": True,
            "signalOrForcedTerminationSent": False,
            "retryPerformed": False,
            "trustedIdentityRuleSha256": structural.TRUSTED_IDENTITY_RULE_SHA256,
            "timestampComparatorSha256": structural.TIMESTAMP_COMPARATOR_SHA256,
            "prelaunchFingerprint": {"synthetic": True},
            "liveConcurrentFingerprint": {"synthetic": True},
            "postExitFingerprint": {"synthetic": True},
        })
        ledger.append({
            "schema": "gate14re-me-process-ledger-row-v2",
            "ordinal": ordinal,
            "mode": mode,
            "processId": pid,
            "creationTimeUtc": creation,
            "exitedAtUtc": creation,
            "exitCode": 0,
            "identityReceiptRelativePath": relative(identity_path),
            "identityReceiptSha256": sha256(identity_path),
            "state": "EXITED_ZERO_TRUSTED_IDENTITY",
        })
    write_jsonl(control / "process-ledger.raw.v2.jsonl", ledger)
    write_json(control / "launch-receipt.v2.json", {
        "schema": "gate14re-me-qualification-launch-receipt-v2",
        "studyId": "Gate14Re-ME",
        "status": "AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED",
        "outputSchemaSha256": SCHEMA_SHA,
        "d3ContractSha256": D3_SHA,
        "structuralToolSha256": STRUCTURAL_SHA,
        "deliveryToolSha256": DELIVERY_SHA,
        "identityBindingSha256": IDENTITY_SHA,
        "syntheticKnownAnswer": True,
    })
    write_json(control / "acquisition-complete.v2.json", {
        "schema": "gate14re-me-qualification-acquisition-complete-v2",
        "studyId": "Gate14Re-ME",
        "status": "QUALIFICATION_RAW_STRUCTURAL_VALIDATION_PENDING",
        "plannedSuperblocks": 1,
        "acceptedSuperblocks": 1,
        "plannedAlgorithmLanes": 1,
        "acceptedAlgorithmLanes": 1,
        "unityProcessCount": 4,
        "wholeSuperblockReplacements": 0,
        "formalCollectionAuthorized": False,
        "formalAnalysisAuthorized": False,
        "rankingOrWinnerComputed": False,
        "syntheticKnownAnswer": True,
    })


def structural_validate(root: Path) -> Dict[str, Any]:
    return structural.validate_raw_package(
        project_root=PROJECT,
        raw_root=root,
        output_schema_path=SCHEMA_PATH,
        output_schema_sha256=SCHEMA_SHA,
        d3_contract_path=D3_PATH,
        d3_contract_sha256=D3_SHA,
        identity_binding_sha256=IDENTITY_SHA,
        profile="synthetic-known-answer",
    )


def rebind_identity_links(root: Path) -> None:
    ledger_path = root / "_control/process-ledger.raw.v2.jsonl"
    rows = read_jsonl(ledger_path)
    for row in rows:
        identity = root / "_control/process-identities" / f"process-{row['ordinal']:04d}.identity.v2.json"
        row["identityReceiptRelativePath"] = relative(identity)
        row["identityReceiptSha256"] = sha256(identity)
    write_jsonl(ledger_path, rows)


def expect_structural_failure(name: str, mutate: Callable[[Path], None], fragment: str) -> Dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"negative-{name}-", dir=WORK) as temp:
        root = Path(temp) / "raw"
        shutil.copytree(RAW, root)
        rebind_identity_links(root)
        mutate(root)
        try:
            structural_validate(root)
        except structural.StructuralError as exc:
            reason = str(exc)
            if fragment not in reason:
                raise KnownAnswerError(f"negative {name} failed for the wrong reason: {reason}") from exc
            return {"name": name, "passed": True, "reasonContains": fragment}
        raise KnownAnswerError(f"negative {name} unexpectedly passed")


def run_negative_structural() -> List[Dict[str, Any]]:
    def missing_resource(root: Path) -> None:
        path = root / "raw/superblocks/SYNTHETIC-SB-000/ALG-A/process-resources.raw.v1.jsonl"
        write_jsonl(path, read_jsonl(path)[:-1])

    def missing_state_point(root: Path) -> None:
        path = root / "raw/superblocks/SYNTHETIC-SB-000/ALG-A/persistent-state.raw.v1.jsonl"
        write_jsonl(path, read_jsonl(path)[:-1])

    def missing_acceptance(root: Path) -> None:
        (root / "raw/superblocks/SYNTHETIC-SB-000/accepted-superblock-receipt.v1.json").unlink()

    def short_ledger(root: Path) -> None:
        path = root / "_control/process-ledger.raw.v2.jsonl"
        write_jsonl(path, read_jsonl(path)[:-1])

    def tampered_identity(root: Path) -> None:
        path = root / "_control/process-identities/process-0003.identity.v2.json"
        value = read_json(path)
        value["mode"] = "oracle"
        write_json(path, value)

    def wrong_final_count(root: Path) -> None:
        path = root / "_control/acquisition-complete.v2.json"
        value = read_json(path)
        value["unityProcessCount"] = 3
        write_json(path, value)

    return [
        expect_structural_failure("missing-process-resource", missing_resource, "requires 26 process-resource rows"),
        expect_structural_failure("missing-persistent-measurement-point", missing_state_point, "persistent-state measurement-point coverage mismatch"),
        expect_structural_failure("missing-accepted-superblock-receipt", missing_acceptance, "requires 1 accepted-superblock receipt"),
        expect_structural_failure("short-process-ledger", short_ledger, "requires 4 process-ledger rows"),
        expect_structural_failure("tampered-process-identity", tampered_identity, "process identity receipt"),
        expect_structural_failure("wrong-terminal-process-count", wrong_final_count, "unityProcessCount"),
    ]


def run_delivery() -> Dict[str, Any]:
    build = delivery.build_delivery(
        project_root=PROJECT,
        raw_root=RAW,
        output_root=DELIVERY,
        output_schema_path=SCHEMA_PATH,
        output_schema_sha256=SCHEMA_SHA,
        d3_contract_path=D3_PATH,
        d3_contract_sha256=D3_SHA,
        runtime_manifest_path=RUNTIME_PATH,
        runtime_manifest_sha256=RUNTIME_SHA,
        identity_binding_sha256=IDENTITY_SHA,
        profile="synthetic-known-answer",
    )
    verified = delivery.verify_delivery(
        project_root=PROJECT,
        delivery_root=DELIVERY,
        runtime_manifest_path=RUNTIME_PATH,
        runtime_manifest_sha256=RUNTIME_SHA,
    )
    shutil.copytree(DELIVERY, NEGATIVE_DELIVERY)
    missing = NEGATIVE_DELIVERY / "event-groups/event-groups.v2.parquet"
    missing.unlink()
    try:
        delivery.verify_delivery(
            project_root=PROJECT,
            delivery_root=NEGATIVE_DELIVERY,
            runtime_manifest_path=RUNTIME_PATH,
            runtime_manifest_sha256=RUNTIME_SHA,
        )
    except delivery.DeliveryError as exc:
        if "missing delivery product" not in str(exc):
            raise KnownAnswerError(f"delivery negative failed for wrong reason: {exc}") from exc
    else:
        raise KnownAnswerError("missing delivery product negative unexpectedly passed")
    return {
        "buildStatus": build["status"],
        "verifyStatus": verified["status"],
        "tables": verified["tables"],
        "products": verified["products"],
        "manifestSha256": verified["deliveryManifestSha256"],
        "missingProductNegativePassed": True,
    }


def freeze_manifest(receipt_path: Path) -> Dict[str, Any]:
    paths = [
        ATTEMPT / "authorization-receipt.v1.json",
        ATTEMPT / "stage-contract.v1.json",
        Path(__file__).resolve(),
        SCHEMA_PATH,
        STRUCTURAL_PATH,
        DELIVERY_PATH,
        SUPERVISOR_PATH,
        CONTRACT_PATH,
        MANIFEST_PATH,
        receipt_path,
        DELIVERY / "delivery-manifest.v2.json",
        DELIVERY / "instrument-export-receipt.v2.json",
    ]
    return {
        "schema": "gate14re-me-terminal-chain-corrigendum-freeze-manifest-v1",
        "studyId": "Gate14Re-ME",
        "status": "FROZEN_TERMINAL_CHAIN_CORRIGENDUM_PASS",
        "artifacts": [
            {"relativePath": relative(path), "sha256": sha256(path), "bytes": path.stat().st_size}
            for path in paths
        ],
        "preservedPriorEvidence": [
            {"relativePath": path, "sha256": expected, "modifiedOrReclassified": False}
            for path, expected in PRESERVED.items()
        ],
        "frozenAtUtc": utc_now(),
    }


def main() -> int:
    receipt_path = ATTEMPT / "terminal-pass-receipt.v1.json"
    failure_path = ATTEMPT / "failure-receipt.v1.json"
    freeze_path = ATTEMPT / "freeze-manifest.v1.json"
    if receipt_path.exists() or failure_path.exists() or freeze_path.exists():
        raise KnownAnswerError("terminal evidence already exists; refusing rerun")
    started = utc_now()
    try:
        require_reserved_roots_absent()
        verify_preserved()
        if unity_process_count() != 0:
            raise KnownAnswerError("Unity process exists before offline known-answer")
        static = verify_versioned_bindings()
        build_synthetic_raw()
        positive = structural_validate(RAW)
        if positive.get("status") != "PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE":
            raise KnownAnswerError("structural-v3 positive did not reach terminal PASS")
        negatives = run_negative_structural()
        delivery_result = run_delivery()
        if unity_process_count() != 0:
            raise KnownAnswerError("Unity process exists after offline known-answer")
        require_reserved_roots_absent()
        verify_preserved()
        receipt = {
            "schema": "gate14re-me-qualification-execution-terminal-chain-corrigendum-terminal-receipt-v1",
            "studyId": "Gate14Re-ME",
            "authorizationId": "gate14re-me-qualification-execution-terminal-chain-corrigendum-attempt-001",
            "status": "PASS_TERMINAL_CHAIN_CORRIGENDUM_OFFLINE_ONLY",
            "passed": True,
            "startedAtUtc": started,
            "completedAtUtc": utc_now(),
            "versionedBindings": static,
            "structuralPositive": positive,
            "structuralNegativeFixtures": negatives,
            "deliveryKnownAnswer": delivery_result,
            "resolvedPriorBlockers": [
                "TERMINAL::OUTPUT_SCHEMA_RECEIPT_PATH_VERSION_ALIGNMENT",
                "TERMINAL::FULL_CARDINALITY_PROCESS_AND_ACCEPTANCE_CLOSURE",
            ],
            "scientificBoundary": {
                "unityInvocationCount": 0,
                "plannerInvocationCount": 0,
                "algorithmLaneExecutionCount": 0,
                "qualificationMeasuredRootCreated": False,
                "formalDeliveryRootCreated": False,
                "qualificationObservationCount": 0,
                "formalObservationCount": 0,
                "formalCollectionPerformed": False,
                "formalAnalysisPerformed": False,
                "rankingPerformed": False,
                "winnerAdjudicationPerformed": False,
                "sealedIdentityMappingOpened": False,
            },
            "activation": {
                "qualificationExecutionAuthorized": False,
                "separateReadinessRecheckRequired": True,
            },
        }
        write_json(receipt_path, receipt)
        write_json(freeze_path, freeze_manifest(receipt_path))
        print(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        failure = {
            "schema": "gate14re-me-qualification-execution-terminal-chain-corrigendum-failure-receipt-v1",
            "studyId": "Gate14Re-ME",
            "status": "FAILED_CLOSED_TERMINAL_CHAIN_CORRIGENDUM",
            "passed": False,
            "startedAtUtc": started,
            "failedAtUtc": utc_now(),
            "exceptionType": type(exc).__name__,
            "exactFailure": str(exc),
            "unityInvocationCount": 0,
            "qualificationMeasuredRootCreated": any(path.exists() for path in RESERVED_ROOTS[:1]),
            "formalDeliveryRootCreated": RESERVED_ROOTS[1].exists(),
            "formalAnalysisRankingOrWinnerPerformed": False,
        }
        write_json(failure_path, failure)
        print(json.dumps(failure, ensure_ascii=False, indent=2, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
