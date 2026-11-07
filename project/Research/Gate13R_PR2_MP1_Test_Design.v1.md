# Gate 13R-PR2-MP1 validation and test design v1

Status: `FROZEN-BEFORE-PILOT / VALIDATION-ONLY-GATES / MEASURED-RETRY-PROHIBITED`

## Gate order

1. Re-hash the five FD1 active inputs and re-audit the complete attempt-2 root.
2. Parse all new JSON/JSONL under strict duplicate-ID, finite-number, absolute-path, and schema rules.
3. Verify deterministic schedule regeneration, stable ordinal serialization, file hashes, 96/384 totals, 16/16/16/48 quotas, Williams row quotas, algorithm × position balance, predecessor balance, unique block/run/output identities, and zero warm-up observations.
4. Run Python/PowerShell unit and synthetic fixture tests under current PowerShell and Windows PowerShell 5.1.
5. Compile the new Unity command without modifying retained V4/V5/V6 files.
6. Run a validation-only telemetry probe and prove PSAPI/CIM identity, positive values, timestamp order, process-start tolerance, byte units, and process composite identity.
7. Run one complete validation-only positive g032 Williams block and validate correctness/structure, full reset, stage completeness/deltas, sample/block memory policy, hashes, and post-exit quiescence.
8. Run a separate validation-only injected-failure block and prove durable block failure is primary, quiescence is separately retained, partial output is atomic, and no next block is authorized.
9. Run negative fixtures for missing telemetry, mixed PID/start/block identity, time reversal, zero/non-finite/overflow, exact/one-byte-over thresholds, unsafe paths, duplicate IDs, partial blocks, unsafe lock targets, and receipt/config/hash mismatches.
10. Re-hash frozen inputs, prove attempt-3 root/receipt absence, Unity quiescence, and no writes to attempt 2.

## Boundary fixtures

Synthetic fixtures cover exact and one-byte-over values at 128 MiB, 256 MiB, 512 MiB, 640 MiB, 768 MiB, 1,024 MiB, 2 GiB, 4 GiB, and 8 GiB. Negative deltas must remain numeric and valid. Missing, boolean-as-number, NaN, Infinity, and checked overflow must fail closed.

## Williams fixtures

For g032/g064/g128 each row must occur four times; for g256 each row must occur twelve times. Every algorithm must occur equally often at positions 1–4 within a scale. Predecessor counts must exactly match deterministic expansion of all scheduled rows; tests compare generated counts to a separately coded expected table.

## Measured execution boundary

Before measured start, all gates must be recorded as passed in a versioned pre-pilot checkpoint and the exact pilot root and execution receipt must be absent. Only then may the root and receipt be created and one measured attempt begin.

After measured start, any hard failure saves an atomic failure receipt, partial manifest, checkpoint, current block/run/stage, file count/bytes/tree hash, and stops. There is no automated retry, resume, top-up, or merge.

## Raw/analysis recovery test

The analysis runner must reject any raw root without a valid immutable Phase-A receipt. It must prove its output path is outside the raw root and create a fresh versioned directory. A synthetic analysis exception must leave raw hashes unchanged and permit only a new analysis-attempt directory—not a Unity invocation.
