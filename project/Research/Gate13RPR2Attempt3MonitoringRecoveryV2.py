#!/usr/bin/env python3
"""Versioned v2 entry for the Gate 13R-PR2 attempt-3 monitor.

This module preserves the v1 implementation and repairs only the scheduled
report-state omission documented in the v2 implementation-repair note.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import Gate13RPR2Attempt3MonitoringRecoveryV1 as _CORE
from Gate13RPR2Attempt3MonitoringRecoveryV1 import *  # noqa: F401,F403


SCRIPT_VERSION = "gate13r-pr2-attempt3-monitoring-recovery-v2"
DEFAULT_CONFIG = _CORE.PROJECT_ROOT / "Research/Gate13R_PR2_Attempt3_Monitoring_Config.v2.json"
_CORE.SCRIPT_VERSION = SCRIPT_VERSION
_CORE.DEFAULT_CONFIG = DEFAULT_CONFIG


def _derive_notification_v2(snapshot: dict[str, Any], previous: dict[str, Any] | None) -> None:
    reasons: list[str] = []
    status = snapshot["status"]
    previous_status = None if previous is None else previous.get("status")
    active_report_states = {
        "ACQUISITION-RUNNING",
        "ACQUISITION-COMPLETE-COMMIT-PENDING",
        "RAW-COMMIT-RECOVERY",
    }
    if status == "NOT-STARTED":
        snapshot["notify"] = False
        snapshot["notificationReason"] = []
        return
    if status in active_report_states:
        if previous is None or previous_status not in active_report_states:
            reasons.append("ACQUISITION-STARTED" if status == "ACQUISITION-RUNNING" else "RAW-COMMIT-ACTIVE")
        else:
            current_slot = snapshot["timing"].get("reportSlot")
            prior_slot = previous.get("timing", {}).get("reportSlot")
            if current_slot is not None and prior_slot is not None and int(current_slot) > int(prior_slot):
                reasons.append("HOURLY-PROGRESS")
    if status == _CORE.TERMINAL_FAILURE and previous_status != _CORE.TERMINAL_FAILURE:
        reasons.append("ACQUISITION-FAILED")
    if status == _CORE.RAW_COMPLETE and previous_status != _CORE.RAW_COMPLETE:
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


def _apply_stall_policy_v2(
    snapshot: dict[str, Any], previous: dict[str, Any] | None, now: Any, config: dict[str, Any]
) -> None:
    active_states = set(config.get("scheduledReportStates", ["ACQUISITION-RUNNING"]))
    if snapshot["status"] not in active_states:
        return
    policy = config["stallPolicy"]
    status_age = snapshot["timing"]["statusAgeSeconds"]
    if status_age is not None and status_age > int(policy["statusStaleAdvisorySecondsExclusive"]):
        snapshot["health"]["reasonCodes"].append("STATUS-STALE-ADVISORY")
    if snapshot["status"] == "ACQUISITION-RUNNING":
        block_elapsed = snapshot["timing"]["currentBlockElapsedSeconds"]
        if block_elapsed is not None and block_elapsed > int(policy["hardTimeoutOverdueActionSecondsExclusive"]):
            _CORE._set_action_required(snapshot, "HARD-TIMEOUT-OVERDUE-ACTION-REQUIRED")
        last_progress = snapshot["progress"].get("lastProgressAtUtc")
        process_matched = snapshot["telemetry"]["osQueryStatus"] in {"MATCHED", "SKIPPED-VALIDATION-ONLY"}
        if last_progress and process_matched:
            no_progress = (now - _CORE.parse_datetime(last_progress)).total_seconds()
            if no_progress > int(policy["noProgressStallSecondsExclusive"]):
                snapshot["health"]["reasonCodes"].append("STALL-SUSPECTED")
    snapshot["health"]["reasonCodes"] = sorted(set(snapshot["health"]["reasonCodes"]))
    if snapshot["status"] != "ACTION-REQUIRED" and snapshot["health"]["reasonCodes"]:
        snapshot["health"]["classification"] = "ADVISORY"


_CORE._derive_notification = _derive_notification_v2
_CORE._apply_stall_policy = _apply_stall_policy_v2


def main(argv: list[str] | None = None) -> int:
    _CORE._derive_notification = _derive_notification_v2
    _CORE._apply_stall_policy = _apply_stall_policy_v2
    _CORE.DEFAULT_CONFIG = DEFAULT_CONFIG
    return _CORE.main(argv)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (_CORE.MonitorError, OSError, ValueError, KeyError) as error:
        import sys
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2)
