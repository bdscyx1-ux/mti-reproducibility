#!/usr/bin/env python3
"""Outcome-blind operational monitor for Gate 13R-PR2 formal attempt 4."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import time
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import psutil


SHANGHAI = timezone(timedelta(hours=8), name="Asia/Shanghai")
ACTIVE = {"ACQUISITION-RUNNING", "AUTO-RESUME-VALIDATING", "AUTO-RESUME-RUNNING", "ACQUISITION-COMPLETE-COMMIT-PENDING", "RAW-COMMIT-RECOVERY"}
TERMINAL = {"RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE", "FAILED-PARTIAL-FORMAL-BLOCKS-RETAINED-NO-AUTO-RETRY", "USER-ACTION-REQUIRED"}


def utc_now() -> datetime:
    return datetime.now(UTC)


def iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def read_json_retry(path: Path, delays: list[int]) -> dict[str, Any]:
    last: BaseException | None = None
    for delay in delays:
        if delay:
            time.sleep(delay)
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as error:
            last = error
    raise RuntimeError(f"READ-RETRY-EXHAUSTED:{path}:{type(last).__name__}:{last}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_create(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".g13r-a4-monitor-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists():
            raise FileExistsError(path)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def latest_snapshot(root: Path) -> dict[str, Any] | None:
    files = sorted(root.glob("progress-*.json")) if root.is_dir() else []
    if not files:
        return None
    try:
        return json.loads(files[-1].read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def unity_identity(status: dict[str, Any]) -> dict[str, Any] | None:
    pid = status.get("currentUnityProcessId")
    if not pid:
        return None
    try:
        process = psutil.Process(int(pid))
        start = datetime.fromtimestamp(process.create_time(), UTC)
        return {
            "pid": int(pid),
            "startTimeUtc": iso(start),
            "commandLine": " ".join(process.cmdline()),
            "workingSetBytes": int(process.memory_info().rss),
            "privateMemoryBytes": int(getattr(process.memory_full_info(), "private", process.memory_info().rss)),
            "alive": process.is_running(),
        }
    except (psutil.NoSuchProcess, psutil.AccessDenied, OSError):
        return {
            "pid": int(pid),
            "startTimeUtc": status.get("currentUnityProcessStartedAtUtc"),
            "commandLine": None,
            "workingSetBytes": status.get("latestWorkingSetBytes"),
            "privateMemoryBytes": status.get("latestPrivateMemoryBytes"),
            "alive": False,
        }


def render_zh(snapshot: dict[str, Any]) -> str:
    current = snapshot["current"]
    progress = snapshot["progress"]
    timing = snapshot["timing"]
    memory = snapshot["memory"]
    paths = snapshot["paths"]
    return (
        f"Gate 13R-PR2 attempt 4 运行快照（上海 {snapshot['capturedAtAsiaShanghai']}；UTC {snapshot['capturedAtUtc']}）："
        f"Phase-A 状态 {snapshot['status']}；已完成/具备块级正式统计资格 {progress['completedProcesses']}/{progress['totalProcesses']} blocks，"
        f"{progress['completedSamples']}/{progress['totalSamples']} samples；当前 ordinal {current['globalProcessOrdinal']}，"
        f"campaign/scenario/cohort={current['campaignId']}/{current['scenarioId']}/{current['cohort']}，"
        f"block/matched-superblock={current['blockId']}/{current['matchedSuperblockId']}，Williams row {current['williamsRow']}，顺序 {current['abbaOrder']}；"
        f"elapsed={timing['elapsedSeconds']}s，throughput={timing['processesPerHour']} blocks/h，保守 ETA={timing['conservativeEtaUtc']}；"
        f"Unity={snapshot['unity']}；working-set/private/available={memory['workingSetBytes']}/{memory['privateMemoryBytes']}/{memory['availablePhysicalMemoryBytes']} bytes；"
        f"advisories={snapshot['advisoryCount']}，files={snapshot['outputFileCount']}，raw={snapshot['rawBytes']} bytes；"
        f"checkpoint={snapshot['durableCheckpointAtUtc']}（age {snapshot['durableCheckpointAgeSeconds']}s）；"
        f"reason={snapshot['reasonCodes']}；paths: checkpoint={paths['checkpoint']} status={paths['status']} receipt={paths['receipt']}。"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--write-snapshot", action="store_true")
    parser.add_argument("--render-report", action="store_true")
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    config_path = project / "Research/Gate13R_PR2_Attempt4_Monitoring_Config.v1.json"
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    delays = [int(value) for value in config["readRetrySeconds"]]
    status_path = project / config["statusRelativePath"]
    receipt_path = project / config["receiptRelativePath"]
    snapshot_root = project / config["snapshotRootRelativePath"]
    now = utc_now()
    previous = latest_snapshot(snapshot_root)
    if not status_path.is_file() or not receipt_path.is_file():
        snapshot = {
            "schemaVersion": 1,
            "snapshotKind": "gate13r-pr2-attempt4-operational-progress-v1",
            "capturedAtUtc": iso(now),
            "capturedAtAsiaShanghai": now.astimezone(SHANGHAI).isoformat(),
            "status": "NOT-STARTED",
            "notify": False,
            "notifyReason": "not-started",
        }
    else:
        status = read_json_retry(status_path, delays)
        receipt = read_json_retry(receipt_path, delays)
        if status.get("formalAttemptOrdinal") != 4 or receipt.get("formalAttemptOrdinal") != 4:
            raise RuntimeError("ATTEMPT4-IDENTITY-MISMATCH")
        receipt_sha = sha256_file(receipt_path)
        expected_formal_root = str((project / config["formalRootRelativePath"]).resolve())
        if status.get("executionReceiptSha256") != receipt_sha or receipt.get("formalRoot") != expected_formal_root:
            raise RuntimeError("ATTEMPT4-COMPOSITE-IDENTITY-MISMATCH")
        durable = parse_time(status.get("lastDurableCheckpointAtUtc"))
        started = parse_time(status.get("startedAtUtc"))
        elapsed = max(0.0, (now - started).total_seconds()) if started else None
        completed = int(status.get("completedProcessCount", 0))
        throughput = (completed / elapsed * 3600.0) if elapsed and completed else None
        remaining = int(status.get("totalProcessCount", 3552)) - completed
        eta = now + timedelta(hours=(remaining / throughput) * 1.2) if throughput and remaining > 0 else (now if remaining == 0 else None)
        age = max(0.0, (now - durable).total_seconds()) if durable else None
        state = str(status["status"])
        slot = now.strftime("%Y-%m-%dT%H:00Z")
        previous_state = None if previous is None else previous.get("status")
        previous_slot = None if previous is None else previous.get("notificationSlot")
        previous_escalated = bool(previous and previous.get("stallEscalated"))
        stalled = bool(state in ACTIVE and age is not None and age >= int(config["stallThresholdSeconds"]))
        immediate = state in TERMINAL and state != previous_state
        start_event = state in ACTIVE and (previous is None or previous_state == "NOT-STARTED")
        scheduled = state in ACTIVE and slot != previous_slot
        stall_event = stalled and not previous_escalated
        notify = bool(immediate or start_event or scheduled or stall_event)
        reason = "terminal-change" if immediate else "start" if start_event else "new-stall" if stall_event else "scheduled-hourly" if scheduled else "unchanged"
        unity = unity_identity(status)
        current = {
            "globalProcessOrdinal": status.get("currentGlobalProcessOrdinal"),
            "campaignId": status.get("currentCampaignId"),
            "scenarioId": status.get("currentScenarioId"),
            "cohort": status.get("currentCohort"),
            "blockId": status.get("currentBlockId"),
            "matchedSuperblockId": status.get("currentMatchedSuperblockId"),
            "abbaOrder": status.get("currentABBAOrder"),
            "williamsRow": status.get("currentWilliamsRow"),
        }
        snapshot = {
            "schemaVersion": 1,
            "snapshotKind": "gate13r-pr2-attempt4-operational-progress-v1",
            "capturedAtUtc": iso(now),
            "capturedAtAsiaShanghai": now.astimezone(SHANGHAI).isoformat(),
            "status": state,
            "phaseAState": state,
            "notify": notify,
            "notifyReason": reason,
            "notificationSlot": slot if notify and (scheduled or start_event) else previous_slot,
            "stallEscalated": stalled,
            "progress": {
                "completedProcesses": completed,
                "eligibleProcesses": int(status.get("eligibleProcessCount", 0)),
                "totalProcesses": int(status.get("totalProcessCount", 3552)),
                "completedSamples": int(status.get("completedSampleCount", 0)),
                "eligibleSamples": int(status.get("eligibleSampleCount", 0)),
                "totalSamples": int(status.get("totalSampleCount", 10176)),
                "automaticResumeCount": int(status.get("automaticResumeCount", 0)),
            },
            "current": current,
            "timing": {
                "elapsedSeconds": None if elapsed is None else round(elapsed, 3),
                "processesPerHour": None if throughput is None else round(throughput, 6),
                "conservativeEtaUtc": None if eta is None else iso(eta),
            },
            "unity": unity,
            "memory": {
                "workingSetBytes": status.get("latestWorkingSetBytes") if unity is None else unity.get("workingSetBytes"),
                "privateMemoryBytes": status.get("latestPrivateMemoryBytes") if unity is None else unity.get("privateMemoryBytes"),
                "availablePhysicalMemoryBytes": int(psutil.virtual_memory().available),
            },
            "advisoryCount": int(status.get("advisoryCrossingCount", 0)),
            "outputFileCount": int(status.get("outputFileCount", 0)),
            "rawBytes": int(status.get("rawBytes", 0)),
            "durableCheckpointAtUtc": status.get("lastDurableCheckpointAtUtc"),
            "durableCheckpointAgeSeconds": None if age is None else round(age, 3),
            "reasonCodes": [value for value in (status.get("errorReasonCode"), "DURABLE-CHECKPOINT-STALL" if stalled else None) if value],
            "paths": {
                "checkpoint": status.get("lastBlockEligibilityCommitPath"),
                "status": str(status_path),
                "receipt": str(receipt_path),
            },
            "formalStatisticalAnalysisExecuted": False,
            "gate14RExecuted": False,
        }
        if args.render_report:
            snapshot["reportZh"] = render_zh(snapshot)
    if args.write_snapshot:
        name = f"progress-{now.strftime('%Y%m%dT%H%M%S%fZ')}.json"
        atomic_create(snapshot_root / name, snapshot)
        snapshot["snapshotPath"] = str(snapshot_root / name)
    print(json.dumps(snapshot, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
