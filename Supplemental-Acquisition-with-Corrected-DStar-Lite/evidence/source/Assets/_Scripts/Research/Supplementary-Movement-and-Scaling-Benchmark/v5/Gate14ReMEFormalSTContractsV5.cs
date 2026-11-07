using System;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Navigation;

namespace DDM.Research.Gate14ReME.V5
{
    /// <summary>
    /// Formal-ST-owned wire identities.  The row payload types that were already
    /// qualified remain V1 exact-hash dependencies; only formal input, schedule,
    /// authorization, manifest and receipt identities are versioned here.
    /// </summary>
    public static class Gate14ReMEFormalSTConstantsV5
    {
        public const string StudyId = "Gate14Re-ME";
        public const string DesignId = "gate14re-me-formal-st-bounded-gnf-v5";
        public const string ProtocolId = "gate14re-me-formal-st-v5";
        public const string InputSchema = "gate14re-me-formal-st-input-bundle-v5";
        public const string ScheduleRowSchema = "gate14re-me-formal-st-schedule-row-v5";
        public const string ExecutionAuthorizationSchema = "gate14re-me-formal-st-execution-authorization-v5";
        public const string ImplementationManifestSchema = "gate14re-me-formal-st-implementation-manifest-v5";
        public const string OracleReceiptSchema = "gate14re-me-formal-st-oracle-pass-receipt-v5";
        public const string LaneReceiptSchema = "gate14re-me-formal-st-lane-receipt-v5";
        public const string EmptyBoundaryReceiptSchema = "gate14re-me-formal-st-empty-boundary-receipt-v5";
        public const string InstrumentReceiptSchema = "gate14re-me-formal-st-instrument-readiness-receipt-v5";
        public const string ResourceBudgetSchema = "gate14re-me-formal-st-operational-resource-budget-v5";
        public const string FairnessBindingSchema = "gate14re-me-six-algorithm-fairness-binding-v1";
        public const int EventGroupCount = 24;
        public const int StateMeasurementPointCount = 26;
        public const int StructuralCellCount = 36;
        public const int SuperblocksPerCell = 36;
        public const int SuperblockCount = 1296;
        public const int LanesPerSuperblock = 6;
        public const int MeasuredLaneProcessCount = 7776;

        public static readonly string[] NamedAlgorithms =
        {
            NavigationAlgorithmIds.AStarRepeated,
            NavigationAlgorithmIds.BidirectionalAStarRepeated,
            NavigationAlgorithmIds.DStarLite,
            NavigationAlgorithmIds.LifelongPlanningAStar,
            NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
            NavigationAlgorithmIds.IncrementalDynamicFlowField
        };

        public static readonly string[] AnonymousLanes =
        {
            "ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"
        };

        public static readonly string[][] WilliamsOrders =
        {
            new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.BidirectionalAStarRepeated, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.LifelongPlanningAStar },
            new[] { NavigationAlgorithmIds.BidirectionalAStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.LifelongPlanningAStar, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField },
            new[] { NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.LifelongPlanningAStar, NavigationAlgorithmIds.BidirectionalAStarRepeated, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.IncrementalDynamicFlowField },
            new[] { NavigationAlgorithmIds.LifelongPlanningAStar, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.BidirectionalAStarRepeated, NavigationAlgorithmIds.AStarRepeated },
            new[] { NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.LifelongPlanningAStar, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.BidirectionalAStarRepeated },
            new[] { NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.BidirectionalAStarRepeated, NavigationAlgorithmIds.LifelongPlanningAStar, NavigationAlgorithmIds.DStarLite }
        };
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTExecutionAuthorizationV5
    {
        public string schema;
        public string studyId;
        public string designId;
        public string authorizationId;
        public string status;
        public bool formalInputGenerationAuthorized;
        public bool formalRootCreationAuthorized;
        public bool compileOrUnityExecutionAuthorized;
        public bool formalCollectionAuthorized;
        public bool formalAcceptanceExecutionAuthorized;
        public bool formalAnalysisAuthorized;
        public bool mqAuthorized;
        public bool mtAuthorized;
        public string measuredRootRelativePath;
        public string implementationManifestRelativePath;
        public string implementationManifestSha256;
        public string executionContractRelativePath;
        public string executionContractSha256;
        public string inputFreezeManifestRelativePath;
        public string inputFreezeManifestSha256;
        public string scheduleRelativePath;
        public string scheduleSha256;
        public string authorizationNonce;
        public int oracleBatchCount;
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTImplementationManifestV5
    {
        public string schema;
        public string studyId;
        public string designId;
        public string status;
        public Gate14ReMEFormalSTFileBindingV5[] artifacts = new Gate14ReMEFormalSTFileBindingV5[0];
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTFileBindingV5
    {
        public string role;
        public string relativePath;
        public string sha256;
        public long bytes;
        public string lineageRelativePath;
        public string lineageSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTScheduleRowV5
    {
        public string schema;
        public int ordinal;
        public int cellOrdinal;
        public int replicateIndex;
        public int contextStratumIndex;
        public int orderIndex;
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
        public Gate14ReMEFormalSTScheduleLaneV5[] algorithmOrder = new Gate14ReMEFormalSTScheduleLaneV5[0];
        public Gate14ReMEFormalSTReplacementV5 replacement;
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTScheduleLaneV5
    {
        public string algorithmId;
        public string anonymousLaneId;
        public string identityBindingSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTReplacementV5
    {
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEFormalSTInputBundleV5
    {
        public string schema;
        public string studyId;
        public string designId;
        public string protocolId;
        public string inputId;
        public string superblockId;
        public string designRegion;
        public long seed;
        public int gridEdge;
        public int agentCount;
        public int changedCellCount;
        public string changeTopology;
        public string graphProfile;
        public int sameTickAtomicPartitions;
        public string contextStratumId;
        public NavigationGridConnectivity connectivity;
        public bool allowDiagonalCornerCutting;
        public float defaultTraversalCost;
        public Gate14ReMECellStateV1[] initialCellOverrides = new Gate14ReMECellStateV1[0];
        public GridCoordinate goal;
        public GridCoordinate[] starts = new GridCoordinate[0];
        public Gate14ReMEEventGroupV1[] eventGroups = new Gate14ReMEEventGroupV1[0];
    }
}
