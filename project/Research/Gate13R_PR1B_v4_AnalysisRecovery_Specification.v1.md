# Gate 13R-PR1B v4 Read-Only Analysis Recovery Specification

Status: `FROZEN-BEFORE-REAL-PILOT-NUMERIC-ANALYSIS / NON-EXECUTING / ONE-RECOVERY-MAXIMUM`

## Preconditions

The single recovery may start only after all of the following have passed:

1. authorization, composite identity specification, recovery specification, test design, output schema, synthetic expected results, provenance, and pre-read preservation audit are frozen and hashed;
2. Python syntax/AST and schema parsing;
3. synthetic positive and negative identity tests;
4. deterministic 20,000-replicate bootstrap regeneration;
5. full structural audit of all 396 process records and 792 sample records without using workload metric values for analysis;
6. verification of every referenced evidence hash and all completion, reset, memory, scenario, Williams, schedule, and provenance gates;
7. frozen v7 tree SHA-256 equality before validation and immediately before recovery;
8. no active Unity process, no `Temp/UnityLockfile`, and absence of the reserved formal root;
9. proof that the independent recovery root does not already exist.

## Analyzer derivation

The v4 recovery analyzer loads the frozen V1 and V4 analyzers without modifying their bytes. It substitutes only the V1 process uniqueness adapter at runtime:

- the frozen per-block evidence loader continues to verify sample hashes, completion, reset, scenario, algorithm, and metric semantics;
- its local numeric-PID uniqueness set is scoped to one block;
- the enclosing global uniqueness set receives the validated block evidence identity key instead of the numeric PID;
- all downstream V1/V4 estimand, bootstrap, classification, P5, and memory-sensitivity functions remain unchanged.

The recovery layer adds a process-identity audit and execution diagnostics but does not remove or reinterpret frozen results.

## One-shot execution

- The recovery output root must not exist before execution.
- Exactly one `--recover` invocation is permitted.
- The analyzer rechecks the frozen source tree before reading workload metrics.
- It builds the frozen V4 analysis in memory and writes only to the independent recovery root.
- All files are written by same-directory temporary file plus atomic replace.
- The frozen source tree is rehashed after output commit; any difference fails the recovery.
- A recovery failure creates an independent failure receipt, partial manifest, log, hash manifest, and failed checkpoint, then stops. Automatic recovery retry is prohibited.

## Required success outputs

- `recovered-order-effect-analysis.json`;
- `analysis-recovery-manifest.json`;
- `analysis-recovery-receipt.json`;
- `analysis-recovery-checkpoint.json`;
- `source-preservation-after.json`;
- `evidence-manifest.json`;
- `analysis-recovery.log`.

The analysis must report scenario and equal-scenario pooled AB-minus-BA estimates, 95% intervals, 20,000 whole-pair bootstrap intervals, alert/no-alert sensitivity, position/predecessor/process-age/wave diagnostics, and a pilot-level order-effect identifiability verdict. It must not create or alter any formal config, schedule, root, receipt, or sample.
