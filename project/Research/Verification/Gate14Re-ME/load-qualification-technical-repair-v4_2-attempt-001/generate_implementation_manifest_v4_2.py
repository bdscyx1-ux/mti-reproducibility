from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_1.json"
TARGET = ROOT / "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_2.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifact(role: str, relative_path: str) -> dict[str, object]:
    path = ROOT / relative_path
    if not path.is_file():
        raise RuntimeError(f"missing artifact: {relative_path}")
    return {
        "role": role,
        "relativePath": relative_path,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def main() -> None:
    if TARGET.exists():
        raise RuntimeError(f"refusing overwrite: {TARGET}")
    manifest = json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    remove_roles = {
        "runner-v4.1-source",
        "runner-v4.1-meta",
        "acquisition-only-supervisor-v4.1",
        "read-only-acceptance-launcher-v4.2",
        "streaming-acceptance-tool-v4.2",
        "acquisition-contract-v4.1",
        "acceptance-contract-v4.2",
        "exact-v4.1-compile-readiness-pass",
    }
    retained = [item for item in manifest["artifacts"] if item["role"] not in remove_roles]
    additions = [
        artifact("runner-v4.2-source", "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_2.cs"),
        artifact("runner-v4.2-meta", "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_2.cs.meta"),
        artifact("geometry-validator-v4-folder-meta", "Assets/_Scripts/Research/Gate14ReME/v4.meta"),
        artifact("geometry-validator-v4.2-source", "Assets/_Scripts/Research/Gate14ReME/v4/Gate14ReMEInputGeometryValidatorV4_2.cs"),
        artifact("geometry-validator-v4.2-meta", "Assets/_Scripts/Research/Gate14ReME/v4/Gate14ReMEInputGeometryValidatorV4_2.cs.meta"),
        artifact("acquisition-only-supervisor-v4.2", "Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_2.ps1"),
        artifact("read-only-acceptance-launcher-v4.3", "Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMEReadOnlyAcceptance.v4_3.ps1"),
        artifact("streaming-acceptance-tool-v4.3", "Research/Gate14Re-ME/Tools/gate14re_me_qualification_acceptance_v4_3.py"),
        artifact("acquisition-contract-v4.2", "Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_2.json"),
        artifact("acceptance-contract-v4.3", "Research/Gate14Re-ME/Execution/v4/load-qualification-acceptance-contract.v4_3.json"),
        artifact("attempt-010-failure-seal", "Research/Verification/Gate14Re-ME/load-qualification-failure-seal-attempt-010/terminal-failure-seal-receipt.v1.json"),
        artifact("v4.2-gnf-validator-compatibility-pass", "Research/Verification/Gate14Re-ME/load-qualification-technical-repair-v4_2-attempt-001/gnf-validator-compatibility-receipt.v1.json"),
        artifact("exact-v4.2-compile-readiness-pass", "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-009/terminal-readiness-receipt.v4_6.json"),
        artifact("exact-v4.2-compile-readiness-freeze", "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-009/freeze-manifest.v4_6.json"),
    ]
    manifest["manifestGeneration"] = 3
    manifest.pop("manifestSchemaV4_1", None)
    manifest["manifestSchemaV4_2"] = "gate14re-me-qualification-current-implementation-manifest-v4.2"
    manifest["executionReadinessStatus"] = "FROZEN_V4_2_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED"
    manifest["implementationId"] = "gate14re-me-bounded-gnf-oracle-cache-v4.2"
    manifest["compatibilityNote"] = (
        "The stable v1 manifest status remains source-oriented for typed runner compatibility. "
        "The authoritative v4.2 readiness state is executionReadinessStatus plus the exact-source "
        "natural-exit-zero compile receipt. V4.2 changes only the version-owned G/N/F geometry "
        "validator and its runner/supervisor/acceptance bindings after attempt-010 failed closed; "
        "the frozen design, schedule, six algorithms, 126 superblocks and 775-process acquisition remain unchanged."
    )
    manifest["artifacts"] = retained + additions
    manifest["technicalRepair"] = {
        "priorFailedAttempt": "load-qualification-execution-attempt-010",
        "failureClass": "VERSION_BINDING_OMISSION_OLD_ORACLE_GEOMETRY_LEVELS",
        "scientificDesignChanged": False,
        "scheduleChanged": False,
        "algorithmCohortChanged": False,
        "processCardinalityChanged": False,
    }
    for item in manifest["artifacts"]:
        actual = artifact(str(item["role"]), str(item["relativePath"]))
        if actual["bytes"] != item["bytes"] or actual["sha256"] != item["sha256"]:
            raise RuntimeError(f"retained artifact drift: {item['relativePath']}")
    relative_paths = [str(item["relativePath"]) for item in manifest["artifacts"]]
    if len(relative_paths) != len(set(relative_paths)):
        raise RuntimeError("duplicate artifact path")
    TARGET.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"target": TARGET.as_posix(), "artifacts": len(manifest["artifacts"]), "sha256": sha256(TARGET)}))


if __name__ == "__main__":
    main()
