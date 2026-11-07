using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14Re.V2;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate14ReFormalValidationCommandV1
    {
        private const string OutputRelativeDirectory = "Research/Verification/Gate14Re/formal-executor-implementation-attempt-001/synthetic-validation-only-attempt-003";
        private const string PlanRelativePath = "Research/Gate14Re/Execution/Gate14Re_Formal_Block_Plan.v1.json";

        private static readonly string[][] WilliamsLabels =
        {
            new[] { "A", "B", "D", "C" },
            new[] { "B", "C", "A", "D" },
            new[] { "C", "D", "B", "A" },
            new[] { "D", "A", "C", "B" }
        };

        private static readonly string[][] WilliamsIds =
        {
            new[] { "A*-R", "D*L", "IDFF", "C-FF" },
            new[] { "D*L", "C-FF", "A*-R", "IDFF" },
            new[] { "C-FF", "IDFF", "D*L", "A*-R" },
            new[] { "IDFF", "A*-R", "C-FF", "D*L" }
        };

        public static void Run()
        {
            int assertions = 0;
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string outputDirectory = Full(projectRoot, OutputRelativeDirectory);
            string receiptPath = Path.Combine(outputDirectory, "validation-receipt.v1.json");
            string failurePath = Path.Combine(outputDirectory, "failure-receipt.v1.json");
            Directory.CreateDirectory(outputDirectory);

            try
            {
                ValidateFrozenBindings(projectRoot, ref assertions);
                ValidatePlan(projectRoot, ref assertions);
                ValidateM2Math(ref assertions);
                ValidateM4Math(ref assertions);
                ValidateSyntheticSerialization(ref assertions);
                ValidateNoFormalState(projectRoot, ref assertions);

                ValidationReceipt receipt = new ValidationReceipt
                {
                    schema = "gate14re-formal-executor-synthetic-validation-receipt-v1",
                    studyId = "Gate14Re",
                    status = "PASS",
                    assertions = assertions,
                    frozenBlocksValidated = 1536,
                    frozenDesignCellsValidated = 32,
                    movementBlocks = 768,
                    m4Blocks = 768,
                    checks = new[]
                    {
                        "frozen_design_plan_contract_schema_and_source_bindings",
                        "1536_unique_contiguous_blocks",
                        "32_cells_B48_and_Williams_12_per_row",
                        "module_condition_N_lane_and_scenario_bindings",
                        "M2_common_mask_positive_and_insufficient_cases",
                        "M4_1800_interval_median_and_nearest_rank_P95",
                        "invalid_frame_interval_fail_closed",
                        "synthetic_output_serialization_only",
                        "no_formal_authorization_root_or_observation"
                    },
                    realScenarioOutcomeRead = false,
                    realScenarioOutcomeWritten = false,
                    formalRootCreated = false,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                WriteJson(receiptPath, receipt);
                if (File.Exists(failurePath)) File.Delete(failurePath);
                Debug.Log("Gate 14Re formal executor synthetic validation PASS: " + assertions.ToString(CultureInfo.InvariantCulture));
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                ValidationFailure failure = new ValidationFailure
                {
                    schema = "gate14re-formal-executor-synthetic-validation-failure-v1",
                    studyId = "Gate14Re",
                    status = "FAIL_CLOSED",
                    assertionsCompleted = assertions,
                    exceptionType = exception.GetType().FullName,
                    message = exception.Message,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                WriteJson(failurePath, failure);
                Debug.LogException(exception);
                EditorApplication.Exit(1);
            }
        }

        private static void ValidateFrozenBindings(string root, ref int assertions)
        {
            Require(root, "Research/Gate14Re/Gate14Re_Experiment_Plan.v2.md", 13845L, "cbeca6d175500770357d1a610149abda58c816547d2c19cfa2e8ce9bebf5771f", true, ref assertions);
            Require(root, "Research/Gate14Re/Gate14Re_Design_Contract.v2.json", 17035L, "8b0e064036b8ffac8d0e0572a93898ec8ea72b4e1898b31e21de70ce417e797f", true, ref assertions);
            Require(root, "Research/Gate14Re/Gate14Re_Experiment_Plan.v3.md", 4437L, "3ea4bcf824b5e83c1be3d98ae96590c58dc444555388b301675a3e91d27bedcc", true, ref assertions);
            Require(root, "Research/Gate14Re/Gate14Re_Design_Contract.v3.json", 4117L, "88c3119e0b6dbbe4d1a3a2a95bd04d619e3d68edbd38b0903c6d4037a4d0e1f3", true, ref assertions);
            Require(root, PlanRelativePath, 1169554L, "9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d", true, ref assertions);
            Require(root, "Research/Gate14Re/Execution/Gate14Re_Formal_Execution_Contract.v1.json", 3232L, "ef73091a360e62e370eddc7d17e88ea8dd1e075dd490f915578bf3920ee9e579", true, ref assertions);
            Require(root, "Research/Gate14Re/Execution/Gate14Re_Formal_Block_Output_Schema.v1.json", 5034L, "46dbf0d779cd99ea0b54c761ad198161c395679cc562a7cc4f7454cd01bd6a88", true, ref assertions);
            Require(root, "Research/Gate14Re/Execution/Gate14Re_Formal_Execution_Contract.v2.json", 3989L, "6309d031e00fcf53380e74343adff5863c88aa1c11cb72542cd352a2f19c2bd3", true, ref assertions);
            Require(root, "Research/Gate14Re/Execution/Gate14Re_Formal_Block_Output_Schema.v2.json", 5236L, "0c248a4046df959bae078f360ba5d4dfc322d603dc0bdd8e920b492db11325c2", true, ref assertions);
            Require(root, "Assets/_Scripts/Research/Gate14Re/v2/Gate14ReFormalContractsV1.cs", 5770L, "2178e166eb13df8df824259de5e3348d71ae466ece7dc2a5c1f23061f79214a7", false, ref assertions);
            Require(root, "Assets/_Scripts/Research/Gate14Re/v2/Gate14ReFormalControllerV1.cs", 39278L, "d1f694dfec3853f58ff2964fc2c7615b06fb2eb669c5293305721e9d1927635b", false, ref assertions);
            Require(root, "Assets/_Scripts/Research/Gate14Re/v2/Gate14ReFormalMathV1.cs", 3827L, "d9182cbb2ac5054345785ce8311d39896a897a7b222142453c9040d87fe13cac", false, ref assertions);
            Require(root, "Assets/_Scripts/Research/Editor/Gate14ReFormalBuildCommandV1.cs", 7014L, "c5af0e46f33518e73ba57aa58b64db45faefc35a0038c54d9dfd589e5ab6dd85", false, ref assertions);
        }

        private static void ValidatePlan(string root, ref int assertions)
        {
            string planPath = Full(root, PlanRelativePath);
            Gate14ReFormalPlanV1 plan = JsonUtility.FromJson<Gate14ReFormalPlanV1>(File.ReadAllText(planPath, Encoding.UTF8));
            Assert(plan != null && plan.schema == "gate14re-formal-block-plan-v1" && plan.studyId == "Gate14Re" && plan.version == 1 && plan.status == "FROZEN_NONEXECUTING", "Plan header", ref assertions);
            Assert(plan.fixedB == 48 && plan.plannedValidProcesses == 1536 && plan.blocks != null && plan.blocks.Length == 1536, "Plan cardinality", ref assertions);

            HashSet<string> blockIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<int> sequences = new HashSet<int>();
            Dictionary<string, int[]> cells = new Dictionary<string, int[]>(StringComparer.Ordinal);
            Dictionary<string, string> scenarioHashes = new Dictionary<string, string>(StringComparer.Ordinal);
            int main = 0;
            int quantity = 0;
            int movement = 0;
            int m4 = 0;

            for (int index = 0; index < plan.blocks.Length; index++)
            {
                Gate14ReFormalBlockV1 block = plan.blocks[index];
                Assert(block.sequence == index + 1 && sequences.Add(block.sequence), "Contiguous unique sequence", ref assertions);
                Assert(!string.IsNullOrWhiteSpace(block.blockId) && blockIds.Add(block.blockId), "Unique block id", ref assertions);
                Assert(block.blockIndex >= 1 && block.blockIndex <= 48 && block.williamsRow == ((block.blockIndex - 1) % 4) + 1, "Block/Williams index", ref assertions);
                Assert(block.maximumWholeBlockReplacements == 1, "Replacement maximum", ref assertions);
                Assert(OrderEquals(block.algorithmLabelsInOrder, WilliamsLabels[block.williamsRow - 1]) && OrderEquals(block.algorithmIdsInOrder, WilliamsIds[block.williamsRow - 1]), "Williams order binding", ref assertions);
                Assert(block.lane == "movement" || block.lane == "m4", "Lane", ref assertions);
                Assert(block.module == "A" || block.module == "Q", "Module", ref assertions);
                if (block.module == "A")
                {
                    main++;
                    Assert(block.unitCount == 128, "Main N=128", ref assertions);
                }
                else
                {
                    quantity++;
                    Assert((block.conditionId == "C01" || block.conditionId == "C07") && (block.unitCount == 1 || block.unitCount == 8 || block.unitCount == 32 || block.unitCount == 512), "Quantity anchor/N", ref assertions);
                }
                if (block.lane == "movement") movement++; else m4++;

                string cell = block.module + "|" + block.conditionId + "|" + block.unitCount.ToString(CultureInfo.InvariantCulture) + "|" + block.lane;
                int[] rows;
                if (!cells.TryGetValue(cell, out rows))
                {
                    rows = new int[4];
                    cells.Add(cell, rows);
                }
                rows[block.williamsRow - 1]++;

                string scenarioPath = Full(root, block.scenarioRelativePath);
                string cached;
                if (!scenarioHashes.TryGetValue(scenarioPath, out cached))
                {
                    FileInfo info = new FileInfo(scenarioPath);
                    Assert(info.Exists && info.Length == block.scenarioBytes, "Scenario bytes", ref assertions);
                    cached = Sha256File(scenarioPath);
                    scenarioHashes.Add(scenarioPath, cached);
                }
                Assert(cached == block.scenarioSha256, "Scenario SHA", ref assertions);
            }
            Assert(blockIds.Count == 1536 && sequences.Count == 1536, "Plan uniqueness", ref assertions);
            Assert(main == 768 && quantity == 768 && movement == 768 && m4 == 768, "Module/lane totals", ref assertions);
            Assert(cells.Count == 32, "Design-cell count", ref assertions);
            foreach (KeyValuePair<string, int[]> cell in cells)
            {
                for (int row = 0; row < 4; row++) Assert(cell.Value[row] == 12, "Williams row 12 uses in " + cell.Key, ref assertions);
            }

            string original = plan.blocks[0].algorithmIdsInOrder[0];
            plan.blocks[0].algorithmIdsInOrder[0] = "tampered";
            Assert(!OrderEquals(plan.blocks[0].algorithmIdsInOrder, WilliamsIds[plan.blocks[0].williamsRow - 1]), "Tampered order negative", ref assertions);
            plan.blocks[0].algorithmIdsInOrder[0] = original;
        }

        private static void ValidateM2Math(ref int assertions)
        {
            Gate14ReMovementAlgorithmRawV1[] samples = new Gate14ReMovementAlgorithmRawV1[4];
            for (int algorithm = 0; algorithm < 4; algorithm++)
            {
                samples[algorithm] = new Gate14ReMovementAlgorithmRawV1 { units = new Gate14ReUnitRawV1[5] };
                for (int unit = 0; unit < 5; unit++)
                {
                    samples[algorithm].units[unit] = new Gate14ReUnitRawV1
                    {
                        agentId = unit,
                        arrived = !(algorithm == 2 && unit == 3),
                        cumulativeHorizontalPathLength = 10d * algorithm + unit
                    };
                }
            }
            int[] mask = Gate14ReFormalMathV1.ComputeAndApplyCommonM2Mask(samples, 4);
            Assert(mask.Length == 4 && mask[0] == 0 && mask[1] == 1 && mask[2] == 2 && mask[3] == 4, "M2 common mask", ref assertions);
            Assert(samples[0].m2CommonMaskSufficient && Math.Abs(samples[0].m2CommonMaskMeanPathLength - 1.75d) < 1e-12d, "M2 common mean", ref assertions);
            mask = Gate14ReFormalMathV1.ComputeAndApplyCommonM2Mask(samples, 5);
            Assert(mask.Length == 4 && !samples[0].m2CommonMaskSufficient && samples[0].m2CommonMaskMeanPathLength == -1d, "M2 insufficient missing sentinel", ref assertions);
        }

        private static void ValidateM4Math(ref int assertions)
        {
            double[] raw = new double[1800];
            for (int index = 0; index < raw.Length; index++) raw[index] = (index + 1d) / 1000000d;
            double median;
            double p95;
            Gate14ReFormalMathV1.SummarizeFrameIntervals(raw, out median, out p95);
            Assert(Math.Abs(median - 0.0009005d) < 1e-15d, "M4 median", ref assertions);
            Assert(Math.Abs(p95 - 0.001710d) < 1e-15d, "M4 nearest-rank P95", ref assertions);
            ExpectFailure(() => Gate14ReFormalMathV1.SummarizeFrameIntervals(new double[1799], out median, out p95), "M4 wrong cardinality", ref assertions);
            raw[4] = 0d;
            ExpectFailure(() => Gate14ReFormalMathV1.SummarizeFrameIntervals(raw, out median, out p95), "M4 zero interval", ref assertions);
        }

        private static void ValidateSyntheticSerialization(ref int assertions)
        {
            Gate14ReFormalBlockOutputV1 output = new Gate14ReFormalBlockOutputV1
            {
                schema = "gate14re-formal-block-output-v2",
                studyId = "Gate14Re",
                status = "COMPLETE",
                blockId = "SYNTHETIC-NOT-A-REAL-BLOCK",
                lane = "movement",
                planSha256 = "9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d",
                executableSha256 = new string('0', 64),
                assemblyCSharpSha256 = new string('1', 64),
                buildReceiptSha256 = new string('2', 64),
                authorizationId = "synthetic",
                m2CommonMaskAgentIds = new[] { 0 },
                movement = new Gate14ReMovementAlgorithmRawV1[4],
                m4 = new Gate14ReM4AlgorithmRawV1[0],
                completeFourAlgorithmBlock = true,
                formalObservationProduced = true,
                formalPhaseA = true
            };
            for (int index = 0; index < 4; index++) output.movement[index] = new Gate14ReMovementAlgorithmRawV1 { algorithmLabel = WilliamsLabels[0][index], productionAlgorithmId = WilliamsIds[0][index], units = new Gate14ReUnitRawV1[0], structuralEvents = new Gate14ReStructuralEventRawV1[0], m5CriticalViolationCodes = new string[0] };
            string json = JsonUtility.ToJson(output, false);
            Assert(json.Contains("gate14re-formal-block-output-v2") && json.Contains("SYNTHETIC-NOT-A-REAL-BLOCK") && json.Contains("\"assemblyCSharpSha256\":\"1111111111111111111111111111111111111111111111111111111111111111\"") && json.Contains("\"buildReceiptSha256\":\"2222222222222222222222222222222222222222222222222222222222222222\"") && json.Contains("\"formalObservationProduced\":true"), "Synthetic serialization with full build identity", ref assertions);
        }

        private static void ValidateNoFormalState(string root, ref int assertions)
        {
            Assert(!Directory.Exists(Full(root, "Research/FormalRuns/Gate14Re")), "No formal measured root", ref assertions);
            Assert(!Directory.Exists(Full(root, "Research/Analysis/Gate14Re")), "No formal analysis root", ref assertions);
            Assert(!File.Exists(Full(root, "Research/Gate14Re/Execution/Gate14Re_Formal_PhaseA_Authorization.v1.json")), "No formal authorization receipt", ref assertions);
            Assert(!File.Exists(Full(root, "Research/Gate14Re/Execution/Gate14Re_Formal_PhaseA_Authorization.v2.json")), "No v2 formal authorization receipt", ref assertions);
        }

        private static bool OrderEquals(string[] actual, string[] expected)
        {
            if (actual == null || expected == null || actual.Length != expected.Length) return false;
            for (int index = 0; index < actual.Length; index++) if (actual[index] != expected[index]) return false;
            return true;
        }

        private static void Require(string root, string relative, long bytes, string sha, bool readOnly, ref int assertions)
        {
            string path = Full(root, relative);
            FileInfo info = new FileInfo(path);
            Assert(info.Exists && info.Length == bytes, "File binding bytes: " + relative, ref assertions);
            Assert(Sha256File(path) == sha, "File binding SHA: " + relative, ref assertions);
            if (readOnly) Assert((info.Attributes & FileAttributes.ReadOnly) != 0, "File ReadOnly: " + relative, ref assertions);
        }

        private static void ExpectFailure(Action action, string message, ref int assertions)
        {
            bool rejected = false;
            try { action(); }
            catch { rejected = true; }
            Assert(rejected, message, ref assertions);
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static string Full(string root, string relative)
        {
            return Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static void WriteJson(string path, object value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        [Serializable]
        private sealed class ValidationReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public int assertions;
            public int frozenBlocksValidated;
            public int frozenDesignCellsValidated;
            public int movementBlocks;
            public int m4Blocks;
            public string[] checks;
            public bool realScenarioOutcomeRead;
            public bool realScenarioOutcomeWritten;
            public bool formalRootCreated;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }

        [Serializable]
        private sealed class ValidationFailure
        {
            public string schema;
            public string studyId;
            public string status;
            public int assertionsCompleted;
            public string exceptionType;
            public string message;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }
    }
}
