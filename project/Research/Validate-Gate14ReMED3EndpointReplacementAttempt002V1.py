#!/usr/bin/env python3
"""Read-only validator for Gate14Re-ME D3 endpoint replacement attempt-002."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess
import sys


EXPECTED_ROOT = Path("H:/DDM_Final_Project").resolve()
AUTHORIZATION_ID = "gate14re-me-d3-endpoint-replacement-attempt-002"

EXPECTED_HASHES = {
    "authorization": "5ce2907d37660129ce6751a54c6c48a660965bb8007a7f3ab21f8c1bd905e583",
    "plan": "4981b37f8a20fe705e857ffe648dd412e6cfbbdaa6ff5497568d9bcead7d72df",
    "prospective_contract": "5960c63ccb0468bf84802f649326d10edea0bd0527ada0c2fdf7342d26f4604d",
    "preexecution": "7d004248125a5068210d8c691cad3d687ac6058e78ea5003596e2d24feed19d1",
    "folder_meta": "383a08462d056e2a3871deab3d67251dec1f733625b04b9bae65c0a0e10c218e",
    "source": "64e9ae20fdc5f03c9f737bc42a655f7488c359e3525b66f288f6ca963770a2ca",
    "source_meta": "a9604ec92d4a89edee2803b20b52cf7603045dd2650b89bbcc0bd883d90723cd",
    "harness": "d05c2939ecd73d3582c9800e0f2a576260b1aa230400914668c4516e7ddc62fa",
    "harness_meta": "9a918a9b9cc5196f8a100f7e2eccfc0cf9db0452baff6789d26deddbd36a106f",
    "known_answer": "e8b16d76e339c87fe5485edcd68c8a6518ce40a5e49acf15b6e8cc6dadfc65aa",
    "unity_log": "7a52346f7fc09a9ee12869cb5b4d445b1b8d9e7d0f30b7ecb17fade00b834d7b",
    "process_receipt": "3565571501f9b9a6afbb6fb78b4c0b54ce54bc91595de4d82238b9be7cd4d311",
    "final_contract": "e402dfc90362a3ac07f5342d218f19c67d31d46f82bec584d5d817fbccb9f0bf",
    "source_manifest": "4ed57ddfbfb2d0b6b73e2b8c0480c0d2fce575505c580afe0efc1af622ddea0a",
    "status_v6": "06043046e01640f0f8c7b54cd7095a4cf704bece676c952c65a653b17e9c3bc1",
    "fairness_binding": "1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71",
    "load_runner_v1": "7bb9237e529f511ad12fcfcb8374db02818977092c3680b287aacc817d182033",
    "output_schema_v1": "ed7d7bddf8e1da647a6085aa8e717d4ee0578ceff3fa7844dbd05c4e17aaea1c",
    "instrument_contract_v1": "7515851e9b447c0e17c580e0cbad86186d156f606cb8828616cd7f4f50ea4503",
    "prior_runtime_failure": "8a508261f9c779ff3d3e3481d5eaf28ebc9d4c513cb69fdc8d30456b3ad9b49a",
    "prior_runtime_freeze": "042f3ca2d07b4b78db04a7b272929f6052cc51739c0aeeaa4e6998b75f5554c8",
    "prior_amendment_failure": "abffc0f216a18666ffb046ab0d7ebe9058e54a15cb07d3ecadd5715352c91ee1",
    "prior_amendment_freeze": "4c2671b3158e9aaa1276e133778850adf44c5ccde8734110e734548abbb21074",
    "prior_status_v5": "66b6a3adbd2c889d19994fa4f3b2a1e5f69cbe60bddb81040b713e3013c3dc80",
    "unity": "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf",
}

ALGORITHM_HASHES = {
    "Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs": "a54bb43ed906c856e3d45493c4d3d10ff1b6f1e0ccda1a9f25ea774908b9c778",
    "Assets/_Scripts/Research/Algorithms/BidirectionalAStarRepeatedPlanner.cs": "82316036aba90be69ca746288798bac1789cdb09afa65cf9ad4180975d1f947e",
    "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs": "ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f",
    "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs": "10686f9bf5b36ec06e8d5e98a7c54f8bdcc5a1c0d0664cb9a3eed6a806bc52c8",
    "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs": "bdaa52bc93950ea6a1737a7629ec6ceda60370f6ebc489deb166e2eddc51f3e1",
    "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs": "63aa0792bd0935d1e98158278580cf2ece5980cf3e52ef7e9adb16bbcddc7638",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def is_read_only(path: Path) -> bool:
    attributes = path.stat().st_file_attributes
    return bool(attributes & stat.FILE_ATTRIBUTE_READONLY)


def unity_process_count() -> int:
    executable = Path("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
    completed = subprocess.run(
        [
            str(executable),
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return int(completed.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args()
    root = Path(args.project_root).resolve()

    checks_passed = 0
    failures: list[str] = []

    def check(condition: bool, label: str) -> None:
        nonlocal checks_passed
        if condition:
            checks_passed += 1
        else:
            failures.append(label)

    check(root == EXPECTED_ROOT, "project root mismatch")

    paths = {
        "authorization": root / "Research/Gate14Re-ME/Gate14Re_ME_D3_Endpoint_Replacement_Authorization.v1.json",
        "plan": root / "Research/Gate14Re-ME/Gate14Re_ME_D3_Endpoint_Replacement_Plan.v1.md",
        "prospective_contract": root / "Research/Gate14Re-ME/Execution/v2/d3-managed-heap-occupancy-contract.prospective.v1.json",
        "preexecution": root / "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/preexecution-manifest.v1.json",
        "folder_meta": root / "Assets/_Scripts/Research/Gate14ReME/v2.meta",
        "source": root / "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs",
        "source_meta": root / "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs.meta",
        "harness": root / "Assets/_Scripts/Research/Editor/Gate14ReMED3EndpointReplacementRunnerV1.cs",
        "harness_meta": root / "Assets/_Scripts/Research/Editor/Gate14ReMED3EndpointReplacementRunnerV1.cs.meta",
        "known_answer": root / "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/d3-known-answer/d3-known-answer-receipt.v1.json",
        "unity_log": root / "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/unity-d3-endpoint-known-answer.log",
        "process_receipt": root / "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/unity-process-receipt.v1.json",
        "final_contract": root / "Research/Gate14Re-ME/Execution/v2/load-qualification-instrument-contract.v2.json",
        "source_manifest": root / "Research/Verification/Gate14Re-ME/d3-endpoint-replacement-attempt-002/source-freeze-manifest.v1.json",
        "status_v6": root / "Research/Gate14Re-ME/Gate14Re_ME_Status.v6.json",
        "fairness_binding": root / "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json",
        "load_runner_v1": root / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs",
        "output_schema_v1": root / "Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json",
        "instrument_contract_v1": root / "Research/Gate14Re-ME/Execution/v1/load-qualification-instrument-contract.v1.json",
        "prior_runtime_failure": root / "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/failure-receipt.v1.json",
        "prior_runtime_freeze": root / "Research/Verification/Gate14Re-ME/runtime-qualification-attempt-001/freeze-receipt.v1.json",
        "prior_amendment_failure": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/failure-receipt.v1.json",
        "prior_amendment_freeze": root / "Research/Verification/Gate14Re-ME/d3-runtime-compatibility-amendment-attempt-001/freeze-receipt.v1.json",
        "prior_status_v5": root / "Research/Gate14Re-ME/Gate14Re_ME_Status.v5.json",
        "unity": Path("H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe"),
    }

    for name, path in paths.items():
        check(path.is_file(), f"missing {name}: {path}")
        if path.is_file():
            check(sha256(path) == EXPECTED_HASHES[name], f"hash mismatch for {name}")
            if name != "unity":
                check(is_read_only(path), f"not read-only: {name}")

    authorization = read_json(paths["authorization"])
    check(authorization.get("schema") == "gate14re-me-d3-endpoint-replacement-authorization-v1", "authorization schema")
    check(authorization.get("authorizationId") == AUTHORIZATION_ID, "authorization id")
    check(authorization.get("status") == "AUTHORIZED_D3_ENDPOINT_REPLACEMENT_ONLY", "authorization status")
    check(all(value is True for value in authorization.get("authorizedScope", {}).values()), "authorized scope incomplete")
    check(all(value is False for value in authorization.get("prohibitedScope", {}).values()), "prohibited scope enabled")
    design = authorization.get("knownAnswerDesign", {})
    check(design.get("negativeControlPairs") == 64, "negative pair count changed")
    check(design.get("negativeControlMaximumAbsoluteDeltaBytes") == 65536, "negative threshold changed")
    check(design.get("positiveControlBytes") == [8388608, 33554432], "positive sizes changed")
    check(design.get("positiveControlMinimumObservedFractionNumerator") == 9, "positive numerator changed")
    check(design.get("positiveControlMinimumObservedFractionDenominator") == 10, "positive denominator changed")
    check(design.get("scaleSeparationMinimumBytes") == 22649242, "scale threshold changed")
    check(design.get("reclamationControlBytes") == 16777216, "reclamation size changed")
    check(design.get("reclamationMinimumAllocationDeltaBytes") == 15099495, "reclamation allocation threshold changed")
    check(design.get("reclamationMinimumRecoveredBytes") == 13421773, "reclamation recovery threshold changed")
    check(design.get("postReclamationBaselineAllowanceBytes") == 2097152, "reclamation allowance changed")
    check(design.get("thresholdsMayBeRelaxedAfterExecution") is False, "post-execution relaxation enabled")

    receipt = read_json(paths["known_answer"])
    check(receipt.get("schema") == "gate14re-me-d3-endpoint-replacement-known-answer-receipt-v1", "known-answer schema")
    check(receipt.get("authorizationId") == AUTHORIZATION_ID, "known-answer authorization")
    check(receipt.get("status") == "PASS_D3_MANAGED_HEAP_OCCUPANCY_KNOWN_ANSWER", "known-answer status")
    check(receipt.get("counterId") == "GC.GetTotalMemory(false)-managed-heap-occupancy-v1", "counter id")
    check(receipt.get("primaryRawField") == "eventGroupManagedHeapBytesEnd", "primary raw field")
    check(receipt.get("cumulativeAllocationCounter") is False, "cumulative-allocation claim present")
    check(receipt.get("nativeAllocationsIncluded") is False, "native-allocation claim present")
    check(receipt.get("negativeSignedDeltaAllowed") is True, "signed-negative policy missing")
    check(receipt.get("clampOrCensorAllowed") is False, "clamp/censor enabled")
    negatives = receipt.get("negativeControls", [])
    check(len(negatives) == 64, "negative-control cardinality")
    check(all(row.get("passed") is True for row in negatives), "negative-control row failed")
    check(all(row.get("absoluteDeltaBytes", 65537) <= 65536 for row in negatives), "negative-control threshold breach")
    check(receipt.get("negativeControlObservedMaximumAbsoluteDeltaBytes") == max(row["absoluteDeltaBytes"] for row in negatives), "negative maximum mismatch")
    check(receipt.get("negativeControlPassed") is True, "negative control not passed")
    positives = receipt.get("positiveControls", [])
    check(len(positives) == 2, "positive-control cardinality")
    if len(positives) == 2:
        check(positives[0].get("requestedBytes") == 8388608 and positives[0].get("minimumDeltaBytes") == 7549748, "small positive contract")
        check(positives[0].get("signedDeltaBytes", 0) >= 7549748 and positives[0].get("passed") is True, "small positive response")
        check(positives[1].get("requestedBytes") == 33554432 and positives[1].get("minimumDeltaBytes") == 30198989, "large positive contract")
        check(positives[1].get("signedDeltaBytes", 0) >= 30198989 and positives[1].get("passed") is True, "large positive response")
        check(receipt.get("observedScaleSeparationBytes") == positives[1]["signedDeltaBytes"] - positives[0]["signedDeltaBytes"], "scale arithmetic")
    check(receipt.get("requiredScaleSeparationBytes") == 22649242, "required scale separation")
    check(receipt.get("observedScaleSeparationBytes", 0) >= 22649242, "observed scale separation")
    check(receipt.get("positiveControlsPassed") is True, "positive controls not passed")
    check(receipt.get("scaleSeparationPassed") is True, "scale separation not passed")
    reclamation = receipt.get("reclamationControl", {})
    check(reclamation.get("requestedBytes") == 16777216, "reclamation request")
    check(reclamation.get("allocationSignedDeltaBytes", 0) >= 15099495, "reclamation allocation response")
    check(reclamation.get("recoveredBytes", 0) >= 13421773, "reclamation recovery response")
    check(reclamation.get("afterReclamationBytes", 2**63) <= reclamation.get("baselineBytes", 0) + 2097152, "reclamation baseline return")
    check(reclamation.get("passed") is True and receipt.get("reclamationControlPassed") is True, "reclamation control not passed")
    for key in ("plannerConstructed", "algorithmLaneExecuted", "dataExporterKnownAnswerRun", "formalAnalysisPerformed", "rankingOrWinnerComputed"):
        check(receipt.get(key) is False, f"evidence boundary true: {key}")
    for key in ("qualificationScheduleRows", "qualificationInputCount", "anonymousIdentityMappingCount", "qualificationObservationCount", "formalObservationCount"):
        check(receipt.get(key) == 0, f"evidence boundary nonzero: {key}")
    check(receipt.get("processId") == 55648, "Unity process id")
    check(receipt.get("commandLineSha256") == "bfa3a577214231f8318bc75b83ca23dd8fd305b1fd0801cfd632666cf2a0d7b2", "in-process command line hash")

    process = read_json(paths["process_receipt"])
    check(process.get("status") == "UNITY_PROCESS_EXITED_ZERO_AFTER_FINAL_SUCCESSFUL_RECOMPILE", "process status")
    check(process.get("process", {}).get("exitCode") == 0, "process exit code")
    check(process.get("process", {}).get("hardTimeoutTriggered") is False, "hard timeout triggered")
    check(process.get("process", {}).get("automaticRetryPerformed") is False, "automatic retry occurred")
    sequence = process.get("compilationSequence", {})
    check(sequence.get("initialStaleGraphDiagnosticObserved") is True, "stale graph diagnostic not recorded")
    check(sequence.get("sameProcessRequestedAdditionalGraphRun") is True, "additional graph run not recorded")
    check(sequence.get("finalTundraBuildSuccessObservedAfterInitialDiagnostic") is True, "final build success not recorded")
    check(sequence.get("finalAssemblyReloadSucceeded") is True, "final assembly reload not recorded")
    check(sequence.get("unresolvedFinalCompilerErrors") == 0, "unresolved final compiler errors")

    log_text = paths["unity_log"].read_text(encoding="utf-8", errors="replace")
    stale_token = "error CS2001: Source file 'H:\\DDM_Final_Project\\Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEAllocationCounterV2.cs' could not be found."
    additional_token = "*** Tundra requires additional run"
    success_token = "*** Tundra build success"
    source_import_token = "Start importing Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEManagedHeapOccupancyV1.cs"
    harness_import_token = "Start importing Assets/_Scripts/Research/Editor/Gate14ReMED3EndpointReplacementRunnerV1.cs"
    reload_token = "Mono: successfully reloaded assembly"
    stale_position = log_text.find(stale_token)
    additional_position = log_text.find(additional_token, stale_position)
    success_position = log_text.find(success_token, additional_position)
    source_import_position = log_text.find(source_import_token, success_position)
    harness_import_position = log_text.find(harness_import_token, success_position)
    reload_position = log_text.find(reload_token, success_position)
    positions = [stale_position, additional_position, success_position, source_import_position, harness_import_position, reload_position]
    check(all(position >= 0 for position in positions), "compile-sequence token missing")
    check(positions == sorted(positions), "compile-sequence order invalid")
    check(len(re.findall(r"error CS\d+", log_text)) == 1, "unexpected compiler-error count")

    rsp = root / "Library/Bee/artifacts/1900b0aE.dag/Assembly-CSharp.rsp"
    check(rsp.is_file(), "current Assembly-CSharp response file missing")
    if rsp.is_file():
        rsp_text = rsp.read_text(encoding="utf-8", errors="replace")
        check("Gate14ReMEAllocationCounterV2.cs" not in rsp_text, "withdrawn candidate remains in current response file")
        check("Gate14ReMEManagedHeapOccupancyV1.cs" in rsp_text, "new D3 source absent from current response file")

    final_contract = read_json(paths["final_contract"])
    check(final_contract.get("status") == "FROZEN_SOURCE_ONLY_D3_V2_INSTRUMENT_CONTRACT", "final contract status")
    replacement = final_contract.get("endpointReplacement", {})
    check(replacement.get("semanticVersion") == 2, "final contract D3 version")
    check(replacement.get("counterId") == "GC.GetTotalMemory(false)-managed-heap-occupancy-v1", "final contract counter")
    integration = final_contract.get("integrationState", {})
    check(integration.get("d3V2StandaloneSourceQualified") is True, "standalone qualification missing")
    for key in ("currentLoadQualificationRunnerUpdatedForD3V2", "currentOutputSchemaUpdatedForD3V2", "runtimeQualificationAttempt002Authorized", "dataExporterKnownAnswerAuthorized", "algorithmLaneExecutionAuthorized", "formalCollectionAuthorized", "formalAnalysisAuthorized", "rankingOrWinnerAuthorized"):
        check(integration.get(key) is False, f"unauthorized integration/execution enabled: {key}")

    status = read_json(paths["status_v6"])
    check(status.get("status") == "D3_V2_MANAGED_HEAP_OCCUPANCY_SOURCE_FROZEN_KNOWN_ANSWER_PASSED", "status-v6 state")
    capabilities = status.get("currentQualifiedCapabilities", {})
    check(capabilities.get("d3V2ManagedHeapOccupancyStandaloneQualified") is True, "status-v6 standalone D3")
    check(capabilities.get("d3V2IntegratedIntoQualificationRunner") is False, "status-v6 runner integration")
    check(capabilities.get("d3V2IntegratedIntoOutputSchema") is False, "status-v6 schema integration")
    check(all(value is False for value in status.get("authorizationState", {}).values()), "status-v6 unauthorized state enabled")

    manifest = read_json(paths["source_manifest"])
    check(manifest.get("status") == "SOURCE_FREEZE_CANDIDATE_D3_V2_KNOWN_ANSWER_PASSED", "source manifest status")
    for artifact in manifest.get("artifacts", []):
        artifact_path = root / artifact["relativePath"]
        check(artifact_path.is_file(), f"manifest artifact missing: {artifact_path}")
        if artifact_path.is_file():
            check(artifact_path.stat().st_size == artifact["bytes"], f"manifest byte count mismatch: {artifact_path}")
            check(sha256(artifact_path) == artifact["sha256"], f"manifest hash mismatch: {artifact_path}")
            check(is_read_only(artifact_path), f"manifest artifact not read-only: {artifact_path}")

    for relative, expected in ALGORITHM_HASHES.items():
        check(sha256(root / relative) == expected, f"algorithm source drift: {relative}")

    source_text = paths["source"].read_text(encoding="utf-8")
    check("GC.GetTotalMemory(false)" in source_text, "replacement API absent")
    check("GetAllocatedBytesForCurrentThread" not in source_text, "retired thread counter in replacement source")
    check("GetTotalAllocatedBytes" not in source_text, "failed process counter in replacement source")

    check(not (root / "Assets/_Scripts/Research/Gate14ReME/v2/Gate14ReMEAllocationCounterV2.cs").exists(), "failed candidate counter active")
    check(not (root / "Assets/_Scripts/Research/Editor/Gate14ReMED3RuntimeCompatibilityRunnerV1.cs").exists(), "failed candidate harness active")
    known_dir_entries = sorted(path.name for path in paths["known_answer"].parent.iterdir())
    check(known_dir_entries == ["d3-known-answer-receipt.v1.json"], "unexpected known-answer output files")

    for relative in (
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ):
        check(not (root / relative).exists(), f"prohibited root exists: {relative}")

    try:
        current_unity_process_count = unity_process_count()
    except Exception as exception:  # fail closed on host-inspection errors
        current_unity_process_count = -1
        failures.append(f"Unity process inspection failed: {exception}")
    check(current_unity_process_count == 0, "Unity process count is not zero")

    result = {
        "schema": "gate14re-me-d3-endpoint-replacement-validation-result-v1",
        "studyId": "Gate14Re-ME",
        "authorizationId": AUTHORIZATION_ID,
        "status": "PASS_D3_V2_SOURCE_FREEZE" if not failures else "FAIL_VALIDATION",
        "checksPassed": checks_passed,
        "checksFailed": len(failures),
        "failures": failures,
        "currentUnityProcessCount": current_unity_process_count,
        "d3V2StandaloneKnownAnswerPassed": True,
        "d3V2IntegratedIntoQualificationRunner": False,
        "algorithmLaneExecuted": False,
        "qualificationObservationCount": 0,
        "formalObservationCount": 0,
        "formalAnalysisPerformed": False,
        "rankingOrWinnerComputed": False,
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
