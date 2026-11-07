#!/usr/bin/env python3
"""Create the create-new provenance binding for Gate 13R-PR2-MP1."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path


FILES = [
    "Research/Gate13R_PR2_MP1_User_Authorization.v1.txt",
    "Research/Gate13R_PR2_MP1_Authorization.v1.json",
    "Research/Gate13R_PR2_MP1_PreWrite_Preservation_Audit.v1.json",
    "Research/Gate13R_PR2_MP1_Specification.v1.md",
    "Research/Gate13R_PR2_MP1_Test_Design.v1.md",
    "Research/Gate13R_PR2_MP1_Instrumentation_Contract.v1.json",
    "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json",
    "Research/Gate13R_PR2_MP1_Output_Schema.v1.json",
    "Research/Gate13R_PR2_MP1_Analysis_Plan.v1.md",
    "Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json",
    "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl",
    "Research/Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json",
    "Research/Gate13R_PR2_MP1_Config_Schema.v1.json",
    "Research/Gate13R_PR2_MP1_Pilot_Config.v1.json",
    "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs",
    "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs.meta",
    "Research/Gate13RPR2MemoryPolicyPilotV1.psm1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotV1.ps1",
    "Research/Start-Gate13RPR2MemoryPolicyPilotV1.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1",
    "Research/Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1",
    "Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py",
    "Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py",
    "Research/Test-Gate13RPR2MemoryPolicyPilotV1.py",
    "Research/Test-Gate13RPR2MP1PowerShellParserV1.ps1",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    if output.exists():
        raise FileExistsError(output)
    base_command = project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV4.cs"
    expected_base_hash = "ef12eb01b903318c5ce9455d5872cff5e7f505f3d1496ffc860d512173be5467"
    if sha256_file(base_command) != expected_base_hash:
        raise RuntimeError("Frozen PR2 V4 command hash mismatch")
    artifacts = []
    for relative in FILES:
        path = project / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        artifacts.append({"relativePath": relative, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    payload = {
        "schemaVersion": 1,
        "provenanceId": "gate13r-pr2-mp1-targeted-memory-pilot-provenance-v1",
        "frozenAtUtc": "2026-10-09T03:25:00Z",
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
        "mechanicalDerivation": {
            "sourceRelativePath": "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV4.cs",
            "sourceSha256": expected_base_hash,
            "sourceBytes": base_command.stat().st_size,
            "derivedRelativePath": "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs",
            "allowedSemanticChanges": [
                "non-formal-MP1-identity-and-bound-inputs",
                "stage-separated-memory-instrumentation",
                "512-640-768-1024-native-diagnostic-flags-only",
                "256MiB-managed-and-4GiB-2GiB-8GiB-emergency-stops",
                "validation-only-injected-failure-support"
            ],
            "retainedSemantics": ["planning-workload", "planner-selection", "deterministic-scenario", "per-sample-reset", "correctness-and-structure", "path-safe-atomic-persistence"]
        },
        "attempt2FrozenIdentity": {"fileCount": 28020, "rawBytes": 8536611302, "canonicalOrdinalTreeSha256": "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e", "allFilesReadOnly": True},
        "runtime": {"powershellCurrent": "7.6.5", "windowsPowerShell51": "5.1.26100.9444", "dotnetCurrent": ".NET 10.0.11", "unityEditor": "2022.3.30f1c1_a6dc00fbe362", "timeZone": "Asia/Shanghai"},
        "artifacts": artifacts,
        "validationHistory": {
            "attempt1": "FAILED-PRESERVED / WINDOWS-PATH-BACKSLASH-INTERPOLATION-IN-TEST-HARNESS",
            "attempt2Static": "345-OF-345-PASSED"
        },
        "authorizationBoundary": {"measuredPilotAttempts": 1, "formalAttempt3Authorized": False, "attempt2RetryResumeTopUpMergeAuthorized": False, "formalAnalysisAuthorized": False, "gate14RAuthorized": False},
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".mp1-provenance-", dir=str(output.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8"))
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"passed": True, "output": str(output), "sha256": sha256_file(output), "artifactCount": len(artifacts)}, sort_keys=True))


if __name__ == "__main__":
    main()
