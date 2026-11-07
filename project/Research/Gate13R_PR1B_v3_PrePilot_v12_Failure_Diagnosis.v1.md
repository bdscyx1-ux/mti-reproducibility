# Gate 13R-PR1B v3 pre-pilot v12 failure diagnosis

## Terminal classification

`FAILED-NO-PILOT / PREPILOT-ONLY / UNITY-NOT-INVOKED / FORMAL-NOT-AUTHORIZED`

The v12 verification root is frozen byte-for-byte. It must not be overwritten, resumed, or relabelled as a passing attempt.

## Observed failure

The v12 static/unit phase completed successfully with 85/85 checks. Immediately afterward, the pre-pilot orchestrator attempted to replace its existing mutable checkpoint through `Write-Gate13RPR1BV3AtomicUtf8NoBomJson`. Under Windows PowerShell 5.1 / .NET Framework, the three-argument call

```text
[System.IO.File]::Replace(source, destination, $null)
```

normalizes the null backup argument as a path and raises `System.ArgumentException: The path is not of a legal form.`

No Unity Editor process was launched. The path-safe Unity C# implementation was not exercised in this failed attempt. The new v7 pilot root and reserved formal root remained absent.

## Root cause and permitted repair

This is a pre-pilot PowerShell compatibility defect, not a scientific-threshold failure. A versioned repair may retain same-directory atomic replacement while supplying a unique, short, verified backup leaf to `File.Replace`, deleting only that helper-owned backup afterward. New-file creation must continue to use a same-directory move. Temporary and backup leaves must remain short, collision-checked, contained, and reparse-safe.

The repair must use new versioned files and a new verification root. The v3 module, v5 plan/provenance, all v12 files, memory thresholds, statistics, schedule cardinality, Williams/mirrored order, reset semantics, and authorization boundary remain immutable.

