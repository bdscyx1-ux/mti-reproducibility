#!/usr/bin/env python3
"""Outcome-free cross-file and synthetic validator for Gate14Re-TB design v1."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import math
import os
import statistics
from pathlib import Path


CORE = {
    "science": "Research/Gate14Re-TB/Gate14Re_TB_NonExecuting_Scientific_Contract.v1.json",
    "input": "Research/Gate14Re-TB/Gate14Re_TB_Input_Generation_Law.v1.json",
    "replay": "Research/Gate14Re-TB/Gate14Re_TB_Replay_Contract.v1.json",
    "winner": "Research/Gate14Re-TB/Gate14Re_TB_Winner_Adjudication_Tree.v1.json",
    "sample": "Research/Gate14Re-TB/Gate14Re_TB_Blinded_Sample_Size_Reestimation_Protocol.v1.json",
    "archive": "Research/Verification/Gate14Re-TB/nonexecuting-design-freeze-attempt-001/gate14re-archive-binding.v1.json",
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def check(condition: bool, name: str, tests: list[dict[str, str]]) -> None:
    if not condition:
        raise AssertionError(name)
    tests.append({"test": name, "status": "PASS"})


def is_read_only(path: Path) -> bool:
    attrs = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attrs & 0x1)


def hmac_rank(seed: bytes, *parts: str) -> bytes:
    message = b"\x00".join(part.encode("utf-8") for part in parts)
    return hmac.new(seed, message, hashlib.sha256).digest()


def bundle_digest(bundle_without_hash: dict) -> str:
    return hashlib.sha256(canonical_bytes(bundle_without_hash)).hexdigest()


def nuisance_summary(values: dict[str, dict[str, list[float]]]) -> float:
    labels = sorted(next(iter(values.values())).keys())
    conditions = sorted(values)
    pair_v = []
    for i, first in enumerate(labels):
        for second in labels[i + 1 :]:
            s2 = []
            for condition in conditions:
                diffs = [
                    a - b
                    for a, b in zip(values[condition][first], values[condition][second], strict=True)
                ]
                s2.append(statistics.variance(diffs))
            pair_v.append(sum(s2) / (len(conditions) ** 2))
    return max(pair_v)


def selected_b(v_m1: float, v_m2: float, r_m2: float) -> tuple[int, int, int]:
    normal = statistics.NormalDist()
    z_crit = normal.inv_cdf(1.0 - 0.05 / (2.0 * 6.0))
    z_power = normal.inv_cdf(0.90)
    req_m1 = math.ceil(((z_crit + z_power) ** 2 * v_m1) / (abs(math.log(0.98)) ** 2))
    req_m2_raw = math.ceil(((z_crit + z_power) ** 2 * v_m2) / (abs(math.log(0.99)) ** 2))
    req_m2 = math.ceil(req_m2_raw / r_m2)
    required = max(req_m1, req_m2, 32)
    grid = [32, 48, 64, 80, 96]
    choice = next((item for item in grid if item >= required), -1)
    return req_m1, req_m2, choice


def validate(root: Path) -> dict:
    tests: list[dict[str, str]] = []
    docs = {}
    hashes = {}
    for key, relative in CORE.items():
        path = root / relative
        check(path.is_file(), f"{key}_file_exists", tests)
        with path.open("r", encoding="utf-8") as handle:
            docs[key] = json.load(handle)
        hashes[relative] = sha256_file(path)
        check(docs[key]["studyId"] == "Gate14Re-TB", f"{key}_study_id", tests)

    expected_algorithms = ["A*-R", "D*L", "C-FF", "IDFF"]
    algorithms = [row["algorithmId"] for row in docs["science"]["algorithms"]]
    check(algorithms == expected_algorithms, "four_algorithms_exact_order_including_dstar_lite", tests)
    check(all(row["included"] for row in docs["science"]["algorithms"]), "all_four_algorithms_included", tests)
    check(docs["winner"]["candidates"] == expected_algorithms, "winner_tree_candidate_binding", tests)
    check(docs["science"]["inputSemantics"]["oneCommonGoalPerSuperblock"], "one_common_goal", tests)
    check(docs["science"]["inputSemantics"]["sameReplayBundleForAllAlgorithms"], "same_input_all_algorithms", tests)
    check(docs["science"]["experimentalUnit"]["name"] == "input superblock", "independent_unit_superblock", tests)
    check(docs["science"]["design"]["quantityUnitCounts"] == [1, 8, 32, 128, 512], "quantity_grid_exact", tests)
    check(docs["sample"]["sampleSizeGrid"]["initialB0PerCell"] == 24, "B0_exact", tests)
    check(docs["sample"]["sampleSizeGrid"]["allowedFinalBPerCell"] == [32, 48, 64, 80, 96], "B_grid_exact", tests)
    check(docs["sample"]["errorAndPower"]["targetPower"] == 0.90, "power_exact", tests)
    check(docs["winner"]["family"]["familywiseAlpha"] == 0.05, "alpha_exact", tests)
    check(len(docs["winner"]["family"]["unorderedPairs"]) == 6, "six_pair_family", tests)
    check(docs["science"]["winnerCommitment"]["oldGate14ReResultCannotEnterAdjudication"], "old_result_excluded", tests)
    check(not docs["science"]["authorization"]["formalCollectionAuthorized"], "collection_not_authorized", tests)
    check(not docs["sample"]["realNuisanceValuesAccessedWhilePreparingThisProtocol"], "no_real_nuisance_access", tests)

    conditions = docs["input"]["sourceConditions"]
    check([item["conditionId"] for item in conditions] == [f"C{i:02d}" for i in range(1, 9)], "eight_source_conditions", tests)
    check(all(len(item["scenarioSha256"]) == 64 for item in conditions), "source_sha_shape", tests)
    for variant in docs["input"]["eventScheduleVariants"]["variants"]:
        check(len(variant["ticks"]) == 5, f"{variant['variantId']}_five_events", tests)
        check(all(0 <= tick < 9000 for tick in variant["ticks"]), f"{variant['variantId']}_inside_cap", tests)
        check(variant["ticks"] == sorted(variant["ticks"]), f"{variant['variantId']}_monotone", tests)

    archive = docs["archive"]
    for binding_name, binding in archive["bindings"].items():
        path = root / binding["path"]
        check(path.is_file(), f"archive_{binding_name}_exists", tests)
        check(sha256_file(path) == binding["sha256"], f"archive_{binding_name}_hash", tests)
        check(is_read_only(path), f"archive_{binding_name}_readonly", tests)

    check(not (root / "Research/FormalRuns/Gate14Re-TB").exists(), "no_tb_formal_root", tests)
    check(not (root / "Research/Analysis/Gate14Re-TB").exists(), "no_tb_analysis_root", tests)

    seed = bytes.fromhex("00" * 31 + "01")
    support = [(x, z) for x in range(40) for z in range(40)]
    ranked1 = sorted(support, key=lambda cell: hmac_rank(seed, "C01", "7", "spawn", str(cell[0]), str(cell[1])))
    ranked2 = sorted(support, key=lambda cell: hmac_rank(seed, "C01", "7", "spawn", str(cell[0]), str(cell[1])))
    check(ranked1 == ranked2 and len(set(ranked1[:512])) == 512, "synthetic_deterministic_unique_spawn_draw", tests)
    check(ranked1[:1] == ranked1[:8][:1] == ranked1[:32][:1] == ranked1[:128][:1] == ranked1[:512][:1], "synthetic_nested_prefix", tests)

    bundle = {
        "schema": "gate14re-tb-input-bundle-v1",
        "studyId": "Gate14Re-TB",
        "conditionId": "C01",
        "drawIndex": 7,
        "goalGridCoordinate": [99, 99],
        "spawnGridCoordinates512": [list(item) for item in ranked1[:512]],
        "eventScheduleVariantId": "E01",
        "fixedStepSeconds": 0.02,
        "movementCapSeconds": 180,
    }
    digest = bundle_digest(bundle)
    check(digest == bundle_digest(bundle), "synthetic_bundle_digest_replay", tests)
    tampered = json.loads(json.dumps(bundle))
    tampered["goalGridCoordinate"] = [99, 98]
    check(bundle_digest(tampered) != digest, "synthetic_bundle_tamper_negative", tests)

    values = {}
    labels = ["K1", "K2", "K3", "K4"]
    for c in range(8):
        condition = f"C{c + 1:02d}"
        values[condition] = {}
        for label_index, label in enumerate(labels):
            values[condition][label] = [
                4.0 + 0.001 * c + 0.0005 * label_index + 0.0015 * math.sin((i + 1) * (label_index + 1) + c)
                for i in range(24)
            ]
    v_original = nuisance_summary(values)
    permutation = {"K1": "K3", "K2": "K1", "K3": "K4", "K4": "K2"}
    permuted = {
        condition: {permutation[label]: series[:] for label, series in by_label.items()}
        for condition, by_label in values.items()
    }
    sign_flipped = {
        condition: {label: [-value for value in series] for label, series in by_label.items()}
        for condition, by_label in values.items()
    }
    check(math.isclose(v_original, nuisance_summary(permuted), rel_tol=0.0, abs_tol=1e-18), "synthetic_label_permutation_invariance", tests)
    check(math.isclose(v_original, nuisance_summary(sign_flipped), rel_tol=0.0, abs_tol=1e-18), "synthetic_sign_flip_invariance", tests)
    req_m1, req_m2, choice = selected_b(v_original, v_original / 4.0, 1.0)
    check(choice in [32, 48, 64, 80, 96], "synthetic_B_rounding_to_grid", tests)
    check(req_m1 >= 0 and req_m2 >= 0, "synthetic_required_B_nonnegative", tests)

    check(docs["replay"]["replayLayers"]["visualTraceReplay"]["plannerInvoked"] is False, "replay_no_planner", tests)
    check(docs["replay"]["replayLayers"]["visualTraceReplay"]["M1ThroughM5ComputationByReplayTool"] is False, "replay_no_outcome_analysis", tests)
    check(docs["winner"]["tier4PreRegisteredEngineeringTiebreak"]["claim"].startswith("ENGINEERING_TIEBREAK"), "engineering_claim_separated", tests)
    check(docs["winner"]["terminalStates"]["zeroMainEligible"]["status"] == "NO_DEPLOYABLE_WINNER", "no_false_winner_when_zero_eligible", tests)

    return {
        "schema": "gate14re-tb-design-validation-output-v1",
        "studyId": "Gate14Re-TB",
        "result": "PASS",
        "testCount": len(tests),
        "tests": tests,
        "artifactSha256": hashes,
        "syntheticOnly": True,
        "actualScenarioSupportOpened": False,
        "actualInputDrawCreated": False,
        "realNuisanceOrOutcomeAccessed": False,
        "formalCollectionAuthorized": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        result = validate(args.root.resolve())
    except Exception as exc:  # fail-closed validator entry point
        print(json.dumps({"result": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
