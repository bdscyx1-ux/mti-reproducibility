# Gate 13R-PR2 Attempt 2 Embedded Contract Repair Specification v2

Status: `ACTIVE / SUPERSEDES-V1-TARGET-VERSION-NAMES-ONLY / FORMAL-ROOT-NOT-CREATED`

This document preserves every scientific and contract clause in
`Gate13R_PR2_Attempt2_Embedded_Contract_Repair_Specification.v1.md`. The V1
create-new derivation stopped on an internal occurrence-count assertion after
creating partial V3/V4/V5 targets. Those files and their failure evidence are
read-only and excluded from the active stack. They are not overwritten.

The only V2 amendment is version identity:

- active C# producer: `Gate13RPR2FormalBatchCommandV4.cs`, class
  `DDM.Research.Editor.Gate13RPR2FormalBatchCommandV4`;
- active execution module: `Gate13RPR2FormalExecutionV5.psm1`;
- active block wrapper: `Run-Gate13RPR2FormalBlockV6.ps1`;
- active campaign orchestrator: `Run-Gate13RPR2FormalCampaignV6.ps1`;
- active derivation script: `New-Gate13RPR2Attempt2VersionedStackV2.py`.

The C# delta from frozen V2 remains exactly: class identity, the required
Boolean `BlockChildRecord.formalCampaign` declaration, and its explicit
`formalCampaign = plan.formalCampaign` assignment. All validation-only,
formal-root, one-shot, two-phase-commit, preservation, and authorization
boundaries from V1 remain unchanged.

