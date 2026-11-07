from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE_EVIDENCE = ROOT / "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-010"
EVIDENCE = ROOT / "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011"
MEASURED_REL = "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-009"
DELIVERY_REL = "Research/Exports/Gate14Re-ME/load-qualification/attempt-009"
AUTHORIZATION_ID = "gate14re-me-load-qualification-execution-attempt-011-c9a7fec1-6e42-421a-bc91-74048f4bbeef"
NONCE = "e9d07163-774e-46cb-9050-021c8956b9ef"
CREATED = "2026-10-19T14:34:30.9233419Z"

HASHES = {
    "supervisor": "1525e2e3a724404e649a5234dc801242cd598fcddaac92bc31514770f9b7b7f5",
    "runner": "622d97031efe51a1ea89fc2da95e5b473c170b817d452e76d3b25d81b228140d",
    "runner_meta": "fe193b1f2899fd6aae3510c032291c3ef2948687a27245d8cd2d847696ef8e92",
    "geometry_validator": "08e2b067e667a11a0cae2f6162721bbd3b59c2e32ce806d247bd10aa63487eb9",
    "manifest": "ae9c6bc5641b36808d896b5cfcc509cb835a55b8c667212f7af5787fcf6b2a00",
    "acquisition": "4498b9bf0b8d8e3cd92c6ddc65a6dbef1a61ec22f88acc6c63e52694cdeeaf7f",
    "acceptance": "dfa6ded73db0ff97dca28880b81882f1a4babd44ea52e7ed963f338fb2dd0c1f",
    "freeze_terminal": "74f215d39353e7ba33009dc975d28cb6b814c599bc66528405282e70a4b1d8e6",
    "freeze_manifest": "b76c9fe738ec250890ccad3ea5728909cb28ccce83e3db87a7a8f27ec6efe036",
    "readiness": "6d590303a6b464831648c6993ff4f340cb99b5dfaac4bf17e6e9bf8c44e4e6bc",
    "attempt010_failure_seal": "4101192a424d33ac227d49fa61ca6580a2d01d381984ed92901f1f9ce151af6d",
    "planning": "8624880f6fbe0b709dd6d2127b5861d62d862d592dcd2b0e311c579afffbeee3",
    "schedule": "8786f687a142900c0cf609817bbc1da957ec3ee9e09d12549e886fb892f026cb",
    "budget": "b6938a75285167045fb9736e6c5a765dba1e54eb037edabec91d82e56d5ccc4e",
    "fairness": "5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca",
    "identity": "77b88a23a559642d455edf0d4caad9a1f9c06b7ddf33703b8fd100f4a1878bd2",
    "identity_rule": "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06",
    "timestamp": "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27",
    "attempt009_seal": "7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705",
    "unity": "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf",
    "powershell": "362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139",
    "python": "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_exclusive(path: Path, value: object) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def write_text_exclusive(path: Path, value: str) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(value.replace("\r\n", "\n"))


def replace_required(text: str, old: str, new: str) -> str:
    if old not in text:
        raise RuntimeError(f"required source token missing: {old}")
    return text.replace(old, new)


def scope() -> dict[str, object]:
    return {
        "schema": "gate14re-me-user-authorization-scope-v1",
        "studyId": "Gate14Re-ME",
        "authorizationScopeId": "gate14re-me-recommended-sequence-through-step-009-c9a7fec1-6e42-421a-bc91-74048f4bbeef",
        "status": "AUTHORIZED_STEPS_001_THROUGH_009_ONLY",
        "authorizedAtUtc": CREATED,
        "authorizationSource": "direct user instruction in the current Codex task",
        "userAuthorizationTextExact": "授权推荐顺序中直至第九项",
        "authorizedSteps": [
            {"ordinal": 1, "name": "authorize-new-qualification"},
            {"ordinal": 2, "name": "issue-one-time-qualification-execution-authorization"},
            {"ordinal": 3, "name": "create-fresh-execution-evidence-measured-and-deferred-acceptance-delivery-roots"},
            {"ordinal": 4, "name": "execute-775-strict-serial-fresh-unity-processes"},
            {"ordinal": 5, "name": "seal-complete-raw-qualification-evidence"},
            {"ordinal": 6, "name": "run-independent-read-only-offline-acceptance-v4.3"},
            {"ordinal": 7, "name": "run-anonymous-resource-prediction-and-authorized-named-runtime-engineering-diagnostic"},
            {"ordinal": 8, "name": "freeze-final-B-and-formal-ST-contract-if-all-scientific-and-technical-gates-pass"},
            {"ordinal": 9, "name": "reactivate-migration-package-stage-as-ready-for-build"},
        ],
        "notAuthorized": [
            "migration-package-staging-or-build", "copying-Unity-installers", "copying-credential-payload", "creating-ZIP",
            "formal-ST-collection", "formal-effect-analysis", "cross-algorithm-effect-interpretation",
            "ranking-weighting-or-winner-adjudication", "automatic-ST-design-change", "automatic-MQ-or-MT-start",
        ],
        "qualificationExecutionRules": {
            "oneShot": True, "strictSerial": True, "freshUnityProcessCount": 775,
            "maximumConcurrentUnityProcesses": 1, "zeroReplacement": True,
            "retryResumeTopUpMergeSkipReorderReplacementOrParallelAuthorized": False,
        },
        "postPassRules": {
            "successfulQualificationRootsRemainImmutable": True,
            "acceptanceIsReadOnlyAndUsesIndependentOutputRoot": True,
            "runtimeDiagnosticMayUnsealAlgorithmIdentityOnlyAfterAnonymousPlanAndPredictionAreFrozen": True,
            "algorithmObservationsEffectsRankingsAndWinnersRemainProhibited": True,
            "migrationPackageFinalState": "REACTIVATED_READY_FOR_BUILD_NOT_BUILT",
        },
    }


def plan() -> dict[str, object]:
    return {
        "schema": "gate14re-me-load-qualification-execution-plan-v4.2",
        "studyId": "Gate14Re-ME", "protocolId": "gate14re-me-load-qualification-v1",
        "designId": "gate14re-me-bounded-gnf-discrimination-window-v4",
        "attemptId": "load-qualification-execution-attempt-011", "status": "PLANNED_NOT_LAUNCHED",
        "createdAtUtc": CREATED, "projectRoot": "H:/DDM_Final_Project",
        "executionEvidenceRootRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011",
        "measuredRootRelativePath": MEASURED_REL,
        "acceptanceDeliveryRootRelativePath": DELIVERY_REL,
        "acceptanceOutputRootPolicy": "CREATE_FRESH_VERSIONED_ROOT_ONLY_AFTER_RAW_ACQUISITION_SEAL",
        "processPlan": {"instrumentSelfTest": 1, "oracleBatch": 6, "emptyBoundary": 12, "algorithmLane": 756, "total": 775, "superblocks": 126, "algorithmsPerSuperblock": 6, "maximumConcurrentUnityProcesses": 1},
        "frozenLoadGrid": {"G": [64, 96, 128], "N": [32, 64, 128], "F": [1, 9, 25, 81], "coreCells": 36, "coreReplicatesPerCell": 3, "coreSuperblocks": 108, "stressCell": {"G": 128, "N": 128, "F": 81}, "stressSuperblocks": 18},
        "executionRules": {"oneShot": True, "strictSerial": True, "freshUnityProcessPerUnit": True, "zeroReplacementFailStop": True, "retryResumeTopUpMergeSkipReorderReplacementOrParallelAuthorized": False, "formalCollectionAuthorized": False, "formalAnalysisAuthorized": False},
        "frozenBindings": {
            "designAndImplementationFreezeTerminalRelativePath": "Research/Verification/Gate14Re-ME/qualification-design-implementation-freeze-v4_2-attempt-001/terminal-receipt.v4_2.json",
            "designAndImplementationFreezeTerminalSha256": HASHES["freeze_terminal"],
            "designAndImplementationFreezeManifestRelativePath": "Research/Verification/Gate14Re-ME/qualification-design-implementation-freeze-v4_2-attempt-001/freeze-manifest.v4_2.json",
            "designAndImplementationFreezeManifestSha256": HASHES["freeze_manifest"],
            "readinessReceiptRelativePath": "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-009/terminal-readiness-receipt.v4_6.json",
            "readinessReceiptSha256": HASHES["readiness"],
            "implementationManifestRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_2.json",
            "implementationManifestSha256": HASHES["manifest"],
            "acquisitionContractRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_2.json",
            "acquisitionContractSha256": HASHES["acquisition"],
            "acceptanceContractRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-acceptance-contract.v4_3.json",
            "acceptanceContractSha256": HASHES["acceptance"],
            "planningAssetsManifestRelativePath": "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets-freeze-manifest.v4.json",
            "planningAssetsManifestSha256": HASHES["planning"],
            "scheduleRelativePath": "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl",
            "scheduleSha256": HASHES["schedule"],
            "resourceBudgetRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-resource-budget.v4_1.json",
            "resourceBudgetSha256": HASHES["budget"],
            "fairnessBindingRelativePath": "Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json",
            "fairnessBindingSha256": HASHES["fairness"],
            "trustedIdentityRuleRelativePath": "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json",
            "trustedIdentityRuleSha256": HASHES["identity_rule"],
            "timestampComparatorRelativePath": "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1",
            "timestampComparatorSha256": HASHES["timestamp"],
            "unityExecutablePath": "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe", "unityExecutableSha256": HASHES["unity"],
            "powerShellExecutablePath": "C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe", "powerShellExecutableSha256": HASHES["powershell"], "powerShellVersion": "7.6.5",
            "pythonExecutablePath": "C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe", "pythonExecutableSha256": HASHES["python"],
        },
        "priorAttemptsIsolation": {
            "attempt009PausedSealRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/terminal-seal-receipt.v1.json",
            "attempt009PausedSealSha256": HASHES["attempt009_seal"],
            "attempt010FailureSealRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-failure-seal-attempt-010/terminal-failure-seal-receipt.v1.json",
            "attempt010FailureSealSha256": HASHES["attempt010_failure_seal"],
            "reuseOrMutationAuthorized": False,
        },
    }


def authorization() -> dict[str, object]:
    return {
        "schema": "gate14re-me-load-qualification-execution-authorization-v1",
        "studyId": "Gate14Re-ME", "protocolId": "gate14re-me-load-qualification-v1", "designId": "gate14re-me-bounded-gnf-discrimination-window-v4",
        "authorizationId": AUTHORIZATION_ID, "authorizationNonce": NONCE,
        "attemptId": "load-qualification-execution-attempt-011", "status": "AUTHORIZED_LOAD_QUALIFICATION_EXECUTION",
        "authorizedAtUtc": CREATED, "authorizationSource": "direct user authorization of recommended sequence through step nine",
        "userAuthorizationTextExact": "授权推荐顺序中直至第九项",
        "userAuthorizationScopeRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/user-authorization-scope.v1.json",
        "qualificationInputGenerationAuthorized": False, "qualificationRootCreationAuthorized": True,
        "compileOrUnityExecutionAuthorized": True, "qualificationExecutionAuthorized": True, "rawSealAuthorized": True,
        "readOnlyOfflineAcceptanceAfterRawSealAuthorized": True, "postPassRuntimeEngineeringDiagnosticAuthorized": True,
        "postPassFinalBAndFormalContractFreezeAuthorized": True, "migrationPackageStageReactivationAuthorized": True,
        "migrationPackageBuildAuthorized": False, "formalCollectionAuthorized": False, "formalAnalysisAuthorized": False,
        "crossAlgorithmEffectsAuthorized": False, "rankingAuthorized": False, "weightingAuthorized": False, "winnerAdjudicationAuthorized": False,
        "measuredRootRelativePath": MEASURED_REL, "acceptanceDeliveryRootRelativePath": DELIVERY_REL,
        "supervisorRelativePath": "Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_2.ps1", "supervisorSha256": HASHES["supervisor"],
        "runnerRelativePath": "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_2.cs", "runnerSha256": HASHES["runner"],
        "runnerExecuteMethod": "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV4_2.Run",
        "implementationManifestRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_2.json", "implementationManifestSha256": HASHES["manifest"],
        "executionContractRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_2.json", "executionContractSha256": HASHES["acquisition"],
        "planningAssetsManifestRelativePath": "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets-freeze-manifest.v4.json", "planningAssetsManifestSha256": HASHES["planning"],
        "resourceBudgetRelativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-resource-budget.v4_1.json", "resourceBudgetSha256": HASHES["budget"],
        "fairnessBindingRelativePath": "Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json", "fairnessBindingSha256": HASHES["fairness"],
        "scheduleRelativePath": "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl", "scheduleSha256": HASHES["schedule"],
        "powerShellHostRuntime": {"executablePath": "C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe", "sha256": HASHES["powershell"], "version": "7.6.5"},
        "unityRuntime": {"executablePath": "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe", "sha256": HASHES["unity"]},
        "strictSerialFreshUnityProcessesAuthorized": 775, "zeroReplacementFailStop": True,
        "retryResumeTopUpMergeSkipReorderOrParallelAuthorized": False,
        "automaticFreshAttemptAfterFrozenTechnicalFailureAuthorized": False,
        "qualificationInputGenerationAlreadyFrozen": True, "qualificationInputRegenerationPerformedByThisAttempt": False,
        "sealedIdentityMappingMayBeOpenedDuringQualification": False,
        "sealedIdentityMappingMayBeOpenedForPostPassRuntimeDiagnosticOnly": True,
        "priorAttemptRootsOrAuthorizationReuseAuthorized": False,
    }


def transformed_prelaunch() -> str:
    text = (SOURCE_EVIDENCE / "Test-Gate14ReMEPrelaunchAttempt010.ps1").read_text(encoding="utf-8-sig")
    replacements = [
        ("gate14re-me-load-qualification-execution-attempt-010-37d80e56-786a-40ac-87bc-5ff9eb1f98a5", AUTHORIZATION_ID),
        ("attempt-010", "attempt-011"), ("attempt-008", "attempt-009"),
        ("prelaunch-audit.v4_1.json", "prelaunch-audit.v4_2.json"), ("prelaunch-failure-receipt.v4_1.json", "prelaunch-failure-receipt.v4_2.json"),
        ("execution-plan.v4_1.json", "execution-plan.v4_2.json"),
        ("Run-Gate14ReMELoadQualification.v4_1.ps1", "Run-Gate14ReMELoadQualification.v4_2.ps1"),
        (HASHES["supervisor"], HASHES["supervisor"]),
        ("1787264268e78c75e4ad7adc0e1490f7e812ea62f0ac5ba4b742a0cc9cba0fb3", HASHES["supervisor"]),
        ("Gate14ReMELoadQualificationRunnerV4_1.cs.meta", "Gate14ReMELoadQualificationRunnerV4_2.cs.meta"),
        ("6c5b7cdac5391397219e80a414f10ce5c78a3914571e38ab3419a65d0cf72175", HASHES["runner_meta"]),
        ("Gate14ReMELoadQualificationRunnerV4_1.cs", "Gate14ReMELoadQualificationRunnerV4_2.cs"),
        ("a3013097068325f314e6842dd9f9bdc2cedbc5d6773a51032200925228690a9f", HASHES["runner"]),
        ("load-qualification-current-implementation-manifest.v4_1.json", "load-qualification-current-implementation-manifest.v4_2.json"),
        ("380939df90716130031dc086086607fa1286e8d6f7cf3d1cadae104e5c798658", HASHES["manifest"]),
        ("load-qualification-acquisition-contract.v4_1.json", "load-qualification-acquisition-contract.v4_2.json"),
        ("1ccf472feecd2c811f4f6547b0424126f74bfa1ac0758885ff9db216cc2834f7", HASHES["acquisition"]),
        ("load-qualification-acceptance-contract.v4_2.json", "load-qualification-acceptance-contract.v4_3.json"),
        ("75b9b08e8fff191dc0168c41fe75a8d9e741dd6a6e0bd7eec941848de91ad19c", HASHES["acceptance"]),
        ("qualification-design-implementation-freeze-v4_1-attempt-001/terminal-receipt.v4_1.json", "qualification-design-implementation-freeze-v4_2-attempt-001/terminal-receipt.v4_2.json"),
        ("400e866654066b204bf46b889f335b3d9debbc74e08029dc6ab6c7c0fac7d403", HASHES["freeze_terminal"]),
        ("qualification-design-implementation-freeze-v4_1-attempt-001/freeze-manifest.v4_1.json", "qualification-design-implementation-freeze-v4_2-attempt-001/freeze-manifest.v4_2.json"),
        ("7f8792fcf42f2e26ce40ee9452cf42980e883ba17e64b362329140e0c4d99e1b", HASHES["freeze_manifest"]),
        ("qualification-implementation-readiness-v4-attempt-007/compile-readiness-receipt.v4_5.json", "qualification-implementation-readiness-v4-attempt-009/terminal-readiness-receipt.v4_6.json"),
        ("de476e64cb5f9f8558ab77720aeaeb57d757dc263b56a8f93b150b54f60377f6", HASHES["readiness"]),
        ("@($manifest.artifacts).Count -eq 33", "@($manifest.artifacts).Count -eq 39"),
        ("implementationManifestArtifactsVerified = 33", "implementationManifestArtifactsVerified = 39"),
        ("FROZEN_V4_1_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED", "FROZEN_V4_2_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED"),
        ("Exact v4.1 compile-readiness receipt", "Exact v4.2 compile-readiness receipt"),
        ("gate14re-me-load-qualification-prelaunch-audit-v4.1", "gate14re-me-load-qualification-prelaunch-audit-v4.2"),
        ("gate14re-me-load-qualification-prelaunch-failure-receipt-v4.1", "gate14re-me-load-qualification-prelaunch-failure-receipt-v4.2"),
    ]
    for old, new in replacements:
        if old != new:
            text = replace_required(text, old, new)
    text = replace_required(text, "$measuredRoot = Resolve-ProjectPath -Root $root -RelativePath $measuredRelative", "$measuredRoot = Resolve-ProjectPath -Root $root -RelativePath $measuredRelative\n$deliveryRelative = '" + DELIVERY_REL + "'\n$deliveryRoot = Resolve-ProjectPath -Root $root -RelativePath $deliveryRelative")
    text = replace_required(text, "Require-Condition (-not (Test-Path -LiteralPath $measuredRoot)) 'Fresh measured root already exists.'", "Require-Condition (-not (Test-Path -LiteralPath $measuredRoot)) 'Fresh measured root already exists.'\n    Require-Condition (-not (Test-Path -LiteralPath $deliveryRoot)) 'Fresh deferred acceptance delivery root already exists.'")
    text = replace_required(text, "measuredRootAbsent = $true", "measuredRootAbsent = $true\n        deferredAcceptanceDeliveryRootRelativePath = $deliveryRelative\n        deferredAcceptanceDeliveryRootAbsent = $true")
    return text


def transformed_launcher() -> str:
    text = (SOURCE_EVIDENCE / "Invoke-Gate14ReMELoadQualificationAttempt010.ps1").read_text(encoding="utf-8-sig")
    for old, new in [
        ("attempt-010", "attempt-011"), ("attempt-008", "attempt-009"),
        ("launch-contract.v4_1.json", "launch-contract.v4_2.json"),
        ("Run-Gate14ReMELoadQualification.v4_1.ps1", "Run-Gate14ReMELoadQualification.v4_2.ps1"),
    ]:
        text = replace_required(text, old, new)
    text = replace_required(text, "Require-Condition (-not (Test-Path -LiteralPath ([string]$contract.measuredRoot))) 'Measured root already exists.'", "Require-Condition (-not (Test-Path -LiteralPath ([string]$contract.measuredRoot))) 'Measured root already exists.'\n    Require-Condition (-not (Test-Path -LiteralPath ([string]$contract.acceptanceDeliveryRoot))) 'Deferred acceptance delivery root already exists.'")
    return text


def phase_one() -> None:
    if EVIDENCE.exists():
        raise RuntimeError(f"refusing to reuse evidence root: {EVIDENCE}")
    prelaunch_text = transformed_prelaunch()
    launcher_text = transformed_launcher()
    EVIDENCE.mkdir(parents=False)
    write_json_exclusive(EVIDENCE / "user-authorization-scope.v1.json", scope())
    write_json_exclusive(EVIDENCE / "execution-plan.v4_2.json", plan())
    write_json_exclusive(EVIDENCE / "execution-authorization.v1.json", authorization())
    write_text_exclusive(EVIDENCE / "Test-Gate14ReMEPrelaunchAttempt011.ps1", prelaunch_text)
    write_text_exclusive(EVIDENCE / "Invoke-Gate14ReMELoadQualificationAttempt011.ps1", launcher_text)
    print(json.dumps({"evidenceRoot": EVIDENCE.as_posix(), "authorizationSha256": sha256(EVIDENCE / "execution-authorization.v1.json"), "planSha256": sha256(EVIDENCE / "execution-plan.v4_2.json"), "scopeSha256": sha256(EVIDENCE / "user-authorization-scope.v1.json"), "prelaunchSha256": sha256(EVIDENCE / "Test-Gate14ReMEPrelaunchAttempt011.ps1"), "launcherSha256": sha256(EVIDENCE / "Invoke-Gate14ReMELoadQualificationAttempt011.ps1")}))


def phase_two() -> None:
    audit = EVIDENCE / "prelaunch-audit.v4_2.json"
    if not audit.is_file():
        raise RuntimeError("prelaunch audit is absent")
    target = EVIDENCE / "launch-contract.v4_2.json"
    if target.exists():
        raise RuntimeError("refusing to overwrite launch contract")
    auth_hash = sha256(EVIDENCE / "execution-authorization.v1.json")
    args = [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-File", "H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_2.ps1",
        "-ProjectRoot", "H:/DDM_Final_Project", "-MeasuredRoot", "H:/DDM_Final_Project/" + MEASURED_REL,
        "-ExecutionAuthorization", "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/execution-authorization.v1.json", "-ExecutionAuthorizationSha256", auth_hash,
        "-ImplementationManifest", "H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_2.json", "-ImplementationManifestSha256", HASHES["manifest"],
        "-ExecutionContract", "H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_2.json", "-ExecutionContractSha256", HASHES["acquisition"],
        "-PlanningAssetsManifest", "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets-freeze-manifest.v4.json", "-PlanningAssetsManifestSha256", HASHES["planning"],
        "-ResourceBudget", "H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v4/load-qualification-resource-budget.v4_1.json", "-ResourceBudgetSha256", HASHES["budget"],
        "-FairnessBinding", "H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json", "-FairnessBindingSha256", HASHES["fairness"],
        "-Schedule", "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl", "-ScheduleSha256", HASHES["schedule"],
        "-TrustedIdentityRule", "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json", "-TrustedIdentityRuleSha256", HASHES["identity_rule"],
        "-TimestampComparator", "H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1", "-TimestampComparatorSha256", HASHES["timestamp"],
        "-UnityExecutable", "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe", "-UnityExecutableSha256", HASHES["unity"],
    ]
    canonical = json.dumps(args, ensure_ascii=False, separators=(",", ":"))
    argument_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    contract = {
        "schema": "gate14re-me-load-qualification-execution-attempt-011-launch-contract-v4.2",
        "studyId": "Gate14Re-ME", "authorizationId": AUTHORIZATION_ID, "attemptId": "load-qualification-execution-attempt-011",
        "status": "FROZEN_EXTERNAL_LAUNCH_CONTRACT", "createdAtUtc": CREATED,
        "executable": {"path": "C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe", "sha256": HASHES["powershell"], "version": "7.6.5"},
        "argumentVectorCanonicalSerialization": "POWERSHELL_CONVERTTOJSON_COMPRESS_UTF8_NO_BOM", "argumentVectorSha256": argument_hash,
        "argumentVector": args, "argumentCount": len(args), "projectRoot": "H:/DDM_Final_Project",
        "measuredRoot": "H:/DDM_Final_Project/" + MEASURED_REL, "acceptanceDeliveryRoot": "H:/DDM_Final_Project/" + DELIVERY_REL,
        "executionAuthorization": {"relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/execution-authorization.v1.json", "sha256": auth_hash},
        "userAuthorizationScope": {"relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/user-authorization-scope.v1.json", "sha256": sha256(EVIDENCE / "user-authorization-scope.v1.json")},
        "executionPlan": {"relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/execution-plan.v4_2.json", "sha256": sha256(EVIDENCE / "execution-plan.v4_2.json")},
        "prelaunchAudit": {"relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/prelaunch-audit.v4_2.json", "sha256": sha256(audit)},
        "implementationManifest": {"relativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_2.json", "sha256": HASHES["manifest"]},
        "executionContract": {"relativePath": "Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_2.json", "sha256": HASHES["acquisition"]},
        "launcher": {"relativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/Invoke-Gate14ReMELoadQualificationAttempt011.ps1", "sha256": sha256(EVIDENCE / "Invoke-Gate14ReMELoadQualificationAttempt011.ps1")},
        "stdoutRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/supervisor.stdout.log",
        "stderrRelativePath": "Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-011/supervisor.stderr.log",
        "workingDirectory": "H:/DDM_Final_Project", "windowStyle": "Hidden", "waitForCompletionAtBootstrap": False,
        "signalOrForcedTerminationAuthorized": False, "migrationPackageBuildAuthorized": False,
    }
    write_json_exclusive(target, contract)
    print(json.dumps({"launchContract": target.as_posix(), "sha256": sha256(target), "argumentVectorSha256": argument_hash, "argumentCount": len(args)}))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("phase-one", "phase-two"))
    args = parser.parse_args()
    phase_one() if args.phase == "phase-one" else phase_two()


if __name__ == "__main__":
    main()
