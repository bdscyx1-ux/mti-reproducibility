#!/usr/bin/env python3
"""Versioned enforcement-boundary diagnostics for Gate 13R-PR2 attempt 2.

This is a read-only, non-executing amendment to the frozen v1 diagnostic.  It
separates the first observed native-memory threshold crossing from the final
sample boundary at which the frozen Unity command enforces the block-level
hard gate.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


PROJECT = Path(__file__).resolve().parents[1]
CORE_PATH = Path(__file__).with_name("Analyze-Gate13RPR2Attempt2FailureV1.py")
CORE_SPEC = importlib.util.spec_from_file_location("gate13r_pr2_fd1_v1_core_for_v3", CORE_PATH)
CORE = importlib.util.module_from_spec(CORE_SPEC)
if CORE_SPEC.loader is None:
    raise RuntimeError("Unable to load the frozen v1 diagnostic core")
CORE_SPEC.loader.exec_module(CORE)

EXPECTED_TREE_SHA256 = "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e"
EXPECTED_FILE_COUNT = 28020
EXPECTED_RAW_BYTES = 8536611302
FAILED_BLOCK_ID = "g13rpr2-c52-b0022"
FAILED_BLOCK_RELATIVE = Path("campaigns/c52-grid-scale-g256-shared--shared/blocks/b0022")
STATUS_TOKENS = [
    "NON-EXECUTING",
    "FAILURE-DIAGNOSTIC-ONLY",
    "PARTIAL-FORMAL-ATTEMPT-EXCLUDED-FROM-FORMAL-ANALYSIS",
    "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
    "FORMAL-ANALYSIS-NOT-AUTHORIZED",
    "GATE14R-NOT-AUTHORIZED",
]


def load_json(path: Path) -> Any:
    return CORE.read_json(path)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CORE.DiagnosticError(message)


def extract_enforcement_source_evidence(command_path: Path) -> dict[str, Any]:
    source = command_path.read_text(encoding="utf-8-sig")
    required_fragments = [
        'AddMemoryPolicyFixture(tests, "final-working-above-512-fail"',
        'AddMemoryPolicyFixture(tests, "final-private-above-512-fail"',
        "bool finalSampleInBlock = index == plan.entries.Length - 1;",
        "evaluation.finalSampleInBlock && !evaluation.blockWorkingSetHardLimitPassedAtSampleBoundary",
        "evaluation.finalSampleInBlock && !evaluation.blockPrivateMemoryHardLimitPassedAtSampleBoundary",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in source]
    require(not missing, f"Frozen command no longer proves deferred final-boundary enforcement: {missing}")
    nonfinal_deferred = (
        'AddMemoryPolicyFixture(tests, "nonfinal-block-above-256-deferred"' in source
        and 'AddMemoryPolicyFixture(tests, "nonfinal-working-above-512-deferred"' in source
        and 'AddMemoryPolicyFixture(tests, "nonfinal-private-above-512-deferred"' in source
    )
    require(nonfinal_deferred, "Frozen command is missing non-final deferred-enforcement fixtures")
    return {
        "relativePath": command_path.relative_to(PROJECT).as_posix(),
        "sha256": CORE.sha256_file(command_path),
        "utf8TextSha256": sha256_text(source),
        "requiredSemanticFragmentsPresent": True,
        "nonFinalOverLimitFixturesPresent": True,
        "finalBoundaryConditionPresent": True,
        "interpretation": (
            "Working-set/private-memory limit flags are measured at every sample boundary, "
            "but block-level hard-fail reasons are appended only when finalSampleInBlock is true."
        ),
    }


def load_failed_block_rows(failed_root: Path) -> list[dict[str, Any]]:
    run_root = failed_root / FAILED_BLOCK_RELATIVE / "runs"
    paths = sorted(run_root.glob("p*/memory-gate-evaluation.json"))
    require(len(paths) == 4, f"Expected four failed-block memory evaluations, found {len(paths)}")
    rows: list[dict[str, Any]] = []
    for path in paths:
        item = load_json(path)
        require(item.get("blockId") == FAILED_BLOCK_ID, f"Unexpected block ID in {path}")
        before = item.get("telemetryBeforeSample") or {}
        after = item.get("telemetryAfterCleanup") or {}
        for name in ("workingSetBytes", "privateMemoryBytes", "managedMemoryBytes"):
            CORE.finite_number(before.get(name), f"before.{name}", nonnegative=True)
            CORE.finite_number(after.get(name), f"after.{name}", nonnegative=True)
        row = {
            "relativePath": path.relative_to(failed_root).as_posix(),
            "sha256": CORE.sha256_file(path),
            "runId": item.get("runId"),
            "blockId": item.get("blockId"),
            "campaignId": item.get("campaignId"),
            "scenarioId": item.get("scenarioId"),
            "algorithmId": item.get("algorithmId"),
            "position": int(item.get("position")),
            "predecessorAlgorithmId": item.get("predecessorAlgorithmId"),
            "processId": after.get("processId"),
            "processStartTimeUtc": after.get("processStartTimeUtc"),
            "finalSampleInBlock": bool(item.get("finalSampleInBlock")),
            "blockRetainedManagedGrowthBytes": int(item.get("blockRetainedManagedGrowthBytesAtSampleBoundary")),
            "blockWorkingSetGrowthBytes": int(item.get("blockWorkingSetGrowthBytesAtSampleBoundary")),
            "blockPrivateMemoryGrowthBytes": int(item.get("blockPrivateMemoryGrowthBytesAtSampleBoundary")),
            "blockWorkingSetHardLimitBytes": int(item.get("blockWorkingSetGrowthHardLimitBytes")),
            "blockPrivateMemoryHardLimitBytes": int(item.get("blockPrivateMemoryGrowthHardLimitBytes")),
            "workingSetLimitPassed": bool(item.get("blockWorkingSetHardLimitPassedAtSampleBoundary")),
            "privateMemoryLimitPassed": bool(item.get("blockPrivateMemoryHardLimitPassedAtSampleBoundary")),
            "workingSetAfterCleanupBytes": int(after.get("workingSetBytes")),
            "privateMemoryAfterCleanupBytes": int(after.get("privateMemoryBytes")),
            "managedMemoryAfterCleanupBytes": int(after.get("managedMemoryBytes")),
            "verdict": item.get("verdict"),
            "reasonCode": item.get("reasonCode"),
        }
        rows.append(row)
    rows.sort(key=lambda value: value["position"])
    require([row["position"] for row in rows] == [1, 2, 3, 4], "Failed-block positions are not exactly 1..4")
    identities = {(row["processId"], row["processStartTimeUtc"], row["blockId"]) for row in rows}
    require(len(identities) == 1, "Failed-block composite process identity is inconsistent")
    final_rows = [row for row in rows if row["finalSampleInBlock"]]
    require(len(final_rows) == 1 and final_rows[0]["position"] == 4, "Final sample boundary identity mismatch")
    previous_working: int | None = None
    previous_private: int | None = None
    for row in rows:
        row["nativeThresholdCrossedAtBoundary"] = not row["workingSetLimitPassed"] or not row["privateMemoryLimitPassed"]
        row["hardGateEnforcedAtBoundary"] = row["finalSampleInBlock"] and row["nativeThresholdCrossedAtBoundary"]
        row["incrementalWorkingSetChangeFromPriorBoundaryBytes"] = (
            None if previous_working is None else row["workingSetAfterCleanupBytes"] - previous_working
        )
        row["incrementalPrivateMemoryChangeFromPriorBoundaryBytes"] = (
            None if previous_private is None else row["privateMemoryAfterCleanupBytes"] - previous_private
        )
        previous_working = row["workingSetAfterCleanupBytes"]
        previous_private = row["privateMemoryAfterCleanupBytes"]
    return rows


def make_policy_matrix(v1_matrix: dict[str, Any], rows: list[dict[str, Any]], timestamp: str) -> dict[str, Any]:
    first_crossing = next(row for row in rows if row["nativeThresholdCrossedAtBoundary"])
    final_enforcement = next(row for row in rows if row["hardGateEnforcedAtBoundary"])
    candidates = []
    for source in v1_matrix.get("candidatePolicies", []):
        candidate = dict(source)
        candidate["measurementBoundarySemantics"] = (
            "Native block deltas are observed at every sample boundary; threshold exceedance can precede enforcement."
        )
        candidate["enforcementBoundarySemantics"] = (
            "The frozen command enforces block-level native hard limits only at the final sample boundary."
        )
        candidate["targetedPilotRequired"] = True
        candidate["attempt2DispositionUnaffected"] = True
        candidate["causalSelectionProhibited"] = True
        candidate["status"] = "UNFROZEN / USER-DECISION-REQUIRED"
        candidate["candidateStatus"] = "UNFROZEN / USER-DECISION-REQUIRED"
        candidates.append(candidate)
    return {
        "schemaVersion": 2,
        "resultKind": "gate13r-pr2-attempt2-memory-policy-decision-matrix-v2",
        "generatedAtUtc": timestamp,
        "statusTokens": STATUS_TOKENS,
        "supersedesForProspectiveDecisionOnly": (
            "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-policy-decision-matrix.json"
        ),
        "v1EvidencePreserved": True,
        "failedAttemptDispositionImmutable": True,
        "observedBlockCount": v1_matrix.get("observedBlockCount"),
        "firstObservedNativeThresholdCrossing": {
            "position": first_crossing["position"],
            "algorithmId": first_crossing["algorithmId"],
            "predecessorAlgorithmId": first_crossing["predecessorAlgorithmId"],
            "workingSetGrowthBytes": first_crossing["blockWorkingSetGrowthBytes"],
            "privateMemoryGrowthBytes": first_crossing["blockPrivateMemoryGrowthBytes"],
        },
        "finalHardGateEnforcement": {
            "position": final_enforcement["position"],
            "algorithmId": final_enforcement["algorithmId"],
            "predecessorAlgorithmId": final_enforcement["predecessorAlgorithmId"],
            "reasonCode": final_enforcement["reasonCode"],
        },
        "causalAttribution": {
            "verdict": "NOT-IDENTIFIABLE-FROM-ATTEMPT2-PARTIAL-EVIDENCE",
            "cffIsEnforcementPointNotEstablishedCause": True,
            "firstCrossingAlgorithmIsNotEstablishedCause": True,
            "algorithmPositionPredecessorEffects": "NOT-IDENTIFIABLE",
            "reason": (
                "All four samples share one process; block native growth already exceeded both limits at position 1, "
                "while the command defers the block-level hard-fail verdict until the final boundary."
            ),
        },
        "selectionRule": (
            "No policy may be selected because it would have allowed attempt 2 to continue or because an algorithm "
            "effect direction is favorable. Selection requires prospective instrumentation and a balanced non-formal pilot."
        ),
        "candidatePolicies": candidates,
        "selectionStatus": "MEMORY-POLICY-UNFROZEN / USER-DECISION-REQUIRED",
        "verdict": "TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED",
    }


def analyze(args: argparse.Namespace) -> None:
    project_root = Path(args.project_root).resolve()
    failed_root = Path(args.failed_root).resolve()
    output_root = Path(args.output_root).resolve()
    manifest_path = Path(args.manifest).resolve()
    CORE.ensure_outside(failed_root, output_root)
    require(project_root == PROJECT.resolve(), "Project root does not match analyzer location")
    manifest = load_json(manifest_path)
    require(manifest.get("canonicalTreeSha256") == EXPECTED_TREE_SHA256, "Evidence tree identity mismatch")
    require(manifest.get("fileCount") == EXPECTED_FILE_COUNT, "Evidence file count mismatch")
    require(manifest.get("rawBytes") == EXPECTED_RAW_BYTES, "Evidence raw-byte count mismatch")
    rows = load_failed_block_rows(failed_root)
    command_path = project_root / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV4.cs"
    command_evidence = extract_enforcement_source_evidence(command_path)
    first_crossing = next(row for row in rows if row["nativeThresholdCrossedAtBoundary"])
    final_enforcement = next(row for row in rows if row["hardGateEnforcedAtBoundary"])
    require(first_crossing["position"] == 1, "First observed native threshold crossing is not position 1")
    require(first_crossing["algorithmId"] == "A*-R", "Unexpected first-crossing algorithm identity")
    require(final_enforcement["position"] == 4 and final_enforcement["algorithmId"] == "C-FF", "Unexpected enforcement boundary")
    require(all(row["nativeThresholdCrossedAtBoundary"] for row in rows), "Native limits were not exceeded at every failed-block boundary")

    boundary = {
        "schemaVersion": 2,
        "resultKind": "gate13r-pr2-attempt2-memory-enforcement-boundary-diagnostic-v2",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "attempt2Disposition": "FAILED / EXCLUDED / NO-RETRY / NO-RESUME / NO-TOP-UP / NO-MERGE",
        "blockId": FAILED_BLOCK_ID,
        "compositeProcessIdentity": {
            "processId": rows[0]["processId"],
            "processStartTimeUtc": rows[0]["processStartTimeUtc"],
            "blockId": FAILED_BLOCK_ID,
            "consistentAcrossAllFourEvaluations": True,
        },
        "frozenCommandEvidence": command_evidence,
        "sampleBoundaries": rows,
        "firstObservedNativeThresholdCrossing": {
            "position": first_crossing["position"],
            "runId": first_crossing["runId"],
            "algorithmId": first_crossing["algorithmId"],
            "predecessorAlgorithmId": first_crossing["predecessorAlgorithmId"],
            "blockWorkingSetGrowthBytes": first_crossing["blockWorkingSetGrowthBytes"],
            "blockPrivateMemoryGrowthBytes": first_crossing["blockPrivateMemoryGrowthBytes"],
            "recordedVerdict": first_crossing["verdict"],
            "whyRecordedVerdictRemainedPass": "Non-final block-limit exceedance is measured but enforcement is deferred.",
        },
        "hardGateEnforcementPoint": {
            "position": final_enforcement["position"],
            "runId": final_enforcement["runId"],
            "algorithmId": final_enforcement["algorithmId"],
            "predecessorAlgorithmId": final_enforcement["predecessorAlgorithmId"],
            "reasonCode": final_enforcement["reasonCode"],
            "interpretation": "C-FF is the final enforcement point, not an identified cause of the earlier native-memory crossing.",
        },
        "identifiability": {
            "algorithmCause": "NOT-IDENTIFIABLE",
            "positionEffect": "NOT-IDENTIFIABLE",
            "predecessorEffect": "NOT-IDENTIFIABLE",
            "scenarioScaleResidencyVsRunawayGrowth": "NOT-IDENTIFIABLE",
            "nativeLeak": "NOT-ESTABLISHED",
            "managedLeak": "NOT-SUPPORTED-BY-FAILED-BLOCK-GATE",
        },
        "diagnosticInterpretation": (
            "The dominant native/process-memory increase appeared by the first post-cleanup boundary and then remained "
            "near that plateau through positions 2-4. This pattern is consistent with, but does not prove, scenario/project "
            "residency or first-workload initialization. It cannot identify an algorithm, position, predecessor, or leak cause."
        ),
        "requiredProspectiveInstrumentation": [
            "process-start snapshot",
            "post-project-load pre-scenario snapshot",
            "post-scenario-load pre-first-sample snapshot",
            "before/raw-after/after-cleanup snapshot for every sample",
            "post-block snapshot",
            "absolute working-set/private-memory and all stage deltas",
            "PID + processStartTimeUtc + blockId composite identity",
        ],
        "requiredBalancedPilot": {
            "status": "TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED",
            "focus": "g256 plus lower-scale controls",
            "design": "fresh process per complete block; rotate algorithms across Williams positions/predecessors; balanced rows",
            "formalUse": "EXCLUDED-FROM-FORMAL-ANALYSIS",
        },
    }

    v1_matrix = load_json(project_root / "Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-policy-decision-matrix.json")
    matrix = make_policy_matrix(v1_matrix, rows, args.timestamp)
    amendment = {
        "schemaVersion": 2,
        "amendmentKind": "gate13r-pr2-attempt2-memory-enforcement-boundary-amendment-v2",
        "createdAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "scope": "Non-executing diagnostic interpretation only; no frozen execution artifact is modified.",
        "preservedV1Analysis": True,
        "correction": (
            "The v1 report correctly identified the durable memory hard-fail record but did not distinguish first measured "
            "threshold crossing from final-sample enforcement. V2 adds that distinction and prohibits algorithm attribution."
        ),
        "attempt2DispositionChanged": False,
        "memoryPolicyChanged": False,
        "formalAttempt3Authorized": False,
        "unityInvocationAuthorized": False,
    }

    outputs: dict[str, Any] = {
        "memory-enforcement-boundary-diagnostic.json": boundary,
        "memory-policy-decision-matrix.json": matrix,
        "memory-enforcement-boundary-amendment.json": amendment,
    }
    for name, value in outputs.items():
        CORE.atomic_write_json(output_root / name, value)
    report = f"""# Gate 13R-PR2 attempt 2 enforcement-boundary diagnostic v2

Status: `{' / '.join(STATUS_TOKENS)}`

## Corrected interpretation

- The failed block crossed both 512 MiB native block-delta limits at position 1 (`A*-R`, predecessor `NONE`): working set {first_crossing['blockWorkingSetGrowthBytes']:,} bytes; private memory {first_crossing['blockPrivateMemoryGrowthBytes']:,} bytes.
- The frozen command measured those failed flags at every boundary but enforced block-level failure only when `finalSampleInBlock = true`.
- Position 4 (`C-FF`, predecessor `IDFF`) is therefore the durable enforcement point, not an identified cause of the increase.
- Algorithm, position, predecessor, expected scenario residency, and native leak causality are all **not identifiable** from this one partial block.
- Attempt 2 remains failed and excluded. No threshold is changed, no Unity process is launched, and no formal analysis is performed.

## Required next evidence

A new, balanced, non-formal memory pilot is required before selecting a prospective policy. It must split process/project/scenario-load residency from per-sample deltas, rotate all four algorithms across Williams positions, use one fresh Unity process per complete block, include g256 and lower-scale controls, and remain excluded from formal inference.
"""
    CORE.atomic_write_text(output_root / "diagnostic-report.md", report)
    evidence_files = sorted(path for path in output_root.iterdir() if path.is_file() and path.name != "evidence-manifest.json")
    evidence = {
        "schemaVersion": 2,
        "manifestKind": "gate13r-pr2-attempt2-enforcement-boundary-diagnostic-evidence-manifest-v2",
        "generatedAtUtc": args.timestamp,
        "statusTokens": STATUS_TOKENS,
        "files": [
            {"relativePath": path.name, "bytes": path.stat().st_size, "sha256": CORE.sha256_file(path)}
            for path in evidence_files
        ],
    }
    CORE.atomic_write_json(output_root / "evidence-manifest.json", evidence)
    print(json.dumps({
        "passed": True,
        "firstCrossingPosition": first_crossing["position"],
        "firstCrossingAlgorithm": first_crossing["algorithmId"],
        "enforcementPosition": final_enforcement["position"],
        "enforcementAlgorithm": final_enforcement["algorithmId"],
        "causalAttribution": "NOT-IDENTIFIABLE",
        "verdict": "TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED",
        "outputRoot": str(output_root),
    }, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--failed-root", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--timestamp", required=True)
    analyze(parser.parse_args())


if __name__ == "__main__":
    main()
