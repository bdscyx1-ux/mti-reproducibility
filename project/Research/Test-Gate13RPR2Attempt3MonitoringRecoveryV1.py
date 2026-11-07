#!/usr/bin/env python3
"""Validation-only test harness for attempt-3 monitoring/recovery v1.

The harness creates only synthetic evidence below an explicitly supplied
verification root.  It never creates the real formal root/receipt/status and
never launches Unity.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone, timedelta
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
from typing import Any, Callable

import Gate13RPR2Attempt3MonitoringRecoveryV1 as MON


UTC = timezone.utc
PROJECT = Path(__file__).resolve().parent.parent
REAL_FORMAL_ROOT = PROJECT / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3"
REAL_RECEIPT = PROJECT / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
REAL_STATUS = PROJECT / "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"
UNITY_LOCK = PROJECT / "Temp/UnityLockfile"
PYTHON = Path(sys.executable).resolve()


def require(condition: Any, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(MON.canonical_json_bytes(value))


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def iso(value: datetime) -> str:
    return MON.iso_utc(value)


class Fixture:
    def __init__(self, root: Path, name: str, now: datetime, status_name: str = "ACQUISITION-RUNNING") -> None:
        self.root = root / name
        self.root.mkdir(parents=True, exist_ok=False)
        self.formal_root = (self.root / "synthetic-formal-root").resolve()
        self.receipt_path = (self.root / "synthetic-receipt.json").resolve()
        self.status_path = (self.root / "synthetic-status.json").resolve()
        self.monitor_root = (self.root / "synthetic-monitoring").resolve()
        self.config_path = (self.root / "synthetic-config.json").resolve()
        self.schema_path = (self.root / "synthetic-status-schema.json").resolve()
        self.os_path = (self.root / "synthetic-os-query.json").resolve()
        self.formal_root.mkdir()
        self.receipt = {
            "schemaVersion": 1,
            "receiptKind": "synthetic-formal-attempt3-receipt",
            "formalAttemptOrdinal": 3,
            "formalRoot": str(self.formal_root),
            "synthetic": True,
        }
        write_json(self.receipt_path, self.receipt)
        started = now - timedelta(hours=2)
        self.status = {
            "schemaVersion": 1,
            "statusKind": "gate13r-pr2-formal-attempt3-operational-status-v1",
            "savedAtUtc": iso(now),
            "status": status_name,
            "formalAttemptOrdinal": 3,
            "formalRoot": str(self.formal_root),
            "executionReceiptSha256": hash_file(self.receipt_path),
            "candidateConfigSha256": "c8d3e9965ae72798e2366c0187a96e578df306bb68196f54039c421672b78042",
            "scheduleSha256": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
            "startedAtUtc": iso(started),
            "lastDurableCheckpointAtUtc": iso(now - timedelta(minutes=1)),
            "completedProcessCount": 100,
            "completedSampleCount": 300,
            "totalProcessCount": 3552,
            "totalSampleCount": 10176,
            "currentGlobalProcessOrdinal": 101,
            "currentCampaignId": "shared-campaign-001",
            "currentScenarioId": "scenario-001",
            "currentCohort": "shared-four-algorithm",
            "currentBlockId": "block-000101",
            "currentMatchedSuperblockId": None,
            "currentABBAOrder": None,
            "currentWilliamsRow": 1,
            "currentUnityProcessId": 4242,
            "currentUnityProcessStartedAtUtc": iso(now - timedelta(minutes=5)),
            "currentUnityBlockStartedAtUtc": iso(now - timedelta(minutes=5)),
            "latestWorkingSetBytes": 500_000_000,
            "latestPrivateMemoryBytes": 450_000_000,
            "latestAvailablePhysicalMemoryBytes": 20_000_000_000,
            "outputFileCount": 900,
            "rawBytes": 123_456_789,
            "advisoryCrossingCount": 2,
            "rawDataComplete": False,
            "analysisAuthorized": False,
            "gate14RAuthorized": False,
            "automaticMeasuredRetryAttempted": False,
            "automaticResumeAttempted": False,
            "automaticTopUpAttempted": False,
            "partialAttemptMergeAttempted": False,
            "errorReasonCode": None,
            "failureCheckpointPath": None,
        }
        self.config = deepcopy(read_json(MON.DEFAULT_CONFIG))
        self.config["formalRoot"] = str(self.formal_root)
        self.config["formalReceipt"] = str(self.receipt_path)
        self.config["formalStatus"] = str(self.status_path)
        self.config["monitoringRoot"] = str(self.monitor_root)
        self.config["readRetry"] = {"maxAttempts": 3, "delaySeconds": [0, 0, 0]}
        write_json(self.config_path, self.config)
        schema = deepcopy(read_json(MON.DEFAULT_STATUS_SCHEMA))
        schema["properties"]["formalRoot"]["const"] = str(self.formal_root)
        write_json(self.schema_path, schema)
        self.os = {
            "exists": True,
            "pid": 4242,
            "name": "Unity",
            "startTimeUtc": self.status["currentUnityProcessStartedAtUtc"],
            "workingSetBytes": 501_000_000,
            "privateMemoryBytes": 451_000_000,
            "availablePhysicalMemoryBytes": 19_999_000_000,
            "commandLine": f'Unity.exe -projectPath "{PROJECT}" -blockId block-000101',
        }
        self.save()

    def save(self) -> None:
        write_json(self.status_path, self.status)
        write_json(self.os_path, self.os)

    def snapshot(self, now: datetime, previous: Path | None = None, skip_os: bool = False) -> dict[str, Any]:
        self.save()
        return MON.build_snapshot(
            self.config_path,
            now=now,
            previous_snapshot_path=previous,
            os_fixture_path=self.os_path,
            status_schema_path=self.schema_path,
            skip_os_query=skip_os,
            sleeper=lambda _: None,
        )

    def store_previous(self, snapshot: dict[str, Any], name: str = "previous.json") -> Path:
        path = self.root / name
        write_json(path, snapshot)
        return path


class Harness:
    def __init__(self, output_root: Path) -> None:
        self.output_root = output_root.resolve()
        self.fixture_root = self.output_root / "fixture-work"
        self.checks: list[dict[str, Any]] = []

    def check(self, check_id: str, function: Callable[[], None]) -> None:
        try:
            function()
            self.checks.append({"id": check_id, "passed": True})
        except BaseException as error:
            self.checks.append(
                {
                    "id": check_id,
                    "passed": False,
                    "errorType": type(error).__name__,
                    "error": str(error),
                    "traceback": traceback.format_exc(),
                }
            )

    def new_fixture(self, name: str, now: datetime, status_name: str = "ACQUISITION-RUNNING") -> Fixture:
        return Fixture(self.fixture_root, name, now, status_name)


def unity_processes() -> list[dict[str, Any]]:
    command = (
        "$p=@(Get-CimInstance Win32_Process -ErrorAction Stop|"
        "Where-Object{$_.Name -in @('Unity.exe','UnityCrashHandler64.exe','UnityCrashHandler32.exe')}|"
        "Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine);"
        "ConvertTo-Json -Compress -InputObject @($p)"
    )
    completed = subprocess.run(
        ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    value = json.loads(completed.stdout or "[]")
    return value if isinstance(value, list) else [value]


def run_wrapper_preview(engine: str) -> dict[str, Any]:
    wrapper = PROJECT / "Research/Get-Gate13RPR2Attempt3OperationalProgressV1.ps1"
    completed = subprocess.run(
        [engine, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(wrapper), "-ProjectPath", str(PROJECT), "-CommandPreviewOnly"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8-sig",
        errors="replace",
        timeout=60,
    )
    return json.loads(completed.stdout)


def run(output_root: Path) -> dict[str, Any]:
    if output_root.exists():
        raise RuntimeError(f"Verification attempt root already exists: {output_root}")
    output_root.mkdir(parents=True, exist_ok=False)
    harness = Harness(output_root)
    harness.fixture_root.mkdir()
    started = datetime.now(UTC)
    upstream_before = {}
    design_manifest_path = PROJECT / "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Design_Freeze_Manifest.v1.json"
    design_manifest = read_json(design_manifest_path)
    for item in design_manifest["files"]:
        path = PROJECT / item["relativePath"]
        upstream_before[item["relativePath"]] = hash_file(path)
    addendum_path = PROJECT / "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Design_Freeze_Addendum.v1.json"
    expectations_path = PROJECT / "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Synthetic_Expectations.v1.json"

    MON.atomic_create_json(
        output_root / "attempt-start-receipt.json",
        {
            "schemaVersion": 1,
            "receiptKind": "gate13r-pr2-attempt3-monitoring-recovery-validation-start-v1",
            "startedAtUtc": iso(started),
            "outputRoot": str(output_root),
            "formalRootCreated": False,
            "formalReceiptCreated": False,
            "formalStatusCreated": False,
            "unityLaunchAuthorized": False,
        },
    )

    # 1-5: identity and preservation.
    harness.check("T01-json-and-schema-parse", lambda: [read_json(PROJECT / name) for name in [
        "Research/Gate13R_PR2_Attempt3_Monitoring_Config.v1.json",
        "Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v1.json",
        "Research/Gate13R_PR2_Attempt3_Operational_Status_Schema.v1.json",
        "Research/Gate13R_PR2_Attempt3_Progress_Snapshot_Schema.v1.json",
        "Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Synthetic_Expectations.v1.json",
    ]])

    def verify_frozen_hashes() -> None:
        for item in design_manifest["files"]:
            require(hash_file(PROJECT / item["relativePath"]) == item["sha256"], item["relativePath"])
        addendum = read_json(addendum_path)
        require(hash_file(design_manifest_path) == addendum["parentManifest"]["sha256"], "parent manifest")
        require(hash_file(expectations_path) == addendum["syntheticExpectationRegistry"]["sha256"], "expectations")
    harness.check("T02-frozen-design-hashes", verify_frozen_hashes)
    harness.check("T03-real-formal-targets-absent-pre", lambda: require(not any(path.exists() for path in [REAL_FORMAL_ROOT, REAL_RECEIPT, REAL_STATUS]), "real formal target exists"))
    harness.check("T04-zero-unity-and-lock-pre", lambda: require(not unity_processes() and not UNITY_LOCK.exists(), "Unity process or lock exists"))

    def no_launch_tokens() -> None:
        source = (PROJECT / "Research/Gate13RPR2Attempt3MonitoringRecoveryV1.py").read_text(encoding="utf-8")
        wrapper = (PROJECT / "Research/Get-Gate13RPR2Attempt3OperationalProgressV1.ps1").read_text(encoding="utf-8")
        for token in ("-executeMethod", "-batchmode", "Start-Process", "Run-Gate13RPR2MP2FormalBlock", "TerminateProcess", "Stop-Process"):
            require(token not in source and token not in wrapper, token)
    harness.check("T05-static-no-unity-launch-or-kill", no_launch_tokens)

    # 6: absent targets.
    def no_targets() -> None:
        now = datetime(2026, 10, 9, 8, 0, tzinfo=UTC)
        fixture_dir = harness.fixture_root / "no-targets"
        fixture_dir.mkdir()
        config = deepcopy(read_json(MON.DEFAULT_CONFIG))
        config.update({
            "formalRoot": str((fixture_dir / "missing-formal").resolve()),
            "formalReceipt": str((fixture_dir / "missing-receipt.json").resolve()),
            "formalStatus": str((fixture_dir / "missing-status.json").resolve()),
            "monitoringRoot": str((fixture_dir / "monitor").resolve()),
            "readRetry": {"maxAttempts": 3, "delaySeconds": [0, 0, 0]},
        })
        config_path = fixture_dir / "config.json"
        write_json(config_path, config)
        snapshot = MON.build_snapshot(config_path, now=now, skip_os_query=True, sleeper=lambda _: None)
        expected = read_json(expectations_path)["expected"]["allFormalTargetsAbsent"]
        require(snapshot["status"] == expected["status"] and snapshot["notify"] is expected["notify"], "not-started mismatch")
        require(MON.persist_snapshot(snapshot, Path(config["monitoringRoot"]), config_path) is None, "not-started snapshot written")
    harness.check("T06-all-targets-absent-not-started-quiet", no_targets)

    # 7: partial target set.
    def partial_targets() -> None:
        now = datetime(2026, 10, 9, 8, 0, tzinfo=UTC)
        fixture_dir = harness.fixture_root / "partial-targets"
        fixture_dir.mkdir()
        (fixture_dir / "formal").mkdir()
        config = deepcopy(read_json(MON.DEFAULT_CONFIG))
        config.update({
            "formalRoot": str((fixture_dir / "formal").resolve()),
            "formalReceipt": str((fixture_dir / "missing-receipt.json").resolve()),
            "formalStatus": str((fixture_dir / "missing-status.json").resolve()),
            "monitoringRoot": str((fixture_dir / "monitor").resolve()),
            "readRetry": {"maxAttempts": 3, "delaySeconds": [0, 0, 0]},
        })
        path = fixture_dir / "config.json"
        write_json(path, config)
        snapshot = MON.build_snapshot(path, now=now, skip_os_query=True, sleeper=lambda _: None)
        require(snapshot["status"] == "ACTION-REQUIRED" and snapshot["notify"], "partial target accepted")
    harness.check("T07-partial-target-action-required", partial_targets)

    # 8-18: valid state, cadence, blinding, output isolation.
    base_time = datetime(2026, 10, 9, 8, 0, tzinfo=UTC)
    fixture8 = harness.new_fixture("running-cadence", base_time)
    snap8 = fixture8.snapshot(base_time)
    harness.check("T08-valid-running-operational-fields", lambda: require(snap8["progress"]["completedProcesses"] == 100 and snap8["telemetry"]["osQueryStatus"] == "MATCHED", "running fixture"))
    harness.check("T09-first-running-start-event", lambda: require(snap8["notificationReason"] == ["ACQUISITION-STARTED"], str(snap8["notificationReason"])))
    prev8 = fixture8.store_previous(snap8)

    def before_hour() -> None:
        later = base_time + timedelta(minutes=59)
        fixture8.status["savedAtUtc"] = iso(later)
        fixture8.status["lastDurableCheckpointAtUtc"] = iso(later)
        fixture8.status["currentUnityBlockStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.status["currentUnityProcessStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.os["startTimeUtc"] = fixture8.status["currentUnityProcessStartedAtUtc"]
        snap = fixture8.snapshot(later, prev8)
        require("HOURLY-PROGRESS" not in snap["notificationReason"], str(snap["notificationReason"]))
    harness.check("T10-before-next-hour-no-report", before_hour)

    def next_hour() -> None:
        later = base_time + timedelta(hours=1)
        fixture8.status["savedAtUtc"] = iso(later)
        fixture8.status["lastDurableCheckpointAtUtc"] = iso(later)
        fixture8.status["currentUnityBlockStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.status["currentUnityProcessStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.os["startTimeUtc"] = fixture8.status["currentUnityProcessStartedAtUtc"]
        snap = fixture8.snapshot(later, prev8)
        require(snap["notificationReason"].count("HOURLY-PROGRESS") == 1, str(snap["notificationReason"]))
    harness.check("T11-new-hour-exactly-one-report", next_hour)

    def missed_slots() -> None:
        later = base_time + timedelta(hours=4)
        fixture8.status["savedAtUtc"] = iso(later)
        fixture8.status["lastDurableCheckpointAtUtc"] = iso(later)
        fixture8.status["currentUnityBlockStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.status["currentUnityProcessStartedAtUtc"] = iso(later - timedelta(minutes=1))
        fixture8.os["startTimeUtc"] = fixture8.status["currentUnityProcessStartedAtUtc"]
        snap = fixture8.snapshot(later, prev8)
        require(snap["notificationReason"] == ["HOURLY-PROGRESS"], str(snap["notificationReason"]))
    harness.check("T12-missed-slots-no-catchup-flood", missed_slots)

    def transition_notification(status_name: str, expected_reason: str, name: str) -> tuple[dict[str, Any], Path, Fixture]:
        fx = harness.new_fixture(name, base_time, status_name)
        if status_name == MON.RAW_COMPLETE:
            fx.status.update({"completedProcessCount": 3552, "completedSampleCount": 10176, "rawDataComplete": True, "currentGlobalProcessOrdinal": None})
        if status_name == MON.TERMINAL_FAILURE:
            fx.status["errorReasonCode"] = "SYNTHETIC-HARD-FAIL"
        snap = fx.snapshot(base_time, skip_os=True)
        require(expected_reason in snap["notificationReason"], str(snap["notificationReason"]))
        return snap, fx.store_previous(snap), fx
    harness.check("T13-failure-event-immediate", lambda: transition_notification(MON.TERMINAL_FAILURE, "ACQUISITION-FAILED", "failure-transition"))
    completion_holder: dict[str, Any] = {}
    def completion_event() -> None:
        snap, path, fx = transition_notification(MON.RAW_COMPLETE, "RAW-DATA-COMPLETE", "complete-transition")
        completion_holder.update({"snap": snap, "path": path, "fx": fx})
    harness.check("T14-completion-event-immediate", completion_event)
    harness.check("T15-acknowledged-terminal-quiet", lambda: require(not completion_holder["fx"].snapshot(base_time + timedelta(minutes=5), completion_holder["path"], skip_os=True)["notify"], "terminal repeated"))

    allowed_keys = set(read_json(MON.DEFAULT_SNAPSHOT_SCHEMA)["properties"].keys())
    harness.check("T16-snapshot-complete-allowed-top-level", lambda: require(set(snap8.keys()) == allowed_keys, f"keys={set(snap8)-allowed_keys}"))

    def blinding() -> None:
        patterns = fixture8.config["blinding"]["forbiddenFieldPatterns"]
        require(not MON.recursively_find_forbidden(snap8, patterns), "snapshot leak")
        require(MON.recursively_find_forbidden({"pValue": 0.01}, patterns), "forbidden fixture not detected")
        report = MON.render_operational_report(snap8).lower()
        for term in ("pvalue", "confidenceinterval", "superiority", "winner", "dynamicHandling".lower()):
            require(term not in report, term)
    harness.check("T17-blinding-and-rendered-report", blinding)

    def output_isolation() -> None:
        path = MON.persist_snapshot(snap8, fixture8.monitor_root, fixture8.config_path)
        require(path is not None and path.exists() and MON.is_relative_to(path, fixture8.monitor_root), "not isolated")
        try:
            MON.persist_snapshot(snap8, fixture8.formal_root, fixture8.config_path)
        except MON.MonitorError:
            return
        raise AssertionError("formal-root write accepted")
    harness.check("T18-monitor-output-isolated-from-formal-root", output_isolation)

    # 19-26: counter, identity, and telemetry failures.
    def counter_regression() -> None:
        fx = harness.new_fixture("counter-regression", base_time)
        prior = fx.snapshot(base_time)
        prior["progress"]["completedProcesses"] = 101
        path = fx.store_previous(prior)
        snap = fx.snapshot(base_time + timedelta(minutes=1), path)
        require(snap["status"] == "ACTION-REQUIRED" and "COUNTER-REGRESSION" in snap["health"]["reasonCodes"], str(snap["health"]))
    harness.check("T19-counter-regression-fail-closed", counter_regression)

    def mutate_status_case(name: str, mutator: Callable[[Fixture], None], expected: str) -> None:
        fx = harness.new_fixture(name, base_time)
        mutator(fx)
        snap = fx.snapshot(base_time)
        require(snap["status"] == "ACTION-REQUIRED", str(snap))
        require(any(expected in code for code in snap["health"]["reasonCodes"]), str(snap["health"]["reasonCodes"]))
    harness.check("T20-count-above-total-rejected", lambda: mutate_status_case("above-total", lambda fx: fx.status.__setitem__("completedProcessCount", 3553), "STATUS-SCHEMA"))
    harness.check("T21-global-ordinal-range-rejected", lambda: mutate_status_case("bad-ordinal", lambda fx: fx.status.__setitem__("currentGlobalProcessOrdinal", 3553), "STATUS-SCHEMA"))
    harness.check("T22-attempt-ordinal-rejected", lambda: mutate_status_case("bad-attempt", lambda fx: fx.status.__setitem__("formalAttemptOrdinal", 2), "STATUS-SCHEMA"))

    def receipt_mismatch() -> None:
        fx = harness.new_fixture("receipt-mismatch", base_time)
        fx.receipt["formalAttemptOrdinal"] = 2
        write_json(fx.receipt_path, fx.receipt)
        fx.status["executionReceiptSha256"] = hash_file(fx.receipt_path)
        snap = fx.snapshot(base_time)
        require(snap["status"] == "ACTION-REQUIRED" and "RECEIPT-ATTEMPT-ORDINAL-MISMATCH" in snap["health"]["reasonCodes"], str(snap["health"]))
    harness.check("T23-root-receipt-config-schedule-identity", receipt_mismatch)

    def composite_mismatch() -> None:
        fx = harness.new_fixture("composite-mismatch", base_time)
        fx.os["startTimeUtc"] = iso(base_time - timedelta(minutes=10))
        snap = fx.snapshot(base_time)
        require(snap["status"] == "ACTION-REQUIRED" and "COMPOSITE-PROCESS-START-MISMATCH" in snap["health"]["reasonCodes"], str(snap["health"]))
    harness.check("T24-composite-process-mismatch-action", composite_mismatch)
    harness.check("T25-invalid-telemetry-action", lambda: mutate_status_case("negative-telemetry", lambda fx: fx.status.__setitem__("latestPrivateMemoryBytes", -1), "STATUS-SCHEMA"))
    harness.check("T26-valid-telemetry-preserved", lambda: require(snap8["telemetry"]["osWorkingSetBytes"] == fixture8.os["workingSetBytes"] and snap8["telemetry"]["statusPrivateMemoryBytes"] == fixture8.status["latestPrivateMemoryBytes"], str(snap8["telemetry"])))

    # 27-32: threshold boundaries and ETA.
    def threshold_snapshot(name: str, status_age: int = 0, no_progress: int | None = None, block_elapsed: int = 60) -> dict[str, Any]:
        now = base_time + timedelta(hours=6)
        fx = harness.new_fixture(name, now)
        fx.status["savedAtUtc"] = iso(now - timedelta(seconds=status_age))
        fx.status["lastDurableCheckpointAtUtc"] = iso(now)
        fx.status["currentUnityBlockStartedAtUtc"] = iso(now - timedelta(seconds=block_elapsed))
        fx.status["currentUnityProcessStartedAtUtc"] = iso(now - timedelta(minutes=1))
        fx.os["startTimeUtc"] = fx.status["currentUnityProcessStartedAtUtc"]
        if no_progress is None:
            return fx.snapshot(now)
        prior = fx.snapshot(now - timedelta(seconds=no_progress))
        prior["progress"]["lastProgressAtUtc"] = iso(now - timedelta(seconds=no_progress))
        prior["progress"]["completedProcesses"] = fx.status["completedProcessCount"]
        path = fx.store_previous(prior)
        return fx.snapshot(now, path)
    harness.check("T27-status-age-exact-boundary", lambda: require("STATUS-STALE-ADVISORY" not in threshold_snapshot("stale-exact", status_age=900)["health"]["reasonCodes"], "exact stale"))
    harness.check("T28-status-age-exclusive-crossing", lambda: require("STATUS-STALE-ADVISORY" in threshold_snapshot("stale-over", status_age=901)["health"]["reasonCodes"], "stale absent"))
    harness.check("T29-no-progress-exact-boundary", lambda: require("STALL-SUSPECTED" not in threshold_snapshot("stall-exact", no_progress=1800)["health"]["reasonCodes"], "exact stall"))
    harness.check("T30-no-progress-exclusive-crossing", lambda: require("STALL-SUSPECTED" in threshold_snapshot("stall-over", no_progress=1801)["health"]["reasonCodes"], "stall absent"))

    def missing_process_boundary(seconds: int, should_action: bool, name: str) -> None:
        now = base_time + timedelta(hours=8)
        fx = harness.new_fixture(name, now)
        fx.os = {"exists": False, "pid": 4242}
        first = fx.snapshot(now - timedelta(seconds=seconds))
        first["health"]["missingOwnedProcessSinceUtc"] = iso(now - timedelta(seconds=seconds))
        path = fx.store_previous(first)
        fx.status["savedAtUtc"] = iso(now)
        fx.status["lastDurableCheckpointAtUtc"] = iso(now)
        snap = fx.snapshot(now, path)
        require((snap["status"] == "ACTION-REQUIRED") is should_action, str(snap["health"]))
    harness.check("T31-missing-process-exact-boundary", lambda: missing_process_boundary(300, False, "missing-exact"))
    harness.check("T32-missing-process-exclusive-crossing", lambda: missing_process_boundary(301, True, "missing-over"))
    harness.check("T33-hard-timeout-overdue-no-kill", lambda: require("HARD-TIMEOUT-OVERDUE-ACTION-REQUIRED" in threshold_snapshot("timeout-over", block_elapsed=3661)["health"]["reasonCodes"] and not threshold_snapshot("timeout-over-two", block_elapsed=3661)["health"]["monitorMayKillProcess"], "timeout boundary"))

    def eta_smaller_rate() -> None:
        now = base_time + timedelta(hours=10)
        fx = harness.new_fixture("eta-rate", now)
        fx.status["startedAtUtc"] = iso(now - timedelta(hours=10))
        fx.status["completedProcessCount"] = 100
        prior = fx.snapshot(now - timedelta(hours=1))
        prior["progress"]["completedProcesses"] = 80
        prior["timing"]["rollingProcessesPerHour"] = 20.0
        path = fx.store_previous(prior)
        snap = fx.snapshot(now, path)
        require(abs(snap["timing"]["overallProcessesPerHour"] - 10.0) < 1e-9, str(snap["timing"]))
        require(abs(snap["timing"]["conservativeProcessesPerHour"] - 10.0) < 1e-9, str(snap["timing"]))
        expected = (3552 - 100) / 10.0 * 1.25
        require(abs(snap["timing"]["etaHours"] - expected) < 1e-6, str(snap["timing"]))
    harness.check("T34-eta-min-positive-and-safety-factor", eta_smaller_rate)

    def eta_unavailable() -> None:
        now = base_time + timedelta(hours=1)
        fx = harness.new_fixture("eta-unavailable", now)
        fx.status["completedProcessCount"] = 0
        fx.status["completedSampleCount"] = 0
        snap = fx.snapshot(now)
        require(snap["timing"]["etaStatus"] == "UNAVAILABLE" and snap["timing"]["etaHours"] is None, str(snap["timing"]))
    harness.check("T35-eta-zero-rate-unavailable", eta_unavailable)

    # 36-46: pure recovery state machine.
    state_machine = read_json(MON.DEFAULT_STATE_MACHINE)
    eligible_prelaunch = {
        "stage": "PRELAUNCH", "formalRootExists": False, "formalReceiptExists": False,
        "formalStatusExists": False, "measuredProcessCount": 0, "measuredSampleCount": 0,
        "defectClass": "IMPLEMENTATION-BUG", "defectConfinedToNewAttempt3Artifacts": True,
        "frozenInputsUnchanged": True, "targetedValidationPassed": True,
        "repairCycleCount": 0, "recentFailureSignatures": ["A", "B"],
    }
    harness.check("T36-prelaunch-all-requirements-eligible", lambda: require(MON.recovery_decision(eligible_prelaunch, state_machine)["disposition"] == "VERSIONED-PRELAUNCH-REPAIR-ELIGIBLE", "prelaunch"))
    harness.check("T37-prelaunch-root-or-measured-rejects", lambda: require(not MON.recovery_decision({**eligible_prelaunch, "formalRootExists": True}, state_machine)["eligible"] and not MON.recovery_decision({**eligible_prelaunch, "measuredSampleCount": 1}, state_machine)["eligible"], "root/measured"))
    harness.check("T38-never-repairable-classes", lambda: require(all(not MON.recovery_decision({**eligible_prelaunch, "defectClass": code}, state_machine)["eligible"] for code in state_machine["prelaunch"]["neverRepairable"]), "neverRepairable"))
    harness.check("T39-prelaunch-three-cycle-limit", lambda: require(not MON.recovery_decision({**eligible_prelaunch, "repairCycleCount": 3}, state_machine)["eligible"], "cycle limit"))
    harness.check("T40-repeated-signature-stop", lambda: require(not MON.recovery_decision({**eligible_prelaunch, "recentFailureSignatures": ["X", "X"]}, state_machine)["eligible"], "signature stop"))

    acquisition_decision = MON.recovery_decision({"stage": "ACQUISITION"}, state_machine)
    harness.check("T41-acquisition-diagnostics-only", lambda: require(acquisition_decision["disposition"] == "READ-ONLY-DIAGNOSTICS-ONLY" and "RETRY-MEASURED-SAMPLE" in acquisition_decision["forbiddenActions"], str(acquisition_decision)))
    harness.check("T42-acquisition-no-advance", lambda: require("ADVANCE-AFTER-HARD-FAILURE" in acquisition_decision["forbiddenActions"] and "CREATE-ATTEMPT-4" in acquisition_decision["forbiddenActions"], str(acquisition_decision)))
    eligible_commit = {
        "stage": "POST-ACQUISITION-COMMIT", "completedProcessCount": 3552,
        "completedSampleCount": 10176, "acquisitionCompleteEvidencePresent": True,
        "rawTreeIdentityStableAcrossTwoReads": True, "unityProcessCount": 0,
        "unityLockExists": False, "noMeasuredFileMutation": True,
        "syntheticCommitValidationPassed": True, "recoveryAttemptCount": 0,
        "recentFailureSignatures": ["A", "B"],
    }
    harness.check("T43-post-acquisition-commit-eligible", lambda: require(MON.recovery_decision(eligible_commit, state_machine)["disposition"] == "NON-UNITY-RAW-COMMIT-RECOVERY-ELIGIBLE", "commit"))
    harness.check("T44-commit-never-returns-unity", lambda: require(not MON.recovery_decision(eligible_commit, state_machine)["unityCommandAllowed"] and "START-UNITY" in MON.recovery_decision(eligible_commit, state_machine)["forbiddenActions"], "Unity allowed"))
    harness.check("T45-commit-attempt-and-signature-limits", lambda: require(not MON.recovery_decision({**eligible_commit, "recoveryAttemptCount": 3}, state_machine)["eligible"] and not MON.recovery_decision({**eligible_commit, "recentFailureSignatures": ["X", "X"]}, state_machine)["eligible"], "commit limits"))
    harness.check("T46-raw-contract-violation-user-action", lambda: require(MON.recovery_decision({**eligible_commit, "completedSampleCount": 10175}, state_machine)["disposition"] == "USER-ACTION-REQUIRED", "raw contract"))

    # 47-51: retries and immutable persistence.
    def retry_read() -> None:
        calls = {"count": 0}
        def reader(_: Path) -> Any:
            calls["count"] += 1
            if calls["count"] < 3:
                raise OSError("synthetic transient")
            return {"ok": True}
        slept: list[float] = []
        value, anomalies = MON.read_json_with_retry(Path("synthetic"), [0, 2, 5], reader=reader, sleeper=slept.append)
        require(value == {"ok": True} and len(anomalies) == 2 and slept == [2, 5], f"{anomalies}/{slept}")
    harness.check("T47-read-retry-exact-three-0-2-5", retry_read)

    def later_success_anomaly_retained() -> None:
        calls = {"count": 0}
        def reader(_: Path) -> Any:
            calls["count"] += 1
            if calls["count"] == 1:
                raise json.JSONDecodeError("synthetic", "", 0)
            return {"ok": True}
        _, anomalies = MON.read_json_with_retry(Path("synthetic"), [0, 0, 0], reader=reader, sleeper=lambda _: None)
        require(len(anomalies) == 1 and anomalies[0].startswith("READ-ATTEMPT-1"), str(anomalies))
    harness.check("T48-later-read-success-retains-anomaly", later_success_anomaly_retained)

    persisted_holder: dict[str, Any] = {}
    def atomic_persist() -> None:
        fx = harness.new_fixture("atomic-persist", base_time)
        snap = fx.snapshot(base_time)
        path = MON.persist_snapshot(snap, fx.monitor_root, fx.config_path)
        require(path is not None and read_json(path) == snap, "persisted bytes")
        persisted_holder.update({"fx": fx, "snap": snap, "path": path})
    harness.check("T49-atomic-snapshot-under-verification-root", atomic_persist)
    def reject_overwrite() -> None:
        try:
            MON.persist_snapshot(persisted_holder["snap"], persisted_holder["fx"].monitor_root, persisted_holder["fx"].config_path)
        except MON.MonitorError as error:
            require("ALREADY-EXISTS" in str(error), str(error))
            return
        raise AssertionError("overwrite accepted")
    harness.check("T50-immutable-snapshot-overwrite-rejected", reject_overwrite)

    def deterministic() -> None:
        fx = harness.new_fixture("deterministic", base_time)
        first = fx.snapshot(base_time)
        second = fx.snapshot(base_time)
        require(MON.canonical_json_bytes(first) == MON.canonical_json_bytes(second), "not byte-identical")
    harness.check("T51-fixed-fixture-deterministic-bytes", deterministic)

    # 52-54: runtime compatibility and final preservation.
    def runtime_compatibility() -> None:
        require(PYTHON.exists(), str(PYTHON))
        py_compile = subprocess.run([str(PYTHON), "-m", "py_compile", str(PROJECT / "Research/Gate13RPR2Attempt3MonitoringRecoveryV1.py")], check=False, capture_output=True, text=True)
        require(py_compile.returncode == 0, py_compile.stderr)
        for engine in ("pwsh.exe", "powershell.exe"):
            preview = run_wrapper_preview(engine)
            require(preview["unityCommandPresent"] is False and preview["experimentMutationAuthorized"] is False, f"{engine}:{preview}")
    harness.check("T52-python-pwsh-winps-parser-binding", runtime_compatibility)

    def no_launch_dry_run_and_automation_contract() -> None:
        completed = subprocess.run(
            [str(PYTHON), str(PROJECT / "Research/Gate13RPR2Attempt3MonitoringRecoveryV1.py"), "snapshot", "--skip-os-query", "--now-utc", "2026-10-09T08:00:00Z"],
            check=True, capture_output=True, text=True, encoding="utf-8",
        )
        output = json.loads(completed.stdout)
        require(output["snapshot"]["status"] == "NOT-STARTED" and output["writtenPath"] is None, str(output))
        config = read_json(MON.DEFAULT_CONFIG)
        require(config["watcherCadenceMinutes"] == 5 and config["scheduledReportCadenceMinutes"] == 60, str(config))
    harness.check("T53-no-launch-dry-run-and-cadence-contract", no_launch_dry_run_and_automation_contract)

    def final_preservation() -> None:
        require(not any(path.exists() for path in [REAL_FORMAL_ROOT, REAL_RECEIPT, REAL_STATUS]), "real target created")
        require(not unity_processes() and not UNITY_LOCK.exists(), "Unity process or lock exists")
        for relative, before_hash in upstream_before.items():
            require(hash_file(PROJECT / relative) == before_hash, relative)
    harness.check("T54-final-formal-absence-and-frozen-hashes", final_preservation)

    ended = datetime.now(UTC)
    passed_count = sum(1 for check in harness.checks if check["passed"])
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt3-monitoring-recovery-validation-summary-v1",
        "startedAtUtc": iso(started),
        "completedAtUtc": iso(ended),
        "outputRoot": str(output_root),
        "testCount": len(harness.checks),
        "passedTestCount": passed_count,
        "failedTestCount": len(harness.checks) - passed_count,
        "passed": passed_count == len(harness.checks) == 54,
        "unityInvocations": 0,
        "formalRootCreated": REAL_FORMAL_ROOT.exists(),
        "formalReceiptCreated": REAL_RECEIPT.exists(),
        "formalStatusCreated": REAL_STATUS.exists(),
        "checks": harness.checks,
    }
    MON.atomic_create_json(output_root / "validation-summary.json", result)
    if result["passed"]:
        MON.atomic_create_json(
            output_root / "pass-receipt.json",
            {
                "schemaVersion": 1,
                "receiptKind": "gate13r-pr2-attempt3-monitoring-recovery-validation-pass-v1",
                "completedAtUtc": iso(ended),
                "validationSummarySha256": hash_file(output_root / "validation-summary.json"),
                "testCount": 54,
                "passedTestCount": 54,
                "formalCampaignStarted": False,
                "unityInvocations": 0,
            },
        )
    else:
        MON.atomic_create_json(
            output_root / "failure-receipt.json",
            {
                "schemaVersion": 1,
                "receiptKind": "gate13r-pr2-attempt3-monitoring-recovery-validation-failure-v1",
                "failedAtUtc": iso(ended),
                "validationSummarySha256": hash_file(output_root / "validation-summary.json"),
                "failedChecks": [check["id"] for check in harness.checks if not check["passed"]],
                "status": "FAILED-PRESERVED-VERSIONED-REPAIR-ALLOWED",
            },
        )
    files = []
    for path in sorted(output_root.rglob("*")):
        if path.is_file() and path.name != "partial-output-manifest.json":
            files.append({"relativePath": path.relative_to(output_root).as_posix(), "rawBytes": path.stat().st_size, "sha256": hash_file(path)})
    MON.atomic_create_json(
        output_root / "partial-output-manifest.json",
        {
            "schemaVersion": 1,
            "manifestKind": "gate13r-pr2-attempt3-monitoring-recovery-validation-output-v1",
            "createdAtUtc": iso(datetime.now(UTC)),
            "fileCount": len(files),
            "rawBytes": sum(item["rawBytes"] for item in files),
            "files": files,
        },
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    result = run(args.output_root)
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "outputRoot": result["outputRoot"]}, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
