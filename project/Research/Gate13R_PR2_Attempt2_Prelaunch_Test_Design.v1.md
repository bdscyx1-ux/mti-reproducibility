# Gate 13R-PR2 Attempt 2 Prelaunch Test Design v1

Status: `FROZEN-BEFORE-IMPLEMENTATION / VALIDATION-ONLY-UNTIL-FORMAL-COMMIT`

## Hard-gate sequence

No attempt-2 formal root or formal execution receipt may exist during tests
T01–T15. A failure creates versioned evidence and blocks formal launch until a
versioned repair passes the same or stronger tests.

| ID | Gate | Required result |
|---|---|---|
| T01 | Authorization/schema parsing | All new JSON and Markdown identities resolve; analysis and Gate 14R remain unauthorized. |
| T02 | Attempt-1 preservation | 31 files, 3,338,221 bytes, canonical tree hash `026b...4f56`, and 31/31 read-only. |
| T03 | Mechanical C# derivation | Only class identity, `BlockChildRecord.formalCampaign`, and its explicit assignment differ from V2. |
| T04 | PowerShell parsing/binding | Native Windows PowerShell 5.1 and active PowerShell parse module, wrapper, campaign, and preflight scripts; absolute `ProjectPath` binding smoke passes. |
| T05 | Synthetic embedded-field positives | Exactly four unique records with Boolean true pass. |
| T06 | Synthetic embedded-field negatives | Missing, false, string `"true"`, numeric `1`, null, and duplicate-run-ID fixtures all fail closed with stable reason codes. |
| T07 | Receipt/root negative gates | Missing, stale, wrong-root, wrong-attempt, wrong-binding, or reused attempt-1 receipt is rejected; formal root remains absent. |
| T08 | Deterministic schedule/config audit | 74 campaigns, 3,552 processes, 10,176 samples, 1,008 matched superblocks, AB/BA 24/24, order×row 12/cell, and unique identities. |
| T09 | Unity compile/self-tests | New V3 producer compiles; retained research tests and structural controls pass. |
| T10 | Telemetry/memory/lock regression | PSAPI/CIM, managed-memory policy, reset and lock-hygiene contracts remain unchanged and pass. |
| T11 | Full validation-only block rehearsal | One fresh Unity process runs one complete four-algorithm Williams block outside the formal root; wrapper V5 passes. |
| T12 | Rehearsal cross-document audit | Top-level manifest, four embedded records, four summaries, four child manifests and four memory evaluations carry Boolean true `formalCampaign`; all hashes and one-process identity match. |
| T13 | Campaign validation-only dry-run | Campaign V5 consumes the V5 wrapper summary/evidence and passes without creating a formal root or starting Unity. |
| T14 | Frozen-input post-audit | Attempt 1 and all bound upstream hashes equal their pre-write values. |
| T15 | Fresh final prelaunch | Exact hashes, storage ≥57,397,541,440 bytes, high-performance/AC/no-sleep/no-hibernate, entitlement/network/native `PSModulePath`, Unity zero, lock absent, and root/status/receipt absent. |

Only after T01–T15 pass may the attempt-2 receipt be atomically created,
validated while fresh, made read-only, and used for the single authorized formal
attempt.

## Rehearsal fixture

The rehearsal is created from one frozen shared-goal schedule record and keeps
its four-algorithm Williams order. It uses a fresh output namespace under
`Research/Verification/Gate13R_PR2_Formal_Attempt2/v1/ContractRehearsal/` and a
dedicated validation receipt. It is labelled
`VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS`, is never copied into the
formal root, and cannot satisfy a formal execution receipt check.

## Formal failure semantics

Once the attempt-2 formal root and receipt are committed, no automatic formal
retry, resume, top-up, merge, adaptive stop, parallelization, or attempt 3 is
allowed. During data collection, any measured contract failure stops before the
next block. After Unity collection completes, tool failures are handled only by
versioned read-only raw-audit recovery; Unity is not rerun.

