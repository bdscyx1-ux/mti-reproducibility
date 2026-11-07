# Gate 13R-PR2 Attempt 2 — Next Authorization Prompt

复制以下完整文本作为下一条授权消息：

---

授权 Gate 13R-PR2 S48/H48 formal attempt 2 的受控、版本化 embedded block-sample contract 修复、完整 prelaunch 验证，以及在全部硬门禁通过后的一次全新正式 raw-data acquisition attempt；不授权 resume、top-up、partial merge、Gate 13R 正式统计分析或 Gate 14R。

## 一、attempt 1 永久保留与排除

1. 完整保留并保持字节不变、只读不变：

   - `Research/Gate13R_PR2_Formal_Execution_Receipt.v1.json`；
   - `Research/Gate13R_PR2_Formal_Execution_Status.v1.json`；
   - `Research/FormalRuns/Gate13R_RQAligned_S48H48/v1/`；
   - `Research/Verification/Gate13R_PR2_Formal_Execution/v1/` 中 attempt-1 的启动日志、launch receipt、failure diagnosis、partial-tree manifest、freeze receipt、evidence manifest 和 ledger evidence；
   - `Research/Gate13R_PR2_Formal_Attempt1_Failure_Checkpoint.md`；
   - Gate 10R/11R/12R/PR1/PR1B/PR2 的全部既有冻结输入、失败证据、原始脚本、原始场景和原始项目归档。

2. attempt 1 必须永久保持：

   `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS`。

3. attempt 1 中第一个 Unity process 生成的四个 sample artifacts 不得补齐、继续、重新提交、转换为有效 block、并入 attempt 2、用于正式推断或与未来数据合并。

4. attempt 1 的冻结根身份必须在修复前、验证后和 attempt-2 启动前逐次核验：31 个文件、3,338,221 bytes、canonical tree SHA-256 `026b9830f220b06af3f0a106f638b3d918d115ba08f5f06c13d9d76542ba4f56`，且 31/31 文件保持只读。

## 二、允许的唯一修复范围

5. 本次只允许修复 attempt 1 已确认的 producer/consumer schema mismatch：

   - 冻结 `Gate13RPR2FormalBatchCommandV2.cs` 中的 `BlockChildRecord` 未声明 `formalCampaign`；
   - 因此已完成 `block-manifest.json` 的每条 `samples[]` 嵌入记录缺少该属性；
   - `Run-Gate13RPR2FormalBlockV4.ps1` line 115 在 StrictMode 下访问该属性并于首个 block 的 wrapper commit 阶段失败。

6. 修复必须放入新的 versioned adapter/wrapper/orchestrator/module/provenance/schema/test 文件，不得修改或覆盖 attempt 1 绑定的任何 V2/V3/V4 文件。推荐机械派生新的 C# adapter，在 `BlockChildRecord` 中增加 `public bool formalCampaign;`，并在构造每条嵌入 sample record 时显式赋值 `formalCampaign = plan.formalCampaign`。

7. 不得通过删除 wrapper 检查、将缺失属性默认为 true、捕获并忽略异常、放宽 schema、降低 correctness/memory/telemetry/hash 门禁或改变实验语义取得通过。新的 wrapper 必须继续要求：

   - block 顶层 `formalCampaign=true`；
   - 每条嵌入 `samples[]` record 的 `formalCampaign=true`；
   - 每个 sample summary、child manifest 和 memory evaluation 的 `formalCampaign=true`；
   - 所有相互引用、hash、process identity、Williams order、reset 和 memory gates 完整匹配。

8. 不得修改 active scientific design：74 campaigns、S48/H48、3,552 fresh Unity block processes、10,176 algorithm samples、strict serial、每 process 最多一个完整 Williams block、每算法每 block 最多一次、shared C1–C5、heterogeneous matched superblocks、AB/BA 24/24、P1/P2–P5/M1–M5 层级、排除规则和 raw-data/analysis 两阶段提交规则全部保持不变。

## 三、正式启动前的版本化验证

9. 先建立独立的 attempt-2 authorization record、repair specification、schema amendment、mechanical-derivation receipt、test design、provenance、validation roots、checkpoint 和运行账本记录。所有失败的 validation attempts 必须独立保留，不得覆盖。

10. 在创建 attempt-2 formal root 或 execution receipt 前，必须通过：

   - Windows PowerShell 5.1 和活动 PowerShell runtime parser/binding；
   - 新旧 C# adapter 的机械差异审计，证明只发生 version/class identity 与 embedded `formalCampaign` contract 所需变化；
   - 编译与 Unity self-tests；
   - synthetic fixtures：缺失、false、重复、类型错误的 embedded `formalCampaign` 均必须 fail closed；
   - 全量 block-manifest schema/unit tests；
   - 实际启动一个 fresh Unity Editor process，在正式根之外执行一个 `VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS` 的完整四算法 Williams block rehearsal；
   - rehearsal 必须通过实际新 block wrapper，生成 passed wrapper summary，并证明 block 顶层、四条 embedded sample records、四个 sample summaries、四个 child manifests 和四个 memory evaluations 的 `formalCampaign=true`；
   - campaign-level validation-only dry-run 必须消费上述同构 wrapper summary，并证明不会重现 attempt-1 的 PropertyNotFoundException；
   - negative no-receipt/fail-closed、telemetry、managed-memory、lock hygiene、independent process、structural exact-match、retained regression、hash/provenance 和 deterministic schedule reconstruction；
   - 74 campaigns、3,552 processes、10,176 samples、1,008 matched superblocks、每 heterogeneous scenario AB/BA 24/24、order×row 12/cell 和所有 run/output identities；
   - attempt-1 和全部冻结上游的 pre/post byte/hash 不变性。

11. 允许对 attempt-2 新建且尚未创建 formal root、尚未启动任何 attempt-2 measured block 的实现、PowerShell/Unity 兼容性和 validation-only 缺陷进行版本化修复与重试。不得以修改冻结 config/schedule、放宽门禁或改变研究语义取得通过。

12. attempt-2 正式启动前必须重新执行并通过：

   - exact config/schema/schedule/manifest/readiness/authorization/provenance hashes；
   - Unity 零进程、项目锁不存在；
   - license/entitlement、网络、原生 Windows PowerShell 5.1 `PSModulePath`；
   - 高性能电源、AC 在线、禁用睡眠/休眠、环境/热状态；
   - H: 原始字节存储预算，free bytes 不低于 `57,397,541,440`；
   - attempt-2 formal root、status sidecar 和 execution receipt 均不存在。

## 四、一次全新的 attempt 2

13. 只有所有硬门禁通过后，才允许创建全新的正式根：

   `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2`

   并创建与本次授权、active frozen config/schedule/readiness、修复后的 versioned adapter stack、全部 validation evidence、resolved root 和 fresh preflight 精确绑定的 attempt-2 execution receipt。不得复用 attempt-1 receipt。

14. receipt 创建后只允许启动一次完整 attempt 2，按冻结 global process ordinal 严格串行执行 3,552 processes / 10,176 samples。禁止改变顺序、跳过 block、并行化、跨 block reuse、adaptive stopping、补齐、择优保留或动态改变样本量。

15. attempt 2 任一 measured sample、block、matched superblock、hash、telemetry、correctness、memory、license、环境、wrapper commit 或持久化硬门禁失败时立即 fail closed：

   - 不启动下一个 block；
   - 原子保存状态、checkpoint、partial-output manifest、日志、global ordinal、campaign/block/run identity、文件数、原始字节数、最后写入时间和逐文件 hash；
   - 标记 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`；
   - 停止并向我报告；
   - 不得自动创建 attempt 3。

16. attempt 2 禁止 retry、resume、top-up、partial-attempt merge，禁止把 attempt 1、pilot 或历史 observations 混入正式数据。

## 五、两阶段提交继续生效

17. attempt 2 全部 Unity measured blocks 完成后，必须先进入：

   `UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN`。

18. raw commit audit 成功后才进入：

   `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`。

19. 一旦全部 Unity collection 完成，任何普通 raw-auditor、hash-manifest、checkpoint-finalization 或未来 analysis implementation bug 均不得触发 Unity 重跑。只允许版本化修复工具并对同一冻结 raw tree 做新的独立只读 audit/analysis attempt。

20. 只有原始数据自身违反冻结采集合同，才标记：

   `RAW-CONTRACT-VIOLATION / USER-DECISION-REQUIRED / NO-UNITY-RERUN`，并停止等待我的新决定。

21. 完成 Phase 1 raw commit 后停止并向我报告；不运行正式统计分析，不启动 Gate 14R，不运行 Playable/OBS 录制，不创建 Gate 14R 输出。

本授权如被采用，授权的是一次新的、完整的 attempt 2，而不是 attempt 1 的 retry/resume/top-up/merge。attempt 1 必须永久只读、永久排除。

---

