# Gate 13R Non-Executing Preparation — Copy-Ready Authorization Prompt

The following prompt authorizes only Gate 13R non-executing preparation. It does not authorize creation of the formal output root or execution of the formal timing campaign.

```text
授权 Gate 13R 非执行准备：以已通过的 Gate 10R attempt 4、Gate 11R attempt 2、`gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`、`Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json`（SHA-256 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`）和 `Research/Gate12R_Readiness_Checkpoint.v1.json`（SHA-256 `93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d`）为唯一活动上游。

先冻结并测试 versioned Gate 13R specification、test design、amendment、formal config、provenance、Williams-block schedule、run/block identity、orchestrator、raw-byte storage preflight、execution-receipt validator、原子 checkpoint 和 fail-closed/no-auto-retry/no-resume 语义。正式设计必须保持双侧 95% CI 的 5% 相对半宽、无 hard cap、每个完整 Williams block 一个全新的 Unity Editor 进程、每样本完整 reset，以及 Gate 11R 的 53 scenarios / 74 campaigns / 212 eligible cells、确定性种子、canonical identity、排除规则和 Playable 映射不变。

按 Gate 12R 的无 cap 候选值冻结：32 个 shared-goal campaigns 每个 548 blocks，21 个 per-agent heterogeneous-goal campaigns 每个 768 blocks，21 个 grouped-field heterogeneous-goal campaigns 每个 400 blocks；合计 42,064 个 formal block processes 和 119,200 个 formal samples。内存门禁保持 `gate12r-sample-128mib-block-128mib-per-sample-v1`：单样本 retained managed 上限 128 MiB，完整 block 上限为 128 MiB × expectedSampleCount（两样本 256 MiB、四样本 512 MiB），完整 block working-set/private-memory 上限各 512 MiB。

将 166,572,888,336 raw bytes 的安全输出投影与 20 GiB reserve 合并，正式启动 raw-byte free-space 门槛冻结为至少 188,047,724,816 bytes；但本阶段只验证计算和边界，不得把 Gate 12R 的磁盘快照替代未来正式启动时的重新检查。预估串行 p95 运行时间 1,141,436.3340784 秒（317.07 小时 / 13.21 天）必须写入 config/readiness disclosure。

允许对 Gate 13R 非执行准备范围内已确认的 PowerShell 5.1、Unity、schema、路径、hash、receipt、checkpoint 或 orchestration 缺陷进行 versioned 自动修复与重试，直至非执行 readiness 全部通过；不得通过修改算法、场景矩阵、Williams 顺序、5% 精度、无 cap 候选 n、memory/reset/telemetry/排除规则或统计语义来取得通过。每个失败 attempt 必须独立保存 receipt、manifest、日志、哈希和 checkpoint。

只能运行静态、单元、Unity 编译、validation-only、fixture 和负向 fail-closed 测试。不得创建 `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1`，不得生成正式 execution receipt，不得启动任何 Gate 13R formal timing block/sample。通过后只生成 non-executing readiness checkpoint、冻结 config/provenance 和正式执行授权提示词，然后停止等待我的单独授权。

不得修改 Gate 10R attempts 1–4、Gate 11R 通过 bundle 与失败证据、Gate 12R attempts 1–4 及其 readiness/evidence、历史 cold/process-reuse roots、旧 Gate 11 retained bundle、Gate 12 历史归档、原始游戏脚本、原始场景或原始项目归档。
```
