# Gate 10R Attempt 4 outside-root preflight v1 failure diagnosis

Status: `FAILED-ATOMICALLY-CLOSED-RETRY-V2-AUTHORIZED`  
Official Gate 10R execution count: 0  
Unity started: no  
Official `v4` root created: no

The v1 outside-root preflight reached and passed its deterministic source-generation validation. Its first output-isolation negative then deliberately invoked the file-scope harness with the frozen original 63/63 summary as the requested output. The harness correctly rejected that prohibited path and wrote the expected error to stderr.

Because the parent Windows PowerShell 5.1 preflight used `$ErrorActionPreference = 'Stop'` and invoked the expected-failure child directly, PowerShell promoted that child stderr to a terminating `NativeCommandError` before the parent could classify the nonzero exit as a passing negative test. This is a preflight result-capture defect; it is not a retained-harness failure and it does not alter the confirmed attempt-3 child-ScriptBlock diagnosis.

The v2 preflight repair is limited to launching the expected-negative harness checks through `System.Diagnostics.Process` with redirected stdout/stderr and reading the child `ExitCode`. It does not modify the retained harness, frozen 63 assertions, algorithms, Unity command, process model, Williams order, reset, telemetry, lock hygiene, precision policy, cap policy or Playable semantics.

