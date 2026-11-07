# Gate 13R 严格串行 10% 正式 Campaign 授权提示词 v2

> 本文件只是下一步可复制的授权模板；文件存在本身不构成正式执行授权。当前不得创建正式 execution receipt、正式输出根或正式 timing 样本。

```text
授权 Gate 13R 严格串行 10% 正式 campaign，并明确接受当前实测证据给出的串行运行时间包络：p50 约 64.830802096 小时、p95 约 83.904223147 小时；为稳定完成，我接受建议的 96 小时连续维护窗口。旧 36 小时硬墙钟限制不再适用于本次严格串行正式执行。

唯一活动正式设计为 `gate13r-one-fresh-unity-process-per-williams-block-10pct-uncapped-serial-v2`。必须以以下冻结文件和 SHA-256 为唯一输入：

- `Research/Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json`
  SHA-256 `faaec5613a2625aee462038305310e229c7cf8fdf67edb800a0b3eb256f1a300`
- `Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json`
  SHA-256 `8bf87ae8c206355930dd6b720756216ef74052ce9d0551680e3a91933a970dc9`
- `Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl`
  SHA-256 `d9300cce732e12a7b90ec43ad9d5f8fe52cbad58da713c25879754eb31ea0ead`
- `Research/Gate13R_Serial_10pct_Formal_Preparation_Provenance.v2.json`
  SHA-256 `409b79506b006378c79a0cb777909e0157b9917a2e439c90d59d0679b2340f7b`
- `Research/Run-Gate13RSerial10pctFormalCampaignV2.ps1`
  SHA-256 `8bdd8f7b1edc8fc84f8ef35099f103fd55f789f352e47537874f2095a6116770`
- `Research/Run-Gate13RSerial10pctFormalBlockV2.ps1`
  SHA-256 `b4827065ec609f148fa0dd58959cb79e5c9bf54f35fd7aa8b64ef172d820fe1b`
- `Research/Verification/Gate13R_Serial_10pct/v9-v2-final/FinalAudit.summary.json`
  SHA-256 `16ffdd5e8a92eb41da07e01017dfdc9ec0c0bea8bea3e3dcf1e7b01892654774`
- `Research/Gate13R_Serial_10pct_Readiness_Checkpoint.v2.json`
  SHA-256 `ac234a0a7977c639cf190c2213f99a5c8a36b55f1de0368ff2b29e89d347c89c`；授权时必须重新核验，若不一致，必须在创建 receipt/root 前 fail closed。

正式规模固定为完整 74-campaign 矩阵、10% per-campaign 相对 95% CI 半宽、无 hard cap、11,160 个 Williams-block processes、31,536 个 samples；候选 blocks/campaign 固定为 shared 144、per-agent heterogeneous 204、grouped-field heterogeneous 108。不得降低矩阵、精度、样本量、Williams 平衡、reset、telemetry、内存门禁或排除规则来缩短时间。

执行拓扑必须严格串行：任意时刻最多一个 Unity Editor；每个完整 Williams block 启动一个全新 Unity Editor 进程；一个进程最多执行一个 block；block 内按冻结 Williams 顺序运行 2 个或 4 个算法；每个样本完整 reset；禁止 2/3/4 lane fallback，禁止跨 block/campaign 复用进程，禁止混合任何并发或旧 cold-process/process-reuse 数据。

先创建独立、versioned、一次性、原子写入的 formal execution receipt，精确绑定上述 config、schedule manifest、schedule、provenance、orchestrator、block wrapper、readiness checkpoint、正式输出根 `Research/FormalRuns/Gate13R_Serial_10pct/v2` 和本授权原文。receipt 必须明确写入 NO-AUTO-RETRY、NO-AUTO-RESUME、NO-PARTIAL-MERGE、STRICT-SERIAL-ONE-UNITY-MAXIMUM，并在使用后不可再次消费。

创建正式输出根之前，重新运行全部 receipt/hash/路径隔离/Windows PowerShell 5.1/Unity executable/项目锁/环境/电源/热状态/PSAPI+CIM telemetry/许可证和原始字节存储 preflight。启动时 H: 可用原始字节必须不少于 86,835,248,752；本轮 validation-only 快照不得授权正式启动。所有门禁全部通过后，才允许原子创建 `Research/FormalRuns/Gate13R_Serial_10pct/v2` 并开始正式 campaign。

许可证门禁要求日志必须出现 `Serial number assigned to:`；出现 `No valid Unity Editor license found` 或 `License is not active (com.unity.editor.headless)` 时必须在下一个 block 启动前 fail closed。单个样本、block、hash、reset、telemetry、存储或环境门禁任一失败时，保存原子 checkpoint、failure receipt、部分输出 manifest、进程身份、日志和已有文件 SHA-256 后立即停止；禁止自动 retry/resume，禁止补齐失败 block，禁止把不同 attempt 合并。

完整保留并排除四 lane v16、三 lane v1、serial preparation v1 以及所有更早 cold/process-reuse 失败或部分输出；不得修改 Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R v4、原始脚本、原始场景、Playable bundle 或历史 evidence roots。正式 campaign 完成后只生成 Gate 13R completion checkpoint、manifest、hash/provenance 和 Gate 14R/15R 前置审阅材料；不得自动进入 Gate 14R、Gate 15R 或可视化录制。
```
