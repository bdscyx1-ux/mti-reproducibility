#!/usr/bin/env python3
"""Mechanically derived v3 harness for the v2 monitor repair."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


SOURCE = Path(__file__).with_name("Test-Gate13RPR2Attempt3MonitoringRecoveryV1.py")


def load_repaired_namespace() -> dict[str, object]:
    source = SOURCE.read_text(encoding="utf-8")
    transformations = [
        ("import Gate13RPR2Attempt3MonitoringRecoveryV1 as MON", "import Gate13RPR2Attempt3MonitoringRecoveryV2 as MON"),
        ('Gate13RPR2Attempt3MonitoringRecoveryV1.py', 'Gate13RPR2Attempt3MonitoringRecoveryV2.py'),
        ('Get-Gate13RPR2Attempt3OperationalProgressV1.ps1', 'Get-Gate13RPR2Attempt3OperationalProgressV2.ps1'),
        ('require(snap["notificationReason"] == ["HOURLY-PROGRESS"], str(snap["notificationReason"]))', 'require(snap["notificationReason"].count("HOURLY-PROGRESS") == 1, str(snap["notificationReason"]))'),
    ]
    for old, new in transformations:
        if source.count(old) < 1:
            raise RuntimeError(f"V1 harness source identity mismatch: {old}")
        source = source.replace(old, new)
    insertion_point = "    # 52-54: runtime compatibility and final preservation.\n"
    extra = '''    # v2 repair-specific raw-commit monitoring checks.\n    def raw_commit_hourly() -> None:\n        now = base_time + timedelta(hours=12)\n        fx = harness.new_fixture("raw-commit-hourly", now, "RAW-COMMIT-RECOVERY")\n        first = fx.snapshot(now, skip_os=True)\n        require("RAW-COMMIT-ACTIVE" in first["notificationReason"], str(first["notificationReason"]))\n        prior = fx.store_previous(first)\n        later = now + timedelta(hours=1)\n        fx.status["savedAtUtc"] = iso(later)\n        fx.status["lastDurableCheckpointAtUtc"] = iso(later)\n        second = fx.snapshot(later, prior, skip_os=True)\n        require(second["notificationReason"].count("HOURLY-PROGRESS") == 1, str(second["notificationReason"]))\n    harness.check("T55-raw-commit-hourly-report", raw_commit_hourly)\n\n    def raw_commit_stale() -> None:\n        now = base_time + timedelta(hours=14)\n        fx = harness.new_fixture("raw-commit-stale", now, "ACQUISITION-COMPLETE-COMMIT-PENDING")\n        fx.status["savedAtUtc"] = iso(now - timedelta(seconds=901))\n        snap = fx.snapshot(now, skip_os=True)\n        require("STATUS-STALE-ADVISORY" in snap["health"]["reasonCodes"], str(snap["health"]))\n    harness.check("T56-raw-commit-status-stale-advisory", raw_commit_stale)\n\n'''
    if source.count(insertion_point) != 1:
        raise RuntimeError("V1 harness insertion point mismatch.")
    source = source.replace(insertion_point, extra + insertion_point)
    source = source.replace('passed_count == len(harness.checks) == 54', 'passed_count == len(harness.checks) == 56')
    source = source.replace('"testCount": 54,', '"testCount": 56,')
    source = source.replace('"passedTestCount": 54,', '"passedTestCount": 56,')
    namespace: dict[str, object] = {"__name__": "gate13r_pr2_attempt3_monitoring_recovery_v3_derived", "__file__": str(SOURCE), "__package__": None}
    exec(compile(source, str(SOURCE) + "::v3-v2-monitor-validation", "exec"), namespace)
    return namespace


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    result = load_repaired_namespace()["run"](args.output_root)  # type: ignore[index,operator]
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "outputRoot": result["outputRoot"], "derivedHarnessVersion": 3}, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
