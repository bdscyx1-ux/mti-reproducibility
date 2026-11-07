# Gate13R-AX2 non-executing precollection readiness

Status: **FINAL-READINESS-PASS**

## Frozen design

- 32 shared-goal campaigns
- B=48 complete blocks per campaign
- four-treatment Williams schedule
- 1,536 complete blocks and 6,144 anonymous samples
- treatments: BiA*-R, LPA*, C-FF, IDFF
- one fresh Unity process per complete four-treatment block

## Verification evidence

- Unity compile: PASS
- algorithm correctness: PASS (962 assertions)
- full schedule/schema/hash validation: PASS
- positive block smoke plus independent raw commit/read-only freeze: PASS
- g256 memory path: PASS; observed peak working set 1799954432 bytes and peak private memory 2053685248 bytes
- injected partial-block failure and raw-commit rejection: PASS
- formal authorization guard: PASS; no formal root or Unity process was created by the guard test
- P1 analysis implementation selftest: PASS; no formal data analyzed and no winner declared

## Scope boundary

No formal Gate13R-AX2 collection was started. No original Gate 13R raw or analysis result was read or modified. Verification samples are non-formal and cannot be merged into a future formal attempt.

A separate single-attempt formal authorization remains required.
