# Reproducing archived results

The supplemental route is described in ../QUICKSTART.md. It reruns the complete supplemental A/B analyses, including the original B eligibility, pairwise contrasts and winner decision. The five recoverable historical studies and manuscript figure/table generators are described in ../HISTORICAL_QUICKSTART.md. AX2 raw outcomes are unavailable; retained summaries are explicitly distinguished from raw-data reproduction. Original sources and new adapters remain separate.

## Integrity first

`tools/verify_package.py` verifies repository files against MANIFEST_SHA256.csv and ZIP files against data-archives/archives.json. It also checks archive entry names and uncompressed sizes against the per-group CSV indexes. Pass `--deep` to read all archived payloads and check every original SHA-256; this reads tens of GiB and takes longer.

`tools/check_supplement.py` reads selected raw records directly from the ZIP files and independently reproduces supplemental A geometric means, five paired contrasts and Holm adjusted p-values, plus supplemental B movement condition means and completion checks. It does not rerun the full original B decision engine or every historical analysis.

## Data groups

The new entry points extract the needed records automatically into a fresh output directory. Do not merge historical and corrected D* Lite results into one acquisition. Archive file indexes record every retained file hash; archives preserve the original bytes, including provenance paths.

For SMSB statistical analysis use `smsb-accepted-tables` first. The much larger `historical-smsb` archives preserve the original acquisition records. Other groups retain raw records, receipts and in-tree control files to preserve traceability.

Historical attempts and diagnostic records may coexist within a retained acquisition root. Follow its accepted-data manifests and contracts when selecting analysis inputs; never treat every JSON file as an independent observation. Pilot data from the separate supplemental pilot directories were not selected for the formal data archives.

## Portability work

Original analysis and execution sources are byte-preserved. The supplemental analyzers have adapted copies, separate input/output arguments and checked study-relative path resolution. The historical wrapper reuses the frozen numerical routines with verified input hashes and new output paths. Machine-specific collection launchers remain evidence of the original invocation; they are not the portable offline interface.

The broad project/ snapshot omits original scene, prefab, texture, font and plugin binaries. A separate unity-minimal/ project has now been compiled and tested with Unity 2022.3.30f1c1: it contains the six frozen backends and a functional checker. This validates algorithm-core portability, not the historical Player or full timed acquisition workflow. Frozen implementation identities remain preserved.

Final manuscript figure labels differ from some historical plotting outputs. `make_figures.py` explicitly implements Figure 1, Figure 2, Figure 3, Figure S1 and Figure S2 using their captions and verified numerical sources. `make_tables.py` exports the numerical tables and preserves design prose separately. The AX2 exceptions are recorded in the per-table provenance file.
