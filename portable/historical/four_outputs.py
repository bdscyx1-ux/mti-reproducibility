"""Verbatim scientific output assembly from frozen four-method analyzer."""
def compute(engine, blocks, shared_blocks, heterogeneous_blocks, superblocks, frozen_timestamp):
    globals().update({k:v for k,v in vars(engine).items() if not k.startswith("__")})
    coverage = build_coverage(blocks, superblocks)
    coverage["generatedAtUtc"] = frozen_timestamp

    p1 = shared_continuous_analysis(shared_blocks, "P1")
    apply_p1_multiplicity(p1)
    shared_primary = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-SHARED-CONFIRMATORY-P1",
        "generatedAtUtc": frozen_timestamp,
        "metric": p1,
        "familyWiseAlpha": ALPHA,
        "multiplicityMethod": "HOLM",
        "simultaneousCiMethod": "BONFERRONI-COMPATIBLE-99-PERCENT-FOR-FIVE-CONTRASTS",
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    supportive_continuous = [shared_continuous_analysis(shared_blocks, metric) for metric in ("P2", "P3-PER-AGENT", "P4")]
    shared_supportive = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-SHARED-SUPPORTIVE-P2-P5",
        "generatedAtUtc": frozen_timestamp,
        "continuousMetrics": supportive_continuous,
        "p3ScalingSlope": p3_scaling_analysis(shared_blocks),
        "p5CountsAndRates": aggregate_p5(shared_blocks, "campaignId"),
        "confirmatoryPromotionAllowed": False,
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    heterogeneous_secondary = {
        "schemaVersion": 1,
        "artifactKind": "GATE13R-PR2-ATTEMPT4-HETEROGENEOUS-SECONDARY",
        "generatedAtUtc": frozen_timestamp,
        "matchedSuperblockCount": len(superblocks),
        "continuousMetrics": [heterogeneous_continuous_analysis(superblocks, metric) for metric in CONTINUOUS_METRICS],
        "p5CountsAndRates": aggregate_p5(heterogeneous_blocks, "scenarioId"),
        "confirmatoryPromotionAllowed": False,
        "globalWinnerOrMajorityVoteProduced": False,
        "gate14RAuthorized": False,
    }

    return {"schedule-coverage-and-missingness.json":coverage,"shared-primary-p1-analysis.json":shared_primary,"shared-supportive-p2-p5-analysis.json":shared_supportive,"heterogeneous-secondary-analysis.json":heterogeneous_secondary}
