#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.InputSchemaCorrigendumAttempt001
{
    [Serializable]
    internal sealed class SchemaCorrigendumAuthorizationHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    internal sealed class PlanningSchemaBindingHeaderV2
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public int version;
    }

    [Serializable]
    internal sealed class SchemaKnownAnswerHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public bool passed;
        public bool terminal;
    }

    [Serializable]
    internal sealed class SchemaCorrigendumFileBindingV1
    {
        public string role;
        public string relativePath;
        public long lengthBytes;
        public string expectedSha256;
        public string actualSha256;
        public bool matched;
    }

    [Serializable]
    internal sealed class InputSchemaCompatibilitySelfCheckReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string createdAtUtc;
        public string completedAtUtc;
        public string unityVersion;
        public string unityExecutablePath;
        public string unityExecutableSha256;
        public bool passed;
        public bool terminal;
        public bool authorizationHeaderPassed;
        public bool planningBindingHeaderPassed;
        public bool schemaKnownAnswerReceiptPassed;
        public bool parentAndProtectedHashesPassed;
        public bool reflectionTargetFound;
        public bool jsonUtilitySerializedTopology;
        public bool jsonUtilityRoundTripPreservedTopology;
        public bool positiveOracleHeaderPassed;
        public bool missingTopologyJsonControlConstructed;
        public bool missingTopologyOracleHeaderFailedAsExpected;
        public bool mismatchedTopologyJsonControlConstructed;
        public bool mismatchedTopologyOracleHeaderFailedAsExpected;
        public string expectedOracleFailureMessage;
        public string missingTopologyObservedFailure;
        public string mismatchedTopologyObservedFailure;
        public bool prohibitedRootsAbsentBefore;
        public bool prohibitedRootsAbsentAfter;
        public bool plannerConstructedOrInvoked;
        public bool algorithmLaneExecuted;
        public bool scheduleInputOrIdentityGenerated;
        public bool qualificationMeasuredRootCreated;
        public bool formalCollectionPerformed;
        public bool formalAnalysisPerformed;
        public bool algorithmRankingPerformed;
        public bool winnerAdjudicationPerformed;
        public SchemaCorrigendumFileBindingV1[] bindings;
        public string exceptionType;
        public string exactFailure;
        public string stackTrace;
    }

    public static class Gate14ReMEInputSchemaCompatibilitySelfCheckV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-001";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/unity-self-check-output";
        private const string ExpectedOracleFailure = "Event-group topology must match the input context.";
        private const string ExpectedUnityExecutableSha256 = "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf";

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = string.Empty;
            InputSchemaCompatibilitySelfCheckReceiptV1 receipt = CreateBaseReceipt();
            List<SchemaCorrigendumFileBindingV1> bindings = new List<SchemaCorrigendumFileBindingV1>();
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                outputDirectory = ResolveExactNewOutputDirectory(projectRoot, Required(arguments, "--g14me-schema-corrigendum-output"));

                receipt.prohibitedRootsAbsentBefore = ProhibitedRootsAbsent(projectRoot);
                Require(receipt.prohibitedRootsAbsentBefore, "A prohibited Gate14Re-ME measured root already exists.");

                Bind(projectRoot, bindings, "authorization",
                    "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Input_Schema_Compatibility_Corrigendum_Authorization.v1.json",
                    "dc8a9e5563e0b428f895f7de56265e78d51b3c57b59295fc9ad4f0bf86c7d6b6");
                Bind(projectRoot, bindings, "corrigendum-plan",
                    "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Input_Schema_Compatibility_Corrigendum_Plan.v1.md",
                    "6d93d2542baaccd82375ad364ad1ebfa2dc45c7e55bb4b52c917afc7b27fccbb");
                Bind(projectRoot, bindings, "parent-status-v11",
                    "Research/Gate14Re-ME/Gate14Re_ME_Status.v11.json",
                    "4bd0f8b512fec16daf3e5dd793caf8420fafd3f80b4f95cd3aca4981f469e47e");
                Bind(projectRoot, bindings, "retained-planning-failure",
                    "Research/Verification/Gate14Re-ME/qualification-planning-freeze-attempt-001/failure-receipt.v1.json",
                    "f3ebfb70faba9d48d39d12eeff5fe64cfc2776ac73c0b672e1ecf04273b4b2c6");
                Bind(projectRoot, bindings, "retained-preflight-audit",
                    "Research/Verification/Gate14Re-ME/qualification-planning-freeze-attempt-001/preflight-compatibility-audit.v1.json",
                    "68fa5cb6c4a3a9c87d29f06acb69dd93f2081f060f69e192478fdedf2231afcf");
                Bind(projectRoot, bindings, "legacy-input-schema-v1",
                    "Research/Gate14Re-ME/Execution/v1/load-qualification-input-schema.v1.json",
                    "12105816916eaadc6575ed28dc96a6bb4a9863d2dbbe70cc034ebcfbf1de2c6b");
                Bind(projectRoot, bindings, "corrected-input-schema-v2",
                    "Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json",
                    "1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117");
                Bind(projectRoot, bindings, "planning-schema-binding-v2",
                    "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json",
                    "abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7");
                Bind(projectRoot, bindings, "schema-known-answer-tool",
                    "Research/Gate14Re-ME/Tools/Test-Gate14ReMEInputSchemaCompatibilityV1.ps1",
                    "b7931734393352dca71397f293428bb18685c912bb41709e04a88db0a16c20c3");
                Bind(projectRoot, bindings, "schema-known-answer-receipt",
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/schema-known-answer-receipt.v1.json",
                    "76977549e66d3e98af3e4f214b507bda1bba9d5d13006762d0f004bd62f40358");
                Bind(projectRoot, bindings, "qualification-contracts-source",
                    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs",
                    "0e6a516c24eff27195b634227a96fde742eea6ef5899eaa7aeda7c514c2b7ee4");
                Bind(projectRoot, bindings, "reference-oracle-source",
                    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs",
                    "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25");
                Bind(projectRoot, bindings, "qualification-runner-v2-source",
                    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs",
                    "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73");
                Bind(projectRoot, bindings, "navigation-contracts-source",
                    "Assets/_Scripts/Research/Navigation/NavigationContracts.cs",
                    "7e074ec1fa13d9de2addeca4defa702fb773974d17615de3fffce93b5c4f5efa");
                receipt.parentAndProtectedHashesPassed = AllBindingsMatched(bindings);
                Require(receipt.parentAndProtectedHashesPassed, "One or more frozen bindings drifted.");

                receipt.unityExecutablePath = Path.GetFullPath(EditorApplication.applicationPath);
                receipt.unityExecutableSha256 = Sha256File(receipt.unityExecutablePath);
                Require(receipt.unityExecutableSha256 == ExpectedUnityExecutableSha256, "Unity executable hash mismatch.");

                SchemaCorrigendumAuthorizationHeaderV1 authorization = JsonUtility.FromJson<SchemaCorrigendumAuthorizationHeaderV1>(
                    ReadText(projectRoot, "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Input_Schema_Compatibility_Corrigendum_Authorization.v1.json"));
                receipt.authorizationHeaderPassed = authorization != null &&
                    authorization.schema == "gate14re-me-qualification-input-schema-compatibility-corrigendum-authorization-v1" &&
                    authorization.studyId == StudyId && authorization.authorizationId == AuthorizationId &&
                    authorization.status == "AUTHORIZED_MINIMUM_ALGORITHM_FREE_INPUT_SCHEMA_COMPATIBILITY_CORRIGENDUM";
                Require(receipt.authorizationHeaderPassed, "Corrigendum authorization header is invalid.");

                PlanningSchemaBindingHeaderV2 planningBinding = JsonUtility.FromJson<PlanningSchemaBindingHeaderV2>(
                    ReadText(projectRoot, "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json"));
                receipt.planningBindingHeaderPassed = planningBinding != null &&
                    planningBinding.schema == "gate14re-me-load-qualification-planning-schema-binding-v2" &&
                    planningBinding.studyId == StudyId && planningBinding.protocolId == "gate14re-me-load-qualification-v1" &&
                    planningBinding.status == "FROZEN_INPUT_VALIDATION_SCHEMA_CORRIGENDUM_PLANNING_PENDING" && planningBinding.version == 2;
                Require(receipt.planningBindingHeaderPassed, "Planning schema binding v2 header is invalid.");

                SchemaKnownAnswerHeaderV1 knownAnswer = JsonUtility.FromJson<SchemaKnownAnswerHeaderV1>(
                    ReadText(projectRoot, "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/schema-known-answer-receipt.v1.json"));
                receipt.schemaKnownAnswerReceiptPassed = knownAnswer != null &&
                    knownAnswer.schema == "gate14re-me-input-schema-compatibility-known-answer-receipt-v1" &&
                    knownAnswer.studyId == StudyId && knownAnswer.authorizationId == AuthorizationId &&
                    knownAnswer.status == "PASS_INPUT_SCHEMA_COMPATIBILITY_KNOWN_ANSWER" && knownAnswer.passed && knownAnswer.terminal;
                Require(receipt.schemaKnownAnswerReceiptPassed, "Schema known-answer receipt is not a terminal pass.");

                MethodInfo validateHeader = typeof(Gate14ReMEInputGeometryValidatorV1).GetMethod(
                    "ValidateGroupHeader",
                    BindingFlags.NonPublic | BindingFlags.Static,
                    null,
                    new Type[] { typeof(Gate14ReMEQualificationInputBundleV1), typeof(Gate14ReMEEventGroupV1), typeof(int) },
                    null);
                receipt.reflectionTargetFound = validateHeader != null && validateHeader.ReturnType == typeof(void);
                Require(receipt.reflectionTargetFound, "The actual private oracle-header validator was not found.");

                Gate14ReMEQualificationInputBundleV1 positiveSource = CreateSyntheticInput("compact");
                string positiveJson = JsonUtility.ToJson(positiveSource, false);
                receipt.jsonUtilitySerializedTopology = positiveJson.Contains("\"topology\":\"compact\"");
                Require(receipt.jsonUtilitySerializedTopology, "JsonUtility did not serialize event-group topology.");
                Gate14ReMEQualificationInputBundleV1 positiveRoundTrip = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(positiveJson);
                receipt.jsonUtilityRoundTripPreservedTopology = HasSingleTopology(positiveRoundTrip, "compact");
                Require(receipt.jsonUtilityRoundTripPreservedTopology, "JsonUtility did not preserve event-group topology on round trip.");
                validateHeader.Invoke(null, new object[] { positiveRoundTrip, positiveRoundTrip.eventGroups[0], 0 });
                receipt.positiveOracleHeaderPassed = true;

                string topologyToken = ",\"topology\":\"compact\"";
                string missingJson = positiveJson.Replace(topologyToken, string.Empty);
                receipt.missingTopologyJsonControlConstructed = missingJson != positiveJson &&
                    !missingJson.Contains("\"topology\"");
                Require(receipt.missingTopologyJsonControlConstructed, "Unable to construct the missing-topology JSON control.");
                Gate14ReMEQualificationInputBundleV1 missingRoundTrip = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(missingJson);
                receipt.missingTopologyOracleHeaderFailedAsExpected = InvokeExpectingFailure(
                    validateHeader, missingRoundTrip, out receipt.missingTopologyObservedFailure);
                Require(receipt.missingTopologyOracleHeaderFailedAsExpected,
                    "Missing topology did not fail through the actual oracle-header validator for the expected reason.");

                string mismatchedJson = positiveJson.Replace("\"topology\":\"compact\"", "\"topology\":\"bottleneck\"");
                receipt.mismatchedTopologyJsonControlConstructed = mismatchedJson != positiveJson &&
                    mismatchedJson.Contains("\"topology\":\"bottleneck\"");
                Require(receipt.mismatchedTopologyJsonControlConstructed, "Unable to construct the mismatched-topology JSON control.");
                Gate14ReMEQualificationInputBundleV1 mismatchedRoundTrip = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(mismatchedJson);
                receipt.mismatchedTopologyOracleHeaderFailedAsExpected = InvokeExpectingFailure(
                    validateHeader, mismatchedRoundTrip, out receipt.mismatchedTopologyObservedFailure);
                Require(receipt.mismatchedTopologyOracleHeaderFailedAsExpected,
                    "Mismatched topology did not fail through the actual oracle-header validator for the expected reason.");

                receipt.prohibitedRootsAbsentAfter = ProhibitedRootsAbsent(projectRoot);
                Require(receipt.prohibitedRootsAbsentAfter, "A prohibited Gate14Re-ME measured root appeared during the self-check.");

                receipt.passed = true;
                receipt.status = "PASS_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK";
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.passed = false;
                receipt.status = "FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK";
                receipt.exceptionType = exception.GetType().FullName;
                receipt.exactFailure = exception.Message;
                receipt.stackTrace = exception.ToString();
                UnityEngine.Debug.LogException(exception);
            }
            finally
            {
                receipt.terminal = true;
                receipt.completedAtUtc = DateTime.UtcNow.ToString("o");
                receipt.bindings = bindings.ToArray();
                receipt.expectedOracleFailureMessage = ExpectedOracleFailure;
                receipt.plannerConstructedOrInvoked = false;
                receipt.algorithmLaneExecuted = false;
                receipt.scheduleInputOrIdentityGenerated = false;
                receipt.qualificationMeasuredRootCreated = false;
                receipt.formalCollectionPerformed = false;
                receipt.formalAnalysisPerformed = false;
                receipt.algorithmRankingPerformed = false;
                receipt.winnerAdjudicationPerformed = false;
                try
                {
                    if (!string.IsNullOrEmpty(outputDirectory) && Directory.Exists(outputDirectory))
                    {
                        WriteJsonAtomic(Path.Combine(outputDirectory, "input-schema-compatibility-self-check-receipt.v1.json"), receipt);
                    }
                }
                catch (Exception writeFailure)
                {
                    exitCode = 4;
                    UnityEngine.Debug.LogError("Unable to preserve input-schema compatibility receipt: " + writeFailure);
                }
                EditorApplication.Exit(exitCode);
            }
        }

        private static InputSchemaCompatibilitySelfCheckReceiptV1 CreateBaseReceipt()
        {
            return new InputSchemaCompatibilitySelfCheckReceiptV1
            {
                schema = "gate14re-me-input-schema-compatibility-unity-self-check-receipt-v1",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                status = "IN_PROGRESS",
                createdAtUtc = DateTime.UtcNow.ToString("o"),
                unityVersion = Application.unityVersion,
                expectedOracleFailureMessage = ExpectedOracleFailure,
                passed = false,
                terminal = false
            };
        }

        private static Gate14ReMEQualificationInputBundleV1 CreateSyntheticInput(string topology)
        {
            return new Gate14ReMEQualificationInputBundleV1
            {
                schema = "gate14re-me-qualification-input-bundle-v1",
                studyId = StudyId,
                protocolId = "gate14re-me-load-qualification-v1",
                inputId = "unity-kat-input",
                superblockId = "unity-kat-superblock",
                designRegion = "core",
                seed = 1L,
                gridEdge = 64,
                agentCount = 8,
                changedCellCount = 1,
                changeTopology = "compact",
                graphProfile = "four_way_weighted_dense",
                sameTickAtomicPartitions = 1,
                contextStratumId = "unity-kat-context",
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                defaultTraversalCost = 1f,
                initialCellOverrides = new Gate14ReMECellStateV1[0],
                goal = new GridCoordinate(63, 63),
                starts = new[]
                {
                    new GridCoordinate(0, 0), new GridCoordinate(1, 0),
                    new GridCoordinate(2, 0), new GridCoordinate(3, 0),
                    new GridCoordinate(4, 0), new GridCoordinate(5, 0),
                    new GridCoordinate(6, 0), new GridCoordinate(7, 0)
                },
                eventGroups = new[]
                {
                    new Gate14ReMEEventGroupV1
                    {
                        eventGroupId = "unity-kat-event-00",
                        eventGroupIndex = 0,
                        cycleIndex = 0,
                        phase = "block",
                        topology = topology,
                        atomicPartitions = new[]
                        {
                            new Gate14ReMEAtomicPartitionV1
                            {
                                partitionIndex = 0,
                                changes = new[]
                                {
                                    new Gate14ReMECellStateV1
                                    {
                                        x = 20,
                                        y = 20,
                                        isWalkable = false,
                                        traversalCost = 1f
                                    }
                                }
                            }
                        }
                    }
                }
            };
        }

        private static bool HasSingleTopology(Gate14ReMEQualificationInputBundleV1 input, string topology)
        {
            return input != null && input.schema == "gate14re-me-qualification-input-bundle-v1" &&
                input.changeTopology == "compact" && input.eventGroups != null && input.eventGroups.Length == 1 &&
                input.eventGroups[0] != null && input.eventGroups[0].topology == topology;
        }

        private static bool InvokeExpectingFailure(
            MethodInfo validateHeader,
            Gate14ReMEQualificationInputBundleV1 input,
            out string observedFailure)
        {
            observedFailure = string.Empty;
            try
            {
                validateHeader.Invoke(null, new object[] { input, input.eventGroups[0], 0 });
                observedFailure = "NO_EXCEPTION";
                return false;
            }
            catch (TargetInvocationException exception)
            {
                Exception actual = exception.InnerException ?? exception;
                observedFailure = actual.Message;
                return observedFailure == ExpectedOracleFailure;
            }
        }

        private static bool ProhibitedRootsAbsent(string projectRoot)
        {
            string[] relativeRoots =
            {
                "Research/PilotRuns/Gate14Re-ME",
                "Research/FormalRuns/Gate14Re-ME",
                "Research/QualificationRuns/Gate14Re-ME",
                "Research/MeasuredRuns/Gate14Re-ME"
            };
            for (int index = 0; index < relativeRoots.Length; index++)
            {
                string fullPath = Path.GetFullPath(Path.Combine(projectRoot,
                    relativeRoots[index].Replace('/', Path.DirectorySeparatorChar)));
                if (Directory.Exists(fullPath) || File.Exists(fullPath)) return false;
            }
            return true;
        }

        private static void Bind(
            string projectRoot,
            List<SchemaCorrigendumFileBindingV1> bindings,
            string role,
            string relativePath,
            string expectedSha256)
        {
            string fullPath = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            Require(File.Exists(fullPath), "Missing bound file: " + relativePath);
            string actual = Sha256File(fullPath);
            FileInfo info = new FileInfo(fullPath);
            SchemaCorrigendumFileBindingV1 binding = new SchemaCorrigendumFileBindingV1
            {
                role = role,
                relativePath = relativePath,
                lengthBytes = info.Length,
                expectedSha256 = expectedSha256,
                actualSha256 = actual,
                matched = actual == expectedSha256
            };
            bindings.Add(binding);
            Require(binding.matched, "Hash mismatch: " + relativePath);
        }

        private static bool AllBindingsMatched(List<SchemaCorrigendumFileBindingV1> bindings)
        {
            if (bindings.Count == 0) return false;
            for (int index = 0; index < bindings.Count; index++)
            {
                if (!bindings[index].matched) return false;
            }
            return true;
        }

        private static string ReadText(string projectRoot, string relativePath)
        {
            string fullPath = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            Require(File.Exists(fullPath), "Missing file: " + relativePath);
            return File.ReadAllText(fullPath, new UTF8Encoding(false, true));
        }

        private static string ResolveExactNewOutputDirectory(string projectRoot, string requested)
        {
            string expected = Path.GetFullPath(Path.Combine(projectRoot,
                ExpectedOutputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            string actual = Path.GetFullPath(Path.IsPathRooted(requested) ? requested : Path.Combine(projectRoot, requested));
            Require(string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase),
                "Self-check output path is outside the exact authorized verification directory.");
            Require(!Directory.Exists(actual) && !File.Exists(actual),
                "Self-check output already exists; overwrite is prohibited.");
            Directory.CreateDirectory(actual);
            return actual;
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> parsed = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                if (!args[index].StartsWith("--g14me-", StringComparison.Ordinal)) continue;
                Require(index + 1 < args.Length, "Missing value for " + args[index]);
                parsed[args[index]] = args[++index];
            }
            return parsed;
        }

        private static string Required(Dictionary<string, string> arguments, string name)
        {
            string value;
            Require(arguments.TryGetValue(name, out value) && !string.IsNullOrWhiteSpace(value),
                "Missing required argument " + name);
            return value;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++)
                {
                    builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                }
                return builder.ToString();
            }
        }

        private static void WriteJsonAtomic(string path, object value)
        {
            string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + Environment.NewLine, new UTF8Encoding(false));
            if (File.Exists(path)) throw new IOException("Refusing to overwrite existing receipt: " + path);
            File.Move(temporary, path);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
#endif
