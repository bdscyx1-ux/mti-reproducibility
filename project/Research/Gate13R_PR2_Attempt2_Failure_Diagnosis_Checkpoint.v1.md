# Gate 13R-PR2 attempt 2 failure-diagnosis checkpoint v1

Saved: 2026-10-09 10:50（Asia/Shanghai）

Status:

`ATTEMPT2-EVIDENCE-FROZEN / PRIMARY-MEMORY-FAILURE-DIAGNOSED / SECONDARY-QUIESCENCE-FAILURE-DIAGNOSED / MEMORY-POLICY-UNFROZEN / FORMAL-ATTEMPT3-NOT-AUTHORIZED / FORMAL-ANALYSIS-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

Additional verdict:

`TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED`

## 1. Frozen attempt 2 evidence

`Research/FormalRuns/Gate13R_RQAligned_S48H48/v2` remains `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE` and excluded from formal analysis. It contains 28,020 files / 8,536,611,302 bytes. All files are read-only. The canonical Unicode/System.StringComparer.Ordinal tree SHA-256 is:

`aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e`

Attempt 2 completed 933/3,552 block processes and 3,732/10,176 samples. Process ordinal 934 is a failed partial block and is not committed formal data. The two-phase raw-data commit was never reached; there is no `RAW-DATA-COMPLETE` receipt.

## 2. Memory diagnosis

All 3,736 available memory evaluations passed telemetry/composite-identity validation. They represent 933 complete blocks plus the four boundaries in failed partial block `g13rpr2-c52-b0022`.

The failed block crossed both 512 MiB native block-delta limits at its first boundary:

| Position | Algorithm | Predecessor | Working-set growth | Private-memory growth | Recorded verdict |
|---:|---|---|---:|---:|---|
| 1 | A*-R | NONE | 603,987,968 B (576.008 MiB) | 646,492,160 B (616.543 MiB) | PASS — enforcement deferred |
| 2 | D*L | A*-R | 610,676,736 B | 643,379,200 B | PASS — enforcement deferred |
| 3 | IDFF | D*L | 614,977,536 B | 643,579,904 B | PASS — enforcement deferred |
| 4 | C-FF | IDFF | 614,866,944 B (586.383 MiB) | 641,327,104 B (611.617 MiB) | HARD-FAIL — final boundary |

The frozen V4 command records threshold flags at every sample boundary but only enforces block-level hard-fail reasons when `finalSampleInBlock` is true. Therefore C-FF is the final enforcement point, not an identified cause of the increase. A*-R is the first observed crossing position, not an identified cause either. Algorithm, position, predecessor, normal g256 residency, and native leak causality remain not identifiable from this block.

Managed growth did not fail its 256 MiB block limit: the observed block maximum over 934 represented blocks was 190,205,952 bytes (181.395 MiB), with zero 256 MiB exceedances. Across all evaluations, verdicts were 3,732 PASS, 3 managed-memory alerts at 128 MiB, and 1 hard fail at the final native-memory enforcement boundary.

## 3. Candidate thresholds remain unfrozen

| Native block-delta candidate | Observed exceed blocks (934 prefix) | ≥90% near misses: working/private | Status |
|---:|---:|---:|---|
| 512 MiB | 1 | 1 / 6 | UNFROZEN |
| 640 MiB | 0 | 1 / 1 | UNFROZEN |
| 768 MiB | 0 | 0 / 0 | UNFROZEN |
| 1,024 MiB | 0 | 0 / 0 | UNFROZEN |

These prefix counts cannot establish full-matrix safety. No threshold was selected, and no candidate may be chosen merely because it would have let attempt 2 continue. Absolute process-memory caps, scenario-size-aware envelopes, and managed-hard/native-advisory layering also remain candidates only.

## 4. Secondary quiescence failure

The durable memory failure preceded the post-exit quiescence failure by 60.731 seconds. Unity had exited, but a zero-byte `Temp/UnityLockfile` remained and the active wrapper surfaced that secondary error as its outer message. The exact stale lock was independently evidenced, then safely removed under the FD1 authorization; Unity remained at zero processes and the failed root hash was unchanged.

The validated, unactivated candidate wrapper semantics now preserve the durable block failure as primary and append quiescence as secondary. Both still fail closed and forbid continuation.

## 5. Validation

- Core synthetic tests: 23/23.
- Canonical-order repair: 4/4.
- Enforcement-boundary tests: 11/11.
- V4 repair tests: 6/6.
- Failure-precedence tests: 10/10 in PowerShell 7.6.5 and 10/10 in Windows PowerShell 5.1.
- Deterministic regeneration: 5/5 output files byte-identical.
- Final validation-only audit: 21/21.
- Final state: Unity 0, lock absent, attempt-3 root absent, attempt-3 receipt absent.

## 6. Stop boundary

FD1 is complete. No Unity process was launched, no formal statistical analysis was run, and no formal attempt 3 was created. The recommended next step is one separately authorized, balanced, non-formal memory pilot with stage-separated process/project/scenario/sample telemetry. Formal attempt 3 must remain unauthorized until that pilot is complete and a prospective memory policy is selected in a separate amendment.
