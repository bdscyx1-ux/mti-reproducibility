# Gate 12R Passed Checkpoint

Saved: 2026-10-08 (Asia/Shanghai)

Terminal status:

```text
GATE12R-PASSED-GATE13R-NOT-AUTHORIZED
```

## Scope completed

Gate 12R has completed the authorized fresh 5% process-reuse pilot and its independent post-pilot readiness audit. The only active upstream is:

- Gate 10R attempt 4;
- Gate 11R attempt 2;
- execution design `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`;
- Gate 11R bundle manifest SHA-256 `5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc`.

The successful pilot remains `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS`. It is admissible only for prospective variance, correlation, budget, storage and candidate sample-size planning. It is not a Gate 13R formal result.

## Retained managed-memory amendment

The original fixed 128 MiB complete-block ceiling was changed prospectively because it applied the same ceiling to one sample and to the aggregate of two or four individually valid samples. Gate 12R attempt 3 demonstrated the inconsistency: its failed two-sample grouped-field block retained 63,397,888 and 71,917,568 bytes in the two samples, both below 128 MiB, while the complete block retained 139,771,904 bytes (133.296875 MiB).

The active hard rules are therefore:

- per-sample retained managed-memory growth: at most 134,217,728 bytes (128 MiB), unchanged;
- complete-block retained managed-memory growth: at most `134,217,728 × expectedSampleCount` bytes;
- two-sample block limit: 268,435,456 bytes (256 MiB);
- four-sample block limit: 536,870,912 bytes (512 MiB);
- complete-block working-set growth: at most 536,870,912 bytes (512 MiB), unchanged;
- complete-block private-memory growth: at most 536,870,912 bytes (512 MiB), unchanged.

This is an aggregation-level correction, not removal of the memory gate or a post-hoc increase of the per-sample threshold. It was frozen before attempt 4 in `Research/Gate12R_Memory_Gate_Amendment.v1.json`, SHA-256 `69a128f8c41c2e0fad1453daed0729f752bb58b77d300f736a758f5121815c20`.

## Failed attempts retained and excluded

- pilot attempts 1–3 remain `FAILED-NO-RESUME-NO-MERGE` and excluded from all candidate/formal analyses;
- attempt 2 completed the measurement payload but failed its then-active formal storage-feasibility rule;
- attempt 3 stopped after 328 measured blocks at the inconsistent fixed complete-block 128 MiB rule; its manifest-listed 7,554 files / 493,784,387 bytes were independently rehashed with zero mismatch;
- all failed receipts, checkpoints, manifests, logs and hashes remain unchanged;
- no failed attempt was resumed, completed, or merged into attempt 4.

## Pre-pilot verification

The fresh verification root is `Research/Verification/Gate12R_ProcessReuse_5pct/v7`.

- static/unit: 332 assertions passed;
- managed-memory aggregation unit tests: 40/40 passed;
- Unity compilation: passed with zero compiler errors;
- PSAPI/CIM telemetry: passed;
- positive Williams blocks: 5 passed;
- injected negative fail-closed block: passed as an expected failure;
- cold structural controls: 8 passed;
- exact structural comparisons: 12/12 passed;
- retained regression: 63/63 passed;
- validation-only pre-pilot audit: 83/83 passed;
- checkpoint status before pilot: `PRE-PILOT-GATES-PASSED-PILOT-NOT-YET-STARTED`.

## Successful pilot payload

The successful root is `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4`.

| Role | Unity processes | Workload samples | Statistical use |
|---|---:|---:|---|
| telemetry probe | 1 | 0 | method validation only |
| excluded warm-up blocks | 8 | 24 | excluded |
| fresh cold structural controls | 36 | 36 | excluded |
| measured Williams blocks | 384 | 1,152 | candidate planning only |
| total | 429 | 1,212 | pilot only |

All 384 measured blocks completed in a fresh Unity Editor process per complete Williams block. Automatic retry and resume counts are zero. Structural comparisons passed 1,152/1,152 with zero mismatch.

Memory observations across the 384 measured blocks:

- sample retained managed-memory violations: 0;
- scaled block retained managed-memory violations: 0;
- block working-set violations: 0;
- block private-memory violations: 0;
- maximum sample retained managed growth: 106,176,512 bytes (101.258 MiB);
- maximum block retained managed growth: 105,242,624 bytes (100.367 MiB);
- maximum block working-set growth: 489,152,512 bytes (466.492 MiB);
- maximum block private-memory growth: 526,295,040 bytes (501.914 MiB).

## Candidate 5% formal design

The precision target remains a two-sided 95% CI with 5% relative half-width. There is no hard cap. Candidate `n_formal` is the number of independent Williams-block Unity processes per campaign.

| Cohort | Campaigns | Candidate blocks per campaign | Formal block processes | Samples per block | Formal samples |
|---|---:|---:|---:|---:|---:|
| four-algorithm shared-goal | 32 | 548 | 17,536 | 4 | 70,144 |
| per-agent heterogeneous-goal | 21 | 768 | 16,128 | 2 | 32,256 |
| grouped-field heterogeneous-goal | 21 | 400 | 8,400 | 2 | 16,800 |
| total | 74 | — | 42,064 | — | 119,200 |

The drivers are paired block log-difference SD upper bounds: shared `IDFF-minus-C-FF` (`sigma_upper = 0.58175694566059455`), per-agent `D*L-minus-A*-R` (`0.68941483881787924`), and grouped-field `IDFF-minus-C-FF` (`0.49699794016508997`).

Serial execution projections:

- p50 wall time: 881,220.2621056 seconds = 244.78 hours;
- p95 wall time: 1,141,436.3340784 seconds = 317.07 hours = 13.21 days;
- projected raw bytes with 1.5× p95 safety: 166,572,888,336 bytes = 155.13 GiB;
- minimum launch free bytes including 20 GiB reserve: 188,047,724,816 bytes = 175.13 GiB;
- pilot-end available free bytes: 292,135,882,752 bytes = 272.07 GiB;
- pilot-end margin over the combined launch gate: 104,088,157,936 bytes = 96.94 GiB.

The storage result is feasible at the recorded pilot-end snapshot. A future formal launch must repeat an original-byte free-space preflight; this snapshot is not a launch authorization.

## Final readiness evidence

- post-pilot readiness audit: 951/951 checks passed;
- readiness checkpoint SHA-256: `93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d`;
- pilot manifest SHA-256: `5b0678518423816212ea27f6cbb0bea18c1d11110ed10aefa1a238c17e0a53b6`;
- pilot execution manifest SHA-256: `fce4c7f9c7fe7df5f424c8a8ae888133942ed49dbede71d4499e502ba812ebd6`;
- block-aware analysis SHA-256: `486b87776e9b4edc78d293977f6eda2f43b386bd4832838780e34558e731731c`;
- correlation diagnostics SHA-256: `bc88d762da8e8440347f7ec35bd45f78b3b39d3426d5aa2e3b5313af6fcd82c1`;
- candidate `n_formal` SHA-256: `5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387`;
- budget/storage SHA-256: `cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f`;
- post-pilot audit SHA-256: `7b8ab16627900a1414d2184178842b665f53f4cfc3f3426120cc31d54fdcfa3e`;
- final pilot evidence manifest SHA-256: `91c5b6e3e5d6b5e1ebc4616d75723c7d482c17420e85c0f7a4833d824410683d`;
- final pilot evidence: 8,714 files / 554,204,972 raw bytes.

The 12 pilot campaign profiles all resolve to the frozen Gate 11R Playable mapping. Unity process count is zero, `Temp/UnityLockfile` is absent, and `Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1` does not exist.

## Authorization boundary

Gate 13R preparation and formal execution are both unauthorized. Do not create a Gate 13R formal root, formal execution receipt, or timing sample from this checkpoint.

The recommended next action is a separately authorized, non-executing Gate 13R preparation. Its copy-ready authorization text is in `Research/Gate13R_NonExecuting_Preparation_Authorization_Prompt.md`.
