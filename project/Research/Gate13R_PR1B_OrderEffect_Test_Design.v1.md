# Gate 13R-PR1B Order-Effect Test Design v1

Status: `FROZEN-BEFORE-PILOT / VALIDATION-FIRST`

## Static and schema tests

1. All PowerShell entry points parse under Windows PowerShell 5.1 and pass explicit absolute `ProjectPath` binding smoke tests.
2. The Python analyzer compiles and its synthetic self-test passes without reading real pilot data.
3. Every frozen upstream path exists and matches its preregistered SHA-256.
4. The Gate 11R matrix resolves exactly six campaign rows: two cohorts for each of three frozen scenarios.
5. Each scenario pair has identical scenario bytes/fingerprint across cohorts and the correct two-algorithm Williams rows.
6. The generated measured schedule has exactly 96 mirrored pairs, 192 superblocks, 384 processes, and 768 samples.
7. AB/BA totals are 96/96; per scenario they are 32/32; AB-first/BA-first mirrored-pair totals are 16/16 per scenario.
8. Scenario wave positions rotate; each four-process mirrored pair is contiguous; the two halves use the same block ordinal.
9. Every generated campaign/run identity is unique and safe.
10. No path targets Gate 12R v4 or any formal root.

## Synthetic statistical tests

The analyzer self-test uses fixed fixtures with manually calculable ratios to verify:

- C1-C4 numerator/denominator direction;
- `D = logRatio_AB - logRatio_BA` sign;
- exact zero-order-effect classification;
- bounded, material, detectable-below-bound, and inconclusive classifications;
- whole-mirrored-pair bootstrap and deterministic seed behavior;
- equal-scenario pooled weighting;
- zero-event P5 handling without pseudocounts;
- rejection of missing, non-positive, non-finite, duplicate, partial, or mismatched inputs;
- fixed H32/H40/H48 recommendation logic.

## Unity verification gates

After static tests pass and before the pilot root exists:

1. Compile the unchanged Gate 12R V3 Unity batch command in a fresh verification root.
2. Run one fresh PSAPI/CIM telemetry probe and require positive, cross-validated working-set/private-memory values.
3. Run one complete four-process mirrored positive fixture on a frozen heterogeneous anchor and verify all block/sample hashes, structural outputs, resets, telemetry, and process uniqueness.
4. Run one intentional negative fail-closed block and require the expected failure receipt, partial evidence, and absence of subsequent sample execution.
5. Recheck that the frozen upstream hashes are unchanged and that the supplemental pilot root and reserved formal root remain absent.

## Pilot launch gate

Only a validation-only audit with every test passed may authorize creation of the new supplemental pilot root. It must bind the exact plan, provenance, telemetry result, runners, analyzer, and upstream hashes.

## Post-pilot audit

Require exact cardinalities, zero partial pairs, unique process/run identities, complete hashes, deterministic re-analysis, pre/post frozen-input hash equality, absence of formal artifacts, and a mechanically derived recommendation. Any failure preserves evidence and terminates without retry or resume.
