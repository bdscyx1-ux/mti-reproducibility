# Gate 12R pilot attempt 2 storage-feasibility diagnosis

## Terminal status

`Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2` is permanently terminal as `FAILED-NO-RESUME-NO-MERGE`. It completed all 8 warm-up blocks, all 36 cold structural controls, and all 384 measured Williams blocks / 1,152 measured samples. The failure occurred only after measured execution, when the frozen p95 storage-feasibility rule was applied. Nothing from this root is eligible for formal analysis, later sample-size estimation, resume, completion, or merging.

## Hard-gate result

The fresh pilot estimated uncapped 5% candidates of 432 blocks per shared-goal campaign, 264 per per-agent heterogeneous-goal campaign, and 68 per grouped-field heterogeneous-goal campaign. Under the unchanged 1.5 p95 safety multiplier and 20 GiB reserve, the shared-goal cohort required 1,017,077,443,328 free bytes while only 154,941,710,336 bytes were available. The pilot therefore failed closed as required.

## Confirmed storage implementation defect

The largest block outputs were not large because of measurements, logs, telemetry, results, or provenance. Each algorithm sample wrote a full local `scenario.canonical.json`. In the 256-by-256 grid campaign, each copy was 11,816,572 bytes, so a four-algorithm block carried four identical 11.8 MB files.

An independent audit of all 1,152 measured sample manifests established:

- 1,152/1,152 local canonical files existed and matched both manifest hashes;
- 1,152/1,152 were byte-identical to the referenced frozen Gate 11R scenario source;
- all sources were inside `Research/FormalScenarios/Gate11R_5pct/v1/Scenarios`;
- the measured root contained 3,806,864,000 duplicated canonical-input bytes;
- those copies represented only nine unique frozen upstream files totalling 29,741,125 bytes.

The canonical source is already an immutable, SHA-256-bound Gate 11R upstream input. Re-copying it into every sample does not add experimental evidence. It incorrectly makes formal incremental storage scale with `samples × scenario size` instead of retaining a hash-bound reference to the already frozen input.

## Authorized versioned correction

The next version may externalize only `scenario.canonical.json`, and only after proving exact byte identity against the frozen Gate 11R source named in the sample manifest. The sample manifest must retain the source path and both source/canonical SHA-256 values, declare the upstream-reference storage mode, and resolve back to an existing file with the same hash. Operations JSONL, workload result, telemetry, sample summary, block manifest, checkpoints, Unity logs, timing, reset boundaries, Williams order, scenarios, algorithms, precision formula, p95 multiplier, reserve, and exclusion rules remain unchanged.

Attempt 2 remains untouched. A passing result requires a new verification root and a new pilot root, a full pre-pilot rerun, and one wholly fresh pilot; no attempt-2 row may be copied, resumed, filled, or merged.
