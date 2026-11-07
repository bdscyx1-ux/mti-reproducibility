# Additional diagnostics for original comments 22 and 23

## Material Passport

- Origin Skill: academic-research-suite experiment-agent / nature-statistics
- Origin Mode: run + validate
- Origin Date: 2026-11-03
- Verification Status: VERIFIED computational replay and independent covariance implementation; bounded statistical interpretation
- Version Label: comments22-23-statistics-v1

The frozen SMSB model and ranking remain intact. This supplement uses 7,776 lane summaries from 1,296 complete six-lane superblocks. The 34-column design and fixed coefficients reproduce the archived estimates (maximum coefficient discrepancy below 1e-8). It adds diagnostics rather than replacing the original confirmatory families. No algorithms were rerun, and no new independent maps, sessions or machines were sampled.

## Residual variation

Both marginal residuals and conditional residuals after a random-intercept BLUP are supplied. There are 38,880 lane–outcome records, 30 algorithm summaries and 1,080 algorithm×cell summaries. Every algorithm/cell is retained. Conditional residual SD varies materially across algorithms and cells; neither convergence nor full design rank establishes common residual variance. These descriptive spreads are not a formal heteroscedasticity test and cannot establish that the conditional mean is correctly specified.

| Outcome | Across-algorithm SD range | Maximum / minimum SD | Across algorithm×cell SD range |
|---|---|---:|---|
| D1_GEOMETRIC_MEAN | 0.2794–0.8475 | 3.034 | 0.2287–0.8949 |
| D1_NEAREST_RANK_P95 | 0.3162–0.8173 | 2.585 | 0.3094–0.8662 |
| D2 | 0.2759–0.8622 | 3.125 | 0.2475–0.8893 |
| D3 | 0.1881–0.6731 | 3.578 | 0.0469–0.8146 |
| D4 | 0.0228–0.0665 | 2.918 | 0.0150–0.1279 |

## Cluster-aware reference-condition uncertainty

The fixed-effect point estimates, design and working random-intercept covariance are kept at their archived values. A superblock-cluster sandwich is added with CR1 multiplier G/(G−1)×(n−1)/(n−p), where G=1,296, n=7,776 and p=34. The reference contrast is IDFF/C-FF at centered continuous axes and the original common reference factors. Inference uses t with 1,295 degrees of freedom. Pointwise 95% intervals and separate Bonferroni 99% intervals for these five diagnostic contrasts are both reported. This is a plug-in GLS sandwich, conditional on the archived variance parameters; it is not a new REML fit or a claim of exact finite-sample coverage.

| Outcome | Ratio | Pointwise 95% cluster interval | 99% interval across the five diagnostics | Cluster / old SE |
|---|---:|---|---|---:|
| D1_GEOMETRIC_MEAN | 0.7586 | [0.7166, 0.8031] | [0.7038, 0.8177] | 1.592 |
| D1_NEAREST_RANK_P95 | 1.1188 | [1.0565, 1.1848] | [1.0376, 1.2064] | 1.441 |
| D2 | 0.7581 | [0.7149, 0.8039] | [0.7018, 0.8189] | 1.610 |
| D3 | 0.2151 | [0.2085, 0.2219] | [0.2065, 0.2241] | 1.159 |
| D4 | 2.4164 | [2.4102, 2.4226] | [2.4082, 2.4246] | 0.734 |

D3 and D4 use log1p, so their inferential ratios compare (value+1), not raw bytes without the shift. The additional uncertainty preserves the observed average-latency / upper-tail / retained-state trade-off: D1 GM is lower for IDFF, while D1 P95 and D4 are higher relative to C-FF. Cluster intervals are not uniformly wider: D4 is narrower under the observed within-block dependence. Do not select the covariance estimator according to its favorable result. These five intervals do not update all original ranking, dominance or scaling-slope decisions.

## Matched-block bootstrap sensitivity

The separate descriptive estimator averages within-superblock transformed IDFF–C-FF differences, with equal weight across the 36 G/N/F cells. It uses 5,000 seeded bootstrap resamples of complete matched blocks within cells. A block, rather than an event or algorithm lane, is the resampled unit. Resampling weights are common across the five outcomes. These are workload-average paired ratios, conceptually distinct from the reference-condition adjusted predictors. Their point values nearly coincide here because of the balanced design; that numerical agreement does not make the estimands interchangeable.

| Outcome | Paired ratio | 95% percentile interval | Cell ratio range | Cells below 1 |
|---|---:|---|---|---:|
| D1_GEOMETRIC_MEAN | 0.7586 | [0.7169, 0.8028] | 0.6260–1.0939 | 33/36 |
| D1_NEAREST_RANK_P95 | 1.1188 | [1.0572, 1.1846] | 0.8461–1.7383 | 9/36 |
| D2 | 0.7581 | [0.7151, 0.8040] | 0.5939–1.1804 | 33/36 |
| D3 | 0.2151 | [0.2086, 0.2218] | 0.1267–0.3803 | 36/36 |
| D4 | 2.4164 | [2.4106, 2.4224] | 2.3046–2.4964 | 0/36 |

These intervals describe the retained, selected workload distribution under independent-superblock assumptions. They do not model new-map populations, between-host or between-session variation, or systematic misspecification. The cell ranges show heterogeneity; a lower aggregate is not a claim of lower latency in every cell.

## Weight sensitivity and actual effect magnitudes

Rank utilities and the original score are reproduced exactly. Four weight choices were specified before the new computations, without searching for a preferred winner. All domain weights sum to one.

| Scheme | D1…D7 weights | Point leader(s) |
|---|---|---|
| original | 0.35, 0.2, 0.15, 0.075, 0.075, 0.075, 0.075 | IDFF |
| equal | 0.1429, 0.1429, 0.1429, 0.1429, 0.1429, 0.1429, 0.1429 | IDFF |
| latency_priority | 0.7, 0.1, 0.05, 0.05, 0.04, 0.03, 0.03 | IDFF |
| retained_state_priority | 0.1, 0.05, 0.05, 0.6, 0.05, 0.05, 0.1 | A*-R |

The archived runtime-priority sweep is also supplied: with D1:D2:D3 fixed at 7:4:3 and the other four domains equally weighted, the point leader changes from C-FF to IDFF at runtime-group weight rho=0.4468085106, with a tie at that boundary. In the archived 128 independent 0.5×/1.5× weight corners followed by normalization, IDFF leads at 118 and C-FF at 10. These are sensitivity scenarios, not repeated experiments or probabilities.

The new full simplex grid uses nonnegative weights summing to one in steps of 0.1 (8,008 vectors, including boundaries). It has 418 tied-leading vectors. All scores and tied leader sets are supplied.

| Algorithm | Unique point-leader vectors | Co-leading vectors including ties |
|---|---:|---:|
| A*-R | 548 | 622 |
| BiA*-R | 0 | 1 |
| D*L | 256 | 288 |
| LPA* | 0 | 0 |
| C-FF | 2851 | 3220 |
| IDFF | 3935 | 4299 |

The grid is a chosen discretization, not a distribution of real user preferences. Counts change with the grid measure/resolution and cannot be interpreted as the probability an algorithm is best. The original conservative score bounds overlap (IDFF 75.5–87.5; C-FF 68.5–80.5), so the original model did not establish a uniquely separated score winner. Those bounds retain the original normal-z model assumptions; this supplement does not silently substitute the new cluster intervals into them.

| Endpoint | IDFF reference value / slope | C-FF reference value / slope | Unit | Exponentiated model contrast |
|---|---:|---:|---|---:|
| D1 GM | 19.7524 | 26.037 | ms | 0.758625 |
| D1 P95 | 34.7525 | 31.0611 | ms | 1.11884 |
| D2 | 2.34511e+07 | 3.09342e+07 | calls | 0.758096 |
| D3 | 6.38191e+06 | 2.96664e+07 | bytes | 0.215123 |
| D4 | 547740 | 226677 | bytes | 2.41638 |
| D5 | 0.031043 | 0.0285353 | log latency per log2 N | 1.00251 |
| D6 | 0.0515003 | -0.00357771 | log latency per log2 F | 1.05662 |
| D7 | 0.649907 | 0.690961 | log latency per log2 G2 | 0.959778 |

D1–D4 entries are inverse-transformed reference predictors, not arithmetic mean measurements. D5 and D6 are log-latency slopes per doubling of N or F; D7 is per doubling of G² (cell area), not per doubling of edge length G. Exponentiating a slope difference gives a relative per-axis latency multiplier. These actual magnitudes accompany the relative ranks so that small and large effects are not confused.

D*L and LPA* have identical D2, D3 and D4 values in all 1,296 matched blocks, while their measured timing values differ. This equality is evidence of strongly related deterministic implementation behavior in these workloads, not independent replication by distinct algorithm families. Both remain candidates in the frozen six-algorithm ranking; changing the candidate set would require redefining its rank utilities.

## Suggested manuscript insertion for original comment 22

A supplementary diagnostic reconstructed residuals from all five frozen SMSB models and tabulated them by algorithm and algorithm×G/N/F cell. Across algorithms, conditional residual SD ranges differed by factors of 2.58–3.58, so numerical convergence and a full-rank design do not establish common residual variance. Keeping the frozen fixed-effect estimates and working covariance, a superblock-cluster CR1 sandwich with t(1,295) inference gave IDFF/C-FF pointwise 95% intervals of [0.7166, 0.8031] for D1 GM, [1.0565, 1.1848] for D1 P95, [0.7149, 0.8039] for D2, [0.2085, 0.2219] for D3 and [2.4102, 2.4226] for D4; the last two compare values after the specified one-byte shift. A separate 5,000-draw, within-cell matched-superblock bootstrap gave compatible descriptive paired contrasts. Its workload-average estimand and the reference-condition model contrast remain distinguished. These additional analyses retain the independent-superblock and selected-workload scope and do not replace the frozen confirmatory or ranking calculations.

## Suggested manuscript insertion for original comment 23

The score is a post hoc preference summary rather than an implementation-independent ordering. Under the original weights, IDFF scores 83.0 and C-FF 74.5, with overlapping original-model conservative bounds of 75.5–87.5 and 68.5–80.5. The archived runtime-weight sweep changes the point leader from C-FF to IDFF at rho=0.4468, and its 128 weight corners select IDFF in 118 scenarios and C-FF in 10. Additional prespecified equal-domain and latency-priority weights also select IDFF, whereas retained-state-priority weights select A*-R. An 8,008-vector simplex grid exposes further preference dependence; its winner counts are scenario counts, not probabilities. Reference latency, calls, bytes and scaling slopes are supplied alongside ranks, including IDFF/C-FF ratios of 0.7586 for D1 GM, 1.1188 for D1 P95 and 2.4164 for shifted D4. D*L and LPA* share identical D2–D4 observations in all 1,296 matched blocks and should not be treated as independent architectural replications.

## Verification and limitations

All 18 source snapshots retain their original SHA-256. A second execution exactly reproduced seven CSV files and five numerical JSON files. A separate explicit per-cluster matrix implementation reproduced all five CR1 standard errors and matched each frozen model standard error. This verifies computations and artifact identity, not model correctness or broader external validity. Analysis ran in Python 3.12.14, NumPy 2.3.5, pandas 3.0.1.

See STATISTICAL_VALIDATION.md for the 11-item interpretation scan.
