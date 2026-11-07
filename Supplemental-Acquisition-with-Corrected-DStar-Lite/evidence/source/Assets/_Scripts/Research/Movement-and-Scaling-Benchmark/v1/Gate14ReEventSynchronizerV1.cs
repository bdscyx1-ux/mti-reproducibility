using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Gate14Re.V1
{
    public interface IGate14ReVisualGridSynchronizerV1
    {
        long VisualRevision { get; }
        void Initialize(IReadOnlyNavigationGrid grid);
        void ApplyGridChange(IReadOnlyNavigationGrid grid, NavigationChangeSet changeSet);
    }

    [Serializable]
    public sealed class Gate14ReStructuralEventRecordV1
    {
        public string eventId;
        public long scheduledTick;
        public int order;
        public int changedCellCount;
        public long previousGridVersion;
        public long newGridVersion;
        public string plannerRepairStatus;
        public string plannerFailureReason;
        public long visualRevision;
    }

    /// <summary>
    /// Applies one canonical change set to the research grid, current planner, and
    /// rendered-grid sink in that order. Any version disagreement fails closed.
    /// </summary>
    public sealed class Gate14ReEventSynchronizerV1
    {
        private readonly ResolvedDeterministicScenario scenario;
        private readonly INavigationPlanner planner;
        private readonly IGate14ReVisualGridSynchronizerV1 visual;
        private int nextEventIndex;
        private long currentTick = -1L;

        public ResearchNavigationGrid Grid { get; private set; }
        public long CurrentTick { get { return currentTick; } }
        public int AppliedEventCount { get { return nextEventIndex; } }

        public Gate14ReEventSynchronizerV1(
            string runId,
            ResolvedDeterministicScenario scenario,
            INavigationPlanner planner,
            IGate14ReVisualGridSynchronizerV1 visual)
        {
            if (string.IsNullOrWhiteSpace(runId)) throw new ArgumentException("Run id is required.", "runId");
            this.scenario = scenario ?? throw new ArgumentNullException("scenario");
            this.planner = planner ?? throw new ArgumentNullException("planner");
            this.visual = visual ?? throw new ArgumentNullException("visual");

            Grid = scenario.CreateGrid();
            planner.Initialize(Grid, new NavigationPlannerInitialization
            {
                runId = runId,
                goalSetId = scenario.GoalSetId,
                goals = CopyGoals(scenario.Goals),
                connectivity = scenario.Connectivity,
                allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                budgetMilliseconds = scenario.InitializationBudgetMilliseconds
            });
            if (planner.GridVersion != Grid.Version) throw new InvalidOperationException("Planner/grid version mismatch after initialization.");
            visual.Initialize(Grid);
            if (visual.VisualRevision != Grid.Version) throw new InvalidOperationException("Visual/grid revision mismatch after initialization.");
        }

        public IReadOnlyList<Gate14ReStructuralEventRecordV1> AdvanceThrough(long targetTick)
        {
            if (targetTick <= currentTick) throw new ArgumentOutOfRangeException("targetTick", "Target tick must increase monotonically.");
            if (targetTick >= Gate14ReProtocolV1.MovementCapTicks) throw new ArgumentOutOfRangeException("targetTick", "Target tick must remain inside the 180-second movement cap.");

            List<Gate14ReStructuralEventRecordV1> records = new List<Gate14ReStructuralEventRecordV1>();
            while (nextEventIndex < scenario.ScheduledChanges.Count)
            {
                ResolvedScheduledNavigationChange scheduled = scenario.ScheduledChanges[nextEventIndex];
                if (scheduled.SimulationTick > targetTick) break;
                if (scheduled.SimulationTick < currentTick) throw new InvalidOperationException("A Gate 14Re event was skipped or applied out of order.");

                long previous = Grid.Version;
                NavigationChangeSet changeSet = Grid.ApplyChanges(scheduled.EventId, previous, scheduled.Changes);
                if (changeSet.previousGridVersion != previous || changeSet.newGridVersion != Grid.Version)
                {
                    throw new InvalidOperationException("Research grid returned an invalid version transition.");
                }

                NavigationRepairResult repair = planner.ApplyChanges(changeSet, scheduled.RepairBudgetMilliseconds);
                if (repair == null) throw new InvalidOperationException("Planner returned a null repair result.");
                if (planner.GridVersion != Grid.Version || repair.GridVersion != Grid.Version)
                {
                    throw new InvalidOperationException("Planner/grid version mismatch after " + scheduled.EventId + ".");
                }

                visual.ApplyGridChange(Grid, changeSet);
                if (visual.VisualRevision != Grid.Version)
                {
                    throw new InvalidOperationException("Visual/grid revision mismatch after " + scheduled.EventId + ".");
                }

                records.Add(new Gate14ReStructuralEventRecordV1
                {
                    eventId = scheduled.EventId,
                    scheduledTick = scheduled.SimulationTick,
                    order = scheduled.Order,
                    changedCellCount = scheduled.Changes.Count,
                    previousGridVersion = previous,
                    newGridVersion = Grid.Version,
                    plannerRepairStatus = repair.Status.ToString(),
                    plannerFailureReason = repair.FailureReason.ToString(),
                    visualRevision = visual.VisualRevision
                });
                nextEventIndex++;
            }
            currentTick = targetTick;
            return new ReadOnlyCollection<Gate14ReStructuralEventRecordV1>(records);
        }

        private static GridCoordinate[] CopyGoals(IReadOnlyList<GridCoordinate> goals)
        {
            GridCoordinate[] result = new GridCoordinate[goals.Count];
            for (int index = 0; index < result.Length; index++) result[index] = goals[index];
            return result;
        }
    }

    /// <summary>
    /// Outcome-free reference sink used by synthetic and no-render validation. It
    /// verifies that every changed cell in the visual representation equals the
    /// authoritative grid after the same change set is applied.
    /// </summary>
    public sealed class Gate14ReInMemoryVisualGridV1 : IGate14ReVisualGridSynchronizerV1
    {
        private bool[] walkable;
        private float[] costs;
        private int width;
        private int height;

        public long VisualRevision { get; private set; }

        public void Initialize(IReadOnlyNavigationGrid grid)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            width = grid.Width;
            height = grid.Height;
            walkable = new bool[checked(width * height)];
            costs = new float[walkable.Length];
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    int index = y * width + x;
                    walkable[index] = grid.IsWalkable(coordinate);
                    costs[index] = grid.GetTraversalCost(coordinate);
                }
            }
            VisualRevision = grid.Version;
        }

        public void ApplyGridChange(IReadOnlyNavigationGrid grid, NavigationChangeSet changeSet)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            if (changeSet == null) throw new ArgumentNullException("changeSet");
            if (grid.Width != width || grid.Height != height || walkable == null || costs == null) throw new InvalidOperationException("Visual grid was not initialized for this grid.");
            if (VisualRevision != changeSet.previousGridVersion) throw new InvalidOperationException("Visual revision did not match the change-set predecessor.");
            if (grid.Version != changeSet.newGridVersion) throw new InvalidOperationException("Visual sink received a stale grid snapshot.");

            for (int index = 0; index < changeSet.changes.Length; index++)
            {
                NavigationGridChange change = changeSet.changes[index];
                int cell = change.coordinate.y * width + change.coordinate.x;
                walkable[cell] = change.isWalkable;
                costs[cell] = change.traversalCost;
                if (walkable[cell] != grid.IsWalkable(change.coordinate) || Math.Abs(costs[cell] - grid.GetTraversalCost(change.coordinate)) > 1e-6f)
                {
                    throw new InvalidOperationException("Rendered walkability/cost representation disagrees with the authoritative grid.");
                }
            }
            VisualRevision = changeSet.newGridVersion;
        }
    }
}
