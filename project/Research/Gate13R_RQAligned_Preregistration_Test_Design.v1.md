# Gate 13R-PR1 非执行测试设计 v1

## 硬门禁

1. 所有新 JSON 可解析，schema/version/identity 完整。
2. Gate 10R v4、Gate 11R bundle、Gate 12R v4 及列出的旧 Gate 13R 文件在前后使用同一 tree/file identity 算法得到相同 SHA-256、文件数和字节数。
3. Gate 11R bundle manifest 必须为 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`。
4. Gate 12R v4 必须为 384 measured blocks、1,152 samples、12 pilot campaigns；所有 run ID 唯一；block 完整；hash chain 通过。
5. P1–P5 原始字段可用性逐字段审计；任何缺字段输出 `INSTRUMENTATION-GAP` 并停止。
6. P5 derived repair count 必须非负且不超过 repairOperationCount；zero-event 必须保留。
7. C1–C5 numerator/denominator、方向与 C5 双侧身份准确；Holm family 恰为五项。
8. 正值连续指标的 ln/back-transform、zero、missing、NaN、Infinity 与 whole-block handling 使用 synthetic fixtures 验证。
9. heterogeneous matching 必须拒绝 different scenario/block/wave、duplicate、partial pair；必须正确计数 AB/BA、adjacency 与 order imbalance。
10. P3 slope 在受控 levels 不足时必须明确 `NOT-ESTIMABLE`。
11. M1–M5 必须无 Gate 12R variance、power 或 n_formal。
12. S/H arithmetic 必须满足授权公式；74 campaigns 不得被删减。
13. 源码静态扫描不得包含 Unity 启动调用；formal root 必须不存在。
14. 核心输出必须在两个隔离临时根确定性再生且 SHA-256 相同。

## Synthetic fixtures

- ln ratio：numerator=2、denominator=4，期望 log ratio=`ln(0.5)`，back-transform=0.5。
- P4：dynamicManagedAllocatedBytes=1024、scheduledEventCount=4，期望 256 bytes/event。
- P5：overall 3/(10+5)=0.2；plan 1/10=0.1；repair (3-1)/5=0.4。
- P5 invalid：budgetExceededOperationCount < budgetExceededPlanCount，必须拒绝。
- zero-event upper bound：0/100 的 one-sided 95% upper=`1-0.05^(1/100)`。
- Holm：raw p `[0.001,0.02,0.03,0.2,0.8]`，adjusted p 必须单调且不小于相应 step-down 值。
- candidate arithmetic：S32/H32 必须为 shared 1,024 processes/4,096 samples，heterogeneous 672 superblocks/1,344 processes/2,688 samples，总计 2,368 processes/6,784 samples。
- mismatched superblock：不同 scenario 或 block ordinal 必须拒绝。
- M1–M5：任何 variance 字段出现即失败。

## Validation-only 顺序

1. parser/schema；2. pre-write hash check；3. Python self-test；4. input hash-chain/observability audit；5. dry-run 到临时根 A；6. dry-run 到临时根 B；7. byte-level deterministic comparison；8.正式非执行分析根生成；9. post-write preservation audit；10. evidence manifest；11. final audit；12. 仅通过后更新计划。

任何硬门禁失败都生成版本化 failure receipt、partial manifest、checkpoint、hash 与诊断。只允许修复本阶段新建的分析/schema/tests；不得启动 Unity、修改 estimand 或放宽门禁。
