# Gate 8 Checkpoint — Corrected Full-Recompute Flow Field (C-FF)

Saved: 2026-10-05 (Asia/Shanghai)

Status: **complete**

User authorization: explicit Gate 8 authorization was received. The authorized scope was to freeze reverse-graph, destination-entry cost, multi-source goal, integration/direction tie-breaking, dynamic full-recompute, budget, and metric semantics; establish an independent reverse multi-source Dijkstra oracle; then implement C-FF using the existing batch, repetition, hash, and checkpoint rules. Gate 8 did not authorize IDFF, original-script modification, original-scene modification, movement simulation, or a formal long-running campaign.

Final usage reading during documentation closeout: 27% used / 73% remaining in the active 5-hour window. This is well above the user's 8% reserve threshold.

## 1. Delivered scope

Gate 8 adds a deterministic shared-goal corrected full-recompute flow-field planner to the research-only navigation stack and connects it to the Gate 5–7 batch and independent-process replication pipeline.

Added or materially extended:

- `Research/Corrected_Full_Recompute_Flow_Field_Specification.md` — frozen graph, ownership, integration, direction, rebuild, budget, metric, and lifecycle semantics;
- `Research/Gate8_CFF_Test_Design.md` — oracle/test design frozen before production implementation;
- `Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs` — `C-FF` implementation of `INavigationPlanner` and a read-only per-cell snapshot for all-cell verification;
- `Assets/_Scripts/Research/Editor/Gate8CorrectedFlowFieldVerification.cs` — independent-oracle, lifecycle, budget, determinism, generated-grid, and workload verification;
- `Research/Verification/Run-Gate8CorrectedFlowFieldVerification.ps1` — real Unity batch verification wrapper;
- `ResearchPlanningBatchCommand` — exact `A*-R`/`D*L`/`C-FF` planner factory;
- `Run-PlanningWorkload.ps1` and `Run-PlanningReplication.ps1` — exact `A*-R`/`D*L`/`C-FF` parameter whitelist;
- dedicated Gate 8 single-run, replication, and final-audit verification scripts;
- updated guides, replication protocol, master plan, and next-session checkpoint.

At the Gate 8 closure boundary, `IDFF` was rejected by both public PowerShell entry points. Gate 9 later superseded that boundary after its own correctness gate; this historical checkpoint otherwise remains unchanged. No research component was attached to an original scene.

## 2. Frozen C-FF semantics

- Uses the same directed destination-entry edge costs as A*-R and D* Lite. Reverse relaxation through destination `v` adds `I(v) + traversalCost(v) × movementMultiplier`; it never charges the predecessor's cost.
- Declared multi-source goals are canonicalized by row `y`, then column `x`; equal-cost ownership is resolved by that canonical goal order.
- A plan request's goal is an ownership assertion. If the start cell's selected owner is another declared goal, the request is rejected instead of silently routing to the other goal.
- Integration construction uses deterministic reverse-Dijkstra ordering. Direction selection is deterministic under the frozen integration/owner/coordinate tie-break rules.
- Four-way/eight-way topology and strict/permissive diagonal corner legality follow the common navigation contract.
- Initialization and every valid dynamic change build a complete scratch integration/owner/direction field and commit it atomically. Blocked goals are inactive until restored.
- Initialization/rebuild budgets are atomic soft deadlines: the full field completes before the overrun is reported. A valid repair that overruns returns `BudgetExceeded` but commits the complete field and advances the grid version. Plan-query budgets remain hard deadlines.
- `repairedCells` for a valid dynamic rebuild is exactly `width × height`; it is a complete-field physical-slot count, not an incremental dirty-region count.
- Timing and managed-allocation measurements are diagnostic; deterministic work counters exclude timing/allocation.

## 3. Algorithm and oracle verification

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8CorrectedFlowFieldVerification.ps1"
```

Result:

- Unity exit code: 0;
- compiler-error signatures: 0;
- assertions: 86,089;
- independent initial reference fields: 24;
- independent post-change reference fields: 72;
- generated small-grid cells compared: 2,880;
- deterministic rebuilt cells: 140;
- deterministic signature SHA-256: `e2e48105fe0233a57dc4bddb98df579d90b8f3cbcbcc66a4a08b244357d34a7e`;
- custom workload integration: 6 plans and 2 repairs;
- committed `dynamic-corridors-sparse-v1` workload: 8 plans;
- runtime and Editor assemblies current;
- result: passed.

The independent oracle is an O(V²) reverse multi-source Dijkstra implementation with direct neighbor enumeration. It does not reuse the production heap, production relaxation helpers, or production direction helpers. Coverage includes asymmetric destination-entry costs, multi-source ownership, direction ties, strict/permissive corners, dynamic full rebuilds, target block/restore, malformed lifecycle/identity/version input, atomic budget behavior on a 96×96 grid, generated fields, deterministic sequences, a shared-goal workload, and the committed dynamic scenario.

## 4. Single-run batch evidence

Fixture: `Research/Verification/Gate8_CFF_BatchFixture_Final/`

- run id: `gate8-cff-batch-final`;
- algorithm: `C-FF`;
- scenario: `dynamic-corridors-sparse-v1`;
- manifest SHA-256: `27ec8cab7b1d0151df8c5b56ffa0c89b8c8b29f41500d00baddf73f31ad678fc`;
- records: 17 total — 13 planner operations, 3 lifecycle records, 1 workload result;
- plans: 8/8 succeeded;
- repairs: 4;
- final grid version: 4;
- budget overruns/failures: 0;
- deterministic work: 2,779 processed nodes/cells, 279 expanded nodes, 289 relaxed edges, 240 repaired cells;
- compiler-error signatures: 0;
- dedicated pipeline checks: 15/15 passed;
- no-overwrite and unauthorized-IDFF guards: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8BatchPipelineVerification.ps1"
```

## 5. Three-process replication evidence

Fixture: `Research/Verification/Gate8_CFF_ReplicationFixture_Final/`

- group id: `gate8-cff-replication-final`;
- repetitions: 3 independent Unity Editor processes;
- group manifest SHA-256: `8b08bbbad0b9962d877e60f8ec7257b50b53a29659584f5115594b1c98718c19`;
- aggregate SHA-256: `b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620`;
- current-code aggregate revalidation SHA-256: `b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620`;
- records: 51 total — 39 planner operations, 9 lifecycle records, 3 workload results;
- plans: 24/24 succeeded;
- repairs: 12;
- no-path, invalid, failed, and budget-exceeded plans: 0;
- all three runs reported identical deterministic work: 2,779 processed, 279 expanded, 289 relaxed, 240 repaired;
- dedicated replication checks: 21/21 passed;
- byte-identical current-code reaggregation, no-overwrite guard, and unauthorized-IDFF guard: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8ReplicationPipelineVerification.ps1"
```

These three repetitions prove pipeline integrity and deterministic algorithmic work counts. They are not claimed as an adequate final scientific sample size, and their timing/allocation statistics are not used to claim superiority.

## 6. Regression and preservation result

The post-integration regression passed Gate 2 through Gate 8, including all retained A*-R and D* Lite fixtures. During that regression, Gate 3 exposed an old verification-contract mismatch: the frozen A*-R specification permits a non-negative `managedAllocatedBytes` diagnostic because Unity runtime counters can legitimately report zero, while the Gate 3 verifier required a strictly positive value. The verifier was corrected to enforce the frozen non-negative contract. No A*-R production algorithm code was changed; Gate 3 then passed 133 assertions and all 36 independent reference cases.

Gate 8 final audit result after documentation closeout:

- 11/11 audit categories passed;
- frozen baseline: 24 checked entries, 0 mismatches;
- passing Gate summaries required: 14;
- PowerShell: 19 scripts parsed, 0 failures;
- evidence formats: 102 JSON and 13 JSONL files parsed, 0 failures;
- exact formal planner scope: `AStarRepeatedPlanner`, `DStarLitePlanner`, and `CorrectedFullRecomputeFlowFieldPlanner`, plus the Gate 2 test double;
- retained Gate 5, Gate 6, Gate 7, and Gate 8 evidence hashes matched;
- only compiler warning: frozen original `Unit.cs` field warning `CS0414`;
- Unity processes: 0;
- `Temp/UnityLockfile`: absent.

Final audit command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8FinalAudit.ps1"
```

## 7. Preservation boundary

- Original scripts and original scenes were not modified.
- Frozen baseline entries remain unchanged.
- Immutable archive: `H:\DDM_Final_Project_Original.zip`.
- Immutable archive SHA-256: `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`.
- Retain the Gate 5, Gate 6, Gate 7, and Gate 8 `*_Final` fixture directories unchanged.
- Retain the Gate 6, Gate 7, and Gate 8 current-code aggregate revalidation artifacts unchanged.

## 8. Exact next decision

Gate 8 is complete. Do not infer authorization for Gate 9.

Recommended next step: obtain explicit authorization for Gate 9 IDFF. If authorized, first freeze incremental state ownership, predecessor/successor propagation, block/unblock and cost-change repair, atomic same-tick changes, direction refresh, repaired-cell metrics, budget interruption consistency, and goal-set invalidation. Every post-event IDFF field must be compared cell-by-cell with a fresh C-FF rebuild before Gate 9 can pass.

Until that authorization is received:

- do not implement IDFF;
- do not modify original scripts/scenes;
- do not launch a formal long-running campaign;
- additional A*-R/D*L/C-FF runs require the user to choose scenario scope and repetition count.
