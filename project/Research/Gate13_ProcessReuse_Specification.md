# Gate 13-R2 Process-Reuse Specification v1

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan / run
- Origin Date: 2026-10-06
- Verification Status: SPECIFICATION-FROZEN-BEFORE-IMPLEMENTATION
- Version Label: `gate13_process_reuse_specification_v1`

## 1. Authority and scope

This specification implements the user's 2026-10-06 authorization to terminate the partial Gate 13 cold-process attempt 2 and prepare a replacement process-reuse design. It authorizes research-only implementation, tests, and one isolated non-formal pilot. It does not authorize a formal process-reuse campaign, a formal execution receipt, creation of `Research/FormalRuns/Gate13_ProcessReuse/v1`, automatic retry, or automatic resume.

The following historical inputs remain byte-frozen: the Gate 11 retained bundle, the successful Gate 12 `v1` pilot, both failed Gate 12 archives, Gate 13 readiness amendment v1, the cold-process Gate 13 config and execution receipts, all original scripts, and all original scenes. New implementation must be additive and research-only.

## 2. Supersession boundary

`Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md` remains an immutable record of the cold-process design. Its rule that one Unity process may produce only one algorithm sample remains valid for Gate 10, Gate 12, and the terminated Gate 13 cold-process attempt. This document introduces a scoped replacement only for Gate 13-R2 and later analysis explicitly bound to the process-reuse config.

The cold-process partial root `Research/FormalRuns/Gate13/v1` has disposition:

- `USER-TERMINATED-DESIGN-CHANGE`;
- `EXCLUDED_FROM_ANALYSIS`;
- `NO-AUTO-RETRY`;
- `NO-RESUME`;
- `SUPERSEDED-BY-PROCESS-REUSE-DESIGN`.

It cannot contribute to formal inference, formal sample-size estimation, Gate 14, or a merged process-reuse table.

## 3. Experimental units and process ownership

The independent runtime unit is one complete Williams block executed in one newly launched Unity Editor process.

1. A four-algorithm block contains exactly one `A*-R`, one `D*L`, one `C-FF`, and one `IDFF` sample in its frozen Williams order.
2. A two-algorithm block contains exactly one authorized sample of each cohort algorithm in its frozen Williams order.
3. An algorithm appears at most once in a process.
4. No Unity process may execute more than one Williams block.
5. No Unity process may execute samples from different scenarios, cohorts, or formal campaigns.
6. A long-lived campaign-level Unity process is prohibited.
7. Separate block processes are the independent replication clusters. Samples inside a block are correlated repeated observations of that process and must retain the block/process identity in analysis.

The Gate 11 scenario order, deterministic seeds, canonical identities, eligibility rules, cohort membership, and Williams rows remain unchanged. For a given campaign, the entry order and canonical schedule SHA-256 remain identical to the cold-process config; only the mapping from entries to Unity processes changes.

## 4. Per-sample state isolation

Before every sample, including position 1, the process-reuse command must execute the same cleanup boundary outside all planner timing endpoints:

1. `GC.Collect()`;
2. `GC.WaitForPendingFinalizers()`;
3. `GC.Collect()`.

Every sample then creates fresh instances of:

- the loaded deterministic scenario definition and resolved scenario;
- research grid;
- planner;
- experiment runner;
- workload accumulator and phase records;
- JSONL logger, queue, writer, and background writer thread;
- run manifest and all output paths.

`DeterministicPlanningWorkloadRunner.Run` must dispose the `ExperimentRunner`; disposal must call `planner.Reset()`. The logger must flush, dispose, and join its writer thread before the next sample starts. No mutable sample object may be deliberately retained across samples. Static mutable planner state is prohibited; static immutable lookup tables are allowed and must be identified by static audit.

Forced collection time, Unity startup time, manifest/hash time, and inter-sample cleanup time are not added to `totalPlannerElapsedMilliseconds`. They are block/process overhead diagnostics. JIT and runtime cache effects are not claimed to be eliminated; Williams position/predecessor balance and recorded telemetry address them explicitly.

## 5. Fail-closed behavior

Each block has an atomic checkpoint written before and after every position. Each sample has a create-new output directory, unique run ID, standalone canonical scenario, JSONL operations log, workload result, atomic manifest, and atomic `sample-summary.json` completion marker. The sample summary binds the workload-result and manifest SHA-256 values; the completed block manifest binds the sample-summary SHA-256.

If any sample, flush, reset, hash, identity, or telemetry validation fails:

- write a block failure record and final block checkpoint atomically;
- retain the partial block and all completed prior positions;
- execute no later position in that block;
- return a non-zero Unity process exit;
- attempt no retry and no resume.

No partial block is eligible for measured pilot analysis or a future formal campaign. A future replacement, if separately authorized, must use a new block/process identity and complete Williams cycle policy.

## 6. Telemetry and provenance

Every sample manifest must retain the existing fairness, scenario, implementation, specification, workload, and Unity provenance and add:

- process-reuse schema and design IDs;
- process ID and process start time;
- block ID and block ordinal;
- within-process position and cohort size;
- immediate predecessor algorithm, or `NONE` at position 1;
- process age before and after the sample;
- working-set, private-memory, and managed-memory bytes before and after;
- GC collection counts for generations 0, 1, and 2 before and after;
- forced-GC boundary completion;
- process-reuse command/specification SHA-256;
- block plan SHA-256;
- `formalCampaign = false` for pilot outputs.

Block manifests must prove that all entries used one process ID, every authorized algorithm appears exactly once, order equals the frozen Williams row, all child hashes validate, and no later sample ran after a failure.

## 7. Structural equivalence

The pilot must create fresh, excluded cold-process reference runs for each selected scenario × authorized algorithm. Process-reuse samples must exactly match their corresponding cold reference on deterministic structural fields:

- scenario ID, fingerprint, source hash, and canonical hash;
- algorithm/cohort/fairness/provenance identities;
- agent/event/phase counts;
- plan, repair, success, no-path, invalid, failed, and budget-overrun counts;
- final grid version and fixed-start flag;
- processed nodes/cells, expanded nodes, relaxed edges, and repaired cells;
- each dynamic phase's tick, event IDs, final grid version, operation/status counts, and structural work counters.

Elapsed times, managed allocation values, timestamps, process telemetry, run IDs, and output paths are intentionally excluded from exact equality. Any structural mismatch blocks readiness.

## 8. Pilot design

The isolated pilot root is `Research/PilotRuns/Gate13_ProcessReuse/v1`. It is create-new and permanently marked `NON-FORMAL / EXCLUDED_FROM_FORMAL_ANALYSIS`.

The frozen measured subset is:

- `core-r01-s1-shared`, four-algorithm cohort, 12 complete blocks / 48 samples;
- `core-r01-s1-hetero`, per-agent cohort, 12 complete blocks / 24 samples;
- `core-r01-s1-hetero`, grouped-field cohort, 12 complete blocks / 24 samples.

One four-algorithm process-reuse block is run first as excluded thermal/JIT warm-up. Eight fresh cold reference processes cover every scenario/cohort/algorithm combination needed for structural comparison. The measured process-reuse pilot therefore contains 36 independent block processes and 96 samples; the warm-up and cold controls are excluded from noise and candidate-`n_formal` estimation.

No pilot result may be copied, promoted, or linked into the reserved formal root.

## 9. Precision and sample-size semantics

The 10% two-sided 95% relative CI half-width target and cap 148 remain unchanged. `n` now denotes independent Williams-block processes per scenario/cohort; because each algorithm appears once per block, it is also the per-algorithm observation count.

For each preregistered family, the pilot must report:

1. the maximum valid marginal standard deviation of the natural-log primary endpoint across scenario × algorithm cells;
2. the maximum valid within-block paired standard deviation of the natural-log endpoint difference for the preregistered algorithm contrast;
3. the maximum of the two resulting required sample sizes.

For either standard deviation `sigma`, use:

```text
n_raw = ceil((1.96 * sigma / ln(1.10))^2)
required_n = next_multiple_of_4(max(30, n_raw))
candidate_n_formal = min(148, required_n)
```

The conservative family candidate is the larger of the marginal and paired requirements. P1 and P3 must be harmonized to the larger scheduled value within the shared four-algorithm cohort. Any requirement above 148 blocks the future formal campaign pending another explicit versioned decision. No significance-, trend-, or variance-based early stopping is allowed during a future formal campaign.

## 10. Position, carryover, age, GC, and memory assessment

The pilot must retain and summarize:

- algorithm × position counts;
- ordered predecessor counts;
- endpoint distributions by algorithm and position;
- paired predecessor contrasts where estimable;
- endpoint association with process position and process age;
- GC deltas and memory deltas by position and algorithm;
- block wall time and per-sample planner time;
- process working-set and managed-memory growth.

Balance and telemetry completeness are hard gates. Position/carryover estimates are diagnostic because the pilot is small; they must remain visible and inform the future analysis model. Structural mismatch, missing process identity, duplicate algorithm in a block, multiple blocks in one process, incomplete block acceptance, non-finite telemetry, or a final managed-memory increase greater than 128 MiB or working-set increase greater than 512 MiB within a measured block is a readiness failure.

## 11. Reserved formal design

The reserved formal root is `Research/FormalRuns/Gate13_ProcessReuse/v1`. This turn must not create it. A prepared config may name it, but only a future user-authorized, versioned execution receipt bound to the final config, amendment, implementation hashes, pilot result, storage preflight, and exact root may permit creation.

The projected formal mapping is 74 campaigns, 15,056 algorithm samples, and 5,864 newly launched Unity block processes. These counts are design projections only until the pilot re-estimates candidate `n_formal`; the config cannot authorize execution.

## 12. Downstream analysis boundary

Gate 14 may accept only one design identity. If a future process-reuse formal campaign is authorized and completes, Gate 14 must accept only its config/root/manifest hashes. It must reject the cold-process root, the process-reuse pilot, warm-up, fresh cold controls, partial blocks, and mixed execution-design tables.
