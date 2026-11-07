#!/usr/bin/env python3
"""Generate and freeze Gate14Re-ME bounded-window v4 planning assets.

This tool is deliberately offline and algorithm neutral.  It never imports or
constructs a planner, never starts Unity, and never creates a measured root.
It implements the frozen goal-rooted Dijkstra oracle semantics solely to
qualify candidate input geometry before any later algorithm-lane execution.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import heapq
import json
import math
import os
import random
import secrets
import shutil
import stat
import subprocess
import sys
import traceback
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STUDY_ID = "Gate14Re-ME"
PROTOCOL_ID = "gate14re-me-load-qualification-v1"
DESIGN_ID = "gate14re-me-bounded-gnf-discrimination-window-v4"
AUTHORIZATION_ID = "gate14re-me-qualification-planning-asset-generation-v4-attempt-002"
ATTEMPT_REL = Path(
    "Research/Verification/Gate14Re-ME/"
    "qualification-planning-asset-generation-v4-attempt-002"
)
ASSET_REL = ATTEMPT_REL / "planning-assets"

INPUT_SCHEMA_REL = Path("Research/Gate14Re-ME/Execution/v4/load-qualification-input-schema.v4_0.json")
SCHEDULE_SCHEMA_REL = Path("Research/Gate14Re-ME/Execution/v4/load-qualification-schedule-schema.v4_0.json")
OUTPUT_SCHEMA_REL = Path("Research/Gate14Re-ME/Execution/v4/load-qualification-output-schema.v4_0.json")
FAIRNESS_REL = Path("Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1_2.json")
ORACLE_SOURCE_REL = Path("Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs")
DESIGN_REL = Path("Research/Verification/Gate14Re-ME/gnf-discrimination-window-design-v2-attempt-001/selected-gnf-design.v2.json")
DESIGN_TERMINAL_REL = Path("Research/Verification/Gate14Re-ME/gnf-discrimination-window-design-v2-attempt-001/terminal-receipt.v2.json")
ACCEPTANCE_FEASIBILITY_TERMINAL_REL = Path("Research/Verification/Gate14Re-ME/load-qualification-acceptance-v4-feasibility-attempt-001/delivery/terminal-final.v4.json")

EXPECTED_HASHES = {
    DESIGN_REL.as_posix(): "aec051d91accd2af8e51baa3a7f8cfd41458065a8551f11a2dec9981bc2cacfd",
    DESIGN_TERMINAL_REL.as_posix(): "6bb7302ba03f02b2b9e7b3e673bfddb93b055d8a3f1e6391111f2a62480abb9f",
    ACCEPTANCE_FEASIBILITY_TERMINAL_REL.as_posix(): "8e23efa3dda65b437eb096c48740c68df7f0271859c7fabf28e40e664e03ef9e",
    INPUT_SCHEMA_REL.as_posix(): "bc891db7548443ee5b3e4b4e1a6173dd264c8e7cd96d92fb6bbe51c9b1ddbdaa",
    SCHEDULE_SCHEMA_REL.as_posix(): "32a1c01abfae216aaa3bc091e704b2d0eb39a43d0fe84028c49782dc22db578e",
    OUTPUT_SCHEMA_REL.as_posix(): "bbf73acaa031331e99db93bfe58affa1f998871eee45040a2bf80c3dc7b0028e",
    FAIRNESS_REL.as_posix(): "ed7d45a47ee5cc1882e0cfe57daf0735be73f0ee84f50f45e4724726d96e5291",
    ORACLE_SOURCE_REL.as_posix(): "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25",
}

ALGORITHMS = ["A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"]
LANES = ["ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"]
GRID_LEVELS = [64, 96, 128]
AGENT_LEVELS = [32, 64, 128]
CHANGE_LEVELS = [1, 9, 25, 81]
TOPOLOGIES = ["compact", "dispersed", "bottleneck"]
GRAPH_PROFILES = ["four_way_weighted_dense", "eight_way_uniform_sparse"]
PARTITION_LEVELS = [1, 4, 16]
PHASES = ["block", "unblock_or_restore", "increase_cost", "decrease_or_restore_cost"]

# Standard six-treatment even-order Williams square.  Rows balance treatment
# position and first-order carryover; every row is repeated exactly 21 times.
WILLIAMS_LANE_SEQUENCES = [
    ["ALG-A", "ALG-B", "ALG-F", "ALG-C", "ALG-E", "ALG-D"],
    ["ALG-B", "ALG-C", "ALG-A", "ALG-D", "ALG-F", "ALG-E"],
    ["ALG-C", "ALG-D", "ALG-B", "ALG-E", "ALG-A", "ALG-F"],
    ["ALG-D", "ALG-E", "ALG-C", "ALG-F", "ALG-B", "ALG-A"],
    ["ALG-E", "ALG-F", "ALG-D", "ALG-A", "ALG-C", "ALG-B"],
    ["ALG-F", "ALG-A", "ALG-E", "ALG-B", "ALG-D", "ALG-C"],
]

DIAGONAL_DISTANCE = 1.4142135623730951
DIJKSTRA_TOLERANCE = 1e-12


class StageFailure(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_json_bytes(value))


def write_jsonl(path: Path, values: Iterable[Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for value in values:
            handle.write(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False))
            handle.write("\n")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise StageFailure(message)


def project_relative(project_root: Path, path: Path) -> str:
    resolved = path.resolve()
    root = project_root.resolve()
    try:
        return resolved.relative_to(root).as_posix()
    except ValueError as exc:
        raise StageFailure(f"path escapes project root: {resolved}") from exc


def verify_file(project_root: Path, relative_path: str, expected_sha: str) -> None:
    path = project_root / Path(relative_path)
    require(path.is_file(), f"missing frozen file: {relative_path}")
    actual = sha256_file(path)
    require(actual == expected_sha, f"frozen hash drift: {relative_path}; expected {expected_sha}; actual {actual}")


def verify_no_gate14reme_unity_process(project_root: Path) -> list[dict[str, Any]]:
    pwsh = shutil.which("pwsh") or shutil.which("powershell")
    require(bool(pwsh), "PowerShell is required for the read-only Unity process check")
    escaped_root = str(project_root).replace("'", "''")
    command = (
        "$items = Get-CimInstance Win32_Process | Where-Object { "
        "$_.Name -match '^Unity(Editor)?\\.exe$' -and "
        f"(($_.CommandLine -like '*{escaped_root}*') -or ($_.CommandLine -match 'Gate14ReME'))"
        " } | Select-Object ProcessId,Name,CreationDate,ExecutablePath,CommandLine; "
        "if ($null -eq $items) { '[]' } else { @($items) | ConvertTo-Json -Depth 5 -Compress }"
    )
    completed = subprocess.run(
        [pwsh, "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    require(completed.returncode == 0, f"Unity process query failed: {completed.stderr.strip()}")
    payload = completed.stdout.strip() or "[]"
    parsed = json.loads(payload)
    if isinstance(parsed, dict):
        parsed = [parsed]
    require(isinstance(parsed, list), "Unity process query returned an invalid payload")
    require(len(parsed) == 0, f"unexpected Gate14Re-ME Unity process(es) are active: {parsed}")
    return parsed


def verify_upstream(project_root: Path) -> dict[str, Any]:
    for relative_path, expected_sha in EXPECTED_HASHES.items():
        verify_file(project_root, relative_path, expected_sha)

    design = load_json(project_root / DESIGN_REL)
    require(design.get("schema") == "gate14re-me-selected-gnf-design-v2", "selected GNF design identity mismatch")
    require(design.get("levels") == {"G": GRID_LEVELS, "N": AGENT_LEVELS, "F": CHANGE_LEVELS}, "selected GNF levels mismatch")
    structure = design.get("structure", {})
    require(structure.get("coreCells") == 36, "selected design core-cell count mismatch")
    require(structure.get("qualificationCoreSuperblocks") == 108, "selected design core count mismatch")
    require(structure.get("stressContextStrata") == 18, "selected design context-stratum count mismatch")
    require(structure.get("qualificationTotalSuperblocks") == 126, "selected design total count mismatch")
    require(structure.get("qualificationAlgorithmLanes") == 756, "selected design lane count mismatch")
    require(structure.get("qualificationTotalFreshProcesses") == 895, "selected design process count mismatch")
    require(structure.get("strictSerialFreshProcesses") is True and structure.get("pairedWilliamsOrder") is True, "selected design execution structure mismatch")

    design_terminal = load_json(project_root / DESIGN_TERMINAL_REL)
    require(
        design_terminal.get("status") == "PASS_PROPOSED_3X3X4_BOUNDED_GNF_WINDOW_NO_EXECUTION_STARTED",
        "selected design terminal receipt is not the expected bounded-window PASS",
    )
    acceptance_terminal = load_json(project_root / ACCEPTANCE_FEASIBILITY_TERMINAL_REL)
    require(
        acceptance_terminal.get("status") == "PASS_FEASIBILITY_STREAMING_ESSENTIAL_ACCEPTANCE_FROZEN"
        and acceptance_terminal.get("typedParquetRoundTripPass") is True
        and acceptance_terminal.get("sourceRootsModified") is False,
        "streaming essential acceptance feasibility is not a clean PASS",
    )

    fairness = load_json(project_root / FAIRNESS_REL)
    require(fairness.get("revision") == "1.2", "fairness revision mismatch")
    require([item["algorithmId"] for item in fairness["algorithms"]] == ALGORITHMS, "fairness algorithm order mismatch")
    for item in fairness["algorithms"]:
        verify_file(project_root, item["implementationRelativePath"], item["implementationSha256"])
        verify_file(project_root, item["specificationRelativePath"], item["specificationSha256"])

    free_bytes = shutil.disk_usage(project_root.anchor).free
    planning_reservation = 10_737_418_240
    require(free_bytes >= planning_reservation, f"insufficient free storage for v4 planning: free={free_bytes}; required={planning_reservation}")
    verify_no_gate14reme_unity_process(project_root)

    return {
        "explicitHashBindingsChecked": len(EXPECTED_HASHES),
        "freeBytesAtPreflight": free_bytes,
        "planningReservationBytesRequired": planning_reservation,
        "selectedCoreCells": 36,
        "selectedSuperblocks": 126,
        "selectedAlgorithmLanes": 756,
        "selectedFreshProcesses": 895,
        "streamingEssentialAcceptanceFeasibilityPass": True,
        "gate14ReMEUnityProcesses": 0,
    }


def context_id(topology: str, graph_profile: str, partitions: int) -> str:
    t = {"compact": "CMP", "dispersed": "DSP", "bottleneck": "BTN"}[topology]
    g = {"four_way_weighted_dense": "4WD", "eight_way_uniform_sparse": "8US"}[graph_profile]
    return f"CTX-{t}-{g}-P{partitions:02d}"


def partition_for_core(changed_cells: int, replicate_index: int) -> int:
    if changed_cells == 1:
        return 1
    if changed_cells == 9:
        return 1 if replicate_index == 0 else 4
    if changed_cells == 25:
        return 4 if replicate_index < 2 else 16
    if changed_cells == 81:
        return 16
    raise StageFailure(f"unknown F level: {changed_cells}")


def build_design_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    partition_counters = {1: 0, 4: 0, 16: 0}
    context_pairs = [(t, g) for t in TOPOLOGIES for g in GRAPH_PROFILES]

    core_index = 0
    for grid_edge in GRID_LEVELS:
        for agent_count in AGENT_LEVELS:
            for changed_cells in CHANGE_LEVELS:
                for replicate_index in range(3):
                    partitions = partition_for_core(changed_cells, replicate_index)
                    pair_index = partition_counters[partitions] % len(context_pairs)
                    partition_counters[partitions] += 1
                    topology, graph_profile = context_pairs[pair_index]
                    ordinal = len(rows)
                    rows.append(
                        {
                            "ordinal": ordinal,
                            "regionIndex": core_index,
                            "designRegion": "core",
                            "replicateIndex": replicate_index,
                            "gridEdge": grid_edge,
                            "agentCount": agent_count,
                            "changedCellCount": changed_cells,
                            "changeTopology": topology,
                            "graphProfile": graph_profile,
                            "sameTickAtomicPartitions": partitions,
                            "contextStratumId": context_id(topology, graph_profile, partitions),
                            "seed": -1_600_000_001 - ordinal,
                            "superblockId": f"G14ME-V4-QSB-C{core_index + 1:03d}",
                            "inputId": f"G14ME-V4-QI-C{core_index + 1:03d}",
                            "williamsSequenceIndex": ordinal % 6,
                        }
                    )
                    core_index += 1

    require(core_index == 108, "core design cardinality construction failed")
    require(partition_counters == {1: 36, 4: 36, 16: 36}, f"core partition balance construction failed: {partition_counters}")

    stress_index = 0
    for topology in TOPOLOGIES:
        for graph_profile in GRAPH_PROFILES:
            for partitions in PARTITION_LEVELS:
                ordinal = len(rows)
                rows.append(
                    {
                        "ordinal": ordinal,
                        "regionIndex": stress_index,
                        "designRegion": "stress",
                        "replicateIndex": 0,
                        "gridEdge": 128,
                        "agentCount": 128,
                        "changedCellCount": 81,
                        "changeTopology": topology,
                        "graphProfile": graph_profile,
                        "sameTickAtomicPartitions": partitions,
                        "contextStratumId": context_id(topology, graph_profile, partitions),
                        "seed": -1_600_000_001 - ordinal,
                        "superblockId": f"G14ME-V4-QSB-S{stress_index + 1:03d}",
                        "inputId": f"G14ME-V4-QI-S{stress_index + 1:03d}",
                        "williamsSequenceIndex": stress_index % 6,
                    }
                )
                stress_index += 1

    require(stress_index == 18 and len(rows) == 126, "stress/total design cardinality construction failed")
    return rows


def choose_starts(grid_edge: int, count: int, seed: int) -> list[tuple[int, int]]:
    candidates = [
        (x, y)
        for y in range(1, grid_edge - 1)
        for x in range(1, grid_edge // 4 + 1)
    ]
    require(len(candidates) >= count, "insufficient left-region start candidates")
    rng = random.Random((abs(seed) << 1) ^ (grid_edge << 17) ^ count)
    rng.shuffle(candidates)
    return candidates[:count]


def baseline_grid(
    grid_edge: int,
    graph_profile: str,
    starts: list[tuple[int, int]],
    goal: tuple[int, int],
) -> tuple[list[bool], list[float], list[dict[str, Any]], tuple[int, int]]:
    size = grid_edge * grid_edge
    walkable = [True] * size
    costs = [1.0] * size
    wall_x = grid_edge // 2
    gate = (wall_x, grid_edge // 2)
    overrides: dict[tuple[int, int], tuple[bool, float]] = {}

    for y in range(grid_edge):
        if (wall_x, y) != gate:
            overrides[(wall_x, y)] = (False, 1.0)

    if graph_profile == "four_way_weighted_dense":
        # A dense walkable graph with a deterministic weighted band before the
        # mandatory crossing.  The wall itself creates a single algorithm-
        # neutral gate, while the band makes the four-way profile genuinely
        # weighted without inflating the bundle to a full-grid override.
        weighted_x = wall_x - 1
        for y in range(grid_edge):
            overrides[(weighted_x, y)] = (True, 1.25)
    elif graph_profile != "eight_way_uniform_sparse":
        raise StageFailure(f"unknown graph profile: {graph_profile}")

    start_set = set(starts)
    require(gate not in start_set and goal not in start_set, "gate/goal conflicts with starts")
    require(goal != gate, "goal conflicts with gate")

    rendered: list[dict[str, Any]] = []
    for (x, y), (is_walkable, traversal_cost) in sorted(overrides.items(), key=lambda item: (item[0][1], item[0][0])):
        index = y * grid_edge + x
        walkable[index] = is_walkable
        costs[index] = traversal_cost
        rendered.append({"x": x, "y": y, "isWalkable": is_walkable, "traversalCost": traversal_cost})

    for coordinate in starts + [goal, gate]:
        index = coordinate[1] * grid_edge + coordinate[0]
        require(walkable[index], f"required baseline coordinate is blocked: {coordinate}")
    return walkable, costs, rendered, gate


def select_changed_cells(
    grid_edge: int,
    changed_cell_count: int,
    topology: str,
    seed: int,
    starts: list[tuple[int, int]],
    goal: tuple[int, int],
    gate: tuple[int, int],
) -> list[tuple[int, int]]:
    excluded = set(starts)
    excluded.add(goal)
    candidates = [
        (x, y)
        for y in range(grid_edge)
        for x in range(grid_edge)
        if (x, y) not in excluded and (x, y) != gate
    ]

    if topology == "compact":
        candidates.sort(key=lambda c: (max(abs(c[0] - gate[0]), abs(c[1] - gate[1])), abs(c[0] - gate[0]) + abs(c[1] - gate[1]), c[1], c[0]))
    elif topology == "dispersed":
        rng = random.Random((abs(seed) << 7) ^ 0x5D15E25ED)
        rng.shuffle(candidates)
    elif topology == "bottleneck":
        wall = [c for c in candidates if c[0] == gate[0]]
        row = [c for c in candidates if c[1] == gate[1] and c[0] != gate[0]]
        rest = [c for c in candidates if c[0] != gate[0] and c[1] != gate[1]]
        wall.sort(key=lambda c: (abs(c[1] - gate[1]), c[1]))
        row.sort(key=lambda c: (abs(c[0] - gate[0]), c[0]))
        rest.sort(key=lambda c: (abs(c[0] - gate[0]) + abs(c[1] - gate[1]), c[1], c[0]))
        candidates = wall + row + rest
    else:
        raise StageFailure(f"unknown topology: {topology}")

    selected = [gate] + candidates[: changed_cell_count - 1]
    require(len(selected) == changed_cell_count, "changed-cell selector cardinality failed")
    require(len(set(selected)) == changed_cell_count, "changed-cell selector produced duplicates")
    require(not (set(selected) & excluded), "changed-cell selector included a start or goal")
    return selected


def split_partitions(cells: list[tuple[int, int]], partition_count: int) -> list[list[tuple[int, int]]]:
    require(partition_count <= len(cells), "nonempty atomic partitions require P <= F")
    partitions: list[list[tuple[int, int]]] = [[] for _ in range(partition_count)]
    for index, coordinate in enumerate(cells):
        partitions[index % partition_count].append(coordinate)
    require(all(partitions), "atomic partition construction produced an empty partition")
    return partitions


def build_input_bundle(row: dict[str, Any]) -> tuple[dict[str, Any], list[bool], list[float], list[tuple[int, int]]]:
    grid_edge = row["gridEdge"]
    goal = (grid_edge - 2, grid_edge // 2)
    starts = choose_starts(grid_edge, row["agentCount"], row["seed"])
    baseline_walkable, baseline_costs, overrides, gate = baseline_grid(
        grid_edge, row["graphProfile"], starts, goal
    )
    selected = select_changed_cells(
        grid_edge,
        row["changedCellCount"],
        row["changeTopology"],
        row["seed"],
        starts,
        goal,
        gate,
    )
    partitions = split_partitions(selected, row["sameTickAtomicPartitions"])

    def baseline_state(coordinate: tuple[int, int]) -> tuple[bool, float]:
        index = coordinate[1] * grid_edge + coordinate[0]
        return baseline_walkable[index], baseline_costs[index]

    event_groups: list[dict[str, Any]] = []
    for group_index in range(24):
        phase = PHASES[group_index % 4]
        rendered_partitions: list[dict[str, Any]] = []
        for partition_index, partition_cells in enumerate(partitions):
            changes: list[dict[str, Any]] = []
            for x, y in partition_cells:
                base_walkable, base_cost = baseline_state((x, y))
                if phase == "block":
                    state_walkable, state_cost = False, base_cost
                elif phase == "increase_cost":
                    state_walkable, state_cost = base_walkable, base_cost * 9.0
                else:
                    state_walkable, state_cost = base_walkable, base_cost
                changes.append(
                    {"x": x, "y": y, "isWalkable": state_walkable, "traversalCost": state_cost}
                )
            rendered_partitions.append({"partitionIndex": partition_index, "changes": changes})
        event_groups.append(
            {
                "eventGroupId": f"{row['inputId']}:EG{group_index:02d}",
                "eventGroupIndex": group_index,
                "cycleIndex": group_index // 4,
                "phase": phase,
                "topology": row["changeTopology"],
                "atomicPartitions": rendered_partitions,
            }
        )

    connectivity = 4 if row["graphProfile"] == "four_way_weighted_dense" else 8
    bundle = {
        "schema": "gate14re-me-qualification-input-bundle-v1",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "inputId": row["inputId"],
        "superblockId": row["superblockId"],
        "designRegion": row["designRegion"],
        "seed": row["seed"],
        "gridEdge": grid_edge,
        "agentCount": row["agentCount"],
        "changedCellCount": row["changedCellCount"],
        "changeTopology": row["changeTopology"],
        "graphProfile": row["graphProfile"],
        "sameTickAtomicPartitions": row["sameTickAtomicPartitions"],
        "contextStratumId": row["contextStratumId"],
        "connectivity": connectivity,
        "allowDiagonalCornerCutting": False,
        "defaultTraversalCost": 1.0,
        "initialCellOverrides": overrides,
        "goal": {"x": goal[0], "y": goal[1]},
        "starts": [{"x": x, "y": y} for x, y in starts],
        "eventGroups": event_groups,
    }
    return bundle, baseline_walkable, baseline_costs, selected


def can_traverse(
    walkable: list[bool],
    grid_edge: int,
    from_coord: tuple[int, int],
    to_coord: tuple[int, int],
    connectivity: int,
    allow_corner_cutting: bool,
) -> bool:
    fx, fy = from_coord
    tx, ty = to_coord
    if not (0 <= fx < grid_edge and 0 <= fy < grid_edge and 0 <= tx < grid_edge and 0 <= ty < grid_edge):
        return False
    if not walkable[fy * grid_edge + fx] or not walkable[ty * grid_edge + tx]:
        return False
    dx, dy = tx - fx, ty - fy
    ax, ay = abs(dx), abs(dy)
    if connectivity == 4:
        return ax + ay == 1
    if ax > 1 or ay > 1 or ax + ay == 0:
        return False
    if ax == 1 and ay == 1 and not allow_corner_cutting:
        horizontal = (fx + dx, fy)
        vertical = (fx, fy + dy)
        return walkable[horizontal[1] * grid_edge + horizontal[0]] and walkable[vertical[1] * grid_edge + vertical[0]]
    return True


def evaluate_oracle(
    walkable: list[bool],
    costs: list[float],
    grid_edge: int,
    goal: tuple[int, int],
    starts: list[tuple[int, int]],
    connectivity: int,
    allow_corner_cutting: bool,
) -> list[tuple[bool, float, int]]:
    goal_index = goal[1] * grid_edge + goal[0]
    require(walkable[goal_index], "oracle goal must be walkable")
    cell_count = grid_edge * grid_edge
    distances = [math.inf] * cell_count
    steps = [2**31 - 1] * cell_count
    distances[goal_index] = 0.0
    steps[goal_index] = 0
    sequence = 0
    heap: list[tuple[float, int, int, int, int, int]] = [(0.0, 0, goal[1], goal[0], sequence, goal_index)]
    offsets = [(0, -1), (-1, 0), (1, 0), (0, 1)] if connectivity == 4 else [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)
    ]

    while heap:
        node_cost, node_steps, y, x, _, node_index = heapq.heappop(heap)
        if node_cost > distances[node_index] + DIJKSTRA_TOLERANCE:
            continue
        if abs(node_cost - distances[node_index]) <= DIJKSTRA_TOLERANCE and node_steps > steps[node_index]:
            continue
        current = (x, y)
        for ox, oy in offsets:
            predecessor = (x + ox, y + oy)
            if not can_traverse(walkable, grid_edge, predecessor, current, connectivity, allow_corner_cutting):
                continue
            diagonal = predecessor[0] != x and predecessor[1] != y
            edge_cost = costs[node_index] * (DIAGONAL_DISTANCE if diagonal else 1.0)
            candidate = node_cost + edge_cost
            candidate_steps = node_steps + 1
            predecessor_index = predecessor[1] * grid_edge + predecessor[0]
            improves = candidate + DIJKSTRA_TOLERANCE < distances[predecessor_index]
            equal_but_shorter = abs(candidate - distances[predecessor_index]) <= DIJKSTRA_TOLERANCE and candidate_steps < steps[predecessor_index]
            if not improves and not equal_but_shorter:
                continue
            distances[predecessor_index] = candidate
            steps[predecessor_index] = candidate_steps
            sequence += 1
            heapq.heappush(
                heap,
                (candidate, candidate_steps, predecessor[1], predecessor[0], sequence, predecessor_index),
            )

    result: list[tuple[bool, float, int]] = []
    for x, y in starts:
        index = y * grid_edge + x
        if not walkable[index] or math.isinf(distances[index]):
            result.append((False, -1.0, -1))
        else:
            result.append((True, distances[index], steps[index]))
    return result


def csharp_float_text(value: float) -> str:
    if value.is_integer():
        return str(int(value))
    return format(value, ".9g")


def grid_state_sha(walkable: list[bool], costs: list[float], grid_edge: int) -> str:
    digest = hashlib.sha256()
    digest.update(f"{grid_edge}x{grid_edge}\n".encode("utf-8"))
    for y in range(grid_edge):
        for x in range(grid_edge):
            index = y * grid_edge + x
            digest.update(
                f"{x},{y},{'1' if walkable[index] else '0'},{csharp_float_text(costs[index])}\n".encode("utf-8")
            )
    return digest.hexdigest()


def nearly_equal(left: float, right: float) -> bool:
    scale = max(1.0, abs(left), abs(right))
    return abs(left - right) <= 1e-9 * scale


def median(values: list[float]) -> float:
    require(len(values) > 0, "median requires at least one value")
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[middle])
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def apply_group(
    bundle: dict[str, Any],
    group: dict[str, Any],
    walkable: list[bool],
    costs: list[float],
) -> list[tuple[int, int]]:
    grid_edge = bundle["gridEdge"]
    changed: list[tuple[int, int]] = []
    for expected_partition, partition in enumerate(group["atomicPartitions"]):
        require(partition["partitionIndex"] == expected_partition, "atomic partition index mismatch")
        require(len(partition["changes"]) > 0, "empty atomic partition")
        for cell in partition["changes"]:
            coordinate = (cell["x"], cell["y"])
            require(coordinate not in changed, "duplicate changed cell in event group")
            require(0 <= coordinate[0] < grid_edge and 0 <= coordinate[1] < grid_edge, "changed cell outside grid")
            require(math.isfinite(cell["traversalCost"]) and cell["traversalCost"] > 0, "invalid traversal cost")
            changed.append(coordinate)
            index = coordinate[1] * grid_edge + coordinate[0]
            walkable[index] = bool(cell["isWalkable"])
            costs[index] = float(cell["traversalCost"])
    return changed


def validate_bundle_geometry(
    bundle: dict[str, Any],
    baseline_walkable: list[bool],
    baseline_costs: list[float],
    input_relative_path: str,
    input_sha: str,
    oracle_source_sha: str,
) -> dict[str, Any]:
    required_keys = {
        "schema", "studyId", "protocolId", "inputId", "superblockId", "designRegion", "seed",
        "gridEdge", "agentCount", "changedCellCount", "changeTopology", "graphProfile",
        "sameTickAtomicPartitions", "contextStratumId", "connectivity", "allowDiagonalCornerCutting",
        "defaultTraversalCost", "initialCellOverrides", "goal", "starts", "eventGroups",
    }
    require(set(bundle) == required_keys, f"input top-level property set mismatch: {bundle.get('inputId')}")
    require(bundle["schema"] == "gate14re-me-qualification-input-bundle-v1", "input schema identity mismatch")
    require(bundle["studyId"] == STUDY_ID and bundle["protocolId"] == PROTOCOL_ID, "input study/protocol mismatch")
    require(bundle["gridEdge"] in GRID_LEVELS and bundle["agentCount"] in AGENT_LEVELS and bundle["changedCellCount"] in CHANGE_LEVELS, "input frozen load level mismatch")
    require(bundle["sameTickAtomicPartitions"] in PARTITION_LEVELS, "input partition level mismatch")
    require(bundle["changeTopology"] in TOPOLOGIES and bundle["graphProfile"] in GRAPH_PROFILES, "input context level mismatch")
    require(bundle["sameTickAtomicPartitions"] <= bundle["changedCellCount"], "input has impossible P > F nonempty partition structure")
    require(len(bundle["starts"]) == bundle["agentCount"], "start count differs from N")
    require(len(bundle["eventGroups"]) == 24, "event-group count differs from 24")
    if bundle["graphProfile"] == "four_way_weighted_dense":
        require(bundle["connectivity"] == 4 and bundle["allowDiagonalCornerCutting"] is False, "four-way profile semantics mismatch")
    else:
        require(bundle["connectivity"] == 8, "eight-way profile semantics mismatch")
    if bundle["designRegion"] == "stress":
        require((bundle["gridEdge"], bundle["agentCount"], bundle["changedCellCount"]) == (128, 128, 81), "stress input is not the frozen v4 high corner")

    grid_edge = bundle["gridEdge"]
    starts = [(item["x"], item["y"]) for item in bundle["starts"]]
    goal = (bundle["goal"]["x"], bundle["goal"]["y"])
    require(len(starts) == len(set(starts)), "starts are not unique")
    require(goal not in set(starts), "goal equals a start")
    for coordinate in starts + [goal]:
        x, y = coordinate
        require(0 <= x < grid_edge and 0 <= y < grid_edge, "start/goal outside grid")
        require(baseline_walkable[y * grid_edge + x], "start/goal blocked in baseline")

    baseline = evaluate_oracle(
        baseline_walkable,
        baseline_costs,
        grid_edge,
        goal,
        starts,
        bundle["connectivity"],
        bundle["allowDiagonalCornerCutting"],
    )
    baseline_steps = [float(item[2]) for item in baseline]
    require(all(item[0] for item in baseline), "not all baseline starts are reachable")
    require(all(item[2] >= 4 for item in baseline), "a baseline path has fewer than four steps")
    threshold = math.ceil(grid_edge / 4.0)
    require(sum(item[2] >= threshold for item in baseline) / len(baseline) >= 0.9, "baseline long-path fraction is below 0.90")
    require(median(baseline_steps) >= math.ceil(grid_edge / 2.0), "baseline median path length is too short")

    first_group_cells = [
        (cell["x"], cell["y"])
        for partition in bundle["eventGroups"][0]["atomicPartitions"]
        for cell in partition["changes"]
    ]
    blocked_walkable = baseline_walkable.copy()
    blocked_costs = baseline_costs.copy()
    increased_walkable = baseline_walkable.copy()
    increased_costs = baseline_costs.copy()
    apply_group(bundle, bundle["eventGroups"][0], blocked_walkable, blocked_costs)
    apply_group(bundle, bundle["eventGroups"][2], increased_walkable, increased_costs)

    blocked = evaluate_oracle(blocked_walkable, blocked_costs, grid_edge, goal, starts, bundle["connectivity"], bundle["allowDiagonalCornerCutting"])
    increased = evaluate_oracle(increased_walkable, increased_costs, grid_edge, goal, starts, bundle["connectivity"], bundle["allowDiagonalCornerCutting"])
    state_values = {
        "baseline": (baseline_walkable, baseline_costs, baseline),
        "blocked": (blocked_walkable, blocked_costs, blocked),
        "increased": (increased_walkable, increased_costs, increased),
    }
    state_hashes = {
        name: grid_state_sha(values[0], values[1], grid_edge)
        for name, values in state_values.items()
    }
    require(len(set(state_hashes.values())) == 3, "baseline/block/increase grid states are not distinct")

    current_walkable = baseline_walkable.copy()
    current_costs = baseline_costs.copy()
    current_label = "baseline"
    event_summaries: list[dict[str, Any]] = []
    affected_fractions: list[float] = []
    minimum_affected = max(1, math.ceil(bundle["agentCount"] * 0.05))
    start_set = set(starts)

    for group_index, group in enumerate(bundle["eventGroups"]):
        require(group["eventGroupIndex"] == group_index, "event-group index mismatch")
        require(group["cycleIndex"] == group_index // 4, "event-group cycle mismatch")
        require(group["phase"] == PHASES[group_index % 4], "event-group phase mismatch")
        require(group["topology"] == bundle["changeTopology"], "event-group topology mismatch")
        require(len(group["atomicPartitions"]) == bundle["sameTickAtomicPartitions"], "atomic partition count mismatch")

        before_label = current_label
        before_oracle = state_values[before_label][2]
        before_sha = state_hashes[before_label]
        changed = apply_group(bundle, group, current_walkable, current_costs)
        require(len(changed) == bundle["changedCellCount"] and len(set(changed)) == bundle["changedCellCount"], "event-group changed-cell cardinality mismatch")
        require(not (set(changed) & start_set) and goal not in set(changed), "event group changes a start or goal")
        require(set(changed) == set(first_group_cells), "event groups do not preserve the same F-cell dynamic boundary")

        phase = group["phase"]
        after_label = "blocked" if phase == "block" else "increased" if phase == "increase_cost" else "baseline"
        expected_walkable, expected_costs, after_oracle = state_values[after_label]
        require(current_walkable == expected_walkable and current_costs == expected_costs, f"event group {group_index} did not reach its exact expected state")
        after_sha = state_hashes[after_label]

        affected_count = 0
        for before_value, after_value in zip(before_oracle, after_oracle):
            changed_status = before_value[0] != after_value[0]
            changed_cost = before_value[0] and after_value[0] and not nearly_equal(before_value[1], after_value[1])
            if changed_status or changed_cost:
                affected_count += 1
        fraction = affected_count / bundle["agentCount"]
        affected_fractions.append(fraction)
        require(affected_count >= minimum_affected, f"event group {group_index} affects too few agents")
        bottleneck_applicable = bundle["changeTopology"] == "bottleneck" and phase in {"block", "increase_cost"}
        require(not bottleneck_applicable or fraction >= 0.5, f"bottleneck group {group_index} affects fewer than half the agents")
        restore_applicable = phase in {"unblock_or_restore", "decrease_or_restore_cost"}
        require(not restore_applicable or after_sha == state_hashes["baseline"], f"restore group {group_index} does not restore exact grid state")
        require(not restore_applicable or after_oracle == baseline, f"restore group {group_index} does not restore oracle state")

        event_summaries.append(
            {
                "eventGroupIndex": group_index,
                "phase": phase,
                "beforeState": before_label,
                "afterState": after_label,
                "beforeGridSha256": before_sha,
                "afterGridSha256": after_sha,
                "uniqueChangedCellCount": len(set(changed)),
                "affectedAgentCount": affected_count,
                "affectedAgentFraction": fraction,
                "minimumAffectedAgentsPassed": True,
                "bottleneckHalfAgentsRuleApplicable": bottleneck_applicable,
                "bottleneckHalfAgentsPassed": True,
                "restoreGridBytesPassed": True,
                "restoreOraclePassed": True,
            }
        )
        current_label = after_label

    median_affected = median(affected_fractions)
    require(median_affected >= 0.10, "median affected-agent fraction is below 0.10")
    require(current_walkable == baseline_walkable and current_costs == baseline_costs, "input does not end at exact baseline state")

    return {
        "schema": "gate14re-me-offline-geometry-oracle-validation-row-v1",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "status": "PASS_ALGORITHM_NEUTRAL_GEOMETRY",
        "inputId": bundle["inputId"],
        "superblockId": bundle["superblockId"],
        "inputRelativePath": input_relative_path,
        "inputSha256": input_sha,
        "oracleId": "gate14re-me-goal-rooted-dijkstra-v1-offline-port",
        "oracleSourceRelativePath": ORACLE_SOURCE_REL.as_posix(),
        "oracleSourceSha256": oracle_source_sha,
        "baselineReachableAgents": len(baseline),
        "baselineMinimumPathSteps": min(item[2] for item in baseline),
        "baselineMedianPathSteps": median(baseline_steps),
        "baselineLongPathThreshold": threshold,
        "baselineLongPathFraction": sum(item[2] >= threshold for item in baseline) / len(baseline),
        "minimumAffectedAgentCount": minimum_affected,
        "medianAffectedAgentFraction": median_affected,
        "eventGroupCount": len(event_summaries),
        "stateSha256": state_hashes,
        "eventGroups": event_summaries,
        "allGeometryChecksPassed": True,
    }


def make_identity_binding(attempt_root: Path, created_at: str) -> tuple[dict[str, Any], str]:
    shuffled_lanes = LANES.copy()
    secrets.SystemRandom().shuffle(shuffled_lanes)
    nonce = secrets.token_hex(32)
    mapping = [
        {"algorithmId": algorithm, "anonymousLaneId": lane}
        for algorithm, lane in zip(ALGORITHMS, shuffled_lanes)
    ]
    binding = {
        "schema": "gate14re-me-sealed-anonymous-identity-binding-v4",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "authorizationId": AUTHORIZATION_ID,
        "status": "SEALED_UNTIL_QUALIFICATION_DECISION_FROZEN",
        "createdAtUtc": created_at,
        "identityBindingId": "gate14re-me-qualification-anonymous-six-lane-v4",
        "generationMethod": "operating-system CSPRNG Fisher-Yates permutation",
        "generationNonceHex": nonce,
        "namedAlgorithms": ALGORITHMS,
        "anonymousLaneIds": LANES,
        "bijection": mapping,
        "qualificationReportsMayExposeNamedIdentity": False,
        "unsealCondition": "qualification decision terminal receipt is frozen and a separate identity-unsealing authorization is granted",
    }
    path = attempt_root / "planning-assets/identity/anonymous-identity-binding.sealed.v4.json"
    write_json(path, binding)
    return binding, sha256_file(path)


def authorization_receipt(created_at: str) -> dict[str, Any]:
    return {
        "schema": "gate14re-me-qualification-planning-asset-generation-v4-attempt-002-authorization-receipt-v4",
        "studyId": STUDY_ID,
        "authorizationId": AUTHORIZATION_ID,
        "authorizedAtUtc": created_at,
        "status": "AUTHORIZED_LIMITED_OFFLINE_PLANNING_ASSET_GENERATION",
        "userAuthorization": "用户要求保留现有六算法配对结构，将 G 改为 64/96/128、N 改为 32/64/128、F 保持四组并改为 1/9/25/81，降低全部最大负载；将 attempt-009 其余可用简化全部应用到新版本，已有资源只能复制并按新版本重新命名；新建的精简只读验收经可行性验证后复用。此阶段仅生成 v4 planning assets，不启动 qualification。",
        "authorizedOutputs": {
            "sealedAnonymousIdentityBindings": 1,
            "coreInputBundles": 108,
            "stressInputBundles": 18,
            "scheduleRows": 126,
            "offlineGeometryOracleValidation": True,
            "freezeManifest": True,
            "terminalReceipt": True,
        },
        "prohibited": [
            "measured-root creation", "Unity launch", "planner construction or invocation",
            "algorithm-lane execution", "qualification observations", "formal observations",
            "formal collection", "formal analysis", "ranking", "winner adjudication",
        ],
    }


def stage_contract(project_root: Path, attempt_root: Path, created_at: str) -> dict[str, Any]:
    generator_rel = project_relative(project_root, attempt_root / "generate_and_validate_planning_assets_v4_1.py")
    schema_driver_rel = project_relative(project_root, attempt_root / "validate_json_schemas_v4_1.ps1")
    return {
        "schema": "gate14re-me-qualification-planning-asset-generation-v4-attempt-002-stage-contract-v4",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "authorizationId": AUTHORIZATION_ID,
        "createdAtUtc": created_at,
        "mode": "OFFLINE_NONEXECUTING_PLANNING_ASSET_GENERATION",
        "attemptRootRelativePath": ATTEMPT_REL.as_posix(),
        "uniqueContracts": {
            "qualificationDesign": {"relativePath": DESIGN_REL.as_posix(), "sha256": EXPECTED_HASHES[DESIGN_REL.as_posix()]},
            "qualificationDesignTerminal": {"relativePath": DESIGN_TERMINAL_REL.as_posix(), "sha256": EXPECTED_HASHES[DESIGN_TERMINAL_REL.as_posix()]},
            "streamingAcceptanceFeasibility": {"relativePath": ACCEPTANCE_FEASIBILITY_TERMINAL_REL.as_posix(), "sha256": EXPECTED_HASHES[ACCEPTANCE_FEASIBILITY_TERMINAL_REL.as_posix()]},
            "inputSchema": {"relativePath": INPUT_SCHEMA_REL.as_posix(), "sha256": EXPECTED_HASHES[INPUT_SCHEMA_REL.as_posix()]},
            "scheduleSchema": {"relativePath": SCHEDULE_SCHEMA_REL.as_posix(), "sha256": EXPECTED_HASHES[SCHEDULE_SCHEMA_REL.as_posix()]},
            "outputSchema": {"relativePath": OUTPUT_SCHEMA_REL.as_posix(), "sha256": EXPECTED_HASHES[OUTPUT_SCHEMA_REL.as_posix()]},
            "sixAlgorithmFairnessBinding": {"relativePath": FAIRNESS_REL.as_posix(), "sha256": EXPECTED_HASHES[FAIRNESS_REL.as_posix()]},
            "referenceOracleSource": {"relativePath": ORACLE_SOURCE_REL.as_posix(), "sha256": EXPECTED_HASHES[ORACLE_SOURCE_REL.as_posix()]},
        },
        "tooling": {
            "generator": {"relativePath": generator_rel, "sha256": sha256_file(attempt_root / "generate_and_validate_planning_assets_v4_1.py")},
            "jsonSchemaDriver": {"relativePath": schema_driver_rel, "sha256": sha256_file(attempt_root / "validate_json_schemas_v4_1.ps1")},
        },
        "requiredOutputs": {
            "sealedIdentityBindingCount": 1,
            "coreInputBundleCount": 108,
            "stressInputBundleCount": 18,
            "totalInputBundleCount": 126,
            "scheduleRowCount": 126,
            "williamsSequenceCount": 6,
            "repetitionsPerWilliamsSequence": 21,
            "candidateBGridRule": "positive multiples of 36",
            "provisionalMinimumB": 36,
            "finalB": None,
            "finalBStatus": "PENDING_POWER_REFREEZE",
        },
        "executionBoundary": {
            "measuredRootCreated": False,
            "unityInvocationsMaximum": 0,
            "plannerInvocationsMaximum": 0,
            "algorithmLaneExecutionsMaximum": 0,
            "qualificationObservationsMaximum": 0,
            "formalObservationsMaximum": 0,
            "formalCollectionAuthorized": False,
            "formalAnalysisAuthorized": False,
            "rankingAuthorized": False,
            "winnerAdjudicationAuthorized": False,
        },
        "failureDisposition": "preserve all evidence and partial assets; do not adopt them; fail closed",
    }


def generate(project_root: Path, attempt_root: Path) -> None:
    require(attempt_root.resolve() == (project_root / ATTEMPT_REL).resolve(), "attempt root is not the authorized canonical path")
    require(attempt_root.is_dir(), "attempt root does not exist")
    allowed_initial = {"generate_and_validate_planning_assets_v4_1.py", "validate_json_schemas_v4_1.ps1", "__pycache__"}
    existing = {item.name for item in attempt_root.iterdir()}
    require(existing.issubset(allowed_initial), f"attempt root is not fresh: unexpected entries {sorted(existing - allowed_initial)}")

    created_at = utc_now()
    write_json(attempt_root / "authorization-receipt.v4.json", authorization_receipt(created_at))
    write_json(attempt_root / "stage-contract.v4.json", stage_contract(project_root, attempt_root, created_at))
    preflight = verify_upstream(project_root)
    write_json(
        attempt_root / "preflight-hash-and-boundary-receipt.v4.json",
        {
            "schema": "gate14re-me-qualification-planning-asset-generation-v4-preflight-v4",
            "studyId": STUDY_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "PASS_FROZEN_HASHES_AND_STAGE_BOUNDARY",
            "checkedAtUtc": utc_now(),
            **preflight,
        },
    )

    binding, binding_sha = make_identity_binding(attempt_root, created_at)
    lane_to_algorithm = {item["anonymousLaneId"]: item["algorithmId"] for item in binding["bijection"]}
    require(set(lane_to_algorithm) == set(LANES) and set(lane_to_algorithm.values()) == set(ALGORITHMS), "identity map is not a six-by-six bijection")

    rows = build_design_rows()
    oracle_source_sha = EXPECTED_HASHES[ORACLE_SOURCE_REL.as_posix()]
    oracle_rows: list[dict[str, Any]] = []
    schedule_rows: list[dict[str, Any]] = []
    input_hashes: list[str] = []

    for row in rows:
        bundle, baseline_walkable, baseline_costs, _ = build_input_bundle(row)
        region = row["designRegion"]
        filename = f"{row['superblockId']}.input.v4.json"
        input_path = attempt_root / "planning-assets/inputs" / region / filename
        write_json(input_path, bundle)
        input_sha = sha256_file(input_path)
        input_hashes.append(input_sha)
        input_rel = project_relative(project_root, input_path)
        oracle_rows.append(
            validate_bundle_geometry(
                bundle,
                baseline_walkable,
                baseline_costs,
                input_rel,
                input_sha,
                oracle_source_sha,
            )
        )

        sequence_index = row["williamsSequenceIndex"]
        lane_order = WILLIAMS_LANE_SEQUENCES[sequence_index]
        schedule_rows.append(
            {
                "schema": "gate14re-me-load-qualification-schedule-row-v4",
                "ordinal": row["ordinal"],
                "superblockId": row["superblockId"],
                "inputRelativePath": input_rel,
                "inputSha256": input_sha,
                "algorithmOrder": [
                    {
                        "algorithmId": lane_to_algorithm[lane],
                        "anonymousLaneId": lane,
                        "identityBindingSha256": binding_sha,
                    }
                    for lane in lane_order
                ],
                "replacement": None,
            }
        )

    schedule_path = attempt_root / "planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
    write_jsonl(schedule_path, schedule_rows)
    oracle_path = attempt_root / "validation/offline-geometry-oracle-validation.v4.jsonl"
    write_jsonl(oracle_path, oracle_rows)

    aggregate_inputs_sha = hashlib.sha256("\n".join(input_hashes).encode("ascii")).hexdigest()
    write_json(
        attempt_root / "asset-generation-receipt.v4.json",
        {
            "schema": "gate14re-me-qualification-planning-asset-generation-v4-receipt-v4",
            "studyId": STUDY_ID,
            "protocolId": PROTOCOL_ID,
            "designId": DESIGN_ID,
            "authorizationId": AUTHORIZATION_ID,
            "status": "GENERATED_PENDING_JSON_SCHEMA_AND_FINAL_FREEZE_VALIDATION",
            "generatedAtUtc": utc_now(),
            "identityBindingRelativePath": project_relative(project_root, attempt_root / "planning-assets/identity/anonymous-identity-binding.sealed.v4.json"),
            "identityBindingSha256": binding_sha,
            "coreInputBundles": 108,
            "stressInputBundles": 18,
            "totalInputBundles": 126,
            "scheduleRows": 126,
            "scheduleRelativePath": project_relative(project_root, schedule_path),
            "scheduleSha256": sha256_file(schedule_path),
            "offlineGeometryValidationRows": len(oracle_rows),
            "offlineGeometryValidationRelativePath": project_relative(project_root, oracle_path),
            "offlineGeometryValidationSha256": sha256_file(oracle_path),
            "orderedInputSha256Aggregate": aggregate_inputs_sha,
            "unityInvocations": 0,
            "plannerInvocations": 0,
            "algorithmLaneExecutions": 0,
            "qualificationObservations": 0,
            "formalObservations": 0,
        },
    )
    print(json.dumps({"status": "GENERATED", "inputs": 126, "scheduleRows": 126, "identityBindingSha256": binding_sha}, separators=(",", ":")))


def validate_and_freeze(project_root: Path, attempt_root: Path) -> None:
    require(attempt_root.resolve() == (project_root / ATTEMPT_REL).resolve(), "attempt root is not the authorized canonical path")
    require(not (attempt_root / "terminal-receipt.v4.json").exists(), "terminal receipt already exists; stage is single-use")
    preflight = verify_upstream(project_root)
    schema_receipt_path = attempt_root / "validation/json-schema-validation-receipt.v4.json"
    require(schema_receipt_path.is_file(), "JSON Schema validation receipt is missing")
    schema_receipt = load_json(schema_receipt_path)
    require(schema_receipt.get("status") == "PASS_JSON_SCHEMA_VALIDATION", "JSON Schema validation did not pass")
    require(schema_receipt.get("inputBundleCount") == 126 and schema_receipt.get("scheduleRowCount") == 126, "JSON Schema validation cardinality mismatch")

    binding_path = attempt_root / "planning-assets/identity/anonymous-identity-binding.sealed.v4.json"
    binding = load_json(binding_path)
    binding_sha = sha256_file(binding_path)
    require(binding.get("status") == "SEALED_UNTIL_QUALIFICATION_DECISION_FROZEN", "identity binding is not sealed")
    require(binding.get("namedAlgorithms") == ALGORITHMS and binding.get("anonymousLaneIds") == LANES, "identity binding cohort mismatch")
    bijection = binding.get("bijection", [])
    require(len(bijection) == 6, "identity binding cardinality mismatch")
    algorithm_to_lane = {item["algorithmId"]: item["anonymousLaneId"] for item in bijection}
    lane_to_algorithm = {item["anonymousLaneId"]: item["algorithmId"] for item in bijection}
    require(set(algorithm_to_lane) == set(ALGORITHMS) and set(algorithm_to_lane.values()) == set(LANES), "identity binding is not bijective")
    require(len(lane_to_algorithm) == 6, "identity binding lane duplication")

    input_paths = sorted((attempt_root / "planning-assets/inputs").rglob("*.input.v4.json"))
    require(len(input_paths) == 126, f"expected 126 input bundles, found {len(input_paths)}")
    core_paths = [path for path in input_paths if path.parent.name == "core"]
    stress_paths = [path for path in input_paths if path.parent.name == "stress"]
    require(len(core_paths) == 108 and len(stress_paths) == 18, "core/stress input cardinality mismatch")

    inputs_by_superblock: dict[str, tuple[Path, dict[str, Any], str]] = {}
    input_ids: set[str] = set()
    seeds: set[int] = set()
    core_structural = Counter()
    core_context = Counter()
    stress_context = Counter()
    for path in input_paths:
        bundle = load_json(path)
        sha = sha256_file(path)
        superblock_id = bundle["superblockId"]
        require(superblock_id not in inputs_by_superblock, f"duplicate superblock id: {superblock_id}")
        require(bundle["inputId"] not in input_ids, f"duplicate input id: {bundle['inputId']}")
        require(bundle["seed"] not in seeds, f"duplicate pilot seed: {bundle['seed']}")
        require(bundle["seed"] < 0, "qualification seed is outside the frozen negative pilot namespace")
        inputs_by_superblock[superblock_id] = (path, bundle, sha)
        input_ids.add(bundle["inputId"])
        seeds.add(bundle["seed"])
        context_key = (bundle["changeTopology"], bundle["graphProfile"], bundle["sameTickAtomicPartitions"])
        if bundle["designRegion"] == "core":
            core_structural[(bundle["gridEdge"], bundle["agentCount"], bundle["changedCellCount"])] += 1
            core_context[context_key] += 1
        else:
            stress_context[context_key] += 1

    require(len(core_structural) == 36 and set(core_structural.values()) == {3}, "core structural-cell replication is not exactly three")
    require(len(core_context) == 18 and set(core_context.values()) == {6}, "core context strata are not exactly balanced at six")
    require(len(stress_context) == 18 and set(stress_context.values()) == {1}, "stress context strata are not exactly one each")

    oracle_path = attempt_root / "validation/offline-geometry-oracle-validation.v4.jsonl"
    oracle_records = [json.loads(line) for line in oracle_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    require(len(oracle_records) == 126, "offline geometry/oracle validation row count mismatch")
    oracle_by_input: dict[str, dict[str, Any]] = {}
    for record in oracle_records:
        require(record.get("status") == "PASS_ALGORITHM_NEUTRAL_GEOMETRY" and record.get("allGeometryChecksPassed") is True, "an offline geometry/oracle row is not PASS")
        require(record["inputId"] not in oracle_by_input, "duplicate offline geometry/oracle input id")
        source_path = project_root / Path(record["inputRelativePath"])
        require(source_path.is_file() and sha256_file(source_path) == record["inputSha256"], "offline geometry/oracle source binding mismatch")
        oracle_by_input[record["inputId"]] = record
    require(set(oracle_by_input) == input_ids, "offline geometry/oracle coverage is not one-to-one with inputs")

    schedule_path = attempt_root / "planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
    schedule_rows = [json.loads(line) for line in schedule_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    require(len(schedule_rows) == 126, "schedule row count mismatch")
    scheduled_paths: set[str] = set()
    scheduled_superblocks: set[str] = set()
    scheduled_input_ids: set[str] = set()
    sequence_counts = Counter()
    position_counts = {lane: [0] * 6 for lane in LANES}
    predecessor_counts = Counter()
    binding_hashes: set[str] = set()

    for ordinal, schedule_row in enumerate(schedule_rows):
        require(schedule_row["ordinal"] == ordinal and schedule_row["schema"] == "gate14re-me-load-qualification-schedule-row-v4", "schedule schema/ordinal mismatch")
        superblock_id = schedule_row["superblockId"]
        require(superblock_id in inputs_by_superblock and superblock_id not in scheduled_superblocks, "schedule superblock missing or duplicated")
        scheduled_superblocks.add(superblock_id)
        path, bundle, actual_sha = inputs_by_superblock[superblock_id]
        expected_rel = project_relative(project_root, path)
        require(schedule_row["inputRelativePath"] == expected_rel and expected_rel not in scheduled_paths, "schedule input path mismatch or duplication")
        require(schedule_row["inputSha256"] == actual_sha, "schedule input SHA-256 mismatch")
        require(schedule_row["replacement"] is None, "this authorization did not generate replacement inputs")
        scheduled_paths.add(expected_rel)
        require(bundle["inputId"] not in scheduled_input_ids, "scheduled input id duplication")
        scheduled_input_ids.add(bundle["inputId"])

        order = schedule_row["algorithmOrder"]
        require(len(order) == 6, "schedule lane cardinality mismatch")
        lanes = [item["anonymousLaneId"] for item in order]
        algorithms = [item["algorithmId"] for item in order]
        require(set(lanes) == set(LANES) and set(algorithms) == set(ALGORITHMS), "schedule row is not a six-lane/six-algorithm permutation")
        for item in order:
            require(lane_to_algorithm[item["anonymousLaneId"]] == item["algorithmId"], "schedule reveals an identity pair inconsistent with the sealed binding")
            binding_hashes.add(item["identityBindingSha256"])
        require(all(item["identityBindingSha256"] == binding_sha for item in order), "schedule identity binding SHA-256 mismatch")
        try:
            sequence_index = WILLIAMS_LANE_SEQUENCES.index(lanes)
        except ValueError as exc:
            raise StageFailure(f"schedule row {ordinal} is not a frozen Williams sequence") from exc
        sequence_counts[sequence_index] += 1
        for position, lane in enumerate(lanes):
            position_counts[lane][position] += 1
        for position in range(1, len(lanes)):
            predecessor_counts[(lanes[position - 1], lanes[position])] += 1

    require(scheduled_superblocks == set(inputs_by_superblock), "schedule superblock coverage is incomplete")
    require(scheduled_input_ids == input_ids, "schedule input-id coverage is incomplete")
    require(binding_hashes == {binding_sha}, "schedule does not bind exactly one identity SHA-256")
    require(sequence_counts == Counter({index: 21 for index in range(6)}), f"Williams sequence repetitions differ from 21: {sequence_counts}")
    require(all(counts == [21] * 6 for counts in position_counts.values()), f"Williams lane-position balance failed: {position_counts}")
    require(len(predecessor_counts) == 30 and set(predecessor_counts.values()) == {21}, "Williams first-order carryover balance failed")

    generation_receipt = load_json(attempt_root / "asset-generation-receipt.v4.json")
    require(generation_receipt.get("coreInputBundles") == 108 and generation_receipt.get("stressInputBundles") == 18, "generation receipt cardinality mismatch")
    require(generation_receipt.get("identityBindingSha256") == binding_sha, "generation receipt identity hash mismatch")
    require(generation_receipt.get("scheduleSha256") == sha256_file(schedule_path), "generation receipt schedule hash mismatch")

    final_validation = {
        "schema": "gate14re-me-qualification-planning-asset-generation-v4-final-validation-v4",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "authorizationId": AUTHORIZATION_ID,
        "status": "PASS_PLANNING_ASSET_STRUCTURAL_AND_ORACLE_VALIDATION",
        "validatedAtUtc": utc_now(),
        "checks": {
            "explicitFrozenBindingsChecked": preflight["explicitHashBindingsChecked"],
            "streamingEssentialAcceptanceFeasibilityPass": preflight["streamingEssentialAcceptanceFeasibilityPass"],
            "inputSchemaV4RowsPassed": 126,
            "scheduleSchemaRowsPassed": 126,
            "offlineGeometryOracleRowsPassed": 126,
            "sealedBijectionCount": 1,
            "uniqueInputIds": len(input_ids),
            "uniquePilotSeeds": len(seeds),
            "uniqueInputPaths": len(scheduled_paths),
            "uniqueSuperblockIds": len(scheduled_superblocks),
            "coreStructuralCells": len(core_structural),
            "coreReplicatesPerStructuralCell": sorted(set(core_structural.values())),
            "coreContextStrata": len(core_context),
            "coreOccurrencesPerContextStratum": sorted(set(core_context.values())),
            "stressContextStrata": len(stress_context),
            "stressOccurrencesPerContextStratum": sorted(set(stress_context.values())),
            "williamsSequences": len(sequence_counts),
            "repetitionsPerWilliamsSequence": sorted(set(sequence_counts.values())),
            "laneOccurrencesPerExecutionPosition": 21,
            "orderedCarryoverOccurrencesPerPair": 21,
            "replacementInputsGenerated": 0,
        },
        "scopeAudit": {
            "measuredRootCreated": False,
            "unityInvocations": 0,
            "plannerInvocations": 0,
            "algorithmLaneExecutions": 0,
            "qualificationObservations": 0,
            "formalObservations": 0,
            "formalCollectionPerformed": False,
            "formalAnalysisPerformed": False,
            "algorithmRankingPerformed": False,
            "winnerAdjudicationPerformed": False,
        },
    }
    final_validation_path = attempt_root / "final-validation-receipt.v4.json"
    write_json(final_validation_path, final_validation)

    manifest_candidates: list[tuple[str, Path]] = [
        ("authorization-receipt", attempt_root / "authorization-receipt.v4.json"),
        ("stage-contract", attempt_root / "stage-contract.v4.json"),
        ("generator-source", attempt_root / "generate_and_validate_planning_assets_v4_1.py"),
        ("json-schema-driver-source", attempt_root / "validate_json_schemas_v4_1.ps1"),
        ("preflight-receipt", attempt_root / "preflight-hash-and-boundary-receipt.v4.json"),
        ("sealed-identity-binding", binding_path),
        ("williams-schedule", schedule_path),
        ("offline-geometry-oracle-validation", oracle_path),
        ("json-schema-validation-receipt", schema_receipt_path),
        ("asset-generation-receipt", attempt_root / "asset-generation-receipt.v4.json"),
        ("final-validation-receipt", final_validation_path),
    ]
    manifest_candidates.extend(("qualification-input-bundle", path) for path in input_paths)
    manifest_artifacts = [
        {
            "role": role,
            "relativePath": project_relative(project_root, path),
            "lengthBytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for role, path in manifest_candidates
    ]
    relative_paths = [item["relativePath"] for item in manifest_artifacts]
    require(len(relative_paths) == len(set(relative_paths)), "freeze manifest contains duplicate paths")
    manifest = {
        "schema": "gate14re-me-qualification-planning-asset-generation-v4-freeze-manifest-v4",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "authorizationId": AUTHORIZATION_ID,
        "status": "FROZEN_PLANNING_ASSETS_PASS",
        "createdAtUtc": utc_now(),
        "artifactCount": len(manifest_artifacts),
        "artifacts": manifest_artifacts,
        "allPathsUnique": True,
        "allHashesAndLengthsMatchedAtFreeze": True,
        "identityBindingRemainsSealed": True,
        "partialPlanningAssetsMayBeAdopted": False,
    }
    manifest_path = attempt_root / "planning-assets-freeze-manifest.v4.json"
    write_json(manifest_path, manifest)

    terminal = {
        "schema": "gate14re-me-qualification-planning-asset-generation-v4-attempt-002-terminal-receipt-v4",
        "studyId": STUDY_ID,
        "protocolId": PROTOCOL_ID,
        "designId": DESIGN_ID,
        "authorizationId": AUTHORIZATION_ID,
        "status": "PASS_QUALIFICATION_PLANNING_ASSETS_FROZEN_V4_NO_EXECUTION_STARTED",
        "state": [
            "SEALED_ANONYMOUS_IDENTITY_BINDING_FROZEN",
            "INPUT_SCHEMA_V4_BOUNDED_GNF_BUNDLES_FROZEN",
            "ALGORITHM_NEUTRAL_GEOMETRY_ORACLE_PASS",
            "WILLIAMS_BALANCED_SCHEDULE_FROZEN",
            "MEASURED_ROOT_NOT_CREATED",
            "QUALIFICATION_EXECUTION_NOT_AUTHORIZED",
        ],
        "completedAtUtc": utc_now(),
        "passed": True,
        "terminal": True,
        "frozenOutputs": {
            "identityBinding": {"relativePath": project_relative(project_root, binding_path), "sha256": binding_sha},
            "schedule": {"relativePath": project_relative(project_root, schedule_path), "sha256": sha256_file(schedule_path)},
            "offlineGeometryOracleValidation": {"relativePath": project_relative(project_root, oracle_path), "sha256": sha256_file(oracle_path)},
            "jsonSchemaValidationReceipt": {"relativePath": project_relative(project_root, schema_receipt_path), "sha256": sha256_file(schema_receipt_path)},
            "finalValidationReceipt": {"relativePath": project_relative(project_root, final_validation_path), "sha256": sha256_file(final_validation_path)},
            "freezeManifest": {"relativePath": project_relative(project_root, manifest_path), "sha256": sha256_file(manifest_path)},
        },
        "cardinality": {
            "sealedAnonymousIdentityBindings": 1,
            "coreInputBundles": 108,
            "stressInputBundles": 18,
            "totalInputBundles": 126,
            "scheduleRows": 126,
            "freshAlgorithmProcessesProspectiveOnly": 756,
            "qualificationTotalFreshProcessesProspectiveOnly": 895,
            "qualificationObservationsGenerated": 0,
        },
        "formalSampleSize": {
            "unit": "independent superblocks per GxNxF cell",
            "candidateGridRule": "positive multiples of 36",
            "provisionalMinimumB": 36,
            "finalB": None,
            "status": "PENDING_NEW_QUALIFICATION_AND_ANONYMOUS_POWER_REFREEZE",
            "attempt009ObservationsMayBecomeFormalSamples": False,
        },
        "scopeAudit": final_validation["scopeAudit"],
        "nextAuthorizationRequired": "A separate authorization is required before creating a qualification measured root or running the qualification preflight/execution. This PASS does not authorize Unity, any planner, any algorithm lane, qualification observations, formal collection, formal analysis, ranking, or winner adjudication.",
    }
    terminal_path = attempt_root / "terminal-receipt.v4.json"
    write_json(terminal_path, terminal)

    # Freeze every artifact in this independent attempt after the terminal
    # receipt exists.  No file is deleted or overwritten after this point.
    for path in sorted(attempt_root.rglob("*")):
        if path.is_file():
            os.chmod(path, stat.S_IREAD)
    print(json.dumps({"status": terminal["status"], "manifestSha256": sha256_file(manifest_path), "terminalSha256": sha256_file(terminal_path)}, separators=(",", ":")))


def write_failure_receipt(attempt_root: Path, mode: str, exc: BaseException) -> None:
    try:
        path = attempt_root / "failure-receipt.v4.json"
        if path.exists():
            return
        write_json(
            path,
            {
                "schema": "gate14re-me-qualification-planning-asset-generation-v4-failure-receipt-v4",
                "studyId": STUDY_ID,
                "authorizationId": AUTHORIZATION_ID,
                "status": "FAIL_CLOSED_PLANNING_ASSET_GENERATION",
                "failedAtUtc": utc_now(),
                "mode": mode,
                "errorType": type(exc).__name__,
                "exactReason": str(exc),
                "traceback": traceback.format_exc(),
                "partialAssetsMayBeAdopted": False,
                "automaticRetryPerformed": False,
                "measuredRootCreated": False,
                "unityInvocations": 0,
                "plannerInvocations": 0,
                "algorithmLaneExecutions": 0,
                "qualificationObservations": 0,
                "formalObservations": 0,
            },
        )
    except Exception:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["generate", "finalize"])
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--attempt-root", required=True)
    args = parser.parse_args()
    project_root = Path(args.project_root).resolve()
    attempt_root = Path(args.attempt_root).resolve()
    try:
        if args.mode == "generate":
            generate(project_root, attempt_root)
        else:
            validate_and_freeze(project_root, attempt_root)
        return 0
    except Exception as exc:
        write_failure_receipt(attempt_root, args.mode, exc)
        print(f"FAIL_CLOSED: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
