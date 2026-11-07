#!/usr/bin/env python3
"""Synthetic and static validation-only tests for Gate 13R-PR2-FD1."""

from __future__ import annotations

import importlib.util
import argparse
import json
import math
import tempfile
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
ANALYZER = PROJECT / "Research/Analyze-Gate13RPR2Attempt2FailureV1.py"


def load_module():
    specification = importlib.util.spec_from_file_location("fd1_analyzer", ANALYZER)
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(module)
    return module


def require(condition: bool, name: str) -> None:
    if not condition:
        raise AssertionError(name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    module = load_module()
    tests: list[tuple[str, bool]] = []

    def check(name: str, condition: bool) -> None:
        require(condition, name)
        tests.append((name, True))

    check("mib-definition", module.MIB == 1048576)
    check("threshold-equality-passes", module.threshold_summary([512 * module.MIB], 512 * module.MIB)["exceededCount"] == 0)
    check("threshold-one-byte-over-fails", module.threshold_summary([512 * module.MIB + 1], 512 * module.MIB)["exceededCount"] == 1)
    check("negative-growth-retained", module.describe([-10, 0, 10])["min"] == -10)
    check("r7-p50", module.r7_quantile([0, 10], 0.5) == 5)
    check("r7-p90", module.r7_quantile([0, 10], 0.9) == 9)
    check("canonical-forward-slash", module.canonical_line("a\\b", 3, "AA") == b"a/b\t3\taa\n")
    check("grid-size-classification", module.grid_size_from("grid-scale-g256-shared") == "g256")
    check("grid-size-unclassified", module.grid_size_from("shared") == "UNCLASSIFIED")
    try:
        module.finite_number(-1, "raw", nonnegative=True)
        raise AssertionError("negative-raw-rejection")
    except module.DiagnosticError:
        tests.append(("negative-raw-rejection", True))
    for invalid, name in ((float("nan"), "nan-rejection"), (float("inf"), "infinity-rejection"), ("1", "string-rejection"), (None, "missing-rejection")):
        try:
            module.finite_number(invalid, name)
            raise AssertionError(name)
        except module.DiagnosticError:
            tests.append((name, True))
    synthetic_blocks = [
        {"maximumBlockWorkingSetGrowthBytes": 512 * module.MIB, "maximumBlockPrivateMemoryGrowthBytes": 512 * module.MIB},
        {"maximumBlockWorkingSetGrowthBytes": 512 * module.MIB + 1, "maximumBlockPrivateMemoryGrowthBytes": 1},
    ]
    candidate = module.candidate_counts(synthetic_blocks, 512)
    check("block-max-candidate-count", candidate["eitherExceededBlockCount"] == 1)
    check("attempt-disposition-immutable", candidate["attempt2DispositionUnaffected"] is True)
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / "root"
        root.mkdir()
        (root / "b.txt").write_bytes(b"b")
        (root / "a.txt").write_bytes(b"a")
        first, first_hash, first_bytes = module.build_file_manifest(root)
        second, second_hash, second_bytes = module.build_file_manifest(root)
        check("manifest-deterministic", first == second and first_hash == second_hash and first_bytes == second_bytes)
        check("manifest-ordinal-order", [item["relativePath"] for item in first] == ["a.txt", "b.txt"])
    source = ANALYZER.read_text(encoding="utf-8")
    forbidden_execution_tokens = ["Unity.exe", "Start-Process", "subprocess.run", "subprocess.Popen", "FormalRuns/Gate13R_RQAligned_S48H48/v3"]
    check("no-unity-or-attempt3-execution", not any(token in source for token in forbidden_execution_tokens))
    forbidden_inference_tokens = ["holm_correction", "candidate-n-formal", "scipy.stats", "statsmodels", "p_value", "p-value"]
    check("no-formal-performance-inference", not any(token.lower() in source.lower() for token in forbidden_inference_tokens))
    prompt = (PROJECT / "Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Next_Authorization_Prompt.md").read_text(encoding="utf-8")
    check("authorization-prohibits-unity", "不授权任何新的 Unity Editor 运行" in prompt)
    check("authorization-prohibits-attempt3", "不授权 attempt 3" in prompt)
    check("authorization-prohibits-formal-analysis", "不授权任何新的 Unity Editor 运行、正式统计分析或 Gate 14R" in prompt)
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-failure-diagnosis-synthetic-test-summary-v1",
        "passed": True,
        "passedCount": len(tests),
        "failedCount": 0,
        "tests": [{"name": name, "passed": passed} for name, passed in tests],
        "unityInvoked": False,
        "formalAnalysisPerformed": False,
        "attempt3Created": False,
    }
    if args.output:
        module.atomic_write_json(Path(args.output).resolve(), result)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
