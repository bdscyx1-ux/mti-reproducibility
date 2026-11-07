# Gate 13R-PR2-MP2 prospective layered memory-policy specification v1

Status: **FROZEN-BEFORE-FUTURE-FORMAL-DATA / NON-EXECUTING / FORMAL-ATTEMPT3-NOT-AUTHORIZED**

Policy ID: `gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1`

Execution design retained unchanged: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`

## 1. Purpose and evidence boundary

This amendment freezes a prospective memory-eligibility contract for a possible Gate 13R-PR2 formal attempt 3. It is informed only by the frozen NON-FORMAL MP1 v2 memory pilot. MP1 v2 is excluded from future formal inference and cannot contribute observations, effects, sample-size evidence, or algorithm-superiority claims.

This specification does not authorize or create a formal output root, formal execution receipt, measured formal block, formal statistical analysis, or Gate 14R run.

## 2. Unchanged formal design

- Complete 74-campaign S48/H48 matrix.
- 32 shared-goal campaigns × 48 four-algorithm Williams blocks.
- 21 heterogeneous scenarios × 48 matched superblocks; each matched superblock contains one per-agent and one grouped-field fresh block process.
- 3,552 fresh Unity Editor block processes and 10,176 algorithm samples.
- Strict serial execution; maximum concurrent Unity Editor processes is one.
- One complete Williams block maximum per fresh Unity process; no cross-block or cross-campaign process reuse.
- One occurrence maximum for each eligible algorithm in a block; full mutable-state reset per sample.
- Active PR2 v2 schedule order, campaign/block/run identities, Williams rows, matched-superblock identities, and AB/BA 24/24 quotas are unchanged.
- P1/shared C1–C5 confirmatory, heterogeneous system/treatment secondary, P2–P5 supportive, M1–M5 prospective Gate 14R.
- Correctness, oracle, structural exact-match, deterministic identity, logging, telemetry, reset, exclusion, two-stage commit, lock hygiene, failure precedence, and no-auto-retry/resume/top-up/merge remain unchanged.

## 3. Scenario classifier

The classifier reads `gridWidth` and `gridHeight` from the canonical scenario source bound by the active schedule record and verifies the source SHA-256. Both values must be positive integers. The canonical maximum grid dimension is `max(gridWidth, gridHeight)` and must be one of `32`, `64`, `128`, or `256`.

- `32`, `64`, and `128` map uniquely to tier `MP2-NATIVE-LE128`.
- `256` maps uniquely to tier `MP2-NATIVE-EQ256`.
- A missing, non-integer, non-positive, unsupported, multiply mapped, hash-mismatched, scenario-ID-mismatched, or otherwise ambiguous value is `CONFIGURATION-HARD-FAIL` before any measured launch.

The generated mapping binds all 53 scenarios, 74 campaigns, and 3,552 schedule records to exactly one tier. It is a prospective overlay; it does not alter the active PR2 v2 schedule.

## 4. Measurement stages and baseline

One immutable block baseline is captured inside the owned Unity process after plan/config validation and before the first sample workload. It contains process identity, working set, private memory, managed memory, available physical memory, process age, GC counters, and UTC timestamp.

For every sample the adapter records:

1. `before-sample` telemetry;
2. `raw-after-workload` telemetry before forced cleanup;
3. `after-forced-cleanup` telemetry after planner/logger/sample disposal and forced full GC;
4. a durable memory-policy evaluation before declaring that sample complete.

After all eligible samples and resets, it records a separate `post-block-pre-exit` boundary after forced cleanup. All telemetry points must have the same composite process identity `(PID, processStartTimeUtc, blockId)`, strictly nondecreasing process age/timestamps and nondecreasing GC counters. Missing, non-positive, non-finite, overflowed, mixed-process, or unverifiable telemetry fails closed.

## 5. Native residency policy

At each `after-forced-cleanup` completed-sample boundary and the `post-block-pre-exit` boundary:

```
workingSetDeltaFromBlockBaselineBytes = workingSetBytes - blockBaselineWorkingSetBytes
privateMemoryDeltaFromBlockBaselineBytes = privateMemoryBytes - blockBaselinePrivateMemoryBytes
nativeResidencyMetricBytes = max(workingSetDeltaFromBlockBaselineBytes,
                                 privateMemoryDeltaFromBlockBaselineBytes)
```

Thresholds are inclusive on the passing side: equality passes; crossing means strictly greater than the threshold.

| Tier | Canonical max dimension | Advisory envelope | Hard eligibility ceiling |
|---|---:|---:|---:|
| `MP2-NATIVE-LE128` | 32, 64, 128 | 512 MiB / 536,870,912 bytes | 640 MiB / 671,088,640 bytes |
| `MP2-NATIVE-EQ256` | 256 | 640 MiB / 671,088,640 bytes | 768 MiB / 805,306,368 bytes |

- Advisory crossing is durably recorded and retained; it does not stop the current block or the campaign.
- Hard crossing is durably recorded as a whole-block/process eligibility failure. The current owned block is permitted to finish its durable failure evidence, but the wrapper returns failure and the orchestrator must not start the next block.
- A crossing observed at a sample position is not attributed to the algorithm at that position. `attributionScope` is always `WHOLE-BLOCK-PROCESS`; the enforcement position is diagnostic only.
- Native values at `raw-after-workload` are transient diagnostics and do not trigger the tier advisory or hard ceiling. They remain subject to independent host-emergency rules.
- No adaptive threshold relaxation is permitted.

## 6. Retained managed-memory policy

Managed-memory decisions use only `after-forced-cleanup` and `post-block-pre-exit` boundaries.

- Sample retained growth above 128 MiB (134,217,728 bytes): `MANAGED-ALERT`; equality passes without alert.
- Sample retained growth above 256 MiB (268,435,456 bytes): emergency hard failure after durable evidence.
- Whole-block retained growth above 256 MiB: emergency hard failure after durable evidence.
- Raw-after-workload managed growth is diagnostic only unless telemetry is invalid or a host-emergency rule fails.

Managed emergency failure stops the current block before any later sample. It cannot be downgraded by a native advisory verdict.

## 7. Host-emergency policy and precedence

At block baseline, every raw-after-workload boundary, every after-cleanup boundary, and post-block:

- `max(workingSetBytes, privateMemoryBytes) > 4 GiB` is a hard host emergency;
- `max(workingSetDeltaFromBlockBaselineBytes, privateMemoryDeltaFromBlockBaselineBytes) > 2 GiB` is a hard host emergency;
- available physical memory below 8 GiB is a hard host emergency;
- native/managed arithmetic overflow, missing or invalid OS telemetry, composite-process mismatch, or unverifiable sustained growth fails closed.

Equality to 4 GiB, 2 GiB, or 8 GiB passes. Host emergency has higher precedence than transient/advisory/native-eligibility classification and stops the current block after durable evidence.

Failure precedence is: durable Unity/sample/block cause → process exit/timeout evidence → secondary quiescence/lock evidence. Lock cleanup never authorizes continuation.

## 8. Durable evidence contract

Every memory evaluation records policy/tier IDs, scenario path/ID/hash, campaign/block/run identities, process composite identity, measurement stage, baselines, raw component values and deltas, native metric, all thresholds, exact-boundary flags, advisory/hard/host/managed verdicts, reason codes, attribution scope, enforcement position, and SHA-256-linked output identity.

Block manifest/checkpoint must distinguish:

- `PASS`;
- `PASS-WITH-ADVISORY`;
- `HARD-FAIL-NATIVE-ELIGIBILITY` (block evidence complete; next block forbidden);
- `HARD-FAIL-MANAGED-EMERGENCY`;
- `HARD-FAIL-HOST-EMERGENCY`;
- `HARD-FAIL-TELEMETRY/PERSISTENCE/LOCK`.

No block may be marked eligible if a hard verdict exists. No later block may start after a hard verdict.

## 9. Two-stage commit

Phase A is formal raw acquisition. After all scheduled blocks complete, it must freeze file counts, raw bytes, per-file hashes, schedule/Williams/AB-BA completeness, environment end snapshot, canonical raw-tree SHA-256 and immutable attributes, yielding `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`.

Phase B is separately authorized, versioned, read-only analysis. Analysis bugs create new analysis attempts against the same immutable Phase-A tree and never trigger Unity reruns. A new experiment is required only if an independently reviewed analysis proves a raw acquisition-contract violation.

## 10. Authorization boundary

MP2 may compile and execute synthetic/self-test/validation-only Unity blocks in `Research/Verification/Gate13R_PR2_MP2/...`, labeled `VALIDATION-ONLY / NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`. The formal attempt-3 root and formal attempt-3 receipt must remain absent throughout MP2.
