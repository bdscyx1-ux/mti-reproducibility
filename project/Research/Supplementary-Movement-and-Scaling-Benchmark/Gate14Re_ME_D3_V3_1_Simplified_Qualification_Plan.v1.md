# Gate14Re-ME D3-v3.1 simplified cumulative-allocation qualification plan v1

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: run / bounded instrument implementation and qualification
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until the D3-v3.1 known-answer and final hash freeze both pass
- Version Label: gate14re_me_d3_v3_1_simplified_qualification_plan_v1

## Method decision

D3-v3.1 preserves the scientific endpoint: owner-thread cumulative managed-allocation bytes observed from the exact `GC.Alloc` marker during an explicit native window. The only ABI correction is to require the data-bearing `Begin` event exposed by Unity 2022.3.30f1c1 as `UInt32`/4 bytes and losslessly widen every positive event value into checked 64-bit cumulative counters. `End` is ignored because the preserved probe established that it carries no metadata. Other event or metadata shapes fail closed.

The prior `Int64`/8 assumption, failed runs, array diagnostic, metadata probe, and all earlier receipts remain unchanged. The diagnostic and probe are not rerun.

## Simplified active chain

1. One versioned Windows x86-64 native plugin listens only to exact `GC.Alloc`, preserves owner/foreign thread separation, and exposes window snapshots.
2. One thin P/Invoke wrapper exposes that native ABI without metric logic.
3. One algorithm-free known-answer harness performs all controls and writes one terminal PASS/FAIL receipt. A failure receipt must retain every completed stage, every control object already computed, every raw window record collected before the first failure, and the exact first failure.

## Frozen controls

- Marker registration, callback registration, `UInt32` type value 3, four-byte width, positive values, and non-null metadata pointer are mandatory.
- All 64 warmed empty owner-thread windows must report zero owner bytes and events.
- One allocation at 4 KiB, 64 KiB, and 1 MiB must be strictly monotonic, stay within 0–256 bytes overhead, and have at most 64 bytes overhead spread.
- A 64-byte single-object control and 4096 repeated 64-byte objects must scale bytes and event count exactly.
- Cumulative counters must never decrease across forced collection. For each adjacent snapshot, unchanged event count requires exactly unchanged bytes; increased event count requires increased bytes.
- The 1 MiB array record supplies the same-thread positive control and byte/rate formula control; no extra rate window is collected.
- A 4 MiB worker-thread allocation must contribute zero owner bytes/events and a positive foreign-thread response.
- All windows must report zero invalid-metadata and counter-overflow events.

## Execution and stopping point

Reuse the already frozen hermetic Windows SDK and the existing `/std:c++17 /O2 /LD /EHsc /W4 /WX /utf-8 /permissive- /Brepro` policy. Build once, statically verify the x86-64 DLL and exports, then run one Unity algorithm-free known-answer using harness-owned `EditorApplication.Exit` and Burst compilation disabled. If it fails, preserve the cycle and repair only within this bounded D3-v3.1 implementation under the existing autonomous-repair authorization.

Passing qualification permits a source/binary/contract/receipt hash freeze only. Qualification-runner or schema integration, schedules, inputs, identity mappings, measured roots, algorithm lanes, formal collection, analysis, ranking, and winner adjudication remain outside this authorization.
