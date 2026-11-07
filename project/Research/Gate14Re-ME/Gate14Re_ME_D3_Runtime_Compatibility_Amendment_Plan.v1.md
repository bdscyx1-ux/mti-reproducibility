# Gate14Re-ME D3 Runtime-Compatibility Amendment Plan v1

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: run / source-freeze amendment
- Origin Date: 2026-10-17
- Verification Status: UNVERIFIED until the bounded D3-only run and freeze validator pass
- Version Label: gate14re_me_d3_runtime_compatibility_amendment_plan_v1

## Scope

This is the smallest stage after runtime-qualification attempt-001 failed closed at D3. It may diagnose and replace only the D3 managed-allocation counter, add prospective positive and negative known-answer controls, execute those controls once in the bound Unity runtime, and freeze the resulting source and evidence.

It must not retry attempt-001, start a full runtime-qualification attempt-002, run the data-export known-answer, generate qualification schedules, inputs, or identity maps, create a qualification measured root, execute an algorithm lane, collect formal observations, analyze algorithms, rank algorithms, or adjudicate a winner.

## Rationale and prospective semantic amendment

The failed counter was thread-scoped `GC.GetAllocatedBytesForCurrentThread`. The Microsoft API contract defines it as a lifetime count for the current thread, but the bound Unity runtime returned no increase for a retained 1 MiB allocation. The candidate is `GC.GetTotalAllocatedBytes(precise: true)`, whose API contract is a process-lifetime managed-allocation count excluding native allocations. Unity 2022.3 documents .NET Standard 2.1 as a supported API profile but also requires runtime-specific validation of .NET system-library behavior.

If qualified, D3 therefore changes prospectively from “managed allocations on the measured Unity thread” to “process-wide managed allocations occurring during the synchronous measured boundary.” This is not a heap-live-size substitution and does not use `GC.GetTotalMemory`.

Primary documentation:

- https://learn.microsoft.com/en-us/dotnet/api/system.gc.getallocatedbytesforcurrentthread
- https://learn.microsoft.com/en-us/dotnet/api/system.gc.gettotalallocatedbytes
- https://docs.unity3d.com/2022.3/Documentation/Manual/dotnetProfileSupport.html
- https://docs.unity3d.com/2022.3/Documentation/Manual/overview-of-dot-net-in-unity.html

## Prospective one-shot acceptance criteria

1. Run exactly 64 empty counter intervals. Every difference must be nonnegative and the maximum may not exceed 65,536 bytes.
2. Allocate and retain a 1,048,576-byte array within one interval. The difference must be at least 1,048,576 bytes.
3. Allocate and retain a 4,194,304-byte array within a later interval. The difference must be at least 4,194,304 bytes.
4. The larger-control difference minus the smaller-control difference must be at least 3,145,728 bytes.
5. All counter readings must be nonnegative and monotonic.
6. The harness must construct no planner, execute no algorithm lane, and create no observation.

These thresholds are fixed before execution. They may not be relaxed after seeing the result.

## Stop rules

Any prior-evidence hash mismatch, executable hash mismatch, existing output path, concurrent Unity process, forbidden-root appearance, compilation error, timeout, exception, non-monotonic reading, negative-control failure, positive-control failure, or scale-separation failure stops the stage without retry. A failure is frozen as failure evidence; no fallback metric is adopted in the same authorization.

## Completion rule

Only a passing one-shot receipt permits creation of the versioned D3 instrument contract and the new source-only scientific freeze. Even after success, runtime-qualification attempt-002 and the deferred exporter known-answer remain separately unauthorized.
