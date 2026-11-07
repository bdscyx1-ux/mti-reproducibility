# Gate 13R-PR2 raw-data / analysis two-phase commit specification v1

## Purpose

This additive execution amendment prevents a completed Unity acquisition from being discarded merely because a later audit or statistical-analysis implementation contains a software defect. It is frozen before any Gate 13R-PR2 formal data exist and does not alter the active v2 config, schedule, algorithms, samples, Williams order, matched-superblock order, memory gates, or statistical estimands.

## Phase 1 — raw-data acquisition commit

The formal orchestrator executes exactly the frozen 3,552 Unity block processes and 10,176 algorithm samples. During acquisition, every measured sample and block remains subject to the existing fail-closed correctness, telemetry, memory, hash, persistence, license, and environment rules. A failure before completion stops the attempt before the next global process ordinal and does not authorize retry, resume, top-up, or merge.

After all scheduled Unity processes exit successfully, Unity execution is permanently finished for this attempt. A raw-commit audit must then generate a raw execution manifest, complete file manifest, per-file SHA-256 values, block/sample cardinalities, schedule/Williams/AB-BA checks, original byte counts, end-environment snapshot, and a canonical raw-payload tree SHA-256.

The terminal success state is:

```text
RAW-DATA-COMPLETE
ANALYSIS-PENDING
IMMUTABLE
```

The immutable raw payload consists of every schedule-owned block directory and its plans, block manifests/checkpoints, sample manifests, sample summaries, workload results, memory evaluations, wrapper summaries, and Unity logs. Terminal root metadata may describe the payload but cannot replace or rewrite it. Later analysis outputs must never be written below the formal raw root.

## Raw-commit audit recovery

If every Unity process has completed but the raw-commit auditor itself crashes, fails to parse, or contains an implementation defect, the collected payload is retained and no Unity process may be rerun automatically. The state becomes:

```text
UNITY-COLLECTION-COMPLETE
RAW-COMMIT-AUDIT-PENDING
NO-UNITY-RERUN
```

Each audit recovery is a separate, versioned, read-only attempt. A recovery may regenerate only audit metadata outside or alongside the immutable payload. It must prove raw-payload pre/post hash equality. It may not change a measured file, manufacture a missing observation, or declare success by weakening the acquisition contract.

Only evidence of a real acquisition-contract violation—such as a missing block, corrupted hash, duplicate identity, invalid telemetry, or schedule mismatch—prevents `RAW-DATA-COMPLETE`. Even then, the system stops and requests a separate user decision; it never automatically reruns Unity.

## Phase 2 — analysis commit

Formal statistical analysis is a separate authorization and is not part of the current campaign authorization. Each analysis attempt writes to an isolated root such as:

```text
Research/Analysis/Gate13R_RQAligned_S48H48/v1/attempt-1
Research/Analysis/Gate13R_RQAligned_S48H48/v1/attempt-2
```

Every attempt binds the immutable raw-data freeze receipt, canonical raw-payload tree hash, analysis implementation, synthetic fixtures, and validation-only results. It reads the raw root without write access and must verify raw-tree hash equality before and after analysis.

An ordinary analysis implementation failure preserves that attempt, does not alter the raw data, does not rerun Unity, and permits a versioned analysis repair followed by a new analysis attempt against the same frozen payload. Gate 14R remains outside this authorization.

## Non-self-referential hashing

The canonical raw-payload tree hash is calculated from deterministic rows containing project-relative payload path, original byte count, and file SHA-256, sorted with ordinal comparison. The generated raw file manifest, freeze receipt, mutable root checkpoint/status, and future analysis directories are not members of the payload set; their own hashes bind the already-computed payload tree hash. This avoids self-referential hashes while preserving complete traceability.
