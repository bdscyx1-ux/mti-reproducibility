#!/usr/bin/env python3
"""Build the stable evidence inventory for the failed zero-block MP1 v1 attempt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    research = root / "Research"
    selected: set[Path] = set()

    top_patterns = [
        "Gate13R_PR2_MP1_*",
        "Gate13RPR2MemoryPolicyPilotV1.psm1",
        "Run-Gate13RPR2MemoryPolicyPilot*V1.ps1",
        "Start-Gate13RPR2MemoryPolicyPilotV1.ps1",
        "Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1",
        "Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py",
        "Analyze-Gate13RPR2MemoryPolicyPilotV1.py",
        "Test-Gate13RPR2MemoryPolicyPilotV1.py",
        "Test-Gate13RPR2MP1*.ps1",
        "New-Gate13RPR2MemoryPolicyPilotV1.py",
        "New-Gate13RPR2MP1*.py",
        "Finalize-Gate13RPR2MP1PrePilotV1.ps1",
        "Preserve-Gate13RPR2MP1PilotV1Failure*.ps1",
    ]
    for pattern in top_patterns:
        selected.update(path for path in research.glob(pattern) if path.is_file())
    for directory in (
        research / "Verification/Gate13R_PR2_MP1",
        research / "PilotRuns/Gate13R_PR2_MemoryPolicy/v1",
    ):
        if directory.exists():
            selected.update(path for path in directory.rglob("*") if path.is_file())
    selected.update(
        path
        for path in (
            root / "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs",
            root / "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs.meta",
            research / "Overall_Project_Plan.md",
            research / "Next_Session_Checkpoint.md",
            research / "Gate13R_PR2_MemoryPolicy_Targeted_Pilot_Next_Authorization_Prompt.md",
        )
        if path.is_file()
    )
    selected.discard(output)
    rows = []
    for path in sorted(selected, key=lambda p: p.relative_to(root).as_posix()):
        stat = path.stat()
        rows.append(
            {
                "relativePath": path.relative_to(root).as_posix(),
                "bytes": stat.st_size,
                "sha256": sha256_file(path),
                "readOnly": not os.access(path, os.W_OK),
            }
        )
    canonical_lines = [f"{row['relativePath']}|{row['bytes']}|{row['sha256']}" for row in rows]
    document = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-mp1-pilot-v1-failure-evidence-manifest-v1",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": "FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / ZERO-MEASURED-BLOCKS",
        "fileCount": len(rows),
        "rawBytes": sum(row["bytes"] for row in rows),
        "canonicalArtifactTreeSha256": hashlib.sha256("\n".join(canonical_lines).encode("utf-8")).hexdigest(),
        "pilotRootIdentity": {
            "fileCount": 5,
            "rawBytes": 5247,
            "canonicalTreeSha256": "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265",
            "allFilesReadOnly": True,
        },
        "formalAttempt3Authorized": False,
        "formalStatisticalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
        "files": rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if output.exists():
        raise RuntimeError(f"Create-new manifest already exists: {output}")
    temporary.replace(output)
    print(json.dumps({"fileCount": len(rows), "rawBytes": document["rawBytes"], "canonicalArtifactTreeSha256": document["canonicalArtifactTreeSha256"]}, sort_keys=True))


if __name__ == "__main__":
    main()

