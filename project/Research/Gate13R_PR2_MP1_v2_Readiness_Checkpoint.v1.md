# Gate 13R-PR2-MP1 attempt 2 / v2 success checkpoint

Status:

`MP1-V2-PILOT-PASSED / RAW-DATA-COMPLETE / RAW-IMMUTABLE / DIAGNOSTIC-ANALYSIS-ATTEMPT1-PASSED / FORWARD-MEMORY-POLICY-RECOMMENDED-BUT-UNFROZEN / MP2-NONEXECUTING-AUTHORIZATION-REQUIRED / FORMAL-ATTEMPT3-NOT-AUTHORIZED / FORMAL-ANALYSIS-NOT-AUTHORIZED / GATE14R-NOT-AUTHORIZED`

## Completed work

- Pre-pilot validation attempt 6 passed all 34 ordered steps under PowerShell 7 and native Windows PowerShell 5.1.
- The sole authorized measured v2 acquisition completed 96/96 fresh Williams-block Unity processes and 384/384 algorithm samples without retry, resume, top-up, merge, skipped block, or reordered block.
- Phase A froze 3,360 raw files / 2,607,785,161 bytes with canonical tree SHA-256 `13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`.
- Phase B analysis attempt 1 rehashed every raw file, reproduced the same tree, and passed with 96 blocks / 1,824 stage records. The analysis root is independent and read-only.
- A post-pilot audit attempt incorrectly reused the pre-pilot “v2 root must be absent” condition; that failure is preserved. The versioned post-pilot audit then passed without rerunning Unity.
- Pilot v1 remains `a1f427…`; formal attempt 2 remains `aafd8018…`; both are fully read-only and unchanged.

## Diagnostic result

The pilot found no runaway-growth or host-safety emergency. Maximum cleanup native delta increased materially with grid scale: approximately 255.05 MiB (g032), 271.17 MiB (g064), 380.98 MiB (g128), and 556.36 MiB (g256). In g256, 1/48 blocks exceeded 512 MiB and 13/48 reached at least 90% of 512 MiB; none exceeded 640, 768, or 1,024 MiB. Maximum retained managed cleanup growth was 84,762,624 bytes, below the retained 128 MiB alert.

The recommended but not yet frozen policy is layered and scenario-aware:

- native advisory envelope: 512 MiB for max grid dimension <=128; 640 MiB for 256;
- native hard eligibility ceiling: 640 MiB for <=128; 768 MiB for 256;
- retained-managed alert/emergency: keep 128/256 MiB after forced cleanup;
- host emergency gates: keep 4 GiB absolute native, 2 GiB relative native growth, and 8 GiB minimum available physical memory;
- advisory crossings are retained but do not stop execution; hard crossings fail closed before the next block;
- any crossing is a whole-block/process eligibility event, not proof that the algorithm in the final position caused it.

This is pilot-informed diagnostic evidence only. It does not support C1-C5/P1-P5 superiority, formal effects, formal sample-size changes, or Gate 14R conclusions.

## Required next decision

The next safe stage is Gate 13R-PR2-MP2 non-executing memory-policy amendment and formal-preparation validation. That stage may prospectively freeze the recommended policy, map every canonical scenario to a policy tier, implement versioned adapters/configuration, and run validation-only tests. It must not create or start formal attempt 3.

Use [Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md](H:/DDM_Final_Project/Research/Gate13R_PR2_MP2_NonExecuting_Next_Authorization_Prompt.md) for the next authorization.
