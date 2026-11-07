using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;

namespace DDM.Research.MQ.V2
{
    [Serializable]
    public sealed class Gate14ReMQFormalOutcomeV2
    {
        public int ordinal;
        public int eventGroupIndex;
        public int agentIndex;
        public bool reachable;
        public double reportedPathCost;
        public int reportedPathSteps;
        public string planStatus;
        public string failureReason;
        public string pathSignatureSha256;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalLaneResultV2
    {
        public string schema;
        public string inputId;
        public string superblockId;
        public string inputSha256;
        public string algorithmId;
        public int eventGroupCount;
        public int initialQueryCount;
        public int postEventQueryCount;
        public int totalQueryCount;
        public int repairCount;
        public int succeededQueryCount;
        public int noPathQueryCount;
        public double initializationWallMilliseconds;
        public double workloadWallMilliseconds;
        public double[] queryWallMilliseconds = new double[0];
        public double[] gridMutationAndRepairWallMilliseconds = new double[0];
        public double[] eventGroupWallMilliseconds = new double[0];
        public Gate14ReMQFormalOutcomeV2[] outcomes = new Gate14ReMQFormalOutcomeV2[0];
        public string workloadStartUtc;
        public string workloadEndUtc;
        public string terminalSemanticDigestSha256;
        public string status;
    }

    /// <summary>
    /// Formal MQ performance kernel. Planner work is identical to the previously
    /// qualified v1 kernel. It additionally records compact query outcomes so the
    /// runner can compare every result with the already-frozen algorithm-neutral
    /// oracle cache after the measured batch has ended. Oracle loading, hashing,
    /// and comparison are deliberately outside MultiQueryBatchRuntimeV1.
    /// </summary>
    public static class Gate14ReMQFormalPerformanceKernelV2
    {
        private const double TechnicalOperationBudgetMilliseconds = 600000d;

        public static Gate14ReMQFormalLaneResultV2 Run(
            Gate14ReMEQualificationInputBundleV1 input,
            string inputSha256,
            string algorithmId)
        {
            Validate(input, inputSha256, algorithmId);
            ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
            INavigationPlanner planner = CreatePlanner(algorithmId);
            List<double> queryTimes = new List<double>(checked((input.eventGroups.Length + 1) * input.starts.Length));
            List<double> repairTimes = new List<double>(input.eventGroups.Length * Math.Max(1, input.sameTickAtomicPartitions));
            List<double> eventTimes = new List<double>(input.eventGroups.Length);
            List<Gate14ReMQFormalOutcomeV2> outcomes = new List<Gate14ReMQFormalOutcomeV2>(
                checked((input.eventGroups.Length + 1) * input.starts.Length));
            StringBuilder semantic = new StringBuilder(8192);
            string runId = input.inputId + ":gate14re-mq-formal-performance-kernel-v2";
            int succeeded = 0;
            int noPath = 0;
            DateTimeOffset workloadStart = DateTimeOffset.UtcNow;
            Stopwatch workloadStopwatch = Stopwatch.StartNew();

            try
            {
                Stopwatch operation = Stopwatch.StartNew();
                NavigationOperationMetrics initialization = planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = runId,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = TechnicalOperationBudgetMilliseconds
                });
                operation.Stop();
                Require(initialization != null && !initialization.budgetExceeded && planner.GridVersion == grid.Version,
                    "Formal MQ initialization failed its hard gate.");
                double initializationMilliseconds = ToMilliseconds(operation.ElapsedTicks);
                AppendSemantic(semantic, "initialize", -1, -1, -1, planner.GridVersion,
                    NavigationPlanStatus.Succeeded, NavigationFailureReason.None, string.Empty);
                RunQueries(input, planner, grid, runId, "initial", -1, queryTimes, outcomes, semantic, ref succeeded, ref noPath);
                int initialQueryCount = input.starts.Length;

                for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    Require(group != null && group.eventGroupIndex == groupIndex && group.atomicPartitions != null,
                        "Formal MQ event-group structure is invalid at " + groupIndex + ".");
                    Stopwatch eventStopwatch = Stopwatch.StartNew();
                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        Require(partition != null && partition.partitionIndex == partitionIndex &&
                                partition.changes != null && partition.changes.Length > 0,
                            "Formal MQ atomic partition is invalid.");
                        Require(!IsRepairPending(planner), "IDFF entered a new partition with a pending repair.");
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++)
                            changes[changeIndex] = partition.changes[changeIndex].ToChange();

                        operation.Restart();
                        NavigationChangeSet changeSet = grid.ApplyChanges(
                            group.eventGroupId + ":p" + partitionIndex.ToString(CultureInfo.InvariantCulture),
                            grid.Version,
                            changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, TechnicalOperationBudgetMilliseconds);
                        operation.Stop();
                        repairTimes.Add(ToMilliseconds(operation.ElapsedTicks));
                        Require(repair != null && repair.Status == NavigationPlanStatus.Succeeded &&
                                repair.FailureReason == NavigationFailureReason.None && repair.Metrics != null &&
                                !repair.Metrics.budgetExceeded && repair.GridVersion == grid.Version &&
                                planner.GridVersion == grid.Version && !IsRepairPending(planner),
                            "Formal MQ repair failed its hard gate.");
                        AppendSemantic(semantic, "repair", groupIndex, partitionIndex, -1, repair.GridVersion,
                            repair.Status, repair.FailureReason, string.Empty);
                    }
                    RunQueries(input, planner, grid, runId, "event-" + groupIndex, groupIndex,
                        queryTimes, outcomes, semantic, ref succeeded, ref noPath);
                    eventStopwatch.Stop();
                    eventTimes.Add(ToMilliseconds(eventStopwatch.ElapsedTicks));
                }

                workloadStopwatch.Stop();
                DateTimeOffset workloadEnd = DateTimeOffset.UtcNow;
                int expectedQueries = checked((input.eventGroups.Length + 1) * input.starts.Length);
                Require(queryTimes.Count == expectedQueries && outcomes.Count == expectedQueries,
                    "Formal MQ query/outcome cardinality is invalid.");
                Require(repairTimes.Count == checked(input.eventGroups.Length * input.sameTickAtomicPartitions),
                    "Formal MQ repair cardinality is invalid.");
                return new Gate14ReMQFormalLaneResultV2
                {
                    schema = "gate14re-mq-formal-lane-result-v2",
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    inputSha256 = inputSha256,
                    algorithmId = algorithmId,
                    eventGroupCount = input.eventGroups.Length,
                    initialQueryCount = initialQueryCount,
                    postEventQueryCount = queryTimes.Count - initialQueryCount,
                    totalQueryCount = queryTimes.Count,
                    repairCount = repairTimes.Count,
                    succeededQueryCount = succeeded,
                    noPathQueryCount = noPath,
                    initializationWallMilliseconds = initializationMilliseconds,
                    workloadWallMilliseconds = ToMilliseconds(workloadStopwatch.ElapsedTicks),
                    queryWallMilliseconds = queryTimes.ToArray(),
                    gridMutationAndRepairWallMilliseconds = repairTimes.ToArray(),
                    eventGroupWallMilliseconds = eventTimes.ToArray(),
                    outcomes = outcomes.ToArray(),
                    workloadStartUtc = workloadStart.ToString("o"),
                    workloadEndUtc = workloadEnd.ToString("o"),
                    terminalSemanticDigestSha256 = HashText(semantic.ToString()),
                    status = "PASS_FORMAL_MQ_MEASURED_KERNEL_PENDING_EXTERNAL_ORACLE_CACHE_COMPARISON"
                };
            }
            finally
            {
                if (workloadStopwatch.IsRunning) workloadStopwatch.Stop();
                planner.Reset();
            }
        }

        private static void RunQueries(
            Gate14ReMEQualificationInputBundleV1 input,
            INavigationPlanner planner,
            ResearchNavigationGrid grid,
            string runId,
            string phase,
            int eventGroupIndex,
            List<double> queryTimes,
            List<Gate14ReMQFormalOutcomeV2> outcomes,
            StringBuilder semantic,
            ref int succeeded,
            ref int noPath)
        {
            for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
            {
                Stopwatch operation = Stopwatch.StartNew();
                NavigationPlanResult plan = planner.Plan(new NavigationPlanRequest
                {
                    runId = runId,
                    requestId = input.inputId + ":" + phase + ":agent:" + agentIndex,
                    goalSetId = input.inputId + ":shared-goal",
                    agentId = agentIndex,
                    start = input.starts[agentIndex],
                    goal = input.goal,
                    expectedGridVersion = grid.Version,
                    budgetMilliseconds = TechnicalOperationBudgetMilliseconds
                });
                operation.Stop();
                queryTimes.Add(ToMilliseconds(operation.ElapsedTicks));
                Require(plan != null && plan.Metrics != null && !plan.Metrics.budgetExceeded &&
                        plan.GridVersion == grid.Version && planner.GridVersion == grid.Version &&
                        !IsRepairPending(planner),
                    "Formal MQ query failed its version, budget, or repair-state gate.");

                bool reachable;
                double pathCost;
                int pathSteps;
                if (plan.Status == NavigationPlanStatus.Succeeded)
                {
                    Require(plan.FailureReason == NavigationFailureReason.None && plan.Path != null && plan.Path.Count > 0,
                        "Succeeded formal MQ query has invalid result structure.");
                    pathCost = ValidateAndComputePathCost(grid, input, agentIndex, plan.Path, phase);
                    pathSteps = plan.Path.Count - 1;
                    reachable = true;
                    succeeded++;
                }
                else if (plan.Status == NavigationPlanStatus.NoPath)
                {
                    Require(plan.FailureReason == NavigationFailureReason.StartBlocked ||
                            plan.FailureReason == NavigationFailureReason.GoalBlocked ||
                            plan.FailureReason == NavigationFailureReason.NoReachablePath,
                        "No-path formal MQ query has an invalid failure reason.");
                    Require(plan.Path == null || plan.Path.Count == 0,
                        "No-path formal MQ query unexpectedly contains path nodes.");
                    pathCost = -1d;
                    pathSteps = -1;
                    reachable = false;
                    noPath++;
                }
                else
                {
                    throw new InvalidOperationException("Formal MQ query reached ineligible status " + plan.Status + ".");
                }

                string signature = ComputePathSha256(plan.Path);
                outcomes.Add(new Gate14ReMQFormalOutcomeV2
                {
                    ordinal = outcomes.Count,
                    eventGroupIndex = eventGroupIndex,
                    agentIndex = agentIndex,
                    reachable = reachable,
                    reportedPathCost = pathCost,
                    reportedPathSteps = pathSteps,
                    planStatus = plan.Status.ToString(),
                    failureReason = plan.FailureReason.ToString(),
                    pathSignatureSha256 = signature
                });
                AppendSemantic(semantic, "query", eventGroupIndex, -1, agentIndex, plan.GridVersion,
                    plan.Status, plan.FailureReason, signature);
            }
        }

        private static double ValidateAndComputePathCost(
            ResearchNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            int agentIndex,
            IReadOnlyList<GridCoordinate> path,
            string phase)
        {
            Require(path[0].Equals(input.starts[agentIndex]) && path[path.Count - 1].Equals(input.goal),
                "Formal MQ path endpoints are invalid at " + phase + ", agent " + agentIndex + ".");
            double total = 0d;
            for (int index = 0; index < path.Count; index++)
            {
                GridCoordinate current = path[index];
                Require(grid.Contains(current) && grid.IsWalkable(current),
                    "Formal MQ path contains an outside or blocked cell.");
                if (index == 0) continue;
                GridCoordinate previous = path[index - 1];
                int dx = Math.Abs(current.x - previous.x);
                int dy = Math.Abs(current.y - previous.y);
                bool diagonal = dx == 1 && dy == 1;
                bool cardinal = dx + dy == 1;
                Require(cardinal || (input.connectivity == NavigationGridConnectivity.EightWay && diagonal),
                    "Formal MQ path contains an illegal move.");
                if (diagonal && !input.allowDiagonalCornerCutting)
                {
                    GridCoordinate sideA = new GridCoordinate(previous.x, current.y);
                    GridCoordinate sideB = new GridCoordinate(current.x, previous.y);
                    Require(grid.Contains(sideA) && grid.Contains(sideB) && grid.IsWalkable(sideA) && grid.IsWalkable(sideB),
                        "Formal MQ path illegally cuts a blocked corner.");
                }
                total += grid.GetTraversalCost(current) * (diagonal ? 1.4142135623730951d : 1d);
            }
            Require(total >= 0d && !double.IsNaN(total) && !double.IsInfinity(total),
                "Formal MQ reported path cost is invalid.");
            return total;
        }

        private static void AppendSemantic(
            StringBuilder semantic,
            string operationType,
            int eventGroupIndex,
            int partitionIndex,
            int agentIndex,
            long gridVersion,
            NavigationPlanStatus status,
            NavigationFailureReason reason,
            string pathFingerprint)
        {
            semantic.Append(operationType).Append('|')
                .Append(eventGroupIndex).Append('|')
                .Append(partitionIndex).Append('|')
                .Append(agentIndex).Append('|')
                .Append(gridVersion).Append('|')
                .Append(status).Append('|')
                .Append(reason).Append('|')
                .Append(pathFingerprint ?? string.Empty).Append('\n');
        }

        private static string ComputePathSha256(IReadOnlyList<GridCoordinate> path)
        {
            StringBuilder canonical = new StringBuilder();
            if (path != null)
            {
                for (int index = 0; index < path.Count; index++)
                    canonical.Append(path[index].x).Append(',').Append(path[index].y).Append(';');
            }
            return HashText(canonical.ToString());
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField)
                return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField)
                return new IncrementalDynamicFlowFieldPlanner();
            throw new NotSupportedException("Formal MQ v2 supports only C-FF and IDFF.");
        }

        private static bool IsRepairPending(INavigationPlanner planner)
        {
            IncrementalDynamicFlowFieldPlanner idff = planner as IncrementalDynamicFlowFieldPlanner;
            return idff != null && idff.RepairPending;
        }

        private static void Validate(Gate14ReMEQualificationInputBundleV1 input, string inputSha256, string algorithmId)
        {
            Require(input != null && input.schema == Gate14ReMEQualificationConstantsV1.InputSchema,
                "Formal MQ input schema is invalid.");
            Require(input.starts != null && input.starts.Length == input.agentCount && input.agentCount > 0,
                "Formal MQ start cardinality is invalid.");
            Require(input.eventGroups != null && input.eventGroups.Length == Gate14ReMEQualificationConstantsV1.EventGroupCount,
                "Formal MQ requires all 24 frozen event groups.");
            Require(IsSha256(inputSha256), "Formal MQ input SHA-256 is invalid.");
            Require(algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField ||
                    algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField,
                "Formal MQ supports only C-FF and IDFF.");
        }

        private static double ToMilliseconds(long ticks)
        {
            return ticks * (1000d / Stopwatch.Frequency);
        }

        private static string HashText(string value)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty));
                StringBuilder result = new StringBuilder(bytes.Length * 2);
                for (int index = 0; index < bytes.Length; index++)
                    result.Append(bytes[index].ToString("x2", CultureInfo.InvariantCulture));
                return result.ToString();
            }
        }

        private static bool IsSha256(string value)
        {
            if (value == null || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return false;
            }
            return true;
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
