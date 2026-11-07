# Gate 13R 48-hour / 10% / three-lane test design v1

## Static and binding gates

1. Windows PowerShell 5.1 parser checks every new `.ps1` and `.psm1` entry.
2. Binding-smoke tests resolve explicit `ProjectPath`, clone root, verification root, pilot root, and Unity executable without starting Unity.
3. JSON schema/identity tests require three lanes, 48-hour hard ceiling, 42-hour readiness p95, 74 campaigns, 10% relative half-width, no hard cap, one fresh process per Williams block, 384 pilot blocks, 1,152 pilot samples, 128 measured waves, 12 warm-up blocks, and 172 licensing stress waves / 516 processes.
4. Frozen Gate 11R, Gate 12R, Gate 10R, v16 failure evidence, original scripts, and original scenes are hash-checked. The old 4-lane v17 prompt remains unchanged and is marked superseded before implementation.
5. The three-lane schedule must regenerate byte-identically. Lane totals must be 128/128/128; cohort totals per lane 64/32/32; campaign/lane cells 10 or 11; imbalance for lane, Williams row, algorithm position, predecessor, and admission position at most one where exact equality is arithmetically impossible.

## Unity and barrier gates

1. Compile the additive three-lane batch command in a fresh lane copy.
2. Serially bootstrap all three lane copies and verify zero compiler errors and clean lock release.
3. Run PSAPI/CIM telemetry in every lane and retain the existing tolerances and memory rules.
4. Positive barrier test: three fresh processes must produce serial evidence and method-ready records in the registered rotating order, remain blocked before release, begin workload only after one atomic release record, exact-match cold structural references, and exit cleanly.
5. Negative tests must separately cover missing serial evidence, explicit inactive entitlement/no-valid-license, terminal licensing-client channel loss, process exit before method-ready, missing release, malformed release, release timeout, wrapper failure, partial wave, and residual-lock handling. The transient `Access token is unavailable; failed to update` line is diagnostic unless it is followed by terminal entitlement failure or process exit without serial assignment, matching the preserved v16 successful-log evidence. Every negative test must fail closed with no later sample or wave.
6. Independent-process repeatability, one-process-per-block, PID uniqueness, reset completeness, static-state leakage, process age, JIT/GC, RSS/private/managed-memory trends, and hash/provenance checks remain mandatory.
7. Retained regression must reproduce the frozen 63/63 Gate 12R analysis suite.

## Licensing stress gate

Run 172 consecutive, nonmeasured, three-lane admission/barrier waves. Admission position rotates `1-2-3`, `2-3-1`, `3-1-2`. Require 516 fresh Unity process identities, 516 serial assignment records, 516 method-ready records, 172 release records, zero retries, zero terminal license failures, and zero residual processes/locks. A single failure terminates qualification and forbids pilot creation.

## Sole NON-FORMAL pilot

Only after every earlier gate passes may the pilot root be created once. Write an execution receipt containing `NON-FORMAL`, `EXCLUDED-FROM-FORMAL-ANALYSIS`, `NO-AUTO-RETRY`, `NO-RESUME`, `NO-PARTIAL-MERGE`, and `FORMAL-CAMPAIGN-NOT-AUTHORIZED`.

Run 12 excluded warm-up blocks followed by 128 measured three-lane waves / 384 measured blocks / 1,152 measured samples. A failed lane excludes the entire wave and terminates the pilot. No successful sibling lane from a failed wave may be merged.

## Post-pilot analyzer

The analyzer runs only on a complete pilot. It verifies all cardinalities and hashes, zero structural mismatch, lane/admission/position/predecessor balance, memory and reset gates, process uniqueness, Playable mapping, block-aware marginal and paired variance/correlation, uncapped 10% candidates, admission/barrier/workload overhead, conservative three-lane efficiency, storage, and full end-to-end p95 projection.

Readiness passes only when every gate passes and projected formal p95 is at most 42 hours. The analyzer must explicitly state that formal execution remains unauthorized. Any failure produces a terminal non-ready checkpoint and stops.
