# Gate 13R-PR1B Balanced Mirrored Order-Effect Supplemental Pilot Specification v1

Status: `PREREGISTERED / NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## Purpose and scope

Gate 12R v4 contains 96 heterogeneous matched pairs, but the observed cohort-process order is 89 `PER_AGENT_THEN_GROUPED` versus 7 `GROUPED_THEN_PER_AGENT`. Those data establish matchability by canonical scenario and block, but they do not separate cohort order from scenario, wave, adjacency, and calendar-time drift with adequate pilot-level strength.

PR1B runs one new, isolated supplemental pilot whose sole scientific purpose is to identify the magnitude and uncertainty of this cohort-process order effect. It is not a formal comparison of algorithm superiority, is not a replacement for Gate 12R v4, and may never be pooled into Gate 13R formal inference.

## Frozen upstream contract

- Gate 10R attempt 4 process topology remains unchanged: one fresh Unity Editor process per complete Williams block, one block maximum per process, one occurrence of each eligible algorithm per process, complete sample reset, and fail-closed execution.
- Gate 11R attempt 2 scenario bytes, canonical identities, deterministic inputs, Williams rows, profiles, presets, and Playable mappings remain unchanged.
- Gate 13R-PR1 retains shared-goal as the only primary confirmatory scope. Heterogeneous cross-family comparisons remain secondary system/treatment comparisons, not pure algorithm causal effects.
- The active Unity implementation remains `Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs` byte-for-byte unchanged.

## Pilot subset

The subset is frozen to the three heterogeneous Gate 12R anchors:

1. `core-r01-s1-hetero`
2. `core-r07-s2-hetero`
3. `goal-count-g32-hetero`

Each scenario has its existing per-agent cohort (`A*-R`, `D*L`) and grouped-field cohort (`C-FF`, `IDFF`). No scenario, algorithm, seed, or profile is regenerated.

## Independent unit and mirrored schedule

The independent diagnostic unit is one **mirrored order pair** for a fixed canonical scenario and fixed Williams block ordinal. Each mirrored pair contains two matched superblocks:

- `AB`: a fresh per-agent process followed immediately by a fresh grouped-field process.
- `BA`: a fresh grouped-field process followed immediately by a fresh per-agent process.

Therefore one mirrored pair contains four fresh Unity Editor processes and eight algorithm samples. Both superblocks use the same scenario, deterministic input identity, and Williams block ordinal. This gives both cohorts the same within-process Williams row in AB and BA.

For each scenario, measured ordinals are exactly 1 through 32. Odd ordinals execute the AB superblock before BA (`P,G,G,P`); even ordinals execute BA before AB (`G,P,P,G`). This balances early/late superblock placement. Scenario order rotates by wave so each anchor occupies early, middle, and late wave positions without changing the four-process contiguity of a mirrored pair.

Measured cardinalities are frozen to:

- 32 mirrored pairs per scenario;
- 96 mirrored pairs total;
- 192 matched superblocks, exactly 96 AB and 96 BA;
- 384 measured Unity block processes;
- 768 measured algorithm samples;
- exactly 32 AB and 32 BA superblocks per scenario;
- exactly 16 AB-first and 16 BA-first mirrored pairs per scenario.

Before measurement, one excluded mirrored warm-up pair at block 33 is run for each scenario: 12 processes and 24 samples. Warm-up data are excluded from every estimator.

## Metrics and contrasts

Order-effect estimation covers cross-family contrasts C1-C4:

- C1: `C-FF / A*-R`
- C2: `C-FF / D*L`
- C3: `IDFF / A*-R`
- C4: `IDFF / D*L`

For strictly positive P1-P4 metrics, the contrast is the natural-log numerator/reference ratio. P1 is the decision-driving order-effect endpoint; P2-P4 are supportive. P5 retains all zero and non-zero eligible counts and is not forced into a log ratio.

The performance endpoint hierarchy from PR1 is not changed: P1 remains the future Gate 13R primary endpoint only in shared-goal formal inference. Within PR1B, P1 is merely the primary *order-diagnostic* endpoint.

## Order-effect estimand

For mirrored pair `i`, metric `m`, and contrast `c`:

`D_i(m,c) = logRatio_AB_i(m,c) - logRatio_BA_i(m,c)`.

`exp(D)` is the multiplicative change in the system/treatment ratio when the grouped-field cohort runs second rather than first. Zero on the log scale (one after exponentiation) means no cohort-order effect.

The scenario-specific estimator is the arithmetic mean of the 32 paired `D_i` values. The pooled estimator gives each of the three scenarios equal weight. Uncertainty uses a two-sided 95% paired t interval and a fixed-seed, whole-mirrored-pair bootstrap sensitivity interval. Individual algorithm samples are never treated as independent.

## Operational materiality bound

The preregistered order-bias bound is a multiplicative 10% shift: `[-log(1.10), +log(1.10)]`. This is an execution-order diagnostic bound, not an algorithm practical-superiority margin and not the 10% CI precision target.

Classification for each P1 contrast and scope is:

- `ORDER-EFFECT-BOUNDED`: the entire 95% t interval lies inside the order-bias bound.
- `MATERIAL-ORDER-EFFECT`: the interval excludes zero and the point estimate lies outside the bound.
- `DETECTABLE-BUT-BELOW-BOUND`: the interval excludes zero, the point lies inside the bound, and the interval is not wholly inside it.
- `INCONCLUSIVE`: all other cases.

The pilot may recommend, but cannot freeze, the heterogeneous formal configuration:

- `H32-SUPPORTED` only if every pooled C1-C4 P1 interval and every scenario-specific C1-C4 P1 interval is `ORDER-EFFECT-BOUNDED`.
- `H40-RECOMMENDED` if all pooled C1-C4 P1 intervals are bounded, no scenario-specific cell is material, but at least one scenario-specific cell is inconclusive or detectable below the bound.
- `H48-RECOMMENDED` if any pooled P1 interval is not bounded or any scenario-specific P1 cell is material.
- `HETERO-DESCRIPTIVE-ONLY-PENDING-REDESIGN` if identity, completeness, model stability, or fixed-schedule checks fail.

These rules concern precision for estimating and adjusting secondary order effects. They do not make the supplemental pilot a formal efficacy study and do not authorize a formal campaign.

## Failure and preservation rules

- All pre-measurement static/unit defects may be repaired only in a new version or verification attempt while preserving failed evidence.
- Once the first measured process starts, any error fails closed. The root is preserved and may not be resumed, retried, topped up, merged, or reinterpreted.
- No optional stopping is allowed. All 96 mirrored pairs are required for a successful pilot.
- Every process, block plan, sample, manifest, result, checkpoint, and analysis output is hashed.
- The pilot root is `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v5-gate13r-pr1b-order-effect`; the path is retained under the proven Gate 12R runner containment base but has an independent Gate 13R-PR1B identity.
- The reserved future formal root `Research/FormalRuns/Gate13R_RQAligned/v1` must remain absent.

## Stopping state

After analysis and final audit, work stops with a non-formal readiness recommendation. No formal config, formal schedule, formal root, formal execution receipt, Gate 13R campaign, or Gate 14R run may be created.
