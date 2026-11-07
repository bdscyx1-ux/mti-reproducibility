# Gate 1 Baseline Audit

Audit date: 2026-10-04 (Asia/Shanghai)

## Preservation boundary

- Working copy: `H:\DDM_Final_Project`
- Immutable archive: `H:\DDM_Final_Project_Original.zip`
- Archive bytes: `1161214842`
- Archive SHA-256: `b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`
- Imported editor: Unity `2022.3.30f1c1 (a6dc00fbe362)`
- A recursive search found no `AGENTS.md` under the project.
- The directory is not a Git repository.

Gate 1 adds isolated research files only. It does not edit the 16 author scripts, existing scenes, packages, prefabs, or project settings. Working-copy author scripts were hashed directly and compared with their ZIP entries; all 16 match byte-for-byte. See `Research/Baseline_SHA256.csv`.

## Existing project

Build order:

1. `Assets/Scenes/MainMenu.unity`
2. `Assets/Scenes/NavMesh_BasePrepareScene.unity`
3. `Assets/Scenes/FlowField_BasePrepareScene.unity`

No project-authored `.asmdef` or `.asmref` exists, so new scripts compile into `Assembly-CSharp`. Generated `.csproj` and `.sln` files are ignored and are not substitutes for Unity compilation.

The three scenes, build settings, and package manifest match the archive. Import changed `ProjectVersion.txt` from `2022.3.30f1` to `2022.3.30f1c1` and changed package-lock registry URLs from `packages.unity.com` to `packages.unity.cn`; both pre-import and post-import hashes are recorded.

## Historical Flow Field findings

The original implementation is historical audit material, not the corrected baseline:

- Serialized grid: 100 x 250 cells; `cellRadius = 1`.
- Each spawn creates 50 units; source threshold is 400.
- Right-click synchronously recreates grid, cost, integration, and direction fields.
- Cost generation calls `Physics.OverlapBox` once per cell.
- `UnitFormation` assigns separate target cells, creating a direct-to-cell phase.
- Runtime-folder `GridDebug` imports `UnityEditor`.
- `InputHandler.Update` and `PlayerManager.Update` both call `HandleUnitMovement`.
- No structured experiment logging or incremental obstacle repair exists.

## Fixed research route

Primary algorithms are per-agent repeated A* (`A*-R`), per-agent D* Lite (`D*L`), and shared Incremental Dynamic Flow Field (`IDFF`). Corrected full-recompute flow field (`C-FF`) is the ablation baseline. NavMesh is excluded from the primary experiment. Visual feedback is held constant; audiovisual feedback is not currently an experimental factor.

Core metrics: `T_init`, `T_repair_p95`, cumulative planning CPU, processed nodes/cells, p95/p99 frame time, budget-overrun rate, success rate, 95% arrival time, memory/GC, path efficiency, and categorized failures.

## Gate 1 additions

- `DDM.Research.Navigation`: common grid, planning, repair, result, capability, and metrics contracts.
- `DDM.Research.Logging`: bounded background JSONL writer and fixed experiment record DTOs.
- No new `MonoBehaviour`; nothing is attached to a scene.

Gate 1 passes only when Unity batch mode exits 0, the log has no compiler-error signature, and `Library/ScriptAssemblies/Assembly-CSharp.dll` is newer than the new sources.
