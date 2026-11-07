#!/usr/bin/env python3
"""Freeze the non-executing Gate13R-AX2 execution package."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from typing import Any, Dict, List, Sequence


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"
COMPILE_SUCCESS_MARKER = "Application will terminate with return code 0"
COMPILE_ERROR = re.compile(r"\berror\s+CS\d+\b|Compilation failed|Scripts have compiler errors", re.IGNORECASE)


class FreezeError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FreezeError(message)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def bind_file(root: pathlib.Path, relative: str) -> Dict[str, Any]:
    path = (root / pathlib.PurePosixPath(relative)).resolve()
    require(path.is_relative_to(root.resolve()), f"Binding escapes project root: {relative}")
    require(path.is_file(), f"Bound file is missing: {relative}")
    return {"path": relative, "sha256": sha256_file(path), "bytes": path.stat().st_size}


def external_binding(path: pathlib.Path) -> Dict[str, Any]:
    resolved = path.resolve()
    require(resolved.is_file(), f"Bound executable is missing: {resolved}")
    return {"path": str(resolved), "sha256": sha256_file(resolved), "bytes": resolved.stat().st_size}


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=pathlib.Path, required=True)
    parser.add_argument("--unity-exe", type=pathlib.Path, required=True)
    parser.add_argument("--python-exe", type=pathlib.Path, required=True)
    parser.add_argument("--powershell-exe", type=pathlib.Path, required=True)
    parser.add_argument("--compile-log", type=pathlib.Path, required=True)
    parser.add_argument("--compile-receipt", type=pathlib.Path, required=True)
    parser.add_argument("--contract", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        root = args.project_root.resolve()
        require(root.is_dir(), f"Project root is missing: {root}")
        compile_log = args.compile_log.resolve()
        require(compile_log.is_file(), f"Unity compile log is missing: {compile_log}")
        compile_bytes = compile_log.read_bytes()
        try:
            compile_text = compile_bytes.decode("utf-8", errors="strict")
            compile_log_encoding = "utf-8"
        except UnicodeDecodeError:
            compile_text = compile_bytes.decode("windows-1252", errors="strict")
            compile_log_encoding = "windows-1252"
        require(COMPILE_SUCCESS_MARKER in compile_text, "Unity compile log does not contain the successful batchmode exit marker.")
        require(COMPILE_ERROR.search(compile_text) is None, "Unity compile log contains a compiler-error marker.")
        runtime_assembly = root / "Library/ScriptAssemblies/Assembly-CSharp.dll"
        editor_assembly = root / "Library/ScriptAssemblies/Assembly-CSharp-Editor.dll"
        require(runtime_assembly.is_file() and editor_assembly.is_file(), "Compiled Unity assemblies are missing.")
        compile_receipt = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-UNITY-COMPILE-RECEIPT",
            "designId": DESIGN_ID,
            "status": "PASS",
            "validatedAtUtc": utc_now(),
            "compileOnly": True,
            "experimentBlockExecuted": False,
            "formalCollectionStarted": False,
            "compileLog": {
                "path": str(compile_log),
                "sha256": sha256_file(compile_log),
                "bytes": compile_log.stat().st_size,
                "decodedAs": compile_log_encoding,
                "successfulExitMarkerFound": True,
                "compilerErrorMarkerFound": False,
            },
            "assemblies": {
                "runtime": external_binding(runtime_assembly),
                "editor": external_binding(editor_assembly),
            },
            "originalGate13RRawOrAnalysisReadOrModified": False,
        }
        compile_receipt_path = args.compile_receipt.resolve()
        write_json_new(compile_receipt_path, compile_receipt)
        package_files = [
            "Assets/_Scripts/Research/Navigation/NavigationContracts.cs",
            "Assets/_Scripts/Research/Experiments/PlanningFairnessContracts.cs",
            "Assets/_Scripts/Research/Experiments/DeterministicPlanningWorkloadRunner.cs",
            "Assets/_Scripts/Research/Algorithms/BidirectionalAStarRepeatedPlanner.cs",
            "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs",
            "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
            "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
            "Assets/_Scripts/Research/Editor/Gate13RAX2BlockRunnerV1.cs",
            "Assets/_Scripts/Research/Editor/Gate13RAX2BlockRunnerV1.cs.meta",
            "Research/Corrected_Full_Recompute_Flow_Field_Specification.md",
            "Research/Incremental_Dynamic_Flow_Field_Specification.md",
            "Research/Gate13R-AX2/README.v1.md",
            "Research/Gate13R-AX2/experiment-plan.v1.md",
            "Research/Gate13R-AX2/Contracts/scientific-contract.v1.md",
            "Research/Gate13R-AX2/Contracts/four-algorithm-extension-fairness.v1.md",
            "Research/Gate13R-AX2/Algorithms/Bidirectional_A_Star_Repeated_Specification.v1.md",
            "Research/Gate13R-AX2/Algorithms/Lifelong_Planning_A_Star_Specification.v1.md",
            "Research/Gate13R-AX2/Analysis/p1-analysis-plan.v1.md",
            "Research/Gate13R-AX2/Analysis/analyze_p1_v1.py",
            "Research/Gate13R-AX2/Execution/v1/formal-williams-schedule.v1.jsonl",
            "Research/Gate13R-AX2/Execution/v1/formal-williams-schedule-manifest.v1.json",
            "Research/Gate13R-AX2/Execution/v1/output-schema.v1.json",
            "Research/Gate13R-AX2/Execution/v1/Run-Gate13RAX2Collection.v1.ps1",
            "Research/Gate13R-AX2/Tools/gate13r_ax2_structural_v1.py",
            "Research/Gate13R-AX2/Tools/gate13r_ax2_raw_commit_v1.py",
        ]
        package_bindings = [bind_file(root, relative) for relative in package_files]
        receipt_bindings = [
            bind_file(root, "Research/Verification/Gate13R-AX2/core-readiness-v1/core-readiness.v1.json"),
            bind_file(root, "Research/Verification/Gate13R-AX2/algorithm-correctness-v1/algorithm-correctness.v1.json"),
            {
                "path": str(compile_receipt_path),
                "sha256": sha256_file(compile_receipt_path),
                "bytes": compile_receipt_path.stat().st_size,
            },
        ]
        contract = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-EXECUTION-CONTRACT",
            "designId": DESIGN_ID,
            "status": "FROZEN-NONEXECUTING",
            "frozenAtUtc": utc_now(),
            "design": {
                "campaignCount": 32,
                "blocksPerCampaign": 48,
                "completeBlockCount": 1536,
                "samplesPerBlock": 4,
                "anonymousSampleCount": 6144,
                "algorithms": ["BiA*-R", "LPA*", "C-FF", "IDFF"],
                "freshUnityProcessPerCompleteBlock": True,
                "strictSerialFourTreatmentWilliamsSchedule": True,
                "maximumWholeBlockTechnicalReplacements": 1,
                "perAlgorithmRetryResumeTopUpMergeSkipReorder": False,
            },
            "executionEntrypoints": {
                "runner": "DDM.Research.Editor.Gate13RAX2BlockRunnerV1.Run",
                "supervisor": "Research/Gate13R-AX2/Execution/v1/Run-Gate13RAX2Collection.v1.ps1",
                "structuralValidator": "Research/Gate13R-AX2/Tools/gate13r_ax2_structural_v1.py",
                "rawCommit": "Research/Gate13R-AX2/Tools/gate13r_ax2_raw_commit_v1.py",
                "p1Analysis": "Research/Gate13R-AX2/Analysis/analyze_p1_v1.py",
            },
            "frozenPackageFiles": package_bindings,
            "verificationReceipts": receipt_bindings,
            "compiledAssemblies": {
                "runtime": external_binding(runtime_assembly),
                "editor": external_binding(editor_assembly),
            },
            "toolchain": {
                "unity": external_binding(args.unity_exe),
                "python": external_binding(args.python_exe),
                "powershell": external_binding(args.powershell_exe),
            },
            "outputBoundary": {
                "formalRootPattern": "Research/FormalRuns/Gate13R-AX2/PhaseA/attempt-NNN",
                "verificationRootPrefix": "Research/Verification/Gate13R-AX2/",
                "originalGate13RRawOrAnalysisMustNotBeReadOrModified": True,
            },
            "formalCollectionAuthorized": False,
            "formalCollectionStarted": False,
        }
        contract_path = args.contract.resolve()
        write_json_new(contract_path, contract)
        print(json.dumps({
            "status": "PASS",
            "compileReceipt": str(compile_receipt_path),
            "compileReceiptSha256": sha256_file(compile_receipt_path),
            "executionContract": str(contract_path),
            "executionContractSha256": sha256_file(contract_path),
            "formalCollectionAuthorized": False,
        }, sort_keys=True))
        return 0
    except (FreezeError, OSError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
