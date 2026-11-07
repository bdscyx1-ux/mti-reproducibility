using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;

namespace DDM.Research.Gate14ReTB.V1
{
    public static class Gate14ReTBProtocolV1
    {
        public const double FixedStepSeconds = 0.02d;
        public const double MovementCapSeconds = 180d;
        public const long MovementCapTicks = 9000L;
        public const int MaximumSpawnCount = 512;
        public const int WarmupRenderedFrames = 600;
        public const int TraceCaptureEveryTicks = 5;

        private static readonly string[] EventIds =
        {
            "block-footprint", "unblock-footprint", "increase-cost-footprint", "decrease-cost-footprint", "restore-initial-state"
        };

        private static readonly long[][] EventSchedules =
        {
            new long[] { 10L, 10L, 1500L, 4500L, 7500L },
            new long[] { 10L, 10L, 1200L, 4200L, 7200L },
            new long[] { 10L, 10L, 1800L, 4800L, 7800L },
            new long[] { 10L, 10L, 2250L, 5250L, 8250L }
        };

        private static readonly string[] EventScheduleIds = { "E01", "E02", "E03", "E04" };

        public static Gate14ReTBPreparedScenarioV1 Prepare(LoadedDeterministicScenario loaded, Gate14ReTBInputBundleV1 bundle)
        {
            if (loaded == null) throw new ArgumentNullException("loaded");
            ValidateBundleHeader(bundle);
            if (!string.Equals(loaded.SourceSha256, bundle.sourceScenarioSha256, StringComparison.Ordinal)) throw new InvalidOperationException("Source scenario SHA-256 does not match input bundle.");
            if (Math.Abs(loaded.Resolved.FixedStepSeconds - FixedStepSeconds) > 1e-12d) throw new InvalidOperationException("Source fixed step drift.");
            if (loaded.Resolved.MaxSimulationTicks <= MovementCapTicks) throw new InvalidOperationException("Source scenario cannot contain the registered movement cap.");
            int scheduleIndex = Array.IndexOf(EventScheduleIds, bundle.eventScheduleVariantId);
            if (scheduleIndex < 0) throw new InvalidOperationException("Unknown event schedule variant.");
            ValidateBundleSchedule(bundle.eventSchedule, scheduleIndex);
            ValidateSourceEvents(loaded.Definition);

            DeterministicScenarioDefinition copy = CloneDefinition(loaded.Definition);
            copy.agents = BuildAgents(copy, bundle);
            for (int index = 0; index < copy.scheduledChanges.Length; index++) copy.scheduledChanges[index].simulationTick = EventSchedules[scheduleIndex][index];
            ResolvedDeterministicScenario resolved = copy.Resolve();
            if (resolved.Agents.Count != bundle.unitCount || resolved.Goals.Count != 1) throw new InvalidOperationException("Prepared scenario population/goal mismatch.");
            for (int index = 0; index < resolved.ScheduledChanges.Count; index++)
            {
                ResolvedScheduledNavigationChange item = resolved.ScheduledChanges[index];
                if (item.EventId != EventIds[index] || item.SimulationTick != EventSchedules[scheduleIndex][index] || item.SimulationTick >= MovementCapTicks)
                    throw new InvalidOperationException("Prepared event schedule mismatch.");
            }
            return new Gate14ReTBPreparedScenarioV1(copy, resolved, bundle);
        }

        public static IReadOnlyList<long> GetEventTicks(Gate14ReTBInputBundleV1 bundle)
        {
            if (bundle == null || bundle.eventSchedule == null || bundle.eventSchedule.ticks == null) throw new ArgumentNullException("bundle");
            return new ReadOnlyCollection<long>((long[])bundle.eventSchedule.ticks.Clone());
        }

        private static void ValidateBundleHeader(Gate14ReTBInputBundleV1 bundle)
        {
            if (bundle == null || bundle.schema != "gate14re-tb-input-bundle-v1" || bundle.studyId != "Gate14Re-TB" || bundle.generatorId != "gate14re-tb-offline-hmac-support-draw-v1")
                throw new InvalidOperationException("Input bundle header mismatch.");
            if (string.IsNullOrWhiteSpace(bundle.superblockId) || string.IsNullOrWhiteSpace(bundle.bundleSha256) || bundle.bundleSha256.Length != 64) throw new InvalidOperationException("Input bundle identity is missing.");
            if (bundle.unitCount != 1 && bundle.unitCount != 8 && bundle.unitCount != 32 && bundle.unitCount != 128 && bundle.unitCount != 512) throw new InvalidOperationException("Unregistered unit count.");
            if (bundle.spawnGridCoordinates512 == null || bundle.spawnGridCoordinates512.Length != MaximumSpawnCount) throw new InvalidOperationException("Input bundle requires 512 ordered spawns.");
            if (bundle.goalGridCoordinate == null || bundle.fixedStepSeconds != FixedStepSeconds || bundle.movementCapSeconds != MovementCapSeconds) throw new InvalidOperationException("Input bundle goal/time binding mismatch.");
            if (bundle.nestedPrefixRule != "use first N of spawnGridCoordinates512") throw new InvalidOperationException("Input bundle prefix rule drift.");
        }

        private static void ValidateBundleSchedule(Gate14ReTBEventScheduleV1 schedule, int scheduleIndex)
        {
            if (schedule == null || schedule.eventIds == null || schedule.ticks == null || schedule.eventIds.Length != EventIds.Length || schedule.ticks.Length != EventIds.Length)
                throw new InvalidOperationException("Input event schedule cardinality mismatch.");
            for (int index = 0; index < EventIds.Length; index++)
            {
                if (schedule.eventIds[index] != EventIds[index] || schedule.ticks[index] != EventSchedules[scheduleIndex][index]) throw new InvalidOperationException("Input event schedule content mismatch.");
            }
        }

        private static void ValidateSourceEvents(DeterministicScenarioDefinition definition)
        {
            ScheduledNavigationChangeDefinition[] events = definition.scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            if (events.Length != EventIds.Length) throw new InvalidOperationException("Source scenario requires exactly five events.");
            for (int index = 0; index < events.Length; index++)
            {
                if (events[index] == null || events[index].eventId != EventIds[index] || events[index].changes == null || events[index].changes.Length == 0)
                    throw new InvalidOperationException("Source event identity/content mismatch.");
            }
        }

        private static ScenarioAgentDefinition[] BuildAgents(DeterministicScenarioDefinition source, Gate14ReTBInputBundleV1 bundle)
        {
            HashSet<GridCoordinate> changed = new HashSet<GridCoordinate>();
            for (int eventIndex = 0; eventIndex < source.scheduledChanges.Length; eventIndex++)
            {
                NavigationGridChange[] changes = source.scheduledChanges[eventIndex].changes ?? new NavigationGridChange[0];
                for (int index = 0; index < changes.Length; index++) changed.Add(changes[index].coordinate);
            }
            GridCoordinate goal = ToGrid(bundle.goalGridCoordinate);
            if (!Contains(source, goal) || changed.Contains(goal)) throw new InvalidOperationException("Input goal is outside the frozen certified support.");
            HashSet<GridCoordinate> used = new HashSet<GridCoordinate>();
            ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[bundle.unitCount];
            for (int index = 0; index < bundle.spawnGridCoordinates512.Length; index++)
            {
                GridCoordinate spawn = ToGrid(bundle.spawnGridCoordinates512[index]);
                if (!Contains(source, spawn) || spawn.Equals(goal) || changed.Contains(spawn) || !used.Add(spawn)) throw new InvalidOperationException("Input spawn list violates distinct certified support.");
                if (index < bundle.unitCount) agents[index] = new ScenarioAgentDefinition { agentId = index, start = spawn, goal = goal };
            }
            return agents;
        }

        private static GridCoordinate ToGrid(Gate14ReTBCoordinateV1 coordinate)
        {
            if (coordinate == null) throw new InvalidOperationException("Null input coordinate.");
            return new GridCoordinate(coordinate.x, coordinate.y);
        }

        private static bool Contains(DeterministicScenarioDefinition source, GridCoordinate coordinate)
        {
            return coordinate.x >= 0 && coordinate.x < source.gridWidth && coordinate.y >= 0 && coordinate.y < source.gridHeight;
        }

        private static DeterministicScenarioDefinition CloneDefinition(DeterministicScenarioDefinition source)
        {
            NavigationGridChange[] initial = source.initialGridOverrides == null ? new NavigationGridChange[0] : (NavigationGridChange[])source.initialGridOverrides.Clone();
            ScheduledNavigationChangeDefinition[] sourceEvents = source.scheduledChanges ?? new ScheduledNavigationChangeDefinition[0];
            ScheduledNavigationChangeDefinition[] events = new ScheduledNavigationChangeDefinition[sourceEvents.Length];
            for (int index = 0; index < sourceEvents.Length; index++)
            {
                ScheduledNavigationChangeDefinition item = sourceEvents[index];
                events[index] = new ScheduledNavigationChangeDefinition
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
                agents = new ScenarioAgentDefinition[0],
                initialGridOverrides = initial,
                scheduledChanges = events
            };
        }
    }

    public sealed class Gate14ReTBPreparedScenarioV1
    {
        public DeterministicScenarioDefinition Definition { get; private set; }
        public ResolvedDeterministicScenario Resolved { get; private set; }
        public Gate14ReTBInputBundleV1 Bundle { get; private set; }
        internal Gate14ReTBPreparedScenarioV1(DeterministicScenarioDefinition definition, ResolvedDeterministicScenario resolved, Gate14ReTBInputBundleV1 bundle)
        {
            Definition = definition;
            Resolved = resolved;
            Bundle = bundle;
        }
    }
}
