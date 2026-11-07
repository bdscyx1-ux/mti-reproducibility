# Gate 10R attempt 3 retained-regression failure checkpoint

Saved: 2026-10-06 22:19 (Asia/Shanghai)

## Terminal state

Gate 10R attempt 3 consumed its one authorized official execution and stopped fail-closed at the retained-regression gate. Status is:

`GATE10R-ATTEMPT3-FAILED-NO-AUTO-RETRY`

There is no active Unity process and no project `UnityLockfile`. The final audit was not started. Gate 11R and Gate 12R were explicitly unauthorized by the user and were not started. Gate 13R remains unauthorized and absent.

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run / validate`
- Verification Status: `FAILED-NO-AUTO-RETRY`
- Version Label: `gate10r_attempt3_retained_wrapper_scope_failure_v3`
- Stable Run ID: `gate10r-to-gate12r-execution-v1`
- Active design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Attempt-3 verification root: `Research/Verification/Gate10R_ProcessReuse_5pct/v3`
- Formal campaign: false

## Gate 10-only authorization boundary

The user authorized Gate 10 only and revoked Gate 11/12 authorization:

> 授权Gate 10，取消Gate 11,12的授权，先解决目前的问题，解决完后向我要后续工作授权

- Authorization source SHA-256: `58c4690cd5d3ce17f9a1b7a8f91def3893985a9609420f945ecdaca74f6817d6`
- Attempt-3 authorization: `Research/Gate10R_Attempt3_Execution_Authorization.v1.json`
- Attempt-3 execution receipt SHA-256: `32b4632ac3362f38d6e86fe8e7797f8c344392de2c4ddd3a3adb2538b940609e`
- Maximum official executions: 1
- Official executions consumed: 1

## Attempt-2 lock problem: resolved

Attempt 3 froze and enforced the following lock policy:

- compile, telemetry, positive block and cold-reference processes must release the lock naturally;
- no cleanup is allowed for those roles;
- only the exact pre-existing attempt-2 stale lock and an owned expected-negative fixture may be cleaned;
- cleanup requires a 60-second natural-quiescence wait, no owned PID, zero total Unity processes, the exact project lock path, a leaf/non-reparse file, zero bytes, the canonical empty-file SHA-256, exclusive read-write access, and timestamps inside the owned process window with the frozen tolerance;
- pre-delete capture and post-delete completion receipts must be written atomically.

The preflight passed `67/67`, captured and removed only the attempt-2 stale lock, and proved the remaining Temp content plus attempt-1/attempt-2 trees unchanged.

- Pre-existing lock capture receipt SHA-256: `33196d3865aaca07c0ba0a7ef9626338ff08a9be8d28eb599b8be95b80826355`
- Pre-existing lock completion receipt SHA-256: `0de035e2af5e566b1c70ddb9231c1295e053b0fb72bba02317486839d5a60a5c`

The official block transition then passed:

- positive Williams blocks: 3/3, distinct Unity PIDs `19504`, `31800`, `31044`;
- expected-negative block: atomic stop after one completed sample, PID `18872`;
- expected-negative lock mode: `controlled-expected-negative-cleanup` after the full wait and predicates;
- fresh cold references: 6/6, all with `natural-lock-absence`;
- structural comparisons: 10/10;
- structural mismatches: 0;
- independent-process repeatability: passed;
- terminal Unity process count: 0;
- terminal project lock: absent.

Therefore the attempt-2 negative-fixture → cold-control lock-transition defect is solved and independently evidenced.

## Other completed attempt-3 gates

1. Windows PowerShell 5.1 parser and parameter-binding preflight: passed.
2. No-Unity attempt-3 preflight: `67/67`.
3. Gate 10R unit tests: `59/59`.
4. Unity compilation: passed, PID `24392`, lock released naturally.
5. PSAPI/CIM telemetry probe: passed, PID `31264`, lock released naturally.
6. Full process-reuse block/cold/structural/lock verification: passed.

These are verification fixtures only. They are `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS` and cannot be used for formal inference or candidate `n_formal`.

## New hard-gate failure

The retained-regression child process exited 0 internally and reported no assertion failure, but its generated summary contained:

- `passed = true`;
- `failures = []`;
- `assertionCount = 0`;
- required assertion count: `63`.

The versioned Gate 10R wrapper therefore returned exit code 1 and stopped the attempt before final audit.

Confirmed cause: the wrapper piped the frozen source into a child `ScriptBlock`. In that invocation form, the source's local `$assertions` and the helper functions' `$script:assertions` belong to different scopes under Windows PowerShell 5.1. A read-only synthetic probe under the same entry form returned `{"localAssertions":0,"scriptAssertions":1}`.

The original retained evidence remains byte-identical and still records 63/63 passed:

- `Research/Verification/Gate12_AnalysisUnitTests.summary.json`
- SHA-256: `1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d`

Detailed diagnosis:

- `Research/Gate10R_Attempt3_RetainedRegression_Failure_Diagnosis.v1.md`
- SHA-256: `cf70bfa21b3f47e5e0eca63d0ae5bcfefca6eda93b82461a115424fc12707fb4`

This is a versioned orchestration-wrapper scope defect, not an algorithm, Unity compilation, telemetry, reset, Williams-order, structural-equivalence, or lock-hygiene failure.

## Frozen attempt-3 evidence

- Partial-output manifest: `Research/Verification/Gate10R_ProcessReuse_5pct/v3/Gate10R_Attempt3_Partial_Output_Manifest.v3.json`
  - artifacts: `162`
  - raw bytes: `14,598,617`
  - SHA-256: `1c0a4aa737e217cd93bb35d5cfa8cc3286bb8954b8df56320c88c03c5632979c`
- Failure receipt: `Research/Verification/Gate10R_ProcessReuse_5pct/v3/Gate10R_Attempt3_Failure_Receipt.v3.json`
  - SHA-256: `e697d3a9fef4272298cd76faeaf7f63e369f657b8fb1937e7c375df97cf5d64e`
- Terminal checkpoint: `Research/Verification/Gate10R_ProcessReuse_5pct/v3/gate10r-checkpoint.json`
  - SHA-256: `e25faf1cdf6892a5468e45248216f1b15676b05b5e6ef8c9d8d46c466d0a9010`

The manifest was independently re-read after closure: all 162 artifact paths, byte counts, and SHA-256 values matched.

## Downstream state

- Gate 11R authorization: revoked / false
- Gate 11R formal-scenario root: absent
- Gate 11R Playable roots: absent
- Gate 12R authorization: revoked / false
- Gate 12R pilot root: absent
- Gate 13R authorization: false
- Gate 13R formal root: absent
- Gate 10R final audit: not started

## Exact resume point

Do not retry or resume attempt 3. Do not append to `v3`. Do not run its final audit. Do not start Gate 11R, Gate 12R, or Gate 13R.

A future Gate 10R attempt requires new explicit authorization and a new versioned root. The narrow repair should:

1. preserve attempts 1–3 byte-for-byte;
2. preserve the original Gate 12 test script and original 63/63 summary byte-for-byte;
3. create a versioned file-scope retained-regression harness, mechanically derived from the frozen source with only explicit project/output routing changes;
4. execute that harness using Windows PowerShell 5.1 `-File`, not a child `ScriptBlock` from standard input;
5. prove the derived test body is semantically/structurally identical and produces 63/63 in an isolated non-original output;
6. re-run the complete Gate 10R hard-gate sequence exactly once only after parser/binding/root-isolation/history-integrity checks pass;
7. remain no-auto-retry/no-resume and keep Gate 11R/Gate 12R unauthorized.

## Suggested next authorization text

```text
授权 Gate 10R attempt 4 的受控、版本化 retained-regression wrapper 修复与一次重试；不授权 Gate 11R、Gate 12R 或 Gate 13R。

完整保留 Gate 10R attempts 1–3 的全部 root、receipt、manifest、checkpoint、日志和哈希，不得修改、覆盖、resume 或重新解释。只允许修复 attempt 3 已确认的 Windows PowerShell 5.1 child-ScriptBlock 作用域缺陷：在新的 v4 文件中，以 file/script scope 执行从冻结 `Run-Gate12AnalysisUnitTests.ps1` 机械派生的测试 harness，只改变显式 ProjectPath 与隔离 summary 输出路由；原测试脚本和原 63/63 summary 必须保持字节不变。

先在全新 `Research/Verification/Gate10R_ProcessReuse_5pct/v4` 根外完成 parser、参数绑定、机械变换差异、原证据不变性、输出隔离和 63/63 validation-only smoke；全部通过后才创建 v4 root 和一次性 execution receipt，并按冻结顺序完整执行 Gate 10R。不得改变算法、Unity command、process-reuse、Williams 顺序、reset、telemetry、lock-hygiene、5% 精度、无 cap 或 Playable 语义。任一硬门禁失败时保存原子失败证据后停止，禁止自动 retry/resume。成功后停止并向我请求 Gate 11R 或其他后续工作的单独授权。
```
