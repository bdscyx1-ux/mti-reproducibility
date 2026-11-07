#!/usr/bin/env python3
"""Read-only Gate14Re-ME qualification execution-readiness audit.

This script deliberately does not create a measured root, launch Unity, invoke a
planner, execute an algorithm lane, or write an observation.  It reads frozen
contracts/assets and current execution sources, then emits one JSON report to
stdout.  A non-zero exit code means the execution chain is not ready and must
remain fail closed.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any


PROJECT_ROOT = pathlib.Path(r"H:\DDM_Final_Project")
ATTEMPT_REL = pathlib.PurePosixPath(
    "Research/Verification/Gate14Re-ME/"
    "qualification-execution-readiness-freeze-attempt-001"
)

EXPECTED_HASHES = {
    "Research/Gate14Re-ME/Gate14Re_ME_Status.v27.json":
        "17c9e19bd5a27b6c6db7e8b50894cb87cad24e11fe9ab61d687bb07f10ea82c0",
    "Research/Verification/Gate14Re-ME/qualification-planning-freeze-v2-attempt-001/qualification-design-freeze.v2.json":
        "067736663b75c7d4fdb545e947959da787a0ee727c276fd0a6e9385bd831f390",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/terminal-receipt.v1.json":
        "7ca501b6c7f40dde2958aac6c9cd37984ff788a55dadf1df494a9e2a0e4f05f3",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json":
        "7e0cbe77cb8bb8f84642856c6356d318f708e168b52a92e6e348cdf948169aca",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl":
        "328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471",
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json":
        "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json":
        "1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117",
    "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json":
        "abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-schedule-schema.v1.json":
        "8a96a5a53d22617ef90134ac1a57e3b7115e5ea7ce03a6739c632fd52119f8a5",
    "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json":
        "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-execution-contract.v1.json":
        "6fd3b87e5a7fba5398335bd77d8620c65a5e28576636ae47cf157a6df06c7654",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json":
        "bef0f0c143f325eb7b3ad9e5401cc89bc7d6ff3938287a9b049e985aac04e887",
    "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json":
        "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb",
    "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json":
        "c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312",
    "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json":
        "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce",
    "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json":
        "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e",
    "Research/Gate14Re-ME/Execution/v1/Run-Gate14ReMELoadQualification.v1.ps1":
        "f3356d2ef61866700496d8426995d2956f4d5f2f20911a50aade455e683d02e3",
    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs":
        "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v2.py":
        "daa1fc48077cc0cb8c62221956355a35c74e8b946660b683f7178e2072e9bc0e",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2.py":
        "5e9f8d8c3403321fb9e1b2b3f67fef00a963bf85f25c66d98bc2c41971434ec4",
    "Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json":
        "1e3a70d6be62554027ca639b6a3c7d896fd232906d627962d8c296e9e884c8dd",
    "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json":
        "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06",
    "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/terminal-receipt.v1.json":
        "ab522787fba973f3441e4d32a2de97244a8b44540f74017d4d15d000af1253db",
    "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1":
        "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27",
    "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/known-answer-receipt.v1.json":
        "ad64fb2bce32f2e6206f6f1f80baa30f273be212075603ee631f61b560cc1b63",
    "Research/Verification/Gate14Re-ME/qualification-implementation-freeze-attempt-001/implementation-manifest.v1.json":
        "9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4",
}

RUNTIME_HASHES = {
    r"H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe":
        "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf",
    r"C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe":
        "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1",
    r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe":
        "8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e",
}


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(relative_path: str) -> dict[str, Any]:
    with (PROJECT_ROOT / pathlib.PurePosixPath(relative_path)).open(
        "r", encoding="utf-8-sig"
    ) as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {relative_path}")
    return value


def read_text(relative_path: str) -> str:
    return (PROJECT_ROOT / pathlib.PurePosixPath(relative_path)).read_text(
        encoding="utf-8-sig"
    )


def main() -> int:
    checks: list[dict[str, Any]] = []

    def check(check_id: str, passed: bool, observed: Any, expected: Any) -> None:
        checks.append(
            {
                "checkId": check_id,
                "passed": bool(passed),
                "observed": observed,
                "expected": expected,
            }
        )

    for relative_path, expected in EXPECTED_HASHES.items():
        path = PROJECT_ROOT / pathlib.PurePosixPath(relative_path)
        actual = file_sha256(path) if path.is_file() else None
        check(f"HASH::{relative_path}", actual == expected, actual, expected)

    for path_text, expected in RUNTIME_HASHES.items():
        path = pathlib.Path(path_text)
        actual = file_sha256(path) if path.is_file() else None
        check(f"RUNTIME_HASH::{path.name}", actual == expected, actual, expected)

    planning_terminal = load_json(
        "Research/Verification/Gate14Re-ME/"
        "qualification-planning-asset-generation-v2-attempt-001/"
        "terminal-receipt.v1.json"
    )
    check(
        "UPSTREAM::PLANNING_ASSETS_TERMINAL",
        planning_terminal.get("status")
        == "PASS_QUALIFICATION_PLANNING_ASSETS_FROZEN_V2"
        and planning_terminal.get("passed") is True,
        {
            "status": planning_terminal.get("status"),
            "passed": planning_terminal.get("passed"),
        },
        {
            "status": "PASS_QUALIFICATION_PLANNING_ASSETS_FROZEN_V2",
            "passed": True,
        },
    )
    cardinality = planning_terminal.get("cardinality", {})
    check(
        "UPSTREAM::PLANNING_CARDINALITY",
        cardinality.get("coreInputBundles") == 144
        and cardinality.get("stressInputBundles") == 18
        and cardinality.get("totalInputBundles") == 162
        and cardinality.get("scheduleRows") == 162
        and cardinality.get("qualificationObservationsGenerated") == 0,
        cardinality,
        {
            "coreInputBundles": 144,
            "stressInputBundles": 18,
            "totalInputBundles": 162,
            "scheduleRows": 162,
            "qualificationObservationsGenerated": 0,
        },
    )

    schedule_path = PROJECT_ROOT / (
        "Research/Verification/Gate14Re-ME/"
        "qualification-planning-asset-generation-v2-attempt-001/"
        "planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl"
    )
    schedule_rows = [
        json.loads(line)
        for line in schedule_path.read_text(encoding="utf-8-sig").splitlines()
        if line.strip()
    ]
    replacement_null_rows = sum(row.get("replacement") is None for row in schedule_rows)
    check("ASSETS::SCHEDULE_ROWS", len(schedule_rows) == 162, len(schedule_rows), 162)
    check(
        "ASSETS::UNIQUE_SUPERBLOCKS",
        len({row.get("superblockId") for row in schedule_rows}) == 162,
        len({row.get("superblockId") for row in schedule_rows}),
        162,
    )
    check(
        "ASSETS::REPLACEMENT_BINDINGS",
        replacement_null_rows == 0,
        {
            "rowsWithNullReplacement": replacement_null_rows,
            "rowsWithBoundReplacement": len(schedule_rows) - replacement_null_rows,
        },
        {"rowsWithNullReplacement": 0, "rowsWithBoundReplacement": 162},
    )

    output_schema = load_json(
        "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json"
    )
    raw_table_ids = [table.get("tableId") for table in output_schema.get("rawTables", [])]
    expected_table_ids = [
        "oracle-agent-checks",
        "oracle-event-checks",
        "operations",
        "event-groups",
        "d3-windows",
        "persistent-state",
        "process-resources",
        "empty-boundary",
        "replacement-ledger",
        "failures-and-voids",
    ]
    check(
        "OUTPUT::COMPLETE_RAW_TABLE_SET",
        raw_table_ids == expected_table_ids,
        raw_table_ids,
        expected_table_ids,
    )
    delivery_views = output_schema.get("deliveryViews", {})
    check(
        "OUTPUT::COMPLETE_ROW_DELIVERY",
        delivery_views.get("aggregateOnlyAllowed") is False
        and delivery_views.get("rowIdentityPreservedAcrossViews") is True
        and "JSON Lines" in str(delivery_views.get("losslessCanonical", ""))
        and "CSV" in str(delivery_views.get("humanPortable", ""))
        and "gzip" in str(delivery_views.get("compressedPortable", ""))
        and "Parquet" in str(delivery_views.get("typedAnalytical", "")),
        delivery_views,
        "all raw rows preserved in JSONL, CSV, gzip JSONL, and typed Parquet",
    )

    trusted_rule = load_json(
        "Research/Verification/Gate14Re-ME/"
        "unity-executable-identity-rule-offline-adjudication-attempt-005/"
        "trusted-launch-identity-rule.v1.json"
    )
    requirements = trusted_rule.get("requirements", {})
    identity_required_keys = [
        "externalThreePhaseExpectedSha256AndIndependentMethodAgreement",
        "external64KiBChunksPathFileIdPeSignerAndMetadataStable",
        "pidCreationTimePathCommandLineAndExecuteMethodBound",
        "inProcessPathSourcesAndStructuralIdentityStable",
        "knownAnswersPassed",
        "normalExitAndPostExitReconfirmationRequired",
    ]
    check(
        "IDENTITY::TRUSTED_RULE_REQUIREMENTS",
        all(requirements.get(key) is True for key in identity_required_keys)
        and requirements.get("fileReadAllBytesRole") == "DIAGNOSTIC_ONLY"
        and requirements.get("anyAuthoritativeMismatchDisposition")
        == "FAIL_CLOSED_NO_ADOPTION",
        {key: requirements.get(key) for key in identity_required_keys}
        | {
            "fileReadAllBytesRole": requirements.get("fileReadAllBytesRole"),
            "anyAuthoritativeMismatchDisposition": requirements.get(
                "anyAuthoritativeMismatchDisposition"
            ),
        },
        "all authoritative identity requirements enabled and fail closed",
    )
    timestamp_receipt = load_json(
        "Research/Verification/Gate14Re-ME/"
        "unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/"
        "known-answer-receipt.v1.json"
    )
    check(
        "IDENTITY::TIMESTAMP_COMPARATOR_QUALIFIED",
        timestamp_receipt.get("status")
        == "PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER"
        and timestamp_receipt.get("passed") is True
        and timestamp_receipt.get("unityInvocationCount") == 0,
        {
            "status": timestamp_receipt.get("status"),
            "passed": timestamp_receipt.get("passed"),
            "unityInvocationCount": timestamp_receipt.get("unityInvocationCount"),
        },
        {
            "status": "PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER",
            "passed": True,
            "unityInvocationCount": 0,
        },
    )

    supervisor_path = (
        "Research/Gate14Re-ME/Execution/v1/"
        "Run-Gate14ReMELoadQualification.v1.ps1"
    )
    supervisor = read_text(supervisor_path)
    runner_path = (
        "Assets/_Scripts/Research/Editor/"
        "Gate14ReMELoadQualificationRunnerV2.cs"
    )
    runner = read_text(runner_path)
    implementation_manifest = load_json(
        "Research/Verification/Gate14Re-ME/"
        "qualification-implementation-freeze-attempt-001/"
        "implementation-manifest.v1.json"
    )
    manifest_paths = {
        artifact.get("relativePath")
        for artifact in implementation_manifest.get("artifacts", [])
        if isinstance(artifact, dict)
    }

    check(
        "EXECUTION::SUPERVISOR_RUNNER_V2",
        "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run" in supervisor
        and "Gate14ReMELoadQualificationRunnerV1.Run" not in supervisor,
        "RunnerV1 is frozen in the current supervisor"
        if "Gate14ReMELoadQualificationRunnerV1.Run" in supervisor
        else "RunnerV1 token absent",
        "RunnerV2 execute method only",
    )
    check(
        "EXECUTION::RECEIPT_VERSION_ALIGNMENT",
        all(
            token in supervisor
            for token in (
                "lane-receipt.v2.json",
                "empty-boundary-receipt.v2.json",
                "instrument-csharp-receipt.v2.json",
            )
        )
        and not any(
            token in supervisor
            for token in (
                "lane-receipt.v1.json",
                "empty-boundary-receipt.v1.json",
                "instrument-csharp-receipt.v1.json",
            )
        ),
        {
            "supervisorExpectsV1": [
                token
                for token in (
                    "lane-receipt.v1.json",
                    "empty-boundary-receipt.v1.json",
                    "instrument-csharp-receipt.v1.json",
                )
                if token in supervisor
            ],
            "runnerEmitsV2": [
                token
                for token in (
                    "lane-receipt.v2.json",
                    "empty-boundary-receipt.v2.json",
                    "instrument-csharp-receipt.v2.json",
                )
                if token in runner
            ],
        },
        "supervisor and RunnerV2 both use v2 receipts",
    )
    required_manifest_paths = {
        runner_path,
        "Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json",
        "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json",
        "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json",
        "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json",
        "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v2.py",
        "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2.py",
    }
    missing_manifest_paths = sorted(required_manifest_paths - manifest_paths)
    check(
        "EXECUTION::CURRENT_IMPLEMENTATION_MANIFEST",
        not missing_manifest_paths
        and implementation_manifest.get("status")
        != "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED",
        {
            "status": implementation_manifest.get("status"),
            "missingCurrentBindings": missing_manifest_paths,
            "runnerSelfCheckRequiresCurrentRunnerHash":
                "ManifestContains(manifest, RunnerRelativePath" in runner,
        },
        "compiled/current execution manifest containing every v2/v3 binding",
    )
    check(
        "EXECUTION::TRUSTED_IDENTITY_WIRED",
        all(
            token in supervisor
            for token in (
                "trusted-launch-identity-rule.v1.json",
                "Gate14ReMETrustedTimestampComparatorV1.ps1",
                "CreationDate",
                "ExecutablePath",
                "CommandLine",
            )
        ),
        {
            "trustedRuleReference": "trusted-launch-identity-rule.v1.json" in supervisor,
            "timestampComparatorReference":
                "Gate14ReMETrustedTimestampComparatorV1.ps1" in supervisor,
            "pidCreationPathCommandLineComposite": all(
                token in supervisor
                for token in ("CreationDate", "ExecutablePath", "CommandLine")
            ),
            "onlyPrelaunchFileHashObserved":
                "Get-FileHash" in supervisor and "post-exit" not in supervisor.lower(),
        },
        "three-phase trusted identity, process composite identity, comparator, and post-exit reconfirmation",
    )
    check(
        "EXECUTION::POST_ACQUISITION_STRUCTURAL_DELIVERY_COMMIT",
        "gate14re_me_qualification_structural_v2.py" in supervisor
        and "gate14re_me_qualification_delivery_v2.py" in supervisor,
        {
            "structuralV2Called":
                "gate14re_me_qualification_structural_v2.py" in supervisor,
            "deliveryV2Called":
                "gate14re_me_qualification_delivery_v2.py" in supervisor,
            "currentTerminalState":
                "QUALIFICATION-RAW-COMMIT-PENDING"
                if "QUALIFICATION-RAW-COMMIT-PENDING" in supervisor
                else None,
        },
        "structural v2 validation followed by complete per-row delivery v2 commit",
    )
    required_launch_bindings = (
        "planning-assets-freeze-manifest.v1.json",
        "load-qualification-input-schema.v2.json",
        "load-qualification-output-schema.v2.json",
        "d3-cumulative-managed-allocation-contract.qualified.v1.json",
        "trusted-launch-identity-rule.v1.json",
        "typed-parquet-runtime-manifest.v1.json",
    )
    check(
        "EXECUTION::LAUNCH_RECEIPT_COMPLETE_BINDINGS",
        all(token in supervisor for token in required_launch_bindings),
        {
            "present": [token for token in required_launch_bindings if token in supervisor],
            "missing": [token for token in required_launch_bindings if token not in supervisor],
        },
        list(required_launch_bindings),
    )

    reserved_roots = [
        PROJECT_ROOT / "Research/PilotRuns/Gate14Re-ME",
        PROJECT_ROOT / "Research/PilotRuns/Gate14Re-ME/load-qualification",
        PROJECT_ROOT
        / "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001",
    ]
    existing_reserved_roots = [
        str(path.relative_to(PROJECT_ROOT)).replace("\\", "/")
        for path in reserved_roots
        if path.exists()
    ]
    check(
        "BOUNDARY::MEASURED_ROOT_NOT_CREATED",
        not existing_reserved_roots,
        existing_reserved_roots,
        [],
    )

    powershell = pathlib.Path(
        r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    )
    query = (
        "$p=@(Get-CimInstance Win32_Process -Filter \"Name='Unity.exe'\" | "
        "Where-Object { $_.CommandLine -like '*Gate14ReME*' -or "
        "$_.CommandLine -like '*Gate14Re-ME*' }); "
        "[pscustomobject]@{count=$p.Count;pids=@($p.ProcessId)} | "
        "ConvertTo-Json -Compress"
    )
    process_result = subprocess.run(
        [str(powershell), "-NoProfile", "-Command", query],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    process_snapshot: dict[str, Any]
    if process_result.returncode == 0:
        process_snapshot = json.loads(process_result.stdout.strip())
    else:
        process_snapshot = {
            "queryError": process_result.stderr.strip(),
            "returnCode": process_result.returncode,
        }
    check(
        "BOUNDARY::NO_GATE14RE_ME_UNITY_PROCESS",
        process_snapshot.get("count") == 0,
        process_snapshot,
        {"count": 0, "pids": []},
    )

    hard_blocker_checks = {
        "EXECUTION::SUPERVISOR_RUNNER_V2",
        "EXECUTION::RECEIPT_VERSION_ALIGNMENT",
        "EXECUTION::CURRENT_IMPLEMENTATION_MANIFEST",
        "EXECUTION::TRUSTED_IDENTITY_WIRED",
        "EXECUTION::POST_ACQUISITION_STRUCTURAL_DELIVERY_COMMIT",
        "EXECUTION::LAUNCH_RECEIPT_COMPLETE_BINDINGS",
    }
    hard_blockers = [
        item["checkId"]
        for item in checks
        if item["checkId"] in hard_blocker_checks and not item["passed"]
    ]
    upstream_or_boundary_failures = [
        item["checkId"]
        for item in checks
        if not item["passed"]
        and (
            item["checkId"].startswith("HASH::")
            or item["checkId"].startswith("RUNTIME_HASH::")
            or item["checkId"].startswith("UPSTREAM::")
            or item["checkId"].startswith("OUTPUT::")
            or item["checkId"].startswith("IDENTITY::")
            or item["checkId"].startswith("BOUNDARY::")
        )
    ]
    report = {
        "schema": "gate14re-me-qualification-execution-readiness-audit-v1",
        "studyId": "Gate14Re-ME",
        "protocolId": "gate14re-me-load-qualification-v1",
        "designId": "gate14re-me-load-qualification-planning-v2",
        "attemptId": "qualification-execution-readiness-freeze-attempt-001",
        "mode": "READ_ONLY_OFFLINE_PRELAUNCH_AUDIT",
        "status": (
            "FAIL_CLOSED_EXECUTION_CHAIN_NOT_READY"
            if hard_blockers or upstream_or_boundary_failures
            else "PASS_EXECUTION_CHAIN_READY_FOR_SEPARATE_EXECUTION_AUTHORIZATION"
        ),
        "passed": not hard_blockers and not upstream_or_boundary_failures,
        "checks": checks,
        "summary": {
            "totalChecks": len(checks),
            "passedChecks": sum(item["passed"] for item in checks),
            "failedChecks": sum(not item["passed"] for item in checks),
            "hardBlockers": hard_blockers,
            "upstreamOrBoundaryFailures": upstream_or_boundary_failures,
            "capabilityGaps": [
                {
                    "gapId": "CAP-001-NO-PREGENERATED-WHOLE-SUPERBLOCK-REPLACEMENTS",
                    "rowsWithBoundReplacement": len(schedule_rows)
                    - replacement_null_rows,
                    "rowsWithNullReplacement": replacement_null_rows,
                    "classification": "NONBLOCKING_FOR_THIS_OFFLINE_AUDIT_BUT_REQUIRES_EXPLICIT_PREEXECUTION_DISPOSITION",
                    "effect": "a primary technical failure would fail closed because no frozen replacement is bound",
                }
            ],
        },
        "scientificBoundary": {
            "measuredRootCreated": False,
            "unityInvocationCount": 0,
            "plannerInvocationCount": 0,
            "algorithmLaneExecutionCount": 0,
            "qualificationObservationCount": 0,
            "formalObservationCount": 0,
            "analysisPerformed": False,
            "rankingPerformed": False,
            "winnerAdjudicationPerformed": False,
            "sealedIdentityMappingDisclosed": False,
        },
    }
    json.dump(report, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0 if report["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
