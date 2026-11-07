# Gate13R-AX2

Gate13R-AX2 是 Gate 13R 的独立四算法 shared-goal 扩展。它复用 Gate 13R 的 32 个 shared-goal campaigns、确定性场景、动态事件、固定起点工作负载、每 campaign `B=48` 和四处理 Williams 顺序规则，但重新同期测量以下四种算法：

1. `BiA*-R`：每次请求从起点和终点双向重新搜索；
2. `LPA*`：每个 agent 保留固定起点的增量搜索状态；
3. `C-FF`：完整重算共享流场；
4. `IDFF`：增量动态共享流场。

本扩展不修改、不追加、不汇并 Gate 13R 的正式 raw、Phase B 或既有结论。旧 Gate 13R 只作为冻结输入与方法来源；Gate13R-AX2 必须使用独立 root、独立授权、独立 raw commit 和独立分析。

## 冻结规模

- campaigns：32；
- 每 campaign blocks：48；
- 完整 Williams blocks：1,536；
- 每 block 算法样本：4；
- 总算法样本：6,144；
- 每算法 P1 观测：1,536（无缺失时）。

## 主要文件

- `experiment-plan.v1.md`：带 Material Passport 的总实验计划；
- `Contracts/scientific-contract.v1.md`：研究问题、实验单位和比较范围；
- `Contracts/four-algorithm-extension-fairness.v1.md`：四算法同期公平性边界；
- `Algorithms/*.md`：新算法规范；
- `Analysis/p1-analysis-plan.v1.md`：P1 原始几何均值和四个配对比较；
- `Execution/v1/formal-williams-schedule.v1.jsonl`：已生成并验证的 1,536-block 顺序；
- `Authorization/next-precollection-readiness-authorization-prompt.v1.md`：进入非执行预采集 readiness 的下一步授权文本；正式采集授权文本只能在完整 readiness 通过后生成。

当前状态：`IMPLEMENTATION-AND-DESIGN-VERIFIED / FORMAL-COLLECTION-NOT-AUTHORIZED`。

