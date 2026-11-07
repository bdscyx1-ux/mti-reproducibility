#!/usr/bin/env python3
"""Run and record the Gate13R-AX2 injected-failure supervisor test."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any, Sequence


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"


class TestError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise TestError(message)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--powershell-exe", type=pathlib.Path, required=True)
    parser.add_argument("--supervisor", type=pathlib.Path, required=True)
    parser.add_argument("--project-root", type=pathlib.Path, required=True)
    parser.add_argument("--unity-exe", type=pathlib.Path, required=True)
    parser.add_argument("--schedule", type=pathlib.Path, required=True)
    parser.add_argument("--schedule-sha256", required=True)
    parser.add_argument("--schema", type=pathlib.Path, required=True)
    parser.add_argument("--schema-sha256", required=True)
    parser.add_argument("--contract", type=pathlib.Path, required=True)
    parser.add_argument("--contract-sha256", required=True)
    parser.add_argument("--measured-root", type=pathlib.Path, required=True)
    parser.add_argument("--python-exe", type=pathlib.Path, required=True)
    parser.add_argument("--structural-tool", type=pathlib.Path, required=True)
    parser.add_argument("--structural-tool-sha256", required=True)
    parser.add_argument("--raw-commit-tool", type=pathlib.Path, required=True)
    parser.add_argument("--raw-commit-tool-sha256", required=True)
    parser.add_argument("--receipt", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        measured_root = args.measured_root.resolve()
        require(not measured_root.exists(), f"Expected-failure root already exists: {measured_root}")
        require(sha256_file(args.raw_commit_tool.resolve()) == args.raw_commit_tool_sha256.lower(), "Raw-commit tool SHA-256 mismatch.")
        command = [
            str(args.powershell_exe.resolve()), "-NoProfile", "-File", str(args.supervisor.resolve()),
            "-Mode", "Verification",
            "-ProjectRoot", str(args.project_root.resolve()),
            "-UnityExe", str(args.unity_exe.resolve()),
            "-SchedulePath", str(args.schedule.resolve()),
            "-ScheduleSha256", args.schedule_sha256.lower(),
            "-OutputSchemaPath", str(args.schema.resolve()),
            "-OutputSchemaSha256", args.schema_sha256.lower(),
            "-ExecutionContractPath", str(args.contract.resolve()),
            "-ExecutionContractSha256", args.contract_sha256.lower(),
            "-MeasuredRoot", str(measured_root),
            "-PythonExe", str(args.python_exe.resolve()),
            "-StructuralToolPath", str(args.structural_tool.resolve()),
            "-StructuralToolSha256", args.structural_tool_sha256.lower(),
            "-BlockIds", "g13rax2-c01-b0002",
            "-InjectFailurePosition", "3",
            "-DisableReplacement",
            "-ProcessTimeoutSeconds", "3600",
        ]
        completed = subprocess.run(command, text=True, encoding="utf-8", errors="replace", capture_output=True, check=False)
        require(completed.returncode == 2, f"Expected supervisor exit code 2, got {completed.returncode}.")
        failure_path = measured_root / "_control" / "failure-receipt.v1.json"
        status_path = measured_root / "_control" / "execution-status.json"
        require(failure_path.is_file() and status_path.is_file(), "Expected failure/status receipts are missing.")
        failure = load_json(failure_path)
        status = load_json(status_path)
        require(failure.get("status") == "FAIL-CLOSED" and status.get("status") == "FAIL-CLOSED", "Supervisor did not fail closed.")
        require(status.get("acceptedBlocks") == 0 and status.get("acceptedAnonymousSamples") == 0, "Injected partial block was accepted.")
        require(status.get("wholeBlockReplacements") == 0 and failure.get("automaticWholeAttemptRetry") is False, "Injected-failure test performed an unauthorized retry/replacement.")
        require(not (measured_root / "_control" / "acquisition-complete.v1.json").exists(), "Failed acquisition incorrectly has a completion receipt.")
        require(not list((measured_root / "_control" / "accepted-blocks").glob("*.json")), "Failed acquisition has an accepted-block receipt.")
        require(not (measured_root / "_commit").exists(), "Failed acquisition has a raw-commit directory.")
        raw_commit_command = [
            str(args.python_exe.resolve()), str(args.raw_commit_tool.resolve()), "commit",
            "--mode", "verification",
            "--project-root", str(args.project_root.resolve()),
            "--measured-root", str(measured_root),
            "--schedule", str(args.schedule.resolve()),
            "--schedule-sha256", args.schedule_sha256.lower(),
            "--schema", str(args.schema.resolve()),
            "--schema-sha256", args.schema_sha256.lower(),
            "--contract", str(args.contract.resolve()),
            "--contract-sha256", args.contract_sha256.lower(),
            "--structural-tool", str(args.structural_tool.resolve()),
            "--structural-tool-sha256", args.structural_tool_sha256.lower(),
            "--expected-blocks", "1",
        ]
        raw_commit = subprocess.run(raw_commit_command, text=True, encoding="utf-8", errors="replace", capture_output=True, check=False)
        require(raw_commit.returncode == 2, f"Expected raw-commit rejection exit code 2, got {raw_commit.returncode}.")
        require("failure receipt" in raw_commit.stderr.lower(), "Raw-commit rejection did not identify the failure receipt.")
        require(not (measured_root / "_commit").exists(), "Rejected raw commit created a commit directory.")
        receipt = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-EXPECTED-FAILURE-TEST",
            "designId": DESIGN_ID,
            "status": "PASS",
            "validatedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "test": {
                "blockId": "g13rax2-c01-b0002",
                "injectedFailurePosition": 3,
                "replacementDisabled": True,
                "supervisorExitCode": completed.returncode,
                "acceptedBlocks": status["acceptedBlocks"],
                "acceptedAnonymousSamples": status["acceptedAnonymousSamples"],
                "wholeBlockReplacements": status["wholeBlockReplacements"],
                "acquisitionCompleteReceiptAbsent": True,
                "acceptedBlockReceiptsAbsent": True,
                "rawCommitDirectoryAbsent": True,
                "rawCommitRejectionExitCode": raw_commit.returncode,
                "rawCommitRejectionReasonMatched": True,
            },
            "bindings": {
                "supervisorSha256": sha256_file(args.supervisor.resolve()),
                "executionContractSha256": args.contract_sha256.lower(),
                "failureReceiptSha256": sha256_file(failure_path),
                "executionStatusSha256": sha256_file(status_path),
                "stdoutSha256": sha256_text(completed.stdout),
                "stderrSha256": sha256_text(completed.stderr),
                "rawCommitToolSha256": sha256_file(args.raw_commit_tool.resolve()),
                "rawCommitToolExpectedSha256": args.raw_commit_tool_sha256.lower(),
                "rawCommitStdoutSha256": sha256_text(raw_commit.stdout),
                "rawCommitStderrSha256": sha256_text(raw_commit.stderr),
            },
            "formalCollectionStarted": False,
            "originalGate13RRawOrAnalysisReadOrModified": False,
        }
        write_json_new(args.receipt.resolve(), receipt)
        print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), "supervisorExitCode": completed.returncode}, sort_keys=True))
        return 0
    except (TestError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
