# Historical analysis and manuscript displays

Five recoverable historical studies can be recomputed from archived measurements.
The expanded Gate13R-AX2 acquisition is an explicit exception: its block outcomes
were deleted during earlier cleanup and no backup is currently known. Its retained
aggregates are not described as raw-data replication.

Use Python 3.12 and a fresh output directory outside the repository. From the
repository directory:

```powershell
python -m pip install -r requirements-figures.txt
python reproduce_historical.py --archives ../data-archives --output ../historical-001
python reproduce.py --archives ../data-archives --output ../supplement-001
python make_figures.py --results ../historical-001/results --output ../figures-001
python make_tables.py --results ../historical-001/results --supplement-results ../supplement-001/results --output ../tables-001
```

The historical entry point verifies ZIP checksums, extracts about 0.87 GB of selected
outcomes/control records and the complete accepted SMSB table package, checks frozen
scientific input bindings, and invokes the original numerical routines. It also
streams 3,072 original operation logs to regenerate the non-AX2 rows of Table S3.
Allow several minutes and at least 3 GB free working space in addition to the archives.
Keep all ZIP parts and corresponding `*.files.csv` indexes for these groups:

- `historical-four-method`
- `historical-confirmation`
- `historical-movement`
- `historical-mq`
- `smsb-accepted-tables`

Keep `archives.json` with the archives. Supplemental A/B use the four ZIPs documented
in QUICKSTART.md. `historical-expanded` contains surviving controls only, and is not
used as a substitute for the missing AX2 observations. `historical-smsb` retains the
acquisition source; this offline workflow uses the accepted typed tables instead.

On success, `historical-001/REPRODUCTION_RESULT.json` reports
`PASS_FOR_FIVE_RECOVERABLE_STUDIES`. The six-algorithm SMSB model, MQ bootstrap,
movement preference analysis, SMSB ranking and reporting tables are included.
Every retained scientific output field is compared where an archived counterpart
exists. Floating-point comparisons use relative tolerance 1e-9 and absolute tolerance
1e-12; decisions and text fields must match exactly. Creation metadata is excluded
explicitly. No new experimental measurements are collected.

`figures-001` contains Figure 1–3 and Figure S1–S2 in PDF, SVG and 300 dpi PNG, plus
CSV source data, captions and rendered panel-alignment reports. The statistical
geometry follows the manuscript; typography and tick placement are regenerated.
The original embedded figures remain separately available for comparison.

`tables-001/tables.html` is a readable overview. `csv/` contains 33 table files
(including separate S7a–e) and three algorithm boxes. Twenty-five tables are generated
from recomputed results, including four mixed-source tables. In Table 3 and Tables
S1–S3, AX2 rows remain explicitly marked as retained summaries. Eight design,
definition or interpretation tables and the three algorithm boxes preserve source
manuscript text. `original-transcription/` preserves the supplied DOCX table content
separately; `TABLE_PROVENANCE.json` records the source of every display.

The historical executors are retained unchanged in `project/Research`. New adapters
live in `portable/historical`; the P1-C5 adaptation includes an exact diff, and the
four-method/SMSB output blocks are copied verbatim from the frozen scientific code.
Collection-machine authorization and output-location checks are historical evidence,
not a requirement to write back to the original machine. New orchestration supplies
fresh paths and does not claim to rerun the original full acquisition certification.
Excluded bulk scenario copies and unused telemetry remain archived and are not
claimed to have been fully replayed. Python audit hooks deny access to the original
acquisition directories.

The minimal Unity project still provides the previously validated 120 algorithm-core
checks. Offline statistical reproduction does not reconstruct the unavailable
historical movement executable or recollect the timed benchmark.
