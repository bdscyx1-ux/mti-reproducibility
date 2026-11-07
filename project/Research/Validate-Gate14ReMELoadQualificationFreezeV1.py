#!/usr/bin/env python3
"""Outcome-free validator for the Gate14Re-ME load-qualification freeze.

This validator reads only protocol/control artifacts.  It does not inspect prior
observations, create inputs or roots, launch Unity, or compute algorithm effects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


V1_BINDINGS = {
    "Research/Gate14Re-ME/Gate14Re_ME_Experiment_Plan.v1.md":
        "af7527b9c58ff0cd8af59fd9acd4fcdd08b5c4dc8f9241c2eccf7496e01a3f43",
    "Research/Gate14Re-ME/Gate14Re_ME_NonExecuting_Scientific_Contract.v1.json":
        "02b8c5edc1d6c8604dbd1816d99ee4616ac2814d6198e0cee273d031fee60e7f",
    "Research/Gate14Re-ME/Gate14Re_ME_Endpoint_Dictionary.v1.json":
        "9736b16601cc8c89166d65a78ff466114ad6affb57f8be2c9df59a5ddfce22f8",
    "Research/Gate14Re-ME/Gate14Re_ME_Data_Delivery_Contract.v1.json":
        "1e3a70d6be62554027ca639b6a3c7d896fd232906d627962d8c296e9e884c8dd",
    "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v1.json":
        "66eb4bc493236394784d146c6e82c2f4cdd1b4bfaf684a2b202b7f7b939503b9",
    "Research/Gate14Re-ME/Gate14Re_ME_Scientific_Freeze_Authorization.v1.json":
        "ecc04686ac7f243d3a7c603a44c4675bcf81002f3d8af3255160200dc81490b6",
    "Research/Gate14Re-ME/Gate14Re_ME_Status.v1.json":
        "d43cc2fdb5f35b7936efa1741f8db0957a3f9444bf0a4910e9ef748a5c45e908",
    "Research/Validate-Gate14ReMEDesignV1.py":
        "ca394b67b6b452536f5e978806419eff62e4af662677f082b2d34b4ee515513c",
}

NEW_JSON = {
    "authorization": "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Load_Qualification_Freeze_Authorization.v1.json",
    "load": "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Load_Qualification_Protocol.v1.json",
    "science": "Research/Gate14Re-ME/Gate14Re_ME_NonExecuting_Scientific_Contract.v2.json",
    "parameters": "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v2.json",
    "status": "Research/Gate14Re-ME/Gate14Re_ME_Status.v2.json",
}

PLAN_V2 = "Research/Gate14Re-ME/Gate14Re_ME_Experiment_Plan.v2.md"
ALGORITHMS = ["A*-R", "BiA*-R", "D*L", "LPA*", "C-FF", "IDFF"]
ANONYMOUS = ["ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(condition: bool, name: str, tests: list[dict[str, str]]) -> None:
    if not condition:
        raise AssertionError(name)
    tests.append({"test": name, "status": "PASS"})


def is_read_only(path: Path) -> bool:
    attributes = getattr(path.stat(), "st_file_attributes", 0)
    return bool(attributes & 0x1)


def validate(root: Path) -> dict[str, object]:
    tests: list[dict[str, str]] = []
    artifact_hashes: dict[str, str] = {}

    for relative, expected_hash in V1_BINDINGS.items():
        path = root / relative
        check(path.is_file(), f"v1_exists:{relative}", tests)
        actual = sha256_file(path)
        check(actual == expected_hash, f"v1_hash_unchanged:{relative}", tests)
        check(is_read_only(path), f"v1_remains_read_only:{relative}", tests)
        artifact_hashes[relative] = actual

    docs: dict[str, dict] = {}
    for key, relative in NEW_JSON.items():
        path = root / relative
        check(path.is_file(), f"new_artifact_exists:{key}", tests)
        with path.open("r", encoding="utf-8") as handle:
            docs[key] = json.load(handle)
        check(docs[key]["studyId"] == "Gate14Re-ME", f"study_id:{key}", tests)
        artifact_hashes[relative] = sha256_file(path)

    plan_path = root / PLAN_V2
    check(plan_path.is_file(), "plan_v2_exists", tests)
    plan_text = plan_path.read_text(encoding="utf-8")
    artifact_hashes[PLAN_V2] = sha256_file(plan_path)
    check("负载资格门" in plan_text, "plan_names_load_gate", tests)
    check("PASS_LOAD_QUALIFICATION" in plan_text, "plan_pass_status_exact", tests)
    check("FAIL_CLOSED_LOAD_QUALIFICATION" in plan_text, "plan_fail_status_exact", tests)
    check("Qualification execution authorization: `NONE`" in plan_text, "plan_qualification_execution_not_authorized", tests)
    check("Formal collection authorization: `NONE`" in plan_text, "plan_formal_collection_not_authorized", tests)
    check("排名、赢家、加权综合分" in plan_text, "plan_forbids_ranking_winner_composite", tests)

    authorization = docs["authorization"]
    check(
        authorization["authorizationId"] == "gate14re-me-load-qualification-freeze-attempt-001",
        "authorization_id_exact",
        tests,
    )
    check(
        authorization["userAuthorizationText"] == "采用建议，增加的正式采集前‘负载资格门’",
        "authorization_text_exact",
        tests,
    )
    decisions = authorization["authorizedDecisions"]
    check(decisions["addFormalPrecollectionLoadQualificationGate"], "authorization_adds_gate", tests)
    check(decisions["retainExistingSixAlgorithmCohort"] == ALGORITHMS, "authorization_six_algorithms_exact", tests)
    for key, value in authorization["notAuthorized"].items():
        check(value is True, f"authorization_not_authorized:{key}", tests)

    load = docs["load"]
    check(load["status"] == "FROZEN_NONEXECUTING_MANDATORY_BEFORE_FORMAL_COLLECTION", "load_status_exact", tests)
    inherited = load["inheritedScientificFreeze"]
    check(inherited["plan"]["sha256"] == V1_BINDINGS[inherited["plan"]["path"]], "load_binds_v1_plan", tests)
    check(inherited["contract"]["sha256"] == V1_BINDINGS[inherited["contract"]["path"]], "load_binds_v1_contract", tests)
    check(inherited["endpointDictionary"]["sha256"] == V1_BINDINGS[inherited["endpointDictionary"]["path"]], "load_binds_v1_endpoints", tests)
    check(inherited["dataDeliveryContract"]["sha256"] == V1_BINDINGS[inherited["dataDeliveryContract"]["path"]], "load_binds_v1_delivery", tests)

    timing = load["timingAndBlocking"]
    for key in (
        "qualificationMustPassBeforeFormalInputDraw",
        "qualificationMustPassBeforeFormalMeasuredRootCreation",
        "qualificationMustPassBeforeAnyFormalObservation",
        "qualificationMustPassBeforeFinalBMayBeAuthorized",
    ):
        check(timing[key] is True, f"timing_block:{key}", tests)
    check(timing["qualificationInputsMayBeReusedInFormalCollection"] is False, "pilot_inputs_not_reused", tests)
    check(timing["qualificationObservationsMayEnterFormalEffectEstimation"] is False, "pilot_observations_not_formal", tests)
    check(timing["requiredPassReceiptStatus"] == "PASS_LOAD_QUALIFICATION", "load_pass_status_exact", tests)
    check(timing["failureStatus"] == "FAIL_CLOSED_LOAD_QUALIFICATION", "load_fail_status_exact", tests)

    blinding = load["algorithmAndDecisionBlinding"]
    check(blinding["algorithmCount"] == 6, "six_anonymous_lanes", tests)
    check(blinding["sealedAnonymousLaneIds"] == ANONYMOUS, "anonymous_lane_ids_exact", tests)
    check(blinding["perLaneQualificationRequired"], "qualification_required_per_lane", tests)
    for key in (
        "crossAlgorithmMeansOrContrastsAllowed",
        "algorithmDirectionsAllowed",
        "algorithmRanksAllowed",
        "winnerAllowed",
        "IDFFSpecificDecisionAllowed",
        "inferentialPValuesAllowed",
    ):
        check(blinding[key] is False, f"blinding_forbids:{key}", tests)

    unit = load["experimentalUnit"]
    check("pilot input superblock" in unit["independentQualificationUnit"], "independent_unit_superblock", tests)
    for key, value in unit.items():
        if key != "independentQualificationUnit":
            check(value is False, f"not_independent:{key}", tests)

    design = load["qualificationDesign"]
    core = design["coreFactorial"]
    check(core["gridEdgeLevels"] == [64, 128, 256], "qualification_grid_levels", tests)
    check(core["agentCountLevels"] == [8, 32, 128, 512], "qualification_agent_levels", tests)
    check(core["changedCellLevels"] == [1, 9, 81, 225], "qualification_change_levels", tests)
    check(3 * 4 * 4 == core["structuralCells"] == 48, "qualification_48_cells", tests)
    check(core["independentPilotSeedsPerCell"] == 3, "three_pilot_seeds_per_cell", tests)
    check(core["pilotSuperblocks"] == 48 * 3 == 144, "core_144_superblocks", tests)
    check(core["jointContextStrata"] == 18, "qualification_18_context_strata", tests)
    check(core["exactOccurrencesPerContextStratumAcrossCore"] == 144 // 18 == 8, "core_context_balance", tests)
    stress = design["highCornerStress"]
    check(
        (stress["gridEdge"], stress["agentCount"], stress["changedCells"]) == (256, 512, 225),
        "stress_high_corner_exact",
        tests,
    )
    check(stress["pilotSuperblocks"] == stress["jointContextStrata"] == 18, "stress_all_contexts", tests)
    check(design["totalPilotSuperblocks"] == 144 + 18 == 162, "total_162_superblocks", tests)
    check(design["freshAlgorithmProcesses"] == 162 * 6 == 972, "total_972_algorithm_processes", tests)
    check(design["eventGroupsPerLane"] == 24, "qualification_24_event_groups", tests)
    check(design["expectedAlgorithmEventGroupRows"] == 162 * 6 * 24 == 23328, "event_group_cardinality", tests)
    check(design["exactRepetitionsOfEachWilliamsSequence"] == 162 // 6 == 27, "williams_27_cycles", tests)
    check(design["eachAnonymousAlgorithmOccursInEachExecutionPosition"] == 27, "williams_position_balance", tests)

    empty = load["emptyBoundaryReference"]
    check(empty["freshProcesses"] == 12, "empty_boundary_12_processes", tests)
    check(empty["iterationsPerProcess"] == 1000, "empty_boundary_1000_each", tests)
    check(empty["totalIterations"] == 12 * 1000 == 12000, "empty_boundary_12000_total", tests)
    check(empty["plannerCalls"] == 0, "empty_boundary_no_planner", tests)
    check(
        empty["floorReferenceFormula"] == "max(100 * stopwatchTickMilliseconds, emptyBoundaryP99ElapsedMilliseconds)",
        "floor_formula_exact",
        tests,
    )

    geometry = load["algorithmNeutralGeometryQualification"]
    starts = geometry["starts"]
    check(starts["minimumBaselineOraclePathSteps"] == 4, "geometry_min_four_steps", tests)
    check(starts["fractionWithBaselineOraclePathStepsAtLeastCeilGOver4"] == 0.9, "geometry_ninety_percent_g_over_four", tests)
    check(starts["medianBaselineOraclePathStepsAtLeastCeilGOver2"], "geometry_median_g_over_two", tests)
    events = geometry["eventGroups"]
    check(events["countPerInput"] == 24, "geometry_24_groups", tests)
    check(events["uniqueChangedCellsExactlyF"], "geometry_exact_F_unique_cells", tests)
    check(events["changedCellsMayIncludeGoalOrStart"] is False, "geometry_no_goal_start_changes", tests)
    check(events["minimumAffectedAgentsEveryGroupFormula"] == "max(1, ceil(0.05 * N))", "geometry_affected_formula", tests)
    check(events["minimumMedianAffectedAgentFractionAcrossLane"] == 0.1, "geometry_median_affected_ten_percent", tests)
    check(events["minimumAffectedAgentFractionForBottleneckBlockOrIncreaseGroups"] == 0.5, "geometry_bottleneck_half_agents", tests)
    check(events["restoreGroupsMustRestoreGridByteExactlyToPreCycleState"], "geometry_restore_grid_exact", tests)
    check(events["restoreGroupsMustRestoreAllReferenceOracleStatusesAndCosts"], "geometry_restore_oracle_exact", tests)

    floor = load["measurementFloorGate"]["perAnonymousLane"]
    check(floor["upperRegionMedianD1AtLeastFloorMultiple"] == 20, "floor_upper_median_20x", tests)
    check(floor["upperRegionFractionD1AtLeastFloorMultiple"] == {"multiple": 5, "minimumFraction": 0.9}, "floor_upper_90pct_5x", tests)
    check(floor["allCoreFractionD1AtLeastFloorMultiple"] == {"multiple": 5, "minimumFraction": 0.8}, "floor_core_80pct_5x", tests)
    check(floor["minimumDistinctPositiveD1ValuesAcrossCore"] == 10, "floor_ten_distinct_D1", tests)
    check(floor["fractionOfEligibleD2EventGroupsWithPositiveGridReads"] == 0.99, "floor_D2_99pct_positive", tests)

    coverage = load["coverageGate"]
    check(coverage["perAnonymousLaneCoreEligibleEventGroupFractionMinimum"] == 0.95, "coverage_core_95pct", tests)
    check(coverage["perAnonymousLanePerGridLevelEligibleFractionMinimum"] == 0.9, "coverage_grid_levels_90pct", tests)
    check(coverage["perAnonymousLanePerAgentLevelEligibleFractionMinimum"] == 0.9, "coverage_agent_levels_90pct", tests)
    check(coverage["perAnonymousLanePerChangedCellLevelEligibleFractionMinimum"] == 0.9, "coverage_change_levels_90pct", tests)
    check(coverage["failedOrMissingRowsRemainInDenominator"], "coverage_missing_stays_in_denominator", tests)

    dynamic = load["withinLaneDynamicRangeGate"]
    check(dynamic["lowAnchor"] == {"gridEdge": 64, "agentCount": 8, "changedCells": 1}, "dynamic_low_anchor", tests)
    check(dynamic["highAnchor"] == {"gridEdge": 256, "agentCount": 512, "changedCells": 225}, "dynamic_high_anchor", tests)
    check(dynamic["minimumSpanRatio"] == 4.0, "dynamic_minimum_fourfold", tests)
    check(dynamic["monotonicityRequired"] is False, "dynamic_no_monotonicity_claim", tests)
    check(dynamic["crossAlgorithmComparison"] is False, "dynamic_no_cross_algorithm_comparison", tests)
    check(dynamic["advantageDirectionUsed"] is False, "dynamic_no_advantage_direction", tests)

    ceiling = load["resourceCeilingGate"]
    check(len(ceiling["thresholdsFrozenBeforeQualificationExecution"]) == 5, "five_resource_threshold_classes", tests)
    check(ceiling["thresholdSelectionMayUseAlgorithmIdentityOrDirection"] is False, "resource_thresholds_identity_blind", tests)
    check(ceiling["outOfMemoryCount"] == 0, "ceiling_zero_oom", tests)
    check(ceiling["unexpectedProcessCrashCount"] == 0, "ceiling_zero_crash", tests)
    check(ceiling["instrumentationInvalidLaneCount"] == 0, "ceiling_zero_instrument_invalid", tests)
    check(ceiling["perAnonymousLaneCoreBudgetExceededFractionMaximum"] == 0.05, "ceiling_core_budget_five_percent", tests)
    check(ceiling["perAnonymousLaneStressBudgetExceededFractionMaximum"] == 0.1, "ceiling_stress_budget_ten_percent", tests)
    check(ceiling["completedEventGroupP99MaximumFractionOfHardTimeout"] == 0.5, "ceiling_p99_half_timeout", tests)
    check(ceiling["peakCommittedBytesMaximumFractionOfLaneAssignedLimit"] == 0.5, "ceiling_memory_half_limit", tests)
    check(ceiling["projectedFormalRawPlusDeliveryBytesMaximumFractionOfReservedStorage"] == 0.5, "ceiling_storage_half_reserved", tests)
    check(ceiling["minimumTimeoutMemoryAndStorageHeadroomFactor"] == 2.0, "ceiling_twofold_headroom", tests)

    replacement = load["failureAndReplacementPolicy"]
    check(replacement["maximumWholeSuperblockReplacementsPerSource"] == 1, "one_whole_superblock_replacement", tests)
    check(replacement["maximumInfrastructureReplacementFraction"] == 0.02, "replacement_fraction_two_percent", tests)
    check(replacement["originalFailureVoidAndReplacementArtifactsRetained"], "replacement_artifacts_retained", tests)
    check(replacement["resumePerAlgorithmRetryTopUpMergeSkipOrOutcomeDependentReorder"] is False, "no_retry_resume_topup_merge_skip_reorder", tests)

    raw = load["qualificationRawDataHardGate"]
    for key in (
        "separateImmutableQualificationRawAndDerivedRoots",
        "retainEveryEmptyBoundaryIteration",
        "retainEveryInputGeometryAndOracleCheck",
        "retainEveryEventGroupD1D2D3AndEligibilityRecord",
        "retainEveryPersistentStateComponentAndMeasurementPoint",
        "retainEveryProcessResourceSample",
        "retainEveryFailureVoidAndReplacementRecord",
        "retainSourcePathSourceSha256AndRecordIdentity",
        "aggregationOnlyRetentionForbidden",
        "completePerObservationQualificationDeliveryReceiptRequired",
    ):
        check(raw[key] is True, f"qualification_raw_gate:{key}", tests)

    verdict = load["verdict"]
    check(verdict["passRequiresEveryGateForAllSixAnonymousLanes"], "verdict_all_gates_all_lanes", tests)
    check(verdict["passStatus"] == "PASS_LOAD_QUALIFICATION", "verdict_pass_exact", tests)
    check(verdict["failStatus"] == "FAIL_CLOSED_LOAD_QUALIFICATION", "verdict_fail_exact", tests)
    forbidden = " ".join(verdict["forbiddenReportContent"])
    for phrase in ("named algorithm means", "rankings", "winner", "IDFF-specific conclusions"):
        check(phrase in forbidden, f"verdict_forbids:{phrase}", tests)

    for key, value in load["authorizationBoundary"].items():
        if key == "protocolFreezeAuthorized":
            check(value is True, "load_protocol_freeze_authorized", tests)
        else:
            check(value is False, f"load_execution_boundary_false:{key}", tests)

    science = docs["science"]
    check(science["version"] == 2, "science_version_two", tests)
    check(science["unchangedScientificDesign"]["algorithms"] == ALGORITHMS, "science_six_algorithms_unchanged", tests)
    check(science["unchangedScientificDesign"]["primaryStructuralCells"] == 48, "science_48_cells_unchanged", tests)
    check(science["unchangedScientificDesign"]["primaryEndpointDomains"] == 7, "science_seven_domains_unchanged", tests)
    check(science["unchangedScientificDesign"]["majoritySupportMinimumDomains"] == 4, "science_four_of_seven_unchanged", tests)
    check(science["newMandatoryGate"]["binding"] == NEW_JSON["load"], "science_binds_load_gate", tests)
    check(science["newMandatoryGate"]["requiredReceiptStatus"] == "PASS_LOAD_QUALIFICATION", "science_requires_pass", tests)
    check(science["qualificationDesignSnapshot"]["totalPilotSuperblocks"] == 162, "science_qualification_162", tests)
    check(science["qualificationDesignSnapshot"]["freshAlgorithmProcesses"] == 972, "science_qualification_972", tests)
    check(science["currentObservationBoundary"]["qualificationObservationCount"] == 0, "science_zero_qualification_observations", tests)
    check(science["currentObservationBoundary"]["formalObservationCount"] == 0, "science_zero_formal_observations", tests)
    check(science["currentObservationBoundary"]["UnityProcessCount"] == 0, "science_zero_unity_processes", tests)

    parameters = docs["parameters"]
    check(parameters["version"] == 2, "parameters_version_two", tests)
    check(parameters["inherits"]["sha256"] == V1_BINDINGS[parameters["inherits"]["path"]], "parameters_binds_v1", tests)
    check(parameters["newPrerequisite"]["binding"] == NEW_JSON["load"], "parameters_binds_load_gate", tests)
    check(parameters["newPrerequisite"]["requiredReceiptStatus"] == "PASS_LOAD_QUALIFICATION", "parameters_requires_pass", tests)
    for key, value in parameters["currentlyUnresolved"].items():
        check(value is None, f"parameter_not_invented:{key}", tests)
    check(parameters["fixedConstraints"]["BMustBePositiveMultipleOf"] == 36, "parameters_B_multiple_36", tests)
    check(parameters["fixedConstraints"]["targetPowerAtLeast"] == 0.9, "parameters_power_point_nine", tests)
    check(parameters["authorizationBoundary"]["qualificationExecutionAuthorized"] is False, "parameters_qualification_not_authorized", tests)
    check(parameters["authorizationBoundary"]["parameterValuesAuthorized"] is False, "parameters_values_not_authorized", tests)

    status = docs["status"]
    check(status["version"] == 2, "status_version_two", tests)
    check(status["v1Preservation"]["v1ArtifactsModified"] is False, "status_v1_not_modified", tests)
    check(status["loadQualificationSnapshot"]["totalPilotSuperblocks"] == 162, "status_162_superblocks", tests)
    check(status["loadQualificationSnapshot"]["freshAlgorithmProcesses"] == 972, "status_972_processes", tests)
    check(status["unchangedDesignSummary"]["algorithms"] == ALGORITHMS, "status_algorithms_unchanged", tests)
    check(status["unchangedDesignSummary"]["finalB"] is None, "status_final_B_pending", tests)
    root_state = status["rootAndObservationState"]
    for key, value in root_state.items():
        if key.endswith("Exists"):
            check(value is False, f"status_root_absent:{key}", tests)
        elif key.endswith("Count"):
            check(value == 0, f"status_zero_count:{key}", tests)
        else:
            check(value is False, f"status_no_prior_data:{key}", tests)
    for key, value in status["authorization"].items():
        if key in ("v2ScientificFreeze", "loadQualificationGateFreeze"):
            check(value is True, f"status_authorized:{key}", tests)
        else:
            check(value is False, f"status_not_authorized:{key}", tests)

    prohibited_roots = [
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ]
    for relative in prohibited_roots:
        check(not (root / relative).exists(), f"execution_root_absent:{relative}", tests)

    return {
        "schema": "gate14re-me-load-qualification-freeze-validation-output-v1",
        "studyId": "Gate14Re-ME",
        "result": "PASS",
        "testCount": len(tests),
        "tests": tests,
        "artifactSha256": artifact_hashes,
        "dataBoundary": {
            "controlAndProtocolArtifactsOnly": True,
            "priorGate14ReObservationsRead": False,
            "excludedGate14ReTB2ObservationsRead": False,
            "Gate14ReMEQualificationObservationsReadOrCreated": 0,
            "Gate14ReMEFormalObservationsReadOrCreated": 0,
            "UnityProcessesLaunched": 0,
        },
        "authorizationBoundary": {
            "qualificationExecutionAuthorized": False,
            "formalCollectionAuthorized": False,
            "formalAnalysisAuthorized": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        result = validate(args.root.resolve())
    except Exception as exc:
        print(json.dumps({
            "result": "FAIL",
            "errorType": type(exc).__name__,
            "message": str(exc),
        }, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
