---
passport_id: gate13r-pr2-mp2
study: Gate 13R-PR2 MP2 non-executing memory-policy amendment and attempt-3 readiness
mode: run
status: non-executing-readiness-passed
formal_attempt3_measured_campaign_authorized: false
formal_attempt3_root_creation_authorized: false
formal_attempt3_receipt_creation_authorized: false
formal_statistical_analysis_authorized: false
gate14r_authorized: false
---

# Gate 13R-PR2-MP2 Material Passport

## Authorized objective

Freeze the prospective layered, scenario-size-aware memory policy before any future formal observations; implement a versioned candidate attempt-3 config, schedule policy overlay, execution adapter and validation contract; then complete validation-only readiness without creating or running a formal attempt.

## Frozen policy

- Native residency metric: `max(working-set delta, private-memory delta)` from the block baseline, evaluated at each completed-sample after-cleanup boundary and at the post-block boundary.
- Canonical maximum grid dimension `<=128`: 512 MiB advisory, 640 MiB hard.
- Canonical maximum grid dimension `==256`: 640 MiB advisory, 768 MiB hard.
- Unknown or ambiguous dimension fails configuration before measured launch.
- Managed memory after forced cleanup: 128 MiB alert, 256 MiB sample and block emergency hard stop.
- Host safety: 4 GiB absolute native, 2 GiB relative native growth, 8 GiB available-memory floor, and fail-closed telemetry overflow/unverifiable sustained growth.
- Raw-after-workload transient crossings remain diagnostic unless a host-emergency rule fails.
- Crossings are whole-block/process eligibility events and cannot be attributed to the final-position algorithm.

## Frozen experimental contract

- 74 campaigns, S48/H48, 3,552 fresh Unity block processes and 10,176 samples.
- Strict serial; one complete Williams block maximum per fresh Unity process; complete reset per sample.
- Schedule order, run IDs, Williams balance, 1,008 matched superblocks and heterogeneous AB/BA 24/24 remain byte-bound to the active PR2 v2 schedule.
- Two-stage raw/analysis commit and no automatic retry, resume, top-up or merge remain unchanged.

## Immutable upstream evidence

- MP1 v2 Phase A: 3,360 files / 2,607,785,161 bytes / tree SHA-256 `13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`.
- MP1 v2 Phase B analysis attempt 1 remains read-only and diagnostic only.
- MP1 pilot v1 and formal attempt 2 retain their frozen identities and exclusions.
- Gate 10R/11R/12R/PR1/PR1B/PR2/FD1 evidence, original game scripts, original scenes and original project archives remain unchanged.

## Stage gates

1. Pre-write read-only preservation audit.
2. Versioned policy registry, scenario mapping, schedule overlay, schema, amendment and candidate config generation.
3. Cross-runtime parser/binding, deterministic regeneration and synthetic boundary tests.
4. Isolated Unity compile/self-test plus positive/expected-negative/telemetry/persistence/lock validation-only fixtures.
5. Post-validation upstream invariance and formal-attempt-3 absence audit.
6. Non-executing readiness checkpoint, plan update and next authorization prompt.

## Stop rules

- Validation-only implementation defects may be repaired only in new versioned attempts with preserved failure evidence.
- Thresholds, schedule, algorithms, reset, correctness, telemetry and two-stage semantics cannot be weakened to obtain a pass.
- Formal attempt 3 measured execution, formal root/receipt creation, formal analysis and Gate 14R are outside this authorization.

## Terminal status

- Validation attempts 1–3 failed closed and remain preserved as independent versioned evidence.
- Validation attempt 4 passed the complete validation-only contract.
- The prospective scenario-size-aware memory policy and active candidate V4 artifacts are frozen for review.
- Formal attempt 3 remains unstarted and requires a separate user authorization.
