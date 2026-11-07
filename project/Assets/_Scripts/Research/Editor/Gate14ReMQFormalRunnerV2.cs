#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.MQ.V1;
using DDM.Research.MQ.V2;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    [Serializable]
    public sealed class Gate14ReMQFormalScheduleRowV2
    {
        public string schema;
        public int processOrdinal;
        public int blockOrdinal;
        public string blockId;
        public int positionWithinBlock;
        public int conditionIndex;
        public string opaqueAlgorithmSlot;
        public int withinAlgorithmConditionIndex;
        public string conditionId;
        public string executorMode;
        public string topologyRole;
        public int workerCount;
        public string affinityPlanId;
        public string analysisRole;
        public int inputAssignmentRowOrdinal;
        public int scheduleSeed;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalInputBindingV2
    {
        public int sourceOrdinal;
        public string sourceInputId;
        public string sourceSuperblockId;
        public int gridEdge;
        public int agentCount;
        public int changedCellCount;
        public string sourceRelativePath;
        public string sourceSha256;
        public string oracleCacheBindingRelativePath;
        public string oracleCacheBindingSha256;
        public string oraclePassReceiptRelativePath;
        public string oraclePassReceiptSha256;
        public string oracleAgentTableRelativePath;
        public string oracleAgentTableSha256;
        public int oracleAgentTableRows;
        public string oracleEventTableRelativePath;
        public string oracleEventTableSha256;
        public int oracleEventTableRows;
        public int laneOrdinal;
        public string formalInputAlias;
        public string cellId;
        public int cellOccurrenceOrdinal;
        public int sourceReplicaIndexWithinCell;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalBlockInputRowV2
    {
        public string schema;
        public int blockOrdinal;
        public string blockId;
        public int scheduleSeed;
        public int laneCount;
        public Gate14ReMQFormalInputBindingV2[] inputs;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalAlgorithmBindingV2
    {
        public string opaqueAlgorithmSlot;
        public string algorithmId;
        public string implementationRelativePath;
        public string implementationSha256;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalIdentityMapV2
    {
        public string schema;
        public string studyId;
        public string designId;
        public string status;
        public bool mappingOpenedOnlyAfterPowerSelectionSealed;
        public Gate14ReMQFormalAlgorithmBindingV2[] algorithms;
        public bool formalEffectDataRead;
        public bool formalAnalysisStarted;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalManifestRowV2
    {
        public string role;
        public string relativePath;
        public long bytes;
        public string sha256;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalImplementationManifestV2
    {
        public string schema;
        public string studyId;
        public string designId;
        public string status;
        public Gate14ReMQFormalManifestRowV2[] artifacts;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalExecutionAuthorizationV2
    {
        public string schema;
        public string studyId;
        public string designId;
        public string authorizationId;
        public string status;
        public string measuredRootRelativePath;
        public string implementationManifestSha256;
        public string executionContractSha256;
        public string scheduleSha256;
        public string blockInputAssignmentsSha256;
        public string identityMapSha256;
        public string fairnessBindingSha256;
        public string resourceBudgetSha256;
        public string unityExecutableSha256;
        public bool formalCollectionAuthorized;
        public bool formalAnalysisAuthorized;
        public bool mqOnly;
    }

    [Serializable]
    public sealed class Gate14ReMQFormalReadinessSummaryV2
    {
        public int scheduleRows;
        public int blockRows;
        public int sourceInputReferences;
        public int distinctSourceInputs;
        public int distinctStructuralCells;
        public int oracleCacheBindingsVerified;
        public int minimumConditionPositionCount;
        public int maximumConditionPositionCount;
    }

    [Serializable]
    internal sealed class Gate14ReMQFormalOracleCacheBindingV2
    {
        public string schema;
        public string status;
        public string inputId;
        public string superblockId;
        public string inputRelativePath;
        public string inputSha256;
        public string oracleSourceRelativePath;
        public string oracleSourceSha256;
        public string oraclePassReceiptRelativePath;
        public string oraclePassReceiptSha256;
        public string agentTableRelativePath;
        public string agentTableSha256;
        public int agentTableRows;
        public string eventTableRelativePath;
        public string eventTableSha256;
        public int eventTableRows;
    }

    [Serializable]
    internal sealed class Gate14ReMQFormalLaneEvidenceV2
    {
        public string schema;
        public int processOrdinal;
        public int blockOrdinal;
        public string blockId;
        public int laneOrdinal;
        public string formalInputAlias;
        public string cellId;
        public string sourceInputId;
        public string sourceSuperblockId;
        public string sourceSha256;
        public string opaqueAlgorithmSlot;
        public string conditionId;
        public MultiQueryLaneRuntimeV1 executorRuntime;
        public int totalQueryCount;
        public int repairCount;
        public double initializationWallMilliseconds;
        public double workloadWallMilliseconds;
        public string workloadStartUtc;
        public string workloadEndUtc;
        public string terminalSemanticDigestSha256;
        public int oracleComparedQueryCount;
        public bool oracleHardGatePassed;
        public string oracleCacheBindingSha256;
    }

    [Serializable]
    internal sealed class Gate14ReMQFormalBatchEvidenceV2
    {
        public string schema;
        public int processOrdinal;
        public int blockOrdinal;
        public string blockId;
        public int positionWithinBlock;
        public string opaqueAlgorithmSlot;
        public string conditionId;
        public string executorMode;
        public string topologyRole;
        public int workerCount;
        public int laneCount;
        public double batchWallMilliseconds;
        public double batchWallSeconds;
        public double processCpuMilliseconds;
        public double workerPoolSetupMilliseconds;
        public bool allAffinityBindingsObserved;
        public bool allLanesComplete;
        public bool allOracleHardGatesPassed;
        public MultiQueryBatchRuntimeV1 runtime;
    }

    [Serializable]
    internal sealed class Gate14ReMQFormalProcessReceiptV2
    {
        public string schema;
        public string studyId;
        public string designId;
        public string authorizationId;
        public string status;
        public int processOrdinal;
        public int blockOrdinal;
        public string blockId;
        public string opaqueAlgorithmSlot;
        public string conditionId;
        public int workerCount;
        public int laneCount;
        public int oracleComparedQueryCount;
        public bool allCorrectnessAndOracleHardGatesPassed;
        public bool allAffinityBindingsObserved;
        public bool completeBatch;
        public string scheduleSha256;
        public string blockInputAssignmentsSha256;
        public string identityMapSha256;
        public string implementationManifestSha256;
        public string executionContractSha256;
        public string fairnessBindingSha256;
        public string resourceBudgetSha256;
        public string unityExecutableSha256;
        public string laneEvidenceSha256;
        public string batchEvidenceSha256;
        public string outputManifestSha256;
        public bool formalAnalysisStarted;
        public string completedAtUtc;
    }

    /// <summary>
    /// Executes exactly one frozen process-schedule row. The outer PowerShell
    /// supervisor is responsible for strict serial fresh-process execution.
    /// No retry, resume, replacement, top-up, skip, merge, or reorder path exists.
    /// </summary>
    public static class Gate14ReMQFormalRunnerV2
    {
        public const int MatchedBlockCount = 36;
        public const int LanesPerBlock = 16;
        public const int ConditionsPerBlock = 24;
        public const int FormalProcessCount = 864;
        public const int EventGroupCount = 24;
        public const int ScheduleSeed = 141420273;
        public const string RunnerRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMQFormalRunnerV2.cs";
        public const string KernelRelativePath = "Assets/_Scripts/Research/MQ/v2/Gate14ReMQFormalPerformanceKernelV2.cs";
        private const int BurstCompletionTimeoutMilliseconds = 300000;
        private const string ReservedMeasuredParent = "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/";
        private const string AffinityPlansRelativePath = "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001/output/affinity-plans.v1.json";

        public static void Run()
        {
            string outputDirectory = null;
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = NormalizeDirectory(Directory.GetParent(Application.dataPath).FullName);
                ExecutionContext context = ValidateExecutionContext(projectRoot, arguments);
                int processOrdinal = ParseOrdinal(Required(arguments, "--g14mq-process-ordinal"));
                Gate14ReMQFormalScheduleRowV2 scheduleRow = context.ScheduleRows[processOrdinal];
                Gate14ReMQFormalBlockInputRowV2 blockRow = context.BlockRows[scheduleRow.blockOrdinal];
                outputDirectory = ResolveOutputDirectory(
                    projectRoot,
                    context.MeasuredRoot,
                    Required(arguments, "--g14mq-output-dir"),
                    scheduleRow);
                EnsureNewOutputDirectory(outputDirectory);
                ExecuteOneProcess(context, scheduleRow, blockRow, outputDirectory);
                // Output is already frozen.  Wait only on Burst's host-lifecycle
                // predicate before unloading the editor domain; this is outside
                // every measured interval and prevents the known shutdown race.
                Gate14ReMEBurstHostLifecycleV1.WaitResult burstWait =
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(BurstCompletionTimeoutMilliseconds);
                Require(burstWait.finalCompilationDone,
                    "Burst current compilation did not finish before formal MQ process shutdown.");
                exitCode = 0;
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
                TryWriteFailure(outputDirectory, exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        public static Gate14ReMQFormalReadinessSummaryV2 ValidateFrozenDesignForReadiness(
            string projectRoot,
            string schedulePath,
            string scheduleSha256,
            string blockInputsPath,
            string blockInputsSha256,
            string identityMapPath,
            string identityMapSha256,
            string executionContractPath,
            string executionContractSha256,
            string fairnessPath,
            string fairnessSha256,
            string resourceBudgetPath,
            string resourceBudgetSha256,
            string implementationManifestPath,
            string implementationManifestSha256)
        {
            RequireFileHash(schedulePath, scheduleSha256, "schedule");
            RequireFileHash(blockInputsPath, blockInputsSha256, "block-input assignments");
            RequireFileHash(identityMapPath, identityMapSha256, "identity map");
            RequireFileHash(executionContractPath, executionContractSha256, "execution contract");
            RequireFileHash(fairnessPath, fairnessSha256, "fairness binding");
            RequireFileHash(resourceBudgetPath, resourceBudgetSha256, "resource budget");
            RequireFileHash(implementationManifestPath, implementationManifestSha256, "implementation manifest");
            RequireJsonMarkers(executionContractPath, "gate14re-mq-formal-execution-contract-v2",
                "FROZEN_EXECUTION_CONTRACT_REQUIRES_SEPARATE_LAUNCH_AUTHORIZATION");
            RequireJsonMarkers(fairnessPath, "gate14re-mq-formal-fairness-and-topology-binding-v2",
                "FROZEN_FAIRNESS_TOPOLOGY_AND_ASSIGNMENT");
            RequireJsonMarkers(resourceBudgetPath, "gate14re-mq-formal-resource-budget-v2",
                "FROZEN_RESOURCE_AND_TIMEOUT_GATES");

            Gate14ReMQFormalImplementationManifestV2 manifest = ReadJson<Gate14ReMQFormalImplementationManifestV2>(implementationManifestPath);
            ValidateImplementationManifest(projectRoot, manifest);
            RequireManifestBinding(manifest, RelativePath(projectRoot, schedulePath), scheduleSha256);
            RequireManifestBinding(manifest, RelativePath(projectRoot, blockInputsPath), blockInputsSha256);
            RequireManifestBinding(manifest, RelativePath(projectRoot, identityMapPath), identityMapSha256);
            RequireManifestBinding(manifest, RelativePath(projectRoot, executionContractPath), executionContractSha256);
            RequireManifestBinding(manifest, RelativePath(projectRoot, fairnessPath), fairnessSha256);
            RequireManifestBinding(manifest, RelativePath(projectRoot, resourceBudgetPath), resourceBudgetSha256);
            RequireManifestBinding(manifest, RunnerRelativePath, Sha256File(Path.Combine(projectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar))));
            RequireManifestBinding(manifest, KernelRelativePath, Sha256File(Path.Combine(projectRoot, KernelRelativePath.Replace('/', Path.DirectorySeparatorChar))));

            Gate14ReMQFormalScheduleRowV2[] scheduleRows = ReadSchedule(schedulePath);
            Gate14ReMQFormalBlockInputRowV2[] blockRows = ReadJsonLines<Gate14ReMQFormalBlockInputRowV2>(blockInputsPath);
            Gate14ReMQFormalIdentityMapV2 identityMap = ReadJson<Gate14ReMQFormalIdentityMapV2>(identityMapPath);
            ValidateIdentityMap(projectRoot, identityMap);
            int minimumPosition;
            int maximumPosition;
            ValidateSchedule(scheduleRows, out minimumPosition, out maximumPosition);
            BlockValidationSummary blockSummary = ValidateBlocks(projectRoot, blockRows, true);
            return new Gate14ReMQFormalReadinessSummaryV2
            {
                scheduleRows = scheduleRows.Length,
                blockRows = blockRows.Length,
                sourceInputReferences = blockSummary.SourceInputReferences,
                distinctSourceInputs = blockSummary.DistinctSourceInputs,
                distinctStructuralCells = blockSummary.DistinctCells,
                oracleCacheBindingsVerified = blockSummary.OracleBindings,
                minimumConditionPositionCount = minimumPosition,
                maximumConditionPositionCount = maximumPosition
            };
        }

        private static void ExecuteOneProcess(
            ExecutionContext context,
            Gate14ReMQFormalScheduleRowV2 scheduleRow,
            Gate14ReMQFormalBlockInputRowV2 blockRow,
            string outputDirectory)
        {
            Gate14ReMQFormalAlgorithmBindingV2 algorithm = FindAlgorithm(context.IdentityMap, scheduleRow.opaqueAlgorithmSlot);
            Gate13RMQAffinityPlanSetV1 planSet = ReadJson<Gate13RMQAffinityPlanSetV1>(
                ResolveExistingFile(context.ProjectRoot, AffinityPlansRelativePath));
            Require(planSet != null && planSet.plans != null && planSet.plans.Length == 10,
                "Frozen affinity-plan set cardinality is invalid.");
            CpuAffinityPlanV1 plan = FindPlan(planSet.plans, scheduleRow.affinityPlanId);
            Require(plan.workerCount == scheduleRow.workerCount && plan.topologyRole == scheduleRow.topologyRole,
                "Schedule row differs from its frozen affinity plan.");

            LoadedLane[] lanes = LoadBlockLanes(context.ProjectRoot, blockRow);
            ManagedMultiQueryWorkItemV1<Gate14ReMQFormalLaneResultV2>[] work =
                new ManagedMultiQueryWorkItemV1<Gate14ReMQFormalLaneResultV2>[lanes.Length];
            for (int index = 0; index < lanes.Length; index++)
            {
                int captured = index;
                work[index] = new ManagedMultiQueryWorkItemV1<Gate14ReMQFormalLaneResultV2>(
                    index,
                    blockRow.inputs[index].formalInputAlias,
                    delegate
                    {
                        Gate14ReMEQualificationInputBundleV1 privateInput = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(lanes[captured].InputJson);
                        Require(privateInput != null, "Private formal MQ input deserialization failed.");
                        return Gate14ReMQFormalPerformanceKernelV2.Run(
                            privateInput,
                            blockRow.inputs[captured].sourceSha256,
                            algorithm.algorithmId);
                    });
            }

            string batchId = context.Authorization.authorizationId + ":P" +
                scheduleRow.processOrdinal.ToString("D4", CultureInfo.InvariantCulture);
            MultiQueryBatchExecutionV1<Gate14ReMQFormalLaneResultV2> execution =
                scheduleRow.executorMode == "direct"
                    ? DirectMultiQueryExecutorV1.Execute(batchId, work, plan, Fingerprint)
                    : ManagedMultiQueryExecutorV1.Execute(batchId, work, plan, Fingerprint);
            Require(execution != null && execution.Runtime != null && execution.Runtime.succeeded,
                "Formal MQ batch failed closed: " +
                (execution == null || execution.Runtime == null ? "missing runtime" : execution.Runtime.firstFailure));
            Require(execution.Values != null && execution.Values.Length == LanesPerBlock &&
                    execution.Runtime.lanes != null && execution.Runtime.lanes.Length == LanesPerBlock &&
                    execution.Runtime.completedLaneCount == LanesPerBlock && execution.Runtime.failedLaneCount == 0 &&
                    execution.Runtime.skippedLaneCount == 0,
                "Formal MQ batch is incomplete.");
            bool allAffinity = ValidateAffinity(execution.Runtime, scheduleRow);

            string laneEvidencePath = Path.Combine(outputDirectory, "formal-lanes.raw.v2.jsonl");
            string batchEvidencePath = Path.Combine(outputDirectory, "formal-batch.raw.v2.json");
            InitializeEmptyFile(laneEvidencePath);
            int oracleCompared = 0;
            for (int laneIndex = 0; laneIndex < LanesPerBlock; laneIndex++)
            {
                Gate14ReMQFormalLaneResultV2 value = execution.Values[laneIndex];
                ValidateLaneResult(value, lanes[laneIndex], algorithm.algorithmId);
                int compared = ValidateAgainstOracle(value, lanes[laneIndex]);
                oracleCompared = checked(oracleCompared + compared);
                AppendJsonLine(laneEvidencePath, new Gate14ReMQFormalLaneEvidenceV2
                {
                    schema = "gate14re-mq-formal-lane-evidence-v2",
                    processOrdinal = scheduleRow.processOrdinal,
                    blockOrdinal = scheduleRow.blockOrdinal,
                    blockId = scheduleRow.blockId,
                    laneOrdinal = laneIndex,
                    formalInputAlias = lanes[laneIndex].Binding.formalInputAlias,
                    cellId = lanes[laneIndex].Binding.cellId,
                    sourceInputId = lanes[laneIndex].Binding.sourceInputId,
                    sourceSuperblockId = lanes[laneIndex].Binding.sourceSuperblockId,
                    sourceSha256 = lanes[laneIndex].Binding.sourceSha256,
                    opaqueAlgorithmSlot = scheduleRow.opaqueAlgorithmSlot,
                    conditionId = scheduleRow.conditionId,
                    executorRuntime = execution.Runtime.lanes[laneIndex],
                    totalQueryCount = value.totalQueryCount,
                    repairCount = value.repairCount,
                    initializationWallMilliseconds = value.initializationWallMilliseconds,
                    workloadWallMilliseconds = value.workloadWallMilliseconds,
                    workloadStartUtc = value.workloadStartUtc,
                    workloadEndUtc = value.workloadEndUtc,
                    terminalSemanticDigestSha256 = value.terminalSemanticDigestSha256,
                    oracleComparedQueryCount = compared,
                    oracleHardGatePassed = true,
                    oracleCacheBindingSha256 = lanes[laneIndex].Binding.oracleCacheBindingSha256
                });
            }

            WriteJsonAtomic(batchEvidencePath, new Gate14ReMQFormalBatchEvidenceV2
            {
                schema = "gate14re-mq-formal-batch-evidence-v2",
                processOrdinal = scheduleRow.processOrdinal,
                blockOrdinal = scheduleRow.blockOrdinal,
                blockId = scheduleRow.blockId,
                positionWithinBlock = scheduleRow.positionWithinBlock,
                opaqueAlgorithmSlot = scheduleRow.opaqueAlgorithmSlot,
                conditionId = scheduleRow.conditionId,
                executorMode = scheduleRow.executorMode,
                topologyRole = scheduleRow.topologyRole,
                workerCount = scheduleRow.workerCount,
                laneCount = LanesPerBlock,
                batchWallMilliseconds = execution.Runtime.batchWallMilliseconds,
                batchWallSeconds = execution.Runtime.batchWallMilliseconds / 1000d,
                processCpuMilliseconds = execution.Runtime.processCpuMilliseconds,
                workerPoolSetupMilliseconds = execution.Runtime.workerPoolSetupMilliseconds,
                allAffinityBindingsObserved = allAffinity,
                allLanesComplete = true,
                allOracleHardGatesPassed = true,
                runtime = execution.Runtime
            });

            string outputManifestPath = Path.Combine(outputDirectory, "output-freeze-manifest.v2.json");
            WriteOutputManifest(outputManifestPath, new[] { laneEvidencePath, batchEvidencePath });
            string receiptPath = Path.Combine(outputDirectory, "process-terminal-receipt.v2.json");
            WriteJsonAtomic(receiptPath, new Gate14ReMQFormalProcessReceiptV2
            {
                schema = "gate14re-mq-formal-process-terminal-receipt-v2",
                studyId = "Gate14Re-MQ-CFF-IDFF",
                designId = "gate14re-mq-cff-idff-formal-v2",
                authorizationId = context.Authorization.authorizationId,
                status = "PASS_ONE_FROZEN_FORMAL_MQ_PROCESS",
                processOrdinal = scheduleRow.processOrdinal,
                blockOrdinal = scheduleRow.blockOrdinal,
                blockId = scheduleRow.blockId,
                opaqueAlgorithmSlot = scheduleRow.opaqueAlgorithmSlot,
                conditionId = scheduleRow.conditionId,
                workerCount = scheduleRow.workerCount,
                laneCount = LanesPerBlock,
                oracleComparedQueryCount = oracleCompared,
                allCorrectnessAndOracleHardGatesPassed = true,
                allAffinityBindingsObserved = allAffinity,
                completeBatch = true,
                scheduleSha256 = context.Authorization.scheduleSha256,
                blockInputAssignmentsSha256 = context.Authorization.blockInputAssignmentsSha256,
                identityMapSha256 = context.Authorization.identityMapSha256,
                implementationManifestSha256 = context.Authorization.implementationManifestSha256,
                executionContractSha256 = context.Authorization.executionContractSha256,
                fairnessBindingSha256 = context.Authorization.fairnessBindingSha256,
                resourceBudgetSha256 = context.Authorization.resourceBudgetSha256,
                unityExecutableSha256 = context.Authorization.unityExecutableSha256,
                laneEvidenceSha256 = Sha256File(laneEvidencePath),
                batchEvidenceSha256 = Sha256File(batchEvidencePath),
                outputManifestSha256 = Sha256File(outputManifestPath),
                formalAnalysisStarted = false,
                completedAtUtc = DateTimeOffset.UtcNow.ToString("o")
            });
        }

        private static ExecutionContext ValidateExecutionContext(string projectRoot, Dictionary<string, string> arguments)
        {
            string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-execution-authorization"));
            string authorizationSha = RequiredSha256(arguments, "--g14mq-execution-authorization-sha256");
            RequireFileHash(authorizationPath, authorizationSha, "execution authorization");
            Gate14ReMQFormalExecutionAuthorizationV2 authorization = ReadJson<Gate14ReMQFormalExecutionAuthorizationV2>(authorizationPath);
            Require(authorization.schema == "gate14re-mq-formal-execution-authorization-v2" &&
                    authorization.studyId == "Gate14Re-MQ-CFF-IDFF" &&
                    authorization.designId == "gate14re-mq-cff-idff-formal-v2" &&
                    authorization.status == "AUTHORIZED_FORMAL_MQ_COLLECTION_ONE_ATTEMPT" &&
                    authorization.formalCollectionAuthorized && !authorization.formalAnalysisAuthorized && authorization.mqOnly &&
                    IsSha256(authorization.unityExecutableSha256),
                "Execution authorization is absent, out of scope, or does not authorize exactly one formal MQ collection attempt.");

            string measuredRoot = ResolveMeasuredRoot(projectRoot, Required(arguments, "--g14mq-measured-root"));
            Require(RelativePath(projectRoot, measuredRoot) == authorization.measuredRootRelativePath.Replace('\\', '/').TrimEnd('/'),
                "Measured root differs from the authorization receipt.");
            string manifestPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-implementation-manifest"));
            string manifestSha = RequiredSha256(arguments, "--g14mq-implementation-manifest-sha256");
            string contractPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-execution-contract"));
            string contractSha = RequiredSha256(arguments, "--g14mq-execution-contract-sha256");
            string schedulePath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-schedule"));
            string scheduleSha = RequiredSha256(arguments, "--g14mq-schedule-sha256");
            string blockPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-block-inputs"));
            string blockSha = RequiredSha256(arguments, "--g14mq-block-inputs-sha256");
            string identityPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-identity-map"));
            string identitySha = RequiredSha256(arguments, "--g14mq-identity-map-sha256");
            string fairnessPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-fairness"));
            string fairnessSha = RequiredSha256(arguments, "--g14mq-fairness-sha256");
            string budgetPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14mq-resource-budget"));
            string budgetSha = RequiredSha256(arguments, "--g14mq-resource-budget-sha256");
            Require(manifestSha == authorization.implementationManifestSha256 &&
                    contractSha == authorization.executionContractSha256 &&
                    scheduleSha == authorization.scheduleSha256 &&
                    blockSha == authorization.blockInputAssignmentsSha256 &&
                    identitySha == authorization.identityMapSha256 &&
                    fairnessSha == authorization.fairnessBindingSha256 &&
                    budgetSha == authorization.resourceBudgetSha256,
                "One or more launch arguments differ from the authorization-bound hashes.");

            // The independent prelaunch-readiness pass performs the exhaustive
            // 576-reference input/oracle hash audit once.  A formal process must
            // still fail closed on every globally frozen artifact and on the 16
            // input/oracle bindings it actually consumes, but repeating the full
            // audit in each of 864 fresh processes would add avoidable I/O outside
            // the measured workload.  Keep the global structural checks here and
            // let LoadBlockLanes perform the complete current-block hash and
            // correctness/oracle validation immediately before execution.
            RequireFileHash(schedulePath, scheduleSha, "schedule");
            RequireFileHash(blockPath, blockSha, "block-input assignments");
            RequireFileHash(identityPath, identitySha, "identity map");
            RequireFileHash(contractPath, contractSha, "execution contract");
            RequireFileHash(fairnessPath, fairnessSha, "fairness binding");
            RequireFileHash(budgetPath, budgetSha, "resource budget");
            RequireFileHash(manifestPath, manifestSha, "implementation manifest");
            RequireJsonMarkers(contractPath, "gate14re-mq-formal-execution-contract-v2",
                "FROZEN_EXECUTION_CONTRACT_REQUIRES_SEPARATE_LAUNCH_AUTHORIZATION");
            RequireJsonMarkers(fairnessPath, "gate14re-mq-formal-fairness-and-topology-binding-v2",
                "FROZEN_FAIRNESS_TOPOLOGY_AND_ASSIGNMENT");
            RequireJsonMarkers(budgetPath, "gate14re-mq-formal-resource-budget-v2",
                "FROZEN_RESOURCE_AND_TIMEOUT_GATES");

            Gate14ReMQFormalImplementationManifestV2 manifest = ReadJson<Gate14ReMQFormalImplementationManifestV2>(manifestPath);
            ValidateImplementationManifest(projectRoot, manifest);
            RequireManifestBinding(manifest, RelativePath(projectRoot, schedulePath), scheduleSha);
            RequireManifestBinding(manifest, RelativePath(projectRoot, blockPath), blockSha);
            RequireManifestBinding(manifest, RelativePath(projectRoot, identityPath), identitySha);
            RequireManifestBinding(manifest, RelativePath(projectRoot, contractPath), contractSha);
            RequireManifestBinding(manifest, RelativePath(projectRoot, fairnessPath), fairnessSha);
            RequireManifestBinding(manifest, RelativePath(projectRoot, budgetPath), budgetSha);
            RequireManifestBinding(manifest, RunnerRelativePath,
                Sha256File(Path.Combine(projectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar))));
            RequireManifestBinding(manifest, KernelRelativePath,
                Sha256File(Path.Combine(projectRoot, KernelRelativePath.Replace('/', Path.DirectorySeparatorChar))));
            Gate14ReMQFormalScheduleRowV2[] scheduleRows = ReadSchedule(schedulePath);
            Gate14ReMQFormalBlockInputRowV2[] blockRows = ReadJsonLines<Gate14ReMQFormalBlockInputRowV2>(blockPath);
            Gate14ReMQFormalIdentityMapV2 identityMap = ReadJson<Gate14ReMQFormalIdentityMapV2>(identityPath);
            ValidateIdentityMap(projectRoot, identityMap);
            int minimumPosition;
            int maximumPosition;
            ValidateSchedule(scheduleRows, out minimumPosition, out maximumPosition);
            ValidateBlocks(projectRoot, blockRows, false);
            return new ExecutionContext(projectRoot, measuredRoot, authorization, scheduleRows, blockRows, identityMap);
        }

        private static void ValidateImplementationManifest(string projectRoot, Gate14ReMQFormalImplementationManifestV2 manifest)
        {
            Require(manifest != null && manifest.schema == "gate14re-mq-formal-implementation-manifest-v2" &&
                    manifest.status == "FROZEN_IMPLEMENTATION_AND_SCHEDULE_READY_FOR_SEPARATE_LAUNCH_AUTHORIZATION" &&
                    manifest.studyId == "Gate14Re-MQ-CFF-IDFF" && manifest.designId == "gate14re-mq-cff-idff-formal-v2" &&
                    manifest.artifacts != null && manifest.artifacts.Length >= 15,
                "Formal MQ implementation manifest is invalid.");
            HashSet<string> paths = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < manifest.artifacts.Length; index++)
            {
                Gate14ReMQFormalManifestRowV2 row = manifest.artifacts[index];
                Require(row != null && !string.IsNullOrWhiteSpace(row.relativePath) && IsSha256(row.sha256) && paths.Add(row.relativePath),
                    "Implementation-manifest row is null, invalid, or duplicated.");
                string path = ResolveExistingFile(projectRoot, row.relativePath);
                Require(new FileInfo(path).Length == row.bytes && Sha256File(path) == row.sha256,
                    "Implementation-manifest file drift: " + row.relativePath);
            }
        }

        private static void ValidateIdentityMap(string projectRoot, Gate14ReMQFormalIdentityMapV2 identityMap)
        {
            Require(identityMap != null && identityMap.schema == "gate14re-mq-formal-opaque-algorithm-identity-map-v2" &&
                    identityMap.status == "FROZEN_AFTER_IDENTITY_BLIND_POWER_SELECTION" &&
                    identityMap.mappingOpenedOnlyAfterPowerSelectionSealed && !identityMap.formalEffectDataRead &&
                    !identityMap.formalAnalysisStarted && identityMap.algorithms != null && identityMap.algorithms.Length == 2,
                "Formal MQ identity map is invalid.");
            HashSet<string> slots = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < identityMap.algorithms.Length; index++)
            {
                Gate14ReMQFormalAlgorithmBindingV2 binding = identityMap.algorithms[index];
                Require(binding != null && slots.Add(binding.opaqueAlgorithmSlot) && algorithms.Add(binding.algorithmId) &&
                        (binding.algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField ||
                         binding.algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField),
                    "Identity map contains an invalid or duplicate algorithm binding.");
                string path = ResolveExistingFile(projectRoot, binding.implementationRelativePath);
                Require(Sha256File(path) == binding.implementationSha256,
                    "Algorithm implementation changed after identity-map freeze.");
            }
            Require(slots.Contains("OPAQUE-A") && slots.Contains("OPAQUE-B"), "Identity map must contain OPAQUE-A and OPAQUE-B.");
        }

        private static void ValidateSchedule(Gate14ReMQFormalScheduleRowV2[] rows, out int minimumPosition, out int maximumPosition)
        {
            Require(rows != null && rows.Length == FormalProcessCount, "Formal schedule must contain exactly 864 rows.");
            int[,] positions = new int[ConditionsPerBlock, ConditionsPerBlock];
            for (int block = 0; block < MatchedBlockCount; block++)
            {
                bool[] conditionSeen = new bool[ConditionsPerBlock];
                bool[] positionSeen = new bool[ConditionsPerBlock];
                for (int within = 0; within < ConditionsPerBlock; within++)
                {
                    int ordinal = block * ConditionsPerBlock + within;
                    Gate14ReMQFormalScheduleRowV2 row = rows[ordinal];
                    Require(row != null && row.schema == "gate14re-mq-formal-process-schedule-row-v2" &&
                            row.processOrdinal == ordinal && row.blockOrdinal == block &&
                            row.blockId == "MQV2-B" + (block + 1).ToString("D3", CultureInfo.InvariantCulture) &&
                            row.positionWithinBlock >= 0 && row.positionWithinBlock < ConditionsPerBlock &&
                            row.conditionIndex >= 0 && row.conditionIndex < ConditionsPerBlock &&
                            !positionSeen[row.positionWithinBlock] && !conditionSeen[row.conditionIndex] &&
                            row.inputAssignmentRowOrdinal == block && row.scheduleSeed == ScheduleSeed,
                        "Formal schedule identity, ordinal, or permutation invariant failed.");
                    positionSeen[row.positionWithinBlock] = true;
                    conditionSeen[row.conditionIndex] = true;
                    positions[row.conditionIndex, row.positionWithinBlock]++;
                    int expectedWithin = row.conditionIndex % 12;
                    string expectedSlot = row.conditionIndex < 12 ? "OPAQUE-A" : "OPAQUE-B";
                    Require(row.withinAlgorithmConditionIndex == expectedWithin && row.opaqueAlgorithmSlot == expectedSlot,
                        "Formal schedule opaque-slot mapping is invalid.");
                    ValidateCondition(row);
                }
            }
            minimumPosition = Int32.MaxValue;
            maximumPosition = Int32.MinValue;
            for (int condition = 0; condition < ConditionsPerBlock; condition++)
            for (int position = 0; position < ConditionsPerBlock; position++)
            {
                minimumPosition = Math.Min(minimumPosition, positions[condition, position]);
                maximumPosition = Math.Max(maximumPosition, positions[condition, position]);
            }
            Require(minimumPosition == 1 && maximumPosition == 2,
                "Formal schedule condition-position counts must be exactly one or two.");
        }

        private static void ValidateCondition(Gate14ReMQFormalScheduleRowV2 row)
        {
            int within = row.withinAlgorithmConditionIndex;
            string[] ids =
            {
                "ST-DIRECT-LARGE-L3", "MQ-LARGE-L3-W1", "MQ-LARGE-L3-W2", "MQ-LARGE-L3-W4", "MQ-LARGE-L3-W8",
                "ST-DIRECT-HIGH-FREQUENCY", "MQ-HIGH-FREQUENCY-W1", "MQ-HIGH-FREQUENCY-W2", "MQ-HIGH-FREQUENCY-W4", "MQ-HIGH-FREQUENCY-W8",
                "MQ-DUAL-CCD-W8-4PLUS4", "MQ-DUAL-CCD-W16-8PLUS8"
            };
            int[] workers = { 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 8, 16 };
            string[] roles =
            {
                "LARGE_L3_CCD", "LARGE_L3_CCD", "LARGE_L3_CCD", "LARGE_L3_CCD", "LARGE_L3_CCD",
                "HIGH_FREQUENCY_CCD", "HIGH_FREQUENCY_CCD", "HIGH_FREQUENCY_CCD", "HIGH_FREQUENCY_CCD", "HIGH_FREQUENCY_CCD",
                "DUAL_CCD_BALANCED", "DUAL_CCD_BALANCED"
            };
            string expectedMode = within == 0 || within == 5 ? "direct" : "managed";
            Require(row.conditionId == ids[within] && row.workerCount == workers[within] && row.topologyRole == roles[within] &&
                    row.executorMode == expectedMode &&
                    row.affinityPlanId == roles[within] + "-W" + workers[within].ToString(CultureInfo.InvariantCulture),
                "Formal schedule condition matrix drifted.");
        }

        private static BlockValidationSummary ValidateBlocks(string projectRoot, Gate14ReMQFormalBlockInputRowV2[] blocks, bool verifyAllFiles)
        {
            Require(blocks != null && blocks.Length == MatchedBlockCount, "Formal block-input file must contain exactly 36 rows.");
            Dictionary<string, int> cellCounts = new Dictionary<string, int>(StringComparer.Ordinal);
            Dictionary<string, Dictionary<string, int>> sourceCounts = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
            HashSet<string> aliases = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> sources = new HashSet<string>(StringComparer.Ordinal);
            int references = 0;
            int oracleBindings = 0;
            for (int blockIndex = 0; blockIndex < blocks.Length; blockIndex++)
            {
                Gate14ReMQFormalBlockInputRowV2 block = blocks[blockIndex];
                Require(block != null && block.schema == "gate14re-mq-formal-block-input-assignment-row-v2" &&
                        block.blockOrdinal == blockIndex && block.blockId == "MQV2-B" + (blockIndex + 1).ToString("D3", CultureInfo.InvariantCulture) &&
                        block.scheduleSeed == ScheduleSeed && block.laneCount == LanesPerBlock &&
                        block.inputs != null && block.inputs.Length == LanesPerBlock,
                    "Formal block-input row identity or cardinality is invalid.");
                HashSet<string> blockCells = new HashSet<string>(StringComparer.Ordinal);
                for (int laneIndex = 0; laneIndex < block.inputs.Length; laneIndex++)
                {
                    Gate14ReMQFormalInputBindingV2 binding = block.inputs[laneIndex];
                    Require(binding != null && binding.laneOrdinal == laneIndex && aliases.Add(binding.formalInputAlias) &&
                            blockCells.Add(binding.cellId) && IsSha256(binding.sourceSha256) &&
                            IsSha256(binding.oracleCacheBindingSha256) && IsSha256(binding.oraclePassReceiptSha256) &&
                            IsSha256(binding.oracleAgentTableSha256) && IsSha256(binding.oracleEventTableSha256),
                        "Formal block input is invalid or duplicated within its block.");
                    Increment(cellCounts, binding.cellId);
                    Dictionary<string, int> perSource;
                    if (!sourceCounts.TryGetValue(binding.cellId, out perSource))
                    {
                        perSource = new Dictionary<string, int>(StringComparer.Ordinal);
                        sourceCounts.Add(binding.cellId, perSource);
                    }
                    Increment(perSource, binding.sourceInputId);
                    sources.Add(binding.sourceInputId);
                    references++;
                    if (verifyAllFiles)
                    {
                        ValidateFrozenInputAndOracleBinding(projectRoot, binding, false);
                        oracleBindings++;
                    }
                }
                Require(blockCells.Count == LanesPerBlock, "Every formal block must contain 16 distinct GxNxF cells.");
            }
            Require(cellCounts.Count == 36, "Formal blocks must cover exactly 36 GxNxF cells.");
            foreach (KeyValuePair<string, int> pair in cellCounts)
            {
                Require(pair.Value == 16, "Every GxNxF cell must appear exactly 16 times.");
                Dictionary<string, int> perSource = sourceCounts[pair.Key];
                Require(perSource.Count == 3, "Every GxNxF cell must use exactly three source inputs.");
                List<int> counts = new List<int>(perSource.Values);
                counts.Sort();
                Require(counts[0] == 5 && counts[1] == 5 && counts[2] == 6,
                    "Each cell's three source inputs must be balanced 5/5/6.");
            }
            return new BlockValidationSummary(references, sources.Count, cellCounts.Count, oracleBindings);
        }

        private static LoadedLane[] LoadBlockLanes(string projectRoot, Gate14ReMQFormalBlockInputRowV2 block)
        {
            LoadedLane[] result = new LoadedLane[block.inputs.Length];
            for (int index = 0; index < result.Length; index++)
                result[index] = ValidateFrozenInputAndOracleBinding(projectRoot, block.inputs[index], true);
            return result;
        }

        private static LoadedLane ValidateFrozenInputAndOracleBinding(
            string projectRoot,
            Gate14ReMQFormalInputBindingV2 binding,
            bool loadOracleRows)
        {
            string inputPath = ResolveExistingFile(projectRoot, binding.sourceRelativePath);
            RequireFileHash(inputPath, binding.sourceSha256, "formal source input");
            string inputJson = File.ReadAllText(inputPath, Encoding.UTF8);
            Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(inputJson);
            Require(input != null && input.schema == Gate14ReMEQualificationConstantsV1.InputSchema &&
                    input.inputId == binding.sourceInputId && input.superblockId == binding.sourceSuperblockId &&
                    input.gridEdge == binding.gridEdge && input.agentCount == binding.agentCount &&
                    input.changedCellCount == binding.changedCellCount && input.eventGroups != null &&
                    input.eventGroups.Length == EventGroupCount,
                "Formal source input metadata differs from the frozen block assignment.");

            string cachePath = ResolveExistingFile(projectRoot, binding.oracleCacheBindingRelativePath);
            string passPath = ResolveExistingFile(projectRoot, binding.oraclePassReceiptRelativePath);
            string agentPath = ResolveExistingFile(projectRoot, binding.oracleAgentTableRelativePath);
            string eventPath = ResolveExistingFile(projectRoot, binding.oracleEventTableRelativePath);
            RequireFileHash(cachePath, binding.oracleCacheBindingSha256, "oracle cache binding");
            RequireFileHash(passPath, binding.oraclePassReceiptSha256, "oracle pass receipt");
            RequireFileHash(agentPath, binding.oracleAgentTableSha256, "oracle agent table");
            RequireFileHash(eventPath, binding.oracleEventTableSha256, "oracle event table");
            Gate14ReMQFormalOracleCacheBindingV2 cache = ReadJson<Gate14ReMQFormalOracleCacheBindingV2>(cachePath);
            Require(cache != null && cache.schema == "gate14re-me-oracle-cache-binding-receipt-v4.1" &&
                    cache.status == "PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V4_1" &&
                    cache.inputId == binding.sourceInputId && cache.superblockId == binding.sourceSuperblockId &&
                    cache.inputRelativePath.Replace('\\', '/') == binding.sourceRelativePath.Replace('\\', '/') &&
                    cache.inputSha256 == binding.sourceSha256 && cache.oraclePassReceiptSha256 == binding.oraclePassReceiptSha256 &&
                    cache.agentTableSha256 == binding.oracleAgentTableSha256 && cache.agentTableRows == binding.oracleAgentTableRows &&
                    cache.eventTableSha256 == binding.oracleEventTableSha256 && cache.eventTableRows == binding.oracleEventTableRows,
                "Oracle cache binding differs from the frozen formal input assignment.");
            Gate14ReMEOraclePassReceiptV1 pass = ReadJson<Gate14ReMEOraclePassReceiptV1>(passPath);
            Require(pass != null && pass.status == "PASS_ALGORITHM_NEUTRAL_GEOMETRY" && pass.allGeometryChecksPassed &&
                    pass.inputId == binding.sourceInputId && pass.superblockId == binding.sourceSuperblockId &&
                    pass.inputSha256 == binding.sourceSha256 && pass.agentRowCount == binding.oracleAgentTableRows &&
                    pass.eventGroupRowCount == EventGroupCount,
                "Oracle pass receipt differs from the frozen formal input assignment.");
            ValidateOracleEventRows(input, binding, eventPath);
            OracleExpected expected = loadOracleRows ? LoadOracleExpected(input, binding, agentPath) : null;
            return new LoadedLane(binding, inputJson, expected);
        }

        private static void ValidateOracleEventRows(
            Gate14ReMEQualificationInputBundleV1 input,
            Gate14ReMQFormalInputBindingV2 binding,
            string path)
        {
            Gate14ReMEOracleEventRawV1[] rows = ReadJsonLines<Gate14ReMEOracleEventRawV1>(path);
            Require(rows.Length == EventGroupCount && rows.Length == binding.oracleEventTableRows,
                "Oracle event table cardinality is invalid.");
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEOracleEventRawV1 row = rows[index];
                Gate14ReMEEventGroupV1 group = input.eventGroups[index];
                Require(row != null && row.inputId == input.inputId && row.superblockId == input.superblockId &&
                        row.eventGroupIndex == index && row.eventGroupId == group.eventGroupId &&
                        row.minimumAffectedAgentsPassed && row.bottleneckHalfAgentsPassed &&
                        row.restoreGridBytesPassed && row.restoreOraclePassed &&
                        row.sourceSha256 == binding.sourceSha256,
                    "Oracle event hard gate failed or differs from the frozen input.");
            }
        }

        private static OracleExpected LoadOracleExpected(
            Gate14ReMEQualificationInputBundleV1 input,
            Gate14ReMQFormalInputBindingV2 binding,
            string path)
        {
            Gate14ReMEOracleAgentRawV1[] rows = ReadJsonLines<Gate14ReMEOracleAgentRawV1>(path);
            int expectedRows = checked(input.agentCount * (1 + (2 * EventGroupCount)));
            Require(rows.Length == expectedRows && rows.Length == binding.oracleAgentTableRows,
                "Oracle agent table cardinality must equal N*(1+2*24).");
            OraclePoint[] baseline = new OraclePoint[input.agentCount];
            OraclePoint[][] after = new OraclePoint[EventGroupCount][];
            bool[] baselineSeen = new bool[input.agentCount];
            bool[,] beforeSeen = new bool[EventGroupCount, input.agentCount];
            bool[,] afterSeen = new bool[EventGroupCount, input.agentCount];
            for (int group = 0; group < EventGroupCount; group++) after[group] = new OraclePoint[input.agentCount];
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEOracleAgentRawV1 row = rows[index];
                Require(row != null && ids.Add(row.recordId) && row.inputId == input.inputId &&
                        row.superblockId == input.superblockId && row.agentIndex >= 0 && row.agentIndex < input.agentCount &&
                        row.startX == input.starts[row.agentIndex].x && row.startY == input.starts[row.agentIndex].y &&
                        row.goalX == input.goal.x && row.goalY == input.goal.y && row.sourceSha256 == binding.sourceSha256 &&
                        ((row.reachable && row.shortestPathCost >= 0d && row.shortestPathSteps >= 0) ||
                         (!row.reachable && row.shortestPathCost == -1d && row.shortestPathSteps == -1)),
                    "Oracle agent row identity or outcome tuple is invalid.");
                OraclePoint point = new OraclePoint(row.reachable, row.shortestPathCost, row.shortestPathSteps);
                if (row.eventGroupIndex == -1)
                {
                    Require(row.comparisonSide == "baseline" && !baselineSeen[row.agentIndex],
                        "Oracle baseline rows must occur exactly once per agent.");
                    baselineSeen[row.agentIndex] = true;
                    baseline[row.agentIndex] = point;
                }
                else
                {
                    Require(row.eventGroupIndex >= 0 && row.eventGroupIndex < EventGroupCount,
                        "Oracle event-group index is invalid.");
                    if (row.comparisonSide == "before")
                    {
                        Require(!beforeSeen[row.eventGroupIndex, row.agentIndex], "Duplicate oracle before row.");
                        beforeSeen[row.eventGroupIndex, row.agentIndex] = true;
                    }
                    else if (row.comparisonSide == "after")
                    {
                        Require(!afterSeen[row.eventGroupIndex, row.agentIndex], "Duplicate oracle after row.");
                        afterSeen[row.eventGroupIndex, row.agentIndex] = true;
                        after[row.eventGroupIndex][row.agentIndex] = point;
                    }
                    else throw new InvalidOperationException("Oracle comparisonSide is invalid.");
                }
            }
            for (int agent = 0; agent < input.agentCount; agent++)
            {
                Require(baselineSeen[agent], "Oracle cache is missing a baseline row.");
                for (int group = 0; group < EventGroupCount; group++)
                    Require(beforeSeen[group, agent] && afterSeen[group, agent], "Oracle cache is missing a before/after row.");
            }
            return new OracleExpected(baseline, after);
        }

        private static int ValidateAgainstOracle(Gate14ReMQFormalLaneResultV2 result, LoadedLane lane)
        {
            Require(lane.Expected != null && result.outcomes != null &&
                    result.outcomes.Length == checked((EventGroupCount + 1) * lane.Binding.agentCount),
                "Formal MQ compact outcome cardinality is invalid.");
            int index = 0;
            for (int phase = -1; phase < EventGroupCount; phase++)
            {
                OraclePoint[] expected = phase < 0 ? lane.Expected.Baseline : lane.Expected.After[phase];
                for (int agent = 0; agent < lane.Binding.agentCount; agent++)
                {
                    Gate14ReMQFormalOutcomeV2 actual = result.outcomes[index];
                    OraclePoint oracle = expected[agent];
                    Require(actual != null && actual.ordinal == index && actual.eventGroupIndex == phase && actual.agentIndex == agent,
                        "Formal MQ outcome ordinal or identity is invalid.");
                    if (oracle.Reachable)
                    {
                        Require(actual.reachable && actual.planStatus == NavigationPlanStatus.Succeeded.ToString() &&
                                Gate14ReMEReferenceOracleV1.NearlyEqual(oracle.Cost, actual.reportedPathCost),
                            "Formal MQ query failed the frozen reachable oracle hard gate.");
                    }
                    else
                    {
                        Require(!actual.reachable && actual.planStatus == NavigationPlanStatus.NoPath.ToString() &&
                                actual.reportedPathCost == -1d && actual.reportedPathSteps == -1,
                            "Formal MQ query failed the frozen no-path oracle hard gate.");
                    }
                    index++;
                }
            }
            return index;
        }

        private static void ValidateLaneResult(Gate14ReMQFormalLaneResultV2 value, LoadedLane lane, string algorithmId)
        {
            Require(value != null && value.schema == "gate14re-mq-formal-lane-result-v2" &&
                    value.status == "PASS_FORMAL_MQ_MEASURED_KERNEL_PENDING_EXTERNAL_ORACLE_CACHE_COMPARISON" &&
                    value.inputId == lane.Binding.sourceInputId && value.superblockId == lane.Binding.sourceSuperblockId &&
                    value.inputSha256 == lane.Binding.sourceSha256 && value.algorithmId == algorithmId &&
                    value.eventGroupCount == EventGroupCount && value.totalQueryCount == value.initialQueryCount + value.postEventQueryCount &&
                    value.totalQueryCount == checked((EventGroupCount + 1) * lane.Binding.agentCount) &&
                    value.repairCount == checked(EventGroupCount * lane.SameTickAtomicPartitions) &&
                    !string.IsNullOrWhiteSpace(value.workloadStartUtc) && !string.IsNullOrWhiteSpace(value.workloadEndUtc) &&
                    value.workloadWallMilliseconds > 0d && IsSha256(value.terminalSemanticDigestSha256),
                "Formal MQ lane result failed its schema, identity, cardinality, or timing-boundary gate.");
        }

        private static bool ValidateAffinity(MultiQueryBatchRuntimeV1 runtime, Gate14ReMQFormalScheduleRowV2 row)
        {
            Require(runtime != null && runtime.affinityPlanId == row.affinityPlanId &&
                    runtime.topologyRole == row.topologyRole && runtime.workerCount == row.workerCount &&
                    runtime.laneCount == LanesPerBlock && runtime.workers != null && runtime.workers.Length == row.workerCount,
                "Formal MQ batch runtime differs from the scheduled affinity plan.");
            for (int index = 0; index < runtime.workers.Length; index++)
                Require(runtime.workers[index] != null && runtime.workers[index].exactBindingObserved &&
                        string.IsNullOrEmpty(runtime.workers[index].setupError),
                    "A formal MQ worker did not observe its exact frozen CPU binding.");
            for (int index = 0; index < runtime.lanes.Length; index++)
                Require(runtime.lanes[index] != null && runtime.lanes[index].state == "COMPLETED" &&
                        runtime.lanes[index].stayedOnConfiguredCpuSet,
                    "A formal MQ lane did not complete on its assigned CPU set.");
            return true;
        }

        private static Gate14ReMQFormalScheduleRowV2[] ReadSchedule(string path)
        {
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            List<Gate14ReMQFormalScheduleRowV2> rows = new List<Gate14ReMQFormalScheduleRowV2>();
            for (int index = 0; index < lines.Length; index++)
            {
                if (string.IsNullOrWhiteSpace(lines[index])) continue;
                Require(lines[index].Contains("\"replacement\":null"),
                    "Formal MQ v2 schedule prohibits every replacement object.");
                Gate14ReMQFormalScheduleRowV2 value = JsonUtility.FromJson<Gate14ReMQFormalScheduleRowV2>(lines[index]);
                Require(value != null, "Schedule row did not deserialize.");
                rows.Add(value);
            }
            return rows.ToArray();
        }

        private static T[] ReadJsonLines<T>(string path)
        {
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            List<T> rows = new List<T>();
            for (int index = 0; index < lines.Length; index++)
            {
                if (string.IsNullOrWhiteSpace(lines[index])) continue;
                T value = JsonUtility.FromJson<T>(lines[index]);
                Require(value != null, "JSONL row did not deserialize: " + path + ":" + (index + 1));
                rows.Add(value);
            }
            return rows.ToArray();
        }

        private static T ReadJson<T>(string path)
        {
            Require(File.Exists(path), "Required JSON file is missing: " + path);
            T value = JsonUtility.FromJson<T>(File.ReadAllText(path, Encoding.UTF8));
            Require(value != null, "Required JSON file did not deserialize: " + path);
            return value;
        }

        private static Gate14ReMQFormalAlgorithmBindingV2 FindAlgorithm(Gate14ReMQFormalIdentityMapV2 map, string slot)
        {
            for (int index = 0; index < map.algorithms.Length; index++)
                if (map.algorithms[index].opaqueAlgorithmSlot == slot) return map.algorithms[index];
            throw new InvalidOperationException("Opaque algorithm slot is absent from the frozen identity map: " + slot);
        }

        private static CpuAffinityPlanV1 FindPlan(CpuAffinityPlanV1[] plans, string id)
        {
            for (int index = 0; index < plans.Length; index++) if (plans[index].planId == id) return plans[index];
            throw new InvalidOperationException("Required frozen affinity plan is missing: " + id);
        }

        private static string Fingerprint(Gate14ReMQFormalLaneResultV2 value)
        {
            return value == null ? string.Empty : value.terminalSemanticDigestSha256;
        }

        private static int ParseOrdinal(string value)
        {
            int result;
            Require(Int32.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out result) &&
                    result >= 0 && result < FormalProcessCount,
                "Formal MQ process ordinal is invalid.");
            return result;
        }

        private static Dictionary<string, string> ParseArguments(string[] values)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < values.Length; index++)
            {
                if (!values[index].StartsWith("--g14mq-", StringComparison.Ordinal)) continue;
                Require(index + 1 < values.Length && !result.ContainsKey(values[index]), "Invalid or duplicate formal MQ argument.");
                result.Add(values[index], values[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> values, string key)
        {
            string value;
            Require(values.TryGetValue(key, out value) && !string.IsNullOrWhiteSpace(value), "Required argument is missing: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> values, string key)
        {
            string value = Required(values, key).ToLowerInvariant();
            Require(IsSha256(value), "Argument is not a lower-case SHA-256: " + key);
            return value;
        }

        private static string ResolveExistingFile(string projectRoot, string value)
        {
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithin(projectRoot, path) && File.Exists(path), "Required project file is missing or escapes the project root: " + value);
            return path;
        }

        private static string ResolveMeasuredRoot(string projectRoot, string value)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithin(projectRoot, full), "Measured root escapes the project.");
            string relative = RelativePath(projectRoot, full).TrimEnd('/') + "/";
            Require(relative.StartsWith(ReservedMeasuredParent, StringComparison.Ordinal) &&
                    relative.Length > ReservedMeasuredParent.Length,
                "Measured root is not a versioned formal MQ v2 attempt root.");
            return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static string ResolveOutputDirectory(
            string projectRoot,
            string measuredRoot,
            string value,
            Gate14ReMQFormalScheduleRowV2 row)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            string expected = Path.Combine(measuredRoot, "raw", "blocks", row.blockId,
                "process-" + row.processOrdinal.ToString("D4", CultureInfo.InvariantCulture));
            Require(IsWithin(measuredRoot, full) &&
                    string.Equals(full.TrimEnd(Path.DirectorySeparatorChar), expected.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase),
                "Formal MQ output directory differs from the frozen process identity.");
            return full;
        }

        private static bool IsWithin(string root, string path)
        {
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(path);
            return full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(full.TrimEnd(Path.DirectorySeparatorChar), root.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
        }

        private static string RelativePath(string root, string path)
        {
            Uri rootUri = new Uri(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri pathUri = new Uri(Path.GetFullPath(path));
            return Uri.UnescapeDataString(rootUri.MakeRelativeUri(pathUri).ToString()).Replace('\\', '/');
        }

        private static string NormalizeDirectory(string value)
        {
            return Path.GetFullPath(value).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static void RequireFileHash(string path, string expected, string label)
        {
            Require(IsSha256(expected) && File.Exists(path) && Sha256File(path) == expected,
                "SHA-256 mismatch for " + label + ".");
        }

        private static void RequireJsonMarkers(string path, string schema, string status)
        {
            string text = File.ReadAllText(path, Encoding.UTF8);
            Require(text.Contains("\"schema\"") && text.Contains(schema) && text.Contains("\"status\"") && text.Contains(status),
                "Schema or status marker mismatch: " + path);
        }

        private static void RequireManifestBinding(Gate14ReMQFormalImplementationManifestV2 manifest, string path, string sha)
        {
            for (int index = 0; index < manifest.artifacts.Length; index++)
                if (manifest.artifacts[index].relativePath == path && manifest.artifacts[index].sha256 == sha) return;
            throw new InvalidOperationException("Implementation manifest lacks exact binding: " + path);
        }

        private static void Increment(Dictionary<string, int> values, string key)
        {
            int count;
            values.TryGetValue(key, out count);
            values[key] = count + 1;
        }

        private static void EnsureNewOutputDirectory(string path)
        {
            Require(!Directory.Exists(path) && !File.Exists(path), "Formal MQ process output directory must be new.");
            Directory.CreateDirectory(path);
        }

        private static void InitializeEmptyFile(string path)
        {
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read)) { }
        }

        private static void AppendJsonLine<T>(string path, T value)
        {
            File.AppendAllText(path, JsonUtility.ToJson(value, false) + "\n", new UTF8Encoding(false));
        }

        private static void WriteJsonAtomic<T>(string path, T value)
        {
            string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + "\n", new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static void WriteOutputManifest(string outputPath, string[] files)
        {
            Gate14ReMQFormalManifestRowV2[] rows = new Gate14ReMQFormalManifestRowV2[files.Length];
            for (int index = 0; index < files.Length; index++)
            {
                rows[index] = new Gate14ReMQFormalManifestRowV2
                {
                    role = "formal-process-output",
                    relativePath = Path.GetFileName(files[index]),
                    bytes = new FileInfo(files[index]).Length,
                    sha256 = Sha256File(files[index])
                };
            }
            WriteJsonAtomic(outputPath, new OutputManifest
            {
                schema = "gate14re-mq-formal-process-output-freeze-manifest-v2",
                status = "FROZEN_COMPLETE_PROCESS_OUTPUTS",
                artifacts = rows
            });
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                return Hex(sha.ComputeHash(stream));
        }

        private static string Hex(byte[] value)
        {
            StringBuilder result = new StringBuilder(value.Length * 2);
            for (int index = 0; index < value.Length; index++)
                result.Append(value[index].ToString("x2", CultureInfo.InvariantCulture));
            return result.ToString();
        }

        private static bool IsSha256(string value)
        {
            if (value == null || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return false;
            }
            return true;
        }

        private static void TryWriteFailure(string outputDirectory, Exception exception)
        {
            if (string.IsNullOrWhiteSpace(outputDirectory) || !Directory.Exists(outputDirectory)) return;
            try
            {
                WriteJsonAtomic(Path.Combine(outputDirectory, "failure-receipt.v2.json"), new FailureReceipt
                {
                    schema = "gate14re-mq-formal-process-failure-receipt-v2",
                    status = "FAIL_CLOSED_NO_RETRY_OR_PARTIAL_ACCEPTANCE",
                    errorType = exception.GetType().FullName,
                    errorMessage = exception.Message,
                    failedAtUtc = DateTimeOffset.UtcNow.ToString("o")
                });
            }
            catch { }
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        private sealed class ExecutionContext
        {
            public string ProjectRoot;
            public string MeasuredRoot;
            public Gate14ReMQFormalExecutionAuthorizationV2 Authorization;
            public Gate14ReMQFormalScheduleRowV2[] ScheduleRows;
            public Gate14ReMQFormalBlockInputRowV2[] BlockRows;
            public Gate14ReMQFormalIdentityMapV2 IdentityMap;

            public ExecutionContext(
                string projectRoot,
                string measuredRoot,
                Gate14ReMQFormalExecutionAuthorizationV2 authorization,
                Gate14ReMQFormalScheduleRowV2[] scheduleRows,
                Gate14ReMQFormalBlockInputRowV2[] blockRows,
                Gate14ReMQFormalIdentityMapV2 identityMap)
            {
                ProjectRoot = projectRoot;
                MeasuredRoot = measuredRoot;
                Authorization = authorization;
                ScheduleRows = scheduleRows;
                BlockRows = blockRows;
                IdentityMap = identityMap;
            }
        }

        private sealed class LoadedLane
        {
            public Gate14ReMQFormalInputBindingV2 Binding;
            public string InputJson;
            public OracleExpected Expected;
            public int SameTickAtomicPartitions;

            public LoadedLane(Gate14ReMQFormalInputBindingV2 binding, string inputJson, OracleExpected expected)
            {
                Binding = binding;
                InputJson = inputJson;
                Expected = expected;
                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(inputJson);
                SameTickAtomicPartitions = input.sameTickAtomicPartitions;
            }
        }

        private sealed class OraclePoint
        {
            public bool Reachable;
            public double Cost;
            public int Steps;

            public OraclePoint(bool reachable, double cost, int steps)
            {
                Reachable = reachable;
                Cost = cost;
                Steps = steps;
            }
        }

        private sealed class OracleExpected
        {
            public OraclePoint[] Baseline;
            public OraclePoint[][] After;

            public OracleExpected(OraclePoint[] baseline, OraclePoint[][] after)
            {
                Baseline = baseline;
                After = after;
            }
        }

        private sealed class BlockValidationSummary
        {
            public int SourceInputReferences;
            public int DistinctSourceInputs;
            public int DistinctCells;
            public int OracleBindings;

            public BlockValidationSummary(int references, int sources, int cells, int oracleBindings)
            {
                SourceInputReferences = references;
                DistinctSourceInputs = sources;
                DistinctCells = cells;
                OracleBindings = oracleBindings;
            }
        }

        [Serializable]
        private sealed class OutputManifest
        {
            public string schema;
            public string status;
            public Gate14ReMQFormalManifestRowV2[] artifacts;
        }

        [Serializable]
        private sealed class FailureReceipt
        {
            public string schema;
            public string status;
            public string errorType;
            public string errorMessage;
            public string failedAtUtc;
        }
    }
}
#endif
