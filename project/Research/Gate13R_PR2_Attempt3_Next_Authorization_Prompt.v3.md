# Gate 13R-PR2 formal attempt 3 — active v2 monitored, bounded-recovery authorization prompt v3

复制以下正文作为下一条授权消息。发送前应先审阅 active v2 monitoring/recovery readiness；本文件本身不构成执行授权。

---

授权 Gate 13R-PR2 formal attempt 3 的一次受控、严格串行、两阶段提交执行，并启用已验证的每小时盲化进度报告与分阶段受限软件恢复；不授权 Phase-B 正式统计分析，不授权 Gate 14R。

## 一、唯一活动 readiness、终审与哈希

1. 以以下 MP2 与 active v2 monitoring/recovery 链作为本次 formal attempt 3 的唯一 readiness 链：

   - `Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json`，SHA-256 `88333a15f3e5deb0eb7998bf15a5f1976df5de9a0382350016aa8623ad4680f8`；
   - `Research/Gate13R_PR2_MP2_Final_Validation_Audit.v1.json`，SHA-256 `bbf41f14682a85e061799a5cb9daed2122d6f8631a878b22bb714ede161bbe9e`；
   - `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json`，SHA-256 `526a7fc6ff67e3c2ac0201f1f88dcc08b9af155e0a25d0332fd4aab189aa809c`；
   - `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Terminal_Audit.v2.json`，SHA-256 `8cb90b20072f0abf1855a2d082a3d08e7865b995b0fac61341ae61a924e81789`；
   - `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Evidence_Manifest.v4.json`，SHA-256 `3667055786238faa58d196f847fa49ba4ab531ce084c259e8f3333ece6ea8dbe`。

2. `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v1.json`、`Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Terminal_Audit.v1.json`、`Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v2.md` 以及 V1 monitor/wrapper 仅作为 superseded 历史证据保留，禁止用于启动、监控或恢复 formal attempt 3；不得修改、覆盖、删除或重新解释其状态。

3. 只允许使用以下 active formal-attempt-3 candidate artifacts：

   - `Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json`，SHA-256 `c8d3e9965ae72798e2366c0187a96e578df306bb68196f54039c421672b78042`；
   - `Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json`，SHA-256 `2cad63b1c89608b2053552ef8c1261603f81231365689ba232d950fc279c4f62`；
   - `Research/Gate13R_PR2_MP2_Provenance.v4.json`，SHA-256 `0f2c666ac4dc324687073fcdd913833e4d7d72dc8ad88bfaa5b1184bcfb7c37f`；
   - `Research/Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json`，SHA-256 `f1b556b3052c865640651bec58751a61dd3823422027fcbef0bf4fdd3a25dd8a`；
   - `Research/Gate13R_PR2_MP2_Memory_Policy_Registry.v2.json`，SHA-256 `1070821ef6264510eb2e7427d7887aaca08bb5d2e7854d48f61a6c8e1285490f`；
   - `Research/Gate13R_PR2_MP2_Scenario_Policy_Mapping.v2.json`，SHA-256 `5dd5daf640831ea49d5fa9e0bb1a318e71669ee9e426bf346f7eebc36f0c5055`；
   - `Research/Gate13R_PR2_MP2_Schedule_Policy_Overlay.v2.jsonl`，SHA-256 `c87cc7eab158dc7a111867364b9c06c2314f44c644ef2a4b8e33348bd1876d13`；
   - `Research/Run-Gate13RPR2MP2FormalBlockV3.ps1`，SHA-256 `fc0c42b858afb8e8d80c6f10544a0d7fb75694ae8c57910d205cea721731ff13`；
   - `Research/New-Gate13RPR2MP2BlockPlanV4.py`，SHA-256 `11365fb3c694ae2fab6c9d3c3cb3c93f3cbe3e6f2f7a30373730f5a236ce8785`；
   - `Research/Gate13RPR2MP2MemoryPolicyV2.psm1`，SHA-256 `7f9e7252fc4a158573ca67f54baa7fa4a0d0c981f3240aa706d46a96d283ffc4`；
   - `Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV5.cs`，SHA-256 `21f86b21a49c936edd5e65fde750d269a54be984186d9c802cbc2804b2691c75`。

4. 底层 PR2 v2 schedule/config 必须保持字节不变：

   - `Research/Gate13R_PR2_Formal_Campaign_Config.v2.json`，SHA-256 `87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e`；
   - `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl`，SHA-256 `df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae`；
   - `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json`，SHA-256 `b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724`。

5. 监控与恢复只允许使用以下 active artifacts：

   - `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Specification.v1.md`，SHA-256 `7760fe037563425ea29239eca9aa123919e9082f0762d3901bfd5a8f77cd1ccc`；
   - `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Implementation_Repair.v2.md`，SHA-256 `0822efd540be52f58e5f190dd6280328871cad3a2070d13a8a5574edeca1bd66`；
   - `Research/Gate13R_PR2_Attempt3_Monitoring_Config.v2.json`，SHA-256 `b88da3901a2c2cc494140a8cd2e3f37b546f637935bc940a8941a850d42770c6`；
   - `Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v1.json`，SHA-256 `2aa5d0e5a11a1e38a05d9e3e82a65dc227e98b953cc4e2678e73eaa96aec1a3d`；
   - `Research/Gate13R_PR2_Attempt3_Operational_Status_Schema.v1.json`，SHA-256 `3aff68ac8e041838283f8e28b72b388ab4de50abe3b357f59bb3e3597f74d89b`；
   - `Research/Gate13R_PR2_Attempt3_Progress_Snapshot_Schema.v1.json`，SHA-256 `5131b2f172f57377e184f164587e59cff73cb40228bdfb3ba60716704e3295df`；
   - `Research/Gate13RPR2Attempt3MonitoringRecoveryV2.py`，SHA-256 `6d1cd6b1f0542c2985fb0c11d3da6caee6c0413f0c5fe13f335897fef8f4c162`；
   - `Research/Get-Gate13RPR2Attempt3OperationalProgressV2.ps1`，SHA-256 `8b9c3733aae86b4adbe03c9bc7806931947746d864854d438bf2a67d09f537c5`；
   - heartbeat `gate13r-attempt3-hourly-progress` 的 `automation.toml`，SHA-256 `c66d41527f075137b2829a291fb303e1d81af940925e739fa3c898cb8f52b0e4`。

6. MP2 validation attempts 1–3、attempt 4 validation root、monitoring validation attempts 1–3、MP1 v1/v2、formal attempts 1–2、Gate 10R/11R/12R/PR1/PR1B/PR2/FD1 全部历史证据、原始游戏脚本、原始场景和原始项目归档必须完整保留且保持字节不变。不得 retry、resume、top-up、merge、覆盖或重新解释 formal attempts 1–2 与任一 pilot observation。

## 二、正式设计与冻结 policy

7. 正式设计固定为完整 74-campaign `S48/H48`：

   - 32 shared-goal campaigns，每 campaign 48 个完整四算法 Williams blocks；
   - 21 heterogeneous scenarios，每 scenario 48 个 matched superblocks；
   - 每个 matched superblock 含一个 fresh per-agent process 和一个 fresh grouped-field process；
   - 每个 heterogeneous scenario 的 AB/BA 为 24/24；
   - shared 1,536 processes / 6,144 samples；
   - heterogeneous 1,008 matched superblocks / 2,016 processes / 4,032 samples；
   - 总计 3,552 fresh Unity block processes / 10,176 algorithm samples。

8. 严格串行，最大并发 Unity Editor 数为 1。一个 fresh Unity Editor process 最多执行一个完整 Williams block；每个算法在 block 内最多一次；每样本完整 reset；禁止跨 block、matched superblock 或 campaign process reuse；禁止重排、跳过、adaptive stopping 或动态改变样本量。

9. 正式 statistical contract 保持不变：P1 是唯一 confirmatory primary endpoint；shared C1–C5 是 Holm FWER 0.05 confirmatory family；heterogeneous C1–C4 是 secondary system/treatment contrasts；P2–P5 supportive；M1–M5 留给 Gate 14R。15% 只是 power-planning effect anchor，不是 practical-superiority margin。Playable Scene 与 OBS 不得进入 formal timing 进程或 formal timing inference。

10. memory policy 固定为 `gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1`：

   - completed-sample cleanup 与 post-block boundary 使用相对 block baseline 的 `max(working-set delta, private-memory delta)`；
   - canonical max grid `<=128`：512 MiB advisory、640 MiB hard；
   - canonical max grid `==256`：640 MiB advisory、768 MiB hard；
   - 未映射或歧义 grid 在 measured launch 前 configuration hard fail；
   - exact threshold passes；advisory crossing 持久化并继续；hard crossing 先持久化，再禁止下一个 block；
   - raw-after-workload transient crossing 只作 diagnostic，host emergency 除外；
   - crossing 是 whole-block/process eligibility event，不得归因于 final-position algorithm；
   - retained-managed：after-cleanup 128 MiB alert、256 MiB sample/block emergency hard fail；
   - host safety：4 GiB absolute native、2 GiB relative native growth、8 GiB available-memory floor；telemetry invalid、mixed identity、non-finite、counter regression 或 overflow 均 fail closed。

11. 不得为取得通过而放宽 memory、correctness、oracle、structural exact-match、deterministic identity、reset、telemetry、failure/timeout denominator、hash/provenance、lock hygiene、Williams/AB-BA、monitor blinding 或 two-stage commit 门禁。

## 三、正式启动前实现、监控绑定与硬门禁

12. 允许新建 versioned formal-attempt-3 authorization record、execution orchestrator、prelaunch test design、atomic checkpoint/status publisher、raw-commit tool 和 provenance。它们只能把 active V4 candidate 与冻结 v2 schedule 映射到已验证 block runner，并集成已冻结 operational status schema；不得修改算法、场景、schedule/order/run identities、policy threshold、reset、telemetry、endpoint 或 statistical contract。

13. future orchestrator 必须以 write-temp、flush/fsync（适用时）和同卷原子替换发布：

   `Research/Gate13R_PR2_Formal_Execution_Status.v3.json`

   status 必须绑定 formal attempt ordinal 3、精确 v3 formal root、execution receipt SHA-256、active V4 candidate 和 v2 schedule identity；必须发布完成 process/sample 计数、当前 global ordinal/campaign/scenario/cohort/block/matched-superblock/Williams/AB-BA、复合 Unity process identity、operational memory/host telemetry、files/raw bytes 和 durable checkpoint 时间，但不得发布任何正式 endpoint、contrast 或 result。

14. 在创建 formal root、formal execution receipt、formal status 或任何 measured block 前，必须完成并通过：

   - Windows PowerShell 5.1 与当前 PowerShell runtime parser/binding；
   - config/schema/schedule/overlay/manifest 全量解析、SHA-256 和 byte-identical deterministic reconstruction；
   - 53 scenarios / 74 campaigns / 3,552 processes / 10,176 samples / 1,008 matched superblocks / AB/BA 24/24 / order×row 12/cell / unique run-output identity；
   - active V4 candidate、V3 wrapper、V4 block-plan builder、V5 Unity command 与 policy module 的 static/unit/synthetic/negative no-receipt/fail-closed/validation-only tests；
   - formal orchestrator 的 no-launch dry-run、从任意 schedule ordinal 的 deterministic plan reconstruction 和不得跳过、重排或复用的证明；
   - status publisher、5-minute watcher、三个 active 状态的 60-minute throttle、blinding、stall/ETA、read retry 和 immutable monitoring persistence 测试；
   - Phase-A raw commit / Phase-B read-only analysis state machine 与 analyzer failure 不触发 Unity rerun 的证明；
   - frozen upstream tree/key-file 前后不变性；
   - 零非本任务 Unity process、Unity lock absence、license/entitlement、网络、原生 Windows PowerShell 5.1 `PSModulePath`、高性能电源、禁用休眠、环境/热状态和 storage preflight；
   - H: 可用空间不得低于 `57,397,541,440` bytes，并基于当前 config 重新计算 raw-byte budget；
   - 精确 formal root、receipt 和 status 在正式启动提交前均不存在；
   - heartbeat `gate13r-attempt3-hourly-progress` 为 ACTIVE，每 5 分钟检查，指向 active V2 wrapper，并由监控器内部按 60 分钟 slot 节流。

## 四、prelaunch 自动修复/retry 的精确边界

15. 在尚未创建 formal root/receipt/status 且 measured process/sample count 均为零时，允许对本阶段新建的 orchestrator、schema、status publisher、monitor/report integration、checkpoint、raw-commit tool 或 validation-only 代码中的已确认软件缺陷进行自动、versioned repair 和 prelaunch retry。

16. 每个失败 prelaunch attempt 必须先保存独立 authorization/attempt receipt、failure signature、log、partial manifest、checkpoint、环境快照和 hashes；repair 后必须先通过 targeted synthetic/validation-only tests，才可开始下一 prelaunch attempt。

17. prelaunch automatic repair 的总上限为 3 个 versioned repair cycles。active v2 monitoring 修复已经消耗 cycle 1，因此本次正式授权后至 measured launch 前最多只剩 2 个自动 repair cycles；不得因重新计数而恢复为 3 个。相同 failure signature 连续出现 2 次时立即停止。环境/license/network/storage/status probe 可按冻结 `0/2/5` 秒读取策略最多查询 3 次，但查询 retry 不计为实验或 repair cycle，也不得绕过、降级或改写为 passed。

18. 以下情况绝不允许自动修复或 retry，必须 fail closed 并向用户报告：

   - frozen hash mismatch；
   - research/statistical contract mismatch；
   - scientific-identifiability failure；
   - ambiguous scenario/policy mapping；
   - formal root/receipt/status 预先存在；
   - 任何需要放宽 gate、threshold、Williams/AB-BA、sample size、memory、correctness、telemetry、blinding 或 two-stage contract 的情形。

19. 自动 prelaunch repair 不授权创建或启动 attempt 4，也不授权修改任何冻结输入。剩余 repair cycles 用尽、同签名停止或硬边界触发时，必须保存证据并等待用户。

## 五、一次正式 acquisition 与每小时进度

20. 只有全部 fresh prelaunch 硬门禁通过后，才允许创建精确 formal root：

   `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v3`

   并创建：

   - `Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json`；
   - `Research/Gate13R_PR2_Formal_Execution_Status.v3.json`。

   receipt 必须与本次用户授权文本、MP2/active-v2 monitoring readiness、terminal audit、evidence manifest、active V4 candidate、v2 schedule/manifest、policy registry/mapping/overlay、orchestrator/status publisher、resolved root、environment 和全部 preflight 结果精确绑定。

21. formal root 与 receipt 创建后，只允许启动一次完整 formal attempt，按 schedule global process ordinal 1–3,552 严格串行执行。不得自动 measured retry、resume、top-up、partial-attempt merge、择优保留、补齐、跨 attempt 拼接、并行化或 process reuse。

22. heartbeat 每 5 分钟静默读取一次 validated status、receipt 和 process identity。仅当状态为 `ACQUISITION-RUNNING`、`ACQUISITION-COMPLETE-COMMIT-PENDING` 或 `RAW-COMMIT-RECOVERY` 时，每个 60 分钟 slot 最多向用户提交一条计划进度，不为错过的 slot 批量补发。开始、失败、raw-data completion、action-required 或新 stall escalation 可即时报告。

23. 进度报告只允许包含：Asia/Shanghai/UTC 时间、Phase-A 状态、completed/total process 与 sample、当前 ordinal/campaign/scenario/cohort/block/matched-superblock/Williams/AB-BA、elapsed/operational throughput/conservative ETA、复合 PID/start-time/block identity、working-set/private/available memory、advisory count、files/raw bytes、checkpoint/last-write age、reason code 与 status/receipt/checkpoint 路径。禁止显示或推导任何 P1–P5、M1–M5、算法 timing、contrast、effect、CI、p 值、ranking、winner 或 superiority。

24. monitor 只能向 `Research/Monitoring/Gate13R_PR2_Attempt3/v1` 原子创建不可覆盖 operational snapshots。monitor 对 formal root 永远只读，不能启动、停止、signal、kill、repair、resume、retry、top-up、merge、skip、replace、reorder 或推进 Unity work。

25. 任一 measured sample、block、matched superblock、correctness、oracle、structural、hash、telemetry、memory、license、environment、persistence 或 formal measured-exit lock-hygiene 硬门禁失败时：

   - 不启动下一个 block；
   - formal measured exit 只能接受 natural lock absence；不得把 validation-only expected-negative controlled cleanup 当作正式继续条件；
   - 原子保存 failure checkpoint、receipt/status、partial output manifest、当前 global ordinal、campaign/superblock/block/run identity、文件数、原始字节数和最后写入时间；
   - 自动诊断只能只读保存进程树、复合身份、OS telemetry、lock/environment、文件/字节计数和已有日志/checkpoint hashes；
   - 标记 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`；
   - 停止并向用户报告；不得自动开始 attempt 4、不得重跑失败 sample/block、不得继续 schedule、不得进入 Gate 14R。

26. status/receipt/OS query 和通知投递可各自最多重试 3 次；读取或通知重试不是实验重跑，绝不能触发 Unity action、修复 measured output 或 schedule advancement。

## 六、两阶段提交与 post-acquisition non-Unity recovery

27. Phase A 是正式 raw acquisition。全部 3,552 processes / 10,176 samples 完成后，必须先生成并验证：

   - raw execution manifest；
   - block/sample/matched-superblock 完整性；
   - 文件数量和原始字节数；
   - 每个 block、sample、summary、workload result 的 SHA-256；
   - schedule/Williams/AB-BA 配额；
   - environment end snapshot；
   - 原始数据树 canonical SHA-256；
   - 状态 `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`。

28. 一旦全部 acquisition 完成，Unity acquisition 对本 attempt 永久关闭。measured blocks 永不因普通 raw-commit、manifest、analyzer、统计脚本、图表脚本或文档 bug 而重跑；raw tree 必须只读冻结，后续 analysis 只能在独立 versioned analysis root 中只读访问。

29. 如果全部 measured blocks 已完成，但 Phase-A manifest/freeze 工具发生普通软件缺陷，允许自动 non-Unity commit recovery，但仅在以下全部为真时：

   - completed process count 恰为 3,552；completed sample count 恰为 10,176；
   - acquisition-complete 证据已持久化；
   - raw file count、raw bytes 与 canonical tree identity 在两次独立读取中完全稳定；
   - Unity process count 为 0，`Temp/UnityLockfile` 不存在；
   - measured output 没有新增、删除或重写；
   - versioned commit repair 已通过 synthetic/validation-only tests。

30. 每个失败 commit attempt 必须独立保存 receipt、failure signature、log、manifest、checkpoint 和 hashes。最多允许 3 次 versioned non-Unity commit-recovery attempts；相同 failure signature 连续出现 2 次即停。commit recovery 绝不允许启动 Unity、创建新 sample、补齐缺失 observation、重写 measured output 或合并历史 attempt。

31. 如果发现 missing block/sample、raw-tree mutation、unverifiable hash、count/identity mismatch 或 raw contract violation，必须进入 `USER-ACTION-REQUIRED`，不得伪造 `RAW-DATA-COMPLETE`，不得通过重跑、补齐或合并修复。

32. 本次授权不允许 Phase-B 正式统计分析。Phase A 成功冻结后，只允许运行 raw completeness、hash/provenance 和 `FORMAL-RAW-READY-FOR-SEPARATE-ANALYSIS-AUTHORIZATION` 审计，然后停止并请求正式分析/Gate 14R 的独立授权。

## 七、停止条件与终态报告

33. 成功状态只能是：

   `FORMAL-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE / FORMAL-STATISTICAL-ANALYSIS-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`。

34. prelaunch 无法在剩余冻结修复上限内解决、acquisition 任一 hard failure、post-acquisition raw contract violation 或 commit recovery 达到上限时，必须完整保存原子、versioned 证据并停止；禁止把 partial formal data、MP1/MP2 pilot/validation data 或历史 attempt observations 混入未来正式推断。

35. 完成后向用户报告：最终 process/sample/file/raw-byte/tree-hash 状态、两阶段提交状态、所有自动 prelaunch/commit repair attempts、每小时监控摘要位置、terminal audit、是否需要正式分析授权；不得在本授权下直接开始 Phase-B analysis 或 Gate 14R。

36. 本授权明确不授权正式统计分析、不授权 Gate 14R、不授权 OBS/Playable timing、不授权 measured acquisition retry/resume/top-up/merge，也不授权修改 frozen inputs 或依据 formal results 事后改变 endpoint、contrast、threshold、exclusion 或 sample size。

---
