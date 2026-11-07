#!/usr/bin/env python3
"""Anonymous, read-only D1/D2 load-window calibration for sealed attempt-009."""

from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


THRESHOLDS = (0.05, 0.10, 0.20)
ANON_LANES = tuple(f"ALG-{letter}" for letter in "ABCDEF")
PAIR_COUNT = 15


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path):
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def dump_json(path: Path, value) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")


def median(values):
    return statistics.median(values)


def geometric_mean(values):
    require(values and all(math.isfinite(v) and v > 0 for v in values), "invalid geometric-mean input")
    return math.exp(sum(math.log(v) for v in values) / len(values))


def metric_separates(signed_log_ratios, threshold):
    require(len(signed_log_ratios) == 3, "pair must have three independent superblocks")
    signs = [1 if value > 0 else -1 if value < 0 else 0 for value in signed_log_ratios]
    stable_direction = all(sign == signs[0] and sign != 0 for sign in signs)
    cutoff = math.log1p(threshold)
    absolute = [abs(value) for value in signed_log_ratios]
    large_count = sum(value >= cutoff for value in absolute)
    return stable_direction and large_count >= 2 and median(absolute) >= cutoff


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    freeze = load_json(root / "pre-analysis-freeze-manifest.v1.json")
    require(freeze["schema"] == "gate14re-me-gnf-discrimination-window-pre-analysis-freeze-manifest-v1", "freeze schema mismatch")
    for item in freeze["files"]:
        path = Path(item["absolutePath"])
        require(path.is_file(), f"missing frozen file: {path}")
        require(path.stat().st_size == int(item["bytes"]), f"size mismatch: {path}")
        require(sha256(path) == item["sha256"], f"hash mismatch: {path}")
    by_role = {item["role"]: Path(item["absolutePath"]) for item in freeze["files"]}

    offline = load_json(by_role["offline-validation-result"])
    require(offline["status"] == "PASS_OFFLINE_NECESSARY_RAW_VALIDATION", "offline validation gate not met")
    require(offline["sealedInventory"]["allCurrentHashesMatchSeal"] is True, "sealed inventory gate not met")
    seal_receipt = load_json(by_role["paused-seal-terminal-receipt"])
    require(seal_receipt["status"] == "PASS_PAUSED_SEAL_CREATED_QUALIFICATION_NOT_PASS", "paused seal gate not met")
    require(seal_receipt["rawDataPreserved"] is True, "raw preservation gate not met")

    measured_root = Path(offline["sourceMeasuredRoot"])
    manifest_rows = {}
    with by_role["measured-file-manifest"].open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            if not line.strip():
                continue
            row = json.loads(line)
            require(row["schema"] == "gate14re-me-paused-seal-file-row-v1" and row["root"] == "measured", "seal manifest row mismatch")
            relative = row["relativePath"].replace("\\", "/")
            require(relative not in manifest_rows, f"duplicate seal path: {relative}")
            manifest_rows[relative] = row

    event_paths = sorted(measured_root.glob("raw/superblocks/G14ME-QSB-C*/ALG-*/event-groups.raw.v2.jsonl"))
    require(len(event_paths) == 864, f"expected 864 core event-group files, got {len(event_paths)}")
    summaries = {}
    inventory = []
    for path in event_paths:
        relative = path.relative_to(measured_root).as_posix()
        require(relative in manifest_rows, f"event file absent from seal manifest: {relative}")
        sealed = manifest_rows[relative]
        require(path.stat().st_size == int(sealed["bytes"]), f"sealed size mismatch: {relative}")
        digest = sha256(path)
        require(digest == sealed["sha256"], f"sealed hash mismatch: {relative}")
        inventory.append({
            "schema": "gate14re-me-gnf-discrimination-window-input-file-v1",
            "relativePath": relative,
            "bytes": path.stat().st_size,
            "sha256": digest,
        })

        rows = []
        with path.open("r", encoding="utf-8-sig") as stream:
            for line in stream:
                if line.strip():
                    rows.append(json.loads(line))
        require(len(rows) == 24, f"expected 24 event groups: {relative}")
        first = rows[0]
        required = [
            "superblockId", "designRegion", "anonymousLaneId", "gridEdge", "agentCount",
            "changedCellCount", "eligible", "finitePositiveElapsed", "eventGroupElapsedMilliseconds",
            "gridAccessorCallsTotal",
        ]
        require(all(field in first for field in required), f"required field missing: {relative}")
        superblock = first["superblockId"]
        lane = first["anonymousLaneId"]
        g, n, f = int(first["gridEdge"]), int(first["agentCount"]), int(first["changedCellCount"])
        require(first["designRegion"] == "core" and lane in ANON_LANES, f"unexpected core identity: {relative}")
        require(all(row["superblockId"] == superblock and row["anonymousLaneId"] == lane for row in rows), f"mixed lane file: {relative}")
        require(all((int(row["gridEdge"]), int(row["agentCount"]), int(row["changedCellCount"])) == (g, n, f) for row in rows), f"mixed GNF file: {relative}")
        eligible = [row for row in rows if row["eligible"] is True]
        d1 = [float(row["eventGroupElapsedMilliseconds"]) for row in eligible if row["finitePositiveElapsed"] is True]
        d2 = [float(row["gridAccessorCallsTotal"]) for row in eligible if float(row["gridAccessorCallsTotal"]) > 0]
        require(len(eligible) >= 23 and len(d1) >= 23 and len(d2) >= 23, f"insufficient eligible event groups: {relative}")
        key = (g, n, f, superblock, lane)
        require(key not in summaries, f"duplicate lane-seed summary: {key}")
        summaries[key] = {"D1": geometric_mean(d1), "D2": median(d2)}

    require(len(summaries) == 864, "lane-seed summary cardinality mismatch")
    with (root / "input-file-inventory.v1.jsonl").open("w", encoding="utf-8", newline="\n") as stream:
        for row in inventory:
            stream.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")

    timing_by_cell = defaultdict(list)
    with by_role["algorithm-gnf-runtime-cells"].open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["designRegion"] != "core":
                continue
            key = (int(row["G"]), int(row["N"]), int(row["F"]))
            timing_by_cell[key].append({
                "p50": float(row["processWallP50Milliseconds"]),
                "maximum": float(row["processWallMaximumMilliseconds"]),
            })
    require(len(timing_by_cell) == 48 and all(len(values) == 6 for values in timing_by_cell.values()), "timing cell cardinality mismatch")

    superblocks_by_cell = defaultdict(set)
    for g, n, f, superblock, lane in summaries:
        superblocks_by_cell[(g, n, f)].add(superblock)
    require(len(superblocks_by_cell) == 48 and all(len(values) == 3 for values in superblocks_by_cell.values()), "core superblock cardinality mismatch")

    cell_rows = []
    for cell in sorted(superblocks_by_cell):
        g, n, f = cell
        superblocks = sorted(superblocks_by_cell[cell])
        pair_metric_margins = []
        separated_counts = {threshold: 0 for threshold in THRESHOLDS}
        for lane_a, lane_b in itertools.combinations(ANON_LANES, 2):
            d1_ratios = [math.log(summaries[(g, n, f, sb, lane_a)]["D1"] / summaries[(g, n, f, sb, lane_b)]["D1"]) for sb in superblocks]
            d2_ratios = [math.log(summaries[(g, n, f, sb, lane_a)]["D2"] / summaries[(g, n, f, sb, lane_b)]["D2"]) for sb in superblocks]
            pair_metric_margins.append(max(median([abs(value) for value in d1_ratios]), median([abs(value) for value in d2_ratios])))
            for threshold in THRESHOLDS:
                if metric_separates(d1_ratios, threshold) or metric_separates(d2_ratios, threshold):
                    separated_counts[threshold] += 1

        timing = timing_by_cell[cell]
        row = {
            "G": g,
            "N": n,
            "F": f,
            "independentSuperblocks": 3,
            "anonymousPairCount": PAIR_COUNT,
            "minimumPairMedianBestMetricLogGap": round(min(pair_metric_margins), 9),
            "medianPairMedianBestMetricLogGap": round(median(pair_metric_margins), 9),
            "cellTypicalProcessWallSeconds": round(median([item["p50"] for item in timing]) / 1000.0, 6),
            "cellWorstObservedProcessWallSeconds": round(max(item["maximum"] for item in timing) / 1000.0, 6),
            "withinPreferred180SecondCeiling": max(item["maximum"] for item in timing) <= 180_000.0,
            "withinHard300SecondCeiling": max(item["maximum"] for item in timing) <= 300_000.0,
        }
        for threshold in THRESHOLDS:
            label = int(round(threshold * 100))
            count = separated_counts[threshold]
            row[f"separatedPairsAt{label}Percent"] = count
            row[f"pairCoverageAt{label}Percent"] = round(count / PAIR_COUNT, 6)
            row[f"allSixOperationallyDistinctAt{label}Percent"] = count == PAIR_COUNT
        cell_rows.append(row)

    csv_fields = list(cell_rows[0].keys())
    with (root / "cell-discrimination-runtime.v1.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=csv_fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(cell_rows)

    factor_boundaries = {}
    for axis in ("G", "N", "F"):
        grouped = defaultdict(list)
        for row in cell_rows:
            grouped[row[axis]].append(row)
        factor_boundaries[axis] = []
        for level in sorted(grouped):
            rows = grouped[level]
            factor_boundaries[axis].append({
                "level": level,
                "cells": len(rows),
                "medianPairCoverageAt10Percent": round(median([r["pairCoverageAt10Percent"] for r in rows]), 6),
                "cellsAllSixDistinctAt10Percent": sum(r["allSixOperationallyDistinctAt10Percent"] for r in rows),
                "medianTypicalProcessWallSeconds": round(median([r["cellTypicalProcessWallSeconds"] for r in rows]), 6),
                "cellsAbove300SecondWorstObserved": sum(not r["withinHard300SecondCeiling"] for r in rows),
            })

    output = {
        "schema": "gate14re-me-gnf-cell-discrimination-runtime-v1",
        "studyId": "Gate14Re-ME",
        "designAttemptId": "gnf-discrimination-window-design-v1-attempt-001",
        "status": "PASS_ANONYMOUS_DESCRIPTIVE_WINDOW_CALIBRATION",
        "method": {
            "anonymousPairs": PAIR_COUNT,
            "thresholds": list(THRESHOLDS),
            "metrics": ["D1 lane-seed geometric mean", "D2 lane-seed median"],
            "independentSuperblocksPerCell": 3,
            "runtimePreferredCeilingSeconds": 180,
            "runtimeHardPlanningCeilingSeconds": 300,
        },
        "cells": cell_rows,
        "factorLevelBoundaries": factor_boundaries,
        "summary": {
            "cells": len(cell_rows),
            "cellsAllSixDistinctAt5Percent": sum(row["allSixOperationallyDistinctAt5Percent"] for row in cell_rows),
            "cellsAllSixDistinctAt10Percent": sum(row["allSixOperationallyDistinctAt10Percent"] for row in cell_rows),
            "cellsAllSixDistinctAt20Percent": sum(row["allSixOperationallyDistinctAt20Percent"] for row in cell_rows),
            "cellsWithinPreferred180SecondCeiling": sum(row["withinPreferred180SecondCeiling"] for row in cell_rows),
            "cellsWithinHard300SecondCeiling": sum(row["withinHard300SecondCeiling"] for row in cell_rows),
        },
        "boundary": "Anonymous descriptive pilot calibration only; not a hypothesis test or formal effect analysis.",
        "algorithmIdentityMappingRead": False,
        "rankingOrWinnerProduced": False,
    }
    dump_json(root / "cell-discrimination-runtime.v1.json", output)
    dump_json(root / "factor-level-boundaries.v1.json", {
        "schema": "gate14re-me-gnf-factor-level-boundaries-v1",
        "studyId": "Gate14Re-ME",
        "designAttemptId": "gnf-discrimination-window-design-v1-attempt-001",
        "factorLevelBoundaries": factor_boundaries,
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
