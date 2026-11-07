# Gate 13R-PR2-MP1 targeted memory-policy pilot authorization prompt

复制以下正文作为下一条授权消息：

---

授权 Gate 13R-PR2-MP1「stage-separated memory instrumentation、failure-precedence wrapper 修复、validation 和一次全新的 NON-FORMAL balanced targeted memory pilot」。本次授权仅允许在所有非执行/编译/validation-only 硬门禁通过后运行一次独立的非正式 pilot；不授权 Gate 13R-PR2 formal attempt 3，不授权 attempt 2 retry/resume/top-up/merge，不授权正式统计分析，不授权 Gate 14R。

## 一、唯一活动诊断上游

1. 以以下文件为唯一 FD1 活动上游：

   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json`，SHA-256 `388b7a1921fe07daf97827353f402c365b0f208a9dc62cbbff2d4b5ea2829b7d`；
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json`，SHA-256 `f192265e12155d0e56e1aa94e18cea1305b66e2fbc0eeb0eeb6ad9618aeb3c3a`；
   - `Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json`，SHA-256 `11cf507ad3daee5c4d17adf3d7349e50b73a925f58fdb175e2b68315240eff5b`；
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/evidence-manifest.json`，SHA-256 `73e34e3910a38462d8dc3a125eaf88e2c800b8f1808206db054fbe50e4f24c46`；
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v2/evidence-manifest.json`，SHA-256 `847e93f13fe7e46eea154741d3e93421ff7c4df389b1a7a2e10cb1b676e4eb3b`；
   - Gate 10R attempt 4、Gate 11R attempt 2 retained bundle、Gate 12R v4、PR1/PR1B、PR2 preparation v2 中被现有 config/provenance 精确绑定的冻结输入。

2. 必须接受并保留 FD1 已确认的边界：

   - attempt 2 永久保持 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / EXCLUDED-FROM-FORMAL-ANALYSIS`；
   - attempt 2 没有达到 `RAW-DATA-COMPLETE`；
   - failed block 的 512 MiB native delta 在 position 1 已经越界，而 position 4 C-FF 只是冻结实现的最终 enforcement point；
   - algorithm、position、predecessor、正常 g256 residency 与 native leak 原因均未从 attempt 2 得到识别；
   - 512/640/768/1,024 MiB 和其他政策均为 `UNFROZEN / USER-DECISION-REQUIRED`。

3. 在任何新文件写入前，重新核验 attempt 2 根仍为 28,020 files / 8,536,611,302 bytes / canonical ordinal tree SHA-256 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`，全部文件只读；核验 Unity 进程为 0、`Temp/UnityLockfile` 不存在、attempt-3 root/receipt 不存在。

## 二、保留与禁止修改

4. 完整保留并保持字节不变：

   - `Research/FormalRuns/Gate13R_RQAligned_S48H48/v2`；
   - attempt 1/2 receipt、status、checkpoint、logs、manifests 和 sidecars；
   - FD1 v1/v2 analysis、失败 attempts、cleanup receipt、provenance 和 checkpoint；
   - PR2 active config/schedule/readiness v2；
   - Gate 10R/11R/12R/PR1/PR1B 全部冻结证据；
   - 原始游戏脚本、原始场景和原始项目归档。

5. 不得覆盖、删除、重命名、解除只读、resume、补齐或合并 attempt 2 根内任何文件；不得把其部分样本用于 C1–C5、P1–P5 superiority、正式方差、正式样本量或 Gate 14R 推断。

## 三、先冻结 targeted pilot 规格与 schedule

6. 在查看任何新 pilot 结果前，先创建并哈希 versioned specification、test design、instrumentation contract、memory-policy candidate registry、schedule、schema、analysis plan、two-stage raw/analysis commit contract 和 provenance。

7. targeted pilot 的推荐冻结矩阵为四个 Gate 11R canonical shared-goal grid-scale scenarios：

   - `grid-scale-g032-shared`：16 measured Williams blocks；
   - `grid-scale-g064-shared`：16 measured Williams blocks；
   - `grid-scale-g128-shared`：16 measured Williams blocks；
   - `grid-scale-g256-shared`：48 measured Williams blocks。

   合计 96 measured fresh Unity block processes / 384 measured algorithm samples。允许每个 scale 在 measured blocks 前最多增加 2 个明确标记 `WARM-UP / EXCLUDED` 的 fresh processes，最多 8 个 warm-up processes；warm-up 不得混入 measured analysis。

8. 每个完整 block 包含 A*-R、D*L、C-FF、IDFF 各一次；一个 fresh Unity Editor process 最多执行一个完整 block；严格串行，最大 Unity concurrency 为 1；每样本完整 reset；禁止跨 block/process reuse。

9. Williams 平衡必须预先冻结：

   - g256 的四个 Williams rows 各 12 blocks；
   - g032/g064/g128 的四个 rows 各 4 blocks；
   - 每个 scale 内每算法在每 position 次数相等；
   - predecessor 配额按 Williams 设计平衡；
   - schedule、run ID、block ID、output path 和 seed 在运行前确定性生成并哈希；
   - 不得根据中途内存结果改变顺序、样本数或 scale 配额。

10. 该 pilot 的唯一目的，是区分 process/project/scenario-load residency、first-workload initialization、per-sample retention、position/predecessor 和 scenario scale 对 working-set/private/managed memory 的影响，并为未来政策选择提供独立诊断证据。它不是算法性能或 superiority 实验。

## 四、stage-separated telemetry 修订

11. 只能在新的 versioned command/wrapper/module 中实现 telemetry；不得修改 active V4/V5/V6 command、wrapper、formal config 或 attempt 2 文件。

12. 每个 pilot process 至少持久化并通过 `(PID, processStartTimeUtc, blockId)` 绑定以下阶段：

   - external first-valid PSAPI snapshot after process creation；
   - Unity command entry / project-loaded snapshot；
   - scenario load 前；
   - scenario load 后、首个 algorithm sample 前；
   - 每个 sample 的 before / raw-after-workload / after-cleanup；
   - block 完成后、Unity 退出前；
   - process exit 与 post-exit quiescence。

13. 每个阶段必须保存：absolute working set、absolute private memory、managed memory、GC counts、process age、capture UTC、source ID，以及相对于 process-start、project-loaded、scenario-loaded 和 block-baseline 的明确 delta。PSAPI 必须为主来源，并用可用的独立 OS/CIM 查询做交叉核验；单位统一为 raw bytes，报告时可转换 MiB。

14. 不得把 working set、private memory、managed memory 或 OS free memory 混为同一指标。negative delta 必须保留；missing、non-finite、PID/start-time 不一致、时间逆序和 block identity 不一致均须 fail closed。

## 五、pilot-only 安全政策

15. 本 pilot 不得把 512/640/768/1,024 MiB 候选中的任一值预先宣布为未来正式门禁。为观察完整 block：

   - 512/640/768/1,024 MiB native block-delta 均只作为 pilot diagnostic flags，不能因为超过其中某一候选就自动把该 candidate 宣布无效或中途删除该 block；
   - 128 MiB sample retained-managed 继续作为 alert；
   - 256 MiB sample retained-managed emergency stop 保持 hard fail；
   - 256 MiB block retained-managed limit 保持 hard fail；
   - telemetry/identity/correctness/reset/structural/hash failure 保持 hard fail。

16. 为保护 32 GiB 主机，pilot 独立采用以下预注册 emergency safety stops，不得运行后放宽：

   - absolute Unity process working set 或 private memory 大于 4 GiB；或
   - 相对 process/block baseline 的 working-set 或 private-memory growth 大于 2 GiB；或
   - OS available physical memory 低于 8 GiB；或
   - 出现不可验证的持续增长/telemetry overflow。

   任一 emergency stop 触发时立即 fail closed，不启动下一个 block，不自动 retry/resume/top-up/merge。

17. pilot 结果只能用于未来 policy decision matrix。不得以“让 attempt 2 通过”为政策选择理由，不得依据 P1–P5 性能方向选阈值，不得修改 attempt 2 的失败结论。

## 六、failure precedence 与 lock hygiene

18. 以 `Research/Gate13RPR2FailurePrecedenceCandidateV1.psm1` 的已验证语义为候选起点，建立新的 pilot-only versioned wrapper：

   - durable Unity/block failure 保持 primary；
   - post-exit quiescence failure 独立保存为 secondary；
   - checkpoint/receipt/manifest 同时保存两者；
   - 任一失败均 fail closed；
   - 不启动下一个 block；
   - lock cleanup 永远不授权继续、retry 或 resume。

19. stale lock 只能在进程树为零、路径/大小/hash/timestamp/handle 全部验证且外部 receipt 已保存后按 exact target 受控清理；如果无法证明安全，不得清理，pilot 停止等待用户。

## 七、测试与正式 pilot 前硬门禁

20. 至少通过：

   - Windows PowerShell 5.1 与当前 PowerShell parser/binding；
   - schema/parser、stable/ordinal serialization、hash/provenance；
   - Unity compile；
   - PSAPI/CIM stage telemetry probe；
   - composite process identity；
   - stage-delta 公式和 byte/MiB boundary fixtures；
   - equal/one-byte-over、negative、missing、NaN/Infinity/overflow；
   - Williams row/position/predecessor balance；
   - per-sample reset、structural/correctness exact-match；
   - primary + secondary failure precedence；
   - negative fail-closed、partial block atomicity 和 lock exact-target protection；
   - deterministic regeneration；
   - no-write-to-attempt2 root；
   - formal attempt-3 root/receipt absence；
   - validation-only final audit。

21. 允许对 pilot 尚未开始前、本阶段新建的 instrumentation/wrapper/schema/tests 中已确认的实现兼容性缺陷进行 versioned 自动修复与 validation-only retry；每个失败 attempt 保存独立 receipt/log/manifest/checkpoint/hash。不得通过改变矩阵、Williams balance、安全 stop、reset、correctness 或 telemetry 语义取得通过。

## 八、一次 NON-FORMAL pilot 与两阶段提交

22. 只有全部 pre-pilot 门禁通过后，才允许创建全新根：

   `H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1`

   并创建精确绑定 specification、schedule、instrumentation、authorization、resolved root 和 preflight 的 pilot execution receipt。

23. pilot 只能启动一次，严格按 schedule 执行。所有输出明确标记：

   `NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / NOT-ALGORITHM-SUPERIORITY-EVIDENCE`。

24. 应用两阶段提交：

   - 阶段 A：Unity measured blocks 完成后先冻结 raw execution manifest、完整性、文件/hash/tree、schedule/Williams 配额、environment end snapshot，并标记 `PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`；
   - 阶段 B：分析器只读访问冻结 raw root，每次分析写入独立 versioned attempt 目录；普通分析器 bug 只修复和重跑分析，不重跑 Unity；
   - 只有 raw 数据违反冻结采集合同，才停止并请求新的实验授权；不得自动重跑或补齐 measured blocks。

25. measured execution 任一硬门禁失败时保存原子 failure receipt、partial manifest、checkpoint、当前 block/run/stage、文件数/bytes/hash 后停止；禁止自动 retry/resume/top-up/merge。已经启动 measured execution 的失败 pilot 不得继续到新 attempt，除非用户另行授权。

## 九、只读分析与决策产物

26. 成功冻结 raw pilot 后，只运行预注册的只读诊断分析，至少报告：

   - 各 stage 的 absolute memory 与增量分布；
   - scale × Williams row × position × predecessor × algorithm 的完整、非选择性切片；
   - first-crossing stage 和 plateau/trend；
   - 512/640/768/1,024 MiB 的 exceed/near-miss counts 与不确定性；
   - 4 GiB absolute cap、2 GiB delta emergency 和 8 GiB free-memory floor 的安全裕度；
   - PSAPI/CIM 一致性；
   - reset/GC/caching/process-age 敏感性；
   - 是否支持 scenario-size-aware envelope；
   - 是否存在可重复的 runaway-growth evidence；
   - false-pass/false-fail、算法公平性和 32 GiB 主机风险。

27. 输出前瞻性 memory policy decision matrix 和 recommendation，但所有候选仍保持 `CANDIDATE`，除非本次授权文本中的测试与 pilot 证据足以形成一个明确、前瞻性的推荐；即使产生推荐，也不得自动改写 formal config、创建 attempt-3 root/receipt 或启动 attempt 3。

28. 不得运行 C1–C5/P1–P5 superiority、正式 effect estimate、正式 n_formal 或 Gate 14R 分析。

## 十、停止条件

29. 成功后只允许生成：versioned pilot raw freeze receipt、独立 analysis result、memory-policy recommendation/readiness checkpoint、updated Overall Project Plan/Next Session Checkpoint，以及下一阶段可复制授权提示词。

30. 完成后立即停止并向我提交：

   - 96 measured blocks / 384 samples 与最多 8 warm-up 的完整性；
   - stage-separated memory 结果；
   - g032/g064/g128/g256 scale trend；
   - algorithm/position/predecessor 的诊断边界；
   - 512/640/768/1,024 MiB 与 absolute/scenario-aware/layered policies 对照；
   - safety-stop 结果；
   - failure-precedence 与 lock-hygiene 验证；
   - raw/analysis 两阶段提交状态；
   - 冻结输入前后不变性；
   - 推荐但尚未正式采用的 policy；
   - 所有新增文件路径与 SHA-256；
   - 一份下一阶段授权提示词。

本授权明确不授权 Gate 13R-PR2 formal attempt 3、attempt 2 retry/resume/top-up/merge、formal output root、formal execution receipt、正式统计分析、Gate 14R、根据 partial/pilot 数据宣布算法 superiority，或把 NON-FORMAL pilot 样本合并进正式数据。

---
