# Gate 13R-PR1B v4 Composite Process Identity Analysis Recovery Run Passport

## Material Passport

- Work unit: `gate13r-pr1b-v4-composite-process-identity-analysis-recovery-v1`
- Authorization source: user authorization received 2026-10-08 (Asia/Shanghai), incorporating the complete text of `Research/Gate13R_PR1B_v4_CompositeProcessIdentity_Next_Authorization_Prompt.md`.
- Authorized scope: versioned, non-executing composite-process-identity analyzer repair and validation, followed only after all hard gates pass by exactly one independent read-only analysis recovery from the frozen complete v3 pilot.
- Frozen pilot root: `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4`.
- Frozen pilot tree SHA-256: `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`.
- Frozen pilot status: `FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / NON-FORMAL / COMPLETE-RAW-EXECUTION / POST-EXECUTION-ANALYZER-FAILED / EXCLUDED-FROM-FORMAL-ANALYSIS`.
- New analysis root: `Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1`.
- New validation root: `Research/Verification/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1`.
- Unity Editor invocation authorized: **No**.
- New pilot samples authorized: **No**.
- Pilot retry/resume/top-up/merge authorized: **No**.
- Gate 13R formal campaign authorized: **No**.
- Gate 14R authorized: **No**.
- Formal output-root creation authorized: **No**.
- Validation-only versioned repair/retry before recovery: **Yes**, with preservation of every failed verification attempt and no scientific-contract change.
- Analysis recovery retry after recovery starts: **No**.

## Frozen Scientific Contract

- P1-P5 and C1-C5 remain unchanged.
- Estimand remains `AB-minus-BA` on the frozen natural-log-ratio scale.
- Confidence level remains 95%.
- Order-effect bound remains `+-log(1.10)`.
- Bootstrap remains 20,000 whole-mirrored-pair replicates with seed `13012026`.
- Three scenarios and 32 mirrored pairs per scenario remain unchanged.
- Williams rows, rotation, AB/BA quotas, memory policy, reset, correctness, hash, and exclusion gates remain unchanged.
- Recovered results are `PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS` and cannot support formal superiority claims.

## Process Identity Contract

- OS process identity: `(processId, processStartTimeUtc)`.
- Block evidence identity: `(processId, processStartTimeUtc, blockId)`.
- Reuse of a numeric PID is legal only after the prior process with that PID has ended.
- Duplicate OS identity, duplicate block evidence identity, overlapping same-PID lifetimes, invalid start time, sample/block PID mismatch, one identity mapped to multiple blocks, or one block mapped to multiple identities fails closed.

## Terminal Success State

`COMPOSITE-PROCESS-IDENTITY-VALIDATED / READ-ONLY-ANALYSIS-RECOVERY-COMPLETE / PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

## Failure State

If validation fails, preserve versioned validation evidence and do not start recovery. If the single recovery fails, preserve independent atomic failure evidence and stop. Never fall back to Unity rerun or pilot continuation.
