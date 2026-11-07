# Gate 10R Attempt 3 Lock-Hygiene Test Design

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `plan / validate / run`
- Origin Date: 2026-10-06
- Verification Status: `TEST-DESIGN-FROZEN-BEFORE-ATTEMPT3-IMPLEMENTATION`
- Version Label: `gate10r_attempt3_lock_hygiene_test_design_v1`

## 1. Ordered hard gates

1. authorization and v1/v2 preservation audit;
2. v3 specification/config/source hash binding;
3. Windows PowerShell 5.1 parser and parameter-binding smoke for every v3 entry;
4. no-Unity lock-hygiene unit vectors on isolated synthetic paths;
5. controlled capture and cleanup of the already-observed attempt-2 stale lock;
6. immutable attempt-3 execution receipt;
7. full official unit gate;
8. Unity compilation;
9. native telemetry/CIM probe;
10. three positive Williams blocks;
11. expected-negative block with bounded post-exit lock handling;
12. six fresh cold-process structural controls and ten exact comparisons;
13. retained 63-assertion regression;
14. final hashes, preservation, root-boundary, lock, and authorization audit.

No later gate runs after a failure. Only item 11 may use post-exit controlled lock cleanup. Gate 11R/12R/13R never run under this authorization.

## 2. Synthetic no-Unity lock vectors

The v3 unit suite must test the lock module without touching the real project lock:

- missing lock reports natural absence;
- exact zero-byte leaf with matching owner window is cleanup-eligible;
- nonzero file is rejected;
- wrong SHA-256 is rejected;
- creation/last-write time outside the owner window is rejected;
- wrong resolved path is rejected;
- directory/reparse target is rejected;
- nonexclusive/open failure is rejected;
- any Unity process or live owned PID is rejected by the policy function;
- positive-process policy never authorizes deletion;
- expected-negative policy writes pre-delete capture before deletion;
- completion receipt binds capture hash and proves lock absence;
- create-new receipts refuse overwrite;
- no recursive or wildcard deletion token exists in the implementation.

Synthetic fixtures remain inside the v3 preflight evidence root; they are not experimental samples.

## 3. Attempt-2 stale-lock cleanup test

Before cleanup, independently verify PID absence, global Unity count zero, literal resolved path, file type, 0-byte length, empty-file hash, timestamp inclusion, exclusive access, and attempt-2 owner-summary hash. Write the pre-delete receipt before removal. After exact removal, verify PID absence, zero Unity, lock absence, v1/v2 tree hashes unchanged, and no other `Temp` entry was removed.

## 4. Full Gate 10R regression

Attempt 3 reruns the entire Gate 10R gate sequence from the unit stage; it does not resume attempt 2. Existing Gate 10R unit vectors, compile checks, telemetry cross-check, Williams balance, reset/memory rules, fail-closed atomicity, independent-process repeatability, cold structural exact-match, and retained regression remain unchanged.

Additional runtime assertions require a per-process post-exit quiescence receipt. Positive/compile/probe/cold receipts must state `natural-lock-absence`; the expected-negative receipt may state either `natural-lock-absence` or `controlled-expected-negative-cleanup` with valid capture binding.

## 5. Successful close

The final audit requires:

- unit, compile, probe, block verification, cold controls, and retained 63/63 all pass;
- structural mismatches: 0/10;
- positive blocks use three distinct Unity PIDs;
- no Unity process or project lock remains;
- v1/v2 manifests and root tree identities remain exact;
- Gate 11R, Gate 12R, Gate 13R, and Playable roots remain absent;
- Gate 11R/Gate 12R continuation authorization fields are false;
- checkpoint status is `GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION`.

