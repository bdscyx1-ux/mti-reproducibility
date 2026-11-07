#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V2;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// D3-only runtime-compatibility known-answer harness. It never constructs a
    /// planner, creates a measured root, or executes an algorithm lane.
    /// </summary>
    public static class Gate14ReMED3RuntimeCompatibilityRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-runtime-compatibility-amendment-attempt-001";
        private const string AuthorizationSchema = "gate14re-me-d3-runtime-compatibility-amendment-authorization-v1";
        private const string AuthorizationStatus = "AUTHORIZED_D3_RUNTIME_COMPATIBILITY_AMENDMENT_ONLY";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/d3-known-answer";
        private const string ExpectedFailureReceiptSha256 = "8a508261f9c779ff3d3e3481d5eaf28ebc9d4c513cb69fdc8d30456b3ad9b49a";
        private const string ExpectedFailedFreezeReceiptSha256 = "042f3ca2d07b4b78db04a7b272929f6052cc51739c0aeeaa4e6998b75f5554c8";
        private const string ExpectedStatusV4Sha256 = "cad8a34346450b9ca286fcbf277a8b5e673198a256e91848903d0b56fc959b37";
        private const int NegativeControlIntervals = 64;
        private const long NegativeControlMaximumBytes = 65536L;
        private const int SmallPositiveControlBytes = 1048576;
        private const int LargePositiveControlBytes = 4194304;
        private const long RequiredScaleSeparationBytes = 3145728L;

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-d3-authorization"));
                string authorizationSha256 = RequiredSha256(arguments, "--g14me-d3-authorization-sha256");
                Require(Sha256File(authorizationPath) == authorizationSha256, "D3 amendment authorization hash mismatch.");

                D3Authorization authorization = ReadJson<D3Authorization>(authorizationPath);
                ValidateAuthorization(authorization, projectRoot);

                string counterSourcePath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-d3-counter-source"));
                string counterSourceSha256 = RequiredSha256(arguments, "--g14me-d3-counter-source-sha256");
                Require(Sha256File(counterSourcePath) == counterSourceSha256, "D3 counter source hash mismatch.");
                Require(RelativePath(projectRoot, counterSourcePath) == "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEAllocationCounterV2.cs",
                    "Unexpected D3 counter source path.");

                RequireProhibitedRootsAbsent(projectRoot);
                string outputDirectory = ResolveOutputDirectory(projectRoot, Required(arguments, "--g14me-d3-output-dir"));
                Require(RelativePath(projectRoot, outputDirectory) == ExpectedOutputRelativePath,
                    "D3 known-answer output path is outside the exact verification-only path.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory),
                    "D3 known-answer output already exists; overwrite or resume is prohibited.");
                string outputParent = Directory.GetParent(outputDirectory).FullName;
                Require(Directory.Exists(outputParent), "D3 verification parent must already exist.");
                Directory.CreateDirectory(outputDirectory);

                // Resolve any one-time runtime initialization before opening a measured interval.
                long warmupBefore = Gate14ReMEAllocationCounterV2.Capture();
                long warmupAfter = Gate14ReMEAllocationCounterV2.Capture();
                Gate14ReMEAllocationCounterV2.Difference(warmupBefore, warmupAfter);

                long[] negativeDifferences = new long[NegativeControlIntervals];
                long negativeMaximum = 0L;
                long negativeTotal = 0L;
                for (int index = 0; index < NegativeControlIntervals; index++)
                {
                    long before = Gate14ReMEAllocationCounterV2.Capture();
                    long after = Gate14ReMEAllocationCounterV2.Capture();
                    long difference = Gate14ReMEAllocationCounterV2.Difference(before, after);
                    negativeDifferences[index] = difference;
                    negativeMaximum = Math.Max(negativeMaximum, difference);
                    negativeTotal = checked(negativeTotal + difference);
                }
                bool negativeControlPassed = negativeMaximum <= NegativeControlMaximumBytes;

                int[] positiveSizes = { SmallPositiveControlBytes, LargePositiveControlBytes };
                byte[][] retained = new byte[positiveSizes.Length][];
                PositiveControlResult[] positiveResults = new PositiveControlResult[positiveSizes.Length];
                bool positiveControlsPassed = true;
                for (int index = 0; index < positiveSizes.Length; index++)
                {
                    int requestedBytes = positiveSizes[index];
                    long before = Gate14ReMEAllocationCounterV2.Capture();
                    retained[index] = new byte[requestedBytes];
                    retained[index][requestedBytes - 1] = 1;
                    long after = Gate14ReMEAllocationCounterV2.Capture();
                    long difference = Gate14ReMEAllocationCounterV2.Difference(before, after);
                    bool passed = difference >= requestedBytes;
                    positiveResults[index] = new PositiveControlResult
                    {
                        requestedBytes = requestedBytes,
                        counterBefore = before,
                        counterAfter = after,
                        differenceBytes = difference,
                        passed = passed
                    };
                    positiveControlsPassed = positiveControlsPassed && passed;
                }
                GC.KeepAlive(retained);

                long observedScaleSeparation = checked(positiveResults[1].differenceBytes - positiveResults[0].differenceBytes);
                bool scaleSeparationPassed = observedScaleSeparation >= RequiredScaleSeparationBytes;
                bool passedAll = negativeControlPassed && positiveControlsPassed && scaleSeparationPassed;

                D3KnownAnswerReceipt receipt = new D3KnownAnswerReceipt
                {
                    schema = "gate14re-me-d3-runtime-compatibility-known-answer-receipt-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = passedAll ? "PASS_D3_PROCESS_WIDE_COUNTER_KNOWN_ANSWER" : "FAIL_CLOSED_D3_PROCESS_WIDE_COUNTER_KNOWN_ANSWER",
                    counterId = Gate14ReMEAllocationCounterV2.CounterId,
                    counterScope = "process-wide managed allocations during the synchronous measured boundary",
                    nativeAllocationsIncluded = false,
                    negativeControlIntervals = NegativeControlIntervals,
                    negativeControlMaximumAllowedBytes = NegativeControlMaximumBytes,
                    negativeControlObservedMaximumBytes = negativeMaximum,
                    negativeControlObservedTotalBytes = negativeTotal,
                    negativeControlDifferencesBytes = negativeDifferences,
                    negativeControlPassed = negativeControlPassed,
                    positiveControls = positiveResults,
                    positiveControlsPassed = positiveControlsPassed,
                    requiredScaleSeparationBytes = RequiredScaleSeparationBytes,
                    observedScaleSeparationBytes = observedScaleSeparation,
                    scaleSeparationPassed = scaleSeparationPassed,
                    counterSourceRelativePath = RelativePath(projectRoot, counterSourcePath),
                    counterSourceSha256 = counterSourceSha256,
                    authorizationRelativePath = RelativePath(projectRoot, authorizationPath),
                    authorizationSha256 = authorizationSha256,
                    unityVersion = Application.unityVersion,
                    frameworkDescription = RuntimeInformation.FrameworkDescription,
                    runtimeVersion = Environment.Version.ToString(),
                    is64BitProcess = Environment.Is64BitProcess,
                    processId = System.Diagnostics.Process.GetCurrentProcess().Id,
                    commandLineSha256 = Sha256Text(Environment.CommandLine),
                    plannerConstructed = false,
                    algorithmLaneExecuted = false,
                    qualificationObservationCount = 0,
                    formalObservationCount = 0,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "d3-known-answer-receipt.v1.json"), receipt);
                Require(passedAll, "One or more prospective D3 runtime-compatibility controls failed.");
                exitCode = 0;
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static void ValidateAuthorization(D3Authorization authorization, string projectRoot)
        {
            Require(authorization != null && authorization.schema == AuthorizationSchema && authorization.studyId == StudyId &&
                    authorization.authorizationId == AuthorizationId && authorization.status == AuthorizationStatus,
                "D3 amendment authorization identity mismatch.");
            Require(authorization.authorizedScope != null &&
                    authorization.authorizedScope.diagnoseD3RuntimeCompatibility &&
                    authorization.authorizedScope.createVersionedD3CounterSource &&
                    authorization.authorizedScope.createD3OnlyKnownAnswerHarness &&
                    authorization.authorizedScope.runOneD3OnlyUnityKnownAnswer &&
                    authorization.authorizedScope.addProspectivePositiveControls &&
                    authorization.authorizedScope.addProspectiveNegativeControls &&
                    authorization.authorizedScope.createVersionedD3InstrumentContract &&
                    authorization.authorizedScope.createSourceOnlyScientificRefreeze,
                "Required D3-only authorization is incomplete.");
            Require(authorization.prohibitedScope != null &&
                    !authorization.prohibitedScope.retryRuntimeQualificationAttempt001 &&
                    !authorization.prohibitedScope.runFullRuntimeQualificationAttempt002 &&
                    !authorization.prohibitedScope.runDataExporterKnownAnswer &&
                    !authorization.prohibitedScope.qualificationScheduleGeneration &&
                    !authorization.prohibitedScope.qualificationInputGeneration &&
                    !authorization.prohibitedScope.anonymousIdentityMapGeneration &&
                    !authorization.prohibitedScope.qualificationMeasuredRootCreation &&
                    !authorization.prohibitedScope.algorithmLaneExecution &&
                    !authorization.prohibitedScope.formalInputGeneration &&
                    !authorization.prohibitedScope.formalMeasuredRootCreation &&
                    !authorization.prohibitedScope.formalCollection &&
                    !authorization.prohibitedScope.formalAnalysis &&
                    !authorization.prohibitedScope.algorithmRanking &&
                    !authorization.prohibitedScope.winnerAdjudication,
                "A prohibited D3 amendment scope was enabled.");
            Require(authorization.priorFailedRuntimeQualification != null &&
                    authorization.priorFailedRuntimeQualification.failureReceiptSha256 == ExpectedFailureReceiptSha256 &&
                    authorization.priorFailedRuntimeQualification.freezeReceiptSha256 == ExpectedFailedFreezeReceiptSha256 &&
                    authorization.priorFailedRuntimeQualification.statusSha256 == ExpectedStatusV4Sha256,
                "Prior failed runtime-qualification bindings mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedRuntimeQualification.failureReceiptRelativePath)) == ExpectedFailureReceiptSha256,
                "Prior D3 failure receipt hash mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedRuntimeQualification.freezeReceiptRelativePath)) == ExpectedFailedFreezeReceiptSha256,
                "Prior runtime-qualification freeze receipt hash mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedRuntimeQualification.statusRelativePath)) == ExpectedStatusV4Sha256,
                "Prior status-v4 hash mismatch.");
            Require(authorization.knownAnswerDesign != null &&
                    authorization.knownAnswerDesign.negativeControlIntervals == NegativeControlIntervals &&
                    authorization.knownAnswerDesign.negativeControlMaximumBytesPerEmptyInterval == NegativeControlMaximumBytes,
                "Prospective negative-control thresholds mismatch.");
        }

        private static void RequireProhibitedRootsAbsent(string projectRoot)
        {
            string[] relativePaths =
            {
                "Research/PilotRuns/Gate14Re-ME",
                "Research/FormalRuns/Gate14Re-ME",
                "Research/Analysis/Gate14Re-ME",
                "Research/Exports/Gate14Re-ME"
            };
            foreach (string relativePath in relativePaths)
            {
                string full = Path.GetFullPath(Path.Combine(projectRoot, relativePath));
                Require(!Directory.Exists(full) && !File.Exists(full), "Prohibited root exists: " + relativePath);
            }
        }

        private static Dictionary<string, string> ParseArguments(string[] arguments)
        {
            Dictionary<string, string> parsed = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index + 1 < arguments.Length; index++)
            {
                if (arguments[index].StartsWith("--g14me-d3-", StringComparison.Ordinal))
                {
                    parsed[arguments[index]] = arguments[index + 1];
                    index++;
                }
            }
            return parsed;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            Require(arguments.TryGetValue(key, out value) && !string.IsNullOrWhiteSpace(value), "Missing required argument: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> arguments, string key)
        {
            string value = Required(arguments, key).ToLowerInvariant();
            Require(value.Length == 64, "Invalid SHA-256 argument: " + key);
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                Require((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'), "Invalid SHA-256 argument: " + key);
            }
            return value;
        }

        private static string ResolveExistingFile(string projectRoot, string candidate)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(candidate) ? candidate : Path.Combine(projectRoot, candidate));
            Require(IsWithin(projectRoot, full) && File.Exists(full), "Required project file is missing or outside the project.");
            return full;
        }

        private static string ResolveOutputDirectory(string projectRoot, string candidate)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(candidate) ? candidate : Path.Combine(projectRoot, candidate));
            Require(IsWithin(projectRoot, full), "Output directory is outside the project.");
            return full;
        }

        private static bool IsWithin(string parent, string child)
        {
            string normalizedParent = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string normalizedChild = Path.GetFullPath(child);
            return normalizedChild.StartsWith(normalizedParent, StringComparison.OrdinalIgnoreCase);
        }

        private static string RelativePath(string projectRoot, string fullPath)
        {
            Uri root = new Uri(Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri file = new Uri(Path.GetFullPath(fullPath));
            return Uri.UnescapeDataString(root.MakeRelativeUri(file).ToString()).Replace('\\', '/');
        }

        private static T ReadJson<T>(string path)
        {
            T value = JsonUtility.FromJson<T>(File.ReadAllText(path, Encoding.UTF8));
            Require(value != null, "JSON could not be deserialized: " + path);
            return value;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 algorithm = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                return Hex(algorithm.ComputeHash(stream));
            }
        }

        private static string Sha256Text(string value)
        {
            using (SHA256 algorithm = SHA256.Create())
            {
                return Hex(algorithm.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty)));
            }
        }

        private static string Hex(byte[] hash)
        {
            StringBuilder builder = new StringBuilder(hash.Length * 2);
            for (int index = 0; index < hash.Length; index++) builder.Append(hash[index].ToString("x2"));
            return builder.ToString();
        }

        private static void WriteJsonAtomic<T>(string path, T value)
        {
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + Environment.NewLine, new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        [Serializable]
        private sealed class D3Authorization
        {
            public string schema;
            public string studyId;
            public string authorizationId;
            public string status;
            public AuthorizedScope authorizedScope;
            public ProhibitedScope prohibitedScope;
            public PriorFailedRuntimeQualification priorFailedRuntimeQualification;
            public KnownAnswerDesign knownAnswerDesign;
        }

        [Serializable]
        private sealed class AuthorizedScope
        {
            public bool diagnoseD3RuntimeCompatibility;
            public bool createVersionedD3CounterSource;
            public bool createD3OnlyKnownAnswerHarness;
            public bool runOneD3OnlyUnityKnownAnswer;
            public bool addProspectivePositiveControls;
            public bool addProspectiveNegativeControls;
            public bool createVersionedD3InstrumentContract;
            public bool createSourceOnlyScientificRefreeze;
        }

        [Serializable]
        private sealed class ProhibitedScope
        {
            public bool retryRuntimeQualificationAttempt001;
            public bool runFullRuntimeQualificationAttempt002;
            public bool runDataExporterKnownAnswer;
            public bool qualificationScheduleGeneration;
            public bool qualificationInputGeneration;
            public bool anonymousIdentityMapGeneration;
            public bool qualificationMeasuredRootCreation;
            public bool algorithmLaneExecution;
            public bool formalInputGeneration;
            public bool formalMeasuredRootCreation;
            public bool formalCollection;
            public bool formalAnalysis;
            public bool algorithmRanking;
            public bool winnerAdjudication;
        }

        [Serializable]
        private sealed class PriorFailedRuntimeQualification
        {
            public string failureReceiptRelativePath;
            public string failureReceiptSha256;
            public string freezeReceiptRelativePath;
            public string freezeReceiptSha256;
            public string statusRelativePath;
            public string statusSha256;
        }

        [Serializable]
        private sealed class KnownAnswerDesign
        {
            public int negativeControlIntervals;
            public long negativeControlMaximumBytesPerEmptyInterval;
        }

        [Serializable]
        private sealed class PositiveControlResult
        {
            public int requestedBytes;
            public long counterBefore;
            public long counterAfter;
            public long differenceBytes;
            public bool passed;
        }

        [Serializable]
        private sealed class D3KnownAnswerReceipt
        {
            public string schema;
            public string studyId;
            public string authorizationId;
            public string status;
            public string counterId;
            public string counterScope;
            public bool nativeAllocationsIncluded;
            public int negativeControlIntervals;
            public long negativeControlMaximumAllowedBytes;
            public long negativeControlObservedMaximumBytes;
            public long negativeControlObservedTotalBytes;
            public long[] negativeControlDifferencesBytes;
            public bool negativeControlPassed;
            public PositiveControlResult[] positiveControls;
            public bool positiveControlsPassed;
            public long requiredScaleSeparationBytes;
            public long observedScaleSeparationBytes;
            public bool scaleSeparationPassed;
            public string counterSourceRelativePath;
            public string counterSourceSha256;
            public string authorizationRelativePath;
            public string authorizationSha256;
            public string unityVersion;
            public string frameworkDescription;
            public string runtimeVersion;
            public bool is64BitProcess;
            public int processId;
            public string commandLineSha256;
            public bool plannerConstructed;
            public bool algorithmLaneExecuted;
            public int qualificationObservationCount;
            public int formalObservationCount;
            public string createdAtUtc;
        }
    }
}
#endif
