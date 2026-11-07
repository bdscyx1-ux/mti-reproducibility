# Gate 13 cold-process → process-reuse controlled migration checkpoint

Saved: 2026-10-06 14:46 (Asia/Shanghai)

Status: `STOPPED / FAILED-NO-AUTO-RETRY / FORMAL-NOT-AUTHORIZED`

This checkpoint records the completed controlled termination of Gate 13 cold-process attempt 2, the Gate 13-R2 process-reuse design and pre-pilot verification, and the terminal failure of the single authorized non-formal process-reuse pilot v1. It is not a formal campaign authorization and it does not make any candidate sample-size output admissible.

## Material Passport

- Origin Skill: `academic-research-suite / experiment-agent`
- Origin Mode: `run`
- Verification Status: `FAILED-NO-AUTO-RETRY; EVIDENCE-SEALED; FORMAL-NOT-AUTHORIZED`
- Version Label: `gate13_r2_process_reuse_pilot_failure_checkpoint_v1`
- Authorization: user message dated 2026-10-06 authorizing the controlled cold-process → process-reuse design migration and one isolated non-formal pilot

## 1. Cold-process attempt 2 termination

The owned attempt-2 process tree was identified before termination. At the stop boundary it was executing:

- campaign: `1 / 74`, `g13-c001-core-r01-s1-shared-s4`;
- Williams block: `37`;
- position: `4`;
- algorithm: `C-FF`;
- run ID: `g13-c001-core-r01-s1-shared-s4-b037-p04-cff`;
- scenario runner PID at capture: `29232`;
- workload runner PID at capture: `5272`;
- Unity PID at capture: `15936`.

Only the owned subtree was terminated. The top-level orchestrator then exited through its fail-closed path. The resulting formal checkpoint is `failed-no-auto-retry`, no owned Gate 13 process remains, and the stopped root contains 147 independently observed completed samples.

The former cold-process root `H:\DDM_Final_Project\Research\FormalRuns\Gate13\v1` is frozen historical evidence:

```text
USER-TERMINATED-DESIGN-CHANGE
EXCLUDED_FROM_ANALYSIS
NO-AUTO-RETRY
NO-RESUME
SUPERSEDED-BY-PROCESS-REUSE-DESIGN
```

It contains 891 files / 129,667,391 raw bytes, with 891/891 files read-only. It must never be resumed, retried, completed, merged with process-reuse data, used for formal inference, used for formal sample-size estimation, or supplied to Gate 14 formal analysis.

Cold termination evidence:

| Artifact | SHA-256 |
|---|---|
| `Gate13_ColdProcess_Termination_Receipt.v1.json` | `4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4` |
| `Gate13_ColdProcess_PreTermination_Snapshot.v1.json` | `42c45962d19735ccb9387e4e2c348d493d30875738d6035843d377d4c9c948ec` |
| `Gate13_ColdProcess_Partial_Output_Manifest.v1.json` | `f3ea8fa2f39bfbbb89380efb0389fc1c1f7d0cdf3849cc0ae45da75c2e960c82` |
| `Gate13_ColdProcess_Exclusion_Marker.v1.json` | `076e5b0a599845f6c7424fda221507c5837c6aa49cdbe94427d2f6e9e00dd91e` |
| terminal cold checkpoint | `351ace32b633c0f155c624f6fbc9148f6139f909cb5f96063c2407aadeae4bdf` |

## 2. Gate 13-R2 frozen process-reuse design

The v1 design uses one fresh Unity Editor process per Williams block. A block runs its frozen 2- or 4-algorithm order in that process, and each algorithm appears at most once. It does not use one long-lived process per campaign. Each sample retains a distinct run ID, directory, manifest, workload result, summary, hash, and completion marker. Planner, grid/scenario state, runner/logger/metrics objects, forced-GC boundary, and mutable per-sample state are recreated or reset before the next sample. Any sample failure fails the block closed; later positions are not executed and no automatic retry/resume is allowed.

Frozen identities:

| Artifact | SHA-256 |
|---|---|
| `Gate13_ProcessReuse_Specification.md` | `06b8f79aff15301acb45a478ac054e0a444be3581fe4cb05f4c5a106dc6e256d` |
| `Gate13_ProcessReuse_Test_Design.md` | `45aed83d000ef8db41a5d910394422ba576ffe96a3543ac67415aa147bc1fefb` |
| `Gate13_ProcessReuse_Pilot_Plan.v1.json` | `de79edaca2bfd7016fd9a50dba85a511c2bdfc6bdce99d629e20e4bded4ca8d9` |
| `Gate13_ProcessReuse_Provenance.v4.json` | `91a8fcabdd157f7511eeda89e8355580954ed03222c51b5163f577b10354b82d` |
| process-reuse Unity command | `08ab7b3c593f55232d59d6266714eeae33c2c93be846e55ac8a235928fee1c33` |
| clean Unity compile v3 log | `b4f02654af7c09f44116665162186b4f2dd6abe0f67101aca2168b13b7c2d9fc` |

Gate 11 scenarios, deterministic seeds, canonical identities, exclusions, comparison cohorts, and Williams rows were not changed. The 10% precision target and cap 148 remain upper-level policy, but no process-reuse `n_formal` has been accepted.

## 3. Pre-pilot verification

The final pre-pilot audit passed 147 current assertions and independently bound the retained Gate 12 analysis regression result of 63/63. Its SHA-256 is `4be30a094cfc116a28f0b2f845dd0c73fdf221ab05d6bd4d756e601771b168c8`.

Positive process-isolation fixtures passed:

- four-algorithm block: 4/4 samples in Unity PID `30828`;
- two-algorithm block: 2/2 samples in Unity PID `3440`;
- all samples inside each block shared the block PID;
- the two blocks used different PIDs;
- frozen order, per-sample hashes, block manifest, and checkpoint all matched.

The retained negative fixture was hash-verified without rerun. It completed position 1, failed at position 2, did not execute later positions, emitted no block-completion manifest, reached `failed-no-auto-retry`, and attempted neither retry nor resume.

## 4. Single authorized non-formal pilot v1

The isolated root was `H:\DDM_Final_Project\Research\PilotRuns\Gate13_ProcessReuse\v1`. The run began at 2026-10-06 14:23:35 and completed its planned Unity execution at 14:35:35.

Execution cardinality was complete:

| Role | Unity processes | Samples |
|---|---:|---:|
| excluded warmup | 1 block process | 4 |
| fresh cold structural references | 8 sample processes | 8 |
| measured process-reuse | 36 block processes | 96 |
| total | 45 | 108 |

All 36 measured block processes completed, all 96 measured samples were present, and fresh-cold structural comparison reported 0 mismatches. This does **not** make the pilot successful: the analysis acceptance gate reported 208 hard errors.

Hard-error classification:

| Failure class | Count | Consequence |
|---|---:|---|
| non-positive `workingSetBytes` telemetry | 96/96 measured samples | OS working-set channel unusable in this Unity/Mono batch environment |
| non-positive `privateMemoryBytes` telemetry | 96/96 measured samples | OS private-memory channel unusable in this Unity/Mono batch environment |
| managed-memory block growth above frozen 128 MiB limit | 16/36 measured blocks | memory-growth acceptance test failed |

The managed/GC/process-age fields were populated; the zero-valued OS memory channels were isolated to `System.Diagnostics.Process` working-set/private-memory telemetry. Ten of twelve grouped-field two-algorithm blocks and six of twelve per-agent two-algorithm blocks exceeded the frozen managed-memory limit; none of the twelve shared four-algorithm blocks did. These findings require a new versioned diagnostic/measurement decision and cannot be waived after observing the data.

The terminal pilot checkpoint is `failed-no-auto-retry`. The run attempted 0 retries and 0 resumes. The generated `candidate-sample-sizes.json` and budget projections are diagnostic by-products only and are explicitly `CANDIDATE-N-NOT-ADMISSIBLE`; no `n_formal` is frozen from this pilot.

## 5. Failed-pilot preservation

The v1 pilot root is sealed as read-only historical evidence:

- file count: 838;
- raw bytes: 91,219,643;
- read-only files: 838/838;
- aggregate SHA-256: `c467cd4ca179f6e919fe9cbfdeee3cd2b4a32c19931bcdc285ca705555a59b38`;
- failure receipt SHA-256: `11f2331d55bb163a1254e7c2e1263f9cbc7c2e162f8bb5db20be5814d898c304`;
- output manifest SHA-256: `eb55ae56d047b44e4a6a7d0713b09437f4435162c19037e37aa5306ebf34c65d`;
- execution manifest SHA-256: `09ce291e7bdeaf4694d61bc034d9caf7478154eb40f5ac30bff52cd9ecd56ed4`;
- terminal checkpoint SHA-256: `8f498bb3b5517baa749799124d2ad636fb718a97372eb07a149ff32d2d2e101d`;
- pilot failure SHA-256: `d5ad7528cf0cfe73e487acaa41ba201a1cf5df333231296f122c83a7747abbc8`;
- failed pilot manifest SHA-256: `72fca3aa870be78e8925f81d2c736149d14d8fa957553578ee2ed06a1c38d014`.

Disposition:

```text
FAILED-NO-AUTO-RETRY
NON-FORMAL
EXCLUDED-FROM-FORMAL-ANALYSIS
NO-RESUME
NOT-READY-FOR-FORMAL
CANDIDATE-N-NOT-ADMISSIBLE
```

## 6. Formal/readiness boundary

- `H:\DDM_Final_Project\Research\FormalRuns\Gate13_ProcessReuse\v1` does not exist and must not be created under the current authorization.
- No process-reuse formal execution receipt exists or is authorized.
- No process-reuse formal amendment/config has been minted from the failed pilot. The post-pilot generator was intentionally not executed.
- Gate 13 is not complete. Gate 14 formal analysis must not start.
- Future Gate 13/Gate 14 formal work may reference only a later, separately authorized, successfully audited process-reuse formal root.
- The cold-process root and failed process-reuse pilot v1 must never be mixed into a formal analysis table.

## 7. Preserved inputs

The following remain unmodified and must continue to be preserved:

- `Research/Gate13_Execution_Authorization.v1.json` and `.v2.json`;
- attempt-1/attempt-2 cold-process logs, diagnostics, checkpoints, receipts, and termination evidence;
- `Research/Gate13_Readiness_Amendment.v1.json`;
- `Research/Gate13_Formal_Campaign_Config.v1.json`;
- `Research/PilotRuns/Gate12/v1/`;
- both Gate 12 failed-attempt archives;
- the Gate 11 retained bundle;
- original scripts and original scenes.

At seal time there were no Unity processes, no `Temp/UnityLockfile`, and no process-reuse formal root.

## 8. Exact next step

Stop here. The current authorization does not permit a retry, resume, repaired analysis rerun, replacement pilot, or formal campaign.

A future user authorization must explicitly establish a new versioned root (for example `Research/PilotRuns/Gate13_ProcessReuse/v2`) and decide, before execution:

1. how to collect valid Windows working-set/private-memory telemetry outside the Unity/Mono limitation, with a validation fixture that proves positive values;
2. whether the 128 MiB managed-memory rule identifies genuine within-process retention or an invalid endpoint/threshold, using a preregistered rule rather than a post-hoc waiver;
3. how v2 provenance binds the v1 failure receipt and preserves v1 read-only;
4. that v2 remains non-formal and cannot create a formal root or receipt;
5. that a successful fresh pilot and readiness audit are required before any separate formal process-reuse authorization can be considered.

