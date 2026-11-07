# Gate 13R-PR1B v4 Composite Process Identity Recovery — Readiness Checkpoint

状态：`COMPOSITE-PROCESS-IDENTITY-VALIDATED / READ-ONLY-ANALYSIS-RECOVERY-COMPLETE / PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-SAMPLE-DESIGN-UNFROZEN / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

保存时间：2026-10-08 23:49:28（Asia/Shanghai）

## 1. 本阶段结论

Gate 13R-PR1B v4 已完成授权范围内的非执行修复、validation-only 验证和一次独立只读 analysis recovery。没有启动 Unity Editor，没有生成新样本，没有 retry/resume/top-up/merge pilot，也没有创建正式输出根或正式 execution receipt。

冻结 v3 pilot 根 `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4` 仍然是失败证据，身份保持：

`FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / NON-FORMAL / COMPLETE-RAW-EXECUTION / POST-EXECUTION-ANALYZER-FAILED / EXCLUDED-FROM-FORMAL-ANALYSIS`

analysis recovery 的成功不把该 pilot 改写为“通过的 pilot”，也不允许把 recovered result 用于正式 superiority inference。

## 2. 复合进程身份修复

冻结 v1 analyzer 错把 numeric Windows PID 当作整个约两小时 pilot 的全局唯一身份。v4 正式区分：

- OS process identity：`(processId, processStartTimeUtc)`；
- block evidence identity：`(processId, processStartTimeUtc, blockId)`；
- PID 只有在前一个同 PID process 已结束后才能合法复用；
- 相同 OS identity 重复、相同 PID 生命周期重叠、无效 start time、sample/block PID 不一致、one-process-to-many-block 或 one-block-to-many-process 均 fail closed。

真实证据中共有 396 个完成的 process records、375 个 numeric PID、19 个 PID reuse groups，最大 multiplicity 为 3；没有 lifetime overlap。396/396 OS identities 与 396/396 block evidence identities 均唯一。

validation v2 通过 `23/23` checks，包括 synthetic `17/17`、固定 seed 的 20,000-replicate bootstrap 确定性、768/768 measured run IDs、77/77 source provenance、15/15 stage provenance、原子 JSON round-trip、零 Unity 和冻结根前后不变性。

## 3. 唯一 recovery 的数据边界

只读 recovery 使用冻结根内已经完整产生的：

- 12 个 warm-up fresh processes / 24 个 excluded samples；
- 96 个 measured mirrored AB/BA pairs；
- 192 个 measured matched superblocks；
- 384 个 measured fresh Unity block processes；
- 768 个 measured algorithm samples。

recovery 只把新结果写入 `Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1/`。该根为 8 文件、116,998 raw bytes，canonical tree SHA-256 为 `70f4f10c3ccd4f4428284c946f233e97cd2052408d74b4c72f24055f3f6c06bd`。

## 4. Order-effect 结果

冻结 estimand 为 `AB_LOG_SYSTEM_RATIO_MINUS_BA_LOG_SYSTEM_RATIO`，95% CI，界限为 `±log(1.10)`，bootstrap 为完整 mirrored pair 单位的 20,000 次重采样、seed `13012026`。

P1 的 12 个 scenario rows 与 4 个 equal-scenario pooled rows 合计 16 个单元：

| 分类 | 数量 |
|---|---:|
| `ORDER-EFFECT-BOUNDED` | 9 |
| `DETECTABLE-BUT-BELOW-BOUND` | 2 |
| `INCONCLUSIVE` | 5 |
| `MATERIAL-ORDER-EFFECT` | 0 |

Pooled P1 结果：

| Contrast | Multiplicative order effect | t 95% CI | Bootstrap 95% CI | 分类 |
|---|---:|---:|---:|---|
| C1 | 1.05169 | [0.99517, 1.11142] | [0.99882, 1.10964] | `INCONCLUSIVE` |
| C2 | 1.00903 | [0.94479, 1.07764] | [0.94821, 1.07862] | `ORDER-EFFECT-BOUNDED` |
| C3 | 1.02052 | [0.96460, 1.07967] | [0.96525, 1.07708] | `ORDER-EFFECT-BOUNDED` |
| C4 | 0.97912 | [0.90969, 1.05385] | [0.91553, 1.05589] | `ORDER-EFFECT-BOUNDED` |

结论是 `PILOT-LEVEL-ORDER-EFFECT-IDENTIFIABLE / SOME-CELLS-INCONCLUSIVE`。这些数值衡量的是 AB/BA 执行顺序效应，不是 C-FF、IDFF、A*-R 或 D*L 的 superiority effect；不得用其宣布算法优胜。

768 个 measured samples 中没有 managed-memory alert。P5 没有 budget-overrun event，状态是 `ZERO-EVENT / ORDER-RATIO-NOT-ESTIMABLE`，没有使用 pseudocount。

## 5. 候选设计影响

shared 候选保持 `S48`。由于 P1 仍有 5 个 scenario/pooled 单元不确定，recovery 推荐 heterogeneous 候选提升为 `H48`。这不是自动冻结的 formal design，必须由 Gate 13R-PR2 的独立用户授权作出选择。

推荐但未冻结的 `S48/H48` 候选为：

- 1,536 shared processes / 6,144 shared samples；
- 1,008 heterogeneous matched superblocks；
- 2,016 heterogeneous processes / 4,032 heterogeneous samples；
- 合计 3,552 fresh block processes / 10,176 samples；
- 每个 heterogeneous scenario 的 AB/BA 配额为 24/24；
- serial p50 约 `20.8082 h`；
- conservative summed-p95 约 `26.4554 h`；
- projected p95 raw storage 9,631,912,320 bytes；
- 1.5× safety storage 14,447,868,480 bytes；
- 加 40 GiB reserve 后最低空闲量 57,397,541,440 bytes。

状态：`CANDIDATE / UNFROZEN / NOT-AUTHORIZED-FOR-LAUNCH`。

## 6. 不变性与证据

- 冻结 v7 pilot：9,118 files / 253,513,394 bytes / tree SHA-256 `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`；
- validation v1 失败证据：8 files / 327,250 bytes / tree SHA-256 `1e66f43d80887cd30dc5b33652b599763fad25c15e84d1c329504430f6d0f4e3`；
- validation v2 通过证据：10 files / 330,936 bytes / tree SHA-256 `39721807d3e708b02831e4468b45f570288a8193059df97602bcb2cfd6039231`；
- recovery root：8 files / 116,998 bytes / tree SHA-256 `70f4f10c3ccd4f4428284c946f233e97cd2052408d74b4c72f24055f3f6c06bd`；
- recovered analysis SHA-256 `da58006ab03e9166c31c82489d7ae7bd8024b362a6b9da08878a05453609fee0`；
- recovery receipt SHA-256 `e48adbfbe6acf4dc2d35c73d117f7179444bcab420edc423c3189304eb4f7096`。

## 7. 停止边界

下一步必须是用户单独授权的 Gate 13R-PR2 或其他工作。本 checkpoint 不授权：

- Gate 13R formal campaign；
- Gate 14R；
- Unity Editor 运行；
- pilot retry/resume/top-up/merge；
- formal root 或 formal execution receipt；
- 将 recovered order-effect diagnostics 解释为正式 algorithm superiority。

推荐的、可复制但尚未获授权的 PR2 文本位于 `Research/Gate13R_PR1B_v4_Next_Authorization_Prompt.md`。
