from __future__ import annotations

import hashlib
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
E = ROOT / "Research/Gate14Re-ME/Execution/v4"
MANIFEST = E / "load-qualification-current-implementation-manifest.v4_1.json"
ACQUISITION = E / "load-qualification-acquisition-contract.v4_1.json"
ACCEPTANCE = E / "load-qualification-acceptance-contract.v4_2.json"
RUNNER = ROOT / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_1.cs"
SUPERVISOR = E / "Run-Gate14ReMELoadQualification.v4_1.ps1"
SCHEDULE = ROOT / (
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/"
    "planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
)
OUTPUT = Path(__file__).resolve().parent / "provisional-implementation-audit-receipt.v4_1.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def batch_index(ordinal: int) -> int:
    require(0 <= ordinal < 126, f"Schedule ordinal outside 0..125: {ordinal}")
    if ordinal < 108:
        g_index = ordinal // 36
        n_index = (ordinal % 36) // 12
        f_index = (ordinal % 12) // 3
        replicate_index = ordinal % 3
        return (g_index + n_index + f_index + (2 * replicate_index)) % 6
    return (ordinal - 108) % 6


def main() -> int:
    require(not OUTPUT.exists(), f"Audit receipt already exists; overwrite prohibited: {OUTPUT}")
    manifest = load_json(MANIFEST)
    acquisition = load_json(ACQUISITION)
    acceptance = load_json(ACCEPTANCE)

    require(
        manifest.get("status")
        == "PROVISIONAL_IMPLEMENTATION_SNAPSHOT_COMPILED_NOT_DESIGN_FREEZE_NOT_EXECUTION_AUTHORIZATION",
        "Manifest is not the expected provisional, execution-unauthorized snapshot.",
    )
    require(manifest.get("scope", {}).get("overallDesignFrozen") is False, "Manifest unexpectedly freezes the design.")
    require(manifest.get("scope", {}).get("qualificationExecutionAuthorized") is False, "Manifest unexpectedly authorizes execution.")
    require(acquisition.get("status", "").startswith("PROVISIONAL_"), "Acquisition contract is not provisional.")
    require(acceptance.get("status", "").startswith("PROVISIONAL_"), "Acceptance contract is not provisional.")

    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list) and artifacts, "Manifest artifact list is empty.")
    by_path: dict[str, dict] = {}
    for artifact in artifacts:
        relative = artifact.get("relativePath")
        require(isinstance(relative, str) and relative and relative not in by_path, f"Duplicate/invalid manifest path: {relative}")
        path = ROOT / Path(relative)
        require(path.is_file(), f"Manifest artifact missing: {relative}")
        require(path.stat().st_size == artifact.get("bytes"), f"Manifest byte-count mismatch: {relative}")
        require(sha256(path) == artifact.get("sha256"), f"Manifest SHA-256 mismatch: {relative}")
        by_path[relative] = artifact

    entry = acquisition["entryPoint"]
    for path_key, hash_key in (
        ("supervisorRelativePath", "supervisorSha256"),
        ("runnerRelativePath", "runnerSha256"),
        ("runnerMetaRelativePath", "runnerMetaSha256"),
    ):
        relative = entry[path_key]
        require(relative in by_path, f"Acquisition entry point absent from manifest: {relative}")
        require(by_path[relative]["sha256"] == entry[hash_key], f"Acquisition entry hash mismatch: {relative}")

    for name, binding in acquisition["frozenBindings"].items():
        relative = binding["relativePath"]
        require(relative in by_path, f"Prospective binding absent from manifest ({name}): {relative}")
        require(by_path[relative]["sha256"] == binding["sha256"], f"Prospective binding hash mismatch ({name})")

    for binding in (
        acceptance["entryPoint"],
        acceptance["sourceContract"],
        acceptance["frozenBindings"]["outputSchema"],
    ):
        if "launcherRelativePath" in binding:
            pairs = (("launcherRelativePath", "launcherSha256"), ("toolRelativePath", "toolSha256"))
        else:
            pairs = (("relativePath", "sha256"),)
        for path_key, hash_key in pairs:
            relative = binding[path_key]
            require(relative in by_path, f"Acceptance binding absent from manifest: {relative}")
            require(by_path[relative]["sha256"] == binding[hash_key], f"Acceptance binding hash mismatch: {relative}")

    compile_receipt_path = ROOT / (
        "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-007/"
        "compile-readiness-receipt.v4_5.json"
    )
    compile_receipt = load_json(compile_receipt_path)
    require(compile_receipt["runnerSha256"] == sha256(RUNNER), "Compile receipt does not bind the exact current runner source.")
    require(compile_receipt["unity"]["naturalExitCode"] == 0, "Exact-source compile did not exit zero.")
    require(compile_receipt["unity"]["compilerErrors"] == 0, "Exact-source compile recorded compiler errors.")
    require(compile_receipt["unity"]["burstCurrentCompilationDone"] is True, "Burst completion was not proven.")
    require(compile_receipt["qualificationExecuted"] is False, "Compile readiness executed qualification.")
    require(compile_receipt["algorithmLaneExecuted"] is False, "Compile readiness executed an algorithm lane.")
    require(compile_receipt["measuredRootCreated"] is False, "Compile readiness created a measured root.")

    runner_text = RUNNER.read_text(encoding="utf-8-sig")
    supervisor_text = SUPERVISOR.read_text(encoding="utf-8-sig")
    lane_start = runner_text.index("private static void RunAlgorithmLane(")
    lane_end = runner_text.index("private static void RunEmptyBoundaryMode(", lane_start)
    lane_text = runner_text[lane_start:lane_end]
    require("Gate14ReMEReferenceOracleV1.Evaluate" not in lane_text, "Algorithm lane still calls the reference-oracle evaluator.")
    require("Gate14ReMEReferenceOracleV1.Evaluate" not in runner_text, "Runner directly calls the reference-oracle evaluator.")
    require('if (mode == "oracle-batch")' in runner_text, "Runner lacks oracle-batch mode.")
    require("referenceOracleEvaluationsPerformedInsideLane = 0" in runner_text, "Lane cache link lacks zero-recompute declaration.")
    require("$processOrdinal -eq 775" in supervisor_text, "Supervisor terminal cardinality is not 775.")
    require("$batchIndex -lt 6" in supervisor_text, "Supervisor does not run exactly six oracle batches.")

    schedule_rows = []
    with SCHEDULE.open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            if line.strip():
                schedule_rows.append(json.loads(line))
    require(len(schedule_rows) == 126, "Schedule does not contain exactly 126 rows.")
    batch_summaries = []
    for batch in range(6):
        selected = [row for row in schedule_rows if batch_index(int(row["ordinal"])) == batch]
        require(len(selected) == 21, f"Oracle batch {batch} does not contain 21 inputs.")
        factors = []
        for row in selected:
            input_path = ROOT / Path(row["inputRelativePath"])
            require(sha256(input_path) == row["inputSha256"], f"Schedule input hash mismatch: {row['inputRelativePath']}")
            bundle = load_json(input_path)
            factors.append(bundle)
        region = Counter(str(x["designRegion"]) for x in factors)
        core = [x for x in factors if x["designRegion"] == "core"]
        g = Counter(int(x["gridEdge"]) for x in core)
        n = Counter(int(x["agentCount"]) for x in core)
        f = Counter(int(x["changedCellCount"]) for x in core)
        topology = Counter(str(x["changeTopology"]) for x in factors)
        require(region == Counter({"core": 18, "stress": 3}), f"Oracle batch {batch} region imbalance: {region}")
        require(sorted(g.values()) == [6, 6, 6], f"Oracle batch {batch} G imbalance: {g}")
        require(sorted(n.values()) == [6, 6, 6], f"Oracle batch {batch} N imbalance: {n}")
        require(sorted(f.values()) == [4, 4, 5, 5], f"Oracle batch {batch} F imbalance: {f}")
        require(sorted(topology.values()) == [7, 7, 7], f"Oracle batch {batch} topology imbalance: {topology}")
        batch_summaries.append(
            {
                "batchIndex": batch,
                "inputs": 21,
                "core": 18,
                "stress": 3,
                "coreGCounts": dict(sorted(g.items())),
                "coreNCounts": dict(sorted(n.items())),
                "coreFCounts": dict(sorted(f.items())),
                "topologyCounts": dict(sorted(topology.items())),
            }
        )

    all_active_text = "\n".join(
        path.read_text(encoding="utf-8-sig")
        for path in (
            ACQUISITION,
            ACCEPTANCE,
            E / "load-qualification-input-schema.v4_1.json",
            E / "load-qualification-schedule-schema.v4_1.json",
            E / "load-qualification-output-schema.v4_1.json",
            E / "load-qualification-resource-budget.v4_1.json",
        )
    )
    require("PENDING_FINAL_PROVISIONAL_HASH" not in all_active_text, "An active v4.1/v4.2 binding still has a placeholder hash.")

    receipt = {
        "schema": "gate14re-me-oracle-cache-provisional-implementation-audit-receipt-v4.1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_PROVISIONAL_IMPLEMENTATION_AUDIT_NOT_DESIGN_FREEZE_NOT_EXECUTION_AUTHORIZATION",
        "manifestRelativePath": MANIFEST.relative_to(ROOT).as_posix(),
        "manifestSha256": sha256(MANIFEST),
        "artifactCount": len(artifacts),
        "artifactHashAndByteChecksPassed": True,
        "prospectiveContractBindingsPassed": True,
        "exactRunnerCompileReadinessPassed": True,
        "algorithmLaneDirectReferenceOracleEvaluations": 0,
        "oracleBatchCount": 6,
        "inputCacheCount": 126,
        "algorithmLaneCount": 756,
        "plannedFreshProcesses": 775,
        "batchBalance": batch_summaries,
        "qualificationExecuted": False,
        "oracleAcquisitionExecuted": False,
        "algorithmLaneExecuted": False,
        "measuredRootCreated": False,
        "overallDesignFrozen": False,
        "executionAuthorized": False,
        "completedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    temporary = OUTPUT.with_suffix(OUTPUT.suffix + f".tmp-{os.getpid()}")
    temporary.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, OUTPUT)
    print(json.dumps(receipt, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL_CLOSED: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise
