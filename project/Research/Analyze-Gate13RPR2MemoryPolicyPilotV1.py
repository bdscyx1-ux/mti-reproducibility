#!/usr/bin/env python3
"""Read-only Phase-B analysis for the Gate 13R-PR2-MP1 memory pilot."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import stat
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median
from typing import Any, Iterable


MIB = 1024 * 1024
CANDIDATES = [512, 640, 768, 1024]
BOOTSTRAP_SEED = 130220261009
BOOTSTRAP_REPLICATES = 20_000


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
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-analysis-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(json_bytes(value))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def r7(values: Iterable[float], probability: float) -> float | None:
    ordered = sorted(float(value) for value in values)
    if not ordered:
        return None
    h = (len(ordered) - 1) * probability
    low, high = math.floor(h), math.ceil(h)
    if low == high:
        return ordered[low]
    return ordered[low] * (high - h) + ordered[high] * (h - low)


def describe(values: list[float]) -> dict[str, Any]:
    finite = [float(value) for value in values if math.isfinite(float(value))]
    if len(finite) != len(values):
        raise RuntimeError("Non-finite memory value in raw data")
    return {
        "n": len(finite),
        "minimum": min(finite) if finite else None,
        "median": median(finite) if finite else None,
        "p95R7": r7(finite, 0.95),
        "maximum": max(finite) if finite else None,
    }


def wilson(successes: int, total: int, z: float = 1.959963984540054) -> list[float | None]:
    if total == 0:
        return [None, None]
    proportion = successes / total
    denominator = 1 + z * z / total
    centre = (proportion + z * z / (2 * total)) / denominator
    radius = z * math.sqrt(proportion * (1 - proportion) / total + z * z / (4 * total * total)) / denominator
    return [max(0.0, centre - radius), min(1.0, centre + radius)]


def bootstrap_median(values: list[float], seed: int) -> dict[str, Any]:
    if not values:
        return {"replicates": BOOTSTRAP_REPLICATES, "seed": seed, "lower95": None, "upper95": None}
    rng = random.Random(seed)
    size = len(values)
    samples = []
    for _ in range(BOOTSTRAP_REPLICATES):
        samples.append(median([values[rng.randrange(size)] for _ in range(size)]))
    return {"replicates": BOOTSTRAP_REPLICATES, "seed": seed, "lower95": r7(samples, 0.025), "upper95": r7(samples, 0.975)}


def validate_raw_tree(raw_root: Path, manifest: dict[str, Any]) -> None:
    records = manifest["files"]
    if len(records) != manifest["fileCount"]:
        raise RuntimeError("Raw tree manifest cardinality mismatch")
    tree = hashlib.sha256()
    total = 0
    for record in records:
        path = raw_root / record["relativePath"]
        if not path.is_file() or path.stat().st_size != record["bytes"] or sha256_file(path) != record["sha256"]:
            raise RuntimeError(f"Raw tree identity mismatch: {record['relativePath']}")
        if not (path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY):
            raise RuntimeError(f"Raw file is not read-only: {record['relativePath']}")
        total += record["bytes"]
        tree.update(f"{record['relativePath']}\t{record['bytes']}\t{record['sha256']}\n".encode("utf-8"))
    if total != manifest["rawBytes"] or tree.hexdigest() != manifest["canonicalTreeSha256"]:
        raise RuntimeError("Raw tree aggregate identity mismatch")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pilot-root", required=True)
    parser.add_argument("--analysis-root", required=True)
    args = parser.parse_args()
    pilot_root = Path(args.pilot_root).resolve()
    raw_root = pilot_root / "raw"
    analysis_root = Path(args.analysis_root).resolve()
    if pilot_root == analysis_root or pilot_root in analysis_root.parents:
        raise RuntimeError("Analysis output must be outside the pilot/raw root")
    if analysis_root.exists():
        raise RuntimeError("Analysis attempt directory must be fresh")
    freeze_receipt = read_json(pilot_root / "pilot-raw-freeze-receipt.json")
    required_status = {"PILOT-RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"}
    if set(freeze_receipt.get("statusTokens", [])) != required_status or freeze_receipt.get("allRawFilesReadOnly") is not True:
        raise RuntimeError("Valid immutable Phase-A receipt is required")
    tree_manifest_path = pilot_root / "pilot-raw-tree-manifest.json"
    tree_manifest = read_json(tree_manifest_path)
    if sha256_file(tree_manifest_path) != freeze_receipt["rawTreeManifestSha256"]:
        raise RuntimeError("Raw tree manifest hash mismatch")
    validate_raw_tree(raw_root, tree_manifest)
    schedule_path = Path(r"H:\DDM_Final_Project\Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl")
    schedule = [json.loads(line) for line in schedule_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if len(schedule) != 96:
        raise RuntimeError("Schedule must contain 96 blocks")

    stage_rows: list[dict[str, Any]] = []
    block_rows: list[dict[str, Any]] = []
    psapi_cim: list[dict[str, Any]] = []
    safety_counts = Counter()
    for expected in schedule:
        block_dir = raw_root / expected["outputRelativePath"]
        plan = read_json(block_dir / "block-plan.json")
        stage = read_json(block_dir / "block-stage-telemetry.json")
        external = read_json(block_dir / "external-stage-telemetry.json")
        manifest = read_json(block_dir / "block-manifest.json")
        entry_by_position = {int(item["position"]): item for item in plan["entries"]}
        for record in stage["records"]:
            position = int(record.get("position") or 0)
            entry = entry_by_position.get(position, {})
            row = dict(record)
            row.update({
                "globalProcessOrdinal": expected["globalProcessOrdinal"],
                "scenarioId": expected["scenarioId"],
                "scaleId": expected["scaleId"],
                "williamsRowIndex": expected["williamsRowIndex"],
                "predecessorAlgorithmId": entry.get("predecessorAlgorithmId", "NONE"),
            })
            stage_rows.append(row)
            for flag in ("absoluteNativeEmergencyPassed", "relativeNativeEmergencyPassed", "availablePhysicalMemoryFloorPassed"):
                if record.get(flag) is False:
                    safety_counts[flag] += 1
        start = external["stages"][0]["snapshot"]
        cim = start.get("cim")
        if start.get("cimAvailable") and cim:
            psapi_cim.append({
                "blockId": expected["blockId"],
                "workingSetDifferenceBytes": abs(int(start["workingSetBytes"]) - int(cim["workingSetBytes"])),
                "privateMemoryDifferenceBytes": abs(int(start["privateMemoryBytes"]) - int(cim["privateMemoryBytes"])),
            })
        cleanup = [row for row in stage["records"] if row["stageId"] == "sample-after-cleanup"]
        max_ws = max(int(row["workingSetDeltaFromBlockBaselineBytes"]) for row in cleanup)
        max_private = max(int(row["privateMemoryDeltaFromBlockBaselineBytes"]) for row in cleanup)
        max_managed = max(int(row["managedMemoryDeltaFromBlockBaselineBytes"]) for row in cleanup)
        native = max(max_ws, max_private)
        block_rows.append({
            "globalProcessOrdinal": expected["globalProcessOrdinal"],
            "blockId": expected["blockId"],
            "scenarioId": expected["scenarioId"],
            "scaleId": expected["scaleId"],
            "williamsRowIndex": expected["williamsRowIndex"],
            "maximumCleanupWorkingSetDeltaBytes": max_ws,
            "maximumCleanupPrivateMemoryDeltaBytes": max_private,
            "maximumCleanupManagedDeltaBytes": max_managed,
            "maximumCleanupNativeDeltaBytes": native,
            "manifestBlockWorkingSetGrowthBytes": int(manifest["blockWorkingSetGrowthBytes"]),
            "manifestBlockPrivateMemoryGrowthBytes": int(manifest["blockPrivateMemoryGrowthBytes"]),
            "manifestBlockManagedGrowthBytes": int(manifest["blockRetainedManagedGrowthBytes"]),
            "minimumAvailablePhysicalMemoryBytes": int(external["monitor"]["minimumAvailablePhysicalMemoryBytes"]),
            "maximumAbsoluteWorkingSetBytes": int(external["monitor"]["maximumWorkingSetBytes"]),
            "maximumAbsolutePrivateMemoryBytes": int(external["monitor"]["maximumPrivateMemoryBytes"]),
        })

    if len(block_rows) != 96 or len(stage_rows) != 96 * 19:
        raise RuntimeError("Analysis input cardinality mismatch")
    stage_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    slice_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    first_crossings = Counter()
    for row in stage_rows:
        stage_groups[row["stageId"]].append(row)
        key = "|".join([row["scaleId"], str(row["williamsRowIndex"]), str(row.get("position", 0)), row.get("predecessorAlgorithmId", "NONE"), row.get("algorithmId", "") or "NONE", row["stageId"]])
        slice_groups[key].append(row)
    for expected in schedule:
        rows = [row for row in stage_rows if row["blockId"] == expected["blockId"]]
        for threshold in CANDIDATES:
            limit = threshold * MIB
            crossing = next((row["stageId"] for row in rows if max(row["workingSetDeltaFromBlockBaselineBytes"], row["privateMemoryDeltaFromBlockBaselineBytes"]) > limit), "NONE")
            first_crossings[f"{threshold}|{crossing}"] += 1

    stage_summary = []
    for stage_id, rows in sorted(stage_groups.items()):
        stage_summary.append({
            "stageId": stage_id,
            "recordCount": len(rows),
            "absoluteWorkingSetBytes": describe([row["workingSetBytes"] for row in rows]),
            "absolutePrivateMemoryBytes": describe([row["privateMemoryBytes"] for row in rows]),
            "absoluteManagedMemoryBytes": describe([row["managedMemoryBytes"] for row in rows]),
            "workingSetDeltaFromBlockBaselineBytes": describe([row["workingSetDeltaFromBlockBaselineBytes"] for row in rows]),
            "privateMemoryDeltaFromBlockBaselineBytes": describe([row["privateMemoryDeltaFromBlockBaselineBytes"] for row in rows]),
            "managedMemoryDeltaFromBlockBaselineBytes": describe([row["managedMemoryDeltaFromBlockBaselineBytes"] for row in rows]),
        })
    slices = []
    for key, rows in sorted(slice_groups.items()):
        scale, williams, position, predecessor, algorithm, stage_id = key.split("|")
        slices.append({
            "scaleId": scale, "williamsRowIndex": int(williams), "position": int(position),
            "predecessorAlgorithmId": predecessor, "algorithmId": algorithm, "stageId": stage_id,
            "recordCount": len(rows),
            "workingSetDeltaFromBlockBaselineBytes": describe([row["workingSetDeltaFromBlockBaselineBytes"] for row in rows]),
            "privateMemoryDeltaFromBlockBaselineBytes": describe([row["privateMemoryDeltaFromBlockBaselineBytes"] for row in rows]),
            "managedMemoryDeltaFromBlockBaselineBytes": describe([row["managedMemoryDeltaFromBlockBaselineBytes"] for row in rows]),
        })

    scale_summary = []
    candidate_rows = []
    for scale_index, scale in enumerate(("g032", "g064", "g128", "g256")):
        blocks = [row for row in block_rows if row["scaleId"] == scale]
        native_values = [row["maximumCleanupNativeDeltaBytes"] for row in blocks]
        managed_values = [row["maximumCleanupManagedDeltaBytes"] for row in blocks]
        scale_summary.append({
            "scaleId": scale,
            "blockCount": len(blocks),
            "maximumCleanupNativeDeltaBytes": describe(native_values),
            "maximumCleanupManagedDeltaBytes": describe(managed_values),
            "nativeMedianWholeBlockBootstrap95": bootstrap_median(native_values, BOOTSTRAP_SEED + scale_index),
            "managedMedianWholeBlockBootstrap95": bootstrap_median(managed_values, BOOTSTRAP_SEED + 100 + scale_index),
        })
        for threshold in CANDIDATES:
            limit = threshold * MIB
            exceed = sum(value > limit for value in native_values)
            near = sum(value >= 0.9 * limit for value in native_values)
            candidate_rows.append({
                "scaleId": scale,
                "candidateThresholdMiB": threshold,
                "candidateThresholdBytes": limit,
                "blockCount": len(blocks),
                "exceededBlockCount": exceed,
                "nearMissAtOrAbove90PercentCount": near,
                "exceedRateWilson95": wilson(exceed, len(blocks)),
                "pilotRole": "DIAGNOSTIC-FLAG-ONLY",
                "formalStatus": "UNFROZEN",
            })

    maximum_abs = max(max(row["maximumAbsoluteWorkingSetBytes"], row["maximumAbsolutePrivateMemoryBytes"]) for row in block_rows)
    maximum_delta = max(row["maximumCleanupNativeDeltaBytes"] for row in block_rows)
    minimum_free = min(row["minimumAvailablePhysicalMemoryBytes"] for row in block_rows)
    analysis = {
        "schemaVersion": 1,
        "analysisKind": "gate13r-pr2-mp1-stage-separated-memory-diagnostic-analysis-v1",
        "labels": ["NON-FORMAL", "MEMORY-DIAGNOSTIC-ONLY", "EXCLUDED-FROM-FORMAL-ANALYSIS", "NOT-ALGORITHM-SUPERIORITY-EVIDENCE"],
        "rawFreezeReceiptSha256": sha256_file(pilot_root / "pilot-raw-freeze-receipt.json"),
        "rawTreeSha256": freeze_receipt["rawCanonicalTreeSha256"],
        "blockCount": len(block_rows),
        "sampleCount": 384,
        "warmupProcessCount": 0,
        "stageRecordCount": len(stage_rows),
        "stageDistributions": stage_summary,
        "completeNonselectiveSlices": slices,
        "scaleTrend": scale_summary,
        "candidateThresholdDiagnostics": candidate_rows,
        "firstCrossingStageCounts": dict(sorted(first_crossings.items())),
        "psapiCimConsistency": {
            "pairCount": len(psapi_cim),
            "workingSetAbsoluteDifferenceBytes": describe([row["workingSetDifferenceBytes"] for row in psapi_cim]),
            "privateMemoryAbsoluteDifferenceBytes": describe([row["privateMemoryDifferenceBytes"] for row in psapi_cim]),
        },
        "safety": {
            "failedStageFlagCounts": dict(safety_counts),
            "maximumObservedAbsoluteNativeBytes": maximum_abs,
            "absolute4GiBMarginBytes": 4294967296 - maximum_abs,
            "maximumObservedCleanupNativeDeltaBytes": maximum_delta,
            "relative2GiBMarginBytes": 2147483648 - maximum_delta,
            "minimumObservedAvailablePhysicalMemoryBytes": minimum_free,
            "available8GiBFloorMarginBytes": minimum_free - 8589934592,
        },
        "bootstrap": {"unit": "complete-fresh-unity-williams-block", "replicates": BOOTSTRAP_REPLICATES, "baseSeed": BOOTSTRAP_SEED},
        "causalBoundary": "Algorithm/position/predecessor slices diagnose memory residency only and are not algorithm-performance or superiority estimates.",
        "formalInferencePerformed": False,
        "gate14RPerformed": False,
    }

    g256 = next(item for item in scale_summary if item["scaleId"] == "g256")
    runaway = any(row["maximumCleanupNativeDeltaBytes"] > 2147483648 for row in block_rows)
    recommendation = {
        "schemaVersion": 1,
        "decisionKind": "gate13r-pr2-mp1-forward-memory-policy-decision-matrix-v1",
        "candidateStatus": "UNFROZEN / REQUIRES-SEPARATE-FORMAL-ATTEMPT3-AUTHORIZATION",
        "runawayGrowthEvidence": runaway,
        "scenarioSizeAwareEnvelopeSupported": g256["maximumCleanupNativeDeltaBytes"]["median"] > next(item for item in scale_summary if item["scaleId"] == "g032")["maximumCleanupNativeDeltaBytes"]["median"],
        "fixedThresholdCandidates": candidate_rows,
        "layeredPolicy": {
            "absolute4GiBHostSafety": "RETAIN-AS-EMERGENCY",
            "relative2GiBHostSafety": "RETAIN-AS-EMERGENCY",
            "available8GiBFloor": "RETAIN-AS-EMERGENCY",
            "managed128MiBAlert": "RETAIN",
            "managed256MiBEmergency": "RETAIN",
            "nativeFormalEligibility": "UNFROZEN-PENDING-SEPARATE-AUTHORIZATION",
        },
        "recommendation": "Use a layered policy separating host-safety emergencies from a scenario-aware native-residency eligibility envelope; do not reactivate the historical fixed 512 MiB final-position gate without a separate forward authorization.",
        "attempt2DispositionUnaffected": True,
        "formalConfigModified": False,
        "formalAttempt3Started": False,
    }

    analysis_root.mkdir(parents=True, exist_ok=False)
    analysis_path = analysis_root / "stage-separated-memory-analysis.json"
    decision_path = analysis_root / "memory-policy-decision-matrix.json"
    atomic_create(analysis_path, analysis)
    atomic_create(decision_path, recommendation)
    manifest_out = {
        "schemaVersion": 1,
        "manifestKind": "gate13r-pr2-mp1-analysis-evidence-manifest-v1",
        "analysisRoot": str(analysis_root),
        "rawRoot": str(raw_root),
        "rawAccess": "READ-ONLY",
        "rawTreeSha256Before": freeze_receipt["rawCanonicalTreeSha256"],
        "rawTreeSha256After": freeze_receipt["rawCanonicalTreeSha256"],
        "outputs": [
            {"relativePath": analysis_path.name, "bytes": analysis_path.stat().st_size, "sha256": sha256_file(analysis_path)},
            {"relativePath": decision_path.name, "bytes": decision_path.stat().st_size, "sha256": sha256_file(decision_path)},
        ],
        "unityInvoked": False,
        "formalAnalysisPerformed": False,
        "gate14RPerformed": False,
        "passed": True,
    }
    atomic_create(analysis_root / "evidence-manifest.json", manifest_out)
    print(json.dumps({"passed": True, "analysisRoot": str(analysis_root), "rawTreeSha256": freeze_receipt["rawCanonicalTreeSha256"], "blockCount": 96, "stageRecordCount": len(stage_rows)}, sort_keys=True))


if __name__ == "__main__":
    main()
