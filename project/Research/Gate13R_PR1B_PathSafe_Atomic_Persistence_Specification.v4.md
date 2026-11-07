# Gate 13R-PR1B path-safe atomic persistence specification v4

## Scope

This specification is a narrow Windows PowerShell 5.1 compatibility amendment to the frozen v3 design. It does not alter the Unity C# path-safe persistence implementation, memory eligibility, experimental schedule, statistics, reset semantics, or authorization boundary.

## Existing mutable target replacement

For a mutable checkpoint or telemetry-status file that already exists:

1. Resolve and validate the final target and its existing ordinary parent directory.
2. Reject a reparse-point parent.
3. Generate two independent short leaves in that same parent:
   - `.g13tmp-<32-lowercase-hex-guid>` for the new bytes;
   - `.g13bak-<32-lowercase-hex-guid>` for the replace backup.
4. Require both leaves to be absent before use.
5. Create the temporary file with `FileMode.CreateNew`, exclusive sharing, UTF-8 without BOM, stable newline normalization, and deterministic JSON serialization supplied by the caller.
6. Revalidate target type and parent identity immediately before commit.
7. Call the four-argument `System.IO.File.Replace(temp, final, backup, true)` so Windows PowerShell 5.1 never receives a null backup path.
8. Delete only the helper-owned backup leaf after a successful replace. On failure, delete only helper-owned temporary/backup leaves that actually exist, then propagate the error.

For a target that does not exist, commit with a same-directory `File.Move`. Immutable evidence targets must continue to reject overwrite; this helper is used only where the calling contract explicitly permits mutable replacement.

## Path and ownership invariants

- Temporary, backup, and final paths are on the same volume and share one verified parent.
- Temporary and backup leaves have fixed length 40 characters.
- The helper never appends a long suffix to the final filename.
- A directory target is rejected.
- A pre-existing temporary or backup leaf is rejected; it is never deleted as though helper-owned.
- Only leaves generated for the current invocation may be cleaned up.
- v12 is preserved byte-for-byte and is never resumed.

## Frozen experimental contract

The v3 experimental contract remains unchanged: exactly one fresh Unity Editor process per complete Williams block, strict serial execution, 12 excluded warm-up processes, 384 measured block processes, 768 measured samples, three heterogeneous scenarios, 32 mirrored pairs per scenario, unchanged P1-P5/C1-C5/order-effect estimands, unchanged memory thresholds, and exactly one fresh NON-FORMAL pilot only after all v13 gates pass.

Gate 13R formal execution and Gate 14R remain unauthorized.

