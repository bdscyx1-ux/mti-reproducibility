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
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Frozen, fail-closed entry point for the future Gate14Re-ME qualification.
    /// Merely compiling this source does not authorize execution. Every mode requires
    /// a later execution-authorization receipt bound to the frozen implementation
    /// manifest and schedule.
    /// </summary>
    public static class Gate14ReMELoadQualificationRunnerV1
    {
        private const string RunnerRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV1.cs";
        private const string OracleRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs";
        private const string InstrumentationRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEInstrumentationV1.cs";
        private const string ReservedMeasuredRootRelativePath = "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001";
        private const string ReservedOutputPrefix = ReservedMeasuredRootRelativePath + "/";

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                ExecutionContext context = ValidateExecutionContext(projectRoot, arguments);
                string mode = Required(arguments, "--g14me-mode");
                if (mode == "oracle") RunOracleMode(context, arguments);
                else if (mode == "lane") RunLaneMode(context, arguments);
                else if (mode == "empty-boundary") RunEmptyBoundaryMode(context, arguments);
                else if (mode == "instrument-self-test") RunInstrumentSelfTestMode(context, arguments);
                else throw new InvalidOperationException("Unsupported --g14me-mode: " + mode);
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

        private static void RunOracleMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            string inputPath = ResolveExistingFile(context.ProjectRoot, Required(arguments, "--g14me-input"));
            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            string inputRelativePath = RelativePath(context.ProjectRoot, inputPath);
            string inputSha256 = Sha256File(inputPath);
            Gate14ReMEQualificationScheduleRowV1 scheduledRow;
            bool scheduledReplacement;
            Require(TryFindScheduledInput(context.ScheduleRows, inputRelativePath, inputSha256, out scheduledRow, out scheduledReplacement),
                "Oracle input is not an exact path/hash member of the frozen qualification schedule.");
            Gate14ReMEQualificationInputBundleV1 input = ReadJson<Gate14ReMEQualificationInputBundleV1>(inputPath);
            string scheduledInstanceId = scheduledReplacement ? scheduledRow.replacement.superblockId : scheduledRow.superblockId;
            Require(input.superblockId == scheduledInstanceId, "Oracle input superblock id differs from the frozen schedule.");
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "oracle", scheduledInstanceId), "oracle");
            EnsureNewOutputDirectory(outputDirectory);
            string oracleSourcePath = Path.Combine(context.ProjectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar));
            string oracleSourceSha256 = Sha256File(oracleSourcePath);
            Gate14ReMEGeometryValidationResultV1 result = Gate14ReMEInputGeometryValidatorV1.Validate(
                input, inputRelativePath, inputSha256, OracleRelativePath, oracleSourceSha256);

            WriteJsonLines(Path.Combine(outputDirectory, "oracle-agent-checks.raw.v1.jsonl"), result.AgentRows);
            WriteJsonLines(Path.Combine(outputDirectory, "oracle-event-checks.raw.v1.jsonl"), result.EventRows);
            WriteJsonAtomic(Path.Combine(outputDirectory, "oracle-pass-receipt.v1.json"), result.Receipt);
        }

        private static void RunLaneMode(ExecutionContext context, Dictionary<string, string> arguments)
        {
            string algorithmId = Required(arguments, "--g14me-algorithm-id");
            string anonymousLaneId = Required(arguments, "--g14me-anonymous-lane-id");
            string identityBindingSha256 = RequiredSha256(arguments, "--g14me-identity-binding-sha256");
            Require(Contains(Gate14ReMEQualificationConstantsV1.AnonymousLanes, anonymousLaneId), "Anonymous lane id is outside ALG-A through ALG-F.");
            Gate14ReMEAlgorithmBindingV1 algorithmBinding = FindAlgorithmBinding(context.Fairness, algorithmId);
            ValidateAlgorithmBinding(context.ProjectRoot, algorithmBinding);

            string inputPath = ResolveExistingFile(context.ProjectRoot, Required(arguments, "--g14me-input"));
            string oracleReceiptPath = ResolveExistingFile(context.ProjectRoot, Required(arguments, "--g14me-oracle-receipt"));
            string expectedOracleReceiptSha = RequiredSha256(arguments, "--g14me-oracle-receipt-sha256");
            Require(Sha256File(oracleReceiptPath) == expectedOracleReceiptSha, "Oracle receipt hash mismatch.");
            Gate14ReMEOraclePassReceiptV1 oracleReceipt = ReadJson<Gate14ReMEOraclePassReceiptV1>(oracleReceiptPath);
            string inputSha256 = Sha256File(inputPath);
            string inputRelativePath = RelativePath(context.ProjectRoot, inputPath);
            Gate14ReMEQualificationScheduleRowV1 scheduledRow;
            bool scheduledReplacement;
            Require(TryFindScheduledInput(context.ScheduleRows, inputRelativePath, inputSha256, out scheduledRow, out scheduledReplacement),
                "Lane input is not an exact path/hash member of the frozen qualification schedule.");
            Require(ScheduleContainsLane(scheduledRow, algorithmId, anonymousLaneId, identityBindingSha256),
                "Algorithm/lane/identity tuple is not present in the frozen schedule row.");
            Require(oracleReceipt.schema == Gate14ReMEQualificationConstantsV1.OracleReceiptSchema &&
                    oracleReceipt.status == "PASS_ALGORITHM_NEUTRAL_GEOMETRY" &&
                    oracleReceipt.allGeometryChecksPassed &&
                    oracleReceipt.inputSha256 == inputSha256 &&
                    oracleReceipt.inputRelativePath == inputRelativePath,
                    "The lane is not bound to a valid prior algorithm-neutral geometry receipt.");

            string outputDirectory = ResolveAuthorizedOutputDirectory(context.ProjectRoot, context.MeasuredRoot, Required(arguments, "--g14me-output-dir"));
            Gate14ReMEQualificationInputBundleV1 input = ReadJson<Gate14ReMEQualificationInputBundleV1>(inputPath);
            string scheduledInstanceId = scheduledReplacement ? scheduledRow.replacement.superblockId : scheduledRow.superblockId;
            Require(input.inputId == oracleReceipt.inputId && input.superblockId == scheduledInstanceId && oracleReceipt.superblockId == scheduledInstanceId,
                "Input/superblock identity does not match the schedule and oracle receipt.");
            RequireExactOutputDirectory(outputDirectory, Path.Combine(context.MeasuredRoot, "raw", "superblocks", scheduledInstanceId, anonymousLaneId), "lane");
            EnsureNewOutputDirectory(outputDirectory);

            RunAlgorithmLane(
                context,
                input,
                inputRelativePath,
                inputSha256,
                RelativePath(context.ProjectRoot, oracleReceiptPath),
                expectedOracleReceiptSha,
                algorithmBinding,
                anonymousLaneId,
                identityBindingSha256,
                outputDirectory);
        }

        private static void RunAlgorithmLane(
            ExecutionContext context,
            Gate14ReMEQualificationInputBundleV1 input,
            string inputRelativePath,
            string inputSha256,
            string oracleReceiptRelativePath,
            string oracleReceiptSha256,
            Gate14ReMEAlgorithmBindingV1 algorithmBinding,
            string anonymousLaneId,
            string identityBindingSha256,
            string outputDirectory)
        {
            Stopwatch laneStopwatch = Stopwatch.StartNew();
            string runnerSha = Sha256File(Path.Combine(context.ProjectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
            Gate14ReMECountingGridV1 countingGrid = new Gate14ReMECountingGridV1(grid);
            INavigationPlanner planner = CreatePlanner(algorithmBinding.algorithmId);
            List<Gate14ReMEOperationRawV1> operationBuffer = new List<Gate14ReMEOperationRawV1>();
            int operationRows = 0;
            int eventRows = 0;
            int stateRows = 0;
            int resourceRows = 0;
            long peakCommittedBytes = 0L;
            bool instrumentValid = true;
            bool laneEligible = true;
            string failureReasonCode = string.Empty;

            string operationPath = Path.Combine(outputDirectory, "operations.raw.v1.jsonl");
            string eventPath = Path.Combine(outputDirectory, "event-groups.raw.v1.jsonl");
            string statePath = Path.Combine(outputDirectory, "persistent-state.raw.v1.jsonl");
            string resourcesPath = Path.Combine(outputDirectory, "process-resources.raw.v1.jsonl");
            InitializeEmptyFile(operationPath);
            InitializeEmptyFile(eventPath);
            InitializeEmptyFile(statePath);
            InitializeEmptyFile(resourcesPath);

            try
            {
                countingGrid.BeginWindow();
                long allocationBefore = Gate14ReMEAllocationCounterV1.Capture();
                Stopwatch initializationStopwatch = Stopwatch.StartNew();
                NavigationOperationMetrics initialization = planner.Initialize(countingGrid, new NavigationPlannerInitialization
                {
                    runId = input.inputId + ":" + anonymousLaneId,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = context.Budget.initializationOperationBudgetMilliseconds
                });
                initializationStopwatch.Stop();
                long allocationAfter = Gate14ReMEAllocationCounterV1.Capture();
                Gate14ReMEGridCounterSnapshotV1 initializationReads = countingGrid.EndWindow();
                instrumentValid = initializationReads.totalCalls >= 0L && allocationAfter >= allocationBefore;
                laneEligible = !initialization.budgetExceeded;
                if (!laneEligible) failureReasonCode = "INITIALIZATION_BUDGET_EXCEEDED";
                else if (!instrumentValid) failureReasonCode = "INITIALIZATION_INSTRUMENT_COUNTER_INVALID";
                Gate14ReMEOperationRawV1 initializationRow = OperationFromMetrics(
                    input, anonymousLaneId, identityBindingSha256, algorithmBinding,
                    "initialize", input.inputId + ":" + anonymousLaneId + ":initialize", -1, -1, -1, grid.Version,
                    NavigationPlanStatus.Succeeded, NavigationFailureReason.None,
                    initialization, false, -1d, -1d, true, inputRelativePath, inputSha256);
                initializationRow.elapsedCpuMilliseconds = initializationStopwatch.Elapsed.TotalMilliseconds;
                initializationRow.managedAllocatedBytes = Gate14ReMEAllocationCounterV1.Difference(allocationBefore, allocationAfter);
                operationBuffer.Add(initializationRow);
                FlushOperations(operationPath, operationBuffer, ref operationRows);
                WriteStateAndResources(context, planner, input, anonymousLaneId, identityBindingSha256,
                    "after-initialization", -1, inputRelativePath, inputSha256, statePath, resourcesPath,
                    ref stateRows, ref resourceRows, ref peakCommittedBytes);

                Gate14ReMEOraclePathV1[] initialOracle = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
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
                    long eventAllocationBefore = Gate14ReMEAllocationCounterV1.Capture();
                    Stopwatch eventStopwatch = Stopwatch.StartNew();
                    int repairCount = 0;
                    int planCount = 0;
                    int succeededCount = 0;
                    int noPathCount = 0;
                    int budgetExceededCount = 0;
                    bool correctnessPassed = true;
                    bool repairPassed = true;

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

                    Gate14ReMEOraclePathV1[] oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                        grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
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
                    long eventAllocationAfter = Gate14ReMEAllocationCounterV1.Capture();
                    Gate14ReMEGridCounterSnapshotV1 reads = countingGrid.EndWindow();
                    long eventAllocated = Gate14ReMEAllocationCounterV1.Difference(eventAllocationBefore, eventAllocationAfter);
                    double eventMilliseconds = eventStopwatch.Elapsed.TotalMilliseconds;
                    bool finitePositive = eventMilliseconds > 0d && !double.IsNaN(eventMilliseconds) && !double.IsInfinity(eventMilliseconds);
                    bool timeoutExceeded = eventMilliseconds > context.Budget.eventGroupHardTimeoutMilliseconds;
                    bool countersPassed = reads.totalCalls >= 0L && eventAllocated >= 0L;
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

                    Gate14ReMEEventGroupRawV1 eventRow = new Gate14ReMEEventGroupRawV1
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
                        allocationCounterStart = eventAllocationBefore,
                        allocationCounterEnd = eventAllocationAfter,
                        eventGroupManagedAllocatedBytes = eventAllocated,
                        allocationCounterId = Gate14ReMEAllocationCounterV1.CounterId,
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
                Gate14ReMELaneReceiptV1 receipt = new Gate14ReMELaneReceiptV1
                {
                    schema = Gate14ReMEQualificationConstantsV1.LaneReceiptSchema,
                    studyId = Gate14ReMEQualificationConstantsV1.StudyId,
                    protocolId = Gate14ReMEQualificationConstantsV1.ProtocolId,
                    status = laneTimeout || memoryExceeded || !laneEligible || !instrumentValid ? "COMPLETED_WITH_QUALIFICATION_FAILURE" : "COMPLETE_RAW_LANE",
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
                    eventGroupRows = eventRows,
                    operationRows = operationRows,
                    persistentStateRows = stateRows,
                    processResourceRows = resourceRows,
                    peakCommittedBytes = peakCommittedBytes,
                    laneWallClockMilliseconds = laneStopwatch.Elapsed.TotalMilliseconds,
                    instrumentValid = instrumentValid,
                    completed = eventRows == Gate14ReMEQualificationConstantsV1.EventGroupCount,
                    failureReasonCode = failureReasonCode,
                    createdAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "lane-receipt.v1.json"), receipt);
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
            string path = Path.Combine(outputDirectory, "empty-boundary.raw.v1.jsonl");
            InitializeEmptyFile(path);
            string sourceSha = Sha256File(Path.Combine(context.ProjectRoot, RunnerRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            for (int index = 0; index < 1000; index++)
            {
                long allocationBefore = Gate14ReMEAllocationCounterV1.Capture();
                long startTicks = Stopwatch.GetTimestamp();
                EmptyBoundary();
                long endTicks = Stopwatch.GetTimestamp();
                long allocationAfter = Gate14ReMEAllocationCounterV1.Capture();
                double elapsed = (endTicks - startTicks) * 1000d / Stopwatch.Frequency;
                AppendJsonLine(path, new Gate14ReMEEmptyBoundaryRawV1
                {
                    recordId = "empty:" + processOrdinal + ":" + index,
                    processOrdinal = processOrdinal,
                    iterationIndex = index,
                    stopwatchStartTicks = startTicks,
                    stopwatchEndTicks = endTicks,
                    elapsedMilliseconds = elapsed,
                    allocationCounterStart = allocationBefore,
                    allocationCounterEnd = allocationAfter,
                    allocatedBytes = Gate14ReMEAllocationCounterV1.Difference(allocationBefore, allocationAfter),
                    plannerInvoked = false,
                    sourceRelativePath = RunnerRelativePath,
                    sourceSha256 = sourceSha
                });
            }
            WriteJsonAtomic(Path.Combine(outputDirectory, "empty-boundary-receipt.v1.json"), new Gate14ReMEEmptyBoundaryReceiptV1
            {
                schema = Gate14ReMEQualificationConstantsV1.EmptyBoundaryReceiptSchema,
                studyId = Gate14ReMEQualificationConstantsV1.StudyId,
                status = "COMPLETE_EMPTY_BOUNDARY_RAW",
                processOrdinal = processOrdinal,
                rawIterationRows = 1000,
                plannerInvoked = false,
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

            long allocationBefore = Gate14ReMEAllocationCounterV1.Capture();
            byte[] positiveControl = new byte[1024 * 1024];
            positiveControl[positiveControl.Length - 1] = 1;
            long allocationAfter = Gate14ReMEAllocationCounterV1.Capture();
            bool allocationPassed = allocationAfter > allocationBefore && Gate14ReMEAllocationCounterV1.Difference(allocationBefore, allocationAfter) >= positiveControl.Length;

            bool clockPassed = true;
            long previous = Stopwatch.GetTimestamp();
            for (int index = 0; index < 10000; index++)
            {
                long current = Stopwatch.GetTimestamp();
                if (current < previous) { clockPassed = false; break; }
                previous = current;
            }
            bool sizerPassed = Gate14ReMEPersistentStateSizerV1.RunSyntheticFixture();
            bool csharpPass = knownAnswer && semantic && allocationPassed && clockPassed && sizerPassed;
            WriteJsonAtomic(Path.Combine(outputDirectory, "instrument-csharp-receipt.v1.json"), new Gate14ReMEInstrumentQualificationReceiptV1
            {
                schema = Gate14ReMEQualificationConstantsV1.InstrumentReceiptSchema,
                studyId = Gate14ReMEQualificationConstantsV1.StudyId,
                status = csharpPass ? "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING" : "FAIL_CLOSED_INSTRUMENT_COMPONENTS",
                gridReadProxyKnownAnswerPassed = knownAnswer,
                gridReadProxySemanticInvariancePassed = semantic,
                allocationCounterPositiveControlPassed = allocationPassed,
                persistentStateSizerSyntheticFixturePassed = sizerPassed,
                clockMonotonicityPassed = clockPassed,
                rawToExportRoundTripPassed = false,
                tamperNegativeTestPassed = false,
                missingNegativeTestPassed = false,
                duplicateNegativeTestPassed = false,
                anonymousLabelSwapNegativeTestPassed = false,
                implementationManifestSha256 = context.ImplementationManifestSha256,
                createdAtUtc = DateTime.UtcNow.ToString("o")
            });
            Require(csharpPass, "One or more C# instrument qualification components failed.");
        }

        private static ExecutionContext ValidateExecutionContext(string projectRoot, Dictionary<string, string> arguments)
        {
            string authorizationPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-execution-authorization"));
            string expectedAuthorizationSha = RequiredSha256(arguments, "--g14me-execution-authorization-sha256");
            Require(Sha256File(authorizationPath) == expectedAuthorizationSha, "Execution-authorization hash mismatch.");
            Gate14ReMEExecutionAuthorizationV1 authorization = ReadJson<Gate14ReMEExecutionAuthorizationV1>(authorizationPath);
            Require(authorization.schema == Gate14ReMEQualificationConstantsV1.ExecutionAuthorizationSchema &&
                    authorization.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
                    authorization.status == "AUTHORIZED_LOAD_QUALIFICATION_EXECUTION" &&
                    authorization.qualificationInputGenerationAuthorized &&
                    authorization.qualificationRootCreationAuthorized &&
                    authorization.compileOrUnityExecutionAuthorized &&
                    authorization.qualificationExecutionAuthorized &&
                    !authorization.formalCollectionAuthorized &&
                    !authorization.formalAnalysisAuthorized &&
                    !string.IsNullOrWhiteSpace(authorization.measuredRootRelativePath) &&
                    IsSha256(authorization.implementationManifestSha256) &&
                    IsSha256(authorization.scheduleSha256) &&
                    !string.IsNullOrWhiteSpace(authorization.authorizationNonce),
                    "Execution authorization is absent, incomplete, or exceeds the qualification boundary.");
            string measuredRoot = Path.GetFullPath(Path.Combine(projectRoot, authorization.measuredRootRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            Require(IsWithinProject(projectRoot, measuredRoot) &&
                    RelativePath(projectRoot, measuredRoot) == ReservedMeasuredRootRelativePath &&
                    authorization.measuredRootRelativePath.Replace('\\', '/') == ReservedMeasuredRootRelativePath,
                "Execution authorization is not bound to the exact frozen measured root.");

            string manifestPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-implementation-manifest"));
            string manifestSha = RequiredSha256(arguments, "--g14me-implementation-manifest-sha256");
            Require(Sha256File(manifestPath) == manifestSha && manifestSha == authorization.implementationManifestSha256,
                "Implementation manifest is not bound to the execution authorization.");
            Gate14ReMEImplementationManifestV1 manifest = ReadJson<Gate14ReMEImplementationManifestV1>(manifestPath);
            Require(manifest.schema == Gate14ReMEQualificationConstantsV1.ImplementationManifestSchema &&
                    manifest.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
                    manifest.status == "FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED",
                    "Implementation manifest status is invalid.");
            Require(RelativePath(projectRoot, manifestPath) == authorization.implementationManifestRelativePath.Replace('\\', '/'),
                "Implementation manifest path is not bound to the execution authorization.");

            string schedulePath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-schedule"));
            string scheduleSha = RequiredSha256(arguments, "--g14me-schedule-sha256");
            Require(Sha256File(schedulePath) == scheduleSha && scheduleSha == authorization.scheduleSha256,
                "Qualification schedule is not bound to the execution authorization.");
            Require(RelativePath(projectRoot, schedulePath) == authorization.scheduleRelativePath.Replace('\\', '/'),
                "Qualification schedule path is not bound to the execution authorization.");
            Gate14ReMEQualificationScheduleRowV1[] scheduleRows = ReadJsonLines<Gate14ReMEQualificationScheduleRowV1>(schedulePath);
            ValidateSchedule(projectRoot, scheduleRows);

            string budgetPath = ResolveExistingFile(projectRoot, Required(arguments, "--g14me-resource-budget"));
            string budgetSha = RequiredSha256(arguments, "--g14me-resource-budget-sha256");
            Require(Sha256File(budgetPath) == budgetSha && ManifestContains(manifest, RelativePath(projectRoot, budgetPath), budgetSha),
                "Resource budget is not bound to the implementation manifest.");
            Gate14ReMEResourceBudgetV1 budget = ReadJson<Gate14ReMEResourceBudgetV1>(budgetPath);
            ValidateBudget(budget);

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

        private static void ValidateBudget(Gate14ReMEResourceBudgetV1 budget)
        {
            Require(budget.schema == Gate14ReMEQualificationConstantsV1.ResourceBudgetSchema &&
                    budget.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
                    budget.status == "FROZEN_PREEXECUTION_BUDGETS" &&
                    budget.eventGroupHardTimeoutMilliseconds == 300000L &&
                    budget.laneWallClockHardTimeoutMilliseconds == 5400000L &&
                    budget.oracleInputHardTimeoutMilliseconds == 900000L &&
                    budget.instrumentProcessHardTimeoutMilliseconds == 600000L &&
                    budget.emptyBoundaryProcessHardTimeoutMilliseconds == 600000L &&
                    budget.plannerOperationBudgetMilliseconds == 240000d &&
                    budget.repairOperationBudgetMilliseconds == 240000d &&
                    budget.initializationOperationBudgetMilliseconds == 600000d &&
                    budget.laneAssignedCommittedMemoryBytes == 17179869184L &&
                    budget.qualificationReservedStorageBytes == 51539607552L &&
                    budget.formalRawAndDeliveryReservedStorageBytes == 103079215104L &&
                    budget.maximumConcurrentUnityProcesses == 1 &&
                    budget.maximumWholeSuperblockTechnicalReplacements == 1 &&
                    budget.minimumHeadroomFactor == 2d,
                    "Resource budget differs from the frozen absolute values.");
        }

        private static void ValidateFairness(string projectRoot, Gate14ReMEFairnessBindingV1 fairness)
        {
            Require(fairness.schema == Gate14ReMEQualificationConstantsV1.FairnessBindingSchema &&
                    fairness.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
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
            for (int index = 0; index < Gate14ReMEQualificationConstantsV1.NamedAlgorithms.Length; index++)
            {
                Require(seen.Contains(Gate14ReMEQualificationConstantsV1.NamedAlgorithms[index]), "Fairness binding is missing a frozen algorithm.");
            }
        }

        private static void ValidateAlgorithmBinding(string projectRoot, Gate14ReMEAlgorithmBindingV1 binding)
        {
            Require(binding != null && Contains(Gate14ReMEQualificationConstantsV1.NamedAlgorithms, binding.algorithmId), "Unknown algorithm binding.");
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

        private static void ValidateSchedule(string projectRoot, Gate14ReMEQualificationScheduleRowV1[] rows)
        {
            Require(rows != null && rows.Length == 162, "Qualification schedule must contain exactly 162 primary rows.");
            HashSet<string> superblocks = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> primaryInputs = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> replacementSuperblocks = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> replacementInputs = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> inputIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> identityBindings = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEQualificationScheduleRowV1 row = rows[index];
                Require(row != null && row.schema == "gate14re-me-load-qualification-schedule-row-v1" && row.ordinal == index,
                    "Schedule schema/ordinal mismatch at row " + index + ".");
                Require(!string.IsNullOrWhiteSpace(row.superblockId) && superblocks.Add(row.superblockId),
                    "Schedule superblock ids must be nonempty and unique.");
                string inputPath = ResolveExistingFile(projectRoot, row.inputRelativePath);
                Require(IsSha256(row.inputSha256) && Sha256File(inputPath) == row.inputSha256,
                    "Primary input hash mismatch in schedule row " + index + ".");
                string inputRelative = RelativePath(projectRoot, inputPath);
                Require(row.inputRelativePath.Replace('\\', '/') == inputRelative && primaryInputs.Add(inputRelative),
                    "Primary input paths must be canonical and unique.");
                Gate14ReMEQualificationInputBundleV1 input = ReadJson<Gate14ReMEQualificationInputBundleV1>(inputPath);
                Require(input.schema == Gate14ReMEQualificationConstantsV1.InputSchema &&
                        input.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
                        input.protocolId == Gate14ReMEQualificationConstantsV1.ProtocolId &&
                        input.superblockId == row.superblockId &&
                        !string.IsNullOrWhiteSpace(input.inputId) && inputIds.Add(input.inputId),
                    "Primary input identity/schema differs from the frozen schedule or is duplicated.");
                ValidateScheduleLanes(row.algorithmOrder, index);
                for (int laneIndex = 0; laneIndex < row.algorithmOrder.Length; laneIndex++)
                {
                    identityBindings.Add(row.algorithmOrder[laneIndex].identityBindingSha256);
                }
            }
            Require(identityBindings.Count == 1, "All schedule rows must bind one common anonymous identity map SHA-256.");
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEQualificationScheduleRowV1 row = rows[index];
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
                    Gate14ReMEQualificationInputBundleV1 replacementInput = ReadJson<Gate14ReMEQualificationInputBundleV1>(replacementPath);
                    Require(replacementInput.schema == Gate14ReMEQualificationConstantsV1.InputSchema &&
                            replacementInput.studyId == Gate14ReMEQualificationConstantsV1.StudyId &&
                            replacementInput.protocolId == Gate14ReMEQualificationConstantsV1.ProtocolId &&
                            replacementInput.superblockId == row.replacement.superblockId &&
                            !string.IsNullOrWhiteSpace(replacementInput.inputId) && inputIds.Add(replacementInput.inputId),
                        "Replacement input identity/schema differs from the frozen schedule or is duplicated.");
                }
            }
        }

        private static void ValidateScheduleLanes(Gate14ReMEQualificationScheduleLaneV1[] lanes, int rowIndex)
        {
            Require(lanes != null && lanes.Length == 6, "Every schedule row must contain exactly six algorithm lanes.");
            HashSet<string> algorithms = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> anonymousLanes = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < lanes.Length; index++)
            {
                Gate14ReMEQualificationScheduleLaneV1 lane = lanes[index];
                Require(lane != null && Contains(Gate14ReMEQualificationConstantsV1.NamedAlgorithms, lane.algorithmId) &&
                        Contains(Gate14ReMEQualificationConstantsV1.AnonymousLanes, lane.anonymousLaneId) &&
                        IsSha256(lane.identityBindingSha256) && algorithms.Add(lane.algorithmId) && anonymousLanes.Add(lane.anonymousLaneId),
                    "Invalid or duplicate algorithm/lane binding in schedule row " + rowIndex + ".");
            }
        }

        private static bool TryFindScheduledInput(
            Gate14ReMEQualificationScheduleRowV1[] rows,
            string inputRelativePath,
            string inputSha256,
            out Gate14ReMEQualificationScheduleRowV1 scheduledRow,
            out bool replacement)
        {
            string normalized = inputRelativePath.Replace('\\', '/');
            for (int index = 0; index < rows.Length; index++)
            {
                Gate14ReMEQualificationScheduleRowV1 row = rows[index];
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
            Gate14ReMEQualificationScheduleRowV1 row,
            string algorithmId,
            string anonymousLaneId,
            string identityBindingSha256)
        {
            if (row == null || row.algorithmOrder == null) return false;
            for (int index = 0; index < row.algorithmOrder.Length; index++)
            {
                Gate14ReMEQualificationScheduleLaneV1 lane = row.algorithmOrder[index];
                if (lane.algorithmId == algorithmId && lane.anonymousLaneId == anonymousLaneId && lane.identityBindingSha256 == identityBindingSha256) return true;
            }
            return false;
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

        private static NavigationPlanRequest CreatePlanRequest(
            Gate14ReMEQualificationInputBundleV1 input,
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
            Gate14ReMEQualificationInputBundleV1 input,
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
            Gate14ReMEQualificationInputBundleV1 input,
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
            Gate14ReMEQualificationInputBundleV1 input,
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

        private static void WriteProgressAtomic(string outputDirectory, Gate14ReMEQualificationInputBundleV1 input, string lane, int groupIndex, string state)
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
            Require(relative.StartsWith(ReservedOutputPrefix, StringComparison.Ordinal), "Output path is outside the reserved qualification root.");
            return full;
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

        private static bool ManifestContains(Gate14ReMEImplementationManifestV1 manifest, string relativePath, string sha256)
        {
            for (int index = 0; index < manifest.artifacts.Length; index++)
            {
                Gate14ReMEFileBindingV1 item = manifest.artifacts[index];
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
                string relative = RelativePath(projectRoot, output).Replace('\\', '/');
                if (!relative.StartsWith(ReservedOutputPrefix, StringComparison.Ordinal)) return;
                // Never let an invalid or absent authorization create a measured root.
                // A failure receipt is written only inside an output directory that the
                // already-authorized execution path created before the later failure.
                if (!Directory.Exists(output)) return;
                WriteJsonAtomic(Path.Combine(output, "process-failure-receipt.v1.json"), new FailureReceipt
                {
                    schema = "gate14re-me-process-failure-receipt-v1",
                    studyId = Gate14ReMEQualificationConstantsV1.StudyId,
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
            public readonly Gate14ReMEExecutionAuthorizationV1 Authorization;
            public readonly Gate14ReMEImplementationManifestV1 Manifest;
            public readonly string ImplementationManifestSha256;
            public readonly Gate14ReMEResourceBudgetV1 Budget;
            public readonly string BudgetSha256;
            public readonly Gate14ReMEFairnessBindingV1 Fairness;
            public readonly string FairnessSha256;
            public readonly Gate14ReMEQualificationScheduleRowV1[] ScheduleRows;
            public readonly string ScheduleSha256;

            public ExecutionContext(
                string projectRoot,
                string measuredRoot,
                Gate14ReMEExecutionAuthorizationV1 authorization,
                Gate14ReMEImplementationManifestV1 manifest,
                string implementationManifestSha256,
                Gate14ReMEResourceBudgetV1 budget,
                string budgetSha256,
                Gate14ReMEFairnessBindingV1 fairness,
                string fairnessSha256,
                Gate14ReMEQualificationScheduleRowV1[] scheduleRows,
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
