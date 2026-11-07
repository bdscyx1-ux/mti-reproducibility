#!/usr/bin/env python3
"""Algorithm-free known-answer harness for the Gate14Re-ME schema-v2 tools.

The harness creates only synthetic raw rows beneath the authorized verification
attempt.  It does not import, construct, or invoke any path-planning algorithm.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Sequence

import gate14re_me_qualification_delivery_v2 as delivery
import gate14re_me_qualification_structural_v2 as structural


HARNESS_SCHEMA = "gate14re-me-schema-v2-tooling-known-answer-harness-v1"
ATTEMPT_RELATIVE = Path(
    "Research/Verification/Gate14Re-ME/schema-v2-tooling-bridge-attempt-001"
)
IDENTITY_SHA256 = hashlib.sha256(
    b"Gate14Re-ME synthetic known-answer identity binding; no algorithm mapping"
).hexdigest()


class HarnessError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def write_jsonl(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(structural.canonical_json(row))
            handle.write("\n")


def read_rows(path: Path) -> List[Dict[str, Any]]:
    return [row for _, row in structural.read_jsonl(path)]


def source_binding(project_root: Path, attempt_root: Path) -> Dict[str, str]:
    source_path = attempt_root / "synthetic-source/synthetic-input-source.v1.json"
    write_json(
        source_path,
        {
            "schema": "gate14re-me-algorithm-free-synthetic-source-v1",
            "studyId": "Gate14Re-ME",
            "status": "SYNTHETIC_KNOWN_ANSWER_ONLY",
            "algorithmConstructedOrInvoked": False,
            "qualificationObservation": False,
            "formalObservation": False,
        },
    )
    return {
        "sourceRelativePath": source_path.relative_to(project_root).as_posix(),
        "sourceSha256": structural.sha256_file(source_path),
    }


def d3_row(
    *,
    record_id: str,
    input_id: str,
    superblock_id: str,
    lane: str,
    identity_sha: str,
    scope: str,
    event_index: int,
    process_ordinal: int,
    iteration_index: int,
    allocation_bytes: int,
    event_count: int,
    start_ticks: int,
    elapsed_ticks: int,
    frequency: int,
    source: Mapping[str, str],
) -> Dict[str, Any]:
    rate = (
        allocation_bytes * frequency / elapsed_ticks if allocation_bytes > 0 else 0.0
    )
    return {
        "recordId": record_id,
        "inputId": input_id,
        "superblockId": superblock_id,
        "anonymousLaneId": lane,
        "identityBindingSha256": identity_sha,
        "measurementScope": scope,
        "eventGroupIndex": event_index,
        "processOrdinal": process_ordinal,
        "iterationIndex": iteration_index,
        "d3CounterId": structural.D3_COUNTER_ID,
        "d3SemanticVersion": structural.D3_SEMANTIC_VERSION,
        "managedAllocationBytes": allocation_bytes,
        "managedAllocationEventCount": event_count,
        "foreignThreadAllocationBytes": 0,
        "foreignThreadAllocationEventCount": 0,
        "invalidMetadataEventCount": 0,
        "counterOverflowCount": 0,
        "ownerNativeThreadId": 4242,
        "observerNativeThreadId": 4242,
        "windowStartStopwatchTicks": start_ticks,
        "windowEndStopwatchTicks": start_ticks + elapsed_ticks,
        "windowElapsedStopwatchTicks": elapsed_ticks,
        "stopwatchFrequency": frequency,
        "managedAllocationRateBytesPerSecond": rate,
        "managedAllocationRateValid": allocation_bytes > 0,
        "beginReturnCode": 0,
        "endReturnCode": 0,
        "pluginReady": True,
        "markerSeen": True,
        "metadataAbiValid": True,
        "ownerThreadMatched": True,
        "counterValid": True,
        "invalidReasonCode": "",
        "d3ContractRelativePath": structural.D3_CONTRACT_RELATIVE_PATH,
        "d3ContractSha256": structural.D3_CONTRACT_SHA256,
        **source,
    }


def create_positive_fixture(project_root: Path, attempt_root: Path) -> Path:
    raw_root = attempt_root / "synthetic-fixture/raw-package"
    source = source_binding(project_root, attempt_root)
    lane_root = raw_root / "raw/superblocks/SYNTHETIC-SB-000/ALG-A"
    empty_root = raw_root / "raw/empty-boundary/process-00"
    oracle_root = raw_root / "oracle/SYNTHETIC-SB-000"
    control_root = raw_root / "_control"
    for directory in (lane_root, empty_root, oracle_root, control_root):
        directory.mkdir(parents=True, exist_ok=True)

    write_jsonl(oracle_root / "oracle-agent-checks.raw.v1.jsonl", [])
    write_jsonl(oracle_root / "oracle-event-checks.raw.v1.jsonl", [])
    write_jsonl(lane_root / "operations.raw.v1.jsonl", [])
    write_jsonl(lane_root / "persistent-state.raw.v1.jsonl", [])
    write_jsonl(lane_root / "process-resources.raw.v1.jsonl", [])
    write_jsonl(control_root / "replacement-ledger.raw.v1.jsonl", [])
    write_jsonl(control_root / "failures-and-voids.raw.v1.jsonl", [])

    input_id = "SYNTHETIC-INPUT-000"
    superblock_id = "SYNTHETIC-SB-000"
    lane = "ALG-A"
    d3_rows: List[Dict[str, Any]] = [
        d3_row(
            record_id="synthetic-d3-init",
            input_id=input_id,
            superblock_id=superblock_id,
            lane=lane,
            identity_sha=IDENTITY_SHA256,
            scope="planner-initialization",
            event_index=-1,
            process_ordinal=-1,
            iteration_index=-1,
            allocation_bytes=4096,
            event_count=1,
            start_ticks=100000,
            elapsed_ticks=10,
            frequency=10_000_000,
            source=source,
        )
    ]
    event_rows: List[Dict[str, Any]] = []
    for index in range(24):
        d3_record_id = f"synthetic-d3-event-{index:02d}"
        d3_rows.append(
            d3_row(
                record_id=d3_record_id,
                input_id=input_id,
                superblock_id=superblock_id,
                lane=lane,
                identity_sha=IDENTITY_SHA256,
                scope="event-group",
                event_index=index,
                process_ordinal=-1,
                iteration_index=-1,
                allocation_bytes=8192 + index * 64,
                event_count=2 + index,
                start_ticks=101000 + index * 100,
                elapsed_ticks=20 + index,
                frequency=10_000_000,
                source=source,
            )
        )
        event_rows.append(
            {
                "recordId": f"synthetic-event-{index:02d}",
                "inputId": input_id,
                "superblockId": superblock_id,
                "designRegion": "synthetic-known-answer",
                "anonymousLaneId": lane,
                "identityBindingSha256": IDENTITY_SHA256,
                "gridEdge": 64,
                "agentCount": 16,
                "changedCellCount": 32,
                "changeTopology": "synthetic-mixed",
                "graphProfile": "synthetic-grid",
                "sameTickAtomicPartitions": 1,
                "contextStratumId": "SYNTHETIC-CONTEXT",
                "eventGroupId": f"synthetic-group-{index:02d}",
                "eventGroupIndex": index,
                "cycleIndex": index // 2,
                "phase": "A" if index % 2 == 0 else "B",
                "eventGroupElapsedMilliseconds": 1.0 + index / 100.0,
                "d3WindowRecordId": d3_record_id,
                "d3CounterId": structural.D3_COUNTER_ID,
                "d3CounterValid": True,
                "gridContainsCalls": 10 + index,
                "gridIsWalkableCalls": 20 + index,
                "gridGetTraversalCostCalls": 30 + index,
                "gridAccessorCallsTotal": 60 + 3 * index,
                "repairOperationCount": 1,
                "planOperationCount": 16,
                "succeededPlanCount": 16,
                "noPathPlanCount": 0,
                "budgetExceededOperationCount": 0,
                "eligible": True,
                "missingOrIneligibleReasonCode": "",
                "finitePositiveElapsed": True,
                "counterValid": True,
                **source,
            }
        )
    write_jsonl(lane_root / "d3-windows.raw.v1.jsonl", d3_rows)
    write_jsonl(lane_root / "event-groups.raw.v2.jsonl", event_rows)
    write_json(
        lane_root / "lane-receipt.v2.json",
        {
            "schema": "gate14re-me-qualification-lane-receipt-v2",
            "studyId": "Gate14Re-ME",
            "protocolId": "gate14re-me-load-qualification-v1",
            "status": "COMPLETE_RAW_LANE",
            "inputId": input_id,
            "superblockId": superblock_id,
            "anonymousLaneId": lane,
            "identityBindingSha256": IDENTITY_SHA256,
            "d3ContractSha256": structural.D3_CONTRACT_SHA256,
            "eventGroupRows": 24,
            "operationRows": 0,
            "d3WindowRows": 25,
            "persistentStateRows": 0,
            "processResourceRows": 0,
            "instrumentValid": True,
            "completed": True,
            "failureReasonCode": "",
            "syntheticKnownAnswer": True,
        },
    )

    empty_rows: List[Dict[str, Any]] = []
    empty_d3_rows: List[Dict[str, Any]] = []
    for index in range(1000):
        d3_record_id = f"synthetic-empty-d3-{index:04d}"
        empty_d3_rows.append(
            d3_row(
                record_id=d3_record_id,
                input_id="",
                superblock_id="",
                lane="",
                identity_sha="",
                scope="empty-boundary",
                event_index=-1,
                process_ordinal=0,
                iteration_index=index,
                allocation_bytes=0,
                event_count=0,
                start_ticks=200000 + index * 10,
                elapsed_ticks=5,
                frequency=10_000_000,
                source=source,
            )
        )
        empty_rows.append(
            {
                "recordId": f"synthetic-empty-{index:04d}",
                "processOrdinal": 0,
                "iterationIndex": index,
                "stopwatchStartTicks": 300000 + index * 10,
                "stopwatchEndTicks": 300005 + index * 10,
                "elapsedMilliseconds": 0.0005,
                "d3WindowRecordId": d3_record_id,
                "d3CounterId": structural.D3_COUNTER_ID,
                "d3CounterValid": True,
                "plannerInvoked": False,
                **source,
            }
        )
    write_jsonl(empty_root / "d3-windows.raw.v1.jsonl", empty_d3_rows)
    write_jsonl(empty_root / "empty-boundary.raw.v2.jsonl", empty_rows)
    write_json(
        empty_root / "empty-boundary-receipt.v2.json",
        {
            "schema": "gate14re-me-empty-boundary-receipt-v2",
            "studyId": "Gate14Re-ME",
            "status": "COMPLETE_EMPTY_BOUNDARY_RAW",
            "processOrdinal": 0,
            "rawIterationRows": 1000,
            "d3WindowRows": 1000,
            "plannerInvoked": False,
            "d3ContractSha256": structural.D3_CONTRACT_SHA256,
            "syntheticKnownAnswer": True,
        },
    )
    return raw_root


def mutate_jsonl(path: Path, mutation: Callable[[List[Dict[str, Any]]], None]) -> None:
    rows = read_rows(path)
    mutation(rows)
    write_jsonl(path, rows)


def run_structural(
    project_root: Path,
    raw_root: Path,
    schema_path: Path,
    contract_path: Path,
) -> Dict[str, Any]:
    return structural.validate_raw_package(
        project_root=project_root,
        raw_root=raw_root,
        output_schema_path=schema_path,
        output_schema_sha256=structural.EXPECTED_SCHEMA_SHA256,
        d3_contract_path=contract_path,
        d3_contract_sha256=structural.D3_CONTRACT_SHA256,
        identity_binding_sha256=IDENTITY_SHA256,
        profile="synthetic-known-answer",
    )


def expect_structural_failure(
    *,
    project_root: Path,
    positive_root: Path,
    negative_root: Path,
    schema_path: Path,
    contract_path: Path,
    mutate: Callable[[Path], None],
    reason_tokens: Sequence[str],
) -> Dict[str, Any]:
    shutil.copytree(positive_root, negative_root)
    mutate(negative_root)
    try:
        run_structural(project_root, negative_root, schema_path, contract_path)
    except structural.StructuralError as exc:
        reason = str(exc)
        if not any(token.lower() in reason.lower() for token in reason_tokens):
            raise HarnessError(
                f"negative fixture failed for an unexpected reason: {negative_root.name}: {reason}"
            ) from exc
        return {
            "testId": negative_root.name,
            "status": "PASS_EXPECTED_FAIL_CLOSED",
            "reason": reason,
        }
    raise HarnessError(f"negative fixture did not fail closed: {negative_root.name}")


def run(project_root: Path) -> Dict[str, Any]:
    project_root = project_root.resolve()
    attempt_root = (project_root / ATTEMPT_RELATIVE).resolve()
    repair_cycle = None
    if attempt_root.exists():
        failure_receipt = attempt_root / "failure-receipt.v1.json"
        if not failure_receipt.is_file():
            raise HarnessError(
                f"verification attempt already exists without a retained failure receipt: {attempt_root}"
            )
        repair_cycle = "repair-cycle-001"
        run_root = attempt_root / repair_cycle
        if run_root.exists():
            raise HarnessError(f"repair cycle already exists: {run_root}")
        run_root.mkdir()
    else:
        attempt_root.parent.mkdir(parents=True, exist_ok=True)
        attempt_root.mkdir()
        run_root = attempt_root
    schema_path = project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json"
    contract_path = project_root / structural.D3_CONTRACT_RELATIVE_PATH
    runtime_manifest_path = project_root / "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json"
    protected = {
        "structuralV1": (
            project_root / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v1.py",
            "4cc4369c50b7b0b89bc7ec657b2384b93ff48905205046c93d25584ca3e5852f",
        ),
        "deliveryV1": (
            project_root / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v1.py",
            "3a5c58cbb4f4db93ebedd563175fa916f9a9443925a1c8955bb107cb3dbb4905",
        ),
        "runnerV2": (
            project_root / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs",
            "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73",
        ),
    }
    structural.require_hash(schema_path, structural.EXPECTED_SCHEMA_SHA256, "schema v2")
    structural.require_hash(contract_path, structural.D3_CONTRACT_SHA256, "D3-v3.1 contract")
    structural.require_hash(
        runtime_manifest_path,
        delivery.TYPED_PARQUET_RUNTIME_SHA256,
        "typed-Parquet runtime manifest",
    )
    for label, (path, expected) in protected.items():
        structural.require_hash(path, expected, label)

    positive_root = create_positive_fixture(project_root, run_root)
    positive_structural = run_structural(
        project_root, positive_root, schema_path, contract_path
    )

    negative_parent = run_root / "negative-fixtures"
    negative_parent.mkdir()
    lane_d3_relative = Path(
        "raw/superblocks/SYNTHETIC-SB-000/ALG-A/d3-windows.raw.v1.jsonl"
    )
    lane_event_relative = Path(
        "raw/superblocks/SYNTHETIC-SB-000/ALG-A/event-groups.raw.v2.jsonl"
    )

    negative_results: List[Dict[str, Any]] = []
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "tamper-source-hash",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows[0].__setitem__("sourceSha256", "0" * 64),
            ),
            reason_tokens=("SHA-256 mismatch", "source hash"),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "missing-d3-join-row",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows.pop(1),
            ),
            reason_tokens=("25 D3 windows", "join target missing", "cardinality"),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "duplicate-record-id",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows.append(dict(rows[0])),
            ),
            reason_tokens=("duplicate recordId",),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "bool-as-int-type-substitution",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows[1].__setitem__("managedAllocationBytes", True),
            ),
            reason_tokens=("integer required", "bool rejected"),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "rate-formula-mismatch",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows[1].__setitem__(
                    "managedAllocationRateBytesPerSecond",
                    rows[1]["managedAllocationRateBytesPerSecond"] + 1.0,
                ),
            ),
            reason_tokens=("rate formula mismatch",),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "retired-snapshot-field-injection",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_d3_relative,
                lambda rows: rows[1].__setitem__("allocationCounterStart", 0),
            ),
            reason_tokens=("retired D3 snapshot field",),
        )
    )
    negative_results.append(
        expect_structural_failure(
            project_root=project_root,
            positive_root=positive_root,
            negative_root=negative_parent / "anonymous-label-swap",
            schema_path=schema_path,
            contract_path=contract_path,
            mutate=lambda root: mutate_jsonl(
                root / lane_event_relative,
                lambda rows: rows[0].__setitem__("anonymousLaneId", "ALG-Z"),
            ),
            reason_tokens=("invalid anonymous lane", "identity-binding swap"),
        )
    )

    delivery_root = run_root / "synthetic-delivery"
    build_receipt = delivery.build_delivery(
        project_root=project_root,
        raw_root=positive_root,
        output_root=delivery_root,
        output_schema_path=schema_path,
        output_schema_sha256=structural.EXPECTED_SCHEMA_SHA256,
        d3_contract_path=contract_path,
        d3_contract_sha256=structural.D3_CONTRACT_SHA256,
        runtime_manifest_path=runtime_manifest_path,
        runtime_manifest_sha256=delivery.TYPED_PARQUET_RUNTIME_SHA256,
        identity_binding_sha256=IDENTITY_SHA256,
        profile="synthetic-known-answer",
    )
    verify_receipt = delivery.verify_delivery(
        project_root=project_root,
        delivery_root=delivery_root,
        runtime_manifest_path=runtime_manifest_path,
        runtime_manifest_sha256=delivery.TYPED_PARQUET_RUNTIME_SHA256,
    )

    tampered_delivery = run_root / "negative-delivery-tamper"
    shutil.copytree(delivery_root, tampered_delivery)
    tamper_target = tampered_delivery / "d3-windows/d3-windows.v2.jsonl"
    with tamper_target.open("ab") as handle:
        handle.write(b" ")
    try:
        delivery.verify_delivery(
            project_root=project_root,
            delivery_root=tampered_delivery,
            runtime_manifest_path=runtime_manifest_path,
            runtime_manifest_sha256=delivery.TYPED_PARQUET_RUNTIME_SHA256,
        )
    except delivery.DeliveryError as exc:
        negative_results.append(
            {
                "testId": "delivery-product-tamper",
                "status": "PASS_EXPECTED_FAIL_CLOSED",
                "reason": str(exc),
            }
        )
    else:
        raise HarnessError("tampered delivery product did not fail closed")

    missing_delivery = run_root / "negative-delivery-missing-file"
    shutil.copytree(delivery_root, missing_delivery)
    missing_target = missing_delivery / "event-groups/event-groups.v2.parquet"
    missing_target.unlink()
    try:
        delivery.verify_delivery(
            project_root=project_root,
            delivery_root=missing_delivery,
            runtime_manifest_path=runtime_manifest_path,
            runtime_manifest_sha256=delivery.TYPED_PARQUET_RUNTIME_SHA256,
        )
    except delivery.DeliveryError as exc:
        negative_results.append(
            {
                "testId": "delivery-product-missing-file",
                "status": "PASS_EXPECTED_FAIL_CLOSED",
                "reason": str(exc),
            }
        )
    else:
        raise HarnessError("missing delivery product did not fail closed")

    forbidden_roots = [
        project_root / "Research/FormalRuns/Gate14Re-ME",
        project_root / "Research/QualificationRuns/Gate14Re-ME",
        project_root / "Research/MeasuredRuns/Gate14Re-ME",
    ]
    if any(path.exists() for path in forbidden_roots):
        raise HarnessError("a prohibited Gate14Re-ME measured/formal root exists")
    for label, (path, expected) in protected.items():
        structural.require_hash(path, expected, f"post-test protected {label}")

    receipt = {
        "schema": "gate14re-me-schema-v2-tooling-known-answer-receipt-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": "gate14re-me-schema-v2-tooling-bridge-attempt-001",
        "status": "PASS_SCHEMA_V2_TOOLING_SYNTHETIC_KNOWN_ANSWER",
        "completedAtUtc": utc_now(),
        "verificationAttemptRelativePath": ATTEMPT_RELATIVE.as_posix(),
        "executionRootRelativePath": run_root.relative_to(project_root).as_posix(),
        "repairCycle": repair_cycle,
        "initialFailureEvidenceRetained": repair_cycle is not None,
        "positiveStructuralValidation": positive_structural,
        "positiveDeliveryBuild": build_receipt,
        "positiveDeliveryVerification": verify_receipt,
        "negativeTests": negative_results,
        "negativeTestsPassed": len(negative_results),
        "syntheticRawRows": sum(positive_structural["tableRows"].values()),
        "syntheticD3WindowRows": positive_structural["tableRows"]["d3-windows"],
        "syntheticEventGroupRows": positive_structural["tableRows"]["event-groups"],
        "syntheticEmptyBoundaryRows": positive_structural["tableRows"]["empty-boundary"],
        "qualificationScheduleRows": 0,
        "qualificationInputs": 0,
        "anonymousIdentityMappings": 0,
        "qualificationMeasuredRootCreated": False,
        "algorithmPlannerConstructedOrInvoked": False,
        "algorithmLanesExecuted": 0,
        "formalObservations": 0,
        "formalAnalysisPerformed": False,
        "crossAlgorithmEffectsComputed": False,
        "rankingOrWinnerComputed": False,
    }
    write_json(run_root / "known-answer-receipt.v1.json", receipt)
    write_json(
        run_root / "scope-audit.v1.json",
        {
            "schema": "gate14re-me-schema-v2-tooling-scope-audit-v1",
            "status": "PASS_AUTHORIZED_SCOPE_ONLY",
            "checkedAtUtc": utc_now(),
            "verificationAttemptRelativePath": ATTEMPT_RELATIVE.as_posix(),
            "executionRootRelativePath": run_root.relative_to(project_root).as_posix(),
            "repairCycle": repair_cycle,
            "initialFailureEvidenceRetained": repair_cycle is not None,
            "forbiddenRootsAbsent": [
                path.relative_to(project_root).as_posix() for path in forbidden_roots
            ],
            "algorithmPlannerConstructedOrInvoked": False,
            "qualificationMeasuredRootCreated": False,
            "formalCollectionPerformed": False,
            "formalAnalysisPerformed": False,
            "rankingOrWinnerComputed": False,
        },
    )
    return receipt


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = run(Path(args.project_root))
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (HarnessError, structural.StructuralError, delivery.DeliveryError) as exc:
        print(
            json.dumps(
                {"schema": HARNESS_SCHEMA, "status": "FAIL_CLOSED", "reason": str(exc)},
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
