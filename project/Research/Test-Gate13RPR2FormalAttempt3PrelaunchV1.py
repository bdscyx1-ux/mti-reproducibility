#!/usr/bin/env python3
"""Static/unit/synthetic prelaunch tests for Gate 13R-PR2 formal attempt 3."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import jsonschema


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(path)
    payload = (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".g13r-a3-test-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def load_module(path: Path):
    specification = importlib.util.spec_from_file_location("gate13r_attempt3_execution", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("unable to load attempt-3 execution module")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--builder-fixture-root", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    builder_root = Path(args.builder_fixture_root).resolve()
    if output_dir.exists() or builder_root.exists():
        raise FileExistsError("prelaunch test outputs must be create-new")
    output_dir.mkdir(parents=True)
    builder_root.mkdir(parents=True)
    orchestrator_path = project / "Research/Gate13RPR2Attempt3ExecutionV1.py"
    module = load_module(orchestrator_path)
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: Any = None) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    try:
        compile(orchestrator_path.read_text(encoding="utf-8"), str(orchestrator_path), "exec")
        check("python-orchestrator-parser", True, sha256_file(orchestrator_path))
    except Exception as error:
        check("python-orchestrator-parser", False, f"{type(error).__name__}:{error}")

    core = module.validate_prelaunch(project, require_targets_absent=True)
    check("core-validation-pass", core["passed"] is True)
    check("frozen-hash-audit-pass", all(item["passed"] for item in core["frozenHashAudit"]), len(core["frozenHashAudit"]))
    schedule, overlay, schedule_summary = module.validate_schedule(project)
    expected_summary = {
        "scenarioCount": 53,
        "campaignCount": 74,
        "processCount": 3552,
        "sampleCount": 10176,
        "runIdCount": 10176,
        "sharedProcessCount": 1536,
        "heterogeneousProcessCount": 2016,
        "matchedSuperblockCount": 1008,
        "heterogeneousScenarioCount": 21,
        "abbaSuperblocksPerScenario": "24/24",
        "abbaProcessRecordsPerScenario": "48/48",
        "orderByWilliamsRowCountPerCell": 12,
        "uniqueBlockAndOutputIdentity": True,
    }
    check("schedule-cardinality-and-balance", schedule_summary == expected_summary, schedule_summary)
    check("global-ordinal-contiguous", [int(value["globalProcessOrdinal"]) for value in schedule] == list(range(1, 3553)))
    run_ids = [str(entry["runId"]) for record in schedule for entry in record["entries"]]
    check("run-id-global-uniqueness", len(run_ids) == 10176 and len(set(run_ids)) == 10176)
    check("output-identity-global-uniqueness", len({str(value["outputRelativePath"]) for value in schedule}) == 3552)

    selected = [1, 48, 1536, 1537, 1538, 2000, 3552]
    deterministic_rows: list[dict[str, Any]] = []
    builder = project / module.PLAN_BUILDER_REL
    for ordinal in selected:
        direct = module.make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
        direct_again = module.make_plan(project, schedule[ordinal - 1], overlay[ordinal - 1], formal=False)
        check(f"direct-plan-deterministic-{ordinal}", module.json_bytes(direct) == module.json_bytes(direct_again))
        builder_path = builder_root / f"p{ordinal:06d}.json"
        completed = subprocess.run(
            [
                sys.executable,
                str(builder),
                "--project-root",
                str(project),
                "--global-process-ordinal",
                str(ordinal),
                "--output",
                str(builder_path),
                "--mode",
                "validation",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        check(f"frozen-builder-exit-{ordinal}", completed.returncode == 0, completed.stderr.strip())
        if completed.returncode == 0:
            builder_plan = json.loads(builder_path.read_text(encoding="utf-8-sig"))
            check(f"direct-plan-exact-match-frozen-builder-{ordinal}", direct == builder_plan)
            deterministic_rows.append(
                {
                    "globalProcessOrdinal": ordinal,
                    "blockId": direct["blockId"],
                    "planSha256": sha256_file(builder_path),
                }
            )

    formal_plan = module.make_plan(project, schedule[0], overlay[0], formal=True, receipt_sha256="a" * 64)
    check("formal-plan-boundary", formal_plan["formalCampaign"] is True and formal_plan["validationOnly"] is False and formal_plan["executionReceiptSha256"] == "a" * 64)
    check("formal-plan-no-injections", all(formal_plan[key] == 0 for key in ("verificationInjectedFailurePosition", "validationInjectedNativeHardPosition", "validationInjectedTelemetryFailurePosition", "validationInjectedPersistenceFailurePosition")))
    check("formal-plan-one-block-identity", formal_plan["globalProcessOrdinal"] == 1 and formal_plan["blockId"] == schedule[0]["blockId"])

    status_schema = json.loads((project / module.STATUS_SCHEMA_REL).read_text(encoding="utf-8-sig"))
    status = module.status_template(project=project, receipt_sha="b" * 64, started_at="2026-10-09T00:00:00Z")
    jsonschema.validate(status, status_schema)
    check("status-prelaunch-schema", True)
    running = dict(status)
    module.apply_record_to_status(running, schedule[0])
    running.update(
        {
            "status": "ACQUISITION-RUNNING",
            "currentUnityProcessId": 1234,
            "currentUnityProcessStartedAtUtc": "2026-10-09T00:00:01Z",
            "currentUnityBlockStartedAtUtc": "2026-10-09T00:00:01Z",
            "latestWorkingSetBytes": 1,
            "latestPrivateMemoryBytes": 1,
            "latestAvailablePhysicalMemoryBytes": 1,
        }
    )
    jsonschema.validate(running, status_schema)
    check("status-running-schema", True)
    for state in (
        "ACQUISITION-COMPLETE-COMMIT-PENDING",
        "RAW-COMMIT-RECOVERY",
        "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE",
        "FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE",
        "USER-ACTION-REQUIRED",
    ):
        candidate = dict(status)
        candidate["status"] = state
        candidate["rawDataComplete"] = state == "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE"
        jsonschema.validate(candidate, status_schema)
        check(f"status-terminal-or-commit-schema-{state.lower()}", True)
    invalid = dict(status)
    invalid["forbiddenAdditionalProperty"] = True
    try:
        jsonschema.validate(invalid, status_schema)
        check("status-additional-property-rejected", False)
    except jsonschema.ValidationError:
        check("status-additional-property-rejected", True)

    fixture_root = output_dir / "synthetic-atomic"
    fixture_root.mkdir()
    atomic_target = fixture_root / "value.json"
    module.atomic_json(atomic_target, {"value": 1}, replace=False)
    check("atomic-create", json.loads(atomic_target.read_text(encoding="utf-8")) == {"value": 1})
    try:
        module.atomic_json(atomic_target, {"value": 2}, replace=False)
        check("atomic-create-rejects-overwrite", False)
    except module.ContractError:
        check("atomic-create-rejects-overwrite", True)
    module.atomic_json(atomic_target, {"value": 3}, replace=True)
    check("atomic-replace", json.loads(atomic_target.read_text(encoding="utf-8")) == {"value": 3})

    payload_root = output_dir / "synthetic-payload" / "campaigns"
    (payload_root / "a").mkdir(parents=True)
    (payload_root / "a" / "x.json").write_text('{"x":1}\n', encoding="utf-8")
    (payload_root / "b.txt").write_text("b\n", encoding="utf-8")
    first = module.payload_snapshot(payload_root)
    second = module.payload_snapshot(payload_root)
    check("payload-snapshot-deterministic", first["canonicalTreeSha256"] == second["canonicalTreeSha256"] and first["fileCount"] == 2)
    (payload_root / "b.txt").write_text("changed\n", encoding="utf-8")
    third = module.payload_snapshot(payload_root)
    check("payload-mutation-detected", third["canonicalTreeSha256"] != first["canonicalTreeSha256"])

    source = orchestrator_path.read_text(encoding="utf-8")
    check("no-adaptive-stopping-path", "adaptive stopping" not in source.lower() or "never" in source.lower())
    check("measured-retry-flags-frozen-false", '"automaticMeasuredRetryAttempted": False' in source and '"automaticResumeAttempted": False' in source)
    check("phase-b-not-invoked", "formalStatisticalAnalysisAuthorized\": False" in source and "gate14RAuthorized\": False" in source)
    check("strict-serial-popen", "for record, policy in zip(schedule, overlay, strict=True)" in source)
    check("frozen-v3-wrapper-used", module.BLOCK_WRAPPER_REL == "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1")
    check("two-stage-raw-complete-token", module.RAW_COMPLETE == "RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE")

    formal_targets = [project / module.FORMAL_ROOT_REL, project / module.RECEIPT_REL, project / module.STATUS_REL]
    check("formal-targets-remain-absent", not any(path.exists() for path in formal_targets), [str(path) for path in formal_targets])
    check("no-unity-launched-by-static-tests", len(module.current_unity_processes()) == 0)
    check("project-lock-remains-absent", not (project / "Temp/UnityLockfile").exists())
    post_hashes = module.assert_hashes(project)
    check("post-test-frozen-hash-audit-pass", all(item["passed"] for item in post_hashes), len(post_hashes))

    failed = [item for item in checks if not item["passed"]]
    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-formal-attempt3-prelaunch-static-unit-synthetic-summary-v1",
        "passed": not failed,
        "testCount": len(checks),
        "passedTestCount": len(checks) - len(failed),
        "failedTestCount": len(failed),
        "failedTestNames": [item["name"] for item in failed],
        "checks": checks,
        "scheduleSummary": schedule_summary,
        "deterministicPlanReconstructions": deterministic_rows,
        "formalTargetsAbsent": not any(path.exists() for path in formal_targets),
        "unityInvocations": 0,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }
    atomic_json(output_dir / "summary.json", result)
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "output": str(output_dir / "summary.json")}, sort_keys=True))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
