# Planning Replication Protocol

Gate: 6 infrastructure, extended by Gates 7, 8, and 9

Entry point: `Research/Run-PlanningReplication.ps1`

This protocol repeats the fixed-start planning workload in independent Unity Editor processes, validates every child run before aggregation, and reports a distribution across completed repetitions. It is a planning microbenchmark protocol, not an agent-motion or arrival-time experiment.

## Scope and prerequisites

- Close the interactive Unity Editor for this project. The command refuses to run while a Unity process or `Temp/UnityLockfile` is present.
- Use a strict schema-v1 scenario file. The committed canonical fixtures are listed in `Research/Scenarios/catalog.json`.
- Use a unique group id and an empty output directory. Existing non-empty output is never merged or overwritten.
- The implemented and authorized algorithms are exactly `A*-R`, `D*L`, `C-FF`, and `IDFF`.
- Choose the repetition count before inspecting results. The command accepts 2–100 repetitions. The retained three-run fixture demonstrates the pipeline; three repetitions are not, by themselves, a generally adequate basis for a publication claim.

## Example

From the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningReplication.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -Repetitions 10 `
  -GroupId "astar-dynamic-corridors-001" `
  -OutputDirectory "H:\DDM_Final_Project\Research\Runs\astar-dynamic-corridors-001" `
  -Algorithm "A*-R"
```

If `-OutputDirectory` is omitted, the group is written under `Research/Runs/<GroupId>/`. A wrapper summary is written beside that directory as `<GroupId>.summary.json`.

For D* Lite, keep the algorithm in a separate comparison group:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningReplication.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -Repetitions 10 `
  -GroupId "dstar-lite-dynamic-corridors-001" `
  -OutputDirectory "H:\DDM_Final_Project\Research\Runs\dstar-lite-dynamic-corridors-001" `
  -Algorithm "D*L"
```

For the corrected full-recompute flow field, keep a third independent group and select `C-FF`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningReplication.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -Repetitions 10 `
  -GroupId "cff-dynamic-corridors-001" `
  -OutputDirectory "H:\DDM_Final_Project\Research\Runs\cff-dynamic-corridors-001" `
  -Algorithm "C-FF"
```

For the incremental dynamic flow field, keep a fourth independent group and select `IDFF`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Run-PlanningReplication.ps1" `
  -ScenarioPath "H:\DDM_Final_Project\Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json" `
  -Repetitions 10 `
  -GroupId "idff-dynamic-corridors-001" `
  -OutputDirectory "H:\DDM_Final_Project\Research\Runs\idff-dynamic-corridors-001" `
  -Algorithm "IDFF"
```

Never combine A*-R, D* Lite, C-FF, and IDFF child results in one aggregate. Algorithm identity is an enforced group invariant.

## Independence model

Each repetition invokes `Research/Run-PlanningWorkload.ps1`, which starts a new headless Unity Editor process. Child ids are deterministic within the group: `<GroupId>-r001`, `<GroupId>-r002`, and so on. Starting a fresh process reduces managed-heap, static-state, and planner-state carryover between samples. It does not isolate the experiment from operating-system scheduling, thermal state, antivirus activity, filesystem cache, or other host-level effects.

The aggregation itself runs in one additional Unity process. No original scene is opened or edited.

## Group invariants

Before aggregation, the launcher requires every child run to have:

- a completed manifest and workload result;
- a unique run id;
- the requested algorithm id;
- the exact same scenario source SHA-256 and semantic scenario fingerprint;
- the same Unity version;
- matching hashes for the canonical scenario, JSONL log, and workload result;
- fully flushed JSONL counts.

The runtime aggregator independently rejects incomplete or malformed workload results. It requires fixed scenario starts and checks the fixed-start workload shape:

```text
planOperationCount = agentCount × (dynamicPlanningPhaseCount + 1)
repairOperationCount = scheduledEventCount
finalGridVersion = scheduledEventCount
```

Plan-status counts must sum to the plan count. Reported success and budget-overrun rates must equal their underlying counts. Runs in one aggregate must also share scenario/algorithm identity, structural counts, and deterministic outcome categories. Search-work counts may be compared; disagreement is reported explicitly rather than silently averaged as deterministic work.

## Output layout

```text
<group>/
  aggregation-request.json
  aggregate.json
  aggregation.Unity.log
  replication-manifest.json
  runs/
    r001/
      scenario.canonical.json
      operations.jsonl
      workload-result.json
      manifest.json
    r001.Unity.log
    r001.summary.json
    ...
<group>.summary.json
```

`replication-manifest.json` records group identity, input hashes, child ids and hashes, Unity identity, aggregate/request/log hashes, and timestamps. `aggregation-request.json` contains the absolute child-result paths used for that execution; if the evidence directory is moved, those paths document the original run but should not be treated as relocatable commands.

Partial output from a failed group is deliberately preserved for diagnosis. Because the launcher will not overwrite it, retry with a new group id/output directory after correcting the cause.

## Statistical definitions

For each supported metric, `aggregate.json` reports:

- sample count, minimum, and maximum;
- arithmetic mean, computed with Welford's numerically stable online update;
- median;
- nearest-rank p95 at sorted index `ceil(0.95 × n) - 1`;
- sample standard deviation with denominator `n - 1`;
- standard error `s / sqrt(n)`;
- two-sided 95% Student-t confidence interval for the mean: `mean ± t(0.975, n-1) × SE`.

Exact two-sided 95% t critical values are embedded for 1–30 degrees of freedom. Above 30 degrees of freedom the implementation uses a Cornish–Fisher expansion around the normal critical value. A one-sample summary is defined internally with zero dispersion and a degenerate interval, but a replication group requires at least two samples.

The interval is an unbounded mean interval. For bounded rates or non-negative measurements it can mathematically extend below zero or above one; the implementation does not clip it. The interval also assumes the repetitions are meaningfully independent and similarly distributed. It is not a guarantee of algorithmic superiority and does not correct for multiple comparisons.

Aggregated metrics are:

- planner initialization milliseconds;
- within-run plan-operation p95 milliseconds;
- within-run dynamic-phase p95 milliseconds;
- total planner elapsed milliseconds;
- managed allocation bytes;
- plan success rate;
- operation budget-overrun rate.

The timing aggregate is therefore a distribution of per-run summaries. For example, `planP95Milliseconds.mean` is the mean of each run's p95, not a pooled p95 over every plan operation. Managed allocation is a diagnostic runtime measurement and can be sensitive to JIT, garbage-collector, and process-start behavior.

## Committed scenario fixtures

- `static_weighted_four_way_v1.scenario.json`: static, weighted, four-way planning with three agents.
- `dynamic_corridors_sparse_v1.scenario.json`: same-tick event grouping plus events separated by hundreds of thousands of simulation ticks.
- `eight_way_strict_corners_v1.scenario.json`: eight-way planning with diagonal corner cutting disabled.

`Run-Gate6ScenarioCatalogVerification.ps1` loads every fixture through Unity's strict boundary, requires byte-for-byte canonical serialization, checks unique source/fingerprint identity, and executes a successful A*-R workload on each fixture.

Gate 7 independently verifies D* Lite on generated oracle cases and retains both a single-run and a three-process fixture on `dynamic_corridors_sparse_v1.scenario.json`. Gate 8 independently verifies C-FF against an O(V²) reverse multi-source Dijkstra oracle and retains matching single-run and three-process fixtures on the same scenario. Gate 9 independently verifies IDFF after every event against a fresh C-FF full rebuild and retains matching single-run and three-process fixtures on the same scenario. The catalog remains an A*-R-authored structural catalog; it is not a claim that every authorized algorithm has been benchmarked on every catalog scenario.

## Verification

Run all Gate 6 verifiers with the interactive Unity Editor closed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate6ReplicationStatisticsVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate6ScenarioCatalogVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate6ReplicationPipelineVerification.ps1"
```

The pipeline verifier recomputes the entire retained fixture's hashes, parses all child JSONL records, checks sequence and identities, validates aggregate statistics and deterministic work counts, scans Unity logs, and confirms that reusing the non-empty output directory is refused without changing the manifest.

Run the Gate 7 D* Lite pipeline checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7DStarLiteVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7BatchPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7ReplicationPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate7FinalAudit.ps1"
```

Run the Gate 8 C-FF pipeline checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8CorrectedFlowFieldVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8BatchPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8ReplicationPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate8FinalAudit.ps1"
```

Run the Gate 9 IDFF pipeline checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9IncrementalFlowFieldVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9BatchPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9ReplicationPipelineVerification.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "H:\DDM_Final_Project\Research\Verification\Run-Gate9FinalAudit.ps1"
```

## Interpretation boundary

Every initial and post-event plan starts from the agent's scenario-declared start. These outputs do not measure movement, arrival time, collisions, local avoidance, crowd behavior, or frame rendering. Gates 7–9 add D* Lite, C-FF, and IDFF planning only. C-FF rebuild budgets are atomic soft deadlines: a complete scratch field is committed before a budget overrun is returned. IDFF initialization is also a soft deadline, whereas IDFF repair and plan budgets are hard and resumable; a pending repair blocks a complete snapshot or route query until consistency is restored. These differences must remain visible when interpreting budget-overrun rates and algorithm-native work counters. None of these Gates modifies an original scene or original script.

## Gate 10 fairness identity and campaign scheduling

Fairness-schema-1 results extend, rather than reinterpret, the legacy replication contract. A new homogeneous aggregate must share all of the following:

- fairness protocol id and SHA-256;
- algorithm specification id and SHA-256;
- algorithm implementation SHA-256;
- workload specification id and SHA-256;
- goal cohort and comparison cohort;
- distinct-goal, planner, persistent-state, and shared-field counts;
- planner-state model, processed-work unit, and native-metric semantics;
- complete dynamic-cost acknowledgement.

Any disagreement is an identity error, not statistical variation. Legacy fairness-schema-0 Gate 6–9 results remain accepted, and the current aggregator has reproduced all four retained historical aggregates byte-for-byte.

`Research/Run-FairPlanningCampaign.ps1` is the multi-algorithm dispatcher. It never creates a cross-algorithm statistical aggregate. Instead it launches one algorithm/sample per Unity process, validates every child, and records a balanced schedule plus per-algorithm provenance in `campaign-manifest.json`. A four-algorithm shared-goal comparison uses complete four-block Williams cycles, so each algorithm occupies each process position equally and every ordered adjacent predecessor pair appears equally often.

The Gate 10 retained 16-process fixture validates this pipeline only. Formal scenario selection belongs to Gate 11, pilot/noise and sample-size decisions belong to Gate 12, and formal campaign execution belongs to Gate 13.
