# Batch Planning Workload Guide

Entry script: `Research/Run-PlanningWorkload.ps1`

This command runs the Gate 4 fixed-start planning microbenchmark through Unity batch mode. It never opens or edits an original scene. The authorized algorithm values are exactly `A*-R`, `D*L`, `C-FF`, and `IDFF`.

## Prerequisites

- Close the interactive Unity Editor for this project.
- Use a strict schema-v1 scenario JSON file. The canonical Gate 4 fixture is available at `Research/Verification/Gate4_Canonical.scenario.json`.
- Keep each output directory unique and empty. The command refuses to mix with or overwrite an earlier run.

## Example

From the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningWorkload.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Verification\Gate4_Canonical.scenario.json" `
  -RunId "astar-reference-001" `
  -Algorithm "A*-R"
```

To run the same workload with the Gate 7 D* Lite planner, use a different run id/output directory and select `D*L`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningWorkload.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -RunId "dstar-lite-reference-001" `
  -Algorithm "D*L"
```

To run the Gate 8 corrected full-recompute flow field, use a shared-goal-compatible scenario and select `C-FF`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningWorkload.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -RunId "cff-reference-001" `
  -Algorithm "C-FF"
```

To run the Gate 9 incremental dynamic flow field, use a shared-goal-compatible scenario and select `IDFF`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningWorkload.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -RunId "idff-reference-001" `
  -Algorithm "IDFF"
```

When `-OutputDirectory` is omitted, output is written to:

```text
Research/Runs/<RunId>/
```

The Unity log and wrapper summary are adjacent to that directory as `<RunId>.Unity.log` and `<RunId>.summary.json`.

## Run directory

- `scenario.canonical.json` — resolved, canonical scenario input;
- `operations.jsonl` — ordered runner lifecycle, planner operation, and final workload records;
- `workload-result.json` — aggregated fixed-start planning result;
- `manifest.json` — source path/hash, semantic fingerprint, output hashes, Unity/runtime identity, timestamps, record counts, and completion state;
- `failure.json` — written only when the batch method fails after the output location has been accepted.

The source SHA-256 identifies exact input bytes. The scenario fingerprint identifies resolved scenario semantics. A noncanonical but semantically equivalent source may therefore have a different source hash and the same fingerprint/canonical hash.

## Interpretation boundary

This is a planning microbenchmark. Every planning phase starts each agent at its scenario-declared start. The result does not contain movement, arrival, collision, crowd, or frame-time measurements. For A*-R, dynamic handling includes version acknowledgement and every full replan after the event tick. For D* Lite, it includes per-agent incremental repair and the subsequent fixed-start queries. For C-FF, it includes an atomic full integration/owner/direction rebuild and the subsequent fixed-start queries. For IDFF, it includes the shared-field incremental consistency repair, dirty-region direction refresh, and subsequent fixed-start queries. A valid C-FF initialization or repair always finishes the scratch rebuild before committing; its rebuild budget is a soft deadline reported after the atomic commit, while a plan-query budget remains a hard deadline. IDFF initialization uses the same soft-deadline convention, but repair and plan budgets are hard and resumable: a pending repair must be completed before a field snapshot or route query is valid. Native work counters have algorithm-specific meaning: C-FF `repairedCells` is the complete number of field slots rebuilt, while IDFF `repairedCells` counts unique cells made consistent for one accepted change set across any interruptions. Compare common totals only under the fairness rules in the overall plan.

Do not label these outputs as full navigation-experiment results.

For multiple independent Unity-process repetitions and statistical aggregation, use `Research/Run-PlanningReplication.ps1` and follow `Research/Replication_Protocol.md`.

## Gate 10 fairness-aware outputs

New runs use manifest schema 2 and workload fairness schema 1. In addition to the original run/scenario/output identities, they record:

- fairness protocol id/path/SHA-256;
- algorithm specification id/path/SHA-256;
- algorithm implementation path/SHA-256;
- workload specification id/path/SHA-256;
- goal cohort and comparison cohort;
- distinct-goal, planner-instance, persistent-state, and shared-field counts;
- planner state model, processed-work unit, and native-metric semantics;
- initialization, initial-planning, and complete dynamic-phase work decomposition;
- per-agent and per-scheduled-event normalizations.

Do not compare algorithms merely because they share a scenario. The result must be authorized by one of the frozen cohorts in `Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md`, and the complete provenance identity must match the intended comparison.

For a balanced multi-algorithm pipeline run, use `Research/Run-FairPlanningCampaign.ps1`. The output directory must be new and empty, and the block count must be a positive multiple of the cohort's algorithm count. For the four-algorithm shared-goal cohort, four blocks form one complete Williams balance cycle:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-FairPlanningCampaign.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Verification\Gate10_SharedGoal.scenario.json" `
  -ComparisonCohortId "four-algorithm-shared-goal-v1" `
  -Blocks 4 `
  -CampaignId "pipeline-validation-example" `
  -OutputDirectory "H:\DDM_Final_Project\Research\Runs\pipeline-validation-example"
```

Each schedule entry starts a separate Unity process. The launcher validates every child manifest, result, canonical scenario and hash before writing `campaign-manifest.json`. Running this command does not turn a fixture into a formal experiment: formal status, scenario membership, repetition count, exclusions and analysis must first be authorized and frozen in Gates 11–13.
