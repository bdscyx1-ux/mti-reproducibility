# Manuscript experiment directory names

The current branch replaces internal acquisition codes in the study folder names with the experiment names used in the manuscript and its Supplementary Materials. The numerical data, frozen scientific source, acquisition identifiers, and recorded hash bindings are preserved.

| Earlier directory name | Current directory name | Manuscript naming source |
| --- | --- | --- |
| `Gate13R_PR2_Attempt4_PhaseB` | `Four-Method-Dynamic-Update-Benchmark` | Supplementary S1.3 and S2.2; main Section 3.3 four-method study |
| `Gate13R-AX2` | `Expanded-Search-Strategy-Benchmark` | Supplementary S1.2 and S2.3; main Sections 3.3 and 4.1 expanded study |
| `Gate13R_P1C5_Independent` | `Independent-Flow-Field-Confirmation` | Supplementary S1.3 and S2.4; main Sections 3.3 and 4.1 field confirmation |
| `Gate14Re` | `Movement-and-Scaling-Benchmark` | Supplementary S1.3 and S3.1; main Sections 3.3 and 4.3 historical movement |
| `Gate14Re-ME` / source folder `Gate14ReME` | `Supplementary-Movement-and-Scaling-Benchmark` | Main Section 3.3 explicitly defines SMSB as Supplementary Movement and Scaling Benchmark; matched six-algorithm cost and scaling experiment |
| `Gate14Re-MQ-CFF-IDFF` | `Managed-Multi-Query-Module` | Main Section 3.3 defines the managed multi-query module (MQ); Section 4.4 reports its results |
| `supplement-20261103` | `Supplemental-Acquisition-with-Corrected-DStar-Lite` | Supplementary S9 heading; main Sections 3.3, 4.1 and 4.3 |
| Supplemental `analysis/A` | `analysis/Shared-Goal-Planning` | Supplementary S9.2 Shared-goal planning results |
| Supplemental `analysis/B` | `analysis/Main-Movement` | Supplementary S9.3 Main movement results and historical boundary |
| `figure-support/smsb-audit` | `figure-support/Supplementary-Movement-and-Scaling-Benchmark-Audit` | Supporting diagnostics for the SMSB experiment |

Hyphens replace spaces; `DStar` represents the `D*` notation because an asterisk is not a portable Windows filename character. Experiment folder names do not change method names or study identities.

## Compatibility with archived records

The complete old-to-new directory map is available in [EXPERIMENT_DIRECTORY_MAP.csv](EXPERIMENT_DIRECTORY_MAP.csv) and [DIRECTORY_RENAME_MAP.json](DIRECTORY_RENAME_MAP.json). `STUDY_MAP.csv` points to the current directories. Corresponding Unity folder metadata files are renamed with their folders, preserving their bytes and GUIDs.

The portable entry points resolve repository files through the map. Historical analysis reconstructs the original path layout in its fresh external working directory before checking frozen input bindings and loading the unchanged scientific routines. Recorded paths, JSON study IDs, source namespaces, historical filenames, and prior validation receipts remain evidence of the acquisition, so their internal codes are retained. Preparatory pilots, failed attempts, and technical test-fixture folders that are not separate experiments named in the manuscript retain their technical labels.

The published `v1.0.0` tag, Release assets, ZIP member names, and archive indexes remain fixed. Use the same Release downloads with the current entry points. This directory change does not create new observations or change any reported result. The Expanded Search-Strategy Benchmark still lacks original block outcomes; a readable directory name does not restore those data.

## Validation

`validation/experiment-directory-renaming.json` records the file-preservation and analysis checks for this layout. `MANIFEST_SHA256.csv` covers the current checkout. Earlier validation records retain their historical paths and original hashes; they describe the version in which they were produced.
