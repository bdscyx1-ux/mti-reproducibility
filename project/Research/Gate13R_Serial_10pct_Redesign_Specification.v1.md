# Gate 13R strict-serial 10% redesign specification v1

## 1. Status and authority

This specification implements the user's 2026-10-08 directive, `不再并行，直接串行实验`, as a nonexecuting Gate 13R redesign. It supersedes four-lane, three-lane, and proposed two-lane execution for all future Gate 13R work. It does not authorize a formal campaign, create a formal output root, create a formal execution receipt, or create formal timing observations.

The frozen upstream evidence remains:

- Gate 10R attempt 4 and execution design `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`;
- Gate 11R attempt 2 and `Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json`;
- Gate 12R successful pilot `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/`;
- the Gate 11R Playable bundle with 53 scenario scenes, 74 campaign profiles, 212 algorithm presets, and one launcher.

The `5pct` token in upstream path/design names is retained as immutable provenance. It does not set the new formal precision target.

## 2. Process topology

The active formal topology is strictly serial:

1. At most one Unity Editor process may exist at any time.
2. Each complete Williams block starts one fresh Unity Editor process.
3. A process executes exactly one complete block, containing each eligible algorithm exactly once in the frozen Williams order.
4. The process must exit and pass log, lock, checkpoint, and output validation before the next process may start.
5. Cross-block and cross-campaign process reuse are forbidden.
6. Parallel lanes, simultaneous license admission, topology fallback, and mixing serial and parallel results are forbidden.
7. Every sample performs the already-frozen full reset of planner, grid, scenario state, runner, logger, metrics collector, and mutable static state.

The statistical unit remains the complete Williams block; samples within a block are paired and are not treated as independent process replicates.

## 3. Matrix and precision

The complete Gate 11R matrix remains 74 campaigns:

| Cohort | Campaigns | Algorithms per block | `sigmaUpper` from Gate 12R v4 | 10% raw requirement | Williams-cycle `n_formal` |
|---|---:|---:|---:|---:|---:|
| shared goal | 32 | 4 | 0.5817569456605945 | 144 | 144 |
| per-agent heterogeneous goal | 21 | 2 | 0.6894148388178792 | 201 | 204 |
| grouped-field heterogeneous goal | 21 | 2 | 0.49699794016508997 | 105 | 108 |

The prospective formula is

`ceil((1.96 * sigmaUpper / ln(1 + 0.10))^2)`,

followed by a minimum of 32 blocks and rounding upward to a multiple of four. There is no hard cap and no significance, trend, budget, or precision early stopping.

The resulting formal scale is:

- 11,160 fresh Unity Editor block processes;
- 31,536 algorithm samples;
- 4,608 / 4,284 / 2,268 processes for shared / per-agent / grouped-field cohorts respectively;
- 18,432 / 8,568 / 4,536 samples respectively.

## 4. Reuse of Gate 12R v4 as the serial pilot

Gate 12R v4 already executed the exact selected runtime topology: one process at a time, one fresh Unity Editor per complete Williams block, with the same reset, memory, telemetry, Williams, scenario, and output semantics. A read-only audit must prove all of the following before this evidence can support readiness:

- 8 excluded warm-up blocks, 36 excluded cold structural controls, 384 measured blocks, and 1 telemetry process;
- 428 block/control wrapper summaries pass with exit code 0;
- no two wrapper process intervals overlap;
- all 428 Unity logs contain `Serial number assigned to:`;
- no log contains `No valid Unity Editor license found` or `License is not active (com.unity.editor.headless)`;
- all manifest-bound wrapper and log hashes match;
- the telemetry process has positive working-set/private-memory values and matching PSAPI/CIM PID plus process-start identity;
- 384 measured blocks and 1,152 measured samples remain complete, nonformal, and excluded from formal analysis;
- retry and resume counts remain zero.

Because this is same-topology evidence, rerunning an equivalent serial pilot would add licensing and disk risk without changing the estimator. The failed four-lane and three-lane attempts are not used for variance, candidate `n_formal`, readiness timing, or formal inference.

## 5. Licensing and process identity

Formal execution must validate licensing after each Unity process exits and before starting the next block:

- `Serial number assigned to:` is required;
- `No valid Unity Editor license found` is terminal;
- `License is not active (com.unity.editor.headless)` is terminal;
- `Access token is unavailable; failed to update` is diagnostic only when the same log contains a serial assignment, the process exits 0, and all block outputs pass;
- any terminal license result fails closed and prevents the next process from starting.

PID alone is not an identity because Windows may reuse it. Provenance and audit identity use PID plus OS process start time. Where a cold structural-control wrapper did not retain the OS start timestamp, its PID plus wrapper start timestamp is used only to prove uniqueness inside the excluded control set; it is not a formal process-identity schema.

## 6. Runtime and storage projection

Using the frozen Gate 12R v4 cohort block-wall distributions:

| Cohort | Processes | Projected p50 | Projected p95 | Raw bytes with 1.5× safety |
|---|---:|---:|---:|---:|
| shared | 4,608 | 121,014.5458176 s | 163,241.3638656 s | 36,846,855,936 |
| per-agent | 4,284 | 73,505.7664992 s | 99,782.0686296 s | 4,603,085,172 |
| grouped-field | 2,268 | 38,870.5752288 s | 39,031.7708340 s | 2,435,634,684 |

Total projected wall time is 64.830802096 hours at p50 and 83.904223147 hours at p95. These are planning estimates, not a completion guarantee. Strict serial execution is incompatible with the previous 36-hour hard gate. No replacement hard limit is invented here; the user must explicitly accept the projected duration or set a new limit when authorizing formal execution. A 96-hour uninterrupted maintenance window is the recommended operating allowance.

Projected raw output with safety is 43,885,575,792 bytes. The launch gate adds a 40 GiB reserve, requiring at least 86,835,248,752 original free bytes on the resolved formal-output volume. A current free-space observation is never launch authorization; the byte count must be queried again immediately before formal-root creation.

## 7. Failure and checkpoint policy

- No automatic retry, resume, fill, or merge.
- A failed sample invalidates the current block and stops the campaign before another Unity process starts.
- Partial blocks and partial campaigns are excluded until a separately authorized new attempt is designed.
- The root checkpoint is atomically written before and after every block.
- Config, schedule, receipt, block plan, summary, manifest, Unity log, and checkpoint are hash-bound.
- Formal output must remain separate from all Gate 12R, four-lane, and three-lane roots.

## 8. Playable scenes

Gate 13R timing remains headless and must not load, render, or record Playable scenes. Every formal campaign retains its Gate 11R scene/profile/preset mapping so that Gate 15V-R can replay the corresponding experiment in the Unity Editor for OBS capture. Playable output is visualization-only and must display `VISUALIZATION REPLAY — NOT A TIMING RUN`.

## 9. Authorization boundary

This specification is ready only for validation-only checks. A later formal authorization must bind an exact versioned serial config, schedule manifest, provenance, output root, and execution receipt; accept the serial runtime projection; require fresh hash/environment/license/storage preflight; and preserve the no-retry/no-resume policy.
