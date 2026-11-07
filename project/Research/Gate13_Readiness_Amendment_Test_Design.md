# Gate 13 Readiness 版本化修订测试设计

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T23:09:58+08:00
- Administrative Update: 2026-10-05T23:45:19+08:00
- Verification Status: SPECIFICATION-FROZEN
- Version Label: gate13_readiness_amendment_test_design_v1

测试设计 ID：`gate13-readiness-amendment-tests-v1`  
绑定规格：`gate13-readiness-amendment-v1`  
状态：非执行型修订审计前冻结

## 1. 授权边界测试

机器可读修订必须同时满足：

- `specificationAndTestDesignOnly = true`；
- `unityInvocationAllowed = false`；
- `formalTimingSamplesAllowed = false`；
- `formalOutputDirectoryCreationAllowed = false`；
- `gate13ExecutionAuthorized = false`；
- `formalCampaignStartAllowed = false`；
- `userUsagePolicyStatus = no-user-imposed-codex-usage-limit` 不能被解释为执行授权；
- original scripts/scenes、Gate 11 bundle 和 Gate 12 successful pilot 的可修改标志全部为 false。

审计脚本不得调用 Unity、修改电源计划、终止进程、创建 formal output root 或修改冻结输入。

## 2. 冻结输入和保留证据测试

审计必须：

1. 验证规格、测试设计和机器可读修订存在且 UTF-8/JSON 可解析；
2. 验证 Gate 11 manifest、matrix、preregistered analysis、Gate 12 candidate/budget/final audit 和 Gate 10 runner 的 SHA-256；
3. 深度遍历 Gate 11 manifest 的 56 个 artifact，验证每个 hash/byte count 和 ordered aggregate；
4. 验证 Gate 11 仍为 53 scenarios、212 eligibility cells；
5. 验证原始 baseline 24/24；
6. 验证 Gate 12 final audit 仍为 passed，且 successful pilot 的 formal-start flag 仍为 false。

任一 mismatch 必须使修订审计失败，不得自动更新期望 hash。

## 3. 10% 精度公式测试

审计必须直接从 Gate 12 `candidate-sample-sizes.json` 读取四个 `sigma_log`，不能信任修订 JSON 中的派生整数，并独立应用：

```text
n_raw = ceil((1.96 × sigma_log / ln(1.10))²)
required_n_formal = next multiple of 4 at or above max(30, n_raw)
```

预期固定向量：

| Family | `n_raw` | `required_n_formal` |
|---|---:|---:|
| P1 | 49 | 52 |
| P2 | 148 | 148 |
| P3 | 46 | 48 |
| P4 | 50 | 52 |

另以合成输入检查：零方差得到 `n_raw=0`、cycle-aligned minimum 为 32；NaN、Infinity、负数和非数值目标必须 fail closed。不得使用 `ln(1.05)`、banker's rounding 或先 cap 后对齐。

## 4. cap 与 Williams 调度测试

必须验证：

- cap 精确为 148；
- 每个 required/scheduled n 都是正整数且 scheduled 不超过 148；
- P1/P2/P4 的 scheduled n 等于 required n；
- P3 的 required n 为 48、scheduled n 为 52，并具有固定的 shared-cohort harmonization reason；
- shared cohort 32 scenarios、4 algorithms、52 blocks、每场景 13 个完整 Williams cycles、6,656 processes；
- per-agent cohort 21 scenarios、2 algorithms、148 blocks、74 cycles、6,216 processes；
- grouped cohort 21 scenarios、2 algorithms、52 blocks、26 cycles、2,184 processes；
- 74 campaigns、15,056 processes 总数精确；
- 不允许用 14,800 的 family-only 简化投影替代可执行的 full-cohort schedule；
- 不允许创建 shared 两算法子 cohort 或把最后一个四算法 Williams cycle 拆开。

## 5. 矩阵不变测试

从 Gate 11 matrix 独立分组并验证：

- `four-algorithm-shared-goal-v1`：32 scenarios、128 eligibility cells、算法集合恰为 `A*-R,D*L,C-FF,IDFF`；
- `per-agent-heterogeneous-goal-v1`：21 scenarios、42 cells、算法集合恰为 `A*-R,D*L`；
- `grouped-field-heterogeneous-goal-v1`：21 scenarios、42 cells、算法集合恰为 `C-FF,IDFF`；
- 总数仍为 53 unique scenarios 和 212 eligibility cells；
- amendment 的 `matrixOrScenarioChange`、`analysisRowChange`、`endpointChange`、`multiplicityChange`、`failureOrOutlierPolicyChange` 全部为 false。

## 6. 预算和存储测试

审计必须从 Gate 12 budget 文件读取四个 observed per-process 值，并用 15,056 独立重算：

- median wall = `64.1962130965 h`；
- p95 wall = `67.6671808478 h`；
- median output = `30.8662777189 GiB`；
- p95 output = `49.3065398270 GiB`；
- p95 output bytes = `52,942,494,009`；
- 20 GiB reserve bytes = `21,474,836,480`；
- minimum launch free bytes = `74,417,330,489`。

浮点字段允许绝对误差 `1e-9`，byte 字段必须精确。p95 wall 必须不超过 168 h。存储判定必须以原始字节为准，并在正式授权以后、formal output root 创建以前重新运行。

当前 H: 快照仅记录为 advisory evidence。即使当前通过，也不得把 `snapshot-pass-not-a-launch-authorization` 改成正式授权。合成负向测试必须证明 `freeBytes = minimumLaunchFreeBytes - 1` 会在产生样本前失败，等于门槛时通过。

## 7. 无自定义用量上限与会话停止策略测试

审计必须确认：

- active user-imposed usage ceiling 为 null，`weeklyRemainingBudgetEnabled = false`；
- 固定短周期窗口停工阈值处于 disabled 状态，不存在固定 reserve percentage，且 usage percentage 不得触发计划性停工；
- 先前 89% 周剩余量及“Gate 13 启动时周剩余量”方案被标记为 inactive、superseded-before-audit，只作为决策历史保留；
- 不得为节省用量降低验证强度，也不得为消耗用量扩大范围；
- additional reset/credit 未授权，平台实际硬限制仍适用；
- wall-clock budget 仍为 `not-explicitly-set`；
- 当前生效的 amendment specification、test design、overall plan 和 next-session checkpoint 中不存在旧的固定窗口余量/百分比停工规则；Gate 10 fairness specification 必须保持 Gate 12 冻结时的原始字节哈希，因此其中的历史 8% 规则只作为冻结历史文本保留，并由 Gate 13 amendment 的当前策略显式覆盖，不得参与 Gate 13 的启动、暂停或停止判断。

该策略不授权创建 formal output root、调用 Unity 或把 `gate13ExecutionAuthorized` 改成 true。

## 8. 未实现状态和负向边界

本阶段审计必须确认：

- 当前 Gate 10 runner 仍是冻结 hash，且参数约束仍为 `Blocks <= 100`；
- `runnerCap148ImplementationPending = true`；
- `formalCampaignConfigurationPending = true`；
- `Research/FormalRuns/Gate13/v1/` 不存在；
- `Research/PilotRuns/Gate13/` 不存在；
- Research JSON 中没有 `formalCampaign: true`、`gate13ExecutionAuthorized: true` 或 `formalCampaignStartAllowed: true`；
- 没有运行中的 Unity process，也没有 `Temp/UnityLockfile`。

这些“尚未实现”检查通过的含义是没有越过本阶段授权边界，不是 Gate 13 已可执行。

## 9. 静态质量和完成态测试

审计必须解析所有 `Research/**/*.ps1`，并解析所有新增 JSON。最终 summary 至少输出：

- 三个修订文档的 hash/bytes；
- 冻结输入检查结果；
- 四 family 独立重算；
- cohort/matrix counts；
- 15,056 进程和预算重算；
- 当前磁盘快照与 future launch threshold；
- 无自定义用量上限、被撤销的 89% 历史快照和固定窗口停工规则移除状态；
- baseline、bundle、PowerShell、Unity process/lock、formal-output absence；
- 每项 boolean check、failed checks 和错误列表；
- `passed`；
- `gate13Status = not-started-not-authorized-implementation-pending`。

审计通过后只允许写入修订 checkpoint 和总体计划恢复点。后续 cap-148 runner/config 实现与 Gate 13 正式执行是两个不同的授权阶段；执行必须另行明确批准。
