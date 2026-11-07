# Formal Scenario Matrix and Preregistration Specification

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T00:00:00+08:00
- Verification Status: UNVERIFIED
- Version Label: code_plan_v1

Gate: 11  
Specification id: `formal-scenario-matrix-v1`  
Generator id: `ddm-formal-scenario-generator-v1`  
Preregistration id: `ddm-planning-preregistration-v1`  
Status: frozen before Gate 11 production implementation  
Frozen: 2026-10-05 (Asia/Shanghai)

## 1. Objective and authorization boundary

Gate 11 materializes and validates the formal input matrix for the fixed-start planning study. It freezes scenario factors, generator seeds, canonical identities, comparison eligibility, exclusion rules, and the analysis table before pilot or formal timing results exist.

Gate 11 may:

1. add a deterministic research-only scenario generator;
2. generate canonical schema-v1 scenario files under `Research/FormalScenarios/v1/`;
3. generate a catalog, matrix config, preregistration config, and bundle manifest;
4. strictly reload, regenerate, hash, classify, initialize, and structurally validate those artifacts;
5. run prior-Gate regression and preservation audits.

Gate 11 does not authorize Gate 12 pilot samples, Gate 13 formal samples, statistical inference, movement simulation, edits to original scripts/scenes, or changes to the frozen Gate 10 fairness contract.

## 2. Research questions and hypotheses

The fixed-start planning study addresses:

| Id | Question | Preregistered directional hypothesis |
|---|---|---|
| `RQ1-node-incremental` | Does per-agent incremental repair reduce dynamic planning cost relative to per-agent full recomputation? | `D*L` has lower dynamic time per event than `A*-R`, separately in shared and per-agent heterogeneous cohorts. |
| `RQ2-field-incremental` | Does incremental field repair reduce dynamic planning cost relative to a fresh full field rebuild? | `IDFF` has lower dynamic time per event than `C-FF`, separately in shared and grouped-field heterogeneous cohorts. |
| `RQ3-agent-scaling` | How does agent count alter shared-field versus per-agent total planning cost? | Shared-field methods have a shallower log-time scaling slope as agent count increases in the shared-goal cohort. |
| `RQ4-change-footprint` | How does changed-cell footprint alter the incremental advantage? | The incremental/full-recompute log ratio approaches zero as changed-cell footprint grows. |
| `RQ5-boundaries` | How do grid size, distinct-goal count, and temporary disconnection affect outcomes? | These are prespecified secondary/descriptive analyses; no directional superiority claim is registered. |

Path length, movement time, collision behavior, arrival rate, and frame rendering are outside the Gate 11 fixed-start result schema and are not preregistered outcomes.

## 3. Constants shared by every generated scenario

| Parameter | Frozen value |
|---|---:|
| Scenario schema | `1` |
| World origin | `(0, 0, 0)` |
| Cell size | `1.0` |
| Fixed step | `0.02 s` |
| Maximum simulation ticks | `100001` |
| Diagonal corner cutting | `false` |
| Initialization budget | `30000 ms` |
| Default plan budget | `10000 ms` |
| Default repair budget | `10000 ms` |
| General dynamic phases | `4` |
| General scheduled events | `5` |
| General event ticks | `10, 10, 50000, 75000, 99999` |

Budgets are common scenario inputs, not algorithm-specific multipliers. Gate 12 may measure whether the frozen budgets are operationally feasible. A change requires a versioned preregistration amendment before Gate 13; it cannot be made silently after formal results are observed.

## 4. Deterministic materialization contract

Every scenario records:

- its integer `randomSeed`;
- one `initialGridOverrides` record for every grid cell, including default-looking cells;
- every agent id, start, and goal;
- every scheduled event, order, tick, effective repair budget, coordinate, walkability, and traversal cost.

There is no runtime topology generation. The seed is provenance for deterministic regeneration and is not consumed by an algorithm during a workload run.

The generator uses integer-only SplitMix64 mixing. For a given generator id, parameter row, and seed, regeneration must reproduce byte-identical canonical JSON. Candidate cells are ordered by unsigned 64-bit key and then by `(y,x)`; ties are broken only by coordinates. Platform random APIs, current time, locale, filesystem order, and floating-point random thresholds are forbidden.

All scenario files are UTF-8 without BOM, LF terminated, strict schema-v1, and byte-canonical under `DeterministicScenarioJson.SerializeCanonical`. Source SHA-256 equals canonical SHA-256. Every scenario fingerprint and source hash must be unique.

## 5. Topology, terrain, agents, and events

### 5.1 Connectivity backbone

The materialized grid contains a protected connected backbone at rows and columns derived from `{1, floor(n/4), floor(n/2), floor(3n/4), n-2}`. Protected cells are initially walkable and are never selected for general blocking events. Agent starts and goals are selected from this backbone.

The target obstacle count is `round(width × height × targetObstacleDensity)`. The generator blocks the lowest deterministic keys among nonprotected cells until that exact target is reached. The catalog records both target and realized density.

### 5.2 Terrain cost modes

- `uniform-v1`: every cell has traversal cost `1`.
- `weighted-1-2-4-8-v1`: every walkable cell receives cost `1`, `2`, `4`, or `8` from a second deterministic key; blocked cells retain cost `1`.

Destination-entry cost, connectivity, and strict diagonal rules remain those frozen by Gates 3, 7, 8, and 9.

### 5.3 Goal structures

- `shared-single-v1`: every agent has one identical goal; comparison cohort `four-algorithm-shared-goal-v1`.
- `heterogeneous-v1`: agents are deterministically assigned across the declared number of distinct goals. The same scenario bytes are referenced separately by `per-agent-heterogeneous-goal-v1` and `grouped-field-heterogeneous-goal-v1`.

For heterogeneous core rows, 16-agent scenarios contain 4 distinct goals and 128-agent scenarios contain 16 distinct goals.

### 5.4 General mixed dynamic profile

The profile `mixed-five-event-four-phase-v1` contains:

1. tick 10/order 0: block the declared footprint of initially walkable, nonprotected cells;
2. tick 10/order 1: unblock the declared footprint of initially blocked, nonprotected cells;
3. tick 50000: increase cost to `8` on another walkable footprint;
4. tick 75000: decrease cost to `1` on another walkable footprint;
5. tick 99999: restore every touched coordinate to its initial state.

The four candidate sets are disjoint before the restore event. Agent starts and all goals are excluded. Every general scenario must preserve reachability from each start to its declared goal after every dynamic phase.

### 5.5 Temporary-disconnection profile

`temporary-disconnect-restore-v1` uses a full vertical barrier with two initial gates. Four single-change phases close the first gate, close the second gate, reopen the first gate, and reopen the second gate. All agents must be initially reachable, remain reachable after the first close, become unreachable after the second close, and be reachable after each reopen. Separate four-way and strict eight-way files are generated.

## 6. Balanced core matrix

The balanced core uses an eight-row orthogonal design. Every structural row has two materialized seeds. Each row/seed is generated once with `shared-single-v1` and once with `heterogeneous-v1`, producing 32 core files.

| Row | Grid | Connectivity | Terrain | Obstacle density | Agents | Dynamic footprint |
|---:|---:|---:|---|---:|---:|---:|
| 1 | 64² | 4 | uniform | 0.10 | 16 | 9 |
| 2 | 64² | 4 | weighted | 0.25 | 128 | 81 |
| 3 | 64² | 8 strict | uniform | 0.25 | 128 | 9 |
| 4 | 64² | 8 strict | weighted | 0.10 | 16 | 81 |
| 5 | 128² | 4 | uniform | 0.25 | 16 | 81 |
| 6 | 128² | 4 | weighted | 0.10 | 128 | 9 |
| 7 | 128² | 8 strict | uniform | 0.10 | 128 | 81 |
| 8 | 128² | 8 strict | weighted | 0.25 | 16 | 9 |

Seeds are `110011/110012` through `110081/110082`: `110000 + row × 10 + seedReplication`. Shared and heterogeneous files for a row/seed reuse the same seed and therefore the same grid/event materialization.

Primary core comparisons are made only within the cohort declared by the matrix entry. Shared and heterogeneous cohort results are never pooled.

## 7. Prespecified stress series

Stress series change one named factor around a fixed reference configuration. They use one materialized seed per level and are secondary unless the analysis table explicitly names them for `RQ3` or `RQ4`.

| Series id | Goal structure | Frozen levels | Reference settings | Files |
|---|---|---|---|---:|
| `grid-scale-v1` | shared | grid `32,64,128,256` | 8-way strict, weighted, density 0.18, 64 agents, footprint 25 | 4 |
| `agent-scale-v1` | shared | agents `1,8,32,128,512` | 128², 4-way, weighted, density 0.18, footprint 25 | 5 |
| `dynamic-footprint-v1` | shared | changed cells `1,9,25,81,225` | 128², 8-way strict, weighted, density 0.18, 64 agents | 5 |
| `goal-count-v1` | heterogeneous | distinct goals `2,4,8,16,32` | 128², 8-way strict, weighted, density 0.18, 128 agents, footprint 25 | 5 |
| `reachability-v1` | shared | connectivity `4,8 strict` | 64², uniform, 32 agents, two-gate barrier | 2 |

Stress seeds are encoded by family and level: `120000 + grid`, `130000 + agents`, `140000 + footprint`, `150000 + goals`, and `160000 + connectivity`.

## 8. Matrix size and algorithm eligibility

The frozen bundle contains 53 unique canonical scenario files:

- 16 shared core;
- 16 heterogeneous core;
- 4 grid-scale shared;
- 5 agent-scale shared;
- 5 footprint shared;
- 5 goal-count heterogeneous;
- 2 reachability shared.

The matrix config expands those files into 212 eligible algorithm×scenario cells:

- every shared file: `A*-R`, `D*L`, `C-FF`, `IDFF`;
- every heterogeneous file under `per-agent-heterogeneous-goal-v1`: `A*-R`, `D*L`;
- the same heterogeneous file under `grouped-field-heterogeneous-goal-v1`: `C-FF`, `IDFF`.

Eligibility is configuration metadata only in Gate 11. No workload sample is executed.

## 9. Canonical bundle identity

`Research/FormalScenarios/v1/` contains:

```text
Scenarios/*.scenario.json
formal-scenario-matrix.json
preregistered-analysis.json
catalog.json
bundle-manifest.json
```

The bundle manifest records:

- this specification and test-design SHA-256;
- Gate 10 fairness and Gate 4 workload-specification SHA-256;
- generator id/source SHA-256;
- every config/catalog SHA-256;
- every scenario relative path, source/canonical SHA-256, semantic fingerprint, and byte count;
- an aggregate bundle SHA-256 computed from ordered `relativePath + LF + sha256 + LF` records;
- `pilotExecuted = false` and `formalCampaignExecuted = false`.

All output paths are create-new. Partial generation is retained for diagnosis and a retry uses a new versioned directory.

## 10. Exclusion, failure, and replacement rules

### 10.1 Gate 11 structural rejection

A scenario or config is rejected before Gate 11 closes if any of these occurs:

- strict schema or semantic validation failure;
- source bytes differ from canonical serialization;
- deterministic regeneration differs byte-for-byte;
- duplicate scenario id, source hash, or fingerprint;
- file size exceeds the 16 MiB scenario boundary;
- incorrect full-cell materialization count;
- factor/seed metadata mismatch;
- cohort or authorized-algorithm mismatch;
- general-profile reachability failure at any phase;
- reachability-profile transition differs from the frozen sequence;
- planner initialization failure for any of the four algorithms;
- artifact hash, bundle hash, or count mismatch.

Rejected inputs are fixed by a new specification/generator version. They are not silently edited in place after freezing.

### 10.2 Future Gate 12–13 sample handling

- Algorithmic `NoPath`, budget overrun, invalid request, and planner failure are outcomes and remain in denominators.
- Timing or allocation outliers are retained. No observation is deleted because it is slow or unfavorable.
- Technical invalidity is limited to nonzero/crashed process, incomplete manifest/JSONL, hash or provenance mismatch, wrong hardware/power preflight, or externally interrupted execution.
- Technical invalid samples remain archived and counted in a failure ledger. Replacement uses the next deterministic sample ordinal and reruns the complete Williams cycle for that scenario/cohort.
- A scenario is never removed after seeing algorithm performance. Any matrix amendment is versioned, justified, and completed before Gate 13.

## 11. Preregistered outcomes and analysis table

### 11.1 Primary endpoint

The primary endpoint is `dynamicHandlingMillisecondsPerScheduledEvent`. Timing analysis uses `log(value)`; zero values are invalid instrumentation and trigger technical investigation, not substitution. Primary effect estimates are exponentiated ratios with 95% confidence intervals.

### 11.2 Secondary endpoints

- `dynamicProcessedNodesOrCellsPerScheduledEvent`, compared only within equal units (`D*L` versus `A*-R` nodes; `IDFF` versus `C-FF` cells);
- `totalPlannerElapsedMillisecondsPerAgent`;
- total managed allocated bytes and dynamic managed allocated bytes;
- plan success and operation budget-overrun rates, retaining all functional failures;
- initialization and initial-query elapsed/work totals;
- algorithm-native counters, reported only under their semantics id.

### 11.3 Frozen analysis rows

| Analysis id | Scenario subset | Cohort | Contrast/model | Endpoint | Multiplicity family |
|---|---|---|---|---|---|
| `P1-DL-vs-A-shared` | shared balanced core | four-algorithm shared | `D*L / A*-R` | primary | `primary-four` |
| `P2-DL-vs-A-hetero` | heterogeneous balanced core | per-agent heterogeneous | `D*L / A*-R` | primary | `primary-four` |
| `P3-IDFF-vs-CFF-shared` | shared balanced core | four-algorithm shared | `IDFF / C-FF` | primary | `primary-four` |
| `P4-IDFF-vs-CFF-grouped` | heterogeneous balanced core | grouped-field heterogeneous | `IDFF / C-FF` | primary | `primary-four` |
| `S1-agent-scaling` | agent-scale | four-algorithm shared | algorithm × `log2(agentCount)` mixed model | total elapsed per agent | `scaling-two` |
| `S2-footprint-scaling` | dynamic-footprint | four-algorithm shared | pair × `log2(changedCells)` mixed model | primary | `scaling-two` |
| `S3-grid-scaling` | grid-scale | four-algorithm shared | descriptive algorithm trajectories | primary + initialization | none |
| `S4-goal-scaling` | goal-count | both heterogeneous cohorts, separate panels | descriptive within-cohort trajectories | primary | none |
| `S5-reachability` | reachability | four-algorithm shared | categorical phase outcomes and recovery | success/failure category | none |

`P1`–`P4` use Holm correction at family-wise alpha `0.05`. `S1` and `S2` use Holm correction as a separate family. Descriptive analyses do not produce confirmatory superiority claims.

### 11.4 Model and reporting policy

- Timing models use log time with fixed effects declared in the matrix and random intercepts for materialized seed and Williams cycle where estimable.
- Report raw `n`, arithmetic mean, median, nearest-rank p95, sample SD, SE, and 95% intervals alongside model estimates.
- Report absolute values and ratios; do not report ratios without the underlying units.
- Use two-sided intervals and tests even for directional hypotheses.
- Report every prespecified row, including null, unfavorable, failed, and budget-overrun results.
- A model assumption failure triggers a prespecified robust or bootstrap sensitivity analysis while retaining the original analysis.

## 12. Gate 12 precision rule and Gate 13 stopping rule

Gate 12 estimates the worst-case standard deviation `sigma_log` of the primary log endpoint within each comparison family. The formal per-algorithm sample count is:

```text
n_raw = ceil((1.96 × sigma_log / ln(1.05))²)
n_formal = next multiple of 4 at or above max(30, n_raw)
maximum n_formal = 100
```

The multiple of four preserves complete four-algorithm Williams cycles and is also valid for two-algorithm cycles. A single common `n_formal` is used for every cell in the family. If the required value exceeds 100, Gate 13 cannot start until a versioned preregistration amendment changes the precision target or reports that the target is infeasible.

Gate 13 uses the fixed Gate 12 value. There is no significance-based, trend-based, or favorable-result early stopping.

## 13. Execution environment policy

Gate 13 preflight must record and hold constant across the campaign:

- exact CPU model and logical processor count;
- installed physical memory;
- Windows edition/build;
- Unity `2022.3.30f1c1` executable hash/path;
- AC power and active Windows power-scheme GUID;
- background-process policy, thermal warm-up policy, and campaign start/end timestamps;
- algorithm/specification/implementation/workload/fairness/matrix/preregistration hashes.

An OS, Unity, algorithm, specification, power-plan, or hardware identity change divides the campaign into a new environment stratum and cannot be silently pooled.

## 14. Gate 11 acceptance criteria

- [ ] Specification and test design pass before generator implementation.
- [ ] Exactly 53 scenario files and 212 eligible algorithm×scenario cells are generated.
- [ ] Every file is strict, byte-canonical, fully materialized, uniquely identified, and below 16 MiB.
- [ ] Regeneration reproduces every scenario byte-for-byte.
- [ ] Cohort and algorithm eligibility match Gate 10.
- [ ] Reachability follows the declared general or transition profile.
- [ ] All four planners initialize on every scenario without storing timing observations.
- [ ] Catalog, matrix, preregistration, and bundle hashes verify.
- [ ] Frozen original baseline remains 24/24 with zero mismatch.
- [ ] Gate 1–10 regression passes and Unity exits cleanly.
- [ ] Gate 12 and Gate 13 remain unexecuted.

