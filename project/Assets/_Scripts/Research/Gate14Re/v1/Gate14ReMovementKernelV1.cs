using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;

namespace DDM.Research.Gate14Re.V1
{
    public enum Gate14ReUnitTerminalStateV1
    {
        Active,
        Arrived,
        NoPath,
        BudgetExceeded,
        InvalidPlan,
        InternalFailure
    }

    public sealed class Gate14ReUnitStateV1
    {
        private readonly List<GridCoordinate> path = new List<GridCoordinate>();

        public int AgentId { get; private set; }
        public GridCoordinate Goal { get; private set; }
        public GridCoordinate CurrentCell { get; internal set; }
        public Vector3 Position { get; internal set; }
        public Gate14ReUnitTerminalStateV1 State { get; internal set; }
        public int ArrivalDwellTicks { get; internal set; }
        public double CumulativeHorizontalPathLength { get; internal set; }
        public bool DeferredReplanAfterAuthorizedOverlap { get; internal set; }
        public int PathIndex { get; internal set; }
        public IReadOnlyList<GridCoordinate> Path { get { return path.AsReadOnly(); } }

        internal Gate14ReUnitStateV1(int agentId, GridCoordinate start, GridCoordinate goal, Vector3 position)
        {
            AgentId = agentId;
            CurrentCell = start;
            Goal = goal;
            Position = position;
            State = Gate14ReUnitTerminalStateV1.Active;
        }

        internal void ReplacePath(IReadOnlyList<GridCoordinate> source)
        {
            path.Clear();
            for (int index = 0; index < source.Count; index++) path.Add(source[index]);
            PathIndex = path.Count > 1 ? 1 : path.Count;
        }
    }

    /// <summary>
    /// Shared deterministic movement adapter used identically for all four planners.
    /// The 20 world-unit/second speed is the existing production unit speed in both
    /// legacy NavMesh PlayerUnit and the FlowField production prefab.  Planning is
    /// performed at release and after each authorized grid event, never per algorithm
    /// using a different movement controller.
    /// </summary>
    public sealed class Gate14ReMovementKernelV1
    {
        public const float SharedSpeedWorldUnitsPerSecond = 20f;
        public const int ArrivalDwellTicksRequired = 10;
        public const float ArrivalRadiusCellMultiplier = 0.75f;

        private readonly string runId;
        private readonly ResolvedDeterministicScenario scenario;
        private readonly INavigationPlanner planner;
        private readonly Gate14ReEventSynchronizerV1 synchronizer;
        private readonly ResearchGridWorldTransform world;
        private readonly List<Gate14ReUnitStateV1> units = new List<Gate14ReUnitStateV1>();
        private readonly List<Gate14ReStructuralEventRecordV1> eventRecords = new List<Gate14ReStructuralEventRecordV1>();
        private bool released;

        public IReadOnlyList<Gate14ReUnitStateV1> Units { get { return new ReadOnlyCollection<Gate14ReUnitStateV1>(units); } }
        public IReadOnlyList<Gate14ReStructuralEventRecordV1> StructuralEventRecords { get { return new ReadOnlyCollection<Gate14ReStructuralEventRecordV1>(eventRecords); } }
        public long CurrentTick { get { return synchronizer.CurrentTick; } }
        public long GridVersion { get { return synchronizer.Grid.Version; } }
        public long PlannerGridVersion { get { return planner.GridVersion; } }
        public bool Released { get { return released; } }

        public Gate14ReMovementKernelV1(
            string runId,
            ResolvedDeterministicScenario scenario,
            INavigationPlanner planner,
            IGate14ReVisualGridSynchronizerV1 visual)
        {
            if (string.IsNullOrWhiteSpace(runId)) throw new ArgumentException("Run id is required.", "runId");
            this.runId = runId;
            this.scenario = scenario ?? throw new ArgumentNullException("scenario");
            this.planner = planner ?? throw new ArgumentNullException("planner");
            if (Math.Abs(scenario.FixedStepSeconds - Gate14ReProtocolV1.FixedStepSeconds) > 1e-12d) throw new InvalidOperationException("Movement kernel requires the frozen 0.02-second fixed step.");
            if (scenario.Goals.Count != 1) throw new InvalidOperationException("Movement kernel requires one shared goal.");

            synchronizer = new Gate14ReEventSynchronizerV1(runId, scenario, planner, visual);
            world = scenario.CreateWorldTransform();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                Vector3 position = world.GridToWorldCenter(agent.Start, scenario.GridWidth, scenario.GridHeight);
                units.Add(new Gate14ReUnitStateV1(agent.AgentId, agent.Start, agent.Goal, position));
            }
        }

        public void Release()
        {
            if (released) throw new InvalidOperationException("Movement kernel has already been released.");
            released = true;
            for (int index = 0; index < units.Count; index++) PlanUnit(units[index], "initial");
        }

        public void AdvanceOneFixedTick()
        {
            if (!released) throw new InvalidOperationException("Movement kernel has not been released.");
            long targetTick = synchronizer.CurrentTick + 1L;
            if (targetTick >= Gate14ReProtocolV1.MovementCapTicks) throw new InvalidOperationException("Movement kernel reached the frozen 180-second cap.");

            IReadOnlyList<Gate14ReStructuralEventRecordV1> applied = synchronizer.AdvanceThrough(targetTick);
            if (applied.Count > 0)
            {
                for (int recordIndex = 0; recordIndex < applied.Count; recordIndex++) eventRecords.Add(applied[recordIndex]);
                for (int unitIndex = 0; unitIndex < units.Count; unitIndex++) PrepareUnitAfterEvent(units[unitIndex]);
            }

            float stepDistance = SharedSpeedWorldUnitsPerSecond * (float)scenario.FixedStepSeconds;
            for (int unitIndex = 0; unitIndex < units.Count; unitIndex++)
            {
                Gate14ReUnitStateV1 unit = units[unitIndex];
                if (unit.State == Gate14ReUnitTerminalStateV1.Active) MoveUnit(unit, stepDistance);
                UpdateArrival(unit);
                ValidateFiniteAndContained(unit);
            }
        }

        private void PrepareUnitAfterEvent(Gate14ReUnitStateV1 unit)
        {
            if (unit.State != Gate14ReUnitTerminalStateV1.Active) return;
            if (synchronizer.Grid.IsWalkable(unit.CurrentCell))
            {
                unit.DeferredReplanAfterAuthorizedOverlap = false;
                PlanUnit(unit, "event-" + synchronizer.AppliedEventCount);
                return;
            }

            // A newly blocked occupied cell is the one explicitly authorized transient
            // overlap. The unit may only finish its already-selected single egress edge;
            // it replans immediately on the first walkable cell.
            unit.DeferredReplanAfterAuthorizedOverlap = true;
            if (unit.PathIndex >= unit.Path.Count || !IsLegalTransition(unit.CurrentCell, unit.Path[unit.PathIndex], true))
            {
                unit.State = Gate14ReUnitTerminalStateV1.NoPath;
            }
        }

        private void MoveUnit(Gate14ReUnitStateV1 unit, float distanceBudget)
        {
            float remaining = distanceBudget;
            int guard = 0;
            while (remaining > 1e-6f && unit.State == Gate14ReUnitTerminalStateV1.Active && guard++ < 32)
            {
                if (unit.PathIndex >= unit.Path.Count) break;
                GridCoordinate nextCell = unit.Path[unit.PathIndex];
                bool authorizedBlockedStart = unit.DeferredReplanAfterAuthorizedOverlap && !synchronizer.Grid.IsWalkable(unit.CurrentCell);
                if (!IsLegalTransition(unit.CurrentCell, nextCell, authorizedBlockedStart))
                {
                    unit.State = Gate14ReUnitTerminalStateV1.InvalidPlan;
                    return;
                }

                Vector3 target = world.GridToWorldCenter(nextCell, scenario.GridWidth, scenario.GridHeight);
                Vector3 delta = target - unit.Position;
                delta.y = 0f;
                float distance = delta.magnitude;
                if (distance <= 1e-6f)
                {
                    unit.Position = target;
                    unit.CurrentCell = nextCell;
                    unit.PathIndex++;
                    if (unit.DeferredReplanAfterAuthorizedOverlap)
                    {
                        unit.DeferredReplanAfterAuthorizedOverlap = false;
                        PlanUnit(unit, "post-overlap-egress");
                    }
                    continue;
                }

                float movement = Math.Min(remaining, distance);
                Vector3 previous = unit.Position;
                unit.Position += delta / distance * movement;
                unit.CumulativeHorizontalPathLength += HorizontalDistance(previous, unit.Position);
                remaining -= movement;
                if (movement + 1e-6f >= distance)
                {
                    unit.Position = target;
                    unit.CurrentCell = nextCell;
                    unit.PathIndex++;
                    if (unit.DeferredReplanAfterAuthorizedOverlap)
                    {
                        unit.DeferredReplanAfterAuthorizedOverlap = false;
                        PlanUnit(unit, "post-overlap-egress");
                    }
                }
            }
            if (guard >= 32) throw new InvalidOperationException("Movement waypoint guard exceeded.");
        }

        private void PlanUnit(Gate14ReUnitStateV1 unit, string phase)
        {
            if (unit.State != Gate14ReUnitTerminalStateV1.Active) return;
            if (!synchronizer.Grid.IsWalkable(unit.CurrentCell))
            {
                unit.State = Gate14ReUnitTerminalStateV1.NoPath;
                return;
            }

            NavigationPlanResult result;
            try
            {
                result = planner.Plan(new NavigationPlanRequest
                {
                    runId = runId,
                    requestId = runId + "-agent-" + unit.AgentId + "-" + phase + "-tick-" + Math.Max(0L, synchronizer.CurrentTick),
                    goalSetId = scenario.GoalSetId,
                    agentId = unit.AgentId,
                    start = unit.CurrentCell,
                    goal = unit.Goal,
                    expectedGridVersion = synchronizer.Grid.Version,
                    budgetMilliseconds = scenario.DefaultPlanBudgetMilliseconds
                });
            }
            catch
            {
                unit.State = Gate14ReUnitTerminalStateV1.InternalFailure;
                return;
            }

            if (result == null || result.GridVersion != synchronizer.Grid.Version || planner.GridVersion != synchronizer.Grid.Version)
            {
                unit.State = Gate14ReUnitTerminalStateV1.InternalFailure;
                return;
            }
            if (result.Status == NavigationPlanStatus.BudgetExceeded || result.FailureReason == NavigationFailureReason.PlanningBudgetExceeded)
            {
                unit.State = Gate14ReUnitTerminalStateV1.BudgetExceeded;
                return;
            }
            if (result.Status == NavigationPlanStatus.NoPath || result.FailureReason == NavigationFailureReason.NoReachablePath)
            {
                unit.State = Gate14ReUnitTerminalStateV1.NoPath;
                return;
            }
            if (result.Status != NavigationPlanStatus.Succeeded)
            {
                unit.State = Gate14ReUnitTerminalStateV1.InvalidPlan;
                return;
            }
            if (!ValidatePath(result.Path, unit.CurrentCell, unit.Goal))
            {
                unit.State = Gate14ReUnitTerminalStateV1.InvalidPlan;
                return;
            }
            unit.ReplacePath(result.Path);
        }

        private bool ValidatePath(IReadOnlyList<GridCoordinate> path, GridCoordinate start, GridCoordinate goal)
        {
            if (path == null || path.Count == 0 || !path[0].Equals(start) || !path[path.Count - 1].Equals(goal)) return false;
            for (int index = 0; index < path.Count; index++)
            {
                if (!synchronizer.Grid.Contains(path[index]) || !synchronizer.Grid.IsWalkable(path[index])) return false;
                if (index > 0 && !IsLegalTransition(path[index - 1], path[index], false)) return false;
            }
            return true;
        }

        private bool IsLegalTransition(GridCoordinate from, GridCoordinate to, bool allowBlockedFrom)
        {
            if (!synchronizer.Grid.Contains(from) || !synchronizer.Grid.Contains(to) || !synchronizer.Grid.IsWalkable(to)) return false;
            if (!allowBlockedFrom && !synchronizer.Grid.IsWalkable(from)) return false;
            int dx = Math.Abs(to.x - from.x);
            int dy = Math.Abs(to.y - from.y);
            if (dx == 0 && dy == 0) return true;
            if (dx > 1 || dy > 1) return false;
            if (scenario.Connectivity == NavigationGridConnectivity.FourWay && dx + dy != 1) return false;
            if (dx == 1 && dy == 1 && !scenario.AllowDiagonalCornerCutting)
            {
                GridCoordinate sideA = new GridCoordinate(from.x + (to.x - from.x), from.y);
                GridCoordinate sideB = new GridCoordinate(from.x, from.y + (to.y - from.y));
                if (!synchronizer.Grid.IsWalkable(sideA) || !synchronizer.Grid.IsWalkable(sideB)) return false;
            }
            return true;
        }

        private void UpdateArrival(Gate14ReUnitStateV1 unit)
        {
            if (unit.State != Gate14ReUnitTerminalStateV1.Active) return;
            Vector3 goal = world.GridToWorldCenter(unit.Goal, scenario.GridWidth, scenario.GridHeight);
            bool within = unit.CurrentCell.Equals(unit.Goal) && HorizontalDistance(unit.Position, goal) <= ArrivalRadiusCellMultiplier * scenario.CellSize;
            unit.ArrivalDwellTicks = within ? unit.ArrivalDwellTicks + 1 : 0;
            if (unit.ArrivalDwellTicks >= ArrivalDwellTicksRequired) unit.State = Gate14ReUnitTerminalStateV1.Arrived;
        }

        private void ValidateFiniteAndContained(Gate14ReUnitStateV1 unit)
        {
            Vector3 position = unit.Position;
            if (float.IsNaN(position.x) || float.IsNaN(position.y) || float.IsNaN(position.z) || float.IsInfinity(position.x) || float.IsInfinity(position.y) || float.IsInfinity(position.z))
            {
                unit.State = Gate14ReUnitTerminalStateV1.InternalFailure;
                return;
            }
            GridCoordinate coordinate;
            if (!world.TryWorldToGrid(position, scenario.GridWidth, scenario.GridHeight, out coordinate))
            {
                unit.State = Gate14ReUnitTerminalStateV1.InternalFailure;
            }
        }

        private static double HorizontalDistance(Vector3 left, Vector3 right)
        {
            double dx = (double)left.x - right.x;
            double dz = (double)left.z - right.z;
            return Math.Sqrt(dx * dx + dz * dz);
        }
    }
}
