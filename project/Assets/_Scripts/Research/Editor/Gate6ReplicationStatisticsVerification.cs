using System;
using System.IO;
using DDM.Research.Analysis;
using DDM.Research.Experiments;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate6ReplicationStatisticsVerification
    {
        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public double threeSampleMean;
            public double threeSampleStandardDeviation;
            public double threeSampleConfidence95Lower;
            public double threeSampleConfidence95Upper;
            public int aggregateRepetitions;
            public string error;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate6_ReplicationStatistics.json");
            VerificationResult result = new VerificationResult();
            try
            {
                int assertions = 0;
                ReplicationMetricSummary summary = ReplicationStatistics.Summarize(new[] { 3d, 1d, 2d });
                Assert(summary.count == 3 && Close(summary.minimum, 1d) && Close(summary.maximum, 3d), "Three-sample bounds are incorrect.", ref assertions);
                Assert(Close(summary.mean, 2d) && Close(summary.median, 2d) && Close(summary.p95NearestRank, 3d), "Three-sample location statistics are incorrect.", ref assertions);
                Assert(Close(summary.sampleStandardDeviation, 1d) && Close(summary.standardError, 1d / Math.Sqrt(3d)), "Three-sample dispersion is incorrect.", ref assertions);
                double expectedMargin = 4.30265272975d / Math.Sqrt(3d);
                Assert(Close(summary.confidence95Lower, 2d - expectedMargin) && Close(summary.confidence95Upper, 2d + expectedMargin), "Student-t 95% confidence interval is incorrect.", ref assertions);

                ReplicationMetricSummary reordered = ReplicationStatistics.Summarize(new[] { 2d, 3d, 1d });
                Assert(Close(summary.mean, reordered.mean) && Close(summary.sampleStandardDeviation, reordered.sampleStandardDeviation), "Statistics changed with input order.", ref assertions);
                ReplicationMetricSummary constant = ReplicationStatistics.Summarize(new[] { 5d, 5d, 5d, 5d });
                Assert(Close(constant.sampleStandardDeviation, 0d) && Close(constant.confidence95Lower, 5d) && Close(constant.confidence95Upper, 5d), "Constant-sample interval is incorrect.", ref assertions);
                ReplicationMetricSummary single = ReplicationStatistics.Summarize(new[] { 7d });
                Assert(single.count == 1 && Close(single.mean, 7d) && Close(single.confidence95Lower, 7d) && Close(single.confidence95Upper, 7d), "Single-sample summary is incorrect.", ref assertions);
                double[] thirtyTwoSamples = new double[32];
                for (int sampleIndex = 0; sampleIndex < thirtyTwoSamples.Length; sampleIndex++) thirtyTwoSamples[sampleIndex] = sampleIndex;
                ReplicationMetricSummary approximatedT = ReplicationStatistics.Summarize(thirtyTwoSamples);
                double inferredCritical = (approximatedT.confidence95Upper - approximatedT.mean) / approximatedT.standardError;
                Assert(Close(approximatedT.mean, 15.5d) && Close(approximatedT.median, 15.5d) && Close(approximatedT.p95NearestRank, 30d), "Thirty-two-sample location statistics are incorrect.", ref assertions);
                Assert(Math.Abs(inferredCritical - 2.039513446d) < 0.00001d, "Higher-degree-of-freedom t approximation is inaccurate.", ref assertions);
                AssertThrows(delegate { ReplicationStatistics.Summarize(new[] { 1d, double.NaN }); }, "Non-finite statistics input was accepted.", ref assertions);
                AssertThrows(delegate { ReplicationStatistics.Summarize(new double[0]); }, "Empty statistics input was accepted.", ref assertions);

                PlanningWorkloadResult runOne = BuildRun("rep-001", 1d, 2d, 3d, 10d, 100L, 196L);
                PlanningWorkloadResult runTwo = BuildRun("rep-002", 2d, 3d, 4d, 20d, 200L, 196L);
                PlanningWorkloadResult runThree = BuildRun("rep-003", 3d, 4d, 5d, 30d, 300L, 196L);
                PlanningReplicationAggregate aggregate = PlanningReplicationAggregator.Aggregate(
                    "group-001",
                    new string('b', 64),
                    new[] { runOne, runTwo, runThree });

                Assert(aggregate.completed && aggregate.repetitionCount == 3 && aggregate.childRunIds.Length == 3, "Aggregate completion or repetition count is incorrect.", ref assertions);
                Assert(aggregate.algorithmId == "A*-R" && aggregate.scenarioFingerprintSha256 == new string('a', 64), "Aggregate identity is incorrect.", ref assertions);
                Assert(aggregate.totalPlanOperationCount == 18 && aggregate.totalRepairOperationCount == 9 && aggregate.totalSucceededPlanCount == 18, "Aggregate operation totals are incorrect.", ref assertions);
                Assert(aggregate.totalNoPathPlanCount == 0 && aggregate.totalBudgetExceededPlanCount == 0 && aggregate.totalInvalidPlanCount == 0 && aggregate.totalFailedPlanCount == 0, "Aggregate failure totals are incorrect.", ref assertions);
                Assert(aggregate.deterministicWorkCountsConsistent && aggregate.consistentProcessedNodesOrCells == 196L && aggregate.consistentExpandedNodes == 46L, "Deterministic work-count consistency is incorrect.", ref assertions);
                Assert(Close(aggregate.initializationMilliseconds.mean, 2d) && Close(aggregate.totalPlannerElapsedMilliseconds.mean, 20d), "Aggregate timing means are incorrect.", ref assertions);
                Assert(Close(aggregate.managedAllocatedBytes.mean, 200d) && Close(aggregate.planSuccessRate.mean, 1d) && Close(aggregate.budgetOverrunRate.mean, 0d), "Aggregate allocation/rate means are incorrect.", ref assertions);

                PlanningWorkloadResult inconsistentWork = BuildRun("rep-004", 4d, 5d, 6d, 40d, 400L, 197L);
                PlanningReplicationAggregate inconsistentAggregate = PlanningReplicationAggregator.Aggregate(
                    "group-002",
                    new string('b', 64),
                    new[] { runOne, inconsistentWork });
                Assert(!inconsistentAggregate.deterministicWorkCountsConsistent && inconsistentAggregate.consistentProcessedNodesOrCells == -1L, "Inconsistent deterministic work was not flagged.", ref assertions);

                PlanningWorkloadResult wrongAlgorithm = BuildRun("rep-005", 2d, 3d, 4d, 20d, 200L, 196L);
                wrongAlgorithm.algorithmId = "OTHER";
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, wrongAlgorithm }); }, "Mixed algorithm ids were accepted.", ref assertions);
                PlanningWorkloadResult duplicateId = BuildRun("rep-001", 2d, 3d, 4d, 20d, 200L, 196L);
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, duplicateId }); }, "Duplicate run ids were accepted.", ref assertions);
                PlanningWorkloadResult badStatusSum = BuildRun("rep-006", 2d, 3d, 4d, 20d, 200L, 196L);
                badStatusSum.succeededPlanCount = 5;
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, badStatusSum }); }, "Invalid status total was accepted.", ref assertions);
                PlanningWorkloadResult badPlanRate = BuildRun("rep-007", 2d, 3d, 4d, 20d, 200L, 196L);
                badPlanRate.planSuccessRate = 0.5d;
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, badPlanRate }); }, "Plan success rate inconsistent with counts was accepted.", ref assertions);
                PlanningWorkloadResult badBudgetRate = BuildRun("rep-008", 2d, 3d, 4d, 20d, 200L, 196L);
                badBudgetRate.budgetOverrunRate = 0.25d;
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, badBudgetRate }); }, "Budget-overrun rate inconsistent with counts was accepted.", ref assertions);
                PlanningWorkloadResult badFixedStartShape = BuildRun("rep-009", 2d, 3d, 4d, 20d, 200L, 196L);
                badFixedStartShape.planOperationCount = 7;
                badFixedStartShape.succeededPlanCount = 7;
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne, badFixedStartShape }); }, "Invalid fixed-start workload shape was accepted.", ref assertions);
                AssertThrows(delegate { PlanningReplicationAggregator.Aggregate("group", new string('b', 64), new[] { runOne }); }, "Single-run replication group was accepted.", ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.threeSampleMean = summary.mean;
                result.threeSampleStandardDeviation = summary.sampleStandardDeviation;
                result.threeSampleConfidence95Lower = summary.confidence95Lower;
                result.threeSampleConfidence95Upper = summary.confidence95Upper;
                result.aggregateRepetitions = aggregate.repetitionCount;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 6 replication statistics verification passed with " + assertions + " assertions.");
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.error = exception.ToString();
                WriteResult(resultPath, result);
                Debug.LogException(exception);
                throw;
            }
        }

        private static PlanningWorkloadResult BuildRun(
            string runId,
            double initialization,
            double planP95,
            double dynamicP95,
            double totalElapsed,
            long allocation,
            long processed)
        {
            return new PlanningWorkloadResult
            {
                runId = runId,
                scenarioId = "replication-scenario",
                scenarioFingerprintSha256 = new string('a', 64),
                algorithmId = "A*-R",
                agentCount = 2,
                scheduledEventCount = 3,
                dynamicPlanningPhaseCount = 2,
                planOperationCount = 6,
                repairOperationCount = 3,
                succeededPlanCount = 6,
                noPathPlanCount = 0,
                budgetExceededPlanCount = 0,
                invalidPlanCount = 0,
                failedPlanCount = 0,
                budgetExceededOperationCount = 0,
                initializationMilliseconds = initialization,
                planP95Milliseconds = planP95,
                dynamicHandlingP95Milliseconds = dynamicP95,
                totalPlannerElapsedMilliseconds = totalElapsed,
                processedNodesOrCells = processed,
                expandedNodes = 46,
                relaxedEdges = 68,
                repairedCells = 0,
                managedAllocatedBytes = allocation,
                planSuccessRate = 1d,
                budgetOverrunRate = 0d,
                finalGridVersion = 3,
                usesFixedScenarioStarts = true,
                completed = true,
                dynamicPhases = new PlanningTickWorkloadRecord[2]
            };
        }

        private static bool Close(double left, double right)
        {
            return Math.Abs(left - right) <= 1e-9d * Math.Max(1d, Math.Max(Math.Abs(left), Math.Abs(right)));
        }

        private static void AssertThrows(Action action, string message, ref int assertions)
        {
            bool threw = false;
            try { action(); }
            catch (ArgumentException) { threw = true; }
            Assert(threw, message, ref assertions);
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void WriteResult(string path, VerificationResult result)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, JsonUtility.ToJson(result, true));
        }
    }
}
