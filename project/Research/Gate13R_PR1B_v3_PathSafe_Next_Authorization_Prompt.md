# Copyable next authorization — Gate 13R-PR1B v3 path-safe repair

```text
授权 Gate 13R-PR1B v3「Windows/Mono path-safe atomic persistence 的受控、版本化修复、验证及一次全新的 NON-FORMAL balanced mirrored order-effect pilot」；不授权 Gate 13R 正式 campaign，不授权 Gate 14R。

一、v2 pilot attempt 2 的冻结与排除

1. 以以下文件和根为 v2 pilot attempt 2 的终态依据：
   - Research/Gate13R_PR1B_v2_Pilot_Attempt2_Terminal_Preservation.v1.json；
   - Research/Gate13R_PR1B_v2_Pilot_Attempt2_Failure_Diagnosis.v1.md；
   - Research/Gate13R_PR1B_v2_Failure_Checkpoint.v1.json；
   - Research/PilotRuns/Gate12R_ProcessReuse_5pct/v6-gate13r-pr1b-order-effect-memory-v2/。

2. v6 必须永久保持：
   FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE /
   NON-FORMAL /
   WARMUP-ONLY /
   NO-MEASURED-OBSERVATIONS /
   EXCLUDED-FROM-FORMAL-ANALYSIS /
   EXCLUDED-FROM-ORDER-EFFECT-INFERENCE。

3. 不得修改、覆盖、删除、重命名、补齐、resume、top-up、合并或重新解释 v6。其一个完整 warm-up block 和一个部分 warm-up block只允许用于失败诊断与 provenance，不得用于 order-effect、algorithm-effect、方差、样本量或正式推断。

4. 完整保留 Gate 13R-PR1B v2 的 v9、v10、v11 verification roots、全部 receipt、manifest、checkpoint、日志、哈希和新增 v2 文件；继续完整保留 Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R v4、Gate 13R-PR1、历史 roots、原始脚本、原始场景和原始项目归档。

二、受控 stale-lock 恢复

5. 在任何 Unity 启动或 lock 删除前，只读核验并记录：
   - 没有指向 H:/DDM_Final_Project 的 Unity.exe 进程；
   - H:/DDM_Final_Project/Temp/UnityLockfile 与 v6 quiescence-failure receipt 中的精确路径一致；
   - 它是非 reparse-point 的零字节普通文件；
   - SHA-256 为 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855；
   - 可被独占读写打开；
   - v6 failure receipt、checkpoint、partial manifest、block failure、quiescence failure 和 terminal preservation 的哈希一致。

6. 仅在全部条件通过后，授权删除这个精确 lockfile。删除前后创建独立、原子、版本化 recovery receipt。不得删除 Temp 目录或其他文件；任一条件不满足立即停止。

三、v3 path-safe atomic persistence 修复

7. 不得修改冻结的 Gate13RPR1BMemoryAwareProcessReuseBatchCommandV2.cs、Gate12RProcessReuseBatchCommandV3.cs 或 v2 wrappers。必须创建新的 versioned v3 Unity command、wrapper、specification amendment、test design、config 和 provenance。

8. 根因冻结为：v6 warm-up position 2 的 IDFF evaluation 临时路径恰好 260 字符，而 C-FF 对应路径为 259 字符；Unity/Mono 的 System.IO.File.WriteAllText 对 260 字符路径抛出 DirectoryNotFoundException。这是持久化实现缺陷，不是算法、场景、内存阈值或统计合同失败。

9. 新的原子写入 helper 必须：
   - 在最终文件所在且已验证存在的同一目录内使用短临时文件名，例如 `.g13tmp-<GUID>`，不得再使用 `<final-name>.tmp-<GUID>`；
   - 保持同卷原子 move/replace；
   - 在写入前验证最终父目录、containment、reparse-point 和路径身份；
   - 遇到临时文件碰撞、写入失败或 move 失败时 fail closed，并尽最大可能清理仅由当前调用创建的临时文件；
   - 不得覆盖既有正式 evidence；
   - 保持 evaluation 在任何 threshold decision 之前持久化；
   - failure、block-failure 和 checkpoint 继续引用 evaluation 路径与 SHA-256；
   - 不改变 UTF-8、稳定序列化、哈希、telemetry、reset 或原子 checkpoint 语义。

10. memory policy 保持完全不变：128 MiB sample alert、256 MiB sample emergency stop、256 MiB complete two-sample block managed hard limit、512 MiB block working/private hard limits；精确阈值通过。不得放宽门禁来取得通过。

11. P1–P5、C1–C5、AB-minus-BA、95% CI、±log(1.10)、bootstrap 20,000/seed 13012026、3 个场景、32 mirrored pairs/scenario、Williams rows、scenario rotation、AB/BA 配额、算法语义、矩阵、排除规则和一个 fresh Unity process/完整 block 均保持不变。

四、v3 测试与 pre-pilot gates

12. 创建全新 verification root，建议：
    Research/Verification/Gate12R_ProcessReuse_5pct/v12-gate13r-pr1b-order-effect-pathsafe-v3
    如已存在必须递增版本，不得覆盖。

13. 新测试至少覆盖：
    - v6 实际失败路径的确定性重现，旧 helper 预期失败、新 helper 成功；
    - 259、260、261 及更长最终/临时路径边界；
    - C-FF 和 IDFF position 路径；
    - 父目录缺失、越界、reparse-point、碰撞、写失败和 move 失败；
    - 临时文件只在同一最终目录生成且名称长度有固定上界；
    - evaluation-before-decision；
    - 12 个 memory threshold fixtures 和 8 个 telemetry fixtures；
    - 正向 mirrored block、负向 fail-closed、独立进程重复性、cold structural control、retained 63/63 regression；
    - v5、v6、v9、v10、v11 及全部冻结上游前后 SHA-256/树哈希不变；
    - formal root 仍不存在。

14. 只有 parser、schema、static、unit、Unity compile、path-boundary self-test、telemetry、正负 block、重复性、cold structural control、retained regression、hash/provenance 和 validation-only final audit 全部通过，才允许创建新 pilot root。

15. pre-pilot 失败时允许仅对新建 v3 实现做版本化修复与 validation-only retry；每个失败 verification attempt 独立保存 receipt、manifest、log、checkpoint 和 hashes。不得启动 pilot、不得修改冻结输入或改变研究语义。

五、一次全新的 NON-FORMAL pilot

16. pre-pilot 全部通过后，才创建全新 pilot root，建议：
    Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v3
    不得使用、继续或合并 v6；如 v7 已存在必须递增版本。

17. 只运行一次完整 fresh pilot：12 warm-up processes/24 excluded samples，加 3 个冻结 heterogeneous scenarios × 32 mirrored pairs/scenario = 96 mirrored pairs、192 AB/BA superblocks、384 measured fresh Unity block processes、768 measured samples；严格串行，最大 Unity 并发 1。

18. 新 pilot root 创建后任一失败均立即保存原子 failure receipt、evaluation、checkpoint、partial-output manifest、日志和哈希并停止。禁止自动 retry、resume、top-up 或与任何历史 attempt 合并。

19. 只有新 pilot 全部完成并通过 final audit 后，才运行冻结的 order-effect analyzer；报告 scenario 与 pooled equal-scenario AB-minus-BA、CI、bootstrap、alert/no-alert sensitivity、position/predecessor/process-age/wave 诊断和 pilot-level order-effect identifiability verdict。不得据此作正式 superiority 结论。

六、停止边界

20. 本授权不允许创建 Research/FormalRuns/Gate13R_RQAligned/v1，不允许 formal execution receipt，不允许 Gate 13R timing campaign，不允许 Gate 14R，不允许 OBS 数据，也不允许修改原始游戏脚本或原始场景。

21. 成功后只更新 readiness checkpoint、Overall_Project_Plan 和 Next_Session_Checkpoint，然后停止并向我请求 Gate 13R-PR2 或其他后续工作的单独授权。失败时保存证据后停止。
```
