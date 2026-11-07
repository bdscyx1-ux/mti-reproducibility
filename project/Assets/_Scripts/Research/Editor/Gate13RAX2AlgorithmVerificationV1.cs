using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate13RAX2AlgorithmVerificationV1
    {
        private const string RunId = "gate13r-ax2-validation-v1";
        private const string GoalSetId = "gate13r-ax2-validation-goals-v1";

        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int bidirectionalStaticCases;
            public int lifelongStaticCases;
            public int lifelongDynamicCases;
            public int gate13RScenarioIntegrationAlgorithms;
            public string error;
        }

        public static void Run()
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string outputDirectory = Path.Combine(projectRoot, "Research", "Verification", "Gate13R-AX2", "algorithm-correctness-v1");
            string outputPath = Path.Combine(outputDirectory, "algorithm-correctness.v1.json");
            Directory.CreateDirectory(outputDirectory);
            VerificationResult result = new VerificationResult();
            try
            {
                int assertions = 0;
                TestIdentitiesAndContracts(ref assertions);
                TestBidirectionalAStarAgainstAStar(result, ref assertions);
                TestLifelongPlanningAStarAgainstAStar(result, ref assertions);
                TestGate13RScenarioIntegration(projectRoot, result, ref assertions);
                result.assertionCount = assertions;
                result.passed = true;
                result.error = string.Empty;
                File.WriteAllText(outputPath, JsonUtility.ToJson(result, true));
                Debug.Log("Gate 13R-AX2 algorithm verification passed with " + assertions + " assertions.");
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.error = exception.ToString();
                File.WriteAllText(outputPath, JsonUtility.ToJson(result, true));
                Debug.LogException(exception);
                throw;
            }
        }

        private static void TestIdentitiesAndContracts(ref int assertions)
        {
            Assert(new BidirectionalAStarRepeatedPlanner().AlgorithmId == NavigationAlgorithmIds.BidirectionalAStarRepeated, "BiA*-R identity mismatch.", ref assertions);
            Assert(new LifelongPlanningAStarPlanner().AlgorithmId == NavigationAlgorithmIds.LifelongPlanningAStar, "LPA* identity mismatch.", ref assertions);
            Assert(new BidirectionalAStarRepeatedPlanner().Capabilities == NavigationPlannerCapabilities.FullRecompute, "BiA*-R capabilities mismatch.", ref assertions);
            Assert(new LifelongPlanningAStarPlanner().Capabilities == (NavigationPlannerCapabilities.PerAgentState | NavigationPlannerCapabilities.IncrementalRepair), "LPA* capabilities mismatch.", ref assertions);

            Assert(PlanningFairnessContracts.AuthorizedProfiles.Count == 4,
                "Gate 10/Gate 13R authorized-profile registry was changed by AX2.", ref assertions);
            string[] originalAlgorithms = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(PlanningFairnessContracts.FourAlgorithmSharedGoalCohort);
            Assert(originalAlgorithms.Length == 4 &&
                   originalAlgorithms[0] == NavigationAlgorithmIds.AStarRepeated &&
                   originalAlgorithms[1] == NavigationAlgorithmIds.DStarLite &&
                   originalAlgorithms[2] == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField &&
                   originalAlgorithms[3] == NavigationAlgorithmIds.IncrementalDynamicFlowField,
                   "Original Gate 10/Gate 13R shared-goal cohort changed by AX2.", ref assertions);

            string[] algorithms = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(PlanningFairnessContracts.Gate13RAX2SharedGoalCohort);
            Assert(algorithms.Length == 4, "AX2 cohort is not a four-treatment cohort.", ref assertions);
            Assert(algorithms[0] == NavigationAlgorithmIds.BidirectionalAStarRepeated &&
                   algorithms[1] == NavigationAlgorithmIds.LifelongPlanningAStar &&
                   algorithms[2] == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField &&
                   algorithms[3] == NavigationAlgorithmIds.IncrementalDynamicFlowField,
                   "AX2 cohort order mismatch.", ref assertions);
        }

        private static void TestBidirectionalAStarAgainstAStar(VerificationResult result, ref int assertions)
        {
            NavigationGridConnectivity[] connectivities =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] cornerPolicies = { false, false, true };
            uint state = 0x8f31a7c5u;
            int cases = 0;
            for (int topology = 0; topology < connectivities.Length; topology++)
            {
                for (int caseIndex = 0; caseIndex < 20; caseIndex++)
                {
                    const int width = 8;
                    const int height = 7;
                    GridCoordinate start = new GridCoordinate(0, 0);
                    GridCoordinate goal = new GridCoordinate(width - 1, height - 1);
                    ResearchNavigationGrid grid = RandomGrid(width, height, start, goal, ref state);
                    INavigationPlanner oracle = Initialize(new AStarRepeatedPlanner(), grid, connectivities[topology], cornerPolicies[topology], goal);
                    INavigationPlanner candidate = Initialize(new BidirectionalAStarRepeatedPlanner(), grid, connectivities[topology], cornerPolicies[topology], goal);
                    NavigationPlanResult expected = oracle.Plan(Request(grid, 0, start, goal, "bia-oracle-" + topology + "-" + caseIndex));
                    NavigationPlanResult actual = candidate.Plan(Request(grid, 0, start, goal, "bia-candidate-" + topology + "-" + caseIndex));
                    AssertEquivalent(grid, expected, actual, connectivities[topology], cornerPolicies[topology], "BiA*-R static case", ref assertions);

                    NavigationPlanResult repeated = candidate.Plan(Request(grid, 0, start, goal, "bia-repeat-" + topology + "-" + caseIndex));
                    Assert(PathsEqual(actual.Path, repeated.Path), "BiA*-R path is not deterministic.", ref assertions);
                    oracle.Reset();
                    candidate.Reset();
                    cases++;
                }
            }
            result.bidirectionalStaticCases = cases;
            Assert(cases == 60, "BiA*-R static case count mismatch.", ref assertions);
        }

        private static void TestLifelongPlanningAStarAgainstAStar(VerificationResult result, ref int assertions)
        {
            NavigationGridConnectivity[] connectivities =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] cornerPolicies = { false, false, true };
            uint state = 0x3bd92e61u;
            int staticCases = 0;
            int dynamicCases = 0;
            for (int topology = 0; topology < connectivities.Length; topology++)
            {
                for (int caseIndex = 0; caseIndex < 12; caseIndex++)
                {
                    const int width = 8;
                    const int height = 7;
                    GridCoordinate start = new GridCoordinate(0, 0);
                    GridCoordinate goal = new GridCoordinate(width - 1, height - 1);
                    ResearchNavigationGrid grid = RandomGrid(width, height, start, goal, ref state);
                    INavigationPlanner oracle = Initialize(new AStarRepeatedPlanner(), grid, connectivities[topology], cornerPolicies[topology], goal);
                    INavigationPlanner candidate = Initialize(new LifelongPlanningAStarPlanner(), grid, connectivities[topology], cornerPolicies[topology], goal);
                    NavigationPlanResult expected = oracle.Plan(Request(grid, 0, start, goal, "lpa-oracle-initial-" + topology + "-" + caseIndex));
                    NavigationPlanResult actual = candidate.Plan(Request(grid, 0, start, goal, "lpa-candidate-initial-" + topology + "-" + caseIndex));
                    AssertEquivalent(grid, expected, actual, connectivities[topology], cornerPolicies[topology], "LPA* initial case", ref assertions);
                    staticCases++;

                    NavigationPlanResult repeated = candidate.Plan(Request(grid, 0, start, goal, "lpa-repeat-" + topology + "-" + caseIndex));
                    Assert(PathsEqual(actual.Path, repeated.Path), "LPA* fixed-state path is not deterministic.", ref assertions);

                    for (int changeIndex = 0; changeIndex < 3; changeIndex++)
                    {
                        int x = 1 + ((caseIndex + (changeIndex * 2)) % (width - 2));
                        int y = 1 + ((topology + caseIndex + changeIndex) % (height - 2));
                        GridCoordinate coordinate = new GridCoordinate(x, y);
                        bool walkable = (Next(ref state) % 5u) != 0u;
                        float cost = 0.5f + ((Next(ref state) % 11u) * 0.25f);
                        NavigationChangeSet changeSet = grid.ApplyChanges(
                            "lpa-change-" + topology + "-" + caseIndex + "-" + changeIndex,
                            grid.Version,
                            new[] { Change(coordinate.x, coordinate.y, walkable, cost) });
                        NavigationRepairResult oracleRepair = oracle.ApplyChanges(changeSet, 5000d);
                        NavigationRepairResult candidateRepair = candidate.ApplyChanges(changeSet, 5000d);
                        Assert(oracleRepair.Status == NavigationPlanStatus.Succeeded, "A*-R oracle failed to accept a dynamic change.", ref assertions);
                        Assert(candidateRepair.Status == NavigationPlanStatus.Succeeded, "LPA* repair failed.", ref assertions);
                        expected = oracle.Plan(Request(grid, 0, start, goal, "lpa-oracle-dynamic-" + topology + "-" + caseIndex + "-" + changeIndex));
                        actual = candidate.Plan(Request(grid, 0, start, goal, "lpa-candidate-dynamic-" + topology + "-" + caseIndex + "-" + changeIndex));
                        AssertEquivalent(grid, expected, actual, connectivities[topology], cornerPolicies[topology], "LPA* dynamic case", ref assertions);
                        dynamicCases++;
                    }

                    NavigationPlanResult movedStart = candidate.Plan(Request(grid, 0, goal, goal, "lpa-moved-start-" + topology + "-" + caseIndex));
                    Assert(movedStart.Status == NavigationPlanStatus.InvalidRequest, "LPA* accepted a changed start for an existing fixed-start agent.", ref assertions);
                    oracle.Reset();
                    candidate.Reset();
                }
            }
            result.lifelongStaticCases = staticCases;
            result.lifelongDynamicCases = dynamicCases;
            Assert(staticCases == 36 && dynamicCases == 108, "LPA* verification case counts mismatch.", ref assertions);
        }

        private static void TestGate13RScenarioIntegration(string projectRoot, VerificationResult result, ref int assertions)
        {
            string relativeScenario = "Research/FormalScenarios/Gate11R_5pct/v1/Scenarios/core-r01-s1-shared.scenario.json";
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(Path.Combine(projectRoot, relativeScenario));
            INavigationPlanner[] planners =
            {
                new BidirectionalAStarRepeatedPlanner(),
                new LifelongPlanningAStarPlanner(),
                new CorrectedFullRecomputeFlowFieldPlanner(),
                new IncrementalDynamicFlowFieldPlanner()
            };
            for (int index = 0; index < planners.Length; index++)
            {
                INavigationPlanner planner = planners[index];
                PlanningRunProvenance provenance = BuildProvenance(projectRoot, planner.AlgorithmId);
                PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run(
                    "g13rax2-validation-" + index,
                    loaded.Definition,
                    planner,
                    null,
                    provenance);
                Assert(workload.completed, "Gate 13R scenario integration did not complete for " + planner.AlgorithmId + ".", ref assertions);
                Assert(workload.failedPlanCount == 0 && workload.invalidPlanCount == 0 && workload.budgetExceededOperationCount == 0, "Gate 13R scenario integration had failed/invalid/budget operations for " + planner.AlgorithmId + ".", ref assertions);
                Assert(workload.scheduledEventCount > 0 && workload.dynamicHandlingMillisecondsPerScheduledEvent > 0d, "Gate 13R scenario integration did not produce a positive P1 for " + planner.AlgorithmId + ".", ref assertions);
                Assert(workload.comparisonCohortId == PlanningFairnessContracts.Gate13RAX2SharedGoalCohort && workload.distinctGoalCount == 1, "Gate 13R-AX2 fairness classification mismatch for " + planner.AlgorithmId + ".", ref assertions);
            }
            result.gate13RScenarioIntegrationAlgorithms = planners.Length;
            Assert(planners.Length == 4, "Gate 13R scenario integration did not exercise four algorithms.", ref assertions);
        }

        private static PlanningRunProvenance BuildProvenance(string projectRoot, string algorithmId)
        {
            PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
            PlanningRunProvenance provenance = new PlanningRunProvenance
            {
                fairnessProtocolId = PlanningFairnessContracts.Gate13RAX2FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.Gate13RAX2FairnessProtocolRelativePath,
                fairnessProtocolSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.Gate13RAX2FairnessProtocolRelativePath),
                algorithmId = algorithmId,
                algorithmSpecificationId = profile.SpecificationId,
                algorithmSpecificationRelativePath = profile.SpecificationRelativePath,
                algorithmSpecificationSha256 = HashProjectFile(projectRoot, profile.SpecificationRelativePath),
                algorithmImplementationRelativePath = profile.ImplementationRelativePath,
                algorithmImplementationSha256 = HashProjectFile(projectRoot, profile.ImplementationRelativePath),
                workloadSpecificationId = PlanningFairnessContracts.WorkloadSpecificationId,
                workloadSpecificationRelativePath = PlanningFairnessContracts.WorkloadSpecificationRelativePath,
                workloadSpecificationSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.WorkloadSpecificationRelativePath)
            };
            PlanningFairnessContracts.ValidateProvenance(provenance, algorithmId);
            return provenance;
        }

        private static string HashProjectFile(string projectRoot, string relativePath)
        {
            string fullPath = Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar));
            using (SHA256 algorithm = SHA256.Create())
            using (FileStream stream = File.OpenRead(fullPath))
            {
                return BitConverter.ToString(algorithm.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static ResearchNavigationGrid RandomGrid(
            int width,
            int height,
            GridCoordinate start,
            GridCoordinate goal,
            ref uint state)
        {
            List<NavigationGridChange> cells = new List<NavigationGridChange>();
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    bool endpoint = coordinate.Equals(start) || coordinate.Equals(goal);
                    bool walkable = endpoint || (Next(ref state) % 100u) >= 23u;
                    float cost = 0.5f + ((Next(ref state) % 13u) * 0.25f);
                    cells.Add(Change(x, y, walkable, cost));
                }
            }
            return new ResearchNavigationGrid(width, height, 1f, cells);
        }

        private static INavigationPlanner Initialize(
            INavigationPlanner planner,
            IReadOnlyNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            GridCoordinate goal)
        {
            planner.Initialize(grid, new NavigationPlannerInitialization
            {
                runId = RunId,
                goalSetId = GoalSetId,
                goals = new[] { goal },
                connectivity = connectivity,
                allowDiagonalCornerCutting = cornerCutting,
                budgetMilliseconds = 5000d
            });
            return planner;
        }

        private static NavigationPlanRequest Request(
            IReadOnlyNavigationGrid grid,
            int agentId,
            GridCoordinate start,
            GridCoordinate goal,
            string requestId)
        {
            return new NavigationPlanRequest
            {
                runId = RunId,
                requestId = requestId,
                goalSetId = GoalSetId,
                agentId = agentId,
                start = start,
                goal = goal,
                expectedGridVersion = grid.Version,
                budgetMilliseconds = 5000d
            };
        }

        private static void AssertEquivalent(
            IReadOnlyNavigationGrid grid,
            NavigationPlanResult expected,
            NavigationPlanResult actual,
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            string label,
            ref int assertions)
        {
            Assert(actual.Status == expected.Status && actual.FailureReason == expected.FailureReason, label + " status differs from A*-R oracle.", ref assertions);
            if (expected.Status != NavigationPlanStatus.Succeeded)
            {
                Assert(actual.Path.Count == 0, label + " returned a path for a non-success result.", ref assertions);
                return;
            }
            Assert(IsValidPath(grid, actual.Path, connectivity, cornerCutting), label + " returned an invalid path.", ref assertions);
            double expectedCost = PathCost(grid, expected.Path);
            double actualCost = PathCost(grid, actual.Path);
            Assert(Math.Abs(expectedCost - actualCost) < 1e-8d, label + " path cost differs from A*-R oracle.", ref assertions);
        }

        private static bool IsValidPath(
            IReadOnlyNavigationGrid grid,
            IReadOnlyList<GridCoordinate> path,
            NavigationGridConnectivity connectivity,
            bool cornerCutting)
        {
            if (path == null || path.Count == 0) return false;
            for (int index = 0; index < path.Count; index++)
            {
                if (!grid.Contains(path[index]) || !grid.IsWalkable(path[index])) return false;
                if (index == 0) continue;
                GridCoordinate from = path[index - 1];
                GridCoordinate to = path[index];
                int dx = Math.Abs(to.x - from.x);
                int dy = Math.Abs(to.y - from.y);
                if (dx > 1 || dy > 1 || dx + dy == 0) return false;
                if (connectivity == NavigationGridConnectivity.FourWay && dx + dy != 1) return false;
                if (dx == 1 && dy == 1 && !cornerCutting)
                {
                    if (!grid.IsWalkable(new GridCoordinate(to.x, from.y)) ||
                        !grid.IsWalkable(new GridCoordinate(from.x, to.y))) return false;
                }
            }
            return true;
        }

        private static double PathCost(IReadOnlyNavigationGrid grid, IReadOnlyList<GridCoordinate> path)
        {
            double total = 0d;
            for (int index = 1; index < path.Count; index++)
            {
                bool diagonal = path[index - 1].x != path[index].x && path[index - 1].y != path[index].y;
                total += grid.GetTraversalCost(path[index]) * (diagonal ? Math.Sqrt(2d) : 1d);
            }
            return total;
        }

        private static bool PathsEqual(IReadOnlyList<GridCoordinate> left, IReadOnlyList<GridCoordinate> right)
        {
            if (left == null || right == null || left.Count != right.Count) return false;
            for (int index = 0; index < left.Count; index++) if (!left[index].Equals(right[index])) return false;
            return true;
        }

        private static NavigationGridChange Change(int x, int y, bool walkable, float cost)
        {
            return new NavigationGridChange
            {
                coordinate = new GridCoordinate(x, y),
                isWalkable = walkable,
                traversalCost = cost
            };
        }

        private static uint Next(ref uint state)
        {
            state = unchecked((state * 1664525u) + 1013904223u);
            return state;
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
