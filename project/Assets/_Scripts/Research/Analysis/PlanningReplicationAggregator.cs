using System;
using System.Collections.Generic;
using DDM.Research.Experiments;

namespace DDM.Research.Analysis
{
    [Serializable]
    public sealed class PlanningReplicationAggregationRequest
    {
        public const int CurrentSchemaVersion = 1;

        public int schemaVersion = CurrentSchemaVersion;
        public string groupId;
        public string scenarioSourceSha256;
        public string algorithmId;
        public string[] workloadResultPaths = new string[0];
    }

    [Serializable]
    public sealed class ReplicationMetricSummary
    {
        public int count;
        public double minimum;
        public double maximum;
        public double mean;
        public double median;
        public double p95NearestRank;
        public double sampleStandardDeviation;
        public double standardError;
        public double confidence95Lower;
        public double confidence95Upper;
    }

    [Serializable]
    public sealed class PlanningReplicationAggregate
    {
        public const int CurrentSchemaVersion = 1;

        public int schemaVersion = CurrentSchemaVersion;
        public string groupId;
        public string algorithmId;
        public string scenarioId;
        public string scenarioFingerprintSha256;
        public string scenarioSourceSha256;
        public int repetitionCount;
        public string[] childRunIds = new string[0];
        public int agentCount;
        public int scheduledEventCount;
        public int dynamicPlanningPhaseCount;
        public int planOperationsPerRun;
        public int repairOperationsPerRun;
        public long finalGridVersion;
        public int totalPlanOperationCount;
        public int totalRepairOperationCount;
        public int totalSucceededPlanCount;
        public int totalNoPathPlanCount;
        public int totalBudgetExceededPlanCount;
        public int totalInvalidPlanCount;
        public int totalFailedPlanCount;
        public int totalBudgetExceededOperationCount;
        public bool allRunsCompleted;
        public bool allRunsUseFixedScenarioStarts;
        public bool deterministicWorkCountsConsistent;
        public long consistentProcessedNodesOrCells;
        public long consistentExpandedNodes;
        public long consistentRelaxedEdges;
        public long consistentRepairedCells;
        public ReplicationMetricSummary initializationMilliseconds;
        public ReplicationMetricSummary planP95Milliseconds;
        public ReplicationMetricSummary dynamicHandlingP95Milliseconds;
        public ReplicationMetricSummary totalPlannerElapsedMilliseconds;
        public ReplicationMetricSummary managedAllocatedBytes;
        public ReplicationMetricSummary planSuccessRate;
        public ReplicationMetricSummary budgetOverrunRate;
        public bool completed;
    }

    public static class ReplicationStatistics
    {
        private static readonly double[] StudentTCritical95 =
        {
            0d,
            12.7062047364d,
            4.30265272975d,
            3.18244630528d,
            2.7764451052d,
            2.57058183564d,
            2.44691184879d,
            2.36462425101d,
            2.3060041352d,
            2.26215716274d,
            2.22813885196d,
            2.20098516008d,
            2.17881282966d,
            2.16036865646d,
            2.14478668792d,
            2.13144954556d,
            2.11990529922d,
            2.10981557783d,
            2.10092204024d,
            2.09302405441d,
            2.08596344727d,
            2.07961384473d,
            2.0738730679d,
            2.06865761042d,
            2.06389856163d,
            2.05953855275d,
            2.05552943864d,
            2.05183051648d,
            2.0484071418d,
            2.04522964213d,
            2.0422724563d
        };

        public static ReplicationMetricSummary Summarize(IReadOnlyList<double> values)
        {
            if (values == null) throw new ArgumentNullException("values");
            if (values.Count == 0) throw new ArgumentException("At least one value is required.", "values");

            double[] sorted = new double[values.Count];
            double mean = 0d;
            double secondMoment = 0d;
            for (int index = 0; index < values.Count; index++)
            {
                double value = values[index];
                if (double.IsNaN(value) || double.IsInfinity(value)) throw new ArgumentException("Replication statistics require finite values.", "values");
                sorted[index] = value;
                int sampleCount = index + 1;
                double delta = value - mean;
                mean += delta / sampleCount;
                double deltaAfterMean = value - mean;
                secondMoment += delta * deltaAfterMean;
            }
            Array.Sort(sorted);

            double sampleStandardDeviation = sorted.Length > 1
                ? Math.Sqrt(Math.Max(0d, secondMoment) / (sorted.Length - 1))
                : 0d;
            double standardError = sorted.Length > 1
                ? sampleStandardDeviation / Math.Sqrt(sorted.Length)
                : 0d;
            double margin = sorted.Length > 1
                ? StudentTCritical(sorted.Length - 1) * standardError
                : 0d;
            int medianUpper = sorted.Length / 2;
            double median = sorted.Length % 2 == 0
                ? (sorted[medianUpper - 1] + sorted[medianUpper]) / 2d
                : sorted[medianUpper];
            int p95Index = Math.Max(0, (int)Math.Ceiling(sorted.Length * 0.95d) - 1);

            return new ReplicationMetricSummary
            {
                count = sorted.Length,
                minimum = sorted[0],
                maximum = sorted[sorted.Length - 1],
                mean = mean,
                median = median,
                p95NearestRank = sorted[p95Index],
                sampleStandardDeviation = sampleStandardDeviation,
                standardError = standardError,
                confidence95Lower = mean - margin,
                confidence95Upper = mean + margin
            };
        }

        private static double StudentTCritical(int degreesOfFreedom)
        {
            if (degreesOfFreedom <= 0) throw new ArgumentOutOfRangeException("degreesOfFreedom");
            if (degreesOfFreedom < StudentTCritical95.Length) return StudentTCritical95[degreesOfFreedom];

            const double z = 1.959963984540054d;
            double df = degreesOfFreedom;
            double z2 = z * z;
            double z3 = z2 * z;
            double z5 = z3 * z2;
            double z7 = z5 * z2;
            return z +
                   ((z3 + z) / (4d * df)) +
                   ((5d * z5 + 16d * z3 + 3d * z) / (96d * df * df)) +
                   ((3d * z7 + 19d * z5 + 17d * z3 - 15d * z) / (384d * df * df * df));
        }
    }

    public static class PlanningReplicationAggregator
    {
        public static PlanningReplicationAggregate Aggregate(
            string groupId,
            string scenarioSourceSha256,
            IReadOnlyList<PlanningWorkloadResult> runs)
        {
            if (string.IsNullOrWhiteSpace(groupId)) throw new ArgumentException("Replication group id is required.", "groupId");
            if (!IsSha256(scenarioSourceSha256)) throw new ArgumentException("Scenario source SHA-256 is required.", "scenarioSourceSha256");
            if (runs == null) throw new ArgumentNullException("runs");
            if (runs.Count < 2) throw new ArgumentException("At least two completed runs are required for replication aggregation.", "runs");

            PlanningWorkloadResult first = runs[0];
            ValidateRun(first, 0);
            HashSet<string> runIds = new HashSet<string>(StringComparer.Ordinal);
            List<double> initialization = new List<double>(runs.Count);
            List<double> planP95 = new List<double>(runs.Count);
            List<double> dynamicP95 = new List<double>(runs.Count);
            List<double> totalElapsed = new List<double>(runs.Count);
            List<double> allocations = new List<double>(runs.Count);
            List<double> successRates = new List<double>(runs.Count);
            List<double> budgetRates = new List<double>(runs.Count);
            string[] childRunIds = new string[runs.Count];
            bool workCountsConsistent = true;

            int totalPlans = 0;
            int totalRepairs = 0;
            int totalSucceeded = 0;
            int totalNoPath = 0;
            int totalBudgetPlans = 0;
            int totalInvalid = 0;
            int totalFailed = 0;
            int totalBudgetOperations = 0;

            for (int index = 0; index < runs.Count; index++)
            {
                PlanningWorkloadResult run = runs[index];
                ValidateRun(run, index);
                if (!runIds.Add(run.runId)) throw new ArgumentException("Replication run ids must be unique: " + run.runId, "runs");
                EnsureIdentityMatches(first, run, index);

                childRunIds[index] = run.runId;
                initialization.Add(run.initializationMilliseconds);
                planP95.Add(run.planP95Milliseconds);
                dynamicP95.Add(run.dynamicHandlingP95Milliseconds);
                totalElapsed.Add(run.totalPlannerElapsedMilliseconds);
                allocations.Add(run.managedAllocatedBytes);
                successRates.Add(run.planSuccessRate);
                budgetRates.Add(run.budgetOverrunRate);

                totalPlans = checked(totalPlans + run.planOperationCount);
                totalRepairs = checked(totalRepairs + run.repairOperationCount);
                totalSucceeded = checked(totalSucceeded + run.succeededPlanCount);
                totalNoPath = checked(totalNoPath + run.noPathPlanCount);
                totalBudgetPlans = checked(totalBudgetPlans + run.budgetExceededPlanCount);
                totalInvalid = checked(totalInvalid + run.invalidPlanCount);
                totalFailed = checked(totalFailed + run.failedPlanCount);
                totalBudgetOperations = checked(totalBudgetOperations + run.budgetExceededOperationCount);

                if (run.processedNodesOrCells != first.processedNodesOrCells ||
                    run.expandedNodes != first.expandedNodes ||
                    run.relaxedEdges != first.relaxedEdges ||
                    run.repairedCells != first.repairedCells)
                {
                    workCountsConsistent = false;
                }
            }

            return new PlanningReplicationAggregate
            {
                groupId = groupId,
                algorithmId = first.algorithmId,
                scenarioId = first.scenarioId,
                scenarioFingerprintSha256 = first.scenarioFingerprintSha256,
                scenarioSourceSha256 = scenarioSourceSha256,
                repetitionCount = runs.Count,
                childRunIds = childRunIds,
                agentCount = first.agentCount,
                scheduledEventCount = first.scheduledEventCount,
                dynamicPlanningPhaseCount = first.dynamicPlanningPhaseCount,
                planOperationsPerRun = first.planOperationCount,
                repairOperationsPerRun = first.repairOperationCount,
                finalGridVersion = first.finalGridVersion,
                totalPlanOperationCount = totalPlans,
                totalRepairOperationCount = totalRepairs,
                totalSucceededPlanCount = totalSucceeded,
                totalNoPathPlanCount = totalNoPath,
                totalBudgetExceededPlanCount = totalBudgetPlans,
                totalInvalidPlanCount = totalInvalid,
                totalFailedPlanCount = totalFailed,
                totalBudgetExceededOperationCount = totalBudgetOperations,
                allRunsCompleted = true,
                allRunsUseFixedScenarioStarts = true,
                deterministicWorkCountsConsistent = workCountsConsistent,
                consistentProcessedNodesOrCells = workCountsConsistent ? first.processedNodesOrCells : -1L,
                consistentExpandedNodes = workCountsConsistent ? first.expandedNodes : -1L,
                consistentRelaxedEdges = workCountsConsistent ? first.relaxedEdges : -1L,
                consistentRepairedCells = workCountsConsistent ? first.repairedCells : -1L,
                initializationMilliseconds = ReplicationStatistics.Summarize(initialization),
                planP95Milliseconds = ReplicationStatistics.Summarize(planP95),
                dynamicHandlingP95Milliseconds = ReplicationStatistics.Summarize(dynamicP95),
                totalPlannerElapsedMilliseconds = ReplicationStatistics.Summarize(totalElapsed),
                managedAllocatedBytes = ReplicationStatistics.Summarize(allocations),
                planSuccessRate = ReplicationStatistics.Summarize(successRates),
                budgetOverrunRate = ReplicationStatistics.Summarize(budgetRates),
                completed = true
            };
        }

        private static void ValidateRun(PlanningWorkloadResult run, int index)
        {
            if (run == null) throw new ArgumentException("Replication run cannot be null at index " + index + ".", "runs");
            if (run.schemaVersion != PlanningWorkloadResult.CurrentSchemaVersion) throw new ArgumentException("Unsupported workload schema at index " + index + ".", "runs");
            if (!run.completed) throw new ArgumentException("Workload run is incomplete at index " + index + ".", "runs");
            if (!run.usesFixedScenarioStarts) throw new ArgumentException("Workload run does not use fixed scenario starts at index " + index + ".", "runs");
            if (string.IsNullOrWhiteSpace(run.runId) || string.IsNullOrWhiteSpace(run.algorithmId) || string.IsNullOrWhiteSpace(run.scenarioId)) throw new ArgumentException("Workload identity is incomplete at index " + index + ".", "runs");
            if (!IsSha256(run.scenarioFingerprintSha256)) throw new ArgumentException("Scenario fingerprint is invalid at index " + index + ".", "runs");
            if (run.agentCount <= 0 || run.scheduledEventCount < 0 || run.planOperationCount <= 0 || run.repairOperationCount < 0 || run.dynamicPlanningPhaseCount < 0) throw new ArgumentException("Workload counts are invalid at index " + index + ".", "runs");
            int expectedPlanOperations = checked(run.agentCount * (run.dynamicPlanningPhaseCount + 1));
            if (run.planOperationCount != expectedPlanOperations) throw new ArgumentException("Plan operation count does not match fixed-start workload structure at index " + index + ".", "runs");
            int categorizedPlans = checked(run.succeededPlanCount + run.noPathPlanCount + run.budgetExceededPlanCount + run.invalidPlanCount + run.failedPlanCount);
            if (categorizedPlans != run.planOperationCount) throw new ArgumentException("Plan status counts do not sum to the plan operation count at index " + index + ".", "runs");
            if (run.finalGridVersion != run.scheduledEventCount || run.repairOperationCount != run.scheduledEventCount) throw new ArgumentException("Dynamic-event/version counts are inconsistent at index " + index + ".", "runs");
            int totalOperationCount = checked(1 + run.planOperationCount + run.repairOperationCount);
            if (run.budgetExceededOperationCount < 0 || run.budgetExceededOperationCount > totalOperationCount) throw new ArgumentException("Budget-overrun operation count is invalid at index " + index + ".", "runs");
            ValidateFiniteNonNegative(run.initializationMilliseconds, "initializationMilliseconds", index);
            ValidateFiniteNonNegative(run.planP95Milliseconds, "planP95Milliseconds", index);
            ValidateFiniteNonNegative(run.dynamicHandlingP95Milliseconds, "dynamicHandlingP95Milliseconds", index);
            ValidateFiniteNonNegative(run.totalPlannerElapsedMilliseconds, "totalPlannerElapsedMilliseconds", index);
            if (run.managedAllocatedBytes < 0L || run.processedNodesOrCells < 0L || run.expandedNodes < 0L || run.relaxedEdges < 0L || run.repairedCells < 0L) throw new ArgumentException("Work/allocation metrics are negative at index " + index + ".", "runs");
            ValidateFairnessExtension(run, index);
            ValidateRate(run.planSuccessRate, "planSuccessRate", index);
            ValidateRate(run.budgetOverrunRate, "budgetOverrunRate", index);
            double expectedSuccessRate = (double)run.succeededPlanCount / run.planOperationCount;
            double expectedBudgetRate = (double)run.budgetExceededOperationCount / totalOperationCount;
            if (!RatesEqual(run.planSuccessRate, expectedSuccessRate)) throw new ArgumentException("Plan success rate does not match its counts at index " + index + ".", "runs");
            if (!RatesEqual(run.budgetOverrunRate, expectedBudgetRate)) throw new ArgumentException("Budget-overrun rate does not match its counts at index " + index + ".", "runs");
        }

        private static void EnsureIdentityMatches(PlanningWorkloadResult first, PlanningWorkloadResult current, int index)
        {
            if (!string.Equals(first.algorithmId, current.algorithmId, StringComparison.Ordinal) ||
                !string.Equals(first.scenarioId, current.scenarioId, StringComparison.Ordinal) ||
                !string.Equals(first.scenarioFingerprintSha256, current.scenarioFingerprintSha256, StringComparison.Ordinal) ||
                first.agentCount != current.agentCount ||
                first.scheduledEventCount != current.scheduledEventCount ||
                first.dynamicPlanningPhaseCount != current.dynamicPlanningPhaseCount ||
                first.planOperationCount != current.planOperationCount ||
                first.repairOperationCount != current.repairOperationCount ||
                first.succeededPlanCount != current.succeededPlanCount ||
                first.noPathPlanCount != current.noPathPlanCount ||
                first.budgetExceededPlanCount != current.budgetExceededPlanCount ||
                first.invalidPlanCount != current.invalidPlanCount ||
                first.failedPlanCount != current.failedPlanCount ||
                first.finalGridVersion != current.finalGridVersion ||
                first.fairnessSchemaVersion != current.fairnessSchemaVersion ||
                !string.Equals(first.fairnessProtocolId, current.fairnessProtocolId, StringComparison.Ordinal) ||
                !string.Equals(first.fairnessProtocolSha256, current.fairnessProtocolSha256, StringComparison.Ordinal) ||
                !string.Equals(first.algorithmSpecificationId, current.algorithmSpecificationId, StringComparison.Ordinal) ||
                !string.Equals(first.algorithmSpecificationSha256, current.algorithmSpecificationSha256, StringComparison.Ordinal) ||
                !string.Equals(first.algorithmImplementationSha256, current.algorithmImplementationSha256, StringComparison.Ordinal) ||
                !string.Equals(first.workloadSpecificationSha256, current.workloadSpecificationSha256, StringComparison.Ordinal) ||
                !string.Equals(first.goalCohortId, current.goalCohortId, StringComparison.Ordinal) ||
                !string.Equals(first.comparisonCohortId, current.comparisonCohortId, StringComparison.Ordinal) ||
                first.distinctGoalCount != current.distinctGoalCount ||
                first.plannerInstanceCount != current.plannerInstanceCount ||
                first.persistentStateInstanceCount != current.persistentStateInstanceCount ||
                first.sharedFieldInstanceCount != current.sharedFieldInstanceCount ||
                !string.Equals(first.plannerStateModelId, current.plannerStateModelId, StringComparison.Ordinal) ||
                !string.Equals(first.processedWorkUnit, current.processedWorkUnit, StringComparison.Ordinal) ||
                !string.Equals(first.nativeMetricsSemanticsId, current.nativeMetricsSemanticsId, StringComparison.Ordinal) ||
                first.dynamicCostIncludesAllRepairsAndPostEventPlans != current.dynamicCostIncludesAllRepairsAndPostEventPlans)
            {
                throw new ArgumentException("Replication run identity or deterministic outcome differs at index " + index + ".", "runs");
            }
        }

        private static void ValidateFairnessExtension(PlanningWorkloadResult run, int index)
        {
            if (run.fairnessSchemaVersion == 0) return;
            if (run.fairnessSchemaVersion != PlanningFairnessContracts.FairnessSchemaVersion)
            {
                throw new ArgumentException("Unsupported fairness extension at index " + index + ".", "runs");
            }

            PlanningAlgorithmFairnessProfile profile;
            try { profile = PlanningFairnessContracts.GetProfile(run.algorithmId); }
            catch (Exception exception) { throw new ArgumentException("Unauthorized fairness algorithm at index " + index + ".", "runs", exception); }
            if (!string.Equals(run.fairnessProtocolId, PlanningFairnessContracts.FairnessProtocolId, StringComparison.Ordinal) ||
                !string.Equals(run.fairnessProtocolRelativePath, PlanningFairnessContracts.FairnessProtocolRelativePath, StringComparison.Ordinal) ||
                !PlanningFairnessContracts.IsSha256(run.fairnessProtocolSha256) ||
                !string.Equals(run.algorithmSpecificationId, profile.SpecificationId, StringComparison.Ordinal) ||
                !string.Equals(run.algorithmSpecificationRelativePath, profile.SpecificationRelativePath, StringComparison.Ordinal) ||
                !PlanningFairnessContracts.IsSha256(run.algorithmSpecificationSha256) ||
                !string.Equals(run.algorithmImplementationRelativePath, profile.ImplementationRelativePath, StringComparison.Ordinal) ||
                !PlanningFairnessContracts.IsSha256(run.algorithmImplementationSha256) ||
                !string.Equals(run.workloadSpecificationId, PlanningFairnessContracts.WorkloadSpecificationId, StringComparison.Ordinal) ||
                !string.Equals(run.workloadSpecificationRelativePath, PlanningFairnessContracts.WorkloadSpecificationRelativePath, StringComparison.Ordinal) ||
                !PlanningFairnessContracts.IsSha256(run.workloadSpecificationSha256) ||
                !string.Equals(run.plannerStateModelId, profile.StateModelId, StringComparison.Ordinal) ||
                !string.Equals(run.processedWorkUnit, profile.ProcessedWorkUnit, StringComparison.Ordinal) ||
                !string.Equals(run.nativeMetricsSemanticsId, profile.NativeMetricsSemanticsId, StringComparison.Ordinal) ||
                !run.dynamicCostIncludesAllRepairsAndPostEventPlans)
            {
                throw new ArgumentException("Fairness provenance is incomplete or inconsistent at index " + index + ".", "runs");
            }

            bool shared = run.distinctGoalCount == 1;
            string expectedGoalCohort = shared
                ? PlanningFairnessContracts.GoalCohortSingleShared
                : PlanningFairnessContracts.GoalCohortHeterogeneous;
            string expectedComparisonCohort = shared
                ? PlanningFairnessContracts.FourAlgorithmSharedGoalCohort
                : (profile.UsesSharedField
                    ? PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort
                    : PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort);
            int expectedPersistentStates = profile.UsesPerAgentState ? run.agentCount : (profile.UsesSharedField ? 1 : 0);
            int expectedFields = profile.UsesSharedField ? 1 : 0;
            if (run.distinctGoalCount <= 0 ||
                !string.Equals(run.goalCohortId, expectedGoalCohort, StringComparison.Ordinal) ||
                !string.Equals(run.comparisonCohortId, expectedComparisonCohort, StringComparison.Ordinal) ||
                run.plannerInstanceCount != 1 ||
                run.persistentStateInstanceCount != expectedPersistentStates ||
                run.sharedFieldInstanceCount != expectedFields)
            {
                throw new ArgumentException("Fairness cohort or state-instance counts are inconsistent at index " + index + ".", "runs");
            }

            ValidateFiniteNonNegative(run.initialPlanningMilliseconds, "initialPlanningMilliseconds", index);
            ValidateFiniteNonNegative(run.dynamicHandlingTotalMilliseconds, "dynamicHandlingTotalMilliseconds", index);
            ValidateFiniteNonNegative(run.totalPlannerElapsedMillisecondsPerAgent, "totalPlannerElapsedMillisecondsPerAgent", index);
            ValidateFiniteNonNegative(run.processedNodesOrCellsPerAgent, "processedNodesOrCellsPerAgent", index);
            ValidateFiniteNonNegative(run.dynamicHandlingMillisecondsPerScheduledEvent, "dynamicHandlingMillisecondsPerScheduledEvent", index);
            ValidateFiniteNonNegative(run.dynamicProcessedNodesOrCellsPerScheduledEvent, "dynamicProcessedNodesOrCellsPerScheduledEvent", index);
            if (run.initializationProcessedNodesOrCells < 0L || run.initialPlanningProcessedNodesOrCells < 0L || run.dynamicProcessedNodesOrCells < 0L || run.dynamicManagedAllocatedBytes < 0L)
            {
                throw new ArgumentException("Fairness work decomposition is negative at index " + index + ".", "runs");
            }

            long phaseProcessed = 0L;
            double phaseElapsed = 0d;
            for (int phaseIndex = 0; phaseIndex < run.dynamicPhases.Length; phaseIndex++)
            {
                PlanningTickWorkloadRecord phase = run.dynamicPhases[phaseIndex];
                if (phase == null || phase.processedNodesOrCells < 0L || phase.managedAllocatedBytes < 0L ||
                    !NumbersEqual(phase.combinedElapsedMilliseconds, phase.repairElapsedMilliseconds + phase.replanElapsedMilliseconds))
                {
                    throw new ArgumentException("Dynamic-phase fairness accounting is invalid at index " + index + ".", "runs");
                }
                phaseProcessed = checked(phaseProcessed + phase.processedNodesOrCells);
                phaseElapsed += phase.combinedElapsedMilliseconds;
            }

            if (run.dynamicPhases.Length != run.dynamicPlanningPhaseCount ||
                phaseProcessed != run.dynamicProcessedNodesOrCells ||
                !NumbersEqual(phaseElapsed, run.dynamicHandlingTotalMilliseconds) ||
                run.processedNodesOrCells != checked(run.initializationProcessedNodesOrCells + run.initialPlanningProcessedNodesOrCells + run.dynamicProcessedNodesOrCells) ||
                !NumbersEqual(run.totalPlannerElapsedMilliseconds, run.initializationMilliseconds + run.initialPlanningMilliseconds + run.dynamicHandlingTotalMilliseconds) ||
                !NumbersEqual(run.totalPlannerElapsedMillisecondsPerAgent, run.totalPlannerElapsedMilliseconds / run.agentCount) ||
                !NumbersEqual(run.processedNodesOrCellsPerAgent, (double)run.processedNodesOrCells / run.agentCount))
            {
                throw new ArgumentException("Fairness totals or per-agent normalization are inconsistent at index " + index + ".", "runs");
            }

            double expectedDynamicElapsedPerEvent = run.scheduledEventCount == 0 ? 0d : run.dynamicHandlingTotalMilliseconds / run.scheduledEventCount;
            double expectedDynamicWorkPerEvent = run.scheduledEventCount == 0 ? 0d : (double)run.dynamicProcessedNodesOrCells / run.scheduledEventCount;
            if (!NumbersEqual(run.dynamicHandlingMillisecondsPerScheduledEvent, expectedDynamicElapsedPerEvent) ||
                !NumbersEqual(run.dynamicProcessedNodesOrCellsPerScheduledEvent, expectedDynamicWorkPerEvent))
            {
                throw new ArgumentException("Per-event fairness normalization is inconsistent at index " + index + ".", "runs");
            }
        }

        private static void ValidateFiniteNonNegative(double value, string field, int index)
        {
            if (double.IsNaN(value) || double.IsInfinity(value) || value < 0d) throw new ArgumentException(field + " is invalid at index " + index + ".", "runs");
        }

        private static void ValidateRate(double value, string field, int index)
        {
            if (double.IsNaN(value) || double.IsInfinity(value) || value < 0d || value > 1d) throw new ArgumentException(field + " is outside [0, 1] at index " + index + ".", "runs");
        }

        private static bool RatesEqual(double left, double right)
        {
            return Math.Abs(left - right) <= 1e-12d;
        }

        private static bool NumbersEqual(double left, double right)
        {
            double scale = Math.Max(1d, Math.Max(Math.Abs(left), Math.Abs(right)));
            return Math.Abs(left - right) <= 1e-9d * scale;
        }

        private static bool IsSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return false;
            }
            return true;
        }
    }
}
