# Gate 14Re 四算法单位运动与数量效应实验计划 v2

状态：`SCIENTIFIC-DESIGN-FROZEN / B48-FIXED / NON-EXECUTING`

日期：2026-10-15（Asia/Shanghai）

本文件取代 `Gate14Re_Experiment_Plan.v1.md` 作为 Gate 14Re 的科学设计权威文本。v1 永久保留为决策历史，但不再控制后续实现或执行。

## 1. 研究目的

Gate 14Re 是一项从零建立的独立确认性研究，只回答两个问题：

1. 在预先登记的真实应用输入条件下，四种固定生产算法中哪一种整体表现更优？
2. 当单位数量增加时，各算法的单位运动表现和全量渲染性能如何变化？

旧 Gate 14R、任何 pilot、任何历史数值分析以及 Gate 13R 的 observation、效应估计、方差或结论均不作为 Gate 14Re 的正式数据、先验中心或选型依据。Gate 13R 只允许提供已经存在的生产算法、场景格式和执行基础设施；Gate 14Re 必须产生 fresh processes 和 fresh observations。

## 2. 一次性冻结的核心设计

- 四个算法固定为：`A=A*-R`、`B=D*L`、`C=C-FF`、`D=IDFF`。
- 主比较包含 8 个冻结应用条件 `C01`–`C08`，主单位数量固定为 `N_primary=128`。
- 数量效应包含 2 个冻结 anchor 条件 `Q1=C01`、`Q2=C07`，单位数量固定为 `N={1,8,32,128,512}`。
- 每个设计单元固定使用 `B=48` 个独立完整 blocks；B 在任何正式结果产生前冻结，不进行结果驱动的事后样本量调整。
- 每个 block 使用一个 fresh Unity process，在同一个冻结输入快照上依次执行四算法；四算法结果是 block 内配对观测，不是四个独立样本。
- 算法顺序使用四行 Williams 平衡顺序；每个设计单元中每行恰好出现 12 次。
- 每次运行只有一个所有单位共享的逻辑终点。到达后保持生产系统的真实行为；不得强制持续运动、复活、循环目标或重定位。
- Gate 14Re 允许得出“没有唯一优胜者”。B=48 的目的是收窄区间，而不是保证或强制产生赢家。

## 3. 算法绑定

| 分析标签 | 生产算法 ID | 生产源码 |
|---|---|---|
| A | A*-R | `Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs` |
| B | D*L | `Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs` |
| C | C-FF | `Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs` |
| D | IDFF | `Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs` |

算法 ID、接口、生产源码和各自规格文件的精确 SHA-256 记录在 `Gate14Re_Design_Contract.v2.json`。本阶段不构建可执行文件，因此正式 standalone build 和 `Assembly-CSharp.dll` 的哈希在 implementation freeze 时机械绑定；这不是未决科学选择。

同一 block 内四算法必须获得相同场景、单位起点、共同终点、事件序列、预算、fixed-step 和初始状态。每个算法开始前必须恢复冻结初始快照，并清空上一算法的世界状态、算法私有状态和 telemetry。不得依据运行结果改变顺序、输入或预算。

## 4. 冻结应用条件

主比较使用以下 8 个既有 shared-goal 场景；精确文件大小和 SHA-256 在设计契约中冻结。

| 条件 | 场景 ID | 网格 | 连通性 | 代价 | 障碍率 | 动态 footprint | 共同终点 |
|---|---|---:|---:|---|---:|---:|---|
| C01 | core-r02-s1-shared | 64×64 | 4 | weighted | 0.25 | 81 | (4,48) |
| C02 | core-r02-s2-shared | 64×64 | 4 | weighted | 0.25 | 81 | (35,62) |
| C03 | core-r03-s1-shared | 64×64 | 8 | uniform | 0.25 | 9 | (14,16) |
| C04 | core-r03-s2-shared | 64×64 | 8 | uniform | 0.25 | 9 | (58,48) |
| C05 | core-r06-s1-shared | 128×128 | 4 | weighted | 0.10 | 9 | (94,126) |
| C06 | core-r06-s2-shared | 128×128 | 4 | weighted | 0.10 | 9 | (2,96) |
| C07 | core-r07-s1-shared | 128×128 | 8 | uniform | 0.10 | 81 | (103,96) |
| C08 | core-r07-s2-shared | 128×128 | 8 | uniform | 0.10 | 81 | (41,32) |

所有场景的 cell size 为 1、fixed step 为 0.02 秒、包含 5 个预定变化事件和 128 个唯一单位起点。Q1 选择 C01，代表较小、较密、weighted、4-connected 条件；Q2 选择 C07，代表较大、较疏、uniform、8-connected 条件。选择在正式数据产生前完成，不得按结果更换。

### 4.1 数量水平的嵌套起点规则

对每个 quantity anchor：

1. 源场景的 128 个单位按 `agentId` 升序形成 canonical prefix。
2. `N=1,8,32` 使用该 prefix 的前 N 个起点；`N=128` 完整使用源场景起点。
3. `N=512` 保留原 128 个起点，再从其余“初始可行走、初始可达共同终点、非共同终点且未被占用”的网格单元中选择 384 个不同起点。
4. 候选单元以 `SHA-256(UTF8("Gate14Re|<conditionId>|<x>|<y>"))` 升序排列；哈希相同则按 y、x 升序决胜。
5. 新单位 ID 固定为 128–511，依所选候选顺序分配。
6. 地图、事件、共同终点和算法语义均不改变。若不足 512 个有效起点，implementation preflight 必须 fail closed；不得按结果删选、重抽或放宽 oracle。

## 5. 两条测量 lane

### 5.1 Movement lane：M1、M2、M3、M5

每个算法在冻结快照上运行真实导航和真实单位状态。

**共同到达规则**

- 单位所在 grid cell 等于共同 goal cell；
- 单位到 goal cell 中心的水平距离不超过 `0.75 × cellSize`；
- 两项条件连续满足 10 个 fixed ticks，即 0.20 秒；
- 到达一经满足即 latch，不因随后生产行为改变；
- 不新增强制停止、持续运动、复活、循环目标或重定位逻辑。

**M1：全部单位完成时间（主判据，越低越好）**

- 从 measurement release 开始，到全部登记单位均 latch 到达为止。
- 正式上限固定为 180 秒。180 秒内未全部完成时，M1 记为 180 秒，同时在 M3 中记录非完成原因；不得删除该算法结果。
- 对 M1 使用 log 变换；主要效应量为算法完成时间几何均值比。

**M2：实际轨迹代价（护栏/次级，越低越好）**

- 单位轨迹代价为 measurement release 至首次 latch 到达之间的累计水平路径长度。
- 每个 block 使用对四算法共同的有效单位 mask，不允许为每个算法选择不同 mask。
- mask 至少包含 `max(1,ceil(0.8N))` 个单位，并且每个被纳入单位在四算法中均有 finite trace 和 latch 到达。
- 不满足 mask 门槛时，该 block 的 M2 标为 inconclusive/missing，不能填 0；算法特异的不完成仍保留为 M3 结果。

**M3：可靠性资格**

- 完成、超时、无路径、预算耗尽和内部失败均按预先定义的终态落盘。
- 算法必须在 8 个主 movement 条件中的每一个条件至少完成 `45/48` 个 blocks，方可通过 M3 工程资格。
- 该门槛是本次工程测试的资格规则，并报告区间；不宣称已经证明任意场景总体风险。

**M5：正确性/安全性资格**

- 在全部主 movement blocks 中，critical violation 必须为 0。
- critical violation 包括：非有限位置/速度/状态；越出 grid/world 边界；穿越或占用不允许的阻塞拓扑且并非授权瞬态事件重叠；禁止的对角 corner cut；错误终点完成；单位身份缺失或重复。
- 普通单位间接触只作支持性描述；除非它造成上述 critical invalid state，否则不自动记为 M5 失败。

### 5.2 Full-population M4 lane

- 场景中必须实际实例化并渲染全部 N 个单位；使用同一生产移动语义和共同终点。
- 已到达或停止的单位保持生产行为，不要求全部单位持续运动。
- 固定 warm-up 600 个 rendered frames，随后测量 1,800 个 rendered frames。
- 原始测量为 monotonic wall-clock frame interval；每个 block 形成 median 和 nearest-rank P95 frame time。FPS 仅由 frame time 派生供展示，不作为另一独立观测。
- 主 `N=128` 的每个条件中，算法必须同时满足：48 个 block P95 的中位数不超过 33.333 ms；且 block P95 超过 50 ms 的 blocks 不多于 3/48。
- `N=512` 是数量扩展性结果，不作为主应用资格门槛。
- 帧不是独立 n；正式 n 始终是完整 block。

## 6. 固定 B=48 与运行规模

Williams 四行固定为：

1. `A-B-D-C`
2. `B-C-A-D`
3. `C-D-B-A`
4. `D-A-C-B`

每个设计单元 48 个 blocks 中，每行使用 12 次。

### 6.1 主比较模块 A

`8 conditions × 1 N_primary × 2 lanes × B48 = 768 fresh Unity processes`

四算法 lane-specific samples：`768 × 4 = 3,072`。

### 6.2 数量效应模块 Q

两个 anchors 在 `N=128` 的数据由模块 A 各自对应的条件提供一次；不重复计数。只补采其余 4 个 N 水平：

`2 anchors × 4 additional N levels × 2 lanes × B48 = 768 fresh Unity processes`

四算法 lane-specific samples：`768 × 4 = 3,072`。

### 6.3 总规模

- 独立 planned valid blocks / fresh Unity processes：`1,536`
- 四算法 lane-specific samples：`6,144`
- 每个设计单元的独立样本量：`B=48`
- 每个 Williams 行在每个设计单元的使用次数：`12`

B=48 是资源与精度之间的预先选择，不声明来自已观察方差的 power 保证。正式数据开始后，不因区间宽、显著性或赢家状态增加样本。

## 7. 确认性选优规则

### 7.1 资格先于速度

只有同时通过 M3、M4、M5 的算法进入最终性能选优。未通过资格的算法不能因 M1 更快而成为推荐算法。

### 7.2 M1 主判据

- 8 个主条件等权；完整 block 是独立单位，四算法按 block 配对。
- 比较全部 6 个无序算法对。对 log(M1) 的六个双侧配对检验使用 Holm family-wise 校正，并通过检验反演报告 Holm-adjusted simultaneous confidence intervals；同时报告普通 95% intervals。
- 最小实际重要差异冻结为 `delta_M1=5%`。
- 某候选算法只有在其相对每一个其他合格算法的 adjusted 完成时间比率区间上限均 `<0.95` 时，才通过 M1 唯一优胜规则。

### 7.3 M2 护栏和次级工程比较

- 最大可接受轨迹代价恶化冻结为 `delta_M2=10%`。
- M1 候选相对每一个其他合格算法的 adjusted M2 比率区间上限必须 `<=1.10`，否则不能推荐。
- 若 M1 没有唯一赢家，仅当候选集的 M1 差异均落在 `±5%` 的实际 tie band 内，且一个候选相对每个其他候选的 adjusted M2 比率区间上限均 `<1.00` 时，才允许以 M2 给出次级工程优选。
- 其余情况报告“无唯一赢家”和保留候选集，不事后扩样、不改阈值、不按点估计强行排序。

## 8. 数量效应模型

- M1 和 M4 是数量效应的主要 outcomes；M2、M3、M5 为支持性 outcomes。
- 对正值结果使用 log 尺度，预登记固定效应为 `log2(N)`、algorithm、algorithm×log2(N) 和 anchor condition。
- 完整 block 是独立单位；同一 block 内的四算法为配对重复测量。
- `N=128` anchor 数据只使用一次，由主模块提供，不复制到独立样本数。
- 报告各算法从 N 加倍时的变化和算法×数量交互区间；不得用某个 N 的单独显著/不显著代替交互结论。
- 最终算法推荐以 `N_primary=128` 的主比较为准；数量曲线说明适用范围和扩展性。

## 9. 运行环境冻结

- 操作系统：Windows 11 Pro，build 26300，64-bit。
- CPU：AMD Ryzen 9 7950X3D，16 cores / 32 logical processors。
- RAM：33,396,609,024 bytes。
- GPU：NVIDIA GeForce RTX 4070 Ti SUPER，16,376 MiB，driver 616.92，PCI 01:00.0；正式运行不得退回其他 GPU 或软件渲染。
- Unity：2022.3.30f1c1。
- 渲染：1920×1080 FullScreenWindow；Ultra/current quality index 5；`vSyncCount=0`；`Application.targetFrameRate=-1`；`runInBackground=true`。
- fixed timestep：0.02 秒。
- camera：top-down orthographic，完整 grid 加 5% margin，16:9；无 UI 或 debug gizmos。

项目设置和 package 文件的精确大小与 SHA-256 在设计契约中绑定。正式实现、standalone build 和现场 preflight 必须重新确认这些绑定。

## 10. 故障、替换与停止规则

- 进程崩溃、磁盘写入失败、错误场景/绑定或未能执行完整四算法属于基础设施失败；整个 block 作废，最多允许一次预先记录的 whole-block replacement，原故障证据永久保留，replacement 不增加可分析 B。
- 单一算法的无路径、预算耗尽、超时、不完成或正确性违规是算法结果；不得重跑或替换该算法结果。
- 任何科学字段、算法、场景、N、共同终点、事件、指标、阈值、Williams 顺序、硬超时或选择规则不匹配时 fail closed。
- 正式数据开始后不允许根据区间宽度、p 值、效应方向、排名或赢家状态扩样。
- 允许的最终结论包括“唯一赢家”“M2 次级工程优选”或“无唯一赢家”。

## 11. 最小执行路线与授权边界

Gate 14Re 只保留以下阶段：

1. **本次科学设计冻结**：本文件和 v2 design contract 已完成科学选择；不产生实验数据。
2. **一次实现与增量验证**：在后续单独授权后实现 runner、两条 lane、schema 和门禁；执行 compile-only、pure-synthetic known-answer tests、短现场 preflight 和 N=512 资源准入。
3. **一次正式 Phase A**：仅在用户再次明确授权后创建唯一 formal measured root，并按冻结设计执行 1,536 个 planned blocks。
4. **一次冻结分析与报告**：结构提交后按预登记模型分析并报告，包括无唯一赢家的可能性。

不设置数值 pilot、nuisance-only projection、Monte Carlo 样本量搜索、历史 raw tree 全量重扫或结果驱动扩样。

当前授权仅到科学设计冻结。未授权实现、编译、Unity 运行、formal measured/analysis root 创建、正式 Phase A、Phase B 或 Gate 15V-R/OBS。
