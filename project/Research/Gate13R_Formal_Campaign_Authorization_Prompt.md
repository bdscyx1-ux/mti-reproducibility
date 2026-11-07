# Gate 13R Formal Campaign — Copy-Ready Authorization Prompt

This file is a future authorization template only. Its existence does not authorize Gate 13R formal execution. The formal output root and formal execution receipt must remain absent until the user sends the complete authorization text below in a new message.

```text
授权 Gate 13R 正式 campaign：以已通过并封存的 Gate 13R 非执行准备为唯一直接上游，并严格绑定以下冻结输入：

- `Research/Gate13R_Formal_Campaign_Config.v1.json`，SHA-256 `af5a164cdabeeff08cd6cd00b21ecd732fcbdc7f51be3454f99aaf65b2ef5109`；
- `Research/Gate13R_NonExecuting_Preparation_Provenance.v1.json`，SHA-256 `c1f8d4b4a8216b2e7f2dbdad7d49decbb77da38087f4c8c91a1366cd4d2963b8`；
- `Research/Gate13R_Formal_Williams_Block_Schedule.v1.jsonl`，SHA-256 `dc460db08f501ef39869de29602cc0caf15106a264f930b55eb1875336c91aa6`；
- `Research/Gate13R_Formal_Williams_Block_Schedule_Manifest.v1.json`，SHA-256 `070fc787df97c63a808c9a8abd8179d708a361a1c83d9cdec107f2aa6ed1182b`；
- `Research/Gate13R_Readiness_Amendment.v1.json`，SHA-256 `72d6ed97aebcf652d6796a72a3794ff11b39ed166271eb9ee8d87e8205984db7`；
- `Research/Verification/Gate13R_NonExecuting_Preparation/v2/FinalAudit.summary.json`，SHA-256 `498cd50b23d85a2e3686010b346a77417c6fdb32c3146d95f49b8818c8741cb7`；
- `Research/Gate13R_NonExecuting_Readiness_Checkpoint.v1.json` 及 `Research/Gate13R_NonExecuting_Preparation_Evidence_Manifest.v1.json`，以正式启动前现场重新计算得到的精确 SHA-256 为准，并在 execution receipt 中逐项绑定。

在创建任何正式输出前，先只读核验上述全部冻结输入、Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R readiness、Gate 11R bundle、Gate 12R memory-policy amendment、Playable bundle 映射及非执行 preparation evidence manifest 的存在性、状态、字节数和 SHA-256；核验 Gate 13R non-executing readiness 状态必须为 `GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED`。任一哈希、计数、路径、身份或状态不一致时 fail closed，不得修复冻结输入、不得创建正式根、不得启动 Unity。

正式设计固定为双侧 95% CI 的 5% 相对半宽、无 hard cap、每个完整 Williams block 启动一个全新的 Unity Editor 进程、进程内严格按冻结 Williams 顺序运行 2 个或 4 个算法样本、每个样本完整 reset、每算法在同一进程内最多一次。Gate 11R 的 53 scenarios、74 campaigns、212 eligible cells、确定性种子、canonical identity、排除规则、campaign profile、algorithm preset 和 Playable Unity Scene 映射保持不变。正式样本量固定为：32 个 shared-goal campaigns 每个 548 blocks，21 个 per-agent heterogeneous-goal campaigns 每个 768 blocks，21 个 grouped-field heterogeneous-goal campaigns 每个 400 blocks；总计 42,064 个 Williams-block 进程和 119,200 个样本。

内存门禁保持 `gate12r-sample-128mib-block-128mib-per-sample-v1`：每样本 retained managed-memory 上限 128 MiB；完整 block 上限为 128 MiB × expectedSampleCount（两样本 256 MiB、四样本 512 MiB）；完整 block working-set 和 private-memory 上限各 512 MiB。不得放宽阈值、改写 telemetry、删减 reset 或改变异常/中断语义。

在正式根创建前，必须重新执行 receipt、hash、路径、环境、电源、热状态、PSAPI/CIM telemetry、Unity/lock hygiene 和 raw-byte storage preflight。正式启动时目标卷实时可用原始字节必须不少于 188,047,724,816 bytes；Gate 12R 或非执行准备阶段的磁盘快照不具授权效力。应在 receipt 中披露串行 p95 预算 1,141,436.3340784 秒（约 317.07 小时 / 13.21 天），并记录正式启动时的实际 UTC 时间、主机、OS、CPU、RAM、GPU、Unity 路径/版本、项目绝对路径、输出根绝对路径和可用字节。

全部 preflight 通过后，才允许创建唯一正式输出根 `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1`，并以 create-new、versioned、原子写入的正式 execution receipt 将其精确绑定到上述 config、schedule、provenance、amendment、readiness checkpoint、evidence manifest、正式设计、主机环境和输出根。不得复用、覆盖或混入任何历史 cold-process、旧 process-reuse、pilot、validation、failed-attempt 或 non-formal 数据。

按冻结 schedule 严格执行 74 campaigns / 42,064 Williams blocks / 119,200 samples。每个 block、sample、summary、checkpoint 和完成标记必须具有独立 canonical identity、hash 和 provenance。进程内任一样本失败、结构输出不一致、reset/telemetry/memory 门禁失败、Unity 非零退出、输出缺失、哈希不一致或环境越界时立即 fail closed：原子保存 failure receipt、checkpoint、部分输出 manifest、日志、当前 campaign/block/position/algorithm/run ID、完成计数和原始字节数后停止，不得启动下一 block。

禁止自动 retry，禁止自动 resume，禁止补齐失败 block，禁止用后续 attempt 合并、覆盖或重新解释部分正式结果。失败后的任何 retry/resume、设计变更或新 attempt 必须由我另行明确授权。不得修改冻结输入、Gate 10R attempts 1–4、Gate 11R bundle/失败证据、Gate 12R attempts/readiness/evidence、历史 cold/process-reuse roots、旧 Gate 11 retained bundle、Gate 12 历史归档、原始游戏脚本、原始场景或原始项目归档。

正式 campaign 全部完成后，先只生成 Gate 13R completion checkpoint、完整输出 manifest、hash/provenance 审计、计数/结构完整性结果和 Gate 14R 输入候选清单；不得在没有单独授权的情况下启动 Gate 14R 正式分析、改变排除规则、进行选择性补跑或删除原始正式输出。
```

