# Gate 13-R2 v2 Telemetry/Readiness Specification

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan / run
- Origin Date: 2026-10-06
- Verification Status: SPECIFICATION-FROZEN-BEFORE-V2-IMPLEMENTATION
- Version Label: `gate13_r2_v2_telemetry_readiness_specification_v1`

## 1. Authority and non-execution boundary

This specification implements the user's 2026-10-06 authorization for a versioned Gate 13-R2 v2 telemetry/readiness repair and exactly one fresh non-formal pilot. It authorizes additive research-only implementation, verification, and the single pilot described here. It does not authorize a process-reuse formal campaign, creation of `Research/FormalRuns/Gate13_ProcessReuse/v1`, a formal execution receipt, automatic retry, automatic resume, or analysis of the failed v1 pilot as if it were usable evidence.

The following remain immutable historical evidence:

- `Research/FormalRuns/Gate13/v1` and its termination receipt, partial-output manifest, exclusion marker, checkpoints, logs, and diagnostics;
- `Research/PilotRuns/Gate13_ProcessReuse/v1` and its failure receipt, output manifest, checkpoint, logs, and diagnostics;
- the Gate 11 retained bundle;
- the successful Gate 12 `v1` pilot and both Gate 12 failed-attempt archives;
- Gate 13 cold-process configuration, amendments, authorizations, and attempt evidence;
- the Gate 13-R2 v1 specification, test design, pilot plan, provenance, source, and scripts;
- all original scripts and all original scenes.

The v1 pilot has disposition `FAILED-NO-AUTO-RETRY / NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS / NO-RESUME / CANDIDATE-N-NOT-ADMISSIBLE`. No v1 timing, variance, memory, or candidate-sample-size value may be carried into v2. V1 may be cited only as the documented reason for creating this prospectively frozen repair.

## 2. Design identity and independent unit

The v2 design ID is `one-fresh-unity-process-per-williams-block-v2-native-telemetry`.

The independent runtime unit remains one complete Williams block in one newly launched Unity Editor process:

1. one Unity process executes exactly one block;
2. a four-algorithm block executes exactly one `A*-R`, `D*L`, `C-FF`, and `IDFF` sample in the frozen Williams order;
3. a two-algorithm block executes exactly one sample of each cohort algorithm in the frozen Williams order;
4. an algorithm occurs at most once in a process;
5. no process crosses scenario, cohort, campaign, or block identity;
6. a campaign-long Unity process is prohibited;
7. samples inside a block are correlated repeated observations and retain block/process identity.

Gate 11 scenario bytes, deterministic seeds, canonical identity, eligibility, cohort definitions, exclusions, and Williams order remain unchanged. The pilot subset and counts are fixed in the versioned v2 pilot plan.

## 3. Windows native process telemetry

### 3.1 In-process source

Unity batch mode shall collect process memory through the Windows native `GetProcessMemoryInfo` API and `PROCESS_MEMORY_COUNTERS_EX`, using the handle and PID of the executing Unity process. The required fields are:

- `WorkingSetSize` as `workingSetBytes`;
- `PrivateUsage` as `privateMemoryBytes`.

The source ID is `windows-psapi-getprocessmemoryinfo-process_memory_counters_ex-v1`. A call failure, marshalling failure, PID inconsistency, or value less than or equal to zero is fatal. `System.Diagnostics.Process.WorkingSet64` and `PrivateMemorySize64` may be recorded for diagnosis but are not authoritative and cannot substitute for the native values.

Every capture records UTC time, Unity PID, process start UTC, process age, native working set, native private memory, managed memory, and GC collection counts for generations 0–2.

### 3.2 Independent operating-system cross-check

Before any workload fixture or pilot run, one dedicated Unity batch telemetry probe must perform a file handshake with its parent PowerShell process:

1. Unity captures native telemetry and atomically writes `telemetry-probe-ready.json` containing its PID, executable path, process start time, and first native values.
2. Unity waits without starting a workload.
3. The parent queries `Win32_Process` through CIM for that exact PID and records `ProcessId`, `Name`, `ExecutablePath`, `CreationDate`, `WorkingSetSize`, and `PrivatePageCount` in `external-os-query.json`, written atomically.
4. Unity reads that acknowledged query, captures native telemetry again, evaluates the frozen rules below, and atomically writes `telemetry-probe-result.json`.
5. Unity exits non-zero if any rule fails.

The CIM query is independent because it is executed by a separate OS process through `Win32_Process`, not through the Unity/Mono `Process` property or the in-process PSAPI call.

For each metric independently, let `L` and `U` be the smaller and larger of the native before/after values, and let `E` be the CIM value. Define distance to the native interval as zero when `L <= E <= U`, otherwise the absolute distance to the nearest endpoint. The pre-registered tolerance is:

```text
tolerance = max(67,108,864 bytes, ceil(0.25 * max(nativeBefore, nativeAfter, external)))
```

The metric passes only when all three values are positive and the distance is at most the tolerance. Both working set and private memory must pass. The ready timestamp must precede the external query timestamp, the external query must precede the second native capture, the entire handshake must complete within 60 seconds, the PID must match exactly, and the CIM creation time must agree with the native process start time within two seconds. These are method-validation rules, not pilot-derived thresholds.

The one successful probe result is a frozen input to all later v2 checks. Probe failure stops the sequence; it is not converted into a relaxed tolerance.

## 4. Managed-memory cleanup boundary

The managed-memory endpoint is prospectively changed from v1's pre-cleanup capture to a post-cleanup retained-memory capture. The numerical 128 MiB rule is unchanged.

For each sample:

1. outside all planner timing endpoints, run `GC.Collect()`, `GC.WaitForPendingFinalizers()`, then `GC.Collect()`;
2. capture `beforeSample` with `GC.GetTotalMemory(false)`;
3. create and execute the complete sample inside a non-inlined workload method;
4. flush and dispose the logger, join its writer thread, dispose the experiment runner, call planner reset through disposal, finalize all workload result files, and copy only scalar/string provenance into a lightweight return object;
5. capture `rawAfterWorkload` before the workload method returns; this is diagnostic only;
6. return from the workload method so scenario, grid, planner, runner, logger, metrics collector, phase collections, and other sample-local objects leave scope;
7. outside the workload method, run the same full collection sequence and capture `afterCleanup` with `GC.GetTotalMemory(false)`;
8. only after `afterCleanup`, write the sample manifest and completion summary using the lightweight return object.

The command must be compiled with the cleanup/workload method marked `NoInlining` so the lifetime boundary is explicit. It must not hold a returned reference to planner, grid, resolved scenario, runner, logger, workload result, or phase collection. Mutable static sample state is prohibited.

## 5. Leak and growth criteria

The following definitions are frozen before the first v2 probe or pilot:

- `sampleRetainedManagedGrowthBytes = afterCleanup.managedMemoryBytes - beforeSample.managedMemoryBytes`;
- `blockRetainedManagedGrowthBytes = lastSample.afterCleanup.managedMemoryBytes - firstSample.beforeSample.managedMemoryBytes`;
- `blockWorkingSetGrowthBytes = lastSample.afterCleanup.workingSetBytes - firstSample.beforeSample.workingSetBytes`;
- `blockPrivateMemoryGrowthBytes = lastSample.afterCleanup.privateMemoryBytes - firstSample.beforeSample.privateMemoryBytes`.

Managed-memory leak failure is operationally defined as either:

- any sample's retained managed growth exceeds 134,217,728 bytes; or
- the block's retained managed growth exceeds 134,217,728 bytes.

The 134,217,728-byte threshold is exactly 128 MiB and is not relaxed. Negative growth is permitted and retained as recorded. `rawAfterWorkload` growth cannot fail or pass the 128 MiB rule; it is reported only as peak/live-workload context.

Working-set and private-memory readiness each require positive values at every capture. A measured block fails readiness if either block endpoint growth exceeds 536,870,912 bytes (512 MiB). Negative growth is permitted. A trend over positions, process age, GC deltas, and raw-versus-cleanup reclamation is diagnostic and must be reported, but no diagnostic trend replaces the hard endpoint rules.

## 6. Per-sample reset and output contract

Each sample creates fresh instances of the loaded scenario definition, resolved scenario, research grid, planner, experiment runner, workload state, logger, writer queue/thread, metrics collector, manifest model, and output paths. Every sample has a unique run ID and create-new directory.

The following must complete before the next sample begins:

- workload result and canonical scenario are atomically finalized;
- JSONL counts match and the writer thread is joined;
- runner disposal and planner reset complete;
- sample-local objects leave the non-inlined method;
- full post-sample collection completes;
- native telemetry and post-cleanup managed memory are positive/valid;
- manifest and `sample-summary.json` are atomically written and hash-bound.

Every sample records `beforeSample`, `rawAfterWorkload`, and `afterCleanup`, the cleanup/reset flags, process identity, position/predecessor, block-plan hash, scenario/source/canonical hashes, implementation hashes, and `formalCampaign = false`. Each block manifest transitively binds all sample summaries and proves same PID, unique algorithms, correct order, full completion, and the three block growth values.

## 7. Fail-closed and atomicity policy

Before and after every position, the block writes an atomic checkpoint. If a sample, reset, cleanup, telemetry, hash, identity, structural, or output operation fails:

- atomically write `block-failure.json` and a terminal `failed-no-auto-retry` block checkpoint;
- retain the partial block and already completed samples;
- execute no later position;
- return a non-zero Unity exit code;
- perform no automatic retry and no resume.

The pilot orchestrator follows the same rule. It writes a terminal pilot failure checkpoint and partial-output manifest, then stops. A failed or partial v2 pilot root is never overwritten or resumed. This authorization permits exactly one pilot root creation and one pilot execution; a replacement would require a new user authorization and new versioned root.

## 8. Structural equivalence and independent-process repetition

Fresh excluded cold-process controls are produced under the v2 root for every selected scenario × eligible algorithm. Every process-reuse sample must exact-match its corresponding cold control on the fixed structural projection used by Gate 13-R2 v1: scenario/canonical/fairness identities, counts, statuses, grid version, planning work counters, and per-dynamic-phase structural fields. Runtime, allocation, process metadata, timestamps, run IDs, and paths are the only named exclusions. Wildcard exclusions are prohibited.

Before the pilot, the same valid fixture block is run twice in separate new Unity processes. Required outcomes are distinct PIDs and process-start times, identical block order, exact structural equality at every position, and valid independent hashes. These verification fixtures are excluded from pilot analysis.

## 9. One fresh non-formal pilot

The only authorized v2 pilot root is `Research/PilotRuns/Gate13_ProcessReuse/v2`. It is created exactly once, after the v2 design/implementation/provenance bindings exist, with an atomic `preparation-checkpoint.json` whose status is `PREPARATION-ONLY-PILOT-NOT-STARTED`. Before all static, unit, compile, telemetry-probe, positive-block, negative fail-closed, independent-process-repeatability, retained-regression, and validation-only gates pass, that root may contain only its preparation checkpoint and root initialization receipt; no warm-up, control, plan, measured-sample, pilot-start, or analysis output is allowed.

The pilot is permanently marked `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`. It contains:

- one excluded four-algorithm process-reuse warm-up block (1 process / 4 samples);
- eight fresh cold structural controls (8 processes / 8 samples);
- shared-goal four-algorithm cohort: 12 blocks / 12 processes / 48 samples;
- per-agent heterogeneous-goal cohort: 12 blocks / 12 processes / 24 samples;
- grouped-field heterogeneous-goal cohort: 12 blocks / 12 processes / 24 samples.

Totals are 45 Unity processes and 108 samples; only the 36 measured block processes / 96 measured samples enter v2 noise, correlation, and candidate-`n_formal` calculations. Warm-up, cold controls, v1 pilot, terminated cold formal samples, and verification fixtures are excluded.

## 10. Candidate sample size and correlation

The primary endpoint, 10% two-sided 95% relative-CI half-width target, cycle multiple 4, minimum 30 blocks, and cap 148 remain unchanged. `n` denotes independent Williams-block Unity processes per scenario/cohort. Within-process samples are correlated.

For each preregistered family, v2 computes both:

1. the maximum valid marginal standard deviation of the natural-log primary endpoint across scenario × algorithm cells;
2. the maximum valid within-block paired standard deviation of the natural-log endpoint difference for its preregistered contrast.

For either standard deviation `sigma`:

```text
n_raw = ceil((1.96 * sigma / ln(1.10))^2)
required_n = next_multiple_of_4(max(30, n_raw))
candidate_n_formal = min(148, required_n)
```

The family candidate is the larger marginal/paired requirement. Shared-cohort P1/P3 use the larger scheduled value. A requirement above 148 is reported as over-cap and blocks readiness. Intrablock correlation, position, predecessor, process age, JIT, GC, working set, private memory, and managed-memory diagnostics remain visible. No result is a formal authorization.

## 11. Readiness and stop condition

Readiness passes only when all required pre-pilot gates pass, the single pilot completes exactly, structural mismatches are zero, all telemetry is valid, hard memory rules pass, hashes/checkpoints are transitive, and candidate sample sizes are generated solely from eligible v2 measured data.

On success, produce only:

- the v2 pilot analysis and immutable output manifest;
- candidate `n_formal` values and cap verdicts;
- a readiness checkpoint with status `PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED`;
- updated project-plan/checkpoint documentation.

Then stop and wait for separate formal authorization. Do not create a process-reuse formal config, formal output root, formal execution receipt, or formal timing sample in this authorization.
