# LPA* 算法规范 v1

算法 ID：`LPA*`

- 使用 backward、goal-rooted 的 Lifelong Planning A*；
- 每个 agent 具有独立 `g`、`rhs`、优先队列与固定 start/goal；
- 初始状态仅 goal 的 `rhs=0`，其余 `g=rhs=∞`；
- key 为 `(min(g,rhs)+h(fixedStart,node), min(g,rhs))`；
- 动态变化时更新变更 cell 及其 8 邻域，以覆盖入格成本、可通行性和禁切角依赖；
- 若全局最小可通行成本下降，则为保持启发式一致性完整重建各 agent 的搜索状态；
- `ApplyChanges` 在冻结 repair budget 内把所有已实例化 agent 状态修复至一致；
- 同一 agent 的 start 或 goal 发生变化属于协议错误；
- 成功路径必须满足冻结的入格成本、连通性和切角规则。

