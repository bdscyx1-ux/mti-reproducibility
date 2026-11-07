# Gate 12R pilot attempt 3 managed-memory diagnosis (v1)

## Terminal state

`Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3` is permanently classified as `FAILED-NO-RESUME-NO-MERGE`, `NON-FORMAL`, and `EXCLUDED-FROM-FORMAL-ANALYSIS`. It completed 328 of 384 measured Williams blocks before the unpublished block `g12r-measured-c08-core-r01-s1-hetero-grouped-field-b028` failed. The failed block executed two samples and no later position; neither the block nor its samples may enter Gate 12R variance or sample-size analysis.

The independent audit rehashed all 7,554 entries and 493,784,387 raw bytes listed by the v3 partial-output manifest. It found zero missing files, length mismatches, or SHA-256 mismatches.

## Observed memory evidence

The 328 completed measured blocks had the following retained managed-memory growth distribution:

| Scope | Count | Median | p90 | p95 | p99 | Maximum |
|---|---:|---:|---:|---:|---:|---:|
| All completed blocks | 328 | -35.57 MiB | 2.14 MiB | 25.16 MiB | 73.43 MiB | 122.02 MiB |
| Four-algorithm shared-goal | 165 | -38.63 MiB | -7.19 MiB | 8.13 MiB | 36.11 MiB | 39.38 MiB |
| Two-algorithm grouped-field | 81 | -33.18 MiB | 18.69 MiB | 27.79 MiB | 98.97 MiB | 98.97 MiB |
| Two-algorithm per-agent | 82 | -27.95 MiB | 23.24 MiB | 48.89 MiB | 122.02 MiB | 122.02 MiB |

The failed two-sample grouped-field block began at 561,168,384 managed bytes and ended its second post-cleanup boundary at 700,940,288 managed bytes: 139,771,904 bytes (133.296875 MiB) of block-level growth. Its two samples individually retained 63,397,888 and 71,917,568 bytes, so both passed the unchanged 128 MiB per-sample rule.

## Root cause

The failure exposed an aggregation inconsistency rather than an unbounded per-sample leak. The prior rule allowed each sample up to 128 MiB of post-full-GC retained growth but also limited an entire two- or four-sample block to the same 128 MiB. A block could therefore consist entirely of individually valid samples and still fail solely because valid retained growth accumulated across positions.

The rule is corrected prospectively, not retrospectively. Attempt 3 remains failed. The sample limit remains 128 MiB. The new block limit is the checked product of 128 MiB and the frozen number of samples in that block: 256 MiB for two-sample cohorts and 512 MiB for four-sample cohorts. This is paired with the unchanged 512 MiB working-set and private-memory limits, full-GC boundaries, positive PSAPI/CIM telemetry, per-sample reset, and fail-closed behavior.

## Bias control

This change is authorized after observing a non-formal pilot failure and is therefore explicitly disclosed. No v3 timing or variance observation may be reused in the fresh pilot. The next attempt must use a new root, rerun all pre-pilot gates, and execute all warm-up, cold controls, and 384 measured blocks from the beginning. The numerical 5% precision target, Williams order, scenario matrix, algorithms, endpoint, no-cap sample-size rule, and storage policy remain unchanged.
