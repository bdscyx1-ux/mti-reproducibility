# D* Lite (`D*L`) Specification

Gate: 7  
Authorization: explicitly authorized by the user on 2026-10-04  
Planned implementation: `Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs`

## 1. Experimental role

`D*L` is the per-agent incremental shortest-path planner. Each agent owns a separate D* Lite state and reuses that state across versioned grid changes. It implements the same `INavigationPlanner` contract and consumes the same research grid as `A*-R`.

Capabilities:

```text
PerAgentState | IncrementalRepair
```

It is not a shared-goal field and does not claim full-recompute behavior during ordinary changes.

## 2. Graph and traversal-cost model

The graph is identical to the A*-R graph:

- every in-bounds cell is a vertex;
- blocked vertices have no traversable incident edges;
- four-way mode exposes orthogonal moves;
- eight-way mode additionally exposes diagonal moves;
- when diagonal corner cutting is disabled, a diagonal move is legal only if both adjacent orthogonal cells are walkable;
- the start vertex has zero entry cost;
- an orthogonal edge `u -> v` costs the traversal cost of destination `v`;
- a diagonal edge `u -> v` costs the traversal cost of destination `v` multiplied by `sqrt(2)`;
- traversal costs must be finite and strictly positive.

Destination-entry costs make opposite directed edges potentially have different costs. D* Lite therefore computes:

```text
rhs(u) = min over successors v of [cost(u, v) + g(v)]
```

The goal has `rhs(goal) = 0` only while the goal is walkable. All other uninitialized or unreachable values are positive infinity.

## 3. Per-agent state

The planner is initialized with the scenario's declared goal set but does not allocate a search state until an agent's first plan request. Each state contains:

- agent id;
- fixed declared goal selected by the first request;
- current and previous start;
- `g` and `rhs` arrays for every cell;
- an incremental priority queue;
- queue-revision counters for deterministic lazy deletion;
- `km`;
- deterministic insertion sequence.

The same agent id may not silently change goal. A later request for a different goal is `InvalidRequest`. Different agents with the same goal still own separate states; this keeps D*L a per-agent method and prevents accidental shared-field behavior.

## 4. Key and heuristic

For state `s`, current start `start`, and `m = min(g(s), rhs(s))`:

```text
key1 = m + h(start, s) + km
key2 = m
```

The heuristic uses Manhattan distance in four-way mode and octile distance in eight-way mode, multiplied by a fixed admissible cost scale.

At planner initialization, every cell is scanned and validated. The smallest walkable traversal cost becomes the heuristic scale. That scale is retained when costs rise or the original minimum-cost cell becomes blocked, so it remains an admissible lower bound.

If a later change introduces a walkable traversal cost below the fixed scale, keys created with the previous scale are no longer guaranteed consistent. The planner therefore performs a measured full state rebuild for every existing agent, adopts the lower scale, and then computes shortest paths normally. This fallback is part of D*L metrics and must not be hidden. Ordinary block/unblock/cost changes that do not lower the global scale use local incremental repair.

When an agent start changes:

```text
km += h(previousStart, newStart)
```

The fixed-start Gate 4 workload normally leaves `km` unchanged, but the behavior is specified and verified for future movement experiments.

## 5. Deterministic priority order

Queue order is fixed as:

1. lowest `key1`;
2. lowest `key2`;
3. lowest grid row `y`;
4. lowest grid column `x`;
5. earliest insertion sequence.

Every scheduled queue entry records the vertex's revision. `UpdateVertex` increments that revision. Entries whose recorded revision is no longer current are discarded lazily. At most one entry per vertex revision is valid.

Floating values use a fixed `1e-12` comparison tolerance for `g/rhs` consistency, algorithmic key relations, and path-cost equality decisions. The heap retains an exact deterministic total order; only the D* Lite control predicates that compare an old/top key with a recalculated/start key apply the tolerance before falling through to the second component. This prevents mathematically equal octile keys from being misclassified by floating-point summation order.

## 6. Core D* Lite operation

`UpdateVertex(u)`:

1. if `u` is the walkable goal, assign `rhs(u) = 0`;
2. otherwise recompute `rhs(u)` from current legal successors;
3. invalidate the prior queue revision;
4. if `g(u)` and `rhs(u)` differ, enqueue the current key/revision.

`ComputeShortestPath(start)` follows the standard D* Lite loop while either:

- the smallest valid queue key is less than the current start key; or
- `rhs(start)` differs from `g(start)`.

For each valid pop:

- if the old key is lower than the newly calculated key, reinsert with the new key;
- else if `g(u) > rhs(u)`, set `g(u) = rhs(u)` and update legal predecessors;
- otherwise set `g(u) = infinity`, update `u`, and update legal predecessors.

The implementation uses the current directed destination-entry edge costs. It does not reuse the A* heap or A* search loop.

## 7. Path extraction

After the start is locally consistent:

- if `g(start)` is infinity, return `NoPath / NoReachablePath`;
- otherwise repeatedly select a legal successor minimizing `cost(current, successor) + g(successor)`;
- equal candidates are ordered by lowest candidate total, then lowest `g(successor)`, row `y`, and column `x`;
- the path includes start and goal;
- positive edge costs guarantee progress; a path longer than the cell count is treated as `InternalError`.

The chosen path need not be byte-identical to A*-R when multiple optimal paths exist, but its cost must match the independent shortest-path oracle.

## 8. Dynamic grid changes

`ExperimentRunner` mutates `ResearchNavigationGrid` before calling `ApplyChanges`. The planner validates:

- non-empty change-set id and changes;
- positive finite repair budget;
- `previousGridVersion == planner.GridVersion`;
- `newGridVersion == previous + 1`;
- live grid version equals the new version;
- all changed coordinates are in bounds and match the live grid values.

For each changed cell, the locally affected update seed is every cell in its clipped 3×3 neighborhood. This covers:

- the changed vertex;
- vertices whose incoming edge to the changed destination changed cost/walkability;
- diagonal edges whose strict-corner legality depends on the changed cell.

Each existing agent state calls `UpdateVertex` on the canonical row-major affected set, then repairs from that state's current start. Multiple changes in one `NavigationChangeSet` are treated as one atomic version update.

## 9. Budget semantics and recoverability

Initialization, plan, and repair budgets must be finite and positive.

- Bookkeeping required to place all affected vertices into a consistent queued state is completed before a repair-budget result is returned.
- `ComputeShortestPath` checks the shared operation stopwatch and may stop with `BudgetExceeded`.
- A budget-exceeded repair still advances the planner grid version because its pending queue is a valid continuation state for the already-applied grid version.
- A later `Plan` continues the pending repair under its own budget.
- A budget-exceeded `Plan` returns an empty path and preserves the incremental state for a later request.
- Programmer/lifecycle misuse still throws and faults `ExperimentRunner`; expected invalid inputs return categorized results.

## 10. Result classification

Expected classifications match A*-R where applicable:

- bad identity, goal switch, negative agent id, bad budget: `InvalidRequest`;
- stale grid version: `InvalidRequest / StaleGridVersion`;
- start outside: `InvalidRequest / StartOutsideGrid`;
- goal outside: `InvalidRequest / GoalOutsideGrid`;
- blocked start: `NoPath / StartBlocked`;
- blocked goal: `NoPath / GoalBlocked`;
- unreachable: `NoPath / NoReachablePath`;
- exhausted operation budget: `BudgetExceeded / PlanningBudgetExceeded`;
- corrupted/inconsistent path state: `Failed / InternalError`.

## 11. Metrics

- `elapsedCpuMilliseconds`: `Stopwatch` elapsed time for the current call;
- `cumulativePlanningCpuMilliseconds`: cumulative initialization, plan, and repair time;
- `processedNodesOrCells`: validated/scanned cells, queue entries examined, and vertices whose rhs/path successor is evaluated;
- `expandedNodes`: valid D* Lite queue pops that execute a state transition;
- `relaxedEdges`: successor/predecessor candidate evaluations that improve a recomputed rhs;
- `repairedCells`: per-agent vertex updates seeded or propagated during `ApplyChanges`; the same physical cell repaired in two agent states counts twice;
- `managedAllocatedBytes`: same thread-allocation counter with the same `GC.GetTotalMemory(false)` fallback used by A*-R;
- `budgetExceeded`: true only when the operation stopwatch exceeds its supplied budget.

Raw totals remain available. Cross-algorithm reports must not claim that D*L `repairedCells` and future flow-field `repairedCells` have identical semantics without qualification.

## 12. Reset and lifecycle

`Reset` discards every per-agent state, queue, grid reference, identity, heuristic scale, version, and cumulative metric. Reinitialization without `Reset` throws. Planning or repairing before initialization throws.

## 13. Independent verification plan

Gate 7 verification must include:

1. static weighted and blocked maps checked against an independent O(V²) Dijkstra oracle;
2. deterministic generated cases for four-way, eight-way strict, and eight-way permissive topology;
3. block, unblock, cost increase, cost decrease, and mixed atomic changes;
4. a cost decrease below the heuristic scale that triggers measured full state rebuild;
5. strict-corner changes where toggling an orthogonal cell changes diagonal legality;
6. no-path, blocked endpoints, and start=goal;
7. same-agent goal-switch rejection and independent state for different agents;
8. moved-start `km` behavior checked through optimal path results;
9. stale version and malformed request rejection;
10. microscopic plan and repair budgets, followed by successful continuation;
11. `ExperimentRunner` and `DeterministicPlanningWorkloadRunner` integration;
12. repeated identical sequences producing identical paths, statuses, versions, and deterministic work counts;
13. full A*-R and Gates 2–6 regression;
14. frozen baseline and unauthorized IDFF/C-FF implementation audit.

The independent oracle may share only the public graph/cost specification. It must not reuse D*L queue, keys, `g/rhs`, repair code, or path extraction.

## 14. Gate 7 exclusions

Gate 7 does not implement C-FF, IDFF, movement, collision avoidance, arrival detection, frame benchmarking, scene binding, or changes to original scripts/scenes. Batch and replication support may be extended from `A*-R` to `D*L` only after algorithm verification passes.
