# Reproduce the supplemental results

The portable entry point reruns the complete corrected D* Lite supplemental A and B analyses from archived measurements. It validates raw identities, executes the statistical calculations and compares every scientific summary field and four CSV tables with the retained results. The historical analysis source files remain unchanged.

## Requirements

Use Python 3.12 and install NumPy with:

```powershell
python -m pip install -r requirements-reproduction.txt
```

The tested environment is Python 3.12.14 with NumPy 2.3.5 on Windows. This is an offline analysis workflow after dependencies and data are present; Unity is not required.

## Required data

Keep these files together in a data directory. The default is the sibling data-archives directory:

- archives.json
- supplement-A.files.csv
- supplement-B.files.csv
- supplement-plans.files.csv
- supplement-A.part001.zip
- supplement-A.part002.zip
- supplement-B.part001.zip
- supplement-plans.part001.zip

The other historical archives are not required for this entry point. The archive and file checksums are verified before use. Data files and their recorded path strings are preserved; the adapter resolves study-relative paths in the selected working directory. It never falls back to the original drive.

## Run

From the repository root, select a new output directory outside the repository:

```powershell
python reproduce.py --archives "../data-archives" --output "../reproduction-001"
```

Only the required 6,144 raw records, receipts and plans are extracted. A uses 1,536 four-algorithm blocks. B uses 768 four-algorithm blocks, split equally between movement and callback measurements. The original B analysis engine and its ten synthetic checks are reused after source identity verification.

Success is reported in REPRODUCTION_RESULT.json with status PASS. Results are written under results/A and results/B; inputs and logs are retained beside them. A pre-existing output directory is refused. The recorded input and source evidence is not overwritten.

The comparison excludes creation timestamps, newly observed runtime version fields and the adapted B analyzer's own source hash. All scientific summary fields and numerical table values are compared. Numerical comparison uses relative tolerance 1e-9 and no absolute tolerance. The completed local validation reproduced 51,486 numerical values and 6,193 CSV rows with maximum absolute difference zero.

## Unity core check

```powershell
python tools/run_unity_check.py --unity "<path to Unity.exe>" --output "../unity-check-001"
```

See unity-minimal/README.md. This compiles the frozen algorithm core and runs 120 functional checks in a new project copy. It does not recollect the full manuscript benchmark.

## Scope

This entry point covers the complete supplemental A/B analyses and a minimal Unity core check. The additional historical entry point and all five figure generators are documented in HISTORICAL_QUICKSTART.md. Five historical studies are recoverable; AX2 is aggregate-only because its block outcomes were deleted. Licenses, hosting and public URLs remain separate release work.
