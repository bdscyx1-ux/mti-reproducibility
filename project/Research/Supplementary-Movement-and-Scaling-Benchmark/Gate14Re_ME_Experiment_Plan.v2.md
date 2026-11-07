# Gate14Re-ME 多端点复杂度扩展实验计划（非执行科学冻结 v2：负载资格门修订）

## Material Passport

- Origin Skills: `academic-research-suite / experiment-agent`; `nature-statistics`
- Origin Mode: `nonexecuting prospective scientific amendment`
- Origin Date: `2026-10-17`
- Verification Status: `FROZEN / NON-EXECUTING / LOAD QUALIFICATION REQUIRED`
- Version Label: `Gate14Re-ME-v2`
- Study ID: `Gate14Re-ME`
- Amendment authorization: `gate14re-me-load-qualification-freeze-attempt-001`
- Qualification execution authorization: `NONE`
- Formal collection authorization: `NONE`
- Formal analysis authorization: `NONE`

## 0. 累积冻结与不变部分

本 v2 是 v1 的前瞻性累积修订，不改写也不替换 v1 文件。以下 v1 文档按精确 SHA-256 整体纳入：

- `Gate14Re_ME_Experiment_Plan.v1.md`：`af7527b9c58ff0cd8af59fd9acd4fcdd08b5c4dc8f9241c2eccf7496e01a3f43`；
- `Gate14Re_ME_NonExecuting_Scientific_Contract.v1.json`：`02b8c5edc1d6c8604dbd1816d99ee4616ac2814d6198e0cee273d031fee60e7f`；
- `Gate14Re_ME_Endpoint_Dictionary.v1.json`：`9736b16601cc8c89166d65a78ff466114ad6affb57f8be2c9df59a5ddfce22f8`；
- `Gate14Re_ME_Data_Delivery_Contract.v1.json`：`1e3a70d6be62554027ca639b6a3c7d896fd232906d627962d8c296e9e884c8dd`。

六算法 cohort、`G × N × F = 3 × 4 × 4 = 48` 个结构单元、18 个上下文层、24 个 event groups、七个主要端点域、`4/7` 多数域判定、35 个 IDFF–对照 Holm contrasts、完整逐条原始数据硬门、失败/replacement 规则以及禁止排名、赢家、加权综合分和词典序决胜，全部保持不变。

本修订唯一增加的是：正式 input draw、formal measured root、正式 observation 和最终 B 授权之前，必须以独立、匿名、不可并入正式估计的 qualification 数据通过“负载资格门”。机器定义见 `Gate14Re_ME_Precollection_Load_Qualification_Protocol.v1.json`。

## 1. 为什么增加负载资格门

名义参数大不等于实际测量负载充分。以下三类问题都可能让正式实验无法回答研究问题：

1. **过轻**：D1 接近计时器分辨率或空边界开销，D5–D7 的 latency slope 主要反映量化噪声；
2. **假复杂**：F 很大但变化不影响任何 agent 的参考最短路，算法只是在处理形式上的事件；
3. **过重**：高角组合大量超时、OOM 或资源饱和，使结构层缺失并破坏可估计性和完整交付。

因此门禁同时设测量地板、几何/路径相关性、覆盖度、匿名 lane 内动态范围和资源天花板。它只回答“该设计能否被可靠测量且有足够负载”，不回答“哪个算法更好”。

## 2. 资格阶段的独立单位与盲法

资格阶段的独立单位是一个 immutable pilot input superblock；其六条匿名算法 lane 是配对技术观测。event group、agent、query、operation、tick 和 grid cell 均不是独立 n。

算法身份在资格报告中密封为 `ALG-A` 至 `ALG-F`。允许对每个匿名 lane 分别检查 floor、coverage、dynamic range 和 ceiling；禁止跨算法均值/contrast、方向性结论、p 值、排名、赢家、IDFF 专属判断或依据优势选择端点/场景/阈值。qualification 数据永久排除于正式效应估计、正式样本量方向寻找和正式结论。

## 3. 固定 qualification 设计

核心 qualification 覆盖全部 48 个 `G × N × F` 结构单元，每单元 3 个互相独立、且不得在 formal collection 重用的 pilot seeds，共 144 个 superblocks。18 个上下文层在核心部分各精确出现 8 次。

另设 18 个高角 stress superblocks，固定 `G=256, N=512, F=225`，逐一覆盖 18 个上下文层。总计：

- 162 个 pilot superblocks；
- 每 superblock 六条 fresh-process anonymous lanes；
- 972 个 fresh algorithm processes；
- 每 lane 24 个 event groups；
- 23,328 条期望的算法 event-group raw rows；
- 六条 Williams sequences 各使用 27 次，每个匿名算法在每个执行位置精确出现 27 次。

另以同一 build、host、clock、instrumentation 和 process policy 运行 12 个不调用 planner 的 fresh empty-boundary processes，每进程 1,000 次、共 12,000 次原始迭代。这一阶段也必须另行授权；本冻结没有运行它。

## 4. 算法无关的几何/有效难度门

每个 pilot input 必须在任何算法进程启动前由冻结并哈希绑定的参考 Dijkstra oracle 检查：

- goal 和 N 个 starts 均可通行，starts 互异且与 goal 不同，基线全部可达；
- 每个 agent 的基线路径至少 4 steps；至少 90% agents 的路径不少于 `ceil(G/4)`；中位路径不少于 `ceil(G/2)`；
- 每组正好有 F 个唯一 changed cells，且不得包含 start 或 goal；
- 每组前后比较参考最短路 status/cost；每组至少影响 `max(1, ceil(0.05N))` 个 agents；lane 内 affected fraction 中位数至少 0.10；bottleneck 的 block/increase groups 至少影响 50% agents；
- restore groups 必须把 grid 字节及全部 oracle status/cost 精确恢复到 cycle 前状态。

162 个 input 中任一项失败，整体资格不通过。算法输出不得参与 input 是否合格的判断。

## 5. 测量地板

定义：

`floorReferenceMs = max(100 × stopwatchTickMilliseconds, emptyBoundaryP99ElapsedMilliseconds)`。

对每个匿名 lane 分别要求：

- 所有 present D1 均为有限正值；
- 上负载区 `G≥128, N≥128, F≥81` 的 D1 中位数至少为 `20 × floorReferenceMs`；
- 上负载区至少 90% D1 不低于 `5 × floorReferenceMs`；核心 144 superblocks 至少 80% D1 不低于该倍数；
- 核心部分至少出现 10 个不同的有限正 D1 值，避免严重计时量化；
- 至少 99% eligible D2 event groups 的 grid-read 总数大于 0。

D3 的合法零分配和 D4 的合法非负状态值不会因“数值小”被删除；二者依赖冻结的 positive-control / synthetic-fixture 仪器资格测试，而不是强迫算法产生不必要工作。

## 6. 覆盖、动态范围与资源天花板

每个匿名 lane 的核心 eligible event-group fraction 至少 0.95；对每个 G level、每个 N level 和每个 F level 分别至少 0.90。失败或 missing rows 仍在分母内，不能通过删除改善比例。

匿名 lane 内的低锚点为 `(64,8,1)`，高锚点为 `(256,512,225)`。以 D1 几何均值比和 D2 中位数比计算：

`max(high D1 / low D1, high D2 / low D2) ≥ 4.0`。

该规则只确认动态范围，不要求单调，不比较不同算法，也不代表任何算法具有优势。

qualification execution 前必须另行冻结 event-group timeout、lane wall-clock timeout、每 lane committed-memory ceiling、qualification storage 和 formal raw+delivery storage。随后必须满足：

- OOM、非预期 process crash、instrument-invalid lane、counter overflow/saturation/nonfinite 各为 0；
- 每匿名 lane 核心 budget-exceeded fraction ≤0.05，高角 stress ≤0.10；
- completed event groups 的 P99 elapsed ≤预冻结 hard timeout 的 50%；
- peak committed bytes ≤每 lane ceiling 的 50%；
- qualification package 与预测 formal raw+delivery 均 ≤各自预留空间的 50%，即至少两倍 headroom。

## 7. 仪器与完整逐条交付门

资格运行前必须通过 D2 known-answer/语义不变、D3 positive-control 单调非零敏感性、D4 逐容器 synthetic fixture、clock monotonicity、raw-to-export round trip，以及 tamper/missing/duplicate/anonymous-label-swap negative tests。

qualification raw 与 derived delivery 分离且只读冻结。必须保留每一条 empty-boundary iteration、input geometry/oracle check、event-group D1/D2/D3/eligibility、persistent-state component、process resource sample、failure/void/replacement，以及 record identity、source path 和 source SHA-256。只保留聚合值被禁止。

## 8. 失败、replacement 与判定

算法特异失败永久保留，不 retry、不逐 lane replacement。基础设施失败只能 void 整个六-lane superblock，最多一次 whole-superblock technical replacement；原失败、void 和 replacement 必须双向绑定。infrastructure replacement fraction 不得超过 0.02，OOM 或资源天花板失败不得被 replacement 擦除。

只有全部几何、仪器、floor、coverage、dynamic-range、ceiling 和逐条交付检查对六条 anonymous lanes 全部通过，receipt 才可写 `PASS_LOAD_QUALIFICATION`。否则只能写 `FAIL_CLOSED_LOAD_QUALIFICATION`，并阻断正式 input draw、formal root、正式采集、阈值事后调整和 qualification observation 重用；任何 redesign 必须取得新的科学冻结。

## 9. 与最终 B/MIPE 修订的顺序

负载资格门通过后，仍不能直接正式采集。还必须依照 `Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v2.json`，单独授权并冻结：各域最小实际重要效应、identity-blind nuisance assumptions、最终 `B`、总 superblocks/processes、明确的 timeout/memory/storage budgets，以及 movement-transfer sentinel 的精确 subset 或取消。

建议且冻结的前置顺序为：

1. outcome-independent implementation 与六算法 source/spec/fairness hash binding；
2. 独立授权 qualification inputs/root/Unity execution；
3. 获得 `PASS_LOAD_QUALIFICATION`；
4. 独立授权并完成最终 MIPE/B precollection amendment；
5. 独立授权 formal input draw 与 collection launch。

任一步失败均 fail closed，不自动进入下一步。

## 10. 本次授权边界

本次只完成 v2 非执行科学冻结。没有创建 `Research/PilotRuns/Gate14Re-ME`、formal/analysis/export root，没有生成 input，没有实现 runner/instrument/exporter，没有编译或运行 Unity，也没有产生或分析任何算法 observation。

qualification implementation、qualification execution、正式采集、正式 raw commit、正式分析、排名、赢家裁决和任何后续实验仍未授权。
