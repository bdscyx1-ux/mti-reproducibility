# Gate 13R-PR2-MP2 non-executing memory-policy amendment authorization prompt

复制以下正文作为下一条授权消息：

---

授权 Gate 13R-PR2-MP2「前瞻性分层、场景规模感知 memory-policy 冻结，formal attempt 3 非执行配置/adapter 实现与 validation-only readiness」。严格以 `Research/Gate13R_PR2_MP1_v2_Readiness_Checkpoint.v1.json`、`Research/Gate13R_PR2_MP1_v2_Memory_Policy_Recommendation.v1.json` 和冻结的 MP1 v2 raw/analysis 为活动上游。本授权不授权 Gate 13R-PR2 formal attempt 3 measured campaign，不授权创建 formal attempt-3 output root 或 formal execution receipt，不授权正式统计分析，不授权 Gate 14R。

## 一、冻结输入与不变性

1. 完整保留并保持字节不变：

   - `Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v2`，Phase A 身份为 3,360 raw files / 2,607,785,161 bytes / raw canonical tree SHA-256 `13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`；
   - `Research/Analysis/Gate13R_PR2_MP1/v2/attempt-1`；
   - MP1 v2 pre-pilot attempts、measured execution receipt/checkpoint、raw-freeze receipt/manifests、analysis attempt 1、post-pilot audit attempts 和 readiness；
   - pilot v1 的 5 files / 5,247 bytes / tree SHA-256 `a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265`；
   - formal attempt 2 的 28,020 files / 8,536,611,302 bytes / tree SHA-256 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`；
   - Gate 10R/11R/12R/PR1/PR1B/PR2/FD1 全部冻结证据，原始游戏脚本、原始场景和原始项目归档。

2. 在任何新写入前，对上述根和关键文件执行只读 SHA-256、file-count、byte-count、read-only、raw-tree/analysis-manifest 自洽性和 formal-attempt-3 absence 审计。不得修改、覆盖、resume、top-up、merge 或重新解释任何失败/非正式 observation。

3. MP1 v2 只能作为 `NON-FORMAL / PILOT-INFORMED / MEMORY-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS` 的前瞻性 policy 设计依据；不得把它并入 future formal data 或用于算法 superiority、P1-P5 formal effect、正式样本量或 Gate 14R 推断。

## 二、前瞻冻结推荐 policy

4. 在查看任何 future formal observation 之前，将以下 policy 冻结为一个新的 versioned formal-attempt-3 candidate contract：

   - native residency metric：每个 completed sample boundary 和 post-block boundary 上，`max(working-set delta, private-memory delta)` 相对于冻结的 block/project baseline；
   - canonical max grid dimension `<=128`：512 MiB advisory envelope，640 MiB hard eligibility ceiling；
   - canonical max grid dimension `==256`：640 MiB advisory envelope，768 MiB hard eligibility ceiling；
   - 未映射或歧义 grid dimension：在 measured launch 前 fail configuration；
   - advisory crossing：完整记录但不停止；
   - hard ceiling crossing：先持久化精确 boundary/identity/reason，再在下一个 block 前 fail closed；
   - raw-after-workload transient crossing 只作诊断，除非独立 host-emergency gate 失败；
   - crossing 是 whole-block/process eligibility event，不得因 final-position enforcement 归因于该位置算法；
   - retained-managed 规则继续为 after-forced-cleanup 128 MiB alert、256 MiB sample/block emergency hard failure；
   - host-safety 继续为 4 GiB absolute native、2 GiB relative native growth、8 GiB available-memory floor，以及 telemetry overflow/unverifiable sustained growth fail closed；
   - failure precedence、lock hygiene、one fresh Unity process per complete Williams block、reset、correctness、telemetry、two-stage raw/analysis commit 和 no-auto-retry/resume/top-up/merge 保持不变。

5. 不得根据 validation 结果自适应放宽上述阈值。若实现证据表明该 policy 无法可靠映射或存在新的科学可识别性问题，应 fail closed 并等待用户决策，不得换成更宽松阈值求通过。

## 三、非执行实现与配置

6. 创建全新的 versioned MP2 specification、test design、policy registry/amendment、scenario-policy mapping manifest、formal config amendment、execution adapter/wrapper、schema、provenance、checkpoint 和独立 validation root。不得覆盖 active PR2 v2 config/schedule 或任何历史文件。

7. 保持正式设计不变：完整 74-campaign S48/H48、3,552 fresh Unity block processes、10,176 algorithm samples、strict serial、one block maximum per Unity process、shared C1-C5/P1 confirmatory contract、heterogeneous secondary matched-superblocks、AB/BA 24/24、Williams 顺序、deterministic identities 和 two-stage commit 均不得改变。

8. 正式 schedule 的 record/order/run identity 必须与 active PR2 v2 schedule 确定性一致；policy mapping 只能作为 versioned prospective overlay。不得创建新 formal output root、formal receipt 或 measured sample。

9. 对全部 53 canonical scenarios / 74 campaigns / 3,552 block-process records生成并验证唯一 policy tier；至少证明每个 scenario 的 grid dimension、advisory threshold、hard threshold、managed thresholds 和 host-safety contract 都可追溯到 canonical source hash。

## 四、测试与 validation-only 门禁

10. 在 readiness 通过前，至少完成：

   - JSON/schema/parser 和 PowerShell 7 / native Windows PowerShell 5.1 binding；
   - deterministic scenario-policy mapping regeneration；
   - exact threshold fixtures：低于、等于、超过 advisory/hard ceiling；
   - `<=128` 与 `==256` 两个 tier；
   - unknown/ambiguous scenario mapping fail closed；
   - raw transient crossing 与 after-cleanup retained crossing 分离；
   - managed 128/256 MiB 规则；
   - 4 GiB/2 GiB/8 GiB host-emergency precedence；
   - final-position attribution rejection；
   - positive complete block、expected-negative hard-ceiling block、telemetry failure、persistence failure和lock-hygiene fixtures；
   - formal schedule/config cardinality、Williams、matched-superblock 与 AB/BA 不变性；
   - Phase-A raw commit / Phase-B read-only analysis state-machine；
   - MP1 v1、MP1 v2 raw/analysis、formal attempt 2 和所有 active upstream 前后 hash/byte 不变性；
   - formal attempt-3 root/receipt 始终不存在。

11. 允许启动仅用于 compile/self-test、synthetic fixture 和 validation-only block 的隔离 Unity Editor 进程；这些输出必须写入独立 verification root，标记 `VALIDATION-ONLY / NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`，不得写入任何 formal root 或作为实验 observation。

12. 允许对本阶段新建且尚未启动 formal measured campaign 的 MP2 实现/schema/test 缺陷进行 versioned 自动修复和 validation-only retry；每个失败 attempt 必须保留独立 receipt、log、manifest、checkpoint 和 hashes。不得通过修改冻结阈值、矩阵、schedule、算法、reset、correctness、telemetry 或 two-stage 语义取得通过。

## 五、成功与停止

13. 全部门禁通过后，只生成 MP2 non-executing readiness checkpoint、candidate formal config/adapter/provenance、验证证据、更新后的 Overall Project Plan/Next Session Checkpoint，以及 Gate 13R-PR2 formal attempt 3 的独立下一授权提示词。

14. 完成后立即停止。不得创建 `Research/FormalRuns/Gate13R_RQAligned_S48H48/v3`，不得创建 formal attempt-3 execution receipt，不得运行任何 formal measured block，不得运行正式统计分析或 Gate 14R。

15. 任一硬门禁失败时原子保存失败 receipt、partial manifest、checkpoint、日志和 hashes 后停止；不得跳过失败门禁进入 formal execution。

本授权明确不授权 pilot v1/v2 retry、resume、top-up 或 merge，不授权 Gate 13R-PR2 formal attempt 3 measured campaign，不授权 formal output root/receipt，不授权正式统计分析，不授权 Gate 14R，也不授权依据 NON-FORMAL pilot 宣布算法 superiority。

---
