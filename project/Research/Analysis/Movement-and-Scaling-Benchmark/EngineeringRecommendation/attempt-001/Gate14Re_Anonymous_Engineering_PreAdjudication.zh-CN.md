# Gate 14Re 匿名综合工程预裁决

状态：`ANONYMOUS PRE-ADJUDICATION COMPLETE / UNBLINDING PENDING`

本分析是对已封存 Gate 14Re raw 的独立只读、事后工程决策分析。原正式结论 `NO_UNIQUE_WINNER` 保持不变；本分析不声称确认性统计优胜。

## 裁决表

| 匿名算法 | 合格 | 运动 rank | 路径 rank | 数量尺度 rank | 渲染 rank | DecisionScore | 静态负担 rank |
|---|---:|---:|---:|---:|---:|---:|---:|
| U17 | YES | 1 | 1 | 2 | 3 | 8 | 2 |
| U29 | YES | 3 | 3 | 3 | 1 | 13 | 1 |
| U43 | YES | 1 | 1 | 1 | 2 | 6 | 3 |
| U61 | NO | — | — | — | — | — | — |

## 匿名预裁决

- 推荐是否可用：YES
- 暂定匿名推荐：U43
- 裁决依据：`UNIQUE_MINIMUM_FROZEN_DECISION_SCORE`
- 生产算法身份：未释放。
- 下一步：只有在用户单独授权解盲与最终推荐后，才可解密标签映射并输出真实算法名称。

## 推断边界

RMAT 的六组匿名对比报告点估计、Holm 校正 p 值与 Bonferroni 同时 95% 区间。区间包含 0 时写作‘方向存在但不确定’，不写作统计平局，也不升级为统计优胜。T95、T99、M2、数量尺度、M4 和静态工程负担依冻结规则承担综合工程裁决作用。
