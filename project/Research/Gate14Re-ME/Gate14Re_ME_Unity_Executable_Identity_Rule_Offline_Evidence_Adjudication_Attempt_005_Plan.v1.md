# Gate14Re-ME Unity executable identity rule offline evidence adjudication attempt-005 plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-unity-executable-identity-rule-offline-evidence-adjudication-attempt-005`
- Retained failed parent: `gate14re-me-unity-executable-identity-rule-repair-attempt-004`
- Input evidence root: `Research/Verification/Gate14Re-ME/unity-executable-identity-rule-repair-attempt-004`
- Output root: `Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005`
- Maximum Unity invocations: **0**
- Method: deterministic, offline, evidence-only adjudication

## Purpose

Attempt-004 remains formally failed closed and not adjudicated because its PowerShell orchestrator raised an empty-directory `Measure-Object.Sum` bookkeeping exception after the isolated Unity process had already exited and after the post-exit fingerprint had been persisted. Attempt-005 does not repair or rerun attempt-004. It independently adjudicates the already-frozen attempt-004 identity evidence and, only if every authoritative condition is satisfied, freezes a new trusted launch-identity rule under the attempt-005 authorization.

## Immutable-parent rule

The adjudicator binds all 34 files currently present in the attempt-004 evidence root by relative path, byte length and SHA-256. It verifies the complete inventory before and after adjudication and requires every retained file to remain read-only. The attempt-004 failure receipt must retain `FAILED_CLOSED_UNITY_EXECUTABLE_IDENTITY_RULE_REPAIR` and `NOT_ADJUDICATED`; status v16 must retain `UNITY_EXECUTABLE_IDENTITY_RULE_REPAIR_FAILED_CLOSED`. Neither file is rewritten or reclassified.

## Authoritative evidence

The pass decision requires all of the following:

1. The external prelaunch, live-concurrent and post-exit fingerprints use the expected schemas and phases, bind the attempt-004 authorization, and occur in chronological order.
2. At each phase, PowerShell `Get-FileHash` and the independent .NET stream implementation agree on SHA-256 and equal `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`.
3. The three external 64 KiB chunk lists are exactly equal, including chunk index, offset, length and SHA-256.
4. The normalized regular-file path, NTFS file ID, file length, creation time, last-write time, attributes, PE identity and valid Authenticode signer remain stable across all three phases.
5. The process launch receipt, in-process ready snapshot and terminal Unity probe receipt agree on PID, process start time, executable path, execute method and the authorized command-line identity.
6. `EditorApplication.applicationPath`, `Process.MainModule.FileName` and `QueryFullProcessImageNameW` all identify the authorized executable path.
7. The initial and after-hold in-process structural file identities match one another and the external NTFS low-64 file identity.
8. SHA-256 known-answer tests pass; the probe reports a terminal internal pass and no schema compatibility self-check, planner, algorithm lane or measured-root activity.
9. The attempt-004 failure receipt records one Unity invocation, no retry and no signal or forced termination. The frozen V4 orchestrator hash and its control flow establish that the observed cleanup exception occurred after the normal exit-code-zero gate, terminal probe validation and post-exit fingerprint write.
10. The attempt-005 adjudicator contains no process-launch or destructive-cleanup primitive, observes no Unity process at entry or before terminal freeze, creates no measured root, and leaves the complete attempt-004 inventory unchanged.

## Diagnostic-only evidence

All in-process byte-read hashes and chunks remain available in the audit record. In particular, `File.ReadAllBytes` instability is reported but cannot authorize or veto executable identity. No explanation of the process-local byte-read discrepancy is claimed.

## Retry policy

The user's automatic-retry authorization applies only to a transparent attempt-005 adjudicator defect or transient read failure. Each failed repair cycle, if any, must be retained. A deterministic missing file, hash mismatch, structural mismatch or prohibited activity is a fail-closed scientific result and may not be retried by altering evidence or weakening a condition.

## Outputs on pass

- `offline-evidence-adjudication.v1.json`
- `trusted-launch-identity-rule.v1.json`
- `terminal-receipt.v1.json`
- `source-and-evidence-freeze-manifest.v1.json`
- `Research/Gate14Re-ME/Gate14Re_ME_Status.v17.json`

All attempt-005 sources and outputs are set read-only after verification.

## Explicit exclusions

No Unity launch, cleanup, deletion, D3 change, schema compatibility self-check, schedule, input, seed, anonymous identity mapping, measured root, planner, oracle, algorithm lane, collection, statistical analysis, weighting, ranking or winner adjudication is permitted.
