# Gate 13 Formal Launch Attempt 2 Checkpoint

Saved: 2026-10-06 12:45 (Asia/Shanghai)

Status: **RUNNING — NOT COMPLETE**

This checkpoint records the authorized Gate 13 formal retry after successful launch. It is an observation and handoff record only. It does not authorize retry, resume, replacement samples, configuration changes, or concurrent execution.

## Material Passport

- Origin skill: `experiment-agent`
- Origin mode: `execute`
- Verification status: `LIVE-RUNNING / PARTIALLY VERIFIED / NOT FINAL`
- Version label: `gate13_formal_launch_attempt2_checkpoint_v1`
- Formal data authority: the runner-owned files under `Research/FormalRuns/Gate13/v1/`, not this narrative checkpoint

## User authorization and immutable binding

The user explicitly authorized attempt 2 on 2026-10-06 with these constraints:

- preserve the attempt-1 receipt, logs, diagnostics, and checkpoint unchanged;
- create a new versioned attempt-2 receipt bound to the same config, amendment, and output root;
- use the verified native Windows PowerShell 5.1 `PSModulePath` only while launching the child process;
- rerun receipt, hash, environment, and raw-byte storage preflight checks;
- create the formal root only after all checks pass;
- continue the frozen 74-campaign / 15,056-sample schedule;
- prohibit automatic retry and automatic resume;
- on another failure, preserve new evidence and stop.

The created receipt is:

- path: `Research/Gate13_Execution_Authorization.v2.json`;
- authorization id: `gate13-formal-execution-v2-20261006T124113p0800`;
- attempt: `2`;
- retry of: `gate13-formal-execution-v1-20261006T123007p0800`;
- SHA-256: `5f3898914c29a3413f70d1ee1c5b7afbe84c05ac7987677f6083227dd93417a8`;
- config SHA-256: `b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874`;
- amendment SHA-256: `1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2`;
- output root: `Research/FormalRuns/Gate13/v1`;
- automatic retry: `false`;
- automatic resume: `false`.

The attempt-2 receipt validator passed before execution. The frozen module, config generator, cap-148 scenario runner, top-level orchestrator, config, amendment, Gate 11 retained bundle, Gate 12 successful pilot, and attempt-1 evidence were rechecked before launch. No frozen runner was modified.

### Attempt-1 preservation audit

The following attempt-1 core evidence remained byte-identical after attempt-2 launch:

- `Research/Gate13_Execution_Authorization.v1.json`: `864740f428c8a0c40c9883c9b9a77988968e68610cf19d48d61529959ec95cc8`;
- `Research/Gate13_Formal_Launch_Attempt1_Checkpoint.md`: `fa31b804b3f8e4d8b402c4e7031a96416af23987cab9a3566b50fcc20ab7c3d4`;
- `Research/Verification/Gate13_Formal_Launch.v1.stdout.log`: empty-file SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`;
- `Research/Verification/Gate13_Formal_Launch.v1.stderr.log`: `5688fb7a5387bfba8223a8165c4f7765ed3f5ac34252d8b57e4630607f5f1b99`;
- hidden-diagnostic v1 stderr: `fc2b9f9e8b265bd7fb26333e665e9299345205c380fcb3dbfa7865a1613257a0`;
- hidden-diagnostic v2 stdout: `729e5e4489cdae1a5d844e8d191082903e465cce32212faaa758db0ba3168e0f`;
- hidden-diagnostic v3 stdout: `41e512c82d1376c21b73bf13ab86c0276dcbbc4741b7797d39f04550871efdda`.

The complementary diagnostic stdout/stderr files that were empty remain empty-file SHA-256. Their original last-write timestamps were also unchanged.

## Launch-only environment correction

The parent environment was changed only for the `Start-Process` call and restored immediately afterward. The child received exactly the native Windows PowerShell 5.1 module roots:

1. `C:\Users\bdscy\Documents\WindowsPowerShell\Modules`
2. `C:\Program Files\WindowsPowerShell\Modules`
3. `C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules`

This corrected the attempt-1 host-environment failure without changing any frozen script.

## Preflight evidence

### Independent validation-only preflight

- result: passed;
- log: `Research/Verification/Gate13_Formal_Preflight.v2.stdout.log`;
- log SHA-256: `75aacceca34ccfdcaef61b2a454d1183fd2627a16ab203d9398b72e1bfca0b3b`;
- stderr: empty;
- free bytes: `162,195,087,360`;
- minimum: `74,417,330,489`;
- margin: `87,777,756,871`;
- mean CPU load: `2.8%`;
- no Unity process, no Unity lock, and no formal root at validation time.

### Runner-owned launch preflight

`Research/FormalRuns/Gate13/v1/launch-preflight.json` was captured at `2026-10-06T12:42:39.0519625+08:00` immediately before root creation and reports:

- overall result: `passed = true`;
- AC line online: `1`;
- active power scheme: High performance, GUID `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`;
- free physical memory: `21,408,137,216` bytes;
- mean CPU load: `4.6%` across five samples;
- temperature unavailable under the frozen fallback policy;
- Unity processes at check: `0`;
- Unity lock present: `false`;
- formal root present at check: `false`;
- free bytes: `162,195,083,264`;
- minimum: `74,417,330,489`;
- margin: `87,777,752,775`;
- storage check: passed.

Only after this runner-owned preflight passed did the runner create the formal root.

## Launch and live evidence

- top-level launch time: `2026-10-06T12:42:18.7943107+08:00`;
- observed top-level Windows PowerShell PID: `3476`;
- exact runner: `Research/Run-Gate13FormalCampaign.ps1`;
- receipt argument: `Research/Gate13_Execution_Authorization.v2.json`;
- live stdout target: `Research/Verification/Gate13_Formal_Launch.v2.stdout.log`;
- live stderr target: `Research/Verification/Gate13_Formal_Launch.v2.stderr.log`;
- formal root: `Research/FormalRuns/Gate13/v1`;
- frozen config copy SHA-256: `b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874`;
- receipt copy SHA-256: `5f3898914c29a3413f70d1ee1c5b7afbe84c05ac7987677f6083227dd93417a8`.

At `2026-10-06T12:44:55.7573459+08:00`:

- the top-level orchestrator was alive;
- checkpoint status was `running-campaign`;
- current campaign ordinal/id was `1 / g13-c001-core-r01-s1-shared-s4`;
- campaign-level checkpoint counts were still `0 campaign / 0 sample`, as expected until the first 208-sample campaign closes;
- independently observed completed sample summaries: `8`;
- invalid completed sample summaries: `0`;
- duplicate run ids: `0`;
- latest completed run: `g13-c001-core-r01-s1-shared-s4-b002-p04-idff`;
- active next Unity run: `g13-c001-core-r01-s1-shared-s4-b003-p01-cff`;
- campaign subtree size: `7,006,653` bytes;
- H: free space: `162,187,423,744` bytes;
- `formal-failure.json`: absent;
- `formal-result.json`: absent.

For all first eight completed sample summaries, an independent check confirmed:

- summary `passed = true`;
- Unity exit code `0`;
- compiler-error match count `0`;
- embedded manifest `completed = true`;
- canonical scenario SHA-256 matches its manifest;
- operations JSONL SHA-256 matches its manifest;
- workload-result SHA-256 matches its manifest.

This proves that attempt 2 crossed the launch gates and is producing valid formal artifacts. It does **not** prove campaign or Gate 13 completion.

### Follow-up health check

At `2026-10-06T12:47:29.6340767+08:00`, a second independent read-only check confirmed:

- the same receipt-bound top-level orchestrator command line was alive;
- checkpoint remained correctly at campaign `1 / 74`;
- completed sample summaries increased from `8` to `19`;
- all 19 completed samples passed the same summary/completion/three-hash audit;
- invalid samples: `0`;
- duplicate run ids: `0`;
- exactly one Unity batch process was active;
- active run: `g13-c001-core-r01-s1-shared-s4-b005-p04-cff`;
- campaign subtree increased to `16,639,693` bytes;
- newest output timestamp was `2026-10-06T12:47:26.1873839+08:00`;
- H: free space was `162,177,495,040` bytes;
- failure marker: absent;
- final marker: absent.

The active High performance power scheme was also queried read-only. Its AC standby timeout and AC hibernate timeout are both `0` seconds (disabled). Hybrid sleep is enabled as a capability, but there is no idle sleep/hibernate trigger on AC. No power setting was changed.

At `2026-10-06T12:48:49.2674386+08:00`, the final handoff audit fixed the saved evidence point at `24 / 24` completed sample summaries passing, `0` invalid samples, and `0` duplicate run ids. A simultaneous liveness snapshot showed exactly one active Unity batch process, continued output growth, `162,173,149,184` bytes free on H:, and no failure or final marker. Counts after this timestamp are intentionally not chased in this checkpoint because the authorized runner remains live.

## Live-run boundary

- Do not open this Unity project in the interactive Unity Editor while the campaign is running.
- Keep the computer on AC power, awake, and on the High performance scheme.
- Do not reboot, sign out, suspend, rename/move the project, edit frozen inputs, or manually alter `Research/FormalRuns/Gate13/v1/`.
- Do not launch another Gate 13 runner or another Unity process against this project.
- Do not interpret the campaign-level `completedSampleCount = 0` as a stall while campaign 1 is still producing per-sample summaries; the top-level checkpoint updates at campaign boundaries.
- Advisory output-growth checks do not authorize termination. Only the frozen hard-timeout logic may terminate its owned process tree.

## Exact resume/inspection procedure

On the next interaction, inspect without launching anything:

1. `Research/FormalRuns/Gate13/v1/formal-checkpoint.json`;
2. `Research/FormalRuns/Gate13/v1/formal-failure.json`, if present;
3. `Research/FormalRuns/Gate13/v1/formal-result.json`, if present;
4. the current command lines for `Run-Gate13FormalCampaign.ps1`, `Run-Gate13FormalScenarioCampaign.ps1`, and Unity;
5. the count and validity of `*.summary.json`, `manifest.json`, and `workload-result.json` files;
6. H: free bytes and the newest output timestamp;
7. the attempt-2 stdout/stderr logs.

Do not rely on PID `3476` alone because PIDs can be recycled. Match command line, config, receipt, and output root.

- If the orchestrator is alive and output is advancing, continue read-only monitoring only.
- If `formal-result.json` exists, verify the final counts/hashes before declaring Gate 13 complete.
- If `formal-failure.json` exists, or the orchestrator is gone without a valid final result, preserve the atomic checkpoint and all partial output, document attempt 2 as failed, and stop.
- Under no condition may this checkpoint be treated as authorization for automatic retry, resume, deletion, overwrite, or an attempt 3.
