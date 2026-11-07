using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Gate14Re.V1
{
    /// <summary>
    /// Frozen, pre-data Gate 14Re mechanical protocol.  It does not read or write
    /// outcome data.  Source scenario bytes remain authoritative; the only event
    /// mutation is an in-memory replacement of the five simulation ticks.
    /// </summary>
    public static class Gate14ReProtocolV1
    {
        public const double FixedStepSeconds = 0.02d;
        public const double MovementCapSeconds = 180d;
        public const long MovementCapTicks = 9000L;
        public const int SourceAgentCount = 128;

        private static readonly string[] EventIds =
        {
            "block-footprint",
            "unblock-footprint",
            "increase-cost-footprint",
            "decrease-cost-footprint",
            "restore-initial-state"
        };

        private static readonly long[] SourceTicks = { 10L, 10L, 50000L, 75000L, 99999L };
        private static readonly long[] Gate14ReTicks = { 10L, 10L, 1500L, 4500L, 7500L };
        private static readonly int[] EventOrders = { 0, 1, 0, 0, 0 };

        public static Gate14RePreparedScenario Prepare(
            LoadedDeterministicScenario loaded,
            string expectedScenarioId,
            string expectedSourceSha256,
            string conditionId,
            int expectedDynamicFootprintCells,
            int unitCount)
        {
            if (loaded == null) throw new ArgumentNullException("loaded");
            if (string.IsNullOrWhiteSpace(expectedScenarioId)) throw new ArgumentException("Expected scenario id is required.", "expectedScenarioId");
            if (string.IsNullOrWhiteSpace(expectedSourceSha256)) throw new ArgumentException("Expected source SHA-256 is required.", "expectedSourceSha256");
            if (string.IsNullOrWhiteSpace(conditionId)) throw new ArgumentException("Condition id is required.", "conditionId");
            if (expectedDynamicFootprintCells <= 0) throw new ArgumentOutOfRangeException("expectedDynamicFootprintCells");
            RequireSupportedUnitCount(unitCount);

            string expectedHash = expectedSourceSha256.Trim().ToLowerInvariant();
            if (!string.Equals(loaded.SourceSha256, expectedHash, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Source scenario SHA-256 does not match the frozen Gate 14Re binding.");
            }
            if (!string.Equals(loaded.Resolved.ScenarioId, expectedScenarioId, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Source scenario id does not match the frozen Gate 14Re binding.");
            }
            ResolvedDeterministicScenario definitionSnapshot = loaded.Definition.Resolve();
            if (!string.Equals(definitionSnapshot.FingerprintSha256, loaded.Resolved.FingerprintSha256, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Loaded source definition changed after its SHA-256-bound parse.");
            }
            if (Math.Abs(loaded.Resolved.FixedStepSeconds - FixedStepSeconds) > 1e-12d)
            {
                throw new InvalidOperationException("Source fixed step is not the frozen 0.02 seconds.");
            }
            if (loaded.Resolved.MaxSimulationTicks <= Gate14ReTicks[Gate14ReTicks.Length - 1])
            {
                throw new InvalidOperationException("Source maxSimulationTicks cannot contain the Gate 14Re event calendar.");
            }

            ValidateSourceEvents(loaded.Definition, expectedDynamicFootprintCells);
            string sourceEventContentSha256 = ComputeEventContentSha256(loaded.Definition.scheduledChanges, false);

            DeterministicScenarioDefinition copy = CloneDefinition(loaded.Definition);
            copy.agents = BuildAgents(loaded.Resolved, conditionId, unitCount);
            for (int index = 0; index < copy.scheduledChanges.Length; index++)
            {
                copy.scheduledChanges[index].simulationTick = Gate14ReTicks[index];
            }

            string retimedEventContentSha256 = ComputeEventContentSha256(copy.scheduledChanges, false);
            if (!string.Equals(sourceEventContentSha256, retimedEventContentSha256, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Event content changed while applying the Gate 14Re in-memory tick adapter.");
            }

            ResolvedDeterministicScenario resolved = copy.Resolve();
            ValidateRetimedEvents(resolved, expectedDynamicFootprintCells);
            if (resolved.Agents.Count != unitCount) throw new InvalidOperationException("Prepared scenario has an unexpected unit count.");
            if (resolved.Goals.Count != 1) throw new InvalidOperationException("Gate 14Re requires exactly one shared logical goal.");

            return new Gate14RePreparedScenario(
                conditionId,
                expectedHash,
                loaded.Resolved.FingerprintSha256,
                sourceEventContentSha256,
                retimedEventContentSha256,
                copy,
                resolved);
        }

        public static IReadOnlyList<string> GetEventIds()
        {
            return new ReadOnlyCollection<string>((string[])EventIds.Clone());
        }

        public static IReadOnlyList<long> GetSourceTicks()
        {
            return new ReadOnlyCollection<long>((long[])SourceTicks.Clone());
        }

        public static IReadOnlyList<long> GetRetimedTicks()
        {
            return new ReadOnlyCollection<long>((long[])Gate14ReTicks.Clone());
        }

        private static void RequireSupportedUnitCount(int unitCount)
        {
            if (unitCount != 1 && unitCount != 8 && unitCount != 32 && unitCount != 128 && unitCount != 512)
            {
                throw new ArgumentOutOfRangeException("unitCount", "Gate 14Re supports only N={1,8,32,128,512}.");
            }
        }

        private static void ValidateSourceEvents(DeterministicScenarioDefinition definition, int footprint)
        {
            ScheduledNavigationChangeDefinition[] events = definition.scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            if (events.Length != EventIds.Length) throw new InvalidOperationException("Gate 14Re source scenarios must contain exactly five scheduled changes.");
            for (int index = 0; index < events.Length; index++)
            {
                ScheduledNavigationChangeDefinition item = events[index];
                if (item == null) throw new InvalidOperationException("A frozen source event is null.");
                if (!string.Equals(item.eventId, EventIds[index], StringComparison.Ordinal)) throw new InvalidOperationException("Frozen source event id/order drift at index " + index + ".");
                if (item.simulationTick != SourceTicks[index]) throw new InvalidOperationException("Frozen source event tick drift for " + item.eventId + ".");
                if (item.order != EventOrders[index]) throw new InvalidOperationException("Frozen source event order drift for " + item.eventId + ".");
                if (Math.Abs(item.repairBudgetMilliseconds - 10000d) > 1e-9d) throw new InvalidOperationException("Frozen repair budget drift for " + item.eventId + ".");
                int expectedCount = index == 4 ? checked(footprint * 4) : footprint;
                NavigationGridChange[] changes = item.changes ?? new NavigationGridChange[0];
                if (changes.Length != expectedCount) throw new InvalidOperationException("Frozen change count drift for " + item.eventId + ".");
            }

            HashSet<GridCoordinate> first = Coordinates(events[0].changes);
            HashSet<GridCoordinate> second = Coordinates(events[1].changes);
            foreach (GridCoordinate coordinate in first)
            {
                if (second.Contains(coordinate)) throw new InvalidOperationException("The two tick-10 source footprints must remain disjoint.");
            }
        }

        private static void ValidateRetimedEvents(ResolvedDeterministicScenario scenario, int footprint)
        {
            if (scenario.ScheduledChanges.Count != EventIds.Length) throw new InvalidOperationException("Retimed scenario has an unexpected event count.");
            for (int index = 0; index < scenario.ScheduledChanges.Count; index++)
            {
                ResolvedScheduledNavigationChange item = scenario.ScheduledChanges[index];
                if (!string.Equals(item.EventId, EventIds[index], StringComparison.Ordinal)) throw new InvalidOperationException("Retimed event id/order drift.");
                if (item.SimulationTick != Gate14ReTicks[index]) throw new InvalidOperationException("Retimed event tick drift for " + item.EventId + ".");
                if (item.Order != EventOrders[index]) throw new InvalidOperationException("Retimed event order drift for " + item.EventId + ".");
                if (item.SimulationTick < 0L || item.SimulationTick >= MovementCapTicks) throw new InvalidOperationException("Retimed event is outside the movement cap.");
                int expectedCount = index == 4 ? checked(footprint * 4) : footprint;
                if (item.Changes.Count != expectedCount) throw new InvalidOperationException("Retimed event change-count drift.");
            }
        }

        private static ScenarioAgentDefinition[] BuildAgents(ResolvedDeterministicScenario source, string conditionId, int unitCount)
        {
            if (source.Agents.Count != SourceAgentCount) throw new InvalidOperationException("Frozen Gate 14Re source scenario must contain exactly 128 agents.");
            if (source.Goals.Count != 1) throw new InvalidOperationException("Frozen Gate 14Re source scenario must contain one shared goal.");

            int prefixCount = Math.Min(unitCount, SourceAgentCount);
            List<ScenarioAgentDefinition> result = new List<ScenarioAgentDefinition>(unitCount);
            HashSet<GridCoordinate> occupied = new HashSet<GridCoordinate>();
            for (int index = 0; index < prefixCount; index++)
            {
                ResolvedScenarioAgent sourceAgent = source.Agents[index];
                if (sourceAgent.AgentId != index) throw new InvalidOperationException("Source agent ids must be the canonical sequence 0..127.");
                if (!sourceAgent.Goal.Equals(source.Goals[0])) throw new InvalidOperationException("All Gate 14Re source agents must share the same goal.");
                if (!occupied.Add(sourceAgent.Start)) throw new InvalidOperationException("Source start coordinates must be distinct.");
                result.Add(new ScenarioAgentDefinition { agentId = sourceAgent.AgentId, start = sourceAgent.Start, goal = sourceAgent.Goal });
            }

            if (unitCount <= SourceAgentCount) return result.ToArray();

            ResearchNavigationGrid grid = source.CreateGrid();
            HashSet<GridCoordinate> reachable = ComputeInitiallyReachable(grid, source.Goals[0], source.Connectivity, source.AllowDiagonalCornerCutting);
            List<CandidateStart> candidates = new List<CandidateStart>();
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    if (!grid.IsWalkable(coordinate) || coordinate.Equals(source.Goals[0]) || occupied.Contains(coordinate) || !reachable.Contains(coordinate)) continue;
                    candidates.Add(new CandidateStart(coordinate, CandidateHash(conditionId, coordinate)));
                }
            }
            candidates.Sort(CandidateStart.Compare);
            int needed = unitCount - SourceAgentCount;
            if (candidates.Count < needed) throw new InvalidOperationException("Insufficient frozen, initially reachable distinct starts for N=512.");
            for (int index = 0; index < needed; index++)
            {
                GridCoordinate start = candidates[index].Coordinate;
                if (!occupied.Add(start)) throw new InvalidOperationException("N=512 candidate selection produced a duplicate start.");
                result.Add(new ScenarioAgentDefinition { agentId = SourceAgentCount + index, start = start, goal = source.Goals[0] });
            }
            return result.ToArray();
        }

        private static HashSet<GridCoordinate> ComputeInitiallyReachable(
            IReadOnlyNavigationGrid grid,
            GridCoordinate goal,
            NavigationGridConnectivity connectivity,
            bool allowDiagonalCornerCutting)
        {
            if (!grid.IsWalkable(goal)) throw new InvalidOperationException("Shared goal is not initially walkable.");
            HashSet<GridCoordinate> visited = new HashSet<GridCoordinate>();
            Queue<GridCoordinate> queue = new Queue<GridCoordinate>();
            visited.Add(goal);
            queue.Enqueue(goal);
            while (queue.Count > 0)
            {
                GridCoordinate current = queue.Dequeue();
                foreach (GridCoordinate next in Neighbors(grid, current, connectivity, allowDiagonalCornerCutting))
                {
                    if (visited.Add(next)) queue.Enqueue(next);
                }
            }
            return visited;
        }

        private static IEnumerable<GridCoordinate> Neighbors(
            IReadOnlyNavigationGrid grid,
            GridCoordinate current,
            NavigationGridConnectivity connectivity,
            bool allowDiagonalCornerCutting)
        {
            int[] dx = connectivity == NavigationGridConnectivity.FourWay
                ? new[] { 0, 1, 0, -1 }
                : new[] { 0, 1, 0, -1, 1, 1, -1, -1 };
            int[] dy = connectivity == NavigationGridConnectivity.FourWay
                ? new[] { 1, 0, -1, 0 }
                : new[] { 1, 0, -1, 0, 1, -1, -1, 1 };
            for (int index = 0; index < dx.Length; index++)
            {
                GridCoordinate next = new GridCoordinate(current.x + dx[index], current.y + dy[index]);
                if (!grid.Contains(next) || !grid.IsWalkable(next)) continue;
                if (dx[index] != 0 && dy[index] != 0 && !allowDiagonalCornerCutting)
                {
                    GridCoordinate sideA = new GridCoordinate(current.x + dx[index], current.y);
                    GridCoordinate sideB = new GridCoordinate(current.x, current.y + dy[index]);
                    if (!grid.IsWalkable(sideA) || !grid.IsWalkable(sideB)) continue;
                }
                yield return next;
            }
        }

        private static DeterministicScenarioDefinition CloneDefinition(DeterministicScenarioDefinition source)
        {
            ScenarioAgentDefinition[] sourceAgents = source.agents ?? new ScenarioAgentDefinition[0];
            ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[sourceAgents.Length];
            for (int index = 0; index < agents.Length; index++)
            {
                ScenarioAgentDefinition item = sourceAgents[index];
                agents[index] = item == null ? null : new ScenarioAgentDefinition { agentId = item.agentId, start = item.start, goal = item.goal };
            }

            NavigationGridChange[] initial = source.initialGridOverrides == null
                ? new NavigationGridChange[0]
                : (NavigationGridChange[])source.initialGridOverrides.Clone();
            ScheduledNavigationChangeDefinition[] sourceEvents = source.scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            ScheduledNavigationChangeDefinition[] events = new ScheduledNavigationChangeDefinition[sourceEvents.Length];
            for (int index = 0; index < events.Length; index++)
            {
                ScheduledNavigationChangeDefinition item = sourceEvents[index];
                events[index] = item == null ? null : new ScheduledNavigationChangeDefinition
                {
                    eventId = item.eventId,
                    simulationTick = item.simulationTick,
                    order = item.order,
                    repairBudgetMilliseconds = item.repairBudgetMilliseconds,
                    changes = item.changes == null ? new NavigationGridChange[0] : (NavigationGridChange[])item.changes.Clone()
                };
            }

            return new DeterministicScenarioDefinition
            {
                schemaVersion = source.schemaVersion,
                scenarioId = source.scenarioId,
                randomSeed = source.randomSeed,
                gridWidth = source.gridWidth,
                gridHeight = source.gridHeight,
                defaultTraversalCost = source.defaultTraversalCost,
                worldOrigin = source.worldOrigin,
                cellSize = source.cellSize,
                connectivity = source.connectivity,
                allowDiagonalCornerCutting = source.allowDiagonalCornerCutting,
                fixedStepSeconds = source.fixedStepSeconds,
                maxSimulationTicks = source.maxSimulationTicks,
                goalSetId = source.goalSetId,
                initializationBudgetMilliseconds = source.initializationBudgetMilliseconds,
                defaultPlanBudgetMilliseconds = source.defaultPlanBudgetMilliseconds,
                defaultRepairBudgetMilliseconds = source.defaultRepairBudgetMilliseconds,
                agents = agents,
                initialGridOverrides = initial,
                scheduledChanges = events
            };
        }

        private static string ComputeEventContentSha256(ScheduledNavigationChangeDefinition[] events, bool includeTicks)
        {
            StringBuilder text = new StringBuilder(4096);
            ScheduledNavigationChangeDefinition[] safe = events ?? new ScheduledNavigationChangeDefinition[0];
            for (int index = 0; index < safe.Length; index++)
            {
                ScheduledNavigationChangeDefinition item = safe[index];
                if (item == null) { text.Append("null|"); continue; }
                text.Append(item.eventId ?? string.Empty).Append('|');
                if (includeTicks) text.Append(item.simulationTick.ToString(CultureInfo.InvariantCulture)).Append('|');
                text.Append(item.order.ToString(CultureInfo.InvariantCulture)).Append('|');
                text.Append(item.repairBudgetMilliseconds.ToString("R", CultureInfo.InvariantCulture)).Append('|');
                NavigationGridChange[] changes = item.changes ?? new NavigationGridChange[0];
                NavigationGridChange[] ordered = (NavigationGridChange[])changes.Clone();
                Array.Sort(ordered, CompareChanges);
                for (int changeIndex = 0; changeIndex < ordered.Length; changeIndex++)
                {
                    NavigationGridChange change = ordered[changeIndex];
                    text.Append(change.coordinate.x.ToString(CultureInfo.InvariantCulture)).Append(',');
                    text.Append(change.coordinate.y.ToString(CultureInfo.InvariantCulture)).Append(',');
                    text.Append(change.isWalkable ? '1' : '0').Append(',');
                    text.Append(change.traversalCost.ToString("R", CultureInfo.InvariantCulture)).Append(';');
                }
                text.Append('|');
            }
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text.ToString()))).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static HashSet<GridCoordinate> Coordinates(NavigationGridChange[] changes)
        {
            HashSet<GridCoordinate> result = new HashSet<GridCoordinate>();
            NavigationGridChange[] safe = changes ?? new NavigationGridChange[0];
            for (int index = 0; index < safe.Length; index++)
            {
                if (!result.Add(safe[index].coordinate)) throw new InvalidOperationException("Frozen event contains duplicate coordinates.");
            }
            return result;
        }

        private static string CandidateHash(string conditionId, GridCoordinate coordinate)
        {
            string value = "Gate14Re|" + conditionId + "|" + coordinate.x.ToString(CultureInfo.InvariantCulture) + "|" + coordinate.y.ToString(CultureInfo.InvariantCulture);
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static int CompareChanges(NavigationGridChange left, NavigationGridChange right)
        {
            int y = left.coordinate.y.CompareTo(right.coordinate.y);
            return y != 0 ? y : left.coordinate.x.CompareTo(right.coordinate.x);
        }

        private sealed class CandidateStart
        {
            public GridCoordinate Coordinate { get; private set; }
            public string Hash { get; private set; }

            public CandidateStart(GridCoordinate coordinate, string hash)
            {
                Coordinate = coordinate;
                Hash = hash;
            }

            public static int Compare(CandidateStart left, CandidateStart right)
            {
                int hash = string.CompareOrdinal(left.Hash, right.Hash);
                if (hash != 0) return hash;
                int y = left.Coordinate.y.CompareTo(right.Coordinate.y);
                return y != 0 ? y : left.Coordinate.x.CompareTo(right.Coordinate.x);
            }
        }
    }

    public sealed class Gate14RePreparedScenario
    {
        public string ConditionId { get; private set; }
        public string SourceSha256 { get; private set; }
        public string SourceFingerprintSha256 { get; private set; }
        public string SourceEventContentSha256 { get; private set; }
        public string RetimedEventContentSha256 { get; private set; }
        public DeterministicScenarioDefinition Definition { get; private set; }
        public ResolvedDeterministicScenario Resolved { get; private set; }

        internal Gate14RePreparedScenario(
            string conditionId,
            string sourceSha256,
            string sourceFingerprintSha256,
            string sourceEventContentSha256,
            string retimedEventContentSha256,
            DeterministicScenarioDefinition definition,
            ResolvedDeterministicScenario resolved)
        {
            ConditionId = conditionId;
            SourceSha256 = sourceSha256;
            SourceFingerprintSha256 = sourceFingerprintSha256;
            SourceEventContentSha256 = sourceEventContentSha256;
            RetimedEventContentSha256 = retimedEventContentSha256;
            Definition = definition;
            Resolved = resolved;
        }
    }
}
