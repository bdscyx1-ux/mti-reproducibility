# Gate14Re-ME G×N×F 最高水平降载：第一轮对角筛选

状态：`PASS_TIMING_ONLY_SCREENING; SUPERSEDED_FOR_FINAL_RECOMMENDATION_BY_BALANCED-AXIS_REDESIGN-V2`

## 不变边界

- 保留 3×4×4 = 48 个 core 负载单元、每单元 3 个 qualification seed、18 个 high-corner context strata、6 个算法的配对结构、Williams 顺序和严格串行 fresh-process 执行。
- 仅替换 G、N、F 各自的最高水平；全部较低水平保持不变。
- attempt-009 的 evidence、measured、delivery 和封存数据均未写入或改判。
- 本轮只读取 G/N/F、算法分层标识和进程墙钟/进程间隙；未读取算法效果 observation、D1–D7 效应、排名或赢家。

## 第一轮结果

| 方案 | Gmax | Nmax | Fmax | B=36 点估计 | 保守+20% | 相对旧预算 | 7 天门 |
|---|---:|---:|---:|---:|---:|---:|---|
| 旧设计参照 | 256 | 512 | 225 | 199.887 h | 280.687 h / 11.695 d | — | 未通过 |
| MILD | 224 | 384 | 196 | 163.799 h | 229.996 h / 9.583 d | -18.060% | 未通过 |
| BALANCED（第一轮） | 192 | 256 | 144 | 128.557 h | 180.884 h / 7.537 d | -35.557% | 未通过 |
| STRONG | 160 | 192 | 100 | 107.130 h | 150.588 h / 6.275 d | -46.350% | 通过 |

按预冻结规则，三组“同步同档下降”的候选中只有 STRONG 穿过 7 天预算门。但它把三个最高水平都压到非常接近次高水平，会不必要地同时牺牲三个尺度轴的顶端间距。因此，本轮只作为筛选证据，不作为最终科学设计建议；另行冻结第二轮“各轴平衡跨度”方案，在仍只改变最高水平的前提下寻找更好的运行时—尺度辨识折中。

## 模型边界

候选值没有被 attempt-009 实际测量。估计是在旧 48-cell 因子网格包络内，对每个算法的进程墙钟 P50/maximum 做 log-duration 对 log2(G/N/F) 的多线性内插；它只能用于规划，不能证明新高锚点的动态范围、measurement floor、geometry/oracle 或 resource ceiling。任何获批的新取值都必须重新冻结合同并从 ordinal 0 运行全新 qualification。
