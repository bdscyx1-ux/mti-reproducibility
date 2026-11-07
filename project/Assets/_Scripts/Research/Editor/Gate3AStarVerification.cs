using System;
using System.Collections.Generic;
using System.IO;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate3AStarVerification
    {
        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public string deterministicPath;
            public long deterministicExpandedNodes;
            public long dynamicGridVersion;
            public int referenceCaseCount;
            public string error;
        }

        public static void Run()
        {
            VerificationResult result = new VerificationResult();
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate3_AStar.json");

            try
            {
                int assertions = 0;
                TestWeightedFourWayAndDeterminism(result, ref assertions);
                TestNoReachablePath(ref assertions);
                TestEightWayCornerPolicy(ref assertions);
                TestVersionAndRequestValidation(ref assertions);
                TestBudgetExceeded(ref assertions);
                TestExperimentRunnerIntegration(result, ref assertions);
                TestReferenceOptimality(result, ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 3 A*-R verification passed with " + assertions + " assertions. Path: " + result.deterministicPath);
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

        private static void TestWeightedFourWayAndDeterminism(VerificationResult verification, ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(5, 3, 1f, new[]
            {
                Change(1, 1, true, 10f),
                Change(2, 1, true, 10f),
                Change(3, 1, true, 10f)
            });
            GridCoordinate start = new GridCoordinate(0, 1);
            GridCoordinate goal = new GridCoordinate(4, 1);
            AStarRepeatedPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);

            Assert(planner.AlgorithmId == NavigationAlgorithmIds.AStarRepeated, "A*-R algorithm id is incorrect.", ref assertions);
            Assert(planner.Capabilities == NavigationPlannerCapabilities.FullRecompute, "A*-R capability flags are incorrect.", ref assertions);

            NavigationPlanResult first = planner.Plan(Request(grid, start, goal, "weighted-1", 1000d));
            Assert(first.Status == NavigationPlanStatus.Succeeded && first.FailureReason == NavigationFailureReason.None, "Weighted four-way plan did not succeed.", ref assertions);
            Assert(first.Path.Count == 7, "Weighted plan did not take the six-edge detour.", ref assertions);
            Assert(!Contains(first.Path, new GridCoordinate(1, 1)) && !Contains(first.Path, new GridCoordinate(2, 1)) && !Contains(first.Path, new GridCoordinate(3, 1)), "Weighted plan crossed an avoidable expensive cell.", ref assertions);
            Assert(Math.Abs(PathCost(grid, first.Path) - 6d) < 1e-9d, "Weighted path cost is not optimal.", ref assertions);
            Assert(IsValidPath(grid, first.Path, NavigationGridConnectivity.FourWay, false), "Weighted result contains an invalid step.", ref assertions);
            Assert(first.Metrics.expandedNodes > 0 && first.Metrics.relaxedEdges > 0 && first.Metrics.processedNodesOrCells >= 15, "A*-R metrics did not record search work.", ref assertions);
            Assert(!first.Metrics.budgetExceeded && first.Metrics.managedAllocatedBytes >= 0, "A*-R reported an invalid managed-allocation delta.", ref assertions);

            NavigationPlanResult second = planner.Plan(Request(grid, start, goal, "weighted-2", 1000d));
            Assert(PathsEqual(first.Path, second.Path), "Repeated A* produced a different path for identical input.", ref assertions);
            Assert(first.Metrics.expandedNodes == second.Metrics.expandedNodes && first.Metrics.relaxedEdges == second.Metrics.relaxedEdges, "Repeated A* produced non-deterministic work counts.", ref assertions);
            Assert(second.Metrics.cumulativePlanningCpuMilliseconds >= first.Metrics.cumulativePlanningCpuMilliseconds + second.Metrics.elapsedCpuMilliseconds, "A*-R cumulative planning time did not advance monotonically.", ref assertions);

            NavigationPlanResult stationary = planner.Plan(Request(grid, goal, goal, "stationary", 1000d));
            Assert(stationary.Status == NavigationPlanStatus.Succeeded && stationary.Path.Count == 1 && stationary.Path[0].Equals(goal), "Start-equals-goal was not handled as a one-cell path.", ref assertions);

            verification.deterministicPath = FormatPath(first.Path);
            verification.deterministicExpandedNodes = first.Metrics.expandedNodes;
            planner.Reset();
        }

        private static void TestNoReachablePath(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(3, 3, 1f, new[]
            {
                Change(1, 0, false, 1f),
                Change(1, 1, false, 1f),
                Change(1, 2, false, 1f)
            });
            GridCoordinate goal = new GridCoordinate(2, 1);
            AStarRepeatedPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationPlanResult plan = planner.Plan(Request(grid, new GridCoordinate(0, 1), goal, "no-path", 1000d));
            Assert(plan.Status == NavigationPlanStatus.NoPath && plan.FailureReason == NavigationFailureReason.NoReachablePath, "Disconnected grid did not return NoReachablePath.", ref assertions);
            Assert(plan.Path.Count == 0, "No-path result unexpectedly contains coordinates.", ref assertions);
            planner.Reset();
        }

        private static void TestEightWayCornerPolicy(ref int assertions)
        {
            GridCoordinate start = new GridCoordinate(0, 0);
            GridCoordinate goal = new GridCoordinate(2, 2);
            ResearchNavigationGrid openGrid = new ResearchNavigationGrid(3, 3);
            AStarRepeatedPlanner diagonalPlanner = Initialize(openGrid, NavigationGridConnectivity.EightWay, false, goal);
            NavigationPlanResult diagonal = diagonalPlanner.Plan(Request(openGrid, start, goal, "diagonal", 1000d));
            Assert(diagonal.Status == NavigationPlanStatus.Succeeded && diagonal.Path.Count == 3, "Eight-way A* did not use the two-diagonal route.", ref assertions);
            Assert(Math.Abs(PathCost(openGrid, diagonal.Path) - (2d * Math.Sqrt(2d))) < 1e-9d, "Eight-way diagonal cost is incorrect.", ref assertions);
            diagonalPlanner.Reset();

            ResearchNavigationGrid cornerGrid = new ResearchNavigationGrid(2, 2, 1f, new[]
            {
                Change(1, 0, false, 1f),
                Change(0, 1, false, 1f)
            });
            GridCoordinate cornerGoal = new GridCoordinate(1, 1);
            AStarRepeatedPlanner strictPlanner = Initialize(cornerGrid, NavigationGridConnectivity.EightWay, false, cornerGoal);
            NavigationPlanResult strict = strictPlanner.Plan(Request(cornerGrid, start, cornerGoal, "strict-corner", 1000d));
            Assert(strict.Status == NavigationPlanStatus.NoPath, "Diagonal corner cutting occurred while disabled.", ref assertions);
            strictPlanner.Reset();

            AStarRepeatedPlanner permissivePlanner = Initialize(cornerGrid, NavigationGridConnectivity.EightWay, true, cornerGoal);
            NavigationPlanResult permissive = permissivePlanner.Plan(Request(cornerGrid, start, cornerGoal, "permissive-corner", 1000d));
            Assert(permissive.Status == NavigationPlanStatus.Succeeded && permissive.Path.Count == 2, "Diagonal corner cutting did not occur while enabled.", ref assertions);
            permissivePlanner.Reset();
        }

        private static void TestVersionAndRequestValidation(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(3, 2);
            GridCoordinate start = new GridCoordinate(0, 0);
            GridCoordinate goal = new GridCoordinate(2, 0);
            AStarRepeatedPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationChangeSet changeSet = grid.ApplyChanges("block-center", 0, new[] { Change(1, 0, false, 1f) });

            NavigationPlanResult stale = planner.Plan(Request(grid, start, goal, "stale", 1000d));
            Assert(stale.Status == NavigationPlanStatus.InvalidRequest && stale.FailureReason == NavigationFailureReason.StaleGridVersion, "A stale planner/grid version was not rejected.", ref assertions);

            NavigationRepairResult repair = planner.ApplyChanges(changeSet, 1000d);
            Assert(repair.Status == NavigationPlanStatus.Succeeded && repair.GridVersion == grid.Version && planner.GridVersion == grid.Version, "A*-R did not acknowledge a valid change set.", ref assertions);
            Assert(repair.Metrics.repairedCells == 0, "A*-R incorrectly claimed incremental cell repair.", ref assertions);

            NavigationPlanRequest wrongRun = Request(grid, start, goal, "wrong-run", 1000d);
            wrongRun.runId = "another-run";
            NavigationPlanResult invalid = planner.Plan(wrongRun);
            Assert(invalid.Status == NavigationPlanStatus.InvalidRequest && invalid.FailureReason == NavigationFailureReason.InvalidRequest, "Mismatched run identity was not rejected.", ref assertions);
            planner.Reset();
        }

        private static void TestBudgetExceeded(ref int assertions)
        {
            ResearchNavigationGrid grid = new ResearchNavigationGrid(128, 128);
            GridCoordinate goal = new GridCoordinate(127, 127);
            AStarRepeatedPlanner planner = Initialize(grid, NavigationGridConnectivity.FourWay, false, goal);
            NavigationPlanResult result = planner.Plan(Request(grid, new GridCoordinate(0, 0), goal, "budget", double.Epsilon));
            Assert(result.Status == NavigationPlanStatus.BudgetExceeded && result.FailureReason == NavigationFailureReason.PlanningBudgetExceeded, "A microscopic budget did not produce BudgetExceeded.", ref assertions);
            Assert(result.Metrics.budgetExceeded && result.Path.Count == 0, "Budget-exceeded metrics or path are incorrect.", ref assertions);
            planner.Reset();
        }

        private static void TestExperimentRunnerIntegration(VerificationResult verification, ref int assertions)
        {
            DeterministicScenarioDefinition definition = new DeterministicScenarioDefinition
            {
                scenarioId = "gate3-runner",
                randomSeed = 3003,
                gridWidth = 5,
                gridHeight = 3,
                connectivity = NavigationGridConnectivity.FourWay,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 4,
                goalSetId = "gate3-goal",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition
                    {
                        agentId = 0,
                        start = new GridCoordinate(0, 1),
                        goal = new GridCoordinate(4, 1)
                    }
                },
                scheduledChanges = new[]
                {
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = "block-middle",
                        simulationTick = 0,
                        order = 0,
                        changes = new[] { Change(2, 1, false, 1f) }
                    }
                }
            };

            AStarRepeatedPlanner planner = new AStarRepeatedPlanner();
            ExperimentRunner runner = new ExperimentRunner("gate3-run", definition, planner);
            runner.Initialize();
            runner.Begin();
            NavigationPlanResult before = runner.PlanForAgent(0, new GridCoordinate(0, 1), "before-change", 1000d);
            Assert(before.Status == NavigationPlanStatus.Succeeded && Contains(before.Path, new GridCoordinate(2, 1)), "Pre-change A*-R path did not use the open middle cell.", ref assertions);

            IReadOnlyList<ExperimentRepairObservation> observations = runner.AdvanceOneTick();
            Assert(observations.Count == 1 && observations[0].Result.Status == NavigationPlanStatus.Succeeded, "Runner did not deliver the dynamic event to A*-R.", ref assertions);
            NavigationPlanResult after = runner.PlanForAgent(0, new GridCoordinate(0, 1), "after-change", 1000d);
            Assert(after.Status == NavigationPlanStatus.Succeeded && !Contains(after.Path, new GridCoordinate(2, 1)), "Post-change A*-R path did not avoid the blocked middle cell.", ref assertions);
            Assert(IsValidPath(runner.Grid, after.Path, NavigationGridConnectivity.FourWay, false), "Post-change A*-R path is invalid.", ref assertions);
            Assert(runner.Grid.Version == 1 && planner.GridVersion == 1, "Runner and A*-R versions diverged after a dynamic event.", ref assertions);

            verification.dynamicGridVersion = runner.Grid.Version;
            runner.Complete("gate3 verification complete");
            runner.Dispose();
            Assert(runner.State == ExperimentRunnerState.Disposed, "Integrated A*-R runner did not dispose cleanly.", ref assertions);
        }

        private static void TestReferenceOptimality(VerificationResult verification, ref int assertions)
        {
            NavigationGridConnectivity[] connectivities =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            bool[] cornerPolicies = { false, false, true };
            uint randomState = 0x6d2b79f5u;
            int caseCount = 0;

            for (int topology = 0; topology < connectivities.Length; topology++)
            {
                for (int caseIndex = 0; caseIndex < 12; caseIndex++)
                {
                    const int width = 6;
                    const int height = 5;
                    GridCoordinate start = new GridCoordinate(0, 0);
                    GridCoordinate goal = new GridCoordinate(width - 1, height - 1);
                    List<NavigationGridChange> cells = new List<NavigationGridChange>();
                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            uint walkabilityRoll = NextDeterministic(ref randomState);
                            uint costRoll = NextDeterministic(ref randomState);
                            GridCoordinate coordinate = new GridCoordinate(x, y);
                            bool endpoint = coordinate.Equals(start) || coordinate.Equals(goal);
                            cells.Add(Change(x, y, endpoint || (walkabilityRoll % 100u) >= 25u, 1f + ((costRoll % 7u) * 0.25f)));
                        }
                    }

                    ResearchNavigationGrid grid = new ResearchNavigationGrid(width, height, 1f, cells);
                    AStarRepeatedPlanner planner = Initialize(grid, connectivities[topology], cornerPolicies[topology], goal);
                    NavigationPlanResult actual = planner.Plan(Request(grid, start, goal, "reference-" + topology + "-" + caseIndex, 1000d));
                    double expectedCost = ReferenceShortestPathCost(grid, start, goal, connectivities[topology], cornerPolicies[topology]);

                    if (double.IsPositiveInfinity(expectedCost))
                    {
                        Assert(actual.Status == NavigationPlanStatus.NoPath && actual.FailureReason == NavigationFailureReason.NoReachablePath, "A*-R disagreed with reference Dijkstra on an unreachable case.", ref assertions);
                        Assert(actual.Path.Count == 0, "Unreachable reference case returned a non-empty A* path.", ref assertions);
                    }
                    else
                    {
                        Assert(actual.Status == NavigationPlanStatus.Succeeded, "A*-R disagreed with reference Dijkstra on a reachable case.", ref assertions);
                        Assert(IsValidPath(grid, actual.Path, connectivities[topology], cornerPolicies[topology]), "Reference comparison produced an invalid A* path.", ref assertions);
                        Assert(Math.Abs(PathCost(grid, actual.Path) - expectedCost) < 1e-8d, "A*-R path cost differs from independent reference Dijkstra.", ref assertions);
                    }

                    planner.Reset();
                    caseCount++;
                }
            }

            verification.referenceCaseCount = caseCount;
            Assert(caseCount == 36, "Reference comparison did not execute every planned case.", ref assertions);
        }

        private static double ReferenceShortestPathCost(
            IReadOnlyNavigationGrid grid,
            GridCoordinate start,
            GridCoordinate goal,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting)
        {
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

        private static uint NextDeterministic(ref uint state)
        {
            state = unchecked((state * 1664525u) + 1013904223u);
            return state;
        }

        private static AStarRepeatedPlanner Initialize(
            IReadOnlyNavigationGrid grid,
            NavigationGridConnectivity connectivity,
            bool allowCornerCutting,
            params GridCoordinate[] goals)
        {
            AStarRepeatedPlanner planner = new AStarRepeatedPlanner();
            planner.Initialize(grid, new NavigationPlannerInitialization
            {
                runId = "gate3-test",
                goalSetId = "gate3-goals",
                goals = goals,
                connectivity = connectivity,
                allowDiagonalCornerCutting = allowCornerCutting,
                budgetMilliseconds = 1000d
            });
            return planner;
        }

        private static NavigationPlanRequest Request(
            IReadOnlyNavigationGrid grid,
            GridCoordinate start,
            GridCoordinate goal,
            string requestId,
            double budgetMilliseconds)
        {
            return new NavigationPlanRequest
            {
                runId = "gate3-test",
                requestId = requestId,
                goalSetId = "gate3-goals",
                agentId = 0,
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

        private static bool IsValidPath(IReadOnlyNavigationGrid grid, IReadOnlyList<GridCoordinate> path, NavigationGridConnectivity connectivity, bool allowCornerCutting)
        {
            if (path.Count == 0) return false;
            for (int index = 0; index < path.Count; index++)
            {
                if (!grid.Contains(path[index]) || !grid.IsWalkable(path[index])) return false;
                if (index == 0) continue;
                int deltaX = Math.Abs(path[index].x - path[index - 1].x);
                int deltaY = Math.Abs(path[index].y - path[index - 1].y);
                if (deltaX > 1 || deltaY > 1 || deltaX + deltaY == 0) return false;
                if (connectivity == NavigationGridConnectivity.FourWay && deltaX + deltaY != 1) return false;
                if (deltaX == 1 && deltaY == 1 && !allowCornerCutting)
                {
                    GridCoordinate horizontal = new GridCoordinate(path[index - 1].x + (path[index].x - path[index - 1].x), path[index - 1].y);
                    GridCoordinate vertical = new GridCoordinate(path[index - 1].x, path[index - 1].y + (path[index].y - path[index - 1].y));
                    if (!grid.IsWalkable(horizontal) || !grid.IsWalkable(vertical)) return false;
                }
            }
            return true;
        }

        private static string FormatPath(IReadOnlyList<GridCoordinate> path)
        {
            System.Text.StringBuilder builder = new System.Text.StringBuilder();
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
