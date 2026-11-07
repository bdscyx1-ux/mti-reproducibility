# Gate13R-AX2 sample-count terminology clarification v1

Gate13R-AX2 is **not** a label-blinded experiment. The block schedule and output files intentionally retain the real algorithm identifiers `BiA*-R`, `LPA*`, `C-FF`, and `IDFF`, because the frozen P1 analysis directly reports each algorithm's raw geometric mean and four named contrasts.

The machine-readable legacy fields `anonymousSampleCount`, `acceptedAnonymousSamples`, and `plannedAnonymousSamples` in execution-contract/readiness/control receipts mean only “algorithm-run sample count.” They do not assert anonymization, label blinding, or concealment of algorithm identity. For this design:

- 1 complete block contains 4 named algorithm-run samples;
- 1,536 complete blocks contain 6,144 named algorithm-run samples;
- acquisition monitoring remains result-blind because it may display only structural counts and may not read or interpret P1, despite the stored algorithm IDs being named.

This clarification changes no schedule, executable, endpoint, analysis, sample size, or authorization boundary. It only removes ambiguity in a legacy counter name.

