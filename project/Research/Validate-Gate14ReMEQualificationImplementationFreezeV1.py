#!/usr/bin/env python3
"""Validate the Gate14Re-ME source-only qualification implementation freeze.

This validator performs static, structural and hash checks only.  It neither
compiles nor starts Unity, creates no measured root, reads no prior experimental
outcome, and computes no algorithm comparison, ranking or winner.
"""

from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_RELATIVE = "Research/Verification/Gate14Re-ME/qualification-implementation-freeze-attempt-001/implementation-manifest.v1.json"
PRIOR_BINDINGS = {
    "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Load_Qualification_Freeze_Authorization.v1.json": "5e2c6b7781069b41c18929bac80705d9523c8fe47d51403d1b51d11012085c1f",
    "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Load_Qualification_Protocol.v1.json": "93f176513ba09f07abe2cb3182a5e7c20662495773d810c54caa7d9589dfa364",
    "Research/Gate14Re-ME/Gate14Re_ME_Experiment_Plan.v2.md": "774942ace72f98961fa65fc97c43ecbc7f850f2dbad47775dc5ff1b96eb4c4d0",
    "Research/Gate14Re-ME/Gate14Re_ME_NonExecuting_Scientific_Contract.v2.json": "73d81fe3be7c0e8f1ba6bbf25e584d86137a2e196d89ec03de7e8d59bf6412f5",
    "Research/Gate14Re-ME/Gate14Re_ME_Precollection_Parameter_Amendment_Protocol.v2.json": "8960c2050f34ff56a8f680f092bdc4cf156ed8cff4ae264015411cbb249255d6",
    "Research/Gate14Re-ME/Gate14Re_ME_Status.v2.json": "287b2483dc87bae95e1a0891d30879e58eaad0fea02c3d3885111506284f050a",
    "Research/Validate-Gate14ReMELoadQualificationFreezeV1.py": "0a205f99a0686dcb550c3456c860b4825097c37e9c39c765ea12d21125835c37",
}
ALGORITHM_BINDINGS = {
    "A*-R": (
        "Assets/_Scripts/Research/Algorithms/AStarRepeatedPlanner.cs",
        "a54bb43ed906c856e3d45493c4d3d10ff1b6f1e0ccda1a9f25ea774908b9c778",
        "Research/AStar_Repeated_Specification.md",
        "0fe75b470bb0b1f256278ddf8089b86660a80a5c20c99006a140ff7c3ec8c5eb",
    ),
    "BiA*-R": (
        "Assets/_Scripts/Research/Algorithms/BidirectionalAStarRepeatedPlanner.cs",
        "82316036aba90be69ca746288798bac1789cdb09afa65cf9ad4180975d1f947e",
        "Research/Gate13R-AX2/Algorithms/Bidirectional_A_Star_Repeated_Specification.v1.md",
        "593e21946de91c8ddab59f70be44084aeb8afe7ae72d52e490589f6e77f16ead",
    ),
    "D*L": (
        "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs",
        "ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f",
        "Research/DStar_Lite_Specification.md",
        "65f03f4827c0bd2edceb967311451cace2a34642235457277cbbaaba222b01c3",
    ),
    "LPA*": (
        "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs",
        "10686f9bf5b36ec06e8d5e98a7c54f8bdcc5a1c0d0664cb9a3eed6a806bc52c8",
        "Research/Gate13R-AX2/Algorithms/Lifelong_Planning_A_Star_Specification.v1.md",
        "703e72a92207ceb05f0e63c35322f2a8e727b5e8be6e1dc699cd287ce254d4a9",
    ),
    "C-FF": (
        "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
        "bdaa52bc93950ea6a1737a7629ec6ceda60370f6ebc489deb166e2eddc51f3e1",
        "Research/Corrected_Full_Recompute_Flow_Field_Specification.md",
        "6f29c7545c2f9d68ad0bfd2b707cb7f7798fd80b39816eb22010f278a6978223",
    ),
    "IDFF": (
        "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
        "63aa0792bd0935d1e98158278580cf2ece5980cf3e52ef7e9adb16bbcddc7638",
        "Research/Incremental_Dynamic_Flow_Field_Specification.md",
        "8a7895c0daa38810a5b1087348be11b427cfeb1f6f0ed2f27730578ac84e70ef",
    ),
}
EXPECTED_ARTIFACTS = {
    "Assets/_Scripts/Research/Gate14ReME.meta",
    "Assets/_Scripts/Research/Gate14ReME/v1.meta",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs.meta",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEInstrumentationV1.cs",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEInstrumentationV1.cs.meta",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs",
    "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs.meta",
    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs",
    "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs.meta",
    "Research/Gate14Re-ME/Execution/v1/Run-Gate14ReMELoadQualification.v1.ps1",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-execution-contract.v1.json",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-input-schema.v1.json",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-instrument-contract.v1.json",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json",
    "Research/Gate14Re-ME/Execution/v1/load-qualification-schedule-schema.v1.json",
    "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json",
    "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Implementation_Freeze_Authorization.v1.json",
    "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Implementation_Plan.v1.md",
    "Research/Gate14Re-ME/Gate14Re_ME_Status.v3.json",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v1.py",
    "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v1.py",
    "Research/Validate-Gate14ReMEQualificationImplementationFreezeV1.py",
}


class ValidationFailure(RuntimeError):
    pass


class Checks:
    def __init__(self) -> None:
        self.items: List[Dict[str, Any]] = []

    def require(self, condition: bool, check_id: str, detail: str) -> None:
        if not condition:
            raise ValidationFailure(f"{check_id}: {detail}")
        self.items.append({"checkId": check_id, "status": "PASS", "detail": detail})


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(relative: str) -> Dict[str, Any]:
    path = PROJECT_ROOT / relative
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ValidationFailure(f"JSON parse failed: {relative}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValidationFailure(f"JSON object required: {relative}")
    return value


def is_read_only(path: Path) -> bool:
    if os.name == "nt":
        import ctypes

        attributes = ctypes.windll.kernel32.GetFileAttributesW(str(path))
        return attributes != -1 and bool(attributes & 0x1)
    return not os.access(path, os.W_OK)


def brace_balance(text: str) -> bool:
    stack: List[str] = []
    pairs = {"}": "{", ")": "(", "]": "["}
    index = 0
    state = "code"
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if state == "code":
            if char == "/" and next_char == "/":
                state = "line_comment"
                index += 2
                continue
            if char == "/" and next_char == "*":
                state = "block_comment"
                index += 2
                continue
            if char == '"':
                state = "string"
            elif char == "'":
                state = "char"
            elif char in "{([":
                stack.append(char)
            elif char in "})]":
                if not stack or stack.pop() != pairs[char]:
                    return False
        elif state == "line_comment":
            if char in "\r\n":
                state = "code"
        elif state == "block_comment":
            if char == "*" and next_char == "/":
                state = "code"
                index += 2
                continue
        elif state in {"string", "char"}:
            if char == "\\":
                index += 2
                continue
            if (state == "string" and char == '"') or (state == "char" and char == "'"):
                state = "code"
        index += 1
    return not stack and state in {"code", "line_comment"}


def csharp_public_fields(text: str, class_name: str) -> List[str]:
    match = re.search(
        rf"public\s+sealed\s+class\s+{re.escape(class_name)}\s*\{{(?P<body>.*?)\n\s*\}}",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValidationFailure(f"C# raw-row class missing: {class_name}")
    return re.findall(
        r"public\s+[A-Za-z0-9_<>\[\].]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^;]+)?;",
        match.group("body"),
    )


def validate() -> Dict[str, Any]:
    checks = Checks()

    for relative, expected in PRIOR_BINDINGS.items():
        path = PROJECT_ROOT / relative
        checks.require(path.is_file(), f"prior-exists:{relative}", "prior frozen file exists")
        checks.require(sha256_file(path) == expected, f"prior-hash:{relative}", "prior SHA-256 unchanged")
        checks.require(is_read_only(path), f"prior-readonly:{relative}", "prior frozen file remains read-only")

    authorization = read_json("Research/Gate14Re-ME/Gate14Re_ME_Qualification_Implementation_Freeze_Authorization.v1.json")
    checks.require(authorization.get("status") == "AUTHORIZED_QUALIFICATION_IMPLEMENTATION_AND_RESOURCE_FREEZE_ONLY", "authorization-status", "implementation-only authorization status exact")
    checks.require(authorization.get("userAuthorizationText") == "单独授权下一阶段", "authorization-text", "exact user authorization text retained")
    authorized = authorization.get("authorized", {})
    checks.require(all(authorized.get(key) is True for key in (
        "qualificationRunnerSourceImplementation",
        "algorithmNeutralReferenceOracleSourceImplementation",
        "D1D2D3D4InstrumentSourceImplementation",
        "completePerObservationDeliverySourceImplementation",
        "structuralValidationSourceImplementation",
        "sixAlgorithmSourceSpecificationAndFairnessHashBinding",
        "exactHostSpecificTimeoutMemoryAndStorageBudgetFreeze",
    )), "authorization-positive-scope", "all and only intended implementation components authorized")
    not_authorized = authorization.get("notAuthorized", {})
    checks.require(all(not_authorized.get(key) is True for key in (
        "qualificationInputGeneration",
        "qualificationScheduleGeneration",
        "qualificationIdentityBindingGeneration",
        "qualificationRootCreation",
        "compileOrUnityExecution",
        "runtimeInstrumentQualification",
        "pilotOrQualificationExecution",
        "formalInputGeneration",
        "formalMeasuredRootCreation",
        "formalCollection",
        "formalAnalysis",
        "ranking",
        "winnerAdjudication",
    )), "authorization-negative-scope", "all execution/formal/inferential activities remain unauthorized")
    checks.require(authorization.get("dataBoundary", {}).get("UnityProcessesLaunched") == 0 and authorization.get("dataBoundary", {}).get("Gate14ReMEQualificationObservationsCreated") == 0, "authorization-zero-observations", "authorization records zero Unity launches and observations")

    budget = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json")
    expected_budget = {
        "eventGroupHardTimeoutMilliseconds": 300000,
        "laneWallClockHardTimeoutMilliseconds": 5400000,
        "oracleInputHardTimeoutMilliseconds": 900000,
        "instrumentProcessHardTimeoutMilliseconds": 600000,
        "emptyBoundaryProcessHardTimeoutMilliseconds": 600000,
        "plannerOperationBudgetMilliseconds": 240000,
        "repairOperationBudgetMilliseconds": 240000,
        "initializationOperationBudgetMilliseconds": 600000,
        "laneAssignedCommittedMemoryBytes": 17179869184,
        "qualificationReservedStorageBytes": 51539607552,
        "formalRawAndDeliveryReservedStorageBytes": 103079215104,
        "maximumConcurrentUnityProcesses": 1,
        "maximumWholeSuperblockTechnicalReplacements": 1,
        "minimumHeadroomFactor": 2.0,
    }
    checks.require(budget.get("status") == "FROZEN_PREEXECUTION_BUDGETS", "budget-status", "resource budget is prospectively frozen")
    for key, expected in expected_budget.items():
        checks.require(budget.get(key) == expected, f"budget:{key}", f"absolute resource value exact: {expected}")
    snapshot = budget.get("hostSnapshot", {})
    checks.require(snapshot.get("storageFreeBytes") == 212333391872 and snapshot.get("totalFrozenReservationsBytes") == 154618822656 and snapshot.get("freeBytesAfterBothReservations") == 57714569216, "budget-storage-arithmetic", "host snapshot and reservation arithmetic exact")
    pass_ceiling = budget.get("qualificationPassCeilings", {})
    checks.require(pass_ceiling.get("lanePeakCommittedMemoryBytesLessThanOrEqual") * 2 == budget["laneAssignedCommittedMemoryBytes"], "budget-memory-headroom", "memory pass ceiling provides exactly two-times headroom")
    checks.require(pass_ceiling.get("qualificationObservedPackageBytesLessThanOrEqual") * 2 == budget["qualificationReservedStorageBytes"], "budget-qualification-storage-headroom", "qualification package pass ceiling provides exactly two-times headroom")
    checks.require(pass_ceiling.get("formalRawAndDeliveryProjectedBytesLessThanOrEqual") * 2 == budget["formalRawAndDeliveryReservedStorageBytes"], "budget-formal-storage-headroom", "formal projection pass ceiling provides exactly two-times headroom")

    fairness = read_json("Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json")
    checks.require(fairness.get("status") == "FROZEN_SIX_ALGORITHM_BINDING", "fairness-status", "six-algorithm binding frozen")
    algorithms = fairness.get("algorithms", [])
    checks.require([item.get("algorithmId") for item in algorithms] == list(ALGORITHM_BINDINGS), "fairness-cohort-order", "exact six-algorithm cohort and order")
    for item in algorithms:
        algorithm_id = item["algorithmId"]
        source, source_hash, specification, specification_hash = ALGORITHM_BINDINGS[algorithm_id]
        checks.require(item.get("implementationRelativePath") == source and item.get("implementationSha256") == source_hash and sha256_file(PROJECT_ROOT / source) == source_hash, f"algorithm-source:{algorithm_id}", "implementation path/hash/current bytes exact")
        checks.require(item.get("specificationRelativePath") == specification and item.get("specificationSha256") == specification_hash and sha256_file(PROJECT_ROOT / specification) == specification_hash, f"algorithm-spec:{algorithm_id}", "specification path/hash/current bytes exact")
    checks.require(sha256_file(PROJECT_ROOT / fairness["navigationContractsRelativePath"]) == fairness["navigationContractsSha256"] == "7e074ec1fa13d9de2addeca4defa702fb773974d17615de3fffce93b5c4f5efa", "fairness-navigation-contracts", "shared navigation contracts exact")
    checks.require(sha256_file(PROJECT_ROOT / fairness["navigationGridRelativePath"]) == fairness["navigationGridSha256"] == "4d147321f9ccc4fb6da64265ceeec28f372542531fa72482b2eced8cdee2f582", "fairness-grid", "shared navigation grid exact")
    checks.require(all(fairness.get(key) is True for key in ("sameByteIdenticalInputBundle", "oneFreshProcessPerAlgorithmLane", "sameDynamicBoundary", "sameOracle")) and fairness.get("algorithmSpecificWarmupGcExtraQueryAllowed") is False, "fairness-rules", "equal input/process/boundary/oracle and no special warm-up privilege")

    json_files = sorted((PROJECT_ROOT / "Research/Gate14Re-ME/Execution/v1").glob("*.json")) + [
        PROJECT_ROOT / "Research/Gate14Re-ME/Gate14Re_ME_Qualification_Implementation_Freeze_Authorization.v1.json",
        PROJECT_ROOT / "Research/Gate14Re-ME/Gate14Re_ME_Status.v3.json",
    ]
    for path in json_files:
        json.loads(path.read_text(encoding="utf-8-sig"))
        checks.require(True, f"json-parse:{path.name}", "JSON parses")

    python_files = [
        PROJECT_ROOT / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v1.py",
        PROJECT_ROOT / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v1.py",
        PROJECT_ROOT / "Research/Validate-Gate14ReMEQualificationImplementationFreezeV1.py",
    ]
    for path in python_files:
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        checks.require(True, f"python-ast:{path.name}", "Python source parses without writing bytecode")

    csharp_files = [
        PROJECT_ROOT / "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs",
        PROJECT_ROOT / "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEInstrumentationV1.cs",
        PROJECT_ROOT / "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs",
        PROJECT_ROOT / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs",
    ]
    for path in csharp_files:
        checks.require(brace_balance(path.read_text(encoding="utf-8")), f"csharp-static-delimiters:{path.name}", "C# delimiter/static lexical check passes; this is not compilation")
    instrumentation_text = csharp_files[1].read_text(encoding="utf-8")
    runner_text = csharp_files[-1].read_text(encoding="utf-8")
    for token in (
        "AUTHORIZED_LOAD_QUALIFICATION_EXECUTION",
        "if (!Directory.Exists(output)) return;",
        "Gate14ReMEReferenceOracleV1.Evaluate",
        "Gate14ReMEPersistentStateSizerV1.Measure",
        "EnsureNewOutputDirectory",
        "--g14me-schedule",
        "TryFindScheduledInput",
        "ScheduleContainsLane",
        "ReservedMeasuredRootRelativePath",
        "RequireExactOutputDirectory",
    ):
        checks.require(token.lower() in runner_text.lower(), f"runner-token:{token}", "runner contains required fail-closed/schedule/oracle/instrument behavior")
    checks.require("GC.GetAllocatedBytesForCurrentThread" in instrumentation_text, "instrumentation-allocation-counter", "D3 source uses the frozen current-thread allocation counter")
    checks.require("Directory.CreateDirectory(output);" not in runner_text[runner_text.index("private static void TryWriteFailureReceipt"):], "runner-no-preauth-failure-root", "failure handler cannot create an unauthorized measured root")
    for token in (
        'input.inputId + ":" + anonymousLaneId + ":initialize"',
        'input.inputId + ":" + anonymousLaneId + ":initial-query:"',
        'input.inputId + ":" + anonymousLaneId + ":resource:"',
        'string.Format("{0}:{1}:state:{2}:{3}", inputId, anonymousLaneId',
    ):
        checks.require(token in runner_text or token in instrumentation_text, f"global-record-id-token:{token}", "algorithm-lane raw recordId construction includes the anonymous lane and is globally unique by design")

    power_shell = PROJECT_ROOT / "Research/Gate14Re-ME/Execution/v1/Run-Gate14ReMELoadQualification.v1.ps1"
    parse_command = (
        "$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile(" 
        + "'" + str(power_shell).replace("'", "''") + "',[ref]$t,[ref]$e)|Out-Null;"
        + "if($e.Count){$e|%{$_.Message};exit 2}else{exit 0}"
    )
    parsed = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", parse_command], capture_output=True, text=True)
    checks.require(parsed.returncode == 0, "powershell-ast", "PowerShell supervisor parses without execution")
    supervisor_text = power_shell.read_text(encoding="utf-8")
    checks.require(supervisor_text.index("# Authorized creation boundary begins here.") < supervisor_text.index("New-Item -ItemType Directory -Path $measuredRootFull"), "supervisor-creation-boundary", "measured-root creation occurs only after the explicit authorized boundary")
    checks.require("System.IO.Path]::GetRelativePath" not in supervisor_text, "supervisor-windows-powershell-compatibility", "supervisor avoids Path.GetRelativePath unavailable in Windows PowerShell 5.1")
    for token in ("maximumConcurrentUnityProcesses", "maximumWholeSuperblockTechnicalReplacements", "Stop-Process", "accepted-superblock-receipt.v1.json", "resume and overwrite are prohibited", "--g14me-schedule", "All schedule rows must bind the same lower-case SHA-256 anonymous identity map", "measuredRootRelativePath", "recordId = \"void:", "recordId = \"replacement:"):
        checks.require(token in supervisor_text, f"supervisor-token:{token}", "supervisor contains required serial/replacement/fail-closed behavior")

    input_schema = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-input-schema.v1.json")
    output_schema = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-output-schema.v1.json")
    schedule_schema = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-schedule-schema.v1.json")
    instrument = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-instrument-contract.v1.json")
    execution = read_json("Research/Gate14Re-ME/Execution/v1/load-qualification-execution-contract.v1.json")
    contracts_text = csharp_files[0].read_text(encoding="utf-8")
    checks.require(input_schema.get("authorizationBoundary", {}).get("inputBundlesGenerated") == 0 and input_schema.get("authorizationBoundary", {}).get("inputGenerationAuthorized") is False, "input-schema-zero-generation", "input schema exists without generating inputs")
    schedule_boundary = schedule_schema.get("authorizationBoundary", {})
    checks.require(schedule_schema.get("$id") == "gate14re-me-load-qualification-schedule-row-v1" and schedule_boundary.get("scheduleRowsGenerated") == 0 and schedule_boundary.get("scheduleGenerationAuthorized") is False and schedule_boundary.get("identityBindingGenerated") is False and schedule_boundary.get("qualificationExecutionAuthorized") is False, "schedule-schema-zero-generation", "schedule schema is frozen without generating a schedule, identity map or execution authority")
    checks.require(schedule_schema.get("required") == csharp_public_fields(contracts_text, "Gate14ReMEQualificationScheduleRowV1"), "schedule-csharp-row-fields", "schedule-row schema required fields exactly match the C# schedule-row contract")
    checks.require(schedule_schema.get("$defs", {}).get("lane", {}).get("required") == csharp_public_fields(contracts_text, "Gate14ReMEQualificationScheduleLaneV1"), "schedule-csharp-lane-fields", "schedule lane schema exactly matches the C# lane contract")
    checks.require(schedule_schema.get("$defs", {}).get("replacement", {}).get("required") == csharp_public_fields(contracts_text, "Gate14ReMEQualificationReplacementV1"), "schedule-csharp-replacement-fields", "schedule replacement schema exactly matches the C# replacement contract")
    checks.require([item.get("tableId") for item in output_schema.get("rawTables", [])] == ["oracle-agent-checks", "oracle-event-checks", "operations", "event-groups", "persistent-state", "process-resources", "empty-boundary", "replacement-ledger", "failures-and-voids"], "output-table-set", "complete per-observation raw table set exact")
    raw_class_by_table = {
        "oracle-agent-checks": "Gate14ReMEOracleAgentRawV1",
        "oracle-event-checks": "Gate14ReMEOracleEventRawV1",
        "operations": "Gate14ReMEOperationRawV1",
        "event-groups": "Gate14ReMEEventGroupRawV1",
        "persistent-state": "Gate14ReMEPersistentStateRawV1",
        "process-resources": "Gate14ReMEProcessResourceRawV1",
        "empty-boundary": "Gate14ReMEEmptyBoundaryRawV1",
    }
    output_specs = {item["tableId"]: item for item in output_schema.get("rawTables", [])}
    for table_id, class_name in raw_class_by_table.items():
        checks.require(output_specs[table_id].get("requiredFields") == csharp_public_fields(contracts_text, class_name), f"output-csharp-fields:{table_id}", "output required fields exactly match the serialized C# raw-row contract")
    checks.require(output_specs["replacement-ledger"].get("requiredFields") == ["recordId", "plannedSuperblockId", "replacementSuperblockId", "replacementOrdinal", "reason", "createdAtUtc"], "output-fields:replacement-ledger", "replacement ledger has a complete per-row delivery contract")
    checks.require(output_specs["failures-and-voids"].get("requiredFields") == ["recordId", "plannedSuperblockId", "instanceId", "isReplacement", "status", "reason", "createdAtUtc"], "output-fields:failures-and-voids", "failure/void ledger has a complete per-row delivery contract")
    checks.require("accepted-superblock-receipt.v1.json" in output_schema.get("receipts", []) and "_control/acquisition-complete.v1.json" in output_schema.get("receipts", []), "output-control-receipts", "accepted-superblock and acquisition-complete receipts are explicitly retained")
    checks.require(output_schema.get("deliveryViews", {}).get("aggregateOnlyAllowed") is False and output_schema.get("currentStageEvidence", {}).get("rawRowsCreated") == 0, "output-no-aggregate-zero-rows", "aggregate-only delivery forbidden and no rows created")
    checks.require([item.get("endpointId") for item in instrument.get("endpoints", [])] == ["D1", "D2", "D3", "D4"], "instrument-endpoints", "D1 through D4 exact")
    checks.require(instrument.get("currentStageEvidence", {}).get("unityCompilationPerformed") is False and instrument.get("currentStageEvidence", {}).get("runtimeKnownAnswerTestsPerformed") is False, "instrument-runtime-unperformed", "runtime instrument evidence is not fabricated")
    checks.require(execution.get("currentAuthorization", {}).get("qualificationExecutionAuthorized") is False and execution.get("currentEvidence", {}).get("UnityProcessesLaunched") == 0, "execution-unauthorized-zero", "execution remains unauthorized with zero launches")

    delivery_path = PROJECT_ROOT / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v1.py"
    delivery_namespace: Dict[str, Any] = {
        "__name__": "gate14re_me_delivery_self_test",
        "__file__": str(delivery_path),
    }
    exec(compile(delivery_path.read_text(encoding="utf-8"), str(delivery_path), "exec"), delivery_namespace)
    checks.require(callable(delivery_namespace.get("self_test")), "delivery-import", "delivery source can be loaded without bytecode for source-level controls")
    self_test = delivery_namespace["self_test"]()
    checks.require(self_test.get("jsonlCsvGzipRoundTripPassed") is True, "delivery-jsonl-csv-gzip", "source-level JSONL/CSV/gzip round trip passes")
    for field in ("tamperNegativeTestPassed", "missingNegativeTestPassed", "duplicateNegativeTestPassed", "anonymousLabelSwapNegativeTestPassed"):
        checks.require(self_test.get(field) is True, f"delivery-negative:{field}", "delivery negative control passes")
    checks.require(self_test.get("typedParquetEngineAvailable") is False and self_test.get("status") == "BLOCKED_TYPED_PARQUET_DEPENDENCY_MISSING", "delivery-parquet-blocker", "missing typed-Parquet dependency is detected and fails closed")

    status = read_json("Research/Gate14Re-ME/Gate14Re_ME_Status.v3.json")
    checks.require(status.get("status") == "QUALIFICATION_IMPLEMENTATION_SOURCE_FROZEN_EXECUTION_NOT_AUTHORIZED", "status-v3", "status accurately reports source-only freeze")
    boundary = status.get("currentEvidenceBoundary", {})
    checks.require(all(boundary.get(key) in (False, 0) for key in ("qualificationRootExists", "formalRootExists", "analysisRootExists", "exportsRootExists", "qualificationInputsGenerated", "qualificationObservationCount", "formalObservationCount", "UnityProcessesLaunched", "Gate14ReOrTB2OutcomesReadOrReused")), "status-zero-boundary", "status records no roots, inputs, observations, Unity or prior-outcome reuse")

    for relative in (
        "Research/PilotRuns/Gate14Re-ME",
        "Research/FormalRuns/Gate14Re-ME",
        "Research/Analysis/Gate14Re-ME",
        "Research/Exports/Gate14Re-ME",
    ):
        checks.require(not (PROJECT_ROOT / relative).exists(), f"absent-root:{relative}", "unauthorized measured/analysis/export root absent")

    process_query = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$p=@(Get-CimInstance Win32_Process -Filter \"Name = 'Unity.exe'\" | ?{$_.CommandLine -like '*Gate14ReMELoadQualificationRunnerV1*' -or $_.CommandLine -like '*Research/PilotRuns/Gate14Re-ME*'});$p.Count",
        ],
        capture_output=True,
        text=True,
    )
    checks.require(process_query.returncode == 0 and process_query.stdout.strip().endswith("0"), "no-gate14reme-unity-process", "no corresponding Unity process exists")

    manifest = read_json(MANIFEST_RELATIVE)
    checks.require(manifest.get("schema") == "gate14re-me-qualification-implementation-manifest-v1" and manifest.get("status") == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED", "manifest-identity", "implementation manifest identity/status exact")
    entries = manifest.get("artifacts", [])
    paths = {entry.get("relativePath") for entry in entries}
    checks.require(paths == EXPECTED_ARTIFACTS, "manifest-artifact-set", "implementation manifest contains the exact source-only artifact set")
    for entry in entries:
        relative = entry["relativePath"]
        path = PROJECT_ROOT / relative
        checks.require(path.is_file(), f"manifest-exists:{relative}", "manifest artifact exists")
        checks.require(sha256_file(path) == entry.get("sha256"), f"manifest-hash:{relative}", "manifest artifact SHA-256 exact")
        checks.require(path.stat().st_size == entry.get("bytes"), f"manifest-bytes:{relative}", "manifest artifact byte count exact")
        checks.require(is_read_only(path), f"manifest-readonly:{relative}", "manifest artifact is read-only")
    checks.require(is_read_only(PROJECT_ROOT / MANIFEST_RELATIVE), "manifest-readonly", "implementation manifest itself is read-only")

    return {
        "schema": "gate14re-me-qualification-implementation-freeze-validation-v1",
        "studyId": "Gate14Re-ME",
        "status": "PASS_SOURCE_ONLY_IMPLEMENTATION_FREEZE",
        "checksPassed": len(checks.items),
        "checksFailed": 0,
        "unityCompilationPerformed": False,
        "UnityProcessesLaunched": 0,
        "runtimeInstrumentQualificationPerformed": False,
        "qualificationInputsGenerated": 0,
        "qualificationObservationCount": 0,
        "formalObservationCount": 0,
        "typedParquetEngineAvailable": False,
        "formalAnalysisPerformed": False,
        "rankingOrWinnerComputed": False,
        "checks": checks.items,
    }


def main() -> int:
    try:
        result = validate()
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"schema": "gate14re-me-qualification-implementation-freeze-validation-v1", "status": "FAIL_CLOSED", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
