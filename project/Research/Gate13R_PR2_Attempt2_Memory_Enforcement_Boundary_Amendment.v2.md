# Gate 13R-PR2 attempt 2 memory enforcement-boundary amendment v2

Status: `NON-EXECUTING / FAILURE-DIAGNOSTIC-ONLY / MEMORY-POLICY-UNFROZEN / FORMAL-ATTEMPT3-NOT-AUTHORIZED`

## Purpose

This amendment preserves the original FD1 v1 diagnostic and adds one interpretation that the frozen evidence requires: a block-level native-memory threshold can be measured as exceeded before the command is permitted to enforce the block-level hard gate.

## Frozen implementation semantics

`Gate13RPR2FormalBatchCommandV4.cs` records working-set and private-memory block-growth flags at every sample boundary. Its frozen fixtures explicitly defer non-final block-limit exceedances, and its production path appends block-level hard-fail reasons only when `finalSampleInBlock` is true.

## Attempt 2 evidence

In failed block `g13rpr2-c52-b0022`, both 512 MiB native limits were already exceeded after position 1 (`A*-R`, predecessor `NONE`). The exceedance persisted at positions 2 and 3. Position 4 (`C-FF`, predecessor `IDFF`) was the final sample boundary and therefore the point at which the command emitted the durable hard-fail record.

Consequently:

- C-FF is the enforcement point, not an identified cause of the native-memory growth.
- A*-R is the first observed crossing position, not an identified cause either.
- Algorithm, Williams position, predecessor, normal g256 residency, and native-leak causality are not identifiable from this single process/block.
- Attempt 2 remains failed and permanently excluded; this amendment changes neither its threshold nor its disposition.

## Prospective consequence

Any future memory-policy selection requires a balanced, non-formal pilot with stage-separated telemetry: process start, post-project load, post-scenario load/pre-sample, every sample boundary, every cleanup boundary, and post-block. All four algorithms must rotate through Williams positions/predecessors in fresh block processes, with g256 and lower-scale controls.
