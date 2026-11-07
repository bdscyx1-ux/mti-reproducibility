using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using DDM.Research.Analysis;
using DDM.Research.Experiments;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate10FairnessVerification
    {
        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int profileCount;
            public int sharedGoalClassificationCount;
            public int heterogeneousClassificationCount;
            public int workloadPlanOperations;
            public int workloadRepairOperations;
            public int dynamicPhaseCount;
            public long totalProcessedNodesOrCells;
            public long dynamicProcessedNodesOrCells;
            public bool legacyAggregationAccepted;
            public int rejectedMixedIdentityCount;
            public string error;
        }

        private static int assertions;
        private static int rejectedMixedIdentities;

        public static void Run()
        {
            string outputPath = Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Research", "Verification", "Gate10_Fairness.json");
            VerificationResult result = new VerificationResult();
            try
            {
                assertions = 0;
                rejectedMixedIdentities = 0;
                VerifyProfiles();
                VerifyCohorts();
                PlanningWorkloadResult workload = VerifyWorkloadAccounting();
                bool legacyAccepted = VerifyAggregationIdentity(workload);

                result.passed = true;
                result.assertionCount = assertions;
                result.profileCount = PlanningFairnessContracts.AuthorizedProfiles.Count;
                result.sharedGoalClassificationCount = 4;
                result.heterogeneousClassificationCount = 4;
                result.workloadPlanOperations = workload.planOperationCount;
                result.workloadRepairOperations = workload.repairOperationCount;
                result.dynamicPhaseCount = workload.dynamicPlanningPhaseCount;
                result.totalProcessedNodesOrCells = workload.processedNodesOrCells;
                result.dynamicProcessedNodesOrCells = workload.dynamicProcessedNodesOrCells;
                result.legacyAggregationAccepted = legacyAccepted;
                result.rejectedMixedIdentityCount = rejectedMixedIdentities;
                result.error = string.Empty;
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.assertionCount = assertions;
                result.error = exception.ToString();
                WriteJson(outputPath, result);
                Debug.LogException(exception);
                throw;
            }

            WriteJson(outputPath, result);
            Debug.Log("Gate 10 fairness verification passed. Assertions: " + assertions.ToString(CultureInfo.InvariantCulture));
        }

        private static void VerifyProfiles()
        {
            IReadOnlyList<PlanningAlgorithmFairnessProfile> profiles = PlanningFairnessContracts.AuthorizedProfiles;
            Assert(profiles.Count == 4, "Exactly four fairness profiles are required.");
            string[] algorithms =
            {
                NavigationAlgorithmIds.AStarRepeated,
                NavigationAlgorithmIds.DStarLite,
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                NavigationAlgorithmIds.IncrementalDynamicFlowField
            };
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> specifications = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < algorithms.Length; index++)
            {
                PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithms[index]);
                Assert(profile.AlgorithmId == algorithms[index], "Profile algorithm order differs.");
                Assert(ids.Add(profile.AlgorithmId), "Duplicate algorithm profile.");
                Assert(specifications.Add(profile.SpecificationId), "Duplicate specification id.");
                Assert(profile.SpecificationRelativePath.StartsWith("Research/", StringComparison.Ordinal), "Specification path is not research-relative.");
                Assert(profile.ImplementationRelativePath.StartsWith("Assets/_Scripts/Research/Algorithms/", StringComparison.Ordinal), "Implementation path is outside the algorithm directory.");
                Assert(profile.ProcessedWorkUnit == "nodes" || profile.ProcessedWorkUnit == "cells", "Processed-work unit is invalid.");
                Assert(!string.IsNullOrWhiteSpace(profile.NativeMetricsSemanticsId), "Native metric semantics id is missing.");
            }
            Assert(PlanningFairnessContracts.GetProfile(NavigationAlgorithmIds.AStarRepeated).StateModelId == "stateless-per-request-v1", "A*-R state model differs.");
            Assert(PlanningFairnessContracts.GetProfile(NavigationAlgorithmIds.DStarLite).UsesPerAgentState, "D* Lite must declare per-agent state.");
            Assert(PlanningFairnessContracts.GetProfile(NavigationAlgorithmIds.CorrectedFullRecomputeFlowField).UsesSharedField, "C-FF must declare a shared field.");
            Assert(PlanningFairnessContracts.GetProfile(NavigationAlgorithmIds.IncrementalDynamicFlowField).UsesSharedField, "IDFF must declare a shared field.");
            ExpectException<NotSupportedException>(() => PlanningFairnessContracts.GetProfile("UNSUPPORTED"), "Unknown profile accepted.");
        }

        private static void VerifyCohorts()
        {
            ResolvedDeterministicScenario shared = BuildScenario(true, true).Resolve();
            ResolvedDeterministicScenario heterogeneous = BuildScenario(false, true).Resolve();
            string[] algorithms =
            {
                NavigationAlgorithmIds.AStarRepeated,
                NavigationAlgorithmIds.DStarLite,
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                NavigationAlgorithmIds.IncrementalDynamicFlowField
            };

            for (int index = 0; index < algorithms.Length; index++)
            {
                PlanningFairnessClassification classification = PlanningFairnessContracts.Classify(shared, algorithms[index]);
                Assert(classification.GoalCohortId == PlanningFairnessContracts.GoalCohortSingleShared, "Shared goal cohort differs.");
                Assert(classification.ComparisonCohortId == PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "Shared comparison cohort differs.");
                Assert(classification.DistinctGoalCount == 1, "Shared distinct-goal count differs.");
                PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(algorithms[index], classification.ComparisonCohortId);
            }

            PlanningFairnessClassification astar = PlanningFairnessContracts.Classify(heterogeneous, NavigationAlgorithmIds.AStarRepeated);
            PlanningFairnessClassification dstar = PlanningFairnessContracts.Classify(heterogeneous, NavigationAlgorithmIds.DStarLite);
            PlanningFairnessClassification cff = PlanningFairnessContracts.Classify(heterogeneous, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField);
            PlanningFairnessClassification idff = PlanningFairnessContracts.Classify(heterogeneous, NavigationAlgorithmIds.IncrementalDynamicFlowField);
            Assert(astar.ComparisonCohortId == PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort, "A*-R heterogeneous cohort differs.");
            Assert(dstar.ComparisonCohortId == PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort, "D* Lite heterogeneous cohort differs.");
            Assert(cff.ComparisonCohortId == PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort, "C-FF heterogeneous cohort differs.");
            Assert(idff.ComparisonCohortId == PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort, "IDFF heterogeneous cohort differs.");
            Assert(astar.PersistentStateInstanceCount == 0 && astar.SharedFieldInstanceCount == 0, "A*-R state counts differ.");
            Assert(dstar.PersistentStateInstanceCount == 2 && dstar.SharedFieldInstanceCount == 0, "D* Lite state counts differ.");
            Assert(cff.PersistentStateInstanceCount == 1 && cff.SharedFieldInstanceCount == 1, "C-FF state counts differ.");
            Assert(idff.PersistentStateInstanceCount == 1 && idff.SharedFieldInstanceCount == 1, "IDFF state counts differ.");
            ExpectException<InvalidOperationException>(
                () => PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(NavigationAlgorithmIds.AStarRepeated, PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort),
                "A*-R was accepted into the grouped-field cohort.");
            ExpectException<InvalidOperationException>(
                () => PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(NavigationAlgorithmIds.IncrementalDynamicFlowField, PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort),
                "IDFF was accepted into the per-agent cohort.");
        }

        private static PlanningWorkloadResult VerifyWorkloadAccounting()
        {
            DeterministicScenarioDefinition definition = BuildScenario(true, true);
            CapturingLogSink sink = new CapturingLogSink();
            PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run(
                "gate10-accounting",
                definition,
                new ScriptedMetricsPlanner(NavigationAlgorithmIds.AStarRepeated),
                sink,
                BuildProvenance(NavigationAlgorithmIds.AStarRepeated));

            Assert(workload.completed, "Workload did not complete.");
            Assert(workload.planOperationCount == 6, "Plan count differs.");
            Assert(workload.repairOperationCount == 3, "Repair count differs.");
            Assert(workload.dynamicPlanningPhaseCount == 2, "Dynamic phase count differs.");
            AssertNearly(workload.initializationMilliseconds, 1d, "Initialization elapsed differs.");
            Assert(workload.initializationProcessedNodesOrCells == 10L, "Initialization work differs.");
            AssertNearly(workload.initialPlanningMilliseconds, 5d, "Initial planning elapsed differs.");
            Assert(workload.initialPlanningProcessedNodesOrCells == 50L, "Initial planning work differs.");
            AssertNearly(workload.dynamicHandlingTotalMilliseconds, 49d, "Dynamic total elapsed differs.");
            Assert(workload.dynamicProcessedNodesOrCells == 490L, "Dynamic work differs.");
            Assert(workload.dynamicManagedAllocatedBytes == 490L, "Dynamic allocation differs.");
            AssertNearly(workload.totalPlannerElapsedMilliseconds, 55d, "Total elapsed differs.");
            Assert(workload.processedNodesOrCells == 550L, "Total work differs.");
            AssertNearly(workload.totalPlannerElapsedMillisecondsPerAgent, 27.5d, "Per-agent elapsed differs.");
            AssertNearly(workload.processedNodesOrCellsPerAgent, 275d, "Per-agent work differs.");
            AssertNearly(workload.dynamicHandlingMillisecondsPerScheduledEvent, 49d / 3d, "Per-event elapsed differs.");
            AssertNearly(workload.dynamicProcessedNodesOrCellsPerScheduledEvent, 490d / 3d, "Per-event work differs.");
            Assert(workload.dynamicPhases[0].repairOperationCount == 2 && workload.dynamicPhases[0].planOperationCount == 2, "Same-tick operation counts differ.");
            AssertNearly(workload.dynamicPhases[0].combinedElapsedMilliseconds, 22d, "First dynamic phase elapsed differs.");
            Assert(workload.dynamicPhases[0].processedNodesOrCells == 220L, "First dynamic phase work differs.");
            AssertNearly(workload.dynamicPhases[1].combinedElapsedMilliseconds, 27d, "Second dynamic phase elapsed differs.");
            Assert(workload.dynamicPhases[1].processedNodesOrCells == 270L, "Second dynamic phase work differs.");
            Assert(workload.fairnessSchemaVersion == 1, "Fairness schema version differs.");
            Assert(workload.comparisonCohortId == PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "Workload comparison cohort differs.");
            Assert(workload.dynamicCostIncludesAllRepairsAndPostEventPlans, "Dynamic-cost completeness flag is false.");
            Assert(ReferenceEquals(sink.WorkloadPayload, workload), "JSONL workload payload is not the returned result.");
            Assert(sink.EnqueuedCount == 14L, "Expected 14 log records for 1 initialize, 3 lifecycle, 6 plans, 3 repairs, and 1 workload result.");

            PlanningWorkloadResult staticWorkload = DeterministicPlanningWorkloadRunner.Run(
                "gate10-static-accounting",
                BuildScenario(true, false),
                new ScriptedMetricsPlanner(NavigationAlgorithmIds.AStarRepeated),
                null,
                BuildProvenance(NavigationAlgorithmIds.AStarRepeated));
            Assert(staticWorkload.scheduledEventCount == 0, "Static event count differs.");
            Assert(staticWorkload.dynamicHandlingMillisecondsPerScheduledEvent == 0d, "Static per-event elapsed must be zero.");
            Assert(staticWorkload.dynamicProcessedNodesOrCellsPerScheduledEvent == 0d, "Static per-event work must be zero.");
            return workload;
        }

        private static bool VerifyAggregationIdentity(PlanningWorkloadResult source)
        {
            PlanningWorkloadResult first = Clone(source);
            PlanningWorkloadResult second = Clone(source);
            first.runId = "gate10-rep-a";
            second.runId = "gate10-rep-b";
            PlanningReplicationAggregate aggregate = PlanningReplicationAggregator.Aggregate("gate10-valid", Repeat('f'), new[] { first, second });
            Assert(aggregate.completed && aggregate.repetitionCount == 2, "Valid fairness aggregation failed.");

            ExpectAggregateRejection(source, result => result.algorithmSpecificationSha256 = Repeat('1'));
            ExpectAggregateRejection(source, result => result.algorithmImplementationSha256 = Repeat('2'));
            ExpectAggregateRejection(source, result => result.fairnessProtocolSha256 = Repeat('3'));
            ExpectAggregateRejection(source, result => result.workloadSpecificationSha256 = Repeat('4'));
            ExpectAggregateRejection(source, result => result.comparisonCohortId = PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort);
            ExpectAggregateRejection(source, result => result.dynamicCostIncludesAllRepairsAndPostEventPlans = false);
            ExpectAggregateRejection(source, result => result.algorithmId = NavigationAlgorithmIds.DStarLite);

            PlanningWorkloadResult legacyA = Clone(source);
            PlanningWorkloadResult legacyB = Clone(source);
            legacyA.runId = "legacy-a";
            legacyB.runId = "legacy-b";
            legacyA.fairnessSchemaVersion = 0;
            legacyB.fairnessSchemaVersion = 0;
            PlanningReplicationAggregate legacy = PlanningReplicationAggregator.Aggregate("gate10-legacy", Repeat('e'), new[] { legacyA, legacyB });
            Assert(legacy.completed, "Legacy schema-v1 aggregation was not preserved.");
            return legacy.completed;
        }

        private static void ExpectAggregateRejection(PlanningWorkloadResult source, Action<PlanningWorkloadResult> mutate)
        {
            PlanningWorkloadResult first = Clone(source);
            PlanningWorkloadResult second = Clone(source);
            first.runId = "valid-a";
            second.runId = "invalid-b";
            mutate(second);
            ExpectException<ArgumentException>(
                () => PlanningReplicationAggregator.Aggregate("gate10-invalid", Repeat('d'), new[] { first, second }),
                "Mixed fairness identity was accepted.");
            rejectedMixedIdentities++;
        }

        private static DeterministicScenarioDefinition BuildScenario(bool sharedGoal, bool dynamic)
        {
            return new DeterministicScenarioDefinition
            {
                scenarioId = sharedGoal ? "gate10-shared" : "gate10-heterogeneous",
                randomSeed = 1010,
                gridWidth = 4,
                gridHeight = 3,
                defaultTraversalCost = 1f,
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 10,
                goalSetId = "gate10-goals",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition { agentId = 0, start = new GridCoordinate(0, 0), goal = new GridCoordinate(3, 1) },
                    new ScenarioAgentDefinition { agentId = 1, start = new GridCoordinate(0, 2), goal = sharedGoal ? new GridCoordinate(3, 1) : new GridCoordinate(3, 2) }
                },
                initialGridOverrides = new NavigationGridChange[0],
                scheduledChanges = dynamic
                    ? new[]
                    {
                        Change("gate-a", 1, 0, new GridCoordinate(1, 0), false, 1f),
                        Change("gate-b", 1, 1, new GridCoordinate(1, 2), true, 2f),
                        Change("gate-c", 2, 0, new GridCoordinate(1, 0), true, 1f)
                    }
                    : new ScheduledNavigationChangeDefinition[0]
            };
        }

        private static ScheduledNavigationChangeDefinition Change(string id, long tick, int order, GridCoordinate coordinate, bool walkable, float cost)
        {
            return new ScheduledNavigationChangeDefinition
            {
                eventId = id,
                simulationTick = tick,
                order = order,
                repairBudgetMilliseconds = 1000d,
                changes = new[] { new NavigationGridChange { coordinate = coordinate, isWalkable = walkable, traversalCost = cost } }
            };
        }

        private static PlanningRunProvenance BuildProvenance(string algorithmId)
        {
            PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
            return new PlanningRunProvenance
            {
                fairnessProtocolId = PlanningFairnessContracts.FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.FairnessProtocolRelativePath,
                fairnessProtocolSha256 = Repeat('a'),
                algorithmId = algorithmId,
                algorithmSpecificationId = profile.SpecificationId,
                algorithmSpecificationRelativePath = profile.SpecificationRelativePath,
                algorithmSpecificationSha256 = Repeat('b'),
                algorithmImplementationRelativePath = profile.ImplementationRelativePath,
                algorithmImplementationSha256 = Repeat('c'),
                workloadSpecificationId = PlanningFairnessContracts.WorkloadSpecificationId,
                workloadSpecificationRelativePath = PlanningFairnessContracts.WorkloadSpecificationRelativePath,
                workloadSpecificationSha256 = Repeat('d')
            };
        }

        private static PlanningWorkloadResult Clone(PlanningWorkloadResult value)
        {
            return JsonUtility.FromJson<PlanningWorkloadResult>(JsonUtility.ToJson(value));
        }

        private static string Repeat(char character)
        {
            return new string(character, 64);
        }

        private static void Assert(bool condition, string message)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void AssertNearly(double actual, double expected, string message)
        {
            assertions++;
            double scale = Math.Max(1d, Math.Max(Math.Abs(actual), Math.Abs(expected)));
            if (Math.Abs(actual - expected) > 1e-9d * scale)
            {
                throw new InvalidOperationException(string.Format(CultureInfo.InvariantCulture, "{0} Expected {1}, actual {2}.", message, expected, actual));
            }
        }

        private static void ExpectException<T>(Action action, string message) where T : Exception
        {
            assertions++;
            try { action(); }
            catch (T) { return; }
            throw new InvalidOperationException(message);
        }

        private static void WriteJson(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        private sealed class ScriptedMetricsPlanner : INavigationPlanner
        {
            private readonly string algorithmId;
            private int planIndex;
            private int repairIndex;
            public string AlgorithmId { get { return algorithmId; } }
            public NavigationPlannerCapabilities Capabilities { get { return NavigationPlannerCapabilities.FullRecompute; } }
            public long GridVersion { get; private set; }

            public ScriptedMetricsPlanner(string algorithmId) { this.algorithmId = algorithmId; }

            public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
            {
                GridVersion = grid.Version;
                planIndex = 0;
                repairIndex = 0;
                return Metrics(1d, 10L, false);
            }

            public NavigationPlanResult Plan(NavigationPlanRequest request)
            {
                double[] elapsed = { 2d, 3d, 6d, 7d, 9d, 10d };
                long[] work = { 20L, 30L, 60L, 70L, 90L, 100L };
                int index = planIndex++;
                return new NavigationPlanResult(
                    NavigationPlanStatus.Succeeded,
                    NavigationFailureReason.None,
                    new[] { request.start, request.goal },
                    GridVersion,
                    Metrics(elapsed[index], work[index], false));
            }

            public NavigationRepairResult ApplyChanges(NavigationChangeSet changeSet, double repairBudgetMilliseconds)
            {
                double[] elapsed = { 4d, 5d, 8d };
                long[] work = { 40L, 50L, 80L };
                int index = repairIndex++;
                GridVersion = changeSet.newGridVersion;
                return new NavigationRepairResult(
                    NavigationPlanStatus.Succeeded,
                    NavigationFailureReason.None,
                    GridVersion,
                    Metrics(elapsed[index], work[index], true));
            }

            public void Reset() { GridVersion = -1; }

            private static NavigationOperationMetrics Metrics(double elapsed, long work, bool repair)
            {
                return new NavigationOperationMetrics
                {
                    elapsedCpuMilliseconds = elapsed,
                    cumulativePlanningCpuMilliseconds = elapsed,
                    processedNodesOrCells = work,
                    expandedNodes = work / 10,
                    relaxedEdges = work * 2,
                    repairedCells = repair ? work / 2 : 0L,
                    managedAllocatedBytes = work,
                    budgetExceeded = false
                };
            }
        }

        private sealed class CapturingLogSink : IExperimentLogSink
        {
            public string FilePath { get { return string.Empty; } }
            public long EnqueuedCount { get; private set; }
            public long WrittenCount { get { return EnqueuedCount; } }
            public PlanningWorkloadResult WorkloadPayload { get; private set; }

            public void Enqueue<T>(string recordType, string runId, T payload)
            {
                EnqueuedCount++;
                if (recordType == "planning_workload_result") WorkloadPayload = (object)payload as PlanningWorkloadResult;
            }

            public void Flush(TimeSpan timeout) { }
            public void Dispose() { }
        }
    }
}
