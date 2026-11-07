# Gate14Re-ME attempt-011 qualification 后运行时工程诊断

## 证据状态

- qualification：`PASS_QUALIFICATION_TERMINAL`；独立流式验收覆盖 2,395,933 行并通过 typed-Parquet 全量值、类型和顺序往返，耗时 177.051 秒。
- 全程 775 个 fresh processes 用时 7.434 小时；756 个 lanes 阶段用时 6.756 小时，平均 111.895 lanes/hour。
- 最后一个滚动小时完成 81 个 lanes。
- 冻结的五项长尾描述量结论：`D*L`（strict plurality across the five predeclared long-tail descriptors (4/5)）。这是运行时间工程描述，不是算法效果排名或赢家。

## 各算法进程墙钟分布（秒）

| 算法 | n | P50 | P90 | P95 | P99 | 最大 | P95/P50 | P99/P50 | 最大/P50 | 超 pooled P95 | matched block 最慢频率 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A*-R | 126 | 25.868 | 40.546 | 40.713 | 43.768 | 55.289 | 1.574 | 1.692 | 2.137 | 0.8% | 1.6% |
| BiA*-R | 126 | 31.476 | 49.700 | 52.719 | 60.971 | 62.011 | 1.675 | 1.937 | 1.970 | 8.7% | 25.4% |
| C-FF | 126 | 25.678 | 31.672 | 34.713 | 39.875 | 40.616 | 1.352 | 1.553 | 1.582 | 0.0% | 2.4% |
| D*L | 126 | 32.985 | 52.562 | 64.009 | 103.267 | 113.080 | 1.941 | 3.131 | 3.428 | 10.3% | 31.0% |
| IDFF | 126 | 25.803 | 31.609 | 31.674 | 34.673 | 40.517 | 1.228 | 1.344 | 1.570 | 0.0% | 4.0% |
| LPA* | 126 | 34.427 | 51.371 | 64.268 | 101.922 | 113.157 | 1.867 | 2.961 | 3.287 | 10.3% | 35.7% |

## 慢 G×N×F 与执行尾段

慢 pooled G×N×F 与慢 algorithm×G×N×F 单元见 `slow-gnf-cells.v2.json`，全部具名单元见 `algorithm-gnf-runtime-cells.v2.csv`，最慢 30 条 lane 见 `slowest-lanes.v2.csv`。core 的 algorithm×G×N×F 每格只有 n=3，因此只报告 n、实际范围、P50 和最大值，不把 P99 当稳定总体估计。

early/middle/late、近期窗口及同算法同 G×N×F 的顺序敏感性见 `order-tail-sensitivity.v2.json`。冻结 schedule 的负载组成与执行顺序存在混杂，随时间漂移不等于系统退化因果。热节流、缓存、杀毒、磁盘或内存压力缺少直接结构证据，只能列为候选解释。

## 时间拆分可识别性

- process wall 与 inclusive lane-body 的 Pearson 相关为 0.992141；两者 P95 尾部重合率为 97.4%。
- 可直接识别：process wall、strict-serial inter-process gap、RunnerV4_2 inclusive lane-body。
- 不可分别识别：纯算法 compute、Unity/startup、exit/finalization，因为没有可信绝对 workloadStartUtc/workloadEndUtc；不得以残差猜测。
- inclusive lane-body 还含 grid 构造、planner 建立、oracle/cache 使用、instrumentation、资源采样、序列化与 raw 写盘，不能整体称为纯算法计算。

## 正式 ST 参数化预算与 7 天门

按 B=36 的当前最小参数行，点估计 64.341 小时，保守估计 69.578 小时，含 20% 运行头寸为 83.493 小时（3.479 天）；168 小时门：未触发。这只是工程预算，不是 B 决策或执行授权。

## 边界

这是 qualification 后的事后工程诊断，不是正式效果比较；未读取算法观测或质量指标，未估计效果方向，未排名、加权或裁决赢家，也不据此自动删除算法、改变科学问题、缩小样本、修改停止规则或启动 ST/MQ/MT。迁移包仍未构建。
