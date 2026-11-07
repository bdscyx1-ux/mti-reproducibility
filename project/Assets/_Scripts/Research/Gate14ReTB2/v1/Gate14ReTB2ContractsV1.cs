using System;

namespace DDM.Research.Gate14ReTB2.V1
{
    [Serializable]
    public sealed class Gate14ReTB2CoordinateV1
    {
        public int x;
        public int y;
    }

    [Serializable]
    public sealed class Gate14ReTB2EventScheduleV1
    {
        public string[] eventIds;
        public long[] ticks;
    }

    [Serializable]
    public sealed class Gate14ReTB2InputBundleV1
    {
        public string schema;
        public string studyId;
        public string generatorId;
        public string generatorImplementationSha256;
        public string supportCertificateSha256;
        public string masterSeedCommitmentSha256;
        public string superblockId;
        public string module;
        public int unitCount;
        public string conditionId;
        public string sourceScenarioRelativePath;
        public string sourceScenarioSha256;
        public int drawIndex;
        public string distanceStratum;
        public Gate14ReTB2CoordinateV1 goalGridCoordinate;
        public Gate14ReTB2CoordinateV1[] spawnGridCoordinates512;
        public string eventScheduleVariantId;
        public Gate14ReTB2EventScheduleV1 eventSchedule;
        public double fixedStepSeconds;
        public double movementCapSeconds;
        public string nestedPrefixRule;
        public string bundleSha256;
    }

    [Serializable]
    public sealed class Gate14ReTB2Stage1PlanV1
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
        public int plannedFreshUnityProcesses;
        public int processesPerSuperblock;
        public int operationalChunkCount;
        public int superblocksPerOperationalChunk;
        public int orderPermutationCount;
        public int replicatesPerOrderPerCell;
        public string inputDrawLedgerSha256;
        public string inputBundleFileManifestSha256;
        public string labelCustodyCommitmentSha256;
        public bool algorithmIdentityPresent;
        public string[] anonymousLabels;
        public bool wholeSuperblockAtomicity;
        public int maximumWholeSuperblockTechnicalReplacements;
        public bool perAlgorithmRetryResumeTopUpMergeSkipReorder;
        public bool formalRootCreated;
        public bool formalCollectionAuthorized;
        public Gate14ReTB2Stage1SuperblockV1[] superblocks;
        public Gate14ReTB2Stage1SampleV1[] samples;
    }

    [Serializable]
    public sealed class Gate14ReTB2Stage1SuperblockV1
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
        public string[] sampleIdsInOrder;
        public int maximumWholeSuperblockTechnicalReplacements;
    }

    [Serializable]
    public sealed class Gate14ReTB2Stage1SampleV1
    {
        public int sampleSequence;
        public string sampleId;
        public string superblockId;
        public string operationalChunkId;
        public string anonymousAlgorithmLabel;
        public int orderPosition;
        public string bundleRelativePath;
        public long bundleFileBytes;
        public string bundleFileSha256;
        public string bundleSha256;
        public string sourceScenarioRelativePath;
        public string sourceScenarioSha256;
        public int hardTimeoutSeconds;
    }

    [Serializable]
    public sealed class Gate14ReTB2LabelCustodyCommitmentV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string custodyId;
        public string[] anonymousLabels;
        public string[] productionAlgorithmSet;
        public string mappingCommitmentSha256;
        public Gate14ReTB2LabelProtectionV1 protection;
        public bool plaintextMappingPersisted;
        public bool mappingMayBeReleasedBeforeFrozenWinnerAdjudication;
        public string proceduralBoundary;
        public bool formalCollectionAuthorized;
        public bool formalAnalysisAuthorized;
        public bool unblindingAuthorized;
    }

    [Serializable]
    public sealed class Gate14ReTB2LabelProtectionV1
    {
        public string mechanism;
        public string scope;
        public bool uiForbidden;
        public string payloadRelativePath;
        public string payloadSha256;
        public string entropyRelativePath;
        public string entropySha256;
    }

    [Serializable]
    public sealed class Gate14ReTB2LabelCustodySecretV1
    {
        public string schema;
        public string studyId;
        public string custodyId;
        public Gate14ReTB2LabelMapEntryV1[] mapping;
    }

    [Serializable]
    public sealed class Gate14ReTB2LabelMapEntryV1
    {
        public string anonymousLabel;
        public string productionAlgorithmId;
    }

    [Serializable]
    public sealed class Gate14ReTB2AuthorizationV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string stage;
        public string planSha256;
        public string executionContractSha256;
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string measuredRoot;
        public string authorizationId;
        public bool userExplicitlyAuthorizedCollection;
    }

    [Serializable]
    public sealed class Gate14ReTB2ExecutionContractV1
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
        public int plannedFreshUnityProcesses;
        public string formalPlanSha256;
        public string inputBundleFileManifestSha256;
        public string labelCustodyCommitmentSha256;
        public string replayContractSha256;
        public double fixedStepSeconds;
        public double movementCapSeconds;
        public int preReleaseWarmupRenderedFrames;
        public int traceCaptureEveryFixedTicks;
        public int perProcessHardTimeoutSeconds;
        public int maximumWholeSuperblockTechnicalReplacements;
        public bool oneFreshProcessPerAnonymousLabel;
        public bool productionIdentityPermittedInOutput;
        public bool fileIoDuringMeasuredWindow;
        public bool compressionDuringMeasuredWindow;
        public bool collectionAuthorized;
    }

    [Serializable]
    public sealed class Gate14ReTB2UnitRawV1
    {
        public int unitIndex;
        public string terminalState;
        public bool arrived;
        public long arrivalTick;
        public double cumulativeHorizontalPathLength;
    }

    [Serializable]
    public sealed class Gate14ReTB2StructuralEventRawV1
    {
        public string eventId;
        public long scheduledTick;
        public int order;
        public int changedCellCount;
        public long previousGridVersion;
        public long newGridVersion;
        public string plannerRepairStatus;
        public string plannerFailureReason;
        public long visualRevision;
    }

    [Serializable]
    public sealed class Gate14ReTB2SampleOutputV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string stage;
        public string sampleId;
        public string superblockId;
        public string operationalChunkId;
        public string anonymousAlgorithmLabel;
        public int orderPosition;
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
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string authorizationId;
        public bool allUnitsArrived;
        public int arrivedCount;
        public int activeAtCapCount;
        public int noPathCount;
        public int budgetExceededCount;
        public int invalidPlanCount;
        public int internalFailureCount;
        public double m1Seconds;
        public Gate14ReTB2UnitRawV1[] units;
        public int m5CriticalViolationCount;
        public string[] m5CriticalViolationCodes;
        public int warmupRenderedFrames;
        public int measuredRenderedFrameIntervals;
        public double[] frameIntervalsSeconds;
        public double medianFrameTimeSeconds;
        public double nearestRankP95FrameTimeSeconds;
        public long simulationTickAtEnd;
        public int structuralEventCount;
        public Gate14ReTB2StructuralEventRawV1[] structuralEvents;
        public string traceRawRelativePath;
        public string traceRawSha256;
        public string traceMerkleRootSha256;
        public int traceChunkCount;
        public int traceCapturedTickCount;
        public bool traceCompressionPending;
        public bool productionAlgorithmIdentityPresent;
        public bool complete;
        public bool formalObservationProduced;
    }

    [Serializable]
    public sealed class Gate14ReTB2TraceHeaderV1
    {
        public string schema;
        public string studyId;
        public string sampleId;
        public string superblockId;
        public string anonymousAlgorithmLabel;
        public string conditionId;
        public int unitCount;
        public string inputBundleSha256;
        public string buildTreeSha256;
        public string assemblySha256;
        public double fixedStepSeconds;
        public int captureEveryFixedTicks;
        public long movementCapTicks;
    }

    [Serializable]
    public sealed class Gate14ReTB2ValidationMarkerV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string sampleId;
        public string anonymousAlgorithmLabel;
        public int unitCount;
        public int structuralEventCount;
        public bool inputBundlePrepared;
        public bool labelCustodyResolvedInMemory;
        public bool productionIdentityWritten;
        public bool traceBufferPreallocated;
        public bool formalObservationProduced;
        public bool m1ThroughM5OutputProduced;
        public bool collectionStarted;
    }

    [Serializable]
    public sealed class Gate14ReTB2FailureV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string sampleId;
        public string exceptionType;
        public string message;
        public bool partialSampleAdmissible;
        public bool formalObservationProduced;
        public bool collectionStarted;
    }
}
