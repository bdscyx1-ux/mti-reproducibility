# Gate 13R-PR2-MP1 v2 checkpoint state-machine amendment

Status: `NON-FORMAL / PRE-FORMAL / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

This amendment changes only MP1 orchestration persistence. It does not change the frozen scientific matrix, algorithm implementation, scenario identity, Williams order, telemetry, memory thresholds, reset semantics, safety stops, or two-stage analysis boundary.

## Confirmed defects repaired

1. A deserialized PowerShell `PSCustomObject` can reject assignment to a property that did not exist in the serialized object. The v2 checkpoint therefore declares every mutable field at creation, and every transition builds a new complete ordered object instead of mutating deserialized state.
2. Passing a null backup path to `System.IO.File.Replace` is not safe on the active PowerShell 7/.NET 10 runtime. The v2 writer uses a non-empty, same-directory, unique backup path, verifies destination SHA-256 and JSON read-back, then removes its owned backup only after the commit is proven.
3. The measured orchestrator catches failures before the first block as well as failures inside a block and between completion and raw freeze. Each failure path creates a durable partial/zero-output manifest, failure receipt, and failed checkpoint before returning non-zero.

## State machine

`AUTHORIZED-NOT-STARTED` → `MEASURED-ACQUISITION-RUNNING` → repeated `BLOCK-PROGRESS` → `PHASE-A-COMMIT-IN-PROGRESS` → `PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`.

From every non-terminal state, a hard failure may transition once to `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`. Terminal states cannot transition.

## Atomicity contract

- Create-new artifacts fail if the destination already exists.
- Replacements occur in the same directory through a unique temporary file and a non-empty unique backup path.
- Every successful write verifies destination existence, SHA-256 equality, JSON read-back, schema validity where applicable, and absence of residual owned temp/backup files.
- A failed replacement retains recoverable evidence rather than silently deleting the only valid backup.

## Authorization boundary

Pilot v1 remains immutable and is never retried, resumed, topped up, merged, or reinterpreted. MP1 v2 permits at most one measured acquisition after all pre-pilot gates pass. Gate 13R-PR2 formal attempt 3, formal statistical analysis, and Gate 14R remain unauthorized.
