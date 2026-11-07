using System;

namespace DDM.Research.Gate14ReTB.V1
{
    [Serializable]
    public sealed class Gate14ReTBCoordinateV1
    {
        public int x;
        public int y;
    }

    [Serializable]
    public sealed class Gate14ReTBEventScheduleV1
    {
        public string[] eventIds;
        public long[] ticks;
    }

    [Serializable]
    public sealed class Gate14ReTBInputBundleV1
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
        public Gate14ReTBCoordinateV1 goalGridCoordinate;
        public Gate14ReTBCoordinateV1[] spawnGridCoordinates512;
        public string eventScheduleVariantId;
        public Gate14ReTBEventScheduleV1 eventSchedule;
        public double fixedStepSeconds;
        public double movementCapSeconds;
        public string nestedPrefixRule;
        public string bundleSha256;
    }

    [Serializable]
    public sealed class Gate14ReTBStage1PlanV1
    {
        public string schema;
        public string studyId;
        public int version;
        public string status;
        public string stage;
        public int B0;
        public int designCellCount;
        public int plannedUniqueSuperblocks;
        public int plannedFreshUnityProcesses;
        public int processesPerSuperblock;
        public string inputDrawLedgerSha256;
        public string inputBundleFileManifestSha256;
        public string labelCustodyCommitmentSha256;
        public bool algorithmIdentityPresent;
        public string[] anonymousLabels;
        public bool wholeSuperblockAtomicity;
        public bool perAlgorithmRetryResumeTopUpMergeSkipReorder;
        public Gate14ReTBStage1SuperblockV1[] superblocks;
        public Gate14ReTBStage1SampleV1[] samples;
    }

    [Serializable]
    public sealed class Gate14ReTBStage1SuperblockV1
    {
        public int sequence;
        public string superblockId;
        public string module;
        public string conditionId;
        public int unitCount;
        public int drawIndex;
        public string distanceStratum;
        public string[] anonymousLabelsInOrder;
        public string[] sampleIdsInOrder;
        public int maximumWholeSuperblockTechnicalReplacements;
    }

    [Serializable]
    public sealed class Gate14ReTBStage1SampleV1
    {
        public int sampleSequence;
        public string sampleId;
        public string superblockId;
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
    public sealed class Gate14ReTBLabelCustodyCommitmentV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string custodyId;
        public string[] anonymousLabels;
        public string[] productionAlgorithmSet;
        public string mappingCommitmentSha256;
        public Gate14ReTBLabelProtectionV1 protection;
        public bool plaintextMappingPersisted;
        public bool mappingMayBeReleasedBeforeFrozenWinnerAdjudication;
        public string proceduralBoundary;
        public bool formalCollectionAuthorized;
        public bool formalAnalysisAuthorized;
        public bool unblindingAuthorized;
    }

    [Serializable]
    public sealed class Gate14ReTBLabelProtectionV1
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
    public sealed class Gate14ReTBLabelCustodySecretV1
    {
        public string schema;
        public string studyId;
        public string custodyId;
        public Gate14ReTBLabelMapEntryV1[] mapping;
    }

    [Serializable]
    public sealed class Gate14ReTBLabelMapEntryV1
    {
        public string anonymousLabel;
        public string productionAlgorithmId;
    }

    [Serializable]
    public sealed class Gate14ReTBAuthorizationV1
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
    public sealed class Gate14ReTBExecutionContractV1
    {
        public string schema;
        public string studyId;
        public int version;
        public string status;
        public string stage;
        public string stage1PlanSha256;
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
    public sealed class Gate14ReTBUnitRawV1
    {
        public int unitIndex;
        public string terminalState;
        public bool arrived;
        public long arrivalTick;
        public double cumulativeHorizontalPathLength;
    }

    [Serializable]
    public sealed class Gate14ReTBStructuralEventRawV1
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
    public sealed class Gate14ReTBSampleOutputV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string stage;
        public string sampleId;
        public string superblockId;
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
        public Gate14ReTBUnitRawV1[] units;
        public int m5CriticalViolationCount;
        public string[] m5CriticalViolationCodes;
        public int warmupRenderedFrames;
        public int measuredRenderedFrameIntervals;
        public double[] frameIntervalsSeconds;
        public double medianFrameTimeSeconds;
        public double nearestRankP95FrameTimeSeconds;
        public long simulationTickAtEnd;
        public int structuralEventCount;
        public Gate14ReTBStructuralEventRawV1[] structuralEvents;
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
    public sealed class Gate14ReTBTraceHeaderV1
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
    public sealed class Gate14ReTBValidationMarkerV1
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
    public sealed class Gate14ReTBFailureV1
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
