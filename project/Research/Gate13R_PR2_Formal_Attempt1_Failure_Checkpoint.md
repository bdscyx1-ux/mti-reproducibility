# Gate 13R-PR2 S48/H48 Formal Attempt 1 Failure Checkpoint

## Terminal status

`FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`

- Formal attempt ordinal: `1`
- Formal root: `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v1`
- Orchestrator PID: `16352`
- Orchestrator start UTC: `2026-10-08T17:44:28.0230380Z`
- Terminal status saved UTC: `2026-10-08T17:44:45.7500452Z`
- Current global process ordinal at failure: `1`
- Campaign: `core-r01-s1-shared--shared`
- Block: `g13rpr2-c01-b0001`
- Formally committed process count: `0`
- Formally committed sample count: `0`
- Generated but permanently excluded sample-artifact count: `4`
- Automatic retry, resume, top-up and partial merge: forbidden
- Formal statistical analysis: not authorized
- Gate 14R: not authorized

## Failure classification

`POST-UNITY-BLOCK-WRAPPER-VALIDATION-IMPLEMENTATION-DEFECT`

The first Unity Editor process completed successfully and returned exit code 0. It generated a completed four-algorithm block, four sample summaries, four child manifests and four memory-gate evaluations. The Unity license became available and the Unity log ended with a successful batch-mode exit.

The frozen block wrapper then failed before writing its wrapper summary and before the orchestrator committed the block. The exact incompatibility is:

- `block-manifest.json` top-level `formalCampaign` is `true`;
- all four sample summaries contain `formalCampaign=true`;
- all four child manifests contain `formalCampaign=true`;
- all four memory-gate evaluations contain `formalCampaign=true`;
- all four embedded `block-manifest.samples[]` records omit the `formalCampaign` property;
- `Run-Gate13RPR2FormalBlockV4.ps1` line 115 accesses `$sample.formalCampaign` under `Set-StrictMode`, which raises `System.Management.Automation.PropertyNotFoundException` before the wrapper can produce a passed summary.

The producer-side source mismatch is in `Gate13RPR2FormalBatchCommandV2.cs`: `BlockChildRecord` does not declare `formalCampaign`, and the `FinalizeSample` `BlockChildRecord` initializer therefore cannot populate it. The wrapper's requirement itself was not relaxed.

## Two-phase commit interpretation

The raw-data / analysis two-phase commit amendment and authorization were active and bound to the execution receipt. However, this attempt did **not** reach:

`UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN`

or:

`RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`

The failure occurred inside Phase 1 while committing the first measured block, not in the post-collection raw auditor and not in formal analysis. Therefore the read-only analysis-recovery rule is not applicable. No analysis was started.

## Evidence disposition

The complete attempt-1 root is frozen as read-only historical failure evidence:

`PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS / NO-RETRY / NO-RESUME / NO-TOP-UP / NO-MERGE`

- Frozen root file count: `31`
- Frozen root raw bytes: `3,338,221`
- Canonical root tree SHA-256: `026b9830f220b06af3f0a106f638b3d918d115ba08f5f06c13d9d76542ba4f56`
- Read-only files: `31/31`
- Unity processes after failure: `0`
- Unity lock after failure: absent

Key evidence:

- `Research/Gate13R_PR2_Formal_Execution_Status.v1.json` — `a7dd97d766a23fc001ac2e8adca5f34206932906a8d6452de55fa43d28d544be`
- `Research/FormalRuns/Gate13R_RQAligned_S48H48/v1/formal-checkpoint.json` — `f09dd3322bf868da15ef9e12387a345aa6ca056a082c4d8c9e8deffe0e83799e`
- `Research/FormalRuns/Gate13R_RQAligned_S48H48/v1/partial-output-manifest.json` — `9ee77190f21cf3b216f9ab84f3c8b2fd77c1944fa09259ddea58775a48278cfc`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-launch-receipt.json` — `2056575d817922bfbbee91570938e9c8ea7bad707aa81b5d9905176d4df35049`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-failure-diagnosis.json` — `efaf6cee119575deae056ef432a4202d2f1629a696b8ac975156995cde52dc2e`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-partial-tree-manifest.json` — `93d6d9efd4232a3f995621d2ad5c62951dcbdf10f7ede13d9b37948aad755ab5`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-evidence-freeze-receipt.json` — `481678f143e577a243c651aef86b0a960d22709836fa36be302e2e6608670b25`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/formal-attempt-1-evidence-manifest.json` — `0f3a2612abc799f04f6e828ee747efdb8b8dda594c35c84fbccad27a734d5fc5`
- `Research/Verification/Gate13R_PR2_Formal_Execution/v1/orchestrator.stderr.log` — `4f4e24552e078cbd61934b2152d665590eaf754578b07766bc7adac247fd71ab`

The trusted run ledger records the terminal failure as sequence `20`, hash `05252ed85fb3dace5dfc55fc33395098bbe21a8d06130dc8166ccdaa86eebcda`.

## Required next decision

No further formal execution is authorized. A new attempt requires a separate user authorization that:

1. preserves attempt 1 byte-for-byte and excludes it permanently;
2. permits only a versioned producer-schema repair that adds and populates `formalCampaign=true` in every embedded `BlockChildRecord`;
3. keeps the strict wrapper requirement rather than weakening it;
4. requires an actual validation-only end-to-end Unity block rehearsal through the block wrapper;
5. re-runs every prelaunch hash, environment, storage, licensing and quiescence gate;
6. creates a new formal root and a new execution receipt;
7. authorizes exactly one new full attempt with no retry, resume, top-up or merge;
8. keeps formal analysis and Gate 14R unauthorized.

