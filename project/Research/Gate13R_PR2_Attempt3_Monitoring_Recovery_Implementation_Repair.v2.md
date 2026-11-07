# Gate 13R-PR2 attempt 3 monitoring implementation repair v2

Status: **VERSIONED PRELAUNCH IMPLEMENTATION REPAIR — NO UNITY — NO FORMAL TARGETS**

## Defect

The frozen v1 specification requires scheduled reports during both acquisition and Phase-A raw-commit recovery. The v1 monitor's notification function tested only `ACQUISITION-RUNNING`, so a long `ACQUISITION-COMPLETE-COMMIT-PENDING` or `RAW-COMMIT-RECOVERY` interval would not receive its hourly report.

## Repair

- Preserve every v1 artifact, readiness checkpoint, terminal audit, evidence manifest, and authorization prompt byte-for-byte.
- Add a v2 config with an explicit `scheduledReportStates` registry.
- Add a v2 Python entry that mechanically reuses the v1 monitor and replaces only scheduled-notification classification plus active-state stale-status classification.
- Add a v2 PowerShell entry bound to the v2 monitor/config.
- Re-run the original full validation suite against v2 and add explicit raw-commit hourly/stale tests.

## Unchanged boundaries

- 5-minute watcher and 60-minute report cadence.
- No catch-up flood.
- Operational blinding.
- `0/2/5` read retry.
- At most three versioned prelaunch repair cycles and same-signature stop after two.
- No measured retry/resume/top-up/merge/skip/replace/advance.
- Post-acquisition recovery remains non-Unity and targets only the same proven-complete raw tree.
- No formal root, receipt, status, Unity launch, formal analysis, or Gate 14R is authorized by this repair.
