# DDM Final Project — 整体研究与实施计划

文档状态：主计划（Living Plan）  
版本：4.11  
建立日期：2026-10-04（Asia/Shanghai）  
项目根目录：`H:\DDM_Final_Project`  
Unity：`2022.3.30f1c1`  
当前恢复点：Gate 13R-PR2-MP2 与 attempt-3 monitoring/recovery v2 非执行 amendment 均已在 formal data 产生前完成。MP2 scenario-scale policy、active V4 candidate 和 S48/H48 schedule 保持冻结；active v2 monitor 将运行期监控固定为每 5 分钟静默检查，并在 acquisition、commit-pending 或 raw-commit-recovery 状态中每 60 分钟最多报告一次，同时保留开始/失败/完成/action-required/stall 事件报告。自动排障被严格分层：formal root/receipt/status 与 measured count 均为零时最多 3 次 versioned prelaunch repair；采集期只允许只读诊断，绝不 retry/resume/top-up/merge/skip/replace/advance；3,552 processes / 10,176 samples 全部完成后，才允许针对同一稳定 raw tree 最多 3 次 non-Unity commit recovery。validation attempts 1–2 与 v1 readiness 均保留；终审发现 v1 遗漏 raw-commit 小时报告后完成第 1 个 versioned repair cycle，active attempt 3 通过 56/56。全部活动上游哈希不变，formal attempt-3 root、receipt、status 与 measured samples 均不存在，Unity 与项目锁均为零。下一步只能在用户单独授权后按 active v4 prompt 创建并执行 formal attempt 3；正式统计分析与 Gate 14R 仍未授权。精确恢复点见 `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json` 与 `.md`。

---

## 1. 文件用途

本文件是整个项目的统一路线图，用于回答以下问题：

1. 研究最终要比较什么；
2. 当前已经完成并验证了什么；
3. 后续各 Gate 的输入、工作内容、验收条件和依赖关系；
4. 哪些工作可以自动继续，哪些工作必须先获得用户明确授权；
5. 正式实验如何保证公平、可重复、可审计；
6. 如何从算法实现推进到实验数据、统计分析和最终论文交付；
7. 如何在不设置自定义 Codex 用量上限的前提下，于实际平台中断、用户暂停、技术失败或 Gate 完成时保存可恢复检查点。

本文是计划。Gate 1–9 是算法正确性与基础设施前提；Gate 10R attempt 4 的 block-process 合同、Gate 11R attempt 2 retained bundle、Gate 12R v4 pilot、Gate 13R-PR1 前瞻性 amendment、Gate 13R-PR1B v4 只读 order-effect recovery、PR2 active v2 preparation、PR2-FD1 failure diagnosis、MP1 v2 的冻结 raw/独立只读 diagnostic analysis、MP2 active V4 candidate/readiness，以及 attempt-3 monitoring/recovery readiness 构成当前活动实验主线。MP1 pilot v1 已作为 zero-block orchestration failure 冻结；MP1 v2 是 `NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS` 证据，不是算法 superiority 数据。MP2 只把这份先验诊断转成前瞻性 formal-attempt-3 policy/config/adapter 合同；monitoring amendment 只增加盲化运行状态与受限软件恢复，不改变实验 observation、研究合同或样本量。旧 Gate 10–13、cold-process formal attempts、早期 Gate 13-R2 pilots、PR1B 失败 attempts、PR2 validation failures/v1 artifact set、PR2 formal attempts 1–2 和已被 PR1 supersede 的 strict-serial 10% v2 启动设计均只作为独立历史/诊断证据保留，不得直接启动或向活动统计迁移 observations。

2026-10-06 的用户决定替代了旧 Gate 10 以后活动路线：从 Gate 10R 重新冻结 process-reuse 公平合同、Gate 11R 新矩阵和全覆盖 Playable bundle、Gate 12R fresh pilot、Gate 13R block-process formal campaign，以及后续 block-aware analysis/replay。活动执行语义仍以 `Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md` 和已通过 Gate 10R attempt 4 为基础；PR1 只前瞻修改尚未产生的 Gate 13R formal 数据之研究问题、contrast、endpoint hierarchy 和样本设计，不重做 Gate 10R/11R，也不改写 Gate 12R pilot。当前授权边界以 `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json` 为准；它没有授予 formal launch。

随后用户一次性授权按顺序执行 Gate 10R、Gate 11R 和 Gate 12R。Gate 10R 新规格、测试设计、config、provenance、Unity command、PowerShell module/wrappers 和验证脚本完成；正式 attempt 1 在运行任何单元断言或 Unity 进程前即因 `Run-Gate10RUnitTests.ps1` 的默认 `ProjectPath` 表达式与 Windows PowerShell 5.1 参数绑定行为不兼容而退出 1。依照用户冻结的 no-auto-retry/no-resume 规则，本次没有修复后重跑，已生成 failure receipt、partial manifest 和 terminal checkpoint。Gate 11R/12R 的授权因 Gate 10R 未通过而未被消费为执行，后续必须先获得独立的 attempt-2 重试授权。

用户随后明确授权 attempt 2 的版本化入口兼容修复与一次重试。attempt-1 证据先经只读完整性审计；九个 v2 入口的 Windows PowerShell 5.1 parser/binding/absolute-ProjectPath/root-isolation 检查全部通过。正式 attempt 2 通过 38/38 unit、Unity compile、telemetry probe、三个正向 block 和预期负向 fail-closed fixture，但负向 fixture 退出后零字节 `Temp/UnityLockfile` 持续存在，首个 cold structural control 的启动前 guard 因而拒绝启动 Unity。attempt 2 已以 `GATE10R-ATTEMPT2-FAILED-NO-AUTO-RETRY` 封存；98 个 partial artifacts / 9,337,336 raw bytes 被 manifest 绑定。条件式 Gate 11R/Gate 12R 授权因 Gate 10R 未全通过而停止，不能跳过硬门禁继续。

用户随后明确改为仅授权 Gate 10R，并撤销 Gate 11R/Gate 12R 授权。attempt 3 采用新的 versioned lock-hygiene 规格：正向、compile、telemetry 和 cold 进程只能自然释锁；只有 attempt-2 已确认遗留锁与预期负向 fixture 可在 60 秒观察、PID 退出、Unity 总数为 0、精确路径、空文件哈希、非 reparse、独占打开和归属时间窗全部满足时留证并删除。67/67 preflight 安全移除 attempt-2 空锁；正式执行通过 59/59 unit、compile、probe、3 positive + 1 expected-negative block、6 cold references、10/10 structural comparisons 和独立进程重复性。原 lock-transition 故障因此已解决。其后冻结的 63 项回归源以 child `ScriptBlock` 运行时，局部 `$assertions` 与 helper 写入的 `$script:assertions` 分属不同作用域，输出 `passed=true`、0 failure、但 `assertionCount=0`；硬门禁按要求退出 1。attempt 3 已封存 162 个 partial artifacts / 14,598,617 raw bytes，未重试、未运行 final audit、未进入任何后续 Gate。

用户随后授权 Gate 10R attempt 4 的受控、版本化 file-scope wrapper 修复与 retry/resume 直至首次完整通过，并继续明确禁止 Gate 11R/12R/13R。attempt 4 在官方根外完成 parser、binding、机械差异、输出隔离、历史不变性和 retained `63/63` smoke；两次 preflight-only 审计入口问题分别原子封存后，v3 preflight 通过 `64/64`。官方执行通过 preflight、unit、compile 和 telemetry；首次 block 入口在 Unity 启动前发现 provenance projection 兼容问题并原子封存，随后使用仅恢复旧字段投影、不改变研究语义的 v4.3 compatibility provenance 完成授权 resume。最终 3 positive + 1 expected-negative block、6 fresh cold controls、10/10 structural comparisons、retained `63/63`、final audit `55/55` 与 terminal integrity `8/8` 全部通过。`v4` 固定为 169 文件 / 14,661,848 bytes / tree SHA-256 `ac7f70b2098f6fc28eaa48116faabe1a527f34168d1c851f5a5d7e8cbbbc53b2`；下游根均未创建。

2026-10-07，用户单独授权 Gate 11R，并允许对 Gate 11R 内部实现/编排问题进行版本化自动修复与重试直至通过，但要求在 Gate 12R 前重新申请授权。preimplementation attempt 1 的 73/74 跨 PowerShell 文件排序失败、两次 compile 入口错误、generation attempt 1 的隐藏 AssetDatabase staging 路径失败，以及两次 final-audit 脚本投影/UTF-8 读取失败均完整保留；它们没有产生 pilot 或正式 timing 数据。活动 attempt 2 最终通过 cross-runtime preimplementation `48/48`、unit `1269/1269`、generation `1544` assertions、fresh-process verification `5893` assertions、212/212 planner initialization 和 final audit `89/89`。通过 bundle 的 manifest SHA-256 为 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`。

2026-10-08，Gate 12R 在三次独立失败 attempt 全部冻结后完成前瞻性 managed-memory 聚合修订：逐样本 retained managed 门禁仍为 128 MiB，完整 block 门禁按冻结样本数缩放为 256/512 MiB，working-set/private 门禁仍为 512 MiB。pre-pilot v7 全部通过；pilot v4 完成 429 个 Unity processes / 1,212 个 workload samples，结构对照 1,152/1,152、memory hard gate 384/384、最终 readiness 951/951。候选正式设计为 74 campaigns、42,064 个 Williams-block processes、119,200 samples；串行 p95 约 317.07 h，启动存储门槛 188,047,724,816 bytes。

同日，用户单独授权 Gate 13R 非执行准备而未授权正式 campaign。准备阶段建立 versioned specification、test design、readiness amendment、正式 config/provenance、全量 Williams-block schedule、validation-only orchestrator、raw-byte storage preflight、正式 receipt guard 与原子 checkpoint。两次机械 command derivation 计数假设、一次 Windows PowerShell 5.1 StrictMode 空枚举以及一次 coverage schema 假设失败均以独立证据保留；版本化修复未改变冻结实验语义。最终 51/51 unit、Unity compile、32/32 schedule validation、负向 execute-without-receipt、byte-identical deterministic regeneration 和 47/47 final audit 通过。readiness checkpoint SHA-256 为 `4cb0763f9b1717b8e92ac8f3a1b13b1b09d543fd3f720da9b61e06e7a4dce182`；formal root、formal receipt 和 timing samples 仍不存在。

随后用户把 formal campaign 的硬墙钟上限先设为 48 小时，再以最新决定改为 36 小时。该决定不就地改写已封存的 5% config/schedule/readiness，而是前瞻阻止其启动。只读重算显示：10% per-campaign 精度对应 11,160 blocks / 31,536 samples / 串行 p95 83.90 h；推荐候选为 4 个隔离 Editor lanes，理想 p95 20.98 h，并以新的 readiness p95 不超过 27 h 作为建议安全门槛。该候选尚未获用户选择，也未获并发 pilot、重配置或正式执行授权；正式记录见 `Research/Gate13R_36h_WallClock_Constraint.v1.json` 和 `Research/Gate13R_36h_Redesign_Discussion.md`。

随后用户正式选择并授权上述 36 h redesign 的 versioned 非执行实现、四个隔离项目副本与一次 NON-FORMAL pilot，但仍未授权 formal campaign。v16 readiness verification 全部通过后，pilot 于 2026-10-08 14:17（Asia/Shanghai）启动；8 个 warm-up blocks 和前 79 个 measured waves 均通过。wave 80 的 lane 1 与 lane 3 在 Unity 启动约 3.6 秒后因未获得 serial/entitlement 而退出 1，lane 2 与 lane 4 虽完成但整个 partial wave 永久排除。pilot 原子保存 6,581 文件 / 3,582,281,468 raw bytes 后终止，状态为 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-MERGE`。机器可读诊断 SHA-256 为 `8a1aa36a3f7fdaea4afe6eef00d7e33e99843b36553e6d1afd898bf3e2750ae1`；下一步只能在新授权下建立 versioned licensing-stability repair、测试与全新 pilot root，不能恢复 v16。

其后曾建立三 lane 稳定性优先候选，但该路线未成为可用正式证据并已封存为排除历史。2026-10-08 用户进一步明确取消所有并行，改用严格串行。新路线不恢复、不修补、不合并任何四 lane/三 lane 输出；它复用 Gate 12R v4 已通过且完全相同的“一 Williams block 一 fresh Unity、进程间零重叠”拓扑证据，并把正式精度前瞻性改为 10%。首个 serial formal-preparation v1 因错误复用旧 5% 存储阈值而被 validation-only 门禁拒绝；v2 修复该兼容缺陷后完成 114 项 readiness、38 项 schedule 与 156 项 final audit。正式执行仍需单独授权，并必须明确接受 p95 `83.904223147 h` / 建议 `96 h` 的串行时间包络。

随后 Gate 13R-PR1 在任何正式数据产生前前瞻性修订研究问题与统计合同。它保留 74-campaign 矩阵与严格串行 block-process 拓扑，但把 shared-goal 四算法完整 block 定为唯一 primary confirmatory scope、P1 定为唯一 primary endpoint，并将 heterogeneous 限定为 secondary system/treatment interpretation。Gate 12R v4 的 384 blocks / 1,152 samples 只读重分析证明 P1–P5 可观测，并确认 heterogeneous 96 pairs 的执行顺序为 89:7、不具备 AB/BA pilot balance。PR1 final audit 66/66 通过；旧 144/204/108 serial v2 不能启动，最终样本设计仍未冻结。

随后为提高 heterogeneous secondary 的 pilot-level order-effect 可识别性，Gate 13R-PR1B 建立 3 个 heterogeneous scenarios × 32 mirrored AB/BA pairs 的 balanced non-formal pilot。v3 path-safe attempt 已完整产生 12 warm-up processes、384 measured fresh block processes 和 768 measured samples，但冻结 v1 analyzer 把 numeric PID 误当作全局唯一身份，因 Windows 合法 PID reuse 在 post-execution analysis 失败。v4 没有重跑 measured blocks，而是先通过复合身份 validation，再对原冻结完整 raw evidence 执行唯一一次只读 recovery：19 个 PID reuse groups 全部无重叠，P1 order effect 在 pilot 层面可识别但部分 cells 不确定，未发现 material order effect。该 evidence 只用于设计，推荐 heterogeneous 候选由 H32 提升为 H48；它不把失败 pilot 改写为通过，也不冻结 formal design。

随后用户按推荐方案授权 Gate 13R-PR2 非执行 formal preparation，并正式选择 `S48/H48`。PR2 未启动 Unity、未创建正式根或正式 receipt。validation attempts 1–2 因 PowerShell 运行时文件名排序差异在 core 前 fail closed，attempt 3 因新 schema 字段名错误在 62/63 core checks 后停止；三次证据均独立冻结。active v2 artifact set 用明确 `StringComparer.Ordinal` 树身份和修复后的 schema 重新生成，validation v4 在 Windows PowerShell 5.1 下通过 63/63、byte-identical deterministic regeneration 和冻结输入前后不变性。S48/H48 因而从候选升级为 `FROZEN-FORMAL-DESIGN / READY-FOR-SEPARATE-EXECUTION-AUTHORIZATION`，但不是已授权 launch。

随后用户分别授权 PR2 formal attempts 1–2；两次均按 one-shot fail-closed 规则停止，禁止 retry/resume/top-up/merge。attempt 2 在 ordinal 934 的 g256 shared block 上记录 block working-set/private-memory 512 MiB hard fail，随后又因零字节 UnityLockfile 遗留产生 secondary quiescence failure。FD1 将 28,020-file 部分根逐文件哈希并冻结只读，确认 3,736/3,736 memory evaluations 可用；关键修正是四个 sample boundaries 均已超过 native limit，首次出现在 position 1，而 hard fail 只在 position 4 final boundary enforce。故不得将 failure 归因于 C-FF、A*-R、position 或 predecessor。当前 memory policy 未冻结，formal attempt 3 未授权；下一步推荐一次四 scale、96-block 的 NON-FORMAL targeted memory pilot。

用户随后授权该 MP1 targeted pilot。新 stage-separated telemetry、failure-precedence wrapper、96-block/384-sample balanced schedule、two-stage contract 与全部 validation 通过，最终 pre-pilot audit 为 29/29。唯一一次 v1 measured launch 在第一个 Unity block 前因 checkpoint state-machine schema 缺陷立即停止；没有 Unity process、block plan、sample 或 raw data。其 5-file v1 root 已只读冻结，保存 failure receipt、zero-output manifest、失败 checkpoint 与原始 checkpoint backup。failure preservation 本身出现一次 `.NET 10 File.Replace(null backup)` 兼容失败，也已独立记录并以非空 backup path 完成证据冻结；它没有重启 pilot。下一步必须是单独授权的 versioned MP1 v2 修复和全新 pilot，不能恢复 v1。

用户随后授权 MP1 attempt 2 / v2。五个 pre-pilot validation 失败 attempts 均独立保留；其 versioned 修复只涉及 checkpoint/atomic persistence、入口兼容和根特定 canonical-tree audit。attempt 6 最终通过 `34/34`。随后唯一一次 authorized measured v2 pilot 完成 96/96 blocks 与 384/384 samples；Phase A 冻结 3,360 raw files / 2,607,785,161 bytes，tree SHA-256 为 `13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`。Phase B analysis attempt 1 只读处理该树并通过；一个误用 pre-pilot “v2 root must be absent” 条件的 post-pilot audit failure 被独立保存，versioned post-pilot audit v2 随后通过，未重跑 Unity。结果未发现 runaway growth 或 host-safety emergency；推荐的 512/640 MiB advisory 与 640/768 MiB hard ceilings 仍为 `RECOMMENDED-BUT-UNFROZEN`，需 MP2 独立授权。

用户随后授权 Gate 13R-PR2-MP2 非执行 policy 冻结、attempt-3 candidate adapter 与 validation-only readiness。MP2 在 future formal observations 产生前冻结 scenario-scale native residency、managed cleanup 和 host-safety 规则，并保持 74-campaign S48/H48 schedule、Williams/AB-BA、one-fresh-process-per-block、reset、correctness、telemetry、two-stage commit 和 no-auto-retry/resume/top-up/merge 不变。validation attempt 1 的 66/67、attempt 2 的 expected-negative lock-mode wrapper failure、attempt 3 的 V2 provenance hash transcription failure 均独立封存；没有任何一次创建 formal root/receipt 或正式 sample。active attempt 4 使用 V3 wrapper 与 V4 candidate artifacts，通过 69/69 static、22/22 threshold fixtures、8/8 telemetry sequence fixtures、PSAPI/CIM cross-check、positive complete block、native-hard/telemetry/persistence expected-negative blocks 和冻结输入 post-audit。formal attempt 3 仍未授权。

随后用户接受 attempt 3 的每小时进度与受限自动排障边界。非执行 amendment 建立盲化 status/snapshot schema、5 分钟 watcher、60 分钟报告节流、stall/ETA、不可覆盖监控快照和三阶段 recovery state machine。prelaunch repair 仅可在 formal 三个目标均不存在且 measured count 为零时版本化执行；采集期硬失败仍采用 `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`，只采集只读诊断；完整 acquisition 后普通 manifest/freeze 缺陷只可对同一 raw tree 做 non-Unity recovery。validation attempt 1 的单项失败与 versioned test-only repair 均保留，attempt 2 通过 54/54；heartbeat 已改为 5 分钟检查并由监控器内部 60 分钟槽节流。没有启动 Unity或创建 formal root/receipt/status。

terminal audit 随后发现 v1 notification function 只在 `ACQUISITION-RUNNING` 调度小时报告，未覆盖规格已经要求的 `ACQUISITION-COMPLETE-COMMIT-PENDING` 与 `RAW-COMMIT-RECOVERY`。该缺陷在 formal 三个目标仍为空、Unity 为零时按 prelaunch repair cycle 1 处理：v1 readiness/prompt/code 全部保留并标记 superseded，active v2 config 明确三个 scheduled-report states，v2 monitor/wrapper 仅修复通知与 active-state stale classification。validation attempt 3 重新执行原全套并新增两项 raw-commit tests，56/56 通过；heartbeat 已切换到 v2 wrapper。实验设计、采集门禁和 no-measured-retry 边界均未改变。

---

## 2. 总体研究目标

在同一套确定性网格、动态事件、预算、日志和统计协议下，比较以下导航规划方法：

| 标识 | 方法 | 角色 | 当前状态 |
|---|---|---|---|
| `A*-R` | Per-agent repeated A* | 每次请求完整重算的基线 | 已实现并验证 |
| `D*L` | Per-agent D* Lite | 每个 agent 维护增量最短路状态 | 已实现并验证 |
| `C-FF` | Corrected full-recompute flow field | 每次变化完整重算的流场消融基线 | 已实现并验证 |
| `IDFF` | Incremental Dynamic Flow Field | 共享目标集上的增量动态流场 | 已实现并验证 |

Gate 13R-PR1 冻结的 primary research question 是：在 shared-goal canonical scenarios 中，在正确性和结构门禁通过的前提下，C-FF 和 IDFF 是否在 P1 动态事件平均处理时间上分别优于 A*-R 与 D*L，以及 C-FF 与 IDFF 之间存在怎样的差异。

其五个正式目标 contrasts 为 C1 `C-FF/A*-R`、C2 `C-FF/D*L`、C3 `IDFF/A*-R`、C4 `IDFF/D*L` 与双侧 C5 `IDFF/C-FF`。P1 五 contrasts 构成 FWER 0.05 的 Holm confirmatory family。C-FF “优于两个基线”要求 C1 与 C2 同时满足判据；IDFF 同理要求 C3 与 C4；不得用指标多数表决或未注册总分替代。

次级问题保留：P2 tail latency、P3 per-agent cost/scaling、P4 allocation 与 P5 budget overrun 用于 supportive 机制解释；heterogeneous 比较 grouped-field system 与 per-agent system 的联合 treatment 差异，不归因为纯算法单因素；M1–M5 在 Gate 14R 才观测移动、到达、路径效率、帧时间和分类失败。


---

## 3. 研究范围与边界

### 3.1 当前主实验范围

第一阶段是确定性的规划微基准：

- agent 在初始阶段和每个动态事件阶段都从场景声明的固定起点规划；
- 不模拟 agent 移动；
- 不测量到达时间、碰撞、局部避障或渲染帧率；
- 重点测量初始化、规划、动态变化处理、工作量、分配、成功率和预算超限率；
- 新活动谱系从 Gate 10R 起把 process-reuse 作为基础合同：每个完整 Williams block 使用一个全新 Unity Editor，进程内按冻结顺序运行 2 或 4 个算法，每个算法最多一次；block 是独立运行时/统计聚类单位，block 内样本是配对相关观测。Gate 12R fresh pilot 已产生 5% 无 cap 候选 `n_formal` 548/768/400。

### 3.2 可选的第二实验阶段

只有在规划微基准完成并单独授权后，才建立移动/到达实验：

- 使用新的研究专用场景或原场景副本，不修改原始场景；
- 固定 movement、碰撞、采样频率和 arrival 判定；
- 测量 p95/p99 帧时间、95% 到达时间、路径效率、失败分类；
- 所有算法使用同样的可视反馈和物理设置；
- 移动实验的结论不得与固定起点规划微基准混写。

### 3.3 补充可视化范围

新谱系在 Gate 11R 就为每个实验条件建立研究专用可 Play 场景入口；正式数据和统计结果冻结后再生成 replay trace 并执行 OBS 录制：

- 计划提供 53 个 unique scenario `.unity` scenes、74 个 campaign launch profiles 和 212 个 algorithm-cell presets；每个统计重复通过 scene/profile/preset/block/position/run identity 映射，不复制物理场景；
- 可视化只消费冻结场景、确定性重建 trace 和 Gate 15R 派生摘要，不参与 Gate 12R/13R 正式计时；
- 规划重放与移动重放使用彼此独立的新 scene，均不得修改原始 scene；
- 视频中的代表性场景由预先记录的确定性规则选择，不按结果优劣事后挑选；
- HUD 必须持续显示“`VISUALIZATION REPLAY — NOT A TIMING RUN`”；
- 视频用于解释算法行为和补充展示，不作为运行时间、帧时间或统计显著性的测量证据。

### 3.4 明确排除项

- 不修改原始脚本和原始场景；
- 不把研究组件挂载到原始场景；
- 不把 NavMesh 作为主算法比较对象；
- 不在算法运行时随机生成未记录的场景内容；
- 不用墙钟时间调度动态事件；
- 不把三次 Gate 6 管线验证当作正式统计样本；
- 不在没有独立 oracle 的情况下接受新算法；
- 不因使用量充足而擅自开始未授权算法 Gate。

---

## 4. 不可破坏的项目保护规则

1. 原始归档保持只读：
   - `H:\DDM_Final_Project_Original.zip`
   - SHA-256：`b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa`
2. 每次主要 Gate 完成后重新核对 `Research/Baseline_SHA256.csv` 中 24 个冻结条目。
3. 所有新增运行时代码放入 `Assets/_Scripts/Research/`。
4. 所有研究规格、计划、协议和检查点放入 `Research/`。
5. 所有验证日志和固定证据放入 `Research/Verification/`。
6. 不覆盖已有实验目录；失败的部分输出也保留用于诊断。
7. Gate 5–10 的 `*_Final` 单次、重复或 campaign fixture 以及 current-code aggregate revalidation 作为固定证据，不重写。
8. `Superseded_Gate5_BatchFixture_PreAllocationFix` 只能作为明确标记的无效历史证据。

---

## 5. 当前已完成状态

### 5.1 已完成 Gate

| Gate | 内容 | 状态 | 主要验收证据 |
|---|---|---|---|
| Gate 1 | 冻结基线、导航/日志合同、真实 Unity 编译 | 完成 | 24 个冻结条目 0 不匹配 |
| Gate 2 | 研究网格、确定性场景、runner 骨架 | 完成 | 26 项断言 |
| Gate 3 | `A*-R` 规格、实现和独立参考验证 | 完成 | 133 项断言、36 个 Dijkstra 对照 |
| Gate 4 | 严格/规范 JSON 和固定起点工作负载 | 完成 | 36 项断言 |
| Gate 5 | 单次 headless Unity 批处理和哈希 manifest | 完成 | 18 项管线检查 |
| Gate 6 | 场景目录、独立重复、统计聚合和最终审计 | 完成 | 26 + 28 项断言、19 类管线检查、11 类总审计 |
| Gate 7 | `D*L` 规格、实现、独立动态参考验证与批处理接入 | 完成 | 411 项断言、24 个静态及 72 个动态参考案例、单次/三进程证据、11 类总审计 |
| Gate 8 | `C-FF` 规格、反向多源 oracle、完整流场实现与批处理接入 | 完成 | 86,089 项断言、24 个初始及 72 个动态全场对照、单次/三进程证据 |
| Gate 9 | `IDFF` 规格、逐事件 fresh-C-FF 全 cell oracle、增量实现与批处理接入 | 完成 | 103,138 项断言、24 个初始及 96 个动态 fresh-C-FF 场、3,600 cell 对照、单次/三进程证据 |
| Gate 10R | Williams-block 进程、公平合同、reset/telemetry/原子 runner | attempt 4 完成 | `59/59` unit、compile/probe、3 positive + 1 expected-negative、6 cold、10/10 structural、retained `63/63`、final `55/55`、integrity `8/8` |
| Gate 11R | 5% 正式矩阵、确定性身份与全覆盖 Playable bundle | attempt 2 完成 | 53 scenarios、74 profiles、212 presets、53 scenes + launcher；`1269/1269` unit、`5893` verification、`89/89` final audit |
| Gate 12R | fresh block-process pilot、相关性、5% 无 cap 样本量与资源投影 | attempt 4 完成 | 384 blocks / 1,152 measured samples；1,152/1,152 structural；384/384 memory gates；readiness `951/951`；候选 548/768/400 |
| Gate 13R-PR1 | 研究问题对齐、五 contrasts/十指标预注册、Gate 12R v4 只读重分析与候选设计比较 | 完成 | P1–P5 observability 通过；96-pair order audit；双重确定性重生成；final audit 66/66 |
| Gate 13R-PR1B | balanced mirrored heterogeneous order-effect pilot 与复合身份只读 recovery | v4 recovery 完成 | raw pilot 仍 failed/excluded；validation 23/23；396/396 composite identities；96 pairs / 768 measured samples；P1 9 bounded、2 below-bound、5 inconclusive、0 material；零 Unity recovery |
| Gate 13R-PR2 | 冻结最终 S/H、planning-effect 解释与正式 schedule，并重建非执行 formal preparation | 完成；validation v4 通过 | active v2 config/schedule；S48/H48、3,552 processes / 10,176 samples；63/63 core |
| Gate 13R-PR2 formal attempts 1–2 | 研究问题对齐后的完整 74-campaign 正式 planning benchmark | 两次失败并冻结 | attempt 2 partial root 28,020 files / 8,536,611,302 bytes；永久 excluded/no-resume/no-merge |
| Gate 13R-PR2-MP1 v2 | 四 scale targeted memory pilot、两阶段提交与只读诊断 | 完成 | pre-pilot 34/34；96/96 blocks；384/384 samples；raw tree `13dd5c30...`；policy recommended but unfrozen |
| Gate 13R-PR2-MP2 | 前瞻性 memory-policy 冻结与 formal-attempt-3 非执行 readiness | 已完成；attempt 4 通过 | active V4 candidate；69/69 static；22/22+8/8 fixtures；positive + 3 expected-negative blocks；formal root/receipt absent |
| Gate 13R-PR2 attempt-3 monitoring/recovery | 盲化小时进度、stall/ETA 与分阶段受限软件恢复 | active v2；validation attempt 3 通过 | 5-minute watcher / 60-minute report across acquisition+raw commit；56/56；采集期零 measured retry；formal targets absent |

旧 Gate 10–13 已移出活动完成表，单独见 `Research/Historical_Gate10_to_Gate13_Archive.md`。

### 5.2 当前实现清单

- 四个正式研究 planner：`AStarRepeatedPlanner`、`DStarLitePlanner`、`CorrectedFullRecomputeFlowFieldPlanner` 与 `IncrementalDynamicFlowFieldPlanner`；
- 3 个 correctness 场景 fixture，以及活动 `Research/FormalScenarios/Gate11R_5pct/v1/` 中 53 个冻结 formal scenarios；
- 单次规划运行器；
- 多进程重复实验运行器；
- Williams 平衡的四算法/两算法 block-process 调度器；
- JSONL 操作日志；
- 单次 manifest、group manifest 和 campaign manifest；
- 公平 schema、目标 cohort、状态/field 数量、规格与实现 SHA-256 provenance；
- 均值、中位数、p95、样本标准差、标准误和 Student-t 95% CI；
- Gate 11R formal matrix、catalog、preregistration、bundle manifest，以及 53 scenes / 74 profiles / 212 presets 的 Playable coverage；
- Gate 12R 的 12-campaign subset、环境/电源/热/存储 preflight、PSAPI+CIM telemetry、block-aware 噪声/相关性/样本量分析器；
- 每个样本 128 MiB retained managed、完整 block `128 MiB × expectedSampleCount`、working/private 512 MiB 的 versioned hard-gate implementation；
- Gate 12R 成功 pilot v4 的 429 个 Unity processes / 1,212 workload samples、8,714-file evidence manifest、候选 548/768/400 和 951/951 readiness audit；
- Gate 13R-PR1 的 amendment、五 contrasts、十指标 registry、matched-superblock specification、Gate 12R v4 reanalysis、candidate sensitivity 与 wall/storage decision table 已冻结并通过；旧 strict-serial 10% v2 保留为不可启动 comparison baseline；
- Gate 13R-PR1B v4 的 composite process-identity specification、validation `23/23`、唯一只读 analysis recovery 与独立 recovery root；完整 v3 raw pilot 仍保持 failed/non-formal/excluded；
- Gate 13R-PR2 active v2 config/schedule/schema/provenance、validation v4 `63/63`、S48/H48 正式设计与 non-executing readiness；validation attempts 1–3 与 official v1 artifact set 只作失败历史；
- Gate 13R-PR2-MP1 v2 的 immutable Phase-A raw tree、独立 Phase-B diagnostic analysis、post-pilot integrity audit 与未冻结 policy recommendation；
- PowerShell、JSON、JSONL、冻结基线和算法范围综合审计。

### 5.3 当前恢复点

在开始任何新实现前，以 `Research/Next_Session_Checkpoint.md` 为准。当前安全恢复点是：

> Gate 1–9 继续作为 prerequisite；Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R pilot attempt 4、Gate 13R-PR1、Gate 13R-PR1B v4 recovery、Gate 13R-PR2 active v2 preparation、Gate 13R-PR2-MP1 v2 immutable raw/diagnostic analysis 与 Gate 13R-PR2-MP2 active V4 candidate/readiness 是唯一活动上游。先读 `Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json`、同名 `.md`、active candidate config/adapter/provenance、final validation audit 和 `Research/Next_Session_Checkpoint.md`。pilot v1、formal attempts 1–2、MP2 validation attempts 1–3 和所有更早失败 attempts 仍不可恢复、不可合并或改写状态。MP2 policy 已前瞻冻结，但未获新的正式授权前不得创建 formal attempt-3 root/receipt、启动正式 Unity measured block、运行正式统计分析或 Gate 14R。

---

## 6. 总体执行路线

推荐顺序如下：

```text
已完成基础设施（Gate 1–6）
        |
        v
Gate 7：D* Lite 规格、oracle、实现与验证
        |
        v
Gate 8：C-FF 完整重算流场基线
        |
        v
Gate 9：IDFF 增量流场
        |
        v
Gate 10R：以 Williams-block 进程为单位重建四算法公平合同、遥测与原子 runner
        |
        v
Gate 11R：新场景矩阵、确定性预注册与 53/74/212 Playable 全覆盖
        |
        v
Gate 12R：fresh block-process pilot、相关性/方差上界与 exact-topology 证据
        |
        v
Gate 13R-PR1：shared-primary / heterogeneous-secondary 研究问题与统计预注册、Gate 12R 只读重分析
        |
        v
Gate 13R-PR1B：balanced mirrored order-effect pilot 与失败 raw evidence 的复合身份只读 recovery
        |
        v
Gate 13R-PR2：S48/H48 与 planning-effect 解释已冻结；active v2 非执行 formal preparation 已通过
        |
        v
Gate 13R：单独授权的严格串行、研究问题对齐正式规划微基准 campaign
        |
        +---------- 可选 Gate 14：移动/到达实验
        |
        v
Gate 15R：block-aware 统计分析、图表和结论
        |
        v
Gate 15V-R：使用 Gate 11R scenes 的确定性重放与 OBS 补充视频
        |
        v
Gate 16：论文、复现包和最终交付
```

Gate 7、8、9 可以按用户研究优先级调整，但推荐先做 D* Lite，再以 C-FF 作为 IDFF 的独立参考基线，最后实现 IDFF。

---

## 7. Gate 7 — D* Lite

状态：完成（2026-10-04）  
授权：用户已明确授权

### 7.1 目标

实现 per-agent D* Lite，使动态网格发生改变时复用上一轮搜索状态，而不是像 A*-R 一样完整重算。

### 7.2 必须先冻结的规格

- 顶点、边和 destination-entry cost 与 A*-R 完全一致；
- 四邻域/八邻域与严格 corner policy；
- `g`、`rhs`、priority key 和 `km` 的精确定义；
- 浮点相等/比较策略；
- open queue 的确定性 tie-breaking；
- 每个 agent 的状态所有权与生命周期；
- goal 改变时是重初始化还是独立状态；
- start 移动语义是否在规划微基准中禁用、在移动实验中启用；
- blocked/unblocked 与 cost increase/decrease 的 update 传播；
- grid version 和 stale update 行为；
- budget 中断后状态能否继续使用，或必须标记失效；
- 指标中 processed、expanded、relaxed、repaired 的确切含义。

### 7.3 独立验证要求

- 静态最优代价必须与独立 Dijkstra 一致；
- 每次动态变化后必须与从头 Dijkstra 的最优代价一致；
- 覆盖阻塞、解锁、成本增加、成本降低和多个同 tick 变化；
- 覆盖有路、无路、start=goal、四/八邻域和禁止穿角；
- 固定输入的路径、状态和工作计数必须确定；
- 微小预算必须稳定返回分类结果；
- 错误 grid version、run id 或 lifecycle 必须被拒绝；
- 不允许复用 A* heap 或启发式实现作为所谓独立 oracle。

### 7.4 Gate 7 验收条件

- [x] 用户明确授权；
- [x] `DStar_Lite_Specification.md` 完成；
- [x] 独立 oracle 测试与实现同步完成，且不复用 D* Lite 搜索结构；
- [x] Unity runtime 和 Editor assembly 编译通过；
- [x] 24 个静态与 72 个动态参考案例全部通过；
- [x] 确定性重复、预算中断/续跑和多智能体状态测试通过；
- [x] A*-R 与 Gate 2–6 全回归不变；
- [x] D* Lite 单次批处理和三进程复现/聚合管线通过；
- [x] 冻结基线 24 项、0 不匹配；
- [x] 不修改原始脚本或场景；
- [x] `Gate7_Checkpoint.md` 和下一会话 checkpoint 写入。

---

## 8. Gate 8 — Corrected Full-Recompute Flow Field（C-FF）

状态：完成（2026-10-05）  
授权：用户已明确授权

### 8.1 目标

建立一个语义正确、每次变化完整重算的共享流场基线。它既是独立实验算法，也是 IDFF 的正确性 oracle/消融对照。

### 8.2 核心规格

- 使用与其他算法相同的研究网格和 cell cost；
- 明确多源 goal set 的 integration cost 定义；
- 明确 direction field 的 tie-breaking；
- 明确不可达 cell、goal cell 和 blocked cell 的表示；
- 四/八邻域和 corner policy 与 A*-R 保持一致；
- 动态变化后完整重建 integration/direction field；
- 查询 agent 下一方向的成本与流场重建成本分开记录；
- 禁止复用原始历史 Flow Field 代码作为已修正实现；历史代码只用于审计。

### 8.3 独立验证

- 每个可达 cell 的 integration cost 与反向多源 Dijkstra 一致；
- direction 必须指向合法且使 integration cost 下降的邻居；
- 不允许 diagonal corner cutting 泄漏；
- 动态变化后完整重算结果与全新初始化结果一致；
- 多目标、不可达区域和加权 cell 均有固定测试。

### 8.4 Gate 8 验收条件

- [x] 用户明确授权；
- [x] C-FF 规格与测试设计在生产实现前冻结；
- [x] 独立 O(V²) 反向多源 Dijkstra oracle 完成；
- [x] 24 个初始、72 个动态和 2,880 个生成网格 cell 的全字段对照通过；
- [x] 方向场、目标所有权、destination-entry cost、corner policy 与确定性测试通过；
- [x] 原子完整重算、软 rebuild budget、硬 plan budget 和生命周期测试通过；
- [x] C-FF 单次批处理与三进程复现/聚合管线通过；
- [x] Unity 和 Gate 2–8 全回归通过；
- [x] 冻结基线 24 项、0 不匹配；
- [x] 不修改原始脚本或场景；
- [x] `Gate8_Checkpoint.md` 和下一会话 checkpoint 写入。

---

## 9. Gate 9 — Incremental Dynamic Flow Field（IDFF）

状态：完成（2026-10-05）

### 9.1 目标

实现共享目标集上的增量 integration/direction field 修复，并与 C-FF 的完整重算结果逐事件对照。

### 9.2 必须冻结的规格

- 增量状态的所有权、版本和失效条件；
- changed cell 的 predecessor/successor 传播集合；
- 成本增加、降低、阻塞、解锁的修复算法；
- 多个同 tick 变化是原子批次还是顺序 update；
- direction field 是即时全量刷新还是按 dirty region 刷新；
- repaired cells、queue pops、relaxations 的计数标准；
- repair budget 中断后的状态一致性；
- goal set 改变时是否强制完整初始化。

### 9.3 最关键的 oracle 原则

在每个动态事件之后：

1. 用 IDFF 增量修复；
2. 用 C-FF 从同一个规范网格完整重算；
3. 比较全部 cell 的可达性、integration cost 和合法方向；
4. 允许多条等价最优方向时，按冻结 tie-breaking 比较；
5. 任何差异都阻止 Gate 通过。

### 9.4 Gate 9 验收条件

- [x] 用户明确授权；
- [x] IDFF 规格与测试设计在生产实现前冻结；
- [x] 24 个初始场、96 个动态 fresh-C-FF 场及 3,600 个 cell 全对照通过；
- [x] 确定性、同 tick、goal-set 失效和预算中断/恢复测试通过；
- [x] IDFF 单次批处理与三进程复现/聚合管线通过；
- [x] A*-R、D*L、C-FF 与 Gate 1–8 回归通过；
- [x] 冻结基线 24 项、0 不匹配；
- [x] 不修改原始脚本或场景；
- [x] `Gate9_Checkpoint.md` 和下一会话 checkpoint 写入。

---

## 10. 活动主线 — Gate 10R→13R 研究问题对齐与严格串行 formal readiness

本节是 Gate 10 以后的唯一活动执行路线。Gate 10R 的 one-fresh-process-per-complete-Williams-block 合同继续有效；Gate 11R 的 53 scenarios / 74 campaign profiles / 212 presets / 53 Playable scenes 保持不变；Gate 12R v4、Gate 13R-PR1B v4 recovery 和 MP1 v2 只作为非正式设计/诊断证据。Gate 13R-PR2 active v2 的 S48/H48 schedule 保持冻结，formal attempts 1–2 均已失败并冻结；MP2 已将 MP1 v2 诊断转成 prospective scenario-scale memory contract 和 active V4 attempt-3 candidate。active monitoring/recovery v2 只加入盲化运行状态、acquisition/raw-commit 小时报告与受限软件恢复，不产生 formal observation。最新活动边界由 `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json` 覆盖。

| Gate | 活动状态 | 冻结结果/下一边界 |
|---|---|---|
| Gate 10R | attempt 4 已通过 | 每个完整 Williams block 一个 fresh Unity；reset/telemetry/lock/structural/retained/final audit 全通过 |
| Gate 11R | attempt 2 已通过 | 完整 74-campaign 矩阵、确定性身份、排除规则、Williams mappings 与 Playable bundle 不变 |
| Gate 12R | pilot attempt 4 已通过 | 384 measured blocks / 1,152 samples；`NON-FORMAL / PILOT-INFORMED / EXCLUDED-FROM-FORMAL-ANALYSIS` |
| Gate 13R-PR1 | 已通过 | shared P1 C1–C5 primary；heterogeneous secondary；P2–P5 supportive；M1–M5 prospective；66/66 final audit |
| Gate 13R-PR1B | v4 recovery 已完成 | v3 raw pilot 仍 failed/excluded；96 balanced mirrored pairs；composite identity 通过；order effect pilot-level identifiable / some cells inconclusive；推荐 H48 |
| Gate 13R-PR2 | 已完成并通过 | S48/H48 已冻结；active v2 config/schedule/schema/provenance；validation v4 63/63；不再运行 supplemental pilot |
| Gate 13R-PR2 formal attempts 1–2 | 失败并冻结 | attempt 2 在 ordinal 934 fail closed；partial observations 永久 excluded/no-resume/no-merge |
| Gate 13R-PR2-MP1 v2 | 已完成 | 34/34 pre-pilot；96/96 blocks；384/384 samples；Phase-A raw immutable；Phase-B diagnostic analysis passed |
| Gate 13R-PR2-MP2 | 已完成；attempt 4 通过 | policy frozen；V4 candidate config/adapter/provenance；69/69 static、22/22+8/8 Unity fixtures、PSAPI/CIM、positive + 3 negative blocks、post-audit 全通过 |
| Gate 13R-PR2 attempt-3 monitoring/recovery | active v2；attempt 3 通过 | 56/56；5-minute silent watcher、acquisition+raw-commit 60-minute report；prelaunch bounded repair / acquisition diagnostics-only / post-acquisition non-Unity commit recovery |
| Gate 13R formal campaign attempt 3 | 未授权 | 必须使用新版 versioned prompt 另行授权后才能建立和启动；正式分析仍不随 launch 自动授权 |

研究合同：shared-goal 四算法位于同一完整 Williams block，block 是独立 cluster。P1 五 contrasts 是唯一 confirmatory family，FWER alpha 0.05，Holm；C1–C4 方向性，C5 双侧。P2–P5 为 supportive，不与 P1 做“赢项投票”。correctness/oracle/structural/hash/reset/provenance 是性能结论前的硬门禁。heterogeneous C1–C4 比较 grouped-field 与 per-agent system/treatment，不能归因为算法名称的单一因果效应。

Gate 12R v4 的 P1–P4 均为 1,152/1,152 finite positive；P5 计数派生 1,152/1,152 有效但全部零 overrun，故不能用 pseudocount 制造 rate superiority 或 n；P3 scaling slope 因缺少同一受控 family 的足够 agent-count levels 而不可由该 pilot 估计。其 heterogeneous 96 pairs 全部 same-wave，但 order 为 89:7，仅可用于 descriptive variance。PR1B 则以前瞻性 balanced mirrored AB/BA 设计补足 pilot-level order-effect 诊断：P1 的 16 个 scenario/pooled cells 中 9 bounded、2 detectable-but-below-bound、5 inconclusive、0 material；结论不能外推为 pure-algorithm causal effect 或 formal superiority。

候选 S/H 比较保留完整 74-campaign 矩阵。用户已在 PR2 选择并冻结 `S48/H48`：shared 32×48=1,536 processes / 6,144 samples；heterogeneous 21×48=1,008 matched superblocks、2,016 processes / 4,032 samples；合计 3,552 processes / 10,176 samples，p50 `20.80818545 h`、conservative summed-p95 `26.45538207 h`，projected p95 raw storage `9,631,912,320` bytes，1.5× safety storage `14,447,868,480` bytes，另加 40 GiB reserve 后最低空闲量 `57,397,541,440` bytes。

该冻结仍不等于 launch authorization。使用 conservative sigma upper 时，10% assumed true effect 下没有 S32–S48 候选能让五 contrasts 全部达到 80% Holm-worst-threshold power；S48 在 15% assumed effect 下的限制项 C2 约为 81%。15% 只作为 planning effect anchor，不是 practical-superiority threshold。balanced pilot 已满足 order-effect 设计诊断目的，不再运行 supplemental pilot；正式执行仍须单独授权并重新通过全部 fresh prelaunch 门禁。

MP2 前瞻性 memory eligibility 已冻结：completed-sample cleanup 与 post-block 以相对 block baseline 的 `max(working-set delta, private-memory delta)` 为 native metric；`<=128` tier 为 512/640 MiB，`==256` tier 为 640/768 MiB，精确等于阈值通过，超过才触发；raw-after-workload 只作 transient diagnostic，host emergency 除外。native hard crossing 是 whole-block/process eligibility event，必须先持久化并禁止下一个 block，不能归因于 final-position algorithm。managed 128 MiB 是 alert，256 MiB sample/block 是 emergency hard failure；host 4 GiB absolute、2 GiB relative growth、8 GiB available floor 与 telemetry unverifiable/overflow 均 fail closed。monitoring amendment 不改变这些门禁，只盲化呈现 operational memory/host telemetry。该 policy 与监控合同均已冻结，但用户仍未授权 measured launch。

### 10.1 Attempt 3 监控与恢复合同

- heartbeat 每 5 分钟运行一次；未开始或无需通知时保持静默；内部按 60 分钟 slot 最多生成一条计划进度报告，不补发错过的多个小时；
- 开始、失败、raw commit 完成、action-required 和新 stall escalation 可不受小时槽限制即时报告；
- 报告只含 process/sample 计数、当前身份、elapsed/operational ETA、OS memory、存储和健康码；禁止 P1–P5、M1–M5、算法 timing、contrast、effect、CI、p 值、ranking 或 superiority；
- status/receipt/OS query 最多按 `0/2/5` 秒读三次；这只是读取重试，绝不等于实验重跑；
- prelaunch versioned repair 上限 3 次，同一失败签名连续出现 2 次即停；frozen hash、research contract、scientific identifiability、formal path pre-existence 或需要放宽门禁时必须交给用户；
- 从首个 measured process 到 acquisition 完成，自动动作只限只读诊断、证据留存和通知；任何 hard failure 都不得启动下一 block；
- 完成 3,552/10,176 后，只有 raw tree 连续两次身份稳定、Unity/lock 为零且无 measured mutation，才可最多 3 次 non-Unity commit recovery；成功只可到 `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`；
- heartbeat 自身不具备 formal launch 或 repair 权限；实际 prelaunch/post-acquisition repair 只能由未来单独授权并绑定该状态机的 execution orchestrator 执行。

旧 `Gate13R_Serial_10pct_* v2` 的 144/204/108、11,160 processes、31,536 samples、p95 83.90 h 仅为 pre-amendment comparison baseline，状态为 `NOT-AUTHORIZED-FOR-LAUNCH`。旧 5%、parallel、cold 与失败尝试继续位于历史证据区，不恢复、不合并、不作为活动 config。

## 历史附录 H — 已替代的旧 Gate 10–13（不属于当前主要内容）

旧 cold-process/迁移谱系的凝练记录已单独移至 `Research/Historical_Gate10_to_Gate13_Archive.md`。以下 H.1–H.4 只保留原计划文本供审计，不得作为活动执行合同、样本量依据或正式分析输入。

### H.1 旧 Gate 10 — 四算法公平性与统一批处理

状态：完成（2026-10-05）  
授权：用户已明确授权

#### H.1.1 目标

让所有算法通过同一批处理入口、同一场景、同一预算和同一输出 schema 运行，并消除比较口径差异。

#### H.1.2 必须解决的公平性问题

##### 共享目标与异构目标

流场天然适合共享目标集，而 A*-R/D*L 通常按 agent 规划。正式实验至少拆分为两个 cohort：

- Shared-goal cohort：所有 agent 共享一个目标或明确的多源目标集；四算法可直接比较；
- Heterogeneous-goal cohort：每个 agent 的目标不同；必须明确是一目标一流场、目标分组流场，还是只比较 per-agent 方法。

禁止在未记录 field 数量的情况下，用一个共享流场与数百个不同目标的 per-agent planner 直接比较。

##### 动态处理成本

- A*-R：change acknowledgement + 事件后所有 agent 的完整重规划；
- D*L：所有受影响 per-agent 状态的 repair + 必要 query；
- C-FF：完整 integration/direction 重算 + query；
- IDFF：增量 repair + dirty direction 更新 + query。

只报告 acknowledgement 或单一内部步骤均视为无效比较。

##### 工作量指标

- 同时保留算法原生工作量指标；
- 提供共同的 processed nodes/cells；
- 不把含义不同的 expanded/repaired 数字直接合并成同一指标；
- 原始总量和 per-agent/per-event 归一化结果同时保留。

#### H.1.3 批处理升级

- 将算法白名单从仅 `A*-R` 扩展到已经通过 Gate 的算法；
- 每个算法独立 Unity 进程；
- manifest 记录算法版本/规格版本；
- campaign 层随机化或平衡算法执行顺序，降低温度和主机漂移偏差；
- 不允许同一进程连续承载多个算法样本。

#### H.1.4 验收条件

- [x] 四算法均已通过自身正确性 Gate；
- [x] 同一规范场景在所有算法中具有相同 fingerprint；
- [x] 每个算法的动态成本边界有文档和自动验证；
- [x] 批处理只接受四个已通过 Gate 的算法；
- [x] 混合 fairness/specification/implementation/workload/cohort/state 身份不能进入同一 aggregate；
- [x] Williams 四块平衡调度、16 个独立 Unity 子进程和 create-new 保护通过；
- [x] Gate 6–9 旧聚合由当前代码字节级重建；
- [x] Gate 1–9 全回归与冻结基线审计通过。

冻结规格：`Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md`。完整证据与边界见 `Research/Gate10_Checkpoint.md`。保留 campaign 明确标记为 `formalCampaign = false`，不得当作正式实验。

---

### H.2 旧 Gate 11 — 正式场景矩阵与实验预注册

状态：完成（2026-10-05）  
授权：用户已明确授权

#### H.2.1 冻结矩阵

- 32 个 balanced-core 文件：八个结构行 × 两个 seed × shared/heterogeneous 两种 goal 结构；
- grid-scale 4 个、agent-scale 5 个、dynamic-footprint 5 个、goal-count 5 个、reachability 2 个；
- 53 个唯一 canonical scenario；
- 32 个 shared 与 21 个 heterogeneous 文件；
- 128 个 shared、42 个 per-agent heterogeneous、42 个 grouped-field heterogeneous eligibility cell，共 212 个；
- 全部 cell、agent、goal 和 event 均显式 materialize，不存在运行时随机输入。

冻结文档中的 `33/20` 汇总行与详细矩阵算术冲突；`Research/Gate11_Frozen_Count_Erratum.md` 将详细矩阵确认为权威，原冻结文档和 retained bundle 均未原地改写。

#### H.2.2 冻结生成和身份

- 规格：`Research/Formal_Scenario_Matrix_and_Preregistration_Specification.md`；
- 生成器：`ddm-formal-scenario-generator-v1`，integer-only SplitMix64；
- bundle：`Research/FormalScenarios/v1/`；
- manifest SHA-256：`ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e`；
- ordered aggregate SHA-256：`91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88`；
- bundle 一律 create-new；后续修正必须新建 version，不覆盖 v1。

#### H.2.3 冻结预注册

- primary endpoint：`dynamicHandlingMillisecondsPerScheduledEvent`；
- `P1`–`P4` 属于 `primary-four` Holm family；
- `S1`–`S2` 属于独立的 `scaling-two` Holm family；
- `S3`–`S5` 仅作描述性分析；
- timing 使用 natural log，报告指数化 ratio 与双侧 95% CI；
- timing/allocation outlier 保留，算法失败保留在分母中；
- technical invalidity 才允许 replacement，且必须用下一 ordinal 重跑完整 Williams cycle；
- Gate 12 依据 `sigma_log` 和当时冻结的 5% precision target 生成 required n；该历史结果保持不可变。Gate 13 使用后续 versioned amendment v1 的 10% 目标，且继续禁止 significance/trend early stopping。

#### H.2.4 验收结果

- [x] 53/53 scenario strict-load、byte-canonical、低于 16 MiB并可字节级重生成；
- [x] 212/212 planner×scenario eligibility 与 Gate 10 cohort 一致；
- [x] 四个 planner 在每个场景的新 grid 上初始化并 reset，不运行 workload；
- [x] 265 个独立 BFS phase state 符合可达性合同；
- [x] matrix、catalog、preregistration、artifact 和 aggregate hash 全部验证；
- [x] 11 类 tamper/negative case 被拒绝；
- [x] Gate 2–10 全回归和 24 项冻结基线通过；
- [x] `pilotExecuted = false`、`formalCampaignExecuted = false`。

完整证据与恢复边界见 `Research/Gate11_Checkpoint.md`。

---

### H.3 旧 Gate 12 — Pilot 与正式样本量冻结

状态：已完成获授权的隔离非正式 pilot 和最终审计；其原 5%/cap-100 阻断已通过独立的 Gate 13-readiness amendment v1 处理

#### H.3.1 Pilot 目标

- 估计每个主要 metric 的噪声；
- 识别 Unity/JIT/GC/温度对 timing 和 allocation 的影响；
- 估计完整 campaign 总运行时间和磁盘量；
- 检查 budget 是否过松或过紧；
- 检查不同算法是否出现系统性失败；
- 决定正式重复次数，而不是沿用 Gate 6 的 3 次。

#### H.3.2 冻结规则

- pilot 重复设计必须在 Gate 12 实现前另行冻结，且输出与 Gate 13 完全隔离；
- 对每个 comparison family 估计 primary log endpoint 的最坏 `sigma_log`；
- `n_raw = ceil((1.96 × sigma_log / ln(1.05))²)`；
- `n_formal` 是不小于 `max(30, n_raw)` 的下一个 4 的倍数，上限 100；
- family 内每个 cell 使用同一个 `n_formal`；若需求超过 100，Gate 13 必须等待 versioned amendment；
- 不允许在看到有利 p 值或趋势后提前停止；
- 如果 timing 分布明显偏斜，同时报告 median/p95 和适当的稳健/重采样区间；
- 当前 t 区间继续保留，但不能自动解释为正态性证明。

以上 5%/cap-100 条款描述 Gate 12 当时实际执行的冻结规则，未被就地改写。Gate 13 的正式样本计划由 amendment v1 另行版本化为 10%/cap-148，并保留全部其他分析和停止规则。

#### H.3.3 环境控制

- 记录 CPU、RAM、OS、Unity 版本；
- 固定电源模式；
- 关闭交互 Unity、浏览器重负载和后台构建；
- 记录运行开始/结束时间；
- 平衡或随机化算法顺序；
- 避免把第一次冷启动只分配给单一算法；
- 每个样本仍使用独立 Unity 进程。

#### H.3.4 验收条件

- [x] pilot 结果与正式结果目录隔离；
- [x] 噪声和运行成本报告完成；
- [x] 候选重复次数、required 次数和停止规则按冻结公式生成；
- [x] 正式 campaign 配置已在非执行 preparation 中冻结；cap-148 runner/config 和 launch guard 已通过但不授予执行权；
- [x] pilot 未被选择性并入正式结果。

当前执行注记：旧的第二次尝试已按授权完整归档到 `Research/PilotRuns/Gate12/v1-failed-warmup-attempt2/`，前后 103 文件、14,187,382 bytes 与 aggregate `b52ee8f...c500` 一致。新的 `Research/PilotRuns/Gate12/v1/` 是成功的非正式 pilot：16 个 warm-up 已排除，256 个 measured 样本完整，Gate 12 最终审计 24/24 通过。其历史 5% 结果仍保留为不可变证据；后续只通过 `Research/Gate13_Readiness_Amendment.v1.json` 的版本化 10%/cap-148 修订解释，不改写 Gate 12 文件。

#### H.3.5 Gate 13-readiness amendment v1

状态：历史 amendment 的规格、测试设计和非执行静态审计已完成；其 byte identity 保持不变。后续非执行 implementation 已通过新的 preparation manifest 记录，formal execution 仍未授权。

- precision target：10% relative 95% CI half-width；
- Gate 11 matrix：53 scenarios / 212 eligibility cells，byte-identical；
- cap：148；
- required n：P1/P2/P3/P4 = 52/148/48/52；
- scheduled n：52/148/52/52；P3 上调到 52 以保持 shared 四算法完整 Williams cycle；
- 74 campaigns / 15,056 independent Unity processes；
- p95 wall/output：67.6672 h / 49.3065 GiB；
- minimum launch free space：74,417,330,489 bytes，保证输出后仍有 20 GiB；
- 当前 H: 只读快照约 151.0567 GiB free，当前通过但不代替未来 launch preflight；
- Codex 用量策略：无项目自定义 ceiling、固定余量、周预算或百分比停工线；平台实际限制仍适用；
- Gate 13 formal timing：0 samples，未启动。

详细证据见 `Research/Gate13_Readiness_Amendment_Checkpoint.md`。

#### H.3.6 Gate 13 nonexecuting preparation v1

状态：完成；本小节记录 preparation 完成时“正式执行未授权、未开始”的历史边界，后续 attempt 1 状态见 Gate 13。

- deterministic config SHA-256：`b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874`；
- 独立 Gate 13 runner 支持 cap 148；Gate 10 runner 保持 byte-identical、最大 100；
- 74 campaigns / 15,056 run IDs 全部确定性展开且唯一；
- raw-byte boundary：`74,417,330,488` 失败，`74,417,330,489` 通过；
- execution receipt 必须绑定 config/amendment/output root，缺失或篡改均在 root 创建前失败；
- checkpoint 原子写入、30 s 监控、3 次无增长 advisory、10,800 s hard timeout、禁止自动 retry/resume；
- 60/60 Gate 13 单元、63/63 Gate 12 回归、16/16 集成 validation 与 23/23 final audit 通过；
- final audit summary SHA-256：`3738b958a323e7050f1641f93abd0756e712aca46f18c4d8b451f2274446c3d8`；
- preparation final audit 当时的 formal root、execution receipt、Unity process、Unity lockfile：均不存在；后续 attempt-1 receipt 已作为独立执行证据保留。

详细证据见 `Research/Gate13_NonExecuting_Preparation_Checkpoint.md`。

---

### H.4 旧 Gate 13 — 正式规划微基准 Campaign

状态：cold-process attempt 1 保留为 root 前失败；attempt 2 已因用户授权的设计变更受控终止并永久排除；process-reuse 非正式 pilot v1 验收失败并封存；Gate 13 尚未完成，当前没有正式执行授权

#### H.4.1 执行原则

- `gate13-readiness-amendment-v1` 的 10%/cap-148/15,056-process 合同及 74,417,330,489-byte storage gate 只保留为已终止 cold-process 设计的历史合同；
- process-reuse 继续保留 10% 精度目标与 cap 148 上限政策，但必须由成功 fresh pilot 重新估计 block-level 方差、同进程相关性、候选 `n_formal`、block/process 数、wall/storage projection 与新的 raw-byte launch gate；当前不存在通过验收的 process-reuse formal config；
- 任何未来正式输出根只能在新的 versioned amendment/config、readiness audit、单独 execution receipt 和启动时 raw-byte/environment preflight 全部通过后创建；
- 只使用冻结的 scenario catalog 和 campaign 配置；
- 每个 scenario × algorithm × repetition 都有唯一 run id；
- 每次运行立即校验 hash 和 completion；
- 不覆盖失败输出；
- 出现系统性错误时暂停整个 campaign，不继续积累无效数据；
- 每个 comparison group 只能包含同一算法和同一场景指纹；
- 运行期间定期检查磁盘、Unity 残留进程和 lockfile。

#### H.4.2 主指标

- `T_init`；
- plan latency 和 p95；
- dynamic handling latency 和 p95；
- total planner elapsed；
- processed nodes/cells；
- expanded nodes、relaxed edges、repaired cells；
- managed allocated bytes；
- success rate；
- budget-overrun rate；
- categorized failures；
- path cost/efficiency（在可比较算法输出完整路径时）。

#### H.4.3 Campaign 验收条件

- [x] cap-148 research-only orchestration/config 与 launch preflight 已在非执行阶段通过；
- [x] 用户已取消全部项目自定义 Codex 用量上限；该策略不包含额外 reset/credit 购买授权；
- [x] 用户已接受 wall-clock 时间安排并授权 attempt 1；attempt-1 receipt 已通过 validator；
- [x] 用户已在审阅 attempt-1 失败检查点后单独授权 attempt 2；receipt v2 和全部启动门槛通过；
- [ ] 所有计划 group 均有 completed manifest；
- [ ] 所有 artifact hash 匹配；
- [ ] JSONL sequence 连续；
- [ ] 缺失/失败样本按预注册规则处理；
- [ ] 没有 scene/source 变化；
- [ ] 原始结果只读归档；
- [ ] 汇总结果可从原始结果重新生成。

#### H.4.4 Formal launch attempt 1（2026-10-06）

- receipt：`Research/Gate13_Execution_Authorization.v1.json`，SHA-256 `864740f428c8a0c40c9883c9b9a77988968e68610cf19d48d61529959ec95cc8`；
- validation-only preflight：通过，H: raw free bytes `162,195,136,512`，门槛余量 `87,777,806,023`；
- formal runner：调用一次，在 `Test-Gate13FormalConfig` 的 deterministic reconstruction 阶段失败；
- 根因：PowerShell 7 父进程的模块目录被 hidden `powershell.exe` 原样继承，Windows PowerShell 5.1 优先发现不兼容的 `Microsoft.PowerShell.Utility` v7，导致 `Get-FileHash` autoload 失败；
- 非执行诊断已证明：只为启动子进程恢复 Windows PowerShell 5.1 原生 `PSModulePath` 后，hidden child 可解析原生 `Get-FileHash` v3.1；
- 终态：无 formal root、无 formal checkpoint、无 Unity、0 campaign、0 sample、未自动 retry；
- attempt-1 receipt、stdout/stderr、诊断和 `Research/Gate13_Formal_Launch_Attempt1_Checkpoint.md` 必须保留不动；
- 该失败因此要求 attempt 2 使用新的 versioned receipt/launch-log identity，并在单独授权后重新跑全部启动门槛；attempt 2 已按此要求执行。

#### H.4.5 Formal launch attempt 2（2026-10-06，已受控终止并排除）

- receipt：`Research/Gate13_Execution_Authorization.v2.json`，SHA-256 `5f3898914c29a3413f70d1ee1c5b7afbe84c05ac7987677f6083227dd93417a8`；
- launch-only 环境：只在创建子进程时使用 Windows PowerShell 5.1 原生 `PSModulePath`，父环境随后恢复；冻结 runner 未修改；
- independent validation-only：通过，H: raw free bytes `162,195,087,360`；
- runner-owned launch preflight：通过，H: raw free bytes `162,195,083,264`，门槛余量 `87,777,752,775`，且检查时 AC/高性能/内存/CPU/no-Unity/no-lock/no-root 全部满足；
- 顺序性：runner 先通过 receipt、hash、环境和 storage 检查，再创建 `Research/FormalRuns/Gate13/v1`；
- 落盘绑定：`frozen-config.json` 与 receipt copy 的 SHA-256 分别精确匹配 config 与 receipt v2；
- 用户随后明确授权 cold-process → process-reuse 设计迁移，并要求先终止 attempt 2；终止前边界为 campaign 1、Williams block 37、position 4、`C-FF`、run ID `g13-c001-core-r01-s1-shared-s4-b037-p04-cff`；
- 只终止 attempt-2 自有进程树，orchestrator 通过 fail-closed 路径退出；终态 checkpoint 为 `failed-no-auto-retry`，剩余 owned process 数为 0；
- 独立清点得到 147 个已完成 cold-process 样本；formal root 共 891 文件、129,667,391 raw bytes、891/891 只读；
- termination receipt SHA-256：`4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4`；partial-output manifest SHA-256：`f3ea8fa2f39bfbbb89380efb0389fc1c1f7d0cdf3849cc0ae45da75c2e960c82`；
- 该 cold root 永久标记为 `USER-TERMINATED-DESIGN-CHANGE / EXCLUDED_FROM_ANALYSIS / NO-AUTO-RETRY / NO-RESUME / SUPERSEDED-BY-PROCESS-REUSE-DESIGN`；不得补齐、合并、正式推断、正式样本量估计或供 Gate 14 使用；
- `Research/Gate13_Formal_Launch_Attempt2_Checkpoint.md` 只保留为终止前历史快照；当前恢复点改为 `Research/Gate13_ProcessReuse_Pilot_Failure_Checkpoint.md`。

#### H.4.6 Gate 13-R2 process-reuse 设计与预 pilot 审计

- 设计标识：`one-fresh-unity-process-per-williams-block-v1`；每个 Williams block 启动一个全新 Unity Editor，进程内按冻结顺序执行 2 或 4 个算法，每个算法最多一次；
- 禁止 campaign 级长期存活进程；样本保持独立 run ID、目录、summary、manifest、hash 和 completion marker；任一样本失败即停止该 block，禁止自动 retry/resume；
- Gate 11 场景矩阵、种子、canonical identity、排除规则、cohort 和 Williams 顺序保持不变；10% precision/cap-148 只保留为上层政策，不沿用 cold-process pilot 方差或 `n_formal`；
- specification、test design、pilot plan、provenance v4 SHA-256 分别为 `06b8f79aff15301acb45a478ac054e0a444be3581fe4cb05f4c5a106dc6e256d`、`45aed83d000ef8db41a5d910394422ba576ffe96a3543ac67415aa147bc1fefb`、`de79edaca2bfd7016fd9a50dba85a511c2bdfc6bdce99d629e20e4bded4ca8d9`、`91a8fcabdd157f7511eeda89e8355580954ed03222c51b5163f577b10354b82d`；
- final pre-pilot audit：147 项当前断言通过并绑定 retained 63/63 回归；两个正向 block 分别证明 4/4、2/2 样本同 block 同 PID且 block 间不同 PID；负向 fixture 证明 position 2 fail closed、无后续样本、无 retry/resume；
- pre-pilot audit SHA-256：`4be30a094cfc116a28f0b2f845dd0c73fdf221ab05d6bd4d756e601771b168c8`。

#### H.4.7 Gate 13-R2 非正式 pilot v1（失败并封存）

- 独立根：`Research/PilotRuns/Gate13_ProcessReuse/v1/`；明确 `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`；
- 执行完整：1 个 warmup block / 4 samples、8 个 fresh-cold reference processes / 8 samples、36 个 measured block processes / 96 samples，共 45 个 Unity 进程 / 108 samples；
- structural exact-match：0 mismatch；
- 分析验收失败：96 个 measured 样本的 working-set telemetry 均为 0、96 个 private-memory telemetry 均为 0，另有 16/36 block 超过冻结的 128 MiB managed-memory-growth 上限，共 208 hard errors；
- 终态：`failed-no-auto-retry`；candidate sample-size/budget 文件只作为失败诊断副产物，明确 `CANDIDATE-N-NOT-ADMISSIBLE`，不得生成 post-pilot amendment/config；
- root 已封存：838 文件、91,219,643 raw bytes、838/838 只读，aggregate `c467cd4ca179f6e919fe9cbfdeee3cd2b4a32c19931bcdc285ca705555a59b38`；
- failure receipt / output manifest SHA-256：`11f2331d55bb163a1254e7c2e1263f9cbc7c2e162f8bb5db20be5814d898c304` / `eb55ae56d047b44e4a6a7d0713b09437f4435162c19037e37aa5306ebf34c65d`；
- 保留的 process-reuse 正式根 `Research/FormalRuns/Gate13_ProcessReuse/v1` 不存在；未生成正式 receipt，未启动正式 timing campaign；
- 后续必须先获得单独授权，建立新版本 telemetry/readiness 修订和全新 pilot root。v1 不得 retry、resume、覆盖或继续分析；只有未来另行授权且审计通过的 process-reuse formal root 才能供 Gate 13/Gate 14 正式引用。

---

## 14. Gate 14 — 可选移动、到达和帧时间实验

状态：可选，必须单独授权

### 14.1 只有满足以下条件才开始

- 四算法规划正确性已完成；
- 正式规划微基准已完成；
- 用户确实需要 arrival、frame 或 crowd-level 结论；
- 建立新的研究专用 scene，不修改原 scene；
- movement 和 local avoidance 规则对所有算法一致。

### 14.2 需要新增的固定合同

- agent 速度、加速度、旋转和 stopping distance；
- path/flow direction 的采样频率；
- 到达半径和 arrival 判定；
- agent-agent 与 agent-obstacle 碰撞策略；
- deadlock/stuck/timeout 分类；
- frame sampling 和 warm-up；
- dynamic event 与移动 tick 的严格顺序；
- 视觉反馈和摄像机是否计入测量。

### 14.3 指标

- M1 `timeTo95PercentArrival / arrivalTimeP95`：lower is better；失败、timeout 与少于 95% 到达必须按预注册 censoring/completion-curve 规则保留；
- M2 `pathEfficiencyRatio`：实际轨迹/独立时间对齐可行 reference；当 reference 是真下界时越接近 1 越好；明显小于 1 先视为 validation 问题；
- M3 `completionRateByDeadline`：higher is better；timeout/deadlock/stuck/失败留在固定分母；
- M4 `frameTimeP95Milliseconds`：lower is better；冻结 warm-up、采样窗口、render/camera；OBS runs 不进入 timing；
- M5 `categorizedMovementFailureRate`：lower is better；预注册 collision/deadlock/stuck/timeout/oscillation/invalid-direction/unreachable/planner/local-avoidance 分类；
- M3 与 M5 高度相关，不作为两个独立“胜票”；planning/movement/rendering 成本边界、memory/GC 作为解释性诊断。

M1–M5 在 Gate 12R 未观测，状态固定为 `PROSPECTIVE-GATE14R / VARIANCE-NOT-ESTIMABLE-FROM-GATE12R`；Gate 14R 必须先建立独立 movement contract 与 NON-FORMAL pilot，不能复用 Gate 12R planning variance。

### 14.4 验收条件

- [ ] 新场景与原始场景隔离；
- [ ] 固定 tick 重放确定；
- [ ] 所有算法使用同样 movement 层；
- [ ] 规划结果与移动结果分开记录；
- [ ] 不把渲染噪声错误归因于算法。

---

## 15. Gate 15 — 统计分析与图表

状态：依赖正式数据

### 15.1 数据处理原则

- 原始 JSONL、manifest 和 workload result 保持只读；
- 派生表格由脚本生成，不手工改数；
- 每张图可以追溯到输入 group manifest；
- 同时报告绝对量和相对基线效应；
- 失败率和性能指标不能只报告成功样本；
- 不用单一均值掩盖长尾和 budget failure。

### 15.2 建议分析

- 每个算法/场景的 n、mean、median、p95、SD、SE、95% CI；
- P1 shared-goal C1–C5 的 block-paired natural-log ratios、back-transformed ratios、Holm adjusted inference 与 compatible simultaneous CI；
- C1/C2 同时决定 C-FF 对两个基线的结论，C3/C4 同时决定 IDFF；C5 双侧单独报告；
- P2–P5 supportive effect sizes，不进行跨指标多数表决；P5 采用 counts/rates 与 cluster-compatible 方法；
- heterogeneous cross-family 按 matched superblock 分析并明确 system/treatment 边界、AB/BA order 与 factor interaction；
- agent count、grid size、dynamic footprint 的扩展曲线；
- P3 scaling slope 只能使用冻结的同一 controlled factor family；
- path efficiency 与计算成本的 trade-off；
- 必要时使用 log scale；
- 明确区分探索性分析与预注册主分析。

### 15.3 最低图表集合

- 初始化成本 vs grid size；
- 动态处理 p95 vs changed-cell count；
- total planning cost vs agent count；
- processed nodes/cells vs change footprint；
- managed allocation vs algorithm；
- success/budget overrun；
- C-FF vs IDFF 修复收益；
- A*-R vs D*L per-agent 增量收益。

### 15.4 验收条件

- [ ] 分析脚本可重复运行；
- [ ] 图表数据与原始 manifest 可追溯；
- [ ] 单位、样本量和 CI 在图表中明确；
- [ ] 没有选择性删除不利结果；
- [ ] 统计结论不超出实验范围。

---

## 15-V. Gate 15-V — 可 Play 可视化、确定性重放与 OBS 补充视频

> 新谱系修订：Gate 11R 必须提前生成并验证所有实验条件的 Playable Scene/profile/preset；Gate 15V-R 不再临时创建代表场景，而是对 Gate 11R 全覆盖资产生成 formal-linked replay traces、执行 Play smoke，并完成 OBS 录制与 manifests。以下旧设计中与视觉样式、watermark 和 timing 隔离有关的规则继续有效。

状态：设计决策已冻结；实现、Play 验证和录制均未授权  
设计标识：`gate15v-playable-visualization-v1`  
顺序：Gate 13 完成并审计、Gate 15 统计摘要冻结后实施；若 Gate 14 获授权并完成，则同时纳入移动重放，否则只交付规划重放

### 15-V.1 目标与证据边界

- 提供可在 Unity Editor 中直接打开并 Play 的研究专用演示场景，供 OBS 录制论文补充视频；
- 解释四算法的搜索、路径、flow direction、动态事件与修复过程，不生成新的正式性能样本；
- 规划可视化使用冻结 formal scenario 与确定性可视化 trace 重建语义状态；现有 Gate 13 聚合日志不含完整路径/全场快照时，不宣称视频是正式 timing 进程的逐帧回放；
- HUD 中展示的正式指标只能来自 Gate 15 已冻结派生表，并带来源 manifest/hash；现场 Play 得到的帧率、耗时和 OBS 数据不得回写 Gate 13/14；
- 可视化输出根、视频输出根和 formal/pilot 输出根物理分离，禁止任何 capture 过程写入冻结实验目录。

### 15-V.2 计划交付物

- 规划重放 scene：`Assets/Scenes/ResearchVisualization/Gate13_PlanningReplay.unity`；
- 条件式移动重放 scene：`Assets/Scenes/ResearchVisualization/Gate14_MovementReplay.unity`；
- 共享可视化代码：`Assets/_Scripts/Research/Visualization/`；
- 版本化 trace、schema、选择清单与 manifest：`Research/VisualizationTraces/v1/`；
- OBS profile 记录、镜头脚本、录制清单、字幕/图例和视频 SHA-256 manifest；
- Play-mode smoke、确定性重放、语义对照、性能保护和基线保护测试；
- 不要求修改 Build Settings；场景应可从 Project 窗口直接打开并 Play。

### 15-V.3 默认可视化箭头设计（冻结）

设计标识：`research-visual-direction-glyph-v1`

- 透明背景、统一线宽、居中 pivot，固定支持 N、NE、E、SE、S、SW、W、NW 八个方向；
- 箭头名义尺寸为 cell 边长的 60%，实现允许在 55%–65% 内为边缘留白，不跨出所属 cell；
- 默认方向箭头采用高对比度前景；方向、goal、blocked、unreachable 和 repair 不得只靠颜色区分，必须同时使用轮廓、图案、形状、明度或动画之一；
- blocked cell 使用深色实心或斜线填充，不用会与方向/失败符号混淆的大型 `X`；
- goal cell 使用环形目标标记或小旗；无合法方向的 goal cell 不绘制伪方向箭头；
- unreachable cell 使用去饱和灰色状态；不存在有效 successor 的 cell 不绘制任意默认方向；
- heterogeneous-goal 以稳定的 owner/goal-group 映射着色，并在图例中显示；相同 canonical identity 在不同播放中必须得到相同映射；
- 动态事件影响或正在 repair 的 cell 使用短暂黄/橙强调，结束后恢复其稳定语义样式；
- C-FF 与 IDFF 对同一 direction/state 使用完全相同的 glyph 和图例；A*-R/D*L 只在真实路径或搜索证据覆盖的 cell 上绘制方向，不把单路径伪装为全局 flow field；
- `Assets/Resources/Sprites/FFIcon.png`、`GridDebug.cs` 和原始 scene 只作为历史语义参考，保持不变；新实现不得覆盖这些资产；
- 大网格必须采用 GPU instancing、batched mesh 或 dynamic texture 等批处理方案，禁止为每个 cell 创建独立 `GameObject + SpriteRenderer`。

### 15-V.4 确定性选择、播放与 OBS 规则

- 在生成视频前冻结 representative scenario selection manifest，至少覆盖 shared-goal、per-agent heterogeneous-goal、grouped-field heterogeneous-goal，以及静态与动态事件；
- 选择规则基于预注册 family、canonical identity 和固定 seed/排序，不基于哪个结果“最好看”；
- 同一 trace、版本和播放配置必须产生相同的 tick/event 顺序、cell 状态和 camera cue；视觉帧的像素级一致性只在相同 Unity/渲染/硬件配置下要求；
- 播放器至少支持 Play/Pause、单 tick/单事件步进、固定倍速、重置、算法/图层切换、图例与 HUD 开关；
- planning scene 展示固定起点规划、动态事件和 flow/path repair；movement scene 只有在 Gate 14 存在冻结 movement 合同时才展示 agent 运动；
- OBS 只录制可视化模式。录制分辨率、帧率、编码器、Unity 版本、显示器缩放和 capture source 必须记录在视频 manifest；
- 视频剪辑只允许片头片尾、章节、字幕和无损语义删节；不得改变事件顺序、速度标注或指标内容，所有加速片段必须显示倍率。

### 15-V.5 验收条件

- [ ] Gate 13 最终审计完成；Gate 15 用于 HUD 的结果表及其 provenance 已冻结；
- [ ] 若包含 movement replay，Gate 14 已单独授权、完成并冻结 movement 合同；若 Gate 14 未执行，movement scene 明确标记为不交付而非失败；
- [ ] 两类可视化 scene（按适用性）与原始 scene 隔离，且原始 24 个冻结条目 0 不匹配；
- [ ] 每个被绘制方向、goal、blocked、unreachable、owner group 和 repair 状态均可追溯到 trace，并通过逐 cell/tick 语义对照；
- [ ] C-FF/IDFF 共用同一 glyph 语义；A*-R/D*L 未被错误表示为全场 flow field；
- [ ] 同一输入至少两次重放的 semantic-state hash 完全一致；
- [ ] 大网格路径不使用 per-cell `GameObject + SpriteRenderer`，并通过 256×256 可交互 Play-mode smoke；
- [ ] HUD watermark 始终可见，capture 数据没有进入正式 timing 数据或正式统计；
- [ ] representative selection、trace、场景/代码、OBS 配置和视频文件均有 manifest 与 SHA-256；
- [ ] 可在 Unity Editor 中 Play，并完成一段不少于 30 秒的 OBS capture smoke；
- [ ] Gate 11 retained bundle、Gate 12 `v1`、两个失败尝试归档、Gate 13 amendment/preparation/formal evidence（若届时存在）均未被改写；
- [ ] 无残留 Unity 进程或 `Temp/UnityLockfile`。

---

## 16. Gate 16 — 论文与最终复现包

状态：最终阶段

### 16.1 论文结构建议

1. Introduction：动态多 agent 导航问题和研究贡献；
2. Related Work：A*、D* Lite、flow field、动态/增量 flow field；
3. Method：共同网格/成本/事件合同和四算法；
4. Experimental Design：场景矩阵、预算、重复、硬件、统计；
5. Results：正确性、性能、扩展性、失败和消融；
6. Discussion：共享目标优势、动态范围、内存、外部有效性；
7. Threats to Validity：Unity runtime、allocation fallback、固定起点微基准、场景选择；
8. Conclusion；
9. Reproducibility appendix。

### 16.2 最终复现包

- 规格文档；
- source code；
- canonical scenarios 和 catalog；
- campaign 配置；
- verification scripts；
- 原始 manifest/JSONL/result；
- 聚合和分析脚本；
- 图表源数据；
- Gate 15-V 的可视化 scene、trace schema/manifest、播放配置、OBS 配置、字幕/图例和补充视频 hash；
- 环境版本和运行命令；
- 基线哈希和不可变归档哈希；
- 已知限制与失败样本。

### 16.3 Definition of Done

- [ ] 四算法均通过独立正确性 Gate；
- [ ] 正式场景和实验方案已冻结；
- [ ] 正式 campaign 完整且 hash 验证通过；
- [ ] 统计分析可从原始数据重建；
- [ ] 论文中的每个数字能定位到结果文件；
- [ ] 原始项目冻结文件 0 不匹配；
- [ ] 没有残留 Unity 进程或 lockfile；
- [ ] 最终 checkpoint 和复现说明完整。

---

## 17. 每个 Gate 的标准工作流程

每个后续 Gate 都执行相同的质量流程：

1. Scope：写清目标、排除项和授权状态；
2. Specification：先固定语义，再写实现；
3. Oracle：建立独立正确性参考；
4. Implementation：只新增研究目录文件；
5. Compile：真实 Unity batch compile；
6. Behavioral verification：正向、边界、错误和确定性测试；
7. Regression：运行所有先前 Gate；
8. Preservation：核对 24 个冻结条目和 ZIP；
9. Evidence：保存日志、结果、hash 和 summary；
10. Documentation：更新 Gate checkpoint、验证 README 和本计划；
11. Clean exit：确认 Unity 进程为 0、lockfile 不存在；
12. Resume point：更新 `Next_Session_Checkpoint.md`。

任何一个步骤失败都不得把 Gate 标记为完成。

---

## 18. Codex 用量与会话停止规则

当前用户指令（2026-10-05）：取消所有项目自定义的 Codex 用量限制。没有活动的 ceiling、固定余量、周剩余量预算、百分比停工线或节省用量规则。此前记录的 89% 周剩余量提案在审计前已被后续指令覆盖，只保留为决策历史，不参与启动、暂停或停止判断。

Gate 10 fairness specification 是 Gate 12 的冻结输入，继续保持 SHA-256 `42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd`。其中历史 8% 窗口规则只用于 provenance；Gate 13 由 versioned amendment 的无自定义用量上限策略覆盖，不得把历史文本恢复为活动控制条件，也不得为删除历史文本而改写该冻结文件。

执行规则：

1. 不以任何用量百分比、窗口余量或周预算替代 Gate 授权边界；
2. 只在平台实际阻止继续、用户要求暂停、技术失败或授权 Gate 完成时保存并退出；
3. 需要停止时必须：
   - 保存当前文件；
   - 运行比例适当的快速检查；
   - 停止/确认无 Unity 进程；
   - 写入精确 checkpoint；
   - 记录通过、失败和未完成项；
4. 不因节省用量而降低验证强度；
5. 不为了消耗可用用量而扩大未授权范围；
6. 新窗口恢复时先读 checkpoint，不重复已经完成的工作。

边界说明：项目无法取消 OpenAI 平台实际执行的账户/计划限制；若平台阻止继续，只能保存精确恢复点并等待可用性恢复。取消自定义用量限制也不等于授权购买 credits、兑换 reset、启动 Gate 13 或越过任何研究 Gate。

---

## 19. 运行环境与权限计划

正常 headless Unity 工作需要：

- 当前任务使用与用户本地环境兼容的执行身份；
- 能访问 `H:\DDM_Final_Project` 和 `H:\UnityEditor`；
- 能访问 Unity 本地许可证服务；
- interactive Unity Editor 关闭；
- 项目没有 `Temp\UnityLockfile`；
- 不需要为了正常 Gate 常规运行而修改原始项目权限；
- 管理员身份不是默认要求，只有明确的主机/许可证问题才单独诊断。

Unity 路径：

```text
H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe
```

---

## 20. 风险登记表

| 风险 | 影响 | 预防/缓解 | 触发后的动作 |
|---|---|---|---|
| 原始脚本或 scene 被改动 | 破坏基线 | 研究目录隔离、24 项 hash 审计 | 立即停止，定位差异，不自动覆盖用户文件 |
| 算法语义漂移 | 比较无效 | Gate 前规格冻结 | 阻止实验，修正规格/实现并重跑 |
| 流场与 per-agent 目标不公平 | 结论无效 | 拆分 shared/heterogeneous cohort | 重建设计，不合并错误结果 |
| A*-R 动态成本漏算 replans | 人为偏向 A*-R | 聚合 acknowledgement + replans | 结果作废并重跑 |
| Unity/JIT/GC 噪声 | timing 偏差 | 独立进程、顺序平衡、pilot | 增加样本或改用稳健摘要 |
| managed allocation fallback 是 process-wide | 内存隔离较弱 | 所有算法同一方法并公开限制 | 不把小差异解释为确定优势 |
| 场景矩阵过大 | 时间/磁盘失控 | balanced core + stress series | 缩减预注册矩阵而非事后挑结果 |
| 输出被覆盖或混合 | 无法审计 | create-new、唯一目录、hash | 保留失败目录，使用新 id 重跑 |
| budget 导致不同功能结果 | aggregate 不可比或失败 | pilot 调预算、记录失败类别 | 按预注册规则分析，不删除失败 |
| Unity 许可证/身份失效 | 无法自动运行 | 开始前做 batch compile | 停止并修复执行环境，不改代码规避 |
| 严格串行 campaign 周期长 | 计划停机、重启或外部中断会使 attempt 失效 | PR2 active v2 已冻结 S48/H48，p95 包络 26.46 h；禁用休眠并做 fresh preflight | fail closed，保留部分证据；不得 resume/merge，只能经新授权开始新 attempt |
| heterogeneous pilot order / carryover | 原 Gate 12R order 89:7，cross-family variance/order effect 难以分离 | PR1B balanced mirrored recovery 已提供 96 pairs，P1 为 9 bounded、2 below-bound、5 inconclusive、0 material；正式 H schedule 仍须 AB/BA 24/24 | 推荐 H48 吸收剩余 uncertainty；不把 diagnostic 转为 superiority，当前不再建议 supplemental pilot |
| 10% assumed effect 下 C2 power 不足 | 可能得到 inconclusive primary contrast | 在 PR2 明确 effect interpretation；优先 S48；报告 5/10/15/20% sensitivity | 不降低 alpha/门槛；扩大设计或接受 inconclusive |
| PowerShell 7 模块路径污染 Windows PowerShell 5.1 | formal runner 在 root 前无法重建配置 | 启动 child 时使用经诊断验证的原生 Windows PowerShell `PSModulePath`，不修改冻结 runner | 保留 attempt 证据、0 自动重试，获得新授权和新 attempt identity 后再启动 |
| block native-memory threshold 把 scenario/project residency 与 planner growth 混合 | 大 grid 正常常驻可能被误判，或真实 runaway 被放过 | 在新 NON-FORMAL pilot 中拆分 process/project/scenario/sample stages；四 scale 与 Williams rows 平衡；保留 managed/native 区分 | policy 保持 UNFROZEN；pilot 前不得启动 formal attempt 3 |
| block hard gate 仅在 final sample enforce | 最终位置算法可能被错误归因为越界原因 | 同时报告 first observed crossing 与 final enforcement point；禁止基于一个 block 作 algorithm attribution | 需要 prospective balanced pilot；C-FF/A*-R 均不得被宣布为原因 |
| post-exit quiescence error 遮蔽 durable block failure | outer status 失真、诊断困难 | 候选 wrapper 先保留 durable primary，再附加 secondary quiescence；两者均 fail closed | versioned pilot-only 验证；不得就地修改 frozen V6 或继续失败 attempt |
| 平台实际用量限制中断工作 | 当前 turn 或后续工作无法继续 | 不设项目自定义余量线；保持细粒度 checkpoint | 写精确 checkpoint，确认进程/锁状态，待平台恢复后续接 |
| 论文结论超出微基准范围 | 外部有效性问题 | 明确 planning vs movement | 降低结论范围或授权 Gate 14 |
| 可视化录制被误当作 timing 证据 | 污染实验结论 | 独立输出根、固定 watermark、只读取冻结统计 | 停止发布，修正标注/manifest，不改写正式数据 |
| 为录屏事后挑选“最好看”的场景 | 展示偏倚 | 预先冻结 canonical identity/seed 选择清单 | 重新按 manifest 录制并披露选择规则 |
| per-cell Unity 对象导致大网格卡顿 | 无法稳定 Play/录制 | instancing、batched mesh 或 dynamic texture | 阻止 Gate 15-V 验收并重构 renderer |

---

## 21. 粗略工作量估计

以下以完整、高强度验证会话为单位，不是承诺日期：

| 阶段 | 预计会话 | 主要不确定性 |
|---|---:|---|
| Gate 7 D* Lite | 已完成（1 个集中会话） | 状态生命周期、动态 oracle、预算恢复均已验证 |
| Gate 8 C-FF | 已完成（1 个集中会话） | 多源 cost、direction tie-breaking、原子重算与独立 oracle 均已验证 |
| Gate 9 IDFF | 已完成（1 个集中会话） | 增量传播、dirty direction、预算恢复及逐事件 fresh-C-FF 对照均已验证 |
| Gate 10R block-process 合同 | 已完成；attempt 4 通过 | one-fresh-Unity-process-per-Williams-block、telemetry、reset、结构对照与 retained regression 已冻结 |
| Gate 11R 5% 场景/Playable bundle | 已完成；attempt 2 通过 | 53/74/212、53 Playable scenes、1 launcher、744 artifacts、89/89 final audit |
| Gate 12R fresh pilot/样本量 | 已完成；attempt 4 与 readiness 通过 | 384 blocks / 1,152 measured；PR1 只读重分析 P1–P5 observability 与五 contrasts；原 548/768/400 和 144/204/108 都不是活动 launch n |
| Gate 13R 旧 5% / 并发 redesign | 历史证据，非活动路线 | 旧 5% preparation 未执行；4-lane v16 与 3-lane v1 永久排除；不得恢复、合并或作为 formal 输入 |
| Gate 13R strict-serial 10% v2 | pre-amendment baseline | 11,160 blocks / 31,536 samples；不得使用旧 config/schedule/prompt 启动 |
| Gate 13R-PR1 | 已完成并通过 | 五 contrasts、十指标、Gate 12R reanalysis、S/H sensitivity、66/66 final audit |
| Gate 13R-PR1B | v4 recovery 已完成 | 96 balanced mirrored pairs；396/396 composite identities；0 material P1 order-effect cells；raw pilot 仍 failed/excluded |
| Gate 13R-PR2 preparation | 已完成；validation v4 通过 | S48/H48 frozen design 与 active v2 artifact set 保留；63/63 core；p50 20.81 h / p95 26.46 h 为历史规划包络 |
| Gate 13R-PR2 formal attempts 1–2 | 两次失败并冻结 | attempt 2 完成 933 blocks 后 native-memory fail；partial evidence 永久 excluded/no-resume/no-merge |
| Gate 13R-PR2-FD1 | 已完成；21/21 final audit | evidence tree 冻结；primary/secondary failure 已区分；memory policy UNFROZEN；targeted pilot required |
| Gate 13R-PR2-MP1 pilot v1 | 失败并冻结；0 blocks / 0 samples | pre-pilot 29/29；checkpoint schema 在首个 Unity 前失败；5 files / 5,247 bytes / tree `a1f427...`; no-retry/no-resume |
| Gate 13R-PR2-MP1 attempt 2 / v2 | 已完成并通过 | pre-pilot 34/34；96/96 blocks / 384/384 samples；3,360 raw files / 2,607,785,161 bytes / tree `13dd5c30...`；analysis attempt 1 passed |
| Gate 13R-PR2-MP2 | 已完成；attempt 4 通过 | scale-aware policy 已前瞻冻结；active V4 candidate；formal attempt-3 root/receipt/sample 均不存在 |
| Gate 13R 研究问题对齐正式 campaign attempt 3 | 未授权；不得启动 | MP2 通过后仍需新的 one-shot formal authorization；不得预先创建 root/receipt |
| Gate 14 可选移动实验 | 3–6 | movement/collision 合同 |
| Gate 15 统计分析与图表 | 2–3 | 结果复杂度、预注册分析和异常解释 |
| Gate 15-V 可视化与 OBS 补充视频 | 4–8 | trace 完整性、批处理 renderer、Play/OBS 验证；Gate 14 未执行时不交付 movement replay |
| Gate 16 论文与复现包 | 2–4 | 论文格式、反馈轮次和补充材料封装 |

每个 Gate 完成后重新估计，禁止把粗略估计当作跳过验证的依据。

---

## 22. 决策点和授权模板

### 当前运行边界

当前没有活动 Unity runner。PR2 S48/H48 formal attempts 1–2 均已 fail closed；MP1 pilot v1 在 0 blocks / 0 samples 时失败并冻结，MP1 v2 的 immutable raw/只读 diagnostic analysis 保持不变。MP2 与 attempt-3 monitoring/recovery 非执行准备均已完成，但这不等于 formal launch authorization。当前下一步不是自动启动 attempt 3，也不是重跑任何 pilot，而是：

1. 先读 `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Readiness_Checkpoint.v2.json` 与 `.md`，再读 MP2 readiness、active V4 candidate config/adapter/provenance、monitoring v2 config/implementation、state machine、validation attempt 3 evidence 和 `Research/Next_Session_Checkpoint.md`；
2. attempt 2 根 `Research/FormalRuns/Gate13R_RQAligned_S48H48/v2` 永久保持只读、failed、excluded、no-resume/no-top-up/no-merge；其 933 个完整 blocks 与失败 partial block 只可用于失败诊断；
3. 活动研究合同仍为完整 74-campaign、shared P1 five-contrast primary、heterogeneous secondary、P2–P5 supportive、M1–M5 prospective，以及 fresh-process-per-block/reset/Williams/telemetry/排除规则；
4. FD1 已确认 block native-memory delta 在失败 block 的 position 1 即超过 512 MiB；position 4 C-FF 是最终执行门禁的位置，不是可识别的内存增长原因；
5. MP2 已前瞻冻结：`<=128` grid 使用 512 MiB advisory / 640 MiB hard，`256` grid 使用 640 MiB advisory / 768 MiB hard；retained-managed 128/256 MiB 与 host 4 GiB/2 GiB/8 GiB 规则保持；
6. pilot v1 root 永久保持只读、failed、zero-sample、no-retry/no-resume/no-top-up/no-merge；
7. pilot v2 raw tree 永久保持 immutable；普通分析/文档缺陷只能建立新 versioned analysis/audit，不得触发 Unity 重跑；
8. 默认推荐下一步是用户审阅并单独授权 active `Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md` 中的一次性 formal attempt 3；它绑定 v2 monitor，在 acquisition 与 raw commit 均提供小时报告和分阶段受限 recovery，但采集期仍禁止 measured retry/resume/top-up/merge。在授权前不得创建 formal root/receipt/status，也不得启动 measured block。

默认方向箭头使用 `research-visual-direction-glyph-v1`。Gate 11R 已创建并验证 53 个 scenario scenes、74 个 campaign profiles、212 个 algorithm presets 和 launcher；其固定水印为 `VISUALIZATION REPLAY — NOT A TIMING RUN`。Gate 12R 已验证 12/12 pilot campaign 的 Playable 映射，但尚未生成 formal-linked trace、未录制视频，也未把 Playable 数据作为 timing evidence。

### 已使用的 attempt-2 授权文本（历史记录）

```text
授权重试 Gate 13 正式启动：保留 `Research/Gate13_Execution_Authorization.v1.json`、attempt-1 日志、诊断和检查点不变；创建绑定相同 config/amendment/output root 的 attempt-2 versioned receipt，仅在启动子进程时使用已验证的 Windows PowerShell 5.1 原生 `PSModulePath`。重新运行全部 receipt、hash、环境和 raw-byte storage preflight，全部通过后才创建 formal root 并继续 74 campaigns / 15,056 samples。禁止自动 retry/resume；再次失败时保存新 attempt 证据后停止。
```

如果只希望暂停 Codex 交互而让已启动的正式 campaign 自行运行：

```text
暂停新的项目操作；不要终止、复制或重启当前 Gate 13 attempt 2。保持电脑供电、唤醒和高性能模式，并保留 attempt-1/attempt-2 receipt、日志、检查点、formal root、amendment、preparation/config、Gate 11 retained bundle、Gate 12 `v1` 与两个 Gate 12 失败归档不动。下次只按 `Research/Gate13_Formal_Launch_Attempt2_Checkpoint.md` 做只读状态核验。
```

Gate 15 和适用的 Gate 14 完成后，如需单独授权可视化实施，建议使用：

```text
授权 Gate 15-V：按 `gate15v-playable-visualization-v1` 与 `research-visual-direction-glyph-v1` 实现研究专用可 Play 场景、确定性 trace/replay、HUD 和 OBS capture smoke。可视化只读取冻结场景与结果，不产生或修改 Gate 13/14 timing 数据；不得修改原始脚本、原始场景、Gate 11 retained bundle、Gate 12 归档或任何冻结正式输出。规格与测试设计通过后再实现，完成验证后停止，不自动进入 Gate 16。
```

---

## 23. 计划维护规则

本文件在以下情况更新版本：

- Gate 状态改变；
- 算法顺序或研究问题改变；
- 实验矩阵、指标或统计规则冻结；
- 新风险被发现；
- 用户改变范围或交付目标；
- 正式 campaign 开始或完成；
- 可视化设计、trace、录制或补充材料范围发生实质变化；
- 论文结构或最终复现包发生实质变化。

更新时必须保留：

- 已完成 Gate 的证据；
- 被替代计划的原因；
- 新增授权边界；
- 与 `Next_Session_Checkpoint.md` 一致的恢复点。

---

## 24. 当前结论

当前活动结论：Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R pilot attempt 4、Gate 13R-PR1、Gate 13R-PR1B v4 recovery、PR2 non-executing preparation、PR2-FD1、MP1 attempt 2 / v2 与 MP2 non-executing readiness 均已完成各自授权范围。MP1 v2 完成 96 blocks / 384 samples，建立了可复核的 stage-separated memory evidence，但仍是 `NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS`；MP2 只把该证据前瞻性转成 formal eligibility policy，没有把 pilot observations 变成正式数据。正式研究问题仍是 shared-goal P1 的 C1–C5 confirmatory family；heterogeneous 是 secondary system/treatment；P2–P5 supportive；M1–M5 prospective Gate 14R。PR1B recovery、PR2-FD1、MP1 v2 与 MP2 validation 均不是 algorithm superiority evidence。

PR2 S48/H48 的设计仍保留为未来正式候选，但 formal attempt 1/2 已作为失败历史冻结。attempt 2 在 933/3,552 个完整 block processes、3,732/10,176 个完整 samples 后于 global ordinal 934 fail closed；两阶段提交没有进入 `RAW-DATA-COMPLETE`。其 28,020-file、8,536,611,302-byte evidence root 已全部只读，canonical ordinal tree SHA-256 为 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`。

FD1 对 3,736/3,736 个有效 memory evaluations 的审计显示：managed block growth 最大 190,205,952 bytes，零 256 MiB exceed；working-set/private-memory block delta 只有失败 block 超过 512 MiB。关键执行语义是 native threshold 在每个 sample boundary 测量，但 block hard-fail 仅在 final sample enforce。失败 block 从 position 1 A*-R 就已越界，position 4 C-FF 只是 enforcement point；algorithm、position、predecessor、正常 g256 residency 与 native leak 原因均不可由该 block 识别。

MP1 v2 结果未发现 runaway growth 或 host-safety emergency；最大 cleanup native delta 为 556,359,680 bytes，最大 retained managed cleanup delta 为 84,762,624 bytes，最低 available physical memory 为 16,199,168,000 bytes。g256 中 1/48 blocks 超过 512 MiB、13/48 达到 512 MiB 的 90%，但 0/48 超过 640/768/1,024 MiB。MP2 已在 formal data 前冻结 `<=128` grid 的 512/640 MiB advisory/hard 与 `256` grid 的 640/768 MiB advisory/hard，并通过两个 tier 的精确边界、telemetry、failure precedence、persistence 和 lock-hygiene 验证；它仍不能在没有用户正式授权时启动 attempt 3。

Playable Scenes 已从末端补充项提升为 Gate 11R 的输入完整性要求，并已实际交付：53 个 scenario scenes、74 个 campaign profiles、212 个 algorithm presets 和 1 个 launcher 覆盖所有实验 cell；统计重复通过 block/position/run identity 映射到同一 canonical scene。独立 Unity 验证已加载所有场景/launcher、验证 GUID/hash/controller 绑定并初始化 212/212 planner cells，Gate 12R 又验证了 12/12 pilot campaign 映射。Gate 13R timing 始终 headless，未来 Gate 15V-R 才生成 formal-linked replay 并录制 OBS；当前 Playable bundle 明确为 visualization-only，不是正式 timing 运行。

旧 Gate 10–13、10%/cap-148 cold-process amendment、两次 cold formal launch、Gate 13-R2 pilots、parallel 设计与旧 strict-serial v2 launch design 均单独作为历史/比较证据保存；不得用其 config/prompt 启动或把正式 observations 混入未来 PR1 谱系。

当前唯一默认下一步是审阅后单独授权 Gate 13R-PR2 formal attempt 3，或明确选择其他工作。当前推荐模板为 `Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md`；它把 active V4 candidate、MP2 readiness、active v2 monitoring/recovery、两阶段提交、fresh prelaunch、one-shot fail-closed 和 acquisition no-auto-retry/resume/top-up/merge 精确绑定。当前 Unity 进程为 0，lock 不存在，attempt-3 formal root/receipt/status 均不存在；正式统计分析和 Gate 14R 也未授权。

---

## 附录 A — 重基线来源与权威文件

2026-10-06 的原始重基线决定、证据边界与机器可读身份继续保留：

- `Research/Gate10R_5pct_Rebaseline_Decision.v1.json`；
- `Research/Gate10R_5pct_Rebaseline_Evidence_Audit.v1.json`；
- `Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md`。

本文第 10 节是当前活动路线摘要，`Research/Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json` 是当前精确恢复点。旧 Gate 10–13 的独立历史说明位于 `Research/Historical_Gate10_to_Gate13_Archive.md`；旧 serial/parallel/cold checkpoints 继续作为比较或排除证据。当文本存在状态差异时，以最新 versioned machine-readable checkpoint、registries、analysis manifest 和 final audit 为准。

---

## 附录 B — Gate 13R-PR1B balanced order-effect pilot attempt 1 终态

2026-10-08，用户采用“为 heterogeneous cross-family secondary 提供更强 pilot-level order-effect 可识别性”的方案后，建立并预注册 Gate 13R-PR1B：三个 heterogeneous canonical scenarios，每场景 32 个 mirrored AB/BA pairs，共 96 pairs、384 measured fresh Unity block processes、768 measured samples；另有 12 个 excluded warm-up processes。独立单位仍是一个 fresh Unity Editor process 执行一个完整 Williams block，严格串行。

全部 parser/static/unit/compile/telemetry/positive mirrored/negative fail-closed/independent-process/hash/provenance/validation-only 门禁通过；pre-pilot final audit 为 38/38。pilot 完成 12/12 warm-up processes，并完成第一 wave 的 12 measured processes（3 complete mirrored pairs）后，在第 13 个 measured process fail closed：`core-r07-s2-hetero`、block 2、BA、grouped-field first、IDFF position 1 的 sample retained managed-memory growth 超过冻结的 128 MiB。

attempt 1 的最终身份是：

`FAILED-NO-RETRY-NO-RESUME-NO-MERGE / EXCLUDED-FROM-FORMAL-ANALYSIS / EXCLUDED-FROM-ORDER-EFFECT-INFERENCE`。

工作负载在内存门禁前已完成，且与同一 Gate 12R v4 counterpart 比较的 34/34 deterministic structural fields 一致，故当前证据不指向算法正确性漂移。Gate 12R v4 的 1,176 个已完成样本中没有一个超过 128 MiB；全体最大值 101.26 MiB，IDFF position-1 最大值 95.22 MiB，同一 counterpart 为 −88.54 MiB。当前事件是新的 retained-memory outlier，但 v3 command 在写出 threshold telemetry 前抛异常，导致确切超限值不可恢复；这是下一版本必须先修复的 observability gap。

当前项目没有 Unity 进程，Gate 13R formal root/receipt/sample 均不存在。异常退出留下一个零字节且可独占访问的 `Temp/UnityLockfile`；在新的 versioned controlled-recovery 授权前保持不动。15/15 冻结上游文件在运行后 SHA-256/字节数均未改变。

当前权威恢复点更新为：

- `Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Terminal_Preservation.v1.json`；
- `Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Failure_Diagnosis.v1.md`；
- `Research/Gate13R_PR1B_OrderEffect_Failure_Checkpoint.v1.json`；
- `Research/Gate13R_PR1B_OrderEffect_Failure_Checkpoint.v1.md`。

推荐下一步不是盲目 retry 或任意提高阈值，而是单独授权 PR1B v2：先持久化 threshold decision 前的完整 telemetry；把 128 MiB 改为 sample diagnostic alert，把 256 MiB 设为两样本 heterogeneous block 的 independent-unit hard gate并同时作为 sample emergency stop，保留 working/private 512 MiB、reset、structural、hash 和 fail-closed 规则；所有验证通过后才允许在全新根运行一次新的 NON-FORMAL pilot。可复制授权文本位于 `Research/Gate13R_PR1B_OrderEffect_Next_Authorization_Prompt.md`。在用户授权前不得清理 lock、启动 Unity、创建新 pilot/formal root、retry/resume 或分析 attempt 1 的部分结果。

---

## 附录 C — Gate 13R-PR1B v2/v3 与 v4 composite-identity recovery 终态

附录 B 是 attempt 1 当时的历史终态，不修改、不删除。其后用户分别授权了 telemetry/independent-block eligibility 修复和 path-safe persistence。v2 保留失败证据；v3 path-safe pilot 在独立 v7 根完成全部 raw execution：12 warm-up processes / 24 excluded samples、96 measured mirrored pairs、192 measured matched superblocks、384 measured fresh Unity block processes和 768 measured samples。

v3 的 post-execution analyzer 随后失败。根因不是 measured workload、memory、reset 或 structural gate，而是冻结 v1 analyzer 把 numeric Windows PID 错当作整个长运行中的全局唯一 process identity。完成证据含 396 个 process records、375 个 numeric PID 和 19 个合法 PID reuse groups；同 PID 生命周期没有重叠。v7 根保持：

`FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / NON-FORMAL / COMPLETE-RAW-EXECUTION / POST-EXECUTION-ANALYZER-FAILED / EXCLUDED-FROM-FORMAL-ANALYSIS`。

用户随后只授权 Gate 13R-PR1B v4 的非执行 composite-identity 修复、validation 和一次只读 analysis recovery。v4 把 OS identity 定义为 `(PID,startTimeUtc)`，block evidence identity 定义为 `(PID,startTimeUtc,blockId)`；validation v2 通过 23/23 checks，确认 396/396 OS identities、396/396 block identities、768/768 measured run IDs，19 个 reuse groups 全部无 overlap。唯一 recovery 没有启动 Unity、没有重跑 measured blocks、没有生成样本，也没有修改 v7 任一字节。

recovered P1 order-effect 证据在 16 个 scenario/pooled cells 中给出 9 `ORDER-EFFECT-BOUNDED`、2 `DETECTABLE-BUT-BELOW-BOUND`、5 `INCONCLUSIVE`、0 `MATERIAL-ORDER-EFFECT`。pilot-level order effect 因而可识别，但部分 cells 不确定；这些 diagnostics 不能被解释为算法 superiority、pure-algorithm causal effect 或 formal result。768 measured samples 没有 managed-memory alert，P5 为 zero-event，未使用 pseudocount。

在 PR1B v4 收口时，当时的推荐是 shared `S48` 不变、heterogeneous 提升为 `H48`，即候选 `S48/H48`：3,552 processes、10,176 samples、serial p50 20.81 h、conservative summed-p95 26.46 h。该候选在当时仍是 `UNFROZEN / NOT-AUTHORIZED-FOR-LAUNCH`；当时不再建议运行 supplemental pilot。权威恢复点为：

- `Research/Gate13R_PR1B_v4_CompositeProcessIdentity_Recovery_Readiness_Checkpoint.v1.json`；
- `Research/Gate13R_PR1B_v4_CompositeProcessIdentity_Recovery_Readiness_Checkpoint.v1.md`；
- `Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1/`。

PR1B 收口时的下一步边界是单独授权 Gate 13R-PR2 非执行 formal preparation。该授权随后已由用户授予并完成；当时的模板 `Research/Gate13R_PR1B_v4_Next_Authorization_Prompt.md` 现在仅作历史授权来源保留。

---

## 附录 D — Gate 13R-PR2 非执行 formal preparation 终态

用户明确选择并冻结完整 74-campaign `S48/H48`，授权范围只包括 versioned amendment、formal config、Williams/matched-superblock schedule、storage/wall-clock preflight、checkpoint、test design、provenance 和 non-executing readiness。该授权没有包括 Unity、formal root、formal execution receipt、Gate 13R timing campaign 或 Gate 14R。

PR2 validation attempts 1–3 均按 fail-closed 保留：attempt 1 揭示 PowerShell 5.1/7 文化排序差异；attempt 2 证明 v1 pre-write 树摘要本身未明确 ordinal comparator；attempt 3 通过 62/63 core checks，唯一失败为新 schema 的 manifest 字段名不一致。所有失败均未启动 Unity或创建 formal root/receipt，且冻结树 pre/post 不变。修复只作用于 PR2 新建身份序列化与 schema，没有改变研究语义或门槛。

active artifact set v2 采用 `StringComparer.Ordinal` 树身份、修复后的 schema v2，以及完整 versioned config/schedule/manifest/preflight/provenance。validation v4 在 Windows PowerShell 5.1 下通过 63/63 core checks，验证：

- 53 scenarios、74 campaigns、212 presets；
- 每 campaign 48 blocks；
- shared 每 Williams row 12 次、每算法每位置 12 次；
- 21×48=1,008 matched superblocks；每 scenario AB/BA 24/24、order×row 12/cell；
- 3,552 unique block/process identities、10,176 unique run IDs、13,728 unique output paths；
- active Gate 11R Playable/profile/preset/scenario 哈希绑定；
- P1/C1–C5/Holm、heterogeneous secondary、P2–P5、M1–M5、memory、reset 和 fail-closed 语义；
- 6/6 official outputs byte-identical deterministic regeneration；
- formal root/receipt absence、零 Unity、全部冻结树前后不变。

active authoritative files：

- `Research/Gate13R_PR2_Formal_Campaign_Config.v2.json`；
- `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl`；
- `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json`；
- `Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json`；
- `Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json` 与 `.md`。

下一步只有在用户单独发送 `Research/Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md` 中的完整授权后，才可建立正式 execution adapter/receipt/root 并执行一次 fail-closed campaign。Gate 14R 仍需更后续的独立授权。

该段记录的是 PR2 preparation 完成时的历史边界。随后 formal attempts 1–2 已执行并 fail closed；当前边界已由附录 E 和 FD1 checkpoint 取代。旧 formal authorization prompt 不得再次用于启动。

---

## 附录 E — Gate 13R-PR2 formal attempts 与 FD1 终态

PR2 S48/H48 formal attempt 1 与 attempt 2 均按 fail-closed 保存，禁止 retry/resume/top-up/merge。attempt 2 使用两阶段提交合同，但在 raw acquisition 未完成前失败，因此没有 raw-data freeze receipt，也没有进入正式分析阶段。

attempt 2 在 global process ordinal 934、campaign `grid-scale-g256-shared--shared`、block `g13rpr2-c52-b0022` 处停止。933 个完整 blocks 和 3,732 个完整 samples 加上失败 block partial evidence 永久排除于正式推断。完整失败根已生成逐文件 SHA-256 manifest，随后冻结为只读；其 identity 为 28,020 files / 8,536,611,302 bytes / canonical tree SHA-256 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`。

FD1 区分了两个失败：primary 是 durable block native-memory hard fail；secondary 是 Unity 退出后遗留零字节 lock 导致的 post-exit quiescence fail。后者曾遮蔽外层错误消息，但没有造成 primary memory failure。stale lock 在 Unity/owned process 均为零、exact path/bytes/hash/timestamp/handle 通过后受控删除，failed root hash 不变。

冻结 Unity command 的 block-level native gate 在每个 boundary 计算 flags，却只在 `finalSampleInBlock` 执行 hard fail。失败 block 四个位置都已超过 working/private 512 MiB，首次越界发生于 position 1；position 4 C-FF 仅是最终 enforcement point。因此不得把 failure 归因于 C-FF，也不能把首次 crossing 归因于 A*-R。需要 prospective balanced diagnostic pilot 才能区分 g256 residency、first-workload initialization、position/predecessor 与真实 runaway growth。

FD1 的 validation-only 结果：23/23 core synthetic、4/4 canonical-order、11/11 enforcement-boundary、6/6 repair、PowerShell 7 与 Windows PowerShell 5.1 各 10/10 failure-precedence、5/5 deterministic regeneration、21/21 final audit。未启动 Unity、未创建 attempt-3 root/receipt、未运行正式统计分析或 Gate 14R。

当前权威文件：

- `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json` 与 `.md`；
- `Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json`；
- `Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json`；
- `Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/` 与 `v2/`；
- `Research/Gate13R_PR2_MemoryPolicy_Targeted_Pilot_Next_Authorization_Prompt.md`。

---

## 附录 F — Gate 13R-PR2-MP1 attempt 2 / v2 终态

MP1 v1 的 zero-block failure 保持不可变。用户另行授权的 MP1 attempt 2 / v2 只修复 checkpoint state machine、path-safe atomic persistence、入口兼容和 root-specific tree-audit 缺陷；五个 validation failure attempts 均各自保留。最终 pre-pilot attempt 6 通过全部 34 个有序步骤。

唯一获授权的 measured v2 pilot 随后严格串行执行，一次完成 96/96 fresh Williams-block processes 和 384/384 algorithm samples。没有 automatic retry、resume、top-up、partial merge 或 schedule reorder。Phase A 原子提交并冻结：

- pilot root：`Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v2`；
- raw files：3,360；
- raw bytes：2,607,785,161；
- raw canonical tree SHA-256：`13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`；
- 状态：`RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`。

Phase B analysis attempt 1 只读重哈希全部 raw files，并生成 96 blocks / 384 samples / 1,824 stage records 的 diagnostic analysis。一个 post-pilot audit attempt 因误用 pre-pilot 的 “v2 root must be absent” 条件失败并独立保留；versioned post-pilot audit v2 随后通过。该普通审计缺陷未导致 Unity 重跑。

诊断未发现 runaway growth 或 host-safety emergency。基于 g032/g064/g128/g256 的 scale trend，推荐但尚未冻结：

- max grid dimension `<=128`：512 MiB native advisory，640 MiB native hard eligibility；
- max grid dimension `==256`：640 MiB native advisory，768 MiB native hard eligibility；
- retained-managed：继续保留 forced-cleanup 后 128 MiB alert / 256 MiB emergency；
- host safety：继续保留 4 GiB absolute / 2 GiB relative / 8 GiB available-memory floor；
- advisory crossing 只记录；hard crossing 必须先持久化，再在下一个 block 前 fail closed；
- crossing 属于 whole-block/process eligibility，不能归因于 final-position algorithm。

该推荐只可在未来的 MP2 非执行 amendment 中前瞻冻结。MP1 v2 不授权也不创建 formal attempt-3 root/receipt，不运行正式统计分析或 Gate 14R。权威恢复文件：

- `Research/Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json` 与 `.md`；
- `Research/Gate13R_PR2_MP1_v2_Memory_Policy_Recommendation.v1.json`；
- `Research/Gate13R_PR2_MP1_v2_PostPilot_Frozen_Root_Audit.v2.json`；
- `Research/Analysis/Gate13R_PR2_MP1/v2/attempt-1/`；
- `Research/Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md`。

---

## 附录 G — Gate 13R-PR2-MP2 非执行 readiness 终态

用户授权 MP2 仅做前瞻性 memory-policy 冻结、formal-attempt-3 candidate config/adapter 和 validation-only readiness；未授权创建 formal root/receipt、运行 measured campaign、正式统计分析或 Gate 14R。MP2 完成后，附录 F 中的 “recommended but unfrozen” 已被本附录的 prospective frozen policy 取代，但 MP1 v2 raw/analysis 仍保持 NON-FORMAL、只读和 excluded。

冻结 policy `gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1`：

- completed-sample cleanup 与 post-block 使用相对 block baseline 的 `max(working-set delta, private-memory delta)`；
- max grid `<=128`：512 MiB advisory、640 MiB hard；
- max grid `==256`：640 MiB advisory、768 MiB hard；
- unknown/ambiguous dimension 在 measured launch 前 fail configuration；
- exact threshold passes；超过 advisory 记录并继续；超过 hard 先持久化并禁止下一个 block；
- raw-after-workload crossing 只作 diagnostic，host emergency 除外；
- crossing 归属 whole-block/process，不归因于 final-position algorithm；
- managed cleanup 128 MiB alert、256 MiB sample/block emergency；
- host 4 GiB absolute native、2 GiB relative native growth、8 GiB available floor 与 telemetry invalid/overflow fail closed。

validation 历史全部保留：

1. attempt 1：66/67，V1 PowerShell module 未显式返回 raw-stage diagnostic reason；
2. attempt 2：self-test、telemetry 和 positive block 通过，native-hard expected-negative 证据正确，但 V2 wrapper 错误拒绝 lock module 已通过的 `controlled-expected-negative-cleanup`；
3. attempt 3：在创建 candidate artifacts 前因 V2 provenance SHA-256 字面值抄录错误 fail closed；零 Unity；
4. attempt 4：active V3 wrapper + V4 candidate 完整通过。

attempt 4 证据：

- static/unit/deterministic：69/69；
- Unity memory fixtures：22/22；telemetry sequence fixtures：8/8；
- PSAPI/CIM probe、license、lock hygiene：passed；
- positive complete `<=128` block：passed / natural lock absence；
- expected-negative `==256` native hard、telemetry failure、persistence failure：全部 passed / durable fail-closed / controlled exact-file lock cleanup；
- schedule/mapping：53 scenarios、74 campaigns、3,552 processes、10,176 samples、1,008 matched superblocks，原 PR2 v2 schedule 字节不变；
- two-stage raw/analysis state machine：passed；analysis failure 不得触发 acquisition 重跑；
- post-validation audit：MP1 v2 raw tree `13dd5c30...`、pilot v1 `a1f427...`、formal attempt 2 `aafd8018...` 与全部只读身份保持不变；
- formal attempt-3 root、execution receipt、status 和 measured samples：不存在。

当前活动 candidate：

- `Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Config.v4.json`；
- `Research/Gate13R_PR2_MP2_Formal_Attempt3_Candidate_Adapter.v4.json`；
- `Research/Gate13R_PR2_MP2_Provenance.v4.json`；
- `Research/Gate13R_PR2_MP2_ExpectedNegative_LockHygiene_Repair_Amendment.v1.json`；
- `Research/Gate13R_PR2_MP2_NonExecuting_Readiness_Checkpoint.v1.json` 与 `.md`。

下一步只有在用户单独授权 active `Research/Gate13R_PR2_Attempt3_Next_Authorization_Prompt.v4.md` 的完整正文后，才可重新运行所有 fresh prelaunch 门禁，并在全部通过后创建精确 versioned formal attempt-3 root/receipt，执行一次严格串行 S48/H48 campaign。MP2 readiness 本身不授权 formal launch、正式分析或 Gate 14R。
