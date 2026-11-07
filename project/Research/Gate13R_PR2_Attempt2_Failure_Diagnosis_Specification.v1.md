# Gate 13R-PR2 attempt 2 failure diagnosis specification v1

## Status and scope

`NON-EXECUTING / FAILURE-DIAGNOSTIC-ONLY / PARTIAL-FORMAL-ATTEMPT-EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-ATTEMPT3-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

This specification applies only to the failed attempt-2 root `Research/FormalRuns/Gate13R_RQAligned_S48H48/v2`. It does not estimate C1-C5 effects, P1-P5 algorithm performance, power, superiority, or Gate 14R movement outcomes. The unit of the operational memory audit is a fresh Unity Williams-block process; per-sample boundaries inside a process are repeated observations, not independent experimental units.

## Evidence identity

- Expected failed execution receipt SHA-256: `a21466228b1e91dd8670093953b28333e235c9ff031b54fe385301c93ee8365e`.
- Expected pre-write file count: 28,020.
- Expected pre-write raw bytes: 8,536,611,302.
- Expected pre-write canonical tree SHA-256: `be2623906d741b39e87f7c1d033d21443d2776f62ed709b4c4ef296220ce5f04`.
- Canonical tree formula: sort actual relative paths by Unicode code point after replacing `\` with `/`; append `relativePath<TAB>byteLength<TAB>lowercaseSha256<LF>` for every file; hash UTF-8 bytes without BOM.
- The partial-output manifest's 28,019 count is a pre-self-write snapshot. The stable root count of 28,020 is valid only if the extra file is exactly `partial-output-manifest.json`.

## Failure precedence

1. The primary failure is the earliest durable experiment/block failure by timestamp.
2. A later post-exit quiescence or stale-lock failure is secondary and must not replace the primary reason.
3. Both reasons remain hard fail-closed conditions; preserving precedence never authorizes continuation, cleanup-and-continue, retry, resume, top-up, or merge.
4. Attempt 2 remains failed regardless of any future policy decision.

## Memory quantities

For each `memory-gate-evaluation.json`:

- `sampleManagedDelta = telemetryAfterCleanup.managedMemoryBytes - telemetryBeforeSample.managedMemoryBytes` and must equal `sampleRetainedManagedGrowthBytes`.
- `blockManagedDelta = blockRetainedManagedGrowthBytesAtSampleBoundary`.
- `blockWorkingSetDelta = blockWorkingSetGrowthBytesAtSampleBoundary`.
- `blockPrivateDelta = blockPrivateMemoryGrowthBytesAtSampleBoundary`.
- `blockBaselineX = telemetryAfterCleanup.X - blockXDelta`.
- Raw absolute byte counts and process ages must be finite and non-negative. Growth deltas may be negative because cleanup can reduce retained memory below baseline.
- Original hard-limit comparison is strict `delta > limit`; equality passes and one byte over fails.
- MiB means 1,048,576 bytes.

The current policy limits are 256 MiB for retained managed growth and 512 MiB independently for working-set and private-memory growth. Working set, private memory, and managed heap remain distinct measures.

## Distribution rules

- R-7 linear interpolation is used for p50, p90, p95, and p99: `h=(n-1)p`, interpolate between floor and ceiling indices.
- Policy exceedance is evaluated on the maximum observed boundary within each fresh block process, so a four-sample block contributes one block maximum.
- Near-miss bands are reported at at least 80%, 90%, and 95% of the applicable threshold.
- Group summaries are generated without selecting on favorable direction for scenario, grid size, algorithm, Williams position, predecessor, and campaign.
- Candidate limits are 512, 640, 768, and 1,024 MiB. They are planning scenarios only and remain `UNFROZEN / USER-DECISION-REQUIRED`.
- Unobserved future schedule records are never imputed. Because collection stopped at ordinal 934, candidate exceedance rates are descriptive of the observed prefix and cannot establish safety for the remaining matrix.

## Composite identity and completeness

- Each sample must retain `runId`, `blockId`, campaign/scenario/cohort, algorithm, position, predecessor, PID, process start time, and telemetry source.
- Before/raw-after/after-cleanup telemetry for a sample must use the same PID and process start time.
- A completed block must map to exactly one `_plans/pNNNNNN.json`, one global process ordinal, and the expected sample count.
- Failed block positions 1-3 are partial evidence; position 4 has a durable memory evaluation and failure record but no successful sample completion.
- Missing summaries, manifests, non-finite values, or identity conflicts are reported explicitly and never filled with zero.

## Stale-lock rule

Only `H:\DDM_Final_Project\Temp\UnityLockfile` may be removed, and only after exact-path, zero-Unity, exited-orchestrator, non-directory, non-reparse-point, zero-byte, SHA-256(empty), timestamp-match, and exclusive-open checks all pass. Cleanup is an administrative restoration step and never changes the attempt-2 result.

## Decision boundary

The diagnostic may recommend a targeted, new, NON-FORMAL memory pilot if the stopped prefix cannot distinguish expected scenario-scale Unity residency from a true runaway process. No memory policy becomes active in this stage. Any policy or failure-precedence wrapper change requires a later versioned amendment, tests, targeted pilot where needed, and separate user authorization before a new formal attempt.
