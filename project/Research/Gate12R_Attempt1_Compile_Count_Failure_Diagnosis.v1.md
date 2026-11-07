# Gate 12R official pre-pilot attempt 1 failure diagnosis

- Status: `FAILED-VERSIONED-REPAIR-RETRY-ALLOWED`
- Failed attempt root: `Research/Verification/Gate12R_ProcessReuse_5pct/v1`
- Pilot root created: `false`
- Gate 13R formal root created: `false`
- Unity compilation process: completed with exit code 0
- Unity compiler/error-pattern matches: 0 (independently re-counted from the frozen log)
- Post-exit lock hygiene: natural lock absence recorded

The failure occurred after Unity had exited successfully. Under Windows PowerShell 5.1 with strict mode, the expression used by the v1 wrapper assigned no pipeline objects to `$matches` when `Select-String` found zero matches. The surrounding `if` expression consequently yielded `$null`, so the subsequent `$matches.Count` access raised `The property 'Count' cannot be found on this object`.

The same PowerShell 5.1 empty-output pattern was found prospectively in the v1 telemetry and cold-reference wrappers. The authorized repair therefore consists only of versioned, mechanically derived wrappers that initialize the relevant collection to `@()` before conditionally assigning `@(Select-String ...)`. The Unity command, algorithms, scenarios, Williams order, reset semantics, telemetry thresholds, memory thresholds, 5% precision target, no-cap policy, and exclusion rules remain unchanged.

Frozen attempt-1 anchors:

- `execution-receipt.json`: `072add00e290f30a3864d7f0efc78f3463517331331efb4e5b67919e749ea463`
- `failure-receipt.json`: `82c31b57b9cacfe32677cc4b122d896169b8c2944386d2351f3893d87c931040`
- `gate12r-checkpoint.json`: `0016b808824f862043fc8cbb08127f989bcff3116e3f4a9e8ac7bb320262c9fd`
- `partial-output-manifest.json`: `423364d3192e24d5aa958c9f7fddce9bdd15d284cfd8f5abb9c8c5accb544aea`
- `Compile/Gate12R.Unity.log`: `f2f2d16835d93a08f7777290a1f22cabafb72f1175dfe7345585f8d3f37163c1`
- Attempt-1 root at diagnosis: 16 files, 95,147 raw bytes; last write `2026-10-07T09:27:02.6016161Z`.

