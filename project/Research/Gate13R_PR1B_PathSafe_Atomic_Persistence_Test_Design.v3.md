# Gate 13R-PR1B v3 Path-Safe Atomic Persistence Test Design

Status: `FROZEN-BEFORE-IMPLEMENTATION / VALIDATION-FIRST`

## Non-Unity gates

1. Parse every new PowerShell 5.1 entry point and run absolute-`ProjectPath` binding smoke tests without Unity.
2. Verify v6, v9, v10, v11 and all upstream bound files against frozen SHA-256/tree identities; verify v6 remains measured-count zero and excluded.
3. Verify the v3 command is additive and the v2 and Gate12R V3 commands remain byte-identical.
4. Static source checks require `.g13tmp-` plus 32 hex characters, same-directory `CreateNew`, containment and reparse validation, owned-temp cleanup, revalidation before move/replace, and immutable-target rejection.
5. Static control-flow checks require evaluation persistence and hashing before the first threshold branch, and evaluation references in sample failure, block failure, and checkpoints.
6. Regenerate the six campaigns and frozen warm-up/measured schedule exactly; pilot and formal roots must be absent.

## Unity path-boundary self-test

The self-test runs in an isolated verification directory and records every fixture. It creates path-equivalent mirrors, never writes into v6.

- C-FF-equivalent parent/final identity: legacy temporary length 259; legacy helper succeeds and v3 helper succeeds.
- IDFF/v6-equivalent identity: final length 223, legacy temporary length 260; legacy helper produces the observed `DirectoryNotFoundException` and v3 helper succeeds using a same-directory temporary path of 236 characters.
- Legacy temporary lengths 261 and 280: legacy helper fails and v3 helper succeeds while its temporary leaf remains 40 characters.
- Missing parent, path outside the allowed root, directory final target, and a real directory junction/reparse path are rejected before persistence.
- A pre-existing temporary collision is rejected and remains byte-identical.
- Injected write failure and injected pre-commit move failure fail closed; only invocation-owned temporary files are removed.
- Create-new immutable evidence rejects overwrite; explicit mutable replacement is tested separately.
- All successful fixtures verify UTF-8 without BOM, LF normalization, final SHA-256, same-directory temporary placement, and no residual `.g13tmp-*` files.

## Unchanged live gates

After compile and the path self-test, run the original 12 memory-policy fixtures and 8 telemetry-validity fixtures, PSAPI/CIM telemetry cross-check, complete positive mirrored verification, intentional position-2 fail-closed verification, independent-process repeatability, cold structural exact-match controls for all four algorithms, retained 63/63 regression, hash/provenance audit, and final validation-only audit.

The negative block must show one completed sample, a durable evaluation/hash for that sample, no later sample, terminal failure/checkpoint evidence, and no automatic retry/resume. Every Unity step must end with zero Unity processes and no `Temp/UnityLockfile`.

## Pilot decision

Only if every gate passes may the new pilot root be created. From that point the pilot is single-attempt: any warm-up, measured, quiescence, telemetry, memory, persistence, manifest, hash, or analysis failure terminates it. No versioned retry is authorized after root creation.
