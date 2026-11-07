#!/usr/bin/env python3
"""Read-only validator for Gate14Re-ME D3 compatibility amendment attempt-001."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys


AUTH_SHA = "a3d6d370caba32c586a57ab205bcb8dc5e745130c87410aeec35318cc837463c"
PLAN_SHA = "9db7d8e0e3c04d719ebd789da5d3cbf8b5f4368f5bc82bdb68a6c2749ae58df1"
PREEXEC_SHA = "bbf989968c12813143b32694950639e3998cd5cd5c936eb043997fb8899ea8f0"
LOG_SHA = "96b5e5558e2c960600c2752479c5f2a404a62243a0a2f0a2673b754534ba78a0"
FAILURE_SHA = "abffc0f216a18666ffb046ab0d7ebe9058e54a15cb07d3ecadd5715352c91ee1"
STATUS_V5_SHA = "66b6a3adbd2c889d19994fa4f3b2a1e5f69cbe60bddb81040b713e3013c3dc80"
EVIDENCE_MANIFEST_SHA = "587a8cbc94da4a551ced320a28dc02181c1858d5bba4c617763c915f9f98b16c"
PRIOR_STATUS_V4_SHA = "cad8a34346450b9ca286fcbf277a8b5e673198a256e91848903d0b56fc959b37"
PRIOR_INSTRUMENTATION_SHA = "e3b52047276a3ae6961914881ba6aaf78bb6a913ca70e4edebb974b2b6deacdb"
PRIOR_LOAD_RUNNER_SHA = "7bb9237e529f511ad12fcfcb8374db02818977092c3680b287aacc817d182033"
UNITY_SHA = "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def is_read_only(path: Path) -> bool:
    attributes = path.stat().st_file_attributes
    return bool(attributes & stat.FILE_ATTRIBUTE_READONLY)


def unity_process_count() -> int:
    executable = Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
    completed = subprocess.run(
        [
            str(executable),
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return int(completed.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    expected_root = Path("H:/DDM_Final_Project").resolve()

    checks_passed = 0
    failures: list[str] = []

    def check(condition: bool, label: str) -> None:
        nonlocal checks_passed
        if condition:
            checks_passed += 1
        else:
            failures.append(label)

    check(root == expected_root, "project root mismatch")

    paths = {
        "authorization": root / "Research/Gate14Re-ME/Gate14Re_ME_D3_Runtime_Compatibility_Amendment_Authorization.v1.json",
        "plan": root / "Research/Gate14Re-ME/Gate14Re_ME_D3_Runtime_Compatibility_Amendment_Plan.v1.md",
        "preexecution": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/preexecution-manifest.v1.json",
        "log": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/unity-d3-known-answer.log",
        "failure": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/failure-receipt.v1.json",
        "status_v5": root / "Research/Gate14Re-ME/Gate14Re_ME_Status.v5.json",
        "evidence_manifest": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/failure-evidence-manifest.v1.json",
        "prior_status_v4": root / "Research/Gate14Re-ME/Gate14Re_ME_Status.v4.json",
        "prior_instrumentation": root / "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEInstrumentationV1.cs",
        "prior_load_runner": root / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs",
        "unity": Path("H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe"),
    }
    expected_hashes = {
        "authorization": AUTH_SHA,
        "plan": PLAN_SHA,
        "preexecution": PREEXEC_SHA,
        "log": LOG_SHA,
        "failure": FAILURE_SHA,
        "status_v5": STATUS_V5_SHA,
        "evidence_manifest": EVIDENCE_MANIFEST_SHA,
        "prior_status_v4": PRIOR_STATUS_V4_SHA,
        "prior_instrumentation": PRIOR_INSTRUMENTATION_SHA,
        "prior_load_runner": PRIOR_LOAD_RUNNER_SHA,
        "unity": UNITY_SHA,
    }

    for name, path in paths.items():
        check(path.is_file(), f"missing {name}: {path}")
        if path.is_file():
            check(sha256(path) == expected_hashes[name], f"hash mismatch for {name}")
            if name != "unity":
                check(is_read_only(path), f"not read-only: {name}")

    authorization = read_json(paths["authorization"])
    check(authorization.get("schema") == "gate14re-me-d3-runtime-compatibility-amendment-authorization-v1", "authorization schema")
    check(authorization.get("authorizationId") == "gate14re-me-d3-runtime-compatibility-amendment-attempt-001", "authorization id")
    check(authorization.get("status") == "AUTHORIZED_D3_RUNTIME_COMPATIBILITY_AMENDMENT_ONLY", "authorization status")
    allowed = authorization.get("authorizedScope", {})
    check(all(value is True for value in allowed.values()), "authorized D3-only scope incomplete")
    prohibited = authorization.get("prohibitedScope", {})
    check(all(value is False for value in prohibited.values()), "prohibited scope enabled")
    check(authorization.get("runtimeBindings", {}).get("automaticRetryAuthorized") is False, "automatic retry authorized")

    failure = read_json(paths["failure"])
    check(failure.get("status") == "FAIL_CLOSED_D3_CANDIDATE_API_NOT_IN_UNITY_COMPILE_SURFACE", "failure status")
    check(failure.get("failedStage") == "unity-compile-before-d3-known-answer", "failed stage")
    check(failure.get("unityProcess", {}).get("exitCode") == 1, "Unity exit code")
    check(failure.get("unityProcess", {}).get("automaticRetryPerformed") is False, "retry occurred")
    check(failure.get("candidate", {}).get("compilePassed") is False, "candidate unexpectedly compiled")
    check(failure.get("candidate", {}).get("runtimeKnownAnswerStarted") is False, "runtime known-answer unexpectedly started")
    disposition = failure.get("downstreamDisposition", {})
    check(disposition.get("fallbackCounterTested") is False, "fallback counter tested")
    check(disposition.get("runtimeQualificationAttempt002Started") is False, "attempt-002 started")
    check(disposition.get("dataExporterKnownAnswerRun") is False, "export known-answer ran")
    check(disposition.get("algorithmLaneExecuted") is False, "algorithm lane executed")
    check(disposition.get("formalAnalysisPerformed") is False, "formal analysis performed")
    check(disposition.get("rankingOrWinnerComputed") is False, "ranking or winner computed")

    status = read_json(paths["status_v5"])
    check(status.get("status") == "D3_RUNTIME_COMPATIBILITY_AMENDMENT_ATTEMPT_001_FAILED_CLOSED_COMPILE_API_UNAVAILABLE", "status-v5 state")
    amendment = status.get("d3CompatibilityAmendment", {})
    check(amendment.get("compilePassed") is False, "status-v5 compile flag")
    check(amendment.get("positiveControlsExecuted") == 0, "positive controls unexpectedly executed")
    check(amendment.get("negativeControlIntervalsExecuted") == 0, "negative controls unexpectedly executed")
    boundary = status.get("scientificBoundary", {})
    for key in ("qualificationScheduleRows", "qualificationInputs", "anonymousIdentityMappings", "qualificationObservations", "algorithmLanes", "formalObservations"):
        check(boundary.get(key) == 0, f"nonzero scientific-boundary field: {key}")
    check(boundary.get("formalAnalysisPerformed") is False, "formal analysis boundary")
    check(boundary.get("algorithmRankingPerformed") is False, "ranking boundary")
    check(boundary.get("winnerAdjudicationPerformed") is False, "winner boundary")

    log_text = paths["log"].read_text(encoding="utf-8", errors="replace")
    check("error CS0117: 'GC' does not contain a definition for 'GetTotalAllocatedBytes'" in log_text, "CS0117 evidence absent")
    check("Scripts have compiler errors." in log_text, "Unity compile-failure terminator absent")

    manifest = read_json(paths["evidence_manifest"])
    check(manifest.get("status") == "FROZEN_FAILURE_EVIDENCE_MANIFEST", "evidence manifest status")
    for artifact in manifest.get("artifacts", []):
        artifact_path = root / artifact["relativePath"]
        check(artifact_path.is_file(), f"manifest artifact missing: {artifact_path}")
        if artifact_path.is_file():
            check(artifact_path.stat().st_size == artifact["bytes"], f"manifest byte count mismatch: {artifact_path}")
            check(sha256(artifact_path) == artifact["sha256"], f"manifest hash mismatch: {artifact_path}")
            check(is_read_only(artifact_path), f"manifest artifact not read-only: {artifact_path}")

    check(not (root / "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEAllocationCounterV2.cs").exists(), "failed counter remains active")
    check(not (root / "Assets/_Scripts/Research/Editor/Gate14ReMED3RuntimeCompatibilityRunnerV1.cs").exists(), "failed harness remains active")
    check(not (root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/d3-known-answer").exists(), "D3 runtime receipt directory exists")
    check(not (root / "Research/Gate14Re-ME/Execution/v2/load-qualification-instrument-contract.v2.json").exists(), "unqualified v2 instrument contract exists")

    for relative in (
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ):
        check(not (root / relative).exists(), f"prohibited root exists: {relative}")

    try:
        current_unity_process_count = unity_process_count()
    except Exception as exception:  # pragma: no cover - fail closed on host inspection errors
        current_unity_process_count = -1
        failures.append(f"Unity process inspection failed: {exception}")
    check(current_unity_process_count == 0, "Unity process count is not zero")

    result = {
        "schema": "gate14re-me-d3-runtime-compatibility-amendment-validation-result-v1",
        "status": "PASS_FAILURE_EVIDENCE_FROZEN" if not failures else "FAIL_VALIDATION",
        "checksPassed": checks_passed,
        "checksFailed": len(failures),
        "failures": failures,
        "currentUnityProcessCount": current_unity_process_count,
        "d3RuntimeKnownAnswerExecuted": False,
        "algorithmLaneExecuted": False,
        "formalAnalysisPerformed": False,
        "rankingOrWinnerComputed": False,
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
