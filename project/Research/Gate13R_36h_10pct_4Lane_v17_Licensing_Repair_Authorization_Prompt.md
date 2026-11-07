# Gate 13R 36h v17 Licensing-Stability Repair Authorization Prompt

复制以下完整文本作为下一步授权：

```text
授权 Gate 13R 36h / 10% / 4-lane v17 的 Unity licensing-stability 非执行修订、测试和一次 fresh NON-FORMAL pilot；不授权 Gate 13R 正式 campaign。

1. 完整保留 `Research/PilotRuns/Gate13R_36h_10pct_4Lane/v16/`、`Research/Gate13R_36h_10pct_4Lane_v16_Licensing_Failure_Diagnosis.v1.json`、`Research/Gate13R_36h_10pct_4Lane_v16_Failed_Checkpoint.md`、v16 readiness verification、receipt、checkpoint、failure receipt、partial manifest、日志和哈希，不得修改、覆盖、retry、resume、补齐或与后续数据合并。v16 的 316 个完整 measured blocks / 948 samples 及 wave 80 的两个成功 block 永久标记为 `NON-FORMAL / EXCLUDED-FROM-READINESS-AND-FORMAL-ANALYSIS`。

2. 在创建 v17 之前，先只读复核 v16 failure receipt、partial manifest 和诊断哈希。允许在复核通过后永久删除仅用于执行的隔离 clone 根 `H:\DDM_Final_Project_Gate13R36H\v16` 以释放空间；不得删除项目内的 v16 pilot/verification/diagnostic evidence。

3. 为 v17 创建新的 versioned specification、test design、amendment、plan、schedule、provenance、verification root、clone root `H:\DDM_Final_Project_Gate13R36H\v17` 和 fresh pilot root `Research/PilotRuns/Gate13R_36h_10pct_4Lane/v17`。不得覆盖任何 v16 文件或目录；不得创建 formal root 或 formal execution receipt。

4. 研究语义保持不变：完整 74-campaign 矩阵、10% per-campaign 相对 95% CI 半宽、无 hard cap、4 个隔离 Unity Editor lanes、每个 Williams block 一个 fresh Unity Editor process、冻结 Williams 顺序、每样本完整 reset、PSAPI/CIM telemetry、128 MiB per-sample retained managed-memory 与 block-scaled memory rules、Playable 映射、readiness p95 ≤ 27 h、formal end-to-end ≤ 36 h。

5. licensing 修订默认采用“串行 license admission + 同步 workload barrier”：每个 wave 按预注册且跨 lane/algorithm 平衡的轮换顺序启动四个 fresh Unity 进程；每个进程必须先提供可审计的 serial/entitlement-ready 证据，才允许启动下一 lane；四个进程全部 ready 后由原子 barrier 同时释放 planning workload。sample timing 只能在 barrier 释放后开始；readiness 的端到端 wall-clock 必须包含 license admission、启动、barrier、workload 和退出的全部时间。不得用长期存活的第五个 Unity 进程，不得通过降低并发数、复用 sample process、忽略 license 错误或自动重启失败 lane 来取得通过。

6. pilot 前必须通过：Windows PowerShell 5.1 parser/binding、静态/单元、Unity compile、四 lane serial-admission/barrier 正向测试、缺失 serial/entitlement 与 licensing-client channel loss 的负向 fail-closed、锁卫生、独立进程重复性、cold structural exact-match、retained regression、hash/provenance 和 validation-only audit。另运行至少 128 个连续、非测量、四-lane licensing-admission stress waves（至少 512 个 fresh Unity processes），要求 0 个 entitlement/serial failure、0 个自动 retry、0 个遗留 Unity/lock；任一失败即保存证据并停止，不得进入 pilot。

7. 全部非执行门禁通过后，只允许运行一次新的 `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS` v17 pilot：8 warm-up blocks、384 measured Williams blocks / 1,152 measured samples、96 个四-lane waves。任一 measured wave 中任一 lane 失败时 fail closed，保存原子 checkpoint、failure receipt 和 partial manifest 后停止；禁止自动 retry/resume/补齐/partial merge。

8. v17 pilot 完整成功后，才允许运行冻结 analyzer，生成 block-aware variance/correlation、license-admission 开销、并行效率、预算/存储、无 hard cap 候选 `n_formal`、projected readiness p95 与 Playable 映射验证。只有 projected readiness p95 ≤ 27 h 才可标记为 formal-readiness candidate；随后停止并向我请求 Gate 13R 正式 campaign 的单独授权。

9. 不得修改 Gate 10R attempt 4、Gate 11R attempt 2 bundle、Gate 12R 成功 v4/历史归档、旧 5% Gate 13R 证据、原始游戏脚本、原始场景或原始项目归档；不得启动 Gate 14 或 Gate 15-V。
```
