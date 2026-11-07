# Gate 13R-PR2 全新 formal attempt 4：块级正式统计资格与自动恢复预注册修正案 v1

状态：`PROSPECTIVE-BEFORE-ATTEMPT4-MEASURED-DATA / VERSIONED-AMENDMENT / PHASE-B-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

记录时间：2026-10-10T04:03:12.1689968Z（Asia/Shanghai：2026-10-10T12:03:12.1689968+08:00）。

## 1. 决策与历史边界

1. 用户明确放弃 Gate 13R-PR2 formal attempt 3 的 ordinal 3,470/3,471 continuation 路径，改为从 global ordinal 1 启动一个全新的 formal attempt 4。
2. Attempt 3 永久保留为 `FAILED / INCOMPLETE / EXCLUDED-FROM-ATTEMPT4` 历史证据；其 `v3` formal root、receipt、status、checkpoint、failure evidence 与事后修正案不得覆盖、删除、移动、合并或重新解释为 attempt 4 数据。
3. `Gate13R_PR2_Attempt3_PostFailure_Protocol_Amendment.v1.md` 所定义的 continuation 从未获得 launch authorization，现标记为 `ABANDONED-BY-USER-BEFORE-CONTINUATION`。Attempt 3 的任何 observation（包括 ordinals 1–3,470）均不得进入 attempt 4 的正式统计数据集。
4. Attempt 4 使用新 formal root `Research/FormalRuns/Gate13R_RQAligned_S48H48/v4`、新 execution receipt、独立 control/monitoring artifacts，并从 ordinal 1 严格按原冻结 schedule 重跑全部 3,552 个 block processes / 10,176 个 algorithm samples。
5. 科学设计保持不变：原 v2 schedule、74 campaigns、53 scenarios、Williams 顺序、AB/BA 顺序、算法实现、确定性输入、P1–P5、C1–C5、multiplicity、样本量和 memory policy 均不因本修正案改变。

## 2. “每个已完成块自动获得正式统计资格”的精确定义

1. 一个 block 只有在同一 fresh Unity process 内完成该 schedule row 的全部样本，并通过原冻结 correctness、结构、算法集合、position、predecessor、run ID、receipt identity、memory hard gate、文件存在性与 SHA-256 校验后，才称为 `COMPLETED-AND-COMMITTED-BLOCK`。
2. 对每个 `COMPLETED-AND-COMMITTED-BLOCK`，orchestrator 必须立即创建一个不可覆盖的块级资格提交记录。提交记录必须包含 global ordinal、schedule/block/campaign/scenario identity、receipt hash、process identity、block manifest hash、wrapper summary hash、样本数、raw file count/bytes 与：

   `formalStatisticalEligibility = true`

3. 该资格在块提交时自动、结果无关且不可选择性撤销；不以整个 attempt 最终完成为前提。后续 attempt 中断、控制面进程退出、status publisher 故障或 raw-commit 工具故障，不得使此前已提交块失去资格。
4. 若后续完整性审计发现预先定义的客观违约（hash mismatch、duplicate identity、错误 schedule identity、partial sample、hard gate failure 或原始文件损坏），对应块必须标记为 integrity failure；这不是基于结果方向的排除，也不得静默删除。审计必须同时保留原资格提交与失效证据。
5. 任何后续获授权的 Phase-B 分析必须纳入全部适用于目标 estimand 的 eligible blocks，不得按效应方向、耗时、显著性、排名或“是否有利”择优纳入。
6. 块级资格不改变原统计独立单位：
   - shared-goal 的一个完整 Williams block 是一个 eligible cluster；
   - heterogeneous cross-cohort estimand 仍要求同一 matched superblock 的 A/B 两个 block 均 eligible；单个 half-pair 可保留块级资格，但不得冒充完整 matched unit；
   - full 32-campaign matrix-level confirmatory estimand 只有在其预定覆盖完整时才能作原计划的完整范围结论。
7. 若 attempt 4 在 3,552 blocks 前永久终止，已提交块仍属于 `FORMAL / FAILURE-TRUNCATED / BLOCK-ELIGIBLE` 数据。它们可在另行授权的 Phase-B 中按其实际覆盖范围估计；必须报告停止 ordinal、缺失 schedule cells、每个 campaign 的 n、完整 matched-superblock 数和缺失机制限制。不得把 failure-truncated 结果称为完整 32-campaign/74-campaign 设计结论，也不得用后验补样、跨 attempt 合并或替代 observation 恢复原完整标签。
8. 本修正案不授权中期结果查看、重复显著性检验、outcome-conditioned stopping 或 outcome-conditioned resume。运行期只能访问结构、身份、进程、内存、文件数、字节数和 checkpoint 元数据。

## 3. Attempt 4 自动 resume 合同

1. Attempt 4 身份由同一 execution receipt、同一 `v4` formal root、同一冻结 config/schedule、同一 ordinal 空间和唯一 block/sample identity 定义；它不要求单一 Python/PowerShell 操作系统进程从头持续存活。
2. 自动 resume 仅允许从最后一个连续的块级资格提交边界恢复，最多发生 3 次；每次必须创建不可覆盖的 resume inspection 与 session receipt。
3. 已提交 ordinals `1..k` 永不重跑。恢复检查只允许以下两种自动路径：
   - ordinal `k+1` 没有任何 measured output：从 `k+1` 开始；
   - ordinal `k+1` 已完整落盘但块级资格提交缺失：在 Unity/lock 均不存在、plan/receipt/process/PID-start/block/sample/hash 全部闭合且不存在更晚 output 时，只读验收并补建资格提交，然后从 `k+2` 开始。
4. 若 ordinal `k+1` 存在 partial、矛盾或无法闭合的 measured evidence，自动 resume 必须失败关闭；不得自动重跑该 block、删除 partial output、跳过、替换、移动、覆盖、top-up 或继续更晚 ordinal。
5. measured block wrapper nonzero、correctness/memory/hash/identity gate failure、Unity concurrency violation、schedule drift、receipt/config hash drift、磁盘不足或重复 identity 均是 hard failure，不属于自动 resume。
6. status/monitoring publication 是非科学控制面。单次 mutable status replace 失败不得使已完成块失去资格；publisher 按冻结 0/2/5 秒策略最多尝试 3 次，仍失败时创建不可覆盖的 publication-event sidecar，并由 append-only block commits 作为恢复真相来源。
7. supervisor 只可在 resume inspection 明确返回 `AUTO-RESUME-SAFE` 时重新启动 orchestrator。相同 resume failure signature 连续出现 2 次、累计 3 次 resume 用尽或 hard failure 均立即停止。
8. 自动 resume 不授权修改 scientific input、改变 schedule、改变样本量、并行 Unity、复用 process、运行统计分析或启动 Gate 14R。

## 4. 完成标签与失败标签

Attempt 4 全部完成且 final raw audit 通过时，允许标签：

`ONE-COMPLETE-FORMAL-ATTEMPT-BLOCK-COMMITTED-AUTO-RESUMABLE`

若发生过 resume，报告中必须给出 resume 次数、每个 session receipt 和准确恢复 ordinal；不得使用“单一不间断进程完成”。

若永久失败但存在已提交块，允许标签：

`INCOMPLETE-FORMAL-ATTEMPT-WITH-PROSPECTIVELY-ELIGIBLE-COMMITTED-BLOCKS`

该标签仅表达块级正式资格，不表达完整设计、充分 power、完整 matrix estimand 或任何 superiority 结论。

## 5. 授权边界

本修正案与用户当前指令授权：生成 attempt 4 的版本化执行/监控实现、运行 prelaunch static/synthetic/negative/readiness gates，并在全部门禁通过后从 ordinal 1 启动一次新的 Phase-A raw acquisition。它同时预先授权本节定义的最多 3 次边界安全自动 resume。

本修正案不授权 Phase-B 正式统计分析，不授权 Gate 14R，不授权 Playable/OBS timing，不授权删除 attempt 3，不授权跨 attempt 合并，也不授权任何 partial block 的自动 measured retry。
