#!/usr/bin/env python3
"""Create mechanically derived v2 MP1 wrappers without modifying frozen v1 files."""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path


EXPECTED_SOURCE_HASHES = {
    "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1": "d9b4acc8f5354cb10577795948a2748119c7eaa9185bf7417e315c0a78dd0e7c",
    "Research/Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1.ps1": "5e17a3ce7766e79b597613ab0a74b02b498138c99f12c3135f1ae451545b8010",
    "Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1": "52b5c419e5d39a821f58c026d195a69b8767c8af00cb5aafb87627b62d4b5e33",
    "Research/Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1": "0704185a2cf1858bf92ebd3e05e4593f971f26542397076e72f1b2cdb142258e",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_create(path: Path, text: str) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-derived-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(text.encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def replace_exact(text: str, old: str, new: str, minimum: int = 1) -> str:
    count = text.count(old)
    if count < minimum:
        raise RuntimeError(f"Expected at least {minimum} occurrence(s) of {old!r}; found {count}")
    return text.replace(old, new)


def add_v2_module(text: str) -> str:
    anchor = "Import-Module (Join-Path $ProjectPath 'Research\\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force"
    addition = anchor + "\nImport-Module (Join-Path $ProjectPath 'Research\\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force"
    return replace_exact(text, anchor, addition, 1)


def derive_block(text: str) -> str:
    text = add_v2_module(text)
    replacements = {
        "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotBlockV1": "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotBlockV2",
        "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v1\\raw": "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v2\\raw",
        "Research\\Verification\\Gate13R_PR2_MP1'": "Research\\Verification\\Gate13R_PR2_MP1_v2'",
        "gate13r-pr2-mp1-validation-only-execution-receipt-v1": "gate13r-pr2-mp1-validation-only-execution-receipt-v2",
        "gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v1": "gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2",
        "gate13r-pr2-mp1-block-wrapper-summary-v1": "gate13r-pr2-mp1-block-wrapper-summary-v2",
        "Write-G13RPR2MP1AtomicJson": "Write-G13RPR2MP1V2AtomicJson",
    }
    for old, new in replacements.items():
        text = replace_exact(text, old, new)
    return text


def derive_selftests(text: str) -> str:
    text = add_v2_module(text)
    replacements = {
        "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1": "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2",
        "Research\\Verification\\Gate13R_PR2_MP1'": "Research\\Verification\\Gate13R_PR2_MP1_v2'",
        "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v1'": "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v2'",
        "gate13r-pr2-mp1-unity-self-test-wrapper-v1": "gate13r-pr2-mp1-unity-self-test-wrapper-v2",
        "gate13r-pr2-mp1-unity-self-tests-v1": "gate13r-pr2-mp1-unity-self-tests-v2",
        "Write-G13RPR2MP1AtomicJson": "Write-G13RPR2MP1V2AtomicJson",
    }
    for old, new in replacements.items():
        text = replace_exact(text, old, new)
    return text


def derive_telemetry(text: str) -> str:
    text = add_v2_module(text)
    replacements = {
        "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1": "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2",
        "Research\\Verification\\Gate13R_PR2_MP1'": "Research\\Verification\\Gate13R_PR2_MP1_v2'",
        "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v1'": "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v2'",
        "gate13r-pr2-mp1-telemetry-preflight-v1": "gate13r-pr2-mp1-telemetry-preflight-v2",
        "Write-G13RPR2MP1AtomicJson": "Write-G13RPR2MP1V2AtomicJson",
    }
    for old, new in replacements.items():
        text = replace_exact(text, old, new)
    return text


def derive_block_validation(text: str) -> str:
    text = add_v2_module(text)
    replacements = {
        "BINDING-SMOKE-PASSED|Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1": "BINDING-SMOKE-PASSED|Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2",
        "Research\\Verification\\Gate13R_PR2_MP1'": "Research\\Verification\\Gate13R_PR2_MP1_v2'",
        "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v1'": "Research\\PilotRuns\\Gate13R_PR2_MemoryPolicy\\v2'",
        "gate13r-pr2-mp1-validation-only-execution-receipt-v1": "gate13r-pr2-mp1-validation-only-execution-receipt-v2",
        "Research\\Gate13R_PR2_MP1_Pilot_Config.v1.json": "Research\\Gate13R_PR2_MP1_Pilot_Config.v2.json",
        "Research/Gate13R_PR2_MP1_Pilot_Config.v1.json": "Research/Gate13R_PR2_MP1_Pilot_Config.v2.json",
        "Research\\Gate13R_PR2_MP1_Test_Design.v1.md": "Research\\Gate13R_PR2_MP1_v2_Test_Design.v1.md",
        "Research/Gate13R_PR2_MP1_Test_Design.v1.md": "Research/Gate13R_PR2_MP1_v2_Test_Design.v1.md",
        "Research\\Gate13R_PR2_MP1_Provenance.v1.json": "Research\\Gate13R_PR2_MP1_Provenance.v2.json",
        "Research/Gate13R_PR2_MP1_Provenance.v1.json": "Research/Gate13R_PR2_MP1_Provenance.v2.json",
        "Research\\Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1": "Research\\Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1",
        "gate13r-pr2-mp1-positive-negative-block-validation-v1": "gate13r-pr2-mp1-positive-negative-block-validation-v2",
        "Write-G13RPR2MP1AtomicJson": "Write-G13RPR2MP1V2AtomicJson",
    }
    for old, new in replacements.items():
        text = replace_exact(text, old, new)
    return text


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    for relative, expected in EXPECTED_SOURCE_HASHES.items():
        actual = sha256(project / relative)
        if actual != expected:
            raise RuntimeError(f"Frozen source hash mismatch: {relative}: {actual}")
    jobs = [
        ("Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1", "Research/Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1", derive_block),
        ("Research/Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1.ps1", "Research/Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV2.ps1", derive_selftests),
        ("Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1", "Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2.ps1", derive_telemetry),
        ("Research/Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1", "Research/Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV2.ps1", derive_block_validation),
    ]
    for source_relative, target_relative, transform in jobs:
        source = project / source_relative
        target = project / target_relative
        text = source.read_text(encoding="utf-8-sig")
        derived = transform(text)
        header = (
            "# Mechanically derived for Gate13R-PR2-MP1 attempt 2 / v2.\n"
            f"# Frozen source: {source_relative}; SHA-256 {EXPECTED_SOURCE_HASHES[source_relative]}.\n"
            "# Allowed changes: v2 root/receipt/output routing and v2 path-safe atomic writer only.\n"
        )
        atomic_create(target, header + derived)
        print(f"{target_relative}|{sha256(target)}")


if __name__ == "__main__":
    main()
