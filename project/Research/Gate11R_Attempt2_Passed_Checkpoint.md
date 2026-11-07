# Gate 11R Attempt 2 Passed Checkpoint

Saved: 2026-10-07 (Asia/Shanghai)

Terminal status:

```text
GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION
```

## Authorized scope completed

Gate 11R froze, generated, and independently verified the 5% process-reuse scenario/config/Playable bundle using Gate 10R attempt 4 and design `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1` as the only active upstream. Gate 12R and Gate 13R were not authorized and did not start.

The retained design is:

- one fresh Unity Editor process per complete Williams block;
- two-sided 95% CI with 5% relative half-width target;
- minimum 32 blocks, upward rounding to a multiple of four, and no hard cap;
- 53 deterministic scenarios: 32 shared-goal and 21 heterogeneous-goal;
- 74 campaign conditions and 212 eligible algorithm cells;
- exact shared four-row and heterogeneous forward/reverse Williams mappings;
- one Playable Unity scene per canonical scenario, one profile per campaign, one preset per eligible algorithm cell;
- Playable outputs are visualization-only and permanently excluded from timing evidence.

## Gate results

1. Attempt-1 preimplementation audit was preserved at 73/74. Its sole failure was a PowerShell 5.1 versus PowerShell 7 filesystem ordering difference in a historical protected tree; no Unity or production root started.
2. Attempt 2 introduced ordinal relative-path canonical tree hashing. Cross-runtime preimplementation audit passed 48/48.
3. Unity compilation required two versioned typo/import repairs; compile attempt 3 passed. The later visible AssetDatabase staging repair compiled again in attempt 4.
4. Editor/specification unit gate passed 1269/1269 assertions with 10 negative tests.
5. Generation attempt 1 failed closed after Unity rejected a dot-prefixed AssetDatabase staging directory. Its two promoted research roots and 680-file Asset staging tree were moved byte-for-byte into `Research/Verification/Gate11R_5pct/v2/Generation/FailedAttempt1` and are excluded evidence.
6. Generation retry 2 used a visible, retry-specific Asset staging path and passed 1544 assertions. It produced 53 scenarios, 74 profiles, 212 presets, 53 scenario scenes, one launcher, and 744 manifest-tracked artifacts.
7. A separate fresh Unity process passed 5893 verification assertions, exact-regenerated all 53 scenarios, loaded all 53 scenario scenes plus the launcher, verified every profile/preset/GUID/hash, initialized and reset all 212 eligible planner cells, and observed zero bundle-byte mutation.
8. Final-audit attempt 1 failed before summary because the script projected the frozen CSV header incorrectly. Attempt 2 passed 88/89; its only failure was Windows PowerShell 5.1 default decoding of a no-BOM UTF-8 watermark. Both failures are preserved. The explicit-UTF-8 retry passed 89/89.

## Frozen active outputs

| Root | Files | Raw bytes | Ordinal tree SHA-256 |
|---|---:|---:|---|
| `Research/FormalScenarios/Gate11R_5pct/v1` | 57 | 125,218,919 | `0f41d8db5c01e9a1f1c14c7ee295151150d2efd91f6fc597fdb0b71b4f7eabe5` |
| `Research/PlayableExperiments/Gate11R_5pct/v1` | 4 | 427,601 | `4d269ff4ada239aa2e636169b590b65c23262d351f1d785087a0a9464fbc06f2` |
| `Assets/_Scenes/Research/Playable/Gate11R_5pct/v1` | 684 | 952,341 | `0ab0a465ce560fa7296a537d5fc969d364a6737d586ad8976215da156da4fd53` |

Principal identities:

- bundle manifest: `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`;
- coverage graph: `7298c124ec6ba2036c639f7b4720bf3634f47afb3f62516d1c9c5e58ac902c0e`;
- final audit: `Research/Verification/Gate11R_5pct/v2/Gate11R_FinalAudit.summary.v2.2.json`, SHA-256 `58d9a41c8d84da8438a61a13abfa255242a84dd8cdec425630651c4c89eed68a`;
- evidence manifest: `Research/Verification/Gate11R_5pct/v2/Gate11R_Evidence_Manifest.v2.json`, SHA-256 `25ade263b1101d368df4da41ba6476b53dda3639ead4afc9ad68184bf76a2d93`.

## Preservation result

- 11/11 historical protected trees matched the canonical ordinal baseline.
- 10/10 Gate 11R protected materials matched.
- 24/24 original project/archive baseline materials matched; the two `archive_entry` reference rows remained outside the material count.
- Gate 10R attempts 1-4, historical cold/process-reuse roots, old Gate 11 retained bundle, Gate 12 archives, original game scripts, original scenes, and the original ZIP remained unchanged.
- Failed Gate 11R evidence and partial output archives remain excluded and immutable.
- Unity process count is zero and `Temp/UnityLockfile` is absent.

## Authorization boundary and exact resume point

Gate 12R pilot authorization is `false`. `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1` is absent. Gate 13R authorization is `false`; its formal root is absent. No pilot, formal campaign, or timing sample was executed by Gate 11R.

Do not regenerate, retry, resume, overwrite, or append to the passed Gate 11R bundle. The next allowed action requires a separate user authorization for Gate 12R. Gate 12R must use the frozen 12-campaign anchor subset, one fresh Unity process per Williams block, fresh telemetry/environment preflight, block-aware variance/correlation, and the uncapped 5% candidate `n_formal` calculation; it must remain NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS and must stop before Gate 13R.

