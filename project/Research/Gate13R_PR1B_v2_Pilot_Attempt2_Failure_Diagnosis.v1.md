# Gate 13R-PR1B v2 pilot attempt 2 failure diagnosis

Status: `FAILED-NO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`  
Classification: `NON-FORMAL / WARMUP-ONLY / NO-MEASURED-OBSERVATIONS / EXCLUDED-FROM-FORMAL-ANALYSIS / EXCLUDED-FROM-ORDER-EFFECT-INFERENCE`

## Outcome

The v2 verification sequence passed at `v11`, including static/unit checks, Unity compilation, the 12/12 memory-threshold fixtures, the 8/8 telemetry-validation fixtures, PSAPI/CIM telemetry, positive mirrored blocks, negative fail-closed behavior, independent-process repeatability, cold structural control, retained 63/63 regression, provenance, and the validation-only final audit.

The one authorized v2 pilot then created the versioned `v6` root. Warm-up process 1 completed. Warm-up process 2 executed C-FF successfully and entered IDFF position 2, but failed while atomically persisting IDFF's `memory-gate-evaluation.json`.

No measured process started. No order-effect analysis ran. Nothing from this root is eligible for variance, sample-size, algorithm-effect, order-effect, or formal inference.

## Root cause

The exception was not a planner-correctness failure and was not a memory-threshold failure. It was a Windows/Mono path-length defect in the new atomic JSON helper:

```text
<final path>.tmp-<32 hexadecimal GUID characters>
```

The corresponding C-FF temporary path was 259 characters and succeeded. The IDFF temporary path was exactly 260 characters because `p02-idff` is one character longer than `p01-cff`. `System.IO.File.WriteAllText` therefore raised `DirectoryNotFoundException` under Unity's Mono/.NET path handling before the evaluation could be committed.

The Unity process exited with failure. The positive-role lock-hygiene policy correctly refused to delete the remaining zero-byte project lock, produced a quiescence-failure receipt, and caused the outer pilot to stop.

## Evidence and integrity

- Pilot root: `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v6-gate13r-pr1b-order-effect-memory-v2`
- Root inventory: 49 files, 1,955,414 raw bytes.
- Canonical tree SHA-256: `85a3fba48ae687acaa04b7b1f91afe0dc115f6efdde5bcaa4bbffa50e9139557`.
- Completed warm-up blocks: 1.
- Partially executed warm-up blocks: 1.
- Completed measured blocks/samples: 0/0.
- Residual lock: exact `Temp/UnityLockfile`, zero bytes, SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`, exclusively openable, with zero Unity processes.
- Reserved formal root remains absent.

## Required next repair

Any next attempt must use a new versioned Unity command and new verification/pilot roots. It must not modify or continue v6. The atomic helper should create a short temporary filename in the final file's existing directory, for example `.g13tmp-<GUID>`, then replace/move it to the final target on the same volume. Tests must cover the exact formerly failing path, long-output-root boundaries, parent existence, collision handling, atomic replacement, cleanup after write failure, and preservation of evaluation-before-threshold semantics.

The residual lock must be handled only by a newly authorized controlled stale-lock recovery with process, exact-path, hash, zero-byte, reparse-point, and exclusive-open checks.

