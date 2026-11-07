# Gate 5 Checkpoint — Reproducible A*-R Batch Pipeline Complete

Completed: 2026-10-04 (Asia/Shanghai)

## Implemented

- `Assets/_Scripts/Research/Editor/ResearchPlanningBatchCommand.cs`
  - strict command-line option parsing;
  - explicit allowlist containing only implemented `A*-R`;
  - fresh-output-directory enforcement;
  - canonical input copy, JSONL operation log, workload result, and provenance manifest;
  - SHA-256 for source input and every primary output;
  - Unity version/runtime platform, timestamps, record counts, and completion state;
  - best-effort `failure.json` after an output location has safely been accepted.
- `Research/Run-PlanningWorkload.ps1`
  - headless Unity launcher, editor/lock guard, default unique run location, compiler scan, and wrapper summary.
- `Research/Verification/Run-Gate5BatchPipelineVerification.ps1`
  - verifies output presence, every recorded hash, identities, semantic counts, UTF-8 JSONL parsing, contiguous sequence numbers, record types, allocation observation, compiler cleanliness, and Unity completion marker.
- `Research/Batch_Planning_Workload_Guide.md`
  - invocation, artifact, provenance, and interpretation instructions.

## Final verified fixture

Directory: `Research/Verification/Gate5_BatchFixture_Final`

- Run id: `gate5-fixture-final`.
- Algorithm: `A*-R`.
- Scenario source/canonical SHA-256: `0245d7512a4fdda306f36e2f36357d33d8eedf7330ce6d162f8f66baa9fd6890`.
- Scenario semantic fingerprint: `d2a8e612af706f03513c726cad734d747141411742fbe92fefd88e7b824c04cf`.
- JSONL SHA-256: `668992a2a709d764a44816c5f244194f0873416d214fb942268d3c3cea4c9c51`.
- Workload result SHA-256: `1ea86922d699cabfb279609e0e105c28053a50348ceaaddf2abe7304aac14107`.
- JSONL records: 14 contiguous records (`3` lifecycle, `10` planner operations, `1` workload result).
- Workload operations: 6 plans, 3 change acknowledgements, 2 dynamic phases, final grid version 3.
- Managed allocation observed: 561,152 bytes total; 5 planner-operation records have a positive allocation delta.
- Unity exit code: `0`; compiler-error signatures: `0`; completion marker present.
- `Gate5_BatchPipeline.summary.json`: all 18 checks passed, including refusal to reuse the non-empty fixture directory.

The earlier pre-allocation-fallback fixture is retained only under the explicitly named `Superseded_Gate5_BatchFixture_PreAllocationFix` archive and is not valid Gate 5 evidence.

## Scope preserved

- The batch allowlist contains only `A*-R`; it refuses unimplemented or unauthorized algorithm ids.
- No original script, scene, prefab, package file, or project setting was intentionally changed.
- No scene is opened or modified by the workload.
- No scenario generation, movement, arrival, frame benchmarking, C-FF, D* Lite, or IDFF was implemented.

## Next safe resume point

The next session can add experimental scenario fixtures and a multi-run replication/aggregation layer around this batch command. D* Lite and IDFF still require explicit next-gate authorization.
