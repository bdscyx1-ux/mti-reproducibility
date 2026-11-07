# Gate 13R 36-hour four-lane expected-negative lock-hygiene test design v5

## Material passport

- Origin skill: `academic-research-suite / experiment-agent`
- Mode: specification, validate, then run
- Status: frozen before Gate 13R v5 implementation
- Scope: non-formal verification wrapper only

## Frozen scientific design

This repair does not change the 74-campaign matrix, deterministic scenarios or seeds, Williams orders, one fresh Unity Editor per Williams block, per-sample reset, algorithms, metrics, telemetry, 128 MiB managed-memory rule, native-memory rules, 10% per-campaign relative 95% CI half-width, uncapped sample-size calculation, four-lane topology, 27-hour readiness p95 gate, 36-hour formal wall-clock limit, or Playable mappings. The Unity C# command remains byte-identical.

## Lock policy

`Research/Gate10R_Attempt3_Lock_Hygiene_Specification.v1.md` and `Research/Gate10RLockHygieneV3.psm1` remain the normative lock policy and implementation. Positive verification, telemetry, compilation, warm-up, measured pilot, and any future formal block require natural lock disappearance. They may never delete a lock.

Controlled cleanup is allowed only when all conditions below hold:

1. wrapper mode is `Verification`;
2. `ExpectFailure` is present;
3. block-plan role is exactly `excluded-negative-fail-closed-verification`;
4. the owned process has exited and no `Unity.exe` process exists globally;
5. 60 seconds of 250 ms natural-quiescence polling has elapsed;
6. the literal `<lane>/Temp/UnityLockfile` is a zero-byte, non-reparse leaf with the empty-file SHA-256;
7. it can be opened exclusively read/write;
8. creation and write timestamps lie within the owned process window plus/minus two seconds;
9. an atomic pre-delete capture receipt is written before exact non-recursive removal;
10. an atomic completion receipt proves PID absent, Unity count zero, and lock absent.

Any failed predicate prohibits deletion and fails the gate. The failed v4 lane lock is historical evidence and must not be removed by v5 work.

## No-Unity unit vectors

The versioned v5 unit runner must test at least:

- the valid expected-negative vector;
- refusal for positive role;
- refusal while the owned PID is marked alive;
- refusal when Unity count is nonzero;
- refusal for a non-exact path;
- refusal for a directory/reparse target;
- refusal for nonzero bytes or non-empty SHA-256;
- refusal when exclusive access is unavailable;
- refusal for timestamps outside the process window;
- one controlled cleanup against only a fresh synthetic project lock below the unit-test output root, including capture/completion receipt hashes and an absent final lock.

The unit test must start no Unity process and create no verification, pilot, or formal root.

## Versioned verification

Only after parser, parameter binding, provenance, frozen-input hashes, the no-Unity unit vectors, and output isolation pass may a new v5 nonexecuting verification root and four new v5 lane copies be created. The negative fixture remains serialized after the positive concurrent wave. A v5 verification failure is terminal for v5; it cannot resume or merge. The sole measured NON-FORMAL pilot remains unconsumed until validation-only audit passes.

