# Gate 13R-PR1 统计分析计划 v1

## 数据与独立单位

Gate 12R v4 是 `NON-FORMAL / PILOT-INFORMED / EXCLUDED-FROM-FORMAL-ANALYSIS`。重分析只读访问 384 个 measured Williams blocks 和 1,152 个 algorithm samples。shared-goal 独立单位是一个 fresh process 执行的完整四算法 Williams block；heterogeneous cross-family 规划性单位是由两个 fresh processes 组成的 matched superblock。

所有结果必须先验证 execution manifest→block manifest→sample workload result 的身份、SHA-256、run ID 唯一性、完整 block、算法集合、position、predecessor、process age、wave 与 cohort。partial block、duplicate run ID、hash mismatch 或 eligibility failure 不进入效应估计，但必须保留在 missing/failure counts 中。

## 连续正值指标 P1–P4

对 P1、P2、P3 per-agent value 和 P4，在两算法值均严格为正且 finite 时使用自然对数 paired contrast：

`d = ln(numerator) - ln(denominator) = ln(numerator / denominator)`。

每个 campaign 的 point estimate 是完整 block 的 d 均值；matrix-level estimator 对 32 个 frozen shared campaigns 等权。pilot anchor reanalysis 同时报告 campaign rows 与仅供规划的 anchor-pooled descriptive row。输出 n clusters、raw samples、eligible/missing/failure、mean log ratio、geometric ratio、sample SD、SE、unadjusted 95% CI、Bonferroni-compatible 99% simultaneous CI、90% one-sided chi-square sigma upper，以及 estimability verdict。

zero、NaN、Infinity 和非正值不得使用 pseudocount。不可估计行必须保留并提供 reason code。

P2 必须读取样本内 event-distribution 的 `dynamicHandlingP95Milliseconds`；不得对重复均值再取 P95。P4 必须计算 `dynamicManagedAllocatedBytes / scheduledEventCount`，不得以 retained managed growth、working set 或 private memory 代替。

## P3 scaling slope

P3 per-agent value 与 agent-count scaling slope 是两个不同 estimands。正式 slope 计划采用冻结 shared-goal agent-scale family 中的 log(agentCount)→log(totalPlannerElapsedMillisecondsPerAgent) 加权线性模型，campaign levels 与权重在正式配置前固定。

Gate 12R v4 只有选定 anchors；若缺少同一受控 scenario family 的足够 agent-count levels，则 slope 输出 `NOT-ESTIMABLE-FROM-GATE12R-V4 / FORMAL-DESIGN-MAPPING-AVAILABLE`。禁止把不同 scenario families 拼成斜率。

## P5 count/rate

整体、plan 与 repair overrun 分别保留分子和分母。derived repair overrun 必须满足 `0 <= budgetExceededOperationCount - budgetExceededPlanCount <= repairOperationCount`。零事件 cell 保留。全零时报告 exact one-sided 95% upper bound `1 - 0.05^(1/N)`；不报告零方差 superiority ratio，不使用 pseudocount，不套用连续 CV 公式。

## Multiplicity 与结论

P1 C1–C5 的 family-wise alpha 为 0.05。正式计算报告 Holm adjusted p-values；为 CI 判据提供更保守但兼容 FWER 的 Bonferroni simultaneous CI。C1–C4 的 superiority 需要正确性门禁通过、方向有利、Holm-adjusted inference 通过且 simultaneous upper confidence bound < 1。C5 双侧报告，不事后指定优胜方向。

P2–P5 与 heterogeneous contrasts 是 supportive/secondary，不进入 P1 confirmatory family，也不以“赢了几项”决定总体优胜。

## Heterogeneous reanalysis

Gate 12R v4 按 `(scenarioId, block ordinal)` 配对 per-agent 与 grouped-field blocks，并验证 same wave、process order 与 adjacency。C1–C4 输出 descriptive matched log ratios、order-stratified estimates、adjacent-only sensitivity 与保守 sigma upper；结果标记 `ORDER-IMBALANCED / PILOT-DESCRIPTIVE-ONLY`。IDFF/C-FF 在 grouped-field block 内 paired；D*L/A*-R 在 per-agent block 内 diagnostic paired。

Supplemental balanced pilot 的 verdict 只能基于 order sensitivity、variance stability 与候选 H 配置，不基于效应方向是否有利。

## Candidate design sensitivity

shared primary 使用 pilot shared blocks 在 campaign 内中心化后的五 contrasts covariance，投影 S=32/40/48 下 32 campaigns 等权 matrix estimator。固定种子 13122026，进行 20,000 次 multivariate-normal null simulation 以验证 Holm family-wise type-I error；各 contrast 对 5%、10%、15%、20% ratio effect 做保守 Holm-worst-threshold power sensitivity。报告 Monte Carlo SE、95% coverage、CI width、bias 与 covariance regularization 状态。

H=32/40/48 的 heterogeneous secondary 投影使用 matched-superblock descriptive variance 与 order sensitivity；不将其提升为 pure algorithm power。

这类 simulation 只比较候选，不冻结最终样本量；practical-effect thresholds 仍是规划情景而非科学阈值。

## Wall-clock 与 storage

时间使用 Gate 12R v4 已冻结的 cohort block p50/p95。heterogeneous matched superblock 的时间是 per-agent 与 grouped-field 两个 fresh processes 的和。storage 使用 cohort p95 raw bytes，另报 1.5× safety projection 与 40 GiB reserve。所有值均是 planning projection，不是 execution authorization。

## 可重复性

分析器只使用 Python 标准库，稳定排序与固定种子，JSON 以 UTF-8、LF、sorted keys、固定 indent 写入临时文件后原子替换。相同冻结输入与固定时间戳必须生成逐字节相同的核心分析文件。M1–M5 永远不能由本脚本生成方差、power 或 n_formal。
