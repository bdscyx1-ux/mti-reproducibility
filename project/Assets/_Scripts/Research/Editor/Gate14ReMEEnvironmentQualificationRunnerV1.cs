#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Qualification-only harness for the frozen Gate14Re-ME D2/D3/D4/clock
    /// instruments. It never creates a measured root or constructs a planner.
    /// </summary>
    public static class Gate14ReMEEnvironmentQualificationRunnerV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationSchema = "gate14re-me-runtime-qualification-authorization-v1";
        private const string AuthorizationStatus = "AUTHORIZED_RUNTIME_QUALIFICATION_ONLY";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/csharp-instruments";
        private const string ExpectedImplementationManifestSha256 = "9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4";
        private const string ExpectedPriorFreezeReceiptSha256 = "43c9dba8b49a1efe0802f6046170be57506c027af9ac764138843c60eef669f7";

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-runtime-authorization"));
                string authorizationSha256 = RequiredSha256(arguments, "--g14me-runtime-authorization-sha256");
                Require(Sha256File(authorizationPath) == authorizationSha256, "Runtime-qualification authorization hash mismatch.");
                RuntimeAuthorization authorization = ReadJson<RuntimeAuthorization>(authorizationPath);
                ValidateAuthorization(authorization);

                string implementationManifestPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-implementation-manifest"));
                string implementationManifestSha256 = RequiredSha256(arguments, "--g14me-implementation-manifest-sha256");
                Require(implementationManifestSha256 == ExpectedImplementationManifestSha256 &&
                        implementationManifestSha256 == authorization.priorSourceFreeze.implementationManifestSha256 &&
                        Sha256File(implementationManifestPath) == implementationManifestSha256,
                    "Frozen implementation-manifest binding mismatch.");

                string priorFreezeReceiptPath = ResolveExistingFile(projectRoot, authorization.priorSourceFreeze.freezeReceiptRelativePath);
                Require(authorization.priorSourceFreeze.freezeReceiptSha256 == ExpectedPriorFreezeReceiptSha256 &&
                        Sha256File(priorFreezeReceiptPath) == ExpectedPriorFreezeReceiptSha256,
                    "Prior source-freeze receipt binding mismatch.");
                RequireProhibitedRootsAbsent(projectRoot);

                string outputDirectory = ResolveOutputDirectory(projectRoot, Required(arguments, "--g14me-output-dir"));
                Require(RelativePath(projectRoot, outputDirectory) == ExpectedOutputRelativePath,
                    "C# instrument output path is outside the exact verification-only path.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory),
                    "C# instrument output already exists; overwrite or resume is prohibited.");
                string parent = Directory.GetParent(outputDirectory).FullName;
                Require(Directory.Exists(parent), "Verification parent must already exist.");
                Directory.CreateDirectory(outputDirectory);

                ResearchNavigationGrid grid = new ResearchNavigationGrid(3, 3, 1f);
                Gate14ReMECountingGridV1 proxy = new Gate14ReMECountingGridV1(grid);
                GridCoordinate coordinate = new GridCoordinate(1, 1);
                long versionBefore = proxy.Version;
                proxy.BeginWindow();
                bool contained = proxy.Contains(coordinate);
                bool walkable = proxy.IsWalkable(coordinate);
                float cost = proxy.GetTraversalCost(coordinate);
                Gate14ReMEGridCounterSnapshotV1 counts = proxy.EndWindow();
                bool gridReadKnownAnswerPassed = counts.containsCalls == 1L &&
                                                 counts.isWalkableCalls == 1L &&
                                                 counts.getTraversalCostCalls == 1L &&
                                                 counts.totalCalls == 3L;
                bool gridReadSemanticInvariancePassed = contained && walkable && cost == 1f && proxy.Version == versionBefore;

                long allocationBefore = Gate14ReMEAllocationCounterV1.Capture();
                byte[] positiveControl = new byte[1024 * 1024];
                positiveControl[positiveControl.Length - 1] = 1;
                long allocationAfter = Gate14ReMEAllocationCounterV1.Capture();
                long allocationDifference = Gate14ReMEAllocationCounterV1.Difference(allocationBefore, allocationAfter);
                bool allocationCounterPassed = allocationAfter > allocationBefore && allocationDifference >= positiveControl.Length;

                bool clockMonotonicityPassed = true;
                long previous = Stopwatch.GetTimestamp();
                for (int index = 0; index < 10000; index++)
                {
                    long current = Stopwatch.GetTimestamp();
                    if (current < previous)
                    {
                        clockMonotonicityPassed = false;
                        break;
                    }
                    previous = current;
                }

                bool persistentStateSizerPassed = Gate14ReMEPersistentStateSizerV1.RunSyntheticFixture();
                bool passed = gridReadKnownAnswerPassed && gridReadSemanticInvariancePassed && allocationCounterPassed &&
                              persistentStateSizerPassed && clockMonotonicityPassed;
                RuntimeInstrumentReceipt receipt = new RuntimeInstrumentReceipt
                {
                    schema = "gate14re-me-runtime-instrument-qualification-receipt-v1",
                    studyId = StudyId,
                    authorizationId = authorization.authorizationId,
                    status = passed ? "PASS_CSHARP_D2_D3_D4_CLOCK_KNOWN_ANSWER" : "FAIL_CLOSED_CSHARP_INSTRUMENT_KNOWN_ANSWER",
                    gridReadProxyKnownAnswerPassed = gridReadKnownAnswerPassed,
                    gridReadProxySemanticInvariancePassed = gridReadSemanticInvariancePassed,
                    gridReadContainsCalls = counts.containsCalls,
                    gridReadIsWalkableCalls = counts.isWalkableCalls,
                    gridReadGetTraversalCostCalls = counts.getTraversalCostCalls,
                    gridReadTotalCalls = counts.totalCalls,
                    allocationCounterPositiveControlPassed = allocationCounterPassed,
                    allocationCounterDifferenceBytes = allocationDifference,
                    allocationPositiveControlBytes = positiveControl.Length,
                    persistentStateSizerSyntheticFixturePassed = persistentStateSizerPassed,
                    clockMonotonicityPassed = clockMonotonicityPassed,
                    clockSamples = 10000,
                    plannerConstructed = false,
                    algorithmLaneExecuted = false,
                    qualificationObservationCount = 0,
                    implementationManifestSha256 = implementationManifestSha256,
                    runtimeAuthorizationSha256 = authorizationSha256,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "instrument-runtime-receipt.v1.json"), receipt);
                Require(passed, "One or more C# runtime instrument known-answer controls failed.");
                exitCode = 0;
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogError("Gate14Re-ME runtime qualification failed closed: " + exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static void ValidateAuthorization(RuntimeAuthorization authorization)
        {
            Require(authorization != null && authorization.schema == AuthorizationSchema && authorization.studyId == StudyId &&
                    authorization.status == AuthorizationStatus && authorization.authorizationId == "gate14re-me-runtime-qualification-attempt-001",
                "Runtime-qualification authorization identity mismatch.");
            Require(authorization.authorizedScope != null && authorization.authorizedScope.installTypedParquetEngine &&
                    authorization.authorizedScope.freezeTypedParquetEngine && authorization.authorizedScope.compileFrozenUnityImplementation &&
                    authorization.authorizedScope.runD2GridReadProxyKnownAnswer && authorization.authorizedScope.runD3AllocationCounterKnownAnswer &&
                    authorization.authorizedScope.runD4PersistentStateSizerKnownAnswer && authorization.authorizedScope.runClockMonotonicityKnownAnswer &&
                    authorization.authorizedScope.runDataExporterKnownAnswer,
                "Required runtime-qualification scope is absent.");
            Require(authorization.prohibitedScope != null && !authorization.prohibitedScope.qualificationScheduleGeneration &&
                    !authorization.prohibitedScope.qualificationInputGeneration && !authorization.prohibitedScope.anonymousIdentityMapGeneration &&
                    !authorization.prohibitedScope.qualificationMeasuredRootCreation && !authorization.prohibitedScope.algorithmLaneExecution &&
                    !authorization.prohibitedScope.formalInputGeneration && !authorization.prohibitedScope.formalMeasuredRootCreation &&
                    !authorization.prohibitedScope.formalCollection && !authorization.prohibitedScope.formalAnalysis &&
                    !authorization.prohibitedScope.algorithmRanking && !authorization.prohibitedScope.winnerAdjudication,
                "Runtime authorization widens into prohibited experimental scope.");
            Require(authorization.priorSourceFreeze != null && authorization.reservedPaths != null &&
                    authorization.reservedPaths.csharpInstrumentOutputRelativePath == ExpectedOutputRelativePath,
                "Runtime authorization path or source-freeze binding is incomplete.");
        }

        private static void RequireProhibitedRootsAbsent(string projectRoot)
        {
            string[] roots =
            {
                "Research/PilotRuns/Gate14Re-ME",
                "Research/FormalRuns/Gate14Re-ME",
                "Research/Analysis/Gate14Re-ME",
                "Research/Exports/Gate14Re-ME"
            };
            for (int index = 0; index < roots.Length; index++)
            {
                Require(!Directory.Exists(Path.Combine(projectRoot, roots[index].Replace('/', Path.DirectorySeparatorChar))),
                    "A prohibited measured, analysis, or export root exists: " + roots[index]);
            }
        }

        private static Dictionary<string, string> ParseArguments(string[] arguments)
        {
            Dictionary<string, string> parsed = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index + 1 < arguments.Length; index++)
            {
                if (arguments[index].StartsWith("--g14me-", StringComparison.Ordinal))
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
                byte[] hash = algorithm.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(hash.Length * 2);
                for (int index = 0; index < hash.Length; index++) builder.Append(hash[index].ToString("x2"));
                return builder.ToString();
            }
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
        private sealed class RuntimeAuthorization
        {
            public string schema;
            public string studyId;
            public string authorizationId;
            public string status;
            public AuthorizedScope authorizedScope;
            public ProhibitedScope prohibitedScope;
            public PriorSourceFreeze priorSourceFreeze;
            public ReservedPaths reservedPaths;
        }

        [Serializable]
        private sealed class AuthorizedScope
        {
            public bool installTypedParquetEngine;
            public bool freezeTypedParquetEngine;
            public bool compileFrozenUnityImplementation;
            public bool runD2GridReadProxyKnownAnswer;
            public bool runD3AllocationCounterKnownAnswer;
            public bool runD4PersistentStateSizerKnownAnswer;
            public bool runClockMonotonicityKnownAnswer;
            public bool runDataExporterKnownAnswer;
        }

        [Serializable]
        private sealed class ProhibitedScope
        {
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
        private sealed class PriorSourceFreeze
        {
            public string implementationManifestRelativePath;
            public string implementationManifestSha256;
            public string freezeReceiptRelativePath;
            public string freezeReceiptSha256;
        }

        [Serializable]
        private sealed class ReservedPaths
        {
            public string csharpInstrumentOutputRelativePath;
        }

        [Serializable]
        private sealed class RuntimeInstrumentReceipt
        {
            public string schema;
            public string studyId;
            public string authorizationId;
            public string status;
            public bool gridReadProxyKnownAnswerPassed;
            public bool gridReadProxySemanticInvariancePassed;
            public long gridReadContainsCalls;
            public long gridReadIsWalkableCalls;
            public long gridReadGetTraversalCostCalls;
            public long gridReadTotalCalls;
            public bool allocationCounterPositiveControlPassed;
            public long allocationCounterDifferenceBytes;
            public int allocationPositiveControlBytes;
            public bool persistentStateSizerSyntheticFixturePassed;
            public bool clockMonotonicityPassed;
            public int clockSamples;
            public bool plannerConstructed;
            public bool algorithmLaneExecuted;
            public int qualificationObservationCount;
            public string implementationManifestSha256;
            public string runtimeAuthorizationSha256;
            public string createdAtUtc;
        }
    }
}
#endif
