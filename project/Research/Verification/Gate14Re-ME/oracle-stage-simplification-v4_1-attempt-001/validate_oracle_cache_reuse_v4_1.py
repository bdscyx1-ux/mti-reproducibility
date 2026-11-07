#!/usr/bin/env python3
"""Read-only structural feasibility check for Gate14Re-ME v4.1 oracle-cache reuse.

The checker reads only algorithm-neutral oracle tables, their receipts, source input
bundles, and the sealed file manifest. It never opens an algorithm-lane observation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import tracemalloc
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, Tuple


class CheckError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise CheckError(f"JSON object required: {path}")
    return value


def read_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise CheckError(f"JSON object required: {path}:{line_number}")
            yield line_number, value


def load_seal_manifest(path: Path) -> Dict[str, Dict[str, Any]]:
    entries: Dict[str, Dict[str, Any]] = {}
    for line_number, row in read_jsonl(path):
        if row.get("schema") != "gate14re-me-paused-seal-file-row-v1" or row.get("root") != "measured":
            raise CheckError(f"unexpected seal row identity: {path}:{line_number}")
        relative = row.get("relativePath")
        if not isinstance(relative, str) or relative in entries:
            raise CheckError(f"invalid or duplicate seal path: {path}:{line_number}")
        entries[relative] = row
    return entries


def require_sealed_file(raw_root: Path, entries: Dict[str, Dict[str, Any]], path: Path) -> None:
    relative = path.resolve(strict=True).relative_to(raw_root.resolve(strict=True)).as_posix()
    row = entries.get(relative)
    if row is None:
        raise CheckError(f"file is absent from the sealed measured manifest: {relative}")
    if path.stat().st_size != row.get("bytes") or sha256_file(path) != row.get("sha256"):
        raise CheckError(f"sealed byte/hash mismatch: {relative}")


def validate_one(
    project_root: Path,
    raw_root: Path,
    entries: Dict[str, Dict[str, Any]],
    oracle_dir: Path,
) -> Tuple[int, int]:
    receipt_path = oracle_dir / "oracle-pass-receipt.v1.json"
    agent_path = oracle_dir / "oracle-agent-checks.raw.v1.jsonl"
    event_path = oracle_dir / "oracle-event-checks.raw.v1.jsonl"
    for path in (receipt_path, agent_path, event_path):
        require_sealed_file(raw_root, entries, path)

    receipt = read_json(receipt_path)
    if (
        receipt.get("status") != "PASS_ALGORITHM_NEUTRAL_GEOMETRY"
        or receipt.get("allGeometryChecksPassed") is not True
        or receipt.get("superblockId") != oracle_dir.name
    ):
        raise CheckError(f"oracle receipt is not a complete algorithm-neutral PASS: {receipt_path}")
    source_relative = receipt.get("inputRelativePath")
    source_sha = receipt.get("inputSha256")
    if not isinstance(source_relative, str) or not isinstance(source_sha, str):
        raise CheckError(f"oracle receipt source binding is malformed: {receipt_path}")
    source = (project_root / Path(source_relative)).resolve(strict=True)
    source.relative_to(project_root.resolve(strict=True))
    if sha256_file(source) != source_sha:
        raise CheckError(f"input source hash mismatch: {source_relative}")
    bundle = read_json(source)
    agent_count = bundle.get("agentCount")
    event_groups = bundle.get("eventGroups")
    if (
        not isinstance(agent_count, int)
        or agent_count <= 0
        or not isinstance(event_groups, list)
        or len(event_groups) != 24
        or bundle.get("superblockId") != oracle_dir.name
    ):
        raise CheckError(f"input bundle identity/cardinality mismatch: {source}")

    expected_agent_rows = agent_count * 49
    record_ids: set[str] = set()
    cache_keys: set[Tuple[int, str, int]] = set()
    agent_rows = 0
    for line_number, row in read_jsonl(agent_path):
        record_id = row.get("recordId")
        if not isinstance(record_id, str) or not record_id or record_id in record_ids:
            raise CheckError(f"duplicate/invalid oracle agent recordId: {agent_path}:{line_number}")
        record_ids.add(record_id)
        if (
            row.get("inputId") != bundle.get("inputId")
            or row.get("superblockId") != oracle_dir.name
            or row.get("sourceRelativePath") != source_relative
            or row.get("sourceSha256") != source_sha
        ):
            raise CheckError(f"oracle agent source identity mismatch: {agent_path}:{line_number}")
        group = row.get("eventGroupIndex")
        side = row.get("comparisonSide")
        agent = row.get("agentIndex")
        if not isinstance(agent, int) or agent < 0 or agent >= agent_count:
            raise CheckError(f"oracle agent index out of range: {agent_path}:{line_number}")
        allowed = (group == -1 and side == "baseline") or (
            isinstance(group, int) and 0 <= group < 24 and side in {"before", "after"}
        )
        key = (group, str(side), agent)
        if not allowed or key in cache_keys:
            raise CheckError(f"oracle cache key invalid or duplicated: {agent_path}:{line_number}")
        cache_keys.add(key)
        reachable = row.get("reachable")
        cost = row.get("shortestPathCost")
        steps = row.get("shortestPathSteps")
        if not isinstance(reachable, bool) or not isinstance(cost, (int, float)) or not isinstance(steps, int):
            raise CheckError(f"oracle reachability tuple has invalid scalar types: {agent_path}:{line_number}")
        if (reachable and (cost < 0 or steps < 0)) or (not reachable and (cost != -1 or steps != -1)):
            raise CheckError(f"oracle reachability tuple is inconsistent: {agent_path}:{line_number}")
        agent_rows += 1
    if agent_rows != expected_agent_rows or len(cache_keys) != expected_agent_rows:
        raise CheckError(f"oracle agent cache cardinality mismatch: {agent_path}: {agent_rows} != {expected_agent_rows}")
    for agent in range(agent_count):
        if (-1, "baseline", agent) not in cache_keys:
            raise CheckError(f"baseline cache row missing: {oracle_dir.name}: agent={agent}")
        for group in range(24):
            if (group, "before", agent) not in cache_keys or (group, "after", agent) not in cache_keys:
                raise CheckError(f"before/after cache row missing: {oracle_dir.name}: group={group}: agent={agent}")

    event_ids: set[str] = set()
    event_indices: set[int] = set()
    event_rows = 0
    for line_number, row in read_jsonl(event_path):
        record_id = row.get("recordId")
        group = row.get("eventGroupIndex")
        if (
            not isinstance(record_id, str)
            or record_id in event_ids
            or not isinstance(group, int)
            or group < 0
            or group >= 24
            or group in event_indices
            or row.get("inputId") != bundle.get("inputId")
            or row.get("superblockId") != oracle_dir.name
            or row.get("sourceRelativePath") != source_relative
            or row.get("sourceSha256") != source_sha
            or row.get("minimumAffectedAgentsPassed") is not True
            or row.get("bottleneckHalfAgentsPassed") is not True
            or row.get("restoreGridBytesPassed") is not True
            or row.get("restoreOraclePassed") is not True
        ):
            raise CheckError(f"oracle event cache row mismatch: {event_path}:{line_number}")
        event_ids.add(record_id)
        event_indices.add(group)
        event_rows += 1
    if event_rows != 24 or event_indices != set(range(24)):
        raise CheckError(f"oracle event cache cardinality mismatch: {event_path}")
    return agent_rows, event_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--raw-root", required=True)
    parser.add_argument("--seal-manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--expected-inputs", type=int, required=True)
    args = parser.parse_args()

    started = time.perf_counter()
    started_utc = utc_now()
    tracemalloc.start()
    project_root = Path(args.project_root).resolve(strict=True)
    raw_root = Path(args.raw_root).resolve(strict=True)
    seal_manifest = Path(args.seal_manifest).resolve(strict=True)
    output = Path(args.output).resolve(strict=False)
    if output.exists():
        raise CheckError(f"refusing to overwrite feasibility receipt: {output}")
    entries = load_seal_manifest(seal_manifest)
    oracle_dirs = sorted(path for path in (raw_root / "oracle").iterdir() if path.is_dir())
    if len(oracle_dirs) != args.expected_inputs:
        raise CheckError(f"oracle input count mismatch: {len(oracle_dirs)} != {args.expected_inputs}")

    total_agent_rows = 0
    total_event_rows = 0
    for oracle_dir in oracle_dirs:
        agent_rows, event_rows = validate_one(project_root, raw_root, entries, oracle_dir)
        total_agent_rows += agent_rows
        total_event_rows += event_rows
    _, peak_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    receipt = {
        "schema": "gate14re-me-oracle-cache-reuse-structural-feasibility-v4.1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_READ_ONLY_ORACLE_CACHE_SHAPE_AND_BINDING_FEASIBILITY",
        "sourceRawRoot": raw_root.as_posix(),
        "sourceSealManifest": seal_manifest.as_posix(),
        "sourceSealManifestSha256": sha256_file(seal_manifest),
        "oracleInputsValidated": len(oracle_dirs),
        "oracleAgentRowsValidated": total_agent_rows,
        "oracleEventRowsValidated": total_event_rows,
        "baselineBeforeAfterCoverageComplete": True,
        "allSourcePathAndShaBindingsMatch": True,
        "algorithmLaneObservationFilesRead": 0,
        "algorithmEffectsComputed": False,
        "qualificationExecuted": False,
        "sourceRootModified": False,
        "peakPythonTracemallocBytes": peak_bytes,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "startedAtUtc": started_utc,
        "completedAtUtc": utc_now(),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
