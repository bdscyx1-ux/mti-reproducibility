# Gate 13R-PR2 attempt 2 failure diagnosis — Run Passport

## Material Passport

- Work unit: `gate13r-pr2-fd1-attempt2-evidence-freeze-memory-lock-diagnosis-v1`.
- Authorization source: exact user authorization captured in `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_User_Authorization.v1.txt` and bounded by `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Next_Authorization_Prompt.md`.
- Failed formal root: `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2`.
- Pre-write canonical tree SHA-256: `be2623906d741b39e87f7c1d033d21443d2776f62ed709b4c4ef296220ce5f04`.
- Mode: `NON-EXECUTING / FAILURE-DIAGNOSTIC-ONLY`.
- Unity Editor execution authorized: **No**.
- Attempt 2 retry/resume/top-up/merge authorized: **No**.
- Attempt 3 authorized: **No**.
- Formal statistical analysis authorized: **No**.
- Gate 14R authorized: **No**.

## Authorized stages

1. Record authorization and prove the failed root is stable before writing.
2. Build a complete per-file evidence manifest and freeze existing attempt-2 files read-only without byte changes.
3. Capture and conditionally remove only the exact stale UnityLockfile after all safety gates.
4. Perform read-only operational memory and failure-precedence diagnostics.
5. Validate deterministic analysis, formulas, frozen-input invariance, and absence of Unity/formal-analysis execution.
6. Produce an unfrozen memory-policy decision matrix, targeted-pilot verdict, plan update, checkpoint, and next authorization prompt.

## Stop conditions

- Any mismatch in the failed root identity, cardinalities, key hashes, or status fails closed.
- Any live Unity or attempt-2 orchestrator blocks stale-lock cleanup.
- Missing or malformed telemetry remains visible and cannot be imputed.
- New diagnostic implementation may be repaired only in a new versioned attempt; frozen evidence is never overwritten.
- The stage stops before any Unity run, pilot, attempt 3, formal statistical analysis, or Gate 14R.
