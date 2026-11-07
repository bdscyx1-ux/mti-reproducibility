# Gate 13R Non-Executing Preparation Test Design v1

## Material Passport

- Specification: `Research/Gate13R_NonExecuting_Preparation_Specification.v1.md`
- Amendment: `Research/Gate13R_Readiness_Amendment.v1.json`
- Test design ID: `gate13r-nonexecuting-preparation-tests-v1`
- Allowed execution classes: static, unit, Unity compile, validation-only, fixture, negative fail-closed
- Formal campaign authorization: `false`

## 1. Gate order

1. Verify authorization scope, upstream hashes, clean process/lock state, and formal-root absence.
2. Freeze specification, test design, amendment, path/identity/schema contracts, and derivation receipts.
3. Run Windows PowerShell 5.1 parser and explicit-parameter binding tests without Unity.
4. Run unit and negative-fixture tests without creating the reserved formal root.
5. Generate the canonical full schedule, schedule manifest, formal config, and provenance outside the formal root.
6. Regenerate into an isolated verification directory and require byte-identical deterministic artifacts.
7. Run Unity compilation only; do not invoke a timing execute method.
8. Run validation-only orchestrator and negative receipt/storage/checkpoint/root-escape fixtures.
9. Audit all hashes, counts, Playable mappings, process/lock state, historical preservation, and formal-root absence.
10. Emit only a non-executing readiness checkpoint and a future formal authorization prompt, then stop.

Any hard failure is preserved in its versioned verification attempt and stops that attempt. Repairs must use a new versioned attempt/root and cannot change frozen research semantics.

## 2. Static and parser assertions

- All new PowerShell files parse under Windows PowerShell 5.1.
- Every entry point requires an explicit absolute `ProjectPath`; no parameter default depends on `$PSScriptRoot`.
- Generator, validator, compile wrapper, block wrapper, and orchestrator binding-smoke modes start no Unity process.
- New files are additive; protected upstream hashes remain unchanged.
- `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1` is absent before and after every allowed test.
- No file named or typed as a formal execution receipt is generated.

## 3. Upstream/config assertions

- Gate 11R bundle, matrix, preregistration, Playable catalogs, Gate 12R readiness, candidate `n_formal`, budget/storage, memory amendment, Unity executable, runner command, specification, test design, amendment, and orchestration sources are hash-bound.
- Formal config states 53 scenarios, 74 campaigns, 212 eligible cells, 42,064 block processes, and 119,200 samples.
- Cohort campaign counts are 32/21/21; blocks per campaign are 548/768/400.
- Precision is two-sided 95% CI, 5% relative half-width, `hardCap = null`.
- Serial p95 is disclosed as 1,141,436.3340784 seconds.
- Formal authorization/root/receipt/timing flags remain false.

## 4. Full schedule and identity assertions

- The JSONL schedule contains exactly 42,064 non-empty records and hashes to the value bound by its manifest/config/provenance.
- Campaign order and scenario/cohort/Playable mappings equal the Gate 11R matrix.
- Every campaign has the cohort-specific block count and every block uses the correct Williams row.
- The full schedule contains exactly 119,200 ordered sample entries.
- Block IDs and run IDs are globally unique and match the frozen safe grammar.
- Positions are one-based and contiguous; predecessors match the prior position.
- Every output path is relative, normalized, unique, and contained by the reserved root.
- Each algorithm appears exactly once per block.
- Algorithm × within-process-position counts are balanced within each complete Williams cycle.

## 5. Memory/reset/telemetry assertions

- Single-sample retained managed limit is exactly 134,217,728 bytes.
- Two- and four-sample block retained managed limits are exactly 268,435,456 and 536,870,912 bytes.
- Block working-set/private-memory limits are exactly 536,870,912 bytes.
- The formal Unity command source preserves the Gate 12R reset, GC, PSAPI, sample/block hard-memory, atomic sample, and single-process-per-block implementation while changing only formal-bound identity/authorization semantics.
- Unity compiles with zero compiler-error patterns.

## 6. Storage preflight boundary tests

- `188,047,724,815` bytes fails.
- `188,047,724,816` bytes passes.
- A larger value passes.
- Negative, null, stale-snapshot-as-launch, wrong-volume, or rounded-GiB-only inputs fail.
- Validation-only may record current free bytes but marks the snapshot `NON-AUTHORIZING`.
- Root creation occurs only after storage and all other preflights pass in the future execute path.

## 7. Execution-receipt validator fixtures

The positive fixture must bind a synthetic later formal authorization, exact config/amendment/provenance/schedule/orchestrator/command hashes, exact resolved root, fresh environment/storage data, no-auto-retry/no-resume, and unconsumed status. It is accepted only in an isolated fixture directory and is never copied to `Research/` as a formal receipt.

Negative fixtures individually test missing formal authorization, current non-executing authorization substitution, wrong config hash, wrong schedule hash, wrong root, stale storage check, insufficient storage, retry/resume enabled, already-consumed receipt, and path escape. Every negative fixture must fail before root creation.

## 8. Atomic checkpoint and fail-closed fixtures

- Atomic write leaves no temporary file after success.
- A complete block transition requires every ordered sample completion marker.
- Injected failure after position 1 writes `failed-no-auto-retry-no-resume`, includes the partial manifest, and rejects later-position completion.
- Duplicate position, mismatched algorithm, wrong predecessor, mixed process ID, invalid memory verdict, or missing child hash is rejected.
- Partial block never increments completed-formal-block or completed-formal-sample counters.
- No fixture path may resolve within the reserved formal root.

## 9. Orchestrator validation-only assertions

- Validation-only validates all frozen files and complete schedule without creating the formal root.
- `-Execute` without a separately authorized, valid execution receipt fails before root creation and before Unity launch.
- Existing formal root, Unity process, or project lock fails closed.
- Campaign order is deterministic; the next block is never started after a failure.
- Automatic retry and resume counters are structurally fixed to zero.

## 10. Playable assertions

- All 74 campaign profiles resolve to canonical scenes.
- All 212 eligible cells resolve to algorithm presets.
- Playable paths and hashes match Gate 11R catalogs/coverage.
- Timing config marks `headless = true`, `loadPlayableScene = false`, `render = false`, and `obs = false`.

## 11. Final audit

The final audit requires all planned assertions to pass, deterministic regeneration to match, Unity process count zero, project lock absent, formal root absent, formal execution receipt absent, protected upstream hashes unchanged, and a complete evidence manifest for the verification root. Only then may the readiness checkpoint state `GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED`.
