# Gate 10 Checkpoint — Four-Algorithm Fairness and Unified Campaign Layer

Saved: 2026-10-05 (Asia/Shanghai)  
Status: complete  
Authorization: explicitly granted by the user  
Formal campaign status: not started and not authorized

## Scope completed

Gate 10 froze and implemented the comparison contract shared by `A*-R`, `D*L`, `C-FF`, and `IDFF`. It did not add a fifth planner, alter any original script or original scene, register the validation scenario in the formal scenario catalog, choose a publication sample size, or launch a formal long-running experiment.

The frozen specification is `Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md` (`four-algorithm-fairness-v1`, SHA-256 `42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd`). The test design is `Research/Gate10_Fairness_Test_Design.md` (SHA-256 `6ab9b5b47783f727a48d55a9dc3b8ef3a360438da874e6233aa2f0af4d646d38`). Both files were written before the production implementation; their write times precede all Gate 10 production-file creation times and their hashes remain unchanged.

## Frozen fairness semantics

- `four-algorithm-shared-goal-v1`: one distinct shared goal; all four algorithms are comparable.
- `per-agent-heterogeneous-goal-v1`: heterogeneous per-agent goals; only `A*-R` and `D*L` are comparable.
- `grouped-field-heterogeneous-goal-v1`: heterogeneous goals grouped into explicitly counted fields; only `C-FF` and `IDFF` are comparable.
- A dynamic phase includes every accepted change at one simulation tick plus all fixed-start post-tick plan queries. Reporting only change acknowledgement, only repair, or only query time is invalid.
- Common metrics retain totals and per-agent/per-event normalization. `expandedNodes`, `relaxedEdges`, and `repairedCells` remain algorithm-native fields and are not silently treated as interchangeable work units.
- Every result and manifest records the fairness protocol, algorithm specification, algorithm implementation, workload specification, goal cohort, comparison cohort, state ownership model, state/field counts, and SHA-256 identities.
- The four-algorithm execution order uses the frozen Williams cycle:
  1. `A*-R`, `D*L`, `IDFF`, `C-FF`;
  2. `D*L`, `C-FF`, `A*-R`, `IDFF`;
  3. `C-FF`, `IDFF`, `D*L`, `A*-R`;
  4. `IDFF`, `A*-R`, `C-FF`, `D*L`.
- One schedule entry launches one Unity Editor process. No process carries samples for multiple algorithms.
- Aggregation rejects mixed fairness protocol, specification, implementation, workload, cohort, state-model, unit, or native-metric identities.

## Implementation

- `Assets/_Scripts/Research/Experiments/PlanningFairnessContracts.cs` centralizes the four exact algorithm profiles, cohort classification, state/field counts, and provenance validation.
- `DeterministicPlanningWorkloadRunner` now emits fairness/provenance fields, initialization/initial-plan/dynamic work decomposition, algorithm-native work totals, managed allocation, and per-agent/per-event normalization.
- JSONL planner operations now retain expanded, relaxed, and repaired counters.
- `ResearchPlanningBatchCommand` emits schema-2 manifests for fairness-aware runs and hashes the exact specification and implementation sources.
- `PlanningReplicationAggregator` validates schema-1 fairness identities while remaining compatible with legacy fairness-schema-0 results.
- `Run-PlanningReplication.ps1` enforces homogeneous fairness identities for new groups.
- `Research/Run-FairPlanningCampaign.ps1` dispatches a Williams-balanced cohort as independent create-new Unity child processes and emits a hashed campaign manifest. It is a pipeline launcher, not authorization for a formal campaign.

## Runtime and rejection verification

`Run-Gate10FairnessVerification.ps1` passed with:

- 95 assertions;
- four exact algorithm profiles;
- four shared-goal and four heterogeneous-goal classification cases;
- six plan operations, three repair operations, and two dynamic phases in the scripted accounting case;
- 550 total and 490 dynamic processed work units with arithmetic closure;
- legacy fairness-schema-0 aggregation accepted;
- seven mixed-identity classes rejected.

The first compile artifact, `Gate10_Fairness_InitialCompile`, intentionally remains as diagnostic history. Its first Asset Database pass saw the new consumer before Unity had imported the new contract source and reported three missing-type errors. Unity then imported the source and generated its `.meta`; `Gate10_Fairness_Compile_AfterImport`, `Gate10_RuntimeCompile`, and final `Gate10_FullRegression_Compile` all passed with zero compiler-error signatures and current runtime/editor assemblies. The superseded first-pass log is not evidence of the final compiled state.

## Retained campaign pipeline fixture

The research-only scenario is `Research/Verification/Gate10_SharedGoal.scenario.json`:

- scenario id: `gate10-shared-goal-v1`;
- source/canonical SHA-256: `98981cd9504d1132099f1812209125c4110b2d3987c581e6ff1696c22d5985a3`;
- semantic fingerprint: `cad9ece799dc0b854647be6fe44c3a5cb59caaf3bf23c704505aed164ccc94ef`.

The retained fixture is `Research/Verification/Gate10_FairCampaignFixture_Final/`. It is explicitly marked `campaignKind = gate10-pipeline-validation` and `formalCampaign = false`. Its campaign-manifest SHA-256 is `4d9d61b15f2e375909c541f6070bd405624e90ae516e6ecb7d7b4ebb7585e987`.

`Run-Gate10CampaignPipelineVerification.ps1` passed all 12 check categories:

- 16 independent Unity child processes, four per algorithm;
- every algorithm appears once in each of four positions;
- all 12 ordered predecessor pairs occur exactly once;
- every child manifest, canonical scenario, workload result, JSONL file, Unity log, and wrapper summary exists and matches its recorded hash/identity;
- 272 JSONL records with continuous per-run sequences: 208 planner-operation, 48 lifecycle, and 16 final workload records;
- 128/128 plans succeeded, 64 repair operations completed, and zero budget-overrun operations occurred;
- dynamic decomposition and per-agent/per-event normalization close arithmetically;
- reusing the retained output directory is rejected without changing the manifest;
- a two-block four-algorithm request is rejected before output creation because it is not a complete balance cycle.

These 16 samples validate dispatch, identity, logging, balance, and failure guards. They are not a publication sample size and must not be interpreted as the Gate 13 formal campaign.

## Backward compatibility

The current compiled aggregator regenerated all four legacy aggregates from their original Gate 6–9 requests. Each output is byte-for-byte identical to its retained aggregate:

| Historical gate | SHA-256 |
|---|---|
| Gate 6 `A*-R` | `41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95` |
| Gate 7 `D*L` | `40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd` |
| Gate 8 `C-FF` | `b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620` |
| Gate 9 `IDFF` | `a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac` |

`Run-Gate10LegacyCompatibilityVerification.ps1` passed all three check categories: all four historical formats accepted, all four outputs byte-identical, and all four Unity aggregation logs clean.

## Full regression and preservation

- Gate 1 final Unity compile: exit code 0, zero compiler-error signatures, current runtime and editor assemblies.
- Gates 2–9 algorithm, scenario, workload, batch, statistics, catalog, replication, and final audits: passed.
- Historical final-audit scope checks now explicitly permit exactly four formal planners plus the named Gate 2 and Gate 10 test doubles; there is no additional formal planner.
- Frozen baseline: 24 entries checked, zero mismatches.
- Gate 10 final audit: all 13 categories passed; 29 PowerShell scripts, 210 JSON files, and 33 JSONL files parsed with zero failures.
- Unity processes: zero; `Temp/UnityLockfile`: absent.
- Original archive remains `H:\DDM_Final_Project_Original.zip`, SHA-256 `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`.
- Original scripts and original scenes were not modified.
- Gate 5–9 retained fixtures and prior current-code revalidation artifacts were not overwritten.

## Next authorization boundary

Gate 10 is complete. Gate 11 is not authorized. The next gate must freeze the formal scenario matrix and preregistration rules before any pilot or formal campaign is run. Gate 12 pilot/noise/sample-size work and Gate 13 formal execution remain separate later authorizations.
