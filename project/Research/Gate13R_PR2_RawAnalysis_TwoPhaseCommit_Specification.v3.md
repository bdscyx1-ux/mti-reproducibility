# Gate 13R-PR2 attempt 4 blockwise raw / analysis commit specification v3

## Scope

This prospective specification applies only to formal attempt 4. It leaves the frozen scientific design unchanged and supersedes the attempt-3-only acquisition-failure disposition in v1/v2. Attempt 3 remains historical and is never merged into attempt 4.

## Phase A0 — immutable attempt commit

Before ordinal 1, the launcher commits one attempt-4 execution receipt, the frozen schedule/config hashes, the fresh `v4` root, the blockwise-eligibility amendment, the bounded-resume contract, the runtime identity, and the passed prelaunch audit. No measured output may predate this commit.

## Phase A1 — blockwise acquisition commits

Each schedule row is executed in one fresh Unity process. After every complete block, the orchestrator validates all samples, identities, order, memory hard gates, files and hashes, then creates exactly one append-only `block-eligibility-commits/pNNNNNN.json` record.

The commit is the durable inclusion boundary. It declares the completed block formally eligible for a later, separately authorized analysis even if a later block or control-plane process fails. Inclusion is automatic and result-independent. A partial block has no commit and no formal eligibility.

Cross-cohort heterogeneous inference still requires both eligible halves of the matched superblock. Full matrix-level claims still require their originally specified coverage. Failure-truncated eligible blocks remain formal observations but cannot be relabeled as a complete design.

## Phase A2 — bounded automatic resume

The supervisor may perform at most three automatic resumes. The append-only block commits, not mutable status, define the frontier. A resume may start only at the first ordinal after the contiguous commit prefix. A complete but uncommitted next block may be promoted only after exact plan, receipt, PID/start time, manifest, summary, sample and hash validation and proof that no later output exists.

Partial or ambiguous next-block evidence, a wrapper nonzero exit, scientific/structural/memory/hash failure, duplicate identity, schedule drift, storage failure, Unity concurrency, or a repeated resume failure signature fails closed. No automatic measured retry, deletion, skip, replacement, top-up, reorder, cross-attempt merge or process reuse is allowed.

Mutable status publication uses 0/2/5-second retries and immutable failure sidecars. Status publication is operational metadata and cannot revoke an already committed block.

## Phase A3 — full raw commit

If all 3,552 blocks / 10,176 samples are committed, the auditor verifies all block commits and payload files, freezes the campaigns tree read-only, and writes the canonical raw tree hash and final audit. Raw-commit implementation failures may be retried without Unity rerun under the existing bounded audit-recovery rule.

If acquisition terminates early, the orchestrator writes a partial formal-eligibility manifest containing every committed block. Those blocks retain formal eligibility; the attempt remains incomplete.

## Phase B — separate analysis authorization

This specification does not authorize statistical analysis. Any later Phase-B authorization must bind either the complete raw freeze receipt or, after terminal failure, the failure-truncated eligibility manifest; include every eligible block applicable to each estimand; report actual schedule coverage and missingness; and preserve the original multiplicity rules where the corresponding estimand remains identifiable. Gate 14R and Playable/OBS timing remain outside scope.
