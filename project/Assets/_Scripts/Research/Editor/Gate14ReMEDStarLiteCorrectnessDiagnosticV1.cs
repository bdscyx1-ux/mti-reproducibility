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
    /// One-shot, non-measured reproduction for the Gate14Re-ME D* Lite oracle
    /// correctness failure. It emits only structural pass/fail location data;
    /// it does not emit path costs, timings, or qualification observations.
    /// </summary>
    public static class Gate14ReMEDStarLiteCorrectnessDiagnosticV1
    {
        private const string ExpectedInputSha256 = "3fbe00d7a27a75551b9ebb7711ccfcd2a0678679e94c3097b7a00209e7261ff3";
        private const string ExpectedAlgorithmSha256 = "ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f";
        private const string ExpectedOracleSha256 = "3dee772014b2416fa252163838deb4394c0e3ea2edc4334ac0fe27e17580cb25";
        private const string AlgorithmRelativePath = "Assets/_Scripts/Research/Algorithms/DStarLitePlanner.cs";
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
                string inputPath = ResolveUnderProject(projectRoot, Required(arguments, "--g14me-dstar-input"));
                outputDirectory = ResolveUnderProject(projectRoot, Required(arguments, "--g14me-dstar-output"));
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Diagnostic output already exists; overwrite or resume is prohibited.");
                Directory.CreateDirectory(outputDirectory);

                receipt.inputRelativePath = RelativePath(projectRoot, inputPath);
                receipt.inputSha256 = Sha256File(inputPath);
                receipt.algorithmSourceSha256 = Sha256File(Path.Combine(projectRoot, AlgorithmRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                receipt.oracleSourceSha256 = Sha256File(Path.Combine(projectRoot, OracleRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                Require(receipt.inputSha256 == ExpectedInputSha256, "Exact diagnostic input hash mismatch.");
                Require(receipt.algorithmSourceSha256 == ExpectedAlgorithmSha256, "Pre-repair D* Lite source hash mismatch.");
                Require(receipt.oracleSourceSha256 == ExpectedOracleSha256, "Reference oracle source hash mismatch.");

                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(File.ReadAllText(inputPath));
                Require(input != null && input.inputId == "G14ME-QI-C002" && input.superblockId == "G14ME-QSB-C002", "Unexpected diagnostic input identity.");
                ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
                DStarLitePlanner planner = new DStarLitePlanner();
                const string diagnosticLane = "ALG-D-DIAGNOSTIC-V1";
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
                        RecordMismatch(receipt, "initial", -1, string.Empty, agentIndex, mismatch);
                        CompleteAndWrite(outputDirectory, receipt);
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
                            RecordMismatch(receipt, group.phase, groupIndex, group.eventGroupId, agentIndex, mismatch);
                            CompleteAndWrite(outputDirectory, receipt);
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
                EditorApplication.Exit(exitCode);
            }
        }

        private static DiagnosticReceipt NewReceipt()
        {
            return new DiagnosticReceipt
            {
                schema = "gate14re-me-dstar-lite-correctness-diagnostic-receipt-v1",
                studyId = "Gate14Re-ME",
                status = "RUNNING",
                completed = false,
                reproducedOracleCorrectnessMismatch = false,
                algorithmSourceRelativePath = AlgorithmRelativePath,
                oracleSourceRelativePath = OracleRelativePath,
                mismatchPhase = string.Empty,
                eventGroupIndex = -1,
                eventGroupId = string.Empty,
                agentIndex = -1,
                mismatchKind = string.Empty,
                completedChecksBeforeMismatch = 0,
                error = string.Empty,
                completedAtUtc = string.Empty
            };
        }

        private static void RecordMismatch(DiagnosticReceipt receipt, string phase, int groupIndex, string groupId, int agentIndex, string mismatch)
        {
            receipt.status = "REPRODUCED_ORACLE_CORRECTNESS_MISMATCH";
            receipt.completed = true;
            receipt.reproducedOracleCorrectnessMismatch = true;
            receipt.mismatchPhase = phase;
            receipt.eventGroupIndex = groupIndex;
            receipt.eventGroupId = groupId;
            receipt.agentIndex = agentIndex;
            receipt.mismatchKind = mismatch;
            receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
        }

        private static void CompleteAndWrite(string outputDirectory, DiagnosticReceipt receipt)
        {
            WriteReceipt(outputDirectory, receipt);
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
            return plan.Status == NavigationPlanStatus.NoPath ? string.Empty : "UNREACHABLE_STATUS_MISMATCH";
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

        private static NavigationPlanRequest CreatePlanRequest(
            Gate14ReMEQualificationInputBundleV1 input,
            string lane,
            int agentIndex,
            long gridVersion,
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
                budgetMilliseconds = 600000d
            };
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (args[index].StartsWith("--g14me-dstar-", StringComparison.Ordinal)) result[args[index]] = args[index + 1];
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
                byte[] hash = sha.ComputeHash(stream);
                return BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
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
