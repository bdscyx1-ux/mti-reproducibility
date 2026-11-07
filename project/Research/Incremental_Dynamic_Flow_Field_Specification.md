# Incremental Dynamic Flow Field (IDFF) Specification

Status: frozen before production implementation  
Gate: 9  
Date: 2026-10-05 (Asia/Shanghai)

## 1. Scope

`IDFF` is the shared-goal incremental counterpart to the Gate 8 corrected full-recompute flow field (`C-FF`). It maintains a reverse multi-source shortest-path field across grid changes and incrementally repairs integration, canonical goal ownership, and directions.

The Gate 9 implementation is research-only and scene-independent. It must not modify or bind to an original script or original scene. It participates only in the fixed-start planning microbenchmark until a later movement experiment is separately authorized.

Every externally visible completed IDFF field must equal a freshly initialized C-FF field built from the same live grid, goal set, connectivity, and corner policy. This is the primary Gate 9 correctness invariant.

## 2. Shared state ownership

One initialized planner owns exactly one shared field consisting of:

- the `IReadOnlyNavigationGrid` reference;
- immutable run id and goal-set id;
- immutable canonical declared goal set;
- immutable four-way/eight-way connectivity and diagonal-corner policy;
- a committed grid version;
- per-cell incremental integration state (`g` and `rhs`);
- per-cell canonical owner-goal state paired with `g` and `rhs`;
- per-cell active-goal state;
- per-cell direction presence and canonical next coordinate;
- one deterministic global inconsistency queue;
- optional pending-repair state for the currently accepted change set.

The field is shared by all agents. Agent ids do not create planner state. A plan request is a read/query operation against the shared field.

The planner capabilities are exactly:

```text
SharedGoalField | IncrementalRepair
```

## 3. Immutable goal-set contract and invalidation

Initialization requires at least one declared goal. Goals are deduplicated and sorted by canonical coordinate order `(y, x)`. Every declared goal must be inside the grid and walkable at initialization.

The declared goal set, `goalSetId`, connectivity, and corner policy are immutable until `Reset`. There is no in-place goal-set mutation API. A different goal set or goal-set id requires:

1. `Reset`;
2. a new `Initialize` call;
3. construction of a new IDFF state.

A plan request with a different goal-set id, an undeclared goal, or a goal that does not own the start cell is `InvalidRequest`.

A grid change may block or restore a declared goal without changing the declared set:

- a walkable declared goal is active and has rhs value `(0, itself)`;
- a blocked declared goal is inactive and has no zero source;
- restoring it reactivates the same canonical source through ordinary incremental repair.

## 4. Graph and directed edge cost

IDFF uses exactly the C-FF graph:

- each walkable cell is a vertex;
- four-way or eight-way neighbors are selected by the initialization contract;
- strict diagonal mode requires both orthogonal side cells to be walkable;
- permissive diagonal mode does not require those side cells;
- blocked endpoints never form an edge.

For a legal forward move `u -> v`:

```text
cost(u, v) = traversalCost(v) × movementMultiplier(u, v)
```

where the multiplier is `1` for an orthogonal move and `sqrt(2)` for a diagonal move. The cost belongs to the destination cell. Reverse propagation through `v` therefore adds `cost(u, v)` and never charges the predecessor's traversal cost.

## 5. Canonical value and ownership ordering

Each finite incremental value is a pair:

```text
(integrationCost, ownerGoal)
```

Pairs are ordered by:

1. smaller integration cost, using the shared `1e-12` comparison tolerance;
2. for equal cost, earlier canonical owner goal `(y, x)`.

Infinity has no owner and is later than every finite pair. Two values are consistent only when their costs are equal under the tolerance and their owner-presence/owner-goal values are equal.

This makes equal-cost multi-source ownership deterministic and identical to C-FF.

## 6. Incremental `g/rhs` invariant

For active goal `s`:

```text
rhs(s) = (0, s)
```

For a blocked cell or inactive goal with no legal successor:

```text
rhs(u) = infinity, no owner
```

For every other walkable cell:

```text
rhs(u) = min over legal successors v of
         (cost(u, v) + gCost(v), gOwner(v))
```

using the pair ordering above.

A cell is locally consistent when `g(u) == rhs(u)` including owner. A completed field requires every cell to be locally consistent and the inconsistency queue to be empty. The completed `g` pair is the externally visible integration/owner value.

## 7. Deterministic inconsistency queue

Every queued entry contains the cell index, coordinate, current queue revision, insertion sequence, and the lexicographically smaller of its `g` and `rhs` pairs.

Queue order is:

1. key integration cost;
2. key owner goal `(y, x)`;
3. cell coordinate `(y, x)`;
4. insertion sequence.

Per-cell revisions implement lazy deletion. A queue entry is valid only if its revision is current and the cell remains inconsistent.

For a valid popped cell `u`:

- if `rhs(u)` is earlier than `g(u)`, assign `g(u) = rhs(u)` and update every possible predecessor;
- otherwise assign `g(u) = infinity`, recompute/schedule `u`, and update every possible predecessor.

The process continues until the queue is empty or a hard repair/query budget interrupts it.

## 8. Change seeding and propagation

An accepted `NavigationChangeSet` must:

- have a non-empty id and non-empty change array;
- advance exactly from `GridVersion` to `GridVersion + 1`;
- match the live grid version;
- contain unique, in-grid coordinates;
- contain finite positive traversal costs;
- exactly match the live grid's post-change walkability and traversal costs.

Validation completes before incremental state is changed.

For every changed coordinate, IDFF seeds the clipped 3×3 neighborhood. This conservative seed covers:

- the changed vertex's own rhs;
- destination-entry cost changes for adjacent predecessors;
- new or removed edges caused by block/unblock;
- strict-corner diagonal legality that depends on an orthogonal side cell;
- declared-goal activation/deactivation.

Seed vertices are visited in row-major index order. Propagation then follows deterministic queue order. Every change set is one atomic state transition even when it contains multiple cells.

## 9. Same-tick event semantics

Gate 4 already freezes the workload rule:

- events sharing a simulation tick are ordered canonically;
- the grid and planner receive one atomic `NavigationChangeSet` per scheduled event;
- no agent plan occurs between those same-tick events;
- agents are replanned once after the entire same-tick group.

Gate 9 preserves that rule to avoid changing prior evidence. IDFF must complete or explicitly remain pending for each accepted event; a different change set must not be silently merged into a pending repair. Thus the same-tick group is observationally atomic to agents while every constituent change set remains separately logged and auditable.

A multi-cell change inside one event is validated and seeded as one atomic batch; input order cannot affect the result.

## 10. Incremental direction refresh

Directions are derived from the completed integration/owner field. IDFF does not rescan all cells after every change.

A cell enters the direction-dirty set when:

- it is in the clipped 3×3 neighborhood of an input change;
- its `g` cost or owner changes;
- it is a geometric predecessor/neighbor of a cell whose `g` cost or owner changes;
- its active-goal state changes.

The set is unique and is refreshed in row-major cell-index order only after the integration queue is empty.

For each dirty walkable, reachable, non-goal cell, candidate successors must be legal and satisfy:

```text
cost(current, successor) + gCost(successor) == gCost(current)
```

The direction tie-break is identical to C-FF:

1. smaller total cost;
2. earlier owner goal `(y, x)`;
3. smaller successor remaining integration;
4. earlier successor coordinate `(y, x)`.

The chosen successor owner must equal the current cell owner. Blocked, unreachable, and active-goal cells have no direction.

The repair is complete only after all direction-dirty cells have been refreshed.

## 11. Budget and interruption consistency

### 11.1 Initialization budget

Initialization has no older field to preserve. Like C-FF initialization, it is an atomic soft deadline:

- initialization always reaches a complete, queryable field;
- an elapsed budget overrun sets `metrics.budgetExceeded = true`;
- the complete field is still committed.

### 11.2 Repair budget

Repair uses a hard, resumable deadline:

- after full validation, the planner advances `GridVersion` to the live grid's new version and records the pending change-set identity;
- integration propagation and direction refresh stop only at deterministic safe boundaries;
- if the deadline expires before both phases finish, `ApplyChanges` returns `BudgetExceeded` and retains resumable pending state;
- no partial field may be exposed as a completed snapshot or used for path extraction;
- retrying `ApplyChanges` with the exact same change set resumes the pending repair;
- a valid `Plan` request may also spend its plan budget resuming the pending repair before extracting a path;
- if that plan budget expires first, the plan returns an empty `BudgetExceeded` result and the pending repair remains resumable;
- a different/new change set while repair is pending is rejected rather than merged or allowed to corrupt state.

`GridVersion` remains aligned with the already mutated research grid throughout pending repair, satisfying the runner's version invariant. Queryability, not version, distinguishes pending from committed field state.

### 11.3 Plan budget

After any pending repair is completed, the remaining plan budget is a hard deadline for validation/path extraction. Budget-exceeded plans return an empty path and do not modify the completed field.

## 12. Snapshot and plan semantics

IDFF exposes an algorithm-specific read-only cell snapshot with the same semantic fields as C-FF:

- walkable;
- reachable;
- active goal;
- integration cost;
- owner presence and owner goal;
- direction presence and next coordinate.

Snapshots are available only for in-grid cells while no repair is pending. A valid in-grid snapshot request during pending repair throws `InvalidOperationException`; returning a partial field is forbidden.

Plan validation and path behavior match C-FF:

- identity, budget, agent id, version, endpoints, declaration, and walkability are checked;
- an unreachable start returns `NoPath / NoReachablePath`;
- a blocked requested goal returns `NoPath / GoalBlocked`;
- a start owned by another declared goal returns `InvalidRequest` rather than silently routing elsewhere;
- a start equal to its active requested goal returns a one-cell path;
- every direction step must be legal and strictly reduce integration;
- completed paths terminate at the requested owner goal.

## 13. Metrics

All metrics are per public operation and use the common `NavigationOperationMetrics` object.

- `elapsedCpuMilliseconds`: stopwatch time spent in the operation, including resumed repair work performed by a plan;
- `cumulativePlanningCpuMilliseconds`: monotonic total over initialization, repair, resumed repair, and plan operations;
- `processedNodesOrCells`: deterministic count of validated change cells, queue/stale entries, rhs cells/candidates, direction cells/candidates, and path cells processed;
- `expandedNodes`: valid inconsistent vertices popped and executed by the incremental queue;
- `relaxedEdges`: legal successor candidates that replace the current best rhs pair during recomputation;
- `repairedCells`: unique physical cell indices first touched for integration/goal/direction repair within one accepted change set, counted once across all interrupted/resumed operations for that change set;
- `managedAllocatedBytes`: the same diagnostic thread-allocation counter and `GC.GetTotalMemory(false)` fallback used by A*-R, D* Lite, and C-FF;
- `budgetExceeded`: whether the public operation stopped or reported overrun under the budget rules above.

Initialization and ordinary completed-field plan queries report zero repaired cells. Work counters are deterministic for fixed input except timing/allocation. IDFF `repairedCells` is an incremental repair-footprint metric and must not be interpreted as identical to C-FF's full-field physical-slot count.

## 14. Failure and lifecycle rules

- `Plan`, `ApplyChanges`, and snapshot access before initialization throw `InvalidOperationException`.
- Reinitialization without `Reset` throws.
- Invalid requests return categorized `InvalidRequest` results and do not mutate a completed field.
- Stale change versions return `InvalidRequest / StaleGridVersion`.
- Invalid live payloads return `InvalidRequest` without seeding repair state.
- `Reset` discards the field, queue, pending repair, ids, goals, metrics accumulation, and grid version.
- No planner exception may be converted into a successful result.

## 15. Gate 9 oracle and acceptance invariant

After initialization and after every completed dynamic event:

1. create a new C-FF planner;
2. initialize it from the current live grid with the same declared goals and topology;
3. compare every cell's walkability, active-goal flag, reachability, finite integration cost, owner, direction presence, and next coordinate;
4. compare selected compatible plan status, legality, terminal goal, and path cost;
5. reject any mismatch.

The fresh C-FF instance must never reuse IDFF arrays, queue entries, dirty sets, or helpers. Gate 8's independent O(V²) oracle already establishes C-FF as the full-recompute semantic reference.

Gate 9 cannot pass if any field mismatch, partial-field exposure, non-deterministic work count, stale-version acceptance, goal-set mutation, regression, baseline mismatch, or original-file modification is observed.
