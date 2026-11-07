# Gate 13R-PR2 non-executing formal-preparation test design

## Hard-gate groups

### A. Authorization and preservation

1. Parse the authorization, amendment, environment snapshot, and pre-write audit.
2. Recompute every listed key-file SHA-256.
3. Recompute every frozen-tree canonical SHA-256 before and after generation.
4. Require the future formal root and any PR2 formal execution receipt to remain absent.
5. Require zero Unity Editor processes before and after validation.

### B. Upstream matrix and Playable identity

1. Require 53 canonical scenarios, 74 campaigns, and 212 eligibility/preset entries.
2. Require 32 shared, 21 per-agent heterogeneous, and 21 grouped-field heterogeneous campaigns.
3. Match every campaign to its scenario, profile, scene, algorithms, Williams rows, and algorithm presets by frozen IDs and hashes.
4. Reject duplicate or missing scenario, campaign, profile, scene, preset, run, block, process, or output-path identities.

### C. Schedule arithmetic and balance

1. Require exactly 3,552 process/block records and 10,176 sample identities.
2. Require global process ordinals to be unique, gapless, and strictly increasing.
3. Require every one of the 74 campaigns to contain exactly 48 complete blocks.
4. For every shared campaign, require each of four frozen Williams rows 12 times and every algorithm in every position 12 times.
5. Require 1,008 heterogeneous matched superblocks, each with exactly two contiguous fresh block-process records.
6. For each heterogeneous scenario, require 48 matched superblocks, AB/BA 24/24, Williams row 0/1 24/24 per cohort, and every order-by-row cell 12 times.
7. Require each matched pair to share canonical scenario, repetition ordinal, deterministic input identity, scenario hash, and fingerprint while using different process/block/run identities.
8. Require one occurrence of each eligible algorithm per block and correct predecessor identities.

### D. Scientific semantics

1. Require P1 as the sole confirmatory primary endpoint.
2. Require shared C1–C5 as the Holm family at alpha 0.05.
3. Require heterogeneous C1–C4 to be labeled secondary system/treatment contrasts.
4. Require the 15% value to be labeled planning anchor only, with practical margin null/unfrozen.
5. Require P2–P5 supportive and M1–M5 prospective Gate 14R.
6. Reject adaptive stopping, per-campaign significance requirements, majority-vote conclusions, or conversion of pilot diagnostics into formal inference.

### E. Process, failure, telemetry, and memory semantics

1. Require strict serial topology and maximum Unity concurrency one.
2. Require one fresh Unity Editor process per complete block and prohibit cross-block/cross-campaign reuse.
3. Require per-sample complete reset and Playable/OBS isolation.
4. Require fail-closed, no automatic retry/resume/top-up/merge, and partial-block ineligibility.
5. Require the frozen 128 MiB alert / 256 MiB emergency and two-sample managed hard limit / 512 MiB working-set and private-memory limits, including exact-threshold-pass semantics.

### F. Resource projection and launch deferral

1. Require the exact p50, summed-p95, raw-byte, safety-byte, reserve, and minimum-free-byte values from the authorization.
2. Confirm current free space exceeds the minimum without treating the preparation snapshot as future launch authorization.
3. Require explicit formal-launch rechecks for storage, environment, power, thermal, license, lock hygiene, input hashes, and raw bytes.

### G. Determinism and static non-execution proof

1. Regenerate config, schedule, manifest, and preflight into an isolated verification directory.
2. Require byte-for-byte equality with the official generated outputs.
3. Scan new generator and validator sources for prohibited process-launch and Unity invocation constructs.
4. Ensure the validator performs read-only inspection of frozen upstream roots.
5. Produce a machine-readable validation summary, post-write preservation audit, and evidence manifest.

## Failure handling

Any failed hard gate produces an isolated versioned failure receipt, checkpoint, log, hashes, and partial manifest. Only a versioned repair to newly created non-executing artifacts may be retried. Scientific semantics, upstream identities, balance requirements, and authorization boundaries may not be relaxed.
