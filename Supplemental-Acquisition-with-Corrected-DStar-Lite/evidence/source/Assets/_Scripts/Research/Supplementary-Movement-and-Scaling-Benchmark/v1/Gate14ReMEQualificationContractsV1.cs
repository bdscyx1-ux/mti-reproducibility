using System;
using DDM.Research.Navigation;

namespace DDM.Research.Gate14ReME.V1
{
    public static class Gate14ReMEQualificationConstantsV1
    {
        public const string StudyId = "Gate14Re-ME";
        public const string ProtocolId = "gate14re-me-load-qualification-v1";
        public const string InputSchema = "gate14re-me-qualification-input-bundle-v1";
        public const string ExecutionAuthorizationSchema = "gate14re-me-load-qualification-execution-authorization-v1";
        public const string ImplementationManifestSchema = "gate14re-me-qualification-implementation-manifest-v1";
        public const string OracleReceiptSchema = "gate14re-me-oracle-pass-receipt-v1";
        public const string LaneReceiptSchema = "gate14re-me-qualification-lane-receipt-v1";
        public const string EmptyBoundaryReceiptSchema = "gate14re-me-empty-boundary-receipt-v1";
        public const string InstrumentReceiptSchema = "gate14re-me-instrument-qualification-receipt-v1";
        public const string ResourceBudgetSchema = "gate14re-me-qualification-resource-budget-v1";
        public const string FairnessBindingSchema = "gate14re-me-six-algorithm-fairness-binding-v1";
        public const int EventGroupCount = 24;
        public const int StateMeasurementPointCount = 26;

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
    }

    [Serializable]
    public sealed class Gate14ReMEExecutionAuthorizationV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public bool qualificationInputGenerationAuthorized;
        public bool qualificationRootCreationAuthorized;
        public bool compileOrUnityExecutionAuthorized;
        public bool qualificationExecutionAuthorized;
        public bool formalCollectionAuthorized;
        public bool formalAnalysisAuthorized;
        public string measuredRootRelativePath;
        public string implementationManifestRelativePath;
        public string implementationManifestSha256;
        public string scheduleRelativePath;
        public string scheduleSha256;
        public string authorizationNonce;
    }

    [Serializable]
    public sealed class Gate14ReMEImplementationManifestV1
    {
        public string schema;
        public string studyId;
        public string status;
        public Gate14ReMEFileBindingV1[] artifacts = new Gate14ReMEFileBindingV1[0];
    }

    [Serializable]
    public sealed class Gate14ReMEFileBindingV1
    {
        public string role;
        public string relativePath;
        public string sha256;
        public long bytes;
    }

    [Serializable]
    public sealed class Gate14ReMEQualificationScheduleRowV1
    {
        public string schema;
        public int ordinal;
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
        public Gate14ReMEQualificationScheduleLaneV1[] algorithmOrder = new Gate14ReMEQualificationScheduleLaneV1[0];
        public Gate14ReMEQualificationReplacementV1 replacement;
    }

    [Serializable]
    public sealed class Gate14ReMEQualificationScheduleLaneV1
    {
        public string algorithmId;
        public string anonymousLaneId;
        public string identityBindingSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEQualificationReplacementV1
    {
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEResourceBudgetV1
    {
        public string schema;
        public string studyId;
        public string status;
        public long eventGroupHardTimeoutMilliseconds;
        public long laneWallClockHardTimeoutMilliseconds;
        public long oracleInputHardTimeoutMilliseconds;
        public long instrumentProcessHardTimeoutMilliseconds;
        public long emptyBoundaryProcessHardTimeoutMilliseconds;
        public double plannerOperationBudgetMilliseconds;
        public double repairOperationBudgetMilliseconds;
        public double initializationOperationBudgetMilliseconds;
        public long laneAssignedCommittedMemoryBytes;
        public long qualificationReservedStorageBytes;
        public long formalRawAndDeliveryReservedStorageBytes;
        public int maximumConcurrentUnityProcesses;
        public int maximumWholeSuperblockTechnicalReplacements;
        public double minimumHeadroomFactor;
    }

    [Serializable]
    public sealed class Gate14ReMEFairnessBindingV1
    {
        public string schema;
        public string studyId;
        public string cohortId;
        public string status;
        public Gate14ReMEAlgorithmBindingV1[] algorithms = new Gate14ReMEAlgorithmBindingV1[0];
        public string navigationContractsRelativePath;
        public string navigationContractsSha256;
        public string navigationGridRelativePath;
        public string navigationGridSha256;
        public bool sameByteIdenticalInputBundle;
        public bool oneFreshProcessPerAlgorithmLane;
        public bool sameDynamicBoundary;
        public bool sameOracle;
        public bool algorithmSpecificWarmupGcExtraQueryAllowed;
    }

    [Serializable]
    public sealed class Gate14ReMEAlgorithmBindingV1
    {
        public string algorithmId;
        public string implementationRelativePath;
        public string implementationSha256;
        public string specificationRelativePath;
        public string specificationSha256;
        public string stateModelId;
        public string nativeMetricsSemanticsId;
    }

    [Serializable]
    public sealed class Gate14ReMEQualificationInputBundleV1
    {
        public string schema;
        public string studyId;
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

    [Serializable]
    public sealed class Gate14ReMECellStateV1
    {
        public int x;
        public int y;
        public bool isWalkable;
        public float traversalCost;

        public NavigationGridChange ToChange()
        {
            return new NavigationGridChange
            {
                coordinate = new GridCoordinate(x, y),
                isWalkable = isWalkable,
                traversalCost = traversalCost
            };
        }
    }

    [Serializable]
    public sealed class Gate14ReMEEventGroupV1
    {
        public string eventGroupId;
        public int eventGroupIndex;
        public int cycleIndex;
        public string phase;
        public string topology;
        public Gate14ReMEAtomicPartitionV1[] atomicPartitions = new Gate14ReMEAtomicPartitionV1[0];
    }

    [Serializable]
    public sealed class Gate14ReMEAtomicPartitionV1
    {
        public int partitionIndex;
        public Gate14ReMECellStateV1[] changes = new Gate14ReMECellStateV1[0];
    }

    [Serializable]
    public sealed class Gate14ReMEOracleAgentRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public int eventGroupIndex;
        public string comparisonSide;
        public int agentIndex;
        public int startX;
        public int startY;
        public int goalX;
        public int goalY;
        public bool reachable;
        public double shortestPathCost;
        public int shortestPathSteps;
        public bool affected;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEOracleEventRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string eventGroupId;
        public int eventGroupIndex;
        public int cycleIndex;
        public string phase;
        public string topology;
        public int uniqueChangedCellCount;
        public int affectedAgentCount;
        public double affectedAgentFraction;
        public bool minimumAffectedAgentsPassed;
        public bool bottleneckHalfAgentsRuleApplicable;
        public bool bottleneckHalfAgentsPassed;
        public bool restoreGridBytesPassed;
        public bool restoreOraclePassed;
        public string beforeGridSha256;
        public string afterGridSha256;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEOraclePassReceiptV1
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public string inputId;
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
        public string oracleSourceRelativePath;
        public string oracleSourceSha256;
        public int agentRowCount;
        public int eventGroupRowCount;
        public int minimumAffectedAgentCount;
        public double medianAffectedAgentFraction;
        public bool allGeometryChecksPassed;
        public string createdAtUtc;
    }

    [Serializable]
    public sealed class Gate14ReMEGridCounterSnapshotV1
    {
        public long containsCalls;
        public long isWalkableCalls;
        public long getTraversalCostCalls;
        public long totalCalls;
    }

    [Serializable]
    public sealed class Gate14ReMEOperationRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string operationType;
        public string operationId;
        public int eventGroupIndex;
        public int partitionIndex;
        public int agentIndex;
        public long gridVersion;
        public string status;
        public string failureReasonCode;
        public bool budgetExceeded;
        public double elapsedCpuMilliseconds;
        public long processedNodesOrCells;
        public long expandedNodes;
        public long relaxedEdges;
        public long repairedCells;
        public long managedAllocatedBytes;
        public bool oracleReachable;
        public double oraclePathCost;
        public double reportedPathCost;
        public bool oraclePathCostMatch;
        public string nativeMetricsSemanticsId;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEEventGroupRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string designRegion;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public int gridEdge;
        public int agentCount;
        public int changedCellCount;
        public string changeTopology;
        public string graphProfile;
        public int sameTickAtomicPartitions;
        public string contextStratumId;
        public string eventGroupId;
        public int eventGroupIndex;
        public int cycleIndex;
        public string phase;
        public double eventGroupElapsedMilliseconds;
        public long allocationCounterStart;
        public long allocationCounterEnd;
        public long eventGroupManagedAllocatedBytes;
        public string allocationCounterId;
        public long gridContainsCalls;
        public long gridIsWalkableCalls;
        public long gridGetTraversalCostCalls;
        public long gridAccessorCallsTotal;
        public int repairOperationCount;
        public int planOperationCount;
        public int succeededPlanCount;
        public int noPathPlanCount;
        public int budgetExceededOperationCount;
        public bool eligible;
        public string missingOrIneligibleReasonCode;
        public bool finitePositiveElapsed;
        public bool counterValid;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEPersistentStateRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string measurementPointId;
        public int eventGroupIndex;
        public string persistentContainerName;
        public string containerKind;
        public long persistentContainerCapacity;
        public int persistentContainerBytesPerElement;
        public long persistentContainerCapacityBytes;
        public long persistentPrimitiveArrayBytes;
        public long persistentStateBytesTotal;
        public string sizingFormulaId;
        public bool valid;
        public string invalidReasonCode;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEProcessResourceRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string measurementPointId;
        public int eventGroupIndex;
        public int processId;
        public long privateMemoryBytes;
        public long workingSetBytes;
        public long managedMemoryBytes;
        public long peakWorkingSetBytes;
        public string capturedAtUtc;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEEmptyBoundaryRawV1
    {
        public string recordId;
        public int processOrdinal;
        public int iterationIndex;
        public long stopwatchStartTicks;
        public long stopwatchEndTicks;
        public double elapsedMilliseconds;
        public long allocationCounterStart;
        public long allocationCounterEnd;
        public long allocatedBytes;
        public bool plannerInvoked;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMELaneReceiptV1
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string inputRelativePath;
        public string inputSha256;
        public string oracleReceiptRelativePath;
        public string oracleReceiptSha256;
        public string implementationManifestSha256;
        public string fairnessBindingSha256;
        public string resourceBudgetSha256;
        public int eventGroupRows;
        public int operationRows;
        public int persistentStateRows;
        public int processResourceRows;
        public long peakCommittedBytes;
        public double laneWallClockMilliseconds;
        public bool instrumentValid;
        public bool completed;
        public string failureReasonCode;
        public string createdAtUtc;
    }

    [Serializable]
    public sealed class Gate14ReMEEmptyBoundaryReceiptV1
    {
        public string schema;
        public string studyId;
        public string status;
        public int processOrdinal;
        public int rawIterationRows;
        public bool plannerInvoked;
        public string implementationManifestSha256;
        public string resourceBudgetSha256;
        public string createdAtUtc;
    }

    [Serializable]
    public sealed class Gate14ReMEInstrumentQualificationReceiptV1
    {
        public string schema;
        public string studyId;
        public string status;
        public bool gridReadProxyKnownAnswerPassed;
        public bool gridReadProxySemanticInvariancePassed;
        public bool allocationCounterPositiveControlPassed;
        public bool persistentStateSizerSyntheticFixturePassed;
        public bool clockMonotonicityPassed;
        public bool rawToExportRoundTripPassed;
        public bool tamperNegativeTestPassed;
        public bool missingNegativeTestPassed;
        public bool duplicateNegativeTestPassed;
        public bool anonymousLabelSwapNegativeTestPassed;
        public string implementationManifestSha256;
        public string createdAtUtc;
    }
}
