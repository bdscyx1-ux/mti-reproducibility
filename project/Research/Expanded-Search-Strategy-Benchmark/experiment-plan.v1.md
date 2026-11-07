# Gate13R-AX2 Code Experiment Plan v1

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `plan + non-formal implementation verification`
- Origin Date: `2026-10-16`
- Verification Status: `CORE-READINESS-PASS / FORMAL-EXECUTOR-PENDING`
- Version Label: `gate13r_ax2_code_plan_v1`

## Experiment Overview

- **Title**: Gate13R-AX2: BiA*-R and LPA* versus C-FF and IDFF in frozen shared-goal campaigns
- **Objective**: 在完全相同的 Gate 13R shared-goal 动态规划工作负载中，同期比较两个新增 A* 系算法与 C-FF、IDFF 的 P1，并保留四算法的原始 P1 几何均值。
- **Hypothesis**: 不预设赢家；检验四个冻结的跨族 P1 几何比是否偏离 1。
- **Type**: deterministic Unity simulation / paired algorithm benchmark

## Setup

- **Language/Framework**: Unity `2022.3.30f1c1`, C#, Python 3（结构生成与分析）
- **Current validation command**: `H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe -batchmode -nographics -quit -projectPath H:\DDM_Final_Project -executeMethod DDM.Research.Editor.Gate13RAX2AlgorithmVerificationV1.Run`
- **Formal entry command**: 尚未冻结；必须由下一阶段 readiness 生成
- **Working Directory**: `H:\DDM_Final_Project`
- **Environment**: Windows；每完整 Williams block 使用一个 fresh Unity process

## Inputs

| Input | Path | Description |
|---|---|---|
| Gate 13R schedule source | `Research/Gate13R_Formal_Williams_Block_Schedule.v1.jsonl` | 仅提取 shared-goal campaign 的结构元数据和前 48 个 block ordinal |
| Frozen scenario catalog | `Research/FormalScenarios/Gate11R_5pct/v1/catalog.json` | 53 个冻结场景的目录；AX2 只选 32 个 shared-goal 场景 |
| Frozen scenario matrix | `Research/FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json` | 场景结构、种子和输入 hash |
| Scientific contract | `Research/Gate13R-AX2/Contracts/scientific-contract.v1.md` | 研究问题、样本量和边界 |
| Fairness contract | `Research/Gate13R-AX2/Contracts/four-algorithm-extension-fairness.v1.md` | 成本、状态与同期公平性规则 |

## Expected Outputs

| Output | Path | Format | Success Criterion |
|---|---|---|---|
| Frozen schedule | `Research/Gate13R-AX2/Execution/v1/formal-williams-schedule.v1.jsonl` | JSONL | 1,536 行；32 campaigns × 48 blocks；每位置每算法 384 次 |
| Schedule manifest | `Research/Gate13R-AX2/Execution/v1/formal-williams-schedule-manifest.v1.json` | JSON | 输入 hash、cardinality 与顺序平衡全部匹配 |
| Algorithm correctness | `Research/Verification/Gate13R-AX2/algorithm-correctness-v1/algorithm-correctness.v1.json` | JSON | `passed=true` 且 962 assertions（含原 Gate 10/Gate 13R 注册表与 cohort 不变性检查） |
| Core readiness | `Research/Verification/Gate13R-AX2/core-readiness-v1/core-readiness.v1.json` | JSON | `CORE-READINESS-PASS` |
| Formal raw | 尚未创建 | versioned raw root | 需另行授权并通过 1,536-block 结构 commit |
| P1 analysis | 尚未创建 | JSON + Markdown | 四个 raw GM、四个冻结配对 contrasts、Holm 与同时区间齐全 |

## Monitoring Configuration

- **Formal timeout**: 尚未冻结；由 fresh-process supervisor contract 决定
- **Monitor files**: 待 readiness 阶段定义 `_control/execution-status.json`、failure receipt、acquisition-complete receipt
- **Metric access during acquisition**: 禁止读取 P1 或任何算法结果；只允许结构性进度
- **Metric key after raw freeze**: `dynamicHandlingMillisecondsPerScheduledEvent`

## Analysis Plan

- **Primary metric**: P1，`dynamicHandlingTotalMilliseconds / scheduledEventCount`，单位 `ms/event`
- **Descriptive output**: 每算法基于全部有效样本的原始几何均值及 `eligibleN/missingN`
- **Independent inference unit**: 32 campaigns；每 campaign 内先平均 48 个配对 block log-ratios
- **Primary family**: `BiA*-R/C-FF`、`BiA*-R/IDFF`、`LPA*/C-FF`、`LPA*/IDFF`
- **Multiplicity**: Holm family-wise `α=0.05`；另报 `98.75%` Bonferroni-compatible simultaneous CI
- **No pseudocount**: P1 必须有限且严格大于 0
- **Interpretation**: raw GM 是描述性量；确认性结论来自 campaign-level paired inference

## Authorization Boundary

当前计划与核心实现验证不构成正式采集授权。正式 executor、supervisor、output schema、raw commit 和分析实现完成并得到 final readiness receipt 后，仍须用户对单一正式 attempt 单独授权。

