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
    if path.exists():
        raise RuntimeError(f"create-new output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
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
    checks: list[dict] = []

    def check(name: str, passed: bool, detail=None) -> None:
        row = {"name": name, "passed": bool(passed)}
        if detail is not None:
            row["detail"] = detail
        checks.append(row)

    frozen = {
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
        "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs": "af9156588bc259dfa8cafeec4adb82c93a2b07f5e2ae772b4b0fd4115dce28a8",
        "Research/Gate13RPR2FormalExecutionV3.psm1": "5eaf15a3f1891d17849cf5c417aabaa03bcac7d25771e83ab905060b2db74b74",
        "Research/Run-Gate13RPR2FormalBlockV4.ps1": "30bf36239aaf321a4d454bf71f777a668476b1b962021d30ec3bb4d6abe25f54",
        "Research/Run-Gate13RPR2FormalCampaignV4.ps1": "66821f7642a260a80a5ea30f3e45a4e93e4dbc0c78095a3bcf2800d86bf65b53",
        "Research/Gate13R_PR2_Formal_Execution_Receipt.v1.json": "2cd30b4d605f231bca64250e91a4e7df7548a10681853f84ad31620b970972bc",
        "Research/Gate13R_PR2_Formal_Execution_Status.v1.json": "a7dd97d766a23fc001ac2e8adca5f34206932906a8d6452de55fa43d28d544be",
        "Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-partial-tree-manifest.json": "93d6d9efd4232a3f995621d2ad5c62951dcbdf10f7ede13d9b37948aad755ab5",
    }
    for relative, expected in frozen.items():
        path = project / relative
        check(f"frozen-hash-{Path(relative).name}", path.is_file() and sha256(path) == expected)

    attempt1_manifest = load_json(project / "Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-partial-tree-manifest.json")
    attempt1_root = Path(attempt1_manifest["formalRoot"])
    attempt1_failures = []
    actual_bytes = 0
    for record in attempt1_manifest["files"]:
        path = attempt1_root / Path(record["relativePath"])
        if not path.is_file():
            attempt1_failures.append(f"missing:{record['relativePath']}")
            continue
        actual_bytes += path.stat().st_size
        if path.stat().st_size != record["rawBytes"] or sha256(path) != record["sha256"]:
            attempt1_failures.append(f"identity:{record['relativePath']}")
        if os.access(path, os.W_OK) and not bool(path.stat().st_file_attributes & 1):
            attempt1_failures.append(f"writable:{record['relativePath']}")
    actual_files = [path for path in attempt1_root.rglob("*") if path.is_file()]
    check(
        "attempt1-tree-preserved",
        not attempt1_failures
        and len(actual_files) == 31
        and len(attempt1_manifest["files"]) == 31
        and actual_bytes == 3338221
        and attempt1_manifest["canonicalTreeSha256"] == "026b9830f220b06af3f0a106f638b3d918d115ba08f5f06c13d9d76542ba4f56",
        attempt1_failures,
    )

    source = (project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs").read_text(encoding="utf-8")
    target = (project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV4.cs").read_text(encoding="utf-8")
    normalized = target.replace("public static class Gate13RPR2FormalBatchCommandV4", "public static class Gate13RPR2FormalBatchCommandV2", 1)
    normalized = normalized.replace("            public bool formalCampaign;\n            public bool completed;", "            public bool completed;", 1)
    normalized = normalized.replace("                formalCampaign = plan.formalCampaign,\n                completed = core.workloadCompleted", "                completed = core.workloadCompleted", 1)
    check("producer-exact-mechanical-diff", normalized == source)
    check("producer-required-field-once", target.count("public bool formalCampaign;\n            public bool completed;") == 1)
    check("producer-required-assignment-once", target.count("formalCampaign = plan.formalCampaign,\n                completed = core.workloadCompleted") == 1)

    module = (project / "Research/Gate13RPR2FormalExecutionV5.psm1").read_text(encoding="utf-8-sig")
    wrapper = (project / "Research/Run-Gate13RPR2FormalBlockV6.ps1").read_text(encoding="utf-8-sig")
    campaign = (project / "Research/Run-Gate13RPR2FormalCampaignV6.ps1").read_text(encoding="utf-8-sig")
    check("module-strict-embedded-validator", all(token in module for token in ["embedded-formalCampaign-missing", "embedded-formalCampaign-type", "embedded-formalCampaign-false", "embedded-runId-duplicate"]))
    check("module-attempt2-receipt", all(token in module for token in ["formalAttemptOrdinal", "attempt1CanonicalTreeSha256", "execution-receipt-attempt-2-v1"]))
    check("wrapper-active-stack", all(token in wrapper for token in ["Gate13RPR2FormalExecutionV5.psm1", "Gate13RPR2FormalBatchCommandV4.Run", "Gate13R_RQAligned_S48H48\\v2"]))
    check("wrapper-rehearsal-boundary", all(token in wrapper for token in ["ValidationOnlyContractRehearsal", "excludedFromFormalAnalysis", "embeddedFormalCampaignContractPassed"]))
    check("wrapper-no-default-true", "formalCampaign = $true" not in wrapper[wrapper.find("$embeddedContract"):wrapper.find("$summary =")])
    check("campaign-active-stack", all(token in campaign for token in ["Gate13RPR2FormalExecutionV5.psm1", "Run-Gate13RPR2FormalBlockV6.ps1", "Gate13RPR2FormalBatchCommandV4.cs", "Gate13R_RQAligned_S48H48\\v2"]))
    check("campaign-attempt2-authorization", all(token in campaign for token in ["Gate13R_PR2_Attempt2_Execution_Authorization.v1.json", "attempt2AuthorizationSha256", "formalAttemptOrdinal = 2"]))
    check("campaign-dry-run", all(token in campaign for token in ["ValidationOnlyDryRun", "VALIDATION-ONLY-DRY-RUN-PASSED", "embeddedFormalCampaignContractPassed"]))
    check("campaign-two-phase", all(token in campaign for token in ["UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN", "RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE", "RAW-CONTRACT-VIOLATION / USER-DECISION-REQUIRED / NO-UNITY-RERUN"]))
    check("campaign-no-analysis-invocation", "bootstrap" not in campaign.lower() and "Research/Analysis/" not in campaign.replace("\\", "/"))

    config = load_json(project / "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json")
    schedule_manifest = load_json(project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json")
    check("config-cardinality", config["totals"]["campaignCount"] == 74 and config["totals"]["heterogeneousMatchedSuperblockCount"] == 1008 and config["totals"]["processCount"] == 3552 and config["totals"]["sampleCount"] == 10176)
    check("config-serial", config["processSemantics"]["strictSerial"] is True and config["processSemantics"]["maximumConcurrentUnityEditorProcesses"] == 1 and config["processSemantics"]["crossBlockReuseAllowed"] is False)

    algorithms = {
        "four-algorithm-shared-goal-v1": ["A*-R", "D*L", "C-FF", "IDFF"],
        "per-agent-heterogeneous-goal-v1": ["A*-R", "D*L"],
        "grouped-field-heterogeneous-goal-v1": ["C-FF", "IDFF"],
    }
    process_count = sample_count = 0
    block_ids: set[str] = set()
    run_ids: set[str] = set()
    outputs: set[str] = set()
    campaigns = Counter()
    campaign_samples = Counter()
    shared: set[str] = set()
    heterogeneous: set[str] = set()
    superblocks: dict[str, list[dict]] = defaultdict(list)
    orders: dict[str, Counter] = defaultdict(Counter)
    order_rows: dict[tuple[str, str], Counter] = defaultdict(Counter)
    errors: list[str] = []
    schedule_path = project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    with schedule_path.open("r", encoding="utf-8") as stream:
        for ordinal, line in enumerate(stream, 1):
            record = json.loads(line)
            process_count += 1
            entries = record["entries"]
            sample_count += len(entries)
            campaigns[record["campaignId"]] += 1
            campaign_samples[record["campaignId"]] += len(entries)
            if record["globalProcessOrdinal"] != ordinal:
                errors.append(f"ordinal-{ordinal}")
            if record["blockId"] in block_ids or record["outputRelativePath"] in outputs:
                errors.append(f"duplicate-block-output-{ordinal}")
            block_ids.add(record["blockId"]); outputs.add(record["outputRelativePath"])
            cohort = record["comparisonCohortId"]
            if [entry["algorithmId"] for entry in entries] != williams(algorithms[cohort], record["williamsRowIndex"]):
                errors.append(f"williams-{ordinal}")
            for position, entry in enumerate(entries, 1):
                predecessor = "NONE" if position == 1 else entries[position - 2]["algorithmId"]
                if entry["position"] != position or entry["predecessorAlgorithmId"] != predecessor or entry["runId"] in run_ids:
                    errors.append(f"entry-{ordinal}-{position}")
                run_ids.add(entry["runId"])
                child = f"{record['outputRelativePath'].rstrip('/')}/{entry['childDirectory'].lstrip('/')}"
                if child in outputs:
                    errors.append(f"child-output-{ordinal}-{position}")
                outputs.add(child)
            matched = record.get("matchedSuperblock")
            if matched:
                heterogeneous.add(record["campaignId"])
                superblocks[matched["matchedSuperblockId"]].append(record)
                order_rows[(record["scenarioId"], cohort)][f"{matched['cohortOrder']}|{record['williamsRowIndex']}"] += 1
            else:
                shared.add(record["campaignId"])
    for records in superblocks.values():
        if len(records) != 2:
            errors.append("superblock-count")
            continue
        scenarios = {record["scenarioId"] for record in records}
        order_set = {record["matchedSuperblock"]["cohortOrder"] for record in records}
        cohorts = {record["comparisonCohortId"] for record in records}
        if len(scenarios) != 1 or len(order_set) != 1 or cohorts != {"per-agent-heterogeneous-goal-v1", "grouped-field-heterogeneous-goal-v1"}:
            errors.append("superblock-pair")
        else:
            orders[next(iter(scenarios))][next(iter(order_set))] += 1
    check("schedule-cardinality", process_count == 3552 and sample_count == 10176 and schedule_manifest["processRecordCount"] == 3552 and schedule_manifest["sampleIdentityCount"] == 10176)
    check("schedule-identities", len(block_ids) == 3552 and len(run_ids) == 10176 and len(outputs) == 13728)
    check("schedule-campaigns", len(campaigns) == 74 and len(shared) == 32 and len(heterogeneous) == 42 and set(campaigns.values()) == {48})
    check("schedule-sample-counts", all(campaign_samples[c] == 192 for c in shared) and all(campaign_samples[c] == 96 for c in heterogeneous))
    check("schedule-superblocks", len(superblocks) == 1008 and all(len(records) == 2 for records in superblocks.values()))
    check("schedule-abba", len(orders) == 21 and all(value == Counter({"AB": 24, "BA": 24}) for value in orders.values()))
    check("schedule-order-row", len(order_rows) == 42 and all(len(value) == 4 and set(value.values()) == {12} for value in order_rows.values()))
    check("schedule-errors-zero", not errors, errors[:50])

    check("formal-root-v2-absent", not (project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v2").exists())
    check("formal-receipt-v2-absent", not (project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v2.json").exists())
    check("formal-status-v2-absent", not (project / "Research/Gate13R_PR2_Formal_Execution_Status.v2.json").exists())
    check("unity-lock-absent", not (project / "Temp/UnityLockfile").exists())

    failed = [row["name"] for row in checks if not row["passed"]]
    summary = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-static-deterministic-validation-v1",
        "checkCount": len(checks),
        "passedCheckCount": len(checks) - len(failed),
        "failedCheckCount": len(failed),
        "failedCheckNames": failed,
        "checks": checks,
        "reconstructed": {
            "campaignCount": len(campaigns),
            "processCount": process_count,
            "sampleCount": sample_count,
            "matchedSuperblockCount": len(superblocks),
            "uniqueRunIdCount": len(run_ids),
        },
        "formalRootV2Absent": not (project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v2").exists(),
        "unityStarted": False,
        "passed": not failed,
    }
    stable_write_new(output, summary)
    print(json.dumps({key: summary[key] for key in ("checkCount", "passedCheckCount", "failedCheckCount", "failedCheckNames", "reconstructed", "passed")}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
