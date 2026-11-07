#!/usr/bin/env python3
"""Versioned repair of the FD1 enforcement-boundary source-evidence check."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
from typing import Any


V3_PATH = Path(__file__).with_name("Analyze-Gate13RPR2Attempt2FailureV3.py")
SPEC = importlib.util.spec_from_file_location("gate13r_pr2_fd1_v3_core", V3_PATH)
V3 = importlib.util.module_from_spec(SPEC)
if SPEC.loader is None:
    raise RuntimeError("Unable to load the preserved V3 analyzer")
SPEC.loader.exec_module(V3)


def extract_enforcement_source_evidence_v4(command_path: Path) -> dict[str, Any]:
    source = command_path.read_text(encoding="utf-8-sig")
    required_fragments = [
        'AddMemoryPolicyFixture(tests, "nonfinal-block-above-256-deferred"',
        'AddMemoryPolicyFixture(tests, "final-working-above-512-fail"',
        'AddMemoryPolicyFixture(tests, "final-private-above-512-fail"',
        "bool finalSampleInBlock = index == plan.entries.Length - 1;",
        "evaluation.finalSampleInBlock && !evaluation.blockManagedHardLimitPassedAtSampleBoundary",
        "evaluation.finalSampleInBlock && !evaluation.blockWorkingSetHardLimitPassedAtSampleBoundary",
        "evaluation.finalSampleInBlock && !evaluation.blockPrivateMemoryHardLimitPassedAtSampleBoundary",
        "if (evaluation.finalSampleInBlock && !evaluation.blockWorkingSetHardLimitPassedAtSampleBoundary)",
        "if (evaluation.finalSampleInBlock && !evaluation.blockPrivateMemoryHardLimitPassedAtSampleBoundary)",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in source]
    V3.require(not missing, f"Frozen command no longer proves deferred final-boundary enforcement: {missing}")
    return {
        "relativePath": command_path.relative_to(V3.PROJECT).as_posix(),
        "sha256": V3.CORE.sha256_file(command_path),
        "utf8TextSha256": V3.sha256_text(source),
        "requiredSemanticFragmentsPresent": True,
        "explicitNonFinalManagedFixturePresent": True,
        "explicitFinalNativeFixturesPresent": True,
        "productionFinalBoundaryConditionsPresent": True,
        "interpretation": (
            "All block-limit flags are measured at each sample boundary. Production hard-fail predicates for managed, "
            "working-set, and private-memory block limits are each conjunctive with finalSampleInBlock; therefore a "
            "non-final native exceedance is recorded but not yet enforced."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--failed-root", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--timestamp", required=True)
    V3.extract_enforcement_source_evidence = extract_enforcement_source_evidence_v4
    V3.analyze(parser.parse_args())


if __name__ == "__main__":
    main()
