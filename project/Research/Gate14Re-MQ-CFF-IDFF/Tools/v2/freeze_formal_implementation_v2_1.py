#!/usr/bin/env python3
"""Create the immutable Gate14Re MQ formal-v2.3 implementation manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ARTIFACTS = [
    ("formal-runner-source", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalRunnerV2.cs"),
    ("formal-runner-meta", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalRunnerV2.cs.meta"),
    ("formal-readiness-source", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalReadinessV2.cs"),
    ("formal-readiness-meta", "Assets/_Scripts/Research/Editor/Gate14ReMQFormalReadinessV2.cs.meta"),
    ("algorithm-free-compile-guard", "Assets/_Scripts/Research/Editor/Gate14ReMQCompileExitV2.cs"),
    ("algorithm-free-compile-guard-meta", "Assets/_Scripts/Research/Editor/Gate14ReMQCompileExitV2.cs.meta"),
    ("formal-performance-kernel-source", "Assets/_Scripts/Research/MQ/v2/Gate14ReMQFormalPerformanceKernelV2.cs"),
    ("formal-performance-kernel-meta", "Assets/_Scripts/Research/MQ/v2/Gate14ReMQFormalPerformanceKernelV2.cs.meta"),
    ("collection-supervisor", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_1.ps1"),
    ("superseded-collection-supervisor", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/Run-Gate14ReMQFormalCollection.v2_0.ps1"),
    ("schedule-generator", "Research/Gate14Re-MQ-CFF-IDFF/Tools/v2/generate_formal_schedule_v2.py"),
    ("implementation-freezer", "Research/Gate14Re-MQ-CFF-IDFF/Tools/v2/freeze_formal_implementation_v2_1.py"),
    ("independent-freeze-validator", "Research/Gate14Re-MQ-CFF-IDFF/Tools/v2/validate_formal_freeze_v2_1.py"),
    ("finalization-tool", "Research/Gate14Re-MQ-CFF-IDFF/Tools/v2/finalize_formal_readiness_v2_1.py"),
    ("formal-schedule", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule.v2.jsonl"),
    ("formal-schedule-summary", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/formal-process-schedule-summary.v2.json"),
    ("formal-block-input-assignments", "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-block-input-assignments.v2.jsonl"),
    ("formal-input-source-manifest", "Research/Gate14Re-MQ-CFF-IDFF/FormalInputs/v2/formal-input-source-manifest.v2.json"),
    ("opaque-algorithm-identity-map", "Research/Gate14Re-MQ-CFF-IDFF/Execution/v2/opaque-algorithm-identity-map.v2.json"),
    ("scientific-and-analysis-contract", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-scientific-and-analysis-contract.v2.json"),
    ("execution-contract", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-execution-contract.v2.json"),
    ("fairness-and-topology-binding", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/fairness-and-topology-binding.v2.json"),
    ("resource-budget", "Research/Gate14Re-MQ-CFF-IDFF/Design/v2/formal-mq-resource-budget.v2.json"),
    ("authorized-design-rules", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/formal-mq-authorized-design.v2.json"),
    ("authorized-design-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-design-rule-freeze-v2-attempt-001/terminal-receipt.v2.json"),
    ("power-result", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-result.v2.json"),
    ("power-selection-seal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/power-selection-seal-receipt.v2.json"),
    ("power-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/identity-blind-power-v2-attempt-001/terminal-receipt.v2.json"),
    ("runtime-diagnostics", "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-runtime-analysis-v2/engineering-runtime-diagnostics.v2.json"),
    ("engineering-affinity-plans", "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/affinity-plans.v1.json"),
    ("engineering-topology-snapshot", "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/topology-snapshot.v1.json"),
    ("engineering-semantic-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/terminal-receipt.v1.json"),
    ("engineering-semantic-external-freeze", "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/external-freeze-receipt.v1.json"),
    ("engineering-performance-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/terminal-receipt.v1.json"),
    ("engineering-performance-external-freeze", "Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/external-freeze-receipt.v1.json"),
    ("managed-multi-query-executor", "Assets/_Scripts/Research/MQ/v1/ManagedMultiQueryExecutorV1.cs"),
    ("qualified-performance-kernel", "Assets/_Scripts/Research/MQ/v1/Gate14ReMQPerformanceKernelV1.cs"),
    ("qualified-semantic-kernel", "Assets/_Scripts/Research/MQ/v1/Gate14ReMQInputKernelV1.cs"),
    ("corrected-full-recompute-flow-field", "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs"),
    ("incremental-dynamic-flow-field", "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs"),
    ("research-navigation-grid", "Assets/_Scripts/Research/Grid/ResearchNavigationGrid.cs"),
    ("navigation-contracts", "Assets/_Scripts/Research/Navigation/NavigationContracts.cs"),
    ("qualification-contracts", "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs"),
    ("algorithm-neutral-reference-oracle", "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs"),
    ("failed-collection-attempt-001-terminal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/terminal-receipt.v2.json"),
    ("failed-collection-attempt-001-failure", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/failure-receipt.v2.json"),
    ("failed-collection-attempt-001-seal", "Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-collection-execution-attempt-001/failure-seal-manifest.v2.json"),
    ("repair-user-authorization", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-control-corrigendum-v2_1-attempt-001/user-authorization-receipt.v2_1.json"),
    ("supervisor-control-fix-receipt", "Research/Verification/Gate14Re-MQ-CFF-IDFF/supervisor-control-corrigendum-v2_1-attempt-001/supervisor-control-fix-receipt.v2_1.json"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--created-at-utc")
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    if output.exists():
        raise RuntimeError(f"Refusing to overwrite implementation manifest: {output}")
    if not output.parent.is_dir():
        raise RuntimeError(f"Output parent is missing: {output.parent}")
    try:
        output.relative_to(root)
    except ValueError as exc:
        raise RuntimeError("Output escapes project root") from exc

    rows = []
    seen: set[str] = set()
    for role, relative in ARTIFACTS:
        if relative in seen:
            raise RuntimeError(f"Duplicate artifact path: {relative}")
        seen.add(relative)
        path = (root / relative).resolve()
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise RuntimeError(f"Artifact escapes project root: {relative}") from exc
        if not path.is_file():
            raise RuntimeError(f"Artifact is missing: {relative}")
        rows.append({"role": role, "relativePath": relative, "bytes": path.stat().st_size, "sha256": sha256(path)})

    created = args.created_at_utc or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    manifest = {
        "schema": "gate14re-mq-formal-implementation-manifest-v2",
        "studyId": "Gate14Re-MQ-CFF-IDFF",
        "designId": "gate14re-mq-cff-idff-formal-v2",
        "status": "FROZEN_IMPLEMENTATION_AND_SCHEDULE_READY_FOR_SEPARATE_LAUNCH_AUTHORIZATION",
        "implementationRevision": "v2.3",
        "collectionSupervisorRevision": "v2.1",
        "artifactCount": len(rows),
        "artifacts": rows,
        "executionBoundary": {
            "formalCollectionAuthorized": False,
            "formalAnalysisAuthorized": False,
            "separateLaunchAuthorizationRequired": True,
            "readinessIsAlgorithmFree": True,
        },
        "prospectiveRepair": {
            "scope": "supervisor-empty-set-count-only",
            "changedCallSites": 3,
            "scientificDesignChanged": False,
            "scheduleChanged": False,
            "formalCollectionAttempt002Authorized": False,
        },
        "createdAtUtc": created,
    }
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"status": manifest["status"], "artifacts": len(rows), "output": str(output), "sha256": sha256(output)}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
