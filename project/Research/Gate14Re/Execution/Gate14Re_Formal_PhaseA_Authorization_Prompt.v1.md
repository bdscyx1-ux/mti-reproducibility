# Gate 14Re 正式 Phase A 单独授权提示词

授权 Gate 14Re 正式 Phase A attempt 001 的单次启动与采集。严格绑定：

- launch readiness：`Research/Verification/Gate14Re/formal-executor-implementation-attempt-001/formal-phase-a-launch-readiness.v1.json`，SHA-256 `7eda9cb08751d5915f962b6a204b5ad937908c7b08f186d098e630baeda1569f`；
- 正式 block plan：SHA-256 `9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d`；
- execution contract v2：SHA-256 `6309d031e00fcf53380e74343adff5863c88aa1c11cb72542cd352a2f19c2bd3`；
- output schema v2：SHA-256 `0c248a4046df959bae078f360ba5d4dfc322d603dc0bdd8e920b492db11325c2`；
- formal runner EXE：SHA-256 `88b1b04971f8b712ddd0f18bca4f7296d287fdd6cdadef57c155d37b9ef0928c`；
- `Assembly-CSharp.dll`：SHA-256 `2f763a06d43a5777d6ce47cdba998d5482e82557ad35ee72f9e07dcd193b2961`；
- build receipt：SHA-256 `d110c97ca2f2f3d5a38490497ebfcf714d976c75b2397a68d46787e29c51ec9a`；
- 完整 standalone build canonical tree：SHA-256 `c4da85e66f9898834bc30b5e5618021458405f9a5962266c4d336479202abd46`；
- build-freeze receipt：SHA-256 `9df8bf66fa7df1d23e3454be5b23cdb99b907fa3e1848942b3845f56373c7199`；
- serial supervisor：SHA-256 `3c0bcf6f228656d58fde5a22f07846bb26b29351ffb7a71f4d6ae30ee5530b49`；
- pending authorization template：SHA-256 `2a9511aa6f0d9ba6499a65275f74efb8057a3bcff1f1142ac363a8639cd46191`。

允许根据冻结模板生成唯一只读正式授权收据：

`Research/Gate14Re/Execution/Gate14Re_Formal_PhaseA_Authorization.v2.json`

其中 `status=AUTHORIZED`、`userExplicitlyAuthorizedFormalPhaseA=true`，使用新的唯一 `authorizationId`，并保持其余路径、哈希、B=48、1536 个完整 blocks、6144 个算法-lane samples 及正式 root 完全不变。

随后允许创建唯一正式 measured root：

`Research/FormalRuns/Gate14Re/PhaseA/attempt-001`

并单次启动冻结 supervisor。必须串行执行，每个 block 使用一个 fresh Unity process，四算法在同一冻结输入内按冻结 Williams 顺序运行；每个进程硬超时 3600 秒。每个 block 最多允许一次完整 block 技术性 replacement；不得在算法内部 retry/resume，不得 top-up、merge、skip 或 reorder。仅完整、通过结构验证的四算法 block 可被采纳；任何 block 在一次 replacement 后仍失败，立即 fail closed 并停止。

完成 1536 个 blocks 后，只允许停在 `FORMAL-PHASE-A-ACQUISITION-COMPLETE / FORMAL-PHASE-A-RAW-COMMIT-PENDING`，随后可完成独立结构性 raw commit 与只读冻结，但不得在本授权下解释、排序或公布 M1–M5 结果。

本授权不包含正式结果分析、赢家裁决、Phase B、Gate 15V-R/OBS，也不允许改变四算法、M1–M5、B=48、32 个设计单元、N 水平、动态事件、场景、渲染环境、Williams 顺序、统计规则或硬超时。任何科学设计变化或不可解释的冻结 hash drift 必须停止并另报。
