using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14Re.V1;
using DDM.Research.Gate14ReTB.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate14ReTBValidationCommandV1
    {
        private const string RelativeOutput = "Research/Verification/Gate14Re-TB/precollection-implementation-attempt-001/editor-validation-only-attempt-001";
        private const string RelativePlan = "Research/Gate14Re-TB/Execution/v1/stage1-anonymous-execution-plan.v1.json";
        private const string RelativeContract = "Research/Gate14Re-TB/Execution/v1/execution-contract.v1.json";
        private const string RelativeCustody = "Research/Gate14Re-TB/Blinding/v1/label-custody-commitment.v1.json";

        public static void Run()
        {
            try
            {
                string root = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string output = Full(root, RelativeOutput);
                if (Directory.Exists(output)) throw new InvalidOperationException("Refusing to overwrite validation attempt.");
                Directory.CreateDirectory(output);
                int assertions = 0;

                string planPath = Full(root, RelativePlan);
                string planText = File.ReadAllText(planPath, Encoding.UTF8);
                AssertNoProductionIdentity(planText, ref assertions);
                Gate14ReTBStage1PlanV1 plan = JsonUtility.FromJson<Gate14ReTBStage1PlanV1>(planText);
                Require(plan != null && plan.samples != null && plan.samples.Length == 1536 && plan.superblocks != null && plan.superblocks.Length == 384, "Plan cardinality", ref assertions);
                Require(!plan.algorithmIdentityPresent && plan.wholeSuperblockAtomicity && !plan.perAlgorithmRetryResumeTopUpMergeSkipReorder, "Plan anonymous atomic policy", ref assertions);

                Gate14ReTBExecutionContractV1 contract = JsonUtility.FromJson<Gate14ReTBExecutionContractV1>(File.ReadAllText(Full(root, RelativeContract), Encoding.UTF8));
                Require(contract != null && contract.schema == "gate14re-tb-execution-contract-v1" && !contract.collectionAuthorized && !contract.productionIdentityPermittedInOutput && !contract.fileIoDuringMeasuredWindow && !contract.compressionDuringMeasuredWindow, "Execution contract no-collection/no-identity/M4 isolation", ref assertions);
                Require(contract.stage1PlanSha256 == Sha256File(planPath) && contract.inputBundleFileManifestSha256 == plan.inputBundleFileManifestSha256 && contract.labelCustodyCommitmentSha256 == plan.labelCustodyCommitmentSha256, "Execution contract plan/input/custody hashes", ref assertions);

                ValidateEverySampleBinding(root, plan, ref assertions);
                ValidateRepresentativePreparedInputs(root, plan, ref assertions);
                ValidateProtocolNegatives(root, plan, ref assertions);
                ValidateCustody(root, ref assertions);
                ValidateOutputSurface(ref assertions);
                ValidateTraceContainer(output, ref assertions);
                ValidateFrozenAlgorithmSources(root, ref assertions);

                ValidationReceipt receipt = new ValidationReceipt
                {
                    schema = "gate14re-tb-editor-validation-only-receipt-v1",
                    studyId = "Gate14Re-TB",
                    status = "PASS",
                    assertions = assertions,
                    planSha256 = Sha256File(planPath),
                    executionContractSha256 = Sha256File(Full(root, RelativeContract)),
                    custodyCommitmentSha256 = Sha256File(Full(root, RelativeCustody)),
                    all1536AnonymousSamplesBound = true,
                    representativeDesignCellsPrepared = 16,
                    custodyPlaintextPersisted = false,
                    productionIdentityWritten = false,
                    traceRoundTripPassed = true,
                    plannerInvokedByTraceVerification = false,
                    m1ThroughM5Produced = false,
                    measuredRootCreated = false,
                    collectionAuthorized = false
                };
                WriteNewJson(Path.Combine(output, "validation-receipt.v1.json"), receipt);
                Debug.Log("GATE14RE_TB_EDITOR_VALIDATION_PASS " + assertions.ToString(CultureInfo.InvariantCulture));
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
                EditorApplication.Exit(1);
            }
        }

        private static void ValidateEverySampleBinding(string root, Gate14ReTBStage1PlanV1 plan, ref int assertions)
        {
            Dictionary<string, Gate14ReTBStage1SuperblockV1> blocks = new Dictionary<string, Gate14ReTBStage1SuperblockV1>(StringComparer.Ordinal);
            for (int index = 0; index < plan.superblocks.Length; index++)
            {
                Gate14ReTBStage1SuperblockV1 block = plan.superblocks[index];
                Require(block != null && !blocks.ContainsKey(block.superblockId), "Unique superblock", ref assertions);
                blocks.Add(block.superblockId, block);
                Require(block.anonymousLabelsInOrder != null && block.anonymousLabelsInOrder.Length == 4 && block.sampleIdsInOrder != null && block.sampleIdsInOrder.Length == 4 && block.maximumWholeSuperblockTechnicalReplacements == 1, "Superblock atomic structure", ref assertions);
            }
            HashSet<string> sampleIds = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < plan.samples.Length; index++)
            {
                Gate14ReTBStage1SampleV1 sample = plan.samples[index];
                Gate14ReTBStage1SuperblockV1 block;
                Require(sample != null && sampleIds.Add(sample.sampleId), "Unique sample reference", ref assertions);
                Require(blocks.TryGetValue(sample.superblockId, out block), "Sample block reference", ref assertions);
                int position = sample.orderPosition - 1;
                Require(position >= 0 && position < 4 && block.sampleIdsInOrder[position] == sample.sampleId && block.anonymousLabelsInOrder[position] == sample.anonymousAlgorithmLabel && sample.hardTimeoutSeconds == 3600, "Sample order/label/timeout", ref assertions);
                string bundlePath = Full(root, sample.bundleRelativePath);
                FileInfo info = new FileInfo(bundlePath);
                Require(info.Exists && info.Length == sample.bundleFileBytes && Sha256File(bundlePath) == sample.bundleFileSha256, "Sample bundle file binding", ref assertions);
            }
        }

        private static void ValidateRepresentativePreparedInputs(string root, Gate14ReTBStage1PlanV1 plan, ref int assertions)
        {
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < plan.samples.Length && seen.Count < 16; index++)
            {
                Gate14ReTBStage1SampleV1 sample = plan.samples[index];
                string bundlePath = Full(root, sample.bundleRelativePath);
                Gate14ReTBInputBundleV1 bundle = JsonUtility.FromJson<Gate14ReTBInputBundleV1>(File.ReadAllText(bundlePath, Encoding.UTF8));
                string key = bundle.module + "|" + bundle.conditionId + "|" + bundle.unitCount.ToString(CultureInfo.InvariantCulture);
                if (!seen.Add(key)) continue;
                string scenarioPath = Full(root, bundle.sourceScenarioRelativePath);
                Require(Sha256File(scenarioPath) == bundle.sourceScenarioSha256, "Representative source scenario hash", ref assertions);
                Gate14ReTBPreparedScenarioV1 prepared = Gate14ReTBProtocolV1.Prepare(DeterministicScenarioJson.LoadFromFile(scenarioPath), bundle);
                Require(prepared.Resolved.Agents.Count == bundle.unitCount && prepared.Resolved.Goals.Count == 1 && prepared.Resolved.ScheduledChanges.Count == 5, "Representative prepared scenario cardinality", ref assertions);
            }
            Require(seen.Count == 16, "All 16 design-cell shapes prepared", ref assertions);
        }

        private static void ValidateProtocolNegatives(string root, Gate14ReTBStage1PlanV1 plan, ref int assertions)
        {
            Gate14ReTBStage1SampleV1 sample = plan.samples[0];
            string json = File.ReadAllText(Full(root, sample.bundleRelativePath), Encoding.UTF8);
            Gate14ReTBInputBundleV1 original = JsonUtility.FromJson<Gate14ReTBInputBundleV1>(json);
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(Full(root, original.sourceScenarioRelativePath));

            Gate14ReTBInputBundleV1 badN = JsonUtility.FromJson<Gate14ReTBInputBundleV1>(json);
            badN.unitCount = 2;
            ExpectFailure(delegate { Gate14ReTBProtocolV1.Prepare(loaded, badN); }, "Unregistered N rejected", ref assertions);
            Gate14ReTBInputBundleV1 badTick = JsonUtility.FromJson<Gate14ReTBInputBundleV1>(json);
            badTick.eventSchedule.ticks[0]++;
            ExpectFailure(delegate { Gate14ReTBProtocolV1.Prepare(loaded, badTick); }, "Event tick tamper rejected", ref assertions);
            Gate14ReTBInputBundleV1 badSource = JsonUtility.FromJson<Gate14ReTBInputBundleV1>(json);
            badSource.sourceScenarioSha256 = new string('0', 64);
            ExpectFailure(delegate { Gate14ReTBProtocolV1.Prepare(loaded, badSource); }, "Source hash tamper rejected", ref assertions);
        }

        private static void ValidateCustody(string root, ref int assertions)
        {
            string path = Full(root, RelativeCustody);
            Gate14ReTBLabelCustodyCommitmentV1 commitment = JsonUtility.FromJson<Gate14ReTBLabelCustodyCommitmentV1>(File.ReadAllText(path, Encoding.UTF8));
            string payloadPath = Full(root, commitment.protection.payloadRelativePath);
            string entropyPath = Full(root, commitment.protection.entropyRelativePath);
            Require(Sha256File(payloadPath) == commitment.protection.payloadSha256 && Sha256File(entropyPath) == commitment.protection.entropySha256, "Custody encrypted-file hashes", ref assertions);
            byte[] entropy = File.ReadAllBytes(entropyPath);
            byte[] plaintext = null;
            try
            {
                plaintext = Gate14ReTBDpapiV1.UnprotectCurrentUserNoUi(File.ReadAllBytes(payloadPath), entropy);
                Require(Sha256Bytes(plaintext) == commitment.mappingCommitmentSha256, "Custody plaintext commitment", ref assertions);
                Gate14ReTBLabelCustodySecretV1 secret = JsonUtility.FromJson<Gate14ReTBLabelCustodySecretV1>(Encoding.UTF8.GetString(plaintext));
                HashSet<string> labels = new HashSet<string>(StringComparer.Ordinal);
                HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
                for (int index = 0; index < secret.mapping.Length; index++) { labels.Add(secret.mapping[index].anonymousLabel); algorithms.Add(secret.mapping[index].productionAlgorithmId); }
                Require(labels.SetEquals(new[] { "K1", "K2", "K3", "K4" }) && algorithms.SetEquals(new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField }), "Custody bijection", ref assertions);
            }
            finally
            {
                Array.Clear(entropy, 0, entropy.Length);
                if (plaintext != null) Array.Clear(plaintext, 0, plaintext.Length);
            }
        }

        private static void ValidateOutputSurface(ref int assertions)
        {
            HashSet<string> deny = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "productionAlgorithmId", "algorithmId", "algorithmName", "identityMapping", "labelMapping", "custodySecret", "winner", "ranking", "superiority" };
            FieldInfo[] fields = typeof(Gate14ReTBSampleOutputV1).GetFields(BindingFlags.Instance | BindingFlags.Public);
            for (int index = 0; index < fields.Length; index++) Require(!deny.Contains(fields[index].Name), "Anonymous output field allowlist", ref assertions);
            Require(typeof(Gate14ReTBSampleOutputV1).GetField("productionAlgorithmIdentityPresent") != null, "Explicit output identity-negative latch", ref assertions);
        }

        private static void ValidateTraceContainer(string output, ref int assertions)
        {
            Gate14ReTBTraceHeaderV1 header = new Gate14ReTBTraceHeaderV1 { schema = "gate14re-tb-trace-header-v1", studyId = "Gate14Re-TB", sampleId = "SYNTHETIC-NO-OUTCOME", superblockId = "SYNTHETIC", anonymousAlgorithmLabel = "K1", conditionId = "SYNTHETIC", unitCount = 2, inputBundleSha256 = new string('1', 64), buildTreeSha256 = new string('2', 64), assemblySha256 = new string('3', 64), fixedStepSeconds = 0.02d, captureEveryFixedTicks = 5, movementCapTicks = 9000L };
            Gate14ReTBTraceRecorderV1 recorder = new Gate14ReTBTraceRecorderV1(header, 2);
            recorder.CaptureSyntheticForValidation(0L, 0L, 0, new[] { new Vector3(0.5f, 0f, 0.5f), new Vector3(1.5f, 0f, 0.5f) }, new[] { false, false });
            recorder.CaptureSyntheticForValidation(5L, 1L, 2, new[] { new Vector3(1f, 0f, 1f), new Vector3(1.75f, 0f, 0.75f) }, new[] { true, false });
            string path = Path.Combine(output, "synthetic-visual-trace.raw");
            Gate14ReTBTraceWriteResultV1 result = recorder.Flush(path);
            byte[] raw = File.ReadAllBytes(path);
            Require(raw.Length > 48 && Encoding.ASCII.GetString(raw, 0, 8) == "G14RTBTR" && BitConverter.ToInt32(raw, 8) == 1 && BitConverter.ToInt32(raw, 12) == 3, "Trace magic/version/chunk count", ref assertions);
            Require(result.traceChunkCount == 3 && result.traceCapturedTickCount == 2 && result.traceRawSha256 == Sha256File(path), "Trace write receipt", ref assertions);
        }

        private static void ValidateFrozenAlgorithmSources(string root, ref int assertions)
        {
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs")) == "a54bb43ed906c856e3d45493c4d3d10ff1b6f1e0ccda1a9f25ea774908b9c778", "A*-R source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs")) == "ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f", "D*L source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs")) == "bdaa52bc93950ea6a1737a7629ec6ceda60370f6ebc489deb166e2eddc51f3e1", "C-FF source", ref assertions);
            Require(Sha256File(Full(root, "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs")) == "63aa0792bd0935d1e98158278580cf2ece5980cf3e52ef7e9adb16bbcddc7638", "IDFF source", ref assertions);
        }

        private static void AssertNoProductionIdentity(string text, ref int assertions)
        {
            string[] deny = { "A*-R", "D*L", "C-FF", "IDFF", "productionAlgorithmId" };
            for (int index = 0; index < deny.Length; index++) Require(text.IndexOf(deny[index], StringComparison.Ordinal) < 0, "Plan identity denylist", ref assertions);
        }

        private static void ExpectFailure(Action action, string label, ref int assertions)
        {
            bool failed = false;
            try { action(); } catch { failed = true; }
            Require(failed, label, ref assertions);
        }

        private static void Require(bool value, string label, ref int assertions)
        {
            if (!value) throw new InvalidOperationException("Validation assertion failed: " + label);
            assertions++;
        }

        private static string Full(string root, string relative) { return Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))); }
        private static string Sha256File(string path) { using (FileStream stream = File.OpenRead(path)) using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(stream)); }
        private static string Sha256Bytes(byte[] value) { using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(value)); }
        private static string Hex(byte[] value) { StringBuilder builder = new StringBuilder(value.Length * 2); for (int index = 0; index < value.Length; index++) builder.Append(value[index].ToString("x2", CultureInfo.InvariantCulture)); return builder.ToString(); }
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
            public string custodyCommitmentSha256;
            public bool all1536AnonymousSamplesBound;
            public int representativeDesignCellsPrepared;
            public bool custodyPlaintextPersisted;
            public bool productionIdentityWritten;
            public bool traceRoundTripPassed;
            public bool plannerInvokedByTraceVerification;
            public bool m1ThroughM5Produced;
            public bool measuredRootCreated;
            public bool collectionAuthorized;
        }
    }
}
