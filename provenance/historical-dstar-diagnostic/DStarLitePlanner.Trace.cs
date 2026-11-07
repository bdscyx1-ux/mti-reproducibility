using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using DDM.Research.Navigation;

namespace DDM.Research.Algorithms
{
    /// <summary>
    /// Deterministic per-agent D* Lite planner. Search state is retained across
    /// versioned grid changes; each agent owns an independent g/rhs/queue state.
    /// </summary>
    public sealed class DStarLitePlanner : INavigationPlanner
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
        private Dictionary<int, AgentSearchState> agentStates;
        private string runId;
        private string goalSetId;
        private NavigationGridConnectivity connectivity;
        private bool allowDiagonalCornerCutting;
        private bool initialized;
        private double heuristicScale;
        private double cumulativePlanningMilliseconds;

        public string AlgorithmId { get { return NavigationAlgorithmIds.DStarLite; } }
        public NavigationPlannerCapabilities Capabilities
        {
            get { return NavigationPlannerCapabilities.PerAgentState | NavigationPlannerCapabilities.IncrementalRepair; }
        }
        public long GridVersion { get; private set; }

        public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization)
        {
            if (initialized) throw new InvalidOperationException("Reset the D* Lite planner before initializing it again.");
            if (grid == null) throw new ArgumentNullException("grid");
            if (initialization == null) throw new ArgumentNullException("initialization");

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();

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

            double minimumCost = double.PositiveInfinity;
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    float cost = grid.GetTraversalCost(coordinate);
                    counters.Processed++;
                    if (!IsPositiveFinite(cost)) throw new ArgumentException("Grid contains an invalid traversal cost at " + coordinate + ".", "grid");
                    if (grid.IsWalkable(coordinate) && cost < minimumCost) minimumCost = cost;
                }
            }
            if (double.IsPositiveInfinity(minimumCost)) throw new ArgumentException("Grid has no walkable cells.", "grid");

            this.grid = grid;
            declaredGoals = goals;
            agentStates = new Dictionary<int, AgentSearchState>();
            runId = initialization.runId;
            goalSetId = initialization.goalSetId;
            connectivity = initialization.connectivity;
            allowDiagonalCornerCutting = connectivity == NavigationGridConnectivity.EightWay && initialization.allowDiagonalCornerCutting;
            heuristicScale = minimumCost;
            GridVersion = grid.Version;
            cumulativePlanningMilliseconds = 0d;
            initialized = true;

            bool budgetExceeded = IsOverBudget(stopwatch, initialization.budgetMilliseconds);
            return FinishMetrics(stopwatch, allocationBefore, counters, budgetExceeded);
        }

        public NavigationPlanResult Plan(NavigationPlanRequest request)
        {
            EnsureInitialized();
            if (request == null) throw new ArgumentNullException("request");

            Stopwatch stopwatch = Stopwatch.StartNew();
            AllocationSnapshot allocationBefore = CaptureAllocationSnapshot();
            WorkCounters counters = new WorkCounters();

            if (!IsRequestIdentityValid(request) || !IsPositiveFinite(request.budgetMilliseconds) || request.agentId < 0)
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
            if (!declaredGoals.Contains(request.goal))
            {
                return FinishPlan(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }

            AgentSearchState state;
            if (agentStates.TryGetValue(request.agentId, out state) && !state.Goal.Equals(request.goal))
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

            if (state == null)
            {
                state = CreateState(request.agentId, request.start, request.goal, ref counters);
                agentStates.Add(request.agentId, state);
            }
            else if (!state.CurrentStart.Equals(request.start))
            {
                state.Km += Heuristic(state.LastStart, request.start);
                state.LastStart = request.start;
                state.CurrentStart = request.start;
                counters.Processed++;
            }

            if (IsOverBudget(stopwatch, request.budgetMilliseconds))
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
            }

            ComputeOutcome compute = ComputeShortestPath(state, stopwatch, request.budgetMilliseconds, ref counters, false);
            if (compute == ComputeOutcome.BudgetExceeded)
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
            }
            if (compute == ComputeOutcome.InternalError)
            {
                return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }

            int startIndex = ToIndex(request.start);
            if (double.IsPositiveInfinity(state.G[startIndex]))
            {
                return FinishPlan(NavigationPlanStatus.NoPath, NavigationFailureReason.NoReachablePath, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }

            IReadOnlyList<GridCoordinate> path;
            ExtractOutcome extraction = ExtractPath(state, request.start, request.goal, stopwatch, request.budgetMilliseconds, ref counters, out path);
            if (extraction == ExtractOutcome.BudgetExceeded)
            {
                return FinishPlan(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, EmptyPath(), stopwatch, allocationBefore, counters, true);
            }
            if (extraction == ExtractOutcome.InternalError)
            {
                return FinishPlan(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, EmptyPath(), stopwatch, allocationBefore, counters, false);
            }
            return FinishPlan(NavigationPlanStatus.Succeeded, NavigationFailureReason.None, path, stopwatch, allocationBefore, counters, false);
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
                NavigationOperationMetrics invalidMetrics = FinishMetrics(stopwatch, allocationBefore, counters, false);
                return new NavigationRepairResult(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, GridVersion, invalidMetrics);
            }
            if (changeSet.previousGridVersion != GridVersion ||
                changeSet.newGridVersion != changeSet.previousGridVersion + 1L ||
                grid.Version != changeSet.newGridVersion)
            {
                counters.Processed = changeCount;
                NavigationOperationMetrics staleMetrics = FinishMetrics(stopwatch, allocationBefore, counters, false);
                return new NavigationRepairResult(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.StaleGridVersion, GridVersion, staleMetrics);
            }

            int cellCount = checked(grid.Width * grid.Height);
            bool[] affected = new bool[cellCount];
            double loweredScale = heuristicScale;
            for (int changeIndex = 0; changeIndex < changeSet.changes.Length; changeIndex++)
            {
                NavigationGridChange change = changeSet.changes[changeIndex];
                if (!grid.Contains(change.coordinate) ||
                    grid.IsWalkable(change.coordinate) != change.isWalkable ||
                    Math.Abs(grid.GetTraversalCost(change.coordinate) - change.traversalCost) > ComparisonTolerance)
                {
                    NavigationOperationMetrics invalidMetrics = FinishMetrics(stopwatch, allocationBefore, counters, false);
                    return new NavigationRepairResult(NavigationPlanStatus.InvalidRequest, NavigationFailureReason.InvalidRequest, GridVersion, invalidMetrics);
                }
                if (change.isWalkable && change.traversalCost < loweredScale) loweredScale = change.traversalCost;
                for (int deltaY = -1; deltaY <= 1; deltaY++)
                {
                    for (int deltaX = -1; deltaX <= 1; deltaX++)
                    {
                        GridCoordinate coordinate = new GridCoordinate(change.coordinate.x + deltaX, change.coordinate.y + deltaY);
                        if (grid.Contains(coordinate)) affected[ToIndex(coordinate)] = true;
                    }
                }
                counters.Processed++;
            }

            GridVersion = changeSet.newGridVersion;
            List<int> sortedAgentIds = new List<int>(agentStates.Keys);
            sortedAgentIds.Sort();
            if (loweredScale < heuristicScale - ComparisonTolerance)
            {
                heuristicScale = loweredScale;
                for (int agentIndex = 0; agentIndex < sortedAgentIds.Count; agentIndex++)
                {
                    AgentSearchState state = agentStates[sortedAgentIds[agentIndex]];
                    RebuildState(state, ref counters, true);
                }
            }
            else
            {
                for (int agentIndex = 0; agentIndex < sortedAgentIds.Count; agentIndex++)
                {
                    AgentSearchState state = agentStates[sortedAgentIds[agentIndex]];
                    for (int cellIndex = 0; cellIndex < affected.Length; cellIndex++)
                    {
                        if (affected[cellIndex]) UpdateVertex(state, cellIndex, ref counters, true);
                    }
                }
            }

            if (IsOverBudget(stopwatch, repairBudgetMilliseconds))
            {
                NavigationOperationMetrics budgetMetrics = FinishMetrics(stopwatch, allocationBefore, counters, true);
                return new NavigationRepairResult(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, GridVersion, budgetMetrics);
            }

            for (int agentIndex = 0; agentIndex < sortedAgentIds.Count; agentIndex++)
            {
                AgentSearchState state = agentStates[sortedAgentIds[agentIndex]];
                ComputeOutcome outcome = ComputeShortestPath(state, stopwatch, repairBudgetMilliseconds, ref counters, true);
                if (outcome == ComputeOutcome.BudgetExceeded)
                {
                    NavigationOperationMetrics budgetMetrics = FinishMetrics(stopwatch, allocationBefore, counters, true);
                    return new NavigationRepairResult(NavigationPlanStatus.BudgetExceeded, NavigationFailureReason.PlanningBudgetExceeded, GridVersion, budgetMetrics);
                }
                if (outcome == ComputeOutcome.InternalError)
                {
                    NavigationOperationMetrics failedMetrics = FinishMetrics(stopwatch, allocationBefore, counters, false);
                    return new NavigationRepairResult(NavigationPlanStatus.Failed, NavigationFailureReason.InternalError, GridVersion, failedMetrics);
                }
            }

            NavigationOperationMetrics metrics = FinishMetrics(stopwatch, allocationBefore, counters, false);
            return new NavigationRepairResult(NavigationPlanStatus.Succeeded, NavigationFailureReason.None, GridVersion, metrics);
        }

        public void Reset()
        {
            grid = null;
            declaredGoals = null;
            if (agentStates != null) agentStates.Clear();
            agentStates = null;
            runId = null;
            goalSetId = null;
            connectivity = NavigationGridConnectivity.FourWay;
            allowDiagonalCornerCutting = false;
            heuristicScale = 0d;
            GridVersion = 0L;
            cumulativePlanningMilliseconds = 0d;
            initialized = false;
        }

        private AgentSearchState CreateState(int agentId, GridCoordinate start, GridCoordinate goal, ref WorkCounters counters)
        {
            AgentSearchState state = new AgentSearchState(agentId, start, goal, checked(grid.Width * grid.Height));
            RebuildState(state, ref counters, false);
            return state;
        }

        private void RebuildState(AgentSearchState state, ref WorkCounters counters, bool countRepair)
        {
            state.Queue = new DeterministicKeyHeap(Math.Min(state.G.Length, 256));
            state.Sequence = 0L;
            state.Km = 0d;
            state.LastStart = state.CurrentStart;
            for (int index = 0; index < state.G.Length; index++)
            {
                state.G[index] = double.PositiveInfinity;
                state.Rhs[index] = double.PositiveInfinity;
                state.QueueRevisions[index] = 0L;
                counters.Processed++;
                if (countRepair) counters.Repaired++;
            }
            int goalIndex = ToIndex(state.Goal);
            if (grid.IsWalkable(state.Goal)) state.Rhs[goalIndex] = 0d;
            ScheduleVertex(state, goalIndex);
        }

        private ComputeOutcome ComputeShortestPath(
            AgentSearchState state,
            Stopwatch stopwatch,
            double budgetMilliseconds,
            ref WorkCounters counters,
            bool countRepair)
        {
            int startIndex = ToIndex(state.CurrentStart);
            while (true)
            {
                KeyNode top;
                bool hasTop = TryPeekValid(state, ref counters, out top);
                bool startConsistent = ValuesEqual(state.G[startIndex], state.Rhs[startIndex]);
                if (!hasTop)
                {
                    return startConsistent ? ComputeOutcome.Completed : ComputeOutcome.InternalError;
                }

                DStarKey startKey = CalculateKey(state, startIndex);
                if (CompareKeys(top.Key, startKey) >= 0 && startConsistent) {
                    bool tolerantLess = top.Key.First < startKey.First - ComparisonTolerance || (Math.Abs(top.Key.First-startKey.First)<=ComparisonTolerance && top.Key.Second < startKey.Second - ComparisonTolerance);
                    if(tolerantLess) Console.WriteLine("EARLY_STOP agent="+state.AgentId+" firstDelta="+(top.Key.First-startKey.First).ToString("R")+" secondDelta="+(top.Key.Second-startKey.Second).ToString("R")+" startConsistent="+startConsistent);
                    return ComputeOutcome.Completed;
                }
                if (IsOverBudget(stopwatch, budgetMilliseconds)) return ComputeOutcome.BudgetExceeded;

                state.Queue.Pop();
                counters.Expanded++;
                counters.Processed++;
                int vertexIndex = top.Index;
                DStarKey newKey = CalculateKey(state, vertexIndex);
                if (CompareKeys(top.Key, newKey) < 0)
                {
                    ScheduleVertex(state, vertexIndex);
                }
                else if (GreaterThan(state.G[vertexIndex], state.Rhs[vertexIndex]))
                {
                    state.G[vertexIndex] = state.Rhs[vertexIndex];
                    InvalidateVertexEntry(state, vertexIndex);
                    UpdatePredecessors(state, vertexIndex, ref counters, countRepair);
                }
                else
                {
                    state.G[vertexIndex] = double.PositiveInfinity;
                    UpdateVertex(state, vertexIndex, ref counters, countRepair);
                    UpdatePredecessors(state, vertexIndex, ref counters, countRepair);
                }
            }
        }

        private void UpdatePredecessors(AgentSearchState state, int vertexIndex, ref WorkCounters counters, bool countRepair)
        {
            GridCoordinate vertex = FromIndex(vertexIndex);
            NeighborOffset[] offsets = GetOffsets();
            for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
            {
                NeighborOffset offset = offsets[offsetIndex];
                GridCoordinate predecessor = new GridCoordinate(vertex.x + offset.X, vertex.y + offset.Y);
                if (!grid.Contains(predecessor) || !CanTraverse(predecessor, vertex)) continue;
                UpdateVertex(state, ToIndex(predecessor), ref counters, countRepair);
            }
        }

        private void UpdateVertex(AgentSearchState state, int vertexIndex, ref WorkCounters counters, bool countRepair)
        {
            GridCoordinate vertex = FromIndex(vertexIndex);
            double rhs = double.PositiveInfinity;
            if (vertex.Equals(state.Goal) && grid.IsWalkable(vertex))
            {
                rhs = 0d;
            }
            else if (grid.IsWalkable(vertex))
            {
                NeighborOffset[] offsets = GetOffsets();
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    NeighborOffset offset = offsets[offsetIndex];
                    GridCoordinate successor = new GridCoordinate(vertex.x + offset.X, vertex.y + offset.Y);
                    if (!grid.Contains(successor) || !CanTraverse(vertex, successor)) continue;
                    int successorIndex = ToIndex(successor);
                    double candidate = EdgeCost(vertex, successor) + state.G[successorIndex];
                    if (candidate < rhs - ComparisonTolerance)
                    {
                        rhs = candidate;
                        counters.Relaxed++;
                    }
                }
            }
            state.Rhs[vertexIndex] = rhs;
            counters.Processed++;
            if (countRepair) counters.Repaired++;
            ScheduleVertex(state, vertexIndex);
        }

        private ExtractOutcome ExtractPath(
            AgentSearchState state,
            GridCoordinate start,
            GridCoordinate goal,
            Stopwatch stopwatch,
            double budgetMilliseconds,
            ref WorkCounters counters,
            out IReadOnlyList<GridCoordinate> path)
        {
            List<GridCoordinate> coordinates = new List<GridCoordinate>();
            GridCoordinate current = start;
            int cellCount = checked(grid.Width * grid.Height);
            for (int step = 0; step <= cellCount; step++)
            {
                coordinates.Add(current);
                counters.Processed++;
                if (current.Equals(goal))
                {
                    path = new ReadOnlyCollection<GridCoordinate>(coordinates);
                    return ExtractOutcome.Completed;
                }
                if (IsOverBudget(stopwatch, budgetMilliseconds))
                {
                    path = EmptyPath();
                    return ExtractOutcome.BudgetExceeded;
                }

                bool found = false;
                GridCoordinate best = default(GridCoordinate);
                double bestTotal = double.PositiveInfinity;
                double bestG = double.PositiveInfinity;
                NeighborOffset[] offsets = GetOffsets();
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    NeighborOffset offset = offsets[offsetIndex];
                    GridCoordinate successor = new GridCoordinate(current.x + offset.X, current.y + offset.Y);
                    if (!grid.Contains(successor) || !CanTraverse(current, successor)) continue;
                    double successorG = state.G[ToIndex(successor)];
                    if (double.IsPositiveInfinity(successorG)) continue;
                    double total = EdgeCost(current, successor) + successorG;
                    counters.Processed++;
                    if (!found || IsBetterPathSuccessor(total, successorG, successor, bestTotal, bestG, best))
                    {
                        found = true;
                        best = successor;
                        bestTotal = total;
                        bestG = successorG;
                    }
                }
                if (!found)
                {
                    path = EmptyPath();
                    return ExtractOutcome.InternalError;
                }
                current = best;
            }
            Console.WriteLine("EXTRACTION_STEP_LIMIT agent="+state.AgentId+" start="+start+" goal="+goal+" last="+current);
            path = EmptyPath();
            return ExtractOutcome.InternalError;
        }

        private bool IsBetterPathSuccessor(
            double total,
            double successorG,
            GridCoordinate successor,
            double bestTotal,
            double bestG,
            GridCoordinate best)
        {
            if (total < bestTotal - ComparisonTolerance) return true;
            if (Math.Abs(total - bestTotal) > ComparisonTolerance) return false;
            if (successorG < bestG - ComparisonTolerance) return true;
            if (Math.Abs(successorG - bestG) > ComparisonTolerance) return false;
            int yComparison = successor.y.CompareTo(best.y);
            return yComparison < 0 || (yComparison == 0 && successor.x < best.x);
        }

        private void ScheduleVertex(AgentSearchState state, int vertexIndex)
        {
            state.QueueRevisions[vertexIndex] = checked(state.QueueRevisions[vertexIndex] + 1L);
            if (ValuesEqual(state.G[vertexIndex], state.Rhs[vertexIndex])) return;
            GridCoordinate coordinate = FromIndex(vertexIndex);
            state.Queue.Push(new KeyNode(
                vertexIndex,
                coordinate.x,
                coordinate.y,
                CalculateKey(state, vertexIndex),
                state.QueueRevisions[vertexIndex],
                state.Sequence++));
        }

        private void InvalidateVertexEntry(AgentSearchState state, int vertexIndex)
        {
            state.QueueRevisions[vertexIndex] = checked(state.QueueRevisions[vertexIndex] + 1L);
        }

        private bool TryPeekValid(AgentSearchState state, ref WorkCounters counters, out KeyNode node)
        {
            while (state.Queue.Count > 0)
            {
                KeyNode candidate = state.Queue.Peek();
                if (candidate.Revision == state.QueueRevisions[candidate.Index] &&
                    !ValuesEqual(state.G[candidate.Index], state.Rhs[candidate.Index]))
                {
                    node = candidate;
                    return true;
                }
                state.Queue.Pop();
                counters.Processed++;
            }
            node = default(KeyNode);
            return false;
        }

        private DStarKey CalculateKey(AgentSearchState state, int vertexIndex)
        {
            double minimum = Math.Min(state.G[vertexIndex], state.Rhs[vertexIndex]);
            GridCoordinate coordinate = FromIndex(vertexIndex);
            return new DStarKey(minimum + Heuristic(state.CurrentStart, coordinate) + state.Km, minimum);
        }

        private double Heuristic(GridCoordinate from, GridCoordinate to)
        {
            int deltaX = Math.Abs(to.x - from.x);
            int deltaY = Math.Abs(to.y - from.y);
            if (connectivity == NavigationGridConnectivity.FourWay) return (deltaX + deltaY) * heuristicScale;
            int minimum = Math.Min(deltaX, deltaY);
            int maximum = Math.Max(deltaX, deltaY);
            return (maximum + ((DiagonalDistance - 1d) * minimum)) * heuristicScale;
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

        private NeighborOffset[] GetOffsets()
        {
            return connectivity == NavigationGridConnectivity.FourWay ? FourWayOffsets : EightWayOffsets;
        }

        private int ToIndex(GridCoordinate coordinate)
        {
            return (coordinate.y * grid.Width) + coordinate.x;
        }

        private GridCoordinate FromIndex(int index)
        {
            return new GridCoordinate(index % grid.Width, index / grid.Width);
        }

        private NavigationPlanResult FinishPlan(
            NavigationPlanStatus status,
            NavigationFailureReason failureReason,
            IReadOnlyList<GridCoordinate> path,
            Stopwatch stopwatch,
            AllocationSnapshot allocationBefore,
            WorkCounters counters,
            bool budgetExceeded)
        {
            NavigationOperationMetrics metrics = FinishMetrics(stopwatch, allocationBefore, counters, budgetExceeded);
            return new NavigationPlanResult(status, failureReason, path, GridVersion, metrics);
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

        private bool IsRequestIdentityValid(NavigationPlanRequest request)
        {
            return !string.IsNullOrWhiteSpace(request.requestId) &&
                   string.Equals(request.runId, runId, StringComparison.Ordinal) &&
                   string.Equals(request.goalSetId, goalSetId, StringComparison.Ordinal);
        }

        private void EnsureInitialized()
        {
            if (!initialized) throw new InvalidOperationException("The D* Lite planner is not initialized.");
        }

        private static int CompareKeys(DStarKey left, DStarKey right)
        {
            int first = left.First.CompareTo(right.First);
            return first != 0 ? first : left.Second.CompareTo(right.Second);
        }

        private static bool ValuesEqual(double left, double right)
        {
            if (double.IsPositiveInfinity(left) && double.IsPositiveInfinity(right)) return true;
            return Math.Abs(left - right) <= ComparisonTolerance;
        }

        private static bool GreaterThan(double left, double right)
        {
            if (double.IsPositiveInfinity(left)) return !double.IsPositiveInfinity(right);
            if (double.IsPositiveInfinity(right)) return false;
            return left > right + ComparisonTolerance;
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

        private sealed class AgentSearchState
        {
            public readonly int AgentId;
            public readonly GridCoordinate Goal;
            public readonly double[] G;
            public readonly double[] Rhs;
            public readonly long[] QueueRevisions;
            public GridCoordinate CurrentStart;
            public GridCoordinate LastStart;
            public double Km;
            public long Sequence;
            public DeterministicKeyHeap Queue;

            public AgentSearchState(int agentId, GridCoordinate start, GridCoordinate goal, int cellCount)
            {
                AgentId = agentId;
                Goal = goal;
                CurrentStart = start;
                LastStart = start;
                G = new double[cellCount];
                Rhs = new double[cellCount];
                QueueRevisions = new long[cellCount];
            }
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

        private struct DStarKey
        {
            public readonly double First;
            public readonly double Second;

            public DStarKey(double first, double second)
            {
                First = first;
                Second = second;
            }
        }

        private struct KeyNode
        {
            public readonly int Index;
            public readonly int X;
            public readonly int Y;
            public readonly DStarKey Key;
            public readonly long Revision;
            public readonly long Sequence;

            public KeyNode(int index, int x, int y, DStarKey key, long revision, long sequence)
            {
                Index = index;
                X = x;
                Y = y;
                Key = key;
                Revision = revision;
                Sequence = sequence;
            }
        }

        private sealed class DeterministicKeyHeap
        {
            private KeyNode[] items;

            public int Count { get; private set; }

            public DeterministicKeyHeap(int capacity)
            {
                items = new KeyNode[Math.Max(4, capacity)];
            }

            public void Push(KeyNode item)
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

            public KeyNode Peek()
            {
                if (Count == 0) throw new InvalidOperationException("The D* Lite queue is empty.");
                return items[0];
            }

            public KeyNode Pop()
            {
                if (Count == 0) throw new InvalidOperationException("The D* Lite queue is empty.");
                KeyNode root = items[0];
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
                KeyNode temporary = items[left];
                items[left] = items[right];
                items[right] = temporary;
            }

            private static int Compare(KeyNode left, KeyNode right)
            {
                int comparison = CompareKeys(left.Key, right.Key);
                if (comparison != 0) return comparison;
                comparison = left.Y.CompareTo(right.Y);
                if (comparison != 0) return comparison;
                comparison = left.X.CompareTo(right.X);
                if (comparison != 0) return comparison;
                return left.Sequence.CompareTo(right.Sequence);
            }
        }

        private enum ComputeOutcome
        {
            Completed,
            BudgetExceeded,
            InternalError
        }

        private enum ExtractOutcome
        {
            Completed,
            BudgetExceeded,
            InternalError
        }
    }
}
