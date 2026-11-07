# Gate 13R-PR2 S48/H48 non-executing formal-preparation specification

## 1. Scope and status

This specification freezes a future formal configuration and schedule without executing Unity, creating formal samples, creating a formal output root, or issuing a formal execution receipt. The configuration is `PROSPECTIVE-BEFORE-FORMAL-DATA`, `NON-EXECUTING`, and `FORMAL-CAMPAIGN-NOT-AUTHORIZED`.

The only active upstreams are the passed Gate 10R attempt 4, passed Gate 11R attempt 2 retained bundle, Gate 12R v4 pilot, Gate 13R-PR1, and Gate 13R-PR1B v4 read-only recovery. The PR1B v7 source pilot remains failed, non-formal, and excluded from formal analysis.

## 2. Matrix and independent units

- The complete Gate 11R matrix remains fixed: 53 canonical scenarios, 74 campaign profiles, and 212 algorithm presets.
- Shared-goal scope contains 32 four-algorithm campaigns. Each campaign receives 48 complete Williams blocks. One block is one independent fresh Unity Editor process and contains four algorithm samples.
- Heterogeneous scope contains 21 canonical scenarios and two campaign/cohort profiles per scenario. Each scenario receives 48 matched superblocks. One superblock contains two independent fresh Unity Editor processes: one per-agent block and one grouped-field block.
- The matched superblock is the cross-family matching unit; each individual block process remains the execution unit. Individual algorithm samples are not independent units.

## 3. Order and balance

Shared blocks rotate the frozen four-row Williams square. Forty-eight blocks give 12 occurrences of every Williams row per campaign and 12 appearances of every algorithm in every position.

Heterogeneous matched superblocks use an orthogonal four-pattern cycle:

1. AB with Williams row 0 in both cohorts;
2. BA with Williams row 0 in both cohorts;
3. AB with Williams row 1 in both cohorts;
4. BA with Williams row 1 in both cohorts.

The cycle is scenario-rotated but complete within every scenario. Consequently, each heterogeneous scenario has 24 AB and 24 BA superblocks; each cohort uses each two-algorithm Williams row 24 times; and each order-by-row cell occurs 12 times. The two block-process records belonging to one matched superblock must be contiguous in the global schedule.

`A` denotes the per-agent cohort and `B` denotes the grouped-field cohort. Matching requires the same canonical scenario, repetition ordinal, scenario hash, scenario fingerprint, and deterministic input identity. Each superblock has its own ID and each process/block/sample has a globally unique identity and output-relative path.

## 4. Scientific contract

P1 (`dynamicHandlingMillisecondsPerScheduledEvent`) remains the sole confirmatory primary endpoint. Shared-goal C1–C5 comprise one confirmatory family with family-wise alpha 0.05 and Holm multiplicity control. C1–C4 are directional superiority contrasts; C5 is a two-sided C-FF/IDFF head-to-head comparison unless separately amended before formal data exist.

Heterogeneous C1–C4 remain secondary matched-superblock system/treatment contrasts. They cannot be described as pure algorithm effects because field ownership and goal representation differ between cohorts. P2–P5 remain supportive. M1–M5 remain prospective Gate 14R endpoints and are not measured or powered here.

The 15% relative effect is a planning anchor used in sensitivity calculations. It is not a practical-superiority or non-inferiority margin. Formal superiority continues to require the preregistered ratio-to-1 confidence-interval rule after Holm-compatible adjustment. There is no adaptive sample-size update, early stopping, or claim that every campaign independently reaches a 10% CI target.

## 5. Execution and reset contract

- Strict serial topology; maximum concurrent Unity Editor process count is one.
- One fresh Unity Editor process executes at most one complete Williams block.
- No reuse across blocks, matched superblocks, or campaigns.
- Every algorithm sample receives complete planner, grid, scenario, runner, logger, metrics, and mutable-static reset.
- Correctness, oracle, structural, deterministic-identity, telemetry, memory, provenance, and completeness gates remain fail-closed.
- A failed sample fails its block; a failed block fails the attempt. No automatic retry, resume, top-up, or partial-attempt merge is allowed.
- Playable scenes and OBS recording remain separate from formal timing execution and formal timing inference.

## 6. Memory and telemetry policy

The latest preregistered PR1B managed-memory semantics are carried forward: a per-sample managed-retained-growth alert at 128 MiB, emergency stop at 256 MiB, two-sample block managed-retained-growth hard limit at 256 MiB, and block working-set/private-memory hard limits at 512 MiB. Exact-threshold values pass. Alerts remain visible and do not silently become exclusions. Formal-launch validation must bind the exact policy identity and re-run telemetry probes under a separate authorization.

## 7. Counts and resource projection

The frozen arithmetic is:

- Shared: `32 × 48 = 1,536` processes; `1,536 × 4 = 6,144` samples.
- Heterogeneous: `21 × 48 = 1,008` matched superblocks; `1,008 × 2 = 2,016` processes; `2,016 × 2 = 4,032` samples.
- Total: `3,552` processes and `10,176` samples.
- Serial p50 projection: `20.808185450666667 h`.
- Conservative summed-p95 envelope: `26.45538207066667 h`.
- Projected p95 raw bytes: `9,631,912,320`.
- 1.5× safety bytes: `14,447,868,480`.
- Additional reserve: `42,949,672,960` bytes (40 GiB).
- Minimum launch free space: `57,397,541,440` bytes.

These are planning projections, not runtime guarantees. All environment, power, thermal, license, lock, hash, raw-byte storage, and free-space checks must be performed again after separate formal authorization and before the formal root is created.

## 8. Non-executing boundary

This stage may create versioned design files, config, schedule, manifest, storage/wall-clock preflight, validation evidence, readiness checkpoints, and a future authorization prompt. It must not create `Research/FormalRuns/Gate13R_RQAligned_S48H48/v1`, a formal execution receipt, a timing sample, or a Unity process. Any future runner or launch orchestration must be separately authorized and bound to the exact hashes produced here.
