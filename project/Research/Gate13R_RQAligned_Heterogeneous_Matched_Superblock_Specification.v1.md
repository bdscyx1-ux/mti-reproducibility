# Gate 13R-PR1 Heterogeneous Matched-Superblock 规格 v1

## 正式 prospective 身份

一个 matched superblock 必须同时满足：

1. 相同 canonical heterogeneous scenario ID 与 scenario source hash；
2. 相同 repetition ordinal 与 deterministic input identity；
3. 一个全新的 per-agent A*-R/D*L Williams-block Unity process；
4. 一个全新的 grouped-field C-FF/IDFF Williams-block Unity process；
5. 两个 processes 均只执行各自一个完整 block；
6. 独立 superblock ID、manifest、hash、checkpoint 与 provenance；
7. cohort-process order 使用 AB/BA，配额相等或最多相差 1；
8. H 为偶数并优先为 4 的倍数；
9. 两个 blocks 位于同一受控 run wave，记录温度/电源/时间漂移；
10. 任一 block 失败时整个 superblock 不完整、fail closed，不继续解释为 paired evidence。

## 因果解释边界

C1–C4 比较 grouped-field system 与 per-agent system 的联合 treatment。它们同时改变 planner ownership、goal representation、算法实现与 process position，不能被写成“只由算法名称造成”的 pure algorithm effect。

IDFF/C-FF 可在 grouped-field block 内 paired；D*L/A*-R 可在 per-agent block 内 paired diagnostic。这两种 within-family pair 不消除 cross-family system 差异。

## Gate 12R v4 retrospective audit

只允许用 `(scenarioId, block ordinal)` 建立 candidate pairs，并验证 scenario hash、wave、execution ordinal、wave slot 与 process order。已知预期是 3 scenarios × 32 ordinals = 96 pairs，全部 same-wave；89 个相邻且为 per-agent→grouped-field，7 个为 grouped-field→per-agent、跨 11 个 slots。

如果复核成立，身份固定为：

`MATCHABLE-BY-SCENARIO-AND-BLOCK / SAME-WAVE / ORDER-IMBALANCED / NOT-ABBA-BALANCED / PILOT-DESCRIPTIVE-ONLY-FOR-CROSS-FAMILY-MEAN`。

允许输出 descriptive paired variance、conservative variance upper bound、cohort-order sensitivity、adjacent-only sensitivity、process/wave sensitivity及 H=32/40/48 规划区间。禁止输出 formal superiority、unbiased cross-family treatment effect 或 pure algorithm effect。

## Supplemental pilot verdict

三种合法 verdict：

- `SUPPLEMENTAL-HETERO-PILOT-RECOMMENDED`：order strata 差异或 adjacency sensitivity 大，现有 variance 对 H 决策不稳定；
- `SUPPLEMENTAL-PILOT-NOT-REQUIRED-FOR-SECONDARY-DESCRIPTIVE-CLAIM`：目标仅为 secondary descriptive，且 sensitivity 稳定；
- `INSUFFICIENT-EVIDENCE-FOR-DECISION`：反向 order 仅 7 对，无法可靠区分 order 与 scenario/wave 影响。

为避免依据效应方向作决定，默认判据只看：反向 order cluster 数是否至少 16、order-stratum log-ratio difference 的不确定性、adjacent-only 与全体 sigma upper 比值、candidate H projection 的稳定性。本阶段不得运行 supplemental pilot。
