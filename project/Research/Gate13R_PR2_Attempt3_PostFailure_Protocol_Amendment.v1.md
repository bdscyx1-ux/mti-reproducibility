# Gate 13R-PR2 formal attempt 3 事后行政中断修正案 v1

## 1. 状态、效力与诚实披露边界

本修正案于 formal attempt 3 已发生硬停止之后、Phase-B 正式统计分析与 Gate 14R 仍未获授权时追加。它是**事后、版本化、可审计的协议偏离修正案**，不是原始预注册，也不得被描述为失败前已冻结的规则。

本修正案只允许建立后续恢复的合同与审计框架。它本身不授权启动 Unity、不授权恢复执行、不授权正式统计分析、不授权 Gate 14R，也不把现有失败终态改写为成功。

以下历史证据保持字节不变且继续有效：

- `Research/Gate13R_PR2_Attempt3_Execution_Authorization.v1.json`；
- `Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v1.json`；
- `Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md`；
- `Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json`；
- `Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md`；
- `Research/Gate13R_PR2_Formal_Execution_Status.v3.json`；
- formal root 中原始 checkpoint、failure checkpoint、日志和所有 measured payload。

本修正案只在其明确列出的 Attempt-3 行政恢复事项上追加并取代 v1 的 `no-resume` 处置；科学设计、算法、场景、Williams 顺序、AB/BA 顺序、endpoint、contrast、multiplicity、threshold、planned sample size 和 Gate 14R 边界均不改变。

## 2. 冻结事实

1. 原始 formal root 为 `Research/FormalRuns/Gate13R_RQAligned_S48H48/v3`，原始 execution receipt 与 schedule/config 身份不变。
2. 原 orchestrator 的 durable committed frontier 为 global process ordinal 1–3,469，共 3,469 processes / 10,010 samples。
3. global ordinal 3,470 的 Unity block 已在原 formal root 落盘；其 block manifest 标记完成 2/2 samples，block checkpoint 为 `block-completed`，wrapper stdout 为 `Pass`。但原 orchestrator 在返回 `verify_completed_block` 之前因 status 文件原子替换发生 `PermissionError [WinError 5]`，因此 3,470 尚未获得 orchestrator commit 身份。
4. ordinal 3,469 是 heterogeneous matched superblock `g13rpr2-h21-m0007` 的 A 半，ordinal 3,470 是其 B 半。3,469 不能单独进入原定 cross-cohort matched-superblock 估计；只有 3,470 经独立取证验收后，两者才构成一个完整、可进入相应估计的 matched superblock。
5. ordinals 1–1,536 覆盖 32 个 shared-goal campaigns 的全部 48 个 Williams blocks，共 6,144 samples。该 confirmatory shared 采集结构已经完整落盘，但其正式分析资格仍须由本修正案要求的只读完整性审计与后续单独 Phase-B 授权确认。
6. ordinals 1,537–3,468 覆盖前 20 个 heterogeneous scenarios 的全部 matched superblocks，以及第 21 个 scenario 的前 6 个完整 matched superblocks。ordinal 3,469 是第 7 个 matched superblock 的未配对 A 半。
7. 当前 formal status 的失败事实、失败时间、reason code 与原始计数不得删除、覆盖或重新编码。
8. 为确认 ordinal 3,470 的落盘状态，修正案起草代理读取了该 block manifest；工具输出同时包含算法 timing 字段。未执行任何对比、效应、区间、显著性、排名或优胜分析，且这些数值不得写入本修正案或向用户报告。该事件必须登记为 `INCIDENTAL-AUTOMATED-AGENT-OUTCOME-FIELD-EXPOSURE / NO-FORMAL-ANALYSIS`，后续 readiness 必须由不接收这些值的结果盲化校验实现独立完成。

## 3. Attempt 身份与允许的最终标签

Attempt 身份由同一 formal root、同一原始 execution receipt、同一冻结 config/schedule、同一 global ordinal 空间以及无重复 measured identity 共同定义，而不是由单个 orchestrator 操作系统进程的连续存活定义。

在且仅在本修正案全部门禁通过、ordinal 3,470 被取证验收、ordinal 3,471–3,552 按原顺序完成、最终 raw commit 验证恰为 3,552 unique processes / 10,176 unique samples / 1,008 complete matched superblocks 时，Attempt 3 可使用以下限定标签：

> **一次性完整正式尝试（同一 frozen schedule/root；曾发生行政中断；依据版本化事后修正案继续完成）**

机器可读 token：

`ONE-COMPLETE-FORMAL-ATTEMPT-SAME-ROOT-ADMINISTRATIVELY-INTERRUPTED-POSTFAILURE-AMENDED`

下列表述永远禁止：

- “按原始冻结协议不间断完成”；
- “原协议预先允许恢复”；
- “未发生失败或协议偏离”；
- “一次完整 non-restartable execution session”；
- 在 3,552/10,176 最终门禁通过前使用任何 `COMPLETE` 标签。

当前允许的状态标签仅为：

`ONE-FORMAL-ATTEMPT-INCOMPLETE-ADMINISTRATIVE-INTERRUPTION-RECOVERY-NOT-YET-AUTHORIZED`

## 4. 恢复前强制门禁

任何 Unity continuation 授权之前必须完成一个独立、版本化、只读的 forensic recovery-readiness audit；审计产物必须写在 formal raw root 之外。至少必须证明：

1. 原始 status、receipt、checkpoint、failure checkpoint、wrapper logs 与 ordinals 1–3,470 已落盘文件的 pre-audit hashes 已冻结；
2. ordinals 1–3,469 与原 schedule/config 一一对应，无 missing identity、duplicate run ID、duplicate global ordinal、hash mismatch、partial sample、错误算法集合、错误 Williams order、错误 predecessor 或错误 process identity；
3. ordinal 3,470 的 block plan、block manifest、block checkpoint、sample manifests、sample summaries、workload results、memory evaluations、wrapper summary/log、PID/start-time 与原 schedule identity 可闭合验证；
4. ordinal 3,470 验收只允许生成 formal root 外部的审计/commit-sidecar；不得重写、补写或标准化其 measured payload；
5. 未发现 ordinal 3,471 或之后的 measured output；
6. 原始 scientific config/schedule、endpoint、contrast、multiplicity、threshold 和样本量保持原 hash；
7. status atomic-publish 缺陷已做版本化修复，并通过专门的并发读取/替换 synthetic test；monitor 不得以会阻止 Windows rename/delete sharing 的方式持有 active status；
8. 新 continuation orchestrator 经过 static、synthetic、negative、exact-frontier 与 no-duplicate 测试；
9. 用户在 continuation 前单独确认：失败后未以结果方向、效应、显著性、排名或优胜判断为依据决定恢复；并由结果盲化的独立校验实现复核结构性门禁。若无法确认，confirmatory 标签必须降级并由另行统计修正案处理；
10. 形成 `RECOVERY-READY-FOR-SEPARATE-LAUNCH-AUTHORIZATION` checkpoint 后停止；readiness 本身不构成 launch authority。

## 5. 唯一允许的行政 continuation

若且仅若全部恢复前门禁通过并获得新的明确用户 launch authorization：

1. 取证验收的 ordinal 3,470 被登记为原 Attempt 3 的 committed measured block；不得重跑 3,470。
2. continuation 的第一个可执行 ordinal 必须是 3,471；不得从 3,470 重启，不得重跑 1–3,470，不得创建替代 observation。
3. 只允许一个 administrative continuation segment，严格按冻结 schedule 执行 3,471–3,552；最大 Unity 并发仍为 1，每 process 最多一个完整 block。
4. continuation 使用新的 versioned control/status/receipt-amendment 路径，但 measured payload 仍归属于同一 v3 formal root 和原 schedule identity。原 v3 failure status 保留为历史证据，不覆盖。
5. continuation 不得 top-up 超过 ordinal 3,552，不得跨 attempt merge，不得引入 pilot/history/validation observations，不得择优保留。
6. continuation 再次发生 measured hard failure时立即停止；本修正案不授权第二次 continuation。
7. 任一恢复审计失败、3,470 无法闭合验证、发现重复/缺失/变异、或 frozen scientific hash 不一致时，Attempt 3 保持 incomplete，禁止 continuation。

## 6. 正式分析资格

1. 本修正案不运行也不授权 Phase-B 正式统计分析。
2. 最终完整恢复成功后，ordinals 1–3,552 可在单独授权的 Phase-B 中按原冻结 estimands 分析；ordinals 1–3,469 原样保留并计入其适用的原定分析单位。
3. ordinal 3,469 只有在 ordinal 3,470 取证验收通过后，才能进入 heterogeneous cross-cohort matched-superblock estimands；它可在完整性清单中计数，但不得作为孤立 half-pair 冒充完整 matched unit。
4. 在最终 3,552/10,176 门禁未通过时，本修正案不自动授权任何 partial formal inference。对已完整的 shared confirmatory cohort 或 truncated heterogeneous 数据进行偏离分析，必须另建明确标记为 post-failure/deviation-aware 的统计修正案并单独授权。
5. M1–M5、Gate 14R、Playable/OBS timing 继续不授权。

## 7. 报告要求

任何论文、报告、注册更新、审计或复现包必须同时披露：

- 原始非恢复合同；
- 2026-10-10 的行政 status-persistence failure；
- 本修正案在失败后形成；
- ordinal 3,470 的取证验收方式；
- continuation 的确切起点 3,471；
- 无重跑、无重复、无替代 observation 的证据；
- 最终唯一 process/sample/matched-superblock counts；
- 结果是否在修正决策前保持盲化；
- 对 confirmatory 解释的任何降级或 sensitivity analysis。

## 8. 当前停止点

本修正案落盘后立即停止。下一步仅可在新的单独授权下实施 forensic recovery-readiness audit 与 continuation tooling；在新的 readiness checkpoint 和 launch authorization 之前，不得启动 Unity、推进 ordinal、修改 formal raw root、运行正式统计或进入 Gate 14R。
