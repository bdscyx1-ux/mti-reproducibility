# Gate 13 Formal Launch Attempt 1 Checkpoint

Saved: 2026-10-06 12:33:08 +08:00  
Status: failed before formal-root creation; no automatic retry performed  
Attempt ID: `gate13-formal-launch-attempt-1`

## Material Passport

- Origin Skill: `experiment-agent`
- Origin Mode: `run`
- Origin Date: `2026-10-06`
- Verification Status: `OBSERVED-FAILED-BEFORE-FORMAL-ROOT`
- Version Label: `gate13_formal_launch_attempt1_v1`

## User authorization and frozen identity

The user explicitly authorized Gate 13 formal execution on 2026-10-06 and accepted the frozen 74-campaign / 15,056-sample / p95 67.6672-hour schedule, the exact config/amendment/output-root binding, the raw-byte launch gate, and the no-automatic-retry/no-automatic-resume rule.

| Artifact | Identity |
|---|---|
| Formal config | `Research/Gate13_Formal_Campaign_Config.v1.json` |
| Config SHA-256 | `b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874` |
| Amendment SHA-256 | `1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2` |
| Attempt-1 receipt | `Research/Gate13_Execution_Authorization.v1.json` |
| Receipt SHA-256 | `864740f428c8a0c40c9883c9b9a77988968e68610cf19d48d61529959ec95cc8` |
| Bound output root | `Research/FormalRuns/Gate13/v1` |

The receipt passed `Test-Gate13ExecutionAuthorization` before the launch attempt.

## Prelaunch observations

The first validation-only snapshot found one zero-byte `Temp/UnityLockfile`. There was no Unity/Unity Hub process, and the file admitted an exclusive-open handle, proving that no process held it. It was preserved rather than deleted:

- quarantine path: `Research/Verification/Gate13_Prelaunch_Quarantine/UnityLockfile.stale.20261006T122935+0800`;
- bytes: `0`;
- SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

After relocation, a second top-level `-ValidationOnly` invocation passed completely:

- config SHA and amendment SHA matched;
- 74 campaigns / 15,056 samples / cap 148 matched;
- AC line status: online;
- active power scheme: High performance, GUID `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`;
- free physical memory: `21,786,931,200 bytes`;
- CPU samples: `2, 23, 0, 3, 8 percent`; mean `7.2%`;
- temperature telemetry: unavailable, advisory-only as preregistered;
- Unity process count: `0`;
- Unity lockfile: absent;
- formal root before and after validation: absent;
- H: available free space: `162,195,136,512 bytes`;
- minimum launch requirement: `74,417,330,489 bytes`;
- margin: `87,777,806,023 bytes`.

## Attempt-1 failure

The formal top-level command was invoked once in a hidden Windows PowerShell 5.1 process. It exited during `Test-Gate13FormalConfig`, before receipt validation inside the runner, before launch preflight, before formal-root creation, and before any Unity process or timing sample.

Observed failure:

```text
Gate 13 config validation failed: Expected config could not be reconstructed:
Get-FileHash was not recognized as a cmdlet.
```

Evidence:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Research/Verification/Gate13_Formal_Launch.v1.stdout.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `Research/Verification/Gate13_Formal_Launch.v1.stderr.log` | 842 | `5688fb7a5387bfba8223a8165c4f7765ed3f5ac34252d8b57e4630607f5f1b99` |

Terminal state after failure:

- top-level orchestrator process: absent;
- scenario campaign process: absent;
- Unity process: `0`;
- `Temp/UnityLockfile`: absent;
- `Research/FormalRuns/Gate13/v1`: absent;
- formal checkpoint: absent because the root was never created;
- completed campaigns: `0`;
- completed formal samples: `0`;
- automatic retry attempted: `false`.

## Diagnosed cause

The active Codex host runs PowerShell 7.6.5. Its parent `PSModulePath` places this PowerShell 7 module directory before Windows PowerShell modules:

```text
C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\Modules
```

`Start-Process` inherited that combined path unchanged into Windows PowerShell 5.1. Windows PowerShell therefore discovered the incompatible PowerShell 7 `Microsoft.PowerShell.Utility` v7.0.0 before its native v3.1.0 module, and `Get-FileHash` autoload failed. This explains why a directly invoked Windows PowerShell validation process passed while the hidden detached process failed.

Diagnostic evidence:

- hidden unsanitized lookup failure: `Research/Verification/Gate13_PowerShell_Hidden_Diagnostic.v1.stderr.log`, SHA-256 `fc2b9f9e8b265bd7fb26333e665e9299345205c380fcb3dbfa7865a1613257a0`;
- inherited module inventory: `Research/Verification/Gate13_PowerShell_Hidden_Diagnostic.v2.stdout.log`, SHA-256 `729e5e4489cdae1a5d844e8d191082903e465cce32212faaa758db0ba3168e0f`;
- sanitized hidden lookup success: `Research/Verification/Gate13_PowerShell_Hidden_Diagnostic.v3.stdout.log`, SHA-256 `41e512c82d1376c21b73bf13ab86c0276dcbbc4741b7797d39f04550871efdda`.

The nonexecuting diagnostic proved that a hidden Windows PowerShell child resolves native `Get-FileHash` v3.1.0 successfully when its launch environment uses only:

```text
C:\Users\bdscy\Documents\WindowsPowerShell\Modules;
C:\Program Files\WindowsPowerShell\Modules;
C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules
```

No production runner, frozen config, original script, original scene, Gate 11 bundle, Gate 12 archive, amendment or preparation artifact was modified to diagnose this issue.

## Exact resume boundary

Do not overwrite or reuse the attempt-1 receipt/log filenames. Do not automatically retry this attempt.

The next permitted formal action requires a new explicit user retry authorization. After that authorization:

1. retain the attempt-1 receipt, logs, diagnostics and this checkpoint unchanged;
2. create a new attempt-2/version-2 execution receipt bound to the same config SHA, amendment SHA and output root;
3. launch Windows PowerShell with the verified native Windows PowerShell module path, without modifying the frozen Gate 13 runners;
4. rerun receipt/config/frozen-hash, AC/power/memory/CPU/no-Unity/no-lock and raw-byte storage checks;
5. create the formal root only if every check passes;
6. preserve the same no-overwrite, no-automatic-retry and no-automatic-resume rules.

Suggested explicit retry authorization:

```text
授权重试 Gate 13 正式启动：保留 `Research/Gate13_Execution_Authorization.v1.json`、attempt-1 日志、诊断和检查点不变；创建绑定相同 config/amendment/output root 的 attempt-2 versioned receipt，仅在启动子进程时使用已验证的 Windows PowerShell 5.1 原生 `PSModulePath`。重新运行全部 receipt、hash、环境和 raw-byte storage preflight，全部通过后才创建 formal root 并继续 74 campaigns / 15,056 samples。禁止自动 retry/resume；再次失败时保存新 attempt 证据后停止。
```
