using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate8CorrectedFlowFieldVerification
    {
        private const double Tolerance = 1e-9d;

        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int staticReferenceFieldCount;
            public int dynamicReferenceFieldCount;
            public int comparedCellCount;
            public string deterministicSignatureSha256;
            public long deterministicRebuiltCells;
            public long finalGridVersion;
            public int workloadPlanOperations;
            public int workloadRepairOperations;
            public int committedScenarioPlanOperations;
            public string error;
        }

        private sealed class OracleField
        {
            public readonly double[] integration;
            public readonly bool[] hasOwner;
            public readonly GridCoordinate[] owner;
            public readonly bool[] activeGoal;
            public readonly bool[] hasDirection;
            public readonly GridCoordinate[] next;

            public OracleField(int count)
            {
                integration = new double[count];
                hasOwner = new bool[count];
                owner = new GridCoordinate[count];
                activeGoal = new bool[count];
                hasDirection = new bool[count];
                next = new GridCoordinate[count];
                for (int index = 0; index < count; index++) integration[index] = double.PositiveInfinity;
            }
        }

        private sealed class SequenceSnapshot
        {
            public string signature;
            public long rebuiltCells;
            public long finalVersion;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate8_CorrectedFlowField.json");
            VerificationResult result = new VerificationResult();
            try
            {
                int assertions = 0;
                TestDirectedDestinationCost(ref assertions);
                TestMultiSourceOwnershipAndDirection(ref assertions);
                TestCornerPolicies(ref assertions);
                TestDynamicFullRecompute(ref assertions);
                TestValidationAndLifecycle(ref assertions);
                TestAtomicBudgetBehavior(ref assertions);
                TestGeneratedOracleMatrix(result, ref assertions);
                TestDeterministicSequence(result, ref assertions);
                TestWorkloadIntegration(result, ref assertions);
                TestCommittedScenarioCompatibility(result, ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 8 C-FF verification passed with " + assertions + " assertions.");
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.error = exception.ToString();
                WriteResult(resultPath, result);
                Debug.LogException(exception);
                throw;
            }
        }

        private static void TestDirectedDestinationCost(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(3, 1, 1f, new[]
            {
                Change(0, 0, true, 9f),
                Change(1, 0, true, 2f),
                Change(2, 0, true, 1f)
            });
            GridCoordinate goal = new GridCoordinate(2, 0);
            CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, 1000d, goal);
            Assert(planner.AlgorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, "C-FF algorithm id is incorrect.", ref assertions);
            Assert(planner.Capabilities == (NavigationPlannerCapabilities.SharedGoalField | NavigationPlannerCapabilities.FullRecompute), "C-FF capability flags are incorrect.", ref assertions);
            CorrectedFlowFieldCellSnapshot first = new CorrectedFlowFieldCellSnapshot();
            CorrectedFlowFieldCellSnapshot middle = new CorrectedFlowFieldCellSnapshot();
            Assert(planner.TryGetCellSnapshot(new GridCoordinate(0, 0), out first) && planner.TryGetCellSnapshot(new GridCoordinate(1, 0), out middle), "C-FF snapshots were unavailable.", ref assertions);
            Assert(Math.Abs(middle.IntegrationCost - 1d) < Tolerance, "Reverse relaxation did not use the destination goal cost.", ref assertions);
            Assert(Math.Abs(first.IntegrationCost - 3d) < Tolerance, "Reverse relaxation incorrectly used predecessor traversal cost.", ref assertions);
            NavigationPlanResult plan = planner.Plan(Request(grid, 0, new GridCoordinate(0, 0), goal, "directed", 1000d));
            Assert(plan.Status == NavigationPlanStatus.Succeeded && Math.Abs(PathCost(grid, plan.Path) - 3d) < Tolerance, "Directed-cost plan is incorrect.", ref assertions);
            CompareAllCells(planner, BuildOracle(grid, NavigationGridConnectivity.FourWay, false, new[] { goal }), grid, "directed", ref assertions);
            planner.Reset();
        }

        private static void TestMultiSourceOwnershipAndDirection(ref int assertions)
        {
            ResearchNavigationGrid line = new ResearchNavigationGrid(5, 1);
            GridCoordinate leftGoal = new GridCoordinate(0, 0);
            GridCoordinate rightGoal = new GridCoordinate(4, 0);
            CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(line, NavigationGridConnectivity.FourWay, false, 1000d, rightGoal, leftGoal, rightGoal);
            CorrectedFlowFieldCellSnapshot center;
            Assert(planner.TryGetCellSnapshot(new GridCoordinate(2, 0), out center), "Multi-source center snapshot is missing.", ref assertions);
            Assert(center.Reachable && center.OwnerGoal.Equals(leftGoal), "Equal-cost goal ownership did not choose canonical goal (y,x).", ref assertions);
            Assert(center.HasDirection && center.Next.Equals(new GridCoordinate(1, 0)), "Multi-source direction does not lead to canonical owner.", ref assertions);
            Assert(planner.Plan(Request(line, 0, new GridCoordinate(2, 0), leftGoal, "owner-left", 1000d)).Status == NavigationPlanStatus.Succeeded, "Compatible owner request failed.", ref assertions);
            NavigationPlanResult incompatible = planner.Plan(Request(line, 0, new GridCoordinate(2, 0), rightGoal, "owner-right", 1000d));
            Assert(incompatible.Status == NavigationPlanStatus.InvalidRequest && incompatible.Path.Count == 0, "Incompatible owner request was silently redirected.", ref assertions);
            CompareAllCells(planner, BuildOracle(line, NavigationGridConnectivity.FourWay, false, new[] { rightGoal, leftGoal }), line, "multi-source", ref assertions);
            planner.Reset();

            ResearchNavigationGrid square = new ResearchNavigationGrid(3, 3);
            CorrectedFullRecomputeFlowFieldPlanner tie = Initialize(square, NavigationGridConnectivity.FourWay, false, 1000d, new GridCoordinate(0, 0));
            CorrectedFlowFieldCellSnapshot diagonalCell;
            tie.TryGetCellSnapshot(new GridCoordinate(1, 1), out diagonalCell);
            Assert(diagonalCell.Next.Equals(new GridCoordinate(1, 0)), "Equal direction candidates did not use successor (y,x) order.", ref assertions);
            NavigationPlanResult stationary = tie.Plan(Request(square, 0, new GridCoordinate(0, 0), new GridCoordinate(0, 0), "stationary", 1000d));
            Assert(stationary.Status == NavigationPlanStatus.Succeeded && stationary.Path.Count == 1, "Goal cell did not return a one-cell path.", ref assertions);
            tie.Reset();
        }

        private static void TestCornerPolicies(ref int assertions)
        {
            GridCoordinate start = new GridCoordinate(0, 0);
            GridCoordinate goal = new GridCoordinate(1, 1);
            NavigationGridChange[] blockedCorners =
            {
                Change(1, 0, false, 1f),
                Change(0, 1, false, 1f)
            };
            ResearchNavigationGrid strictGrid = new ResearchNavigationGrid(2, 2, 1f, blockedCorners);
            CorrectedFullRecomputeFlowFieldPlanner strict = Initialize(strictGrid, NavigationGridConnectivity.EightWay, false, 1000d, goal);
            NavigationPlanResult strictPlan = strict.Plan(Request(strictGrid, 0, start, goal, "strict", 1000d));
            Assert(strictPlan.Status == NavigationPlanStatus.NoPath && strictPlan.FailureReason == NavigationFailureReason.NoReachablePath, "Strict C-FF allowed diagonal corner cutting.", ref assertions);
            CompareAllCells(strict, BuildOracle(strictGrid, NavigationGridConnectivity.EightWay, false, new[] { goal }), strictGrid, "strict corner", ref assertions);
            strict.Reset();

            ResearchNavigationGrid permissiveGrid = new ResearchNavigationGrid(2, 2, 1f, blockedCorners);
            CorrectedFullRecomputeFlowFieldPlanner permissive = Initialize(permissiveGrid, NavigationGridConnectivity.EightWay, true, 1000d, goal);
            NavigationPlanResult permissivePlan = permissive.Plan(Request(permissiveGrid, 0, start, goal, "permissive", 1000d));
            Assert(permissivePlan.Status == NavigationPlanStatus.Succeeded && permissivePlan.Path.Count == 2, "Permissive C-FF rejected the legal diagonal.", ref assertions);
            Assert(Math.Abs(PathCost(permissiveGrid, permissivePlan.Path) - Math.Sqrt(2d)) < Tolerance, "Permissive diagonal cost is incorrect.", ref assertions);
            CompareAllCells(permissive, BuildOracle(permissiveGrid, NavigationGridConnectivity.EightWay, true, new[] { goal }), permissiveGrid, "permissive corner", ref assertions);
            permissive.Reset();
        }

        private static void TestDynamicFullRecompute(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(6, 4);
            GridCoordinate firstGoal = new GridCoordinate(5, 0);
            GridCoordinate secondGoal = new GridCoordinate(5, 3);
            GridCoordinate[] goals = { firstGoal, secondGoal };
            CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(grid, NavigationGridConnectivity.EightWay, false, 1000d, goals);
            CompareAllCells(planner, BuildOracle(grid, NavigationGridConnectivity.EightWay, false, goals), grid, "dynamic initial", ref assertions);

            NavigationGridChange[][] batches =
            {
                new[] { Change(2, 1, false, 1f) },
                new[] { Change(2, 1, true, 4f), Change(3, 2, false, 1f) },
                new[] { Change(2, 1, true, 0.5f), Change(3, 2, true, 1f) },
                new[] { Change(0, 3, true, 7f) },
                new[] { Change(5, 0, false, 1f) },
                new[] { Change(5, 0, true, 1f) }
            };
            for (int index = 0; index < batches.Length; index++)
            {
                NavigationChangeSet changeSet = grid.ApplyChanges("full-rebuild-" + index, grid.Version, batches[index]);
                NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1000d);
                Assert(repair.Status == NavigationPlanStatus.Succeeded, "C-FF dynamic rebuild failed at step " + index + ".", ref assertions);
                Assert(repair.Metrics.repairedCells == grid.Width * grid.Height, "C-FF did not report a complete physical-field rebuild.", ref assertions);
                CompareAllCells(planner, BuildOracle(grid, NavigationGridConnectivity.EightWay, false, goals), grid, "dynamic step " + index, ref assertions);
                if (index == 4)
                {
                    NavigationPlanResult blocked = planner.Plan(Request(grid, 0, new GridCoordinate(4, 0), firstGoal, "blocked-goal", 1000d));
                    Assert(blocked.Status == NavigationPlanStatus.NoPath && blocked.FailureReason == NavigationFailureReason.GoalBlocked, "C-FF blocked-goal classification is incorrect.", ref assertions);
                }
            }
            NavigationPlanResult restoredGoal = planner.Plan(Request(grid, 0, new GridCoordinate(4, 0), firstGoal, "restored-goal", 1000d));
            Assert(restoredGoal.Status == NavigationPlanStatus.Succeeded && restoredGoal.Path.Count == 2, "Restored C-FF goal did not become usable again.", ref assertions);
            planner.Reset();
        }

        private static void TestValidationAndLifecycle(ref int assertions)
        {
            bool beforeInitializeThrew = false;
            try { new CorrectedFullRecomputeFlowFieldPlanner().Plan(new NavigationPlanRequest()); }
            catch (InvalidOperationException) { beforeInitializeThrew = true; }
            Assert(beforeInitializeThrew, "C-FF planning before initialization did not throw.", ref assertions);

            ResearchNavigationGrid grid = new ResearchNavigationGrid(4, 3);
            GridCoordinate goal = new GridCoordinate(3, 1);
            CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, 1000d, goal);
            NavigationPlanRequest wrongRun = Request(grid, 0, new GridCoordinate(0, 1), goal, "wrong-run", 1000d);
            wrongRun.runId = "wrong";
            Assert(planner.Plan(wrongRun).Status == NavigationPlanStatus.InvalidRequest, "C-FF accepted a wrong run id.", ref assertions);
            NavigationPlanResult outside = planner.Plan(Request(grid, 0, new GridCoordinate(-1, 0), goal, "outside", 1000d));
            Assert(outside.Status == NavigationPlanStatus.InvalidRequest && outside.FailureReason == NavigationFailureReason.StartOutsideGrid, "C-FF outside-start classification is incorrect.", ref assertions);
            NavigationPlanResult undeclared = planner.Plan(Request(grid, 0, new GridCoordinate(0, 1), new GridCoordinate(3, 2), "undeclared", 1000d));
            Assert(undeclared.Status == NavigationPlanStatus.InvalidRequest, "C-FF accepted an undeclared goal.", ref assertions);

            NavigationChangeSet actual = grid.ApplyChanges("block-start", grid.Version, new[] { Change(0, 1, false, 1f) });
            NavigationPlanResult stale = planner.Plan(Request(grid, 0, new GridCoordinate(0, 0), goal, "stale", 1000d));
            Assert(stale.Status == NavigationPlanStatus.InvalidRequest && stale.FailureReason == NavigationFailureReason.StaleGridVersion, "C-FF accepted a stale plan.", ref assertions);
            NavigationChangeSet wrongPayload = new NavigationChangeSet
            {
                changeSetId = "wrong-payload",
                previousGridVersion = actual.previousGridVersion,
                newGridVersion = actual.newGridVersion,
                changes = new[] { Change(0, 1, true, 1f) }
            };
            Assert(planner.ApplyChanges(wrongPayload, 1000d).Status == NavigationPlanStatus.InvalidRequest && planner.GridVersion == 0, "C-FF accepted mismatched live payload.", ref assertions);
            Assert(planner.ApplyChanges(actual, 1000d).Status == NavigationPlanStatus.Succeeded && planner.GridVersion == 1, "C-FF valid rebuild failed after an invalid request.", ref assertions);
            NavigationPlanResult blockedStart = planner.Plan(Request(grid, 0, new GridCoordinate(0, 1), goal, "blocked-start", 1000d));
            Assert(blockedStart.Status == NavigationPlanStatus.NoPath && blockedStart.FailureReason == NavigationFailureReason.StartBlocked, "C-FF blocked-start classification is incorrect.", ref assertions);

            planner.Reset();
            Assert(planner.GridVersion == 0, "C-FF reset did not clear version.", ref assertions);
            planner.Initialize(grid, Initialization(NavigationGridConnectivity.FourWay, false, 1000d, goal));
            Assert(planner.GridVersion == grid.Version, "C-FF could not reinitialize after reset.", ref assertions);
            planner.Reset();
        }

        private static void TestAtomicBudgetBehavior(ref int assertions)
        {
            const int size = 96;
            ResearchNavigationGrid grid = new ResearchNavigationGrid(size, size);
            GridCoordinate goal = new GridCoordinate(size - 1, size - 1);
            CorrectedFullRecomputeFlowFieldPlanner planner = new CorrectedFullRecomputeFlowFieldPlanner();
            NavigationOperationMetrics initialization = planner.Initialize(grid, Initialization(NavigationGridConnectivity.EightWay, false, 1e-12d, goal));
            Assert(initialization.budgetExceeded, "Microscopic C-FF initialization budget did not record an overrun.", ref assertions);
            CorrectedFlowFieldCellSnapshot initialCell;
            Assert(planner.TryGetCellSnapshot(new GridCoordinate(0, 0), out initialCell) && initialCell.Reachable && initialCell.HasDirection, "Budget-overrun initialization exposed an incomplete field.", ref assertions);

            NavigationChangeSet changeSet = grid.ApplyChanges("budget-rebuild", grid.Version, new[] { Change(size / 2, size / 2, false, 1f) });
            NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1e-12d);
            Assert(repair.Status == NavigationPlanStatus.BudgetExceeded && repair.Metrics.budgetExceeded, "Microscopic C-FF repair budget did not return BudgetExceeded.", ref assertions);
            Assert(repair.GridVersion == grid.Version && planner.GridVersion == grid.Version && repair.Metrics.repairedCells == size * size, "Budget-overrun repair did not atomically commit the complete field.", ref assertions);
            CompareAllCells(planner, BuildOracle(grid, NavigationGridConnectivity.EightWay, false, new[] { goal }), grid, "budget rebuild", ref assertions);

            NavigationPlanResult recovered = planner.Plan(Request(grid, 0, new GridCoordinate(0, 0), goal, "budget-recovered", 5000d));
            Assert(recovered.Status == NavigationPlanStatus.Succeeded, "Plan could not use the atomically committed over-budget field.", ref assertions);
            NavigationPlanResult tinyPlan = planner.Plan(Request(grid, 0, new GridCoordinate(0, 0), goal, "budget-plan", 1e-12d));
            Assert(tinyPlan.Status == NavigationPlanStatus.BudgetExceeded && tinyPlan.Path.Count == 0, "Microscopic plan budget did not return an empty BudgetExceeded result.", ref assertions);
            planner.Reset();
        }

        private static void TestGeneratedOracleMatrix(VerificationResult verification, ref int assertions)
        {
            NavigationGridConnectivity[] topologies =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] cornerPolicies = { false, false, true };
            uint randomState = 0x83c14f27u;
            int staticFields = 0;
            int dynamicFields = 0;
            int comparedCells = 0;

            for (int topology = 0; topology < topologies.Length; topology++)
            {
                for (int caseIndex = 0; caseIndex < 8; caseIndex++)
                {
                    const int width = 6;
                    const int height = 5;
                    GridCoordinate[] availableGoals =
                    {
                        new GridCoordinate(5, 4),
                        new GridCoordinate(5, 0),
                        new GridCoordinate(3, 2)
                    };
                    int goalCount = 1 + (caseIndex % 3);
                    GridCoordinate[] goals = new GridCoordinate[goalCount];
                    Array.Copy(availableGoals, goals, goalCount);
                    HashSet<GridCoordinate> goalSet = new HashSet<GridCoordinate>(goals);
                    List<NavigationGridChange> initial = new List<NavigationGridChange>();
                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            GridCoordinate coordinate = new GridCoordinate(x, y);
                            uint walkabilityRoll = NextDeterministic(ref randomState);
                            uint costRoll = NextDeterministic(ref randomState);
                            initial.Add(Change(x, y, goalSet.Contains(coordinate) || (walkabilityRoll % 100u) >= 23u, 0.5f + ((costRoll % 10u) * 0.25f)));
                        }
                    }

                    ResearchNavigationGrid grid = new ResearchNavigationGrid(width, height, 1f, initial);
                    CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(grid, topologies[topology], cornerPolicies[topology], 1000d, goals);
                    comparedCells += CompareAllCells(planner, BuildOracle(grid, topologies[topology], cornerPolicies[topology], goals), grid, "generated initial", ref assertions);
                    staticFields++;

                    for (int changeIndex = 0; changeIndex < 3; changeIndex++)
                    {
                        int x = 1 + ((caseIndex + changeIndex * 2) % 4);
                        int y = (topology + caseIndex + changeIndex * 2) % height;
                        GridCoordinate coordinate = new GridCoordinate(x, y);
                        if (goalSet.Contains(coordinate)) coordinate = new GridCoordinate(1, (y + 1) % height);
                        uint walkabilityRoll = NextDeterministic(ref randomState);
                        uint costRoll = NextDeterministic(ref randomState);
                        NavigationGridChange change = Change(coordinate.x, coordinate.y, (walkabilityRoll % 5u) != 0u, 0.5f + ((costRoll % 9u) * 0.25f));
                        NavigationChangeSet changeSet = grid.ApplyChanges("oracle-change-" + topology + "-" + caseIndex + "-" + changeIndex, grid.Version, new[] { change });
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1000d);
                        Assert(repair.Status == NavigationPlanStatus.Succeeded && repair.Metrics.repairedCells == width * height, "Generated C-FF rebuild failed.", ref assertions);
                        comparedCells += CompareAllCells(planner, BuildOracle(grid, topologies[topology], cornerPolicies[topology], goals), grid, "generated dynamic", ref assertions);
                        dynamicFields++;
                    }
                    planner.Reset();
                }
            }
            verification.staticReferenceFieldCount = staticFields;
            verification.dynamicReferenceFieldCount = dynamicFields;
            verification.comparedCellCount = comparedCells;
            Assert(staticFields == 24 && dynamicFields == 72 && comparedCells == 2880, "C-FF generated reference matrix counts are incorrect.", ref assertions);
        }

        private static void TestDeterministicSequence(VerificationResult verification, ref int assertions)
        {
            SequenceSnapshot first = RunDeterministicSequence();
            SequenceSnapshot second = RunDeterministicSequence();
            Assert(first.signature == second.signature, "C-FF field/path/work signature changed across identical sequences.", ref assertions);
            Assert(first.rebuiltCells == second.rebuiltCells && first.rebuiltCells == 4L * 35L, "C-FF deterministic rebuilt-cell total is incorrect.", ref assertions);
            Assert(first.finalVersion == second.finalVersion && first.finalVersion == 4, "C-FF deterministic final version is incorrect.", ref assertions);
            verification.deterministicSignatureSha256 = Sha256Hex(first.signature);
            verification.deterministicRebuiltCells = first.rebuiltCells;
            verification.finalGridVersion = first.finalVersion;
        }

        private static SequenceSnapshot RunDeterministicSequence()
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(7, 5, 1f, new[]
            {
                Change(3, 1, false, 1f),
                Change(3, 3, false, 1f),
                Change(2, 2, true, 2f),
                Change(4, 2, true, 2f)
            });
            GridCoordinate goal = new GridCoordinate(6, 2);
            CorrectedFullRecomputeFlowFieldPlanner planner = Initialize(grid, NavigationGridConnectivity.EightWay, false, 1000d, goal);
            StringBuilder signature = new StringBuilder();
            long rebuilt = 0L;
            AppendSignature(planner, grid, planner.Plan(Request(grid, 0, new GridCoordinate(0, 2), goal, "det-0", 1000d)), signature);
            NavigationGridChange[][] changes =
            {
                new[] { Change(3, 2, false, 1f) },
                new[] { Change(3, 1, true, 1f) },
                new[] { Change(3, 2, true, 0.5f) },
                new[] { Change(3, 3, true, 1f), Change(3, 1, false, 1f) }
            };
            for (int index = 0; index < changes.Length; index++)
            {
                NavigationChangeSet set = grid.ApplyChanges("det-change-" + index, grid.Version, changes[index]);
                NavigationRepairResult repair = planner.ApplyChanges(set, 1000d);
                rebuilt += repair.Metrics.repairedCells;
                signature.Append("R:").Append(repair.Status).Append(':').Append(repair.Metrics.processedNodesOrCells).Append(':').Append(repair.Metrics.expandedNodes).Append(':').Append(repair.Metrics.relaxedEdges).Append('|');
                AppendSignature(planner, grid, planner.Plan(Request(grid, 0, new GridCoordinate(0, 2), goal, "det-plan-" + index, 1000d)), signature);
            }
            SequenceSnapshot snapshot = new SequenceSnapshot { signature = signature.ToString(), rebuiltCells = rebuilt, finalVersion = planner.GridVersion };
            planner.Reset();
            return snapshot;
        }

        private static void AppendSignature(CorrectedFullRecomputeFlowFieldPlanner planner, IReadOnlyNavigationGrid grid, NavigationPlanResult plan, StringBuilder signature)
        {
            signature.Append("P:").Append(plan.Status).Append(':').Append(FormatPath(plan.Path)).Append(':').Append(plan.Metrics.processedNodesOrCells).Append('|');
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    CorrectedFlowFieldCellSnapshot cell;
                    planner.TryGetCellSnapshot(new GridCoordinate(x, y), out cell);
                    signature.Append(cell.Reachable ? cell.IntegrationCost.ToString("R") : "INF").Append('/');
                    if (cell.HasOwnerGoal) signature.Append(cell.OwnerGoal.x).Append(',').Append(cell.OwnerGoal.y);
                    signature.Append('/');
                    if (cell.HasDirection) signature.Append(cell.Next.x).Append(',').Append(cell.Next.y);
                    signature.Append(';');
                }
            }
        }

        private static void TestWorkloadIntegration(VerificationResult verification, ref int assertions)
        {
            DeterministicScenarioDefinition scenario = new DeterministicScenarioDefinition
            {
                schemaVersion = 1,
                scenarioId = "gate8-cff-workload",
                randomSeed = 8008,
                gridWidth = 5,
                gridHeight = 3,
                defaultTraversalCost = 1f,
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 5,
                goalSetId = "gate8-shared-goal",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition { agentId = 0, start = new GridCoordinate(0, 0), goal = new GridCoordinate(4, 1) },
                    new ScenarioAgentDefinition { agentId = 1, start = new GridCoordinate(0, 2), goal = new GridCoordinate(4, 1) }
                },
                initialGridOverrides = new[] { Change(2, 1, true, 3f) },
                scheduledChanges = new[]
                {
                    new ScheduledNavigationChangeDefinition { eventId = "block-upper", simulationTick = 1, order = 0, repairBudgetMilliseconds = 1000d, changes = new[] { Change(2, 0, false, 1f) } },
                    new ScheduledNavigationChangeDefinition { eventId = "switch", simulationTick = 3, order = 0, repairBudgetMilliseconds = 1000d, changes = new[] { Change(2, 0, true, 1f), Change(2, 2, false, 1f) } }
                }
            };
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run("gate8-workload-run", scenario, new CorrectedFullRecomputeFlowFieldPlanner(), null);
            Assert(workload.completed && workload.algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField && workload.usesFixedScenarioStarts, "C-FF workload identity/completion is incorrect.", ref assertions);
            Assert(workload.planOperationCount == 6 && workload.repairOperationCount == 2 && workload.dynamicPlanningPhaseCount == 2 && workload.finalGridVersion == 2, "C-FF workload structural counts are incorrect.", ref assertions);
            Assert(workload.succeededPlanCount == 6 && workload.failedPlanCount == 0 && workload.invalidPlanCount == 0 && workload.noPathPlanCount == 0, "C-FF shared-goal workload did not produce six successful plans.", ref assertions);
            Assert(workload.repairedCells == 2L * 15L && workload.processedNodesOrCells > 0, "C-FF workload did not report complete rebuild work.", ref assertions);
            verification.workloadPlanOperations = workload.planOperationCount;
            verification.workloadRepairOperations = workload.repairOperationCount;
        }

        private static void TestCommittedScenarioCompatibility(VerificationResult verification, ref int assertions)
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string scenarioPath = Path.Combine(projectPath, "Research", "Scenarios", "dynamic_corridors_sparse_v1.scenario.json");
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run("gate8-committed-scenario", loaded.Definition, new CorrectedFullRecomputeFlowFieldPlanner(), null);
            Assert(workload.completed && workload.algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, "Committed dynamic scenario did not complete with C-FF.", ref assertions);
            Assert(workload.planOperationCount == 8 && workload.repairOperationCount == 4 && workload.succeededPlanCount == 8, "Committed dynamic scenario is not C-FF goal-ownership compatible.", ref assertions);
            Assert(workload.invalidPlanCount == 0 && workload.failedPlanCount == 0 && workload.noPathPlanCount == 0 && workload.finalGridVersion == 4, "Committed dynamic scenario produced invalid C-FF outcomes.", ref assertions);
            verification.committedScenarioPlanOperations = workload.planOperationCount;
        }

        private static int CompareAllCells(
            CorrectedFullRecomputeFlowFieldPlanner planner,
            OracleField expected,
            IReadOnlyNavigationGrid grid,
            string context,
            ref int assertions)
        {
            int compared = 0;
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    int index = (y * grid.Width) + x;
                    CorrectedFlowFieldCellSnapshot actual;
                    Assert(planner.TryGetCellSnapshot(coordinate, out actual), "Missing C-FF snapshot: " + context + " " + coordinate, ref assertions);
                    Assert(actual.Walkable == grid.IsWalkable(coordinate), "Walkability mismatch: " + context + " " + coordinate, ref assertions);
                    bool expectedReachable = !double.IsPositiveInfinity(expected.integration[index]);
                    Assert(actual.Reachable == expectedReachable, "Reachability mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(actual.IsActiveGoal == expected.activeGoal[index], "Active-goal mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(actual.HasOwnerGoal == expected.hasOwner[index] && (!actual.HasOwnerGoal || actual.OwnerGoal.Equals(expected.owner[index])), "Owner mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(actual.HasDirection == expected.hasDirection[index] && (!actual.HasDirection || actual.Next.Equals(expected.next[index])), "Direction mismatch: " + context + " " + coordinate, ref assertions);
                    Assert((double.IsPositiveInfinity(actual.IntegrationCost) && double.IsPositiveInfinity(expected.integration[index])) || Math.Abs(actual.IntegrationCost - expected.integration[index]) < Tolerance, "Integration mismatch: " + context + " " + coordinate, ref assertions);
                    compared++;
                }
            }
            return compared;
        }

        private static OracleField BuildOracle(
            IReadOnlyNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            GridCoordinate[] goals)
        {
            int count = checked(grid.Width * grid.Height);
            OracleField result = new OracleField(count);
            bool[] settled = new bool[count];
            HashSet<GridCoordinate> unique = new HashSet<GridCoordinate>(goals);
            List<GridCoordinate> canonical = new List<GridCoordinate>(unique);
            canonical.Sort(CompareCoordinates);
            for (int goalIndex = 0; goalIndex < canonical.Count; goalIndex++)
            {
                GridCoordinate goal = canonical[goalIndex];
                if (!grid.IsWalkable(goal)) continue;
                int index = (goal.y * grid.Width) + goal.x;
                result.integration[index] = 0d;
                result.hasOwner[index] = true;
                result.owner[index] = goal;
                result.activeGoal[index] = true;
            }

            for (int iteration = 0; iteration < count; iteration++)
            {
                int currentIndex = -1;
                for (int index = 0; index < count; index++)
                {
                    if (settled[index] || double.IsPositiveInfinity(result.integration[index])) continue;
                    if (currentIndex < 0 || CompareOracleVertex(index, currentIndex, result, grid.Width) < 0) currentIndex = index;
                }
                if (currentIndex < 0) break;
                settled[currentIndex] = true;
                GridCoordinate destination = new GridCoordinate(currentIndex % grid.Width, currentIndex / grid.Width);
                for (int deltaY = -1; deltaY <= 1; deltaY++)
                {
                    for (int deltaX = -1; deltaX <= 1; deltaX++)
                    {
                        if (deltaX == 0 && deltaY == 0) continue;
                        GridCoordinate predecessor = new GridCoordinate(destination.x - deltaX, destination.y - deltaY);
                        if (!ReferenceLegalMove(grid, predecessor, destination, connectivity, allowCornerCutting)) continue;
                        int predecessorIndex = (predecessor.y * grid.Width) + predecessor.x;
                        double multiplier = deltaX != 0 && deltaY != 0 ? Math.Sqrt(2d) : 1d;
                        double candidate = result.integration[currentIndex] + (grid.GetTraversalCost(destination) * multiplier);
                        bool lower = candidate < result.integration[predecessorIndex] - 1e-12d;
                        bool equalEarlier = Math.Abs(candidate - result.integration[predecessorIndex]) <= 1e-12d &&
                            (!result.hasOwner[predecessorIndex] || CompareCoordinates(result.owner[currentIndex], result.owner[predecessorIndex]) < 0);
                        if (!lower && !equalEarlier) continue;
                        if (lower || candidate < result.integration[predecessorIndex]) result.integration[predecessorIndex] = candidate;
                        result.hasOwner[predecessorIndex] = true;
                        result.owner[predecessorIndex] = result.owner[currentIndex];
                    }
                }
            }

            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate current = new GridCoordinate(x, y);
                    int currentIndex = (y * grid.Width) + x;
                    if (!grid.IsWalkable(current) || double.IsPositiveInfinity(result.integration[currentIndex]) || result.activeGoal[currentIndex]) continue;
                    bool found = false;
                    GridCoordinate bestSuccessor = new GridCoordinate();
                    GridCoordinate bestOwner = new GridCoordinate();
                    double bestTotal = double.PositiveInfinity;
                    double bestRemaining = double.PositiveInfinity;
                    for (int deltaY = -1; deltaY <= 1; deltaY++)
                    {
                        for (int deltaX = -1; deltaX <= 1; deltaX++)
                        {
                            if (deltaX == 0 && deltaY == 0) continue;
                            GridCoordinate successor = new GridCoordinate(x + deltaX, y + deltaY);
                            if (!ReferenceLegalMove(grid, current, successor, connectivity, allowCornerCutting)) continue;
                            int successorIndex = (successor.y * grid.Width) + successor.x;
                            if (!result.hasOwner[successorIndex]) continue;
                            double multiplier = deltaX != 0 && deltaY != 0 ? Math.Sqrt(2d) : 1d;
                            double total = (grid.GetTraversalCost(successor) * multiplier) + result.integration[successorIndex];
                            if (Math.Abs(total - result.integration[currentIndex]) > 1e-12d) continue;
                            if (!found || CompareOracleDirection(total, result.owner[successorIndex], result.integration[successorIndex], successor, bestTotal, bestOwner, bestRemaining, bestSuccessor) < 0)
                            {
                                found = true;
                                bestTotal = total;
                                bestOwner = result.owner[successorIndex];
                                bestRemaining = result.integration[successorIndex];
                                bestSuccessor = successor;
                            }
                        }
                    }
                    if (!found) throw new InvalidOperationException("Oracle reachable cell has no direction: " + current);
                    if (!result.owner[currentIndex].Equals(bestOwner)) throw new InvalidOperationException("Oracle owner/direction disagreement: " + current);
                    result.hasDirection[currentIndex] = true;
                    result.next[currentIndex] = bestSuccessor;
                }
            }
            return result;
        }

        private static int CompareOracleVertex(int leftIndex, int rightIndex, OracleField field, int width)
        {
            double leftDistance = field.integration[leftIndex];
            double rightDistance = field.integration[rightIndex];
            if (Math.Abs(leftDistance - rightDistance) > 1e-12d) return leftDistance.CompareTo(rightDistance);
            int comparison = CompareCoordinates(field.owner[leftIndex], field.owner[rightIndex]);
            if (comparison != 0) return comparison;
            GridCoordinate left = new GridCoordinate(leftIndex % width, leftIndex / width);
            GridCoordinate right = new GridCoordinate(rightIndex % width, rightIndex / width);
            return CompareCoordinates(left, right);
        }

        private static int CompareOracleDirection(
            double leftTotal, GridCoordinate leftOwner, double leftRemaining, GridCoordinate leftSuccessor,
            double rightTotal, GridCoordinate rightOwner, double rightRemaining, GridCoordinate rightSuccessor)
        {
            if (Math.Abs(leftTotal - rightTotal) > 1e-12d) return leftTotal.CompareTo(rightTotal);
            int comparison = CompareCoordinates(leftOwner, rightOwner);
            if (comparison != 0) return comparison;
            if (Math.Abs(leftRemaining - rightRemaining) > 1e-12d) return leftRemaining.CompareTo(rightRemaining);
            return CompareCoordinates(leftSuccessor, rightSuccessor);
        }

        private static bool ReferenceLegalMove(
            IReadOnlyNavigationGrid grid,
            GridCoordinate from,
            GridCoordinate to,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting)
        {
            if (!grid.Contains(from) || !grid.Contains(to) || !grid.IsWalkable(from) || !grid.IsWalkable(to)) return false;
            int deltaX = Math.Abs(to.x - from.x);
            int deltaY = Math.Abs(to.y - from.y);
            if (deltaX > 1 || deltaY > 1 || deltaX + deltaY == 0) return false;
            if (connectivity == NavigationGridConnectivity.FourWay && deltaX + deltaY != 1) return false;
            if (deltaX == 1 && deltaY == 1 && !allowCornerCutting)
            {
                if (!grid.IsWalkable(new GridCoordinate(to.x, from.y)) || !grid.IsWalkable(new GridCoordinate(from.x, to.y))) return false;
            }
            return true;
        }

        private static CorrectedFullRecomputeFlowFieldPlanner Initialize(
            IReadOnlyNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            double budget,
            params GridCoordinate[] goals)
        {
            CorrectedFullRecomputeFlowFieldPlanner planner = new CorrectedFullRecomputeFlowFieldPlanner();
            planner.Initialize(grid, Initialization(connectivity, allowCornerCutting, budget, goals));
            return planner;
        }

        private static NavigationPlannerInitialization Initialization(
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            double budget,
            params GridCoordinate[] goals)
        {
            return new NavigationPlannerInitialization
            {
                runId = "gate8-test",
                goalSetId = "gate8-goals",
                goals = goals,
                connectivity = connectivity,
                allowDiagonalCornerCutting = allowCornerCutting,
                budgetMilliseconds = budget
            };
        }

        private static NavigationPlanRequest Request(
            IReadOnlyNavigationGrid grid,
            int agentId,
            GridCoordinate start,
            GridCoordinate goal,
            string requestId,
            double budget)
        {
            return new NavigationPlanRequest
            {
                runId = "gate8-test",
                requestId = requestId,
                goalSetId = "gate8-goals",
                agentId = agentId,
                start = start,
                goal = goal,
                expectedGridVersion = grid.Version,
                budgetMilliseconds = budget
            };
        }

        private static NavigationGridChange Change(int x, int y, bool walkable, float cost)
        {
            return new NavigationGridChange { coordinate = new GridCoordinate(x, y), isWalkable = walkable, traversalCost = cost };
        }

        private static int CompareCoordinates(GridCoordinate left, GridCoordinate right)
        {
            int comparison = left.y.CompareTo(right.y);
            return comparison != 0 ? comparison : left.x.CompareTo(right.x);
        }

        private static uint NextDeterministic(ref uint state)
        {
            state = unchecked((state * 1664525u) + 1013904223u);
            return state;
        }

        private static double PathCost(IReadOnlyNavigationGrid grid, IReadOnlyList<GridCoordinate> path)
        {
            double total = 0d;
            for (int index = 1; index < path.Count; index++)
            {
                int deltaX = Math.Abs(path[index].x - path[index - 1].x);
                int deltaY = Math.Abs(path[index].y - path[index - 1].y);
                total += grid.GetTraversalCost(path[index]) * (deltaX == 1 && deltaY == 1 ? Math.Sqrt(2d) : 1d);
            }
            return total;
        }

        private static string FormatPath(IReadOnlyList<GridCoordinate> path)
        {
            StringBuilder builder = new StringBuilder();
            for (int index = 0; index < path.Count; index++)
            {
                if (index > 0) builder.Append(" -> ");
                builder.Append(path[index]);
            }
            return builder.ToString();
        }

        private static string Sha256Hex(string value)
        {
            using (SHA256 sha256 = SHA256.Create())
            {
                byte[] hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(value));
                return BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void WriteResult(string path, VerificationResult result)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, JsonUtility.ToJson(result, true));
        }
    }
}
