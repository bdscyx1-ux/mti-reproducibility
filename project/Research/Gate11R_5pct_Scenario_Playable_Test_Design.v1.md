# Gate 11R — 5% Scenario/Playable Bundle Test Design v1

Saved: 2026-10-07 (Asia/Shanghai)

## Material passport

- Test-design ID: `gate11r-process-reuse-5pct-scenario-playable-tests-v1`
- Specification ID: `gate11r-process-reuse-5pct-scenario-playable-spec-v1`
- Active upstream: Gate 10R attempt 4 / `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Execution policy: one official Gate 11R attempt, fail closed, no automatic retry or resume
- Authorized terminal state: `GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION`

## 1. Test ordering

The following stages are hard gates and run strictly in order. Production generation is forbidden until stages 1–3 pass. Any failure writes an atomic failed receipt, evidence manifest, log hashes, and checkpoint, then exits without entering later stages.

1. outside-root static/preimplementation audit;
2. PowerShell parser, parameter-binding, path-isolation, and create-new tests;
3. Unity compilation and editor-unit/specification tests;
4. single-use production generation;
5. separate-process scenario and Playable verification;
6. negative/tamper and timing-isolation checks;
7. preservation and validation-only final audit.

## 2. Preimplementation assertions

The outside-root audit must prove:

- Gate 10R v4 terminal checkpoint is exactly passed and its final audit/tree hashes match the authorization;
- the authorization source hash matches;
- scenario, campaign, eligibility, seed, precision, Williams, exclusion, pilot-anchor, and Playable contracts are internally complete;
- expected counts are 53 scenarios, 74 campaigns, 212 algorithm cells, 53 scenario scenes, 74 profiles, 212 presets, and one launcher;
- all four official Gate 11R production roots are absent;
- Gate 12R and Gate 13R roots are absent;
- protected tree identities and protected material hashes match the prewrite audit;
- no Unity process and no project lock are present;
- specification and test-design hashes are captured before production implementation.

The audit writes outside `Research/Verification/Gate11R_5pct/v1` so that an official root cannot exist before the single-use receipt is consumed.

## 3. Static and unit tests

### 3.1 Matrix and seed tests

- generate blueprint metadata twice in one process and exact-compare all fields;
- assert lexically unique scenario IDs and exactly 32 shared/21 heterogeneous;
- assert the eight core rows, two replications, formulas, and shared/heterogeneous pairing;
- assert all stress level sets and seed formulas;
- assert every generated scenario validates, has the expected seed/family/level, and uses only frozen deterministic inputs;
- assert the additive generator does not read `Research/FormalScenarios/v1`.

### 3.2 Campaign and eligibility tests

- assert 32 shared, 21 per-agent, and 21 grouped-field campaign IDs;
- assert all campaign IDs are unique and point to exactly one canonical scenario;
- assert four algorithms for shared and the correct two for each heterogeneous cohort;
- assert exactly 212 unique `(campaign, algorithm)` cells and 53 cells per algorithm;
- reject wrong cohort/algorithm pairs, duplicate cells, unknown scenarios, and mixed design IDs.

### 3.3 Williams tests

- assert the exact four shared rows and the two forward/reverse heterogeneous rows;
- assert every row is a permutation of eligible algorithms with no duplicate;
- over a four-block supercycle, assert every algorithm occupies every shared position once and every heterogeneous position twice;
- assert predecessor/carryover counts are balanced according to the frozen square;
- assert `blockOrdinal -> row -> position/predecessor` is deterministic and independent of filesystem order.

### 3.4 Precision, exclusion, and preregistration tests

- assert `ln(1.05)` equals `0.048790164169432` within `1e-15`;
- assert minimum 32, rounding multiple 4, and no hard cap;
- assert no outcome-dependent exclusion and all failure categories remain in future denominators;
- assert P1–P4 primary and S1–S5 secondary table definitions are present;
- assert all 12 pilot campaign anchors resolve to eligible campaigns.

### 3.5 Playable mapping tests

- assert safe deterministic filename encoding and no path collision;
- assert exactly one scene per scenario, one profile per campaign, and one preset per eligible cell;
- assert every preset maps to one profile and its profile's scene;
- assert direction glyph, watermark, capture layout, controls, and visualization-only flags are immutable constants;
- assert the headless timing runner has no dependency from any generated plan/config to a Playable asset path.

## 4. Unity compile gate

Run a fresh Unity batch process with the verified editor. Compilation passes only with exit code 0, no compiler-error log match, no unexpected project mutation outside additive Gate 11R source/meta files and ordinary Unity transient directories, and natural lock release. The process tree and log hash are recorded.

## 5. Official generation gate

Before generation, atomically create and consume a versioned execution receipt bound to the exact authorization, specification, test design, source files, Unity executable/version, project path, and four resolved output roots. Recheck that each output root is absent.

One fresh Unity batch process creates all production outputs. It writes content into staging directories under the same parent and promotes complete roots only after internal validation. Manifests/catalogs are written last. A partial failure is marked `INCOMPLETE / EXCLUDED` and cannot be resumed.

Generation must produce:

- 53 strict canonical JSON scenarios plus matrix/catalog/preregistration/bundle manifest;
- 53 scenario scenes and one launcher scene;
- 74 campaign profile assets;
- 212 algorithm preset assets;
- four research-side catalogs/manifests;
- a generation summary containing counts, raw bytes, file hashes, GUIDs, and root tree hashes.

## 6. Separate-process verification gate

A second fresh Unity batch process treats production roots as read-only and must:

1. regenerate all 53 scenario definitions in memory and byte-compare them to disk;
2. resolve every scenario and compare its fingerprint, seed, dimensions, agents, goals, events, family and level metadata;
3. load every generated scenario scene and the launcher, assert zero missing scripts, exactly one scenario controller per scenario scene, exact scenario/hash bindings, and valid camera/capture configuration;
4. load all 74 profiles and 212 presets by GUID/path and verify every serialized field;
5. rebuild the 74/212 coverage graph independently and exact-match the catalogs;
6. initialize each of the 212 eligible planner/scenario/cohort cells without collecting timing observations, then reset it;
7. snapshot every production file before/after verification and assert byte immutability;
8. emit one validation summary and an independent signature over the complete coverage graph.

This process is validation-only and all its outputs are excluded from formal analysis.

## 7. Negative and fail-closed tests

Tests use in-memory clones or disposable paths outside the production roots. They must reject:

- a modified scenario byte or mismatched scenario fingerprint;
- duplicate/unknown campaign and preset IDs;
- an ineligible algorithm/cohort combination;
- a missing scene/controller/profile/preset;
- a wrong asset GUID, scenario hash, design ID, Williams row, glyph ID, watermark, or visualization flag;
- an existing output root, path escape, symlink/reparse redirection, or historical-root target;
- a timing config that references a Playable path;
- any attempt to create Gate 12R or Gate 13R output.

At least one injected pre-generation failure must demonstrate that no production root is created. Negative tests must never alter the retained bundle or original assets.

## 8. Preservation and final audit

The final audit recomputes every protected tree/material identity from `Gate11R_PreWrite_Preservation_Audit.v1.json`, verifies Gate 10R attempts 1–4 are unchanged, confirms historical roots remain read-only where already frozen, confirms original script/scene hashes are unchanged, and confirms Gate 12R/Gate 13R roots remain absent.

It then verifies all production manifests against live bytes, records root file counts/raw bytes/tree hashes, records Unity process count 0 and absent lockfile, and writes an atomic terminal checkpoint.

Passing terminal status:

```text
GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION
```

Failing terminal status:

```text
GATE11R-FAILED-NO-AUTO-RETRY-NO-RESUME
```

Gate 12R and Gate 13R are never invoked by this test design.
