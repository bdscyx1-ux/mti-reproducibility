# Gate 13R-PR1B Order-Effect Pilot Attempt 1 Failure Diagnosis

Status: `FAILED-NO-RETRY-NO-RESUME-NO-MERGE`  
Analysis role: failure diagnosis only; no order-effect or algorithm-effect inference  
Formal campaign: not authorized and not created

## Outcome

The balanced mirrored heterogeneous order-effect pilot passed its complete pre-pilot gate, completed all 12 excluded warm-up block processes, and completed the first 12 measured block processes. It then failed closed on the thirteenth measured process. The failed process was:

- scenario: `core-r07-s2-hetero`;
- wave/block: `2`;
- mirrored superblock order: `BA`;
- first cohort process: `grouped-field-heterogeneous-goal-v1`;
- first algorithm: `IDFF` at position 1 with predecessor `NONE`;
- process ID: `13692`;
- run ID: `g13r-pr1b-m-b002-ba-s1-core-r07-s2-hetero-grouped-field-b002-p01-idff`.

The planning workload itself completed. The hard failure occurred afterward, during cleanup telemetry evaluation:

> Sample retained managed-memory growth exceeded the frozen 128 MiB limit.

No later sample in the block was executed. The orchestrator did not start the next process.

## Progress preserved

| Item | Planned | Completed before failure |
|---|---:|---:|
| Excluded warm-up processes | 12 | 12 |
| Excluded warm-up samples | 24 | 24 |
| Measured processes | 384 | 12 |
| Measured samples | 768 | 24 |
| Measured mirrored pairs | 96 | 3 |

All partial measured output is permanently `EXCLUDED-FROM-FORMAL-ANALYSIS` and `EXCLUDED-FROM-ORDER-EFFECT-INFERENCE`. Three complete pairs are not enough to estimate the preregistered order effect and, more importantly, belong to an attempt terminated by a hard eligibility gate. They must not be topped up, merged, or interpreted.

## Primary and secondary failure

The primary failure is the per-sample retained managed-memory hard gate in `Gate12RProcessReuseBatchCommandV3`. Its sequence is:

1. force a full collection boundary;
2. capture the sample baseline;
3. execute the workload and reset the planner/logger;
4. force another collection boundary;
5. capture after-cleanup telemetry;
6. calculate `afterCleanup.managedMemoryBytes - before.managedMemoryBytes`;
7. throw when the value is greater than `134217728` bytes.

The secondary failure is lock hygiene after Unity terminated with exit code 1. Unity left `H:/DDM_Final_Project/Temp/UnityLockfile`, a zero-byte file that was exclusively accessible and had no associated live Unity process. The wrapper correctly refused to delete it because cleanup had not been authorized. This lock is evidence of the abnormal exit, not the root cause.

## What can and cannot be inferred

The failed IDFF workload produced a complete `workload-result.json`. Thirty-four deterministic structural fields were compared with the successful Gate 12R v4 sample for the same canonical scenario, block, cohort, position, and algorithm. All 34 matched, including scenario fingerprint, operation counts, success/failure counts, grid version, processed nodes/cells, expanded nodes, relaxed edges, repaired cells, cohort identity, planner-state identity, and dynamic work counts.

Therefore:

- this attempt does not show an IDFF correctness divergence;
- it does show a retained-memory eligibility event after a structurally complete workload;
- it does not provide a valid order-effect estimate;
- it does not affect any formal Gate 13R result because no formal root, receipt, or sample exists.

## Historical telemetry comparison

The frozen Gate 12R v4 pilot contains 1,176 completed sample manifests with retained managed-memory telemetry:

- samples above 128 MiB: `0`;
- maximum across all algorithms/positions: `101.26 MiB`;
- IDFF position-1 sample count: `98`;
- IDFF position-1 P95: `79.18 MiB`;
- IDFF position-1 maximum: `95.22 MiB`;
- exact historical counterpart for this scenario/block/position: `-92,839,936 bytes` (`-88.54 MiB`).

This makes the current event a new outlier relative to the frozen pilot evidence. It does not, by itself, prove a reproducible leak.

## Observability defect

The exact failed retained-growth value cannot be recovered. The v3 command evaluates the hard threshold before writing `telemetryAfterCleanup` and `sampleRetainedManagedGrowthBytes` into a durable manifest. The failure artifacts preserve the threshold message but not the measurements that triggered it.

This is a diagnostics defect. It must be corrected prospectively in a new versioned command before any new pilot. Re-running the same attempt would neither repair the missing evidence nor respect the preregistered no-retry rule.

## Scientific risk of a blind retry

A blind retry can turn a position-specific or algorithm-specific memory failure into selection bias: a new attempt might pass merely because the outlier did not recur, while the failed attempt is silently ignored. An arbitrary post-failure threshold increase has the same problem. The next policy must be frozen before new observations, retain the attempt-1 failure, and apply identically to all algorithms and positions.

The recommended amendment aligns the hard retained-memory eligibility decision with the independent experimental unit—the complete Williams block process—while keeping the former 128 MiB threshold as a sample-level alert:

- always persist the three telemetry captures and calculated deltas before any threshold decision;
- retain `128 MiB` as a diagnostic sample alert threshold;
- use `256 MiB` as an emergency per-sample stop for this two-sample heterogeneous block;
- retain the existing `256 MiB` two-sample block retained-growth hard gate;
- retain the existing `512 MiB` working-set/private-memory block hard gates;
- retain full reset, structural, hash, process identity, no-retry, and fail-closed requirements;
- include warned samples in a preregistered sensitivity analysis rather than selectively deleting them.

This does not change P1–P5 definitions, algorithms, scenarios, Williams orders, order-effect estimands, or the formal research question. It changes only how memory-reset evidence is observed and how a sample-level warning is separated from a block-level independent-unit hard failure.

## Terminal evidence

- terminal preservation: `Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Terminal_Preservation.v1.json`;
- pilot root: `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v5-gate13r-pr1b-order-effect/`;
- failure receipt SHA-256: `ca378535590d9fda229d1b8f41511b0301269ba004d8b782ccae20208f3a4d25`;
- checkpoint SHA-256: `c1d0350a2ec6025743be82005247ddf180ff00aa99bbfb0d3ab7e5e39b762132`;
- partial-output manifest SHA-256: `08449a4ada4149b3e665d29ec94c32abf5a9ed725e8738e0e9e42e1b699d60a6`;
- frozen upstream inputs: `15/15` unchanged;
- project Unity processes after failure: `0`;
- reserved formal root: absent.

## Stop condition

Attempt 1 is terminal. Do not retry, resume, top up, merge, delete, rewrite, or use it for effect inference. The next action requires separate authorization for a versioned v2 observability/eligibility amendment, controlled stale-lock recovery, full validation, and one entirely fresh non-formal pilot root.
