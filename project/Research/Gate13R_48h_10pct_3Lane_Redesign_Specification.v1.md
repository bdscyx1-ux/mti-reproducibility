# Gate 13R 48-hour / 10% / three-lane stability-first redesign specification v1

## Authority and stopping point

- Specification ID: `gate13r-48h-10pct-three-lane-stability-first-spec-v1`.
- Execution design ID: `gate13r-48h-10pct-three-isolated-editor-lanes-serial-license-admission-v1`.
- The user's later steering replaces the authorized four-lane v17 design before any v17 artifact, clone, stress run or pilot was created.
- This design authorizes versioned implementation, nonexecuting verification, licensing stress qualification, and exactly one fresh `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS` pilot.
- It does not authorize a Gate 13R formal campaign, formal output root, formal execution receipt, Gate 14 analysis, or Gate 15-V execution.

## Frozen scientific semantics

The Gate 11R retained matrix remains byte-identical: 74 campaigns comprising 32 shared-goal, 21 per-agent heterogeneous-goal, and 21 grouped-field heterogeneous-goal campaigns. Deterministic scenarios and seeds, canonical identities, exclusion rules, eligible algorithms, Williams rows, Playable scenes, campaign profiles, presets, workload endpoint, telemetry, reset boundaries, and structural comparison rules remain unchanged.

The primary endpoint remains `dynamicHandlingMillisecondsPerScheduledEvent` on the natural-log scale. Every campaign targets a two-sided 95% confidence interval with 10% relative half-width. Candidate sample sizes use `z = 1.96`, a one-sided 90% upper confidence bound on sigma, a minimum of 32 independent Williams blocks, upward rounding to a multiple of four, and no hard cap:

`n_raw = ceil((1.96 * sigma_upper / log(1.10))^2)`

`n_formal = max(32, round_up_to_multiple_of_4(n_raw))`

A Williams block remains the independent process unit. Every block starts exactly one fresh Unity Editor process; a shared-goal block contains four algorithm samples and a heterogeneous-goal block contains two. Every mutable planner, grid, scenario, runner, logger, metrics collector, and static-state boundary is reset per sample. A process executes one block and exits. There is no sample-process reuse and no fifth long-lived Unity process.

## Three isolated lanes

The active clone root is `H:/DDM_Final_Project_Gate13R48H/v1` with exactly three byte-audited project copies:

- lane 1: `lane-01`, affinity `0x000000FF`;
- lane 2: `lane-02`, affinity `0x0000FF00`;
- lane 3: `lane-03`, affinity `0x00FF0000`.

The remaining logical processors are left available to Windows, the orchestrator, the licensing client, storage, and monitoring. Each lane has separate `Assets`, `Packages`, `ProjectSettings`, `Library`, `Temp`, `Logs`, and Unity lock namespaces. Scientific source files are ordinary copies, never junctions, symlinks, or hard links.

No unrelated Unity process may exist at a wave boundary. The orchestrator owns only processes it starts. It must not terminate unrelated Unity, PowerShell, Codex, licensing-client, or user processes.

## Serial license admission and synchronized workload barrier

Each three-lane wave uses a preregistered rotating admission order. For wave `w`, the first lane is `1 + ((w - 1) mod 3)`, followed cyclically by the other two lanes. This balances first, middle, and last admission positions exactly over every complete three-wave cycle.

For each lane in admission order:

1. start a fresh hidden Unity Editor process;
2. require the Unity log to contain `Serial number assigned to`;
3. fail immediately on the discriminating terminal patterns `No valid Unity Editor license found` or inactive headless entitlement; record access-token update warnings diagnostically, because the preserved v16 corpus proves that this warning can precede a successful license update and serial assignment;
4. write a create-new, hashable license-admission evidence record;
5. only then start the next lane.

After all three processes have license evidence, each process must enter the additive research batch command and write a create-new method-ready record. Only after all three method-ready records exist does the orchestrator atomically write the wave release record. All three processes then begin the planning workload. Sample timing begins after barrier release. End-to-end wall-clock includes admission, Editor startup, ready waiting, barrier release, workload, exit, quiescence, checkpointing, and finalization.

Missing serial evidence, a licensing-client channel loss, a process exit before readiness, a missing/malformed barrier release, timeout, residual lock, or any block/sample failure fails the entire wave closed. There is no lane restart, automatic retry, resume, fill-in, or partial merge.

## Pilot and schedule

The representative pilot subset remains the same 12 Gate 11R campaigns and contains 32 measured blocks per campaign: 384 fresh Unity processes and 1,152 algorithm samples. The schedule contains 128 complete three-lane waves and exactly 128 measured blocks per lane. Cohort totals per lane are 64 shared-goal, 32 per-agent, and 32 grouped-field blocks.

Campaign order rotates by five between block ordinals. Lane allocation is deterministic and distributes each campaign's 32 blocks as 10/11/11 across lanes, rotating the lane receiving 10 so that totals are exactly balanced across all 12 campaigns. Per campaign, algorithm-position, Williams-row, predecessor, lane, and admission-position imbalance may not exceed one; aggregate cohort and lane totals must be exact.

Before measured work, run 12 excluded warm-up blocks, four per lane, using complete Williams rows. The sole measured pilot root is `Research/PilotRuns/Gate13R_48h_10pct_3Lane/v1`. Verification is separate at `Research/Verification/Gate13R_48h_10pct_3Lane/v1`. The reserved formal root `Research/FormalRuns/Gate13R_48h_10pct_3Lane/v1` must remain absent.

## Licensing qualification

Before the pilot, run 172 consecutive nonmeasured three-lane licensing stress waves: 516 fresh Unity Editor processes. Every wave uses serial license admission, rotating admission order, method-ready synchronization, and an atomic barrier release, but executes no planning workload. Qualification requires:

- 516/516 serial/entitlement admissions;
- 516/516 method-ready records;
- 172/172 atomic releases and clean exits;
- zero automatic retries or resumes;
- zero terminal license errors;
- zero residual Unity processes or lockfiles.

Any failure writes a terminal receipt, checkpoint, log manifest, and hashes and stops before pilot creation. Stress outputs are nonmeasured verification evidence and are excluded from readiness variance and formal analysis.

## Telemetry and memory

PSAPI in-process and CIM external working-set/private-memory cross-checks remain required and positive. Managed memory is observed after the frozen full-collection boundary. The per-sample retained managed-memory limit remains 128 MiB and the block limit remains 128 MiB times the expected sample count. Native working-set and private-memory growth remain limited to 512 MiB per block. Reducing lanes does not relax any threshold.

## Runtime projection and readiness

The hard formal end-to-end wall-clock ceiling is 48 hours. Formal readiness requires projected p95 no greater than 42 hours, leaving six hours for preflight, tail variability, manifest hashing, checkpoint finalization, and orderly shutdown.

The analyzer separately reports license-admission time, method-ready time, barrier wait, post-release workload/exit time, wave wall time, concurrency efficiency, and storage. Projection uses the pilot's complete three-lane waves and includes serial admission overhead. No v16 observation may enter the candidate `n_formal`, variance, correlation, or readiness calculation.

Readiness can pass only if the complete pilot, all structural and telemetry gates, the 10% uncapped candidate calculation, storage feasibility, Playable mapping, and `projected_formal_p95_hours <= 42` all pass. Passing readiness still requires separate user authorization for formal execution.

## Preservation and failure policy

All v16 project evidence remains immutable and excluded. The deleted v16 execution clone is not evidence. New writes use versioned, create-new or atomic-replace semantics. Any hard-gate failure preserves an atomic receipt, checkpoint, manifest, logs, and hashes, then stops. Two-lane fallback is not automatic and requires a new design decision.
