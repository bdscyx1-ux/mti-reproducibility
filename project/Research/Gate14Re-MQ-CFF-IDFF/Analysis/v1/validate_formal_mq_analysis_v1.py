#!/usr/bin/env python3
"""Outcome-free static and synthetic validation for the formal MQ analyzer."""

from __future__ import annotations

import ast
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any


EXPECTED_ANALYZER_SHA256 = "c313fc16f9a4659f7e507af90fc822dff42d8319a4033cf5e9d5f492ef604748"
EXPECTED_CONTRACT_SHA256 = "940025bca8952568f68dd08fa333b0bac395a0203da98ddd5f61f87a6dcb6f59"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_analyzer(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("gate14re_mq_analyzer_v1", path)
    require(spec is not None and spec.loader is not None, "unable to load analyzer module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def synthetic_data(analyzer: Any) -> dict[str, dict[str, dict[str, float]]]:
    data: dict[str, dict[str, dict[str, float]]] = {}
    for block in range(analyzer.EXPECTED_BLOCKS):
        block_id = f"SYNTH-B{block + 1:03d}"
        data[block_id] = {}
        block_jitter = (block - 17.5) * 0.0005
        for slot, base in (("OPAQUE-A", 12.0), ("OPAQUE-B", 15.0)):
            slot_shift = 0.0 if slot == "OPAQUE-A" else 0.02
            cells: dict[str, float] = {}
            cells["ST-DIRECT-LARGE-L3"] = base * math.exp(block_jitter)
            cells["ST-DIRECT-HIGH-FREQUENCY"] = base * 0.92 * math.exp(block_jitter)
            for worker in (1, 2, 4, 8):
                cells[f"MQ-LARGE-L3-W{worker}"] = base * 1.03 * math.exp((-0.13 - slot_shift) * math.log2(worker) + block_jitter)
                cells[f"MQ-HIGH-FREQUENCY-W{worker}"] = base * 0.95 * math.exp((-0.12 - slot_shift) * math.log2(worker) + block_jitter)
            cells["MQ-DUAL-CCD-W8-4PLUS4"] = base * 0.73 * math.exp(block_jitter)
            cells["MQ-DUAL-CCD-W16-8PLUS8"] = cells["MQ-DUAL-CCD-W8-4PLUS4"] * math.exp(-0.11 - slot_shift)
            data[block_id][slot] = cells
    return data


def main() -> int:
    here = Path(__file__).resolve().parent
    analyzer_path = here / "analyze_formal_mq_v1.py"
    contract_path = here / "formal-mq-analysis-contract.v1.json"
    require(sha256_file(analyzer_path) == EXPECTED_ANALYZER_SHA256, "analyzer hash mismatch")
    require(sha256_file(contract_path) == EXPECTED_CONTRACT_SHA256, "contract hash mismatch")

    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    require(contract["status"] == "FROZEN_PRE_OUTCOME_FORMAL_ANALYSIS_IMPLEMENTATION", "contract status")
    require(contract["independentUnit"]["matchedBlocks"] == 36, "contract B")
    require(contract["primaryInference"]["family"] == ["P1", "P2", "P3", "P4"], "primary family")
    require(contract["keySecondaryInference"]["family"] == ["S1", "S2"], "secondary family")
    require(contract["primaryInference"]["multiplicity"].startswith("Holm"), "primary multiplicity")
    require(contract["sensitivityAnalyses"]["studentizedMatchedBlockBootstrap"]["seed"] == 141420274, "bootstrap seed")
    require(contract["integrityAndExecution"]["parseLaneObservationValues"] is False, "lane-value boundary")
    require(contract["authorizationBoundary"]["formalStAuthorized"] is False, "ST boundary")
    require(contract["authorizationBoundary"]["mtAuthorized"] is False, "MT boundary")
    require(contract["authorizationBoundary"]["algorithmRankingOrWinnerAuthorized"] is False, "ranking boundary")

    source = analyzer_path.read_text(encoding="utf-8")
    tree = ast.parse(source)
    string_literals = {
        node.value
        for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    require("formal-lanes.raw.v2.jsonl" not in string_literals, "analyzer contains lane-observation filename")
    require("formal-batch.raw.v2.json" in string_literals, "analyzer lacks frozen batch endpoint filename")
    function_names = {node.name for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    for required_function in (
        "verify_acquisition_manifest",
        "validate_collection_terminal",
        "equal_weight_slope",
        "one_sample_statistics",
        "holm_adjust",
        "exact_signed_rank_lower_p",
        "studentized_bootstrap",
        "leave_one_out",
        "formal_run",
    ):
        require(required_function in function_names, f"missing function {required_function}")

    analyzer = load_analyzer(analyzer_path)
    self_test = analyzer.self_test()
    require(self_test["status"] == "PASS", "embedded self-test failed")
    identity = {"OPAQUE-A": "C-FF", "OPAQUE-B": "IDFF"}
    data = synthetic_data(analyzer)
    block_rows, block_ids, values = analyzer.compute_block_estimands(data, identity)
    require(len(block_rows) == 36 * 6, "synthetic block-estimand cardinality")
    require(len(block_ids) == 36, "synthetic block count")
    results = analyzer.apply_inference(values, identity)
    require(results["primaryGateForSecondariesOpen"] is True, "synthetic primary gate should open")
    require(all(row.get("confirmatoryClaimPassed") is True for row in results["results"][:4]), "synthetic primary claims")
    require(all(row.get("keySecondaryClaimPassed") is True for row in results["results"][4:]), "synthetic secondary claims")
    condition_summary = analyzer.condition_summaries(data, identity)
    require(len(condition_summary["rows"]) == 24, "synthetic condition summaries")
    exploratory = analyzer.descriptive_exploratory(data, values, block_ids, identity)
    require(len(exploratory["stDirectVersusMqW1"]) == 4, "synthetic overhead rows")
    require(len(exploratory["crossAlgorithmInteractions"]) == 3, "synthetic cross rows")
    small_matrix = analyzer.np.asarray(
        [[values[hypothesis_id][index] for hypothesis_id in analyzer.ALL_HYPOTHESIS_IDS] for index in range(36)],
        dtype=analyzer.np.float64,
    )
    bootstrap = analyzer.studentized_bootstrap(small_matrix, 2_000, 141420274, analyzer.ALL_HYPOTHESIS_IDS)
    require(set(bootstrap["columns"]) == set(analyzer.ALL_HYPOTHESIS_IDS), "synthetic bootstrap columns")

    receipt = {
        "schema": "gate14re-mq-formal-analysis-independent-validation-v1",
        "status": "PASS_OUTCOME_FREE_STATIC_AND_SYNTHETIC_VALIDATION",
        "analyzerSha256": EXPECTED_ANALYZER_SHA256,
        "analysisContractSha256": EXPECTED_CONTRACT_SHA256,
        "checks": {
            "contractBindings": True,
            "noLaneObservationFilenameInAnalyzerAst": True,
            "batchEndpointFilenamePresent": True,
            "requiredFunctionsPresent": True,
            "embeddedKnownAnswerTests": True,
            "syntheticBlockEstimands": len(block_rows),
            "syntheticPrimaryGateOpen": True,
            "syntheticPrimaryClaimsPassed": 4,
            "syntheticKeySecondaryClaimsPassed": 2,
            "syntheticConditionSummaryRows": len(condition_summary["rows"]),
            "syntheticOverheadRows": len(exploratory["stDirectVersusMqW1"]),
            "syntheticCrossAlgorithmRows": len(exploratory["crossAlgorithmInteractions"]),
            "syntheticBootstrapDraws": 2_000,
        },
        "formalOutcomeFilesOpenedOrParsed": False,
        "formalAnalysisStarted": False,
        "formalStStarted": False,
        "mtStarted": False,
    }
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
