# Gate 11 Checkpoint — Formal Scenario Matrix and Preregistration

Saved: 2026-10-05 (Asia/Shanghai)  
Status: complete  
Authorization: explicitly granted by the user  
Gate 12 pilot status: not started and not authorized  
Gate 13 formal campaign status: not started and not authorized

## Scope completed

Gate 11 froze, generated, and independently verified the complete fixed-start planning input matrix. It did not execute a planning workload, retain planner initialization timings as experimental observations, choose a formal numeric sample size, start a pilot, or launch a formal campaign. Original scripts and original scenes were not modified.

The frozen planning specification is `Research/Formal_Scenario_Matrix_and_Preregistration_Specification.md`:

- specification id: `formal-scenario-matrix-v1`;
- generator id: `ddm-formal-scenario-generator-v1`;
- preregistration id: `ddm-planning-preregistration-v1`;
- SHA-256: `498d3ea8549b234ebaac27658ee9be1ad67051f49e71e131e5b013287f28f4f4`.

The frozen test design is `Research/Gate11_Formal_Scenario_Matrix_Test_Design.md`, SHA-256 `bfb124d8ecf80ef15e8fcf391b4f0b51ee1b27b8a03303afa1b12a1062304b58`. Both files were written and audited before production implementation. The post-implementation specification audit confirms their hashes and timestamps remain frozen.

## Frozen-count erratum

Create-new generation exposed an arithmetic contradiction in the frozen shared/heterogeneous subtotal. The detailed family enumeration produces:

- 32 shared-goal files: 16 shared core + 4 grid-scale + 5 agent-scale + 5 footprint-scale + 2 reachability;
- 21 heterogeneous-goal files: 16 heterogeneous core + 5 goal-count;
- 53 total files;
- 128 shared eligibility cells + 42 per-agent heterogeneous cells + 42 grouped-field heterogeneous cells = 212 total cells.

The isolated frozen summary line `33/20` cannot coexist with those detailed factor levels or Gate 10 classification. `Research/Gate11_Frozen_Count_Erratum.md` records the correction; its SHA-256 is `8b252970d9836dfe1732c7c7df7b0fd743de79d341a52c82234999bfa8fe8197`. The original specification and test-design files, the generated scenarios, and the retained bundle manifest were not rewritten. The first wrapper summary that detected the mismatch remains diagnostic evidence; the Unity generation result itself records successful 53/212 creation.

## Deterministic implementation

- `Assets/_Scripts/Research/Scenarios/FormalScenarioMatrixGenerator.cs` implements integer-only SplitMix64 generation and the exact frozen matrix; source SHA-256 `248ee464d4ddbc900b229ff4f86386308f652f229751aaef7cff6e72fbc981cb`.
- `Assets/_Scripts/Research/Editor/Gate11FormalScenarioMatrixCommand.cs` provides separate create-new `Generate` and read-only `Verify` entry points.
- `Research/Verification/Run-Gate11ScenarioMatrixGeneration.ps1` runs the one-time generator in a fresh Unity process.
- `Research/Verification/Run-Gate11ScenarioMatrixVerification.ps1` snapshots every retained bundle file before and after verification and requires byte identity.

Each scenario explicitly materializes every grid cell, every agent start/goal, and every scheduled change. No algorithm consumes the provenance seed at runtime. Shared/heterogeneous core pairs reuse the same seed and have identical grid/event materialization. General changes never touch the protected backbone, starts, or goals; the temporary-disconnection cases use the frozen two-gate barrier transition.

## Retained formal bundle

Bundle: `Research/FormalScenarios/v1/`

- 53 canonical schema-v1 scenario files;
- 1 matrix config with 212 unique eligibility entries;
- 1 preregistration config with `P1`–`P4` and `S1`–`S5`;
- 1 catalog;
- 1 manifest written last;
- 57 files total.

Key identities:

| Artifact | SHA-256 |
|---|---|
| `formal-scenario-matrix.json` | `404df63d38bccd66bb665446e0f2cbf3e5f8c7293f543b3213bde4206435fe9f` |
| `preregistered-analysis.json` | `7e947885c38fcf9307fd9202585dda3b2b5d11334f495428760009a2aa202b5b` |
| `catalog.json` | `53466889b80c5f75aa124e623155a6abaac7ff91a979b7d2490dade0978baa1d` |
| `bundle-manifest.json` | `ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e` |
| ordered bundle aggregate | `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88` |

The manifest also binds the Gate 10 fairness specification at `42a4a843...`, the Gate 4 workload specification at `2af12d33...`, the frozen Gate 11 specification/test design, and the generator source. It records `pilotExecuted = false` and `formalCampaignExecuted = false`.

## Matrix and preregistration state

- Balanced core: 32 files, eight structural rows × two materialized seeds × two goal structures.
- Stress series: grid 4, agent 5, changed-cell footprint 5, goal count 5, reachability 2.
- Shared cohort: all four algorithms, 128 cells.
- Heterogeneous per-agent cohort: `A*-R` and `D*L`, 42 cells.
- Heterogeneous grouped-field cohort: `C-FF` and `IDFF`, 42 cells.
- Primary endpoint: `dynamicHandlingMillisecondsPerScheduledEvent`, analyzed on the natural-log scale and reported as exponentiated ratios with two-sided 95% intervals.
- Primary Holm family: `P1`–`P4`; secondary Holm family: `S1`–`S2`; `S3`–`S5` are descriptive.
- Outliers and algorithmic failures are retained. Only prespecified technical invalidity permits replacement, using the next ordinal and a complete Williams cycle.
- Gate 12 must estimate `sigma_log` and apply `n_raw = ceil((1.96 × sigma_log / ln(1.05))²)`, then the next multiple of four at or above `max(30, n_raw)`, capped at 100. A requirement above 100 blocks Gate 13 pending a versioned amendment.
- Significance- or trend-based early stopping is forbidden.

## Retained-bundle verification

`Run-Gate11ScenarioMatrixVerification.ps1` passed with:

- 1,497,213 assertions;
- 53/53 strict-load, canonical-byte, source/canonical hash, fingerprint, size, full-cell and deterministic-regeneration checks;
- 212/212 eligibility and planner-initialization cases;
- fresh `A*-R`, `D*L`, `C-FF`, and `IDFF` initialization on every scenario, followed by reset and no plan/repair call;
- 265 independent BFS phase states, including exact `true,true,false,true,true` temporary-disconnection sequences;
- exact general-event disjointness and final restoration;
- exact core pairing and factor/stress coverage;
- nine preregistration rows and frozen policy/precision rules;
- 11 negative/tamper categories;
- 57 files before and after, byte-identical;
- unchanged manifest SHA-256 `ea596c8c...64c12e`;
- zero Gate 12/13 execution flags.

## Cross-Gate regression and preservation

- Real Unity runtime/editor compilation passed with current assemblies and zero compiler-error signatures.
- Gate 2 smoke, Gate 3 A*-R, Gate 4 scenario/workload, Gate 6 statistics/catalog, Gate 7 D* Lite, Gate 8 C-FF, Gate 9 IDFF, and Gate 10 fairness behavioral verification all passed.
- Gate 5–9 batch, replication, and final audits passed.
- Gate 10 frozen specification, Williams campaign fixture, legacy compatibility, and final audit passed.
- The Gate 10 campaign fixture remains non-formal and unchanged; no Gate 11 scenario was dispatched through it.
- Frozen original baseline: 24 entries checked, zero mismatches.
- Original archive remains `H:\DDM_Final_Project_Original.zip`, SHA-256 `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`.
- Original scripts and original scenes were not modified.
- Unity process count is zero and `Temp/UnityLockfile` is absent at clean exit.

## Next authorization boundary

Gate 11 is complete. Gate 12 is not authorized. The next permissible phase, only after explicit user authorization, is a non-formal pilot/noise/preflight stage that uses the frozen bundle, keeps pilot output isolated, records the exact machine/power environment, and estimates `sigma_log` for the frozen precision rule. Gate 13 remains blocked until Gate 12 fixes the formal sample count and receives separate authorization.

Do not modify the Gate 11 retained bundle in place. A required correction uses a new versioned specification/generator/output directory. Do not run a Gate 12 pilot or Gate 13 campaign from this checkpoint without explicit authorization.

## Closure commands

Run with interactive Unity closed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate11SpecificationAudit.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate11ScenarioMatrixVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate11FinalAudit.ps1"
```
