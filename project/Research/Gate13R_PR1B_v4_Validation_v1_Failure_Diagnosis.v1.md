# Gate 13R-PR1B v4 validation v1 pre-recovery failure diagnosis

Status: `FAILED-PRE-RECOVERY / RECOVERY-NOT-STARTED / VERSIONED-VALIDATION-ONLY-REPAIR-ALLOWED`

The 24 validation checks executed successfully in memory, but the v1 PowerShell `Write-AtomicJson` helper appended the single-quoted string ``'`n'``. In PowerShell, the backtick escape is not expanded inside single quotes, so `validation-summary.json` ends with the two literal characters `` `n `` after the closing JSON brace. The recovery wrapper correctly failed while parsing that file and stopped before calling the Python recovery analyzer.

Consequences:

- no Unity process was launched;
- no pilot sample was generated, retried, resumed, topped up, or merged;
- no P1-P5/C1-C5 recovery analysis ran;
- no recovery root was created;
- the one authorized read-only recovery invocation was not consumed;
- the frozen v7 pilot tree remains byte-identical at `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`.

Allowed versioned repair: create a new v2 validation orchestrator/root and v2 recovery wrapper that append a real LF with a double-quoted PowerShell string, rerun all validation-only gates, and only then use the still-unused single recovery authorization. The v1 verification root and scripts remain frozen.
