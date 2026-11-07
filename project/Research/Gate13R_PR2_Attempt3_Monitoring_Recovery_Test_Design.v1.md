# Gate 13R-PR2 Attempt 3 monitoring/recovery test design v1

## Purpose

Validate the non-executing operational monitor and bounded recovery contract without creating a formal root, execution receipt or status and without launching Unity.

## Frozen-before-test artifacts

- Authorization and pre-write audit.
- Monitoring/recovery specification.
- Monitoring configuration.
- Operational status and progress snapshot schemas.
- Recovery state-machine registry.
- Synthetic fixture expected-result registry.

These artifacts must be hashed before implementation results are inspected.

## Test groups

### A. Identity and preservation

1. Parse every new JSON/schema artifact.
2. Recheck MP2 readiness, active V4 candidate, v2 schedule, policy registry/mapping/overlay and wrapper hashes.
3. Prove formal v3 root, receipt and status remain absent before and after tests.
4. Prove zero Unity Editor process and absent `Temp/UnityLockfile` before and after tests.
5. Static proof that validation commands contain no Unity executable or formal runner invocation.

### B. Monitoring state and reporting cadence

6. All formal targets absent → `NOT-STARTED`, quiet.
7. Partial formal target set → `ACTION-REQUIRED`, immediate report.
8. Valid acquisition-running fixture → operational snapshot with correct totals and identities.
9. First running observation → start event report.
10. Watcher tick before the next 60-minute slot → no scheduled report.
11. Watcher tick in a new 60-minute slot → exactly one scheduled report.
12. Missed slots → one current report, no catch-up flood.
13. Failure/completion/action-required transition → immediate report independent of hourly slot.
14. Terminal state already acknowledged → quiet on the next unchanged tick.

### C. Blinding and data minimization

15. Snapshot contains the complete allowed operational field set.
16. Snapshot and rendered report reject or omit P1-P5, M1-M5, algorithm timing, contrasts, effect, CI, p-value, ranking, winner and superiority fields.
17. Monitoring output is excluded from formal/raw/statistical roots.
18. A requested snapshot path inside the formal root is rejected.

### D. Counter, identity and telemetry validation

19. Counter regression fails closed.
20. Completed count above total fails closed.
21. Global ordinal outside 1–3,552 fails closed.
22. Formal attempt ordinal other than 3 fails closed.
23. Root/receipt SHA/config/schedule mismatch fails closed.
24. Composite PID/start-time/block mismatch becomes action-required.
25. Missing, negative, non-integer or non-finite telemetry becomes action-required.
26. Valid PSAPI/CIM-style fixture preserves working set/private/available values without exposing endpoint data.

### E. Stall and ETA

27. Status age exactly 15 minutes is not stale; greater than 15 is advisory.
28. No progress exactly 30 minutes is not stall; greater than 30 is `STALL-SUSPECTED`.
29. Missing owned process for greater than 5 minutes becomes action-required.
30. Block elapsed greater than 3,660 seconds becomes hard-timeout-overdue action-required without a kill command.
31. Rolling and overall positive rates choose the smaller rate and apply ×1.25 ETA factor.
32. Zero/negative/insufficient rate returns `UNAVAILABLE`.

### F. Recovery state machine

33. Prelaunch repair is eligible only with all formal targets absent and zero measured counts.
34. Prelaunch repair is rejected after root, receipt, status or measured launch.
35. Frozen hash/research-contract/scientific failures are never auto-repairable.
36. Maximum 3 prelaunch versioned repair cycles.
37. Two consecutive identical repaired failure signatures stop automation.
38. Acquisition hard failure permits diagnostics only and returns no retry/resume/top-up/merge action.
39. Failure status forbids next-block advancement.
40. Post-acquisition commit recovery requires 3,552/10,176 complete, zero Unity, absent lock and stable raw-tree identity.
41. Commit recovery never returns a Unity command.
42. Maximum 3 commit-recovery attempts and repeated-signature stop.
43. Raw contract violation requires user decision.

### G. Read retry and persistence

44. Status/receipt read policy is exactly three attempts with delays 0/2/5 seconds.
45. A later successful read retains the earlier anomaly count.
46. Synthetic monitoring snapshot writes atomically under verification root.
47. Attempted overwrite of an immutable snapshot is rejected.
48. Deterministic serialization produces byte-identical output for fixed fixture and fixed time.

### H. Runtime compatibility and final audit

49. Python parser/CLI tests pass with the configured local Python runtime.
50. PowerShell 7 and native Windows PowerShell 5.1 parser/binding smoke tests pass for the wrapper.
51. No-launch dry-run returns without Unity.
52. Automation contract records 5-minute silent watcher and 60-minute report cadence.
53. Post-test frozen-input hashes equal pre-write values.
54. Evidence manifest and readiness checkpoint bind every test and output hash.

## Failure handling

Any failure is preserved under a new versioned verification attempt with receipt, diagnosis, checkpoint, partial manifest and hashes. Implementation-only defects may be repaired in a new version without changing the monitoring/recovery semantics. A scientific or authorization-boundary failure stops and waits for the user.
