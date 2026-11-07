# Gate13R-AX2 next formal collection authorization prompt v1

## Preconditions already satisfied

- Final readiness: `FINAL-READINESS-PASS`
- Final readiness receipt: `Research/Verification/Gate13R-AX2/precollection-readiness-v1/final-readiness.v1.json`
- Final readiness SHA-256: `ec6d7634e830aaf51bfb5fbbe01cb1a1fdd20256aa13cee05e514ace52b27482`
- No Gate13R-AX2 formal collection has been started.
- Non-formal verification samples are excluded from every future formal attempt.

## Exact authorization text

> 按 `next-formal-collection-authorization-prompt.v1.md` 授权 Gate13R-AX2 Phase A attempt-001 单次正式采集，并授权采集完成后执行独立结构性 raw commit 与只读冻结。严格绑定 32 个 shared-goal campaigns、每 campaign B=48、四处理 Williams schedule、1536 个完整 blocks、6144 个匿名样本，以及 BiA*-R、LPA*、C-FF、IDFF；每个完整四处理 block 使用一个 fresh Unity process，block 内严格串行，最多一次 whole-block 技术 replacement，禁止逐算法 retry/resume/top-up/merge/skip/reorder。正式 P1 分析、算法排名、赢家裁决及任何后续实验仍未授权；raw commit 成功后停止并向我请求下一步授权。

## Frozen bindings for the future authorization receipt

- Intended measured root: `H:/DDM_Final_Project/Research/FormalRuns/Gate13R-AX2/PhaseA/attempt-001`
- Schedule SHA-256: `3ea4198796bc5024194fb52f5e1c43ccbb51bf557186993b3703c19c2787838b`
- Output schema SHA-256: `de90d9bbfd72104e3176dd223e565a032ad6c0b21d098af2fbe7388ad2378a70`
- Execution contract v3 SHA-256: `9e4a127d5410b02e33e9b5f6e77d5a0fc6e4e637cbd9dc10b03e59e63aef03eb`
- Block runner source SHA-256: `11d2087032b5e09c7761a69f6a8ce963dbea5a19ebc9b09012a483c510b40e62`
- Supervisor SHA-256: `08902326d5aeb7ff7a7ce8210514923bac4fab1f3f240b877f39cc1f5c387354`
- Structural validator SHA-256: `af0298440e786af07425cb42c6f03c9c3e11812dd0eeb981fceb503eea4cb8c3`
- Raw-commit tool SHA-256: `38a47fb6f831350c66f85346f4f4b378ecb87dfd681e3d86ae9840c488790663`
- Frozen P1 analysis implementation SHA-256: `ab69d02ec61d348ed176b8616390968704ed4be72a53432d26ff463fe4c24e89` (not authorized to execute by this prompt)
- Runtime assembly SHA-256: `656ff839dfcc528d44815fc7be74c2a56eaa8af7ad2b1c5db8c28797f529bd67`
- Editor assembly SHA-256: `7c3efd1a0f9b7cddffc1e1a88ada025db72ce484a03752a8d954d77eb580e128`
- Unity executable SHA-256: `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`
- Python executable SHA-256: `b847bb9f4e48c19f585c8bf7d8b355f3f8c6d2125717ece9c9d7e16fb9f09de8`
- PowerShell executable SHA-256: `362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139`

## Fail-closed boundary

Before launch, create a versioned authorization receipt and external launch receipt that bind the exact authorization text, measured root, readiness receipt, and every frozen hash above. The measured root must not already exist. Any hash drift, existing root, identity mismatch, unexplained structural anomaly, or failed block after its one authorized whole-block replacement must stop the attempt without whole-attempt restart, sample reuse, or creation of attempt-002.

The independent raw commit may validate only schema, cardinality, paths, hashes, process identities, Williams order, replacement ledger, and the finite-positive presence of P1. It must not aggregate or interpret P1. Formal P1 analysis, algorithm ranking, and winner adjudication require a later explicit authorization.
