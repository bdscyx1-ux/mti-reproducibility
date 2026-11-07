# Gate 10R Attempt 4 retained-regression test design v1

Status: FROZEN-BEFORE-IMPLEMENTATION  
Design ID: `gate10r-attempt4-filescope-retained-regression-v1`

## Phase A — outside-v4-root, no-Unity hard gates

1. Windows PowerShell 5.1 parser checks for every new v4 PowerShell entrypoint and the derived harness.
2. Parameter-binding smoke verifies missing mandatory parameters fail before script execution and explicit absolute `ProjectPath`/`SummaryPath` bind successfully.
3. Deterministic mechanical transformation regenerates the expected harness in memory and requires byte-for-byte equality with the saved v4 harness.
4. Diff allowlist requires all changed lines to belong only to the parameter/path/output-routing preamble; the retained test body is exact.
5. Attempts 1–3 tree identities, frozen source hash and frozen 63/63 summary hash must match the pre-write baseline before and after smoke.
6. Output-isolation negatives reject the original summary, attempts 1–3, v4 official root and any path outside the dedicated preflight root.
7. File-scope validation-only smoke runs the harness once using Windows PowerShell 5.1 `-File`, writes only the isolated smoke summary/log, and requires exit code 0, `passed=true`, `assertionCount=63`, zero failures and unchanged originals.
8. Unity process count must remain zero, `Temp/UnityLockfile` must remain absent and the v4 official root must remain absent throughout Phase A.

Any Phase-A failure is fail-closed and prohibits v4-root creation.

## Phase B — one official v4 execution

After Phase A passes, create the v4 root and one immutable execution receipt. Consume it once and execute in frozen order:

1. v4 no-Unity preflight;
2. Gate 10R unit tests;
3. Unity compilation;
4. telemetry probe;
5. three positive Williams blocks;
6. expected-negative atomic fail-closed block;
7. six fresh cold-process references;
8. ten exact structural comparisons and independent-process repeatability;
9. retained regression through the saved v4 harness using `powershell.exe -File`;
10. final integrity and authorization audit.

## Failure and retry oracle

On a hard-gate failure, record the failing command, input hashes, owned process state, partial output inventory and hashes, failure receipt, checkpoint and manifest atomically. Do not overwrite or resume the failed root. The user authorizes another additive versioned execution only within the same wrapper-scope repair; each retry receives a new root and one-use receipt. No threshold, research command or semantic input may change. Stop on the first complete Gate 10R pass.

## Success oracle

- full sequence exit status 0;
- all stage summaries passed;
- retained summary reports exactly 63 assertions, no failures and the expected frozen input hashes;
- attempts 1–3, original retained source and original 63/63 summary remain byte-identical;
- no Gate 11R, Gate 12R or Gate 13R output root is created;
- terminal status is `GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION`.
