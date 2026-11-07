"""Verbatim scientific analysis block from frozen SMSB v1.3 analyzer."""
def compute(engine, package_root, terminal_final_path, bindings, schedule_path, identity_path, pq, output_root):
    globals().update({k:v for k,v in vars(engine).items() if not k.startswith("__")})
    terminal, acceptance_manifest, tables = validate_acceptance_package(
        package_root,
        terminal_final_path,
        bindings["acceptanceTerminalFinalSha256"],
        bindings["acceptanceTerminalReceiptSha256"],
        bindings["acceptanceManifestSha256"],
        bindings["acceptanceFileManifestSha256"],
    )
    schedule, lane_map = load_schedule_and_identity(
        schedule_path, bindings["scheduleSha256"], identity_path, bindings["identityBindingSha256"]
    )
    control_ledgers = validate_control_ledgers(pq, package_root, tables)
    table_path = lambda table_id: package_root / str(tables[table_id]["typedParquet"]["relativePath"])
    lanes, d3_links, event_gates = aggregate_event_groups(pq, table_path("event-groups"), lane_map)
    d3_gate = attach_d3_allocations(pq, table_path("d3-windows"), lanes, d3_links)
    d4_gate = attach_persistent_state(pq, table_path("persistent-state"), lanes)
    correctness = validate_operations_and_oracle(
        pq, table_path("operations"), table_path("oracle-event-checks")
    )
    X, fixed_effect_columns, indices, centers = build_design_matrix(lanes)
    models = fit_all_models(lanes, X, fixed_effect_columns)
    domain_gates = {
        "D1_DYNAMIC_LATENCY": bool(event_gates["D1EventGroupValidity"]),
        "D2_GRID_READ_WORK": bool(event_gates["D2GridCounterValidity"]),
        "D3_DYNAMIC_ALLOCATION": bool(d3_gate["D3CounterValidity"]),
        "D4_PERSISTENT_STATE_BYTES": bool(d4_gate["D4SizingFormulaValidity"]),
        "D5_AGENT_COUNT_SCALING": bool(event_gates["D1EventGroupValidity"]),
        "D6_CHANGE_FOOTPRINT_SCALING": bool(event_gates["D1EventGroupValidity"]),
        "D7_GRID_SIZE_SCALING": bool(event_gates["D1EventGroupValidity"]),
    }
    confirmatory = build_confirmatory_results(models, indices, domain_gates, bool(correctness["correctnessOracle"]))
    exploratory = build_exploratory_results(models, indices)
    descriptive = build_descriptive_results(lanes)
    source_reverification = reverify_acceptance_manifest(package_root, bindings["acceptanceFileManifestSha256"])
    hard_gates = {
        "completeAcceptedDelivery": True,
        "sourcePackageUnchangedDuringAnalysis": source_reverification["allHashesStillMatch"],
        "correctnessOracle": bool(correctness["correctnessOracle"]),
        "D1MeasurementValidity": domain_gates["D1_DYNAMIC_LATENCY"],
        "D2CounterValidity": domain_gates["D2_GRID_READ_WORK"],
        "D3CounterValidity": domain_gates["D3_DYNAMIC_ALLOCATION"],
        "D4SizingFormulaValidity": domain_gates["D4_PERSISTENT_STATE_BYTES"],
        "preservedFailureResolutionCompatibility": control_ledgers["preservedTechnicalFailureRows"] == 2,
        "zeroReplacement": control_ledgers["replacementRows"] == 0,
    }
    input_audit = {
        "schema": "gate14re-me-formal-st-analysis-input-audit-v1",
        "studyId": STUDY_ID,
        "status": "PASS_FROZEN_ACCEPTANCE_INPUT_AUDIT",
        "sourceAcceptanceAttempt": "attempt-002",
        "sourceAcquisitionAttempt": "attempt-003",
        "analysisAttempt": "attempt-004",
        "comparators": list(COMPARATORS),
        "minimumComparatorHypothesesRequiredForDomainPass": MIN_DOMAIN_COMPARATOR_PASSES,
        "bindings": bindings,
        "acceptanceTerminalStatus": terminal["status"],
        "acceptanceManifestStatus": acceptance_manifest["status"],
        "tableRowCounts": acceptance_manifest["tableRowCounts"],
        "scheduleRows": len(schedule),
        "scheduledAlgorithmLanes": len(lane_map),
        "controlLedgers": control_ledgers,
        "eventGroupValidation": event_gates,
        "d3Validation": d3_gate,
        "d4Validation": d4_gate,
        "correctnessValidation": correctness,
        "sourcePackageReverification": source_reverification,
        "sourceRootsModified": False,
    }
    lane_rows = [
        {
            "schema": "gate14re-me-formal-st-lane-estimand-v1",
            "superblockId": lane["superblockId"],
            "anonymousLaneId": lane["anonymousLaneId"],
            "algorithm": lane["algorithm"],
            "executionPosition": lane["executionPosition"],
            "scheduleOrdinal": lane["scheduleOrdinal"],
            "gridEdge": lane["gridEdge"],
            "agentCount": lane["agentCount"],
            "changedCellCount": lane["changedCellCount"],
            "changeTopology": lane["changeTopology"],
            "graphProfile": lane["graphProfile"],
            "sameTickAtomicPartitions": lane["sameTickAtomicPartitions"],
            "contextStratumId": lane["contextStratumId"],
            "d1GeometricMeanMilliseconds": lane["d1GeometricMeanMilliseconds"],
            "d1NearestRankP95Milliseconds": lane["d1NearestRankP95Milliseconds"],
            "d2GridAccessorCalls": lane["d2GridAccessorCalls"],
            "d2GridContainsCalls": lane["d2GridContainsCalls"],
            "d2GridIsWalkableCalls": lane["d2GridIsWalkableCalls"],
            "d2GridGetTraversalCostCalls": lane["d2GridGetTraversalCostCalls"],
            "d3TotalManagedAllocationBytes": lane["d3TotalManagedAllocationBytes"],
            "d4MaxPersistentStateBytes": lane["d4MaxPersistentStateBytes"],
            "independentUnit": False,
        }
        for lane in lanes
    ]
    model_diagnostics = {
        "schema": "gate14re-me-formal-st-model-diagnostics-v1",
        "studyId": STUDY_ID,
        "fixedEffectColumns": fixed_effect_columns,
        "axisCenters": centers,
        "executionPositionCoding": "categorical with position 0 reference",
        "algorithmReference": TARGET,
        "models": {model_id: strip_model_arrays(model) for model_id, model in models.items()},
        "modelSelectionByPValueDirectionOrWinner": False,
    }

    write_json(output_root / "analysis-input-audit.v1.json", input_audit)
    write_json(output_root / "hard-gates.v1.json", {"schema": "gate14re-me-formal-st-hard-gates-v1", **hard_gates})
    write_jsonl(output_root / "lane-estimands.v1.jsonl", lane_rows)
    write_json(output_root / "descriptive-summaries.v1.json", descriptive)
    write_json(output_root / "model-fit-diagnostics.v1.json", model_diagnostics)
    write_json(output_root / "confirmatory-results.v1.json", confirmatory)
    write_json(output_root / "exploratory-pair-matrices.v1.json", exploratory)
    report_text = build_report(confirmatory, hard_gates, models)
    atomic_write_text(output_root / "formal-st-analysis-report.zh-CN.v1.md", report_text)
