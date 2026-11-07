# C-FF/IDFF Managed Multi-Query Scalability Supplement — Material Passport

## Status

`PROSPECTIVE_TECHNICAL_QUALIFICATION_AUTHORIZED_FORMAL_COLLECTION_NOT_YET_FROZEN`

This is an independent multi-query (MQ) study. It does not amend, replace, merge
with, or reinterpret the six-algorithm formal ST study, its package, or its data.
It is also not the movement-transfer (MT) study.

## Scientific scope

The study asks how a managed fixed worker pool changes throughput, latency,
resource use, and scaling for two flow-field algorithms:

- corrected full-recompute flow field (`C-FF`);
- incremental dynamic flow field (`IDFF`).

The intended claims are limited to full recomputation versus incremental repair
within this managed MQ implementation and the frozen host-topology conditions.
They cannot be generalized to the other four ST algorithms and cannot establish
a six-algorithm winner.

## Evidence stages

1. `Gate13R-MQ-CFF-IDFF`: correctness, oracle agreement, determinism, worker-count
   invariance, CPU affinity, private-state isolation, ordinal restoration, and
   fail-closed behavior.
2. `Gate14Re-MQ-CFF-IDFF`: identity-blind engineering qualification and prospective
   resource planning.
3. Formal MQ design freeze: estimands, minimum important effect, power, sample
   size, multiplicity, stopping, implementation, schedule, and runtime bindings.
4. Formal MQ collection and formal analysis, only after stage 3 is complete.

Technical qualification timings are engineering evidence only. They are not
formal observations and are ineligible for algorithm-effect claims.

## Current authorization boundary

The user authorized the previously discussed C-FF/IDFF MQ experiment to proceed.
That authorization is sufficient for implementation, compilation, Gate13R-MQ,
and identity-blind Gate14Re-MQ preparation. The formal MQ effect threshold,
power target, candidate sample sizes, multiplicity rule, and stopping rule have
not yet been frozen and will not be invented or inherited from formal ST.

