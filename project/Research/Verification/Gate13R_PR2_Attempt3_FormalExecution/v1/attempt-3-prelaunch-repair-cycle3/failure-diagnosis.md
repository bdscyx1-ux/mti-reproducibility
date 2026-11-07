# Gate 13R-PR2 attempt 3 prelaunch repair cycle 3 diagnosis

The native PowerShell launcher reached Python, but Python stopped during argument parsing before `create_receipt` and before any formal target or Unity process existed. The unparenthesized expression `$PSHOME + '\powershell.exe'` was embedded directly in an array expression and was emitted as two command-line items.

This is an isolated precommit launcher defect. The final allowed prelaunch repair creates a V2 launcher with a scalar, fully resolved PowerShell executable path before the argument array is built. The repaired launcher must pass PS5/PS7 parser and binding checks, a formal-commandline capture fixture, no-launch dry runs, static tests, and a fresh final audit. No frozen scientific or execution semantics may change.
