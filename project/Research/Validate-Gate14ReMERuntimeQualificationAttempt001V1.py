#!/usr/bin/env python3
"""Validate the fail-closed Gate14Re-ME runtime qualification attempt-001."""

from __future__ import annotations

import argparse
import hashlib
import json
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence


PROJECT_RELATIVE = {
    "authorization": "Research/Gate14Re-ME/Gate14Re_ME_Runtime_Qualification_Authorization.v1.json",
    "preexecution": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/preexecution-manifest.v1.json",
    "implementation": "Research/Verification/Gate14Re-ME/qualification-implementation-freeze-attempt-001/implementation-manifest.v1.json",
    "source_freeze": "Research/Verification/Gate14Re-ME/qualification-implementation-freeze-attempt-001/freeze-receipt.v1.json",
    "runtime_manifest": "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json",
    "compile_receipt": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/unity-compile-receipt.v1.json",
    "compile_log": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/unity-compile.log",
    "instrument_receipt": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/csharp-instruments/instrument-runtime-receipt.v1.json",
    "instrument_log": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/unity-instrument-self-test.log",
    "pip_download_log": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/pip-download.log",
    "pip_install_log": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/pip-install.log",
    "failure_receipt": "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/failure-receipt.v1.json",
    "status": "Research/Gate14Re-ME/Gate14Re_ME_Status.v4.json",
}

EXPECTED_HASHES = {
    "authorization": "86f2e82282b98e5dd9d0e0f855faffcfee37c59ba9b18f03d2a0a417fee60b2d",
    "preexecution": "8cbf8de6fd151daa311e309dd854e9986956da5c8d5796dd8dad47c085a1ee1d",
    "implementation": "9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4",
    "source_freeze": "43c9dba8b49a1efe0802f6046170be57506c027af9ac764138843c60eef669f7",
    "runtime_manifest": "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e",
    "compile_receipt": "8bf340c15b8438e053ef21b47d35ced495b3939033423e40c6164e9799d0e019",
    "compile_log": "1b81ab325ae4491d9229915027ae6711d56f2aa544d543340000cf4bd08dc53c",
    "instrument_receipt": "be76050b64107f57b5b1086b3fcd318aa3d964c23f5f8dd9935798ff51f5b231",
    "instrument_log": "5d3ff6ae59468c0dc68ed158342e905c55e37b4d778ad2fd8c36fa97efef74da",
    "pip_download_log": "ba0fa92a56806dab41fd60c060aed80c71a54e7c4d32637b6aa79b195d81cd2a",
    "pip_install_log": "baa6eff3ca2f0e18e1febc190f0ccdb1830a875bb7cca8ea527e27a976da8d75",
    "failure_receipt": "8a508261f9c779ff3d3e3481d5eaf28ebc9d4c513cb69fdc8d30456b3ad9b49a",
    "status": "cad8a34346450b9ca286fcbf277a8b5e673198a256e91848903d0b56fc959b37",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def is_read_only(path: Path) -> bool:
    attributes = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attributes & stat.FILE_ATTRIBUTE_READONLY)


class Checks:
    def __init__(self) -> None:
        self.passed = 0
        self.failures: List[Dict[str, str]] = []

    def require(self, condition: bool, check_id: str, detail: str) -> None:
        if condition:
            self.passed += 1
        else:
            self.failures.append({"checkId": check_id, "detail": detail})


def unity_process_count() -> int:
    command = [
        "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
        "-NoProfile",
        "-Command",
        "@(Get-CimInstance Win32_Process -Filter \"Name = 'Unity.exe'\").Count",
    ]
    return int(subprocess.check_output(command, text=True).strip())


def validate(project_root: Path) -> Dict[str, Any]:
    checks = Checks()
    paths = {name: project_root / relative for name, relative in PROJECT_RELATIVE.items()}
    for name, expected in EXPECTED_HASHES.items():
        path = paths[name]
        checks.require(path.is_file(), f"exists:{name}", f"required file exists: {PROJECT_RELATIVE[name]}")
        if path.is_file():
            checks.require(sha256_file(path) == expected, f"hash:{name}", f"SHA-256 exact: {PROJECT_RELATIVE[name]}")
            checks.require(is_read_only(path), f"readonly:{name}", f"file remains read-only: {PROJECT_RELATIVE[name]}")

    implementation = read_json(paths["implementation"])
    artifacts = implementation.get("artifacts", [])
    checks.require(len(artifacts) == 24, "implementation-artifact-count", "prior source freeze retains 24 artifacts")
    for row in artifacts:
        path = project_root / str(row["relativePath"])
        checks.require(path.is_file(), f"implementation-exists:{row['relativePath']}", "source-freeze artifact exists")
        if path.is_file():
            checks.require(sha256_file(path) == row["sha256"], f"implementation-hash:{row['relativePath']}", "source-freeze artifact hash exact")
            checks.require(path.stat().st_size == int(row["bytes"]), f"implementation-bytes:{row['relativePath']}", "source-freeze artifact bytes exact")
            checks.require(is_read_only(path), f"implementation-readonly:{row['relativePath']}", "source-freeze artifact remains read-only")

    preexecution = read_json(paths["preexecution"])
    checks.require(preexecution.get("status") == "FROZEN_RUNTIME_QUALIFICATION_PREEXECUTION", "preexecution-status", "preexecution manifest status exact")
    for row in preexecution.get("artifacts", []):
        path = project_root / str(row["relativePath"])
        checks.require(path.is_file(), f"preexecution-exists:{row['relativePath']}", "preexecution artifact exists")
        if path.is_file():
            checks.require(sha256_file(path) == row["sha256"], f"preexecution-hash:{row['relativePath']}", "preexecution artifact hash exact")
            checks.require(path.stat().st_size == int(row["bytes"]), f"preexecution-bytes:{row['relativePath']}", "preexecution artifact bytes exact")
            checks.require(is_read_only(path), f"preexecution-readonly:{row['relativePath']}", "preexecution artifact remains read-only")

    runtime = read_json(paths["runtime_manifest"])
    checks.require(runtime.get("status") == "FROZEN_TYPED_PARQUET_RUNTIME", "runtime-status", "typed-Parquet runtime status exact")
    checks.require(runtime.get("distribution") == {"name": "pyarrow", "version": "25.0.1", "pythonAbi": "cp312", "platform": "win_amd64"}, "runtime-distribution", "typed-Parquet distribution exact")
    checks.require(runtime.get("wheelArtifactCount") == 1, "runtime-wheel-count", "exactly one frozen wheel")
    checks.require(runtime.get("installedFileCount") == 762, "runtime-installed-count", "installed-file count exact")
    for group_name, rows in (("wheel", runtime.get("wheelArtifacts", [])), ("installed", runtime.get("installedFiles", []))):
        for row in rows:
            path = project_root / str(row["relativePath"])
            checks.require(path.is_file(), f"{group_name}-exists:{row['relativePath']}", "runtime artifact exists")
            if path.is_file():
                checks.require(sha256_file(path) == row["sha256"], f"{group_name}-hash:{row['relativePath']}", "runtime artifact hash exact")
                checks.require(path.stat().st_size == int(row["bytes"]), f"{group_name}-bytes:{row['relativePath']}", "runtime artifact bytes exact")
                checks.require(is_read_only(path), f"{group_name}-readonly:{row['relativePath']}", "runtime artifact is read-only")

    compile_receipt = read_json(paths["compile_receipt"])
    checks.require(compile_receipt.get("status") == "PASS_UNITY_FROZEN_IMPLEMENTATION_COMPILE", "compile-status", "Unity compilation passed")
    checks.require(compile_receipt.get("compilerErrorMatches") == 0 and compile_receipt.get("successfulBatchmodeExitObserved") is True, "compile-evidence", "Unity compile log has no compiler errors and a successful exit")
    compile_log = paths["compile_log"].read_text(encoding="utf-8", errors="replace")
    checks.require("Exiting batchmode successfully now!" in compile_log and "Application will terminate with return code 0" in compile_log, "compile-log-success", "Unity log records successful batchmode return code 0")
    checks.require("error CS" not in compile_log and "Scripts have compiler errors" not in compile_log, "compile-log-no-errors", "Unity log has no compiler errors")

    instrument = read_json(paths["instrument_receipt"])
    checks.require(instrument.get("status") == "FAIL_CLOSED_CSHARP_INSTRUMENT_KNOWN_ANSWER", "instrument-status", "C# known-answer failed closed")
    checks.require(instrument.get("gridReadProxyKnownAnswerPassed") is True and instrument.get("gridReadProxySemanticInvariancePassed") is True, "d2-pass", "D2 controls passed")
    checks.require(instrument.get("allocationCounterPositiveControlPassed") is False and instrument.get("allocationCounterDifferenceBytes") == 0 and instrument.get("allocationPositiveControlBytes") == 1048576, "d3-fail-exact", "D3 exact failed positive-control values retained")
    checks.require(instrument.get("persistentStateSizerSyntheticFixturePassed") is True, "d4-pass", "D4 synthetic fixture passed")
    checks.require(instrument.get("clockMonotonicityPassed") is True and instrument.get("clockSamples") == 10000, "clock-pass", "clock monotonicity passed")
    checks.require(instrument.get("plannerConstructed") is False and instrument.get("algorithmLaneExecuted") is False and instrument.get("qualificationObservationCount") == 0, "instrument-boundary", "no planner, lane, or qualification observation")

    failure = read_json(paths["failure_receipt"])
    checks.require(failure.get("status") == "FAIL_CLOSED_D3_ALLOCATION_COUNTER_POSITIVE_CONTROL", "failure-status", "failure receipt status exact")
    disposition = failure.get("downstreamDisposition", {})
    checks.require(disposition.get("automaticRetryPerformed") is False and disposition.get("frozenImplementationModified") is False and disposition.get("exportKnownAnswerRun") is False, "failure-disposition", "no retry, modification, or downstream exporter run")
    checks.require(not (project_root / "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/python-export").exists(), "export-output-absent", "export known-answer output was not created")

    status = read_json(paths["status"])
    checks.require(status.get("status") == "RUNTIME_QUALIFICATION_FAILED_CLOSED_D3_COUNTER_UNUSABLE", "status-v4", "status v4 records fail-closed D3 outcome")
    boundary = status.get("scientificBoundary", {})
    checks.require(boundary == {"qualificationScheduleRows": 0, "qualificationInputs": 0, "anonymousIdentityMappings": 0, "qualificationObservations": 0, "algorithmLanes": 0, "formalObservations": 0, "formalAnalysisPerformed": False, "algorithmRankingPerformed": False, "winnerAdjudicationPerformed": False}, "status-boundary", "scientific boundary remains all-zero/false")

    for relative in (
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ):
        checks.require(not (project_root / relative).exists(), f"prohibited-root-absent:{relative}", "prohibited root remains absent")

    current_unity = unity_process_count()
    checks.require(current_unity == 0, "unity-process-count", "no Unity process remains")
    return {
        "schema": "gate14re-me-runtime-qualification-attempt-001-validation-v1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_FAILURE_EVIDENCE_FROZEN" if not checks.failures else "FAIL_VALIDATION",
        "checksPassed": checks.passed,
        "checksFailed": len(checks.failures),
        "failures": checks.failures,
        "runtimeWheelArtifactCount": runtime.get("wheelArtifactCount"),
        "runtimeInstalledFileCount": runtime.get("installedFileCount"),
        "sourceFreezeArtifactCount": len(artifacts),
        "currentUnityProcessCount": current_unity,
        "d3AllocationCounterPositiveControlPassed": instrument.get("allocationCounterPositiveControlPassed"),
        "d3AllocationCounterDifferenceBytes": instrument.get("allocationCounterDifferenceBytes"),
        "exportKnownAnswerRun": False,
        "qualificationScheduleRows": 0,
        "qualificationInputs": 0,
        "anonymousIdentityMappings": 0,
        "qualificationObservationCount": 0,
        "algorithmLanes": 0,
        "formalObservationCount": 0,
        "formalAnalysisPerformed": False,
        "rankingOrWinnerComputed": False,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = validate(Path(args.project_root).resolve())
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result["checksFailed"] == 0 else 2
    except Exception as exc:
        print(json.dumps({"schema": "gate14re-me-runtime-qualification-attempt-001-validation-v1", "status": "FAIL_VALIDATION", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
