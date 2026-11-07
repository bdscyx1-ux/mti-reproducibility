# Scenario I/O and Planning Workload Specification

Gate: 4

Runtime implementations:

- `Assets/_Scripts/Research/Scenarios/DeterministicScenarioJson.cs`
- `Assets/_Scripts/Research/Experiments/DeterministicPlanningWorkloadRunner.cs`

## Strict scenario-file boundary

`DeterministicScenarioJson` is the only supported schema-v1 JSON file boundary. It validates JSON structure before Unity's `JsonUtility` deserializes the data. This is necessary because `JsonUtility` otherwise ignores unknown fields, which could silently turn a misspelled experimental parameter into a default value.

The strict validator rejects:

- unknown or contextually misplaced fields;
- duplicate object fields;
- missing required fields, including explicitly empty arrays that must still be present;
- trailing commas or trailing root content;
- wrong JSON value types;
- fractional/exponent notation for integer fields;
- integers outside their declared Int32 or Int64 range;
- non-finite or out-of-range numeric tokens;
- invalid UTF-8 files;
- inputs larger than 16 MiB.

After structural validation, the normal scenario semantic validation still applies: dimensions, costs, budgets, topology, ids, coordinates, blocked starts/goals, and scheduled-event constraints must all be valid before resolution.

## Canonical scenario files

Canonical serialization starts from `ResolvedDeterministicScenario`, not the mutable source definition. It therefore writes:

- trimmed ids;
- agents, initial overrides, events, and changes in canonical order;
- inherited event repair budgets as their explicit effective values;
- UTF-8 without a byte-order mark;
- LF newlines;
- a final newline.

Parsing and canonicalizing a canonical file again must reproduce identical bytes and the same scenario fingerprint. Two valid source definitions that differ only in input-array order canonicalize to identical bytes.

Two hashes serve different purposes:

- the source-file SHA-256 identifies exact input bytes;
- `FingerprintSha256` identifies resolved scenario semantics.

Both should be retained in experiment provenance.

## Headless planning workload

`DeterministicPlanningWorkloadRunner` is a route-planning microbenchmark. It does not simulate motion.

Execution order is:

1. resolve the scenario and initialize the injected planner;
2. plan once for every agent from its declared scenario start;
3. jump directly to the next scheduled event tick;
4. apply every event at that tick in canonical order;
5. plan again for every agent from its declared scenario start;
6. repeat until all scheduled events are consumed;
7. complete the runner and emit a workload result.

Empty tick ranges are skipped without iteration. Events sharing a tick form one dynamic planning phase. Repair calls remain one per scheduled event, while replanning happens once per agent after the entire same-tick event group has been applied.

`usesFixedScenarioStarts` is always `true`. Consequently, workload results measure planning and dynamic map handling only. They are not arrival-time, movement, collision, or crowd-simulation results.

## Aggregation semantics

The workload result records operation/status counts, final grid version, initialization time, nearest-rank plan p95, nearest-rank dynamic-handling p95, summed planner elapsed time, search/cell work, allocation metrics, success rate, and operation budget-overrun rate.

For each dynamic phase:

```text
combined elapsed = sum(event ApplyChanges elapsed) + sum(all fixed-start replans elapsed)
```

This correctly includes A*-R full recomputation after a change instead of reporting only its inexpensive version acknowledgement.

The budget-overrun denominator includes initialization, plan, and repair/acknowledgement operations. Plan success rate uses plan operations only.

## Exclusions

This gate does not generate scenarios, move agents, detect arrival, measure frames, modify scenes, implement C-FF, D* Lite, or IDFF, or perform cross-run statistical inference.
