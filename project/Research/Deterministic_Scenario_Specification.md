# Deterministic Scenario Specification

Schema version: `1`

Runtime definition: `Assets/_Scripts/Research/Scenarios/DeterministicScenarioDefinition.cs`

## Purpose

One fully materialized scenario must be replayable across every navigation algorithm without using wall-clock scheduling or algorithm-specific map state. A scenario resolves to a canonical immutable snapshot and a SHA-256 fingerprint before an experiment begins.

`randomSeed` records the seed used by a future scenario generator. It does not authorize random generation during an algorithm run. Any generated starts, goals, initial cells, or dynamic events must be written explicitly into the scenario definition before benchmarking.

## Required top-level fields

| Field | Meaning | Constraint |
| --- | --- | --- |
| `schemaVersion` | Scenario schema | Must equal `1` |
| `scenarioId` | Stable human-readable id | Non-empty |
| `randomSeed` | Generator/replay seed | Any 32-bit integer |
| `gridWidth`, `gridHeight` | Research-grid dimensions | Each greater than zero |
| `defaultTraversalCost` | Cost for cells without overrides | Finite and greater than zero |
| `worldOrigin` | Minimum X/Z corner of cell `(0, 0)` | Finite X, Y, and Z |
| `cellSize` | Square-cell world size | Finite and greater than zero |
| `connectivity` | Neighbor topology | `4` or `8` |
| `allowDiagonalCornerCutting` | Eight-way diagonal policy | Ignored with four-way connectivity |
| `fixedStepSeconds` | Simulation time represented by one tick | Finite and greater than zero |
| `maxSimulationTicks` | Exclusive tick limit | Greater than zero |
| `goalSetId` | Shared goal-set identity passed to planners | Non-empty |
| `initializationBudgetMilliseconds` | Planner initialization budget | Finite and greater than zero |
| `defaultPlanBudgetMilliseconds` | Default per-plan budget | Finite and greater than zero |
| `defaultRepairBudgetMilliseconds` | Default per-event repair budget | Finite and greater than zero |
| `agents` | Explicit agent starts and goals | At least one; unique non-negative ids |
| `initialGridOverrides` | Explicit initial blocked/weighted cells | Unique in-bounds coordinates |
| `scheduledChanges` | Explicit dynamic map events | Deterministic tick/order keys |

Traversal costs remain finite and positive even for blocked cells. Walkability and cost are separate properties, which prevents special cost sentinels from leaking into algorithm comparisons.

## Agent definition

Each agent contains:

- `agentId`: unique, non-negative integer;
- `start`: in-bounds and initially walkable grid coordinate;
- `goal`: in-bounds and initially walkable grid coordinate.

Multiple agents may share a goal. The resolved scenario deduplicates and sorts goals before planner initialization.

## Dynamic event definition

Each scheduled event contains:

- `eventId`: unique non-empty id;
- `simulationTick`: integer tick in `[0, maxSimulationTicks)`;
- `order`: non-negative tie-breaker that must be unique within a tick;
- `repairBudgetMilliseconds`: `0` to inherit the scenario default, otherwise a finite positive budget;
- `changes`: one or more unique in-bounds cell changes.

Events are applied in ascending `(simulationTick, order, eventId ordinal)` order. Changes inside an event are normalized in row-major `(y, x)` order. The runner advances by integer ticks only; no event is scheduled from `Time.time`, frame time, or wall-clock time.

## Canonical resolution and fingerprint

Resolution performs a defensive deep copy and canonical ordering:

1. agents by `agentId`;
2. unique goals by `(y, x)`;
3. initial cell overrides by `(y, x)`;
4. scheduled events by `(simulationTick, order, eventId ordinal)`;
5. changes within each event by `(y, x)`.

The normalized values are encoded with invariant culture and hashed with SHA-256. Every algorithm run for a comparison must log the same `FingerprintSha256`. A different fingerprint is a different experiment input, even if the scenario id is unchanged.

## World/grid mapping

`ResearchGridWorldTransform` maps grid X to world X and grid Y to world Z:

```text
worldCenter.x = origin.x + (grid.x + 0.5) * cellSize
worldCenter.y = origin.y
worldCenter.z = origin.z + (grid.y + 0.5) * cellSize
```

World-to-grid conversion uses floor division relative to the minimum corner. The transform is data only and is not attached to any original scene.

## Example JSON shape

```json
{
  "schemaVersion": 1,
  "scenarioId": "example-shared-goal",
  "randomSeed": 12345,
  "gridWidth": 4,
  "gridHeight": 3,
  "defaultTraversalCost": 1.0,
  "worldOrigin": { "x": 0.0, "y": 0.0, "z": 0.0 },
  "cellSize": 1.0,
  "connectivity": 4,
  "allowDiagonalCornerCutting": false,
  "fixedStepSeconds": 0.02,
  "maxSimulationTicks": 500,
  "goalSetId": "primary",
  "initializationBudgetMilliseconds": 1000.0,
  "defaultPlanBudgetMilliseconds": 16.6667,
  "defaultRepairBudgetMilliseconds": 16.6667,
  "agents": [
    {
      "agentId": 0,
      "start": { "x": 0, "y": 0 },
      "goal": { "x": 3, "y": 2 }
    }
  ],
  "initialGridOverrides": [
    {
      "coordinate": { "x": 1, "y": 1 },
      "isWalkable": false,
      "traversalCost": 1.0
    }
  ],
  "scheduledChanges": [
    {
      "eventId": "open-center",
      "simulationTick": 100,
      "order": 0,
      "repairBudgetMilliseconds": 0.0,
      "changes": [
        {
          "coordinate": { "x": 1, "y": 1 },
          "isWalkable": true,
          "traversalCost": 1.0
        }
      ]
    }
  ]
}
```

## Gate 2 exclusions

The schema does not implement scenario generation, agent movement, collision avoidance, A*-R, D* Lite, IDFF, C-FF, statistical aggregation, or scene binding. Those concerns require later gates and must consume this resolved specification rather than mutate it.
