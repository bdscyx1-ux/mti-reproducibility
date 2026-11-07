from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter, defaultdict
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def stable_write_new(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise RuntimeError(f"create-new output exists: {path}")
    temporary = path.parent / f".g13tmp-{os.urandom(16).hex()}"
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
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
    formal_status = project / "Research/Gate13R_PR2_Formal_Execution_Status.v1.json"
    checks: list[dict] = []

    def check(name: str, passed: bool, detail=None) -> None:
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
        "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json": "805200a362440918682317f3ecf4fdb35fa441a1459457700a0f5f2a43a113df",
        "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md": "1641c22ddcb788f46ee1b2956f3bf8c8e13312459b5c22b139396001823085a5",
        "Research/Gate13R_PR2_Formal_Execution_Authorization.v2.json": "b39323958710c4962cf868ae3ba6057f42649e8f23fb7f5feb04ffd12c438759",
        "Research/Gate13R_PR2_TwoPhaseCommit_Supplemental_Authorization.v1.txt": "4af69eb71362f89698d38760db335985a015af49f176dd7f81805cb6d2d4821a",
        "Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs": "a47a731c979d58304230a150947ca1bb50207d13d1214b7d4de6e683bba6b5d6",
        "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs": "af9156588bc259dfa8cafeec4adb82c93a2b07f5e2ae772b4b0fd4115dce28a8",
        "Research/Gate13RPR2FormalExecutionV3.psm1": "5eaf15a3f1891d17849cf5c417aabaa03bcac7d25771e83ab905060b2db74b74",
        "Research/Run-Gate13RPR2FormalBlockV4.ps1": "30bf36239aaf321a4d454bf71f777a668476b1b962021d30ec3bb4d6abe25f54",
        "Research/Run-Gate13RPR2FormalCampaignV4.ps1": "66821f7642a260a80a5ea30f3e45a4e93e4dbc0c78095a3bcf2800d86bf65b53",
        "Research/Run-Gate13RPR2FormalTelemetryProbeV3.ps1": "7bad2277fe642881c3289fc25333e16b2353b1676686bc114a584d47e3b07dbc",
        "Research/Run-Gate13RPR2FormalUnitySelfTestsV3.ps1": "a05ac8097d9fc2d5bc39e2cd08ca7e0b6d8208db99ca5d2b8e8f85b337513918",
        "Research/Test-Gate13RPR2FormalExecutionV4.ps1": "c0814b287f7d2fe54298ecd6f38e3427cbf41cbc4db8f50c85a9cd8b7e704e14",
        "Research/Gate13R_PR2_Formal_Execution_Adapter_Provenance.v3.json": "0f264fb4a8d246a893a077a8c3f66426394274cd112887b0d49f5aba164a72b7",
    }
    for relative, digest in expected.items():
        path = project / relative
        check(f"hash-{Path(relative).name}", path.is_file() and sha256(path) == digest)

    config = load_json(project / "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json")
    manifest = load_json(project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json")
    amendment = load_json(project / "Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json")
    authorization = load_json(project / "Research/Gate13R_PR2_Formal_Execution_Authorization.v2.json")
    provenance = load_json(project / "Research/Gate13R_PR2_Formal_Execution_Adapter_Provenance.v3.json")
    check(
        "config-counts",
        config["totals"]["campaignCount"] == 74
        and config["totals"]["processCount"] == 3552
        and config["totals"]["sampleCount"] == 10176
        and config["totals"]["heterogeneousMatchedSuperblockCount"] == 1008,
    )
    check(
        "config-strict-serial",
        config["processSemantics"]["strictSerial"] is True
        and config["processSemantics"]["maximumConcurrentUnityEditorProcesses"] == 1
        and config["processSemantics"]["crossBlockReuseAllowed"] is False,
    )
    check(
        "authorization-two-phase-boundary",
        authorization["authorizationId"] == "gate13r-pr2-s48-h48-formal-raw-acquisition-two-phase-authorization-v2"
        and authorization["authorizedScope"]["formalRawAcquisitionAttemptCount"] == 1
        and authorization["authorizedScope"]["formalStatisticalAnalysisAuthorized"] is False
        and authorization["authorizedScope"]["gate14RAuthorized"] is False,
    )
    check("two-phase-frozen-before-data", amendment["status"] == "FROZEN-BEFORE-FORMAL-DATA")
    check("two-phase-no-science-change", amendment["changesScientificEstimands"] is False and amendment["changesScheduleOrSampleCount"] is False)
    check("raw-terminal-tokens", amendment["phase1RawAcquisition"]["requiredTerminalTokens"] == ["RAW-DATA-COMPLETE", "ANALYSIS-PENDING", "IMMUTABLE"])
    check("post-collection-tooling-no-unity-rerun", amendment["postCollectionRawCommitRecovery"]["rerunUnityAllowed"] is False)
    check("analysis-separate-not-authorized", amendment["phase2Analysis"]["authorizedByThisAmendment"] is False and amendment["phase2Analysis"]["rawRootWriteAllowed"] is False)
    check(
        "provenance-binds-current-implementation",
        provenance["authorization"]["sha256"] == expected["Research/Gate13R_PR2_Formal_Execution_Authorization.v2.json"]
        and provenance["twoPhaseCommit"]["amendment"]["sha256"] == expected["Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json"]
        and provenance["processContract"]["processCount"] == 3552,
    )

    schedule_path = project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    expected_algorithms = {
        "four-algorithm-shared-goal-v1": ["A*-R", "D*L", "C-FF", "IDFF"],
        "per-agent-heterogeneous-goal-v1": ["A*-R", "D*L"],
        "grouped-field-heterogeneous-goal-v1": ["C-FF", "IDFF"],
    }
    process_count = 0
    sample_count = 0
    run_ids: set[str] = set()
    block_ids: set[str] = set()
    outputs: set[str] = set()
    campaign_processes = Counter()
    campaign_samples = Counter()
    shared_campaigns: set[str] = set()
    heterogeneous_campaigns: set[str] = set()
    superblocks: dict[str, list[dict]] = defaultdict(list)
    order_by_scenario: dict[str, Counter] = defaultdict(Counter)
    order_row_by_scenario_cohort: dict[tuple[str, str], Counter] = defaultdict(Counter)
    schedule_errors: list[str] = []
    with schedule_path.open("r", encoding="utf-8") as stream:
        for expected_ordinal, line in enumerate(stream, 1):
            record = json.loads(line)
            process_count += 1
            entries = record["entries"]
            sample_count += len(entries)
            if record["globalProcessOrdinal"] != expected_ordinal:
                schedule_errors.append(f"ordinal-{expected_ordinal}")
            if record["blockId"] in block_ids:
                schedule_errors.append(f"duplicate-block-{record['blockId']}")
            block_ids.add(record["blockId"])
            if record["outputRelativePath"] in outputs:
                schedule_errors.append(f"duplicate-output-{expected_ordinal}")
            outputs.add(record["outputRelativePath"])
            campaign_processes[record["campaignId"]] += 1
            campaign_samples[record["campaignId"]] += len(entries)
            cohort = record["comparisonCohortId"]
            if [entry["algorithmId"] for entry in entries] != williams(expected_algorithms[cohort], record["williamsRowIndex"]):
                schedule_errors.append(f"williams-{expected_ordinal}")
            for position, entry in enumerate(entries, 1):
                predecessor = "NONE" if position == 1 else entries[position - 2]["algorithmId"]
                if entry["position"] != position or entry["predecessorAlgorithmId"] != predecessor:
                    schedule_errors.append(f"position-predecessor-{expected_ordinal}-{position}")
                if entry["runId"] in run_ids:
                    schedule_errors.append(f"duplicate-run-{entry['runId']}")
                run_ids.add(entry["runId"])
                child_output = f"{record['outputRelativePath'].rstrip('/')}/{entry['childDirectory'].lstrip('/')}"
                if child_output in outputs:
                    schedule_errors.append(f"duplicate-child-output-{child_output}")
                outputs.add(child_output)
            matched = record.get("matchedSuperblock")
            if matched:
                heterogeneous_campaigns.add(record["campaignId"])
                superblock_id = matched["matchedSuperblockId"]
                superblocks[superblock_id].append(record)
                order_row_by_scenario_cohort[(record["scenarioId"], cohort)][f"{matched['cohortOrder']}|{record['williamsRowIndex']}"] += 1
            else:
                shared_campaigns.add(record["campaignId"])

    for superblock_id, records in superblocks.items():
        if len(records) != 2:
            schedule_errors.append(f"superblock-process-count-{superblock_id}")
            continue
        scenarios = {record["scenarioId"] for record in records}
        orders = {record["matchedSuperblock"]["cohortOrder"] for record in records}
        cohorts = {record["comparisonCohortId"] for record in records}
        ordinals = {record["matchedSuperblock"]["matchedSuperblockOrdinal"] for record in records}
        if len(scenarios) != 1 or len(orders) != 1 or len(ordinals) != 1 or cohorts != {"per-agent-heterogeneous-goal-v1", "grouped-field-heterogeneous-goal-v1"}:
            schedule_errors.append(f"superblock-pair-{superblock_id}")
            continue
        order_by_scenario[next(iter(scenarios))][next(iter(orders))] += 1

    check("schedule-cardinality", process_count == 3552 and sample_count == 10176)
    check("schedule-manifest-cardinality", manifest["totals"]["processCount"] == process_count and manifest["totals"]["sampleCount"] == sample_count)
    check("schedule-identities-unique", len(block_ids) == 3552 and len(run_ids) == 10176 and len(outputs) == 13728)
    check("schedule-campaign-counts", len(campaign_processes) == 74 and len(shared_campaigns) == 32 and len(heterogeneous_campaigns) == 42)
    check("schedule-every-campaign-48-processes", set(campaign_processes.values()) == {48})
    check("schedule-shared-and-heterogeneous-samples", all(campaign_samples[campaign] == 192 for campaign in shared_campaigns) and all(campaign_samples[campaign] == 96 for campaign in heterogeneous_campaigns))
    check("schedule-matched-superblocks", len(superblocks) == 1008 and all(len(records) == 2 for records in superblocks.values()))
    check("schedule-ab-ba-24-24-per-scenario", len(order_by_scenario) == 21 and all(counts == Counter({"AB": 24, "BA": 24}) for counts in order_by_scenario.values()), {key: dict(value) for key, value in sorted(order_by_scenario.items())})
    check("schedule-order-row-12-per-cell", len(order_row_by_scenario_cohort) == 42 and all(len(cells) == 4 and set(cells.values()) == {12} for cells in order_row_by_scenario_cohort.values()))
    check("schedule-content-errors-zero", not schedule_errors, schedule_errors[:50])

    source_path = project / "Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs"
    target_path = project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs"
    derivation = load_json(project / "Research/Gate13R_PR2_Formal_Unity_Adapter_Derivation_Receipt.v2.json")
    mechanically_derived = source_path.read_text(encoding="utf-8-sig")
    route_counts_ok = True
    for route in derivation["routes"]:
        route_counts_ok &= mechanically_derived.count(route["from"]) == route["replacementCount"]
        mechanically_derived = mechanically_derived.replace(route["from"], route["to"])
    target = target_path.read_text(encoding="utf-8-sig")
    check("adapter-route-counts", route_counts_ok)
    check("adapter-exact-mechanical-derivation", mechanically_derived == target)

    block_script = (project / "Research/Run-Gate13RPR2FormalBlockV4.ps1").read_text(encoding="utf-8-sig")
    campaign_script = (project / "Research/Run-Gate13RPR2FormalCampaignV4.ps1").read_text(encoding="utf-8-sig")
    module_script = (project / "Research/Gate13RPR2FormalExecutionV3.psm1").read_text(encoding="utf-8-sig")
    check("block-fail-closed-tokens", all(token in block_script for token in ["automaticRetryAttempted = $false", "automaticResumeAttempted = $false", "hardMemoryRulesPassed"]))
    check("campaign-exact-root", "Research\\FormalRuns\\Gate13R_RQAligned_S48H48\\v1" in campaign_script)
    check("campaign-current-bindings", all(token in campaign_script for token in ["Formal_Execution_Authorization.v2.json", "supplementalAuthorizationSha256", "twoPhaseSpecificationSha256", "FormalBlockV4.ps1", "FormalExecutionV3.psm1"]))
    check("campaign-terminal-two-phase-state", "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE" in campaign_script)
    check("campaign-tool-failure-no-unity-rerun", "UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN" in campaign_script)
    check("campaign-no-analysis-invocation", "bootstrap" not in campaign_script.lower() and "Research/Analysis/" not in campaign_script.replace("\\", "/"))
    check("module-non-self-referential-exclusions", all(name in module_script for name in ["raw-execution-manifest.json", "raw-payload-file-manifest.jsonl", "raw-data-freeze-receipt.json", "environment-end-snapshot.json"]))
    check("module-read-only-freeze", "Set-G13RPR2RawPayloadReadOnly" in module_script)
    check("module-two-phase-receipt-policy", all(token in module_script for token in ["twoPhaseCommitRequired", "ordinaryPostCollectionToolFailureMayRerunUnity", "analysisFailureMayRerunUnity", "supplementalAuthorizationId"]))
    check("formal-root-absent", not formal_root.exists())
    check("formal-receipt-absent", not formal_receipt.exists())
    check("formal-status-absent", not formal_status.exists())
    check("project-lock-absent", not (project / "Temp/UnityLockfile").exists())

    failed = [row["name"] for row in checks if not row["passed"]]
    summary = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-formal-execution-active-v3-v4-static-and-deterministic-schedule-validation-v1",
        "checkCount": len(checks),
        "passedCheckCount": len(checks) - len(failed),
        "failedCheckCount": len(failed),
        "failedCheckNames": failed,
        "checks": checks,
        "reconstructed": {
            "campaignCount": len(campaign_processes),
            "processCount": process_count,
            "sampleCount": sample_count,
            "sharedCampaignCount": len(shared_campaigns),
            "heterogeneousCampaignCount": len(heterogeneous_campaigns),
            "heterogeneousScenarioCount": len(order_by_scenario),
            "matchedSuperblockCount": len(superblocks),
            "uniqueBlockIdCount": len(block_ids),
            "uniqueRunIdCount": len(run_ids),
            "uniqueOutputIdentityCount": len(outputs),
        },
        "formalRootAbsent": not formal_root.exists(),
        "formalExecutionReceiptAbsent": not formal_receipt.exists(),
        "formalStatusAbsent": not formal_status.exists(),
        "unityLaunched": False,
        "passed": not failed,
    }
    stable_write_new(output, summary)
    print(json.dumps({key: summary[key] for key in ("checkCount", "passedCheckCount", "failedCheckCount", "failedCheckNames", "reconstructed", "passed")}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
