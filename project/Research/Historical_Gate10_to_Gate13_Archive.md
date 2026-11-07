# Historical Appendix — Superseded Gate 10–13 Lineage

Status: `HISTORICAL / SUPERSEDED / EXCLUDED FROM ACTIVE GATE10R–13R ANALYSIS`

This appendix separates the former Gate 10–13 lineage from the active Gate 10R–13R plan. Nothing in this file authorizes a retry, resume, merge, reinterpretation, or use of historical timing data in the active 5% block-process analysis.

## H1. Old Gate 10

The former Gate 10 froze the first four-algorithm fairness contract and unified cold-process campaign layer. It passed 95 contract assertions, 16 independent Unity processes, 12/12 campaign checks and byte-identical compatibility checks. Its process unit was not the active one-process-per-Williams-block design, so it remains correctness/infrastructure history only.

## H2. Old Gate 11

The former Gate 11 froze a 53-scenario matrix and 212 eligibility cells, with 1,497,213 assertions and 212 planner initializations. The retained bundle remains immutable, but it is not the active Gate 11R bundle. Active work uses `Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json` instead.

## H3. Old Gate 12

The former cold-process Gate 12 pilot completed 16 excluded warm-ups and 256 measured samples in 272 independent Unity processes; retained regression 63/63 and final audit 24/24 passed. Its cold-process variance, cap-100 feasibility result and candidate sample sizes must not be migrated into the active process-reuse design.

Two earlier Gate 12 failures and the successful `Research/PilotRuns/Gate12/v1/` archive remain immutable evidence. None is an input to active Gate 12R sample-size calculation.

## H4. Old Gate 13 cold-process preparation and campaign attempts

The historical readiness amendment changed that old design to 10% relative precision with cap 148. It planned 74 campaigns / 15,056 independent Unity sample processes and a 74,417,330,489-byte launch gate. The non-executing preparation passed its static, unit, integration and final audits.

Formal attempt 1 failed before formal-root creation because a PowerShell 7 `PSModulePath` polluted the Windows PowerShell 5.1 child environment. It produced zero formal samples.

Formal attempt 2 passed launch preflight and began the cold-process campaign, then was deliberately terminated under the user's authorized design migration. Its boundary was campaign 1 / Williams block 37 / position 4, with 147 completed samples. The entire root is permanently marked `USER-TERMINATED-DESIGN-CHANGE / EXCLUDED_FROM_ANALYSIS / NO-AUTO-RETRY / NO-RESUME / SUPERSEDED-BY-PROCESS-REUSE-DESIGN` and must not be completed or merged.

## H5. Old Gate 13-R2 process-reuse pilots

Gate 13-R2 v1 demonstrated one fresh Unity process per Williams block and completed 45 processes / 108 samples with zero structural mismatch, but failed telemetry/readiness with invalid zero-valued OS memory fields and managed-memory hard errors. It is excluded.

Gate 13-R2 v2 validated native PSAPI/CIM telemetry but failed its block verification entry before its pilot began. It is also excluded.

## H6. Relationship to the active plan

The active lineage restarted at Gate 10R with a 5% precision target, no cap, one fresh Unity process per complete Williams block, block-aware paired analysis and complete Playable coverage. Its authoritative plan is `Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md`.

The active terminal state is Gate 12R passed. Its admissible pilot-planning evidence is `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4`, and its readiness checkpoint is `Research/Gate12R_Readiness_Checkpoint.v1.json`. Gate 13R remains separately unauthorized.

Historical Gate 10–13 artifacts may be cited only to document design evolution, failed safeguards, exclusions and reproducibility decisions. They may not supply active timing estimates, variances, candidate `n_formal`, formal observations or statistical conclusions.
