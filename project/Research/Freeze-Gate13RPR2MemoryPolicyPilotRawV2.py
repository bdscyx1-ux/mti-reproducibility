# Mechanically derived from Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py; SHA-256 87861378c94c93a8a6c91915bb6b5e919746c4dedb287b53f710a56e7733964d.
#!/usr/bin/env python3
"""Validate and atomically commit immutable Gate 13R-PR2-MP1 raw pilot data."""

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


LABELS = ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"]
STATUS = ["PILOT-RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def atomic_create(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(path)
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-freeze-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(json_bytes(value))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def build_tree(root: Path) -> tuple[list[dict[str, Any]], int, str]:
    files = sorted((path for path in root.rglob("*") if path.is_file()), key=lambda path: path.relative_to(root).as_posix())
    records: list[dict[str, Any]] = []
    total = 0
    tree = hashlib.sha256()
    seen: set[str] = set()
    for path in files:
        relative = path.relative_to(root).as_posix()
        key = relative.casefold()
        if key in seen:
            raise RuntimeError(f"Case-colliding raw path: {relative}")
        seen.add(key)
        before = path.stat()
        digest = sha256_file(path)
        after = path.stat()
        if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
            raise RuntimeError(f"Raw file changed during hash: {relative}")
        total += before.st_size
        tree.update(f"{relative}\t{before.st_size}\t{digest}\n".encode("utf-8"))
        records.append({"ordinal": len(records) + 1, "relativePath": relative, "bytes": before.st_size, "sha256": digest})
    return records, total, tree.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pilot-root", required=True)
    parser.add_argument("--raw-root", required=True)
    parser.add_argument("--schedule", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--environment-end", required=True)
    args = parser.parse_args()
    pilot_root = Path(args.pilot_root).resolve()
    raw_root = Path(args.raw_root).resolve()
    if raw_root.parent != pilot_root or raw_root.name != "raw":
        raise RuntimeError("Raw root must be the exact pilot-root/raw directory")
    schedule_path = Path(args.schedule).resolve()
    config_path = Path(args.config).resolve()
    receipt_path = Path(args.receipt).resolve()
    environment_path = Path(args.environment_end).resolve()
    schedule = [json.loads(line) for line in schedule_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if len(schedule) != 96:
        raise RuntimeError("Schedule must contain exactly 96 measured blocks")
    receipt = read_json(receipt_path)
    config = read_json(config_path)
    if receipt.get("receiptKind") != "gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2" or receipt.get("measuredPilotAuthorized") is not True:
        raise RuntimeError("Pilot v2 execution receipt is not authorized")
    if config.get("configId") != "gate13r-pr2-mp1-targeted-memory-pilot-config-v2":
        raise RuntimeError("Pilot v2 config identity mismatch")

    block_summaries: list[dict[str, Any]] = []
    sample_count = 0
    for expected in schedule:
        block_dir = raw_root / expected["outputRelativePath"]
        manifest_path = block_dir / "block-manifest.json"
        wrapper_path = block_dir / "wrapper-summary.json"
        stage_path = block_dir / "block-stage-telemetry.json"
        external_path = block_dir / "external-stage-telemetry.json"
        checkpoint_path = block_dir / "block-checkpoint.json"
        for required in (manifest_path, wrapper_path, stage_path, external_path, checkpoint_path, block_dir / "block-plan.json", block_dir / "Unity.log"):
            if not required.is_file():
                raise RuntimeError(f"Required raw block file missing: {required}")
        if (block_dir / "block-failure.json").exists():
            raise RuntimeError(f"Failed block cannot enter raw commit: {expected['blockId']}")
        manifest = read_json(manifest_path)
        wrapper = read_json(wrapper_path)
        stage = read_json(stage_path)
        checkpoint = read_json(checkpoint_path)
        if manifest.get("blockId") != expected["blockId"] or manifest.get("completed") is not True or manifest.get("formalCampaign") is not False:
            raise RuntimeError(f"Block manifest identity/completion failure: {expected['blockId']}")
        if manifest.get("completedSampleCount") != 4 or len(manifest.get("samples", [])) != 4:
            raise RuntimeError(f"Block sample cardinality failure: {expected['blockId']}")
        if wrapper.get("passed") is not True or wrapper.get("formalCampaign") is not False:
            raise RuntimeError(f"Wrapper did not pass: {expected['blockId']}")
        if stage.get("completed") is not True or len(stage.get("records", [])) != 19:
            raise RuntimeError(f"Stage telemetry incomplete: {expected['blockId']}")
        if checkpoint.get("status") != "block-completed":
            raise RuntimeError(f"Terminal block checkpoint mismatch: {expected['blockId']}")
        sample_count += 4
        block_summaries.append({
            "globalProcessOrdinal": expected["globalProcessOrdinal"],
            "blockId": expected["blockId"],
            "scenarioId": expected["scenarioId"],
            "williamsRowIndex": expected["williamsRowIndex"],
            "blockManifestSha256": sha256_file(manifest_path),
            "wrapperSummarySha256": sha256_file(wrapper_path),
            "stageTelemetrySha256": sha256_file(stage_path),
            "externalTelemetrySha256": sha256_file(external_path),
        })
    if sample_count != 384:
        raise RuntimeError("Measured sample count must equal 384")

    records, raw_bytes, tree_sha = build_tree(raw_root)
    captured = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    tree_manifest_path = pilot_root / "pilot-raw-tree-manifest.json"
    execution_manifest_path = pilot_root / "pilot-raw-execution-manifest.json"
    receipt_out_path = pilot_root / "pilot-raw-freeze-receipt.json"
    tree_manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-mp1-immutable-raw-tree-manifest-v2",
        "capturedAtUtc": captured,
        "rawRoot": str(raw_root),
        "fileCount": len(records),
        "rawBytes": raw_bytes,
        "canonicalTreeFormula": "ordinal-relative-forward-slash + TAB + byteLength + TAB + lowercase-sha256 + LF; UTF-8 no BOM",
        "canonicalTreeSha256": tree_sha,
        "files": records,
    }
    atomic_create(tree_manifest_path, tree_manifest)
    execution_manifest = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-mp1-raw-execution-manifest-v2",
        "capturedAtUtc": captured,
        "labels": LABELS,
        "statusTokens": STATUS,
        "measuredBlockCount": 96,
        "measuredSampleCount": 384,
        "warmupProcessCount": 0,
        "scheduleSha256": sha256_file(schedule_path),
        "configSha256": sha256_file(config_path),
        "executionReceiptSha256": sha256_file(receipt_path),
        "environmentEndSnapshotSha256": sha256_file(environment_path),
        "rawTreeManifestSha256": sha256_file(tree_manifest_path),
        "rawTreeSha256": tree_sha,
        "blocks": block_summaries,
    }
    atomic_create(execution_manifest_path, execution_manifest)

    for path in (path for path in raw_root.rglob("*") if path.is_file()):
        os.chmod(path, stat.S_IREAD)
    read_only_count = sum(bool(path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY) for path in raw_root.rglob("*") if path.is_file())
    if read_only_count != len(records):
        raise RuntimeError("Not every raw file became read-only")
    freeze_receipt = {
        "schemaVersion": 1,
        "receiptKind": "gate13r-pr2-mp1-pilot-raw-freeze-receipt-v2",
        "committedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "labels": LABELS,
        "statusTokens": STATUS,
        "pilotRoot": str(pilot_root),
        "rawRoot": str(raw_root),
        "measuredBlockCount": 96,
        "measuredSampleCount": 384,
        "warmupProcessCount": 0,
        "rawFileCount": len(records),
        "rawBytes": raw_bytes,
        "rawCanonicalTreeSha256": tree_sha,
        "rawTreeManifestSha256": sha256_file(tree_manifest_path),
        "rawExecutionManifestSha256": sha256_file(execution_manifest_path),
        "allRawFilesReadOnly": True,
        "analysisPending": True,
        "ordinaryAnalysisFailureMayRerunUnity": False,
        "automaticRetryAuthorized": False,
        "automaticResumeAuthorized": False,
        "topUpAuthorized": False,
        "partialMergeAuthorized": False,
        "formalCampaign": False,
        "formalAnalysisAuthorized": False,
        "gate14RAuthorized": False,
    }
    atomic_create(receipt_out_path, freeze_receipt)
    for path in (tree_manifest_path, execution_manifest_path, environment_path, receipt_out_path):
        os.chmod(path, stat.S_IREAD)
    print(json.dumps({"passed": True, "fileCount": len(records), "rawBytes": raw_bytes, "rawTreeSha256": tree_sha, "rawFreezeReceipt": str(receipt_out_path)}, sort_keys=True))


if __name__ == "__main__":
    main()
