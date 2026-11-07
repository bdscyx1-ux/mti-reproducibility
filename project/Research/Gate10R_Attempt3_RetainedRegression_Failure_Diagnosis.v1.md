# Gate 10R attempt 3 retained-regression failure diagnosis

## Status

- Attempt: `3`
- Terminal stage: retained 63-assertion regression
- Outcome: `GATE10R-ATTEMPT3-FAILED-NO-AUTO-RETRY`
- Automatic retry/resume: forbidden and not attempted
- Gate 11R / Gate 12R: not authorized and not started
- Gate 13R: not authorized and not started

## What passed before the stop

- No-Unity preflight: `67/67`
- Gate 10R unit tests: `59/59`
- Unity compilation: passed; lock released naturally
- Native/OS telemetry probe: passed; lock released naturally
- Process-reuse block verification: passed
  - three positive Williams blocks in three distinct Unity processes;
  - one atomic expected-negative block;
  - six fresh cold-process structural references;
  - ten structural comparisons, zero mismatches;
  - positive and cold processes released the lock naturally;
  - the expected-negative process used the frozen, evidence-captured controlled cleanup after the 60-second quiescence window.

## Observed failure

`Research/Verification/Gate10R_ProcessReuse_5pct/v3/RetainedRegression/RetainedRegression63.summary.json` reported:

- `passed = true`
- `failures = []`
- `assertionCount = 0`

The hard gate requires `passed = true` **and** exactly `63` assertions. The wrapper therefore stopped with exit code `1`. The final audit was not started.

The original retained evidence remained byte-identical:

- `Research/Verification/Gate12_AnalysisUnitTests.summary.json`
- SHA-256: `1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d`
- recorded assertion count: `63`
- recorded result: passed

## Confirmed cause

The versioned Gate 10R wrapper executes the frozen Gate 12 test source as a child `ScriptBlock` read from standard input. The frozen source initializes `$assertions` in that child scope, but its assertion helpers increment `$script:assertions`. Under Windows PowerShell 5.1, those are different scopes in this invocation form. Consequently the tests execute without failures, while the summary reads the unchanged child-scope value `0`.

A read-only synthetic scope probe under the same Windows PowerShell 5.1 entry form returned:

```json
{"localAssertions":0,"scriptAssertions":1}
```

This is an orchestration-wrapper scope defect. It is not a Unity, planner, algorithm, telemetry, process-reuse, Williams-order, structural-equivalence, or historical-evidence failure.

## Next permitted repair (requires a new user authorization)

A new versioned Gate 10R attempt may replace only the retained-regression invocation wrapper so the frozen source runs in file/script scope while redirecting its summary to a new attempt root. It must preserve the original test script and original summary byte-for-byte, preflight the new wrapper without Unity, run the complete frozen Gate 10R sequence only if that preflight passes, and remain fail-closed with no automatic retry/resume.

No such repair or new attempt is authorized by the current Gate 10-only attempt-3 receipt.
