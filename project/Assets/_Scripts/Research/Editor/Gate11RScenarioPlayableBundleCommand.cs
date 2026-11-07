using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using DDM.Research.Visualization;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Create-new Gate 11R matrix and Playable bundle command. UnitTests never
    /// creates production roots; Generate runs once; Verify is read-only.
    /// </summary>
    public static class Gate11RScenarioPlayableBundleCommand
    {
        private const string ScenarioRootRelative = "Research/FormalScenarios/Gate11R_5pct/v1";
        private const string PlayableCatalogRootRelative = "Research/PlayableExperiments/Gate11R_5pct/v1";
        private const string PlayableAssetRootRelative = "Assets/_Scenes/Research/Playable/Gate11R_5pct/v1";
        private const string VerificationRootRelative = "Research/Verification/Gate11R_5pct/v2";
        private const string ScenarioStagingRelative = "Research/FormalScenarios/Gate11R_5pct/.staging-v1-attempt2";
        private const string CatalogStagingRelative = "Research/PlayableExperiments/Gate11R_5pct/.staging-v1-attempt2";
        private const string AssetStagingRelative = "Assets/_Scenes/Research/Playable/Gate11R_5pct/_staging-v1-attempt2-retry2";
        private const string ScenarioDirectoryName = "Scenarios";
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);

        private static readonly string[] SharedAlgorithms =
        {
            NavigationAlgorithmIds.AStarRepeated,
            NavigationAlgorithmIds.DStarLite,
            NavigationAlgorithmIds.IncrementalDynamicFlowField,
            NavigationAlgorithmIds.CorrectedFullRecomputeFlowField
        };

        private static readonly string[][] SharedWilliams =
        {
            new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField },
            new[] { NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.IncrementalDynamicFlowField },
            new[] { NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.AStarRepeated },
            new[] { NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.DStarLite }
        };

        private static readonly string[][] PerAgentWilliams =
        {
            new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite },
            new[] { NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.AStarRepeated }
        };

        private static readonly string[][] GroupedFieldWilliams =
        {
            new[] { NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField },
            new[] { NavigationAlgorithmIds.IncrementalDynamicFlowField, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField }
        };

        [Serializable]
        private sealed class CommandResult
        {
            public int schemaVersion = 2;
            public string commandId;
            public string mode;
            public bool passed;
            public string createdAtUtc;
            public int assertionCount;
            public int scenarioCount;
            public int sharedScenarioCount;
            public int heterogeneousScenarioCount;
            public int campaignCount;
            public int eligibilityCount;
            public int sceneCount;
            public int profileCount;
            public int presetCount;
            public int plannerInitializationCount;
            public int artifactCount;
            public int negativeTestCount;
            public string manifestSha256;
            public string coverageGraphSha256;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
            public bool timingSamplesCollected;
            public string error;
        }

        [Serializable]
        private sealed class MatrixDocument
        {
            public int schemaVersion = 2;
            public string specificationId;
            public string matrixId;
            public string generatorId;
            public string executionDesignId;
            public string precisionPolicyId;
            public int scenarioCount;
            public int campaignCount;
            public int eligibilityCount;
            public ScenarioRecord[] scenarios;
            public CampaignRecord[] campaigns;
            public PresetRecord[] eligibilityEntries;
        }

        [Serializable]
        private sealed class ScenarioCatalogDocument
        {
            public int schemaVersion = 2;
            public string matrixId;
            public int scenarioCount;
            public ScenarioRecord[] scenarios;
        }

        [Serializable]
        private sealed class ScenarioRecord
        {
            public string scenarioId;
            public string familyId;
            public string levelId;
            public int structuralRow;
            public int seedReplication;
            public int randomSeed;
            public int gridWidth;
            public int gridHeight;
            public int connectivity;
            public string terrainModeId;
            public double targetObstacleDensity;
            public int targetObstacleCount;
            public int agentCount;
            public int dynamicFootprint;
            public string goalStructureId;
            public int distinctGoalCount;
            public string dynamicProfileId;
            public string scenarioRelativePath;
            public long scenarioRawBytes;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string sceneAssetPath;
            public string sceneAssetGuid;
            public long sceneRawBytes;
            public string sceneSha256;
            public string[] campaignIds;
        }

        [Serializable]
        private sealed class CampaignRecord
        {
            public string campaignId;
            public string scenarioId;
            public string scenarioRelativePath;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string comparisonCohortId;
            public string[] eligibleAlgorithmIds;
            public WilliamsRow[] williamsRows;
            public string sceneAssetPath;
            public string profileAssetPath;
            public string profileAssetGuid;
            public long profileRawBytes;
            public string profileSha256;
            public bool pilotAnchor;
        }

        [Serializable]
        private sealed class WilliamsRow
        {
            public int rowIndex;
            public string[] algorithms;
        }

        [Serializable]
        private sealed class PresetRecord
        {
            public string presetId;
            public string matrixEntryId;
            public string campaignId;
            public string scenarioId;
            public string comparisonCohortId;
            public string algorithmId;
            public string sceneAssetPath;
            public string profileAssetPath;
            public string presetAssetPath;
            public string presetAssetGuid;
            public long presetRawBytes;
            public string presetSha256;
        }

        [Serializable]
        private sealed class PreregistrationDocument
        {
            public int schemaVersion = 2;
            public string preregistrationId;
            public string specificationId;
            public string matrixId;
            public string executionDesignId;
            public string independentUnit;
            public string precisionPolicyId;
            public double logRelativeHalfWidthTarget;
            public string formula;
            public int minimumBlocks;
            public int blockMultiple;
            public bool hardCapEnabled;
            public string[] primaryAnalysisIds;
            public string[] secondaryAnalysisIds;
            public string multiplicityPolicy;
            public string clusteringPolicy;
            public string[] exclusionRules;
            public string[] forbiddenExclusions;
            public string[] pilotCampaignAnchors;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
        }

        [Serializable]
        private sealed class PlayableSceneCatalogDocument
        {
            public int schemaVersion = 2;
            public string playableBundleId;
            public string matrixId;
            public string directionGlyphId;
            public string captureLayoutId;
            public string watermark;
            public int sceneCount;
            public ScenarioRecord[] scenes;
        }

        [Serializable]
        private sealed class CampaignCatalogDocument
        {
            public int schemaVersion = 2;
            public string playableBundleId;
            public int campaignCount;
            public CampaignRecord[] campaigns;
        }

        [Serializable]
        private sealed class PresetCatalogDocument
        {
            public int schemaVersion = 2;
            public string playableBundleId;
            public int presetCount;
            public PresetRecord[] presets;
        }

        [Serializable]
        private sealed class CoverageDocument
        {
            public int schemaVersion = 2;
            public string coverageId;
            public string playableBundleId;
            public string matrixId;
            public int scenarioCount;
            public int campaignCount;
            public int presetCount;
            public string launcherSceneAssetPath;
            public string launcherSceneAssetGuid;
            public string launcherSceneSha256;
            public string coverageGraphSha256;
            public bool visualizationOnly;
            public bool timingEvidenceAllowed;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
        }

        [Serializable]
        private sealed class BundleManifest
        {
            public int schemaVersion = 2;
            public string manifestId;
            public string specificationId;
            public string specificationSha256;
            public string testDesignSha256;
            public string generatorId;
            public string generatorSourceSha256;
            public string retainedGeneratorSourceSha256;
            public string commandSourceSha256;
            public string campaignProfileSourceSha256;
            public string algorithmPresetSourceSha256;
            public string sceneControllerSourceSha256;
            public string launcherSourceSha256;
            public string matrixId;
            public string preregistrationId;
            public string playableBundleId;
            public string executionDesignId;
            public string precisionPolicyId;
            public string scenarioRoot;
            public string playableCatalogRoot;
            public string playableAssetRoot;
            public int scenarioCount;
            public int campaignCount;
            public int eligibilityCount;
            public int sceneCount;
            public int profileCount;
            public int presetCount;
            public ArtifactRecord[] artifacts;
            public string artifactAggregateSha256;
            public bool visualizationOnly;
            public bool timingEvidenceAllowed;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
        }

        [Serializable]
        private sealed class ArtifactRecord
        {
            public string relativePath;
            public long rawBytes;
            public string sha256;
        }

        private sealed class BuildState
        {
            public readonly List<ScenarioRecord> Scenarios = new List<ScenarioRecord>();
            public readonly List<CampaignRecord> Campaigns = new List<CampaignRecord>();
            public readonly List<PresetRecord> Presets = new List<PresetRecord>();
            public string LauncherAssetPath;
            public string LauncherGuid;
            public string LauncherSha256;
            public string CoverageGraphSha256;
        }

        public static void UnitTests() { Run("unit"); }
        public static void Generate() { Run("generate"); }
        public static void GenerateRetry2() { Run("generate-retry2"); }
        public static void Verify() { Run("verify"); }

        private static void Run(string mode)
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string verificationRoot = Full(projectRoot, VerificationRootRelative);
            Directory.CreateDirectory(verificationRoot);
            string resultPath = Path.Combine(verificationRoot, mode == "unit" ? "Gate11R_UnitTests.summary.v2.json" : mode == "generate" ? "Gate11R_Generation.summary.v2.json" : mode == "generate-retry2" ? "Gate11R_Generation.summary.v2.2.json" : "Gate11R_Verification.summary.v2.json");
            CommandResult result = new CommandResult
            {
                commandId = "gate11r-scenario-playable-bundle-command-v2",
                mode = mode,
                createdAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                pilotExecuted = false,
                formalCampaignExecuted = false,
                timingSamplesCollected = false,
                error = string.Empty
            };
            try
            {
                int assertions = 0;
                if (mode == "unit") RunUnitTests(projectRoot, result, ref assertions);
                else if (mode == "generate" || mode == "generate-retry2") GenerateBundle(projectRoot, result, ref assertions);
                else if (mode == "verify") VerifyBundle(projectRoot, result, ref assertions);
                else throw new ArgumentOutOfRangeException("mode");
                result.assertionCount = assertions;
                result.passed = true;
                WriteJsonReplace(resultPath, result);
                Debug.Log("Gate 11R " + mode + " passed with " + assertions + " assertions.");
            }
            catch (Exception exception)
            {
                result.passed = false;
                result.error = exception.ToString();
                WriteJsonReplace(resultPath, result);
                Debug.LogException(exception);
                throw;
            }
        }

        private static void RunUnitTests(string projectRoot, CommandResult result, ref int assertions)
        {
            AssertProductionRootsAbsent(projectRoot, ref assertions);
            FormalScenarioBlueprint[] blueprints = Gate11RFormalScenarioMatrixGenerator.BuildBlueprints();
            BuildState state = BuildMetadataOnly(blueprints, ref assertions);
            ValidateBlueprints(blueprints, ref assertions);
            ValidateCampaignsAndPresets(state, ref assertions);
            ValidateWilliams(state.Campaigns, ref assertions);
            ValidatePrecisionAndPreregistration(BuildPreregistration(state), state, ref assertions);
            RunNegativeUnitTests(state, ref assertions);
            SetCounts(result, state, blueprints);
            result.negativeTestCount = 10;
        }

        private static BuildState BuildMetadataOnly(FormalScenarioBlueprint[] blueprints, ref int assertions)
        {
            BuildState state = new BuildState();
            for (int index = 0; index < blueprints.Length; index++)
            {
                FormalScenarioBlueprint blueprint = blueprints[index];
                ScenarioRecord scenario = NewScenarioRecord(blueprint);
                scenario.scenarioRelativePath = ScenarioRootRelative + "/Scenarios/" + blueprint.scenarioId + ".scenario.json";
                scenario.sceneAssetPath = PlayableAssetRootRelative + "/Scenarios/" + blueprint.scenarioId + ".unity";
                state.Scenarios.Add(scenario);
                AddCampaignsAndPresets(scenario, blueprint.IsSharedGoal, state);
            }
            LinkCampaignIds(state);
            Assert(state.Scenarios.Count == 53 && state.Campaigns.Count == 74 && state.Presets.Count == 212, "Metadata-only coverage counts differ.", ref assertions);
            return state;
        }

        private static void GenerateBundle(string projectRoot, CommandResult result, ref int assertions)
        {
            AssertProductionRootsAbsent(projectRoot, ref assertions);
            string scenarioStage = Full(projectRoot, ScenarioStagingRelative);
            string catalogStage = Full(projectRoot, CatalogStagingRelative);
            string assetStageFull = Full(projectRoot, AssetStagingRelative);
            Assert(!Directory.Exists(scenarioStage) && !Directory.Exists(catalogStage) && !Directory.Exists(assetStageFull), "A Gate 11R staging root already exists.", ref assertions);

            Directory.CreateDirectory(Path.Combine(scenarioStage, ScenarioDirectoryName));
            Directory.CreateDirectory(catalogStage);
            EnsureAssetFolder(AssetStagingRelative);
            EnsureAssetFolder(AssetStagingRelative + "/Scenarios");
            EnsureAssetFolder(AssetStagingRelative + "/CampaignProfiles");
            EnsureAssetFolder(AssetStagingRelative + "/AlgorithmPresets");
            EnsureAssetFolder(AssetStagingRelative + "/Launcher");

            FormalScenarioBlueprint[] blueprints = Gate11RFormalScenarioMatrixGenerator.BuildBlueprints();
            BuildState state = BuildMetadataOnly(blueprints, ref assertions);
            Dictionary<string, FormalScenarioBlueprint> blueprintById = IndexBlueprints(blueprints);
            for (int index = 0; index < state.Scenarios.Count; index++)
            {
                ScenarioRecord record = state.Scenarios[index];
                DeterministicScenarioDefinition definition = Gate11RFormalScenarioMatrixGenerator.GenerateDefinition(blueprintById[record.scenarioId]);
                ResolvedDeterministicScenario resolved = definition.Resolve();
                byte[] bytes = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(resolved));
                string stagePath = Path.Combine(scenarioStage, ScenarioDirectoryName, record.scenarioId + ".scenario.json");
                WriteCreateNew(stagePath, bytes);
                record.scenarioRawBytes = bytes.LongLength;
                record.scenarioSha256 = Sha256(bytes);
                record.scenarioFingerprintSha256 = resolved.FingerprintSha256;
            }
            PropagateScenarioIdentities(state);

            CreateProfiles(state, ref assertions);
            CreatePresets(state, ref assertions);
            CreateScenarioScenes(state, ref assertions);
            CreateLauncherScene(state, ref assertions);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            CaptureAssetIdentities(projectRoot, state, ref assertions);

            ValidateCampaignsAndPresets(state, ref assertions);
            ValidateWilliams(state.Campaigns, ref assertions);
            string coverageGraph = BuildCoverageGraph(state);
            state.CoverageGraphSha256 = Sha256(StrictUtf8.GetBytes(coverageGraph));

            MatrixDocument matrix = BuildMatrix(state);
            ScenarioCatalogDocument catalog = new ScenarioCatalogDocument { matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId, scenarioCount = state.Scenarios.Count, scenarios = state.Scenarios.ToArray() };
            PreregistrationDocument preregistration = BuildPreregistration(state);
            PlayableSceneCatalogDocument sceneCatalog = new PlayableSceneCatalogDocument
            {
                playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId,
                matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId,
                directionGlyphId = Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId,
                captureLayoutId = Gate11RFormalScenarioMatrixGenerator.CaptureLayoutId,
                watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark,
                sceneCount = state.Scenarios.Count,
                scenes = state.Scenarios.ToArray()
            };
            CampaignCatalogDocument campaignCatalog = new CampaignCatalogDocument { playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId, campaignCount = state.Campaigns.Count, campaigns = state.Campaigns.ToArray() };
            PresetCatalogDocument presetCatalog = new PresetCatalogDocument { playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId, presetCount = state.Presets.Count, presets = state.Presets.ToArray() };
            CoverageDocument coverage = new CoverageDocument
            {
                coverageId = "gate11r-53-74-212-playable-coverage-v1",
                playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId,
                matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId,
                scenarioCount = state.Scenarios.Count,
                campaignCount = state.Campaigns.Count,
                presetCount = state.Presets.Count,
                launcherSceneAssetPath = state.LauncherAssetPath,
                launcherSceneAssetGuid = state.LauncherGuid,
                launcherSceneSha256 = state.LauncherSha256,
                coverageGraphSha256 = state.CoverageGraphSha256,
                visualizationOnly = true,
                timingEvidenceAllowed = false,
                pilotExecuted = false,
                formalCampaignExecuted = false
            };

            WriteJsonCreateNew(Path.Combine(scenarioStage, "formal-scenario-matrix.json"), matrix);
            WriteJsonCreateNew(Path.Combine(scenarioStage, "catalog.json"), catalog);
            WriteJsonCreateNew(Path.Combine(scenarioStage, "preregistered-analysis.json"), preregistration);
            WriteJsonCreateNew(Path.Combine(catalogStage, "playable-scene-catalog.json"), sceneCatalog);
            WriteJsonCreateNew(Path.Combine(catalogStage, "campaign-profile-catalog.json"), campaignCatalog);
            WriteJsonCreateNew(Path.Combine(catalogStage, "algorithm-preset-catalog.json"), presetCatalog);
            WriteJsonCreateNew(Path.Combine(catalogStage, "coverage-manifest.json"), coverage);

            List<ArtifactRecord> artifacts = CollectStagedArtifacts(projectRoot, scenarioStage, catalogStage, assetStageFull);
            BundleManifest manifest = BuildManifest(projectRoot, state, artifacts);
            string manifestStagePath = Path.Combine(scenarioStage, "bundle-manifest.json");
            WriteJsonCreateNew(manifestStagePath, manifest);
            string manifestHash = Sha256(File.ReadAllBytes(manifestStagePath));

            AssertStagedCoverage(state, scenarioStage, catalogStage, assetStageFull, ref assertions);
            PromoteResearchDirectory(scenarioStage, Full(projectRoot, ScenarioRootRelative));
            PromoteResearchDirectory(catalogStage, Full(projectRoot, PlayableCatalogRootRelative));
            string moveError = AssetDatabase.MoveAsset(AssetStagingRelative, PlayableAssetRootRelative);
            Assert(string.IsNullOrEmpty(moveError), "Playable asset staging promotion failed: " + moveError, ref assertions);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            ValidatePromotedAssetGuids(state, ref assertions);

            result.manifestSha256 = manifestHash;
            result.coverageGraphSha256 = state.CoverageGraphSha256;
            result.artifactCount = artifacts.Count;
            SetCounts(result, state, blueprints);
            AssertProductionRootsPresent(projectRoot, ref assertions);
        }

        private static void VerifyBundle(string projectRoot, CommandResult result, ref int assertions)
        {
            AssertProductionRootsPresent(projectRoot, ref assertions);
            Dictionary<string, string> before = SnapshotProductionFiles(projectRoot);
            string scenarioRoot = Full(projectRoot, ScenarioRootRelative);
            BundleManifest manifest = LoadJson<BundleManifest>(Path.Combine(scenarioRoot, "bundle-manifest.json"));
            MatrixDocument matrix = LoadJson<MatrixDocument>(Path.Combine(scenarioRoot, "formal-scenario-matrix.json"));
            ScenarioCatalogDocument catalog = LoadJson<ScenarioCatalogDocument>(Path.Combine(scenarioRoot, "catalog.json"));
            PreregistrationDocument preregistration = LoadJson<PreregistrationDocument>(Path.Combine(scenarioRoot, "preregistered-analysis.json"));
            string playableRoot = Full(projectRoot, PlayableCatalogRootRelative);
            PlayableSceneCatalogDocument sceneCatalog = LoadJson<PlayableSceneCatalogDocument>(Path.Combine(playableRoot, "playable-scene-catalog.json"));
            CampaignCatalogDocument campaignCatalog = LoadJson<CampaignCatalogDocument>(Path.Combine(playableRoot, "campaign-profile-catalog.json"));
            PresetCatalogDocument presetCatalog = LoadJson<PresetCatalogDocument>(Path.Combine(playableRoot, "algorithm-preset-catalog.json"));
            CoverageDocument coverage = LoadJson<CoverageDocument>(Path.Combine(playableRoot, "coverage-manifest.json"));

            VerifyHeadersAndCounts(manifest, matrix, catalog, preregistration, sceneCatalog, campaignCatalog, presetCatalog, coverage, ref assertions);
            VerifyManifestArtifacts(projectRoot, manifest, ref assertions);
            FormalScenarioBlueprint[] blueprints = Gate11RFormalScenarioMatrixGenerator.BuildBlueprints();
            Dictionary<string, FormalScenarioBlueprint> blueprintById = IndexBlueprints(blueprints);
            VerifyScenarios(projectRoot, matrix.scenarios, blueprintById, ref assertions);
            VerifyCampaignProfiles(campaignCatalog.campaigns, ref assertions);
            VerifyAlgorithmPresets(presetCatalog.presets, ref assertions);
            VerifyScenes(matrix.scenarios, coverage, ref assertions);
            BuildState state = new BuildState();
            state.Scenarios.AddRange(matrix.scenarios);
            state.Campaigns.AddRange(campaignCatalog.campaigns);
            state.Presets.AddRange(presetCatalog.presets);
            state.CoverageGraphSha256 = coverage.coverageGraphSha256;
            ValidateCampaignsAndPresets(state, ref assertions);
            ValidateWilliams(state.Campaigns, ref assertions);
            Assert(Sha256(StrictUtf8.GetBytes(BuildCoverageGraph(state))) == coverage.coverageGraphSha256, "Coverage graph signature differs.", ref assertions);
            result.plannerInitializationCount = VerifyPlannerInitialization(projectRoot, state.Presets, ref assertions);
            result.negativeTestCount = RunVerificationNegativeTests(state, manifest, ref assertions);
            VerifyTimingIsolation(projectRoot, ref assertions);
            Dictionary<string, string> after = SnapshotProductionFiles(projectRoot);
            Assert(SnapshotsEqual(before, after), "Read-only verification changed a production byte.", ref assertions);

            result.manifestSha256 = Sha256(File.ReadAllBytes(Path.Combine(scenarioRoot, "bundle-manifest.json")));
            result.coverageGraphSha256 = coverage.coverageGraphSha256;
            result.artifactCount = manifest.artifacts.Length;
            SetCounts(result, state, blueprints);
        }

        private static ScenarioRecord NewScenarioRecord(FormalScenarioBlueprint blueprint)
        {
            return new ScenarioRecord
            {
                scenarioId = blueprint.scenarioId,
                familyId = blueprint.familyId,
                levelId = blueprint.levelId,
                structuralRow = blueprint.structuralRow,
                seedReplication = blueprint.seedReplication,
                randomSeed = blueprint.randomSeed,
                gridWidth = blueprint.gridWidth,
                gridHeight = blueprint.gridHeight,
                connectivity = (int)blueprint.connectivity,
                terrainModeId = blueprint.terrainModeId,
                targetObstacleDensity = blueprint.targetObstacleDensity,
                targetObstacleCount = blueprint.targetObstacleCount,
                agentCount = blueprint.agentCount,
                dynamicFootprint = blueprint.dynamicFootprint,
                goalStructureId = blueprint.goalStructureId,
                distinctGoalCount = blueprint.distinctGoalCount,
                dynamicProfileId = blueprint.dynamicProfileId
            };
        }

        private static void AddCampaignsAndPresets(ScenarioRecord scenario, bool shared, BuildState state)
        {
            if (shared)
            {
                AddCampaign(scenario, scenario.scenarioId + "--shared", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, SharedAlgorithms, SharedWilliams, state);
            }
            else
            {
                AddCampaign(scenario, scenario.scenarioId + "--per-agent", PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort,
                    new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite }, PerAgentWilliams, state);
                AddCampaign(scenario, scenario.scenarioId + "--grouped-field", PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort,
                    new[] { NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField }, GroupedFieldWilliams, state);
            }
        }

        private static void AddCampaign(ScenarioRecord scenario, string campaignId, string cohort, string[] algorithms, string[][] rows, BuildState state)
        {
            string profilePath = PlayableAssetRootRelative + "/CampaignProfiles/" + campaignId + ".asset";
            CampaignRecord campaign = new CampaignRecord
            {
                campaignId = campaignId,
                scenarioId = scenario.scenarioId,
                scenarioRelativePath = scenario.scenarioRelativePath,
                scenarioSha256 = scenario.scenarioSha256,
                scenarioFingerprintSha256 = scenario.scenarioFingerprintSha256,
                comparisonCohortId = cohort,
                eligibleAlgorithmIds = (string[])algorithms.Clone(),
                williamsRows = ToWilliamsRows(rows),
                sceneAssetPath = scenario.sceneAssetPath,
                profileAssetPath = profilePath,
                pilotAnchor = IsPilotAnchor(campaignId)
            };
            state.Campaigns.Add(campaign);
            for (int index = 0; index < algorithms.Length; index++)
            {
                string presetId = campaignId + "--" + AlgorithmSlug(algorithms[index]);
                state.Presets.Add(new PresetRecord
                {
                    presetId = presetId,
                    matrixEntryId = scenario.scenarioId + "|" + cohort + "|" + algorithms[index],
                    campaignId = campaignId,
                    scenarioId = scenario.scenarioId,
                    comparisonCohortId = cohort,
                    algorithmId = algorithms[index],
                    sceneAssetPath = scenario.sceneAssetPath,
                    profileAssetPath = profilePath,
                    presetAssetPath = PlayableAssetRootRelative + "/AlgorithmPresets/" + presetId + ".asset"
                });
            }
        }

        private static void LinkCampaignIds(BuildState state)
        {
            for (int s = 0; s < state.Scenarios.Count; s++)
            {
                List<string> ids = new List<string>();
                for (int c = 0; c < state.Campaigns.Count; c++) if (state.Campaigns[c].scenarioId == state.Scenarios[s].scenarioId) ids.Add(state.Campaigns[c].campaignId);
                ids.Sort(StringComparer.Ordinal);
                state.Scenarios[s].campaignIds = ids.ToArray();
            }
        }

        private static void PropagateScenarioIdentities(BuildState state)
        {
            Dictionary<string, ScenarioRecord> scenarios = new Dictionary<string, ScenarioRecord>(StringComparer.Ordinal);
            for (int index = 0; index < state.Scenarios.Count; index++) scenarios.Add(state.Scenarios[index].scenarioId, state.Scenarios[index]);
            for (int index = 0; index < state.Campaigns.Count; index++)
            {
                ScenarioRecord scenario = scenarios[state.Campaigns[index].scenarioId];
                state.Campaigns[index].scenarioSha256 = scenario.scenarioSha256;
                state.Campaigns[index].scenarioFingerprintSha256 = scenario.scenarioFingerprintSha256;
            }
        }

        private static void CreateProfiles(BuildState state, ref int assertions)
        {
            for (int index = 0; index < state.Campaigns.Count; index++)
            {
                CampaignRecord row = state.Campaigns[index];
                Gate11RCampaignProfile asset = ScriptableObject.CreateInstance<Gate11RCampaignProfile>();
                asset.schemaId = "gate11r-campaign-profile-v1";
                asset.campaignId = row.campaignId;
                asset.matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId;
                asset.executionDesignId = Gate11RFormalScenarioMatrixGenerator.ExecutionDesignId;
                asset.scenarioId = row.scenarioId;
                asset.scenarioRelativePath = row.scenarioRelativePath;
                asset.scenarioSha256 = row.scenarioSha256;
                asset.scenarioFingerprintSha256 = row.scenarioFingerprintSha256;
                asset.sceneAssetPath = row.sceneAssetPath;
                asset.comparisonCohortId = row.comparisonCohortId;
                asset.eligibleAlgorithmIds = (string[])row.eligibleAlgorithmIds.Clone();
                asset.williamsRows = WilliamsStrings(row.williamsRows);
                asset.defaultBlockOrdinal = 0;
                asset.visualizationOnly = true;
                asset.timingEvidenceAllowed = false;
                string stagePath = ToStagingAssetPath(row.profileAssetPath);
                AssetDatabase.CreateAsset(asset, stagePath);
            }
            Assert(state.Campaigns.Count == 74, "Profile creation count differs.", ref assertions);
        }

        private static void CreatePresets(BuildState state, ref int assertions)
        {
            for (int index = 0; index < state.Presets.Count; index++)
            {
                PresetRecord row = state.Presets[index];
                ScenarioRecord scenario = FindScenario(state, row.scenarioId);
                Gate11RAlgorithmPreset asset = ScriptableObject.CreateInstance<Gate11RAlgorithmPreset>();
                asset.schemaId = "gate11r-algorithm-preset-v1";
                asset.presetId = row.presetId;
                asset.matrixEntryId = row.matrixEntryId;
                asset.campaignId = row.campaignId;
                asset.campaignProfileAssetPath = row.profileAssetPath;
                asset.scenarioId = row.scenarioId;
                asset.scenarioRelativePath = scenario.scenarioRelativePath;
                asset.scenarioSha256 = scenario.scenarioSha256;
                asset.sceneAssetPath = row.sceneAssetPath;
                asset.comparisonCohortId = row.comparisonCohortId;
                asset.algorithmId = row.algorithmId;
                asset.directionGlyphId = Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId;
                asset.captureLayoutId = Gate11RFormalScenarioMatrixGenerator.CaptureLayoutId;
                asset.watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark;
                asset.visualizationOnly = true;
                asset.timingEvidenceAllowed = false;
                AssetDatabase.CreateAsset(asset, ToStagingAssetPath(row.presetAssetPath));
            }
            Assert(state.Presets.Count == 212, "Preset creation count differs.", ref assertions);
        }

        private static void CreateScenarioScenes(BuildState state, ref int assertions)
        {
            for (int index = 0; index < state.Scenarios.Count; index++)
            {
                ScenarioRecord row = state.Scenarios[index];
                Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                GameObject root = new GameObject("Gate11RPlayableSceneController");
                Gate11RPlayableSceneController controller = root.AddComponent<Gate11RPlayableSceneController>();
                controller.Configure(row.scenarioId, row.scenarioRelativePath, row.scenarioSha256, row.scenarioFingerprintSha256,
                    row.campaignIds, AlgorithmsForScenario(row));
                GameObject cameraObject = new GameObject("Gate11RFixedCaptureCamera");
                Camera camera = cameraObject.AddComponent<Camera>();
                camera.orthographic = true;
                camera.orthographicSize = 5f;
                camera.clearFlags = CameraClearFlags.SolidColor;
                camera.backgroundColor = new Color(0.035f, 0.04f, 0.055f, 1f);
                cameraObject.transform.position = new Vector3(0f, 0f, -10f);
                string stagePath = ToStagingAssetPath(row.sceneAssetPath);
                Assert(EditorSceneManager.SaveScene(scene, stagePath, false), "Failed to save Playable scene: " + row.scenarioId, ref assertions);
            }
            Assert(state.Scenarios.Count == 53, "Scene creation count differs.", ref assertions);
        }

        private static void CreateLauncherScene(BuildState state, ref int assertions)
        {
            state.Presets.Sort(delegate(PresetRecord left, PresetRecord right) { return string.CompareOrdinal(left.presetId, right.presetId); });
            string[] presetIds = new string[state.Presets.Count];
            string[] scenarioIds = new string[state.Presets.Count];
            string[] campaignIds = new string[state.Presets.Count];
            string[] algorithmIds = new string[state.Presets.Count];
            string[] scenePaths = new string[state.Presets.Count];
            for (int index = 0; index < state.Presets.Count; index++)
            {
                presetIds[index] = state.Presets[index].presetId;
                scenarioIds[index] = state.Presets[index].scenarioId;
                campaignIds[index] = state.Presets[index].campaignId;
                algorithmIds[index] = state.Presets[index].algorithmId;
                scenePaths[index] = state.Presets[index].sceneAssetPath;
            }
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            GameObject root = new GameObject("Gate11RPlayableLauncher");
            Gate11RPlayableLauncher launcher = root.AddComponent<Gate11RPlayableLauncher>();
            launcher.Configure(presetIds, scenarioIds, campaignIds, algorithmIds, scenePaths);
            GameObject cameraObject = new GameObject("Gate11RLauncherCamera");
            Camera camera = cameraObject.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.035f, 0.04f, 0.055f, 1f);
            state.LauncherAssetPath = PlayableAssetRootRelative + "/Launcher/Gate11R_Playable_Launcher.unity";
            Assert(EditorSceneManager.SaveScene(scene, ToStagingAssetPath(state.LauncherAssetPath), false), "Failed to save the Playable launcher scene.", ref assertions);
        }

        private static void CaptureAssetIdentities(string projectRoot, BuildState state, ref int assertions)
        {
            for (int index = 0; index < state.Scenarios.Count; index++)
            {
                ScenarioRecord row = state.Scenarios[index];
                string stageAsset = ToStagingAssetPath(row.sceneAssetPath);
                string full = Full(projectRoot, stageAsset);
                row.sceneAssetGuid = AssetDatabase.AssetPathToGUID(stageAsset);
                row.sceneRawBytes = new FileInfo(full).Length;
                row.sceneSha256 = Sha256(File.ReadAllBytes(full));
                Assert(!string.IsNullOrWhiteSpace(row.sceneAssetGuid), "Scene GUID is missing: " + row.scenarioId, ref assertions);
            }
            for (int index = 0; index < state.Campaigns.Count; index++)
            {
                CampaignRecord row = state.Campaigns[index];
                string stageAsset = ToStagingAssetPath(row.profileAssetPath);
                string full = Full(projectRoot, stageAsset);
                row.profileAssetGuid = AssetDatabase.AssetPathToGUID(stageAsset);
                row.profileRawBytes = new FileInfo(full).Length;
                row.profileSha256 = Sha256(File.ReadAllBytes(full));
            }
            for (int index = 0; index < state.Presets.Count; index++)
            {
                PresetRecord row = state.Presets[index];
                string stageAsset = ToStagingAssetPath(row.presetAssetPath);
                string full = Full(projectRoot, stageAsset);
                row.presetAssetGuid = AssetDatabase.AssetPathToGUID(stageAsset);
                row.presetRawBytes = new FileInfo(full).Length;
                row.presetSha256 = Sha256(File.ReadAllBytes(full));
            }
            string launcherStage = ToStagingAssetPath(state.LauncherAssetPath);
            state.LauncherGuid = AssetDatabase.AssetPathToGUID(launcherStage);
            state.LauncherSha256 = Sha256(File.ReadAllBytes(Full(projectRoot, launcherStage)));
        }

        private static MatrixDocument BuildMatrix(BuildState state)
        {
            return new MatrixDocument
            {
                specificationId = Gate11RFormalScenarioMatrixGenerator.SpecificationId,
                matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId,
                generatorId = Gate11RFormalScenarioMatrixGenerator.GeneratorId,
                executionDesignId = Gate11RFormalScenarioMatrixGenerator.ExecutionDesignId,
                precisionPolicyId = Gate11RFormalScenarioMatrixGenerator.PrecisionPolicyId,
                scenarioCount = state.Scenarios.Count,
                campaignCount = state.Campaigns.Count,
                eligibilityCount = state.Presets.Count,
                scenarios = state.Scenarios.ToArray(),
                campaigns = state.Campaigns.ToArray(),
                eligibilityEntries = state.Presets.ToArray()
            };
        }

        private static PreregistrationDocument BuildPreregistration(BuildState state)
        {
            List<string> anchors = new List<string>();
            for (int index = 0; index < state.Campaigns.Count; index++) if (state.Campaigns[index].pilotAnchor) anchors.Add(state.Campaigns[index].campaignId);
            anchors.Sort(StringComparer.Ordinal);
            return new PreregistrationDocument
            {
                preregistrationId = Gate11RFormalScenarioMatrixGenerator.PreregistrationId,
                specificationId = Gate11RFormalScenarioMatrixGenerator.SpecificationId,
                matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId,
                executionDesignId = Gate11RFormalScenarioMatrixGenerator.ExecutionDesignId,
                independentUnit = "one-fresh-unity-editor-process-per-complete-williams-block",
                precisionPolicyId = Gate11RFormalScenarioMatrixGenerator.PrecisionPolicyId,
                logRelativeHalfWidthTarget = Gate11RFormalScenarioMatrixGenerator.RelativeHalfWidthLogTarget,
                formula = "ceil((1.96*sigma_upper/ln(1.05))^2), round upward to multiple of four",
                minimumBlocks = Gate11RFormalScenarioMatrixGenerator.MinimumFormalBlocks,
                blockMultiple = Gate11RFormalScenarioMatrixGenerator.FormalBlockMultiple,
                hardCapEnabled = false,
                primaryAnalysisIds = new[] { "P1-shared-planning-repair", "P2-heterogeneous-treatment", "P3-idff-vs-cff-dynamic", "P4-memory-budget-failure" },
                secondaryAnalysisIds = new[] { "S1-factor-trends", "S2-p95-dispersion", "S3-failure-taxonomy", "S4-position-predecessor-process-age", "S5-resource-scaling" },
                multiplicityPolicy = "Holm correction within P1-P4 primary family",
                clusteringPolicy = "Williams block is the independent cluster; paired log contrasts plus mixed or cluster-robust sensitivity",
                exclusionRules = new[] { "invalid-scenario-proven-by-verifier", "missing-eligibility-contract", "frozen-input-hash-mismatch", "prospective-versioned-user-approved-amendment" },
                forbiddenExclusions = new[] { "runtime-magnitude", "effect-direction", "statistical-significance", "NoPath-frequency", "budget-overrun", "unfavorable-result" },
                pilotCampaignAnchors = anchors.ToArray(),
                pilotExecuted = false,
                formalCampaignExecuted = false
            };
        }

        private static BundleManifest BuildManifest(string projectRoot, BuildState state, List<ArtifactRecord> artifacts)
        {
            artifacts.Sort(delegate(ArtifactRecord left, ArtifactRecord right) { return string.CompareOrdinal(left.relativePath, right.relativePath); });
            StringBuilder aggregate = new StringBuilder();
            for (int index = 0; index < artifacts.Count; index++) aggregate.Append(artifacts[index].relativePath).Append('\t').Append(artifacts[index].rawBytes).Append('\t').Append(artifacts[index].sha256).Append('\n');
            return new BundleManifest
            {
                manifestId = "gate11r-scenario-playable-bundle-manifest-v1",
                specificationId = Gate11RFormalScenarioMatrixGenerator.SpecificationId,
                specificationSha256 = FileSha(projectRoot, "Research/Gate11R_5pct_Scenario_Playable_Specification.v1.md"),
                testDesignSha256 = FileSha(projectRoot, "Research/Gate11R_5pct_Scenario_Playable_Test_Design.v1.md"),
                generatorId = Gate11RFormalScenarioMatrixGenerator.GeneratorId,
                generatorSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Scenarios/Gate11RFormalScenarioMatrixGenerator.cs"),
                retainedGeneratorSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Scenarios/FormalScenarioMatrixGenerator.cs"),
                commandSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Editor/Gate11RScenarioPlayableBundleCommand.cs"),
                campaignProfileSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Visualization/Gate11RCampaignProfile.cs"),
                algorithmPresetSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Visualization/Gate11RAlgorithmPreset.cs"),
                sceneControllerSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Visualization/Gate11RPlayableSceneController.cs"),
                launcherSourceSha256 = FileSha(projectRoot, "Assets/_Scripts/Research/Visualization/Gate11RPlayableLauncher.cs"),
                matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId,
                preregistrationId = Gate11RFormalScenarioMatrixGenerator.PreregistrationId,
                playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId,
                executionDesignId = Gate11RFormalScenarioMatrixGenerator.ExecutionDesignId,
                precisionPolicyId = Gate11RFormalScenarioMatrixGenerator.PrecisionPolicyId,
                scenarioRoot = ScenarioRootRelative,
                playableCatalogRoot = PlayableCatalogRootRelative,
                playableAssetRoot = PlayableAssetRootRelative,
                scenarioCount = state.Scenarios.Count,
                campaignCount = state.Campaigns.Count,
                eligibilityCount = state.Presets.Count,
                sceneCount = state.Scenarios.Count,
                profileCount = state.Campaigns.Count,
                presetCount = state.Presets.Count,
                artifacts = artifacts.ToArray(),
                artifactAggregateSha256 = Sha256(StrictUtf8.GetBytes(aggregate.ToString())),
                visualizationOnly = true,
                timingEvidenceAllowed = false,
                pilotExecuted = false,
                formalCampaignExecuted = false
            };
        }

        private static List<ArtifactRecord> CollectStagedArtifacts(string projectRoot, string scenarioStage, string catalogStage, string assetStage)
        {
            List<ArtifactRecord> result = new List<ArtifactRecord>();
            CollectTree(result, scenarioStage, ScenarioRootRelative);
            CollectTree(result, catalogStage, PlayableCatalogRootRelative);
            CollectTree(result, assetStage, PlayableAssetRootRelative);
            return result;
        }

        private static void CollectTree(List<ArtifactRecord> rows, string stageRoot, string finalRelativeRoot)
        {
            string normalizedRoot = Path.GetFullPath(stageRoot).TrimEnd(Path.DirectorySeparatorChar);
            string[] files = Directory.GetFiles(normalizedRoot, "*", SearchOption.AllDirectories);
            Array.Sort(files, StringComparer.Ordinal);
            for (int index = 0; index < files.Length; index++)
            {
                string relative = files[index].Substring(normalizedRoot.Length).TrimStart(Path.DirectorySeparatorChar).Replace('\\', '/');
                byte[] bytes = File.ReadAllBytes(files[index]);
                rows.Add(new ArtifactRecord { relativePath = finalRelativeRoot + "/" + relative, rawBytes = bytes.LongLength, sha256 = Sha256(bytes) });
            }
        }

        private static void ValidateBlueprints(FormalScenarioBlueprint[] rows, ref int assertions)
        {
            Assert(rows.Length == 53, "Scenario count differs.", ref assertions);
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            int shared = 0;
            int heterogeneous = 0;
            for (int index = 0; index < rows.Length; index++)
            {
                FormalScenarioBlueprint row = rows[index];
                Assert(ids.Add(row.scenarioId), "Duplicate scenario id: " + row.scenarioId, ref assertions);
                Assert(row.randomSeed > 0 && row.gridWidth > 0 && row.gridHeight > 0 && row.agentCount > 0, "Invalid blueprint: " + row.scenarioId, ref assertions);
                if (row.IsSharedGoal) shared++; else heterogeneous++;
                DeterministicScenarioDefinition first = Gate11RFormalScenarioMatrixGenerator.GenerateDefinition(row);
                DeterministicScenarioDefinition second = Gate11RFormalScenarioMatrixGenerator.GenerateDefinition(row);
                string firstJson = DeterministicScenarioJson.SerializeCanonical(first.Resolve());
                string secondJson = DeterministicScenarioJson.SerializeCanonical(second.Resolve());
                Assert(firstJson == secondJson, "In-process regeneration differs: " + row.scenarioId, ref assertions);
            }
            Assert(shared == 32 && heterogeneous == 21, "Goal-structure scenario counts differ.", ref assertions);
        }

        private static void ValidateCampaignsAndPresets(BuildState state, ref int assertions)
        {
            Assert(state.Campaigns.Count == 74 && state.Presets.Count == 212, "Campaign/preset counts differ.", ref assertions);
            HashSet<string> campaignIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> cells = new HashSet<string>(StringComparer.Ordinal);
            Dictionary<string, int> perAlgorithm = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int index = 0; index < state.Campaigns.Count; index++)
            {
                CampaignRecord campaign = state.Campaigns[index];
                Assert(campaignIds.Add(campaign.campaignId), "Duplicate campaign id: " + campaign.campaignId, ref assertions);
                string[] expected = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(campaign.comparisonCohortId);
                Assert(SetEquals(expected, campaign.eligibleAlgorithmIds), "Campaign eligibility differs: " + campaign.campaignId, ref assertions);
            }
            for (int index = 0; index < state.Presets.Count; index++)
            {
                PresetRecord preset = state.Presets[index];
                Assert(campaignIds.Contains(preset.campaignId), "Preset campaign is unknown: " + preset.presetId, ref assertions);
                PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(preset.algorithmId, preset.comparisonCohortId);
                Assert(cells.Add(preset.matrixEntryId), "Duplicate eligibility cell: " + preset.matrixEntryId, ref assertions);
                int count;
                perAlgorithm.TryGetValue(preset.algorithmId, out count);
                perAlgorithm[preset.algorithmId] = count + 1;
            }
            for (int index = 0; index < SharedAlgorithms.Length; index++)
                Assert(perAlgorithm.ContainsKey(SharedAlgorithms[index]) && perAlgorithm[SharedAlgorithms[index]] == 53, "Algorithm coverage differs: " + SharedAlgorithms[index], ref assertions);
        }

        private static void ValidateWilliams(List<CampaignRecord> campaigns, ref int assertions)
        {
            for (int c = 0; c < campaigns.Count; c++)
            {
                CampaignRecord campaign = campaigns[c];
                int expectedRows = campaign.eligibleAlgorithmIds.Length == 4 ? 4 : 2;
                Assert(campaign.williamsRows.Length == expectedRows, "Williams row count differs: " + campaign.campaignId, ref assertions);
                int[] positions = new int[campaign.eligibleAlgorithmIds.Length];
                for (int rowIndex = 0; rowIndex < campaign.williamsRows.Length; rowIndex++)
                {
                    string[] row = campaign.williamsRows[rowIndex].algorithms;
                    Assert(SetEquals(row, campaign.eligibleAlgorithmIds), "Williams row is not a permutation: " + campaign.campaignId, ref assertions);
                    for (int position = 0; position < row.Length; position++)
                    {
                        int algorithm = Array.IndexOf(campaign.eligibleAlgorithmIds, row[position]);
                        positions[algorithm]++;
                    }
                }
                for (int index = 0; index < positions.Length; index++) Assert(positions[index] == expectedRows, "Williams coverage differs.", ref assertions);
            }
        }

        private static void ValidatePrecisionAndPreregistration(PreregistrationDocument value, BuildState state, ref int assertions)
        {
            Assert(Math.Abs(Math.Log(1.05d) - value.logRelativeHalfWidthTarget) < 1e-15d, "5% log precision differs.", ref assertions);
            Assert(value.minimumBlocks == 32 && value.blockMultiple == 4 && !value.hardCapEnabled, "Formal block policy differs.", ref assertions);
            Assert(value.primaryAnalysisIds.Length == 4 && value.secondaryAnalysisIds.Length == 5, "Preregistered analysis rows differ.", ref assertions);
            Assert(value.pilotCampaignAnchors.Length == 12, "Pilot campaign anchor count differs.", ref assertions);
            for (int index = 0; index < value.pilotCampaignAnchors.Length; index++) Assert(FindCampaign(state, value.pilotCampaignAnchors[index]) != null, "Pilot anchor is not eligible.", ref assertions);
            Assert(!value.pilotExecuted && !value.formalCampaignExecuted, "Execution flags differ.", ref assertions);
        }

        private static void RunNegativeUnitTests(BuildState state, ref int assertions)
        {
            Assert(!SetEquals(new[] { NavigationAlgorithmIds.AStarRepeated }, SharedAlgorithms), "Incomplete shared eligibility was accepted.", ref assertions);
            Assert(!IsSafeRelativePath("../escape"), "Path escape was accepted.", ref assertions);
            Assert(!IsSafeRelativePath("Research/FormalScenarios/v1"), "Historical root was accepted as a target.", ref assertions);
            Assert(!IsSafeRelativePath("Assets/_Scenes/../Original.unity"), "Asset path escape was accepted.", ref assertions);
            Assert(FindCampaign(state, "unknown") == null, "Unknown campaign was accepted.", ref assertions);
            bool rejected = false;
            try { PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(NavigationAlgorithmIds.AStarRepeated, PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort); }
            catch (InvalidOperationException) { rejected = true; }
            Assert(rejected, "Ineligible grouped-field algorithm was accepted.", ref assertions);
            Assert(Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark.Contains("NOT A TIMING RUN"), "Visualization watermark differs.", ref assertions);
            Assert(Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId == "research-visual-direction-glyph-v1", "Direction glyph id differs.", ref assertions);
            Assert(!File.Exists(Full(Directory.GetParent(Application.dataPath).FullName, "Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1")), "Gate 12R root exists during Gate 11R unit tests.", ref assertions);
            Assert(!File.Exists(Full(Directory.GetParent(Application.dataPath).FullName, "Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1")), "Gate 13R root exists during Gate 11R unit tests.", ref assertions);
        }

        private static void VerifyHeadersAndCounts(BundleManifest manifest, MatrixDocument matrix, ScenarioCatalogDocument catalog, PreregistrationDocument preregistration,
            PlayableSceneCatalogDocument sceneCatalog, CampaignCatalogDocument campaignCatalog, PresetCatalogDocument presetCatalog, CoverageDocument coverage, ref int assertions)
        {
            Assert(manifest != null && manifest.manifestId == "gate11r-scenario-playable-bundle-manifest-v1", "Manifest identity differs.", ref assertions);
            Assert(manifest.specificationId == Gate11RFormalScenarioMatrixGenerator.SpecificationId && manifest.matrixId == Gate11RFormalScenarioMatrixGenerator.MatrixId, "Manifest design identity differs.", ref assertions);
            Assert(manifest.scenarioCount == 53 && manifest.campaignCount == 74 && manifest.eligibilityCount == 212 && manifest.sceneCount == 53 && manifest.profileCount == 74 && manifest.presetCount == 212, "Manifest counts differ.", ref assertions);
            Assert(matrix.scenarioCount == 53 && matrix.campaignCount == 74 && matrix.eligibilityCount == 212, "Matrix counts differ.", ref assertions);
            Assert(catalog.scenarioCount == 53 && sceneCatalog.sceneCount == 53 && campaignCatalog.campaignCount == 74 && presetCatalog.presetCount == 212, "Catalog counts differ.", ref assertions);
            Assert(coverage.scenarioCount == 53 && coverage.campaignCount == 74 && coverage.presetCount == 212, "Coverage counts differ.", ref assertions);
            Assert(!manifest.pilotExecuted && !manifest.formalCampaignExecuted && !coverage.pilotExecuted && !coverage.formalCampaignExecuted, "A downstream execution flag is true.", ref assertions);
            Assert(manifest.visualizationOnly && !manifest.timingEvidenceAllowed && coverage.visualizationOnly && !coverage.timingEvidenceAllowed, "Visualization isolation flags differ.", ref assertions);
            BuildState state = new BuildState();
            state.Campaigns.AddRange(campaignCatalog.campaigns);
            ValidatePrecisionAndPreregistration(preregistration, state, ref assertions);
        }

        private static void VerifyManifestArtifacts(string projectRoot, BundleManifest manifest, ref int assertions)
        {
            Assert(manifest.artifacts != null && manifest.artifacts.Length > 0, "Manifest artifact list is empty.", ref assertions);
            StringBuilder aggregate = new StringBuilder();
            string previous = null;
            for (int index = 0; index < manifest.artifacts.Length; index++)
            {
                ArtifactRecord row = manifest.artifacts[index];
                Assert(previous == null || string.CompareOrdinal(previous, row.relativePath) < 0, "Artifact paths are not unique ordinal order.", ref assertions);
                previous = row.relativePath;
                string path = Full(projectRoot, row.relativePath);
                Assert(File.Exists(path), "Manifest artifact is missing: " + row.relativePath, ref assertions);
                byte[] bytes = File.ReadAllBytes(path);
                Assert(bytes.LongLength == row.rawBytes && Sha256(bytes) == row.sha256, "Manifest artifact identity differs: " + row.relativePath, ref assertions);
                aggregate.Append(row.relativePath).Append('\t').Append(row.rawBytes).Append('\t').Append(row.sha256).Append('\n');
            }
            Assert(Sha256(StrictUtf8.GetBytes(aggregate.ToString())) == manifest.artifactAggregateSha256, "Artifact aggregate differs.", ref assertions);
        }

        private static void VerifyScenarios(string projectRoot, ScenarioRecord[] rows, Dictionary<string, FormalScenarioBlueprint> blueprints, ref int assertions)
        {
            Assert(rows != null && rows.Length == 53, "Scenario record count differs.", ref assertions);
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < rows.Length; index++)
            {
                ScenarioRecord row = rows[index];
                Assert(ids.Add(row.scenarioId) && blueprints.ContainsKey(row.scenarioId), "Scenario identity is unknown or duplicate.", ref assertions);
                byte[] disk = File.ReadAllBytes(Full(projectRoot, row.scenarioRelativePath));
                DeterministicScenarioDefinition generated = Gate11RFormalScenarioMatrixGenerator.GenerateDefinition(blueprints[row.scenarioId]);
                ResolvedDeterministicScenario resolved = generated.Resolve();
                byte[] expected = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(resolved));
                Assert(BytesEqual(disk, expected), "Separate-process scenario regeneration differs: " + row.scenarioId, ref assertions);
                Assert(Sha256(disk) == row.scenarioSha256 && resolved.FingerprintSha256 == row.scenarioFingerprintSha256, "Scenario hash/fingerprint differs: " + row.scenarioId, ref assertions);
                Assert(row.randomSeed == blueprints[row.scenarioId].randomSeed && row.agentCount == blueprints[row.scenarioId].agentCount && row.distinctGoalCount == blueprints[row.scenarioId].distinctGoalCount, "Scenario metadata differs.", ref assertions);
            }
        }

        private static void VerifyCampaignProfiles(CampaignRecord[] rows, ref int assertions)
        {
            Assert(rows != null && rows.Length == 74, "Campaign profile count differs.", ref assertions);
            for (int index = 0; index < rows.Length; index++)
            {
                CampaignRecord row = rows[index];
                Gate11RCampaignProfile asset = AssetDatabase.LoadAssetAtPath<Gate11RCampaignProfile>(row.profileAssetPath);
                Assert(asset != null, "Campaign profile asset is missing: " + row.campaignId, ref assertions);
                Assert(asset.campaignId == row.campaignId && asset.scenarioId == row.scenarioId && asset.comparisonCohortId == row.comparisonCohortId, "Campaign profile fields differ.", ref assertions);
                Assert(asset.scenarioSha256 == row.scenarioSha256 && asset.sceneAssetPath == row.sceneAssetPath, "Campaign profile bindings differ.", ref assertions);
                Assert(SetEquals(asset.eligibleAlgorithmIds, row.eligibleAlgorithmIds) && asset.williamsRows.Length == row.williamsRows.Length, "Campaign profile eligibility/Williams fields differ.", ref assertions);
                Assert(asset.visualizationOnly && !asset.timingEvidenceAllowed, "Campaign profile timing isolation differs.", ref assertions);
                Assert(AssetDatabase.AssetPathToGUID(row.profileAssetPath) == row.profileAssetGuid, "Campaign profile GUID differs.", ref assertions);
                Assert(Sha256(File.ReadAllBytes(Full(Directory.GetParent(Application.dataPath).FullName, row.profileAssetPath))) == row.profileSha256, "Campaign profile bytes differ.", ref assertions);
            }
        }

        private static void VerifyAlgorithmPresets(PresetRecord[] rows, ref int assertions)
        {
            Assert(rows != null && rows.Length == 212, "Algorithm preset count differs.", ref assertions);
            for (int index = 0; index < rows.Length; index++)
            {
                PresetRecord row = rows[index];
                Gate11RAlgorithmPreset asset = AssetDatabase.LoadAssetAtPath<Gate11RAlgorithmPreset>(row.presetAssetPath);
                Assert(asset != null, "Algorithm preset is missing: " + row.presetId, ref assertions);
                Assert(asset.presetId == row.presetId && asset.matrixEntryId == row.matrixEntryId && asset.algorithmId == row.algorithmId, "Algorithm preset identity differs.", ref assertions);
                Assert(asset.campaignId == row.campaignId && asset.scenarioId == row.scenarioId && asset.sceneAssetPath == row.sceneAssetPath, "Algorithm preset bindings differ.", ref assertions);
                Assert(asset.directionGlyphId == Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId && asset.watermark == Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark, "Algorithm preset visual contract differs.", ref assertions);
                Assert(asset.visualizationOnly && !asset.timingEvidenceAllowed, "Algorithm preset timing isolation differs.", ref assertions);
                Assert(AssetDatabase.AssetPathToGUID(row.presetAssetPath) == row.presetAssetGuid, "Algorithm preset GUID differs.", ref assertions);
            }
        }

        private static void VerifyScenes(ScenarioRecord[] rows, CoverageDocument coverage, ref int assertions)
        {
            for (int index = 0; index < rows.Length; index++)
            {
                Scene scene = EditorSceneManager.OpenScene(rows[index].sceneAssetPath, OpenSceneMode.Single);
                Gate11RPlayableSceneController[] controllers = UnityEngine.Object.FindObjectsOfType<Gate11RPlayableSceneController>(true);
                Assert(scene.IsValid() && controllers.Length == 1, "Playable scene controller count differs: " + rows[index].scenarioId, ref assertions);
                Gate11RPlayableSceneController controller = controllers[0];
                Assert(controller.scenarioId == rows[index].scenarioId && controller.scenarioRelativePath == rows[index].scenarioRelativePath && controller.scenarioSha256 == rows[index].scenarioSha256, "Playable scene binding differs.", ref assertions);
                Assert(controller.directionGlyphId == Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId && controller.watermark == Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark, "Playable scene visual contract differs.", ref assertions);
                Assert(controller.visualizationOnly && !controller.timingEvidenceAllowed, "Playable scene timing isolation differs.", ref assertions);
                Assert(UnityEngine.Object.FindObjectsOfType<Camera>(true).Length == 1, "Playable scene camera count differs.", ref assertions);
                Assert(AssetDatabase.AssetPathToGUID(rows[index].sceneAssetPath) == rows[index].sceneAssetGuid, "Playable scene GUID differs.", ref assertions);
            }
            Scene launcherScene = EditorSceneManager.OpenScene(coverage.launcherSceneAssetPath, OpenSceneMode.Single);
            Gate11RPlayableLauncher[] launchers = UnityEngine.Object.FindObjectsOfType<Gate11RPlayableLauncher>(true);
            Assert(launcherScene.IsValid() && launchers.Length == 1 && launchers[0].IsShapeValid(), "Playable launcher is invalid.", ref assertions);
            Assert(AssetDatabase.AssetPathToGUID(coverage.launcherSceneAssetPath) == coverage.launcherSceneAssetGuid, "Launcher GUID differs.", ref assertions);
        }

        private static int VerifyPlannerInitialization(string projectRoot, List<PresetRecord> presets, ref int assertions)
        {
            Dictionary<string, LoadedDeterministicScenario> cache = new Dictionary<string, LoadedDeterministicScenario>(StringComparer.Ordinal);
            int count = 0;
            for (int index = 0; index < presets.Count; index++)
            {
                PresetRecord preset = presets[index];
                LoadedDeterministicScenario loaded;
                if (!cache.TryGetValue(preset.scenarioId, out loaded))
                {
                    Gate11RAlgorithmPreset asset = AssetDatabase.LoadAssetAtPath<Gate11RAlgorithmPreset>(preset.presetAssetPath);
                    loaded = DeterministicScenarioJson.LoadFromFile(Full(projectRoot, asset.scenarioRelativePath));
                    cache.Add(preset.scenarioId, loaded);
                }
                ResolvedDeterministicScenario scenario = loaded.Resolved;
                DDM.Research.Grid.ResearchNavigationGrid grid = scenario.CreateGrid();
                INavigationPlanner planner = CreatePlanner(preset.algorithmId);
                NavigationOperationMetrics metrics = planner.Initialize(grid, new NavigationPlannerInitialization
                {
                    runId = "gate11r-validation-" + index,
                    goalSetId = scenario.GoalSetId,
                    goals = CopyGoals(scenario.Goals),
                    connectivity = scenario.Connectivity,
                    allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                    budgetMilliseconds = scenario.InitializationBudgetMilliseconds
                });
                Assert(metrics != null && planner.GridVersion == grid.Version, "Planner initialization failed: " + preset.matrixEntryId, ref assertions);
                planner.Reset();
                count++;
            }
            Assert(count == 212, "Planner initialization coverage differs.", ref assertions);
            return count;
        }

        private static int RunVerificationNegativeTests(BuildState state, BundleManifest manifest, ref int assertions)
        {
            int count = 0;
            ScenarioRecord scenario = state.Scenarios[0];
            Assert(!string.Equals(scenario.scenarioSha256, MutateHash(scenario.scenarioSha256), StringComparison.Ordinal), "Mutated scenario hash was accepted.", ref assertions); count++;
            Assert(FindCampaign(state, "unknown-campaign") == null, "Unknown campaign was accepted.", ref assertions); count++;
            Assert(!SetEquals(new[] { NavigationAlgorithmIds.AStarRepeated }, FindCampaign(state, state.Campaigns[0].campaignId).eligibleAlgorithmIds), "Incomplete eligibility was accepted.", ref assertions); count++;
            Assert(!IsSafeRelativePath("../outside"), "Path escape was accepted.", ref assertions); count++;
            Assert(!IsSafeRelativePath("Research/FormalScenarios/v1"), "Historical root target was accepted.", ref assertions); count++;
            Assert(!manifest.timingEvidenceAllowed && manifest.visualizationOnly, "Timing isolation mutation would be accepted.", ref assertions); count++;
            Assert(manifest.executionDesignId == Gate11RFormalScenarioMatrixGenerator.ExecutionDesignId, "Wrong execution design was accepted.", ref assertions); count++;
            Assert(manifest.precisionPolicyId == Gate11RFormalScenarioMatrixGenerator.PrecisionPolicyId, "Wrong precision policy was accepted.", ref assertions); count++;
            Assert(Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark == "VISUALIZATION REPLAY — NOT A TIMING RUN", "Wrong watermark was accepted.", ref assertions); count++;
            Assert(Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId == "research-visual-direction-glyph-v1", "Wrong glyph was accepted.", ref assertions); count++;
            return count;
        }

        private static void VerifyTimingIsolation(string projectRoot, ref int assertions)
        {
            string[] timingSources =
            {
                "Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs",
                "Assets/_Scripts/Research/Editor/ResearchPlanningProcessReuseBatchCommandV2.cs"
            };
            for (int index = 0; index < timingSources.Length; index++)
            {
                string text = File.ReadAllText(Full(projectRoot, timingSources[index]));
                Assert(text.IndexOf("Assets/_Scenes/Research/Playable/Gate11R_5pct", StringComparison.Ordinal) < 0, "Timing runner references the Playable asset root.", ref assertions);
                Assert(text.IndexOf("Gate11RPlayable", StringComparison.Ordinal) < 0, "Timing runner references a Playable component.", ref assertions);
            }
        }

        private static void AssertStagedCoverage(BuildState state, string scenarioStage, string catalogStage, string assetStage, ref int assertions)
        {
            Assert(Directory.GetFiles(Path.Combine(scenarioStage, ScenarioDirectoryName), "*.scenario.json").Length == 53, "Staged scenario count differs.", ref assertions);
            Assert(Directory.GetFiles(Path.Combine(assetStage, "Scenarios"), "*.unity").Length == 53, "Staged scene count differs.", ref assertions);
            Assert(Directory.GetFiles(Path.Combine(assetStage, "CampaignProfiles"), "*.asset").Length == 74, "Staged profile count differs.", ref assertions);
            Assert(Directory.GetFiles(Path.Combine(assetStage, "AlgorithmPresets"), "*.asset").Length == 212, "Staged preset count differs.", ref assertions);
            Assert(File.Exists(Path.Combine(assetStage, "Launcher", "Gate11R_Playable_Launcher.unity")), "Staged launcher is missing.", ref assertions);
            Assert(Directory.GetFiles(catalogStage, "*.json").Length == 4, "Staged Playable catalog count differs.", ref assertions);
        }

        private static void ValidatePromotedAssetGuids(BuildState state, ref int assertions)
        {
            for (int index = 0; index < state.Scenarios.Count; index++) Assert(AssetDatabase.AssetPathToGUID(state.Scenarios[index].sceneAssetPath) == state.Scenarios[index].sceneAssetGuid, "Scene GUID changed during promotion.", ref assertions);
            for (int index = 0; index < state.Campaigns.Count; index++) Assert(AssetDatabase.AssetPathToGUID(state.Campaigns[index].profileAssetPath) == state.Campaigns[index].profileAssetGuid, "Profile GUID changed during promotion.", ref assertions);
            for (int index = 0; index < state.Presets.Count; index++) Assert(AssetDatabase.AssetPathToGUID(state.Presets[index].presetAssetPath) == state.Presets[index].presetAssetGuid, "Preset GUID changed during promotion.", ref assertions);
            Assert(AssetDatabase.AssetPathToGUID(state.LauncherAssetPath) == state.LauncherGuid, "Launcher GUID changed during promotion.", ref assertions);
        }

        private static string BuildCoverageGraph(BuildState state)
        {
            List<string> rows = new List<string>();
            for (int index = 0; index < state.Presets.Count; index++)
            {
                PresetRecord row = state.Presets[index];
                rows.Add(row.presetId + "\t" + row.campaignId + "\t" + row.scenarioId + "\t" + row.algorithmId + "\t" + row.sceneAssetPath + "\t" + row.profileAssetPath + "\t" + row.presetAssetPath);
            }
            rows.Sort(StringComparer.Ordinal);
            return string.Join("\n", rows.ToArray()) + "\n";
        }

        private static Dictionary<string, FormalScenarioBlueprint> IndexBlueprints(FormalScenarioBlueprint[] rows)
        {
            Dictionary<string, FormalScenarioBlueprint> result = new Dictionary<string, FormalScenarioBlueprint>(StringComparer.Ordinal);
            for (int index = 0; index < rows.Length; index++) result.Add(rows[index].scenarioId, rows[index]);
            return result;
        }

        private static ScenarioRecord FindScenario(BuildState state, string scenarioId)
        {
            for (int index = 0; index < state.Scenarios.Count; index++) if (state.Scenarios[index].scenarioId == scenarioId) return state.Scenarios[index];
            return null;
        }

        private static CampaignRecord FindCampaign(BuildState state, string campaignId)
        {
            for (int index = 0; index < state.Campaigns.Count; index++) if (state.Campaigns[index].campaignId == campaignId) return state.Campaigns[index];
            return null;
        }

        private static WilliamsRow[] ToWilliamsRows(string[][] rows)
        {
            WilliamsRow[] result = new WilliamsRow[rows.Length];
            for (int index = 0; index < rows.Length; index++) result[index] = new WilliamsRow { rowIndex = index, algorithms = (string[])rows[index].Clone() };
            return result;
        }

        private static string[] WilliamsStrings(WilliamsRow[] rows)
        {
            string[] result = new string[rows.Length];
            for (int index = 0; index < rows.Length; index++) result[index] = string.Join("|", rows[index].algorithms);
            return result;
        }

        private static string[] AlgorithmsForScenario(ScenarioRecord scenario)
        {
            return scenario.goalStructureId == FormalScenarioMatrixGenerator.SharedGoalStructureId
                ? (string[])SharedAlgorithms.Clone()
                : new[] { NavigationAlgorithmIds.AStarRepeated, NavigationAlgorithmIds.DStarLite, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, NavigationAlgorithmIds.IncrementalDynamicFlowField };
        }

        private static bool IsPilotAnchor(string campaignId)
        {
            string[] anchors =
            {
                "core-r01-s1-shared--shared", "core-r07-s2-shared--shared", "grid-scale-g256-shared--shared",
                "agent-scale-a512-shared--shared", "dynamic-footprint-f225-shared--shared", "reachability-c8-strict-shared--shared",
                "core-r01-s1-hetero--per-agent", "core-r01-s1-hetero--grouped-field",
                "core-r07-s2-hetero--per-agent", "core-r07-s2-hetero--grouped-field",
                "goal-count-g32-hetero--per-agent", "goal-count-g32-hetero--grouped-field"
            };
            return Array.IndexOf(anchors, campaignId) >= 0;
        }

        private static string AlgorithmSlug(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return "astar-r";
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return "dstar-l";
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return "cff";
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return "idff";
            throw new ArgumentOutOfRangeException("algorithmId");
        }

        private static string ToStagingAssetPath(string finalPath)
        {
            if (!finalPath.StartsWith(PlayableAssetRootRelative + "/", StringComparison.Ordinal)) throw new InvalidOperationException("Asset path is outside the Gate 11R root.");
            return AssetStagingRelative + finalPath.Substring(PlayableAssetRootRelative.Length);
        }

        private static void EnsureAssetFolder(string assetPath)
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            Directory.CreateDirectory(Full(projectRoot, assetPath));
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
        }

        private static void PromoteResearchDirectory(string source, string destination)
        {
            if (Directory.Exists(destination) || File.Exists(destination)) throw new IOException("Create-new destination already exists: " + destination);
            Directory.Move(source, destination);
        }

        private static void AssertProductionRootsAbsent(string projectRoot, ref int assertions)
        {
            foreach (string relative in new[] { ScenarioRootRelative, PlayableCatalogRootRelative, PlayableAssetRootRelative })
                Assert(!Directory.Exists(Full(projectRoot, relative)) && !File.Exists(Full(projectRoot, relative)), "Create-new Gate 11R root already exists: " + relative, ref assertions);
            Assert(!Directory.Exists(Full(projectRoot, "Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1")), "Gate 12R root exists.", ref assertions);
            Assert(!Directory.Exists(Full(projectRoot, "Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1")), "Gate 13R root exists.", ref assertions);
        }

        private static void AssertProductionRootsPresent(string projectRoot, ref int assertions)
        {
            foreach (string relative in new[] { ScenarioRootRelative, PlayableCatalogRootRelative, PlayableAssetRootRelative })
                Assert(Directory.Exists(Full(projectRoot, relative)), "Gate 11R production root is missing: " + relative, ref assertions);
            Assert(!Directory.Exists(Full(projectRoot, "Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1")), "Gate 12R root exists.", ref assertions);
            Assert(!Directory.Exists(Full(projectRoot, "Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1")), "Gate 13R root exists.", ref assertions);
        }

        private static void SetCounts(CommandResult result, BuildState state, FormalScenarioBlueprint[] blueprints)
        {
            int shared = 0;
            for (int index = 0; index < blueprints.Length; index++) if (blueprints[index].IsSharedGoal) shared++;
            result.scenarioCount = state.Scenarios.Count;
            result.sharedScenarioCount = shared;
            result.heterogeneousScenarioCount = blueprints.Length - shared;
            result.campaignCount = state.Campaigns.Count;
            result.eligibilityCount = state.Presets.Count;
            result.sceneCount = state.Scenarios.Count;
            result.profileCount = state.Campaigns.Count;
            result.presetCount = state.Presets.Count;
        }

        private static Dictionary<string, string> SnapshotProductionFiles(string projectRoot)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (string root in new[] { ScenarioRootRelative, PlayableCatalogRootRelative, PlayableAssetRootRelative })
            {
                string fullRoot = Full(projectRoot, root).TrimEnd(Path.DirectorySeparatorChar);
                string[] files = Directory.GetFiles(fullRoot, "*", SearchOption.AllDirectories);
                for (int index = 0; index < files.Length; index++)
                {
                    string relative = root + "/" + files[index].Substring(fullRoot.Length).TrimStart(Path.DirectorySeparatorChar).Replace('\\', '/');
                    result.Add(relative, Sha256(File.ReadAllBytes(files[index])));
                }
            }
            return result;
        }

        private static bool SnapshotsEqual(Dictionary<string, string> left, Dictionary<string, string> right)
        {
            if (left.Count != right.Count) return false;
            foreach (KeyValuePair<string, string> pair in left)
            {
                string value;
                if (!right.TryGetValue(pair.Key, out value) || value != pair.Value) return false;
            }
            return true;
        }

        private static bool SetEquals(string[] left, string[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            HashSet<string> set = new HashSet<string>(left, StringComparer.Ordinal);
            return set.Count == left.Length && set.SetEquals(right);
        }

        private static bool IsSafeRelativePath(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path) || path.Contains("..")) return false;
            string normalized = path.Replace('\\', '/');
            if (normalized.StartsWith("Research/FormalScenarios/v1", StringComparison.Ordinal)) return false;
            return true;
        }

        private static string MutateHash(string value)
        {
            return (value[0] == '0' ? "1" : "0") + value.Substring(1);
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new ArgumentOutOfRangeException("algorithmId");
        }

        private static GridCoordinate[] CopyGoals(IReadOnlyList<GridCoordinate> goals)
        {
            GridCoordinate[] result = new GridCoordinate[goals.Count];
            for (int index = 0; index < result.Length; index++) result[index] = goals[index];
            return result;
        }

        private static string FileSha(string projectRoot, string relativePath)
        {
            return Sha256(File.ReadAllBytes(Full(projectRoot, relativePath)));
        }

        private static T LoadJson<T>(string path) where T : class
        {
            T value = JsonUtility.FromJson<T>(StrictUtf8.GetString(File.ReadAllBytes(path)));
            if (value == null) throw new InvalidDataException("JSON did not deserialize: " + path);
            return value;
        }

        private static void WriteJsonCreateNew<T>(string path, T value)
        {
            WriteCreateNew(path, SerializeJson(value));
        }

        private static void WriteJsonReplace<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            File.WriteAllBytes(path, SerializeJson(value));
        }

        private static byte[] SerializeJson<T>(T value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            return StrictUtf8.GetBytes(json);
        }

        private static void WriteCreateNew(string path, byte[] bytes)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }
        }

        private static string Full(string projectRoot, string relativePath)
        {
            return Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static string Sha256(byte[] bytes)
        {
            SHA256 sha = SHA256.Create();
            try { return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", string.Empty).ToLowerInvariant(); }
            finally { sha.Dispose(); }
        }

        private static bool BytesEqual(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            for (int index = 0; index < left.Length; index++) if (left[index] != right[index]) return false;
            return true;
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            assertions++;
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
