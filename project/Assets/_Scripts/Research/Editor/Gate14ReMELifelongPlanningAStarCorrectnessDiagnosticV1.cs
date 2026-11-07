using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
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
    /// One-shot, non-measured reproduction for the Gate14Re-ME LPA* oracle
    /// correctness failure. It emits only structural pass/fail location data;
    /// it does not emit paths, path costs, timings, or qualification observations.
    /// </summary>
    public static class Gate14ReMELifelongPlanningAStarCorrectnessDiagnosticV1
    {
        private const string ExpectedInputSha256 = "3fbe00d7a27a75551b9ebb7711ccfcd2a0678679e94c3097b7a00209e7261ff3";
        private const string ExpectedAlgorithmSha256 = "948bdc4019e96776c8d382f381c159041038ac191f4b6000debd94f7daf8a82a";
        private const string ExpectedOracleSha256 = "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25";
        private const string AlgorithmRelativePath = "Assets/_Scripts/Research/Algorithms/LifelongPlanningAStarPlanner.cs";
        private const string OracleRelativePath = "Assets/_Scripts/Research/Gate14ReME/v1/Gate14ReMEReferenceOracleV1.cs";

        [Serializable]
        private sealed class DiagnosticReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public bool completed;
            public bool reproducedOracleCorrectnessMismatch;
            public string inputRelativePath;
            public string inputSha256;
            public string algorithmSourceRelativePath;
            public string algorithmSourceSha256;
            public string oracleSourceRelativePath;
            public string oracleSourceSha256;
            public string mismatchPhase;
            public int eventGroupIndex;
            public string eventGroupId;
            public int agentIndex;
            public string mismatchKind;
            public string observedPlanStatus;
            public string observedFailureReason;
            public bool startGIsPositiveInfinity;
            public bool startRhsIsPositiveInfinity;
            public bool startValuesConsistent;
            public int openQueueCount;
            public string extractionTraceOutcome;
            public int extractionFailureX;
            public int extractionFailureY;
            public int completedChecksBeforeMismatch;
            public string error;
            public string completedAtUtc;
        }

        public static void Run()
        {
            int exitCode = 1;
            DiagnosticReceipt receipt = NewReceipt();
            string outputDirectory = null;
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string inputPath = ResolveUnderProject(projectRoot, Required(arguments, "--g14me-lpa-input"));
                outputDirectory = ResolveUnderProject(projectRoot, Required(arguments, "--g14me-lpa-output"));
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Diagnostic output already exists; overwrite or resume is prohibited.");
                Directory.CreateDirectory(outputDirectory);

                receipt.inputRelativePath = RelativePath(projectRoot, inputPath);
                receipt.inputSha256 = Sha256File(inputPath);
                receipt.algorithmSourceSha256 = Sha256File(Path.Combine(projectRoot, AlgorithmRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                receipt.oracleSourceSha256 = Sha256File(Path.Combine(projectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                Require(receipt.inputSha256 == ExpectedInputSha256, "Exact diagnostic input hash mismatch.");
                Require(receipt.algorithmSourceSha256 == ExpectedAlgorithmSha256, "Exact LPA* source hash mismatch.");
                Require(receipt.oracleSourceSha256 == ExpectedOracleSha256, "Reference oracle source hash mismatch.");

                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(File.ReadAllText(inputPath));
                Require(input != null && input.inputId == "G14ME-QI-C002" && input.superblockId == "G14ME-QSB-C002", "Unexpected diagnostic input identity.");
                ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
                LifelongPlanningAStarPlanner planner = new LifelongPlanningAStarPlanner();
                const string diagnosticLane = "ALG-E-DIAGNOSTIC-V1";
                planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = input.inputId + ":" + diagnosticLane,
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
                    NavigationPlanResult plan = planner.Plan(CreatePlanRequest(input, diagnosticLane, agentIndex, grid.Version, "initial"));
                    string mismatch = ClassifyMismatch(grid, initialOracle[agentIndex], plan);
                    if (!string.IsNullOrEmpty(mismatch))
                    {
                        RecordMismatch(receipt, planner, grid, input, plan, "initial", -1, string.Empty, agentIndex, mismatch);
                        WriteReceipt(outputDirectory, receipt);
                        exitCode = 0;
                        return;
                    }
                    receipt.completedChecksBeforeMismatch++;
                }

                for (int groupIndex = 0; groupIndex < input.eventGroups.Length; groupIndex++)
                {
                    Gate14ReMEEventGroupV1 group = input.eventGroups[groupIndex];
                    for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                    {
                        Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                        NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                        for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = partition.changes[changeIndex].ToChange();
                        NavigationChangeSet changeSet = grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                        NavigationRepairResult repair = planner.ApplyChanges(changeSet, 600000d);
                        Require(repair.Status == NavigationPlanStatus.Succeeded, "Diagnostic repair operation did not succeed.");
                    }

                    Gate14ReMEOraclePathV1[] oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                        grid, input.goal, input.starts, input.connectivity, input.allowDiagonalCornerCutting);
                    for (int agentIndex = 0; agentIndex < input.starts.Length; agentIndex++)
                    {
                        NavigationPlanResult plan = planner.Plan(CreatePlanRequest(input, diagnosticLane, agentIndex, grid.Version, "g" + groupIndex));
                        string mismatch = ClassifyMismatch(grid, oracle[agentIndex], plan);
                        if (!string.IsNullOrEmpty(mismatch))
                        {
                            RecordMismatch(receipt, planner, grid, input, plan, group.phase, groupIndex, group.eventGroupId, agentIndex, mismatch);
                            WriteReceipt(outputDirectory, receipt);
                            exitCode = 0;
                            return;
                        }
                        receipt.completedChecksBeforeMismatch++;
                    }
                }

                receipt.status = "PASS_NO_ORACLE_CORRECTNESS_MISMATCH_REPRODUCED";
                receipt.completed = true;
                receipt.reproducedOracleCorrectnessMismatch = false;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.status = "FAILED_DIAGNOSTIC_HARNESS";
                receipt.completed = false;
                receipt.error = exception.GetType().FullName + ": " + exception.Message;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                if (!string.IsNullOrEmpty(outputDirectory) && Directory.Exists(outputDirectory)) WriteReceipt(outputDirectory, receipt);
                Debug.LogException(exception);
            }
            finally
            {
                try
                {
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(300000);
                }
                catch (Exception exception)
                {
                    exitCode = 1;
                    Debug.LogException(exception);
                }
                EditorApplication.Exit(exitCode);
            }
        }

        private static DiagnosticReceipt NewReceipt()
        {
            return new DiagnosticReceipt
            {
                schema = "gate14re-me-lpa-star-correctness-diagnostic-receipt-v1",
                studyId = "Gate14Re-ME",
                status = "RUNNING",
                algorithmSourceRelativePath = AlgorithmRelativePath,
                oracleSourceRelativePath = OracleRelativePath,
                mismatchPhase = string.Empty,
                eventGroupIndex = -1,
                eventGroupId = string.Empty,
                agentIndex = -1,
                mismatchKind = string.Empty,
                error = string.Empty,
                completedAtUtc = string.Empty
            };
        }

        private static void RecordMismatch(
            DiagnosticReceipt receipt,
            LifelongPlanningAStarPlanner planner,
            IReadOnlyNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            NavigationPlanResult plan,
            string phase,
            int groupIndex,
            string groupId,
            int agentIndex,
            string mismatch)
        {
            receipt.status = "REPRODUCED_ORACLE_CORRECTNESS_MISMATCH";
            receipt.completed = true;
            receipt.reproducedOracleCorrectnessMismatch = true;
            receipt.mismatchPhase = phase;
            receipt.eventGroupIndex = groupIndex;
            receipt.eventGroupId = groupId;
            receipt.agentIndex = agentIndex;
            receipt.mismatchKind = mismatch;
            receipt.observedPlanStatus = plan.Status.ToString();
            receipt.observedFailureReason = plan.FailureReason.ToString();
            CapturePlannerState(receipt, planner, grid, input, agentIndex);
            receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
        }

        private static void CapturePlannerState(
            DiagnosticReceipt receipt,
            LifelongPlanningAStarPlanner planner,
            IReadOnlyNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            int agentIndex)
        {
            BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
            object statesObject = typeof(LifelongPlanningAStarPlanner).GetField("agentStates", flags).GetValue(planner);
            IDictionary states = (IDictionary)statesObject;
            object state = states[agentIndex];
            Type stateType = state.GetType();
            double[] g = (double[])stateType.GetField("G", flags).GetValue(state);
            double[] rhs = (double[])stateType.GetField("Rhs", flags).GetValue(state);
            GridCoordinate start = (GridCoordinate)stateType.GetField("CurrentStart", flags).GetValue(state);
            object queue = stateType.GetField("Queue", flags).GetValue(state);
            int startIndex = (start.y * input.gridEdge) + start.x;
            double startG = g[startIndex];
            double startRhs = rhs[startIndex];
            receipt.startGIsPositiveInfinity = double.IsPositiveInfinity(startG);
            receipt.startRhsIsPositiveInfinity = double.IsPositiveInfinity(startRhs);
            receipt.startValuesConsistent =
                (receipt.startGIsPositiveInfinity && receipt.startRhsIsPositiveInfinity) ||
                Math.Abs(startG - startRhs) <= 1e-12d;
            receipt.openQueueCount = (int)queue.GetType().GetProperty("Count", flags).GetValue(queue, null);
            TraceGreedyExtraction(receipt, grid, input, g, start);
        }

        private static void TraceGreedyExtraction(
            DiagnosticReceipt receipt,
            IReadOnlyNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            double[] g,
            GridCoordinate start)
        {
            GridCoordinate[] offsets = input.connectivity == NavigationGridConnectivity.FourWay
                ? new[] { new GridCoordinate(0, -1), new GridCoordinate(-1, 0), new GridCoordinate(1, 0), new GridCoordinate(0, 1) }
                : new[]
                {
                    new GridCoordinate(-1, -1), new GridCoordinate(0, -1), new GridCoordinate(1, -1),
                    new GridCoordinate(-1, 0), new GridCoordinate(1, 0),
                    new GridCoordinate(-1, 1), new GridCoordinate(0, 1), new GridCoordinate(1, 1)
                };
            HashSet<GridCoordinate> visited = new HashSet<GridCoordinate>();
            GridCoordinate current = start;
            int cellCount = checked(grid.Width * grid.Height);
            for (int step = 0; step <= cellCount; step++)
            {
                if (current.Equals(input.goal))
                {
                    receipt.extractionTraceOutcome = "REACHED_GOAL";
                    return;
                }
                if (!visited.Add(current))
                {
                    receipt.extractionTraceOutcome = "CYCLE";
                    receipt.extractionFailureX = current.x;
                    receipt.extractionFailureY = current.y;
                    return;
                }

                bool found = false;
                GridCoordinate best = default(GridCoordinate);
                double bestTotal = double.PositiveInfinity;
                double bestG = double.PositiveInfinity;
                for (int offsetIndex = 0; offsetIndex < offsets.Length; offsetIndex++)
                {
                    GridCoordinate successor = new GridCoordinate(current.x + offsets[offsetIndex].x, current.y + offsets[offsetIndex].y);
                    if (!CanTraverse(grid, input, current, successor)) continue;
                    double successorG = g[(successor.y * grid.Width) + successor.x];
                    if (double.IsPositiveInfinity(successorG)) continue;
                    bool diagonal = current.x != successor.x && current.y != successor.y;
                    double total = grid.GetTraversalCost(successor) * (diagonal ? Math.Sqrt(2d) : 1d) + successorG;
                    if (!found || IsBetterSuccessor(total, successorG, successor, bestTotal, bestG, best))
                    {
                        found = true;
                        best = successor;
                        bestTotal = total;
                        bestG = successorG;
                    }
                }
                if (!found)
                {
                    receipt.extractionTraceOutcome = "NO_FINITE_SUCCESSOR";
                    receipt.extractionFailureX = current.x;
                    receipt.extractionFailureY = current.y;
                    return;
                }
                current = best;
            }
            receipt.extractionTraceOutcome = "STEP_LIMIT";
            receipt.extractionFailureX = current.x;
            receipt.extractionFailureY = current.y;
        }

        private static bool CanTraverse(
            IReadOnlyNavigationGrid grid,
            Gate14ReMEQualificationInputBundleV1 input,
            GridCoordinate from,
            GridCoordinate to)
        {
            if (!grid.Contains(from) || !grid.Contains(to) || !grid.IsWalkable(from) || !grid.IsWalkable(to)) return false;
            int deltaX = to.x - from.x;
            int deltaY = to.y - from.y;
            int absoluteX = Math.Abs(deltaX);
            int absoluteY = Math.Abs(deltaY);
            if (absoluteX > 1 || absoluteY > 1 || absoluteX + absoluteY == 0) return false;
            if (input.connectivity == NavigationGridConnectivity.FourWay) return absoluteX + absoluteY == 1;
            if (absoluteX == 1 && absoluteY == 1 && !input.allowDiagonalCornerCutting)
            {
                return grid.IsWalkable(new GridCoordinate(from.x + deltaX, from.y)) &&
                       grid.IsWalkable(new GridCoordinate(from.x, from.y + deltaY));
            }
            return true;
        }

        private static bool IsBetterSuccessor(
            double total,
            double successorG,
            GridCoordinate successor,
            double bestTotal,
            double bestG,
            GridCoordinate best)
        {
            if (total < bestTotal - 1e-12d) return true;
            if (Math.Abs(total - bestTotal) > 1e-12d) return false;
            if (successorG < bestG - 1e-12d) return true;
            if (Math.Abs(successorG - bestG) > 1e-12d) return false;
            int yComparison = successor.y.CompareTo(best.y);
            return yComparison < 0 || (yComparison == 0 && successor.x < best.x);
        }

        private static string ClassifyMismatch(IReadOnlyNavigationGrid grid, Gate14ReMEOraclePathV1 oracle, NavigationPlanResult plan)
        {
            if (oracle.Reachable)
            {
                if (plan.Status != NavigationPlanStatus.Succeeded) return "REACHABLE_STATUS_MISMATCH";
                double reportedCost = ComputePathCost(grid, plan.Path);
                return reportedCost >= 0d && Gate14ReMEReferenceOracleV1.NearlyEqual(oracle.Cost, reportedCost)
                    ? string.Empty
                    : "REACHABLE_PATH_COST_MISMATCH";
            }
            return plan.Status == NavigationPlanStatus.NoPath
                ? string.Empty
                : "UNREACHABLE_STATUS_MISMATCH_" + plan.Status.ToString().ToUpperInvariant();
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

        private static NavigationPlanRequest CreatePlanRequest(Gate14ReMEQualificationInputBundleV1 input, string lane, int agentIndex, long gridVersion, string phase)
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
                budgetMilliseconds = 600000d
            };
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (args[index].StartsWith("--g14me-lpa-", StringComparison.Ordinal)) result[args[index]] = args[index + 1];
            }
            return result;
        }

        private static string Required(Dictionary<string, string> arguments, string name)
        {
            string value;
            if (!arguments.TryGetValue(name, out value) || string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Missing required argument: " + name);
            return value;
        }

        private static string ResolveUnderProject(string projectRoot, string value)
        {
            string fullPath = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            string rootWithSeparator = Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            Require(fullPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase), "Path is outside the project root.");
            return fullPath;
        }

        private static string RelativePath(string root, string path)
        {
            Uri rootUri = new Uri(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri pathUri = new Uri(Path.GetFullPath(path));
            return Uri.UnescapeDataString(rootUri.MakeRelativeUri(pathUri).ToString()).Replace('\\', '/');
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void WriteReceipt(string outputDirectory, DiagnosticReceipt receipt)
        {
            File.WriteAllText(Path.Combine(outputDirectory, "diagnostic-receipt.v1.json"), JsonUtility.ToJson(receipt, true));
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
