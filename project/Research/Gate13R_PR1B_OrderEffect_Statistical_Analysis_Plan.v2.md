# Gate 13R-PR1B v2 Order-Effect Statistical Analysis Plan

Status: `FROZEN-BEFORE-NEW-PILOT-DATA / NON-FORMAL`

## Estimation set

The primary diagnostic analysis set contains every complete, eligible measured mirrored pair from the single successful v2 attempt. Eligibility requires all four constituent fresh-process blocks, all eight algorithm samples, durable memory evaluations, valid reset/telemetry/hash/provenance, and no hard memory breach. Partial pairs are never analyzed. Warm-up data and all attempt-1 data are excluded.

`MEMORY-ALERT-128MIB` does not make an otherwise eligible observation missing and cannot justify selective deletion. The primary set therefore includes alert and no-alert pairs.

## Contrasts and order effect

C1 is C-FF/A*-R, C2 C-FF/D*L, C3 IDFF/A*-R, and C4 IDFF/D*L. For positive P1–P4 endpoints, form natural-log ratios within each AB and BA superblock and then compute `D_i = logRatio_AB_i - logRatio_BA_i` for each complete mirrored pair. P5 preserves operation counts and zero events without pseudocount log ratios.

For each scenario and contrast, report the mean of 32 `D_i` values, SD, SE, two-sided 95% paired-t interval, exponentiated estimate/interval, and a fixed-seed whole-mirrored-pair bootstrap interval. The pooled estimate gives each scenario equal weight. Bootstrap replicates are 20,000 and seed is 13012026.

## Decision rule

The frozen order-effect diagnostic bound is ±`log(1.10)`. Classification remains:

- `ORDER-EFFECT-BOUNDED`: the entire 95% t interval lies within the bound;
- `MATERIAL-ORDER-EFFECT`: the interval excludes zero and the point is outside the bound;
- `DETECTABLE-BUT-BELOW-BOUND`: the interval excludes zero, the point is inside the bound, but the interval is not wholly bounded;
- `INCONCLUSIVE`: otherwise.

The mechanical H32/H40/H48 recommendation logic from PR1B v1 is unchanged and cannot authorize a formal campaign.

## Memory-alert sensitivity

The analyzer must first report the frozen primary all-eligible result. It then reports:

1. alert incidence by scenario, cohort, algorithm, Williams position, predecessor, superblock order, pair-process position, and wave;
2. whether the process immediately after an alerted sample/block shows altered P1–P4, process-age, working-set, private-memory, or managed-memory deltas;
3. a no-alert mirrored-pair subset sensitivity result, labelled `SENSITIVITY-ONLY-NOT-PRIMARY`;
4. an influence table comparing all-eligible and no-alert estimates/intervals without changing eligibility or the decision rule.

If the no-alert subset is too small or loses AB/BA/scenario support, it is reported as not estimable. It is never substituted for the primary result.

## Diagnostics

Report position, predecessor, process age, wave, scenario slot, AB/BA order, adjacency/contiguity, and environment drift. Samples are not independent; complete mirrored pairs are the resampling and inferential unit. No formal superiority claim, sample-size conclusion, or Gate 14R claim is permitted.
