# Gate 12 Authorized Retry — Warm-up Wrapper Failure Checkpoint

Saved: 2026-10-05 (Asia/Shanghai)

Status: the explicitly authorized Gate 12 retry stopped under the frozen no-auto-retry rule. The isolated warm-up campaign itself completed successfully, but the outer Windows PowerShell 5.1 process monitor misclassified it because an asynchronous `Start-Process -PassThru` object exposed a null exit code. No measured pilot campaign and no Gate 13 work started.

## Authorization and attempt boundary

- Direct authorization received: `授权重试 Gate 12`.
- The prior zero-sample attempt was moved intact to `Research/PilotRuns/Gate12/v1-failed-pre-sample-attempt1/`.
- Move receipt: `Research/PilotRuns/Gate12/Gate12_Attempt1_MoveReceipt.json`, SHA-256 `65f4fe1ee923c44cc372a6122a52a6351ece921f777435140ea81dbc7a52377e`.
- The authorized retry created a new `Research/PilotRuns/Gate12/v1/` and stopped after the warm-up wrapper returned a false-negative status.
- The one authorized retry has therefore been consumed. No third attempt is authorized by this checkpoint.

## What actually completed

The warm-up evidence is internally passing:

- campaign: `g12p-warmup-r01-shared`;
- classification: non-formal, analysis-excluded thermal warm-up;
- 4 complete Williams blocks and 16 independent Unity processes;
- 4 observations each for A*-R, D*L, C-FF, and IDFF;
- `positionBalanced = true` and `orderedPredecessorBalanced = true`;
- all 16 per-run wrapper summaries passed with Unity exit code 0;
- all manifest, workload-result, and operations JSONL hashes match the campaign manifest;
- campaign manifest reports `completed = true`, wrapper summary reports `passed = true`, and campaign stderr is empty.

The pilot evidence did not begin:

- completed measured campaign count: 0/12;
- completed measured Unity-process count: 0/256;
- no `measured/` directory exists;
- no noise estimate, runtime projection, or candidate `n_formal` was generated.

## Failure and root cause

The outer runner recorded:

```text
Campaign failed with exit code : g12p-warmup-r01-shared
```

The blank value is decisive. A standalone PowerShell 5.1 probe reproduced the platform behavior:

- asynchronous `Start-Process -PassThru` plus redirected streams: `HasExited = true`, `ExitCode = null`;
- reflection reports that the returned object did not start the process and therefore cannot determine the exit code;
- `Start-Process -Wait` exposes exit code 0, but cannot support the frozen 30-second live monitor;
- an owned `System.Diagnostics.Process` with concurrent stdout/stderr draining exposes exit code 0 and preserves live monitoring.

The failure was therefore an outer-wrapper observation defect, not a Unity, algorithm, scenario, budget, Williams-order, or campaign-pipeline failure.

## Repair and validation

`Run-Gate12Pilot.ps1` now uses the tested owned-process helper from `Gate12PilotAnalysis.psm1`, drains both redirected streams asynchronously to avoid pipe deadlock, preserves campaign-directory growth monitoring, and retains the same hard-timeout process-tree termination behavior.

- repaired runner SHA-256: `bf45cebf1b04a73f1d3ca4cbdc6375f3aab00b9979e129145ac27e91e62cb025`;
- repaired module SHA-256: `96194e77239ad1e842d6ccacd2ffc870afdf8d3a2701144ae05dadeb472fe676`;
- analyzer SHA-256: `6aab2f34713ca929ca184bdda2238defedf022f2a39f050959aed02194b91a65`;
- unit-test script SHA-256: `e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1`;
- analysis/process regression: 63/63 assertions passed;
- process-behavior probe SHA-256: `602e294f7ecb8461f11930f457b5ce9a5e06f495071da16f1efa23c1cc2fda83`.

No repaired pilot was started after this validation.

## Preserved attempt identity

The stopped attempt remains untouched at `Research/PilotRuns/Gate12/v1/`:

- 103 files;
- 14,187,382 bytes;
- ordered relative-path + byte-count + file-hash aggregate SHA-256: `b52ee8f13c9b96edd2f0ab83f4969161ef5b257d1543588ec9608877086dc500`;
- warm-up campaign manifest SHA-256: `de900f8d91b544ff290c1329d55fb893c243efe620925f655ee0714f8f8101d8`;
- warm-up wrapper summary SHA-256: `a04bd2047b1c56f273acd40783931efabf9a65a09da09b1ff0cd069158588da0`;
- stdout SHA-256: `63bf5391df54d2cc892aca1ae4ad4de227f7941b3309c75eaf2f39613c8e6786`;
- empty stderr SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

Structured diagnostic: `Research/Verification/Gate12_RetryWarmupFailureDiagnostic.summary.json`.

## Frozen and safety state

- Gate 12 specification SHA-256 remains `29e6ca0de24b10f4a3a679378a353f9ae1821b130d1218f298591d2e89878b7c`.
- Gate 12 test-design SHA-256 remains `c8f71a54f9c73f936e3ddfeff6d4212bd48fb495847b9185a69adf720226e199`.
- Gate 12 plan SHA-256 remains `cc63505f444223c06a7f69a979c6a0d2e7f0d29e8217d910fe46b61db5618ce4`.
- Gate 11 retained bundle still verifies with 56 artifacts, 57 files, manifest SHA-256 `ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e`, and aggregate SHA-256 `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88`.
- Unity process count is 0 and `Temp/UnityLockfile` is absent.
- Original scripts and original scenes were not modified.
- Gate 13 was not started.

## Exact resume action requiring new authorization

Do not rerun automatically. After explicit user authorization:

1. verify the stopped attempt still has the aggregate above;
2. move it intact to `Research/PilotRuns/Gate12/v1-failed-warmup-attempt2/` and write a before/after hash receipt;
3. rerun preflight and the 63-assertion regression;
4. create a fresh `Research/PilotRuns/Gate12/v1/` and run one new Gate 12 attempt with the repaired monitor;
5. if it succeeds, analyze only the 256 measured samples and generate candidate `n_formal`; never include the 16 warm-up samples;
6. stop before Gate 13 regardless of the candidate result.
