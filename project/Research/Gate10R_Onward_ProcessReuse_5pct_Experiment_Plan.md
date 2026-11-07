# Gate 10R 以后实验重基线计划：Williams-block 进程、5% 精度与全覆盖 Playable Scenes

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-06T15:45:00+08:00
- Verification Status: 5% READINESS VERIFIED AND PRESERVED / 36H REDESIGN SELECTION PENDING / FORMAL CAMPAIGN NOT AUTHORIZED
- Version Label: gate10r_5pct_rebaseline_plan_v2.1
- Active Design ID: `gate10r-onward-one-process-per-williams-block-5pct-playable-v1`
- Upstream Evidence Audit: `Research/Gate10R_5pct_Rebaseline_Evidence_Audit.v1.json`
- Machine-readable Decision: `Research/Gate10R_5pct_Rebaseline_Decision.v1.json`
- Gate 10R terminal upstream: `Research/Verification/Gate10R_ProcessReuse_5pct/v4`
- Gate 11R retained bundle: `Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json` (`5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`)
- Gate 12R readiness: `Research/Gate12R_Readiness_Checkpoint.v1.json`
- Gate 13R non-executing readiness: `Research/Gate13R_NonExecuting_Readiness_Checkpoint.v1.json` (`4cb0763f9b1717b8e92ac8f3a1b13b1b09d543fd3f720da9b61e06e7a4dce182`)
- Post-readiness author constraint: `Research/Gate13R_36h_WallClock_Constraint.v1.json`

## 1. 结论先行

从本计划生效起，Gate 1–9 继续作为算法正确性和基础设施前提；旧 Gate 10–13 全部转为历史谱系，不再作为新正式实验的活动合同。新活动路线从 **Gate 10R** 开始，重新冻结公平性、进程所有权、遥测、统计单位、场景矩阵、pilot 和 formal campaign。

新路线的四个核心决定是：

1. 一个完整 Williams block 使用一个全新的 Unity Editor 进程；
2. 进程内按冻结 Williams 顺序运行 2 个或 4 个算法样本，每个算法最多一次；
3. 正式样本量目标恢复为双侧 95% CI 的 **5% 相对半宽**，不继承旧 10%/cap-148 结论；
4. 每个实验条件都必须具有可在 Unity Editor 中进入 Play Mode 的可视化入口，供后续确定性重放和 OBS 视频录制。

本文件最初只完成重新规划；现在已经由实际证据推进并验证到 Gate 13R 旧 5% 非执行准备。Gate 10R attempt 4 已完整通过 block-process、telemetry、lock-hygiene、fresh-cold structural、repeatability、retained `63/63` 和 final audit；Gate 11R attempt 2 已冻结并验证 53 scenarios / 74 profiles / 212 presets 的 Playable bundle；Gate 12R 最终通过 384 个 measured Williams-block 进程和 1,152 个 measured samples，并生成三类 cohort 的无 cap 5% 候选 `n_formal`。Gate 13R preparation 已冻结并验证 74 campaigns、42,064 个唯一 block IDs、119,200 个唯一 sample/run IDs、正式 config/provenance/schedule、receipt guard、storage gate 和原子 checkpoint。用户随后把 formal 端到端硬墙钟上限改为 36 h，因此该 5% config 只保留为未执行证据；正式 campaign、redesign 和并发 pilot 均未授权，正式根仍不存在。

## 2. 历史证据如何使用

### 2.1 可以作为新设计依据的实际证据

- 四算法正向 fixture 已实际完成 4/4 样本，全部样本使用同一个 Unity PID `30828`，顺序为 `A*-R → D*L → IDFF → C-FF`；
- 两算法正向 fixture 已实际完成 2/2 样本，全部样本使用同一个 Unity PID `3440`，顺序为 `A*-R → D*L`；
- 两个 fixture 使用不同 PID，证明“每 block 一个新进程”已经有可工作的实际实现；
- process-reuse v1 pilot 实际完成 45 个 Unity 进程、108 个样本、36 个 measured block 和 96 个 measured 样本；fresh-cold 结构投影为 0 mismatch；
- v2 telemetry probe 已证明 Unity 内 `GetProcessMemoryInfo/PROCESS_MEMORY_COUNTERS_EX` 能返回正 working-set/private-memory，并能由独立父进程 CIM 对同一 PID 交叉核验；两项外部查询均位于内部前后采集区间中。

### 2.2 不得迁移到新统计设计的旧结果

- cold-process Gate 12 pilot 的方差、5% `n_formal`、cap-100 结论；
- cold-process Gate 13 amendment 的 10%/cap-148、52/148/52/52、15,056 个 sample-process 和存储投影；
- 已终止 Gate 13 cold-process formal root 的任何 timing 数据；
- process-reuse v1 pilot 的 timing、方差、candidate n 和内存结论；
- process-reuse v2 未开始 pilot，因此不存在可用样本量结论。

旧证据只证明实现形态、结构等价能力和已知失败风险。活动 `n_formal` 现已由 Gate 12R fresh process-reuse pilot v4 独立产生；attempts 1–3 仍永久排除且不得与 v4 合并。

## 3. 新实验单位与因果比较边界

### 3.1 独立单位

独立运行时单位和统计聚类单位统一为：

```text
1 fresh Unity Editor process = 1 complete Williams block
```

四算法 shared-goal block 包含：

```text
1 × A*-R + 1 × D*L + 1 × C-FF + 1 × IDFF
```

两算法 heterogeneous block 分别包含：

```text
per-agent cohort:       1 × A*-R + 1 × D*L
grouped-field cohort:   1 × C-FF + 1 × IDFF
```

同一 block 内样本共享进程、managed heap、JIT/cache 历史和系统瞬时状态，因此不是彼此独立的四个或两个实验单位。分析必须保留 `blockId`、Unity PID、process-start time、position 和 predecessor；主要成对对比利用 block 内配对，不把 block 内观测当作独立重复。

### 3.2 Williams 顺序

四算法完整四行周期继续使用：

```text
block row 1: A*-R, D*L, IDFF, C-FF
block row 2: D*L, C-FF, A*-R, IDFF
block row 3: C-FF, IDFF, D*L, A*-R
block row 4: IDFF, A*-R, C-FF, D*L
```

两算法使用正序/逆序两行，但正式 block 数仍统一取 4 的倍数，以便所有 cohort 使用同一个完整调度粒度。每个算法在完整四行周期中获得位置平衡；四算法设计同时平衡有序 predecessor。position、predecessor、process age、JIT、GC 和缓存增长必须留在诊断表中。

### 3.3 进程和样本隔离

每个样本前后必须在计时端点之外完成：

- 完整 GC 边界；
- 新建 scenario definition、resolved scenario、grid、planner、runner、logger、writer thread、metrics collector 和 manifest state；
- logger flush/dispose/join；
- runner dispose 和 planner reset；
- 非内联 sample method 返回，使大对象离开作用域；
- post-return full GC 和 retained-memory 采集；
- 原子写入样本 summary/hash 后才允许下一个 position。

任一 position 失败时，block 写入失败记录和终态 checkpoint，后续 position 不运行。不得自动 retry 或 resume。

## 4. 5% 精度的正式含义

### 4.1 目标

5% 精度定义为：主要 log-ratio 效应和需要保证绝对精度的边际 log 均值，其双侧 95% CI 在指数尺度上的目标相对半宽为 5%。使用：

```text
h = ln(1.05) = 0.048790164169432
```

pilot 对每个固定 anchor cell 同时估计：

1. 每个算法 primary endpoint 的 marginal log SD；
2. 每个预注册 contrast 的 block 内 paired log-difference SD。

为避免用 32 个 pilot blocks 的点估计低估方差，Gate 12R 使用各 SD 的单侧 90% 上置信界 `sigma_upper`，而不是直接使用样本 SD。对每个 family：

```text
raw_n = ceil((1.96 × sigma_upper / ln(1.05))²)
required_n = next_multiple_of_4(max(32, raw_n))
family_n = max(marginal requirements, paired requirements)
```

shared cohort 的 P1 与 P3 统一使用两者中更大的 block 数。`n` 始终表示每个 scenario/cohort 的独立 Williams-block Unity 进程数；由于每个算法在 block 内出现一次，它同时也是每个算法在该 campaign 中的观测数。

### 4.2 不再沿用 cap 148

旧 cap 148 属于 10% cold-process 历史修订，不适用于新 5% block-process 设计。新计划不在看到 fresh pilot 之前虚构一个硬 cap。

Gate 12R 必须输出：

- uncapped required `n`；
- 三个 cohort 的计划 block/process/sample 数；
- p50/p95 wall-time 投影；
- raw-byte 存储投影和启动门槛；
- 计算与存储可行性；
- 若不可行，需要缩小矩阵、增加资源或修改精度时的候选方案。

任何 cap、矩阵缩减或 5% 目标修改都必须在 Gate 13R 之前由用户另行批准，并形成前瞻性 versioned amendment。不得在看到 formal 结果后停止，也不得根据显著性、趋势或有利结果提前结束。

## 5. Gate 11R 目标矩阵

新 Gate 11R 以历史 53-scenario 因子结构作为设计参考，但必须写入新的 specification/generator/bundle identity，并在新根重新生成、重新校验。旧 `Research/FormalScenarios/v1` 不是活动执行输入。

计划目标为：

| 层级 | 数量 | 说明 |
|---|---:|---|
| 唯一 canonical scenario | 53 | 32 shared + 21 heterogeneous |
| scenario/cohort campaign condition | 74 | 32 shared + 21 per-agent hetero + 21 grouped-field hetero |
| eligible algorithm cell | 212 | 每个算法 53 个 cell |

计划新根：

```text
Research/FormalScenarios/Gate11R_5pct/v1/
```

Gate 11R 必须重新冻结：

- research questions、primary/secondary endpoints 和 analysis rows；
- 53 个 scenario 的参数水平、seed、canonical identity 和排除规则；
- 74 个 campaign condition 与 212 个 algorithm cell 的 cohort eligibility；
- Williams row、position/predecessor 语义；
- Playable Scene 映射；
- pilot anchor subset；
- 5% precision 公式和 formal stopping rule。

如果 Gate 11R 规格审阅决定改变 53/74/212，必须在生成任何 v1 新 bundle 前更新本计划与 machine-readable decision；不能静默沿用旧文件或在 pilot 后删减不利场景。

## 6. 每一个实验的 Playable Unity Scene 交付合同

### 6.1 覆盖定义

“每一个实验都有 Playable Unity Scene”按三个层级落实：

1. **53 个唯一 canonical scenario**：每个生成一个独立 `.unity` scene；
2. **74 个 campaign condition**：每个生成一个可选择 cohort 和运行模式的 launch profile；
3. **212 个 algorithm cell**：每个生成一个 algorithm preset，并在覆盖 manifest 中映射到 scene 和 campaign profile。

统计重复不会复制成成千上万个相同 `.unity` 文件。每个 formal repeat 通过以下完整身份映射到可 Play 入口：

```text
scenario scene
+ campaign/cohort profile
+ algorithm preset
+ Williams block ordinal
+ position/predecessor
+ run ID or replay trace ID
```

因此 53 个物理场景可以完整覆盖 74 个实验 campaign 和 212 个算法实验 cell，同时每一个 formal sample 都能被确定性重建。

### 6.2 目录和资产目标

计划目录：

```text
Assets/_Scenes/Research/Playable/Gate11R_5pct/v1/
    Scenarios/                 53 × .unity
    CampaignProfiles/          74 × research-only profile asset
    AlgorithmPresets/         212 × research-only preset asset
    Launcher/                  1 × experiment browser/launcher scene

Research/PlayableExperiments/Gate11R_5pct/v1/
    playable-scene-catalog.json
    campaign-profile-catalog.json
    algorithm-preset-catalog.json
    coverage-manifest.json
```

如果 Unity 序列化要求 profile 使用 `.asset`，其 GUID、文件 hash 和关联 JSON identity 必须同时进入 coverage manifest。所有资产均为 research-only，禁止修改原始 scene 或把研究组件挂到原始 scene。

### 6.3 Play Mode 功能

每个场景必须能在 Unity Editor 中直接进入 Play Mode，并具备：

- canonical grid、walkability、destination-entry cost 和 event timeline 可视化；
- agent start、goal 和 distinct-goal grouping；
- 算法选择和 campaign/cohort 锁定；
- Play、Pause、Single Step、Next Event、Restart 和 deterministic seek；
- path、expanded/repaired state、integration field 和 direction field 的分层显示；
- 已冻结默认箭头 `research-visual-direction-glyph-v1`；
- HUD 显示 scenario/campaign/algorithm/block/position/trace hash；
- 固定水印：`VISUALIZATION REPLAY — NOT A TIMING RUN`；
- 适合 OBS 的固定相机、无 UI/带 UI capture layout 和录制元数据导出。

### 6.4 场景与 benchmark 的隔离

- headless timing runner 不加载这些 Playable Scenes；
- Play Mode、渲染、HUD、箭头和 OBS 不进入 Gate 12R/13R timing；
- 可视化运行不得回写 formal workload result；
- formal campaign 完成后，另行运行 `EXCLUDED-VISUALIZATION-REPLAY`；
- replay 必须在结构字段上与选定 formal result exact-match，才可标记为该实验的正式补充可视化；
- 如果旧/正式日志不足以重建逐帧内部状态，视频只能声明为同 scenario/config 的确定性再运行，不能声称是原 timing 进程的逐帧录屏。

### 6.5 覆盖验收

Gate 11R 关闭前必须满足：

- 53/53 unique scenario 有可加载 `.unity` scene；
- 74/74 campaign condition 有 launch profile；
- 212/212 algorithm cell 有 preset；
- 每个 preset 的 scene、profile、scenario SHA-256 和 cohort eligibility 一致；
- 任一缺失、重复、GUID 漂移、hash 漂移或 scene→scenario 结构不一致都会阻断 Gate 12R。

## 7. 新 Gate 路线

### Gate 10R — process-reuse 公平合同与 runner 重建

目标：把“每 block 一个 Unity 进程”从 Gate 13 的后置迁移提升为整个实验体系的基础合同。

先冻结：

- block/process/sample 的所有权和独立性；
- 四算法/两算法 Williams rows；
- complete dynamic-cost boundary；
- metric、allocation、failure 和 budget 语义；
- reset、static-state、logger/thread 和 GC 清理边界；
- native working-set/private-memory 与 managed retained-memory 语义；
- retained managed-memory 使用前瞻冻结的双层门禁：每个样本仍为 128 MiB；完整 block 的上限为 `128 MiB × expectedSampleCount`，即两样本 256 MiB、四样本 512 MiB；
- working-set/private-memory 的完整 block growth 门槛各保持 512 MiB；
- position、predecessor、process-age、JIT、GC 和 cache 诊断；
- atomic checkpoint、fail-closed、no-auto-retry/no-resume；
- 新 provenance/schema/design IDs。

实现和测试必须是 additive research-only。不得覆盖 v1/v2 命令或证据。

Gate 10R 最低验证：

- PowerShell AST/static/unit；
- Unity 编译；
- native/CIM telemetry probe；
- 4-alg positive block；
- 2-alg positive block；
- injected-failure negative block；
- 同一 plan 的两个独立进程重复；
- fresh cold structural references；
- Gate 1–9 retained regression；
- validation-only final audit。

Gate 10R attempt 4 已完成并通过；attempts 1–3 保留为不可恢复、不可合并的失败证据。活动下游只能引用 attempt 4 和设计 `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`。

### Gate 11R — 新矩阵、预注册与 Playable Scene bundle

输入：通过 Gate 10R 的新设计和 runner hash。

输出：

- 新 `FormalScenarios/Gate11R_5pct/v1` bundle；
- 新 matrix/catalog/preregistration/manifest；
- 53/74/212 Playable coverage；
- scene generator、scene verifier 和 create-new 输出规则；
- 结构/场景/scene 双向 hash 与 GUID provenance；
- 选定的 Gate 12R pilot anchors。

Gate 11R attempt 2 已完成并通过，只生成和验证输入及场景，没有运行 timing pilot。活动 bundle manifest SHA-256 为 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`。

### Gate 12R — fresh 5% process-reuse pilot

计划固定 anchor：

Shared scenarios：

1. `core-r01-s1-shared`；
2. `core-r07-s2-shared`；
3. `grid-scale-g256-shared`；
4. `agent-scale-a512-shared`；
5. `dynamic-footprint-f225-shared`；
6. `reachability-c8-strict-shared`。

Heterogeneous scenarios（各自分别运行 per-agent 与 grouped-field cohort）：

1. `core-r01-s1-hetero`；
2. `core-r07-s2-hetero`；
3. `goal-count-g32-hetero`。

计划 pilot payload：

| 类型 | Unity 进程 | workload 样本 | 是否进入方差估计 |
|---|---:|---:|---|
| telemetry method probe | 1 | 0 | 否 |
| excluded warm-up complete cycles | 8 | 24 | 否 |
| fresh cold structural controls | 36 | 36 | 否 |
| 12 campaigns × 32 measured blocks | 384 | 1,152 | 是 |
| 合计 | 429 | 1,212 | 仅 384/1,152 measured |

pre-pilot verification fixture 的 Unity 进程另计且全部排除。pilot root 只允许创建一次，必须标记 `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`。

Gate 12R 输出：

- marginal、paired、intraclass correlation；
- position/predecessor/process-age/JIT/GC/memory 诊断；
- one-sided 90% `sigma_upper`；
- 三个 cohort 的 uncapped 5% `required_n`；
- block/process/sample、wall-time、存储投影；
- exact structural comparison；
- readiness checkpoint。

任一 hard gate 失败就保存原子 checkpoint 和部分证据后停止；已经启动 measured block 的失败 attempt 不 resume、不补齐、不与后续 attempt 合并。Gate 12R attempts 1–3 均按此规则冻结。用户随后前瞻批准修正 retained managed-memory 的聚合层级：128 MiB 仍是逐样本硬门禁，block 门禁按其冻结样本数线性缩放；这不是依据结果放宽单样本阈值。

Gate 12R attempt 4 已通过：

- 8 个 excluded warm-up blocks、36 个 fresh cold structural controls、384 个 measured blocks 和 1,152 个 measured samples 全部完成；
- 合计 429 个 Unity 进程 / 1,212 个 workload samples，自动 retry/resume 均为 0；
- structural exact comparison 为 1,152/1,152，mismatch 0；
- 384/384 measured blocks 的 sample-managed、scaled block-managed、working-set 和 private-memory 门禁全部通过；
- 最大单样本 retained managed growth 为 101.258 MiB；最大 block retained managed growth 为 100.367 MiB；最大 block working-set/private-memory growth 为 466.492/501.914 MiB；
- post-pilot readiness audit 为 951/951 checks；Gate 13R formal root 不存在。

无 cap 5% 候选结果为：

| cohort | 每个 campaign 的 `n_formal` blocks | campaign 数 | formal block processes | 每 block 样本 | formal samples |
|---|---:|---:|---:|---:|---:|
| four-algorithm shared-goal | 548 | 32 | 17,536 | 4 | 70,144 |
| per-agent heterogeneous-goal | 768 | 21 | 16,128 | 2 | 32,256 |
| grouped-field heterogeneous-goal | 400 | 21 | 8,400 | 2 | 16,800 |
| 合计 | — | 74 | 42,064 | — | 119,200 |

串行执行投影合计为 p50 244.78 h、p95 317.07 h（13.21 d）。带 1.5× p95 safety 的原始输出投影为 166,572,888,336 bytes（155.13 GiB）；加 20 GiB reserve 后正式启动门槛为 188,047,724,816 bytes（175.13 GiB）。pilot 结束时可用空间 292,135,882,752 bytes（272.07 GiB），因此当前投影可行，但正式启动时必须重新读取原始 free bytes。

后续作者决定为 Gate 13R 正式 campaign 设置 **36 小时端到端硬墙钟上限**，替代尚未落地的 48 小时上限。上述 5% config 的 317.07 h 投影因此不再满足启动条件；config/schedule/readiness 保留为未执行的历史 readiness 证据，不得就地修改或用旧 authorization prompt 启动。新的活动停止点是精度/并发 redesign selection。只读候选重算、旧 Gate 13 对照及推荐的 10% + 4 隔离 Editor lanes 方案见 `Research/Gate13R_36h_Redesign_Discussion.md`；36 小时决定本身见 `Research/Gate13R_36h_WallClock_Constraint.v1.json`。任何候选都必须先经过新的并发 pilot 和 versioned readiness，才能生成新正式 config 并申请正式授权。

### Gate 13R — 非执行准备与正式 block-process campaign

Gate 12R 成功且用户接受资源投影后，独立非执行准备已经完成：

- 生成绑定新 matrix、runner、pilot、`n_formal`、Unity 和环境的正式 config；
- 按 cohort 为全部 74 campaigns 分配同 family block 数；
- 生成全量 Williams schedules、run IDs、block IDs 和 output projections；
- raw-byte storage preflight；
- execution receipt validator、atomic checkpoint 和 no-auto-retry/no-resume 测试；
- formal root 在单独正式授权前必须不存在。

非执行准备的终态为 `GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED`。51/51 unit、Unity compile、32/32 schedule validation、预期负向 receipt guard、byte-identical deterministic regeneration 和 47/47 final audit 全部通过。冻结身份为：config `af5a164cdabeeff08cd6cd00b21ecd732fcbdc7f51be3454f99aaf65b2ef5109`、schedule `dc460db08f501ef39869de29602cc0caf15106a264f930b55eb1875336c91aa6`、provenance `c1f8d4b4a8216b2e7f2dbdad7d49decbb77da38087f4c8c91a1366cd4d2963b8`。完整恢复点见 `Research/Gate13R_NonExecuting_Preparation_Checkpoint.md`。

计划 formal root：

```text
Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1
```

原 5% 正式执行 prompt 已因 36 小时硬上限而失效，不得使用。未来正式计时仍只运行 headless block runner，不加载 Playable Scene，不启动 OBS；但在此之前必须先获得 redesign/pilot 授权、完成新的并发证据和 readiness，再单独申请正式 campaign 授权。

### Gate 15R — block-aware 统计分析

主要模型以 block 为聚类单位：

- block 内 log-difference paired contrasts；
- mixed model / cluster-robust sensitivity analysis；
- algorithm、scenario factor、position、predecessor 和必要交互；
- seed/scenario 与 block random effects（可估计时）；
- P1–P4 Holm correction；
- raw n、均值、中位数、nearest-rank p95、SD、SE、CI、绝对值和 ratio；
- 所有 failure、NoPath、budget overrun 留在分母和分类表；
- 不混合 old cold-process、old process-reuse pilot、warm-up、cold controls、partial blocks 或 visualization replay。

### Gate 15V-R — 可视化重放与 OBS

Gate 15R 结果表冻结后，不再创建场景，而是使用 Gate 11R 已生成的完整 Playable bundle：

- 为每个 212 algorithm cell 至少生成一个可验证 replay trace；
- 每个实验均可录制；正式补充视频可按预注册覆盖规则选取主视频，剩余实验保留可 Play scene/trace；
- 每个视频生成 recording manifest，绑定 scene、profile、preset、trace、formal result summary、OBS profile 和文件 hash；
- 视频不作为 timing、显著性或帧时间证据。

### Gate 16R — 论文与复现包

复现包必须同时包含：

- Gate 10R–13R specification/config/provenance；
- formal raw/derived manifests；
- analysis scripts/tables/figures；
- 53 Playable Scenes、74 profiles、212 presets 的 coverage manifest；
- replay trace 和 OBS recording manifests；
- 历史失败谱系的排除说明，但不混入新数据表。

## 8. 输出根与防混淆规则

新谱系只使用新根：

```text
Research/Verification/Gate10R_ProcessReuse_5pct/v1
Research/Verification/Gate10R_ProcessReuse_5pct/v2
Research/Verification/Gate10R_ProcessReuse_5pct/v3
Research/FormalScenarios/Gate11R_5pct/v1
Research/PlayableExperiments/Gate11R_5pct/v1
Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1
Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1
Assets/_Scenes/Research/Playable/Gate11R_5pct/v1
```

以下历史根永久不作为新谱系的 writable target 或统计输入：

```text
Research/FormalRuns/Gate13/v1
Research/PilotRuns/Gate13_ProcessReuse/v1
Research/PilotRuns/Gate13_ProcessReuse/v2
Research/FormalScenarios/v1
Research/PilotRuns/Gate12/v1
```

新分析器必须显式拒绝旧 design ID、旧 root、旧 config 和混合 execution-design 表。

## 9. 环境、存储与运行前门禁

每个 pilot/formal 运行前记录并匹配：

- CPU 型号、logical processors、RAM；
- Windows edition/build；
- Unity path/version/SHA-256；
- AC power、active power scheme；
- thermal warm-up 和 background-process policy；
- implementation/spec/matrix/preregistration/config hashes；
- 输出根解析后的绝对路径；
- 可用空间与按原始字节投影计算的安全余量；
- 当前无其他 Unity、项目 lock 或同根 runner。

正式启动存储门槛在 Gate 12R 后按实际 raw bytes per block 计算，不从 cold-process 配置复制。

## 10. 保留与完整性规则

- 不删除、解封、覆盖、补齐或继续分析历史 cold/process-reuse roots；
- 不修改原始脚本和原始 scenes；
- Gate 1–9 规格与实现保持活动 prerequisite，但必须在 Gate 10R 做 retained regression；
- 旧 Gate 10–13 文档作为 historical provenance 保留，不就地改写成新设计；
- 新版本只通过新文件、新 design ID 和新 output roots 建立；
- 每个 Gate 在 specification/test design 通过后才能实现；
- pilot/formal 失败均 fail closed，无自动 retry/resume；
- Playable/OBS 路径与 timing 路径物理和语义隔离。

## 11. 当前停止点与下一授权

当前终态为：

```text
GATE13R-36H-REDESIGN-SELECTION-PENDING-FORMAL-CAMPAIGN-NOT-AUTHORIZED
```

Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R pilot attempt 4 和已封存的 Gate 13R non-executing preparation 是唯一活动上游。Gate 13R 通过证据见 `Research/Gate13R_NonExecuting_Readiness_Checkpoint.v1.json`、`Research/Gate13R_NonExecuting_Preparation_Evidence_Manifest.v1.json` 和 `Research/Gate13R_NonExecuting_Preparation_Checkpoint.md`。当前没有授权：

- Gate 13R 正式 execution receipt、formal root 或 timing campaign；
- Gate 15R 正式统计分析；
- Gate 15V-R trace 生成、Play Mode 录制或 OBS 工作。

下一项作者决定是选择满足 36 小时硬上限的前瞻性精度/并发方案。推荐但尚未冻结的是完整 74-campaign、10% per-campaign 相对半宽、4 个隔离 Unity Editor lanes，并要求新的 readiness p95 不超过 27 小时。该选择完成后仍须单独授权并发 pilot；pilot/readiness 通过后才会生成新的 formal config 和正式授权提示词。现有 `Research/Gate13R_Formal_Campaign_Authorization_Prompt.md` 只绑定旧 5%/317.07 h config，不得使用。

## 12. Gate 10R→13R 关闭条件总表

| Gate | 关闭条件 | 当前状态 | 下一 Gate 是否自动开始 |
|---|---|---|---|
| 10R | 新规格/测试、compile、positive/negative block、telemetry、repeatability、cold structural、Gate1–9 regression 全通过 | attempt 4 已通过 | 否 |
| 11R | 新 53/74/212 bundle 与 53 scenes/74 profiles/212 presets 全覆盖并验证 | attempt 2 已通过 | 否 |
| 12R | fresh pilot 成功；5% uncapped n、相关性和资源投影完成；无 hard error | attempt 4 与 readiness 951/951 已通过 | 否 |
| 13R preparation | formal config/receipt/preflight/checkpoint 测试通过，formal root 仍不存在 | 已通过：51 unit、compile、32 schedule、negative receipt guard、47 final audit | 否 |
| 13R campaign | 单独授权后完成全部 blocks，hash/manifest/checkpoint/final audit 通过 | 未授权 | 否 |
| 15R | 预注册分析和派生表冻结 | 未开始 | 否 |
| 15V-R | 所有实验具备可 Play/replay 覆盖，OBS 主视频与 manifests 完成 | 未开始 | 否 |

任何一行失败都保存 versioned 证据并停止，不跳过、不自动续跑。
