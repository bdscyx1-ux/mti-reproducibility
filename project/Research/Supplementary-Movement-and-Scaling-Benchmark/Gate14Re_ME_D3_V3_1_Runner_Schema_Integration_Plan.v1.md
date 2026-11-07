# Gate14Re-ME D3-v3.1 runner/schema integration plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-d3-v3-1-runner-schema-integration-attempt-001`
- Stage: minimum versioned runner/schema integration
- Scientific endpoint: unchanged owner-thread cumulative managed-allocation bytes from exact `GC.Alloc` `Begin` UInt32/4 metadata

## Objective

Integrate the already qualified and frozen D3-v3.1 instrument into a new qualification-runner revision and a new complete-per-observation output-schema revision. The old V1 runner, old V1 output schema, D3-v2 evidence, and every D3-v3/v3.1 qualification artifact remain immutable.

## Raw-data design

D3-v3.1 is saved in a dedicated `d3-windows.raw.v1.jsonl` table. One row represents one explicitly bounded native counter window. Each row retains the owner-thread byte and event totals, foreign-thread diagnostics, invalid-metadata and overflow counts, owner native thread id, start/end/elapsed `Stopwatch` ticks, frequency, derived rate and its validity flag, native begin/end return codes, readiness/ABI checks, the measurement scope, and join keys to the corresponding initialization, event-group, or empty-boundary record.

The dedicated table prevents the true cumulative counter from being mislabeled as the retired start/end snapshot-difference design. Event-group and empty-boundary rows carry only a `d3WindowRecordId` join key plus validity state. The preexisting `operations.managedAllocatedBytes` field is explicitly retained only as an algorithm-reported diagnostic from `NavigationOperationMetrics`; it is not the formal D3 endpoint.

## Authorized sequence

1. Verify all parent and protected hashes and confirm that no qualification/formal measured root exists.
2. Add versioned D3 window contracts and a fail-closed bounded-window helper.
3. Add `Gate14ReMELoadQualificationRunnerV2` without modifying V1.
4. Add output schema v2 and an integrated D3-v3.1 instrument contract.
5. Add a one-shot algorithm-free integration self-check that never constructs a planner and never calls any runner mode.
6. Compile once with Unity 2022.3.30f1c1 and then run the one-shot integration self-check.
7. Verify strict JSON, bindings, source tokens, no algorithm invocation, no measured root, and no surviving Unity process.
8. Freeze the exact hashes and terminal receipt, then stop for separate authorization.

## Fail-closed criteria

Compilation failure, self-check failure, missing raw field, old D3 snapshot semantics in the new schema, parent/protected hash drift, any planner construction/invocation, or any schedule/input/identity/measured-root artifact makes this stage fail closed. No automatic expansion into qualification execution is allowed.

## Explicit exclusions

This stage does not generate a schedule, qualification input, or identity mapping; does not create a qualification measured root; does not run D2/D3/D4 runtime qualification modes or any algorithm lane; and does not perform formal collection, analysis, ranking, weighting, or winner adjudication.
