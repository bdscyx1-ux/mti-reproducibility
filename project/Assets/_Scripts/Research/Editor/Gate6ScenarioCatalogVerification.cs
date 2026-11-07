using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate6ScenarioCatalogVerification
    {
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);
        private static readonly string[] ExpectedFiles =
        {
            "dynamic_corridors_sparse_v1.scenario.json",
            "eight_way_strict_corners_v1.scenario.json",
            "static_weighted_four_way_v1.scenario.json"
        };

        [Serializable]
        private sealed class ScenarioCatalogEntry
        {
            public string file;
            public string scenarioId;
            public string sourceSha256;
            public string fingerprintSha256;
            public int gridWidth;
            public int gridHeight;
            public int connectivity;
            public bool allowDiagonalCornerCutting;
            public int agentCount;
            public int scheduledEventCount;
            public int dynamicPlanningPhaseCount;
            public int planOperationCount;
            public int repairOperationCount;
            public int succeededPlanCount;
            public long processedNodesOrCells;
            public long expandedNodes;
            public long relaxedEdges;
        }

        [Serializable]
        private sealed class ScenarioCatalog
        {
            public int schemaVersion = 1;
            public string algorithmId = "A*-R";
            public int scenarioCount;
            public ScenarioCatalogEntry[] entries = new ScenarioCatalogEntry[0];
        }

        [Serializable]
        private sealed class VerificationResult
        {
            public bool passed;
            public int assertionCount;
            public int scenarioCount;
            public string catalogPath;
            public string error;
        }

        public static void Run()
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string scenarioDirectory = Path.Combine(projectPath, "Research", "Scenarios");
            string catalogPath = Path.Combine(scenarioDirectory, "catalog.json");
            string resultPath = Path.Combine(projectPath, "Research", "Verification", "Gate6_ScenarioCatalog.json");
            VerificationResult verification = new VerificationResult { catalogPath = catalogPath };

            try
            {
                int assertions = 0;
                string[] files = Directory.GetFiles(scenarioDirectory, "*.scenario.json", SearchOption.TopDirectoryOnly);
                Array.Sort(files, delegate(string left, string right)
                {
                    return StringComparer.Ordinal.Compare(Path.GetFileName(left), Path.GetFileName(right));
                });
                Assert(files.Length == ExpectedFiles.Length, "The committed scenario fixture count is incorrect.", ref assertions);

                HashSet<string> scenarioIds = new HashSet<string>(StringComparer.Ordinal);
                HashSet<string> fingerprints = new HashSet<string>(StringComparer.Ordinal);
                List<ScenarioCatalogEntry> entries = new List<ScenarioCatalogEntry>();
                bool sawStaticFourWay = false;
                bool sawSparseSameTickDynamic = false;
                bool sawStrictEightWay = false;

                for (int index = 0; index < files.Length; index++)
                {
                    string fileName = Path.GetFileName(files[index]);
                    Assert(string.Equals(fileName, ExpectedFiles[index], StringComparison.Ordinal), "Unexpected scenario fixture: " + fileName, ref assertions);

                    LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(files[index]);
                    ResolvedDeterministicScenario scenario = loaded.Resolved;
                    byte[] sourceBytes = File.ReadAllBytes(files[index]);
                    byte[] canonicalBytes = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(scenario));
                    Assert(BytesEqual(sourceBytes, canonicalBytes), "Scenario is not byte-for-byte canonical: " + fileName, ref assertions);
                    Assert(IsSha256(loaded.SourceSha256) && IsSha256(scenario.FingerprintSha256), "Scenario hashes are invalid: " + fileName, ref assertions);
                    Assert(scenarioIds.Add(scenario.ScenarioId), "Scenario id is duplicated: " + scenario.ScenarioId, ref assertions);
                    Assert(fingerprints.Add(scenario.FingerprintSha256), "Scenario fingerprint is duplicated: " + scenario.FingerprintSha256, ref assertions);

                    PlanningWorkloadResult workload = DeterministicPlanningWorkloadRunner.Run(
                        "catalog-" + scenario.ScenarioId,
                        loaded.Definition,
                        new AStarRepeatedPlanner(),
                        null);
                    Assert(workload.completed && workload.usesFixedScenarioStarts, "Fixture workload did not complete with fixed starts: " + fileName, ref assertions);
                    Assert(workload.succeededPlanCount == workload.planOperationCount && workload.noPathPlanCount == 0 && workload.budgetExceededPlanCount == 0 && workload.invalidPlanCount == 0 && workload.failedPlanCount == 0, "Fixture workload did not produce only successful plans: " + fileName, ref assertions);
                    Assert(workload.repairOperationCount == scenario.ScheduledChanges.Count && workload.finalGridVersion == scenario.ScheduledChanges.Count, "Fixture dynamic counts are inconsistent: " + fileName, ref assertions);

                    if (scenario.Connectivity == NavigationGridConnectivity.FourWay && scenario.ScheduledChanges.Count == 0)
                    {
                        sawStaticFourWay = true;
                    }
                    if (scenario.Connectivity == NavigationGridConnectivity.EightWay && !scenario.AllowDiagonalCornerCutting)
                    {
                        sawStrictEightWay = true;
                    }
                    if (scenario.ScheduledChanges.Count >= 2)
                    {
                        for (int eventIndex = 1; eventIndex < scenario.ScheduledChanges.Count; eventIndex++)
                        {
                            if (scenario.ScheduledChanges[eventIndex].SimulationTick == scenario.ScheduledChanges[eventIndex - 1].SimulationTick &&
                                scenario.MaxSimulationTicks >= 1000000L)
                            {
                                sawSparseSameTickDynamic = true;
                            }
                        }
                    }

                    entries.Add(new ScenarioCatalogEntry
                    {
                        file = fileName,
                        scenarioId = scenario.ScenarioId,
                        sourceSha256 = loaded.SourceSha256,
                        fingerprintSha256 = scenario.FingerprintSha256,
                        gridWidth = scenario.GridWidth,
                        gridHeight = scenario.GridHeight,
                        connectivity = (int)scenario.Connectivity,
                        allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                        agentCount = scenario.Agents.Count,
                        scheduledEventCount = scenario.ScheduledChanges.Count,
                        dynamicPlanningPhaseCount = workload.dynamicPlanningPhaseCount,
                        planOperationCount = workload.planOperationCount,
                        repairOperationCount = workload.repairOperationCount,
                        succeededPlanCount = workload.succeededPlanCount,
                        processedNodesOrCells = workload.processedNodesOrCells,
                        expandedNodes = workload.expandedNodes,
                        relaxedEdges = workload.relaxedEdges
                    });
                }

                Assert(sawStaticFourWay, "Catalog does not cover a static four-way fixture.", ref assertions);
                Assert(sawSparseSameTickDynamic, "Catalog does not cover sparse and same-tick dynamic events.", ref assertions);
                Assert(sawStrictEightWay, "Catalog does not cover strict eight-way corner handling.", ref assertions);

                ScenarioCatalog catalog = new ScenarioCatalog
                {
                    scenarioCount = entries.Count,
                    entries = entries.ToArray()
                };
                WriteJson(catalogPath, catalog);

                verification.passed = true;
                verification.assertionCount = assertions;
                verification.scenarioCount = entries.Count;
                verification.error = string.Empty;
                WriteJson(resultPath, verification);
                Debug.Log("Gate 6 scenario catalog verification passed with " + assertions + " assertions.");
            }
            catch (Exception exception)
            {
                verification.passed = false;
                verification.error = exception.ToString();
                WriteJson(resultPath, verification);
                Debug.LogException(exception);
                throw;
            }
        }

        private static bool BytesEqual(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            for (int index = 0; index < left.Length; index++)
            {
                if (left[index] != right[index]) return false;
            }
            return true;
        }

        private static bool IsSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return false;
            }
            return true;
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }

        private static void WriteJson<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            File.WriteAllBytes(path, StrictUtf8.GetBytes(json));
        }
    }
}
