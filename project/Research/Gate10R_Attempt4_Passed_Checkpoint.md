# Gate 10R Attempt 4 — Passed Checkpoint

Saved: 2026-10-06 (Asia/Shanghai)

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run / validate`
- Verification Status: `PASSED / WAITING-FOR-USER-AUTHORIZATION`
- Version Label: `gate10r_attempt4_filescope_retained_regression_passed_v4`
- Stable Run ID: `gate10r-to-gate12r-execution-v1`
- Active design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Evidence root: `Research/Verification/Gate10R_ProcessReuse_5pct/v4`

## Terminal outcome

Gate 10R attempt 4 passed. The terminal machine state is:

```text
GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION
```

The attempt-4 file/script-scope repair corrected the confirmed Windows PowerShell 5.1 child-`ScriptBlock` wrapper defect without changing algorithm behavior, Unity command semantics, one-process-per-Williams-block ownership, reset, telemetry, memory/carryover thresholds, lock-hygiene policy, 5% precision policy, uncapped candidate-`n_formal` policy, metrics, or future Playable Scene requirements.

Gate 11R, Gate 12R, Gate 13R preparation, and Gate 13R formal execution remain unauthorized and were not started.

## Passed hard gates

1. Outside-root, no-Unity preflight passed `64/64` after two versioned preflight-only audit-wrapper corrections. The mechanically derived retained harness passed `63/63`; the official `v4` root was still absent at that boundary.
2. Official preflight passed `16/16` and atomically consumed the one-use attempt-4 execution receipt.
3. Gate 10R unit tests passed `59/59`.
4. Unity compilation passed with zero compiler-error matches and natural lock release.
5. PSAPI/CIM telemetry probe passed and naturally released the Unity lock.
6. The first official block entry failed before starting its block Unity process because the plan generator expected the legacy top-level provenance projection. The failure receipt, partial manifest, and checkpoint were preserved. A versioned compatibility-only provenance projection was then used under the user's authorized retry/resume policy; research semantics were not changed.
7. Resume-1 block verification passed:
   - 3 positive Williams blocks in 3 distinct Unity Editor processes;
   - 1 expected-negative atomic fail-closed block;
   - 6 fresh cold-process structural references;
   - 10/10 structural comparisons with `0` mismatch;
   - independent-process repeatability passed;
   - positive/cold lock release was natural; expected-negative cleanup followed the frozen controlled-evidence policy.
8. The frozen retained regression passed `63/63` under Windows PowerShell 5.1 `-File` file/script scope.
9. The official final audit passed `55/55`.
10. The terminal integrity audit retry passed `8/8`. Its preserved v1 predecessor had `13/14` because it mistakenly treated two `archive_entry` reference rows as material project files; v2 correctly audited the documented 24 `working_copy`/`external_archive` material entries and retained the two archive-only reference rows separately.

## Principal immutable evidence

| Evidence | SHA-256 |
|---|---|
| Attempt-4 config | `9df8c08faae4621c93a5f3d1201b652c0516d6842389e74eb48067312025579c` |
| Base provenance | `6ea15fbd9e9c9755c6d69c56e7db15fa55de0239fdba7d4a14d352035f72f482` |
| Outside-root preflight v3 summary | `c99937522b8067a42a4be32f68f3459fded299667dea9ad1543e9cdb6fa2ba2f` |
| One-use official execution receipt | `7941737dd6d07e1802e56aa38ff497a5928673854b19c0841264c202b97c9f6f` |
| Official execution-1 failure receipt | `db20cbf21361e263b3abee22d6e34dd1efc420f1df2c6be4c1c19e9def3f7047` |
| Resume-1 receipt | `66bc2c00a45a73ff42f15a01b94a21b028e144e207b2cf2a7d065d7540aa9f95` |
| Block verification summary | `c31a66dd3545d92f7277ada0040b1c70d7c3063f85598e6484d0c22c560a3115` |
| Isolated retained `63/63` summary | `6ccf57725da15c98c8b04d341a698d48a13670d3e2bf09c6ef893b5f466672f9` |
| Evidence manifest | `95bb77828c4fa94d4d002bf455a8c2b2f9c9938d99840f61fba6f56c0c003106` |
| Final audit `55/55` | `8714fea2235d488abad7278bd6ccef9cf50f75aae57969220f40a19de16dd72c` |
| Terminal checkpoint | `fab889a1ff9f2d7911a6018b9cd3316e4dbff6e1c8cd8523678488ef252cbf56` |
| Terminal integrity v2 `8/8` | `bd652180c60254c1073f3c8c44e681172e2c4ecf706c98b1281c6123fed54d12` |

The final `v4` evidence-tree identity is:

```text
files       = 169
raw bytes   = 14,661,848
tree SHA-256= ac7f70b2098f6fc28eaa48116faabe1a527f34168d1c851f5a5d7e8cbbbc53b2
```

## Preservation results

- Attempt 1: `4` files / `9,577` bytes / tree SHA-256 `2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d`.
- Attempt 2: `101` files / `9,375,526` bytes / tree SHA-256 `da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce`.
- Attempt 3: `165` files / `14,661,809` bytes / tree SHA-256 `29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23`.
- Frozen `Run-Gate12AnalysisUnitTests.ps1`: `13,713` bytes / SHA-256 `e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1`.
- Frozen original `Gate12_AnalysisUnitTests.summary.json`: `1,748` bytes / SHA-256 `1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d`.
- All 24 material frozen baseline entries matched with zero mismatch.
- Historical cold-process/process-reuse roots remained read-only.
- Unity process count is `0`; `Temp/UnityLockfile` is absent.

## Downstream boundary

The following roots remain absent:

```text
Research/FormalScenarios/Gate11R_5pct/v1
Research/PlayableExperiments/Gate11R_5pct/v1
Assets/_Scenes/Research/Playable/Gate11R_5pct/v1
Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1
Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1
```

No Gate 11R matrix/Playable assets, Gate 12R pilot samples, candidate `n_formal`, Gate 13R formal root, formal receipt, or formal timing samples were created.

## Exact next step

Stop here. Do not modify or append to attempts 1–4. Do not start Gate 11R, Gate 12R, or Gate 13R without a new explicit user authorization.

If the user wants to follow the recommended sequence, request a separate Gate 11R authorization. A suitable authorization is:

> 授权 Gate 11R：以已通过的 Gate 10R attempt 4 和 `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1` 为唯一活动上游，先冻结并测试 5% process-reuse 正式场景矩阵、确定性种子、canonical identity、排除规则、Williams block 映射，以及每个实验条件对应的 Playable Unity Scenes/profiles/presets；规格与测试设计通过后只生成和验证 Gate 11R 场景、配置与 Playable bundle。不得启动 Gate 12R pilot 或 Gate 13R，不得修改 Gate 10R attempts 1–4、历史 cold/process-reuse roots、Gate 11 retained bundle、Gate 12 archives、原始脚本或原始场景；任一硬门禁失败时原子保存证据后停止。

