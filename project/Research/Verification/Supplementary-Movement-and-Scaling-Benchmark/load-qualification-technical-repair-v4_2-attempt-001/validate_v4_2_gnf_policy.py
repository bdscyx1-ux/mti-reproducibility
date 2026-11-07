from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


EXPECTED_SCHEDULE_SHA256 = "8786f687a142900c0cf609817bbc1da957ec3ee9e09d12549e886fb892f026cb"
EXPECTED_VALIDATOR_SHA256 = "08e2b067e667a11a0cae2f6162721bbd3b59c2e32ce806d247bd10aa63487eb9"
EXPECTED_G = {64, 96, 128}
EXPECTED_N = {32, 64, 128}
EXPECTED_F = {1, 9, 25, 81}
EXPECTED_STRESS = (128, 128, 81)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fail(message: str) -> None:
    raise RuntimeError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    receipt = Path(args.receipt).resolve()
    verification_root = (root / "Research/Verification/Gate14Re-ME").resolve()
    if verification_root not in receipt.parents:
        fail("Receipt escapes the Gate14Re-ME verification root.")
    if receipt.exists():
        fail("Receipt already exists; overwrite is prohibited.")

    schedule_rel = Path(
        "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/"
        "planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
    )
    validator_rel = Path("Assets/_Scripts/Research/Gate14ReME/v4/Gate14ReMEInputGeometryValidatorV4_2.cs")
    schedule_path = root / schedule_rel
    validator_path = root / validator_rel
    if sha256_file(schedule_path) != EXPECTED_SCHEDULE_SHA256:
        fail("Schedule hash mismatch.")
    if sha256_file(validator_path) != EXPECTED_VALIDATOR_SHA256:
        fail("Validator hash mismatch.")

    source = validator_path.read_text(encoding="utf-8")
    required_fragments = (
        "GridLevels = { 64, 96, 128 }",
        "AgentLevels = { 32, 64, 128 }",
        "ChangeLevels = { 1, 9, 25, 81 }",
        "input.gridEdge == 128 && input.agentCount == 128 && input.changedCellCount == 81",
    )
    for fragment in required_fragments:
        if fragment not in source:
            fail(f"Validator source is missing frozen policy fragment: {fragment}")

    lines = [line for line in schedule_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(lines) != 126:
        fail(f"Expected 126 schedule rows, found {len(lines)}.")
    core = Counter()
    stress = Counter()
    input_paths: set[str] = set()
    identity_hashes: set[str] = set()
    for ordinal, line in enumerate(lines):
        row = json.loads(line)
        if row.get("schema") != "gate14re-me-load-qualification-schedule-row-v4" or row.get("ordinal") != ordinal:
            fail(f"Schedule schema/ordinal mismatch at {ordinal}.")
        if row.get("replacement") is not None or len(row.get("algorithmOrder", [])) != 6:
            fail(f"Schedule replacement/lane cardinality mismatch at {ordinal}.")
        relative = row["inputRelativePath"].replace("\\", "/")
        if relative in input_paths:
            fail(f"Duplicate input path: {relative}")
        input_paths.add(relative)
        input_path = root / Path(relative)
        if sha256_file(input_path) != row["inputSha256"]:
            fail(f"Input hash mismatch: {relative}")
        record = json.loads(input_path.read_text(encoding="utf-8"))
        key = (int(record["gridEdge"]), int(record["agentCount"]), int(record["changedCellCount"]))
        if key[0] not in EXPECTED_G or key[1] not in EXPECTED_N or key[2] not in EXPECTED_F:
            fail(f"Input outside frozen G/N/F policy: {relative} => {key}")
        if record["designRegion"] == "core":
            core[key] += 1
        elif record["designRegion"] == "stress":
            if key != EXPECTED_STRESS:
                fail(f"Stress input outside frozen corner: {relative} => {key}")
            stress[key] += 1
        else:
            fail(f"Unknown design region in {relative}")
        for lane in row["algorithmOrder"]:
            identity_hashes.add(lane["identityBindingSha256"])

    if len(core) != 36 or sum(core.values()) != 108 or set(core.values()) != {3}:
        fail("Core cell/replicate cardinality mismatch.")
    if stress != Counter({EXPECTED_STRESS: 18}):
        fail("Stress cardinality mismatch.")
    if identity_hashes != {"77b88a23a559642d455edf0d4caad9a1f9c06b7ddf33703b8fd100f4a1878bd2"}:
        fail("Sealed identity hash mismatch.")

    payload = {
        "schema": "gate14re-me-v4.2-gnf-validator-compatibility-receipt-v1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_ALL_126_FROZEN_INPUTS_MATCH_VERSIONED_V4_2_VALIDATOR_POLICY",
        "scheduleRelativePath": schedule_rel.as_posix(),
        "scheduleSha256": EXPECTED_SCHEDULE_SHA256,
        "validatorRelativePath": validator_rel.as_posix(),
        "validatorSha256": EXPECTED_VALIDATOR_SHA256,
        "gridLevels": sorted(EXPECTED_G),
        "agentLevels": sorted(EXPECTED_N),
        "changedCellLevels": sorted(EXPECTED_F),
        "coreCells": len(core),
        "coreSuperblocks": sum(core.values()),
        "coreReplicatesPerCell": 3,
        "stressCell": {"G": 128, "N": 128, "F": 81},
        "stressSuperblocks": sum(stress.values()),
        "scheduleRows": len(lines),
        "algorithmLanes": len(lines) * 6,
        "observationsRead": False,
        "algorithmEffectsComputed": False,
        "rankingOrWinnerComputed": False,
        "completedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    receipt.parent.mkdir(parents=True, exist_ok=True)
    receipt.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
