# Gate 13R-PR1B v2 Memory-Observable Balanced Mirrored Order-Effect Pilot Specification

Status: `PREREGISTERED / NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## Scope

This specification authorizes one entirely new supplemental pilot after PR1B attempt 1 terminated at its former per-sample 128 MiB gate. Attempt 1 remains immutable, terminal, and excluded. No observation from that attempt enters this pilot or its estimators.

The scientific design from PR1B v1 is unchanged: the anchors are `core-r01-s1-hetero`, `core-r07-s2-hetero`, and `goal-count-g32-hetero`; each has the existing per-agent and grouped-field cohorts; each measured scenario has block ordinals 1–32; every mirrored diagnostic pair contains contiguous AB and BA superblocks, four fresh Unity processes, and eight samples. Odd/even block ordering and scenario-wave rotation remain frozen. There are 96 measured mirrored pairs, 384 measured processes, and 768 measured samples, preceded by 12 excluded warm-up processes and 24 excluded samples.

## Memory observability and eligibility

Before any threshold decision, each sample atomically writes `memory-gate-evaluation.json`. The artifact records sample/block/scenario/cohort/algorithm/position/predecessor identity; before, raw-after-workload, and after-cleanup managed/working-set/private counters; GC counts; PID, process start, process age and timestamps; sample and block deltas; all thresholds; and the verdict/reason code. Threshold failures must reference its path and SHA-256 from sample failure, block failure, and checkpoint artifacts.

The complete two-sample Williams-block process is the independent unit. The frozen v2 policy is:

- sample retained managed growth at or below 128 MiB: `PASS`;
- above 128 MiB and at or below 256 MiB: `MEMORY-ALERT-128MIB`, continue and retain the observation;
- above 256 MiB: immediate hard failure, with no later sample;
- complete-block retained managed net growth above 256 MiB: hard failure;
- complete-block working-set or private-memory growth above 512 MiB: hard failure.

Exact-threshold values pass. Missing, non-finite, mixed-process, temporally inconsistent, non-positive, GC-inconsistent, overflowing, or non-durably-written telemetry fails closed. Full GC boundaries, per-sample fresh state, planner reset, logger disposal, structural exact-match, hashes, provenance, Williams order, and one-block-per-fresh-process remain required.

The 128 MiB signal is not an exclusion rule. All eligible alert observations remain in the primary order-effect analysis. A no-alert subset is reported only as a labelled sensitivity analysis and may not replace the all-eligible-block result. Alert incidence and carryover are reported by scenario, cohort, algorithm, position, predecessor, process age, and wave.

## Frozen estimands

P1–P5, C1–C4, `D = logRatio_AB - logRatio_BA`, two-sided 95% intervals, the ±`log(1.10)` diagnostic bound, 20,000 complete-mirrored-pair bootstrap replicates with seed 13012026, and equal-scenario pooled weighting remain unchanged. P1 remains the order-diagnostic decision endpoint for this non-formal pilot. This pilot cannot establish formal algorithm superiority.

## Execution and stopping

Pre-pilot validation uses a fresh v9 verification root and must pass parser/schema/static/unit, Unity compile, in-process PSAPI versus independent CIM telemetry, memory-policy boundaries, positive mirrored blocks, intentional fail-closed behavior, independent-process repeatability, cold structural control, retained 63/63 regression, hashes/provenance, and validation-only audit.

Only then may the fresh v6 pilot root be created. Execution is strictly serial. Once measured execution starts, any hard failure preserves evidence and terminates the attempt with no retry, resume, top-up, merge, or optional stopping. The reserved formal root must remain absent.

## Explicit exclusions

No Gate 13R formal config/root/receipt/timing campaign, Gate 14R run, OBS capture, Playable timing sample, original game-script change, original scene change, or formal inference is authorized.
