# Gate14Re-ME formal ST v5 四选五域规则正式分析报告

## 分析边界

本报告仅分析 read-only acceptance attempt-002 所冻结的 attempt-003 采集数据。独立单位为 superblock（N=1296）；7776 条算法 lane、事件组、查询和操作均不被当作独立样本。源数据未修改；本次按用户授权将域通过规则改为：硬门控有效，且 A*-R、BiA*-R、D*L、LPA*、C-FF 五个比较假设中至少四个通过。未运行 MQ、MT，未生成排名、综合分数或赢家字段。

正式假设家族仍为 7 个域 × IDFF 对 5 个比较算法，共 35 个复合假设；单侧较低为优，Holm 强 FWER α=0.05。D1 每个比较采用几何均值与最近秩 P95 的交并检验（p 值取两者较大值）。40 个原始对比同时报告双侧 Bonferroni 区间。MIPE 仅作实用重要性标记，不改变零假设。

## 硬门控

- completeAcceptedDelivery: PASS
- sourcePackageUnchangedDuringAnalysis: PASS
- correctnessOracle: PASS
- D1MeasurementValidity: PASS
- D2CounterValidity: PASS
- D3CounterValidity: PASS
- D4SizingFormulaValidity: PASS
- preservedFailureResolutionCompatibility: PASS
- zeroReplacement: PASS

## 四选五域判定

| 域 | 有效 | 域通过（1/0） | 通过比较数/5 | 未通过比较 |
|---|---:|---:|---:|---|
| D1_DYNAMIC_LATENCY | 是 | 1 | 4/5 | C-FF |
| D2_GRID_READ_WORK | 是 | 1 | 5/5 | 无 |
| D3_DYNAMIC_ALLOCATION | 是 | 1 | 5/5 | 无 |
| D4_PERSISTENT_STATE_BYTES | 是 | 0 | 2/5 | A*-R, BiA*-R, C-FF |
| D5_AGENT_COUNT_SCALING | 是 | 1 | 4/5 | C-FF |
| D6_CHANGE_FOOTPRINT_SCALING | 是 | 0 | 0/5 | A*-R, BiA*-R, D*L, LPA*, C-FF |
| D7_GRID_SIZE_SCALING | 是 | 0 | 0/5 | A*-R, BiA*-R, D*L, LPA*, C-FF |

## 域判据结果

域通过 = 硬门控有效 AND 五个比较算法的假设中至少四个通过。域通过数为 4/7；阈值为至少 4/7。判据状态：PASS。

## 未通过的比较假设

- D1_DYNAMIC_LATENCY: C-FF 比较未通过：GM 比率 0.758625，同时区间 [0.715234, 0.80465]；P95 比率 1.11884，同时区间 [1.04801, 1.19446]；Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；P95 点估计未低于 1；P95 同时区间未完全低于 1。D1 为 GM 与 P95 的交并检验，两部分必须同时满足。
- D4_PERSISTENT_STATE_BYTES: A*-R 比较未通过：IDFF/A*-R 比率 61768.2，同时区间 [61412, 62126.4]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 1；同时区间未完全低于 1。
- D4_PERSISTENT_STATE_BYTES: BiA*-R 比较未通过：IDFF/BiA*-R 比率 61768.2，同时区间 [61412, 62126.4]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 1；同时区间未完全低于 1。
- D4_PERSISTENT_STATE_BYTES: C-FF 比较未通过：IDFF/C-FF 比率 2.41638，同时区间 [2.40244, 2.43039]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 1；同时区间未完全低于 1。
- D5_AGENT_COUNT_SCALING: C-FF 比较未通过：IDFF−C-FF 斜率差 0.00250772，同时区间 [-0.0696284, 0.0746438]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D6_CHANGE_FOOTPRINT_SCALING: A*-R 比较未通过：IDFF−A*-R 斜率差 0.0394487，同时区间 [0.0141763, 0.064721]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D6_CHANGE_FOOTPRINT_SCALING: BiA*-R 比较未通过：IDFF−BiA*-R 斜率差 0.0383321，同时区间 [0.0130598, 0.0636044]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D6_CHANGE_FOOTPRINT_SCALING: D*L 比较未通过：IDFF−D*L 斜率差 -0.0217879，同时区间 [-0.0470602, 0.00348443]，Holm 调整单侧 p=0.0404857。失败原因：同时区间未完全低于 0。
- D6_CHANGE_FOOTPRINT_SCALING: LPA* 比较未通过：IDFF−LPA* 斜率差 -0.0217547，同时区间 [-0.047027, 0.00351766]，Holm 调整单侧 p=0.0404857。失败原因：同时区间未完全低于 0。
- D6_CHANGE_FOOTPRINT_SCALING: C-FF 比较未通过：IDFF−C-FF 斜率差 0.055078，同时区间 [0.0298056, 0.0803503]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D7_GRID_SIZE_SCALING: A*-R 比较未通过：IDFF−A*-R 斜率差 -0.026655，同时区间 [-0.0984465, 0.0451365]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；同时区间未完全低于 0。
- D7_GRID_SIZE_SCALING: BiA*-R 比较未通过：IDFF−BiA*-R 斜率差 -0.0488751，同时区间 [-0.120667, 0.0229163]，Holm 调整单侧 p=0.182101。失败原因：Holm 调整单侧 p=0.182101 不小于 0.05；同时区间未完全低于 0。
- D7_GRID_SIZE_SCALING: D*L 比较未通过：IDFF−D*L 斜率差 0.0343226，同时区间 [-0.0374689, 0.106114]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D7_GRID_SIZE_SCALING: LPA* 比较未通过：IDFF−LPA* 斜率差 0.0340515，同时区间 [-0.03774, 0.105843]，Holm 调整单侧 p=1。失败原因：Holm 调整单侧 p=1 不小于 0.05；点估计未低于 0；同时区间未完全低于 0。
- D7_GRID_SIZE_SCALING: C-FF 比较未通过：IDFF−C-FF 斜率差 -0.0410537，同时区间 [-0.112845, 0.0307378]，Holm 调整单侧 p=0.389814。失败原因：Holm 调整单侧 p=0.389814 不小于 0.05；同时区间未完全低于 0。

## IDFF–比较算法的确认性结果

下表保持冻结域与比较算法顺序，不按效果或显著性排序。比率域报告 IDFF/比较算法；斜率域报告 IDFF−比较算法的每轴单位差异。五个比较算法均参与四选五域判定。

| 域 | 比较算法 | 估计 | 同时区间 | Holm 调整 p | 方向有利 | 达到 MIPE | 假设通过 |
|---|---|---:|---|---:|---:|---:|---:|
| D1_DYNAMIC_LATENCY | A*-R | GM 0.317289; P95 0.244408 | GM [0.29914, 0.336538]; P95 [0.228936, 0.260927] | 0 | 是 | 是 | 是 |
| D1_DYNAMIC_LATENCY | BiA*-R | GM 0.164653; P95 0.116837 | GM [0.155235, 0.174642]; P95 [0.109441, 0.124734] | 0 | 是 | 是 | 是 |
| D1_DYNAMIC_LATENCY | D*L | GM 0.152829; P95 0.161828 | GM [0.144088, 0.162101]; P95 [0.151583, 0.172765] | 0 | 是 | 是 | 是 |
| D1_DYNAMIC_LATENCY | LPA* | GM 0.152929; P95 0.161925 | GM [0.144181, 0.162207]; P95 [0.151674, 0.172868] | 0 | 是 | 是 | 是 |
| D1_DYNAMIC_LATENCY | C-FF | GM 0.758625; P95 1.11884 | GM [0.715234, 0.80465]; P95 [1.04801, 1.19446] | 1 | 否 | 否 | 否 |
| D2_GRID_READ_WORK | A*-R | 0.496178 | [0.467314, 0.526825] | 0 | 是 | 是 | 是 |
| D2_GRID_READ_WORK | BiA*-R | 0.23891 | [0.225012, 0.253666] | 0 | 是 | 是 | 是 |
| D2_GRID_READ_WORK | D*L | 0.162835 | [0.153363, 0.172893] | 0 | 是 | 是 | 是 |
| D2_GRID_READ_WORK | LPA* | 0.162835 | [0.153363, 0.172893] | 0 | 是 | 是 | 是 |
| D2_GRID_READ_WORK | C-FF | 0.758096 | [0.713996, 0.804921] | 0 | 是 | 是 | 是 |
| D3_DYNAMIC_ALLOCATION | A*-R | 0.0243756 | [0.0233255, 0.025473] | 0 | 是 | 是 | 是 |
| D3_DYNAMIC_ALLOCATION | BiA*-R | 0.0117379 | [0.0112322, 0.0122663] | 0 | 是 | 是 | 是 |
| D3_DYNAMIC_ALLOCATION | D*L | 0.415697 | [0.397788, 0.434412] | 0 | 是 | 是 | 是 |
| D3_DYNAMIC_ALLOCATION | LPA* | 0.415697 | [0.397788, 0.434412] | 0 | 是 | 是 | 是 |
| D3_DYNAMIC_ALLOCATION | C-FF | 0.215123 | [0.205855, 0.224808] | 0 | 是 | 是 | 是 |
| D4_PERSISTENT_STATE_BYTES | A*-R | 61768.2 | [61412, 62126.4] | 1 | 否 | 否 | 否 |
| D4_PERSISTENT_STATE_BYTES | BiA*-R | 61768.2 | [61412, 62126.4] | 1 | 否 | 否 | 否 |
| D4_PERSISTENT_STATE_BYTES | D*L | 0.0252416 | [0.025096, 0.025388] | 0 | 是 | 是 | 是 |
| D4_PERSISTENT_STATE_BYTES | LPA* | 0.0252416 | [0.025096, 0.025388] | 0 | 是 | 是 | 是 |
| D4_PERSISTENT_STATE_BYTES | C-FF | 2.41638 | [2.40244, 2.43039] | 1 | 否 | 否 | 否 |
| D5_AGENT_COUNT_SCALING | A*-R | -0.665695 | [-0.737832, -0.593559] | 0 | 是 | 是 | 是 |
| D5_AGENT_COUNT_SCALING | BiA*-R | -0.668307 | [-0.740443, -0.596171] | 0 | 是 | 是 | 是 |
| D5_AGENT_COUNT_SCALING | D*L | -0.66522 | [-0.737356, -0.593084] | 0 | 是 | 是 | 是 |
| D5_AGENT_COUNT_SCALING | LPA* | -0.665954 | [-0.73809, -0.593818] | 0 | 是 | 是 | 是 |
| D5_AGENT_COUNT_SCALING | C-FF | 0.00250772 | [-0.0696284, 0.0746438] | 1 | 否 | 否 | 否 |
| D6_CHANGE_FOOTPRINT_SCALING | A*-R | 0.0394487 | [0.0141763, 0.064721] | 1 | 否 | 否 | 否 |
| D6_CHANGE_FOOTPRINT_SCALING | BiA*-R | 0.0383321 | [0.0130598, 0.0636044] | 1 | 否 | 否 | 否 |
| D6_CHANGE_FOOTPRINT_SCALING | D*L | -0.0217879 | [-0.0470602, 0.00348443] | 0.0404857 | 是 | 否 | 否 |
| D6_CHANGE_FOOTPRINT_SCALING | LPA* | -0.0217547 | [-0.047027, 0.00351766] | 0.0404857 | 是 | 否 | 否 |
| D6_CHANGE_FOOTPRINT_SCALING | C-FF | 0.055078 | [0.0298056, 0.0803503] | 1 | 否 | 否 | 否 |
| D7_GRID_SIZE_SCALING | A*-R | -0.026655 | [-0.0984465, 0.0451365] | 1 | 是 | 否 | 否 |
| D7_GRID_SIZE_SCALING | BiA*-R | -0.0488751 | [-0.120667, 0.0229163] | 0.182101 | 是 | 否 | 否 |
| D7_GRID_SIZE_SCALING | D*L | 0.0343226 | [-0.0374689, 0.106114] | 1 | 否 | 否 | 否 |
| D7_GRID_SIZE_SCALING | LPA* | 0.0340515 | [-0.03774, 0.105843] | 1 | 否 | 否 | 否 |
| D7_GRID_SIZE_SCALING | C-FF | -0.0410537 | [-0.112845, 0.0307378] | 0.389814 | 是 | 否 | 否 |

## 模型执行状态

- D1_GEOMETRIC_MEAN: random-intercept REML mixed-effects model paired by superblock; fallback=no; n=7776; superblocks=1296
- D1_NEAREST_RANK_P95: random-intercept REML mixed-effects model paired by superblock; fallback=no; n=7776; superblocks=1296
- D2: random-intercept REML mixed-effects model paired by superblock; fallback=no; n=7776; superblocks=1296
- D3: random-intercept REML mixed-effects model paired by superblock; fallback=no; n=7776; superblocks=1296
- D4: random-intercept REML mixed-effects model paired by superblock; fallback=no; n=7776; superblocks=1296

完整数值、区间、门控、描述性分布和 15 对探索矩阵见同目录 JSON/JSONL 文件。探索矩阵按每个域单独做 Holm 校正，固定顺序展示，不用于排名。
