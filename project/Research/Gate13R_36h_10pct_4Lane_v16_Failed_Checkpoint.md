# Gate 13R 36h / 10% / 4-Lane Pilot v16 — Failed Checkpoint

Saved: 2026-10-08 (Asia/Shanghai)

Terminal status: `GATE13R-36H-V16-NONFORMAL-PILOT-FAILED-NO-RETRY-NO-RESUME`

The frozen four-lane NON-FORMAL pilot started only after the complete v16 readiness verification passed and the launch environment satisfied the exact 16 GiB gate. It then completed both warm-up waves and 79 measured waves before failing closed at measured wave 80. No formal campaign was authorized or started.

## Completed evidence

- Warm-up: 8/8 Williams blocks completed.
- Atomically completed measured waves: 79/96.
- Atomically completed measured blocks: 316/384.
- Atomically completed measured samples: 948/1,152.
- Wave 80 launched four blocks. Lanes 2 and 4 completed two blocks / eight samples, but the entire partial wave is excluded and cannot be merged.
- Partial evidence manifest: 6,581 files / 3,582,281,468 raw bytes.
- Automatic retry, resume and partial merge: none.
- Formal root and formal execution receipt: absent.

## Failure

Wave 80 lanes 1 and 3 exited in about 3.6 seconds with Unity exit code 1. Their block manifests and terminal block checkpoints were never created. Both Unity logs contain:

- `No valid Unity Editor license found. Please activate your license.`
- `License is not active (com.unity.editor.headless). HasEntitlements will fail.`
- `Access token is unavailable; failed to update`

Across all 328 pilot Unity logs, 326 received a serial assignment and only these two failed logs did not. The same generic signature-validation warning appears in successful runs, so it is not by itself the discriminating cause. The evidence supports a transient Unity Licensing Client channel/entitlement-assignment race during simultaneous four-lane startup, not an algorithm, scenario, memory, timeout or lock-hygiene failure.

Machine-readable diagnosis: `Research/Gate13R_36h_10pct_4Lane_v16_Licensing_Failure_Diagnosis.v1.json`.

## Frozen boundary

- Preserve `Research/PilotRuns/Gate13R_36h_10pct_4Lane/v16/` byte-for-byte.
- Do not retry, resume, fill missing waves, or merge the two successful blocks from failed wave 80.
- Do not use v16 for candidate `n_formal`, readiness p95, formal inference or Gate 14 analysis.
- Do not create `Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1` or any formal receipt.
- A fresh versioned pilot must use a new output root and a pre-registered Unity licensing-stability mitigation. That work requires separate user authorization.

## Suggested next authorization scope

The next authorization should be limited to a versioned licensing-readiness repair, tests and one fresh NON-FORMAL pilot. It should require a persistent/warmed licensing-client strategy or a deterministically staggered lane-start strategy, explicit four-lane entitlement probes, failure-injection tests, unchanged 74-campaign/10%/four-lane scientific semantics, and a new create-new pilot root. Formal execution must remain excluded.
