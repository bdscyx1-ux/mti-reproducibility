using System;
using DDM.Research.Gate14ReTB2.V1;

namespace DDM.Research.Gate14ReTB2.V2
{
    [Serializable]
    public sealed class Gate14ReTB2FormalPlanV2
    {
        public string schema;
        public string studyId;
        public int version;
        public string status;
        public string stage;
        public string route;
        public int B;
        public int designCellCount;
        public bool quantitySubstudyRetained;
        public string[] quantityAnchors;
        public int[] quantityN;
        public bool N128AnchorReuse;
        public int plannedUniqueSuperblocks;
        public int plannedAnonymousAlgorithmLanes;
        public int plannedFreshUnityProcesses;
        public int processesPerSuperblock;
        public int lanesPerProcess;
        public int operationalChunkCount;
        public int superblocksPerOperationalChunk;
        public int orderPermutationCount;
        public int replicatesPerOrderPerCell;
        public int fullM1ThroughM5TelemetryLanes;
        public int tracedSuperblocks;
        public int tracedAnonymousLanes;
        public string sourceV1FormalPlanSha256;
        public string sourceV1InputBundleManifestSha256;
        public string inputBundleAdoptionReceiptSha256;
        public string inputDrawLedgerSha256;
        public string labelCustodyCommitmentSha256;
        public bool algorithmIdentityPresent;
        public string[] anonymousLabels;
        public bool wholeSuperblockAtomicity;
        public bool oneFreshProcessPerSuperblock;
        public bool serialLanesInFrozenWilliamsOrder;
        public bool hardResetBetweenLanesRequired;
        public int maximumWholeSuperblockTechnicalReplacements;
        public bool perAlgorithmRetryResumeTopUpMergeSkipReorder;
        public bool formalRootCreated;
        public bool formalCollectionAuthorized;
        public Gate14ReTB2FormalSuperblockV2[] superblocks;
    }

    [Serializable]
    public sealed class Gate14ReTB2FormalSuperblockV2
    {
        public int sequence;
        public int operationalChunkSequence;
        public string operationalChunkId;
        public string superblockId;
        public string module;
        public string conditionId;
        public int unitCount;
        public int drawIndex;
        public string distanceStratum;
        public int orderPermutationIndex;
        public string[] anonymousLabelsInOrder;
        public string[] laneIdsInOrder;
        public string bundleRelativePath;
        public long bundleFileBytes;
        public string bundleFileSha256;
        public string bundleSha256;
        public bool traceCaptureRequired;
        public int hardTimeoutSeconds;
        public int maximumWholeSuperblockTechnicalReplacements;
    }

    [Serializable]
    public sealed class Gate14ReTB2ExecutionContractV2
    {
        public string schema;
        public string studyId;
        public int version;
        public string status;
        public string stage;
        public string route;
        public int B;
        public int designCellCount;
        public int plannedUniqueSuperblocks;
        public int plannedAnonymousAlgorithmLanes;
        public int plannedFreshUnityProcesses;
        public string formalPlanSha256;
        public string inputBundleAdoptionReceiptSha256;
        public string sourceV1InputBundleManifestSha256;
        public string labelCustodyCommitmentSha256;
        public double fixedStepSeconds;
        public double movementCapSecondsPerLane;
        public int preReleaseWarmupRenderedFramesPerLane;
        public int traceCaptureEveryFixedTicks;
        public Gate14ReTB2ProcessModelV2 processModel;
        public Gate14ReTB2HardResetContractV2 hardResetBetweenLanes;
        public Gate14ReTB2TraceContractV2 trace;
        public bool productionIdentityPermittedInOutput;
        public bool fileIoDuringMeasuredWindow;
        public bool compressionDuringMeasuredWindow;
        public bool collectionAuthorized;
    }

    [Serializable]
    public sealed class Gate14ReTB2ProcessModelV2
    {
        public bool oneFreshProcessPerCompleteSuperblock;
        public int processesPerSuperblock;
        public int anonymousLanesPerProcess;
        public bool serialWithinSuperblock;
        public bool serialAcrossSuperblocks;
        public bool wholeSuperblockAtomicity;
        public int maximumWholeSuperblockTechnicalReplacements;
        public bool perAlgorithmRetryResumeTopUpMergeSkipReorder;
        public int perProcessHardTimeoutSeconds;
        public bool failClosedAfterFailedWholeSuperblockReplacement;
    }

    [Serializable]
    public sealed class Gate14ReTB2HardResetContractV2
    {
        public bool required;
        public bool waitForUnityDestroyCompletion;
        public bool verifyNoPriorLaneRuntimeObjects;
        public bool cacheOrOperatingSystemIsolationClaimed;
    }

    [Serializable]
    public sealed class Gate14ReTB2TraceContractV2
    {
        public bool selectionOutcomeIndependent;
        public int tracedSuperblocks;
        public int tracedAnonymousLanes;
        public int untracedAnonymousLanes;
        public int captureHzWhenSelected;
        public bool essentialM1ThroughM5TelemetryRetainedForEveryLane;
        public bool preallocatedDuringMeasuredWindow;
        public bool fileIoDuringMeasuredWindow;
        public bool compressionDuringMeasuredWindow;
        public bool flushAfterMeasuredWindow;
        public bool plannerInvokedByReplay;
    }

    [Serializable]
    public sealed class Gate14ReTB2CollectionAuthorizationV2
    {
        public string schema;
        public string studyId;
        public string status;
        public string stage;
        public string planSha256;
        public string executionContractSha256;
        public string outputSchemaContractSha256;
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string measuredRoot;
        public string authorizationId;
        public bool userExplicitlyAuthorizedCollection;
    }

    [Serializable]
    public sealed class Gate14ReTB2LaneOutputV2
    {
        public string laneId;
        public string anonymousAlgorithmLabel;
        public int orderPosition;
        public bool allUnitsArrived;
        public int arrivedCount;
        public int activeAtCapCount;
        public int noPathCount;
        public int budgetExceededCount;
        public int invalidPlanCount;
        public int internalFailureCount;
        public double m1Seconds;
        public Gate14ReTB2UnitRawV1[] units;
        public double m2CommonMaskMeanPathLength;
        public int m5CriticalViolationCount;
        public string[] m5CriticalViolationCodes;
        public int measuredRenderedFrameIntervals;
        public double[] frameIntervalsSeconds;
        public double medianFrameTimeSeconds;
        public double nearestRankP95FrameTimeSeconds;
        public long simulationTickAtEnd;
        public int structuralEventCount;
        public Gate14ReTB2StructuralEventRawV1[] structuralEvents;
        public bool traceCaptured;
        public string traceRawRelativePath;
        public string traceRawSha256;
        public string traceMerkleRootSha256;
        public int traceChunkCount;
        public int traceCapturedTickCount;
        public bool traceCompressionPending;
        public bool complete;
    }

    [Serializable]
    public sealed class Gate14ReTB2HardResetReceiptV2
    {
        public int afterOrderPosition;
        public bool destroyCompleted;
        public int priorLaneRuntimeObjectCount;
        public bool nextLanePreparedFromImmutableBundle;
        public bool passed;
    }

    [Serializable]
    public sealed class Gate14ReTB2SuperblockOutputV2
    {
        public string schema;
        public string studyId;
        public string status;
        public string stage;
        public string superblockId;
        public string operationalChunkId;
        public string module;
        public string conditionId;
        public int unitCount;
        public int drawIndex;
        public string distanceStratum;
        public string bundleSha256;
        public string bundleFileSha256;
        public string sourceScenarioSha256;
        public string planSha256;
        public string executionContractSha256;
        public string outputSchemaContractSha256;
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string authorizationId;
        public string[] anonymousLabelsInOrder;
        public Gate14ReTB2LaneOutputV2[] lanes;
        public int[] commonM2MaskUnitIndices;
        public int commonM2MaskCount;
        public int commonM2MaskMinimumRequired;
        public bool traceCaptureRequired;
        public Gate14ReTB2HardResetReceiptV2[] hardResetReceipts;
        public int warmupRenderedFramesPerLane;
        public int wholeSuperblockAttempt;
        public bool productionAlgorithmIdentityPresent;
        public bool complete;
        public bool formalObservationProduced;
    }

    [Serializable]
    public sealed class Gate14ReTB2ValidationMarkerV2
    {
        public string schema;
        public string studyId;
        public string status;
        public string superblockId;
        public int validatedAnonymousLanes;
        public int validatedHardResets;
        public bool allFourProductionPlannersExercisedWithoutCustodyDecryption;
        public bool inputBundlePreparedPerLane;
        public bool labelCustodyResolvedInMemory;
        public bool productionIdentityWritten;
        public bool tracePolicyMatchedPlan;
        public bool formalObservationProduced;
        public bool m1ThroughM5OutputProduced;
        public bool collectionStarted;
    }

    [Serializable]
    public sealed class Gate14ReTB2FailureV2
    {
        public string schema;
        public string studyId;
        public string status;
        public string superblockId;
        public int completedLaneCount;
        public string exceptionType;
        public string message;
        public bool partialLaneOutputAdmissible;
        public bool formalObservationProduced;
        public bool collectionStarted;
    }
}
