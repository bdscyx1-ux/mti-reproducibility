using System;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;

namespace DDM.Research.MQ.V1
{
    [Serializable]
    public sealed class Gate14ReMQSemanticOperationV1
    {
        public int ordinal;
        public string operationType;
        public int eventGroupIndex;
        public int partitionIndex;
        public int agentIndex;
        public long gridVersion;
        public string status;
        public string failureReason;
        public bool oracleReachable;
        public double oracleCost;
        public int oracleSteps;
        public double reportedCost;
        public int reportedPathNodeCount;
        public string pathSignatureSha256;
        public bool idffRepairPendingBefore;
        public bool idffRepairPendingAfter;
    }

    [Serializable]
    public sealed class Gate14ReMQFieldCheckpointV1
    {
        public int ordinal;
        public string checkpointId;
        public int eventGroupIndex;
        public long gridVersion;
        public bool idffRepairPending;
        public string gridStateSha256;
        public string fieldStateSha256;
    }

    [Serializable]
    public sealed class Gate14ReMQSemanticTranscriptV1
    {
        public string schema;
        public string inputId;
        public string inputSha256;
        public string algorithmId;
        public int eventGroupLimit;
        public string status;
        public int operationCount;
        public int fieldCheckpointCount;
        public Gate14ReMQSemanticOperationV1[] operations = new Gate14ReMQSemanticOperationV1[0];
        public Gate14ReMQFieldCheckpointV1[] fieldCheckpoints = new Gate14ReMQFieldCheckpointV1[0];
        public string semanticTranscriptSha256;
    }

    /// <summary>
    /// Timing-free semantic kernel used by Gate13R-MQ. Each invocation creates a
    /// private grid and planner, applies event partitions serially, and verifies
    /// every query against the frozen algorithm-neutral reference oracle.
    /// </summary>
    public static class Gate14ReMQInputKernelV1
    {
        private const double TechnicalOperationBudgetMilliseconds = 600000d;

        public static Gate14ReMQSemanticTranscriptV1 RunSemantic(
            Gate14ReMEQualificationInputBundleV1 input,
            string inputSha256,
            string algorithmId,
            int eventGroupLimit)
        {
            ValidateInput(input, inputSha256, algorithmId, eventGroupLimit);
            ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
            INavigationPlanner planner = CreatePlanner(algorithmId);
            List<Gate14ReMQSemanticOperationV1> operations = new List<Gate14ReMQSemanticOperationV1>();
            List<Gate14ReMQFieldCheckpointV1> checkpoints = new List<Gate14ReMQFieldCheckpointV1>();
            string stableRunId = input.inputId + ":gate13r-mq-kernel-v1";

            try
            {
                NavigationOperationMetrics initialization = planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = stableRunId,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = TechnicalOperationBudgetMilliseconds
                });
                Require(initialization != null && !initialization.budgetExceeded,
                    "Planner initialization exceeded the technical qualification budget.");
                Require(planner.GridVersion == grid.Version, "Planner/grid versions differ after initialization.");
                operations.Add(NewOperation(
                    operations.Count, "initialize", -1, -1, -1, planner.GridVersion,
                    NavigationPlanStatus.Succeeded, NavigationFailureReason.None,
                    false, -1d, -1, -1d, 0, HashUtf8(string.Empty), false, IsRepairPending(planner)));
                AddCheckpoint(checkpoints, planner, grid, "after-initialization", -1);
                QueryAndValidateAll(input, planner, grid, stableRunId, "initial", -1, operations);
                AddCheckpoint(checkpoints, planner, grid, "after-initial-queries", -1);

                for (int groupIndex = 0; groupIndex < eventGroupLimit; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    Require(group != null && group.eventGroupIndex == groupIndex,
                        "Event-group index is not contiguous at " + groupIndex + ".");
                    Require(group.atomicPartitions != null && group.atomicPartitions.Length > 0,
                        "Event group contains no atomic partitions at " + groupIndex + ".");

                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        Require(partition != null && partition.partitionIndex == partitionIndex,
                            "Atomic-partition index is not contiguous at group " + groupIndex + ".");
                        Require(partition.changes != null && partition.changes.Length > 0,
                            "Atomic partition contains no changes at group " + groupIndex + ".");
                        bool pendingBefore = IsRepairPending(planner);
                        Require(!pendingBefore, "IDFF had a pending repair before a new atomic partition.");
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++)
                        {
                            changes[changeIndex] = partition.changes[changeIndex].ToChange();
                        }
                        NavigationChangeSet changeSet = grid.ApplyChanges(
                            group.eventGroupId + ":p" + partitionIndex.ToString(CultureInfo.InvariantCulture),
                            grid.Version,
                            changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, TechnicalOperationBudgetMilliseconds);
                        bool pendingAfter = IsRepairPending(planner);
                        Require(repair != null && repair.Status == NavigationPlanStatus.Succeeded &&
                                repair.FailureReason == NavigationFailureReason.None &&
                                repair.GridVersion == grid.Version && planner.GridVersion == grid.Version &&
                                repair.Metrics != null && !repair.Metrics.budgetExceeded && !pendingAfter,
                            "Repair did not reach a successful, queryable terminal state at group " + groupIndex +
                            ", partition " + partitionIndex + ".");
                        operations.Add(NewOperation(
                            operations.Count, "repair", groupIndex, partitionIndex, -1, repair.GridVersion,
                            repair.Status, repair.FailureReason, false, -1d, -1, -1d, 0,
                            HashUtf8(string.Empty), pendingBefore, pendingAfter));
                    }

                    QueryAndValidateAll(input, planner, grid, stableRunId, "event-" + groupIndex, groupIndex, operations);
                    AddCheckpoint(checkpoints, planner, grid, "after-event-group-" + groupIndex, groupIndex);
                }

                Gate14ReMQSemanticTranscriptV1 transcript = new Gate14ReMQSemanticTranscriptV1
                {
                    schema = "gate14re-mq-semantic-transcript-v1",
                    inputId = input.inputId,
                    inputSha256 = inputSha256,
                    algorithmId = algorithmId,
                    eventGroupLimit = eventGroupLimit,
                    status = "PASS_ORACLE_AND_SEMANTIC_KERNEL",
                    operationCount = operations.Count,
                    fieldCheckpointCount = checkpoints.Count,
                    operations = operations.ToArray(),
                    fieldCheckpoints = checkpoints.ToArray()
                };
                transcript.semanticTranscriptSha256 = ComputeSemanticTranscriptSha256(transcript);
                return transcript;
            }
            finally
            {
                planner.Reset();
            }
        }

        public static string ComputeSemanticTranscriptSha256(Gate14ReMQSemanticTranscriptV1 transcript)
        {
            if (transcript == null) throw new ArgumentNullException("transcript");
            StringBuilder canonical = new StringBuilder(4096);
            Append(canonical, transcript.schema);
            Append(canonical, transcript.inputId);
            Append(canonical, transcript.inputSha256);
            Append(canonical, transcript.algorithmId);
            Append(canonical, transcript.eventGroupLimit.ToString(CultureInfo.InvariantCulture));
            Append(canonical, transcript.status);
            Gate14ReMQSemanticOperationV1[] operations = transcript.operations ?? new Gate14ReMQSemanticOperationV1[0];
            for (int index = 0; index < operations.Length; index++)
            {
                Gate14ReMQSemanticOperationV1 row = operations[index];
                Require(row != null && row.ordinal == index, "Semantic-operation ordinals must be contiguous.");
                Append(canonical, row.ordinal.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.operationType);
                Append(canonical, row.eventGroupIndex.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.partitionIndex.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.agentIndex.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.gridVersion.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.status);
                Append(canonical, row.failureReason);
                Append(canonical, row.oracleReachable ? "1" : "0");
                Append(canonical, FormatDouble(row.oracleCost));
                Append(canonical, row.oracleSteps.ToString(CultureInfo.InvariantCulture));
                Append(canonical, FormatDouble(row.reportedCost));
                Append(canonical, row.reportedPathNodeCount.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.pathSignatureSha256);
                Append(canonical, row.idffRepairPendingBefore ? "1" : "0");
                Append(canonical, row.idffRepairPendingAfter ? "1" : "0");
            }
            Gate14ReMQFieldCheckpointV1[] checkpoints = transcript.fieldCheckpoints ?? new Gate14ReMQFieldCheckpointV1[0];
            for (int index = 0; index < checkpoints.Length; index++)
            {
                Gate14ReMQFieldCheckpointV1 row = checkpoints[index];
                Require(row != null && row.ordinal == index, "Field-checkpoint ordinals must be contiguous.");
                Append(canonical, row.ordinal.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.checkpointId);
                Append(canonical, row.eventGroupIndex.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.gridVersion.ToString(CultureInfo.InvariantCulture));
                Append(canonical, row.idffRepairPending ? "1" : "0");
                Append(canonical, row.gridStateSha256);
                Append(canonical, row.fieldStateSha256);
            }
            return HashUtf8(canonical.ToString());
        }

        private static void QueryAndValidateAll(
            Gate14ReMEQualificationInputBundleV1 input,
            INavigationPlanner planner,
            ResearchNavigationGrid grid,
            string runId,
            string phase,
            int eventGroupIndex,
            List<Gate14ReMQSemanticOperationV1> operations)
        {
            Gate14ReMEOraclePathV1[] oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
            Require(oracle.Length == input.starts.Length, "Oracle result cardinality differs from the start cardinality.");

            for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
            {
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
                Require(plan != null && plan.Metrics != null && !plan.Metrics.budgetExceeded,
                    "Plan exceeded the technical qualification budget at phase " + phase + ", agent " + agentIndex + ".");
                Require(plan.GridVersion == grid.Version && planner.GridVersion == grid.Version,
                    "Plan/grid version mismatch at phase " + phase + ", agent " + agentIndex + ".");
                double reportedCost = ValidatePlanAgainstOracle(
                    grid, input, agentIndex, plan, oracle[agentIndex], phase);
                operations.Add(NewOperation(
                    operations.Count, "query", eventGroupIndex, -1, agentIndex, plan.GridVersion,
                    plan.Status, plan.FailureReason, oracle[agentIndex].Reachable, oracle[agentIndex].Cost,
                    oracle[agentIndex].Steps, reportedCost, plan.Path == null ? 0 : plan.Path.Count,
                    ComputePathSha256(plan.Path), IsRepairPending(planner), IsRepairPending(planner)));
            }
        }

        private static double ValidatePlanAgainstOracle(
            ResearchNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            int agentIndex,
            NavigationPlanResult plan,
            Gate14ReMEOraclePathV1 oracle,
            string phase)
        {
            if (!oracle.Reachable)
            {
                Require(plan.Status == NavigationPlanStatus.NoPath,
                    "Oracle reports no path but planner status was " + plan.Status + " at " + phase + ", agent " + agentIndex + ".");
                NavigationFailureReason expectedReason = !grid.IsWalkable(input.starts[agentIndex])
                    ? NavigationFailureReason.StartBlocked
                    : (!grid.IsWalkable(input.goal) ? NavigationFailureReason.GoalBlocked : NavigationFailureReason.NoReachablePath);
                Require(plan.FailureReason == expectedReason,
                    "No-path failure reason mismatch at " + phase + ", agent " + agentIndex + ".");
                Require(plan.Path == null || plan.Path.Count == 0,
                    "No-path result unexpectedly contains path nodes at " + phase + ", agent " + agentIndex + ".");
                return -1d;
            }

            Require(plan.Status == NavigationPlanStatus.Succeeded && plan.FailureReason == NavigationFailureReason.None,
                "Oracle reports a path but planner did not succeed at " + phase + ", agent " + agentIndex + ".");
            Require(plan.Path != null && plan.Path.Count > 0,
                "Succeeded plan contains no path nodes at " + phase + ", agent " + agentIndex + ".");
            Require(plan.Path[0].Equals(input.starts[agentIndex]) && plan.Path[plan.Path.Count - 1].Equals(input.goal),
                "Succeeded path endpoints are invalid at " + phase + ", agent " + agentIndex + ".");

            double total = 0d;
            for (int index = 0; index < plan.Path.Count; index++)
            {
                GridCoordinate current = plan.Path[index];
                Require(grid.Contains(current) && grid.IsWalkable(current),
                    "Path contains an outside or blocked cell at " + phase + ", agent " + agentIndex + ".");
                if (index == 0) continue;
                GridCoordinate previous = plan.Path[index - 1];
                int dx = Math.Abs(current.x - previous.x);
                int dy = Math.Abs(current.y - previous.y);
                bool diagonal = dx == 1 && dy == 1;
                bool cardinal = dx + dy == 1;
                Require(cardinal || (input.connectivity == NavigationGridConnectivity.EightWay && diagonal),
                    "Path contains an illegal move at " + phase + ", agent " + agentIndex + ".");
                if (diagonal && !input.allowDiagonalCornerCutting)
                {
                    GridCoordinate sideA = new GridCoordinate(previous.x, current.y);
                    GridCoordinate sideB = new GridCoordinate(current.x, previous.y);
                    Require(grid.Contains(sideA) && grid.Contains(sideB) && grid.IsWalkable(sideA) && grid.IsWalkable(sideB),
                        "Path illegally cuts a blocked diagonal corner at " + phase + ", agent " + agentIndex + ".");
                }
                total += grid.GetTraversalCost(current) * (diagonal ? 1.4142135623730951d : 1d);
            }
            Require(Gate14ReMEReferenceOracleV1.NearlyEqual(total, oracle.Cost),
                "Planner path cost does not match the reference oracle at " + phase + ", agent " + agentIndex + ".");
            return total;
        }

        private static void AddCheckpoint(
            List<Gate14ReMQFieldCheckpointV1> checkpoints,
            INavigationPlanner planner,
            ResearchNavigationGrid grid,
            string checkpointId,
            int eventGroupIndex)
        {
            bool pending = IsRepairPending(planner);
            Require(!pending, "A field checkpoint cannot be captured while IDFF repair is pending.");
            checkpoints.Add(new Gate14ReMQFieldCheckpointV1
            {
                ordinal = checkpoints.Count,
                checkpointId = checkpointId,
                eventGroupIndex = eventGroupIndex,
                gridVersion = grid.Version,
                idffRepairPending = pending,
                gridStateSha256 = Gate14ReMEReferenceOracleV1.ComputeGridStateSha256(grid),
                fieldStateSha256 = ComputeFieldStateSha256(planner, grid)
            });
        }

        private static string ComputeFieldStateSha256(INavigationPlanner planner, ResearchNavigationGrid grid)
        {
            StringBuilder canonical = new StringBuilder(checked(grid.Width * grid.Height * 48));
            Append(canonical, planner.AlgorithmId);
            Append(canonical, grid.Width.ToString(CultureInfo.InvariantCulture));
            Append(canonical, grid.Height.ToString(CultureInfo.InvariantCulture));
            Append(canonical, grid.Version.ToString(CultureInfo.InvariantCulture));
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    bool walkable;
                    bool reachable;
                    bool activeGoal;
                    double integration;
                    bool hasOwner;
                    GridCoordinate owner;
                    bool hasDirection;
                    GridCoordinate next;
                    ReadSnapshot(planner, coordinate, out walkable, out reachable, out activeGoal,
                        out integration, out hasOwner, out owner, out hasDirection, out next);
                    Append(canonical,
                        x.ToString(CultureInfo.InvariantCulture) + "," +
                        y.ToString(CultureInfo.InvariantCulture) + "," +
                        (walkable ? "1" : "0") + "," +
                        (reachable ? "1" : "0") + "," +
                        (activeGoal ? "1" : "0") + "," +
                        FormatDouble(integration) + "," +
                        (hasOwner ? "1" : "0") + "," +
                        (hasOwner ? owner.x.ToString(CultureInfo.InvariantCulture) : "-") + "," +
                        (hasOwner ? owner.y.ToString(CultureInfo.InvariantCulture) : "-") + "," +
                        (hasDirection ? "1" : "0") + "," +
                        (hasDirection ? next.x.ToString(CultureInfo.InvariantCulture) : "-") + "," +
                        (hasDirection ? next.y.ToString(CultureInfo.InvariantCulture) : "-"));
                }
            }
            return HashUtf8(canonical.ToString());
        }

        private static void ReadSnapshot(
            INavigationPlanner planner,
            GridCoordinate coordinate,
            out bool walkable,
            out bool reachable,
            out bool activeGoal,
            out double integration,
            out bool hasOwner,
            out GridCoordinate owner,
            out bool hasDirection,
            out GridCoordinate next)
        {
            CorrectedFullRecomputeFlowFieldPlanner cff = planner as CorrectedFullRecomputeFlowFieldPlanner;
            if (cff != null)
            {
                CorrectedFlowFieldCellSnapshot value;
                Require(cff.TryGetCellSnapshot(coordinate, out value), "C-FF field snapshot is unavailable.");
                walkable = value.Walkable;
                reachable = value.Reachable;
                activeGoal = value.IsActiveGoal;
                integration = value.IntegrationCost;
                hasOwner = value.HasOwnerGoal;
                owner = value.OwnerGoal;
                hasDirection = value.HasDirection;
                next = value.Next;
                return;
            }
            IncrementalDynamicFlowFieldPlanner idff = planner as IncrementalDynamicFlowFieldPlanner;
            if (idff != null)
            {
                IncrementalFlowFieldCellSnapshot value;
                Require(idff.TryGetCellSnapshot(coordinate, out value), "IDFF field snapshot is unavailable.");
                walkable = value.Walkable;
                reachable = value.Reachable;
                activeGoal = value.IsActiveGoal;
                integration = value.IntegrationCost;
                hasOwner = value.HasOwnerGoal;
                owner = value.OwnerGoal;
                hasDirection = value.HasDirection;
                next = value.Next;
                return;
            }
            throw new NotSupportedException("Field snapshots are unsupported for algorithm " + planner.AlgorithmId + ".");
        }

        private static bool IsRepairPending(INavigationPlanner planner)
        {
            IncrementalDynamicFlowFieldPlanner idff = planner as IncrementalDynamicFlowFieldPlanner;
            return idff != null && idff.RepairPending;
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField)
                return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField)
                return new IncrementalDynamicFlowFieldPlanner();
            throw new NotSupportedException("Gate13R-MQ v1 supports only C-FF and IDFF.");
        }

        private static Gate14ReMQSemanticOperationV1 NewOperation(
            int ordinal,
            string operationType,
            int eventGroupIndex,
            int partitionIndex,
            int agentIndex,
            long gridVersion,
            NavigationPlanStatus status,
            NavigationFailureReason failureReason,
            bool oracleReachable,
            double oracleCost,
            int oracleSteps,
            double reportedCost,
            int reportedPathNodeCount,
            string pathSha256,
            bool pendingBefore,
            bool pendingAfter)
        {
            return new Gate14ReMQSemanticOperationV1
            {
                ordinal = ordinal,
                operationType = operationType,
                eventGroupIndex = eventGroupIndex,
                partitionIndex = partitionIndex,
                agentIndex = agentIndex,
                gridVersion = gridVersion,
                status = status.ToString(),
                failureReason = failureReason.ToString(),
                oracleReachable = oracleReachable,
                oracleCost = oracleCost,
                oracleSteps = oracleSteps,
                reportedCost = reportedCost,
                reportedPathNodeCount = reportedPathNodeCount,
                pathSignatureSha256 = pathSha256,
                idffRepairPendingBefore = pendingBefore,
                idffRepairPendingAfter = pendingAfter
            };
        }

        private static string ComputePathSha256(IReadOnlyList<GridCoordinate> path)
        {
            StringBuilder canonical = new StringBuilder();
            if (path != null)
            {
                for (int index = 0; index < path.Count; index++)
                {
                    canonical.Append(path[index].x.ToString(CultureInfo.InvariantCulture));
                    canonical.Append(',');
                    canonical.Append(path[index].y.ToString(CultureInfo.InvariantCulture));
                    canonical.Append('\n');
                }
            }
            return HashUtf8(canonical.ToString());
        }

        private static void ValidateInput(
            Gate14ReMEQualificationInputBundleV1 input,
            string inputSha256,
            string algorithmId,
            int eventGroupLimit)
        {
            Require(input != null, "Qualification input is required.");
            Require(input.schema == Gate14ReMEQualificationConstantsV1.InputSchema,
                "Qualification input schema is not the frozen v1 DTO schema.");
            Require(!string.IsNullOrWhiteSpace(input.inputId), "Qualification input id is required.");
            Require(IsSha256(inputSha256), "Input SHA-256 must be lower-case hexadecimal.");
            Require(algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField ||
                    algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField,
                "Only C-FF and IDFF are eligible for this MQ kernel.");
            Require(input.starts != null && input.starts.Length == input.agentCount && input.agentCount > 0,
                "Input start cardinality differs from agentCount.");
            Require(input.eventGroups != null && eventGroupLimit > 0 && eventGroupLimit <= input.eventGroups.Length,
                "Event-group limit is outside the input bundle.");
        }

        private static string FormatDouble(double value)
        {
            if (double.IsPositiveInfinity(value)) return "+INF";
            if (double.IsNegativeInfinity(value)) return "-INF";
            if (double.IsNaN(value)) return "NAN";
            return value.ToString("R", CultureInfo.InvariantCulture);
        }

        private static void Append(StringBuilder builder, string value)
        {
            string safe = value ?? string.Empty;
            builder.Append(safe.Length.ToString(CultureInfo.InvariantCulture));
            builder.Append(':');
            builder.Append(safe);
            builder.Append('\n');
        }

        private static string HashUtf8(string value)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty));
                StringBuilder text = new StringBuilder(hash.Length * 2);
                for (int index = 0; index < hash.Length; index++) text.Append(hash[index].ToString("x2", CultureInfo.InvariantCulture));
                return text.ToString();
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
