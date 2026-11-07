#!/usr/bin/env python3
"""Static, synthetic, and no-launch readiness tests for formal attempt 4."""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import jsonschema


def sha256_file(path: Path) -> str:
    import hashlib
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_module(path: Path):
    specification = importlib.util.spec_from_file_location("gate13r_attempt4_execution", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("unable to load attempt-4 execution module")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    if output_dir.exists():
        raise FileExistsError(output_dir)
    output_dir.mkdir(parents=True)
    orchestrator_path = project / "Research/Gate13RPR2Attempt4ExecutionV1.py"
    launcher_path = project / "Research/Run-Gate13RPR2FormalAttempt4V1.ps1"
    wrapper_path = project / "Research/Run-Gate13RPR2MP2FormalBlockV4.ps1"
    module = load_module(orchestrator_path)
    checks: list[dict] = []

    def check(name: str, passed: bool, detail=None) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    try:
        compile(orchestrator_path.read_text(encoding="utf-8"), str(orchestrator_path), "exec")
        check("python-orchestrator-parser", True, sha256_file(orchestrator_path))
    except Exception as error:
        check("python-orchestrator-parser", False, f"{type(error).__name__}:{error}")

    core = module.validate_prelaunch(project, require_targets_absent=True)
    check("core-validation-pass", core["passed"] is True)
    check("fresh-attempt4-targets-absent", core["formalTargetsAbsent"] is True)
    check("attempt3-terminal-preserved", core["attempt3HistoricalTerminalPreserved"] is True)
    check("attempt3-data-reuse-forbidden", core["attempt3DataReuseAuthorized"] is False)
    check("blockwise-formal-eligibility-enabled", core["perCompletedBlockFormalEligibility"] is True)
    check("automatic-resume-enabled-and-bounded", core["automaticResumeAuthorized"] is True and core["maximumAutomaticResumeCount"] == 3)
    check("automatic-measured-retry-forbidden", core["automaticMeasuredRetryAuthorized"] is False)
    check("phase-b-and-gate14r-not-authorized", core["phaseBFormalStatisticalAnalysisAuthorized"] is False and core["gate14RAuthorized"] is False)
    check("schedule-cardinality", core["schedule"]["processCount"] == 3552 and core["schedule"]["sampleCount"] == 10176)

    schema = json.loads((project / module.STATUS_SCHEMA_REL).read_text(encoding="utf-8-sig"))
    candidate_status = module.status_template(project, "a" * 64, "2026-10-10T00:00:00Z")
    jsonschema.validate(candidate_status, schema)
    check("attempt4-status-schema", True)
    candidate_status["status"] = "AUTO-RESUME-RUNNING"
    candidate_status["automaticResumeCount"] = 3
    jsonschema.validate(candidate_status, schema)
    check("attempt4-resume-status-schema", True)
    candidate_status["automaticResumeCount"] = 4
    try:
        jsonschema.validate(candidate_status, schema)
        check("resume-count-overflow-rejected", False)
    except jsonschema.ValidationError:
        check("resume-count-overflow-rejected", True)

    with tempfile.TemporaryDirectory(prefix="g13r-a4-synthetic-") as temp:
        root = Path(temp)
        formal_root = root / "formal"
        control_root = formal_root / "_control"
        (formal_root / "_plans").mkdir(parents=True)
        (control_root / "process-identities").mkdir(parents=True)
        (control_root / "block-eligibility-commits").mkdir(parents=True)
        (control_root / "block-wrapper-logs").mkdir(parents=True)
        record = {"globalProcessOrdinal": 1, "outputRelativePath": "campaigns/c/blocks/b"}
        paths = module.block_paths(formal_root, control_root, record)
        check("synthetic-artifact-state-not-started", module.artifact_state(formal_root, control_root, record) == "not-started")
        paths["plan"].write_text("{}\n", encoding="utf-8")
        check("plan-only-remains-resumable-not-started", module.artifact_state(formal_root, control_root, record) == "not-started")
        paths["stdout"].parent.mkdir(parents=True, exist_ok=True)
        paths["stdout"].write_text("launched\n", encoding="utf-8")
        check("execution-log-without-completion-is-ambiguous", module.artifact_state(formal_root, control_root, record) == "partial-or-ambiguous")
        paths["stdout"].unlink()
        paths["manifest"].parent.mkdir(parents=True)
        paths["manifest"].write_text("{}\n", encoding="utf-8")
        paths["summary"].write_text("{}\n", encoding="utf-8")
        check("complete-pair-detected-for-promotion", module.artifact_state(formal_root, control_root, record) == "complete-uncommitted")
        paths["commit"].write_text("{}\n", encoding="utf-8")
        check("commit-dominates-artifact-state", module.artifact_state(formal_root, control_root, record) == "committed")
        a = root / "a.txt"
        b = root / "b.txt"
        a.write_text("a\n", encoding="utf-8")
        b.write_text("b\n", encoding="utf-8")
        first = module.files_tree([b, a], root)
        second = module.files_tree([a, b], root)
        check("block-raw-tree-order-deterministic", first == second)
        resume_root = control_root / "resume-events"
        resume_root.mkdir(parents=True)
        (resume_root / "r01.json").write_text("{}\n", encoding="utf-8")
        (resume_root / "r01-promotion.json").write_text("{}\n", encoding="utf-8")
        check("promotion-receipt-does-not-consume-resume-count", len(module.resume_event_paths(control_root)) == 1)
        stable_path = root / "stable-commit.json"
        stable_path.write_text(json.dumps({"createdAtUtc": "old", "value": 7}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        stable_value = module.idempotent_commit_value(
            stable_path, {"createdAtUtc": "new", "value": 7}, "createdAtUtc"
        )
        check("raw-commit-retry-preserves-original-timestamp", stable_value == {"createdAtUtc": "old", "value": 7})
        later_record = {"globalProcessOrdinal": 2, "outputRelativePath": "campaigns/c/blocks/b2"}
        later_paths = module.block_paths(formal_root, control_root, later_record)
        later_paths["plan"].write_text("{}\n", encoding="utf-8")
        try:
            module.ensure_no_later_artifacts(formal_root, control_root, [later_record], 0)
            check("later-plan-artifact-rejected", False)
        except module.UnsafeResume:
            check("later-plan-artifact-rejected", True)

    source = orchestrator_path.read_text(encoding="utf-8")
    check("append-only-block-eligibility-commit-present", "formalStatisticalEligibility\": True" in source and "block-eligibility-commits" in source)
    check("no-automatic-measured-retry", '"automaticMeasuredRetryAttempted": False' in source and '"automaticMeasuredRetry": False' in source)
    check("partial-ambiguous-fails-closed", "PARTIAL-OR-AMBIGUOUS-NEXT-BLOCK" in source)
    check("three-resume-cap", "MAX_AUTO_RESUMES = 3" in source)
    check("repeated-session-failure-signature-fails-closed", "ATTEMPT4-REPEATED-SESSION-FAILURE-SIGNATURE" in source)
    check("raw-commit-exhaustion-prohibits-supervisor-resume", "gate13r-pr2-attempt4-raw-commit-auto-resume-prohibited-v1" in source)
    check("fresh-v4-root", module.FORMAL_ROOT_REL.endswith("/v4"))

    native_powershell = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
    for name, script, extra in (
        ("launcher-binding-smoke", launcher_path, ["-Mode", "Validate"]),
        ("block-wrapper-binding-smoke", wrapper_path, ["-BlockPlanPath", "x", "-OutputDirectory", "y", "-AllowedRoot", "z", "-ExecutionReceiptPath", "r"]),
    ):
        completed = subprocess.run(
            [str(native_powershell), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script), "-ProjectPath", str(project), *extra, "-BindingSmokeOnly"],
            capture_output=True, text=True, check=False,
        )
        check(name, completed.returncode == 0 and "BINDING-SMOKE-PASSED" in completed.stdout, completed.stderr.strip())

    check("unity-quiescent", len(module.base.current_unity_processes()) == 0)
    check("project-lock-absent", not (project / "Temp/UnityLockfile").exists())
    failed = [item for item in checks if not item["passed"]]
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-formal-attempt4-prelaunch-static-synthetic-summary-v1",
        "passed": not failed,
        "testCount": len(checks),
        "passedTestCount": len(checks) - len(failed),
        "failedTestCount": len(failed),
        "failedTestNames": [item["name"] for item in failed],
        "checks": checks,
        "formalTargetsAbsent": core["formalTargetsAbsent"],
        "unityInvocations": 0,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }
    (output_dir / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "output": str(output_dir / "summary.json")}, sort_keys=True))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
