# Reproduce additional SMSB diagnostics

Read PROTOCOL.md and RESULTS.md. Source snapshots are under source/; no access to the original H drive is needed for analysis or validation. prepare.py documents original provenance and is not required after extraction.

Use Python 3.12 with NumPy and pandas (delivered versions are pinned in requirements.txt):

```powershell
python analyze.py
python validate.py
python write_report.py
```

analyze.py writes analysis/. validate.py explicitly reruns the deterministic analysis with a 600-second timeout, checks exact output reproduction, and independently reconstructs the cluster-sandwich standard errors. Keep a copy of delivered outputs before reproducing if preserving the original timestamp is important. It does not run Unity or alter original archived files. Source hashes and protocol freeze are checked before analysis.

Main files: residuals_by_algorithm.csv; residuals_by_algorithm_cell.csv; cluster_robust_reference_contrasts.json; paired_block_bootstrap.json; paired_cell_ratios.csv; weight_scenarios.csv; simplex_weight_scan.csv; effect_size_idff_cff.csv; summary.json; validation_receipt.json. Full lane-level residuals are included for reproducible diagnostics.

This is an additional post hoc diagnostic of the retained workload data, not replacement preregistration or a new confirmatory acquisition. Original score bounds remain original-model quantities. The source metadata retain local provenance paths; analysis uses relative paths within this folder.
