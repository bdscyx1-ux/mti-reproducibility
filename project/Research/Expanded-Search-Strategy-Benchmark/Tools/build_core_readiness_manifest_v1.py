#!/usr/bin/env python3
"""Build a structural core-readiness receipt for Gate13R-AX2."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
OUTPUT_DIR = PROJECT_ROOT / "Research" / "Verification" / "Gate13R-AX2" / "core-readiness-v1"
OUTPUT_PATH = OUTPUT_DIR / "core-readiness.v1.json"

FILES = [
    "Assets/_Scripts/Research/Navigation/NavigationContracts.cs",
    "Assets/_Scripts/Research/Experiments/PlanningFairnessContracts.cs",
    "Assets/_Scripts/Research/Experiments/DeterministicPlanningWorkloadRunner.cs",
    "Assets/_Scripts/Research/Algorithms/BidirectionalAStarRepeatedPlanner.cs",
    "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs",
    "Assets/_Scripts/Research/Editor/Gate13RAX2AlgorithmVerificationV1.cs",
    "Research/Gate13R-AX2/README.v1.md",
    "Research/Gate13R-AX2/experiment-plan.v1.md",
    "Research/Gate13R-AX2/Contracts/scientific-contract.v1.md",
    "Research/Gate13R-AX2/Contracts/four-algorithm-extension-fairness.v1.md",
    "Research/Gate13R-AX2/Algorithms/Bidirectional_A_Star_Repeated_Specification.v1.md",
    "Research/Gate13R-AX2/Algorithms/Lifelong_Planning_A_Star_Specification.v1.md",
    "Research/Gate13R-AX2/Analysis/p1-analysis-plan.v1.md",
    "Research/Gate13R-AX2/Tools/generate_schedule_v1.py",
    "Research/Gate13R-AX2/Execution/v1/formal-williams-schedule.v1.jsonl",
    "Research/Gate13R-AX2/Execution/v1/formal-williams-schedule-manifest.v1.json",
]

EXPECTED_SOURCE_HASHES = {
    "Research/Gate13R_Formal_Williams_Block_Schedule.v1.jsonl": "dc460db08f501ef39869de29602cc0caf15106a264f930b55eb1875336c91aa6",
    "Research/FormalScenarios/Gate11R_5pct/v1/catalog.json": "f99f1aff29e5fe244fa637d28ce243c4ca94f5679ad9bfb95f96a39ea6147e84",
    "Research/FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json": "cc5f020003f3fad75bd82ebb2c26df521fd639ff0ee5376132853120dbc16aa3",
    "Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json": "5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    source_checks = []
    for relative, expected in EXPECTED_SOURCE_HASHES.items():
        actual = sha256(PROJECT_ROOT / relative)
        source_checks.append({"path": relative, "expectedSha256": expected, "actualSha256": actual, "passed": actual == expected})

    schedule_manifest_path = PROJECT_ROOT / "Research/Gate13R-AX2/Execution/v1/formal-williams-schedule-manifest.v1.json"
    schedule_manifest = json.loads(schedule_manifest_path.read_text(encoding="utf-8"))
    schedule_path = PROJECT_ROOT / schedule_manifest["schedule"]["path"]
    schedule_lines = sum(1 for line in schedule_path.open("r", encoding="utf-8") if line.strip())
    schedule_checks = {
        "sha256": sha256(schedule_path),
        "expectedSha256": schedule_manifest["schedule"]["sha256"],
        "lineCount": schedule_lines,
        "campaignCount": schedule_manifest["campaignCount"],
        "blocksPerCampaign": schedule_manifest["blocksPerCampaign"],
        "algorithmSampleCount": schedule_manifest["algorithmSampleCount"],
        "passed": (
            sha256(schedule_path) == schedule_manifest["schedule"]["sha256"]
            and schedule_lines == 1536
            and schedule_manifest["campaignCount"] == 32
            and schedule_manifest["blocksPerCampaign"] == 48
            and schedule_manifest["algorithmSampleCount"] == 6144
        ),
    }

    algorithm_result_path = PROJECT_ROOT / "Research/Verification/Gate13R-AX2/algorithm-correctness-v1/algorithm-correctness.v1.json"
    algorithm_result = json.loads(algorithm_result_path.read_text(encoding="utf-8"))
    algorithm_checks = {
        "path": str(algorithm_result_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "sha256": sha256(algorithm_result_path),
        "passed": bool(algorithm_result.get("passed")) and algorithm_result.get("assertionCount") == 962,
        "assertionCount": algorithm_result.get("assertionCount"),
        "bidirectionalStaticCases": algorithm_result.get("bidirectionalStaticCases"),
        "lifelongStaticCases": algorithm_result.get("lifelongStaticCases"),
        "lifelongDynamicCases": algorithm_result.get("lifelongDynamicCases"),
        "gate13RScenarioIntegrationAlgorithms": algorithm_result.get("gate13RScenarioIntegrationAlgorithms"),
    }

    file_bindings = []
    for relative in FILES:
        path = PROJECT_ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"Missing core artifact: {relative}")
        file_bindings.append({"path": relative, "sha256": sha256(path), "bytes": path.stat().st_size})

    passed = all(item["passed"] for item in source_checks) and schedule_checks["passed"] and algorithm_checks["passed"]
    receipt = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-CORE-READINESS",
        "designId": "gate13r-ax2-shared32-b48-four-treatment-v1",
        "status": "CORE-READINESS-PASS" if passed else "CORE-READINESS-FAIL",
        "sourceBindingsPassed": all(item["passed"] for item in source_checks),
        "sourceChecks": source_checks,
        "scheduleChecks": schedule_checks,
        "algorithmCorrectness": algorithm_checks,
        "fileBindings": file_bindings,
        "formalExecutorFrozen": False,
        "rawCommitToolFrozen": False,
        "analysisImplementationFrozen": False,
        "formalCollectionAuthorized": False,
        "pendingBeforeFormalCollection": [
            "derive isolated Gate13R-AX2 block runner/supervisor from the Gate 13R process-per-block framework",
            "freeze output schema, structural validation, raw-commit tool, and P1 analysis implementation",
            "run non-formal smoke/memory/negative-path tests and build a final readiness receipt",
            "obtain a separate single-attempt formal collection authorization",
        ],
    }
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": receipt["status"], "path": str(OUTPUT_PATH)}, ensure_ascii=False))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

