# Gate 12 Pilot、噪声与候选样本量规格

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T19:57:56+08:00
- Verification Status: SPECIFICATION-FROZEN
- Version Label: gate12_pilot_spec_v1

规格 ID：`gate12-isolated-pilot-v1`  
状态：实现前冻结；任何实质修改均须创建新版本，不得就地改写  
机器可读计划：`Research/Gate12_Pilot_Plan.v1.json`

## 1. 授权边界与停止点

Gate 12 只授权一个与正式结果物理隔离的非正式 pilot，用于环境检查、噪声估计、预算/运行成本评估和 Gate 11 精度公式计算。Gate 12 不授权 Gate 13，不允许把 pilot 样本并入正式分析，也不允许根据 pilot 的有利结果、显著性或趋势启动或提前停止正式 campaign。

以下内容在本 Gate 中保持只读：

- `Research/FormalScenarios/v1/` 的 57 个 retained-bundle 文件；
- Gate 10 的公平性规格、workload 规格、runner 和已保留夹具；
- 所有原始脚本和原始场景；
- Gate 11 的规格、测试设计、count erratum、矩阵、预注册和 manifest。

Gate 12 允许新增独立的规格、验证脚本、pilot orchestration、分析器、pilot 输出和检查点。任何必须改变 Gate 10/11 冻结合同或场景内容的问题都终止 Gate 12，并要求版本化修订。

## 2. 冻结输入

Gate 12 在每次 preflight、pilot 结束和最终审计时验证以下身份：

| 输入 | SHA-256 |
|---|---|
| Gate 11 bundle manifest | `ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e` |
| Gate 11 ordered aggregate | `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88` |
| Gate 11 matrix | `404df63d38bccd66bb665446e0f2cbf3e5f8c7293f543b3213bde4206435fe9f` |
| Gate 11 preregistration | `7e947885c38fcf9307fd9202585dda3b2b5d11334f495428760009a2aa202b5b` |
| Gate 10 fairness specification | `42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd` |
| Gate 4 workload specification | `2af12d33c4a010b14511f86d11d2f45634cac794b6763ea1cc36e8f1940a8ea1` |
| Gate 10 fair-campaign runner | `176f82fed18beee2fc7e2c8cb37ce988f7c7f4740cdeec3c5510b677843615c3` |
| Gate 10 workload runner | `c75bed92db9b6df5d1123198acb5358fd58297aa770e78acd0c4530cf9fbbbfb` |
| Unity executable | `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf` |

完整路径和实现层哈希由机器可读计划固定。bundle 内每个 artifact 的字节数和 SHA-256 都按 Gate 11 manifest 重新核对，不能只检查顶层 manifest。

## 3. Pilot subset

Pilot 使用 balanced core 的结构行 `1, 2, 7, 8`、仅使用 materialized seed replication `s1`，并对每一行使用配对的 shared 与 heterogeneous 场景。精确的八个 scenario ID、路径、source hash 和 fingerprint 均写入机器可读计划。

选择理由：

- 同时覆盖 `64×64` 与 `128×128`；
- 同时覆盖 4/8 邻接、uniform/weighted terrain、0.10/0.25 obstacle density；
- 同时覆盖 16/128 agents 与 9/81 changed cells；
- 同时覆盖 shared、per-agent heterogeneous 和 grouped-field heterogeneous 比较；
- 保留 `s2` 完整 materialized seed，不让 pilot 消耗或污染未来正式证据的第二 seed 身份。

这是噪声 pilot，而不是因素效应估计；四行子集中的 grid/connectivity 别名不用于任何因果或 scaling 结论。

## 4. 重复、顺序与进程隔离

每个 `scenario × algorithm` 测量 cell 固定为 8 个独立 Unity 进程样本：

- shared cohort：每个场景 `Blocks = 8`，四算法，每算法 8 次，共 32 进程；
- 每个 heterogeneous cohort：每个场景 `Blocks = 8`，两算法，每算法 8 次，共 16 进程；
- 四个场景对、三个 cohort，共 12 个测量 campaign、256 个测量进程；
- 每一个 workload 样本由新的 Unity 进程产生，不在同一 Unity 进程中连续测量两个算法；
- shared cohort 包含两个完整四算法 Williams cycles；每个两算法 cohort 包含四个完整 Williams cycles；
- campaign 级顺序按机器可读计划的 12 行 interleaved row/cohort 顺序固定，不能根据中间 timing 调序。

另运行一个排除于所有统计和样本量计算的热状态 warm-up：`core-r01-s1-shared`、shared cohort、`Blocks = 4`，共 16 个独立 Unity 进程。warm-up 后静置 60 秒再开始测量。总计最多 272 个 Unity 进程。

## 5. 环境、电源与热状态 preflight

Preflight 必须记录并验证：

- CPU 型号、物理/逻辑核数、启动前负载样本；
- 已安装/可用物理内存；
- Windows edition、version、build；
- Unity 路径、product version、字节数和 SHA-256；
- AC 在线状态、电池状态（若存在）和 active power scheme GUID/name；
- 输出盘总量、可用空间；
- Unity 进程与 `Temp/UnityLockfile`；
- CPU time 和 working set 最大的 20 个后台进程快照；
- 可用时的 ACPI thermal-zone 温度；不可用必须显式记录 `unavailable`，不能伪造温度；
- Gate 10/11 和 Gate 12 冻结文件的 hash；
- campaign 开始、warm-up 前后、每个测量 campaign、结束时的 UTC/local timestamp。

硬 preflight 条件：AC 在线；电源计划固定为 GUID `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`（High performance）；可用物理内存至少 4 GiB；H: 可用空间至少 10 GiB；5 次一秒间隔 CPU load 平均值不高于 50%；没有 Unity 进程；没有 Unity lock；所有冻结 hash 正确。

Gate 12 不自动关闭浏览器、构建工具或任何用户进程。它用客观 CPU 阈值和后台进程快照识别重负载；不满足时在产生 timing 样本前停止。warm-up 后和结束时电源计划/AC 状态必须与开始一致。传感器不可用本身不是失败，因为热控制由完整 warm-up、60 秒稳定期、campaign 交错和 Williams 顺序共同承担。

## 6. 监控、失败与检查点

- 监控间隔：30 秒；连续 3 次没有输出增长记为 `OUTPUT_STALL` advisory，但不自动重试或重排。
- 单个 campaign hard timeout：1800 秒；只有 hard timeout 可以终止对应进程树。
- crash、编译错误、hash mismatch、manifest 不完整、进程中断、power-scheme 变化和 preflight 失败都是技术无效；停止后保留证据，不自动重试。
- `NoPath`、budget exceeded、invalid request 和 planner failure 是算法结果，不是技术无效，不得删除或替换。
- 每完成一个 campaign，原子式写入新的 pilot checkpoint/manifest 内容并记录所有子 manifest/result hash。既有输出不得覆盖。
- 若需要替换技术无效 pilot，必须由后续明确操作使用新 ordinal 和完整 Williams cycle；本次脚本不自行替换。

## 7. 噪声估计

Primary endpoint 固定为 `dynamicHandlingMillisecondsPerScheduledEvent`。每个值必须为有限且严格正数；零值表示 instrumentation 无效，不能加 epsilon、截断或替换。

对每个预注册 family：

1. 按 `comparisonCohortId × scenarioId × algorithmId` 建立 cell；
2. 只使用 8 个 measured 样本，排除 warm-up；
3. 对 endpoint 取自然对数；
4. 用 Bessel 修正的样本标准差计算每个 cell 的 `s_log`；
5. `sigma_log` 是该 family 所有合法 cell 的最大 `s_log`；
6. 保留 governing cell、每个 cell 的 n/mean/median/p95/sample SD/min/max 和原始结果 locator；
7. timing/allocations 的所有 outlier 均保留，不进行性能驱动删除。

Family 映射严格为：P1 shared A*-R/D*L；P2 heterogeneous per-agent A*-R/D*L；P3 shared C-FF/IDFF；P4 heterogeneous grouped-field C-FF/IDFF。

另外对 initialization、initial planning、total-per-agent、dynamic allocation、processed work、success 和 budget-overrun 指标生成描述性噪声/范围表；这些描述不能替代 primary precision 公式。

## 8. 候选正式样本量

每个 family 独立应用 Gate 11 公式：

```text
n_raw = ceil((1.96 × sigma_log / ln(1.05))²)
required_n_formal = next multiple of 4 at or above max(30, n_raw)
candidate_n_formal = min(100, required_n_formal)
```

若 `required_n_formal <= 100`，候选值可作为该 family 每个正式 cell 的固定次数，仍须 Gate 13 单独授权。若 `required_n_formal > 100`，报告 `candidate_n_formal = 100` 只是 cap 展示值，同时必须给出未截断需求并将 Gate 13 标记为 `blocked-versioned-amendment-required`；不得假装 100 已满足精度目标。

最小 30 经四舍入后实际最小候选为 32。不得在 Gate 13 中根据显著性、趋势、效果方向或中间方差提前停止。

## 9. 预算与运行可行性

分析器根据 measured campaign 的外层 wall time 和字节量，报告每进程 median/p95 wall seconds、median/p95 bytes，并按 family-specific 候选 n 投影完整 212-entry campaign：

```text
processes = 32×2×n_P1 + 21×2×n_P2 + 32×2×n_P3 + 21×2×n_P4
```

技术可行性边界为：p95 投影不超过 168 小时；投影输出写入后 H: 至少保留 20 GiB；没有 campaign hard timeout 或技术无效。超过任一边界时 Gate 13 自动 readiness 为 blocked。用户的时间/费用预算当前为 `not-set`，因此即使技术可行也不能视为 Gate 13 已获授权。

Budget-overrun 和算法失败率必须按算法、场景和 family 报告。出现算法 budget overrun 不得删样本或静默放宽预算；它触发 Gate 13 前的显式决策/版本化修订记录。

## 10. 输出与完成条件

所有 pilot 输出只写入 `Research/PilotRuns/Gate12/v1/`，create-new only。至少包含：

- 冻结计划副本身份、preflight、warm-up manifest、12 个 measured campaign；
- pilot manifest/checkpoint、环境开始/结束快照、监控事件；
- 所有 workload 原始结果及 hash；
- `noise-analysis.json`、`candidate-sample-sizes.json`、`budget-feasibility.json`；
- 人类可读验证报告和 Gate 12 checkpoint；
- 对 retained bundle 的运行前/运行后 hash 快照。

Gate 12 仅在以下条件全部满足时完成：规格/测试设计先于生产实现并通过审计；256 个 measured 样本严格完整；warm-up 被排除；四个 family 都有完整 cell；公式测试通过；预算投影完成；bundle 和 baseline 未改变；所有 PowerShell/JSON 可解析；没有 Unity process/lock 遗留；Gate 13 没有被启动。
