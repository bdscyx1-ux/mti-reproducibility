# Gate 13R strict-serial 10% test design v1

## Purpose

This design tests whether the frozen Gate 12R v4 evidence can support a strictly serial Gate 13R 10% formal plan without running Unity or creating formal outputs.

## Hard-gate groups

### A. Authority and isolation

1. The selection record contains the exact user directive.
2. Maximum Unity concurrency is one and the lane count is one.
3. Parallel fallback and mixed topology are false.
4. Formal authorization, formal receipt, formal root creation, and formal timing remain false.
5. `Research/FormalRuns/Gate13R_Serial_10pct/v1` is absent.
6. No Unity process is running during validation.

### B. Frozen upstream identity

1. Gate 11R bundle SHA-256 is `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`.
2. Gate 12R execution receipt, execution manifest, checkpoint, partial manifest, candidate calculation, budget projection, correlation diagnostics, block-aware analysis, pilot manifest, readiness checkpoint, and telemetry result retain their audited SHA-256 values.
3. Gate 12R status remains `GATE12R-COMPLETE-GATE13R-NOT-AUTHORIZED`.
4. Retry and resume counts are zero.

### C. Exact serial execution audit

For all 428 Gate 12R block/control entries:

1. the wrapper summary exists and matches the hash bound by the execution manifest;
2. `passed=true`, `exitCode=0`, and the output manifest hash matches;
3. the Unity log exists, appears in the partial manifest, and matches its bound hash;
4. the log contains a serial assignment and contains neither registered terminal license signature;
5. non-control block manifests assert one block per process, shared process ID, and frozen order;
6. PID bindings match;
7. process intervals sorted by start time never overlap;
8. PID plus process-start identity is unique.

Expected aggregate verdicts are 428/428 summaries, 428/428 logs, 428 serial assignments, zero terminal license errors, zero overlaps, 384 measured blocks, and 1,152 measured samples.

### D. Telemetry audit

1. The bound telemetry result SHA-256 is `d8b9a29f81cd147b8bfb6a94dde46eef1a8b7bca83248729a8f2b8e27824d31e`.
2. PSAPI before/after working-set and private-memory values are positive.
3. CIM PID and creation time match PSAPI PID and process start time.
4. Working-set/private-memory interval comparisons pass.
5. Its Unity log contains a serial assignment and no terminal license result.
6. The telemetry process completed before the pilot's first block process.

### E. Statistics and cardinality

1. Recompute `n_raw = ceil((1.96*sigmaUpper/ln(1.1))^2)` from Gate 12R v4.
2. Apply minimum 32 and round upward to a multiple of four.
3. Assert `n_formal` = 144, 204, 108.
4. Assert 32, 21, 21 campaigns and 4, 2, 2 samples per block.
5. Assert 11,160 block processes and 31,536 samples.
6. Assert no hard cap and no early stopping.

### F. Runtime and storage

1. Recompute cohort and total p50/p95 wall projections from frozen Gate 12R block values.
2. Assert total p50 = 64.830802096 hours and p95 = 83.904223147 hours within floating-point tolerance.
3. Recompute 1.5× p95 raw-byte projection as 43,885,575,792 bytes.
4. Add a 40 GiB reserve and assert launch requirement 86,835,248,752 bytes.
5. Record current free bytes as non-authorizing and require a fresh original-byte check at actual launch.

### G. Playable mapping

Assert 53 scenarios/scenes, 74 campaign profiles, and 212 algorithm presets. Assert `visualizationOnly=true` and `timingEvidenceAllowed=false`. No Playable scene is loaded by this validation.

## Negative/static expectations

- Any missing or changed upstream hash fails validation.
- Any overlapping process interval fails validation.
- Any log without serial assignment, with a terminal license signature, or with a hash mismatch fails validation.
- Any lane count greater than one or any fallback-to-parallel flag fails validation.
- Any existing formal root, formal execution receipt, or formal timing output fails validation.
- The 36-hour value must not be represented as feasible under strict serial execution.

## Execution boundary

The validator may read files, compute hashes, inspect current process count and drive free bytes, and create only a versioned verification summary/evidence audit. It must not launch Unity, create a formal root, create a formal execution receipt, or generate timing samples.
