# Gate 13R-PR2 Attempt 3 operational monitoring and bounded recovery specification v1

## 1. Status and scope

This is a prospective, non-executing amendment created before any Gate 13R-PR2 formal attempt-3 observation. It adds operational monitoring and bounded software recovery without changing the experimental design, measured workload, algorithm code, scenario matrix, schedule, memory policy, statistical contract, sample size or two-stage raw/analysis commit.

This document does **not** authorize a formal root, formal execution receipt, formal status, Unity launch, measured sample, formal statistical analysis or Gate 14R.

## 2. Unchanged formal design

- Complete 74-campaign S48/H48 matrix.
- 3,552 fresh Unity Editor block processes and 10,176 algorithm samples.
- Strict serial topology; maximum concurrent Unity Editor count is one.
- One complete Williams block maximum per fresh process; one occurrence maximum per eligible algorithm; complete mutable-state reset per sample.
- Active PR2 v2 schedule/order/run/output identities, Williams rows, 1,008 matched-superblock identities and heterogeneous AB/BA 24/24 quotas remain byte-identical.
- MP2 scenario-size-aware memory policy, correctness/oracle/structural gates, telemetry, failure denominator, lock hygiene and two-stage commit remain frozen.

## 3. Monitoring topology

The operational watcher is external to Unity and external to the formal raw root.

- Silent watcher cadence: every 5 minutes while the local task and host are available.
- Scheduled user report cadence: once per 60-minute slot while status is `ACQUISITION-RUNNING` or `RAW-COMMIT-RECOVERY`.
- Event reports: on the first watcher tick observing start, failure, completion, action-required or a newly escalated stall condition.
- `NOT-STARTED`, `PRELAUNCH` and already terminal states remain quiet unless user action is required.
- A delayed watcher emits at most one report for the current slot. It never emits catch-up reports for every missed slot.

The watcher reads only the atomic formal status, execution receipt identity, current owned-process identity and OS operational telemetry. It may atomically write timestamped monitoring snapshots only below `Research/Monitoring/Gate13R_PR2_Attempt3/v1`; this root is operational evidence, not formal raw data. The watcher must never write beneath the formal root.

## 4. Blinded progress contract

An hourly progress report may contain only:

- Asia/Shanghai and UTC timestamps;
- Phase-A state and operational status;
- completed/total block processes and samples;
- current global process ordinal, campaign, scenario, cohort, block or matched-superblock, Williams row and AB/BA order;
- elapsed wall clock, rolling operational throughput and conservative operational ETA;
- current Unity composite identity `(PID, processStartTime, blockId)`;
- working set, private memory, available physical memory and MP2 advisory-count summaries;
- durable output file count, raw byte count, last-checkpoint time and last-write age;
- stall, failure, completion or action-required reason codes;
- exact checkpoint/status/receipt paths.

The report and monitoring snapshot must not contain or derive:

- per-algorithm or per-run timing values;
- P1-P5 or M1-M5 endpoint values;
- contrasts, effect estimates, confidence intervals, p-values or adjusted inferences;
- algorithm rankings, winners or superiority/non-inferiority signals;
- outcome-conditioned stop/continue recommendations.

Monitoring data cannot enter Gate 13R or Gate 14R statistical inference.

## 5. Status contract

The future attempt-3 orchestrator must atomically publish a status document conforming to `Gate13R_PR2_Attempt3_Operational_Status_Schema.v1.json`. It includes totals, current identities, timestamps, storage counters and operational telemetry but no performance endpoints. Every update uses write-to-temp, flush/fsync where supported and same-volume atomic replace.

The status source is valid only when it binds formal attempt ordinal 3, the exact v3 root, the exact execution receipt SHA-256 and the active V4 candidate/v2 schedule identities. A partial path set, malformed JSON, counter regression, total mismatch, future timestamp, composite-process mismatch or non-finite telemetry is `ACTION-REQUIRED`; it never authorizes a retry.

## 6. Read and notification retry

Read retry is not experiment retry.

- Atomic status/receipt reads: at most 3 total attempts with delays `0, 2, 5` seconds.
- OS process query: at most 3 total attempts with the same delays.
- Notification delivery: at most 3 delivery attempts with scheduler-level delays; failure is recorded outside the formal root.
- A successful later read does not erase earlier read anomalies.
- These retries never start, stop, signal, restart or replace Unity and never advance the formal schedule.

## 7. Stall classification

Stall detection is operational and advisory. Only the frozen block runner owns the 3,600-second hard timeout.

- Status last-write age `>15 minutes`: `STATUS-STALE-ADVISORY`.
- No durable process/sample/checkpoint progress for `>30 minutes` while a matching Unity process remains alive: `STALL-SUSPECTED` and immediate user report.
- Status says running but the exact composite Unity process is absent for `>5 minutes`: `PROCESS-IDENTITY-ACTION-REQUIRED`.
- Current block elapsed `>3,660 seconds`: `HARD-TIMEOUT-OVERDUE-ACTION-REQUIRED`; the monitor reports but never kills or retries.
- A long but identity-valid block below the runner timeout is never treated as a failed sample merely because the hourly count did not change.

## 8. Operational throughput and ETA

Monitoring snapshots use only completed-process counters and timestamps. When both an approximately one-hour rate and an overall-since-start rate are positive, the conservative rate is the smaller rate. ETA is `(remaining processes / conservative rate) × 1.25`. When no positive defensible rate exists, ETA is `UNAVAILABLE`; zero progress is not replaced with a fabricated estimate. ETA is operational guidance, not a completion guarantee or research result.

## 9. Prelaunch automatic repair/retry

Automatic prelaunch repair is allowed only when all are true:

1. exact formal v3 root, receipt and status are absent;
2. no measured process or sample has started;
3. the defect is confined to newly created attempt-3 orchestrator, schema, monitoring, reporting, checkpoint or validation-only code;
4. active V4 candidate, v2 schedule, MP2 policy and frozen upstream hashes remain unchanged;
5. the repair is versioned and the failed attempt keeps receipt, log, manifest, checkpoint and hashes;
6. targeted synthetic/validation-only tests pass before a new prelaunch attempt.

Limits:

- at most 3 automatic versioned repair cycles in this prelaunch stage;
- an unchanged failure signature on two consecutive repaired attempts stops automation;
- frozen hash mismatch, research-contract mismatch, ambiguous scenario mapping, scientific-identifiability failure, formal-path pre-existence or any need to relax a gate is non-repairable and requires user action.

Environment/license/storage probes may be re-read up to 3 times without code changes. They cannot be bypassed, downgraded or rewritten as passed.

## 10. Measured acquisition failure

From the first measured-process launch through acquisition completion:

- no measured sample or block is automatically retried;
- no resume, top-up, partial-attempt merge, skip, replacement, schedule advancement or attempt-4 creation is automatic;
- on any hard failure, the orchestrator must first persist the exact failure and partial manifest, then refuse to start the next block;
- the automatic diagnostic collector may capture read-only process tree, composite identity, OS telemetry, file/byte counters, lock state, environment snapshot and existing log/checkpoint hashes into the independent monitoring root;
- formal measured exit still accepts only natural Unity lock absence;
- terminal status remains `FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE` until a new explicit user authorization creates a new formal attempt.

## 11. Post-acquisition non-Unity commit recovery

After all 3,552 Unity processes and 10,176 samples are durably complete, Unity acquisition is permanently disabled for this attempt. A versioned non-Unity commit/freeze tool may be repaired and retried against the same raw tree only if:

- acquisition-complete evidence is present;
- the raw file count, raw byte count and canonical tree SHA-256 are stable across two independent reads;
- no Unity process or project lock exists;
- no measured output is added, removed or rewritten;
- each failed commit attempt is separately preserved;
- synthetic and validation-only commit tests pass before retry.

At most 3 versioned commit-recovery attempts are allowed. Two consecutive identical failure signatures stop automation. Any missing block/sample, raw-tree mutation, unverifiable hash or contract violation fails closed and requires a user decision. Recovery success may only produce `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`; it does not authorize Phase-B analysis.

## 12. Automation heartbeat

The Codex heartbeat identity is `gate13r-attempt3-hourly-progress`. After this amendment validates, it will be updated to a silent 5-minute watcher with hourly report throttling. It remains quiet before attempt 3 starts and after a terminal state has already been acknowledged. The heartbeat itself grants no execution or retry authority.

## 13. Stop condition

This stage succeeds only after schemas, state transitions, read-only guarantees, blinding, retry boundaries, synthetic fixtures, PowerShell/Python parsing and formal-path absence all pass. It then produces a new versioned attempt-3 authorization prompt and stops. Formal execution still requires a separate user message.
