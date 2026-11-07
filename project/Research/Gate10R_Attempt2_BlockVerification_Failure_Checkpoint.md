# Gate 10R Attempt 2 Block-Verification Failure Checkpoint

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run / validate`
- Origin Date: 2026-10-06
- Verification Status: `FAILED-NO-AUTO-RETRY`
- Version Label: `gate10r_attempt2_block_transition_lock_failure_v2`
- Stable Run ID: `gate10r-to-gate12r-execution-v1`
- Active design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`

## Terminal state

Gate 10R attempt 2 consumed its single authorized official execution and stopped fail-closed at `official-block-verification`. The versioned Windows PowerShell 5.1 compatibility correction itself passed all prospective checks: 62/62 no-Unity preflight checks, 38/38 official unit assertions, Unity compilation, and the telemetry probe all passed.

The block-verification run then completed three positive Williams blocks and the expected negative fail-closed fixture. The four owned Unity process IDs were `22532`, `22896`, `2200`, and `19936`; the completed fixtures contained 11 samples in total. The negative fixture exited with its expected failure, preserved one completed sample, and did not execute later samples.

Before the first of six planned fresh cold-process structural controls could start Unity, the entry guard reported:

```text
Unity must be closed and the project lock absent.
```

At the subsequent read-only inspection, no `Unity.exe` process remained, but `H:\DDM_Final_Project\Temp\UnityLockfile` still existed as a zero-byte file with creation and last-write time `2026-10-06T13:09:17.4285441Z`, during the owned negative fixture. The evidence establishes lock persistence at that transition. It does not by itself distinguish delayed Unity cleanup from a stale lock artifact, so the failure is recorded without a stronger causal claim.

- Official attempt-2 execution count: 1
- Positive blocks completed: 3
- Expected negative blocks completed: 1
- Completed block samples: 11
- Fresh cold controls completed/planned: 0/6
- Structural comparisons completed/planned: 0/10
- Retained regression: not started
- Validation-only final audit: not started
- Gate 11R: not started
- Gate 12R: not started
- Gate 13R preparation/campaign: not authorized and not started
- Automatic retry/resume: 0/0
- Disposition: `GATE10R-ATTEMPT2-FAILED-NO-AUTO-RETRY`

All attempt-2 outputs are `NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS / NOT-FOR-GATE14-INFERENCE`. They cannot produce a candidate `n_formal` and cannot be resumed or combined with any future attempt.

## Frozen evidence

- Execution receipt SHA-256: `02660a160a67655aa27a364d63fbed896471d02c0c5b953f646143feeafdc9d7`
- No-Unity preflight summary SHA-256: `dfb24677c34528688264ca0d8c3b8cb92c1004d7526b459275c9578f85cf35f4`
- Unit-test summary SHA-256: `810bb589f46152f57b5b9fa6dc62b8fee9d248c8479b1f18786e3f40eb7382d0`
- Failure stderr SHA-256: `2aee9da910c1faf889e7e056ebb994860d3ecd901647b69b9f27f282b76eb0a6`
- Partial-output manifest SHA-256: `1d228e45195aee1eca5c58730952b65753e723b66ad21e1fa8f80f6ac8e72dbe`
- Failure receipt SHA-256: `a50896a296a68722e4ea8a7801d2a2505feb712cd58349294df1a056de6e70ec`
- Terminal checkpoint SHA-256: `630a1ca4a91c43c23de552ca2e77acbcf38ec13d94f79ab83da74bda04e09815`
- Partial manifest scope: 98 artifacts / 9,337,336 raw bytes before the manifest itself

The complete attempt-1 root `Research/Verification/Gate10R_ProcessReuse_5pct/v1` and all files named by its manifest remain immutable. The attempt-2 root `Research/Verification/Gate10R_ProcessReuse_5pct/v2` is now also terminal evidence: do not overwrite, delete, resume, reinterpret, or append experimental samples to it.

## Exact continuation boundary

No further experimental execution is authorized. A later attempt requires a new explicit authorization, a new versioned root, and a prospectively frozen lock-hygiene transition design. Such an authorization must decide whether the exact owned stale lock may be evidence-captured and removed after all owned Unity processes have exited, or whether the expected-negative fixture must instead be isolated in a disposable project copy. It must not modify attempt 1 or attempt 2 and must authorize at most one new official execution.

Until then:

1. do not delete or alter the observed `Temp/UnityLockfile` as part of this attempt;
2. do not run Gate 10R retained regression or final audit;
3. do not start Gate 11R or Gate 12R despite their earlier conditional authorization;
4. do not create Gate 13R preparation, formal roots, receipts, or campaigns.

