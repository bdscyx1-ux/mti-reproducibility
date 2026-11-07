# Gate 13R-PR1B Failure Checkpoint v1

Saved: 2026-10-08 19:53:23 +08:00

Gate 13R-PR1B balanced mirrored pilot attempt 1 is terminal:

`FAILED-PER-SAMPLE-RETAINED-MANAGED-MEMORY-GATE / NO-RETRY / NO-RESUME / NO-MERGE / PARTIAL-DATA-EXCLUDED / GATE13R-FORMAL-NOT-AUTHORIZED`

## Exact resume state

1. Read `Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Terminal_Preservation.v1.json`.
2. Read `Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Failure_Diagnosis.v1.md`.
3. Treat `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v5-gate13r-pr1b-order-effect/` as immutable failed evidence.
4. Do not run the order-effect analyzer on the partial attempt for effect inference.
5. Do not retry, resume, top up, merge, delete, or rewrite attempt 1.
6. No Unity process remains. A zero-byte, exclusively accessible `H:/DDM_Final_Project/Temp/UnityLockfile` remains and must not be removed without the separate controlled-recovery authorization contained in the next prompt.
7. `Research/FormalRuns/Gate13R_RQAligned/v1` remains absent. No formal receipt or formal timing sample exists.

## Failure point

- completed: 12/12 warm-up processes and 12/384 measured processes;
- complete measured mirrored pairs: 3/96, permanently excluded;
- failed measured process: 13th;
- scenario: `core-r07-s2-hetero`;
- block: 2;
- order/cohort: `BA`, grouped-field first;
- algorithm: IDFF, position 1, predecessor NONE;
- primary error: retained managed-memory growth greater than 128 MiB;
- exact growth: unavailable because v3 throws before durable telemetry publication;
- workload structural comparison: 34/34 fields equal to the frozen historical counterpart.

## Required next authorization

Use `Research/Gate13R_PR1B_OrderEffect_Next_Authorization_Prompt.md`. It authorizes only a prospective v2 telemetry/memory-policy amendment, controlled lock recovery, full validation, and one fresh non-formal pilot. It does not authorize Gate 13R formal execution or Gate 14R.
