using System;
using System.Collections.Generic;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Scenarios
{
    /// <summary>
    /// Frozen Gate 11 scenario-factor row. These records are metadata only; all
    /// runtime inputs are materialized into DeterministicScenarioDefinition.
    /// </summary>
    [Serializable]
    public sealed class FormalScenarioBlueprint
    {
        public string scenarioId;
        public string familyId;
        public int structuralRow;
        public int seedReplication;
        public int randomSeed;
        public int gridWidth;
        public int gridHeight;
        public NavigationGridConnectivity connectivity;
        public string terrainModeId;
        public double targetObstacleDensity;
        public int targetObstacleCount;
        public int agentCount;
        public int dynamicFootprint;
        public string goalStructureId;
        public int distinctGoalCount;
        public string dynamicProfileId;
        public string levelId;

        public bool IsSharedGoal
        {
            get { return string.Equals(goalStructureId, FormalScenarioMatrixGenerator.SharedGoalStructureId, StringComparison.Ordinal); }
        }

        public bool IsTemporaryDisconnection
        {
            get { return string.Equals(dynamicProfileId, FormalScenarioMatrixGenerator.TemporaryDisconnectionProfileId, StringComparison.Ordinal); }
        }
    }

    /// <summary>
    /// Integer-only, order-independent generator frozen for Gate 11. It never
    /// consults wall time, locale, filesystem order, or a platform RNG.
    /// </summary>
    public static class FormalScenarioMatrixGenerator
    {
        public const string SpecificationId = "formal-scenario-matrix-v1";
        public const string GeneratorId = "ddm-formal-scenario-generator-v1";
        public const string PreregistrationId = "ddm-planning-preregistration-v1";
        public const string SharedGoalStructureId = "shared-single-v1";
        public const string HeterogeneousGoalStructureId = "heterogeneous-v1";
        public const string MixedDynamicProfileId = "mixed-five-event-four-phase-v1";
        public const string TemporaryDisconnectionProfileId = "temporary-disconnect-restore-v1";
        public const string UniformTerrainId = "uniform-v1";
        public const string WeightedTerrainId = "weighted-1-2-4-8-v1";
        public const int ExpectedScenarioCount = 53;
        public const int ExpectedEligibilityCount = 212;

        private const ulong ObstacleSalt = 0x91e10da5c79e7b1dUL;
        private const ulong TerrainSalt = 0xd1b54a32d192ed03UL;
        private const ulong BlockSalt = 0x94d049bb133111ebUL;
        private const ulong UnblockSalt = 0xbf58476d1ce4e5b9UL;
        private const ulong IncreaseSalt = 0x9e3779b97f4a7c15UL;
        private const ulong DecreaseSalt = 0x632be59bd9b4e019UL;
        private const ulong GoalSalt = 0x8cb92baa3f3d8dd7UL;
        private const ulong StartSalt = 0xdb4f0b9175ae2165UL;

        private sealed class KeyedCoordinate
        {
            public GridCoordinate Coordinate;
            public ulong Key;
        }

        private sealed class KeyedCoordinateComparer : IComparer<KeyedCoordinate>
        {
            public int Compare(KeyedCoordinate left, KeyedCoordinate right)
            {
                int keyComparison = left.Key.CompareTo(right.Key);
                if (keyComparison != 0) return keyComparison;
                int yComparison = left.Coordinate.y.CompareTo(right.Coordinate.y);
                return yComparison != 0 ? yComparison : left.Coordinate.x.CompareTo(right.Coordinate.x);
            }
        }

        public static FormalScenarioBlueprint[] BuildBlueprints()
        {
            List<FormalScenarioBlueprint> rows = new List<FormalScenarioBlueprint>(ExpectedScenarioCount);

            int[] grids = { 64, 64, 64, 64, 128, 128, 128, 128 };
            NavigationGridConnectivity[] connectivities =
            {
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.FourWay,
                NavigationGridConnectivity.EightWay,
                NavigationGridConnectivity.EightWay
            };
            string[] terrains =
            {
                UniformTerrainId, WeightedTerrainId, UniformTerrainId, WeightedTerrainId,
                UniformTerrainId, WeightedTerrainId, UniformTerrainId, WeightedTerrainId
            };
            double[] densities = { 0.10d, 0.25d, 0.25d, 0.10d, 0.25d, 0.10d, 0.10d, 0.25d };
            int[] agents = { 16, 128, 128, 16, 16, 128, 128, 16 };
            int[] footprints = { 9, 81, 9, 81, 81, 9, 81, 9 };

            for (int row = 1; row <= 8; row++)
            {
                for (int replication = 1; replication <= 2; replication++)
                {
                    int seed = 110000 + row * 10 + replication;
                    AddGeneral(rows, string.Format("core-r{0:00}-s{1}-shared", row, replication), "balanced-core-v1", row, replication,
                        seed, grids[row - 1], connectivities[row - 1], terrains[row - 1], densities[row - 1], agents[row - 1], footprints[row - 1],
                        SharedGoalStructureId, 1, "row-" + row);
                    int goalCount = agents[row - 1] == 16 ? 4 : 16;
                    AddGeneral(rows, string.Format("core-r{0:00}-s{1}-hetero", row, replication), "balanced-core-v1", row, replication,
                        seed, grids[row - 1], connectivities[row - 1], terrains[row - 1], densities[row - 1], agents[row - 1], footprints[row - 1],
                        HeterogeneousGoalStructureId, goalCount, "row-" + row);
                }
            }

            int[] gridLevels = { 32, 64, 128, 256 };
            for (int index = 0; index < gridLevels.Length; index++)
            {
                int grid = gridLevels[index];
                AddGeneral(rows, string.Format("grid-scale-g{0:000}-shared", grid), "grid-scale-v1", 0, 1,
                    120000 + grid, grid, NavigationGridConnectivity.EightWay, WeightedTerrainId, 0.18d, 64, 25,
                    SharedGoalStructureId, 1, "grid-" + grid);
            }

            int[] agentLevels = { 1, 8, 32, 128, 512 };
            for (int index = 0; index < agentLevels.Length; index++)
            {
                int agentCount = agentLevels[index];
                AddGeneral(rows, string.Format("agent-scale-a{0:000}-shared", agentCount), "agent-scale-v1", 0, 1,
                    130000 + agentCount, 128, NavigationGridConnectivity.FourWay, WeightedTerrainId, 0.18d, agentCount, 25,
                    SharedGoalStructureId, 1, "agents-" + agentCount);
            }

            int[] footprintLevels = { 1, 9, 25, 81, 225 };
            for (int index = 0; index < footprintLevels.Length; index++)
            {
                int footprint = footprintLevels[index];
                AddGeneral(rows, string.Format("dynamic-footprint-f{0:000}-shared", footprint), "dynamic-footprint-v1", 0, 1,
                    140000 + footprint, 128, NavigationGridConnectivity.EightWay, WeightedTerrainId, 0.18d, 64, footprint,
                    SharedGoalStructureId, 1, "footprint-" + footprint);
            }

            int[] goalLevels = { 2, 4, 8, 16, 32 };
            for (int index = 0; index < goalLevels.Length; index++)
            {
                int goalCount = goalLevels[index];
                AddGeneral(rows, string.Format("goal-count-g{0:00}-hetero", goalCount), "goal-count-v1", 0, 1,
                    150000 + goalCount, 128, NavigationGridConnectivity.EightWay, WeightedTerrainId, 0.18d, 128, 25,
                    HeterogeneousGoalStructureId, goalCount, "goals-" + goalCount);
            }

            AddReachability(rows, NavigationGridConnectivity.FourWay);
            AddReachability(rows, NavigationGridConnectivity.EightWay);

            if (rows.Count != ExpectedScenarioCount) throw new InvalidOperationException("The frozen Gate 11 blueprint count changed.");
            return rows.ToArray();
        }

        public static DeterministicScenarioDefinition GenerateDefinition(FormalScenarioBlueprint blueprint)
        {
            if (blueprint == null) throw new ArgumentNullException("blueprint");
            ValidateBlueprint(blueprint);

            bool[,] protectedCells = BuildProtectedMap(blueprint.gridWidth, blueprint.gridHeight);
            bool[,] walkable = new bool[blueprint.gridWidth, blueprint.gridHeight];
            float[,] costs = new float[blueprint.gridWidth, blueprint.gridHeight];
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                for (int x = 0; x < blueprint.gridWidth; x++)
                {
                    walkable[x, y] = true;
                    costs[x, y] = 1f;
                }
            }

            if (blueprint.IsTemporaryDisconnection)
            {
                MaterializeBarrier(blueprint, walkable, costs);
            }
            else
            {
                MaterializeGeneralTopology(blueprint, protectedCells, walkable, costs);
            }

            ScenarioAgentDefinition[] agents = blueprint.IsTemporaryDisconnection
                ? BuildBarrierAgents(blueprint, protectedCells)
                : BuildGeneralAgents(blueprint, protectedCells);

            ScheduledNavigationChangeDefinition[] scheduled = blueprint.IsTemporaryDisconnection
                ? BuildBarrierEvents(blueprint)
                : BuildGeneralEvents(blueprint, protectedCells, walkable, costs);

            NavigationGridChange[] initial = new NavigationGridChange[checked(blueprint.gridWidth * blueprint.gridHeight)];
            int cellIndex = 0;
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                for (int x = 0; x < blueprint.gridWidth; x++)
                {
                    initial[cellIndex++] = Change(x, y, walkable[x, y], costs[x, y]);
                }
            }

            DeterministicScenarioDefinition definition = new DeterministicScenarioDefinition
            {
                schemaVersion = DeterministicScenarioDefinition.CurrentSchemaVersion,
                scenarioId = blueprint.scenarioId,
                randomSeed = blueprint.randomSeed,
                gridWidth = blueprint.gridWidth,
                gridHeight = blueprint.gridHeight,
                defaultTraversalCost = 1f,
                worldOrigin = Vector3.zero,
                cellSize = 1f,
                connectivity = blueprint.connectivity,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 100001,
                goalSetId = blueprint.scenarioId + "-goals",
                initializationBudgetMilliseconds = 30000d,
                defaultPlanBudgetMilliseconds = 10000d,
                defaultRepairBudgetMilliseconds = 10000d,
                agents = agents,
                initialGridOverrides = initial,
                scheduledChanges = scheduled
            };
            definition.Resolve();
            return definition;
        }

        public static bool[,] BuildProtectedMap(int width, int height)
        {
            bool[,] map = new bool[width, height];
            int[] rows = UniqueBackboneIndices(height);
            int[] columns = UniqueBackboneIndices(width);
            for (int index = 0; index < rows.Length; index++)
            {
                int y = rows[index];
                for (int x = 0; x < width; x++) map[x, y] = true;
            }
            for (int index = 0; index < columns.Length; index++)
            {
                int x = columns[index];
                for (int y = 0; y < height; y++) map[x, y] = true;
            }
            return map;
        }

        public static ulong DeterministicKey(int seed, int x, int y, ulong salt)
        {
            unchecked
            {
                ulong value = (ulong)(uint)seed;
                value ^= ((ulong)(uint)x << 32) | (uint)y;
                value ^= salt;
                return SplitMix64(value);
            }
        }

        public static ulong SplitMix64(ulong value)
        {
            unchecked
            {
                ulong z = value + 0x9e3779b97f4a7c15UL;
                z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL;
                z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL;
                return z ^ (z >> 31);
            }
        }

        private static void AddGeneral(
            List<FormalScenarioBlueprint> rows,
            string scenarioId,
            string familyId,
            int structuralRow,
            int seedReplication,
            int seed,
            int grid,
            NavigationGridConnectivity connectivity,
            string terrain,
            double density,
            int agents,
            int footprint,
            string goalStructure,
            int goals,
            string levelId)
        {
            int target = (int)Math.Round(grid * (double)grid * density, MidpointRounding.AwayFromZero);
            rows.Add(new FormalScenarioBlueprint
            {
                scenarioId = scenarioId,
                familyId = familyId,
                structuralRow = structuralRow,
                seedReplication = seedReplication,
                randomSeed = seed,
                gridWidth = grid,
                gridHeight = grid,
                connectivity = connectivity,
                terrainModeId = terrain,
                targetObstacleDensity = density,
                targetObstacleCount = target,
                agentCount = agents,
                dynamicFootprint = footprint,
                goalStructureId = goalStructure,
                distinctGoalCount = goals,
                dynamicProfileId = MixedDynamicProfileId,
                levelId = levelId
            });
        }

        private static void AddReachability(List<FormalScenarioBlueprint> rows, NavigationGridConnectivity connectivity)
        {
            int grid = 64;
            int target = grid - 2;
            rows.Add(new FormalScenarioBlueprint
            {
                scenarioId = connectivity == NavigationGridConnectivity.FourWay ? "reachability-c4-shared" : "reachability-c8-strict-shared",
                familyId = "reachability-v1",
                structuralRow = 0,
                seedReplication = 1,
                randomSeed = 160000 + (int)connectivity,
                gridWidth = grid,
                gridHeight = grid,
                connectivity = connectivity,
                terrainModeId = UniformTerrainId,
                targetObstacleDensity = target / (double)(grid * grid),
                targetObstacleCount = target,
                agentCount = 32,
                dynamicFootprint = 1,
                goalStructureId = SharedGoalStructureId,
                distinctGoalCount = 1,
                dynamicProfileId = TemporaryDisconnectionProfileId,
                levelId = "connectivity-" + (int)connectivity
            });
        }

        private static void ValidateBlueprint(FormalScenarioBlueprint blueprint)
        {
            if (string.IsNullOrWhiteSpace(blueprint.scenarioId) || string.IsNullOrWhiteSpace(blueprint.familyId)) throw new ArgumentException("Blueprint identity is incomplete.");
            if (blueprint.gridWidth < 4 || blueprint.gridHeight < 4) throw new ArgumentException("Blueprint grid is too small.");
            if (blueprint.agentCount <= 0 || blueprint.distinctGoalCount <= 0 || blueprint.distinctGoalCount > blueprint.agentCount) throw new ArgumentException("Blueprint agent/goal counts are invalid.");
            if (blueprint.dynamicFootprint <= 0) throw new ArgumentException("Blueprint dynamic footprint is invalid.");
            if (blueprint.targetObstacleCount < 0 || blueprint.targetObstacleCount >= blueprint.gridWidth * blueprint.gridHeight) throw new ArgumentException("Blueprint obstacle count is invalid.");
            if (!string.Equals(blueprint.terrainModeId, UniformTerrainId, StringComparison.Ordinal) &&
                !string.Equals(blueprint.terrainModeId, WeightedTerrainId, StringComparison.Ordinal)) throw new ArgumentException("Blueprint terrain mode is invalid.");
            if (!blueprint.IsSharedGoal && !string.Equals(blueprint.goalStructureId, HeterogeneousGoalStructureId, StringComparison.Ordinal)) throw new ArgumentException("Blueprint goal structure is invalid.");
        }

        private static void MaterializeGeneralTopology(FormalScenarioBlueprint blueprint, bool[,] protectedCells, bool[,] walkable, float[,] costs)
        {
            List<KeyedCoordinate> obstacleCandidates = new List<KeyedCoordinate>();
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                for (int x = 0; x < blueprint.gridWidth; x++)
                {
                    if (!protectedCells[x, y]) obstacleCandidates.Add(Keyed(blueprint.randomSeed, x, y, ObstacleSalt));
                }
            }
            obstacleCandidates.Sort(new KeyedCoordinateComparer());
            if (obstacleCandidates.Count < blueprint.targetObstacleCount) throw new InvalidOperationException("Not enough nonprotected cells for the frozen obstacle target.");
            for (int index = 0; index < blueprint.targetObstacleCount; index++)
            {
                GridCoordinate coordinate = obstacleCandidates[index].Coordinate;
                walkable[coordinate.x, coordinate.y] = false;
            }

            if (string.Equals(blueprint.terrainModeId, WeightedTerrainId, StringComparison.Ordinal))
            {
                float[] values = { 1f, 2f, 4f, 8f };
                for (int y = 0; y < blueprint.gridHeight; y++)
                {
                    for (int x = 0; x < blueprint.gridWidth; x++)
                    {
                        costs[x, y] = walkable[x, y]
                            ? values[(int)(DeterministicKey(blueprint.randomSeed, x, y, TerrainSalt) & 3UL)]
                            : 1f;
                    }
                }
            }
        }

        private static void MaterializeBarrier(FormalScenarioBlueprint blueprint, bool[,] walkable, float[,] costs)
        {
            int barrierX = blueprint.gridWidth / 2;
            int firstGateY = blueprint.gridHeight / 4;
            int secondGateY = (blueprint.gridHeight * 3) / 4;
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                bool gate = y == firstGateY || y == secondGateY;
                walkable[barrierX, y] = gate;
                costs[barrierX, y] = 1f;
            }
        }

        private static ScenarioAgentDefinition[] BuildGeneralAgents(FormalScenarioBlueprint blueprint, bool[,] protectedCells)
        {
            List<KeyedCoordinate> goalCandidates = CollectProtectedCandidates(blueprint, protectedCells, GoalSalt, -1);
            if (goalCandidates.Count < blueprint.distinctGoalCount) throw new InvalidOperationException("Not enough protected goal candidates.");
            GridCoordinate[] goals = new GridCoordinate[blueprint.distinctGoalCount];
            HashSet<GridCoordinate> goalSet = new HashSet<GridCoordinate>();
            for (int index = 0; index < goals.Length; index++)
            {
                goals[index] = goalCandidates[index].Coordinate;
                goalSet.Add(goals[index]);
            }

            List<KeyedCoordinate> startCandidates = CollectProtectedCandidates(blueprint, protectedCells, StartSalt, -1);
            startCandidates.RemoveAll(delegate(KeyedCoordinate item) { return goalSet.Contains(item.Coordinate); });
            if (startCandidates.Count < blueprint.agentCount) throw new InvalidOperationException("Not enough unique protected start candidates.");

            ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[blueprint.agentCount];
            for (int index = 0; index < agents.Length; index++)
            {
                agents[index] = new ScenarioAgentDefinition
                {
                    agentId = index,
                    start = startCandidates[index].Coordinate,
                    goal = goals[index % goals.Length]
                };
            }
            return agents;
        }

        private static ScenarioAgentDefinition[] BuildBarrierAgents(FormalScenarioBlueprint blueprint, bool[,] protectedCells)
        {
            int barrierX = blueprint.gridWidth / 2;
            List<KeyedCoordinate> goals = CollectProtectedCandidates(blueprint, protectedCells, GoalSalt, 1);
            List<KeyedCoordinate> starts = CollectProtectedCandidates(blueprint, protectedCells, StartSalt, 0);
            if (goals.Count == 0 || starts.Count < blueprint.agentCount) throw new InvalidOperationException("The barrier scenario lacks start or goal candidates.");
            GridCoordinate sharedGoal = goals[0].Coordinate;
            ScenarioAgentDefinition[] agents = new ScenarioAgentDefinition[blueprint.agentCount];
            int written = 0;
            for (int index = 0; index < starts.Count && written < agents.Length; index++)
            {
                GridCoordinate start = starts[index].Coordinate;
                if (start.x >= barrierX || start.Equals(sharedGoal)) continue;
                agents[written] = new ScenarioAgentDefinition { agentId = written, start = start, goal = sharedGoal };
                written++;
            }
            if (written != agents.Length) throw new InvalidOperationException("The barrier scenario lacks unique left-side starts.");
            return agents;
        }

        private static List<KeyedCoordinate> CollectProtectedCandidates(FormalScenarioBlueprint blueprint, bool[,] protectedCells, ulong salt, int side)
        {
            List<KeyedCoordinate> candidates = new List<KeyedCoordinate>();
            int barrierX = blueprint.gridWidth / 2;
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                for (int x = 0; x < blueprint.gridWidth; x++)
                {
                    if (!protectedCells[x, y]) continue;
                    if (side == 0 && x >= barrierX) continue;
                    if (side == 1 && x <= barrierX) continue;
                    candidates.Add(Keyed(blueprint.randomSeed, x, y, salt));
                }
            }
            candidates.Sort(new KeyedCoordinateComparer());
            return candidates;
        }

        private static ScheduledNavigationChangeDefinition[] BuildGeneralEvents(FormalScenarioBlueprint blueprint, bool[,] protectedCells, bool[,] walkable, float[,] costs)
        {
            HashSet<GridCoordinate> selected = new HashSet<GridCoordinate>();
            List<GridCoordinate> block = SelectDynamicCells(blueprint, protectedCells, walkable, costs, true, false, BlockSalt, blueprint.dynamicFootprint, selected);
            List<GridCoordinate> unblock = SelectDynamicCells(blueprint, protectedCells, walkable, costs, false, false, UnblockSalt, blueprint.dynamicFootprint, selected);
            List<GridCoordinate> increase = SelectDynamicCells(blueprint, protectedCells, walkable, costs, true, false, IncreaseSalt, blueprint.dynamicFootprint, selected);
            bool requireAboveOne = string.Equals(blueprint.terrainModeId, WeightedTerrainId, StringComparison.Ordinal);
            List<GridCoordinate> decrease = SelectDynamicCells(blueprint, protectedCells, walkable, costs, true, requireAboveOne, DecreaseSalt, blueprint.dynamicFootprint, selected);

            NavigationGridChange[] blockChanges = new NavigationGridChange[block.Count];
            NavigationGridChange[] unblockChanges = new NavigationGridChange[unblock.Count];
            NavigationGridChange[] increaseChanges = new NavigationGridChange[increase.Count];
            NavigationGridChange[] decreaseChanges = new NavigationGridChange[decrease.Count];
            List<GridCoordinate> touched = new List<GridCoordinate>(selected);
            touched.Sort(CompareCoordinates);
            NavigationGridChange[] restoreChanges = new NavigationGridChange[touched.Count];

            for (int index = 0; index < block.Count; index++) blockChanges[index] = Change(block[index].x, block[index].y, false, costs[block[index].x, block[index].y]);
            for (int index = 0; index < unblock.Count; index++) unblockChanges[index] = Change(unblock[index].x, unblock[index].y, true, costs[unblock[index].x, unblock[index].y]);
            for (int index = 0; index < increase.Count; index++) increaseChanges[index] = Change(increase[index].x, increase[index].y, true, 8f);
            for (int index = 0; index < decrease.Count; index++) decreaseChanges[index] = Change(decrease[index].x, decrease[index].y, true, 1f);
            for (int index = 0; index < touched.Count; index++)
            {
                GridCoordinate coordinate = touched[index];
                restoreChanges[index] = Change(coordinate.x, coordinate.y, walkable[coordinate.x, coordinate.y], costs[coordinate.x, coordinate.y]);
            }

            return new[]
            {
                Event("block-footprint", 10, 0, blockChanges),
                Event("unblock-footprint", 10, 1, unblockChanges),
                Event("increase-cost-footprint", 50000, 0, increaseChanges),
                Event("decrease-cost-footprint", 75000, 0, decreaseChanges),
                Event("restore-initial-state", 99999, 0, restoreChanges)
            };
        }

        private static ScheduledNavigationChangeDefinition[] BuildBarrierEvents(FormalScenarioBlueprint blueprint)
        {
            int x = blueprint.gridWidth / 2;
            int firstY = blueprint.gridHeight / 4;
            int secondY = (blueprint.gridHeight * 3) / 4;
            return new[]
            {
                Event("close-first-gate", 10, 0, new[] { Change(x, firstY, false, 1f) }),
                Event("close-second-gate", 50000, 0, new[] { Change(x, secondY, false, 1f) }),
                Event("reopen-first-gate", 75000, 0, new[] { Change(x, firstY, true, 1f) }),
                Event("reopen-second-gate", 99999, 0, new[] { Change(x, secondY, true, 1f) })
            };
        }

        private static List<GridCoordinate> SelectDynamicCells(
            FormalScenarioBlueprint blueprint,
            bool[,] protectedCells,
            bool[,] walkable,
            float[,] costs,
            bool desiredWalkability,
            bool requireCostAboveOne,
            ulong salt,
            int count,
            HashSet<GridCoordinate> selected)
        {
            List<KeyedCoordinate> candidates = new List<KeyedCoordinate>();
            for (int y = 0; y < blueprint.gridHeight; y++)
            {
                for (int x = 0; x < blueprint.gridWidth; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    if (protectedCells[x, y] || selected.Contains(coordinate) || walkable[x, y] != desiredWalkability) continue;
                    if (requireCostAboveOne && costs[x, y] <= 1f) continue;
                    candidates.Add(Keyed(blueprint.randomSeed, x, y, salt));
                }
            }
            candidates.Sort(new KeyedCoordinateComparer());
            if (candidates.Count < count) throw new InvalidOperationException("Not enough disjoint cells for dynamic footprint " + count + ".");
            List<GridCoordinate> result = new List<GridCoordinate>(count);
            for (int index = 0; index < count; index++)
            {
                GridCoordinate coordinate = candidates[index].Coordinate;
                result.Add(coordinate);
                selected.Add(coordinate);
            }
            result.Sort(CompareCoordinates);
            return result;
        }

        private static ScheduledNavigationChangeDefinition Event(string id, long tick, int order, NavigationGridChange[] changes)
        {
            return new ScheduledNavigationChangeDefinition
            {
                eventId = id,
                simulationTick = tick,
                order = order,
                repairBudgetMilliseconds = 10000d,
                changes = changes
            };
        }

        private static NavigationGridChange Change(int x, int y, bool isWalkable, float cost)
        {
            return new NavigationGridChange
            {
                coordinate = new GridCoordinate(x, y),
                isWalkable = isWalkable,
                traversalCost = cost
            };
        }

        private static KeyedCoordinate Keyed(int seed, int x, int y, ulong salt)
        {
            return new KeyedCoordinate
            {
                Coordinate = new GridCoordinate(x, y),
                Key = DeterministicKey(seed, x, y, salt)
            };
        }

        private static int[] UniqueBackboneIndices(int size)
        {
            int[] values = { 1, size / 4, size / 2, (size * 3) / 4, size - 2 };
            List<int> unique = new List<int>();
            for (int index = 0; index < values.Length; index++)
            {
                int value = values[index];
                if (value < 0 || value >= size || unique.Contains(value)) continue;
                unique.Add(value);
            }
            unique.Sort();
            return unique.ToArray();
        }

        private static int CompareCoordinates(GridCoordinate left, GridCoordinate right)
        {
            int yComparison = left.y.CompareTo(right.y);
            return yComparison != 0 ? yComparison : left.x.CompareTo(right.x);
        }
    }
}
