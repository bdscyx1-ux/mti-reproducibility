# Gate 13R — 36 小时墙钟约束与旧 Gate 13 对照

记录时间：2026-10-08（Asia/Shanghai）

状态：`AUTHOR-WALLCLOCK-DECISION-RECORDED / REDESIGN-SELECTION-PENDING / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## 结论

用户已把 Gate 13R 正式 campaign 的端到端硬墙钟上限从 48 小时改为 36 小时。现有 5% 无 cap Gate 13R config 的串行 p95 投影为 317.07 小时，不能在该上限下启动。现有 config、schedule、readiness 和 authorization prompt 均保持字节不变，作为“已通过但从未执行的旧 readiness 设计”保留；后续必须建立新的 versioned 设计、并发 pilot、config、schedule 和 readiness，再单独申请正式执行授权。

36 小时从正式启动 preflight 开始，到 terminal formal checkpoint 原子写入结束；包括 preflight、未来设计要求的 warm-up、全部正式 blocks、manifest/hash finalization 和 terminal checkpoint。正式 campaign 仍禁止自动 retry/resume。

## 为什么 Gate 13R 比旧 Gate 13 大很多

| 项目 | 旧 Gate 13 | 当前 Gate 13R | 影响 |
|---|---:|---:|---|
| campaigns | 74 | 74 | 矩阵规模没有增加 |
| 精度目标 | 10% relative half-width | 5% relative half-width | 仅此变化在同一方差下就使样本量约乘以 3.816 |
| hard cap | 148 | 无 cap | 新版不会为了运行时间截断所需独立单位 |
| 方差输入 | pilot `sigma_log` 点估计 | 单侧 90% `sigma_upper`，并取 cohort 内 marginal/paired 最坏项 | 新版更保守 |
| 独立统计单位 | 单个算法样本；每样本一个新 Editor 进程 | 完整 Williams block；每 block 一个新 Editor 进程 | 口径不同，不能直接把 samples 当 processes 对比 |
| 每个进程的样本 | 1 | 共享目标 4；另外两类 2 | 119,200 samples 中包含 block 内相关、配对观测 |
| OS/Unity 进程数 | 15,056 | 42,064 | 2.794 倍 |
| 算法样本数 | 15,056 | 119,200 | 7.917 倍 |
| 串行 p95 投影 | 67.67 h | 317.07 h | 4.686 倍 |

精度项使用相同方差时的理论比例为：

```text
n(5%) / n(10%)
= [ln(1.10) / ln(1.05)]^2
= 3.816
```

旧 Gate 13 使用四个 family 的 `sigma_log` 点估计，正式 `n` 为 shared 52、per-agent 148、grouped 52。当前 Gate 13R 使用 Gate 12R fresh block-process pilot，在每个 campaign/algorithm 的 marginal log SD 和每个 paired contrast 上计算单侧 90% 标准差上界，再取 cohort 内最坏项；得到 shared 548、per-agent 768、grouped 400 个独立 blocks。它回答的是“每个 campaign 都达到 5% 精度”的更强问题。

运行时间并非按 sample 数线性膨胀到 7.917 倍，因为 process-reuse 让一个 Editor 进程完成整个 block。旧 Gate 13 每个 fresh process 的 p95 是 16.18 秒；当前 Gate 13R 按 cohort 的 block p95 是 35.43、23.29、17.21 秒，加权约 27.13 秒。于是运行时间变化可近似拆为：

```text
进程数量 2.794 倍 × 每进程加权 p95 约 1.677 倍 ≈ 总 p95 4.686 倍
```

因此，大幅增加不是重复计数错误：主要来源是 5% 精度、保守方差上界、每 campaign 最坏项保护，以及 block 内 2/4 个配对样本的新计数口径。process-reuse 反而已经减少了相对于 119,200 个样本的 Editor 冷启动次数。

## 36 小时下的只读候选投影

以下数值只按 Gate 12R 已冻结的 `sigma_upper` 和 block p95 重算，尚未经过并发 Unity pilot，因此不是可执行 config。

| 每 campaign 精度 | shared / per-agent / grouped blocks | 总 blocks | 总 samples | 串行 p95 | 为把理想 p95 压到不高于 27 h 所需 lanes | 理想并行 p95 | 36 h 内所需最低效率 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 5% | 548 / 768 / 400 | 42,064 | 119,200 | 317.07 h | 12 | 26.42 h | 73.4% |
| 7.5% | 252 / 352 / 184 | 19,320 | 54,768 | 145.65 h | 6 | 24.28 h | 67.4% |
| 10% | 144 / 204 / 108 | 11,160 | 31,536 | 83.90 h | 4 | 20.98 h | 58.3% |
| 15% | 68 / 96 / 52 | 5,284 | 14,920 | 39.68 h | 2 | 19.84 h | 55.1% |

推荐但尚未冻结的方案是：维持完整 74-campaign 矩阵，把每 campaign 精度改为 10%，使用 4 个相互隔离的 Unity Editor lanes，并要求新的 readiness p95 不超过 27 小时，给 36 小时硬上限留下 25% 余量。相比 5% + 12 lanes，它更适合 32 GiB RAM 主机，也较不容易让 CPU、存储、温度和 Editor 启动竞争污染 timing。

四 lane 不能直接启动正式实验。Unity 同一项目受 `UnityLockfile` 限制，每 lane 必须有独立、哈希绑定的项目副本；还必须通过新的并发 pilot，验证结构 exact-match、lane/position/cohort 平衡、CPU affinity/CCD、温度/功耗、I/O、后台负载、并行效率和 tail runtime。只有这些证据证明端到端 p95 满足新的 readiness 门槛后，才能生成新正式 config 并请求单独授权。

## 当前授权边界

- 已记录：36 小时硬墙钟上限。
- 未决定：5%、7.5%、10%、15% 或重新定义 primary estimand。
- 未授权：并发 pilot、任何新 Gate 13R config/schedule、formal root、formal receipt、formal timing campaign、Gate 14R/15R。
- 旧 5% config 的 formal authorization prompt 不得继续使用。
