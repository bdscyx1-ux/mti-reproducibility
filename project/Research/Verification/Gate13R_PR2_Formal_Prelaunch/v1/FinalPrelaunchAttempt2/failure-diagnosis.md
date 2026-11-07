# Gate 13R-PR2 final prelaunch V2 attempt 2 failure diagnosis

The full audit committed 24/26 passing checks. Frozen-tree integrity, active hashes, previous self-tests, license evidence, network, storage, CPU load, AC power, native PowerShell identity, Unity quiescence, and formal-root absence all passed.

Only the localized `powercfg` label parser failed. The underlying `STANDBYIDLE` and `HIBERNATEIDLE` blocks both contain AC index `0x00000000`; `HKLM\SYSTEM\CurrentControlSet\Control\Power\HibernateEnabled` is `0`. V3 therefore changes only how these already-required states are read: it selects the penultimate hex index in the setting block (AC precedes DC) and verifies the registry hibernation flag. Thresholds and requirements are unchanged.
