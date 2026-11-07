# Copyable next authorization — Gate 13R-PR1B v4 composite process-identity analysis recovery

```text
授权 Gate 13R-PR1B v4「复合进程身份的非执行分析修复、验证，以及对已冻结完整 v3 pilot 的一次独立只读 analysis recovery」；不授权任何新的 Unity Editor 运行，不授权 pilot retry/resume/top-up/merge，不授权 Gate 13R 正式 campaign，不授权 Gate 14R。

一、冻结失败 attempt

1. 以以下文件和根为 Gate 13R-PR1B v3 path-safe pilot 的终态依据：
   - Research/Gate13R_PR1B_v3_PathSafe_Pilot_Terminal_Preservation.v1.json；
   - Research/Gate13R_PR1B_v3_PathSafe_Pilot_Failure_Diagnosis.v1.md；
   - Research/Gate13R_PR1B_v3_PathSafe_Pilot_Failure_Checkpoint.v1.json；
   - Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4/；
   - 上述 pilot root 的 canonical tree SHA-256：
     4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed。

2. v7 pilot root 必须永久保持：
   FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE /
   NON-FORMAL /
   COMPLETE-RAW-EXECUTION /
   POST-EXECUTION-ANALYZER-FAILED /
   EXCLUDED-FROM-FORMAL-ANALYSIS。

3. 不得修改、覆盖、删除、重命名、resume、top-up、合并或在 v7 root 内写入任何修复后的 analysis、manifest、receipt 或 checkpoint。不得把 v7 原 checkpoint 改为 passed，不得把 v7 重新解释为一次成功 pilot。

4. 完整保留 Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R v4、Gate 13R-PR1、PR1B v1-v3、v6 failure root、verification v9-v17、全部 receipt/manifest/checkpoint/log/hash、原始脚本、原始场景和原始项目归档。

二、冻结根因和允许的修复

5. 根因冻结为：冻结的 v1 analyzer 将 numeric Windows PID 当作整次约两小时运行期间的全局唯一进程身份；Windows 在前一进程退出后合法复用了 PID。396 个完成的 Unity process records 只有 375 个 distinct PID values，但 `(processId, processStartTimeUtc, blockId)` 有 396 个唯一值，19 个 PID-reuse groups 均无 lifetime overlap。

6. 只允许新建 versioned analyzer、schema、test design、analysis-recovery orchestrator、provenance 和独立 analysis output root。不得修改冻结的 Analyze-Gate13RPR1BOrderEffectPilotV1.py、V2.py、V3.py、V4.py 或任何既有 wrapper。

7. 新正式定义必须区分：
   - OS process identity key：`(processId, processStartTimeUtc)`；
   - block evidence identity key：`(processId, processStartTimeUtc, blockId)`；
   - numeric PID 单独重复在前一同 PID process 已结束时是合法 OS PID reuse；
   - 相同 OS process identity 重复、同 PID lifetime overlap、缺失/不可解析 start time、sample PID 与 block PID 不一致、一个 process identity 映射多个 block、或一个 block 映射多个 process identity 必须 fail closed。

8. 保持 P1-P5、C1-C5、AB-minus-BA、95% CI、±log(1.10)、bootstrap 20,000/seed 13012026、3 场景、32 mirrored pairs/scenario、Williams rows、scenario rotation、AB/BA 配额、算法语义、memory policy、排除规则和一个 fresh Unity process/完整 block 的研究语义完全不变。

三、validation-only 测试

9. 在读取真实 pilot 数值用于分析前，先冻结并哈希：
   - composite process-identity specification；
   - analysis-recovery specification；
   - test design；
   - schema；
   - synthetic fixture expected outputs；
   - provenance；
   - v7 pre-read preservation audit。

10. 测试至少覆盖：
    - legal sequential reuse of one PID with different start times；
    - illegal overlapping lifetimes for one reused PID；
    - duplicate `(PID,startTime)`；
    - duplicate `(PID,startTime,blockId)`；
    - one process identity mapped to multiple blocks；
    - one block mapped to multiple process identities；
    - missing, non-UTC, malformed, future, or impossible processStartTimeUtc；
    - sample/block PID mismatch；
    - duplicate run ID and schedule key；
    - all 396 composite identities and 768 measured run IDs unique；
    - complete hashes, completion, memory, reset, scenario and Williams gates；
    - deterministic 20,000-replicate bootstrap regeneration；
    - output isolation and proof of zero writes to v7；
    - zero Unity invocation；
    - formal root absence；
    - v7 and all frozen roots before/after tree-hash equality。

11. 允许仅对本阶段新建的非执行 analyzer、tests、schema 和 recovery orchestrator 做版本化自动修复与 validation-only retry。每个失败 verification attempt 必须保存独立 receipt、manifest、log、checkpoint 和 hash。不得根据结果方向改变 estimand、阈值、排除规则或统计合同。

四、一次只读 analysis recovery

12. 只有全部静态、单元、synthetic fixture、schema、hash/provenance、output-isolation、no-Unity 和 validation-only final audit 通过后，才允许对冻结 v7 root 进行一次只读 analysis recovery。

13. recovery 必须：
    - 从 v7 只读加载 12 warm-up/24 excluded samples 和 384 measured processes/768 measured samples；
    - 不启动 Unity，不生成或补充任何实验样本；
    - 不修改 v7 内任何字节；
    - 只把新 analysis、manifest、receipt、log、hash 和 checkpoint 写入独立 versioned root，例如：
      Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1/；
    - 明确标记 ANALYSIS-RECOVERY-FROM-COMPLETE-FAILED-NONFORMAL-PILOT /
      PILOT-DIAGNOSTIC-ONLY /
      EXCLUDED-FROM-FORMAL-ANALYSIS；
    - 报告 scenario 与 pooled equal-scenario AB-minus-BA、95% CI、20,000 whole-mirrored-pair bootstrap、alert/no-alert sensitivity、position/predecessor/process-age/wave 诊断和 pilot-level order-effect identifiability verdict；
    - 不得作 Gate 13R 正式 superiority 结论。

14. recovery 执行失败时原子保存独立 failure receipt、partial manifest、log、hash 和 checkpoint 后停止；禁止自动重跑 recovery，禁止退回去重跑 Unity pilot。

五、停止边界

15. 本授权不允许创建或修改 Research/FormalRuns/Gate13R_RQAligned/v1，不允许 formal execution receipt，不允许 Gate 13R timing campaign，不允许 Gate 14R，不允许 OBS 数据，不允许修改原始游戏脚本或原始场景。

16. 成功后仅生成独立 recovery readiness/checkpoint、更新 Overall_Project_Plan 和 Next_Session_Checkpoint，然后停止并向我请求 Gate 13R-PR2 或其他后续工作的单独授权。失败时保存证据后停止。
```
