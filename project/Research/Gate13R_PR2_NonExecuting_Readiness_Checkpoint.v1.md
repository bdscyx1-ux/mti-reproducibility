# Gate 13R-PR2 non-executing formal-preparation readiness checkpoint

Saved: 2026-10-09 00:18:51 (Asia/Shanghai)

Status:

`PR2-NONEXECUTING-PREPARATION-VALIDATED / S48-H48-FROZEN / FORMAL-CONFIG-AND-SCHEDULE-READY / FORMAL-ROOT-ABSENT / FORMAL-EXECUTION-RECEIPT-ABSENT / UNITY-NOT-LAUNCHED / GATE13R-FORMAL-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

Machine-readable checkpoint: `Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json`, SHA-256 `669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc`.

## 1. Active artifact set

Only the PR2 v2 formal-preparation artifact set is active for any future formal authorization:

| Artifact | SHA-256 |
|---|---|
| `Research/Gate13R_PR2_Formal_Campaign_Config.v2.json` | `87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e` |
| `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl` | `df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae` |
| `Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json` | `b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724` |
| `Research/Gate13R_PR2_Storage_WallClock_Preflight.v2.json` | `c474499e647d5ad32efe01d199ede187b61f004e9487b8278e44109258cd0435` |
| `Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json` | `9e81530bcf6d32dd1792c8bd693d72988bef6f37e59a1ad154019ca228908e56` |
| `Research/Gate13R_PR2_Formal_Preparation_Schema.v2.json` | `940bfca8cb3e677deadff2600471eeaec9e99ff6bab9a06a625a0f30365a9d1e` |

The v1 artifact set is preserved as failed-schema-validation history and is not authorized for launch.

## 2. Frozen S48/H48 design

- Complete Gate 11R matrix: 53 scenarios, 74 campaigns, 212 presets.
- Shared: 32 campaigns × 48 complete four-algorithm Williams blocks = 1,536 fresh processes / 6,144 samples.
- Heterogeneous: 21 scenarios × 48 matched superblocks = 1,008 superblocks / 2,016 fresh processes / 4,032 samples.
- Total: 3,552 fresh block processes / 10,176 samples.
- Every heterogeneous scenario: AB/BA 24/24; each order × Williams-row cell 12; each cohort row 24.
- Strict serial; maximum Unity concurrency one; one complete block maximum per process; per-sample complete reset; no cross-block or cross-campaign reuse.

## 3. Scientific and interpretation contract

- P1 is the sole confirmatory primary endpoint.
- Shared C1–C5 form the Holm FWER 0.05 family.
- Heterogeneous C1–C4 remain secondary system/treatment contrasts, not pure algorithm causal effects.
- P2–P5 are supportive; M1–M5 remain prospective Gate 14R endpoints.
- The 15% relative effect is a planning anchor only. It is not a practical-superiority margin.
- No adaptive stopping, per-campaign significance requirement, majority vote, or claim that pooled superiority applies to every campaign.
- Correctness and eligibility remain prior hard gates.

## 4. Resource envelope

- Serial p50: 20.808185450666667 h.
- Conservative summed-p95: 26.45538207066667 h.
- Projected p95 raw bytes: 9,631,912,320.
- 1.5× safety bytes: 14,447,868,480.
- Additional 40 GiB reserve: 42,949,672,960 bytes.
- Minimum launch free space: 57,397,541,440 bytes.
- Observed during final preparation closeout: 276,247,064,576 free bytes on H:.

The observed value does not authorize launch. Storage, raw-byte budget, environment, power, thermal state, license, network, lock hygiene, process state, and all hashes must be measured again immediately before any formal root is created.

## 5. Validation history and terminal proof

Attempts 1–3 remain immutable failed validation-only evidence:

1. v1 stopped before core validation because PowerShell 5.1 and 7 used different culture ordering for a tree manifest.
2. v2 proved that the older pre-write tree digests themselves used runtime-dependent ordering; it stopped before core validation.
3. v3 reached 62/63 core checks; the only failure was a new schema property-name mismatch.

The repaired v4 path used explicit `StringComparer.Ordinal`, schema v2, the complete official artifact set v2, and Windows PowerShell 5.1 execution. It passed:

- core validation 63/63;
- all config/schema/schedule records;
- 74 × 48 campaign/block arithmetic;
- all Williams/position/order-row balance;
- 1,008 matched-superblock identity and contiguity checks;
- 10,176 unique run IDs and 13,728 unique block/sample output paths;
- every Gate 11R scenario/profile/preset/Playable hash binding;
- memory/scientific/failure/resource contracts;
- byte-identical deterministic regeneration of all six official v2 outputs;
- pre/post frozen-tree integrity;
- zero Unity processes and absence of the formal root/receipt.

Successful verification root: `Research/Verification/Gate13R_PR2_NonExecuting_Preparation/v4`, 14 files / 11,585,336 bytes / canonical ordinal tree SHA-256 `4c1262219f4923ba201de089b4bcf0b3be11c8c59c8dab2a9623bf53f4e38d29`.

## 6. Authorization boundary and next step

The reserved future formal root is `Research/FormalRuns/Gate13R_RQAligned_S48H48/v1`; it does not exist. No PR2 formal execution receipt exists. No Unity Editor was launched by PR2. No formal timing sample exists. Gate 13R formal execution and Gate 14R remain unauthorized.

If the user decides to execute the formal campaign, use `Research/Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md`, SHA-256 `0cdfa4dfe87ce5642be675a16653d9b8cb5cb29721bdda742a3cfd97ae566661`. That prompt authorizes one fail-closed formal attempt only after fresh prelaunch checks; it does not authorize Gate 14R or automatic retry/resume/top-up/merge.
