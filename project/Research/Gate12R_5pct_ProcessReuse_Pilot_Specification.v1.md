# Gate 12R 5% Process-Reuse Pilot Specification v1

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: plan-run
- Origin Date: 2026-10-07 (Asia/Shanghai)
- Verification Status: FROZEN-BEFORE-IMPLEMENTATION
- Version Label: `gate12r_5pct_process_reuse_pilot_spec_v1`
- Specification ID: `gate12r-fresh-process-reuse-5pct-pilot-spec-v1`
- Execution Design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`

## 1. Scope and immutable upstream

Gate 12R consumes only Gate 10R attempt 4, Gate 11R attempt 2, the execution design above, and `Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json` SHA-256 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`. Historical cold/process-reuse roots, the old Gate 11 bundle, old Gate 12 archives, original game scripts/scenes, and the original project archive are protected evidence and are never inputs or writable targets.

The only pilot root for attempt 1 is `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1`. It is create-new, `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`, and may be created only after every pre-pilot hard gate passes. `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1` must remain absent. A pilot attempt that starts any measured block can never be resumed, completed, overwritten, or merged; a repair/retry requires a new versioned plan, receipt, verification root, and pilot root.

## 2. Independent unit and Williams contract

One fresh Unity Editor process owns exactly one complete Williams block. Within a block each eligible algorithm runs once, in the Gate 10R/Gate 11R frozen row. Four-algorithm shared blocks use the four-row cycle; two-algorithm heterogeneous blocks use forward/reverse rows. Every sample has a unique run ID and fresh scenario/grid/planner/runner/logger/metrics state. Full GC occurs outside timing before every sample and after the non-inlined sample method returns. Any sample failure atomically fails the block and prevents later positions.

Measured samples are correlated within process. The independent runtime and statistical cluster is the Williams block, never the algorithm sample. Partial blocks, warm-up, cold controls, telemetry, verification fixtures, visualization runs, and all historical roots are permanently excluded.

## 3. Frozen 12-campaign pilot subset

Shared anchors (one four-algorithm campaign each):

1. `core-r01-s1-shared--shared`
2. `core-r07-s2-shared--shared`
3. `grid-scale-g256-shared--shared`
4. `agent-scale-a512-shared--shared`
5. `dynamic-footprint-f225-shared--shared`
6. `reachability-c8-strict-shared--shared`

Heterogeneous anchors (per-agent and grouped-field campaigns for each scenario):

1. `core-r01-s1-hetero`
2. `core-r07-s2-hetero`
3. `goal-count-g32-hetero`

This yields 6 shared, 3 per-agent, and 3 grouped-field campaigns. Each measured campaign contains 32 complete blocks. Blocks execute in 32 waves; within a wave campaign order is a deterministic cyclic permutation with step 5 over the 12 frozen campaign ordinals. This interleaves campaign families while preserving each campaign's block ordinal and Williams row.

## 4. Warm-up, controls, and exact payload

The excluded warm-up is one complete Williams cycle per cohort: four shared blocks on `core-r01-s1-shared`, two per-agent blocks and two grouped-field blocks on `core-r01-s1-hetero`. It is 8 fresh Unity processes and 24 samples, followed by a 10-second quiet stabilization interval and a repeated environment check.

Fresh cold structural controls run every eligible algorithm once for every pilot campaign: 24 shared plus 6 per-agent plus 6 grouped-field controls, for 36 fresh Unity processes and 36 samples. Each measured result must exact-match its campaign/algorithm cold structural projection.

The frozen payload is:

| Role | Unity processes | Samples | Variance input |
|---|---:|---:|---|
| PSAPI/CIM telemetry probe | 1 | 0 | no |
| excluded warm-up | 8 | 24 | no |
| fresh cold structural controls | 36 | 36 | no |
| 12 campaigns × 32 measured blocks | 384 | 1,152 | yes |
| total | 429 | 1,212 | only 384/1,152 measured |

Pre-pilot Unity fixtures are additional and excluded.

## 5. Environment, power, thermal, and storage preflight

Every launch records CPU model, logical processors, RAM, Windows edition/build, Unity version/path/hash, user/machine, active power scheme, Win32 AC-line state, available physical memory, H: free bytes, CPU-load samples, thermal-query availability, Unity process inventory, project lock, and reserved formal-root absence.

Hard launch requirements are: Unity SHA-256 `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`; High performance scheme GUID `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`; AC line online; at least 4 GiB free physical memory; mean CPU load at most 50% over five one-second samples; at least 20 GiB free on H:; no other Unity process; no `Temp/UnityLockfile`; no Gate 13R formal root. AC is measured with `GetSystemPowerStatus`, so a desktop without `Win32_Battery` remains testable.

If ACPI thermal zones are unavailable, the exact unavailability is recorded and does not fail the gate; thermal control then consists of the frozen warm-up, quiet interval, balanced/interleaved order, and start/post-warm-up/end snapshots. Available sensor values must be finite and physically plausible (0–125 °C).

## 6. Telemetry and memory rules

One fresh probe must return strictly positive working-set and private-memory values from Unity's `GetProcessMemoryInfo/PROCESS_MEMORY_COUNTERS_EX` and an independent parent `Win32_Process` CIM query for the same PID. The external value must lie within, or no farther than max(64 MiB, 25% of the maximum observation) from, the native before/after interval. PID, executable, timestamp order, and creation time (2-second tolerance) must match.

Per sample and block, retained managed growth must not exceed 128 MiB; block working-set and private-memory growth must not exceed 512 MiB. Raw post-workload managed growth is diagnostic only. Thresholds cannot be relaxed after observing pilot data.

## 7. Statistical and precision contract

The primary endpoint for sizing is `dynamicHandlingMillisecondsPerScheduledEvent`, natural-log transformed, and must be finite and strictly positive. For every fixed campaign/algorithm cell, compute marginal log SD from 32 independent blocks. For each campaign compute paired log-difference SD for `D*L − A*-R` (shared and per-agent) and `IDFF − C-FF` (shared and grouped-field).

For sample SD `s` with `df = n - 1`, the preregistered one-sided 90% upper confidence bound is:

```text
sigma_upper = s * sqrt(df / chi_square_quantile(0.10, df))
h = ln(1.05)
raw_n = ceil((1.96 * sigma_upper / h)^2)
required_n = next_multiple_of_4(max(32, raw_n))
```

No hard cap exists. Each cohort candidate is the maximum requirement over all its marginal cells and paired contrasts. The shared candidate additionally harmonizes P1 and P3 by taking their larger requirement. `n_formal` always means independent block processes per formal campaign.

Report per-campaign consistency ICC, pairwise within-block correlation, position, predecessor, process-age/JIT proxy, GC and native/managed-memory diagnostics. JIT is not directly instrumented; `process-age-position-first-use-v1` is the preregistered proxy and must not be mislabeled as a direct JIT counter.

## 8. Resource projection

Formal projections use 32 shared, 21 per-agent and 21 grouped-field campaigns. For each cohort report p50/p95 block wall time and raw bytes, then project block processes, algorithm samples, wall hours, and raw bytes using the uncapped candidate. Storage is host-feasible only when currently free bytes exceed `1.5 × projected p95 raw bytes + 20 GiB reserve`; wall-time is reported without an invented hard cap. An infeasible projection does not retroactively alter pilot data; it requires a future user-approved Gate 13R amendment.

## 9. Playable mapping

All 12 pilot campaigns must resolve exactly to the Gate 11R campaign profile, canonical scenario scene, and every eligible algorithm preset. All 53 scenarios, 74 profiles and 212 presets remain covered. Playable assets are visualization-only; they are never loaded by the timing runner and never write timing evidence.

## 10. Terminal policy

Success requires complete cardinality, zero structural mismatches, all memory/reset/hash/provenance gates, valid block-aware analysis, candidate `n_formal`, resource projection, output manifest, and readiness checkpoint. Success stops at `GATE12R-PASSED-WAITING-FOR-GATE13R-AUTHORIZATION`. Failure writes an atomic receipt, partial-output manifest and checkpoint, remains excluded, and may only be followed by a fresh versioned attempt under the user's standing Gate 12R repair/retry authorization. Gate 13R is not authorized.
