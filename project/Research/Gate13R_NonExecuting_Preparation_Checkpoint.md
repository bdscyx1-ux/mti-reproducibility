# Gate 13R Non-Executing Preparation Checkpoint

Saved: 2026-10-08 (Asia/Shanghai)

Terminal status: `GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED`

Gate 13R non-executing preparation is complete. The formal configuration, provenance, complete Williams-block schedule, validation-only orchestrator, raw-byte storage gate, execution-receipt guard, atomic checkpoint behavior and fail-closed semantics have been implemented and validated. This checkpoint does **not** authorize the formal campaign.

## Frozen formal design

- Design ID: `gate13r-one-fresh-unity-process-per-williams-block-5pct-uncapped-v1`.
- Precision: two-sided 95% CI with 5% relative half-width.
- Hard sample cap: none.
- Process unit: one fresh Unity Editor process per complete Williams block.
- Matrix: 53 scenarios / 74 campaigns / 212 eligible algorithm cells.
- Formal schedule: 42,064 unique block processes and 119,200 unique sample/run identities.
- Cohort allocation:
  - 32 shared-goal campaigns × 548 blocks = 17,536 blocks / 70,144 samples;
  - 21 per-agent heterogeneous-goal campaigns × 768 blocks = 16,128 blocks / 32,256 samples;
  - 21 grouped-field heterogeneous-goal campaigns × 400 blocks = 8,400 blocks / 16,800 samples.
- Memory policy: 128 MiB retained managed-memory per sample; 256/512 MiB per complete two-/four-sample block; 512 MiB working-set and private-memory per block.
- Launch storage gate: at least 188,047,724,816 original free bytes on `H:\` measured again at the actual formal launch.
- Serial p95 projection: 1,141,436.3340784 seconds (about 317.07 hours / 13.21 days).

## Passed validation evidence

- Unit tests v2: 51 assertions, 0 failures.
- Unity 2022.3.30f1c1 compilation: exit 0, 0 compiler-error matches, natural lock absence.
- Schedule validation: 32 assertions, 42,064 unique block IDs, 119,200 unique run IDs and 42,064 unique output paths.
- Validation-only orchestrator: passed; storage arithmetic passed, but the observed free-space snapshot is deliberately marked non-authorizing.
- Negative execute-without-receipt fixture: expected exit 1 with `A separately authorized formal execution receipt is required.`; no Unity process, lock, formal root or receipt was created.
- Deterministic regeneration: config, provenance, schedule and schedule manifest are byte-identical to the primary generation.
- Final audit: 47 assertions, 0 failures.
- Sealed evidence manifest: 17 files / 76,224,915 raw bytes; aggregate SHA-256 `4c28165b8be1209094ef27a31baac2c81e1a58feffb59885a393af11ba535bad`.

## Principal frozen hashes

- Formal config: `af5a164cdabeeff08cd6cd00b21ecd732fcbdc7f51be3454f99aaf65b2ef5109`.
- Provenance: `c1f8d4b4a8216b2e7f2dbdad7d49decbb77da38087f4c8c91a1366cd4d2963b8`.
- Full schedule JSONL: `dc460db08f501ef39869de29602cc0caf15106a264f930b55eb1875336c91aa6`.
- Schedule manifest: `070fc787df97c63a808c9a8abd8179d708a361a1c83d9cdec107f2aa6ed1182b`.
- Readiness amendment: `72d6ed97aebcf652d6796a72a3794ff11b39ed166271eb9ee8d87e8205984db7`.
- Final audit: `498cd50b23d85a2e3686010b346a77417c6fdb32c3146d95f49b8818c8741cb7`.
- Evidence manifest: `5da2251aee505a570f42f336048f4f5f4ad87f026df845e2f9aa36ece2e54f2c`.
- Machine-readable readiness checkpoint: `4cb0763f9b1717b8e92ac8f3a1b13b1b09d543fd3f720da9b61e06e7a4dce182`.
- Future formal-authorization prompt: `06bf1f88f6f1f99425d534210d05c538c266a49374aa5ebfda912fc09b64c738`.

## Preserved versioned repair evidence

All failures are retained and excluded from formal evidence:

1. Command derivation attempt 1 rejected an incorrect exact replacement-count assumption for the Gate 12R source.
2. Command derivation attempt 2 rejected a second incorrect exact replacement-count assumption.
3. Unit attempt 1 exposed Windows PowerShell 5.1 StrictMode behavior for an empty enumeration; v2 fixed only the count expression with an explicit array wrapper and passed 51/51.
4. Generation attempt 1 assumed a non-existent coverage property; generation v2 validates the actual frozen coverage counts/flags and completed successfully.

No failed attempt created a formal root, formal execution receipt or formal timing observation.

## Authorization boundary and current machine state

- Formal campaign authorization: **false**.
- Formal output root `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1`: absent.
- Formal execution receipt: absent.
- Formal timing blocks/samples: none.
- Unity processes after sealing: zero.
- `Temp/UnityLockfile`: absent.
- The validation-only storage snapshot was 291,975,700,480 free bytes and passed the arithmetic check, but it is not a launch authorization. The full preflight must be rerun immediately before any future formal-root creation.
- Automatic retry/resume remains prohibited for the formal campaign.

## Exact next step

Do not run any Gate 13R formal command until the user separately sends the complete authorization text in `Research/Gate13R_Formal_Campaign_Authorization_Prompt.md`. At that future launch, recompute and bind the current readiness-checkpoint and evidence-manifest hashes, rerun every frozen-input/environment/storage/Unity-lock preflight, and create the formal root only after all checks pass.

If formal authorization is not given, stop here and preserve every artifact byte-for-byte.

