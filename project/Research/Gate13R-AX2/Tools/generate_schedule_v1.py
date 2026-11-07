#!/usr/bin/env python3
"""Generate the frozen Gate13R-AX2 schedule from Gate 13R structural metadata only."""

from __future__ import annotations

import hashlib
import json
from collections import Counter, OrderedDict
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_SCHEDULE = PROJECT_ROOT / "Research" / "Gate13R_Formal_Williams_Block_Schedule.v1.jsonl"
SOURCE_CATALOG = PROJECT_ROOT / "Research" / "FormalScenarios" / "Gate11R_5pct" / "v1" / "catalog.json"
SOURCE_MATRIX = PROJECT_ROOT / "Research" / "FormalScenarios" / "Gate11R_5pct" / "v1" / "formal-scenario-matrix.json"
SOURCE_BUNDLE_MANIFEST = PROJECT_ROOT / "Research" / "FormalScenarios" / "Gate11R_5pct" / "v1" / "bundle-manifest.json"
OUTPUT_DIR = PROJECT_ROOT / "Research" / "Gate13R-AX2" / "Execution" / "v1"
OUTPUT_SCHEDULE = OUTPUT_DIR / "formal-williams-schedule.v1.jsonl"
OUTPUT_MANIFEST = OUTPUT_DIR / "formal-williams-schedule-manifest.v1.json"

SOURCE_SHARED_COHORT = "four-algorithm-shared-goal-v1"
TARGET_COHORT = "gate13r-ax2-shared-goal-v1"
ALGORITHMS = ("BiA*-R", "LPA*", "C-FF", "IDFF")
SLUGS = {
    "BiA*-R": "biastar-r",
    "LPA*": "lpa-star",
    "C-FF": "cff",
    "IDFF": "idff",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def williams_row(row_index: int) -> list[str]:
    count = len(ALGORITHMS)
    base_indices = [0]
    for step in range(1, count):
        base_indices.append((step + 1) // 2 if step % 2 == 1 else count - (step // 2))
    return [ALGORITHMS[(base_indices[index] + row_index) % count] for index in range(count)]


def load_shared_records() -> list[dict]:
    records: list[dict] = []
    with SOURCE_SCHEDULE.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, start=1):
            raw = raw.strip()
            if not raw:
                continue
            record = json.loads(raw)
            if (record.get("comparisonCohortId") == SOURCE_SHARED_COHORT and
                    1 <= int(record.get("campaignBlockOrdinal", 0)) <= 48):
                record["_sourceLineNumber"] = line_number
                records.append(record)
    return records


def main() -> None:
    source_records = load_shared_records()
    campaigns: OrderedDict[str, list[dict]] = OrderedDict()
    for record in source_records:
        campaigns.setdefault(record["campaignId"], []).append(record)

    if len(campaigns) != 32:
        raise RuntimeError(f"Expected 32 shared campaigns, found {len(campaigns)}")
    if len(source_records) != 1536:
        raise RuntimeError(f"Expected 1536 source shared blocks, found {len(source_records)}")

    output_records: list[dict] = []
    position_counts: dict[str, Counter[int]] = {algorithm: Counter() for algorithm in ALGORITHMS}
    row_counts: Counter[int] = Counter()
    global_ordinal = 0

    for campaign_ordinal, (campaign_id, records) in enumerate(campaigns.items(), start=1):
        records.sort(key=lambda item: int(item["campaignBlockOrdinal"]))
        if len(records) != 48:
            raise RuntimeError(f"Campaign {campaign_id} has {len(records)} blocks, expected 48")
        if [int(item["campaignBlockOrdinal"]) for item in records] != list(range(1, 49)):
            raise RuntimeError(f"Campaign {campaign_id} does not contain contiguous blocks 1..48")

        for source in records:
            global_ordinal += 1
            block_ordinal = int(source["campaignBlockOrdinal"])
            row_index = (block_ordinal - 1) % 4
            if int(source["williamsRowIndex"]) != row_index:
                raise RuntimeError(f"Source Williams row drift in {campaign_id} block {block_ordinal}")
            row = williams_row(row_index)
            row_counts[row_index] += 1
            block_id = f"g13rax2-c{campaign_ordinal:02d}-b{block_ordinal:04d}"
            entries: list[dict] = []
            predecessor = "NONE"
            for position, algorithm_id in enumerate(row, start=1):
                slug = SLUGS[algorithm_id]
                run_id = f"{block_id}-p{position:02d}-{slug}"
                child_directory = f"runs/p{position:02d}-{slug}"
                entries.append(
                    {
                        "position": position,
                        "algorithmId": algorithm_id,
                        "predecessorAlgorithmId": predecessor,
                        "runId": run_id,
                        "childDirectory": child_directory,
                        "sampleOutputRelativePath": (
                            f"campaigns/c{campaign_ordinal:02d}-{campaign_id}/blocks/"
                            f"b{block_ordinal:04d}/{child_directory}"
                        ),
                    }
                )
                position_counts[algorithm_id][position] += 1
                predecessor = algorithm_id

            output_records.append(
                {
                    "schemaVersion": 1,
                    "scheduleKind": "gate13r-ax2-formal-williams-block-schedule-record-v1",
                    "designId": "gate13r-ax2-shared32-b48-four-treatment-v1",
                    "globalBlockOrdinal": global_ordinal,
                    "campaignOrdinal": campaign_ordinal,
                    "campaignId": campaign_id,
                    "scenarioId": source["scenarioId"],
                    "scenarioRelativePath": source["scenarioRelativePath"],
                    "scenarioSha256": source["scenarioSha256"],
                    "scenarioFingerprintSha256": source["scenarioFingerprintSha256"],
                    "comparisonCohortId": TARGET_COHORT,
                    "campaignBlockOrdinal": block_ordinal,
                    "williamsRowIndex": row_index,
                    "blockId": block_id,
                    "outputRelativePath": f"campaigns/c{campaign_ordinal:02d}-{campaign_id}/blocks/b{block_ordinal:04d}",
                    "expectedSampleCount": 4,
                    "sceneAssetPath": source["sceneAssetPath"],
                    "sourceGate13RProfileAssetPath": source["profileAssetPath"],
                    "sourceGate13RProfileAssetGuid": source["profileAssetGuid"],
                    "sourceGate13RProfileSha256": source["profileSha256"],
                    "sourceGate13RScheduleLineNumber": source["_sourceLineNumber"],
                    "entries": entries,
                }
            )

    if global_ordinal != 1536:
        raise RuntimeError(f"Generated {global_ordinal} blocks, expected 1536")
    for algorithm_id in ALGORITHMS:
        for position in range(1, 5):
            if position_counts[algorithm_id][position] != 384:
                raise RuntimeError(
                    f"Position imbalance for {algorithm_id} at {position}: "
                    f"{position_counts[algorithm_id][position]} != 384"
                )
    if any(row_counts[row] != 384 for row in range(4)):
        raise RuntimeError(f"Williams row imbalance: {dict(row_counts)}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    schedule_bytes = ("\n".join(canonical_json(record) for record in output_records) + "\n").encode("utf-8")
    OUTPUT_SCHEDULE.write_bytes(schedule_bytes)
    schedule_sha256 = hashlib.sha256(schedule_bytes).hexdigest()

    manifest = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-AX2-FORMAL-WILLIAMS-SCHEDULE-MANIFEST",
        "designId": "gate13r-ax2-shared32-b48-four-treatment-v1",
        "status": "NON_EXECUTING_SCHEDULE_FROZEN",
        "sourceBindings": {
            "gate13rSchedule": {"path": str(SOURCE_SCHEDULE.relative_to(PROJECT_ROOT)).replace("\\", "/"), "sha256": sha256(SOURCE_SCHEDULE)},
            "gate11rCatalog": {"path": str(SOURCE_CATALOG.relative_to(PROJECT_ROOT)).replace("\\", "/"), "sha256": sha256(SOURCE_CATALOG)},
            "gate11rMatrix": {"path": str(SOURCE_MATRIX.relative_to(PROJECT_ROOT)).replace("\\", "/"), "sha256": sha256(SOURCE_MATRIX)},
            "gate11rBundleManifest": {"path": str(SOURCE_BUNDLE_MANIFEST.relative_to(PROJECT_ROOT)).replace("\\", "/"), "sha256": sha256(SOURCE_BUNDLE_MANIFEST)},
        },
        "algorithmIdsInBaseOrder": list(ALGORITHMS),
        "primaryContrasts": [
            "BiA*-R/C-FF",
            "BiA*-R/IDFF",
            "LPA*/C-FF",
            "LPA*/IDFF",
        ],
        "campaignCount": 32,
        "blocksPerCampaign": 48,
        "completeBlockCount": 1536,
        "algorithmSampleCount": 6144,
        "perAlgorithmSampleCount": 1536,
        "williamsRowCounts": {str(row): row_counts[row] for row in range(4)},
        "perAlgorithmPositionCounts": {
            algorithm: {str(position): position_counts[algorithm][position] for position in range(1, 5)}
            for algorithm in ALGORITHMS
        },
        "campaignIdsInExecutionOrder": list(campaigns.keys()),
        "schedule": {
            "path": str(OUTPUT_SCHEDULE.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "sha256": schedule_sha256,
            "lineCount": len(output_records),
        },
        "formalCollectionAuthorized": False,
    }
    OUTPUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(canonical_json({"scheduleSha256": schedule_sha256, "blocks": len(output_records), "campaigns": len(campaigns)}))


if __name__ == "__main__":
    main()

