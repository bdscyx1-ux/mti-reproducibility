# Gate 13R-PR2 final prelaunch V1 attempt 1 failure diagnosis

The validation-only script called `Read-G13RPR2TextWithRetry` with `MaximumWaitSeconds`; the frozen helper's actual bounded-time parameter is `TimeoutMilliseconds`. This is a PowerShell named-parameter compatibility defect in the new prelaunch validator, not an experiment, Unity, frozen-input, or scientific-contract failure.

The exact failed V1 implementation remains under SHA-256 `9aa63898f87aa15952f346d6758a3566a68be94260a01048573522182ef1c856`. The permitted V2 repair changes only that argument to `-TimeoutMilliseconds 30000` and writes to an independent output path.

No formal attempt was consumed.
