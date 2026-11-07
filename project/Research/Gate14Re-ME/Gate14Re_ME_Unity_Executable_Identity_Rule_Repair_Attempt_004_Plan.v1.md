# Gate14Re-ME Unity executable identity rule repair attempt-004 plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-unity-executable-identity-rule-repair-attempt-004`
- Preserved parents: identity audits attempts 001, 002 and 003, plus the earlier schema-compatibility-corrigendum evidence
- Stage: one-time isolated algorithm-free Unity trusted-launch identity rule repair
- Unity: `H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe`
- Expected external SHA-256: `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`

## Why this repair is necessary

Attempt-003 established that the executable path, file length, timestamps, NTFS file identity, PE identity, external full-file hashes, external chunk hashes, in-process `File.OpenRead` hash, in-process shared-stream hash and in-process chunk hashes were stable. Only the in-process `File.ReadAllBytes` whole-file hash changed across the hold. The old rule incorrectly collapsed all in-process byte-read methods into one authority gate, so that diagnostic-only instability failed the probe even though the externally observed executable and live process identity were stable.

Attempt-004 repairs the identity rule rather than D3. No D3-v3.1 source, binary, contract, qualification receipt, runner integration or schema artifact may change.

## Authoritative launch identity

The trusted rule passes only when all of the following hold:

1. External prelaunch, live-concurrent and post-exit fingerprints each have two agreeing full-file SHA-256 implementations equal to the frozen expected hash.
2. All three external 64 KiB chunk sets, normalized path, NTFS file ID, file length, timestamps, PE identity and Authenticode signer remain stable.
3. The launched process is bound by PID, creation time, executable path and exact command line containing the authorized execute method and isolated project.
4. `EditorApplication.applicationPath`, `Process.MainModule.FileName` and `QueryFullProcessImageNameW` resolve to the same authorized path.
5. The in-process structural identity—path, length, timestamps, attributes, NTFS file identity and PE identity—remains stable across the 30-second observation hold.
6. Exactly one isolated algorithm-free Unity invocation occurs, exits naturally with code 0, and leaves no Unity or prohibited Gate14Re-ME process.

## Diagnostic-only observations

The probe still captures both initial and after-hold values for:

- SHA-256 over `File.OpenRead`;
- SHA-256 over a shared `FileStream`;
- SHA-256 over `File.ReadAllBytes`;
- 64 KiB in-process chunk digests;
- SHA-256 known answers.

These values remain available for diagnosis. None of the in-process file-read hashes or chunks may authorize or veto executable identity by itself. The known-answer checks remain a probe-integrity guard, and the structural identity fields remain part of the composite process identity.

## One-shot sequence

1. Verify the attempt-003 evidence inventory against its frozen 33-file digest and verify all attempt-004 source-manifest bindings.
2. Verify that attempt-004 evidence root and status v16 do not exist, no Unity process is active, and no prohibited Gate14Re-ME measured root exists.
3. Freeze the attempt-004 authorization, this plan, C# probe, PowerShell orchestrator and source manifest.
4. Launch one and only one isolated algorithm-free Unity identity probe.
5. Capture external fingerprints before launch, while the same PID is alive, and after natural exit.
6. Adjudicate only the authoritative external and composite-process conditions; retain all in-process byte-read results as diagnostic evidence.
7. On pass, freeze `trusted-launch-identity-rule.v1.json`, the terminal receipt, status v16 and the complete evidence manifest. On any failure, freeze the exact failure receipt and status v16 without retry.

## Explicit exclusions

This authorization does not permit a schema-compatibility self-check, qualification or formal scheduling, input or seed generation, identity mapping, measured-root creation, planner or oracle execution, any algorithm lane, formal collection, formal analysis, weighting, ranking, or winner adjudication.
