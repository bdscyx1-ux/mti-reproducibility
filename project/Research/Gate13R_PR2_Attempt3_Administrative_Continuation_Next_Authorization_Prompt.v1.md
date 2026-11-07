# Gate 13R-PR2 formal attempt 3 — forensic recovery-readiness and administrative continuation authorization prompt v1

本文件是下一阶段可复制的授权文本，**本身不构成授权**。在发送前应审阅：

- `Research/Gate13R_PR2_Attempt3_PostFailure_Protocol_Amendment.v1.md`；
- `Research/Gate13R_PR2_Attempt3_Recovery_State_Machine.v2.json`；
- `Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v2.md`；
- 其配套 authorization 与 preservation manifest。

---

授权 Gate 13R-PR2 formal attempt 3 的一次版本化、结果盲化、只读 forensic recovery-readiness audit；仅在全部门禁通过、生成 `RECOVERY-READY-FOR-SEPARATE-LAUNCH-AUTHORIZATION` checkpoint 并再次获得我明确的 launch authorization 后，才可执行一个行政 continuation segment。

1. 保留并冻结原始 v3 status、receipt、checkpoint、failure checkpoint、logs 与 formal payload；不得覆盖、删除、改写或把原失败重编码为成功。
2. 只读验证 ordinals 1–3,469 的 schedule identity、完整 block/sample、算法集合、Williams/predecessor、PID/start-time、hash、run-ID 唯一性及所有原始 hard gates。
3. 只读取证 ordinal 3,470；只有证据链完全闭合才可在 formal root 外生成 promotion/commit sidecar。禁止重跑或修改 3,470。
4. 验证不存在 ordinal 3,471 及之后的 measured output；冻结所有 scientific config/schedule/endpoint/contrast/multiplicity/threshold hashes。
5. 允许对 status atomic-persistence 与 continuation orchestrator 做 versioned implementation repair、static/synthetic/negative validation，但不得写入 measured payload，不得读取或报告 P1–P5/M1–M5、算法 timing、effect、CI、p 值、ranking、winner 或 superiority。
6. forensic audit 通过后停止并报告 readiness；audit authorization 不等于 Unity launch authorization。
7. 若我随后明确授权 launch，则只允许：验收 3,470 后从 global ordinal 3,471 开始，严格按原 schedule 执行至 3,552；最大 Unity 并发 1；不得重跑 1–3,470；不得 top-up 超过 3,552；不得 merge pilot/history/其他 attempt；不得替换、跳过、重排或择优保留 observation。
8. continuation 只允许一个 segment。任一 measured hard failure立即 fail closed；不得自动 retry、再次 resume 或创建第二 continuation。
9. 只有最终验证 3,552 unique processes、10,176 unique samples、1,008 complete matched superblocks、全部 quota 与 raw-tree freeze 后，才允许使用限定标签：`一次性完整正式尝试（同一 frozen schedule/root；曾发生行政中断；依据版本化事后修正案继续完成）`。
10. 本授权不授权 Phase-B 正式统计分析，不授权 Gate 14R，不授权 Playable/OBS timing，也不授权将 incomplete half-pair 或 partial acquisition 描述为完整分析单位。

---

建议把 forensic readiness 与 Unity launch 拆成两条独立授权消息；第一条只完成审计、修复和 readiness，第二条在审计通过后才启动 continuation。
