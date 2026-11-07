# Gate 13R-PR2-MP1 targeted memory-policy pilot — Run Passport

## Material Passport

- Work unit: `gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1`.
- Authorization source: exact user words in `Research/Gate13R_PR2_MP1_User_Authorization.v1.txt`, bounded by `Research/Gate13R_PR2_MemoryPolicy_Targeted_Pilot_Next_Authorization_Prompt.md`.
- Mode: `RUN / NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY`.
- Attempt 2 source root: `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2` (read-only historical failure evidence).
- New pilot root, if and only if every pre-pilot gate passes: `H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1`.
- Measured design: 96 fresh Unity block processes / 384 algorithm samples, strict serial; no measured retry, resume, top-up, or merge.
- Raw/analysis rule: Phase A freezes immutable raw data; Phase B analyzes it read-only in independent versioned attempts.
- Formal attempt 3 authorized: **No**.
- Formal statistical analysis authorized: **No**.
- Gate 14R authorized: **No**.

## Authorized stages

1. Freeze specification, instrumentation, policy candidates, schedule, schema, analysis plan, two-stage contract, and provenance before observing new pilot results.
2. Add new versioned pilot-only command/wrapper/orchestrator without modifying V4/V5/V6 or historical evidence.
3. Run parser, unit, synthetic, Unity compile/telemetry/positive/negative and validation-only gates.
4. If and only if all gates pass, execute one fresh NON-FORMAL targeted pilot.
5. Commit immutable raw data, then perform read-only diagnostic analysis.
6. Produce an unfrozen policy recommendation, readiness checkpoint, plan update, and next authorization prompt.

## Stop conditions

- Any attempt-2 identity/hash/read-only mismatch fails closed.
- Any frozen schedule, telemetry, reset, correctness, or safety-gate failure fails closed.
- Once measured acquisition starts, any hard failure stops the pilot without automatic retry/resume/top-up/merge.
- An analysis implementation defect may be repaired only in an independent versioned analysis attempt against the same immutable raw root.
- Work stops before formal attempt 3, formal statistical analysis, or Gate 14R.
