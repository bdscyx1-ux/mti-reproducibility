#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using DDM.Research.Gate14ReME.V3;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.Attempt003V31
{
    [Serializable]
    internal sealed class Gate14ReMED3V31AuthorizationHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31ContractHeaderV1
    {
        public string schema;
        public string studyId;
        public string endpointId;
        public string semanticVersion;
        public string status;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31WindowRecordV1
    {
        public string controlId;
        public int trial;
        public int requestedPayloadBytes;
        public int requestedAllocationCount;
        public long managedAllocationBytes;
        public long managedAllocationEventCount;
        public long foreignThreadAllocationBytes;
        public long foreignThreadAllocationEventCount;
        public long invalidMetadataEventCount;
        public long counterOverflowCount;
        public long ownerNativeThreadId;
        public long windowStartStopwatchTicks;
        public long windowEndStopwatchTicks;
        public long windowElapsedStopwatchTicks;
        public long stopwatchFrequency;
        public double managedAllocationRateBytesPerSecond;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31StageRecordV1
    {
        public string stageId;
        public bool completed;
        public bool passed;
        public string detail;
        public string completedAtUtc;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31MarkerControlV1
    {
        public string exactMarkerName;
        public bool pluginReady;
        public bool markerSeen;
        public int createCallbackRegistrationCode;
        public int markerCallbackRegistrationCode;
        public string requiredMetadataType;
        public int requiredMetadataTypeValue;
        public int requiredMetadataSizeBytes;
        public bool abiExportsMatchContract;
        public bool observedPositiveMetadata;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31EmptyControlV1
    {
        public int trials;
        public long maximumOwnerBytes;
        public long maximumOwnerEvents;
        public bool allOwnerResponsesZero;
        public bool allDiagnosticsClean;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31ArrayControlV1
    {
        public Gate14ReMED3V31WindowRecordV1[] records;
        public long minimumOverheadBytes;
        public long maximumOverheadBytes;
        public long overheadSpreadBytes;
        public bool allWithinPayloadAndOverheadBounds;
        public bool strictlyIncreasing;
        public bool overheadSpreadPassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31RepeatedControlV1
    {
        public int payloadBytesPerObject;
        public int repetitions;
        public Gate14ReMED3V31WindowRecordV1 oneObject;
        public Gate14ReMED3V31WindowRecordV1 repeatedObjects;
        public long expectedRepeatedBytes;
        public long expectedRepeatedEvents;
        public bool exactByteScalingPassed;
        public bool exactEventScalingPassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31GCControlV1
    {
        public int payloadBytes;
        public Gate14ReMED3V31WindowRecordV1 finalWindow;
        public long beforeCollectionBytes;
        public long beforeCollectionEvents;
        public long afterCollectionBytes;
        public long afterCollectionEvents;
        public long endWindowBytes;
        public long endWindowEvents;
        public bool countersNeverDecrease;
        public bool beforeToAfterConditionalConsistency;
        public bool afterToEndConditionalConsistency;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31ThreadControlV1
    {
        public Gate14ReMED3V31WindowRecordV1 reusedOneMiBOwnerRecord;
        public Gate14ReMED3V31WindowRecordV1 crossThreadRecord;
        public long harnessNativeThreadId;
        public int crossThreadRequestedPayloadBytes;
        public bool ownerIdPassed;
        public bool ownerPositiveResponsePassed;
        public bool crossThreadOwnerExclusionPassed;
        public bool crossThreadForeignResponsePassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31FormulaControlV1
    {
        public string reusedControlId;
        public Gate14ReMED3V31WindowRecordV1 reusedOneMiBArrayRecord;
        public double independentlyRecomputedRateBytesPerSecond;
        public double absoluteRecomputeError;
        public double maximumAbsoluteRecomputeError;
        public bool finitePositiveRatePassed;
        public bool recomputePassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31FileBindingV1
    {
        public string role;
        public string relativePath;
        public string sha256;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31ScientificBoundaryV1
    {
        public bool priorEvidenceRetained;
        public bool priorDiagnosticsRerun;
        public bool currentQualificationRunnerModified;
        public bool currentOutputSchemaModified;
        public bool algorithmSourcesModified;
        public int qualificationScheduleRows;
        public int qualificationInputs;
        public int anonymousIdentityMappings;
        public bool qualificationMeasuredRootCreated;
        public int algorithmLanes;
        public int formalObservations;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
        public bool fallbackMetricUsed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V31KnownAnswerReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string parentAuthorizationId;
        public string status;
        public int version;
        public string createdAtUtc;
        public string completedAtUtc;
        public bool terminal;
        public bool passed;
        public string unityVersion;
        public string runtimeVersion;
        public string operatingSystem;
        public string architecture;
        public string currentStage;
        public string firstFailedCriterion;
        public string exceptionType;
        public string exactFailure;
        public string stackTrace;
        public bool automaticRepairAuthorized;
        public bool automaticRetryPerformedThisProcess;
        public Gate14ReMED3V31FileBindingV1[] bindings;
        public Gate14ReMED3V31StageRecordV1[] completedStages;
        public Gate14ReMED3V31MarkerControlV1 markerAndMetadata;
        public Gate14ReMED3V31EmptyControlV1 emptyWindow;
        public Gate14ReMED3V31ArrayControlV1 knownArrayScale;
        public Gate14ReMED3V31RepeatedControlV1 repeatedSmallObjects;
        public Gate14ReMED3V31GCControlV1 gcCumulativeBehavior;
        public Gate14ReMED3V31ThreadControlV1 threadAttribution;
        public Gate14ReMED3V31FormulaControlV1 byteAndRateFormula;
        public Gate14ReMED3V31WindowRecordV1[] allMeasuredWindows;
        public int measuredWindowCount;
        public bool allInvalidMetadataCountsZero;
        public bool allOverflowCountsZero;
        public bool observedPositiveUInt32Metadata;
        public Gate14ReMED3V31ScientificBoundaryV1 scientificBoundary;
    }

    public static class Gate14ReMED3V31KnownAnswerRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-v3-1-simplified-abi-amendment-20261017";
        private const string ParentAuthorizationId = "gate14re-me-d3-v3-cumulative-allocation-qualification-attempt-003";

        private const string ParentAuthorizationRelativePath = "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_Cumulative_Allocation_Qualification_Attempt_003_Authorization.v1.json";
        private const string AmendmentAuthorizationRelativePath = "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_1_Simplified_ABI_Amendment_Authorization.v1.json";
        private const string PlanRelativePath = "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_1_Simplified_Qualification_Plan.v1.md";
        private const string ContractRelativePath = "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.prospective.v2.json";
        private const string NativeSourceRelativePath = "Research/Gate14Re-ME/Native/v3/Gate14ReMED3AllocationCounterV31.cpp";
        private const string NativeBinaryRelativePath = "Assets/Plugins/x86_64/Gate14ReMED3AllocationCounterV31.dll";
        private const string ManagedWrapperRelativePath = "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMECumulativeAllocationCounterV2.cs";
        private const string HarnessRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMED3V31KnownAnswerRunnerV1.cs";
        private const string ProbeReceiptRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/repair-cycle-009-metadata-shape-probe-v1/probe-output/metadata-shape-probe-receipt.v1.json";
        private const string Cycle011ReceiptRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/repair-cycle-011-metadata-shape-probe-run-v1/cycle-receipt.v1.json";
        private const string CurrentRunnerRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs";
        private const string CurrentSchemaRelativePath = "Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json";
        private const string SixAlgorithmBindingRelativePath = "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json";
        private const string D3V2ContractRelativePath = "Research/Gate14Re-ME/Execution/v2/load-qualification-instrument-contract.v2.json";
        private const string D3V2SourceRelativePath = "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs";
        private const string PriorV3ContractRelativePath = "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.prospective.v1.json";
        private const string PriorV3SourceRelativePath = "Research/Gate14Re-ME/Native/v3/Gate14ReMED3AllocationCounterV3.cpp";
        private const string PriorV3BinaryRelativePath = "Assets/Plugins/x86_64/Gate14ReMED3AllocationCounterV3.dll";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/repair-cycle-013-d3-v3-1-known-answer-v1/known-answer-output";

        private const string ParentAuthorizationSha256 = "49a766a3e92ad197a1cf880d65766c24b2f2b21c426cf425e07f2d2a571d5bb2";
        private const string ProbeReceiptSha256 = "f6294cbd635901b481b71733d4a35cef5dd2051892578d5becd5ae4e2aeb9bbe";
        private const string Cycle011ReceiptSha256 = "d9a9e98fa86ab20ddf11baf2068e42655df7e580be3f88eced5d3b9712c6cc8c";
        private const string CurrentRunnerSha256 = "7bb9237e529f511ad12fcfcb8374db02818977092c3680b287aacc817d182033";
        private const string CurrentSchemaSha256 = "ed7d7bddf8e1da647a6085aa8e717d4ee0578ceff3fa7844dbd05c4e17aaea1c";
        private const string SixAlgorithmBindingSha256 = "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71";
        private const string D3V2ContractSha256 = "e402dfc90362a3ac07f5342d218f19c67d31d46f82bec584d5d817fbccb9f0bf";
        private const string D3V2SourceSha256 = "64e9ae20fdc5f03c9f737bc42a655f7488c359e3525b66f288f6ca963770a2ca";
        private const string PriorV3ContractSha256 = "a72d97113a4089f5d9532c6ac6d4bb817341339e5192afdaad6729a142cd5ff1";
        private const string PriorV3SourceSha256 = "12c41acc7dc106d314bd71d3bdc1d95e0346cc8467e0a1a1e1b3109093ef2a0d";
        private const string PriorV3BinarySha256 = "924d43ecbc03f4e606a26a3de1593e96fdf7d3607d6e9e3c8942c877f0575245";

        private const int EmptyWindowTrials = 64;
        private const int MaximumArrayOverheadBytes = 256;
        private const int MaximumArrayOverheadSpreadBytes = 64;
        private const int SmallObjectPayloadBytes = 64;
        private const int SmallObjectRepetitions = 4096;
        private const int GCReclamationPayloadBytes = 8 * 1024 * 1024;
        private const int CrossThreadPayloadBytes = 4 * 1024 * 1024;
        private const double MaximumRateRecomputeError = 1e-9;

        private static byte s_sink;
        private static int s_workerReady;
        private static int s_workerCommand;
        private static int s_workerDone;

        public static void Run()
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string outputDirectory = null;
            int exitCode = 3;
            List<Gate14ReMED3V31WindowRecordV1> windows = new List<Gate14ReMED3V31WindowRecordV1>(80);
            List<Gate14ReMED3V31StageRecordV1> stages = new List<Gate14ReMED3V31StageRecordV1>(12);
            Gate14ReMED3V31KnownAnswerReceiptV1 receipt = CreateBaseReceipt();

            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                outputDirectory = ResolveExactOutputDirectory(projectRoot, Required(arguments, "--g14me-d3v31-output-dir"));
                EnsureNewOutputDirectory(outputDirectory);

                receipt.currentStage = "frozen-bindings";
                ValidateBindings(projectRoot, arguments);
                receipt.bindings = BuildBindings(projectRoot);
                CompleteStage(stages, "frozen-bindings", true, "All versioned inputs, prior evidence, and protected later-stage files matched their bound hashes.");

                ExecuteKnownAnswer(receipt, stages, windows);
                receipt.status = "PASS_D3_V3_1_TRUE_CUMULATIVE_MANAGED_ALLOCATION_QUALIFICATION";
                receipt.passed = true;
                receipt.terminal = true;
                receipt.currentStage = "complete";
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.status = "FAILED_CLOSED_D3_V3_1_QUALIFICATION";
                receipt.passed = false;
                receipt.terminal = true;
                receipt.firstFailedCriterion = receipt.currentStage;
                receipt.exceptionType = exception.GetType().FullName;
                receipt.exactFailure = exception.Message;
                receipt.stackTrace = exception.ToString();
                UnityEngine.Debug.LogException(exception);
            }
            finally
            {
                receipt.completedAtUtc = DateTime.UtcNow.ToString("o");
                receipt.completedStages = stages.ToArray();
                receipt.allMeasuredWindows = windows.ToArray();
                receipt.measuredWindowCount = windows.Count;
                try
                {
                    if (!string.IsNullOrEmpty(outputDirectory) && Directory.Exists(outputDirectory))
                    {
                        WriteJsonAtomic(Path.Combine(outputDirectory, "d3-v3-1-known-answer-receipt.v1.json"), receipt);
                        UnityEngine.Debug.Log("Gate14Re-ME D3-v3.1 terminal receipt: " + receipt.status);
                    }
                }
                catch (Exception writeFailure)
                {
                    exitCode = 4;
                    UnityEngine.Debug.LogError("Unable to preserve D3-v3.1 terminal receipt: " + writeFailure);
                }
                EditorApplication.Exit(exitCode);
            }
        }

        private static Gate14ReMED3V31KnownAnswerReceiptV1 CreateBaseReceipt()
        {
            return new Gate14ReMED3V31KnownAnswerReceiptV1
            {
                schema = "gate14re-me-d3-v3-1-known-answer-receipt-v1",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                parentAuthorizationId = ParentAuthorizationId,
                status = "IN_PROGRESS",
                version = 1,
                createdAtUtc = DateTime.UtcNow.ToString("o"),
                terminal = false,
                passed = false,
                unityVersion = Application.unityVersion,
                runtimeVersion = Environment.Version.ToString(),
                operatingSystem = SystemInfo.operatingSystem,
                architecture = Environment.Is64BitProcess ? "x86-64" : "not-x86-64",
                currentStage = "startup",
                automaticRepairAuthorized = true,
                automaticRetryPerformedThisProcess = false,
                scientificBoundary = new Gate14ReMED3V31ScientificBoundaryV1
                {
                    priorEvidenceRetained = true,
                    priorDiagnosticsRerun = false,
                    currentQualificationRunnerModified = false,
                    currentOutputSchemaModified = false,
                    algorithmSourcesModified = false,
                    qualificationScheduleRows = 0,
                    qualificationInputs = 0,
                    anonymousIdentityMappings = 0,
                    qualificationMeasuredRootCreated = false,
                    algorithmLanes = 0,
                    formalObservations = 0,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false,
                    fallbackMetricUsed = false
                }
            };
        }

        private static void ExecuteKnownAnswer(
            Gate14ReMED3V31KnownAnswerReceiptV1 receipt,
            List<Gate14ReMED3V31StageRecordV1> stages,
            List<Gate14ReMED3V31WindowRecordV1> windows)
        {
            receipt.currentStage = "marker-and-uint32-abi-readiness";
            Gate14ReMED3V31MarkerControlV1 marker = new Gate14ReMED3V31MarkerControlV1
            {
                exactMarkerName = "GC.Alloc",
                pluginReady = Gate14ReMECumulativeAllocationCounterV2.IsReady(),
                markerSeen = Gate14ReMECumulativeAllocationCounterV2.MarkerSeen(),
                createCallbackRegistrationCode = Gate14ReMECumulativeAllocationCounterV2.CreateCallbackRegistrationCode(),
                markerCallbackRegistrationCode = Gate14ReMECumulativeAllocationCounterV2.MarkerCallbackRegistrationCode(),
                requiredMetadataType = "UInt32",
                requiredMetadataTypeValue = Gate14ReMECumulativeAllocationCounterV2.RequiredMetadataTypeValue(),
                requiredMetadataSizeBytes = Gate14ReMECumulativeAllocationCounterV2.RequiredMetadataSizeBytes()
            };
            marker.abiExportsMatchContract = marker.requiredMetadataTypeValue == 3 && marker.requiredMetadataSizeBytes == 4;
            marker.passed = marker.pluginReady && marker.markerSeen && marker.createCallbackRegistrationCode == 0 &&
                marker.markerCallbackRegistrationCode == 0 && marker.abiExportsMatchContract;
            receipt.markerAndMetadata = marker;
            CompleteStage(stages, receipt.currentStage, marker.passed, "Exact GC.Alloc listener readiness and UInt32/4 ABI export check.");
            Require(marker.passed, "Exact GC.Alloc marker registration or UInt32/4 ABI readiness failed.");

            receipt.currentStage = "measurement-path-warmup";
            WarmUpMeasurementPaths();
            FullCollection();
            CompleteStage(stages, receipt.currentStage, true, "Native lifecycle, allocation paths, timing path, worker-free collection path, and JIT paths warmed before controls.");

            receipt.currentStage = "empty-window-zero-response";
            List<Gate14ReMED3V31WindowRecordV1> emptyRecords = new List<Gate14ReMED3V31WindowRecordV1>(EmptyWindowTrials);
            for (int index = 0; index < EmptyWindowTrials; index++)
            {
                Gate14ReMED3V31WindowRecordV1 record = MeasureEmptyWindow(index + 1);
                emptyRecords.Add(record);
                windows.Add(record);
            }
            receipt.emptyWindow = EvaluateEmptyControl(emptyRecords);
            CompleteStage(stages, receipt.currentStage, receipt.emptyWindow.passed, "64 warmed empty windows evaluated.");
            Require(receipt.emptyWindow.passed, "Empty-window zero-response criterion failed.");

            receipt.currentStage = "known-array-scale";
            int[] requestedArraySizes = { 4096, 65536, 1048576 };
            Gate14ReMED3V31WindowRecordV1[] arrayRecords = new Gate14ReMED3V31WindowRecordV1[requestedArraySizes.Length];
            for (int index = 0; index < requestedArraySizes.Length; index++)
            {
                arrayRecords[index] = MeasureArrayWindow("known-array", index + 1, requestedArraySizes[index]);
                windows.Add(arrayRecords[index]);
            }
            receipt.knownArrayScale = EvaluateArrayScale(arrayRecords);
            CompleteStage(stages, receipt.currentStage, receipt.knownArrayScale.passed, "4 KiB, 64 KiB, and 1 MiB raw windows evaluated before fail-closed decision.");
            Require(receipt.knownArrayScale.passed, "Known-array bounded-overhead or monotonic-scale criterion failed.");

            receipt.currentStage = "repeated-small-object-scaling";
            Gate14ReMED3V31WindowRecordV1 oneSmall = MeasureArrayWindow("small-object-single", 1, SmallObjectPayloadBytes);
            windows.Add(oneSmall);
            Gate14ReMED3V31WindowRecordV1 repeatedSmall = MeasureRepeatedWindow(
                "small-object-repeated", 1, SmallObjectPayloadBytes, SmallObjectRepetitions);
            windows.Add(repeatedSmall);
            receipt.repeatedSmallObjects = EvaluateRepeatedControl(oneSmall, repeatedSmall);
            CompleteStage(stages, receipt.currentStage, receipt.repeatedSmallObjects.passed, "Single-object and 4096-object raw windows evaluated.");
            Require(receipt.repeatedSmallObjects.passed, "Repeated-small-object exact byte/event scaling criterion failed.");

            receipt.currentStage = "gc-cumulative-behavior";
            receipt.gcCumulativeBehavior = MeasureGCControl();
            windows.Add(receipt.gcCumulativeBehavior.finalWindow);
            CompleteStage(stages, receipt.currentStage, receipt.gcCumulativeBehavior.passed,
                "Nondecrease and event-conditioned byte consistency evaluated across forced collection.");
            Require(receipt.gcCumulativeBehavior.passed, "GC cumulative-counter behavior criterion failed.");

            receipt.currentStage = "thread-attribution";
            long harnessThreadId = Gate14ReMECumulativeAllocationCounterV2.CurrentNativeThreadId();
            Thread worker = StartAndWarmWorker();
            Gate14ReMED3V31WindowRecordV1 crossThread;
            try
            {
                FullCollection();
                crossThread = MeasureCrossThreadWindow();
            }
            finally
            {
                StopWorker(worker);
            }
            windows.Add(crossThread);
            receipt.threadAttribution = EvaluateThreadControl(arrayRecords[2], crossThread, harnessThreadId);
            CompleteStage(stages, receipt.currentStage, receipt.threadAttribution.passed,
                "Reused 1 MiB owner record and 4 MiB worker allocation evaluated.");
            Require(receipt.threadAttribution.passed, "Owner-thread attribution or cross-thread exclusion criterion failed.");

            receipt.currentStage = "byte-and-rate-formula";
            receipt.byteAndRateFormula = EvaluateFormulaControl(arrayRecords[2]);
            CompleteStage(stages, receipt.currentStage, receipt.byteAndRateFormula.passed,
                "Reused the 1 MiB known-array raw record; no separate rate-payload window was run.");
            Require(receipt.byteAndRateFormula.passed, "Byte/rate formula criterion failed.");

            receipt.currentStage = "global-metadata-and-overflow-integrity";
            bool invalidZero = true;
            bool overflowZero = true;
            bool positive = false;
            for (int index = 0; index < windows.Count; index++)
            {
                invalidZero &= windows[index].invalidMetadataEventCount == 0;
                overflowZero &= windows[index].counterOverflowCount == 0;
                positive |= windows[index].managedAllocationEventCount > 0 && windows[index].managedAllocationBytes > 0;
            }
            receipt.allInvalidMetadataCountsZero = invalidZero;
            receipt.allOverflowCountsZero = overflowZero;
            receipt.observedPositiveUInt32Metadata = positive;
            receipt.markerAndMetadata.observedPositiveMetadata = positive;
            receipt.markerAndMetadata.passed = receipt.markerAndMetadata.passed && invalidZero && positive;
            bool globalPassed = invalidZero && overflowZero && positive && receipt.markerAndMetadata.passed;
            CompleteStage(stages, receipt.currentStage, globalPassed,
                "All collected windows checked for strict UInt32 metadata acceptance, positive response, and checked-counter overflow.");
            Require(globalPassed, "Invalid metadata, counter overflow, or absence of positive UInt32 allocation-size observations.");
        }

        private static void WarmUpMeasurementPaths()
        {
            Gate14ReMECumulativeAllocationCounterV2.Snapshot ignored;
            Require(Gate14ReMECumulativeAllocationCounterV2.BeginWindow() == 0, "Warm-up BeginWindow failed.");
            Require(Gate14ReMECumulativeAllocationCounterV2.SnapshotWindow(out ignored) == 0, "Warm-up SnapshotWindow failed.");
            Require(Gate14ReMECumulativeAllocationCounterV2.EndWindow(out ignored) == 0, "Warm-up EndWindow failed.");
            AllocateOne(16);
            AllocateRepeated(16, 2);
            Stopwatch.GetTimestamp();
            Thread.SpinWait(16);
            FullCollection();
        }

        private static Gate14ReMED3V31WindowRecordV1 MeasureEmptyWindow(int trial)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            Gate14ReMECumulativeAllocationCounterV2.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native empty-window lifecycle failed.");
            return CreateWindowRecord("empty-window", trial, 0, 0, snapshot, start, end);
        }

        private static Gate14ReMED3V31WindowRecordV1 MeasureArrayWindow(string controlId, int trial, int payloadBytes)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            AllocateOne(payloadBytes);
            Gate14ReMECumulativeAllocationCounterV2.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native array-window lifecycle failed: " + controlId);
            return CreateWindowRecord(controlId, trial, payloadBytes, 1, snapshot, start, end);
        }

        private static Gate14ReMED3V31WindowRecordV1 MeasureRepeatedWindow(
            string controlId, int trial, int payloadBytes, int repetitions)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            AllocateRepeated(payloadBytes, repetitions);
            Gate14ReMECumulativeAllocationCounterV2.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native repeated-object window lifecycle failed.");
            return CreateWindowRecord(controlId, trial, checked(payloadBytes * repetitions), repetitions, snapshot, start, end);
        }

        private static Gate14ReMED3V31GCControlV1 MeasureGCControl()
        {
            FullCollection();
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            AllocateOne(GCReclamationPayloadBytes);
            Gate14ReMECumulativeAllocationCounterV2.Snapshot before;
            int beforeCode = Gate14ReMECumulativeAllocationCounterV2.SnapshotWindow(out before);
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            Gate14ReMECumulativeAllocationCounterV2.Snapshot after;
            int afterCode = Gate14ReMECumulativeAllocationCounterV2.SnapshotWindow(out after);
            Gate14ReMECumulativeAllocationCounterV2.Snapshot final;
            int endCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out final);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && beforeCode == 0 && afterCode == 0 && endCode == 0,
                "Native GC-control window lifecycle failed.");

            bool nondecrease = after.ManagedAllocationBytes >= before.ManagedAllocationBytes &&
                after.ManagedAllocationEventCount >= before.ManagedAllocationEventCount &&
                final.ManagedAllocationBytes >= after.ManagedAllocationBytes &&
                final.ManagedAllocationEventCount >= after.ManagedAllocationEventCount;
            bool firstConsistent = TransitionConsistent(before.ManagedAllocationBytes, before.ManagedAllocationEventCount,
                after.ManagedAllocationBytes, after.ManagedAllocationEventCount);
            bool secondConsistent = TransitionConsistent(after.ManagedAllocationBytes, after.ManagedAllocationEventCount,
                final.ManagedAllocationBytes, final.ManagedAllocationEventCount);
            bool positive = before.ManagedAllocationBytes >= GCReclamationPayloadBytes && before.ManagedAllocationEventCount >= 1;
            bool clean = final.InvalidMetadataEventCount == 0 && final.CounterOverflowCount == 0;

            return new Gate14ReMED3V31GCControlV1
            {
                payloadBytes = GCReclamationPayloadBytes,
                finalWindow = CreateWindowRecord("gc-cumulative-behavior", 1, GCReclamationPayloadBytes, 1, final, start, end),
                beforeCollectionBytes = before.ManagedAllocationBytes,
                beforeCollectionEvents = before.ManagedAllocationEventCount,
                afterCollectionBytes = after.ManagedAllocationBytes,
                afterCollectionEvents = after.ManagedAllocationEventCount,
                endWindowBytes = final.ManagedAllocationBytes,
                endWindowEvents = final.ManagedAllocationEventCount,
                countersNeverDecrease = nondecrease,
                beforeToAfterConditionalConsistency = firstConsistent,
                afterToEndConditionalConsistency = secondConsistent,
                passed = positive && clean && nondecrease && firstConsistent && secondConsistent
            };
        }

        private static bool TransitionConsistent(long priorBytes, long priorEvents, long laterBytes, long laterEvents)
        {
            if (laterEvents == priorEvents) return laterBytes == priorBytes;
            return laterEvents > priorEvents && laterBytes > priorBytes;
        }

        private static Gate14ReMED3V31WindowRecordV1 MeasureCrossThreadWindow()
        {
            Volatile.Write(ref s_workerDone, 0);
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            Volatile.Write(ref s_workerCommand, 2);
            bool completed = SpinUntilEqual(ref s_workerDone, 2, Stopwatch.Frequency * 30L);
            Gate14ReMECumulativeAllocationCounterV2.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Volatile.Write(ref s_workerCommand, 0);
            Require(completed, "Worker-thread allocation timed out.");
            Require(beginCode == 0 && endCode == 0, "Native cross-thread window lifecycle failed.");
            return CreateWindowRecord("cross-thread-exclusion", 1, CrossThreadPayloadBytes, 1, snapshot, start, end);
        }

        private static Thread StartAndWarmWorker()
        {
            Volatile.Write(ref s_workerReady, 0);
            Volatile.Write(ref s_workerCommand, 0);
            Volatile.Write(ref s_workerDone, 0);
            Thread worker = new Thread(WorkerMain);
            worker.IsBackground = true;
            worker.Name = "Gate14Re-ME-D3-v3.1-known-answer-worker";
            worker.Start();
            Require(SpinUntilEqual(ref s_workerReady, 1, Stopwatch.Frequency * 30L), "Worker did not become ready.");
            Volatile.Write(ref s_workerCommand, 1);
            Require(SpinUntilEqual(ref s_workerDone, 1, Stopwatch.Frequency * 30L), "Worker warm-up timed out.");
            Volatile.Write(ref s_workerCommand, 0);
            Volatile.Write(ref s_workerDone, 0);
            return worker;
        }

        private static void StopWorker(Thread worker)
        {
            if (worker == null) return;
            Volatile.Write(ref s_workerCommand, 9);
            Require(worker.Join(30000), "Worker failed to terminate.");
        }

        private static void WorkerMain()
        {
            Volatile.Write(ref s_workerReady, 1);
            for (;;)
            {
                int command = Volatile.Read(ref s_workerCommand);
                if (command == 9) return;
                if (command == 1 && Volatile.Read(ref s_workerDone) == 0)
                {
                    AllocateOne(64);
                    Volatile.Write(ref s_workerDone, 1);
                }
                else if (command == 2 && Volatile.Read(ref s_workerDone) == 0)
                {
                    AllocateOne(CrossThreadPayloadBytes);
                    Volatile.Write(ref s_workerDone, 2);
                }
                else
                {
                    Thread.SpinWait(64);
                }
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void AllocateOne(int payloadBytes)
        {
            byte[] value = new byte[payloadBytes];
            value[0] = 1;
            value[value.Length - 1] = 2;
            s_sink ^= value[0];
            GC.KeepAlive(value);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void AllocateRepeated(int payloadBytes, int repetitions)
        {
            for (int index = 0; index < repetitions; index++) AllocateOne(payloadBytes);
        }

        private static void FullCollection()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        private static bool SpinUntilEqual(ref int location, int expected, long timeoutTicks)
        {
            long started = Stopwatch.GetTimestamp();
            while (Volatile.Read(ref location) != expected)
            {
                if (Stopwatch.GetTimestamp() - started > timeoutTicks) return false;
                Thread.SpinWait(64);
            }
            return true;
        }

        private static Gate14ReMED3V31WindowRecordV1 CreateWindowRecord(
            string controlId,
            int trial,
            int requestedPayloadBytes,
            int requestedAllocationCount,
            Gate14ReMECumulativeAllocationCounterV2.Snapshot snapshot,
            long start,
            long end)
        {
            long elapsed = end - start;
            double rate = elapsed > 0
                ? snapshot.ManagedAllocationBytes * (double)Stopwatch.Frequency / elapsed
                : double.NaN;
            return new Gate14ReMED3V31WindowRecordV1
            {
                controlId = controlId,
                trial = trial,
                requestedPayloadBytes = requestedPayloadBytes,
                requestedAllocationCount = requestedAllocationCount,
                managedAllocationBytes = snapshot.ManagedAllocationBytes,
                managedAllocationEventCount = snapshot.ManagedAllocationEventCount,
                foreignThreadAllocationBytes = snapshot.ForeignThreadAllocationBytes,
                foreignThreadAllocationEventCount = snapshot.ForeignThreadAllocationEventCount,
                invalidMetadataEventCount = snapshot.InvalidMetadataEventCount,
                counterOverflowCount = snapshot.CounterOverflowCount,
                ownerNativeThreadId = snapshot.OwnerNativeThreadId,
                windowStartStopwatchTicks = start,
                windowEndStopwatchTicks = end,
                windowElapsedStopwatchTicks = elapsed,
                stopwatchFrequency = Stopwatch.Frequency,
                managedAllocationRateBytesPerSecond = rate
            };
        }

        private static Gate14ReMED3V31EmptyControlV1 EvaluateEmptyControl(List<Gate14ReMED3V31WindowRecordV1> records)
        {
            long maximumBytes = 0;
            long maximumEvents = 0;
            bool zero = true;
            bool clean = true;
            for (int index = 0; index < records.Count; index++)
            {
                maximumBytes = Math.Max(maximumBytes, records[index].managedAllocationBytes);
                maximumEvents = Math.Max(maximumEvents, records[index].managedAllocationEventCount);
                zero &= records[index].managedAllocationBytes == 0 && records[index].managedAllocationEventCount == 0;
                clean &= records[index].invalidMetadataEventCount == 0 && records[index].counterOverflowCount == 0;
            }
            return new Gate14ReMED3V31EmptyControlV1
            {
                trials = records.Count,
                maximumOwnerBytes = maximumBytes,
                maximumOwnerEvents = maximumEvents,
                allOwnerResponsesZero = zero,
                allDiagnosticsClean = clean,
                passed = records.Count == EmptyWindowTrials && zero && clean
            };
        }

        private static Gate14ReMED3V31ArrayControlV1 EvaluateArrayScale(Gate14ReMED3V31WindowRecordV1[] records)
        {
            long minimumOverhead = long.MaxValue;
            long maximumOverhead = long.MinValue;
            bool withinBounds = true;
            bool increasing = true;
            for (int index = 0; index < records.Length; index++)
            {
                long overhead = records[index].managedAllocationBytes - records[index].requestedPayloadBytes;
                minimumOverhead = Math.Min(minimumOverhead, overhead);
                maximumOverhead = Math.Max(maximumOverhead, overhead);
                withinBounds &= overhead >= 0 && overhead <= MaximumArrayOverheadBytes;
                withinBounds &= records[index].managedAllocationEventCount >= 1;
                withinBounds &= records[index].invalidMetadataEventCount == 0 && records[index].counterOverflowCount == 0;
                if (index > 0) increasing &= records[index].managedAllocationBytes > records[index - 1].managedAllocationBytes;
            }
            long spread = maximumOverhead - minimumOverhead;
            bool spreadPassed = spread <= MaximumArrayOverheadSpreadBytes;
            return new Gate14ReMED3V31ArrayControlV1
            {
                records = records,
                minimumOverheadBytes = minimumOverhead,
                maximumOverheadBytes = maximumOverhead,
                overheadSpreadBytes = spread,
                allWithinPayloadAndOverheadBounds = withinBounds,
                strictlyIncreasing = increasing,
                overheadSpreadPassed = spreadPassed,
                passed = withinBounds && increasing && spreadPassed
            };
        }

        private static Gate14ReMED3V31RepeatedControlV1 EvaluateRepeatedControl(
            Gate14ReMED3V31WindowRecordV1 oneObject,
            Gate14ReMED3V31WindowRecordV1 repeatedObjects)
        {
            long expectedBytes = checked(oneObject.managedAllocationBytes * (long)SmallObjectRepetitions);
            long expectedEvents = checked(oneObject.managedAllocationEventCount * (long)SmallObjectRepetitions);
            bool byteScaling = oneObject.managedAllocationBytes > 0 && repeatedObjects.managedAllocationBytes == expectedBytes;
            bool eventScaling = oneObject.managedAllocationEventCount > 0 && repeatedObjects.managedAllocationEventCount == expectedEvents;
            bool clean = oneObject.invalidMetadataEventCount == 0 && repeatedObjects.invalidMetadataEventCount == 0 &&
                oneObject.counterOverflowCount == 0 && repeatedObjects.counterOverflowCount == 0;
            return new Gate14ReMED3V31RepeatedControlV1
            {
                payloadBytesPerObject = SmallObjectPayloadBytes,
                repetitions = SmallObjectRepetitions,
                oneObject = oneObject,
                repeatedObjects = repeatedObjects,
                expectedRepeatedBytes = expectedBytes,
                expectedRepeatedEvents = expectedEvents,
                exactByteScalingPassed = byteScaling,
                exactEventScalingPassed = eventScaling,
                passed = clean && byteScaling && eventScaling
            };
        }

        private static Gate14ReMED3V31ThreadControlV1 EvaluateThreadControl(
            Gate14ReMED3V31WindowRecordV1 ownerRecord,
            Gate14ReMED3V31WindowRecordV1 crossThread,
            long harnessNativeThreadId)
        {
            bool ownerId = ownerRecord.ownerNativeThreadId == harnessNativeThreadId;
            bool ownerPositive = ownerRecord.managedAllocationBytes >= 1048576 && ownerRecord.managedAllocationEventCount >= 1;
            bool excluded = crossThread.managedAllocationBytes == 0 && crossThread.managedAllocationEventCount == 0;
            bool foreignPositive = crossThread.foreignThreadAllocationBytes >= CrossThreadPayloadBytes &&
                crossThread.foreignThreadAllocationEventCount >= 1;
            bool clean = ownerRecord.invalidMetadataEventCount == 0 && crossThread.invalidMetadataEventCount == 0 &&
                ownerRecord.counterOverflowCount == 0 && crossThread.counterOverflowCount == 0;
            return new Gate14ReMED3V31ThreadControlV1
            {
                reusedOneMiBOwnerRecord = ownerRecord,
                crossThreadRecord = crossThread,
                harnessNativeThreadId = harnessNativeThreadId,
                crossThreadRequestedPayloadBytes = CrossThreadPayloadBytes,
                ownerIdPassed = ownerId,
                ownerPositiveResponsePassed = ownerPositive,
                crossThreadOwnerExclusionPassed = excluded,
                crossThreadForeignResponsePassed = foreignPositive,
                passed = clean && ownerId && ownerPositive && excluded && foreignPositive
            };
        }

        private static Gate14ReMED3V31FormulaControlV1 EvaluateFormulaControl(Gate14ReMED3V31WindowRecordV1 record)
        {
            double recomputed = record.managedAllocationBytes * (double)record.stopwatchFrequency /
                record.windowElapsedStopwatchTicks;
            double error = Math.Abs(record.managedAllocationRateBytesPerSecond - recomputed);
            bool finitePositive = record.managedAllocationBytes > 0 && record.windowElapsedStopwatchTicks > 0 &&
                record.stopwatchFrequency > 0 && !double.IsNaN(record.managedAllocationRateBytesPerSecond) &&
                !double.IsInfinity(record.managedAllocationRateBytesPerSecond) &&
                record.managedAllocationRateBytesPerSecond > 0;
            bool recomputePassed = error <= MaximumRateRecomputeError;
            return new Gate14ReMED3V31FormulaControlV1
            {
                reusedControlId = "known-array/trial-3/1048576-bytes",
                reusedOneMiBArrayRecord = record,
                independentlyRecomputedRateBytesPerSecond = recomputed,
                absoluteRecomputeError = error,
                maximumAbsoluteRecomputeError = MaximumRateRecomputeError,
                finitePositiveRatePassed = finitePositive,
                recomputePassed = recomputePassed,
                passed = finitePositive && recomputePassed
            };
        }

        private static void CompleteStage(
            List<Gate14ReMED3V31StageRecordV1> stages,
            string stageId,
            bool passed,
            string detail)
        {
            stages.Add(new Gate14ReMED3V31StageRecordV1
            {
                stageId = stageId,
                completed = true,
                passed = passed,
                detail = detail,
                completedAtUtc = DateTime.UtcNow.ToString("o")
            });
        }

        private static Gate14ReMED3V31FileBindingV1[] BuildBindings(string projectRoot)
        {
            string[] roles =
            {
                "parent-authorization", "abi-amendment-authorization", "simplified-plan", "prospective-contract",
                "native-source", "native-binary", "managed-wrapper", "known-answer-harness",
                "metadata-probe-receipt", "repair-cycle-011-receipt", "protected-qualification-runner",
                "protected-output-schema", "protected-six-algorithm-binding", "retained-d3-v2-contract",
                "retained-d3-v2-source", "retained-prior-v3-contract", "retained-prior-v3-source", "retained-prior-v3-binary"
            };
            string[] paths =
            {
                ParentAuthorizationRelativePath, AmendmentAuthorizationRelativePath, PlanRelativePath, ContractRelativePath,
                NativeSourceRelativePath, NativeBinaryRelativePath, ManagedWrapperRelativePath, HarnessRelativePath,
                ProbeReceiptRelativePath, Cycle011ReceiptRelativePath, CurrentRunnerRelativePath, CurrentSchemaRelativePath,
                SixAlgorithmBindingRelativePath, D3V2ContractRelativePath, D3V2SourceRelativePath, PriorV3ContractRelativePath,
                PriorV3SourceRelativePath, PriorV3BinaryRelativePath
            };
            Gate14ReMED3V31FileBindingV1[] result = new Gate14ReMED3V31FileBindingV1[paths.Length];
            for (int index = 0; index < paths.Length; index++)
            {
                result[index] = new Gate14ReMED3V31FileBindingV1
                {
                    role = roles[index],
                    relativePath = paths[index],
                    sha256 = Sha256File(Path.Combine(projectRoot, paths[index]))
                };
            }
            return result;
        }

        private static void ValidateBindings(string projectRoot, Dictionary<string, string> arguments)
        {
            Require(Application.unityVersion == "2022.3.30f1c1", "Unity version mismatch.");
            Require(Environment.Is64BitProcess, "Unity process is not x86-64.");

            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-amendment",
                "--g14me-d3v31-amendment-sha256", AmendmentAuthorizationRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-plan",
                "--g14me-d3v31-plan-sha256", PlanRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-contract",
                "--g14me-d3v31-contract-sha256", ContractRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-native-source",
                "--g14me-d3v31-native-source-sha256", NativeSourceRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-native-binary",
                "--g14me-d3v31-native-binary-sha256", NativeBinaryRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-managed-wrapper",
                "--g14me-d3v31-managed-wrapper-sha256", ManagedWrapperRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v31-harness",
                "--g14me-d3v31-harness-sha256", HarnessRelativePath);

            ValidateFixedHash(projectRoot, ParentAuthorizationRelativePath, ParentAuthorizationSha256);
            ValidateFixedHash(projectRoot, ProbeReceiptRelativePath, ProbeReceiptSha256);
            ValidateFixedHash(projectRoot, Cycle011ReceiptRelativePath, Cycle011ReceiptSha256);
            ValidateFixedHash(projectRoot, CurrentRunnerRelativePath, CurrentRunnerSha256);
            ValidateFixedHash(projectRoot, CurrentSchemaRelativePath, CurrentSchemaSha256);
            ValidateFixedHash(projectRoot, SixAlgorithmBindingRelativePath, SixAlgorithmBindingSha256);
            ValidateFixedHash(projectRoot, D3V2ContractRelativePath, D3V2ContractSha256);
            ValidateFixedHash(projectRoot, D3V2SourceRelativePath, D3V2SourceSha256);
            ValidateFixedHash(projectRoot, PriorV3ContractRelativePath, PriorV3ContractSha256);
            ValidateFixedHash(projectRoot, PriorV3SourceRelativePath, PriorV3SourceSha256);
            ValidateFixedHash(projectRoot, PriorV3BinaryRelativePath, PriorV3BinarySha256);

            Gate14ReMED3V31AuthorizationHeaderV1 amendment = JsonUtility.FromJson<Gate14ReMED3V31AuthorizationHeaderV1>(
                File.ReadAllText(Path.Combine(projectRoot, AmendmentAuthorizationRelativePath), Encoding.UTF8));
            Require(amendment != null &&
                amendment.schema == "gate14re-me-d3-v3-1-simplified-abi-amendment-authorization-v1" &&
                amendment.studyId == StudyId && amendment.authorizationId == AuthorizationId &&
                amendment.status == "AUTHORIZED_D3_V3_1_SIMPLIFIED_ABI_QUALIFICATION_CONTINUATION",
                "D3-v3.1 amendment authorization semantic binding mismatch.");

            Gate14ReMED3V31ContractHeaderV1 contract = JsonUtility.FromJson<Gate14ReMED3V31ContractHeaderV1>(
                File.ReadAllText(Path.Combine(projectRoot, ContractRelativePath), Encoding.UTF8));
            Require(contract != null &&
                contract.schema == "gate14re-me-d3-v3-1-cumulative-managed-allocation-contract-prospective-v2" &&
                contract.studyId == StudyId && contract.endpointId == "D3" && contract.semanticVersion == "3.1" &&
                contract.status == "PROSPECTIVE_UNQUALIFIED_D3_V3_1",
                "D3-v3.1 prospective contract semantic binding mismatch.");
        }

        private static void ValidateFixedHash(string projectRoot, string relativePath, string expectedSha256)
        {
            string path = Path.Combine(projectRoot, relativePath);
            Require(File.Exists(path), "Bound file is absent: " + relativePath);
            Require(Sha256File(path) == expectedSha256, "Frozen hash drift: " + relativePath);
        }

        private static void ValidateArgumentBoundFile(
            string projectRoot,
            Dictionary<string, string> arguments,
            string pathArgument,
            string hashArgument,
            string expectedRelativePath)
        {
            string actualPath = Path.GetFullPath(Required(arguments, pathArgument));
            string expectedPath = Path.GetFullPath(Path.Combine(projectRoot, expectedRelativePath));
            Require(string.Equals(actualPath, expectedPath, StringComparison.OrdinalIgnoreCase),
                "Bound path mismatch: " + pathArgument);
            Require(File.Exists(actualPath), "Bound file is absent: " + expectedRelativePath);
            Require(Sha256File(actualPath) == RequiredSha256(arguments, hashArgument),
                "Bound hash mismatch: " + expectedRelativePath);
        }

        private static string ResolveExactOutputDirectory(string projectRoot, string provided)
        {
            string actual = Path.GetFullPath(provided);
            string expected = Path.GetFullPath(Path.Combine(projectRoot, ExpectedOutputRelativePath));
            Require(string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase), "Known-answer output path mismatch.");
            return actual;
        }

        private static void EnsureNewOutputDirectory(string path)
        {
            if (Directory.Exists(path) || File.Exists(path))
                throw new InvalidOperationException("Refusing to overwrite existing known-answer output path: " + path);
            Directory.CreateDirectory(path);
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                if (!args[index].StartsWith("--", StringComparison.Ordinal)) continue;
                if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal))
                    throw new InvalidOperationException("Missing value for command argument: " + args[index]);
                values.Add(args[index], args[++index]);
            }
            return values;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            if (!arguments.TryGetValue(key, out value) || string.IsNullOrWhiteSpace(value))
                throw new InvalidOperationException("Required command argument is missing: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> arguments, string key)
        {
            string value = Required(arguments, key).ToLowerInvariant();
            if (value.Length != 64) throw new InvalidOperationException("Invalid SHA-256 value: " + key);
            for (int index = 0; index < value.Length; index++)
            {
                char c = value[index];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
                    throw new InvalidOperationException("Invalid SHA-256 value: " + key);
            }
            return value;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] hash = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(hash.Length * 2);
                for (int index = 0; index < hash.Length; index++) builder.Append(hash[index].ToString("x2"));
                return builder.ToString();
            }
        }

        private static void WriteJsonAtomic<T>(string path, T value)
        {
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite terminal receipt: " + path);
            string temporary = path + ".tmp." + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + "\n", new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
#endif
