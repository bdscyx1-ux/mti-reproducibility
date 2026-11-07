# Shared Flow Fields for Dynamic Navigation in Interactive Strategy Environments

This repository collects research source, experimental inputs, archived analyses and provenance for the MTI manuscript dated 6 November 2026. It includes portable entry points for five recoverable historical studies, the complete supplemental A/B analyses, all five manuscript figures, and editable tables. A minimal Unity project provides functional checks of all six frozen algorithm backends. Large measurement records are organized as separate ZIP archives in the sibling `data-archives` directory. The versioned data distribution is described under Download below.

**Data limitation:** Gate13R-AX2 block outcomes were removed by earlier cleanup and no backup is currently known. Its archived aggregate results remain available, but raw-data reproduction is unavailable. AX2 rows in Table 3 and Tables S1–S3 are explicitly labelled in the table exports. See [docs/DATA_LIMITATIONS.md](docs/DATA_LIMITATIONS.md).

Start with [QUICKSTART.md](QUICKSTART.md). Run `python reproduce.py --archives ../data-archives --output ../reproduction-001` from this directory to reproduce the supplemental results. The output directory must be new. This entry point uses four small supplemental ZIPs, not all historical data archives.

For historical results and manuscript displays, follow [HISTORICAL_QUICKSTART.md](HISTORICAL_QUICKSTART.md): run `reproduce_historical.py`, then `make_figures.py` and `make_tables.py`. Generated manuscript displays and their provenance are retained under `release-displays/`.

## Contents

- `project/Assets/_Scripts`: current source snapshot, including research and legacy support scripts. Current source is not automatically identical to every historical frozen implementation.
- `project/Research/Analysis`: archived outputs for the historical acquisitions. Preserve acquisition and attempt identifiers when interpreting results.
- `project/Research/FormalInputs`, `FormalScenarios`, `Scenarios`: input and scenario definitions.
- `project/Research/Gate13R-AX2`, `Gate14Re`, `Gate14Re-ME`, `Gate14Re-MQ-CFF-IDFF`: designs, analysis code and supporting implementation records.
- `project/Research/Verification`: selected text-based verification records and archived code. These records describe earlier checks; their presence does not mean those checks were rerun during packaging.
- `supplement-20261103`: corrected D* Lite supplemental planning and movement analyses, frozen source evidence and completion records. Raw records, plans and inputs are in separate archives.
- `figure-support/smsb-audit`: additional SMSB diagnostics. These are post hoc diagnostics, not replacement confirmatory results or a verified export of every final manuscript figure.
- `figure-support/manuscript-embedded`: the five figures extracted from the supplied manuscript and supplementary DOCX files, with paragraph-order caption associations. These are delivered images, not editable plotting sources.
- `provenance/manuscript-audit`: retained audit records.
- `provenance/historical-dstar-diagnostic`: recovered historical D* Lite source and diagnostic evidence. The historical source hash matches the recorded implementation identity; it does not recover the historical executable.
- `docs/STUDY_MAP.csv`: manuscript-to-acquisition map and analysis entry points.
- `tools`: package verification and independent checks of selected supplemental results.
- `portable`: adapted full supplemental analyzers, exact patches and original/adapted source hashes.
- `unity-minimal`: seven byte-preserved research source files and an independent 120-case functional checker; see its README.

## Start with existing measurements

1. Read `docs/STUDY_MAP.csv` and `docs/REPRODUCTION.md`.
2. Run `python tools/verify_package.py --archives ../data-archives` to verify repository hashes and archive identities.
3. Follow QUICKSTART.md to rerun the full supplemental analyses. The earlier `tools/check_supplement.py` remains available as a smaller independent numerical cross-check.
4. For historical analysis, use `reproduce_historical.py` with a fresh external output directory. It extracts the scientific inputs it needs; manual extraction into the repository is unnecessary. ZIP parts are independent archives, not volumes of one split ZIP.
5. Original acquisition-specific launchers remain historical evidence. Use the new offline entry point for reproducible result calculations and preserve the acquisition boundaries described in HISTORICAL_QUICKSTART.md.

The lightweight tools use Python standard-library modules. Historical environments are recorded separately in `docs/ENVIRONMENT.md`; installing a current interpreter does not reconstruct an unrecorded historical environment.

## Download

Repository: https://github.com/bdscyx1-ux/mti-reproducibility

Version: **v1.0.0**. Data and convenience ZIPs are distributed through [the versioned GitHub Release](https://github.com/bdscyx1-ux/mti-reproducibility/releases/tag/v1.0.0). A completed release contains all 67 data ZIPs, their `*.files.csv` indexes, `archives.json` and the release checksum file. If the release is still a draft or assets are incomplete, do not treat the data publication as complete.

Place the data ZIPs and indexes together in `../data-archives` relative to this repository. The ZIP parts are independent archives. The complete raw archive set is about 3.36 GiB compressed; see QUICKSTART.md for the smaller supplemental route and HISTORICAL_QUICKSTART.md for required historical groups. A Git clone contains code, supporting records and figures, but does not download Release assets.

Use [docs/DOWNLOADS.md](docs/DOWNLOADS.md) for a complete inventory and download instructions. This GitHub release has no archival DOI. Preserve the version/tag and checksums when citing or reusing the materials.

## Licenses and citation

Author-owned code is MIT-licensed. Author-owned data and figures use CC BY 4.0. Read [LICENSING.md](LICENSING.md) for exact scope, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for exclusions and dependency notices, and CITATION.cff for citation metadata.

## Scope and provenance

Historical execution records retain recorded machine paths and hardware/runtime metadata so that acquisition provenance and file bindings remain interpretable. These paths are historical records, not prerequisites or download locations. Use the portable entry points above. Machine-bound encrypted label-custody payloads and three local-toolkit QA scripts are excluded from the public copy; original local evidence is preserved. See docs/PUBLICATION_EXCLUSIONS.json.

The original snapshot preservation report describes the earlier local v3 candidate. The publication derivation is separately recorded in validation/publication-file-changes.json. English filenames and their original names are mapped in docs/FILENAME_MAP.csv; historical source code may still emit a Chinese-named result note when run. Scientific source bytes and raw ZIP payloads are otherwise preserved as documented.

No Unity Editor, Unity installation, commercial asset pack, thesis PDF or manuscript DOCX is bundled. The broad project/ snapshot omits scene and asset payloads from the original project. Use unity-minimal/ for the validated algorithm-core functional check; it does not reproduce the complete game or all historical collection pipelines. The historical standalone movement executable was previously reported unavailable; a newer build is not a substitute for it.
