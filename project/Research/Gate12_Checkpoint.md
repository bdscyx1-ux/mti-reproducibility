# Gate 12 Checkpoint — Isolated Pilot, Noise and Candidate Sample Size

Saved: 2026-10-05 (Asia/Shanghai)  
Status: complete for the authorized non-formal Gate 12 scope  
Authorization: explicitly granted by the user for one retry  
Gate 13 status: not started, not authorized, and blocked  
Formal results produced: none

## Scope completed

Gate 12 verified and archived the prior stopped `v1`, reran the frozen 63-assertion analysis regression and validation-only environment preflight, then executed exactly one create-new isolated non-formal pilot. It analyzed only the 256 measured samples, generated the four preregistered family sample-size candidates and budget projections, and stopped. No Gate 13 command, directory, process, sample, or formal result was created.

Original scripts, original scenes, the Gate 10 contracts, and the Gate 11 retained bundle were not modified.

## Prior-attempt archive

The stopped second attempt was verified before and after its move from `Research/PilotRuns/Gate12/v1/` to `Research/PilotRuns/Gate12/v1-failed-warmup-attempt2/`:

- files: 103 before and 103 after;
- bytes: 14,187,382 before and after;
- ordered aggregate SHA-256: `b52ee8f13c9b96edd2f0ab83f4969161ef5b257d1543588ec9608877086dc500` before and after;
- preserved intact: true;
- warm-up retained: 16/16 successful, measured samples retained: 0;
- move receipt: `Research/PilotRuns/Gate12/Gate12_Attempt2_MoveReceipt.json`;
- move-receipt SHA-256: `ce38bc25176acfc52d41542200571cb2a9822ac739d8615523a20c3716d49e76`.

The first stopped attempt remains at `Research/PilotRuns/Gate12/v1-failed-pre-sample-attempt1/`. Neither failed attempt contributed observations to the successful pilot analysis.

## Frozen identities and preflight

| Item | SHA-256 / result |
|---|---|
| Gate 12 specification | `29e6ca0de24b10f4a3a679378a353f9ae1821b130d1218f298591d2e89878b7c` |
| Gate 12 test design | `c8f71a54f9c73f936e3ddfeff6d4212bd48fb495847b9185a69adf720226e199` |
| Gate 12 machine-readable plan | `cc63505f444223c06a7f69a979c6a0d2e7f0d29e8217d910fe46b61db5618ce4` |
| Analysis module | `96194e77239ad1e842d6ccacd2ffc870afdf8d3a2701144ae05dadeb472fe676` |
| Pilot runner | `bf45cebf1b04a73f1d3ca4cbdc6375f3aab00b9979e129145ac27e91e62cb025` |
| Analyzer | `6aab2f34713ca929ca184bdda2238defedf022f2a39f050959aed02194b91a65` |
| Gate 11 bundle manifest | `ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e` |
| Gate 11 ordered bundle aggregate | `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88` |
| Analysis unit regression | 63/63 passed |
| Validation-only preflight | passed |

Preflight recorded AC power online, the frozen high-performance power scheme, sufficient memory and initial output-drive capacity, acceptable CPU load, the expected Unity executable identity, no running Unity process, no Unity lockfile, and exact frozen hashes. Temperature telemetry was unavailable and remained the preregistered advisory-only condition; it was not silently imputed.

## Pilot execution

Successful output root: `Research/PilotRuns/Gate12/v1/`

- 1 warm-up campaign, 4 complete Williams blocks, 16 independent Unity processes;
- 12 measured campaigns, 256 independent Unity processes;
- 272 total Unity processes;
- 16 warm-up samples excluded from all noise and sample-size calculations;
- 256/256 measured samples retained;
- every campaign was position-balanced and ordered-predecessor-balanced;
- zero hard timeouts, zero monitoring anomalies, zero technical invalidities, and zero automatic retries;
- zero compiler-error signatures in 272 Unity logs;
- outer pilot wall time: 4,225.1154783 seconds, approximately 70.42 minutes;
- pilot manifest SHA-256: `638ac2e3fe243212ef031bdbed4c06394447e055c4d080be370357c41122e18a`;
- analysis manifest SHA-256: `c8b6586bcc59d7ce1fc332a490cada73ee69052ef5abcc65fe2b3b90cdff7699`.

`pilot-checkpoint.json` intentionally remains the runner's terminal hand-off state `pilot-completed-analysis-pending`; the subsequently written `analysis-manifest.json`, this checkpoint, and the final audit close the analysis stage without rewriting the raw runner checkpoint.

## Candidate formal sample sizes

The primary endpoint is `dynamicHandlingMillisecondsPerScheduledEvent`. For each preregistered family, the analysis takes the maximum valid scenario-by-algorithm cell sample standard deviation on the natural-log scale and applies:

```text
n_raw = ceil((1.96 × sigma_log / ln(1.05))²)
required_n_formal = next multiple of 4 at or above max(30, n_raw)
candidate_n_formal = min(100, required_n_formal)
```

The independently recomputed results exactly match the frozen analyzer:

| Family | Governing cell | `sigma_log` | `n_raw` | Required `n_formal` | Reported candidate | Precision status |
|---|---|---:|---:|---:|---:|---|
| P1 `D*L` vs `A*-R`, shared | `four-algorithm-shared-goal-v1::core-r01-s1-shared::D*L` | 0.3371608505 | 184 | 184 | 100 | blocked — amendment required |
| P2 `D*L` vs `A*-R`, heterogeneous | `per-agent-heterogeneous-goal-v1::core-r01-s1-hetero::A*-R` | 0.5896465874 | 562 | 564 | 100 | blocked — amendment required |
| P3 `IDFF` vs `C-FF`, shared | `four-algorithm-shared-goal-v1::core-r01-s1-shared::IDFF` | 0.3266133748 | 173 | 176 | 100 | blocked — amendment required |
| P4 `IDFF` vs `C-FF`, grouped | `grouped-field-heterogeneous-goal-v1::core-r02-s1-hetero::IDFF` | 0.3408731499 | 188 | 188 | 100 | blocked — amendment required |

Every family contains eight complete cells with eight measured repetitions per cell, for 64 measured observations per family. The displayed candidate value `100` is only the frozen cap display value. It does **not** satisfy the 5% precision rule for any family and must not be represented as an approved formal sample size.

## Runtime and storage feasibility

Observed outer-campaign costs, recomputed independently:

- median wall time per Unity process: 15.3497852781 seconds;
- nearest-rank p95 wall time per Unity process: 16.1797191188 seconds;
- median output per process: 2,201,276.125 bytes;
- nearest-rank p95 output per process: 3,516,371.8125 bytes.

Projection using the capped display value of 100 for all four families:

| Quantity | Projection |
|---|---:|
| Unity processes | 21,200 |
| Median wall time | 90.3932 hours |
| p95 wall time | 95.2806 hours |
| Median output | 43.4621 GiB |
| p95 output | 69.4274 GiB |
| H: free before analysis | 69.3820 GiB |
| p95 projected headroom | -0.0454 GiB |

The capped time projection is below the frozen 168-hour technical limit, but storage fails: it does not leave the required 20 GiB and would slightly exceed the recorded free space even before reserving that headroom.

Projection using the uncapped precision requirements:

- 54,624 Unity processes;
- p95 wall time 245.5003 hours, above 168 hours;
- p95 output 178.8869 GiB.

Operational pilot totals were 92,160 plan operations and 1,280 repair operations. There were zero budget-exceeded operations, zero `NoPath` plans, and zero budget-exceeded plans. The retained 20,720 invalid plans and 1,088 failed plans are algorithmic outcomes from the frozen workload, not technical-invalidity exclusions; the frozen rule correctly retains them.

## Gate 13 decision

Gate 13 readiness is:

```text
blocked-precision-cap-and-storage-versioned-amendment-required
```

The block has three independent parts:

1. all four family precision requirements exceed the frozen cap of 100;
2. even the capped projection fails the 20 GiB storage-headroom requirement;
3. the uncapped projection exceeds both the 168-hour technical wall-time boundary and available storage.

The user's Gate 13 time/financial budget remains unset. Gate 13 is neither technically ready nor authorized. A future step must first freeze and test a versioned amendment covering the precision target/cap, family design, storage destination/retention, and acceptable time budget. Only after that amendment passes may the user separately authorize a formal campaign.

## Final independent audit

`Research/Verification/Run-Gate12FinalAudit.ps1` independently reloaded the raw workload results rather than calling the production analysis module. Its final result passed all 24 completion checks:

- original baseline: 24/24, zero mismatch;
- Gate 11 retained bundle: 56 artifacts plus manifest, 57 files, exact before/after aggregate;
- Gate 2–11 retained summaries: 14/14 passing;
- campaigns: 13/13 complete and balanced;
- child identities/hashes: 272/272 valid, 272 unique run IDs;
- independent family noise/sample-size recomputation: exact match for P1–P4;
- independent runtime/storage/operation recomputation: exact match;
- PowerShell: 41 scripts parsed;
- JSON: 1,478 files parsed;
- JSONL: 321 files and 98,155 lines parsed;
- Unity logs and per-run wrappers: 272/272 clean;
- live Unity processes: zero;
- `Temp/UnityLockfile`: absent;
- Gate 13/formal output: absent.

Final-audit script SHA-256: `692c7f3a13ff7aa847780ee803e17790e4a572a53edbe366d364b79608f4ef01`.  
Final-audit summary SHA-256: `87a5d93dead6dc367ab0716ad2e4e2239570fc42577be978d0f0378ca14f78c8`.

The first audit pass exposed a Windows PowerShell 5.1 code-page false positive when `ParseFile` read an existing UTF-8-without-BOM script. The audit was corrected to explicitly decode UTF-8 and use `ParseInput`, then rerun from the beginning; the passing summary above is the final result. No experiment artifact was changed by that audit repair.

The hashed `Gate12_Pilot_Validation_Report.md` contains a presentation-only mojibake artifact for several en-dash characters because Windows PowerShell 5.1 decoded the UTF-8 analyzer source through its legacy code page. Numeric JSON, identifiers, formulas, hashes, and decisions are unaffected. The hashed report was left unchanged; this UTF-8 checkpoint is the clean human-readable interpretation.

## Material Passport

- Origin skill/mode: ARS experiment validation.
- Verification status: `VERIFIED` for Gate 12 execution integrity, raw-to-report arithmetic, and authorization boundaries.
- Source: `Research/PilotRuns/Gate12/v1/`, frozen Gate 12 plan, and Gate 11 retained bundle.
- Experimental unit: one independent Unity Editor process executing one algorithm/scenario observation.
- Included: all 256 measured observations from the successful `v1` only.
- Excluded by preregistration: 16 thermal warm-up observations.
- Excluded for technical invalidity: none.
- Transformation: natural logarithm of the positive primary endpoint within each scenario-by-algorithm cell.
- Variance estimator: Bessel-corrected sample standard deviation; family estimator is the maximum complete-cell value.
- Precision target: two-sided normal critical value 1.96 and relative half-width 5%, rounded upward to a complete 4-run Williams cycle.
- Environment sensitivity: timing and output-size projections are specific to the recorded machine, Unity 2022.3.30f1c1, power state, background state, and drive availability on 2026-10-05.
- Reproducibility verdict: deterministic identities and analysis arithmetic are reproducible from retained artifacts; wall time and allocation remain environment-sensitive.
- Interpretation boundary: this pilot estimates variability and feasibility. It does not establish algorithm superiority, statistical significance, or a formal campaign result.

## Statistical fallacy scan

Coverage: 11/11 types checked. No load-bearing fallacy was detected for the permitted Gate 12 claims.

| Fallacy | Result for this checkpoint |
|---|---|
| Simpson's paradox | No aggregate direction or algorithm-effect claim is made; family/cohort/cell structure remains separate. |
| Ecological fallacy | No group-level result is generalized to individual agents. |
| Berkson's paradox | The deterministic balanced pilot subset is used only for noise/feasibility estimation; no selected-sample association is claimed. |
| Collider bias | No covariate adjustment or conditioned causal model is fitted. |
| Base-rate neglect | No diagnostic sensitivity/specificity inference is made. |
| Regression to the mean | No extreme-score pre/post improvement claim is made. |
| Survivorship bias | All measured samples and algorithmic failures were retained; technical exclusions were zero. |
| Look-elsewhere effect | All four preregistered families and all complete cells are reported; no significance search was performed. |
| Garden of forking paths | Subset, endpoint, transform, estimator, formula, cap, exclusions, and stopping rule were frozen before production execution. |
| Correlation implies causation | No observational association is interpreted causally. |
| Reverse causality | No directional causal relation is inferred. |

## Preservation and next-session boundary

- Treat `Research/PilotRuns/Gate12/v1/` as immutable successful pilot evidence.
- Treat both failed-attempt archives and their move receipts as immutable diagnostic evidence.
- Do not edit the Gate 11 `Research/FormalScenarios/v1/` bundle in place.
- Do not modify original scripts or original scenes.
- Do not reinterpret candidate 100 as precision-satisfying.
- Do not start Gate 13 from this checkpoint.
- The next permissible research action is specification/test design for a versioned Gate 13-readiness amendment, and it requires explicit user authorization before implementation or execution.

## Verification command

Run with interactive Unity closed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate12FinalAudit.ps1"
```

The audit is read-only except for replacing its own `Gate12_FinalAudit.summary.json` result.
