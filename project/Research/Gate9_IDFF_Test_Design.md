# Gate 9 IDFF Verification Design

Status: frozen before production implementation  
Date: 2026-10-05 (Asia/Shanghai)

## Test order

1. Freeze `Research/Incremental_Dynamic_Flow_Field_Specification.md` and this test design.
2. Build Gate 9 comparison helpers around a newly initialized C-FF instance for every initial/dynamic comparison point.
3. Implement lifecycle, budget-interruption, same-tick, and deterministic-sequence tests before public algorithm authorization.
4. Implement `IncrementalDynamicFlowFieldPlanner` without changing the frozen tests to accommodate implementation details.
5. Compile and run in real headless Unity.
6. Only after the algorithm gate passes, add `IDFF` to the public batch/replication whitelist and retain new evidence.

## A. Static semantic equivalence

For fixed four-way, eight-way strict, and eight-way permissive grids, compare IDFF with a fresh C-FF over every cell:

- walkability;
- active-goal state;
- reachability;
- integration cost within `1e-9`;
- owner presence and canonical owner goal;
- direction presence and exact next coordinate.

Include:

- destination-entry cost asymmetry;
- one, two, and three declared goals;
- equal-cost canonical owner ties;
- equal-direction ties;
- weighted orthogonal and diagonal paths;
- unreachable regions and blocked cells;
- start equals active goal;
- compatible and incompatible requested owners.

Require IDFF capabilities to be exactly `SharedGoalField | IncrementalRepair`.

## B. Dynamic fresh-C-FF oracle matrix

Use deterministic seeded maps spanning:

- four-way topology;
- eight-way strict topology;
- eight-way permissive topology;
- one, two, and three goals;
- weighted and blocked cells.

For every map, apply a deterministic sequence containing:

- block;
- unblock;
- cost increase;
- cost decrease;
- active-goal block and restore where applicable;
- a multi-cell atomic change;
- a strict-corner side-cell change;
- a remote/irrelevant change.

After every completed change, create a brand-new C-FF planner on the current grid and compare every cell. No C-FF instance is reused across events.

Minimum acceptance target:

- at least 24 initial fresh-C-FF fields;
- at least 96 post-change fresh-C-FF fields;
- at least 3,000 all-cell dynamic comparisons.

## C. Incremental propagation and direction footprint

Verify specifically that:

- changed cells are seeded as a canonical atomic set independent of input order;
- destination-entry cost increases and decreases propagate in the correct reverse direction;
- block/unblock can both invalidate and restore distant cells;
- owner-only changes propagate even when integration costs remain tied;
- strict-corner legality changes seed all necessary local dependencies;
- direction changes propagate to predecessors of integration-changed cells;
- a selected local/irrelevant change repairs fewer than `width × height` unique cells;
- `repairedCells` is deterministic and counts unique physical cells across interrupted/resumed work;
- a completed field has no pending repair and exposes snapshots for every in-grid cell.

The verifier must not require every dynamic change to touch fewer than all cells; global shortest-path effects may legitimately propagate through the entire field.

## D. Same-tick and atomic change behavior

Direct planner tests:

- apply the same multi-cell change in different input orders through separately constructed grids and require identical normalized change sets, fields, work counts, and paths;
- include multiple cells whose effects interact within one change set;
- compare the completed result to one fresh C-FF built only after the whole atomic change.

Runner tests:

- use at least two canonically ordered events at the same simulation tick;
- require one repair record per event and one post-group plan phase per agent;
- confirm there is no plan between same-tick events;
- require the final IDFF field to equal fresh C-FF after the group.

## E. Budget interruption and recovery

On a sufficiently large deterministic grid:

- microscopic initialization budget must complete a valid field and report a soft overrun;
- microscopic repair budget must return `BudgetExceeded`, advance planner version to the live grid version, and leave `RepairPending == true`;
- in-grid snapshot access while pending must throw rather than expose a partial field;
- a tiny plan budget while pending must return an empty `BudgetExceeded` result and preserve resumable state;
- retrying the exact same change set with a large budget must complete repair;
- retrying with a mismatched change-set identity/payload must be rejected;
- after completion, `RepairPending == false` and every cell must equal a newly initialized C-FF field;
- a later compatible plan must succeed;
- no completed snapshot from the previous grid version may be reported as current while repair is pending.

## F. Goal-set invalidation and lifecycle

Verify:

- initialization rejects no goals, outside goals, blocked initial goals, malformed ids, invalid budgets, and unsupported topology;
- duplicate goals canonicalize deterministically;
- wrong run id, goal-set id, undeclared requested goal, incompatible owner goal, stale plan version, and malformed agent/budget are rejected;
- a same-planner goal-set change is impossible through plan or change-set input;
- `Reset + Initialize` is required and sufficient for a new goal set;
- blocking/restoring a declared goal changes only its active status, not declaration identity;
- plan, repair, and snapshot before initialization throw;
- reinitialize before reset throws;
- reset clears pending repair and grid version.

## G. Determinism

Run identical initial maps and change sequences at least twice and compare:

- complete per-event field signatures;
- plan paths and statuses;
- queue-derived deterministic work counters;
- unique repaired-cell totals;
- final grid version;
- pending/completed transitions.

Exclude timing and managed allocation from the deterministic signature.

## H. Workload and committed-scenario integration

Run:

- a compact custom shared/multi-goal workload with same-tick events;
- `Research/Scenarios/dynamic_corridors_sparse_v1.scenario.json` through `DeterministicPlanningWorkloadRunner`.

Require successful fixed-start plan counts, expected repair counts, no invalid/failed outcomes, correct final version, and deterministic native work totals. Compare the final IDFF planner field with a fresh C-FF where the direct verifier owns the planner instance.

## I. Public pipeline and regression

Only after A–H pass:

- add `IDFF` to `ResearchPlanningBatchCommand`;
- add `IDFF` to `Run-PlanningWorkload.ps1` and `Run-PlanningReplication.ps1`;
- retain one final IDFF single-run fixture;
- retain one three-process IDFF replication fixture;
- reaggregate the retained child results with current compiled code and require byte-identical aggregate output;
- verify hash integrity, JSONL identity/order/counts, no-overwrite behavior, and exact four-algorithm authorization;
- replace the negative unauthorized-algorithm test with a guaranteed unsupported sentinel rather than a future algorithm id;
- run Gates 2–9 regression;
- check all 24 frozen baseline entries;
- parse every PowerShell, JSON, and JSONL artifact;
- require zero Unity processes and no lockfile at final audit.

## Pass rule

Any completed-field difference from a freshly initialized C-FF, partial snapshot exposure, illegal direction, owner mismatch, non-deterministic work count, invalid pending-repair transition, silent goal-set mutation, same-tick planning leak, regression failure, baseline mismatch, evidence-hash mismatch, or original-file modification blocks Gate 9 completion.
