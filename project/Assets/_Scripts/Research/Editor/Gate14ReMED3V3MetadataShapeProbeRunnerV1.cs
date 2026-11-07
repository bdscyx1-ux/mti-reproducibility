#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V3;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.Attempt003Probe
{
    [Serializable]
    internal sealed class Gate14ReMED3V3MetadataShapeProbeRecordV1
    {
        public int requestedPayloadBytes;
        public ulong ownerObservationCount;
        public ulong foreignObservationCount;
        public int lastEventType;
        public uint lastEventDataCount;
        public uint lastMetadataType;
        public uint lastMetadataSize;
        public bool lastPointerNonNull;
        public bool lastRawInt64Available;
        public long lastRawInt64;
        public uint ownerThreadId;
    }

    [Serializable]
    internal sealed class Gate14ReMED3V3MetadataShapeProbeReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string createdAtUtc;
        public string unityVersion;
        public string nativeSourceSha256;
        public string nativeBinarySha256;
        public string managedWrapperSha256;
        public string probeHarnessSha256;
        public bool pluginReady;
        public bool markerSeen;
        public int createCallbackRegistrationCode;
        public int markerCallbackRegistrationCode;
        public Gate14ReMED3V3MetadataShapeProbeRecordV1[] records;
        public bool probeCountsAsD3Qualification;
        public bool fallbackMetricUsed;
        public bool algorithmLaneExecuted;
        public bool qualificationMeasuredRootCreated;
        public bool formalAnalysisPerformed;
        public bool rankingOrWinnerComputed;
    }

    public static class Gate14ReMED3V3MetadataShapeProbeRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-v3-cumulative-allocation-qualification-attempt-003";
        private const string OutputRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/repair-cycle-009-metadata-shape-probe-v1/probe-output";
        private const string NativeSourceRelativePath = "Research/Gate14Re-ME/Native/v3/Gate14ReMED3AllocationMetadataProbeV1.cpp";
        private const string NativeBinaryRelativePath = "Assets/Plugins/x86_64/Gate14ReMED3AllocationMetadataProbeV1.dll";
        private const string ManagedWrapperRelativePath = "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMED3AllocationMetadataProbeV1.cs";
        private const string HarnessRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMED3V3MetadataShapeProbeRunnerV1.cs";
        private static byte s_sink;

        public static void Run()
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string outputDirectory = Path.GetFullPath(Path.Combine(projectRoot, OutputRelativePath));
            try
            {
                Require(Application.unityVersion == "2022.3.30f1c1", "Unity version mismatch.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Probe output already exists.");
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string sourceHash = ValidateHash(projectRoot, NativeSourceRelativePath, arguments, "--g14me-probe-source-sha256");
                string binaryHash = ValidateHash(projectRoot, NativeBinaryRelativePath, arguments, "--g14me-probe-binary-sha256");
                string wrapperHash = ValidateHash(projectRoot, ManagedWrapperRelativePath, arguments, "--g14me-probe-wrapper-sha256");
                string harnessHash = ValidateHash(projectRoot, HarnessRelativePath, arguments, "--g14me-probe-harness-sha256");

                bool ready = Gate14ReMED3AllocationMetadataProbeV1.IsReady();
                bool seen = Gate14ReMED3AllocationMetadataProbeV1.MarkerSeen();
                int createCode = Gate14ReMED3AllocationMetadataProbeV1.CreateCallbackRegistrationCode();
                int markerCode = Gate14ReMED3AllocationMetadataProbeV1.MarkerCallbackRegistrationCode();
                Require(ready && seen && createCode == 0 && markerCode == 0, "Metadata probe marker registration is not ready.");

                AllocateOne(16);
                int[] payloads = { 4096, 65536, 1048576 };
                List<Gate14ReMED3V3MetadataShapeProbeRecordV1> records = new List<Gate14ReMED3V3MetadataShapeProbeRecordV1>();
                for (int index = 0; index < payloads.Length; index++)
                {
                    Require(Gate14ReMED3AllocationMetadataProbeV1.Begin() == 0, "Probe Begin failed.");
                    AllocateOne(payloads[index]);
                    Gate14ReMED3AllocationMetadataProbeV1.Snapshot snapshot;
                    Require(Gate14ReMED3AllocationMetadataProbeV1.End(out snapshot) == 0, "Probe End failed.");
                    records.Add(new Gate14ReMED3V3MetadataShapeProbeRecordV1
                    {
                        requestedPayloadBytes = payloads[index],
                        ownerObservationCount = snapshot.OwnerObservationCount,
                        foreignObservationCount = snapshot.ForeignObservationCount,
                        lastEventType = snapshot.LastEventType,
                        lastEventDataCount = snapshot.LastEventDataCount,
                        lastMetadataType = snapshot.LastMetadataType,
                        lastMetadataSize = snapshot.LastMetadataSize,
                        lastPointerNonNull = snapshot.LastPointerNonNull,
                        lastRawInt64Available = snapshot.LastRawInt64Available,
                        lastRawInt64 = snapshot.LastRawInt64,
                        ownerThreadId = snapshot.OwnerThreadId
                    });
                }

                Gate14ReMED3V3MetadataShapeProbeReceiptV1 receipt = new Gate14ReMED3V3MetadataShapeProbeReceiptV1
                {
                    schema = "gate14re-me-d3-v3-metadata-shape-probe-receipt-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = "DIAGNOSTIC_ONLY_NOT_QUALIFICATION",
                    createdAtUtc = DateTime.UtcNow.ToString("o"),
                    unityVersion = Application.unityVersion,
                    nativeSourceSha256 = sourceHash,
                    nativeBinarySha256 = binaryHash,
                    managedWrapperSha256 = wrapperHash,
                    probeHarnessSha256 = harnessHash,
                    pluginReady = ready,
                    markerSeen = seen,
                    createCallbackRegistrationCode = createCode,
                    markerCallbackRegistrationCode = markerCode,
                    records = records.ToArray(),
                    probeCountsAsD3Qualification = false,
                    fallbackMetricUsed = false,
                    algorithmLaneExecuted = false,
                    qualificationMeasuredRootCreated = false,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false
                };
                Directory.CreateDirectory(outputDirectory);
                WriteJsonAtomic(Path.Combine(outputDirectory, "metadata-shape-probe-receipt.v1.json"), receipt);
                UnityEngine.Debug.Log("Gate14Re-ME D3-v3 metadata-shape probe complete; no qualification decision produced.");
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
                EditorApplication.Exit(3);
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

        private static string ValidateHash(string projectRoot, string relativePath, Dictionary<string, string> arguments, string key)
        {
            string expected;
            Require(arguments.TryGetValue(key, out expected), "Missing argument: " + key);
            expected = expected.ToLowerInvariant();
            Require(expected.Length == 64, "Invalid SHA-256: " + key);
            string actual = Sha256File(Path.Combine(projectRoot, relativePath));
            Require(actual == expected, "Hash mismatch: " + relativePath);
            return actual;
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
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite probe receipt: " + path);
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
