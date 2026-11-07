#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V3;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.D3V31IntegrationAttempt001
{
    [Serializable]
    internal sealed class AuthorizationHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    internal sealed class InstrumentContractHeaderV1
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public int version;
    }

    [Serializable]
    internal sealed class OutputSchemaD3BindingV1
    {
        public string endpointId;
        public string semanticVersion;
        public string counterId;
        public string contractRelativePath;
        public string contractSha256;
        public string primaryRawTable;
        public string primaryRawField;
        public string[] rateRawInputs;
        public string rateDerivedField;
        public string[] oldSnapshotDifferenceFieldsProhibited;
    }

    [Serializable]
    internal sealed class OutputSchemaRawTableV1
    {
        public string tableId;
        public string fileName;
        public string grain;
        public string[] requiredFields;
    }

    [Serializable]
    internal sealed class OutputSchemaHeaderV1
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public int version;
        public OutputSchemaD3BindingV1 d3Binding;
        public OutputSchemaRawTableV1[] rawTables;
    }

    [Serializable]
    internal sealed class FileBindingV1
    {
        public string role;
        public string relativePath;
        public long lengthBytes;
        public string expectedSha256;
        public string actualSha256;
        public bool matched;
    }

    [Serializable]
    internal sealed class IntegrationSelfCheckReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string createdAtUtc;
        public string completedAtUtc;
        public string unityVersion;
        public bool passed;
        public bool terminal;
        public bool parentAndProtectedHashesPassed;
        public bool outputSchemaHeaderPassed;
        public bool d3RawFieldSetPassed;
        public bool eventAndEmptyJoinFieldsPassed;
        public bool oldSnapshotFieldsExcludedFromV2Tables;
        public bool runnerSourceBindingPassed;
        public bool runnerTypeAndEntryPointPassed;
        public bool syntheticStrictJsonRoundTripPassed;
        public bool syntheticRateFormulaPassed;
        public bool priorV1ArtifactsUnchanged;
        public bool qualificationMeasuredRootAbsentBefore;
        public bool qualificationMeasuredRootAbsentAfter;
        public bool formalMeasuredRootAbsentBefore;
        public bool formalMeasuredRootAbsentAfter;
        public bool plannerConstructed;
        public bool algorithmLaneExecuted;
        public bool scheduleInputOrIdentityGenerated;
        public bool formalCollectionPerformed;
        public bool formalAnalysisRankingOrWinnerPerformed;
        public FileBindingV1[] bindings;
        public string syntheticSerializedD3Window;
        public string exceptionType;
        public string exactFailure;
        public string stackTrace;
    }

    public static class Gate14ReMED3V31RunnerSchemaIntegrationSelfCheckV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-d3-v3-1-runner-schema-integration-attempt-001";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/d3-v3-1-runner-schema-integration-attempt-001/unity-self-check-output";

        private static readonly string[] D3RequiredFields =
        {
            "recordId", "inputId", "superblockId", "anonymousLaneId", "identityBindingSha256",
            "measurementScope", "eventGroupIndex", "processOrdinal", "iterationIndex", "d3CounterId",
            "d3SemanticVersion", "managedAllocationBytes", "managedAllocationEventCount",
            "foreignThreadAllocationBytes", "foreignThreadAllocationEventCount", "invalidMetadataEventCount",
            "counterOverflowCount", "ownerNativeThreadId", "observerNativeThreadId",
            "windowStartStopwatchTicks", "windowEndStopwatchTicks", "windowElapsedStopwatchTicks",
            "stopwatchFrequency", "managedAllocationRateBytesPerSecond", "managedAllocationRateValid",
            "beginReturnCode", "endReturnCode", "pluginReady", "markerSeen", "metadataAbiValid",
            "ownerThreadMatched", "counterValid", "invalidReasonCode", "d3ContractRelativePath",
            "d3ContractSha256", "sourceRelativePath", "sourceSha256"
        };

        private static readonly string[] OldSnapshotFields =
        {
            "allocationCounterStart", "allocationCounterEnd", "eventGroupManagedAllocatedBytes", "allocatedBytes"
        };

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = string.Empty;
            IntegrationSelfCheckReceiptV1 receipt = CreateBaseReceipt();
            List<FileBindingV1> bindings = new List<FileBindingV1>();
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                outputDirectory = ResolveExactNewOutputDirectory(projectRoot, Required(arguments, "--g14me-integration-output"));

                string qualificationAttempt001 = Path.Combine(projectRoot, "Research", "PilotRuns", "Gate14Re-ME", "load-qualification", "attempt-001");
                string qualificationAttempt002 = Path.Combine(projectRoot, "Research", "PilotRuns", "Gate14Re-ME", "load-qualification", "attempt-002");
                string formalRoot = Path.Combine(projectRoot, "Research", "FormalRuns", "Gate14Re-ME");
                receipt.qualificationMeasuredRootAbsentBefore = !Directory.Exists(qualificationAttempt001) && !Directory.Exists(qualificationAttempt002);
                receipt.formalMeasuredRootAbsentBefore = !Directory.Exists(formalRoot);
                Require(receipt.qualificationMeasuredRootAbsentBefore, "A prohibited qualification measured root already exists.");
                Require(receipt.formalMeasuredRootAbsentBefore, "A prohibited Gate14Re-ME formal measured root already exists.");

                Bind(projectRoot, bindings, "authorization",
                    "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_1_Runner_Schema_Integration_Authorization.v1.json",
                    "f58a70591bf24d1c9e7800cfc27134a582cd9ab1c89197e2b2f44e950c36f2a2");
                Bind(projectRoot, bindings, "integration-plan",
                    "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_1_Runner_Schema_Integration_Plan.v1.md",
                    "e7dfb8ead352c132e152315c4abf7a1bd63688be59fb8c0907030232cdb52e0c");
                Bind(projectRoot, bindings, "parent-freeze-receipt",
                    "Research/Verification/Gate14Re-ME/d3-v3-cumulative-allocation-qualification-attempt-003/freeze-receipt.v1.json",
                    "23df3757a0cac246b5d120c9ef025a2861b2cc062e4b920c42fbb0b450147bc8");
                Bind(projectRoot, bindings, "qualified-d3-contract",
                    "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json",
                    "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce");
                Bind(projectRoot, bindings, "native-d3-binary",
                    "Assets/Plugins/x86_64/Gate14ReMED3AllocationCounterV31.dll",
                    "8973663f67d5becf6ea3693ae088dc1186f8b84d82c15026d45c51124f6a0e63");
                Bind(projectRoot, bindings, "managed-d3-wrapper",
                    "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMECumulativeAllocationCounterV2.cs",
                    "f9e2dd5bff847d7c0fe56795af6091342e542ea7bd5aa7ecbcf8ad0dd08c7007");
                Bind(projectRoot, bindings, "protected-runner-v1",
                    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs",
                    "7bb9237e529f511ad12fcfcb8374db02818977092c3680b287aacc817d182033");
                Bind(projectRoot, bindings, "protected-output-schema-v1",
                    "Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json",
                    "ed7d7bddf8e1da647a6085aa8e717d4ee0578ceff3fa7844dbd05c4e17aaea1c");
                Bind(projectRoot, bindings, "protected-six-algorithm-fairness-binding",
                    "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json",
                    "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71");
                Bind(projectRoot, bindings, "d3-v3-1-runner-contracts",
                    "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMELoadQualificationD3V31ContractsV1.cs",
                    "a30d8cb6a246de1e3ed1c8f2b3e8e0bd2ab1255f10781ee68a3027fa2ed5a902");
                Bind(projectRoot, bindings, "qualification-runner-v2",
                    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs",
                    "39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73");
                Bind(projectRoot, bindings, "output-schema-v2",
                    "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json",
                    "eebb880290615c28bfacddd94fcdbfa7ee53351582adac6adf21bf31ab9856cb");
                Bind(projectRoot, bindings, "integrated-instrument-contract-v3",
                    "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json",
                    "c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312");
                receipt.parentAndProtectedHashesPassed = AllBindingsMatched(bindings);
                receipt.priorV1ArtifactsUnchanged = true;
                Require(receipt.parentAndProtectedHashesPassed, "One or more frozen binding hashes drifted.");

                string authorizationJson = ReadText(projectRoot,
                    "Research/Gate14Re-ME/Gate14Re_ME_D3_V3_1_Runner_Schema_Integration_Authorization.v1.json");
                AuthorizationHeaderV1 authorization = JsonUtility.FromJson<AuthorizationHeaderV1>(authorizationJson);
                Require(authorization != null && authorization.schema == "gate14re-me-d3-v3-1-runner-schema-integration-authorization-v1" &&
                    authorization.studyId == StudyId && authorization.authorizationId == AuthorizationId &&
                    authorization.status == "AUTHORIZED_MINIMUM_RUNNER_SCHEMA_INTEGRATION_STAGE",
                    "Integration authorization header is invalid.");

                string instrumentJson = ReadText(projectRoot,
                    "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json");
                InstrumentContractHeaderV1 instrument = JsonUtility.FromJson<InstrumentContractHeaderV1>(instrumentJson);
                Require(instrument != null && instrument.schema == "gate14re-me-load-qualification-instrument-contract-v3" &&
                    instrument.studyId == StudyId && instrument.protocolId == "gate14re-me-load-qualification-v1" && instrument.version == 3 &&
                    instrument.status == "FROZEN_SOURCE_INTEGRATED_D3_V3_1_RUNTIME_QUALIFICATION_PENDING",
                    "Integrated instrument-contract header is invalid.");

                string schemaJson = ReadText(projectRoot,
                    "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v2.json");
                OutputSchemaHeaderV1 schema = JsonUtility.FromJson<OutputSchemaHeaderV1>(schemaJson);
                receipt.outputSchemaHeaderPassed = schema != null &&
                    schema.schema == "gate14re-me-load-qualification-output-schema-v2" &&
                    schema.studyId == StudyId && schema.protocolId == "gate14re-me-load-qualification-v1" && schema.version == 2 &&
                    schema.d3Binding != null && schema.d3Binding.endpointId == "D3" &&
                    schema.d3Binding.semanticVersion == Gate14ReMED3V31QualificationConstantsV1.SemanticVersion &&
                    schema.d3Binding.counterId == Gate14ReMED3V31QualificationConstantsV1.CounterId &&
                    schema.d3Binding.contractSha256 == Gate14ReMED3V31QualificationConstantsV1.ContractSha256 &&
                    schema.d3Binding.primaryRawTable == "d3-windows" && schema.d3Binding.primaryRawField == "managedAllocationBytes";
                Require(receipt.outputSchemaHeaderPassed, "Output schema v2 header or D3 binding is invalid.");

                OutputSchemaRawTableV1 d3Table = FindTable(schema, "d3-windows");
                OutputSchemaRawTableV1 eventTable = FindTable(schema, "event-groups");
                OutputSchemaRawTableV1 emptyTable = FindTable(schema, "empty-boundary");
                receipt.d3RawFieldSetPassed = d3Table != null && d3Table.fileName == Gate14ReMED3V31QualificationConstantsV1.D3WindowFileName &&
                    ExactFieldSet(d3Table.requiredFields, D3RequiredFields);
                receipt.eventAndEmptyJoinFieldsPassed = eventTable != null && emptyTable != null &&
                    eventTable.fileName == Gate14ReMED3V31QualificationConstantsV1.EventGroupFileName &&
                    emptyTable.fileName == Gate14ReMED3V31QualificationConstantsV1.EmptyBoundaryFileName &&
                    Contains(eventTable.requiredFields, "d3WindowRecordId") && Contains(eventTable.requiredFields, "d3CounterValid") &&
                    Contains(emptyTable.requiredFields, "d3WindowRecordId") && Contains(emptyTable.requiredFields, "d3CounterValid");
                receipt.oldSnapshotFieldsExcludedFromV2Tables = ExcludesAll(d3Table.requiredFields, OldSnapshotFields) &&
                    ExcludesAll(eventTable.requiredFields, OldSnapshotFields) && ExcludesAll(emptyTable.requiredFields, OldSnapshotFields);
                Require(receipt.d3RawFieldSetPassed && receipt.eventAndEmptyJoinFieldsPassed &&
                    receipt.oldSnapshotFieldsExcludedFromV2Tables,
                    "Output schema v2 raw field or D3 join requirements failed.");

                string runnerSource = ReadText(projectRoot, "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs");
                receipt.runnerSourceBindingPassed = runnerSource.Contains("Gate14ReMED3MeasurementWindowV1") &&
                    runnerSource.Contains("Gate14ReMED3WindowRawV1") && runnerSource.Contains("CreateRawRecord(") &&
                    runnerSource.Contains("Gate14ReMEEventGroupRawV2") && runnerSource.Contains("Gate14ReMEEmptyBoundaryRawV2") &&
                    !runnerSource.Contains("Gate14ReMEAllocationCounterV1") && !runnerSource.Contains("eventGroupManagedAllocatedBytes") &&
                    !runnerSource.Contains("allocationCounterStart") && !runnerSource.Contains("allocationCounterEnd");
                Require(receipt.runnerSourceBindingPassed, "Runner V2 does not exclusively bind the D3-v3.1 window implementation.");

                MethodInfo entryPoint = typeof(DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2).GetMethod(
                    "Run", BindingFlags.Public | BindingFlags.Static);
                receipt.runnerTypeAndEntryPointPassed = entryPoint != null && entryPoint.ReturnType == typeof(void) &&
                    typeof(Gate14ReMED3MeasurementWindowV1).GetMethod("CreateRawRecord", BindingFlags.Public | BindingFlags.Instance) != null;
                Require(receipt.runnerTypeAndEntryPointPassed, "Versioned runner or D3 window type did not compile to the expected API.");

                Gate14ReMED3WindowRawV1 synthetic = CreateSyntheticWindow();
                string syntheticJson = JsonUtility.ToJson(synthetic, false);
                receipt.syntheticSerializedD3Window = syntheticJson;
                Gate14ReMED3WindowRawV1 roundTrip = JsonUtility.FromJson<Gate14ReMED3WindowRawV1>(syntheticJson);
                receipt.syntheticStrictJsonRoundTripPassed = roundTrip != null &&
                    !syntheticJson.Contains("NaN") && !syntheticJson.Contains("Infinity") &&
                    roundTrip.recordId == synthetic.recordId && roundTrip.managedAllocationBytes == synthetic.managedAllocationBytes &&
                    roundTrip.managedAllocationEventCount == synthetic.managedAllocationEventCount &&
                    roundTrip.windowElapsedStopwatchTicks == synthetic.windowElapsedStopwatchTicks &&
                    roundTrip.d3ContractSha256 == Gate14ReMED3V31QualificationConstantsV1.ContractSha256;
                double recomputed = roundTrip.managedAllocationBytes * (double)roundTrip.stopwatchFrequency /
                    roundTrip.windowElapsedStopwatchTicks;
                receipt.syntheticRateFormulaPassed = roundTrip.managedAllocationRateValid &&
                    Math.Abs(recomputed - roundTrip.managedAllocationRateBytesPerSecond) <= 1e-9;
                Require(receipt.syntheticStrictJsonRoundTripPassed && receipt.syntheticRateFormulaPassed,
                    "Synthetic D3 raw-row strict JSON or rate formula self-check failed.");

                receipt.qualificationMeasuredRootAbsentAfter = !Directory.Exists(qualificationAttempt001) && !Directory.Exists(qualificationAttempt002);
                receipt.formalMeasuredRootAbsentAfter = !Directory.Exists(formalRoot);
                Require(receipt.qualificationMeasuredRootAbsentAfter && receipt.formalMeasuredRootAbsentAfter,
                    "A prohibited measured root appeared during the self-check.");

                receipt.passed = true;
                receipt.status = "PASS_D3_V3_1_RUNNER_SCHEMA_INTEGRATION_SELF_CHECK";
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.passed = false;
                receipt.status = "FAILED_CLOSED_D3_V3_1_RUNNER_SCHEMA_INTEGRATION_SELF_CHECK";
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
                receipt.plannerConstructed = false;
                receipt.algorithmLaneExecuted = false;
                receipt.scheduleInputOrIdentityGenerated = false;
                receipt.formalCollectionPerformed = false;
                receipt.formalAnalysisRankingOrWinnerPerformed = false;
                try
                {
                    if (!string.IsNullOrEmpty(outputDirectory) && Directory.Exists(outputDirectory))
                    {
                        WriteJsonAtomic(Path.Combine(outputDirectory, "integration-self-check-receipt.v1.json"), receipt);
                    }
                }
                catch (Exception writeFailure)
                {
                    exitCode = 4;
                    UnityEngine.Debug.LogError("Unable to preserve integration self-check receipt: " + writeFailure);
                }
                EditorApplication.Exit(exitCode);
            }
        }

        private static IntegrationSelfCheckReceiptV1 CreateBaseReceipt()
        {
            return new IntegrationSelfCheckReceiptV1
            {
                schema = "gate14re-me-d3-v3-1-runner-schema-integration-self-check-receipt-v1",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                status = "IN_PROGRESS",
                createdAtUtc = DateTime.UtcNow.ToString("o"),
                passed = false,
                terminal = false,
                unityVersion = Application.unityVersion
            };
        }

        private static Gate14ReMED3WindowRawV1 CreateSyntheticWindow()
        {
            return new Gate14ReMED3WindowRawV1
            {
                recordId = "synthetic:d3-window:1",
                inputId = "synthetic-input",
                superblockId = "synthetic-superblock",
                anonymousLaneId = "ALG-A",
                identityBindingSha256 = new string('a', 64),
                measurementScope = "event-group",
                eventGroupIndex = 0,
                processOrdinal = -1,
                iterationIndex = -1,
                d3CounterId = Gate14ReMED3V31QualificationConstantsV1.CounterId,
                d3SemanticVersion = Gate14ReMED3V31QualificationConstantsV1.SemanticVersion,
                managedAllocationBytes = 4096L,
                managedAllocationEventCount = 1L,
                foreignThreadAllocationBytes = 0L,
                foreignThreadAllocationEventCount = 0L,
                invalidMetadataEventCount = 0L,
                counterOverflowCount = 0L,
                ownerNativeThreadId = 42L,
                observerNativeThreadId = 42L,
                windowStartStopwatchTicks = 100L,
                windowEndStopwatchTicks = 200L,
                windowElapsedStopwatchTicks = 100L,
                stopwatchFrequency = 1000L,
                managedAllocationRateBytesPerSecond = 40960d,
                managedAllocationRateValid = true,
                beginReturnCode = 0,
                endReturnCode = 0,
                pluginReady = true,
                markerSeen = true,
                metadataAbiValid = true,
                ownerThreadMatched = true,
                counterValid = true,
                invalidReasonCode = string.Empty,
                d3ContractRelativePath = Gate14ReMED3V31QualificationConstantsV1.ContractRelativePath,
                d3ContractSha256 = Gate14ReMED3V31QualificationConstantsV1.ContractSha256,
                sourceRelativePath = "synthetic",
                sourceSha256 = new string('b', 64)
            };
        }

        private static OutputSchemaRawTableV1 FindTable(OutputSchemaHeaderV1 schema, string tableId)
        {
            if (schema == null || schema.rawTables == null) return null;
            for (int index = 0; index < schema.rawTables.Length; index++)
            {
                if (schema.rawTables[index] != null && schema.rawTables[index].tableId == tableId) return schema.rawTables[index];
            }
            return null;
        }

        private static bool ExactFieldSet(string[] actual, string[] expected)
        {
            if (actual == null || expected == null || actual.Length != expected.Length) return false;
            HashSet<string> set = new HashSet<string>(actual, StringComparer.Ordinal);
            if (set.Count != actual.Length) return false;
            for (int index = 0; index < expected.Length; index++) if (!set.Contains(expected[index])) return false;
            return true;
        }

        private static bool Contains(string[] values, string value)
        {
            if (values == null) return false;
            for (int index = 0; index < values.Length; index++) if (values[index] == value) return true;
            return false;
        }

        private static bool ExcludesAll(string[] values, string[] excluded)
        {
            if (values == null || excluded == null) return false;
            for (int index = 0; index < excluded.Length; index++) if (Contains(values, excluded[index])) return false;
            return true;
        }

        private static void Bind(string projectRoot, List<FileBindingV1> bindings, string role, string relativePath, string expectedSha256)
        {
            string fullPath = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            Require(File.Exists(fullPath), "Missing bound file: " + relativePath);
            string actual = Sha256File(fullPath);
            FileInfo info = new FileInfo(fullPath);
            FileBindingV1 binding = new FileBindingV1
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

        private static bool AllBindingsMatched(List<FileBindingV1> bindings)
        {
            if (bindings.Count == 0) return false;
            for (int index = 0; index < bindings.Count; index++) if (!bindings[index].matched) return false;
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
            string expected = Path.GetFullPath(Path.Combine(projectRoot, ExpectedOutputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            string actual = Path.GetFullPath(Path.IsPathRooted(requested) ? requested : Path.Combine(projectRoot, requested));
            Require(string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase), "Self-check output path is outside the exact authorized verification directory.");
            Require(!Directory.Exists(actual) && !File.Exists(actual), "Self-check output already exists; overwrite is prohibited.");
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
            Require(arguments.TryGetValue(name, out value) && !string.IsNullOrWhiteSpace(value), "Missing required argument " + name);
            return value;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
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
