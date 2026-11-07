using System;
using System.Collections;
using System.IO;
using System.Reflection;
using DDM.Research.Algorithms;
using DDM.Research.Gate14ReME.V1;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Categorical key-state diagnostic for the first failing C002 block event.
    /// No key values, path costs, timings, or qualification observations are emitted.
    /// </summary>
    public static class Gate14ReMEDStarLiteKeyDiagnosticV2
    {
        private const double Tolerance = 1e-12d;
        private const string InputRelativePath = "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/inputs/core/G14ME-QSB-C002.input.v2.json";
        private const string OutputRelativePath = "Research/Verification/Gate14Re-ME/qualification-dstar-lite-oracle-correctness-corrigendum-attempt-001/repair-cycle-002-key-diagnostic";

        [Serializable]
        private sealed class KeyDiagnosticReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public bool completed;
            public string inputId;
            public string eventGroupId;
            public int agentIndex;
            public bool startConsistentBeforePlan;
            public int validQueueEntryCount;
            public string topFirstExactRelationToStartFirst;
            public bool topFirstWithinToleranceOfStartFirst;
            public string topSecondExactRelationToStartSecond;
            public string exactLexicographicRelationToStartKey;
            public string postPlanStatus;
            public string postPlanFailureReason;
            public bool oracleReachable;
            public string mismatchKind;
            public string error;
            public string completedAtUtc;
        }

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = null;
            KeyDiagnosticReceipt receipt = NewReceipt();
            try
            {
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string inputPath = Path.Combine(projectRoot, InputRelativePath.Replace('/', Path.DirectorySeparatorChar));
                outputDirectory = Path.Combine(projectRoot, OutputRelativePath.Replace('/', Path.DirectorySeparatorChar));
                Require(File.Exists(inputPath), "Diagnostic input is missing.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Diagnostic output already exists; overwrite or resume is prohibited.");
                Directory.CreateDirectory(outputDirectory);

                Gate14ReMEQualificationInputBundleV1 input = JsonUtility.FromJson<Gate14ReMEQualificationInputBundleV1>(File.ReadAllText(inputPath));
                Require(input != null && input.inputId == "G14ME-QI-C002", "Unexpected diagnostic input.");
                receipt.inputId = input.inputId;
                ResearchNavigationGrid grid = Gate14ReMEInputGeometryValidatorV1.BuildGrid(input);
                DStarLitePlanner planner = new DStarLitePlanner();
                const string lane = "ALG-D-KEY-DIAGNOSTIC-V2";
                planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = input.inputId + ":" + lane,
                    goalSetId = input.inputId + ":shared-goal",
                    goals = new[] { input.goal },
                    connectivity = input.connectivity,
                    allowDiagonalCornerCutting = input.allowDiagonalCornerCutting,
                    budgetMilliseconds = 600000d
                });

                NavigationPlanResult initial = planner.Plan(CreateRequest(input, lane, grid.Version, "initial"));
                Require(initial.Status == NavigationPlanStatus.Succeeded, "Initial diagnostic plan did not succeed.");

                Gate14ReMEEventGroupV1 group = input.eventGroups[0];
                receipt.eventGroupId = group.eventGroupId;
                for (int partitionIndex = 0; partitionIndex < group.atomicPartitions.Length; partitionIndex++)
                {
                    Gate14ReMEAtomicPartitionV1 partition = group.atomicPartitions[partitionIndex];
                    NavigationGridChange[] changes = new NavigationGridChange[partition.changes.Length];
                    for (int changeIndex = 0; changeIndex < changes.Length; changeIndex++) changes[changeIndex] = partition.changes[changeIndex].ToChange();
                    NavigationChangeSet changeSet = grid.ApplyChanges(group.eventGroupId + ":p" + partitionIndex, grid.Version, changes);
                    NavigationRepairResult repair = planner.ApplyChanges(changeSet, 600000d);
                    Require(repair.Status == NavigationPlanStatus.Succeeded, "Diagnostic repair did not succeed.");
                }

                CaptureKeyRelations(planner, grid, input.starts[0], receipt);
                Gate14ReMEOraclePathV1 oracle = Gate14ReMEReferenceOracleV1.Evaluate(
                    grid, input.goal, new[] { input.starts[0] }, input.connectivity, input.allowDiagonalCornerCutting)[0];
                NavigationPlanResult afterBlock = planner.Plan(CreateRequest(input, lane, grid.Version, "after-block"));
                receipt.postPlanStatus = afterBlock.Status.ToString();
                receipt.postPlanFailureReason = afterBlock.FailureReason.ToString();
                receipt.oracleReachable = oracle.Reachable;
                receipt.mismatchKind = oracle.Reachable
                    ? (afterBlock.Status == NavigationPlanStatus.Succeeded ? string.Empty : "REACHABLE_STATUS_MISMATCH")
                    : (afterBlock.Status == NavigationPlanStatus.NoPath ? string.Empty : "UNREACHABLE_STATUS_MISMATCH");
                receipt.status = "PASS_CATEGORICAL_KEY_DIAGNOSTIC";
                receipt.completed = true;
                receipt.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                WriteReceipt(outputDirectory, receipt);
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.status = "FAILED_CATEGORICAL_KEY_DIAGNOSTIC";
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

        private static void CaptureKeyRelations(DStarLitePlanner planner, IReadOnlyNavigationGrid grid, GridCoordinate start, KeyDiagnosticReceipt receipt)
        {
            Type plannerType = typeof(DStarLitePlanner);
            FieldInfo agentStatesField = plannerType.GetField("agentStates", BindingFlags.Instance | BindingFlags.NonPublic);
            Require(agentStatesField != null, "Planner state field is unavailable.");
            IDictionary agentStates = (IDictionary)agentStatesField.GetValue(planner);
            object state = agentStates[0];
            Require(state != null, "Agent zero state is unavailable.");

            Type stateType = state.GetType();
            double[] g = (double[])stateType.GetField("G", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(state);
            double[] rhs = (double[])stateType.GetField("Rhs", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(state);
            long[] revisions = (long[])stateType.GetField("QueueRevisions", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(state);
            double km = (double)stateType.GetField("Km", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(state);
            object queue = stateType.GetField("Queue", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(state);
            Type queueType = queue.GetType();
            int queueCount = (int)queueType.GetProperty("Count", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(queue, null);
            Array items = (Array)queueType.GetField("items", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(queue);

            int startIndex = (start.y * grid.Width) + start.x;
            double startSecond = Math.Min(g[startIndex], rhs[startIndex]);
            double startFirst = startSecond + km;
            receipt.startConsistentBeforePlan = ValuesEqual(g[startIndex], rhs[startIndex]);

            bool found = false;
            double topFirst = 0d;
            double topSecond = 0d;
            int topX = 0;
            int topY = 0;
            long topSequence = 0L;
            for (int itemIndex = 0; itemIndex < queueCount; itemIndex++)
            {
                object node = items.GetValue(itemIndex);
                Type nodeType = node.GetType();
                int index = (int)nodeType.GetField("Index", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(node);
                long revision = (long)nodeType.GetField("Revision", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(node);
                if (revision != revisions[index] || ValuesEqual(g[index], rhs[index])) continue;
                int x = index % grid.Width;
                int y = index / grid.Width;
                double second = Math.Min(g[index], rhs[index]);
                double first = second + Octile(start.x, start.y, x, y) + km;
                long sequence = (long)nodeType.GetField("Sequence", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetValue(node);
                receipt.validQueueEntryCount++;
                if (!found || Compare(first, second, y, x, sequence, topFirst, topSecond, topY, topX, topSequence) < 0)
                {
                    found = true;
                    topFirst = first;
                    topSecond = second;
                    topX = x;
                    topY = y;
                    topSequence = sequence;
                }
            }
            Require(found, "No valid diagnostic queue entry remained after the block repair.");

            startFirst += Octile(start.x, start.y, start.x, start.y);
            receipt.topFirstExactRelationToStartFirst = Relation(topFirst, startFirst);
            receipt.topFirstWithinToleranceOfStartFirst = Math.Abs(topFirst - startFirst) <= Tolerance;
            receipt.topSecondExactRelationToStartSecond = Relation(topSecond, startSecond);
            int firstRelation = topFirst.CompareTo(startFirst);
            receipt.exactLexicographicRelationToStartKey = firstRelation != 0 ? Relation(topFirst, startFirst) : Relation(topSecond, startSecond);
        }

        private static int Compare(double first, double second, int y, int x, long sequence, double otherFirst, double otherSecond, int otherY, int otherX, long otherSequence)
        {
            int result = first.CompareTo(otherFirst);
            if (result != 0) return result;
            result = second.CompareTo(otherSecond);
            if (result != 0) return result;
            result = y.CompareTo(otherY);
            if (result != 0) return result;
            result = x.CompareTo(otherX);
            return result != 0 ? result : sequence.CompareTo(otherSequence);
        }

        private static string Relation(double left, double right)
        {
            int comparison = left.CompareTo(right);
            return comparison < 0 ? "LESS" : (comparison > 0 ? "GREATER" : "EQUAL");
        }

        private static double Octile(int x1, int y1, int x2, int y2)
        {
            int dx = Math.Abs(x2 - x1);
            int dy = Math.Abs(y2 - y1);
            int minimum = Math.Min(dx, dy);
            int maximum = Math.Max(dx, dy);
            return maximum + ((Math.Sqrt(2d) - 1d) * minimum);
        }

        private static bool ValuesEqual(double left, double right)
        {
            if (double.IsPositiveInfinity(left) && double.IsPositiveInfinity(right)) return true;
            return Math.Abs(left - right) <= Tolerance;
        }

        private static NavigationPlanRequest CreateRequest(Gate14ReMEQualificationInputBundleV1 input, string lane, long version, string phase)
        {
            return new NavigationPlanRequest
            {
                runId = input.inputId + ":" + lane,
                requestId = input.inputId + ":" + lane + ":" + phase + ":agent:0",
                goalSetId = input.inputId + ":shared-goal",
                agentId = 0,
                start = input.starts[0],
                goal = input.goal,
                expectedGridVersion = version,
                budgetMilliseconds = 600000d
            };
        }

        private static KeyDiagnosticReceipt NewReceipt()
        {
            return new KeyDiagnosticReceipt
            {
                schema = "gate14re-me-dstar-lite-categorical-key-diagnostic-receipt-v2",
                studyId = "Gate14Re-ME",
                status = "RUNNING",
                inputId = string.Empty,
                eventGroupId = string.Empty,
                agentIndex = 0,
                topFirstExactRelationToStartFirst = string.Empty,
                topSecondExactRelationToStartSecond = string.Empty,
                exactLexicographicRelationToStartKey = string.Empty,
                postPlanStatus = string.Empty,
                postPlanFailureReason = string.Empty,
                mismatchKind = string.Empty,
                error = string.Empty,
                completedAtUtc = string.Empty
            };
        }

        private static void WriteReceipt(string outputDirectory, KeyDiagnosticReceipt receipt)
        {
            File.WriteAllText(Path.Combine(outputDirectory, "key-diagnostic-receipt.v2.json"), JsonUtility.ToJson(receipt, true));
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
