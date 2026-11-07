# Gate 13R-PR2-MP1 read-only diagnostic analysis plan v1

Status: `FROZEN-BEFORE-PILOT / NON-FORMAL / NO-SUPERIORITY-INFERENCE`

## Eligibility

Analysis may start only from a Phase-A raw-freeze receipt whose root identity, 96-block/384-sample completeness, file manifest, tree hash, schedule hash, Williams quotas, environment end snapshot, and immutable attributes validate. The analysis process has no Unity launch path and writes only to a fresh `Research/Analysis/Gate13R_PR2_MemoryPolicy/vN` directory.

## Descriptive units

The independent diagnostic unit is one fresh Unity process executing one complete Williams block. Sample-position telemetry is nested within a process. All summaries preserve scale, block, Williams row, position, predecessor, algorithm, stage, and composite process identity. Algorithm slices are diagnostic residency views, not performance or causal superiority estimates.

## Registered outputs

1. Absolute working-set/private/managed distributions at every registered stage.
2. Checked deltas from process-start, project-loaded, scenario-loaded, and block baselines.
3. Complete scale × row × position × predecessor × algorithm cells with counts, missingness, median, R7 P95, maximum, and bootstrap interval where applicable.
4. First crossing stage and subsequent plateau/trend for 512/640/768/1,024 MiB diagnostic candidates.
5. Candidate exceed and 90%-near-miss counts with Wilson binomial intervals by scale and overall.
6. Margins to the 4 GiB absolute, 2 GiB delta, and 8 GiB free-memory safety limits.
7. PSAPI/CIM absolute and relative discrepancies at jointly observed stages.
8. Managed reset/GC, process-age, first-workload, scale, position, predecessor, and cache-sensitivity descriptions.
9. Evidence for or against reproducible runaway growth and for a scenario-size-aware envelope.
10. False-pass/false-fail, algorithm-fairness, and 32 GiB host-risk discussion.

Bootstrap resamples complete block processes only, uses seed `130220261009`, and defaults to 20,000 replicates for registered interval outputs. It never resamples individual algorithm samples as independent observations.

## Prohibited analyses

No C1–C5 or P1–P5 superiority inference, formal effect estimate, formal n-formal calculation, adaptive threshold selection, Gate 14R movement analysis, or attempt-2 reinterpretation is permitted.

## Recovery

An analysis-code failure preserves its attempt directory and logs, leaves the raw root byte-identical, and may be repaired in a new versioned analysis attempt. It cannot trigger Unity measured reruns. Raw-contract failure stops and requires new user authorization.
