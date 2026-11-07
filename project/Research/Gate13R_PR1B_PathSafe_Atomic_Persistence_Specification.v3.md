# Gate 13R-PR1B v3 Path-Safe Atomic Persistence Specification

Status: `FROZEN-BEFORE-IMPLEMENTATION / NON-FORMAL / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## Scope and provenance

This additive v3 repair addresses only the Windows/Mono path-length failure that terminated the immutable v6 pilot. The v6 root remains `FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`, warm-up-only, without measured observations, and excluded from every estimator. The v2 Unity command, wrappers, v9-v11 verification roots, and all upstream Gate 10R/11R/12R evidence remain byte-frozen.

The observed v6 IDFF temporary evaluation path was 260 characters and failed in `System.IO.File.WriteAllText`; the corresponding C-FF path was 259 characters and succeeded. The final evaluation path was 223 characters. The defect arose because v2 appended `.tmp-<GUID>` to the complete final filename.

## Atomic persistence contract

Every v3 JSON commit resolves and validates the allowed output root, final path, and existing parent before any write. The final path must be a leaf within the allowed root. The allowed root and every existing directory from that root to the final parent must be ordinary directories, not reparse points, and their full-path identities must remain stable. Missing parents, containment escapes, directories at the final path, and reparse traversal fail closed.

The temporary file is created in the final file's verified directory with `FileMode.CreateNew`, `FileAccess.Write`, and no sharing. Its leaf is exactly `.g13tmp-` plus a 32-character lower-case hexadecimal GUID, giving a fixed 40-character maximum independent of the final filename. The helper revalidates the final destination immediately before commit. A new evidence target uses same-volume `File.Move`; an explicitly mutable checkpoint/result may use same-volume `File.Replace`. Existing immutable evidence is never overwritten.

On collision, serialization/write failure, or move/replace failure, the call fails closed. Cleanup is attempted only for a temporary file proven to have been created by that invocation. A pre-existing collision fixture is never removed. JSON remains pretty, stable Unity `JsonUtility` output normalized to LF, UTF-8 without BOM, and newline-terminated.

`memory-gate-evaluation.json` must be committed and SHA-256 bound before any memory-threshold decision. Sample failure, block failure, and checkpoint artifacts continue to reference the evaluation path and hash. Mutable checkpoint replacement is the only repeated block evidence update; telemetry probe result replacement is allowed only inside its fresh verification directory.

## Unchanged scientific design

The memory policy remains 128 MiB alert, 256 MiB sample emergency stop, 256 MiB complete two-sample block managed-growth limit, and 512 MiB complete-block working/private limits; exact thresholds pass. P1-P5, C1-C5, AB-minus-BA, two-sided 95% intervals, ±`log(1.10)`, 20,000 complete-pair bootstrap replicates with seed 13012026, three scenarios, 32 mirrored pairs per scenario, Williams rows, scenario rotation, AB/BA quotas, reset, telemetry, one fresh Unity process per complete block, and strict serial execution are unchanged.

## Verification and execution boundary

Pre-pilot gates use a new versioned verification root. They must prove the observed 259/260 boundary, new-helper success for the isolated v6-equivalent case, 259/260/261 and longer legacy-temporary boundaries, C-FF/IDFF positions, path containment and reparse rejection, collision ownership, injected write/move failure cleanup, fixed temporary-leaf length, evaluation-before-decision, the existing 12 memory and 8 telemetry fixtures, compile, telemetry, positive and negative blocks, independent-process repeatability, cold structural control, retained 63/63 regression, frozen-root hashes, quiescence, and formal-root absence.

Only a complete passing final audit may create one new pilot root. That pilot consists of 12 excluded warm-up processes/24 samples and 384 measured processes/768 samples. After the pilot root exists, any failure terminates the attempt with atomic evidence and no retry, resume, top-up, or merge. Analysis runs only after all pilot observations and the final audit pass. Gate 13R formal execution, Gate 14R, OBS, and original script/scene changes remain forbidden.
