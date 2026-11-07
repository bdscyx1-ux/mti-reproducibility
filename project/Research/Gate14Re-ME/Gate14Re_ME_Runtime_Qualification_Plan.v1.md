# Gate14Re-ME Runtime Qualification Plan v1

## Scope

This stage is limited to runtime qualification of the already frozen source implementation. It may install and hash-freeze an isolated typed-Parquet engine, compile the Unity project against the frozen implementation, run D2/D3/D4/clock known-answer controls, and run the frozen delivery source through known-answer export round trips.

It must not generate a qualification schedule, qualification input, anonymous identity map, qualification measured root, algorithm lane, formal input, formal observation, statistical comparison, ranking, or winner.

## Prospective bindings

- Prior implementation manifest SHA-256: `9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4`.
- Prior source-freeze receipt SHA-256: `43c9dba8b49a1efe0802f6046170be57506c027af9ac764138843c60eef669f7`.
- Typed-Parquet distribution: `pyarrow==25.0.1`, CPython 3.12, Windows x86-64.
- Dependency installation is isolated under `Research/Gate14Re-ME/Runtime/v1`; downloaded wheels and every installed file must be hash inventoried and made read-only.
- Runtime evidence is confined to `Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001`.
- At most one Unity process may run at a time. No automatic retry is authorized.

## Ordered procedure

1. Revalidate the prior source-freeze receipt, implementation-manifest hash, read-only state, absent prohibited roots, and zero matching Unity processes.
2. Download the pinned binary wheel set once, install it locally from the downloaded wheel set, inventory all wheel and installed-package bytes, and freeze them read-only.
3. Add a qualification-only editor harness that calls the frozen public D2/D3/D4 instrumentation APIs without constructing or running any algorithm planner.
4. Compile the Unity project once. Treat any compilation failure as fail-closed evidence; do not retry automatically.
5. Run the C# known-answer harness once under a hard timeout and require all five controls to pass: D2 known answer, D2 semantic invariance, D3 allocation positive control, D4 synthetic fixture, and clock monotonicity.
6. Load the frozen delivery source without bytecode generation and run JSONL, gzip JSONL, CSV, and typed-Parquet known-answer round trips plus tamper, missing-field, duplicate-ID, and anonymous-label-swap negative controls.
7. Bind logs, receipts, dependency inventory, source hashes, executable hashes, and boundary checks into a read-only runtime-qualification freeze receipt.

## Stop rules

Any executable, source, prior receipt, manifest, dependency, wheel, installed-file, output-path, or authorization mismatch fails closed. Any appearance of a prohibited measured/analysis/export root or any request to generate schedule/input/identity material stops this stage. No result may be interpreted as evidence of algorithm performance or advantage.
