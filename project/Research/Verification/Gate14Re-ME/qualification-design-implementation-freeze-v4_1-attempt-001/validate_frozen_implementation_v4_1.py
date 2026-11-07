from __future__ import annotations

import ast
import hashlib
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


FREEZE_ROOT = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[4]
E = ROOT / "Research/Gate14Re-ME/Execution/v4"
MANIFEST = E / "load-qualification-current-implementation-manifest.v4_1.json"
ACQUISITION = E / "load-qualification-acquisition-contract.v4_1.json"
ACCEPTANCE = E / "load-qualification-acceptance-contract.v4_2.json"
INPUT_SCHEMA = E / "load-qualification-input-schema.v4_1.json"
SCHEDULE_SCHEMA = E / "load-qualification-schedule-schema.v4_1.json"
OUTPUT_SCHEMA = E / "load-qualification-output-schema.v4_1.json"
BUDGET = E / "load-qualification-resource-budget.v4_1.json"
SAMPLE_SIZE = E / "formal-sample-size-decision.v4_1.json"
FAIRNESS = E / "six-algorithm-fairness-binding.v4_1.json"
RUNNER = ROOT / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_1.cs"
SUPERVISOR = E / "Run-Gate14ReMELoadQualification.v4_1.ps1"
ACCEPTANCE_LAUNCHER = E / "Run-Gate14ReMEReadOnlyAcceptance.v4_2.ps1"
ACCEPTANCE_TOOL = ROOT / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_acceptance_v4_2.py"
SCHEDULE = ROOT / (
    "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/"
    "planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
)
COMPILE_RECEIPT = ROOT / (
    "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-007/"
    "compile-readiness-receipt.v4_5.json"
)
PLAN = FREEZE_ROOT / "freeze-plan.v4_1.json"
AUTHORIZATION = FREEZE_ROOT / "user-authorization-receipt.v4_1.json"
INVENTORY = FREEZE_ROOT / "frozen-source-inventory.v4_1.jsonl"
READINESS = FREEZE_ROOT / "frozen-readiness-receipt.v4_1.json"
FREEZE_MANIFEST = FREEZE_ROOT / "freeze-manifest.v4_1.json"
TERMINAL = FREEZE_ROOT / "terminal-receipt.v4_1.json"


class FreezeError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FreezeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root is not an object: {path}")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL row is not an object: {path}:{line_number}")
            rows.append(value)
    return rows


def relative(path: Path) -> str:
    resolved = path.resolve()
    require(resolved.is_relative_to(ROOT.resolve()), f"Path escapes project root: {path}")
    return resolved.relative_to(ROOT.resolve()).as_posix()


def write_json_exclusive(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def write_jsonl_exclusive(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(json.dumps(row, separators=(",", ":"), ensure_ascii=False) + "\n")


def oracle_batch_index(ordinal: int) -> int:
    require(0 <= ordinal < 126, f"oracle batch ordinal outside 0..125: {ordinal}")
    if ordinal < 108:
        g_index = ordinal // 36
        within_g = ordinal % 36
        n_index = within_g // 12
        within_n = within_g % 12
        f_index = within_n // 3
        replicate_index = ordinal % 3
        return (g_index + n_index + f_index + 2 * replicate_index) % 6
    return (ordinal - 108) % 6


def parse_powershell(path: Path) -> str:
    executable = shutil.which("pwsh")
    require(executable is not None, "PowerShell 7 executable is unavailable for AST parsing")
    quoted = str(path.resolve()).replace("'", "''")
    command = (
        "$errors=$null; "
        f"[System.Management.Automation.Language.Parser]::ParseFile('{quoted}',[ref]$null,[ref]$errors) | Out-Null; "
        "if($errors.Count){$errors | ForEach-Object {$_.ToString()}; exit 2}; 'PASS'"
    )
    result = subprocess.run(
        [executable, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    require(result.returncode == 0 and "PASS" in result.stdout, f"PowerShell parse failed for {path}: {result.stderr or result.stdout}")
    return str(Path(executable).resolve())


def unity_process_count() -> int:
    executable = shutil.which("pwsh")
    require(executable is not None, "PowerShell 7 executable is unavailable for process inspection")
    result = subprocess.run(
        [
            executable,
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "@(Get-CimInstance Win32_Process -Filter \"Name = 'Unity.exe'\").Count",
        ],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    require(result.returncode == 0, f"Unity process inspection failed: {result.stderr or result.stdout}")
    return int(result.stdout.strip())


def validate_manifest() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest = load_json(MANIFEST)
    require(manifest.get("schema") == "gate14re-me-qualification-implementation-manifest-v1", "manifest schema mismatch")
    require(manifest.get("status") == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED", "manifest compatibility status is not frozen")
    require(manifest.get("manifestSchemaV4_1") == "gate14re-me-qualification-current-implementation-manifest-v4.1", "manifest v4.1 identity mismatch")
    require(
        manifest.get("executionReadinessStatus") == "FROZEN_V4_1_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED",
        "manifest readiness status mismatch",
    )
    scope = manifest.get("scope", {})
    require(scope.get("qualificationDesignFrozen") is True, "qualification design is not frozen in the manifest")
    require(scope.get("overallFormalDesignFrozen") is False, "formal design was prematurely frozen")
    require(scope.get("formalSampleSizeFinalized") is False, "formal sample size was prematurely finalized")
    require(scope.get("qualificationExecutionAuthorized") is False, "manifest unexpectedly authorizes execution")
    require(scope.get("formalCollectionAuthorized") is False, "manifest unexpectedly authorizes formal collection")
    require(scope.get("formalAnalysisAuthorized") is False, "manifest unexpectedly authorizes formal analysis")
    require(scope.get("rankingOrWinnerAuthorized") is False, "manifest unexpectedly authorizes ranking or winner selection")

    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list) and len(artifacts) == 33, "manifest artifact cardinality mismatch")
    index: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        require(isinstance(artifact, dict), "manifest artifact is not an object")
        artifact_relative = artifact.get("relativePath")
        require(isinstance(artifact_relative, str) and artifact_relative not in index, f"duplicate/invalid artifact path: {artifact_relative}")
        path = ROOT / Path(artifact_relative)
        require(path.is_file(), f"manifest artifact is missing: {artifact_relative}")
        require(path.stat().st_size == artifact.get("bytes"), f"manifest byte count mismatch: {artifact_relative}")
        require(sha256(path) == artifact.get("sha256"), f"manifest SHA-256 mismatch: {artifact_relative}")
        index[artifact_relative] = artifact
    return manifest, index


def validate_contracts(manifest_index: dict[str, dict[str, Any]]) -> dict[str, Any]:
    acquisition = load_json(ACQUISITION)
    acceptance = load_json(ACCEPTANCE)
    input_schema = load_json(INPUT_SCHEMA)
    schedule_schema = load_json(SCHEDULE_SCHEMA)
    output_schema = load_json(OUTPUT_SCHEMA)
    budget = load_json(BUDGET)
    sample_size = load_json(SAMPLE_SIZE)
    fairness = load_json(FAIRNESS)

    require(acquisition.get("status") == "FROZEN_V4_1_ACQUISITION_ONLY_EXECUTION_UNAUTHORIZED", "acquisition contract is not frozen")
    require(acquisition.get("design") == {
        "G": [64, 96, 128],
        "N": [32, 64, 128],
        "F": [1, 9, 25, 81],
        "coreCells": 36,
        "coreReplicatesPerCell": 3,
        "coreSuperblocks": 108,
        "stressSuperblocks": 18,
        "totalSuperblocks": 126,
        "algorithmsPerSuperblock": 6,
        "algorithmLanes": 756,
        "freshProcesses": {
            "instrumentSelfTest": 1,
            "oracleBatch": 6,
            "emptyBoundary": 12,
            "algorithmLane": 756,
            "total": 775,
        },
    }, "acquisition design/cardinality differs from the frozen design")
    design_state = acquisition.get("designState", {})
    require(design_state.get("qualificationDesignFrozen") is True, "acquisition qualification design is not frozen")
    require(design_state.get("overallFormalDesignFrozen") is False, "acquisition contract prematurely freezes formal design")
    require(design_state.get("formalSampleSizeFinalized") is False, "acquisition contract prematurely finalizes B")
    require(design_state.get("qualificationExecutionAuthorized") is False, "acquisition contract unexpectedly authorizes execution")

    rules = acquisition.get("executionRules", {})
    for field in ("retry", "resume", "topUp", "merge", "skip", "reorder"):
        require(rules.get(field) is False, f"acquisition rule unexpectedly enables {field}")
    require(rules.get("replacement") == 0, "acquisition replacement must be zero")
    require(rules.get("strictSerialFreshUnityProcesses") is True, "acquisition is not strict serial")
    require(rules.get("maximumConcurrentUnityProcesses") == 1, "acquisition concurrency differs from one")
    require(rules.get("oneHashBoundAlgorithmNeutralOracleCachePerInput") is True, "oracle-cache policy is absent")
    require(rules.get("referenceOracleEvaluationsInsideAlgorithmLane") == 0, "lane oracle recomputation is not zero")

    for name, binding in acquisition.get("frozenBindings", {}).items():
        path_relative = binding.get("relativePath")
        require(path_relative in manifest_index, f"acquisition binding is absent from manifest: {name}")
        require(binding.get("sha256") == manifest_index[path_relative].get("sha256"), f"acquisition binding hash mismatch: {name}")

    require(input_schema.get("authorizationBoundary", {}).get("schemaFrozen") is True, "input schema is not frozen")
    require(input_schema.get("authorizationBoundary", {}).get("qualificationExecutionAuthorized") is False, "input schema authorizes execution")
    require(schedule_schema.get("authorizationBoundary", {}).get("schemaFrozen") is True, "schedule schema is not frozen")
    require(schedule_schema.get("authorizationBoundary", {}).get("plannedRows") == 126, "schedule schema row count mismatch")
    require(schedule_schema.get("authorizationBoundary", {}).get("plannedFreshProcesses") == 775, "schedule schema process count mismatch")
    require(schedule_schema.get("authorizationBoundary", {}).get("qualificationExecutionAuthorized") is False, "schedule schema authorizes execution")
    require(
        output_schema.get("status") == "FROZEN_BOUNDED_WINDOW_STREAMING_ESSENTIAL_ACCEPTANCE_ORACLE_CACHE_V4_1",
        "output schema is not frozen",
    )
    require("acceptance-manifest.v4_2.json" in output_schema.get("receipts", []), "output schema does not name the actual acceptance manifest")
    require("delivery-manifest.v4_2.json" not in output_schema.get("receipts", []), "stale acceptance manifest name remains")
    require(budget.get("status") == "FROZEN_V4_1_ORACLE_CACHE_BOUNDED_LOAD_PREEXECUTION_BUDGETS", "resource budget is not frozen")
    require(budget.get("maximumConcurrentUnityProcesses") == 1, "resource budget concurrency mismatch")
    require(budget.get("maximumWholeSuperblockTechnicalReplacements") == 0, "resource budget replacement mismatch")
    require(budget.get("oracleCacheV41", {}).get("batchCount") == 6, "resource budget oracle batch count mismatch")
    require(budget.get("oracleCacheV41", {}).get("laneReferenceOracleEvaluations") == 0, "resource budget lane recomputation mismatch")

    require(sample_size.get("status") == "PENDING_NEW_QUALIFICATION_AND_ANONYMOUS_POWER_REFREEZE", "sample-size decision status drifted")
    require(sample_size.get("candidateB") == [36, 72, 108, 144], "candidate B grid drifted")
    require(sample_size.get("provisionalMinimumB") == 36, "provisional minimum B drifted")
    require(sample_size.get("finalB") is None, "final B was outcome-driven or prematurely frozen")
    require(sample_size.get("formalCollectionAuthorized") is False, "sample-size decision authorizes formal collection")

    ownership = fairness.get("v4_1VersionOwnership", {})
    require(fairness.get("status") == "FROZEN_SIX_ALGORITHM_BINDING", "fairness binding status drifted")
    require(ownership.get("qualificationDesignFreeze") is True, "fairness binding lacks qualification freeze")
    require(ownership.get("overallFormalDesignFreeze") is False, "fairness binding prematurely freezes formal design")
    require(ownership.get("formalSampleSizeFinalized") is False, "fairness binding prematurely finalizes sample size")
    require(ownership.get("executionAuthorized") is False, "fairness binding authorizes execution")
    algorithms = fairness.get("algorithms")
    require(isinstance(algorithms, list) and len(algorithms) == 6, "fairness algorithm cardinality mismatch")
    require({item.get("algorithmId") for item in algorithms} == {"A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"}, "fairness algorithm cohort drifted")
    for item in algorithms:
        implementation = ROOT / Path(item["implementationRelativePath"])
        specification = ROOT / Path(item["specificationRelativePath"])
        require(sha256(implementation) == item.get("implementationSha256"), f"algorithm implementation drift: {item.get('algorithmId')}")
        require(sha256(specification) == item.get("specificationSha256"), f"algorithm specification drift: {item.get('algorithmId')}")

    require(
        acceptance.get("status") == "FROZEN_READ_ONLY_OFFLINE_ACCEPTANCE_V4_2_ORACLE_CACHE_EXECUTION_UNAUTHORIZED",
        "acceptance contract is not frozen",
    )
    require(acceptance.get("entryPoint", {}).get("contractPathAndShaMustBePassedToLauncher") is True, "acceptance contract is not a launcher trust anchor")
    require(acceptance.get("entryPoint", {}).get("launcherSha256") == sha256(ACCEPTANCE_LAUNCHER), "acceptance launcher hash mismatch")
    require(acceptance.get("entryPoint", {}).get("toolSha256") == sha256(ACCEPTANCE_TOOL), "acceptance tool hash mismatch")
    require(acceptance.get("sourceContract", {}).get("sha256") == sha256(ACQUISITION), "acceptance source-contract hash mismatch")
    require(
        acceptance.get("sourceContract", {}).get("requiredContractStatus") == acquisition.get("status"),
        "acceptance source-contract status mismatch",
    )
    require(acceptance.get("frozenBindings", {}).get("outputSchema", {}).get("sha256") == sha256(OUTPUT_SCHEMA), "acceptance output-schema binding mismatch")
    require(acceptance.get("frozenBindings", {}).get("schedule", {}).get("sha256") == sha256(SCHEDULE), "acceptance schedule binding mismatch")
    require(acceptance.get("memoryAndHashingRules", {}).get("wholeDatasetRowsRetainedInMemory") is False, "acceptance retains the whole dataset")
    require(acceptance.get("memoryAndHashingRules", {}).get("perRowSourceFileRehash") is False, "acceptance rehashes source files per row")
    require(acceptance.get("memoryAndHashingRules", {}).get("parquetBatchRows") == 4096, "acceptance batch size drifted")
    require(acceptance.get("terminalPassMeaning", {}).get("formalSampleSizeFinalized") is False, "acceptance prematurely finalizes sample size")
    require(acceptance.get("terminalPassMeaning", {}).get("executionAuthorizedByThisContract") is False, "acceptance contract authorizes execution")

    return {
        "acquisitionContractSha256": sha256(ACQUISITION),
        "acceptanceContractSha256": sha256(ACCEPTANCE),
        "inputSchemaSha256": sha256(INPUT_SCHEMA),
        "scheduleSchemaSha256": sha256(SCHEDULE_SCHEMA),
        "outputSchemaSha256": sha256(OUTPUT_SCHEMA),
        "resourceBudgetSha256": sha256(BUDGET),
        "sampleSizeDecisionSha256": sha256(SAMPLE_SIZE),
        "fairnessBindingSha256": sha256(FAIRNESS),
    }


def validate_schedule() -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    schedule_rows = load_jsonl(SCHEDULE)
    require(len(schedule_rows) == 126, "schedule must contain exactly 126 rows")
    superblocks: set[str] = set()
    input_paths: set[str] = set()
    identity_hashes: set[str] = set()
    cell_counts: Counter[tuple[int, int, int]] = Counter()
    regions: Counter[str] = Counter()
    batch_summaries: list[dict[str, Any]] = []
    expected_algorithms = {"A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"}
    expected_lanes = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
    bundles: list[dict[str, Any]] = []

    for ordinal, row in enumerate(schedule_rows):
        require(row.get("schema") == "gate14re-me-load-qualification-schedule-row-v4", f"schedule schema mismatch at {ordinal}")
        require(row.get("ordinal") == ordinal, f"schedule ordinal mismatch at {ordinal}")
        require(row.get("replacement") is None, f"schedule contains replacement at {ordinal}")
        superblock_id = row.get("superblockId")
        require(isinstance(superblock_id, str) and superblock_id not in superblocks, f"duplicate/invalid superblock at {ordinal}")
        superblocks.add(superblock_id)
        lanes = row.get("algorithmOrder")
        require(isinstance(lanes, list) and len(lanes) == 6, f"lane cardinality mismatch at {ordinal}")
        require({lane.get("algorithmId") for lane in lanes} == expected_algorithms, f"algorithm cohort mismatch at {ordinal}")
        require({lane.get("anonymousLaneId") for lane in lanes} == expected_lanes, f"anonymous lane cohort mismatch at {ordinal}")
        identity_hashes.update(str(lane.get("identityBindingSha256")) for lane in lanes)
        input_relative = row.get("inputRelativePath")
        require(isinstance(input_relative, str) and input_relative not in input_paths, f"duplicate/invalid input path at {ordinal}")
        input_paths.add(input_relative)
        input_path = ROOT / Path(input_relative)
        require(sha256(input_path) == row.get("inputSha256"), f"input hash mismatch at {ordinal}")
        bundle = load_json(input_path)
        bundles.append(bundle)
        require(bundle.get("schema") == "gate14re-me-qualification-input-bundle-v1", f"input schema mismatch at {ordinal}")
        require(bundle.get("superblockId") == superblock_id, f"input superblock mismatch at {ordinal}")
        require(len(bundle.get("eventGroups", [])) == 24, f"event-group cardinality mismatch at {ordinal}")
        g, n, f = int(bundle["gridEdge"]), int(bundle["agentCount"]), int(bundle["changedCellCount"])
        require(g in {64, 96, 128} and n in {32, 64, 128} and f in {1, 9, 25, 81}, f"factor support mismatch at {ordinal}")
        region = str(bundle.get("designRegion"))
        require(region in {"core", "stress"}, f"design region mismatch at {ordinal}")
        regions[region] += 1
        if region == "core":
            cell_counts[(g, n, f)] += 1
        else:
            require((g, n, f) == (128, 128, 81), f"stress input is not at the bounded high corner: {ordinal}")

    require(len(identity_hashes) == 1, "schedule does not bind exactly one sealed identity hash")
    require(regions == Counter({"core": 108, "stress": 18}), f"region counts mismatch: {regions}")
    expected_cells = {(g, n, f) for g in (64, 96, 128) for n in (32, 64, 128) for f in (1, 9, 25, 81)}
    require(set(cell_counts) == expected_cells, "core GxNxF cell support is incomplete")
    require(set(cell_counts.values()) == {3}, "core GxNxF cells do not have exactly three replicates")

    for batch_index in range(6):
        selected = [(row, bundles[int(row["ordinal"])]) for row in schedule_rows if oracle_batch_index(int(row["ordinal"])) == batch_index]
        require(len(selected) == 21, f"oracle batch {batch_index} does not contain 21 inputs")
        region = Counter(str(bundle["designRegion"]) for _, bundle in selected)
        core = [bundle for _, bundle in selected if bundle["designRegion"] == "core"]
        g_counts = Counter(int(bundle["gridEdge"]) for bundle in core)
        n_counts = Counter(int(bundle["agentCount"]) for bundle in core)
        f_counts = Counter(int(bundle["changedCellCount"]) for bundle in core)
        topology_counts = Counter(str(bundle["changeTopology"]) for _, bundle in selected)
        require(region == Counter({"core": 18, "stress": 3}), f"oracle batch {batch_index} region imbalance")
        require(sorted(g_counts.values()) == [6, 6, 6], f"oracle batch {batch_index} G imbalance")
        require(sorted(n_counts.values()) == [6, 6, 6], f"oracle batch {batch_index} N imbalance")
        require(sorted(f_counts.values()) == [4, 4, 5, 5], f"oracle batch {batch_index} F imbalance")
        require(sorted(topology_counts.values()) == [7, 7, 7], f"oracle batch {batch_index} topology imbalance")
        batch_summaries.append({
            "batchIndex": batch_index,
            "inputs": 21,
            "core": 18,
            "stress": 3,
            "coreGCounts": dict(sorted(g_counts.items())),
            "coreNCounts": dict(sorted(n_counts.items())),
            "coreFCounts": dict(sorted(f_counts.items())),
            "topologyCounts": dict(sorted(topology_counts.items())),
        })
    return schedule_rows, batch_summaries, next(iter(identity_hashes))


def validate_sources() -> dict[str, Any]:
    runner_text = RUNNER.read_text(encoding="utf-8-sig")
    supervisor_text = SUPERVISOR.read_text(encoding="utf-8-sig")
    launcher_text = ACCEPTANCE_LAUNCHER.read_text(encoding="utf-8-sig")
    tool_text = ACCEPTANCE_TOOL.read_text(encoding="utf-8-sig")
    ast.parse(tool_text, filename=str(ACCEPTANCE_TOOL))
    lane_start = runner_text.index("private static void RunAlgorithmLane(")
    lane_end = runner_text.index("private static void RunEmptyBoundaryMode(", lane_start)
    lane_text = runner_text[lane_start:lane_end]
    require("Gate14ReMEReferenceOracleV1.Evaluate" not in lane_text, "algorithm lane calls the reference oracle")
    require("Gate14ReMEReferenceOracleV1.Evaluate" not in runner_text, "runner directly calls the reference oracle")
    require('if (mode == "oracle-batch")' in runner_text, "runner lacks oracle-batch mode")
    require("referenceOracleEvaluationsPerformedInsideLane = 0" in runner_text, "lane cache link lacks zero-recompute declaration")
    for token in (
        "$processOrdinal -eq 775",
        "$batchIndex -lt 6",
        "FROZEN_V4_1_ACQUISITION_ONLY_EXECUTION_UNAUTHORIZED",
        "FROZEN_V4_1_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED",
        "FROZEN_V4_1_ORACLE_CACHE_BOUNDED_LOAD_PREEXECUTION_BUDGETS",
    ):
        require(token in supervisor_text, f"supervisor frozen gate missing: {token}")
    for token in (
        "AcceptanceContractSha256",
        "FROZEN_READ_ONLY_OFFLINE_ACCEPTANCE_V4_2_ORACLE_CACHE_EXECUTION_UNAUTHORIZED",
        "acceptance launcher v4.2 self-binding",
        "frozen acquisition contract v4.1",
        "executionContractSha256",
        "parquetBatchRows",
    ):
        require(token in launcher_text, f"acceptance launcher contract gate missing: {token}")
    pwsh_path = parse_powershell(SUPERVISOR)
    parse_powershell(ACCEPTANCE_LAUNCHER)

    compile_receipt = load_json(COMPILE_RECEIPT)
    require(compile_receipt.get("runnerSha256") == sha256(RUNNER), "exact compile receipt does not bind the frozen runner")
    unity = compile_receipt.get("unity", {})
    unity_path = Path(str(unity.get("executablePath")))
    require(unity_path.is_file(), "compiled Unity executable is missing")
    require(sha256(unity_path) == unity.get("sha256"), "compiled Unity executable hash drifted")
    require(unity.get("naturalExitCode") == 0, "exact compile did not exit naturally with code zero")
    require(unity.get("compilerErrors") == 0, "exact compile recorded compiler errors")
    require(unity.get("burstCurrentCompilationDone") is True, "exact compile did not prove Burst completion")
    require(compile_receipt.get("qualificationExecuted") is False, "compile readiness executed qualification")
    require(compile_receipt.get("oracleAcquisitionExecuted") is False, "compile readiness executed oracle acquisition")
    require(compile_receipt.get("algorithmLaneExecuted") is False, "compile readiness executed an algorithm lane")
    require(compile_receipt.get("measuredRootCreated") is False, "compile readiness created a measured root")

    return {
        "runnerSha256": sha256(RUNNER),
        "supervisorSha256": sha256(SUPERVISOR),
        "acceptanceLauncherSha256": sha256(ACCEPTANCE_LAUNCHER),
        "acceptanceToolSha256": sha256(ACCEPTANCE_TOOL),
        "compileReceiptSha256": sha256(COMPILE_RECEIPT),
        "compileEvidenceAdoptedWithoutRecompile": True,
        "unityExecutablePath": unity_path.as_posix(),
        "unityExecutableSha256": unity.get("sha256"),
        "powerShellParserExecutablePath": Path(pwsh_path).as_posix(),
        "pythonAstParsePassed": True,
        "powerShellAstParsePassed": True,
        "algorithmLaneDirectReferenceOracleEvaluations": 0,
    }


def inventory_row(path: Path, role: str) -> dict[str, Any]:
    return {
        "schema": "gate14re-me-qualification-frozen-source-inventory-row-v4.1",
        "role": role,
        "relativePath": relative(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def main() -> int:
    for output in (INVENTORY, READINESS, FREEZE_MANIFEST, TERMINAL):
        require(not output.exists(), f"freeze output already exists; overwrite prohibited: {output}")
    plan = load_json(PLAN)
    authorization = load_json(AUTHORIZATION)
    require(plan.get("status") == "PREDECLARED_QUALIFICATION_FREEZE_PLAN_EXECUTION_UNAUTHORIZED", "freeze plan status mismatch")
    require(authorization.get("status") == "AUTHORIZED_QUALIFICATION_DESIGN_IMPLEMENTATION_CONTRACT_AND_READINESS_FREEZE_ONLY", "user authorization scope mismatch")
    for field in (
        "qualificationExecutionAuthorized",
        "executionAuthorizationCreationAuthorized",
        "newAttemptRootsAuthorized",
        "formalCollectionAuthorized",
        "formalAnalysisAuthorized",
        "rankingOrWinnerAuthorized",
        "algorithmObservationAccessAuthorized",
        "attempt009RawMutationAuthorized",
    ):
        require(authorization.get(field) is False, f"authorization unexpectedly enables {field}")

    manifest, manifest_index = validate_manifest()
    contract_hashes = validate_contracts(manifest_index)
    schedule_rows, batch_summaries, identity_sha = validate_schedule()
    source_checks = validate_sources()
    active_unity = unity_process_count()
    require(active_unity == 0, f"Unity process is active during freeze readiness: {active_unity}")
    free_bytes = shutil.disk_usage(ROOT).free
    reserved_bytes = int(load_json(BUDGET)["qualificationReservedStorageBytes"])
    require(free_bytes >= reserved_bytes, f"qualification storage headroom is below {reserved_bytes} bytes")

    inventory_rows: list[dict[str, Any]] = []
    for artifact in manifest["artifacts"]:
        inventory_rows.append(inventory_row(ROOT / Path(artifact["relativePath"]), str(artifact["role"])))
    inventory_rows.extend([
        inventory_row(MANIFEST, "frozen-implementation-manifest-v4.1"),
        inventory_row(PLAN, "predeclared-freeze-plan-v4.1"),
        inventory_row(AUTHORIZATION, "user-authorization-receipt-v4.1"),
        inventory_row(Path(__file__), "freeze-validator-v4.1"),
    ])
    require(len({row["relativePath"] for row in inventory_rows}) == len(inventory_rows), "freeze inventory contains duplicate paths")
    write_jsonl_exclusive(INVENTORY, inventory_rows)

    completed_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    readiness = {
        "schema": "gate14re-me-qualification-frozen-readiness-receipt-v4.1",
        "materialPassport": {
            "schema": "ars-material-passport-v9",
            "materialId": "gate14re-me-qualification-v4.1-readiness-attempt-001",
            "materialType": "EXPERIMENT_READINESS_VALIDATION",
            "verificationStatus": "VERIFIED",
        },
        "studyId": "Gate14Re-ME",
        "status": "PASS_FROZEN_V4_1_V4_2_READ_ONLY_READINESS_EXECUTION_UNAUTHORIZED",
        "implementationManifestRelativePath": relative(MANIFEST),
        "implementationManifestSha256": sha256(MANIFEST),
        "implementationManifestArtifacts": len(manifest["artifacts"]),
        "frozenSourceInventoryRelativePath": relative(INVENTORY),
        "frozenSourceInventorySha256": sha256(INVENTORY),
        "contractHashes": contract_hashes,
        "sourceChecks": source_checks,
        "qualificationDesign": {
            "G": [64, 96, 128],
            "N": [32, 64, 128],
            "F": [1, 9, 25, 81],
            "coreSuperblocks": 108,
            "stressSuperblocks": 18,
            "totalSuperblocks": len(schedule_rows),
            "algorithmLanes": 756,
            "oracleBatchProcesses": 6,
            "plannedFreshProcesses": 775,
            "identityBindingSha256": identity_sha,
            "oracleBatchBalance": batch_summaries,
        },
        "formalSampleSize": {
            "candidateB": [36, 72, 108, 144],
            "provisionalMinimumB": 36,
            "finalB": None,
            "finalizationPendingTerminalQualificationAndAnonymousPower": True,
        },
        "acceptance": {
            "readOnlyOffline": True,
            "wholeDatasetRowsRetainedInMemory": False,
            "perRowSourceFileRehash": False,
            "parquetBatchRows": 4096,
            "contractSelfBindingRequired": True,
            "sourceAcquisitionContractBindingRequired": True,
        },
        "hostReadiness": {
            "activeUnityProcesses": active_unity,
            "freeStorageBytes": free_bytes,
            "requiredQualificationReservationBytes": reserved_bytes,
            "storageHeadroomPassed": True,
        },
        "authorizationBoundary": {
            "qualificationDesignFrozen": True,
            "overallFormalDesignFrozen": False,
            "qualificationExecutionAuthorized": False,
            "executionAuthorizationCreated": False,
            "newAttemptRootsCreated": False,
            "unityExecutedByThisStage": False,
            "algorithmObservationsRead": False,
            "formalCollectionAuthorized": False,
            "formalAnalysisAuthorized": False,
            "rankingOrWinnerAuthorized": False,
            "migrationPackageState": "DORMANT_SEALED_FOR_LATER_REACTIVATION",
        },
        "completedAtUtc": completed_at,
    }
    write_json_exclusive(READINESS, readiness)

    freeze_manifest = {
        "schema": "gate14re-me-qualification-design-implementation-freeze-manifest-v4.1",
        "studyId": "Gate14Re-ME",
        "status": "FROZEN_QUALIFICATION_V4_1_V4_2_READINESS_PASS_EXECUTION_UNAUTHORIZED",
        "artifacts": [
            inventory_row(PLAN, "predeclared-freeze-plan-v4.1"),
            inventory_row(AUTHORIZATION, "user-authorization-receipt-v4.1"),
            inventory_row(Path(__file__), "freeze-validator-v4.1"),
            inventory_row(INVENTORY, "frozen-source-inventory-v4.1"),
            inventory_row(READINESS, "frozen-readiness-receipt-v4.1"),
            inventory_row(MANIFEST, "frozen-implementation-manifest-v4.1"),
            inventory_row(ACQUISITION, "frozen-acquisition-contract-v4.1"),
            inventory_row(ACCEPTANCE, "frozen-acceptance-contract-v4.2"),
        ],
        "artifactCount": 8,
        "qualificationExecutionAuthorized": False,
        "executionAuthorizationCreated": False,
        "newAttemptRootsCreated": False,
        "formalSampleSizeFinalized": False,
        "createdAtUtc": completed_at,
    }
    write_json_exclusive(FREEZE_MANIFEST, freeze_manifest)

    terminal = {
        "schema": "gate14re-me-qualification-design-implementation-freeze-terminal-v4.1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_FROZEN_QUALIFICATION_V4_1_V4_2_EXECUTION_UNAUTHORIZED",
        "freezeManifestRelativePath": relative(FREEZE_MANIFEST),
        "freezeManifestSha256": sha256(FREEZE_MANIFEST),
        "readinessReceiptRelativePath": relative(READINESS),
        "readinessReceiptSha256": sha256(READINESS),
        "implementationManifestRelativePath": relative(MANIFEST),
        "implementationManifestSha256": sha256(MANIFEST),
        "acquisitionContractSha256": sha256(ACQUISITION),
        "acceptanceContractSha256": sha256(ACCEPTANCE),
        "plannedFreshProcesses": 775,
        "qualificationExecuted": False,
        "executionAuthorizationCreated": False,
        "newAttemptRootsCreated": False,
        "algorithmObservationsRead": False,
        "formalSampleSizeFinalized": False,
        "nextGate": "SEPARATE_EXPLICIT_FRESH_EXECUTION_ATTEMPT_AUTHORIZATION",
        "completedAtUtc": completed_at,
    }
    write_json_exclusive(TERMINAL, terminal)
    print(json.dumps(terminal, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL_CLOSED: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise
