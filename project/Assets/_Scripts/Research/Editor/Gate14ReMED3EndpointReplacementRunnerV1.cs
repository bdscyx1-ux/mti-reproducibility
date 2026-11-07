#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V2;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// One-shot D3-v2 endpoint known-answer harness. It never constructs a
    /// planner, creates a measured root, or executes an algorithm lane.
    /// </summary>
    public static class Gate14ReMED3EndpointReplacementRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-endpoint-replacement-attempt-002";
        private const string AuthorizationSchema = "gate14re-me-d3-endpoint-replacement-authorization-v1";
        private const string AuthorizationStatus = "AUTHORIZED_D3_ENDPOINT_REPLACEMENT_ONLY";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/d3-known-answer";
        private const string ExpectedCounterSourceRelativePath = "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs";
        private const string ExpectedProspectiveContractRelativePath = "Research/Gate14Re-ME/Execution/v2/d3-managed-heap-occupancy-contract.prospective.v1.json";
        private const string ExpectedPriorAmendmentFailureSha256 = "abffc0f216a18666ffb046ab0d7ebe9058e54a15cb07d3ecadd5715352c91ee1";
        private const string ExpectedPriorAmendmentFreezeSha256 = "4c2671b3158e9aaa1276e133778850adf44c5ccde8734110e734548abbb21074";
        private const string ExpectedStatusV5Sha256 = "66b6a3adbd2c889d19994fa4f3b2a1e5f69cbe60bddb81040b713e3013c3dc80";
        private const int NegativeControlPairs = 64;
        private const long NegativeControlMaximumAbsoluteDeltaBytes = 65536L;
        private const int SmallPositiveControlBytes = 8388608;
        private const long SmallPositiveMinimumDeltaBytes = 7549748L;
        private const int LargePositiveControlBytes = 33554432;
        private const long LargePositiveMinimumDeltaBytes = 30198989L;
        private const long RequiredScaleSeparationBytes = 22649242L;
        private const int ReclamationControlBytes = 16777216;
        private const long ReclamationMinimumAllocationDeltaBytes = 15099495L;
        private const long ReclamationMinimumRecoveredBytes = 13421773L;
        private const long PostReclamationBaselineAllowanceBytes = 2097152L;

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;

                string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-d3v2-authorization"));
                string authorizationSha256 = RequiredSha256(arguments, "--g14me-d3v2-authorization-sha256");
                Require(Sha256File(authorizationPath) == authorizationSha256, "D3-v2 authorization hash mismatch.");
                D3Authorization authorization = ReadJson<D3Authorization>(authorizationPath);
                ValidateAuthorization(authorization, projectRoot);

                string counterSourcePath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-d3v2-counter-source"));
                string counterSourceSha256 = RequiredSha256(arguments, "--g14me-d3v2-counter-source-sha256");
                Require(Sha256File(counterSourcePath) == counterSourceSha256, "D3-v2 counter source hash mismatch.");
                Require(RelativePath(projectRoot, counterSourcePath) == ExpectedCounterSourceRelativePath, "Unexpected D3-v2 source path.");

                string prospectiveContractPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-d3v2-prospective-contract"));
                string prospectiveContractSha256 = RequiredSha256(arguments, "--g14me-d3v2-prospective-contract-sha256");
                Require(Sha256File(prospectiveContractPath) == prospectiveContractSha256, "D3-v2 prospective contract hash mismatch.");
                Require(RelativePath(projectRoot, prospectiveContractPath) == ExpectedProspectiveContractRelativePath, "Unexpected prospective-contract path.");

                RequireProhibitedRootsAbsent(projectRoot);
                string outputDirectory = ResolveOutputDirectory(projectRoot, Required(arguments, "--g14me-d3v2-output-dir"));
                Require(RelativePath(projectRoot, outputDirectory) == ExpectedOutputRelativePath, "D3-v2 output path is outside the exact verification-only path.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "D3-v2 output already exists; overwrite or resume is prohibited.");
                string outputParent = Directory.GetParent(outputDirectory).FullName;
                Require(Directory.Exists(outputParent), "D3-v2 verification parent must already exist.");
                Directory.CreateDirectory(outputDirectory);

                // Warm up outside all known-answer intervals.
                long warmupStart = Gate14ReMEManagedHeapOccupancyV1.Capture();
                long warmupEnd = Gate14ReMEManagedHeapOccupancyV1.Capture();
                Gate14ReMEManagedHeapOccupancyV1.SignedDelta(warmupStart, warmupEnd);
                ForceFullCollection();

                NegativeControlResult[] negativeResults = new NegativeControlResult[NegativeControlPairs];
                long negativeMaximumAbsoluteDelta = 0L;
                bool negativeControlPassed = true;
                for (int index = 0; index < NegativeControlPairs; index++)
                {
                    long start = Gate14ReMEManagedHeapOccupancyV1.Capture();
                    long end = Gate14ReMEManagedHeapOccupancyV1.Capture();
                    long signedDelta = Gate14ReMEManagedHeapOccupancyV1.SignedDelta(start, end);
                    long absoluteDelta = AbsoluteChecked(signedDelta);
                    bool pairPassed = absoluteDelta <= NegativeControlMaximumAbsoluteDeltaBytes;
                    negativeResults[index] = new NegativeControlResult
                    {
                        pairIndex = index,
                        startBytes = start,
                        endBytes = end,
                        signedDeltaBytes = signedDelta,
                        absoluteDeltaBytes = absoluteDelta,
                        passed = pairPassed
                    };
                    if (absoluteDelta > negativeMaximumAbsoluteDelta) negativeMaximumAbsoluteDelta = absoluteDelta;
                    negativeControlPassed = negativeControlPassed && pairPassed;
                }

                PositiveControlResult smallPositive = RunPositiveControl(SmallPositiveControlBytes, SmallPositiveMinimumDeltaBytes);
                PositiveControlResult largePositive = RunPositiveControl(LargePositiveControlBytes, LargePositiveMinimumDeltaBytes);
                long observedScaleSeparation = checked(largePositive.signedDeltaBytes - smallPositive.signedDeltaBytes);
                bool scaleSeparationPassed = observedScaleSeparation >= RequiredScaleSeparationBytes;

                ReclamationControlResult reclamation = RunReclamationControl();
                bool passedAll = negativeControlPassed && smallPositive.passed && largePositive.passed && scaleSeparationPassed && reclamation.passed;

                D3KnownAnswerReceipt receipt = new D3KnownAnswerReceipt
                {
                    schema = "gate14re-me-d3-endpoint-replacement-known-answer-receipt-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = passedAll ? "PASS_D3_MANAGED_HEAP_OCCUPANCY_KNOWN_ANSWER" : "FAIL_CLOSED_D3_MANAGED_HEAP_OCCUPANCY_KNOWN_ANSWER",
                    endpointId = "D3",
                    endpointSemanticVersion = 2,
                    endpointName = "event-boundary managed-heap occupancy",
                    counterId = Gate14ReMEManagedHeapOccupancyV1.CounterId,
                    primaryRawField = "eventGroupManagedHeapBytesEnd",
                    rawFields = new[] { "eventGroupManagedHeapBytesStart", "eventGroupManagedHeapBytesEnd", "eventGroupManagedHeapSignedDeltaBytes" },
                    cumulativeAllocationCounter = false,
                    nativeAllocationsIncluded = false,
                    negativeSignedDeltaAllowed = true,
                    clampOrCensorAllowed = false,
                    negativeControlPairs = NegativeControlPairs,
                    negativeControlMaximumAllowedAbsoluteDeltaBytes = NegativeControlMaximumAbsoluteDeltaBytes,
                    negativeControlObservedMaximumAbsoluteDeltaBytes = negativeMaximumAbsoluteDelta,
                    negativeControls = negativeResults,
                    negativeControlPassed = negativeControlPassed,
                    positiveControls = new[] { smallPositive, largePositive },
                    positiveControlsPassed = smallPositive.passed && largePositive.passed,
                    requiredScaleSeparationBytes = RequiredScaleSeparationBytes,
                    observedScaleSeparationBytes = observedScaleSeparation,
                    scaleSeparationPassed = scaleSeparationPassed,
                    reclamationControl = reclamation,
                    reclamationControlPassed = reclamation.passed,
                    counterSourceRelativePath = RelativePath(projectRoot, counterSourcePath),
                    counterSourceSha256 = counterSourceSha256,
                    prospectiveContractRelativePath = RelativePath(projectRoot, prospectiveContractPath),
                    prospectiveContractSha256 = prospectiveContractSha256,
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
                    qualificationScheduleRows = 0,
                    qualificationInputCount = 0,
                    anonymousIdentityMappingCount = 0,
                    qualificationObservationCount = 0,
                    formalObservationCount = 0,
                    dataExporterKnownAnswerRun = false,
                    formalAnalysisPerformed = false,
                    rankingOrWinnerComputed = false,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "d3-known-answer-receipt.v1.json"), receipt);
                Require(passedAll, "One or more prospective D3-v2 endpoint controls failed.");
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

        private static PositiveControlResult RunPositiveControl(int requestedBytes, long minimumDeltaBytes)
        {
            ForceFullCollection();
            long start = Gate14ReMEManagedHeapOccupancyV1.Capture();
            long end = AllocateTouchRetainAndCapture(requestedBytes);
            long signedDelta = Gate14ReMEManagedHeapOccupancyV1.SignedDelta(start, end);
            return new PositiveControlResult
            {
                requestedBytes = requestedBytes,
                minimumDeltaBytes = minimumDeltaBytes,
                startBytes = start,
                endBytes = end,
                signedDeltaBytes = signedDelta,
                passed = signedDelta >= minimumDeltaBytes
            };
        }

        private static ReclamationControlResult RunReclamationControl()
        {
            ForceFullCollection();
            long baseline = Gate14ReMEManagedHeapOccupancyV1.Capture();
            long peak = AllocateTouchRetainAndCapture(ReclamationControlBytes);
            long allocationDelta = Gate14ReMEManagedHeapOccupancyV1.SignedDelta(baseline, peak);

            // The retained array lived in a no-inline helper and is out of scope here.
            ForceFullCollection();
            long afterReclamation = Gate14ReMEManagedHeapOccupancyV1.Capture();
            long recovered = checked(peak - afterReclamation);
            long baselineDrift = Gate14ReMEManagedHeapOccupancyV1.SignedDelta(baseline, afterReclamation);
            bool passed = allocationDelta >= ReclamationMinimumAllocationDeltaBytes &&
                          recovered >= ReclamationMinimumRecoveredBytes &&
                          afterReclamation <= checked(baseline + PostReclamationBaselineAllowanceBytes);
            return new ReclamationControlResult
            {
                requestedBytes = ReclamationControlBytes,
                minimumAllocationDeltaBytes = ReclamationMinimumAllocationDeltaBytes,
                minimumRecoveredBytes = ReclamationMinimumRecoveredBytes,
                postReclamationBaselineAllowanceBytes = PostReclamationBaselineAllowanceBytes,
                baselineBytes = baseline,
                peakBytes = peak,
                afterReclamationBytes = afterReclamation,
                allocationSignedDeltaBytes = allocationDelta,
                recoveredBytes = recovered,
                postReclamationBaselineSignedDeltaBytes = baselineDrift,
                passed = passed
            };
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static long AllocateTouchRetainAndCapture(int requestedBytes)
        {
            byte[] retained = new byte[requestedBytes];
            for (int offset = 0; offset < retained.Length; offset += 4096)
            {
                retained[offset] = (byte)((offset / 4096) & 255);
            }
            retained[retained.Length - 1] = 1;
            long occupied = Gate14ReMEManagedHeapOccupancyV1.Capture();
            GC.KeepAlive(retained);
            return occupied;
        }

        private static void ForceFullCollection()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        private static long AbsoluteChecked(long value)
        {
            return value >= 0L ? value : checked(-value);
        }

        private static void ValidateAuthorization(D3Authorization authorization, string projectRoot)
        {
            Require(authorization != null && authorization.schema == AuthorizationSchema && authorization.studyId == StudyId &&
                    authorization.authorizationId == AuthorizationId && authorization.status == AuthorizationStatus,
                "D3-v2 authorization identity mismatch.");
            Require(authorization.authorizedScope != null &&
                    authorization.authorizedScope.retireOriginalD3DefinitionProspectively &&
                    authorization.authorizedScope.defineManagedHeapOccupancyEndpoint &&
                    authorization.authorizedScope.createVersionedD3EndpointSource &&
                    authorization.authorizedScope.createD3OnlyKnownAnswerHarness &&
                    authorization.authorizedScope.runOneD3OnlyUnityKnownAnswer &&
                    authorization.authorizedScope.runPositiveNegativeAndReclamationControls &&
                    authorization.authorizedScope.createVersionedD3InstrumentContractAfterPass &&
                    authorization.authorizedScope.createSourceOnlyScientificFreezeAfterPass,
                "Required D3-v2 authorization is incomplete.");
            Require(authorization.prohibitedScope != null &&
                    !authorization.prohibitedScope.modifyPriorFrozenEvidence &&
                    !authorization.prohibitedScope.retryPriorD3Attempts &&
                    !authorization.prohibitedScope.runFullRuntimeQualificationAttempt002 &&
                    !authorization.prohibitedScope.runDataExporterKnownAnswer &&
                    !authorization.prohibitedScope.modifyAlgorithmImplementations &&
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
                "A prohibited D3-v2 scope was enabled.");
            Require(authorization.priorFailedD3Amendment != null &&
                    authorization.priorFailedD3Amendment.failureReceiptSha256 == ExpectedPriorAmendmentFailureSha256 &&
                    authorization.priorFailedD3Amendment.freezeReceiptSha256 == ExpectedPriorAmendmentFreezeSha256 &&
                    authorization.priorFailedD3Amendment.statusSha256 == ExpectedStatusV5Sha256,
                "Prior failed D3-amendment bindings mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedD3Amendment.failureReceiptRelativePath)) == ExpectedPriorAmendmentFailureSha256,
                "Prior D3-amendment failure receipt hash mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedD3Amendment.freezeReceiptRelativePath)) == ExpectedPriorAmendmentFreezeSha256,
                "Prior D3-amendment freeze receipt hash mismatch.");
            Require(Sha256File(ResolveExistingFile(projectRoot, authorization.priorFailedD3Amendment.statusRelativePath)) == ExpectedStatusV5Sha256,
                "Status-v5 hash mismatch.");
            Require(authorization.knownAnswerDesign != null &&
                    authorization.knownAnswerDesign.negativeControlPairs == NegativeControlPairs &&
                    authorization.knownAnswerDesign.negativeControlMaximumAbsoluteDeltaBytes == NegativeControlMaximumAbsoluteDeltaBytes &&
                    authorization.knownAnswerDesign.positiveControlBytes != null &&
                    authorization.knownAnswerDesign.positiveControlBytes.Length == 2 &&
                    authorization.knownAnswerDesign.positiveControlBytes[0] == SmallPositiveControlBytes &&
                    authorization.knownAnswerDesign.positiveControlBytes[1] == LargePositiveControlBytes &&
                    authorization.knownAnswerDesign.positiveControlMinimumObservedFractionNumerator == 9 &&
                    authorization.knownAnswerDesign.positiveControlMinimumObservedFractionDenominator == 10 &&
                    authorization.knownAnswerDesign.scaleSeparationMinimumBytes == RequiredScaleSeparationBytes &&
                    authorization.knownAnswerDesign.reclamationControlBytes == ReclamationControlBytes &&
                    authorization.knownAnswerDesign.reclamationMinimumAllocationDeltaBytes == ReclamationMinimumAllocationDeltaBytes &&
                    authorization.knownAnswerDesign.reclamationMinimumRecoveredBytes == ReclamationMinimumRecoveredBytes &&
                    authorization.knownAnswerDesign.postReclamationBaselineAllowanceBytes == PostReclamationBaselineAllowanceBytes &&
                    !authorization.knownAnswerDesign.thresholdsMayBeRelaxedAfterExecution,
                "Prospective D3-v2 thresholds mismatch.");
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
                if (arguments[index].StartsWith("--g14me-d3v2-", StringComparison.Ordinal))
                {
                    Require(!parsed.ContainsKey(arguments[index]), "Duplicate argument: " + arguments[index]);
                    parsed.Add(arguments[index], arguments[index + 1]);
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
            using (FileStream stream = File.OpenRead(path)) return Hex(algorithm.ComputeHash(stream));
        }

        private static string Sha256Text(string value)
        {
            using (SHA256 algorithm = SHA256.Create()) return Hex(algorithm.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty)));
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
            public PriorFailedD3Amendment priorFailedD3Amendment;
            public KnownAnswerDesign knownAnswerDesign;
        }

        [Serializable]
        private sealed class AuthorizedScope
        {
            public bool retireOriginalD3DefinitionProspectively;
            public bool defineManagedHeapOccupancyEndpoint;
            public bool createVersionedD3EndpointSource;
            public bool createD3OnlyKnownAnswerHarness;
            public bool runOneD3OnlyUnityKnownAnswer;
            public bool runPositiveNegativeAndReclamationControls;
            public bool createVersionedD3InstrumentContractAfterPass;
            public bool createSourceOnlyScientificFreezeAfterPass;
        }

        [Serializable]
        private sealed class ProhibitedScope
        {
            public bool modifyPriorFrozenEvidence;
            public bool retryPriorD3Attempts;
            public bool runFullRuntimeQualificationAttempt002;
            public bool runDataExporterKnownAnswer;
            public bool modifyAlgorithmImplementations;
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
        private sealed class PriorFailedD3Amendment
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
            public int negativeControlPairs;
            public long negativeControlMaximumAbsoluteDeltaBytes;
            public int[] positiveControlBytes;
            public int positiveControlMinimumObservedFractionNumerator;
            public int positiveControlMinimumObservedFractionDenominator;
            public long scaleSeparationMinimumBytes;
            public int reclamationControlBytes;
            public long reclamationMinimumAllocationDeltaBytes;
            public long reclamationMinimumRecoveredBytes;
            public long postReclamationBaselineAllowanceBytes;
            public bool thresholdsMayBeRelaxedAfterExecution;
        }

        [Serializable]
        private sealed class NegativeControlResult
        {
            public int pairIndex;
            public long startBytes;
            public long endBytes;
            public long signedDeltaBytes;
            public long absoluteDeltaBytes;
            public bool passed;
        }

        [Serializable]
        private sealed class PositiveControlResult
        {
            public int requestedBytes;
            public long minimumDeltaBytes;
            public long startBytes;
            public long endBytes;
            public long signedDeltaBytes;
            public bool passed;
        }

        [Serializable]
        private sealed class ReclamationControlResult
        {
            public int requestedBytes;
            public long minimumAllocationDeltaBytes;
            public long minimumRecoveredBytes;
            public long postReclamationBaselineAllowanceBytes;
            public long baselineBytes;
            public long peakBytes;
            public long afterReclamationBytes;
            public long allocationSignedDeltaBytes;
            public long recoveredBytes;
            public long postReclamationBaselineSignedDeltaBytes;
            public bool passed;
        }

        [Serializable]
        private sealed class D3KnownAnswerReceipt
        {
            public string schema;
            public string studyId;
            public string authorizationId;
            public string status;
            public string endpointId;
            public int endpointSemanticVersion;
            public string endpointName;
            public string counterId;
            public string primaryRawField;
            public string[] rawFields;
            public bool cumulativeAllocationCounter;
            public bool nativeAllocationsIncluded;
            public bool negativeSignedDeltaAllowed;
            public bool clampOrCensorAllowed;
            public int negativeControlPairs;
            public long negativeControlMaximumAllowedAbsoluteDeltaBytes;
            public long negativeControlObservedMaximumAbsoluteDeltaBytes;
            public NegativeControlResult[] negativeControls;
            public bool negativeControlPassed;
            public PositiveControlResult[] positiveControls;
            public bool positiveControlsPassed;
            public long requiredScaleSeparationBytes;
            public long observedScaleSeparationBytes;
            public bool scaleSeparationPassed;
            public ReclamationControlResult reclamationControl;
            public bool reclamationControlPassed;
            public string counterSourceRelativePath;
            public string counterSourceSha256;
            public string prospectiveContractRelativePath;
            public string prospectiveContractSha256;
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
            public int qualificationScheduleRows;
            public int qualificationInputCount;
            public int anonymousIdentityMappingCount;
            public int qualificationObservationCount;
            public int formalObservationCount;
            public bool dataExporterKnownAnswerRun;
            public bool formalAnalysisPerformed;
            public bool rankingOrWinnerComputed;
            public string createdAtUtc;
        }
    }
}
#endif
