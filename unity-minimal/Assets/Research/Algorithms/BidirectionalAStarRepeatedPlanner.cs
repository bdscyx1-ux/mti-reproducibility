using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using DDM.Research.Navigation;

namespace DDM.Research.Algorithms
{
    /// <summary>
    /// Deterministic per-request bidirectional A*. No search state is reused between
    /// plans. The reverse frontier traverses the exact reverse of each directed
    /// enter-cost edge, preserving optimality on weighted grids.
    /// </summary>
    public sealed class BidirectionalAStarRepeatedPlanner : INavigationPlanner
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

        public string AlgorithmId { get { return NavigationAlgorithmIds.BidirectionalAStarRepeated; } }
        public NavigationPlannerCapabilities Capabilities { get { return NavigationPlannerCapabilities.FullRecompute; } }
        public long GridVersion { get; private set; }

        public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
        {
            if (initialized) throw new InvalidOperationException("Reset the BiA*-R planner before initializing it again.");
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
            double[] forwardScores = new double[cellCount];
            double[] backwardScores = new double[cellCount];
            int[] forwardPredecessors = new int[cellCount];
            int[] backwardSuccessors = new int[cellCount];
            bool[] forwardClosed = new bool[cellCount];
            bool[] backwardClosed = new bool[cellCount];
            for (int index = 0; index < cellCount; index++)
            {
                forwardScores[index] = double.PositiveInfinity;
                backwardScores[index] = double.PositiveInfinity;
                forwardPredecessors[index] = -1;
                backwardSuccessors[index] = -1;
            }

            int startIndex = ToIndex(request.start);
            int goalIndex = ToIndex(request.goal);
            forwardScores[startIndex] = 0d;
            backwardScores[goalIndex] = 0d;
            DeterministicOpenHeap forwardOpen = new DeterministicOpenHeap(Math.Min(cellCount, 256));
            DeterministicOpenHeap backwardOpen = new DeterministicOpenHeap(Math.Min(cellCount, 256));
            long forwardSequence = 0L;
            long backwardSequence = 0L;
            forwardOpen.Push(new OpenNode(
                startIndex,
                request.start.x,
                request.start.y,
                0d,
                Heuristic(request.start, request.goal, minimumTraversalCost),
                forwardSequence++));
            backwardOpen.Push(new OpenNode(
                goalIndex,
                request.goal.x,
                request.goal.y,
                0d,
                Heuristic(request.goal, request.start, minimumTraversalCost),
                backwardSequence++));

            double bestPathCost = double.PositiveInfinity;
            int bestMeetingIndex = -1;
            NeighborOffset[] offsets = connectivity == NavigationGridConnectivity.FourWay ? FourWayOffsets : EightWayOffsets;
            while (true)
            {
                if (IsOverBudget(stopwatch, request.budgetMilliseconds))
                {
                    return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, processed, expanded, relaxed, true);
                }

                OpenNode forwardTop;
                OpenNode backwardTop;
                bool hasForward = TryPeekValid(forwardOpen, forwardScores, forwardClosed, ref processed, out forwardTop);
                bool hasBackward = TryPeekValid(backwardOpen, backwardScores, backwardClosed, ref processed, out backwardTop);
                if (!hasForward && !hasBackward) break;
                if (bestMeetingIndex >= 0 &&
                    (!hasForward || forwardTop.F >= bestPathCost - ComparisonTolerance) &&
                    (!hasBackward || backwardTop.F >= bestPathCost - ComparisonTolerance))
                {
                    break;
                }

                bool expandForward = hasForward && (!hasBackward || CompareOpenNodes(forwardTop, backwardTop) <= 0);
                if (expandForward)
                {
                    OpenNode currentNode = forwardOpen.Pop();
                    if (currentNode.G > forwardScores[currentNode.Index] + ComparisonTolerance || forwardClosed[currentNode.Index]) continue;
                    forwardClosed[currentNode.Index] = true;
                    expanded++;
                    processed++;
                    ConsiderMeeting(currentNode.Index, forwardScores, backwardScores, ref bestPathCost, ref bestMeetingIndex);

                    GridCoordinate current = new GridCoordinate(currentNode.X, currentNode.Y);
                    for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                    {
                        NeighborOffset offset = offsets[offsetIndex];
                        GridCoordinate neighbor = new GridCoordinate(current.x + offset.X, current.y + offset.Y);
                        if (!grid.Contains(neighbor) || !CanTraverse(current, neighbor)) continue;
                        int neighborIndex = ToIndex(neighbor);
                        double tentativeScore = currentNode.G + EdgeCost(current, neighbor);
                        if (tentativeScore >= forwardScores[neighborIndex] - ComparisonTolerance) continue;

                        forwardPredecessors[neighborIndex] = currentNode.Index;
                        forwardScores[neighborIndex] = tentativeScore;
                        forwardClosed[neighborIndex] = false;
                        relaxed++;
                        forwardOpen.Push(new OpenNode(
                            neighborIndex,
                            neighbor.x,
                            neighbor.y,
                            tentativeScore,
                            Heuristic(neighbor, request.goal, minimumTraversalCost),
                            forwardSequence++));
                        ConsiderMeeting(neighborIndex, forwardScores, backwardScores, ref bestPathCost, ref bestMeetingIndex);
                    }
                }
                else
                {
                    OpenNode currentNode = backwardOpen.Pop();
                    if (currentNode.G > backwardScores[currentNode.Index] + ComparisonTolerance || backwardClosed[currentNode.Index]) continue;
                    backwardClosed[currentNode.Index] = true;
                    expanded++;
                    processed++;
                    ConsiderMeeting(currentNode.Index, forwardScores, backwardScores, ref bestPathCost, ref bestMeetingIndex);

                    GridCoordinate current = new GridCoordinate(currentNode.X, currentNode.Y);
                    for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                    {
                        NeighborOffset offset = offsets[offsetIndex];
                        GridCoordinate predecessor = new GridCoordinate(current.x + offset.X, current.y + offset.Y);
                        if (!grid.Contains(predecessor) || !CanTraverse(predecessor, current)) continue;
                        int predecessorIndex = ToIndex(predecessor);
                        // Reverse traversal must charge the original forward edge
                        // c(predecessor,current), hence current's enter cost.
                        double tentativeScore = currentNode.G + EdgeCost(predecessor, current);
                        if (tentativeScore >= backwardScores[predecessorIndex] - ComparisonTolerance) continue;

                        backwardSuccessors[predecessorIndex] = currentNode.Index;
                        backwardScores[predecessorIndex] = tentativeScore;
                        backwardClosed[predecessorIndex] = false;
                        relaxed++;
                        backwardOpen.Push(new OpenNode(
                            predecessorIndex,
                            predecessor.x,
                            predecessor.y,
                            tentativeScore,
                            Heuristic(predecessor, request.start, minimumTraversalCost),
                            backwardSequence++));
                        ConsiderMeeting(predecessorIndex, forwardScores, backwardScores, ref bestPathCost, ref bestMeetingIndex);
                    }
                }
            }

            if (bestMeetingIndex >= 0)
            {
                IReadOnlyList<GridCoordinate> path = ReconstructBidirectionalPath(
                    forwardPredecessors,
                    backwardSuccessors,
                    startIndex,
                    goalIndex,
                    bestMeetingIndex,
                    cellCount);
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

        private IReadOnlyList<GridCoordinate> ReconstructBidirectionalPath(
            int[] forwardPredecessors,
            int[] backwardSuccessors,
            int startIndex,
            int goalIndex,
            int meetingIndex,
            int cellCount)
        {
            IReadOnlyList<GridCoordinate> prefix = ReconstructPath(
                forwardPredecessors,
                startIndex,
                meetingIndex,
                cellCount);
            if (prefix == null) return null;

            List<GridCoordinate> path = new List<GridCoordinate>(prefix);
            int current = meetingIndex;
            for (int step = 0; step <= cellCount; step++)
            {
                if (current == goalIndex) return new ReadOnlyCollection<GridCoordinate>(path);
                current = backwardSuccessors[current];
                if (current < 0 || current >= cellCount) return null;
                path.Add(FromIndex(current));
            }
            return null;
        }

        private static void ConsiderMeeting(
            int index,
            double[] forwardScores,
            double[] backwardScores,
            ref double bestPathCost,
            ref int bestMeetingIndex)
        {
            double forward = forwardScores[index];
            double backward = backwardScores[index];
            if (double.IsPositiveInfinity(forward) || double.IsPositiveInfinity(backward)) return;
            double candidate = forward + backward;
            if (candidate < bestPathCost - ComparisonTolerance ||
                (Math.Abs(candidate - bestPathCost) <= ComparisonTolerance &&
                 (bestMeetingIndex < 0 || index < bestMeetingIndex)))
            {
                bestPathCost = candidate;
                bestMeetingIndex = index;
            }
        }

        private static bool TryPeekValid(
            DeterministicOpenHeap open,
            double[] scores,
            bool[] closed,
            ref long processed,
            out OpenNode node)
        {
            while (open.Count > 0)
            {
                OpenNode candidate = open.Peek();
                if (!closed[candidate.Index] && candidate.G <= scores[candidate.Index] + ComparisonTolerance)
                {
                    node = candidate;
                    return true;
                }
                open.Pop();
                processed++;
            }
            node = default(OpenNode);
            return false;
        }

        private static int CompareOpenNodes(OpenNode left, OpenNode right)
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

        private bool CanTraverse(GridCoordinate from, GridCoordinate to)
        {
            if (!grid.IsWalkable(from) || !grid.IsWalkable(to)) return false;
            int deltaX = to.x - from.x;
            int deltaY = to.y - from.y;
            int absoluteX = Math.Abs(deltaX);
            int absoluteY = Math.Abs(deltaY);
            if (absoluteX > 1 || absoluteY > 1 || absoluteX + absoluteY == 0) return false;
            if (connectivity == NavigationGridConnectivity.FourWay) return absoluteX + absoluteY == 1;
            if (absoluteX == 1 && absoluteY == 1 && !allowDiagonalCornerCutting)
            {
                GridCoordinate horizontal = new GridCoordinate(from.x + deltaX, from.y);
                GridCoordinate vertical = new GridCoordinate(from.x, from.y + deltaY);
                return grid.IsWalkable(horizontal) && grid.IsWalkable(vertical);
            }
            return true;
        }

        private double EdgeCost(GridCoordinate from, GridCoordinate to)
        {
            bool diagonal = from.x != to.x && from.y != to.y;
            return grid.GetTraversalCost(to) * (diagonal ? DiagonalDistance : 1d);
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
            if (!initialized) throw new InvalidOperationException("The BiA*-R planner is not initialized.");
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
                if (Count == 0) throw new InvalidOperationException("The bidirectional A* open set is empty.");
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

            public OpenNode Peek()
            {
                if (Count == 0) throw new InvalidOperationException("The bidirectional A* open set is empty.");
                return items[0];
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
