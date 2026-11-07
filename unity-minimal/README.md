# Minimal navigation core project

This project contains the six frozen navigation backends, their interface definitions and a new independent functional checker. The seven original source files are byte-preserved and identified in source-identities.json. The checker is new packaging validation code and is not part of the historical experiment.

The project requires Unity 2022.3.30f1c1 and no Asset Store assets or external Unity packages. It has been compiled and checked in a fresh project copy using that Editor version on Windows. Unity may regenerate its settings, package lock and cache when opening the project.

From the repository root:

```powershell
python tools/run_unity_check.py --unity "<path to Unity.exe>" --output "../unity-check-001"
```

The output directory must be new. The launcher copies this project, verifies the original source hashes, compiles it in batch mode and runs 120 checks: six algorithms, four-neighbor and strict eight-neighbor movement, two fixed agent starts and five grid states. The grid states cover initial weighted traversal, a barrier with a gap, disconnection, reconnection and a cost increase. Successful path costs are compared with an independent Dijkstra implementation; path legality, endpoints, grid versions and NoPath statuses are checked.

Success requires validation.json to report PASS and functional-check.json to contain 120 passed checks. The wrapper also retains the Unity log. These small functional checks do not reproduce published timings, the historical movement Player, the SMSB instrumentation or the complete experiment matrix. Use the archived-data analysis entry point to reproduce the supplemental numerical results.
