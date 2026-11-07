# Gate 12R managed-memory aggregation test design (v1)

## Purpose

Validate the prospective memory-gate amendment without changing workload, timing, telemetry, reset, Williams, scenario, precision, or exclusion semantics.

## Static and unit requirements

1. The new Unity command must retain the 134,217,728-byte per-sample limit.
2. The block limit must be calculated with checked integer arithmetic as `134217728 * expectedSampleCount`.
3. A two-sample block must publish a 268,435,456-byte managed limit; a four-sample block must publish 536,870,912 bytes.
4. A sample at the limit passes and a sample one byte above the limit fails before a block completion marker can be written.
5. A block at its scaled limit passes and a block one byte above fails without a block completion marker.
6. Working-set and private-memory block limits remain 536,870,912 bytes.
7. The memory policy ID, per-sample limit, scaled block limit, expected sample count, and formula ID must be present in each completed block manifest.
8. The previous V2 command, v3 plan, v3 provenance, and v3 pilot root must remain byte-identical.

## Unity integration requirements

Run fresh two-sample and four-sample positive Williams blocks. Confirm per-sample full-GC telemetry, sample-level 128 MiB checks, correct scaled block limit, exact Williams order, one Unity process per block, reset fields, hashes, and completion markers. Run a negative block with injected intermediate-position failure and confirm no later position, no automatic retry/resume, and no completed block manifest.

## Fresh pilot rule

The first pilot using this amendment starts at a new root. It reruns all warm-up, cold structural controls, and measured blocks. Earlier attempts remain excluded and cannot contribute observations, variance, correlation, storage projection, or candidate `n_formal`.
