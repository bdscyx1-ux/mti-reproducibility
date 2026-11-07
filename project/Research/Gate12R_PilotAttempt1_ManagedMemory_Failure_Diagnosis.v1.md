# Gate 12R pilot attempt 1 managed-memory failure diagnosis (v1)

## Scope and terminal disposition

This diagnosis covers only `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1`. The root is terminally classified as `FAILED-NO-RESUME-NO-MERGE`, `NON-FORMAL`, and `EXCLUDED-FROM-FORMAL-ANALYSIS`. Its completed samples are not eligible for Gate 12R sample-size estimation, Gate 13R execution planning, or combination with a later attempt.

## Failure chain

1. The pilot completed 8 excluded warm-up block processes, 36 cold structural controls, and 202 measured Williams-block processes (608 measured samples).
2. Measured ordinal 247 targeted campaign `core-r01-s1-hetero--per-agent`, Williams block 17, with `A*-R` at position 1 followed by `D*L` at position 2.
3. Both child samples completed, but the Unity block command then rejected the block because retained managed-memory growth from the first pre-sample boundary to the final post-cleanup boundary was 134,512,640 bytes.
4. The frozen block limit is 134,217,728 bytes (128 MiB). The observed excess was 294,912 bytes (0.28125 MiB). No threshold relaxation or telemetry reinterpretation is authorized.
5. Unity exited non-zero and left `Temp/UnityLockfile`, a zero-byte file that was no longer owned and was available for exclusive read/write access. The outer wrapper then emitted a post-exit quiescence failure. That wrapper error is secondary; the block checkpoint and Unity log preserve the primary managed-memory hard failure.

## Confirmed implementation-contract defect

The frozen command `Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs` records `plannerResetCompleted = true` in every successful sample manifest, but its successful sample path does not invoke `planner.Reset()` before the next sample. All four planner implementations expose `Reset()` and use it to release planner-owned grid, state, field, queue, or per-agent references.

This is a confirmed mismatch between the declared per-sample reset contract and the actual implementation. It is a plausible contributor to retained managed-memory growth, but this diagnosis does not infer that it is the sole cause from one threshold crossing.

## Authorized repair boundary

A later attempt may use a new, versioned command derived mechanically from the frozen command. The permitted semantic change is to call `planner.Reset()` after capturing the existing raw-after-workload telemetry and before returning from the sample core. This preserves the frozen workload timing and raw telemetry boundary while making the declared reset contract true before the outer forced-GC cleanup boundary.

The repair must be tested against the exact failed campaign/block in multiple fresh Unity processes and must then pass the complete Gate 12R pre-pilot gate suite before a new pilot root can be created. The frozen 128 MiB/512 MiB limits, PSAPI/CIM telemetry, scenario matrix, Williams ordering, algorithms, 5% precision target, and no-cap policy remain unchanged.

