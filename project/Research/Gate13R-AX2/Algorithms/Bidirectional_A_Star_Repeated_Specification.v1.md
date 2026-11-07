# BiA*-R 算法规范 v1

算法 ID：`BiA*-R`

- 每个 `Plan` 请求创建相互独立的正向与反向 A* 前沿，不跨请求复用搜索状态；
- 正向前沿从 start 搜索 goal；反向前沿从 goal 在反图上搜索 start；
- 启发式为按全局最小可通行入格成本缩放的 Manhattan 或 octile 距离；
- 发现两前沿共同到达的节点时形成一条可实现路径上界；
- 只有当两个前沿的有效最小 `f` 均不低于当前最佳完整路径代价时才终止；
- 所有队列 tie 均按 `f, h, y, x, insertion-sequence` 确定性排序；
- 动态变更不保留搜索状态，`ApplyChanges` 只校验并推进 grid version；
- 输出路径必须满足冻结的入格成本、连通性和切角规则。

