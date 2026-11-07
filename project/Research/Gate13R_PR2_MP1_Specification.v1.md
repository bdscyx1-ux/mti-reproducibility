# Gate 13R-PR2-MP1 targeted memory-policy pilot specification v1

Status: `FROZEN-BEFORE-PILOT / NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY / FORMAL-ATTEMPT3-NOT-AUTHORIZED`

## Purpose and boundary

MP1 determines where Unity process memory is introduced and retained across process start, project load, deterministic scenario load, four Williams-ordered algorithm samples, cleanup, block completion, and process exit. It is not an algorithm-performance experiment and cannot support C1–C5, P1–P5, formal variance, formal sample-size, or Gate 14R inference.

The historical attempt-2 root remains failed, incomplete, read-only, and excluded. MP1 neither resumes nor repairs that root and never merges MP1 observations with it.

## Frozen measured matrix

| Canonical scenario | Grid | Measured fresh block processes | Williams row quota |
|---|---:|---:|---:|
| `grid-scale-g032-shared` | 32×32 | 16 | 4 per row |
| `grid-scale-g064-shared` | 64×64 | 16 | 4 per row |
| `grid-scale-g128-shared` | 128×128 | 16 | 4 per row |
| `grid-scale-g256-shared` | 256×256 | 48 | 12 per row |

Total: 96 measured block processes and 384 measured algorithm samples. This version freezes `warmupProcessCount = 0`; the authorization ceiling of two per scale/eight total is not consumed. Validation-only Unity invocations are separate, explicitly excluded, and are not warm-up or measured observations.

Each process executes exactly one complete four-algorithm block. A block contains A*-R, D*L, C-FF, and IDFF exactly once. Execution is strict serial with maximum Unity Editor concurrency one. Each sample creates fresh planner/grid/scenario/runner/logger/metric state, then resets the planner, disposes logging, returns heavy references, forces the registered cleanup boundary, and captures post-cleanup telemetry.

## Frozen Williams design

The base algorithm order is `[A*-R, D*L, C-FF, IDFF]`. Row construction uses the retained Gate 10R/PR2 algorithm: base indices `[0,1,3,2]`, rotated by row index. Rows are therefore:

1. `A*-R, D*L, IDFF, C-FF`
2. `D*L, C-FF, A*-R, IDFF`
3. `C-FF, IDFF, D*L, A*-R`
4. `IDFF, A*-R, C-FF, D*L`

Rows cycle in deterministic block ordinal order. Algorithm × position is exactly balanced within every scale. Directed predecessor counts are those implied by the complete Williams rows and are balanced within each row quota. Schedule, IDs, paths, scenario seeds, scenario hashes, and row assignments are generated before Unity execution and hashed.

## Telemetry stages

Every process is bound by `(PID, processStartTimeUtc, blockId)`. Required stages are:

1. `external-first-valid-psapi-after-process-create`;
2. `unity-command-entry-project-loaded`;
3. `before-scenario-load`;
4. `after-scenario-load-before-first-sample`;
5. for each position: `sample-before`, `sample-raw-after-workload`, `sample-after-cleanup`;
6. `post-block-pre-exit`;
7. `process-exit`;
8. `post-exit-quiescence`.

Every in-process memory stage stores working-set bytes, private-memory bytes, managed-memory bytes, GC generation counts, process age, UTC capture time, source ID, block identity, and checked deltas against the available process-start, project-loaded, scenario-loaded, and block baselines. Negative deltas are retained. External snapshots store PSAPI-backed process values, an independent CIM cross-check when available, OS available physical memory, process identity, UTC, and source IDs.

Missing/non-finite values, checked-arithmetic overflow, PID/start-time/block mismatch, timestamp reversal, non-positive required absolute memory, or missing required stages fail closed.

## Frozen pilot-only policy

- Candidate native deltas 512, 640, 768, and 1,024 MiB are diagnostic flags only.
- Sample retained-managed growth above 128 MiB is an alert.
- Sample retained-managed growth above 256 MiB is an emergency hard failure.
- Block retained-managed growth above 256 MiB is a hard failure at each completed sample boundary and at block completion.
- Correctness, oracle, structural exact-match, deterministic identity, reset, telemetry, hash, and persistence failures are hard failures.
- Absolute Unity working set or private memory above 4 GiB is an emergency hard failure.
- Working-set or private-memory growth above 2 GiB relative to the applicable process/block baseline is an emergency hard failure.
- OS available physical memory below 8 GiB is an emergency hard failure.
- Unverifiable sustained growth or telemetry overflow is an emergency hard failure.

Any hard failure prevents the next block and permanently terminates this single measured pilot attempt. No automatic retry, resume, top-up, or partial merge is permitted.

## Failure precedence and lock hygiene

Durable Unity/block failure is primary when present; hard timeout is next; non-zero Unity exit without durable block failure is next; post-exit quiescence failure is primary only when no earlier primary cause exists. A quiescence failure is otherwise retained as a distinct secondary cause. Any cause fails closed. Lock cleanup cannot authorize continuation.

An exact stale-lock cleanup may occur only after zero owned/live Unity process-tree evidence, exact lock path/size/hash/timestamp/handle verification, and an externally persisted receipt. Inability to prove every condition stops MP1.

## Two-stage commit

Phase A freezes an immutable raw tree only after all 96 measured blocks and 384 samples satisfy the acquisition contract. The raw commit records every file hash, tree hash, schedule quota, environment end snapshot, and status `PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`.

Phase B reads the raw tree without writes and creates independent versioned analysis attempts. An ordinary analysis-code defect is repaired and re-run against the same raw commit; it never causes Unity measured blocks to rerun. Only evidence that raw data violate this frozen acquisition contract can require a new user-authorized experiment.

## Success and stopping

Successful MP1 ends after the raw commit, one validated read-only diagnostic analysis, an unfrozen policy decision matrix/recommendation, readiness checkpoint, plan update, and next authorization prompt. It does not create a formal root or receipt and does not start formal attempt 3 or Gate 14R.
