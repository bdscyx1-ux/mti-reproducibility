# Gate14Re-ME Unity executable identity discrepancy audit attempt-003 plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-unity-executable-identity-discrepancy-audit-attempt-003`
- Preserved parents: attempts 001 and 002
- Stage: one-time replay of the original isolated algorithm-free Unity executable identity probe
- Unity: `H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe`
- Expected external SHA-256: `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`

## Authorized cause and repair

Attempt-002 failed before Unity launch with `unityInvocationCount=0`. The already-repaired return expression reached line 302, but the preceding `-match` operator updated PowerShell's automatic `$Matches` variable. PowerShell variable names are case-insensitive, so the local `$matches` array was overwritten before it was returned.

Attempt-003 may only rename that local variable and its references inside `Get-HashValue`:

```powershell
$hashMatches = @(...)
Require-Condition (... $hashMatches ...)
return [string]($hashMatches[0].sha256)
```

The regular expression, success predicate, selected hash value, audit observations, classification logic, trusted-rule logic, hold duration and Unity execute method remain unchanged.

## Preservation boundary

Every frozen source and failure-evidence file from attempts 001 and 002 remains at its existing path, byte-identical and read only. The attempt-003 preexecution manifest binds both complete eight-file sets, together with the original protected schema-corrigendum evidence.

## Authorized sequence

1. Re-hash both prior eight-file frozen sets and verify that all 16 files remain read only.
2. Verify that the attempt-003 evidence root and status v15 do not exist, no Unity process is active, and no Gate14Re-ME measured root exists.
3. Freeze the attempt-003 authorization, this plan, diagnostic-source copy, orchestrator copy and preexecution manifest.
4. Verify that the only semantic orchestrator change is the `$matches` to `$hashMatches` local-variable rename; all remaining differences must be mechanical attempt/status routing.
5. Invoke the frozen attempt-003 orchestrator once. It may launch `DDM.Research.Editor.UnityExecutableIdentityAuditAttempt001.Gate14ReMEUnityExecutableIdentityAuditV1.Run` no more than once.
6. Do not signal, forcibly terminate, repair or retry Unity. Preserve either the successful terminal evidence or the failure receipt and status v15.
7. Re-hash both prior frozen sets after termination and verify exact preservation.

## Explicit exclusions

This authorization does not permit schema compatibility self-check, qualification or formal scheduling, input or seed generation, identity mapping, any measured-root creation, planner/oracle execution, any algorithm lane, formal collection, analysis, weighting, ranking, or winner adjudication.
