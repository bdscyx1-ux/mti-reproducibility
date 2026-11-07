# Gate14Re-ME 多端点复杂度扩展实验计划（非执行科学冻结 v1）

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `nonexecuting scientific freeze`
- Origin Date: `2026-10-17`
- Verification Status: `FROZEN / NON-EXECUTING / PRECOLLECTION PARAMETERS PENDING`
- Version Label: `Gate14Re-ME-v1`
- Study ID: `Gate14Re-ME`
- Scientific-freeze authorization: `gate14re-me-nonexecuting-scientific-freeze-attempt-001`
- Formal collection authorization: `NONE`
- Formal analysis authorization: `NONE`

## 0. 本次冻结的结论与边界

本次冻结固定六算法、复杂度设计、七个主要端点域、`4/7` 多数域判定、多重性控制、失败/替换规则，以及“完整逐条原始数据可交付”这一不可绕过的硬条件。

本次冻结不保证 IDFF 在新数据中获得优势，也不授权通过修改指标、删除不利结果或扩大样本来制造优势。正式结果必须完整报告 IDFF 有利、对照算法有利、未决和测量失效四类情况。禁止总排名、赢家裁决、加权综合分、投票分或词典序决胜。

本次冻结仍不虚构尚未给定的最小实际重要效应和最终每结构单元样本量 `B`。它们必须依照 `Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v1.json`，在任何正式 input draw、measured root 或 observation 之前，由用户另行授权并冻结。因而本次状态不是“可采集”。

原始 Gate 14Re 保持只读；已终止的 Gate14Re-TB2 Phase A attempt-001 永久排除。二者的 observation 不得进入 Gate14Re-ME 的估计、样本量方向判断、输入筛选、端点选择、补采或合并。

## 1. 研究问题与允许表述

主要问题是：在共享目标、动态网格以及逐级增加的网格规模、单位数量和变化范围下，IDFF 是否在预先登记的多数资源/复杂度扩展端点域中，相对 A*-R、BiA*-R、D*L、LPA* 和 C-FF 分别显示统计学优势，同时通过正确性与测量资格门禁？

每个主要端点域只能归入以下类别：

1. `IDFF_ADVANTAGE`：该域对五个具名对照的全部必需 Holm 校正区间均位于 IDFF 有利方向；
2. `UNRESOLVED`：有效域未能解析出所要求的方向；
3. `COMPARATOR_ADVANTAGE`：对称校正区间对至少一个具名对照有利；
4. `MEASUREMENT_INVALID`：冻结的测量契约失效，该域保留在七域分母中并阻断多数支持声明。

只有 D1–D7 至少四域为 `IDFF_ADVANTAGE`，且全部正确性、测量与完整交付门禁通过，才可写“多数预注册端点域支持 IDFF”。这不是排名、赢家或部署建议。若仅有 0–3 域满足，必须写“未获得多数端点域支持”。

## 2. 六算法 cohort 与公平边界

固定算法为 `A*-R`、`BiA*-R`、`D*L`、`LPA*`、`C-FF` 和 `IDFF`。正式采集前必须把六算法源码、规格、构建和可执行文件的 SHA-256 绑定到独立的机器可读公平契约。不得为了本研究改变算法搜索、修复、路径提取、budget 或状态语义；仅允许经独立验证的外部计量适配器和只读状态计数接口。

每个逻辑 superblock 使用字节完全相同的 input bundle。六算法分别在六个 fresh Unity processes 中运行，形成 superblock 内配对观测；六条 lane 不是六个独立统计样本。固定 Williams 顺序如下，并在每个结构单元内均衡：

1. `A*-R → BiA*-R → IDFF → D*L → C-FF → LPA*`
2. `BiA*-R → D*L → A*-R → LPA* → IDFF → C-FF`
3. `D*L → LPA* → BiA*-R → C-FF → A*-R → IDFF`
4. `LPA* → C-FF → D*L → IDFF → BiA*-R → A*-R`
5. `C-FF → IDFF → LPA* → A*-R → D*L → BiA*-R`
6. `IDFF → A*-R → C-FF → BiA*-R → LPA* → D*L`

统一动态计量边界为：

`同 tick 全部 ApplyChanges + 完整 same-tick 事件组结束后的全部 N 个 post-event Plan 查询`

仅比较 `ApplyChanges` 被禁止。初始化、初始查询和动态处理必须分开记录。算法特异 warm-up、GC、重建或额外查询被禁止。

## 3. 复杂度设计

主要结构矩阵固定为：

- 网格边长 `G ∈ {64, 128, 256}`；
- 共享目标单位数 `N ∈ {8, 32, 128, 512}`；
- 每事件组唯一变化单元数 `F ∈ {1, 9, 81, 225}`。

共有 `3 × 4 × 4 = 48` 个主要结构单元。每单元在 18 个上下文层间均衡：

- topology：`compact / dispersed / bottleneck`；
- graph profile：`four_way_weighted_dense / eight_way_uniform_sparse`；
- same-tick atomic partitions：`1 / 4 / 16`。

每 lane 固定 24 个事件组、6 个四阶段循环：block、unblock/restore、increase cost、decrease/restore cost。原子分片只切分同一批 F 个唯一变化单元；完整同 tick 事件组结束后才进行 N-agent 查询。

正式 `B` 必须是 36 的正整数倍。最终 accepted superblocks 为 `48 × B`，fresh algorithm processes 为 `48 × B × 6`。最终 B 尚未授权或冻结。

## 4. 七个主要端点域

机器定义见 `Gate14Re_ME_Endpoint_Dictionary.v1.json`：

1. `D1_DYNAMIC_LATENCY`：完整动态边界下的 24 条 event-group elapsed raw values；block 几何均值和 nearest-rank P95 构成一个 conjunctive 域。
2. `D2_GRID_READ_WORK`：共享只读 proxy 记录的 grid accessor 总数及每个 API 分项计数。
3. `D3_DYNAMIC_ALLOCATION`：每个 event group 的 managed allocated bytes，外加可重建的 block total。
4. `D4_PERSISTENT_STATE_BYTES`：初始化后、初始 N 查询后及每个事件组后的逐容器逻辑状态容量，共 26 个测量点/eligible lane。
5. `D5_AGENT_COUNT_SCALING`：D1 对 `log2(N)` 的 algorithm interaction。
6. `D6_CHANGE_FOOTPRINT_SCALING`：D1 对 `log2(F)` 的 algorithm interaction。
7. `D7_GRID_SIZE_SCALING`：D1 对 `log2(G²)` 的 algorithm interaction。

D5–D7 共用 D1 raw observations，不能宣称七域彼此独立。所有 raw values、原始单位、eligibility、missing reason、source path 和 source SHA-256 均须保留。

次级权衡端点包括初始化、N=8 cold query、带 `nativeSemanticsId` 的算法原生诊断、可靠性、oracle 正确性，以及若后续修订明确冻结则保留的 movement-transfer sentinel。它们不计入 `4/7`，但每条实际采集的原始记录同样受完整交付硬门约束。

## 5. 统计计划

独立实验单位是一个 input superblock。算法 lane、事件组、agent、query、operation、frame、tick 和 grid cell 均不得伪作独立 n。

主要模型固定为：

`outcome ~ algorithm + log2(N) + log2(F) + log2(G²) + topology + graphProfile + burstPartitions + algorithm:log2(N) + algorithm:log2(F) + algorithm:log2(G²) + executionOrder`

superblock 为配对 cluster。主要估计采用预注册 mixed-effects model；仅当数值非收敛触发预注册 fallback 时，使用相同 fixed-effect formula 和 superblock-cluster robust covariance。不得按方向或 p 值选择模型。

D1–D4 报告 IDFF/对照比率及同时区间，低于 1 有利；D5–D7 报告 IDFF 减去对照的每次加倍 slope 差及同时区间，低于 0 有利。七域乘五个 IDFF 对照形成 35 个确认性 contrasts，采用 Holm strong FWER，`α=0.05`。D1 每对算法取几何均值与 P95 两个单侧 p 值较大者，仍只是一项域级 contrast。

六算法全部 15 个无序算法对必须以完整矩阵报告，使用独立标识的探索性 Holm family，不得排序。

## 6. 完整逐条原始数据硬冻结条件

完整规则见 `Gate14Re_ME_Data_Delivery_Contract.v1.json`。核心条件如下：

- measured raw 与 derived delivery 必须分离；raw root 是唯一真源，export 不得改写 raw。
- 每个 accepted superblock 必须存在六个具名算法 lane；失败、void、replacement-source 和 replacement 均保留，不得静默删除。
- 交付粒度同时包括：lane/sample-run、atomic metric-long、event-group、operation/event/query、persistent-state component、failure/replacement ledger。
- 所有 raw rows 必须带 study/phase/attempt/cell/superblock/lane/algorithm/process/record identity，以及 applicable event/query/agent/measurement-point identity。
- 每个值必须带单位、数值类型、测量边界、present flag、missing reason、eligibility、source path 和 source SHA-256。
- 几何均值、P95、比率、斜率、百分比或总数不能替代 constituent raw rows；百分比必须同时交付 numerator 与 denominator。
- 必须交付 CSV、typed Parquet、compressed JSONL、data dictionary、source provenance、manifest、canonical tree 和 delivery receipt；禁止 Excel-only 或 proprietary-only 交付。
- raw commit 只有在结构验证 receipt 为 `PASS_COMPLETE_PER_OBSERVATION_RAW_DATA_DELIVERABLE` 时才可成功；状态必须同时含 `RAW_IMMUTABLE`、`COMPLETE_PER_OBSERVATION_DELIVERABLE` 和 `ANALYSIS_PENDING`。
- raw commit 只能验证 schema、cardinality、paths、hashes、types/finiteness、顺序、replacement ledger 和 raw-to-export traceability；不得聚合、解释方向、排名或裁决赢家。
- 若完整性门禁失败，必须 fail closed：保留证据，不分析、不补采、不合并、不重启，也不得未经新授权建立替代 attempt。

建议并冻结的 delivery package 为：

```text
Research/Exports/Gate14Re-ME/<phaseId>/<attemptId>/v1/
├── gate14re-me-sample-wide.csv
├── gate14re-me-metric-long.csv.zst
├── gate14re-me-metric-long.parquet
├── gate14re-me-eventgroup-long.csv.zst
├── gate14re-me-eventgroup-long.parquet
├── gate14re-me-operations.v1.jsonl.zst
├── gate14re-me-persistent-state-long.csv.zst
├── gate14re-me-failures-replacements.csv
├── data-dictionary.v1.json
├── source-provenance.v1.json
├── export-manifest.v1.jsonl
├── export-canonical-tree.v1.jsonl
└── delivery-receipt.v1.json
```

## 7. 正确性、测量与交付资格门禁

在正式 collection readiness 前必须完成：

- 六算法 source/specification/fairness hash binding；
- D2 proxy known-answer test，且不改变 path/status/version；
- D3 allocation counter monotonic nonzero sensitivity test；
- D4 per-container state formula synthetic fixture；
- output schema、data dictionary、exporter 和 structural validator 源码哈希冻结；
- synthetic end-to-end export known-answer test；
- raw-to-export record count/value round trip；
- tamper、missing row、duplicate row 和 cross-algorithm label swap negative tests；
- 资源检查覆盖 raw root 与完整 delivery package 的最坏情形空间。

任何主要仪器在采集前失效，必须 redesign/refreeze；采集后才发现失效则该域记为 `MEASUREMENT_INVALID`，保留在七域分母中。

## 8. 失败与 replacement

单算法失败作为结果永久保留，不重试、不替换。基础设施失败只能 void 整个六-lane superblock，最多允许一次完整 whole-superblock replacement；原始失败和 voided artifacts 必须保留并与 replacement 双向绑定。禁止 resume、逐算法 retry、top-up、merge、skip 或结果依赖 reorder。

## 9. 尚需单独冻结的预采集参数

以下项目不在本次授权中，且不得自动推断：

1. 每个域用于 power planning 的最小实际重要效应及单位；
2. identity-blind nuisance/resource evidence；
3. 最终 `B`、superblock 数和 process 数；
4. movement-transfer sentinel 的精确 subset，或明确取消该可选次级端点。

它们只能通过一次单独授权的 precollection parameter amendment 固化。任何正式 input draw、measured root、Unity measured run 或 observation 在该修订前均被禁止。

## 10. 授权边界

本次只授权并完成非执行科学冻结。本次没有授权：

- 修改生产算法；
- 生成正式 input bundles；
- 实现 runner、仪器、exporter、validator 或分析脚本；
- 编译或运行 Unity；
- 创建 formal measured/analysis/export root；
- 正式采集或 raw commit；
- 正式分析、排名、赢家裁决、部署建议或后续实验。

上述阶段必须分别取得新授权，并继续受完整逐条原始数据硬门约束。
