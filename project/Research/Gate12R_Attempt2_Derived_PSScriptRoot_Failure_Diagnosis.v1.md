# Gate 12R official pre-pilot attempt 2 failure diagnosis

- Status: `FAILED-VERSIONED-REPAIR-RETRY-ALLOWED`
- Failed attempt root: `Research/Verification/Gate12R_ProcessReuse_5pct/v2`
- Static/unit and Playable mapping: passed
- Unity compilation: passed, exit code 0, zero compiler/error-pattern matches, natural lock absence
- Telemetry Unity process started: `false`
- Pilot root created: `false`
- Gate 13R formal root created: `false`

The v2 telemetry compatibility wrapper correctly derived a source file without changing telemetry semantics, but placed that derived file in an isolated evidence directory. The frozen v1 telemetry source locates two modules relative to `$PSScriptRoot`; after relocation, that variable referred to the evidence directory rather than `Research`, so `Import-Module` failed before Unity telemetry execution began. The same latent relocation defect applies to the mechanically derived cold-reference source.

The authorized v3 compatibility repair changes only the two derived-source module import expressions to resolve from the already mandatory, absolute `ProjectPath\Research` path. It retains the v2 empty-array fix and additionally captures derived-child stdout/stderr as versioned evidence. Algorithms, Unity commands, scenario data, Williams ordering, reset semantics, telemetry and memory thresholds, 5% precision, no-cap policy, and exclusion rules remain unchanged.

Frozen attempt-2 anchors:

- `execution-receipt.json`: `c0d467c6791bb3dc65dec768d3f48e14f83fee9764e3cf6a90239dbd93cf5840`
- `failure-receipt.json`: `1cc2cc862b691f3736d1bed9a32b6a3718289a808d755872841440b7c47cd3b4`
- `gate12r-checkpoint.json`: `5bb35a129d09dde6a7750f17a1ba4934629df2f93181b607da50ea6fa96a2646`
- `partial-output-manifest.json`: `0f048b0d18c5720c49ee813ce0e29965689a1e3030995fe11ebc065c3d01442e`
- `Compile/summary.json`: `c4a8d1354eb5bdfdd9f041ecb12d2e715fbe70dbedd0ce837d30292dc71799ea`
- Attempt-2 root at diagnosis: 23 files, 112,169 raw bytes.

