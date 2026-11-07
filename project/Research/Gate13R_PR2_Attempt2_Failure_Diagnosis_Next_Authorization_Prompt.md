# Gate 13R-PR2 attempt 2 失败证据冻结与非执行诊断授权提示词

复制以下正文作为下一条授权消息：

---

授权 Gate 13R-PR2-FD1「attempt 2 失败证据冻结、内存门禁与 lock-hygiene 非执行诊断、候选修订设计和 validation-only 验证」。本次授权不授权 Gate 13R-PR2 attempt 2 的 retry、resume、top-up 或 partial merge；不授权 attempt 3，不授权任何新的 Unity Editor 运行、正式统计分析或 Gate 14R。

## 一、唯一活动失败证据与已知边界

1. 本阶段唯一允许诊断的正式失败根为：

   `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2`

2. 本阶段必须绑定并核验：

   - `Research/Gate13R_PR2_Formal_Execution_Receipt.v2.json`，已知 SHA-256：`a21466228b1e91dd8670093953b28333e235c9ff031b54fe385301c93ee8365e`；
   - `Research/Gate13R_PR2_Formal_Execution_Status.v2.json`；
   - attempt 2 formal checkpoint、partial-output manifest、launch receipt、stdout/stderr；
   - global process ordinal 934 对应的 schedule/config/plan；
   - block `g13rpr2-c52-b0022` 的 block checkpoint、block failure、Unity log、四个位置的已有输出；
   - `p04-cff/memory-gate-evaluation.json`，已知 SHA-256：`7e91da24abee3ae3b440391457b9dac7ede0228718f2aeeb5ff55804425dc6a3`；
   - `g13rpr2-c52-b0022.quiescence-failure.json`；
   - Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R v4、PR1/PR1B、PR2 preparation、attempt 1 与 attempt 2 的全部冻结输入和历史证据。

3. 在任何新诊断文件写入前，先只读复核下列预期事实；若不一致，记录差异并 fail closed，不得凭本提示词覆盖实际证据：

   - attempt 2 最终状态为 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`；
   - `rawDataComplete = false`，不存在成功的 raw-data freeze receipt；
   - 已完整完成 933 / 3,552 个 block processes；
   - 已完整完成 3,732 / 10,176 个 algorithm samples；
   - 已完整完成 19 个 campaigns，并完成第 20 个 campaign 的前 21 / 48 个 blocks；
   - 第 934 个 process、block `g13rpr2-c52-b0022` 在 position 4、C-FF、predecessor IDFF 处失败；
   - 失败 block 的前三个位置属于 partial/uncommitted evidence，不计入已完整完成样本；
   - orchestrator 和 Unity Editor 均已退出；
   - `H:\DDM_Final_Project\Temp\UnityLockfile` 是当前遗留的 0-byte stale lock；
   - partial-output manifest 在自身写入前记录 28,019 个文件；当前根包含该 manifest 后应解释为约 28,020 个文件，而不是将差 1 错判为证据篡改；
   - attempt 2 部分根约为 8,536,611,302 bytes，但必须以新的稳定快照实际值为准。

4. attempt 2 的 933 个完整 blocks、失败 block 的三个部分样本以及全部其他 partial outputs 永久保持：

   `PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS / NO-RESUME / NO-TOP-UP / NO-MERGE`

   它们只可用于失败诊断、门禁设计和成本评估，不得用于 C1–C5 superiority、P1–P5 正式效应估计、正式样本量结论或 Gate 14R 推断。

## 二、attempt 2 证据冻结

5. 在改动 stale lock 或创建诊断脚本前，对 attempt 2 根和全部外部 sidecars 执行稳定性检查：

   - 解析绝对路径；
   - 连续稳定读取；
   - 文件数量、原始字节数、最后写入时间；
   - 每个文件 SHA-256；
   - 稳定排序的 canonical tree SHA-256；
   - receipt/config/schedule/readiness/adapter/authorization/status/checkpoint/manifest/log 的独立 SHA-256；
   - 当前进程树、Unity 数量和 UnityLockfile 状态。

6. 在 attempt 2 根外创建独立、版本化、原子写入的：

   - failure-preservation receipt；
   - full partial-output evidence manifest；
   - frozen-input manifest；
   - provenance；
   - checkpoint。

7. 完整 manifest 写入并自验证后，将 attempt 2 根内现有文件冻结为只读历史证据，再次核验所有字节哈希和 canonical tree hash 不变。不得覆盖、删除、重命名、移动或补写根内任何文件；只读属性变化必须单独记录，不能伪装成字节内容变化。

8. Gate 13R-PR2 attempt 1、attempt 2、全部 pilot、Gate 10R/11R/12R/PR1/PR1B 证据、原始脚本、原始场景和原始项目归档必须保持字节不变。

## 三、stale UnityLockfile 的受控处理

9. 在任何清理前，完整记录精确目标：

   `H:\DDM_Final_Project\Temp\UnityLockfile`

   包括解析路径、是否为 reparse point、大小、SHA-256、创建/写入时间、独占打开能力、相关 PID/handle、当前 Unity 进程数和项目路径。

10. 只有同时满足下列条件时，才授权删除上述唯一 stale lock 文件：

   - Unity Editor 进程数为 0；
   - attempt 2 orchestrator 已退出；
   - 文件解析路径与上述精确路径一致；
   - 文件不是目录、不是 reparse point；
   - 文件为 0 bytes，SHA-256 为 SHA-256(empty)；
   - 时间戳和 quiescence-failure receipt 一致；
   - 没有活动进程持有该 lock；
   - 完整 pre-cleanup 证据已原子保存。

11. 删除后创建独立 cleanup receipt，并再次证明 Unity 数量为 0、目标 lock 不存在、attempt 2 根哈希不变。不得删除 `Temp` 目录、其他 lock、其他 Unity 项目文件或用户进程；若任一条件不满足，不得清理，只报告阻断原因。

12. stale lock 清理只用于恢复项目的非运行静态状态；本阶段清理后仍禁止启动 Unity。

## 四、primary memory failure 与 secondary quiescence failure 诊断

13. 必须按时间顺序区分两类失败：

   - primary：C-FF 样本的正式 memory eligibility hard fail；
   - secondary：Unity 异常退出后遗留 lock，导致 post-exit quiescence fail。

14. 复核第 934 个 block 的预期内存事实：

   - sample retained managed growth：2,080,768 bytes；
   - block retained managed growth：89,227,264 bytes；
   - block working-set growth：614,866,944 bytes；
   - block private-memory growth：641,327,104 bytes；
   - managed block hard limit：268,435,456 bytes；
   - working-set hard limit：536,870,912 bytes；
   - private-memory hard limit：536,870,912 bytes；
   - expected verdict：`HARD-FAIL-BLOCK-WORKING-SET-512MIB+HARD-FAIL-BLOCK-PRIVATE-MEMORY-512MIB`。

15. 不得只检查失败样本。必须只读重建 attempt 2 所有可用 memory-gate evaluations、sample summaries、block manifests、block plans 和 telemetry，并按以下层级审计：

   - scenario/campaign；
   - grid size 和其他冻结 factor levels；
   - algorithm；
   - Williams position；
   - predecessor；
   - block ordinal；
   - process age；
   - per-sample managed growth；
   - block retained managed growth；
   - block working-set growth；
   - block private-memory growth；
   - absolute working set/private memory 与相对 baseline growth；
   - threshold headroom、near-miss 和 first-crossing。

16. 必须检查失败是否属于：

   - 单点异常；
   - g256 或其他规模因素下的系统性容量增长；
   - C-FF 特定效应；
   - position-4、IDFF predecessor 或 Williams row 的混杂；
   - Unity/AssetDatabase/domain reload/cache 的正常常驻增长；
   - reset 不完整；
   - telemetry 或 baseline 定义错误；
   - working-set/private-memory 阈值与 managed-memory eligibility 语义不一致；
   - 真实的进程级资源失控。

17. 必须验证 PSAPI/CIM、PID/start-time/block identity、单位换算、baseline 选择、清理边界、GC 计数和 telemetry completeness。不得把 working set、private memory、managed memory 三者混为同一概念，也不得仅凭当前证据直接断言 native-memory leak。

18. 对失败前相邻 blocks、同 scenario 的全部可用 blocks、相同算法不同 position/predecessor、相同规模的其他可用 campaign 做敏感性比较。不得因某种切片对修订门禁更有利而选择性报告。

19. quiescence 诊断必须确定：

   - Unity 已退出而 0-byte lock 保留的时间顺序；
   - 60 秒 quiescence 是否只是观察到 secondary hygiene failure；
   - wrapper 是否错误地用 secondary failure 遮蔽了 primary memory failure；
   - 未来候选 wrapper 应如何同时保留 primary 与 secondary reason，而不放宽 fail-closed、不得继续下一个 block、不得自动清理后续跑。

## 五、memory policy 候选决策矩阵

20. 当前 attempt 2 的 512 MiB working-set/private-memory 门禁不得事后改写；无论诊断结论如何，attempt 2 永久保持 failed/excluded。

21. 只生成前瞻性、UNFROZEN 的候选政策决策矩阵，至少比较：

   - 保持当前 512 MiB block delta hard fail；
   - 640 MiB、768 MiB、1,024 MiB block delta 候选；
   - 与场景规模无关的绝对 process-memory cap；
   - 预注册的 scenario-size-aware envelope；
   - managed-memory 继续 hard fail，而 working-set/private-memory 改为带独立系统 RAM 安全上限的 eligibility/advisory 分层；
   - 其他由冻结证据支持、但不改变算法和场景语义的候选。

22. 每个候选必须报告：

   - 科学含义与测量对象；
   - false-pass / false-fail 风险；
   - 是否会把正常 Unity 资产加载误判为 planner leak；
   - 是否仍能发现真实 runaway growth；
   - 与 32 GiB RAM 主机和串行单 Unity topology 的关系；
   - 对算法公平性、scenario comparability 和结果可解释性的影响；
   - 对 Gate 10R/12R/PR1B 既有证据的兼容性；
   - 是否需要 instrumentation amendment；
   - 是否需要新的 NON-FORMAL targeted pilot；
   - 正式采用前的测试与 preregistration 要求。

23. 不得使用“让 attempt 2 通过”作为选择阈值的理由。不得依据本次 C-FF 结果方向或任何 P1–P5 性能结果选择最有利政策。候选政策必须保持 `UNFROZEN / USER-DECISION-REQUIRED`。

24. 如建议开展 targeted pilot，只能生成设计和下一阶段授权提示词。本阶段不得运行该 pilot。pilot 设计必须优先覆盖 g256、失败 Williams row/position/predecessor 和邻近阈值场景，同时保留足够的对照 row；不得将其冒充正式样本。

## 六、versioned 非执行修复与测试

25. 允许为本阶段新建 versioned 只读分析器、schema、synthetic fixtures、test harness 和 validation-only orchestrator。不得修改 active V4/V5/V6 command/module/wrapper/campaign 文件。

26. 如诊断确认 failure-cause masking，可创建一个候选、未激活的 versioned wrapper patch，要求：

   - primary Unity/block failure 永远保留为 primary cause；
   - quiescence failure 作为独立 secondary cause；
   - 二者均进入 checkpoint、receipt 和 manifest；
   - 任一失败仍 fail closed；
   - 不启动下一个 block；
   - 不自动 retry/resume/top-up/merge；
   - 不通过删除 lock 后继续当前 attempt；
   - 不改变算法、场景、telemetry、Williams、reset 或统计语义。

27. 测试至少覆盖：

   - frozen-input SHA-256 与 canonical tree；
   - stable-read 和 partial-manifest self-count reconciliation；
   - PID/start-time/block composite identity；
   - MiB/bytes 与 baseline 公式；
   - working set/private/managed 三种内存的区分；
   - threshold boundary、equal-to-boundary、one-byte-over、missing/non-finite/negative；
   - factor/algorithm/position/predecessor 分层；
   - primary + secondary failure precedence；
   - stale-lock exact-target protection；
   - zero-Unity requirement；
   - no-write-to-attempt2-root；
   - no formal-performance analysis；
   - no Unity command invocation；
   - no attempt-3 root/receipt；
   - deterministic regeneration；
   - pre/post upstream hash equality。

28. 允许对本阶段新建的非执行分析脚本、schema、fixtures 和 tests 进行版本化自动修复与 retry，直至测试通过或遇到无法通过软件修复解决的 scientific-identifiability hard gate。每个失败 attempt 必须保留独立 receipt、日志、manifest、checkpoint、哈希和 diagnosis；不得覆盖失败证据。

29. 自动修复不得修改冻结输入、删除不利证据、改变 threshold 候选的报告规则、启动 Unity、创建正式根、创建 attempt-3 execution receipt 或运行正式统计分析。

## 七、要求生成的版本化产物

30. 如下 v1 路径不存在则创建 v1；如已存在则递增版本，禁止覆盖：

   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Authorization.v1.json`
   - `Research/Gate13R_PR2_Attempt2_Failure_PreWrite_Audit.v1.json`
   - `Research/Gate13R_PR2_Attempt2_Failure_Preservation_Receipt.v1.json`
   - `Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Specification.v1.md`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Test_Design.v1.md`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-telemetry-inventory.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-threshold-distribution.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/factor-position-predecessor-sensitivity.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/primary-secondary-failure-timeline.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/lock-hygiene-diagnosis.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/memory-policy-decision-matrix.json`
   - `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/evidence-manifest.json`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.md`
   - `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Next_Authorization_Prompt.md`

31. 所有新产物必须原子写入、稳定排序、确定性序列化，记录 UTC 与 Asia/Shanghai 时间、输入/脚本/输出 SHA-256、PowerShell/.NET 环境、固定随机种子（如使用）和实际重试历史。

32. 新产物必须显式标记：

   `NON-EXECUTING / FAILURE-DIAGNOSTIC-ONLY / PARTIAL-FORMAL-ATTEMPT-EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-ATTEMPT3-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

## 八、计划更新与停止条件

33. 只有证据冻结、诊断测试、deterministic regeneration、hash/provenance 和 validation-only final audit 全部通过后，才允许更新：

   - `Research/Overall_Project_Plan.md`；
   - `Research/Next_Session_Checkpoint.md`。

34. 计划更新只能记录：

   - attempt 2 在 933 个完整 processes 后失败；
   - primary memory hard fail 与 secondary stale-lock quiescence failure；
   - attempt 2 永久 excluded/no-resume/no-merge；
   - 两阶段提交未进入 raw-data-complete；
   - memory policy 和后续 targeted pilot/attempt 3 决策尚未冻结。

   不得将 partial evidence 写成正式算法结果，不得重写历史记录。

35. 本阶段成功状态只能是：

   `ATTEMPT2-EVIDENCE-FROZEN / PRIMARY-MEMORY-FAILURE-DIAGNOSED / SECONDARY-QUIESCENCE-FAILURE-DIAGNOSED / MEMORY-POLICY-UNFROZEN / FORMAL-ATTEMPT3-NOT-AUTHORIZED / FORMAL-ANALYSIS-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

36. 如果现有证据不足以区分正常 scenario-scale memory growth 与真实资源泄漏，则输出：

   `TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED`

   但本授权下不得运行该 pilot。

37. 完成后立即停止并向我提交：

   - attempt 2 完整证据树摘要和 canonical tree SHA-256；
   - 933 个完整 blocks 与失败 block 的 memory telemetry 可用性摘要；
   - primary/secondary failure timeline；
   - working-set/private/managed 的分布、near-miss 和 factor/position/predecessor 诊断；
   - 512/640/768/1,024 MiB 及其他候选政策决策表；
   - stale lock 处理 receipt；
   - 是否建议 targeted NON-FORMAL pilot 的 verdict；
   - 所有新增文件路径和 SHA-256；
   - 冻结输入前后不变性结果；
   - 更新后的整体计划与 session checkpoint；
   - 一份可直接复制的下一阶段授权提示词。

本授权明确不授权任何 Unity Editor 运行、Gate 13R-PR2 attempt 2 retry/resume/top-up/merge、attempt 3、正式统计分析、Gate 14R、正式样本补齐、历史输出合并或根据 partial results 宣布算法 superiority。

---
