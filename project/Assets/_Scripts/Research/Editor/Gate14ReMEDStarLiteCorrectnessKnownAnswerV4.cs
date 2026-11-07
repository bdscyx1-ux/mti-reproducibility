using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Parameterized, one-shot post-repair correctness known answer. A fresh
    /// output root is mandatory for every invocation; measured metrics are
    /// never emitted.
    /// </summary>
    public static class Gate14ReMEDStarLiteCorrectnessKnownAnswerV4
    {
        private const string ExpectedInputSha256 = "3fbe00d7a27a75551b9ebb7711ccfcd2a0678679e94c3097b7a00209e7261ff3";
        private const string ExpectedAlgorithmSha256 = "b6938a3389de4764a26ed15c59582dd31017e8b44c38fa004be356989ca8d199";
        private const string ExpectedSpecificationSha256 = "d25ea4cadf6e08b802c51d8b2a3245da8b436d4b1029973bed576d89de34d732";
        private const string ExpectedOracleSha256 = "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25";
        private const string InputRelativePath = "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/inputs/core/G14ME-QSB-C002.input.v2.json";
        private const string AllowedOutputPrefix = "Research/Verification/Gate14Re-ME/qualification-dstar-lite-oracle-correctness-corrigendum-attempt-001/";
        private const string AlgorithmRelativePath = "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs";
        private const string SpecificationRelativePath = "Research/DStar_Lite_Specification.md";
        private const string OracleRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs";
        private const string SourceRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMEDStarLiteCorrectnessKnownAnswerV4.cs";
        private const string BurstHostLifecycleSourceRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMEBurstHostLifecycleV1.cs";
        private const string OutputArgument = "-gate14DStarKnownAnswerOutputRelativePath";
        private const string ExecutionIdArgument = "-gate14DStarKnownAnswerExecutionId";
        private const string PostReceiptDrainArgument = "-gate14DStarPostReceiptDrainMilliseconds";
        private const string BurstCompletionTimeoutArgument = "-gate14DStarBurstCompletionTimeoutMilliseconds";
        private const int MaximumPostReceiptDrainMilliseconds = 300000;

        [Serializable]
        private sealed class KnownAnswerReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public string outputRelativePath;
            public string inputRelativePath;
            public string inputSha256;
            public string algorithmSourceRelativePath;
            public string algorithmSourceSha256;
            public string specificationRelativePath;
            public string specificationSha256;
            public string oracleSourceRelativePath;
            public string oracleSourceSha256;
            public int initialQueryChecks;
            public int eventGroupCount;
            public int repairOperationChecks;
            public int postEventQueryChecks;
            public string failedPhase;
            public int failedEventGroupIndex;
            public int failedAgentIndex;
            public string failureKind;
            public string error;
            public string completedAtUtc;
        }

        [Serializable]
        private sealed class PostReceiptDrainReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public int requestedDrainMilliseconds;
            public long observedDrainMilliseconds;
            public bool burstDisableCompilationArgumentPresent;
            public bool burstForceSyncCompilationArgumentPresent;
            public string sourceRelativePath;
            public string sourceSha256;
            public string completedAtUtc;
        }

        [Serializable]
        private sealed class BurstCompletionReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public int timeoutMilliseconds;
            public bool initialCompilationDone;
            public bool finalCompilationDone;
            public int requiredConsecutiveDoneObservations;
            public int achievedConsecutiveDoneObservations;
            public int pollCount;
            public long elapsedMilliseconds;
            public string reflectedType;
            public string reflectedMethod;
            public string lifecycleSourceRelativePath;
            public string lifecycleSourceSha256;
            public string completedAtUtc;
        }

        [Serializable]
        private sealed class HostLifecycleFailureReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public string error;
            public string failedAtUtc;
        }

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = null;
            try
            {
                outputDirectory = RunKnownAnswer();
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;

                int burstCompletionTimeoutMilliseconds = ReadOptionalNonNegativeIntegerArgument(BurstCompletionTimeoutArgument, 0);
                if (burstCompletionTimeoutMilliseconds > 0)
                {
                    Gate14ReMEBurstHostLifecycleV1.WaitResult waitResult =
                        Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(burstCompletionTimeoutMilliseconds);
                    BurstCompletionReceipt burstReceipt = new BurstCompletionReceipt
                    {
                        schema = "gate14re-me-burst-current-compilation-completion-receipt-v1",
                        studyId = "Gate14Re-ME",
                        executionId = ReadRequiredArgument(ExecutionIdArgument),
                        status = "PASS_BURST_CURRENT_COMPILATION_STABLY_DONE",
                        passed = waitResult.finalCompilationDone,
                        timeoutMilliseconds = burstCompletionTimeoutMilliseconds,
                        initialCompilationDone = waitResult.initialCompilationDone,
                        finalCompilationDone = waitResult.finalCompilationDone,
                        requiredConsecutiveDoneObservations = waitResult.requiredConsecutiveDoneObservations,
                        achievedConsecutiveDoneObservations = waitResult.achievedConsecutiveDoneObservations,
                        pollCount = waitResult.pollCount,
                        elapsedMilliseconds = waitResult.elapsedMilliseconds,
                        reflectedType = waitResult.reflectedType,
                        reflectedMethod = waitResult.reflectedMethod,
                        lifecycleSourceRelativePath = BurstHostLifecycleSourceRelativePath,
                        lifecycleSourceSha256 = Sha256File(Path.Combine(projectRoot, BurstHostLifecycleSourceRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                        completedAtUtc = DateTimeOffset.UtcNow.ToString("o")
                    };
                    File.WriteAllText(Path.Combine(outputDirectory, "burst-current-compilation-completion.v1.json"), JsonUtility.ToJson(burstReceipt, true));
                }

                int drainMilliseconds = ReadOptionalNonNegativeIntegerArgument(PostReceiptDrainArgument, 0);
                Require(drainMilliseconds <= MaximumPostReceiptDrainMilliseconds, "Requested post-receipt drain exceeds the diagnostic maximum.");

                System.Diagnostics.Stopwatch stopwatch = System.Diagnostics.Stopwatch.StartNew();
                System.Threading.Thread.Sleep(drainMilliseconds);
                stopwatch.Stop();

                string[] commandLineArguments = Environment.GetCommandLineArgs();
                PostReceiptDrainReceipt drainReceipt = new PostReceiptDrainReceipt
                {
                    schema = "gate14re-me-dstar-lite-known-answer-post-receipt-drain-receipt-v1",
                    studyId = "Gate14Re-ME",
                    executionId = ReadRequiredArgument(ExecutionIdArgument),
                    status = "PASS_POST_RECEIPT_DRAIN_COMPLETED",
                    passed = true,
                    requestedDrainMilliseconds = drainMilliseconds,
                    observedDrainMilliseconds = stopwatch.ElapsedMilliseconds,
                    burstDisableCompilationArgumentPresent = ContainsArgument(commandLineArguments, "--burst-disable-compilation"),
                    burstForceSyncCompilationArgumentPresent = ContainsArgument(commandLineArguments, "--burst-force-sync-compilation"),
                    sourceRelativePath = SourceRelativePath,
                    sourceSha256 = Sha256File(Path.Combine(projectRoot, SourceRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                    completedAtUtc = DateTimeOffset.UtcNow.ToString("o")
                };
                File.WriteAllText(Path.Combine(outputDirectory, "post-receipt-drain-completion.v1.json"), JsonUtility.ToJson(drainReceipt, true));
                exitCode = 0;
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
                TryWriteHostLifecycleFailure(outputDirectory, exception);
            }
            finally
            {
                // Match the already-qualified RunnerV2 host-lifecycle contract.
                // Returning and relying on -quit leaves this Unity build spinning
                // after its licensing channels disconnect.
                EditorApplication.Exit(exitCode);
            }
        }

        private static void TryWriteHostLifecycleFailure(string outputDirectory, Exception exception)
        {
            if (string.IsNullOrEmpty(outputDirectory) || !Directory.Exists(outputDirectory)) return;
            try
            {
                HostLifecycleFailureReceipt receipt = new HostLifecycleFailureReceipt
                {
                    schema = "gate14re-me-known-answer-host-lifecycle-failure-receipt-v1",
                    studyId = "Gate14Re-ME",
                    executionId = ReadRequiredArgument(ExecutionIdArgument),
                    status = "FAIL_POST_CORRECTNESS_HOST_LIFECYCLE",
                    passed = false,
                    error = exception.GetType().FullName + ": " + exception.Message,
                    failedAtUtc = DateTimeOffset.UtcNow.ToString("o")
                };
                File.WriteAllText(Path.Combine(outputDirectory, "host-lifecycle-failure.v1.json"), JsonUtility.ToJson(receipt, true));
            }
            catch (Exception receiptException)
            {
                Debug.LogException(receiptException);
            }
        }

        private static string RunKnownAnswer()
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string outputRelativePath = ReadRequiredArgument(OutputArgument).Replace('\\', '/').TrimEnd('/');
            string executionId = ReadRequiredArgument(ExecutionIdArgument);
            Require(IsAllowedFreshOutputRelativePath(outputRelativePath), "Known-answer output path is outside the frozen corrigendum root or is not relative.");
            Require(!string.IsNullOrWhiteSpace(executionId), "Known-answer execution ID is empty.");

            string outputDirectory = Path.GetFullPath(Path.Combine(projectRoot, outputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            string allowedRoot = Path.GetFullPath(Path.Combine(projectRoot, AllowedOutputPrefix.Replace('/', Path.DirectorySeparatorChar)));
            Require(outputDirectory.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase), "Known-answer output path escaped the frozen corrigendum root.");
            Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Known-answer output already exists; overwrite or resume is prohibited.");
            Directory.CreateDirectory(outputDirectory);

            KnownAnswerReceipt receipt = NewReceipt(projectRoot, executionId, outputRelativePath);
            try
            {
                Require(receipt.inputSha256 == ExpectedInputSha256, "Exact known-answer input hash mismatch.");
                Require(receipt.algorithmSourceSha256 == ExpectedAlgorithmSha256, "Post-repair D* Lite source hash mismatch.");
                Require(receipt.specificationSha256 == ExpectedSpecificationSha256, "Post-repair D* Lite specification hash mismatch.");
                Require(receipt.oracleSourceSha256 == ExpectedOracleSha256, "Reference oracle source hash mismatch.");

                string inputPath = Path.Combine(projectRoot, InputRelativePath.Replace('/', Path.DirectorySeparatorChar));
                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(File.ReadAllText(inputPath));
                Require(input != null && input.inputId == "G14ME-QI-C002" && input.superblockId == "G14ME-QSB-C002", "Unexpected known-answer input identity.");
                Require(input.eventGroups != null && input.eventGroups.Length == 24 && input.starts != null && input.starts.Length == 8, "Known-answer input cardinality mismatch.");

                ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
                DStarLitePlanner planner = new DStarLitePlanner();
                const string lane = "ALG-D-CORRECTNESS-KNOWN-ANSWER-V4";
                planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = input.inputId + ":" + lane,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = 600000d
                });

                Gate14ReMEOraclePathV1[] initialOracle = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                {
                    NavigationPlanResult plan = planner.Plan(CreateRequest(input, lane, agentIndex, grid.Version, "initial"));
                    RequireCorrect(grid, initialOracle[agentIndex], plan, receipt, "initial", -1, agentIndex);
                    receipt.initialQueryChecks++;
                }

                for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    receipt.eventGroupCount++;
                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = partition.changes[changeIndex].ToChange();
                        NavigationChangeSet changeSet = grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, 600000d);
                        if (repair.Status != NavigationPlanStatus.Succeeded)
                        {
                            receipt.failedPhase = group.phase;
                            receipt.failedEventGroupIndex = groupIndex;
                            receipt.failedAgentIndex = -1;
                            receipt.failureKind = "REPAIR_STATUS_MISMATCH";
                            throw new InvalidOperationException("Post-repair known-answer repair status mismatch.");
                        }
                        receipt.repairOperationChecks++;
                    }

                    Gate14ReMEOraclePathV1[] oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                        grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                    for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                    {
                        NavigationPlanResult plan = planner.Plan(CreateRequest(input, lane, agentIndex, grid.Version, "g" + groupIndex));
                        RequireCorrect(grid, oracle[agentIndex], plan, receipt, group.phase, groupIndex, agentIndex);
                        receipt.postEventQueryChecks++;
                    }
                }

                receipt.status = "PASS_DSTAR_LITE_C002_ORACLE_CORRECTNESS_KNOWN_ANSWER";
                receipt.passed = true;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
            }
            catch (Exception exception)
            {
                receipt.status = "FAIL_DSTAR_LITE_C002_ORACLE_CORRECTNESS_KNOWN_ANSWER";
                receipt.passed = false;
                receipt.error = exception.GetType().FullName + ": " + exception.Message;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
                throw;
            }

            return outputDirectory;
        }

        private static KnownAnswerReceipt NewReceipt(string projectRoot, string executionId, string outputRelativePath)
        {
            return new KnownAnswerReceipt
            {
                schema = "gate14re-me-dstar-lite-c002-oracle-correctness-known-answer-receipt-v4",
                studyId = "Gate14Re-ME",
                executionId = executionId,
                status = "RUNNING",
                outputRelativePath = outputRelativePath,
                inputRelativePath = InputRelativePath,
                inputSha256 = Sha256File(Path.Combine(projectRoot, InputRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                algorithmSourceRelativePath = AlgorithmRelativePath,
                algorithmSourceSha256 = Sha256File(Path.Combine(projectRoot, AlgorithmRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                specificationRelativePath = SpecificationRelativePath,
                specificationSha256 = Sha256File(Path.Combine(projectRoot, SpecificationRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                oracleSourceRelativePath = OracleRelativePath,
                oracleSourceSha256 = Sha256File(Path.Combine(projectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar))),
                failedPhase = string.Empty,
                failedEventGroupIndex = -1,
                failedAgentIndex = -1,
                failureKind = string.Empty,
                error = string.Empty,
                completedAtUtc = string.Empty
            };
        }

        private static void RequireCorrect(
            IReadOnlyNavigationGrid grid,
            Gate14ReMEOraclePathV1 oracle,
            NavigationPlanResult plan,
            KnownAnswerReceipt receipt,
            string phase,
            int groupIndex,
            int agentIndex)
        {
            bool correct;
            string failureKind;
            if (oracle.Reachable)
            {
                double cost = ComputePathCost(grid, plan.Path);
                correct = plan.Status == NavigationPlanStatus.Succeeded && cost >= 0d && Gate14ReMEReferenceOracleV1.NearlyEqual(oracle.Cost, cost);
                failureKind = plan.Status == NavigationPlanStatus.Succeeded ? "REACHABLE_PATH_COST_MISMATCH" : "REACHABLE_STATUS_MISMATCH";
            }
            else
            {
                correct = plan.Status == NavigationPlanStatus.NoPath;
                failureKind = "UNREACHABLE_STATUS_MISMATCH";
            }
            if (correct) return;
            receipt.failedPhase = phase;
            receipt.failedEventGroupIndex = groupIndex;
            receipt.failedAgentIndex = agentIndex;
            receipt.failureKind = failureKind;
            throw new InvalidOperationException("Post-repair D* Lite oracle correctness mismatch.");
        }

        private static double ComputePathCost(IReadOnlyNavigationGrid grid, IReadOnlyList<GridCoordinate> path)
        {
            if (path == null || path.Count == 0) return -1d;
            double total = 0d;
            for (int index = 1; index < path.Count; index++)
            {
                GridCoordinate previous = path[index - 1];
                GridCoordinate current = path[index];
                bool diagonal = previous.x != current.x && previous.y != current.y;
                total += grid.GetTraversalCost(current) * (diagonal ? Math.Sqrt(2d) : 1d);
            }
            return total;
        }

        private static NavigationPlanRequest CreateRequest(Gate14ReMEQualificationInputBundleV1 input, string lane, int agentIndex, long version, string phase)
        {
            return new NavigationPlanRequest
            {
                runId = input.inputId + ":" + lane,
                requestId = input.inputId + ":" + lane + ":" + phase + ":agent:" + agentIndex,
                goalSetId = input.inputId + ":shared-goal",
                agentId = agentIndex,
                start = input.starts[agentIndex],
                goal = input.goal,
                expectedGridVersion = version,
                budgetMilliseconds = 600000d
            };
        }

        private static string ReadRequiredArgument(string name)
        {
            string[] arguments = Environment.GetCommandLineArgs();
            for (int index = 0; index < arguments.Length - 1; index++)
            {
                if (string.Equals(arguments[index], name, StringComparison.Ordinal)) return arguments[index + 1];
            }
            throw new InvalidOperationException("Missing required command-line argument: " + name);
        }

        private static int ReadOptionalNonNegativeIntegerArgument(string name, int defaultValue)
        {
            string[] arguments = Environment.GetCommandLineArgs();
            for (int index = 0; index < arguments.Length - 1; index++)
            {
                if (!string.Equals(arguments[index], name, StringComparison.Ordinal)) continue;
                int parsed;
                Require(int.TryParse(arguments[index + 1], out parsed) && parsed >= 0, "Command-line argument must be a non-negative integer: " + name);
                return parsed;
            }
            return defaultValue;
        }

        private static bool ContainsArgument(string[] arguments, string expected)
        {
            for (int index = 0; index < arguments.Length; index++)
            {
                if (string.Equals(arguments[index], expected, StringComparison.Ordinal)) return true;
            }
            return false;
        }

        private static bool IsAllowedFreshOutputRelativePath(string path)
        {
            return !string.IsNullOrWhiteSpace(path)
                && !Path.IsPathRooted(path)
                && path.StartsWith(AllowedOutputPrefix, StringComparison.Ordinal)
                && path.IndexOf("..", StringComparison.Ordinal) < 0;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void WriteReceipt(string outputDirectory, KnownAnswerReceipt receipt)
        {
            File.WriteAllText(Path.Combine(outputDirectory, "known-answer-receipt.v4.json"), JsonUtility.ToJson(receipt, true));
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
