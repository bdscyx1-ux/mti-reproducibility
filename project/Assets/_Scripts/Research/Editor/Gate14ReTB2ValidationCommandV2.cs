using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReTB2.V1;
using DDM.Research.Gate14ReTB2.V2;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate14ReTB2ValidationCommandV2
    {
        private const string RelativeOutput = "Research/Verification/Gate14Re-TB2/simplified-runner-v2/editor-validation-only-attempt-001";
        private const string RelativePlan = "Research/Gate14Re-TB2/Execution/v2/formal-anonymous-execution-plan.v2.json";
        private const string RelativeContract = "Research/Gate14Re-TB2/Execution/v2/execution-contract.v2.json";
        private const string RelativeOutputSchema = "Research/Gate14Re-TB2/Execution/v2/anonymous-superblock-output-schema.v2.json";
        private const string RelativeCustody = "Research/Gate14Re-TB2/Blinding/v1/label-custody-commitment.v1.json";

        public static void Run()
        {
            try
            {
                string root = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string output = Full(root, RelativeOutput);
                if (Directory.Exists(output)) throw new InvalidOperationException("Refusing to overwrite v2 editor validation attempt.");
                Directory.CreateDirectory(output);
                int assertions = 0;

                string planPath = Full(root, RelativePlan);
                string planText = File.ReadAllText(planPath, Encoding.UTF8);
                AssertNoProductionIdentity(planText, ref assertions);
                Gate14ReTB2FormalPlanV2 plan = JsonUtility.FromJson<Gate14ReTB2FormalPlanV2>(planText);
                Require(plan != null && plan.schema == "gate14re-tb2-simplified-formal-execution-plan-v2" && plan.route == "R2" && plan.B == 336, "Plan identity", ref assertions);
                Require(plan.quantitySubstudyRetained && plan.N128AnchorReuse && plan.designCellCount == 16, "Quantity sub-study retention", ref assertions);
                Require(plan.superblocks != null && plan.superblocks.Length == 5376 && plan.plannedAnonymousAlgorithmLanes == 21504 && plan.plannedFreshUnityProcesses == 5376, "Plan cardinality", ref assertions);
                Require(plan.processesPerSuperblock == 1 && plan.lanesPerProcess == 4 && plan.oneFreshProcessPerSuperblock && plan.hardResetBetweenLanesRequired, "Consolidated process isolation", ref assertions);
                Require(plan.tracedSuperblocks == 288 && plan.tracedAnonymousLanes == 1152 && plan.fullM1ThroughM5TelemetryLanes == 21504, "Trace/telemetry counts", ref assertions);
                Require(!plan.algorithmIdentityPresent && plan.wholeSuperblockAtomicity && plan.maximumWholeSuperblockTechnicalReplacements == 1 && !plan.perAlgorithmRetryResumeTopUpMergeSkipReorder && !plan.formalRootCreated && !plan.formalCollectionAuthorized, "Anonymous atomic no-collection policy", ref assertions);

                Gate14ReTB2ExecutionContractV2 contract = JsonUtility.FromJson<Gate14ReTB2ExecutionContractV2>(File.ReadAllText(Full(root, RelativeContract), Encoding.UTF8));
                Require(contract != null && contract.schema == "gate14re-tb2-execution-contract-v2" && contract.formalPlanSha256 == Sha256File(planPath), "Execution contract plan binding", ref assertions);
                Require(contract.processModel != null && contract.processModel.oneFreshProcessPerCompleteSuperblock && contract.processModel.processesPerSuperblock == 1 && contract.processModel.anonymousLanesPerProcess == 4, "Execution process model", ref assertions);
                Require(contract.hardResetBetweenLanes != null && contract.hardResetBetweenLanes.required && contract.hardResetBetweenLanes.waitForUnityDestroyCompletion && contract.hardResetBetweenLanes.verifyNoPriorLaneRuntimeObjects && !contract.hardResetBetweenLanes.cacheOrOperatingSystemIsolationClaimed, "Hard-reset contract", ref assertions);
                Require(contract.trace != null && contract.trace.tracedSuperblocks == 288 && contract.trace.tracedAnonymousLanes == 1152 && contract.trace.untracedAnonymousLanes == 20352 && contract.trace.essentialM1ThroughM5TelemetryRetainedForEveryLane, "Trace-audit contract", ref assertions);
                Require(!contract.collectionAuthorized && !contract.productionIdentityPermittedInOutput && !contract.fileIoDuringMeasuredWindow && !contract.compressionDuringMeasuredWindow, "Execution no-collection/no-identity/M4 isolation", ref assertions);

                ValidateEveryBlockBinding(root, plan, ref assertions);
                ValidateRepresentativePreparedInputs(root, plan, ref assertions);
                ValidateProtocolNegatives(root, plan, ref assertions);
                ValidateCustody(root, ref assertions);
                ValidateOutputSurface(ref assertions);
                ValidateCommonMask(ref assertions);
                ValidateHardResetImplementationSurface(ref assertions);
                ValidateTraceContainer(output, ref assertions);
                ValidateStandaloneMarkers(root, ref assertions);
                ValidateFrozenAlgorithmSources(root, ref assertions);

                ValidationReceipt receipt = new ValidationReceipt
                {
                    schema = "gate14re-tb2-editor-validation-only-receipt-v2",
                    studyId = "Gate14Re-TB2",
                    status = "PASS",
                    assertions = assertions,
                    planSha256 = Sha256File(planPath),
                    executionContractSha256 = Sha256File(Full(root, RelativeContract)),
                    outputSchemaContractSha256 = Sha256File(Full(root, RelativeOutputSchema)),
                    custodyCommitmentSha256 = Sha256File(Full(root, RelativeCustody)),
                    all5376SuperblocksBound = true,
                    anonymousLaneBindings = 21504,
                    representativeDesignCellsPrepared = 16,
                    tracedAndUntracedStandaloneLifecycleValidationPassed = true,
                    hardResetTransitionsPerValidatedProcess = 3,
                    commonM2MaskSyntheticTestPassed = true,
                    custodyPlaintextPersisted = false,
                    productionIdentityWritten = false,
                    plannerInvokedByTraceVerification = false,
                    m1ThroughM5Produced = false,
                    measuredRootCreated = false,
                    collectionAuthorized = false
                };
                WriteNewJson(Path.Combine(output, "validation-receipt.v2.json"), receipt);
                Debug.Log("GATE14RE_TB2_V2_EDITOR_VALIDATION_PASS " + assertions.ToString(CultureInfo.InvariantCulture));
                EditorApplication.Exit(0);
            }
            catch (Exception exception) { Debug.LogException(exception); EditorApplication.Exit(1); }
        }

        private static void ValidateEveryBlockBinding(string root, Gate14ReTB2FormalPlanV2 plan, ref int assertions)
        {
            HashSet<string> blocks = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> lanes = new HashSet<string>(StringComparer.Ordinal);
            int traced = 0;
            for (int index = 0; index < plan.superblocks.Length; index++)
            {
                Gate14ReTB2FormalSuperblockV2 block = plan.superblocks[index];
                Require(block != null && blocks.Add(block.superblockId), "Unique superblock", ref assertions);
                Require(block.sequence == index + 1 && block.operationalChunkSequence == block.drawIndex && block.hardTimeoutSeconds == 3600 && block.maximumWholeSuperblockTechnicalReplacements == 1, "Block sequence/chunk/timeout/replacement", ref assertions);
                Require(block.anonymousLabelsInOrder != null && block.anonymousLabelsInOrder.Length == 4 && block.laneIdsInOrder != null && block.laneIdsInOrder.Length == 4, "Block four-lane structure", ref assertions);
                HashSet<string> labels = new HashSet<string>(block.anonymousLabelsInOrder, StringComparer.Ordinal);
                Require(labels.SetEquals(new[] { "K1", "K2", "K3", "K4" }), "Block anonymous permutation", ref assertions);
                for (int lane = 0; lane < 4; lane++)
                {
                    string expected = block.superblockId + "-" + block.anonymousLabelsInOrder[lane] + "-O" + (lane + 1).ToString(CultureInfo.InvariantCulture);
                    Require(block.laneIdsInOrder[lane] == expected && lanes.Add(expected), "Lane identity/order", ref assertions);
                }
                bool expectedTrace = IsTraceDraw(block.drawIndex);
                Require(block.traceCaptureRequired == expectedTrace, "Frozen trace selection", ref assertions);
                if (expectedTrace) traced++;
                string bundlePath = Full(root, block.bundleRelativePath);
                FileInfo info = new FileInfo(bundlePath);
                Require(info.Exists && info.Length == block.bundleFileBytes && Sha256File(bundlePath) == block.bundleFileSha256, "Adopted bundle file binding", ref assertions);
            }
            Require(blocks.Count == 5376 && lanes.Count == 21504 && traced == 288, "Global block/lane/trace counts", ref assertions);
        }

        private static void ValidateRepresentativePreparedInputs(string root, Gate14ReTB2FormalPlanV2 plan, ref int assertions)
        {
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < plan.superblocks.Length && seen.Count < 16; index++)
            {
                Gate14ReTB2FormalSuperblockV2 block = plan.superblocks[index];
                string key = block.module + "|" + block.conditionId + "|" + block.unitCount.ToString(CultureInfo.InvariantCulture);
                if (!seen.Add(key)) continue;
                Gate14ReTB2InputBundleV1 bundle = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(File.ReadAllText(Full(root, block.bundleRelativePath), Encoding.UTF8));
                string scenarioPath = Full(root, bundle.sourceScenarioRelativePath);
                Require(Sha256File(scenarioPath) == bundle.sourceScenarioSha256, "Representative scenario hash", ref assertions);
                Gate14ReTB2PreparedScenarioV1 prepared = Gate14ReTB2ProtocolV1.Prepare(DeterministicScenarioJson.LoadFromFile(scenarioPath), bundle);
                Require(prepared.Resolved.Agents.Count == bundle.unitCount && prepared.Resolved.Goals.Count == 1 && prepared.Resolved.ScheduledChanges.Count == 5, "Representative prepared scenario", ref assertions);
            }
            Require(seen.Count == 16, "All 16 unique design cells prepared", ref assertions);
        }

        private static void ValidateProtocolNegatives(string root, Gate14ReTB2FormalPlanV2 plan, ref int assertions)
        {
            Gate14ReTB2FormalSuperblockV2 block = plan.superblocks[0];
            string json = File.ReadAllText(Full(root, block.bundleRelativePath), Encoding.UTF8);
            Gate14ReTB2InputBundleV1 original = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(json);
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(Full(root, original.sourceScenarioRelativePath));
            Gate14ReTB2InputBundleV1 badN = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(json);
            badN.unitCount = 2;
            ExpectFailure(delegate { Gate14ReTB2ProtocolV1.Prepare(loaded, badN); }, "Unregistered N rejected", ref assertions);
            Gate14ReTB2InputBundleV1 badTick = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(json);
            badTick.eventSchedule.ticks[0]++;
            ExpectFailure(delegate { Gate14ReTB2ProtocolV1.Prepare(loaded, badTick); }, "Event tick tamper rejected", ref assertions);
            Gate14ReTB2InputBundleV1 badSource = JsonUtility.FromJson<Gate14ReTB2InputBundleV1>(json);
            badSource.sourceScenarioSha256 = new string('0', 64);
            ExpectFailure(delegate { Gate14ReTB2ProtocolV1.Prepare(loaded, badSource); }, "Source hash tamper rejected", ref assertions);
        }

        private static void ValidateCustody(string root, ref int assertions)
        {
            Gate14ReTB2LabelCustodyCommitmentV1 commitment = JsonUtility.FromJson<Gate14ReTB2LabelCustodyCommitmentV1>(File.ReadAllText(Full(root, RelativeCustody), Encoding.UTF8));
            Require(commitment != null && commitment.schema == "gate14re-tb2-label-custody-commitment-v1" && commitment.status == "FROZEN_MAPPING_ENCRYPTED_NOT_RELEASED", "Custody header", ref assertions);
            Require(commitment.protection != null && commitment.protection.mechanism == "Windows DPAPI CryptProtectData" && commitment.protection.scope == "CurrentUser on this host account" && commitment.protection.uiForbidden, "Custody protection", ref assertions);
            Require(Sha256File(Full(root, commitment.protection.payloadRelativePath)) == commitment.protection.payloadSha256 && Sha256File(Full(root, commitment.protection.entropyRelativePath)) == commitment.protection.entropySha256, "Custody encrypted-file hashes", ref assertions);
            Require(!commitment.plaintextMappingPersisted && !commitment.mappingMayBeReleasedBeforeFrozenWinnerAdjudication && !commitment.unblindingAuthorized, "Custody no-release boundary", ref assertions);
        }

        private static void ValidateOutputSurface(ref int assertions)
        {
            HashSet<string> deny = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "productionAlgorithmId", "algorithmId", "algorithmName", "identityMapping", "labelMapping", "custodySecret", "winner", "ranking", "superiority" };
            FieldInfo[] top = typeof(Gate14ReTB2SuperblockOutputV2).GetFields(BindingFlags.Instance | BindingFlags.Public);
            for (int index = 0; index < top.Length; index++) Require(!deny.Contains(top[index].Name), "Top-level anonymous output field", ref assertions);
            FieldInfo[] lane = typeof(Gate14ReTB2LaneOutputV2).GetFields(BindingFlags.Instance | BindingFlags.Public);
            for (int index = 0; index < lane.Length; index++) Require(!deny.Contains(lane[index].Name), "Lane anonymous output field", ref assertions);
            Require(typeof(Gate14ReTB2SuperblockOutputV2).GetField("productionAlgorithmIdentityPresent") != null, "Explicit output identity-negative latch", ref assertions);
        }

        private static void ValidateCommonMask(ref int assertions)
        {
            List<Gate14ReTB2LaneOutputV2> lanes = new List<Gate14ReTB2LaneOutputV2>();
            for (int lane = 0; lane < 4; lane++)
            {
                lanes.Add(new Gate14ReTB2LaneOutputV2
                {
                    units = new[]
                    {
                        new Gate14ReTB2UnitRawV1 { unitIndex = 0, arrived = true, cumulativeHorizontalPathLength = 4d + lane },
                        new Gate14ReTB2UnitRawV1 { unitIndex = 1, arrived = lane != 2, cumulativeHorizontalPathLength = 8d + lane }
                    }
                });
            }
            MethodInfo method = typeof(Gate14ReTB2FormalControllerV2).GetMethod("BuildCommonM2Mask", BindingFlags.NonPublic | BindingFlags.Static);
            Require(method != null, "Common-mask implementation exists", ref assertions);
            int[] mask = (int[])method.Invoke(null, new object[] { lanes, 2 });
            Require(mask.Length == 1 && mask[0] == 0, "Common mask uses intersection across all four lanes", ref assertions);
        }

        private static void ValidateHardResetImplementationSurface(ref int assertions)
        {
            Type type = typeof(Gate14ReTB2FormalControllerV2);
            Require(type.GetMethod("ResetAndBeginNextLane", BindingFlags.NonPublic | BindingFlags.Instance) != null, "Hard-reset coroutine exists", ref assertions);
            Require(type.GetMethod("QueueLaneObjectsForDestruction", BindingFlags.NonPublic | BindingFlags.Instance) != null, "Destroy queue exists", ref assertions);
            Require(type.GetField("destroyedLaneObjects", BindingFlags.NonPublic | BindingFlags.Instance) != null, "Destroyed-object verification ledger exists", ref assertions);
            Require(type.GetField("resetReceipts", BindingFlags.NonPublic | BindingFlags.Instance) != null, "Reset receipt ledger exists", ref assertions);
        }

        private static void ValidateTraceContainer(string output, ref int assertions)
        {
            Gate14ReTB2TraceHeaderV1 header = new Gate14ReTB2TraceHeaderV1 { schema = "gate14re-tb2-trace-header-v1", studyId = "Gate14Re-TB2", sampleId = "SYNTHETIC-NO-OUTCOME", superblockId = "SYNTHETIC", anonymousAlgorithmLabel = "K1", conditionId = "SYNTHETIC", unitCount = 2, inputBundleSha256 = new string('1', 64), buildTreeSha256 = new string('2', 64), assemblySha256 = new string('3', 64), fixedStepSeconds = 0.02d, captureEveryFixedTicks = 5, movementCapTicks = 9000L };
            Gate14ReTB2TraceRecorderV1 recorder = new Gate14ReTB2TraceRecorderV1(header, 2);
            recorder.CaptureSyntheticForValidation(0L, 0L, 0, new[] { new Vector3(0.5f, 0f, 0.5f), new Vector3(1.5f, 0f, 0.5f) }, new[] { false, false });
            recorder.CaptureSyntheticForValidation(5L, 1L, 2, new[] { new Vector3(1f, 0f, 1f), new Vector3(1.75f, 0f, 0.75f) }, new[] { true, false });
            string path = Path.Combine(output, "synthetic-visual-trace.raw");
            Gate14ReTB2TraceWriteResultV1 result = recorder.Flush(path);
            byte[] raw = File.ReadAllBytes(path);
            Require(raw.Length > 48 && Encoding.ASCII.GetString(raw, 0, 8) == "G14RTBTR" && BitConverter.ToInt32(raw, 8) == 1 && BitConverter.ToInt32(raw, 12) == 3, "Trace magic/version/chunks", ref assertions);
            Require(result.traceChunkCount == 3 && result.traceCapturedTickCount == 2 && result.traceRawSha256 == Sha256File(path), "Trace write receipt", ref assertions);
        }

        private static void ValidateStandaloneMarkers(string root, ref int assertions)
        {
            string[] paths =
            {
                "Research/Verification/Gate14Re-TB2/simplified-runner-v2/standalone-validation-attempt-001/validation-marker.v2.json",
                "Research/Verification/Gate14Re-TB2/simplified-runner-v2/standalone-validation-attempt-002/validation-marker.v2.json"
            };
            for (int index = 0; index < paths.Length; index++)
            {
                Gate14ReTB2ValidationMarkerV2 marker = JsonUtility.FromJson<Gate14ReTB2ValidationMarkerV2>(File.ReadAllText(Full(root, paths[index]), Encoding.UTF8));
                Require(marker != null && marker.status == "PASS" && marker.validatedAnonymousLanes == 4 && marker.validatedHardResets == 3 && marker.allFourProductionPlannersExercisedWithoutCustodyDecryption && marker.inputBundlePreparedPerLane && !marker.labelCustodyResolvedInMemory && !marker.productionIdentityWritten && marker.tracePolicyMatchedPlan && !marker.formalObservationProduced && !marker.m1ThroughM5OutputProduced && !marker.collectionStarted, "Standalone lifecycle marker", ref assertions);
            }
            Require(Directory.GetFiles(Full(root, "Research/Verification/Gate14Re-TB2/simplified-runner-v2/standalone-validation-attempt-002/traces")).Length == 0, "Untraced block produced no trace files", ref assertions);
        }

        private static void ValidateFrozenAlgorithmSources(string root, ref int assertions)
        {
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs")) == "a54bb43ed906c856e3d45493c4d3d10ff1b6f1e0ccda1a9f25ea774908b9c778", "A*-R source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs")) == "ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f", "D*L source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs")) == "bdaa52bc93950ea6a1737a7629ec6ceda60370f6ebc489deb166e2eddc51f3e1", "C-FF source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs")) == "63aa0792bd0935d1e98158278580cf2ece5980cf3e52ef7e9adb16bbcddc7638", "IDFF source", ref assertions);
        }

        private static bool IsTraceDraw(int draw) { return (draw >= 1 && draw <= 6) || (draw >= 163 && draw <= 168) || (draw >= 331 && draw <= 336); }
        private static void AssertNoProductionIdentity(string text, ref int assertions) { string[] deny = { "A*-R", "D*L", "C-FF", "IDFF", "productionAlgorithmId" }; for (int index = 0; index < deny.Length; index++) Require(text.IndexOf(deny[index], StringComparison.Ordinal) < 0, "Plan identity denylist", ref assertions); }
        private static void ExpectFailure(Action action, string label, ref int assertions) { bool failed = false; try { action(); } catch { failed = true; } Require(failed, label, ref assertions); }
        private static void Require(bool value, string label, ref int assertions) { if (!value) throw new InvalidOperationException("Validation assertion failed: " + label); assertions++; }
        private static string Full(string root, string relative) { return Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))); }
        private static string Sha256File(string path) { using (FileStream stream = File.OpenRead(path)) using (SHA256 sha = SHA256.Create()) { byte[] value = sha.ComputeHash(stream); StringBuilder builder = new StringBuilder(value.Length * 2); for (int index = 0; index < value.Length; index++) builder.Append(value[index].ToString("x2", CultureInfo.InvariantCulture)); return builder.ToString(); } }
        private static void WriteNewJson(string path, object value) { if (File.Exists(path)) throw new IOException("Overwrite forbidden."); File.WriteAllText(path, JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n", new UTF8Encoding(false)); }

        [Serializable]
        private sealed class ValidationReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public int assertions;
            public string planSha256;
            public string executionContractSha256;
            public string outputSchemaContractSha256;
            public string custodyCommitmentSha256;
            public bool all5376SuperblocksBound;
            public int anonymousLaneBindings;
            public int representativeDesignCellsPrepared;
            public bool tracedAndUntracedStandaloneLifecycleValidationPassed;
            public int hardResetTransitionsPerValidatedProcess;
            public bool commonM2MaskSyntheticTestPassed;
            public bool custodyPlaintextPersisted;
            public bool productionIdentityWritten;
            public bool plannerInvokedByTraceVerification;
            public bool m1ThroughM5Produced;
            public bool measuredRootCreated;
            public bool collectionAuthorized;
        }
    }
}
