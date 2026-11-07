# Gate14Re-ME Unity executable identity discrepancy audit plan v1

- Study: Gate14Re-ME
- Authorization: `gate14re-me-unity-executable-identity-discrepancy-audit-attempt-001`
- Stage: algorithm-free Unity executable identity discrepancy audit
- Unity: `H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe`
- Expected external SHA-256: `0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf`

## Objective

Explain, at the level needed for a trustworthy execution-control rule, why schema compatibility corrigendum attempt-001 observed the expected SHA-256 outside the Unity process before launch and after exit while the running editor obtained a different SHA-256 from `EditorApplication.applicationPath`. Preserve attempt-001 exactly, run no schema or algorithm work, and freeze one fail-closed identity rule supported by contemporaneous observations.

## Isolation boundary

The audit uses a new minimal Unity project created only beneath the evidence-only verification root. The project contains only the frozen identity probe and minimal Unity project metadata. It does not import the Gate14Re-ME project Assets, Packages, schema self-check, planner, oracle, runner, or algorithms. Unity-generated project cache files therefore remain isolated from the scientific project and are not measured data.

## Authorized sequence

1. Verify the authorization, this plan, status v12, and every file beneath the prior schema-compatibility-corrigendum attempt-001 root. Record a complete pre-audit inventory of paths, lengths, attributes and SHA-256 values.
2. Verify the installed Unity executable as a regular non-reparse file. Record normalized path, file ID, length, timestamps, Authenticode status and signer, PE identity fields, independent external SHA-256 calculations, and 64-KiB chunk hashes.
3. Refuse to start if any Unity process already exists, any prohibited Gate14Re-ME measured root exists, any protected hash drifts, or this evidence root already exists.
4. Create the evidence root and an isolated minimal Unity audit project. Copy the frozen diagnostic source into that project without modifying the Gate14Re-ME Unity project.
5. Launch exactly one hidden Unity batchmode process with only the permitted identity-probe execute method. Capture its PID, creation time, executable path and exact command line.
6. In process, record `EditorApplication.applicationPath`, `Process.MainModule.FileName`, Win32 `QueryFullProcessImageName`, Win32 file identity, PE identity fields, three independent managed read/hash paths, 64-KiB chunk hashes, the standard SHA-256 `abc` known answer, and a file-length zero-stream SHA-256 known answer. Publish a ready snapshot and hold the process for 30 seconds.
7. While that exact PID remains alive, take a second external executable fingerprint. After the probe's normal self-exit, take a third external fingerprint. Do not signal, terminate, or retry the process.
8. Compare paths, file IDs, metadata, whole-file hashes, chunk hashes and known-answer results. Classify the discrepancy without claiming a deeper OS or vendor cause not established by the evidence.
9. Reinventory the prior attempt and verify exact equality with the pre-audit inventory. Verify that no prohibited roots or outputs were created and no prohibited process or execute method ran.
10. Remove only regenerable `Library`, `Temp`, `Logs`, `obj`, and `UserSettings` directories from the isolated audit project after Unity has exited, after resolving and verifying each exact deletion target beneath that project. Preserve and freeze its source, project metadata, Unity log, receipts, observations, source/tool manifest, terminal receipt, one identity-verification rule, and status v13. Mark the new immutable files read only.

## Interpretation rules

- If synthetic SHA-256 known answers fail, classify the hashing implementation as untrustworthy; do not infer a file difference.
- If known answers pass, all in-process read/hash methods agree, the live external view retains the expected hash, path and file ID agree, and chunk hashes differ, classify the observation as a process-local executable byte-read-view difference. This is an operational explanation, not a claim about an unobserved kernel, security product, or Unity-internal root cause.
- If the live external view changes, classify transient on-disk mutation and fail closed.
- If path or file ID differs, classify alternate executable identity and fail closed.
- If the prior discrepancy does not reproduce, retain the observations and fail closed; do not manufacture an explanation or retry.

## Candidate trustworthy rule

The external controller's prelaunch hash is authoritative only when two independent external hash implementations agree with the frozen expected value for the exact normalized regular-file path and stable file ID. The launched process is then identified by the tuple `(PID, creation time, executable path, exact command line, execute method, isolated project path)` and the same externally resolved executable file identity. In-process self-hashing is diagnostic, not authoritative. After normal exit, the controller must reconfirm the same path, file ID, length and expected external hash. Any mismatch fails closed and consumes the attempt without retry.

## Explicit exclusions

This stage does not invoke `Gate14ReMEInputSchemaCompatibilitySelfCheckV1.Run`; does not validate or adopt a schema; does not create a qualification schedule, input, seed set, geometry, identity map or measured root; does not construct or invoke a planner or oracle; does not execute an algorithm lane; and does not perform collection, analysis, ranking, weighting, or winner adjudication.
