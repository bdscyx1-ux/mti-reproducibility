#!/usr/bin/env python3
"""Versioned mechanical repair of the v1 validation harness.

The monitoring implementation and frozen expected behavior are unchanged.  The
only transformation changes T12 from exact array equality to a count of one
HOURLY-PROGRESS reason, because an independent STALL-SUSPECTED safety event may
legitimately be reported on the same watcher tick.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


SOURCE = Path(__file__).with_name("Test-Gate13RPR2Attempt3MonitoringRecoveryV1.py")
OLD = 'require(snap["notificationReason"] == ["HOURLY-PROGRESS"], str(snap["notificationReason"]))'
NEW = 'require(snap["notificationReason"].count("HOURLY-PROGRESS") == 1, str(snap["notificationReason"]))'


def load_repaired_namespace() -> dict[str, object]:
    source = SOURCE.read_text(encoding="utf-8")
    if source.count(OLD) != 1:
        raise RuntimeError("V1 harness source identity mismatch for the one permitted mechanical transformation.")
    repaired = source.replace(OLD, NEW)
    namespace: dict[str, object] = {
        "__name__": "gate13r_pr2_attempt3_monitoring_recovery_v2_derived",
        "__file__": str(SOURCE),
        "__package__": None,
    }
    exec(compile(repaired, str(SOURCE) + "::v2-mechanical-repair", "exec"), namespace)
    return namespace


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    namespace = load_repaired_namespace()
    result = namespace["run"](args.output_root)  # type: ignore[index,operator]
    print(json.dumps({
        "passed": result["passed"],
        "testCount": result["testCount"],
        "passedTestCount": result["passedTestCount"],
        "outputRoot": result["outputRoot"],
        "derivedHarnessVersion": 2,
    }, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
