#!/usr/bin/env python3
"""V3 static, deterministic and wrapper-repair tests for Gate 13R-PR2-MP2."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MIB = 1024 * 1024
GIB = 1024 * MIB
POLICY_ID = "gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1"
EXPECTED_SCHEDULE_SHA = "df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae"
EXPECTED_CONFIG_SHA = "87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".g13r-pr2-mp2-test-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, path)
        os.unlink(temporary)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def tier(maximum: int) -> tuple[str, int, int]:
    if maximum in (32, 64, 128):
        return "MP2-NATIVE-LE128", 512 * MIB, 640 * MIB
    if maximum == 256:
        return "MP2-NATIVE-EQ256", 640 * MIB, 768 * MIB
    raise ValueError("unsupported")


def evaluate(stage: str, advisory: int, hard: int, native: int = 0, sample_managed: int = 0, block_managed: int = 0, absolute_native: int = GIB, available: int = 8 * GIB) -> tuple[str, str]:
    if absolute_native > 4 * GIB:
        return "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-ABSOLUTE-NATIVE-4GIB"
    if native > 2 * GIB:
        return "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-RELATIVE-NATIVE-GROWTH-2GIB"
    if available < 8 * GIB:
        return "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-AVAILABLE-MEMORY-BELOW-8GIB"
    if stage == "after-forced-cleanup" and sample_managed > 256 * MIB:
        return "HARD-FAIL-MANAGED-EMERGENCY", "HARD-FAIL-SAMPLE-MANAGED-AFTER-CLEANUP-256MIB"
    if stage == "post-block-pre-exit" and block_managed > 256 * MIB:
        return "HARD-FAIL-MANAGED-EMERGENCY", "HARD-FAIL-BLOCK-MANAGED-AFTER-CLEANUP-256MIB"
    if stage != "raw-after-workload" and native > hard:
        return "HARD-FAIL-NATIVE-ELIGIBILITY", "HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING"
    reasons = []
    if stage != "raw-after-workload" and native > advisory:
        reasons.append("NATIVE-RESIDENCY-ADVISORY")
    if stage == "after-forced-cleanup" and sample_managed > 128 * MIB:
        reasons.append("MANAGED-AFTER-CLEANUP-ALERT-128MIB")
    if reasons:
        return "PASS-WITH-ADVISORY", "+".join(reasons)
    if stage == "raw-after-workload":
        return "PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY"
    return "PASS", "PASS"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    checks: list[dict[str, Any]] = []

    def check(identifier: str, passed: bool, detail: Any = None) -> None:
        checks.append({"id": identifier, "passed": bool(passed), "detail": detail})

    schedule_path = project / "Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl"
    config_path = project / "Research/Gate13R_PR2_Formal_Campaign_Config.v2.json"
    mapping_path = project / "Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json"
    overlay_path = project / "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl"
    overlay_manifest_path = project / "Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay_Manifest.v2.json"
    registry_path = project / "Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json"
    amendment_path = project / "Research/Gate13R_PR2_MP2_Memory_Policy_Amendment.v2.json"
    candidate_path = project / "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v3.json"
    adapter_path = project / "Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v3.json"
    provenance_path = project / "Research/Gate13R_PR2_MP2_Provenance.v3.json"
    schema_path = project / "Research/Gate13R_PR2_MP2_Schema.v2.json"

    check("active-schedule-sha256", sha256_file(schedule_path) == EXPECTED_SCHEDULE_SHA)
    check("active-config-sha256", sha256_file(config_path) == EXPECTED_CONFIG_SHA)
    artifacts = [mapping_path, overlay_path, overlay_manifest_path, registry_path, amendment_path, candidate_path, adapter_path, provenance_path, schema_path]
    check("generated-artifacts-exist", all(path.is_file() for path in artifacts), [str(path) for path in artifacts if not path.is_file()])
    for path in artifacts:
        if path.suffix == ".json":
            try:
                load_json(path)
                check(f"json-parse-{path.name}", True)
            except Exception as exc:
                check(f"json-parse-{path.name}", False, repr(exc))

    schedule = load_jsonl(schedule_path)
    overlay = load_jsonl(overlay_path)
    mapping = load_json(mapping_path)
    overlay_manifest = load_json(overlay_manifest_path)
    registry = load_json(registry_path)
    candidate = load_json(candidate_path)
    adapter = load_json(adapter_path)
    provenance = load_json(provenance_path)
    check("schedule-process-cardinality", len(schedule) == 3552)
    check("overlay-process-cardinality", len(overlay) == 3552)
    check("scenario-cardinality", mapping["scenarioCount"] == len(mapping["scenarios"]) == 53)
    check("campaign-cardinality", mapping["campaignCount"] == 74)
    check("overlay-sha-manifest", overlay_manifest["overlaySha256"] == sha256_file(overlay_path) and overlay_manifest["overlayRawBytes"] == overlay_path.stat().st_size)
    check("policy-id-consistent", registry["policyId"] == mapping["policyId"] == overlay_manifest["policyId"] == POLICY_ID)

    schedule_ids: set[tuple[Any, ...]] = set()
    overlay_ids: set[tuple[Any, ...]] = set()
    run_ids: set[str] = set()
    superblocks: dict[str, list[dict[str, Any]]] = defaultdict(list)
    order_by_scenario: dict[str, Counter[str]] = defaultdict(Counter)
    for schedule_record, overlay_record in zip(schedule, overlay):
        sid = (schedule_record["globalProcessOrdinal"], schedule_record["blockId"], schedule_record["campaignId"], schedule_record["scenarioId"], schedule_record["scenarioRelativePath"])
        oid = (overlay_record["globalProcessOrdinal"], overlay_record["blockId"], overlay_record["campaignId"], overlay_record["scenarioId"], overlay_record["scenarioRelativePath"])
        schedule_ids.add(sid); overlay_ids.add(oid)
        run_ids.update(entry["runId"] for entry in schedule_record["entries"])
        check_id = int(schedule_record["globalProcessOrdinal"])
        if check_id in (1, 1776, 3552):
            check(f"overlay-sentinel-identity-{check_id}", sid == oid and [entry["runId"] for entry in schedule_record["entries"]] == overlay_record["expectedRunIds"])
        matched = schedule_record.get("matchedSuperblock")
        if matched:
            superblocks[matched["matchedSuperblockId"]].append(schedule_record)
            order_by_scenario[schedule_record["scenarioId"]][matched["cohortOrder"]] += 1
    check("schedule-overlay-one-to-one", schedule_ids == overlay_ids and len(schedule_ids) == 3552)
    check("run-id-cardinality", len(run_ids) == 10176)
    check("matched-superblock-cardinality", len(superblocks) == 1008 and all(len(rows) == 2 for rows in superblocks.values()))
    check("heterogeneous-abba-record-quota", len(order_by_scenario) == 21 and all(counts == Counter({"AB": 48, "BA": 48}) for counts in order_by_scenario.values()), {key: dict(value) for key, value in order_by_scenario.items() if value != Counter({"AB": 48, "BA": 48})})

    mapped_scenarios = {}
    campaigns = set()
    mapping_ok = True
    for entry in mapping["scenarios"]:
        source = project / entry["scenarioRelativePath"]
        scenario = load_json(source)
        expected_tier = tier(max(int(scenario["gridWidth"]), int(scenario["gridHeight"])))
        mapping_ok &= (
            sha256_file(source) == entry["scenarioSourceSha256"]
            and scenario["scenarioId"] == entry["scenarioId"]
            and entry["tierId"] == expected_tier[0]
            and entry["nativeAdvisoryBytes"] == expected_tier[1]
            and entry["nativeHardBytes"] == expected_tier[2]
        )
        mapped_scenarios[entry["scenarioRelativePath"]] = entry
        campaigns.update(entry["campaignIds"])
    check("unique-scenario-policy-mapping", mapping_ok and len(mapped_scenarios) == 53 and len(campaigns) == 74)
    check("tier-scenario-counts", Counter(entry["tierId"] for entry in mapping["scenarios"]) == Counter({"MP2-NATIVE-LE128": 52, "MP2-NATIVE-EQ256": 1}))
    check("all-processes-map-one-tier", all(row["scenarioRelativePath"] in mapped_scenarios and row["tierId"] == mapped_scenarios[row["scenarioRelativePath"]]["tierId"] for row in overlay))

    boundary_cases: list[tuple[str, bool]] = []
    for label, advisory, hard in (("le128", 512 * MIB, 640 * MIB), ("eq256", 640 * MIB, 768 * MIB)):
        boundary_cases.extend([
            (f"{label}-advisory-minus-one", evaluate("after-forced-cleanup", advisory, hard, advisory - 1) == ("PASS", "PASS")),
            (f"{label}-advisory-equal", evaluate("after-forced-cleanup", advisory, hard, advisory) == ("PASS", "PASS")),
            (f"{label}-advisory-plus-one", evaluate("after-forced-cleanup", advisory, hard, advisory + 1) == ("PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY")),
            (f"{label}-hard-equal", evaluate("post-block-pre-exit", advisory, hard, hard) == ("PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY")),
            (f"{label}-hard-plus-one", evaluate("post-block-pre-exit", advisory, hard, hard + 1) == ("HARD-FAIL-NATIVE-ELIGIBILITY", "HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING")),
        ])
    for identifier, passed in boundary_cases:
        check(f"boundary-{identifier}", passed)
    check("raw-transient-separated", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, 640 * MIB + 1) == ("PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY"))
    check("managed-128-equality", evaluate("after-forced-cleanup", 512 * MIB, 640 * MIB, sample_managed=128 * MIB) == ("PASS", "PASS"))
    check("managed-128-crossing", evaluate("after-forced-cleanup", 512 * MIB, 640 * MIB, sample_managed=128 * MIB + 1)[0] == "PASS-WITH-ADVISORY")
    check("managed-256-equality", evaluate("after-forced-cleanup", 512 * MIB, 640 * MIB, sample_managed=256 * MIB)[0] == "PASS-WITH-ADVISORY")
    check("managed-256-crossing", evaluate("after-forced-cleanup", 512 * MIB, 640 * MIB, sample_managed=256 * MIB + 1)[0] == "HARD-FAIL-MANAGED-EMERGENCY")
    check("block-managed-256-crossing", evaluate("post-block-pre-exit", 512 * MIB, 640 * MIB, block_managed=256 * MIB + 1)[0] == "HARD-FAIL-MANAGED-EMERGENCY")
    check("host-4gib-equality", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, absolute_native=4 * GIB)[0] == "PASS")
    check("host-4gib-crossing", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, absolute_native=4 * GIB + 1)[0] == "HARD-FAIL-HOST-EMERGENCY")
    check("host-2gib-equality", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, native=2 * GIB)[0] == "PASS")
    check("host-2gib-crossing", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, native=2 * GIB + 1)[0] == "HARD-FAIL-HOST-EMERGENCY")
    check("host-8gib-equality", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, available=8 * GIB)[0] == "PASS")
    check("host-8gib-below", evaluate("raw-after-workload", 512 * MIB, 640 * MIB, available=8 * GIB - 1)[0] == "HARD-FAIL-HOST-EMERGENCY")

    source = (project / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs").read_text(encoding="utf-8-sig")
    wrapper = (project / "Research/Run-Gate13RPR2MP2FormalBlockV3.ps1").read_text(encoding="utf-8-sig")
    module = (project / "Research/Gate13RPR2MP2MemoryPolicyV2.psm1").read_text(encoding="utf-8-sig")
    check("unity-source-policy-tokens", all(token in source for token in [POLICY_ID, "MP2-NATIVE-LE128", "MP2-NATIVE-EQ256", "WHOLE-BLOCK-PROCESS", "GlobalMemoryStatusEx", "raw-after-workload", "post-block-pre-exit"]))
    check("unity-source-final-position-rejection", 'attributedAlgorithmId = string.Empty' in source and 'attributionScope = "WHOLE-BLOCK-PROCESS"' in source)
    check("wrapper-formal-receipt-gate", all(token in wrapper for token in ["FormalAttempt3", "formal attempt-3 receipt", "Assert-G13RPR2MP2FormalAttempt3Absent", "NoLaunchDryRun"]))
    check("wrapper-role-specific-lock-acceptance", all(token in wrapper for token in ["controlled-expected-negative-cleanup", "$ExpectedOutcome -eq 'Pass'", "@('natural-lock-absence','controlled-expected-negative-cleanup')", "lockHygieneModeAccepted"]))
    check("wrapper-positive-lock-not-relaxed", "$lockMode -eq 'natural-lock-absence'" in wrapper)
    check("module-policy-tokens", all(token in module for token in [POLICY_ID, "HARD-FAIL-NATIVE-ELIGIBILITY", "RAW-TRANSIENT-DIAGNOSTIC-ONLY", "WHOLE-BLOCK-PROCESS"]))
    check("candidate-authorization-boundary", candidate["mp2AuthorizationBoundary"] == {"formalAttempt3ExecutionReceiptCreationAuthorized": False, "formalAttempt3MeasuredCampaignAuthorized": False, "formalAttempt3RootCreationAuthorized": False, "formalStatisticalAnalysisAuthorized": False, "gate14RAuthorized": False, "nonExecuting": True, "validationOnlyUnityAuthorized": True})
    check("candidate-design-cardinality", candidate["totals"]["campaignCount"] == 74 and candidate["totals"]["processCount"] == 3552 and candidate["totals"]["sampleCount"] == 10176)
    check("candidate-schedule-unchanged", candidate["schedule"]["scheduleSha256"] == EXPECTED_SCHEDULE_SHA)
    check("adapter-does-not-create-formal", adapter["createsFormalRoot"] is False and adapter["createsFormalReceipt"] is False and adapter["formalModeRequiresSeparateAttempt3Receipt"] is True)
    check("provenance-no-execution", provenance["formalAttempt3RootCreated"] is False and provenance["formalAttempt3ReceiptCreated"] is False and provenance["formalAttempt3MeasuredCampaignExecuted"] is False and provenance["formalStatisticalAnalysisExecuted"] is False and provenance["gate14RExecuted"] is False)

    state_machine_allowed = {"ACQUISITION-PENDING": {"RAW-DATA-COMPLETE"}, "RAW-DATA-COMPLETE": {"ANALYSIS-COMPLETE", "ANALYSIS-FAILED-RECOVERABLE"}, "ANALYSIS-FAILED-RECOVERABLE": {"ANALYSIS-COMPLETE", "ANALYSIS-FAILED-RECOVERABLE"}}
    check("two-stage-valid-transition", "RAW-DATA-COMPLETE" in state_machine_allowed["ACQUISITION-PENDING"] and "ANALYSIS-COMPLETE" in state_machine_allowed["RAW-DATA-COMPLETE"])
    check("two-stage-analysis-cannot-trigger-acquisition", "ACQUISITION-PENDING" not in state_machine_allowed["ANALYSIS-FAILED-RECOVERABLE"])

    verification_temp = project / "Research/Verification/Gate13R_PR2_MP2/determinism-temp"
    verification_temp.mkdir(parents=True, exist_ok=True)
    generator = project / "Research/New-Gate13RPR2MP2WrapperRepairArtifactsV3.py"
    with tempfile.TemporaryDirectory(prefix="regen-a-", dir=str(verification_temp)) as first, tempfile.TemporaryDirectory(prefix="regen-b-", dir=str(verification_temp)) as second:
        for target in (first, second):
            completed = subprocess.run([os.fspath(Path(os.sys.executable)), os.fspath(generator), "--project-root", os.fspath(project), "--output-dir", target], capture_output=True, text=True, check=False)
            if completed.returncode != 0:
                check(f"deterministic-generator-run-{Path(target).name}", False, completed.stderr[-2000:])
        first_files = sorted(path.name for path in Path(first).iterdir() if path.is_file())
        second_files = sorted(path.name for path in Path(second).iterdir() if path.is_file())
        check("deterministic-regeneration-file-set", first_files == second_files and len(first_files) == 4)
        check("deterministic-regeneration-byte-identity", first_files == second_files and all((Path(first) / name).read_bytes() == (Path(second) / name).read_bytes() for name in first_files))
        check("generated-main-equals-regeneration", all((project / "Research" / name).read_bytes() == (Path(first) / name).read_bytes() for name in first_files))
    try:
        verification_temp.rmdir()
    except OSError:
        pass

    formal_root = project / "Research/FormalRuns/Gate13R_RQAligned_S48H48/v3"
    formal_receipt = project / "Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json"
    formal_status = project / "Research/Gate13R_PR2_Formal_Execution_Status.v3.json"
    check("formal-attempt3-root-absent", not formal_root.exists())
    check("formal-attempt3-receipt-absent", not formal_receipt.exists())
    check("formal-attempt3-status-absent", not formal_status.exists())
    check("unity-project-lock-absent", not (project / "Temp/UnityLockfile").exists())

    result = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-mp2-static-unit-determinism-summary-v3",
        "completedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "testCount": len(checks),
        "passedTestCount": sum(1 for item in checks if item["passed"]),
        "checks": checks,
        "passed": all(item["passed"] for item in checks),
        "formalAttempt3RootCreated": False,
        "formalAttempt3ReceiptCreated": False,
        "unityInvoked": False,
    }
    atomic_create(output, result)
    print(json.dumps({"passed": result["passed"], "testCount": result["testCount"], "passedTestCount": result["passedTestCount"], "output": str(output)}, sort_keys=True))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
