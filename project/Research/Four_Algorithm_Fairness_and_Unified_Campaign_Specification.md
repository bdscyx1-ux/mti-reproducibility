# Four-Algorithm Fairness and Unified Campaign Specification

Gate: 10  
Specification id: `four-algorithm-fairness-v1`  
Status: frozen before Gate 10 production implementation  
Frozen: 2026-10-05 (Asia/Shanghai)

## 1. Scope

This specification defines the comparison boundary shared by `A*-R`, `D*L`, `C-FF`, and `IDFF`. It does not authorize a formal performance campaign, a final scenario matrix, movement simulation, arrival-time claims, scene modification, or changes to frozen original scripts.

Gate 10 delivers:

1. explicit comparison cohorts;
2. exact algorithm/specification/implementation provenance;
3. a backward-compatible fairness extension to the fixed-start workload result;
4. frozen dynamic-cost and metric accounting;
5. a deterministic balanced cross-algorithm dispatcher in which every sample is a new Unity process;
6. strict rejection of mixed identities;
7. pipeline-scale verification only.

Gate 11 freezes the formal scenario matrix and preregistration. Gate 12 freezes pilot-derived sample size. Gate 13 alone may execute the formal campaign.

## 2. Algorithm identities

The only authorized algorithm profiles are:

| Algorithm id | Specification id | Specification file | Implementation file | State model |
|---|---|---|---|---|
| `A*-R` | `a-star-repeated-v1` | `Research/AStar_Repeated_Specification.md` | `Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs` | stateless per request |
| `D*L` | `d-star-lite-v1` | `Research/DStar_Lite_Specification.md` | `Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs` | persistent per-agent state |
| `C-FF` | `corrected-full-recompute-flow-field-v1` | `Research/Corrected_Full_Recompute_Flow_Field_Specification.md` | `Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs` | one shared multi-source field |
| `IDFF` | `incremental-dynamic-flow-field-v1` | `Research/Incremental_Dynamic_Flow_Field_Specification.md` | `Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs` | one shared incremental multi-source field |

Every new batch result and manifest records the specification id and SHA-256, implementation SHA-256, fairness protocol id and SHA-256, and fixed-start workload-contract SHA-256. Paths are recorded relative to the project root. Missing, malformed, or mismatched provenance makes a run ineligible for Gate 10 comparison.

## 3. Goal cohorts

Goal coordinates are deduplicated after deterministic scenario resolution.

### 3.1 `four-algorithm-shared-goal-v1`

- Exactly one distinct goal coordinate is declared by all agents.
- Authorized algorithms: `A*-R`, `D*L`, `C-FF`, `IDFF`.
- All four algorithms are directly comparable under the same canonical scenario, budgets, event sequence, and fixed-start queries.
- `C-FF` and `IDFF` each use exactly one shared field.
- `D*L` owns one persistent state instance per agent.
- `A*-R` owns no persistent state.

This is the only Gate 10 cohort that permits a four-algorithm comparison.

### 3.2 `per-agent-heterogeneous-goal-v1`

- More than one distinct agent goal is present.
- Authorized algorithms: `A*-R`, `D*L` only.
- Each query retains its declared agent goal.
- Results cannot be merged with either flow-field cohort.

### 3.3 `grouped-field-heterogeneous-goal-v1`

- More than one distinct agent goal is present.
- Authorized algorithms: `C-FF`, `IDFF` only.
- One explicit multi-source field contains the complete canonical goal set.
- `sharedFieldInstanceCount` must be one and the distinct-goal count must be recorded.
- Results cannot be presented as a direct per-agent comparison and cannot be merged with `per-agent-heterogeneous-goal-v1`.

An algorithm/cohort mismatch is rejected before a campaign output directory is populated. A heterogeneous four-algorithm campaign is invalid in Gate 10.

## 4. Fixed-start workload and budget equality

Every comparison sample uses the same byte-identical canonical scenario and therefore the same:

- grid, traversal costs, connectivity, and corner policy;
- agent starts and goals;
- event ids, ticks, order, and changes;
- initialization budget;
- default plan budget;
- effective repair budget for every event.

No algorithm-specific budget multiplier or hidden warm-up operation is permitted. Budget semantics remain algorithm-native and visible: a soft atomic deadline and a hard resumable deadline are not reinterpreted as identical behavior. Budget overruns and failures remain in the recorded outcome rates and cannot be discarded.

Every sample is a cold, independent Unity Editor process. The workload does not simulate motion; every initial and post-event plan uses the scenario-declared start.

## 5. Dynamic-cost boundary

For a tick containing one or more events:

```text
dynamic phase elapsed
  = sum(all ApplyChanges operations at that tick)
  + sum(all fixed-start plan queries after the complete same-tick event group)
```

The same inclusion boundary applies to deterministic work and managed allocation.

- `A*-R`: change acknowledgement plus all required full replans.
- `D*L`: all per-agent repairs plus all post-event queries.
- `C-FF`: complete field rebuilds plus all post-event queries.
- `IDFF`: incremental consistency repairs, dirty direction refresh, any plan-triggered completion, and all post-event queries.

Reporting only acknowledgement, queue work, field repair, or query work is not a valid dynamic comparison. Initialization and the initial pre-event query phase remain separately recorded.

## 6. Fairness result extension

The existing workload schema remains readable for Gates 4–9. Gate 10 adds an explicit `fairnessSchemaVersion = 1` extension. Legacy retained results have version zero after deserialization and remain valid only for their historical single-algorithm audits; they are not Gate 10 campaign inputs.

Every Gate 10 result records:

- fairness, algorithm-specification, implementation, and workload provenance;
- `goalCohortId` and `comparisonCohortId`;
- distinct goal count;
- planner, persistent-state, and shared-field instance counts;
- state-model id and processed-work unit (`nodes` or `cells`);
- whether dynamic accounting includes every repair and post-event plan;
- initialization work;
- initial-query elapsed/work totals;
- dynamic-phase elapsed/work totals;
- total elapsed/work per agent;
- dynamic elapsed/work per scheduled event;
- raw algorithm-native totals already present in the workload result.

All normalized values use explicit denominators. If the scheduled-event count is zero, per-event normalized values are zero and must not be interpreted as observed dynamic performance.

## 7. Metric semantics

### 7.1 Common metrics

The common comparison surface is:

- initialization elapsed time;
- initial-query elapsed time;
- dynamic-handling total and p95 elapsed time;
- total planner elapsed time;
- processed nodes/cells, with `processedWorkUnit` retained;
- managed allocated bytes;
- plan success rate;
- budget-overrun rate;
- categorized failures;
- per-agent total elapsed/work;
- per-event dynamic elapsed/work.

`processedNodesOrCells` is a common accounting slot, not proof that a node and a cell have identical computational cost. The unit label must remain present in analysis tables.

### 7.2 Algorithm-native metrics

`expandedNodes`, `relaxedEdges`, and `repairedCells` remain raw native counters. They may be reported within an algorithm or as explicitly labelled diagnostic counters, but they must not be pooled into a single cross-algorithm scalar or substituted for common elapsed/work metrics.

The algorithm profile fixes the native semantics identifier. A missing or changed semantics id invalidates comparison provenance.

Timing and managed allocation are runtime observations and need independent-process repetition. Deterministic work counts are structural evidence, not a replacement for timing samples.

## 8. Balanced execution order

The canonical algorithm order for the four-algorithm cohort is:

```text
A*-R, D*L, C-FF, IDFF
```

Gate 10 uses the even-order Williams design. For four algorithms, one complete cycle is:

```text
block 1: A*-R, D*L, IDFF, C-FF
block 2: D*L, C-FF, A*-R, IDFF
block 3: C-FF, IDFF, D*L, A*-R
block 4: IDFF, A*-R, C-FF, D*L
```

Within one complete cycle:

- every algorithm occurs once in every position;
- every ordered pair of distinct algorithms occurs exactly once as an immediate predecessor relationship;
- each block contains exactly one sample of every authorized cohort algorithm.

Two-algorithm heterogeneous cohorts use the analogous two-row design. A campaign block count must be a positive multiple of its algorithm count; incomplete balance cycles are rejected.

Every schedule entry invokes `Run-PlanningWorkload.ps1` separately. One Unity process may produce only one algorithm sample. Algorithms cannot share a managed heap, static planner state, or Editor process.

## 9. Campaign identity and outputs

A Gate 10 campaign is a dispatcher/validation artifact, not a mixed replication aggregate. Its manifest records:

- campaign id and comparison cohort;
- scenario source SHA-256, semantic fingerprint, and canonical SHA-256;
- fairness protocol id/SHA-256;
- algorithm order and complete balance-cycle count;
- every block/position/algorithm/run id;
- child manifest and workload-result hashes;
- child provenance and structural counts;
- position and predecessor-balance verification;
- completion state.

Statistical aggregation remains homogeneous: one algorithm, one scenario fingerprint/source hash, one fairness protocol, one specification id/hash, one implementation hash, and one comparison cohort per replication aggregate. A campaign may reference several homogeneous aggregates later, but no aggregate may contain mixed algorithms.

Output directories are create-new. Partial failures are retained; retry uses a new campaign id/directory.

## 10. Eligibility and interpretation

A result is eligible for comparison only when:

1. the algorithm is authorized for its declared cohort;
2. provenance hashes are valid and identical within its homogeneous group;
3. scenario source/fingerprint and structural counts match the comparison plan;
4. budgets come from the same canonical scenario;
5. dynamic accounting is complete;
6. fixed-start semantics are true;
7. no child artifact hash, JSONL sequence, or completion check fails;
8. the execution order forms complete Williams cycles.

Gate 10 verification fixtures prove contract enforcement and pipeline operation. They do not establish performance superiority. No inferential comparison, scenario selection, or publication claim is authorized until Gates 11–13.

## 11. Preservation boundary

- Do not modify any original script or original scene.
- Do not attach research components to original scenes.
- Keep all Gate 5–9 retained fixtures byte-identical.
- Keep the 24-entry frozen baseline at zero mismatches.
- Use only research-only scenario files and headless Unity execution.
- Stop and checkpoint before the active usage window reaches the user's 8% reserve.
