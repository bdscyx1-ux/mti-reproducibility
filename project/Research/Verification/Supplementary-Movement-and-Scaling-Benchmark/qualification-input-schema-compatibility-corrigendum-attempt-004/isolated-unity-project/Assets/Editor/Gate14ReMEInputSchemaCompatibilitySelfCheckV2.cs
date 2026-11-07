#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.InputSchemaCorrigendumAttempt004
{
    [Serializable]
    internal sealed class Attempt004AuthorizationHeaderV1
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
    internal sealed class TrustedRuleHeaderV1
    {
        public string schema;
        public string studyId;
        public string ruleId;
        public string status;
        public TrustedRuleApplicabilityV1 applicability;
        public TrustedRuleRequirementsV1 requirements;
    }

    [Serializable]
    internal sealed class TrustedRuleApplicabilityV1
    {
        public string unityVersion;
        public string unityExecutablePath;
        public string unityExecutableExpectedSha256;
        public string ntfsFileIndexLow64Hex;
        public long fileLengthBytes;
        public string creationTimeUtc;
        public string lastWriteTimeUtc;
        public string signerThumbprint;
    }

    [Serializable]
    internal sealed class TrustedRuleRequirementsV1
    {
        public bool externalThreePhaseExpectedSha256AndIndependentMethodAgreement;
        public bool external64KiBChunksPathFileIdPeSignerAndMetadataStable;
        public bool pidCreationTimePathCommandLineAndExecuteMethodBound;
        public bool inProcessPathSourcesAndStructuralIdentityStable;
        public bool knownAnswersPassed;
        public bool normalExitAndPostExitReconfirmationRequired;
        public bool inProcessSelfHashesRequiredForAuthorization;
        public string fileReadAllBytesRole;
        public string anyAuthoritativeMismatchDisposition;
    }

    [Serializable]
    internal sealed class Attempt004FileBindingV1
    {
        public string role;
        public string relativePath;
        public long lengthBytes;
        public string expectedSha256;
        public string actualSha256;
        public bool matched;
    }

    [Serializable]
    internal sealed class InProcessFileIdentityV1
    {
        public bool succeeded;
        public string normalizedPath;
        public string finalPath;
        public string volumeSerialHex;
        public string fileIndexLow64Hex;
        public string exactFailure;
    }

    [Serializable]
    internal sealed class InProcessPeIdentityV1
    {
        public bool succeeded;
        public long peHeaderOffset;
        public string optionalHeaderMagicHex;
        public long checksumFieldOffset;
        public string checksumHex;
        public long securityDirectoryFieldOffset;
        public long certificateTableFileOffset;
        public long certificateTableSizeBytes;
        public string exactFailure;
    }

    [Serializable]
    internal sealed class InProcessIdentitySnapshotV1
    {
        public string capturedAtUtc;
        public int processId;
        public string processStartTimeUtc;
        public string editorApplicationPath;
        public string processMainModulePath;
        public string queryFullProcessImageNamePath;
        public bool allExecutablePathsEqual;
        public long fileLengthBytes;
        public string creationTimeUtc;
        public string lastWriteTimeUtc;
        public InProcessFileIdentityV1 fileIdentity;
        public InProcessPeIdentityV1 peIdentity;
    }

    [Serializable]
    internal sealed class InProcessReadySnapshotV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public bool schemaCompatibilitySelfCheckInvoked;
        public bool plannerInvoked;
        public bool algorithmLaneExecuted;
        public bool measuredRootCreated;
        public InProcessIdentitySnapshotV1 process;
    }

    [Serializable]
    internal sealed class InputSchemaCompatibilitySelfCheckReceiptV2
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
        public bool authorizationHeaderPassed;
        public bool trustedIdentityRuleHeaderPassed;
        public bool planningBindingHeaderPassed;
        public bool retainedSchemaKnownAnswerPassed;
        public bool sourceAndEvidenceBindingsPassed;
        public bool prohibitedRootsAbsentBefore;
        public bool prohibitedRootsAbsentAfter;
        public InProcessIdentitySnapshotV1 initialProcessIdentity;
        public InProcessIdentitySnapshotV1 afterHoldProcessIdentity;
        public bool inProcessStructuralIdentityStableAcrossHold;
        public bool inProcessFileReadHashesAuthoritative;
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
        public Attempt004FileBindingV1[] bindings;
        public string exceptionType;
        public string exactFailure;
        public string stackTrace;
        public int schemaCompatibilitySelfCheckInvocations;
        public int scheduleRowsGenerated;
        public int qualificationInputsGenerated;
        public int anonymousIdentityMappingsGenerated;
        public bool qualificationMeasuredRootCreated;
        public int plannerInvocations;
        public int algorithmLaneExecutions;
        public bool formalCollectionPerformed;
        public bool formalAnalysisPerformed;
        public bool algorithmRankingPerformed;
        public bool winnerAdjudicationPerformed;
    }

    public static class Gate14ReMEInputSchemaCompatibilitySelfCheckV2
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-004";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-004/unity-output";
        private const string ExpectedOracleFailure = "Event-group topology must match the input context.";
        private const uint GenericReadAttributes = 0x80u;
        private const uint ShareRead = 0x1u;
        private const uint ShareWrite = 0x2u;
        private const uint ShareDelete = 0x4u;
        private const uint OpenExisting = 3u;

        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime
        {
            public uint Low;
            public uint High;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public FileTime CreationTime;
            public FileTime LastAccessTime;
            public FileTime LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(IntPtr handle, out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(IntPtr handle, StringBuilder path, uint pathLength, uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageNameW(IntPtr processHandle, uint flags, StringBuilder executablePath, ref uint size);

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = string.Empty;
            InputSchemaCompatibilitySelfCheckReceiptV2 receipt = CreateBaseReceipt();
            List<Attempt004FileBindingV1> bindings = new List<Attempt004FileBindingV1>();
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string sourceProjectRoot = Path.GetFullPath(Required(arguments, "--g14me-source-project-root"));
                outputDirectory = ResolveExactOutputDirectory(sourceProjectRoot, Required(arguments, "--g14me-schema-output-dir"));
                int holdSeconds;
                Require(int.TryParse(Required(arguments, "--g14me-live-hold-seconds"), NumberStyles.None, CultureInfo.InvariantCulture, out holdSeconds) && holdSeconds >= 5 && holdSeconds <= 120,
                    "Live identity hold seconds are outside the authorized range.");

                BindAbsolute(bindings, "source-freeze-manifest", Required(arguments, "--g14me-source-freeze-manifest"),
                    Required(arguments, "--g14me-source-freeze-manifest-sha256"), sourceProjectRoot);
                Bind(sourceProjectRoot, bindings, "parent-status-v23", "Research/Gate14Re-ME/Gate14Re_ME_Status.v23.json", "d3702df64532afbc14d1e494591dd63cc8d26d68662c8b57250c48420f229537");
                Bind(sourceProjectRoot, bindings, "trusted-launch-identity-rule-v1", "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json", "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06");
                Bind(sourceProjectRoot, bindings, "qualified-timestamp-comparator-attempt007", "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1", "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27");
                Bind(sourceProjectRoot, bindings, "timestamp-comparator-attempt007-known-answer", "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/known-answer-receipt.v1.json", "ad64fb2bce32f2e6206f6f1f80baa30f273be212075603ee631f61b560cc1b63");
                Bind(sourceProjectRoot, bindings, "timestamp-comparator-attempt007-freeze-manifest", "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/source-and-evidence-freeze-manifest.v1.json", "302f8d14c725f43e063d95ecb8b23297ee3f5701c47ed55abc64fdb62ad4aeb2");
                Bind(sourceProjectRoot, bindings, "schema-compatibility-attempt003-failure-receipt", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003/failure-receipt.v1.json", "aea859d3b2935ff71d66a4cd9bcdd005c3acddf093e409b712e129374a9b5a97");
                Bind(sourceProjectRoot, bindings, "schema-compatibility-attempt003-freeze-manifest", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003/source-and-evidence-freeze-manifest.v1.json", "0d87c68508c5505a1b886d3206af56d92f4c0c792daabba0ffac7591b6ae2277");
                Bind(sourceProjectRoot, bindings, "corrected-input-schema-v2", "Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json", "1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117");
                Bind(sourceProjectRoot, bindings, "planning-schema-binding-v2", "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json", "abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7");
                Bind(sourceProjectRoot, bindings, "qualification-contracts-source", "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs", "0e6a516c24eff27195b634227a96fde742eea6ef5899eaa7aeda7c514c2b7ee4");
                Bind(sourceProjectRoot, bindings, "reference-oracle-and-geometry-validator-source", "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs", "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25");
                Bind(sourceProjectRoot, bindings, "research-grid-source", "Assets/_Scripts/Research/Grid/ResearchNavigationGrid.cs", "4d147321f9ccc4fb6da64265ceeec28f372542531fa72482b2eced8cdee2f582");
                Bind(sourceProjectRoot, bindings, "navigation-contracts-source", "Assets/_Scripts/Research/Navigation/NavigationContracts.cs", "7e074ec1fa13d9de2addeca4defa702fb773974d17615de3fffce93b5c4f5efa");
                Bind(sourceProjectRoot, bindings, "attempt001-failure-receipt", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/failure-receipt.v1.json", "a92d258027ea0add02e874d3b73b20c7790f18b904af7d051a3ccc09e5eb69f1");
                Bind(sourceProjectRoot, bindings, "attempt001-freeze-manifest", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/source-and-evidence-freeze-manifest.v1.json", "9ad8a0ce59a286f5c32704f612154d6f751bb38d8bcd3003a8902da5bc1dc2b9");
                Bind(sourceProjectRoot, bindings, "attempt001-schema-known-answer", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/schema-known-answer-receipt.v1.json", "76977549e66d3e98af3e4f214b507bda1bba9d5d13006762d0f004bd62f40358");
                Bind(sourceProjectRoot, bindings, "attempt001-post-exit-identity-audit", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/post-exit-unity-identity-audit.v1.json", "9585fdc3b2b250dc1801d9a81d41d045cee1028a0d1d9707f982664133fcee41");
                Bind(sourceProjectRoot, bindings, "attempt001-unity-failure-receipt", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/unity-self-check-output/input-schema-compatibility-self-check-receipt.v1.json", "f9a3ee42729fc055836e8448043278732cd43decf2ca2a06c58e135fb979944b");
                Bind(sourceProjectRoot, bindings, "attempt002-source-freeze-manifest", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-002/source-freeze-manifest.v1.json", "8c679db079a38c35fc892c08cefb1fb035d9335066020ee6b1ccc638d30e076f");
                Bind(sourceProjectRoot, bindings, "attempt002-failure-receipt", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-002/failure-receipt.v1.json", "ddba11bfc889e1e34b08b036926af7e92dd3030390672bc28bbbbf34ddcf6b1f");
                Bind(sourceProjectRoot, bindings, "attempt002-evidence-freeze-manifest", "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-002/source-and-evidence-freeze-manifest.v1.json", "63160466da1b5e52106fae7a4681372a8b0af6913678513c89b51f4f9fada14c");
                receipt.sourceAndEvidenceBindingsPassed = AllBindingsMatched(bindings);
                Require(receipt.sourceAndEvidenceBindingsPassed, "One or more frozen source or evidence bindings drifted.");

                string attempt004Root = Path.GetFullPath(Path.Combine(sourceProjectRoot,
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-004".Replace('/', Path.DirectorySeparatorChar)));
                Attempt004AuthorizationHeaderV1 authorization = JsonUtility.FromJson<Attempt004AuthorizationHeaderV1>(
                    File.ReadAllText(Path.Combine(attempt004Root, "authorization-receipt.v1.json"), new UTF8Encoding(false, true)));
                receipt.authorizationHeaderPassed = authorization != null &&
                    authorization.schema == "gate14re-me-qualification-input-schema-compatibility-corrigendum-authorization-v4" &&
                    authorization.studyId == StudyId && authorization.authorizationId == AuthorizationId &&
                    authorization.status == "AUTHORIZED_ONE_ISOLATED_ALGORITHM_FREE_UNITY_SCHEMA_COMPATIBILITY_SELF_CHECK";
                Require(receipt.authorizationHeaderPassed, "Attempt-004 authorization header is invalid.");

                TrustedRuleHeaderV1 trustedRule = JsonUtility.FromJson<TrustedRuleHeaderV1>(ReadText(sourceProjectRoot,
                    "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json"));
                receipt.trustedIdentityRuleHeaderPassed = trustedRule != null && trustedRule.applicability != null && trustedRule.requirements != null &&
                    trustedRule.schema == "gate14re-me-unity-executable-identity-verification-rule-v1" && trustedRule.studyId == StudyId &&
                    trustedRule.status == "FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION" &&
                    trustedRule.applicability.unityVersion == "2022.3.30f1c1" &&
                    trustedRule.applicability.unityExecutableExpectedSha256 == "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf" &&
                    trustedRule.requirements.externalThreePhaseExpectedSha256AndIndependentMethodAgreement &&
                    trustedRule.requirements.external64KiBChunksPathFileIdPeSignerAndMetadataStable &&
                    trustedRule.requirements.pidCreationTimePathCommandLineAndExecuteMethodBound &&
                    trustedRule.requirements.inProcessPathSourcesAndStructuralIdentityStable && trustedRule.requirements.knownAnswersPassed &&
                    trustedRule.requirements.normalExitAndPostExitReconfirmationRequired &&
                    !trustedRule.requirements.inProcessSelfHashesRequiredForAuthorization &&
                    trustedRule.requirements.fileReadAllBytesRole == "DIAGNOSTIC_ONLY" &&
                    trustedRule.requirements.anyAuthoritativeMismatchDisposition == "FAIL_CLOSED_NO_ADOPTION";
                Require(receipt.trustedIdentityRuleHeaderPassed, "Trusted launch identity rule header or requirements are invalid.");

                PlanningSchemaBindingHeaderV2 planningBinding = JsonUtility.FromJson<PlanningSchemaBindingHeaderV2>(ReadText(sourceProjectRoot,
                    "Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json"));
                receipt.planningBindingHeaderPassed = planningBinding != null &&
                    planningBinding.schema == "gate14re-me-load-qualification-planning-schema-binding-v2" &&
                    planningBinding.studyId == StudyId && planningBinding.protocolId == "gate14re-me-load-qualification-v1" &&
                    planningBinding.status == "FROZEN_INPUT_VALIDATION_SCHEMA_CORRIGENDUM_PLANNING_PENDING" && planningBinding.version == 2;
                Require(receipt.planningBindingHeaderPassed, "Planning schema binding v2 header is invalid.");

                SchemaKnownAnswerHeaderV1 knownAnswer = JsonUtility.FromJson<SchemaKnownAnswerHeaderV1>(ReadText(sourceProjectRoot,
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/schema-known-answer-receipt.v1.json"));
                receipt.retainedSchemaKnownAnswerPassed = knownAnswer != null &&
                    knownAnswer.schema == "gate14re-me-input-schema-compatibility-known-answer-receipt-v1" &&
                    knownAnswer.studyId == StudyId &&
                    knownAnswer.authorizationId == "gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-001" &&
                    knownAnswer.status == "PASS_INPUT_SCHEMA_COMPATIBILITY_KNOWN_ANSWER" && knownAnswer.passed && knownAnswer.terminal;
                Require(receipt.retainedSchemaKnownAnswerPassed, "Retained schema known-answer receipt is not a terminal pass.");

                receipt.prohibitedRootsAbsentBefore = ProhibitedRootsAbsent(sourceProjectRoot);
                Require(receipt.prohibitedRootsAbsentBefore, "A prohibited Gate14Re-ME measured root already exists.");

                receipt.initialProcessIdentity = CaptureIdentity();
                Require(receipt.initialProcessIdentity.allExecutablePathsEqual, "In-process executable paths disagree.");
                Require(PathsEqual(receipt.initialProcessIdentity.editorApplicationPath, trustedRule.applicability.unityExecutablePath),
                    "In-process executable path does not equal the trusted rule path.");
                Require(receipt.initialProcessIdentity.fileLengthBytes == trustedRule.applicability.fileLengthBytes,
                    "In-process executable length does not equal the trusted rule.");
                Require(receipt.initialProcessIdentity.fileIdentity != null && receipt.initialProcessIdentity.fileIdentity.succeeded &&
                    receipt.initialProcessIdentity.fileIdentity.fileIndexLow64Hex == trustedRule.applicability.ntfsFileIndexLow64Hex,
                    "In-process executable file identity does not equal the trusted rule.");

                InProcessReadySnapshotV1 ready = new InProcessReadySnapshotV1
                {
                    schema = "gate14re-me-input-schema-compatibility-in-process-ready-snapshot-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = "IN_PROCESS_SCHEMA_SELF_CHECK_IDENTITY_READY",
                    schemaCompatibilitySelfCheckInvoked = false,
                    plannerInvoked = false,
                    algorithmLaneExecuted = false,
                    measuredRootCreated = false,
                    process = receipt.initialProcessIdentity
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "in-process-ready-snapshot.v1.json"), ready);
                Thread.Sleep(checked(holdSeconds * 1000));

                receipt.afterHoldProcessIdentity = CaptureIdentity();
                receipt.inProcessStructuralIdentityStableAcrossHold = StructuralIdentityEqual(receipt.initialProcessIdentity, receipt.afterHoldProcessIdentity);
                Require(receipt.inProcessStructuralIdentityStableAcrossHold, "In-process structural executable identity changed during the live hold.");

                MethodInfo validateHeader = typeof(Gate14ReMEInputGeometryValidatorV1).GetMethod(
                    "ValidateGroupHeader", BindingFlags.NonPublic | BindingFlags.Static, null,
                    new Type[] { typeof(Gate14ReMEQualificationInputBundleV1), typeof(Gate14ReMEEventGroupV1), typeof(int) }, null);
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

                string missingJson = positiveJson.Replace(",\"topology\":\"compact\"", string.Empty);
                receipt.missingTopologyJsonControlConstructed = missingJson != positiveJson && !missingJson.Contains("\"topology\"");
                Require(receipt.missingTopologyJsonControlConstructed, "Unable to construct the missing-topology JSON control.");
                Gate14ReMEQualificationInputBundleV1 missingRoundTrip = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(missingJson);
                receipt.missingTopologyOracleHeaderFailedAsExpected = InvokeExpectingFailure(validateHeader, missingRoundTrip,
                    out receipt.missingTopologyObservedFailure);
                Require(receipt.missingTopologyOracleHeaderFailedAsExpected,
                    "Missing topology did not fail through the actual oracle-header validator for the expected reason.");

                string mismatchedJson = positiveJson.Replace("\"topology\":\"compact\"", "\"topology\":\"bottleneck\"");
                receipt.mismatchedTopologyJsonControlConstructed = mismatchedJson != positiveJson &&
                    mismatchedJson.Contains("\"topology\":\"bottleneck\"");
                Require(receipt.mismatchedTopologyJsonControlConstructed, "Unable to construct the mismatched-topology JSON control.");
                Gate14ReMEQualificationInputBundleV1 mismatchedRoundTrip = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(mismatchedJson);
                receipt.mismatchedTopologyOracleHeaderFailedAsExpected = InvokeExpectingFailure(validateHeader, mismatchedRoundTrip,
                    out receipt.mismatchedTopologyObservedFailure);
                Require(receipt.mismatchedTopologyOracleHeaderFailedAsExpected,
                    "Mismatched topology did not fail through the actual oracle-header validator for the expected reason.");

                receipt.prohibitedRootsAbsentAfter = ProhibitedRootsAbsent(sourceProjectRoot);
                Require(receipt.prohibitedRootsAbsentAfter, "A prohibited Gate14Re-ME measured root appeared during the self-check.");
                receipt.passed = true;
                receipt.status = "PASS_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK_ATTEMPT_004";
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.passed = false;
                receipt.status = "FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK_ATTEMPT_004";
                receipt.exceptionType = exception.GetType().FullName;
                receipt.exactFailure = exception.Message;
                receipt.stackTrace = exception.ToString();
                UnityEngine.Debug.LogException(exception);
            }
            finally
            {
                receipt.terminal = true;
                receipt.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                receipt.bindings = bindings.ToArray();
                receipt.expectedOracleFailureMessage = ExpectedOracleFailure;
                receipt.inProcessFileReadHashesAuthoritative = false;
                receipt.schemaCompatibilitySelfCheckInvocations = 1;
                receipt.scheduleRowsGenerated = 0;
                receipt.qualificationInputsGenerated = 0;
                receipt.anonymousIdentityMappingsGenerated = 0;
                receipt.qualificationMeasuredRootCreated = false;
                receipt.plannerInvocations = 0;
                receipt.algorithmLaneExecutions = 0;
                receipt.formalCollectionPerformed = false;
                receipt.formalAnalysisPerformed = false;
                receipt.algorithmRankingPerformed = false;
                receipt.winnerAdjudicationPerformed = false;
                try
                {
                    if (!string.IsNullOrEmpty(outputDirectory) && Directory.Exists(outputDirectory))
                    {
                        WriteJsonAtomic(Path.Combine(outputDirectory, "input-schema-compatibility-self-check-receipt.v2.json"), receipt);
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

        private static InputSchemaCompatibilitySelfCheckReceiptV2 CreateBaseReceipt()
        {
            return new InputSchemaCompatibilitySelfCheckReceiptV2
            {
                schema = "gate14re-me-input-schema-compatibility-unity-self-check-receipt-v2",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                status = "IN_PROGRESS",
                createdAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                unityVersion = Application.unityVersion,
                passed = false,
                terminal = false,
                expectedOracleFailureMessage = ExpectedOracleFailure,
                inProcessFileReadHashesAuthoritative = false
            };
        }

        private static Gate14ReMEQualificationInputBundleV1 CreateSyntheticInput(string topology)
        {
            return new Gate14ReMEQualificationInputBundleV1
            {
                schema = "gate14re-me-qualification-input-bundle-v1",
                studyId = StudyId,
                protocolId = "gate14re-me-load-qualification-v1",
                inputId = "unity-kat-input-attempt-004",
                superblockId = "unity-kat-superblock-attempt-004",
                designRegion = "core",
                seed = 1L,
                gridEdge = 64,
                agentCount = 8,
                changedCellCount = 1,
                changeTopology = "compact",
                graphProfile = "four_way_weighted_dense",
                sameTickAtomicPartitions = 1,
                contextStratumId = "unity-kat-context-attempt-004",
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                defaultTraversalCost = 1f,
                initialCellOverrides = new Gate14ReMECellStateV1[0],
                goal = new GridCoordinate(63, 63),
                starts = new[]
                {
                    new GridCoordinate(0, 0), new GridCoordinate(1, 0), new GridCoordinate(2, 0), new GridCoordinate(3, 0),
                    new GridCoordinate(4, 0), new GridCoordinate(5, 0), new GridCoordinate(6, 0), new GridCoordinate(7, 0)
                },
                eventGroups = new[]
                {
                    new Gate14ReMEEventGroupV1
                    {
                        eventGroupId = "unity-kat-event-00-attempt-004",
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
                                    new Gate14ReMECellStateV1 { x = 20, y = 20, isWalkable = false, traversalCost = 1f }
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

        private static bool InvokeExpectingFailure(MethodInfo validateHeader, Gate14ReMEQualificationInputBundleV1 input, out string observedFailure)
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

        private static InProcessIdentitySnapshotV1 CaptureIdentity()
        {
            Process process = Process.GetCurrentProcess();
            string editorPath = NormalizePath(EditorApplication.applicationPath);
            string mainModulePath = NormalizePath(process.MainModule.FileName);
            StringBuilder queried = new StringBuilder(32768);
            uint size = (uint)queried.Capacity;
            Require(QueryFullProcessImageNameW(process.Handle, 0, queried, ref size),
                "QueryFullProcessImageNameW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
            string queryPath = NormalizePath(queried.ToString());
            FileInfo info = new FileInfo(editorPath);
            return new InProcessIdentitySnapshotV1
            {
                capturedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                processId = process.Id,
                processStartTimeUtc = process.StartTime.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture),
                editorApplicationPath = editorPath,
                processMainModulePath = mainModulePath,
                queryFullProcessImageNamePath = queryPath,
                allExecutablePathsEqual = PathsEqual(editorPath, mainModulePath) && PathsEqual(editorPath, queryPath),
                fileLengthBytes = info.Length,
                creationTimeUtc = info.CreationTimeUtc.ToString("o", CultureInfo.InvariantCulture),
                lastWriteTimeUtc = info.LastWriteTimeUtc.ToString("o", CultureInfo.InvariantCulture),
                fileIdentity = CaptureFileIdentity(editorPath),
                peIdentity = CapturePeIdentity(editorPath)
            };
        }

        private static InProcessFileIdentityV1 CaptureFileIdentity(string path)
        {
            InProcessFileIdentityV1 result = new InProcessFileIdentityV1 { normalizedPath = NormalizePath(path) };
            IntPtr handle = new IntPtr(-1);
            try
            {
                handle = CreateFileW(path, GenericReadAttributes, ShareRead | ShareWrite | ShareDelete, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
                Require(handle != new IntPtr(-1), "CreateFileW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                ByHandleFileInformation information;
                Require(GetFileInformationByHandle(handle, out information),
                    "GetFileInformationByHandle failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                StringBuilder finalPath = new StringBuilder(32768);
                uint finalLength = GetFinalPathNameByHandleW(handle, finalPath, (uint)finalPath.Capacity, 0);
                Require(finalLength > 0 && finalLength < finalPath.Capacity,
                    "GetFinalPathNameByHandleW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                ulong fileIndex = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                result.finalPath = NormalizePath(RemoveExtendedPathPrefix(finalPath.ToString()));
                result.volumeSerialHex = information.VolumeSerialNumber.ToString("x8", CultureInfo.InvariantCulture);
                result.fileIndexLow64Hex = fileIndex.ToString("x16", CultureInfo.InvariantCulture);
                result.succeeded = true;
            }
            catch (Exception exception)
            {
                result.succeeded = false;
                result.exactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            finally
            {
                if (handle != new IntPtr(-1)) CloseHandle(handle);
            }
            return result;
        }

        private static InProcessPeIdentityV1 CapturePeIdentity(string path)
        {
            InProcessPeIdentityV1 result = new InProcessPeIdentityV1();
            try
            {
                using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (BinaryReader reader = new BinaryReader(stream, Encoding.UTF8, false))
                {
                    Require(stream.Length >= 256, "PE file is too short.");
                    stream.Position = 0x3c;
                    int peOffset = reader.ReadInt32();
                    Require(peOffset > 0 && peOffset + 256 < stream.Length, "PE header offset is invalid.");
                    stream.Position = peOffset;
                    Require(reader.ReadUInt32() == 0x00004550, "PE signature is invalid.");
                    long optionalHeaderOffset = peOffset + 24L;
                    stream.Position = optionalHeaderOffset;
                    ushort magic = reader.ReadUInt16();
                    Require(magic == 0x10b || magic == 0x20b, "PE optional-header magic is unsupported.");
                    long checksumOffset = optionalHeaderOffset + 64L;
                    stream.Position = checksumOffset;
                    uint checksum = reader.ReadUInt32();
                    long dataDirectoryOffset = optionalHeaderOffset + (magic == 0x20b ? 112L : 96L);
                    long securityDirectoryOffset = dataDirectoryOffset + 32L;
                    stream.Position = securityDirectoryOffset;
                    uint certificateOffset = reader.ReadUInt32();
                    uint certificateSize = reader.ReadUInt32();
                    result.peHeaderOffset = peOffset;
                    result.optionalHeaderMagicHex = magic.ToString("x4", CultureInfo.InvariantCulture);
                    result.checksumFieldOffset = checksumOffset;
                    result.checksumHex = checksum.ToString("x8", CultureInfo.InvariantCulture);
                    result.securityDirectoryFieldOffset = securityDirectoryOffset;
                    result.certificateTableFileOffset = certificateOffset;
                    result.certificateTableSizeBytes = certificateSize;
                    result.succeeded = true;
                }
            }
            catch (Exception exception)
            {
                result.succeeded = false;
                result.exactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            return result;
        }

        private static bool StructuralIdentityEqual(InProcessIdentitySnapshotV1 left, InProcessIdentitySnapshotV1 right)
        {
            return left != null && right != null && left.processId == right.processId &&
                left.processStartTimeUtc == right.processStartTimeUtc && left.allExecutablePathsEqual && right.allExecutablePathsEqual &&
                PathsEqual(left.editorApplicationPath, right.editorApplicationPath) &&
                PathsEqual(left.processMainModulePath, right.processMainModulePath) &&
                PathsEqual(left.queryFullProcessImageNamePath, right.queryFullProcessImageNamePath) &&
                left.fileLengthBytes == right.fileLengthBytes && left.creationTimeUtc == right.creationTimeUtc &&
                left.lastWriteTimeUtc == right.lastWriteTimeUtc && FileIdentityEqual(left.fileIdentity, right.fileIdentity) &&
                PeIdentityEqual(left.peIdentity, right.peIdentity);
        }

        private static bool FileIdentityEqual(InProcessFileIdentityV1 left, InProcessFileIdentityV1 right)
        {
            return left != null && right != null && left.succeeded && right.succeeded &&
                PathsEqual(left.normalizedPath, right.normalizedPath) && PathsEqual(left.finalPath, right.finalPath) &&
                left.volumeSerialHex == right.volumeSerialHex && left.fileIndexLow64Hex == right.fileIndexLow64Hex;
        }

        private static bool PeIdentityEqual(InProcessPeIdentityV1 left, InProcessPeIdentityV1 right)
        {
            return left != null && right != null && left.succeeded && right.succeeded &&
                left.peHeaderOffset == right.peHeaderOffset && left.optionalHeaderMagicHex == right.optionalHeaderMagicHex &&
                left.checksumFieldOffset == right.checksumFieldOffset && left.checksumHex == right.checksumHex &&
                left.securityDirectoryFieldOffset == right.securityDirectoryFieldOffset &&
                left.certificateTableFileOffset == right.certificateTableFileOffset &&
                left.certificateTableSizeBytes == right.certificateTableSizeBytes;
        }

        private static bool ProhibitedRootsAbsent(string projectRoot)
        {
            string[] roots =
            {
                "Research/PilotRuns/Gate14Re-ME", "Research/FormalRuns/Gate14Re-ME",
                "Research/QualificationRuns/Gate14Re-ME", "Research/MeasuredRuns/Gate14Re-ME"
            };
            for (int index = 0; index < roots.Length; index++)
            {
                string full = Path.GetFullPath(Path.Combine(projectRoot, roots[index].Replace('/', Path.DirectorySeparatorChar)));
                if (Directory.Exists(full) || File.Exists(full)) return false;
            }
            return true;
        }

        private static void Bind(string root, List<Attempt004FileBindingV1> bindings, string role, string relativePath, string expectedSha256)
        {
            BindAbsolute(bindings, role, Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar))),
                expectedSha256, root);
        }

        private static void BindAbsolute(List<Attempt004FileBindingV1> bindings, string role, string path, string expectedSha256, string sourceRoot)
        {
            string full = Path.GetFullPath(path);
            Require(File.Exists(full), "Missing bound file: " + full);
            string actual = Sha256File(full);
            Attempt004FileBindingV1 binding = new Attempt004FileBindingV1
            {
                role = role,
                relativePath = MakeRelativePath(sourceRoot, full),
                lengthBytes = new FileInfo(full).Length,
                expectedSha256 = expectedSha256.ToLowerInvariant(),
                actualSha256 = actual,
                matched = actual == expectedSha256.ToLowerInvariant()
            };
            bindings.Add(binding);
            Require(binding.matched, "Hash mismatch: " + binding.relativePath);
        }

        private static bool AllBindingsMatched(List<Attempt004FileBindingV1> bindings)
        {
            if (bindings.Count == 0) return false;
            for (int index = 0; index < bindings.Count; index++) if (!bindings[index].matched) return false;
            return true;
        }

        private static string ReadText(string root, string relativePath)
        {
            string full = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            Require(File.Exists(full), "Missing file: " + relativePath);
            return File.ReadAllText(full, new UTF8Encoding(false, true));
        }

        private static string ResolveExactOutputDirectory(string sourceRoot, string requested)
        {
            string expected = Path.GetFullPath(Path.Combine(sourceRoot, ExpectedOutputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            string actual = Path.GetFullPath(requested);
            Require(string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase),
                "Self-check output path is outside the exact authorized verification directory.");
            Require(Directory.Exists(actual), "Authorized self-check output directory does not exist.");
            Require(!File.Exists(Path.Combine(actual, "in-process-ready-snapshot.v1.json")) &&
                !File.Exists(Path.Combine(actual, "input-schema-compatibility-self-check-receipt.v2.json")),
                "Self-check output evidence already exists; overwrite is prohibited.");
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

        private static string MakeRelativePath(string root, string path)
        {
            Uri rootUri = new Uri(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri pathUri = new Uri(Path.GetFullPath(path));
            return Uri.UnescapeDataString(rootUri.MakeRelativeUri(pathUri).ToString()).Replace('\\', '/');
        }

        private static string NormalizePath(string path)
        {
            return Path.GetFullPath(RemoveExtendedPathPrefix(path)).Replace('\\', '/');
        }

        private static string RemoveExtendedPathPrefix(string path)
        {
            if (path.StartsWith("\\\\?\\UNC\\", StringComparison.OrdinalIgnoreCase)) return "\\\\" + path.Substring(8);
            if (path.StartsWith("\\\\?\\", StringComparison.OrdinalIgnoreCase)) return path.Substring(4);
            return path;
        }

        private static bool PathsEqual(string left, string right)
        {
            if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right)) return false;
            return string.Equals(NormalizePath(left), NormalizePath(right), StringComparison.OrdinalIgnoreCase);
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
