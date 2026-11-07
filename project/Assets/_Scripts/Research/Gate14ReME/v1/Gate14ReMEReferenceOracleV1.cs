using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Grid;
using DDM.Research.Navigation;

namespace DDM.Research.Gate14ReME.V1
{
    public struct Gate14ReMEOraclePathV1
    {
        public bool Reachable;
        public double Cost;
        public int Steps;

        public Gate14ReMEOraclePathV1(bool reachable, double cost, int steps)
        {
            Reachable = reachable;
            Cost = cost;
            Steps = steps;
        }
    }

    /// <summary>
    /// Algorithm-neutral goal-rooted Dijkstra reference. Reverse relaxation uses
    /// the forward edge's destination-cell cost so its semantics match the six
    /// frozen planners without invoking any planner implementation.
    /// </summary>
    public static class Gate14ReMEReferenceOracleV1
    {
        public const string OracleId = "gate14re-me-goal-rooted-dijkstra-v1";
        private const double DiagonalDistance = 1.4142135623730951d;
        private const double Tolerance = 1e-12d;

        private static readonly GridCoordinate[] FourWayOffsets =
        {
            new GridCoordinate(0, -1),
            new GridCoordinate(-1, 0),
            new GridCoordinate(1, 0),
            new GridCoordinate(0, 1)
        };

        private static readonly GridCoordinate[] EightWayOffsets =
        {
            new GridCoordinate(-1, -1),
            new GridCoordinate(0, -1),
            new GridCoordinate(1, -1),
            new GridCoordinate(-1, 0),
            new GridCoordinate(1, 0),
            new GridCoordinate(-1, 1),
            new GridCoordinate(0, 1),
            new GridCoordinate(1, 1)
        };

        public static Gate14ReMEOraclePathV1[] Evaluate(
            IReadOnlyNavigationGrid grid,
            GridCoordinate goal,
            IReadOnlyList<GridCoordinate> starts,
            NavigationGridConnectivity connectivity,
            bool allowDiagonalCornerCutting)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            if (starts == null) throw new ArgumentNullException("starts");
            if (!grid.Contains(goal) || !grid.IsWalkable(goal))
            {
                throw new InvalidOperationException("The oracle goal must be contained and walkable.");
            }

            int cellCount = checked(grid.Width * grid.Height);
            double[] distances = new double[cellCount];
            int[] steps = new int[cellCount];
            for (int index = 0; index < cellCount; index++)
            {
                distances[index] = double.PositiveInfinity;
                steps[index] = int.MaxValue;
            }

            int goalIndex = ToIndex(goal, grid.Width);
            distances[goalIndex] = 0d;
            steps[goalIndex] = 0;
            DeterministicHeap heap = new DeterministicHeap(Math.Max(16, cellCount / 8));
            long sequence = 0L;
            heap.Push(new HeapNode(goalIndex, goal.x, goal.y, 0d, 0, sequence++));
            GridCoordinate[] offsets = connectivity == NavigationGridConnectivity.FourWay ? FourWayOffsets : EightWayOffsets;

            while (heap.Count > 0)
            {
                HeapNode node = heap.Pop();
                if (node.Cost > distances[node.Index] + Tolerance) continue;
                if (Math.Abs(node.Cost - distances[node.Index]) <= Tolerance && node.Steps > steps[node.Index]) continue;
                GridCoordinate current = new GridCoordinate(node.X, node.Y);

                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    GridCoordinate offset = offsets[offsetIndex];
                    GridCoordinate predecessor = new GridCoordinate(current.x + offset.x, current.y + offset.y);
                    if (!CanTraverse(grid, predecessor, current, connectivity, allowDiagonalCornerCutting)) continue;
                    bool diagonal = predecessor.x != current.x && predecessor.y != current.y;
                    double edgeCost = grid.GetTraversalCost(current) * (diagonal ? DiagonalDistance : 1d);
                    double candidate = node.Cost + edgeCost;
                    int candidateSteps = checked(node.Steps + 1);
                    int predecessorIndex = ToIndex(predecessor, grid.Width);
                    bool improves = candidate + Tolerance < distances[predecessorIndex];
                    bool equalButShorter = Math.Abs(candidate - distances[predecessorIndex]) <= Tolerance && candidateSteps < steps[predecessorIndex];
                    if (!improves && !equalButShorter) continue;
                    distances[predecessorIndex] = candidate;
                    steps[predecessorIndex] = candidateSteps;
                    heap.Push(new HeapNode(predecessorIndex, predecessor.x, predecessor.y, candidate, candidateSteps, sequence++));
                }
            }

            Gate14ReMEOraclePathV1[] result = new Gate14ReMEOraclePathV1[starts.Count];
            for (int index = 0; index < starts.Count; index++)
            {
                GridCoordinate start = starts[index];
                if (!grid.Contains(start) || !grid.IsWalkable(start))
                {
                    result[index] = new Gate14ReMEOraclePathV1(false, -1d, -1);
                    continue;
                }
                int startIndex = ToIndex(start, grid.Width);
                bool reachable = !double.IsPositiveInfinity(distances[startIndex]);
                result[index] = reachable
                    ? new Gate14ReMEOraclePathV1(true, distances[startIndex], steps[startIndex])
                    : new Gate14ReMEOraclePathV1(false, -1d, -1);
            }
            return result;
        }

        public static string ComputeGridStateSha256(IReadOnlyNavigationGrid grid)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            using (SHA256 sha = SHA256.Create())
            {
                byte[] dimensionBytes = Encoding.UTF8.GetBytes(grid.Width + "x" + grid.Height + "\n");
                sha.TransformBlock(dimensionBytes, 0, dimensionBytes.Length, null, 0);
                for (int y = 0; y < grid.Height; y++)
                {
                    for (int x = 0; x < grid.Width; x++)
                    {
                        GridCoordinate coordinate = new GridCoordinate(x, y);
                        byte[] row = Encoding.UTF8.GetBytes(
                            x + "," + y + "," +
                            (grid.IsWalkable(coordinate) ? "1" : "0") + "," +
                            grid.GetTraversalCost(coordinate).ToString("R", System.Globalization.CultureInfo.InvariantCulture) + "\n");
                        sha.TransformBlock(row, 0, row.Length, null, 0);
                    }
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                return ToLowerHex(sha.Hash);
            }
        }

        public static bool SameOracle(Gate14ReMEOraclePathV1[] left, Gate14ReMEOraclePathV1[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            for (int index = 0; index < left.Length; index++)
            {
                if (left[index].Reachable != right[index].Reachable) return false;
                if (left[index].Steps != right[index].Steps) return false;
                if (left[index].Reachable && !NearlyEqual(left[index].Cost, right[index].Cost)) return false;
            }
            return true;
        }

        public static bool NearlyEqual(double left, double right)
        {
            double scale = Math.Max(1d, Math.Max(Math.Abs(left), Math.Abs(right)));
            return Math.Abs(left - right) <= 1e-9d * scale;
        }

        private static bool CanTraverse(
            IReadOnlyNavigationGrid grid,
            GridCoordinate from,
            GridCoordinate to,
            NavigationGridConnectivity connectivity,
            bool allowDiagonalCornerCutting)
        {
            if (!grid.Contains(from) || !grid.Contains(to) || !grid.IsWalkable(from) || !grid.IsWalkable(to)) return false;
            int dx = to.x - from.x;
            int dy = to.y - from.y;
            int absoluteX = Math.Abs(dx);
            int absoluteY = Math.Abs(dy);
            if (connectivity == NavigationGridConnectivity.FourWay) return absoluteX + absoluteY == 1;
            if (absoluteX > 1 || absoluteY > 1 || absoluteX + absoluteY == 0) return false;
            if (absoluteX == 1 && absoluteY == 1 && !allowDiagonalCornerCutting)
            {
                GridCoordinate horizontal = new GridCoordinate(from.x + dx, from.y);
                GridCoordinate vertical = new GridCoordinate(from.x, from.y + dy);
                return grid.IsWalkable(horizontal) && grid.IsWalkable(vertical);
            }
            return true;
        }

        private static int ToIndex(GridCoordinate coordinate, int width)
        {
            return checked((coordinate.y * width) + coordinate.x);
        }

        private static string ToLowerHex(byte[] bytes)
        {
            StringBuilder builder = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++) builder.Append(bytes[index].ToString("x2"));
            return builder.ToString();
        }

        private struct HeapNode
        {
            public readonly int Index;
            public readonly int X;
            public readonly int Y;
            public readonly double Cost;
            public readonly int Steps;
            public readonly long Sequence;

            public HeapNode(int index, int x, int y, double cost, int steps, long sequence)
            {
                Index = index;
                X = x;
                Y = y;
                Cost = cost;
                Steps = steps;
                Sequence = sequence;
            }
        }

        private sealed class DeterministicHeap
        {
            private HeapNode[] items;
            public int Count { get; private set; }

            public DeterministicHeap(int capacity)
            {
                items = new HeapNode[Math.Max(4, capacity)];
            }

            public void Push(HeapNode item)
            {
                if (Count == items.Length) Array.Resize(ref items, checked(items.Length * 2));
                int index = Count++;
                items[index] = item;
                while (index > 0)
                {
                    int parent = (index - 1) / 2;
                    if (Compare(items[parent], items[index]) <= 0) break;
                    Swap(parent, index);
                    index = parent;
                }
            }

            public HeapNode Pop()
            {
                if (Count == 0) throw new InvalidOperationException("The oracle heap is empty.");
                HeapNode root = items[0];
                Count--;
                if (Count > 0)
                {
                    items[0] = items[Count];
                    int index = 0;
                    while (true)
                    {
                        int left = (index * 2) + 1;
                        if (left >= Count) break;
                        int right = left + 1;
                        int best = right < Count && Compare(items[right], items[left]) < 0 ? right : left;
                        if (Compare(items[index], items[best]) <= 0) break;
                        Swap(index, best);
                        index = best;
                    }
                }
                return root;
            }

            private void Swap(int left, int right)
            {
                HeapNode temporary = items[left];
                items[left] = items[right];
                items[right] = temporary;
            }

            private static int Compare(HeapNode left, HeapNode right)
            {
                int comparison = left.Cost.CompareTo(right.Cost);
                if (comparison != 0) return comparison;
                comparison = left.Steps.CompareTo(right.Steps);
                if (comparison != 0) return comparison;
                comparison = left.Y.CompareTo(right.Y);
                if (comparison != 0) return comparison;
                comparison = left.X.CompareTo(right.X);
                if (comparison != 0) return comparison;
                return left.Sequence.CompareTo(right.Sequence);
            }
        }
    }

    public sealed class Gate14ReMEGeometryValidationResultV1
    {
        public Gate14ReMEOraclePassReceiptV1 Receipt;
        public Gate14ReMEOracleAgentRawV1[] AgentRows;
        public Gate14ReMEOracleEventRawV1[] EventRows;
    }

    public static class Gate14ReMEInputGeometryValidatorV1
    {
        private static readonly int[] GridLevels = { 64, 128, 256 };
        private static readonly int[] AgentLevels = { 8, 32, 128, 512 };
        private static readonly int[] ChangeLevels = { 1, 9, 81, 225 };
        private static readonly int[] PartitionLevels = { 1, 4, 16 };
        private static readonly string[] Topologies = { "compact", "dispersed", "bottleneck" };
        private static readonly string[] Phases = { "block", "unblock_or_restore", "increase_cost", "decrease_or_restore_cost" };

        public static Gate14ReMEGeometryValidationResultV1 Validate(
            Gate14ReMEQualificationInputBundleV1 input,
            string inputRelativePath,
            string inputSha256,
            string oracleSourceRelativePath,
            string oracleSourceSha256)
        {
            ValidateInputHeader(input);
            ResearchNavigationGrid grid = BuildGrid(input);
            HashSet<GridCoordinate> startsSet = new HashSet<GridCoordinate>();
            for (int index = 0; index < input.starts.Length; index++)
            {
                GridCoordinate start = input.starts[index];
                Require(grid.Contains(start) && grid.IsWalkable(start), "Every start must be contained and walkable.");
                Require(!start.Equals(input.goal), "Every start must differ from the goal.");
                Require(startsSet.Add(start), "Starts must be unique.");
            }
            Require(grid.Contains(input.goal) && grid.IsWalkable(input.goal), "The goal must be contained and walkable.");

            List<Gate14ReMEOracleAgentRawV1> agentRows = new List<Gate14ReMEOracleAgentRawV1>();
            List<Gate14ReMEOracleEventRawV1> eventRows = new List<Gate14ReMEOracleEventRawV1>();
            Gate14ReMEOraclePathV1[] baseline = Gate14ReMEReferenceOracleV1.Evaluate(
                grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
            ValidateBaseline(input, baseline);
            AddAgentRows(agentRows, input, -1, "baseline", baseline, null, inputRelativePath, inputSha256);

            string cycleBaselineGridSha = string.Empty;
            Gate14ReMEOraclePathV1[] cycleBaselineOracle = null;
            double[] affectedFractions = new double[input.eventGroups.Length];
            int minimumAffectedAgents = Math.Max(1, (int)Math.Ceiling(input.agentCount * 0.05d));

            for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
            {
                Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                ValidateGroupHeader(input, group, groupIndex);
                Gate14ReMEOraclePathV1[] before = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                string beforeSha = Gate14ReMEReferenceOracleV1.ComputeGridStateSha256(grid);
                if (groupIndex % 4 == 0 || groupIndex % 4 == 2)
                {
                    cycleBaselineGridSha = beforeSha;
                    cycleBaselineOracle = before;
                }

                HashSet<GridCoordinate> changed = new HashSet<GridCoordinate>();
                for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                {
                    Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                    Require(partition != null && partition.partitionIndex == partitionIndex, "Atomic partition indices must be consecutive from zero.");
                    Require(partition.changes != null && partition.changes.Length > 0, "Every atomic partition must contain at least one change.");
                    NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                    for (int changeIndex = 0; changeIndex < partition.changes.Length; changeIndex++)
                    {
                        Gate14ReMECellStateV1 cell = partition.changes[changeIndex];
                        GridCoordinate coordinate = new GridCoordinate(cell.x, cell.y);
                        Require(changed.Add(coordinate), "A changed cell may occur only once in a complete event group.");
                        Require(!coordinate.Equals(input.goal) && !startsSet.Contains(coordinate), "Changed cells may not contain a start or the goal.");
                        changes[changeIndex] = cell.ToChange();
                    }
                    grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                }
                Require(changed.Count == input.changedCellCount, "Every event group must contain exactly F unique changed cells.");

                Gate14ReMEOraclePathV1[] after = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                string afterSha = Gate14ReMEReferenceOracleV1.ComputeGridStateSha256(grid);
                bool[] affected = new bool[input.agentCount];
                int affectedCount = 0;
                for (int agentIndex = 0; agentIndex < input.agentCount; agentIndex++)
                {
                    bool changedStatus = before[agentIndex].Reachable != after[agentIndex].Reachable;
                    bool changedCost = before[agentIndex].Reachable && after[agentIndex].Reachable &&
                                       !Gate14ReMEReferenceOracleV1.NearlyEqual(before[agentIndex].Cost, after[agentIndex].Cost);
                    affected[agentIndex] = changedStatus || changedCost;
                    if (affected[agentIndex]) affectedCount++;
                }
                double fraction = (double)affectedCount / input.agentCount;
                affectedFractions[groupIndex] = fraction;
                bool minimumPassed = affectedCount >= minimumAffectedAgents;
                bool bottleneckApplicable = input.changeTopology == "bottleneck" &&
                                            (group.phase == "block" || group.phase == "increase_cost");
                bool bottleneckPassed = !bottleneckApplicable || fraction >= 0.5d;
                bool restoreApplicable = group.phase == "unblock_or_restore" || group.phase == "decrease_or_restore_cost";
                bool restoreGridPassed = !restoreApplicable || string.Equals(afterSha, cycleBaselineGridSha, StringComparison.Ordinal);
                bool restoreOraclePassed = !restoreApplicable || Gate14ReMEReferenceOracleV1.SameOracle(after, cycleBaselineOracle);
                Require(minimumPassed, "Every event group must affect max(1, ceil(0.05*N)) agents.");
                Require(bottleneckPassed, "Bottleneck block/increase groups must affect at least half of agents.");
                Require(restoreGridPassed, "Restore groups must restore exact grid bytes.");
                Require(restoreOraclePassed, "Restore groups must restore all oracle statuses and costs.");

                AddAgentRows(agentRows, input, groupIndex, "before", before, affected, inputRelativePath, inputSha256);
                AddAgentRows(agentRows, input, groupIndex, "after", after, affected, inputRelativePath, inputSha256);
                eventRows.Add(new Gate14ReMEOracleEventRawV1
                {
                    recordId = input.inputId + ":oracle-event:" + groupIndex,
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    eventGroupId = group.eventGroupId,
                    eventGroupIndex = groupIndex,
                    cycleIndex = group.cycleIndex,
                    phase = group.phase,
                    topology = group.topology,
                    uniqueChangedCellCount = changed.Count,
                    affectedAgentCount = affectedCount,
                    affectedAgentFraction = fraction,
                    minimumAffectedAgentsPassed = minimumPassed,
                    bottleneckHalfAgentsRuleApplicable = bottleneckApplicable,
                    bottleneckHalfAgentsPassed = bottleneckPassed,
                    restoreGridBytesPassed = restoreGridPassed,
                    restoreOraclePassed = restoreOraclePassed,
                    beforeGridSha256 = beforeSha,
                    afterGridSha256 = afterSha,
                    sourceRelativePath = inputRelativePath,
                    sourceSha256 = inputSha256
                });
            }

            Array.Sort(affectedFractions);
            double medianAffectedFraction = Median(affectedFractions);
            Require(medianAffectedFraction >= 0.10d, "The median affected-agent fraction must be at least 0.10.");
            return new Gate14ReMEGeometryValidationResultV1
            {
                AgentRows = agentRows.ToArray(),
                EventRows = eventRows.ToArray(),
                Receipt = new Gate14ReMEOraclePassReceiptV1
                {
                    schema = Gate14ReMEQualificationConstantsV1.OracleReceiptSchema,
                    studyId = Gate14ReMEQualificationConstantsV1.StudyId,
                    protocolId = Gate14ReMEQualificationConstantsV1.ProtocolId,
                    status = "PASS_ALGORITHM_NEUTRAL_GEOMETRY",
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    inputRelativePath = inputRelativePath,
                    inputSha256 = inputSha256,
                    oracleSourceRelativePath = oracleSourceRelativePath,
                    oracleSourceSha256 = oracleSourceSha256,
                    agentRowCount = agentRows.Count,
                    eventGroupRowCount = eventRows.Count,
                    minimumAffectedAgentCount = minimumAffectedAgents,
                    medianAffectedAgentFraction = medianAffectedFraction,
                    allGeometryChecksPassed = true,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                }
            };
        }

        public static ResearchNavigationGrid BuildGrid(Gate14ReMEQualificationInputBundleV1 input)
        {
            NavigationGridChange[] overrides = new NavigationGridChange[input.initialCellOverrides == null ? 0 : input.initialCellOverrides.Length];
            for (int index = 0; index < overrides.Length; index++) overrides[index] = input.initialCellOverrides[index].ToChange();
            return new ResearchNavigationGrid(input.gridEdge, input.gridEdge, input.defaultTraversalCost, overrides);
        }

        private static void ValidateInputHeader(Gate14ReMEQualificationInputBundleV1 input)
        {
            Require(input != null, "The qualification input is required.");
            Require(input.schema == Gate14ReMEQualificationConstantsV1.InputSchema, "Unexpected input schema.");
            Require(input.studyId == Gate14ReMEQualificationConstantsV1.StudyId, "Unexpected study id.");
            Require(input.protocolId == Gate14ReMEQualificationConstantsV1.ProtocolId, "Unexpected protocol id.");
            Require(!string.IsNullOrWhiteSpace(input.inputId) && !string.IsNullOrWhiteSpace(input.superblockId), "Input and superblock ids are required.");
            Require(input.designRegion == "core" || input.designRegion == "stress", "Design region must be core or stress.");
            Require(Contains(GridLevels, input.gridEdge), "Grid edge is outside the frozen levels.");
            Require(Contains(AgentLevels, input.agentCount), "Agent count is outside the frozen levels.");
            Require(Contains(ChangeLevels, input.changedCellCount), "Changed-cell count is outside the frozen levels.");
            Require(Contains(PartitionLevels, input.sameTickAtomicPartitions), "Atomic-partition count is outside the frozen levels.");
            Require(Contains(Topologies, input.changeTopology), "Change topology is outside the frozen levels.");
            Require(input.starts != null && input.starts.Length == input.agentCount, "The number of starts must equal N.");
            Require(input.eventGroups != null && input.eventGroups.Length == Gate14ReMEQualificationConstantsV1.EventGroupCount, "Every input must contain 24 event groups.");
            Require(input.defaultTraversalCost > 0f && !float.IsNaN(input.defaultTraversalCost) && !float.IsInfinity(input.defaultTraversalCost), "Default traversal cost must be finite and positive.");
            if (input.graphProfile == "four_way_weighted_dense")
            {
                Require(input.connectivity == NavigationGridConnectivity.FourWay && !input.allowDiagonalCornerCutting, "The four-way profile has fixed connectivity semantics.");
            }
            else if (input.graphProfile == "eight_way_uniform_sparse")
            {
                Require(input.connectivity == NavigationGridConnectivity.EightWay, "The eight-way profile has fixed connectivity semantics.");
            }
            else throw new InvalidOperationException("Graph profile is outside the frozen levels.");
            if (input.designRegion == "stress")
            {
                Require(input.gridEdge == 256 && input.agentCount == 512 && input.changedCellCount == 225, "Stress inputs must use the frozen high corner.");
            }
        }

        private static void ValidateBaseline(Gate14ReMEQualificationInputBundleV1 input, Gate14ReMEOraclePathV1[] baseline)
        {
            int threshold = (int)Math.Ceiling(input.gridEdge / 4d);
            int longCount = 0;
            double[] steps = new double[baseline.Length];
            for (int index = 0; index < baseline.Length; index++)
            {
                Require(baseline[index].Reachable, "All baseline starts must be reachable.");
                Require(baseline[index].Steps >= 4, "Every baseline oracle path must have at least four steps.");
                if (baseline[index].Steps >= threshold) longCount++;
                steps[index] = baseline[index].Steps;
            }
            Require((double)longCount / baseline.Length >= 0.90d, "At least 90% of baseline paths must be at least ceil(G/4) steps.");
            Array.Sort(steps);
            Require(Median(steps) >= Math.Ceiling(input.gridEdge / 2d), "Median baseline path steps must be at least ceil(G/2).");
        }

        private static void ValidateGroupHeader(Gate14ReMEQualificationInputBundleV1 input, Gate14ReMEEventGroupV1 group, int groupIndex)
        {
            Require(group != null, "Event groups may not be null.");
            Require(group.eventGroupIndex == groupIndex, "Event-group indices must be consecutive from zero.");
            Require(group.cycleIndex == groupIndex / 4, "Event-group cycle index is inconsistent.");
            Require(group.phase == Phases[groupIndex % 4], "Event-group phase is inconsistent with the frozen cycle.");
            Require(group.topology == input.changeTopology, "Event-group topology must match the input context.");
            Require(!string.IsNullOrWhiteSpace(group.eventGroupId), "Event-group id is required.");
            Require(group.atomicPartitions != null && group.atomicPartitions.Length == input.sameTickAtomicPartitions, "Every group must use the frozen atomic-partition count.");
        }

        private static void AddAgentRows(
            List<Gate14ReMEOracleAgentRawV1> rows,
            Gate14ReMEQualificationInputBundleV1 input,
            int eventGroupIndex,
            string side,
            Gate14ReMEOraclePathV1[] values,
            bool[] affected,
            string sourceRelativePath,
            string sourceSha256)
        {
            for (int index = 0; index < values.Length; index++)
            {
                rows.Add(new Gate14ReMEOracleAgentRawV1
                {
                    recordId = string.Format("{0}:oracle-agent:{1}:{2}:{3}", input.inputId, eventGroupIndex, side, index),
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    eventGroupIndex = eventGroupIndex,
                    comparisonSide = side,
                    agentIndex = index,
                    startX = input.starts[index].x,
                    startY = input.starts[index].y,
                    goalX = input.goal.x,
                    goalY = input.goal.y,
                    reachable = values[index].Reachable,
                    shortestPathCost = values[index].Cost,
                    shortestPathSteps = values[index].Steps,
                    affected = affected != null && affected[index],
                    sourceRelativePath = sourceRelativePath,
                    sourceSha256 = sourceSha256
                });
            }
        }

        private static double Median(double[] sorted)
        {
            if (sorted == null || sorted.Length == 0) throw new InvalidOperationException("Median requires at least one value.");
            int middle = sorted.Length / 2;
            return sorted.Length % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2d;
        }

        private static bool Contains(int[] values, int value)
        {
            for (int index = 0; index < values.Length; index++) if (values[index] == value) return true;
            return false;
        }

        private static bool Contains(string[] values, string value)
        {
            for (int index = 0; index < values.Length; index++) if (values[index] == value) return true;
            return false;
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
