# Gate 13R 36-hour / 10% / four-lane redesign specification v1

## Status and authority

- Specification ID: `gate13r-36h-10pct-four-lane-redesign-spec-v1`.
- Execution design ID: `gate13r-36h-10pct-four-isolated-editor-lanes-v1`.
- This document implements the user's 2026-10-08 authorization for a versioned redesign, tests, four isolated Unity project copies, and exactly one non-formal concurrency pilot.
- It does **not** authorize a formal Gate 13R campaign, a formal execution receipt, a formal output root, or formal timing samples.
- The previously frozen 5% Gate 13R config, schedule, receipts, and preparation evidence remain immutable historical material and are not executable under this design.

## Scientific estimand and matrix

The complete Gate 11R matrix remains fixed at 74 campaigns: 32 shared-goal campaigns, 21 per-agent heterogeneous-goal campaigns, and 21 grouped-field heterogeneous-goal campaigns. Scenario bytes, deterministic seeds, canonical identities, exclusions, eligible algorithms, Playable scenes, campaign profiles, algorithm presets, and Williams rows remain those in the Gate 11R retained bundle with bundle SHA-256 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`.

The primary timing endpoint remains `dynamicHandlingMillisecondsPerScheduledEvent`, analysed on the natural-log scale. The target is a per-campaign relative 95% confidence-interval half-width of 10%. Candidate sample sizes use `z = 1.96`, a 90% one-sided upper confidence bound on sigma, a minimum of 32 independent blocks, and rounding upward to a multiple of four. There is no hard sample-size cap.

For every campaign/algorithm marginal cell and every preregistered within-block algorithm contrast:

`n_raw = ceil((1.96 * sigma_upper / log(1.10))^2)`

`n_formal = max(32, round_up_to_multiple_of_4(n_raw))`

Here `log(1.10) = 0.0953101798043249`; using the log half-width rather than the decimal `0.10` preserves the Gate 11/Gate 12 multiplicative-precision convention.

The cohort candidate is the maximum candidate across all pilot campaigns, marginal cells, and paired contrasts belonging to that cohort. The pilot may produce a candidate and readiness finding only; it cannot create formal data.

## Independent unit and process lifetime

1. A Williams block is the independent process unit.
2. Every block starts one fresh Unity Editor process.
3. A four-algorithm shared-goal block contains four samples in its frozen Williams order; a heterogeneous-goal block contains two samples.
4. Each eligible algorithm appears no more than once in a process.
5. A process exits after its one block. No Unity process may execute a second block.
6. Each sample recreates and disposes planner, grid, scenario state, runner, logger, metrics collector, and other mutable state; the existing Gate 12R reset and telemetry contract remains binding.
7. A sample failure fails the entire block closed and prevents later positions in that block. A failed measured pilot prevents every later wave; it is not retried, resumed, filled in, or merged.

## Four isolated Unity Editor lanes

The pilot uses four byte-audited project copies outside the source project:

- lane 1: `H:/DDM_Final_Project_Gate13R36H/v1/lane-01`, affinity mask `0x000000FF`;
- lane 2: `H:/DDM_Final_Project_Gate13R36H/v1/lane-02`, affinity mask `0x0000FF00`;
- lane 3: `H:/DDM_Final_Project_Gate13R36H/v1/lane-03`, affinity mask `0x00FF0000`;
- lane 4: `H:/DDM_Final_Project_Gate13R36H/v1/lane-04`, affinity mask `0xFF000000`.

Each lane has its own `Assets`, `Packages`, `ProjectSettings`, `Library`, `Temp`, and Unity lock namespace. Scientific source files are ordinary copied bytes, not junctions, symlinks, or hard links. `Library`, `Temp`, and `Logs` are operational caches excluded from scientific identity; the copied scientific inputs must match the source hashes. Unity processes run at normal priority. The orchestrator owns only the processes it starts and must never terminate an unrelated Unity, PowerShell, Codex, or user process.

Before a wave starts, no unrelated Unity process may exist and all four lane lockfiles must be absent. At most one owned Unity process may run in each lane and at most four owned Unity processes may run globally. The next wave cannot start until all four prior wrapper processes have terminated, all owned Unity processes have exited, and all four lane lockfiles are absent.

## Pilot design

The sole measured pilot is marked `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS` and is rooted at `Research/PilotRuns/Gate13R_36h_10pct_4Lane/v1`. Verification is rooted separately at `Research/Verification/Gate13R_36h_10pct_4Lane/v1`. The reserved future formal root `Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1` must remain absent.

The representative subset is frozen to these 12 campaigns:

1. `core-r01-s1-shared--shared`
2. `core-r07-s2-shared--shared`
3. `grid-scale-g256-shared--shared`
4. `agent-scale-a512-shared--shared`
5. `dynamic-footprint-f225-shared--shared`
6. `reachability-c8-strict-shared--shared`
7. `core-r01-s1-hetero--per-agent`
8. `core-r01-s1-hetero--grouped-field`
9. `core-r07-s2-hetero--per-agent`
10. `core-r07-s2-hetero--grouped-field`
11. `goal-count-g32-hetero--per-agent`
12. `goal-count-g32-hetero--grouped-field`

There are 32 measured blocks per campaign: 384 block processes and 1,152 algorithm samples. Eight excluded warm-up blocks are run first, two per lane. Measured work is grouped into 96 four-lane waves. Campaign order rotates by step five between block ordinals. Lane assignment is deterministic:

`lane = 1 + ((WilliamsRowIndex + WilliamsCycleIndex + CampaignOrdinalZeroBased) mod 4)`

where `WilliamsRowIndex = (block - 1) mod cohortSize` and `WilliamsCycleIndex = floor((block - 1) / cohortSize)`. This yields exactly 96 measured blocks per lane, eight blocks per lane per pilot campaign, balanced Williams rows within each lane, and lane totals of 48 shared-goal, 24 per-agent, and 24 grouped-field blocks.

## Preflight and telemetry

The preflight requires AC power, the frozen high-performance power scheme, at least 16 GiB available physical memory, at least 40 GiB free on both the source-output drive and clone drive (the same drive may satisfy both), mean CPU load no greater than 50% across five one-second samples, source hashes intact, both formal roots absent, all four lane roots valid, and no Unity processes or Unity lockfiles.

Every lane must independently pass the existing in-process PSAPI versus external CIM telemetry handshake. Working-set and private-memory observations must be positive and within the frozen absolute/relative tolerance. Managed memory remains sampled after a full collection boundary. The retained managed-memory limit remains 128 MiB per sample and scales by sample count for the block; native working-set and private-memory growth limits remain 512 MiB per block. Concurrent aggregate RSS/private-memory peaks are diagnostic and must fit available physical memory without paging-risk evidence.

## Structural and order controls

Every pilot sample must exact-match the retained fresh cold-process structural reference for the same campaign and algorithm after projection to deterministic structural fields. The pilot must verify:

- algorithm × position × lane balance;
- predecessor and Williams-row balance;
- process age, JIT, GC, RSS, private-memory, and managed-memory trends;
- sample reset and static-state leak boundaries;
- per-block, per-sample, config, provenance, and summary hashes;
- independent-process repeatability;
- atomic negative failure behavior; and
- strict separation from every cold-process, earlier process-reuse, and future formal table.

## Runtime projection and readiness

The external wrapper wall time, including Unity startup and exit, is the block wall-time measure. Let `B_c` be the cohort-specific p95 wrapper seconds, `N_c` the uncapped cohort candidate, and `C_c` the number of formal campaigns (32, 21, 21). Let measured pilot elapsed seconds span the first measured-wave launch through final measured-wave quiescence, and let:

`observed_efficiency = sum(measured_block_wrapper_seconds) / (4 * measured_pilot_elapsed_seconds)`

`conservative_efficiency = min(0.85, 0.90 * observed_efficiency)`

`formal_p95_hours = (sum(C_c * N_c * B_c) / (4 * conservative_efficiency) + 1800) / 3600`

The 1,800-second allowance covers future formal preflight, checkpoint finalization, and output-manifest finalization. The 10% haircut and 0.85 ceiling are preregistered before observing this pilot. No post-pilot efficiency inflation is allowed.

Readiness can pass only if all scientific, structural, environment, telemetry, isolation, storage, and preservation gates pass and `formal_p95_hours <= 27`. The 27-hour launch gate intentionally leaves nine hours inside the hard 36-hour end-to-end ceiling. Passing readiness still does not authorize formal execution.

## Failure and preservation policy

All writes use create-new or atomic-replace semantics within the new versioned roots. A verification defect may be fixed before the measured pilot begins, with versioned evidence. Once measured execution begins, any hard-gate failure creates an atomic failure receipt, checkpoint, partial-output manifest, and hashes, then stops without automatic retry or resume. The pilot root is never reinterpreted as formal data. Historical roots and frozen inputs remain byte-identical.
