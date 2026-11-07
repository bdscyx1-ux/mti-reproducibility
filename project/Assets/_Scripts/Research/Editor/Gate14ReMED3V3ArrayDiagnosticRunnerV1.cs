#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Runtime.CompilerServices;
using DDM.Research.Gate14ReME.V3;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.Attempt003Diagnostic
{
    [Serializable]
    internal sealed class Gate14ReMED3V3ArrayDiagnosticRecordV1
    {
        public int trial;
        public int requestedPayloadBytes;
        public long managedAllocationBytes;
        public long managedAllocationEventCount;
        public long foreignThreadAllocationBytes;
        public long foreignThreadAllocationEventCount;
        public long invalidMetadataEventCount;
        public long counterOverflowCount;
        public long overheadBytes;
        public uint ownerNativeThreadId;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ArrayDiagnosticReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string createdAtUtc;
        public string unityVersion;
        public string nativeBinarySha256;
        public string managedWrapperSha256;
        public string diagnosticHarnessSha256;
        public bool pluginReady;
        public bool markerSeen;
        public int createCallbackRegistrationCode;
        public int markerCallbackRegistrationCode;
        public int emptyWindowTrials;
        public long maximumEmptyWindowBytes;
        public long maximumEmptyWindowEvents;
        public bool allEmptyWindowsZero;
        public Gate14ReMED3V3ArrayDiagnosticRecordV1[] records;
        public long minimumOverheadBytes;
        public long maximumOverheadBytes;
        public long overheadSpreadBytes;
        public bool allPayloadBoundsPassed;
        public bool allEventCountsPassed;
        public bool allMetadataAndOverflowCountsZero;
        public bool everyTrialStrictlyIncreasing;
        public bool originalOverheadSpreadCriterionPassed;
        public bool qualificationDecisionProduced;
        public bool fallbackMetricUsed;
        public bool algorithmLaneExecuted;
        public bool qualificationMeasuredRootCreated;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3ArrayDiagnosticFailureV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string failedAtUtc;
        public string exceptionType;
        public string exactReason;
        public string stackTrace;
        public bool algorithmLaneExecuted;
        public bool qualificationMeasuredRootCreated;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
    }

    public static class Gate14ReMED3V3ArrayDiagnosticRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-v3-cumulative-allocation-qualification-attempt-003";
        private const string OutputRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/repair-cycle-008-array-diagnostic-v1/diagnostic-output";
        private const string NativeBinaryRelativePath = "Assets/Plugins/x86_64/Gate14ReMED3AllocationCounterV3.dll";
        private const string ManagedWrapperRelativePath = "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMECumulativeAllocationCounterV1.cs";
        private const string HarnessRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMED3V3ArrayDiagnosticRunnerV1.cs";
        private const string NativeBinarySha256 = "924d43ecbc03f4e606a26a3de1593e96fdf7d3607d6e9e3c8942c877f0575245";
        private const string ManagedWrapperSha256 = "0fcac01678ec387aa2659543a2b84cba67b58ec97bdbfbc1e84aa77f5f0c3f9c";
        private const int EmptyWindowTrials = 64;
        private const int ReplicateTrials = 8;
        private const int MaximumArrayOverheadBytes = 256;
        private const int MaximumArrayOverheadSpreadBytes = 64;
        private static byte s_sink;

        public static void Run()
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string outputDirectory = Path.GetFullPath(Path.Combine(projectRoot, OutputRelativePath));
            try
            {
                Require(Application.unityVersion == "2022.3.30f1c1", "Unity version mismatch.");
                Require(Environment.Is64BitProcess, "Unity process is not x86-64.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Diagnostic output already exists.");
                Require(Sha256File(Path.Combine(projectRoot, NativeBinaryRelativePath)) == NativeBinarySha256, "Native binary hash drift.");
                Require(Sha256File(Path.Combine(projectRoot, ManagedWrapperRelativePath)) == ManagedWrapperSha256, "Managed wrapper hash drift.");

                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string expectedHarnessHash = RequiredSha256(arguments, "--g14me-d3v3-array-diagnostic-sha256");
                string actualHarnessHash = Sha256File(Path.Combine(projectRoot, HarnessRelativePath));
                Require(actualHarnessHash == expectedHarnessHash, "Diagnostic harness hash mismatch.");

                bool pluginReady = Gate14ReMECumulativeAllocationCounterV1.IsReady();
                bool markerSeen = Gate14ReMECumulativeAllocationCounterV1.MarkerSeen();
                int createCode = Gate14ReMECumulativeAllocationCounterV1.CreateCallbackRegistrationCode();
                int markerCode = Gate14ReMECumulativeAllocationCounterV1.MarkerCallbackRegistrationCode();
                Require(pluginReady && markerSeen && createCode == 0 && markerCode == 0, "D3-v3 native marker registration is not ready.");

                WarmUp();
                FullCollection();

                long maximumEmptyBytes = 0;
                long maximumEmptyEvents = 0;
                bool allEmptyZero = true;
                for (int trial = 1; trial <= EmptyWindowTrials; trial++)
                {
                    Gate14ReMECumulativeAllocationCounterV1.Snapshot empty = MeasureEmpty();
                    maximumEmptyBytes = Math.Max(maximumEmptyBytes, empty.ManagedAllocationBytes);
                    maximumEmptyEvents = Math.Max(maximumEmptyEvents, empty.ManagedAllocationEventCount);
                    allEmptyZero &= empty.ManagedAllocationBytes == 0 && empty.ManagedAllocationEventCount == 0;
                    allEmptyZero &= empty.InvalidMetadataEventCount == 0 && empty.CounterOverflowCount == 0;
                }

                int[] payloads = { 4096, 65536, 1048576 };
                List<Gate14ReMED3V3ArrayDiagnosticRecordV1> records = new List<Gate14ReMED3V3ArrayDiagnosticRecordV1>(payloads.Length * ReplicateTrials);
                long minimumOverhead = long.MaxValue;
                long maximumOverhead = long.MinValue;
                bool allBounds = true;
                bool allEvents = true;
                bool allClean = true;
                bool everyTrialIncreasing = true;

                for (int trial = 1; trial <= ReplicateTrials; trial++)
                {
                    long previousBytes = -1;
                    for (int index = 0; index < payloads.Length; index++)
                    {
                        Gate14ReMED3V3ArrayDiagnosticRecordV1 record = MeasureArray(trial, payloads[index]);
                        records.Add(record);
                        minimumOverhead = Math.Min(minimumOverhead, record.overheadBytes);
                        maximumOverhead = Math.Max(maximumOverhead, record.overheadBytes);
                        allBounds &= record.overheadBytes >= 0 && record.overheadBytes <= MaximumArrayOverheadBytes;
                        allEvents &= record.managedAllocationEventCount >= 1;
                        allClean &= record.invalidMetadataEventCount == 0 && record.counterOverflowCount == 0;
                        if (previousBytes >= 0) everyTrialIncreasing &= record.managedAllocationBytes > previousBytes;
                        previousBytes = record.managedAllocationBytes;
                    }
                }

                long spread = maximumOverhead - minimumOverhead;
                Gate14ReMED3V3ArrayDiagnosticReceiptV1 receipt = new Gate14ReMED3V3ArrayDiagnosticReceiptV1
                {
                    schema = "gate14re-me-d3-v3-array-diagnostic-receipt-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = "DIAGNOSTIC_ONLY_NOT_QUALIFICATION",
                    createdAtUtc = DateTime.UtcNow.ToString("o"),
                    unityVersion = Application.unityVersion,
                    nativeBinarySha256 = NativeBinarySha256,
                    managedWrapperSha256 = ManagedWrapperSha256,
                    diagnosticHarnessSha256 = actualHarnessHash,
                    pluginReady = pluginReady,
                    markerSeen = markerSeen,
                    createCallbackRegistrationCode = createCode,
                    markerCallbackRegistrationCode = markerCode,
                    emptyWindowTrials = EmptyWindowTrials,
                    maximumEmptyWindowBytes = maximumEmptyBytes,
                    maximumEmptyWindowEvents = maximumEmptyEvents,
                    allEmptyWindowsZero = allEmptyZero,
                    records = records.ToArray(),
                    minimumOverheadBytes = minimumOverhead,
                    maximumOverheadBytes = maximumOverhead,
                    overheadSpreadBytes = spread,
                    allPayloadBoundsPassed = allBounds,
                    allEventCountsPassed = allEvents,
                    allMetadataAndOverflowCountsZero = allClean,
                    everyTrialStrictlyIncreasing = everyTrialIncreasing,
                    originalOverheadSpreadCriterionPassed = spread <= MaximumArrayOverheadSpreadBytes,
                    qualificationDecisionProduced = false,
                    fallbackMetricUsed = false,
                    algorithmLaneExecuted = false,
                    qualificationMeasuredRootCreated = false,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false
                };
                Directory.CreateDirectory(outputDirectory);
                WriteJsonAtomic(Path.Combine(outputDirectory, "array-diagnostic-receipt.v1.json"), receipt);
                UnityEngine.Debug.Log("Gate14Re-ME D3-v3 array diagnostic complete; no qualification decision produced.");
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                try
                {
                    Directory.CreateDirectory(outputDirectory);
                    WriteJsonAtomic(Path.Combine(outputDirectory, "failure-receipt.v1.json"), new Gate14ReMED3V3ArrayDiagnosticFailureV1
                    {
                        schema = "gate14re-me-d3-v3-array-diagnostic-failure-receipt-v1",
                        studyId = StudyId,
                        authorizationId = AuthorizationId,
                        status = "FAILED_CLOSED_DIAGNOSTIC",
                        failedAtUtc = DateTime.UtcNow.ToString("o"),
                        exceptionType = exception.GetType().FullName,
                        exactReason = exception.Message,
                        stackTrace = exception.ToString(),
                        algorithmLaneExecuted = false,
                        qualificationMeasuredRootCreated = false,
                        formalAnalysisPerformed = false,
                        rankingOrWinnerComputed = false
                    });
                }
                catch (Exception writeFailure)
                {
                    UnityEngine.Debug.LogError("Unable to preserve D3-v3 array diagnostic failure: " + writeFailure);
                }
                UnityEngine.Debug.LogException(exception);
                EditorApplication.Exit(3);
            }
        }

        private static void WarmUp()
        {
            Gate14ReMECumulativeAllocationCounterV1.Snapshot ignored;
            Require(Gate14ReMECumulativeAllocationCounterV1.BeginWindow() == 0, "Warm-up BeginWindow failed.");
            Require(Gate14ReMECumulativeAllocationCounterV1.EndWindow(out ignored) == 0, "Warm-up EndWindow failed.");
            AllocateOne(16);
            Stopwatch.GetTimestamp();
            FullCollection();
        }

        private static Gate14ReMECumulativeAllocationCounterV1.Snapshot MeasureEmpty()
        {
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            Require(beginCode == 0 && endCode == 0, "Empty diagnostic window lifecycle failed.");
            return snapshot;
        }

        private static Gate14ReMED3V3ArrayDiagnosticRecordV1 MeasureArray(int trial, int payloadBytes)
        {
            Gate14ReMECumulativeAllocationCounterV1.Snapshot snapshot;
            int beginCode = Gate14ReMECumulativeAllocationCounterV1.BeginWindow();
            AllocateOne(payloadBytes);
            int endCode = Gate14ReMECumulativeAllocationCounterV1.EndWindow(out snapshot);
            Require(beginCode == 0 && endCode == 0, "Array diagnostic window lifecycle failed.");
            return new Gate14ReMED3V3ArrayDiagnosticRecordV1
            {
                trial = trial,
                requestedPayloadBytes = payloadBytes,
                managedAllocationBytes = snapshot.ManagedAllocationBytes,
                managedAllocationEventCount = snapshot.ManagedAllocationEventCount,
                foreignThreadAllocationBytes = snapshot.ForeignThreadAllocationBytes,
                foreignThreadAllocationEventCount = snapshot.ForeignThreadAllocationEventCount,
                invalidMetadataEventCount = snapshot.InvalidMetadataEventCount,
                counterOverflowCount = snapshot.CounterOverflowCount,
                overheadBytes = snapshot.ManagedAllocationBytes - payloadBytes,
                ownerNativeThreadId = snapshot.OwnerNativeThreadId
            };
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

        private static void FullCollection()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                if (!args[index].StartsWith("--", StringComparison.Ordinal)) continue;
                Require(index + 1 < args.Length, "Missing value for argument: " + args[index]);
                values[args[index]] = args[++index];
            }
            return values;
        }

        private static string RequiredSha256(Dictionary<string, string> arguments, string key)
        {
            string value;
            Require(arguments.TryGetValue(key, out value), "Missing argument: " + key);
            value = value.ToLowerInvariant();
            Require(value.Length == 64, "Invalid SHA-256 value: " + key);
            for (int index = 0; index < value.Length; index++)
                Require((value[index] >= '0' && value[index] <= '9') || (value[index] >= 'a' && value[index] <= 'f'),
                    "Invalid SHA-256 value: " + key);
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
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite diagnostic receipt: " + path);
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
