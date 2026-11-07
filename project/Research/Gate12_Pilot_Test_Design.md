# Gate 12 Pilot、噪声与样本量测试设计

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: plan
- Origin Date: 2026-10-05T19:57:56+08:00
- Verification Status: SPECIFICATION-FROZEN
- Version Label: gate12_pilot_test_design_v1

测试设计 ID：`gate12-pilot-tests-v1`  
绑定规格：`gate12-isolated-pilot-v1`  
状态：实现前冻结

## 1. Gate 顺序测试

预实现审计必须在任何 Gate 12 production runner、analysis module 或 pilot 输出存在前通过，并保存：规格、测试设计、机器可读计划、Gate 11 manifest 和 bundle aggregate 的 hash 与 timestamp。

审计失败条件包括：

- 三个冻结文件缺失或无法解析；
- Gate 12 production 文件或 pilot output 已提前出现；
- Gate 11 retained bundle 任一 artifact hash/size 改变；
- Gate 10 runner、workload、fairness 或 Unity executable hash 改变；
- 原始 baseline 24 条任一不匹配；
- 已有 Unity process/lock；
- Gate 11 manifest 的 `pilotExecuted` 或 `formalCampaignExecuted` 不为 false。

预实现审计通过后才允许新增实现文件。最终审计通过时间必须晚于三个冻结输入的 LastWriteTimeUtc，且三个 hash 必须仍与预实现审计相同。

## 2. 计划和 subset 单元测试

机器可读计划必须满足：

- 唯一 `pilotPlanId = gate12-isolated-pilot-v1`；
- `formalCampaign = false`、`gate13ExecutionAuthorized = false`；
- 精确 8 个 scenario、4 个结构行、shared/heterogeneous 成对；
- 仅 `s1`，结构行集合恰为 `{1,2,7,8}`；
- 每个 scenario path/hash/fingerprint 与 Gate 11 matrix 和 manifest 一致；
- 12 个 measured campaign ordinal 连续且 ID 唯一；
- 每行恰有 shared、per-agent、grouped 三个 cohort；
- shared campaign 只引用 shared scenario；两个 heterogeneous campaign 只引用配对 hetero scenario；
- shared/cohort eligibility 中每个算法都存在；
- Blocks 均为 8；每 cell n=8；总 measured sample 256；warm-up 16；总进程 272；
- campaign output root 不在 Gate 11 bundle 内，且名称不含 `FormalCampaign`。

## 3. Preflight 测试

正向测试验证当前机器快照包含 CPU/RAM/OS/Unity/power/disk/background/thermal 字段，且每个硬条件有显式 boolean verdict。

合成负向测试逐项验证 fail-closed：

1. AC offline；
2. active scheme GUID 不同；
3. free memory 低于 4 GiB；
4. H: free space 低于 10 GiB；
5. mean CPU load 高于 50%；
6. Unity process 存在；
7. Unity lock 存在；
8. Unity version/hash 不同；
9. Gate 10/11 hash 不同；
10. temperature unavailable 只产生显式 advisory，不单独失败。

测试不得改变电源计划或终止用户进程。

## 4. Williams、独立进程与 provenance 测试

对 warm-up 和每个 measured campaign 验证：

- `formalCampaign = false`；
- nested Gate 10 campaign manifest 完成且 hash 匹配；
- block/position 唯一、每 block 算法集合完整；
- position counts 和 ordered predecessor counts 精确平衡；
- shared 8 blocks = 2 个四算法完整周期；两算法 8 blocks = 4 个完整周期；
- 每 schedule entry 有唯一 run ID 和独立 manifest/result/JSONL；
- child Unity version、scenario source/canonical/fingerprint、fairness/workload/algorithm specification/implementation hash 一致；
- result 的 comparison cohort、goal cohort、planner state model 与算法授权一致；
- `dynamicCostIncludesAllRepairsAndPostEventPlans = true`；
- 每个 child artifact 的实际 SHA-256 与 manifest 一致；
- JSONL sequence 连续且全部 flush；
- measured campaign 共 256 entries，warm-up 16 entries；两者路径完全分离。

缺 block、重复算法、顺序不平衡、同一 child 重复计数、formal flag 为 true 或 provenance mismatch 均使 Gate 12 失败。

## 5. 样本提取和噪声测试

必须验证：

- warm-up entry 无法进入 measured sample 集；
- 只接受计划中的 12 个 campaign；
- 每个 family 恰有 4 scenario × 2 algorithm × 8 repetitions = 64 个 endpoint；
- 每个 cell 恰有 8 个值；
- endpoint 必须 finite 且 `> 0`；NaN、Infinity、0、负数均拒绝；
- log 使用自然对数；sample SD 使用分母 `n-1`；
- family `sigma_log` 是 cell SD 最大值并携带 governing cell；
- 相同值 `[1,1,1,1]` 的 log sample SD 为 0；
- endpoint `[1,e,e²,e³]` 的 log sample SD 为 `sqrt(5/3)`，允许绝对误差 `1e-12`；
- outlier 不删除，算法失败不被技术 invalidity 过滤器误删；
- warm-up、技术无效目录和任何 Gate 10 历史 fixture 都不计入 n。

## 6. 精度公式固定向量

公式实现至少通过以下向量（浮点比较使用 `1e-12`，整数必须精确）：

| `sigma_log` | `n_raw` | `required_n_formal` | `candidate_n_formal` | Gate 13 precision status |
|---:|---:|---:|---:|---|
| 0.00 | 0 | 32 | 32 | within-cap |
| 0.15 | 37 | 40 | 40 | within-cap |
| 0.24 | 93 | 96 | 96 | within-cap |
| 0.25 | 101 | 104 | 100 | blocked-amendment-required |

NaN、Infinity 和负 `sigma_log` 必须拒绝。不得用 banker's rounding 替代 `Ceiling`，不得先 cap `n_raw` 再按 4 对齐。

## 7. Budget 和运行成本测试

用合成 campaign 数据验证：

- P1/P3 使用 32 shared scenario、P2/P4 使用 21 heterogeneous scenario 的进程数公式；
- 四个 family 候选均 32 时，总数等于 `212 × 32 = 6784`；
- family 值不同时严格按 `32×2×n_P1 + 21×2×n_P2 + 32×2×n_P3 + 21×2×n_P4`；
- wall time 和 bytes 同时输出 median 与 nearest-rank p95；
- projected p95 wall time 超过 168 小时则 blocked；
- projected storage 后 H: headroom 少于 20 GiB 则 blocked；
- 任一 campaign hard timeout 或 technical invalidity 则 blocked；
- 算法 budget overrun 被计数和报告，但样本仍保留；
- 未设置用户费用/时间预算时必须输出 `not-set`，不能推断用户已批准 Gate 13。

## 8. Create-new、监控与中断测试

- 已存在非空 output root 必须拒绝；
- hard timeout 可以终止且只能终止对应 pilot campaign process tree；
- crash/timeout 不自动重试；
- 90 秒 output stall 只写 advisory，不删除或重排样本；
- 每个完成 campaign 后 checkpoint 增加一次并能由 hash 复核；
- incomplete checkpoint 不得伪装为 complete；
- 未明确使用未来的 resume 入口时，不自动续跑。

## 9. 完成态与回归测试

Pilot 完成后必须运行：

1. Gate 12 plan/unit tests；
2. pilot manifest 深度验证和 272 个 child identity/hash 验证；
3. 四 family noise/sample-size/预算报告的独立重算；
4. PowerShell parser、全部新增 JSON/JSONL parse；
5. Gate 2–10 已保留 summary 状态与 Gate 11 bundle 全 hash 审计；
6. 原始 baseline 24/24；
7. Unity compiler log error signature 扫描；
8. Unity process/lock clean-exit；
9. 搜索并确认没有 Gate 13 output、`formalCampaign = true` 或 pilot 样本并入正式目录。

最终 Gate 12 checkpoint 必须列出实际进程数、family `sigma_log`、候选/required n、预算投影、技术无效数、bundle 前后 hash 和 Gate 13 是否因 cap/预算/技术状态而 blocked。无论结果如何，Gate 13 均保持“未授权”。
