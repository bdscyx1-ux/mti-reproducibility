using System;
using System.Collections.Generic;

namespace DDM.Research.Navigation
{
    public static class NavigationAlgorithmIds
    {
        public const string AStarRepeated = "A*-R";
        public const string BidirectionalAStarRepeated = "BiA*-R";
        public const string LifelongPlanningAStar = "LPA*";
        public const string DStarLite = "D*L";
        public const string IncrementalDynamicFlowField = "IDFF";
        public const string CorrectedFullRecomputeFlowField = "C-FF";
    }

    public enum NavigationGridConnectivity
    {
        FourWay = 4,
        EightWay = 8
    }

    [Flags]
    public enum NavigationPlannerCapabilities
    {
        None = 0,
        PerAgentState = 1,
        SharedGoalField = 2,
        IncrementalRepair = 4,
        FullRecompute = 8
    }

    public enum NavigationPlanStatus { Succeeded, NoPath, InvalidRequest, BudgetExceeded, Cancelled, Failed }
    public enum NavigationFailureReason { None, InvalidGrid, StartOutsideGrid, GoalOutsideGrid, StartBlocked, GoalBlocked, NoReachablePath, PlanningBudgetExceeded, StaleGridVersion, InternalError, InvalidRequest }

    [Serializable]
    public struct GridCoordinate : IEquatable<GridCoordinate>
    {
        public int x;
        public int y;

        public GridCoordinate(int x, int y) { this.x = x; this.y = y; }
        public bool Equals(GridCoordinate other) { return x == other.x && y == other.y; }
        public override bool Equals(object obj) { return obj is GridCoordinate && Equals((GridCoordinate)obj); }
        public override int GetHashCode() { unchecked { return (x * 397) ^ y; } }
        public override string ToString() { return string.Format("({0}, {1})", x, y); }
    }

    public interface IReadOnlyNavigationGrid
    {
        int Width { get; }
        int Height { get; }
        long Version { get; }
        bool Contains(GridCoordinate coordinate);
        bool IsWalkable(GridCoordinate coordinate);
        float GetTraversalCost(GridCoordinate coordinate);
    }

    [Serializable]
    public sealed class NavigationPlannerInitialization
    {
        public string runId;
        public string goalSetId;
        public GridCoordinate[] goals = new GridCoordinate[0];
        public NavigationGridConnectivity connectivity = NavigationGridConnectivity.FourWay;
        public bool allowDiagonalCornerCutting;
        public double budgetMilliseconds;
    }

    [Serializable]
    public sealed class NavigationPlanRequest
    {
        public string runId;
        public string requestId;
        public string goalSetId;
        public int agentId;
        public GridCoordinate start;
        public GridCoordinate goal;
        public long expectedGridVersion;
        public double budgetMilliseconds;
    }

    [Serializable]
    public struct NavigationGridChange
    {
        public GridCoordinate coordinate;
        public bool isWalkable;
        public float traversalCost;
    }

    [Serializable]
    public sealed class NavigationChangeSet
    {
        public string changeSetId;
        public long previousGridVersion;
        public long newGridVersion;
        public NavigationGridChange[] changes = new NavigationGridChange[0];
    }

    [Serializable]
    public sealed class NavigationOperationMetrics
    {
        public double elapsedCpuMilliseconds;
        public double cumulativePlanningCpuMilliseconds;
        public long processedNodesOrCells;
        public long expandedNodes;
        public long relaxedEdges;
        public long repairedCells;
        public long managedAllocatedBytes;
        public bool budgetExceeded;
    }

    public sealed class NavigationPlanResult
    {
        public NavigationPlanStatus Status { get; private set; }
        public NavigationFailureReason FailureReason { get; private set; }
        public IReadOnlyList<GridCoordinate> Path { get; private set; }
        public long GridVersion { get; private set; }
        public NavigationOperationMetrics Metrics { get; private set; }

        public NavigationPlanResult(NavigationPlanStatus status, NavigationFailureReason failureReason, IReadOnlyList<GridCoordinate> path, long gridVersion, NavigationOperationMetrics metrics)
        {
            Status = status;
            FailureReason = failureReason;
            Path = path ?? new GridCoordinate[0];
            GridVersion = gridVersion;
            Metrics = metrics ?? new NavigationOperationMetrics();
        }
    }

    public sealed class NavigationRepairResult
    {
        public NavigationPlanStatus Status { get; private set; }
        public NavigationFailureReason FailureReason { get; private set; }
        public long GridVersion { get; private set; }
        public NavigationOperationMetrics Metrics { get; private set; }

        public NavigationRepairResult(NavigationPlanStatus status, NavigationFailureReason failureReason, long gridVersion, NavigationOperationMetrics metrics)
        {
            Status = status;
            FailureReason = failureReason;
            GridVersion = gridVersion;
            Metrics = metrics ?? new NavigationOperationMetrics();
        }
    }

    public interface INavigationPlanner
    {
        string AlgorithmId { get; }
        NavigationPlannerCapabilities Capabilities { get; }
        long GridVersion { get; }
        NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid grid, NavigationPlannerInitialization initialization);
        NavigationPlanResult Plan(NavigationPlanRequest request);
        NavigationRepairResult ApplyChanges(NavigationChangeSet changeSet, double repairBudgetMilliseconds);
        void Reset();
    }
}
