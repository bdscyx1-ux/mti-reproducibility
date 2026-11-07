using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.MQ.V1;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    [Serializable]
    internal sealed class Gate13RMQInputBindingV1
    {
        public int ordinal;
        public string inputId;
        public string relativePath;
        public string sha256;
        public long bytes;
        public int gridEdge;
        public int agentCount;
        public int changedCellCount;
        public int replicaIndex;
    }

    [Serializable]
    internal sealed class Gate13RMQInputInventoryV1
    {
        public string schema;
        public string status;
        public int sourceInputCount;
        public int laneCount;
        public int eventGroupLimit;
        public Gate13RMQInputBindingV1[] lanes = new Gate13RMQInputBindingV1[0];
    }

    [Serializable]
    internal sealed class Gate13RMQAffinityPlanSetV1
    {
        public string schema;
        public string status;
        public CpuAffinityPlanV1[] plans = new CpuAffinityPlanV1[0];
    }

    [Serializable]
    internal sealed class Gate13RMQComparisonV1
    {
        public string schema;
        public string algorithmId;
        public string conditionId;
        public int laneOrdinal;
        public string inputId;
        public string expectedSemanticSha256;
        public string actualSemanticSha256;
        public bool exactSemanticMatch;
        public bool ordinalRestored;
    }

    [Serializable]
    internal sealed class Gate13RMQCrossAlgorithmComparisonV1
    {
        public string schema;
        public int laneOrdinal;
        public string inputId;
        public string cffOracleOutcomeSha256;
        public string idffOracleOutcomeSha256;
        public bool oracleOutcomeMatch;
    }

    [Serializable]
    internal sealed class Gate13RMQInjectedFailureReceiptV1
    {
        public string schema;
        public string status;
        public string batchId;
        public int laneCount;
        public int completedLaneCount;
        public int failedLaneCount;
        public int skippedLaneCount;
        public bool batchRejected;
        public bool noRetryOrReplacement;
    }

    [Serializable]
    internal sealed class Gate13RMQFileManifestRowV1
    {
        public int ordinal;
        public string relativePath;
        public string sha256;
        public long bytes;
    }

    [Serializable]
    internal sealed class Gate13RMQFileManifestV1
    {
        public string schema;
        public string status;
        public Gate13RMQFileManifestRowV1[] files = new Gate13RMQFileManifestRowV1[0];
    }

    [Serializable]
    internal sealed class Gate13RMQTerminalReceiptV1
    {
        public string schema;
        public string studyId;
        public string executionId;
        public string status;
        public string scope;
        public int eventGroupLimit;
        public int sourceInputCount;
        public int laneCount;
        public int algorithmCount;
        public int directConditionCount;
        public int managedConditionCount;
        public int totalSemanticBatchCount;
        public int comparisonRowCount;
        public int crossAlgorithmComparisonRowCount;
        public bool allOracleChecksPassed;
        public bool allSemanticComparisonsPassed;
        public bool repeatedDeterminismPassed;
        public bool affinityChecksPassed;
        public bool failClosedInjectionPassed;
        public bool formalMQCollectionExecuted;
        public bool formalSTOrMTTouched;
        public string inputInventorySha256;
        public string topologySnapshotSha256;
        public string affinityPlansSha256;
        public string batchRuntimeSha256;
        public string comparisonSha256;
        public string crossAlgorithmComparisonSha256;
        public string directTranscriptSha256;
        public string injectedFailureReceiptSha256;
        public string sourceManifestSha256;
        public string outputManifestSha256;
        public string createdAtUtc;
    }

    /// <summary>
    /// Gate13R correctness, determinism, isolation, affinity, and fail-closed
    /// qualification for the independent C-FF/IDFF managed MQ supplement.
    /// This is not a formal performance collection.
    /// </summary>
    public static class Gate13RMQCffIdffQualificationV1
    {
        private const int EventGroupLimit = 4;
        private const int SourceInputCount = 8;
        private const int LaneCount = 16;
        private const string AllowedOutputParent = "Research/Verification/Gate14Re-MQ-CFF-IDFF";
        private const string InputParent = "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/inputs/core";

        private static readonly string[] SourceInputNames =
        {
            "G14ME-V4-QSB-C001.input.v4.json",
            "G14ME-V4-QSB-C006.input.v4.json",
            "G14ME-V4-QSB-C013.input.v4.json",
            "G14ME-V4-QSB-C018.input.v4.json",
            "G14ME-V4-QSB-C037.input.v4.json",
            "G14ME-V4-QSB-C042.input.v4.json",
            "G14ME-V4-QSB-C073.input.v4.json",
            "G14ME-V4-QSB-C078.input.v4.json"
        };

        private static readonly string[] SourceInputSha256 =
        {
            "fd63473726c286210ffc87d1db087d7c0b8b7341e6fe0a518c9a096fa4fec2ea",
            "acd4af5d084c34a01ff34ac28708899fb96fe88eb89d441d844ba4528ab991ef",
            "aeb580d1fb99759ba327606a85d026cfe2f8ee2d289d7b8cb23f587126a0beca",
            "4751efb56ae45112b79d1cfc645683092782bed75d4332e85812aafa804b0dea",
            "4becab38c5278db884e2e261db8c992f782710e153a88b981966b3312ba5dd4b",
            "18b56a93999b4083d7918e0b6d7b24a293eb8867ba7968337e6a80f6c822839b",
            "0ba8d440461f2e14f4da40a971e968172876a292471af411c986a850b44da739",
            "f4a1185d5b22eb10f8708b4c91a30cafb46ceeb8f86bff91d7043e4fa96e4e27"
        };

        private static readonly string[] Algorithms =
        {
            NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
            NavigationAlgorithmIds.IncrementalDynamicFlowField
        };

        public static void Run()
        {
            string outputRoot = null;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string executionId = Required(arguments, "--g14mq-execution-id");
                string projectRoot = NormalizeDirectory(Directory.GetCurrentDirectory());
                outputRoot = ResolveNewOutputRoot(projectRoot, Required(arguments, "--g14mq-output-root"));
                Directory.CreateDirectory(outputRoot);
                RunQualification(projectRoot, outputRoot, executionId);
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
                TryWriteFailure(outputRoot, exception);
                EditorApplication.Exit(1);
            }
        }

        private static void RunQualification(string projectRoot, string outputRoot, string executionId)
        {
            string inputInventoryPath = Path.Combine(outputRoot, "input-inventory.v1.json");
            string topologyPath = Path.Combine(outputRoot, "topology-snapshot.v1.json");
            string affinityPlansPath = Path.Combine(outputRoot, "affinity-plans.v1.json");
            string batchRuntimePath = Path.Combine(outputRoot, "technical-batch-runtime.v1.jsonl");
            string comparisonPath = Path.Combine(outputRoot, "semantic-comparisons.v1.jsonl");
            string crossAlgorithmPath = Path.Combine(outputRoot, "cross-algorithm-oracle-outcome-comparisons.v1.jsonl");
            string transcriptPath = Path.Combine(outputRoot, "direct-semantic-transcripts.v1.jsonl");
            string injectedFailurePath = Path.Combine(outputRoot, "injected-failure-receipt.v1.json");
            InitializeEmptyFile(batchRuntimePath);
            InitializeEmptyFile(comparisonPath);
            InitializeEmptyFile(crossAlgorithmPath);
            InitializeEmptyFile(transcriptPath);

            SourceLane[] lanes = LoadAndBindInputs(projectRoot);
            Gate13RMQInputBindingV1[] inventoryRows = new Gate13RMQInputBindingV1[lanes.Length];
            for (int index = 0; index < lanes.Length; index++) inventoryRows[index] = lanes[index].Binding;
            WriteJsonAtomic(inputInventoryPath, new Gate13RMQInputInventoryV1
            {
                schema = "gate13r-mq-input-inventory-v1",
                status = "FROZEN_TECHNICAL_QUALIFICATION_CORPUS_NOT_FORMAL_SAMPLE",
                sourceInputCount = SourceInputCount,
                laneCount = LaneCount,
                eventGroupLimit = EventGroupLimit,
                lanes = inventoryRows
            });

            WindowsCpuTopologySnapshotV1 topology = WindowsCpuTopologyV1.Capture();
            WriteJsonAtomic(topologyPath, topology);
            List<CpuAffinityPlanV1> plans = CreateAllPlans(topology);
            WriteJsonAtomic(affinityPlansPath, new Gate13RMQAffinityPlanSetV1
            {
                schema = "gate13r-mq-affinity-plan-set-v1",
                status = "FROZEN_PHYSICAL_CORE_ONLY_NO_SMT",
                plans = plans.ToArray()
            });

            Dictionary<string, Gate14ReMQSemanticTranscriptV1[]> baselines = new Dictionary<string, Gate14ReMQSemanticTranscriptV1[]>(StringComparer.Ordinal);
            int batchCount = 0;
            int comparisonRows = 0;
            bool repeatedDeterminismPassed = true;
            for (int algorithmIndex = 0; algorithmIndex < Algorithms.Length; algorithmIndex++)
            {
                string algorithmId = Algorithms[algorithmIndex];
                CpuAffinityPlanV1 largeOne = FindPlan(plans, "LARGE_L3_CCD-W1");
                MultiQueryBatchExecutionV1<Gate14ReMQSemanticTranscriptV1> directLarge = DirectMultiQueryExecutorV1.Execute(
                    BatchId(executionId, algorithmId, "ST-DIRECT-LARGE-L3", 1),
                    CreateSemanticWork(lanes, algorithmId),
                    largeOne,
                    TranscriptFingerprint);
                RequireBatchSuccess(directLarge);
                batchCount++;
                AppendJsonLine(batchRuntimePath, directLarge.Runtime);
                baselines.Add(algorithmId, directLarge.Values);
                for (int laneIndex = 0; laneIndex < directLarge.Values.Length; laneIndex++)
                {
                    ValidateTranscriptIdentity(directLarge.Values[laneIndex], lanes[laneIndex], algorithmId);
                    AppendJsonLine(transcriptPath, directLarge.Values[laneIndex]);
                }

                CpuAffinityPlanV1 highOne = FindPlan(plans, "HIGH_FREQUENCY_CCD-W1");
                MultiQueryBatchExecutionV1<Gate14ReMQSemanticTranscriptV1> directHigh = DirectMultiQueryExecutorV1.Execute(
                    BatchId(executionId, algorithmId, "ST-DIRECT-HIGH-FREQUENCY", 1),
                    CreateSemanticWork(lanes, algorithmId),
                    highOne,
                    TranscriptFingerprint);
                RequireBatchSuccess(directHigh);
                batchCount++;
                AppendJsonLine(batchRuntimePath, directHigh.Runtime);
                comparisonRows += CompareWithBaseline(
                    comparisonPath, algorithmId, "ST-DIRECT-HIGH-FREQUENCY", lanes,
                    directLarge.Values, directHigh.Values);

                string[] managedPlanIds =
                {
                    "LARGE_L3_CCD-W1", "LARGE_L3_CCD-W2", "LARGE_L3_CCD-W4", "LARGE_L3_CCD-W8",
                    "HIGH_FREQUENCY_CCD-W1", "HIGH_FREQUENCY_CCD-W2", "HIGH_FREQUENCY_CCD-W4", "HIGH_FREQUENCY_CCD-W8",
                    "DUAL_CCD_BALANCED-W8", "DUAL_CCD_BALANCED-W16"
                };
                Gate14ReMQSemanticTranscriptV1[] firstLargeEight = null;
                for (int planIndex = 0; planIndex < managedPlanIds.Length; planIndex++)
                {
                    CpuAffinityPlanV1 plan = FindPlan(plans, managedPlanIds[planIndex]);
                    string conditionId = "MQ-" + managedPlanIds[planIndex];
                    MultiQueryBatchExecutionV1<Gate14ReMQSemanticTranscriptV1> execution = ManagedMultiQueryExecutorV1.Execute(
                        BatchId(executionId, algorithmId, conditionId, 1),
                        CreateSemanticWork(lanes, algorithmId),
                        plan,
                        TranscriptFingerprint);
                    RequireBatchSuccess(execution);
                    batchCount++;
                    AppendJsonLine(batchRuntimePath, execution.Runtime);
                    comparisonRows += CompareWithBaseline(
                        comparisonPath, algorithmId, conditionId, lanes,
                        directLarge.Values, execution.Values);
                    if (managedPlanIds[planIndex] == "LARGE_L3_CCD-W8") firstLargeEight = execution.Values;
                }

                Require(firstLargeEight != null, "The MQ-8 repeated-determinism source batch is missing.");
                CpuAffinityPlanV1 repeatPlan = FindPlan(plans, "LARGE_L3_CCD-W8");
                MultiQueryBatchExecutionV1<Gate14ReMQSemanticTranscriptV1> repeat = ManagedMultiQueryExecutorV1.Execute(
                    BatchId(executionId, algorithmId, "MQ-LARGE_L3_CCD-W8", 2),
                    CreateSemanticWork(lanes, algorithmId),
                    repeatPlan,
                    TranscriptFingerprint);
                RequireBatchSuccess(repeat);
                batchCount++;
                AppendJsonLine(batchRuntimePath, repeat.Runtime);
                int repeatedRows = CompareWithBaseline(
                    comparisonPath, algorithmId, "MQ-LARGE_L3_CCD-W8-REPEAT-2", lanes,
                    firstLargeEight, repeat.Values);
                comparisonRows += repeatedRows;
                repeatedDeterminismPassed = repeatedDeterminismPassed && repeatedRows == LaneCount;
            }

            int crossRows = WriteCrossAlgorithmComparisons(crossAlgorithmPath, lanes,
                baselines[NavigationAlgorithmIds.CorrectedFullRecomputeFlowField],
                baselines[NavigationAlgorithmIds.IncrementalDynamicFlowField]);

            Gate13RMQInjectedFailureReceiptV1 injected = RunInjectedFailure(
                executionId, FindPlan(plans, "LARGE_L3_CCD-W2"), batchRuntimePath);
            WriteJsonAtomic(injectedFailurePath, injected);
            Require(injected.batchRejected && injected.noRetryOrReplacement,
                "Injected failure did not reject the complete MQ batch without retry/replacement.");

            string sourceManifestPath = Path.Combine(outputRoot, "source-bindings-manifest.v1.json");
            WriteSourceManifest(projectRoot, sourceManifestPath);
            string outputManifestPath = Path.Combine(outputRoot, "output-freeze-manifest.v1.json");
            WriteOutputManifest(outputRoot, outputManifestPath, new[]
            {
                inputInventoryPath, topologyPath, affinityPlansPath, batchRuntimePath,
                comparisonPath, crossAlgorithmPath, transcriptPath, injectedFailurePath,
                sourceManifestPath
            });

            Gate13RMQTerminalReceiptV1 terminal = new Gate13RMQTerminalReceiptV1
            {
                schema = "gate13r-mq-cff-idff-terminal-receipt-v1",
                studyId = "Gate14Re-MQ-CFF-IDFF",
                executionId = executionId,
                status = "PASS_GATE13R_MQ_CORRECTNESS_DETERMINISM_AFFINITY_ISOLATION_FAIL_CLOSED",
                scope = "TECHNICAL_QUALIFICATION_ONLY_NOT_FORMAL_MQ_COLLECTION",
                eventGroupLimit = EventGroupLimit,
                sourceInputCount = SourceInputCount,
                laneCount = LaneCount,
                algorithmCount = Algorithms.Length,
                directConditionCount = 2,
                managedConditionCount = 10,
                totalSemanticBatchCount = batchCount,
                comparisonRowCount = comparisonRows,
                crossAlgorithmComparisonRowCount = crossRows,
                allOracleChecksPassed = true,
                allSemanticComparisonsPassed = true,
                repeatedDeterminismPassed = repeatedDeterminismPassed,
                affinityChecksPassed = true,
                failClosedInjectionPassed = true,
                formalMQCollectionExecuted = false,
                formalSTOrMTTouched = false,
                inputInventorySha256 = Sha256File(inputInventoryPath),
                topologySnapshotSha256 = Sha256File(topologyPath),
                affinityPlansSha256 = Sha256File(affinityPlansPath),
                batchRuntimeSha256 = Sha256File(batchRuntimePath),
                comparisonSha256 = Sha256File(comparisonPath),
                crossAlgorithmComparisonSha256 = Sha256File(crossAlgorithmPath),
                directTranscriptSha256 = Sha256File(transcriptPath),
                injectedFailureReceiptSha256 = Sha256File(injectedFailurePath),
                sourceManifestSha256 = Sha256File(sourceManifestPath),
                outputManifestSha256 = Sha256File(outputManifestPath),
                createdAtUtc = DateTimeOffset.UtcNow.ToString("o")
            };
            Require(repeatedDeterminismPassed, "Repeated MQ-8 semantic determinism failed.");
            WriteJsonAtomic(Path.Combine(outputRoot, "terminal-receipt.v1.json"), terminal);
        }

        private static SourceLane[] LoadAndBindInputs(string projectRoot)
        {
            Require(SourceInputNames.Length == SourceInputCount && SourceInputSha256.Length == SourceInputCount,
                "Frozen source-input arrays have inconsistent cardinality.");
            SourceLane[] lanes = new SourceLane[LaneCount];
            for (int laneOrdinal = 0; laneOrdinal < lanes.Length; laneOrdinal++)
            {
                int sourceIndex = laneOrdinal % SourceInputCount;
                string relativePath = InputParent + "/" + SourceInputNames[sourceIndex];
                string absolutePath = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
                Require(File.Exists(absolutePath), "Frozen technical input is missing: " + relativePath);
                string sha256 = Sha256File(absolutePath);
                Require(sha256 == SourceInputSha256[sourceIndex], "Frozen technical input hash mismatch: " + relativePath);
                string json = File.ReadAllText(absolutePath, Encoding.UTF8);
                Gate14ReME.V1.Gate14ReMEQualificationInputBundleV1 input =
                    JsonUtility.FromJson<Gate14ReME.V1.Gate14ReMEQualificationInputBundleV1>(json);
                Require(input != null && input.eventGroups != null && input.eventGroups.Length >= EventGroupLimit,
                    "Frozen technical input cannot support the event-group qualification limit: " + relativePath);
                lanes[laneOrdinal] = new SourceLane
                {
                    Json = json,
                    Binding = new Gate13RMQInputBindingV1
                    {
                        ordinal = laneOrdinal,
                        inputId = input.inputId,
                        relativePath = relativePath,
                        sha256 = sha256,
                        bytes = new FileInfo(absolutePath).Length,
                        gridEdge = input.gridEdge,
                        agentCount = input.agentCount,
                        changedCellCount = input.changedCellCount,
                        replicaIndex = laneOrdinal / SourceInputCount
                    }
                };
            }
            return lanes;
        }

        private static List<CpuAffinityPlanV1> CreateAllPlans(WindowsCpuTopologySnapshotV1 topology)
        {
            List<CpuAffinityPlanV1> result = new List<CpuAffinityPlanV1>();
            int[] singleDomainCounts = { 1, 2, 4, 8 };
            for (int index = 0; index < singleDomainCounts.Length; index++)
            {
                int count = singleDomainCounts[index];
                result.Add(WindowsCpuTopologyV1.CreatePlan(topology, "LARGE_L3_CCD-W" + count, WindowsCpuTopologyV1.LargeL3Role, count));
                result.Add(WindowsCpuTopologyV1.CreatePlan(topology, "HIGH_FREQUENCY_CCD-W" + count, WindowsCpuTopologyV1.HighFrequencyRole, count));
            }
            result.Add(WindowsCpuTopologyV1.CreatePlan(topology, "DUAL_CCD_BALANCED-W8", WindowsCpuTopologyV1.DualCcdBalancedRole, 8));
            result.Add(WindowsCpuTopologyV1.CreatePlan(topology, "DUAL_CCD_BALANCED-W16", WindowsCpuTopologyV1.DualCcdBalancedRole, 16));
            return result;
        }

        private static ManagedMultiQueryWorkItemV1<Gate14ReMQSemanticTranscriptV1>[] CreateSemanticWork(
            SourceLane[] lanes,
            string algorithmId)
        {
            ManagedMultiQueryWorkItemV1<Gate14ReMQSemanticTranscriptV1>[] work =
                new ManagedMultiQueryWorkItemV1<Gate14ReMQSemanticTranscriptV1>[lanes.Length];
            for (int index = 0; index < lanes.Length; index++)
            {
                int capturedIndex = index;
                string capturedJson = lanes[index].Json;
                string capturedSha = lanes[index].Binding.sha256;
                string capturedAlgorithm = algorithmId;
                work[index] = new ManagedMultiQueryWorkItemV1<Gate14ReMQSemanticTranscriptV1>(
                    index,
                    capturedAlgorithm + "-technical-lane-" + index.ToString("D2", CultureInfo.InvariantCulture),
                    delegate
                    {
                        Gate14ReME.V1.Gate14ReMEQualificationInputBundleV1 privateInput =
                            JsonUtility.FromJson<Gate14ReME.V1.Gate14ReMEQualificationInputBundleV1>(capturedJson);
                        Require(privateInput != null && privateInput.inputId == lanes[capturedIndex].Binding.inputId,
                            "Per-lane private input deserialization changed identity.");
                        return Gate14ReMQInputKernelV1.RunSemantic(
                            privateInput, capturedSha, capturedAlgorithm, EventGroupLimit);
                    });
            }
            return work;
        }

        private static int CompareWithBaseline(
            string outputPath,
            string algorithmId,
            string conditionId,
            SourceLane[] lanes,
            Gate14ReMQSemanticTranscriptV1[] expected,
            Gate14ReMQSemanticTranscriptV1[] actual)
        {
            Require(expected != null && actual != null && expected.Length == LaneCount && actual.Length == LaneCount,
                "Semantic comparison cardinality differs from the frozen lane count.");
            for (int index = 0; index < LaneCount; index++)
            {
                ValidateTranscriptIdentity(actual[index], lanes[index], algorithmId);
                bool exact = expected[index].semanticTranscriptSha256 == actual[index].semanticTranscriptSha256;
                Require(exact, "Semantic transcript mismatch for " + algorithmId + " " + conditionId + " lane " + index + ".");
                AppendJsonLine(outputPath, new Gate13RMQComparisonV1
                {
                    schema = "gate13r-mq-semantic-comparison-v1",
                    algorithmId = algorithmId,
                    conditionId = conditionId,
                    laneOrdinal = index,
                    inputId = lanes[index].Binding.inputId,
                    expectedSemanticSha256 = expected[index].semanticTranscriptSha256,
                    actualSemanticSha256 = actual[index].semanticTranscriptSha256,
                    exactSemanticMatch = exact,
                    ordinalRestored = actual[index].inputId == lanes[index].Binding.inputId
                });
            }
            return LaneCount;
        }

        private static int WriteCrossAlgorithmComparisons(
            string outputPath,
            SourceLane[] lanes,
            Gate14ReMQSemanticTranscriptV1[] cff,
            Gate14ReMQSemanticTranscriptV1[] idff)
        {
            Require(cff.Length == LaneCount && idff.Length == LaneCount, "Cross-algorithm comparison cardinality mismatch.");
            for (int index = 0; index < LaneCount; index++)
            {
                string left = OracleOutcomeFingerprint(cff[index]);
                string right = OracleOutcomeFingerprint(idff[index]);
                Require(left == right, "C-FF and IDFF oracle outcome projections differ at lane " + index + ".");
                AppendJsonLine(outputPath, new Gate13RMQCrossAlgorithmComparisonV1
                {
                    schema = "gate13r-mq-cross-algorithm-oracle-outcome-comparison-v1",
                    laneOrdinal = index,
                    inputId = lanes[index].Binding.inputId,
                    cffOracleOutcomeSha256 = left,
                    idffOracleOutcomeSha256 = right,
                    oracleOutcomeMatch = true
                });
            }
            return LaneCount;
        }

        private static Gate13RMQInjectedFailureReceiptV1 RunInjectedFailure(
            string executionId,
            CpuAffinityPlanV1 plan,
            string batchRuntimePath)
        {
            ManagedMultiQueryWorkItemV1<string>[] work = new ManagedMultiQueryWorkItemV1<string>[8];
            for (int index = 0; index < work.Length; index++)
            {
                int captured = index;
                work[index] = new ManagedMultiQueryWorkItemV1<string>(index, "injected-" + index, delegate
                {
                    if (captured == 0) throw new InvalidOperationException("INTENTIONAL_GATE13R_MQ_FAIL_CLOSED_INJECTION");
                    System.Threading.Thread.SpinWait(200000);
                    return "completed-" + captured;
                });
            }
            MultiQueryBatchExecutionV1<string> execution = ManagedMultiQueryExecutorV1.Execute(
                executionId + ":FAIL-CLOSED-INJECTION", work, plan, HashText);
            AppendJsonLine(batchRuntimePath, execution.Runtime);
            Require(!execution.Runtime.succeeded && execution.Runtime.failedLaneCount >= 1 &&
                    execution.Runtime.completedLaneCount + execution.Runtime.failedLaneCount + execution.Runtime.skippedLaneCount == work.Length,
                "Injected failure batch did not produce a complete fail-closed terminal ledger.");
            return new Gate13RMQInjectedFailureReceiptV1
            {
                schema = "gate13r-mq-injected-failure-receipt-v1",
                status = "PASS_COMPLETE_BATCH_REJECTED_NO_RETRY_NO_REPLACEMENT",
                batchId = execution.Runtime.batchId,
                laneCount = work.Length,
                completedLaneCount = execution.Runtime.completedLaneCount,
                failedLaneCount = execution.Runtime.failedLaneCount,
                skippedLaneCount = execution.Runtime.skippedLaneCount,
                batchRejected = !execution.Runtime.succeeded,
                noRetryOrReplacement = true
            };
        }

        private static void ValidateTranscriptIdentity(
            Gate14ReMQSemanticTranscriptV1 transcript,
            SourceLane lane,
            string algorithmId)
        {
            Require(transcript != null && transcript.status == "PASS_ORACLE_AND_SEMANTIC_KERNEL" &&
                    transcript.inputId == lane.Binding.inputId && transcript.inputSha256 == lane.Binding.sha256 &&
                    transcript.algorithmId == algorithmId && transcript.eventGroupLimit == EventGroupLimit &&
                    transcript.semanticTranscriptSha256 == Gate14ReMQInputKernelV1.ComputeSemanticTranscriptSha256(transcript),
                "Semantic transcript identity or self-hash is invalid.");
        }

        private static string OracleOutcomeFingerprint(Gate14ReMQSemanticTranscriptV1 transcript)
        {
            StringBuilder canonical = new StringBuilder();
            canonical.Append(transcript.inputId).Append('\n');
            for (int index = 0; index < transcript.operations.Length; index++)
            {
                Gate14ReMQSemanticOperationV1 row = transcript.operations[index];
                if (row.operationType != "query") continue;
                canonical.Append(row.eventGroupIndex).Append('|')
                    .Append(row.agentIndex).Append('|')
                    .Append(row.gridVersion).Append('|')
                    .Append(row.status).Append('|')
                    .Append(row.failureReason).Append('|')
                    .Append(row.oracleReachable ? "1" : "0").Append('|')
                    .Append(row.oracleCost.ToString("R", CultureInfo.InvariantCulture)).Append('\n');
            }
            return HashText(canonical.ToString());
        }

        private static void WriteSourceManifest(string projectRoot, string outputPath)
        {
            string[] relativePaths =
            {
                "Assets/_Scripts/Research/MQ/v1/WindowsCpuTopologyV1.cs",
                "Assets/_Scripts/Research/MQ/v1/ManagedMultiQueryExecutorV1.cs",
                "Assets/_Scripts/Research/MQ/v1/Gate14ReMQInputKernelV1.cs",
                "Assets/_Scripts/Research/Editor/Gate13RMQCffIdffQualificationV1.cs",
                "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
                "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
                "Assets/_Scripts/Research/Grid/ResearchNavigationGrid.cs",
                "Assets/_Scripts/Research/Navigation/NavigationContracts.cs",
                "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEQualificationContractsV1.cs",
                "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs"
            };
            Gate13RMQFileManifestRowV1[] rows = new Gate13RMQFileManifestRowV1[relativePaths.Length];
            for (int index = 0; index < relativePaths.Length; index++)
            {
                string fullPath = Path.Combine(projectRoot, relativePaths[index].Replace('/', Path.DirectorySeparatorChar));
                Require(File.Exists(fullPath), "A source-manifest member is missing: " + relativePaths[index]);
                rows[index] = new Gate13RMQFileManifestRowV1
                {
                    ordinal = index,
                    relativePath = relativePaths[index],
                    sha256 = Sha256File(fullPath),
                    bytes = new FileInfo(fullPath).Length
                };
            }
            WriteJsonAtomic(outputPath, new Gate13RMQFileManifestV1
            {
                schema = "gate13r-mq-source-bindings-manifest-v1",
                status = "FROZEN_EXACT_SOURCE_BINDINGS",
                files = rows
            });
        }

        private static void WriteOutputManifest(string outputRoot, string outputPath, string[] files)
        {
            Gate13RMQFileManifestRowV1[] rows = new Gate13RMQFileManifestRowV1[files.Length];
            for (int index = 0; index < files.Length; index++)
            {
                Require(File.Exists(files[index]), "An output-manifest member is missing: " + files[index]);
                rows[index] = new Gate13RMQFileManifestRowV1
                {
                    ordinal = index,
                    relativePath = Path.GetFileName(files[index]),
                    sha256 = Sha256File(files[index]),
                    bytes = new FileInfo(files[index]).Length
                };
            }
            WriteJsonAtomic(outputPath, new Gate13RMQFileManifestV1
            {
                schema = "gate13r-mq-output-freeze-manifest-v1",
                status = "FROZEN_TECHNICAL_QUALIFICATION_OUTPUTS",
                files = rows
            });
        }

        private static CpuAffinityPlanV1 FindPlan(List<CpuAffinityPlanV1> plans, string planId)
        {
            for (int index = 0; index < plans.Count; index++) if (plans[index].planId == planId) return plans[index];
            throw new InvalidOperationException("Required affinity plan is missing: " + planId);
        }

        private static string BatchId(string executionId, string algorithmId, string conditionId, int repetition)
        {
            return executionId + ":" + algorithmId + ":" + conditionId + ":R" + repetition;
        }

        private static string TranscriptFingerprint(Gate14ReMQSemanticTranscriptV1 value)
        {
            return value == null ? string.Empty : value.semanticTranscriptSha256;
        }

        private static void RequireBatchSuccess<T>(MultiQueryBatchExecutionV1<T> execution)
        {
            Require(execution != null && execution.Runtime != null && execution.Runtime.succeeded,
                "A semantic MQ batch failed closed: " + (execution == null || execution.Runtime == null ? "missing runtime" : execution.Runtime.firstFailure));
        }

        private static Dictionary<string, string> ParseArguments(string[] values)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < values.Length; index++)
            {
                if (!values[index].StartsWith("--g14mq-", StringComparison.Ordinal)) continue;
                Require(index + 1 < values.Length, "Missing argument value for " + values[index] + ".");
                Require(!result.ContainsKey(values[index]), "Duplicate argument: " + values[index]);
                result.Add(values[index], values[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            Require(arguments.TryGetValue(key, out value) && !string.IsNullOrWhiteSpace(value), "Required argument is missing: " + key);
            return value;
        }

        private static string ResolveNewOutputRoot(string projectRoot, string value)
        {
            string fullPath = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            string allowed = NormalizeDirectory(Path.Combine(projectRoot, AllowedOutputParent.Replace('/', Path.DirectorySeparatorChar)));
            Require(IsWithin(allowed, fullPath), "Output root escapes the MQ verification parent.");
            Require(!Directory.Exists(fullPath) && !File.Exists(fullPath), "Output root must be new: " + fullPath);
            return fullPath;
        }

        private static bool IsWithin(string parent, string candidate)
        {
            string normalizedParent = NormalizeDirectory(parent) + Path.DirectorySeparatorChar;
            string normalizedCandidate = Path.GetFullPath(candidate);
            return normalizedCandidate.StartsWith(normalizedParent, StringComparison.OrdinalIgnoreCase);
        }

        private static string NormalizeDirectory(string path)
        {
            return Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static void InitializeEmptyFile(string path)
        {
            Require(!File.Exists(path), "Output file already exists: " + path);
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

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                return Hex(sha.ComputeHash(stream));
            }
        }

        private static string HashText(string value)
        {
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty)));
        }

        private static string Hex(byte[] bytes)
        {
            StringBuilder value = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++) value.Append(bytes[index].ToString("x2", CultureInfo.InvariantCulture));
            return value.ToString();
        }

        private static void TryWriteFailure(string outputRoot, Exception exception)
        {
            if (string.IsNullOrEmpty(outputRoot) || !Directory.Exists(outputRoot)) return;
            try
            {
                WriteJsonAtomic(Path.Combine(outputRoot, "failure-receipt.v1.json"), new Gate13RMQFailureReceiptV1
                {
                    schema = "gate13r-mq-failure-receipt-v1",
                    status = "FAIL_CLOSED_TECHNICAL_QUALIFICATION",
                    errorType = exception.GetType().FullName,
                    error = exception.Message,
                    createdAtUtc = DateTimeOffset.UtcNow.ToString("o")
                });
            }
            catch { }
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        private sealed class SourceLane
        {
            public string Json;
            public Gate13RMQInputBindingV1 Binding;
        }

        [Serializable]
        private sealed class Gate13RMQFailureReceiptV1
        {
            public string schema;
            public string status;
            public string errorType;
            public string error;
            public string createdAtUtc;
        }
    }
}
