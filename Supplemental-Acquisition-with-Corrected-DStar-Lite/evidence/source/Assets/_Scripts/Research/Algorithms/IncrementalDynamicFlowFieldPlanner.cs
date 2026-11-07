using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using DDM.Research.Navigation;

namespace DDM.Research.Algorithms
{
    public struct IncrementalFlowFieldCellSnapshot
    {
        public bool Walkable { get; private set; }
        public bool Reachable { get; private set; }
        public bool IsActiveGoal { get; private set; }
        public double IntegrationCost { get; private set; }
        public bool HasOwnerGoal { get; private set; }
        public GridCoordinate OwnerGoal { get; private set; }
        public bool HasDirection { get; private set; }
        public GridCoordinate Next { get; private set; }

        internal IncrementalFlowFieldCellSnapshot(
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
    /// Deterministic shared multi-source flow field with resumable incremental
    /// g/rhs repair and dirty-region direction refresh.
    /// </summary>
    public sealed class IncrementalDynamicFlowFieldPlanner : INavigationPlanner
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

        private double[] gCost;
        private bool[] gHasOwner;
        private GridCoordinate[] gOwner;
        private double[] rhsCost;
        private bool[] rhsHasOwner;
        private GridCoordinate[] rhsOwner;
        private bool[] activeGoal;
        private bool[] hasDirection;
        private GridCoordinate[] next;
        private long[] queueRevisions;
        private DeterministicRepairHeap queue;
        private long sequence;

        private bool repairPending;
        private string pendingChangeSetId;
        private long pendingPreviousVersion;
        private long pendingNewVersion;
        private NavigationGridChange[] pendingChanges;
        private bool[] repairCounted;
        private bool[] directionDirty;
        private List<int> directionDirtyIndices;
        private int directionCursor;
        private bool directionPhaseReady;

        public string AlgorithmId { get { return NavigationAlgorithmIds.IncrementalDynamicFlowField; } }
        public NavigationPlannerCapabilities Capabilities
        {
            get { return NavigationPlannerCapabilities.SharedGoalField | NavigationPlannerCapabilities.IncrementalRepair; }
        }
        public long GridVersion { get; private set; }
        public bool RepairPending { get { return repairPending; } }

        public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
        {
            if (initialized) throw new InvalidOperationException("Reset the IDFF planner before initializing it again.");
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

            gCost = NewInfinityArray(cellCount);
            gHasOwner = new bool[cellCount];
            gOwner = new GridCoordinate[cellCount];
            rhsCost = NewInfinityArray(cellCount);
            rhsHasOwner = new bool[cellCount];
            rhsOwner = new GridCoordinate[cellCount];
            activeGoal = new bool[cellCount];
            hasDirection = new bool[cellCount];
            next = new GridCoordinate[cellCount];
            queueRevisions = new long[cellCount];
            queue = new DeterministicRepairHeap(Math.Max(4, canonicalGoals.Length));
            sequence = 0L;
            directionDirty = new bool[cellCount];
            directionDirtyIndices = new List<int>(cellCount);

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();
            bool budgetExceeded = false;

            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    if (!IsPositiveFinite(grid.GetTraversalCost(coordinate))) throw new InvalidOperationException("Grid contains an invalid traversal cost at " + coordinate + ".");
                    counters.Processed++;
                    MarkDirectionDirty(ToIndex(coordinate));
                }
                if (IsOverBudget(stopwatch, initialization.budgetMilliseconds)) budgetExceeded = true;
            }
            for (int goalIndex = 0; goalIndex < canonicalGoals.Length; goalIndex++)
            {
                UpdateVertex(ToIndex(canonicalGoals[goalIndex]), ref counters, false);
            }
            while (ProcessOneQueueVertex(ref counters, false))
            {
                if (IsOverBudget(stopwatch, initialization.budgetMilliseconds)) budgetExceeded = true;
            }
            directionDirtyIndices.Sort();
            for (int index = 0; index < directionDirtyIndices.Count; index++)
            {
                RefreshDirection(directionDirtyIndices[index], ref counters, false);
                if (IsOverBudget(stopwatch, initialization.budgetMilliseconds)) budgetExceeded = true;
            }
            ClearDirectionDirtyState();
            initialized = true;
            return FinishMetrics(stopwatch, allocationBefore, counters, budgetExceeded);
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

            if (repairPending && !ContinuePendingRepair(stopwatch, request.budgetMilliseconds, ref counters))
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
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
            if (!gHasOwner[startIndex] || double.IsPositiveInfinity(gCost[startIndex]))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.NoReachablePath, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            if (!gOwner[startIndex].Equals(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }

            List<GridCoordinate> path = new List<GridCoordinate>();
            GridCoordinate current = request.start;
            path.Add(current);
            for (int step = 0; step <= gCost.Length; step++)
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
                if (!hasDirection[currentIndex])
                {
                    return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
                }
                GridCoordinate successor = next[currentIndex];
                int successorIndex = ToIndex(successor);
                if (!IsLegalForwardMove(current, successor) || gCost[successorIndex] >= gCost[currentIndex])
                {
                    return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
                }
                current = successor;
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

            if (!IsPositiveFinite(repairBudgetMilliseconds))
            {
                return FinishRepair(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, stopwatch, allocationBefore, counters, false);
            }

            if (repairPending)
            {
                if (!MatchesPendingChangeSet(changeSet, ref counters))
                {
                    return FinishRepair(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, stopwatch, allocationBefore, counters, false);
                }
            }
            else
            {
                NavigationFailureReason validationFailure;
                NavigationGridChange[] normalized;
                if (!TryValidateNewChangeSet(changeSet, ref counters, out validationFailure, out normalized))
                {
                    return FinishRepair(NavigationPlanStatus.InvalidRequest, validationFailure, stopwatch, allocationBefore, counters, false);
                }
                BeginRepair(changeSet, normalized, ref counters);
            }

            bool completed = ContinuePendingRepair(stopwatch, repairBudgetMilliseconds, ref counters);
            return FinishRepair(
                completed ? NavigationPlanStatus.Succeeded : NavigationPlanStatus.BudgetExceeded,
                completed ? NavigationFailureReason.None : NavigationFailureReason.PlanningBudgetExceeded,
                stopwatch,
                allocationBefore,
                counters,
                !completed);
        }

        public bool TryGetCellSnapshot(GridCoordinate coordinate, out IncrementalFlowFieldCellSnapshot snapshot)
        {
            EnsureInitialized();
            snapshot = new IncrementalFlowFieldCellSnapshot();
            if (!grid.Contains(coordinate)) return false;
            if (repairPending) throw new InvalidOperationException("The IDFF field is not queryable while incremental repair is pending.");
            int index = ToIndex(coordinate);
            snapshot = new IncrementalFlowFieldCellSnapshot(
                grid.IsWalkable(coordinate),
                gHasOwner[index] && !double.IsPositiveInfinity(gCost[index]),
                activeGoal[index],
                gCost[index],
                gHasOwner[index],
                gOwner[index],
                hasDirection[index],
                next[index]);
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
            gCost = null;
            gHasOwner = null;
            gOwner = null;
            rhsCost = null;
            rhsHasOwner = null;
            rhsOwner = null;
            activeGoal = null;
            hasDirection = null;
            next = null;
            queueRevisions = null;
            queue = null;
            sequence = 0L;
            ClearPendingRepair();
            directionDirty = null;
            directionDirtyIndices = null;
            GridVersion = 0L;
        }

        private bool TryValidateNewChangeSet(
            NavigationChangeSet changeSet,
            ref WorkCounters counters,
            out NavigationFailureReason failure,
            out NavigationGridChange[] normalized)
        {
            failure = NavigationFailureReason.InvalidRequest;
            normalized = null;
            int count = changeSet.changes == null ? 0 : changeSet.changes.Length;
            if (string.IsNullOrWhiteSpace(changeSet.changeSetId) || count == 0) return false;
            if (changeSet.previousGridVersion != GridVersion || changeSet.newGridVersion != GridVersion + 1L || grid.Version != changeSet.newGridVersion)
            {
                failure = NavigationFailureReason.StaleGridVersion;
                return false;
            }

            normalized = (NavigationGridChange[])changeSet.changes.Clone();
            HashSet<GridCoordinate> seen = new HashSet<GridCoordinate>();
            for (int index = 0; index < normalized.Length; index++)
            {
                NavigationGridChange change = normalized[index];
                counters.Processed++;
                if (!grid.Contains(change.coordinate) || !seen.Add(change.coordinate) || !IsPositiveFinite(change.traversalCost) ||
                    grid.IsWalkable(change.coordinate) != change.isWalkable ||
                    Math.Abs(grid.GetTraversalCost(change.coordinate) - change.traversalCost) > ComparisonTolerance)
                {
                    failure = NavigationFailureReason.InvalidRequest;
                    normalized = null;
                    return false;
                }
            }
            Array.Sort(normalized, CompareChanges);
            return true;
        }

        private void BeginRepair(NavigationChangeSet changeSet, NavigationGridChange[] normalized, ref WorkCounters counters)
        {
            repairPending = true;
            pendingChangeSetId = changeSet.changeSetId;
            pendingPreviousVersion = changeSet.previousGridVersion;
            pendingNewVersion = changeSet.newGridVersion;
            pendingChanges = normalized;
            repairCounted = new bool[gCost.Length];
            directionPhaseReady = false;
            directionCursor = 0;
            ClearDirectionDirtyState();
            GridVersion = changeSet.newGridVersion;

            bool[] affected = new bool[gCost.Length];
            for (int changeIndex = 0; changeIndex < normalized.Length; changeIndex++)
            {
                GridCoordinate center = normalized[changeIndex].coordinate;
                for (int deltaY = -1; deltaY <= 1; deltaY++)
                {
                    for (int deltaX = -1; deltaX <= 1; deltaX++)
                    {
                        GridCoordinate coordinate = new GridCoordinate(center.x + deltaX, center.y + deltaY);
                        if (!grid.Contains(coordinate)) continue;
                        int index = ToIndex(coordinate);
                        affected[index] = true;
                        MarkDirectionDirty(index);
                    }
                }
            }
            for (int index = 0; index < affected.Length; index++)
            {
                if (affected[index]) UpdateVertex(index, ref counters, true);
            }
        }

        private bool ContinuePendingRepair(Stopwatch stopwatch, double budgetMilliseconds, ref WorkCounters counters)
        {
            if (!repairPending) return true;
            while (!directionPhaseReady)
            {
                if (IsOverBudget(stopwatch, budgetMilliseconds)) return false;
                if (!ProcessOneQueueVertex(ref counters, true))
                {
                    directionDirtyIndices.Sort();
                    directionPhaseReady = true;
                    directionCursor = 0;
                }
            }
            while (directionCursor < directionDirtyIndices.Count)
            {
                if (IsOverBudget(stopwatch, budgetMilliseconds)) return false;
                RefreshDirection(directionDirtyIndices[directionCursor++], ref counters, true);
            }
            ClearPendingRepair();
            ClearDirectionDirtyState();
            return true;
        }

        private bool MatchesPendingChangeSet(NavigationChangeSet changeSet, ref WorkCounters counters)
        {
            if (changeSet == null || !string.Equals(changeSet.changeSetId, pendingChangeSetId, StringComparison.Ordinal) ||
                changeSet.previousGridVersion != pendingPreviousVersion || changeSet.newGridVersion != pendingNewVersion ||
                changeSet.changes == null || changeSet.changes.Length != pendingChanges.Length || grid.Version != pendingNewVersion)
            {
                return false;
            }
            NavigationGridChange[] candidate = (NavigationGridChange[])changeSet.changes.Clone();
            Array.Sort(candidate, CompareChanges);
            for (int index = 0; index < candidate.Length; index++)
            {
                counters.Processed++;
                NavigationGridChange left = candidate[index];
                NavigationGridChange right = pendingChanges[index];
                if (!left.coordinate.Equals(right.coordinate) || left.isWalkable != right.isWalkable ||
                    Math.Abs(left.traversalCost - right.traversalCost) > ComparisonTolerance ||
                    !grid.Contains(left.coordinate) || grid.IsWalkable(left.coordinate) != left.isWalkable ||
                    Math.Abs(grid.GetTraversalCost(left.coordinate) - left.traversalCost) > ComparisonTolerance)
                {
                    return false;
                }
            }
            return true;
        }

        private bool ProcessOneQueueVertex(ref WorkCounters counters, bool countRepair)
        {
            RepairNode node;
            while (queue.Count > 0)
            {
                node = queue.Pop();
                counters.Processed++;
                if (node.Revision == queueRevisions[node.Index] && !PairsEqual(
                    gCost[node.Index], gHasOwner[node.Index], gOwner[node.Index],
                    rhsCost[node.Index], rhsHasOwner[node.Index], rhsOwner[node.Index]))
                {
                    counters.Expanded++;
                    int comparison = ComparePairs(
                        rhsCost[node.Index], rhsHasOwner[node.Index], rhsOwner[node.Index],
                        gCost[node.Index], gHasOwner[node.Index], gOwner[node.Index]);
                    if (comparison < 0)
                    {
                        SetG(node.Index, rhsCost[node.Index], rhsHasOwner[node.Index], rhsOwner[node.Index], ref counters, countRepair);
                        InvalidateQueueEntry(node.Index);
                        UpdatePredecessors(node.Index, ref counters, countRepair);
                    }
                    else
                    {
                        SetG(node.Index, double.PositiveInfinity, false, default(GridCoordinate), ref counters, countRepair);
                        UpdateVertex(node.Index, ref counters, countRepair);
                        UpdatePredecessors(node.Index, ref counters, countRepair);
                    }
                    return true;
                }
            }
            return false;
        }

        private void UpdatePredecessors(int vertexIndex, ref WorkCounters counters, bool countRepair)
        {
            GridCoordinate vertex = FromIndex(vertexIndex);
            NeighborOffset[] offsets = GetOffsets();
            for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
            {
                GridCoordinate predecessor = new GridCoordinate(vertex.x - offsets[offsetIndex].X, vertex.y - offsets[offsetIndex].Y);
                if (grid.Contains(predecessor)) UpdateVertex(ToIndex(predecessor), ref counters, countRepair);
            }
        }

        private void UpdateVertex(int index, ref WorkCounters counters, bool countRepair)
        {
            GridCoordinate coordinate = FromIndex(index);
            bool newActiveGoal = declaredGoalSet.Contains(coordinate) && grid.IsWalkable(coordinate);
            if (activeGoal[index] != newActiveGoal)
            {
                activeGoal[index] = newActiveGoal;
                MarkDirectionDependencies(index);
                if (countRepair) MarkRepairCell(index, ref counters);
            }

            double bestCost = double.PositiveInfinity;
            bool bestHasOwner = false;
            GridCoordinate bestOwner = default(GridCoordinate);
            if (newActiveGoal)
            {
                bestCost = 0d;
                bestHasOwner = true;
                bestOwner = coordinate;
            }
            else if (grid.IsWalkable(coordinate))
            {
                NeighborOffset[] offsets = GetOffsets();
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    GridCoordinate successor = new GridCoordinate(coordinate.x + offsets[offsetIndex].X, coordinate.y + offsets[offsetIndex].Y);
                    if (!grid.Contains(successor) || !IsLegalForwardMove(coordinate, successor)) continue;
                    int successorIndex = ToIndex(successor);
                    if (!gHasOwner[successorIndex] || double.IsPositiveInfinity(gCost[successorIndex])) continue;
                    counters.Processed++;
                    double candidateCost = ForwardEdgeCost(coordinate, successor) + gCost[successorIndex];
                    GridCoordinate candidateOwner = gOwner[successorIndex];
                    bool lower = candidateCost < bestCost - ComparisonTolerance;
                    bool equalEarlierOwner = ValuesEqual(candidateCost, bestCost) &&
                        (!bestHasOwner || CompareCoordinates(candidateOwner, bestOwner) < 0);
                    if (!lower && !equalEarlierOwner) continue;
                    bestCost = candidateCost;
                    bestHasOwner = true;
                    bestOwner = candidateOwner;
                    counters.Relaxed++;
                }
            }

            bool rhsChanged = !PairsEqual(rhsCost[index], rhsHasOwner[index], rhsOwner[index], bestCost, bestHasOwner, bestOwner);
            rhsCost[index] = bestCost;
            rhsHasOwner[index] = bestHasOwner;
            rhsOwner[index] = bestOwner;
            counters.Processed++;
            if (rhsChanged && countRepair) MarkRepairCell(index, ref counters);
            ScheduleVertex(index);
        }

        private void SetG(int index, double cost, bool hasOwnerValue, GridCoordinate owner, ref WorkCounters counters, bool countRepair)
        {
            if (PairsEqual(gCost[index], gHasOwner[index], gOwner[index], cost, hasOwnerValue, owner)) return;
            gCost[index] = cost;
            gHasOwner[index] = hasOwnerValue;
            gOwner[index] = owner;
            MarkDirectionDependencies(index);
            if (countRepair) MarkRepairCell(index, ref counters);
        }

        private void ScheduleVertex(int index)
        {
            queueRevisions[index] = checked(queueRevisions[index] + 1L);
            if (PairsEqual(gCost[index], gHasOwner[index], gOwner[index], rhsCost[index], rhsHasOwner[index], rhsOwner[index])) return;
            bool rhsEarlier = ComparePairs(rhsCost[index], rhsHasOwner[index], rhsOwner[index], gCost[index], gHasOwner[index], gOwner[index]) < 0;
            double keyCost = rhsEarlier ? rhsCost[index] : gCost[index];
            bool keyHasOwner = rhsEarlier ? rhsHasOwner[index] : gHasOwner[index];
            GridCoordinate keyOwner = rhsEarlier ? rhsOwner[index] : gOwner[index];
            GridCoordinate coordinate = FromIndex(index);
            queue.Push(new RepairNode(index, coordinate.x, coordinate.y, keyCost, keyHasOwner, keyOwner, queueRevisions[index], sequence++));
        }

        private void InvalidateQueueEntry(int index)
        {
            queueRevisions[index] = checked(queueRevisions[index] + 1L);
        }

        private void MarkDirectionDependencies(int index)
        {
            MarkDirectionDirty(index);
            GridCoordinate coordinate = FromIndex(index);
            NeighborOffset[] offsets = GetOffsets();
            for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
            {
                GridCoordinate predecessor = new GridCoordinate(coordinate.x - offsets[offsetIndex].X, coordinate.y - offsets[offsetIndex].Y);
                if (grid.Contains(predecessor)) MarkDirectionDirty(ToIndex(predecessor));
            }
        }

        private void MarkDirectionDirty(int index)
        {
            if (directionDirty[index]) return;
            directionDirty[index] = true;
            directionDirtyIndices.Add(index);
        }

        private void RefreshDirection(int index, ref WorkCounters counters, bool countRepair)
        {
            GridCoordinate current = FromIndex(index);
            if (countRepair) MarkRepairCell(index, ref counters);
            counters.Processed++;
            hasDirection[index] = false;
            next[index] = default(GridCoordinate);
            if (!grid.IsWalkable(current) || !gHasOwner[index] || double.IsPositiveInfinity(gCost[index]) || activeGoal[index]) return;

            bool found = false;
            DirectionCandidate best = new DirectionCandidate();
            NeighborOffset[] offsets = GetOffsets();
            for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
            {
                GridCoordinate successor = new GridCoordinate(current.x + offsets[offsetIndex].X, current.y + offsets[offsetIndex].Y);
                if (!grid.Contains(successor) || !IsLegalForwardMove(current, successor)) continue;
                int successorIndex = ToIndex(successor);
                if (!gHasOwner[successorIndex] || double.IsPositiveInfinity(gCost[successorIndex])) continue;
                counters.Processed++;
                double total = ForwardEdgeCost(current, successor) + gCost[successorIndex];
                if (!ValuesEqual(total, gCost[index])) continue;
                DirectionCandidate candidate = new DirectionCandidate(total, gCost[successorIndex], gOwner[successorIndex], successor);
                if (!found || CompareDirectionCandidates(candidate, best) < 0)
                {
                    found = true;
                    best = candidate;
                }
            }
            if (!found) throw new InvalidOperationException("Reachable IDFF cell has no optimal direction: " + current);
            if (!gOwner[index].Equals(best.Owner)) throw new InvalidOperationException("IDFF integration owner and direction owner disagree at " + current + ".");
            hasDirection[index] = true;
            next[index] = best.Successor;
        }

        private void MarkRepairCell(int index, ref WorkCounters counters)
        {
            if (repairCounted == null || repairCounted[index]) return;
            repairCounted[index] = true;
            counters.Repaired++;
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
                return grid.IsWalkable(horizontal) && grid.IsWalkable(vertical);
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
            return new NavigationPlanResult(status, reason, path, GridVersion, FinishMetrics(stopwatch, allocationBefore, counters, budgetExceeded));
        }

        private NavigationRepairResult FinishRepair(
            NavigationPlanStatus status,
            NavigationFailureReason reason,
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
            bool budgetExceeded)
        {
            return new NavigationRepairResult(status, reason, GridVersion, FinishMetrics(stopwatch, allocationBefore, counters, budgetExceeded));
        }

        private NavigationOperationMetrics FinishMetrics(
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
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
                repairedCells = counters.Repaired,
                managedAllocatedBytes = MeasureAllocatedBytes(allocationBefore, allocationAfter),
                budgetExceeded = budgetExceeded
            };
        }

        private void ClearPendingRepair()
        {
            repairPending = false;
            pendingChangeSetId = null;
            pendingPreviousVersion = 0L;
            pendingNewVersion = 0L;
            pendingChanges = null;
            repairCounted = null;
            directionPhaseReady = false;
            directionCursor = 0;
        }

        private void ClearDirectionDirtyState()
        {
            if (directionDirty != null) Array.Clear(directionDirty, 0, directionDirty.Length);
            if (directionDirtyIndices != null) directionDirtyIndices.Clear();
            directionCursor = 0;
            directionPhaseReady = false;
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
            if (!initialized) throw new InvalidOperationException("The IDFF planner is not initialized.");
        }

        private static int ComparePairs(
            double leftCost, bool leftHasOwner, GridCoordinate leftOwner,
            double rightCost, bool rightHasOwner, GridCoordinate rightOwner)
        {
            if (!leftHasOwner) return rightHasOwner ? 1 : 0;
            if (!rightHasOwner) return -1;
            if (leftCost < rightCost - ComparisonTolerance) return -1;
            if (leftCost > rightCost + ComparisonTolerance) return 1;
            return CompareCoordinates(leftOwner, rightOwner);
        }

        private static bool PairsEqual(
            double leftCost, bool leftHasOwner, GridCoordinate leftOwner,
            double rightCost, bool rightHasOwner, GridCoordinate rightOwner)
        {
            if (leftHasOwner != rightHasOwner) return false;
            if (!leftHasOwner) return true;
            return ValuesEqual(leftCost, rightCost) && leftOwner.Equals(rightOwner);
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

        private static int CompareChanges(NavigationGridChange left, NavigationGridChange right)
        {
            return CompareCoordinates(left.coordinate, right.coordinate);
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

        private static double[] NewInfinityArray(int count)
        {
            double[] values = new double[count];
            for (int index = 0; index < count; index++) values[index] = double.PositiveInfinity;
            return values;
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

        private struct WorkCounters
        {
            public long Processed;
            public long Expanded;
            public long Relaxed;
            public long Repaired;
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

        private struct RepairNode
        {
            public readonly int Index;
            public readonly int X;
            public readonly int Y;
            public readonly double KeyCost;
            public readonly bool KeyHasOwner;
            public readonly GridCoordinate KeyOwner;
            public readonly long Revision;
            public readonly long Sequence;

            public RepairNode(int index, int x, int y, double keyCost, bool keyHasOwner, GridCoordinate keyOwner, long revision, long sequence)
            {
                Index = index;
                X = x;
                Y = y;
                KeyCost = keyCost;
                KeyHasOwner = keyHasOwner;
                KeyOwner = keyOwner;
                Revision = revision;
                Sequence = sequence;
            }
        }

        private sealed class DeterministicRepairHeap
        {
            private RepairNode[] items;
            public int Count { get; private set; }

            public DeterministicRepairHeap(int capacity)
            {
                items = new RepairNode[Math.Max(4, capacity)];
            }

            public void Push(RepairNode item)
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

            public RepairNode Pop()
            {
                if (Count == 0) throw new InvalidOperationException("The IDFF repair heap is empty.");
                RepairNode root = items[0];
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
                RepairNode temporary = items[left];
                items[left] = items[right];
                items[right] = temporary;
            }

            private static int Compare(RepairNode left, RepairNode right)
            {
                int comparison = left.KeyCost.CompareTo(right.KeyCost);
                if (comparison != 0) return comparison;
                if (left.KeyHasOwner != right.KeyHasOwner) return left.KeyHasOwner ? -1 : 1;
                if (left.KeyHasOwner)
                {
                    comparison = CompareCoordinates(left.KeyOwner, right.KeyOwner);
                    if (comparison != 0) return comparison;
                }
                comparison = left.Y.CompareTo(right.Y);
                if (comparison != 0) return comparison;
                comparison = left.X.CompareTo(right.X);
                if (comparison != 0) return comparison;
                return left.Sequence.CompareTo(right.Sequence);
            }
        }
    }
}
