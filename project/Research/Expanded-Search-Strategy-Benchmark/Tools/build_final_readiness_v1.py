#!/usr/bin/env python3
"""Build the final non-executing Gate13R-AX2 precollection readiness receipt."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import stat
import sys
from typing import Any, Dict, Iterable, List, Mapping, Sequence


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"


class ReadinessError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReadinessError(message)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: pathlib.Path) -> Any:
    require(path.is_file(), f"Required JSON is missing: {path}")
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ReadinessError(f"Invalid JSON at {path}: {exc}") from exc


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def write_text_new(path: pathlib.Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(value)


def relative_binding(root: pathlib.Path, relative: str) -> Dict[str, Any]:
    path = (root / pathlib.PurePosixPath(relative)).resolve()
    require(path.is_relative_to(root.resolve()) and path.is_file(), f"Bound readiness evidence is missing/unsafe: {relative}")
    return {"path": relative, "sha256": sha256_file(path), "bytes": path.stat().st_size}


def resolve_contract_binding(root: pathlib.Path, value: Mapping[str, Any]) -> pathlib.Path:
    raw_path = pathlib.Path(value["path"])
    path = raw_path.resolve() if raw_path.is_absolute() else (root / pathlib.PurePosixPath(value["path"])).resolve()
    require(path.is_file(), f"Contract-bound file is missing: {path}")
    require(sha256_file(path) == value["sha256"], f"Contract-bound file drift: {path}")
    require(path.stat().st_size == value["bytes"], f"Contract-bound byte-count drift: {path}")
    return path


def read_only_file_count(root: pathlib.Path) -> tuple[int, int]:
    files = [path for path in root.rglob("*") if path.is_file()]
    read_only = [path for path in files if not (path.stat().st_mode & stat.S_IWRITE)]
    return len(files), len(read_only)


def verify_contract(root: pathlib.Path, path: pathlib.Path, expected_sha256: str) -> Dict[str, Any]:
    require(path.is_file(), f"Execution contract is missing: {path}")
    actual = sha256_file(path)
    require(actual == expected_sha256, f"Execution contract SHA-256 mismatch: {actual}")
    contract = load_json(path)
    require(contract.get("designId") == DESIGN_ID and contract.get("status") == "FROZEN-NONEXECUTING", "Execution contract identity/status mismatch.")
    require(contract.get("formalCollectionAuthorized") is False and contract.get("formalCollectionStarted") is False, "Execution contract incorrectly claims formal authorization/execution.")
    files = contract.get("frozenPackageFiles")
    require(isinstance(files, list) and len(files) >= 20, "Execution contract package binding list is incomplete.")
    for binding in files:
        resolve_contract_binding(root, binding)
    for binding in contract.get("verificationReceipts", []):
        resolve_contract_binding(root, binding)
    for binding in contract.get("compiledAssemblies", {}).values():
        resolve_contract_binding(root, binding)
    for binding in contract.get("toolchain", {}).values():
        resolve_contract_binding(root, binding)
    design = contract.get("design", {})
    require(design.get("campaignCount") == 32 and design.get("blocksPerCampaign") == 48 and design.get("completeBlockCount") == 1536 and design.get("anonymousSampleCount") == 6144, "Execution contract design cardinality mismatch.")
    require(design.get("freshUnityProcessPerCompleteBlock") is True and design.get("strictSerialFourTreatmentWilliamsSchedule") is True, "Execution contract fresh-process/Williams invariant mismatch.")
    require(design.get("perAlgorithmRetryResumeTopUpMergeSkipReorder") is False, "Execution contract permits a forbidden per-algorithm action.")
    return {
        "path": str(path),
        "sha256": actual,
        "frozenPackageFileCount": len(files),
        "allFrozenPackageHashesMatch": True,
        "formalCollectionAuthorized": False,
    }


def verify_positive_smoke(root: pathlib.Path, contract_sha256: str) -> Dict[str, Any]:
    acquisition = load_json(root / "_control" / "acquisition-complete.v1.json")
    status = load_json(root / "_control" / "execution-status.json")
    launch = load_json(root / "_control" / "launch-receipt.v1.json")
    raw = load_json(root / "_commit" / "raw-complete-receipt.v1.json")
    require(acquisition.get("status") == "VERIFICATION-ACQUISITION-COMPLETE" and status.get("status") == "VERIFICATION-RAW-COMMIT-PENDING", "Positive smoke did not reach the expected acquisition/raw-commit boundary.")
    require(acquisition.get("acceptedBlocks") == 1 and acquisition.get("acceptedAnonymousSamples") == 4, "Positive smoke cardinality mismatch.")
    require(acquisition.get("launchedProcesses") == 1 and acquisition.get("wholeBlockReplacements") == 0, "Positive smoke process/replacement ledger mismatch.")
    require(launch.get("executionContract", {}).get("sha256") == contract_sha256, "Positive smoke execution-contract binding mismatch.")
    require(raw.get("status") == "VERIFICATION-RAW-COMPLETE" and raw.get("collection", {}).get("completeBlocks") == 1, "Positive smoke raw commit is incomplete.")
    require(raw.get("collection", {}).get("anonymousSamples") == 4 and raw.get("p1AggregatedOrInterpreted") is False, "Positive smoke raw-commit scope mismatch.")
    total_files, read_only_files = read_only_file_count(root)
    require(total_files == read_only_files and total_files > 0, "Positive smoke raw root is not fully read-only.")
    return {
        "root": str(root),
        "acceptedBlocks": 1,
        "anonymousSamples": 4,
        "freshProcesses": 1,
        "wholeBlockReplacements": 0,
        "rawCompleteReceiptSha256": sha256_file(root / "_commit" / "raw-complete-receipt.v1.json"),
        "manifestFileCount": raw["manifest"]["fileCount"],
        "readOnlyFileCount": read_only_files,
        "p1AggregatedOrInterpreted": False,
        "passed": True,
    }


def verify_memory(root: pathlib.Path, contract_sha256: str) -> Dict[str, Any]:
    acquisition = load_json(root / "_control" / "acquisition-complete.v1.json")
    launch = load_json(root / "_control" / "launch-receipt.v1.json")
    receipts = sorted((root / "_control" / "process-receipts").glob("*.v1.json"))
    require(len(receipts) == 1, "Memory test must have exactly one process receipt.")
    process = load_json(receipts[0])
    require(acquisition.get("status") == "VERIFICATION-ACQUISITION-COMPLETE" and acquisition.get("acceptedBlocks") == 1 and acquisition.get("acceptedAnonymousSamples") == 4, "Memory test acquisition did not complete one full block.")
    require(launch.get("selectedBlockIds") == ["g13rax2-c20-b0001"], "Memory test did not select the frozen g256 block.")
    require(launch.get("executionContract", {}).get("sha256") == contract_sha256, "Memory test execution-contract binding mismatch.")
    require(process.get("exitCode") == 0 and process.get("timedOut") is False and process.get("structuralValidationPassed") is True and process.get("accepted") is True, "Memory test process did not finish and validate.")
    peak_working = process.get("peakWorkingSetBytes")
    peak_private = process.get("peakPrivateMemoryBytes")
    require(isinstance(peak_working, int) and peak_working > 0 and isinstance(peak_private, int) and peak_private > 0, "Memory test peak observations are missing.")
    return {
        "root": str(root),
        "blockId": "g13rax2-c20-b0001",
        "scenarioClass": "grid-scale-g256",
        "acceptedBlocks": 1,
        "anonymousSamples": 4,
        "freshProcesses": 1,
        "wholeBlockReplacements": acquisition.get("wholeBlockReplacements"),
        "peakWorkingSetBytes": peak_working,
        "peakPrivateMemoryBytes": peak_private,
        "timedOut": False,
        "structuralValidationPassed": True,
        "postHocHardMemoryThresholdApplied": False,
        "interpretation": "Observed completion evidence only; not a universal resource guarantee.",
        "passed": True,
    }


def verify_status_receipt(path: pathlib.Path, artifact_kind: str) -> Dict[str, Any]:
    value = load_json(path)
    require(value.get("artifactKind") == artifact_kind and value.get("designId") == DESIGN_ID and value.get("status") == "PASS", f"Receipt did not pass: {path}")
    return {"path": str(path), "sha256": sha256_file(path), "passed": True}


def render_report(receipt: Mapping[str, Any]) -> str:
    memory = receipt["tests"]["memoryG256"]
    return "\n".join([
        "# Gate13R-AX2 non-executing precollection readiness",
        "",
        f"Status: **{receipt['status']}**",
        "",
        "## Frozen design",
        "",
        "- 32 shared-goal campaigns",
        "- B=48 complete blocks per campaign",
        "- four-treatment Williams schedule",
        "- 1,536 complete blocks and 6,144 anonymous samples",
        "- treatments: BiA*-R, LPA*, C-FF, IDFF",
        "- one fresh Unity process per complete four-treatment block",
        "",
        "## Verification evidence",
        "",
        "- Unity compile: PASS",
        "- algorithm correctness: PASS (962 assertions)",
        "- full schedule/schema/hash validation: PASS",
        "- positive block smoke plus independent raw commit/read-only freeze: PASS",
        f"- g256 memory path: PASS; observed peak working set {memory['peakWorkingSetBytes']} bytes and peak private memory {memory['peakPrivateMemoryBytes']} bytes",
        "- injected partial-block failure and raw-commit rejection: PASS",
        "- formal authorization guard: PASS; no formal root or Unity process was created by the guard test",
        "- P1 analysis implementation selftest: PASS; no formal data analyzed and no winner declared",
        "",
        "## Scope boundary",
        "",
        "No formal Gate13R-AX2 collection was started. No original Gate 13R raw or analysis result was read or modified. Verification samples are non-formal and cannot be merged into a future formal attempt.",
        "",
        "A separate single-attempt formal authorization remains required.",
        "",
    ])


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=pathlib.Path, required=True)
    parser.add_argument("--contract", type=pathlib.Path, required=True)
    parser.add_argument("--contract-sha256", required=True)
    parser.add_argument("--positive-root", type=pathlib.Path, required=True)
    parser.add_argument("--memory-root", type=pathlib.Path, required=True)
    parser.add_argument("--expected-failure-receipt", type=pathlib.Path, required=True)
    parser.add_argument("--authorization-guard-receipt", type=pathlib.Path, required=True)
    parser.add_argument("--structural-selftest", type=pathlib.Path, required=True)
    parser.add_argument("--schedule-validation", type=pathlib.Path, required=True)
    parser.add_argument("--analysis-selftest", type=pathlib.Path, required=True)
    parser.add_argument("--compile-receipt", type=pathlib.Path, required=True)
    parser.add_argument("--core-readiness", type=pathlib.Path, required=True)
    parser.add_argument("--algorithm-correctness", type=pathlib.Path, required=True)
    parser.add_argument("--receipt", type=pathlib.Path, required=True)
    parser.add_argument("--report", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        root = args.project_root.resolve()
        require(root.is_dir(), f"Project root is missing: {root}")
        contract_sha = args.contract_sha256.lower()
        contract = verify_contract(root, args.contract.resolve(), contract_sha)
        core_value = load_json(args.core_readiness.resolve())
        correctness_value = load_json(args.algorithm_correctness.resolve())
        require(core_value.get("status") == "CORE-READINESS-PASS" and core_value.get("formalCollectionAuthorized") is False, "Core readiness did not pass or incorrectly authorizes formal collection.")
        require(correctness_value.get("passed") is True and correctness_value.get("assertionCount") == 962, "Algorithm correctness receipt mismatch.")
        compile_receipt = verify_status_receipt(args.compile_receipt.resolve(), "GATE13R-AX2-UNITY-COMPILE-RECEIPT")
        structural_selftest = verify_status_receipt(args.structural_selftest.resolve(), "GATE13R-AX2-STRUCTURAL-SELFTEST")
        schedule_validation = verify_status_receipt(args.schedule_validation.resolve(), "GATE13R-AX2-STRUCTURAL-SCHEDULE-VALIDATION")
        analysis_selftest = verify_status_receipt(args.analysis_selftest.resolve(), "GATE13R-AX2-P1-ANALYSIS-SELFTEST")
        expected_failure = verify_status_receipt(args.expected_failure_receipt.resolve(), "GATE13R-AX2-EXPECTED-FAILURE-TEST")
        expected_failure_value = load_json(args.expected_failure_receipt.resolve())
        require(expected_failure_value.get("test", {}).get("supervisorExitCode") == 2 and expected_failure_value.get("test", {}).get("rawCommitRejectionExitCode") == 2, "Expected-failure test exit-code evidence mismatch.")
        require(expected_failure_value.get("test", {}).get("acceptedBlocks") == 0 and expected_failure_value.get("test", {}).get("rawCommitDirectoryAbsent") is True, "Expected-failure test accepted or committed a partial block.")
        authorization_guard = verify_status_receipt(args.authorization_guard_receipt.resolve(), "GATE13R-AX2-FORMAL-AUTHORIZATION-GUARD-TEST")
        authorization_guard_value = load_json(args.authorization_guard_receipt.resolve())
        require(authorization_guard_value.get("supervisorExitCode") == 2 and authorization_guard_value.get("formalRootCreated") is False and authorization_guard_value.get("unityProcessLaunched") is False, "Formal authorization guard evidence mismatch.")
        positive = verify_positive_smoke(args.positive_root.resolve(), contract_sha)
        memory = verify_memory(args.memory_root.resolve(), contract_sha)
        formal_root = root / "Research/FormalRuns/Gate13R-AX2"
        formal_launch_receipts = list(formal_root.rglob("launch-receipt*.json")) if formal_root.exists() else []
        require(not formal_launch_receipts, "A Gate13R-AX2 formal launch receipt exists; readiness must remain non-executing.")
        superseded = []
        for relative in (
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/smoke-positive/_control/failure-receipt.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/expected-failure/_control/failure-receipt.v1.json",
        ):
            path = root / pathlib.PurePosixPath(relative)
            if path.is_file():
                superseded.append({"path": relative, "sha256": sha256_file(path), "excludedFromReadinessEvidence": True, "sampleReuseAuthorized": False})
        receipt = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-FINAL-PRECOLLECTION-READINESS",
            "designId": DESIGN_ID,
            "status": "FINAL-READINESS-PASS",
            "completedAtUtc": utc_now(),
            "design": {
                "campaignCount": 32,
                "blocksPerCampaign": 48,
                "completeBlockCount": 1536,
                "anonymousSampleCount": 6144,
                "algorithms": ["BiA*-R", "LPA*", "C-FF", "IDFF"],
                "schedule": "four-treatment Williams",
                "freshUnityProcessPerCompleteBlock": True,
            },
            "frozenExecutionContract": contract,
            "evidence": {
                "coreReadiness": {"path": str(args.core_readiness.resolve()), "sha256": sha256_file(args.core_readiness.resolve()), "status": core_value["status"]},
                "algorithmCorrectness": {"path": str(args.algorithm_correctness.resolve()), "sha256": sha256_file(args.algorithm_correctness.resolve()), "assertionCount": correctness_value["assertionCount"], "status": "PASS"},
                "compile": compile_receipt,
                "structuralSelftest": structural_selftest,
                "scheduleValidation": schedule_validation,
                "p1AnalysisSelftest": analysis_selftest,
                "expectedFailureAndRawCommitRejection": expected_failure,
                "formalAuthorizationGuard": authorization_guard,
            },
            "tests": {
                "positiveSmokeAndRawCommit": positive,
                "memoryG256": memory,
                "expectedFailure": expected_failure_value["test"],
                "formalAuthorizationGuard": {
                    "supervisorExitCode": authorization_guard_value["supervisorExitCode"],
                    "missingAuthorizationRejected": authorization_guard_value["missingAuthorizationRejected"],
                    "formalRootCreated": authorization_guard_value["formalRootCreated"],
                    "unityProcessLaunched": authorization_guard_value["unityProcessLaunched"],
                },
            },
            "supersededVerificationAttempts": superseded,
            "scopeAttestation": {
                "formalCollectionStarted": False,
                "formalLaunchReceiptCount": 0,
                "originalGate13RRawOrAnalysisReadOrModified": False,
                "verificationSamplesAreNonFormal": True,
                "verificationSamplesMayBeMergedIntoFormalAttempt": False,
                "p1FormalAnalysisExecuted": False,
                "winnerDeclared": False,
            },
            "authorizationState": {
                "formalCollectionAuthorized": False,
                "singleAttemptFormalAuthorizationPromptMayNowBeGenerated": True,
                "formalCollectionMayNotStartWithoutSeparateUserAuthorization": True,
            },
        }
        write_json_new(args.receipt.resolve(), receipt)
        write_text_new(args.report.resolve(), render_report(receipt))
        print(json.dumps({
            "status": receipt["status"],
            "receipt": str(args.receipt.resolve()),
            "receiptSha256": sha256_file(args.receipt.resolve()),
            "report": str(args.report.resolve()),
            "reportSha256": sha256_file(args.report.resolve()),
            "formalCollectionStarted": False,
            "formalCollectionAuthorized": False,
        }, sort_keys=True))
        return 0
    except (ReadinessError, OSError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
