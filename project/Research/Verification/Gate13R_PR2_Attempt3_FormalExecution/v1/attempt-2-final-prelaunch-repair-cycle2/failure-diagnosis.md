# Gate 13R-PR2 attempt 3 prelaunch repair cycle 2 diagnosis

Status: `PRELAUNCH-FAILED-VERSIONED-REPAIR-ELIGIBLE`

The final audit completed all expensive preservation and environment checks. It passed 31 of 32 checks and failed only the validation-only parameter-binding aggregation.

The defect is isolated to the new audit harness. PowerShell array splatting treats a string array as positional arguments; strings such as `-ProjectPath` were passed as positional values instead of named parameters. No Unity Editor process was launched by this failure, and the formal root, execution receipt, and operational status remained absent.

The authorized repair changes only the smoke-test argument carrier to hashtable-based named splatting. It does not change any frozen input, formal schedule, memory policy, Unity command, block wrapper, endpoint, threshold, sample size, or two-stage commit rule.
