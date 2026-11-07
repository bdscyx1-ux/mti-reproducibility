#!/usr/bin/env python3
"""Create MP1 v2.1 provenance after the two preserved validation-only repairs."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    source_generator = project / "Research/New-Gate13RPR2MP1ProvenanceV2.py"
    spec = importlib.util.spec_from_file_location("mp1_v2_provenance", source_generator)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    artifacts = list(module.ARTIFACTS) + [
        "Research/Gate13R_PR2_MP1_Provenance.v2.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt1_Failure_Log.v1.txt",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt1_Partial_Manifest.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt1_Failure_Receipt.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt1_Checkpoint.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt2_Failure_Log.v1.txt",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt2_Partial_Manifest.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt2_Failure_Receipt.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Validation_Attempt2_Checkpoint.v1.json",
        "Research/New-Gate13RPR2MP1ProvenanceV2_1.py",
    ]
    output = project / "Research/Gate13R_PR2_MP1_Provenance.v2_1.json"
    if output.exists():
        raise FileExistsError(output)
    records = []
    seen = set()
    for relative in artifacts:
        if relative in seen:
            continue
        seen.add(relative)
        path = project / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        records.append({"relativePath": relative, "bytes": path.stat().st_size, "sha256": sha256(path)})
    value = {
        "schemaVersion": 2,
        "provenanceId": "gate13r-pr2-mp1-attempt2-v2-1-provenance-v1",
        "frozenAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "scientificDesignId": "gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1",
        "executionAttemptId": "gate13r-pr2-mp1-attempt2-v2",
        "implementationRevision": "v2.1-empty-collection-and-cast-safe-failure-persistence",
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
        "artifacts": records,
        "validationHistory": [
            {"attempt": 1, "status": "FAILED-PRESERVED", "reason": "EMPTY-RAW-FILE-COLLECTION-NORMALIZED-TO-NULL-BEFORE-COUNT", "unityStarted": False},
            {"attempt": 2, "status": "FAILED-PRESERVED", "reason": "UNWRAPPED-IF-STATEMENT-USED-AS-CAST-OPERAND", "unityStarted": False},
            {"attempt": 3, "status": "ZERO-BLOCK-FIXTURE-PASSED-PS7-AND-PS51", "measuredPilotStarted": False},
        ],
        "scheduleIdentity": {"relativePath": "Research/Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl", "sha256": "826c7b85da6e3fcbe982a6e3becf21318216d5579dc198f2d47f5de0dc600136", "manifestSha256": "1ad38d5c78df69d4d94374dee1f95bbb0375c2df90aa2ceab978dd0d4e221c46", "byteIdenticalToPilotV1": True},
        "repairBoundary": {"scientificSemanticsChanged": False, "batchCommandChanged": False, "scheduleChanged": False, "repairs": ["explicit-empty-array-normalization", "precomputed-raw-byte-total-before-ordered-object-construction"]},
        "pilotV1FrozenIdentity": {"fileCount": 5, "rawBytes": 5247, "canonicalTreeSha256": "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265", "allFilesReadOnly": True},
        "formalAttempt2FrozenIdentity": {"fileCount": 28020, "rawBytes": 8536611302, "canonicalTreeSha256": "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e", "allFilesReadOnly": True},
        "authorizationBoundary": {"pilotV1RetryResumeTopUpMergeAuthorized": False, "measuredPilotV2Attempts": 1, "formalAttempt3Authorized": False, "formalStatisticalAnalysisAuthorized": False, "gate14RAuthorized": False},
    }
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-1-provenance-", dir=str(output.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"path": str(output), "bytes": output.stat().st_size, "sha256": sha256(output), "artifactCount": len(records)}, sort_keys=True))


if __name__ == "__main__":
    main()
