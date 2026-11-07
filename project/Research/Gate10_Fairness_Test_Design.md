# Gate 10 Fairness and Unified Campaign Test Design

Frozen: 2026-10-05 (Asia/Shanghai)  
Status: approved test design before production implementation

## 1. Acceptance principle

Gate 10 passes only if the four algorithms can be dispatched under a frozen, machine-verifiable comparison contract without mixing incompatible goal cohorts, provenance, scenarios, algorithms, budgets, metric meanings, or Unity processes. Gate 10 is a pipeline/correctness gate, not a performance study.

## 2. Specification audit before implementation

Before production source changes:

1. verify that the fairness specification and this test design exist;
2. verify the frozen ids, four profiles, three cohorts, dynamic-cost equation, normalized denominators, native-metric restriction, Williams order, homogeneous-aggregate rule, campaign boundary, and preservation boundary;
3. parse every existing PowerShell script;
4. verify all 24 frozen baseline entries;
5. verify that no Gate 10 production implementation file exists yet.

Any failure blocks implementation.

## 3. Runtime profile and cohort tests

The Unity verifier must assert:

- exactly four profiles and no duplicate ids;
- exact specification/implementation paths and state-model ids;
- exact native-metric semantics ids;
- shared one-goal scenarios classify as `four-algorithm-shared-goal-v1` for all four algorithms;
- heterogeneous scenarios classify A*-R/D*L as `per-agent-heterogeneous-goal-v1`;
- heterogeneous scenarios classify C-FF/IDFF as `grouped-field-heterogeneous-goal-v1`;
- every algorithm/cohort mismatch is rejected;
- A*-R records zero persistent states/fields;
- D*L records one persistent state per agent and zero fields;
- C-FF/IDFF record one shared field and one persistent state unit;
- distinct goal counts are deterministic under agent permutation.

## 4. Workload accounting tests

Using recording planners with deliberately distinct initialization, initial-plan, repair, and dynamic-plan metrics, verify exact arithmetic for:

- initialization work;
- initial-query elapsed/work;
- each dynamic phase's repair-plus-replan elapsed/work/allocation;
- dynamic totals;
- all-operation totals;
- per-agent elapsed/work;
- per-event dynamic elapsed/work;
- zero-event normalization;
- success and budget-overrun denominators;
- same-tick multiple-event inclusion before one replan phase;
- JSONL workload payload equality with the returned result.

The test must fail if dynamic accounting omits an event repair or a post-event plan.

## 5. Provenance and batch tests

Run every algorithm through the real Unity batch entry on the same canonical shared-goal fixture and verify:

- manifest schema and fairness extension version;
- exact algorithm specification id/path/SHA-256;
- exact implementation path/SHA-256;
- fairness specification id/path/SHA-256;
- fixed-start workload specification path/SHA-256;
- identical scenario source/fingerprint/canonical hashes;
- identical declared budgets and structural counts;
- exact comparison cohort;
- complete dynamic-cost flag;
- child JSONL identity and continuous sequence;
- result/manifest hashes;
- create-new/no-overwrite behavior;
- unsupported algorithms fail before output creation.

## 6. Identity rejection tests

The current compiled replication aggregator must continue reproducing all retained Gate 6–9 schema-v1 aggregates byte-for-byte.

For fairness-extended results it must reject:

- mixed algorithm ids;
- mixed scenario ids or fingerprints;
- mixed comparison cohorts;
- mixed fairness protocol ids/hashes;
- mixed algorithm specification ids/hashes;
- mixed implementation hashes;
- missing or malformed Gate 10 provenance;
- fixed-start or dynamic-cost-completeness false;
- structural and deterministic outcome mismatches.

Legacy schema-v1 results remain valid for historical reaggregation but are ineligible for a Gate 10 campaign.

## 7. Balanced scheduler tests

For the four-algorithm cohort, verify one complete four-block schedule exactly equals:

```text
A*-R D*L IDFF C-FF
D*L C-FF A*-R IDFF
C-FF IDFF D*L A*-R
IDFF A*-R C-FF D*L
```

Verify:

- every block has each algorithm exactly once;
- every position contains each algorithm exactly once per cycle;
- all 12 ordered predecessor pairs occur exactly once per cycle;
- run ids and directories are unique and deterministic;
- a block count not divisible by four is rejected;
- two-algorithm cohorts receive the two-row balanced design;
- cohort/algorithm mismatches fail before sample output creation.

## 8. Actual unified campaign fixture

Create one research-only shared-goal correctness scenario. Execute one complete four-block Williams cycle:

- 4 algorithms;
- 4 blocks;
- 16 independent Unity child processes;
- one algorithm sample per process;
- no formal warm-up or discarded sample;
- no inferential claims.

The retained campaign verifier checks every child artifact, provenance hash, scenario identity, JSONL sequence, outcome count, schedule position, ordered predecessor pair, and no-overwrite guard.

## 9. Regression and final audit

After Gate 10 integration:

1. real Unity compile verification;
2. Gate 2–9 behavioral and pipeline regression;
3. byte-identical current-code reaggregation for retained Gate 6–9 fixtures;
4. Gate 10 runtime, batch, scheduler, and retained-campaign verification;
5. all PowerShell, JSON, and JSONL parsing;
6. exact four-planner scope;
7. all frozen evidence hashes;
8. 24-entry baseline audit;
9. compiler-warning audit;
10. zero Unity processes and no `Temp/UnityLockfile`;
11. Gate 10 checkpoint and exact next-session resume point.

Any mismatch prevents Gate 10 completion.
