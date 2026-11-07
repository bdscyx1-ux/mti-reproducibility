# Gate13R-AX2 科学契约 v1

## 1. 研究问题

在 Gate 13R 已冻结的贴近实际 shared-goal 动态导航场景中，两个新增的基于 A* 的算法 `BiA*-R` 与 `LPA*`，相对于 `C-FF` 和 `IDFF`，在动态事件处理时间 P1 上是否存在可重复的差异？

本实验不重新比较旧 Gate 13R 的 `A*-R` 与 `D*L`，也不把旧结果与新采集数据合并为同一个确认性检验。

## 2. 冻结输入

- 直接复用 `Research/FormalScenarios/Gate11R_5pct/v1` 中 Gate 13R 使用过的 32 个 `shared-single-v1` 场景；
- 场景 JSON、随机种子、障碍、地形成本、agent 起点、共享目标、动态事件及预算均保持不变；
- 仅处理 `--shared` campaign；所有 heterogeneous cohorts 均排除；
- 输入文件须以 SHA-256 绑定，采集时不得重新生成场景。

## 3. 处理臂与主要比较

同期四处理臂固定为：

1. `BiA*-R`；
2. `LPA*`；
3. `C-FF`；
4. `IDFF`。

主要比较族固定为四个有方向的比值（分子/分母）：

1. `BiA*-R / C-FF`；
2. `BiA*-R / IDFF`；
3. `LPA* / C-FF`；
4. `LPA* / IDFF`。

P1 越低越好，因此比值 `< 1` 有利于分子算法，`> 1` 有利于分母算法。`BiA*-R / LPA*` 与 `C-FF / IDFF` 可作为描述性同族比较，但不加入主要四检验族。

## 4. 实验单位与样本量

- 独立推断单位：campaign（`n=32`）；
- 重复测量单位：同一 campaign 内的完整四算法 Williams block（`B=48`）；
- 总 blocks：`32 × 48 = 1,536`；
- 总算法样本：`1,536 × 4 = 6,144`；
- 一个 block 必须在一个 fresh Unity process 中按其冻结顺序完整运行四种算法；
- block 不完整时只能按预先冻结的 whole-block 技术 replacement 规则处理；不得逐算法 retry、resume、top-up、merge、skip 或 reorder。

`B=48` 是用户明确选定的固定设计参数，不由本批数据重新估计或提前停止。

## 5. 顺序与配对

复用 Gate 13R 的四处理 Williams 构造规则。基序列按处理臂索引为 `[0,1,3,2]`，随后循环平移，得到四行：

1. `BiA*-R, LPA*, IDFF, C-FF`；
2. `LPA*, C-FF, BiA*-R, IDFF`；
3. `C-FF, IDFF, LPA*, BiA*-R`；
4. `IDFF, BiA*-R, C-FF, LPA*`。

每 campaign 的 48 blocks 中每行恰出现 12 次，每算法在每个位置恰出现 12 次。四算法必须共享同一个场景实例、事件序列和 block 环境。

## 6. 主要端点 P1

P1 定义保持 Gate 13R 不变：

`P1 = dynamicHandlingTotalMilliseconds / scheduledEventCount`

单位为 `ms / scheduled event`。每个算法样本必须满足 P1 有限且严格大于 0；不使用 pseudocount，不以 0 替换缺失或失败。

## 7. 输出边界

必须同时输出：

- 四算法各自的 P1 原始几何均值、有效观测数和缺失数；
- 四个主要配对几何比、置信区间、原始 p 值与 Holm 调整结果；
- campaign 层面的配对汇总和缺失原因；
- 顺序平衡与完整性审计。

“原始几何均值”是描述性量，不替代 campaign 配对推断，也不得被单独当作确认性胜负检验。

## 8. 决策与边界

本实验只回答上述四个 P1 比较和算法级原始几何均值。任何综合赢家、M2–M5、工程性 tiebreak、跨 Gate 13R 合并结论或论文中的最终推荐，均需要另行冻结裁决树；不得依据采集中的可见结果临时修改。

## 9. 终止与授权

完成算法正确性、schedule、runner、provenance、输出 schema、raw-commit 与分析代码的冻结验证后，才可生成单次正式采集授权提示词。本文档本身不授权正式采集。

