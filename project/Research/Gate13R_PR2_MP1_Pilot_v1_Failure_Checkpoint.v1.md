# Gate 13R-PR2-MP1 pilot v1 failure checkpoint

Status:

`FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / ZERO-MEASURED-BLOCKS / IMMUTABLE`

## 发生了什么

MP1 的完整 pre-pilot 门禁先通过 `29/29`。一次性启动随后创建了 v1 pilot root、execution receipt 和初始 checkpoint，但 Windows PowerShell 5.1 orchestration 在第一个 Unity block 之前立即失败：从 JSON 反序列化得到的 checkpoint `PSCustomObject` 没有预先声明 `startedAtUtc`，StrictMode 因而拒绝第 64 行的属性赋值。

这不是算法、场景、telemetry、memory threshold、Unity license 或采集数据失败。没有启动 Unity Editor，没有生成 block plan，没有运行 measured block，也没有生成 measured sample。

## 冻结结果

- pilot v1 root：`H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1`；
- measured blocks：`0 / 96`；
- measured samples：`0 / 384`；
- raw files：`0`；
- Phase A raw commit：未发生；
- pilot evidence files：`5`；
- pilot evidence bytes：`5,247`；
- canonical tree SHA-256：`a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265`；
- `5/5` 文件均已只读；
- failure-preservation receipt SHA-256：`6d129e01b678871754413ca853051f7f8b921dad3ee572d35e96775fde57087e`。

失败证据保存时还发现 PowerShell 7/.NET 10 不接受 `File.Replace(..., backupPath = null)`。该 preservation attempt 的失败单独保留；随后仅使用非空 backup path 完成 checkpoint 原子替换和只读冻结，未重启或续跑 pilot。

## 冻结输入不变性

失败后重新逐文件核验 Gate 13R-PR2 formal attempt 2：仍为 `28,020` files / `8,536,611,302` bytes / canonical tree SHA-256 `aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`，全部只读。Unity process 为 0，`Temp/UnityLockfile` 不存在，formal attempt 3 root/receipt 不存在。

## 授权边界

不得 retry、resume、top-up、merge 或修改 pilot v1。不得对其运行 raw analysis，因为它没有达到 `PILOT-RAW-DATA-COMPLETE`。formal attempt 3、正式统计分析和 Gate 14R 仍未授权。

若要继续，必须单独授权 versioned v2 checkpoint-state-machine 修复、扩展 validation，以及一个全新的 v2 NON-FORMAL pilot；建议授权文本见：

`Research/Gate13R_PR2_MP1_Attempt2_Next_Authorization_Prompt.md`

