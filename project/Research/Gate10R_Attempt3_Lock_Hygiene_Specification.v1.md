# Gate 10R Attempt 3 Lock-Hygiene Specification

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `plan / validate / run`
- Origin Date: 2026-10-06
- Verification Status: `SPECIFICATION-FROZEN-BEFORE-ATTEMPT3-IMPLEMENTATION`
- Version Label: `gate10r_attempt3_lock_hygiene_specification_v1`

## 1. Scope and unchanged research semantics

Attempt 3 is a narrow orchestration repair for the project-lock transition exposed by attempt 2. It does not modify the frozen Gate 10R research design. The following remain byte- and semantics-identical: the Unity command, planner implementations, research grid, scenarios, Williams rows, one-fresh-Unity-process-per-block ownership, per-sample reset, telemetry definitions, 128 MiB managed rule, 512 MiB native rules, exact structural projection, 5% precision target, uncapped future `n_formal`, and Playable-scene requirement.

Attempt 1 and attempt 2 are terminal evidence. Attempt 3 writes only to new versioned files and `Research/Verification/Gate10R_ProcessReuse_5pct/v3`.

Gate 11R and Gate 12R authorization is revoked. A successful Gate 10R attempt 3 must stop with `GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION`; it cannot generate scenarios, Playable assets, pilot samples, or formal data.

## 2. Exact lock identity

The only deletable path is the fully resolved literal path:

```text
H:\DDM_Final_Project\Temp\UnityLockfile
```

No wildcard, directory deletion, recursive deletion, alternate project path, symlink/reparse traversal, or other `Temp` cleanup is permitted. Before every cleanup, the resolved project root and resolved lock path must equal the frozen values using ordinal-insensitive Windows path comparison.

## 3. Post-exit quiescence contract

After every owned Unity process returns:

1. record the owned PID and process start/completion timestamps;
2. verify the owned PID no longer exists;
3. poll every 250 ms for at most 60 seconds;
4. require the global `Unity.exe` process count to be zero;
5. wait for the exact project lock to disappear naturally.

For compile, telemetry, positive block, and cold-reference processes, natural lock disappearance is mandatory. A persistent lock after 60 seconds is a hard failure and cannot be deleted automatically.

## 4. Expected-negative exception

Only an owned fixture whose plan is explicitly marked `excluded-negative-fail-closed-verification` and whose wrapper was invoked with `ExpectFailure` may use controlled cleanup. If its lock remains after the 60-second natural-quiescence window, all of the following must be true:

- the owned PID is absent;
- no `Unity.exe` process exists;
- the path is the exact frozen lock path;
- the file is a normal leaf file, not a directory or reparse point;
- the file is exactly 0 bytes;
- SHA-256 is `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`;
- the file can be opened read/write with `FileShare.None` and immediately closed;
- creation and last-write timestamps lie between the owned process start minus 2 seconds and completion plus 2 seconds;
- a create-new pre-delete capture receipt has been atomically written and hashed.

Only then may the exact file be removed with a literal, non-recursive operation. A create-new completion receipt must record the capture-receipt hash, deletion time, and verified postcondition: owned PID absent, Unity count zero, lock absent. Any failed predicate stops the gate without deletion.

## 5. Pre-existing attempt-2 stale lock

Before attempt 3 official execution, the no-Unity preflight may apply the same controlled cleanup once to the lock already bound by attempt-2 evidence. Its required owner evidence is:

- owned PID `19936`;
- process window `2026-10-06T21:09:14.5903019+08:00` to `2026-10-06T21:09:26.2233236+08:00`;
- lock timestamp `2026-10-06T13:09:17.4285441Z`;
- length 0 and the empty-file SHA-256 above;
- attempt-2 negative summary SHA-256 bound by attempt-2 manifest.

The pre-delete and completion receipts belong to attempt 3. Attempt-2 files remain untouched.

## 6. Failure and execution policy

- Static/parser/binding/unit/preflight work starts no Unity.
- The official attempt begins only after a versioned execution receipt is created.
- Maximum official executions: one.
- No automatic retry or resume.
- No continuation from attempt-2 partial outputs.
- Any hard failure writes terminal evidence and stops.
- Successful Gate 10R writes a versioned manifest and checkpoint, then requests new user authorization.

