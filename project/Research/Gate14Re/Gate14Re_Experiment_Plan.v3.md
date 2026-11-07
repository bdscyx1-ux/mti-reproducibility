# Gate 14Re 科学设计 v3：动态事件窗口修正

状态：`SCIENTIFIC-DESIGN-FROZEN / B48-FIXED / DYNAMIC-EVENTS-IN-WINDOW / NON-EXECUTING`

日期：2026-10-15（Asia/Shanghai）

## 1. 权威关系

本文件与 `Gate14Re_Design_Contract.v3.json` 共同构成 Gate 14Re v3 的动态事件修正。除本文件明确修改的事件时间与事件同步门禁外，`Gate14Re_Experiment_Plan.v2.md` 和 `Gate14Re_Design_Contract.v2.json` 的全部科学规则继续有效。

v3 不改变：四算法、8 个主条件、2 个数量 anchors、`N_primary=128`、`N={1,8,32,128,512}`、B=48、Williams 顺序、1,536 个 planned fresh processes、6,144 个算法 lane samples、共同终点、到达规则、M1–M5 定义、资格门槛、选优规则、多重性、失败替换规则、硬件/渲染环境或“允许无唯一赢家”的结论空间。

## 2. 修正原因

8 个冻结源场景都已包含相同五类确定性 `scheduledChanges`，但源场景后三项事件位于 1,000、1,500 和 1,999.98 秒。Gate 14Re Movement lane 的上限是 180 秒，因此原时间不能在该 lane 内执行。

Gate 14Re 不新增随机障碍生成器，也不新增带独立轨迹的物理移动障碍物。修正只改变事件发生 tick；事件 ID、order、repair budget、变化坐标、walkability、traversal cost 和源场景 SHA-256 全部保持不变。

## 3. Gate 14Re 固定事件日历

fixed step 固定为 0.02 秒。所有算法在每个 block 中使用相同的下列日历：

| Event ID | Tick | 时间 | Order | 语义 |
|---|---:|---:|---:|---|
| `block-footprint` | 10 | 0.20 秒 | 0 | 冻结单元集合变为不可通行 |
| `unblock-footprint` | 10 | 0.20 秒 | 1 | 另一冻结单元集合变为可通行 |
| `increase-cost-footprint` | 1,500 | 30 秒 | 0 | 冻结单元集合代价提高 |
| `decrease-cost-footprint` | 4,500 | 90 秒 | 0 | 冻结单元集合代价降低 |
| `restore-initial-state` | 7,500 | 150 秒 | 0 | 所有触及单元恢复源场景初始状态 |

四个事件时点均严格位于 180 秒上限内。两个 tick=10 的事件作用于互不重叠的冻结坐标集合，按 order 0、1 依次执行，不互相抵消。

算法如果在某个后续事件之前已完成全部单位任务，其已 latch 的 M1/M2/M3 结果不因后续事件改变。算法更早完成并因此不再受后续扰动，是冻结时间轴下的合法完成速度结果；不得为了强制相同事件暴露而延长 M1、复活单位或循环目标。每个算法的实际已应用事件计数只作为结构性诊断，不作为新的选优指标。

## 4. 运行时同步门禁

Gate 14Re 实现必须同时完成以下步骤，缺一即 fail closed：

1. 从 SHA-256 已绑定的源场景读取五个原事件。
2. 逐项验证原 event ID、原 tick、order、repair budget、变化数量和逐坐标变化内容。
3. 只在内存中的 Gate 14Re adapter 将 tick 映射为 v3 日历；不得覆盖源场景 JSON。
4. 到达事件 tick 时，以固定 order 调用 `ResearchNavigationGrid.ApplyChanges`。
5. 将同一 `NavigationChangeSet` 传入当前生产 planner 的 `ApplyChanges`，并验证 planner/grid version 一致。
6. 同一帧更新用于实际渲染的 walkability/cost 表示；不可只改变 planner 而让画面保持旧状态。
7. 原始结构日志记录 event ID、scheduled tick、order、changed-cell count、previous/new grid version、planner repair status 和 visual revision。
8. 漏事件、重复事件、乱序、坐标漂移、事件内容漂移、grid/planner/visual version 不一致均立即使该 block 成为基础设施失败。

## 5. 禁止范围

- 不允许运行时随机选择事件位置、时间、数量或方向。
- 不允许依据算法、速度、路径、M1–M5、帧率或先前结果重抽事件。
- 不允许新增 physical moving-obstacle agent、随机碰撞轨迹或算法特异事件。
- 不允许修改冻结源场景文件或旧 v1/v2 权威文件。
- 当前修正不授权 formal Phase A、formal measured/analysis root、Phase B 或 Gate 15V-R/OBS。

## 6. 下一阶段

v3 科学修正冻结后，允许进行一次 Gate 14Re research-only 实现阶段：实现 v3 event adapter、movement/M4 runner、结构日志与可视同步；执行 compile-only、pure-synthetic known-answer validation、短现场 preflight 和 N=512 资源准入。该阶段不得产生正式 observation，也不得启动正式 Phase A。
