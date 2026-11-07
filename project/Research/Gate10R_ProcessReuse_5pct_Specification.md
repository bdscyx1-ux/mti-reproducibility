# Gate 10R Process-Reuse Fairness and Execution Specification

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `plan / run / validate`
- Origin Date: 2026-10-06
- Verification Status: `SPECIFICATION-FROZEN-BEFORE-IMPLEMENTATION`
- Version Label: `gate10r_process_reuse_5pct_specification_v1`
- Active lineage: `gate10r-onward-one-process-per-williams-block-5pct-playable-v1`
- Execution design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`

## 1. Scope and non-scope

Gate 10R rebuilds and verifies the research-only execution kernel that will be used by Gate 12R and, only after later authorization, Gate 13R. It does not generate Gate 11R scenarios or scenes, run the Gate 12R pilot, create a Gate 13R formal root, or produce formal timing evidence.

Historical Gate 10–13 code and output are design evidence only. The new command, PowerShell module, wrappers, configuration, verification fixtures, manifests, and checkpoints use new names and roots. No original gameplay script or original scene may be modified.

## 2. Ownership and independent unit

A complete Williams block is owned by exactly one fresh Unity Editor process.

- A four-algorithm shared-goal block contains exactly one sample each for `A*-R`, `D*L`, `C-FF`, and `IDFF`, in one frozen Williams row.
- A two-algorithm heterogeneous-goal block contains exactly one sample each for its authorized pair, in one frozen Williams row.
- An algorithm occurs at most once in a block process.
- A process executes exactly one block and may not cross scenario, cohort, campaign, or block.
- Samples in one process are paired and potentially correlated; the block process is the independent cluster.
- A campaign-long Unity process and one-process-per-sample execution are outside the active design.

The outer orchestrator owns process creation and termination. The Unity command owns only the entries in its one hash-bound block plan.

## 3. Williams order and predecessor semantics

The four-algorithm family uses the frozen four-row Williams cycle already defined by the fairness contracts, with exact algorithm and predecessor balance over each complete cycle. The two-algorithm family alternates the two authorized orders. Position is one-based. Position 1 predecessor is `NONE`; later predecessors must equal the immediately preceding algorithm. Plans with duplicate algorithms, missing/duplicate positions, wrong predecessors, mixed cohorts/scenarios, or a row that differs from the frozen schedule are rejected before the first sample.

## 4. Complete sample reset

Every sample creates fresh instances of:

- loaded scenario definition and resolved scenario;
- research grid;
- planner;
- deterministic workload runner and experiment runner;
- logger, writer queue, writer thread, and output paths;
- metrics collector and phase collections;
- manifest/summary models;
- every mutable research-owned sample state.

Before the next position, workload/canonical/JSONL output is finalized, writer flush/join and disposal complete, planner reset completes, sample-local heavy references leave a non-inlined method, and a forced post-return collection boundary completes. Mutable static planner/sample state is prohibited. Unity/global immutable caches may exist only if they are not mutated by a sample and are recorded as process-level environment, not sample state.

## 5. Telemetry and memory semantics

Native process telemetry is authoritative only when collected in Unity by Windows PSAPI `GetProcessMemoryInfo` with `PROCESS_MEMORY_COUNTERS_EX`:

- working set: `WorkingSetSize`;
- private memory: `PrivateUsage`.

All native values must be positive. A dedicated probe must cross-check the same PID with CIM `Win32_Process.WorkingSetSize` and `PrivatePageCount`, agree on executable identity and creation time within two seconds, satisfy ready < external-query < native-after ordering, finish within 60 seconds, and remain within `max(64 MiB, 25% of the largest observed value)` of the native interval.

Managed memory is sampled at `beforeSample`, `rawAfterWorkload`, and `afterCleanup`. The pass/fail endpoint is post-return, post-cleanup, post-full-GC `afterCleanup`; raw live-workload growth is diagnostic only.

Frozen limits:

- per-sample retained managed growth ≤ 134,217,728 bytes;
- complete-block retained managed growth ≤ 134,217,728 bytes;
- block working-set endpoint growth ≤ 536,870,912 bytes;
- block private-memory endpoint growth ≤ 536,870,912 bytes.

Negative growth is valid. Limits may not be relaxed after observing fixtures or pilot data.

## 6. Per-sample evidence

Each sample has a unique safe run ID and create-new output directory. It records:

- design/lineage/config IDs and block-plan SHA-256;
- campaign, scenario, cohort, block, position, predecessor, and algorithm;
- Unity PID, process start time, executable identity, and process age;
- scenario source and canonical hashes;
- workload result, JSONL, manifest, and summary hashes;
- three telemetry captures, GC deltas, reset/cleanup flags, logger completion, and timing/allocation metrics;
- `formalCampaign = false`.

A complete block manifest transitively binds the plan and all sample summaries/results, proves one PID, exact order, unique algorithms, complete cardinality, and the four endpoint-growth values.

## 7. Structural exact-match projection

For the same scenario, algorithm, seed, fairness contract, and dynamic-event semantics, every process-reuse sample must exact-match a fresh cold-process reference on the following named projection:

- algorithm/fairness/scenario/canonical identities;
- completion and path-status fields;
- grid dimensions/version and dynamic phase count;
- planning workload counters, expanded/repaired counts, path/cost/status fields;
- per-phase event identity and structural fields;
- deterministic output cardinalities.

Only these fields are excluded:

- run ID and output paths;
- timestamps and durations;
- process ID/start time/age;
- working-set/private/managed/GC telemetry;
- allocation byte counters;
- file hashes whose bytes contain an allowed excluded field.

No wildcard exclusion is allowed. The comparison tool must materialize and hash both canonical projections.

## 8. Fail-closed and atomicity

Before the first sample and before/after every position, the command atomically writes a block checkpoint. Any plan, identity, sample, reset, logger, telemetry, structural, hash, or output failure:

1. atomically writes `block-failure.json`;
2. atomically transitions the checkpoint to `failed-no-auto-retry`;
3. preserves completed samples and partial evidence;
4. launches no later position;
5. creates no completion manifest;
6. returns a non-zero Unity exit status;
7. performs no retry or resume.

A create-new root is never overwritten. Partial/negative fixtures are excluded from analysis.

## 9. Budget and metric semantics

Gate 10R verifies execution correctness, not a timing campaign. Fixture timing is environment-sensitive diagnostic evidence. Budget exhaustion and `NoPath` remain observable outcome classes and are never silently discarded. The primary Gate 12R endpoint remains the frozen workload timing metric defined in Gate 10 fairness contracts; visualization, scene rendering, Editor UI, and OBS are never loaded by this headless command.

## 10. Provenance and protected roots

The new provenance binds specification, test design, config, implementation sources, scripts, Unity executable/version, historical planning baseline, and the authorization receipt. It rejects the old process-reuse design IDs as active outputs.

Protected roots are read-only evidence. The following must remain absent through Gate 10R:

- `Research/FormalScenarios/Gate11R_5pct/v1`;
- `Research/PlayableExperiments/Gate11R_5pct/v1`;
- `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1`;
- `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1`.

## 11. Gate close

Gate 10R closes only after the frozen test design passes in order: static/AST, non-Unity unit and negative vectors, Unity compilation, native/CIM probe, two-algorithm positive block, two independent four-algorithm blocks, injected mid-block fail-closed block, fresh cold structural controls, exact-match and repeatability checks, retained Gate 1–9 regression, transitive hashes, preservation re-audit, and validation-only final audit. A hard failure stops this authorization without retry or resume.

