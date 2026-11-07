# Gate 13R P1–C5 独立专项确认性研究：冻结统计分析计划 v1

## 1. 研究问题与边界

本研究只回答一个确认性问题：在冻结的 32 个 shared-goal campaign 有限矩阵内，C-FF 与 IDFF 哪一个在 P1（`dynamicHandlingMillisecondsPerScheduledEvent`，越低越好）上更优。研究不外推至未纳入的 campaign，不分析 M1–M5，不执行 Gate 14R，也不与 Gate 13R-PR2 attempt 4 的原始数据合并。

## 2. 设计与独立单位

- 双侧显著性水平：`α = 0.05`。
- 确认性检验族：一个预先指定的 P1–C5 对比；不需要多重性校正。
- 最小检测差异：对称乘法比值 `1.10`，即真比值 `IDFF/C-FF = 1/1.10` 或 `1.10`。
- 目标把握度：`90%`。
- 固定 campaign：32 个；对目标有限矩阵等权。
- 每个 campaign：50 个全新成对 blocks，AB 25 个、BA 25 个。
- 总计：1,600 个 Unity 进程、3,200 个算法样本。
- 独立实验单位（正式 `n`）：一个全新 Unity 进程内完成的 C-FF/IDFF 成对 block。算法样本是同一 block 内的配对观测，不作为两个独立单位。
- 固定分层：`campaign × AB/BA order`，共 64 层，每层 25 个独立 blocks。

冻结前确定性模拟从每 campaign 50 blocks 开始。仅当两个效应方向中较小的模拟把握度之单侧 95% Wilson 下限低于 0.90 时，才以每 campaign 增加 2 blocks 的方式向上调整；不得向下减少。

## 3. 数据完整性与纳入规则

正式分析必须同时满足：完整冻结日程、1,600 个互不复用的复合 Unity 进程身份、每 block 恰有两个按冻结顺序完成且通过哈希验证的样本、所有硬内存门禁通过、没有注入故障、没有实验重跑/补样/替换/重排、原始提交清单与冻结 SHA-256 一致。

任何计划 block 缺失、重复、不合格、身份冲突或哈希不一致时：

1. 不删除该 block 后继续分析；
2. 不自动补样、替换、重跑或重排；
3. 确认性结果输出为 `NOT-ESTIMABLE / USER-ACTION-REQUIRED`；
4. 不产生方向性优胜结论。

## 4. 主要估计量

对每个合格 block 计算：

`d = ln(P1_IDFF / P1_CFF)`。

在每个 `campaign × order` 层内计算 block 对数比均值。主要估计量是 64 个层均值的等权平均：

`theta_hat = (1/64) * sum_h mean(d_h)`。

主要效应以几何均值比 `R = exp(theta_hat)` 报告。`R < 1` 表示 IDFF 的 P1 较低，`R > 1` 表示 C-FF 的 P1 较低。

## 5. 不确定性、检验与判定

分层方差估计为：

`V_hat = sum_h (1/64)^2 * s_h^2 / n_h`。

自由度使用 Welch–Satterthwaite 近似。构造双侧 95% t 置信区间并报告双侧精确 p 值。由于确认性检验族只有一个预先指定的对比，不作多重性校正。

冻结判定：

- 95% CI 全部低于 1：`IDFF-LOWER-P1-CONFIRMED`；
- 95% CI 全部高于 1：`CFF-LOWER-P1-CONFIRMED`；
- 95% CI 包含 1：`UNRESOLVED`；
- 任一完整性门禁失败：`NOT-ESTIMABLE / USER-ACTION-REQUIRED`。

“统计确认”不等同于工程重要性。结果同时报告相对差异、95% CI、双侧 p 值、block 数、campaign 数和每层样本量。

## 6. 顺序与稳健性输出

AB 与 BA 分层估计、32 个 campaign 的描述性估计及其区间仅用于诊断一致性，不改变主要确认性判定，也不构成新的检验族。不得依据这些输出选择性删除、补样或重排。

## 7. 两阶段执行边界

- Phase A：只执行冻结日程的数据采集与原始完整性提交。
- Phase B：分析实现必须在 Phase A 启动前冻结，但在原始数据完成后仍需单独授权才可执行。
- Phase B 只读加载新的专项原始根；不得写入原始根。
- Gate 14R 与 M1–M5 均保持未授权。
