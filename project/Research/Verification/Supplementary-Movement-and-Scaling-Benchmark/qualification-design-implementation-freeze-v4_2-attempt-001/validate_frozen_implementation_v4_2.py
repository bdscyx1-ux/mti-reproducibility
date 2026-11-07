from __future__ import annotations

import ast
import hashlib
import json
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


FREEZE_ROOT = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[4]
EXECUTION = ROOT / "Research/Gate14Re-ME/Execution/v4"
MANIFEST = EXECUTION / "load-qualification-current-implementation-manifest.v4_2.json"
ACQUISITION = EXECUTION / "load-qualification-acquisition-contract.v4_2.json"
ACCEPTANCE = EXECUTION / "load-qualification-acceptance-contract.v4_3.json"
RUNNER = ROOT / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_2.cs"
VALIDATOR = ROOT / "Assets/_Scripts/Research/Gate14ReME/v4/Gate14ReMEInputGeometryValidatorV4_2.cs"
SUPERVISOR = EXECUTION / "Run-Gate14ReMELoadQualification.v4_2.ps1"
ACCEPTANCE_LAUNCHER = EXECUTION / "Run-Gate14ReMEReadOnlyAcceptance.v4_3.ps1"
ACCEPTANCE_TOOL = ROOT / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_acceptance_v4_3.py"
SCHEDULE = ROOT / "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
READINESS_TERMINAL = ROOT / "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-009/terminal-readiness-receipt.v4_6.json"
READINESS_FREEZE = ROOT / "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-009/freeze-manifest.v4_6.json"
FAILURE_SEAL = ROOT / "Research/Verification/Gate14Re-ME/load-qualification-failure-seal-attempt-010/terminal-failure-seal-receipt.v1.json"
PLAN = FREEZE_ROOT / "freeze-plan.v4_2.json"
AUTHORIZATION = FREEZE_ROOT / "user-authorization-receipt.v4_2.json"
INVENTORY = FREEZE_ROOT / "frozen-source-inventory.v4_2.jsonl"
READINESS = FREEZE_ROOT / "frozen-readiness-receipt.v4_2.json"
FREEZE_MANIFEST = FREEZE_ROOT / "freeze-manifest.v4_2.json"
TERMINAL = FREEZE_ROOT / "terminal-receipt.v4_2.json"
PWSH = Path("C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe")
NEXT_MEASURED = ROOT / "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-009"
NEXT_DELIVERY = ROOT / "Research/Exports/Gate14Re-ME/load-qualification/attempt-009"


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
    require(resolved.is_relative_to(ROOT.resolve()), f"path escapes project root: {path}")
    return resolved.relative_to(ROOT.resolve()).as_posix()


def write_json_exclusive(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def write_jsonl_exclusive(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(json.dumps(row, separators=(",", ":"), ensure_ascii=False) + "\n")


def inventory_row(path: Path, role: str) -> dict[str, Any]:
    return {
        "schema": "gate14re-me-qualification-frozen-source-inventory-row-v4.2",
        "role": role,
        "relativePath": relative(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def parse_powershell(path: Path) -> None:
    require(PWSH.is_file(), "frozen PowerShell host is missing")
    quoted = str(path.resolve()).replace("'", "''")
    command = (
        "$errors=$null; "
        f"[System.Management.Automation.Language.Parser]::ParseFile('{quoted}',[ref]$null,[ref]$errors)|Out-Null; "
        "if($errors.Count){$errors|ForEach-Object{$_.ToString()};exit 2};'PASS'"
    )
    result = subprocess.run(
        [str(PWSH), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True,
        text=True,
        timeout=60,
    )
    require(result.returncode == 0 and "PASS" in result.stdout, f"PowerShell AST parse failed: {path}: {result.stderr}")


def active_unity_count() -> int:
    result = subprocess.run(
        [str(PWSH), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "@(Get-CimInstance Win32_Process -Filter \"Name='Unity.exe'\" -ErrorAction SilentlyContinue).Count"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    require(result.returncode == 0, "could not inspect Unity processes")
    return int(result.stdout.strip())


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


def validate_manifest() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest = load_json(MANIFEST)
    require(manifest.get("schema") == "gate14re-me-qualification-implementation-manifest-v1", "manifest stable schema mismatch")
    require(manifest.get("status") == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED", "manifest compatibility status mismatch")
    require(manifest.get("manifestSchemaV4_2") == "gate14re-me-qualification-current-implementation-manifest-v4.2", "manifest v4.2 header mismatch")
    require(manifest.get("executionReadinessStatus") == "FROZEN_V4_2_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED", "manifest readiness status mismatch")
    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list) and len(artifacts) == 39, "manifest artifact cardinality mismatch")
    index: dict[str, dict[str, Any]] = {}
    for item in artifacts:
        rel = str(item.get("relativePath"))
        require(rel not in index, f"duplicate manifest path: {rel}")
        path = ROOT / rel
        require(path.is_file(), f"missing manifest artifact: {rel}")
        require(path.stat().st_size == item.get("bytes"), f"manifest byte mismatch: {rel}")
        require(sha256(path) == item.get("sha256"), f"manifest hash mismatch: {rel}")
        index[rel] = item
    for required in (RUNNER, VALIDATOR, SUPERVISOR, ACCEPTANCE_LAUNCHER, ACCEPTANCE_TOOL, ACQUISITION, ACCEPTANCE, READINESS_TERMINAL, READINESS_FREEZE, FAILURE_SEAL):
        require(relative(required) in index, f"required artifact missing from manifest: {required}")
    repair = manifest.get("technicalRepair", {})
    require(repair.get("priorFailedAttempt") == "load-qualification-execution-attempt-010", "technical repair failed-attempt binding mismatch")
    for field in ("scientificDesignChanged", "scheduleChanged", "algorithmCohortChanged", "processCardinalityChanged"):
        require(repair.get(field) is False, f"technical repair unexpectedly changed {field}")
    return manifest, index


def validate_contracts() -> dict[str, str]:
    acquisition = load_json(ACQUISITION)
    acceptance = load_json(ACCEPTANCE)
    require(acquisition.get("status") == "FROZEN_V4_2_ACQUISITION_ONLY_EXECUTION_UNAUTHORIZED", "acquisition contract status mismatch")
    design = acquisition.get("design", {})
    require(design.get("G") == [64, 96, 128] and design.get("N") == [32, 64, 128] and design.get("F") == [1, 9, 25, 81], "acquisition G/N/F mismatch")
    require(design.get("totalSuperblocks") == 126 and design.get("algorithmLanes") == 756, "acquisition cardinality mismatch")
    require(design.get("freshProcesses", {}).get("total") == 775, "acquisition process total mismatch")
    rules = acquisition.get("executionRules", {})
    require(rules.get("strictSerialFreshUnityProcesses") is True and rules.get("maximumConcurrentUnityProcesses") == 1, "strict seriality mismatch")
    require(rules.get("replacement") == 0 and rules.get("retry") is False and rules.get("resume") is False, "retry/replacement prohibition mismatch")
    require(rules.get("topUp") is False and rules.get("merge") is False and rules.get("skip") is False and rules.get("reorder") is False, "one-shot prohibition mismatch")
    entry = acquisition.get("entryPoint", {})
    require(entry.get("supervisorSha256") == sha256(SUPERVISOR), "supervisor contract hash mismatch")
    require(entry.get("runnerSha256") == sha256(RUNNER), "runner contract hash mismatch")
    require(entry.get("runnerExecuteMethod") == "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run", "runner method mismatch")
    geometry = acquisition.get("frozenBindings", {}).get("geometryValidatorV4_2", {})
    require(geometry.get("sha256") == sha256(VALIDATOR), "geometry validator contract hash mismatch")
    corrigendum = acquisition.get("technicalCorrigendum", {})
    require(corrigendum.get("failedAttemptSealSha256") == sha256(FAILURE_SEAL), "failed-attempt seal mismatch")
    require(corrigendum.get("qualificationDesignChanged") is False, "corrigendum changes scientific design")

    require(acceptance.get("status") == "FROZEN_READ_ONLY_OFFLINE_ACCEPTANCE_V4_3_ORACLE_CACHE_EXECUTION_UNAUTHORIZED", "acceptance status mismatch")
    acceptance_entry = acceptance.get("entryPoint", {})
    require(acceptance_entry.get("launcherSha256") == sha256(ACCEPTANCE_LAUNCHER), "acceptance launcher hash mismatch")
    require(acceptance_entry.get("toolSha256") == sha256(ACCEPTANCE_TOOL), "acceptance tool hash mismatch")
    source = acceptance.get("sourceContract", {})
    require(source.get("sha256") == sha256(ACQUISITION), "acceptance source-contract hash mismatch")
    require(source.get("requiredContractStatus") == acquisition.get("status"), "acceptance source-contract status mismatch")
    memory = acceptance.get("memoryAndHashingRules", {})
    require(memory.get("wholeDatasetRowsRetainedInMemory") is False, "acceptance retains all rows in memory")
    require(memory.get("perRowSourceFileRehash") is False, "acceptance rehashes source per row")
    require(memory.get("parquetBatchRows") == 4096, "acceptance batch size mismatch")
    return {"acquisition": sha256(ACQUISITION), "acceptance": sha256(ACCEPTANCE)}


def validate_schedule() -> tuple[str, list[dict[str, Any]]]:
    rows = load_jsonl(SCHEDULE)
    require(len(rows) == 126, "schedule row count mismatch")
    regions: Counter[str] = Counter()
    cells: Counter[tuple[int, int, int]] = Counter()
    superblocks: set[str] = set()
    inputs: set[str] = set()
    identities: set[str] = set()
    bundles: list[dict[str, Any]] = []
    for ordinal, row in enumerate(rows):
        require(row.get("ordinal") == ordinal, f"schedule ordinal mismatch: {ordinal}")
        require(row.get("replacement") is None, f"replacement row present: {ordinal}")
        superblock = str(row.get("superblockId"))
        require(superblock and superblock not in superblocks, f"duplicate superblock: {ordinal}")
        superblocks.add(superblock)
        lanes = row.get("algorithmOrder")
        require(isinstance(lanes, list) and len(lanes) == 6, f"lane count mismatch: {ordinal}")
        require(len({str(lane.get("algorithmId")) for lane in lanes}) == 6, f"algorithm cohort mismatch: {ordinal}")
        require({str(lane.get("anonymousLaneId")) for lane in lanes} == {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}, f"anonymous lane mismatch: {ordinal}")
        identities.update(str(lane.get("identityBindingSha256")) for lane in lanes)
        input_rel = str(row.get("inputRelativePath"))
        require(input_rel and input_rel not in inputs, f"duplicate input: {ordinal}")
        inputs.add(input_rel)
        input_path = ROOT / input_rel
        require(sha256(input_path) == row.get("inputSha256"), f"input hash mismatch: {ordinal}")
        bundle = load_json(input_path)
        bundles.append(bundle)
        require(bundle.get("superblockId") == superblock, f"input superblock mismatch: {ordinal}")
        require(len(bundle.get("eventGroups", [])) == 24, f"event-group count mismatch: {ordinal}")
        g, n, f = int(bundle["gridEdge"]), int(bundle["agentCount"]), int(bundle["changedCellCount"])
        require(g in {64, 96, 128} and n in {32, 64, 128} and f in {1, 9, 25, 81}, f"G/N/F mismatch: {ordinal}")
        region = str(bundle.get("designRegion"))
        regions[region] += 1
        if region == "core":
            cells[(g, n, f)] += 1
        else:
            require(region == "stress" and (g, n, f) == (128, 128, 81), f"stress corner mismatch: {ordinal}")
    require(regions == Counter({"core": 108, "stress": 18}), f"region counts mismatch: {regions}")
    expected = {(g, n, f) for g in (64, 96, 128) for n in (32, 64, 128) for f in (1, 9, 25, 81)}
    require(set(cells) == expected and set(cells.values()) == {3}, "core cell coverage/replication mismatch")
    require(len(identities) == 1, "identity binding cardinality mismatch")
    batches: list[dict[str, Any]] = []
    for batch in range(6):
        selected = [bundles[i] for i in range(126) if oracle_batch_index(i) == batch]
        require(len(selected) == 21, f"oracle batch size mismatch: {batch}")
        counts = Counter(str(item["designRegion"]) for item in selected)
        require(counts == Counter({"core": 18, "stress": 3}), f"oracle batch region imbalance: {batch}")
        batches.append({"batchIndex": batch, "inputs": 21, "core": 18, "stress": 3})
    return next(iter(identities)), batches


def validate_sources() -> None:
    runner = RUNNER.read_text(encoding="utf-8-sig")
    validator = VALIDATOR.read_text(encoding="utf-8-sig")
    supervisor = SUPERVISOR.read_text(encoding="utf-8-sig")
    launcher = ACCEPTANCE_LAUNCHER.read_text(encoding="utf-8-sig")
    tool = ACCEPTANCE_TOOL.read_text(encoding="utf-8-sig")
    ast.parse(tool, filename=str(ACCEPTANCE_TOOL))
    require("Gate14ReMEInputGeometryValidatorV4_2.Validate" in runner, "runner does not call v4.2 validator")
    require("Gate14ReMEReferenceOracleV1.Evaluate" not in runner, "runner directly evaluates the reference oracle")
    require('if (mode == "oracle-batch")' in runner and "referenceOracleEvaluationsPerformedInsideLane = 0" in runner, "runner oracle-cache rule mismatch")
    for token in ("{ 64, 96, 128 }", "{ 32, 64, 128 }", "{ 1, 9, 25, 81 }", "input.gridEdge == 128 && input.agentCount == 128 && input.changedCellCount == 81"):
        require(token in validator, f"v4.2 validator policy token missing: {token}")
    for token in ("$runnerMethod = 'DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run'", "$processOrdinal -eq 775", "$batchIndex -lt 6", "manifestSchemaV4_2", "FROZEN_V4_2_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED"):
        require(token in supervisor, f"supervisor token missing: {token}")
    for token in ("FROZEN_READ_ONLY_OFFLINE_ACCEPTANCE_V4_3_ORACLE_CACHE_EXECUTION_UNAUTHORIZED", "frozen acquisition contract v4.2", "parquetBatchRows"):
        require(token in launcher, f"acceptance launcher token missing: {token}")
    parse_powershell(SUPERVISOR)
    parse_powershell(ACCEPTANCE_LAUNCHER)


def validate_readiness() -> None:
    terminal = load_json(READINESS_TERMINAL)
    require(terminal.get("status") == "PASS_EXACT_V4_2_ALGORITHM_FREE_COMPILE_READINESS", "readiness terminal status mismatch")
    require(terminal.get("unity", {}).get("naturalExitCode") == 0, "readiness Unity exit code mismatch")
    require(terminal.get("compile", {}).get("compilerErrorMatches") == 0, "readiness compiler errors present")
    require(terminal.get("compile", {}).get("burstCurrentCompilationDone") is True, "readiness Burst completion missing")
    scope = terminal.get("scope", {})
    for field in ("qualificationExecuted", "oracleAcquisitionExecuted", "algorithmLaneExecuted", "formalCollectionExecuted", "algorithmObservationsRead", "scientificDesignChanged"):
        require(scope.get(field) is False, f"readiness scope unexpectedly true: {field}")
    freeze = load_json(READINESS_FREEZE)
    require(freeze.get("status") == "PASS_FROZEN_EXACT_V4_2_ALGORITHM_FREE_COMPILE_READINESS", "readiness freeze status mismatch")


def main() -> int:
    for output in (INVENTORY, READINESS, FREEZE_MANIFEST, TERMINAL):
        require(not output.exists(), f"freeze output already exists; overwrite prohibited: {output}")
    authorization = load_json(AUTHORIZATION)
    require(authorization.get("authorizedThroughStep") == 9, "user authorization sequence mismatch")
    require(authorization.get("qualificationExecutionAuthorized") is True, "qualification execution is not authorized")
    require(authorization.get("migrationPackageBuildOrTestAuthorized") is False, "package build unexpectedly authorized")
    require(authorization.get("formalCollectionAuthorized") is False, "formal collection unexpectedly authorized")
    manifest, _ = validate_manifest()
    contract_hashes = validate_contracts()
    identity_sha, batch_summaries = validate_schedule()
    validate_sources()
    validate_readiness()
    failure_seal = load_json(FAILURE_SEAL)
    require(failure_seal.get("status") == "PASS_FAILURE_EVIDENCE_FROZEN_NO_RETRY_NO_REUSE", "attempt-010 failure seal status mismatch")
    require(failure_seal.get("sourceRootsMutationPermitted") is False, "attempt-010 failure roots permit mutation")
    require(failure_seal.get("retryResumeTopUpMergeSkipReorderReplacementOrParallelPerformed") is False, "attempt-010 failure seal records a prohibited continuation")
    unity_count = active_unity_count()
    require(unity_count == 0, f"Unity process active during freeze: {unity_count}")
    require(not NEXT_MEASURED.exists() and not NEXT_DELIVERY.exists(), "next attempt measured/delivery root is not fresh")
    free_bytes = shutil.disk_usage(ROOT).free
    required_bytes = int(load_json(EXECUTION / "load-qualification-resource-budget.v4_1.json")["qualificationReservedStorageBytes"])
    require(free_bytes >= required_bytes, "qualification storage headroom insufficient")

    rows = [inventory_row(ROOT / item["relativePath"], str(item["role"])) for item in manifest["artifacts"]]
    rows.extend([
        inventory_row(MANIFEST, "frozen-implementation-manifest-v4.2"),
        inventory_row(PLAN, "predeclared-freeze-plan-v4.2"),
        inventory_row(AUTHORIZATION, "user-authorization-receipt-v4.2"),
        inventory_row(Path(__file__), "freeze-validator-v4.2"),
    ])
    require(len({row["relativePath"] for row in rows}) == len(rows), "freeze inventory duplicate path")
    write_jsonl_exclusive(INVENTORY, rows)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    readiness = {
        "schema": "gate14re-me-qualification-frozen-readiness-receipt-v4.2",
        "studyId": "Gate14Re-ME",
        "status": "PASS_FROZEN_V4_2_V4_3_READ_ONLY_READINESS_FRESH_EXECUTION_AUTHORIZED_SEPARATELY",
        "implementationManifestRelativePath": relative(MANIFEST),
        "implementationManifestSha256": sha256(MANIFEST),
        "implementationManifestArtifacts": len(manifest["artifacts"]),
        "frozenSourceInventoryRelativePath": relative(INVENTORY),
        "frozenSourceInventorySha256": sha256(INVENTORY),
        "contractHashes": contract_hashes,
        "qualificationDesign": {
            "G": [64, 96, 128], "N": [32, 64, 128], "F": [1, 9, 25, 81],
            "coreSuperblocks": 108, "stressSuperblocks": 18, "totalSuperblocks": 126,
            "algorithmLanes": 756, "oracleBatchProcesses": 6, "plannedFreshProcesses": 775,
            "identityBindingSha256": identity_sha, "oracleBatchBalance": batch_summaries,
        },
        "technicalRepair": {
            "priorFailedAttempt": "load-qualification-execution-attempt-010",
            "failureSealSha256": sha256(FAILURE_SEAL),
            "versionOwnedGeometryValidatorSha256": sha256(VALIDATOR),
            "scientificDesignChanged": False,
        },
        "compileReadiness": {
            "terminalReceiptSha256": sha256(READINESS_TERMINAL),
            "freezeManifestSha256": sha256(READINESS_FREEZE),
            "unityNaturalExitCode": 0,
            "compilerErrors": 0,
            "burstCurrentCompilationDone": True,
        },
        "hostReadiness": {"activeUnityProcesses": unity_count, "freeStorageBytes": free_bytes, "requiredStorageBytes": required_bytes, "storageHeadroomPassed": True},
        "authorizationBoundary": {
            "freshQualificationAttemptAuthorized": True,
            "sameAttemptRetryAuthorized": False,
            "formalCollectionAuthorized": False,
            "formalAnalysisAuthorized": False,
            "rankingOrWinnerAuthorized": False,
            "migrationPackageBuildAuthorized": False,
        },
        "completedAtUtc": now,
    }
    write_json_exclusive(READINESS, readiness)
    freeze_manifest = {
        "schema": "gate14re-me-qualification-design-implementation-freeze-manifest-v4.2",
        "studyId": "Gate14Re-ME",
        "status": "FROZEN_QUALIFICATION_V4_2_V4_3_READINESS_PASS",
        "artifacts": [
            inventory_row(PLAN, "predeclared-freeze-plan-v4.2"),
            inventory_row(AUTHORIZATION, "user-authorization-receipt-v4.2"),
            inventory_row(Path(__file__), "freeze-validator-v4.2"),
            inventory_row(INVENTORY, "frozen-source-inventory-v4.2"),
            inventory_row(READINESS, "frozen-readiness-receipt-v4.2"),
            inventory_row(MANIFEST, "frozen-implementation-manifest-v4.2"),
            inventory_row(ACQUISITION, "frozen-acquisition-contract-v4.2"),
            inventory_row(ACCEPTANCE, "frozen-acceptance-contract-v4.3"),
            inventory_row(FAILURE_SEAL, "attempt-010-failure-seal"),
            inventory_row(READINESS_TERMINAL, "exact-v4.2-compile-readiness-terminal"),
            inventory_row(READINESS_FREEZE, "exact-v4.2-compile-readiness-freeze"),
        ],
        "qualificationExecutionAuthorizedBySeparateUserScope": True,
        "sameAttemptRetry": False,
        "formalSampleSizeFinalized": False,
        "migrationPackageBuildAuthorized": False,
        "createdAtUtc": now,
    }
    write_json_exclusive(FREEZE_MANIFEST, freeze_manifest)
    terminal = {
        "schema": "gate14re-me-qualification-design-implementation-freeze-terminal-v4.2",
        "studyId": "Gate14Re-ME",
        "status": "PASS_FROZEN_QUALIFICATION_V4_2_V4_3_READY_FOR_NEW_ONE_SHOT_EXECUTION",
        "freezeManifestRelativePath": relative(FREEZE_MANIFEST),
        "freezeManifestSha256": sha256(FREEZE_MANIFEST),
        "readinessReceiptRelativePath": relative(READINESS),
        "readinessReceiptSha256": sha256(READINESS),
        "implementationManifestRelativePath": relative(MANIFEST),
        "implementationManifestSha256": sha256(MANIFEST),
        "acquisitionContractSha256": sha256(ACQUISITION),
        "acceptanceContractSha256": sha256(ACCEPTANCE),
        "plannedFreshProcesses": 775,
        "priorFailedAttemptReused": False,
        "algorithmObservationsRead": False,
        "formalSampleSizeFinalized": False,
        "migrationPackageBuildAuthorized": False,
        "nextGate": "CREATE_ATTEMPT_011_ONE_SHOT_AUTHORIZATION_AND_FRESH_ROOTS",
        "completedAtUtc": now,
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
