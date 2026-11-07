# Gate 13R-PR1B v3 path-safe pilot failure diagnosis

Status: `FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`  
Classification: `NON-FORMAL / COMPLETE-RAW-EXECUTION / POST-EXECUTION-ANALYZER-FAILED / EXCLUDED-FROM-FORMAL-ANALYSIS`

## Outcome

The path-safe pre-pilot verification passed at `v16`, including 124/124 static checks, 111/111 final validation-only checks, Unity compilation, path-boundary tests, telemetry, positive and negative block tests, independent-process repeatability, cold structural control, retained 63/63 regression, provenance, and final audit.

The one authorized fresh pilot then completed all planned execution:

- 12 warm-up Unity block processes and 24 excluded samples;
- 96 measured mirrored pairs;
- 192 measured AB/BA matched superblocks;
- 384 measured fresh Unity block processes;
- 768 measured algorithm samples;
- zero incomplete blocks and zero incomplete samples.

After the raw execution completed, the frozen order-effect analyzer failed before producing `order-effect-analysis.json` or `pilot-manifest.json`. The orchestrator correctly wrote a failure receipt, failed checkpoint, and partial-output manifest and stopped. No retry, resume, top-up, merge, or independent analyzer rerun was performed.

## Root cause

The failure was caused by an analyzer process-identity contract that treats the numeric Windows PID as globally unique across the full run:

```python
process_id = int(block["processId"])
require(process_id not in seen_processes,
        f"duplicate Unity process identity: {process_id}")
```

Windows may legally reuse a PID after its previous process exits. During this approximately two-hour strictly serial pilot, 396 completed Unity process records used 375 distinct numeric PID values. There were 19 PID-reuse groups; the largest multiplicity was three. No reused PID had overlapping process lifetimes.

The first analyzer rejection reported PID `27512`. The two records were distinct fresh processes:

- `g13r-pr1b-m-b004-ab-s2-goal-count-g32-hetero-grouped-field-b004`, process start `2026-10-08T13:42:57.2674176Z`;
- `g13r-pr1b-m-b010-ab-s2-core-r01-s1-hetero-per-agent-b010`, process start `2026-10-08T14:01:32.1002827Z`.

The frozen block manifests already record `processStartTimeUtc`. The composite evidence identity `(processId, processStartTimeUtc, blockId)` is unique for all 396 completed process records, and reused PID lifetimes do not overlap. The failure therefore reflects an overly strict analyzer identity check, not process reuse within a block and not a violation of the one-fresh-process-per-block topology.

## What did not fail

- All 396 block manifests completed.
- All 792 sample summaries, workload results, and memory-gate evaluations exist.
- All 768 measured samples completed.
- Every block reports `hardMemoryRulesPassed=true`.
- No sample reached the 128 MiB retained-managed alert threshold.
- Maximum observed retained-managed growth was 70,815,744 bytes per sample and 128,217,088 bytes per block, below the frozen limits.
- Maximum block working-set and private-memory growth were 373,817,344 and 421,298,176 bytes, below the frozen 512 MiB limits.
- The end environment audit passed, with no Unity process, no project lockfile, and no formal output root.
- All 77 provenance-bound files match their frozen size and SHA-256.
- Frozen v6 and verification v9-v16 tree identities remain unchanged.

These facts are diagnostic only. They do not convert the failed pilot into a successful pilot and do not authorize order-effect or formal inference.

## Frozen evidence

- Pilot root: `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4`
- Root inventory: 9,118 files, 253,513,394 raw bytes.
- Canonical tree SHA-256: `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`.
- Failure receipt SHA-256: `c9f8a96aa1ff953e84bcdcc5a7b70be2a635f764e4970824b1891473046d2680`.
- Failed checkpoint SHA-256: `b98888e7c89537f9f533712422c646289a08b6999de287fd1c8597301cfdd60c`.
- Execution manifest SHA-256: `df33956d5622d03f5965dabc2c43d96e0314fa65aec04da9e6b536d1d5b6f688`.
- Partial-output manifest SHA-256: `d31c9f9e08eb93b4775d83ff43c94c3b5345ba3c02ab5f519cba619e6319cd00`.

The root must remain byte-frozen and must not be resumed, topped up, merged, reclassified as successful, or written to by a repaired analyzer.

## Recommended next step

The least wasteful scientifically defensible next step is a separately authorized, versioned, analysis-only recovery:

1. Keep the failed pilot root immutable and failed.
2. Define OS process identity as `(processId, processStartTimeUtc)` and bind it one-to-one to `blockId`.
3. Require 396 unique composite block identities, non-overlapping lifetimes for every reused PID, two samples sharing the same block process, unique run IDs, and all existing hash/completion gates.
4. Add synthetic tests for legal sequential PID reuse, illegal overlapping lifetimes, duplicate composite identity, inconsistent sample PID, missing/invalid start time, and deterministic regeneration.
5. Write any recovered analysis only to a separate versioned analysis root, never into the failed pilot root.
6. Run no Unity process and create no new experimental observation.

This requires new user authorization. Gate 13R formal execution and Gate 14R remain unauthorized.
