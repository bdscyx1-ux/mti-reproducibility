# Gate 13R-PR2 Attempt 2 Embedded Contract Repair Specification v1

Status: `FROZEN-BEFORE-IMPLEMENTATION / NON-ANALYTIC / FORMAL-ROOT-NOT-CREATED`

Recorded: 2026-10-08T17:58:03Z (2026-10-09T01:58:03+08:00)

## Authority and boundary

This specification implements only the repair authorized by
`Gate13R_PR2_Attempt2_Execution_Authorization.v1.json`. It does not authorize
formal statistical analysis, Gate 14R, Playable/OBS execution, reuse of the
attempt-1 root, or any change to the frozen S48/H48 scientific design.

Attempt 1 remains permanently
`FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE /
PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS`. Its 31-file,
3,338,221-byte tree has canonical SHA-256
`026b9830f220b06af3f0a106f638b3d918d115ba08f5f06c13d9d76542ba4f56`.

## Confirmed defect

The frozen producer `Gate13RPR2FormalBatchCommandV2.cs` serializes each
completed child sample through `BlockChildRecord`. The record did not declare
`formalCampaign`, although the authoritative sample summary, child manifest,
memory evaluation, block plan, and top-level block manifest all carried that
field. The frozen V4 block wrapper correctly required
`block-manifest.json.samples[].formalCampaign == true`; under StrictMode the
missing property caused a `PropertyNotFoundException` after the first Unity
block had completed.

## Permitted producer change

The V3 C# adapter is a mechanical derivative of the frozen V2 adapter. Exactly
three source-level changes are permitted:

1. Change the public class identity from
   `Gate13RPR2FormalBatchCommandV2` to `Gate13RPR2FormalBatchCommandV3`.
2. Add `public bool formalCampaign;` to `BlockChildRecord` immediately before
   its `completed` field.
3. Assign `formalCampaign = plan.formalCampaign` when constructing every
   returned `BlockChildRecord`, immediately before assigning `completed`.

No algorithm, scenario, timing, telemetry, managed-memory, reset, oracle,
structural comparison, output path, or workload behavior may change.

## Consumer contract

The V5 block wrapper must fail closed unless all of the following are true:

- the block plan and top-level block manifest carry Boolean
  `formalCampaign=true`;
- `samples` has the exact expected cardinality and every embedded record has a
  present, Boolean, true `formalCampaign` property;
- embedded run IDs are present and unique within the block;
- each sample summary, child manifest, and managed-memory evaluation has a
  present, Boolean, true `formalCampaign` property;
- all record identities, positions, process identities, paths, hashes,
  Williams order, reset fields, telemetry fields, and memory gates remain
  valid.

Missing, string-valued, numeric, null, or false embedded `formalCampaign`
values are contract failures. They must never be defaulted or coerced to true.

## Validation-only rehearsal boundary

One complete, four-algorithm, fresh-Unity Williams block may be run outside the
formal root under the explicit switch `ValidationOnlyContractRehearsal`. The
plan and outputs must additionally carry:

- `validationOnly=true`;
- `excludedFromFormalAnalysis=true`;
- `formalExecutionAuthorized=false`;
- `contractRehearsalId=gate13r-pr2-attempt2-embedded-contract-rehearsal-v1`.

The `formalCampaign=true` bit remains intentionally set in that rehearsal only
to exercise the exact repaired producer/consumer payload contract. The
validation markers dominate its analysis eligibility: the rehearsal is never
formal data and may not be merged with attempt 1, attempt 2, pilots, or future
analyses.

## Formal attempt-2 invariant

After all validation and fresh prelaunch gates pass, the only permitted formal
root is
`H:/DDM_Final_Project/Research/FormalRuns/Gate13R_RQAligned_S48H48/v2`.
The frozen schedule remains 74 campaigns, 3,552 fresh Unity block processes,
10,176 algorithm samples, 1,008 heterogeneous matched superblocks, strict
serial execution, and AB/BA 24/24 per heterogeneous scenario.

Attempt 2 is one-shot. Any measured-data contract failure before all Unity
blocks complete ends it as
`FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE`. After all Unity blocks
complete, the two-phase commit rules prevent ordinary audit or analysis code
defects from causing a Unity rerun.

