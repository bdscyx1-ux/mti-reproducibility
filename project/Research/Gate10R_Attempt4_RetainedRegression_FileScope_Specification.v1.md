# Gate 10R Attempt 4 retained-regression file-scope specification v1

Status: FROZEN-BEFORE-IMPLEMENTATION  
Design ID: `gate10r-attempt4-filescope-retained-regression-v1`  
Authorization: `Gate10R_Attempt4_Execution_Authorization.v1.json`

## Problem boundary

Attempt 3 proved the Unity lock transition, unit, compile, telemetry, positive/negative Williams-block, fresh-cold structural-control and repeatability gates. It then failed only because `Run-Gate10RRetainedRegressionV3.ps1` executed the mechanically transformed retained harness as a child `ScriptBlock`. In Windows PowerShell 5.1, assertion helpers wrote `$script:assertions` and `$script:failures` in the child script scope while the harness summary read the child-local variables initialized before helper invocation. The retained tests executed, but the wrapper reported zero assertions.

Attempt 4 fixes only this execution-scope defect. It does not reinterpret attempt 3 as passing and does not reuse attempt 3 runtime output.

## Frozen transformation

The v4 retained harness is a standalone `.ps1` file mechanically derived from frozen `Research/Verification/Run-Gate12AnalysisUnitTests.ps1` SHA-256 `e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1`.

Only these source transformations are allowed:

1. Replace the optional `ProjectPath` parameter with mandatory `ProjectPath` and mandatory isolated `SummaryPath` parameters.
2. Resolve and validate `ProjectPath` after parameter binding as an absolute path.
3. Resolve `scriptDirectory` to the frozen original `Research/Verification` directory so the frozen pre-audit input remains unchanged.
4. Resolve and validate the caller-supplied isolated `SummaryPath`; require its parent directory to exist; prohibit the original retained summary path and all attempt 1–3 roots.
5. Execute the transformed harness through Windows PowerShell 5.1 `-File`, never through `ScriptBlock::Create`, dot-sourcing, `Invoke-Expression`, or stdin command text.

All imports, fixtures, assertions, formulas, processes, failure rules and summary fields after the routing preamble remain byte-equivalent to the frozen source.

## Root and execution rules

- All parser, parameter-binding, mechanical-diff, frozen-evidence, output-isolation and 63/63 validation-only smoke evidence is written to `Research/Verification/Gate10R_Attempt4_Preflight/v1`, outside the future v4 official root.
- `Research/Verification/Gate10R_ProcessReuse_5pct/v4` must not exist before every outside-root hard gate passes.
- The v4 root is created exactly once for the first official execution, with a fresh versioned receipt bound to the v4 sources and inputs.
- Every execution receipt is consumable once. Any failure is closed atomically before an additive retry; a retry must use a new versioned root and receipt and may not alter the frozen transformation or research semantics.
- Stop immediately at the first complete Gate 10R pass. Gate 11R, Gate 12R and Gate 13R remain unauthorized.

## Unchanged research semantics

The algorithm implementations, Unity command, one-fresh-Unity-process-per-Williams-block model, Williams ordering, per-sample reset, telemetry, lock hygiene, structural comparison, 5% precision target, no-cap planning and Playable-scene semantics are unchanged from the active Gate 10R specification and attempt-3 inputs.

## Pass condition

Attempt 4 passes only if the full frozen sequence succeeds: no-Unity v4 preflight, unit gate, Unity compile gate, telemetry probe, positive and negative block verification, cold structural controls, retained 63/63 regression under file/script scope, and final integrity/authorization audit.

