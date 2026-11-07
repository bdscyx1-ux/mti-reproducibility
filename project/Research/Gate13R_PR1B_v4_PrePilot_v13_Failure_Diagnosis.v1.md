# Gate 13R-PR1B v4 pre-pilot v13 failure diagnosis

## Terminal classification

`FAILED-NO-PILOT / PREPILOT-ONLY / BLOCK-SAMPLE-NOT-STARTED / FORMAL-NOT-AUTHORIZED`

The v13 verification root is frozen byte-for-byte and must not be overwritten, resumed, or relabelled as passing.

## Passed evidence

v13 proved the Windows PowerShell 5.1 atomic replacement repair in the actual orchestrator and passed static/unit, Unity compilation, Unity path-safe boundary self-tests, memory threshold self-tests, and PSAPI/CIM telemetry. The failure occurred before the first positive/negative block sample was launched.

## Root cause

The new provenance v6/v7 was intentionally rebuilt from selected fields rather than cloning every Gate10R-compatible binding from v5. `New-Gate10RBlockPlan` requires five top-level compatibility bindings: `config`, `specification`, `testDesign`, `executionAuthorization`, and `unityCommand`. v7 contains the first three but omitted `executionAuthorization` and `unityCommand`. Strict mode therefore raised `PropertyNotFoundException` while generating the first verification block plan.

This is a provenance-schema compatibility defect. It is not a Unity, algorithm, reset, memory-threshold, structural, scenario, statistical, or sample-eligibility failure.

## Permitted narrow repair

Create a new provenance version that preserves v7 and all 49 bound files, adds:

- `executionAuthorization`, byte-bound to the existing user authorization file `Research/Gate13R_PR1B_v3_Authorization.v1.json`;
- `unityCommand`, byte-bound to the unchanged C# V3 path-safe command;
- the v13 terminal-preservation and diagnosis evidence.

Then verify all five compatibility fields and their hashes with a non-Unity block-plan generation smoke before creating a new verification root. Scientific semantics and all thresholds remain unchanged.

