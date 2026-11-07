using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using DDM.Research.Navigation;

namespace DDM.Research.Algorithms
{
    public struct CorrectedFlowFieldCellSnapshot
    {
        public bool Walkable { get; private set; }
        public bool Reachable { get; private set; }
        public bool IsActiveGoal { get; private set; }
        public double IntegrationCost { get; private set; }
        public bool HasOwnerGoal { get; private set; }
        public GridCoordinate OwnerGoal { get; private set; }
        public bool HasDirection { get; private set; }
        public GridCoordinate Next { get; private set; }

        internal CorrectedFlowFieldCellSnapshot(
            bool walkable,
            bool reachable,
            bool isActiveGoal,
            double integrationCost,
            bool hasOwnerGoal,
            GridCoordinate ownerGoal,
            bool hasDirection,
            GridCoordinate next)
        {
            Walkable = walkable;
            Reachable = reachable;
            IsActiveGoal = isActiveGoal;
            IntegrationCost = integrationCost;
            HasOwnerGoal = hasOwnerGoal;
            OwnerGoal = ownerGoal;
            HasDirection = hasDirection;
            Next = next;
        }
    }

    /// <summary>
    /// Deterministic shared multi-source flow field. Every accepted grid change
    /// rebuilds integration, ownership, and direction arrays from scratch.
    /// </summary>
    public sealed class CorrectedFullRecomputeFlowFieldPlanner : INavigationPlanner
    {
        private const double DiagonalDistance = 1.4142135623730951d;
        private const double ComparisonTolerance = 1e-12d;

        private static readonly NeighborOffset[] FourWayOffsets =
        {
            new NeighborOffset(0, -1),
            new NeighborOffset(-1, 0),
            new NeighborOffset(1, 0),
            new NeighborOffset(0, 1)
        };

        private static readonly NeighborOffset[] EightWayOffsets =
        {
            new NeighborOffset(-1, -1),
            new NeighborOffset(0, -1),
            new NeighborOffset(1, -1),
            new NeighborOffset(-1, 0),
            new NeighborOffset(1, 0),
            new NeighborOffset(-1, 1),
            new NeighborOffset(0, 1),
            new NeighborOffset(1, 1)
        };

        private IReadOnlyNavigationGrid grid;
        private HashSet<GridCoordinate> declaredGoalSet;
        private GridCoordinate[] canonicalGoals;
        private string runId;
        private string goalSetId;
        private NavigationGridConnectivity connectivity;
        private bool allowDiagonalCornerCutting;
        private bool initialized;
        private double cumulativePlanningMilliseconds;
        private FieldData field;

        public string AlgorithmId { get { return NavigationAlgorithmIds.CorrectedFullRecomputeFlowField; } }
        public NavigationPlannerCapabilities Capabilities
        {
            get { return NavigationPlannerCapabilities.SharedGoalField | NavigationPlannerCapabilities.FullRecompute; }
        }
        public long GridVersion { get; private set; }

        public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
        {
            if (initialized) throw new InvalidOperationException("Reset the C-FF planner before initializing it again.");
            if (grid == null) throw new ArgumentNullException("grid");
            if (initialization == null) throw new ArgumentNullException("initialization");
            if (grid.Width <= 0 || grid.Height <= 0) throw new ArgumentException("Grid dimensions must be positive.", "grid");
            int cellCount;
            try { cellCount = checked(grid.Width * grid.Height); }
            catch (OverflowException) { throw new ArgumentException("Grid cell count exceeds the supported range.", "grid"); }
            if (cellCount <= 0) throw new ArgumentException("Grid cell count must be positive.", "grid");
            if (string.IsNullOrWhiteSpace(initialization.runId)) throw new ArgumentException("Run id is required.", "initialization");
            if (string.IsNullOrWhiteSpace(initialization.goalSetId)) throw new ArgumentException("Goal-set id is required.", "initialization");
            if (!IsPositiveFinite(initialization.budgetMilliseconds)) throw new ArgumentOutOfRangeException("initialization", "Initialization budget must be finite and positive.");
            if (!Enum.IsDefined(typeof(NavigationGridConnectivity), initialization.connectivity)) throw new ArgumentException("Unsupported grid connectivity.", "initialization");
            if (initialization.goals == null || initialization.goals.Length == 0) throw new ArgumentException("At least one declared goal is required.", "initialization");

            HashSet<GridCoordinate> uniqueGoals = new HashSet<GridCoordinate>();
            for (int index = 0; index < initialization.goals.Length; index++)
            {
                GridCoordinate goal = initialization.goals[index];
                if (!grid.Contains(goal)) throw new ArgumentException("A declared goal is outside the grid: " + goal, "initialization");
                if (!grid.IsWalkable(goal)) throw new ArgumentException("A declared goal is blocked: " + goal, "initialization");
                uniqueGoals.Add(goal);
            }
            GridCoordinate[] goals = new GridCoordinate[uniqueGoals.Count];
            uniqueGoals.CopyTo(goals);
            Array.Sort(goals, CompareCoordinates);

            this.grid = grid;
            declaredGoalSet = uniqueGoals;
            canonicalGoals = goals;
            runId = initialization.runId;
            goalSetId = initialization.goalSetId;
            connectivity = initialization.connectivity;
            allowDiagonalCornerCutting = connectivity == NavigationGridConnectivity.EightWay && initialization.allowDiagonalCornerCutting;
            GridVersion = grid.Version;
            cumulativePlanningMilliseconds = 0d;

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();
            bool budgetExceeded;
            FieldData built = BuildCompleteField(stopwatch, initialization.budgetMilliseconds, ref counters, out budgetExceeded);
            field = built;
            initialized = true;
            return FinishMetrics(stopwatch, allocationBefore, counters, 0L, budgetExceeded);
        }

        public NavigationPlanResult Plan(NavigationPlanRequest request)
        {
            EnsureInitialized();
            if (request == null) throw new ArgumentNullException("request");
            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();

            if (!IsRequestIdentityValid(request) || request.agentId < 0 || !IsPositiveFinite(request.budgetMilliseconds))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (request.expectedGridVersion != GridVersion || grid.Version != GridVersion)
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StaleGridVersion, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!grid.Contains(request.start))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StartOutsideGrid, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!grid.Contains(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.GoalOutsideGrid, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!declaredGoalSet.Contains(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!grid.IsWalkable(request.start))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.StartBlocked, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!grid.IsWalkable(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.GoalBlocked, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (IsOverBudget(stopwatch, request.budgetMilliseconds))
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
            }

            int startIndex = ToIndex(request.start);
            if (double.IsPositiveInfinity(field.Integration[startIndex]) || !field.HasOwner[startIndex])
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.NoReachablePath, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!field.Owner[startIndex].Equals(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }

            List<GridCoordinate> path = new List<GridCoordinate>();
            GridCoordinate current = request.start;
            path.Add(current);
            int cellCount = field.Integration.Length;
            for (int step = 0; step <= cellCount; step++)
            {
                counters.Processed++;
                if (current.Equals(request.goal))
                {
                    return FinishPlan(NavigationPlanStatus.Succeeded, NavigationFailureReason.None, new ReadOnlyCollection<GridCoordinate>(path), stopwatch, allocationBefore, counters, false);
                }
                if (IsOverBudget(stopwatch, request.budgetMilliseconds))
                {
                    return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
                }

                int currentIndex = ToIndex(current);
                if (!field.HasDirection[currentIndex])
                {
                    return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
                }
                GridCoordinate next = field.Next[currentIndex];
                int nextIndex = ToIndex(next);
                if (!IsLegalForwardMove(current, next) || field.Integration[nextIndex] >= field.Integration[currentIndex])
                {
                    return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
                }
                current = next;
                path.Add(current);
            }
            return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
        }

        public NavigationRepairResult ApplyChanges(NavigationChangeSet changeSet, double repairBudgetMilliseconds)
        {
            EnsureInitialized();
            if (changeSet == null) throw new ArgumentNullException("changeSet");
            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();

            int changeCount = changeSet.changes == null ? 0 : changeSet.changes.Length;
            if (!IsPositiveFinite(repairBudgetMilliseconds) || string.IsNullOrWhiteSpace(changeSet.changeSetId) || changeCount == 0)
            {
                counters.Processed = changeCount;
                return FinishRepair(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, stopwatch, allocationBefore, counters, 0L, false);
            }
            if (changeSet.previousGridVersion != GridVersion || changeSet.newGridVersion != GridVersion + 1L || grid.Version != changeSet.newGridVersion)
            {
                return FinishRepair(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StaleGridVersion, stopwatch, allocationBefore, counters, 0L, false);
            }

            HashSet<GridCoordinate> seen = new HashSet<GridCoordinate>();
            for (int index = 0; index < changeSet.changes.Length; index++)
            {
                NavigationGridChange change = changeSet.changes[index];
                counters.Processed++;
                if (!grid.Contains(change.coordinate) || !seen.Add(change.coordinate) || !IsPositiveFinite(change.traversalCost) ||
                    grid.IsWalkable(change.coordinate) != change.isWalkable ||
                    Math.Abs(grid.GetTraversalCost(change.coordinate) - change.traversalCost) > ComparisonTolerance)
                {
                    return FinishRepair(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, stopwatch, allocationBefore, counters, 0L, false);
                }
            }

            bool budgetExceeded;
            FieldData rebuilt = BuildCompleteField(stopwatch, repairBudgetMilliseconds, ref counters, out budgetExceeded);
            field = rebuilt;
            GridVersion = changeSet.newGridVersion;
            long repairedCells = checked((long)grid.Width * grid.Height);
            return FinishRepair(
                budgetExceeded ? NavigationPlanStatus.BudgetExceeded : NavigationPlanStatus.Succeeded,
                budgetExceeded ? NavigationFailureReason.PlanningBudgetExceeded : NavigationFailureReason.None,
                stopwatch,
                allocationBefore,
                counters,
                repairedCells,
                budgetExceeded);
        }

        public bool TryGetCellSnapshot(GridCoordinate coordinate, out CorrectedFlowFieldCellSnapshot snapshot)
        {
            EnsureInitialized();
            snapshot = new CorrectedFlowFieldCellSnapshot();
            if (!grid.Contains(coordinate)) return false;
            int index = ToIndex(coordinate);
            bool reachable = !double.IsPositiveInfinity(field.Integration[index]);
            snapshot = new CorrectedFlowFieldCellSnapshot(
                grid.IsWalkable(coordinate),
                reachable,
                field.ActiveGoal[index],
                field.Integration[index],
                field.HasOwner[index],
                field.Owner[index],
                field.HasDirection[index],
                field.Next[index]);
            return true;
        }

        public void Reset()
        {
            grid = null;
            declaredGoalSet = null;
            canonicalGoals = null;
            runId = null;
            goalSetId = null;
            connectivity = default(NavigationGridConnectivity);
            allowDiagonalCornerCutting = false;
            initialized = false;
            cumulativePlanningMilliseconds = 0d;
            field = null;
            GridVersion = 0L;
        }

        private FieldData BuildCompleteField(Stopwatch stopwatch, double budgetMilliseconds, ref WorkCounters counters, out bool budgetExceeded)
        {
            int cellCount = checked(grid.Width * grid.Height);
            FieldData built = new FieldData(cellCount);
            int[] revisions = new int[cellCount];
            DeterministicIntegrationHeap heap = new DeterministicIntegrationHeap(Math.Max(4, canonicalGoals.Length));
            long sequence = 0L;
            budgetExceeded = false;

            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    float cost = grid.GetTraversalCost(coordinate);
                    counters.Processed++;
                    if (!IsPositiveFinite(cost)) throw new InvalidOperationException("Grid contains an invalid traversal cost at " + coordinate + ".");
                }
                if (IsOverBudget(stopwatch, budgetMilliseconds)) budgetExceeded = true;
            }

            for (int goalIndex = 0; goalIndex < canonicalGoals.Length; goalIndex++)
            {
                GridCoordinate goal = canonicalGoals[goalIndex];
                if (!grid.IsWalkable(goal)) continue;
                int index = ToIndex(goal);
                built.Integration[index] = 0d;
                built.HasOwner[index] = true;
                built.Owner[index] = goal;
                built.ActiveGoal[index] = true;
                revisions[index]++;
                heap.Push(new IntegrationNode(index, goal.x, goal.y, 0d, goal, revisions[index], sequence++));
            }

            while (heap.Count > 0)
            {
                IntegrationNode node = heap.Pop();
                counters.Processed++;
                if (node.Revision != revisions[node.Index] || !ValuesEqual(node.Distance, built.Integration[node.Index]) ||
                    !built.HasOwner[node.Index] || !node.Owner.Equals(built.Owner[node.Index]))
                {
                    continue;
                }
                counters.Expanded++;
                GridCoordinate destination = FromIndex(node.Index);
                NeighborOffset[] offsets = GetOffsets();
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    GridCoordinate predecessor = new GridCoordinate(destination.x - offsets[offsetIndex].X, destination.y - offsets[offsetIndex].Y);
                    if (!grid.Contains(predecessor) || !IsLegalForwardMove(predecessor, destination)) continue;
                    counters.Processed++;
                    int predecessorIndex = ToIndex(predecessor);
                    double candidate = built.Integration[node.Index] + ForwardEdgeCost(predecessor, destination);
                    bool lower = candidate < built.Integration[predecessorIndex] - ComparisonTolerance;
                    bool equalAndEarlierOwner = ValuesEqual(candidate, built.Integration[predecessorIndex]) &&
                        (!built.HasOwner[predecessorIndex] || CompareCoordinates(node.Owner, built.Owner[predecessorIndex]) < 0);
                    if (!lower && !equalAndEarlierOwner) continue;

                    if (lower) built.Integration[predecessorIndex] = candidate;
                    else if (candidate < built.Integration[predecessorIndex]) built.Integration[predecessorIndex] = candidate;
                    built.HasOwner[predecessorIndex] = true;
                    built.Owner[predecessorIndex] = node.Owner;
                    revisions[predecessorIndex]++;
                    counters.Relaxed++;
                    heap.Push(new IntegrationNode(
                        predecessorIndex,
                        predecessor.x,
                        predecessor.y,
                        built.Integration[predecessorIndex],
                        node.Owner,
                        revisions[predecessorIndex],
                        sequence++));
                }
                if (IsOverBudget(stopwatch, budgetMilliseconds)) budgetExceeded = true;
            }

            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate current = new GridCoordinate(x, y);
                    int currentIndex = ToIndex(current);
                    counters.Processed++;
                    if (!grid.IsWalkable(current) || double.IsPositiveInfinity(built.Integration[currentIndex]) || built.ActiveGoal[currentIndex]) continue;

                    DirectionCandidate best = new DirectionCandidate();
                    bool hasBest = false;
                    NeighborOffset[] offsets = GetOffsets();
                    for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                    {
                        GridCoordinate successor = new GridCoordinate(current.x + offsets[offsetIndex].X, current.y + offsets[offsetIndex].Y);
                        if (!grid.Contains(successor) || !IsLegalForwardMove(current, successor)) continue;
                        int successorIndex = ToIndex(successor);
                        if (!built.HasOwner[successorIndex] || double.IsPositiveInfinity(built.Integration[successorIndex])) continue;
                        counters.Processed++;
                        double total = ForwardEdgeCost(current, successor) + built.Integration[successorIndex];
                        if (!ValuesEqual(total, built.Integration[currentIndex])) continue;
                        DirectionCandidate candidate = new DirectionCandidate(total, built.Integration[successorIndex], built.Owner[successorIndex], successor);
                        if (!hasBest || CompareDirectionCandidates(candidate, best) < 0)
                        {
                            best = candidate;
                            hasBest = true;
                        }
                    }
                    if (!hasBest) throw new InvalidOperationException("Reachable non-goal cell has no optimal direction: " + current);
                    if (!built.Owner[currentIndex].Equals(best.Owner)) throw new InvalidOperationException("Integration owner and direction owner disagree at " + current + ".");
                    built.HasDirection[currentIndex] = true;
                    built.Next[currentIndex] = best.Successor;
                }
                if (IsOverBudget(stopwatch, budgetMilliseconds)) budgetExceeded = true;
            }

            if (IsOverBudget(stopwatch, budgetMilliseconds)) budgetExceeded = true;
            return built;
        }

        private bool IsLegalForwardMove(GridCoordinate from, GridCoordinate to)
        {
            if (!grid.Contains(from) || !grid.Contains(to) || !grid.IsWalkable(from) || !grid.IsWalkable(to)) return false;
            int deltaX = Math.Abs(to.x - from.x);
            int deltaY = Math.Abs(to.y - from.y);
            if (deltaX > 1 || deltaY > 1 || deltaX + deltaY == 0) return false;
            if (connectivity == NavigationGridConnectivity.FourWay) return deltaX + deltaY == 1;
            if (deltaX == 1 && deltaY == 1 && !allowDiagonalCornerCutting)
            {
                GridCoordinate horizontal = new GridCoordinate(to.x, from.y);
                GridCoordinate vertical = new GridCoordinate(from.x, to.y);
                if (!grid.IsWalkable(horizontal) || !grid.IsWalkable(vertical)) return false;
            }
            return true;
        }

        private double ForwardEdgeCost(GridCoordinate from, GridCoordinate to)
        {
            bool diagonal = from.x != to.x && from.y != to.y;
            return grid.GetTraversalCost(to) * (diagonal ? DiagonalDistance : 1d);
        }

        private NeighborOffset[] GetOffsets()
        {
            return connectivity == NavigationGridConnectivity.FourWay ? FourWayOffsets : EightWayOffsets;
        }

        private NavigationPlanResult FinishPlan(
            NavigationPlanStatus status,
            NavigationFailureReason reason,
            IReadOnlyList<GridCoordinate> path,
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
            bool budgetExceeded)
        {
            return new NavigationPlanResult(status, reason, path, GridVersion, FinishMetrics(stopwatch, allocationBefore, counters, 0L, budgetExceeded));
        }

        private NavigationRepairResult FinishRepair(
            NavigationPlanStatus status,
            NavigationFailureReason reason,
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
            long repairedCells,
            bool budgetExceeded)
        {
            return new NavigationRepairResult(status, reason, GridVersion, FinishMetrics(stopwatch, allocationBefore, counters, repairedCells, budgetExceeded));
        }

        private NavigationOperationMetrics FinishMetrics(
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
            long repairedCells,
            bool budgetExceeded)
        {
            stopwatch.Stop();
            AllocationSnapshot allocationAfter = CaptureAllocationSnapshot();
            cumulativePlanningMilliseconds += stopwatch.Elapsed.TotalMilliseconds;
            return new NavigationOperationMetrics
            {
                elapsedCpuMilliseconds = stopwatch.Elapsed.TotalMilliseconds,
                cumulativePlanningCpuMilliseconds = cumulativePlanningMilliseconds,
                processedNodesOrCells = counters.Processed,
                expandedNodes = counters.Expanded,
                relaxedEdges = counters.Relaxed,
                repairedCells = repairedCells,
                managedAllocatedBytes = MeasureAllocatedBytes(allocationBefore, allocationAfter),
                budgetExceeded = budgetExceeded
            };
        }

        private bool IsRequestIdentityValid(NavigationPlanRequest request)
        {
            return !string.IsNullOrWhiteSpace(request.requestId) &&
                   string.Equals(request.runId, runId, StringComparison.Ordinal) &&
                   string.Equals(request.goalSetId, goalSetId, StringComparison.Ordinal);
        }

        private int ToIndex(GridCoordinate coordinate)
        {
            return (coordinate.y * grid.Width) + coordinate.x;
        }

        private GridCoordinate FromIndex(int index)
        {
            return new GridCoordinate(index % grid.Width, index / grid.Width);
        }

        private void EnsureInitialized()
        {
            if (!initialized) throw new InvalidOperationException("The C-FF planner is not initialized.");
        }

        private static int CompareDirectionCandidates(DirectionCandidate left, DirectionCandidate right)
        {
            if (!ValuesEqual(left.Total, right.Total)) return left.Total.CompareTo(right.Total);
            int comparison = CompareCoordinates(left.Owner, right.Owner);
            if (comparison != 0) return comparison;
            if (!ValuesEqual(left.Remaining, right.Remaining)) return left.Remaining.CompareTo(right.Remaining);
            return CompareCoordinates(left.Successor, right.Successor);
        }

        private static int CompareCoordinates(GridCoordinate left, GridCoordinate right)
        {
            int comparison = left.y.CompareTo(right.y);
            return comparison != 0 ? comparison : left.x.CompareTo(right.x);
        }

        private static bool ValuesEqual(double left, double right)
        {
            if (double.IsPositiveInfinity(left) && double.IsPositiveInfinity(right)) return true;
            return Math.Abs(left - right) <= ComparisonTolerance;
        }

        private static bool IsOverBudget(Stopwatch stopwatch, double budgetMilliseconds)
        {
            return stopwatch.Elapsed.TotalMilliseconds > budgetMilliseconds;
        }

        private static bool IsPositiveFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value) && value > 0d;
        }

        private static bool IsPositiveFinite(float value)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value) && value > 0f;
        }

        private static AllocationSnapshot CaptureAllocationSnapshot()
        {
            return new AllocationSnapshot(GC.GetAllocatedBytesForCurrentThread(), GC.GetTotalMemory(false));
        }

        private static long MeasureAllocatedBytes(AllocationSnapshot before, AllocationSnapshot after)
        {
            if (before.ThreadBytes > 0L || after.ThreadBytes > 0L) return Math.Max(0L, after.ThreadBytes - before.ThreadBytes);
            return Math.Max(0L, after.TotalManagedBytes - before.TotalManagedBytes);
        }

        private static IReadOnlyList<GridCoordinate> EmptyPath()
        {
            return new GridCoordinate[0];
        }

        private sealed class FieldData
        {
            public readonly double[] Integration;
            public readonly bool[] HasOwner;
            public readonly GridCoordinate[] Owner;
            public readonly bool[] ActiveGoal;
            public readonly bool[] HasDirection;
            public readonly GridCoordinate[] Next;

            public FieldData(int cellCount)
            {
                Integration = new double[cellCount];
                HasOwner = new bool[cellCount];
                Owner = new GridCoordinate[cellCount];
                ActiveGoal = new bool[cellCount];
                HasDirection = new bool[cellCount];
                Next = new GridCoordinate[cellCount];
                for (int index = 0; index < cellCount; index++) Integration[index] = double.PositiveInfinity;
            }
        }

        private struct WorkCounters
        {
            public long Processed;
            public long Expanded;
            public long Relaxed;
        }

        private struct AllocationSnapshot
        {
            public readonly long ThreadBytes;
            public readonly long TotalManagedBytes;

            public AllocationSnapshot(long threadBytes, long totalManagedBytes)
            {
                ThreadBytes = threadBytes;
                TotalManagedBytes = totalManagedBytes;
            }
        }

        private struct NeighborOffset
        {
            public readonly int X;
            public readonly int Y;

            public NeighborOffset(int x, int y)
            {
                X = x;
                Y = y;
            }
        }

        private struct DirectionCandidate
        {
            public readonly double Total;
            public readonly double Remaining;
            public readonly GridCoordinate Owner;
            public readonly GridCoordinate Successor;

            public DirectionCandidate(double total, double remaining, GridCoordinate owner, GridCoordinate successor)
            {
                Total = total;
                Remaining = remaining;
                Owner = owner;
                Successor = successor;
            }
        }

        private struct IntegrationNode
        {
            public readonly int Index;
            public readonly int X;
            public readonly int Y;
            public readonly double Distance;
            public readonly GridCoordinate Owner;
            public readonly int Revision;
            public readonly long Sequence;

            public IntegrationNode(int index, int x, int y, double distance, GridCoordinate owner, int revision, long sequence)
            {
                Index = index;
                X = x;
                Y = y;
                Distance = distance;
                Owner = owner;
                Revision = revision;
                Sequence = sequence;
            }
        }

        private sealed class DeterministicIntegrationHeap
        {
            private IntegrationNode[] items;
            public int Count { get; private set; }

            public DeterministicIntegrationHeap(int capacity)
            {
                items = new IntegrationNode[Math.Max(4, capacity)];
            }

            public void Push(IntegrationNode item)
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

            public IntegrationNode Pop()
            {
                if (Count == 0) throw new InvalidOperationException("The C-FF integration heap is empty.");
                IntegrationNode root = items[0];
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
                IntegrationNode temporary = items[left];
                items[left] = items[right];
                items[right] = temporary;
            }

            private static int Compare(IntegrationNode left, IntegrationNode right)
            {
                int comparison = left.Distance.CompareTo(right.Distance);
                if (comparison != 0) return comparison;
                comparison = CompareCoordinates(left.Owner, right.Owner);
                if (comparison != 0) return comparison;
                comparison = left.Y.CompareTo(right.Y);
                if (comparison != 0) return comparison;
                comparison = left.X.CompareTo(right.X);
                if (comparison != 0) return comparison;
                return left.Sequence.CompareTo(right.Sequence);
            }
        }
    }
}
