# Gate 13R 严格串行 10% 非执行准备检查点 v2

状态：`GATE13R-SERIAL-10PCT-NONEXECUTING-PREPARATION-PASSED-FORMAL-NOT-AUTHORIZED`

保存日期：2026-10-08（Asia/Shanghai）

## 结论

用户指令“**不再并行，直接串行实验**”已经落实为唯一活动 Gate 13R 路线：

- 最多同时存在 1 个 Unity Editor；
- 每个完整 Williams block 启动 1 个全新的 Unity Editor 进程；
- 一个进程最多执行一个 block，block 内按冻结 Williams 顺序执行 2 个或 4 个算法；
- 每个样本继续执行完整 reset；
- 不允许 2/3/4 lane fallback，不允许串行与并行数据混合；
- block 内任一样本失败即 fail closed，不自动 retry、resume 或合并部分 attempt。

本轮只完成非执行设计、配置、调度和 validation-only 审计。**没有启动 Unity，没有创建正式 execution receipt，没有创建正式输出根，也没有生成正式 timing 样本。**

## 冻结规模

| 项目 | 冻结值 |
|---|---:|
| 精度目标 | 每 campaign 相对 95% CI 半宽 10% |
| hard cap | 无 |
| 场景 | 53 |
| campaigns | 74 |
| eligible algorithm cells | 212 |
| shared-goal blocks/campaign | 144 |
| per-agent heterogeneous blocks/campaign | 204 |
| grouped-field heterogeneous blocks/campaign | 108 |
| 正式 Williams-block processes | 11,160 |
| 正式样本 | 31,536 |

## 串行运行时间与存储

- 串行 p50 投影：`64.830802096 h`；
- 串行 p95 投影：`83.904223147 h`；
- 建议维护窗口：`96 h`；
- 旧 `36 h` 硬墙钟约束在严格串行下不可满足，因此不能继续作为启动门禁；
- 当前不擅自建立新的硬墙钟上限。正式授权必须明确接受上述时间包络，或给出新的上限并允许重新设计；
- 预计 formal raw bytes（含 1.5× safety）：`43,885,575,792`；
- 另保留 40 GiB，正式启动最低空闲原始字节：`86,835,248,752`；
- validation-only 观察到 `276,620,062,720` 可用字节，但该快照不具启动授权效力；正式 root 创建前必须重新测量。

## 通过的非执行门禁

- Gate 12R v4 exact-topology evidence audit：通过；428/428 wrapper summaries、428/428 license serial assignment、0 process overlap、0 retry/resume；
- 严格串行 readiness：114/114 assertions；
- v2 schedule validation：38/38 assertions，11,160 unique blocks、31,536 unique runs，Williams position balance 通过；
- v2 config/schedule/manifest/provenance deterministic regeneration：逐字节一致；
- v2 orchestrator validation-only：通过；存储子门禁通过且明确为 non-authorizing；
- 缺失正式 execution receipt 的负向测试：按预期 exit 1，并在 Unity/root/timing 创建前拒绝；
- v2 final audit：156/156 assertions，0 errors。

## 活动绑定

- config：`Research/Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json`  
  SHA-256 `faaec5613a2625aee462038305310e229c7cf8fdf67edb800a0b3eb256f1a300`
- schedule：`Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl`  
  SHA-256 `d9300cce732e12a7b90ec43ad9d5f8fe52cbad58da713c25879754eb31ea0ead`
- schedule manifest：`Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json`  
  SHA-256 `8bf87ae8c206355930dd6b720756216ef74052ce9d0551680e3a91933a970dc9`
- provenance：`Research/Gate13R_Serial_10pct_Formal_Preparation_Provenance.v2.json`  
  SHA-256 `409b79506b006378c79a0cb777909e0157b9917a2e439c90d59d0679b2340f7b`
- orchestrator：`Research/Run-Gate13RSerial10pctFormalCampaignV2.ps1`  
  SHA-256 `8bdd8f7b1edc8fc84f8ef35099f103fd55f789f352e47537874f2095a6116770`
- block wrapper：`Research/Run-Gate13RSerial10pctFormalBlockV2.ps1`  
  SHA-256 `b4827065ec609f148fa0dd58959cb79e5c9bf54f35fd7aa8b64ef172d820fe1b`
- final audit：`Research/Verification/Gate13R_Serial_10pct/v9-v2-final/FinalAudit.summary.json`  
  SHA-256 `16ffdd5e8a92eb41da07e01017dfdc9ec0c0bea8bea3e3dcf1e7b01892654774`

## 历史证据边界

- 四 lane v16、三 lane v1 和所有更早的并发尝试继续作为失败/排除证据保留，不得 retry、resume、补齐或与串行结果合并；
- serial formal-preparation v1 因复用旧 5% 存储阈值而被拒绝，保持原样；
- v2 是唯一活动的非执行正式准备；
- Gate 10R attempt 4、Gate 11R attempt 2、Gate 12R pilot v4 仍是活动上游；原始脚本、原始场景及所有冻结历史 root 保持不变。

## 精确停止点

正式输出根 `Research/FormalRuns/Gate13R_Serial_10pct/v2` 不存在。下一步只能由用户另行发送正式执行授权；授权必须绑定本检查点列出的 exact hashes，并明确接受串行 p95 `83.904223147 h` / 建议 `96 h` 维护窗口。获得授权后，仍须先生成一次性 versioned execution receipt，并重新执行 hash、环境、电源、热状态、PSAPI/CIM、许可证和原始字节存储 preflight；全部通过后才可原子创建 formal root。
