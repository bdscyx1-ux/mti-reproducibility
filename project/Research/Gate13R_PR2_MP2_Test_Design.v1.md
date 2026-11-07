# Gate 13R-PR2-MP2 validation-only test design v1

Status: **FROZEN-BEFORE-VALIDATION / NON-EXECUTING / FORMAL-ATTEMPT3-NOT-AUTHORIZED**

## Test objective

Demonstrate that the prospective MP2 policy is uniquely mapped, boundary-correct, fail-closed, path-safe, deterministic, compatible with PowerShell 7 and Windows PowerShell 5.1, and executable by the Unity batch environment without changing the active S48/H48 schedule or any frozen evidence.

## A. Preservation and authorization tests

1. Recompute the frozen pilot-v1 and formal-attempt-2 canonical identities under their original tree contracts.
2. Recompute the MP1-v2 raw identity (3,360 files / 2,607,785,161 bytes / `13dd5c30...`) and prove raw/analysis manifests agree.
3. Verify all frozen roots remain read-only and key-file hashes match the MP2 pre-write audit.
4. Verify formal attempt-3 root, receipt and status are absent before, during and after every validation attempt.
5. Verify authorization/config candidates contain `formalMeasuredCampaignAuthorized=false`, `formalRootCreationAuthorized=false`, `formalReceiptCreationAuthorized=false`, `formalStatisticalAnalysisAuthorized=false`, and `gate14RAuthorized=false`.

## B. Mapping and schedule invariance tests

1. Parse all 53 canonical scenario sources and verify scenario ID, source SHA-256, positive integer width/height and an allowed maximum dimension.
2. Prove exactly one tier for every scenario, all 74 campaigns and all 3,552 schedule records.
3. Prove dimensions 32/64/128 map to `MP2-NATIVE-LE128`; 256 maps to `MP2-NATIVE-EQ256`.
4. Reject missing, non-integer, non-positive, unsupported, hash-mismatched and ambiguous mappings.
5. Regenerate mapping and overlay twice into isolated roots; require byte-identical outputs and SHA-256.
6. Prove the overlay is one-to-one with the active PR2 v2 schedule by global process ordinal, block ID, campaign ID, scenario identity and run IDs.
7. Revalidate 74 campaigns, 3,552 processes, 10,176 samples, 1,008 matched superblocks, Williams rows and heterogeneous AB/BA 24/24 without changing the active schedule bytes.

## C. Pure policy boundary fixtures

For both tiers, test `advisory-1`, `advisory`, `advisory+1`, `hard-1`, `hard`, and `hard+1`. Equality must pass. Above advisory must record without stopping; above hard must produce the exact hard reason and next-block prohibition.

Additional fixtures cover:

- working-set-dominant and private-memory-dominant native metrics;
- negative/non-growing component deltas;
- raw transient above tier hard but below host emergency (diagnostic only);
- cleanup retained native above tier hard (whole-block hard failure);
- managed `128 MiB-1`, `128 MiB`, `128 MiB+1`, `256 MiB`, and `256 MiB+1`;
- post-block managed `256 MiB` and `256 MiB+1`;
- host absolute `4 GiB`, `4 GiB+1`;
- host relative `2 GiB`, `2 GiB+1`;
- available memory `8 GiB`, `8 GiB-1`;
- checked-arithmetic overflow, missing/non-positive/non-finite telemetry, mixed composite process identity, timestamp/process-age/GC regression;
- final-position algorithm attribution rejection.

## D. Cross-runtime adapter tests

1. PowerShell 7 parser, import and parameter-binding smoke tests.
2. Native Windows PowerShell 5.1 parser, import and parameter-binding smoke tests using native `PSModulePath`.
3. Explicit absolute `ProjectPath`, output-root containment, formal-root rejection in validation mode, create-new semantics and path-safe atomic persistence.
4. Candidate formal mode rejects missing/incorrect future attempt-3 receipt, policy registry, overlay or config hashes before Unity launch.
5. A static no-launch dry run proves the adapter maps one schedule record to the expected policy tier and block plan without creating a formal root or receipt.

## E. Unity validation-only tests

All Unity outputs are isolated below a versioned MP2 verification attempt root.

1. Project compile and method-discovery smoke test for the versioned MP2 command.
2. Unity memory-policy self-test covering all exact boundaries and reason-code precedence.
3. Native telemetry/available-memory probe with independent OS/CIM cross-check and composite-process identity.
4. Positive complete shared four-sample Williams block with valid mapping, reset, hashes, telemetry, post-block evaluation and natural lock absence.
5. Expected-negative native hard-ceiling block: persist exact evidence, identify the event as whole-block/process, return failure, and prove no subsequent block launch.
6. Expected-negative telemetry failure and managed/host emergency fixtures.
7. Expected-negative atomic persistence fault: preserve prior evidence, clean only the owned temporary path, and fail closed.
8. Expected-negative lock-hygiene fixture: preserve primary cause precedence and prove lock cleanup does not authorize continuation.

Synthetic threshold crossings may be injected only through an explicitly validation-only fixture field that is rejected by formal plans. They are not experimental observations.

## F. Two-stage state-machine tests

1. Validate state transitions `ACQUISITION-PENDING → RAW-DATA-COMPLETE/ANALYSIS-PENDING/IMMUTABLE → ANALYSIS-COMPLETE`.
2. Reject analysis before immutable raw commit, raw mutation after commit, same-directory analysis overwrite, and analysis-triggered Unity launch.
3. Validate that an ordinary analysis failure requires a new versioned analysis attempt against the same raw tree, not a Unity rerun.

## G. Pass criteria

Every required assertion must pass. A scientific-identifiability, mapping, persistence, telemetry, lock, schedule or frozen-input failure is a hard gate. Implementation defects may be corrected only in a new versioned validation attempt with the failed attempt preserved. Thresholds, schedule, algorithms, reset/correctness contract and two-stage semantics cannot be weakened.

The final readiness checkpoint may be `PASSED` only when:

- all static/unit/cross-runtime/Unity validation assertions pass;
- every upstream pre/post identity matches;
- verification outputs are clearly non-formal and excluded;
- Unity is quiescent and the project lock absent;
- formal attempt-3 root/receipt/status remain absent.
