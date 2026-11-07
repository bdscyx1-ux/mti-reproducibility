#!/usr/bin/env python3
"""Mechanically derive the MP1 v2 static/unit validation from the frozen v1 test."""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path


SOURCE_SHA256 = "173206d26196b6d0ce53918a0f449b8c9444fa72cc611a1fa77ab3bad4acc77e"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace(text: str, old: str, new: str, count: int | None = None) -> str:
    occurrences = text.count(old)
    if occurrences == 0 or (count is not None and occurrences != count):
        raise RuntimeError(f"Replacement anchor mismatch for {old!r}: {occurrences}")
    return text.replace(old, new)


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    source = project / "Research/Test-Gate13RPR2MemoryPolicyPilotV1.py"
    target = project / "Research/Test-Gate13RPR2MemoryPolicyPilotV2.py"
    if sha(source) != SOURCE_SHA256:
        raise RuntimeError("Frozen MP1 v1 static test hash mismatch")
    if target.exists():
        raise FileExistsError(target)
    text = source.read_text(encoding="utf-8-sig")
    text = replace(text, '"""Static, schema, schedule, formula, and no-Unity validation for MP1."""', '"""Static, schema, schedule, formula, state-machine, and no-Unity validation for MP1 v2."""', 1)
    text = replace(text, 'prewrite = read_json(project / "Research/Gate13R_PR2_MP1_PreWrite_Preservation_Audit.v1.json")', 'prewrite = read_json(project / "Research/Gate13R_PR2_MP1_v2_PreWrite_Preservation_Audit.v1.json")', 1)
    text = replace(text, 'check("prewrite-attempt2-identity", prewrite["passed"] is True and prewrite["attempt2FormalRoot"]["canonicalOrdinalTreeSha256"] == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e")', 'check("prewrite-attempt2-identity", prewrite["passed"] is True and prewrite["formalAttempt2"]["canonicalTreeSha256"] == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e")\n    check("prewrite-pilot-v1-identity", prewrite["pilotV1"]["canonicalTreeSha256"] == "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265" and prewrite["pilotV1"]["rawFileCount"] == 0)', 1)
    old_list_end = '        "Research/Gate13R_PR2_MP1_Pilot_Config.v1.json",\n    ]'
    new_list_end = '''        "Research/Gate13R_PR2_MP1_Pilot_Config.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Authorization.v1.json",
        "Research/Gate13R_PR2_MP1_v2_PreWrite_Preservation_Audit.v1.json",
        "Research/Gate13R_PR2_MP1_v2_Checkpoint_Schema.v1.json",
        "Research/Gate13R_PR2_MP1_Pilot_Config.v2.json",
        "Research/Gate13R_PR2_MP1_Provenance.v2.json",
    ]'''
    text = replace(text, old_list_end, new_list_end, 1)
    text = replace(text, 'wrapper = (project / "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1").read_text(encoding="utf-8-sig")', 'wrapper = (project / "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1").read_text(encoding="utf-8-sig")', 1)
    anchor = '    check("no-auto-retry", all(token in wrapper for token in ["automaticRetryAttempted = $false", "automaticResumeAttempted = $false", "topUpAttempted = $false", "partialMergeAttempted = $false"]))'
    insertion = anchor + '''
    state_module = (project / "Research/Gate13RPR2MemoryPolicyPilotV2.psm1").read_text(encoding="utf-8-sig")
    check("state-complete-fields", all(token in state_module for token in ["startedAtUtc", "failureReceiptSha256", "partialOutputManifestSha256", "phaseACommittedAtUtc", "rawTreeSha256"]))
    check("state-no-direct-deserialized-mutation", "$checkpoint.startedAtUtc =" not in (project / "Research/Run-Gate13RPR2MemoryPolicyPilotV2.ps1").read_text(encoding="utf-8-sig"))
    check("atomic-nonempty-backup", "[IO.File]::Replace($temporary, $full, $backup)" in state_module and "[IO.File]::Replace($temporary, $full, $null)" not in state_module)
    check("outer-zero-block-failure", "SYNTHETIC-ZERO-BLOCK-INJECTED-FAILURE" in (project / "Research/Run-Gate13RPR2MemoryPolicyPilotV2.ps1").read_text(encoding="utf-8-sig"))
    config_v2 = read_json(project / "Research/Gate13R_PR2_MP1_Pilot_Config.v2.json")
    check("config-v2-identity", config_v2["configId"] == "gate13r-pr2-mp1-targeted-memory-pilot-config-v2" and config_v2["scientificDesignId"] == "gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1")
    check("config-v2-cardinality", config_v2["matrix"]["measuredProcesses"] == 96 and config_v2["matrix"]["measuredSamples"] == 384 and config_v2["matrix"]["warmupProcesses"] == 0)
    check("config-v2-root", config_v2["execution"]["pilotRoot"] == r"H:\\DDM_Final_Project\\Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v2")'''
    text = replace(text, anchor, insertion, 1)
    text = replace(text, 'analysis = (project / "Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py").read_text(encoding="utf-8-sig")', 'analysis = (project / "Research/Analyze-Gate13RPR2MemoryPolicyPilotV2.py").read_text(encoding="utf-8-sig")', 1)
    text = replace(text, 'check("measured-pilot-root-absent", not (project / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1").exists())', 'check("measured-pilot-v2-root-absent", not (project / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v2").exists())\n    check("failed-pilot-v1-root-retained", (project / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1").exists())', 1)
    text = replace(text, '"gate13r-pr2-mp1-static-unit-validation-v1"', '"gate13r-pr2-mp1-static-unit-validation-v2"', 1)
    text = replace(text, 'prefix=".mp1-test-"', 'prefix=".mp1-v2-test-"', 1)
    header = f'# Mechanically derived from Research/Test-Gate13RPR2MemoryPolicyPilotV1.py; SHA-256 {SOURCE_SHA256}.\n'
    data = (header + text).encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-static-", dir=str(target.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(f"Research/Test-Gate13RPR2MemoryPolicyPilotV2.py|{sha(target)}")


if __name__ == "__main__":
    main()
