# Gate 13-R2 v2 Telemetry/Readiness Test Design

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan / validate / run
- Origin Date: 2026-10-06
- Verification Status: TEST-DESIGN-FROZEN-BEFORE-V2-IMPLEMENTATION
- Version Label: `gate13_r2_v2_telemetry_readiness_test_design_v1`

## 1. Mandatory gate order

The order is fail-closed:

1. historical-root and frozen-input preservation audit;
2. v2 specification, test-design, amendment, pilot-plan, implementation, and provenance static audit;
3. create the fresh v2 pilot root once with preparation-only atomic metadata and no pilot data;
4. PowerShell unit and negative tests without Unity;
5. Unity compilation;
6. native telemetry/CIM cross-check probe;
7. valid two- and four-algorithm positive block fixtures;
8. injected invalid-entry negative block fixture;
9. two fresh-process executions of the same valid fixture and exact structural comparison;
10. retained 63-item regression suite;
11. validation-only audit, including forbidden formal-root absence and preparation-only pilot-root state;
12. transition the pilot checkpoint once and run one excluded warm-up;
13. run eight fresh cold structural controls;
14. run 36 measured process-reuse blocks exactly once;
15. analyze, seal, create candidate `n_formal`, write readiness checkpoint, and stop.

No later gate may start after an earlier failure. There is no automatic retry or resume. A pilot-stage failure permanently seals the v2 root as failed/partial. A deterministic implementation defect found before the pilot-start transition may be corrected additively and recompiled within this development authorization, but every failed verification invocation remains archived and the telemetry acceptance criteria cannot change. Preparation metadata is not a pilot attempt; once a warm-up or other pilot child is launched, the single authorized pilot attempt has begun.

## 2. Preservation tests

- `Research/FormalRuns/Gate13/v1` contains 891 files, 129,667,391 raw bytes, and 891 read-only files.
- Cold termination/exclusion/partial-manifest hashes match the pre-v2 preservation audit.
- `Research/PilotRuns/Gate13_ProcessReuse/v1` contains 838 files, 91,219,643 raw bytes, and 838 read-only files.
- Its ordered aggregate is `c467cd4ca179f6e919fe9cbfdeee3cd2b4a32c19931bcdc285ca705555a59b38`.
- V1 terminal status remains failed-no-auto-retry/no-resume and candidate output remains inadmissible.
- All frozen bindings listed in `Research/Verification/Gate13R2_v2_PreservationAudit.summary.json` hash-match.
- No Unity process or Unity lockfile exists at the verification boundary.
- At the first preservation audit, `Research/PilotRuns/Gate13_ProcessReuse/v2` and `Research/FormalRuns/Gate13_ProcessReuse/v1` are absent. The v2 root is subsequently created once at its specified preparation gate; the formal root must remain absent throughout this authorization.

## 3. Static specification and source tests

- V2 identifiers, paths, source files, plan, amendment, and provenance are unique and do not overwrite v1.
- Original scenes, original scripts, Gate 11 retained files, Gate 12 evidence, cold Gate 13 evidence, and v1 process-reuse evidence retain their frozen hashes.
- V2 source contains the Windows `GetProcessMemoryInfo` declaration, `PROCESS_MEMORY_COUNTERS_EX`, `WorkingSetSize`, and `PrivateUsage` mappings.
- Authoritative telemetry does not read `Process.WorkingSet64` or `Process.PrivateMemorySize64` as its source.
- The workload lifetime method is marked `NoInlining`; the caller performs post-return forced collection.
- Static audit rejects mutable static planner/sample state and returned heavy sample references.
- `formalCampaign` is false in every v2 fixture/pilot path.
- Pilot scripts contain no creation path for the formal root or formal execution receipt.
- The 128 MiB managed and 512 MiB native endpoint thresholds exactly match the specification and plan.

## 4. Non-Unity unit and negative tests

- Atomic JSON creation and replacement semantics are deterministic.
- Block-plan generation rejects duplicate algorithms, missing/duplicate positions, wrong predecessor, wrong Williams row or schedule hash, mixed scenario/cohort, unsafe IDs, escaping/absolute child paths, invalid source hash, or count outside `1..148`.
- Plan construction is byte-deterministic from frozen inputs.
- Two- and four-algorithm Williams rows have exact position and predecessor balance.
- Sample and block verification rejects zero/negative native telemetry, missing cleanup captures, timestamp reversal, PID mismatch, mixed PIDs, stale plan hash, child hash mismatch, incomplete block, or later sample after failure.
- Managed-memory test vectors cover negative growth, exactly 128 MiB, 128 MiB plus one byte, raw peak above threshold with post-cleanup pass, per-sample residual failure, and block-endpoint failure.
- Native growth vectors cover negative growth, exactly 512 MiB, and 512 MiB plus one byte for both working set and private memory.
- Probe-comparison vectors cover an external value inside the native interval, exactly at the tolerance, one byte beyond tolerance, non-positive values, timestamp reversal, PID mismatch, and creation-time mismatch.
- Candidate-size vectors cover zero variance, minimum 30, cycle rounding, exactly cap 148, over-cap, marginal/paired maximum, and P1/P3 harmonization.
- Selectors reject all cold/v1/fixture/warm-up/control/partial sources from candidate analysis.

## 5. Unity compilation gate

Run Unity in batch mode against the unchanged project and compile all scripts. Required verdict: process exit 0; no `error CS`, script compile error, or execute-method failure. Record Unity executable/product hash, v2 source/meta hashes, full log hash, start/end time, and process ID. Compilation cannot create either pilot or formal root.

## 6. Telemetry probe gate

Run exactly one dedicated probe invocation after successful compilation. It must demonstrate:

- a positive in-process PSAPI working set and private memory before/after the external query;
- a positive external CIM `WorkingSetSize` and `PrivatePageCount` for the same Unity PID;
- exact PID and executable identity;
- creation/start time agreement within two seconds;
- ready < external query < native after timestamps and total handshake <=60 seconds;
- per-metric interval-distance <= `max(64 MiB, 25% of largest observed value)`;
- atomic ready, external-query, result, stdout, stderr, and Unity log evidence;
- successful non-zero-field validation by an independent PowerShell verifier.

Any failure blocks all fixture and pilot execution. No fallback to v1 zero-valued telemetry or threshold relaxation is allowed.

## 7. Positive block fixtures

Run one valid two-algorithm and one valid four-algorithm fixture, each in a fresh Unity process. For each fixture:

- exact plan order and predecessor chain;
- one PID/start time for all samples in the block;
- every authorized algorithm exactly once;
- three valid telemetry captures per sample;
- positive working/private/managed values;
- post-return cleanup capture after raw capture;
- logger flush/join, runner disposal, planner reset, and fresh-state flags true;
- child result/canonical/log/manifest/summary hashes validate;
- terminal block manifest and checkpoint are complete and atomic;
- hard managed/native growth rules pass.

## 8. Negative fail-closed fixture

Use a create-new fixture whose first entry is valid, second entry contains a deliberately invalid algorithm/identity mutation, and later entries are otherwise valid. Required behavior:

- first sample may complete;
- invalid position fails;
- `block-failure.json` and terminal `failed-no-auto-retry` checkpoint are written;
- no later position directory, manifest, or completion marker exists;
- Unity exits non-zero;
- no retry or resume marker exists;
- partial fixture is excluded from all analysis selectors.

## 9. Independent-process repeatability

Execute the same valid four-algorithm fixture twice using separate create-new output directories and new Unity launches. Require different PIDs and process start times, identical planned order, zero structural mismatches at each corresponding position, valid hashes, and complete blocks. Runtime/telemetry values need not match. Both executions are verification-only and excluded from pilot analysis.

## 10. Retained regression and validation-only audit

The retained 63-item Gate 1–11 regression suite must pass without rewriting its fixtures. The validation-only audit then re-verifies:

- all frozen hashes and historical root aggregates;
- specification/test/amendment/plan/provenance/source/script bindings;
- telemetry probe and all fixture verdicts;
- no active Unity process or project lock;
- adequate disk/RAM, AC power, required power plan, and quiet CPU preflight;
- fresh v2 pilot root exists and contains only the hash-bound initialization receipt and `PREPARATION-ONLY-PILOT-NOT-STARTED` checkpoint;
- process-reuse formal root absent;
- no formal config, receipt, or execution authorization for v2;
- exact pilot cardinalities and one-shot authorization.

Only a completely passing audit may create the v2 pilot root.

## 11. Pilot cardinality and balance

| Role | Unity processes | Samples | Candidate-analysis inclusion |
|---|---:|---:|---|
| excluded process-reuse warm-up | 1 | 4 | excluded |
| fresh cold structural controls | 8 | 8 | excluded |
| shared measured blocks | 12 | 48 | included |
| per-agent measured blocks | 12 | 24 | included |
| grouped-field measured blocks | 12 | 24 | included |
| total | 45 | 108 | 36 blocks / 96 samples included |

Hard balance assertions:

- 36 distinct measured Unity process identities;
- one complete block per measured process;
- shared: three observations per algorithm × position and three per ordered predecessor pair;
- each two-algorithm cohort: six observations per algorithm × position and six per predecessor direction;
- no duplicate algorithm in a process;
- exact frozen Williams order and scenario/cohort identity.

## 12. Pilot telemetry, structure, and analysis gates

- All 96 measured samples have positive PSAPI working/private values at before, raw, and cleanup captures.
- Timestamps and process ages are ordered; GC deltas are non-negative.
- Structural mismatch count against fresh cold controls is zero.
- Every sample retained managed growth and every block retained managed growth are <=134,217,728 bytes.
- Every block working-set and private-memory endpoint growth is <=536,870,912 bytes.
- All completed sample/block hashes and checkpoint transitions validate transitively.
- No partial block enters analysis.
- Candidate calculations use only 36 measured v2 block processes / 96 samples.
- Marginal and paired log-scale requirements, intrablock correlations, position/predecessor diagnostics, age/JIT/GC/native/managed diagnostics, throughput, variance, raw bytes, and budget projections are reported.
- An over-cap requirement is reported without truncating the underlying required value and makes readiness fail.

## 13. Success and failure sealing

On any pilot failure, atomically write a failure record, terminal failed-no-auto-retry/no-resume checkpoint, and partial-output manifest; mark all output `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`; stop without analysis continuation, retry, or resume.

On success, atomically write the pilot manifest, immutable output manifest, candidate `n_formal`, and readiness checkpoint `PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED`; then make pilot evidence read-only and stop. In both outcomes, the formal root and formal receipt remain absent.
