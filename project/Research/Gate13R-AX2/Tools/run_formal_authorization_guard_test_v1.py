#!/usr/bin/env python3
"""Verify that the AX2 supervisor cannot create a formal root without authorization."""

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


class GuardError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GuardError(message)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


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
    parser.add_argument("--candidate-formal-root", type=pathlib.Path, required=True)
    parser.add_argument("--python-exe", type=pathlib.Path, required=True)
    parser.add_argument("--structural-tool", type=pathlib.Path, required=True)
    parser.add_argument("--structural-tool-sha256", required=True)
    parser.add_argument("--receipt", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        candidate = args.candidate_formal_root.resolve()
        require(not candidate.exists(), f"Candidate formal root unexpectedly exists before guard test: {candidate}")
        command = [
            str(args.powershell_exe.resolve()), "-NoProfile", "-File", str(args.supervisor.resolve()),
            "-Mode", "Formal",
            "-ProjectRoot", str(args.project_root.resolve()),
            "-UnityExe", str(args.unity_exe.resolve()),
            "-SchedulePath", str(args.schedule.resolve()),
            "-ScheduleSha256", args.schedule_sha256.lower(),
            "-OutputSchemaPath", str(args.schema.resolve()),
            "-OutputSchemaSha256", args.schema_sha256.lower(),
            "-ExecutionContractPath", str(args.contract.resolve()),
            "-ExecutionContractSha256", args.contract_sha256.lower(),
            "-MeasuredRoot", str(candidate),
            "-PythonExe", str(args.python_exe.resolve()),
            "-StructuralToolPath", str(args.structural_tool.resolve()),
            "-StructuralToolSha256", args.structural_tool_sha256.lower(),
        ]
        completed = subprocess.run(command, text=True, encoding="utf-8", errors="replace", capture_output=True, check=False)
        require(completed.returncode == 2, f"Expected authorization-guard exit code 2, got {completed.returncode}.")
        combined = (completed.stdout + "\n" + completed.stderr).lower()
        require("authorization receipt" in combined, "Authorization guard did not identify the missing receipt.")
        require(not candidate.exists(), "Authorization-guard test created a formal root.")
        receipt = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-FORMAL-AUTHORIZATION-GUARD-TEST",
            "designId": DESIGN_ID,
            "status": "PASS",
            "validatedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "candidateFormalRoot": str(candidate),
            "supervisorExitCode": completed.returncode,
            "missingAuthorizationRejected": True,
            "formalRootCreated": False,
            "unityProcessLaunched": False,
            "bindings": {
                "supervisorSha256": sha256_file(args.supervisor.resolve()),
                "executionContractSha256": args.contract_sha256.lower(),
                "stdoutSha256": sha256_text(completed.stdout),
                "stderrSha256": sha256_text(completed.stderr),
            },
            "formalCollectionStarted": False,
            "originalGate13RRawOrAnalysisReadOrModified": False,
        }
        write_json_new(args.receipt.resolve(), receipt)
        print(json.dumps({"status": "PASS", "receipt": str(args.receipt.resolve()), "formalRootCreated": False}, sort_keys=True))
        return 0
    except (GuardError, OSError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
