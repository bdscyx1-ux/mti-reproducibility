# Gate 13 非执行准备测试设计 v1

测试设计 ID：`gate13-nonexecuting-preparation-tests-v1`  
日期：2026-10-06  
对应规格：`gate13-nonexecuting-preparation-specification-v1`

## 1. 总原则

测试先验证纯函数和 fail-closed 边界，再运行集成的 validation-only 路径，最后运行既有回归并复核冻结证据。任何测试不得创建 `Research/FormalRuns/Gate13/v1`、不得生成 `formalCampaign = true`、不得启动 Unity。

测试开始和结束都记录：

- formal root 是否不存在；
- Unity process 数；
- `Temp/UnityLockfile`；
- Gate 11 bundle manifest/aggregate；
- Gate 12 final audit、pilot manifest、candidate 与 budget hashes；
- 24 项 original baseline；
- Gate 10 fairness specification、runner 与 workload runner hashes。

## 2. 单元测试矩阵

### 2.1 Williams 调度

- 四算法 52 blocks：208 samples、13 cycles，各算法每 position 13 次，每个有向相邻 pair 13 次；
- 两算法 148 blocks：296 samples、74 cycles，各算法每 position 74 次，每个有向相邻 pair 74 次；
- 两算法 52 blocks：104 samples、26 cycles；
- blocks 不是算法数的整数倍、blocks 为 0、算法数为奇数或未知算法时拒绝；
- 同一输入重复展开得到相同 canonical schedule SHA-256。

### 2.2 正式 config

- Gate 11 原始 scenario 顺序与固定 cohort 顺序产生恰好 74 campaigns；
- cohort campaign 数分别为 32/21/21；
- blocks 分别为 52/148/52；
- samples 分别为 6,656/6,216/2,184，总计 15,056；
- 每个 campaign 的 scenario hash/fingerprint、cohort eligibility 和 schedule hash 可独立重算；
- 所有 campaign ID、output path、run ID 唯一且位于冻结 formal root 下；
- 相同输入两次生成的 JSON 文本和 SHA-256 完全相同；
- 更改 blocks、总数、scenario hash、路径、config ID、amendment hash、execution flag 或正式根路径必须失败。

### 2.3 原始字节存储门槛

- `freeBytes = 74,417,330,488`：失败；
- `freeBytes = 74,417,330,489`：通过；
- `freeBytes = 74,417,330,490`：通过；
- null、负数、非整数或错误 volume/path：失败；
- 判定只比较 Int64 原始字节；GiB 显示不得反向影响 verdict；
- validation-only 当前 snapshot 标记为 advisory、`launchAuthorizationConferred = false`。

### 2.4 执行授权 fail-closed

在内存构造合成对象，不把 authorization receipt 写入项目：

- null receipt、false flag、错误 kind、错误 config hash、错误 amendment hash、错误 output root、空用户引用均失败；
- 只有所有字段精确匹配时 validator 通过；
- validator 通过不等于本阶段可执行，命令行仍必须显式 `-Execute`；
- `-Execute` 缺 receipt 必须在创建 formal root 前失败。

### 2.5 路径与 checkpoint

- campaign output 必须是 formal root 下 config 指定的唯一目录；
- `..`、root 前缀碰撞、绝对路径替换、已有目录和已有 summary 均拒绝；
- checkpoint temp path 与 target 同目录，序列化后能原子替换；
- validation-only 不调用 checkpoint writer；
- failure 状态不允许自动 retry 或覆盖部分输出。

### 2.6 监控

- 未达 stall/timeout：continue；
- 连续 3 次无增长：advisory，但不 kill；
- 达 10,800 秒：hard-timeout，允许终止 owned process tree；
- 任意非零 campaign exit：停止且 no-auto-retry。

## 3. 静态与集成 validation-only

`Run-Gate13PreparationValidation.ps1` 必须：

1. 解析所有新增 `.ps1/.psm1`；
2. 解析 config 与全部项目 JSON；
3. 深度验证 Gate 11 bundle 57 files/56 artifacts 与 aggregate；
4. 验证 Gate 12 成功 `v1` 的关键 hashes 和 final audit passed；
5. 验证 24/24 original baseline；
6. 调用顶层 orchestrator `-ValidationOnly`；
7. 对 74 个 campaign 调用纯 validation，且至少对 cap-148 campaign 调用 scenario runner `-ValidationOnly`；
8. 证明调用前后 formal root 均不存在、Unity process 没有增加、lockfile 不存在；
9. 验证 config 与实现文件未包含可绕过 authorization/preflight 的默认执行路径；
10. 输出单独的 verification summary，不写 formal root。

## 4. 回归测试

必须运行：

- `Research/Verification/Run-Gate12AnalysisUnitTests.ps1`，预期 63/63；
- `Research/Verification/Run-Gate13ReadinessAmendmentAudit.ps1`，预期全部通过；
- 复核 Gate 12 成功 `v1` 中已归档的 start/post-warmup/end preflight 证据，并在新的 Gate 13 独立入口重新执行等价且包含原始字节存储门槛的 `-ValidationOnly` preflight；不得为重跑 Gate 12 preflight 而移动、覆盖或伪造已存在的冻结 `v1` 输出根目录；
- 新增 Gate 13 unit tests 与 validation-only integration。

由于本阶段未修改 C#、Unity assets 或原始场景，不运行新的 timing workload 或正式 Unity campaign。保留的 Gate 2–12 passing summaries 与最终审计哈希用于回归证据；如 PowerShell/JSON 静态或现有回归失败，必须先修复，不能通过启动 timing sample 绕过。

## 5. 负向安全测试

以下任一条件必须在创建 formal root 和调用 Unity 之前失败：

- 缺失或伪造 execution authorization；
- config/amendment/runner/workload/Unity/fairness/spec hash 不匹配；
- formal root 已存在；
- Gate 11 scenario path 逃逸 bundle；
- scenario source hash 或 fingerprint 不匹配；
- free bytes 少 1 byte；
- Unity 已运行或 lockfile 存在；
- blocks 超过 config、不是完整 Williams cycle，或 sample count 不一致；
- campaign output path 与 config 不同；
- 尝试自动 retry、覆盖或自动 resume。

## 6. 通过标准与停止条件

通过要求：所有新增单元/静态/validation-only tests 通过；Gate 12 的 63 项回归通过；Gate 13 amendment audit 通过；Gate 12 已归档 preflight 证据仍有效且新的 Gate 13 validation-only preflight 通过；冻结边界 byte-identical；formal root 不存在；无 Unity/lock；未产生正式 sample。

通过后写入：

- `Research/Gate13_NonExecuting_Preparation_Manifest.v1.json`；
- `Research/Verification/Gate13_Preparation_Final_Audit.summary.json`；
- `Research/Gate13_NonExecuting_Preparation_Checkpoint.md`。

随后立即停止，等待用户对 Gate 13 正式执行的单独授权。
