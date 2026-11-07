# Gate 13 Readiness 版本化修订规格

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T23:09:58+08:00
- Administrative Update: 2026-10-05T23:45:19+08:00
- Verification Status: SPECIFICATION-FROZEN
- Version Label: gate13_readiness_amendment_spec_v1

规格 ID：`gate13-readiness-amendment-v1`  
机器可读修订：`Research/Gate13_Readiness_Amendment.v1.json`  
状态：精度、cap、Williams 调度、启动前存储门槛与无自定义 Codex 用量上限策略已记录；Gate 13 尚未开始且未获执行授权

## 1. 用户决定与本阶段停止点

用户于 2026-10-05 明确决定：

1. 将 primary endpoint 的相对 95% CI 半宽目标从 5% 修订为 10%；
2. Gate 11 的 53 个场景、212 个 eligibility cell、分析行和排除规则保持不变；
3. 每个 algorithm × scenario cell 的上限由 100 提高到 148；
4. 正式执行前必须重新检查输出卷可用空间；
5. 当前不得启动 Gate 13；
6. 取消所有由项目或代理自行设置的 Codex 用量 ceiling、固定余量、百分比停工线和节省用量规则；
7. 用户先前报告的 89% 周剩余量及“以 Gate 13 启动时周剩余量为上限”的方案，在本次审计前即被最新指令撤销，不构成活动预算；
8. 实际平台硬限制仍客观适用；本决定不授权购买 credits、使用 reset、启动 Gate 13 或越过任何科学/技术 Gate。

本阶段只允许新增版本化修订规格、测试设计、机器可读修订、静态审计和检查点。不得调用 Unity，不得创建正式结果根目录，不得生成 formal timing 样本，也不得把“修订已记录”解释为 Gate 13 执行授权。

## 2. 保持不变的研究合同

以下内容不因本修订改变：

- Gate 11 retained bundle 的 53 个场景、212 个 eligibility cell、canonical identity、种子、cohort 和算法资格；
- primary endpoint `dynamicHandlingMillisecondsPerScheduledEvent`、自然对数变换、指数化 ratio 和双侧 95% CI；
- P1–P4 分析行、Holm multiplicity family、secondary/descriptive 分析表；
- outlier 全部保留、算法失败保留在分母、只有 technical invalidity 可替换；
- 每个样本使用独立 Unity 进程；
- Williams 平衡、provenance/hash、create-new、完整保留和检查点规则；
- 禁止依据显著性、趋势、效果方向或中间方差提前停止；
- 原始脚本、原始场景、Gate 11 `Research/FormalScenarios/v1/` 和成功 Gate 12 `Research/PilotRuns/Gate12/v1/` 均保持只读。

本修订只改变 precision target、cap、由此导出的固定样本数，以及对应的预算和启动前存储门槛。

## 3. 冻结输入身份

| 输入 | SHA-256 |
|---|---|
| Gate 11 bundle manifest | `ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e` |
| Gate 11 ordered bundle aggregate | `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88` |
| Gate 11 matrix | `404df63d38bccd66bb665446e0f2cbf3e5f8c7293f543b3213bde4206435fe9f` |
| Gate 11 preregistered analysis | `7e947885c38fcf9307fd9202585dda3b2b5d11334f495428760009a2aa202b5b` |
| Gate 12 candidate sample sizes | `e0a32ee0545f722e46eb6c2a995f869db73944321be525e492c0dce6f3c05ff3` |
| Gate 12 budget feasibility | `5d1c380061deb2dd4c31f5b01fa48e7665eb405699ce67e1cfdc2b33a87f5f69` |
| Gate 12 final audit summary | `87a5d93dead6dc367ab0716ad2e4e2239570fc42577be978d0f0378ca14f78c8` |
| Current Gate 10 campaign runner | `176f82fed18beee2fc7e2c8cb37ce988f7c7f4740cdeec3c5510b677843615c3` |

审计必须深度验证 Gate 11 manifest 中全部 artifact，而不能仅比较顶层 manifest。以上冻结输入如有任何字节变化，本修订失效并停止在正式样本产生之前。

## 4. 修订后的精度公式

对 Gate 12 已冻结的每个 family `sigma_log` 独立计算：

```text
n_raw = ceil((1.96 × sigma_log / ln(1.10))²)
required_n_formal = next multiple of 4 at or above max(30, n_raw)
cap = 148
```

`10%` 表示 primary log endpoint 的双侧 95% CI 相对半宽设计目标，不表示算法正确率、统计功效或显著性阈值。Gate 12 的 pilot 只提供冻结噪声估计；正式 campaign 中不得重新估计方差后改变样本数。

## 5. Family 样本量与 shared-cohort 对齐

| Family | `sigma_log` | `n_raw` | 统计最低 `required_n_formal` | 正式调度 `scheduled_n_formal` |
|---|---:|---:|---:|---:|
| P1 `D*L` vs `A*-R`, shared | 0.3371608505 | 49 | 52 | 52 |
| P2 `D*L` vs `A*-R`, heterogeneous | 0.5896465874 | 148 | 148 | 148 |
| P3 `IDFF` vs `C-FF`, shared | 0.3266133748 | 46 | 48 | 52 |
| P4 `IDFF` vs `C-FF`, grouped | 0.3408731499 | 50 | 52 | 52 |

P3 的 48 是公式导出的最低需求，但 P1 与 P3 共用 `four-algorithm-shared-goal-v1`。Gate 10 合同要求该 cohort 的每个 block 同时包含四个算法，并以四个 block 构成完整 Williams cycle。不得为了节省 256 个进程，把最后一个 shared cycle 拆成仅含 `A*-R`/`D*L` 的非授权子 cohort。

因此 shared cohort 冻结为每个算法 52 次：P1 恰好满足 52，P3 从最低 48 预先上调到 52。该调整在看到任何正式结果前完成，只提高 P3 精度，不改变矩阵、对比、分析或排除规则。

## 6. 正式调度规模

| Cohort | 场景数 | 算法数 | 每场景 blocks | 完整 Williams cycles/场景 | Unity 进程 |
|---|---:|---:|---:|---:|---:|
| four-algorithm shared | 32 | 4 | 52 | 13 | 6,656 |
| per-agent heterogeneous | 21 | 2 | 148 | 74 | 6,216 |
| grouped-field heterogeneous | 21 | 2 | 52 | 26 | 2,184 |
| **总计** | **74 campaign** | — | — | — | **15,056** |

每个 `scenario × cohort` 是一个 campaign；每个 `scenario × algorithm × repetition` 对应一个新的 Unity 进程和唯一 run ID。所有 blocks 在任何执行前全部固定，禁止根据中间结果减少、增加或调序。

## 7. 预算投影和存储硬门槛

使用 Gate 12 的实测每进程成本：

- median wall：`15.349785278125001 s/process`；
- p95 wall：`16.17971911875 s/process`；
- median output：`2,201,276.125 bytes/process`；
- p95 output：`3,516,371.8125 bytes/process`。

对 15,056 个进程的冻结投影为：

- median wall：`64.1962 h`；
- p95 wall：`67.6672 h`，低于 168 h 技术边界；
- median output：`30.8663 GiB`；
- p95 output：`49.3065 GiB`，即 `52,942,494,009 bytes`。

输出位置计划为 `Research/FormalRuns/Gate13/v1/`，只允许 create-new。为了在 p95 输出完成后仍保留 20 GiB，启动前目标卷必须至少有：

```text
52,942,494,009 projected bytes + 21,474,836,480 reserve bytes
= 74,417,330,489 free bytes
= 69.3065398270 GiB
```

比较必须使用原始字节数，不得用显示层四舍五入后的 GiB 判定。2026-10-05 的只读快照显示 H: 有 `162,195,955,712 bytes`（151.0568 GiB）可用，当前快照通过，但它不是未来启动授权。正式输出目录创建前必须重新测量；少于 `74,417,330,489 bytes` 时立即停止，且不得产生任何正式样本。

## 8. Codex 用量策略、尚未获得的授权和待实现项

当前 Gate 10 runner 仍冻结在 `Blocks <= 100`；本规格不会就地修改它。后续若继续 readiness 实现，必须在新的研究专用 Gate 13 orchestration/config 层支持 cap 148，先通过负向测试和静态/回归审计，仍不得触碰原始脚本或原始场景。

以下状态保持为 false/pending：

- `gate13ImplementationAuthorized = false`；
- `gate13ExecutionAuthorized = false`；
- `formalCampaignStartAllowed = false`；
- 正式 campaign 配置生成、runner cap-148 支持和 launch-time preflight 实现均未开始；
- `userUsagePolicyStatus = no-user-imposed-codex-usage-limit`；
- 不再设置任何自定义 Codex 用量 ceiling、窗口余量、周剩余量预算或百分比停工线；实际平台硬限制、用户暂停、授权阶段完成或技术失败仍可触发检查点；
- 先前 89% 快照只保留为被最新指令撤销的历史决策，不得作为 Gate 13 启动或停止条件；
- 不得为了消耗可用用量而扩大范围、降低验证标准或启动未授权工作；
- additional reset/credit 未授权；用户可接受的 wall-clock 时间预算仍未单独明确记录。

Gate 10 fairness specification 属于 Gate 12 冻结输入，必须保留 SHA-256 `42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd`，其中的历史 8% 窗口规则不得通过改写该冻结文件来删除。对 Gate 13 而言，该历史文本已被本 amendment 的 `no-user-imposed-codex-usage-limit` 策略覆盖，只保留 provenance 意义，不再是活动控制条件。

未来即使非执行实现和 readiness audit 全部通过，也必须由用户另行明确授权 Gate 13 执行，才能创建正式输出根目录或启动第一个 Unity 进程。

## 9. 本阶段完成条件

本修订阶段只在以下条件全部满足时完成：

1. 规格、测试设计和机器可读修订相互一致；
2. 10% 公式由 Gate 12 原始 `sigma_log` 独立重算一致；
3. P3 52 次 shared-cohort 对齐和 15,056 进程被显式审计；
4. 预算与最低空闲字节数独立重算一致；
5. Gate 11 bundle、Gate 12 成功 pilot 和原始 baseline 字节未改变；
6. 无 Unity process/lock，无 formal output root，无 `formalCampaign=true`；
7. 无自定义用量上限字段、被撤销的 89% 历史快照和无固定窗口停工阈值相互一致；
8. 审计输出明确保留 Gate 13 `not-started / not-authorized` 状态。
