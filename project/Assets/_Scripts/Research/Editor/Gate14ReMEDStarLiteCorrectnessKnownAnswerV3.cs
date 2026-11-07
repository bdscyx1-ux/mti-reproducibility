using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Post-repair exact-input correctness known answer for the C002 bottleneck
    /// sequence. It records structural check counts only, never measured metrics.
    /// </summary>
    public static class Gate14ReMEDStarLiteCorrectnessKnownAnswerV3
    {
        private const string ExpectedInputSha256 = "3fbe00d7a27a75551b9ebb7711ccfcd2a0678679e94c3097b7a00209e7261ff3";
        private const string ExpectedAlgorithmSha256 = "b6938a3389de4764a26ed15c59582dd31017e8b44c38fa004be356989ca8d199";
        private const string ExpectedSpecificationSha256 = "d25ea4cadf6e08b802c51d8b2a3245da8b436d4b1029973bed576d89de34d732";
        private const string ExpectedOracleSha256 = "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25";
        private const string InputRelativePath = "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/inputs/core/G14ME-QSB-C002.input.v2.json";
        private const string OutputRelativePath = "Research/Verification/Gate14Re-ME/qualification-dstar-lite-oracle-correctness-corrigendum-attempt-001/repair-cycle-003-post-repair-known-answer";
        private const string AlgorithmRelativePath = "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs";
        private const string SpecificationRelativePath = "Research/DStar_Lite_Specification.md";
        private const string OracleRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs";

        [Serializable]
        private sealed class KnownAnswerReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public bool passed;
            public string inputRelativePath;
            public string inputSha256;
            public string algorithmSourceRelativePath;
            public string algorithmSourceSha256;
            public string specificationRelativePath;
            public string specificationSha256;
            public string oracleSourceRelativePath;
            public string oracleSourceSha256;
            public int initialQueryChecks;
            public int eventGroupCount;
            public int repairOperationChecks;
            public int postEventQueryChecks;
            public string failedPhase;
            public int failedEventGroupIndex;
            public int failedAgentIndex;
            public string failureKind;
            public string error;
            public string completedAtUtc;
        }

        public static void Run()
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string outputDirectory = Path.Combine(projectRoot, OutputRelativePath.Replace('/', Path.DirectorySeparatorChar));
            Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Known-answer output already exists; overwrite or resume is prohibited.");
            Directory.CreateDirectory(outputDirectory);
            KnownAnswerReceipt receipt = NewReceipt(projectRoot);
            try
            {
                Require(receipt.inputSha256 == ExpectedInputSha256, "Exact known-answer input hash mismatch.");
                Require(receipt.algorithmSourceSha256 == ExpectedAlgorithmSha256, "Post-repair D* Lite source hash mismatch.");
                Require(receipt.specificationSha256 == ExpectedSpecificationSha256, "Post-repair D* Lite specification hash mismatch.");
                Require(receipt.oracleSourceSha256 == ExpectedOracleSha256, "Reference oracle source hash mismatch.");

                string inputPath = Path.Combine(projectRoot, InputRelativePath.Replace('/', Path.DirectorySeparatorChar));
                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(File.ReadAllText(inputPath));
                Require(input != null && input.inputId == "G14ME-QI-C002" && input.superblockId == "G14ME-QSB-C002", "Unexpected known-answer input identity.");
                Require(input.eventGroups != null && input.eventGroups.Length == 24 && input.starts != null && input.starts.Length == 8, "Known-answer input cardinality mismatch.");

                ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
                DStarLitePlanner planner = new DStarLitePlanner();
                const string lane = "ALG-D-CORRECTNESS-KNOWN-ANSWER-V3";
                planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = input.inputId + ":" + lane,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = 600000d
                });

                Gate14ReMEOraclePathV1[] initialOracle = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                {
                    NavigationPlanResult plan = planner.Plan(CreateRequest(input, lane, agentIndex, grid.Version, "initial"));
                    RequireCorrect(grid, initialOracle[agentIndex], plan, receipt, "initial", -1, agentIndex);
                    receipt.initialQueryChecks++;
                }

                for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    receipt.eventGroupCount++;
                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = partition.changes[changeIndex].ToChange();
                        NavigationChangeSet changeSet = grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, 600000d);
                        if (repair.Status != NavigationPlanStatus.Succeeded)
                        {
                            receipt.failedPhase = group.phase;
                            receipt.failedEventGroupIndex = groupIndex;
                            receipt.failedAgentIndex = -1;
                            receipt.failureKind = "REPAIR_STATUS_MISMATCH";
                            throw new InvalidOperationException("Post-repair known-answer repair status mismatch.");
                        }
                        receipt.repairOperationChecks++;
                    }

                    Gate14ReMEOraclePathV1[] oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                        grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                    for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                    {
                        NavigationPlanResult plan = planner.Plan(CreateRequest(input, lane, agentIndex, grid.Version, "g" + groupIndex));
                        RequireCorrect(grid, oracle[agentIndex], plan, receipt, group.phase, groupIndex, agentIndex);
                        receipt.postEventQueryChecks++;
                    }
                }

                receipt.status = "PASS_DSTAR_LITE_C002_ORACLE_CORRECTNESS_KNOWN_ANSWER";
                receipt.passed = true;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
            }
            catch (Exception exception)
            {
                receipt.status = "FAIL_DSTAR_LITE_C002_ORACLE_CORRECTNESS_KNOWN_ANSWER";
                receipt.passed = false;
                receipt.error = exception.GetType().FullName + ": " + exception.Message;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
                throw;
            }
        }

        private static KnownAnswerReceipt NewReceipt(string projectRoot)
        {
            return new KnownAnswerReceipt
            {
                schema = "gate14re-me-dstar-lite-c002-oracle-correctness-known-answer-receipt-v3",
                studyId = "Gate14Re-ME",
                status = "RUNNING",
                inputRelativePath = InputRelativePath,
                inputSha256 = Sha256File(Path.Combine(projectRoot, InputRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                algorithmSourceRelativePath = AlgorithmRelativePath,
                algorithmSourceSha256 = Sha256File(Path.Combine(projectRoot, AlgorithmRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                specificationRelativePath = SpecificationRelativePath,
                specificationSha256 = Sha256File(Path.Combine(projectRoot, SpecificationRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                oracleSourceRelativePath = OracleRelativePath,
                oracleSourceSha256 = Sha256File(Path.Combine(projectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                failedPhase = string.Empty,
                failedEventGroupIndex = -1,
                failedAgentIndex = -1,
                failureKind = string.Empty,
                error = string.Empty,
                completedAtUtc = string.Empty
            };
        }

        private static void RequireCorrect(
            IReadOnlyNavigationGrid grid,
            Gate14ReMEOraclePathV1 oracle,
            NavigationPlanResult plan,
            KnownAnswerReceipt receipt,
            string phase,
            int groupIndex,
            int agentIndex)
        {
            bool correct;
            string failureKind;
            if (oracle.Reachable)
            {
                double cost = ComputePathCost(grid, plan.Path);
                correct = plan.Status == NavigationPlanStatus.Succeeded && cost >= 0d && Gate14ReMEReferenceOracleV1.NearlyEqual(oracle.Cost, cost);
                failureKind = plan.Status == NavigationPlanStatus.Succeeded ? "REACHABLE_PATH_COST_MISMATCH" : "REACHABLE_STATUS_MISMATCH";
            }
            else
            {
                correct = plan.Status == NavigationPlanStatus.NoPath;
                failureKind = "UNREACHABLE_STATUS_MISMATCH";
            }
            if (correct) return;
            receipt.failedPhase = phase;
            receipt.failedEventGroupIndex = groupIndex;
            receipt.failedAgentIndex = agentIndex;
            receipt.failureKind = failureKind;
            throw new InvalidOperationException("Post-repair D* Lite oracle correctness mismatch.");
        }

        private static double ComputePathCost(IReadOnlyNavigationGrid grid, IReadOnlyList<GridCoordinate> path)
        {
            if (path == null || path.Count == 0) return -1d;
            double total = 0d;
            for (int index = 1; index < path.Count; index++)
            {
                GridCoordinate previous = path[index - 1];
                GridCoordinate current = path[index];
                bool diagonal = previous.x != current.x && previous.y != current.y;
                total += grid.GetTraversalCost(current) * (diagonal ? Math.Sqrt(2d) : 1d);
            }
            return total;
        }

        private static NavigationPlanRequest CreateRequest(Gate14ReMEQualificationInputBundleV1 input, string lane, int agentIndex, long version, string phase)
        {
            return new NavigationPlanRequest
            {
                runId = input.inputId + ":" + lane,
                requestId = input.inputId + ":" + lane + ":" + phase + ":agent:" + agentIndex,
                goalSetId = input.inputId + ":shared-goal",
                agentId = agentIndex,
                start = input.starts[agentIndex],
                goal = input.goal,
                expectedGridVersion = version,
                budgetMilliseconds = 600000d
            };
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void WriteReceipt(string outputDirectory, KnownAnswerReceipt receipt)
        {
            File.WriteAllText(Path.Combine(outputDirectory, "known-answer-receipt.v3.json"), JsonUtility.ToJson(receipt, true));
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
