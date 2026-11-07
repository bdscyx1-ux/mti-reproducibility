from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter, defaultdict
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def stable_write_new(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise RuntimeError(f"create-new output exists: {path}")
    temporary = path.parent / f".g13tmp-{os.urandom(16).hex()}"
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def williams(items: list[str], row: int) -> list[str]:
    count = len(items)
    base = [0]
    for step in range(1, count):
        base.append((step + 1) // 2 if step % 2 else count - step // 2)
    return [items[(index + row) % count] for index in base]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = Path(args.project).resolve()
    output = Path(args.output).resolve()
    formal_root = project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v1"
    formal_receipt = project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v1.json"
    checks: list[dict] = []

    def check(name: str, passed: bool, detail=None):
        row = {"name": name, "passed": bool(passed)}
        if detail is not None:
            row["detail"] = detail
        checks.append(row)

    expected = {
        "Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json": "669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc",
        "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json": "87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e",
        "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl": "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae",
        "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json": "b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724",
        "Research/Gate13R_PR2_Storage_WallClock_Preflight.v2.json": "c474499e647d5ad32efe01d199ede187b61f004e9487b8278e44109258cd0435",
        "Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json": "9e81530bcf6d32dd1792c8bd693d72988bef6f37e59a1ad154019ca228908e56",
        "Research/Gate13R_PR2_Formal_Preparation_Schema.v2.json": "940bfca8cb3e677deadff2600471eeaec9e99ff6bab9a06a625a0f30365a9d1e",
        "Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs": "a47a731c979d58304230a150947ca1bb50207d13d1214b7d4de6e683bba6b5d6",
    }
    for relative, digest in expected.items():
        path = project / relative
        check(f"hash-{Path(relative).name}", path.is_file() and sha256(path) == digest)

    config = load_json(project / "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json")
    amendment = load_json(project / "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json")
    check("config-counts", config["totals"]["processCount"] == 3552 and config["totals"]["sampleCount"] == 10176)
    check("config-strict-serial", config["processSemantics"]["strictSerial"] is True and config["processSemantics"]["maximumConcurrentUnityEditorProcesses"] == 1)
    check("two-phase-frozen-before-data", amendment["status"] == "FROZEN-BEFORE-FORMAL-DATA")
    check("two-phase-no-science-change", amendment["changesScientificEstimands"] is False and amendment["changesScheduleOrSampleCount"] is False)
    check("raw-terminal-tokens", amendment["phase1RawAcquisition"]["requiredTerminalTokens"] == ["RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"])
    check("post-collection-tooling-no-unity-rerun", amendment["postCollectionRawCommitRecovery"]["rerunUnityAllowed"] is False)
    check("analysis-separate-not-authorized", amendment["phase2Analysis"]["authorizedByThisAmendment"] is False and amendment["phase2Analysis"]["rawRootWriteAllowed"] is False)

    source_path = project / "Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs"
    target_path = project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV1.cs"
    derivation = load_json(project / "Research/Gate13R_PR2_Formal_Unity_Adapter_Derivation_Receipt.v1.json")
    source = source_path.read_text(encoding="utf-8-sig")
    mechanically_derived = source
    route_counts_ok = True
    for route in derivation["routes"]:
        count = mechanically_derived.count(route["from"])
        route_counts_ok &= count == route["replacementCount"]
        mechanically_derived = mechanically_derived.replace(route["from"], route["to"])
    check("adapter-route-counts", route_counts_ok)
    target = target_path.read_text(encoding="utf-8-sig")
    check("adapter-exact-mechanical-derivation", mechanically_derived == target)
    check("adapter-target-hash", sha256(target_path) == derivation["targetSha256"])
    check("adapter-source-still-frozen", sha256(source_path) == derivation["sourceSha256"])
    required_adapter_tokens = [
        "Gate13RPR2FormalBatchCommandV1",
        "if (!plan.formalCampaign)",
        'plan.analysisRole, "formal-timing"',
        "expectedAlgorithms.Length != 2 && expectedAlgorithms.Length != 4",
        "plan.verificationInjectedFailurePosition != 0",
        "executionReceiptRelativePath",
        "executionReceiptSha256",
        "SampleManagedAlertThresholdBytes = 134217728L",
        "SampleManagedEmergencyStopBytes = 268435456L",
        "TwoSampleBlockManagedGrowthLimitBytes = 268435456L",
        "NativeGrowthLimitBytes = 536870912L",
    ]
    check("adapter-required-tokens", all(token in target for token in required_adapter_tokens))
    forbidden_adapter_tokens = [
        "This command invocation is not authorized to produce formal samples.",
        "accepts only a two-sample heterogeneous Williams block",
        "pilotPlanRelativePath",
        "telemetryProbeResultRelativePath",
    ]
    check("adapter-forbidden-tokens-absent", all(token not in target for token in forbidden_adapter_tokens))

    schedule_path = project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    process_count = sample_count = 0
    run_ids: set[str] = set()
    block_ids: set[str] = set()
    outputs: set[str] = set()
    campaign_blocks = Counter()
    hetero_orders = defaultdict(Counter)
    row_cells = defaultdict(Counter)
    schedule_errors: list[str] = []
    expected_algorithms = {
        "four-algorithm-shared-goal-v1": ["A*-R", "D*L", "C-FF", "IDFF"],
        "per-agent-heterogeneous-goal-v1": ["A*-R", "D*L"],
        "grouped-field-heterogeneous-goal-v1": ["C-FF", "IDFF"],
    }
    with schedule_path.open("r", encoding="utf-8") as stream:
        for ordinal, line in enumerate(stream, 1):
            record = json.loads(line)
            process_count += 1
            if record["globalProcessOrdinal"] != ordinal:
                schedule_errors.append(f"ordinal-{ordinal}")
            if record["blockId"] in block_ids:
                schedule_errors.append(f"duplicate-block-{record['blockId']}")
            block_ids.add(record["blockId"])
            if record["outputRelativePath"] in outputs:
                schedule_errors.append(f"duplicate-output-{ordinal}")
            outputs.add(record["outputRelativePath"])
            cohort = record["comparisonCohortId"]
            entries = record["entries"]
            sample_count += len(entries)
            expected_row = williams(expected_algorithms[cohort], (record["campaignBlockOrdinal"] - 1) % len(expected_algorithms[cohort]))
            actual_row = [entry["algorithmId"] for entry in entries]
            if expected_row != actual_row:
                schedule_errors.append(f"williams-{ordinal}")
            for position, entry in enumerate(entries, 1):
                if entry["position"] != position or entry["predecessorAlgorithmId"] != ("NONE" if position == 1 else entries[position - 2]["algorithmId"]):
                    schedule_errors.append(f"position-predecessor-{ordinal}-{position}")
                if entry["runId"] in run_ids:
                    schedule_errors.append(f"duplicate-run-{entry['runId']}")
                run_ids.add(entry["runId"])
                if entry["childDirectory"] in outputs:
                    schedule_errors.append(f"duplicate-child-output-{entry['childDirectory']}")
                outputs.add(entry["childDirectory"])
            campaign_blocks[record["campaignId"]] += 1
            matched = record.get("matchedSuperblock")
            if matched:
                scenario = record["scenarioId"]
                hetero_orders[scenario][matched["cohortOrder"]] += 1
                row_cells[scenario][f"{matched['cohortOrder']}|{record['williamsRowIndex']}"] += 1
    check("schedule-cardinality", process_count == 3552 and sample_count == 10176)
    check("schedule-identities-unique", len(block_ids) == 3552 and len(run_ids) == 10176 and len(outputs) == 13728)
    check("schedule-all-campaigns-48", len(campaign_blocks) == 74 and set(campaign_blocks.values()) == {48})
    check("schedule-ab-ba-24-24", len(hetero_orders) == 21 and all(counts == Counter({"AB": 48, "BA": 48}) or counts == Counter({"AB": 24, "BA": 24}) for counts in hetero_orders.values()), dict(hetero_orders))
    # Each scenario has two process records per superblock, so order labels occur twice per superblock.
    check("schedule-order-row-12-per-cohort-cell", all(all(value == 24 for value in cells.values()) and len(cells) == 4 for cells in row_cells.values()))
    check("schedule-content-errors-zero", not schedule_errors, schedule_errors[:20])

    block_script = (project / "Research/Run-Gate13RPR2FormalBlockV1.ps1").read_text(encoding="utf-8-sig")
    campaign_script = (project / "Research/Run-Gate13RPR2FormalCampaignV1.ps1").read_text(encoding="utf-8-sig")
    module_script = (project / "Research/Gate13RPR2FormalExecutionV1.psm1").read_text(encoding="utf-8-sig")
    check("block-fail-closed-tokens", all(token in block_script for token in ["automaticRetryAttempted = $false", "automaticResumeAttempted = $false", "hardMemoryRulesPassed"]))
    check("campaign-exact-root", "Research\\FormalRuns\\Gate13R_RQAligned_S48H48\\v1" in campaign_script)
    check("campaign-terminal-two-phase-state", "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE" in campaign_script)
    check("campaign-tool-failure-no-unity-rerun", "UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN" in campaign_script)
    check("campaign-no-analysis-invocation", "Gate14" not in campaign_script and "bootstrap" not in campaign_script.lower())
    check("module-non-self-referential-exclusions", all(name in module_script for name in ["raw-execution-manifest.json", "raw-payload-file-manifest.jsonl", "raw-data-freeze-receipt.json"]))
    check("module-read-only-freeze", "Set-G13RPR2RawPayloadReadOnly" in module_script)
    check("formal-root-absent", not formal_root.exists())
    check("formal-receipt-absent", not formal_receipt.exists())

    failed = [row["name"] for row in checks if not row["passed"]]
    summary = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-formal-execution-adapter-static-and-schedule-validation-v1",
        "checkCount": len(checks),
        "passedCheckCount": len(checks) - len(failed),
        "failedCheckCount": len(failed),
        "failedCheckNames": failed,
        "checks": checks,
        "formalRootAbsent": not formal_root.exists(),
        "formalExecutionReceiptAbsent": not formal_receipt.exists(),
        "unityLaunched": False,
        "passed": not failed,
    }
    stable_write_new(output, summary)
    print(json.dumps({key: summary[key] for key in ("checkCount", "passedCheckCount", "failedCheckCount", "failedCheckNames", "passed")}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
