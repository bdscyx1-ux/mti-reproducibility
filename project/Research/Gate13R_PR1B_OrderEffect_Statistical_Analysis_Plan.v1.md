# Gate 13R-PR1B Order-Effect Statistical Analysis Plan v1

Status: `FROZEN-BEFORE-NEW-PILOT-DATA / PILOT-INFORMED / NON-FORMAL`

## Analysis population

The valid measured population is the exact 96-pair schedule in `Gate13R_PR1B_OrderEffect_Pilot_Plan.v1.json`. A pair is eligible only when all four fresh Unity processes and all eight algorithm samples complete, preserve the same canonical scenario hash and block ordinal, pass correctness/structural/reset/memory gates, and have unique process and run identities. Partial mirrored pairs remain in failure evidence but contribute to no estimator. A successful attempt requires zero partial measured pairs.

Warm-up, compilation, telemetry, positive verification, negative fail-closed verification, Gate 12R v4, and every historical root are excluded from numerical PR1B estimates.

## Fixed metric reconstruction

- P1: `dynamicHandlingMillisecondsPerScheduledEvent` from the frozen workload result; strictly positive.
- P2: within-sample `dynamicHandlingP95Milliseconds`; strictly positive.
- P3: `totalPlannerElapsedMillisecondsPerAgent`; strictly positive. The agent-count scaling slope is outside this three-scenario order pilot.
- P4: `dynamicManagedAllocatedBytes / scheduledEventCount`; both fields must be present and the denominator must be positive.
- P5 overall: `budgetExceededOperationCount / (planOperationCount + repairOperationCount)`. Plan and repair strata are retained where their denominators are positive. Zero events remain zero; no pseudocount is permitted.

Missing, non-finite, non-positive P1-P4 values, negative counts, impossible P5 derived repair counts, failed correctness, duplicate run IDs, duplicate process identities, or a partial block fail the pilot rather than being silently excluded.

## Contrasts and transformation

The fixed cross-family system/treatment contrasts are C1-C4. For P1-P4:

`L_order = ln(metric_numerator_order / metric_denominator_order)`

and for each mirrored pair:

`D = L_AB - L_BA`.

Positive `D` means the numerator/reference ratio is larger under per-agent-then-grouped than under grouped-then-per-agent. Because P1-P4 are lower-is-better, a positive `D` means the grouped-field system looks less favorable when it runs second, but PR1B does not convert that observation into formal superiority or inferiority.

## Estimation

For each metric, contrast, and scenario, report `n`, mean `D`, sample SD, standard error, two-sided 95% paired t interval, `exp(mean D)`, exponentiated interval, fixed-seed whole-pair bootstrap percentile interval, AB and BA geometric ratios, and Pearson correlation of `D` with measured wave/block ordinal.

The scenario-specific t critical value is fixed to `t(31, 0.975) = 2.039513446`. The pooled equal-scenario estimate uses all 96 mirrored-pair values with equal scenario counts and `t(95, 0.975) = 1.985251004`. The pooled bootstrap is stratified: each replicate resamples 32 complete mirrored pairs with replacement within each scenario, then equally averages the three scenario means.

Bootstrap settings are fixed to 20,000 replicates with seed `13012026`. Percentiles use linear interpolation at 2.5% and 97.5%. No algorithm-sample bootstrap is allowed.

P5 is summarized with eligible operation counts and order-specific rates. If all events are zero, report `ZERO-EVENT / ORDER-RATIO-NOT-ESTIMABLE`; do not report zero variance as evidence of equivalence.

## Multiplicity and interpretation

No PR1B estimate is a formal algorithm-performance test. The report shows raw diagnostic intervals and simultaneously checks all twelve scenario-specific P1 C1-C4 cells plus four pooled cells against the fixed 10% order-bias bound. No claim is based on `p > 0.05`, and no multiplicity-adjusted algorithm superiority claim is generated.

The future Gate 13R C1-C5 Holm family remains unchanged and applies only to the eventual formal shared-goal data. PR1B does not consume formal alpha.

## Decision rule

The exact classifications and H32/H40/H48 recommendation rule are those in the specification. The recommendation is computed mechanically without inspecting effect direction favorability. A material order effect may increase the recommended heterogeneous matched-superblock count and requires retaining order as a prespecified covariate/stratum; it cannot change shared-goal S48.

## Prohibited conclusions

PR1B cannot establish that C-FF or IDFF is superior to A*-R or D*L, cannot estimate a pure algorithm causal effect across heterogeneous ownership families, cannot be merged into the future formal estimator, and cannot justify changing the shared primary endpoint, five contrasts, Holm family, scenario matrix, correctness gates, or Williams design.
