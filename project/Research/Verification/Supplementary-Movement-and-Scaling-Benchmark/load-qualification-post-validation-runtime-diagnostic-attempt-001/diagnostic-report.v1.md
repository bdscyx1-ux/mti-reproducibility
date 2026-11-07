# Gate14Re-ME attempt-009 离线验收后运行时工程诊断

## 结论

- 离线必要原始数据验收：`PASS_OFFLINE_NECESSARY_RAW_VALIDATION`；耗时 107.495 秒，峰值工作集 86.5 MiB。它不是原 qualification terminal PASS，也未验证 delivery/typed-Parquet。
- 全程 1,147 个 fresh processes 用时 29.41 小时；972 个 algorithm lanes 阶段用时 26.79 小时，平均 36.29 lanes/hour。
- 最后一个滚动小时完成 13 个 lanes，与用户观察的约 12–13 lanes/hour 一致。
- 进程墙钟与 inclusive lane-body 的 Pearson 相关为 0.999769；P95 尾部重合率为 98.0%。尾部主要发生在已直接测得的 lane-body 区间，而不是进程间隙；但纯算法计算、Unity 启动、退出和 lane 内仪器/序列化/I/O 不能被当前 instrumentation 分别识别。
- 冻结长尾描述量的多数指向：`LPA*`。这只是运行时工程长尾，不是算法效果排名或赢家。
- 正式 ST 的最终 B 尚未冻结。按当前 48-cell、六算法、B=36 最小平衡单位，含 20% 头寸的工程预算为 11.695 天；7 天门：触发。

## 各算法进程墙钟分布（秒）

| 算法 | n | P50 | P90 | P95 | P99 | 最大 | P95/P50 | 超 pooled P95 比例 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A*-R | 162 | 31.641 | 225.263 | 269.397 | 315.770 | 328.518 | 8.514 | 0.0% |
| BiA*-R | 162 | 46.622 | 391.173 | 494.117 | 607.228 | 631.202 | 10.598 | 9.9% |
| C-FF | 162 | 31.481 | 73.925 | 89.314 | 110.424 | 110.926 | 2.837 | 0.0% |
| D*L | 162 | 49.804 | 396.993 | 466.910 | 998.534 | 1452.583 | 9.375 | 9.9% |
| IDFF | 162 | 31.582 | 76.779 | 79.746 | 89.859 | 116.278 | 2.525 | 0.0% |
| LPA* | 162 | 49.914 | 397.768 | 457.209 | 972.843 | 1462.082 | 9.160 | 10.5% |

## 慢负载单元与尾段

core G×N×F 单元按 pooled P50 进程墙钟最慢的前 12 个见 `slow-gnf-cells.v1.json`；全部算法×region×G×N×F 见 `algorithm-gnf-runtime-cells.v1.csv`，最慢 30 条 lane 见 `slowest-lanes.v1.csv`。算法×core 单元只有 n=3，不把其 P99 当稳定总体估计。

结构负载与 inclusive lane-body 的描述性相关：log(operation rows)=0.875055，G=0.461979，N=0.81963，F=0.34192。这些相关不构成因果。

early/middle/late 与 G×N×F 的执行顺序高度混杂，最后 18 个 superblocks 又全部是 G=256、N=512、F=225 stress。缺少在相同 algorithm×region×G×N×F 上跨足够时间段的随机重复，因此不能把尾段变慢直接归因于热节流、缓存、杀毒、磁盘或系统退化。

## 可识别与不可识别的时间部分

- 可直接识别：process wall、strict-serial inter-process gap、RunnerV3 inclusive lane-body duration。
- 不可分别识别：纯算法 compute、Unity/startup、exit/finalization；当前数据没有可信绝对 workloadStartUtc/workloadEndUtc。
- lane-body 本身包含 grid 构造、planner 初始化/查询/repair、参考 oracle、instrumentation、状态/资源采样和 raw 写盘，因此不得把 lane-body 全部称为算法计算。
- process-resource 的 private/working-set/peak-working-set 样本为结构性零，且没有温度、CPU 频率、杀毒或磁盘吞吐时间序列，所以这些只能列为候选解释。

## 验收为什么原来很慢

旧 validator 对 7,126,405 个 source-bound rows 逐行调用文件 SHA-256，而实际只有 163 个不同来源；同时 `load_tables` 将 7,126,405 个行字典及 RowEnvelope 全部保留在内存。其 Runner method 还硬编码为 V2，而本次真实执行是 V3。离线 v2 改为每个 distinct path 只规范化/哈希一次并流式丢弃行，7.24 GB、约 712.6 万 source-bound rows 的必要验收在约 106 秒完成。

## 科学与决策边界

这是事后工程诊断，不是正式效果比较；不据此自动删除算法、改变科学问题、缩小样本、修改停止规则或启动 ST/MQ/MT。若 7 天门触发，`st-major-simplification-candidate.v1.json` 仅是一份待用户明确授权、重新功效论证并先验冻结的候选。六算法 MQ 仍是未来可能的独立研究，绝不是 MT。
