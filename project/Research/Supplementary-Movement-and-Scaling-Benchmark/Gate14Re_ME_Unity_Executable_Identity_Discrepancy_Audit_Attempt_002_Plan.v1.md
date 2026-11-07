# Gate14Re-ME Unity executable identity discrepancy audit attempt-002 plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-unity-executable-identity-discrepancy-audit-attempt-002`
- Parent attempt: `unity-executable-identity-discrepancy-audit-attempt-001`
- Stage: one-time replay of the original isolated algorithm-free Unity executable identity probe
- Unity: `H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe`
- Expected external SHA-256: `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`

## Authorized cause and repair

Attempt-001 failed closed before Unity launch. Its failure receipt records `unityInvocationCount=0` and the exact PowerShell error produced by `return [string]$matches[0].sha256` in `Get-HashValue`. Attempt-002 is limited to the precedence-safe expression `return [string]($matches[0].sha256)`.

No audit measurement, observation field, classification branch, identity rule, hold duration, Unity execute method, or process-control policy may change. Versioned authorization IDs, paths and status links are mechanical evidence-routing changes only.

## Preservation boundary

All attempt-001 sources and evidence remain at their existing paths, byte-identical and read only. The attempt-002 preexecution manifest must bind the complete attempt-001 frozen set: authorization, plan, probe source, orchestrator, preexecution manifest, failure receipt, prior-attempt inventory, and status v13. The manifest also retains the original protected schema-corrigendum bindings used by the audit.

## Authorized sequence

1. Verify the complete attempt-001 frozen set by path, length and SHA-256, and verify that the attempt-002 evidence root and status v14 do not exist.
2. Verify that no Unity process is active and that no Gate14Re-ME pilot, qualification, formal, or other measured root exists.
3. Freeze the versioned attempt-002 authorization, this plan, the diagnostic-source copy, the orchestrator copy, and a preexecution manifest. Record the hashes after the single authorized expression repair.
4. Prove by normalized source comparison that the diagnostic observation method is unchanged and that the orchestrator delta contains only the authorized repair plus mechanical attempt/version evidence routing.
5. Invoke the frozen attempt-002 orchestrator once. It may launch the unchanged execute method `DDM.Research.Editor.UnityExecutableIdentityAuditAttempt001.Gate14ReMEUnityExecutableIdentityAuditV1.Run` no more than once.
6. Do not signal or forcibly terminate Unity. Do not retry. On success, preserve the original terminal audit evidence and status v14. On any failure, preserve the failure receipt and status v14 and stop.
7. Re-hash the complete attempt-001 frozen set and verify exact equality with the preflight bindings.

## Explicit exclusions

This authorization does not permit schema compatibility self-check, qualification or formal scheduling, input or seed generation, identity mapping, any measured-root creation, planner/oracle execution, any algorithm lane, formal collection, analysis, weighting, ranking, or winner adjudication.
