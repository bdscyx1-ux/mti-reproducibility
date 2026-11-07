# Gate 11 Formal Scenario Matrix Test Design

Frozen: 2026-10-05 (Asia/Shanghai)  
Applies to: `formal-scenario-matrix-v1`  
Status: frozen before production implementation

## 1. Specification audit before implementation

The pre-implementation audit must verify:

- specification id, generator id, preregistration id, matrix counts, factor levels, seed formulas, exclusion rules, analysis rows, precision rule, and preservation boundary are present;
- this test design contains every required verification family;
- neither the generator, Gate 11 Unity command, Gate 11 wrappers, nor the formal bundle exists yet;
- all 24 frozen baseline entries match;
- every existing PowerShell script parses.

After implementation, the same audit switches to frozen-integrity mode: hashes remain identical and specification/test-design write times precede all Gate 11 production-file creation times.

## 2. Generator unit and determinism tests

Verify in Unity that:

1. generator/spec/preregistration ids are exact;
2. the L8 table contains eight unique balanced structural rows;
3. every core row has exactly two seeds and both goal structures;
4. stress level arrays exactly match the frozen values;
5. scenario count is 53 and expanded eligibility count is 212;
6. scenario ids, paths, seeds, and matrix entry ids are unique;
7. regenerating definitions twice in memory produces identical canonical bytes and fingerprints;
8. order-independent integer key generation is stable on fixed known vectors;
9. obstacle count equals the frozen target count;
10. every initial cell is materialized exactly once in `(y,x)` order;
11. weighted costs belong to `{1,2,4,8}` and uniform costs equal `1`;
12. starts/goals are in bounds, walkable, and excluded from general dynamic changes;
13. event ids/ticks/orders/changes match the frozen dynamic profile;
14. restore events reproduce the initial state of every touched coordinate.

## 3. Create-new generation tests

The generation command must:

- refuse any nonempty output directory;
- write scenarios before configs and write the bundle manifest last;
- preserve partial output if generation fails;
- emit a summary with exit code, compiler scan, counts, paths, and pass/fail state;
- record `pilotExecuted = false` and `formalCampaignExecuted = false`;
- refuse a second generation attempt without changing the retained manifest.

## 4. Strict I/O and canonical identity tests

For every retained scenario:

- strict-load through `DeterministicScenarioJson.LoadFromFile`;
- compare source bytes to `SerializeCanonical` bytes;
- require source SHA-256 = canonical SHA-256;
- verify source hash and semantic fingerprint against catalog/matrix/manifest;
- parse the canonical bytes again and require the same fingerprint;
- enforce the 16 MiB maximum;
- require `initialGridOverrides.Count = width × height`;
- require one record for each coordinate and canonical `(y,x)` order;
- require unique scenario id, source hash, and semantic fingerprint across the bundle.

## 5. Matrix and parameter coverage tests

Verify exact counts:

- shared core: 16;
- heterogeneous core: 16;
- grid scale: 4;
- agent scale: 5;
- dynamic footprint: 5;
- goal count: 5;
- reachability: 2;
- total scenarios: 53;
- shared algorithm cells: 33 × 4 = 132;
- heterogeneous per-agent cells: 20 × 2 = 40;
- heterogeneous grouped-field cells: 20 × 2 = 40;
- total eligibility cells: 212.

For the balanced core, verify every two-level factor occurs eight times across the 16 seed-materialized rows and every structural row has the paired shared/heterogeneous files with identical cell/event materialization.

## 6. Cohort, provenance, and planner initialization tests

For every matrix entry:

- recompute distinct goal count;
- require shared entries to classify as `four-algorithm-shared-goal-v1` for all four profiles;
- require heterogeneous entries to classify as `per-agent-heterogeneous-goal-v1` for `A*-R`/`D*L` and `grouped-field-heterogeneous-goal-v1` for `C-FF`/`IDFF`;
- require the exact authorized algorithms declared by the config;
- initialize fresh `A*-R`, `D*L`, `C-FF`, and `IDFF` instances against a fresh grid snapshot;
- require initialization to finish without exception, invalid grid, or stale version;
- reset each planner after initialization;
- do not execute a planning workload or persist initialization timing as an experimental result.

## 7. Independent reachability tests

Use a verifier-owned BFS/Dijkstra-free graph traversal independent of all four planners.

For general scenarios:

- every start must reach its declared goal initially and after each same-tick-complete dynamic phase;
- apply events by canonical tick/order and confirm the final restore state equals the initial grid for all touched cells.

For temporary-disconnection scenarios:

- expected all-agent reachability sequence is `true, true, false, true, true` for initial plus four phases;
- strict eight-way traversal must enforce both orthogonal corner cells before allowing a diagonal;
- final grid must restore both gates.

## 8. Preregistration config tests

Require machine-readable rows for `P1`–`P4` and `S1`–`S5`, with:

- exact scenario-family selector;
- exact comparison cohort;
- authorized algorithm contrast or model;
- endpoint id and unit;
- confirmatory/descriptive classification;
- multiplicity family;
- two-sided alpha for confirmatory rows;
- outlier, failure, technical invalidity, replacement, and amendment policies;
- Gate 12 precision formula and Gate 13 fixed-N/no-early-stop rule;
- environment preflight requirements.

Unknown analysis ids, missing rows, duplicate rows, or a formal numeric sample size before Gate 12 invalidate the config.

## 9. Tamper and negative tests

Using temporary copies only, require rejection of:

- changed scenario bytes;
- changed source hash or fingerprint in catalog/matrix;
- duplicate scenario id or matrix entry id;
- missing or extra scenario file;
- truncated full-cell materialization;
- wrong factor metadata or seed;
- unauthorized algorithm/cohort combination;
- changed specification/generator/workload/fairness hash;
- changed preregistration row or precision rule;
- manifest written with `pilotExecuted` or `formalCampaignExecuted` true;
- incomplete or malformed bundle aggregate hash.

The retained bundle must remain unchanged after every negative test.

## 10. Regression and final audit

Run:

- real Unity compile with current runtime/editor assemblies;
- Gates 2–10 behavioral, batch, replication, compatibility, and final audits;
- Gate 11 generation and retained-bundle verification;
- PowerShell, JSON, JSONL, evidence-hash, formal-planner-scope, warning, process, and lockfile audits;
- 24-entry frozen baseline verification.

The Gate 11 checkpoint must record exact counts and hashes, state that no pilot/formal sample was executed, and advance the authorization boundary to Gate 12.

