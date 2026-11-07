#!/usr/bin/env python3
"""Create the deterministic Gate 13R-PR2-MP1 attempt-2/v2 provenance registry."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ARTIFACTS = [
    "Research/Gate13R_PR2_MP1_Attempt2_Next_Authorization_Prompt.md",
    "Research/Gate13R_PR2_MP1_v2_User_Authorization.v1.txt",
    "Research/Gate13R_PR2_MP1_v2_Authorization.v1.json",
    "Research/Gate13R_PR2_MP1_v2_PreWrite_Preservation_Audit.v1.json",
    "Research/Gate13R_PR2_MP1_v2_Checkpoint_StateMachine_Amendment.v1.md",
    "Research/Gate13R_PR2_MP1_v2_Checkpoint_Schema.v1.json",
    "Research/Gate13R_PR2_MP1_v2_Test_Design.v1.md",
    "Research/Gate13R_PR2_MP1_Config_Schema.v2.json",
    "Research/Gate13R_PR2_MP1_Pilot_Config.v2.json",
    "Research/Gate13R_PR2_MP1_Specification.v1.md",
    "Research/Gate13R_PR2_MP1_Instrumentation_Contract.v1.json",
    "Research/Gate13R_PR2_MP1_Memory_Policy_Candidate_Registry.v1.json",
    "Research/Gate13R_PR2_MP1_Output_Schema.v1.json",
    "Research/Gate13R_PR2_MP1_Analysis_Plan.v1.md",
    "Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json",
    "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl",
    "Research/Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json",
    "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs",
    "Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs.meta",
    "Research/Gate13RPR2MemoryPolicyPilotV1.psm1",
    "Research/Gate13RPR2MemoryPolicyPilotV2.psm1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotV2.ps1",
    "Research/Start-Gate13RPR2MemoryPolicyPilotV2.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2.ps1",
    "Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2.ps1",
    "Research/Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2.ps1",
    "Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV2.py",
    "Research/Analyze-Gate13RPR2MemoryPolicyPilotV2.py",
    "Research/Test-Gate13RPR2MemoryPolicyPilotV2.py",
    "Research/Test-Gate13RPR2MP1PowerShellParserV2.ps1",
    "Research/Test-Gate13RPR2MP1V2CheckpointStateMachine.ps1",
    "Research/Test-Gate13RPR2MP1V2ZeroBlockFailure.ps1",
    "Research/Audit-Gate13RPR2MP1V2FrozenRoots.py",
    "Research/Finalize-Gate13RPR2MP1PrePilotV2.ps1",
    "Research/Invoke-Gate13RPR2MP1V2PrePilotValidation.ps1",
    "Research/Test-Gate13RPR2MP1FailurePrecedenceV1.ps1",
    "Research/Gate10RLockHygieneV3.psm1",
    "Research/New-Gate13RPR2MP1V2DerivedScripts.py",
    "Research/New-Gate13RPR2MP1V2PhaseScripts.py",
    "Research/New-Gate13RPR2MP1V2StaticTest.py",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    output = project / "Research/Gate13R_PR2_MP1_Provenance.v2.json"
    if output.exists():
        raise FileExistsError(output)
    artifacts = []
    for relative in ARTIFACTS:
        path = project / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        artifacts.append({"relativePath": relative, "bytes": path.stat().st_size, "sha256": sha256(path)})
    value = {
        "schemaVersion": 2,
        "provenanceId": "gate13r-pr2-mp1-attempt2-v2-provenance-v1",
        "frozenAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
        "scientificDesignId": "gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1",
        "executionAttemptId": "gate13r-pr2-mp1-attempt2-v2",
        "artifacts": artifacts,
        "scheduleIdentity": {
            "relativePath": "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl",
            "sha256": "826c7b85da6e3fcbe982a6e3becf21318216d5579dc198f2d47f5de0dc600136",
            "manifestSha256": "1ad38d5c78df69d4d94374dee1f95bbb0375c2df90aa2ceab978dd0d4e221c46",
            "byteIdenticalToPilotV1": True,
        },
        "v2RepairBoundary": {
            "allowed": ["complete-ordered-checkpoint-state-machine", "nonempty-backup-path-safe-atomic-replace", "outer-orchestrator-pre-first-block-failure-evidence", "v2-root-and-receipt-routing"],
            "scientificSemanticsChanged": False,
            "batchCommandChanged": False,
            "scheduleChanged": False,
        },
        "pilotV1FrozenIdentity": {"fileCount": 5, "rawBytes": 5247, "canonicalTreeSha256": "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265", "allFilesReadOnly": True},
        "formalAttempt2FrozenIdentity": {"fileCount": 28020, "rawBytes": 8536611302, "canonicalTreeSha256": "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e", "allFilesReadOnly": True},
        "authorizationBoundary": {"pilotV1RetryResumeTopUpMergeAuthorized": False, "measuredPilotV2Attempts": 1, "formalAttempt3Authorized": False, "formalStatisticalAnalysisAuthorized": False, "gate14RAuthorized": False},
        "runtime": {"powershellCurrent": "7.6.5", "dotnetCurrent": ".NET 10.0.11", "windowsPowerShell51": "5.1.26100.9444", "unityEditor": "2022.3.30f1c1_a6dc00fbe362", "timeZone": "Asia/Shanghai"},
    }
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-provenance-", dir=str(output.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"path": str(output), "bytes": output.stat().st_size, "sha256": sha256(output), "artifactCount": len(artifacts)}, sort_keys=True))


if __name__ == "__main__":
    main()
