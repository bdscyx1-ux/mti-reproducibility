# Gate 13R-PR2 attempt 3 monitoring/recovery readiness v2

Status: **PASSED — ACTIVE V2 MONITOR — NON-EXECUTING — FORMAL ATTEMPT 3 NOT AUTHORIZED**

## Why v2 exists

The preserved v1 monitor passed its initial suite but a terminal review found that hourly scheduling was limited to `ACQUISITION-RUNNING`. The frozen specification also requires hourly operational reports while Phase-A raw commit is pending or being recovered. No formal target or Unity process existed when this implementation-only defect was found.

The v1 readiness, audit, prompt, code and evidence remain immutable and are superseded by this checkpoint. The v2 repair adds explicit scheduled report states:

- `ACQUISITION-RUNNING`;
- `ACQUISITION-COMPLETE-COMMIT-PENDING`;
- `RAW-COMMIT-RECOVERY`.

## Validation

- Historical validation attempt 1: preserved 53/54 test-assertion failure.
- Historical validation attempt 2: preserved 54/54 against v1 implementation.
- Post-readiness defect receipt: preserved.
- Active validation attempt 3: **56/56 passed**, including all prior checks plus raw-commit hourly reporting and raw-commit stale-status advisory.
- Python, PowerShell 7 and Windows PowerShell 5.1 parser/binding: passed.
- Unity invocations: 0.
- Formal root/receipt/status: absent.
- All 18 active upstream key hashes and all superseded v1 artifact hashes: unchanged.

## Active monitoring files

- `Research/Gate13R_PR2_Attempt3_Monitoring_Config.v2.json`
- `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Implementation_Repair.v2.md`
- `Research/Gate13RPR2Attempt3MonitoringRecoveryV2.py`
- `Research/Get-Gate13RPR2Attempt3OperationalProgressV2.ps1`
- `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_Evidence_Manifest.v3.json`
- `Research/Gate13R_PR2_Attempt3_Monitoring_Recovery_PostValidation_Preservation_Audit.v2.json`

The v1 base specification, state machine and schemas remain binding unless explicitly superseded by the narrow v2 implementation-repair note.

## Recovery and execution boundary

- Prelaunch versioned repair remains limited to three cycles total; one cycle has been consumed by this repair.
- During measured acquisition, automatic action remains diagnostics/notification only. No measured retry, resume, top-up, merge, skip, replacement, next-block advancement after hard failure, or attempt 4 is allowed.
- After complete acquisition, only non-Unity raw-commit recovery against the same stable tree is permitted, subject to the frozen prerequisites and three-attempt limit.
- Formal statistical analysis and Gate 14R remain unauthorized.

The next step is a separate user authorization using the active v3 authorization prompt.
