# Gate 9 Checkpoint — Incremental Dynamic Flow Field (IDFF)

Saved: 2026-10-05 (Asia/Shanghai)

Status: **complete**

Final recorded usage reading: 69% used / 31% remaining in the active 5-hour window, safely above the user's required 8% reserve threshold.

User authorization: explicit Gate 9 authorization was received. The authorized scope was to freeze IDFF state ownership, incremental propagation, same-tick atomic changes, direction refresh, budget-interruption consistency, goal-set invalidation, and metric semantics; approve the specification and test design before implementation; compare every post-event field cell-by-cell with a fresh C-FF full recomputation; preserve the Gate 8 batch, repetition, hash, and checkpoint rules; and leave every original script and original scene unchanged.

Gate 10, formal campaign execution, movement simulation, and original-scene changes were not authorized by Gate 9.

## 1. Delivered scope

Gate 9 adds a deterministic shared-goal incremental dynamic flow-field planner to the research-only navigation stack and connects it to the existing single-run and independent-process replication pipelines.

Added or materially extended:

- `Research/Incremental_Dynamic_Flow_Field_Specification.md` — frozen IDFF ownership, propagation, same-tick, direction, budget, lifecycle, invalidation, and metric semantics;
- `Research/Gate9_IDFF_Test_Design.md` — test and fresh-C-FF oracle design frozen before production implementation;
- `Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs` — `IDFF` implementation and read-only all-cell snapshot;
- `Assets/_Scripts/Research/Editor/Gate9IncrementalFlowFieldVerification.cs` — generated-field, fresh-C-FF, lifecycle, budget, determinism, same-tick, and workload verification;
- `Research/Verification/Run-Gate9IncrementalFlowFieldVerification.ps1` — real Unity batch verification wrapper;
- `ResearchPlanningBatchCommand` — exact four-algorithm factory: `A*-R`, `D*L`, `C-FF`, and `IDFF`;
- `Run-PlanningWorkload.ps1` and `Run-PlanningReplication.ps1` — exact four-algorithm parameter whitelist;
- dedicated Gate 9 single-run, replication, and final-audit verifiers;
- Gate 1 compile evidence correction that checks runtime and Editor source timestamps against their respective Unity assemblies.

No research component was attached to an original scene.

## 2. Frozen IDFF semantics

- One planner owns one shared multi-source field. No per-agent shortest-path state is created.
- Goals and topology are immutable between `Initialize` and `Reset`; a goal-set or topology change invalidates the instance and requires `Reset` plus a new `Initialize`.
- The field uses the same directed destination-entry edge cost, goal canonicalization, owner tie-breaking, topology, and corner legality as C-FF.
- Each cell stores lexicographic `g` and `rhs` labels `(integration cost, canonical goal owner)`. A deterministic global inconsistency heap propagates changes until all inconsistent cells are resolved.
- Every valid changed cell seeds its clipped 3×3 dependency neighborhood. Cost increases, decreases, block, and unblock changes share the same consistency propagation rule.
- Each scenario event remains one atomic change set and one repair operation. Multiple events on the same tick retain Gate 4 ordering, with no planning between those events and one planning phase after the tick group.
- Direction refresh is restricted to the accumulated dirty dependency region after a successful repair; it uses the same deterministic direction selection as C-FF.
- Initialization uses an atomic soft deadline. Incremental repair uses a hard resumable deadline: grid identity/version advance immediately with the accepted change set, an interrupted field cannot be snapshotted or planned as complete, and only the identical change set may resume that pending repair.
- A plan request may spend its own hard budget resuming a pending repair. Planning proceeds only after the field becomes consistent.
- `repairedCells` counts unique cells made consistent for an accepted change set, including work resumed across budget interruptions; it is not a full-grid slot count.
- Timing and managed-allocation measurements are diagnostic. Deterministic work counters exclude timing and allocation.

## 3. Algorithm and fresh-C-FF verification

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9IncrementalFlowFieldVerification.ps1"
```

Result:

- Unity exit code: 0;
- compiler-error signatures: 0;
- assertions: 103,138;
- initial fresh-C-FF reference fields: 24;
- post-event fresh-C-FF reference fields: 96;
- all-cell comparisons: 3,600 cells;
- deterministic repaired cells across the four-change sequence: 78;
- deterministic signature SHA-256: `4db0263b6b6c8bf40f478c9aff64540e74b4b662ef0cc29fc0bc69d5375777a7`;
- custom same-tick workload: 4 plans and 2 repairs;
- committed `dynamic-corridors-sparse-v1` workload: 8 plans;
- final grid version in the deterministic sequence: 4;
- runtime and Editor assemblies current;
- result: passed.

For every dynamic event, the verifier constructs a brand-new C-FF planner from the initial grid, replays the complete accepted event history, and then compares every cell's reachability, integration cost, owner, and direction with IDFF. No production IDFF state, heap, propagation helper, or direction helper is reused by the oracle. This also covers events that temporarily block goals because history replay begins from the valid initial field.

Coverage includes destination-entry asymmetry, multi-source ownership and ties, four/eight-way topology, strict/permissive diagonal corners, cost increase/decrease, block/unblock, target block/restore, malformed identities/versions/change sets, goal-set invalidation, initialization soft deadlines, repair hard interruption/resume, plan-triggered resume, dirty direction refresh, deterministic repetitions, same-tick workload behavior, and the committed dynamic scenario.

The algorithm result file is `Research/Verification/Gate9_IncrementalFlowField.json`; SHA-256: `605db09fdca3176e3db21a03da0fb1cca9e7a31ec1037de1b6d8860b69dc0328`.

## 4. Single-run batch evidence

Fixture: `Research/Verification/Gate9_IDFF_BatchFixture_Final/`

- run id: `gate9-idff-batch-final`;
- algorithm: `IDFF`;
- scenario: `dynamic-corridors-sparse-v1`;
- manifest SHA-256: `cc241d5359235bd4dc62d8eac6937e9d90e5cd06610a49598a84e26cc270df10`;
- records: 17 total — 13 planner operations, 3 lifecycle records, 1 workload result;
- plans: 8/8 succeeded;
- repairs: 4;
- final grid version: 4;
- budget overruns/failures: 0;
- deterministic work: 3,033 processed nodes/cells, 148 expanded nodes, 854 relaxed edges, 109 repaired cells;
- managed allocation: 4,096 bytes in the retained run;
- compiler-error signatures: 0;
- dedicated pipeline checks: 16/16 passed;
- incremental-footprint check: `109 < 4 × 60` full-grid rebuild slots;
- no-overwrite and unsupported-algorithm guards: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9BatchPipelineVerification.ps1"
```

## 5. Three-process replication evidence

Fixture: `Research/Verification/Gate9_IDFF_ReplicationFixture_Final/`

- group id: `gate9-idff-replication-final`;
- repetitions: 3 independent Unity Editor processes;
- group manifest SHA-256: `9350a571e895c011080765e75b71fcd38f818d05ec7025fd12a96895ca90ce1b`;
- aggregate SHA-256: `a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac`;
- current-code aggregate revalidation SHA-256: `a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac`;
- records: 51 total — 39 planner operations, 9 lifecycle records, 3 workload results;
- plans: 24/24 succeeded;
- repairs: 12;
- no-path, invalid, failed, and budget-exceeded operations: 0;
- all runs completed and used fixed scenario starts;
- deterministic work in every run: 3,033 processed nodes/cells, 148 expanded nodes, 854 relaxed edges, 109 repaired cells;
- current compiled aggregator regenerated the retained aggregate byte-for-byte;
- dedicated replication-pipeline checks: 21/21 passed;
- no-overwrite and unsupported-algorithm guards: passed.

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9ReplicationPipelineVerification.ps1"
```

These three repetitions validate process isolation, deterministic structural/work counts, output integrity, and aggregation. They are not a formal sample size and must not be interpreted as a completed performance campaign.

## 6. Full regression and preservation

- Gate 1 real Unity compilation: passed after correcting the verifier to map runtime and Editor sources to their respective assemblies; compiler errors: 0.
- Gates 2–9 algorithm, scenario, workload, batch, catalog, statistics, replication, and prior final-audit checks: passed.
- Frozen baseline: 24 entries checked, 0 mismatches.
- Formal research planners: exactly four — `AStarRepeatedPlanner`, `DStarLitePlanner`, `CorrectedFullRecomputeFlowFieldPlanner`, and `IncrementalDynamicFlowFieldPlanner`; Gate 2 retains one `RecordingPlanner` test double.
- Public batch and replication entries accept exactly `A*-R`, `D*L`, `C-FF`, and `IDFF`; the sentinel `UNSUPPORTED` is rejected before output creation.
- The only compiler warning remains frozen original code: `Assets/_Scripts/FlowFieldScripts_Attempt 2/Unit.cs`, `CS0414` for `gravityMultiplier`.
- Original scripts and scenes: unchanged according to the 24-entry frozen baseline.
- Immutable original archive: `H:\DDM_Final_Project_Original.zip`.
- Archive SHA-256: `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`.

Consolidated audit command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9FinalAudit.ps1"
```

Documentation-closeout final audit result: 11/11 categories passed; 24 frozen baseline entries matched; 23 PowerShell scripts, 130 JSON files, and 17 JSONL files parsed with zero failures; all retained Gate 5–9 evidence hashes matched; the exact four-planner scope passed; Unity processes were 0 and `Temp/UnityLockfile` was absent.

## 7. Authorization boundary and next step

Gate 9 is complete. Four algorithms now have correctness gates and use the same batch and independent-process replication infrastructure. No formal long-running experiment campaign has been authorized.

The next planned phase is Gate 10: freeze cross-algorithm fairness semantics, shared-goal versus heterogeneous-goal cohorts, common and native work metrics, dynamic-cost accounting, algorithm/spec version provenance, execution-order balancing, and mixed-identity rejection. Gate 10 requires explicit user authorization before implementation or campaign execution.

Until then:

- do not modify original scripts or scenes;
- do not attach research components to original scenes;
- do not start a formal campaign;
- preserve all Gate 5–9 retained fixtures and current-code aggregate revalidation artifacts;
- use `Research/Next_Session_Checkpoint.md` as the exact resume point.
