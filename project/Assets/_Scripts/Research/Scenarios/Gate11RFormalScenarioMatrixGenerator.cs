using System;

namespace DDM.Research.Scenarios
{
    /// <summary>
    /// Additive Gate 11R identity facade. Scenario materialization delegates to
    /// the already verified integer-only generator, whose exact source hash is
    /// bound in Gate 11R provenance. It never reads the retained Gate 11 bundle.
    /// </summary>
    public static class Gate11RFormalScenarioMatrixGenerator
    {
        public const string SpecificationId = "gate11r-process-reuse-5pct-scenario-playable-spec-v1";
        public const string MatrixId = "gate11r-process-reuse-5pct-scenario-matrix-v1";
        public const string GeneratorId = "ddm-gate11r-formal-scenario-generator-v1";
        public const string PreregistrationId = "ddm-gate11r-planning-preregistration-v1";
        public const string PlayableBundleId = "gate11r-playable-experiment-bundle-v1";
        public const string ExecutionDesignId = "gate10r-one-fresh-unity-process-per-williams-block-5pct-v1";
        public const string PrecisionPolicyId = "two-sided-95pct-ci-relative-half-width-5pct-uncapped-v1";
        public const string DirectionGlyphId = "research-visual-direction-glyph-v1";
        public const string VisualizationWatermark = "VISUALIZATION REPLAY — NOT A TIMING RUN";
        public const string CaptureLayoutId = "gate11r-fixed-capture-layout-16x9-v1";
        public const int ExpectedScenarioCount = 53;
        public const int ExpectedSharedScenarioCount = 32;
        public const int ExpectedHeterogeneousScenarioCount = 21;
        public const int ExpectedCampaignCount = 74;
        public const int ExpectedEligibilityCount = 212;
        public const int ExpectedSceneCount = 53;
        public const int ExpectedProfileCount = 74;
        public const int ExpectedPresetCount = 212;
        public const int MinimumFormalBlocks = 32;
        public const int FormalBlockMultiple = 4;
        public const double RelativeHalfWidthLogTarget = 0.048790164169432d;

        public static FormalScenarioBlueprint[] BuildBlueprints()
        {
            FormalScenarioBlueprint[] rows = FormalScenarioMatrixGenerator.BuildBlueprints();
            if (rows == null || rows.Length != ExpectedScenarioCount)
            {
                throw new InvalidOperationException("The frozen Gate 11R scenario count changed.");
            }
            return rows;
        }

        public static DeterministicScenarioDefinition GenerateDefinition(FormalScenarioBlueprint blueprint)
        {
            return FormalScenarioMatrixGenerator.GenerateDefinition(blueprint);
        }
    }
}
