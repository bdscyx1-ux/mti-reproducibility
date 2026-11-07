# Gate14Re-MQ-CFF-IDFF 正式 MQ 分析结果（v1）

## Material Passport

- Origin Skill: experiment-agent + nature-statistics
- Origin Mode: run + validate
- Origin Date: 2026-10-22T04:41:50.753085Z
- Verification Status: ANALYZED
- Version Label: gate14re_mq_formal_analysis_v1
- Authorization ID: gate14re-mq-formal-analysis-attempt-001-b9079a33-6716-4485-a88c-1981edb87afc

## 终局结论边界

本报告只分析已封印的 MQ attempt-003。分析终端 PASS 表示数据完整性与冻结统计流程成功执行，不等同于所有科学假设均通过。未启动 formal ST、MT，未进行算法排名或赢家裁决。

## 冻结设计读出

- 独立分析单位：完整 matched block；每项假设 n=36。
- 技术层级：864 个进程和每进程 16 条 lane 均不被当作独立 n。
- 主族：P1–P4，单侧 one-sample Student t；Holm 强 FWER 0.05。
- 决策区间：P1–P4 使用 Bonferroni 单侧同时上界（族置信度 95%）；S1–S2 在门开启时对应使用二项族上界。
- 实际重要性：点估计必须不高于 log(0.9) 才达到 10% MIPE。

## 主检验与门控 secondary

| ID | 算法 | 拓扑 | 几何比 | 95% 普通区间 | Holm p | Bonferroni 上界（比值） | MIPE | 判定 |
|---|---|---|---:|---:|---:|---:|:---:|---|
| P1 | C-FF | LARGE_L3_CCD | 0.659722 | [0.639353, 0.680739] | 1.109e-24 | 0.684027 | 是 | PASS：统计支持且达到预设 MIPE |
| P2 | C-FF | HIGH_FREQUENCY_CCD | 0.664197 | [0.643934, 0.685097] | 1.109e-24 | 0.688365 | 是 | PASS：统计支持且达到预设 MIPE |
| P3 | IDFF | LARGE_L3_CCD | 0.671454 | [0.651030, 0.692519] | 1.348e-24 | 0.695813 | 是 | PASS：统计支持且达到预设 MIPE |
| P4 | IDFF | HIGH_FREQUENCY_CCD | 0.677528 | [0.657409, 0.698262] | 1.348e-24 | 0.701503 | 是 | PASS：统计支持且达到预设 MIPE |
| S1 | C-FF | DUAL_CCD_BALANCED | 0.803817 | [0.755330, 0.855417] | 1.592e-08 | 0.855417 | 是 | PASS：门控 secondary 统计支持且达到 MIPE |
| S2 | IDFF | DUAL_CCD_BALANCED | 0.839691 | [0.799845, 0.881522] | 1.592e-08 | 0.881522 | 是 | PASS：门控 secondary 统计支持且达到 MIPE |

S1–S2 门状态：OPEN。门控规则只取决于 P1–P4 是否全部经 Holm 拒绝；MIPE 仍逐项决定是否可形成实际重要性 claim。

## 稳健性与审计

- 已执行 100,000 次、固定种子 141420274 的 matched-block studentized bootstrap。
- 已执行 exact conditional one-sample Wilcoxon signed-rank sensitivity 与 leave-one-block-out 影响诊断。
- 稳健性分析不改变冻结 confirmatory 判定。
- 统计谬误扫描覆盖：11/11；复现状态为 ANALYZED（单次正式执行约束下未进行第二次正式数据重跑）。

## 论文使用边界

可据本报告逐项表述 C-FF 与 IDFF 的单 CCD worker-scaling 证据，以及在门开启时的双 CCD W16/W8 secondary 证据。不得将跨算法描述性差异改写为排名、赢家或因果硬件机制结论。
