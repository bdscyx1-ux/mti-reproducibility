using System;
using System.Collections.Generic;
using System.IO;
using DDM.Research.Experiments;
using DDM.Research.Grid;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate2SmokeVerification
    {
        [Serializable]
        private sealed class SmokeResult
        {
            public bool passed;
            public int assertionCount;
            public string scenarioFingerprintSha256;
            public string error;
        }

        public static void Run()
        {
            SmokeResult result = new SmokeResult();
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate2_Smoke.json");

            try
            {
                int assertions = 0;
                DeterministicScenarioDefinition firstDefinition = BuildScenario(false);
                DeterministicScenarioDefinition reorderedDefinition = BuildScenario(true);
                ResolvedDeterministicScenario first = firstDefinition.Resolve();
                ResolvedDeterministicScenario reordered = reorderedDefinition.Resolve();

                Assert(first.FingerprintSha256 == reordered.FingerprintSha256, "Canonical fingerprint changed when source arrays were reordered.", ref assertions);
                Assert(first.Agents[0].AgentId == 2 && first.Agents[1].AgentId == 7, "Agents were not normalized by agent id.", ref assertions);
                Assert(first.InitialGridOverrides[0].coordinate.Equals(new GridCoordinate(1, 1)), "Initial grid changes were not normalized by coordinate.", ref assertions);

                ResearchNavigationGrid grid = first.CreateGrid();
                Assert(grid.Version == 0, "Initial grid version must be zero.", ref assertions);
                Assert(!grid.IsWalkable(new GridCoordinate(1, 1)), "Initial blocked cell was not applied.", ref assertions);
                Assert(Math.Abs(grid.GetTraversalCost(new GridCoordinate(2, 1)) - 3f) < 0.0001f, "Initial traversal cost was not applied.", ref assertions);

                ResearchGridWorldTransform worldTransform = first.CreateWorldTransform();
                GridCoordinate roundTripCoordinate;
                Vector3 worldCenter = worldTransform.GridToWorldCenter(new GridCoordinate(1, 2), first.GridWidth, first.GridHeight);
                Assert(worldTransform.TryWorldToGrid(worldCenter, first.GridWidth, first.GridHeight, out roundTripCoordinate), "World center did not map into the grid.", ref assertions);
                Assert(roundTripCoordinate.Equals(new GridCoordinate(1, 2)), "Grid/world transform did not round-trip.", ref assertions);
                Assert(!worldTransform.TryWorldToGrid(new Vector3(float.NaN, 0f, 20f), first.GridWidth, first.GridHeight, out roundTripCoordinate), "Non-finite world coordinates were not rejected.", ref assertions);

                long versionBeforeInvalidChange = grid.Version;
                bool duplicateRejected = false;
                try
                {
                    grid.ApplyChanges("duplicate", grid.Version, new[]
                    {
                        Change(0, 0, true, 1f),
                        Change(0, 0, false, 1f)
                    });
                }
                catch (ArgumentException) { duplicateRejected = true; }
                Assert(duplicateRejected, "Duplicate coordinates were not rejected.", ref assertions);
                Assert(grid.Version == versionBeforeInvalidChange, "Rejected change mutated the grid version.", ref assertions);
                Assert(grid.IsWalkable(new GridCoordinate(0, 0)), "Rejected change partially mutated the grid.", ref assertions);

                DeterministicScenarioDefinition invalidDefinition = BuildScenario(false);
                invalidDefinition.initialGridOverrides = new[]
                {
                    Change(0, 0, false, 1f)
                };
                ScenarioValidationResult invalidResult = invalidDefinition.Validate();
                Assert(invalidResult.HasErrors, "Blocked agent start did not fail validation.", ref assertions);
                Assert(ContainsIssue(invalidResult, "blocked_start"), "Blocked-start validation code was not emitted.", ref assertions);

                DeterministicScenarioDefinition duplicateEventDefinition = BuildScenario(false);
                duplicateEventDefinition.scheduledChanges = new[]
                {
                    duplicateEventDefinition.scheduledChanges[0],
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = " toggle-corridor ",
                        simulationTick = 2,
                        order = 0,
                        changes = new[] { Change(1, 1, true, 1f) }
                    }
                };
                Assert(ContainsIssue(duplicateEventDefinition.Validate(), "duplicate_event_id"), "Event ids that collide after trimming were not rejected.", ref assertions);

                RecordingPlanner planner = new RecordingPlanner();
                ExperimentRunner runner = new ExperimentRunner("gate2-smoke", firstDefinition, planner);
                runner.Initialize();
                Assert(runner.State == ExperimentRunnerState.Initialized, "Runner did not enter Initialized state.", ref assertions);
                Assert(planner.Connectivity == NavigationGridConnectivity.FourWay && !planner.AllowDiagonalCornerCutting, "Runner did not forward grid topology to the planner.", ref assertions);
                runner.Begin();
                Assert(runner.State == ExperimentRunnerState.Running, "Runner did not enter Running state.", ref assertions);

                IReadOnlyList<ExperimentRepairObservation> tickZero = runner.AdvanceOneTick();
                Assert(runner.CurrentSimulationTick == 0 && tickZero.Count == 0, "Tick zero produced an unexpected event.", ref assertions);
                IReadOnlyList<ExperimentRepairObservation> tickOne = runner.AdvanceOneTick();
                Assert(tickOne.Count == 1 && tickOne[0].EventId == "toggle-corridor", "Tick-one event was not applied deterministically.", ref assertions);
                Assert(runner.Grid.Version == 1 && planner.GridVersion == 1, "Grid and planner versions diverged after repair.", ref assertions);

                NavigationPlanResult plan = runner.PlanForAgent(2, first.GetAgent(2).Start);
                Assert(plan.Status == NavigationPlanStatus.Succeeded, "Injected planner result was not returned.", ref assertions);
                Assert(planner.PlanCallCount == 1 && planner.RepairCallCount == 1, "Runner delegated an unexpected number of planner operations.", ref assertions);
                runner.Complete("smoke complete");
                Assert(runner.State == ExperimentRunnerState.Completed, "Runner did not enter Completed state.", ref assertions);
                runner.Dispose();
                Assert(runner.State == ExperimentRunnerState.Disposed, "Runner did not enter Disposed state.", ref assertions);

                RecordingPlanner loggingFailurePlanner = new RecordingPlanner();
                ExperimentRunner loggingFailureRunner = new ExperimentRunner(
                    "gate2-log-failure",
                    firstDefinition,
                    loggingFailurePlanner,
                    new SelectiveFailureLogSink("runner_lifecycle", "running"));
                loggingFailureRunner.Initialize();
                bool beginFailureObserved = false;
                try { loggingFailureRunner.Begin(); }
                catch (InvalidOperationException) { beginFailureObserved = true; }
                Assert(beginFailureObserved && loggingFailureRunner.State == ExperimentRunnerState.Faulted, "Begin logging failure did not fault the runner.", ref assertions);
                loggingFailureRunner.Dispose();

                result.passed = true;
                result.assertionCount = assertions;
                result.scenarioFingerprintSha256 = first.FingerprintSha256;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 2 smoke verification passed with " + assertions + " assertions. Fingerprint: " + first.FingerprintSha256);
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

        private static DeterministicScenarioDefinition BuildScenario(bool reverseArrays)
        {
            ScenarioAgentDefinition firstAgent = new ScenarioAgentDefinition
            {
                agentId = 7,
                start = new GridCoordinate(0, 0),
                goal = new GridCoordinate(3, 2)
            };
            ScenarioAgentDefinition secondAgent = new ScenarioAgentDefinition
            {
                agentId = 2,
                start = new GridCoordinate(0, 2),
                goal = new GridCoordinate(3, 2)
            };
            NavigationGridChange blocked = Change(1, 1, false, 1f);
            NavigationGridChange weighted = Change(2, 1, true, 3f);
            NavigationGridChange opened = Change(1, 1, true, 1f);
            NavigationGridChange closed = Change(2, 1, false, 3f);

            return new DeterministicScenarioDefinition
            {
                scenarioId = "gate2-smoke-scenario",
                randomSeed = 12345,
                gridWidth = 4,
                gridHeight = 3,
                defaultTraversalCost = 1f,
                worldOrigin = new Vector3(10f, 0f, 20f),
                cellSize = 2f,
                connectivity = NavigationGridConnectivity.FourWay,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 10,
                goalSetId = "shared-goal",
                initializationBudgetMilliseconds = 50d,
                defaultPlanBudgetMilliseconds = 5d,
                defaultRepairBudgetMilliseconds = 5d,
                agents = reverseArrays ? new[] { firstAgent, secondAgent } : new[] { secondAgent, firstAgent },
                initialGridOverrides = reverseArrays ? new[] { weighted, blocked } : new[] { blocked, weighted },
                scheduledChanges = new[]
                {
                    new ScheduledNavigationChangeDefinition
                    {
                        eventId = "toggle-corridor",
                        simulationTick = 1,
                        order = 0,
                        repairBudgetMilliseconds = 0d,
                        changes = reverseArrays ? new[] { closed, opened } : new[] { opened, closed }
                    }
                }
            };
        }

        private static NavigationGridChange Change(int x, int y, bool isWalkable, float traversalCost)
        {
            return new NavigationGridChange
            {
                coordinate = new GridCoordinate(x, y),
                isWalkable = isWalkable,
                traversalCost = traversalCost
            };
        }

        private static bool ContainsIssue(ScenarioValidationResult result, string code)
        {
            for (int index = 0; index < result.Issues.Count; index++)
            {
                if (string.Equals(result.Issues[index].Code, code, StringComparison.Ordinal)) return true;
            }
            return false;
        }

        private static void Assert(bool condition, string message, ref int assertionCount)
        {
            assertionCount++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void WriteResult(string resultPath, SmokeResult result)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(resultPath));
            File.WriteAllText(resultPath, JsonUtility.ToJson(result, true));
        }

        private sealed class RecordingPlanner : INavigationPlanner
        {
            private IReadOnlyNavigationGrid grid;

            public string AlgorithmId { get { return "GATE2-TEST-DOUBLE"; } }
            public NavigationPlannerCapabilities Capabilities { get { return NavigationPlannerCapabilities.IncrementalRepair; } }
            public long GridVersion { get; private set; }
            public int PlanCallCount { get; private set; }
            public int RepairCallCount { get; private set; }
            public NavigationGridConnectivity Connectivity { get; private set; }
            public bool AllowDiagonalCornerCutting { get; private set; }

            public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
            {
                this.grid = grid ?? throw new ArgumentNullException("grid");
                GridVersion = grid.Version;
                Connectivity = initialization.connectivity;
                AllowDiagonalCornerCutting = initialization.allowDiagonalCornerCutting;
                return new NavigationOperationMetrics();
            }

            public NavigationPlanResult Plan(NavigationPlanRequest request)
            {
                if (request.expectedGridVersion != GridVersion) throw new InvalidOperationException("Test-double request version mismatch.");
                PlanCallCount++;
                return new NavigationPlanResult(
                    NavigationPlanStatus.Succeeded,
                    NavigationFailureReason.None,
                    new[] { request.start, request.goal },
                    GridVersion,
                    new NavigationOperationMetrics());
            }

            public NavigationRepairResult ApplyChanges(NavigationChangeSet changeSet, double repairBudgetMilliseconds)
            {
                if (changeSet.previousGridVersion != GridVersion) throw new InvalidOperationException("Test-double repair version mismatch.");
                GridVersion = changeSet.newGridVersion;
                RepairCallCount++;
                return new NavigationRepairResult(
                    NavigationPlanStatus.Succeeded,
                    NavigationFailureReason.None,
                    GridVersion,
                    new NavigationOperationMetrics());
            }

            public void Reset()
            {
                grid = null;
                GridVersion = 0;
            }
        }

        private sealed class SelectiveFailureLogSink : IExperimentLogSink
        {
            private readonly string failedRecordType;
            private readonly string failedLifecycleState;

            public string FilePath { get { return string.Empty; } }
            public long EnqueuedCount { get; private set; }
            public long WrittenCount { get { return EnqueuedCount; } }

            public SelectiveFailureLogSink(string failedRecordType, string failedLifecycleState)
            {
                this.failedRecordType = failedRecordType;
                this.failedLifecycleState = failedLifecycleState;
            }

            public void Enqueue<T>(string recordType, string runId, T payload)
            {
                ExperimentRunnerLifecycleRecord lifecycle = payload as ExperimentRunnerLifecycleRecord;
                if (recordType == failedRecordType && lifecycle != null && lifecycle.state == failedLifecycleState)
                {
                    throw new InvalidOperationException("Intentional smoke-test logging failure.");
                }
                EnqueuedCount++;
            }

            public void Flush(TimeSpan timeout) { }
            public void Dispose() { }
        }
    }
}
