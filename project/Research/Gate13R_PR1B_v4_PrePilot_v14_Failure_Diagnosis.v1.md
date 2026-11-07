# Gate 13R-PR1B v4 pre-pilot v14 failure diagnosis

## Terminal classification

`FAILED-NO-PILOT / PREPILOT-ONLY / FIRST-POSITIVE-BASE-BLOCK-PASSED / FORMAL-NOT-AUTHORIZED`

The v14 verification root is frozen byte-for-byte and must not be overwritten, resumed, or relabelled as passing.

## Root cause

The v14 orchestrator, Unity compilation, path-safe C# self-test, memory-policy self-test, telemetry probe, provenance-compatible plan generation, and first positive base block all passed. After canonical input externalization, `Run-Gate13RPR1BMemoryAwareBlockV4.ps1` updated the existing wrapper summary through a locally embedded three-argument call:

```text
[System.IO.File]::Replace(temp, summary, $null)
```

Windows PowerShell 5.1 rejected the null backup path. This is the same runtime compatibility class fixed earlier in the shared module, but the block wrapper contained a second embedded replacement implementation that the initial static scan did not cover.

No memory threshold, structural comparison, algorithm, reset, scenario, eligibility, or statistical gate failed.

## Permitted repair

Create a new versioned block wrapper that imports the frozen v4 helper module and routes existing-summary replacement through `Write-Gate13RPR1BV3AtomicUtf8NoBomJson`. Add a static assertion that every active PowerShell execution file contains zero three-argument `File.Replace` calls with a null backup. Route new block-verification, static, pilot, and pre-pilot wrappers to that block wrapper. Preserve every v14 byte and rerun all gates from the beginning in a new verification root.

