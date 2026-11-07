# Gate 12 Pre-Sample Failure Checkpoint

Saved: 2026-10-05 (Asia/Shanghai)  
Status: stopped before the first Unity sample; retry requires an explicit user decision  
Gate 13 status: not started and not authorized

## What completed

- Gate 12 specification, test design, and machine-readable plan were frozen before production implementation.
- `Gate12_PreImplementationAudit.summary.json` passed with Gate 11 bundle aggregate `91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88` and original baseline 24/24.
- The first implementation unit-test pass completed with 55 assertions and no failures.
- A no-output real-machine preflight passed: AC online, High performance power scheme, no Unity process/lock, sufficient CPU/RAM/disk capacity, and all frozen hashes correct.
- The authorized pilot command was invoked once. It captured the start environment but stopped before warm-up or measured execution.

## Exact failure

The first checkpoint attempted to evaluate `.Sum` on the empty collection of completed campaigns while `Set-StrictMode` was active:

```text
Gate 12 pilot failed without auto-retry: The property 'Sum' cannot be found on this object.
```

The affected state was `completedMeasuredCampaignCount = 0`. The workload/campaign runner was never invoked.

## Preserved evidence

- Failed attempt root: `Research/PilotRuns/Gate12/v1/`
- Only file: `environment-start.json`
- Captured at: `2026-10-05T20:43:23.2416129+08:00`
- File bytes: `20841`
- SHA-256: `a643e1791fb157bc4a96fbc871242cdd7772d188eb076cf402f823aa37b7ffe3`
- Preflight verdict inside the file: passed
- Warm-up Unity process count: `0`
- Measured Unity process count: `0`
- Formal Unity process count: `0`
- Unity process count after stop: `0`
- `Temp/UnityLockfile`: absent

No file was deleted, overwritten, or moved. The absence of a generated `pilot-failure.json` is also explained by the same empty-collection expression being present in the catch handler; this checkpoint is an operator-authored reconstruction and is not represented as runner-generated evidence.

## Repair prepared

The aggregation was replaced by `Get-Gate12CompletedSampleCount`, which explicitly iterates zero or more entries and rejects negative counts. Unit tests now cover:

- empty list → `0`;
- `16 + 32` → `48`;
- negative count → rejection.

The failed root remains at the frozen create-new destination. A new attempt must not overwrite or silently resume it. The permitted recovery, after explicit user approval, is:

1. move the failed root intact to `Research/PilotRuns/Gate12/v1-failed-pre-sample-attempt1/`;
2. write a move receipt with before/after file hash and zero-sample attestation;
3. rerun the frozen `v1` plan at its original create-new path;
4. retain the archived failed attempt permanently outside measured/formal inputs.

