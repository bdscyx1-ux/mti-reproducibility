# Gate 13R-PR2 static schedule V5 attempt 1 failure diagnosis

The new validator compiled, then failed before committing its summary because it addressed the frozen schedule manifest through a nonexistent `totals` object. The manifest's count fields are root properties (`campaignCount`, `processRecordCount`, `sampleIdentityCount`, and `heterogeneousMatchedSuperblockCount`).

This is a validation-only implementation defect. It is not a schedule, data, Unity, or scientific-contract failure. The exact V5 script is retained under SHA-256 `6f2999f34678545cf0a37880f8708dbb7da3045696679b9a437b253a05aa4307`. The permitted repair is a new V6 validator that changes only the manifest property access and writes to a new summary path.

No formal root, formal execution receipt, formal status, Unity process, project lock, or measured sample was created.
