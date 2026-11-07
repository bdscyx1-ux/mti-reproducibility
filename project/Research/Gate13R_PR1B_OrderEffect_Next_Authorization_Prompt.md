# Copyable next authorization — Gate 13R-PR1B v2

```text
授权 Gate 13R-PR1B v2「managed-memory 可观测性与 independent-block eligibility 的受控、版本化修复、验证及一次全新的 NON-FORMAL balanced mirrored order-effect pilot」；不授权 Gate 13R 正式 campaign，不授权 Gate 14R。

一、attempt 1 的终止与保留

1. 以以下文件为 attempt 1 的终态依据：
   - Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Terminal_Preservation.v1.json；
   - Research/Gate13R_PR1B_OrderEffect_Pilot_Attempt1_Failure_Diagnosis.v1.md；
   - Research/Gate13R_PR1B_OrderEffect_Failure_Checkpoint.v1.json；
   - Research/PilotRuns/Gate12R_ProcessReuse_5pct/v5-gate13r-pr1b-order-effect/。

2. attempt 1 必须永久保持：
   FAILED-NO-RETRY-NO-RESUME-NO-MERGE /
   EXCLUDED-FROM-FORMAL-ANALYSIS /
   EXCLUDED-FROM-ORDER-EFFECT-INFERENCE。

3. 不得修改、覆盖、删除、重命名、补齐、resume、top-up、合并或重新解释 attempt 1。其 3 个完整 measured mirrored pairs 和失败 IDFF workload 只允许用于失败诊断与 provenance，不得用于 order-effect、algorithm-effect、样本量或正式推断。

4. 完整保留 Gate 10R attempt 4、Gate 11R attempt 2 retained bundle、Gate 12R v4、Gate 13R-PR1、历史 cold/process-reuse roots、旧 36h/48h/parallel/serial 设计、原始脚本、原始场景和原始项目归档。冻结输入必须进行前后 SHA-256 不变性审计。

二、受控 lock 恢复

5. 在任何 Unity 启动前，只读核验：
   - 没有指向 H:/DDM_Final_Project 的 Unity.exe 进程；
   - H:/DDM_Final_Project/Temp/UnityLockfile 为 attempt 1 异常退出留下的零字节文件；
   - 该文件可被独占读写打开；
   - attempt 1 quiescence-failure、Unity log、failure receipt 和 terminal preservation 哈希一致。

6. 上述条件全部满足后，授权仅删除该精确 lockfile。删除前后创建独立、原子、版本化的 stale-lock recovery receipt，记录绝对路径、大小、SHA-256、进程审计、独占访问结果、UTC/Asia-Shanghai 时间和操作结果。不得删除 Temp 目录或任何其他文件；任一条件不满足立即停止。

三、v2 可观测性修复

7. 不得修改冻结的 Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs。必须创建新的 versioned v2 Unity command/wrapper/config/provenance/test 文件。

8. 新命令必须在应用任何 managed-memory threshold 之前原子写出 memory-gate-evaluation.json，至少包含：
   - run/block/scenario/cohort/algorithm/position/predecessor identity；
   - before、raw-after-workload、after-cleanup 的 managed/working-set/private bytes；
   - GC collection counts；
   - process ID、start time 和 process age；
   - sample retained managed growth；
   - block cumulative/net growth；
   - 全部 warning/hard thresholds；
   - 判定结果和 reason code。

9. 即使随后 fail closed，failure.json、block-failure.json 和 checkpoint 也必须引用上述 evaluation 的路径和 SHA-256，使任何 threshold failure 的精确数值可恢复。缺测、NaN、非有限值、混合 PID、时间倒序或写出失败均为硬失败。

四、前瞻性 memory eligibility amendment

10. 在任何新 Unity 数据生成前冻结新的 versioned amendment。对本次仅含两个算法样本的 heterogeneous Williams block，memory policy 冻结为：
    - 134217728 bytes 保留为 per-sample diagnostic alert threshold，不再单独作为 sample validity hard failure；
    - sample retained growth >134217728 且 <=268435456 bytes 时，继续执行 block，但必须标记 MEMORY-ALERT-128MIB，并保留在预注册 sensitivity analysis 中，不得选择性删除；
    - sample retained growth >268435456 bytes 时 emergency fail closed，不执行后续样本；
    - 完整两样本 block 的 retained managed-memory net growth hard limit 保持 268435456 bytes；
    - block working-set growth 和 private-memory growth hard limit 均保持 536870912 bytes；
    - full GC boundary、每样本 reset、planner/logger disposal、结构 exact-match、hash/provenance、process identity 和 fail-closed 规则不变。

11. 该变化的理由必须明确为：独立实验单位是一个完整 fresh Unity Williams-block process；128 MiB sample delta 同时包含首次加载/JIT/cache 与潜在泄漏，不能在没有精确 telemetry 的情况下作为唯一 validity 判据；block-level hard gate 和 256 MiB emergency stop 继续防止跨样本污染与失控增长。

12. 不得修改 P1–P5、C1–C5、AB-minus-BA estimand、95% CI、±log(1.10) order-bias diagnostic bound、bootstrap 20,000/seed 13012026、三个场景、32 mirrored pairs/scenario、Williams rows、scenario rotation、AB/BA 配额、算法语义、场景矩阵或排除规则来取得通过。

五、测试和 pre-pilot gates

13. 创建全新 verification root：
    Research/Verification/Gate12R_ProcessReuse_5pct/v9-gate13r-pr1b-order-effect-memory-v2
   如该路径已存在，必须递增版本，不得覆盖。

14. 在创建新 pilot root 前完成 parser、schema、static、unit、Unity compile、telemetry、正向 mirrored block、负向 fail-closed、独立进程重复性、cold structural control、retained regression、hash/provenance 和 validation-only final audit。

15. 测试必须至少覆盖：
    - evaluation 必须先于 threshold decision 持久化；
    - 128 MiB 以下为 PASS；
    - 恰好 128 MiB 不触发 alert；
    - 128 MiB 以上且不超过 256 MiB 为 MEMORY-ALERT-128MIB 并继续；
    - 恰好 256 MiB 不触发 emergency stop；
    - 256 MiB 以上立即 fail closed；
    - 两样本 block net growth 恰好/超过 256 MiB 的边界；
    - working/private 512 MiB 边界；
    - alert sample 后续 position 的 reset/carryover 记录；
    - failure artifact 引用 evaluation hash；
    - missing/non-finite/mixed-PID/partial block 拒绝；
    - attempt 1 和全部冻结上游前后字节不变；
    - formal root 仍不存在。

16. pre-pilot gates 任一失败时允许只对 v2 新建实现做版本化修复和 validation-only retry；不得启动 measured pilot，且每个失败验证 attempt 均须保存独立 receipt、manifest、log、checkpoint 和 hashes。不得通过放宽新冻结 thresholds 或改变研究语义取得通过。

六、一次全新的 NON-FORMAL pilot

17. 只有全部 v2 pre-pilot gates 通过后，才创建全新 pilot root：
    Research/PilotRuns/Gate12R_ProcessReuse_5pct/v6-gate13r-pr1b-order-effect-memory-v2
   如该路径已存在，必须递增版本，不得覆盖。

18. 只允许运行一次完整 fresh pilot：3 个冻结 heterogeneous scenarios、32 mirrored pairs/scenario、96 mirrored pairs、192 AB/BA superblocks、384 measured fresh Unity block processes、768 measured samples，另加冻结的 12 warm-up processes/24 excluded samples；严格串行，最大 Unity 并发 1。

19. pilot 必须标记 NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS。不得复用 attempt 1 的进程、输出或 measured observations。每个 process 只执行一个完整 Williams block，每样本完整 reset。

20. measured 阶段开始后，任一硬门禁失败时立即保存原子 failure receipt、evaluation、checkpoint、partial-output manifest、日志和哈希并停止。禁止自动 retry、resume、top-up 或与 attempt 1/其他 attempt 合并。

21. 只有 v2 pilot 全部完成且 final audit 通过后，才运行冻结的 order-effect analyzer；报告每个场景和 pooled equal-scenario 的 AB-minus-BA、CI、bootstrap、alert/no-alert sensitivity、position/predecessor/process-age/wave 诊断，以及 supplemental heterogeneous pilot 是否足以支持更强的 pilot-level order-effect identifiability。不得据此作正式 superiority 结论。

七、停止边界

22. 本授权不允许创建 Research/FormalRuns/Gate13R_RQAligned/v1，不允许创建 formal execution receipt，不允许启动 Gate 13R timing campaign，不允许启动 Gate 14R，不允许生成 OBS 数据，也不允许修改原始游戏脚本或原始场景。

23. v2 成功后只更新 readiness checkpoint、Overall_Project_Plan 和 Next_Session_Checkpoint，然后停止并向我请求 Gate 13R-PR2 或其他后续工作的单独授权。失败时保存证据后停止。
```
