# Gate 13R-PR2 candidate failure-precedence wrapper specification v1

Status: `NON-EXECUTING / CANDIDATE-ONLY / NOT-ACTIVE / FORMAL-ATTEMPT3-NOT-AUTHORIZED`

## Confirmed defect

The frozen active V6 block wrapper calls post-exit quiescence before it reads the Unity-emitted `block-failure.json`. If quiescence throws because a zero-byte lock remains after Unity has exited, the outer error becomes the visible terminal error even when Unity already wrote a durable block failure.

This does not erase the durable primary record, but it masks it in the outer status and makes diagnosis needlessly ambiguous.

## Candidate semantics

A future, separately authorized wrapper revision should:

1. Invoke post-exit quiescence inside a catch boundary that records, but does not discard, the quiescence exception.
2. Read any durable `block-failure.json`, block checkpoint, Unity exit status, timeout status, and quiescence-failure receipt before selecting terminal precedence.
3. Treat a durable Unity/block failure as primary when it predates and explains the failed block.
4. Append the post-exit quiescence failure as a separate secondary cause.
5. Persist both causes in the wrapper summary, formal checkpoint, status sidecar, and partial-output manifest.
6. Fail closed before the next block regardless of whether one or both causes exist.
7. Never convert lock deletion into authorization to continue, retry, resume, top up, or merge the attempt.

## Candidate precedence

1. Durable Unity/block failure.
2. Hard timeout.
3. Non-zero Unity exit without a durable block failure.
4. Post-exit quiescence failure when no earlier primary cause exists.

Quiescence remains a hard failure in every case; its position in the list controls reporting, not eligibility.

The accompanying module is a pure, validation-only resolver. It does not launch Unity, delete locks, alter the failed root, or activate a new wrapper.
