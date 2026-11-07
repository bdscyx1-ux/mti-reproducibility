#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Gate14ReME.V3;
using DDM.Research.Gate14ReME.V4;
using DDM.Research.Gate14ReME.V5;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Versioned, fail-closed entry point for Gate14Re-ME formal ST v5
    /// with the independently qualified D3-v3.1 cumulative-allocation instrument.
    /// Merely compiling this source does not authorize execution. Every mode requires
    /// a later execution-authorization receipt bound to the frozen implementation
    /// manifest and schedule.
    /// </summary>
    public static class Gate14ReMEFormalSTRunnerV5
    {
        private const string RunnerRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMEFormalSTRunnerV5.cs";
        private const string OracleRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs";
        private const string InstrumentationRelativePath = "Assets/_Scripts/Research/Gate14ReME/v3/Gate14ReMELoadQualificationD3V31ContractsV1.cs";
        private const string ReservedFormalMeasuredRootParentRelativePath = "Research/FormalRuns/Gate14Re-ME/formal-st/v5/";
        private const int BurstCompletionTimeoutMilliseconds = 300000;

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                ExecutionContext context = ValidateExecutionContext(projectRoot, arguments);
                string mode = Required(arguments, "--g14me-mode");
                if (mode == "oracle-batch") RunOracleBatchMode(context, arguments);
                else if (mode == "lane") RunLaneMode(context, arguments);
                else if (mode == "empty-boundary") RunEmptyBoundaryMode(context, arguments);
                else if (mode == "instrument-self-test") RunInstrumentSelfTestMode(context, arguments);
                else throw new InvalidOperationException("Unsupported --g14me-mode: " + mode);

                // The mode output is already frozen at this point. Every
                // formal ST process is a fresh Unity editor process, so
                // wait on Burst's own completion predicate before unloading
                // Mono; this prevents the compiler-thread teardown race
                // without changing any measured interval or metric.
                Gate14ReMEBurstHostLifecycleV1.WaitResult burstWait =
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(BurstCompletionTimeoutMilliseconds);
                Require(burstWait.finalCompilationDone, "Burst current compilation did not finish before process shutdown.");
                exitCode = 0;
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
                TryWriteFailureReceipt(exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static void RunOracleBatchMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            int batchIndex;
            Require(int.TryParse(Required(arguments, "--g14me-oracle-batch-index"), NumberStyles.None, CultureInfo.InvariantCulture, out batchIndex) &&
                    batchIndex >= 0 && batchIndex < context.Authorization.oracleBatchCount,
                "Oracle batch index is outside the authorization-bound batch count.");
            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "oracle-batches", "batch-" + batchIndex.ToString("D2", CultureInfo.InvariantCulture)), "oracle-batch");
            EnsureNewOutputDirectory(outputDirectory);
            string oracleRoot = Path.Combine(context.MeasuredRoot, "oracle");
            Directory.CreateDirectory(oracleRoot);
            string oracleSourcePath = Path.Combine(context.ProjectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar));
            string oracleSourceSha256 = Sha256File(oracleSourcePath);
            List<FormalSTOracleBatchMemberV5> members = new List<FormalSTOracleBatchMemberV5>();

            for (int scheduleIndex = 0; scheduleIndex < context.ScheduleRows.Length; scheduleIndex++)
            {
                Gate14ReMEFormalSTScheduleRowV5 scheduledRow = context.ScheduleRows[scheduleIndex];
                if (OracleBatchIndexForScheduleOrdinal(scheduledRow.ordinal, context.Authorization.oracleBatchCount) != batchIndex) continue;
                Require(scheduledRow.replacement == null, "Oracle batching prohibits replacement schedule rows.");
                string inputPath = ResolveExistingFile(context.ProjectRoot, scheduledRow.inputRelativePath);
                string inputRelativePath = RelativePath(context.ProjectRoot, inputPath);
                string inputSha256 = Sha256File(inputPath);
                Require(inputRelativePath == scheduledRow.inputRelativePath.Replace('\\', '/') && inputSha256 == scheduledRow.inputSha256,
                    "Oracle batch input does not match the frozen schedule path/hash.");
                Gate14ReMEFormalSTInputBundleV5 input = ReadJson<Gate14ReMEFormalSTInputBundleV5>(inputPath);
                Require(input.superblockId == scheduledRow.superblockId,
                    "Oracle batch input superblock id differs from the frozen schedule.");

                string oracleDirectory = Path.Combine(oracleRoot, scheduledRow.superblockId);
                EnsureNewOutputDirectory(oracleDirectory);
                Gate14ReMEGeometryValidationResultV1 result = Gate14ReMEInputGeometryValidatorV5.Validate(
                    input, inputRelativePath, inputSha256, OracleRelativePath, oracleSourceSha256);
                string agentTablePath = Path.Combine(oracleDirectory, "oracle-agent-checks.raw.v1.jsonl");
                string eventTablePath = Path.Combine(oracleDirectory, "oracle-event-checks.raw.v1.jsonl");
                string oracleReceiptPath = Path.Combine(oracleDirectory, "oracle-pass-receipt.v5.json");
                WriteJsonLines(agentTablePath, result.AgentRows);
                WriteJsonLines(eventTablePath, result.EventRows);
                WriteJsonAtomic(oracleReceiptPath, result.Receipt);

                FormalSTOracleCacheBindingReceiptV5 cacheReceipt = new FormalSTOracleCacheBindingReceiptV5
                {
                    schema = "gate14re-me-formal-st-oracle-cache-binding-receipt-v5",
                    studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                    status = "PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5",
                    batchIndex = batchIndex,
                    scheduleOrdinal = scheduledRow.ordinal,
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    inputRelativePath = inputRelativePath,
                    inputSha256 = inputSha256,
                    oracleSourceRelativePath = OracleRelativePath,
                    oracleSourceSha256 = oracleSourceSha256,
                    oraclePassReceiptRelativePath = RelativePath(context.ProjectRoot, oracleReceiptPath),
                    oraclePassReceiptSha256 = Sha256File(oracleReceiptPath),
                    agentTableRelativePath = RelativePath(context.ProjectRoot, agentTablePath),
                    agentTableSha256 = Sha256File(agentTablePath),
                    agentTableRows = result.AgentRows.Length,
                    eventTableRelativePath = RelativePath(context.ProjectRoot, eventTablePath),
                    eventTableSha256 = Sha256File(eventTablePath),
                    eventTableRows = result.EventRows.Length,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                string cacheReceiptPath = Path.Combine(oracleDirectory, "oracle-cache-binding-receipt.v5.json");
                WriteJsonAtomic(cacheReceiptPath, cacheReceipt);
                members.Add(new FormalSTOracleBatchMemberV5
                {
                    scheduleOrdinal = scheduledRow.ordinal,
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    cacheBindingReceiptRelativePath = RelativePath(context.ProjectRoot, cacheReceiptPath),
                    cacheBindingReceiptSha256 = Sha256File(cacheReceiptPath)
                });
            }

            int expectedMembers = Gate14ReMEFormalSTConstantsV5.SuperblockCount / context.Authorization.oracleBatchCount;
            Require(members.Count == expectedMembers, "Oracle batch membership differs from the authorization-bound equal partition.");
            WriteJsonAtomic(Path.Combine(outputDirectory, "oracle-batch-receipt.v5.json"), new FormalSTOracleBatchReceiptV5
            {
                schema = "gate14re-me-formal-st-oracle-batch-receipt-v5",
                studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                status = "PASS_ORACLE_BATCH_COMPLETE_V5",
                batchIndex = batchIndex,
                batchCount = context.Authorization.oracleBatchCount,
                assignmentRule = "schedule-ordinal-mod-authorization-batch-count-v5",
                inputCount = members.Count,
                members = members.ToArray(),
                createdAtUtc = DateTime.UtcNow.ToString("o")
            });
        }

        private static void RunLaneMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            string algorithmId = Required(arguments, "--g14me-algorithm-id");
            string anonymousLaneId = Required(arguments, "--g14me-anonymous-lane-id");
            string identityBindingSha256 = RequiredSha256(arguments, "--g14me-identity-binding-sha256");
            Require(Contains(Gate14ReMEFormalSTConstantsV5.AnonymousLanes, anonymousLaneId), "Anonymous lane id is outside ALG-A through ALG-F.");
            Gate14ReMEAlgorithmBindingV1 algorithmBinding = FindAlgorithmBinding(context.Fairness, algorithmId);
            ValidateAlgorithmBinding(context.ProjectRoot, algorithmBinding);

            string inputPath = ResolveExistingFile(context.ProjectRoot, Required(arguments, "--g14me-input"));
            string cacheBindingPath = ResolveExistingFile(context.ProjectRoot, Required(arguments, "--g14me-oracle-cache-binding"));
            string expectedCacheBindingSha = RequiredSha256(arguments, "--g14me-oracle-cache-binding-sha256");
            Require(Sha256File(cacheBindingPath) == expectedCacheBindingSha, "Oracle cache-binding receipt hash mismatch.");
            FormalSTOracleCacheBindingReceiptV5 cacheBinding = ReadJson<FormalSTOracleCacheBindingReceiptV5>(cacheBindingPath);
            string inputSha256 = Sha256File(inputPath);
            string inputRelativePath = RelativePath(context.ProjectRoot, inputPath);
            Gate14ReMEFormalSTScheduleRowV5 scheduledRow;
            bool scheduledReplacement;
            Require(TryFindScheduledInput(context.ScheduleRows, inputRelativePath, inputSha256, out scheduledRow, out scheduledReplacement),
                "Lane input is not an exact path/hash member of the frozen formal ST schedule.");
            Require(ScheduleContainsLane(scheduledRow, algorithmId, anonymousLaneId, identityBindingSha256),
                "Algorithm/lane/identity tuple is not present in the frozen schedule row.");
            Require(!scheduledReplacement && scheduledRow.replacement == null,
                "Formal ST v5 prohibits replacement schedule rows.");

            Gate14ReMEFormalSTInputBundleV5 input = ReadJson<Gate14ReMEFormalSTInputBundleV5>(inputPath);
            string scheduledInstanceId = scheduledRow.superblockId;
            string expectedCacheBindingPath = Path.GetFullPath(Path.Combine(
                context.MeasuredRoot,
                "oracle",
                scheduledInstanceId,
                "oracle-cache-binding-receipt.v5.json"));
            Require(string.Equals(Path.GetFullPath(cacheBindingPath), expectedCacheBindingPath, StringComparison.OrdinalIgnoreCase),
                "Oracle cache-binding receipt path does not match the exact measured input cache path.");
            Require(cacheBinding.schema == "gate14re-me-formal-st-oracle-cache-binding-receipt-v5" &&
                    cacheBinding.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                    cacheBinding.status == "PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5" &&
                    cacheBinding.scheduleOrdinal == scheduledRow.ordinal &&
                    cacheBinding.batchIndex == OracleBatchIndexForScheduleOrdinal(scheduledRow.ordinal, context.Authorization.oracleBatchCount) &&
                    cacheBinding.inputId == input.inputId &&
                    cacheBinding.superblockId == scheduledInstanceId &&
                    cacheBinding.inputRelativePath == inputRelativePath &&
                    cacheBinding.inputSha256 == inputSha256 &&
                    cacheBinding.oracleSourceRelativePath == OracleRelativePath,
                "Oracle cache-binding receipt does not match the input and frozen schedule.");
            string oracleSourcePath = ResolveExistingFile(context.ProjectRoot, cacheBinding.oracleSourceRelativePath);
            Require(Sha256File(oracleSourcePath) == cacheBinding.oracleSourceSha256,
                "Oracle reference source hash differs from the cache binding.");
            string oracleReceiptPath = ResolveExistingFile(context.ProjectRoot, cacheBinding.oraclePassReceiptRelativePath);
            string agentTablePath = ResolveExistingFile(context.ProjectRoot, cacheBinding.agentTableRelativePath);
            string eventTablePath = ResolveExistingFile(context.ProjectRoot, cacheBinding.eventTableRelativePath);
            string expectedOracleDirectory = Path.GetFullPath(Path.Combine(context.MeasuredRoot, "oracle", scheduledInstanceId));
            Require(IsWithinProject(expectedOracleDirectory, oracleReceiptPath) &&
                    IsWithinProject(expectedOracleDirectory, agentTablePath) &&
                    IsWithinProject(expectedOracleDirectory, eventTablePath),
                "Oracle cache members must be located under the exact measured oracle/superblock directory.");
            Require(Sha256File(oracleReceiptPath) == cacheBinding.oraclePassReceiptSha256 &&
                    Sha256File(agentTablePath) == cacheBinding.agentTableSha256 &&
                    Sha256File(eventTablePath) == cacheBinding.eventTableSha256,
                "One or more oracle cache member hashes differ from the cache binding.");
            Gate14ReMEOraclePassReceiptV1 oracleReceipt = ReadJson<Gate14ReMEOraclePassReceiptV1>(oracleReceiptPath);
            Require(oracleReceipt.schema == Gate14ReMEFormalSTConstantsV5.OracleReceiptSchema &&
                    oracleReceipt.status == "PASS_ALGORITHM_NEUTRAL_GEOMETRY" &&
                    oracleReceipt.allGeometryChecksPassed &&
                    oracleReceipt.inputSha256 == inputSha256 &&
                    oracleReceipt.inputRelativePath == inputRelativePath,
                    "The lane is not bound to a valid prior algorithm-neutral geometry receipt.");

            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            Require(input.inputId == oracleReceipt.inputId && input.superblockId == scheduledInstanceId && oracleReceipt.superblockId == scheduledInstanceId,
                "Input/superblock identity does not match the schedule and oracle receipt.");
            ValidateOracleEventTable(input, cacheBinding, eventTablePath);
            FormalSTOracleCacheV5 oracleCache = LoadOracleCache(input, cacheBinding, agentTablePath);
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "raw", "superblocks", scheduledInstanceId, anonymousLaneId), "lane");
            EnsureNewOutputDirectory(outputDirectory);

            RunAlgorithmLane(
                context,
                input,
                inputRelativePath,
                inputSha256,
                RelativePath(context.ProjectRoot, oracleReceiptPath),
                cacheBinding.oraclePassReceiptSha256,
                oracleCache,
                RelativePath(context.ProjectRoot, cacheBindingPath),
                expectedCacheBindingSha,
                algorithmBinding,
                anonymousLaneId,
                identityBindingSha256,
                outputDirectory);
        }

        private static void RunAlgorithmLane(
            ExecutionContext context,
            Gate14ReMEFormalSTInputBundleV5 input,
            string inputRelativePath,
            string inputSha256,
            string oracleReceiptRelativePath,
            string oracleReceiptSha256,
            FormalSTOracleCacheV5 oracleCache,
            string oracleCacheBindingRelativePath,
            string oracleCacheBindingSha256,
            Gate14ReMEAlgorithmBindingV1 algorithmBinding,
            string anonymousLaneId,
            string identityBindingSha256,
            string outputDirectory)
        {
            Stopwatch laneStopwatch = Stopwatch.StartNew();
            string runnerSha = Sha256File(Path.Combine(context.ProjectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV5.BuildGrid(input);
            Gate14ReMECountingGridV1 countingGrid = new Gate14ReMECountingGridV1(grid);
            INavigationPlanner planner = CreatePlanner(algorithmBinding.algorithmId);
            List<Gate14ReMEOperationRawV1> operationBuffer = new List<Gate14ReMEOperationRawV1>();
            int operationRows = 0;
            int eventRows = 0;
            int d3WindowRows = 0;
            int stateRows = 0;
            int resourceRows = 0;
            long peakCommittedBytes = 0L;
            bool instrumentValid = true;
            bool laneEligible = true;
            string failureReasonCode = string.Empty;

            string operationPath = Path.Combine(outputDirectory, "operations.raw.v1.jsonl");
            string eventPath = Path.Combine(outputDirectory, Gate14ReMED3V31QualificationConstantsV1.EventGroupFileName);
            string d3WindowPath = Path.Combine(outputDirectory, Gate14ReMED3V31QualificationConstantsV1.D3WindowFileName);
            string statePath = Path.Combine(outputDirectory, "persistent-state.raw.v1.jsonl");
            string resourcesPath = Path.Combine(outputDirectory, "process-resources.raw.v1.jsonl");
            InitializeEmptyFile(operationPath);
            InitializeEmptyFile(eventPath);
            InitializeEmptyFile(d3WindowPath);
            InitializeEmptyFile(statePath);
            InitializeEmptyFile(resourcesPath);

            try
            {
                countingGrid.BeginWindow();
                Stopwatch initializationStopwatch = new Stopwatch();
                NavigationOperationMetrics initialization;
                Gate14ReMED3MeasurementWindowV1 initializationD3 = new Gate14ReMED3MeasurementWindowV1();
                using (initializationD3)
                {
                    initializationStopwatch.Start();
                    initialization = planner.Initialize(countingGrid, new NavigationPlannerInitialization
                    {
                        runId = input.inputId + ":" + anonymousLaneId,
                        goalSetId = input.inputId + ":shared-goal",
                        goals = new[] { input.goal },
                        connectivity = input.connectivity,
                        allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                        budgetMilliseconds = context.Budget.initializationOperationBudgetMilliseconds
                    });
                    initializationStopwatch.Stop();
                }
                Gate14ReMEGridCounterSnapshotV1 initializationReads = countingGrid.EndWindow();
                string initializationD3RecordId = input.inputId + ":" + anonymousLaneId + ":d3:initialize";
                Gate14ReMED3WindowRawV1 initializationD3Row = initializationD3.CreateRawRecord(
                    initializationD3RecordId, input.inputId, input.superblockId, anonymousLaneId,
                    identityBindingSha256, "planner-initialization", -1, -1, -1,
                    RunnerRelativePath, runnerSha);
                AppendJsonLine(d3WindowPath, initializationD3Row);
                d3WindowRows++;
                instrumentValid = initializationReads.totalCalls >= 0L && initializationD3Row.counterValid;
                laneEligible = !initialization.budgetExceeded;
                if (!laneEligible) failureReasonCode = "INITIALIZATION_BUDGET_EXCEEDED";
                else if (!instrumentValid) failureReasonCode = "INITIALIZATION_INSTRUMENT_COUNTER_INVALID";
                Gate14ReMEOperationRawV1 initializationRow = OperationFromMetrics(
                    input, anonymousLaneId, identityBindingSha256, algorithmBinding,
                    "initialize", input.inputId + ":" + anonymousLaneId + ":initialize", -1, -1, -1, grid.Version,
                    NavigationPlanStatus.Succeeded, NavigationFailureReason.None,
                    initialization, false, -1d, -1d, true, inputRelativePath, inputSha256);
                initializationRow.elapsedCpuMilliseconds = initializationStopwatch.Elapsed.TotalMilliseconds;
                operationBuffer.Add(initializationRow);
                FlushOperations(operationPath, operationBuffer, ref operationRows);
                WriteStateAndResources(context, planner, input, anonymousLaneId, identityBindingSha256,
                    "after-initialization", -1, inputRelativePath, inputSha256, statePath, resourcesPath,
                    ref stateRows, ref resourceRows, ref peakCommittedBytes);

                Gate14ReMEOraclePathV1[] initialOracle = oracleCache.Baseline;
                for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                {
                    NavigationPlanResult plan = planner.Plan(CreatePlanRequest(input, anonymousLaneId, agentIndex, grid.Version, context.Budget.plannerOperationBudgetMilliseconds, "initial"));
                    double reportedCost = ComputeReportedPathCost(grid, plan.Path);
                    bool correctness = CorrectnessMatches(initialOracle[agentIndex], plan, reportedCost);
                    if (!correctness)
                    {
                        laneEligible = false;
                        if (string.IsNullOrEmpty(failureReasonCode)) failureReasonCode = "INITIAL_QUERY_ORACLE_CORRECTNESS_MISMATCH";
                    }
                    operationBuffer.Add(OperationFromPlan(input, anonymousLaneId, identityBindingSha256,
                        algorithmBinding, "initial_query", input.inputId + ":" + anonymousLaneId + ":initial-query:" + agentIndex,
                        -1, agentIndex, plan, initialOracle[agentIndex], reportedCost, correctness,
                        inputRelativePath, inputSha256));
                }
                FlushOperations(operationPath, operationBuffer, ref operationRows);
                WriteStateAndResources(context, planner, input, anonymousLaneId, identityBindingSha256,
                    "after-initial-queries", -1, inputRelativePath, inputSha256, statePath, resourcesPath,
                    ref stateRows, ref resourceRows, ref peakCommittedBytes);

                for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    WriteProgressAtomic(outputDirectory, input, anonymousLaneId, groupIndex, "MEASURING");
                    countingGrid.BeginWindow();
                    Stopwatch eventStopwatch = new Stopwatch();
                    int repairCount = 0;
                    int planCount = 0;
                    int succeededCount = 0;
                    int noPathCount = 0;
                    int budgetExceededCount = 0;
                    bool correctnessPassed = true;
                    bool repairPassed = true;
                    Gate14ReMED3MeasurementWindowV1 eventD3 = new Gate14ReMED3MeasurementWindowV1();
                    using (eventD3)
                    {
                        eventStopwatch.Start();

                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = partition.changes[changeIndex].ToChange();
                        NavigationChangeSet changeSet = grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, context.Budget.repairOperationBudgetMilliseconds);
                        repairCount++;
                        repairPassed = repairPassed && repair.Status == NavigationPlanStatus.Succeeded;
                        if (repair.Metrics.budgetExceeded || repair.Status == NavigationPlanStatus.BudgetExceeded) budgetExceededCount++;
                        operationBuffer.Add(OperationFromMetrics(
                            input, anonymousLaneId, identityBindingSha256, algorithmBinding,
                            "repair", input.inputId + ":" + anonymousLaneId + ":" + group.eventGroupId + ":repair:" + partitionIndex,
                            groupIndex, partitionIndex, -1, repair.GridVersion,
                            repair.Status, repair.FailureReason, repair.Metrics,
                            false, -1d, -1d, true, inputRelativePath, inputSha256));
                    }

                    Gate14ReMEOraclePathV1[] oracle = oracleCache.AfterEventGroups[groupIndex];
                    for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                    {
                        NavigationPlanResult plan = planner.Plan(CreatePlanRequest(input, anonymousLaneId, agentIndex, grid.Version, context.Budget.plannerOperationBudgetMilliseconds, "g" + groupIndex));
                        planCount++;
                        if (plan.Status == NavigationPlanStatus.Succeeded) succeededCount++;
                        else if (plan.Status == NavigationPlanStatus.NoPath) noPathCount++;
                        if (plan.Metrics.budgetExceeded || plan.Status == NavigationPlanStatus.BudgetExceeded) budgetExceededCount++;
                        double reportedCost = ComputeReportedPathCost(grid, plan.Path);
                        bool correctness = CorrectnessMatches(oracle[agentIndex], plan, reportedCost);
                        correctnessPassed = correctnessPassed && correctness;
                        operationBuffer.Add(OperationFromPlan(input, anonymousLaneId, identityBindingSha256,
                            algorithmBinding, "post_event_query", input.inputId + ":" + anonymousLaneId + ":" + group.eventGroupId + ":query:" + agentIndex,
                            groupIndex, agentIndex, plan, oracle[agentIndex], reportedCost, correctness,
                            inputRelativePath, inputSha256));
                    }

                    eventStopwatch.Stop();
                    }
                    Gate14ReMEGridCounterSnapshotV1 reads = countingGrid.EndWindow();
                    string d3WindowRecordId = input.inputId + ":" + anonymousLaneId + ":d3:event:" + groupIndex;
                    Gate14ReMED3WindowRawV1 d3WindowRow = eventD3.CreateRawRecord(
                        d3WindowRecordId, input.inputId, input.superblockId, anonymousLaneId,
                        identityBindingSha256, "event-group", groupIndex, -1, -1,
                        RunnerRelativePath, runnerSha);
                    AppendJsonLine(d3WindowPath, d3WindowRow);
                    d3WindowRows++;
                    double eventMilliseconds = eventStopwatch.Elapsed.TotalMilliseconds;
                    bool finitePositive = eventMilliseconds > 0d && !double.IsNaN(eventMilliseconds) && !double.IsInfinity(eventMilliseconds);
                    bool timeoutExceeded = eventMilliseconds > context.Budget.eventGroupHardTimeoutMilliseconds;
                    bool countersPassed = reads.totalCalls >= 0L && d3WindowRow.counterValid;
                    bool eligible = finitePositive && correctnessPassed && repairPassed && !timeoutExceeded && budgetExceededCount == 0 && countersPassed;
                    string ineligibleReason = eligible ? string.Empty :
                        (!finitePositive ? "D1_NONFINITE_OR_NONPOSITIVE" :
                        (!correctnessPassed ? "ORACLE_CORRECTNESS_MISMATCH" :
                        (!repairPassed ? "REPAIR_OPERATION_FAILED" :
                        (timeoutExceeded ? "EVENT_GROUP_HARD_TIMEOUT_EXCEEDED" :
                        (budgetExceededCount != 0 ? "OPERATION_BUDGET_EXCEEDED" : "INSTRUMENT_COUNTER_INVALID")))));
                    laneEligible = laneEligible && eligible;
                    instrumentValid = instrumentValid && countersPassed;
                    if (!eligible && string.IsNullOrEmpty(failureReasonCode)) failureReasonCode = ineligibleReason;

                    Gate14ReMEEventGroupRawV2 eventRow = new Gate14ReMEEventGroupRawV2
                    {
                        recordId = input.inputId + ":" + anonymousLaneId + ":event:" + groupIndex,
                        inputId = input.inputId,
                        superblockId = input.superblockId,
                        designRegion = input.designRegion,
                        anonymousLaneId = anonymousLaneId,
                        identityBindingSha256 = identityBindingSha256,
                        gridEdge = input.gridEdge,
                        agentCount = input.agentCount,
                        changedCellCount = input.changedCellCount,
                        changeTopology = input.changeTopology,
                        graphProfile = input.graphProfile,
                        sameTickAtomicPartitions = input.sameTickAtomicPartitions,
                        contextStratumId = input.contextStratumId,
                        eventGroupId = group.eventGroupId,
                        eventGroupIndex = groupIndex,
                        cycleIndex = group.cycleIndex,
                        phase = group.phase,
                        eventGroupElapsedMilliseconds = eventMilliseconds,
                        d3WindowRecordId = d3WindowRecordId,
                        d3CounterId = Gate14ReMED3V31QualificationConstantsV1.CounterId,
                        d3CounterValid = d3WindowRow.counterValid,
                        gridContainsCalls = reads.containsCalls,
                        gridIsWalkableCalls = reads.isWalkableCalls,
                        gridGetTraversalCostCalls = reads.getTraversalCostCalls,
                        gridAccessorCallsTotal = reads.totalCalls,
                        repairOperationCount = repairCount,
                        planOperationCount = planCount,
                        succeededPlanCount = succeededCount,
                        noPathPlanCount = noPathCount,
                        budgetExceededOperationCount = budgetExceededCount,
                        eligible = eligible,
                        missingOrIneligibleReasonCode = ineligibleReason,
                        finitePositiveElapsed = finitePositive,
                        counterValid = countersPassed,
                        sourceRelativePath = inputRelativePath,
                        sourceSha256 = inputSha256
                    };
                    FlushOperations(operationPath, operationBuffer, ref operationRows);
                    AppendJsonLine(eventPath, eventRow);
                    eventRows++;
                    WriteStateAndResources(context, planner, input, anonymousLaneId, identityBindingSha256,
                        "after-event-group-" + groupIndex, groupIndex, inputRelativePath, inputSha256,
                        statePath, resourcesPath, ref stateRows, ref resourceRows, ref peakCommittedBytes);
                    WriteProgressAtomic(outputDirectory, input, anonymousLaneId, groupIndex, "COMPLETED_GROUP");
                }

                laneStopwatch.Stop();
                bool laneTimeout = laneStopwatch.Elapsed.TotalMilliseconds > context.Budget.laneWallClockHardTimeoutMilliseconds;
                bool memoryExceeded = peakCommittedBytes > context.Budget.laneAssignedCommittedMemoryBytes;
                if (laneTimeout) failureReasonCode = "LANE_WALL_CLOCK_HARD_TIMEOUT_EXCEEDED";
                else if (memoryExceeded) failureReasonCode = "LANE_COMMITTED_MEMORY_CEILING_EXCEEDED";
                WriteJsonAtomic(Path.Combine(outputDirectory, "lane-oracle-cache-link.v5.json"), new FormalSTLaneOracleCacheLinkV5
                {
                    schema = "gate14re-me-formal-st-lane-oracle-cache-link-v5",
                    studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                    status = "BOUND_TO_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5",
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    anonymousLaneId = anonymousLaneId,
                    identityBindingSha256 = identityBindingSha256,
                    oracleCacheBindingRelativePath = oracleCacheBindingRelativePath,
                    oracleCacheBindingSha256 = oracleCacheBindingSha256,
                    agentTableRelativePath = oracleCache.AgentTableRelativePath,
                    agentTableSha256 = oracleCache.AgentTableSha256,
                    agentTableRows = oracleCache.AgentTableRows,
                    referenceOracleEvaluationsPerformedInsideLane = 0,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                });
                Gate14ReMELaneReceiptV2 receipt = new Gate14ReMELaneReceiptV2
                {
                    schema = Gate14ReMEFormalSTConstantsV5.LaneReceiptSchema,
                    studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                    protocolId = Gate14ReMEFormalSTConstantsV5.ProtocolId,
                    status = laneTimeout || memoryExceeded || !laneEligible || !instrumentValid ? "COMPLETED_WITH_FORMAL_ST_FAILURE" : "COMPLETE_RAW_FORMAL_ST_LANE",
                    inputId = input.inputId,
                    superblockId = input.superblockId,
                    anonymousLaneId = anonymousLaneId,
                    identityBindingSha256 = identityBindingSha256,
                    inputRelativePath = inputRelativePath,
                    inputSha256 = inputSha256,
                    oracleReceiptRelativePath = oracleReceiptRelativePath,
                    oracleReceiptSha256 = oracleReceiptSha256,
                    implementationManifestSha256 = context.ImplementationManifestSha256,
                    fairnessBindingSha256 = context.FairnessSha256,
                    resourceBudgetSha256 = context.BudgetSha256,
                    d3ContractSha256 = Gate14ReMED3V31QualificationConstantsV1.ContractSha256,
                    eventGroupRows = eventRows,
                    operationRows = operationRows,
                    d3WindowRows = d3WindowRows,
                    persistentStateRows = stateRows,
                    processResourceRows = resourceRows,
                    peakCommittedBytes = peakCommittedBytes,
                    laneWallClockMilliseconds = laneStopwatch.Elapsed.TotalMilliseconds,
                    instrumentValid = instrumentValid,
                    completed = eventRows == Gate14ReMEFormalSTConstantsV5.EventGroupCount &&
                        d3WindowRows == Gate14ReMEFormalSTConstantsV5.EventGroupCount + 1,
                    failureReasonCode = failureReasonCode,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "lane-receipt.v5.json"), receipt);
            }
            catch (Exception)
            {
                laneStopwatch.Stop();
                throw;
            }
            finally
            {
                try { planner.Reset(); }
                catch (Exception resetException) { UnityEngine.Debug.LogException(resetException); }
            }
        }

        private static void RunEmptyBoundaryMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            int processOrdinal;
            if (!int.TryParse(Required(arguments, "--g14me-process-ordinal"), NumberStyles.None, CultureInfo.InvariantCulture, out processOrdinal) || processOrdinal < 0 || processOrdinal >= 12)
            {
                throw new InvalidOperationException("Empty-boundary process ordinal must be 0 through 11.");
            }
            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "raw", "empty-boundary", "process-" + processOrdinal.ToString("D2", CultureInfo.InvariantCulture)), "empty-boundary");
            EnsureNewOutputDirectory(outputDirectory);
            string path = Path.Combine(outputDirectory, Gate14ReMED3V31QualificationConstantsV1.EmptyBoundaryFileName);
            string d3WindowPath = Path.Combine(outputDirectory, Gate14ReMED3V31QualificationConstantsV1.D3WindowFileName);
            InitializeEmptyFile(path);
            InitializeEmptyFile(d3WindowPath);
            string sourceSha = Sha256File(Path.Combine(context.ProjectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            int d3WindowRows = 0;
            for (int index = 0; index < 1000; index++)
            {
                long startTicks;
                long endTicks;
                Gate14ReMED3MeasurementWindowV1 d3Window = new Gate14ReMED3MeasurementWindowV1();
                using (d3Window)
                {
                    startTicks = Stopwatch.GetTimestamp();
                    EmptyBoundary();
                    endTicks = Stopwatch.GetTimestamp();
                }
                string recordId = "empty:" + processOrdinal + ":" + index;
                string d3WindowRecordId = "empty-d3:" + processOrdinal + ":" + index;
                Gate14ReMED3WindowRawV1 d3WindowRow = d3Window.CreateRawRecord(
                    d3WindowRecordId, string.Empty, string.Empty, string.Empty, string.Empty,
                    "empty-boundary", -1, processOrdinal, index, RunnerRelativePath, sourceSha);
                AppendJsonLine(d3WindowPath, d3WindowRow);
                d3WindowRows++;
                Require(d3WindowRow.counterValid, "D3-v3.1 empty-boundary window is invalid: " + d3WindowRow.invalidReasonCode);
                double elapsed = (endTicks - startTicks) * 1000d / Stopwatch.Frequency;
                AppendJsonLine(path, new Gate14ReMEEmptyBoundaryRawV2
                {
                    recordId = recordId,
                    processOrdinal = processOrdinal,
                    iterationIndex = index,
                    stopwatchStartTicks = startTicks,
                    stopwatchEndTicks = endTicks,
                    elapsedMilliseconds = elapsed,
                    d3WindowRecordId = d3WindowRecordId,
                    d3CounterId = Gate14ReMED3V31QualificationConstantsV1.CounterId,
                    d3CounterValid = d3WindowRow.counterValid,
                    plannerInvoked = false,
                    sourceRelativePath = RunnerRelativePath,
                    sourceSha256 = sourceSha
                });
            }
            WriteJsonAtomic(Path.Combine(outputDirectory, "empty-boundary-receipt.v5.json"), new Gate14ReMEEmptyBoundaryReceiptV2
            {
                schema = Gate14ReMEFormalSTConstantsV5.EmptyBoundaryReceiptSchema,
                studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                status = "COMPLETE_EMPTY_BOUNDARY_RAW",
                processOrdinal = processOrdinal,
                rawIterationRows = 1000,
                d3WindowRows = d3WindowRows,
                plannerInvoked = false,
                d3ContractSha256 = Gate14ReMED3V31QualificationConstantsV1.ContractSha256,
                implementationManifestSha256 = context.ImplementationManifestSha256,
                resourceBudgetSha256 = context.BudgetSha256,
                createdAtUtc = DateTime.UtcNow.ToString("o")
            });
        }

        private static void RunInstrumentSelfTestMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "instruments", "csharp"), "instrument-self-test");
            EnsureNewOutputDirectory(outputDirectory);
            ResearchNavigationGrid grid = new ResearchNavigationGrid(3, 3, 1f);
            Gate14ReMECountingGridV1 proxy = new Gate14ReMECountingGridV1(grid);
            GridCoordinate coordinate = new GridCoordinate(1, 1);
            long versionBefore = proxy.Version;
            proxy.BeginWindow();
            bool contained = proxy.Contains(coordinate);
            bool walkable = proxy.IsWalkable(coordinate);
            float cost = proxy.GetTraversalCost(coordinate);
            Gate14ReMEGridCounterSnapshotV1 counts = proxy.EndWindow();
            bool knownAnswer = counts.containsCalls == 1L && counts.isWalkableCalls == 1L && counts.getTraversalCostCalls == 1L && counts.totalCalls == 3L;
            bool semantic = contained && walkable && cost == 1f && proxy.Version == versionBefore;

            Gate14ReMED3MeasurementWindowV1 d3Window = new Gate14ReMED3MeasurementWindowV1();
            byte[] positiveControl;
            using (d3Window)
            {
                positiveControl = new byte[1024 * 1024];
                positiveControl[positiveControl.Length - 1] = 1;
                GC.KeepAlive(positiveControl);
            }
            string sourceSha = Sha256File(Path.Combine(context.ProjectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            Gate14ReMED3WindowRawV1 d3Row = d3Window.CreateRawRecord(
                "instrument-self-test:d3:one-mib", string.Empty, string.Empty, string.Empty, string.Empty,
                "instrument-self-test-positive-control", -1, -1, -1, RunnerRelativePath, sourceSha);
            string d3WindowPath = Path.Combine(outputDirectory, Gate14ReMED3V31QualificationConstantsV1.D3WindowFileName);
            InitializeEmptyFile(d3WindowPath);
            AppendJsonLine(d3WindowPath, d3Row);
            bool d3ReadinessPassed = d3Row.pluginReady && d3Row.markerSeen && d3Row.metadataAbiValid && d3Row.ownerThreadMatched;
            bool allocationPassed = d3Row.counterValid && d3Row.managedAllocationBytes >= positiveControl.Length &&
                d3Row.managedAllocationEventCount >= 1L;
            double independentlyRecomputedRate = d3Row.windowElapsedStopwatchTicks > 0L
                ? d3Row.managedAllocationBytes * (double)d3Row.stopwatchFrequency / d3Row.windowElapsedStopwatchTicks
                : 0.0;
            bool ratePassed = d3Row.managedAllocationRateValid && independentlyRecomputedRate > 0d &&
                !double.IsNaN(independentlyRecomputedRate) && !double.IsInfinity(independentlyRecomputedRate) &&
                Math.Abs(independentlyRecomputedRate - d3Row.managedAllocationRateBytesPerSecond) <= 1e-9;

            bool clockPassed = true;
            long previous = Stopwatch.GetTimestamp();
            for (int index = 0; index < 10000; index++)
            {
                long current = Stopwatch.GetTimestamp();
                if (current < previous) { clockPassed = false; break; }
                previous = current;
            }
            bool sizerPassed = Gate14ReMEPersistentStateSizerV1.RunSyntheticFixture();
            bool csharpPass = knownAnswer && semantic && d3ReadinessPassed && allocationPassed && ratePassed && clockPassed && sizerPassed;
            WriteJsonAtomic(Path.Combine(outputDirectory, "instrument-readiness-receipt.v5.json"), new Gate14ReMEInstrumentQualificationReceiptV2
            {
                schema = Gate14ReMEFormalSTConstantsV5.InstrumentReceiptSchema,
                studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                status = csharpPass ? "PASS_FORMAL_ST_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING" : "FAIL_CLOSED_FORMAL_ST_INSTRUMENT_COMPONENTS",
                gridReadProxyKnownAnswerPassed = knownAnswer,
                gridReadProxySemanticInvariancePassed = semantic,
                d3V31PluginReadinessPassed = d3ReadinessPassed,
                d3V31OneMiBPositiveControlPassed = allocationPassed,
                d3V31RateFormulaPassed = ratePassed,
                persistentStateSizerSyntheticFixturePassed = sizerPassed,
                clockMonotonicityPassed = clockPassed,
                rawToExportRoundTripPassed = false,
                tamperNegativeTestPassed = false,
                missingNegativeTestPassed = false,
                duplicateNegativeTestPassed = false,
                anonymousLabelSwapNegativeTestPassed = false,
                d3ContractSha256 = Gate14ReMED3V31QualificationConstantsV1.ContractSha256,
                implementationManifestSha256 = context.ImplementationManifestSha256,
                createdAtUtc = DateTime.UtcNow.ToString("o")
            });
            Require(csharpPass, "One or more formal ST C# instrument components failed.");
        }

        private static ExecutionContext ValidateExecutionContext(string projectRoot, Dictionary<string, string> arguments)
        {
            string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-execution-authorization"));
            string expectedAuthorizationSha = RequiredSha256(arguments, "--g14me-execution-authorization-sha256");
            Require(Sha256File(authorizationPath) == expectedAuthorizationSha, "Execution-authorization hash mismatch.");
            Gate14ReMEFormalSTExecutionAuthorizationV5 authorization = ReadJson<Gate14ReMEFormalSTExecutionAuthorizationV5>(authorizationPath);
            Require(authorization.schema == Gate14ReMEFormalSTConstantsV5.ExecutionAuthorizationSchema &&
                    authorization.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                    authorization.designId == Gate14ReMEFormalSTConstantsV5.DesignId &&
                    authorization.status == "AUTHORIZED_FORMAL_ST_COLLECTION" &&
                    authorization.formalRootCreationAuthorized &&
                    authorization.compileOrUnityExecutionAuthorized &&
                    authorization.formalCollectionAuthorized &&
                    !authorization.formalInputGenerationAuthorized &&
                    !authorization.formalAcceptanceExecutionAuthorized &&
                    !authorization.formalAnalysisAuthorized &&
                    !authorization.mqAuthorized &&
                    !authorization.mtAuthorized &&
                    authorization.oracleBatchCount > 0 &&
                    authorization.oracleBatchCount <= Gate14ReMEFormalSTConstantsV5.SuperblockCount &&
                    Gate14ReMEFormalSTConstantsV5.SuperblockCount % authorization.oracleBatchCount == 0 &&
                    !string.IsNullOrWhiteSpace(authorization.measuredRootRelativePath) &&
                    IsSha256(authorization.implementationManifestSha256) &&
                    IsSha256(authorization.scheduleSha256) &&
                    !string.IsNullOrWhiteSpace(authorization.authorizationNonce),
                    "Execution authorization is absent, incomplete, or exceeds the formal ST boundary.");
            string normalizedAuthorizationMeasuredRoot = authorization.measuredRootRelativePath.Replace('\\', '/').TrimEnd('/');
            string measuredRoot = Path.GetFullPath(Path.Combine(projectRoot, normalizedAuthorizationMeasuredRoot.Replace('/', Path.DirectorySeparatorChar)));
            string measuredRootRelativePath = RelativePath(projectRoot, measuredRoot).Replace('\\', '/').TrimEnd('/');
            Require(IsWithinProject(projectRoot, measuredRoot) &&
                    measuredRootRelativePath == normalizedAuthorizationMeasuredRoot &&
                    IsReservedFormalMeasuredRoot(measuredRootRelativePath),
                "Execution authorization is not bound to the exact frozen measured root.");

            string manifestPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-implementation-manifest"));
            string manifestSha = RequiredSha256(arguments, "--g14me-implementation-manifest-sha256");
            Require(Sha256File(manifestPath) == manifestSha && manifestSha == authorization.implementationManifestSha256,
                "Implementation manifest is not bound to the execution authorization.");
            Gate14ReMEFormalSTImplementationManifestV5 manifest = ReadJson<Gate14ReMEFormalSTImplementationManifestV5>(manifestPath);
            Require(manifest.schema == Gate14ReMEFormalSTConstantsV5.ImplementationManifestSchema &&
                    manifest.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                    manifest.designId == Gate14ReMEFormalSTConstantsV5.DesignId &&
                    manifest.status == "FROZEN_FORMAL_ST_V5_IMPLEMENTATION_READY",
                    "Implementation manifest status is invalid.");
            Require(RelativePath(projectRoot, manifestPath) == authorization.implementationManifestRelativePath.Replace('\\', '/'),
                "Implementation manifest path is not bound to the execution authorization.");

            string schedulePath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-schedule"));
            string scheduleSha = RequiredSha256(arguments, "--g14me-schedule-sha256");
            Require(Sha256File(schedulePath) == scheduleSha && scheduleSha == authorization.scheduleSha256,
                "Formal ST schedule is not bound to the execution authorization.");
            Require(RelativePath(projectRoot, schedulePath) == authorization.scheduleRelativePath.Replace('\\', '/'),
                "Formal ST schedule path is not bound to the execution authorization.");
            Gate14ReMEFormalSTScheduleRowV5[] scheduleRows = ReadFormalSTScheduleJsonLines(schedulePath);
            ValidateSchedule(projectRoot, scheduleRows);

            string budgetPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-resource-budget"));
            string budgetSha = RequiredSha256(arguments, "--g14me-resource-budget-sha256");
            Require(Sha256File(budgetPath) == budgetSha && ManifestContains(manifest, RelativePath(projectRoot, budgetPath), budgetSha),
                "Resource budget is not bound to the implementation manifest.");
            FormalSTOperationalBudgetV5 budget = ReadJson<FormalSTOperationalBudgetV5>(budgetPath);
            ValidateBudget(budget, authorization.oracleBatchCount);

            string fairnessPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-fairness-binding"));
            string fairnessSha = RequiredSha256(arguments, "--g14me-fairness-binding-sha256");
            Require(Sha256File(fairnessPath) == fairnessSha && ManifestContains(manifest, RelativePath(projectRoot, fairnessPath), fairnessSha),
                "Fairness binding is not bound to the implementation manifest.");
            Gate14ReMEFairnessBindingV1 fairness = ReadJson<Gate14ReMEFairnessBindingV1>(fairnessPath);
            ValidateFairness(projectRoot, fairness);

            Require(ManifestContains(manifest, RunnerRelativePath, Sha256File(Path.Combine(projectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)))),
                "The running source does not match the frozen implementation manifest.");
            return new ExecutionContext(projectRoot, measuredRoot, authorization, manifest, manifestSha, budget, budgetSha, fairness, fairnessSha, scheduleRows, scheduleSha);
        }

        private static void ValidateBudget(FormalSTOperationalBudgetV5 budget, int authorizationBatchCount)
        {
            Require(budget.schema == Gate14ReMEFormalSTConstantsV5.ResourceBudgetSchema &&
                    budget.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                    budget.designId == Gate14ReMEFormalSTConstantsV5.DesignId &&
                    budget.status == "FROZEN_FORMAL_ST_V5_OPERATIONAL_LIMITS" &&
                    budget.eventGroupHardTimeoutMilliseconds == 300000L &&
                    budget.laneWallClockHardTimeoutMilliseconds == 600000L &&
                    budget.oracleBatchHardTimeoutMilliseconds == 3600000L &&
                    budget.instrumentProcessHardTimeoutMilliseconds == 600000L &&
                    budget.emptyBoundaryProcessHardTimeoutMilliseconds == 300000L &&
                    budget.plannerOperationBudgetMilliseconds == 240000d &&
                    budget.repairOperationBudgetMilliseconds == 240000d &&
                    budget.initializationOperationBudgetMilliseconds == 600000d &&
                    budget.laneAssignedCommittedMemoryBytes == 17179869184L &&
                    budget.formalRawAndDeliveryReservedStorageBytes == 64310367960L &&
                    budget.maximumConcurrentUnityProcesses == 1 &&
                    budget.maximumWholeSuperblockTechnicalReplacements == 0 &&
                    budget.runtimePlanningHeadroomFactor == 1.2d &&
                    budget.oracleCacheV5 != null &&
                    authorizationBatchCount >= budget.oracleCacheV5.minimumBatchCount &&
                    authorizationBatchCount <= budget.oracleCacheV5.maximumBatchCount &&
                    Gate14ReMEFormalSTConstantsV5.SuperblockCount % authorizationBatchCount == 0 &&
                    budget.oracleCacheV5.assignmentRule == "schedule-ordinal-mod-authorization-batch-count-v5" &&
                    budget.oracleCacheV5.algorithmNeutralImmutablePerInputCache &&
                    budget.oracleCacheV5.laneReferenceOracleEvaluations == 0 &&
                    budget.oracleCacheV5.strictSerialFreshUnityBatchProcesses,
                    "Resource budget differs from the frozen absolute values.");
        }

        private static void ValidateFairness(string projectRoot, Gate14ReMEFairnessBindingV1 fairness)
        {
            Require(fairness.schema == Gate14ReMEFormalSTConstantsV5.FairnessBindingSchema &&
                    fairness.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                    fairness.status == "FROZEN_SIX_ALGORITHM_BINDING" &&
                    fairness.algorithms != null && fairness.algorithms.Length == 6 &&
                    fairness.sameByteIdenticalInputBundle && fairness.oneFreshProcessPerAlgorithmLane &&
                    fairness.sameDynamicBoundary && fairness.sameOracle &&
                    !fairness.algorithmSpecificWarmupGcExtraQueryAllowed,
                    "Six-algorithm fairness binding is invalid.");
            Require(Sha256File(Path.Combine(projectRoot, fairness.navigationContractsRelativePath.Replace('/', Path.DirectorySeparatorChar))) == fairness.navigationContractsSha256,
                "Navigation contracts hash drifted.");
            Require(Sha256File(Path.Combine(projectRoot, fairness.navigationGridRelativePath.Replace('/', Path.DirectorySeparatorChar))) == fairness.navigationGridSha256,
                "Navigation grid hash drifted.");
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < fairness.algorithms.Length; index++)
            {
                ValidateAlgorithmBinding(projectRoot, fairness.algorithms[index]);
                Require(seen.Add(fairness.algorithms[index].algorithmId), "Duplicate algorithm id in fairness binding.");
            }
            for (int index = 0; index < Gate14ReMEFormalSTConstantsV5.NamedAlgorithms.Length; index++)
            {
                Require(seen.Contains(Gate14ReMEFormalSTConstantsV5.NamedAlgorithms[index]), "Fairness binding is missing a frozen algorithm.");
            }
        }

        private static void ValidateAlgorithmBinding(string projectRoot, Gate14ReMEAlgorithmBindingV1 binding)
        {
            Require(binding != null && Contains(Gate14ReMEFormalSTConstantsV5.NamedAlgorithms, binding.algorithmId), "Unknown algorithm binding.");
            string implementation = Path.Combine(projectRoot, binding.implementationRelativePath.Replace('/', Path.DirectorySeparatorChar));
            string specification = Path.Combine(projectRoot, binding.specificationRelativePath.Replace('/', Path.DirectorySeparatorChar));
            Require(Sha256File(implementation) == binding.implementationSha256, "Algorithm implementation hash drift: " + binding.algorithmId);
            Require(Sha256File(specification) == binding.specificationSha256, "Algorithm specification hash drift: " + binding.algorithmId);
        }

        private static Gate14ReMEAlgorithmBindingV1 FindAlgorithmBinding(Gate14ReMEFairnessBindingV1 fairness, string algorithmId)
        {
            for (int index = 0; index < fairness.algorithms.Length; index++)
            {
                if (fairness.algorithms[index].algorithmId == algorithmId) return fairness.algorithms[index];
            }
            throw new InvalidOperationException("Algorithm is not present in the frozen fairness binding: " + algorithmId);
        }

        private static void ValidateSchedule(string projectRoot, Gate14ReMEFormalSTScheduleRowV5[] rows)
        {
            Require(rows != null && rows.Length == Gate14ReMEFormalSTConstantsV5.SuperblockCount,
                "Formal ST schedule must contain exactly 1296 primary rows.");
            HashSet<string> superblocks = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> primaryInputs = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> replacementSuperblocks = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> replacementInputs = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> inputIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> identityBindings = new HashSet<string>(StringComparer.Ordinal);
            Dictionary<string, int> cellCounts = new Dictionary<string, int>(StringComparer.Ordinal);
            int[] orderCounts = new int[6];
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEFormalSTScheduleRowV5 row = rows[index];
                Require(row != null && row.schema == Gate14ReMEFormalSTConstantsV5.ScheduleRowSchema && row.ordinal == index,
                    "Schedule schema/ordinal mismatch at row " + index + ".");
                Require(row.replacement == null,
                    "Formal ST v5 freezes zero replacement schedule rows.");
                int expectedCellOrdinal = index / Gate14ReMEFormalSTConstantsV5.SuperblocksPerCell;
                int expectedReplicate = index % Gate14ReMEFormalSTConstantsV5.SuperblocksPerCell;
                int expectedContext = expectedReplicate % 18;
                int expectedOrder = expectedReplicate < 18
                    ? (expectedContext + expectedCellOrdinal) % 6
                    : (expectedContext + 3 + expectedCellOrdinal) % 6;
                Require(row.cellOrdinal == expectedCellOrdinal && row.replicateIndex == expectedReplicate &&
                        row.contextStratumIndex == expectedContext && row.orderIndex == expectedOrder,
                    "Schedule frozen cell/replicate/context/order rule mismatch at row " + index + ".");
                Require(!string.IsNullOrWhiteSpace(row.superblockId) && superblocks.Add(row.superblockId),
                    "Schedule superblock ids must be nonempty and unique.");
                string inputPath = ResolveExistingFile(projectRoot, row.inputRelativePath);
                Require(IsSha256(row.inputSha256) && Sha256File(inputPath) == row.inputSha256,
                    "Primary input hash mismatch in schedule row " + index + ".");
                string inputRelative = RelativePath(projectRoot, inputPath);
                Require(row.inputRelativePath.Replace('\\', '/') == inputRelative && primaryInputs.Add(inputRelative),
                    "Primary input paths must be canonical and unique.");
                Gate14ReMEFormalSTInputBundleV5 input = ReadJson<Gate14ReMEFormalSTInputBundleV5>(inputPath);
                Require(input.schema == Gate14ReMEFormalSTConstantsV5.InputSchema &&
                        input.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                        input.designId == Gate14ReMEFormalSTConstantsV5.DesignId &&
                        input.protocolId == Gate14ReMEFormalSTConstantsV5.ProtocolId &&
                        input.superblockId == row.superblockId &&
                        !string.IsNullOrWhiteSpace(input.inputId) && inputIds.Add(input.inputId),
                    "Primary input identity/schema differs from the frozen schedule or is duplicated.");
                ValidateScheduleLanes(row.algorithmOrder, index);
                Require(row.algorithmOrder.Length == Gate14ReMEFormalSTConstantsV5.WilliamsOrders[row.orderIndex].Length,
                    "Schedule order width mismatch at row " + index + ".");
                for (int laneIndex = 0; laneIndex < row.algorithmOrder.Length; laneIndex++)
                {
                    Require(row.algorithmOrder[laneIndex].algorithmId == Gate14ReMEFormalSTConstantsV5.WilliamsOrders[row.orderIndex][laneIndex],
                        "Schedule Williams-order mismatch at row " + index + ".");
                    identityBindings.Add(row.algorithmOrder[laneIndex].identityBindingSha256);
                }
                Require((input.gridEdge == 64 || input.gridEdge == 96 || input.gridEdge == 128) &&
                        (input.agentCount == 32 || input.agentCount == 64 || input.agentCount == 128) &&
                        (input.changedCellCount == 1 || input.changedCellCount == 9 || input.changedCellCount == 25 || input.changedCellCount == 81),
                    "Input G/N/F is outside the frozen v5 design at row " + index + ".");
                string cellKey = input.gridEdge + ":" + input.agentCount + ":" + input.changedCellCount;
                int cellCount;
                cellCounts.TryGetValue(cellKey, out cellCount);
                cellCounts[cellKey] = cellCount + 1;
                orderCounts[row.orderIndex]++;
            }
            Require(identityBindings.Count == 1, "All schedule rows must bind one common anonymous identity map SHA-256.");
            Require(cellCounts.Count == Gate14ReMEFormalSTConstantsV5.StructuralCellCount,
                "Formal ST schedule does not contain exactly 36 structural G x N x F cells.");
            foreach (KeyValuePair<string, int> pair in cellCounts)
            {
                Require(pair.Value == Gate14ReMEFormalSTConstantsV5.SuperblocksPerCell,
                    "Formal ST cell replicate count mismatch: " + pair.Key + ".");
            }
            for (int orderIndex = 0; orderIndex < orderCounts.Length; orderIndex++)
            {
                Require(orderCounts[orderIndex] == 216, "Formal ST Williams-order global balance mismatch.");
            }
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEFormalSTScheduleRowV5 row = rows[index];
                if (row.replacement != null)
                {
                    Require(!string.IsNullOrWhiteSpace(row.replacement.superblockId) &&
                            !superblocks.Contains(row.replacement.superblockId) && replacementSuperblocks.Add(row.replacement.superblockId),
                        "Replacement superblock id is invalid in schedule row " + index + ".");
                    string replacementPath = ResolveExistingFile(projectRoot, row.replacement.inputRelativePath);
                    Require(IsSha256(row.replacement.inputSha256) && Sha256File(replacementPath) == row.replacement.inputSha256,
                        "Replacement input hash mismatch in schedule row " + index + ".");
                    string replacementRelative = RelativePath(projectRoot, replacementPath);
                    Require(row.replacement.inputRelativePath.Replace('\\', '/') == replacementRelative &&
                            !primaryInputs.Contains(replacementRelative) && replacementInputs.Add(replacementRelative),
                        "Replacement inputs must be canonical, unique and disjoint from primary inputs.");
                    Gate14ReMEFormalSTInputBundleV5 replacementInput = ReadJson<Gate14ReMEFormalSTInputBundleV5>(replacementPath);
                    Require(replacementInput.schema == Gate14ReMEFormalSTConstantsV5.InputSchema &&
                            replacementInput.studyId == Gate14ReMEFormalSTConstantsV5.StudyId &&
                            replacementInput.protocolId == Gate14ReMEFormalSTConstantsV5.ProtocolId &&
                            replacementInput.superblockId == row.replacement.superblockId &&
                            !string.IsNullOrWhiteSpace(replacementInput.inputId) && inputIds.Add(replacementInput.inputId),
                        "Replacement input identity/schema differs from the frozen schedule or is duplicated.");
                }
            }
        }

        private static void ValidateScheduleLanes(Gate14ReMEFormalSTScheduleLaneV5[] lanes, int rowIndex)
        {
            Require(lanes != null && lanes.Length == 6, "Every schedule row must contain exactly six algorithm lanes.");
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> anonymousLanes = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < lanes.Length; index++)
            {
                Gate14ReMEFormalSTScheduleLaneV5 lane = lanes[index];
                Require(lane != null && Contains(Gate14ReMEFormalSTConstantsV5.NamedAlgorithms, lane.algorithmId) &&
                        Contains(Gate14ReMEFormalSTConstantsV5.AnonymousLanes, lane.anonymousLaneId) &&
                        IsSha256(lane.identityBindingSha256) && algorithms.Add(lane.algorithmId) && anonymousLanes.Add(lane.anonymousLaneId),
                    "Invalid or duplicate algorithm/lane binding in schedule row " + rowIndex + ".");
            }
        }

        private static bool TryFindScheduledInput(
            Gate14ReMEFormalSTScheduleRowV5[] rows,
            string inputRelativePath,
            string inputSha256,
            out Gate14ReMEFormalSTScheduleRowV5 scheduledRow,
            out bool replacement)
        {
            string normalized = inputRelativePath.Replace('\\', '/');
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEFormalSTScheduleRowV5 row = rows[index];
                if (row.inputRelativePath.Replace('\\', '/') == normalized && row.inputSha256 == inputSha256)
                {
                    scheduledRow = row;
                    replacement = false;
                    return true;
                }
                if (row.replacement != null && row.replacement.inputRelativePath.Replace('\\', '/') == normalized && row.replacement.inputSha256 == inputSha256)
                {
                    scheduledRow = row;
                    replacement = true;
                    return true;
                }
            }
            scheduledRow = null;
            replacement = false;
            return false;
        }

        private static bool ScheduleContainsLane(
            Gate14ReMEFormalSTScheduleRowV5 row,
            string algorithmId,
            string anonymousLaneId,
            string identityBindingSha256)
        {
            if (row == null || row.algorithmOrder == null) return false;
            for (int index = 0; index < row.algorithmOrder.Length; index++)
            {
                Gate14ReMEFormalSTScheduleLaneV5 lane = row.algorithmOrder[index];
                if (lane.algorithmId == algorithmId && lane.anonymousLaneId == anonymousLaneId && lane.identityBindingSha256 == identityBindingSha256) return true;
            }
            return false;
        }

        private static FormalSTOracleCacheV5 LoadOracleCache(
            Gate14ReMEFormalSTInputBundleV5 input,
            FormalSTOracleCacheBindingReceiptV5 binding,
            string agentTablePath)
        {
            Gate14ReMEOracleAgentRawV1[] rows = ReadJsonLines<Gate14ReMEOracleAgentRawV1>(agentTablePath);
            int expectedRows = input.agentCount * (1 + (2 * Gate14ReMEFormalSTConstantsV5.EventGroupCount));
            Require(rows.Length == expectedRows && rows.Length == binding.agentTableRows,
                "Oracle agent cache row count must equal N*(1+2*eventGroupCount).");
            Gate14ReMEOraclePathV1[] baseline = new Gate14ReMEOraclePathV1[input.agentCount];
            Gate14ReMEOraclePathV1[][] after = new Gate14ReMEOraclePathV1[Gate14ReMEFormalSTConstantsV5.EventGroupCount][];
            bool[] baselineSeen = new bool[input.agentCount];
            bool[,] beforeSeen = new bool[Gate14ReMEFormalSTConstantsV5.EventGroupCount, input.agentCount];
            bool[,] afterSeen = new bool[Gate14ReMEFormalSTConstantsV5.EventGroupCount, input.agentCount];
            HashSet<string> recordIds = new HashSet<string>(StringComparer.Ordinal);
            for (int groupIndex = 0; groupIndex < after.Length; groupIndex++) after[groupIndex] = new Gate14ReMEOraclePathV1[input.agentCount];

            for (int rowIndex = 0; rowIndex < rows.Length; rowIndex++)
            {
                Gate14ReMEOracleAgentRawV1 row = rows[rowIndex];
                Require(row != null && recordIds.Add(row.recordId), "Oracle agent cache record ids must be nonempty and unique.");
                Require(row.inputId == input.inputId && row.superblockId == input.superblockId &&
                        row.sourceRelativePath == binding.inputRelativePath && row.sourceSha256 == binding.inputSha256,
                    "Oracle agent cache identity/source binding mismatch.");
                Require(row.agentIndex >= 0 && row.agentIndex < input.agentCount &&
                        row.startX == input.starts[row.agentIndex].x && row.startY == input.starts[row.agentIndex].y &&
                        row.goalX == input.goal.x && row.goalY == input.goal.y,
                    "Oracle agent cache coordinate or agent-index mismatch.");
                Require((row.reachable && row.shortestPathCost >= 0d && !double.IsNaN(row.shortestPathCost) && !double.IsInfinity(row.shortestPathCost) && row.shortestPathSteps >= 0) ||
                        (!row.reachable && row.shortestPathCost == -1d && row.shortestPathSteps == -1),
                    "Oracle agent cache reachability/cost/steps tuple is invalid.");
                Gate14ReMEOraclePathV1 value = new Gate14ReMEOraclePathV1(row.reachable, row.shortestPathCost, row.shortestPathSteps);
                if (row.eventGroupIndex == -1)
                {
                    Require(row.comparisonSide == "baseline" && !baselineSeen[row.agentIndex],
                        "Oracle cache baseline rows must occur exactly once per agent.");
                    baselineSeen[row.agentIndex] = true;
                    baseline[row.agentIndex] = value;
                }
                else
                {
                    Require(row.eventGroupIndex >= 0 && row.eventGroupIndex < Gate14ReMEFormalSTConstantsV5.EventGroupCount,
                        "Oracle cache event-group index is out of range.");
                    if (row.comparisonSide == "before")
                    {
                        Require(!beforeSeen[row.eventGroupIndex, row.agentIndex],
                            "Oracle cache before rows must occur exactly once per event group and agent.");
                        beforeSeen[row.eventGroupIndex, row.agentIndex] = true;
                    }
                    else if (row.comparisonSide == "after")
                    {
                        Require(!afterSeen[row.eventGroupIndex, row.agentIndex],
                            "Oracle cache after rows must occur exactly once per event group and agent.");
                        afterSeen[row.eventGroupIndex, row.agentIndex] = true;
                        after[row.eventGroupIndex][row.agentIndex] = value;
                    }
                    else
                    {
                        throw new InvalidOperationException("Oracle cache comparisonSide must be baseline, before, or after.");
                    }
                }
            }
            for (int agentIndex = 0; agentIndex < input.agentCount; agentIndex++)
            {
                Require(baselineSeen[agentIndex], "Oracle cache is missing a baseline agent row.");
                for (int groupIndex = 0; groupIndex < Gate14ReMEFormalSTConstantsV5.EventGroupCount; groupIndex++)
                {
                    Require(beforeSeen[groupIndex, agentIndex] && afterSeen[groupIndex, agentIndex],
                        "Oracle cache is missing a before/after event-group agent row.");
                }
            }
            return new FormalSTOracleCacheV5(
                baseline,
                after,
                binding.agentTableRelativePath,
                binding.agentTableSha256,
                binding.agentTableRows);
        }

        private static void ValidateOracleEventTable(
            Gate14ReMEFormalSTInputBundleV5 input,
            FormalSTOracleCacheBindingReceiptV5 binding,
            string eventTablePath)
        {
            Gate14ReMEOracleEventRawV1[] rows = ReadJsonLines<Gate14ReMEOracleEventRawV1>(eventTablePath);
            Require(rows.Length == Gate14ReMEFormalSTConstantsV5.EventGroupCount && rows.Length == binding.eventTableRows,
                "Oracle event cache must contain exactly one row per event group.");
            bool[] seen = new bool[Gate14ReMEFormalSTConstantsV5.EventGroupCount];
            HashSet<string> recordIds = new HashSet<string>(StringComparer.Ordinal);
            for (int rowIndex = 0; rowIndex < rows.Length; rowIndex++)
            {
                Gate14ReMEOracleEventRawV1 row = rows[rowIndex];
                Require(row != null && recordIds.Add(row.recordId) && row.eventGroupIndex >= 0 &&
                        row.eventGroupIndex < Gate14ReMEFormalSTConstantsV5.EventGroupCount && !seen[row.eventGroupIndex],
                    "Oracle event cache record identity/index must be unique and in range.");
                seen[row.eventGroupIndex] = true;
                Gate14ReMEEventGroupV1 group = input.eventGroups[row.eventGroupIndex];
                Require(row.inputId == input.inputId && row.superblockId == input.superblockId &&
                        row.eventGroupId == group.eventGroupId && row.cycleIndex == group.cycleIndex &&
                        row.phase == group.phase && row.topology == group.topology &&
                        row.uniqueChangedCellCount == input.changedCellCount &&
                        row.minimumAffectedAgentsPassed && row.bottleneckHalfAgentsPassed &&
                        row.restoreGridBytesPassed && row.restoreOraclePassed &&
                        row.sourceRelativePath == binding.inputRelativePath && row.sourceSha256 == binding.inputSha256,
                    "Oracle event cache content or geometry gate mismatch.");
            }
            for (int groupIndex = 0; groupIndex < seen.Length; groupIndex++)
            {
                Require(seen[groupIndex], "Oracle event cache is missing an event-group row.");
            }
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.BidirectionalAStarRepeated) return new BidirectionalAStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (algorithmId == NavigationAlgorithmIds.LifelongPlanningAStar) return new LifelongPlanningAStarPlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new NotSupportedException("Unsupported algorithm: " + algorithmId);
        }

        private static int OracleBatchIndexForScheduleOrdinal(int ordinal, int batchCount)
        {
            Require(ordinal >= 0 && ordinal < Gate14ReMEFormalSTConstantsV5.SuperblockCount,
                "Oracle batch assignment requires formal schedule ordinal 0..1295.");
            Require(batchCount > 0 && batchCount <= Gate14ReMEFormalSTConstantsV5.SuperblockCount &&
                    Gate14ReMEFormalSTConstantsV5.SuperblockCount % batchCount == 0,
                "Oracle batch count must be a positive divisor of 1296.");
            return ordinal % batchCount;
        }

        private static NavigationPlanRequest CreatePlanRequest(
            Gate14ReMEFormalSTInputBundleV5 input,
            string lane,
            int agentIndex,
            long gridVersion,
            double budgetMilliseconds,
            string phase)
        {
            return new NavigationPlanRequest
            {
                runId = input.inputId + ":" + lane,
                requestId = input.inputId + ":" + lane + ":" + phase + ":agent:" + agentIndex,
                goalSetId = input.inputId + ":shared-goal",
                agentId = agentIndex,
                start = input.starts[agentIndex],
                goal = input.goal,
                expectedGridVersion = gridVersion,
                budgetMilliseconds = budgetMilliseconds
            };
        }

        private static Gate14ReMEOperationRawV1 OperationFromPlan(
            Gate14ReMEFormalSTInputBundleV5 input,
            string anonymousLaneId,
            string identityBindingSha256,
            Gate14ReMEAlgorithmBindingV1 algorithmBinding,
            string operationType,
            string operationId,
            int eventGroupIndex,
            int agentIndex,
            NavigationPlanResult plan,
            Gate14ReMEOraclePathV1 oracle,
            double reportedCost,
            bool correctness,
            string sourceRelativePath,
            string sourceSha256)
        {
            return OperationFromMetrics(input, anonymousLaneId, identityBindingSha256, algorithmBinding,
                operationType, operationId, eventGroupIndex, -1, agentIndex, plan.GridVersion,
                plan.Status, plan.FailureReason, plan.Metrics, oracle.Reachable, oracle.Cost,
                reportedCost, correctness, sourceRelativePath, sourceSha256);
        }

        private static Gate14ReMEOperationRawV1 OperationFromMetrics(
            Gate14ReMEFormalSTInputBundleV5 input,
            string anonymousLaneId,
            string identityBindingSha256,
            Gate14ReMEAlgorithmBindingV1 algorithmBinding,
            string operationType,
            string operationId,
            int eventGroupIndex,
            int partitionIndex,
            int agentIndex,
            long gridVersion,
            NavigationPlanStatus status,
            NavigationFailureReason failureReason,
            NavigationOperationMetrics metrics,
            bool oracleReachable,
            double oracleCost,
            double reportedCost,
            bool correctness,
            string sourceRelativePath,
            string sourceSha256)
        {
            NavigationOperationMetrics safe = metrics ?? new NavigationOperationMetrics();
            return new Gate14ReMEOperationRawV1
            {
                recordId = operationId,
                inputId = input.inputId,
                superblockId = input.superblockId,
                anonymousLaneId = anonymousLaneId,
                identityBindingSha256 = identityBindingSha256,
                operationType = operationType,
                operationId = operationId,
                eventGroupIndex = eventGroupIndex,
                partitionIndex = partitionIndex,
                agentIndex = agentIndex,
                gridVersion = gridVersion,
                status = status.ToString(),
                failureReasonCode = failureReason.ToString(),
                budgetExceeded = safe.budgetExceeded || status == NavigationPlanStatus.BudgetExceeded,
                elapsedCpuMilliseconds = safe.elapsedCpuMilliseconds,
                processedNodesOrCells = safe.processedNodesOrCells,
                expandedNodes = safe.expandedNodes,
                relaxedEdges = safe.relaxedEdges,
                repairedCells = safe.repairedCells,
                managedAllocatedBytes = safe.managedAllocatedBytes,
                oracleReachable = oracleReachable,
                oraclePathCost = oracleCost,
                reportedPathCost = reportedCost,
                oraclePathCostMatch = correctness,
                nativeMetricsSemanticsId = algorithmBinding.nativeMetricsSemanticsId,
                sourceRelativePath = sourceRelativePath,
                sourceSha256 = sourceSha256
            };
        }

        private static bool CorrectnessMatches(Gate14ReMEOraclePathV1 oracle, NavigationPlanResult plan, double reportedCost)
        {
            if (oracle.Reachable)
            {
                return plan.Status == NavigationPlanStatus.Succeeded &&
                       reportedCost >= 0d && Gate14ReMEReferenceOracleV1.NearlyEqual(oracle.Cost, reportedCost);
            }
            return plan.Status == NavigationPlanStatus.NoPath;
        }

        private static double ComputeReportedPathCost(IReadOnlyNavigationGrid grid, System.Collections.Generic.IReadOnlyList<GridCoordinate> path)
        {
            if (path == null || path.Count == 0) return -1d;
            double total = 0d;
            for (int index = 1; index < path.Count; index++)
            {
                GridCoordinate previous = path[index - 1];
                GridCoordinate current = path[index];
                bool diagonal = previous.x != current.x && previous.y != current.y;
                total += grid.GetTraversalCost(current) * (diagonal ? 1.4142135623730951d : 1d);
            }
            return total;
        }

        private static void WriteStateAndResources(
            ExecutionContext context,
            INavigationPlanner planner,
            Gate14ReMEFormalSTInputBundleV5 input,
            string anonymousLaneId,
            string identityBindingSha256,
            string measurementPointId,
            int eventGroupIndex,
            string sourceRelativePath,
            string sourceSha256,
            string statePath,
            string resourcesPath,
            ref int stateRows,
            ref int resourceRows,
            ref long peakCommittedBytes)
        {
            Gate14ReMEPersistentStateRawV1[] state = Gate14ReMEPersistentStateSizerV1.Measure(
                planner, input.inputId, input.superblockId, anonymousLaneId, identityBindingSha256,
                measurementPointId, eventGroupIndex, sourceRelativePath, sourceSha256);
            for (int index = 0; index < state.Length; index++) AppendJsonLine(statePath, state[index]);
            stateRows = checked(stateRows + state.Length);

            Gate14ReMEProcessResourceRawV1 resources = Gate14ReMEProcessResourcesV1.Capture(
                input.inputId + ":" + anonymousLaneId + ":resource:" + measurementPointId,
                input.inputId, input.superblockId, anonymousLaneId, identityBindingSha256,
                measurementPointId, eventGroupIndex, sourceRelativePath, sourceSha256);
            AppendJsonLine(resourcesPath, resources);
            resourceRows++;
            if (resources.privateMemoryBytes > peakCommittedBytes) peakCommittedBytes = resources.privateMemoryBytes;
            Require(resources.privateMemoryBytes <= context.Budget.laneAssignedCommittedMemoryBytes,
                "Lane committed-memory ceiling exceeded.");
        }

        private static void FlushOperations(string path, List<Gate14ReMEOperationRawV1> buffer, ref int count)
        {
            for (int index = 0; index < buffer.Count; index++) AppendJsonLine(path, buffer[index]);
            count = checked(count + buffer.Count);
            buffer.Clear();
        }

        private static void WriteProgressAtomic(string outputDirectory, Gate14ReMEFormalSTInputBundleV5 input, string lane, int groupIndex, string state)
        {
            WriteJsonAtomic(Path.Combine(outputDirectory, "process-progress.v1.json"), new ProgressReceipt
            {
                schema = "gate14re-me-process-progress-v1",
                inputId = input.inputId,
                anonymousLaneId = lane,
                eventGroupIndex = groupIndex,
                state = state,
                updatedAtUtc = DateTime.UtcNow.ToString("o")
            }, true);
        }

        private static void EmptyBoundary()
        {
            GC.KeepAlive(null);
        }

        private static Dictionary<string, string> ParseArguments(string[] values)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < values.Length; index++)
            {
                string value = values[index];
                if (!value.StartsWith("--g14me-", StringComparison.Ordinal)) continue;
                if (index + 1 >= values.Length) throw new InvalidOperationException("Missing value for " + value);
                if (result.ContainsKey(value)) throw new InvalidOperationException("Duplicate argument: " + value);
                result.Add(value, values[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            if (!arguments.TryGetValue(key, out value) || string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Required argument missing: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> arguments, string key)
        {
            string value = Required(arguments, key).ToLowerInvariant();
            if (!IsSha256(value)) throw new InvalidOperationException("Argument is not a lower-case SHA-256: " + key);
            return value;
        }

        private static string ResolveExistingFile(string projectRoot, string value)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithinProject(projectRoot, full), "Path escapes the project root: " + value);
            Require(File.Exists(full), "Required file is missing: " + full);
            return full;
        }

        private static string ResolveAuthorizedOutputDirectory(string projectRoot, string measuredRoot, string value)
        {
            string full = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithinProject(projectRoot, full), "Output path escapes the project root.");
            Require(IsWithinProject(measuredRoot, full), "Output path escapes the authorization-bound measured root.");
            string relative = RelativePath(projectRoot, full).Replace('\\', '/');
            string measuredRootPrefix = RelativePath(projectRoot, measuredRoot).Replace('\\', '/').TrimEnd('/') + "/";
            Require(relative.StartsWith(measuredRootPrefix, StringComparison.Ordinal), "Output path is outside the authorization-bound formal ST root.");
            return full;
        }

        private static bool IsReservedFormalMeasuredRoot(string relativePath)
        {
            string normalized = (relativePath ?? string.Empty).Replace('\\', '/').TrimEnd('/');
            if (!normalized.StartsWith(ReservedFormalMeasuredRootParentRelativePath, StringComparison.Ordinal)) return false;
            string leaf = normalized.Substring(ReservedFormalMeasuredRootParentRelativePath.Length);
            const string attemptPrefix = "attempt-";
            if (!leaf.StartsWith(attemptPrefix, StringComparison.Ordinal) || leaf.Length == attemptPrefix.Length || leaf.IndexOf('/') >= 0) return false;
            for (int index = attemptPrefix.Length; index < leaf.Length; index++)
            {
                if (leaf[index] < '0' || leaf[index] > '9') return false;
            }
            return true;
        }

        private static void RequireExactOutputDirectory(string actual, string expected, string mode)
        {
            string normalizedActual = Path.GetFullPath(actual).TrimEnd(Path.DirectorySeparatorChar);
            string normalizedExpected = Path.GetFullPath(expected).TrimEnd(Path.DirectorySeparatorChar);
            Require(string.Equals(normalizedActual, normalizedExpected, StringComparison.OrdinalIgnoreCase),
                "Output directory does not match the frozen " + mode + " schedule identity.");
        }

        private static bool IsWithinProject(string projectRoot, string fullPath)
        {
            string root = Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            return fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase);
        }

        private static string RelativePath(string projectRoot, string fullPath)
        {
            Uri root = new Uri(Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri path = new Uri(Path.GetFullPath(fullPath));
            return Uri.UnescapeDataString(root.MakeRelativeUri(path).ToString()).Replace('\\', '/');
        }

        private static void EnsureNewOutputDirectory(string path)
        {
            if (Directory.Exists(path) && Directory.GetFileSystemEntries(path).Length > 0)
            {
                throw new InvalidOperationException("Refusing to overwrite a non-empty output directory: " + path);
            }
            Directory.CreateDirectory(path);
        }

        private static T ReadJson<T>(string path)
        {
            T value = JsonUtility.FromJson<T>(File.ReadAllText(path, Encoding.UTF8));
            if (value == null) throw new InvalidOperationException("JSON deserialization returned null: " + path);
            return value;
        }

        private enum ScheduleReplacementTokenKind
        {
            Missing,
            Null,
            Object,
            Unsupported
        }

        private static Gate14ReMEFormalSTScheduleRowV5[] ReadFormalSTScheduleJsonLines(string path)
        {
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            List<Gate14ReMEFormalSTScheduleRowV5> values = new List<Gate14ReMEFormalSTScheduleRowV5>();
            for (int index = 0; index < lines.Length; index++)
            {
                if (string.IsNullOrWhiteSpace(lines[index])) continue;
                values.Add(ParseFormalSTScheduleRowJson(lines[index], path + ":" + (index + 1)));
            }
            return values.ToArray();
        }

        internal static Gate14ReMEFormalSTScheduleRowV5 ParseFormalSTScheduleRowJson(string json, string sourceLabel)
        {
            Require(!string.IsNullOrWhiteSpace(json), "Schedule JSON is empty: " + sourceLabel);
            ScheduleReplacementTokenKind replacementKind = GetTopLevelReplacementTokenKind(json, sourceLabel);
            Require(replacementKind != ScheduleReplacementTokenKind.Unsupported,
                "Schedule replacement must be a JSON object, JSON null, or an omitted member: " + sourceLabel);

            Gate14ReMEFormalSTScheduleRowV5 row = JsonUtility.FromJson<Gate14ReMEFormalSTScheduleRowV5>(json);
            Require(row != null, "Schedule JSON deserialization returned null: " + sourceLabel);

            if (replacementKind == ScheduleReplacementTokenKind.Missing ||
                replacementKind == ScheduleReplacementTokenKind.Null)
            {
                // Unity JsonUtility may instantiate an empty nested DTO for JSON null.
                // The raw top-level token is authoritative for null/omitted semantics.
                row.replacement = null;
            }
            else
            {
                Require(row.replacement != null,
                    "Schedule replacement object could not be deserialized: " + sourceLabel);
                Require(!string.IsNullOrWhiteSpace(row.replacement.superblockId) &&
                        !string.IsNullOrWhiteSpace(row.replacement.inputRelativePath) &&
                        IsSha256(row.replacement.inputSha256),
                    "Schedule replacement object is empty or incomplete: " + sourceLabel);
            }
            return row;
        }

        private static ScheduleReplacementTokenKind GetTopLevelReplacementTokenKind(string json, string sourceLabel)
        {
            int position = 0;
            SkipJsonWhitespace(json, ref position);
            RequireJsonCharacter(json, ref position, '{', sourceLabel);
            SkipJsonWhitespace(json, ref position);

            ScheduleReplacementTokenKind replacementKind = ScheduleReplacementTokenKind.Missing;
            bool replacementSeen = false;
            if (position < json.Length && json[position] == '}')
            {
                position++;
            }
            else
            {
                while (true)
                {
                    SkipJsonWhitespace(json, ref position);
                    string memberName = ReadJsonString(json, ref position, sourceLabel);
                    SkipJsonWhitespace(json, ref position);
                    RequireJsonCharacter(json, ref position, ':', sourceLabel);
                    SkipJsonWhitespace(json, ref position);
                    Require(position < json.Length, "Schedule JSON member has no value: " + sourceLabel);

                    ScheduleReplacementTokenKind currentKind = ScheduleReplacementTokenKind.Unsupported;
                    if (memberName == "replacement")
                    {
                        Require(!replacementSeen, "Schedule JSON contains duplicate top-level replacement members: " + sourceLabel);
                        replacementSeen = true;
                        if (json[position] == 'n') currentKind = ScheduleReplacementTokenKind.Null;
                        else if (json[position] == '{') currentKind = ScheduleReplacementTokenKind.Object;
                    }

                    SkipJsonValue(json, ref position, sourceLabel, 0);
                    if (memberName == "replacement") replacementKind = currentKind;
                    SkipJsonWhitespace(json, ref position);
                    Require(position < json.Length, "Schedule JSON object is unterminated: " + sourceLabel);
                    if (json[position] == '}')
                    {
                        position++;
                        break;
                    }
                    RequireJsonCharacter(json, ref position, ',', sourceLabel);
                }
            }

            SkipJsonWhitespace(json, ref position);
            Require(position == json.Length, "Schedule JSON has trailing content: " + sourceLabel);
            return replacementKind;
        }

        private static void SkipJsonValue(string json, ref int position, string sourceLabel, int depth)
        {
            Require(depth <= 128, "Schedule JSON nesting exceeds the frozen limit: " + sourceLabel);
            SkipJsonWhitespace(json, ref position);
            Require(position < json.Length, "Schedule JSON value is missing: " + sourceLabel);
            char token = json[position];
            if (token == '"')
            {
                ReadJsonString(json, ref position, sourceLabel);
                return;
            }
            if (token == '{')
            {
                position++;
                SkipJsonWhitespace(json, ref position);
                if (position < json.Length && json[position] == '}')
                {
                    position++;
                    return;
                }
                while (true)
                {
                    SkipJsonWhitespace(json, ref position);
                    ReadJsonString(json, ref position, sourceLabel);
                    SkipJsonWhitespace(json, ref position);
                    RequireJsonCharacter(json, ref position, ':', sourceLabel);
                    SkipJsonValue(json, ref position, sourceLabel, depth + 1);
                    SkipJsonWhitespace(json, ref position);
                    Require(position < json.Length, "Schedule JSON object is unterminated: " + sourceLabel);
                    if (json[position] == '}')
                    {
                        position++;
                        return;
                    }
                    RequireJsonCharacter(json, ref position, ',', sourceLabel);
                }
            }
            if (token == '[')
            {
                position++;
                SkipJsonWhitespace(json, ref position);
                if (position < json.Length && json[position] == ']')
                {
                    position++;
                    return;
                }
                while (true)
                {
                    SkipJsonValue(json, ref position, sourceLabel, depth + 1);
                    SkipJsonWhitespace(json, ref position);
                    Require(position < json.Length, "Schedule JSON array is unterminated: " + sourceLabel);
                    if (json[position] == ']')
                    {
                        position++;
                        return;
                    }
                    RequireJsonCharacter(json, ref position, ',', sourceLabel);
                }
            }
            if (token == 't')
            {
                SkipJsonLiteral(json, ref position, "true", sourceLabel);
                return;
            }
            if (token == 'f')
            {
                SkipJsonLiteral(json, ref position, "false", sourceLabel);
                return;
            }
            if (token == 'n')
            {
                SkipJsonLiteral(json, ref position, "null", sourceLabel);
                return;
            }
            SkipJsonNumber(json, ref position, sourceLabel);
        }

        private static string ReadJsonString(string json, ref int position, string sourceLabel)
        {
            Require(position < json.Length && json[position] == '"',
                "Schedule JSON expected a string: " + sourceLabel);
            position++;
            StringBuilder value = new StringBuilder();
            while (position < json.Length)
            {
                char current = json[position++];
                if (current == '"') return value.ToString();
                Require(current >= 0x20, "Schedule JSON string contains a control character: " + sourceLabel);
                if (current != '\\')
                {
                    value.Append(current);
                    continue;
                }

                Require(position < json.Length, "Schedule JSON string has an incomplete escape: " + sourceLabel);
                char escaped = json[position++];
                if (escaped == '"' || escaped == '\\' || escaped == '/') value.Append(escaped);
                else if (escaped == 'b') value.Append('\b');
                else if (escaped == 'f') value.Append('\f');
                else if (escaped == 'n') value.Append('\n');
                else if (escaped == 'r') value.Append('\r');
                else if (escaped == 't') value.Append('\t');
                else if (escaped == 'u')
                {
                    Require(position + 4 <= json.Length, "Schedule JSON string has an incomplete Unicode escape: " + sourceLabel);
                    int codePoint = 0;
                    for (int index = 0; index < 4; index++)
                    {
                        int hex = JsonHexValue(json[position++]);
                        Require(hex >= 0, "Schedule JSON string has an invalid Unicode escape: " + sourceLabel);
                        codePoint = (codePoint << 4) | hex;
                    }
                    value.Append((char)codePoint);
                }
                else
                {
                    throw new InvalidOperationException("Schedule JSON string has an invalid escape: " + sourceLabel);
                }
            }
            throw new InvalidOperationException("Schedule JSON string is unterminated: " + sourceLabel);
        }

        private static void SkipJsonNumber(string json, ref int position, string sourceLabel)
        {
            int start = position;
            if (position < json.Length && json[position] == '-') position++;
            Require(position < json.Length, "Schedule JSON number is incomplete: " + sourceLabel);
            if (json[position] == '0')
            {
                position++;
                Require(position >= json.Length || json[position] < '0' || json[position] > '9',
                    "Schedule JSON number has a leading zero: " + sourceLabel);
            }
            else
            {
                Require(json[position] >= '1' && json[position] <= '9',
                    "Schedule JSON value has an unsupported token: " + sourceLabel);
                while (position < json.Length && json[position] >= '0' && json[position] <= '9') position++;
            }
            if (position < json.Length && json[position] == '.')
            {
                position++;
                int fractionStart = position;
                while (position < json.Length && json[position] >= '0' && json[position] <= '9') position++;
                Require(position > fractionStart, "Schedule JSON number has an empty fraction: " + sourceLabel);
            }
            if (position < json.Length && (json[position] == 'e' || json[position] == 'E'))
            {
                position++;
                if (position < json.Length && (json[position] == '+' || json[position] == '-')) position++;
                int exponentStart = position;
                while (position < json.Length && json[position] >= '0' && json[position] <= '9') position++;
                Require(position > exponentStart, "Schedule JSON number has an empty exponent: " + sourceLabel);
            }
            Require(position > start, "Schedule JSON number is missing: " + sourceLabel);
        }

        private static void SkipJsonLiteral(string json, ref int position, string literal, string sourceLabel)
        {
            Require(position + literal.Length <= json.Length &&
                    string.CompareOrdinal(json, position, literal, 0, literal.Length) == 0,
                "Schedule JSON literal is invalid: " + sourceLabel);
            position += literal.Length;
        }

        private static void RequireJsonCharacter(string json, ref int position, char expected, string sourceLabel)
        {
            Require(position < json.Length && json[position] == expected,
                "Schedule JSON expected '" + expected + "': " + sourceLabel);
            position++;
        }

        private static void SkipJsonWhitespace(string json, ref int position)
        {
            while (position < json.Length)
            {
                char current = json[position];
                if (current != ' ' && current != '\t' && current != '\r' && current != '\n') return;
                position++;
            }
        }

        private static int JsonHexValue(char value)
        {
            if (value >= '0' && value <= '9') return value - '0';
            if (value >= 'a' && value <= 'f') return value - 'a' + 10;
            if (value >= 'A' && value <= 'F') return value - 'A' + 10;
            return -1;
        }

        private static T[] ReadJsonLines<T>(string path) where T : class
        {
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            List<T> values = new List<T>();
            for (int index = 0; index < lines.Length; index++)
            {
                if (string.IsNullOrWhiteSpace(lines[index])) continue;
                T value = JsonUtility.FromJson<T>(lines[index]);
                if (value == null) throw new InvalidOperationException("JSONL deserialization returned null at " + path + ":" + (index + 1));
                values.Add(value);
            }
            return values.ToArray();
        }

        private static void InitializeEmptyFile(string path)
        {
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite raw file: " + path);
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read)) { }
        }

        private static void AppendJsonLine<T>(string path, T value)
        {
            File.AppendAllText(path, JsonUtility.ToJson(value, false) + "\n", new UTF8Encoding(false));
        }

        private static void WriteJsonLines<T>(string path, T[] values)
        {
            InitializeEmptyFile(path);
            for (int index = 0; index < values.Length; index++) AppendJsonLine(path, values[index]);
        }

        private static void WriteJsonAtomic<T>(string path, T value, bool replace = false)
        {
            string temporary = path + ".tmp." + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + "\n", new UTF8Encoding(false));
            if (File.Exists(path))
            {
                if (!replace) throw new InvalidOperationException("Refusing to overwrite receipt: " + path);
                File.Delete(path);
            }
            File.Move(temporary, path);
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path)) return ToLowerHex(sha.ComputeHash(stream));
        }

        private static string ToLowerHex(byte[] bytes)
        {
            StringBuilder builder = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++) builder.Append(bytes[index].ToString("x2"));
            return builder.ToString();
        }

        private static bool IsSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char c = value[index];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
            }
            return true;
        }

        private static bool ManifestContains(Gate14ReMEFormalSTImplementationManifestV5 manifest, string relativePath, string sha256)
        {
            for (int index = 0; index < manifest.artifacts.Length; index++)
            {
                Gate14ReMEFormalSTFileBindingV5 item = manifest.artifacts[index];
                if (item.relativePath.Replace('\\', '/') == relativePath.Replace('\\', '/') && item.sha256 == sha256) return true;
            }
            return false;
        }

        private static bool Contains(string[] values, string value)
        {
            for (int index = 0; index < values.Length; index++) if (values[index] == value) return true;
            return false;
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void TryWriteFailureReceipt(Exception exception)
        {
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string value;
                if (!arguments.TryGetValue("--g14me-output-dir", out value)) return;
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string output = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
                if (!IsWithinProject(projectRoot, output)) return;
                string authorizationValue;
                string authorizationShaValue;
                if (!arguments.TryGetValue("--g14me-execution-authorization", out authorizationValue) ||
                    !arguments.TryGetValue("--g14me-execution-authorization-sha256", out authorizationShaValue)) return;
                string authorizationPath = ResolveExistingFile(projectRoot, authorizationValue);
                string expectedAuthorizationSha = authorizationShaValue.ToLowerInvariant();
                if (!IsSha256(expectedAuthorizationSha) || Sha256File(authorizationPath) != expectedAuthorizationSha) return;
                Gate14ReMEFormalSTExecutionAuthorizationV5 authorization = ReadJson<Gate14ReMEFormalSTExecutionAuthorizationV5>(authorizationPath);
                string normalizedAuthorizationMeasuredRoot = (authorization.measuredRootRelativePath ?? string.Empty).Replace('\\', '/').TrimEnd('/');
                if (authorization.schema != Gate14ReMEFormalSTConstantsV5.ExecutionAuthorizationSchema ||
                    authorization.studyId != Gate14ReMEFormalSTConstantsV5.StudyId ||
                    authorization.designId != Gate14ReMEFormalSTConstantsV5.DesignId ||
                    authorization.status != "AUTHORIZED_FORMAL_ST_COLLECTION" ||
                    !authorization.formalRootCreationAuthorized ||
                    !authorization.formalCollectionAuthorized ||
                    authorization.formalAnalysisAuthorized ||
                    authorization.mqAuthorized ||
                    authorization.mtAuthorized ||
                    !IsReservedFormalMeasuredRoot(normalizedAuthorizationMeasuredRoot)) return;
                string measuredRoot = Path.GetFullPath(Path.Combine(projectRoot, normalizedAuthorizationMeasuredRoot.Replace('/', Path.DirectorySeparatorChar)));
                if (!IsWithinProject(measuredRoot, output)) return;
                // Never let an invalid or absent authorization create a measured root.
                // A failure receipt is written only inside an output directory that the
                // already-authorized execution path created before the later failure.
                if (!Directory.Exists(output)) return;
                WriteJsonAtomic(Path.Combine(output, "process-failure-receipt.v1.json"), new FailureReceipt
                {
                    schema = "gate14re-me-formal-st-process-failure-receipt-v5",
                    studyId = Gate14ReMEFormalSTConstantsV5.StudyId,
                    status = "FAIL_CLOSED_PROCESS",
                    exceptionType = exception.GetType().FullName,
                    message = exception.Message,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                });
            }
            catch { }
        }

        private sealed class ExecutionContext
        {
            public readonly string ProjectRoot;
            public readonly string MeasuredRoot;
            public readonly Gate14ReMEFormalSTExecutionAuthorizationV5 Authorization;
            public readonly Gate14ReMEFormalSTImplementationManifestV5 Manifest;
            public readonly string ImplementationManifestSha256;
            public readonly FormalSTOperationalBudgetV5 Budget;
            public readonly string BudgetSha256;
            public readonly Gate14ReMEFairnessBindingV1 Fairness;
            public readonly string FairnessSha256;
            public readonly Gate14ReMEFormalSTScheduleRowV5[] ScheduleRows;
            public readonly string ScheduleSha256;

            public ExecutionContext(
                string projectRoot,
                string measuredRoot,
                Gate14ReMEFormalSTExecutionAuthorizationV5 authorization,
                Gate14ReMEFormalSTImplementationManifestV5 manifest,
                string implementationManifestSha256,
                FormalSTOperationalBudgetV5 budget,
                string budgetSha256,
                Gate14ReMEFairnessBindingV1 fairness,
                string fairnessSha256,
                Gate14ReMEFormalSTScheduleRowV5[] scheduleRows,
                string scheduleSha256)
            {
                ProjectRoot = projectRoot;
                MeasuredRoot = measuredRoot;
                Authorization = authorization;
                Manifest = manifest;
                ImplementationManifestSha256 = implementationManifestSha256;
                Budget = budget;
                BudgetSha256 = budgetSha256;
                Fairness = fairness;
                FairnessSha256 = fairnessSha256;
                ScheduleRows = scheduleRows;
                ScheduleSha256 = scheduleSha256;
            }
        }

        [Serializable]
        private sealed class FormalSTOperationalBudgetV5
        {
            public string schema;
            public string studyId;
            public string designId;
            public string status;
            public long eventGroupHardTimeoutMilliseconds;
            public long laneWallClockHardTimeoutMilliseconds;
            public long oracleBatchHardTimeoutMilliseconds;
            public long instrumentProcessHardTimeoutMilliseconds;
            public long emptyBoundaryProcessHardTimeoutMilliseconds;
            public double plannerOperationBudgetMilliseconds;
            public double repairOperationBudgetMilliseconds;
            public double initializationOperationBudgetMilliseconds;
            public long laneAssignedCommittedMemoryBytes;
            public long formalRawAndDeliveryReservedStorageBytes;
            public int maximumConcurrentUnityProcesses;
            public int maximumWholeSuperblockTechnicalReplacements;
            public double runtimePlanningHeadroomFactor;
            public FormalSTOracleCacheBudgetV5 oracleCacheV5;
        }

        [Serializable]
        private sealed class FormalSTOracleCacheBudgetV5
        {
            public int minimumBatchCount;
            public int maximumBatchCount;
            public string assignmentRule;
            public bool algorithmNeutralImmutablePerInputCache;
            public int laneReferenceOracleEvaluations;
            public bool strictSerialFreshUnityBatchProcesses;
        }

        [Serializable]
        private sealed class FormalSTOracleCacheBindingReceiptV5
        {
            public string schema;
            public string studyId;
            public string status;
            public int batchIndex;
            public int scheduleOrdinal;
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
            public string createdAtUtc;
        }

        [Serializable]
        private sealed class FormalSTOracleBatchMemberV5
        {
            public int scheduleOrdinal;
            public string inputId;
            public string superblockId;
            public string cacheBindingReceiptRelativePath;
            public string cacheBindingReceiptSha256;
        }

        [Serializable]
        private sealed class FormalSTOracleBatchReceiptV5
        {
            public string schema;
            public string studyId;
            public string status;
            public int batchIndex;
            public int batchCount;
            public string assignmentRule;
            public int inputCount;
            public FormalSTOracleBatchMemberV5[] members;
            public string createdAtUtc;
        }

        [Serializable]
        private sealed class FormalSTLaneOracleCacheLinkV5
        {
            public string schema;
            public string studyId;
            public string status;
            public string inputId;
            public string superblockId;
            public string anonymousLaneId;
            public string identityBindingSha256;
            public string oracleCacheBindingRelativePath;
            public string oracleCacheBindingSha256;
            public string agentTableRelativePath;
            public string agentTableSha256;
            public int agentTableRows;
            public int referenceOracleEvaluationsPerformedInsideLane;
            public string createdAtUtc;
        }

        private sealed class FormalSTOracleCacheV5
        {
            public readonly Gate14ReMEOraclePathV1[] Baseline;
            public readonly Gate14ReMEOraclePathV1[][] AfterEventGroups;
            public readonly string AgentTableRelativePath;
            public readonly string AgentTableSha256;
            public readonly int AgentTableRows;

            public FormalSTOracleCacheV5(
                Gate14ReMEOraclePathV1[] baseline,
                Gate14ReMEOraclePathV1[][] afterEventGroups,
                string agentTableRelativePath,
                string agentTableSha256,
                int agentTableRows)
            {
                Baseline = baseline;
                AfterEventGroups = afterEventGroups;
                AgentTableRelativePath = agentTableRelativePath;
                AgentTableSha256 = agentTableSha256;
                AgentTableRows = agentTableRows;
            }
        }

        [Serializable]
        private sealed class ProgressReceipt
        {
            public string schema;
            public string inputId;
            public string anonymousLaneId;
            public int eventGroupIndex;
            public string state;
            public string updatedAtUtc;
        }

        [Serializable]
        private sealed class FailureReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public string exceptionType;
            public string message;
            public string createdAtUtc;
        }
    }
}
#endif

