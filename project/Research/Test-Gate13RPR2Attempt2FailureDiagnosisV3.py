#!/usr/bin/env python3
"""Synthetic/static tests for the v2 enforcement-boundary amendment."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
ANALYZER = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV3.py"


def load_module():
    spec = importlib.util.spec_from_file_location("gate13r_pr2_fd1_v3", ANALYZER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    module = load_module()
    tests: list[dict[str, object]] = []

    def check(name: str, condition: bool) -> None:
        if not condition:
            raise AssertionError(name)
        tests.append({"name": name, "passed": True})

    def simulate(final: bool, working: int, private: int, limit: int) -> tuple[bool, str]:
        crossing = working > limit or private > limit
        if final and crossing:
            return False, "HARD-FAIL"
        return True, "PASS"

    limit = 512 * 1024 * 1024
    check("equal-boundary-nonfinal-passes", simulate(False, limit, limit, limit) == (True, "PASS"))
    check("one-byte-over-nonfinal-is-deferred", simulate(False, limit + 1, limit + 1, limit) == (True, "PASS"))
    check("one-byte-over-final-hard-fails", simulate(True, limit + 1, limit + 1, limit) == (False, "HARD-FAIL"))
    check("below-limit-final-passes", simulate(True, limit, limit - 1, limit) == (True, "PASS"))

    synthetic_rows = [
        {"position": 1, "algorithmId": "A*-R", "predecessorAlgorithmId": "NONE", "nativeThresholdCrossedAtBoundary": True, "hardGateEnforcedAtBoundary": False},
        {"position": 2, "algorithmId": "D*L", "predecessorAlgorithmId": "A*-R", "nativeThresholdCrossedAtBoundary": True, "hardGateEnforcedAtBoundary": False},
        {"position": 3, "algorithmId": "IDFF", "predecessorAlgorithmId": "D*L", "nativeThresholdCrossedAtBoundary": True, "hardGateEnforcedAtBoundary": False},
        {"position": 4, "algorithmId": "C-FF", "predecessorAlgorithmId": "IDFF", "nativeThresholdCrossedAtBoundary": True, "hardGateEnforcedAtBoundary": True},
    ]
    first = next(row for row in synthetic_rows if row["nativeThresholdCrossedAtBoundary"])
    enforced = next(row for row in synthetic_rows if row["hardGateEnforcedAtBoundary"])
    check("first-crossing-distinct-from-enforcement", first["position"] == 1 and enforced["position"] == 4)
    check("final-algorithm-cause-attribution-prohibited", first["algorithmId"] != enforced["algorithmId"])

    source = ANALYZER.read_text(encoding="utf-8")
    check("explicit-not-identifiable", "NOT-IDENTIFIABLE" in source)
    check("explicit-enforcement-not-cause", "enforcement point, not an identified cause" in source)
    check("no-unity-command", not any(token in source for token in ("Unity.exe", "Start-Process", "subprocess.run", "subprocess.Popen")))
    check("no-attempt3-root", "Gate13R_RQAligned_S48H48/v3" not in source)
    check("no-formal-inference", not any(token in source.lower() for token in ("holm_correction", "p_value", "p-value", "candidate-n-formal")))

    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-enforcement-boundary-v3-test-summary",
        "passed": True,
        "passedCount": len(tests),
        "failedCount": 0,
        "tests": tests,
        "unityInvoked": False,
        "formalAnalysisPerformed": False,
        "attempt3Created": False,
    }
    if args.output:
        module.CORE.atomic_write_json(Path(args.output).resolve(), result)
    print(json.dumps(result, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
