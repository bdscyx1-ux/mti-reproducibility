using System;

namespace DDM.Research.Gate14Re.V2
{
    [Serializable]
    public sealed class Gate14ReFormalPlanV1
    {
        public string schema;
        public string studyId;
        public int version;
        public string status;
        public int fixedB;
        public int plannedValidProcesses;
        public string[] algorithmLabels;
        public string[] algorithmIds;
        public Gate14ReFormalBlockV1[] blocks;
    }

    [Serializable]
    public sealed class Gate14ReFormalBlockV1
    {
        public int sequence;
        public string blockId;
        public string module;
        public string lane;
        public string conditionId;
        public string scenarioId;
        public string scenarioRelativePath;
        public long scenarioBytes;
        public string scenarioSha256;
        public int dynamicFootprintCells;
        public int unitCount;
        public int blockIndex;
        public int williamsRow;
        public string[] algorithmLabelsInOrder;
        public string[] algorithmIdsInOrder;
        public int maximumWholeBlockReplacements;
    }

    [Serializable]
    public sealed class Gate14ReFormalAuthorizationV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string planSha256;
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string formalRoot;
        public string authorizationId;
        public bool userExplicitlyAuthorizedFormalPhaseA;
    }

    [Serializable]
    public sealed class Gate14ReUnitRawV1
    {
        public int agentId;
        public string terminalState;
        public bool arrived;
        public long arrivalTick;
        public double cumulativeHorizontalPathLength;
    }

    [Serializable]
    public sealed class Gate14ReMovementAlgorithmRawV1
    {
        public string algorithmLabel;
        public string productionAlgorithmId;
        public int orderPosition;
        public int unitCount;
        public bool allUnitsArrived;
        public int arrivedCount;
        public int activeAtCapCount;
        public int noPathCount;
        public int budgetExceededCount;
        public int invalidPlanCount;
        public int internalFailureCount;
        public double m1Seconds;
        public int m5CriticalViolationCount;
        public string[] m5CriticalViolationCodes;
        public int structuralEventCount;
        public Gate14ReUnitRawV1[] units;
        public Gate14ReStructuralEventRawV1[] structuralEvents;
        public int m2CommonMaskCount;
        public bool m2CommonMaskSufficient;
        public double m2CommonMaskMeanPathLength;
    }

    [Serializable]
    public sealed class Gate14ReM4AlgorithmRawV1
    {
        public string algorithmLabel;
        public string productionAlgorithmId;
        public int orderPosition;
        public int unitCount;
        public int unitsWithEnabledRenderer;
        public int warmupRenderedFrames;
        public int measuredRenderedFrameIntervals;
        public double[] frameIntervalsSeconds;
        public double medianFrameTimeSeconds;
        public double nearestRankP95FrameTimeSeconds;
        public long simulationTickAtEnd;
        public int structuralEventCount;
        public Gate14ReStructuralEventRawV1[] structuralEvents;
    }

    [Serializable]
    public sealed class Gate14ReStructuralEventRawV1
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
    public sealed class Gate14ReFormalBlockOutputV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string blockId;
        public int blockSequence;
        public string module;
        public string lane;
        public string conditionId;
        public string scenarioId;
        public string scenarioSha256;
        public int unitCount;
        public int blockIndex;
        public int williamsRow;
        public string planSha256;
        public string executableSha256;
        public string assemblyCSharpSha256;
        public string buildReceiptSha256;
        public string authorizationId;
        public int m2CommonMaskMinimum;
        public int[] m2CommonMaskAgentIds;
        public bool m2CommonMaskSufficient;
        public Gate14ReMovementAlgorithmRawV1[] movement;
        public Gate14ReM4AlgorithmRawV1[] m4;
        public bool completeFourAlgorithmBlock;
        public bool formalObservationProduced;
        public bool formalPhaseA;
    }

    [Serializable]
    public sealed class Gate14ReValidationMarkerV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string lane;
        public int unitCount;
        public int algorithmsStructurallyInitialized;
        public int structuralEventCount;
        public bool gridPlannerVisualRevisionMatch;
        public bool formalObservationProduced;
        public bool m1ThroughM5OutputProduced;
        public bool formalPhaseAStarted;
    }

    [Serializable]
    public sealed class Gate14ReFormalFailureV1
    {
        public string schema;
        public string studyId;
        public string status;
        public string blockId;
        public string exceptionType;
        public string message;
        public bool formalObservationProduced;
        public bool partialBlockAdmissible;
        public bool formalPhaseAStarted;
    }
}
