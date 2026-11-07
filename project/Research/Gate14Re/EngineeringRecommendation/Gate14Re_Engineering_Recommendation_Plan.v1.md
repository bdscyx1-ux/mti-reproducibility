# Gate 14Re 只读匿名综合工程推荐计划 v1

状态：`FROZEN-BEFORE-DERIVED-OUTCOME-ACCESS / POST-HOC / READ-ONLY / ANONYMOUS-FIRST`

日期：2026-10-16（Asia/Shanghai）

## 1. 目的与正式边界

本计划只回答一个工程决策问题：在 Gate 14Re 已封存的贴近实际应用场景中，四个算法里是否能够形成一个可审计的综合工程推荐。

原 Gate 14Re 正式 Phase B 结论 `NO_UNIQUE_WINNER` 永久保留。本分析不修改 formal raw、不修改既有 Phase B、不重新定义原 M1，也不把事后分析包装为确认性统计赢家。新的结论只能称为 `POST-HOC COMPOSITE ENGINEERING RECOMMENDATION`。

本阶段只允许匿名预裁决。真实算法身份的解盲和最终生产算法推荐需要用户另行授权。

## 2. 独立单位与数据层级

- 独立分析单位固定为一次 fresh Unity process 产生的完整四算法 input block。
- 每个 condition 有 48 个独立 complete blocks。
- agent、arrival tick 和 rendered frame interval 都是 block 内子样本，不得作为独立 n。
- 所有比较保持同一 block 内四算法配对，并在 8 个固定 condition 间等权汇总。
- 不排除任何已结构验收的 complete block，不补采、不扩 B、不重跑 Unity。

## 3. 高分辨率运动端点

对 movement lane 的每个算法 sample，令每个 agent 的截尾到达 tick 为：已到达时取 `arrivalTick`，未到达时取 9000；所有 tick 均限制在原冻结的 180 秒上限内。

主要派生端点：

`RMAT180 = 0.02 × mean(censored arrival ticks)`

描述性逐级 tiebreak：

1. RMAT180，越低越好；
2. T95，截尾到达 tick 的 nearest-rank 95th percentile；
3. T99；
4. T100−T50，越低表示尾部越集中；
5. 原 M1，仅作最后的描述性回退。

RMAT180 的六组无序算法对使用 block 内差值。每个 condition 先求 48 个 paired block 差值的均值，再对 8 个 condition 等权。报告点估计、普通 95% 区间、六组 Bonferroni 同时 95% 区间、未校正双侧 p 值和六组 Holm 校正 p 值。

同时区间包含 0 时写作“点估计具有方向，但当前精度不能确认”，不得写作统计平局、统计等效或统计优胜。T95、T99、尾部展开和原 M1 不新增确认性检验，只参与预冻结的描述性顺序。

## 4. 其他证据维度

### 4.1 资格门槛

完全复用原 Phase B 的 M3、M4、M5 门槛并从 immutable raw 重算。只有同时通过 M3、M4、M5 的算法进入推荐比较。

### 4.2 M2 路径效率

只使用四算法共同充分的 block-common mask。对每个 condition 求 block 级路径均值的几何汇总，8 个 condition 等权；越低越好。既有配对、多重性和同时区间规则保持不变，但在本分析中仅作为工程证据。

### 4.3 数量尺度

保留 C01、C07 两个 anchors 和 N={1,8,32,128,512}。使用原冻结模型 `outcome ~ anchor + log2(N) + algorithm + algorithm×log2(N)`，complete block 为 cluster。数量尺度维度包含：

- log RMAT180 的每 doubling ratio；
- log M2 的每 doubling ratio（共同 mask 足够时）；
- log M4 block-P95 的每 doubling ratio。

每项 ratio 越低表示随数量增长的退化越小。数量尺度 rank 为可用子项 rank 的算术平均再排序；RMAT180 和 M4-P95 必须可用，否则 fail closed。

### 4.4 M4 渲染表现

主条件 N=128 下，对每个 condition 的 block nearest-rank P95 frame time 作几何汇总，并在 8 个 condition 间等权；越低越好。

### 4.5 静态工程负担

仅作最后一层 tiebreak。对冻结的四个生产 planner 源文件计算透明的词法代理，按以下顺序越低越好：logical source lines、branch tokens、allocation sites、public-surface tokens、source bytes。它们不是长期维护成本的直接测量，只有前述运行证据仍相同时才可使用。

## 5. 综合裁决

只在 eligible algorithms 内排名：

`DecisionScore = 2 × R_movement + R_path + R_scaling + R_render`

rank 1 最好，总分越低越好。唯一最低总分产生匿名暂定推荐。最低总分相同时，固定按以下顺序逐级比较：

1. RMAT180；
2. T95；
3. T99；
4. T100−T50；
5. 原 M1；
6. M2；
7. 数量尺度综合 rank；
8. M4 P95；
9. 静态工程负担 tuple。

若所有运行证据与静态代理仍完全相同，不得使用算法名称、匿名标签字典序、随机数或哈希强行选优；状态必须为 `EXACT_EVIDENCE_AND_STATIC_PROXY_EQUALITY_REQUIRES_USER_POLICY`。

## 6. 标签盲化与阶段停止点

源标签到 U17/U29/U43/U61 的随机映射已在访问派生结果前产生，明文映射不落盘，密文由 Windows DPAPI CurrentUser 保护。匿名分析输出不得包含 production algorithm ID、原始 source label 或映射。

匿名预裁决完成后必须停止于：

`ANONYMOUS_PRE-ADJUDICATION_COMPLETE / UNBLINDING_PENDING`

未获得新的明确授权前，不得解盲，不得输出真实算法名称，不得把匿名推荐改写为最终生产推荐，不得启动新采集、Gate 15V-R 或 OBS。

