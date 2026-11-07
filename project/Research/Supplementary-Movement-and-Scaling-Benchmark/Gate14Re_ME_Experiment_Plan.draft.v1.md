# Gate14Re-ME 多端点复杂度扩展实验计划（草案 v1）

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent` + `nature-statistics`
- Origin Mode: `plan`
- Origin Date: `2026-10-17`
- Verification Status: `UNVERIFIED / DRAFT / NON-EXECUTING`
- Version Label: `Gate14Re-ME-draft-v1`（2026-10-17 cohort correction：六算法）
- Proposed Study ID: `Gate14Re-ME`
- Collection authorization: `NONE`

## 0. 结论边界

本草案可以保证的是：实验会覆盖多种复杂度轴、记录多个预先登记的端点域、使用正确的独立实验单位、控制多重比较并完整报告不利或不显著结果。

本草案不能、也不得保证 IDFF 在真实新数据中取得优势。实际结论必须由从零采集的新数据决定。设计目标是提高对 IDFF 理论优势及其适用边界的检出能力，而不是通过事后更换指标制造既定结论。

原始 Gate 14Re 已完成正式采集与分析，必须保持只读；Gate14Re-TB2 Phase A attempt-001 已被用户授权终止并永久排除。两者的 observation 均不得进入本研究的估计、样本拼接、补采、筛选或端点选择。原 Gate 14Re 结果只作为公开披露的研究动机，Gate14Re-ME 是独立的前瞻性扩展/复现研究。

## 1. 研究问题与允许结论

### 1.1 主要研究问题

在共享目标、动态网格和逐级增加的网格规模、单位数量及变化范围下，IDFF 是否在预先登记的多数资源/扩展性端点域上，相对 A*-R、BiA*-R、D*L、LPA* 和 C-FF 分别显示统计学优势，同时保持路径正确性和运行可靠性？

### 1.2 允许的端点结论

每个端点域、每个算法对只能归入以下三类之一：

1. `IDFF_ADVANTAGE`：经多重性校正的区间完全位于有利方向；
2. `UNRESOLVED`：区间跨越无差异边界；
3. `COMPARATOR_ADVANTAGE`：经校正的区间完全位于对照算法有利方向。

允许写“多数端点域支持 IDFF”的条件是：7 个主要端点域中至少 4 个端点域均相对五个对照算法满足 `IDFF_ADVANTAGE`，且正确性/安全性门禁全部通过。该表述不是赢家裁决、算法排名或综合得分。

如果只有 0–3 个端点域满足条件，必须写“未获得多数端点域支持”；不得改端点、改分母、删算法、扩样或把点估计改写成优势。

### 1.3 明确禁止

- 不产生算法总排名、名次或“唯一赢家”。
- 不构造加权分数、效用函数、AHP/TOPSIS、投票权重或词典序决胜。
- 不把均值、中位数、P95、最大值拆成多张独立“选票”。
- 不因观察到的方向、p 值、区间宽度或算法身份而更换指标、复杂度单元或样本量。
- 不隐藏对 IDFF 不利、无差异或测量失败的端点。
- 不复用原 Gate 14Re 或被排除 TB2 attempt-001 的任何 observation。

## 2. 固定算法与公平边界

比较算法固定为 `A*-R`、`BiA*-R`、`D*L`、`LPA*`、`C-FF` 和 `IDFF`，均绑定正式冻结前重新计算的源码与规格 SHA-256。算法实现不得为本研究改变搜索、修复、路径提取、预算或状态语义；只允许增加经独立验证的外部计量适配器和只读状态计数接口。

六算法覆盖的预注册机制类别如下；这些类别只用于解释研究覆盖面，不作为分组得分或隐含排名：

| 算法 | 状态/更新机制 | Gate14Re-ME 冻结要求 |
|---|---|---|
| A*-R | 单向、逐请求 full recompute | 重新绑定源码、规格与哈希 |
| BiA*-R | 双向、逐请求 full recompute | 绑定 `BidirectionalAStarRepeatedPlanner.cs` 与 `Bidirectional_A_Star_Repeated_Specification.v1.md` |
| D*L | per-agent incremental repair | 重新绑定源码、规格与哈希 |
| LPA* | backward goal-rooted、per-agent incremental repair | 绑定 `LifelongPlanningAStarPlanner.cs` 与 `Lifelong_Planning_A_Star_Specification.v1.md` |
| C-FF | shared-goal full recompute field | 重新绑定源码、规格与哈希 |
| IDFF | shared-goal incremental field repair | 重新绑定源码、规格与哈希 |

既有四算法公平协议不能自动扩展为本研究的六算法协议。正式冻结前必须生成独立的 `six-algorithm shared-goal` 比较 cohort/fairness contract，并逐项确认 BiA*-R 与 LPA* 使用相同 grid、入格成本、连通性、切角、budget、版本和动态处理边界。Gate13R-AX2 的算法源码与规格可作为实现来源，但其 observation 不得进入 Gate14Re-ME 的估计、输入选择或样本量方向判断。

每个逻辑 superblock 使用字节完全相同的输入 bundle。六算法分别在六个 fresh Unity processes 中执行，形成 superblock 内配对观测。进程启动顺序使用以下六处理 Williams 平衡顺序，并在每个结构单元内均衡分配；每个算法在每个位置恰出现一次，每个有向一阶前序对恰出现一次：

1. `A*-R → BiA*-R → IDFF → D*L → C-FF → LPA*`
2. `BiA*-R → D*L → A*-R → LPA* → IDFF → C-FF`
3. `D*L → LPA* → BiA*-R → C-FF → A*-R → IDFF`
4. `LPA* → C-FF → D*L → IDFF → BiA*-R → A*-R`
5. `C-FF → IDFF → LPA* → A*-R → D*L → BiA*-R`
6. `IDFF → A*-R → C-FF → BiA*-R → LPA* → D*L`

这里的顺序仅指同一主机上的 lane 启动顺序，不改变每个算法在独立 fresh process 中执行的约束。单算法失败不得重试；基础设施失败使整个六-lane superblock 作废，最多允许一次完整 replacement，原失败证据永久保留。

动态处理的统一计量边界固定为：

`同 tick 全部 ApplyChanges + 同 tick 事件组结束后的全部 N 个 post-event Plan 查询`

仅报告 `ApplyChanges` 对 A*-R 不公平且无效。初始化、初始查询和动态处理必须分别记录。

## 3. 复杂度设计

### 3.1 48 个主要结构单元

采用完整的三轴结构矩阵：

- 网格边长 `G ∈ {64, 128, 256}`；
- 共享目标单位数 `N ∈ {8, 32, 128, 512}`；
- 每个事件组的唯一变化单元数 `F ∈ {1, 9, 81, 225}`。

因此共有 `3 × 4 × 4 = 48` 个主要结构单元。三轴全部在正式采集前冻结，不得按结果删减高负载单元。

### 3.2 单元内平衡的上下文因素

每个结构单元中的独立输入 draw 在下列 18 个上下文层之间均衡分配：

- 变化空间形态：`compact`、`dispersed`、`bottleneck`；
- 图/代价 profile：`4-way weighted dense`、`8-way uniform sparse`；
- 同 tick 原子分片数：`1`、`4`、`16`。

原子分片数只把同一批 F 个唯一变化单元确定性地切分为 1、4 或 16 个 change sets；总变化单元集合保持相同，并且只在完整 same-tick 事件组结束后进行一次 N-agent 查询。这避免把“更多变化量”和“更多事件 bookkeeping”混为一谈。

正式每单元样本量 `B` 必须是 36 的正整数倍，以支持 18 层上下文和 6 个执行顺序的平衡。B 尚未冻结，见第 8 节。

### 3.3 每个 lane 的动态压力序列

每个算法 lane 执行 24 个确定性事件组，由 6 个四阶段循环组成：

1. block footprint；
2. unblock/restore footprint；
3. increase traversal cost；
4. decrease/restore traversal cost。

每个循环使用一个预先生成、互不结果依赖的 footprint。所有事件 ID、坐标、原子分片、顺序、预算和预期 grid version 均写入输入 bundle。事件组之间不得插入算法特异 warm-up、GC、重建或额外查询。

输入生成只允许使用结构可行性过滤：尺寸正确、坐标合法、起点/目标合法、事件可应用及独立 oracle 可判定。不得以任何算法的速度、内存、路径长度、失败率或历史结果筛选 bundle。

## 4. 七个主要端点域

详细机器定义见 `Gate14Re_ME_Endpoint_Dictionary.draft.v1.json`。七个端点域为：

1. `D1_DYNAMIC_LATENCY`：完整动态处理边界的 block 内几何均值与 block 内 nearest-rank P95；二者构成一个端点域，不分别计数。
2. `D2_GRID_READ_WORK`：同一边界内共享只读 grid proxy 记录的原始 grid accessor 调用总数，并附各 API 分项原始计数。
3. `D3_DYNAMIC_ALLOCATION`：同一边界内托管分配字节；计量器必须在 precollection sensitivity test 中通过。
4. `D4_PERSISTENT_STATE_BYTES`：使用冻结的、逐容器可审计的逻辑状态容量公式记录 planner 持久状态字节，不等同于进程 RSS。
5. `D5_AGENT_COUNT_SCALING`：动态延迟对 `log2(N)` 的 algorithm interaction；比较每次 N 加倍的变化率。
6. `D6_CHANGE_FOOTPRINT_SCALING`：动态延迟对 `log2(F)` 的 algorithm interaction。
7. `D7_GRID_SIZE_SCALING`：动态延迟对 `log2(G²)` 的 algorithm interaction。

D5–D7 共享延迟原始量，因此不宣称七个域统计独立；多重性程序必须在任意相关结构下仍有效。原始值、效应量和区间全部保留。

### 4.1 预先登记的次级/权衡端点

以下端点不计入“4/7 多数”规则，但必须完整报告，并允许其他算法显示优势：

- 初始化 elapsed time、初始化 grid reads 和初始化 allocation；
- 无动态变化时的 N=8 cold-query latency；
- algorithm-native `expandedNodes`、`relaxedEdges`、`repairedCells`，仅作带语义标签的诊断，不跨算法合成；
- plan success、budget overrun、分类失败率；
- 独立 oracle 的路径代价正确性；
- 预登记 sentinel 单元中的真实 movement completion、轨迹代价和 critical violation。

## 5. 正确性与测量资格门禁

任何性能优势表述都以以下门禁为前提：

- 所有算法使用相同 grid、goal、starts、events、budgets 和 fixed-step；
- 所有成功路径满足独立最短路 oracle 或冻结的等价容差；
- grid/planner/visual versions 全程一致；
- 无非有限状态、越界、非法 corner cut、错误 goal、重复或缺失单位身份；
- D2 计数 proxy 的启用/禁用 known-answer 差异符合预期且不改变路径/status/version；
- D3 allocator counter 在受控分配敏感性测试中单调、非零并可复现；
- D4 状态计数公式与容器容量的 synthetic fixtures 一致。

若 D2、D3 或 D4 任一主要计量器在正式采集前不能验证，必须先修改设计并重新冻结；若正式采集后才发现失效，该域记为 `MEASUREMENT_INVALID`，且不得从 7 个域分母中删除，也不得宣称“多数端点域支持”。

## 6. 统计分析计划

### 6.1 独立单位与重复结构

- 独立实验单位：一个新生成的完整 input superblock。
- 六算法 lane：同一 superblock 内配对重复观测，不是六个独立 n。
- 24 个事件组：技术性重复测量，只形成 block-level summaries，不作为独立 n。
- frame、tick、agent、grid cell 和 API call 均不是独立 n。

### 6.2 模型

正值 raw endpoints 使用预先指定的 log 尺度。主要模型固定包括：

`outcome ~ algorithm + log2(N) + log2(F) + log2(G²) + topology + graphProfile + burstPartitions + algorithm:log2(N) + algorithm:log2(F) + algorithm:log2(G²) + executionOrder`

superblock 作为配对 cluster。主要估计使用预先指定的混合效应模型；若仅因数值非收敛触发预登记 fallback，则使用同一固定效应公式与 superblock-cluster robust covariance，不得按显著性选择模型。

allocation 和 logical state bytes 允许零值，使用 `log1p` 变换，并同时报告原始尺度的中位数和分位数。失败/预算超限使用预先登记的二项模型并保留所有算法结果。

### 6.3 效应量与方向判定

对 D1–D4 报告 IDFF/对照的比率及同时置信区间，低于 1 有利；对 D5–D7 报告 IDFF 减去对照的每次加倍 slope 差及同时置信区间，低于 0 有利。

每个域中 IDFF 与五个对照的主要 contrasts 构成 35 个确认性声明。使用 Holm strong-FWER 控制 `α=0.05`。D1 的几何均值和 P95 为同一域的 conjunctive requirement；每个算法对先以 intersection-union 方式取两个单侧检验 p 值的较大者作为一个 D1 contrast p 值，且两条同时区间都必须有利。因此 D1 仍只贡献五个域级 contrasts，不能被拆成十个优势机会。

端点域判定：

- `IDFF_ADVANTAGE`：该域对 A*-R、BiA*-R、D*L、LPA*、C-FF 的所有必需 adjusted intervals 均完全位于 IDFF 有利方向；
- `COMPARATOR_ADVANTAGE`：至少一个经校正的对称 interval 完全位于对照有利方向，并逐对照报告；
- `UNRESOLVED`：其余情况。

除 35 个确认性 contrasts 外，六算法全部 15 个无序算法对以完整矩阵报告，使用独立标识的探索性 Holm family；这些结果不得转化为排名。

### 6.4 “多数端点域支持”规则

只有同时满足以下条件，报告中才可出现“多数端点域支持 IDFF”：

1. D1–D7 至少 4 个域为 `IDFF_ADVANTAGE`；
2. 所有正确性/安全性门禁通过；
3. 无主要域为 `MEASUREMENT_INVALID`；
4. 无结果驱动排除、补采、改模、改阈值或端点替换。

该规则只描述跨域证据图谱，不授予“赢家”“排名第一”或部署决策。

## 7. 报告格式

正式输出必须至少包含：

- 7 行端点域表：raw definition、effect、95% simultaneous CI、adjusted p、方向分类；
- 每个端点域的完整 6×6 pairwise matrix（15 个无序算法对），不排序；
- 各复杂度轴的 interaction estimates 与 raw distribution；
- 每个结构单元的实际 n、失败和 replacement ledger；
- 所有次级权衡端点；
- `IDFF_ADVANTAGE / UNRESOLVED / COMPARATOR_ADVANTAGE / MEASUREMENT_INVALID` 数量；
- 明确声明没有综合得分、权重、排名或赢家裁决。

## 8. B、效应阈值与冻结前步骤

当前草案不虚构样本量。正式 B 必须在任何 Gate14Re-ME formal observation 产生前完成：

1. outcome-free instrumentation validation；
2. 仅输出 nuisance covariance、missingness 和运行资源的 identity-blind planning diagnostic；
3. 用户确认每个域的最小实际重要效应；
4. 在 35 个确认性 contrasts、Holm FWER 0.05 和建议 power ≥0.90 下选择满足要求的最小 36 的倍数；
5. 资源可行性检查；若不可行，在采集前修改设计，禁止以不足 power 的 B 强行启动。

planning diagnostic 不得输出匿名算法均值、方向、排序、赢家或可反推生产身份的结果；不得进入正式估计。

## 9. 授权与版本边界

本文件只完成科学设计草案，不授权：

- 修改生产算法；
- 生成或冻结正式输入 bundles；
- 实现 runner、计量器或分析脚本；
- 编译、运行 Unity、建立 measured/analysis root；
- 使用或解封原 Gate14Re/TB2 observation；
- 正式采集、分析、排名、赢家裁决或部署。

用户确认研究 ID、7 个域、复杂度矩阵、最小实际重要效应和样本量策略后，方可生成不可变的正式科学契约与单独的实现授权。

