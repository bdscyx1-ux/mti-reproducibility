# Gate 11 Frozen Count Erratum

Status: frozen arithmetic correction discovered during create-new generation  
Date: 2026-10-05 (Asia/Shanghai)  
Applies to: `formal-scenario-matrix-v1`  
Scope: count reconciliation only; no scenario factor, seed, generator rule, eligibility rule, analysis row, or retained bundle byte is changed

## Discovery

The create-new Gate 11 generation completed with exactly 53 scenario files and 212 unique algorithm×scenario eligibility entries. The outer generation wrapper then rejected its own summary because the frozen specification and test design contain an internally inconsistent shared/heterogeneous subtotal.

The enumerated matrix is:

| Component | Shared | Heterogeneous | Total |
|---|---:|---:|---:|
| Balanced core | 16 | 16 | 32 |
| Grid scale | 4 | 0 | 4 |
| Agent scale | 5 | 0 | 5 |
| Dynamic footprint | 5 | 0 | 5 |
| Goal count | 0 | 5 | 5 |
| Reachability | 2 | 0 | 2 |
| **Total files** | **32** | **21** | **53** |

The resulting eligibility expansion is:

- shared: `32 × 4 = 128`;
- heterogeneous per-agent: `21 × 2 = 42`;
- heterogeneous grouped-field: `21 × 2 = 42`;
- total: `128 + 42 + 42 = 212`.

The frozen summary line `33 × 4`, `20 × 2`, `20 × 2` also sums to 212, but it cannot be reconciled with the frozen family enumeration, the five heterogeneous goal-count levels, or Gate 10 cohort classification.

## Resolution

The detailed family matrix, factor levels, goal structures, seeds, and Gate 10 classifier are authoritative. Automated Gate 11 subtotal checks therefore use `32 shared / 21 heterogeneous` and `128 / 42 / 42` eligibility cells while retaining the originally frozen specification and test-design files byte-for-byte.

This correction does not authorize:

- changing any retained scenario/config byte;
- changing the total of 53 scenarios or 212 eligibility entries;
- reclassifying any heterogeneous scenario as shared;
- running a Gate 12 pilot or Gate 13 formal campaign.

The initially failed wrapper summary is retained as the discovery record. Subsequent retained-bundle verification and the Gate 11 final audit must cite this erratum and verify that the bundle manifest hash did not change.
