# Gate14Re-ME bounded qualification v4 — frozen implementation summary

Status: **superseded draft; user requested no freeze while oracle-stage simplification is deployed; execution unauthorized**.

This document records the pre-oracle-simplification state only. It is not the final design freeze. The then-current implementation still used 126 independent oracle Unity processes and repeated reference-oracle computation inside every algorithm lane; that omission is being corrected under a new versioned implementation rather than silently changing this draft.

This version replaces the excessive-load acquisition design exposed by attempt-009 while preserving the scientific comparison structure: the same six algorithms run as a paired set inside every independent superblock, in a strictly serial, fresh-Unity-process schedule with zero replacement. No new qualification run was started during this work.

## 1. B decision

`B` is the number of independent six-algorithm paired superblocks per `G × N × F` cell in the later formal ST design. It is not the number of individual algorithm runs, and the six algorithms inside one superblock are not six independent samples.

Attempt-009 cannot freeze the final `B` because it used a different G×N×F support, included the excessive-load tail now being removed, and did not reach terminal qualification PASS. Choosing `B` from named outcome separation would also be outcome-driven.

The reusable planning rule is therefore:

- final `B`: unset (`null`);
- provisional minimum: `B = 36`;
- allowed candidate grid: positive multiples of 36 (`36, 72, 108, 144, ...`);
- finalization: only after the bounded v4 qualification passes and a reproducible anonymous power calculation is frozen before formal collection.

Attempt-009 may be reused only for anonymous nuisance variance/covariance sensitivity, structural failure and missingness information, and engineering runtime/memory/storage priors. Its observations cannot become formal samples.

## 2. Bounded G×N×F design

- `G` (grid edge): `64, 96, 128`
- `N` (agent count): `32, 64, 128`
- `F` (changed cells per event group): `1, 9, 25, 81`
- core factorial: `3 × 3 × 4 = 36` cells
- core repeats: 3 independent superblocks per cell = 108 superblocks
- high-corner stress repeats: 18 additional superblocks at `G=128, N=128, F=81`
- total qualification superblocks: 126
- paired algorithm lanes: `126 × 6 = 756`
- total strict-serial fresh processes: `1 instrument + 126 oracle + 12 empty-boundary + 756 lanes = 895`

The maximum G and N are both reduced to 128, and maximum F is reduced to 81. The four F levels preserve a low-to-high discrimination gradient without reintroducing the attempt-009 extreme tail.

## 3. Balance and fairness preserved

The generated 126-row schedule passed all static checks:

- ordinals are exactly `0..125`;
- every row binds a unique input file and SHA-256;
- every superblock contains all six algorithms exactly once;
- each algorithm appears 126 times overall;
- each algorithm occupies each of the six lane positions 21 times;
- each ordered predecessor pair appears 21 times;
- replacement is null in all 126 rows.

Existing algorithm implementations were not renamed or modified. Reused contracts and helpers are explicitly copied or rebound under v4 names where version ownership is required, while stable external contracts remain hash-bound as declared dependencies.

## 4. Simplifications applied

1. Acquisition and acceptance are separated. The acquisition supervisor writes and freezes raw data and structural receipts only; expensive delivery acceptance runs later, read-only, against the sealed acquisition.
2. The independent acceptance hashes each unique source file once, streams JSONL tables, retains only essential join and uniqueness state, and does not keep every raw row in memory.
3. Redundant CSV/gzip/duplicate-JSONL views are non-gating. Canonical raw JSONL plus typed Parquet full round-trip remain gating.
4. Raw source rows remain fully preserved; the optimization removes repeated verification work, not evidence.
5. Acquisition uses one fresh Unity process at a time, no parallelism, no retry/resume/top-up/merge/skip/reorder/replacement.
6. A 10-minute hard lane timeout prevents an individual tail lane from extending indefinitely. Crossing the limit fails the one-shot attempt closed; it does not silently replace the lane.
7. Resource ceilings are frozen prospectively: 16 GiB process memory, 32 GiB qualification storage, single concurrency, and zero replacement.
8. Input/schedule generation, runtime identity, source identity, and acceptance tools are independently hash-bound.

## 5. Acceptance feasibility reused and optimized

The streaming essential acceptance core was exercised once against the sealed attempt-009 data without changing the source roots:

- source raw rows: 7,126,405;
- source size: approximately 7.24 GB;
- necessary validation: 106.432 seconds, about 86.5 MiB peak memory;
- streaming delivery/typed-Parquet feasibility: 364.519 seconds, about 335.2 MiB peak memory;
- combined observed wall time: approximately 470.951 seconds (7 minutes 51 seconds);
- typed-Parquet build and full value/type/order round-trip: PASS;
- source roots unchanged: PASS.

The reusable v4.1 acceptance keeps this streaming/hash-deduplication architecture but changes its expected counts to the new 126-superblock/895-process design. It cannot be data-run before a future v4 acquisition exists; its syntax, contracts, hashes, and cardinality logic passed this readiness audit.

## 6. Compile/readiness history

- attempt-001: compilation imported v4 with zero compiler errors, then Unity hit a known Burst shutdown crash; failure evidence preserved.
- attempt-002: Burst guard completed, but the source-triggered exit did not occur before its readiness deadline; failure evidence preserved and the exactly identified failed readiness process was terminated only after fail-closed recording.
- attempt-003: fresh cache-state compile/readiness exited naturally with code 0; no compiler errors; PASS.
- attempt-004 (this audit): 28 implementation artifacts, 21 contract bindings, 18 JSON documents, two PowerShell entry points, the Python AST, all 126 schedule/input bindings, G×N×F balance, planned cardinalities, B state, compile receipt, and attempt-009 seal all passed.

## 7. Runtime estimate and limits of inference

The engineering estimate for the 895-process qualification is approximately 9.49 hours at the point estimate, 10.70 hours conservatively, and 12.84 hours with an additional 20% reserve. This is not a guarantee: the new G=96 level and bounded tail have not yet been measured in a terminally passing v4 run.

For the later formal design, provisional `B=36` over 36 cells implies 1,296 formal superblocks and 7,776 paired algorithm processes before any separately contracted control processes. That is only a parameterized planning example, not a frozen sample size or authorization.

## 8. Evidence boundary

- attempt-009 remains sealed and unchanged;
- no new measured or delivery root was created;
- no v4 qualification process or algorithm lane was launched;
- no algorithm observation, effect, direction, ranking, weight, or winner was read or computed;
- formal collection and formal analysis remain unauthorized;
- the migration package remains `DORMANT_SEALED_FOR_LATER_REACTIVATION`.

A future execution requires a new, explicit, v4-bound one-shot authorization and fresh evidence/measured/delivery roots. Static readiness PASS is not qualification PASS.
