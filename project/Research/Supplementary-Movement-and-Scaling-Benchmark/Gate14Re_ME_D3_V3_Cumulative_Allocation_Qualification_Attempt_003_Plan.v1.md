# Gate14Re-ME D3-v3 cumulative allocation qualification attempt-003 plan v1

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: run / bounded autonomous instrument repair and qualification
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until the final D3-v3 qualification receipt and immutable freeze both pass
- Version Label: gate14re_me_d3_v3_cumulative_allocation_qualification_attempt_003_plan_v1

## Authorized endpoint

Attempt-003 continues until D3-v3 is fully usable as a separately frozen instrument: a compatible Windows SDK is installed and frozen, the Windows x86-64 plugin builds with `/utf-8`, `/W4`, and `/WX`, Unity imports and compiles the versioned wrapper/harness, and the unchanged algorithm-free known-answer qualification criteria all pass. Completion makes the instrument eligible for a later separately authorized runner/schema integration stage; it does not itself perform that integration.

## Repair-loop policy

The user explicitly authorizes automatic repair after a failure within this attempt. This overrides the experiment-agent default no-auto-retry rule only for the bounded SDK/plugin/wrapper/harness qualification work described here. Every command, failed cycle, diagnostic, source version, binary hash, and disposition remains preserved under a monotonically numbered repair-cycle directory. No failed evidence may be deleted, rewritten, or silently replaced.

Permitted repairs include correcting installer syntax, waiting for the installer service and VS instance to settle, correcting native build errors, creating versioned—not overwritten—native or managed source when frozen bytes would change, correcting Unity compilation/import problems, and correcting the algorithm-free harness or plugin implementation when a known-answer control exposes a defect. Repairs may not change the D3 semantic endpoint, relax an acceptance threshold, suppress warnings, remove `/WX`, substitute another metric, construct a planner, or use algorithm data.

## Ordered execution

1. Freeze the authorization, plan, attempt-001/002 bindings, protected runner/schema hashes, and installation preflight.
2. Invoke the selected Windows 11 SDK component with installer-supported syntax and monitor the installer/VS instance to a verified terminal state.
3. Freeze the exact installed SDK product version, registry binding, include/library/bin paths, `vcvars64` environment, and critical-file hashes.
4. Create an attempt-003 algorithm-free harness whose acceptance criteria are identical to the original prospective D3-v3 contract.
5. Compile the native plugin under `/utf-8 /W4 /WX`; preserve and repair any failed build cycle without mutating frozen prior evidence.
6. After a successful binary freeze, run Unity algorithm-free qualification cycles. Preserve every failed run and repair only implementation/harness defects without relaxing criteria.
7. When all criteria pass, freeze the qualified source, DLL, import metadata, wrapper, harness, contract, SDK/toolchain manifest, qualification receipt, and final validation receipt.
8. Stop and request separate authorization for runner/schema integration. Do not proceed into schedules, inputs, identities, measured roots, algorithms, collection, analysis, ranking, or adjudication.

## Hard stops

A hard stop remains if success would require changing endpoint semantics, using a substitute metric, entering any prohibited later stage, changing security settings, supplying credentials, authorizing a reboot, or overcoming a non-repairable Unity profiler limitation. Such a stop preserves all evidence and requests the exact missing authority rather than widening scope.
