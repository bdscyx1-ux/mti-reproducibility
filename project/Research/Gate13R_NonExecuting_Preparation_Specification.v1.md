# Gate 13R Non-Executing Preparation Specification v1

## Material Passport

- Origin skill: `academic-research-suite / experiment-agent`
- Origin mode: `run / validate`
- Stable preparation ID: `gate13r-nonexecuting-preparation-v1`
- Active execution design: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Formal design ID: `gate13r-one-fresh-unity-process-per-williams-block-5pct-uncapped-v1`
- Input boundary: Gate 10R attempt 4, Gate 11R attempt 2, Gate 12R attempt 4 and readiness checkpoint only
- Verification status: `SPECIFICATION-FROZEN / IMPLEMENTATION-NOT-YET-VERIFIED`
- Formal campaign authorization: `false`

## 1. Scope and authority

This specification implements only the user-authorized Gate 13R non-executing preparation. It authorizes additive research infrastructure, deterministic schedule/config generation, static and unit tests, Unity compilation, validation-only checks, fixtures, and negative fail-closed tests. It does not authorize creation of `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1`, a formal execution receipt, a formal timing block, a formal timing sample, retry, or resume.

The preparation may name the reserved formal root and define future executable paths, but no code path may create or populate that root unless a later, separately supplied formal-campaign authorization is validated and bound into a new versioned execution receipt.

## 2. Frozen upstream

The only active upstream is:

- Gate 10R attempt 4 and execution design `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`;
- Gate 11R attempt 2 bundle manifest SHA-256 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`;
- Gate 11R matrix SHA-256 `cc5f020003f3fad75bd82ebb2c26df521fd639ff0ee5376132853120dbc16aa3`;
- Gate 12R readiness checkpoint SHA-256 `93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d`;
- Gate 12R candidate `n_formal` SHA-256 `5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387`;
- Gate 12R budget/storage projection SHA-256 `cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f`;
- Gate 12R managed-memory amendment SHA-256 `69a128f8c41c2e0fad1453daed0729f752bb58b77d300f736a758f5121815c20`.

All Gate 10R attempts 1–4, Gate 11R attempts/bundle, Gate 12R attempts 1–4/readiness/evidence, historical cold/process-reuse roots, old Gate 11 retained bundle, Gate 12 archives, original game scripts, original scenes, and original project archives remain byte-frozen. New Gate 13R work is additive.

## 3. Formal matrix and experimental unit

The matrix remains 53 canonical scenarios, 74 campaigns, and 212 eligible scenario–algorithm cells. The independent unit is one complete Williams block executed by one newly launched Unity Editor process. A process executes exactly one block, contains two or four algorithm samples in the frozen Williams order, and executes each eligible algorithm exactly once.

No Unity process may cross a block, campaign, scenario, or cohort boundary. Samples in the same block are paired and potentially correlated. Each sample starts from freshly created scenario definition/resolution, research grid, planner, runner, logger, metrics collector, output writer, manifest state, Unity objects, and research-owned mutable static state; cleanup is mandatory before the next position.

## 4. Precision and schedule cardinality

The precision target remains a two-sided 95% confidence interval with 5% relative half-width. The candidate sample size is uncapped. Gate 12R prospectively fixed the number of independent block processes per campaign:

| Cohort | Campaigns | Blocks per campaign | Block processes | Samples per block | Samples |
|---|---:|---:|---:|---:|---:|
| four-algorithm shared goal | 32 | 548 | 17,536 | 4 | 70,144 |
| per-agent heterogeneous goal | 21 | 768 | 16,128 | 2 | 32,256 |
| grouped-field heterogeneous goal | 21 | 400 | 8,400 | 2 | 16,800 |
| total | 74 | — | 42,064 | — | 119,200 |

Every candidate is a multiple of the four-row scheduling cycle. The formal schedule is materialized as one canonical JSONL record per block. Each record binds campaign/scenario/cohort identity, global and campaign block ordinals, Williams row, block ID, expected sample count, and ordered sample entries. Each sample entry binds position, algorithm, predecessor, run ID, and relative output directory. The schedule SHA-256 is part of the formal config and provenance.

## 5. Identity grammar

- Campaign order is exactly the Gate 11R matrix order.
- Block IDs are deterministic, safe, unique, and contain campaign ordinal plus within-campaign block ordinal.
- Run IDs are deterministic, safe, unique, and contain block ID, position, and algorithm slug.
- Output paths are relative to the reserved formal root and cannot escape it.
- Position is contiguous and one-based.
- Position 1 predecessor is `NONE`; every later predecessor is the immediately preceding algorithm in the same Williams row.
- Williams row is `((blockOrdinal - 1) mod rowCount)` and must match the frozen Gate 11R row byte-for-byte at the semantic level.

## 6. Memory, reset, and telemetry contract

The memory policy remains `gate12r-sample-128mib-block-128mib-per-sample-v1`:

- per-sample retained managed-memory growth ≤ 134,217,728 bytes;
- complete-block retained managed-memory growth ≤ 134,217,728 × expected sample count;
- two-sample block limit = 268,435,456 bytes;
- four-sample block limit = 536,870,912 bytes;
- complete-block working-set growth ≤ 536,870,912 bytes;
- complete-block private-memory growth ≤ 536,870,912 bytes.

PSAPI in-process telemetry and CIM cross-check semantics remain those validated in Gate 12R. The future formal command must record positive working-set/private-memory observations, managed memory, process creation time/age, GC counters, reset completion, per-sample and block hard-rule verdicts, and a single process ID shared by all samples in one block.

## 7. Fail-closed and atomicity

Before launching a formal block, the future orchestrator must validate the formal authorization receipt, config/amendment/provenance/schedule hashes, exact reserved-root identity, raw-byte storage gate, environment, Unity absence, and project-lock absence. Only after every preflight passes may it create the formal root with create-new semantics.

Each block writes an atomic checkpoint before position 1 and after every position. Any error stops the current block, prevents later positions, records the partial evidence manifest and a terminal `failed-no-auto-retry-no-resume` checkpoint, and terminates the campaign orchestrator. Automatic retry, automatic resume, completion of a partial block, reuse of a partial block identity, and merging across attempts are forbidden.

The preparation tests these semantics only with isolated verification fixtures. It cannot create a real formal execution receipt or reserved formal root.

## 8. Raw-byte storage preflight

The projected raw output with safety is 166,572,888,336 bytes. A 20 GiB reserve adds 21,474,836,480 bytes. The exact launch threshold is therefore 188,047,724,816 free bytes. The future launch preflight must query the volume containing the resolved formal root immediately before root creation and compare raw integer bytes using `availableFreeBytes >= minimumLaunchFreeBytes`.

Gate 12R's disk snapshot is planning evidence only. Validation-only tests may exercise synthetic values below, equal to, and above the threshold and may record a non-authorizing current snapshot, but cannot emit a launch receipt.

## 9. Execution receipt validator

A future formal execution receipt is valid only when it is versioned, explicitly states formal authorization, binds a later user authorization record, binds the exact config/amendment/provenance/schedule/checkpoint-schema/orchestrator/Unity-command hashes, resolves the exact reserved root, records a fresh storage/environment preflight, states no-auto-retry/no-resume, and has not been consumed. Any missing/mismatched field fails closed before formal-root creation.

This preparation provides the validator and positive/negative fixtures only. It does not create a formal execution receipt.

## 10. Playable mapping boundary

Every formal campaign retains the Gate 11R mapping to its canonical Playable scene, campaign profile, and algorithm presets. Timing remains headless and does not load Playable scenes, render HUD/arrows, or start OBS. Playable assets are visualization-only and cannot write timing outputs. Formal-linked replay remains a later, separately authorized visualization stage.

## 11. Runtime and readiness disclosure

The planned serial runtime is an estimate: p50 881,220.2621056 seconds and p95 1,141,436.3340784 seconds (317.07 hours / 13.21 days). Passing Gate 13R preparation means only that the frozen config, full schedule, validators, orchestration skeleton, compile surface, and fail-closed fixtures are internally consistent while the formal root remains absent. It does not authorize or imply completion of the formal campaign.

## 12. Terminal state

On success the terminal state is `GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED`. The only next action is to request a separate Gate 13R formal campaign authorization. No formal execution begins automatically.
