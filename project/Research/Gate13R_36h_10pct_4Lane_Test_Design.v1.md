# Gate 13R 36-hour / 10% / four-lane test design v1

## Identity and boundary

- Test design ID: `gate13r-36h-10pct-four-lane-tests-v1`.
- Bound design: `gate13r-36h-10pct-four-isolated-editor-lanes-v1`.
- Formal execution is forbidden. The only measured execution allowed by this test design is one pilot marked `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`.

## Gate order

Tests execute in the order below. A failed hard gate prevents all later gates. A repair is allowed only before measured pilot start and must remain additive/versioned.

### T01 — protected-input preservation

Recompute all hashes in `Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json`; assert both reserved formal roots remain absent; assert the old 5% config and schedule are unchanged. Pass requires exact byte length and SHA-256 equality for every listed file.

### T02 — PowerShell and JSON static validation

Parse every new `.ps1` and `.psm1` with Windows PowerShell 5.1, perform binding-only smoke tests with explicit absolute paths, parse every new JSON document, reject rooted child-output paths and traversal, and assert that all new roots are version-isolated.

### T03 — deterministic schedule and balance unit tests

Generate the 12-campaign, 32-block schedule twice and require byte-identical output. Assert 384 measured blocks, 1,152 samples, 96 four-lane waves, 96 measured blocks per lane, eight blocks per campaign/lane, lane cohort totals 48/24/24, exact Williams rows, one algorithm occurrence per block, and balanced algorithm × position × lane counts. Unit-test the 10% uncapped sample-size formula, percentile, sigma-upper, efficiency-haircut, p95 projection, and `<= 27 h` readiness boundary.

### T04 — additive Unity command derivation

Mechanically derive the new Unity entry point from the frozen Gate 12R V3 command using an explicit replacement table. Assert that the old source hash remains `eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97`, that only approved identity/kind tokens differ, and that workload, reset, telemetry, memory, hashing, and failure logic are otherwise byte-equivalent.

### T05 — source-project Unity compile

With no Unity process and no source lockfile, run a batch compile against `H:/DDM_Final_Project`. Pass requires exit code zero, no compiler/error patterns, successful method discovery, post-exit quiescence, and no reserved formal root.

### T06 — four isolated project copies

Create `lane-01` through `lane-04` outside the source project. Each copy receives independent `Assets`, `Packages`, `ProjectSettings`, preseeded `Library`, required frozen Research scenario/specification inputs, and the versioned redesign inputs. Reject reparse points and hard-linked scientific files. Compare source/copy length and SHA-256 for every scientific input. Assert each lane can create and remove its own temporary lock fixture without affecting another lane.

### T07 — four-lane telemetry handshake

Launch exactly four fresh Unity Editor telemetry-probe processes concurrently, one per isolated project and affinity mask. An independent CIM query must cross-check each process's positive working-set/private-memory values, executable, PID, creation time, and capture order. Pass requires four independent results, distinct PIDs, distinct project roots, correct affinity masks, no lock residue, and no formal outputs.

### T08 — positive concurrent block smoke

Launch a four-lane wave of excluded verification blocks. Validate one fresh Unity process per lane/block, exact Williams order, complete sample/reset/memory evidence, independent PIDs, affinity, hashes, and no lock residue. Compare every sample's deterministic structural projection to its retained fresh cold-process reference.

### T09 — negative fail-closed smoke

With no other Unity process running, inject a failure at position two in one excluded verification block. Require non-zero exit, `failed-no-auto-retry`, exactly one completed sample, no later sample directory, an atomic failure record, and no automatic retry/resume. This fixture is never part of the measured pilot.

### T10 — independent-process repeatability and cold structural control

Run the same excluded block in two fresh Unity processes and require exact structural equality between them and the retained cold reference for every algorithm. Timing values are not required to be identical.

### T11 — retained regression

Run the retained 63-test analysis/algorithm regression harness and require 63/63. Recheck Gate 11R scenario/profile/preset/Playable coverage hashes and the Gate 12R reset, telemetry, memory, and canonical-identity invariants used by this redesign.

### T12 — validation-only pre-pilot audit

Without creating the pilot root, validate authority, spec/test/amendment/provenance hashes, pilot-plan cardinalities, schedule balance, lane copy identity, telemetry results, T01–T11 evidence, source quiescence, free storage/memory, power state, CPU load, formal-root absence, and pilot-root absence. Only a fully passing audit permits creation of the one pilot root and execution receipt.

### T13 — sole non-formal concurrent pilot

Create the pilot root exactly once; write an atomic execution receipt explicitly stating `NON-FORMAL`, `EXCLUDED-FROM-FORMAL-ANALYSIS`, `NO-AUTO-RETRY`, `NO-RESUME`, and `FORMAL-CAMPAIGN-NOT-AUTHORIZED`. Run eight excluded warm-up blocks followed by 96 measured waves/384 measured blocks. Stop before the next wave on any failed wrapper/block or isolation condition.

### T14 — post-pilot analysis and readiness

Require 384 complete measured block manifests and 1,152 complete sample manifests, exact cold structural equality, all balance constraints, no mixed PIDs within a block, no reused process across blocks, and no formal flags. Produce block-aware marginal/paired variance, correlation and order diagnostics, cohort p95 wrapper time, observed/conservative concurrency efficiency, storage projection, uncapped 10% candidates, and the preregistered p95 runtime projection.

Readiness passes only if every gate passes, projected storage plus reserve fits, and projected p95 is no greater than 27 hours. A successful readiness checkpoint states that separate user authorization is still required for Gate 13R formal execution. A failure checkpoint states that the design must be revised and may not be launched formally.

## Required terminal evidence

Whether the pilot succeeds or fails, preserve an execution receipt, current checkpoint, block/wave ledger, process ownership records, environment snapshots, hashes, partial-output manifest, Unity/wrapper logs, and formal-root absence evidence. No partial pilot contributes to a later pilot or formal analysis.
