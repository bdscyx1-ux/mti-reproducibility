# Gate 13 非执行准备实现规格 v1

规格 ID：`gate13-nonexecuting-preparation-specification-v1`  
日期：2026-10-06  
状态：冻结后实现；只授权非执行准备，不授权正式 campaign  
上位修订：`Research/Gate13_Readiness_Amendment.v1.json`

## 1. 本阶段授权边界

本阶段只允许实现并验证 Gate 13 的独立研究专用 orchestration/config 层，包括：

1. 支持每算法每 cell 最多 148 次的正式调度配置；
2. 74 个 scenario/cohort campaign、15,056 个独立 Unity 样本进程的确定性展开；
3. 正式启动前、正式输出根目录创建前的原始字节存储硬门槛；
4. formal campaign 的 create-new、独立进程、Williams 平衡、provenance、监控与原子检查点机制；
5. 静态、单元、回归和 validation-only 检查。

本阶段明确禁止：

- 创建 `Research/FormalRuns/Gate13/v1`；
- 创建任何 `formalCampaign = true` 的结果；
- 启动 Gate 13 timing sample 或 timing campaign；
- 创建 Gate 13 正式执行授权 receipt；
- 修改 Gate 12 成功 `v1`、Gate 11 retained bundle、原始脚本或原始场景；
- 修改 Gate 10 runner 以放宽其 `Blocks <= 100` 合同。

## 2. 冻结输入与版本关系

`Gate13_Readiness_Amendment.v1.json` 保持为当时的不可变决策记录。其 `gate13ImplementationAuthorized = false` 与 implementation pending 字段描述 amendment 冻结时的状态；本次用户授权由新的 preparation manifest/checkpoint 记录，不回写或改写历史 amendment。

实现必须逐字节绑定并验证至少以下输入：

- Gate 13 amendment；
- Gate 11 `bundle-manifest.json`、`formal-scenario-matrix.json` 与 `preregistered-analysis.json`；
- Gate 12 candidate sample sizes、budget feasibility、final audit 与成功 pilot manifest；
- Gate 10 fairness specification、Gate 10 campaign runner 与共享 workload runner；
- Unity executable 的路径、产品版本与 SHA-256；
- 原始项目 24 项 baseline。

Gate 10 fairness specification 必须保持 Gate 12 冻结哈希 `42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd`。其中历史 8% 规则仅保留 provenance；Gate 13 当前不设置项目自定义 Codex 用量 ceiling、固定余量或百分比停工线。

## 3. 正式矩阵与 cap-148 调度

矩阵不变：53 个场景、212 个 eligibility cells、74 个 scenario/cohort campaigns。

| cohort | 场景数 | 算法顺序 | blocks/场景 | 完整 Williams cycles | Unity 样本数 |
|---|---:|---|---:|---:|---:|
| `four-algorithm-shared-goal-v1` | 32 | `A*-R,D*L,C-FF,IDFF` | 52 | 13 | 6,656 |
| `per-agent-heterogeneous-goal-v1` | 21 | `A*-R,D*L` | 148 | 74 | 6,216 |
| `grouped-field-heterogeneous-goal-v1` | 21 | `C-FF,IDFF` | 52 | 26 | 2,184 |

总计为 74 campaigns、15,056 个独立 Unity 进程。P3 的 formula required n 为 48，但 shared cohort 的正式 scheduled n 为 52，以与 P1 共用完整四算法 Williams cycle；不得把该 harmonization 当成精度公式变化。

campaign 顺序固定为：按 Gate 11 matrix 中 `scenarios` 的原始顺序遍历，再按全局 cohort 顺序 `shared -> per-agent heterogeneous -> grouped-field heterogeneous` 选择该场景声明的 cohort。每个 campaign 的 ID、目录、run ID 和 Williams 序列均由此规则确定，配置生成必须字节确定。

## 4. 独立实现与执行入口

新层使用以下独立文件：

- `Research/Gate13FormalPreparation.psm1`：纯验证、调度、配置、授权、存储和监控函数；
- `Research/New-Gate13FormalCampaignConfig.ps1`：确定性生成正式配置；
- `Research/Run-Gate13FormalScenarioCampaign.ps1`：单个 scenario/cohort campaign runner，cap 为 148；
- `Research/Run-Gate13FormalCampaign.ps1`：74-campaign 顶层 orchestrator；
- `Research/Gate13_Formal_Campaign_Config.v1.json`：非授权、非执行配置。

新 runner 可以调用既有 `Run-PlanningWorkload.ps1`，但不得修改它。每个 sample 必须通过新的 PowerShell child process 调用 workload runner，从而继续满足“一 sample 一 Unity process”。

所有执行入口必须显式选择 `-ValidationOnly` 或 `-Execute`。`-ValidationOnly` 不得创建 formal root、不得创建 campaign 目录、不得调用 Unity。`-Execute` 必须同时满足：

1. 提供独立的、用户另行授权后才允许创建的 Gate 13 execution receipt；
2. receipt 与最终 config、amendment、输出根路径的 SHA/identity 精确绑定；
3. config 和所有冻结输入通过逐字节验证；
4. 当前无 Unity process、无 `Temp/UnityLockfile`；
5. launch preflight 通过；
6. formal root 尚不存在。

任一条件不满足时必须 fail closed。

## 5. 正式执行授权 receipt 合同

本阶段只实现 validator，不创建 receipt。未来 receipt 至少必须包含：

- `schemaVersion = 1`；
- `authorizationKind = gate13-formal-execution-authorization-v1`；
- 非空、文件安全的 `authorizationId`；
- `gate13ExecutionAuthorized = true`；
- `formalCampaignStartAllowed = true`；
- 最终 config SHA-256；
- amendment SHA-256；
- `outputRootRelativePath = Research/FormalRuns/Gate13/v1`；
- 非空用户授权引用和授权时间。

项目用量策略、preparation 授权、配置文件自身或当前磁盘空间均不得替代该 receipt。

## 6. 原始字节存储 preflight

冻结值：

- p95 projected output：`52,942,494,009 bytes`；
- 最低 post-campaign reserve：`21,474,836,480 bytes`；
- 最低 launch free bytes：`74,417,330,489 bytes`。

正式执行时必须按以下顺序执行：

1. 验证 execution receipt；
2. 验证 config、冻结输入、Unity identity、无 Unity/lock 和 formal root 不存在；
3. 对 formal root 所在 volume 读取当前 `AvailableFreeSpace` 原始字节；
4. 以 `freeBytes >= 74,417,330,489` 判定；
5. 通过后才允许创建 formal root；失败时不得产生任何正式样本或正式根目录。

GiB 只可用于显示，不得参与判定。`minimum - 1` 必须失败，`minimum` 必须通过。validation-only 的当前存储快照只能是 advisory，不构成启动授权。

## 7. 环境、监控和失败语义

正式入口继续执行 Gate 12 的客观环境检查：AC online、High performance power scheme、至少 4 GiB 可用物理内存、5 次一秒间隔 CPU 负载均值不超过 50%、无 Unity process、无 Unity lockfile。温度不可用时记录 unavailable，继续依赖受控环境和 Williams 平衡。

每个 scenario/cohort campaign 由独立 PowerShell process 运行。监控规则：30 秒检查一次；连续 3 次无输出增长只产生 advisory；每 campaign 硬超时 10,800 秒；仅硬超时允许终止 owned process tree；不得自动 retry。失败或超时后保留已有部分输出并停止顶层 orchestrator。

正式根目录、每个 campaign 目录和旁路 summary 都采用 create-new/no-overwrite。任何重试必须在后续明确决策中使用新版本或新 attempt identity；本实现不自动恢复、不自动覆盖。

## 8. provenance 与正式 manifest

单 campaign manifest 必须记录：

- `formalCampaign = true`（仅未来已授权执行路径可产生）；
- config、amendment、execution receipt、scenario source 的 SHA-256；
- cohort、canonical algorithm order、blocks、sample count、完整 Williams cycle 数；
- position 与 ordered-predecessor balance；
- Unity、fairness protocol、workload specification 和每算法 specification/implementation identity；
- 每个 sample 的 run ID、相对目录、child manifest/result/operations hashes 与完成状态。

顶层 checkpoint 必须通过同目录临时文件加原子 replace/move 写入，并在：formal root 创建后、每个 campaign 前、每个 campaign 后、完成或失败时更新。checkpoint 至少记录 config/authorization hashes、状态、已完成 campaign、当前 campaign、累计样本数和错误；它是恢复证据，不授权自动 resume 或 retry。

## 9. 非执行完成条件

本阶段只有在以下条件全部满足时才完成：

1. preparation 规格与测试设计冻结；
2. config 确定性生成，74 campaigns/15,056 samples 与 amendment 精确一致；
3. cap-148 runner 与 orchestrator 均通过 PowerShell parser；
4. 存储边界、Williams、config tamper、authorization fail-closed、路径 containment 和 create-new 负向测试通过；
5. Gate 12 63 项分析回归、Gate 13 amendment audit、Gate 12 validation-only preflight 通过；
6. Gate 11 retained bundle、Gate 12 成功 `v1` 和原始 baseline 均未改变；
7. `Research/FormalRuns/Gate13/v1` 不存在；
8. 无 Unity process、无 Unity lockfile；
9. 写入 versioned preparation manifest 与精确 checkpoint。

通过后必须停止。只有新的、明确的 Gate 13 正式执行授权才允许创建 execution receipt、formal root 或启动第一个 timing sample。
