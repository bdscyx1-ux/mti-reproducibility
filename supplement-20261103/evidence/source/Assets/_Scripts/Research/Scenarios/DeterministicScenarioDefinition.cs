using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Scenarios
{
    [Serializable]
    public sealed class ScenarioAgentDefinition
    {
        public int agentId;
        public GridCoordinate start;
        public GridCoordinate goal;
    }

    [Serializable]
    public sealed class ScheduledNavigationChangeDefinition
    {
        public string eventId;
        public long simulationTick;
        public int order;
        public double repairBudgetMilliseconds;
        public NavigationGridChange[] changes = new NavigationGridChange[0];
    }

    public enum ScenarioValidationSeverity
    {
        Warning,
        Error
    }

    public sealed class ScenarioValidationIssue
    {
        public ScenarioValidationSeverity Severity { get; private set; }
        public string Code { get; private set; }
        public string Path { get; private set; }
        public string Message { get; private set; }

        public ScenarioValidationIssue(ScenarioValidationSeverity severity, string code, string path, string message)
        {
            Severity = severity;
            Code = code ?? string.Empty;
            Path = path ?? string.Empty;
            Message = message ?? string.Empty;
        }

        public override string ToString()
        {
            return string.Format("{0} {1} at {2}: {3}", Severity, Code, Path, Message);
        }
    }

    public sealed class ScenarioValidationResult
    {
        private readonly List<ScenarioValidationIssue> issues = new List<ScenarioValidationIssue>();

        public IReadOnlyList<ScenarioValidationIssue> Issues { get { return issues.AsReadOnly(); } }
        public bool HasErrors
        {
            get
            {
                for (int index = 0; index < issues.Count; index++)
                {
                    if (issues[index].Severity == ScenarioValidationSeverity.Error) return true;
                }
                return false;
            }
        }

        internal void AddError(string code, string path, string message)
        {
            issues.Add(new ScenarioValidationIssue(ScenarioValidationSeverity.Error, code, path, message));
        }

        internal void AddWarning(string code, string path, string message)
        {
            issues.Add(new ScenarioValidationIssue(ScenarioValidationSeverity.Warning, code, path, message));
        }
    }

    public sealed class ScenarioValidationException : Exception
    {
        public ScenarioValidationResult ValidationResult { get; private set; }

        public ScenarioValidationException(ScenarioValidationResult validationResult)
            : base(BuildMessage(validationResult))
        {
            ValidationResult = validationResult;
        }

        private static string BuildMessage(ScenarioValidationResult result)
        {
            if (result == null) return "Scenario validation failed.";
            StringBuilder builder = new StringBuilder("Scenario validation failed:");
            for (int index = 0; index < result.Issues.Count; index++)
            {
                ScenarioValidationIssue issue = result.Issues[index];
                if (issue.Severity == ScenarioValidationSeverity.Error)
                {
                    builder.Append(Environment.NewLine).Append("- ").Append(issue);
                }
            }
            return builder.ToString();
        }
    }

    /// <summary>
    /// Serializable experiment input. Dynamic events are scheduled by integer tick,
    /// never by wall-clock time, and Resolve returns a canonical immutable snapshot.
    /// </summary>
    [Serializable]
    public sealed class DeterministicScenarioDefinition
    {
        public const int CurrentSchemaVersion = 1;

        public int schemaVersion = CurrentSchemaVersion;
        public string scenarioId;
        public int randomSeed;
        public int gridWidth;
        public int gridHeight;
        public float defaultTraversalCost = 1f;
        public Vector3 worldOrigin = Vector3.zero;
        public float cellSize = 1f;
        public NavigationGridConnectivity connectivity = NavigationGridConnectivity.FourWay;
        public bool allowDiagonalCornerCutting;
        public double fixedStepSeconds = 0.02d;
        public long maxSimulationTicks = 3000;
        public string goalSetId = "primary";
        public double initializationBudgetMilliseconds = 1000d;
        public double defaultPlanBudgetMilliseconds = 16.6667d;
        public double defaultRepairBudgetMilliseconds = 16.6667d;
        public ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[0];
        public NavigationGridChange[] initialGridOverrides = new NavigationGridChange[0];
        public ScheduledNavigationChangeDefinition[] scheduledChanges = new ScheduledNavigationChangeDefinition[0];

        public ScenarioValidationResult Validate()
        {
            ScenarioValidationResult result = new ScenarioValidationResult();

            if (schemaVersion != CurrentSchemaVersion)
            {
                result.AddError("unsupported_schema", "schemaVersion", "Expected schema version " + CurrentSchemaVersion + ".");
            }
            if (string.IsNullOrWhiteSpace(scenarioId)) result.AddError("required", "scenarioId", "Scenario id is required.");
            if (gridWidth <= 0) result.AddError("invalid_dimension", "gridWidth", "Grid width must be greater than zero.");
            if (gridHeight <= 0) result.AddError("invalid_dimension", "gridHeight", "Grid height must be greater than zero.");
            if (!IsPositiveFinite(defaultTraversalCost)) result.AddError("invalid_cost", "defaultTraversalCost", "Default traversal cost must be finite and greater than zero.");
            if (!IsFinite(worldOrigin.x) || !IsFinite(worldOrigin.y) || !IsFinite(worldOrigin.z)) result.AddError("invalid_origin", "worldOrigin", "World origin components must be finite.");
            if (!IsPositiveFinite(cellSize)) result.AddError("invalid_cell_size", "cellSize", "Cell size must be finite and greater than zero.");
            if (!Enum.IsDefined(typeof(NavigationGridConnectivity), connectivity)) result.AddError("invalid_connectivity", "connectivity", "Connectivity value is not supported.");
            if (connectivity == NavigationGridConnectivity.FourWay && allowDiagonalCornerCutting)
            {
                result.AddWarning("unused_option", "allowDiagonalCornerCutting", "Corner cutting has no effect for four-way connectivity.");
            }
            if (!IsPositiveFinite(fixedStepSeconds)) result.AddError("invalid_fixed_step", "fixedStepSeconds", "Fixed step must be finite and greater than zero.");
            if (maxSimulationTicks <= 0) result.AddError("invalid_duration", "maxSimulationTicks", "Maximum simulation ticks must be greater than zero.");
            if (string.IsNullOrWhiteSpace(goalSetId)) result.AddError("required", "goalSetId", "Goal-set id is required.");
            if (!IsPositiveFinite(initializationBudgetMilliseconds)) result.AddError("invalid_budget", "initializationBudgetMilliseconds", "Initialization budget must be finite and greater than zero.");
            if (!IsPositiveFinite(defaultPlanBudgetMilliseconds)) result.AddError("invalid_budget", "defaultPlanBudgetMilliseconds", "Plan budget must be finite and greater than zero.");
            if (!IsPositiveFinite(defaultRepairBudgetMilliseconds)) result.AddError("invalid_budget", "defaultRepairBudgetMilliseconds", "Repair budget must be finite and greater than zero.");

            ValidateInitialGrid(result);
            ValidateAgents(result);
            ValidateScheduledChanges(result);
            ValidateAgentCellsRemainInitiallyWalkable(result);
            return result;
        }

        public ResolvedDeterministicScenario Resolve()
        {
            ScenarioValidationResult validation = Validate();
            if (validation.HasErrors) throw new ScenarioValidationException(validation);
            return new ResolvedDeterministicScenario(this, validation);
        }

        private void ValidateInitialGrid(ScenarioValidationResult result)
        {
            NavigationGridChange[] overrides = initialGridOverrides ?? new NavigationGridChange[0];
            HashSet<GridCoordinate> seen = new HashSet<GridCoordinate>();
            for (int index = 0; index < overrides.Length; index++)
            {
                string path = "initialGridOverrides[" + index + "]";
                NavigationGridChange change = overrides[index];
                if (!Contains(change.coordinate)) result.AddError("outside_grid", path + ".coordinate", "Coordinate is outside the grid: " + change.coordinate);
                if (!IsPositiveFinite(change.traversalCost)) result.AddError("invalid_cost", path + ".traversalCost", "Traversal cost must be finite and greater than zero.");
                if (!seen.Add(change.coordinate)) result.AddError("duplicate_coordinate", path + ".coordinate", "Initial overrides contain a duplicate coordinate: " + change.coordinate);
            }
        }

        private void ValidateAgents(ScenarioValidationResult result)
        {
            ScenarioAgentDefinition[] scenarioAgents = agents ?? new ScenarioAgentDefinition[0];
            if (scenarioAgents.Length == 0) result.AddError("required", "agents", "At least one agent is required.");

            HashSet<int> agentIds = new HashSet<int>();
            for (int index = 0; index < scenarioAgents.Length; index++)
            {
                string path = "agents[" + index + "]";
                ScenarioAgentDefinition agent = scenarioAgents[index];
                if (agent == null)
                {
                    result.AddError("null_entry", path, "Agent definition cannot be null.");
                    continue;
                }
                if (agent.agentId < 0) result.AddError("invalid_agent_id", path + ".agentId", "Agent id must be non-negative.");
                if (!agentIds.Add(agent.agentId)) result.AddError("duplicate_agent_id", path + ".agentId", "Agent id must be unique: " + agent.agentId);
                if (!Contains(agent.start)) result.AddError("outside_grid", path + ".start", "Start is outside the grid: " + agent.start);
                if (!Contains(agent.goal)) result.AddError("outside_grid", path + ".goal", "Goal is outside the grid: " + agent.goal);
            }
        }

        private void ValidateScheduledChanges(ScenarioValidationResult result)
        {
            ScheduledNavigationChangeDefinition[] events = scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            HashSet<string> eventIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> tickOrders = new HashSet<string>(StringComparer.Ordinal);

            for (int eventIndex = 0; eventIndex < events.Length; eventIndex++)
            {
                string path = "scheduledChanges[" + eventIndex + "]";
                ScheduledNavigationChangeDefinition scheduled = events[eventIndex];
                if (scheduled == null)
                {
                    result.AddError("null_entry", path, "Scheduled change cannot be null.");
                    continue;
                }

                string normalizedEventId = scheduled.eventId == null ? null : scheduled.eventId.Trim();
                if (string.IsNullOrWhiteSpace(normalizedEventId)) result.AddError("required", path + ".eventId", "Event id is required.");
                else if (!eventIds.Add(normalizedEventId)) result.AddError("duplicate_event_id", path + ".eventId", "Event id must be unique after trimming: " + normalizedEventId);

                if (scheduled.simulationTick < 0 || scheduled.simulationTick >= maxSimulationTicks)
                {
                    result.AddError("invalid_tick", path + ".simulationTick", "Event tick must be within [0, maxSimulationTicks)." );
                }
                if (scheduled.order < 0) result.AddError("invalid_order", path + ".order", "Event order must be non-negative.");

                string tickOrderKey = scheduled.simulationTick.ToString(CultureInfo.InvariantCulture) + ":" + scheduled.order.ToString(CultureInfo.InvariantCulture);
                if (!tickOrders.Add(tickOrderKey)) result.AddError("duplicate_tick_order", path + ".order", "Events at the same tick must have unique order values.");

                if (!IsNonNegativeFinite(scheduled.repairBudgetMilliseconds)) result.AddError("invalid_budget", path + ".repairBudgetMilliseconds", "Event repair budget must be zero (inherit) or a finite positive value.");

                NavigationGridChange[] changes = scheduled.changes ?? new NavigationGridChange[0];
                if (changes.Length == 0) result.AddError("required", path + ".changes", "Scheduled event must contain at least one grid change.");
                HashSet<GridCoordinate> coordinates = new HashSet<GridCoordinate>();
                for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++)
                {
                    string changePath = path + ".changes[" + changeIndex + "]";
                    NavigationGridChange change = changes[changeIndex];
                    if (!Contains(change.coordinate)) result.AddError("outside_grid", changePath + ".coordinate", "Coordinate is outside the grid: " + change.coordinate);
                    if (!IsPositiveFinite(change.traversalCost)) result.AddError("invalid_cost", changePath + ".traversalCost", "Traversal cost must be finite and greater than zero.");
                    if (!coordinates.Add(change.coordinate)) result.AddError("duplicate_coordinate", changePath + ".coordinate", "Event contains a duplicate coordinate: " + change.coordinate);
                }
            }
        }

        private void ValidateAgentCellsRemainInitiallyWalkable(ScenarioValidationResult result)
        {
            Dictionary<GridCoordinate, bool> walkability = new Dictionary<GridCoordinate, bool>();
            NavigationGridChange[] overrides = initialGridOverrides ?? new NavigationGridChange[0];
            for (int index = 0; index < overrides.Length; index++) walkability[overrides[index].coordinate] = overrides[index].isWalkable;

            ScenarioAgentDefinition[] scenarioAgents = agents ?? new ScenarioAgentDefinition[0];
            for (int index = 0; index < scenarioAgents.Length; index++)
            {
                ScenarioAgentDefinition agent = scenarioAgents[index];
                if (agent == null) continue;
                bool isWalkable;
                if (walkability.TryGetValue(agent.start, out isWalkable) && !isWalkable)
                {
                    result.AddError("blocked_start", "agents[" + index + "].start", "Agent start is blocked by the initial grid state.");
                }
                if (walkability.TryGetValue(agent.goal, out isWalkable) && !isWalkable)
                {
                    result.AddError("blocked_goal", "agents[" + index + "].goal", "Agent goal is blocked by the initial grid state.");
                }
            }
        }

        private bool Contains(GridCoordinate coordinate)
        {
            return coordinate.x >= 0 && coordinate.x < gridWidth && coordinate.y >= 0 && coordinate.y < gridHeight;
        }

        private static bool IsFinite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }
        private static bool IsPositiveFinite(float value) { return IsFinite(value) && value > 0f; }
        private static bool IsPositiveFinite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value) && value > 0d; }
        private static bool IsNonNegativeFinite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value) && value >= 0d; }
    }

    public sealed class ResolvedScenarioAgent
    {
        public int AgentId { get; private set; }
        public GridCoordinate Start { get; private set; }
        public GridCoordinate Goal { get; private set; }

        internal ResolvedScenarioAgent(int agentId, GridCoordinate start, GridCoordinate goal)
        {
            AgentId = agentId;
            Start = start;
            Goal = goal;
        }
    }

    public sealed class ResolvedScheduledNavigationChange
    {
        public string EventId { get; private set; }
        public long SimulationTick { get; private set; }
        public int Order { get; private set; }
        public double RepairBudgetMilliseconds { get; private set; }
        public IReadOnlyList<NavigationGridChange> Changes { get; private set; }

        internal ResolvedScheduledNavigationChange(string eventId, long simulationTick, int order, double repairBudgetMilliseconds, NavigationGridChange[] changes)
        {
            EventId = eventId;
            SimulationTick = simulationTick;
            Order = order;
            RepairBudgetMilliseconds = repairBudgetMilliseconds;
            Changes = Array.AsReadOnly(changes);
        }
    }

    /// <summary>Canonical, immutable scenario snapshot shared by every algorithm run.</summary>
    public sealed class ResolvedDeterministicScenario
    {
        private readonly Dictionary<int, ResolvedScenarioAgent> agentsById;

        public int SchemaVersion { get; private set; }
        public string ScenarioId { get; private set; }
        public int RandomSeed { get; private set; }
        public int GridWidth { get; private set; }
        public int GridHeight { get; private set; }
        public float DefaultTraversalCost { get; private set; }
        public Vector3 WorldOrigin { get; private set; }
        public float CellSize { get; private set; }
        public NavigationGridConnectivity Connectivity { get; private set; }
        public bool AllowDiagonalCornerCutting { get; private set; }
        public double FixedStepSeconds { get; private set; }
        public long MaxSimulationTicks { get; private set; }
        public string GoalSetId { get; private set; }
        public double InitializationBudgetMilliseconds { get; private set; }
        public double DefaultPlanBudgetMilliseconds { get; private set; }
        public double DefaultRepairBudgetMilliseconds { get; private set; }
        public IReadOnlyList<ResolvedScenarioAgent> Agents { get; private set; }
        public IReadOnlyList<GridCoordinate> Goals { get; private set; }
        public IReadOnlyList<NavigationGridChange> InitialGridOverrides { get; private set; }
        public IReadOnlyList<ResolvedScheduledNavigationChange> ScheduledChanges { get; private set; }
        public IReadOnlyList<ScenarioValidationIssue> ValidationIssues { get; private set; }
        public string FingerprintSha256 { get; private set; }

        internal ResolvedDeterministicScenario(DeterministicScenarioDefinition source, ScenarioValidationResult validation)
        {
            SchemaVersion = source.schemaVersion;
            ScenarioId = source.scenarioId.Trim();
            RandomSeed = source.randomSeed;
            GridWidth = source.gridWidth;
            GridHeight = source.gridHeight;
            DefaultTraversalCost = source.defaultTraversalCost;
            WorldOrigin = source.worldOrigin;
            CellSize = source.cellSize;
            Connectivity = source.connectivity;
            AllowDiagonalCornerCutting = source.allowDiagonalCornerCutting;
            FixedStepSeconds = source.fixedStepSeconds;
            MaxSimulationTicks = source.maxSimulationTicks;
            GoalSetId = source.goalSetId.Trim();
            InitializationBudgetMilliseconds = source.initializationBudgetMilliseconds;
            DefaultPlanBudgetMilliseconds = source.defaultPlanBudgetMilliseconds;
            DefaultRepairBudgetMilliseconds = source.defaultRepairBudgetMilliseconds;

            ScenarioAgentDefinition[] sourceAgents = source.agents ?? new ScenarioAgentDefinition[0];
            List<ResolvedScenarioAgent> resolvedAgents = new List<ResolvedScenarioAgent>();
            for (int index = 0; index < sourceAgents.Length; index++)
            {
                ScenarioAgentDefinition agent = sourceAgents[index];
                resolvedAgents.Add(new ResolvedScenarioAgent(agent.agentId, agent.start, agent.goal));
            }
            resolvedAgents.Sort(delegate(ResolvedScenarioAgent left, ResolvedScenarioAgent right) { return left.AgentId.CompareTo(right.AgentId); });
            Agents = new ReadOnlyCollection<ResolvedScenarioAgent>(resolvedAgents);
            agentsById = new Dictionary<int, ResolvedScenarioAgent>();
            for (int index = 0; index < resolvedAgents.Count; index++) agentsById.Add(resolvedAgents[index].AgentId, resolvedAgents[index]);

            List<GridCoordinate> goals = new List<GridCoordinate>();
            HashSet<GridCoordinate> seenGoals = new HashSet<GridCoordinate>();
            for (int index = 0; index < resolvedAgents.Count; index++)
            {
                GridCoordinate goal = resolvedAgents[index].Goal;
                if (seenGoals.Add(goal)) goals.Add(goal);
            }
            goals.Sort(CompareCoordinates);
            Goals = new ReadOnlyCollection<GridCoordinate>(goals);

            NavigationGridChange[] sourceInitial = source.initialGridOverrides ?? new NavigationGridChange[0];
            NavigationGridChange[] initial = (NavigationGridChange[])sourceInitial.Clone();
            Array.Sort(initial, CompareChanges);
            InitialGridOverrides = Array.AsReadOnly(initial);

            ScheduledNavigationChangeDefinition[] sourceScheduled = source.scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            List<ResolvedScheduledNavigationChange> scheduled = new List<ResolvedScheduledNavigationChange>();
            for (int index = 0; index < sourceScheduled.Length; index++)
            {
                ScheduledNavigationChangeDefinition item = sourceScheduled[index];
                NavigationGridChange[] changes = (NavigationGridChange[])item.changes.Clone();
                Array.Sort(changes, CompareChanges);
                double budget = item.repairBudgetMilliseconds > 0d ? item.repairBudgetMilliseconds : DefaultRepairBudgetMilliseconds;
                scheduled.Add(new ResolvedScheduledNavigationChange(item.eventId.Trim(), item.simulationTick, item.order, budget, changes));
            }
            scheduled.Sort(CompareScheduledChanges);
            ScheduledChanges = new ReadOnlyCollection<ResolvedScheduledNavigationChange>(scheduled);
            ValidationIssues = validation.Issues;
            FingerprintSha256 = ComputeFingerprint(this);
        }

        public ResolvedScenarioAgent GetAgent(int agentId)
        {
            ResolvedScenarioAgent agent;
            if (!agentsById.TryGetValue(agentId, out agent)) throw new KeyNotFoundException("Scenario does not define agent " + agentId + ".");
            return agent;
        }

        public ResearchNavigationGrid CreateGrid()
        {
            return new ResearchNavigationGrid(GridWidth, GridHeight, DefaultTraversalCost, InitialGridOverrides);
        }

        public ResearchGridWorldTransform CreateWorldTransform()
        {
            return new ResearchGridWorldTransform(WorldOrigin, CellSize);
        }

        private static string ComputeFingerprint(ResolvedDeterministicScenario scenario)
        {
            StringBuilder canonical = new StringBuilder(2048);
            Append(canonical, scenario.SchemaVersion);
            Append(canonical, scenario.ScenarioId);
            Append(canonical, scenario.RandomSeed);
            Append(canonical, scenario.GridWidth);
            Append(canonical, scenario.GridHeight);
            Append(canonical, scenario.DefaultTraversalCost);
            Append(canonical, scenario.WorldOrigin.x);
            Append(canonical, scenario.WorldOrigin.y);
            Append(canonical, scenario.WorldOrigin.z);
            Append(canonical, scenario.CellSize);
            Append(canonical, (int)scenario.Connectivity);
            Append(canonical, scenario.AllowDiagonalCornerCutting ? 1 : 0);
            Append(canonical, scenario.FixedStepSeconds);
            Append(canonical, scenario.MaxSimulationTicks);
            Append(canonical, scenario.GoalSetId);
            Append(canonical, scenario.InitializationBudgetMilliseconds);
            Append(canonical, scenario.DefaultPlanBudgetMilliseconds);
            Append(canonical, scenario.DefaultRepairBudgetMilliseconds);

            Append(canonical, scenario.Agents.Count);
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                Append(canonical, agent.AgentId);
                Append(canonical, agent.Start.x);
                Append(canonical, agent.Start.y);
                Append(canonical, agent.Goal.x);
                Append(canonical, agent.Goal.y);
            }

            Append(canonical, scenario.InitialGridOverrides.Count);
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++) Append(canonical, scenario.InitialGridOverrides[index]);

            Append(canonical, scenario.ScheduledChanges.Count);
            for (int index = 0; index < scenario.ScheduledChanges.Count; index++)
            {
                ResolvedScheduledNavigationChange scheduled = scenario.ScheduledChanges[index];
                Append(canonical, scheduled.EventId);
                Append(canonical, scheduled.SimulationTick);
                Append(canonical, scheduled.Order);
                Append(canonical, scheduled.RepairBudgetMilliseconds);
                Append(canonical, scheduled.Changes.Count);
                for (int changeIndex = 0; changeIndex < scheduled.Changes.Count; changeIndex++) Append(canonical, scheduled.Changes[changeIndex]);
            }

            using (SHA256 sha256 = SHA256.Create())
            {
                byte[] hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(canonical.ToString()));
                return BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void Append(StringBuilder builder, NavigationGridChange change)
        {
            Append(builder, change.coordinate.x);
            Append(builder, change.coordinate.y);
            Append(builder, change.isWalkable ? 1 : 0);
            Append(builder, change.traversalCost);
        }

        private static void Append(StringBuilder builder, string value)
        {
            string text = value ?? string.Empty;
            builder.Append(text.Length.ToString(CultureInfo.InvariantCulture)).Append(':').Append(text).Append('|');
        }

        private static void Append(StringBuilder builder, int value) { Append(builder, value.ToString(CultureInfo.InvariantCulture)); }
        private static void Append(StringBuilder builder, long value) { Append(builder, value.ToString(CultureInfo.InvariantCulture)); }
        private static void Append(StringBuilder builder, float value) { Append(builder, value.ToString("R", CultureInfo.InvariantCulture)); }
        private static void Append(StringBuilder builder, double value) { Append(builder, value.ToString("R", CultureInfo.InvariantCulture)); }

        private static int CompareCoordinates(GridCoordinate left, GridCoordinate right)
        {
            int yComparison = left.y.CompareTo(right.y);
            return yComparison != 0 ? yComparison : left.x.CompareTo(right.x);
        }

        private static int CompareChanges(NavigationGridChange left, NavigationGridChange right)
        {
            return CompareCoordinates(left.coordinate, right.coordinate);
        }

        private static int CompareScheduledChanges(ResolvedScheduledNavigationChange left, ResolvedScheduledNavigationChange right)
        {
            int tickComparison = left.SimulationTick.CompareTo(right.SimulationTick);
            if (tickComparison != 0) return tickComparison;
            int orderComparison = left.Order.CompareTo(right.Order);
            return orderComparison != 0 ? orderComparison : string.CompareOrdinal(left.EventId, right.EventId);
        }
    }
}
