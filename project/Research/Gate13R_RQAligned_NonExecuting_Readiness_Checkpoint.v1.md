# Gate 13R-PR1 非执行 Readiness Checkpoint v1

状态：`PREREGISTRATION-AMENDMENT-VALIDATED / SHARED-PRIMARY-FROZEN / HETEROGENEOUS-SECONDARY-FROZEN / GATE12R-PILOT-REANALYZED / HETERO-ORDER-IMBALANCE-AUDITED / FORMAL-SAMPLE-DESIGN-UNFROZEN / GATE13R-FORMAL-NOT-AUTHORIZED`

## 已完成

- P1 作为唯一 confirmatory primary；P2–P5 为 supportive；M1–M5 仅为 prospective Gate 14R。
- shared-goal C1–C5 是唯一 primary family，FWER 0.05，Holm；C5 双侧。
- heterogeneous 保留完整矩阵，但解释为 secondary system/treatment，而非 pure algorithm effect。
- Gate 12R v4 只读核验了 384 blocks、1,152 samples、1,152 unique run IDs、384 unique process identities；P1–P5 均有合法字段。
- P5 的 1,152 个样本全部为零 overrun；零事件已保留，样本量判定为 `NOT-ESTIMABLE-FROM-ZERO-EVENT-PILOT`，未添加 pseudocount。
- P3 per-agent metric 可估计；agent-count scaling slope 因受控 levels 不足而 `NOT-ESTIMABLE-FROM-GATE12R-V4`。
- M1–M5 没有从 Gate 12R 虚构方差、power 或 n。
- 96/96 heterogeneous candidate pairs 可按 scenario/block 匹配并同 wave；89 adjacent，顺序 89:7，故只允许 descriptive paired variance/order sensitivity。
- 两个隔离分析根逐字节一致；final audit 66/66 通过。

## 候选规模

| 候选 | Unity processes | samples | p50 h | conservative p95 h | 1.5× storage safety |
|---|---:|---:|---:|---:|---:|
| S32/H32 | 2,368 | 6,784 | 13.87 | 17.64 | 9,631,912,320 B |
| S40/H32 | 2,624 | 7,808 | 15.74 | 20.16 | 11,678,959,872 B |
| S48/H32 | 2,880 | 8,832 | 17.61 | 22.68 | 13,726,007,424 B |
| S40/H40 | 2,960 | 8,480 | 17.34 | 22.05 | 12,039,890,400 B |
| S48/H40 | 3,216 | 9,504 | 19.21 | 24.57 | 14,086,937,952 B |
| S48/H48 | 3,552 | 10,176 | 20.81 | 26.46 | 14,447,868,480 B |
| 旧 144/204/108 | 11,160 | 31,536 | 64.83 | 83.90 | 43,885,575,792 B |

所有新行都是 `CANDIDATE / UNFROZEN / NOT-AUTHORIZED-FOR-LAUNCH`。旧行是 pre-amendment comparison baseline，不得启动。

## 推荐但未冻结

推荐将 `S48/H32` 交给用户决策：它把更多预算放到唯一 primary scope，同时以 H32 保留 secondary heterogeneous；完整 74-campaign 矩阵、Williams balance 和 prospective AB/BA 都不删减；p95 22.68 h 低于此前 36 h 规划边界。启动时仍需 40 GiB reserve，最低空闲原始字节约 `56,675,680,384`。

关键限制：在 10% assumed true effect 规划情景下，S32–S48 没有一个让五 contrasts 全部达到 80% Holm-worst-threshold power，C2 是限制项；在 15% assumed effect 下，S48 的限制项 C2 约为 81%。15% 目前只是规划情景，不是“至少改善 15%”的正式结论阈值。

## 下一步必须由用户决定

1. 保持 statistical superiority 阈值为 ratio 1、将 15% 仅作为设计 effect scenario，还是冻结非零 practical-superiority margin；
2. 是否冻结 S48/H32；
3. heterogeneous 是否维持 secondary descriptive、无需 supplemental pilot，还是先运行一个 AB/BA-balanced supplemental pilot。

本 checkpoint 不授权创建新 formal config/schedule/root/receipt，不授权 Unity，不授权 Gate 13R formal campaign，也不授权 Gate 14R。
