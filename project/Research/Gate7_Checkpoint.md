# Gate 7 Checkpoint — D* Lite

Saved: 2026-10-04 (Asia/Shanghai)

Status: **complete**

User authorization: explicit authorization for Gate 7 was received. Gate 7 did not authorize C-FF, IDFF, original-scene modification, original-script modification, movement simulation, or a formal long-running campaign.

Final usage reading: 72% used / 28% remaining in the active 5-hour window. The gate completed before reaching the reserve threshold then in force; subsequent work uses the user's updated 8% reserve threshold.

## 1. Delivered scope

Gate 7 adds a deterministic per-agent D* Lite planner to the existing research-only navigation stack and connects it to the Gate 5/6 batch and replication pipeline.

Added or materially extended:

- `Research/DStar_Lite_Specification.md` — frozen graph, cost, state, update, key, tie-breaking, budget, metric, and lifecycle semantics;
- `Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs` — `D*L` implementation of `INavigationPlanner`;
- `Assets/_Scripts/Research/Editor/Gate7DStarLiteVerification.cs` — algorithm, lifecycle, budget, determinism, and independent-oracle verification;
- `Research/Verification/Run-Gate7DStarLiteVerification.ps1` — real Unity batch verification wrapper;
- `ResearchPlanningBatchCommand` — exact `A*-R`/`D*L` planner factory;
- `Run-PlanningWorkload.ps1` and `Run-PlanningReplication.ps1` — exact `A*-R`/`D*L` parameter whitelist;
- dedicated Gate 7 single-run, replication, and final-audit verification scripts;
- updated guides, protocol, master plan, and next-session checkpoint.

C-FF and IDFF remain rejected by both public PowerShell entry points. No research component was attached to an original scene.

## 2. Frozen D* Lite semantics

- Same directed destination-entry graph costs as A*-R.
- Four-way/eight-way topology and strict/permissive diagonal corner behavior follow the common navigation contract.
- Each agent owns independent `g`, `rhs`, queue, revision, `km`, start, and fixed-goal state.
- A same-agent goal change is rejected instead of silently replacing state.
- Deterministic queue order: `key1`, `key2`, row `y`, column `x`, insertion sequence.
- Lazy queue deletion uses per-vertex revisions.
- Path successor order is deterministic by total cost, successor `g`, row, and column.
- A clipped 3×3 seed around each changed cell covers destination-entry costs and strict-corner legality.
- Ordinary changes use local repair. A newly introduced walkable cost below the frozen heuristic scale triggers a measured full rebuild of every existing per-agent state.
- A repair budget result is returned only after affected bookkeeping has been queued. Budget-exceeded plan/repair state remains resumable.
- Grid version, live change payload, run id, goal-set id, endpoint, budget, and lifecycle misuse are validated.

## 3. Algorithm verification

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7DStarLiteVerification.ps1"
```

Result:

- Unity exit code: 0;
- compiler-error signatures: 0;
- assertions: 411;
- independent static reference cases: 24;
- independent post-change reference cases: 72;
- all reference costs/statuses matched an independent O(V²) Dijkstra implementation;
- deterministic sequence work: 297 repair units;
- workload integration: 6 plans and 3 repairs;
- runtime and Editor assemblies current;
- result: passed.

Coverage includes weighted paths, no path, blocked endpoints, `start == goal`, four/eight-way topology, strict/permissive corners, block/unblock, cost increase/decrease, mixed atomic changes, lower heuristic-scale rebuild, multi-agent isolation, goal-switch rejection, moved start, stale versions, malformed identities/payloads, microscopic plan/repair budgets with continuation, workload integration, and repeated deterministic sequences.

## 4. Single-run batch evidence

Fixture: `Research/Verification/Gate7_DStarLite_BatchFixture_Final/`

- run id: `gate7-dstar-lite-batch-final`;
- algorithm: `D*L`;
- scenario: `dynamic-corridors-sparse-v1`;
- manifest SHA-256: `c2c160d0c1aec00a59e7d2d02ebfee776a4ce1272b23fc2929e8d568c09cd427`;
- records: 17 total — 13 planner operations, 3 lifecycle records, 1 workload result;
- plans: 8/8 succeeded;
- repairs: 4;
- final grid version: 4;
- budget overruns/failures: 0;
- deterministic work: 1130 processed nodes/cells, 105 expanded nodes, 548 relaxed edges, 328 repaired cells;
- compiler-error signatures: 0;
- dedicated pipeline checks: 17/17 passed;
- no-overwrite and unauthorized-IDFF guards: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7BatchPipelineVerification.ps1"
```

## 5. Three-process replication evidence

Fixture: `Research/Verification/Gate7_DStarLite_ReplicationFixture_Final/`

- group id: `gate7-dstar-lite-replication-final`;
- repetitions: 3 independent Unity Editor processes;
- group manifest SHA-256: `24fca9a22a24e2f7c18003162790a9bc775c6aaf4a9e4ca95ff4261dc589e4fc`;
- aggregate SHA-256: `40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd`;
- current-code aggregate revalidation SHA-256: `40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd`;
- records: 51 total — 39 planner operations, 9 lifecycle records, 3 workload results;
- plans: 24/24 succeeded;
- repairs: 12;
- no-path, invalid, failed, and budget-exceeded plans: 0;
- all three runs reported identical deterministic work: 1130 processed, 105 expanded, 548 relaxed, 328 repaired;
- dedicated replication checks: 21/21 passed;
- byte-identical current-code reaggregation, no-overwrite guard, and unauthorized-IDFF guard: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7ReplicationPipelineVerification.ps1"
```

These three repetitions prove pipeline integrity and deterministic algorithmic work counts. They are not claimed as an adequate final scientific sample size, and their timing/allocation statistics are not used to claim superiority.

## 6. Regression and preservation result

After D* Lite batch integration, the following were rerun and passed:

- Gate 2 smoke: 26 assertions;
- Gate 3 A*-R: 133 assertions and 36 independent Dijkstra cases;
- Gate 4 scenario/workload: 36 assertions;
- Gate 5 batch pipeline: 18 checks;
- Gate 6 replication statistics: 26 assertions;
- Gate 6 scenario catalog: 28 assertions across 3 canonical fixtures;
- Gate 6 A*-R replication pipeline: 19 audit categories;
- updated Gate 6 consolidated audit: 11 checks;
- Gate 7 D* Lite algorithm, single-run pipeline, replication pipeline, and final audit.

Gate 7 final audit result:

- 11/11 audit categories passed;
- frozen baseline: 24 checked entries, 0 mismatches;
- PowerShell: 15 scripts parsed, 0 failures;
- evidence formats at final audit: 76 JSON and 9 JSONL files parsed, 0 failures;
- exact formal planner scope: `AStarRepeatedPlanner` and `DStarLitePlanner`, plus the Gate 2 test double;
- retained Gate 5, Gate 6, and Gate 7 evidence hashes matched;
- only compiler warning: frozen original `Unit.cs` field warning `CS0414`;
- Unity processes: 0;
- `Temp/UnityLockfile`: absent.

Final audit command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7FinalAudit.ps1"
```

## 7. Preservation boundary

- Original scripts and original scenes were not modified.
- Frozen baseline entries remain unchanged.
- Immutable archive: `H:\DDM_Final_Project_Original.zip`.
- Immutable archive SHA-256: `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`.
- Retain the Gate 5, Gate 6, and Gate 7 `*_Final` fixture directories unchanged.
- Retain both current-code aggregate revalidation files unchanged.

## 8. Exact next decision

Gate 7 is complete. Do not infer authorization for the next algorithm.

Recommended next step: obtain explicit authorization for Gate 8 C-FF. Gate 8 should freeze reverse-graph/multi-source integration semantics and direction tie-breaking, establish an independent reverse multi-source Dijkstra oracle, and only then implement the corrected full-recompute flow field. This ordering provides the full-recompute reference needed by a later IDFF Gate.

Until that authorization is received:

- do not implement C-FF;
- do not implement IDFF;
- do not modify original scripts/scenes;
- do not launch a formal long-running campaign;
- additional A*-R/D* Lite runs require the user to choose scenario scope and repetition count.
