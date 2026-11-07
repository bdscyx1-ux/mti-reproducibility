# Gate13R-AX2 P1 分析计划 v1

## 描述性原始几何均值

对算法 `a`，记 campaign `c`、block `b` 的严格正 P1 为 `P1[a,c,b]`。算法级原始几何均值定义为：

`GM[a] = exp((1/32) × Σ_c ((1/48) × Σ_b log(P1[a,c,b])))`

因为每 campaign 均固定 `B=48`，在无缺失时它等价于对该算法全部 1,536 个 P1 观测取 `exp(mean(log(P1)))`。输出单位为 `ms / scheduled event`，并同时给出 `eligibleN`、`missingN` 和缺失原因。不得使用 pseudocount。

该值保留 P1 的原始量纲，但它是描述性汇总；显著性推断不得把 1,536 个 block 当成 1,536 个独立 campaign。

## 配对推断

对主要比较 `a/b`：

1. 在每个完整 block 内计算 `log(P1[a,c,b] / P1[b,c,b])`；
2. 在每个 campaign 内对 48 个完整 block 的 log-ratio 求均值；
3. 以 32 个 campaign 均权作为独立单位，对 campaign mean log-ratio 求总体均值和标准误；
4. 指数变换得到几何比与置信区间。

四个主要比较构成一个 family-wise `α=0.05` 的检验族，p 值使用 Holm 调整。报告每个比较的双侧 95% 单项区间，并额外报告 Bonferroni-compatible `98.75%` 同时区间。若希望与原 Gate 13R 的 99% 展示完全并排，可追加 99% 保守区间，但不得替代冻结的 98.75% family-compatible 区间。

## 解释规则

- ratio `<1`：分子算法的 P1 较低；
- ratio `>1`：分母算法的 P1 较低；
- Holm 调整后 `p<0.05` 且同时区间不跨 1：该比较存在确认性 P1 差异；
- 其余情况只能报告估计方向和不确定性，不得强造统计赢家；
- 算法级原始几何均值的排序不自动构成统计赢家。

## 缺失和完整性

只有同一 campaign/block 中比较双方均有效时才形成配对。任何失败必须按结构化原因计数。不得逐算法补采；是否允许一次 whole-block replacement 必须在正式 execution contract 中预先冻结。

