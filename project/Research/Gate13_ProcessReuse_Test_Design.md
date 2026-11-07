# Gate 13-R2 Process-Reuse Test Design v1

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan / validate
- Origin Date: 2026-10-06
- Verification Status: TEST-DESIGN-FROZEN-BEFORE-IMPLEMENTATION
- Version Label: `gate13_process_reuse_test_design_v1`

## 1. Gate sequence

The test order is mandatory:

1. preservation and termination evidence audit;
2. specification/config static audit;
3. PowerShell/unit negative tests without Unity;
4. Unity compilation and process-reuse command verification;
5. legacy 63-item regression suite;
6. validation-only preflight proving the formal root is absent and execution unauthorized;
7. one excluded warm-up block;
8. fresh cold structural controls;
9. the frozen non-formal measured pilot;
10. pilot analysis, candidate `n_formal`, budget projection, final audit, and stop.

Failure at any stage stops the sequence with no automatic retry. A rerun requires explicit user authorization unless the failure occurs before any Unity/pilot output and is a deterministic implementation defect repaired within this authorized development turn; any created pilot root is never overwritten.

## 2. Preservation assertions

- The Gate 11 bundle contains exactly the retained files and has its frozen aggregate/hash.
- Gate 12 successful `v1` and both failure archives retain their pre-recorded byte counts/hashes.
- Gate 13 readiness amendment v1, cold config, attempt-1/attempt-2 receipts, logs, and checkpoints remain byte-identical to the termination snapshot, except that the cold formal root received only its orchestrator-written failure evidence before read-only freeze.
- The cold termination receipt, pre-termination snapshot, partial-output manifest, and exclusion marker cross-hash correctly.
- Every file under `Research/FormalRuns/Gate13/v1` is read-only.
- No cold attempt process remains.
- The cold root is rejected by every process-reuse analysis selector.

## 3. Static and config tests

- The process-reuse specification and test design exist and hash-match the amendment/config.
- Existing cold scripts/configs and original scenes are not edited.
- Static audit finds no mutable static planner fields.
- The new formal config deterministically reconstructs to byte-identical JSON.
- Formal config counts are 53 scenarios, 212 eligibility cells, 74 campaigns, 15,056 samples, and 5,864 block processes before pilot-driven sample-size revision.
- Each campaign's block count, algorithm count, sample count, schedule hash, scenario identity, and Williams rows equal the cold config.
- `eachBlockUsesIndependentUnityProcess = true`, `eachSampleUsesIndependentUnityProcess = false`, `oneBlockPerUnityProcess = true`, and `algorithmOccursAtMostOncePerProcess = true`.
- The reserved formal root is named but absent.
- Config, amendment, and checkpoint all state that formal execution is not authorized.

## 4. PowerShell unit/negative tests

- Williams rows for 2 and 4 algorithms retain exact position and ordered-predecessor balance.
- Block-plan generation is deterministic and path-safe.
- Duplicate algorithms, missing positions, wrong predecessor, wrong schedule hash, block count outside `1..148`, mixed scenario/cohort entries, unsafe run IDs, absolute/escaping output paths, and non-create-new roots are rejected.
- A block result with mixed process IDs is rejected.
- A partial block cannot be marked completed.
- Sample hashes, block-plan hash, source scenario hash, config hash, and implementation hash are validated.
- Sample-size formula vectors cover zero variance, minimum 30, cycle rounding, exactly cap 148, and over-cap failure.
- Marginal and paired requirements are both computed; the conservative maximum is used.
- Shared P1/P3 harmonization uses the larger value.
- Formal-root creation and formal execution receipt creation are absent from all pilot paths.

## 5. Unity command tests

- One two-algorithm fixture block and one four-algorithm fixture block compile and complete.
- All samples in a block report the same process ID.
- Different block invocations report different process IDs.
- Position order exactly matches the block plan.
- Planner, scenario/grid, runner, logger, and output directory are fresh for every sample.
- Logger counts match, writer threads terminate, and planner reset completes.
- Per-position atomic checkpoint transitions are correct.
- An injected invalid entry fails closed, writes failure/checkpoint evidence, and executes no later position.
- Every child workload result, atomic manifest, atomic sample summary/completion marker, and block manifest hash validates transitively.
- Structural equality comparator ignores only the enumerated runtime fields and rejects a one-field structural mutation.

## 6. Regression tests

The same 63 retained Gate 1–11 regression checks used by Gate 12/13 readiness must pass after the additive implementation. Frozen expected hashes must remain unchanged. No process-reuse test may regenerate or rewrite retained fixtures.

## 7. Pilot cardinality and process identity

Expected non-formal execution:

| Role | Unity processes | Samples | Analysis inclusion |
|---|---:|---:|---|
| excluded process-reuse warm-up | 1 | 4 | excluded |
| fresh cold structural controls | 8 | 8 | structural validation only |
| shared measured process-reuse | 12 | 48 | pilot noise/diagnostics |
| per-agent measured process-reuse | 12 | 24 | pilot noise/diagnostics |
| grouped measured process-reuse | 12 | 24 | pilot noise/diagnostics |
| total | 45 | 108 | never formal |

Hard assertions:

- measured block process IDs: 36 distinct;
- measured sample count: 96;
- every measured process contributes one complete block;
- each algorithm appears once per block;
- shared position counts: 3 per algorithm per position;
- shared ordered predecessor counts: 3 per ordered pair;
- each two-algorithm cohort position count: 6 per algorithm per position;
- each two-algorithm cohort ordered predecessor count: 6 per direction.

## 8. Structural oracle

For the three pilot campaign identities, run one fresh cold process per eligible algorithm. Compare all 96 measured process-reuse samples to the matching scenario/cohort/algorithm control using the exact structural field set in the specification. Required verdict: zero mismatches. Timing, allocation, timestamps, run IDs, process metadata, and file paths are excluded by name; no wildcard exclusion is allowed.

## 9. Runtime diagnostics

All telemetry fields must be present, finite where numeric, and internally ordered (`ageAfter >= ageBefore`, non-negative GC deltas, positive memory values). Report:

- mean/median/p95 planner endpoint by algorithm × position;
- paired log contrast by block for each preregistered family;
- predecessor-stratified means;
- Spearman/Pearson diagnostics for position and age;
- working-set/private/managed-memory deltas;
- GC deltas by generation;
- block wall-time and startup-amortization ratio.

Hard memory limits are +128 MiB managed and +512 MiB working set within one measured block. A breach blocks readiness. Smaller trends are advisory and remain in the report.

## 10. Candidate sample size and budget

Use only the 96 measured process-reuse samples. The warm-up, fresh cold controls, and terminated cold formal samples are excluded. For P1–P4, emit marginal sigma/requirement, paired sigma/requirement, conservative required/candidate `n_formal`, cap status, and shared-cohort harmonization. Any conservative requirement above 148 blocks readiness.

Budget projection uses observed block-process wall times and raw bytes, not the old per-sample process projection. It reports median, p95, and conservative total wall time/bytes for the proposed 74-campaign schedule. It does not grant formal execution.

## 11. Final readiness conditions

Readiness passes only if:

- preservation, hashes, unit, compile, 63 regressions, and validation-only checks pass;
- formal root remains absent;
- pilot cardinalities/process identities are exact;
- structural mismatch count is zero;
- all block/checkpoint/hash/fail-closed tests pass;
- memory hard limits pass;
- candidate sample sizes and cap status are reported without using excluded data;
- the final checkpoint says `PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED`;
- no formal receipt or formal timing sample exists.

Passing readiness is not formal campaign authorization.
