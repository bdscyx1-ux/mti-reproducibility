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
    public static class Gate9IncrementalFlowFieldVerification
    {
        private const double Tolerance = 1e-9d;

        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int initialFreshCffFieldCount;
            public int dynamicFreshCffFieldCount;
            public int comparedCellCount;
            public string deterministicSignatureSha256;
            public long deterministicRepairedCells;
            public long finalGridVersion;
            public int workloadPlanOperations;
            public int workloadRepairOperations;
            public int committedScenarioPlanOperations;
            public string error;
        }

        private sealed class HistoryStep
        {
            public string Id;
            public NavigationGridChange[] Changes;
        }

        private sealed class FreshCffField
        {
            public ResearchNavigationGrid Grid;
            public CorrectedFullRecomputeFlowFieldPlanner Planner;
        }

        private sealed class SequenceResult
        {
            public string Signature;
            public long RepairedCells;
            public long FinalVersion;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate9_IncrementalFlowField.json");
            VerificationResult result = new VerificationResult();
            try
            {
                int assertions = 0;
                TestBasicSemantics(ref assertions);
                TestGoalBlockRestore(ref assertions);
                TestBudgetInterruption(ref assertions);
                TestGeneratedFreshCffMatrix(result, ref assertions);
                TestDeterminism(result, ref assertions);
                TestLifecycleAndGoalInvalidation(ref assertions);
                TestSameTickWorkload(result, ref assertions);
                TestCommittedScenario(result, ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 9 IDFF verification passed with " + assertions + " assertions.");
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

        private static void TestBasicSemantics(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(5, 3, 1f, new[]
            {
                Change(1, 1, true, 3f),
                Change(2, 1, true, 2f),
                Change(3, 1, true, 3f)
            });
            ResearchNavigationGrid baseGrid = grid.Clone();
            GridCoordinate left = new GridCoordinate(0, 1);
            GridCoordinate right = new GridCoordinate(4, 1);
            GridCoordinate[] goals = { right, left };
            IncrementalDynamicFlowFieldPlanner planner = InitializeIdff(grid, NavigationGridConnectivity.FourWay, false, 1000d, goals);
            Assert(planner.AlgorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField, "IDFF algorithm id is incorrect.", ref assertions);
            Assert(planner.Capabilities == (NavigationPlannerCapabilities.SharedGoalField | NavigationPlannerCapabilities.IncrementalRepair), "IDFF capability flags are incorrect.", ref assertions);
            CompareWithFreshCff(planner, grid, baseGrid, new List<HistoryStep>(), NavigationGridConnectivity.FourWay, false, goals, "basic", ref assertions);

            IncrementalFlowFieldCellSnapshot center;
            Assert(planner.TryGetCellSnapshot(new GridCoordinate(2, 1), out center), "IDFF center snapshot is missing.", ref assertions);
            Assert(center.Reachable && center.OwnerGoal.Equals(left), "IDFF equal-cost ownership did not select canonical goal.", ref assertions);
            NavigationPlanResult compatible = planner.Plan(Request(grid, new GridCoordinate(2, 1), left, "basic-compatible", 1000d));
            NavigationPlanResult incompatible = planner.Plan(Request(grid, new GridCoordinate(2, 1), right, "basic-incompatible", 1000d));
            Assert(compatible.Status == NavigationPlanStatus.Succeeded && compatible.Path[compatible.Path.Count - 1].Equals(left), "IDFF compatible owner plan failed.", ref assertions);
            Assert(incompatible.Status == NavigationPlanStatus.InvalidRequest && incompatible.Path.Count == 0, "IDFF silently redirected an incompatible owner request.", ref assertions);

            NavigationChangeSet atomic = grid.ApplyChanges("basic-atomic", grid.Version, new[]
            {
                Change(2, 0, false, 1f),
                Change(2, 1, true, 0.5f),
                Change(2, 2, false, 1f)
            });
            NavigationRepairResult repair = planner.ApplyChanges(atomic, 1000d);
            Assert(repair.Status == NavigationPlanStatus.Succeeded && !planner.RepairPending && repair.Metrics.repairedCells > 0, "IDFF atomic repair failed.", ref assertions);
            List<HistoryStep> history = new List<HistoryStep> { Step(atomic) };
            CompareWithFreshCff(planner, grid, baseGrid, history, NavigationGridConnectivity.FourWay, false, goals, "basic atomic", ref assertions);
        }

        private static void TestGoalBlockRestore(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(7, 1, 1f);
            ResearchNavigationGrid baseGrid = grid.Clone();
            GridCoordinate left = new GridCoordinate(0, 0);
            GridCoordinate right = new GridCoordinate(6, 0);
            GridCoordinate[] goals = { right, left };
            IncrementalDynamicFlowFieldPlanner planner = InitializeIdff(grid, NavigationGridConnectivity.FourWay, false, 1000d, goals);
            List<HistoryStep> history = new List<HistoryStep>();

            NavigationChangeSet blocked = grid.ApplyChanges("block-goal", grid.Version, new[] { Change(0, 0, false, 1f) });
            Assert(planner.ApplyChanges(blocked, 1000d).Status == NavigationPlanStatus.Succeeded, "IDFF failed to block an active goal.", ref assertions);
            history.Add(Step(blocked));
            CompareWithFreshCff(planner, grid, baseGrid, history, NavigationGridConnectivity.FourWay, false, goals, "blocked goal", ref assertions);
            IncrementalFlowFieldCellSnapshot blockedGoal;
            planner.TryGetCellSnapshot(left, out blockedGoal);
            Assert(!blockedGoal.IsActiveGoal && !blockedGoal.Reachable, "Blocked IDFF goal remained active or reachable.", ref assertions);

            NavigationChangeSet restored = grid.ApplyChanges("restore-goal", grid.Version, new[] { Change(0, 0, true, 1f) });
            Assert(planner.ApplyChanges(restored, 1000d).Status == NavigationPlanStatus.Succeeded, "IDFF failed to restore a declared goal.", ref assertions);
            history.Add(Step(restored));
            CompareWithFreshCff(planner, grid, baseGrid, history, NavigationGridConnectivity.FourWay, false, goals, "restored goal", ref assertions);
            IncrementalFlowFieldCellSnapshot restoredGoal;
            planner.TryGetCellSnapshot(left, out restoredGoal);
            Assert(restoredGoal.IsActiveGoal && restoredGoal.IntegrationCost == 0d, "Restored IDFF goal did not reactivate.", ref assertions);
        }

        private static void TestBudgetInterruption(ref int assertions)
        {
            const int size = 96;
            ResearchNavigationGrid grid = new ResearchNavigationGrid(size, size, 1f);
            ResearchNavigationGrid baseGrid = grid.Clone();
            GridCoordinate goal = new GridCoordinate(size - 1, size - 1);
            IncrementalDynamicFlowFieldPlanner planner = new IncrementalDynamicFlowFieldPlanner();
            NavigationOperationMetrics initialization = planner.Initialize(grid, Initialization(NavigationGridConnectivity.EightWay, false, double.Epsilon, goal));
            Assert(initialization.budgetExceeded && !planner.RepairPending, "IDFF microscopic initialization budget did not complete with a soft overrun.", ref assertions);

            NavigationChangeSet changeSet = grid.ApplyChanges("budget-change", grid.Version, new[] { Change(48, 48, false, 1f) });
            NavigationRepairResult interrupted = planner.ApplyChanges(changeSet, double.Epsilon);
            Assert(interrupted.Status == NavigationPlanStatus.BudgetExceeded && planner.RepairPending, "IDFF microscopic repair budget did not leave resumable pending state.", ref assertions);
            Assert(planner.GridVersion == grid.Version && interrupted.GridVersion == grid.Version, "Pending IDFF repair did not retain the live grid version.", ref assertions);

            bool snapshotThrew = false;
            try { IncrementalFlowFieldCellSnapshot ignored; planner.TryGetCellSnapshot(new GridCoordinate(0, 0), out ignored); }
            catch (InvalidOperationException) { snapshotThrew = true; }
            Assert(snapshotThrew, "IDFF exposed a partial snapshot while repair was pending.", ref assertions);

            NavigationChangeSet wrongIdentity = new NavigationChangeSet
            {
                changeSetId = "wrong-budget-change",
                previousGridVersion = changeSet.previousGridVersion,
                newGridVersion = changeSet.newGridVersion,
                changes = changeSet.changes
            };
            Assert(planner.ApplyChanges(wrongIdentity, 1000d).Status == NavigationPlanStatus.InvalidRequest && planner.RepairPending, "IDFF accepted a mismatched pending change-set identity.", ref assertions);

            NavigationPlanResult tinyPlan = planner.Plan(Request(grid, new GridCoordinate(0, 0), goal, "pending-tiny-plan", double.Epsilon));
            Assert(tinyPlan.Status == NavigationPlanStatus.BudgetExceeded && tinyPlan.Path.Count == 0 && planner.RepairPending, "IDFF pending repair was not safely resumable through a tiny plan budget.", ref assertions);

            NavigationRepairResult resumed = planner.ApplyChanges(changeSet, 10000d);
            Assert(resumed.Status == NavigationPlanStatus.Succeeded && !planner.RepairPending, "IDFF exact pending change retry did not complete.", ref assertions);
            List<HistoryStep> history = new List<HistoryStep> { Step(changeSet) };
            CompareWithFreshCff(planner, grid, baseGrid, history, NavigationGridConnectivity.EightWay, false, new[] { goal }, "budget resumed", ref assertions);
            NavigationPlanResult recovered = planner.Plan(Request(grid, new GridCoordinate(0, 0), goal, "pending-recovered", 10000d));
            Assert(recovered.Status == NavigationPlanStatus.Succeeded, "IDFF plan did not recover after pending repair completion.", ref assertions);
            long repaired = interrupted.Metrics.repairedCells + tinyPlan.Metrics.repairedCells + resumed.Metrics.repairedCells;
            Assert(repaired > 0 && repaired <= (long)size * size, "IDFF interrupted repaired-cell accounting is not unique and bounded.", ref assertions);
        }

        private static void TestGeneratedFreshCffMatrix(VerificationResult result, ref int assertions)
        {
            int initialFields = 0;
            int dynamicFields = 0;
            int comparedCells = 0;
            NavigationGridConnectivity[] topologies =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] corners = { false, false, true };
            for (int caseIndex = 0; caseIndex < 24; caseIndex++)
            {
                GridCoordinate[] goalPool =
                {
                    new GridCoordinate(5, 4),
                    new GridCoordinate(0, 4),
                    new GridCoordinate(5, 0)
                };
                int goalCount = 1 + (caseIndex % 3);
                GridCoordinate[] goals = new GridCoordinate[goalCount];
                Array.Copy(goalPool, goals, goalCount);
                List<NavigationGridChange> overrides = new List<NavigationGridChange>();
                for (int y = 0; y < 5; y++)
                {
                    for (int x = 0; x < 6; x++)
                    {
                        GridCoordinate coordinate = new GridCoordinate(x, y);
                        if (Contains(goals, coordinate) || IsDynamicCoordinate(coordinate)) continue;
                        int code = (x * 17) + (y * 29) + (caseIndex * 13);
                        if (code % 19 == 0) overrides.Add(Change(x, y, false, 1f));
                        else if (code % 5 == 0) overrides.Add(Change(x, y, true, 1f + ((code % 7) * 0.25f)));
                    }
                }
                ResearchNavigationGrid grid = new ResearchNavigationGrid(6, 5, 1f, overrides);
                ResearchNavigationGrid baseGrid = grid.Clone();
                int topologyIndex = caseIndex % topologies.Length;
                IncrementalDynamicFlowFieldPlanner planner = InitializeIdff(grid, topologies[topologyIndex], corners[topologyIndex], 1000d, goals);
                List<HistoryStep> history = new List<HistoryStep>();
                comparedCells += CompareWithFreshCff(planner, grid, baseGrid, history, topologies[topologyIndex], corners[topologyIndex], goals, "generated initial " + caseIndex, ref assertions);
                initialFields++;

                NavigationGridChange[][] steps =
                {
                    new[] { Change(2, 2, true, 4f) },
                    new[] { Change(3, 2, false, 1f) },
                    new[] { Change(3, 2, true, 0.75f) },
                    new[] { Change(2, 2, true, 0.5f), Change(1, 3, false, 1f), Change(4, 1, true, 2.5f) }
                };
                for (int stepIndex = 0; stepIndex < steps.Length; stepIndex++)
                {
                    NavigationChangeSet set = grid.ApplyChanges("generated-" + caseIndex + "-" + stepIndex, grid.Version, steps[stepIndex]);
                    NavigationRepairResult repair = planner.ApplyChanges(set, 1000d);
                    Assert(repair.Status == NavigationPlanStatus.Succeeded && !planner.RepairPending, "Generated IDFF repair failed at case/step " + caseIndex + "/" + stepIndex + ".", ref assertions);
                    history.Add(Step(set));
                    comparedCells += CompareWithFreshCff(planner, grid, baseGrid, history, topologies[topologyIndex], corners[topologyIndex], goals, "generated dynamic " + caseIndex + "/" + stepIndex, ref assertions);
                    dynamicFields++;
                }
            }
            Assert(initialFields == 24 && dynamicFields == 96 && comparedCells == 3600, "Gate 9 generated fresh-C-FF matrix counts are incorrect.", ref assertions);
            result.initialFreshCffFieldCount = initialFields;
            result.dynamicFreshCffFieldCount = dynamicFields;
            result.comparedCellCount = comparedCells;
        }

        private static void TestDeterminism(VerificationResult result, ref int assertions)
        {
            SequenceResult first = RunDeterministicSequence();
            SequenceResult second = RunDeterministicSequence();
            Assert(first.Signature == second.Signature, "IDFF deterministic field/path/work signature changed across identical runs.", ref assertions);
            Assert(first.RepairedCells == second.RepairedCells && first.RepairedCells > 0, "IDFF repaired-cell totals are non-deterministic.", ref assertions);
            Assert(first.FinalVersion == second.FinalVersion && first.FinalVersion == 4, "IDFF deterministic final version is incorrect.", ref assertions);
            result.deterministicSignatureSha256 = Sha256Hex(first.Signature);
            result.deterministicRepairedCells = first.RepairedCells;
            result.finalGridVersion = first.FinalVersion;
        }

        private static SequenceResult RunDeterministicSequence()
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(8, 5, 1f, new[]
            {
                Change(3, 1, false, 1f), Change(3, 3, false, 1f), Change(4, 2, true, 2f)
            });
            GridCoordinate goal = new GridCoordinate(7, 2);
            IncrementalDynamicFlowFieldPlanner planner = InitializeIdff(grid, NavigationGridConnectivity.EightWay, false, 1000d, goal);
            StringBuilder signature = new StringBuilder();
            long repaired = 0L;
            AppendSignature(planner, grid, planner.Plan(Request(grid, new GridCoordinate(0, 2), goal, "det-plan-0", 1000d)), signature);
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
                repaired += repair.Metrics.repairedCells;
                signature.Append("R:").Append(repair.Status).Append(':').Append(repair.Metrics.processedNodesOrCells).Append(':').Append(repair.Metrics.expandedNodes).Append(':').Append(repair.Metrics.relaxedEdges).Append(':').Append(repair.Metrics.repairedCells).Append('|');
                AppendSignature(planner, grid, planner.Plan(Request(grid, new GridCoordinate(0, 2), goal, "det-plan-" + (index + 1), 1000d)), signature);
            }
            return new SequenceResult { Signature = signature.ToString(), RepairedCells = repaired, FinalVersion = planner.GridVersion };
        }

        private static void TestLifecycleAndGoalInvalidation(ref int assertions)
        {
            IncrementalDynamicFlowFieldPlanner planner = new IncrementalDynamicFlowFieldPlanner();
            bool beforeInitializeThrew = false;
            try { planner.Plan(new NavigationPlanRequest()); }
            catch (InvalidOperationException) { beforeInitializeThrew = true; }
            Assert(beforeInitializeThrew, "IDFF plan before initialization did not throw.", ref assertions);

            ResearchNavigationGrid grid = new ResearchNavigationGrid(4, 2, 1f);
            GridCoordinate goal = new GridCoordinate(3, 1);
            planner.Initialize(grid, Initialization(NavigationGridConnectivity.FourWay, false, 1000d, goal, goal));
            bool reinitializeThrew = false;
            try { planner.Initialize(grid, Initialization(NavigationGridConnectivity.FourWay, false, 1000d, goal)); }
            catch (InvalidOperationException) { reinitializeThrew = true; }
            Assert(reinitializeThrew, "IDFF reinitialized without reset.", ref assertions);

            NavigationPlanRequest wrongGoalSet = Request(grid, new GridCoordinate(0, 0), goal, "wrong-goal-set", 1000d);
            wrongGoalSet.goalSetId = "other-goals";
            Assert(planner.Plan(wrongGoalSet).Status == NavigationPlanStatus.InvalidRequest, "IDFF accepted a different goal-set id.", ref assertions);
            NavigationPlanRequest undeclared = Request(grid, new GridCoordinate(0, 0), new GridCoordinate(0, 1), "undeclared", 1000d);
            Assert(planner.Plan(undeclared).Status == NavigationPlanStatus.InvalidRequest, "IDFF accepted an undeclared goal.", ref assertions);
            planner.Reset();
            Assert(planner.GridVersion == 0 && !planner.RepairPending, "IDFF reset did not clear version/pending state.", ref assertions);
            planner.Initialize(grid, new NavigationPlannerInitialization
            {
                runId = "gate9-test", goalSetId = "new-goals", goals = new[] { new GridCoordinate(0, 1) },
                connectivity = NavigationGridConnectivity.FourWay, budgetMilliseconds = 1000d
            });
            Assert(planner.GridVersion == grid.Version, "IDFF could not initialize a new goal set after reset.", ref assertions);
        }

        private static void TestSameTickWorkload(VerificationResult result, ref int assertions)
        {
            DeterministicScenarioDefinition scenario = new DeterministicScenarioDefinition
            {
                schemaVersion = 1,
                scenarioId = "gate9-idff-same-tick",
                randomSeed = 9009,
                gridWidth = 6,
                gridHeight = 3,
                defaultTraversalCost = 1f,
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 4,
                goalSetId = "gate9-shared-goal",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition { agentId = 0, start = new GridCoordinate(0, 0), goal = new GridCoordinate(5, 1) },
                    new ScenarioAgentDefinition { agentId = 1, start = new GridCoordinate(0, 2), goal = new GridCoordinate(5, 1) }
                },
                initialGridOverrides = new[] { Change(3, 1, true, 2f) },
                scheduledChanges = new[]
                {
                    new ScheduledNavigationChangeDefinition { eventId = "same-a", simulationTick = 1, order = 0, repairBudgetMilliseconds = 1000d, changes = new[] { Change(2, 0, false, 1f) } },
                    new ScheduledNavigationChangeDefinition { eventId = "same-b", simulationTick = 1, order = 1, repairBudgetMilliseconds = 1000d, changes = new[] { Change(2, 2, false, 1f), Change(3, 1, true, 0.75f) } }
                }
            };
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run("gate9-same-tick-run", scenario, new IncrementalDynamicFlowFieldPlanner(), null);
            Assert(workload.completed && workload.algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField, "IDFF same-tick workload identity/completion is incorrect.", ref assertions);
            Assert(workload.planOperationCount == 4 && workload.repairOperationCount == 2 && workload.dynamicPlanningPhaseCount == 1 && workload.finalGridVersion == 2, "IDFF same-tick workload grouping is incorrect.", ref assertions);
            Assert(workload.succeededPlanCount == 4 && workload.invalidPlanCount == 0 && workload.failedPlanCount == 0 && workload.noPathPlanCount == 0, "IDFF same-tick workload plans did not all succeed.", ref assertions);
            Assert(workload.repairedCells > 0 && workload.repairedCells < 2L * 18L, "IDFF same-tick workload did not report an incremental repair footprint.", ref assertions);
            result.workloadPlanOperations = workload.planOperationCount;
            result.workloadRepairOperations = workload.repairOperationCount;
        }

        private static void TestCommittedScenario(VerificationResult result, ref int assertions)
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(Path.Combine(projectPath, "Research", "Scenarios", "dynamic_corridors_sparse_v1.scenario.json"));
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run("gate9-committed-scenario", loaded.Definition, new IncrementalDynamicFlowFieldPlanner(), null);
            Assert(workload.completed && workload.algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField, "Committed dynamic scenario did not complete with IDFF.", ref assertions);
            Assert(workload.planOperationCount == 8 && workload.repairOperationCount == 4 && workload.succeededPlanCount == 8, "Committed scenario IDFF operation counts are incorrect.", ref assertions);
            Assert(workload.invalidPlanCount == 0 && workload.failedPlanCount == 0 && workload.noPathPlanCount == 0 && workload.finalGridVersion == 4, "Committed scenario produced IDFF failures.", ref assertions);
            result.committedScenarioPlanOperations = workload.planOperationCount;
        }

        private static int CompareWithFreshCff(
            IncrementalDynamicFlowFieldPlanner actual,
            ResearchNavigationGrid liveGrid,
            ResearchNavigationGrid baseGrid,
            List<HistoryStep> history,
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            GridCoordinate[] goals,
            string context,
            ref int assertions)
        {
            FreshCffField expected = BuildFreshCff(baseGrid, history, connectivity, cornerCutting, goals);
            Assert(!actual.RepairPending && actual.GridVersion == liveGrid.Version && expected.Grid.Version == liveGrid.Version, "Field/version is not complete for comparison: " + context, ref assertions);
            int compared = 0;
            for (int y = 0; y < liveGrid.Height; y++)
            {
                for (int x = 0; x < liveGrid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    IncrementalFlowFieldCellSnapshot idff;
                    CorrectedFlowFieldCellSnapshot cff;
                    Assert(actual.TryGetCellSnapshot(coordinate, out idff), "Missing IDFF snapshot: " + context + " " + coordinate, ref assertions);
                    Assert(expected.Planner.TryGetCellSnapshot(coordinate, out cff), "Missing C-FF snapshot: " + context + " " + coordinate, ref assertions);
                    Assert(idff.Walkable == cff.Walkable && idff.Walkable == liveGrid.IsWalkable(coordinate), "Walkability mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(idff.Reachable == cff.Reachable, "Reachability mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(idff.IsActiveGoal == cff.IsActiveGoal, "Active-goal mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(idff.HasOwnerGoal == cff.HasOwnerGoal && (!idff.HasOwnerGoal || idff.OwnerGoal.Equals(cff.OwnerGoal)), "Owner mismatch: " + context + " " + coordinate, ref assertions);
                    Assert(idff.HasDirection == cff.HasDirection && (!idff.HasDirection || idff.Next.Equals(cff.Next)), "Direction mismatch: " + context + " " + coordinate, ref assertions);
                    Assert((double.IsPositiveInfinity(idff.IntegrationCost) && double.IsPositiveInfinity(cff.IntegrationCost)) || Math.Abs(idff.IntegrationCost - cff.IntegrationCost) < Tolerance, "Integration mismatch: " + context + " " + coordinate, ref assertions);
                    compared++;
                }
            }
            expected.Planner.Reset();
            return compared;
        }

        private static FreshCffField BuildFreshCff(
            ResearchNavigationGrid baseGrid,
            List<HistoryStep> history,
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            GridCoordinate[] goals)
        {
            ResearchNavigationGrid oracleGrid = baseGrid.Clone();
            CorrectedFullRecomputeFlowFieldPlanner planner = new CorrectedFullRecomputeFlowFieldPlanner();
            planner.Initialize(oracleGrid, OracleInitialization(connectivity, cornerCutting, goals));
            for (int index = 0; index < history.Count; index++)
            {
                HistoryStep step = history[index];
                NavigationChangeSet set = oracleGrid.ApplyChanges(step.Id, oracleGrid.Version, step.Changes);
                NavigationRepairResult repair = planner.ApplyChanges(set, 10000d);
                if (repair.Status != NavigationPlanStatus.Succeeded) throw new InvalidOperationException("Fresh C-FF replay failed at " + step.Id + ".");
            }
            return new FreshCffField { Grid = oracleGrid, Planner = planner };
        }

        private static void AppendSignature(IncrementalDynamicFlowFieldPlanner planner, IReadOnlyNavigationGrid grid, NavigationPlanResult plan, StringBuilder signature)
        {
            signature.Append("P:").Append(plan.Status).Append(':').Append(FormatPath(plan.Path)).Append(':').Append(plan.Metrics.processedNodesOrCells).Append('|');
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    IncrementalFlowFieldCellSnapshot cell;
                    planner.TryGetCellSnapshot(new GridCoordinate(x, y), out cell);
                    signature.Append(cell.Reachable ? cell.IntegrationCost.ToString("R") : "INF").Append('/');
                    if (cell.HasOwnerGoal) signature.Append(cell.OwnerGoal.x).Append(',').Append(cell.OwnerGoal.y);
                    signature.Append('/');
                    if (cell.HasDirection) signature.Append(cell.Next.x).Append(',').Append(cell.Next.y);
                    signature.Append(';');
                }
            }
        }

        private static IncrementalDynamicFlowFieldPlanner InitializeIdff(
            ResearchNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            double budget,
            params GridCoordinate[] goals)
        {
            IncrementalDynamicFlowFieldPlanner planner = new IncrementalDynamicFlowFieldPlanner();
            planner.Initialize(grid, Initialization(connectivity, cornerCutting, budget, goals));
            return planner;
        }

        private static NavigationPlannerInitialization Initialization(
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            double budget,
            params GridCoordinate[] goals)
        {
            return new NavigationPlannerInitialization
            {
                runId = "gate9-test",
                goalSetId = "gate9-goals",
                goals = goals,
                connectivity = connectivity,
                allowDiagonalCornerCutting = cornerCutting,
                budgetMilliseconds = budget
            };
        }

        private static NavigationPlannerInitialization OracleInitialization(
            NavigationGridConnectivity connectivity,
            bool cornerCutting,
            GridCoordinate[] goals)
        {
            return new NavigationPlannerInitialization
            {
                runId = "gate9-oracle",
                goalSetId = "gate9-oracle-goals",
                goals = goals,
                connectivity = connectivity,
                allowDiagonalCornerCutting = cornerCutting,
                budgetMilliseconds = 10000d
            };
        }

        private static NavigationPlanRequest Request(IReadOnlyNavigationGrid grid, GridCoordinate start, GridCoordinate goal, string requestId, double budget)
        {
            return new NavigationPlanRequest
            {
                runId = "gate9-test",
                requestId = requestId,
                goalSetId = "gate9-goals",
                agentId = 0,
                start = start,
                goal = goal,
                expectedGridVersion = grid.Version,
                budgetMilliseconds = budget
            };
        }

        private static HistoryStep Step(NavigationChangeSet set)
        {
            return new HistoryStep { Id = set.changeSetId, Changes = (NavigationGridChange[])set.changes.Clone() };
        }

        private static NavigationGridChange Change(int x, int y, bool walkable, float cost)
        {
            return new NavigationGridChange { coordinate = new GridCoordinate(x, y), isWalkable = walkable, traversalCost = cost };
        }

        private static bool Contains(GridCoordinate[] coordinates, GridCoordinate value)
        {
            for (int index = 0; index < coordinates.Length; index++) if (coordinates[index].Equals(value)) return true;
            return false;
        }

        private static bool IsDynamicCoordinate(GridCoordinate value)
        {
            return value.Equals(new GridCoordinate(2, 2)) || value.Equals(new GridCoordinate(3, 2)) ||
                   value.Equals(new GridCoordinate(1, 3)) || value.Equals(new GridCoordinate(4, 1));
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
                return BitConverter.ToString(sha256.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", string.Empty).ToLowerInvariant();
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
