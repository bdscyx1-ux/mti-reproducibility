# Gate 11R Preimplementation Failure Checkpoint

Saved: 2026-10-07 (Asia/Shanghai)

## Outcome

Gate 11R stopped at the first outside-root preimplementation hard gate. Terminal state:

```text
GATE11R-FAILED-NO-AUTO-RETRY-NO-RESUME
```

The audit passed 73 of 74 checks. It did not start Unity, create the official Gate 11R verification root, generate a scenario, generate a Playable asset, or enter Gate 12R/Gate 13R.

## Failed check and diagnosis

The failed check was the protected-tree identity of:

```text
Research/PilotRuns/Gate13_ProcessReuse/v1
```

Both runtimes observed exactly 838 files and 91,219,643 raw bytes. The PowerShell 7.6.5 prewrite calculation returned tree SHA-256 `652c0cc0a66b62d1adfb8d4f71e0edc27e5804caaf18be49c5c30a4633b210ca`; Windows PowerShell 5.1 returned `20f151c53bbc979a0e14f988edd6ae717e0e8c128b33b492b4dfb922fc3924cc`.

The tree function sorted full paths with the current PowerShell runtime's default `Sort-Object` semantics. On this 838-file tree, PowerShell 7 and Windows PowerShell 5.1 produced different row order. The failure therefore identifies a noncanonical cross-runtime audit wrapper, not proven protected-file modification. Under the frozen fail-closed rule, equal count and byte totals are insufficient to reinterpret the failed check as passed.

## Preserved evidence

- Structured audit: `Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Audit.summary.v1.json`
- Diagnostic log: `Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Failure.diagnostic.log`
- Failure receipt: `Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Failure_Receipt.v1.json`
- Partial manifest: `Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Partial_Manifest.v1.json`
- Atomic checkpoint: `Research/Verification/Gate11R_5pct_PreImplementation/v1/gate11r-preimplementation-failure.checkpoint.v1.json`

The Gate 11R specification and test design were frozen before the failure and remain non-production planning evidence. All three Gate 11R production roots and the official Gate 11R verification root remain absent.

## Required next authorization

No retry or resume is authorized. A suitable next instruction is:

> 授权 Gate 11R attempt 2 的受控、版本化审计修复与一次重试；完整保留 Gate 11R preimplementation attempt 1 的 summary、diagnostic、receipt、manifest 和 checkpoint，不得覆盖、修改、resume 或重新解释。只允许在新的 v2 审计脚本中，将 protected-tree identity 改为以标准化相对路径进行 `StringComparer.Ordinal` 排序，并逐文件比较 relative path、bytes 和 SHA-256；先在 PowerShell 7 与 Windows PowerShell 5.1 交叉证明同一树得到相同 identity。全部 outside-root 门禁通过后，才按已冻结的 Gate 11R v1 specification/test design 继续一次 Gate 11R 生成与验证；不得启动 Gate 12R 或 Gate 13R。任一硬门禁失败时原子保存新的失败证据后停止，禁止自动 retry/resume。
