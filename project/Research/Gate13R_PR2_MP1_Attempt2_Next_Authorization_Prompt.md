# Gate 13R-PR2-MP1 attempt 2 / v2 next authorization prompt

复制以下正文作为下一条授权消息：

---

授权 Gate 13R-PR2-MP1 attempt 2 / v2「checkpoint state-machine 与跨运行时 atomic-replace 受控修复、完整 validation，以及一次全新的 NON-FORMAL balanced targeted memory pilot」。不授权 pilot v1 retry/resume/top-up/merge，不授权 Gate 13R-PR2 formal attempt 3，不授权正式统计分析或 Gate 14R。

## 一、冻结失败证据与活动上游

1. 以 `Research/Gate13R_PR2_MP1_Pilot_v1_Failure_Checkpoint.v1.json` 及其 Markdown 为 pilot v1 失败恢复点。pilot v1 必须永久保持：

   `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / ZERO-MEASURED-BLOCKS / IMMUTABLE`。

2. 完整保留且保持字节不变：

   - `Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v1`，精确身份为 5 files / 5,247 bytes / canonical tree SHA-256 `a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265`，5/5 文件只读；
   - `Research/Gate13R_PR2_MP1_Pilot_v1_Failure_Preservation_Receipt.v1.json`，SHA-256 `6d129e01b678871754413ca853051f7f8b921dad3ee572d35e96775fde57087e`；
   - preservation attempt-1 failure receipt；
   - MP1 v1 specification、test design、instrumentation contract、candidate registry、schedule/config/schema/provenance、pre-pilot audit/readiness、validation attempts 和实现；
   - Gate 13R-PR2 formal attempt 2 root，精确身份仍为 28,020 files / 8,536,611,302 bytes / canonical tree SHA-256 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`，全部只读；
   - Gate 10R/11R/12R/PR1/PR1B/PR2/FD1 全部冻结证据、原始游戏脚本、原始场景和原始项目归档。

3. pilot v1 没有启动 Unity、没有 block plan、没有 measured block/sample，也没有 Phase-A raw commit。不得把它解释为 memory-policy 结果，不得对其运行诊断分析或与 v2 数据合并。

## 二、仅允许的实现修复

4. 只允许在全新的 versioned v2 文件中修复已确认的 orchestration checkpoint 缺陷：

   - 不得向缺少属性的反序列化 `PSCustomObject` 直接赋值；
   - v2 checkpoint schema 必须在初始创建时预声明所有后续状态需要的字段，至少包括 `startedAtUtc`、failure fields、completed counts、current ordinal/block、Phase-A fields 和 `rawTreeSha256`；或在每个 transition 中从冻结输入构造一个新的完整 ordered checkpoint；
   - 所有 transition 必须进行 schema validation、create/replace postcondition 和 SHA-256 验证；
   - 不得使用在 PowerShell 7/.NET 10 下会把 null backup path 解释为空路径的 `File.Replace` 调用；如使用 replace，必须采用经过验证的非空 backup path 或等价的 versioned、path-safe atomic primitive；
   - outer orchestrator 必须覆盖第一个 block 前的失败，原子保存 failure receipt、zero/partial manifest 和 failed checkpoint，不能依赖事后人工补证。

5. 不得改变 MP1 v1 已冻结的科学设计：四个 canonical shared-goal scales、16/16/16/48 measured blocks、96 fresh block processes、384 samples、0 warm-up、Williams row/position/predecessor balance、严格串行、每 block 一个 fresh Unity process、每样本完整 reset、stage-separated telemetry、managed/native/host safety stops、failure precedence、lock hygiene、two-stage commit 和 analysis plan均保持不变。

6. 新建 versioned v2 config、schema、provenance、launcher/orchestrator/wrapper amendment、authorization record、validation root、readiness checkpoint和独立 pilot root：

   `H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2`

   不得覆盖或修改任何 v1 文件。schedule 如保持字节相同，必须由 v2 manifest/provenance 显式引用并证明 deterministic identity；所有含 pilot root 或 receipt 身份的 artifact 必须版本化为 v2。

## 三、v2 pilot 前新增硬门禁

7. 在创建 v2 pilot root 前，除重新通过 MP1 v1 的全部静态、单元、Unity compile/self-test、PSAPI/CIM telemetry、正向 block、负向 fail-closed、failure-precedence、lock-hygiene、deterministic regeneration、hash/provenance 和 validation-only final audit外，还必须新增并通过：

   - PowerShell 7 与原生 Windows PowerShell 5.1 的 checkpoint schema/parser/binding tests；
   - 完整状态机 fixtures：`AUTHORIZED-NOT-STARTED -> MEASURED-ACQUISITION-RUNNING -> BLOCK-PROGRESS -> PILOT-RAW-DATA-COMPLETE`；
   - 独立 failure transition fixtures：第一个 block 前、block 内、最后 block 后 raw-freeze 前；
   - 每个 transition 的 create-new/replace、backup、hash、read-back schema 和 residual-temp postcondition；
   - synthetic zero-block injected failure，必须自动生成 durable failure receipt、zero-output manifest 和 failed checkpoint，且不得启动 Unity；
   - synthetic raw-complete transition，证明 `rawTreeSha256` 可持久化而不会在 96 blocks 后才触发缺失属性；
   - static/runtime proof：v1 root 不可写、v2 root 尚不存在、formal attempt-3 root/receipt 不存在；
   - v1 pilot root、formal attempt 2 root及所有冻结上游的前后 hash/byte 不变性。

8. 允许对 v2 pilot root 尚未创建且未启动任何 measured block之前发现的 v2 instrumentation/orchestration/schema/test 实现缺陷进行 versioned 自动修复和 validation-only retry；每个失败 validation attempt必须保留独立 receipt、日志、manifest、checkpoint和哈希。不得通过改变矩阵、Williams balance、安全门禁、reset、correctness、telemetry或two-stage语义取得通过。

## 四、一次全新的 v2 NON-FORMAL pilot

9. 只有全部 v2 pre-pilot硬门禁通过后，才允许创建 v2 pilot root及与授权、v2 config/provenance、冻结 schedule、resolved root和preflight精确绑定的 execution receipt。

10. v2 measured pilot只能启动一次。启动后任一 acquisition硬失败立即 fail closed并停止，不得自动 retry/resume/top-up/merge；不得回到 v1，也不得创建 v3 pilot，除非用户再次单独授权。

11. 全部 96 blocks / 384 samples成功后，先完成 Phase A：raw manifest、完整性、逐文件 hash、canonical tree、schedule/Williams配额、environment-end snapshot和只读冻结，状态为：

   `PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`。

12. 只有 Phase A成功后，才按冻结 analysis plan只读分析 v2 raw root。普通分析器 bug只能 versioned修复并重跑分析，不得重跑Unity。只有 raw违反采集合同才停止并请求新的实验授权。

13. 分析仅用于 stage-separated memory、scale/position/predecessor/algorithm诊断、512/640/768/1,024 MiB候选、absolute/scenario-aware/layered policy和host safety margin；禁止 C1-C5/P1-P5 superiority、正式 effect、正式 n_formal或 Gate 14R推断。

## 五、停止条件

14. 成功后只生成 raw-freeze receipt、独立诊断 analysis、candidate memory-policy recommendation/readiness、整体计划与 next-session checkpoint更新，以及下一阶段授权提示词；不得自动修改 formal config、创建 formal attempt-3 root/receipt或启动正式 campaign。

15. 任一 v2 measured硬门禁失败时，保存原子 failure receipt、partial manifest、checkpoint、当前 ordinal/block/stage、文件数/bytes/hash后立即停止。成功或失败都要报告 v1和formal attempt 2的前后不变性。

本授权明确不授权 pilot v1 retry/resume/top-up/merge，不授权 Gate 13R-PR2 formal attempt 3，不授权正式统计分析，不授权 Gate 14R，不授权把任何 NON-FORMAL pilot observations合并进正式数据或据此宣布算法 superiority。

---

