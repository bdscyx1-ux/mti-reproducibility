using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using DDM.Research.Navigation;

namespace DDM.Research.Algorithms
{
    /// <summary>
    /// Deterministic per-request A* baseline. No search state is reused between plans.
    /// Traversal cost is paid when entering a cell and diagonal distance is sqrt(2).
    /// </summary>
    public sealed class AStarRepeatedPlanner : INavigationPlanner
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
        private HashSet<GridCoordinate> declaredGoals;
        private string runId;
        private string goalSetId;
        private NavigationGridConnectivity connectivity;
        private bool allowDiagonalCornerCutting;
        private bool initialized;
        private double cumulativePlanningMilliseconds;

        public string AlgorithmId { get { return NavigationAlgorithmIds.AStarRepeated; } }
        public NavigationPlannerCapabilities Capabilities { get { return NavigationPlannerCapabilities.FullRecompute; } }
        public long GridVersion { get; private set; }

        public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
        {
            if (initialized) throw new InvalidOperationException("Reset the A*-R planner before initializing it again.");
            if (grid == null) throw new ArgumentNullException("grid");
            if (initialization == null) throw new ArgumentNullException("initialization");

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();

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

            HashSet<GridCoordinate> goals = new HashSet<GridCoordinate>();
            for (int index = 0; index < initialization.goals.Length; index++)
            {
                GridCoordinate goal = initialization.goals[index];
                if (!grid.Contains(goal)) throw new ArgumentException("A declared goal is outside the grid: " + goal, "initialization");
                if (!grid.IsWalkable(goal)) throw new ArgumentException("A declared goal is blocked: " + goal, "initialization");
                goals.Add(goal);
            }

            this.grid = grid;
            declaredGoals = goals;
            runId = initialization.runId;
            goalSetId = initialization.goalSetId;
            connectivity = initialization.connectivity;
            allowDiagonalCornerCutting = connectivity == NavigationGridConnectivity.EightWay && initialization.allowDiagonalCornerCutting;
            GridVersion = grid.Version;
            cumulativePlanningMilliseconds = 0d;
            initialized = true;

            return FinishMetrics(
                stopwatch,
                allocationBefore,
                initialization.goals.Length,
                0,
                0,
                0,
                stopwatch.Elapsed.TotalMilliseconds > initialization.budgetMilliseconds);
        }

        public NavigationPlanResult Plan(NavigationPlanRequest request)
        {
            EnsureInitialized();
            if (request == null) throw new ArgumentNullException("request");

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            long processed = 0;
            long expanded = 0;
            long relaxed = 0;

            if (!IsRequestIdentityValid(request) || !IsPositiveFinite(request.budgetMilliseconds) || request.agentId < 0)
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (request.expectedGridVersion != GridVersion || grid.Version != GridVersion)
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StaleGridVersion, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (!grid.Contains(request.start))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StartOutsideGrid, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (!grid.Contains(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.GoalOutsideGrid, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (!declaredGoals.Contains(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (!grid.IsWalkable(request.start))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.StartBlocked, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }
            if (!grid.IsWalkable(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.GoalBlocked, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }

            if (request.start.Equals(request.goal))
            {
                return FinishPlan(
                    NavigationPlanStatus.Succeeded,
                    NavigationFailureReason.None,
                    new ReadOnlyCollection<GridCoordinate>(new[] { request.start }),
                    stopwatch,
                    allocationBefore,
                    1,
                    0,
                    0,
                    false);
            }

            double minimumTraversalCost = double.PositiveInfinity;
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    processed++;
                    if (grid.IsWalkable(coordinate))
                    {
                        float cost = grid.GetTraversalCost(coordinate);
                        if (!IsPositiveFinite(cost))
                        {
                            return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InvalidGrid, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
                        }
                        if (cost < minimumTraversalCost) minimumTraversalCost = cost;
                    }

                    if ((processed & 63L) == 1L && IsOverBudget(stopwatch, request.budgetMilliseconds))
                    {
                        return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, true);
                    }
                }
            }

            if (double.IsPositiveInfinity(minimumTraversalCost))
            {
                return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InvalidGrid, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
            }

            int cellCount = checked(grid.Width * grid.Height);
            double[] scores = new double[cellCount];
            int[] predecessors = new int[cellCount];
            bool[] closed = new bool[cellCount];
            for (int index = 0; index < cellCount; index++)
            {
                scores[index] = double.PositiveInfinity;
                predecessors[index] = -1;
            }

            int startIndex = ToIndex(request.start);
            int goalIndex = ToIndex(request.goal);
            scores[startIndex] = 0d;
            DeterministicOpenHeap open = new DeterministicOpenHeap(Math.Min(cellCount, 256));
            long insertionSequence = 0;
            double startHeuristic = Heuristic(request.start, request.goal, minimumTraversalCost);
            open.Push(new OpenNode(startIndex, request.start.x, request.start.y, 0d, startHeuristic, insertionSequence++));

            NeighborOffset[] offsets = connectivity == NavigationGridConnectivity.FourWay ? FourWayOffsets : EightWayOffsets;
            while (open.Count > 0)
            {
                if (IsOverBudget(stopwatch, request.budgetMilliseconds))
                {
                    return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, true);
                }

                OpenNode currentNode = open.Pop();
                if (currentNode.G > scores[currentNode.Index] + ComparisonTolerance || closed[currentNode.Index]) continue;

                closed[currentNode.Index] = true;
                expanded++;
                processed++;
                if (currentNode.Index == goalIndex)
                {
                    IReadOnlyList<GridCoordinate> path = ReconstructPath(predecessors, startIndex, goalIndex, cellCount);
                    if (path == null)
                    {
                        return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
                    }
                    if (IsOverBudget(stopwatch, request.budgetMilliseconds))
                    {
                        return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, true);
                    }
                    return FinishPlan(NavigationPlanStatus.Succeeded, NavigationFailureReason.None, path, stopwatch, allocationBefore, processed, expanded, relaxed, false);
                }

                GridCoordinate current = new GridCoordinate(currentNode.X, currentNode.Y);
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    NeighborOffset offset = offsets[offsetIndex];
                    GridCoordinate neighbor = new GridCoordinate(current.x + offset.X, current.y + offset.Y);
                    if (!grid.Contains(neighbor) || !grid.IsWalkable(neighbor)) continue;

                    bool diagonal = offset.X != 0 && offset.Y != 0;
                    if (diagonal && !allowDiagonalCornerCutting)
                    {
                        GridCoordinate horizontal = new GridCoordinate(current.x + offset.X, current.y);
                        GridCoordinate vertical = new GridCoordinate(current.x, current.y + offset.Y);
                        if (!grid.IsWalkable(horizontal) || !grid.IsWalkable(vertical)) continue;
                    }

                    float traversalCost = grid.GetTraversalCost(neighbor);
                    if (!IsPositiveFinite(traversalCost))
                    {
                        return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InvalidGrid, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
                    }

                    int neighborIndex = ToIndex(neighbor);
                    double tentativeScore = currentNode.G + (traversalCost * (diagonal ? DiagonalDistance : 1d));
                    if (tentativeScore >= scores[neighborIndex] - ComparisonTolerance) continue;

                    predecessors[neighborIndex] = currentNode.Index;
                    scores[neighborIndex] = tentativeScore;
                    closed[neighborIndex] = false;
                    relaxed++;
                    double heuristic = Heuristic(neighbor, request.goal, minimumTraversalCost);
                    open.Push(new OpenNode(neighborIndex, neighbor.x, neighbor.y, tentativeScore, heuristic, insertionSequence++));
                }
            }

            if (IsOverBudget(stopwatch, request.budgetMilliseconds))
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, true);
            }
            return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.NoReachablePath, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, false);
        }

        public NavigationRepairResult ApplyChanges(NavigationChangeSet changeSet, double repairBudgetMilliseconds)
        {
            EnsureInitialized();
            if (changeSet == null) throw new ArgumentNullException("changeSet");

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            int changeCount = changeSet.changes == null ? 0 : changeSet.changes.Length;
            if (!IsPositiveFinite(repairBudgetMilliseconds) || changeCount == 0)
            {
                NavigationOperationMetrics invalidMetrics = FinishMetrics(stopwatch, allocationBefore, changeCount, 0, 0, 0, false);
                return new NavigationRepairResult(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, GridVersion, invalidMetrics);
            }

            if (changeSet.previousGridVersion != GridVersion ||
                changeSet.newGridVersion != changeSet.previousGridVersion + 1 ||
                grid.Version != changeSet.newGridVersion)
            {
                NavigationOperationMetrics staleMetrics = FinishMetrics(stopwatch, allocationBefore, changeCount, 0, 0, 0, false);
                return new NavigationRepairResult(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StaleGridVersion, GridVersion, staleMetrics);
            }

            GridVersion = changeSet.newGridVersion;
            bool budgetExceeded = IsOverBudget(stopwatch, repairBudgetMilliseconds);
            NavigationOperationMetrics metrics = FinishMetrics(stopwatch, allocationBefore, changeCount, 0, 0, 0, budgetExceeded);
            return new NavigationRepairResult(
                budgetExceeded ? NavigationPlanStatus.BudgetExceeded : NavigationPlanStatus.Succeeded,
                budgetExceeded ? NavigationFailureReason.PlanningBudgetExceeded : NavigationFailureReason.None,
                GridVersion,
                metrics);
        }

        public void Reset()
        {
            grid = null;
            declaredGoals = null;
            runId = null;
            goalSetId = null;
            connectivity = NavigationGridConnectivity.FourWay;
            allowDiagonalCornerCutting = false;
            GridVersion = 0;
            cumulativePlanningMilliseconds = 0d;
            initialized = false;
        }

        private NavigationPlanResult FinishPlan(
            NavigationPlanStatus status,
            NavigationFailureReason failureReason,
            IReadOnlyList<GridCoordinate> path,
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            long processed,
            long expanded,
            long relaxed,
            bool budgetExceeded)
        {
            NavigationOperationMetrics metrics = FinishMetrics(stopwatch, allocationBefore, processed, expanded, relaxed, 0, budgetExceeded);
            return new NavigationPlanResult(status, failureReason, path, GridVersion, metrics);
        }

        private NavigationOperationMetrics FinishMetrics(
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            long processed,
            long expanded,
            long relaxed,
            long repaired,
            bool budgetExceeded)
        {
            stopwatch.Stop();
            AllocationSnapshot allocationAfter = CaptureAllocationSnapshot();
            cumulativePlanningMilliseconds += stopwatch.Elapsed.TotalMilliseconds;
            return new NavigationOperationMetrics
            {
                elapsedCpuMilliseconds = stopwatch.Elapsed.TotalMilliseconds,
                cumulativePlanningCpuMilliseconds = cumulativePlanningMilliseconds,
                processedNodesOrCells = processed,
                expandedNodes = expanded,
                relaxedEdges = relaxed,
                repairedCells = repaired,
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

        private IReadOnlyList<GridCoordinate> ReconstructPath(int[] predecessors, int startIndex, int goalIndex, int cellCount)
        {
            List<GridCoordinate> reversePath = new List<GridCoordinate>();
            int current = goalIndex;
            for (int step = 0; step <= cellCount; step++)
            {
                reversePath.Add(FromIndex(current));
                if (current == startIndex)
                {
                    reversePath.Reverse();
                    return new ReadOnlyCollection<GridCoordinate>(reversePath);
                }
                current = predecessors[current];
                if (current < 0 || current >= cellCount) return null;
            }
            return null;
        }

        private double Heuristic(GridCoordinate from, GridCoordinate goal, double minimumTraversalCost)
        {
            int deltaX = Math.Abs(goal.x - from.x);
            int deltaY = Math.Abs(goal.y - from.y);
            if (connectivity == NavigationGridConnectivity.FourWay)
            {
                return (deltaX + deltaY) * minimumTraversalCost;
            }

            int minimum = Math.Min(deltaX, deltaY);
            int maximum = Math.Max(deltaX, deltaY);
            return (maximum + ((DiagonalDistance - 1d) * minimum)) * minimumTraversalCost;
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
            if (!initialized) throw new InvalidOperationException("The A*-R planner is not initialized.");
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
            if (before.ThreadBytes > 0L || after.ThreadBytes > 0L)
            {
                return Math.Max(0L, after.ThreadBytes - before.ThreadBytes);
            }
            return Math.Max(0L, after.TotalManagedBytes - before.TotalManagedBytes);
        }

        private static IReadOnlyList<GridCoordinate> EmptyPath()
        {
            return new GridCoordinate[0];
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

        private struct OpenNode
        {
            public readonly int Index;
            public readonly int X;
            public readonly int Y;
            public readonly double G;
            public readonly double H;
            public readonly double F;
            public readonly long Sequence;

            public OpenNode(int index, int x, int y, double g, double h, long sequence)
            {
                Index = index;
                X = x;
                Y = y;
                G = g;
                H = h;
                F = g + h;
                Sequence = sequence;
            }
        }

        private sealed class DeterministicOpenHeap
        {
            private OpenNode[] items;

            public int Count { get; private set; }

            public DeterministicOpenHeap(int capacity)
            {
                items = new OpenNode[Math.Max(4, capacity)];
            }

            public void Push(OpenNode item)
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

            public OpenNode Pop()
            {
                if (Count == 0) throw new InvalidOperationException("The A* open set is empty.");
                OpenNode root = items[0];
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
                OpenNode temporary = items[left];
                items[left] = items[right];
                items[right] = temporary;
            }

            private static int Compare(OpenNode left, OpenNode right)
            {
                int comparison = left.F.CompareTo(right.F);
                if (comparison != 0) return comparison;
                comparison = left.H.CompareTo(right.H);
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
