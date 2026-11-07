# Gate14Re-ME D3-v3 cumulative allocation qualification plan v1

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: run / isolated instrument qualification
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until the single authorized native build and Unity known-answer run pass
- Version Label: gate14re_me_d3_v3_cumulative_allocation_qualification_plan_v1

## Scope

This stage prospectively retires D3-v2 as the formal D3 while retaining every D3-v2 source and evidence artifact. It may implement and compile one Windows x86-64 native Unity profiler plugin, create one algorithm-free D3-v3 harness, execute one known-answer Unity process, and freeze the source, binary, hashes, instrument contract, and receipts only if all fixed criteria pass.

The stage does not modify or integrate the current qualification runner or output schema. It does not generate a schedule, input, anonymous identity mapping, or qualification measured root. It does not construct a planner, execute an algorithm lane, collect formal observations, analyze algorithms, rank algorithms, or adjudicate a winner. No fallback metric is permitted.

## Instrument definition

D3-v3 is owner-thread cumulative managed allocation bytes. The native plugin registers only for the exact Unity profiler marker GC.Alloc. During an explicitly armed window it reads metadata element zero only when its type is Int64 and its width is exactly eight bytes. Positive allocation sizes emitted on the owner Windows native thread are summed into the primary byte and event counters. Events on other threads are excluded from the primary counters and retained only as qualification diagnostics.

The raw time basis is Stopwatch ticks. The only derived rate is bytes multiplied by Stopwatch.Frequency and divided by positive elapsed ticks. The primary counter never subtracts bytes after garbage collection.

## Prospective one-shot controls

All criteria are fixed in the prospective contract before execution and may not be relaxed afterward:

1. The exact GC.Alloc marker must be found, its callback must register, and observed allocation-size metadata must be positive Int64 values of exactly eight bytes.
2. After P/Invoke, allocation, collection, and threading paths are warmed outside measurement, all 64 empty owner-thread windows must report zero owner bytes and zero owner events.
3. Single byte-array allocations of 4 KiB, 64 KiB, and 1 MiB must each report at least the requested payload and no more than 256 bytes of per-allocation overhead; results must be strictly increasing and overhead spread must not exceed 64 bytes.
4. Repeating a warmed 64-byte-array allocation 4096 times must scale both event count and bytes exactly from the one-object control.
5. A cumulative counter snapshot taken after an 8 MiB allocation must not decrease after forced GC. If GC emits no new managed allocation event on the owner thread, bytes and events must be exactly unchanged.
6. A 1 MiB allocation on the owner thread must produce a positive primary response attributed to the captured owner thread.
7. A warmed worker-thread 4 MiB allocation must leave owner bytes/events at zero while producing at least the requested bytes and one event in foreign-thread diagnostics.
8. Byte and rate formula values must be finite, positive where required, and exactly reproducible within the frozen numerical tolerance.
9. Every window must report zero invalid-metadata and overflow events.

## Stop and completion rules

Any frozen-input drift, build failure, Unity compilation or execution failure, timeout, exception, marker failure, metadata failure, attribution failure, empty-window response, scale failure, reclamation failure, or formula failure stops this stage without retry and preserves the failure evidence. It must not try D3-v2, a frame counter, heap occupancy, or another metric.

Only a full pass permits the final D3-v3 instrument contract, source/binary freeze manifest, qualification receipt, freeze receipt, and status v7. Success remains source-and-instrument qualification only; runner/schema integration and every algorithm or formal stage still require separate authorization.
