#!/usr/bin/env python3
"""Structural-only preflight for Gate 13R-PR2 attempt-4 Phase B.

The preflight verifies provenance hashes, schedule/manifests structure, frozen
implementation safeguards, synthetic self-tests, and the *absence* of both a
formal execution authorization and a formal analysis output root.  It does not
open any block workload-result file and does not calculate P1-P5 values.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import uuid
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


PREFLIGHT_ID = "gate13r-pr2-attempt4-phaseb-structural-preflight-v2"
CONTRACT_KIND = "GATE13R-PR2-ATTEMPT4-PHASEB-FROZEN-EXECUTION-CONTRACT"
PAYLOAD_BASE_RELATIVE_PATH = "campaigns"
V1_ANALYZER_ID = "gate13r-pr2-attempt4-phaseb-analyzer-v1"
V2_ANALYZER_ID = "gate13r-pr2-attempt4-phaseb-analyzer-v2"
FORBIDDEN_PYTHON_IMPORTS = {"subprocess", "socket", "requests", "urllib", "http", "ftplib"}
FORBIDDEN_POWERSHELL_COMMANDS = (
    "Start-Process",
    "Invoke-WebRequest",
    "Invoke-RestMethod",
    "Remove-Item",
    "Set-Content",
    "Add-Content",
    "Out-File",
    "Stop-Process",
)


class PreflightError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PreflightError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        value = json.load(handle)
    require(isinstance(value, dict), f"JSON root must be an object: {path}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            value = json.loads(stripped)
            require(isinstance(value, dict), f"JSONL row {line_number} is not an object: {path}")
            yield value


def write_json_new(path: Path, value: dict[str, Any]) -> None:
    require(not path.exists(), f"immutable preflight report already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
    with temporary.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def resolve_relative(root: Path, relative_path: str, label: str) -> Path:
    require(isinstance(relative_path, str) and relative_path.strip(), f"{label}: empty path")
    candidate = (root / Path(relative_path.replace("/", os.sep))).resolve()
    resolved_root = root.resolve()
    require(candidate == resolved_root or candidate.is_relative_to(resolved_root), f"{label}: escapes project root")
    return candidate


def verify_binding(project_root: Path, binding: dict[str, Any], label: str) -> Path:
    require(isinstance(binding, dict), f"{label}: invalid binding")
    path = resolve_relative(project_root, str(binding.get("relativePath", "")), label)
    require(path.is_file(), f"{label}: missing file")
    expected_hash = str(binding.get("sha256", "")).lower()
    require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"{label}: malformed SHA-256")
    require(sha256_file(path) == expected_hash, f"{label}: SHA-256 mismatch")
    return path


def raw_metadata_identity(raw_root: Path) -> dict[str, Any]:
    """Hash path/size/mtime metadata without opening raw payload content."""
    digest = hashlib.sha256()
    count = 0
    total_bytes = 0
    for path in sorted((item for item in raw_root.rglob("*") if item.is_file()), key=lambda p: p.as_posix()):
        stat_result = path.stat()
        relative = path.relative_to(raw_root).as_posix()
        digest.update(f"{relative}\t{stat_result.st_size}\t{stat_result.st_mtime_ns}\n".encode("utf-8"))
        count += 1
        total_bytes += stat_result.st_size
    return {"fileCount": count, "rawBytes": total_bytes, "metadataSha256": digest.hexdigest()}


def inspect_repair_delta(
    v1_analyzer_path: Path,
    v2_analyzer_path: Path,
    v1_wrapper_path: Path,
    v2_wrapper_path: Path,
) -> dict[str, Any]:
    """Prove that v2 contains only the authorized functional repair and version bindings."""
    v1_analyzer = v1_analyzer_path.read_text(encoding="utf-8-sig")
    v2_analyzer = v2_analyzer_path.read_text(encoding="utf-8-sig")
    old_id = f'ANALYZER_ID = "{V1_ANALYZER_ID}"'
    new_id = f'ANALYZER_ID = "{V2_ANALYZER_ID}"'
    old_resolution = 'path = resolve_relative(raw_root, relative, "raw payload")'
    new_resolution = 'path = resolve_relative(raw_root / "campaigns", relative, "raw payload")'
    require(v1_analyzer.count(old_id) == 1, "v1 analyzer ID anchor is not unique")
    require(v1_analyzer.count(old_resolution) == 1, "v1 payload-resolution anchor is not unique")
    expected_analyzer = v1_analyzer.replace(old_id, new_id, 1).replace(old_resolution, new_resolution, 1)
    require(v2_analyzer == expected_analyzer, "v2 analyzer differs from v1 beyond the authorized two-line repair delta")

    v1_wrapper = v1_wrapper_path.read_text(encoding="utf-8-sig")
    v2_wrapper = v2_wrapper_path.read_text(encoding="utf-8-sig")
    old_contract = "Research\\Gate13R_PR2_Attempt4_PhaseB_Execution_Contract.v1.json"
    new_contract = "Research\\Gate13R_PR2_Attempt4_PhaseB_Execution_Contract.v2.json"
    require(v1_wrapper.count(old_contract) == 1, "v1 wrapper contract anchor is not unique")
    expected_wrapper = v1_wrapper.replace(old_contract, new_contract, 1)
    require(v2_wrapper == expected_wrapper, "v2 wrapper differs from v1 beyond the authorized contract-version binding")
    return {
        "soleAuthorizedFunctionalDelta": "RAW-PAYLOAD-MANIFEST-RELATIVE-PATH-BASE-RAWROOT/CAMPAIGNS",
        "analyzerDeltaExact": True,
        "analyzerIdVersionChangeOnlyOtherThanFunctionalDelta": True,
        "wrapperContractBindingVersionChangeOnly": True,
        "statisticalAnalysisCodeUnchanged": True,
        "v1AnalyzerSha256": sha256_file(v1_analyzer_path),
        "v2AnalyzerSha256": sha256_file(v2_analyzer_path),
        "v1WrapperSha256": sha256_file(v1_wrapper_path),
        "v2WrapperSha256": sha256_file(v2_wrapper_path),
    }


def inspect_contract_equivalence(v1: dict[str, Any], v2: dict[str, Any]) -> dict[str, Any]:
    """Verify the repair contract preserves all statistical/input/output semantics."""
    for key in (
        "frozenInputBindings",
        "design",
        "statisticalContract",
        "executionSequenceAfterFutureAuthorization",
        "output",
        "failClosedRules",
        "explicitExclusions",
    ):
        require(v2.get(key) == v1.get(key), f"v2 contract changed frozen semantic section: {key}")
    for key in ("gate", "formalAttemptOrdinal", "phase", "purpose"):
        require(v2.get("scope", {}).get(key) == v1.get("scope", {}).get(key), f"v2 contract changed scope field: {key}")
    raw_keys = (
        "rootRelativePath",
        "mode",
        "canonicalRawTreeSha256",
        "expectedOutputFileCount",
        "expectedRawBytes",
        "formalExecutionMustVerifyEveryPayloadFileSha256BeforeOutcomeLoading",
        "formalExecutionMustCompareRawMetadataIdentityBeforeAndAfterAnalysis",
        "writesInsideRawRootForbidden",
    )
    for key in raw_keys:
        require(v2.get("rawInput", {}).get(key) == v1.get("rawInput", {}).get(key), f"v2 contract changed raw-input field: {key}")
    require(
        v2.get("rawInput", {}).get("payloadManifestRelativePathBase") == "rawRoot/campaigns",
        "v2 contract lacks the authorized payload manifest path-base repair",
    )
    require(
        v2.get("implementationBindings", {}).get("outputSchema") == v1.get("implementationBindings", {}).get("outputSchema"),
        "v2 contract changed the frozen output-schema binding",
    )
    return {
        "frozenInputBindingsExact": True,
        "designExact": True,
        "statisticalContractExact": True,
        "executionSequenceExact": True,
        "outputSpecificationExact": True,
        "failClosedRulesExact": True,
        "explicitExclusionsExact": True,
        "outputSchemaBindingExact": True,
        "soleSemanticChange": "rawInput.payloadManifestRelativePathBase=rawRoot/campaigns",
    }


def inspect_analyzer(path: Path) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8-sig")
    tree = ast.parse(source, filename=str(path))
    imported_roots: set[str] = set()
    forbidden_calls: list[str] = []
    exact_movement_metric_constants: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_roots.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_roots.add(node.module.split(".")[0])
        elif isinstance(node, ast.Call):
            function = node.func
            if isinstance(function, ast.Attribute) and isinstance(function.value, ast.Name):
                qualified = f"{function.value.id}.{function.attr}"
                if qualified in {"os.system", "os.popen", "os.spawnl", "os.spawnv"}:
                    forbidden_calls.append(qualified)
            elif isinstance(function, ast.Name) and function.id in {"eval", "exec", "compile"}:
                forbidden_calls.append(function.id)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value in {"M1", "M2", "M3", "M4", "M5"}:
            exact_movement_metric_constants.append(node.value)
    require(not (imported_roots & FORBIDDEN_PYTHON_IMPORTS), f"analyzer imports forbidden modules: {sorted(imported_roots & FORBIDDEN_PYTHON_IMPORTS)}")
    require(not forbidden_calls, f"analyzer contains forbidden calls: {forbidden_calls}")
    require(not exact_movement_metric_constants, "analyzer contains an exact M1-M5 metric constant")
    require("if __name__ == \"__main__\":" in source, "analyzer lacks a main guard")
    require("phaseBFormalStatisticalAnalysisAuthorized" in source, "analyzer lacks explicit Phase B authorization guard")
    require("gate14RAuthorized" in source, "analyzer lacks explicit Gate 14R guard")
    require("rawRootMutationAuthorized" in source, "analyzer lacks explicit raw-root mutation guard")
    require(
        'resolve_relative(raw_root / "campaigns", relative, "raw payload")' in source,
        "analyzer lacks the frozen rawRoot/campaigns payload-manifest base repair",
    )
    return {
        "astParsed": True,
        "importedModuleRoots": sorted(imported_roots),
        "forbiddenImportsFound": [],
        "forbiddenCallsFound": [],
        "exactM1ThroughM5MetricConstantsFound": [],
        "mainGuardPresent": True,
        "authorizationGuardsPresent": True,
        "payloadManifestBaseRepairPresent": True,
    }


def inspect_wrapper(path: Path) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8-sig")
    found = [command for command in FORBIDDEN_POWERSHELL_COMMANDS if re.search(rf"(?im)^\s*&?\s*{re.escape(command)}\b", source)]
    require(not found, f"wrapper contains forbidden command invocation(s): {found}")
    for required in (
        "phaseBFormalStatisticalAnalysisAuthorized",
        "formalOutcomeDataLoadingAuthorized",
        "gate14RAuthorized",
        "rawRootMutationAuthorized",
        "unityLaunchOrControlAuthorized",
        "contractSha256",
    ):
        require(required in source, f"wrapper lacks required guard: {required}")
    require("Get-FileHash" in source, "wrapper does not verify implementation hashes")
    return {
        "parsedAsText": True,
        "forbiddenCommandInvocationsFound": [],
        "separateAuthorizationGuardsPresent": True,
        "implementationHashChecksPresent": True,
    }


def run_analyzer_self_test(path: Path) -> dict[str, Any]:
    specification = importlib.util.spec_from_file_location("gate13r_attempt4_phaseb_analyzer_preflight", path)
    require(specification is not None and specification.loader is not None, "cannot import analyzer for synthetic self-test")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    result = module.run_self_test()
    require(result.get("selfTest") == "PASS", "analyzer synthetic self-test did not pass")
    require(result.get("analyzerId") == V2_ANALYZER_ID, "analyzer synthetic self-test returned the wrong analyzer ID")
    require(result.get("formalRawOpened") is False, "self-test claims formal raw was opened")
    require(result.get("formalAnalysisExecuted") is False, "self-test claims formal analysis was executed")
    require(result.get("gate14RExecuted") is False, "self-test claims Gate 14R was executed")
    return result


def inspect_schedule(path: Path) -> dict[str, Any]:
    process_count = 0
    sample_count = 0
    ordinals: list[int] = []
    block_ids: set[str] = set()
    run_ids: set[str] = set()
    cohort_process_counts = Counter()
    cohort_sample_counts = Counter()
    shared_williams = Counter()
    heterogeneous_williams = Counter()
    matched: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in iter_jsonl(path):
        process_count += 1
        ordinal = int(row.get("globalProcessOrdinal", -1))
        ordinals.append(ordinal)
        block_id = str(row.get("blockId", ""))
        require(block_id and block_id not in block_ids, f"duplicate or empty blockId: {block_id}")
        block_ids.add(block_id)
        cohort = str(row.get("comparisonCohortId", ""))
        cohort_process_counts[cohort] += 1
        entries = row.get("entries", [])
        require(isinstance(entries, list) and len(entries) == int(row.get("expectedSampleCount", -1)), f"schedule entry count mismatch at ordinal {ordinal}")
        sample_count += len(entries)
        cohort_sample_counts[cohort] += len(entries)
        algorithms = [str(entry.get("algorithmId", "")) for entry in entries]
        positions = [int(entry.get("position", -1)) for entry in entries]
        require(len(set(algorithms)) == len(algorithms), f"duplicate algorithm at ordinal {ordinal}")
        require(sorted(positions) == list(range(1, len(entries) + 1)), f"invalid positions at ordinal {ordinal}")
        for entry in entries:
            run_id = str(entry.get("runId", ""))
            require(run_id and run_id not in run_ids, f"duplicate/empty schedule runId: {run_id}")
            run_ids.add(run_id)
        row_index = int(row.get("williamsRowIndex", -1))
        if cohort == "four-algorithm-shared-goal-v1":
            require(set(algorithms) == {"A*-R", "D*L", "IDFF", "C-FF"}, f"shared algorithm set mismatch at ordinal {ordinal}")
            shared_williams[row_index] += 1
            require(row.get("matchedSuperblock") is None, f"shared row unexpectedly has matchedSuperblock at ordinal {ordinal}")
        else:
            require(cohort in {"per-agent-heterogeneous-goal-v1", "grouped-field-heterogeneous-goal-v1"}, f"unexpected cohort: {cohort}")
            require(len(entries) == 2, f"heterogeneous row is not two-algorithm at ordinal {ordinal}")
            heterogeneous_williams[row_index] += 1
            matched_value = row.get("matchedSuperblock")
            require(isinstance(matched_value, dict), f"heterogeneous row lacks matchedSuperblock at ordinal {ordinal}")
            matched[str(matched_value.get("matchedSuperblockId", ""))].append(row)
    require(process_count == 3552, "schedule process count is not 3552")
    require(sample_count == 10176, "schedule sample count is not 10176")
    require(sorted(ordinals) == list(range(1, 3553)), "schedule ordinals are not exactly 1..3552")
    require(len(run_ids) == 10176, "schedule run IDs are not unique")
    require(cohort_process_counts == Counter({
        "four-algorithm-shared-goal-v1": 1536,
        "per-agent-heterogeneous-goal-v1": 1008,
        "grouped-field-heterogeneous-goal-v1": 1008,
    }), "schedule cohort process counts differ from frozen design")
    require(shared_williams == Counter({0: 384, 1: 384, 2: 384, 3: 384}), "shared Williams rows are not balanced")
    require(len(matched) == 1008, "matched superblock count is not 1008")
    order_counts = Counter()
    for identifier, pair in matched.items():
        require(identifier and len(pair) == 2, f"matched superblock {identifier!r} does not contain two processes")
        cohorts = {str(row["comparisonCohortId"]) for row in pair}
        require(cohorts == {"per-agent-heterogeneous-goal-v1", "grouped-field-heterogeneous-goal-v1"}, f"matched superblock {identifier} cohort pair mismatch")
        pair_by_cohort = {str(row["comparisonCohortId"]): row for row in pair}
        per_agent_value = pair_by_cohort["per-agent-heterogeneous-goal-v1"]["matchedSuperblock"]
        grouped_field_value = pair_by_cohort["grouped-field-heterogeneous-goal-v1"]["matchedSuperblock"]
        for shared_key in (
            "cohortOrder",
            "deterministicInputIdentity",
            "matchedSuperblockId",
            "matchedSuperblockOrdinal",
            "pairGlobalProcessOrdinals",
            "scenarioOrdinal",
        ):
            require(per_agent_value.get(shared_key) == grouped_field_value.get(shared_key), f"matched superblock {identifier} {shared_key} mismatch")
        require(str(per_agent_value.get("cohortRole", "")) == "A-PER-AGENT", f"matched superblock {identifier} per-agent role mismatch")
        require(str(grouped_field_value.get("cohortRole", "")) == "B-GROUPED-FIELD", f"matched superblock {identifier} grouped-field role mismatch")
        order = str(per_agent_value.get("cohortOrder", ""))
        require(order in {"AB", "BA"}, f"matched superblock {identifier} invalid order")
        expected_positions = {"AB": (1, 2), "BA": (2, 1)}
        per_agent_position, grouped_field_position = expected_positions[order]
        require(int(per_agent_value.get("cohortProcessPosition", -1)) == per_agent_position, f"matched superblock {identifier} per-agent position mismatch")
        require(int(grouped_field_value.get("cohortProcessPosition", -1)) == grouped_field_position, f"matched superblock {identifier} grouped-field position mismatch")
        order_counts[order] += 1
        pair_ordinals = sorted(int(row["globalProcessOrdinal"]) for row in pair)
        require(pair_ordinals[1] == pair_ordinals[0] + 1, f"matched superblock {identifier} is not adjacent")
    require(order_counts == Counter({"AB": 504, "BA": 504}), "matched-superblock AB/BA orders are not balanced")
    return {
        "processCount": process_count,
        "sampleCount": sample_count,
        "uniqueBlockIdCount": len(block_ids),
        "uniqueRunIdCount": len(run_ids),
        "cohortProcessCounts": dict(sorted(cohort_process_counts.items())),
        "cohortSampleCounts": dict(sorted(cohort_sample_counts.items())),
        "sharedWilliamsRowCounts": {str(key): value for key, value in sorted(shared_williams.items())},
        "heterogeneousWilliamsProcessRowCounts": {str(key): value for key, value in sorted(heterogeneous_williams.items())},
        "matchedSuperblockCount": len(matched),
        "matchedSuperblockOrderCounts": dict(sorted(order_counts.items())),
    }


def inspect_payload_manifest(path: Path, raw_root: Path, base_relative_path: str) -> dict[str, Any]:
    require(base_relative_path == PAYLOAD_BASE_RELATIVE_PATH, "payload manifest base is not the frozen campaigns directory")
    payload_root = resolve_relative(raw_root, base_relative_path, "raw payload base")
    require(payload_root.is_dir(), "raw payload base directory is missing")
    count = 0
    declared_raw_bytes = 0
    actual_raw_bytes = 0
    legacy_direct_resolution_existing_file_count = 0
    relative_paths: set[str] = set()
    for entry in iter_jsonl(path):
        relative = str(entry.get("relativePath", ""))
        digest = str(entry.get("sha256", "")).lower()
        size = entry.get("rawBytes")
        require(relative and relative not in relative_paths, f"duplicate/empty raw payload path: {relative}")
        normalized = PurePosixPath(relative.replace("\\", "/"))
        require(not normalized.is_absolute(), f"absolute raw payload path: {relative}")
        require(".." not in normalized.parts, f"raw payload path traverses upward: {relative}")
        require(normalized.parts and normalized.parts[0] != PAYLOAD_BASE_RELATIVE_PATH, f"raw payload path duplicates campaigns base: {relative}")
        require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, f"malformed raw payload SHA for {relative}")
        require(isinstance(size, int) and not isinstance(size, bool) and size >= 0, f"invalid raw payload size for {relative}")
        resolved = resolve_relative(payload_root, relative, "raw payload")
        require(resolved.is_file(), f"raw payload file does not resolve below rawRoot/campaigns: {relative}")
        actual_size = resolved.stat().st_size
        require(actual_size == size, f"raw payload byte mismatch: {relative}")
        legacy_candidate = resolve_relative(raw_root, relative, "legacy raw payload resolution")
        if legacy_candidate.is_file():
            legacy_direct_resolution_existing_file_count += 1
        relative_paths.add(relative)
        count += 1
        declared_raw_bytes += size
        actual_raw_bytes += actual_size
    require(count == 89472, "payload manifest file count is not 89472")
    require(declared_raw_bytes == 26429810187, "payload manifest declared raw-byte total mismatch")
    require(actual_raw_bytes == declared_raw_bytes, "payload manifest actual raw-byte total mismatch")
    require(legacy_direct_resolution_existing_file_count == 0, "legacy rawRoot-direct resolution unexpectedly finds payload files")
    return {
        "relativePathResolutionBase": "rawRoot/campaigns",
        "resolvedPayloadRoot": str(payload_root),
        "manifestRows": count,
        "declaredRawBytes": declared_raw_bytes,
        "actualRawBytes": actual_raw_bytes,
        "uniqueRelativePathCount": len(relative_paths),
        "existingFileCount": count,
        "sizeMatchCount": count,
        "legacyRawRootDirectResolutionExistingFileCount": legacy_direct_resolution_existing_file_count,
        "payloadFilesOpened": False,
        "payloadFileHashesComputed": False,
        "outcomeValuesRead": False,
    }


def inspect_top_manifests(eligibility_path: Path, evidence_path: Path) -> dict[str, Any]:
    eligibility = load_json(eligibility_path)
    evidence = load_json(evidence_path)
    commits = eligibility.get("blockCommits", [])
    blocks = evidence.get("blocks", [])
    require(eligibility.get("allCompletedBlocksFormallyEligible") is True, "eligibility manifest aggregate flag is not true")
    require(len(commits) == 3552, "eligibility commit reference count mismatch")
    require(len(blocks) == 3552, "raw evidence block reference count mismatch")
    require(int(eligibility.get("processCount", -1)) == 3552 and int(eligibility.get("sampleCount", -1)) == 10176, "eligibility aggregate counts mismatch")
    require(int(evidence.get("processCount", -1)) == 3552 and int(evidence.get("sampleCount", -1)) == 10176, "evidence aggregate counts mismatch")
    commit_paths = [str(item.get("relativePath", "")) for item in commits]
    evidence_ordinals = [int(item.get("globalProcessOrdinal", -1)) for item in blocks]
    require(len(set(commit_paths)) == 3552 and all(commit_paths), "eligibility commit paths are not unique")
    require(sorted(evidence_ordinals) == list(range(1, 3553)), "evidence ordinals are not exactly 1..3552")
    for item in commits:
        require(re.fullmatch(r"[0-9a-f]{64}", str(item.get("sha256", "")).lower()) is not None, "malformed eligibility commit SHA")
    for item in blocks:
        require(re.fullmatch(r"[0-9a-f]{64}", str(item.get("blockManifestSha256", "")).lower()) is not None, "malformed evidence block SHA")
    return {
        "eligibilityCommitReferenceCount": len(commits),
        "rawEvidenceBlockReferenceCount": len(blocks),
        "processCount": 3552,
        "sampleCount": 10176,
        "perBlockCommitFilesOpened": False,
        "blockManifestFilesOpened": False,
        "workloadResultFilesOpened": False,
    }


def freeze_files(paths: list[Path]) -> list[dict[str, Any]]:
    result = []
    for path in paths:
        require(path.is_file(), f"freeze target missing: {path}")
        before_hash = sha256_file(path)
        path.chmod(stat.S_IREAD)
        after_hash = sha256_file(path)
        require(before_hash == after_hash, f"freeze target content changed while setting read-only: {path}")
        result.append({
            "path": str(path),
            "sha256": after_hash,
            "readOnlyAttributeRequested": True,
            "osWritableAfterFreeze": os.access(path, os.W_OK),
        })
    return result


def run_preflight(project_root: Path, contract_path: Path, timestamp_utc: str) -> dict[str, Any]:
    project_root = project_root.resolve()
    contract_path = contract_path.resolve()
    require(project_root.is_dir(), "project root does not exist")
    require(contract_path.is_file(), "Phase B contract does not exist")
    require(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", timestamp_utc) is not None, "invalid preflight timestamp")
    contract = load_json(contract_path)
    require(contract.get("contractKind") == CONTRACT_KIND, "wrong contract kind")
    require(contract.get("contractId") == "gate13r-pr2-attempt4-phaseb-formal-analysis-v2", "wrong v2 contract ID")
    require(contract.get("contractStatus") == "FROZEN-AWAITING-SEPARATE-EXECUTION-AUTHORIZATION", "wrong contract status")
    boundary = contract.get("authorizationBoundary", {})
    require(boundary.get("phaseBExecutionAuthorizedByThisContract") is False, "contract self-authorizes Phase B")
    require(boundary.get("formalOutcomeDataLoadingAuthorized") is False, "contract authorizes outcome loading")
    require(boundary.get("gate14RAuthorized") is False, "contract authorizes Gate 14R")
    require(boundary.get("rawRootMutationAuthorized") is False, "contract authorizes raw mutation")

    preparation_path = verify_binding(project_root, contract["preparationAuthorizationBinding"], "preparation authorization")
    preparation = load_json(preparation_path)
    require(
        preparation.get("authorizationKind") == "GATE13R-PR2-ATTEMPT4-PHASEB-V2-REPAIR-PREPARATION-ONLY",
        "wrong v2 repair-preparation authorization kind",
    )
    require(
        preparation.get("repairScope", {}).get("soleAuthorizedFunctionalDelta")
        == "RAW-PAYLOAD-MANIFEST-RELATIVE-PATH-BASE-RAWROOT/CAMPAIGNS",
        "preparation authorization does not limit the repair to the sole authorized delta",
    )
    prep_boundary = preparation.get("authorizationBoundary", {})
    require(prep_boundary.get("phaseBFormalStatisticalAnalysisExecutionAuthorized") is False, "preparation authorization permits formal execution")
    require(prep_boundary.get("formalOutcomeDataLoadingAuthorized") is False, "preparation authorization permits outcome loading")
    require(prep_boundary.get("gate14RAuthorized") is False, "preparation authorization permits Gate 14R")

    implementation_paths = {
        label: verify_binding(project_root, binding, f"implementation {label}")
        for label, binding in contract["implementationBindings"].items()
    }
    input_paths = {
        label: verify_binding(project_root, binding, f"input {label}")
        for label, binding in contract["frozenInputBindings"].items()
    }
    lineage_paths = {
        label: verify_binding(project_root, binding, f"repair lineage {label}")
        for label, binding in contract["repairLineage"]["bindings"].items()
    }

    expected_auth_path = resolve_relative(project_root, contract["separateExecutionAuthorization"]["expectedRelativePath"], "future execution authorization")
    output_root = resolve_relative(project_root, contract["output"]["rootRelativePath"], "formal analysis output root")
    report_path = resolve_relative(project_root, contract["preflight"]["reportRelativePath"], "preflight report")
    require(not expected_auth_path.exists(), "formal Phase B execution authorization unexpectedly exists")
    require(not output_root.exists(), "formal Phase B output root unexpectedly exists")
    require(not report_path.exists(), "immutable preflight report already exists")
    require(
        lineage_paths["v1ExecutionAuthorization"].is_file(),
        "historical v1 execution authorization is missing from repair lineage",
    )
    historical_v1_authorization = load_json(lineage_paths["v1ExecutionAuthorization"])
    require(
        historical_v1_authorization.get("contractSha256") == sha256_file(lineage_paths["v1Contract"]),
        "historical v1 authorization is not bound to the v1 contract",
    )
    require(
        historical_v1_authorization.get("contractRelativePath")
        == lineage_paths["v1Contract"].relative_to(project_root).as_posix(),
        "historical v1 authorization contract path mismatch",
    )

    raw_root = resolve_relative(project_root, str(contract["rawInput"]["rootRelativePath"]), "frozen raw root")
    require(raw_root.is_dir(), "frozen raw root is missing")
    require(output_root != raw_root and not output_root.is_relative_to(raw_root), "analysis output cannot be inside raw root")
    raw_execution_manifest = load_json(input_paths["rawExecutionManifest"])
    require(
        raw_execution_manifest.get("rawPayloadRootRelativePath") == PAYLOAD_BASE_RELATIVE_PATH,
        "raw execution manifest does not bind its payload root to campaigns",
    )
    raw_metadata_before = raw_metadata_identity(raw_root)

    freeze_receipt = load_json(input_paths["rawDataFreezeReceipt"])
    raw_ready_audit = load_json(input_paths["formalRawReadyAudit"])
    require(freeze_receipt.get("allCompletedBlocksFormallyEligible") is True, "raw freeze receipt eligibility flag failed")
    require(freeze_receipt.get("allPayloadFilesReadOnly") is True, "raw freeze receipt read-only flag failed")
    require(freeze_receipt.get("analysisAuthorized") is False and freeze_receipt.get("analysisPending") is True, "raw freeze receipt analysis boundary changed")
    require(freeze_receipt.get("gate14RAuthorized") is False, "raw freeze receipt Gate 14R boundary changed")
    require(raw_ready_audit.get("passed") is True, "formal raw-ready audit did not pass")
    require(raw_ready_audit.get("phaseBAnalysisExecuted") is False, "raw-ready audit says Phase B executed")
    require(raw_ready_audit.get("gate14RExecuted") is False, "raw-ready audit says Gate 14R executed")

    repair_delta_inspection = inspect_repair_delta(
        lineage_paths["v1Analyzer"],
        implementation_paths["analyzer"],
        lineage_paths["v1Wrapper"],
        implementation_paths["executionWrapper"],
    )
    v1_contract = load_json(lineage_paths["v1Contract"])
    contract_equivalence = inspect_contract_equivalence(v1_contract, contract)
    analyzer_inspection = inspect_analyzer(implementation_paths["analyzer"])
    wrapper_inspection = inspect_wrapper(implementation_paths["executionWrapper"])
    self_test = run_analyzer_self_test(implementation_paths["analyzer"])
    schedule_inspection = inspect_schedule(input_paths["formalSchedule"])
    top_manifest_inspection = inspect_top_manifests(
        input_paths["blockFormalEligibilityManifest"], input_paths["rawBlockEvidenceManifest"]
    )
    payload_manifest_inspection = inspect_payload_manifest(
        input_paths["rawPayloadFileManifest"], raw_root, PAYLOAD_BASE_RELATIVE_PATH
    )

    output_schema = load_json(implementation_paths["outputSchema"])
    require(output_schema.get("explicitExclusions", {}).get("gate14RAuthorized") is False, "output schema Gate 14R exclusion missing")
    require(output_schema.get("explicitExclusions", {}).get("movementMetricIdsForbidden") == ["M1", "M2", "M3", "M4", "M5"], "output schema M1-M5 exclusion mismatch")
    artifact_names = [str(item.get("relativePath")) for item in output_schema.get("requiredArtifactsInCommitOrder", [])]
    require(artifact_names == contract["output"]["requiredArtifactRelativePaths"], "contract/output-schema artifact lists differ")
    raw_metadata_after = raw_metadata_identity(raw_root)
    require(raw_metadata_after == raw_metadata_before, "frozen raw-root metadata changed during structural preflight")

    report: dict[str, Any] = {
        "schemaVersion": 1,
        "preflightId": PREFLIGHT_ID,
        "createdAtUtc": timestamp_utc,
        "status": "PASS-READY-FOR-SEPARATE-PHASEB-EXECUTION-AUTHORIZATION",
        "contractRelativePath": contract_path.relative_to(project_root).as_posix(),
        "contractSha256": sha256_file(contract_path),
        "authorizationState": {
            "preparationAuthorized": True,
            "phaseBFormalStatisticalAnalysisExecutionAuthorized": False,
            "formalOutcomeDataLoadingAuthorized": False,
            "separateExecutionAuthorizationPath": expected_auth_path.relative_to(project_root).as_posix(),
            "separateExecutionAuthorizationFileState": "ABSENT",
            "formalAnalysisOutputRootState": "ABSENT",
            "gate14RAuthorized": False,
        },
        "checks": {
            "allFrozenInputHashesMatch": True,
            "allImplementationHashesMatch": True,
            "allRepairLineageHashesMatch": True,
            "preparationAuthorizationBoundaryPass": True,
            "historicalV1ExecutionAuthorizationBoundOnlyToV1": True,
            "v2ExecutionAuthorizationAbsent": True,
            "rawFreezeReceiptPass": True,
            "formalRawReadyAuditPass": True,
            "uniqueRepairDelta": repair_delta_inspection,
            "contractSemanticEquivalence": contract_equivalence,
            "rawExecutionManifestPayloadRootRelativePath": PAYLOAD_BASE_RELATIVE_PATH,
            "scheduleStructure": schedule_inspection,
            "topManifestStructure": top_manifest_inspection,
            "rawPayloadManifestStructure": payload_manifest_inspection,
            "rawMetadataIdentityBefore": raw_metadata_before,
            "rawMetadataIdentityAfter": raw_metadata_after,
            "rawMetadataIdentityUnchanged": True,
            "analyzerStaticInspection": analyzer_inspection,
            "wrapperStaticInspection": wrapper_inspection,
            "analyzerSyntheticSelfTest": self_test,
            "outputSchemaBoundaryPass": True,
        },
        "nonActions": {
            "blockManifestsOpened": False,
            "workloadResultFilesOpened": False,
            "P1ThroughP5OutcomeValuesRead": False,
            "formalStatisticalAnalysisExecuted": False,
            "formalAnalysisOutputCreated": False,
            "rawRootWritten": False,
            "rawPayloadContentOpened": False,
            "rawPayloadHashesComputed": False,
            "unityLaunchedOrControlled": False,
            "gate14RExecuted": False,
            "M1ThroughM5ReadDerivedOrReported": False,
        },
        "nextRequiredGate": {
            "action": "SEPARATE-EXPLICIT-PHASEB-V2-FORMAL-ANALYSIS-EXECUTION-AUTHORIZATION",
            "mustBindContractSha256": True,
            "mustKeepGate14RUnauthorized": True,
        },
        "pythonVersion": sys.version,
    }
    write_json_new(report_path, report)
    freeze_targets = [
        contract_path,
        preparation_path,
        implementation_paths["analyzer"],
        implementation_paths["executionWrapper"],
        implementation_paths["preflight"],
        implementation_paths["outputSchema"],
    ]
    frozen = freeze_files(freeze_targets)
    report_path.chmod(stat.S_IREAD)
    return {
        "status": report["status"],
        "reportPath": str(report_path),
        "reportSha256": sha256_file(report_path),
        "frozenArtifactCount": len(frozen),
        "formalStatisticalAnalysisExecuted": False,
        "gate14RAuthorized": False,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gate 13R-PR2 attempt-4 Phase B structural-only preflight")
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--timestamp-utc", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = run_preflight(arguments.project_root, arguments.contract, arguments.timestamp_utc)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except PreflightError as error:
        print(json.dumps({
            "status": "FAIL-CLOSED",
            "reason": str(error),
            "formalStatisticalAnalysisExecuted": False,
            "gate14RAuthorized": False,
        }, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
