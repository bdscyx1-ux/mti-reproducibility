# Gate 13R-PR1 研究问题对齐的非执行预注册规格 v1

状态：`PILOT-INFORMED / PROSPECTIVE-BEFORE-FORMAL-DATA / NON-EXECUTING / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## 1. 目的与边界

本规格在任何 Gate 13R 正式数据产生前，重整研究问题、比较范围、指标层级与候选样本设计。它只允许读取已冻结的 Gate 12R v4 pilot 证据并做规划性重分析，不启动 Unity、不生成新样本、不创建正式输出根或正式 execution receipt。

Gate 10R attempt 4 的执行语义保持不变：每个完整 Williams block 使用一个全新的 Unity Editor 进程；一个进程最多一个 block；每个 eligible algorithm 在进程内最多出现一次；每个样本完整 reset；跨 block/campaign 不复用进程；严格串行；Playable/OBS 与 timing inference 隔离。

Gate 11R 的 53 个 canonical scenarios、74 个 campaign profiles、212 个 algorithm presets、确定性种子、canonical identity、排除规则、Williams 映射和 53 个 Playable scenes 保持字节不变。完整 74-campaign 矩阵保留。

## 2. 正式研究问题

Primary：在 shared-goal canonical scenarios 中，在正确性与结构门禁通过的前提下，C-FF 和 IDFF 是否在动态事件平均处理时间 P1 上分别优于 A*-R 和 D*L，以及 C-FF 与 IDFF 之间存在怎样的差异。

Secondary：在相同 canonical heterogeneous scenario 和受控 execution wave 下，grouped-field C-FF/IDFF system 与 per-agent A*-R/D*L system 在 P1–P5 上如何不同，以及差异如何随 scenario factor 与 goal count 变化。

Heterogeneous cross-family 差异包含 field ownership、goal representation 与算法实现的联合系统差异，因此只能称为 system/treatment contrast，不能称为 pure algorithm causal effect。

## 3. 比较范围与五个 contrasts

shared-goal 四算法完整 Williams block 是唯一 primary confirmatory comparison scope。Williams block 是独立 cluster；algorithm sample 不是独立实验单位。

- C1：C-FF / A*-R，方向性 superiority。
- C2：C-FF / D*L，方向性 superiority。
- C3：IDFF / A*-R，方向性 superiority。
- C4：IDFF / D*L，方向性 superiority。
- C5：IDFF / C-FF，双侧 head-to-head。

对 lower-is-better 指标，ratio < 1 有利于分子；对 higher-is-better 指标，ratio > 1 有利于分子。C-FF 优于两个基线必须同时满足 C1 与 C2；IDFF 优于两个基线必须同时满足 C3 与 C4。D*L / A*-R 仅为 diagnostic baseline contrast。

## 4. 指标层级

P1 `dynamicHandlingMillisecondsPerScheduledEvent` 是唯一 confirmatory primary endpoint。P2–P5 是 planning/resource supportive endpoints。M1–M5 只属于 prospective Gate 14R，不在 Gate 12R 中观测，也不从 Gate 12R 推导方差、power 或 n_formal。

正确性、valid path/field、structural exact-match、C-FF/IDFF integration-direction equivalence、确定性身份、完整 reset、hash 与 provenance 完整性均为 eligibility gates，不是额外“得分”。任何未通过 eligibility gate 的低耗时结果都不得用于优越性结论。

十项指标的公式、分母、方向与缺失处理以 `Gate13R_RQAligned_Metric_Registry.v1.json` 为唯一机器可读定义。

## 5. 推断层级

P1 的 C1–C5 组成 family-wise alpha 0.05 的唯一 confirmatory family。使用 Holm adjusted p-values；同时报告未调整 95% CI 与 Bonferroni-compatible simultaneous CI。C1–C4 的方向性判断仍报告完整 ratio 与 CI；C5 保持双侧。

主要 estimand 是 32 个 shared campaigns 的等权 matrix-level mean log ratio；每个 campaign 内完整 blocks 等权。单 campaign 结果只描述 heterogeneity/factor trend，不要求每个 campaign 单独显著。pooled superiority 不表示每个 campaign 都 superiority。

10% precision target 只表示 CI 精度，不表示实际效果至少为 10%。practical-superiority/non-inferiority margin 尚未冻结。

## 6. Heterogeneous matched-superblock

正式 prospective matched superblock 由相同 scenario、相同 repetition ordinal、相同 deterministic input identity 的一个 fresh per-agent process 和一个 fresh grouped-field process 构成。两种 cohort-process 顺序必须 AB/BA 平衡；配额相同或最多相差 1；block count 应为偶数并优先为 4 的倍数。

Gate 12R v4 的 96 个 candidate pairs 可以按 scenario/block 匹配且同 wave，但已知顺序为 89 次 per-agent→grouped-field、7 次 grouped-field→per-agent。它们只允许估计 descriptive paired log-difference variance、保守 variance upper bound 与 order/adjacency sensitivity，不允许正式 superiority 或 unbiased cross-family treatment claim。

## 7. 样本配置候选

保留旧 strict-serial 10% per-campaign 144/204/108 方案作为 `PRE-AMENDMENT-COMPARISON-BASELINE / NOT-AUTHORIZED-FOR-LAUNCH`。比较 S32/H32、S40/H32、S48/H32、S40/H40、S48/H40、S48/H48；S 是每个 shared campaign 的完整 blocks 数，H 是每个 heterogeneous scenario 的 matched superblocks 数。

候选只做 planning sensitivity；不自动冻结最终 n_formal，不删减 74-campaign 矩阵，也不将 pilot observed effect 当作样本量充分性的唯一依据。

## 8. 停止条件

只有 schema、公式、可识别性、hash、provenance、synthetic fixtures、确定性重生成和 validation-only final audit 全部通过，才更新整体计划。成功后状态仍为 `FORMAL-SAMPLE-DESIGN-UNFROZEN / GATE13R-FORMAL-NOT-AUTHORIZED`，并立即停止等待用户选择 practical-effect margin、样本配置及是否需要 supplemental balanced heterogeneous pilot。
