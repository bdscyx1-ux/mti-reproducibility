# Gate 13R-PR1B v4 Composite Process Identity Test Design

Status: `FROZEN-BEFORE-REAL-PILOT-NUMERIC-ANALYSIS / VALIDATION-ONLY`

## Synthetic identity tests

| Test | Expected result |
|---|---|
| Same PID reused after prior half-open lifetime ends, with different UTC start times and block IDs | pass |
| Same PID reused while the prior lifetime is still open | `PID-LIFETIME-OVERLAP` |
| Duplicate `(PID,startTime)` | `DUPLICATE-OS-PROCESS-IDENTITY` and/or the more specific mapping violation |
| Duplicate `(PID,startTime,blockId)` | `DUPLICATE-BLOCK-EVIDENCE-IDENTITY` |
| One OS identity mapped to multiple block IDs | `PROCESS-IDENTITY-MULTIPLE-BLOCKS` |
| One block ID mapped to multiple OS identities | `BLOCK-MULTIPLE-PROCESS-IDENTITIES` |
| Missing start time | `PROCESS-START-MISSING` |
| Non-UTC start time | `PROCESS-START-NON-UTC` |
| Malformed start time | `PROCESS-START-MALFORMED` |
| Start after frozen execution completion | `PROCESS-START-FUTURE` |
| Start after block/wrapper completion | `PROCESS-TIME-ORDER-IMPOSSIBLE` |
| Sample or sample-summary PID differs from block PID | `SAMPLE-BLOCK-PID-MISMATCH` |
| Duplicate run ID | `DUPLICATE-RUN-ID` |
| Duplicate schedule key | `DUPLICATE-SCHEDULE-KEY` |

## Statistical invariance tests

- frozen V1 self-tests pass;
- frozen V4 self-tests pass;
- contrast directions and AB-minus-BA sign are unchanged;
- order-effect classification at `+-log(1.10)` is unchanged;
- bootstrap run twice with exactly 20,000 replicates and seed `13012026` is byte-identical;
- no-alert sensitivity remains secondary and cannot replace the all-eligible primary set;
- P5 zero events remain zero and receive no pseudocount.

## Real structural validation-only audit

The audit may read manifests, summaries, memory evaluations, and file hashes, but it must not calculate P1-P5/C1-C5 results. It must verify:

- 396/396 OS identities and 396/396 block evidence identities unique;
- 768/768 measured run IDs and 792/792 total run IDs unique;
- legal non-overlapping numeric-PID reuse;
- all execution/block/sample/wrapper PIDs agree;
- all block, sample manifest, summary, workload-result, and memory-evaluation hashes agree;
- all 396 blocks and 792 samples complete;
- memory hard gates, reset, logger disposal, fresh sample state, canonical scenario, Williams order, and exclusion flags pass;
- 12 warm-up blocks, 384 measured blocks, 96 measured mirrored pairs, and 192 measured matched superblocks;
- plan/provenance/execution bindings and all provenance-bound files match;
- source tree remains `4125d99e4953dc78fd254b93343ea65f952623e98b0d3c26355770896a442bed`;
- no write occurs beneath v7;
- no Unity process is active or invoked;
- the formal root is absent;
- the recovery root is absent before the one-shot recovery.

## Recovery acceptance tests

- recovery output conforms to the frozen schema and required labels;
- source tree identity before and after is identical;
- recovery root contains no Unity output or sample directory;
- analysis reports 3 scenarios, 32 pairs per scenario, 96 total pairs, 192 superblocks, 384 measured composite process identities, and 768 measured run IDs;
- bootstrap metadata is exactly 20,000/13012026/whole mirrored pair/equal scenario;
- manifest hashes every non-self output;
- success checkpoint does not authorize Gate 13R or Gate 14R;
- failed recovery cannot be resumed or retried automatically.
