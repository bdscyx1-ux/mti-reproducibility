using System;
using System.Collections.Generic;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Experiments
{
    [Serializable]
    public sealed class PlanningTickWorkloadRecord
    {
        public long simulationTick;
        public string[] eventIds = new string[0];
        public long finalGridVersion;
        public int repairOperationCount;
        public int planOperationCount;
        public int succeededPlanCount;
        public int noPathPlanCount;
        public int budgetExceededOperationCount;
        public double repairElapsedMilliseconds;
        public double replanElapsedMilliseconds;
        public double combinedElapsedMilliseconds;
        public long processedNodesOrCells;
        public long expandedNodes;
        public long relaxedEdges;
        public long repairedCells;
        public long managedAllocatedBytes;
    }

    [Serializable]
    public sealed class PlanningWorkloadResult
    {
        public const int CurrentSchemaVersion = 1;

        public int schemaVersion = CurrentSchemaVersion;
        public string runId;
        public string scenarioId;
        public string scenarioFingerprintSha256;
        public string algorithmId;
        public int agentCount;
        public int scheduledEventCount;
        public int dynamicPlanningPhaseCount;
        public int planOperationCount;
        public int repairOperationCount;
        public int succeededPlanCount;
        public int noPathPlanCount;
        public int budgetExceededPlanCount;
        public int invalidPlanCount;
        public int failedPlanCount;
        public int budgetExceededOperationCount;
        public double initializationMilliseconds;
        public double planP95Milliseconds;
        public double dynamicHandlingP95Milliseconds;
        public double totalPlannerElapsedMilliseconds;
        public long processedNodesOrCells;
        public long expandedNodes;
        public long relaxedEdges;
        public long repairedCells;
        public long managedAllocatedBytes;
        public double planSuccessRate;
        public double budgetOverrunRate;
        public long finalGridVersion;
        public bool usesFixedScenarioStarts;
        public bool completed;
        public PlanningTickWorkloadRecord[] dynamicPhases = new PlanningTickWorkloadRecord[0];

        public int fairnessSchemaVersion;
        public string fairnessProtocolId;
        public string fairnessProtocolRelativePath;
        public string fairnessProtocolSha256;
        public string algorithmSpecificationId;
        public string algorithmSpecificationRelativePath;
        public string algorithmSpecificationSha256;
        public string algorithmImplementationRelativePath;
        public string algorithmImplementationSha256;
        public string workloadSpecificationId;
        public string workloadSpecificationRelativePath;
        public string workloadSpecificationSha256;
        public string goalCohortId;
        public string comparisonCohortId;
        public int distinctGoalCount;
        public int plannerInstanceCount;
        public int persistentStateInstanceCount;
        public int sharedFieldInstanceCount;
        public string plannerStateModelId;
        public string processedWorkUnit;
        public string nativeMetricsSemanticsId;
        public bool dynamicCostIncludesAllRepairsAndPostEventPlans;
        public long initializationProcessedNodesOrCells;
        public double initialPlanningMilliseconds;
        public long initialPlanningProcessedNodesOrCells;
        public double dynamicHandlingTotalMilliseconds;
        public long dynamicProcessedNodesOrCells;
        public long dynamicManagedAllocatedBytes;
        public double totalPlannerElapsedMillisecondsPerAgent;
        public double processedNodesOrCellsPerAgent;
        public double dynamicHandlingMillisecondsPerScheduledEvent;
        public double dynamicProcessedNodesOrCellsPerScheduledEvent;
    }

    /// <summary>
    /// Headless route-planning microbenchmark. Agents are replanned from their declared
    /// scenario starts after every dynamic-event tick; no movement is simulated.
    /// </summary>
    public static class DeterministicPlanningWorkloadRunner
    {
        public static PlanningWorkloadResult Run(
            string runId,
            DeterministicScenarioDefinition scenarioDefinition,
            INavigationPlanner planner,
            IExperimentLogSink logSink = null,
            PlanningRunProvenance provenance = null)
        {
            if (string.IsNullOrWhiteSpace(runId)) throw new ArgumentException("Run id is required.", "runId");
            if (scenarioDefinition == null) throw new ArgumentNullException("scenarioDefinition");
            if (planner == null) throw new ArgumentNullException("planner");

            string algorithmId = planner.AlgorithmId;
            PlanningWorkloadAccumulator accumulator = new PlanningWorkloadAccumulator();
            List<PlanningTickWorkloadRecord> phases = new List<PlanningTickWorkloadRecord>();
            ExperimentRunner runner = new ExperimentRunner(runId, scenarioDefinition, planner, logSink, false);
            PlanningWorkloadResult result = null;

            try
            {
                runner.Initialize();
                accumulator.AddInitialization(runner.InitializationMetrics);
                PlanningFairnessClassification fairness = null;
                if (provenance != null)
                {
                    PlanningFairnessContracts.ValidateProvenance(provenance, algorithmId);
                    fairness = PlanningFairnessContracts.Classify(runner.Scenario, algorithmId, provenance);
                    PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(algorithmId, fairness.ComparisonCohortId);
                }
                runner.Begin();
                PlanAllAgents(runner, accumulator, null);

                int scheduledIndex = 0;
                while (scheduledIndex < runner.Scenario.ScheduledChanges.Count)
                {
                    long tick = runner.Scenario.ScheduledChanges[scheduledIndex].SimulationTick;
                    IReadOnlyList<ExperimentRepairObservation> observations = runner.AdvanceToTick(tick);
                    PlanningTickWorkloadRecord phase = new PlanningTickWorkloadRecord
                    {
                        simulationTick = tick,
                        eventIds = new string[observations.Count],
                        repairOperationCount = observations.Count
                    };

                    for (int observationIndex = 0; observationIndex < observations.Count; observationIndex++)
                    {
                        ExperimentRepairObservation observation = observations[observationIndex];
                        phase.eventIds[observationIndex] = observation.EventId;
                        phase.repairElapsedMilliseconds += observation.Result.Metrics.elapsedCpuMilliseconds;
                        if (observation.Result.Metrics.budgetExceeded) phase.budgetExceededOperationCount++;
                        accumulator.AddRepair(observation.Result);
                        AddPhaseMetrics(phase, observation.Result.Metrics);
                    }

                    PlanAllAgents(runner, accumulator, phase);
                    phase.finalGridVersion = runner.Grid.Version;
                    phase.combinedElapsedMilliseconds = phase.repairElapsedMilliseconds + phase.replanElapsedMilliseconds;
                    phases.Add(phase);
                    accumulator.AddDynamicPhase(phase);
                    scheduledIndex += observations.Count;
                    if (observations.Count == 0) throw new InvalidOperationException("No events were applied at the next scheduled event tick.");
                }

                runner.Complete("planning workload complete");
                result = accumulator.BuildResult(runId, runner.Scenario, algorithmId, runner.Grid.Version, phases, provenance, fairness);
                result.completed = true;
                if (logSink != null) logSink.Enqueue("planning_workload_result", runId, result);
                return result;
            }
            finally
            {
                runner.Dispose();
            }
        }

        private static void PlanAllAgents(
            ExperimentRunner runner,
            PlanningWorkloadAccumulator accumulator,
            PlanningTickWorkloadRecord phase)
        {
            for (int agentIndex = 0; agentIndex < runner.Scenario.Agents.Count; agentIndex++)
            {
                ResolvedScenarioAgent agent = runner.Scenario.Agents[agentIndex];
                NavigationPlanResult plan = runner.PlanForAgent(agent.AgentId, agent.Start);
                accumulator.AddPlan(plan);
                if (phase == null)
                {
                    accumulator.AddInitialPlan(plan.Metrics);
                    continue;
                }

                phase.planOperationCount++;
                phase.replanElapsedMilliseconds += plan.Metrics.elapsedCpuMilliseconds;
                AddPhaseMetrics(phase, plan.Metrics);
                if (plan.Status == NavigationPlanStatus.Succeeded) phase.succeededPlanCount++;
                else if (plan.Status == NavigationPlanStatus.NoPath) phase.noPathPlanCount++;
                if (plan.Metrics.budgetExceeded) phase.budgetExceededOperationCount++;
            }
        }

        private static void AddPhaseMetrics(PlanningTickWorkloadRecord phase, NavigationOperationMetrics metrics)
        {
            NavigationOperationMetrics safe = metrics ?? new NavigationOperationMetrics();
            phase.processedNodesOrCells += safe.processedNodesOrCells;
            phase.expandedNodes += safe.expandedNodes;
            phase.relaxedEdges += safe.relaxedEdges;
            phase.repairedCells += safe.repairedCells;
            phase.managedAllocatedBytes += safe.managedAllocatedBytes;
        }

        private sealed class PlanningWorkloadAccumulator
        {
            private readonly List<double> planTimes = new List<double>();
            private readonly List<double> dynamicTimes = new List<double>();
            private int totalOperationCount;

            public int PlanOperationCount { get; private set; }
            public int RepairOperationCount { get; private set; }
            public int SucceededPlanCount { get; private set; }
            public int NoPathPlanCount { get; private set; }
            public int BudgetExceededPlanCount { get; private set; }
            public int InvalidPlanCount { get; private set; }
            public int FailedPlanCount { get; private set; }
            public int BudgetExceededOperationCount { get; private set; }
            public double InitializationMilliseconds { get; private set; }
            public double TotalElapsedMilliseconds { get; private set; }
            public long ProcessedNodesOrCells { get; private set; }
            public long ExpandedNodes { get; private set; }
            public long RelaxedEdges { get; private set; }
            public long RepairedCells { get; private set; }
            public long ManagedAllocatedBytes { get; private set; }
            public long InitializationProcessedNodesOrCells { get; private set; }
            public double InitialPlanningMilliseconds { get; private set; }
            public long InitialPlanningProcessedNodesOrCells { get; private set; }
            public double DynamicHandlingTotalMilliseconds { get; private set; }
            public long DynamicProcessedNodesOrCells { get; private set; }
            public long DynamicManagedAllocatedBytes { get; private set; }

            public void AddInitialization(NavigationOperationMetrics metrics)
            {
                InitializationMilliseconds = Safe(metrics).elapsedCpuMilliseconds;
                InitializationProcessedNodesOrCells = Safe(metrics).processedNodesOrCells;
                AddMetrics(metrics);
            }

            public void AddInitialPlan(NavigationOperationMetrics metrics)
            {
                NavigationOperationMetrics safe = Safe(metrics);
                InitialPlanningMilliseconds += safe.elapsedCpuMilliseconds;
                InitialPlanningProcessedNodesOrCells += safe.processedNodesOrCells;
            }

            public void AddPlan(NavigationPlanResult plan)
            {
                PlanOperationCount++;
                NavigationOperationMetrics metrics = Safe(plan.Metrics);
                planTimes.Add(metrics.elapsedCpuMilliseconds);
                AddMetrics(metrics);
                switch (plan.Status)
                {
                    case NavigationPlanStatus.Succeeded: SucceededPlanCount++; break;
                    case NavigationPlanStatus.NoPath: NoPathPlanCount++; break;
                    case NavigationPlanStatus.BudgetExceeded: BudgetExceededPlanCount++; break;
                    case NavigationPlanStatus.InvalidRequest: InvalidPlanCount++; break;
                    default: FailedPlanCount++; break;
                }
            }

            public void AddRepair(NavigationRepairResult repair)
            {
                RepairOperationCount++;
                AddMetrics(repair.Metrics);
            }

            public void AddDynamicPhase(PlanningTickWorkloadRecord phase)
            {
                dynamicTimes.Add(phase.combinedElapsedMilliseconds);
                DynamicHandlingTotalMilliseconds += phase.combinedElapsedMilliseconds;
                DynamicProcessedNodesOrCells += phase.processedNodesOrCells;
                DynamicManagedAllocatedBytes += phase.managedAllocatedBytes;
            }

            public PlanningWorkloadResult BuildResult(
                string runId,
                ResolvedDeterministicScenario scenario,
                string algorithmId,
                long finalGridVersion,
                List<PlanningTickWorkloadRecord> phases,
                PlanningRunProvenance provenance,
                PlanningFairnessClassification fairness)
            {
                PlanningWorkloadResult result = new PlanningWorkloadResult
                {
                    runId = runId,
                    scenarioId = scenario.ScenarioId,
                    scenarioFingerprintSha256 = scenario.FingerprintSha256,
                    algorithmId = algorithmId,
                    agentCount = scenario.Agents.Count,
                    scheduledEventCount = scenario.ScheduledChanges.Count,
                    dynamicPlanningPhaseCount = phases.Count,
                    planOperationCount = PlanOperationCount,
                    repairOperationCount = RepairOperationCount,
                    succeededPlanCount = SucceededPlanCount,
                    noPathPlanCount = NoPathPlanCount,
                    budgetExceededPlanCount = BudgetExceededPlanCount,
                    invalidPlanCount = InvalidPlanCount,
                    failedPlanCount = FailedPlanCount,
                    budgetExceededOperationCount = BudgetExceededOperationCount,
                    initializationMilliseconds = InitializationMilliseconds,
                    planP95Milliseconds = Percentile95(planTimes),
                    dynamicHandlingP95Milliseconds = Percentile95(dynamicTimes),
                    totalPlannerElapsedMilliseconds = TotalElapsedMilliseconds,
                    processedNodesOrCells = ProcessedNodesOrCells,
                    expandedNodes = ExpandedNodes,
                    relaxedEdges = RelaxedEdges,
                    repairedCells = RepairedCells,
                    managedAllocatedBytes = ManagedAllocatedBytes,
                    planSuccessRate = PlanOperationCount == 0 ? 0d : (double)SucceededPlanCount / PlanOperationCount,
                    budgetOverrunRate = totalOperationCount == 0 ? 0d : (double)BudgetExceededOperationCount / totalOperationCount,
                    finalGridVersion = finalGridVersion,
                    usesFixedScenarioStarts = true,
                    dynamicPhases = phases.ToArray(),
                    initializationProcessedNodesOrCells = InitializationProcessedNodesOrCells,
                    initialPlanningMilliseconds = InitialPlanningMilliseconds,
                    initialPlanningProcessedNodesOrCells = InitialPlanningProcessedNodesOrCells,
                    dynamicHandlingTotalMilliseconds = DynamicHandlingTotalMilliseconds,
                    dynamicProcessedNodesOrCells = DynamicProcessedNodesOrCells,
                    dynamicManagedAllocatedBytes = DynamicManagedAllocatedBytes,
                    totalPlannerElapsedMillisecondsPerAgent = scenario.Agents.Count == 0 ? 0d : TotalElapsedMilliseconds / scenario.Agents.Count,
                    processedNodesOrCellsPerAgent = scenario.Agents.Count == 0 ? 0d : (double)ProcessedNodesOrCells / scenario.Agents.Count,
                    dynamicHandlingMillisecondsPerScheduledEvent = scenario.ScheduledChanges.Count == 0 ? 0d : DynamicHandlingTotalMilliseconds / scenario.ScheduledChanges.Count,
                    dynamicProcessedNodesOrCellsPerScheduledEvent = scenario.ScheduledChanges.Count == 0 ? 0d : (double)DynamicProcessedNodesOrCells / scenario.ScheduledChanges.Count
                };

                if (provenance != null && fairness != null)
                {
                    PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
                    result.fairnessSchemaVersion = PlanningFairnessContracts.FairnessSchemaVersion;
                    result.fairnessProtocolId = provenance.fairnessProtocolId;
                    result.fairnessProtocolRelativePath = provenance.fairnessProtocolRelativePath;
                    result.fairnessProtocolSha256 = provenance.fairnessProtocolSha256;
                    result.algorithmSpecificationId = provenance.algorithmSpecificationId;
                    result.algorithmSpecificationRelativePath = provenance.algorithmSpecificationRelativePath;
                    result.algorithmSpecificationSha256 = provenance.algorithmSpecificationSha256;
                    result.algorithmImplementationRelativePath = provenance.algorithmImplementationRelativePath;
                    result.algorithmImplementationSha256 = provenance.algorithmImplementationSha256;
                    result.workloadSpecificationId = provenance.workloadSpecificationId;
                    result.workloadSpecificationRelativePath = provenance.workloadSpecificationRelativePath;
                    result.workloadSpecificationSha256 = provenance.workloadSpecificationSha256;
                    result.goalCohortId = fairness.GoalCohortId;
                    result.comparisonCohortId = fairness.ComparisonCohortId;
                    result.distinctGoalCount = fairness.DistinctGoalCount;
                    result.plannerInstanceCount = fairness.PlannerInstanceCount;
                    result.persistentStateInstanceCount = fairness.PersistentStateInstanceCount;
                    result.sharedFieldInstanceCount = fairness.SharedFieldInstanceCount;
                    result.plannerStateModelId = profile.StateModelId;
                    result.processedWorkUnit = profile.ProcessedWorkUnit;
                    result.nativeMetricsSemanticsId = profile.NativeMetricsSemanticsId;
                    result.dynamicCostIncludesAllRepairsAndPostEventPlans = true;
                }
                return result;
            }

            private void AddMetrics(NavigationOperationMetrics metrics)
            {
                NavigationOperationMetrics safe = Safe(metrics);
                totalOperationCount++;
                TotalElapsedMilliseconds += safe.elapsedCpuMilliseconds;
                ProcessedNodesOrCells += safe.processedNodesOrCells;
                ExpandedNodes += safe.expandedNodes;
                RelaxedEdges += safe.relaxedEdges;
                RepairedCells += safe.repairedCells;
                ManagedAllocatedBytes += safe.managedAllocatedBytes;
                if (safe.budgetExceeded) BudgetExceededOperationCount++;
            }

            private static NavigationOperationMetrics Safe(NavigationOperationMetrics metrics)
            {
                return metrics ?? new NavigationOperationMetrics();
            }

            private static double Percentile95(List<double> values)
            {
                if (values.Count == 0) return 0d;
                double[] sorted = values.ToArray();
                Array.Sort(sorted);
                int index = Math.Max(0, (int)Math.Ceiling(sorted.Length * 0.95d) - 1);
                return sorted[index];
            }
        }
    }
}
