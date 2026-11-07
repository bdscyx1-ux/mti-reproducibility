# Gate14Re-ME D3-v3 cumulative allocation qualification attempt-002 plan v1

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: run / isolated toolchain repair and instrument qualification
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until SDK installation, the one native build, and the conditional one Unity known-answer run complete
- Version Label: gate14re_me_d3_v3_cumulative_allocation_qualification_attempt_002_plan_v1

## Independent authorization and boundary

Attempt-002 is a new, independent toolchain-repair attempt. Attempt-001 remains immutable failure evidence and will not be resumed, overwritten, or deleted. This attempt may install exactly one compatible Windows SDK component for the current Visual Studio 2022 instance, freeze the installed SDK version and critical files, compile the already-authorized Windows x86-64 native D3-v3 counter once under the newly frozen encoding policy, and—only after successful compilation—run exactly one versioned copy of the original algorithm-free known-answer harness.

This attempt does not integrate or modify the current qualification runner or output schema. It does not generate a schedule, qualification input, anonymous identity mapping, or qualification measured root. It does not construct a planner, execute any algorithm lane, collect formal observations, analyze algorithms, rank algorithms, or adjudicate a winner.

## SDK selection

The exact installed Visual Studio 17.14.41 catalog exposes `Microsoft.VisualStudio.Component.Windows11SDK.26100` with catalog version `17.14.37011.9` and display title `Windows 11 SDK (10.0.26100.7705)`. The component is selected because it is in the current instance catalog and is not marked out of support. No other component is requested.

After installation, the attempt must record the installed SDK product version, include and library roots, the initialized `WindowsSdkDir` and `WindowsSDKVersion`, and SHA-256 values for the SDK installer/catalog evidence and a fixed critical-file set including `Windows.h`, `winnt.h`, `sdkddkver.h`, the Universal CRT `stdlib.h`, and x64 `kernel32.lib`. Missing or ambiguous versioned roots stop the attempt.

## Frozen compiler policy

The one native build must retain `/W4` and `/WX`, add `/utf-8`, and continue to use `/std:c++17`, `/permissive-`, and `/Brepro`. No warning suppression, code-page fallback, warning-level reduction, or removal of warnings-as-errors is permitted. The exact initialized compiler, linker, `vcvars64.bat`, SDK roots, command line, stdout/stderr log, exit code, and output hashes must be frozen.

## Conditional one-shot execution

The native build is attempted exactly once. If it fails, no Unity process may start. If and only if it succeeds and the DLL hash is frozen, one Unity 2022.3.30f1c1 batch process may compile and execute the attempt-002 harness. The harness preserves the original prospective controls unchanged: exact `GC.Alloc` marker/Int64 metadata qualification, 64 warmed empty windows, 4 KiB/64 KiB/1 MiB array scaling, 4096 repeated small objects, GC reclamation invariance, owner-thread response, worker-thread exclusion, byte/rate formula identity, and zero invalid-metadata/overflow events.

No native-build or Unity retry is authorized. Any failure is frozen in place and ends this attempt without fallback or expansion.
