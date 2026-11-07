# Gate14Re-MQ-CFF-IDFF 正式设计提案 v1

状态：`PROPOSAL_ONLY_AWAITING_EXPLICIT_USER_SCIENTIFIC_AUTHORIZATION`

这不是正式设计冻结，也没有启动正式 MQ collection 或 formal analysis。本目录把已经通过的工程证据转换成一组可以一次性授权的科学设计建议；它不默认继承 Gate14Re-ME formal ST 的 10% MIPE、功效或停止规则。

## 已完成且冻结的工作

- Gate13R-MQ 正确性、oracle、一致性、worker-count invariance、硬 CPU affinity、私有状态隔离与预期 fail-closed 注入均通过。
- Gate14Re-MQ 工程 qualification 通过：24 个技术 batch、384 条 lane 记录、全部语义摘要一致、全部 affinity 与输入哈希绑定有效。
- 独立只读复核通过；工程输出和复核证据均已冻结。
- 工程运行时诊断完成。候选最大规模 `B=144` 的 1.9× 压力预算约 47.95 小时，未触发 168 小时门。
- 上述 qualification 数据只能用于工程可行性与 identity-blind nuisance 规划，不能成为正式 MQ 效果样本。

## 推荐的正式 MQ 问题

分别对 C-FF 和 IDFF 判断：

1. 在 LARGE_L3 CCD 上，MQ 的 `W1→W2→W4→W8` 是否随每次 worker 翻倍获得可靠且具有实际意义的 batch wall-time 降低；
2. 在 HIGH_FREQUENCY CCD 上是否同样成立；
3. 在 balanced dual-CCD 上，`W16 (8+8)` 相对 `W8 (4+4)` 是否获得可靠且具有实际意义的 batch wall-time 降低。

这形成六项主检验：两个算法 × 两个单 CCD slope，加上两个算法各自的 dual-CCD W16/W8 配对对比。它不把 C-FF 和 IDFF 排名，也不声称 CCD 差异由缓存或频率中的某一个因素造成。

## 推荐规则

- 独立单位：一个完整 matched MQ block；每个 block 含 16 个全新私有 workload lane，并以相同的 opaque inputs/seeds 跑完 `2 algorithms × 12 conditions = 24` 个 fresh Unity processes。
- 正式推断以 block 为单位，lane 和 event rows 只是 block 内嵌套测量，不能冒充独立样本。
- 单 CCD 主 estimand：每个 block 内对 `log(batch wall time)` 关于 `log2(worker count)` 的等权 slope；`exp(slope)` 是每次 worker 翻倍后的几何 wall-time ratio。
- Dual-CCD 主 estimand：每个 block 的 `log(W16 wall / W8 wall)` 配对差。
- MQ 专属 MIPE 建议为 10%：ratio `≤0.90`，等价 log threshold `≤ln(0.90)=-0.10536051565782628`。
- MIPE 作为事前功效替代值和实际重要性门；统计 superiority 的零假设仍是无改善（slope 或 log-ratio `≥0`）。每项正式 claim 同时要求：单侧 Holm-adjusted `p<0.05`、同时区间低于无改善边界，以及点估计达到 10% MIPE。
- 六项主检验采用单侧 Holm strong FWER 0.05；不生成总体赢家、加权分数或多数投票结论。
- 功效目标 `≥0.90`，候选 `B={36,72,108,144}`。在任何正式输入抽取或正式 observation 之前，只用去身份 nuisance inputs 做 Monte Carlo；选择六项 opaque 主检验中最差一项的 Wilson 95% 功效下界仍 `≥0.90` 的最小 B。
- 如果 B=144 仍不满足，不追加样本；停止冻结并向用户提交修改设计。
- 正式开始后不允许 sample-size re-estimation、benefit/futility stopping、retry、replacement、top-up、跨 attempt 合并、删 endpoint、删 condition 或删算法。
- ST-direct 对 MQ-W1 只作为实现开销 sentinel 和描述性参照，不进入六项主检验族。
- 全部 correctness/oracle、语义摘要、输入哈希、affinity、cardinality 和 ordinal 仍是硬门，不与性能合成分数。

## 授权后仍会分阶段推进

1. 先冻结 MQ 专属 estimand/MIPE/multiplicity/power/stopping 合同。
2. 在新的 Verification root 做只读 identity-blind power simulation，选择并冻结 B。
3. 生成全新的 formal MQ inputs、opaque schedule、执行合同、实现绑定和 prelaunch readiness；不得复用 qualification observations。
4. readiness PASS 后先报告精确进程数、预算、根目录和冻结哈希。
5. 正式 collection 仍等待单独的明确启动授权；本提案不会自动启动它。

## 建议的一次性设计授权文本

> 我授权 Gate14Re-MQ-CFF-IDFF 独立 MQ 正式设计按 formal-mq-design-recommendation.v1 执行：六项主检验、MQ 专属 10% MIPE、单侧 Holm FWER 0.05、仅使用 identity-blind nuisance inputs 做功效，在 B=36/72/108/144 中选择最小满足最差主检验 Wilson 95% 功效下界不低于 0.90 的 B；保留全部 correctness/oracle 硬门，不允许正式启动后的重估、获益或无效停止、retry、replacement、top-up 或跨 attempt 合并。授权完成只读功效、正式设计/实现/日程冻结与 prelaunch readiness；正式 collection 在 readiness PASS 后仍须单独报告并等待我明确启动授权。

完整机器可读版本见 `formal-mq-design-recommendation.v1.json`。
