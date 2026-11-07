# Gate 13R-PR2 validation-only attempt 3 failure diagnosis

Attempt 3 reached the complete core validator. Sixty-two of sixty-three checks passed. The sole failure was a typo-level mismatch in the newly created schema: `matchedSuperblockCount` was required although the generated schedule manifest consistently names the field `heterogeneousMatchedSuperblockCount`.

The schedule itself passed all counts and balance checks: 3,552 process records, 10,176 samples, 74 campaigns × 48 blocks, 1,008 matched superblocks, per-scenario AB/BA 24/24, order × row cells 12 each, and all preset/Playable identities. Deterministic regeneration was byte-identical. Frozen upstream trees passed both pre- and post-validation audits. No Unity process, formal root, formal execution receipt, Gate 13R run, or Gate 14R activity occurred.

Because the final formal config must not remain bound to a known-invalid schema, the repair will version the complete artifact set rather than merely ignoring the schema failure:

- schema v2 corrects the manifest property name;
- generator v2 binds schema v2 and produces config/schedule/manifest/preflight/provenance/summary v2;
- validator/orchestrator v4 targets only the v2 artifact set and a fresh v4 verification root;
- v1 official artifacts and v1–v3 validation evidence remain immutable history.

No scientific or operational threshold changes.
