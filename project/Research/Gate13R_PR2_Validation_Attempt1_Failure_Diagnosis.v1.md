# Gate 13R-PR2 validation-only attempt 1 failure diagnosis

## Outcome

Attempt 1 failed closed at the pre-validation preservation gate. The core schedule/config validator did not start. No Unity process was launched, no formal root or formal execution receipt was created, and no frozen input was modified.

## Root cause

The pre-write tree identities had been computed under PowerShell 7. The first validation orchestrator was deliberately parser-compatible with Windows PowerShell 5.1 and was executed under 5.1. Its `Sort-Object FullName` applies a different runtime/culture collation for filenames that share a stem but have `.json` and `.log` suffixes.

For `Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1`, both runtimes observed exactly 8 files and 116,998 raw bytes, and the attempt's pre/post identities were identical. PowerShell 7 produced the already frozen canonical hash `70f4f10c...`; Windows PowerShell 5.1 produced `ce843b75...` solely because it placed `analysis-recovery.log` before the sibling JSON files when constructing the ordered manifest.

This is an identity-serialization defect in the new PR2 validator, not evidence of upstream mutation.

## Authorized repair

Attempt 2 will preserve the entire v1 validation root and all PR2 official generated artifacts. New v2 validation sources will mechanically derive from v1 and change only:

1. tree-manifest ordering to explicit `.NET StringComparer.Ordinal`;
2. versioned v2 validation IDs and output root;
3. active-source binding so the static scan covers the v2 orchestrator.

The S48/H48 matrix, schedule, scientific contract, resource projection, thresholds, and authorization boundary are unchanged.
