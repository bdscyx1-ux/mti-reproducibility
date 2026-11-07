# Gate 11R — 5% Process-Reuse Formal Scenario and Playable Bundle Specification v1

Saved: 2026-10-07 (Asia/Shanghai)

## Material passport

- Specification ID: `gate11r-process-reuse-5pct-scenario-playable-spec-v1`
- Scenario-matrix ID: `gate11r-process-reuse-5pct-scenario-matrix-v1`
- Generator ID: `ddm-gate11r-formal-scenario-generator-v1`
- Preregistration ID: `ddm-gate11r-planning-preregistration-v1`
- Playable-bundle ID: `gate11r-playable-experiment-bundle-v1`
- Active upstream design ID: `gate10r-one-fresh-unity-process-per-williams-block-5pct-v1`
- Active upstream evidence: Gate 10R attempt 4 only
- Precision policy: `two-sided-95pct-ci-relative-half-width-5pct-uncapped-v1`
- Status at freeze: specification only; no Gate 11R production root exists

## 1. Scope and immutable boundary

Gate 11R creates and validates research-only inputs. It does not execute a timing pilot or formal timing campaign. Its only writable production roots are:

```text
Research/FormalScenarios/Gate11R_5pct/v1
Research/PlayableExperiments/Gate11R_5pct/v1
Assets/_Scenes/Research/Playable/Gate11R_5pct/v1
Research/Verification/Gate11R_5pct/v1
```

The old `Research/FormalScenarios/v1` bundle is design-history evidence, not an active execution input. Gate 10R attempts 1–4, every historical cold/process-reuse root, the old Gate 11 retained bundle, Gate 12 archives, original game scripts, and original scenes are read-only. Gate 12R and Gate 13R roots must remain absent.

Generation is create-new and single-use. An existing non-empty production root is a hard error. A hard error atomically records a failed receipt, manifest, log hashes, and checkpoint, then stops without retry or resume.

## 2. Experimental unit and precision policy

The independent execution unit inherited from Gate 10R is one fresh Unity Editor process per complete Williams block. The process executes either four algorithms for a shared-goal campaign or two algorithms for a heterogeneous-goal cohort. Each eligible algorithm appears exactly once in the process. Every sample has its own run ID and fully reset planner, grid, scenario state, runner, logger, metrics collector, and mutable static state.

The formal target remains a two-sided 95% confidence interval with 5% relative half-width on the exponentiated scale:

```text
h = ln(1.05) = 0.048790164169432
raw_n = ceil((1.96 * sigma_upper / h)^2)
```

`n` means independent Williams-block Unity processes per scenario/cohort. The future candidate is rounded upward to a multiple of four and has a minimum of 32 blocks. There is no hard cap. Gate 11R does not estimate `sigma_upper` or `n_formal`.

## 3. Canonical scenario matrix

### 3.1 Counts and goal cohorts

The matrix contains exactly 53 unique canonical scenarios:

| Scenario family | Canonical scenarios | Goal form |
|---|---:|---|
| balanced core | 32 | 16 shared + 16 heterogeneous |
| grid scale | 4 | shared |
| agent scale | 5 | shared |
| dynamic footprint | 5 | shared |
| heterogeneous goal count | 5 | heterogeneous |
| strict reachability | 2 | shared |
| total | 53 | 32 shared + 21 heterogeneous |

Shared scenarios produce one `shared-goal` campaign with four eligible algorithms. Heterogeneous scenarios produce two campaigns over the same immutable scenario bytes: `per-agent-heterogeneous-goal` with `A*-R` and `D* Lite`, and `grouped-field-heterogeneous-goal` with `C-FF` and `IDFF`. Therefore Gate 11R contains exactly 74 campaign conditions and 212 eligible algorithm cells:

```text
32 shared campaigns * 4 algorithms = 128 cells
21 per-agent campaigns * 2 algorithms = 42 cells
21 grouped-field campaigns * 2 algorithms = 42 cells
total = 74 campaigns / 212 cells
```

### 3.2 Balanced-core levels and seeds

Rows 1–8 freeze the following `(grid, connectivity, terrain, obstacle density, agents, dynamic footprint)` tuples:

1. `(64, four-way, uniform, 0.10, 16, 9)`
2. `(64, four-way, weighted, 0.25, 128, 81)`
3. `(64, eight-way, uniform, 0.25, 128, 9)`
4. `(64, eight-way, weighted, 0.10, 16, 81)`
5. `(128, four-way, uniform, 0.25, 16, 81)`
6. `(128, four-way, weighted, 0.10, 128, 9)`
7. `(128, eight-way, uniform, 0.10, 128, 81)`
8. `(128, eight-way, weighted, 0.25, 16, 9)`

Each row has seed replications 1 and 2. The seed is `110000 + 10*row + replication`. For each seed, both `core-rRR-sS-shared` and `core-rRR-sS-hetero` are generated. Shared has one distinct goal; heterogeneous has 4 goals for 16 agents and 16 goals for 128 agents.

### 3.3 Stress levels and seeds

- Grid scale: `32, 64, 128, 256`; ID `grid-scale-gGGG-shared`; seed `120000 + grid`; fixed 64 agents, footprint 25, eight-way weighted terrain, density 0.18.
- Agent scale: `1, 8, 32, 128, 512`; ID `agent-scale-aAAA-shared`; seed `130000 + agents`; fixed 128×128 four-way weighted terrain, density 0.18, footprint 25.
- Dynamic footprint: `1, 9, 25, 81, 225`; ID `dynamic-footprint-fFFF-shared`; seed `140000 + footprint`; fixed 128×128 eight-way weighted terrain, density 0.18, 64 agents.
- Goal count: `2, 4, 8, 16, 32`; ID `goal-count-gGG-hetero`; seed `150000 + goals`; fixed 128×128 eight-way weighted terrain, density 0.18, 128 agents, footprint 25.
- Strict reachability: IDs `reachability-c4-strict-shared` and `reachability-c8-strict-shared`; seeds are derived by the frozen base generator as `160000 + connectivity cardinality`; temporary disconnect/restore semantics remain byte-deterministic.

### 3.4 Canonical identity

A canonical scenario identity is the tuple:

```text
(scenario-matrix ID, generator ID, scenario ID, random seed,
 canonical JSON SHA-256, resolved scenario fingerprint SHA-256)
```

JSON is UTF-8 without BOM, uses the existing strict deterministic schema and invariant formatting, and contains the fully materialized grid, agents, goals, budgets, and ordered dynamic events. Generation must be independent of locale, wall clock, filesystem order, Unity asset GUID order, and platform RNG.

The additive Gate 11R generator facade may invoke the existing deterministic materialization functions whose source hash is frozen in the Gate 11R provenance. It must not read scenario bytes or metadata from the old Gate 11 retained bundle. Re-generation in a separate Unity process must exact-match every produced scenario byte and resolved fingerprint.

### 3.5 Exclusion rules

No scenario or cell is excluded because of runtime magnitude, direction of effect, statistical significance, NoPath frequency, budget overrun, or an unfavorable result. Before Gate 13R, exclusion is allowed only for:

1. a non-deterministic or invalid scenario proven by the Gate 11R verifier;
2. a missing algorithm eligibility contract;
3. a corrupted/hash-mismatched frozen input;
4. a formally versioned user-approved design amendment created before any affected formal data exist.

Such a condition fails Gate 11R; it does not silently remove a row. Warm-up, validation, visualization replay, partial blocks, historical cold-process results, and historical process-reuse results are permanently excluded from future formal inference.

## 4. Campaign identity and Williams mapping

Campaign IDs are canonical:

```text
<scenario-id>--shared
<scenario-id>--per-agent
<scenario-id>--grouped-field
```

Shared campaigns use algorithm order labels `astar-repeated`, `dstar-lite`, `idff`, and `cff` with this four-row balanced Williams square:

| row | position 1 | position 2 | position 3 | position 4 |
|---:|---|---|---|---|
| 0 | A*-R | D* Lite | IDFF | C-FF |
| 1 | D* Lite | C-FF | A*-R | IDFF |
| 2 | C-FF | IDFF | D* Lite | A*-R |
| 3 | IDFF | A*-R | C-FF | D* Lite |

Per-agent heterogeneous campaigns use forward/reverse rows `[A*-R, D* Lite]` and `[D* Lite, A*-R]`. Grouped-field heterogeneous campaigns use `[C-FF, IDFF]` and `[IDFF, C-FF]`. Future total block counts remain multiples of four; two-algorithm rows repeat in a four-block supercycle. For block ordinal `b >= 0`, the shared row is `b mod 4`; the heterogeneous row is `b mod 2`. Position and predecessor are derived only from the selected row. A block may contain no duplicate algorithm.

The Gate 11R campaign profile stores all applicable rows, not a measured block schedule. Gate 12R alone may determine candidate block counts.

## 5. Preregistered analysis contract

Primary families P1–P4 use block-aware paired log contrasts and Holm correction:

- P1: shared-goal `C-FF` versus `A*-R`, `D* Lite`, and `IDFF` on wall-clock planning/repair work.
- P2: grouped-field versus per-agent treatment within heterogeneous scenarios, using eligible algorithm-family contrasts without treating within-process samples as independent.
- P3: `IDFF` versus fresh `C-FF` under dynamic updates, including repair work and structural equivalence/failure status.
- P4: memory/allocation and deadline/budget behavior, retaining failures and overruns in denominators.

Secondary families S1–S5 are factor trends, p95/dispersion, NoPath/failure taxonomy, position/predecessor/process-age diagnostics, and resource scaling. Gate 15R must use block clustering or a mixed/cluster-robust equivalent. Gate 11R freezes the table schema only; it produces no analysis result.

## 6. Playable Unity bundle contract

### 6.1 Coverage and physical layout

```text
Assets/_Scenes/Research/Playable/Gate11R_5pct/v1/
  Scenarios/           53 .unity scenes
  CampaignProfiles/    74 research-only ScriptableObject assets
  AlgorithmPresets/   212 research-only ScriptableObject assets
  Launcher/             1 .unity scene

Research/PlayableExperiments/Gate11R_5pct/v1/
  playable-scene-catalog.json
  campaign-profile-catalog.json
  algorithm-preset-catalog.json
  coverage-manifest.json
```

Every one of the 212 algorithm cells maps bijectively to one preset, one eligible campaign profile, and the canonical scenario scene. Every campaign maps to one scenario and contains only eligible algorithms. Scene, profile, and preset GUIDs and SHA-256 values are recorded after serialization and rechecked in a separate Unity process.

### 6.2 Scene behavior

Opening any generated scenario scene and entering Play mode must work without editing the scene. Each scene contains exactly one `Gate11RPlayableSceneController` bound to one canonical scenario file and its hash. It provides:

- Play/Pause, Single Step, Next Event, Restart, and deterministic event-index seek;
- grid walkability/cost visualization, agent starts, goals, selected path, and dynamic-change highlighting;
- direction/integration visualization for field algorithms using direction glyph design `research-visual-direction-glyph-v1`;
- path and aggregate expanded/repaired metrics for per-agent algorithms;
- campaign, algorithm, Williams row/block ordinal, position, predecessor, scenario fingerprint, and trace hash in the HUD;
- a fixed capture layout and the exact watermark `VISUALIZATION REPLAY — NOT A TIMING RUN`.

The launcher exposes all 74 profiles and 212 presets, resolves the mapped scenario, and loads the selected scene. Replay controls operate on deterministic simulation events, never wall time. Visualization output is descriptive supplemental evidence only and cannot be used as timing, frame-time, statistical, or formal sample evidence.

### 6.3 Timing isolation

The Gate 10R/Gate 12R/Gate 13R headless timing runner must never load the generated Playable scenes, controller, profiles, or presets. All Playable assets live under the dedicated research-only asset root. The formal scenario JSON is the only shared scientific input; visualization state and OBS state are not part of formal timing.

## 7. Gate 12R pilot anchors frozen for downstream use

Gate 11R records, but does not execute, these anchors:

- Shared: `core-r01-s1-shared`, `core-r07-s2-shared`, `grid-scale-g256-shared`, `agent-scale-a512-shared`, `dynamic-footprint-f225-shared`, `reachability-c8-strict-shared`.
- Heterogeneous, each in both cohorts: `core-r01-s1-hetero`, `core-r07-s2-hetero`, `goal-count-g32-hetero`.

This is 12 pilot campaign conditions. Gate 12R remains unauthorized.

## 8. Gate 11R completion condition

Gate 11R passes only if the frozen test design passes in order, all 53 scenarios exact-regenerate, all 74 profiles and 212 presets have complete/bijective coverage, all 53 scenes and the launcher load with valid controller bindings, all provenance and protected-root hashes match, and the validation-only final audit finds Gate 12R/Gate 13R roots absent. Success writes `GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION` and stops.
