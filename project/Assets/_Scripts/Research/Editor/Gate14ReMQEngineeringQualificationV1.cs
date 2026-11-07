using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.MQ.V1;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    [Serializable]
    internal sealed class Gate14ReMQPerformanceLaneEvidenceV1
    {
        public string schema;
        public int batchOrdinal;
        public string conditionId;
        public int laneOrdinal;
        public int sourceReplicaIndex;
        public MultiQueryLaneRuntimeV1 executorRuntime;
        public Gate14ReMQPerformanceLaneResultV1 workload;
    }

    [Serializable]
    internal sealed class Gate14ReMQConditionSummaryV1
    {
        public string schema;
        public int batchOrdinal;
        public string algorithmId;
        public string conditionId;
        public string executorMode;
        public string topologyRole;
        public int workerCount;
        public int laneCount;
        public int totalQueryCount;
        public int totalRepairCount;
        public double batchWallMilliseconds;
        public double processCpuMilliseconds;
        public double processCpuEquivalentCoreCount;
        public double workerPoolSetupMilliseconds;
        public double endToEndLaneThroughputPerSecond;
        public double endToEndQueryThroughputPerSecond;
        public double outerLaneWallP50Milliseconds;
        public double outerLaneWallP95Milliseconds;
        public double outerLaneWallP99Milliseconds;
        public double outerLaneWallMaxMilliseconds;
        public double workloadWallP50Milliseconds;
        public double workloadWallP95Milliseconds;
        public double workloadWallP99Milliseconds;
        public double workloadWallMaxMilliseconds;
        public double queryP50Milliseconds;
        public double queryP95Milliseconds;
        public double queryP99Milliseconds;
        public double queryMaxMilliseconds;
        public double repairP50Milliseconds;
        public double repairP95Milliseconds;
        public double repairP99Milliseconds;
        public double repairMaxMilliseconds;
        public double initializationP50Milliseconds;
        public double initializationP95Milliseconds;
        public double initializationP99Milliseconds;
        public double initializationMaxMilliseconds;
        public long totalWorkerThreadManagedAllocatedBytes;
        public double workerThreadCpuTotalMilliseconds;
        public bool exactTerminalDigestInvariancePassed;
        public string interpretationBoundary;
    }

    [Serializable]
    internal sealed class Gate14ReMQEngineeringTerminalReceiptV1
    {
        public string schema;
        public string studyId;
        public string executionId;
        public string status;
        public string scope;
        public int algorithmCount;
        public int conditionCountPerAlgorithm;
        public int batchCount;
        public int laneRows;
        public int summaryRows;
        public int sourceInputCount;
        public int laneCountPerBatch;
        public int eventGroupsPerLane;
        public bool gate13rPrerequisiteVerified;
        public bool allBatchesPassed;
        public bool allTerminalDigestsInvariant;
        public bool explicitWorkloadBoundariesPresent;
        public bool oracleOrFullFieldHashInsideMeasuredWorkload;
        public bool formalMQCollectionExecuted;
        public bool formalAnalysisExecuted;
        public bool formalSTOrMTTouched;
        public string gate13rExternalFreezeReceiptSha256;
        public string performanceLaneEvidenceSha256;
        public string batchRuntimeSha256;
        public string conditionSummarySha256;
        public string sourceManifestSha256;
        public string outputManifestSha256;
        public string createdAtUtc;
    }

    /// <summary>
    /// One-batch-per-condition engineering qualification. It measures the full
    /// 24-event workload and verifies terminal semantic invariance, but it is not
    /// a powered or randomized formal MQ experiment and cannot support effects.
    /// </summary>
    public static class Gate14ReMQEngineeringQualificationV1
    {
        private const string AllowedOutputParent = "Research/Verification/Gate14Re-MQ-CFF-IDFF";
        private const string Gate13Root = "Research/Verification/Gate14Re-MQ-CFF-IDFF/gate13r-mq-qualification-attempt-001";
        private const string Gate13ExternalFreezeSha = "6b67f820b5c841d99ec915a2966a24bb48535047753fa95fe828cc0343718814";
        private const string Gate13TerminalSha = "c3eb67b53c28ed9a1d7a1d340f7f49230789af46c8fba8c445d9088ca60dec6e";
        private const string Gate13InputInventorySha = "e6f88d922e4a27a0f4e5cdfb56000f7d8d03a9f602c406ffd265044d2c30c92d";
        private const string Gate13TopologySha = "0dbcb5d141ec3fe5545997b1591140d26625748315ed90bd022222a179193a72";
        private const string Gate13AffinityPlansSha = "7f45ab8e5042081d489b19b0640c5c688e1288b746a877cfe31b1e81745262a8";

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
            VerifyGate13Prerequisite(projectRoot);
            string gate13Output = Path.Combine(projectRoot, (Gate13Root + "/output").Replace('/', Path.DirectorySeparatorChar));
            string inputInventoryPath = Path.Combine(gate13Output, "input-inventory.v1.json");
            string topologyPath = Path.Combine(gate13Output, "topology-snapshot.v1.json");
            string affinityPlansPath = Path.Combine(gate13Output, "affinity-plans.v1.json");
            Gate13RMQInputInventoryV1 inventory = ReadJson<Gate13RMQInputInventoryV1>(inputInventoryPath);
            Gate13RMQAffinityPlanSetV1 planSet = ReadJson<Gate13RMQAffinityPlanSetV1>(affinityPlansPath);
            Require(inventory != null && inventory.lanes != null && inventory.lanes.Length == 16 && inventory.sourceInputCount == 8,
                "Gate13R input inventory cardinality is invalid.");
            Require(planSet != null && planSet.plans != null && planSet.plans.Length == 10,
                "Gate13R affinity plan cardinality is invalid.");
            SourceLane[] lanes = LoadSourceLanes(projectRoot, inventory);

            string laneEvidencePath = Path.Combine(outputRoot, "performance-lanes.raw.v1.jsonl");
            string batchRuntimePath = Path.Combine(outputRoot, "technical-batches.raw.v1.jsonl");
            string summaryPath = Path.Combine(outputRoot, "condition-summaries.engineering.v1.jsonl");
            InitializeEmptyFile(laneEvidencePath);
            InitializeEmptyFile(batchRuntimePath);
            InitializeEmptyFile(summaryPath);

            List<Condition> conditions = CreateConditions(planSet.plans);
            int batchOrdinal = 0;
            int laneRows = 0;
            int summaryRows = 0;
            bool allDigestInvariant = true;
            for (int algorithmIndex = 0; algorithmIndex < Algorithms.Length; algorithmIndex++)
            {
                string algorithmId = Algorithms[algorithmIndex];
                string[] baselineDigests = null;
                for (int conditionIndex = 0; conditionIndex < conditions.Count; conditionIndex++)
                {
                    Condition condition = conditions[conditionIndex];
                    ManagedMultiQueryWorkItemV1<Gate14ReMQPerformanceLaneResultV1>[] work = CreateWork(lanes, algorithmId);
                    MultiQueryBatchExecutionV1<Gate14ReMQPerformanceLaneResultV1> execution = condition.Direct
                        ? DirectMultiQueryExecutorV1.Execute(
                            BatchId(executionId, batchOrdinal, algorithmId, condition.ConditionId),
                            work, condition.Plan, Fingerprint)
                        : ManagedMultiQueryExecutorV1.Execute(
                            BatchId(executionId, batchOrdinal, algorithmId, condition.ConditionId),
                            work, condition.Plan, Fingerprint);
                    Require(execution != null && execution.Runtime != null && execution.Runtime.succeeded,
                        "Engineering MQ batch failed closed: " + (execution == null || execution.Runtime == null ? "missing runtime" : execution.Runtime.firstFailure));
                    AppendJsonLine(batchRuntimePath, execution.Runtime);

                    bool digestInvariant = true;
                    if (baselineDigests == null) baselineDigests = new string[lanes.Length];
                    for (int laneIndex = 0; laneIndex < lanes.Length; laneIndex++)
                    {
                        Gate14ReMQPerformanceLaneResultV1 result = execution.Values[laneIndex];
                        ValidateResult(result, lanes[laneIndex], algorithmId);
                        if (conditionIndex == 0) baselineDigests[laneIndex] = result.terminalSemanticDigestSha256;
                        bool laneDigestMatch = baselineDigests[laneIndex] == result.terminalSemanticDigestSha256;
                        Require(laneDigestMatch, "Terminal semantic digest changed across MQ conditions at lane " + laneIndex + ".");
                        digestInvariant = digestInvariant && laneDigestMatch;
                        AppendJsonLine(laneEvidencePath, new Gate14ReMQPerformanceLaneEvidenceV1
                        {
                            schema = "gate14re-mq-performance-lane-evidence-v1",
                            batchOrdinal = batchOrdinal,
                            conditionId = condition.ConditionId,
                            laneOrdinal = laneIndex,
                            sourceReplicaIndex = lanes[laneIndex].Binding.replicaIndex,
                            executorRuntime = execution.Runtime.lanes[laneIndex],
                            workload = result
                        });
                        laneRows++;
                    }
                    Gate14ReMQConditionSummaryV1 summary = Summarize(
                        batchOrdinal, algorithmId, condition, execution, digestInvariant);
                    AppendJsonLine(summaryPath, summary);
                    summaryRows++;
                    allDigestInvariant = allDigestInvariant && digestInvariant;
                    batchOrdinal++;
                }
            }

            Require(batchOrdinal == Algorithms.Length * conditions.Count && laneRows == batchOrdinal * lanes.Length,
                "Engineering qualification output cardinality is invalid.");
            Require(allDigestInvariant, "One or more terminal semantic digests varied across conditions.");

            string sourceManifestPath = Path.Combine(outputRoot, "source-bindings-manifest.v1.json");
            WriteSourceManifest(projectRoot, sourceManifestPath);
            string outputManifestPath = Path.Combine(outputRoot, "output-freeze-manifest.v1.json");
            WriteOutputManifest(outputManifestPath, new[]
            {
                laneEvidencePath, batchRuntimePath, summaryPath, sourceManifestPath
            });
            WriteJsonAtomic(Path.Combine(outputRoot, "terminal-receipt.v1.json"), new Gate14ReMQEngineeringTerminalReceiptV1
            {
                schema = "gate14re-mq-engineering-qualification-terminal-receipt-v1",
                studyId = "Gate14Re-MQ-CFF-IDFF",
                executionId = executionId,
                status = "PASS_ENGINEERING_QUALIFICATION_FORMAL_MQ_DESIGN_STILL_PENDING",
                scope = "FULL_24_EVENT_TECHNICAL_RUNTIME_QUALIFICATION_NOT_A_POWERED_OR_RANDOMIZED_FORMAL_EXPERIMENT",
                algorithmCount = Algorithms.Length,
                conditionCountPerAlgorithm = conditions.Count,
                batchCount = batchOrdinal,
                laneRows = laneRows,
                summaryRows = summaryRows,
                sourceInputCount = inventory.sourceInputCount,
                laneCountPerBatch = lanes.Length,
                eventGroupsPerLane = Gate14ReMEQualificationConstantsV1.EventGroupCount,
                gate13rPrerequisiteVerified = true,
                allBatchesPassed = true,
                allTerminalDigestsInvariant = true,
                explicitWorkloadBoundariesPresent = true,
                oracleOrFullFieldHashInsideMeasuredWorkload = false,
                formalMQCollectionExecuted = false,
                formalAnalysisExecuted = false,
                formalSTOrMTTouched = false,
                gate13rExternalFreezeReceiptSha256 = Gate13ExternalFreezeSha,
                performanceLaneEvidenceSha256 = Sha256File(laneEvidencePath),
                batchRuntimeSha256 = Sha256File(batchRuntimePath),
                conditionSummarySha256 = Sha256File(summaryPath),
                sourceManifestSha256 = Sha256File(sourceManifestPath),
                outputManifestSha256 = Sha256File(outputManifestPath),
                createdAtUtc = DateTimeOffset.UtcNow.ToString("o")
            });
        }

        private static List<Condition> CreateConditions(CpuAffinityPlanV1[] plans)
        {
            List<Condition> result = new List<Condition>();
            result.Add(new Condition("ST-DIRECT-LARGE-L3", true, FindPlan(plans, "LARGE_L3_CCD-W1")));
            result.Add(new Condition("MQ-LARGE-L3-W1", false, FindPlan(plans, "LARGE_L3_CCD-W1")));
            result.Add(new Condition("MQ-LARGE-L3-W2", false, FindPlan(plans, "LARGE_L3_CCD-W2")));
            result.Add(new Condition("MQ-LARGE-L3-W4", false, FindPlan(plans, "LARGE_L3_CCD-W4")));
            result.Add(new Condition("MQ-LARGE-L3-W8", false, FindPlan(plans, "LARGE_L3_CCD-W8")));
            result.Add(new Condition("ST-DIRECT-HIGH-FREQUENCY", true, FindPlan(plans, "HIGH_FREQUENCY_CCD-W1")));
            result.Add(new Condition("MQ-HIGH-FREQUENCY-W1", false, FindPlan(plans, "HIGH_FREQUENCY_CCD-W1")));
            result.Add(new Condition("MQ-HIGH-FREQUENCY-W2", false, FindPlan(plans, "HIGH_FREQUENCY_CCD-W2")));
            result.Add(new Condition("MQ-HIGH-FREQUENCY-W4", false, FindPlan(plans, "HIGH_FREQUENCY_CCD-W4")));
            result.Add(new Condition("MQ-HIGH-FREQUENCY-W8", false, FindPlan(plans, "HIGH_FREQUENCY_CCD-W8")));
            result.Add(new Condition("MQ-DUAL-CCD-W8-4PLUS4", false, FindPlan(plans, "DUAL_CCD_BALANCED-W8")));
            result.Add(new Condition("MQ-DUAL-CCD-W16-8PLUS8", false, FindPlan(plans, "DUAL_CCD_BALANCED-W16")));
            return result;
        }

        private static ManagedMultiQueryWorkItemV1<Gate14ReMQPerformanceLaneResultV1>[] CreateWork(
            SourceLane[] lanes,
            string algorithmId)
        {
            ManagedMultiQueryWorkItemV1<Gate14ReMQPerformanceLaneResultV1>[] work =
                new ManagedMultiQueryWorkItemV1<Gate14ReMQPerformanceLaneResultV1>[lanes.Length];
            for (int index = 0; index < lanes.Length; index++)
            {
                string json = lanes[index].Json;
                string sha = lanes[index].Binding.sha256;
                string algorithm = algorithmId;
                work[index] = new ManagedMultiQueryWorkItemV1<Gate14ReMQPerformanceLaneResultV1>(
                    index, algorithm + "-engineering-lane-" + index.ToString("D2", CultureInfo.InvariantCulture),
                    delegate
                    {
                        Gate14ReMEQualificationInputBundleV1 privateInput = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(json);
                        Require(privateInput != null, "Private performance input deserialization failed.");
                        return Gate14ReMQPerformanceKernelV1.Run(privateInput, sha, algorithm);
                    });
            }
            return work;
        }

        private static Gate14ReMQConditionSummaryV1 Summarize(
            int batchOrdinal,
            string algorithmId,
            Condition condition,
            MultiQueryBatchExecutionV1<Gate14ReMQPerformanceLaneResultV1> execution,
            bool digestInvariant)
        {
            List<double> outerLane = new List<double>();
            List<double> workload = new List<double>();
            List<double> query = new List<double>();
            List<double> repair = new List<double>();
            List<double> initialization = new List<double>();
            int totalQueries = 0;
            int totalRepairs = 0;
            long totalAllocation = 0L;
            double workerCpu = 0d;
            for (int laneIndex = 0; laneIndex < execution.Values.Length; laneIndex++)
            {
                Gate14ReMQPerformanceLaneResultV1 value = execution.Values[laneIndex];
                MultiQueryLaneRuntimeV1 runtime = execution.Runtime.lanes[laneIndex];
                AddFinite(outerLane, runtime.wallMilliseconds);
                AddFinite(workload, value.workloadWallMilliseconds);
                AddFinite(initialization, value.initializationWallMilliseconds);
                AddFiniteRange(query, value.queryWallMilliseconds);
                AddFiniteRange(repair, value.gridMutationAndRepairWallMilliseconds);
                totalQueries = checked(totalQueries + value.totalQueryCount);
                totalRepairs = checked(totalRepairs + value.repairCount);
                totalAllocation = checked(totalAllocation + runtime.workerThreadManagedAllocatedBytes);
                workerCpu += runtime.workerThreadCpuMilliseconds;
            }
            double wall = execution.Runtime.batchWallMilliseconds;
            Require(wall > 0d, "Batch wall time must be positive.");
            return new Gate14ReMQConditionSummaryV1
            {
                schema = "gate14re-mq-condition-summary-engineering-v1",
                batchOrdinal = batchOrdinal,
                algorithmId = algorithmId,
                conditionId = condition.ConditionId,
                executorMode = execution.Runtime.executorMode,
                topologyRole = execution.Runtime.topologyRole,
                workerCount = execution.Runtime.workerCount,
                laneCount = execution.Runtime.laneCount,
                totalQueryCount = totalQueries,
                totalRepairCount = totalRepairs,
                batchWallMilliseconds = wall,
                processCpuMilliseconds = execution.Runtime.processCpuMilliseconds,
                processCpuEquivalentCoreCount = execution.Runtime.processCpuMilliseconds / wall,
                workerPoolSetupMilliseconds = execution.Runtime.workerPoolSetupMilliseconds,
                endToEndLaneThroughputPerSecond = execution.Runtime.laneCount * 1000d / wall,
                endToEndQueryThroughputPerSecond = totalQueries * 1000d / wall,
                outerLaneWallP50Milliseconds = Quantile(outerLane, 0.50d),
                outerLaneWallP95Milliseconds = Quantile(outerLane, 0.95d),
                outerLaneWallP99Milliseconds = Quantile(outerLane, 0.99d),
                outerLaneWallMaxMilliseconds = Maximum(outerLane),
                workloadWallP50Milliseconds = Quantile(workload, 0.50d),
                workloadWallP95Milliseconds = Quantile(workload, 0.95d),
                workloadWallP99Milliseconds = Quantile(workload, 0.99d),
                workloadWallMaxMilliseconds = Maximum(workload),
                queryP50Milliseconds = Quantile(query, 0.50d),
                queryP95Milliseconds = Quantile(query, 0.95d),
                queryP99Milliseconds = Quantile(query, 0.99d),
                queryMaxMilliseconds = Maximum(query),
                repairP50Milliseconds = Quantile(repair, 0.50d),
                repairP95Milliseconds = Quantile(repair, 0.95d),
                repairP99Milliseconds = Quantile(repair, 0.99d),
                repairMaxMilliseconds = Maximum(repair),
                initializationP50Milliseconds = Quantile(initialization, 0.50d),
                initializationP95Milliseconds = Quantile(initialization, 0.95d),
                initializationP99Milliseconds = Quantile(initialization, 0.99d),
                initializationMaxMilliseconds = Maximum(initialization),
                totalWorkerThreadManagedAllocatedBytes = totalAllocation,
                workerThreadCpuTotalMilliseconds = workerCpu,
                exactTerminalDigestInvariancePassed = digestInvariant,
                interpretationBoundary = "ENGINEERING_RUNTIME_QUALIFICATION_ONLY_NOT_FORMAL_EFFECT_ESTIMATE_OR_WINNER_RANKING"
            };
        }

        private static void VerifyGate13Prerequisite(string projectRoot)
        {
            string external = Path.Combine(projectRoot, (Gate13Root + "/external-freeze-receipt.v1.json").Replace('/', Path.DirectorySeparatorChar));
            string output = Path.Combine(projectRoot, (Gate13Root + "/output").Replace('/', Path.DirectorySeparatorChar));
            Require(Sha256File(external) == Gate13ExternalFreezeSha, "Gate13R external freeze receipt hash mismatch.");
            Require(Sha256File(Path.Combine(output, "terminal-receipt.v1.json")) == Gate13TerminalSha,
                "Gate13R terminal receipt hash mismatch.");
            Require(Sha256File(Path.Combine(output, "input-inventory.v1.json")) == Gate13InputInventorySha,
                "Gate13R input inventory hash mismatch.");
            Require(Sha256File(Path.Combine(output, "topology-snapshot.v1.json")) == Gate13TopologySha,
                "Gate13R topology snapshot hash mismatch.");
            Require(Sha256File(Path.Combine(output, "affinity-plans.v1.json")) == Gate13AffinityPlansSha,
                "Gate13R affinity-plan hash mismatch.");
        }

        private static SourceLane[] LoadSourceLanes(string projectRoot, Gate13RMQInputInventoryV1 inventory)
        {
            SourceLane[] result = new SourceLane[inventory.lanes.Length];
            for (int index = 0; index < result.Length; index++)
            {
                Gate13RMQInputBindingV1 binding = inventory.lanes[index];
                Require(binding != null && binding.ordinal == index, "Gate13R input ordinals are not contiguous.");
                string fullPath = Path.GetFullPath(Path.Combine(projectRoot, binding.relativePath.Replace('/', Path.DirectorySeparatorChar)));
                Require(File.Exists(fullPath) && Sha256File(fullPath) == binding.sha256,
                    "A Gate13R-bound input is missing or changed: " + binding.relativePath);
                string json = File.ReadAllText(fullPath, Encoding.UTF8);
                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(json);
                Require(input != null && input.sameTickAtomicPartitions > 0,
                    "A Gate13R-bound input has invalid atomic-partition metadata.");
                result[index] = new SourceLane
                {
                    Binding = binding,
                    Json = json,
                    SameTickAtomicPartitions = input.sameTickAtomicPartitions
                };
            }
            return result;
        }

        private static void ValidateResult(Gate14ReMQPerformanceLaneResultV1 result, SourceLane source, string algorithmId)
        {
            Require(result != null && result.schema == "gate14re-mq-performance-lane-result-v1" &&
                    result.status == "PASS_TECHNICAL_PERFORMANCE_KERNEL" &&
                    result.inputId == source.Binding.inputId && result.inputSha256 == source.Binding.sha256 &&
                    result.algorithmId == algorithmId &&
                    result.eventGroupCount == Gate14ReMEQualificationConstantsV1.EventGroupCount &&
                    result.totalQueryCount == result.initialQueryCount + result.postEventQueryCount &&
                    result.totalQueryCount == checked((Gate14ReMEQualificationConstantsV1.EventGroupCount + 1) * source.Binding.agentCount) &&
                    result.repairCount == checked(Gate14ReMEQualificationConstantsV1.EventGroupCount * source.SameTickAtomicPartitions) &&
                    result.queryWallMilliseconds != null && result.queryWallMilliseconds.Length == result.totalQueryCount &&
                    result.gridMutationAndRepairWallMilliseconds != null && result.gridMutationAndRepairWallMilliseconds.Length == result.repairCount &&
                    result.eventGroupWallMilliseconds != null && result.eventGroupWallMilliseconds.Length == result.eventGroupCount &&
                    !string.IsNullOrWhiteSpace(result.workloadStartUtc) && !string.IsNullOrWhiteSpace(result.workloadEndUtc) &&
                    result.workloadWallMilliseconds > 0d && IsSha256(result.terminalSemanticDigestSha256),
                "Performance lane result failed schema, identity, cardinality, or boundary validation.");
        }

        private static string Fingerprint(Gate14ReMQPerformanceLaneResultV1 value)
        {
            return value == null ? string.Empty : value.terminalSemanticDigestSha256;
        }

        private static string BatchId(string executionId, int ordinal, string algorithmId, string conditionId)
        {
            return executionId + ":B" + ordinal.ToString("D2", CultureInfo.InvariantCulture) + ":" + algorithmId + ":" + conditionId;
        }

        private static CpuAffinityPlanV1 FindPlan(CpuAffinityPlanV1[] plans, string id)
        {
            for (int index = 0; index < plans.Length; index++) if (plans[index].planId == id) return plans[index];
            throw new InvalidOperationException("Required affinity plan is missing: " + id);
        }

        private static void AddFinite(List<double> values, double value)
        {
            Require(value >= 0d && !double.IsNaN(value) && !double.IsInfinity(value), "A timing value is invalid.");
            values.Add(value);
        }

        private static void AddFiniteRange(List<double> values, double[] source)
        {
            Require(source != null, "A timing array is missing.");
            for (int index = 0; index < source.Length; index++) AddFinite(values, source[index]);
        }

        private static double Quantile(List<double> values, double probability)
        {
            Require(values != null && values.Count > 0 && probability >= 0d && probability <= 1d,
                "Quantile inputs are invalid.");
            double[] sorted = values.ToArray();
            Array.Sort(sorted);
            double position = (sorted.Length - 1) * probability;
            int lower = (int)Math.Floor(position);
            int upper = (int)Math.Ceiling(position);
            if (lower == upper) return sorted[lower];
            double fraction = position - lower;
            return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction);
        }

        private static double Maximum(List<double> values)
        {
            Require(values != null && values.Count > 0, "Maximum requires data.");
            double maximum = values[0];
            for (int index = 1; index < values.Count; index++) if (values[index] > maximum) maximum = values[index];
            return maximum;
        }

        private static void WriteSourceManifest(string projectRoot, string outputPath)
        {
            string[] relativePaths =
            {
                "Assets/_Scripts/Research/MQ/v1/WindowsCpuTopologyV1.cs",
                "Assets/_Scripts/Research/MQ/v1/ManagedMultiQueryExecutorV1.cs",
                "Assets/_Scripts/Research/MQ/v1/Gate14ReMQPerformanceKernelV1.cs",
                "Assets/_Scripts/Research/Editor/Gate14ReMQEngineeringQualificationV1.cs",
                "Assets/_Scripts/Research/Algorithms/CorrectedFullRecomputeFlowFieldPlanner.cs",
                "Assets/_Scripts/Research/Algorithms/IncrementalDynamicFlowFieldPlanner.cs",
                "Assets/_Scripts/Research/Grid/ResearchNavigationGrid.cs",
                "Assets/_Scripts/Research/Navigation/NavigationContracts.cs"
            };
            Gate13RMQFileManifestRowV1[] rows = new Gate13RMQFileManifestRowV1[relativePaths.Length];
            for (int index = 0; index < relativePaths.Length; index++)
            {
                string fullPath = Path.Combine(projectRoot, relativePaths[index].Replace('/', Path.DirectorySeparatorChar));
                Require(File.Exists(fullPath), "Source binding is missing: " + relativePaths[index]);
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
                schema = "gate14re-mq-engineering-source-bindings-manifest-v1",
                status = "FROZEN_EXACT_SOURCE_BINDINGS",
                files = rows
            });
        }

        private static void WriteOutputManifest(string outputPath, string[] files)
        {
            Gate13RMQFileManifestRowV1[] rows = new Gate13RMQFileManifestRowV1[files.Length];
            for (int index = 0; index < files.Length; index++)
            {
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
                schema = "gate14re-mq-engineering-output-freeze-manifest-v1",
                status = "FROZEN_ENGINEERING_QUALIFICATION_OUTPUTS",
                files = rows
            });
        }

        private static T ReadJson<T>(string path)
        {
            Require(File.Exists(path), "Required JSON file is missing: " + path);
            T value = JsonUtility.FromJson<T>(File.ReadAllText(path, Encoding.UTF8));
            Require(value != null, "Required JSON file did not deserialize: " + path);
            return value;
        }

        private static Dictionary<string, string> ParseArguments(string[] values)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < values.Length; index++)
            {
                if (!values[index].StartsWith("--g14mq-", StringComparison.Ordinal)) continue;
                Require(index + 1 < values.Length && !result.ContainsKey(values[index]), "Invalid or duplicate MQ argument.");
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

        private static string ResolveNewOutputRoot(string projectRoot, string value)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            string allowed = NormalizeDirectory(Path.Combine(projectRoot, AllowedOutputParent.Replace('/', Path.DirectorySeparatorChar))) + Path.DirectorySeparatorChar;
            Require(full.StartsWith(allowed, StringComparison.OrdinalIgnoreCase), "Output root escapes the MQ verification parent.");
            Require(!Directory.Exists(full) && !File.Exists(full), "Output root must be new.");
            return full;
        }

        private static string NormalizeDirectory(string value)
        {
            return Path.GetFullPath(value).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
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

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                return Hex(sha.ComputeHash(stream));
        }

        private static string Hex(byte[] value)
        {
            StringBuilder result = new StringBuilder(value.Length * 2);
            for (int index = 0; index < value.Length; index++) result.Append(value[index].ToString("x2", CultureInfo.InvariantCulture));
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

        private static void TryWriteFailure(string outputRoot, Exception exception)
        {
            if (string.IsNullOrWhiteSpace(outputRoot) || !Directory.Exists(outputRoot)) return;
            try
            {
                WriteJsonAtomic(Path.Combine(outputRoot, "failure-receipt.v1.json"), new Gate14ReMQEngineeringFailureV1
                {
                    schema = "gate14re-mq-engineering-failure-receipt-v1",
                    status = "FAIL_CLOSED_ENGINEERING_QUALIFICATION",
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
            public Gate13RMQInputBindingV1 Binding;
            public string Json;
            public int SameTickAtomicPartitions;
        }

        private sealed class Condition
        {
            public string ConditionId;
            public bool Direct;
            public CpuAffinityPlanV1 Plan;

            public Condition(string conditionId, bool direct, CpuAffinityPlanV1 plan)
            {
                ConditionId = conditionId;
                Direct = direct;
                Plan = plan;
            }
        }

        [Serializable]
        private sealed class Gate14ReMQEngineeringFailureV1
        {
            public string schema;
            public string status;
            public string errorType;
            public string error;
            public string createdAtUtc;
        }
    }
}
