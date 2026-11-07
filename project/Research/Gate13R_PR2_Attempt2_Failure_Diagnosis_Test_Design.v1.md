# Gate 13R-PR2 attempt 2 failure diagnosis test design v1

## Boundary

All tests are non-executing and must statically prove that no Unity command, attempt-3 formal root, formal execution receipt, P1-P5 inference, or Gate 14R work is invoked. Synthetic fixtures are written only to a temporary test directory and are never mixed with the failed root.

## Test groups

1. **Authorization and frozen identity**
   - prompt, exact user authorization, execution receipt, status, checkpoint, schedule, and failed memory-evaluation hashes;
   - stable root count/bytes/tree hash;
   - partial-manifest 28,019 plus self-write reconciliation;
   - failed root remains unchanged before and after analysis.

2. **Canonical manifest**
   - ordinal path ordering, forward-slash normalization, UTF-8/LF serialization;
   - duplicate/case-colliding relative path rejection;
   - deterministic regeneration from identical bytes;
   - file mutation between enumeration and hash must fail visibly.

3. **Memory arithmetic**
   - exact byte/MiB conversion;
   - sample delta equals after-cleanup minus before-sample;
   - block baseline equals after-cleanup minus block delta;
   - valid negative deltas are retained;
   - negative raw byte counts, missing fields, strings, NaN, Infinity, and identity conflicts are rejected or explicitly classified invalid;
   - equality with a threshold passes; one byte over fails;
   - 512/640/768/1,024 MiB scenarios use block maxima, not independent samples.

4. **Composite identity and grouping**
   - PID/start-time/block/run identity;
   - algorithm, Williams position, predecessor, scenario, campaign, grid-size grouping;
   - missing grid size remains `UNCLASSIFIED`, not imputed;
   - incomplete failed block is retained and marked partial.

5. **Failure precedence**
   - primary memory failure timestamp precedes secondary quiescence failure;
   - secondary failure cannot overwrite primary reason;
   - both failures remain fail closed;
   - candidate wrapper semantics never continue the block or campaign.

6. **Lock safety**
   - exact target only;
   - zero Unity and exited orchestrator required;
   - reject directory, reparse point, nonzero bytes, wrong SHA/timestamp, or exclusive-open failure;
   - cleanup receipt must prove post-delete absence and frozen-root hash invariance.

7. **Scope enforcement**
   - no P1-P5 timing/effect estimator;
   - no C1-C5 contrast;
   - no formal sample-size result;
   - no Unity executable invocation;
   - no attempt-3 root or receipt;
   - output status remains `FAILURE-DIAGNOSTIC-ONLY` and policy remains `UNFROZEN`.

## Final validation-only audit

The final audit passes only if synthetic tests, real-root schema/identity checks, deterministic regeneration, output SHA-256 manifest, root pre/post canonical hash equality, read-only freeze, lock cleanup receipt, and ARS run-ledger integrity all pass. Any scientific-identifiability limitation remains visible and results in `TARGETED-NON-FORMAL-MEMORY-PILOT-REQUIRED`; it is not repaired by relaxing a threshold.
