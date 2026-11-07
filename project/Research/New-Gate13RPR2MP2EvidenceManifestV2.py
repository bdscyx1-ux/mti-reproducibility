#!/usr/bin/env python3
"""Create the terminal evidence manifest for Gate 13R-PR2-MP2.

This is a non-executing archival step.  It hashes the versioned MP2 artifacts
and the complete validation root, proves the forbidden formal-attempt-3 paths
are absent, and never invokes Unity or any experiment runner.
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "Research"
VERIFY_ROOT = RESEARCH / "Verification" / "Gate13R_PR2_MP2" / "v1"
TARGET = RESEARCH / "Gate13R_PR2_MP2_Evidence_Manifest.v2.json"
POST_AUDIT = VERIFY_ROOT / "attempt-4" / "post-validation-frozen-input-audit.json"

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


def entry(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "relativePath": path.relative_to(ROOT).as_posix(),
        "rawBytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def tree(root: Path) -> dict[str, object]:
    files = sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix())
    rows: list[dict[str, object]] = []
    tree_digest = hashlib.sha256()
    raw_bytes = 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest = sha256(path)
        raw_bytes += size
        rows.append({"relativePath": rel, "rawBytes": size, "sha256": digest})
        tree_digest.update(f"{rel}\t{size}\t{digest}\n".encode("utf-8"))
    return {
        "absolutePath": str(root.resolve()),
        "treeContract": "relative-path-tab-raw-bytes-tab-sha256-final-lf-v1",
        "fileCount": len(rows),
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": tree_digest.hexdigest(),
        "files": rows,
    }


def selected_artifacts() -> list[Path]:
    selected: set[Path] = set()
    name_prefixes = (
        "Gate13R_PR2_MP2_",
        "Gate13RPR2MP2",
        "Run-Gate13RPR2MP2",
        "New-Gate13RPR2MP2",
        "Test-Gate13RPR2MP2",
        "Finalize-Gate13RPR2MP2",
    )
    for path in RESEARCH.iterdir():
        if not path.is_file() or path == TARGET or path.name.endswith(".lock"):
            continue
        if path.name == "Gate13R_PR2_MP2_Run_Passport_run_ledger.yaml":
            # The final ledger entry binds this manifest, so the ledger is
            # intentionally bound later by the terminal consistency audit.
            continue
        if path.name.startswith(name_prefixes):
            selected.add(path)

    selected.update(
        {
            ROOT / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs",
            RESEARCH / "Verification/Run-Gate13RPR2MP2MemoryPolicySelfTestV1.ps1",
            RESEARCH / "Verification/Run-Gate13RPR2MP2TelemetryProbeV1.ps1",
            RESEARCH / "Verification/Freeze-Gate13RPR2MP2ValidationAttemptV1.ps1",
            RESEARCH / "Gate13R_PR2_Attempt3_Next_Authorization_Prompt.md",
            RESEARCH / "Overall_Project_Plan.md",
            RESEARCH / "Next_Session_Checkpoint.md",
        }
    )
    return sorted(selected, key=lambda p: p.relative_to(ROOT).as_posix())


def atomic_create(path: Path, payload: dict[str, object]) -> None:
    if path.exists():
        raise FileExistsError(f"refusing to overwrite versioned manifest: {path}")
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        with tmp.open("xb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def main() -> int:
    if not VERIFY_ROOT.is_dir():
        raise FileNotFoundError(VERIFY_ROOT)
    if any(path.exists() for path in FORBIDDEN):
        present = [str(path) for path in FORBIDDEN if path.exists()]
        raise RuntimeError(f"forbidden formal-attempt-3 target exists: {present}")

    post_audit = json.loads(POST_AUDIT.read_text(encoding="utf-8"))
    if not post_audit.get("passed"):
        raise RuntimeError("post-validation frozen-input audit is not passed")

    now_utc = datetime.now(UTC).replace(microsecond=0)
    shanghai = timezone(timedelta(hours=8))
    artifacts = selected_artifacts()
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "manifestId": "gate13r-pr2-mp2-evidence-manifest-v2",
        "savedAtUtc": now_utc.isoformat().replace("+00:00", "Z"),
        "savedAtAsiaShanghai": now_utc.astimezone(shanghai).isoformat(),
        "statusTokens": [
            "NON-EXECUTING",
            "VALIDATION-ONLY-PASSED",
            "FAILED-ATTEMPTS-PRESERVED",
            "EVIDENCE-MANIFEST-V1-FAILED-PRESERVED",
            "FORMAL-ATTEMPT3-NOT-AUTHORIZED",
            "FORMAL-ROOT-ABSENT",
            "FORMAL-RECEIPT-ABSENT",
            "FORMAL-ANALYSIS-NOT-AUTHORIZED",
            "GATE14R-NOT-AUTHORIZED",
        ],
        "authorizationBoundary": {
            "formalAttempt3MeasuredCampaignExecuted": False,
            "formalAttempt3RootCreated": False,
            "formalAttempt3ExecutionReceiptCreated": False,
            "formalAttempt3StatusCreated": False,
            "formalStatisticalAnalysisExecuted": False,
            "gate14RExecuted": False,
        },
        "formalAttempt3ForbiddenTargets": [
            {"absolutePath": str(path.resolve()), "exists": path.exists()} for path in FORBIDDEN
        ],
        "activeCandidate": {
            "config": entry(RESEARCH / "Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json"),
            "adapter": entry(RESEARCH / "Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json"),
            "provenance": entry(RESEARCH / "Gate13R_PR2_MP2_Provenance.v4.json"),
            "memoryPolicyRegistry": entry(RESEARCH / "Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"),
            "scenarioPolicyMapping": entry(RESEARCH / "Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"),
            "schedulePolicyOverlay": entry(RESEARCH / "Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"),
            "wrapper": entry(RESEARCH / "Run-Gate13RPR2MP2FormalBlockV3.ps1"),
            "memoryPolicyModule": entry(RESEARCH / "Gate13RPR2MP2MemoryPolicyV2.psm1"),
        },
        "readiness": {
            "checkpointJson": entry(RESEARCH / "Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json"),
            "checkpointMarkdown": entry(RESEARCH / "Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.md"),
            "finalValidationAudit": entry(RESEARCH / "Gate13R_PR2_MP2_Final_Validation_Audit.v1.json"),
            "nextAuthorizationPrompt": entry(RESEARCH / "Gate13R_PR2_Attempt3_Next_Authorization_Prompt.md"),
        },
        "upstreamPreservation": {
            "postValidationAudit": entry(POST_AUDIT),
            "pilotV2Raw": post_audit["pilotV2Raw"],
            "pilotV1": post_audit["pilotV1"],
            "formalAttempt2": post_audit["formalAttempt2"],
            "analysisAttempt1": post_audit["analysisAttempt1"],
        },
        "selectedArtifacts": [entry(path) for path in artifacts],
        "validationTree": tree(VERIFY_ROOT),
        "runLedgerBinding": {
            "relativePath": "Research/Gate13R_PR2_MP2_Run_Passport_run_ledger.yaml",
            "bindingStage": "terminal-consistency-audit-after-final-ledger-receipt",
            "excludedFromThisManifestToAvoidCircularHashDependency": True,
        },
        "supersedesFailedManifest": {
            "relativePath": "Research/Gate13R_PR2_MP2_Evidence_Manifest.v1.json",
            "failureReceipt": entry(RESEARCH / "Gate13R_PR2_MP2_Evidence_Manifest_v1_Failure_Receipt.v1.json"),
            "failedManifest": entry(RESEARCH / "Gate13R_PR2_MP2_Evidence_Manifest.v1.json"),
            "reasonCode": "POST-MANIFEST-PASSPORT-TERMINAL-STATUS-UPDATE",
        },
    }
    atomic_create(TARGET, payload)
    print(json.dumps(entry(TARGET), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
