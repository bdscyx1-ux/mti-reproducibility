#!/usr/bin/env python3
"""Outcome-free cross-file and synthetic validator for Gate14Re-ME design v1."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path


CORE = {
    "authorization": "Research/Gate14Re-ME/Gate14Re_ME_Scientific_Freeze_Authorization.v1.json",
    "science": "Research/Gate14Re-ME/Gate14Re_ME_NonExecuting_Scientific_Contract.v1.json",
    "endpoints": "Research/Gate14Re-ME/Gate14Re_ME_Endpoint_Dictionary.v1.json",
    "delivery": "Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json",
    "parameters": "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v1.json",
    "status": "Research/Gate14Re-ME/Gate14Re_ME_Status.v1.json",
}

PLAN = "Research/Gate14Re-ME/Gate14Re_ME_Experiment_Plan.v1.md"

ALGORITHMS = ["A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"]
COMPARATORS = ["A*-R", "BiA*-R", "D*L", "LPA*", "C-FF"]
DOMAINS = [
    "D1_DYNAMIC_LATENCY",
    "D2_GRID_READ_WORK",
    "D3_DYNAMIC_ALLOCATION",
    "D4_PERSISTENT_STATE_BYTES",
    "D5_AGENT_COUNT_SCALING",
    "D6_CHANGE_FOOTPRINT_SCALING",
    "D7_GRID_SIZE_SCALING",
]

EXPECTED_EXPORTS = {
    "gate14re-me-sample-wide.csv",
    "gate14re-me-metric-long.csv.zst",
    "gate14re-me-metric-long.parquet",
    "gate14re-me-eventgroup-long.csv.zst",
    "gate14re-me-eventgroup-long.parquet",
    "gate14re-me-operations.v1.jsonl.zst",
    "gate14re-me-persistent-state-long.csv.zst",
    "gate14re-me-failures-replacements.csv",
    "data-dictionary.v1.json",
    "source-provenance.v1.json",
    "export-manifest.v1.jsonl",
    "export-canonical-tree.v1.jsonl",
    "delivery-receipt.v1.json",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def check(condition: bool, name: str, tests: list[dict[str, str]]) -> None:
    if not condition:
        raise AssertionError(name)
    tests.append({"test": name, "status": "PASS"})


def validate_williams(sequences: list[list[str]], tests: list[dict[str, str]]) -> None:
    check(len(sequences) == 6, "williams_six_sequences", tests)
    check(all(len(row) == 6 for row in sequences), "williams_six_positions", tests)
    check(all(set(row) == set(ALGORITHMS) for row in sequences), "williams_each_row_is_permutation", tests)
    for position in range(6):
        check(
            {row[position] for row in sequences} == set(ALGORITHMS),
            f"williams_position_{position + 1}_balanced",
            tests,
        )
    directed_pairs = [
        (row[index], row[index + 1])
        for row in sequences
        for index in range(len(row) - 1)
    ]
    expected_pairs = {
        (first, second)
        for first in ALGORITHMS
        for second in ALGORITHMS
        if first != second
    }
    check(len(directed_pairs) == 30, "williams_thirty_adjacencies", tests)
    check(set(directed_pairs) == expected_pairs, "williams_all_directed_predecessor_pairs_once", tests)


def synthetic_delivery_checks(tests: list[dict[str, str]]) -> dict[str, int]:
    rows: list[dict[str, object]] = []
    for superblock_index in range(2):
        for position, algorithm in enumerate(ALGORITHMS, start=1):
            for event_group in range(1, 25):
                record_id = f"SB{superblock_index + 1:03d}:{position}:{event_group:02d}:latency"
                rows.append(
                    {
                        "studyId": "Gate14Re-ME",
                        "phaseId": "SYNTHETIC",
                        "attemptId": "validation-only",
                        "designId": "synthetic-known-answer",
                        "structuralCellId": "G64-N8-F1",
                        "superblockId": f"SB{superblock_index + 1:03d}",
                        "inputBundleId": f"IB{superblock_index + 1:03d}",
                        "laneId": f"L{position}",
                        "algorithmId": algorithm,
                        "executionOrderSequenceId": "W1",
                        "executionPosition": position,
                        "processId": 1000 + 10 * superblock_index + position,
                        "recordId": record_id,
                        "eventGroupId": event_group,
                        "metricId": "eventGroupElapsedMilliseconds",
                        "value": float(1000 * superblock_index + 100 * position + event_group) / 10.0,
                        "unit": "ms",
                        "valuePresent": True,
                        "missingReasonCode": None,
                        "eligibilityStatus": "ELIGIBLE",
                        "sourcePath": f"_superblocks/SB{superblock_index + 1:03d}/lanes/{position}/event-groups.v1.jsonl",
                        "sourceSha256": hashlib.sha256(record_id.encode("utf-8")).hexdigest(),
                    }
                )

    expected_count = 2 * 6 * 24
    check(len(rows) == expected_count, "synthetic_event_group_cardinality", tests)
    check(len({row["recordId"] for row in rows}) == expected_count, "synthetic_record_ids_unique", tests)
    check({row["algorithmId"] for row in rows} == set(ALGORITHMS), "synthetic_all_named_algorithms", tests)
    by_lane: dict[tuple[str, str], int] = {}
    for row in rows:
        key = (str(row["superblockId"]), str(row["algorithmId"]))
        by_lane[key] = by_lane.get(key, 0) + 1
    check(set(by_lane.values()) == {24}, "synthetic_twenty_four_event_groups_per_lane", tests)

    ordered = sorted(rows, key=lambda row: str(row["recordId"]))
    canonical_hash = hashlib.sha256(canonical_bytes(ordered)).hexdigest()
    check(canonical_hash == hashlib.sha256(canonical_bytes(ordered)).hexdigest(), "synthetic_canonical_hash_reproducible", tests)

    fieldnames = sorted(ordered[0])
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(ordered)
    buffer.seek(0)
    round_trip = list(csv.DictReader(buffer))
    check(len(round_trip) == expected_count, "synthetic_csv_round_trip_record_count", tests)
    check(
        [row["recordId"] for row in round_trip] == [str(row["recordId"]) for row in ordered],
        "synthetic_csv_round_trip_identity_order",
        tests,
    )

    tampered = json.loads(json.dumps(ordered))
    tampered[0]["value"] = float(tampered[0]["value"]) + 1.0
    check(
        hashlib.sha256(canonical_bytes(tampered)).hexdigest() != canonical_hash,
        "synthetic_tamper_negative",
        tests,
    )
    missing = ordered[:-1]
    check(len(missing) != expected_count, "synthetic_missing_row_negative", tests)
    duplicated = ordered + [ordered[-1]]
    check(
        len({row["recordId"] for row in duplicated}) != len(duplicated),
        "synthetic_duplicate_record_negative",
        tests,
    )
    swapped = json.loads(json.dumps(ordered))
    swapped[0]["algorithmId"], swapped[24]["algorithmId"] = (
        swapped[24]["algorithmId"],
        swapped[0]["algorithmId"],
    )
    check(
        hashlib.sha256(canonical_bytes(swapped)).hexdigest() != canonical_hash,
        "synthetic_algorithm_label_swap_negative",
        tests,
    )
    check(
        all(row["sourcePath"] and len(str(row["sourceSha256"])) == 64 for row in ordered),
        "synthetic_source_path_hash_traceability",
        tests,
    )
    return {
        "syntheticSuperblocks": 2,
        "syntheticLanes": 12,
        "syntheticEventGroupRows": expected_count,
    }


def validate(root: Path) -> dict[str, object]:
    tests: list[dict[str, str]] = []
    docs: dict[str, dict] = {}
    hashes: dict[str, str] = {}

    for key, relative in CORE.items():
        path = root / relative
        check(path.is_file(), f"{key}_file_exists", tests)
        with path.open("r", encoding="utf-8") as handle:
            docs[key] = json.load(handle)
        check(docs[key]["studyId"] == "Gate14Re-ME", f"{key}_study_id", tests)
        hashes[relative] = sha256_file(path)

    plan_path = root / PLAN
    check(plan_path.is_file(), "plan_file_exists", tests)
    plan_text = plan_path.read_text(encoding="utf-8")
    hashes[PLAN] = sha256_file(plan_path)
    check("完整逐条原始数据硬冻结条件" in plan_text, "plan_contains_raw_delivery_hard_gate", tests)
    check("Formal collection authorization: `NONE`" in plan_text, "plan_collection_not_authorized", tests)

    check(docs["authorization"]["authorizationId"] == "gate14re-me-nonexecuting-scientific-freeze-attempt-001", "authorization_id", tests)
    check(docs["authorization"]["authorizedDecisions"]["completePerObservationRawDataDeliverabilityIsHardCondition"], "authorization_raw_delivery_hard_condition", tests)
    check(docs["authorization"]["authorizedDecisions"]["retainAllSixNamedAlgorithms"] == ALGORITHMS, "authorization_six_algorithms", tests)

    check(docs["science"]["algorithms"] == ALGORITHMS, "science_six_algorithms_exact", tests)
    check(docs["endpoints"]["algorithmCohort"] == ALGORITHMS, "endpoint_six_algorithms_exact", tests)
    check(docs["endpoints"]["idffComparators"] == COMPARATORS, "endpoint_five_comparators_exact", tests)
    check(docs["status"]["designSummary"]["algorithms"] == ALGORITHMS, "status_six_algorithms_exact", tests)

    design = docs["science"]["design"]
    check(design["gridEdgeLevels"] == [64, 128, 256], "grid_levels_exact", tests)
    check(design["agentCountLevels"] == [8, 32, 128, 512], "agent_levels_exact", tests)
    check(design["changedCellLevels"] == [1, 9, 81, 225], "footprint_levels_exact", tests)
    check(3 * 4 * 4 == design["primaryStructuralCells"] == 48, "forty_eight_structural_cells", tests)
    check(design["withinCellContextFactors"]["jointContextStrata"] == 18, "eighteen_context_strata", tests)
    check(design["eventGroupsPerLane"] == 24, "twenty_four_event_groups", tests)
    check(design["eventCyclesPerLane"] == 6, "six_event_cycles", tests)
    check(design["BPerStructuralCell"] is None, "final_B_not_invented", tests)
    validate_williams(design["sixTreatmentWilliamsExecutionOrders"], tests)

    check(docs["science"]["primaryEndpointDomains"] == DOMAINS, "seven_domains_exact", tests)
    check([row["domainId"] for row in docs["endpoints"]["primaryDomains"]] == DOMAINS, "endpoint_dictionary_seven_domains_exact", tests)
    majority = docs["science"]["majoritySupportRule"]
    check(majority["minimumIDFFAdvantageDomains"] == 4, "majority_four", tests)
    check(majority["totalDomains"] == 7, "majority_denominator_seven", tests)
    check(majority["advantageDomainRequiresFavorableAdjustedEvidenceAgainst"] == COMPARATORS, "majority_requires_all_five_comparators", tests)
    check(not majority["failedOrInvalidDomainRemovedFromDenominator"], "invalid_domain_not_removed", tests)
    check(docs["science"]["statisticalModel"]["confirmatoryContrastCount"] == 35, "thirty_five_confirmatory_contrasts", tests)
    check("Holm" in docs["science"]["statisticalModel"]["multiplicity"], "holm_strong_fwer", tests)

    integrity = docs["science"]["integrityBoundary"]
    check(not integrity["positiveIDFFResultGuaranteed"], "no_guaranteed_positive_result", tests)
    check(not integrity["ranking"], "ranking_forbidden", tests)
    check(not integrity["winnerAdjudication"], "winner_forbidden", tests)
    check(not integrity["weightedComposite"], "weighted_composite_forbidden", tests)

    hard = docs["delivery"]["hardCondition"]
    check(hard["completePerObservationRawDataDeliverable"], "delivery_complete_per_observation", tests)
    check(hard["mandatoryForPrecollectionReadiness"], "delivery_required_for_readiness", tests)
    check(hard["mandatoryForFormalRawCommit"], "delivery_required_for_raw_commit", tests)
    check(hard["mandatoryBeforeAnyFormalAnalysisAuthorizationCanBeExercised"], "delivery_required_before_analysis", tests)
    check(not docs["delivery"]["storageArchitecture"]["formalMeasuredRootExistsAtThisFreeze"], "delivery_no_measured_root_at_freeze", tests)
    check(docs["delivery"]["rawFieldRetention"]["aggregationOnlyStorageForbidden"], "aggregation_only_forbidden", tests)
    check(docs["delivery"]["rawFieldRetention"]["summariesMayNotSubstituteForConstituentRows"], "constituent_rows_required", tests)
    check(docs["delivery"]["expectedStructuralCardinality"]["eventGroupsPerAcceptedLane"] == 24, "delivery_event_group_cardinality", tests)
    check(docs["delivery"]["expectedStructuralCardinality"]["persistentStateMeasurementPointsPerAcceptedLane"] == 26, "delivery_state_point_cardinality", tests)
    exports = {row["path"] for row in docs["delivery"]["requiredDerivedDeliveryPackage"]["files"]}
    check(exports == EXPECTED_EXPORTS, "delivery_export_package_exact", tests)
    check(all(row["required"] for row in docs["delivery"]["requiredDerivedDeliveryPackage"]["files"]), "delivery_all_exports_required", tests)
    check(docs["delivery"]["completenessAndReproducibilityChecks"]["allRawRecordsTraceToMeasuredSourcePathAndSha256"], "raw_source_traceability_required", tests)
    check(docs["delivery"]["completenessAndReproducibilityChecks"]["allExportRecordsTraceToRawRecordId"], "export_raw_record_traceability_required", tests)
    check(docs["delivery"]["freezeBeforeCollectionRequirements"]["syntheticKnownAnswerDeliveryTestRequired"], "synthetic_delivery_test_required", tests)
    check(docs["delivery"]["formalRawCommitGate"]["requiredReceiptStatus"] == "PASS_COMPLETE_PER_OBSERVATION_RAW_DATA_DELIVERABLE", "raw_commit_receipt_status_exact", tests)
    check(set(docs["delivery"]["formalRawCommitGate"]["requiredStateFlags"]) == {"RAW_IMMUTABLE", "COMPLETE_PER_OBSERVATION_DELIVERABLE", "ANALYSIS_PENDING"}, "raw_commit_state_flags_exact", tests)

    parameters = docs["parameters"]
    check(parameters["currentlyUnresolved"]["minimumPracticallyImportantEffectsByDomain"] is None, "mipe_not_invented", tests)
    check(parameters["currentlyUnresolved"]["finalBPerStructuralCell"] is None, "parameter_final_B_not_invented", tests)
    check(parameters["fixedConstraints"]["BMustBePositiveMultipleOf"] == 36, "B_multiple_of_thirty_six", tests)
    check(parameters["fixedConstraints"]["targetPowerAtLeast"] == 0.9, "target_power_point_nine", tests)
    check(parameters["timing"]["mustCompleteBeforeAnyFormalObservation"], "parameter_amendment_before_observation", tests)
    check(not parameters["authorizationBoundary"]["parameterValuesAuthorized"], "parameter_values_not_authorized", tests)

    boundary = docs["science"]["authorizationBoundary"]
    for key in (
        "implementationAuthorized",
        "inputGenerationAuthorized",
        "compileOrUnityExecutionAuthorized",
        "formalMeasuredRootCreationAuthorized",
        "formalCollectionAuthorized",
        "formalExportExecutionAuthorized",
        "formalAnalysisAuthorized",
        "rankingAuthorized",
        "winnerAdjudicationAuthorized",
    ):
        check(not boundary[key], f"authorization_boundary_{key}_false", tests)

    check(not (root / "Research/FormalRuns/Gate14Re-ME").exists(), "no_gate14re_me_formal_root", tests)
    check(not (root / "Research/Analysis/Gate14Re-ME").exists(), "no_gate14re_me_analysis_root", tests)
    check(not (root / "Research/Exports/Gate14Re-ME").exists(), "no_gate14re_me_export_root", tests)

    synthetic = synthetic_delivery_checks(tests)

    return {
        "schema": "gate14re-me-design-validation-output-v1",
        "studyId": "Gate14Re-ME",
        "result": "PASS",
        "testCount": len(tests),
        "tests": tests,
        "artifactSha256": hashes,
        "syntheticSummary": synthetic,
        "syntheticOnly": True,
        "priorGate14ReObservationsRead": False,
        "excludedGate14ReTB2ObservationsRead": False,
        "Gate14ReMEFormalObservationCount": 0,
        "UnityProcessCount": 0,
        "formalCollectionAuthorized": False,
        "formalAnalysisAuthorized": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        result = validate(args.root.resolve())
    except Exception as exc:
        print(
            json.dumps(
                {
                    "result": "FAIL",
                    "errorType": type(exc).__name__,
                    "message": str(exc),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
