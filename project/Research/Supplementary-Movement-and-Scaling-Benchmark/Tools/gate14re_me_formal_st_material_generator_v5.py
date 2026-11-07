#!/usr/bin/env python3
"""Generate and freeze Gate14Re-ME formal-ST v5 inputs and schedule.

The package-build workflow only runs ``known-answer``.  ``generate`` is
deliberately fail-closed behind a later, separate input-generation
authorization and writes only to a fresh reserved FormalInputs attempt root.
It never starts Unity, creates a measured root, executes an algorithm lane, or
performs a formal analysis.

Geometry construction reuses the exact qualified v4.1 algorithm-neutral
kernel by hash.  Formal v5 adds the frozen 36 x 36 schedule and the fully
crossed P factor.  For P > F, each of the F unique cells is replayed
deterministically across nonempty atomic partitions; the unique F-cell
boundary and post-group state remain identical across P variants.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import traceback
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STUDY_ID = "Gate14Re-ME"
DESIGN_ID = "gate14re-me-formal-st-bounded-gnf-v5"
PROTOCOL_ID = "gate14re-me-formal-st-v5"
INPUT_SCHEMA = "gate14re-me-formal-st-input-bundle-v5"
SCHEDULE_SCHEMA = "gate14re-me-formal-st-schedule-row-v5"
AUTH_SCHEMA = "gate14re-me-formal-st-input-generation-authorization-v5"
AUTH_STATUS = "AUTHORIZED_FORMAL_INPUT_GENERATION_ONLY"
FREEZE_STATUS = "FROZEN_FORMAL_INPUTS_AND_SCHEDULE_EXECUTION_NOT_AUTHORIZED"

GRID_LEVELS = [64, 96, 128]
AGENT_LEVELS = [32, 64, 128]
CHANGE_LEVELS = [1, 9, 25, 81]
TOPOLOGIES = ["compact", "dispersed", "bottleneck"]
GRAPH_PROFILES = ["four_way_weighted_dense", "eight_way_uniform_sparse"]
PARTITION_LEVELS = [1, 4, 16]
ALGORITHMS = ["A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"]
ANONYMOUS_LANES = ["ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"]
WILLIAMS_ORDERS = [
    ["A*-R", "BiA*-R", "IDFF", "D*L", "C-FF", "LPA*"],
    ["BiA*-R", "D*L", "A*-R", "LPA*", "IDFF", "C-FF"],
    ["D*L", "LPA*", "BiA*-R", "C-FF", "A*-R", "IDFF"],
    ["LPA*", "C-FF", "D*L", "IDFF", "BiA*-R", "A*-R"],
    ["C-FF", "IDFF", "LPA*", "A*-R", "D*L", "BiA*-R"],
    ["IDFF", "A*-R", "C-FF", "BiA*-R", "LPA*", "D*L"],
]

LINEAGE_REL = Path(
    "Research/Verification/Gate14Re-ME/"
    "qualification-planning-asset-generation-v4-attempt-002/"
    "generate_and_validate_planning_assets_v4_1.py"
)
LINEAGE_SHA256 = "a4b70d5908dfb90291747b7cdba9f5f172a10c036d4ad1f543cd16ad007e83f4"
FREEZE_INDEX_REL = Path("Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json")
FREEZE_INDEX_SHA256 = "35c3b98e42cc21b200308460c6b93fb48961b4a450522acc23958c76b70b00dd"
SCHEDULE_CONTRACT_REL = Path("Research/Gate14Re-ME/Execution/v5/formal-st-schedule-contract.v5_0.json")
SCHEDULE_CONTRACT_SHA256 = "d480b1a1fda1dda0737015e66064e58aa5f84d87fa5d594d3bab65d9b7712cbc"
FAIRNESS_REL = Path("Research/Gate14Re-ME/Execution/v5/formal-st-fairness-runtime-binding.v5_0.json")
FAIRNESS_SHA256 = "fb0aff4f17618022ad4818b0f3afbf9ce44b804f97bfd2f9027e7bd3d9a8a06f"
ORACLE_REL = Path("Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs")
ORACLE_SHA256 = "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25"
RESERVED_OUTPUT = re.compile(
    r"^Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-[0-9]{3}$"
)


class StageFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise StageFailure(message)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value))


def write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":"), allow_nan=False))
            handle.write("\n")


def project_relative(project_root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError as exc:
        raise StageFailure(f"path escapes project root: {path}") from exc


def verify_hash(project_root: Path, relative: Path, expected: str) -> Path:
    path = (project_root / relative).resolve()
    require(path.is_file(), f"required file is missing: {relative.as_posix()}")
    require(sha256_file(path) == expected, f"SHA-256 mismatch: {relative.as_posix()}")
    return path


def load_lineage(project_root: Path):
    path = verify_hash(project_root, LINEAGE_REL, LINEAGE_SHA256)
    spec = importlib.util.spec_from_file_location("gate14re_me_qualified_geometry_v4_1", path)
    require(spec is not None and spec.loader is not None, "cannot load qualified geometry lineage")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def context_id(topology: str, graph_profile: str, partitions: int) -> str:
    t = {"compact": "CMP", "dispersed": "DSP", "bottleneck": "BTN"}[topology]
    g = {"four_way_weighted_dense": "4WD", "eight_way_uniform_sparse": "8US"}[graph_profile]
    return f"CTX-{t}-{g}-P{partitions:02d}"


def seed_for(master_seed: bytes, ordinal: int) -> int:
    digest = hashlib.sha256(master_seed + b"\0Gate14Re-ME-formal-v5\0" + ordinal.to_bytes(4, "big")).digest()
    value = int.from_bytes(digest[:8], "big", signed=False) & ((1 << 63) - 1)
    return value if value != 0 else ordinal + 1


def build_design_rows(master_seed: bytes) -> list[dict[str, Any]]:
    contexts = [
        (topology, graph_profile, partitions)
        for topology in TOPOLOGIES
        for graph_profile in GRAPH_PROFILES
        for partitions in PARTITION_LEVELS
    ]
    rows: list[dict[str, Any]] = []
    cell_ordinal = 0
    for grid_edge in GRID_LEVELS:
        for agent_count in AGENT_LEVELS:
            for changed_cells in CHANGE_LEVELS:
                for replicate in range(36):
                    ordinal = len(rows)
                    context_index = replicate % 18
                    topology, graph_profile, partitions = contexts[context_index]
                    order_index = (
                        (context_index + cell_ordinal) % 6
                        if replicate < 18
                        else (context_index + 3 + cell_ordinal) % 6
                    )
                    rows.append({
                        "ordinal": ordinal,
                        "cellOrdinal": cell_ordinal,
                        "replicateIndex": replicate,
                        "contextStratumIndex": context_index,
                        "orderIndex": order_index,
                        "designRegion": "core",
                        "gridEdge": grid_edge,
                        "agentCount": agent_count,
                        "changedCellCount": changed_cells,
                        "changeTopology": topology,
                        "graphProfile": graph_profile,
                        "sameTickAtomicPartitions": partitions,
                        "contextStratumId": context_id(topology, graph_profile, partitions),
                        "seed": seed_for(master_seed, ordinal),
                        "superblockId": f"formal-sb-{ordinal:04d}",
                        "inputId": f"G14REME-V5-FI-{ordinal:04d}",
                    })
                cell_ordinal += 1
    require(len(rows) == 1296 and cell_ordinal == 36, "formal design cardinality construction failed")
    require(len({row["seed"] for row in rows}) == 1296, "derived formal seeds are not unique")
    return rows


def split_partitions_formal(cells: list[tuple[int, int]], partition_count: int) -> list[list[tuple[int, int]]]:
    require(cells and partition_count in PARTITION_LEVELS, "invalid formal partition request")
    partitions: list[list[tuple[int, int]]] = [[] for _ in range(partition_count)]
    if partition_count <= len(cells):
        for index, cell in enumerate(cells):
            partitions[index % partition_count].append(cell)
    else:
        for index in range(partition_count):
            partitions[index].append(cells[index % len(cells)])
    require(all(partitions), "formal atomic partitions must be nonempty")
    require(set(cell for part in partitions for cell in part) == set(cells), "formal partitions changed the F-cell boundary")
    return partitions


def formal_partition_checks(bundle: dict[str, Any]) -> None:
    expected_boundary: set[tuple[int, int]] | None = None
    for group in bundle["eventGroups"]:
        partitions = group["atomicPartitions"]
        require(len(partitions) == bundle["sameTickAtomicPartitions"], "formal partition count mismatch")
        boundary: set[tuple[int, int]] = set()
        for expected, partition in enumerate(partitions):
            require(partition["partitionIndex"] == expected and partition["changes"], "empty or misindexed formal partition")
            coordinates = [(item["x"], item["y"]) for item in partition["changes"]]
            require(len(coordinates) == len(set(coordinates)), "duplicate coordinate inside one formal partition")
            boundary.update(coordinates)
        require(len(boundary) == bundle["changedCellCount"], "formal event group does not contain exactly F unique cells")
        if expected_boundary is None:
            expected_boundary = boundary
        require(boundary == expected_boundary, "formal event groups do not preserve the same F-cell boundary")


def qualified_geometry_view(bundle: dict[str, Any]) -> dict[str, Any]:
    view = json.loads(json.dumps(bundle))
    view.pop("designId", None)
    view["schema"] = "gate14re-me-qualification-input-bundle-v1"
    view["protocolId"] = "gate14re-me-load-qualification-v1"
    if view["sameTickAtomicPartitions"] > view["changedCellCount"]:
        for group in view["eventGroups"]:
            unique: list[dict[str, Any]] = []
            seen: set[tuple[int, int]] = set()
            for partition in group["atomicPartitions"]:
                for cell in partition["changes"]:
                    coordinate = (cell["x"], cell["y"])
                    if coordinate not in seen:
                        seen.add(coordinate)
                        unique.append(cell)
            group["atomicPartitions"] = [{"partitionIndex": 0, "changes": unique}]
        view["sameTickAtomicPartitions"] = 1
    return view


def build_and_validate_bundle(kernel: Any, row: dict[str, Any], input_relative: str = "KAT") -> tuple[dict[str, Any], dict[str, Any]]:
    original_split = kernel.split_partitions
    try:
        kernel.split_partitions = split_partitions_formal
        bundle, baseline_walkable, baseline_costs, _ = kernel.build_input_bundle(row)
    finally:
        kernel.split_partitions = original_split
    bundle["schema"] = INPUT_SCHEMA
    bundle["studyId"] = STUDY_ID
    bundle["designId"] = DESIGN_ID
    bundle["protocolId"] = PROTOCOL_ID
    formal_partition_checks(bundle)
    view = qualified_geometry_view(bundle)
    validation = kernel.validate_bundle_geometry(
        view,
        baseline_walkable,
        baseline_costs,
        input_relative,
        sha256_bytes(canonical_bytes(bundle)),
        ORACLE_SHA256,
    )
    validation["schema"] = "gate14re-me-formal-st-offline-geometry-oracle-validation-row-v5"
    validation["protocolId"] = PROTOCOL_ID
    validation["designId"] = DESIGN_ID
    validation["formalPartitionReplayValidated"] = True
    validation["formalPartitionCount"] = bundle["sameTickAtomicPartitions"]
    validation["formalUniqueChangedCellCount"] = bundle["changedCellCount"]
    return bundle, validation


def schedule_rows(
    rows: list[dict[str, Any]],
    input_bindings: list[tuple[str, str]],
    algorithm_to_lane: dict[str, str],
    identity_sha: str,
) -> list[dict[str, Any]]:
    require(len(rows) == len(input_bindings) == 1296, "formal schedule input cardinality mismatch")
    result: list[dict[str, Any]] = []
    for row, (relative_path, input_sha) in zip(rows, input_bindings):
        order = WILLIAMS_ORDERS[row["orderIndex"]]
        result.append({
            "schema": SCHEDULE_SCHEMA,
            "ordinal": row["ordinal"],
            "cellOrdinal": row["cellOrdinal"],
            "replicateIndex": row["replicateIndex"],
            "contextStratumIndex": row["contextStratumIndex"],
            "orderIndex": row["orderIndex"],
            "superblockId": row["superblockId"],
            "inputRelativePath": relative_path,
            "inputSha256": input_sha,
            "algorithmOrder": [
                {
                    "algorithmId": algorithm,
                    "anonymousLaneId": algorithm_to_lane[algorithm],
                    "identityBindingSha256": identity_sha,
                }
                for algorithm in order
            ],
            "replacement": None,
        })
    return result


def validate_schedule(rows: list[dict[str, Any]]) -> dict[str, Any]:
    require(len(rows) == 1296, "formal schedule must contain 1296 rows")
    order_counts = Counter()
    cell_counts = Counter()
    context_counts = Counter()
    position_counts = {(cell, algorithm, position): 0 for cell in range(36) for algorithm in ALGORITHMS for position in range(6)}
    for ordinal, row in enumerate(rows):
        require(row["ordinal"] == ordinal and row["schema"] == SCHEDULE_SCHEMA, "schedule ordinal/schema mismatch")
        expected_cell = ordinal // 36
        expected_rep = ordinal % 36
        expected_context = expected_rep % 18
        expected_order = (expected_context + expected_cell) % 6 if expected_rep < 18 else (expected_context + 3 + expected_cell) % 6
        require(
            (row["cellOrdinal"], row["replicateIndex"], row["contextStratumIndex"], row["orderIndex"])
            == (expected_cell, expected_rep, expected_context, expected_order),
            f"schedule assignment mismatch at ordinal {ordinal}",
        )
        named = [item["algorithmId"] for item in row["algorithmOrder"]]
        lanes = [item["anonymousLaneId"] for item in row["algorithmOrder"]]
        require(named == WILLIAMS_ORDERS[expected_order], "named Williams row mismatch")
        require(set(named) == set(ALGORITHMS) and set(lanes) == set(ANONYMOUS_LANES), "schedule cohort mismatch")
        require(row["replacement"] is None, "v5.0 executable package freezes zero replacement")
        cell_counts[expected_cell] += 1
        context_counts[(expected_cell, expected_context)] += 1
        order_counts[expected_order] += 1
        for position, algorithm in enumerate(named):
            position_counts[(expected_cell, algorithm, position)] += 1
    require(set(cell_counts.values()) == {36} and len(cell_counts) == 36, "schedule is not B=36 per cell")
    require(set(context_counts.values()) == {2} and len(context_counts) == 648, "context strata are not repeated exactly twice per cell")
    require(order_counts == Counter({index: 216 for index in range(6)}), "overall Williams-order balance failed")
    require(set(position_counts.values()) == {6}, "within-cell algorithm-position balance failed")
    return {
        "scheduleRows": 1296,
        "structuralCells": 36,
        "rowsPerCell": 36,
        "contextStrataPerCell": 18,
        "rowsPerContextStratumPerCell": 2,
        "ordersOverallEach": 216,
        "algorithmPositionsPerCellEach": 6,
    }


def load_identity_binding(path: Path, expected_sha: str) -> tuple[dict[str, str], str]:
    require(path.is_file() and sha256_file(path) == expected_sha, "identity binding hash mismatch")
    value = json.loads(path.read_text(encoding="utf-8"))
    bijection = value.get("bijection", [])
    algorithm_to_lane = {item["algorithmId"]: item["anonymousLaneId"] for item in bijection}
    require(set(algorithm_to_lane) == set(ALGORITHMS), "identity binding algorithm cohort mismatch")
    require(set(algorithm_to_lane.values()) == set(ANONYMOUS_LANES), "identity binding is not bijective")
    return algorithm_to_lane, expected_sha


def known_answer(project_root: Path, output: Path) -> None:
    require(not output.exists(), "known-answer output path must be fresh")
    output.mkdir(parents=True)
    kernel = load_lineage(project_root)
    for relative, expected in [
        (FREEZE_INDEX_REL, FREEZE_INDEX_SHA256),
        (SCHEDULE_CONTRACT_REL, SCHEDULE_CONTRACT_SHA256),
        (FAIRNESS_REL, FAIRNESS_SHA256),
        (ORACLE_REL, ORACLE_SHA256),
    ]:
        verify_hash(project_root, relative, expected)
    master_seed = bytes.fromhex("9f" * 32)
    rows = build_design_rows(master_seed)
    identity_sha = "1" * 64
    mapping = dict(zip(ALGORITHMS, ANONYMOUS_LANES))
    bindings = [(f"KAT/input-{index:04d}.json", f"{index:064x}") for index in range(1296)]
    schedule = schedule_rows(rows, bindings, mapping, identity_sha)
    checks = validate_schedule(schedule)
    p_gt_f = next(row for row in rows if row["gridEdge"] == 64 and row["agentCount"] == 32 and row["changedCellCount"] == 1 and row["sameTickAtomicPartitions"] == 16)
    bundle, geometry = build_and_validate_bundle(kernel, p_gt_f)
    require(bundle["sameTickAtomicPartitions"] == 16 and bundle["changedCellCount"] == 1, "P>F KAT did not exercise the frozen cross")
    receipt = {
        "schema": "gate14re-me-formal-st-material-generator-known-answer-receipt-v5",
        "studyId": STUDY_ID,
        "designId": DESIGN_ID,
        "status": "PASS_FORMAL_V5_GENERATOR_KNOWN_ANSWER_NO_FORMAL_MATERIAL_CREATED",
        "passedAtUtc": utc_now(),
        "lineage": {"relativePath": LINEAGE_REL.as_posix(), "sha256": LINEAGE_SHA256},
        "scheduleChecks": checks,
        "geometryCheck": {
            "case": {"G":64,"N":32,"F":1,"P":16},
            "status": geometry["status"],
            "formalPartitionReplayValidated": geometry["formalPartitionReplayValidated"],
        },
        "scope": {
            "formalInputsGenerated": 0,
            "formalScheduleRowsPersisted": 0,
            "formalMeasuredRootCreated": False,
            "unityInvocations": 0,
            "algorithmLaneExecutions": 0,
            "formalCollectionPerformed": False,
            "formalAnalysisPerformed": False,
            "mqPerformed": False,
            "mtPerformed": False,
        },
    }
    write_json(output / "terminal-receipt.v5.json", receipt)
    print(json.dumps({"status": receipt["status"], "receiptSha256": sha256_file(output / "terminal-receipt.v5.json")}, separators=(",", ":")))


def generate(project_root: Path, output_root: Path, authorization_path: Path, authorization_sha: str) -> None:
    require(authorization_path.is_file() and sha256_file(authorization_path) == authorization_sha, "generation authorization hash mismatch")
    authorization = json.loads(authorization_path.read_text(encoding="utf-8"))
    require(authorization.get("schema") == AUTH_SCHEMA and authorization.get("status") == AUTH_STATUS, "generation authorization header mismatch")
    require(authorization.get("formalInputGenerationAuthorized") is True, "input generation is not authorized")
    for prohibited in ["formalRootCreationAuthorized","formalCollectionAuthorized","formalAcceptanceExecutionAuthorized","formalAnalysisAuthorized","mqAuthorized","mtAuthorized"]:
        require(authorization.get(prohibited) is False, f"generation authorization exceeds its boundary: {prohibited}")
    relative_output = project_relative(project_root, output_root)
    require(RESERVED_OUTPUT.fullmatch(relative_output) is not None, "output root is not a reserved formal-input attempt")
    require(authorization.get("outputRootRelativePath") == relative_output, "authorization output-root mismatch")
    require(not output_root.exists(), "formal-input output root must be fresh")
    master_seed_hex = authorization.get("masterSeedHex", "")
    require(re.fullmatch(r"[0-9a-f]{64}", master_seed_hex) is not None, "master seed must be 32-byte lowercase hex")
    master_seed = bytes.fromhex(master_seed_hex)
    require(authorization.get("masterSeedCommitmentSha256") == sha256_bytes(master_seed), "master-seed commitment mismatch")
    identity_rel = authorization.get("identityBindingRelativePath", "")
    identity_sha = authorization.get("identityBindingSha256", "")
    identity_path = (project_root / identity_rel).resolve()
    require(project_relative(project_root, identity_path) == identity_rel, "identity binding path is noncanonical")
    algorithm_to_lane, identity_sha = load_identity_binding(identity_path, identity_sha)

    kernel = load_lineage(project_root)
    for relative, expected in [
        (FREEZE_INDEX_REL, FREEZE_INDEX_SHA256),
        (SCHEDULE_CONTRACT_REL, SCHEDULE_CONTRACT_SHA256),
        (FAIRNESS_REL, FAIRNESS_SHA256),
        (ORACLE_REL, ORACLE_SHA256),
    ]:
        verify_hash(project_root, relative, expected)

    output_root.mkdir(parents=True)
    rows = build_design_rows(master_seed)
    input_bindings: list[tuple[str, str]] = []
    validations: list[dict[str, Any]] = []
    input_paths: list[Path] = []
    try:
        for row in rows:
            filename = f"{row['superblockId']}.input.v5.json"
            path = output_root / "inputs" / filename
            relative = project_relative(project_root, path)
            bundle, validation = build_and_validate_bundle(kernel, row, relative)
            write_json(path, bundle)
            input_sha = sha256_file(path)
            validation["inputSha256"] = input_sha
            input_bindings.append((relative, input_sha))
            validations.append(validation)
            input_paths.append(path)

        schedule = schedule_rows(rows, input_bindings, algorithm_to_lane, identity_sha)
        checks = validate_schedule(schedule)
        schedule_path = output_root / "schedule" / "formal-st-williams-schedule.v5.jsonl"
        validation_path = output_root / "validation" / "offline-geometry-oracle-validation.v5.jsonl"
        write_jsonl(schedule_path, schedule)
        write_jsonl(validation_path, validations)

        artifact_paths = input_paths + [schedule_path, validation_path, authorization_path, identity_path]
        artifacts = [{
            "relativePath": project_relative(project_root, path),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        } for path in artifact_paths]
        manifest = {
            "schema": "gate14re-me-formal-st-input-freeze-manifest-v5",
            "studyId": STUDY_ID,
            "designId": DESIGN_ID,
            "status": FREEZE_STATUS,
            "authorizationId": authorization.get("authorizationId"),
            "inputCount": 1296,
            "scheduleRowCount": 1296,
            "scheduleRelativePath": project_relative(project_root, schedule_path),
            "scheduleSha256": sha256_file(schedule_path),
            "identityBindingRelativePath": identity_rel,
            "identityBindingSha256": identity_sha,
            "scheduleChecks": checks,
            "artifactCount": len(artifacts),
            "artifacts": artifacts,
            "scope": {
                "formalMeasuredRootCreated": False,
                "unityInvocations": 0,
                "algorithmLaneExecutions": 0,
                "formalCollectionPerformed": False,
                "formalAnalysisPerformed": False,
                "mqPerformed": False,
                "mtPerformed": False,
            },
            "createdAtUtc": utc_now(),
        }
        manifest_path = output_root / "formal-input-freeze-manifest.v5.json"
        write_json(manifest_path, manifest)
        terminal = {
            "schema": "gate14re-me-formal-st-input-generation-terminal-receipt-v5",
            "studyId": STUDY_ID,
            "designId": DESIGN_ID,
            "status": "PASS_FORMAL_INPUTS_FROZEN_EXECUTION_NOT_AUTHORIZED",
            "inputFreezeManifestRelativePath": project_relative(project_root, manifest_path),
            "inputFreezeManifestSha256": sha256_file(manifest_path),
            "completedAtUtc": utc_now(),
            "scope": manifest["scope"],
        }
        terminal_path = output_root / "terminal-receipt.v5.json"
        write_json(terminal_path, terminal)
        for path in sorted(output_root.rglob("*")):
            if path.is_file():
                os.chmod(path, stat.S_IREAD)
        print(json.dumps({"status": terminal["status"], "terminalSha256": sha256_file(terminal_path)}, separators=(",", ":")))
    except Exception:
        failure_path = output_root / "failure-receipt.v5.json"
        if not failure_path.exists():
            write_json(failure_path, {
                "schema": "gate14re-me-formal-st-input-generation-failure-receipt-v5",
                "studyId": STUDY_ID,
                "status": "FAIL_CLOSED_FORMAL_INPUT_GENERATION",
                "error": traceback.format_exc(),
                "failedAtUtc": utc_now(),
                "formalCollectionPerformed": False,
                "formalAnalysisPerformed": False,
            })
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["known-answer", "generate"])
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--authorization")
    parser.add_argument("--authorization-sha256")
    args = parser.parse_args()
    project_root = Path(args.project_root).resolve()
    output = Path(args.output).resolve()
    try:
        if args.mode == "known-answer":
            known_answer(project_root, output)
        else:
            require(bool(args.authorization and args.authorization_sha256), "generate mode requires exact authorization path and SHA-256")
            generate(project_root, output, Path(args.authorization).resolve(), args.authorization_sha256)
        return 0
    except Exception as exc:
        print(f"FAIL_CLOSED: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
