# Gate 10R Attempt 1 Failure Checkpoint

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run / validate`
- Origin Date: 2026-10-06
- Verification Status: `FAILED-NO-AUTO-RETRY`
- Version Label: `gate10r_attempt1_unit_entry_failure_v1`

## Terminal state

Gate 10R attempt 1 stopped at the first official execution gate. Windows PowerShell 5.1 evaluated the test script's parameter default before a usable `$PSScriptRoot` was available, so the nested `Split-Path` expression received an empty string at line 3. Exit code: 1.

This failure occurred before the unit assertions, Unity compilation, telemetry probe, positive/negative block fixtures, cold structural controls, retained regression, Gate 11R, or Gate 12R pilot.

- Unity processes after failure: 0
- Project lock: absent
- Automatic retry: not attempted
- Automatic resume: not attempted
- Gate 13R formal root: absent
- Disposition: `GATE10R-FAILED-NO-AUTO-RETRY / WAIT-FOR-EXPLICIT-RETRY-AUTHORIZATION`

## Evidence

- Failure log SHA-256: `ed11b29ab0e7331007a1ec30f1471fb28cf185924de006981ca7895db954f479`
- Partial manifest SHA-256: `9dc16acfc7bab0f72d621fd6620f83235411e3afa6d9138fbde1445f87ff138e`
- Failure receipt SHA-256: `a1d501c72fa1e1a21f041c9cb7c73967b85e0dafbe2b74fe1cf83d003613917a`

A future attempt must use a new versioned attempt-2 receipt and new verification root. Attempt 1 must remain unchanged. The prospective correction is to make `ProjectPath` explicit at invocation or derive it inside the script body after parameter binding; no correction or rerun is authorized by this checkpoint.

