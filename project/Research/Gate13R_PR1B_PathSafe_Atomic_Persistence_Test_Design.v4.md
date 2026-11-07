# Gate 13R-PR1B path-safe atomic persistence test design v4

## Pre-write and preservation gates

- Verify the v12 tree identity `4ae0c0ea30e65b0cf5e15bbdffeffd8155e7e5de341c262f4ad3d2e00c4f12fe` before and after v13.
- Verify v6, v9, v10, and v11 retained roots and all authorization/provenance inputs remain byte-identical.
- Verify the new v13 verification root, new v7-v4 pilot root, Unity lock, and reserved formal root are absent before execution.
- Verify zero Unity processes before v13 creation.

## Windows PowerShell 5.1 atomic-helper fixtures

The v4 helper must pass synthetic create/replace/failure fixtures before any Unity launch:

1. create a new JSON file through a short same-directory temporary leaf;
2. replace an existing mutable JSON file through a short same-directory backup leaf;
3. preserve valid UTF-8-no-BOM JSON and the exact new semantic value;
4. reject a directory target;
5. reject a missing parent;
6. reject a reparse-point parent;
7. reject pre-existing temporary/backup collisions in deterministic injected fixtures;
8. clean up only invocation-owned temporary and backup leaves after injected write, replace, and cleanup paths;
9. leave zero `.g13tmp-*` and `.g13bak-*` residues;
10. prove that v12 files and frozen immutable evidence were not replaced.

## Full v13 gate chain

After parser, parameter-binding, path-isolation, plan/provenance, and atomic-helper smoke checks pass, v13 must rerun the complete frozen chain:

- static/unit and analyzer fixtures;
- Unity compilation;
- Unity C# path-safe atomic self-test, including legacy temporary lengths 259, 260, 261, and 280;
- 128/256/256/512 MiB exact-boundary memory-policy self-test;
- positive PSAPI/CIM telemetry cross-check;
- positive block and negative fail-closed block;
- independent-process repeatability;
- cold-process structural control;
- retained 63/63 regression;
- hash/provenance and validation-only final audit.

Any failure preserves a versioned root and stops before pilot creation. Only a passing v13 final audit may authorize creation of the new v7-v4 NON-FORMAL pilot root. No pilot retry, resume, top-up, or merge is permitted once that root exists.

