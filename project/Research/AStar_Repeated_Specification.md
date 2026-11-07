# Repeated A* (`A*-R`) Specification

Implementation: `Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs`

Gate: 3

## Role in the experiment

`A*-R` is the per-agent full-recompute baseline. Every `Plan` request starts a new A* search and reuses no open set, closed set, predecessor tree, or shortest-path state from an earlier request. It implements `INavigationPlanner`, consumes the resolved Gate 2 grid contract, and has no scene or `MonoBehaviour` dependency.

Its capability is `FullRecompute`. It deliberately does not claim `IncrementalRepair`.

## Graph and cost model

- A grid cell is a vertex.
- Four-way connectivity exposes orthogonal neighbors only.
- Eight-way connectivity additionally exposes diagonal neighbors.
- With diagonal corner cutting disabled, a diagonal edge is legal only when both adjacent orthogonal cells are walkable.
- The start vertex has zero entry cost.
- Entering an orthogonal neighbor costs that destination cell's traversal cost.
- Entering a diagonal neighbor costs destination traversal cost multiplied by `sqrt(2)`.
- Blocked cells have no incident traversable entry edge.

All traversal costs must be finite and greater than zero. The destination-entry convention is fixed for every later reference implementation and comparison.

## Heuristic and optimality

Each request scans the current walkable grid to find its minimum traversal cost. The heuristic is:

- Manhattan distance multiplied by the minimum cost for four-way grids;
- octile distance multiplied by the minimum cost for eight-way grids.

The scan makes the heuristic admissible even when legal traversal costs are below `1`. It is included in the measured planning operation. The implementation uses a binary min-heap and permits stale heap entries; a stale entry is discarded when popped.

Deterministic priority order is:

1. lowest `f = g + h`;
2. lowest `h`;
3. lowest grid row (`y`);
4. lowest grid column (`x`);
5. earliest insertion sequence.

This fixes path selection when multiple optimal paths exist. It does not make elapsed time deterministic; time remains a measured hardware/runtime property.

## Dynamic changes

`ApplyChanges` validates and acknowledges the new grid version but performs no incremental search repair. `repairedCells` is therefore zero. After a dynamic event, the experiment harness must issue a new `Plan` for every agent that requires a new route.

For comparisons, A*-R change-handling cost consists of:

- the small `ApplyChanges` acknowledgement operation; plus
- all subsequent full-recompute `Plan` operations caused by that event.

Reporting only the acknowledgement as A*-R repair time would be invalid.

## Budgets and results

Initialization, planning, and change acknowledgement require finite positive millisecond budgets. Planning checks the wall-clock stopwatch during the minimum-cost scan and search loop. A budget overrun returns:

- status `BudgetExceeded`;
- failure reason `PlanningBudgetExceeded`;
- an empty path;
- `metrics.budgetExceeded = true`.

Expected invalid inputs return `InvalidRequest` with a categorized failure where available. Programmer/lifecycle misuse, such as planning before initialization, throws and lets `ExperimentRunner` enter `Faulted`.

## Metrics

- `elapsedCpuMilliseconds`: high-resolution elapsed time for the current planner operation. The historic field name is retained; the implementation uses `Stopwatch` elapsed time on the single experiment thread.
- `cumulativePlanningCpuMilliseconds`: monotonically accumulated elapsed planner time since initialization, including initialization, plan calls, and change acknowledgements.
- `processedNodesOrCells`: grid cells inspected by the minimum-cost scan plus valid search nodes expanded. Use `expandedNodes` when only A* expansions are required.
- `expandedNodes`: non-stale nodes removed from the open set and closed.
- `relaxedEdges`: successful lower-cost edge relaxations.
- `repairedCells`: always zero for A*-R.
- `managedAllocatedBytes`: non-negative managed allocation delta during measured algorithm work. The implementation uses `GC.GetAllocatedBytesForCurrentThread` when the Unity runtime exposes a non-zero counter; Unity 2022 Mono returned a constant zero in the end-to-end gate, so the implementation falls back to the non-collecting `GC.GetTotalMemory(false)` delta. The fallback observes real allocation but is process-wide and therefore less isolated; the measurement method must remain identical across algorithms.

## Verification boundary

The Gate 3 verification covers weighted optimal detours, no-path classification, start-equals-goal, four/eight-way topology, both corner policies, deterministic path/work counts, stale versions, invalid run identity, microscopic budget exhaustion, runner-driven dynamic changes, and 36 deterministic weighted/blocked cases checked against an independent O(V²) Dijkstra implementation.

It does not implement movement, collision avoidance, arrival detection, scenario generation, D* Lite, IDFF, C-FF, scene binding, or statistical aggregation.
