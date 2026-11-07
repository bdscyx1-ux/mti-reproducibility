# Gate 13R-PR2-MP1 attempt 2 / v2 test design

## Purpose

Prove that the checkpoint-state and path-safe atomic persistence repair works under both PowerShell 7 and native Windows PowerShell 5.1 without changing the frozen MP1 scientific design.

## New persistence tests

1. Parse and bind every v2 PowerShell entry under both runtimes.
2. Create an initial checkpoint and prove that all later mutable fields already exist.
3. Exercise the complete success state sequence and validate every serialized read-back.
4. Exercise independent failures before block 1, inside a block, and after block 96 but before raw freeze.
5. Verify create-new refusal, replace with a non-empty backup, destination SHA-256, schema read-back and zero residual owned temp/backup artifacts.
6. Inject a zero-block outer-orchestrator failure; require an automatic durable failure receipt, zero-output manifest and failed checkpoint, and prove Unity was not started.
7. Exercise a synthetic raw-complete transition with a persisted 64-hex `rawTreeSha256`.

## Retained scientific and systems tests

- 96 schedule rows / 384 samples / 0 warm-up and 16/16/16/48 scale allocation.
- Williams row, position and predecessor balance; deterministic schedule regeneration.
- Unity compile plus memory-policy and path-safe-atomic self-tests.
- PSAPI/CIM telemetry probe and managed/native stage telemetry.
- Positive complete block and injected negative fail-closed block.
- Failure precedence, lock hygiene, correctness, structural exact match, per-sample reset and licensing evidence.
- Hash/provenance, v1/formal-attempt-2 immutability, v2-root absence and formal-attempt-3 absence before launch.

## Stop policy

Validation-only implementation defects may be repaired in new versioned validation attempts before the measured root exists. Once the one-shot v2 measured acquisition begins, any acquisition hard failure ends the pilot with no retry, resume, top-up or merge. After a successful Phase-A freeze, ordinary analysis defects may be repaired only by a new read-only analysis attempt against the same immutable raw tree.
