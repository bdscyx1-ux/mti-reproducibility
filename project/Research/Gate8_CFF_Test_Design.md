# Gate 8 C-FF Verification Design

Status: frozen before production implementation  
Date: 2026-10-04 (Asia/Shanghai)

## Test order

1. Implement the independent O(V²) reverse multi-source Dijkstra oracle in the Gate 8 Editor verifier.
2. Implement all-cell comparison helpers and fixed expected cases without calling production search helpers.
3. Implement `CorrectedFullRecomputeFlowFieldPlanner`.
4. Compile in real headless Unity and run the complete verifier.
5. Only after the algorithm gate passes, add `C-FF` to public batch/replication selection and retain new evidence.

## Required groups

### A. Fixed semantic cases

- weighted destination-entry asymmetry that would fail if reverse relaxation used predecessor cost;
- canonical equal-cost multi-goal ownership by goal `(y,x)`;
- deterministic direction tie by owner, remaining integration, and successor `(y,x)`;
- start equals active goal;
- incompatible requested goal is rejected rather than silently redirected;
- blocked start, blocked requested goal, unreachable start, outside endpoints, undeclared goal, malformed identity, bad budget, and stale version;
- initialization before/after reset and lifecycle misuse.

### B. Topology cases

- four-way;
- eight-way with strict corners;
- eight-way with permissive corners;
- weighted orthogonal and diagonal paths;
- blocked and unreachable regions.

### C. Full-recompute dynamics

- block and unblock;
- cost increase and decrease;
- active goal blocked and restored;
- multiple cells changed atomically;
- strict-corner legality changed by an orthogonal cell;
- irrelevant change still reports exactly `width * height` repaired cells;
- every post-change field equals a fresh independent oracle field;
- rebuild counters are deterministic across identical sequences.

### D. Budget behavior

- microscopic initialization budget completes an atomic field and reports overrun;
- microscopic repair budget returns `BudgetExceeded`, commits a complete oracle-equal field, and advances version;
- a later plan succeeds from the committed field;
- microscopic plan budget returns an empty budget-exceeded result without changing the field.

### E. Generated independent comparisons

Use fixed seeded maps for:

- four-way topology;
- eight-way strict topology;
- eight-way permissive topology;
- one, two, and three goals;
- weighted and blocked cells.

For each initial map and every deterministic change step, compare all cells:

- walkable flag;
- active goal flag;
- reachable flag;
- integration within `1e-9` for finite values;
- owner goal;
- direction presence;
- next coordinate.

Also plan from selected compatible starts and compare path terminal goal, legality, and total cost with oracle integration.

Minimum acceptance target: at least 24 initial fields and 72 post-change fields, matching the strength of the Gate 7 dynamic oracle matrix.

### F. Integration and regression

- `ExperimentRunner` lifecycle;
- `DeterministicPlanningWorkloadRunner` on a C-FF-compatible shared/multi-source scenario;
- public batch selector only after A–E pass;
- Gates 2–7 full regression;
- 24-entry frozen baseline audit;
- exact algorithm-scope audit confirming IDFF remains absent;
- no Unity process or lockfile at exit.

## Pass rule

Any all-cell mismatch, wrong directed cost, wrong goal owner, wrong direction, non-deterministic work count, partial field after budget overrun, stale-version acceptance, regression failure, baseline mismatch, or unauthorized IDFF implementation blocks Gate 8 completion.
