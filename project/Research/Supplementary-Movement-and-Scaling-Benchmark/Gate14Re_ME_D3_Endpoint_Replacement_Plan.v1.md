# Gate14Re-ME D3 Endpoint Replacement Plan v1

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: run / prospective endpoint replacement and source-only freeze
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until the one-shot D3-only Unity run and post-run validator pass
- Version Label: gate14re_me_d3_endpoint_replacement_plan_v1

## Scope

This is the next minimum stage after the original thread-local cumulative-allocation counter produced a zero response and the first process-wide cumulative-allocation candidate was absent from the bound Unity compile surface. The original D3 definition is retired prospectively rather than patched again.

This stage may define and implement only the replacement D3 endpoint, run one D3-only known-answer process, and create a source-only scientific freeze after every prospective criterion passes. It must not retry either failed attempt, start runtime-qualification attempt-002, run the exporter known-answer, generate qualification schedules, inputs, or identities, create a qualification measured root, construct a planner, execute an algorithm lane, collect observations, analyze algorithms, rank algorithms, or adjudicate a winner.

## Replacement endpoint

D3 v2 is **event-boundary managed-heap occupancy**, measured with `System.GC.GetTotalMemory(false)` in bytes.

The raw record must preserve:

1. `eventGroupManagedHeapBytesStart`;
2. `eventGroupManagedHeapBytesEnd` (the primary D3 value);
3. `eventGroupManagedHeapSignedDeltaBytes = end - start`.

The signed difference may be negative after garbage collection and must never be clamped, censored, or substituted. The endpoint estimates current managed-heap occupancy and excludes native memory. It is an allocation-related state endpoint, not cumulative allocation throughput. No claim from the retired D3 definition transfers to D3 v2.

The selection is grounded in the platform contract for `GC.GetTotalMemory(Boolean)`, which returns the best available approximation of bytes currently allocated in managed memory / heap size excluding fragmentation. The call already occurs in the six current planner source files and multiple existing Unity runners, establishing compile-surface availability without executing an algorithm.

Primary documentation:

- https://learn.microsoft.com/dotnet/api/system.gc.gettotalmemory
- https://docs.unity3d.com/Manual/performance-managed-memory-introduction.html

## Prospective one-shot acceptance criteria

All thresholds are fixed before the run and may not be relaxed afterward.

1. After warm-up and a full collection outside all measured intervals, execute 64 immediate capture pairs. The absolute signed difference of every pair must be no more than 65,536 bytes.
2. After a full collection, allocate, touch, and retain 8,388,608 bytes until the second capture. The signed occupancy increase must be at least 7,549,748 bytes (90%).
3. In a separate baseline after a full collection, allocate, touch, and retain 33,554,432 bytes until the second capture. The signed occupancy increase must be at least 30,198,989 bytes (90%).
4. The observed 32 MiB increase minus the observed 8 MiB increase must be at least 22,649,242 bytes (90% of the requested separation).
5. For the reclamation control, start after a full collection, allocate and retain 16,777,216 bytes through a peak capture, then leave the allocation scope and force collection before the final capture. The allocation increase must be at least 15,099,495 bytes, the recovered amount must be at least 13,421,773 bytes, and the final occupancy may not exceed the starting baseline by more than 2,097,152 bytes.
6. Every captured occupancy must be nonnegative. Negative signed deltas are valid only where permitted by the endpoint semantics.
7. The harness must construct no planner, execute no algorithm lane, create no qualification/formal observation, and touch none of the prohibited roots.

## Stop rules

Any authorization mismatch, prior-evidence hash mismatch, executable hash mismatch, prospective-contract mismatch, existing output path, concurrent Unity process, forbidden-root appearance, compilation error, timeout, exception, control failure, or evidence-boundary violation stops the stage without retry. Failed evidence is preserved; no further endpoint is tried in this authorization.

## Completion rule

Only a passing one-shot receipt permits creation of the versioned D3 instrument contract, source-freeze manifest, freeze receipt, and status v6. Even after success, the existing load-qualification runner is not silently modified, runtime-qualification attempt-002 remains unauthorized, and the exporter known-answer remains deferred.
