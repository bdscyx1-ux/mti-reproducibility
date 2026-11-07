# Gate14Re-ME qualification planning freeze v2 attempt-001

## Material Passport

- Origin Skills: `academic-research-suite / experiment-agent`
- Origin Mode: `nonexecuting prospective qualification planning freeze`
- Origin Date: `2026-10-17`
- Verification Status: `FROZEN DESIGN / STRUCTURALLY VERIFIED / NOT EXECUTED`
- Study ID: `Gate14Re-ME`
- Design ID: `gate14re-me-load-qualification-planning-v2`
- Authorization ID: `gate14re-me-qualification-planning-freeze-v2-attempt-001`
- Parent status: `Gate14Re_ME_Status.v26.json`
- Qualification schedule/input/identity generation: `NOT AUTHORIZED`
- Measured-root creation and Unity/algorithm execution: `NOT AUTHORIZED`
- Formal collection, analysis, ranking and winner adjudication: `NOT AUTHORIZED`

## 1. 冻结结论

本阶段仅冻结 Gate14Re-ME 正式采集前的负载资格设计。唯一输入契约是 Status v26 已采用的 input schema v2 与 planning schema binding v2。历史同名 `qualification-planning-freeze-attempt-001` 因旧 schema v1 与 runtime contract 冲突而失败；该失败目录与状态保持不变。本次证据使用 `qualification-planning-freeze-v2-attempt-001`，表示 schema-v2 系列的首次规划冻结，不改判历史失败。

冻结后的资格阶段只回答：“六条匿名算法 lane 在相同输入、相同仪器和相同资源边界下，是否都有足够、可测、非平凡且可完整交付的负载？”它不回答哪个算法更优，不计算跨算法效应、p 值、排名或赢家，也不得因为希望 IDFF 占优而筛选场景、端点或阈值。

## 2. 六算法与输入契约

六算法固定为 A*-R、BiA*-R、D*L、LPA*、C-FF 和 IDFF。qualification 报告只使用 `ALG-A` 至 `ALG-F`；一个未来另行授权的密封双射负责匿名身份，当前没有生成该映射。

输入必须同时满足：

- `load-qualification-input-schema.v2.json`，SHA-256 `1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117`；
- `load-qualification-planning-schema-binding.v2.json`，SHA-256 `abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7`；
- runtime bundle identity 仍为 `gate14re-me-qualification-input-bundle-v1`；
- `eventGroups[*].topology` 必须存在，并与 input-level `changeTopology` 一致。

旧 validation schema v1 只作为历史失败证据保留，不可用于后续资格规划。

## 3. 负载层级、单位、重复与阻断

核心设计是 `G × N × F = 3 × 4 × 4 = 48` 个结构单元：

- grid edge `G ∈ {64, 128, 256}`；
- agent count `N ∈ {8, 32, 128, 512}`；
- changed cells `F ∈ {1, 9, 81, 225}`。

每个结构单元使用 3 个互不相同、且不得在 formal collection 重用的 pilot seeds，共 144 个 core superblocks。上下文是 `3 topology × 2 graph profile × 3 same-tick atomic partition count = 18` 个 strata，每个 stratum 在 core 中精确出现 8 次。

另有 18 个 high-corner stress superblocks，固定 `G=256, N=512, F=225`，每个 context stratum 一个独立 seed。总计 162 个 pilot superblocks、每 superblock 六条匿名 lane、972 个 fresh algorithm processes、每 lane 24 个 event groups，预期 23,328 条 event-group raw rows。

独立实验单位是“一个 immutable pilot input superblock”。六条 lane 是同一 superblock 内的配对技术观测；lane、event group、agent、query、operation、tick、cell 和 measurement point 均不是独立 n。core 的 3 seeds 是独立重复，event groups 是 lane 内技术重复。

算法顺序采用六条 Williams sequences，每条精确重复 27 次；每个匿名算法在每个执行位置精确出现 27 次。当前只冻结此平衡要求，不生成具体顺序表。

另冻结 12 个不调用 planner 的 fresh empty-boundary processes，每进程 1,000 次，共 12,000 条原始迭代，用于计算 `floorReferenceMs = max(100 × stopwatchTickMilliseconds, emptyBoundaryP99ElapsedMilliseconds)`。

## 4. 仪器证据绑定

- D2：grid-read proxy known-answer 与 semantic-invariance 均通过；历史 runtime attempt 的整体失败状态不被改判。
- D3：正式绑定 D3-v3.1 owner-thread cumulative managed allocation bytes；保留 bytes、event count、foreign-thread diagnostics、invalid metadata、overflow、ticks、frequency 及 `bytes/second` 公式字段。旧 D3 零响应失败完整保留。
- D4：逐容器 persistent-state synthetic fixture 通过；合法非负状态量不因数值小而删除。
- clock：10,000 样本 monotonicity 检查通过。
- raw/export：schema-v2 tooling bridge 已通过逐条 JSONL/CSV/compressed JSONL/typed-Parquet round trip 和负向完整性测试。
- Unity 启动身份：绑定 trusted launch identity rule v1 与 attempt-007 的 UTC-ticks timestamp comparator；本阶段没有启动 Unity。

这些证据只证明仪器和规划前置条件可用，不是算法性能结果。

## 5. 指标方向

正式分析时 D1 latency、D2 grid-read work、D3 cumulative managed allocation bytes 与 D4 persistent state bytes 均为 lower-is-better；D5–D7 的 IDFF-minus-comparator slope difference 也是越低越有利。D3 的 `bytes/second` 只作为逐窗口诊断和公式核验字段完整保留，不是独立 confirmatory endpoint，也不单独赋予优劣方向。qualification 不执行这些正式方向性比较。

qualification 中：D1 用于测量地板与 lane 内低/高锚点动态范围；D2 用于 active-work coverage 与动态范围；D3 和 D4 依赖已冻结的仪器资格与逐条完整性，不通过强迫非零工作制造“负载”。

## 6. 资格门

所有 162 个输入必须先通过算法无关 Dijkstra oracle：starts/goal 合法且可达、路径长度满足下限、每组恰有 F 个唯一 changed cells、每组影响至少 `max(1, ceil(0.05N))` agents、lane 内 affected fraction 中位数至少 0.10、bottleneck block/increase 至少影响 50% agents，restore 必须逐字节和逐 oracle status/cost 恢复。

对每条匿名 lane：

- 上负载区 `G≥128, N≥128, F≥81` 的 D1 中位数至少为 `20 × floorReferenceMs`；
- 上负载区至少 90%、全部 core 至少 80% 的 D1 不低于 `5 × floorReferenceMs`；
- core 至少有 10 个不同的有限正 D1；
- 至少 99% eligible D2 event groups 的 grid reads 大于 0；
- core eligible fraction 至少 0.95，且每个 G、N、F level 分别至少 0.90；失败和缺失仍留在分母；
- 低锚点 `(64,8,1)` 与高锚点 `(256,512,225)` 满足 `max(high D1 / low D1, high D2 / low D2) ≥ 4.0`；无需单调，也不得跨算法比较。

资源门继续使用冻结预算：event-group hard timeout 300,000 ms、lane wall-clock hard timeout 5,400,000 ms、每 lane assigned committed memory 16 GiB、qualification storage 48 GiB、formal raw+delivery storage 96 GiB、Unity concurrency 精确为 1，并要求至少两倍 headroom。OOM、意外 crash、instrument-invalid、counter overflow/saturation/nonfinite 必须为 0。

只有几何、仪器、floor、coverage、dynamic-range、resource 和完整逐条交付对六条匿名 lane 全部通过，才允许未来写 `PASS_LOAD_QUALIFICATION`；否则只能 `FAIL_CLOSED_LOAD_QUALIFICATION`。

## 7. 技术失败、replacement 与停止规则

算法特异失败作为 outcome 永久保留，不 retry、不做 per-lane replacement。基础设施失败只能 void 整个六-lane superblock，最多一次 whole-superblock technical replacement；原失败、void 和 replacement 必须双向绑定。infrastructure replacement fraction 不得超过 0.02，OOM 或资源上限失败不得被 replacement 擦除。

任何 hash drift、证据缺失、schema/runtime 不兼容、六算法 source/spec drift、未来映射不唯一、设计/Williams 不平衡、未授权根目录、存储不足或异常进程，必须在后续资产生成前 fail closed。未来 qualification 中任何 oracle/instrument failure、path/hash/identity mismatch、并发大于 1 或 retry/resume/top-up/merge/skip/reorder 都立即停止。

qualification 失败时不得 formal input draw、创建 formal root、放宽阈值或重用 observation；通过后也必须停止，另行授权 MIPE/final B 参数修订，不能直接进入正式采集。

## 8. 完整逐条 provenance

必须保留十张原始表：oracle-agent checks、oracle-event checks、operations、event groups、D3 windows、persistent state、process resources、empty boundary、replacement ledger、failures/voids。每条适用记录必须有稳定 record identity、input/superblock/lane/process/measurement identity、eligibility 与 missing reason、source relative path 和 source SHA-256。

D3 必须逐窗口保留累计 bytes、allocation event count、foreign-thread bytes/events、invalid metadata、overflow、owner/observer thread IDs、start/end/elapsed ticks、frequency、allocation rate 及 rate-valid flag。只保存汇总值不合格。

## 9. 后续资产生成合同

当前未生成任何资产。只有新的独立授权才可创建：

1. 一个密封的六算法匿名身份双射；
2. 144 个 core + 18 个 stress input bundles，全部通过 schema v2 与算法无关 oracle；
3. 162 行 JSONL schedule，绑定每个 input/hash 与 identity-binding hash，并满足 Williams 平衡；
4. schema、唯一性、cardinality、context balance、Williams balance、path 和 hash 的 terminal validation receipt。

后续资产生成也不得创建 measured root、启动 Unity、构造/调用 planner、运行算法 lane、产生 qualification observation 或进入正式工作，除非再取得明确且独立的授权。

## 10. 本阶段边界

本阶段生成 0 行 schedule、0 个 input bundle、0 个匿名身份映射、0 个 measured root、0 次 Unity、0 次 planner、0 条算法 lane、0 条 qualification/formal observation。未执行正式分析、排名或赢家裁决。
