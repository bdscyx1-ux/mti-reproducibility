#!/usr/bin/env python3
"""Read-only post-pilot integrity audit for Gate 13R-PR2-MP1 v2."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT = Path(r"H:\DDM_Final_Project")
PILOT_V1 = PROJECT / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1"
FORMAL_ATTEMPT2 = PROJECT / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v2"
PILOT_V2 = PROJECT / "Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v2"
ANALYSIS_ATTEMPT1 = PROJECT / "Research/Analysis/Gate13R_PR2_MP1/v2/attempt-1"
EXPECTED_RAW_TREE = "13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def all_read_only(paths: list[Path]) -> bool:
    return bool(paths) and all(path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY for path in paths)


def frozen_tree(root: Path, contract_id: str) -> dict[str, Any]:
    files = sorted((path for path in root.rglob("*") if path.is_file()), key=lambda path: path.relative_to(root).as_posix())
    records: list[tuple[str, int, str]] = []
    raw_bytes = 0
    for path in files:
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest = sha256_file(path)
        records.append((relative, size, digest))
        raw_bytes += size
    if contract_id == "mp1-pilot-v1-pipe-delimited-no-final-lf-v1":
        payload = "\n".join(f"{relative}|{size}|{digest}" for relative, size, digest in records).encode("utf-8")
    elif contract_id == "gate13r-pr2-attempt2-ordinal-tab-final-lf-v2":
        payload = "".join(f"{relative}\t{size}\t{digest}\n" for relative, size, digest in records).encode("utf-8")
    else:
        raise ValueError(contract_id)
    return {
        "absolutePath": str(root.resolve()),
        "fileCount": len(files),
        "rawBytes": raw_bytes,
        "canonicalTreeContractId": contract_id,
        "canonicalTreeSha256": hashlib.sha256(payload).hexdigest(),
        "allFilesReadOnly": all_read_only(files),
    }


def validate_raw_tree() -> dict[str, Any]:
    raw_root = PILOT_V2 / "raw"
    manifest_path = PILOT_V2 / "pilot-raw-tree-manifest.json"
    freeze_path = PILOT_V2 / "pilot-raw-freeze-receipt.json"
    manifest = read_json(manifest_path)
    freeze = read_json(freeze_path)
    tree = hashlib.sha256()
    raw_bytes = 0
    files = manifest.get("files", [])
    mismatches: list[str] = []
    for ordinal, record in enumerate(files, start=1):
        path = raw_root / record["relativePath"]
        if record.get("ordinal") != ordinal:
            mismatches.append(f"ordinal:{record.get('relativePath')}")
            continue
        if not path.is_file():
            mismatches.append(f"missing:{record['relativePath']}")
            continue
        size = path.stat().st_size
        digest = sha256_file(path)
        if size != record["bytes"] or digest != record["sha256"]:
            mismatches.append(f"identity:{record['relativePath']}")
        if not (path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY):
            mismatches.append(f"writable:{record['relativePath']}")
        raw_bytes += size
        tree.update(f"{record['relativePath']}\t{size}\t{digest}\n".encode("utf-8"))
    actual_files = [path for path in raw_root.rglob("*") if path.is_file()]
    canonical = tree.hexdigest()
    passed = (
        not mismatches
        and len(files) == 3360
        and len(actual_files) == 3360
        and raw_bytes == 2607785161
        and manifest.get("fileCount") == 3360
        and manifest.get("rawBytes") == raw_bytes
        and manifest.get("canonicalTreeSha256") == canonical == EXPECTED_RAW_TREE
        and freeze.get("rawCanonicalTreeSha256") == canonical
        and freeze.get("allRawFilesReadOnly") is True
        and set(freeze.get("statusTokens", [])) == {"PILOT-RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"}
    )
    return {
        "absolutePath": str(raw_root.resolve()),
        "fileCount": len(actual_files),
        "rawBytes": raw_bytes,
        "canonicalTreeSha256": canonical,
        "manifestSha256": sha256_file(manifest_path),
        "freezeReceiptSha256": sha256_file(freeze_path),
        "mismatchCount": len(mismatches),
        "firstMismatches": mismatches[:10],
        "allFilesReadOnly": all_read_only(actual_files),
        "passed": passed,
    }


def validate_analysis() -> dict[str, Any]:
    evidence_path = ANALYSIS_ATTEMPT1 / "evidence-manifest.json"
    evidence = read_json(evidence_path)
    output_checks = []
    for record in evidence.get("outputs", []):
        path = ANALYSIS_ATTEMPT1 / record["relativePath"]
        actual_sha = sha256_file(path) if path.is_file() else None
        output_checks.append({
            "relativePath": record["relativePath"],
            "expectedSha256": record["sha256"],
            "actualSha256": actual_sha,
            "passed": path.is_file() and path.stat().st_size == record["bytes"] and actual_sha == record["sha256"],
        })
    files = [path for path in ANALYSIS_ATTEMPT1.rglob("*") if path.is_file()]
    passed = (
        evidence.get("passed") is True
        and evidence.get("rawAccess") == "READ-ONLY"
        and evidence.get("rawTreeSha256Before") == EXPECTED_RAW_TREE
        and evidence.get("rawTreeSha256After") == EXPECTED_RAW_TREE
        and evidence.get("unityInvoked") is False
        and evidence.get("formalAnalysisPerformed") is False
        and evidence.get("gate14RPerformed") is False
        and all(item["passed"] for item in output_checks)
        and all_read_only(files)
    )
    return {
        "absolutePath": str(ANALYSIS_ATTEMPT1.resolve()),
        "fileCount": len(files),
        "allFilesReadOnly": all_read_only(files),
        "evidenceManifestSha256": sha256_file(evidence_path),
        "outputChecks": output_checks,
        "passed": passed,
    }


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-postpilot-audit-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    pilot_v1 = frozen_tree(PILOT_V1, "mp1-pilot-v1-pipe-delimited-no-final-lf-v1")
    formal_attempt2 = frozen_tree(FORMAL_ATTEMPT2, "gate13r-pr2-attempt2-ordinal-tab-final-lf-v2")
    raw = validate_raw_tree()
    analysis = validate_analysis()
    checkpoint = read_json(PILOT_V2 / "pilot-checkpoint.json")
    pilot_top_files = [path for path in PILOT_V2.iterdir() if path.is_file()]
    checks = {
        "pilotV1Identity": pilot_v1["fileCount"] == 5 and pilot_v1["rawBytes"] == 5247 and pilot_v1["canonicalTreeSha256"] == "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265" and pilot_v1["allFilesReadOnly"],
        "formalAttempt2Identity": formal_attempt2["fileCount"] == 28020 and formal_attempt2["rawBytes"] == 8536611302 and formal_attempt2["canonicalTreeSha256"] == "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e" and formal_attempt2["allFilesReadOnly"],
        "pilotV2PhaseAComplete": checkpoint.get("status") == "PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE" and checkpoint.get("completedBlockCount") == 96 and checkpoint.get("completedSampleCount") == 384 and checkpoint.get("rawTreeSha256") == EXPECTED_RAW_TREE,
        "pilotV2TopFilesReadOnly": all_read_only(pilot_top_files),
        "rawTreePassed": raw["passed"],
        "analysisAttempt1Passed": analysis["passed"],
        "unityLockAbsent": not (PROJECT / "Temp/UnityLockfile").exists(),
        "formalAttempt3RootAbsent": not (PROJECT / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3").exists(),
        "formalAttempt3ReceiptAbsent": not (PROJECT / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json").exists(),
    }
    result = {
        "schemaVersion": 1,
        "auditKind": "gate13r-pr2-mp1-v2-postpilot-integrity-audit-v1",
        "capturedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS"],
        "pilotV1": pilot_v1,
        "formalAttempt2": formal_attempt2,
        "pilotV2Raw": raw,
        "analysisAttempt1": analysis,
        "checks": checks,
        "formalAnalysisPerformed": False,
        "gate14RPerformed": False,
        "passed": all(checks.values()),
    }
    output = Path(args.output).resolve()
    atomic_create(output, result)
    print(json.dumps({"passed": result["passed"], "output": str(output), "rawTreeSha256": raw["canonicalTreeSha256"]}, sort_keys=True))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
