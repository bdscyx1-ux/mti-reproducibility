#!/usr/bin/env python3
"""No-Unity structural preflight for Gate 13R P1-C5 independent study."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"unable to load module: {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--execution-contract-sha256", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    if output_dir.exists():
        raise FileExistsError(output_dir)
    output_dir.mkdir(parents=True)
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: Any = None) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    contract_path = project / "Research/Gate13R_P1C5_Independent_Execution_Contract.v1.json"
    check("execution-contract-sha256", contract_path.is_file() and sha256_file(contract_path) == args.execution_contract_sha256)
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    check("execution-contract-frozen-status", contract.get("status") == "FROZEN-PRELAUNCH-NOT-EXECUTED")
    check("phase-b-not-authorized", contract.get("phaseBAnalysisAuthorized") is False)
    check("gate14r-and-m1m5-not-authorized", contract.get("gate14RAuthorized") is False and contract.get("m1ThroughM5Authorized") is False)
    check("no-auto-retry-resume-topup", all(contract.get(key) is False for key in ("automaticRetryAuthorized", "automaticResumeAuthorized", "topUpAuthorized", "replacementAuthorized", "reorderAuthorized")))

    python_files = [
        "Research/Prepare-Gate13RP1C5IndependentV1.py",
        "Research/New-Gate13RP1C5IndependentBlockPlanV1.py",
        "Research/Gate13RP1C5IndependentExecutionV1.py",
        "Research/Analyze-Gate13RP1C5IndependentPhaseBV1.py",
        "Research/Test-Gate13RP1C5IndependentPreflightV1.py",
    ]
    for relative in python_files:
        path = project / relative
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
            check(f"python-parser:{relative}", True, sha256_file(path))
        except Exception as error:
            check(f"python-parser:{relative}", False, f"{type(error).__name__}:{error}")

    execution = load_module("gate13r_p1c5_execution", project / "Research/Gate13RP1C5IndependentExecutionV1.py")
    core = execution.validate_prelaunch(project, args.execution_contract_sha256, require_targets_absent=True)
    check("core-validation", core.get("passed") is True)
    check("fresh-formal-targets-absent", core.get("formalTargetsAbsent") is True)
    check("schedule-cardinality", core.get("processCount") == 1600 and core.get("sampleCount") == 3200)
    check("fixed-campaign-design", core.get("campaignCount") == 32 and core.get("blocksPerCampaign") == 50)

    prepare = subprocess.run(
        [sys.executable, str(project / "Research/Prepare-Gate13RP1C5IndependentV1.py"), "--project-root", str(project)],
        capture_output=True,
        text=True,
        check=False,
    )
    check("deterministic-preparation-idempotent", prepare.returncode == 0, prepare.stderr.strip())
    if prepare.returncode == 0:
        prepared = json.loads(prepare.stdout)
        check("power-gate-and-no-upward-adjustment", prepared.get("passed") is True and prepared.get("selectedBlocksPerCampaign") == 50 and prepared.get("minimumDirectionalPowerLower", 0) >= 0.90, prepared)

    power = json.loads((project / "Research/Gate13R_P1C5_Independent_Power_Simulation.v1.json").read_text(encoding="utf-8-sig"))
    check("power-report-pass", power.get("passed") is True)
    check("type-i-simulation-near-alpha", abs(float(power["nullTypeIErrorCheck"]["estimate"]) - 0.05) <= 0.005)

    schedule = list(execution.iter_jsonl(project / "Research/Gate13R_P1C5_Independent_Schedule.v1.jsonl"))
    by_campaign_order: dict[tuple[str, str], int] = {}
    for record in schedule:
        key = (str(record["campaignId"]), str(record["orderLabel"]))
        by_campaign_order[key] = by_campaign_order.get(key, 0) + 1
    check("campaign-order-balance", len(by_campaign_order) == 64 and set(by_campaign_order.values()) == {25})
    check("fresh-process-flag-all-records", all(record.get("freshProcessRequired") is True and record.get("maximumBlocksInProcess") == 1 for record in schedule))

    analysis = load_module("gate13r_p1c5_analysis", project / "Research/Analyze-Gate13RP1C5IndependentPhaseBV1.py")
    critical = analysis.student_t_ppf(0.975, 1536.0)
    check("student-t-critical-sanity", 1.959 < critical < 1.963, critical)
    analyzer_source = (project / "Research/Analyze-Gate13RP1C5IndependentPhaseBV1.py").read_text(encoding="utf-8")
    check("analysis-requires-separate-authorization", "GATE13R-P1C5-INDEPENDENT-PHASEB-FORMAL-ANALYSIS-AUTHORIZATION" in analyzer_source)
    check("analysis-output-outside-raw-root", 'ANALYSIS_ROOT_REL = "Research/Analysis/Gate13R_P1C5_Independent/v1"' in analyzer_source)

    csharp = (project / "Assets/_Scripts/Research/Editor/Gate13RP1C5FormalBatchCommandV1.cs").read_text(encoding="utf-8")
    check("csharp-independent-class", "public static class Gate13RP1C5FormalBatchCommandV1" in csharp)
    check("csharp-independent-design", 'DesignId = "gate13r-p1c5-independent-confirmatory-study-v1"' in csharp)
    check("csharp-pair-only-cohort", 'cohortId == "p1-c5-shared-goal-v1"' in csharp and 'cohortId == "four-algorithm-shared-goal-v1"' not in csharp)
    check("csharp-independent-cli-namespace", "-ddmGate13RP1C5BlockPlanPath" in csharp and "-ddmGate13RP1C5OutputDirectory" in csharp)

    attempt4_contract = json.loads((project / "Research/Gate13R_PR2_Attempt4_Execution_Contract.v1.json").read_text(encoding="utf-8-sig"))
    frozen_original_hash = attempt4_contract["frozenBindings"]["Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs"]
    check("attempt4-command-preserved", sha256_file(project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs") == frozen_original_hash)

    native_powershell = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
    smoke_cases = [
        (
            "launcher-binding-smoke",
            project / "Research/Run-Gate13RP1C5IndependentV1.ps1",
            ["-ExecutionContractSha256", args.execution_contract_sha256],
        ),
        (
            "block-wrapper-binding-smoke",
            project / "Research/Run-Gate13RP1C5IndependentBlockV1.ps1",
            ["-BlockPlanPath", "x", "-OutputDirectory", "y", "-AllowedRoot", "z", "-ExecutionReceiptPath", "r"],
        ),
    ]
    for name, script, extra in smoke_cases:
        completed = subprocess.run(
            [str(native_powershell), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script), "-ProjectPath", str(project), *extra, "-BindingSmokeOnly"],
            capture_output=True,
            text=True,
            check=False,
        )
        check(name, completed.returncode == 0 and "BINDING-SMOKE-PASSED" in completed.stdout, completed.stderr.strip())

    process_check = subprocess.run(
        [str(native_powershell), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count"],
        capture_output=True,
        text=True,
        check=False,
    )
    check("unity-quiescent", process_check.returncode == 0 and process_check.stdout.strip() == "0", process_check.stdout.strip())
    check("project-lock-absent", not (project / "Temp/UnityLockfile").exists())
    check("formal-root-still-absent-after-preflight", not (project / "Research/FormalRuns/Gate13R_P1C5_Independent/v1").exists())
    check("execution-receipt-still-absent-after-preflight", not (project / "Research/Gate13R_P1C5_Independent_Execution_Receipt.v1.json").exists())

    failed = [item for item in checks if not item["passed"]]
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-p1c5-independent-no-unity-preflight-summary-v1",
        "passed": not failed,
        "testCount": len(checks),
        "passedTestCount": len(checks) - len(failed),
        "failedTestCount": len(failed),
        "failedTestNames": [item["name"] for item in failed],
        "checks": checks,
        "executionContractSha256": args.execution_contract_sha256,
        "formalTargetsAbsent": core.get("formalTargetsAbsent"),
        "unityInvoked": False,
        "phaseBAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "m1ThroughM5Authorized": False,
    }
    output_path = output_dir / "summary.json"
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "output": str(output_path)}, sort_keys=True))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
