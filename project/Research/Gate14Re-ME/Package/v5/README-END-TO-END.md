# Gate14Re-ME Formal ST v5 端到端一键迁移包

## 1. 这个版本解决什么问题

本包把原来彼此分开的阶段授权合并为一条受限的端到端授权链。操作者在目标机上明确启动 RUN-TO-DATA-PACKAGE.cmd 后，包内可以依次完成：

1. 包文件、运行时、Unity 与冻结合同核验；
2. 算法无关 readiness；
3. 生成并冻结正式 ST 输入和调度；
4. 根据刚冻结的输入哈希派生正式采集子授权；
5. 严格串行执行正式 ST 原始数据采集；
6. 完整冻结原始采集根；
7. 根据原始冻结哈希派生只读验收子授权；
8. 执行独立、流式、有限内存的只读验收；
9. 生成完整的已验收数据包和终局证据。

在上述既定范围内，运行中不再逐阶段向用户索要新的科研授权。

RUN-TO-DATA-PACKAGE.cmd 自带的 ConfirmFormalCollection 参数只是防止误点的启动保护，表示操作者确实选择了端到端入口；它不是新的科研授权。

## 2. 两个入口的区别

### START-HERE.cmd

只执行安装、完整哈希核验、known-answer 检查和算法无关 readiness。

它不会：

- 生成正式输入；
- 启动正式采集；
- 生成正式数据包；
- 启动分析、MQ 或 MT。

适合先检查目标机是否能正确解压、是否有足够的软件环境、Unity 是否能运行。

### RUN-TO-DATA-PACKAGE.cmd

执行完整端到端流程，直到生成已验收数据包。

一旦进入正式输入生成阶段，这个入口按单次 attempt 运行。任何技术失败都会 fail closed：保留已有根和证据，禁止在同一 attempt 中 retry、resume、top-up、merge、skip、reorder、replacement 或并行补齐。

## 3. 运行前准备

目标机应满足以下条件：

- Windows；
- 建议至少预留 75 GiB 可用磁盘空间。脚本硬门为冻结的 64,310,367,960 字节正式原始/交付预算，再加 10 GiB 端到端安全余量；
- 可用虚拟内存至少覆盖 16 GiB lane 承诺量，再加 4 GiB 安全余量；
- 不要同时运行其他 Unity.exe；
- 保持稳定供电，关闭自动休眠；
- 不要把包放在会自动同步、自动去重或按需下载的目录；
- 不要移动、改名或编辑包内文件；
- 不要预先创建 FormalInputs、FormalRuns、FormalDataPackages 或本次 execution evidence 的 attempt-001 根。

包内包含精确版本的 Unity 安装器、PowerShell 和 Python 运行时，但不包含任何账号、许可证或凭据。

如果目标机的 Unity 需要许可证激活，可能仍需操作者在系统或 Unity 界面完成许可证激活。许可证激活是软件许可条件，不是新的实验授权，也不会允许把账号、许可证文件或凭据写入 ZIP。

## 4. 推荐操作流程

### 4.1 复制与解压

1. 把 ZIP 完整复制到目标机。
2. 校验 ZIP 随附的 SHA-256。
3. 使用支持 ZIP64 的工具完整解压。
4. 保持最外层目录 Gate14ReME-FormalST-v5 不变。
5. 不要直接在 ZIP 内运行 CMD。

### 4.2 可选：先做 readiness

双击 START-HERE.cmd。

成功标志：

PASS_MIGRATION_PACKAGE_INSTALL_AND_ALGORITHM_FREE_READINESS

注意：端到端入口固定使用 PackageReadiness/end-to-end-attempt-001。若先单独运行 START-HERE.cmd，它应使用自己按时间生成的默认 receipt 目录，不会占用端到端固定 readiness 根。

### 4.3 正式运行到数据包

确认磁盘、内存、供电和 Unity 空闲后，双击：

RUN-TO-DATA-PACKAGE.cmd

这个入口已固定传入端到端启动保护。无需在 input generation、formal collection 或 acceptance 之间再次授权或手工启动下一脚本。

不要重复双击。如果窗口似乎暂时没有新输出，应先检查进程与 receipt；正式 ST 包含 7,843 个严格串行的新 Unity 进程，运行可能持续数天。

## 5. 实验流程与固定规模

### 5.1 正式设计

- G：64、96、128；
- N：32、64、128；
- F：1、9、25、81；
- 36 个 G × N × F 结构单元；
- 每单元 B = 36；
- 1,296 个 superblock；
- 6 个冻结算法；
- 7,776 个算法 lane；
- 54 个 oracle batch，每批 24 个输入；
- 12 个 empty-boundary 进程；
- 1 个 instrument self-test；
- 总计 7,843 个严格串行 fresh Unity process；
- whole-superblock technical replacement = 0。

### 5.2 执行顺序

1. 核验 package manifest、主授权、子授权模板及全部冻结 SHA-256；
2. 检查固定根均不存在；
3. 检查 Unity 空闲、磁盘和虚拟内存硬门；
4. 执行算法无关 readiness；
5. 用预发的 input-generation 子授权生成 1,296 个输入及 1,296 行调度；
6. 冻结 input manifest 与 schedule；
7. 编排器只依据冻结哈希生成 collection-only 子授权；
8. instrument self-test；
9. 54 个 oracle batch；
10. 12 个 empty-boundary；
11. 1,296 个 superblock，每个按 Williams 顺序执行 6 个 lane；
12. 冻结 raw acquisition；
13. 编排器只依据 raw freeze 和 terminal 哈希生成 read-only acceptance 子授权；
14. 流式完整验收、typed Parquet 全量 round-trip、逐文件 manifest；
15. 写入端到端最终证据和 terminal。

## 6. 产物位置

### 正式输入

Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-001

### 原始采集根

Research/FormalRuns/Gate14Re-ME/formal-st/v5/attempt-001

此处是冻结原始证据。验收不得写回。

### 完整已验收数据包

Research/FormalDataPackages/Gate14Re-ME/formal-st/v5/attempt-001

这个目录就是本流程的最终数据包。它包含：

- 必要的控制与原始交付视图；
- typed Parquet 全量交付；
- acceptance-manifest.v5.json；
- file-manifest.v5.jsonl；
- terminal-receipt.v5.json；
- terminal-final.v5.json。

### 端到端证据

Research/Verification/Gate14Re-ME/formal-st-end-to-end-execution-attempt-001

终局成功标志：

PASS_ACCEPTED_FORMAL_ST_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN

## 7. 成功后怎么判断

必须同时满足：

- 原始采集 terminal 为 PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING；
- acceptance terminal 为 PASS_READ_ONLY_FORMAL_ST_ACCEPTANCE；
- 1,296 个 accepted superblock；
- 7,776 个 named algorithm lane；
- typed Parquet full round-trip = true；
- source measured root write-back = false；
- 端到端 terminal 为 PASS_ACCEPTED_FORMAL_ST_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN。

只有最后一项出现，才表示本一键流程真正结束。

## 8. 失败处理

若任一步骤失败：

- 不要再次双击；
- 不要删除、改写或移动 FormalInputs、FormalRuns、FormalDataPackages 和 execution evidence；
- 不要在相同 attempt 中续跑、补跑、合并或替换；
- 保存控制台输出；
- 查找 orchestration-failure-receipt.v1.json；
- 将整个失败 evidence root 和相关 attempt 根交回诊断；
- 只有在创建全新 attempt、重新绑定授权和哈希后才能重新执行。

失败终局标志：

FAILED_CLOSED_PRESERVE_ALL_ROOTS_NO_RETRY_OR_RESUME

## 9. 授权边界

本包已经包含并约束以下授权：

- readiness；
- formal input generation；
- formal ST collection；
- raw freeze；
- independent read-only acceptance；
- complete accepted data package creation。

本包明确不授权：

- formal analysis；
- 算法效果解释；
- 排名、加权或赢家裁决；
- MQ；
- MT；
- 自动改变 G、N、F、B、指标、停止规则或算法集合；
- 任何 retry、resume、top-up、merge、skip、reorder、replacement 或并行完成；
- 把账号、许可证或其他凭据放入 ZIP。

生成数据包后，流程会停止。后续如果要做 formal analysis，必须另行建立分析合同与授权。

## 10. 授权与实现的审计文件

- 主授权：Research/Gate14Re-ME/Package/v5/Authorizations/end-to-end-through-data-package-authorization.v1.json
- 输入生成子授权：Research/Gate14Re-ME/Package/v5/Authorizations/formal-input-generation-authorization.end-to-end.v1.json
- 复用身份绑定：Research/Gate14Re-ME/Package/v5/Authorizations/formal-st-algorithm-identity-binding.reused.v5.json
- 端到端编排器：Research/Gate14Re-ME/Package/v5/Run-To-Accepted-Data-Package.v5_1.ps1
- 包级逐文件清单：Research/Gate14Re-ME/Package/v5/package-manifest.v1.json

编排器只会在前一阶段已经完整冻结且哈希匹配时派生下一阶段的最小子授权，无法用主授权越过冻结门或扩大到分析阶段。
