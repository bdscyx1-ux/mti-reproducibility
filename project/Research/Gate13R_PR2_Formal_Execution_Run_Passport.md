# Gate 13R-PR2 S48/H48 formal execution — Run Passport

## Material Passport

- Work unit: `gate13r-pr2-rq-aligned-s48-h48-formal-execution-v1`.
- Authorization source: user authorization received 2026-10-09 (Asia/Shanghai), matching the complete text in `Research/Gate13R_PR2_Formal_Campaign_Next_Authorization_Prompt.md` (SHA-256 `0cdfa4dfe87ce5642be675a16653d9b8cb5cb29721bdda742a3cfd97ae566661`).
- Additional frozen rule: raw-data acquisition and later analysis are separate commits under `gate13r-pr2-raw-analysis-two-phase-commit-v1`.
- Gate 13R formal campaign authorized: **one controlled attempt**.
- Gate 14R authorized: **No**.
- Automatic formal retry, resume, top-up, or partial-attempt merge authorized: **No**.

## Frozen acquisition design

- Active readiness checkpoint SHA-256: `669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc`.
- Active config SHA-256: `87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e`.
- Active schedule SHA-256: `df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae`.
- Strict serial topology; maximum one Unity Editor process.
- 3,552 fresh Unity block processes and 10,176 algorithm samples.
- Exact formal root: `H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v1`.

## Stage boundary

The current authorization includes raw acquisition and raw-data commit only. It does not authorize formal statistical analysis. A successful run stops at `RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE`. An analysis implementation failure in a later authorization can never, by itself, invalidate or rerun the Unity acquisition.

## Stop conditions

- During measured acquisition: any hard gate fails closed before the next process ordinal.
- After all Unity blocks: an auditor implementation failure freezes the collected payload and permits only a versioned read-only raw-commit audit recovery; it does not authorize Unity rerun.
- A proven raw-contract violation requires a separate user decision.
