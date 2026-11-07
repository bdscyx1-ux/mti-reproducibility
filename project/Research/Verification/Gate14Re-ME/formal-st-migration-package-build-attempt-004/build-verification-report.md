# Gate14Re-ME Formal ST v5 端到端迁移包 attempt-004 构建验证报告

## 终局

PASS_END_TO_END_MIGRATION_PACKAGE_BUILT_AND_ALGORITHM_FREE_TESTED_FORMAL_EXECUTION_NOT_STARTED

## 包

- ZIP：Research/Packages/Gate14Re-ME/formal-st/v5/attempt-004/Gate14ReME-FormalST-v5-end-to-end-attempt-004.zip
- 字节数：3,542,565,954
- SHA-256：493c2e7ebbd2f77b2a12803d0878c5a4f18bafd60a554380718a38bbc04fcedf
- ZIP 条目：2,812
- manifest 载荷文件：2,811
- manifest 载荷字节：3,769,326,937

## 验证结果

1. 新 staging root：PASS。
2. 全量逐文件 SHA-256 manifest：PASS。
3. credential-like 路径扫描：0。
4. staging 授权链 dry-run：PASS。
5. ZIP64 构建及 CRC：PASS。
6. 全新解压：PASS。
7. 全新解压后的全量逐文件 SHA-256：PASS。
8. 全新解压后的授权链 dry-run：PASS。
9. Unity 算法无关 readiness：PASS。
10. Unity 自然退出码：0。
11. readiness 算法实例数：0。
12. FormalInputs 根：未创建。
13. FormalRuns 根：未创建。
14. FormalDataPackages 根：未创建。
15. formal analysis、MQ、MT：均未启动。

## 授权模型

用户主授权允许目标机在一次明确启动后，从 readiness 自动推进到完整已验收数据包。编排器只有在上一阶段终局冻结且哈希完整匹配时，才能派生下一阶段的最小子授权。

主授权不允许 formal analysis、效果解释、排名或赢家、MQ、MT、设计变更、同 attempt 重试/恢复/补齐、replacement、并行执行或凭据打包。

## 关键修正

正式采集入口绑定的是 qualification 冻结的：

Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json

SHA-256：

5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca

它满足 formal supervisor 要求的 FROZEN_SIX_ALGORITHM_BINDING。旧文档曾误列 v5 构建输入包装文件；旧 ZIP 未被改写，新包及外部旧版 README 已修正该说明。

## 测试边界

本次 package test 没有执行端到端正式模式，因为那会真实生成 formal inputs 并启动正式实验。端到端路径通过 staging 与 fresh extraction 两次只读授权链 dry-run，以及 fresh extraction 上一次真实 Unity 算法无关 readiness 验证。
