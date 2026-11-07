#!/usr/bin/env python3
"""Blinded Gate 13R-PR2 attempt-3 operational monitoring and recovery policy.

This module is intentionally incapable of launching, stopping, signalling, or
retrying Unity.  It reads an atomically published operational status, validates
its identity, optionally cross-checks the currently owned Unity process, and
creates an immutable operational snapshot outside the formal raw-data root.

The recovery subcommand is a pure decision function.  It returns the actions
permitted by the frozen state machine; it does not perform those actions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone, timedelta
from typing import Any, Callable, Iterable

from jsonschema import Draft202012Validator, FormatChecker


SCRIPT_VERSION = "gate13r-pr2-attempt3-monitoring-recovery-v1"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = PROJECT_ROOT / "Research/Gate13R_PR2_Attempt3_Monitoring_Config.v1.json"
DEFAULT_STATUS_SCHEMA = PROJECT_ROOT / "Research/Gate13R_PR2_Attempt3_Operational_Status_Schema.v1.json"
DEFAULT_SNAPSHOT_SCHEMA = PROJECT_ROOT / "Research/Gate13R_PR2_Attempt3_Progress_Snapshot_Schema.v1.json"
DEFAULT_STATE_MACHINE = PROJECT_ROOT / "Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v1.json"
UTC = timezone.utc
SHANGHAI = timezone(timedelta(hours=8))
TERMINAL_FAILURE = "FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE"
RAW_COMPLETE = "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE"


class MonitorError(RuntimeError):
    """A fail-closed monitoring or persistence error."""


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def parse_datetime(value: str) -> datetime:
    if not isinstance(value, str):
        raise MonitorError("DATETIME-NOT-STRING")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise MonitorError("DATETIME-MISSING-TIMEZONE")
    return parsed.astimezone(UTC)


def iso_utc(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


def iso_shanghai(value: datetime) -> str:
    return value.astimezone(SHANGHAI).isoformat(timespec="microseconds")


def resolve_path(value: str | Path) -> Path:
    return Path(value).expanduser().resolve()


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def atomic_create_bytes(path: Path, payload: bytes) -> None:
    """Create a file atomically without ever overwriting an existing file."""
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise MonitorError(f"IMMUTABLE-SNAPSHOT-ALREADY-EXISTS:{path}")
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}-{time.time_ns()}")
    descriptor: int | None = None
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            descriptor = None
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.rename(temporary, path)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary.exists():
            temporary.unlink()


def atomic_create_json(path: Path, value: Any) -> None:
    atomic_create_bytes(path, canonical_json_bytes(value))


def schema_errors(instance: Any, schema: dict[str, Any]) -> list[str]:
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = []
    for error in sorted(validator.iter_errors(instance), key=lambda item: list(item.absolute_path)):
        location = "/".join(str(part) for part in error.absolute_path) or "$"
        errors.append(f"{location}:{error.message}")
    return errors


def read_json_with_retry(
    path: Path,
    delays: Iterable[float],
    *,
    reader: Callable[[Path], Any] = load_json,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[Any, list[str]]:
    anomalies: list[str] = []
    last_error: BaseException | None = None
    delay_values = list(delays)
    if not delay_values:
        raise MonitorError("READ-RETRY-SCHEDULE-EMPTY")
    for attempt, delay in enumerate(delay_values, start=1):
        if delay > 0:
            sleeper(delay)
        try:
            return reader(path), anomalies
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            last_error = error
            anomalies.append(f"READ-ATTEMPT-{attempt}:{type(error).__name__}")
    raise MonitorError(f"READ-FAILED-AFTER-{len(delay_values)}-ATTEMPTS:{path}:{last_error}")


def observe_target_set(paths: list[Path], delays: list[float], sleeper: Callable[[float], None] = time.sleep) -> tuple[list[bool], list[str]]:
    anomalies: list[str] = []
    latest = [path.exists() for path in paths]
    for attempt, delay in enumerate(delays, start=1):
        if delay > 0:
            sleeper(delay)
        latest = [path.exists() for path in paths]
        if all(latest) or not any(latest):
            return latest, anomalies
        anomalies.append(f"PARTIAL-TARGET-SET-ATTEMPT-{attempt}")
    return latest, anomalies


def query_unity_process_once(pid: int, powershell: str = "powershell.exe") -> dict[str, Any]:
    command = (
        "$ErrorActionPreference='Stop';"
        f"$id={int(pid)};"
        "$p=Get-Process -Id $id -ErrorAction SilentlyContinue;"
        "if($null-eq$p){[pscustomobject]@{exists=$false;pid=$id}|ConvertTo-Json -Compress;exit 0};"
        "$c=Get-CimInstance Win32_Process -Filter (\"ProcessId=$id\") -ErrorAction Stop;"
        "$o=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;"
        "[pscustomobject]@{exists=$true;pid=[int]$p.Id;name=[string]$p.Name;"
        "startTimeUtc=$p.StartTime.ToUniversalTime().ToString('o');"
        "workingSetBytes=[int64]$p.WorkingSet64;privateMemoryBytes=[int64]$p.PrivateMemorySize64;"
        "availablePhysicalMemoryBytes=([int64]$o.FreePhysicalMemory*1024);"
        "commandLine=[string]$c.CommandLine}|ConvertTo-Json -Compress"
    )
    completed = subprocess.run(
        [powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )
    if completed.returncode != 0:
        raise MonitorError(f"OS-PROCESS-QUERY-FAILED:{completed.returncode}:{completed.stderr.strip()}")
    return json.loads(completed.stdout)


def query_process_with_retry(
    pid: int,
    delays: list[float],
    *,
    fixture_path: Path | None = None,
    powershell: str = "powershell.exe",
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[dict[str, Any], list[str]]:
    if fixture_path is not None:
        value, anomalies = read_json_with_retry(fixture_path, delays, sleeper=sleeper)
        return value, anomalies
    anomalies: list[str] = []
    last_error: BaseException | None = None
    for attempt, delay in enumerate(delays, start=1):
        if delay > 0:
            sleeper(delay)
        try:
            return query_unity_process_once(pid, powershell), anomalies
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError, MonitorError) as error:
            last_error = error
            anomalies.append(f"OS-QUERY-ATTEMPT-{attempt}:{type(error).__name__}")
    raise MonitorError(f"OS-PROCESS-QUERY-FAILED-AFTER-{len(delays)}-ATTEMPTS:{last_error}")


def recursively_find_forbidden(value: Any, patterns: list[str], path: str = "$") -> list[str]:
    findings: list[str] = []
    compiled = [re.compile(pattern, re.IGNORECASE) for pattern in patterns]
    if isinstance(value, dict):
        for key, item in value.items():
            if any(pattern.search(str(key)) for pattern in compiled):
                findings.append(f"{path}/{key}")
            findings.extend(recursively_find_forbidden(item, patterns, f"{path}/{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            findings.extend(recursively_find_forbidden(item, patterns, f"{path}/{index}"))
    return findings


def load_previous_snapshot(snapshot_path: Path | None, monitoring_root: Path) -> dict[str, Any] | None:
    if snapshot_path is not None:
        return load_json(snapshot_path)
    if not monitoring_root.exists():
        return None
    candidates: list[tuple[datetime, Path]] = []
    for path in monitoring_root.glob("progress-*.json"):
        try:
            snapshot = load_json(path)
            candidates.append((parse_datetime(snapshot["capturedAtUtc"]), path))
        except (OSError, KeyError, ValueError, json.JSONDecodeError, MonitorError):
            continue
    if not candidates:
        return None
    return load_json(max(candidates, key=lambda pair: pair[0])[1])


def _empty_identity() -> dict[str, Any]:
    return {
        "globalProcessOrdinal": None,
        "campaignId": None,
        "scenarioId": None,
        "cohort": None,
        "blockId": None,
        "matchedSuperblockId": None,
        "abbaOrder": None,
        "williamsRow": None,
        "unityPid": None,
        "unityProcessStartedAtUtc": None,
    }


def _base_snapshot(now: datetime, config: dict[str, Any], config_path: Path) -> dict[str, Any]:
    totals = config["fixedTotals"]
    return {
        "schemaVersion": 1,
        "snapshotKind": "gate13r-pr2-attempt3-operational-progress-v1",
        "capturedAtUtc": iso_utc(now),
        "capturedAtAsiaShanghai": iso_shanghai(now),
        "active": False,
        "phase": "PRELAUNCH",
        "status": "NOT-STARTED",
        "notify": False,
        "notificationReason": [],
        "blindedOperationalOnly": True,
        "totals": {
            "campaigns": int(totals["campaignCount"]),
            "processes": int(totals["processCount"]),
            "samples": int(totals["sampleCount"]),
            "matchedSuperblocks": int(totals["matchedSuperblockCount"]),
        },
        "progress": {
            "completedProcesses": 0,
            "completedSamples": 0,
            "processPercent": 0.0,
            "samplePercent": 0.0,
            "lastProgressAtUtc": None,
        },
        "currentIdentity": _empty_identity(),
        "timing": {
            "startedAtUtc": None,
            "elapsedSeconds": 0.0,
            "statusAgeSeconds": None,
            "lastCheckpointAgeSeconds": None,
            "currentBlockElapsedSeconds": None,
            "overallProcessesPerHour": None,
            "rollingProcessesPerHour": None,
            "conservativeProcessesPerHour": None,
            "etaHours": None,
            "etaStatus": "UNAVAILABLE",
            "reportSlot": None,
        },
        "telemetry": {
            "statusWorkingSetBytes": None,
            "statusPrivateMemoryBytes": None,
            "statusAvailablePhysicalMemoryBytes": None,
            "osWorkingSetBytes": None,
            "osPrivateMemoryBytes": None,
            "osAvailablePhysicalMemoryBytes": None,
            "advisoryCrossingCount": 0,
            "osQueryStatus": "NOT-APPLICABLE",
        },
        "storage": {
            "outputFileCount": 0,
            "rawBytes": 0,
        },
        "health": {
            "classification": "OK",
            "reasonCodes": [],
            "readAnomalyCount": 0,
            "readAnomalies": [],
            "missingOwnedProcessSinceUtc": None,
            "monitorMayKillProcess": False,
            "experimentRetryAuthorized": False,
        },
        "sourceIdentity": {
            "monitorVersion": SCRIPT_VERSION,
            "configPath": str(config_path),
            "configSha256": sha256_file(config_path),
            "formalRoot": str(resolve_path(config["formalRoot"])),
            "receiptPath": str(resolve_path(config["formalReceipt"])),
            "statusPath": str(resolve_path(config["formalStatus"])),
            "receiptSha256": None,
            "statusSha256": None,
            "candidateConfigSha256": "c8d3e9965ae72798e2366c0187a96e578df306bb68196f54039c421672b78042",
            "scheduleSha256": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
        },
    }


def _set_action_required(snapshot: dict[str, Any], *reason_codes: str) -> None:
    snapshot["status"] = "ACTION-REQUIRED"
    snapshot["active"] = False
    snapshot["health"]["classification"] = "ACTION-REQUIRED"
    snapshot["health"]["reasonCodes"] = sorted(set(snapshot["health"]["reasonCodes"] + list(reason_codes)))


def _positive_rate(value: Any) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)) and float(value) > 0:
        return float(value)
    return None


def _derive_progress_timing(
    snapshot: dict[str, Any],
    status: dict[str, Any],
    previous: dict[str, Any] | None,
    now: datetime,
    eta_multiplier: float,
) -> None:
    completed_processes = int(status["completedProcessCount"])
    completed_samples = int(status["completedSampleCount"])
    total_processes = int(status["totalProcessCount"])
    total_samples = int(status["totalSampleCount"])
    started = parse_datetime(status["startedAtUtc"])
    checkpoint = parse_datetime(status["lastDurableCheckpointAtUtc"])
    saved = parse_datetime(status["savedAtUtc"])
    elapsed = max(0.0, (now - started).total_seconds())
    snapshot["progress"].update(
        {
            "completedProcesses": completed_processes,
            "completedSamples": completed_samples,
            "processPercent": round(100.0 * completed_processes / total_processes, 9),
            "samplePercent": round(100.0 * completed_samples / total_samples, 9),
        }
    )
    previous_processes = None if previous is None else previous.get("progress", {}).get("completedProcesses")
    if previous_processes is not None and completed_processes < int(previous_processes):
        _set_action_required(snapshot, "COUNTER-REGRESSION")
    if previous is None or previous_processes is None or completed_processes > int(previous_processes):
        last_progress = now
    else:
        prior_last = previous.get("progress", {}).get("lastProgressAtUtc")
        last_progress = parse_datetime(prior_last) if prior_last else checkpoint
    snapshot["progress"]["lastProgressAtUtc"] = iso_utc(last_progress)

    overall_rate = completed_processes / (elapsed / 3600.0) if completed_processes > 0 and elapsed > 0 else None
    rolling_rate = None
    if previous is not None:
        prior_time = parse_datetime(previous["capturedAtUtc"])
        delta_seconds = (now - prior_time).total_seconds()
        delta_processes = completed_processes - int(previous.get("progress", {}).get("completedProcesses", 0))
        if delta_processes > 0 and delta_seconds > 0:
            rolling_rate = delta_processes / (delta_seconds / 3600.0)
        else:
            rolling_rate = _positive_rate(previous.get("timing", {}).get("rollingProcessesPerHour"))
    rates = [rate for rate in (_positive_rate(overall_rate), _positive_rate(rolling_rate)) if rate is not None]
    conservative_rate = min(rates) if rates else None
    remaining = total_processes - completed_processes
    eta = (remaining / conservative_rate) * eta_multiplier if conservative_rate and remaining > 0 else (0.0 if remaining == 0 else None)
    block_start = status.get("currentUnityBlockStartedAtUtc")
    block_elapsed = max(0.0, (now - parse_datetime(block_start)).total_seconds()) if block_start else None
    report_slot = int(elapsed // 3600.0) if elapsed >= 0 else None
    snapshot["timing"].update(
        {
            "startedAtUtc": iso_utc(started),
            "elapsedSeconds": round(elapsed, 6),
            "statusAgeSeconds": round(max(0.0, (now - saved).total_seconds()), 6),
            "lastCheckpointAgeSeconds": round(max(0.0, (now - checkpoint).total_seconds()), 6),
            "currentBlockElapsedSeconds": None if block_elapsed is None else round(block_elapsed, 6),
            "overallProcessesPerHour": None if overall_rate is None else round(overall_rate, 9),
            "rollingProcessesPerHour": None if rolling_rate is None else round(rolling_rate, 9),
            "conservativeProcessesPerHour": None if conservative_rate is None else round(conservative_rate, 9),
            "etaHours": None if eta is None else round(eta, 9),
            "etaStatus": "AVAILABLE" if eta is not None else "UNAVAILABLE",
            "reportSlot": report_slot,
        }
    )


def _validate_status_semantics(status: dict[str, Any], now: datetime) -> list[str]:
    reasons: list[str] = []
    for field in ("savedAtUtc", "startedAtUtc", "lastDurableCheckpointAtUtc"):
        try:
            if parse_datetime(status[field]) > now + timedelta(seconds=60):
                reasons.append(f"FUTURE-TIMESTAMP:{field}")
        except (KeyError, ValueError, MonitorError):
            reasons.append(f"INVALID-TIMESTAMP:{field}")
    process_count = status.get("completedProcessCount")
    sample_count = status.get("completedSampleCount")
    if isinstance(process_count, int) and isinstance(sample_count, int):
        if process_count == 3552 and sample_count != 10176:
            reasons.append("FINAL-COUNTS-INCONSISTENT")
        if status.get("rawDataComplete") and (process_count != 3552 or sample_count != 10176):
            reasons.append("RAW-COMPLETE-COUNTS-INCONSISTENT")
    if status.get("status") == RAW_COMPLETE and not status.get("rawDataComplete"):
        reasons.append("RAW-COMPLETE-FLAG-MISSING")
    if status.get("status") == "ACQUISITION-RUNNING":
        for field in (
            "currentGlobalProcessOrdinal",
            "currentBlockId",
            "currentUnityProcessId",
            "currentUnityProcessStartedAtUtc",
            "currentUnityBlockStartedAtUtc",
            "latestWorkingSetBytes",
            "latestPrivateMemoryBytes",
            "latestAvailablePhysicalMemoryBytes",
        ):
            if status.get(field) is None:
                reasons.append(f"RUNNING-FIELD-MISSING:{field}")
        for field in ("latestWorkingSetBytes", "latestPrivateMemoryBytes", "latestAvailablePhysicalMemoryBytes"):
            value = status.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                reasons.append(f"INVALID-TELEMETRY:{field}")
    return reasons


def _process_health(
    snapshot: dict[str, Any],
    status: dict[str, Any],
    previous: dict[str, Any] | None,
    now: datetime,
    os_process: dict[str, Any] | None,
    skip_os_query: bool,
) -> None:
    if status["status"] != "ACQUISITION-RUNNING":
        snapshot["telemetry"]["osQueryStatus"] = "NOT-APPLICABLE"
        return
    if skip_os_query:
        snapshot["telemetry"]["osQueryStatus"] = "SKIPPED-VALIDATION-ONLY"
        return
    if not isinstance(os_process, dict):
        _set_action_required(snapshot, "OS-PROCESS-QUERY-INVALID")
        return
    if not os_process.get("exists"):
        snapshot["telemetry"]["osQueryStatus"] = "OWNED-PROCESS-NOT-OBSERVED"
        previous_since = None if previous is None else previous.get("health", {}).get("missingOwnedProcessSinceUtc")
        missing_since = parse_datetime(previous_since) if previous_since else now
        snapshot["health"]["missingOwnedProcessSinceUtc"] = iso_utc(missing_since)
        snapshot["health"]["reasonCodes"].append("PROCESS-MISSING-OBSERVED")
        if (now - missing_since).total_seconds() > 300:
            _set_action_required(snapshot, "PROCESS-IDENTITY-ACTION-REQUIRED")
        return
    snapshot["telemetry"]["osQueryStatus"] = "MATCHED"
    snapshot["health"]["missingOwnedProcessSinceUtc"] = None
    expected_pid = int(status["currentUnityProcessId"])
    actual_pid = os_process.get("pid")
    name = str(os_process.get("name", ""))
    if actual_pid != expected_pid or name.lower() not in {"unity", "unity.exe"}:
        _set_action_required(snapshot, "COMPOSITE-PROCESS-IDENTITY-MISMATCH")
    try:
        start_delta = abs((parse_datetime(os_process["startTimeUtc"]) - parse_datetime(status["currentUnityProcessStartedAtUtc"])).total_seconds())
        if start_delta > 2.0:
            _set_action_required(snapshot, "COMPOSITE-PROCESS-START-MISMATCH")
    except (KeyError, ValueError, MonitorError):
        _set_action_required(snapshot, "COMPOSITE-PROCESS-START-INVALID")
    for source_key, target_key in (
        ("workingSetBytes", "osWorkingSetBytes"),
        ("privateMemoryBytes", "osPrivateMemoryBytes"),
        ("availablePhysicalMemoryBytes", "osAvailablePhysicalMemoryBytes"),
    ):
        value = os_process.get(source_key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            _set_action_required(snapshot, f"INVALID-OS-TELEMETRY:{source_key}")
        else:
            snapshot["telemetry"][target_key] = value
    command_line = str(os_process.get("commandLine", ""))
    project_token = str(PROJECT_ROOT).lower()
    if project_token not in command_line.lower():
        _set_action_required(snapshot, "OWNED-PROCESS-COMMANDLINE-MISMATCH")


def _apply_stall_policy(snapshot: dict[str, Any], previous: dict[str, Any] | None, now: datetime, config: dict[str, Any]) -> None:
    if snapshot["status"] != "ACQUISITION-RUNNING":
        return
    policy = config["stallPolicy"]
    status_age = snapshot["timing"]["statusAgeSeconds"]
    if status_age is not None and status_age > int(policy["statusStaleAdvisorySecondsExclusive"]):
        snapshot["health"]["reasonCodes"].append("STATUS-STALE-ADVISORY")
    block_elapsed = snapshot["timing"]["currentBlockElapsedSeconds"]
    if block_elapsed is not None and block_elapsed > int(policy["hardTimeoutOverdueActionSecondsExclusive"]):
        _set_action_required(snapshot, "HARD-TIMEOUT-OVERDUE-ACTION-REQUIRED")
    last_progress = snapshot["progress"].get("lastProgressAtUtc")
    process_matched = snapshot["telemetry"]["osQueryStatus"] in {"MATCHED", "SKIPPED-VALIDATION-ONLY"}
    if last_progress and process_matched:
        no_progress = (now - parse_datetime(last_progress)).total_seconds()
        if no_progress > int(policy["noProgressStallSecondsExclusive"]):
            snapshot["health"]["reasonCodes"].append("STALL-SUSPECTED")
    snapshot["health"]["reasonCodes"] = sorted(set(snapshot["health"]["reasonCodes"]))
    if snapshot["status"] != "ACTION-REQUIRED" and snapshot["health"]["reasonCodes"]:
        snapshot["health"]["classification"] = "ADVISORY"


def _derive_notification(snapshot: dict[str, Any], previous: dict[str, Any] | None) -> None:
    reasons: list[str] = []
    status = snapshot["status"]
    previous_status = None if previous is None else previous.get("status")
    if status == "NOT-STARTED":
        snapshot["notify"] = False
        snapshot["notificationReason"] = []
        return
    if status == "ACQUISITION-RUNNING":
        if previous is None or previous_status != "ACQUISITION-RUNNING":
            reasons.append("ACQUISITION-STARTED")
        else:
            current_slot = snapshot["timing"].get("reportSlot")
            prior_slot = previous.get("timing", {}).get("reportSlot")
            if current_slot is not None and prior_slot is not None and int(current_slot) > int(prior_slot):
                reasons.append("HOURLY-PROGRESS")
    if status == TERMINAL_FAILURE and previous_status != TERMINAL_FAILURE:
        reasons.append("ACQUISITION-FAILED")
    if status == RAW_COMPLETE and previous_status != RAW_COMPLETE:
        reasons.append("RAW-DATA-COMPLETE")
    if status == "ACTION-REQUIRED" and previous_status != "ACTION-REQUIRED":
        reasons.append("USER-ACTION-REQUIRED")
    current_health = set(snapshot["health"].get("reasonCodes", []))
    previous_health = set() if previous is None else set(previous.get("health", {}).get("reasonCodes", []))
    escalations = current_health - previous_health
    for escalation in ("STALL-SUSPECTED", "PROCESS-IDENTITY-ACTION-REQUIRED", "HARD-TIMEOUT-OVERDUE-ACTION-REQUIRED"):
        if escalation in escalations:
            reasons.append(escalation)
    snapshot["notificationReason"] = sorted(set(reasons))
    snapshot["notify"] = bool(snapshot["notificationReason"])


def build_snapshot(
    config_path: Path,
    *,
    now: datetime | None = None,
    previous_snapshot_path: Path | None = None,
    os_fixture_path: Path | None = None,
    status_schema_path: Path = DEFAULT_STATUS_SCHEMA,
    skip_os_query: bool = False,
    powershell: str = "powershell.exe",
    sleeper: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    now = (now or datetime.now(UTC)).astimezone(UTC)
    config_path = config_path.resolve()
    config = load_json(config_path)
    monitoring_root = resolve_path(config["monitoringRoot"])
    formal_root = resolve_path(config["formalRoot"])
    receipt_path = resolve_path(config["formalReceipt"])
    status_path = resolve_path(config["formalStatus"])
    previous = load_previous_snapshot(previous_snapshot_path, monitoring_root)
    snapshot = _base_snapshot(now, config, config_path)
    delays = [float(value) for value in config["readRetry"]["delaySeconds"]]
    flags, anomalies = observe_target_set([formal_root, receipt_path, status_path], delays, sleeper)
    snapshot["health"]["readAnomalies"].extend(anomalies)
    if not any(flags):
        snapshot["health"]["readAnomalyCount"] = len(anomalies)
        _derive_notification(snapshot, previous)
        validate_snapshot(snapshot)
        return snapshot
    if not all(flags):
        snapshot["phase"] = "PRELAUNCH"
        _set_action_required(snapshot, "PARTIAL-FORMAL-TARGET-SET")
        snapshot["health"]["readAnomalyCount"] = len(anomalies)
        _derive_notification(snapshot, previous)
        validate_snapshot(snapshot)
        return snapshot

    try:
        receipt, receipt_anomalies = read_json_with_retry(receipt_path, delays, sleeper=sleeper)
        status, status_anomalies = read_json_with_retry(status_path, delays, sleeper=sleeper)
        anomalies.extend(receipt_anomalies)
        anomalies.extend(status_anomalies)
    except MonitorError as error:
        _set_action_required(snapshot, "ATOMIC-SOURCE-READ-FAILED")
        snapshot["health"]["readAnomalies"].append(str(error))
        snapshot["health"]["readAnomalyCount"] = len(snapshot["health"]["readAnomalies"])
        _derive_notification(snapshot, previous)
        validate_snapshot(snapshot)
        return snapshot

    receipt_sha = sha256_file(receipt_path)
    status_sha = sha256_file(status_path)
    snapshot["sourceIdentity"]["receiptSha256"] = receipt_sha
    snapshot["sourceIdentity"]["statusSha256"] = status_sha
    schema = load_json(status_schema_path.resolve())
    validation_reasons = [f"STATUS-SCHEMA:{item}" for item in schema_errors(status, schema)]
    validation_reasons.extend(_validate_status_semantics(status, now))
    if not isinstance(receipt, dict):
        validation_reasons.append("RECEIPT-NOT-OBJECT")
    else:
        if receipt.get("formalAttemptOrdinal") != 3:
            validation_reasons.append("RECEIPT-ATTEMPT-ORDINAL-MISMATCH")
        if resolve_path(str(receipt.get("formalRoot", PROJECT_ROOT))) != formal_root:
            validation_reasons.append("RECEIPT-FORMAL-ROOT-MISMATCH")
    if status.get("executionReceiptSha256") != receipt_sha:
        validation_reasons.append("RECEIPT-SHA256-MISMATCH")
    if validation_reasons:
        _set_action_required(snapshot, *validation_reasons)
        snapshot["health"]["readAnomalies"].extend(anomalies)
        snapshot["health"]["readAnomalyCount"] = len(snapshot["health"]["readAnomalies"])
        _derive_notification(snapshot, previous)
        validate_snapshot(snapshot)
        return snapshot

    formal_status = str(status["status"])
    if formal_status == "PRELAUNCH":
        snapshot["phase"] = "PRELAUNCH"
        snapshot["status"] = "PRELAUNCH"
    elif formal_status == "ACQUISITION-RUNNING":
        snapshot["phase"] = "PHASE-A-ACQUISITION"
        snapshot["status"] = formal_status
        snapshot["active"] = True
    elif formal_status in {"ACQUISITION-COMPLETE-COMMIT-PENDING", "RAW-COMMIT-RECOVERY"}:
        snapshot["phase"] = "PHASE-A-RAW-COMMIT"
        snapshot["status"] = formal_status
        snapshot["active"] = True
    elif formal_status == RAW_COMPLETE:
        snapshot["phase"] = "PHASE-A-COMMITTED"
        snapshot["status"] = formal_status
    elif formal_status in {TERMINAL_FAILURE, "USER-ACTION-REQUIRED"}:
        snapshot["phase"] = "TERMINAL"
        snapshot["status"] = formal_status
        snapshot["health"]["classification"] = "ACTION-REQUIRED"
        reason = status.get("errorReasonCode") or formal_status
        snapshot["health"]["reasonCodes"].append(str(reason))
    else:
        _set_action_required(snapshot, "UNKNOWN-FORMAL-STATUS")

    _derive_progress_timing(snapshot, status, previous, now, float(config["etaPolicy"]["safetyMultiplier"]))
    snapshot["currentIdentity"] = {
        "globalProcessOrdinal": status.get("currentGlobalProcessOrdinal"),
        "campaignId": status.get("currentCampaignId"),
        "scenarioId": status.get("currentScenarioId"),
        "cohort": status.get("currentCohort"),
        "blockId": status.get("currentBlockId"),
        "matchedSuperblockId": status.get("currentMatchedSuperblockId"),
        "abbaOrder": status.get("currentABBAOrder"),
        "williamsRow": status.get("currentWilliamsRow"),
        "unityPid": status.get("currentUnityProcessId"),
        "unityProcessStartedAtUtc": status.get("currentUnityProcessStartedAtUtc"),
    }
    snapshot["telemetry"].update(
        {
            "statusWorkingSetBytes": status.get("latestWorkingSetBytes"),
            "statusPrivateMemoryBytes": status.get("latestPrivateMemoryBytes"),
            "statusAvailablePhysicalMemoryBytes": status.get("latestAvailablePhysicalMemoryBytes"),
            "advisoryCrossingCount": int(status.get("advisoryCrossingCount", 0)),
        }
    )
    snapshot["storage"].update({"outputFileCount": int(status["outputFileCount"]), "rawBytes": int(status["rawBytes"])})
    os_process = None
    if formal_status == "ACQUISITION-RUNNING" and not skip_os_query:
        try:
            os_process, process_anomalies = query_process_with_retry(
                int(status["currentUnityProcessId"]),
                delays,
                fixture_path=os_fixture_path,
                powershell=powershell,
                sleeper=sleeper,
            )
            anomalies.extend(process_anomalies)
        except (ValueError, TypeError, MonitorError) as error:
            anomalies.append(str(error))
            _set_action_required(snapshot, "OS-PROCESS-QUERY-FAILED")
    _process_health(snapshot, status, previous, now, os_process, skip_os_query)
    _apply_stall_policy(snapshot, previous, now, config)
    snapshot["health"]["readAnomalies"] = anomalies
    snapshot["health"]["readAnomalyCount"] = len(anomalies)
    _derive_notification(snapshot, previous)
    forbidden = recursively_find_forbidden(snapshot, list(config["blinding"]["forbiddenFieldPatterns"]))
    if forbidden:
        raise MonitorError("BLINDING-FIELD-REJECTED:" + ",".join(forbidden))
    validate_snapshot(snapshot)
    return snapshot


def validate_snapshot(snapshot: dict[str, Any]) -> None:
    errors = schema_errors(snapshot, load_json(DEFAULT_SNAPSHOT_SCHEMA))
    if errors:
        raise MonitorError("SNAPSHOT-SCHEMA-FAILED:" + "|".join(errors))


def persist_snapshot(snapshot: dict[str, Any], requested_root: Path, config_path: Path) -> Path | None:
    config = load_json(config_path)
    configured_root = resolve_path(config["monitoringRoot"])
    requested_root = requested_root.resolve()
    formal_root = resolve_path(config["formalRoot"])
    if requested_root != configured_root:
        raise MonitorError("SNAPSHOT-ROOT-NOT-CONFIGURED-MONITORING-ROOT")
    if is_relative_to(requested_root, formal_root) or is_relative_to(formal_root, requested_root):
        raise MonitorError("SNAPSHOT-ROOT-OVERLAPS-FORMAL-ROOT")
    if snapshot["status"] == "NOT-STARTED":
        return None
    stamp = parse_datetime(snapshot["capturedAtUtc"]).strftime("%Y%m%dT%H%M%S%fZ")
    target = requested_root / f"progress-{stamp}.json"
    atomic_create_json(target, snapshot)
    return target


def recovery_decision(context: dict[str, Any], state_machine: dict[str, Any]) -> dict[str, Any]:
    stage = str(context.get("stage", "UNKNOWN"))
    result: dict[str, Any] = {
        "schemaVersion": 1,
        "decisionKind": "gate13r-pr2-attempt3-bounded-recovery-decision-v1",
        "stage": stage,
        "eligible": False,
        "disposition": "USER-ACTION-REQUIRED",
        "allowedActions": [],
        "forbiddenActions": [
            "START-UNITY",
            "RETRY-MEASURED-SAMPLE",
            "RESUME-MEASURED-ATTEMPT",
            "TOP-UP",
            "PARTIAL-MERGE",
            "SKIP-OR-REPLACE-BLOCK",
            "ADVANCE-AFTER-HARD-FAILURE",
            "CREATE-ATTEMPT-4",
        ],
        "reasonCodes": [],
        "unityCommandAllowed": False,
    }
    if stage == "PRELAUNCH":
        policy = state_machine["prelaunch"]
        defect_class = str(context.get("defectClass", ""))
        if defect_class in set(policy["neverRepairable"]):
            result["reasonCodes"].append(defect_class)
            return result
        requirements = {
            "formalRootAbsent": not bool(context.get("formalRootExists")),
            "formalReceiptAbsent": not bool(context.get("formalReceiptExists")),
            "formalStatusAbsent": not bool(context.get("formalStatusExists")),
            "measuredProcessCountZero": int(context.get("measuredProcessCount", 0)) == 0,
            "measuredSampleCountZero": int(context.get("measuredSampleCount", 0)) == 0,
            "defectConfinedToNewAttempt3Artifacts": bool(context.get("defectConfinedToNewAttempt3Artifacts")),
            "frozenInputsUnchanged": bool(context.get("frozenInputsUnchanged")),
            "targetedValidationPassed": bool(context.get("targetedValidationPassed")),
        }
        failed = [name for name in policy["required"] if not requirements.get(name, False)]
        repair_cycles = int(context.get("repairCycleCount", 0))
        if repair_cycles >= int(policy["maximumRepairCycles"]):
            failed.append("MAXIMUM-REPAIR-CYCLES-REACHED")
        signatures = list(context.get("recentFailureSignatures", []))
        if len(signatures) >= 2 and signatures[-1] == signatures[-2]:
            failed.append("CONSECUTIVE-SAME-FAILURE-SIGNATURE")
        if failed:
            result["reasonCodes"] = sorted(set(failed))
            return result
        result.update(
            {
                "eligible": True,
                "disposition": "VERSIONED-PRELAUNCH-REPAIR-ELIGIBLE",
                "allowedActions": ["PRESERVE-FAILED-PRELAUNCH-ATTEMPT", "CREATE-VERSIONED-REPAIR", "RUN-TARGETED-NON-UNITY-VALIDATION"],
            }
        )
        return result
    if stage == "ACQUISITION":
        result.update(
            {
                "eligible": True,
                "disposition": "READ-ONLY-DIAGNOSTICS-ONLY",
                "allowedActions": ["CAPTURE-READ-ONLY-DIAGNOSTICS", "NOTIFY-USER", "PRESERVE-FAILURE-EVIDENCE"],
                "reasonCodes": ["MEASURED-RETRY-PROHIBITED"],
            }
        )
        return result
    if stage == "POST-ACQUISITION-COMMIT":
        policy = state_machine["postAcquisitionCommit"]
        requirements = {
            "completedProcessCountEquals3552": int(context.get("completedProcessCount", -1)) == 3552,
            "completedSampleCountEquals10176": int(context.get("completedSampleCount", -1)) == 10176,
            "acquisitionCompleteEvidencePresent": bool(context.get("acquisitionCompleteEvidencePresent")),
            "rawTreeIdentityStableAcrossTwoReads": bool(context.get("rawTreeIdentityStableAcrossTwoReads")),
            "zeroUnityProcesses": int(context.get("unityProcessCount", -1)) == 0,
            "unityLockAbsent": not bool(context.get("unityLockExists")),
            "noMeasuredFileMutation": bool(context.get("noMeasuredFileMutation")),
            "syntheticCommitValidationPassed": bool(context.get("syntheticCommitValidationPassed")),
        }
        failed = [name for name in policy["required"] if not requirements.get(name, False)]
        attempts = int(context.get("recoveryAttemptCount", 0))
        if attempts >= int(policy["maximumRecoveryAttempts"]):
            failed.append("MAXIMUM-RECOVERY-ATTEMPTS-REACHED")
        signatures = list(context.get("recentFailureSignatures", []))
        if len(signatures) >= 2 and signatures[-1] == signatures[-2]:
            failed.append("CONSECUTIVE-SAME-FAILURE-SIGNATURE")
        if failed:
            result["reasonCodes"] = sorted(set(failed))
            return result
        result.update(
            {
                "eligible": True,
                "disposition": "NON-UNITY-RAW-COMMIT-RECOVERY-ELIGIBLE",
                "allowedActions": ["PRESERVE-FAILED-COMMIT-ATTEMPT", "CREATE-VERSIONED-COMMIT-REPAIR", "RUN-SYNTHETIC-COMMIT-VALIDATION", "RETRY-COMMIT-AGAINST-SAME-RAW-TREE"],
            }
        )
        return result
    result["reasonCodes"].append("UNKNOWN-STAGE")
    return result


def render_operational_report(snapshot: dict[str, Any]) -> str:
    """Render only fields already admitted by the blinded snapshot contract."""
    progress = snapshot["progress"]
    totals = snapshot["totals"]
    timing = snapshot["timing"]
    identity = snapshot["currentIdentity"]
    telemetry = snapshot["telemetry"]
    health = snapshot["health"]
    eta = "不可用" if timing["etaHours"] is None else f"{timing['etaHours']:.2f} 小时"
    reasons = "、".join(snapshot["notificationReason"] or health["reasonCodes"] or ["无"])
    return (
        f"Gate 13R-PR2 attempt 3 运行状态（{snapshot['capturedAtAsiaShanghai']}）\n"
        f"阶段/状态：{snapshot['phase']} / {snapshot['status']}\n"
        f"进度：process {progress['completedProcesses']}/{totals['processes']} "
        f"({progress['processPercent']:.2f}%)；sample {progress['completedSamples']}/{totals['samples']} "
        f"({progress['samplePercent']:.2f}%)\n"
        f"当前：ordinal={identity['globalProcessOrdinal']}，campaign={identity['campaignId']}，"
        f"scenario={identity['scenarioId']}，cohort={identity['cohort']}，block={identity['blockId']}\n"
        f"运行时长：{timing['elapsedSeconds'] / 3600.0:.2f} 小时；保守 ETA：{eta}\n"
        f"内存：working-set={telemetry['osWorkingSetBytes']}，private={telemetry['osPrivateMemoryBytes']}，"
        f"available={telemetry['osAvailablePhysicalMemoryBytes']} bytes；advisory={telemetry['advisoryCrossingCount']}\n"
        f"持久化：files={snapshot['storage']['outputFileCount']}，rawBytes={snapshot['storage']['rawBytes']}\n"
        f"健康/通知：{health['classification']}；{reasons}"
    )


def parse_now(value: str | None) -> datetime | None:
    return None if value is None else parse_datetime(value)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    snapshot = subparsers.add_parser("snapshot", help="create a blinded operational snapshot")
    snapshot.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    snapshot.add_argument("--now-utc")
    snapshot.add_argument("--previous-snapshot", type=Path)
    snapshot.add_argument("--os-fixture", type=Path)
    snapshot.add_argument("--status-schema", type=Path, default=DEFAULT_STATUS_SCHEMA)
    snapshot.add_argument("--skip-os-query", action="store_true")
    snapshot.add_argument("--powershell", default="powershell.exe")
    snapshot.add_argument("--write", action="store_true")
    snapshot.add_argument("--snapshot-root", type=Path)
    snapshot.add_argument("--output", type=Path)
    snapshot.add_argument("--render-report", action="store_true")

    recovery = subparsers.add_parser("recovery-decision", help="evaluate the frozen recovery state machine")
    recovery.add_argument("--context", type=Path, required=True)
    recovery.add_argument("--state-machine", type=Path, default=DEFAULT_STATE_MACHINE)
    recovery.add_argument("--output", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    if args.command == "snapshot":
        config_path = args.config.resolve()
        snapshot = build_snapshot(
            config_path,
            now=parse_now(args.now_utc),
            previous_snapshot_path=None if args.previous_snapshot is None else args.previous_snapshot.resolve(),
            os_fixture_path=None if args.os_fixture is None else args.os_fixture.resolve(),
            status_schema_path=args.status_schema.resolve(),
            skip_os_query=bool(args.skip_os_query),
            powershell=args.powershell,
        )
        written = None
        if args.write:
            config = load_json(config_path)
            root = resolve_path(config["monitoringRoot"]) if args.snapshot_root is None else args.snapshot_root.resolve()
            written = persist_snapshot(snapshot, root, config_path)
        envelope = {"snapshot": snapshot, "writtenPath": None if written is None else str(written)}
        if args.output is not None:
            atomic_create_json(args.output.resolve(), envelope)
        print(json.dumps(envelope, ensure_ascii=False, sort_keys=True, allow_nan=False))
        if args.render_report and snapshot["notify"]:
            print(render_operational_report(snapshot), file=sys.stderr)
        return 0
    if args.command == "recovery-decision":
        context = load_json(args.context.resolve())
        decision = recovery_decision(context, load_json(args.state_machine.resolve()))
        if args.output is not None:
            atomic_create_json(args.output.resolve(), decision)
        print(json.dumps(decision, ensure_ascii=False, sort_keys=True, allow_nan=False))
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (MonitorError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2)
