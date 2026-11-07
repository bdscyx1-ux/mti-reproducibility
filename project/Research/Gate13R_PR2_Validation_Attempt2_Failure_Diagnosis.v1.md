# Gate 13R-PR2 validation-only attempt 2 failure diagnosis

## Outcome

Attempt 2 again failed closed before the core validator started. Zero Unity processes were observed before and after; the future formal root and formal execution receipt remained absent.

## Refined root cause

Attempt 2 fixed the new orchestrator to order canonical tree-manifest rows with `.NET StringComparer.Ordinal`. That repair worked consistently under Windows PowerShell 5.1. However, the v1 pre-write audit's expected hashes had been captured with PowerShell 7 `Sort-Object FullName`, which uses runtime/culture collation rather than an explicitly specified ordinal comparator.

Four larger trees therefore received different tree-level hashes under the corrected algorithm, while every file count and total raw-byte count stayed identical. The remaining two trees happened to have filename sets for which the two orders coincide. Pre/post attempt-2 identities were identical for all six trees, proving the validator did not change them.

## Versioned repair

The v1 pre-write audit remains immutable historical evidence. A new v2 audit will:

- name its algorithm `relative-path-UTF8-size-fileSHA256-lines-sorted-StringComparer.Ordinal-v1`;
- retain the same six absolute roots, file counts, byte counts, key-file hashes, and absence checks;
- record the corrected cross-runtime canonical hashes;
- explain that the identity amendment changes serialization order only, not the frozen bytes.

Attempt 3 will use new v3 validator/orchestrator files and a new v3 validation root. No scientific, schedule, resource, or authorization gate changes.
