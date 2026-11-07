# Next Session Checkpoint

Saved: 2026-10-06 (Asia/Shanghai)

Current state: Gate 10R attempt 4 passed all authorized hard gates and stopped at `GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION`. Gate 11R, Gate 12R, Gate 13R preparation, and Gate 13R formal execution are not authorized and did not start.

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run / validate`
- Verification Status: `PASSED / WAITING-FOR-USER-AUTHORIZATION`
- Version Label: `gate10r_attempt4_passed_v4`
- Stable Run ID: `gate10r-to-gate12r-execution-v1`
- Active design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Attempt-4 root: `Research/Verification/Gate10R_ProcessReuse_5pct/v4`

## Authorization boundary

- User authorization covered Gate 10R attempt 4 controlled, versioned wrapper repair plus retry/resume until Gate 10R passed.
- Gate 11R authorization: false.
- Gate 12R authorization: false.
- Gate 13R preparation/formal authorization: false/false.
- Attempt 4 stopped on the first complete pass as required.

## Gate 10R attempt-4 result

1. Outside-root no-Unity preflight: `64/64`; retained file-scope smoke: `63/63`.
2. Official preflight: `16/16`.
3. Gate 10R unit tests: `59/59`.
4. Unity compile: passed; natural lock release.
5. PSAPI/CIM telemetry probe: passed; natural lock release.
6. Official block execution-1: failed before starting block Unity due solely to legacy provenance projection shape; its receipt/manifest/checkpoint are frozen.
7. Versioned resume-1: passed 3 positive blocks, 1 expected-negative fail-closed block, 6 fresh cold references, and 10/10 structural comparisons with zero mismatch.
8. Retained regression: `63/63` under Windows PowerShell 5.1 `-File`; no child `ScriptBlock`.
9. Final audit: `55/55`.
10. Terminal integrity audit retry: `8/8`; all 24 material frozen baseline entries matched.

## Principal terminal evidence

- Human checkpoint: `Research/Gate10R_Attempt4_Passed_Checkpoint.md`.
- Final summary: `Research/Verification/Gate10R_ProcessReuse_5pct/v4/Gate10R_FinalAudit.summary.v4.json`, SHA-256 `8714fea2235d488abad7278bd6ccef9cf50f75aae57969220f40a19de16dd72c`.
- Evidence manifest: `Research/Verification/Gate10R_ProcessReuse_5pct/v4/Gate10R_Evidence_Manifest.v4.json`, SHA-256 `95bb77828c4fa94d4d002bf455a8c2b2f9c9938d99840f61fba6f56c0c003106`.
- Terminal checkpoint: `Research/Verification/Gate10R_ProcessReuse_5pct/v4/gate10r-checkpoint.json`, SHA-256 `fab889a1ff9f2d7911a6018b9cd3316e4dbff6e1c8cd8523678488ef252cbf56`.
- Terminal integrity audit v2: `Research/Gate10R_Attempt4_Terminal_Integrity_Audit.v2.json`, SHA-256 `bd652180c60254c1073f3c8c44e681172e2c4ecf706c98b1281c6123fed54d12`.
- Attempt-4 tree: `169` files / `14,661,848` bytes / SHA-256 `ac7f70b2098f6fc28eaa48116faabe1a527f34168d1c851f5a5d7e8cbbbc53b2`.

The first terminal-integrity script output is preserved at `Research/Gate10R_Attempt4_Terminal_Integrity_Audit.v1.json`. It failed only because it counted two `archive_entry` reference rows as material project files; v2 corrected the audit scope to the documented 24 `working_copy`/`external_archive` entries. This was an audit-only correction, not an experiment retry or semantic change.

## Preservation state

- Gate 10R attempts 1–3 remain byte-identical to their frozen tree identities.
- The frozen retained source and original 63/63 summary remain byte-identical.
- Historical cold-process/process-reuse roots remain read-only.
- Original scripts/scenes and the immutable project archive match the frozen baseline.
- Unity process count: `0`.
- `Temp/UnityLockfile`: absent.

## Downstream state

- `Research/FormalScenarios/Gate11R_5pct/v1`: absent.
- `Research/PlayableExperiments/Gate11R_5pct/v1`: absent.
- `Assets/_Scenes/Research/Playable/Gate11R_5pct/v1`: absent.
- `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1`: absent.
- `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1`: absent.
- New candidate `n_formal`: not calculated; it remains a Gate 12R output.

## Exact resume point

Do not retry, resume, overwrite, or append to Gate 10R attempts 1–4. Read `Research/Gate10R_Attempt4_Passed_Checkpoint.md` and the terminal JSON checkpoint first.

The next recommended work is Gate 11R, but it requires a separate user authorization. Gate 11R should freeze and validate the 5% process-reuse scenario matrix, deterministic seeds, canonical identities, exclusion rules, Williams-block mappings, and the complete Playable Scene/profile/preset bundle; it must not start Gate 12R or Gate 13R.

Read first:

- `Research/Gate10R_Attempt4_Passed_Checkpoint.md`;
- `Research/Verification/Gate10R_ProcessReuse_5pct/v4/gate10r-checkpoint.json`;
- `Research/Verification/Gate10R_ProcessReuse_5pct/v4/Gate10R_FinalAudit.summary.v4.json`;
- `Research/Gate10R_Attempt4_Terminal_Integrity_Audit.v2.json`;
- `Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md`;
- `Research/Overall_Project_Plan.md`;
- `Research/Gate10R_to_Gate12R_Execution_Run_Passport_run_ledger.yaml`.

