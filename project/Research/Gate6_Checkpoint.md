# Gate 6 Checkpoint — Independent Replication and Statistical Aggregation Complete

Completed: 2026-10-04 (Asia/Shanghai)

## Implemented

- `Assets/_Scripts/Research/Analysis/PlanningReplicationAggregator.cs`
  - strict replication identity and fixed-start workload-shape validation;
  - stable mean, median, nearest-rank p95, sample standard deviation, standard error, and two-sided Student-t 95% confidence interval;
  - exact t critical values through 30 degrees of freedom and a documented higher-df approximation;
  - explicit deterministic search-work consistency reporting.
- `Assets/_Scripts/Research/Editor/ResearchReplicationAggregateCommand.cs`
  - headless Unity aggregation from an explicit request file;
  - UTF-8 validation, schema/algorithm checks, and create-new aggregate output.
- `Research/Run-PlanningReplication.ps1`
  - one fresh Unity process per repetition plus a separate aggregation process;
  - unique child ids/directories, no-overwrite enforcement, immediate child hash validation, one-fingerprint/one-algorithm enforcement, and a hashed group manifest.
- `Research/Scenarios/`
  - three committed canonical fixtures covering static weighted four-way, sparse/same-tick dynamic four-way, and strict-corner eight-way workloads;
  - generated `catalog.json` with source hashes, semantic fingerprints, structural counts, and deterministic A*-R work counts.
- `Research/Replication_Protocol.md`
  - replication semantics, formulas, limitations, output layout, and interpretation boundary.

## Verification results

- Replication statistics: passed, 26 assertions, compiler-error signatures 0, runtime and Editor assemblies current.
- Scenario catalog: passed, 28 assertions across 3 canonical fixtures; every plan succeeded.
- End-to-end replication pipeline: all 19 audit categories passed.
  - 3 independent child Unity processes and 1 aggregation Unity process;
  - 51 JSONL records total: 39 planner operations, 9 lifecycle records, 3 workload results;
  - output reuse refused with nonzero exit status, and the retained group manifest remained unchanged.
  - unauthorized `D*L` selection and a one-repetition request both failed before creating output.
- Current-code aggregate revalidation: passed; the stricter final aggregator reproduced the retained aggregate byte-for-byte with SHA-256 `41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95`.

## Final retained fixture

Directory: `Research/Verification/Gate6_ReplicationFixture_Final`

- Group id: `gate6-replication-final`.
- Algorithm: `A*-R`.
- Scenario: `dynamic-corridors-sparse-v1`.
- Repetitions: 3.
- Scenario source SHA-256: `7a99bd229df801aafba8e018769c8a7fe3022852b40025b2e48267f3495a2634`.
- Scenario semantic fingerprint: `85df1443b080ad83f2fb397157bdc185fb0113b473eb1ce853bff86d3764c450`.
- Group manifest SHA-256: `f7d20028012c631f455cff67a2612e9c8d9333d1f189a9e7d0c5b57f1a79ce52`.
- Aggregate SHA-256: `41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95`.
- Aggregate outcome: 24/24 successful plans, 12 repair acknowledgements, 0 failed/no-path/invalid/budget-exceeded plans.
- Deterministic work per run: 592 processed nodes/cells, 102 expanded nodes, 231 relaxed edges, 0 repaired cells; consistent across all repetitions.
- Plan success rate: 1.0 in every run; operation budget-overrun rate: 0.0 in every run.

The three-run evidence is a pipeline-validation fixture, not a claim that three repetitions are an adequate final scientific sample size.

## Scope preserved

- Original scripts, original scenes, prefabs, packages, and project settings were not intentionally modified.
- The Gate 5 retained fixture remains unchanged.
- The replication pipeline allowlist contains only implemented `A*-R`.
- No movement simulation, arrival metric, collision avoidance, C-FF, D* Lite, or IDFF was implemented.

## Next safe decision point

Gate 6 completes the non-algorithm experimental infrastructure requested after Gate 5. Before adding another planner, define and authorize that algorithm's exact state, graph/cost semantics, update semantics, tie-breaking, metrics, and independent oracle tests. D* Lite and IDFF still require explicit user authorization.
