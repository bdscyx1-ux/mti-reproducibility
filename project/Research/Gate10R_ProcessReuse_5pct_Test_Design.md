# Gate 10R Process-Reuse Test Design

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `plan / validate / run`
- Origin Date: 2026-10-06
- Verification Status: `TEST-DESIGN-FROZEN-BEFORE-IMPLEMENTATION`
- Version Label: `gate10r_process_reuse_5pct_test_design_v1`

## 1. Fail-closed order

1. authorization-ledger and historical-preservation audit;
2. specification/test/config static audit;
3. additive implementation and provenance hash binding;
4. PowerShell parser/AST and non-Unity unit/negative tests;
5. Unity batch compilation;
6. one native-telemetry/CIM handshake probe;
7. one valid two-algorithm block;
8. two independent valid four-algorithm executions of the same plan;
9. one injected position-2 failure block;
10. four fresh cold-process references and structural exact-match;
11. retained Gate 1–9 regression;
12. final preservation, hash, root-boundary, and validation-only audit.

No later item runs after an earlier hard failure. No failed invocation is retried or resumed.

## 2. Static assertions

The audit requires a unique Gate 10R class, namespace-visible execute methods, design ID, CLI switches, checkpoint kind, module, wrapper, telemetry probe, cold reference wrapper, and versioned verification root. It verifies:

- no historical source/script bytes changed;
- no original gameplay script or scene changed;
- PSAPI `GetProcessMemoryInfo`, `PROCESS_MEMORY_COUNTERS_EX`, `WorkingSetSize`, and `PrivateUsage` are present;
- the workload lifetime method is `NoInlining`;
- authoritative telemetry does not use `Process.WorkingSet64` or `PrivateMemorySize64`;
- no mutable static sample/planner container exists;
- thresholds equal 128 MiB managed and 512 MiB native;
- every fixture is `formalCampaign = false`;
- scripts contain no Gate 11R/12R/13R root creation path except explicit absence checks.

## 3. Non-Unity unit and negative vectors

The module tests:

- atomic create-new JSON and checkpoint replacement;
- deterministic plan bytes from identical inputs;
- exact four- and two-algorithm Williams rows;
- position and predecessor balance;
- duplicate algorithm, wrong/missing position, wrong predecessor, wrong schedule hash, mixed scenario/cohort, unsafe ID/path, invalid hash, and invalid count rejection;
- missing result, stale child hash, mixed PID, incomplete block, later output after failure, non-positive native telemetry, missing cleanup capture, and timestamp reversal rejection;
- managed growth vectors: negative, exactly 128 MiB, 128 MiB + 1, high raw/valid cleanup, per-sample fail, block endpoint fail;
- native endpoint vectors: negative, exactly 512 MiB, and 512 MiB + 1 for both metrics;
- telemetry probe vectors: same PID/executable/time, valid interval, exact tolerance, one byte outside tolerance, non-positive value, wrong PID, and reversed timestamps;
- structural projection ignores only the enumerated runtime/telemetry fields and detects any structural mutation.
- wildcard structural exclusions are forbidden; every excluded field class must be named before execution.

## 4. Compilation

Run Unity 2022.3.30f1c1 batchmode with the project and a no-op Gate 10R compile entry. Require exit code 0, no `error CS`, no script-compilation failure, and no execute-method failure. Record Unity executable SHA-256, Gate 10R source/meta hashes, PID, timestamps, and log hash. Compilation creates no experiment root.

## 5. Telemetry probe

Use exactly one fresh Unity process. It must produce positive in-process native and external CIM working/private values, exact PID/executable identity, creation-time agreement ≤2 seconds, ordered timestamps, handshake ≤60 seconds, and both metric distances within the frozen tolerance. The independent PowerShell verifier must recalculate the verdict. All probe artifacts are verification-only.

## 6. Positive fixtures

The two-algorithm block and both four-algorithm blocks require:

- one distinct fresh Unity PID per block;
- all samples within a block share that PID/start time;
- exact Williams order/predecessors;
- every expected algorithm once, no duplicate;
- unique run IDs/create-new directories;
- valid before/raw/cleanup telemetry and GC ordering;
- reset, logger join, planner reset, disposal, and cleanup flags true;
- child hashes, block manifest, and final checkpoint valid;
- all frozen managed/native limits pass.

The two four-algorithm blocks reuse identical plan semantics but distinct output roots and processes. Corresponding structural projections must exact-match.

## 7. Negative fixture

A four-entry plan injects an invalid identity at position 2. Position 1 may finish. Required terminal state:

- non-zero Unity status;
- `block-failure.json` exists;
- checkpoint is `failed-no-auto-retry`;
- completed count is exactly 1;
- no position 3 or 4 directory;
- no block completion manifest;
- no retry/resume marker.

## 8. Cold structural controls

Run `A*-R`, `D*L`, `C-FF`, and `IDFF` in four fresh excluded cold processes against the same scenario/seed. Compare every eligible positive fixture sample to its matching reference with the frozen structural projection. Required mismatch count: zero. Timing and process telemetry are not compared.

## 9. Retained Gate 1–9 regression

Run the existing non-destructive retained verification commands applicable to the current project. The suite must cover scenario/grid determinism, A*-R, batch artifacts, repetition/catalog statistics, D* Lite, C-FF reverse oracle/full recompute, and IDFF full-cell/event comparison. It must not rewrite retained fixtures. Record every command, exit code, summary/log hash, and aggregate pass/fail count.

## 10. Final audit

The final audit recomputes:

- all Gate 10R source/config/spec/test/provenance hashes;
- fixture cardinalities, process identities, order, structural comparisons, memory limits, atomic checkpoints, and no-retry/no-resume facts;
- historical root counts/bytes/read-only status and frozen key hashes;
- absence of Gate 11R, Gate 12R, and Gate 13R roots;
- no Unity process/project lock;
- no formal campaign marker.

Gate close requires all assertions pass and writes a versioned manifest/checkpoint. Otherwise it writes a failure checkpoint and stops.
