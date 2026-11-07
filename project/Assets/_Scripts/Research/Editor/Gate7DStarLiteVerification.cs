using System;
using System.Collections.Generic;
using System.IO;
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
    public static class Gate7DStarLiteVerification
    {
        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int staticReferenceCaseCount;
            public int dynamicReferenceCaseCount;
            public string deterministicPath;
            public long deterministicRepairWork;
            public long finalGridVersion;
            public int workloadPlanOperations;
            public int workloadRepairOperations;
            public string error;
        }

        private sealed class SequenceSnapshot
        {
            public string paths;
            public string work;
            public long finalVersion;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate7_DStarLite.json");
            VerificationResult result = new VerificationResult();
            try
            {
                int assertions = 0;
                TestStaticWeightedAndReuse(result, ref assertions);
                TestLocalDynamicChanges(result, ref assertions);
                TestLowerHeuristicScaleRebuild(ref assertions);
                TestDynamicCornerPolicy(ref assertions);
                TestMultiAgentAndValidation(ref assertions);
                TestBudgetContinuation(ref assertions);
                TestWorkloadIntegration(result, ref assertions);
                TestReferenceSequences(result, ref assertions);
                TestDeterministicSequence(result, ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 7 D* Lite verification passed with " + assertions + " assertions.");
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

        private static void TestStaticWeightedAndReuse(VerificationResult verification, ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(5, 3, 1f, new[]
            {
                Change(1, 1, true, 10f),
                Change(2, 1, true, 10f),
                Change(3, 1, true, 10f)
            });
            GridCoordinate start = new GridCoordinate(0, 1);
            GridCoordinate goal = new GridCoordinate(4, 1);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            Assert(planner.AlgorithmId == NavigationAlgorithmIds.DStarLite, "D* Lite algorithm id is incorrect.", ref assertions);
            Assert(planner.Capabilities == (NavigationPlannerCapabilities.PerAgentState | NavigationPlannerCapabilities.IncrementalRepair), "D* Lite capabilities are incorrect.", ref assertions);

            NavigationPlanResult first = planner.Plan(Request(grid, 0, start, goal, "weighted-first", 1000d));
            AssertPlanMatchesReference(grid, first, start, goal, NavigationGridConnectivity.FourWay, false, "weighted first", ref assertions);
            Assert(first.Path.Count == 7 && !Contains(first.Path, new GridCoordinate(2, 1)), "D* Lite did not choose the weighted detour.", ref assertions);

            NavigationPlanResult second = planner.Plan(Request(grid, 0, start, goal, "weighted-second", 1000d));
            Assert(second.Status == NavigationPlanStatus.Succeeded && PathsEqual(first.Path, second.Path), "Repeated unchanged D* Lite plan was not deterministic.", ref assertions);
            Assert(second.Metrics.expandedNodes == 0, "Unchanged D* Lite state unexpectedly expanded queue nodes.", ref assertions);
            verification.deterministicPath = FormatPath(first.Path);
            planner.Reset();
        }

        private static void TestLocalDynamicChanges(VerificationResult verification, ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(6, 3);
            GridCoordinate start = new GridCoordinate(0, 1);
            GridCoordinate goal = new GridCoordinate(5, 1);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationPlanResult initial = planner.Plan(Request(grid, 0, start, goal, "local-initial", 1000d));
            Assert(initial.Status == NavigationPlanStatus.Succeeded && Contains(initial.Path, new GridCoordinate(2, 1)), "Initial local-change path is incorrect.", ref assertions);

            NavigationChangeSet blocked = grid.ApplyChanges("block-middle", grid.Version, new[] { Change(2, 1, false, 1f) });
            NavigationRepairResult blockedRepair = planner.ApplyChanges(blocked, 1000d);
            Assert(blockedRepair.Status == NavigationPlanStatus.Succeeded && blockedRepair.Metrics.repairedCells > 0, "D* Lite did not incrementally repair a blocked cell.", ref assertions);
            NavigationPlanResult detour = planner.Plan(Request(grid, 0, start, goal, "local-detour", 1000d));
            AssertPlanMatchesReference(grid, detour, start, goal, NavigationGridConnectivity.FourWay, false, "blocked detour", ref assertions);
            Assert(!Contains(detour.Path, new GridCoordinate(2, 1)), "Repaired path still contains the blocked cell.", ref assertions);

            NavigationChangeSet increased = grid.ApplyChanges("increase-upper", grid.Version, new[] { Change(3, 0, true, 8f) });
            NavigationRepairResult increasedRepair = planner.ApplyChanges(increased, 1000d);
            Assert(increasedRepair.Status == NavigationPlanStatus.Succeeded, "D* Lite cost-increase repair failed.", ref assertions);
            NavigationPlanResult afterIncrease = planner.Plan(Request(grid, 0, start, goal, "after-increase", 1000d));
            AssertPlanMatchesReference(grid, afterIncrease, start, goal, NavigationGridConnectivity.FourWay, false, "cost increase", ref assertions);

            NavigationChangeSet restored = grid.ApplyChanges("restore-middle", grid.Version, new[]
            {
                Change(3, 0, true, 1f),
                Change(2, 1, true, 1f)
            });
            NavigationRepairResult restoredRepair = planner.ApplyChanges(restored, 1000d);
            Assert(restoredRepair.Status == NavigationPlanStatus.Succeeded && planner.GridVersion == 3, "D* Lite mixed local repair failed.", ref assertions);
            NavigationPlanResult restoredPlan = planner.Plan(Request(grid, 0, start, goal, "restored", 1000d));
            AssertPlanMatchesReference(grid, restoredPlan, start, goal, NavigationGridConnectivity.FourWay, false, "restored route", ref assertions);
            Assert(restoredPlan.Path.Count == 6 && Contains(restoredPlan.Path, new GridCoordinate(2, 1)), "Restored route did not return to the direct corridor.", ref assertions);
            verification.finalGridVersion = planner.GridVersion;
            planner.Reset();
        }

        private static void TestLowerHeuristicScaleRebuild(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(4, 3, 2f);
            GridCoordinate start = new GridCoordinate(0, 1);
            GridCoordinate goal = new GridCoordinate(3, 1);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationPlanResult initial = planner.Plan(Request(grid, 0, start, goal, "scale-initial", 1000d));
            AssertPlanMatchesReference(grid, initial, start, goal, NavigationGridConnectivity.FourWay, false, "scale initial", ref assertions);

            NavigationChangeSet lower = grid.ApplyChanges("lower-below-scale", grid.Version, new[] { Change(1, 1, true, 0.25f) });
            NavigationRepairResult repair = planner.ApplyChanges(lower, 1000d);
            Assert(repair.Status == NavigationPlanStatus.Succeeded, "Lower heuristic-scale repair failed.", ref assertions);
            Assert(repair.Metrics.repairedCells >= grid.Width * grid.Height, "Lower heuristic scale did not trigger a measured full state rebuild.", ref assertions);
            NavigationPlanResult result = planner.Plan(Request(grid, 0, start, goal, "scale-lowered", 1000d));
            AssertPlanMatchesReference(grid, result, start, goal, NavigationGridConnectivity.FourWay, false, "scale lowered", ref assertions);
            Assert(Contains(result.Path, new GridCoordinate(1, 1)), "Lower-cost cell was not used after heuristic rebuild.", ref assertions);
            planner.Reset();
        }

        private static void TestDynamicCornerPolicy(ref int assertions)
        {
            GridCoordinate start = new GridCoordinate(0, 0);
            GridCoordinate goal = new GridCoordinate(1, 1);
            ResearchNavigationGrid strictGrid = new ResearchNavigationGrid(2, 2);
            DStarLitePlanner strict = Initialize(strictGrid, NavigationGridConnectivity.EightWay, false, goal);
            NavigationPlanResult diagonal = strict.Plan(Request(strictGrid, 0, start, goal, "corner-open", 1000d));
            Assert(diagonal.Status == NavigationPlanStatus.Succeeded && diagonal.Path.Count == 2, "Open strict-corner grid did not use the diagonal.", ref assertions);

            NavigationChangeSet oneBlocked = strictGrid.ApplyChanges("corner-one", strictGrid.Version, new[] { Change(1, 0, false, 1f) });
            Assert(strict.ApplyChanges(oneBlocked, 1000d).Status == NavigationPlanStatus.Succeeded, "Strict-corner single-block repair failed.", ref assertions);
            NavigationPlanResult around = strict.Plan(Request(strictGrid, 0, start, goal, "corner-around", 1000d));
            AssertPlanMatchesReference(strictGrid, around, start, goal, NavigationGridConnectivity.EightWay, false, "strict corner around", ref assertions);
            Assert(around.Path.Count == 3, "Strict corner policy still allowed the blocked diagonal.", ref assertions);

            NavigationChangeSet bothBlocked = strictGrid.ApplyChanges("corner-both", strictGrid.Version, new[] { Change(0, 1, false, 1f) });
            Assert(strict.ApplyChanges(bothBlocked, 1000d).Status == NavigationPlanStatus.Succeeded, "Strict-corner second-block repair failed.", ref assertions);
            NavigationPlanResult disconnected = strict.Plan(Request(strictGrid, 0, start, goal, "corner-none", 1000d));
            Assert(disconnected.Status == NavigationPlanStatus.NoPath && disconnected.FailureReason == NavigationFailureReason.NoReachablePath, "Strict corner disconnection was not detected.", ref assertions);
            strict.Reset();

            ResearchNavigationGrid permissiveGrid = new ResearchNavigationGrid(2, 2, 1f, new[]
            {
                Change(1, 0, false, 1f),
                Change(0, 1, false, 1f)
            });
            DStarLitePlanner permissive = Initialize(permissiveGrid, NavigationGridConnectivity.EightWay, true, goal);
            NavigationPlanResult permissivePlan = permissive.Plan(Request(permissiveGrid, 0, start, goal, "corner-permissive", 1000d));
            Assert(permissivePlan.Status == NavigationPlanStatus.Succeeded && permissivePlan.Path.Count == 2, "Permissive D* Lite did not allow corner cutting.", ref assertions);
            permissive.Reset();
        }

        private static void TestMultiAgentAndValidation(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(5, 3);
            GridCoordinate firstGoal = new GridCoordinate(4, 0);
            GridCoordinate secondGoal = new GridCoordinate(4, 2);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, firstGoal, secondGoal);
            NavigationPlanResult first = planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "agent-one", 1000d));
            NavigationPlanResult second = planner.Plan(Request(grid, 2, new GridCoordinate(0, 2), secondGoal, "agent-two", 1000d));
            Assert(first.Status == NavigationPlanStatus.Succeeded && second.Status == NavigationPlanStatus.Succeeded, "Independent agent states did not initialize.", ref assertions);

            NavigationPlanResult goalSwitch = planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), secondGoal, "goal-switch", 1000d));
            Assert(goalSwitch.Status == NavigationPlanStatus.InvalidRequest, "Same-agent goal switch was accepted.", ref assertions);
            NavigationPlanRequest wrongRun = Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "wrong-run", 1000d);
            wrongRun.runId = "wrong";
            Assert(planner.Plan(wrongRun).Status == NavigationPlanStatus.InvalidRequest, "Wrong run identity was accepted.", ref assertions);

            NavigationPlanRequest outside = Request(grid, 1, new GridCoordinate(-1, 0), firstGoal, "outside", 1000d);
            NavigationPlanResult outsideResult = planner.Plan(outside);
            Assert(outsideResult.Status == NavigationPlanStatus.InvalidRequest && outsideResult.FailureReason == NavigationFailureReason.StartOutsideGrid, "Outside start classification is incorrect.", ref assertions);

            NavigationChangeSet actual = grid.ApplyChanges("multi-block", grid.Version, new[] { Change(2, 0, false, 1f) });
            NavigationPlanResult stalePlan = planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "stale-before-repair", 1000d));
            Assert(stalePlan.Status == NavigationPlanStatus.InvalidRequest && stalePlan.FailureReason == NavigationFailureReason.StaleGridVersion, "Stale grid was not rejected before repair.", ref assertions);
            NavigationChangeSet wrongPayload = new NavigationChangeSet
            {
                changeSetId = "wrong-payload",
                previousGridVersion = actual.previousGridVersion,
                newGridVersion = actual.newGridVersion,
                changes = new[] { Change(2, 0, true, 1f) }
            };
            NavigationRepairResult invalidRepair = planner.ApplyChanges(wrongPayload, 1000d);
            Assert(invalidRepair.Status == NavigationPlanStatus.InvalidRequest && planner.GridVersion == 0, "Mismatched live change payload was accepted.", ref assertions);
            NavigationRepairResult validRepair = planner.ApplyChanges(actual, 1000d);
            Assert(validRepair.Status == NavigationPlanStatus.Succeeded && planner.GridVersion == 1, "Valid multi-agent repair failed after invalid request.", ref assertions);
            AssertPlanMatchesReference(grid, planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "agent-one-repaired", 1000d)), new GridCoordinate(0, 0), firstGoal, NavigationGridConnectivity.FourWay, false, "agent one repaired", ref assertions);
            AssertPlanMatchesReference(grid, planner.Plan(Request(grid, 2, new GridCoordinate(1, 2), secondGoal, "agent-two-moved", 1000d)), new GridCoordinate(1, 2), secondGoal, NavigationGridConnectivity.FourWay, false, "agent two moved", ref assertions);

            NavigationChangeSet blockGoal = grid.ApplyChanges("block-goal", grid.Version, new[] { Change(4, 0, false, 1f) });
            planner.ApplyChanges(blockGoal, 1000d);
            NavigationPlanResult blockedGoal = planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "blocked-goal", 1000d));
            Assert(blockedGoal.Status == NavigationPlanStatus.NoPath && blockedGoal.FailureReason == NavigationFailureReason.GoalBlocked, "Blocked goal classification is incorrect.", ref assertions);
            NavigationChangeSet reopenGoal = grid.ApplyChanges("reopen-goal", grid.Version, new[] { Change(4, 0, true, 1f) });
            planner.ApplyChanges(reopenGoal, 1000d);
            AssertPlanMatchesReference(grid, planner.Plan(Request(grid, 1, new GridCoordinate(0, 0), firstGoal, "goal-restored", 1000d)), new GridCoordinate(0, 0), firstGoal, NavigationGridConnectivity.FourWay, false, "goal restored", ref assertions);
            planner.Reset();

            bool threwBeforeInitialize = false;
            try { new DStarLitePlanner().Plan(Request(grid, 0, new GridCoordinate(0, 0), firstGoal, "uninitialized", 1000d)); }
            catch (InvalidOperationException) { threwBeforeInitialize = true; }
            Assert(threwBeforeInitialize, "Planning before D* Lite initialization did not throw.", ref assertions);
        }

        private static void TestBudgetContinuation(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(96, 96);
            GridCoordinate start = new GridCoordinate(0, 0);
            GridCoordinate goal = new GridCoordinate(95, 95);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationPlanResult exhausted = planner.Plan(Request(grid, 0, start, goal, "plan-budget", double.Epsilon));
            Assert(exhausted.Status == NavigationPlanStatus.BudgetExceeded && exhausted.Metrics.budgetExceeded && exhausted.Path.Count == 0, "Microscopic D* Lite plan budget did not stop safely.", ref assertions);
            NavigationPlanResult continued = planner.Plan(Request(grid, 0, start, goal, "plan-continue", 5000d));
            AssertPlanMatchesReference(grid, continued, start, goal, NavigationGridConnectivity.FourWay, false, "continued plan", ref assertions);

            NavigationChangeSet change = grid.ApplyChanges("budget-change", grid.Version, new[] { Change(48, 48, false, 1f) });
            NavigationRepairResult repairBudget = planner.ApplyChanges(change, double.Epsilon);
            Assert(repairBudget.Status == NavigationPlanStatus.BudgetExceeded && repairBudget.Metrics.budgetExceeded && planner.GridVersion == grid.Version, "Microscopic repair budget did not preserve a resumable versioned state.", ref assertions);
            NavigationPlanResult afterRepair = planner.Plan(Request(grid, 0, start, goal, "repair-continue", 5000d));
            AssertPlanMatchesReference(grid, afterRepair, start, goal, NavigationGridConnectivity.FourWay, false, "continued repair", ref assertions);
            planner.Reset();
        }

        private static void TestWorkloadIntegration(VerificationResult verification, ref int assertions)
        {
            DeterministicScenarioDefinition scenario = new DeterministicScenarioDefinition
            {
                scenarioId = "gate7-workload",
                randomSeed = 7007,
                gridWidth = 6,
                gridHeight = 4,
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                maxSimulationTicks = 1000002,
                goalSetId = "gate7-goals",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition { agentId = 0, start = new GridCoordinate(0, 0), goal = new GridCoordinate(5, 0) },
                    new ScenarioAgentDefinition { agentId = 1, start = new GridCoordinate(0, 3), goal = new GridCoordinate(5, 3) }
                },
                scheduledChanges = new[]
                {
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = "block-upper",
                        simulationTick = 2,
                        order = 0,
                        repairBudgetMilliseconds = 1000d,
                        changes = new[] { Change(2, 0, false, 1f) }
                    },
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = "block-lower",
                        simulationTick = 2,
                        order = 1,
                        repairBudgetMilliseconds = 1000d,
                        changes = new[] { Change(2, 3, false, 1f) }
                    },
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = "restore",
                        simulationTick = 1000000,
                        order = 0,
                        repairBudgetMilliseconds = 1000d,
                        changes = new[] { Change(2, 0, true, 1f), Change(2, 3, true, 1f) }
                    }
                }
            };
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run("gate7-workload-run", scenario, new DStarLitePlanner(), null);
            Assert(workload.completed && workload.algorithmId == NavigationAlgorithmIds.DStarLite && workload.usesFixedScenarioStarts, "D* Lite workload did not complete with the correct identity.", ref assertions);
            Assert(workload.planOperationCount == 6 && workload.repairOperationCount == 3 && workload.dynamicPlanningPhaseCount == 2 && workload.finalGridVersion == 3, "D* Lite workload structural counts are incorrect.", ref assertions);
            Assert(workload.succeededPlanCount == 6 && workload.failedPlanCount == 0 && workload.noPathPlanCount == 0 && workload.invalidPlanCount == 0, "D* Lite workload did not produce six successful plans.", ref assertions);
            Assert(workload.repairedCells > 0 && workload.processedNodesOrCells > 0, "D* Lite workload did not record incremental work.", ref assertions);
            verification.workloadPlanOperations = workload.planOperationCount;
            verification.workloadRepairOperations = workload.repairOperationCount;
        }

        private static void TestReferenceSequences(VerificationResult verification, ref int assertions)
        {
            NavigationGridConnectivity[] connectivities =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] cornerPolicies = { false, false, true };
            uint randomState = 0x7a31b5c9u;
            int staticCases = 0;
            int dynamicCases = 0;

            for (int topology = 0; topology < connectivities.Length; topology++)
            {
                for (int caseIndex = 0; caseIndex < 8; caseIndex++)
                {
                    const int width = 6;
                    const int height = 5;
                    GridCoordinate start = new GridCoordinate(0, 0);
                    GridCoordinate goal = new GridCoordinate(width - 1, height - 1);
                    List<NavigationGridChange> initial = new List<NavigationGridChange>();
                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            uint walkabilityRoll = NextDeterministic(ref randomState);
                            uint costRoll = NextDeterministic(ref randomState);
                            GridCoordinate coordinate = new GridCoordinate(x, y);
                            bool endpoint = coordinate.Equals(start) || coordinate.Equals(goal);
                            initial.Add(Change(x, y, endpoint || (walkabilityRoll % 100u) >= 24u, 0.75f + ((costRoll % 8u) * 0.25f)));
                        }
                    }

                    ResearchNavigationGrid grid = new ResearchNavigationGrid(width, height, 1f, initial);
                    DStarLitePlanner planner = Initialize(grid, connectivities[topology], cornerPolicies[topology], goal);
                    NavigationPlanResult initialPlan = planner.Plan(Request(grid, 0, start, goal, "reference-initial-" + topology + "-" + caseIndex, 1000d));
                    AssertPlanMatchesReference(grid, initialPlan, start, goal, connectivities[topology], cornerPolicies[topology], "reference initial", ref assertions);
                    staticCases++;

                    for (int changeIndex = 0; changeIndex < 3; changeIndex++)
                    {
                        int x = 1 + ((caseIndex * 2 + changeIndex) % (width - 2));
                        int y = (topology + caseIndex + (changeIndex * 2)) % height;
                        uint walkabilityRoll = NextDeterministic(ref randomState);
                        uint costRoll = NextDeterministic(ref randomState);
                        NavigationGridChange change = Change(x, y, (walkabilityRoll % 5u) != 0u, 0.5f + ((costRoll % 9u) * 0.25f));
                        NavigationChangeSet changeSet = grid.ApplyChanges("reference-change-" + topology + "-" + caseIndex + "-" + changeIndex, grid.Version, new[] { change });
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1000d);
                        Assert(repair.Status == NavigationPlanStatus.Succeeded, "D* Lite reference-sequence repair failed.", ref assertions);
                        NavigationPlanResult plan = planner.Plan(Request(grid, 0, start, goal, "reference-plan-" + topology + "-" + caseIndex + "-" + changeIndex, 1000d));
                        AssertPlanMatchesReference(grid, plan, start, goal, connectivities[topology], cornerPolicies[topology], "reference dynamic", ref assertions);
                        dynamicCases++;
                    }
                    planner.Reset();
                }
            }
            verification.staticReferenceCaseCount = staticCases;
            verification.dynamicReferenceCaseCount = dynamicCases;
            Assert(staticCases == 24 && dynamicCases == 72, "D* Lite reference case counts are incorrect.", ref assertions);
        }

        private static void TestDeterministicSequence(VerificationResult verification, ref int assertions)
        {
            SequenceSnapshot first = RunDeterministicSequence();
            SequenceSnapshot second = RunDeterministicSequence();
            Assert(first.paths == second.paths, "D* Lite paths/statuses changed across identical dynamic sequences.", ref assertions);
            Assert(first.work == second.work, "D* Lite deterministic work counts changed across identical sequences.", ref assertions);
            Assert(first.finalVersion == second.finalVersion && first.finalVersion == 4, "D* Lite deterministic sequence versions are incorrect.", ref assertions);
            verification.deterministicRepairWork = ParseRepairTotal(first.work);
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
            GridCoordinate start = new GridCoordinate(0, 2);
            GridCoordinate goal = new GridCoordinate(6, 2);
            DStarLitePlanner planner = Initialize(grid, NavigationGridConnectivity.EightWay, false, goal);
            StringBuilder paths = new StringBuilder();
            StringBuilder work = new StringBuilder();
            long repairTotal = 0L;

            AppendPlan(planner.Plan(Request(grid, 0, start, goal, "det-0", 1000d)), paths, work);
            NavigationGridChange[][] changes =
            {
                new[] { Change(3, 2, false, 1f) },
                new[] { Change(3, 1, true, 1f) },
                new[] { Change(3, 2, true, 0.5f) },
                new[] { Change(3, 3, true, 1f), Change(3, 1, false, 1f) }
            };
            for (int index = 0; index < changes.Length; index++)
            {
                NavigationChangeSet changeSet = grid.ApplyChanges("det-change-" + index, grid.Version, changes[index]);
                NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1000d);
                repairTotal += repair.Metrics.repairedCells;
                work.Append("R:").Append(repair.Status).Append(':')
                    .Append(repair.Metrics.processedNodesOrCells).Append(':')
                    .Append(repair.Metrics.expandedNodes).Append(':')
                    .Append(repair.Metrics.relaxedEdges).Append(':')
                    .Append(repair.Metrics.repairedCells).Append('|');
                AppendPlan(planner.Plan(Request(grid, 0, start, goal, "det-plan-" + index, 1000d)), paths, work);
            }
            work.Append("TOTAL_REPAIR=").Append(repairTotal);
            SequenceSnapshot snapshot = new SequenceSnapshot { paths = paths.ToString(), work = work.ToString(), finalVersion = planner.GridVersion };
            planner.Reset();
            return snapshot;
        }

        private static void AppendPlan(NavigationPlanResult plan, StringBuilder paths, StringBuilder work)
        {
            paths.Append(plan.Status).Append(':').Append(FormatPath(plan.Path)).Append('|');
            work.Append("P:").Append(plan.Status).Append(':')
                .Append(plan.Metrics.processedNodesOrCells).Append(':')
                .Append(plan.Metrics.expandedNodes).Append(':')
                .Append(plan.Metrics.relaxedEdges).Append('|');
        }

        private static long ParseRepairTotal(string work)
        {
            const string marker = "TOTAL_REPAIR=";
            int index = work.LastIndexOf(marker, StringComparison.Ordinal);
            return index < 0 ? -1L : long.Parse(work.Substring(index + marker.Length));
        }

        private static void AssertPlanMatchesReference(
            IReadOnlyNavigationGrid grid,
            NavigationPlanResult actual,
            GridCoordinate start,
            GridCoordinate goal,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            string context,
            ref int assertions)
        {
            double expected = ReferenceShortestPathCost(grid, start, goal, connectivity, allowCornerCutting);
            if (double.IsPositiveInfinity(expected))
            {
                Assert(actual.Status == NavigationPlanStatus.NoPath && actual.FailureReason == NavigationFailureReason.NoReachablePath, "D* Lite disagreed with Dijkstra on unreachable case: " + context, ref assertions);
                Assert(actual.Path.Count == 0, "Unreachable D* Lite result contains a path: " + context, ref assertions);
            }
            else
            {
                Assert(actual.Status == NavigationPlanStatus.Succeeded, "D* Lite disagreed with Dijkstra on reachable case: " + context, ref assertions);
                Assert(IsValidPath(grid, actual.Path, connectivity, allowCornerCutting), "D* Lite returned an invalid path: " + context, ref assertions);
                Assert(Math.Abs(PathCost(grid, actual.Path) - expected) < 1e-8d, "D* Lite path cost differs from Dijkstra: " + context, ref assertions);
            }
        }

        private static double ReferenceShortestPathCost(
            IReadOnlyNavigationGrid grid,
            GridCoordinate start,
            GridCoordinate goal,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting)
        {
            if (!grid.IsWalkable(start) || !grid.IsWalkable(goal)) return double.PositiveInfinity;
            int count = checked(grid.Width * grid.Height);
            double[] distances = new double[count];
            bool[] visited = new bool[count];
            for (int index = 0; index < count; index++) distances[index] = double.PositiveInfinity;
            int startIndex = (start.y * grid.Width) + start.x;
            int goalIndex = (goal.y * grid.Width) + goal.x;
            distances[startIndex] = 0d;

            for (int iteration = 0; iteration < count; iteration++)
            {
                int currentIndex = -1;
                double currentDistance = double.PositiveInfinity;
                for (int index = 0; index < count; index++)
                {
                    if (!visited[index] && distances[index] < currentDistance)
                    {
                        currentIndex = index;
                        currentDistance = distances[index];
                    }
                }
                if (currentIndex < 0) break;
                if (currentIndex == goalIndex) return currentDistance;
                visited[currentIndex] = true;
                GridCoordinate current = new GridCoordinate(currentIndex % grid.Width, currentIndex / grid.Width);

                for (int deltaY = -1; deltaY <= 1; deltaY++)
                {
                    for (int deltaX = -1; deltaX <= 1; deltaX++)
                    {
                        if (deltaX == 0 && deltaY == 0) continue;
                        bool diagonal = deltaX != 0 && deltaY != 0;
                        if (connectivity == NavigationGridConnectivity.FourWay && diagonal) continue;
                        GridCoordinate neighbor = new GridCoordinate(current.x + deltaX, current.y + deltaY);
                        if (!grid.Contains(neighbor) || !grid.IsWalkable(neighbor)) continue;
                        if (diagonal && !allowCornerCutting)
                        {
                            if (!grid.IsWalkable(new GridCoordinate(current.x + deltaX, current.y)) ||
                                !grid.IsWalkable(new GridCoordinate(current.x, current.y + deltaY))) continue;
                        }
                        int neighborIndex = (neighbor.y * grid.Width) + neighbor.x;
                        double candidate = currentDistance + (grid.GetTraversalCost(neighbor) * (diagonal ? Math.Sqrt(2d) : 1d));
                        if (candidate < distances[neighborIndex]) distances[neighborIndex] = candidate;
                    }
                }
            }
            return double.PositiveInfinity;
        }

        private static DStarLitePlanner Initialize(
            IReadOnlyNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            params GridCoordinate[] goals)
        {
            DStarLitePlanner planner = new DStarLitePlanner();
            planner.Initialize(grid, new NavigationPlannerInitialization
            {
                runId = "gate7-test",
                goalSetId = "gate7-goals",
                goals = goals,
                connectivity = connectivity,
                allowDiagonalCornerCutting = allowCornerCutting,
                budgetMilliseconds = 1000d
            });
            return planner;
        }

        private static NavigationPlanRequest Request(
            IReadOnlyNavigationGrid grid,
            int agentId,
            GridCoordinate start,
            GridCoordinate goal,
            string requestId,
            double budgetMilliseconds)
        {
            return new NavigationPlanRequest
            {
                runId = "gate7-test",
                requestId = requestId,
                goalSetId = "gate7-goals",
                agentId = agentId,
                start = start,
                goal = goal,
                expectedGridVersion = grid.Version,
                budgetMilliseconds = budgetMilliseconds
            };
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

        private static uint NextDeterministic(ref uint state)
        {
            state = unchecked((state * 1664525u) + 1013904223u);
            return state;
        }

        private static bool Contains(IReadOnlyList<GridCoordinate> path, GridCoordinate coordinate)
        {
            for (int index = 0; index < path.Count; index++) if (path[index].Equals(coordinate)) return true;
            return false;
        }

        private static bool PathsEqual(IReadOnlyList<GridCoordinate> left, IReadOnlyList<GridCoordinate> right)
        {
            if (left.Count != right.Count) return false;
            for (int index = 0; index < left.Count; index++) if (!left[index].Equals(right[index])) return false;
            return true;
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

        private static bool IsValidPath(
            IReadOnlyNavigationGrid grid,
            IReadOnlyList<GridCoordinate> path,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting)
        {
            if (path.Count == 0) return false;
            for (int index = 0; index < path.Count; index++)
            {
                if (!grid.Contains(path[index]) || !grid.IsWalkable(path[index])) return false;
                if (index == 0) continue;
                GridCoordinate previous = path[index - 1];
                GridCoordinate current = path[index];
                int deltaX = Math.Abs(current.x - previous.x);
                int deltaY = Math.Abs(current.y - previous.y);
                if (deltaX > 1 || deltaY > 1 || deltaX + deltaY == 0) return false;
                if (connectivity == NavigationGridConnectivity.FourWay && deltaX + deltaY != 1) return false;
                if (deltaX == 1 && deltaY == 1 && !allowCornerCutting)
                {
                    GridCoordinate horizontal = new GridCoordinate(current.x, previous.y);
                    GridCoordinate vertical = new GridCoordinate(previous.x, current.y);
                    if (!grid.IsWalkable(horizontal) || !grid.IsWalkable(vertical)) return false;
                }
            }
            return true;
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
