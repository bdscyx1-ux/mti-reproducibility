# Gate 13R-PR2 formal attempt 3 — next authorization prompt

复制以下正文作为下一条授权消息。发送前可先审阅 MP2 readiness；本文件本身不构成执行授权。

---

授权 Gate 13R-PR2 formal attempt 3 的一次受控、严格串行、两阶段提交执行；不授权正式统计分析，不授权 Gate 14R。

## 一、唯一活动上游与哈希

1. 以以下 MP2 non-executing readiness 为唯一 attempt-3 readiness checkpoint：

   - `Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json`，SHA-256 `88333a15f3e5deb0eb7998bf15a5f1976df5de9a0382350016aa8623ad4680f8`；
   - `Research/Gate13R_PR2_MP2_Final_Validation_Audit.v1.json`，SHA-256 `bbf41f14682a85e061799a5cb9daed2122d6f8631a878b22bb714ede161bbe9e`。

2. 只允许使用以下 active formal-attempt-3 candidate artifacts：

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

3. 底层 PR2 v2 schedule/config 继续保持字节不变：

   - `Research/Gate13R_PR2_Formal_Campaign_Config.v2.json`，SHA-256 `87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e`；
   - `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl`，SHA-256 `df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae`；
   - `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json`，SHA-256 `b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724`。

4. MP2 validation attempts 1–3、attempt 4 validation root、MP1 v1/v2、formal attempts 1–2、Gate 10R/11R/12R/PR1/PR1B/PR2/FD1 全部历史证据、原始游戏脚本、原始场景和原始项目归档必须完整保留且保持字节不变。不得 retry、resume、top-up、merge、覆盖或重新解释 formal attempts 1–2 与任一 pilot observation。

## 二、正式设计与冻结 policy

5. 正式设计固定为完整 74-campaign `S48/H48`：

   - 32 shared-goal campaigns，每 campaign 48 个完整四算法 Williams blocks；
   - 21 heterogeneous scenarios，每 scenario 48 个 matched superblocks；
   - 每个 matched superblock 含一个 fresh per-agent process 和一个 fresh grouped-field process；
   - 每个 heterogeneous scenario 的 AB/BA 为 24/24；
   - shared 1,536 processes / 6,144 samples；
   - heterogeneous 1,008 matched superblocks / 2,016 processes / 4,032 samples；
   - 总计 3,552 fresh Unity block processes / 10,176 algorithm samples。

6. 严格串行，最大并发 Unity Editor 数为 1。一个 fresh Unity Editor process 最多执行一个完整 Williams block；每个算法在 block 内最多一次；每样本完整 reset；禁止跨 block、matched superblock 或 campaign process reuse；禁止重排、跳过、adaptive stopping 或动态改变样本量。

7. 正式 statistical contract 保持不变：P1 是唯一 confirmatory primary endpoint；shared C1–C5 是 Holm FWER 0.05 confirmatory family；heterogeneous C1–C4 是 secondary system/treatment contrasts；P2–P5 supportive；M1–M5 留给 Gate 14R。15% 只是 power-planning effect anchor，不是 practical-superiority margin。Playable Scene 与 OBS 不得进入 formal timing 进程或 formal timing inference。

8. memory policy 固定为 `gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1`：

   - completed-sample cleanup 与 post-block boundary 使用相对 block baseline 的 `max(working-set delta, private-memory delta)`；
   - canonical max grid `<=128`：512 MiB advisory、640 MiB hard；
   - canonical max grid `==256`：640 MiB advisory、768 MiB hard；
   - 未映射或歧义 grid 在 measured launch 前 configuration hard fail；
   - exact threshold passes；advisory crossing 持久化并继续；hard crossing 先持久化，再禁止下一个 block；
   - raw-after-workload transient crossing 只作 diagnostic，host emergency 除外；
   - crossing 是 whole-block/process eligibility event，不得归因于 final-position algorithm；
   - retained-managed：after-cleanup 128 MiB alert、256 MiB sample/block emergency hard fail；
   - host safety：4 GiB absolute native、2 GiB relative native growth、8 GiB available-memory floor；telemetry invalid、mixed identity、non-finite、counter regression 或 overflow 均 fail closed。

9. 不得为取得通过而放宽 memory、correctness、oracle、structural exact-match、deterministic identity、reset、telemetry、failure/timeout denominator、hash/provenance、lock hygiene、Williams/AB-BA 或 two-stage commit 门禁。

## 三、正式启动前的实现与硬门禁

10. 允许新建 versioned formal-attempt-3 authorization record、execution orchestrator、prelaunch test design、atomic checkpoint、status schema 和 provenance。它们只能把 active V4 candidate 与冻结 v2 schedule 映射到已验证 block runner；不得修改算法、场景、schedule/order/run identities、policy threshold、reset、telemetry 或 statistical contract。

11. 在创建 formal root、formal execution receipt 或任何 measured block 前，必须完成并通过：

   - Windows PowerShell 5.1 与当前 PowerShell runtime parser/binding；
   - config/schema/schedule/overlay/manifest 全量解析、SHA-256 和 byte-identical deterministic reconstruction；
   - 53 scenarios / 74 campaigns / 3,552 processes / 10,176 samples / 1,008 matched superblocks / AB/BA 24/24 / order×row 12/cell / unique run-output identity；
   - active V4 candidate、V3 wrapper、V4 block-plan builder、V5 Unity command 与 policy module 的 static/unit/synthetic/negative no-receipt/fail-closed/validation-only tests；
   - formal orchestrator 的 no-launch dry-run、从任意 schedule ordinal 的 deterministic plan reconstruction 和“不得跳过/重排/复用”的证明；
   - Phase-A raw commit / Phase-B read-only analysis state-machine 与 analyzer failure 不触发 Unity rerun 的证明；
   - frozen upstream tree/key-file 前后不变性；
   - 零非本任务 Unity process、Unity lock absence、license/entitlement、网络、原生 Windows PowerShell 5.1 `PSModulePath`、高性能电源、禁用休眠、环境/热状态和 storage preflight；
   - H: 可用空间不得低于 `57,397,541,440` bytes，并基于当前 config 重新计算 raw-byte budget；
   - 精确 formal root、receipt 和 status 在正式启动授权提交前均不存在。

12. 允许对第 10–11 条中新建且尚未创建 formal root、尚未启动 measured block 的 attempt-3 orchestrator/schema/validation-only 实现缺陷进行 versioned 修复与 prelaunch retry。每个失败 attempt 必须独立保存 receipt、log、manifest、checkpoint 和 hashes。不得修改 frozen candidate/config/schedule/policy 或研究语义求通过。

## 四、一次正式 acquisition

13. 只有全部 fresh prelaunch 硬门禁通过后，才允许创建精确 formal root：

   `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v3`

   并创建：

   - `Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json`；
   - `Research/Gate13R_PR2_Formal_Execution_Status.v3.json`。

   receipt 必须与本次用户授权文本、readiness、active V4 candidate、v2 schedule/manifest、policy registry/mapping/overlay、formal orchestrator、resolved root、environment 和全部 preflight 结果精确绑定。

14. formal root 与 receipt 创建后，只允许启动一次完整 formal attempt，按 schedule global process ordinal 1–3,552 严格串行执行。不得自动 retry、resume、top-up、partial-attempt merge、择优保留、补齐、跨 attempt 拼接、并行化或 process reuse。

15. 任一 measured sample、block、matched superblock、correctness、oracle、structural、hash、telemetry、memory、license、environment、persistence 或 formal measured-exit lock-hygiene 硬门禁失败时：

   - 不启动下一个 block；
   - formal measured exit 只能接受 natural lock absence；不得把 validation-only expected-negative controlled cleanup 当作正式继续条件；
   - 原子保存 failure checkpoint、receipt/status、partial output manifest、当前 global ordinal、campaign/superblock/block/run identity、文件数、原始字节数和最后写入时间；
   - 标记 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`；
   - 停止并向用户报告，不得自动开始 attempt 4 或 Gate 14R。

## 五、两阶段提交

16. Phase A 是正式 raw acquisition。全部 3,552 processes / 10,176 samples 完成后，必须先生成并验证：

   - raw execution manifest；
   - block/sample/matched-superblock 完整性；
   - 文件数量和原始字节数；
   - 每个 block、sample、summary、workload result 的 SHA-256；
   - schedule/Williams/AB-BA 配额；
   - environment end snapshot；
   - 原始数据树 canonical SHA-256；
   - 状态 `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`。

17. 一旦 Phase A 达到上述状态，measured Unity blocks 永不因普通 analyzer、统计脚本、图表脚本或文档 bug 而重跑。raw tree 必须只读冻结；后续 analysis 只能在独立 versioned analysis root 中只读访问。

18. 如果全部 measured blocks 已完成，但 Phase-A manifest/freeze 工具发生普通软件缺陷：

   - 立即禁止任何进一步 Unity acquisition；
   - 保存 acquisition-complete 与 commit-failure 证据；
   - 只允许对同一完整 raw tree 做 versioned、non-Unity commit recovery；
   - 不得通过重跑 block 修复 manifest；
   - 若证据表明 raw contract 本身不完整、被篡改或无法验证，则 fail closed 并等待用户决策，不得伪造 `RAW-DATA-COMPLETE`。

19. 本次授权不允许 Phase-B 正式统计分析。Phase A 成功冻结后，只允许运行 raw completeness、hash/provenance 和 `FORMAL-RAW-READY-FOR-SEPARATE-ANALYSIS-AUTHORIZATION` 审计，然后停止并请求正式分析/Gate 14R 的独立授权。

## 六、停止条件

20. 成功状态只能是：

   `FORMAL-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE / FORMAL-STATISTICAL-ANALYSIS-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`。

21. 失败时必须保留完整、原子、versioned 证据并停止；禁止把 partial formal data、MP1/MP2 pilot/validation data 或历史 attempt observations 混入未来正式推断。

22. 本授权明确不授权正式统计分析、不授权 Gate 14R、不授权 OBS/Playable timing、不授权 formal retry/resume/top-up/merge，也不授权修改 frozen inputs 或依据 formal results 事后改变 endpoint、contrast、threshold、exclusion 或 sample size。

---
