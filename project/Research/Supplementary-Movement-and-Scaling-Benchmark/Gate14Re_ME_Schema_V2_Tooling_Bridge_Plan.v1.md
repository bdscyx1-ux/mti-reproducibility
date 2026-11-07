# Gate14Re-ME schema-v2 tooling bridge plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-schema-v2-tooling-bridge-attempt-001`
- Stage: minimum algorithm-free structural/delivery tooling bridge
- Scientific endpoint: unchanged D3-v3.1 owner-thread cumulative managed-allocation bytes from exact `GC.Alloc` `Begin` UInt32/4 metadata

## Objective

Add new versioned Python tools that can fail closed on output-schema v2 raw packages and create/verify complete per-observation JSONL, RFC 4180 CSV, deterministic JSONL.GZ, and typed-Parquet deliveries. The tools must understand `d3-windows.raw.v1.jsonl`, the event-group and empty-boundary join keys, D3-v3.1 counter semantics, and the zero/rate policy. The frozen v1 tools, integrated runner, schema, D3 contract, and all prior evidence remain unchanged.

## Authorized sequence

1. Verify parent, schema, D3 contract, typed-Parquet runtime, runner, and protected-v1-tool hashes.
2. Add `gate14re_me_qualification_structural_v2.py` with exact scalar typing, D3 row semantics, fixed lane/empty-boundary cardinalities, and one-to-one join validation.
3. Add `gate14re_me_qualification_delivery_v2.py` with fixed raw-table order, source/path/hash validation, deterministic four-view export, explicit column types, full value/type round trips, and manifest verification.
4. Add an algorithm-free synthetic known-answer harness under the new verification attempt.
5. Generate only synthetic raw fixtures under that verification attempt: one 24-event synthetic lane with 25 D3 windows and one 1000-iteration empty-boundary process with 1000 joined D3 windows.
6. Run positive structural, export, and delivery verification checks.
7. Run isolated negative fixtures for source tamper, missing join row, duplicate record ID, scalar type substitution, rate-formula mismatch, retired snapshot-field injection, and anonymous-label/identity swap. Each must fail closed.
8. Recheck protected hashes and absence of qualification/formal measured roots, then freeze exact sources, evidence, and terminal receipt.

## Lossless delivery contract

Every source row remains independently addressable by `recordId`. JSONL and JSONL.GZ preserve canonical values; CSV uses a manifested fixed column order and explicit source-derived scalar type map; Parquet uses an explicit Arrow schema. Verification compares complete row order, keys, values, and Python scalar types after every round trip. D3 joins are revalidated against the canonical exported rows, and every product hash is bound in the delivery manifest.

## Fail-closed criteria

Any wrong schema/D3/runtime hash, malformed JSONL, missing required field, non-flat or non-finite value, bool-as-integer substitution, signed-int64 overflow, duplicate `recordId`, invalid D3 marker/ABI/thread/counter state, wrong rate or zero policy, tick regression, missing or multiple join target, retired D3 snapshot field, source path/hash drift, round-trip type/value change, product tamper, protected hash drift, algorithm invocation, or forbidden root creation fails the stage.

## Explicit exclusions

This stage does not generate qualification scheduling, qualification inputs, or anonymous identity mappings; does not create a qualification measured root; does not construct or invoke planners or run any algorithm lane; and does not perform formal collection, formal analysis, weighting, ranking, or winner adjudication.
