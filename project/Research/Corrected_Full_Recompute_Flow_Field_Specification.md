# Corrected Full-Recompute Flow Field (`C-FF`) Specification

Gate: 8  
Authorization: explicitly authorized by the user on 2026-10-04  
Planned implementation: `Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs`

## 1. Experimental role

`C-FF` is the semantically corrected, shared-goal, full-recompute flow-field baseline. It builds one integration field and one deterministic next-cell field for the complete declared goal set. Every accepted grid change triggers a complete rebuild; no state from the old field is used to accelerate the new result.

Capabilities:

```text
SharedGoalField | FullRecompute
```

It is the future correctness oracle and ablation baseline for IDFF, but Gate 8 does not implement IDFF or claim incremental behavior.

## 2. Forward graph and destination-entry cost

The public path semantics are identical to A*-R and D* Lite:

- every in-bounds cell is a vertex;
- blocked vertices have no traversable incident edges;
- four-way mode exposes orthogonal moves;
- eight-way mode additionally exposes diagonal moves;
- with strict corners, a diagonal `u -> v` is legal only when both adjacent orthogonal cells are walkable;
- orthogonal `cost(u, v) = traversalCost(v)`;
- diagonal `cost(u, v) = traversalCost(v) * sqrt(2)`;
- traversal costs must be finite and strictly positive.

Because cost belongs to the destination, opposite directions can have different costs.

## 3. Reverse multi-source integration

For declared goal set `G`, the integration value is the cheapest forward cost from a cell to any currently walkable goal:

```text
I(u) = min over g in G of shortestForwardCost(u, g)
```

The field is computed with reverse multi-source Dijkstra:

1. canonicalize unique goals by row `y`, then column `x`;
2. seed every currently walkable goal with integration `0` and itself as owner;
3. when settled reverse vertex `v` is processed, enumerate every legal forward predecessor `u`;
4. relax `u` with `I(v) + cost(u, v)`.

The crucial directed-cost rule is:

```text
reverse candidate through v
    = I(v) + traversalCost(v) * movementMultiplier(u, v)
```

It must not use `traversalCost(u)`. Forward legality is evaluated exactly as it would be for `u -> v`, including strict diagonal-corner checks.

Blocked or unreachable cells have positive-infinity integration and no owner/direction. A blocked declared goal is not a source until it becomes walkable again. If every goal is blocked or unreachable, the rebuild still succeeds and produces an all-unreachable field.

## 4. Multi-source goal ownership

Each reachable cell owns exactly one selected goal. Equal-cost goals are ordered by canonical goal coordinate:

1. lowest total integration cost;
2. lowest goal row `y`;
3. lowest goal column `x`.

This ownership is part of the observable deterministic field.

The common `NavigationPlanRequest.goal` remains an agent-target assertion, not an instruction to silently choose a different source. A plan succeeds only when:

- the requested goal belongs to the declared goal set;
- the requested goal is currently walkable; and
- the field-selected owner of the request start equals the requested goal.

If the start is reachable but owned by a different goal, the request returns `InvalidRequest / InvalidRequest`. This prevents a shared field from silently routing an agent to a different scenario target. Formal cross-algorithm experiments must therefore use a shared-goal cohort or an explicitly compatible multi-source cohort. A plan request never builds a private per-goal field.

## 5. Deterministic queue order

The production reverse-Dijkstra heap order is:

1. lowest integration distance;
2. owner goal row `y`;
3. owner goal column `x`;
4. cell row `y`;
5. cell column `x`;
6. earliest insertion sequence.

Entries record a per-cell revision. Superseded entries are removed lazily. Distance equality uses a fixed absolute tolerance of `1e-12`; a strictly lower distance wins, while a tolerance-equal distance can update ownership only when the candidate goal is canonically earlier.

## 6. Direction-field construction

Direction is stored as the next grid cell rather than a normalized vector. After integration is complete, every cell is visited once in row-major order.

- blocked/unreachable cells: no direction;
- goal cells: no direction and owner is the goal itself;
- every other reachable cell selects one legal forward successor `v`.

Successor candidates are ordered by:

1. lowest `cost(u, v) + I(v)`;
2. lowest owner goal row `y`;
3. lowest owner goal column `x`;
4. lowest `I(v)`;
5. lowest successor row `y`;
6. lowest successor column `x`.

The selected total must equal `I(u)` within `1e-12`, and the selected successor owner becomes the cell owner. Positive edge costs guarantee strictly decreasing integration along a valid direction chain.

## 7. Diagnostic cell snapshot

Gate 8 exposes a read-only C-FF-specific diagnostic query for verification and future IDFF comparison. For an in-bounds cell it reports:

- walkability;
- reachability;
- whether the cell is a currently active goal;
- integration cost;
- selected owner goal when reachable;
- selected next cell when a direction exists.

This is not added to `INavigationPlanner`; it is an algorithm-specific observation API. It cannot mutate the field.

## 8. Initialization and complete rebuild

Initialization validates dimensions, all traversal costs, identities, connectivity, budgets, and declared goals. Duplicate declared goals are canonicalized. Declared goals must initially be in-bounds and walkable.

The initial field is fully built during `Initialize`. Every accepted `ApplyChanges` performs another complete build into scratch arrays. The old committed field remains untouched until the new integration and direction arrays are complete; the scratch field is then committed atomically.

No queue, distance, direction, ownership, or dirty-region state from the prior field is used to reduce rebuild work.

## 9. Change-set validation

`ExperimentRunner` mutates `ResearchNavigationGrid` before calling `ApplyChanges`. C-FF validates:

- non-empty change-set id and change array;
- finite positive repair budget;
- `previousGridVersion == planner.GridVersion`;
- `newGridVersion == previous + 1`;
- live grid version equals `newGridVersion`;
- every changed coordinate is in bounds;
- every payload walkability/cost value matches the live grid;
- traversal costs remain finite and positive.

An invalid change is rejected without advancing planner version or replacing the committed field. A valid change always rebuilds the entire field, including when the changed cell is irrelevant to every shortest path.

## 10. Budget semantics

Flow-field rebuilds are atomic and cannot expose partial arrays. The common initialization interface has no failure result, and the live grid has already advanced before repair. Therefore C-FF uses a documented atomic soft-deadline rule for full rebuilds:

- initialization and repair always finish the current full rebuild;
- the stopwatch is sampled during work and at completion;
- if it exceeds the supplied budget, metrics set `budgetExceeded = true`;
- `ApplyChanges` returns `BudgetExceeded / PlanningBudgetExceeded`, but commits the complete field and advances `GridVersion`;
- subsequent plan queries can safely use that complete field;
- no partial field is retained for continuation.

Plan-query budget is a hard deadline during validation/path extraction. A budget-exceeded plan returns an empty path and does not mutate the field.

This difference from interruptible A*-R/D* Lite must remain visible in reports. Formal fairness analysis must compare both overrun rates and completed operation costs rather than pretending all algorithms have identical interruption mechanics.

## 11. Plan extraction and classification

After identity/version/endpoint validation:

- blocked start: `NoPath / StartBlocked`;
- blocked requested goal: `NoPath / GoalBlocked`;
- unreachable start: `NoPath / NoReachablePath`;
- reachable start owned by another declared goal: `InvalidRequest / InvalidRequest`;
- otherwise follow the precomputed next-cell chain until the requested goal;
- include both start and goal in the path;
- a chain longer than the cell count, a non-decreasing integration step, or a wrong terminal owner is `Failed / InternalError`.

`start == goal` produces a one-cell path when that goal is active and requested.

Bad identity, negative agent id, undeclared goal, invalid budget, or incompatible goal ownership returns `InvalidRequest`. Outside endpoints and stale versions use the existing specific failure reasons.

## 12. Metrics

- `elapsedCpuMilliseconds`: current call stopwatch;
- `cumulativePlanningCpuMilliseconds`: cumulative initialization, rebuild, and plan-query time;
- `processedNodesOrCells`: grid validation visits, heap entries examined, reverse predecessor candidates, direction candidates, and path cells examined;
- `expandedNodes`: valid reverse-Dijkstra cells settled;
- `relaxedEdges`: reverse predecessor relaxations that change distance or canonical owner;
- `repairedCells`: on a valid dynamic rebuild, exactly `width * height`; initialization and plan queries report zero;
- `managedAllocatedBytes`: the same thread-allocation counter and `GC.GetTotalMemory(false)` fallback used by A*-R/D* Lite;
- `budgetExceeded`: whether the operation exceeded its specified budget under the rules above.

The raw counters are deterministic for fixed input except timing/allocation. C-FF `repairedCells` means complete physical field slots rebuilt and must not be interpreted as an incremental dirty-region count.

## 13. Lifecycle and reset

`Reset` discards the grid reference, committed field, goal set, queue state, identity, topology, version, and cumulative metrics. Reinitialization without `Reset` throws. Planning or repairing before initialization throws.

## 14. Independent verification contract

The Gate 8 oracle is an O(V²) reverse multi-source Dijkstra implementation with no heap. It independently:

- scans unsettled cells to choose the next `(distance, owner goal, y, x)` vertex;
- enumerates predecessors and computes directed destination-entry cost directly;
- derives every cell direction independently from the frozen ordering;
- never calls C-FF integration, heap, direction, path-extraction, or private neighbor helpers.

Production versus oracle comparisons cover every cell's reachability, integration, owner, active-goal state, direction presence, and selected next cell.

## 15. Gate 8 exclusions

Gate 8 does not implement IDFF, incremental flow-field repair, unit movement, collision avoidance, arrival detection, frame benchmarking, scene binding, or changes to original scripts/scenes. Public batch/replication support may add `C-FF` only after the algorithm and independent-oracle verification pass.
