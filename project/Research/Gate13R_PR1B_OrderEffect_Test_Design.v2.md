# Gate 13R-PR1B v2 Memory Observability and Order-Effect Test Design

Status: `FROZEN-BEFORE-UNITY-VERIFICATION / VALIDATION-FIRST`

## Non-Unity gates

1. Windows PowerShell 5.1 parses every v2 entry point and each passes explicit absolute-`ProjectPath` binding smoke.
2. The v2 preparation module validates exact plan identity, thresholds, roots, cardinalities, scenario/campaign identities, AB/BA quotas, contiguity, and unique run identities.
3. The analyzer compiles and passes deterministic synthetic fixtures without reading pilot data.
4. Upstream and attempt-1 preservation hashes match the pre-write audit; v1 roots and files are not written.
5. Static source inspection proves that `memory-gate-evaluation.json` is atomically written and hashed before a threshold exception can be thrown, and that sample/block failures and checkpoints carry its reference.
6. The formal root and fresh pilot root are absent.

## Unity memory-policy fixtures

The Unity self-test must pass all exact boundaries: below 128 MiB, exactly 128 MiB, above 128 MiB, exactly 256 MiB, above 256 MiB, complete-block managed exactly/above 256 MiB, working-set exactly/above 512 MiB, and private-memory exactly/above 512 MiB. It must also reject missing telemetry, mixed PID, mixed process start, non-finite process age, decreasing process age, non-positive counters, and decreasing GC counts.

## Live Unity gates

1. Compile the new additive command while proving the frozen V3 command remains byte-identical.
2. Run the self-test in a fresh verification output.
3. Run a fresh telemetry probe through the new command and require positive PSAPI counters cross-validated against independent CIM values and process identity.
4. Run one complete four-process mirrored positive fixture; require distinct Unity PIDs, complete resets, two memory evaluations per block, evaluation/manifest hash binding, structural validity, and retained alert samples.
5. Run an intentional position-2 fail-closed block; require one completed sample, no later execution, terminal checkpoint and failure evidence.
6. Repeat a frozen two-sample block in two independent fresh Unity processes and require exact structural projection equality.
7. Compare each algorithm in the two heterogeneous cohorts with a fresh cold-process reference and require exact structural equality.
8. Run the frozen 63/63 retained analysis regression under Windows PowerShell 5.1 file scope and prove its source and original summary hashes unchanged.

## Final validation-only gate

The audit requires all preceding summaries to pass, exact provenance hashes, 96 regenerated mirrored pairs, no partial identity, no Unity process/lock, v1/attempt-1 byte invariance, fresh pilot root absence, and formal root absence. Only this audit may set `pilotExecutionAuthorized=true`.

After measured execution begins, no retry or resume is allowed. A hard failure must preserve the durable evaluation, receipt, checkpoint, logs, and partial manifest, then stop.
