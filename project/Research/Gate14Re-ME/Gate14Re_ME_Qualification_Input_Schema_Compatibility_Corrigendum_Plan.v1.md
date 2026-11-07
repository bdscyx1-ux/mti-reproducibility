# Gate14Re-ME qualification-input schema compatibility corrigendum plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-001`
- Stage: minimum algorithm-free input-validation-schema corrigendum
- Runtime bundle identity: unchanged `gate14re-me-qualification-input-bundle-v1`

## Objective

Repair only the validation-layer omission proven by qualification-planning attempt-001: the frozen C# event-group DTO and oracle require `eventGroups[*].topology`, while validation schema v1 prohibits it. Preserve schema v1 and every prior artifact, create a versioned corrected validation schema, select it through one minimum versioned planning binding, and prove interoperability without creating any real qualification planning or measured data.

## Authorized sequence

1. Verify status v11, the retained failure evidence, frozen schema v1, DTO, oracle, runner V2, protocol, schedule schema, execution contract, and fairness-binding hashes.
2. Create `load-qualification-input-schema.v2.json` as a validation corrigendum. Preserve every v1 input constraint and the runtime bundle `schema` constant. Add only a required `eventGroups[*].topology` property using the same `compact`, `dispersed`, and `bottleneck` levels; retain cross-field equality as an oracle semantic check.
3. Create one versioned planning-schema binding selecting the corrected validator while retaining all existing runtime identities and frozen hashes.
4. Create and run a dependency-free PowerShell known-answer tool using `Test-Json`: a topology-bearing bundle must pass v2 and reproduce the v1 additional-property failure; missing topology, an invalid topology level, an unknown event-group field, and a missing required top-level field must each fail v2.
5. Add one algorithm-free Unity Editor self-check harness. In one batchmode invocation, compile the project, serialize and deserialize a synthetic DTO with `JsonUtility`, invoke the actual private `Gate14ReMEInputGeometryValidatorV1.ValidateGroupHeader` by reflection, and require: matching topology passes; missing and mismatched topology fail for the expected oracle reason.
6. Recheck protected hashes, absence of planning outputs and measured roots, zero planner/lane activity, then freeze sources, generated receipts, logs, hashes, and terminal status.

## Scientific invariants

- No factor, level, context stratum, event count, event phase, changed-cell rule, partition rule, geometry gate, algorithm identity, Williams schedule, endpoint, load threshold, statistical rule, or runtime bundle identity changes.
- JSON Schema performs structural and level validation. Equality between each event-group topology and input-level `changeTopology` remains enforced by the frozen Unity oracle.
- The v1 schema remains intact as historical evidence and is not selected for the next planning attempt.

## Fail-closed criteria

Any protected-hash drift, additional schema difference, bundle-identity change, unexpected known-answer result, Unity compile error, JsonUtility topology loss, missing reflection target, wrong oracle positive or negative result, second Unity invocation, partial planning artifact, measured-root creation, or planner construction fails this stage. The failed stage is retained and cannot be resumed without a new authorization.

## Explicit exclusions

This stage does not generate a qualification schedule, qualification input, replacement input, seed set, geometry, event set, or anonymous identity mapping; does not create `Research/PilotRuns/Gate14Re-ME`; does not run any algorithm lane or full oracle qualification; and does not perform formal collection, analysis, ranking, or winner adjudication.
