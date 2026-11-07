# Gate 13R-PR1B v4 Composite Process Identity Specification

Status: `FROZEN-BEFORE-REAL-PILOT-NUMERIC-ANALYSIS / NON-EXECUTING / FORMAL-CAMPAIGN-NOT-AUTHORIZED`

## Scope

This specification repairs only the process-identity contract used by the post-execution analyzer. It does not change the frozen v3 pilot bytes, experimental samples, P1-P5 definitions, C1-C5 directions, AB-minus-BA estimands, Williams schedule, memory policy, exclusion rules, or inferential thresholds.

## Identity definitions

1. The numeric Windows PID is an operating-system handle that may be reused after the earlier process exits. A numeric PID alone is not a globally unique identity across the full pilot.
2. The OS process identity key is the ordered pair `(processId, processStartTimeUtc)`.
3. The block evidence identity key is the ordered triple `(processId, processStartTimeUtc, blockId)`.
4. `processStartTimeUtc` must be a non-empty RFC 3339 UTC value ending in `Z`, must parse to a timezone-aware instant, and must be no later than the block start, block completion, wrapper completion, and frozen execution completion.
5. The process lifetime used for overlap validation is the half-open interval `[processStartTimeUtc, wrapperSummary.completedAt)`. The wrapper completion timestamp is used because the wrapper observes Unity process termination before completing.
6. Reuse of a numeric PID is legal if and only if every earlier interval for that PID ends at or before the later process start. Equality at the half-open boundary is legal.

## Fail-closed conditions

Analysis is ineligible if any of the following occurs:

- duplicate OS process identity key;
- duplicate block evidence identity key;
- overlapping lifetimes for the same numeric PID;
- missing, malformed, non-UTC, future, or temporally impossible `processStartTimeUtc`;
- mismatch among execution entry, block manifest, sample entry, sample summary, or wrapper PID;
- one OS process identity mapped to more than one block;
- one block mapped to more than one OS process identity;
- duplicate run ID;
- duplicate schedule key `(role, scenarioId, block, superblockOrder, comparisonCohortId)`;
- an incomplete block/sample, broken evidence hash, failed reset/correctness/memory gate, scenario mismatch, or Williams-order mismatch.

## Cardinality requirements

- 12 excluded warm-up block processes and 24 excluded warm-up samples;
- 384 measured block processes and 768 measured samples;
- 396 total block process records and 792 total sample records;
- 396 unique OS process identity keys;
- 396 unique block evidence identity keys;
- 768 unique measured run IDs and 792 unique total run IDs;
- 96 complete measured mirrored pairs and 192 measured matched superblocks.

## Preservation and isolation

- Frozen source root: `Research/PilotRuns/Gate12R_ProcessReuse_5pct/v7-gate13r-pr1b-order-effect-pathsafe-v4`.
- Required frozen source tree SHA-256: `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`.
- The source root is read-only by contract. No repaired analysis, receipt, manifest, checkpoint, log, or temporary file may be written within it.
- New outputs are limited to `Research/Analysis/Gate13R_PR1B_CompositeProcessIdentity_Recovery/v1` and the versioned validation root.
- `Research/FormalRuns/Gate13R_RQAligned/v1` must remain absent.
- No command in this stage may launch Unity Editor or generate, retry, resume, top up, or merge samples.

## Statistical invariance

The recovered analyzer must preserve exactly:

- P1-P5 and C1-C5;
- natural-log ratio and AB-minus-BA direction;
- 95% confidence intervals;
- absolute order-effect bound `log(1.10)`;
- 20,000 whole-mirrored-pair bootstrap replicates and seed `13012026`;
- three scenarios, 32 mirrored pairs per scenario, equal-scenario pooled weighting;
- all-complete-eligible-pairs primary analysis including memory alerts;
- no-alert analysis as sensitivity only;
- P5 zero-event handling without pseudocounts;
- prohibition of formal superiority or pure-algorithm causal claims.

Recovered output must be labeled `ANALYSIS-RECOVERY-FROM-COMPLETE-FAILED-NONFORMAL-PILOT / PILOT-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS`.
