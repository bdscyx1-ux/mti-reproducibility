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

namespace DDM.Research.Editor.Attempt003
{
    [Serializable]
    internal sealed class Gate14ReMED3V3AuthorizationHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ContractHeaderV1
    {
        public string schema;
        public string studyId;
        public string endpointId;
        public int semanticVersion;
        public string status;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3WindowRecordV1
    {
        public string controlId;
        public int trial;
        public int requestedPayloadBytes;
        public long managedAllocationBytes;
        public long managedAllocationEventCount;
        public long foreignThreadAllocationBytes;
        public long foreignThreadAllocationEventCount;
        public long invalidMetadataEventCount;
        public long counterOverflowCount;
        public long windowStartStopwatchTicks;
        public long windowEndStopwatchTicks;
        public long windowElapsedStopwatchTicks;
        public long stopwatchFrequency;
        public double managedAllocationRateBytesPerSecond;
        public long ownerNativeThreadId;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3MarkerQualificationV1
    {
        public string exactMarkerName;
        public bool pluginReady;
        public bool markerSeen;
        public int createCallbackRegistrationCode;
        public int markerCallbackRegistrationCode;
        public string requiredMetadataType;
        public int requiredMetadataSizeBytes;
        public bool observedPositiveMetadata;
        public bool metadataShapePassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3EmptyControlV1
    {
        public int trials;
        public long maximumOwnerBytes;
        public long maximumOwnerEvents;
        public bool allOwnerResponsesZero;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ArrayScaleControlV1
    {
        public Gate14ReMED3V3WindowRecordV1[] records;
        public long minimumOverheadBytes;
        public long maximumOverheadBytes;
        public long overheadSpreadBytes;
        public bool allWithinPayloadAndOverheadBounds;
        public bool strictlyIncreasing;
        public bool overheadSpreadPassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3RepeatedSmallObjectControlV1
    {
        public int payloadBytesPerObject;
        public int repetitions;
        public Gate14ReMED3V3WindowRecordV1 oneObject;
        public Gate14ReMED3V3WindowRecordV1 repeatedObjects;
        public long expectedRepeatedBytes;
        public long expectedRepeatedEvents;
        public bool exactByteScalingPassed;
        public bool exactEventScalingPassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3GCReclamationControlV1
    {
        public int payloadBytes;
        public Gate14ReMED3V3WindowRecordV1 finalWindow;
        public long beforeCollectionBytes;
        public long beforeCollectionEvents;
        public long afterCollectionBytes;
        public long afterCollectionEvents;
        public long endWindowBytes;
        public long endWindowEvents;
        public bool nondecreasePassed;
        public bool exactStabilityPassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ThreadAttributionControlV1
    {
        public Gate14ReMED3V3WindowRecordV1 sameThread;
        public Gate14ReMED3V3WindowRecordV1 crossThread;
        public long harnessNativeThreadId;
        public int crossThreadRequestedPayloadBytes;
        public bool sameThreadOwnerIdPassed;
        public bool sameThreadPositiveResponsePassed;
        public bool crossThreadOwnerExclusionPassed;
        public bool crossThreadForeignResponsePassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3FormulaControlV1
    {
        public Gate14ReMED3V3WindowRecordV1 record;
        public double independentlyRecomputedRateBytesPerSecond;
        public double absoluteRecomputeError;
        public double maximumAbsoluteRecomputeError;
        public bool finitePositiveRatePassed;
        public bool recomputePassed;
        public bool passed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3BindingsV1
    {
        public string authorizationRelativePath;
        public string authorizationSha256;
        public string planRelativePath;
        public string planSha256;
        public string prospectiveContractRelativePath;
        public string prospectiveContractSha256;
        public string nativeSourceRelativePath;
        public string nativeSourceSha256;
        public string nativeBinaryRelativePath;
        public string nativeBinarySha256;
        public string managedWrapperRelativePath;
        public string managedWrapperSha256;
        public string knownAnswerHarnessRelativePath;
        public string knownAnswerHarnessSha256;
        public string currentQualificationRunnerSha256;
        public string currentOutputSchemaSha256;
        public string sixAlgorithmBindingSha256;
        public string d3V2ContractSha256;
        public string d3V2SourceSha256;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ScientificBoundaryV1
    {
        public bool d3V2EvidenceRetained;
        public bool currentQualificationRunnerModified;
        public bool currentOutputSchemaModified;
        public bool algorithmSourcesModified;
        public int qualificationScheduleRows;
        public int qualificationInputs;
        public int anonymousIdentityMappings;
        public bool qualificationMeasuredRootCreated;
        public int qualificationObservations;
        public int algorithmLanes;
        public int formalObservations;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
        public bool fallbackMetricUsed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3KnownAnswerReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public int version;
        public string createdAtUtc;
        public string unityVersion;
        public string runtimeVersion;
        public string operatingSystem;
        public string architecture;
        public Gate14ReMED3V3BindingsV1 bindings;
        public Gate14ReMED3V3MarkerQualificationV1 markerAndMetadata;
        public Gate14ReMED3V3EmptyControlV1 emptyWindow;
        public Gate14ReMED3V3ArrayScaleControlV1 knownArrayScale;
        public Gate14ReMED3V3RepeatedSmallObjectControlV1 repeatedSmallObjects;
        public Gate14ReMED3V3GCReclamationControlV1 gcReclamationInvariance;
        public Gate14ReMED3V3ThreadAttributionControlV1 threadAttribution;
        public Gate14ReMED3V3FormulaControlV1 byteAndRateFormula;
        public Gate14ReMED3V3WindowRecordV1[] allMeasuredWindows;
        public int measuredWindowCount;
        public bool allInvalidMetadataCountsZero;
        public bool allOverflowCountsZero;
        public Gate14ReMED3V3ScientificBoundaryV1 scientificBoundary;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3FailureReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string failedAtUtc;
        public string exceptionType;
        public string exactReason;
        public string stackTrace;
        public bool automaticRetryPerformed;
        public bool fallbackMetricUsed;
        public bool algorithmLaneExecuted;
        public bool qualificationMeasuredRootCreated;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
    }

    public static class Gate14ReMED3V3KnownAnswerRunnerV2
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-v3-cumulative-allocation-qualification-attempt-003";
        private const string AuthorizationRelativePath = "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_Cumulative_Allocation_Qualification_Attempt_003_Authorization.v1.json";
        private const string PlanRelativePath = "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_Cumulative_Allocation_Qualification_Attempt_003_Plan.v1.md";
        private const string ContractRelativePath = "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.prospective.v1.json";
        private const string NativeSourceRelativePath = "Research/Gate14Re-ME/Native/v3/Gate14ReMED3AllocationCounterV3.cpp";
        private const string NativeBinaryRelativePath = "Assets/Plugins/x86_64/Gate14ReMED3AllocationCounterV3.dll";
        private const string ManagedWrapperRelativePath = "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMECumulativeAllocationCounterV1.cs";
        private const string HarnessRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMED3V3KnownAnswerRunnerV2.cs";
        private const string CurrentRunnerRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs";
        private const string CurrentSchemaRelativePath = "Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json";
        private const string SixAlgorithmBindingRelativePath = "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json";
        private const string D3V2ContractRelativePath = "Research/Gate14Re-ME/Execution/v2/load-qualification-instrument-contract.v2.json";
        private const string D3V2SourceRelativePath = "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/d3-known-answer";

        private const string CurrentRunnerSha256 = "7bb9237e529f511ad12fcfcb8374db02818977092c3680b287aacc817d182033";
        private const string CurrentSchemaSha256 = "ed7d7bddf8e1da647a6085aa8e717d4ee0578ceff3fa7844dbd05c4e17aaea1c";
        private const string SixAlgorithmBindingSha256 = "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71";
        private const string D3V2ContractSha256 = "e402dfc90362a3ac07f5342d218f19c67d31d46f82bec584d5d817fbccb9f0bf";
        private const string D3V2SourceSha256 = "64e9ae20fdc5f03c9f737bc42a655f7488c359e3525b66f288f6ca963770a2ca";

        private const int EmptyWindowTrials = 64;
        private const int MaximumArrayOverheadBytes = 256;
        private const int MaximumArrayOverheadSpreadBytes = 64;
        private const int SmallObjectPayloadBytes = 64;
        private const int SmallObjectRepetitions = 4096;
        private const int GCReclamationPayloadBytes = 8 * 1024 * 1024;
        private const int SameThreadPayloadBytes = 1024 * 1024;
        private const int CrossThreadPayloadBytes = 4 * 1024 * 1024;
        private const int RatePayloadBytes = 1024 * 1024;
        private const double MaximumRateRecomputeError = 1e-9;

        private static byte s_sink;
        private static int s_workerReady;
        private static int s_workerCommand;
        private static int s_workerDone;

        public static void Run()
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string outputDirectory = null;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                outputDirectory = ResolveExactOutputDirectory(projectRoot, Required(arguments, "--g14me-d3v3-output-dir"));
                ValidateBindings(projectRoot, arguments);
                EnsureNewOutputDirectory(outputDirectory);
                Gate14ReMED3V3KnownAnswerReceiptV1 receipt = ExecuteKnownAnswer(projectRoot, arguments);
                WriteJsonAtomic(Path.Combine(outputDirectory, "d3-v3-known-answer-receipt.v1.json"), receipt);
                UnityEngine.Debug.Log("Gate14Re-ME D3-v3 known-answer PASS. Receipt: " + outputDirectory);
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                TryWriteFailureReceipt(projectRoot, outputDirectory, exception);
                UnityEngine.Debug.LogException(exception);
                EditorApplication.Exit(3);
            }
        }

        private static Gate14ReMED3V3KnownAnswerReceiptV1 ExecuteKnownAnswer(string projectRoot, Dictionary<string, string> arguments)
        {
            Require(Gate14ReMECumulativeAllocationCounterV1.IsReady(), "Native plugin is not ready.");
            Require(Gate14ReMECumulativeAllocationCounterV1.MarkerSeen(), "Exact GC.Alloc marker was not observed.");
            Require(Gate14ReMECumulativeAllocationCounterV1.CreateCallbackRegistrationCode() == 0,
                "Create-marker callback registration failed.");
            Require(Gate14ReMECumulativeAllocationCounterV1.MarkerCallbackRegistrationCode() == 0,
                "GC.Alloc event callback registration failed.");

            WarmUpMeasurementPaths();
            FullCollection();

            List<Gate14ReMED3V3WindowRecordV1> allWindows = new List<Gate14ReMED3V3WindowRecordV1>(EmptyWindowTrials + 12);
            List<Gate14ReMED3V3WindowRecordV1> emptyWindows = new List<Gate14ReMED3V3WindowRecordV1>(EmptyWindowTrials);
            for (int index = 0; index < EmptyWindowTrials; index++)
            {
                Gate14ReMED3V3WindowRecordV1 record = MeasureEmptyWindow(index + 1);
                emptyWindows.Add(record);
                allWindows.Add(record);
            }

            Gate14ReMED3V3EmptyControlV1 emptyControl = EvaluateEmptyControl(emptyWindows);
            Require(emptyControl.passed, "Empty-window zero-response criterion failed.");

            int[] requestedArraySizes = { 4096, 65536, 1048576 };
            Gate14ReMED3V3WindowRecordV1[] arrayRecords = new Gate14ReMED3V3WindowRecordV1[requestedArraySizes.Length];
            for (int index = 0; index < requestedArraySizes.Length; index++)
            {
                arrayRecords[index] = MeasureArrayWindow("known-array", index + 1, requestedArraySizes[index]);
                allWindows.Add(arrayRecords[index]);
            }
            Gate14ReMED3V3ArrayScaleControlV1 arrayScale = EvaluateArrayScale(arrayRecords);
            Require(arrayScale.passed, "Known-array size or monotonic scale criterion failed.");

            Gate14ReMED3V3WindowRecordV1 oneSmall = MeasureArrayWindow("small-object-single", 1, SmallObjectPayloadBytes);
            Gate14ReMED3V3WindowRecordV1 repeatedSmall = MeasureRepeatedWindow(
                "small-object-repeated", 1, SmallObjectPayloadBytes, SmallObjectRepetitions);
            allWindows.Add(oneSmall);
            allWindows.Add(repeatedSmall);
            Gate14ReMED3V3RepeatedSmallObjectControlV1 repeatedControl = EvaluateRepeatedControl(oneSmall, repeatedSmall);
            Require(repeatedControl.passed, "Repeated-small-object exact scaling criterion failed.");

            Gate14ReMED3V3GCReclamationControlV1 reclamation = MeasureGCReclamationWindow();
            allWindows.Add(reclamation.finalWindow);
            Require(reclamation.passed, "GC reclamation invariance criterion failed.");

            long harnessNativeThreadId = Gate14ReMECumulativeAllocationCounterV1.CurrentNativeThreadId();
            Gate14ReMED3V3WindowRecordV1 sameThread = MeasureArrayWindow("same-thread", 1, SameThreadPayloadBytes);
            allWindows.Add(sameThread);

            Thread worker = StartAndWarmWorker();
            Gate14ReMED3V3WindowRecordV1 crossThread;
            try
            {
                FullCollection();
                crossThread = MeasureCrossThreadWindow();
            }
            finally
            {
                StopWorker(worker);
            }
            allWindows.Add(crossThread);
            Gate14ReMED3V3ThreadAttributionControlV1 threadControl = EvaluateThreadControl(
                sameThread, crossThread, harnessNativeThreadId);
            Require(threadControl.passed, "Same-thread attribution or cross-thread exclusion criterion failed.");

            Gate14ReMED3V3WindowRecordV1 rateRecord = MeasureArrayWindow("byte-rate-formula", 1, RatePayloadBytes);
            allWindows.Add(rateRecord);
            Gate14ReMED3V3FormulaControlV1 formulaControl = EvaluateFormulaControl(rateRecord);
            Require(formulaControl.passed, "Byte/rate formula criterion failed.");

            bool invalidZero = true;
            bool overflowZero = true;
            bool observedPositiveMetadata = false;
            for (int index = 0; index < allWindows.Count; index++)
            {
                invalidZero &= allWindows[index].invalidMetadataEventCount == 0;
                overflowZero &= allWindows[index].counterOverflowCount == 0;
                observedPositiveMetadata |= allWindows[index].managedAllocationEventCount > 0 &&
                    allWindows[index].managedAllocationBytes > 0;
            }
            Require(invalidZero, "At least one window observed invalid GC.Alloc metadata.");
            Require(overflowZero, "At least one native counter overflow was observed.");
            Require(observedPositiveMetadata, "No positive Int64 GC.Alloc allocation-size metadata was observed.");

            Gate14ReMED3V3MarkerQualificationV1 marker = new Gate14ReMED3V3MarkerQualificationV1
            {
                exactMarkerName = "GC.Alloc",
                pluginReady = true,
                markerSeen = true,
                createCallbackRegistrationCode = 0,
                markerCallbackRegistrationCode = 0,
                requiredMetadataType = "Int64",
                requiredMetadataSizeBytes = 8,
                observedPositiveMetadata = observedPositiveMetadata,
                metadataShapePassed = invalidZero,
                passed = observedPositiveMetadata && invalidZero
            };

            Gate14ReMED3V3BindingsV1 bindings = BuildBindings(projectRoot, arguments);
            return new Gate14ReMED3V3KnownAnswerReceiptV1
            {
                schema = "gate14re-me-d3-v3-known-answer-receipt-v1",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                status = "PASS_D3_V3_TRUE_CUMULATIVE_MANAGED_ALLOCATION_QUALIFICATION",
                version = 1,
                createdAtUtc = DateTime.UtcNow.ToString("o"),
                unityVersion = Application.unityVersion,
                runtimeVersion = Environment.Version.ToString(),
                operatingSystem = SystemInfo.operatingSystem,
                architecture = Environment.Is64BitProcess ? "x86-64" : "not-x86-64",
                bindings = bindings,
                markerAndMetadata = marker,
                emptyWindow = emptyControl,
                knownArrayScale = arrayScale,
                repeatedSmallObjects = repeatedControl,
                gcReclamationInvariance = reclamation,
                threadAttribution = threadControl,
                byteAndRateFormula = formulaControl,
                allMeasuredWindows = allWindows.ToArray(),
                measuredWindowCount = allWindows.Count,
                allInvalidMetadataCountsZero = invalidZero,
                allOverflowCountsZero = overflowZero,
                scientificBoundary = new Gate14ReMED3V3ScientificBoundaryV1
                {
                    d3V2EvidenceRetained = true,
                    currentQualificationRunnerModified = false,
                    currentOutputSchemaModified = false,
                    algorithmSourcesModified = false,
                    qualificationScheduleRows = 0,
                    qualificationInputs = 0,
                    anonymousIdentityMappings = 0,
                    qualificationMeasuredRootCreated = false,
                    qualificationObservations = 0,
                    algorithmLanes = 0,
                    formalObservations = 0,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false,
                    fallbackMetricUsed = false
                }
            };
        }

        private static void WarmUpMeasurementPaths()
        {
            Gate14ReMECumulativeAllocationCounterV1.Snapshot ignored;
            Require(Gate14ReMECumulativeAllocationCounterV1.BeginWindow() == 0, "Warm-up BeginWindow failed.");
            Require(Gate14ReMECumulativeAllocationCounterV1.SnapshotWindow(out ignored) == 0, "Warm-up SnapshotWindow failed.");
            Require(Gate14ReMECumulativeAllocationCounterV1.EndWindow(out ignored) == 0, "Warm-up EndWindow failed.");
            AllocateOne(16);
            AllocateRepeated(16, 2);
            AllocateAndRelease(16);
            Stopwatch.GetTimestamp();
            Thread.SpinWait(16);
            FullCollection();
        }

        private static Gate14ReMED3V3WindowRecordV1 MeasureEmptyWindow(int trial)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native empty-window lifecycle failed.");
            return CreateWindowRecord("empty-window", trial, 0, snapshot, start, end);
        }

        private static Gate14ReMED3V3WindowRecordV1 MeasureArrayWindow(string controlId, int trial, int payloadBytes)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            AllocateOne(payloadBytes);
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native array-window lifecycle failed: " + controlId);
            return CreateWindowRecord(controlId, trial, payloadBytes, snapshot, start, end);
        }

        private static Gate14ReMED3V3WindowRecordV1 MeasureRepeatedWindow(
            string controlId, int trial, int payloadBytes, int repetitions)
        {
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            AllocateRepeated(payloadBytes, repetitions);
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && endCode == 0, "Native repeated-object window lifecycle failed.");
            return CreateWindowRecord(controlId, trial, payloadBytes * repetitions, snapshot, start, end);
        }

        private static Gate14ReMED3V3GCReclamationControlV1 MeasureGCReclamationWindow()
        {
            FullCollection();
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            AllocateAndRelease(GCReclamationPayloadBytes);
            Gate14ReMECumulativeAllocationCounterV1.Snapshot before;
            int beforeCode = Gate14ReMECumulativeAllocationCounterV1.SnapshotWindow(out before);
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            Gate14ReMECumulativeAllocationCounterV1.Snapshot after;
            int afterCode = Gate14ReMECumulativeAllocationCounterV1.SnapshotWindow(out after);
            Gate14ReMECumulativeAllocationCounterV1.Snapshot final;
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out final);
            long end = Stopwatch.GetTimestamp();
            Require(beginCode == 0 && beforeCode == 0 && afterCode == 0 && endCode == 0,
                "Native GC-reclamation window lifecycle failed.");

            Gate14ReMED3V3WindowRecordV1 record = CreateWindowRecord(
                "gc-reclamation-invariance", 1, GCReclamationPayloadBytes, final, start, end);
            bool nondecrease = after.ManagedAllocationBytes >= before.ManagedAllocationBytes &&
                after.ManagedAllocationEventCount >= before.ManagedAllocationEventCount &&
                final.ManagedAllocationBytes >= after.ManagedAllocationBytes &&
                final.ManagedAllocationEventCount >= after.ManagedAllocationEventCount;
            bool exactStability = after.ManagedAllocationBytes == before.ManagedAllocationBytes &&
                after.ManagedAllocationEventCount == before.ManagedAllocationEventCount &&
                final.ManagedAllocationBytes == after.ManagedAllocationBytes &&
                final.ManagedAllocationEventCount == after.ManagedAllocationEventCount;
            bool positive = before.ManagedAllocationBytes >= GCReclamationPayloadBytes && before.ManagedAllocationEventCount >= 1;
            bool clean = final.InvalidMetadataEventCount == 0 && final.CounterOverflowCount == 0;
            return new Gate14ReMED3V3GCReclamationControlV1
            {
                payloadBytes = GCReclamationPayloadBytes,
                finalWindow = record,
                beforeCollectionBytes = before.ManagedAllocationBytes,
                beforeCollectionEvents = before.ManagedAllocationEventCount,
                afterCollectionBytes = after.ManagedAllocationBytes,
                afterCollectionEvents = after.ManagedAllocationEventCount,
                endWindowBytes = final.ManagedAllocationBytes,
                endWindowEvents = final.ManagedAllocationEventCount,
                nondecreasePassed = nondecrease,
                exactStabilityPassed = exactStability,
                passed = positive && clean && nondecrease && exactStability
            };
        }

        private static Gate14ReMED3V3WindowRecordV1 MeasureCrossThreadWindow()
        {
            Volatile.Write(ref s_workerDone, 0);
            long start = Stopwatch.GetTimestamp();
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            Volatile.Write(ref s_workerCommand, 2);
            bool completed = SpinUntilEqual(ref s_workerDone, 2, Stopwatch.Frequency * 30L);
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            long end = Stopwatch.GetTimestamp();
            Volatile.Write(ref s_workerCommand, 0);
            Require(completed, "Worker-thread allocation timed out.");
            Require(beginCode == 0 && endCode == 0, "Native cross-thread window lifecycle failed.");
            return CreateWindowRecord("cross-thread-exclusion", 1, CrossThreadPayloadBytes, snapshot, start, end);
        }

        private static Thread StartAndWarmWorker()
        {
            Volatile.Write(ref s_workerReady, 0);
            Volatile.Write(ref s_workerCommand, 0);
            Volatile.Write(ref s_workerDone, 0);
            Thread worker = new Thread(WorkerMain);
            worker.IsBackground = true;
            worker.Name = "Gate14Re-ME-D3-v3-known-answer-worker";
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
            worker.Join(30000);
        }

        private static void WorkerMain()
        {
            Volatile.Write(ref s_workerReady, 1);
            while (true)
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

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void AllocateAndRelease(int payloadBytes)
        {
            AllocateOne(payloadBytes);
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

        private static Gate14ReMED3V3WindowRecordV1 CreateWindowRecord(
            string controlId,
            int trial,
            int requestedPayloadBytes,
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot,
            long start,
            long end)
        {
            long elapsed = end - start;
            double rate = elapsed > 0
                ? snapshot.ManagedAllocationBytes * (double)Stopwatch.Frequency / elapsed
                : double.NaN;
            return new Gate14ReMED3V3WindowRecordV1
            {
                controlId = controlId,
                trial = trial,
                requestedPayloadBytes = requestedPayloadBytes,
                managedAllocationBytes = snapshot.ManagedAllocationBytes,
                managedAllocationEventCount = snapshot.ManagedAllocationEventCount,
                foreignThreadAllocationBytes = snapshot.ForeignThreadAllocationBytes,
                foreignThreadAllocationEventCount = snapshot.ForeignThreadAllocationEventCount,
                invalidMetadataEventCount = snapshot.InvalidMetadataEventCount,
                counterOverflowCount = snapshot.CounterOverflowCount,
                windowStartStopwatchTicks = start,
                windowEndStopwatchTicks = end,
                windowElapsedStopwatchTicks = elapsed,
                stopwatchFrequency = Stopwatch.Frequency,
                managedAllocationRateBytesPerSecond = rate,
                ownerNativeThreadId = snapshot.OwnerNativeThreadId
            };
        }

        private static Gate14ReMED3V3EmptyControlV1 EvaluateEmptyControl(List<Gate14ReMED3V3WindowRecordV1> records)
        {
            long maximumBytes = 0;
            long maximumEvents = 0;
            bool zero = true;
            for (int index = 0; index < records.Count; index++)
            {
                maximumBytes = Math.Max(maximumBytes, records[index].managedAllocationBytes);
                maximumEvents = Math.Max(maximumEvents, records[index].managedAllocationEventCount);
                zero &= records[index].managedAllocationBytes == 0 && records[index].managedAllocationEventCount == 0;
                zero &= records[index].invalidMetadataEventCount == 0 && records[index].counterOverflowCount == 0;
            }
            return new Gate14ReMED3V3EmptyControlV1
            {
                trials = records.Count,
                maximumOwnerBytes = maximumBytes,
                maximumOwnerEvents = maximumEvents,
                allOwnerResponsesZero = zero,
                passed = records.Count == EmptyWindowTrials && zero
            };
        }

        private static Gate14ReMED3V3ArrayScaleControlV1 EvaluateArrayScale(Gate14ReMED3V3WindowRecordV1[] records)
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
            return new Gate14ReMED3V3ArrayScaleControlV1
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

        private static Gate14ReMED3V3RepeatedSmallObjectControlV1 EvaluateRepeatedControl(
            Gate14ReMED3V3WindowRecordV1 oneObject,
            Gate14ReMED3V3WindowRecordV1 repeatedObjects)
        {
            long expectedBytes = oneObject.managedAllocationBytes * SmallObjectRepetitions;
            long expectedEvents = oneObject.managedAllocationEventCount * SmallObjectRepetitions;
            bool byteScaling = oneObject.managedAllocationBytes > 0 && repeatedObjects.managedAllocationBytes == expectedBytes;
            bool eventScaling = oneObject.managedAllocationEventCount > 0 && repeatedObjects.managedAllocationEventCount == expectedEvents;
            bool clean = oneObject.invalidMetadataEventCount == 0 && repeatedObjects.invalidMetadataEventCount == 0 &&
                oneObject.counterOverflowCount == 0 && repeatedObjects.counterOverflowCount == 0;
            return new Gate14ReMED3V3RepeatedSmallObjectControlV1
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

        private static Gate14ReMED3V3ThreadAttributionControlV1 EvaluateThreadControl(
            Gate14ReMED3V3WindowRecordV1 sameThread,
            Gate14ReMED3V3WindowRecordV1 crossThread,
            long harnessNativeThreadId)
        {
            bool sameOwner = sameThread.ownerNativeThreadId == harnessNativeThreadId;
            bool samePositive = sameThread.managedAllocationBytes >= SameThreadPayloadBytes &&
                sameThread.managedAllocationEventCount >= 1;
            bool excluded = crossThread.managedAllocationBytes == 0 && crossThread.managedAllocationEventCount == 0;
            bool foreignPositive = crossThread.foreignThreadAllocationBytes >= CrossThreadPayloadBytes &&
                crossThread.foreignThreadAllocationEventCount >= 1;
            bool clean = sameThread.invalidMetadataEventCount == 0 && crossThread.invalidMetadataEventCount == 0 &&
                sameThread.counterOverflowCount == 0 && crossThread.counterOverflowCount == 0;
            return new Gate14ReMED3V3ThreadAttributionControlV1
            {
                sameThread = sameThread,
                crossThread = crossThread,
                harnessNativeThreadId = harnessNativeThreadId,
                crossThreadRequestedPayloadBytes = CrossThreadPayloadBytes,
                sameThreadOwnerIdPassed = sameOwner,
                sameThreadPositiveResponsePassed = samePositive,
                crossThreadOwnerExclusionPassed = excluded,
                crossThreadForeignResponsePassed = foreignPositive,
                passed = clean && sameOwner && samePositive && excluded && foreignPositive
            };
        }

        private static Gate14ReMED3V3FormulaControlV1 EvaluateFormulaControl(Gate14ReMED3V3WindowRecordV1 record)
        {
            double recomputed = record.managedAllocationBytes * (double)record.stopwatchFrequency /
                record.windowElapsedStopwatchTicks;
            double error = Math.Abs(record.managedAllocationRateBytesPerSecond - recomputed);
            bool finitePositive = record.managedAllocationBytes > 0 && record.windowElapsedStopwatchTicks > 0 &&
                record.stopwatchFrequency > 0 && !double.IsNaN(record.managedAllocationRateBytesPerSecond) &&
                !double.IsInfinity(record.managedAllocationRateBytesPerSecond) &&
                record.managedAllocationRateBytesPerSecond > 0;
            bool recomputePassed = error <= MaximumRateRecomputeError;
            return new Gate14ReMED3V3FormulaControlV1
            {
                record = record,
                independentlyRecomputedRateBytesPerSecond = recomputed,
                absoluteRecomputeError = error,
                maximumAbsoluteRecomputeError = MaximumRateRecomputeError,
                finitePositiveRatePassed = finitePositive,
                recomputePassed = recomputePassed,
                passed = finitePositive && recomputePassed
            };
        }

        private static Gate14ReMED3V3BindingsV1 BuildBindings(string projectRoot, Dictionary<string, string> arguments)
        {
            return new Gate14ReMED3V3BindingsV1
            {
                authorizationRelativePath = AuthorizationRelativePath,
                authorizationSha256 = Sha256File(Path.Combine(projectRoot, AuthorizationRelativePath)),
                planRelativePath = PlanRelativePath,
                planSha256 = Sha256File(Path.Combine(projectRoot, PlanRelativePath)),
                prospectiveContractRelativePath = ContractRelativePath,
                prospectiveContractSha256 = Sha256File(Path.Combine(projectRoot, ContractRelativePath)),
                nativeSourceRelativePath = NativeSourceRelativePath,
                nativeSourceSha256 = Sha256File(Path.Combine(projectRoot, NativeSourceRelativePath)),
                nativeBinaryRelativePath = NativeBinaryRelativePath,
                nativeBinarySha256 = Sha256File(Path.Combine(projectRoot, NativeBinaryRelativePath)),
                managedWrapperRelativePath = ManagedWrapperRelativePath,
                managedWrapperSha256 = Sha256File(Path.Combine(projectRoot, ManagedWrapperRelativePath)),
                knownAnswerHarnessRelativePath = HarnessRelativePath,
                knownAnswerHarnessSha256 = Sha256File(Path.Combine(projectRoot, HarnessRelativePath)),
                currentQualificationRunnerSha256 = CurrentRunnerSha256,
                currentOutputSchemaSha256 = CurrentSchemaSha256,
                sixAlgorithmBindingSha256 = SixAlgorithmBindingSha256,
                d3V2ContractSha256 = D3V2ContractSha256,
                d3V2SourceSha256 = D3V2SourceSha256
            };
        }

        private static void ValidateBindings(string projectRoot, Dictionary<string, string> arguments)
        {
            Require(Application.unityVersion == "2022.3.30f1c1", "Unity version mismatch.");
            Require(Environment.Is64BitProcess, "Unity process is not x86-64.");

            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-authorization",
                "--g14me-d3v3-authorization-sha256", AuthorizationRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-plan",
                "--g14me-d3v3-plan-sha256", PlanRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-contract",
                "--g14me-d3v3-contract-sha256", ContractRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-native-source",
                "--g14me-d3v3-native-source-sha256", NativeSourceRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-native-binary",
                "--g14me-d3v3-native-binary-sha256", NativeBinaryRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-managed-wrapper",
                "--g14me-d3v3-managed-wrapper-sha256", ManagedWrapperRelativePath);
            ValidateArgumentBoundFile(projectRoot, arguments, "--g14me-d3v3-harness",
                "--g14me-d3v3-harness-sha256", HarnessRelativePath);

            Require(Sha256File(Path.Combine(projectRoot, CurrentRunnerRelativePath)) == CurrentRunnerSha256,
                "Current qualification runner hash drift.");
            Require(Sha256File(Path.Combine(projectRoot, CurrentSchemaRelativePath)) == CurrentSchemaSha256,
                "Current output schema hash drift.");
            Require(Sha256File(Path.Combine(projectRoot, SixAlgorithmBindingRelativePath)) == SixAlgorithmBindingSha256,
                "Six-algorithm binding hash drift.");
            Require(Sha256File(Path.Combine(projectRoot, D3V2ContractRelativePath)) == D3V2ContractSha256,
                "D3-v2 contract hash drift.");
            Require(Sha256File(Path.Combine(projectRoot, D3V2SourceRelativePath)) == D3V2SourceSha256,
                "D3-v2 source hash drift.");

            string authorizationPath = Path.Combine(projectRoot, AuthorizationRelativePath);
            Gate14ReMED3V3AuthorizationHeaderV1 authorization = JsonUtility.FromJson<Gate14ReMED3V3AuthorizationHeaderV1>(
                File.ReadAllText(authorizationPath, Encoding.UTF8));
            Require(authorization != null &&
                authorization.schema == "gate14re-me-d3-v3-cumulative-allocation-qualification-attempt-003-authorization-v1" &&
                authorization.studyId == StudyId && authorization.authorizationId == AuthorizationId &&
                authorization.status == "AUTHORIZED_D3_V3_AUTONOMOUS_REPAIR_TO_FULL_INSTRUMENT_QUALIFICATION",
                "Authorization semantic binding mismatch.");

            string contractPath = Path.Combine(projectRoot, ContractRelativePath);
            Gate14ReMED3V3ContractHeaderV1 contract = JsonUtility.FromJson<Gate14ReMED3V3ContractHeaderV1>(
                File.ReadAllText(contractPath, Encoding.UTF8));
            Require(contract != null &&
                contract.schema == "gate14re-me-d3-v3-cumulative-managed-allocation-contract-prospective-v1" &&
                contract.studyId == StudyId && contract.endpointId == "D3" && contract.semanticVersion == 3 &&
                contract.status == "PROSPECTIVE_UNQUALIFIED",
                "Prospective instrument-contract semantic binding mismatch.");
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
            string expectedHash = RequiredSha256(arguments, hashArgument);
            Require(Sha256File(actualPath) == expectedHash, "Bound hash mismatch: " + expectedRelativePath);
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
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite receipt: " + path);
            string temporary = path + ".tmp." + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + "\n", new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static void TryWriteFailureReceipt(string projectRoot, string outputDirectory, Exception exception)
        {
            try
            {
                string expected = Path.GetFullPath(Path.Combine(projectRoot, ExpectedOutputRelativePath));
                if (string.IsNullOrEmpty(outputDirectory) ||
                    !string.Equals(Path.GetFullPath(outputDirectory), expected, StringComparison.OrdinalIgnoreCase))
                    return;
                Directory.CreateDirectory(outputDirectory);
                string path = Path.Combine(outputDirectory, "failure-receipt.v1.json");
                if (File.Exists(path)) return;
                WriteJsonAtomic(path, new Gate14ReMED3V3FailureReceiptV1
                {
                    schema = "gate14re-me-d3-v3-known-answer-failure-receipt-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = "FAILED_CLOSED_D3_V3_QUALIFICATION",
                    failedAtUtc = DateTime.UtcNow.ToString("o"),
                    exceptionType = exception.GetType().FullName,
                    exactReason = exception.Message,
                    stackTrace = exception.ToString(),
                    automaticRetryPerformed = false,
                    fallbackMetricUsed = false,
                    algorithmLaneExecuted = false,
                    qualificationMeasuredRootCreated = false,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false
                });
            }
            catch (Exception writeFailure)
            {
                UnityEngine.Debug.LogError("Unable to preserve D3-v3 failure receipt: " + writeFailure);
            }
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
#endif
