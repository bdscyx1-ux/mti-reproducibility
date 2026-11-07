# Gate 13R-PR2 formal attempt 3 prelaunch test design v1

Status: `PRELAUNCH-ONLY / FORMAL-TARGETS-MUST-BE-ABSENT / NO-MEASURED-DATA`

## Scope

This test design validates the versioned attempt-3 execution orchestrator, operational status publisher, raw-data commit tool, and their exact bindings to the already-frozen MP2 V4 candidate and formal v2 schedule. It does not authorize or perform Phase-B statistical analysis or Gate 14R.

## Hard preconditions

- Exact v3 formal root, receipt, and status are absent.
- No Unity Editor process exists and `Temp/UnityLockfile` is absent.
- Historical attempts 1 and 2 and all frozen upstream inputs remain byte-identical.
- H: free bytes are at least `57,397,541,440`.
- Native Windows PowerShell 5.1 receives the verified native `PSModulePath`.
- The high-performance power scheme is active and AC sleep/hibernate cannot interrupt the run.
- The active heartbeat remains enabled, executes the V2 monitor every five minutes, and the monitor internally throttles scheduled reports to one per 60-minute slot.

## Static and unit gates

1. Python parser/import checks for the attempt-3 orchestrator and its tests.
2. Windows PowerShell 5.1 and active PowerShell parser/binding checks for the launch entry and frozen MP2 V3 block wrapper.
3. Exact SHA-256 checks for every active readiness, candidate, schedule, policy, command, monitoring, two-stage-commit, authorization, and execution artifact.
4. Full schedule reconstruction: 53 scenarios, 74 campaigns, 3,552 contiguous global process ordinals, 10,176 unique run IDs, 1,008 matched superblocks, per-scenario AB/BA 24/24, and order-by-Williams-row 12 per cell.
5. Deterministic block-plan reconstruction for first, shared terminal, first heterogeneous, interior heterogeneous, and final ordinals, plus arbitrary-ordinal no-launch dry runs.
6. No skip, reorder, duplicate output, cross-block process reuse, adaptive stopping, automatic measured retry, resume, top-up, or partial merge paths.
7. Operational status schema tests, atomic write/replace tests, composite process identity tests, telemetry tests, and blinded-field rejection.
8. Failure-precedence and fail-closed tests for wrapper nonzero exit, missing Unity identity, duplicate/missing block evidence, bad hashes, raw-tree mutation, incomplete counts, and formal-target preexistence.
9. Two-stage state-machine proof: `ACQUISITION-RUNNING` -> `ACQUISITION-COMPLETE-COMMIT-PENDING` -> `RAW-COMMIT-RECOVERY` when needed -> `RAW-DATA-COMPLETE-ANALYSIS-PENDING-IMMUTABLE`. Analysis failures cannot invoke Unity.
10. Synthetic raw-commit fixture verification, including immutable payload manifest, canonical tree digest, environment end snapshot, and separate commit-attempt evidence.

## Fresh Unity validation gates

After every static gate passes and while formal targets remain absent:

- Unity MP2 memory-policy self tests pass.
- PSAPI/CIM telemetry probe returns positive, cross-checkable values.
- One complete positive validation-only Williams block passes with natural lock absence.
- Native-hard, telemetry-failure, and persistence-failure negative fixtures fail closed and do not execute later positions.
- The frozen MP2 static/unit/determinism suite, retained validation evidence, and monitoring 56/56 suite pass again.

All validation outputs use a new independent verification attempt root and are marked `VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS`.

## Launch decision

Only a single all-green final audit may authorize atomic creation of the v3 formal root, receipt, and status. Any hard-gate failure is preserved as a versioned prelaunch attempt. At most two further versioned software-repair cycles remain because the monitoring V2 repair consumed cycle 1. The same failure signature twice stops automatically.

## Acquisition and commit boundary

Once the v3 target set is created, measured acquisition is a single non-restartable attempt. During acquisition, diagnostics are read-only and cannot advance or repeat the schedule. After all 3,552 processes and 10,176 samples complete, Unity acquisition closes permanently. Only the bounded, non-Unity raw-commit recovery described in the authorization may run. Phase-B formal statistical analysis and Gate 14R remain unauthorized.
