#!/usr/bin/env python3
"""Terminal, non-executing consistency audit for Gate 13R-PR2-MP2."""

from __future__ import annotations

import hashlib
import json
import locale
import os
import subprocess
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Research"
MANIFEST = RESEARCH / "Gate13R_PR2_MP2_Evidence_Manifest.v2.json"
READINESS = RESEARCH / "Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json"
PASSPORT = RESEARCH / "Gate13R_PR2_MP2_Run_Passport.md"
LEDGER = RESEARCH / "Gate13R_PR2_MP2_Run_Passport_run_ledger.yaml"
TARGET = RESEARCH / "Gate13R_PR2_MP2_Terminal_Consistency_Audit.v3.json"
ATTEMPT1_FAILURE = RESEARCH / "Gate13R_PR2_MP2_Terminal_Audit_Attempt1_Failure_Receipt.v1.json"
ATTEMPT2_FAILURE = RESEARCH / "Gate13R_PR2_MP2_Terminal_Audit_Attempt2_Failure_Receipt.v1.json"
PYTHON = Path(r"C:\Users\bdscy\AppData\Local\Python\bin\python.exe")
LEDGER_TOOL = Path(
    r"C:\Users\bdscy\.codex\plugins\cache\ars-codex\ars-codex\3.23.0"
    r"\skills\academic-research-suite\ars\scripts\run_ledger.py"
)
POWERSHELL = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")

FORBIDDEN = (
    RESEARCH / "FormalRuns" / "Gate13R_RQAligned_S48H48" / "v3",
    RESEARCH / "Gate13R_PR2_Formal_Execution_Receipt.v3.json",
    RESEARCH / "Gate13R_PR2_Formal_Execution_Status.v3.json",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_identity(path: Path) -> dict[str, object]:
    return {
        "relativePath": path.relative_to(ROOT).as_posix(),
        "rawBytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def verify_identity(record: dict[str, object]) -> dict[str, object]:
    path = ROOT / str(record["relativePath"])
    exists = path.is_file()
    actual_bytes = path.stat().st_size if exists else None
    actual_hash = sha256(path) if exists else None
    passed = (
        exists
        and actual_bytes == record["rawBytes"]
        and actual_hash == record["sha256"]
    )
    return {
        "relativePath": record["relativePath"],
        "exists": exists,
        "expectedRawBytes": record["rawBytes"],
        "actualRawBytes": actual_bytes,
        "expectedSha256": record["sha256"],
        "actualSha256": actual_hash,
        "passed": passed,
    }


def verify_validation_tree(record: dict[str, object]) -> dict[str, object]:
    root = Path(str(record["absolutePath"]))
    rows = []
    tree_digest = hashlib.sha256()
    raw_bytes = 0
    mismatch_count = 0
    expected = {str(row["relativePath"]): row for row in record["files"]}
    actual_paths = sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix())
    actual_names = {p.relative_to(root).as_posix() for p in actual_paths}
    for path in actual_paths:
        rel = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest = sha256(path)
        raw_bytes += size
        tree_digest.update(f"{rel}\t{size}\t{digest}\n".encode("utf-8"))
        exp = expected.get(rel)
        passed = exp is not None and exp["rawBytes"] == size and exp["sha256"] == digest
        if not passed:
            mismatch_count += 1
            if len(rows) < 20:
                rows.append({"relativePath": rel, "actualRawBytes": size, "actualSha256": digest, "expected": exp})
    missing = sorted(set(expected) - actual_names)
    mismatch_count += len(missing)
    return {
        "absolutePath": str(root),
        "expectedFileCount": record["fileCount"],
        "actualFileCount": len(actual_paths),
        "expectedRawBytes": record["rawBytes"],
        "actualRawBytes": raw_bytes,
        "expectedTreeSha256": record["canonicalTreeSha256"],
        "actualTreeSha256": tree_digest.hexdigest(),
        "mismatchCount": mismatch_count,
        "firstMismatches": rows,
        "firstMissing": missing[:20],
        "passed": (
            mismatch_count == 0
            and len(actual_paths) == record["fileCount"]
            and raw_bytes == record["rawBytes"]
            and tree_digest.hexdigest() == record["canonicalTreeSha256"]
        ),
    }


def decode_console(data: bytes) -> str:
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        encoding = locale.getpreferredencoding(False) or "gb18030"
        try:
            return data.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            return data.decode("gb18030")


def ledger_command(command: str) -> tuple[int, dict[str, object], str]:
    completed = subprocess.run(
        [str(PYTHON), str(LEDGER_TOOL), command, "--passport-path", str(PASSPORT)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    stdout = decode_console(completed.stdout)
    stderr = decode_console(completed.stderr)
    parsed = json.loads(stdout) if stdout.strip() else {}
    return completed.returncode, parsed, stderr


def unity_processes() -> list[dict[str, object]]:
    script = (
        "$names=@('Unity.exe','UnityCrashHandler64.exe','UnityShaderCompiler.exe');"
        "$p=Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$names -contains $_.Name} | "
        "Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine;"
        "@($p) | ConvertTo-Json -Depth 4 -Compress"
    )
    completed = subprocess.run(
        [str(POWERSHELL), "-NoProfile", "-NonInteractive", "-Command", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(decode_console(completed.stderr))
    text = decode_console(completed.stdout).strip()
    if not text or text == "null" or text == "[]":
        return []
    value = json.loads(text)
    return value if isinstance(value, list) else [value]


def atomic_create(path: Path, payload: dict[str, object]) -> None:
    if path.exists():
        raise FileExistsError(f"refusing to overwrite versioned audit: {path}")
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    data = (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        with temp.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    artifact_checks = [verify_identity(record) for record in manifest["selectedArtifacts"]]
    tree_check = verify_validation_tree(manifest["validationTree"])

    show_code, show, show_stderr = ledger_command("show")
    report_code, report, report_stderr = ledger_command("report")
    trusted = show.get("trusted_entries", [])
    expected_steps = {
        "mp2-validation-attempt-1": "failed",
        "mp2-validation-attempt-2": "failed",
        "mp2-validation-attempt-3": "failed",
        "mp2-validation-attempt-4": "passed",
        "mp2-evidence-manifest-v1": "failed",
        "mp2-evidence-manifest-v2": "passed",
        "mp2-nonexecuting-readiness": "passed",
    }
    recorded_steps = {
        str(item["step"]): str(item["status"])
        for item in trusted
        if item.get("kind") == "tool_receipt"
    }
    ledger_passed = (
        show_code == 0
        and show.get("ledger_status") == "ok"
        and show.get("entries") == 8
        and recorded_steps == expected_steps
        and report_code == 0
        and report.get("ledger_status") == "ok"
        and not report.get("awaiting_answer")
        and not report.get("cannot_confirm")
        and not report.get("not_run")
        and not report.get("missing")
    )

    processes = unity_processes()
    formal_absence = [{"absolutePath": str(path.resolve()), "exists": path.exists()} for path in FORBIDDEN]
    lock = ROOT / "Temp" / "UnityLockfile"
    plan_text = (RESEARCH / "Overall_Project_Plan.md").read_text(encoding="utf-8")
    checkpoint_text = (RESEARCH / "Next_Session_Checkpoint.md").read_text(encoding="utf-8")
    boundary_passed = (
        not any(item["exists"] for item in formal_absence)
        and not lock.exists()
        and not processes
        and readiness.get("passed") is True
        and readiness["authorizationBoundary"]["formalAttempt3MeasuredCampaignExecuted"] is False
        and readiness["authorizationBoundary"]["formalAttempt3RootCreated"] is False
        and readiness["authorizationBoundary"]["formalAttempt3ExecutionReceiptCreated"] is False
        and readiness["authorizationBoundary"]["formalStatisticalAnalysisExecuted"] is False
        and readiness["authorizationBoundary"]["gate14RExecuted"] is False
        and readiness["nextAction"] == "WAIT-FOR-SEPARATE-GATE13R-PR2-FORMAL-ATTEMPT3-AUTHORIZATION"
        and "formal attempt 3 仍未授权" in plan_text
        and "FORMAL-ATTEMPT3-NOT-AUTHORIZED" in checkpoint_text
        and "下一步必须由用户单独授权 Gate 13R-PR2 formal attempt 3" in checkpoint_text
    )

    schedule = ROOT / readiness["formalDesign"]["schedule"]["relativePath"]
    schedule_manifest = ROOT / readiness["formalDesign"]["scheduleManifest"]["relativePath"]
    schedule_passed = (
        readiness["formalDesign"]["campaignCount"] == 74
        and readiness["formalDesign"]["processCount"] == 3552
        and readiness["formalDesign"]["sampleCount"] == 10176
        and readiness["formalDesign"]["matchedSuperblockCount"] == 1008
        and readiness["formalDesign"]["maximumConcurrentUnityEditors"] == 1
        and sha256(schedule) == readiness["formalDesign"]["schedule"]["sha256"]
        and sha256(schedule_manifest) == readiness["formalDesign"]["scheduleManifest"]["sha256"]
    )

    all_passed = (
        all(check["passed"] for check in artifact_checks)
        and tree_check["passed"]
        and ledger_passed
        and boundary_passed
        and schedule_passed
    )
    now = datetime.now(UTC).replace(microsecond=0)
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "auditId": "gate13r-pr2-mp2-terminal-consistency-audit-v3",
        "savedAtUtc": now.isoformat().replace("+00:00", "Z"),
        "savedAtAsiaShanghai": now.astimezone(timezone(timedelta(hours=8))).isoformat(),
        "passed": all_passed,
        "statusTokens": [
            "GATE13R-PR2-MP2-PASSED" if all_passed else "GATE13R-PR2-MP2-TERMINAL-AUDIT-FAILED",
            "NON-EXECUTING",
            "TERMINAL-AUDIT-ATTEMPTS1-2-FAILED-PRESERVED",
            "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
            "FORMAL-ROOT-ABSENT" if not any(item["exists"] for item in formal_absence) else "FORMAL-TARGET-PRESENT",
            "FORMAL-ANALYSIS-NOT-AUTHORIZED",
            "GATE14R-NOT-AUTHORIZED",
        ],
        "evidenceManifest": file_identity(MANIFEST),
        "readinessCheckpoint": file_identity(READINESS),
        "runPassport": file_identity(PASSPORT),
        "terminalAuditAttempt1FailureReceipt": file_identity(ATTEMPT1_FAILURE),
        "terminalAuditAttempt2FailureReceipt": file_identity(ATTEMPT2_FAILURE),
        "runLedger": {
            **file_identity(LEDGER),
            "showExitCode": show_code,
            "reportExitCode": report_code,
            "showStderr": show_stderr,
            "reportStderr": report_stderr,
            "ledgerStatus": show.get("ledger_status"),
            "entryCount": show.get("entries"),
            "lastEntryHash": trusted[-1]["hash"] if trusted else None,
            "recordedSteps": recorded_steps,
            "expectedSteps": expected_steps,
            "passed": ledger_passed,
        },
        "selectedArtifactVerification": {
            "checked": len(artifact_checks),
            "failed": sum(1 for item in artifact_checks if not item["passed"]),
            "checks": artifact_checks,
            "passed": all(item["passed"] for item in artifact_checks),
        },
        "validationTreeVerification": tree_check,
        "formalDesignVerification": {
            "campaignCount": readiness["formalDesign"]["campaignCount"],
            "processCount": readiness["formalDesign"]["processCount"],
            "sampleCount": readiness["formalDesign"]["sampleCount"],
            "matchedSuperblockCount": readiness["formalDesign"]["matchedSuperblockCount"],
            "maximumConcurrentUnityEditors": readiness["formalDesign"]["maximumConcurrentUnityEditors"],
            "schedule": file_identity(schedule),
            "scheduleManifest": file_identity(schedule_manifest),
            "passed": schedule_passed,
        },
        "authorizationBoundaryVerification": {
            "forbiddenTargets": formal_absence,
            "unityProjectLock": {"absolutePath": str(lock.resolve()), "exists": lock.exists()},
            "unityEditorProcesses": processes,
            "formalAttempt3MeasuredCampaignExecuted": False,
            "formalStatisticalAnalysisExecuted": False,
            "gate14RExecuted": False,
            "passed": boundary_passed,
        },
        "nextAction": "WAIT-FOR-SEPARATE-GATE13R-PR2-FORMAL-ATTEMPT3-AUTHORIZATION",
    }
    atomic_create(TARGET, payload)
    print(json.dumps(file_identity(TARGET), ensure_ascii=False, sort_keys=True))
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
