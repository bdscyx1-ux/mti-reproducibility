# Gate 13 Readiness Amendment Checkpoint

Saved: 2026-10-06 00:00 (Asia/Shanghai)  
Status: versioned precision/cap/schedule/storage/usage-policy specification and test design passed; nonexecuting implementation pending  
Gate 13 formal campaign: not started and not authorized  
Unity invoked in this stage: no  
Formal timing samples produced: zero

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T23:09:58+08:00
- Verification Status: SPECIFICATION-VERIFIED
- Version Label: gate13_readiness_amendment_checkpoint_v1

## User-owned decision

The user selected and this amendment now freezes:

- a 10% relative 95% CI half-width target for the primary log endpoint;
- the byte-identical Gate 11 matrix and all 53 scenarios / 212 eligibility cells;
- a maximum of 148 samples per algorithm × scenario cell;
- a mandatory storage recheck immediately before any future formal start;
- no project-defined Codex usage ceiling, fixed reserve, weekly budget, percentage stop line, or usage-conservation rule;
- an explicit stop before Gate 13 execution in the current stage.

The user briefly proposed using all weekly usage remaining at Gate 13 start and reported a contemporaneous 89% remaining snapshot, then cancelled all usage limits before the updated audit. That proposal is retained only as inactive decision history and is not an execution ceiling. The active no-limit policy cannot remove platform-enforced limits and does not authorize credits, resets, formal implementation, or execution.

This decision authorized recording and verifying the readiness amendment only. It did not authorize formal implementation or execution.

## Frozen formal sample schedule

Independent recomputation from the Gate 12 `sigma_log` values produced:

| Family | `n_raw` at 10% | Required | Scheduled |
|---|---:|---:|---:|
| P1 `D*L` vs `A*-R`, shared | 49 | 52 | 52 |
| P2 `D*L` vs `A*-R`, heterogeneous | 148 | 148 | 148 |
| P3 `IDFF` vs `C-FF`, shared | 46 | 48 | 52 |
| P4 `IDFF` vs `C-FF`, grouped | 50 | 52 | 52 |

P3 is scheduled at 52 rather than its minimum 48 because P1 and P3 share the mandatory four-algorithm cohort. Using 52 for all four algorithms preserves 13 complete Williams cycles per shared scenario. A 48/52 split would require an unauthorized partial/sub-cohort and is therefore rejected before formal execution.

Frozen campaign scale:

- shared cohort: 32 scenarios × 4 algorithms × 52 = 6,656 processes;
- per-agent heterogeneous cohort: 21 × 2 × 148 = 6,216 processes;
- grouped-field heterogeneous cohort: 21 × 2 × 52 = 2,184 processes;
- total: 74 scenario/cohort campaigns and 15,056 independent Unity processes.

## Budget and storage boundary

Gate 12 observed-cost projection for 15,056 processes:

- median wall time: 64.1962 h;
- p95 wall time: 67.6672 h, below the 168 h technical boundary;
- median output: 30.8663 GiB;
- p95 output: 49.3065 GiB / 52,942,494,009 bytes;
- retained free-space reserve: 20 GiB / 21,474,836,480 bytes;
- mandatory minimum free space immediately before launch: 74,417,330,489 bytes / 69.3065 GiB.

The updated audit snapshot recorded H: free space as 162,195,853,312 bytes / 151.0567 GiB, which exceeded the threshold by 87,778,522,823 bytes / about 81.75 GiB. This is a passing snapshot only. The same raw-byte comparison must be repeated after a future explicit formal authorization and before creation of `Research/FormalRuns/Gate13/v1/`.

The wall-clock and storage projections above are technical experimental safeguards, not Codex usage limits. They remain active even though all project-defined Codex usage limits have been removed.

## Static audit result

`Research/Verification/Run-Gate13ReadinessAmendmentAudit.ps1` passed 20/20 checks:

- four-family 10% formula recomputation matched;
- P3 shared-cohort harmonization and 15,056-process schedule matched;
- budget and byte-level storage threshold recomputed exactly;
- Gate 11 56 artifacts plus manifest and ordered aggregate matched;
- original baseline 24/24 matched;
- Gate 12 final audit remained passing;
- the active policy has no project-defined Codex usage ceiling or fixed-window stop threshold, while the superseded 89% proposal remains inactive;
- PowerShell parsing passed;
- no formal authorization flag, output root, Unity process, or Unity lock existed.

Frozen artifact identities:

| Artifact | SHA-256 |
|---|---|
| Amendment specification | `aea5abcdf34fac5a9e705c8824f548805572eb5774e4e22dad5da40043eb7a8b` |
| Amendment test design | `821081025e4d6aab243c4594220a7dd2e56b879755e5de61456782aa6664a551` |
| Machine-readable amendment | `1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2` |
| Audit script | `f2a14a1415ec39fc9a4280fea7af2f566a5a39e3c4a904bbd11adc8fd9479c0c` |
| Passing audit summary | `0a2ad1463d67db694b2d4796c6ad69773ca4db23813d9c0bf022e0cfa7dc8eec` |

The first audit attempt failed before any execution because the expected Gate 12 budget hash contained one transcription error and Windows PowerShell 5.1 misread Chinese string literals in the audit script. Both audit-only defects were corrected; the audit restarted from the beginning and the passing summary above is the terminal result. No frozen input or experimental data changed.

## Remaining boundary

Current status is:

```text
readiness-amendment-v1-spec-and-tests-passed /
nonexecuting-implementation-not-authorized /
gate13-formal-campaign-not-started-not-authorized
```

The current Gate 10 runner still deliberately enforces `Blocks <= 100`. The next possible stage is a separately authorized, nonexecuting readiness implementation that creates a research-only cap-148 orchestration/config and launch-time preflight, then runs static/unit/regression and validation-only checks. It must not create the formal output root or start Unity timing runs.

Even after that implementation passes, Gate 13 execution requires a later explicit user authorization. There is no project-defined Codex usage budget to satisfy; the acceptable wall-clock schedule remains `not-explicitly-set` and must be addressed before formal start.

## Preservation boundary

- Do not modify original scripts or original scenes.
- Keep `Research/FormalScenarios/v1/` byte-identical.
- Keep `Research/PilotRuns/Gate12/v1/` and both failed-attempt archives byte-identical.
- Do not modify the current Gate 10 runner during this completed specification-only stage.
- Do not reintroduce a project-defined Codex usage ceiling or percentage stop line unless the user later issues a new explicit instruction.
- Do not set any formal/Gate 13 execution flag true.
- Do not create `Research/FormalRuns/Gate13/v1/` without a future explicit formal authorization.

## Read-only verification command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate13ReadinessAmendmentAudit.ps1" -ProjectPath "H:\DDM_Final_Project"
```
