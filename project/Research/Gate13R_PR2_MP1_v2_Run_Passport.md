---
passport_id: gate13r-pr2-mp1-v2
study: Gate 13R-PR2 MP1 attempt 2 / v2
mode: run
status: completed-readiness-policy-recommended-unfrozen
formal_campaign_authorized: false
formal_statistical_analysis_authorized: false
gate14r_authorized: false
---

# Gate 13R-PR2-MP1 attempt 2 / v2 Material Passport

## Authorized objective

Repair only the checkpoint state machine and cross-runtime path-safe atomic replacement defects in new v2 artifacts, rerun the complete pre-pilot validation contract, then run at most one fresh NON-FORMAL balanced targeted memory pilot if and only if every hard gate passes.

## Frozen scientific contract

- Four canonical shared-goal scales: g032, g064, g128, g256.
- Measured blocks: 16 / 16 / 16 / 48; total 96 fresh Unity block processes.
- Four algorithm samples per complete Williams block; total 384 samples.
- Strict serial; zero warm-up processes; complete reset per sample.
- Stage-separated PSAPI/CIM, managed-memory and host-safety telemetry.
- Two-stage commit: immutable Phase-A raw data, then versioned read-only diagnostic analysis.
- NON-FORMAL / MEMORY-DIAGNOSTIC-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS.

## Immutable evidence

- Pilot v1 remains failed with zero measured blocks and is never retried, resumed, topped up, merged, or analyzed as a memory-policy result.
- Gate 13R-PR2 formal attempt 2 remains immutable and excluded.
- Gate 13R-PR2 formal attempt 3, formal statistical analysis, and Gate 14R are not authorized.

## Stage gates

1. Pre-write preservation audit.
2. v2 state-machine and path-safe atomic persistence implementation.
3. Cross-runtime parser/binding/unit/fixture validation.
4. Full scientific implementation validation, Unity compile/self-test, telemetry, positive and negative block tests, lock hygiene, hashes and final pre-pilot audit.
5. One-shot measured acquisition only after all prior gates pass.
6. Phase-A raw-data commit and immutable freeze.
7. Versioned read-only diagnostic analysis; ordinary analysis bugs never cause Unity reruns.

## Stop rules

- Before measured acquisition, implementation defects may be fixed only in new versioned v2 validation attempts.
- After measured acquisition starts, any acquisition hard failure stops the attempt with durable evidence; no automatic retry/resume/top-up/merge.
- Analysis failures may be repaired only in a new analysis attempt against the same immutable Phase-A raw tree.

## Completion record

- Pre-pilot validation attempt 6 passed 34/34 ordered steps.
- The sole measured v2 acquisition completed 96/96 fresh blocks and 384/384 samples without retry, resume, top-up, or merge.
- Phase A froze 3,360 raw files / 2,607,785,161 bytes / canonical tree SHA-256 `13dd5c30cd016d42e80f472c962d09f89f4d0fb6714d68228e2c657f6c80da93`.
- Phase B analysis attempt 1 passed against the immutable raw tree with 1,824 stage records.
- The forward layered memory policy is recommended but remains unfrozen pending a separate MP2 non-executing authorization.
- Formal attempt 3, formal statistical analysis, and Gate 14R remain unauthorized.
