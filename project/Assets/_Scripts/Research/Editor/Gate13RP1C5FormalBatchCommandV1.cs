using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Gate 13R P1-C5 independent confirmatory-study entry point. It is mechanically
    /// derived from the validated PR2 command while using a distinct design identity,
    /// two-algorithm cohort, command-line namespace, and receipt-gated raw lineage.
    /// </summary>
    public static class Gate13RP1C5FormalBatchCommandV1
    {
        private const string DesignId = "gate13r-p1c5-independent-confirmatory-study-v1";
        private const string MemoryGatePolicyId = "gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1";
        private const string BlockManagedLimitFormulaId = "after-forced-cleanup-block-delta-256mib-v1";
        private const string NativeTelemetrySourceId = "windows-psapi-getprocessmemoryinfo-process_memory_counters_ex-v1";
        private const long SampleManagedAlertThresholdBytes = 134217728L;
        private const long SampleManagedEmergencyStopBytes = 268435456L;
        private const long TwoSampleBlockManagedGrowthLimitBytes = 268435456L;
        private const long TierLe128NativeAdvisoryBytes = 536870912L;
        private const long TierLe128NativeHardBytes = 671088640L;
        private const long TierEq256NativeAdvisoryBytes = 671088640L;
        private const long TierEq256NativeHardBytes = 805306368L;
        private const long HostAbsoluteNativeEmergencyBytes = 4294967296L;
        private const long HostRelativeNativeGrowthEmergencyBytes = 2147483648L;
        private const long HostAvailablePhysicalMemoryFloorBytes = 8589934592L;
        private const long ProbeAbsoluteToleranceBytes = 67108864L;
        private const double ProbeRelativeTolerance = 0.25d;
        private const int ProbeTimeoutSeconds = 60;
        private const double ProbeCreationTimeToleranceSeconds = 2d;
        private static readonly UTF8Encoding Utf8WithoutBom = new UTF8Encoding(false);
        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", RegexOptions.CultureInvariant);
        private static readonly Regex AtomicTemporaryLeaf = new Regex("^\\.g13tmp-[0-9a-f]{32}$", RegexOptions.CultureInvariant);
        private const string AtomicTemporaryPrefix = ".g13tmp-";
        private const int AtomicTemporaryLeafLength = 40;
        private static string AtomicPersistenceAllowedRoot;
        private static string LastAtomicTemporaryPathForSelfTest;

        private enum AtomicFaultInjection
        {
            None,
            BeforeWrite,
            BeforeCommit
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_MEMORY_COUNTERS_EX
        {
            public uint cb;
            public uint PageFaultCount;
            public UIntPtr PeakWorkingSetSize;
            public UIntPtr WorkingSetSize;
            public UIntPtr QuotaPeakPagedPoolUsage;
            public UIntPtr QuotaPagedPoolUsage;
            public UIntPtr QuotaPeakNonPagedPoolUsage;
            public UIntPtr QuotaNonPagedPoolUsage;
            public UIntPtr PagefileUsage;
            public UIntPtr PeakPagefileUsage;
            public UIntPtr PrivateUsage;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }

        [DllImport("psapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessMemoryInfo(
            IntPtr processHandle,
            out PROCESS_MEMORY_COUNTERS_EX counters,
            uint size);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);

        [Serializable]
        private sealed class BlockPlan
        {
            public int schemaVersion;
            public string planId;
            public string designId;
            public string blockId;
            public string campaignId;
            public string scenarioId;
            public string scenarioRelativePath;
            public string scenarioSourceSha256;
            public string comparisonCohortId;
            public int block;
            public int williamsRowIndex;
            public bool formalCampaign;
            public bool validationOnly;
            public string analysisRole;
            public int verificationInjectedFailurePosition;
            public string formalConfigRelativePath;
            public string formalConfigSha256;
            public string specificationRelativePath;
            public string specificationSha256;
            public string testDesignRelativePath;
            public string testDesignSha256;
            public string amendmentRelativePath;
            public string amendmentSha256;
            public string commandRelativePath;
            public string commandSha256;
            public string provenanceRelativePath;
            public string provenanceSha256;
            public string executionReceiptRelativePath;
            public string executionReceiptSha256;
            public string memoryPolicyId;
            public string policyTierId;
            public int gridWidth;
            public int gridHeight;
            public int canonicalMaximumGridDimension;
            public long nativeAdvisoryThresholdBytes;
            public long nativeHardThresholdBytes;
            public long hostAbsoluteNativeEmergencyBytes;
            public long hostRelativeNativeGrowthEmergencyBytes;
            public long hostAvailablePhysicalMemoryFloorBytes;
            public string memoryPolicyRegistryRelativePath;
            public string memoryPolicyRegistrySha256;
            public string scenarioPolicyMappingRelativePath;
            public string scenarioPolicyMappingSha256;
            public string schedulePolicyOverlayRelativePath;
            public string schedulePolicyOverlaySha256;
            public int validationInjectedNativeHardPosition;
            public int validationInjectedTelemetryFailurePosition;
            public int validationInjectedPersistenceFailurePosition;
            public BlockEntry[] entries = new BlockEntry[0];
        }

        [Serializable]
        private sealed class BlockEntry
        {
            public int position;
            public string algorithmId;
            public string predecessorAlgorithmId;
            public string runId;
            public string directory;
        }

        [Serializable]
        private sealed class ScenarioDimensionIdentity
        {
            public string scenarioId;
            public int gridWidth;
            public int gridHeight;
        }

        [Serializable]
        private sealed class ProcessTelemetry
        {
            public int schemaVersion = 2;
            public string sourceId = NativeTelemetrySourceId;
            public string capturedAtUtc;
            public int processId;
            public string processStartTimeUtc;
            public double processAgeMilliseconds;
            public long workingSetBytes;
            public long privateMemoryBytes;
            public long managedMemoryBytes;
            public long availablePhysicalMemoryBytes;
            public int gcCollectionCount0;
            public int gcCollectionCount1;
            public int gcCollectionCount2;
        }

        [Serializable]
        private sealed class ProcessReuseSampleManifest
        {
            public int schemaVersion = 6;
            public string executionDesignId = DesignId;
            public string runId;
            public string algorithmId;
            public int fairnessSchemaVersion;
            public string fairnessProtocolId;
            public string fairnessProtocolRelativePath;
            public string fairnessProtocolSha256;
            public string algorithmSpecificationId;
            public string algorithmSpecificationRelativePath;
            public string algorithmSpecificationSha256;
            public string algorithmImplementationRelativePath;
            public string algorithmImplementationSha256;
            public string workloadSpecificationId;
            public string workloadSpecificationRelativePath;
            public string workloadSpecificationSha256;
            public string goalCohortId;
            public string comparisonCohortId;
            public int distinctGoalCount;
            public int plannerInstanceCount;
            public int persistentStateInstanceCount;
            public int sharedFieldInstanceCount;
            public string plannerStateModelId;
            public string processedWorkUnit;
            public string nativeMetricsSemanticsId;
            public bool dynamicCostIncludesAllRepairsAndPostEventPlans;
            public string scenarioSourcePath;
            public string scenarioSourceSha256;
            public string scenarioFingerprintSha256;
            public string canonicalScenarioFile;
            public string canonicalScenarioSha256;
            public string operationsJsonlFile;
            public string operationsJsonlSha256;
            public string workloadResultFile;
            public string workloadResultSha256;
            public string unityVersion;
            public string runtimePlatform;
            public string startedAtUtc;
            public string completedAtUtc;
            public long enqueuedLogRecords;
            public long writtenLogRecords;
            public int planOperationCount;
            public int repairOperationCount;
            public string blockId;
            public int block;
            public int position;
            public int cohortSize;
            public string predecessorAlgorithmId;
            public string blockPlanSha256;
            public string processReuseSpecificationSha256;
            public string processReuseTestDesignSha256;
            public string processReuseAmendmentSha256;
            public string processReuseCommandSha256;
            public string executionReceiptSha256;
            public string memoryGatePolicyId;
            public string policyTierId;
            public int canonicalMaximumGridDimension;
            public long nativeAdvisoryThresholdBytes;
            public long nativeHardThresholdBytes;
            public long maximumSampleRetainedManagedGrowthBytes;
            public long sampleManagedAlertThresholdBytes;
            public long sampleManagedEmergencyStopBytes;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
            public bool sampleMemoryAlert128MiB;
            public bool sampleEmergencyStopPassed;
            public bool nativeAdvisoryCrossed;
            public bool nativeHardCrossed;
            public bool hostEmergencyCrossed;
            public string memoryAttributionScope;
            public bool forcedGcBeforeCompleted;
            public bool forcedGcAfterCompleted;
            public bool sampleStateCreatedFresh;
            public bool heavySampleReferencesReturned;
            public bool plannerResetCompleted;
            public bool loggerDisposed;
            public bool formalCampaign;
            public ProcessTelemetry telemetryBeforeSample;
            public ProcessTelemetry telemetryRawAfterWorkload;
            public ProcessTelemetry telemetryAfterCleanup;
            public long sampleRetainedManagedGrowthBytes;
            public bool retainedManagedGrowthWithinLimit;
            public bool completed;
        }

        [Serializable]
        private sealed class BlockChildRecord
        {
            public int position;
            public string algorithmId;
            public string predecessorAlgorithmId;
            public string runId;
            public string outputRelativePath;
            public string manifestRelativePath;
            public string manifestSha256;
            public string summaryRelativePath;
            public string summarySha256;
            public string workloadResultRelativePath;
            public string workloadResultSha256;
            public int processId;
            public double processAgeBeforeMilliseconds;
            public double processAgeRawAfterMilliseconds;
            public double processAgeAfterCleanupMilliseconds;
            public long workingSetBeforeBytes;
            public long workingSetRawAfterBytes;
            public long workingSetAfterCleanupBytes;
            public long privateMemoryBeforeBytes;
            public long privateMemoryRawAfterBytes;
            public long privateMemoryAfterCleanupBytes;
            public long managedMemoryBeforeBytes;
            public long managedMemoryRawAfterBytes;
            public long managedMemoryAfterCleanupBytes;
            public long availablePhysicalMemoryBeforeBytes;
            public long availablePhysicalMemoryRawAfterBytes;
            public long availablePhysicalMemoryAfterCleanupBytes;
            public long sampleRetainedManagedGrowthBytes;
            public long nativeResidencyMetricBytes;
            public bool nativeAdvisoryCrossed;
            public bool nativeHardCrossed;
            public bool hostEmergencyCrossed;
            public string memoryAttributionScope;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
            public bool sampleMemoryAlert128MiB;
            public bool sampleEmergencyStopPassed;
            public int gcCollectionDelta0;
            public int gcCollectionDelta1;
            public int gcCollectionDelta2;
            public double totalPlannerElapsedMilliseconds;
            public double dynamicHandlingMillisecondsPerScheduledEvent;
            public bool formalCampaign;
            public bool completed;
        }

        [Serializable]
        private sealed class ProcessReuseSampleSummary
        {
            public int schemaVersion = 3;
            public string summaryKind = "gate13r-p1c5-independent-formal-sample-summary-v1";
            public string executionDesignId = DesignId;
            public string runId;
            public string blockId;
            public int block;
            public int position;
            public string algorithmId;
            public string predecessorAlgorithmId;
            public int processId;
            public string processStartTimeUtc;
            public string workloadResultRelativePath;
            public string workloadResultSha256;
            public string manifestRelativePath;
            public string manifestSha256;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
            public bool sampleMemoryAlert128MiB;
            public string completedAtUtc;
            public bool formalCampaign;
            public bool completed;
        }

        [Serializable]
        private sealed class BlockManifest
        {
            public int schemaVersion = 5;
            public string manifestKind = "gate13r-p1c5-independent-formal-block-manifest-v1";
            public string executionDesignId = DesignId;
            public string blockId;
            public string campaignId;
            public string comparisonCohortId;
            public string scenarioRelativePath;
            public string scenarioSourceSha256;
            public string blockPlanSha256;
            public int block;
            public int processId;
            public string processStartTimeUtc;
            public string startedAtUtc;
            public string completedAtUtc;
            public int expectedSampleCount;
            public int completedSampleCount;
            public bool oneBlockPerUnityProcess;
            public bool oneSamplePerAlgorithmPerProcess;
            public bool allSamplesShareProcessId;
            public bool orderMatchesBlockPlan;
            public long blockRetainedManagedGrowthBytes;
            public long blockWorkingSetGrowthBytes;
            public long blockPrivateMemoryGrowthBytes;
            public long nativeResidencyMetricBytes;
            public string memoryGatePolicyId;
            public string policyTierId;
            public int canonicalMaximumGridDimension;
            public string blockManagedLimitFormulaId;
            public long maximumSampleRetainedManagedGrowthBytes;
            public long sampleManagedAlertThresholdBytes;
            public long sampleManagedEmergencyStopBytes;
            public long maximumManagedGrowthBytes;
            public long nativeAdvisoryThresholdBytes;
            public long nativeHardThresholdBytes;
            public long hostAbsoluteNativeEmergencyBytes;
            public long hostRelativeNativeGrowthEmergencyBytes;
            public long hostAvailablePhysicalMemoryFloorBytes;
            public int memoryAlertSampleCount;
            public bool anySampleMemoryAlert128MiB;
            public int nativeAdvisoryBoundaryCount;
            public int nativeHardBoundaryCount;
            public bool nativeAdvisoryCrossed;
            public bool nativeHardCrossed;
            public string nativeCrossingAttributionScope;
            public string attributedAlgorithmId;
            public ProcessTelemetry blockBaselineTelemetry;
            public ProcessTelemetry postBlockTelemetry;
            public string postBlockMemoryEvaluationRelativePath;
            public string postBlockMemoryEvaluationSha256;
            public bool hardMemoryRulesPassed;
            public bool validationOnly;
            public bool formalCampaign;
            public BlockChildRecord[] samples = new BlockChildRecord[0];
            public bool completed;
        }

        [Serializable]
        private sealed class BlockCheckpoint
        {
            public int schemaVersion = 3;
            public string checkpointKind = "gate13r-p1c5-independent-formal-block-checkpoint-v1";
            public string blockId;
            public string status;
            public string savedAtUtc;
            public int processId;
            public int expectedSampleCount;
            public int completedSampleCount;
            public int currentPosition;
            public string currentRunId;
            public string error;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
            public bool automaticRetryAuthorized;
            public bool automaticResumeAuthorized;
            public bool formalCampaign;
        }

        [Serializable]
        private sealed class BlockFailure
        {
            public int schemaVersion = 3;
            public string failureKind = "gate13r-p1c5-independent-formal-block-failure-v1";
            public string failedAtUtc;
            public string blockId;
            public int processId;
            public int completedSampleCount;
            public int failedPosition;
            public string failedRunId;
            public string exceptionType;
            public string message;
            public string stackTrace;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
            public bool laterPositionsExecuted;
            public bool automaticRetryAttempted;
            public bool automaticResumeAttempted;
            public bool formalCampaign;
        }

        [Serializable]
        private sealed class SampleFailure
        {
            public int schemaVersion = 3;
            public string failedAtUtc;
            public string exceptionType;
            public string message;
            public string stackTrace;
            public string memoryGateEvaluationRelativePath;
            public string memoryGateEvaluationSha256;
            public string memoryGateVerdict;
            public string memoryGateReasonCode;
        }

        private sealed class SampleCoreResult
        {
            public string childDirectory;
            public string resultPath;
            public string manifestPath;
            public string summaryPath;
            public string resultFileName;
            public string manifestFileName;
            public string summaryFileName;
            public ProcessReuseSampleManifest manifest;
            public string scenarioId;
            public double totalPlannerElapsedMilliseconds;
            public double dynamicHandlingMillisecondsPerScheduledEvent;
            public bool workloadCompleted;
        }

        private sealed class MemoryEvaluationReference
        {
            public string relativePath = string.Empty;
            public string sha256 = string.Empty;
            public string verdict = string.Empty;
            public string reasonCode = string.Empty;
        }

        [Serializable]
        private sealed class MemoryGateEvaluation
        {
            public int schemaVersion = 2;
            public string evaluationKind = "gate13r-pr2-mp2-layered-memory-gate-evaluation-v1";
            public string memoryGatePolicyId = MemoryGatePolicyId;
            public string evaluatedAtUtc;
            public string runId;
            public string blockId;
            public string campaignId;
            public string scenarioId;
            public string scenarioRelativePath;
            public string comparisonCohortId;
            public string algorithmId;
            public int block;
            public int position;
            public string predecessorAlgorithmId;
            public int expectedSampleCount;
            public bool finalSampleInBlock;
            public string measurementStage;
            public string policyTierId;
            public int canonicalMaximumGridDimension;
            public string attributionScope = "WHOLE-BLOCK-PROCESS";
            public string attributedAlgorithmId = "";
            public int enforcementObservedAtPosition;
            public string enforcementObservedAlgorithmId;
            public ProcessTelemetry blockBaselineTelemetry;
            public ProcessTelemetry telemetryBeforeSample;
            public ProcessTelemetry telemetryRawAfterWorkload;
            public ProcessTelemetry telemetryAfterCleanup;
            public long sampleRetainedManagedGrowthBytes;
            public long blockRetainedManagedGrowthBytesAtSampleBoundary;
            public long blockWorkingSetGrowthBytesAtSampleBoundary;
            public long blockPrivateMemoryGrowthBytesAtSampleBoundary;
            public long nativeResidencyMetricBytes;
            public long absoluteNativeBytes;
            public long sampleManagedAlertThresholdBytes = SampleManagedAlertThresholdBytes;
            public long sampleManagedEmergencyStopBytes = SampleManagedEmergencyStopBytes;
            public long blockRetainedManagedGrowthHardLimitBytes = TwoSampleBlockManagedGrowthLimitBytes;
            public long nativeAdvisoryThresholdBytes;
            public long nativeHardThresholdBytes;
            public long hostAbsoluteNativeEmergencyBytes = HostAbsoluteNativeEmergencyBytes;
            public long hostRelativeNativeGrowthEmergencyBytes = HostRelativeNativeGrowthEmergencyBytes;
            public long hostAvailablePhysicalMemoryFloorBytes = HostAvailablePhysicalMemoryFloorBytes;
            public bool telemetryValid;
            public bool sampleMemoryAlert128MiB;
            public bool sampleEmergencyStopPassed;
            public bool blockManagedHardLimitPassedAtSampleBoundary;
            public bool nativeAdvisoryCrossed;
            public bool nativeHardCrossed;
            public bool hostEmergencyCrossed;
            public bool rawTransientDiagnosticOnly;
            public bool startNextBlockAllowed;
            public bool stopCurrentBlock;
            public string verdict;
            public string reasonCode;
            public bool formalCampaign;
            public bool completed;
        }

        [Serializable]
        private sealed class MemoryPolicyFixtureResult
        {
            public string id;
            public string stage;
            public string tierId;
            public long sampleGrowthBytes;
            public long blockManagedGrowthBytes;
            public long blockWorkingSetGrowthBytes;
            public long blockPrivateMemoryGrowthBytes;
            public long workingSetBytes;
            public long privateMemoryBytes;
            public long availablePhysicalMemoryBytes;
            public bool finalSampleInBlock;
            public string expectedVerdict;
            public string expectedReasonCode;
            public string actualVerdict;
            public string actualReasonCode;
            public bool passed;
        }

        [Serializable]
        private sealed class MemoryPolicySelfTestSummary
        {
            public int schemaVersion = 2;
            public string summaryKind = "gate13r-pr2-mp2-layered-memory-policy-self-test-v1";
            public string completedAtUtc;
            public int testCount;
            public int passedTestCount;
            public MemoryPolicyFixtureResult[] tests = new MemoryPolicyFixtureResult[0];
            public int telemetryValidationTestCount;
            public int telemetryValidationPassedTestCount;
            public TelemetryValidationFixtureResult[] telemetryValidationTests = new TelemetryValidationFixtureResult[0];
            public bool passed;
        }

        [Serializable]
        private sealed class TelemetryValidationFixtureResult
        {
            public string id;
            public bool expectedPassed;
            public string expectedReasonCode;
            public bool actualPassed;
            public string actualReasonCode;
            public bool passed;
        }

        [Serializable]
        private sealed class PathSafeAtomicPayload
        {
            public int schemaVersion = 1;
            public string id;
            public string value;
        }

        [Serializable]
        private sealed class PathSafeAtomicFixtureResult
        {
            public string id;
            public int finalPathLength;
            public int legacyTemporaryPathLength;
            public int pathSafeTemporaryPathLength;
            public bool expectedLegacySuccess;
            public bool actualLegacySuccess;
            public string legacyExceptionType;
            public bool pathSafeSuccess;
            public string pathSafeExceptionType;
            public string detail;
            public bool passed;
        }

        [Serializable]
        private sealed class PathSafeAtomicSelfTestSummary
        {
            public int schemaVersion = 1;
            public string summaryKind = "gate13r-pr1b-v3-path-safe-atomic-persistence-self-test-v1";
            public string completedAtUtc;
            public string rootCauseReasonCode = "WINDOWS-MONO-MAX-PATH-AT-ATOMIC-TEMP-FILE";
            public int v6FailedTemporaryPathLengthCharacters = 260;
            public int cffSuccessfulTemporaryPathLengthCharacters = 259;
            public int fixedTemporaryLeafLengthCharacters = AtomicTemporaryLeafLength;
            public int testCount;
            public int passedTestCount;
            public PathSafeAtomicFixtureResult[] tests = new PathSafeAtomicFixtureResult[0];
            public int residualOwnedTemporaryFileCount;
            public bool passed;
        }

        [Serializable]
        private sealed class TelemetryProbeReady
        {
            public int schemaVersion = 1;
            public string readyKind = "gate13r-pr1b-v2-native-telemetry-probe-ready-v1";
            public string executionDesignId = DesignId;
            public string writtenAtUtc;
            public string executablePath;
            public string expectedExternalQueryFile = "external-os-query.json";
            public ProcessTelemetry nativeBefore;
        }

        [Serializable]
        private sealed class ExternalOsQuery
        {
            public int schemaVersion;
            public string queryKind;
            public string querySourceId;
            public string queriedAtUtc;
            public int processId;
            public string name;
            public string executablePath;
            public string creationDateUtc;
            public long workingSetBytes;
            public long privateMemoryBytes;
        }

        [Serializable]
        private sealed class TelemetryProbeResult
        {
            public int schemaVersion = 1;
            public string resultKind = "gate13r-pr1b-v2-native-telemetry-probe-result-v1";
            public string executionDesignId = DesignId;
            public string completedAtUtc;
            public string inProcessSourceId = NativeTelemetrySourceId;
            public string externalSourceId;
            public ProcessTelemetry nativeBefore;
            public ExternalOsQuery externalQuery;
            public ProcessTelemetry nativeAfter;
            public long workingSetDistanceToNativeIntervalBytes;
            public long workingSetToleranceBytes;
            public bool workingSetPassed;
            public long privateMemoryDistanceToNativeIntervalBytes;
            public long privateMemoryToleranceBytes;
            public bool privateMemoryPassed;
            public double creationTimeDifferenceSeconds;
            public double handshakeDurationSeconds;
            public bool pidPassed;
            public bool executablePassed;
            public bool timestampOrderPassed;
            public bool creationTimePassed;
            public string error;
            public bool passed;
        }

        public static void ProbeTelemetry()
        {
            string outputDirectory = null;
            TelemetryProbeResult result = new TelemetryProbeResult();
            try
            {
                string[] arguments = Environment.GetCommandLineArgs();
                outputDirectory = Path.GetFullPath(RequiredOption(arguments, "-ddmGate10RTelemetryProbeDirectory"));
                EnsureFreshOutputDirectory(outputDirectory);
                Directory.CreateDirectory(outputDirectory);
                SetAtomicPersistenceAllowedRoot(outputDirectory);
                Process process = Process.GetCurrentProcess();
                string executablePath = Path.GetFullPath(process.MainModule.FileName);
                ProcessTelemetry before = CaptureTelemetry(process);
                result.nativeBefore = before;
                WriteAtomicJson(Path.Combine(outputDirectory, "telemetry-probe-ready.json"), new TelemetryProbeReady
                {
                    writtenAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    executablePath = executablePath,
                    nativeBefore = before
                });

                string externalPath = Path.Combine(outputDirectory, "external-os-query.json");
                Stopwatch wait = Stopwatch.StartNew();
                while (!File.Exists(externalPath) && wait.Elapsed < TimeSpan.FromSeconds(ProbeTimeoutSeconds)) Thread.Sleep(100);
                if (!File.Exists(externalPath)) throw new TimeoutException("Timed out waiting for the independent Win32_Process query.");

                ExternalOsQuery external = JsonUtility.FromJson<ExternalOsQuery>(File.ReadAllText(externalPath, Encoding.UTF8));
                if (external == null) throw new InvalidOperationException("The independent OS query JSON is invalid.");
                ProcessTelemetry after = CaptureTelemetry(process);
                result.externalQuery = external;
                result.nativeAfter = after;
                result.externalSourceId = external.querySourceId;
                result.pidPassed = external.processId == before.processId && after.processId == before.processId;
                result.executablePassed = PathsEqual(executablePath, external.executablePath);

                DateTime beforeUtc = ParseUtc(before.capturedAtUtc, "native before timestamp");
                DateTime externalUtc = ParseUtc(external.queriedAtUtc, "external query timestamp");
                DateTime afterUtc = ParseUtc(after.capturedAtUtc, "native after timestamp");
                DateTime nativeStartUtc = ParseUtc(before.processStartTimeUtc, "native process start timestamp");
                DateTime externalStartUtc = ParseUtc(external.creationDateUtc, "external process creation timestamp");
                result.timestampOrderPassed = beforeUtc < externalUtc && externalUtc < afterUtc;
                result.creationTimeDifferenceSeconds = Math.Abs((externalStartUtc - nativeStartUtc).TotalSeconds);
                result.creationTimePassed = result.creationTimeDifferenceSeconds <= ProbeCreationTimeToleranceSeconds;
                result.handshakeDurationSeconds = (afterUtc - beforeUtc).TotalSeconds;

                result.workingSetDistanceToNativeIntervalBytes = DistanceToClosedInterval(
                    external.workingSetBytes,
                    before.workingSetBytes,
                    after.workingSetBytes);
                result.workingSetToleranceBytes = ProbeTolerance(
                    external.workingSetBytes,
                    before.workingSetBytes,
                    after.workingSetBytes);
                result.workingSetPassed = ValuesPositive(external.workingSetBytes, before.workingSetBytes, after.workingSetBytes)
                    && result.workingSetDistanceToNativeIntervalBytes <= result.workingSetToleranceBytes;

                result.privateMemoryDistanceToNativeIntervalBytes = DistanceToClosedInterval(
                    external.privateMemoryBytes,
                    before.privateMemoryBytes,
                    after.privateMemoryBytes);
                result.privateMemoryToleranceBytes = ProbeTolerance(
                    external.privateMemoryBytes,
                    before.privateMemoryBytes,
                    after.privateMemoryBytes);
                result.privateMemoryPassed = ValuesPositive(external.privateMemoryBytes, before.privateMemoryBytes, after.privateMemoryBytes)
                    && result.privateMemoryDistanceToNativeIntervalBytes <= result.privateMemoryToleranceBytes;

                result.passed = result.pidPassed
                    && result.executablePassed
                    && result.timestampOrderPassed
                    && result.creationTimePassed
                    && result.handshakeDurationSeconds >= 0d
                    && result.handshakeDurationSeconds <= ProbeTimeoutSeconds
                    && result.workingSetPassed
                    && result.privateMemoryPassed;
                result.completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                result.error = result.passed ? string.Empty : "One or more frozen telemetry-probe acceptance rules failed.";
                WriteAtomicJsonReplacing(Path.Combine(outputDirectory, "telemetry-probe-result.json"), result);
                if (!result.passed) throw new InvalidOperationException(result.error);
                UnityEngine.Debug.Log("DDM Gate 13R-PR1B v2 native telemetry probe passed.");
            }
            catch (Exception exception)
            {
                if (!string.IsNullOrWhiteSpace(outputDirectory))
                {
                    try
                    {
                        Directory.CreateDirectory(outputDirectory);
                        result.completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                        result.error = exception.ToString();
                        result.passed = false;
                        WriteAtomicJsonReplacing(Path.Combine(outputDirectory, "telemetry-probe-result.json"), result);
                    }
                    catch { }
                }
                UnityEngine.Debug.LogException(exception);
                throw;
            }
        }

        public static void RunMemoryPolicySelfTest()
        {
            string[] arguments = Environment.GetCommandLineArgs();
            string outputDirectory = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RPR2MP2MemoryPolicyTestDirectory"));
            EnsureFreshOutputDirectory(outputDirectory);
            Directory.CreateDirectory(outputDirectory);
            SetAtomicPersistenceAllowedRoot(outputDirectory);

            List<MemoryPolicyFixtureResult> tests = new List<MemoryPolicyFixtureResult>();
            AddMemoryPolicyFixture(tests, "le128-below-advisory", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeAdvisoryBytes - 1L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "PASS");
            AddMemoryPolicyFixture(tests, "le128-exact-advisory", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeAdvisoryBytes, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "PASS");
            AddMemoryPolicyFixture(tests, "le128-above-advisory", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeAdvisoryBytes + 1L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY");
            AddMemoryPolicyFixture(tests, "le128-exact-hard", "post-block-pre-exit", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeHardBytes, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY");
            AddMemoryPolicyFixture(tests, "le128-above-hard", "post-block-pre-exit", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeHardBytes + 1L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-NATIVE-ELIGIBILITY", "HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING");
            AddMemoryPolicyFixture(tests, "eq256-exact-advisory", "after-forced-cleanup", "MP2-NATIVE-EQ256", TierEq256NativeAdvisoryBytes, TierEq256NativeHardBytes, 0L, 0L, 0L, TierEq256NativeAdvisoryBytes, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "PASS");
            AddMemoryPolicyFixture(tests, "eq256-above-advisory", "after-forced-cleanup", "MP2-NATIVE-EQ256", TierEq256NativeAdvisoryBytes, TierEq256NativeHardBytes, 0L, 0L, 0L, TierEq256NativeAdvisoryBytes + 1L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY");
            AddMemoryPolicyFixture(tests, "eq256-exact-hard", "post-block-pre-exit", "MP2-NATIVE-EQ256", TierEq256NativeAdvisoryBytes, TierEq256NativeHardBytes, 0L, 0L, 0L, TierEq256NativeHardBytes, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "NATIVE-RESIDENCY-ADVISORY");
            AddMemoryPolicyFixture(tests, "eq256-above-hard", "post-block-pre-exit", "MP2-NATIVE-EQ256", TierEq256NativeAdvisoryBytes, TierEq256NativeHardBytes, 0L, 0L, 0L, TierEq256NativeHardBytes + 1L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-NATIVE-ELIGIBILITY", "HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING");
            AddMemoryPolicyFixture(tests, "raw-transient-above-tier-hard-diagnostic", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, TierLe128NativeHardBytes + 1L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY");
            AddMemoryPolicyFixture(tests, "managed-exact-128-pass", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, SampleManagedAlertThresholdBytes, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "PASS");
            AddMemoryPolicyFixture(tests, "managed-above-128-alert", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, SampleManagedAlertThresholdBytes + 1L, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "MANAGED-AFTER-CLEANUP-ALERT-128MIB");
            AddMemoryPolicyFixture(tests, "managed-exact-256-alert", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, SampleManagedEmergencyStopBytes, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS-WITH-ADVISORY", "MANAGED-AFTER-CLEANUP-ALERT-128MIB");
            AddMemoryPolicyFixture(tests, "managed-above-256-emergency", "after-forced-cleanup", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, SampleManagedEmergencyStopBytes + 1L, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-MANAGED-EMERGENCY", "HARD-FAIL-SAMPLE-MANAGED-AFTER-CLEANUP-256MIB");
            AddMemoryPolicyFixture(tests, "block-managed-exact-256-pass", "post-block-pre-exit", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, TwoSampleBlockManagedGrowthLimitBytes, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "PASS");
            AddMemoryPolicyFixture(tests, "block-managed-above-256-emergency", "post-block-pre-exit", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, TwoSampleBlockManagedGrowthLimitBytes + 1L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-MANAGED-EMERGENCY", "HARD-FAIL-BLOCK-MANAGED-AFTER-CLEANUP-256MIB");
            AddMemoryPolicyFixture(tests, "host-absolute-exact-4gib-pass", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, 0L, 0L, HostAbsoluteNativeEmergencyBytes, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY");
            AddMemoryPolicyFixture(tests, "host-absolute-above-4gib", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, 0L, 0L, HostAbsoluteNativeEmergencyBytes + 1L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-ABSOLUTE-NATIVE-4GIB");
            AddMemoryPolicyFixture(tests, "host-relative-exact-2gib-pass", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, HostRelativeNativeGrowthEmergencyBytes, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY");
            AddMemoryPolicyFixture(tests, "host-relative-above-2gib", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, HostRelativeNativeGrowthEmergencyBytes + 1L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-RELATIVE-NATIVE-GROWTH-2GIB");
            AddMemoryPolicyFixture(tests, "host-available-exact-8gib-pass", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes, "PASS", "RAW-TRANSIENT-DIAGNOSTIC-ONLY");
            AddMemoryPolicyFixture(tests, "host-available-below-8gib", "raw-after-workload", "MP2-NATIVE-LE128", TierLe128NativeAdvisoryBytes, TierLe128NativeHardBytes, 0L, 0L, 0L, 0L, 1073741824L, 1073741824L, HostAvailablePhysicalMemoryFloorBytes - 1L, "HARD-FAIL-HOST-EMERGENCY", "HARD-FAIL-HOST-AVAILABLE-MEMORY-BELOW-8GIB");

            List<TelemetryValidationFixtureResult> telemetryTests = new List<TelemetryValidationFixtureResult>();
            ProcessTelemetry validBefore = CreateTelemetryFixture(41001, "2026-10-08T00:00:00.0000000Z", "2026-10-08T00:00:01.0000000Z", 1000d, 100L, 200L, 300L, HostAvailablePhysicalMemoryFloorBytes, 1, 2, 3);
            ProcessTelemetry validRawAfter = CreateTelemetryFixture(41001, "2026-10-08T00:00:00.0000000Z", "2026-10-08T00:00:02.0000000Z", 2000d, 110L, 210L, 310L, HostAvailablePhysicalMemoryFloorBytes, 2, 3, 4);
            ProcessTelemetry validAfterCleanup = CreateTelemetryFixture(41001, "2026-10-08T00:00:00.0000000Z", "2026-10-08T00:00:03.0000000Z", 3000d, 105L, 205L, 305L, HostAvailablePhysicalMemoryFloorBytes, 3, 4, 5);
            AddTelemetryValidationFixture(telemetryTests, "valid-sequence", validBefore, validRawAfter, validAfterCleanup, true, "PASS");
            AddTelemetryValidationFixture(telemetryTests, "missing-before", null, validRawAfter, validAfterCleanup, false, "HARD-FAIL-TELEMETRY-MISSING");
            ProcessTelemetry mixedPid = CloneTelemetryFixture(validAfterCleanup); mixedPid.processId = 41002;
            AddTelemetryValidationFixture(telemetryTests, "mixed-pid", validBefore, validRawAfter, mixedPid, false, "HARD-FAIL-TELEMETRY-MIXED-PID");
            ProcessTelemetry mixedStart = CloneTelemetryFixture(validAfterCleanup); mixedStart.processStartTimeUtc = "2026-10-08T00:00:00.5000000Z";
            AddTelemetryValidationFixture(telemetryTests, "mixed-process-start", validBefore, validRawAfter, mixedStart, false, "HARD-FAIL-TELEMETRY-MIXED-PROCESS-START");
            ProcessTelemetry nonFiniteAge = CloneTelemetryFixture(validRawAfter); nonFiniteAge.processAgeMilliseconds = double.NaN;
            AddTelemetryValidationFixture(telemetryTests, "nonfinite-process-age", validBefore, nonFiniteAge, validAfterCleanup, false, "HARD-FAIL-TELEMETRY-NONFINITE-PROCESS-AGE");
            ProcessTelemetry decreasingAge = CloneTelemetryFixture(validAfterCleanup); decreasingAge.processAgeMilliseconds = 1500d;
            AddTelemetryValidationFixture(telemetryTests, "process-age-order", validBefore, validRawAfter, decreasingAge, false, "HARD-FAIL-TELEMETRY-PROCESS-AGE-ORDER");
            ProcessTelemetry nonPositiveWorking = CloneTelemetryFixture(validAfterCleanup); nonPositiveWorking.workingSetBytes = 0L;
            AddTelemetryValidationFixture(telemetryTests, "nonpositive-working-set", validBefore, validRawAfter, nonPositiveWorking, false, "HARD-FAIL-TELEMETRY-WORKING-SET-NONPOSITIVE");
            ProcessTelemetry decreasingGc = CloneTelemetryFixture(validAfterCleanup); decreasingGc.gcCollectionCount2 = 2;
            AddTelemetryValidationFixture(telemetryTests, "gc-count-order", validBefore, validRawAfter, decreasingGc, false, "HARD-FAIL-TELEMETRY-GC-COUNT-ORDER");

            MemoryPolicySelfTestSummary summary = new MemoryPolicySelfTestSummary
            {
                completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                testCount = tests.Count,
                passedTestCount = tests.FindAll(delegate(MemoryPolicyFixtureResult item) { return item.passed; }).Count,
                tests = tests.ToArray(),
                telemetryValidationTestCount = telemetryTests.Count,
                telemetryValidationPassedTestCount = telemetryTests.FindAll(delegate(TelemetryValidationFixtureResult item) { return item.passed; }).Count,
                telemetryValidationTests = telemetryTests.ToArray()
            };
            summary.passed = summary.passedTestCount == summary.testCount
                && summary.telemetryValidationPassedTestCount == summary.telemetryValidationTestCount;
            WriteAtomicJson(Path.Combine(outputDirectory, "memory-policy-self-test.json"), summary);
            if (!summary.passed) throw new InvalidOperationException("One or more Gate 13R-PR2-MP2 memory-policy fixtures failed.");
            UnityEngine.Debug.Log("DDM Gate 13R-PR2-MP2 memory-policy self-test passed.");
        }


        public static void RunPathSafeAtomicSelfTest()
        {
            string[] arguments = Environment.GetCommandLineArgs();
            string outputDirectory = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RPR1BPathSafeTestDirectory"));
            EnsureFreshOutputDirectory(outputDirectory);
            Directory.CreateDirectory(outputDirectory);
            SetAtomicPersistenceAllowedRoot(outputDirectory);

            List<PathSafeAtomicFixtureResult> tests = new List<PathSafeAtomicFixtureResult>();
            tests.Add(RunLegacyBoundaryFixture(outputDirectory, "cff-position-legacy-temp-259", 194, 259, true));
            tests.Add(RunLegacyBoundaryFixture(outputDirectory, "idff-v6-legacy-temp-260", 195, 260, false));
            tests.Add(RunLegacyBoundaryFixture(outputDirectory, "legacy-temp-261", 196, 261, false));
            tests.Add(RunLegacyBoundaryFixture(outputDirectory, "legacy-temp-280", 215, 280, false));

            string ordinaryParent = Path.Combine(outputDirectory, "ordinary");
            Directory.CreateDirectory(ordinaryParent);
            PathSafeAtomicPayload payload = new PathSafeAtomicPayload { id = "path-safe-fixture", value = "stable" };

            string missingTarget = Path.Combine(outputDirectory, "missing-parent", "evidence.json");
            tests.Add(RunExpectedAtomicFailure("missing-parent-rejected", missingTarget, delegate
            {
                WriteAtomicJson(missingTarget, payload);
            }, delegate { return !File.Exists(missingTarget); }));

            string outsideTarget = Path.Combine(Directory.GetParent(outputDirectory).FullName, ".g13-outside-" + Guid.NewGuid().ToString("N") + ".json");
            tests.Add(RunExpectedAtomicFailure("outside-containment-rejected", outsideTarget, delegate
            {
                WriteAtomicJson(outsideTarget, payload);
            }, delegate { return !File.Exists(outsideTarget); }));

            string directoryTarget = Path.Combine(ordinaryParent, "directory-target.json");
            Directory.CreateDirectory(directoryTarget);
            tests.Add(RunExpectedAtomicFailure("directory-final-target-rejected", directoryTarget, delegate
            {
                WriteAtomicJson(directoryTarget, payload);
            }, delegate { return Directory.Exists(directoryTarget); }));

            string reparseTarget = Path.Combine(outputDirectory, "reparse-target");
            string reparseLink = Path.Combine(outputDirectory, "reparse-link");
            Directory.CreateDirectory(reparseTarget);
            CreateOwnedJunction(reparseLink, reparseTarget);
            try
            {
                string reparseFile = Path.Combine(reparseLink, "evidence.json");
                tests.Add(RunExpectedAtomicFailure("reparse-point-rejected", reparseFile, delegate
                {
                    WriteAtomicJson(reparseFile, payload);
                }, delegate { return !File.Exists(Path.Combine(reparseTarget, "evidence.json")); }));
            }
            finally
            {
                RemoveOwnedJunction(reparseLink);
            }

            string collisionLeaf = AtomicTemporaryPrefix + new string('1', 32);
            string collisionPath = Path.Combine(ordinaryParent, collisionLeaf);
            WriteTextCreateNew(collisionPath, "collision-sentinel\n");
            string collisionSha = ComputeFileSha256(collisionPath);
            string collisionTarget = Path.Combine(ordinaryParent, "collision-evidence.json");
            tests.Add(RunExpectedAtomicFailure("temporary-collision-preserved", collisionTarget, delegate
            {
                WriteAtomicJsonCore(collisionTarget, payload, false, collisionLeaf, AtomicFaultInjection.None);
            }, delegate { return File.Exists(collisionPath) && string.Equals(ComputeFileSha256(collisionPath), collisionSha, StringComparison.Ordinal) && !File.Exists(collisionTarget); }));
            File.Delete(collisionPath);

            string writeFaultLeaf = AtomicTemporaryPrefix + new string('2', 32);
            string writeFaultPath = Path.Combine(ordinaryParent, writeFaultLeaf);
            string writeFaultTarget = Path.Combine(ordinaryParent, "write-fault-evidence.json");
            tests.Add(RunExpectedAtomicFailure("injected-write-failure-cleans-owned-temp", writeFaultTarget, delegate
            {
                WriteAtomicJsonCore(writeFaultTarget, payload, false, writeFaultLeaf, AtomicFaultInjection.BeforeWrite);
            }, delegate { return !File.Exists(writeFaultPath) && !File.Exists(writeFaultTarget); }));

            string moveFaultLeaf = AtomicTemporaryPrefix + new string('3', 32);
            string moveFaultPath = Path.Combine(ordinaryParent, moveFaultLeaf);
            string moveFaultTarget = Path.Combine(ordinaryParent, "move-fault-evidence.json");
            tests.Add(RunExpectedAtomicFailure("injected-move-failure-cleans-owned-temp", moveFaultTarget, delegate
            {
                WriteAtomicJsonCore(moveFaultTarget, payload, false, moveFaultLeaf, AtomicFaultInjection.BeforeCommit);
            }, delegate { return !File.Exists(moveFaultPath) && !File.Exists(moveFaultTarget); }));

            string immutableTarget = Path.Combine(ordinaryParent, "immutable-evidence.json");
            WriteAtomicJson(immutableTarget, new PathSafeAtomicPayload { id = "immutable", value = "first" });
            string immutableSha = ComputeFileSha256(immutableTarget);
            tests.Add(RunExpectedAtomicFailure("immutable-evidence-overwrite-rejected", immutableTarget, delegate
            {
                WriteAtomicJson(immutableTarget, new PathSafeAtomicPayload { id = "immutable", value = "second" });
            }, delegate { return string.Equals(ComputeFileSha256(immutableTarget), immutableSha, StringComparison.Ordinal); }));

            string mutableTarget = Path.Combine(ordinaryParent, "mutable-checkpoint.json");
            WriteAtomicJsonReplacing(mutableTarget, new PathSafeAtomicPayload { id = "mutable", value = "first" });
            string mutableFirstSha = ComputeFileSha256(mutableTarget);
            WriteAtomicJsonReplacing(mutableTarget, new PathSafeAtomicPayload { id = "mutable", value = "second" });
            string mutableSecondSha = ComputeFileSha256(mutableTarget);
            bool mutablePassed = File.Exists(mutableTarget) && !string.Equals(mutableFirstSha, mutableSecondSha, StringComparison.Ordinal);
            tests.Add(new PathSafeAtomicFixtureResult
            {
                id = "explicit-mutable-replacement",
                finalPathLength = mutableTarget.Length,
                pathSafeTemporaryPathLength = LastAtomicTemporaryPathForSelfTest == null ? 0 : LastAtomicTemporaryPathForSelfTest.Length,
                pathSafeSuccess = mutablePassed,
                detail = "Only explicitly mutable checkpoint/result targets may replace existing bytes.",
                passed = mutablePassed
            });

            string[] residual = Directory.GetFiles(outputDirectory, AtomicTemporaryPrefix + "*", SearchOption.AllDirectories);
            tests.Add(new PathSafeAtomicFixtureResult
            {
                id = "no-residual-owned-temporaries",
                pathSafeSuccess = residual.Length == 0,
                detail = "residual=" + residual.Length.ToString(CultureInfo.InvariantCulture),
                passed = residual.Length == 0
            });

            PathSafeAtomicSelfTestSummary summary = new PathSafeAtomicSelfTestSummary
            {
                completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                testCount = tests.Count,
                passedTestCount = tests.FindAll(delegate(PathSafeAtomicFixtureResult item) { return item.passed; }).Count,
                tests = tests.ToArray(),
                residualOwnedTemporaryFileCount = residual.Length
            };
            summary.passed = summary.passedTestCount == summary.testCount;
            WriteAtomicJson(Path.Combine(outputDirectory, "path-safe-atomic-self-test.json"), summary);
            if (!summary.passed) throw new InvalidOperationException("One or more Gate 13R-PR1B v3 path-safe atomic fixtures failed.");
            UnityEngine.Debug.Log("DDM Gate 13R-PR1B v3 path-safe atomic self-test passed.");
        }

        private static PathSafeAtomicFixtureResult RunLegacyBoundaryFixture(string root, string id, int parentLength, int expectedLegacyTemporaryLength, bool expectedLegacySuccess)
        {
            string parent = CreateDirectoryAtExactLength(root, parentLength, id);
            string finalPath = Path.Combine(parent, "memory-gate-evaluation.json");
            string legacyTemporary = finalPath + ".tmp-" + new string('a', 32);
            PathSafeAtomicPayload payload = new PathSafeAtomicPayload { id = id, value = "boundary" };
            bool legacySuccess = false;
            string legacyException = string.Empty;
            try
            {
                WriteJson(legacyTemporary, payload);
                legacySuccess = true;
            }
            catch (Exception exception)
            {
                legacyException = exception.GetType().FullName;
            }
            finally
            {
                if (File.Exists(legacyTemporary)) File.Delete(legacyTemporary);
            }

            bool pathSafeSuccess = false;
            string pathSafeException = string.Empty;
            int pathSafeTemporaryLength = 0;
            string observedTemporaryPath = string.Empty;
            try
            {
                WriteAtomicJson(finalPath, payload);
                observedTemporaryPath = LastAtomicTemporaryPathForSelfTest ?? string.Empty;
                pathSafeSuccess = File.Exists(finalPath) && JsonHasStableUtf8Lf(finalPath);
                pathSafeTemporaryLength = observedTemporaryPath.Length;
            }
            catch (Exception exception)
            {
                pathSafeException = exception.GetType().FullName;
            }
            finally
            {
                if (File.Exists(finalPath)) File.Delete(finalPath);
            }

            bool legacyExpectationPassed = expectedLegacySuccess
                ? legacySuccess
                : !legacySuccess && string.Equals(legacyException, typeof(DirectoryNotFoundException).FullName, StringComparison.Ordinal);
            bool passed = legacyTemporary.Length == expectedLegacyTemporaryLength
                && legacyExpectationPassed
                && pathSafeSuccess
                && pathSafeTemporaryLength < 260
                && !string.IsNullOrEmpty(observedTemporaryPath)
                && string.Equals(Path.GetDirectoryName(observedTemporaryPath), parent, StringComparison.OrdinalIgnoreCase)
                && AtomicTemporaryLeaf.IsMatch(Path.GetFileName(observedTemporaryPath));

            return new PathSafeAtomicFixtureResult
            {
                id = id,
                finalPathLength = finalPath.Length,
                legacyTemporaryPathLength = legacyTemporary.Length,
                pathSafeTemporaryPathLength = pathSafeTemporaryLength,
                expectedLegacySuccess = expectedLegacySuccess,
                actualLegacySuccess = legacySuccess,
                legacyExceptionType = legacyException,
                pathSafeSuccess = pathSafeSuccess,
                pathSafeExceptionType = pathSafeException,
                detail = "parent=" + parent.Length.ToString(CultureInfo.InvariantCulture) + ";fixedLeaf=" + AtomicTemporaryLeafLength.ToString(CultureInfo.InvariantCulture),
                passed = passed
            };
        }

        private static PathSafeAtomicFixtureResult RunExpectedAtomicFailure(string id, string finalPath, Action action, Func<bool> postcondition)
        {
            bool failed = false;
            string exceptionType = string.Empty;
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failed = true;
                exceptionType = exception.GetType().FullName;
            }
            bool passed = failed && postcondition();
            return new PathSafeAtomicFixtureResult
            {
                id = id,
                finalPathLength = finalPath.Length,
                pathSafeTemporaryPathLength = LastAtomicTemporaryPathForSelfTest == null ? 0 : LastAtomicTemporaryPathForSelfTest.Length,
                pathSafeSuccess = false,
                pathSafeExceptionType = exceptionType,
                detail = "Expected fail-closed rejection with postcondition preservation.",
                passed = passed
            };
        }

        private static string CreateDirectoryAtExactLength(string root, int targetLength, string label)
        {
            int leafLength = targetLength - root.Length - 1;
            string prefix = "p" + targetLength.ToString(CultureInfo.InvariantCulture) + "-";
            if (leafLength < prefix.Length) throw new InvalidOperationException("Verification root is too long for boundary fixture " + label + ".");
            string path = Path.Combine(root, prefix + new string('x', leafLength - prefix.Length));
            if (path.Length != targetLength) throw new InvalidOperationException("Boundary directory length construction failed.");
            Directory.CreateDirectory(path);
            return path;
        }

        private static bool JsonHasStableUtf8Lf(string path)
        {
            byte[] bytes = File.ReadAllBytes(path);
            if (bytes.Length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) return false;
            string text = Utf8WithoutBom.GetString(bytes);
            return text.IndexOf("\r", StringComparison.Ordinal) < 0 && text.EndsWith("\n", StringComparison.Ordinal);
        }

        private static void CreateOwnedJunction(string linkPath, string targetPath)
        {
            string command = "/d /c mklink /J \"" + linkPath + "\" \"" + targetPath + "\"";
            ProcessStartInfo start = new ProcessStartInfo(Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe", command);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            using (Process process = Process.Start(start))
            {
                string stdout = process.StandardOutput.ReadToEnd();
                string stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0 || !Directory.Exists(linkPath)) throw new IOException("Could not create owned reparse fixture: " + stdout + " " + stderr);
            }
        }

        private static void RemoveOwnedJunction(string linkPath)
        {
            if (!Directory.Exists(linkPath)) return;
            string command = "/d /c rmdir \"" + linkPath + "\"";
            ProcessStartInfo start = new ProcessStartInfo(Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe", command);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            using (Process process = Process.Start(start))
            {
                process.WaitForExit();
                if (process.ExitCode != 0 || Directory.Exists(linkPath)) throw new IOException("Could not remove owned reparse fixture.");
            }
        }

        private static void AddMemoryPolicyFixture(
            List<MemoryPolicyFixtureResult> tests,
            string id,
            string stage,
            string tierId,
            long nativeAdvisoryBytes,
            long nativeHardBytes,
            long sampleGrowthBytes,
            long blockManagedGrowthBytes,
            long blockWorkingSetGrowthBytes,
            long blockPrivateMemoryGrowthBytes,
            long workingSetBytes,
            long privateMemoryBytes,
            long availablePhysicalMemoryBytes,
            string expectedVerdict,
            string expectedReasonCode)
        {
            ProcessTelemetry fixturePoint = new ProcessTelemetry
            {
                workingSetBytes = workingSetBytes,
                privateMemoryBytes = privateMemoryBytes,
                managedMemoryBytes = 1L,
                availablePhysicalMemoryBytes = availablePhysicalMemoryBytes
            };
            MemoryGateEvaluation evaluation = new MemoryGateEvaluation
            {
                telemetryValid = true,
                measurementStage = stage,
                policyTierId = tierId,
                nativeAdvisoryThresholdBytes = nativeAdvisoryBytes,
                nativeHardThresholdBytes = nativeHardBytes,
                sampleRetainedManagedGrowthBytes = sampleGrowthBytes,
                blockRetainedManagedGrowthBytesAtSampleBoundary = blockManagedGrowthBytes,
                blockWorkingSetGrowthBytesAtSampleBoundary = blockWorkingSetGrowthBytes,
                blockPrivateMemoryGrowthBytesAtSampleBoundary = blockPrivateMemoryGrowthBytes,
                nativeResidencyMetricBytes = Math.Max(blockWorkingSetGrowthBytes, blockPrivateMemoryGrowthBytes),
                absoluteNativeBytes = Math.Max(workingSetBytes, privateMemoryBytes),
                telemetryRawAfterWorkload = fixturePoint,
                telemetryAfterCleanup = fixturePoint,
                finalSampleInBlock = string.Equals(stage, "post-block-pre-exit", StringComparison.Ordinal)
            };
            ApplyMemoryPolicy(evaluation);
            tests.Add(new MemoryPolicyFixtureResult
            {
                id = id,
                stage = stage,
                tierId = tierId,
                sampleGrowthBytes = sampleGrowthBytes,
                blockManagedGrowthBytes = blockManagedGrowthBytes,
                blockWorkingSetGrowthBytes = blockWorkingSetGrowthBytes,
                blockPrivateMemoryGrowthBytes = blockPrivateMemoryGrowthBytes,
                workingSetBytes = workingSetBytes,
                privateMemoryBytes = privateMemoryBytes,
                availablePhysicalMemoryBytes = availablePhysicalMemoryBytes,
                finalSampleInBlock = evaluation.finalSampleInBlock,
                expectedVerdict = expectedVerdict,
                expectedReasonCode = expectedReasonCode,
                actualVerdict = evaluation.verdict,
                actualReasonCode = evaluation.reasonCode,
                passed = string.Equals(evaluation.verdict, expectedVerdict, StringComparison.Ordinal)
                    && string.Equals(evaluation.reasonCode, expectedReasonCode, StringComparison.Ordinal)
            });
        }

        private static ProcessTelemetry CreateTelemetryFixture(
            int processId,
            string processStartTimeUtc,
            string capturedAtUtc,
            double processAgeMilliseconds,
            long workingSetBytes,
            long privateMemoryBytes,
            long managedMemoryBytes,
            long availablePhysicalMemoryBytes,
            int gc0,
            int gc1,
            int gc2)
        {
            return new ProcessTelemetry
            {
                capturedAtUtc = capturedAtUtc,
                processId = processId,
                processStartTimeUtc = processStartTimeUtc,
                processAgeMilliseconds = processAgeMilliseconds,
                workingSetBytes = workingSetBytes,
                privateMemoryBytes = privateMemoryBytes,
                managedMemoryBytes = managedMemoryBytes,
                availablePhysicalMemoryBytes = availablePhysicalMemoryBytes,
                gcCollectionCount0 = gc0,
                gcCollectionCount1 = gc1,
                gcCollectionCount2 = gc2
            };
        }

        private static ProcessTelemetry CloneTelemetryFixture(ProcessTelemetry source)
        {
            return CreateTelemetryFixture(
                source.processId,
                source.processStartTimeUtc,
                source.capturedAtUtc,
                source.processAgeMilliseconds,
                source.workingSetBytes,
                source.privateMemoryBytes,
                source.managedMemoryBytes,
                source.availablePhysicalMemoryBytes,
                source.gcCollectionCount0,
                source.gcCollectionCount1,
                source.gcCollectionCount2);
        }

        private static void AddTelemetryValidationFixture(
            List<TelemetryValidationFixtureResult> tests,
            string id,
            ProcessTelemetry before,
            ProcessTelemetry rawAfter,
            ProcessTelemetry afterCleanup,
            bool expectedPassed,
            string expectedReasonCode)
        {
            string reasonCode;
            bool actualPassed = TryValidateTelemetrySequence(before, rawAfter, afterCleanup, out reasonCode);
            tests.Add(new TelemetryValidationFixtureResult
            {
                id = id,
                expectedPassed = expectedPassed,
                expectedReasonCode = expectedReasonCode,
                actualPassed = actualPassed,
                actualReasonCode = reasonCode,
                passed = actualPassed == expectedPassed && string.Equals(reasonCode, expectedReasonCode, StringComparison.Ordinal)
            });
        }

        public static void Run()
        {
            string outputRoot = null;
            BlockPlan plan = null;
            List<BlockChildRecord> completed = new List<BlockChildRecord>();
            int currentPosition = 0;
            string currentRunId = null;
            MemoryEvaluationReference currentMemoryEvaluation = new MemoryEvaluationReference();
            MemoryEvaluationReference firstNativeHardMemoryEvaluation = null;
            ProcessTelemetry blockBaselineTelemetry = null;
            DateTime blockStartedUtc = DateTime.UtcNow;
            Process process = Process.GetCurrentProcess();
            int processId = process.Id;
            try
            {
                string[] arguments = Environment.GetCommandLineArgs();
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string planPath = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RP1C5BlockPlanPath"));
                string expectedPlanSha256 = RequiredOption(arguments, "-ddmGate13RP1C5BlockPlanSha256");
                outputRoot = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RP1C5OutputDirectory"));
                if (!File.Exists(planPath)) throw new FileNotFoundException("Gate 13R P1-C5 formal block plan is missing.", planPath);
                string actualPlanSha256 = ComputeFileSha256(planPath);
                if (!string.Equals(actualPlanSha256, expectedPlanSha256, StringComparison.Ordinal)) throw new InvalidOperationException("Block-plan SHA-256 mismatch.");
                plan = JsonUtility.FromJson<BlockPlan>(File.ReadAllText(planPath, Encoding.UTF8));
                ValidatePlan(plan, projectRoot, outputRoot);
                EnsureFreshOutputDirectory(outputRoot);
                Directory.CreateDirectory(outputRoot);
                SetAtomicPersistenceAllowedRoot(outputRoot);
                WriteCheckpoint(outputRoot, plan, processId, "block-started", completed.Count, 0, null, null, null);

                string scenarioPath = Path.GetFullPath(Path.Combine(projectRoot, plan.scenarioRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                if (!File.Exists(scenarioPath)) throw new FileNotFoundException("Scenario file is missing.", scenarioPath);
                if (!string.Equals(ComputeFileSha256(scenarioPath), plan.scenarioSourceSha256, StringComparison.Ordinal)) throw new InvalidOperationException("Scenario source SHA-256 mismatch.");

                ForceCollectionBoundary();
                blockBaselineTelemetry = CaptureTelemetry(process);
                WriteAtomicJson(Path.Combine(outputRoot, "block-baseline-telemetry.json"), blockBaselineTelemetry);
                MemoryGateEvaluation baselineEvaluation = CreateMemoryGateEvaluation(
                    plan,
                    plan.entries[0],
                    plan.scenarioId,
                    blockBaselineTelemetry,
                    blockBaselineTelemetry,
                    blockBaselineTelemetry,
                    blockBaselineTelemetry,
                    false,
                    "raw-after-workload");
                WriteAtomicJson(Path.Combine(outputRoot, "block-baseline-memory-gate-evaluation.json"), baselineEvaluation);
                if (baselineEvaluation.stopCurrentBlock) throw new InvalidOperationException("Block baseline host eligibility failed after durable evaluation: " + baselineEvaluation.reasonCode + ".");

                for (int index = 0; index < plan.entries.Length; index++)
                {
                    BlockEntry entry = plan.entries[index];
                    currentPosition = entry.position;
                    currentRunId = entry.runId;
                    currentMemoryEvaluation = new MemoryEvaluationReference();
                    WriteCheckpoint(outputRoot, plan, processId, "running-sample", completed.Count, currentPosition, currentRunId, null, currentMemoryEvaluation);
                    if (plan.verificationInjectedFailurePosition == currentPosition) throw new InvalidOperationException("Injected Gate 10R verification failure at position " + currentPosition.ToString(CultureInfo.InvariantCulture) + ".");
                    bool finalSampleInBlock = index == plan.entries.Length - 1;
                    BlockChildRecord child = RunSample(
                        projectRoot,
                        outputRoot,
                        scenarioPath,
                        plan,
                        entry,
                        actualPlanSha256,
                        process,
                        blockBaselineTelemetry,
                        finalSampleInBlock,
                        currentMemoryEvaluation);
                    completed.Add(child);
                    if (child.nativeHardCrossed && firstNativeHardMemoryEvaluation == null)
                    {
                        firstNativeHardMemoryEvaluation = new MemoryEvaluationReference
                        {
                            relativePath = currentMemoryEvaluation.relativePath,
                            sha256 = currentMemoryEvaluation.sha256,
                            verdict = currentMemoryEvaluation.verdict,
                            reasonCode = currentMemoryEvaluation.reasonCode
                        };
                    }
                    WriteCheckpoint(outputRoot, plan, processId, "sample-completed", completed.Count, currentPosition, currentRunId, null, currentMemoryEvaluation);
                }

                ValidateCompletedBlock(plan, completed, processId);
                ForceCollectionBoundary();
                ProcessTelemetry postBlockTelemetry = CaptureTelemetry(process);
                BlockEntry finalEntry = plan.entries[plan.entries.Length - 1];
                MemoryGateEvaluation postBlockEvaluation = CreateMemoryGateEvaluation(
                    plan,
                    finalEntry,
                    plan.scenarioId,
                    blockBaselineTelemetry,
                    postBlockTelemetry,
                    postBlockTelemetry,
                    blockBaselineTelemetry,
                    true,
                    "post-block-pre-exit");
                const string postBlockEvaluationFileName = "post-block-memory-gate-evaluation.json";
                string postBlockEvaluationPath = Path.Combine(outputRoot, postBlockEvaluationFileName);
                WriteAtomicJson(postBlockEvaluationPath, postBlockEvaluation);
                string postBlockEvaluationSha256 = ComputeFileSha256(postBlockEvaluationPath);

                long managedGrowth = checked(postBlockTelemetry.managedMemoryBytes - blockBaselineTelemetry.managedMemoryBytes);
                long workingSetGrowth = checked(postBlockTelemetry.workingSetBytes - blockBaselineTelemetry.workingSetBytes);
                long privateMemoryGrowth = checked(postBlockTelemetry.privateMemoryBytes - blockBaselineTelemetry.privateMemoryBytes);
                long blockManagedGrowthLimitBytes = TwoSampleBlockManagedGrowthLimitBytes;
                int nativeAdvisoryBoundaryCount = postBlockEvaluation.nativeAdvisoryCrossed ? 1 : 0;
                int nativeHardBoundaryCount = postBlockEvaluation.nativeHardCrossed ? 1 : 0;
                long maximumNativeResidencyMetricBytes = postBlockEvaluation.nativeResidencyMetricBytes;
                for (int childIndex = 0; childIndex < completed.Count; childIndex++)
                {
                    if (completed[childIndex].nativeAdvisoryCrossed) nativeAdvisoryBoundaryCount++;
                    if (completed[childIndex].nativeHardCrossed) nativeHardBoundaryCount++;
                    maximumNativeResidencyMetricBytes = Math.Max(maximumNativeResidencyMetricBytes, completed[childIndex].nativeResidencyMetricBytes);
                }
                bool hardMemoryRulesPassed = nativeHardBoundaryCount == 0
                    && !postBlockEvaluation.hostEmergencyCrossed
                    && postBlockEvaluation.sampleEmergencyStopPassed
                    && postBlockEvaluation.blockManagedHardLimitPassedAtSampleBoundary;

                BlockManifest blockManifest = new BlockManifest
                {
                    blockId = plan.blockId,
                    campaignId = plan.campaignId,
                    comparisonCohortId = plan.comparisonCohortId,
                    scenarioRelativePath = plan.scenarioRelativePath,
                    scenarioSourceSha256 = plan.scenarioSourceSha256,
                    blockPlanSha256 = actualPlanSha256,
                    block = plan.block,
                    processId = processId,
                    processStartTimeUtc = process.StartTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
                    startedAtUtc = blockStartedUtc.ToString("O", CultureInfo.InvariantCulture),
                    completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    expectedSampleCount = plan.entries.Length,
                    completedSampleCount = completed.Count,
                    oneBlockPerUnityProcess = true,
                    oneSamplePerAlgorithmPerProcess = true,
                    allSamplesShareProcessId = true,
                    orderMatchesBlockPlan = true,
                    blockRetainedManagedGrowthBytes = managedGrowth,
                    blockWorkingSetGrowthBytes = workingSetGrowth,
                    blockPrivateMemoryGrowthBytes = privateMemoryGrowth,
                    nativeResidencyMetricBytes = maximumNativeResidencyMetricBytes,
                    memoryGatePolicyId = MemoryGatePolicyId,
                    policyTierId = plan.policyTierId,
                    canonicalMaximumGridDimension = plan.canonicalMaximumGridDimension,
                    blockManagedLimitFormulaId = BlockManagedLimitFormulaId,
                    maximumSampleRetainedManagedGrowthBytes = SampleManagedEmergencyStopBytes,
                    sampleManagedAlertThresholdBytes = SampleManagedAlertThresholdBytes,
                    sampleManagedEmergencyStopBytes = SampleManagedEmergencyStopBytes,
                    maximumManagedGrowthBytes = blockManagedGrowthLimitBytes,
                    nativeAdvisoryThresholdBytes = plan.nativeAdvisoryThresholdBytes,
                    nativeHardThresholdBytes = plan.nativeHardThresholdBytes,
                    hostAbsoluteNativeEmergencyBytes = plan.hostAbsoluteNativeEmergencyBytes,
                    hostRelativeNativeGrowthEmergencyBytes = plan.hostRelativeNativeGrowthEmergencyBytes,
                    hostAvailablePhysicalMemoryFloorBytes = plan.hostAvailablePhysicalMemoryFloorBytes,
                    memoryAlertSampleCount = completed.FindAll(delegate(BlockChildRecord child) { return child.sampleMemoryAlert128MiB; }).Count,
                    anySampleMemoryAlert128MiB = completed.Exists(delegate(BlockChildRecord child) { return child.sampleMemoryAlert128MiB; }),
                    nativeAdvisoryBoundaryCount = nativeAdvisoryBoundaryCount,
                    nativeHardBoundaryCount = nativeHardBoundaryCount,
                    nativeAdvisoryCrossed = nativeAdvisoryBoundaryCount > 0,
                    nativeHardCrossed = nativeHardBoundaryCount > 0,
                    nativeCrossingAttributionScope = "WHOLE-BLOCK-PROCESS",
                    attributedAlgorithmId = string.Empty,
                    blockBaselineTelemetry = blockBaselineTelemetry,
                    postBlockTelemetry = postBlockTelemetry,
                    postBlockMemoryEvaluationRelativePath = postBlockEvaluationFileName,
                    postBlockMemoryEvaluationSha256 = postBlockEvaluationSha256,
                    hardMemoryRulesPassed = hardMemoryRulesPassed,
                    validationOnly = plan.validationOnly,
                    formalCampaign = plan.formalCampaign,
                    samples = completed.ToArray(),
                    completed = true
                };
                WriteAtomicJson(Path.Combine(outputRoot, "block-manifest.json"), blockManifest);
                if (!hardMemoryRulesPassed)
                {
                    if (postBlockEvaluation.hostEmergencyCrossed || postBlockEvaluation.nativeHardCrossed || !postBlockEvaluation.blockManagedHardLimitPassedAtSampleBoundary)
                    {
                        currentMemoryEvaluation = new MemoryEvaluationReference
                        {
                            relativePath = postBlockEvaluationFileName,
                            sha256 = postBlockEvaluationSha256,
                            verdict = postBlockEvaluation.verdict,
                            reasonCode = postBlockEvaluation.reasonCode
                        };
                    }
                    else if (firstNativeHardMemoryEvaluation != null)
                    {
                        currentMemoryEvaluation = firstNativeHardMemoryEvaluation;
                    }
                    WriteCheckpoint(outputRoot, plan, processId, "block-completed-memory-ineligible", completed.Count, 0, null, currentMemoryEvaluation.reasonCode, currentMemoryEvaluation);
                    throw new InvalidOperationException("MP2 block completed but is memory-ineligible; the next block is forbidden: " + currentMemoryEvaluation.reasonCode + ".");
                }
                WriteCheckpoint(outputRoot, plan, processId, "block-completed", completed.Count, 0, null, null, currentMemoryEvaluation);
                UnityEngine.Debug.Log("DDM Gate 13R P1-C5 block completed: " + plan.blockId);
            }
            catch (Exception exception)
            {
                if (!string.IsNullOrWhiteSpace(outputRoot))
                {
                    try
                    {
                        Directory.CreateDirectory(outputRoot);
                        WriteAtomicJson(Path.Combine(outputRoot, "block-failure.json"), new BlockFailure
                        {
                            failedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                            blockId = plan == null ? string.Empty : plan.blockId,
                            processId = processId,
                            completedSampleCount = completed.Count,
                            failedPosition = currentPosition,
                            failedRunId = currentRunId ?? string.Empty,
                            exceptionType = exception.GetType().FullName,
                            message = exception.Message,
                            stackTrace = exception.ToString(),
                            memoryGateEvaluationRelativePath = currentMemoryEvaluation.relativePath,
                            memoryGateEvaluationSha256 = currentMemoryEvaluation.sha256,
                            memoryGateVerdict = currentMemoryEvaluation.verdict,
                            memoryGateReasonCode = currentMemoryEvaluation.reasonCode,
                            laterPositionsExecuted = false,
                            automaticRetryAttempted = false,
                            automaticResumeAttempted = false,
                            formalCampaign = plan != null && plan.formalCampaign
                        });
                        if (plan != null) WriteCheckpoint(outputRoot, plan, processId, "failed-no-auto-retry", completed.Count, currentPosition, currentRunId, exception.Message, currentMemoryEvaluation);
                    }
                    catch { }
                }
                UnityEngine.Debug.LogException(exception);
                throw;
            }
        }

        private static BlockChildRecord RunSample(
            string projectRoot,
            string outputRoot,
            string scenarioPath,
            BlockPlan plan,
            BlockEntry entry,
            string blockPlanSha256,
            Process process,
            ProcessTelemetry blockBaselineTelemetry,
            bool finalSampleInBlock,
            MemoryEvaluationReference memoryEvaluation)
        {
            string childDirectory = ResolveChildDirectory(outputRoot, entry.directory);
            EnsureFreshOutputDirectory(childDirectory);
            try
            {
                ForceCollectionBoundary();
                ProcessTelemetry before = CaptureTelemetry(process);
                if (blockBaselineTelemetry == null) throw new InvalidOperationException("MP2 block baseline telemetry is missing.");
                SampleCoreResult core = RunSampleCore(projectRoot, childDirectory, scenarioPath, plan, entry, blockPlanSha256, before, process);
                ForceCollectionBoundary();
                ProcessTelemetry afterCleanup = CaptureTelemetry(process);
                return FinalizeSample(
                    plan,
                    entry,
                    before,
                    afterCleanup,
                    core,
                    blockBaselineTelemetry,
                    finalSampleInBlock,
                    memoryEvaluation);
            }
            catch (Exception exception)
            {
                if (Directory.Exists(childDirectory))
                {
                    try
                    {
                        WriteAtomicJson(Path.Combine(childDirectory, "failure.json"), new SampleFailure
                        {
                            failedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                            exceptionType = exception.GetType().FullName,
                            message = exception.Message,
                            stackTrace = exception.ToString(),
                            memoryGateEvaluationRelativePath = memoryEvaluation.relativePath,
                            memoryGateEvaluationSha256 = memoryEvaluation.sha256,
                            memoryGateVerdict = memoryEvaluation.verdict,
                            memoryGateReasonCode = memoryEvaluation.reasonCode
                        });
                    }
                    catch { }
                }
                throw;
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static SampleCoreResult RunSampleCore(
            string projectRoot,
            string childDirectory,
            string scenarioPath,
            BlockPlan plan,
            BlockEntry entry,
            string blockPlanSha256,
            ProcessTelemetry before,
            Process process)
        {
            DateTime startedUtc = DateTime.UtcNow;
            INavigationPlanner planner = CreatePlanner(entry.algorithmId);
            PlanningRunProvenance provenance = BuildProvenance(projectRoot, entry.algorithmId);
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
            Directory.CreateDirectory(childDirectory);

            const string canonicalFileName = "scenario.canonical.json";
            const string operationsFileName = "operations.jsonl";
            const string resultFileName = "workload-result.json";
            const string manifestFileName = "manifest.json";
            const string summaryFileName = "sample-summary.json";
            string canonicalPath = Path.Combine(childDirectory, canonicalFileName);
            string operationsPath = Path.Combine(childDirectory, operationsFileName);
            string resultPath = Path.Combine(childDirectory, resultFileName);
            string manifestPath = Path.Combine(childDirectory, manifestFileName);
            string summaryPath = Path.Combine(childDirectory, summaryFileName);

            string canonicalSha256 = DeterministicScenarioJson.SaveCanonical(canonicalPath, loaded.Resolved, false);
            PlanningWorkloadResult workload;
            long enqueued;
            long written;
            bool loggerDisposed = false;
            using (JsonlExperimentLogger logger = new JsonlExperimentLogger(operationsPath, ExperimentLogFileMode.CreateNew))
            {
                workload = DeterministicPlanningWorkloadRunner.Run(entry.runId, loaded.Definition, planner, logger, provenance);
                logger.Flush(TimeSpan.FromSeconds(30d));
                enqueued = logger.EnqueuedCount;
                written = logger.WrittenCount;
            }
            loggerDisposed = true;
            if (!workload.completed) throw new InvalidOperationException("Planning workload did not complete; refusing to publish a sample completion marker.");
            WriteAtomicJson(resultPath, workload);
            ProcessTelemetry rawAfter = CaptureTelemetry(process);
            planner.Reset();

            ProcessReuseSampleManifest manifest = new ProcessReuseSampleManifest
            {
                runId = entry.runId,
                algorithmId = entry.algorithmId,
                fairnessSchemaVersion = workload.fairnessSchemaVersion,
                fairnessProtocolId = workload.fairnessProtocolId,
                fairnessProtocolRelativePath = workload.fairnessProtocolRelativePath,
                fairnessProtocolSha256 = workload.fairnessProtocolSha256,
                algorithmSpecificationId = workload.algorithmSpecificationId,
                algorithmSpecificationRelativePath = workload.algorithmSpecificationRelativePath,
                algorithmSpecificationSha256 = workload.algorithmSpecificationSha256,
                algorithmImplementationRelativePath = workload.algorithmImplementationRelativePath,
                algorithmImplementationSha256 = workload.algorithmImplementationSha256,
                workloadSpecificationId = workload.workloadSpecificationId,
                workloadSpecificationRelativePath = workload.workloadSpecificationRelativePath,
                workloadSpecificationSha256 = workload.workloadSpecificationSha256,
                goalCohortId = workload.goalCohortId,
                comparisonCohortId = workload.comparisonCohortId,
                distinctGoalCount = workload.distinctGoalCount,
                plannerInstanceCount = workload.plannerInstanceCount,
                persistentStateInstanceCount = workload.persistentStateInstanceCount,
                sharedFieldInstanceCount = workload.sharedFieldInstanceCount,
                plannerStateModelId = workload.plannerStateModelId,
                processedWorkUnit = workload.processedWorkUnit,
                nativeMetricsSemanticsId = workload.nativeMetricsSemanticsId,
                dynamicCostIncludesAllRepairsAndPostEventPlans = workload.dynamicCostIncludesAllRepairsAndPostEventPlans,
                scenarioSourcePath = loaded.SourcePath,
                scenarioSourceSha256 = loaded.SourceSha256,
                scenarioFingerprintSha256 = loaded.Resolved.FingerprintSha256,
                canonicalScenarioFile = canonicalFileName,
                canonicalScenarioSha256 = canonicalSha256,
                operationsJsonlFile = operationsFileName,
                operationsJsonlSha256 = ComputeFileSha256(operationsPath),
                workloadResultFile = resultFileName,
                workloadResultSha256 = ComputeFileSha256(resultPath),
                unityVersion = Application.unityVersion,
                runtimePlatform = Application.platform.ToString(),
                startedAtUtc = startedUtc.ToString("O", CultureInfo.InvariantCulture),
                enqueuedLogRecords = enqueued,
                writtenLogRecords = written,
                planOperationCount = workload.planOperationCount,
                repairOperationCount = workload.repairOperationCount,
                blockId = plan.blockId,
                block = plan.block,
                position = entry.position,
                cohortSize = plan.entries.Length,
                predecessorAlgorithmId = entry.predecessorAlgorithmId,
                blockPlanSha256 = blockPlanSha256,
                processReuseSpecificationSha256 = plan.specificationSha256,
                processReuseTestDesignSha256 = plan.testDesignSha256,
                processReuseAmendmentSha256 = plan.amendmentSha256,
                processReuseCommandSha256 = plan.commandSha256,
                executionReceiptSha256 = plan.executionReceiptSha256,
                memoryGatePolicyId = MemoryGatePolicyId,
                policyTierId = plan.policyTierId,
                canonicalMaximumGridDimension = plan.canonicalMaximumGridDimension,
                nativeAdvisoryThresholdBytes = plan.nativeAdvisoryThresholdBytes,
                nativeHardThresholdBytes = plan.nativeHardThresholdBytes,
                maximumSampleRetainedManagedGrowthBytes = SampleManagedEmergencyStopBytes,
                sampleManagedAlertThresholdBytes = SampleManagedAlertThresholdBytes,
                sampleManagedEmergencyStopBytes = SampleManagedEmergencyStopBytes,
                forcedGcBeforeCompleted = true,
                forcedGcAfterCompleted = false,
                sampleStateCreatedFresh = true,
                heavySampleReferencesReturned = false,
                plannerResetCompleted = true,
                loggerDisposed = loggerDisposed,
                formalCampaign = plan.formalCampaign,
                telemetryBeforeSample = before,
                telemetryRawAfterWorkload = rawAfter,
                completed = false
            };

            return new SampleCoreResult
            {
                childDirectory = childDirectory,
                resultPath = resultPath,
                manifestPath = manifestPath,
                summaryPath = summaryPath,
                resultFileName = resultFileName,
                manifestFileName = manifestFileName,
                summaryFileName = summaryFileName,
                manifest = manifest,
                scenarioId = workload.scenarioId,
                totalPlannerElapsedMilliseconds = workload.totalPlannerElapsedMilliseconds,
                dynamicHandlingMillisecondsPerScheduledEvent = workload.dynamicHandlingMillisecondsPerScheduledEvent,
                workloadCompleted = workload.completed
            };
        }

        private static BlockChildRecord FinalizeSample(
            BlockPlan plan,
            BlockEntry entry,
            ProcessTelemetry before,
            ProcessTelemetry afterCleanup,
            SampleCoreResult core,
            ProcessTelemetry blockBaselineTelemetry,
            bool finalSampleInBlock,
            MemoryEvaluationReference memoryEvaluation)
        {
            ProcessTelemetry rawAfter = core.manifest.telemetryRawAfterWorkload;
            MemoryGateEvaluation evaluation = CreateMemoryGateEvaluation(
                plan,
                entry,
                core.scenarioId,
                before,
                rawAfter,
                afterCleanup,
                blockBaselineTelemetry,
                finalSampleInBlock,
                "after-forced-cleanup");
            if (plan.validationOnly && plan.validationInjectedTelemetryFailurePosition == entry.position)
            {
                evaluation.telemetryValid = false;
                evaluation.verdict = "HARD-FAIL-TELEMETRY";
                evaluation.reasonCode = "HARD-FAIL-TELEMETRY-VALIDATION-INJECTION";
                evaluation.stopCurrentBlock = true;
                evaluation.startNextBlockAllowed = false;
            }
            if (plan.validationOnly && plan.validationInjectedNativeHardPosition == entry.position)
            {
                evaluation.blockWorkingSetGrowthBytesAtSampleBoundary = checked(plan.nativeHardThresholdBytes + 1L);
                evaluation.nativeResidencyMetricBytes = Math.Max(evaluation.blockWorkingSetGrowthBytesAtSampleBoundary, evaluation.blockPrivateMemoryGrowthBytesAtSampleBoundary);
                ApplyMemoryPolicy(evaluation);
            }
            const string evaluationFileName = "memory-gate-evaluation.json";
            string evaluationPath = Path.Combine(core.childDirectory, evaluationFileName);
            if (plan.validationOnly && plan.validationInjectedPersistenceFailurePosition == entry.position)
            {
                throw new IOException("HARD-FAIL-PERSISTENCE-VALIDATION-INJECTION-BEFORE-MEMORY-EVALUATION-COMMIT");
            }
            WriteAtomicJson(evaluationPath, evaluation);
            string evaluationSha256 = ComputeFileSha256(evaluationPath);
            memoryEvaluation.relativePath = NormalizeRelative(Path.Combine(entry.directory, evaluationFileName));
            memoryEvaluation.sha256 = evaluationSha256;
            memoryEvaluation.verdict = evaluation.verdict;
            memoryEvaluation.reasonCode = evaluation.reasonCode;

            if (!evaluation.telemetryValid || evaluation.stopCurrentBlock)
            {
                throw new InvalidOperationException("Memory eligibility failed after durable evaluation: " + evaluation.reasonCode + ".");
            }

            long retainedManagedGrowth = evaluation.sampleRetainedManagedGrowthBytes;

            core.manifest.telemetryAfterCleanup = afterCleanup;
            core.manifest.sampleRetainedManagedGrowthBytes = retainedManagedGrowth;
            core.manifest.retainedManagedGrowthWithinLimit = evaluation.sampleEmergencyStopPassed;
            core.manifest.memoryGateEvaluationRelativePath = evaluationFileName;
            core.manifest.memoryGateEvaluationSha256 = evaluationSha256;
            core.manifest.memoryGateVerdict = evaluation.verdict;
            core.manifest.memoryGateReasonCode = evaluation.reasonCode;
            core.manifest.policyTierId = plan.policyTierId;
            core.manifest.canonicalMaximumGridDimension = plan.canonicalMaximumGridDimension;
            core.manifest.nativeAdvisoryThresholdBytes = plan.nativeAdvisoryThresholdBytes;
            core.manifest.nativeHardThresholdBytes = plan.nativeHardThresholdBytes;
            core.manifest.sampleMemoryAlert128MiB = evaluation.sampleMemoryAlert128MiB;
            core.manifest.sampleEmergencyStopPassed = evaluation.sampleEmergencyStopPassed;
            core.manifest.nativeAdvisoryCrossed = evaluation.nativeAdvisoryCrossed;
            core.manifest.nativeHardCrossed = evaluation.nativeHardCrossed;
            core.manifest.hostEmergencyCrossed = evaluation.hostEmergencyCrossed;
            core.manifest.memoryAttributionScope = evaluation.attributionScope;
            core.manifest.forcedGcAfterCompleted = true;
            core.manifest.completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
            core.manifest.completed = core.workloadCompleted;
            WriteAtomicJson(core.manifestPath, core.manifest);
            string resultSha256 = ComputeFileSha256(core.resultPath);
            string manifestSha256 = ComputeFileSha256(core.manifestPath);

            ProcessReuseSampleSummary summary = new ProcessReuseSampleSummary
            {
                runId = entry.runId,
                blockId = plan.blockId,
                block = plan.block,
                position = entry.position,
                algorithmId = entry.algorithmId,
                predecessorAlgorithmId = entry.predecessorAlgorithmId,
                processId = before.processId,
                processStartTimeUtc = before.processStartTimeUtc,
                workloadResultRelativePath = core.resultFileName,
                workloadResultSha256 = resultSha256,
                manifestRelativePath = core.manifestFileName,
                manifestSha256 = manifestSha256,
                memoryGateEvaluationRelativePath = evaluationFileName,
                memoryGateEvaluationSha256 = evaluationSha256,
                memoryGateVerdict = evaluation.verdict,
                memoryGateReasonCode = evaluation.reasonCode,
                sampleMemoryAlert128MiB = evaluation.sampleMemoryAlert128MiB,
                completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                formalCampaign = plan.formalCampaign,
                completed = true
            };
            WriteAtomicJson(core.summaryPath, summary);

            return new BlockChildRecord
            {
                position = entry.position,
                algorithmId = entry.algorithmId,
                predecessorAlgorithmId = entry.predecessorAlgorithmId,
                runId = entry.runId,
                outputRelativePath = NormalizeRelative(entry.directory),
                manifestRelativePath = NormalizeRelative(Path.Combine(entry.directory, core.manifestFileName)),
                manifestSha256 = manifestSha256,
                summaryRelativePath = NormalizeRelative(Path.Combine(entry.directory, core.summaryFileName)),
                summarySha256 = ComputeFileSha256(core.summaryPath),
                workloadResultRelativePath = NormalizeRelative(Path.Combine(entry.directory, core.resultFileName)),
                workloadResultSha256 = resultSha256,
                processId = before.processId,
                processAgeBeforeMilliseconds = before.processAgeMilliseconds,
                processAgeRawAfterMilliseconds = rawAfter.processAgeMilliseconds,
                processAgeAfterCleanupMilliseconds = afterCleanup.processAgeMilliseconds,
                workingSetBeforeBytes = before.workingSetBytes,
                workingSetRawAfterBytes = rawAfter.workingSetBytes,
                workingSetAfterCleanupBytes = afterCleanup.workingSetBytes,
                privateMemoryBeforeBytes = before.privateMemoryBytes,
                privateMemoryRawAfterBytes = rawAfter.privateMemoryBytes,
                privateMemoryAfterCleanupBytes = afterCleanup.privateMemoryBytes,
                managedMemoryBeforeBytes = before.managedMemoryBytes,
                managedMemoryRawAfterBytes = rawAfter.managedMemoryBytes,
                managedMemoryAfterCleanupBytes = afterCleanup.managedMemoryBytes,
                availablePhysicalMemoryBeforeBytes = before.availablePhysicalMemoryBytes,
                availablePhysicalMemoryRawAfterBytes = rawAfter.availablePhysicalMemoryBytes,
                availablePhysicalMemoryAfterCleanupBytes = afterCleanup.availablePhysicalMemoryBytes,
                sampleRetainedManagedGrowthBytes = retainedManagedGrowth,
                nativeResidencyMetricBytes = evaluation.nativeResidencyMetricBytes,
                nativeAdvisoryCrossed = evaluation.nativeAdvisoryCrossed,
                nativeHardCrossed = evaluation.nativeHardCrossed,
                hostEmergencyCrossed = evaluation.hostEmergencyCrossed,
                memoryAttributionScope = evaluation.attributionScope,
                memoryGateEvaluationRelativePath = NormalizeRelative(Path.Combine(entry.directory, evaluationFileName)),
                memoryGateEvaluationSha256 = evaluationSha256,
                memoryGateVerdict = evaluation.verdict,
                memoryGateReasonCode = evaluation.reasonCode,
                sampleMemoryAlert128MiB = evaluation.sampleMemoryAlert128MiB,
                sampleEmergencyStopPassed = evaluation.sampleEmergencyStopPassed,
                gcCollectionDelta0 = afterCleanup.gcCollectionCount0 - before.gcCollectionCount0,
                gcCollectionDelta1 = afterCleanup.gcCollectionCount1 - before.gcCollectionCount1,
                gcCollectionDelta2 = afterCleanup.gcCollectionCount2 - before.gcCollectionCount2,
                totalPlannerElapsedMilliseconds = core.totalPlannerElapsedMilliseconds,
                dynamicHandlingMillisecondsPerScheduledEvent = core.dynamicHandlingMillisecondsPerScheduledEvent,
                formalCampaign = plan.formalCampaign,
                completed = core.workloadCompleted
            };
        }

        private static MemoryGateEvaluation CreateMemoryGateEvaluation(
            BlockPlan plan,
            BlockEntry entry,
            string scenarioId,
            ProcessTelemetry before,
            ProcessTelemetry rawAfter,
            ProcessTelemetry afterCleanup,
            ProcessTelemetry blockBaselineTelemetry,
            bool finalSampleInBlock,
            string measurementStage)
        {
            MemoryGateEvaluation evaluation = new MemoryGateEvaluation
            {
                evaluatedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                runId = entry.runId,
                blockId = plan.blockId,
                campaignId = plan.campaignId,
                scenarioId = scenarioId,
                scenarioRelativePath = plan.scenarioRelativePath,
                comparisonCohortId = plan.comparisonCohortId,
                algorithmId = entry.algorithmId,
                block = plan.block,
                position = entry.position,
                predecessorAlgorithmId = entry.predecessorAlgorithmId,
                expectedSampleCount = plan.entries.Length,
                finalSampleInBlock = finalSampleInBlock,
                measurementStage = measurementStage,
                policyTierId = plan.policyTierId,
                canonicalMaximumGridDimension = plan.canonicalMaximumGridDimension,
                enforcementObservedAtPosition = entry.position,
                enforcementObservedAlgorithmId = entry.algorithmId,
                blockBaselineTelemetry = blockBaselineTelemetry,
                telemetryBeforeSample = before,
                telemetryRawAfterWorkload = rawAfter,
                telemetryAfterCleanup = afterCleanup,
                nativeAdvisoryThresholdBytes = plan.nativeAdvisoryThresholdBytes,
                nativeHardThresholdBytes = plan.nativeHardThresholdBytes,
                hostAbsoluteNativeEmergencyBytes = plan.hostAbsoluteNativeEmergencyBytes,
                hostRelativeNativeGrowthEmergencyBytes = plan.hostRelativeNativeGrowthEmergencyBytes,
                hostAvailablePhysicalMemoryFloorBytes = plan.hostAvailablePhysicalMemoryFloorBytes,
                formalCampaign = plan.formalCampaign
            };

            string telemetryReason;
            evaluation.telemetryValid = TryValidateTelemetrySequence(before, rawAfter, afterCleanup, out telemetryReason);
            if (!evaluation.telemetryValid)
            {
                evaluation.sampleEmergencyStopPassed = false;
                evaluation.blockManagedHardLimitPassedAtSampleBoundary = false;
                evaluation.startNextBlockAllowed = false;
                evaluation.stopCurrentBlock = true;
                evaluation.verdict = "HARD-FAIL-TELEMETRY";
                evaluation.reasonCode = telemetryReason;
                evaluation.completed = true;
                return evaluation;
            }

            try
            {
                evaluation.sampleRetainedManagedGrowthBytes = checked(afterCleanup.managedMemoryBytes - before.managedMemoryBytes);
                if (blockBaselineTelemetry == null) throw new InvalidOperationException("MP2 block baseline telemetry is missing.");
                evaluation.blockRetainedManagedGrowthBytesAtSampleBoundary = checked(afterCleanup.managedMemoryBytes - blockBaselineTelemetry.managedMemoryBytes);
                evaluation.blockWorkingSetGrowthBytesAtSampleBoundary = checked(afterCleanup.workingSetBytes - blockBaselineTelemetry.workingSetBytes);
                evaluation.blockPrivateMemoryGrowthBytesAtSampleBoundary = checked(afterCleanup.privateMemoryBytes - blockBaselineTelemetry.privateMemoryBytes);
                evaluation.nativeResidencyMetricBytes = Math.Max(evaluation.blockWorkingSetGrowthBytesAtSampleBoundary, evaluation.blockPrivateMemoryGrowthBytesAtSampleBoundary);
                evaluation.absoluteNativeBytes = Math.Max(afterCleanup.workingSetBytes, afterCleanup.privateMemoryBytes);
            }
            catch (OverflowException)
            {
                evaluation.sampleEmergencyStopPassed = false;
                evaluation.blockManagedHardLimitPassedAtSampleBoundary = false;
                evaluation.startNextBlockAllowed = false;
                evaluation.stopCurrentBlock = true;
                evaluation.verdict = "HARD-FAIL-TELEMETRY";
                evaluation.reasonCode = "HARD-FAIL-TELEMETRY-DELTA-OVERFLOW";
                evaluation.completed = true;
                return evaluation;
            }

            try
            {
                ApplyMemoryPolicy(evaluation);
            }
            catch (OverflowException)
            {
                evaluation.sampleEmergencyStopPassed = false;
                evaluation.blockManagedHardLimitPassedAtSampleBoundary = false;
                evaluation.startNextBlockAllowed = false;
                evaluation.stopCurrentBlock = true;
                evaluation.verdict = "HARD-FAIL-TELEMETRY";
                evaluation.reasonCode = "HARD-FAIL-TELEMETRY-DELTA-OVERFLOW";
            }
            evaluation.completed = true;
            return evaluation;
        }

        private static void ApplyMemoryPolicy(MemoryGateEvaluation evaluation)
        {
            bool isRaw = string.Equals(evaluation.measurementStage, "raw-after-workload", StringComparison.Ordinal);
            bool isCleanup = string.Equals(evaluation.measurementStage, "after-forced-cleanup", StringComparison.Ordinal);
            bool isPostBlock = string.Equals(evaluation.measurementStage, "post-block-pre-exit", StringComparison.Ordinal);
            evaluation.sampleMemoryAlert128MiB = isCleanup && evaluation.sampleRetainedManagedGrowthBytes > SampleManagedAlertThresholdBytes;
            evaluation.sampleEmergencyStopPassed = !isCleanup || evaluation.sampleRetainedManagedGrowthBytes <= SampleManagedEmergencyStopBytes;
            evaluation.blockManagedHardLimitPassedAtSampleBoundary = !isPostBlock || evaluation.blockRetainedManagedGrowthBytesAtSampleBoundary <= TwoSampleBlockManagedGrowthLimitBytes;
            evaluation.nativeAdvisoryCrossed = (isCleanup || isPostBlock) && evaluation.nativeResidencyMetricBytes > evaluation.nativeAdvisoryThresholdBytes;
            evaluation.nativeHardCrossed = (isCleanup || isPostBlock) && evaluation.nativeResidencyMetricBytes > evaluation.nativeHardThresholdBytes;
            evaluation.rawTransientDiagnosticOnly = isRaw;

            List<string> hostReasons = new List<string>();
            ProcessTelemetry hostPoint = isRaw ? evaluation.telemetryRawAfterWorkload : evaluation.telemetryAfterCleanup;
            long absoluteNative = hostPoint == null ? evaluation.absoluteNativeBytes : Math.Max(hostPoint.workingSetBytes, hostPoint.privateMemoryBytes);
            long relativeNative = evaluation.nativeResidencyMetricBytes;
            long availablePhysical = hostPoint == null ? 0L : hostPoint.availablePhysicalMemoryBytes;
            if (!isRaw && evaluation.telemetryRawAfterWorkload != null && evaluation.blockBaselineTelemetry != null)
            {
                long rawWorkingDelta = checked(evaluation.telemetryRawAfterWorkload.workingSetBytes - evaluation.blockBaselineTelemetry.workingSetBytes);
                long rawPrivateDelta = checked(evaluation.telemetryRawAfterWorkload.privateMemoryBytes - evaluation.blockBaselineTelemetry.privateMemoryBytes);
                absoluteNative = Math.Max(absoluteNative, Math.Max(evaluation.telemetryRawAfterWorkload.workingSetBytes, evaluation.telemetryRawAfterWorkload.privateMemoryBytes));
                relativeNative = Math.Max(relativeNative, Math.Max(rawWorkingDelta, rawPrivateDelta));
                availablePhysical = Math.Min(availablePhysical, evaluation.telemetryRawAfterWorkload.availablePhysicalMemoryBytes);
            }
            evaluation.absoluteNativeBytes = absoluteNative;
            if (absoluteNative > evaluation.hostAbsoluteNativeEmergencyBytes) hostReasons.Add("HARD-FAIL-HOST-ABSOLUTE-NATIVE-4GIB");
            if (relativeNative > evaluation.hostRelativeNativeGrowthEmergencyBytes) hostReasons.Add("HARD-FAIL-HOST-RELATIVE-NATIVE-GROWTH-2GIB");
            if (availablePhysical < evaluation.hostAvailablePhysicalMemoryFloorBytes) hostReasons.Add("HARD-FAIL-HOST-AVAILABLE-MEMORY-BELOW-8GIB");
            evaluation.hostEmergencyCrossed = hostReasons.Count > 0;

            evaluation.stopCurrentBlock = false;
            evaluation.startNextBlockAllowed = true;
            if (evaluation.hostEmergencyCrossed)
            {
                evaluation.verdict = "HARD-FAIL-HOST-EMERGENCY";
                evaluation.reasonCode = string.Join("+", hostReasons.ToArray());
                evaluation.stopCurrentBlock = true;
                evaluation.startNextBlockAllowed = false;
            }
            else if (!evaluation.sampleEmergencyStopPassed)
            {
                evaluation.verdict = "HARD-FAIL-MANAGED-EMERGENCY";
                evaluation.reasonCode = "HARD-FAIL-SAMPLE-MANAGED-AFTER-CLEANUP-256MIB";
                evaluation.stopCurrentBlock = true;
                evaluation.startNextBlockAllowed = false;
            }
            else if (!evaluation.blockManagedHardLimitPassedAtSampleBoundary)
            {
                evaluation.verdict = "HARD-FAIL-MANAGED-EMERGENCY";
                evaluation.reasonCode = "HARD-FAIL-BLOCK-MANAGED-AFTER-CLEANUP-256MIB";
                evaluation.stopCurrentBlock = true;
                evaluation.startNextBlockAllowed = false;
            }
            else if (evaluation.nativeHardCrossed)
            {
                evaluation.verdict = "HARD-FAIL-NATIVE-ELIGIBILITY";
                evaluation.reasonCode = "HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING";
                evaluation.startNextBlockAllowed = false;
            }
            else if (evaluation.nativeAdvisoryCrossed || evaluation.sampleMemoryAlert128MiB)
            {
                evaluation.verdict = "PASS-WITH-ADVISORY";
                if (evaluation.nativeAdvisoryCrossed && evaluation.sampleMemoryAlert128MiB) evaluation.reasonCode = "NATIVE-RESIDENCY-ADVISORY+MANAGED-AFTER-CLEANUP-ALERT-128MIB";
                else if (evaluation.nativeAdvisoryCrossed) evaluation.reasonCode = "NATIVE-RESIDENCY-ADVISORY";
                else evaluation.reasonCode = "MANAGED-AFTER-CLEANUP-ALERT-128MIB";
            }
            else if (isRaw)
            {
                evaluation.verdict = "PASS";
                evaluation.reasonCode = "RAW-TRANSIENT-DIAGNOSTIC-ONLY";
            }
            else
            {
                evaluation.verdict = "PASS";
                evaluation.reasonCode = "PASS";
            }
        }

        private static void ValidatePlan(BlockPlan plan, string projectRoot, string outputRoot)
        {
            if (plan == null || plan.schemaVersion != 3) throw new InvalidOperationException("Unsupported Gate 13R P1-C5 block-plan schema.");
            if (!string.Equals(plan.designId, DesignId, StringComparison.Ordinal)) throw new InvalidOperationException("Gate 13R P1-C5 design identity mismatch.");
            if (plan.formalCampaign == plan.validationOnly) throw new InvalidOperationException("Exactly one of formalCampaign and validationOnly must be true.");
            if (plan.formalCampaign)
            {
                if (!string.Equals(plan.analysisRole, "formal-timing", StringComparison.Ordinal)) throw new InvalidOperationException("The formal block analysis role must be formal-timing.");
                if (plan.verificationInjectedFailurePosition != 0 || plan.validationInjectedNativeHardPosition != 0 || plan.validationInjectedTelemetryFailurePosition != 0 || plan.validationInjectedPersistenceFailurePosition != 0) throw new InvalidOperationException("Injected failures are forbidden in a formal block plan.");
            }
            else
            {
                if (!string.Equals(plan.analysisRole, "validation-only", StringComparison.Ordinal)) throw new InvalidOperationException("A validation block must use the validation-only role.");
                string verificationRoot = Path.GetFullPath(Path.Combine(projectRoot, "Research", "Verification", "Gate13R_P1C5_Independent"));
                if (!IsWithin(outputRoot, verificationRoot)) throw new InvalidOperationException("MP2 validation output must remain in the independent verification root.");
                if (!string.IsNullOrWhiteSpace(plan.executionReceiptRelativePath) || !string.IsNullOrWhiteSpace(plan.executionReceiptSha256)) throw new InvalidOperationException("A validation-only plan cannot bind a formal execution receipt.");
            }
            if (!SafeId.IsMatch(plan.planId ?? string.Empty) || !SafeId.IsMatch(plan.blockId ?? string.Empty) || !SafeId.IsMatch(plan.campaignId ?? string.Empty)) throw new InvalidOperationException("Unsafe block/campaign/plan identity.");
            if (plan.block < 1) throw new InvalidOperationException("Block ordinal must be positive.");
            string[] expectedAlgorithms = ExpectedAlgorithms(plan.comparisonCohortId);
            if (expectedAlgorithms.Length != 2) throw new InvalidOperationException("Gate 13R P1-C5 accepts only the complete frozen two-sample cohort.");
            if (plan.entries == null || plan.entries.Length != expectedAlgorithms.Length) throw new InvalidOperationException("Block entry count does not match cohort size.");
            if (!string.Equals(plan.memoryPolicyId, MemoryGatePolicyId, StringComparison.Ordinal)) throw new InvalidOperationException("MP2 memory-policy identity mismatch.");
            bool tierLe128 = string.Equals(plan.policyTierId, "MP2-NATIVE-LE128", StringComparison.Ordinal)
                && (plan.canonicalMaximumGridDimension == 32 || plan.canonicalMaximumGridDimension == 64 || plan.canonicalMaximumGridDimension == 128)
                && plan.nativeAdvisoryThresholdBytes == TierLe128NativeAdvisoryBytes
                && plan.nativeHardThresholdBytes == TierLe128NativeHardBytes;
            bool tierEq256 = string.Equals(plan.policyTierId, "MP2-NATIVE-EQ256", StringComparison.Ordinal)
                && plan.canonicalMaximumGridDimension == 256
                && plan.nativeAdvisoryThresholdBytes == TierEq256NativeAdvisoryBytes
                && plan.nativeHardThresholdBytes == TierEq256NativeHardBytes;
            if (!tierLe128 && !tierEq256) throw new InvalidOperationException("MP2 scenario tier or threshold mapping mismatch.");
            if (plan.hostAbsoluteNativeEmergencyBytes != HostAbsoluteNativeEmergencyBytes
                || plan.hostRelativeNativeGrowthEmergencyBytes != HostRelativeNativeGrowthEmergencyBytes
                || plan.hostAvailablePhysicalMemoryFloorBytes != HostAvailablePhysicalMemoryFloorBytes) throw new InvalidOperationException("MP2 host-emergency threshold mismatch.");
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> runIds = new HashSet<string>(StringComparer.Ordinal);
            if (plan.williamsRowIndex < 0 || plan.williamsRowIndex >= expectedAlgorithms.Length) throw new InvalidOperationException("Frozen Williams-row index is outside the cohort.");
            string[] expectedRow = WilliamsRow(expectedAlgorithms, plan.williamsRowIndex);
            for (int index = 0; index < plan.entries.Length; index++)
            {
                BlockEntry entry = plan.entries[index];
                int expectedPosition = index + 1;
                string expectedPredecessor = index == 0 ? "NONE" : plan.entries[index - 1].algorithmId;
                if (entry == null || entry.position != expectedPosition) throw new InvalidOperationException("Block positions must be contiguous and one-based.");
                if (!string.Equals(entry.algorithmId, expectedRow[index], StringComparison.Ordinal)) throw new InvalidOperationException("Block order differs from the frozen Williams row.");
                if (!string.Equals(entry.predecessorAlgorithmId, expectedPredecessor, StringComparison.Ordinal)) throw new InvalidOperationException("Predecessor identity mismatch.");
                if (!algorithms.Add(entry.algorithmId)) throw new InvalidOperationException("An algorithm appears more than once in the process.");
                if (!SafeId.IsMatch(entry.runId ?? string.Empty) || !runIds.Add(entry.runId)) throw new InvalidOperationException("Unsafe or duplicate run ID.");
                ResolveChildDirectory(outputRoot, entry.directory);
            }
            if (algorithms.Count != expectedAlgorithms.Length) throw new InvalidOperationException("The block does not contain the exact authorized cohort.");
            ValidateBoundFile(projectRoot, plan.formalConfigRelativePath, plan.formalConfigSha256, "Gate 13R-PR2 formal config");
            ValidateBoundFile(projectRoot, plan.specificationRelativePath, plan.specificationSha256, "Gate 13R-PR2 formal execution specification");
            ValidateBoundFile(projectRoot, plan.testDesignRelativePath, plan.testDesignSha256, "Gate 13R-PR2 prelaunch test design");
            ValidateBoundFile(projectRoot, plan.amendmentRelativePath, plan.amendmentSha256, "Gate 13R-PR2 two-phase amendment");
            ValidateBoundFile(projectRoot, plan.commandRelativePath, plan.commandSha256, "Gate 13R-PR2 formal command");
            ValidateBoundFile(projectRoot, plan.provenanceRelativePath, plan.provenanceSha256, "Gate 13R-PR2 formal execution provenance");
            ValidateBoundFile(projectRoot, plan.memoryPolicyRegistryRelativePath, plan.memoryPolicyRegistrySha256, "Gate 13R-PR2-MP2 policy registry");
            ValidateBoundFile(projectRoot, plan.scenarioPolicyMappingRelativePath, plan.scenarioPolicyMappingSha256, "Gate 13R-PR2-MP2 scenario mapping");
            ValidateBoundFile(projectRoot, plan.schedulePolicyOverlayRelativePath, plan.schedulePolicyOverlaySha256, "Gate 13R-PR2-MP2 schedule policy overlay");
            if (plan.formalCampaign) ValidateBoundFile(projectRoot, plan.executionReceiptRelativePath, plan.executionReceiptSha256, "Gate 13R P1-C5 formal execution receipt");

            string scenarioPath = Path.GetFullPath(Path.Combine(projectRoot, plan.scenarioRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            ScenarioDimensionIdentity scenarioIdentity = JsonUtility.FromJson<ScenarioDimensionIdentity>(File.ReadAllText(scenarioPath, Encoding.UTF8));
            if (scenarioIdentity == null || string.IsNullOrWhiteSpace(scenarioIdentity.scenarioId)) throw new InvalidOperationException("Scenario dimension identity is missing.");
            if (!string.Equals(scenarioIdentity.scenarioId, plan.scenarioId, StringComparison.Ordinal)) throw new InvalidOperationException("Scenario ID differs from the frozen MP2 mapping.");
            int actualMaximum = Math.Max(scenarioIdentity.gridWidth, scenarioIdentity.gridHeight);
            if (scenarioIdentity.gridWidth <= 0 || scenarioIdentity.gridHeight <= 0 || scenarioIdentity.gridWidth != plan.gridWidth || scenarioIdentity.gridHeight != plan.gridHeight || actualMaximum != plan.canonicalMaximumGridDimension) throw new InvalidOperationException("Scenario dimensions differ from the frozen MP2 mapping.");
        }

        private static void ValidateCompletedBlock(BlockPlan plan, List<BlockChildRecord> completed, int processId)
        {
            if (completed.Count != plan.entries.Length) throw new InvalidOperationException("A partial block cannot be marked complete.");
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < completed.Count; index++)
            {
                BlockChildRecord child = completed[index];
                BlockEntry entry = plan.entries[index];
                if (!child.completed || child.position != entry.position || child.algorithmId != entry.algorithmId || child.runId != entry.runId) throw new InvalidOperationException("Completed child identity/order mismatch.");
                if (child.processId != processId) throw new InvalidOperationException("Samples in one block reported mixed process IDs.");
                if (!algorithms.Add(child.algorithmId)) throw new InvalidOperationException("Duplicate algorithm in completed block.");
            }
        }

        private static bool TryValidateTelemetrySequence(ProcessTelemetry before, ProcessTelemetry rawAfter, ProcessTelemetry afterCleanup, out string reasonCode)
        {
            reasonCode = "PASS";
            if (before == null || rawAfter == null || afterCleanup == null) { reasonCode = "HARD-FAIL-TELEMETRY-MISSING"; return false; }
            if (before.processId <= 0 || before.processId != rawAfter.processId || before.processId != afterCleanup.processId) { reasonCode = "HARD-FAIL-TELEMETRY-MIXED-PID"; return false; }
            if (string.IsNullOrWhiteSpace(before.processStartTimeUtc)
                || !string.Equals(before.processStartTimeUtc, rawAfter.processStartTimeUtc, StringComparison.Ordinal)
                || !string.Equals(before.processStartTimeUtc, afterCleanup.processStartTimeUtc, StringComparison.Ordinal))
            {
                reasonCode = "HARD-FAIL-TELEMETRY-MIXED-PROCESS-START";
                return false;
            }
            if (!IsFinite(before.processAgeMilliseconds) || !IsFinite(rawAfter.processAgeMilliseconds) || !IsFinite(afterCleanup.processAgeMilliseconds)) { reasonCode = "HARD-FAIL-TELEMETRY-NONFINITE-PROCESS-AGE"; return false; }
            if (before.processAgeMilliseconds < 0d || before.processAgeMilliseconds > rawAfter.processAgeMilliseconds || rawAfter.processAgeMilliseconds > afterCleanup.processAgeMilliseconds) { reasonCode = "HARD-FAIL-TELEMETRY-PROCESS-AGE-ORDER"; return false; }
            DateTime beforeUtc;
            DateTime rawAfterUtc;
            DateTime afterCleanupUtc;
            if (!DateTime.TryParse(before.capturedAtUtc, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out beforeUtc)
                || !DateTime.TryParse(rawAfter.capturedAtUtc, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out rawAfterUtc)
                || !DateTime.TryParse(afterCleanup.capturedAtUtc, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out afterCleanupUtc))
            {
                reasonCode = "HARD-FAIL-TELEMETRY-TIMESTAMP-PARSE";
                return false;
            }
            beforeUtc = beforeUtc.ToUniversalTime();
            rawAfterUtc = rawAfterUtc.ToUniversalTime();
            afterCleanupUtc = afterCleanupUtc.ToUniversalTime();
            if (beforeUtc > rawAfterUtc || rawAfterUtc > afterCleanupUtc) { reasonCode = "HARD-FAIL-TELEMETRY-TIMESTAMP-ORDER"; return false; }
            if (!ValuesPositive(before.workingSetBytes, rawAfter.workingSetBytes, afterCleanup.workingSetBytes)) { reasonCode = "HARD-FAIL-TELEMETRY-WORKING-SET-NONPOSITIVE"; return false; }
            if (!ValuesPositive(before.privateMemoryBytes, rawAfter.privateMemoryBytes, afterCleanup.privateMemoryBytes)) { reasonCode = "HARD-FAIL-TELEMETRY-PRIVATE-MEMORY-NONPOSITIVE"; return false; }
            if (!ValuesPositive(before.managedMemoryBytes, rawAfter.managedMemoryBytes, afterCleanup.managedMemoryBytes)) { reasonCode = "HARD-FAIL-TELEMETRY-MANAGED-MEMORY-NONPOSITIVE"; return false; }
            if (!ValuesPositive(before.availablePhysicalMemoryBytes, rawAfter.availablePhysicalMemoryBytes, afterCleanup.availablePhysicalMemoryBytes)) { reasonCode = "HARD-FAIL-TELEMETRY-AVAILABLE-PHYSICAL-MEMORY-NONPOSITIVE"; return false; }
            if (before.gcCollectionCount0 < 0 || before.gcCollectionCount1 < 0 || before.gcCollectionCount2 < 0
                || rawAfter.gcCollectionCount0 < before.gcCollectionCount0 || rawAfter.gcCollectionCount1 < before.gcCollectionCount1 || rawAfter.gcCollectionCount2 < before.gcCollectionCount2
                || afterCleanup.gcCollectionCount0 < rawAfter.gcCollectionCount0 || afterCleanup.gcCollectionCount1 < rawAfter.gcCollectionCount1 || afterCleanup.gcCollectionCount2 < rawAfter.gcCollectionCount2)
            {
                reasonCode = "HARD-FAIL-TELEMETRY-GC-COUNT-ORDER";
                return false;
            }
            return true;
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        private static void ForceCollectionBoundary()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        private static ProcessTelemetry CaptureTelemetry(Process process)
        {
            PROCESS_MEMORY_COUNTERS_EX counters;
            uint size = checked((uint)Marshal.SizeOf(typeof(PROCESS_MEMORY_COUNTERS_EX)));
            if (!GetProcessMemoryInfo(process.Handle, out counters, size)) throw new InvalidOperationException("GetProcessMemoryInfo failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture) + ".");
            long workingSet = CheckedUIntPtrToInt64(counters.WorkingSetSize, "WorkingSetSize");
            long privateMemory = CheckedUIntPtrToInt64(counters.PrivateUsage, "PrivateUsage");
            long managed = GC.GetTotalMemory(false);
            MEMORYSTATUSEX memoryStatus = new MEMORYSTATUSEX();
            memoryStatus.dwLength = checked((uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)));
            if (!GlobalMemoryStatusEx(ref memoryStatus)) throw new InvalidOperationException("GlobalMemoryStatusEx failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture) + ".");
            if (memoryStatus.ullAvailPhys > long.MaxValue) throw new OverflowException("Available physical memory exceeds Int64.");
            long availablePhysicalMemory = (long)memoryStatus.ullAvailPhys;
            if (workingSet <= 0L || privateMemory <= 0L || managed <= 0L || availablePhysicalMemory <= 0L) throw new InvalidOperationException("Native/managed/host telemetry must be strictly positive.");
            DateTime capturedUtc = DateTime.UtcNow;
            DateTime startUtc = process.StartTime.ToUniversalTime();
            return new ProcessTelemetry
            {
                capturedAtUtc = capturedUtc.ToString("O", CultureInfo.InvariantCulture),
                processId = process.Id,
                processStartTimeUtc = startUtc.ToString("O", CultureInfo.InvariantCulture),
                processAgeMilliseconds = Math.Max(0d, (capturedUtc - startUtc).TotalMilliseconds),
                workingSetBytes = workingSet,
                privateMemoryBytes = privateMemory,
                managedMemoryBytes = managed,
                availablePhysicalMemoryBytes = availablePhysicalMemory,
                gcCollectionCount0 = GC.CollectionCount(0),
                gcCollectionCount1 = GC.CollectionCount(1),
                gcCollectionCount2 = GC.CollectionCount(2)
            };
        }

        private static long CheckedUIntPtrToInt64(UIntPtr value, string label)
        {
            ulong unsigned = value.ToUInt64();
            if (unsigned > long.MaxValue) throw new OverflowException(label + " exceeds Int64.");
            return (long)unsigned;
        }

        private static long DistanceToClosedInterval(long value, long first, long second)
        {
            long lower = Math.Min(first, second);
            long upper = Math.Max(first, second);
            if (value < lower) return lower - value;
            if (value > upper) return value - upper;
            return 0L;
        }

        private static long ProbeTolerance(long external, long before, long after)
        {
            long maximum = Math.Max(external, Math.Max(before, after));
            long relative = checked((long)Math.Ceiling(ProbeRelativeTolerance * maximum));
            return Math.Max(ProbeAbsoluteToleranceBytes, relative);
        }

        private static bool ValuesPositive(long first, long second, long third)
        {
            return first > 0L && second > 0L && third > 0L;
        }

        private static DateTime ParseUtc(string value, string label)
        {
            DateTime parsed;
            if (!DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed)) throw new InvalidOperationException("Invalid " + label + ".");
            return parsed.ToUniversalTime();
        }

        private static bool PathsEqual(string first, string second)
        {
            if (string.IsNullOrWhiteSpace(first) || string.IsNullOrWhiteSpace(second)) return false;
            return string.Equals(Path.GetFullPath(first), Path.GetFullPath(second), StringComparison.OrdinalIgnoreCase);
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new NotSupportedException("Unauthorized Gate 10R process-reuse planner: " + algorithmId);
        }

        private static PlanningRunProvenance BuildProvenance(string projectRoot, string algorithmId)
        {
            PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
            PlanningRunProvenance provenance = new PlanningRunProvenance
            {
                fairnessProtocolId = PlanningFairnessContracts.FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.FairnessProtocolRelativePath,
                fairnessProtocolSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.FairnessProtocolRelativePath),
                algorithmId = profile.AlgorithmId,
                algorithmSpecificationId = profile.SpecificationId,
                algorithmSpecificationRelativePath = profile.SpecificationRelativePath,
                algorithmSpecificationSha256 = HashProjectFile(projectRoot, profile.SpecificationRelativePath),
                algorithmImplementationRelativePath = profile.ImplementationRelativePath,
                algorithmImplementationSha256 = HashProjectFile(projectRoot, profile.ImplementationRelativePath),
                workloadSpecificationId = PlanningFairnessContracts.WorkloadSpecificationId,
                workloadSpecificationRelativePath = PlanningFairnessContracts.WorkloadSpecificationRelativePath,
                workloadSpecificationSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.WorkloadSpecificationRelativePath)
            };
            PlanningFairnessContracts.ValidateProvenance(provenance, algorithmId);
            return provenance;
        }

        private static string[] ExpectedAlgorithms(string cohortId)
        {
            if (cohortId == "p1-c5-shared-goal-v1") return new[] { "C-FF", "IDFF" };
            throw new InvalidOperationException("Unsupported comparison cohort: " + cohortId);
        }

        private static string[] WilliamsRow(string[] items, int rowIndex)
        {
            int count = items.Length;
            int[] baseIndices = new int[count];
            baseIndices[0] = 0;
            for (int step = 1; step < count; step++) baseIndices[step] = step % 2 == 1 ? (step + 1) / 2 : count - (step / 2);
            string[] row = new string[count];
            for (int index = 0; index < count; index++) row[index] = items[(baseIndices[index] + rowIndex) % count];
            return row;
        }

        private static void WriteCheckpoint(string outputRoot, BlockPlan plan, int processId, string status, int completedCount, int currentPosition, string currentRunId, string error, MemoryEvaluationReference memoryEvaluation)
        {
            WriteAtomicJsonReplacing(Path.Combine(outputRoot, "block-checkpoint.json"), new BlockCheckpoint
            {
                blockId = plan.blockId,
                status = status,
                savedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                processId = processId,
                expectedSampleCount = plan.entries.Length,
                completedSampleCount = completedCount,
                currentPosition = currentPosition,
                currentRunId = currentRunId ?? string.Empty,
                error = error ?? string.Empty,
                memoryGateEvaluationRelativePath = memoryEvaluation == null ? string.Empty : memoryEvaluation.relativePath,
                memoryGateEvaluationSha256 = memoryEvaluation == null ? string.Empty : memoryEvaluation.sha256,
                memoryGateVerdict = memoryEvaluation == null ? string.Empty : memoryEvaluation.verdict,
                memoryGateReasonCode = memoryEvaluation == null ? string.Empty : memoryEvaluation.reasonCode,
                automaticRetryAuthorized = false,
                automaticResumeAuthorized = false,
                formalCampaign = plan.formalCampaign
            });
        }

        private static void ValidateBoundFile(string projectRoot, string relativePath, string expectedSha256, string label)
        {
            if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath)) throw new InvalidOperationException("Invalid " + label + " relative path.");
            string path = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!IsWithin(path, projectRoot) || !File.Exists(path)) throw new FileNotFoundException("Bound " + label + " is missing or outside the project.", path);
            if (!string.Equals(ComputeFileSha256(path), expectedSha256, StringComparison.Ordinal)) throw new InvalidOperationException("Bound " + label + " SHA-256 mismatch.");
        }

        private static string ResolveChildDirectory(string outputRoot, string relativePath)
        {
            if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath)) throw new InvalidOperationException("Child output path must be a non-empty relative path.");
            string fullPath = Path.GetFullPath(Path.Combine(outputRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!IsWithin(fullPath, outputRoot) || string.Equals(fullPath.TrimEnd(Path.DirectorySeparatorChar), outputRoot.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Child output path escapes or equals the block root.");
            return fullPath;
        }

        private static bool IsWithin(string candidate, string root)
        {
            string normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string normalizedCandidate = Path.GetFullPath(candidate);
            return normalizedCandidate.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase);
        }

        private static string RequiredOption(string[] arguments, string option)
        {
            string value = null;
            for (int index = 0; index < arguments.Length; index++)
            {
                if (!string.Equals(arguments[index], option, StringComparison.Ordinal)) continue;
                if (value != null) throw new ArgumentException("Command-line option was supplied more than once: " + option);
                if (index + 1 >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index + 1])) throw new ArgumentException("Command-line option requires a value: " + option);
                value = arguments[index + 1];
            }
            if (value == null) throw new ArgumentException("Required command-line option is missing: " + option);
            return value;
        }

        private static void EnsureFreshOutputDirectory(string outputDirectory)
        {
            if (File.Exists(outputDirectory)) throw new IOException("Output path is an existing file: " + outputDirectory);
            if (Directory.Exists(outputDirectory) && Directory.GetFileSystemEntries(outputDirectory).Length > 0) throw new IOException("Output directory is not empty; refusing to mix or overwrite runs: " + outputDirectory);
        }

        private static string HashProjectFile(string projectRoot, string relativePath)
        {
            string path = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!File.Exists(path)) throw new FileNotFoundException("Required provenance source is missing.", path);
            return ComputeFileSha256(path);
        }

        private static string ComputeFileSha256(string path)
        {
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (SHA256 sha256 = SHA256.Create())
            {
                return BitConverter.ToString(sha256.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static string NormalizeRelative(string value)
        {
            return value.Replace(Path.DirectorySeparatorChar, '/');
        }

        private static string StableJson<T>(T value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            return json;
        }

        private static void WriteJson<T>(string path, T value)
        {
            File.WriteAllText(path, StableJson(value), Utf8WithoutBom);
        }

        private static void WriteTextCreateNew(string path, string text)
        {
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (StreamWriter writer = new StreamWriter(stream, Utf8WithoutBom))
            {
                writer.Write(text);
            }
        }

        private static void WriteJsonCreateNew<T>(string path, T value)
        {
            WriteTextCreateNew(path, StableJson(value));
        }

        private static void SetAtomicPersistenceAllowedRoot(string root)
        {
            string full = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (!Directory.Exists(full)) throw new DirectoryNotFoundException("Atomic persistence allowed root does not exist: " + full);
            ValidateOrdinaryDirectoryIdentity(full);
            AtomicPersistenceAllowedRoot = full;
        }

        private static void ValidateOrdinaryDirectoryIdentity(string path)
        {
            if (!Directory.Exists(path)) throw new DirectoryNotFoundException("Atomic persistence directory does not exist: " + path);
            DirectoryInfo info = new DirectoryInfo(path);
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("Atomic persistence rejects reparse-point directories: " + path);
            string observed = Path.GetFullPath(info.FullName).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string expected = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (!string.Equals(observed, expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Atomic persistence directory identity changed: " + path);
        }

        private static string ValidateAtomicFinalPath(string path, bool allowExistingFinal)
        {
            if (string.IsNullOrWhiteSpace(AtomicPersistenceAllowedRoot)) throw new InvalidOperationException("Atomic persistence allowed root was not initialized.");
            string root = Path.GetFullPath(AtomicPersistenceAllowedRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string full = Path.GetFullPath(path);
            if (!IsWithin(full, root)) throw new InvalidOperationException("Atomic persistence final path escapes the allowed root: " + full);
            string parent = Path.GetDirectoryName(full);
            if (string.IsNullOrWhiteSpace(parent) || !Directory.Exists(parent)) throw new DirectoryNotFoundException("Atomic persistence final parent does not exist: " + parent);
            ValidateOrdinaryDirectoryIdentity(root);
            string relativeParent = parent.Length == root.Length ? string.Empty : parent.Substring(root.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string current = root;
            if (!string.IsNullOrEmpty(relativeParent))
            {
                string[] segments = relativeParent.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);
                for (int index = 0; index < segments.Length; index++)
                {
                    current = Path.Combine(current, segments[index]);
                    ValidateOrdinaryDirectoryIdentity(current);
                }
            }
            if (Directory.Exists(full)) throw new IOException("Atomic persistence final path is an existing directory: " + full);
            if (File.Exists(full))
            {
                FileInfo file = new FileInfo(full);
                if ((file.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("Atomic persistence rejects a reparse-point final file: " + full);
                if (!allowExistingFinal) throw new IOException("Atomic persistence refuses to overwrite immutable evidence: " + full);
            }
            return full;
        }

        private static void WriteAtomicJson<T>(string path, T value)
        {
            WriteAtomicJsonCore(path, value, false, null, AtomicFaultInjection.None);
        }

        private static void WriteAtomicJsonReplacing<T>(string path, T value)
        {
            WriteAtomicJsonCore(path, value, true, null, AtomicFaultInjection.None);
        }

        private static void WriteAtomicJsonCore<T>(string path, T value, bool allowReplace, string forcedTemporaryLeaf, AtomicFaultInjection fault)
        {
            string full = ValidateAtomicFinalPath(path, allowReplace);
            string parent = Path.GetDirectoryName(full);
            string temporaryLeaf = forcedTemporaryLeaf ?? (AtomicTemporaryPrefix + Guid.NewGuid().ToString("N"));
            if (!AtomicTemporaryLeaf.IsMatch(temporaryLeaf) || temporaryLeaf.Length != AtomicTemporaryLeafLength) throw new InvalidOperationException("Atomic persistence temporary leaf identity is invalid.");
            string temporary = Path.Combine(parent, temporaryLeaf);
            LastAtomicTemporaryPathForSelfTest = temporary;
            if (!string.Equals(Path.GetDirectoryName(temporary), parent, StringComparison.OrdinalIgnoreCase) || !IsWithin(temporary, AtomicPersistenceAllowedRoot)) throw new InvalidOperationException("Atomic persistence temporary path is not in the verified final directory.");
            if (File.Exists(temporary) || Directory.Exists(temporary)) throw new IOException("Atomic persistence temporary collision: " + temporary);
            bool temporaryOwned = false;
            try
            {
                if (fault == AtomicFaultInjection.BeforeWrite) throw new IOException("Injected atomic write failure.");
                WriteJsonCreateNew(temporary, value);
                temporaryOwned = true;
                if (fault == AtomicFaultInjection.BeforeCommit) throw new IOException("Injected atomic move failure.");
                string revalidated = ValidateAtomicFinalPath(full, allowReplace);
                if (!string.Equals(revalidated, full, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Atomic persistence final path identity changed before commit.");
                if (File.Exists(full))
                {
                    if (!allowReplace) throw new IOException("Atomic persistence refuses to overwrite immutable evidence: " + full);
                    File.Replace(temporary, full, null);
                }
                else
                {
                    File.Move(temporary, full);
                }
                temporaryOwned = false;
                if (!File.Exists(full)) throw new IOException("Atomic persistence commit did not produce the final file.");
            }
            finally
            {
                if (temporaryOwned && File.Exists(temporary))
                {
                    try { File.Delete(temporary); }
                    catch { }
                }
            }
        }
    }
}
