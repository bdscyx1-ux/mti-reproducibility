using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate4ScenarioWorkloadVerification
    {
        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public string scenarioFingerprintSha256;
            public string canonicalFileSha256;
            public int canonicalUtf8Bytes;
            public int workloadPlanOperations;
            public int workloadRepairOperations;
            public int workloadDynamicPhases;
            public long workloadFinalGridVersion;
            public string error;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string verificationDirectory = Path.Combine(projectPath, "Research", "Verification");
            string canonicalPath = Path.Combine(verificationDirectory, "Gate4_Canonical.scenario.json");
            string invalidUtf8Path = Path.Combine(verificationDirectory, "Gate4_InvalidUtf8.tmp");
            string resultPath = Path.Combine(verificationDirectory, "Gate4_ScenarioWorkload.json");
            VerificationResult result = new VerificationResult();

            try
            {
                int assertions = 0;
                DeterministicScenarioDefinition definition = BuildScenario(false);
                DeterministicScenarioDefinition reordered = BuildScenario(true);
                ResolvedDeterministicScenario resolved = definition.Resolve();
                ResolvedDeterministicScenario reorderedResolved = reordered.Resolve();
                string canonical = DeterministicScenarioJson.SerializeCanonical(resolved);
                string reorderedCanonical = DeterministicScenarioJson.SerializeCanonical(reorderedResolved);

                Assert(resolved.FingerprintSha256 == reorderedResolved.FingerprintSha256, "Reordered scenario changed its fingerprint.", ref assertions);
                Assert(canonical == reorderedCanonical, "Canonical scenario JSON changed with source-array order.", ref assertions);
                Assert(canonical.Contains("场景-四号门"), "Canonical JSON did not retain UTF-8 scenario text.", ref assertions);
                Assert(!canonical.Contains("\r"), "Canonical JSON contains platform-specific carriage returns.", ref assertions);

                LoadedDeterministicScenario parsed = DeterministicScenarioJson.Parse(canonical);
                Assert(parsed.Resolved.FingerprintSha256 == resolved.FingerprintSha256, "Canonical parse changed the scenario fingerprint.", ref assertions);
                Assert(DeterministicScenarioJson.SerializeCanonical(parsed.Resolved) == canonical, "Canonical JSON is not byte-stable after parse/resolve.", ref assertions);
                Assert(parsed.SourcePath == string.Empty && parsed.SourceSha256.Length == 64, "In-memory parse provenance is incomplete.", ref assertions);

                string savedHash = DeterministicScenarioJson.SaveCanonical(canonicalPath, resolved, true);
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(canonicalPath);
                byte[] canonicalBytes = File.ReadAllBytes(canonicalPath);
                Assert(savedHash == loaded.SourceSha256, "Saved and loaded scenario SHA-256 values differ.", ref assertions);
                Assert(loaded.SourcePath == Path.GetFullPath(canonicalPath), "Loaded scenario did not retain its absolute source path.", ref assertions);
                Assert(loaded.Resolved.FingerprintSha256 == resolved.FingerprintSha256, "File round trip changed the scenario fingerprint.", ref assertions);
                Assert(canonicalBytes.Length > 3 && !(canonicalBytes[0] == 0xef && canonicalBytes[1] == 0xbb && canonicalBytes[2] == 0xbf), "Canonical scenario file unexpectedly contains a UTF-8 BOM.", ref assertions);

                AssertRejectsJson(InsertAfterRootOpen(canonical, "  \"unknownField\": 1,\n"), "Unknown root field was accepted.", ref assertions);
                AssertRejectsJson(InsertAfterRootOpen(canonical, "  \"schemaVersion\": 1,\n"), "Duplicate root field was accepted.", ref assertions);
                AssertRejectsJson(RemoveLineContaining(canonical, "\"goalSetId\""), "Missing required root field was accepted.", ref assertions);
                AssertRejectsJson(canonical.Replace("\"gridWidth\": 6", "\"gridWidth\": 6.0"), "Non-integer grid width token was accepted.", ref assertions);
                AssertRejectsJson(canonical.Replace("\"gridWidth\": 6", "\"gridWidth\": 2147483648"), "Out-of-range Int32 field was accepted.", ref assertions);
                AssertRejectsJson(canonical.Replace("\"maxSimulationTicks\": 1000002", "\"maxSimulationTicks\": 9223372036854775808"), "Out-of-range Int64 field was accepted.", ref assertions);
                AssertRejectsJson(canonical.Replace("      \"agentId\"", "      \"gridWidth\": 6,\n      \"agentId\""), "Misplaced known field was accepted.", ref assertions);
                AssertRejectsJson(AddTrailingRootComma(canonical), "Trailing root comma was accepted.", ref assertions);

                File.WriteAllBytes(invalidUtf8Path, new byte[] { 0x7b, 0xff, 0x7d });
                bool invalidUtf8Rejected = false;
                try { DeterministicScenarioJson.LoadFromFile(invalidUtf8Path); }
                catch (InvalidDataException) { invalidUtf8Rejected = true; }
                Assert(invalidUtf8Rejected, "Invalid UTF-8 scenario bytes were accepted.", ref assertions);

                CapturingLogSink logSink = new CapturingLogSink();
                PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run(
                    "gate4-workload",
                    loaded.Definition,
                    new AStarRepeatedPlanner(),
                    logSink);

                Assert(workload.completed, "Planning workload did not complete.", ref assertions);
                Assert(workload.algorithmId == NavigationAlgorithmIds.AStarRepeated, "Planning workload recorded the wrong algorithm id.", ref assertions);
                Assert(workload.scenarioFingerprintSha256 == resolved.FingerprintSha256, "Planning workload recorded the wrong scenario fingerprint.", ref assertions);
                Assert(workload.agentCount == 2 && workload.planOperationCount == 6, "Planning workload plan count is incorrect.", ref assertions);
                Assert(workload.scheduledEventCount == 3 && workload.repairOperationCount == 3, "Planning workload repair count is incorrect.", ref assertions);
                Assert(workload.dynamicPlanningPhaseCount == 2 && workload.dynamicPhases.Length == 2, "Events were not grouped into two deterministic tick phases.", ref assertions);
                Assert(workload.dynamicPhases[0].simulationTick == 2 && workload.dynamicPhases[0].eventIds.Length == 2, "Same-tick events were not applied together in order.", ref assertions);
                Assert(workload.dynamicPhases[0].eventIds[0] == "block-upper" && workload.dynamicPhases[0].eventIds[1] == "block-lower", "Same-tick event order changed.", ref assertions);
                Assert(workload.dynamicPhases[1].simulationTick == 1000000 && workload.dynamicPhases[1].eventIds.Length == 1, "Sparse future event tick was not reached directly.", ref assertions);
                Assert(workload.succeededPlanCount == 6 && workload.noPathPlanCount == 0 && workload.failedPlanCount == 0, "Planning workload contains an unexpected plan failure.", ref assertions);
                Assert(workload.finalGridVersion == 3 && workload.repairedCells == 0, "Planning workload version or A*-R repair semantics are incorrect.", ref assertions);
                Assert(workload.usesFixedScenarioStarts && Math.Abs(workload.planSuccessRate - 1d) < 1e-12d, "Planning workload fixed-start or success-rate semantics are incorrect.", ref assertions);
                Assert(workload.processedNodesOrCells > 0 && workload.expandedNodes > 0 && workload.totalPlannerElapsedMilliseconds >= 0d, "Planning workload metrics are empty.", ref assertions);
                Assert(logSink.Count("planning_workload_result") == 1, "Planning workload summary was not logged exactly once.", ref assertions);
                Assert(logSink.Count("planner_operation") == 10, "Planner operation log count is incorrect.", ref assertions);
                Assert(logSink.Count("runner_lifecycle") == 3, "Runner lifecycle log count is incorrect.", ref assertions);

                result.passed = true;
                result.assertionCount = assertions;
                result.scenarioFingerprintSha256 = resolved.FingerprintSha256;
                result.canonicalFileSha256 = savedHash;
                result.canonicalUtf8Bytes = canonicalBytes.Length;
                result.workloadPlanOperations = workload.planOperationCount;
                result.workloadRepairOperations = workload.repairOperationCount;
                result.workloadDynamicPhases = workload.dynamicPlanningPhaseCount;
                result.workloadFinalGridVersion = workload.finalGridVersion;
                result.error = string.Empty;
                WriteResult(resultPath, result);
                Debug.Log("Gate 4 scenario/workload verification passed with " + assertions + " assertions. Fingerprint: " + resolved.FingerprintSha256);
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.error = exception.ToString();
                WriteResult(resultPath, result);
                Debug.LogException(exception);
                throw;
            }
            finally
            {
                if (File.Exists(invalidUtf8Path)) File.Delete(invalidUtf8Path);
            }
        }

        private static DeterministicScenarioDefinition BuildScenario(bool reverseArrays)
        {
            ScenarioAgentDefinition upper = new ScenarioAgentDefinition
            {
                agentId = 4,
                start = new GridCoordinate(0, 0),
                goal = new GridCoordinate(5, 0)
            };
            ScenarioAgentDefinition lower = new ScenarioAgentDefinition
            {
                agentId = 1,
                start = new GridCoordinate(0, 3),
                goal = new GridCoordinate(5, 3)
            };
            NavigationGridChange weighted = Change(3, 1, true, 2.5f);
            NavigationGridChange blocked = Change(3, 2, false, 1f);
            ScheduledNavigationChangeDefinition blockUpper = new ScheduledNavigationChangeDefinition
            {
                eventId = "block-upper",
                simulationTick = 2,
                order = 0,
                repairBudgetMilliseconds = 0d,
                changes = new[] { Change(2, 0, false, 1f) }
            };
            ScheduledNavigationChangeDefinition blockLower = new ScheduledNavigationChangeDefinition
            {
                eventId = "block-lower",
                simulationTick = 2,
                order = 1,
                repairBudgetMilliseconds = 0d,
                changes = new[] { Change(2, 3, false, 1f) }
            };
            ScheduledNavigationChangeDefinition reopen = new ScheduledNavigationChangeDefinition
            {
                eventId = "reopen-both",
                simulationTick = 1000000,
                order = 0,
                repairBudgetMilliseconds = 8d,
                changes = reverseArrays
                    ? new[] { Change(2, 3, true, 1f), Change(2, 0, true, 1f) }
                    : new[] { Change(2, 0, true, 1f), Change(2, 3, true, 1f) }
            };

            return new DeterministicScenarioDefinition
            {
                scenarioId = "场景-四号门",
                randomSeed = 404,
                gridWidth = 6,
                gridHeight = 4,
                defaultTraversalCost = 1f,
                worldOrigin = new Vector3(-3f, 0.5f, 8f),
                cellSize = 1.25f,
                connectivity = NavigationGridConnectivity.FourWay,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = 0.02d,
                maxSimulationTicks = 1000002,
                goalSetId = "gate4-shared-goals",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 10d,
                agents = reverseArrays ? new[] { upper, lower } : new[] { lower, upper },
                initialGridOverrides = reverseArrays ? new[] { blocked, weighted } : new[] { weighted, blocked },
                scheduledChanges = reverseArrays
                    ? new[] { reopen, blockLower, blockUpper }
                    : new[] { blockUpper, blockLower, reopen }
            };
        }

        private static NavigationGridChange Change(int x, int y, bool walkable, float cost)
        {
            return new NavigationGridChange
            {
                coordinate = new GridCoordinate(x, y),
                isWalkable = walkable,
                traversalCost = cost
            };
        }

        private static void AssertRejectsJson(string json, string failureMessage, ref int assertions)
        {
            bool rejected = false;
            try { DeterministicScenarioJson.Parse(json); }
            catch (ScenarioJsonFormatException) { rejected = true; }
            Assert(rejected, failureMessage, ref assertions);
        }

        private static string InsertAfterRootOpen(string json, string insertion)
        {
            int open = json.IndexOf('{');
            if (open < 0) throw new InvalidOperationException("Canonical JSON has no root object.");
            return json.Insert(open + 1, "\n" + insertion);
        }

        private static string RemoveLineContaining(string json, string marker)
        {
            string[] lines = json.Split('\n');
            StringBuilder builder = new StringBuilder(json.Length);
            bool removed = false;
            for (int index = 0; index < lines.Length; index++)
            {
                if (!removed && lines[index].Contains(marker)) { removed = true; continue; }
                if (index < lines.Length - 1) builder.Append(lines[index]).Append('\n');
                else builder.Append(lines[index]);
            }
            if (!removed) throw new InvalidOperationException("Required field marker was not found in canonical JSON.");
            return builder.ToString();
        }

        private static string AddTrailingRootComma(string json)
        {
            int closing = json.LastIndexOf('}');
            if (closing < 0) throw new InvalidOperationException("Canonical JSON has no root closing brace.");
            return json.Insert(closing, ",");
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

        private sealed class CapturingLogSink : IExperimentLogSink
        {
            private readonly Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);

            public string FilePath { get { return string.Empty; } }
            public long EnqueuedCount { get; private set; }
            public long WrittenCount { get { return EnqueuedCount; } }

            public void Enqueue<T>(string recordType, string runId, T payload)
            {
                int count;
                counts.TryGetValue(recordType, out count);
                counts[recordType] = count + 1;
                EnqueuedCount++;
            }

            public int Count(string recordType)
            {
                int count;
                return counts.TryGetValue(recordType, out count) ? count : 0;
            }

            public void Flush(TimeSpan timeout) { }
            public void Dispose() { }
        }
    }
}
