# Gate14Re-ME qualification implementation freeze — source-only plan v1

## 1. Scope and authorization boundary

The user separately authorized the next stage with the exact text `单独授权下一阶段`. In the immediately preceding frozen state, the next stage was defined as the outcome-independent implementation and freeze of the mandatory precollection load-qualification machinery and exact resource ceilings. This stage therefore implements and freezes source, schemas, bindings and static evidence only.

This stage does **not** authorize or perform qualification input or schedule generation, anonymous identity-binding generation, measured-root creation, Unity compilation or execution, runtime instrument qualification, qualification measurement, formal input generation, formal collection, formal analysis, ranking, winner adjudication or any later experiment. No Gate14Re, Gate14Re-TB2, Gate13R or Gate13R-AX2 outcome was opened or used to tune this machinery.

## 2. Implemented components

The implementation is isolated from the six production planner sources.

- `Gate14ReMEQualificationContractsV1.cs` defines the future authorization, input, raw-row and receipt contracts.
- `Gate14ReMEReferenceOracleV1.cs` defines an algorithm-neutral, goal-rooted deterministic Dijkstra oracle and the frozen geometry checks. It creates no planner and uses no algorithm output to admit an input.
- `Gate14ReMEInstrumentationV1.cs` defines the D2 read-only grid proxy, D3 thread-allocation counter, D4 logical-capacity sizing formulas and resource snapshots.
- `Gate14ReMELoadQualificationRunnerV1.cs` defines four future Unity modes: `oracle`, `instrument-self-test`, `empty-boundary` and `lane`. Every mode requires a later exact-hash execution authorization. An invalid authorization cannot create a measured root or failure directory.
- `Run-Gate14ReMELoadQualification.v1.ps1` defines future serial, fresh-process orchestration with strict preflight, all-input oracle qualification before any lane, 12 empty-boundary processes, six strict serial lanes per superblock, and at most one supervisor-controlled whole-superblock technical replacement.
- `gate14re_me_qualification_structural_v1.py` validates future raw identities, paths, hashes, row cardinalities and replacement structure without computing cross-algorithm effects.
- `gate14re_me_qualification_delivery_v1.py` defines lossless JSONL, CSV, deterministic JSONL.GZ and typed Parquet delivery with record-ID round trips and tamper/missing/duplicate/anonymous-label-swap negative controls.

## 3. Frozen resource values

All values are prospective and absolute. They are not inferred from algorithm results.

| Resource | Frozen value | Qualification pass line |
|---|---:|---:|
| Event-group hard timeout | 300,000 ms | ≤ 300,000 ms |
| Lane wall-clock hard timeout | 5,400,000 ms | ≤ 5,400,000 ms |
| Oracle process timeout | 900,000 ms | process exits successfully |
| Instrument process timeout | 600,000 ms | process exits successfully |
| Empty-boundary process timeout | 600,000 ms | process exits successfully |
| Planner operation budget | 240,000 ms | no budget excess |
| Repair operation budget | 240,000 ms | no budget excess |
| Initialization budget | 600,000 ms | no budget excess |
| Lane assigned committed memory | 16 GiB | peak private memory ≤ 8 GiB (2× headroom) |
| Qualification storage reservation | 48 GiB | package ≤ 24 GiB (2× headroom) |
| Formal raw + delivery reservation | 96 GiB | projection ≤ 48 GiB (2× headroom) |
| Concurrent Unity processes | 1 | exactly serial |
| Whole-superblock technical replacements | 1 maximum | no per-algorithm retry/resume/top-up |

At the host snapshot, H: had 212,333,391,872 free bytes. Both frozen reservations total 154,618,822,656 bytes and would leave 57,714,569,216 bytes. The snapshot is a capacity basis, not a performance benchmark or a guarantee of later availability; future execution must check free space again before creating the measured root.

## 4. Instrument semantics

- D1 is the complete event-group wall-clock interval, including every atomic repair and all N path queries.
- D2 counts only planner-visible `Contains`, `IsWalkable` and `GetTraversalCost` calls through a semantic-invariant read-only proxy.
- D3 is `GC.GetAllocatedBytesForCurrentThread` end minus start over the same boundary. A valid zero is retained.
- D4 is planner-owned persistent logical capacity, reported component by component at 26 points per lane. It does not claim CLR-object, allocator, total-heap or RSS accuracy.
- Process private memory, working set, managed memory and peak working set are retained separately from D4.

Runtime evidence is intentionally absent at this stage. The known-answer, positive-control, synthetic-fixture, clock, round-trip and negative tests remain mandatory gates under a future execution authorization.

## 5. Six-algorithm fairness binding

The cohort is exactly A*-R, BiA*-R, D*L, LPA*, C-FF and IDFF. Each implementation and specification is bound by SHA-256 together with the shared navigation contracts and grid source. Every future superblock uses a byte-identical input across six fresh processes, the same oracle and dynamic boundary, no algorithm-specific warm-up/GC/query privilege, a frozen balanced order, and strict anonymous qualification reporting.

The production algorithm sources and specifications were not changed by this stage.

## 6. Delivery and current blocker

The delivery contract requires every raw row in four views: canonical JSONL, RFC 4180 CSV, deterministic gzip JSONL and typed Parquet. The source implements all four and fails closed when the Parquet engine is absent. At this freeze, the current Python runtime has neither `pyarrow` nor another supported typed-Parquet engine. This is recorded as a transparent readiness blocker, not silently downgraded to an aggregate or string-only format.

Before any qualification execution, a later separate authorization must cover a frozen Parquet dependency (or a new scientific amendment to the delivery format), Unity compilation, runtime instrument tests, qualification schedule/input/identity generation, root creation and qualification-only execution. Formal work remains a later and separate decision even if qualification passes.
