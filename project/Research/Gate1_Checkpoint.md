# Gate 1 Checkpoint — Complete

Completed: 2026-10-04 15:52 (Asia/Shanghai)

## Completed

- Added root `.gitignore` for Unity/IDE generated output.
- Added `Research/Baseline_Audit.md`.
- Added `Research/Baseline_SHA256.csv` with the immutable ZIP, all 16 author scripts, build scenes, build settings, package files, and pre/post-import environment states.
- Added scene-independent navigation contracts at `Assets/_Scripts/Research/Navigation/NavigationContracts.cs`.
- Added a bounded background JSONL logger and experiment DTOs at `Assets/_Scripts/Research/Logging/JsonlExperimentLogger.cs`.
- No existing author script, scene, prefab, package file, or project setting was edited.
- Recomputed 21 frozen working-copy hashes after the additions: 21 checked, 0 mismatches.

## Compilation evidence

- Unity executable: `H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe` (relocated path confirmed 2026-10-04; product version `2022.3.30f1c1_a6dc00fbe362`).
- Unity refreshed `Library/ScriptAssemblies/Assembly-CSharp.dll` to 105,984 bytes at 2026-10-04 15:51:30, later than the newest Gate 1 research source (2026-10-04 11:09:21).
- Unity process count returned to zero.
- Final verification ran under the interactive `bdscy` execution identity and wrote `Research/Verification/Gate1_Unity.log` plus `Gate1_Unity.summary.json`.
- Final Unity exit code: `0`.
- Compiler-error signature count: `0` for `error CS####`, `Scripts have compiler errors`, and `Compilation failed`.
- The log contains both `Batchmode quit successfully invoked` and `Exiting batchmode successfully now!`.
- `Gate1_Unity.summary.json` records `passed: true` and `assemblyIsCurrent: true`.
- After relocating the editor to `H:\UnityEditor` and adding that directory to the workspace, Codex could launch `Unity.exe`, but Unity stopped before creating the project lock or Editor log. The paired `hasp_rt.exe` process and `SafeNet Sentinel/Sentinel LDK/error_36049.log` identify a pre-project Sentinel/HASP licensing failure: secure storage (`fridge`) could not be mounted and the configured port-1947 license endpoint reset the connection. This is not evidence of a C# compiler failure.
- That earlier licensing failure was resolved by reconnecting the local execution environment under `bdscy` with full access. Both earlier diagnostic processes were stopped, and the final run left no project lock.

## Gate decision

- **PASS.** Gate 1 is complete.
- Gate 2 may begin with only the research grid, deterministic scenario specification, and experiment-runner skeleton.
- D* Lite and IDFF remain explicitly out of scope.
- Original scripts and original scenes remain frozen and must not be modified or receive research components.

## Latest non-Unity checks

- `Run-Gate1UnityVerification.ps1` parsed with 0 PowerShell syntax errors.
- Recomputed all 24 frozen manifest entries (immutable archive plus working-copy baselines): 24 checked, 0 mismatches.
- Recomputed the same 24 frozen entries after the successful final Unity run: 24 checked, 0 mismatches.
