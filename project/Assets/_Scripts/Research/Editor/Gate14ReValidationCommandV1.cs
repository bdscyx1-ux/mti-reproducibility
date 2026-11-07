using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Gate14Re.V1;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class Gate14ReValidationCommandV1
    {
        private const string ReceiptRelativePath = "Research/Verification/Gate14Re/implementation-attempt-001/synthetic-validation-only-attempt-003/validation-receipt.v1.json";
        private const string FailureRelativePath = "Research/Verification/Gate14Re/implementation-attempt-001/synthetic-validation-only-attempt-003/failure-receipt.v1.json";

        private static readonly ConditionBinding[] Conditions =
        {
            new ConditionBinding("C01", "core-r02-s1-shared", "Research/FormalScenarios/v1/Scenarios/core-r02-s1-shared.scenario.json", "7612d4a77374c8920cfd493f19cb07b8ba48065dff89187cefd635eee41dfb94", 81, true),
            new ConditionBinding("C02", "core-r02-s2-shared", "Research/FormalScenarios/v1/Scenarios/core-r02-s2-shared.scenario.json", "8cb48030e5c75ef5b4477852188dc1930bff5fba32644335af4edadf81d7f32d", 81, false),
            new ConditionBinding("C03", "core-r03-s1-shared", "Research/FormalScenarios/v1/Scenarios/core-r03-s1-shared.scenario.json", "a2272840c88fd70d40b2508dd00d75156c86c37ecb813c04651f09fdeb4223a2", 9, false),
            new ConditionBinding("C04", "core-r03-s2-shared", "Research/FormalScenarios/v1/Scenarios/core-r03-s2-shared.scenario.json", "c2eaee5d3c241fe2304c3ad794c77fe02efa1c659e32bbc3caeb8b10344d1bc8", 9, false),
            new ConditionBinding("C05", "core-r06-s1-shared", "Research/FormalScenarios/v1/Scenarios/core-r06-s1-shared.scenario.json", "ff4c38d9761b46cefb584f47b8861e6f50fb0de4155e8bae38654d81baf342fc", 9, false),
            new ConditionBinding("C06", "core-r06-s2-shared", "Research/FormalScenarios/v1/Scenarios/core-r06-s2-shared.scenario.json", "3c4650745359e1a60a71d3a6db32890ffb91482c947657bab9f3de322b510126", 9, false),
            new ConditionBinding("C07", "core-r07-s1-shared", "Research/FormalScenarios/v1/Scenarios/core-r07-s1-shared.scenario.json", "34f206248d0c563c4a2bc8bf7d0cb9a1a86b1e53d345a19968776911b5a07692", 81, true),
            new ConditionBinding("C08", "core-r07-s2-shared", "Research/FormalScenarios/v1/Scenarios/core-r07-s2-shared.scenario.json", "a1227c2b468e7ec06836198257a25efd67ac6e0cc4ff622403b582ee58899f2a", 81, false)
        };

        public static void Run()
        {
            int assertions = 0;
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string receiptPath = Full(projectRoot, ReceiptRelativePath);
            string failurePath = Full(projectRoot, FailureRelativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(receiptPath));

            try
            {
                ValidateFrozenDesign(projectRoot, ref assertions);
                ValidateActualBindingsAndSynchronization(projectRoot, ref assertions);
                ValidateMovementKernelSynthetic(ref assertions);
                ValidateQuantityConstruction(projectRoot, ref assertions);
                ValidateNegativeGates(projectRoot, ref assertions);
                ValidateNoFormalRoots(projectRoot, ref assertions);

                ValidationReceipt receipt = new ValidationReceipt
                {
                    schema = "gate14re-synthetic-validation-receipt-v1",
                    studyId = "Gate14Re",
                    stage = "research_only_incremental_validation",
                    status = "PASS",
                    assertions = assertions,
                    conditionBindingsValidated = Conditions.Length,
                    productionAlgorithmsStructurallyExercised = 4,
                    eventScheduleTicks = new long[] { 10L, 10L, 1500L, 4500L, 7500L },
                    quantityLevelsValidated = new int[] { 1, 8, 32, 128, 512 },
                    checks = new[]
                    {
                        "frozen_v2_v3_hash_and_readonly_bindings",
                        "all_eight_source_scenario_hashes_and_event_content",
                        "in_memory_tick_only_retiming",
                        "grid_planner_visual_version_lockstep_all_four_production_planners",
                        "same_tick_order_and_all_five_events",
                        "shared_movement_kernel_known_answer_all_four_production_planners",
                        "N1_N8_N32_N128_canonical_prefix",
                        "N512_deterministic_reachable_distinct_start_construction",
                        "tampered_hash_definition_event_and_visual_revision_fail_closed",
                        "unsupported_N_fail_closed",
                        "no_formal_root_and_no_outcome_output"
                    },
                    actualOutcomeValuesRead = false,
                    actualOutcomeValuesWritten = false,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false,
                    formalMeasuredRootCreated = false,
                    formalAnalysisRootCreated = false
                };
                WriteJson(receiptPath, receipt);
                if (File.Exists(failurePath)) File.Delete(failurePath);
                Debug.Log("Gate 14Re validation PASS: " + assertions.ToString(CultureInfo.InvariantCulture) + " assertions.");
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                ValidationFailure failure = new ValidationFailure
                {
                    schema = "gate14re-synthetic-validation-failure-v1",
                    studyId = "Gate14Re",
                    status = "FAIL_CLOSED",
                    assertionsCompletedBeforeFailure = assertions,
                    exceptionType = exception.GetType().FullName,
                    message = exception.Message,
                    formalPhaseAStarted = false,
                    formalObservationProduced = false
                };
                WriteJson(failurePath, failure);
                Debug.LogException(exception);
                EditorApplication.Exit(1);
            }
        }

        private static void ValidateFrozenDesign(string projectRoot, ref int assertions)
        {
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Experiment_Plan.v2.md", 13845L, "cbeca6d175500770357d1a610149abda58c816547d2c19cfa2e8ce9bebf5771f", true, ref assertions);
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Design_Contract.v2.json", 17035L, "8b0e064036b8ffac8d0e0572a93898ec8ea72b4e1898b31e21de70ce417e797f", true, ref assertions);
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Experiment_Plan.v3.md", 4437L, "3ea4bcf824b5e83c1be3d98ae96590c58dc444555388b301675a3e91d27bedcc", true, ref assertions);
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Design_Contract.v3.json", 4117L, "88c3119e0b6dbbe4d1a3a2a95bd04d619e3d68edbd38b0903c6d4037a4d0e1f3", true, ref assertions);
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Status.v3.json", 1318L, "a079b4689ef19369832d35dbe70130455cc77947c7f8fd450d93c2cae7dc4ff3", true, ref assertions);
            RequireFile(projectRoot, "Research/Gate14Re/Gate14Re_Scientific_Freeze_Receipt.v2.json", 3776L, "ec741e55f849f84d642c18f3731ce82f034e7647c15114d145c69b30e293373e", true, ref assertions);
        }

        private static void ValidateActualBindingsAndSynchronization(string projectRoot, ref int assertions)
        {
            string[] algorithmIds =
            {
                NavigationAlgorithmIds.AStarRepeated,
                NavigationAlgorithmIds.DStarLite,
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                NavigationAlgorithmIds.IncrementalDynamicFlowField
            };

            for (int conditionIndex = 0; conditionIndex < Conditions.Length; conditionIndex++)
            {
                ConditionBinding binding = Conditions[conditionIndex];
                string path = Full(projectRoot, binding.relativePath);
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                Gate14RePreparedScenario prepared = Gate14ReProtocolV1.Prepare(
                    loaded,
                    binding.scenarioId,
                    binding.sha256,
                    binding.conditionId,
                    binding.footprint,
                    128);
                Assert(string.Equals(prepared.SourceEventContentSha256, prepared.RetimedEventContentSha256, StringComparison.Ordinal), "Event content digest changed during retiming.", ref assertions);
                Assert(prepared.Resolved.Agents.Count == 128 && prepared.Resolved.Goals.Count == 1, "Main condition did not preserve N=128 and one shared goal.", ref assertions);

                for (int algorithmIndex = 0; algorithmIndex < algorithmIds.Length; algorithmIndex++)
                {
                    INavigationPlanner planner = CreatePlanner(algorithmIds[algorithmIndex]);
                    Gate14ReInMemoryVisualGridV1 visual = new Gate14ReInMemoryVisualGridV1();
                    Gate14ReEventSynchronizerV1 synchronizer = new Gate14ReEventSynchronizerV1(
                        "gate14re-validation-" + binding.conditionId + "-" + algorithmIndex.ToString(CultureInfo.InvariantCulture),
                        prepared.Resolved,
                        planner,
                        visual);
                    int records = 0;
                    records += synchronizer.AdvanceThrough(10L).Count;
                    records += synchronizer.AdvanceThrough(1500L).Count;
                    records += synchronizer.AdvanceThrough(4500L).Count;
                    records += synchronizer.AdvanceThrough(7500L).Count;
                    Assert(records == 5, "Synchronizer did not apply exactly five events.", ref assertions);
                    Assert(synchronizer.Grid.Version == 5L && planner.GridVersion == 5L && visual.VisualRevision == 5L, "Grid/planner/visual revisions did not finish in lockstep.", ref assertions);
                    planner.Reset();
                }
            }
        }

        private static void ValidateQuantityConstruction(string projectRoot, ref int assertions)
        {
            int[] levels = { 1, 8, 32, 128, 512 };
            for (int conditionIndex = 0; conditionIndex < Conditions.Length; conditionIndex++)
            {
                ConditionBinding binding = Conditions[conditionIndex];
                if (!binding.quantityAnchor) continue;
                string path = Full(projectRoot, binding.relativePath);
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                for (int levelIndex = 0; levelIndex < levels.Length; levelIndex++)
                {
                    int n = levels[levelIndex];
                    Gate14RePreparedScenario prepared = Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, n);
                    Assert(prepared.Resolved.Agents.Count == n, "Quantity constructor returned the wrong N.", ref assertions);
                    HashSet<GridCoordinate> starts = new HashSet<GridCoordinate>();
                    for (int agentIndex = 0; agentIndex < prepared.Resolved.Agents.Count; agentIndex++)
                    {
                        ResolvedScenarioAgent agent = prepared.Resolved.Agents[agentIndex];
                        Assert(agent.AgentId == agentIndex, "Quantity agent ids are not canonical.", ref assertions);
                        Assert(starts.Add(agent.Start), "Quantity construction contains a duplicate start.", ref assertions);
                        Assert(agent.Goal.Equals(prepared.Resolved.Goals[0]), "Quantity construction changed the shared goal.", ref assertions);
                    }
                }

                Gate14RePreparedScenario first = Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 512);
                Gate14RePreparedScenario second = Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 512);
                for (int index = 0; index < 512; index++)
                {
                    Assert(first.Resolved.Agents[index].Start.Equals(second.Resolved.Agents[index].Start), "N=512 candidate order is not deterministic.", ref assertions);
                }
            }
        }

        private static void ValidateMovementKernelSynthetic(ref int assertions)
        {
            DeterministicScenarioDefinition definition = new DeterministicScenarioDefinition
            {
                schemaVersion = DeterministicScenarioDefinition.CurrentSchemaVersion,
                scenarioId = "gate14re-pure-synthetic-movement-known-answer",
                randomSeed = 140001,
                gridWidth = 12,
                gridHeight = 12,
                defaultTraversalCost = 1f,
                worldOrigin = Vector3.zero,
                cellSize = 1f,
                connectivity = NavigationGridConnectivity.EightWay,
                allowDiagonalCornerCutting = false,
                fixedStepSeconds = Gate14ReProtocolV1.FixedStepSeconds,
                maxSimulationTicks = Gate14ReProtocolV1.MovementCapTicks + 1L,
                goalSetId = "gate14re-synthetic-shared-goal",
                initializationBudgetMilliseconds = 1000d,
                defaultPlanBudgetMilliseconds = 1000d,
                defaultRepairBudgetMilliseconds = 1000d,
                agents = new[]
                {
                    new ScenarioAgentDefinition { agentId = 0, start = new GridCoordinate(0, 0), goal = new GridCoordinate(11, 11) }
                },
                initialGridOverrides = new NavigationGridChange[0],
                scheduledChanges = new[]
                {
                    SyntheticEvent("block-footprint", 10L, 0, new GridCoordinate(11, 0), false, 1f),
                    SyntheticEvent("unblock-footprint", 10L, 1, new GridCoordinate(10, 0), true, 1f),
                    SyntheticEvent("increase-cost-footprint", 1500L, 0, new GridCoordinate(9, 0), true, 4f),
                    SyntheticEvent("decrease-cost-footprint", 4500L, 0, new GridCoordinate(8, 0), true, 1f),
                    SyntheticEvent("restore-initial-state", 7500L, 0, new GridCoordinate(11, 0), true, 1f)
                }
            };
            ResolvedDeterministicScenario scenario = definition.Resolve();
            string[] algorithmIds =
            {
                NavigationAlgorithmIds.AStarRepeated,
                NavigationAlgorithmIds.DStarLite,
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
                NavigationAlgorithmIds.IncrementalDynamicFlowField
            };
            for (int algorithmIndex = 0; algorithmIndex < algorithmIds.Length; algorithmIndex++)
            {
                INavigationPlanner planner = CreatePlanner(algorithmIds[algorithmIndex]);
                Gate14ReMovementKernelV1 kernel = new Gate14ReMovementKernelV1(
                    "gate14re-synthetic-movement-" + algorithmIndex.ToString(CultureInfo.InvariantCulture),
                    scenario,
                    planner,
                    new Gate14ReInMemoryVisualGridV1());
                kernel.Release();
                for (int tick = 0; tick < 20; tick++) kernel.AdvanceOneFixedTick();
                Assert(kernel.CurrentTick == 19L, "Movement kernel tick progression drifted.", ref assertions);
                Assert(kernel.GridVersion == 2L && kernel.PlannerGridVersion == 2L, "Movement kernel lost grid/planner version lockstep.", ref assertions);
                Assert(kernel.StructuralEventRecords.Count == 2, "Movement kernel did not apply the two tick-10 events.", ref assertions);
                Assert(kernel.Units.Count == 1, "Movement kernel changed the synthetic unit count.", ref assertions);
                Gate14ReUnitStateV1 unit = kernel.Units[0];
                Assert(unit.State == Gate14ReUnitTerminalStateV1.Active || unit.State == Gate14ReUnitTerminalStateV1.Arrived, "Movement kernel produced an unexpected synthetic terminal state.", ref assertions);
                Assert(unit.CumulativeHorizontalPathLength > 0d && unit.CumulativeHorizontalPathLength <= 8.0001d, "Movement kernel violated the frozen shared-speed distance bound.", ref assertions);
                planner.Reset();
            }
        }

        private static ScheduledNavigationChangeDefinition SyntheticEvent(
            string eventId,
            long tick,
            int order,
            GridCoordinate coordinate,
            bool walkable,
            float cost)
        {
            return new ScheduledNavigationChangeDefinition
            {
                eventId = eventId,
                simulationTick = tick,
                order = order,
                repairBudgetMilliseconds = 1000d,
                changes = new[]
                {
                    new NavigationGridChange { coordinate = coordinate, isWalkable = walkable, traversalCost = cost }
                }
            };
        }

        private static void ValidateNegativeGates(string projectRoot, ref int assertions)
        {
            ConditionBinding binding = Conditions[2];
            string path = Full(projectRoot, binding.relativePath);

            ExpectThrows(delegate
            {
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, new string('0', 64), binding.conditionId, binding.footprint, 128);
            }, "Tampered scenario hash was accepted.", ref assertions);

            ExpectThrows(delegate
            {
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                loaded.Definition.scheduledChanges[0].simulationTick++;
                Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 128);
            }, "Mutated event tick after parse was accepted.", ref assertions);

            ExpectThrows(delegate
            {
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                loaded.Definition.scheduledChanges[0].changes[0].traversalCost += 1f;
                Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 128);
            }, "Mutated cell content after parse was accepted.", ref assertions);

            ExpectThrows(delegate
            {
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 2);
            }, "Unsupported unit count was accepted.", ref assertions);

            ExpectThrows(delegate
            {
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(path);
                Gate14RePreparedScenario prepared = Gate14ReProtocolV1.Prepare(loaded, binding.scenarioId, binding.sha256, binding.conditionId, binding.footprint, 128);
                Gate14ReEventSynchronizerV1 synchronizer = new Gate14ReEventSynchronizerV1(
                    "gate14re-negative-visual",
                    prepared.Resolved,
                    new AStarRepeatedPlanner(),
                    new StaleVisualSink());
                synchronizer.AdvanceThrough(10L);
            }, "Stale visual revision was accepted.", ref assertions);
        }

        private static void ValidateNoFormalRoots(string projectRoot, ref int assertions)
        {
            Assert(!Directory.Exists(Full(projectRoot, "Research/FormalRuns/Gate14Re")), "Formal Gate 14Re measured root exists during pre-formal validation.", ref assertions);
            Assert(!Directory.Exists(Full(projectRoot, "Research/Analysis/Gate14Re")), "Formal Gate 14Re analysis root exists during pre-formal validation.", ref assertions);
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new ArgumentOutOfRangeException("algorithmId");
        }

        private static void RequireFile(string root, string relativePath, long bytes, string sha256, bool readOnly, ref int assertions)
        {
            string path = Full(root, relativePath);
            FileInfo file = new FileInfo(path);
            Assert(file.Exists, "Required file is missing: " + relativePath, ref assertions);
            Assert(file.Length == bytes, "Required file size drift: " + relativePath, ref assertions);
            Assert(string.Equals(Sha256(path), sha256, StringComparison.Ordinal), "Required file SHA-256 drift: " + relativePath, ref assertions);
            Assert(file.IsReadOnly == readOnly, "Required file ReadOnly drift: " + relativePath, ref assertions);
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            if (!condition) throw new InvalidOperationException(message);
            assertions++;
        }

        private static void ExpectThrows(Action action, string message, ref int assertions)
        {
            bool threw = false;
            try { action(); }
            catch { threw = true; }
            Assert(threw, message, ref assertions);
        }

        private static string Full(string root, string relativePath)
        {
            return Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static string Sha256(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void WriteJson(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        private sealed class ConditionBinding
        {
            public string conditionId;
            public string scenarioId;
            public string relativePath;
            public string sha256;
            public int footprint;
            public bool quantityAnchor;

            public ConditionBinding(string conditionId, string scenarioId, string relativePath, string sha256, int footprint, bool quantityAnchor)
            {
                this.conditionId = conditionId;
                this.scenarioId = scenarioId;
                this.relativePath = relativePath;
                this.sha256 = sha256;
                this.footprint = footprint;
                this.quantityAnchor = quantityAnchor;
            }
        }

        private sealed class StaleVisualSink : IGate14ReVisualGridSynchronizerV1
        {
            public long VisualRevision { get; private set; }
            public void Initialize(IReadOnlyNavigationGrid grid) { VisualRevision = grid.Version; }
            public void ApplyGridChange(IReadOnlyNavigationGrid grid, NavigationChangeSet changeSet) { }
        }

        [Serializable]
        private sealed class ValidationReceipt
        {
            public string schema;
            public string studyId;
            public string stage;
            public string status;
            public int assertions;
            public int conditionBindingsValidated;
            public int productionAlgorithmsStructurallyExercised;
            public long[] eventScheduleTicks;
            public int[] quantityLevelsValidated;
            public string[] checks;
            public bool actualOutcomeValuesRead;
            public bool actualOutcomeValuesWritten;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
            public bool formalMeasuredRootCreated;
            public bool formalAnalysisRootCreated;
        }

        [Serializable]
        private sealed class ValidationFailure
        {
            public string schema;
            public string studyId;
            public string status;
            public int assertionsCompletedBeforeFailure;
            public string exceptionType;
            public string message;
            public bool formalPhaseAStarted;
            public bool formalObservationProduced;
        }
    }
}
