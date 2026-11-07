# Gate14Re-ME formal ST v5 migration package

This package installs or locates the exact Unity 2022.3.30f1c1 editor, verifies
every frozen package file, runs the bounded-memory acceptance known-answer
tests, compiles the Unity project, and executes an algorithm-free readiness
entry point.

Run `START-HERE.cmd` from the extracted package. The script may install the
bundled Unity editor if the exact executable is absent. Unity licensing remains
the responsibility of the target machine; no account or license credential is
included.

Successful readiness does **not** generate formal inputs or a formal schedule,
does **not** create a formal measured root, and does **not** start formal ST
collection, formal analysis, MQ, or MT. Those stages require their own later,
explicit authorization and fresh versioned roots.

Advanced use from the bundled PowerShell runtime:

```powershell
MigrationRuntime\PowerShell\pwsh.exe -NoProfile -File `
  Research\Gate14Re-ME\Package\v5\Install-And-Verify-Gate14ReMEFormalST.v5_0.ps1 `
  -UnityExecutable D:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe `
  -ReceiptRoot D:\Gate14ReME-readiness\attempt-001
```

The formal acquisition supervisor is packaged for later use but is never
called by `START-HERE.cmd` or the readiness script.
