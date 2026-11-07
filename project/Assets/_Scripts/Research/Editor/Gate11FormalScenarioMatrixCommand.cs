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
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Gate 11 is an input-materialization gate. Generate writes a create-new
    /// bundle; Verify is read-only and never executes Plan or ApplyChanges.
    /// </summary>
    public static class Gate11FormalScenarioMatrixCommand
    {
        private const string BundleRelativePath = "Research/FormalScenarios/v1";
        private const string ScenarioDirectoryName = "Scenarios";
        private const string MatrixFileName = "formal-scenario-matrix.json";
        private const string PreregistrationFileName = "preregistered-analysis.json";
        private const string CatalogFileName = "catalog.json";
        private const string ManifestFileName = "bundle-manifest.json";
        private const string SpecificationRelativePath = "Research/Formal_Scenario_Matrix_and_Preregistration_Specification.md";
        private const string TestDesignRelativePath = "Research/Gate11_Formal_Scenario_Matrix_Test_Design.md";
        private const string GeneratorSourceRelativePath = "Assets/_Scripts/Research/Scenarios/FormalScenarioMatrixGenerator.cs";
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);

        [Serializable]
        private sealed class Gate11Result
        {
            public bool passed;
            public string mode;
            public int assertionCount;
            public int scenarioCount;
            public int eligibilityCount;
            public int sharedScenarioCount;
            public int heterogeneousScenarioCount;
            public int plannerInitializationCount;
            public int reachabilityPhaseCount;
            public int negativeTestCount;
            public bool secondGenerationRefused;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
            public string outputDirectory;
            public string manifestPath;
            public string manifestSha256;
            public string bundleAggregateSha256;
            public string error;
        }

        [Serializable]
        private sealed class MatrixConfiguration
        {
            public int schemaVersion;
            public string specificationId;
            public string generatorId;
            public string preregistrationId;
            public int scenarioCount;
            public int eligibilityCount;
            public MatrixScenarioRecord[] scenarios;
            public EligibilityRecord[] eligibilityEntries;
        }

        [Serializable]
        private sealed class MatrixScenarioRecord
        {
            public string scenarioId;
            public string relativePath;
            public string familyId;
            public int structuralRow;
            public int seedReplication;
            public int randomSeed;
            public int gridWidth;
            public int gridHeight;
            public int connectivity;
            public bool allowDiagonalCornerCutting;
            public string terrainModeId;
            public double targetObstacleDensity;
            public int targetObstacleCount;
            public int agentCount;
            public int dynamicFootprint;
            public string goalStructureId;
            public int distinctGoalCount;
            public string dynamicProfileId;
            public string levelId;
            public string sourceSha256;
            public string canonicalSha256;
            public string fingerprintSha256;
            public long byteCount;
            public string[] comparisonCohorts;
        }

        [Serializable]
        private sealed class EligibilityRecord
        {
            public string matrixEntryId;
            public string scenarioId;
            public string scenarioRelativePath;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string comparisonCohortId;
            public string algorithmId;
        }

        [Serializable]
        private sealed class CatalogConfiguration
        {
            public int schemaVersion;
            public string specificationId;
            public string generatorId;
            public int scenarioCount;
            public CatalogEntry[] scenarios;
        }

        [Serializable]
        private sealed class CatalogEntry
        {
            public string scenarioId;
            public string relativePath;
            public string familyId;
            public int randomSeed;
            public int width;
            public int height;
            public int initialObstacleCount;
            public double realizedObstacleDensity;
            public int agentCount;
            public int distinctGoalCount;
            public int scheduledEventCount;
            public string sourceSha256;
            public string canonicalSha256;
            public string fingerprintSha256;
            public long byteCount;
        }

        [Serializable]
        private sealed class PreregistrationConfiguration
        {
            public int schemaVersion;
            public string preregistrationId;
            public string specificationId;
            public string primaryEndpointId;
            public string timingTransform;
            public string effectScale;
            public string confidenceInterval;
            public AnalysisRow[] analysisRows;
            public string outlierPolicyId;
            public string algorithmicFailurePolicyId;
            public string technicalInvalidityPolicyId;
            public string replacementPolicyId;
            public string amendmentPolicyId;
            public string gate12PrecisionFormula;
            public int gate12MinimumPerAlgorithm;
            public int gate12MaximumPerAlgorithm;
            public int gate12CycleMultiple;
            public string formalSampleSizeStatus;
            public bool significanceEarlyStoppingAllowed;
            public bool trendEarlyStoppingAllowed;
            public string[] environmentPreflightRequirements;
        }

        [Serializable]
        private sealed class AnalysisRow
        {
            public string analysisId;
            public string scenarioSelector;
            public string comparisonCohortId;
            public string contrastOrModel;
            public string endpointId;
            public string unit;
            public string classification;
            public string multiplicityFamily;
            public bool twoSided;
            public double alpha;
        }

        [Serializable]
        private sealed class BundleManifest
        {
            public int schemaVersion;
            public string specificationId;
            public string specificationRelativePath;
            public string specificationSha256;
            public string testDesignRelativePath;
            public string testDesignSha256;
            public string generatorId;
            public string generatorSourceRelativePath;
            public string generatorSourceSha256;
            public string preregistrationId;
            public string fairnessProtocolId;
            public string fairnessProtocolRelativePath;
            public string fairnessProtocolSha256;
            public string workloadSpecificationId;
            public string workloadSpecificationRelativePath;
            public string workloadSpecificationSha256;
            public int scenarioCount;
            public int eligibilityCount;
            public bool pilotExecuted;
            public bool formalCampaignExecuted;
            public ArtifactRecord[] artifacts;
            public ManifestScenarioRecord[] scenarios;
            public string bundleAggregateSha256;
        }

        [Serializable]
        private sealed class ArtifactRecord
        {
            public string relativePath;
            public string sha256;
            public long byteCount;
        }

        [Serializable]
        private sealed class ManifestScenarioRecord
        {
            public string scenarioId;
            public string relativePath;
            public string sourceSha256;
            public string canonicalSha256;
            public string fingerprintSha256;
            public long byteCount;
        }

        private sealed class GeneratedRecord
        {
            public FormalScenarioBlueprint Blueprint;
            public ResolvedDeterministicScenario Scenario;
            public string RelativePath;
            public string SourceSha256;
            public string FingerprintSha256;
            public long ByteCount;
            public int InitialObstacleCount;
        }

        private sealed class GridState
        {
            public bool[,] Walkable;
            public float[,] Costs;
            public int Width;
            public int Height;

            public GridState(int width, int height)
            {
                Width = width;
                Height = height;
                Walkable = new bool[width, height];
                Costs = new float[width, height];
            }
        }

        public static void Generate()
        {
            Run("generate");
        }

        public static void Verify()
        {
            Run("verify");
        }

        private static void Run(string mode)
        {
            string projectPath = Directory.GetParent(Application.dataPath).FullName;
            string resultPath = Path.Combine(projectPath, "Research", "Verification",
                mode == "generate" ? "Gate11_ScenarioMatrixGeneration.json" : "Gate11_ScenarioMatrixVerification.json");
            Gate11Result result = new Gate11Result
            {
                mode = mode,
                outputDirectory = Path.Combine(projectPath, BundleRelativePath.Replace('/', Path.DirectorySeparatorChar)),
                manifestPath = Path.Combine(projectPath, BundleRelativePath.Replace('/', Path.DirectorySeparatorChar), ManifestFileName),
                pilotExecuted = false,
                formalCampaignExecuted = false,
                error = string.Empty
            };
            try
            {
                int assertions = 0;
                if (mode == "generate") GenerateBundle(projectPath, result, ref assertions);
                else VerifyBundle(projectPath, result, ref assertions);
                result.assertionCount = assertions;
                result.passed = true;
                WriteResult(resultPath, result);
                Debug.Log("Gate 11 scenario matrix " + mode + " passed with " + assertions + " assertions.");
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

        private static void GenerateBundle(string projectPath, Gate11Result result, ref int assertions)
        {
            string bundlePath = Path.Combine(projectPath, BundleRelativePath.Replace('/', Path.DirectorySeparatorChar));
            AssertOutputDirectoryEmpty(bundlePath, ref assertions);
            Directory.CreateDirectory(bundlePath);
            string scenarioDirectory = Path.Combine(bundlePath, ScenarioDirectoryName);
            Directory.CreateDirectory(scenarioDirectory);

            FormalScenarioBlueprint[] blueprints = FormalScenarioMatrixGenerator.BuildBlueprints();
            Assert(blueprints.Length == FormalScenarioMatrixGenerator.ExpectedScenarioCount, "Frozen scenario count differs.", ref assertions);
            ValidateBlueprintIdentities(blueprints, ref assertions);

            List<GeneratedRecord> generated = new List<GeneratedRecord>(blueprints.Length);
            List<ArtifactRecord> artifacts = new List<ArtifactRecord>();
            for (int index = 0; index < blueprints.Length; index++)
            {
                FormalScenarioBlueprint blueprint = blueprints[index];
                DeterministicScenarioDefinition definition = FormalScenarioMatrixGenerator.GenerateDefinition(blueprint);
                ResolvedDeterministicScenario scenario = definition.Resolve();
                string canonical = DeterministicScenarioJson.SerializeCanonical(scenario);
                byte[] bytes = StrictUtf8.GetBytes(canonical);
                Assert(bytes.Length <= DeterministicScenarioJson.MaximumUtf8Bytes, "Generated scenario exceeds the strict input boundary: " + blueprint.scenarioId, ref assertions);
                string relativePath = ScenarioDirectoryName + "/" + blueprint.scenarioId + ".scenario.json";
                string fullPath = Path.Combine(bundlePath, relativePath.Replace('/', Path.DirectorySeparatorChar));
                WriteBytesCreateNew(fullPath, bytes);
                string hash = Sha256(bytes);
                int obstacleCount = CountInitialObstacles(scenario);
                GeneratedRecord record = new GeneratedRecord
                {
                    Blueprint = blueprint,
                    Scenario = scenario,
                    RelativePath = relativePath,
                    SourceSha256 = hash,
                    FingerprintSha256 = scenario.FingerprintSha256,
                    ByteCount = bytes.LongLength,
                    InitialObstacleCount = obstacleCount
                };
                generated.Add(record);
                artifacts.Add(new ArtifactRecord { relativePath = relativePath, sha256 = hash, byteCount = bytes.LongLength });
            }

            MatrixConfiguration matrix = BuildMatrix(generated);
            CatalogConfiguration catalog = BuildCatalog(generated);
            PreregistrationConfiguration preregistration = BuildPreregistration();

            WriteConfiguration(bundlePath, MatrixFileName, matrix, artifacts);
            WriteConfiguration(bundlePath, PreregistrationFileName, preregistration, artifacts);
            WriteConfiguration(bundlePath, CatalogFileName, catalog, artifacts);

            artifacts.Sort(CompareArtifacts);
            BundleManifest manifest = BuildManifest(projectPath, generated, artifacts);
            string manifestPath = Path.Combine(bundlePath, ManifestFileName);
            byte[] manifestBytes = SerializeJsonBytes(manifest);
            WriteBytesCreateNew(manifestPath, manifestBytes);

            result.scenarioCount = generated.Count;
            result.eligibilityCount = matrix.eligibilityEntries.Length;
            CountGoalStructures(blueprints, out result.sharedScenarioCount, out result.heterogeneousScenarioCount);
            result.manifestSha256 = Sha256(manifestBytes);
            result.bundleAggregateSha256 = manifest.bundleAggregateSha256;
            result.secondGenerationRefused = Directory.EnumerateFileSystemEntries(bundlePath).GetEnumerator().MoveNext();
            Assert(result.scenarioCount == 53 && result.eligibilityCount == 212, "Generated bundle counts differ.", ref assertions);
            Assert(result.secondGenerationRefused, "A second generation would not be refused.", ref assertions);
            Assert(!manifest.pilotExecuted && !manifest.formalCampaignExecuted, "Execution flags must remain false.", ref assertions);
        }

        private static void VerifyBundle(string projectPath, Gate11Result result, ref int assertions)
        {
            string bundlePath = Path.Combine(projectPath, BundleRelativePath.Replace('/', Path.DirectorySeparatorChar));
            string manifestPath = Path.Combine(bundlePath, ManifestFileName);
            Assert(File.Exists(manifestPath), "Bundle manifest is missing.", ref assertions);

            BundleManifest manifest = LoadJson<BundleManifest>(manifestPath);
            MatrixConfiguration matrix = LoadJson<MatrixConfiguration>(Path.Combine(bundlePath, MatrixFileName));
            CatalogConfiguration catalog = LoadJson<CatalogConfiguration>(Path.Combine(bundlePath, CatalogFileName));
            PreregistrationConfiguration preregistration = LoadJson<PreregistrationConfiguration>(Path.Combine(bundlePath, PreregistrationFileName));
            FormalScenarioBlueprint[] blueprints = FormalScenarioMatrixGenerator.BuildBlueprints();
            Dictionary<string, FormalScenarioBlueprint> blueprintById = IndexBlueprints(blueprints);

            string manifestHashBeforeGenerationGuard = Sha256(File.ReadAllBytes(manifestPath));
            bool secondGenerationRejected = false;
            int generationGuardAssertions = 0;
            try { AssertOutputDirectoryEmpty(bundlePath, ref generationGuardAssertions); }
            catch (InvalidOperationException) { secondGenerationRejected = true; }
            Assert(secondGenerationRejected && Sha256(File.ReadAllBytes(manifestPath)) == manifestHashBeforeGenerationGuard,
                "The create-new generation guard did not reject the retained output without mutation.", ref assertions);

            VerifyManifest(projectPath, bundlePath, manifest, ref assertions);
            VerifyConfigurationHeaders(matrix, catalog, preregistration, ref assertions);
            VerifyPreregistration(preregistration, ref assertions);
            VerifyBlueprintCoverage(blueprints, ref assertions);
            VerifyArtifactSet(bundlePath, manifest, ref assertions);

            Dictionary<string, MatrixScenarioRecord> matrixById = IndexMatrixScenarios(matrix.scenarios, ref assertions);
            Dictionary<string, CatalogEntry> catalogById = IndexCatalog(catalog.scenarios, ref assertions);
            Dictionary<string, ManifestScenarioRecord> manifestById = IndexManifestScenarios(manifest.scenarios, ref assertions);
            Dictionary<string, List<EligibilityRecord>> eligibilityByScenario = IndexEligibility(matrix.eligibilityEntries, ref assertions);
            HashSet<string> sourceHashes = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> fingerprints = new HashSet<string>(StringComparer.Ordinal);
            Dictionary<string, string> pairedMaterialization = new Dictionary<string, string>(StringComparer.Ordinal);
            int plannerInitializations = 0;
            int phaseCount = 0;
            int sharedCount = 0;
            int heterogeneousCount = 0;

            for (int index = 0; index < blueprints.Length; index++)
            {
                FormalScenarioBlueprint blueprint = blueprints[index];
                MatrixScenarioRecord matrixRecord;
                CatalogEntry catalogRecord;
                ManifestScenarioRecord manifestRecord;
                Assert(matrixById.TryGetValue(blueprint.scenarioId, out matrixRecord), "Matrix scenario is missing: " + blueprint.scenarioId, ref assertions);
                Assert(catalogById.TryGetValue(blueprint.scenarioId, out catalogRecord), "Catalog scenario is missing: " + blueprint.scenarioId, ref assertions);
                Assert(manifestById.TryGetValue(blueprint.scenarioId, out manifestRecord), "Manifest scenario is missing: " + blueprint.scenarioId, ref assertions);
                string scenarioPath = Path.Combine(bundlePath, matrixRecord.relativePath.Replace('/', Path.DirectorySeparatorChar));
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                ResolvedDeterministicScenario scenario = loaded.Resolved;
                byte[] sourceBytes = File.ReadAllBytes(scenarioPath);
                byte[] canonicalBytes = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(scenario));
                string sourceHash = Sha256(sourceBytes);
                string canonicalHash = Sha256(canonicalBytes);

                Assert(ByteArraysEqual(sourceBytes, canonicalBytes), "Source is not byte-canonical: " + blueprint.scenarioId, ref assertions);
                Assert(sourceHash == canonicalHash && sourceHash == loaded.SourceSha256, "Source/canonical hash differs: " + blueprint.scenarioId, ref assertions);
                Assert(sourceHash == matrixRecord.sourceSha256 && sourceHash == matrixRecord.canonicalSha256, "Matrix hash differs: " + blueprint.scenarioId, ref assertions);
                Assert(sourceHash == catalogRecord.sourceSha256 && sourceHash == catalogRecord.canonicalSha256, "Catalog hash differs: " + blueprint.scenarioId, ref assertions);
                Assert(sourceHash == manifestRecord.sourceSha256 && sourceHash == manifestRecord.canonicalSha256, "Manifest hash differs: " + blueprint.scenarioId, ref assertions);
                Assert(scenario.FingerprintSha256 == matrixRecord.fingerprintSha256 && scenario.FingerprintSha256 == catalogRecord.fingerprintSha256 && scenario.FingerprintSha256 == manifestRecord.fingerprintSha256,
                    "Scenario fingerprint metadata differs: " + blueprint.scenarioId, ref assertions);
                Assert(sourceBytes.LongLength == matrixRecord.byteCount && sourceBytes.LongLength == catalogRecord.byteCount && sourceBytes.LongLength == manifestRecord.byteCount,
                    "Scenario byte count metadata differs: " + blueprint.scenarioId, ref assertions);
                Assert(sourceBytes.Length <= DeterministicScenarioJson.MaximumUtf8Bytes, "Scenario exceeds 16 MiB: " + blueprint.scenarioId, ref assertions);
                Assert(sourceHashes.Add(sourceHash), "Duplicate scenario source hash: " + blueprint.scenarioId, ref assertions);
                Assert(fingerprints.Add(scenario.FingerprintSha256), "Duplicate scenario fingerprint: " + blueprint.scenarioId, ref assertions);

                LoadedDeterministicScenario reparsed = DeterministicScenarioJson.Parse(StrictUtf8.GetString(canonicalBytes));
                Assert(reparsed.Resolved.FingerprintSha256 == scenario.FingerprintSha256, "Canonical reparse fingerprint differs: " + blueprint.scenarioId, ref assertions);
                DeterministicScenarioDefinition regeneratedDefinition = FormalScenarioMatrixGenerator.GenerateDefinition(blueprintById[blueprint.scenarioId]);
                byte[] regeneratedBytes = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(regeneratedDefinition.Resolve()));
                Assert(ByteArraysEqual(sourceBytes, regeneratedBytes), "Deterministic regeneration differs: " + blueprint.scenarioId, ref assertions);

                VerifyScenarioMetadata(blueprint, scenario, matrixRecord, catalogRecord, manifestRecord, ref assertions);
                VerifyFullCellMaterialization(blueprint, scenario, ref assertions);
                VerifyTerrainAndObstacles(blueprint, scenario, ref assertions);
                VerifyEventsAndRestoration(blueprint, scenario, ref assertions);
                phaseCount += VerifyIndependentReachability(blueprint, scenario, ref assertions);
                VerifyEligibility(scenario, eligibilityByScenario[blueprint.scenarioId], matrixRecord, ref assertions);
                InitializeEveryPlanner(scenario, ref plannerInitializations, ref assertions);

                if (blueprint.IsSharedGoal) sharedCount++; else heterogeneousCount++;
                if (string.Equals(blueprint.familyId, "balanced-core-v1", StringComparison.Ordinal))
                {
                    string pairKey = blueprint.structuralRow.ToString(CultureInfo.InvariantCulture) + ":" + blueprint.seedReplication.ToString(CultureInfo.InvariantCulture);
                    string materialization = ComputeMaterializationSignature(scenario);
                    string previous;
                    if (pairedMaterialization.TryGetValue(pairKey, out previous)) Assert(previous == materialization, "Core shared/heterogeneous materialization differs: " + pairKey, ref assertions);
                    else pairedMaterialization.Add(pairKey, materialization);
                }
            }

            Assert(matrix.scenarioCount == 53 && matrix.scenarios.Length == 53, "Matrix scenario count differs.", ref assertions);
            Assert(matrix.eligibilityCount == 212 && matrix.eligibilityEntries.Length == 212, "Matrix eligibility count differs.", ref assertions);
            Assert(catalog.scenarioCount == 53 && catalog.scenarios.Length == 53, "Catalog scenario count differs.", ref assertions);
            Assert(sharedCount == 32 && heterogeneousCount == 21, "Shared/heterogeneous scenario counts differ; see Gate11_Frozen_Count_Erratum.md.", ref assertions);
            Assert(pairedMaterialization.Count == 16, "Core materialization-pair count differs.", ref assertions);
            VerifyFixedKeyVectors(ref assertions);
            int negativeTests = RunNegativeTests(bundlePath, manifest, matrix, catalog, preregistration, ref assertions);

            result.scenarioCount = blueprints.Length;
            result.eligibilityCount = matrix.eligibilityEntries.Length;
            result.sharedScenarioCount = sharedCount;
            result.heterogeneousScenarioCount = heterogeneousCount;
            result.plannerInitializationCount = plannerInitializations;
            result.reachabilityPhaseCount = phaseCount;
            result.negativeTestCount = negativeTests;
            result.secondGenerationRefused = secondGenerationRejected;
            result.pilotExecuted = manifest.pilotExecuted;
            result.formalCampaignExecuted = manifest.formalCampaignExecuted;
            result.manifestSha256 = Sha256(File.ReadAllBytes(manifestPath));
            result.bundleAggregateSha256 = manifest.bundleAggregateSha256;
            Assert(plannerInitializations == 53 * 4, "Planner initialization count differs.", ref assertions);
            Assert(!result.pilotExecuted && !result.formalCampaignExecuted, "Gate 12/13 execution flag is set.", ref assertions);
        }

        private static MatrixConfiguration BuildMatrix(List<GeneratedRecord> generated)
        {
            List<MatrixScenarioRecord> scenarios = new List<MatrixScenarioRecord>();
            List<EligibilityRecord> eligibility = new List<EligibilityRecord>();
            for (int index = 0; index < generated.Count; index++)
            {
                GeneratedRecord item = generated[index];
                string[] cohorts = item.Blueprint.IsSharedGoal
                    ? new[] { PlanningFairnessContracts.FourAlgorithmSharedGoalCohort }
                    : new[] { PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort, PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort };
                scenarios.Add(new MatrixScenarioRecord
                {
                    scenarioId = item.Blueprint.scenarioId,
                    relativePath = item.RelativePath,
                    familyId = item.Blueprint.familyId,
                    structuralRow = item.Blueprint.structuralRow,
                    seedReplication = item.Blueprint.seedReplication,
                    randomSeed = item.Blueprint.randomSeed,
                    gridWidth = item.Blueprint.gridWidth,
                    gridHeight = item.Blueprint.gridHeight,
                    connectivity = (int)item.Blueprint.connectivity,
                    allowDiagonalCornerCutting = false,
                    terrainModeId = item.Blueprint.terrainModeId,
                    targetObstacleDensity = item.Blueprint.targetObstacleDensity,
                    targetObstacleCount = item.Blueprint.targetObstacleCount,
                    agentCount = item.Blueprint.agentCount,
                    dynamicFootprint = item.Blueprint.dynamicFootprint,
                    goalStructureId = item.Blueprint.goalStructureId,
                    distinctGoalCount = item.Blueprint.distinctGoalCount,
                    dynamicProfileId = item.Blueprint.dynamicProfileId,
                    levelId = item.Blueprint.levelId,
                    sourceSha256 = item.SourceSha256,
                    canonicalSha256 = item.SourceSha256,
                    fingerprintSha256 = item.FingerprintSha256,
                    byteCount = item.ByteCount,
                    comparisonCohorts = cohorts
                });
                for (int cohortIndex = 0; cohortIndex < cohorts.Length; cohortIndex++)
                {
                    string cohort = cohorts[cohortIndex];
                    string[] algorithms = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(cohort);
                    for (int algorithmIndex = 0; algorithmIndex < algorithms.Length; algorithmIndex++)
                    {
                        string algorithm = algorithms[algorithmIndex];
                        eligibility.Add(new EligibilityRecord
                        {
                            matrixEntryId = item.Blueprint.scenarioId + "|" + cohort + "|" + algorithm,
                            scenarioId = item.Blueprint.scenarioId,
                            scenarioRelativePath = item.RelativePath,
                            scenarioSha256 = item.SourceSha256,
                            scenarioFingerprintSha256 = item.FingerprintSha256,
                            comparisonCohortId = cohort,
                            algorithmId = algorithm
                        });
                    }
                }
            }
            return new MatrixConfiguration
            {
                schemaVersion = 1,
                specificationId = FormalScenarioMatrixGenerator.SpecificationId,
                generatorId = FormalScenarioMatrixGenerator.GeneratorId,
                preregistrationId = FormalScenarioMatrixGenerator.PreregistrationId,
                scenarioCount = scenarios.Count,
                eligibilityCount = eligibility.Count,
                scenarios = scenarios.ToArray(),
                eligibilityEntries = eligibility.ToArray()
            };
        }

        private static CatalogConfiguration BuildCatalog(List<GeneratedRecord> generated)
        {
            CatalogEntry[] entries = new CatalogEntry[generated.Count];
            for (int index = 0; index < generated.Count; index++)
            {
                GeneratedRecord item = generated[index];
                entries[index] = new CatalogEntry
                {
                    scenarioId = item.Blueprint.scenarioId,
                    relativePath = item.RelativePath,
                    familyId = item.Blueprint.familyId,
                    randomSeed = item.Blueprint.randomSeed,
                    width = item.Blueprint.gridWidth,
                    height = item.Blueprint.gridHeight,
                    initialObstacleCount = item.InitialObstacleCount,
                    realizedObstacleDensity = item.InitialObstacleCount / (double)(item.Blueprint.gridWidth * item.Blueprint.gridHeight),
                    agentCount = item.Blueprint.agentCount,
                    distinctGoalCount = item.Blueprint.distinctGoalCount,
                    scheduledEventCount = item.Scenario.ScheduledChanges.Count,
                    sourceSha256 = item.SourceSha256,
                    canonicalSha256 = item.SourceSha256,
                    fingerprintSha256 = item.FingerprintSha256,
                    byteCount = item.ByteCount
                };
            }
            return new CatalogConfiguration
            {
                schemaVersion = 1,
                specificationId = FormalScenarioMatrixGenerator.SpecificationId,
                generatorId = FormalScenarioMatrixGenerator.GeneratorId,
                scenarioCount = entries.Length,
                scenarios = entries
            };
        }

        private static PreregistrationConfiguration BuildPreregistration()
        {
            return new PreregistrationConfiguration
            {
                schemaVersion = 1,
                preregistrationId = FormalScenarioMatrixGenerator.PreregistrationId,
                specificationId = FormalScenarioMatrixGenerator.SpecificationId,
                primaryEndpointId = "dynamicHandlingMillisecondsPerScheduledEvent",
                timingTransform = "natural-log-v1",
                effectScale = "exponentiated-ratio-v1",
                confidenceInterval = "two-sided-95-percent-v1",
                analysisRows = new[]
                {
                    Analysis("P1-DL-vs-A-shared", "balanced-core-v1:shared-single-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "D*L / A*-R", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "confirmatory", "primary-four", true, 0.05d),
                    Analysis("P2-DL-vs-A-hetero", "balanced-core-v1:heterogeneous-v1", PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort, "D*L / A*-R", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "confirmatory", "primary-four", true, 0.05d),
                    Analysis("P3-IDFF-vs-CFF-shared", "balanced-core-v1:shared-single-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "IDFF / C-FF", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "confirmatory", "primary-four", true, 0.05d),
                    Analysis("P4-IDFF-vs-CFF-grouped", "balanced-core-v1:heterogeneous-v1", PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort, "IDFF / C-FF", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "confirmatory", "primary-four", true, 0.05d),
                    Analysis("S1-agent-scaling", "agent-scale-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "algorithm x log2(agentCount) mixed model", "totalPlannerElapsedMillisecondsPerAgent", "milliseconds/agent", "confirmatory-secondary", "scaling-two", true, 0.05d),
                    Analysis("S2-footprint-scaling", "dynamic-footprint-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "pair x log2(changedCells) mixed model", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "confirmatory-secondary", "scaling-two", true, 0.05d),
                    Analysis("S3-grid-scaling", "grid-scale-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "descriptive algorithm trajectories", "primary-plus-initialization", "declared-native-units", "descriptive", "none", false, 0d),
                    Analysis("S4-goal-scaling", "goal-count-v1", "both-heterogeneous-cohorts-separate-v1", "descriptive within-cohort trajectories", "dynamicHandlingMillisecondsPerScheduledEvent", "milliseconds/event", "descriptive", "none", false, 0d),
                    Analysis("S5-reachability", "reachability-v1", PlanningFairnessContracts.FourAlgorithmSharedGoalCohort, "categorical phase outcomes and recovery", "successFailureCategory", "category", "descriptive", "none", false, 0d)
                },
                outlierPolicyId = "retain-all-timing-and-allocation-outliers-v1",
                algorithmicFailurePolicyId = "retain-algorithmic-failures-in-denominators-v1",
                technicalInvalidityPolicyId = "process-manifest-hash-provenance-preflight-interruption-only-v1",
                replacementPolicyId = "archive-invalid-next-ordinal-rerun-complete-williams-cycle-v1",
                amendmentPolicyId = "versioned-before-gate13-no-performance-based-removal-v1",
                gate12PrecisionFormula = "n_raw=ceil((1.96*sigma_log/ln(1.05))^2);n_formal=next_multiple_of_4(max(30,n_raw));cap=100",
                gate12MinimumPerAlgorithm = 30,
                gate12MaximumPerAlgorithm = 100,
                gate12CycleMultiple = 4,
                formalSampleSizeStatus = "unset-until-gate12-v1",
                significanceEarlyStoppingAllowed = false,
                trendEarlyStoppingAllowed = false,
                environmentPreflightRequirements = new[]
                {
                    "cpu-model-and-logical-processor-count",
                    "installed-physical-memory",
                    "windows-edition-and-build",
                    "unity-2022.3.30f1c1-path-and-sha256",
                    "ac-power-and-active-power-scheme-guid",
                    "background-process-policy",
                    "thermal-warmup-policy",
                    "campaign-start-and-end-timestamps",
                    "algorithm-specification-implementation-workload-fairness-matrix-preregistration-hashes"
                }
            };
        }

        private static AnalysisRow Analysis(string id, string selector, string cohort, string contrast, string endpoint, string unit, string classification, string multiplicity, bool twoSided, double alpha)
        {
            return new AnalysisRow
            {
                analysisId = id,
                scenarioSelector = selector,
                comparisonCohortId = cohort,
                contrastOrModel = contrast,
                endpointId = endpoint,
                unit = unit,
                classification = classification,
                multiplicityFamily = multiplicity,
                twoSided = twoSided,
                alpha = alpha
            };
        }

        private static BundleManifest BuildManifest(string projectPath, List<GeneratedRecord> generated, List<ArtifactRecord> artifacts)
        {
            ManifestScenarioRecord[] scenarios = new ManifestScenarioRecord[generated.Count];
            for (int index = 0; index < generated.Count; index++)
            {
                GeneratedRecord item = generated[index];
                scenarios[index] = new ManifestScenarioRecord
                {
                    scenarioId = item.Blueprint.scenarioId,
                    relativePath = item.RelativePath,
                    sourceSha256 = item.SourceSha256,
                    canonicalSha256 = item.SourceSha256,
                    fingerprintSha256 = item.FingerprintSha256,
                    byteCount = item.ByteCount
                };
            }
            return new BundleManifest
            {
                schemaVersion = 1,
                specificationId = FormalScenarioMatrixGenerator.SpecificationId,
                specificationRelativePath = SpecificationRelativePath,
                specificationSha256 = HashProjectFile(projectPath, SpecificationRelativePath),
                testDesignRelativePath = TestDesignRelativePath,
                testDesignSha256 = HashProjectFile(projectPath, TestDesignRelativePath),
                generatorId = FormalScenarioMatrixGenerator.GeneratorId,
                generatorSourceRelativePath = GeneratorSourceRelativePath,
                generatorSourceSha256 = HashProjectFile(projectPath, GeneratorSourceRelativePath),
                preregistrationId = FormalScenarioMatrixGenerator.PreregistrationId,
                fairnessProtocolId = PlanningFairnessContracts.FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.FairnessProtocolRelativePath,
                fairnessProtocolSha256 = HashProjectFile(projectPath, PlanningFairnessContracts.FairnessProtocolRelativePath),
                workloadSpecificationId = PlanningFairnessContracts.WorkloadSpecificationId,
                workloadSpecificationRelativePath = PlanningFairnessContracts.WorkloadSpecificationRelativePath,
                workloadSpecificationSha256 = HashProjectFile(projectPath, PlanningFairnessContracts.WorkloadSpecificationRelativePath),
                scenarioCount = generated.Count,
                eligibilityCount = BuildMatrix(generated).eligibilityEntries.Length,
                pilotExecuted = false,
                formalCampaignExecuted = false,
                artifacts = artifacts.ToArray(),
                scenarios = scenarios,
                bundleAggregateSha256 = ComputeAggregateHash(artifacts)
            };
        }

        private static void VerifyManifest(string projectPath, string bundlePath, BundleManifest manifest, ref int assertions)
        {
            Assert(manifest != null && manifest.schemaVersion == 1, "Manifest schema differs.", ref assertions);
            Assert(manifest.specificationId == FormalScenarioMatrixGenerator.SpecificationId, "Manifest specification id differs.", ref assertions);
            Assert(manifest.generatorId == FormalScenarioMatrixGenerator.GeneratorId, "Manifest generator id differs.", ref assertions);
            Assert(manifest.preregistrationId == FormalScenarioMatrixGenerator.PreregistrationId, "Manifest preregistration id differs.", ref assertions);
            Assert(manifest.scenarioCount == 53 && manifest.eligibilityCount == 212, "Manifest counts differ.", ref assertions);
            Assert(!manifest.pilotExecuted && !manifest.formalCampaignExecuted, "Manifest records Gate 12 or Gate 13 execution.", ref assertions);
            Assert(manifest.specificationRelativePath == SpecificationRelativePath && manifest.specificationSha256 == HashProjectFile(projectPath, SpecificationRelativePath), "Specification provenance differs.", ref assertions);
            Assert(manifest.testDesignRelativePath == TestDesignRelativePath && manifest.testDesignSha256 == HashProjectFile(projectPath, TestDesignRelativePath), "Test-design provenance differs.", ref assertions);
            Assert(manifest.generatorSourceRelativePath == GeneratorSourceRelativePath && manifest.generatorSourceSha256 == HashProjectFile(projectPath, GeneratorSourceRelativePath), "Generator provenance differs.", ref assertions);
            Assert(manifest.fairnessProtocolId == PlanningFairnessContracts.FairnessProtocolId && manifest.fairnessProtocolRelativePath == PlanningFairnessContracts.FairnessProtocolRelativePath &&
                manifest.fairnessProtocolSha256 == HashProjectFile(projectPath, PlanningFairnessContracts.FairnessProtocolRelativePath), "Fairness provenance differs.", ref assertions);
            Assert(manifest.workloadSpecificationId == PlanningFairnessContracts.WorkloadSpecificationId && manifest.workloadSpecificationRelativePath == PlanningFairnessContracts.WorkloadSpecificationRelativePath &&
                manifest.workloadSpecificationSha256 == HashProjectFile(projectPath, PlanningFairnessContracts.WorkloadSpecificationRelativePath), "Workload provenance differs.", ref assertions);
            Assert(manifest.artifacts != null && manifest.artifacts.Length == 56, "Manifest artifact count differs.", ref assertions);
            Assert(manifest.scenarios != null && manifest.scenarios.Length == 53, "Manifest scenario record count differs.", ref assertions);

            List<ArtifactRecord> ordered = new List<ArtifactRecord>(manifest.artifacts);
            ordered.Sort(CompareArtifacts);
            for (int index = 0; index < ordered.Count; index++)
            {
                ArtifactRecord artifact = ordered[index];
                string path = Path.Combine(bundlePath, artifact.relativePath.Replace('/', Path.DirectorySeparatorChar));
                Assert(File.Exists(path), "Manifest artifact is missing: " + artifact.relativePath, ref assertions);
                byte[] bytes = File.ReadAllBytes(path);
                Assert(bytes.LongLength == artifact.byteCount && Sha256(bytes) == artifact.sha256, "Manifest artifact identity differs: " + artifact.relativePath, ref assertions);
                if (index > 0) Assert(string.CompareOrdinal(ordered[index - 1].relativePath, artifact.relativePath) < 0, "Manifest artifact paths are duplicated.", ref assertions);
            }
            Assert(IsLowerSha256(manifest.bundleAggregateSha256), "Bundle aggregate is malformed.", ref assertions);
            Assert(manifest.bundleAggregateSha256 == ComputeAggregateHash(ordered), "Bundle aggregate hash differs.", ref assertions);
        }

        private static void VerifyConfigurationHeaders(MatrixConfiguration matrix, CatalogConfiguration catalog, PreregistrationConfiguration preregistration, ref int assertions)
        {
            Assert(matrix != null && matrix.schemaVersion == 1 && matrix.specificationId == FormalScenarioMatrixGenerator.SpecificationId && matrix.generatorId == FormalScenarioMatrixGenerator.GeneratorId && matrix.preregistrationId == FormalScenarioMatrixGenerator.PreregistrationId,
                "Matrix header differs.", ref assertions);
            Assert(catalog != null && catalog.schemaVersion == 1 && catalog.specificationId == FormalScenarioMatrixGenerator.SpecificationId && catalog.generatorId == FormalScenarioMatrixGenerator.GeneratorId,
                "Catalog header differs.", ref assertions);
            Assert(preregistration != null && preregistration.schemaVersion == 1 && preregistration.specificationId == FormalScenarioMatrixGenerator.SpecificationId && preregistration.preregistrationId == FormalScenarioMatrixGenerator.PreregistrationId,
                "Preregistration header differs.", ref assertions);
        }

        private static void VerifyPreregistration(PreregistrationConfiguration preregistration, ref int assertions)
        {
            string[] expectedIds =
            {
                "P1-DL-vs-A-shared", "P2-DL-vs-A-hetero", "P3-IDFF-vs-CFF-shared", "P4-IDFF-vs-CFF-grouped",
                "S1-agent-scaling", "S2-footprint-scaling", "S3-grid-scaling", "S4-goal-scaling", "S5-reachability"
            };
            Assert(preregistration.primaryEndpointId == "dynamicHandlingMillisecondsPerScheduledEvent", "Primary endpoint differs.", ref assertions);
            Assert(preregistration.timingTransform == "natural-log-v1" && preregistration.effectScale == "exponentiated-ratio-v1", "Timing analysis scale differs.", ref assertions);
            Assert(preregistration.analysisRows != null && preregistration.analysisRows.Length == expectedIds.Length, "Preregistration row count differs.", ref assertions);
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < preregistration.analysisRows.Length; index++)
            {
                AnalysisRow row = preregistration.analysisRows[index];
                Assert(row != null && row.analysisId == expectedIds[index] && ids.Add(row.analysisId), "Preregistration analysis ids differ.", ref assertions);
                Assert(!string.IsNullOrWhiteSpace(row.scenarioSelector) && !string.IsNullOrWhiteSpace(row.comparisonCohortId) && !string.IsNullOrWhiteSpace(row.contrastOrModel) &&
                    !string.IsNullOrWhiteSpace(row.endpointId) && !string.IsNullOrWhiteSpace(row.unit) && !string.IsNullOrWhiteSpace(row.classification) && !string.IsNullOrWhiteSpace(row.multiplicityFamily),
                    "Preregistration row is incomplete: " + row.analysisId, ref assertions);
                if (index < 6) Assert(row.twoSided && Math.Abs(row.alpha - 0.05d) < 1e-12d, "Confirmatory alpha differs: " + row.analysisId, ref assertions);
                else Assert(!row.twoSided && row.alpha == 0d, "Descriptive row declares a confirmatory alpha: " + row.analysisId, ref assertions);
            }
            Assert(preregistration.gate12PrecisionFormula == "n_raw=ceil((1.96*sigma_log/ln(1.05))^2);n_formal=next_multiple_of_4(max(30,n_raw));cap=100", "Gate 12 precision formula differs.", ref assertions);
            Assert(preregistration.gate12MinimumPerAlgorithm == 30 && preregistration.gate12MaximumPerAlgorithm == 100 && preregistration.gate12CycleMultiple == 4, "Gate 12 sample constraints differ.", ref assertions);
            Assert(preregistration.formalSampleSizeStatus == "unset-until-gate12-v1", "A formal sample size was set before Gate 12.", ref assertions);
            Assert(!preregistration.significanceEarlyStoppingAllowed && !preregistration.trendEarlyStoppingAllowed, "Early stopping is enabled.", ref assertions);
            Assert(preregistration.outlierPolicyId == "retain-all-timing-and-allocation-outliers-v1" &&
                preregistration.algorithmicFailurePolicyId == "retain-algorithmic-failures-in-denominators-v1" &&
                preregistration.technicalInvalidityPolicyId == "process-manifest-hash-provenance-preflight-interruption-only-v1" &&
                preregistration.replacementPolicyId == "archive-invalid-next-ordinal-rerun-complete-williams-cycle-v1" &&
                preregistration.amendmentPolicyId == "versioned-before-gate13-no-performance-based-removal-v1", "Exclusion/replacement policies differ.", ref assertions);
            Assert(preregistration.environmentPreflightRequirements != null && preregistration.environmentPreflightRequirements.Length == 9, "Environment preflight requirements differ.", ref assertions);
        }

        private static void VerifyBlueprintCoverage(FormalScenarioBlueprint[] blueprints, ref int assertions)
        {
            Dictionary<string, int> familyCounts = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int index = 0; index < blueprints.Length; index++)
            {
                int value;
                familyCounts.TryGetValue(blueprints[index].familyId, out value);
                familyCounts[blueprints[index].familyId] = value + 1;
            }
            Assert(familyCounts["balanced-core-v1"] == 32 && familyCounts["grid-scale-v1"] == 4 && familyCounts["agent-scale-v1"] == 5 &&
                familyCounts["dynamic-footprint-v1"] == 5 && familyCounts["goal-count-v1"] == 5 && familyCounts["reachability-v1"] == 2,
                "Scenario family coverage differs.", ref assertions);

            HashSet<string> structuralRows = new HashSet<string>(StringComparer.Ordinal);
            int[] gridCounts = new int[2];
            int[] connectivityCounts = new int[2];
            int[] terrainCounts = new int[2];
            int[] densityCounts = new int[2];
            int[] agentCounts = new int[2];
            int[] footprintCounts = new int[2];
            for (int index = 0; index < blueprints.Length; index++)
            {
                FormalScenarioBlueprint item = blueprints[index];
                if (item.familyId != "balanced-core-v1" || !item.IsSharedGoal) continue;
                structuralRows.Add(item.structuralRow + ":" + item.gridWidth + ":" + (int)item.connectivity + ":" + item.terrainModeId + ":" + item.targetObstacleDensity.ToString("R", CultureInfo.InvariantCulture) + ":" + item.agentCount + ":" + item.dynamicFootprint);
                gridCounts[item.gridWidth == 64 ? 0 : 1]++;
                connectivityCounts[item.connectivity == NavigationGridConnectivity.FourWay ? 0 : 1]++;
                terrainCounts[item.terrainModeId == FormalScenarioMatrixGenerator.UniformTerrainId ? 0 : 1]++;
                densityCounts[Math.Abs(item.targetObstacleDensity - 0.10d) < 1e-12d ? 0 : 1]++;
                agentCounts[item.agentCount == 16 ? 0 : 1]++;
                footprintCounts[item.dynamicFootprint == 9 ? 0 : 1]++;
            }
            Assert(structuralRows.Count == 8, "Balanced structural row count differs.", ref assertions);
            Assert(BalancedEight(gridCounts) && BalancedEight(connectivityCounts) && BalancedEight(terrainCounts) && BalancedEight(densityCounts) && BalancedEight(agentCounts) && BalancedEight(footprintCounts),
                "Balanced core factor occurrence differs.", ref assertions);
            Assert(CollectLevels(blueprints, "grid-scale-v1", "grid") == "32,64,128,256", "Grid stress levels differ.", ref assertions);
            Assert(CollectLevels(blueprints, "agent-scale-v1", "agent") == "1,8,32,128,512", "Agent stress levels differ.", ref assertions);
            Assert(CollectLevels(blueprints, "dynamic-footprint-v1", "footprint") == "1,9,25,81,225", "Footprint stress levels differ.", ref assertions);
            Assert(CollectLevels(blueprints, "goal-count-v1", "goal") == "2,4,8,16,32", "Goal stress levels differ.", ref assertions);
        }

        private static void VerifyArtifactSet(string bundlePath, BundleManifest manifest, ref int assertions)
        {
            HashSet<string> expected = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < manifest.artifacts.Length; index++) expected.Add(manifest.artifacts[index].relativePath);
            expected.Add(ManifestFileName);
            List<string> actual = new List<string>();
            foreach (string file in Directory.GetFiles(bundlePath, "*", SearchOption.AllDirectories))
            {
                actual.Add(NormalizeRelativePath(bundlePath, file));
            }
            Assert(actual.Count == expected.Count, "Bundle contains a missing or extra file.", ref assertions);
            for (int index = 0; index < actual.Count; index++) Assert(expected.Contains(actual[index]), "Unexpected bundle file: " + actual[index], ref assertions);
        }

        private static void VerifyScenarioMetadata(FormalScenarioBlueprint blueprint, ResolvedDeterministicScenario scenario, MatrixScenarioRecord matrix, CatalogEntry catalog, ManifestScenarioRecord manifest, ref int assertions)
        {
            string expectedRelativePath = ScenarioDirectoryName + "/" + blueprint.scenarioId + ".scenario.json";
            Assert(scenario.ScenarioId == blueprint.scenarioId && scenario.RandomSeed == blueprint.randomSeed, "Scenario identity/seed differs: " + blueprint.scenarioId, ref assertions);
            Assert(scenario.GridWidth == blueprint.gridWidth && scenario.GridHeight == blueprint.gridHeight && scenario.Connectivity == blueprint.connectivity && !scenario.AllowDiagonalCornerCutting,
                "Scenario grid/connectivity differs: " + blueprint.scenarioId, ref assertions);
            Assert(scenario.Agents.Count == blueprint.agentCount && scenario.Goals.Count == blueprint.distinctGoalCount, "Scenario agent/goal count differs: " + blueprint.scenarioId, ref assertions);
            Assert(Math.Abs(scenario.FixedStepSeconds - 0.02d) < 1e-12d && scenario.MaxSimulationTicks == 100001 && scenario.InitializationBudgetMilliseconds == 30000d &&
                scenario.DefaultPlanBudgetMilliseconds == 10000d && scenario.DefaultRepairBudgetMilliseconds == 10000d, "Scenario constants differ: " + blueprint.scenarioId, ref assertions);
            Assert(matrix.familyId == blueprint.familyId && matrix.structuralRow == blueprint.structuralRow && matrix.seedReplication == blueprint.seedReplication && matrix.randomSeed == blueprint.randomSeed &&
                matrix.gridWidth == blueprint.gridWidth && matrix.gridHeight == blueprint.gridHeight && matrix.connectivity == (int)blueprint.connectivity && !matrix.allowDiagonalCornerCutting &&
                matrix.terrainModeId == blueprint.terrainModeId && Math.Abs(matrix.targetObstacleDensity - blueprint.targetObstacleDensity) < 1e-15d && matrix.targetObstacleCount == blueprint.targetObstacleCount &&
                matrix.agentCount == blueprint.agentCount && matrix.dynamicFootprint == blueprint.dynamicFootprint && matrix.goalStructureId == blueprint.goalStructureId &&
                matrix.distinctGoalCount == blueprint.distinctGoalCount && matrix.dynamicProfileId == blueprint.dynamicProfileId && matrix.levelId == blueprint.levelId,
                "Matrix factor metadata differs: " + blueprint.scenarioId, ref assertions);
            Assert(catalog.familyId == blueprint.familyId && catalog.randomSeed == blueprint.randomSeed && catalog.width == blueprint.gridWidth && catalog.height == blueprint.gridHeight &&
                catalog.agentCount == blueprint.agentCount && catalog.distinctGoalCount == blueprint.distinctGoalCount, "Catalog factor metadata differs: " + blueprint.scenarioId, ref assertions);
            Assert(matrix.relativePath == expectedRelativePath && catalog.relativePath == expectedRelativePath && manifest.relativePath == expectedRelativePath,
                "Scenario relative paths differ across matrix/catalog/manifest: " + blueprint.scenarioId, ref assertions);
        }

        private static void VerifyFullCellMaterialization(FormalScenarioBlueprint blueprint, ResolvedDeterministicScenario scenario, ref int assertions)
        {
            int expected = checked(blueprint.gridWidth * blueprint.gridHeight);
            Assert(scenario.InitialGridOverrides.Count == expected, "Full-cell materialization count differs: " + blueprint.scenarioId, ref assertions);
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++)
            {
                int expectedX = index % blueprint.gridWidth;
                int expectedY = index / blueprint.gridWidth;
                GridCoordinate coordinate = scenario.InitialGridOverrides[index].coordinate;
                Assert(coordinate.x == expectedX && coordinate.y == expectedY, "Initial cells are not canonical (y,x): " + blueprint.scenarioId, ref assertions);
            }
        }

        private static void VerifyTerrainAndObstacles(FormalScenarioBlueprint blueprint, ResolvedDeterministicScenario scenario, ref int assertions)
        {
            int obstacles = 0;
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++)
            {
                NavigationGridChange change = scenario.InitialGridOverrides[index];
                if (!change.isWalkable)
                {
                    obstacles++;
                    Assert(change.traversalCost == 1f, "Blocked cell cost differs: " + blueprint.scenarioId, ref assertions);
                }
                if (blueprint.terrainModeId == FormalScenarioMatrixGenerator.UniformTerrainId) Assert(change.traversalCost == 1f, "Uniform terrain contains a non-unit cost: " + blueprint.scenarioId, ref assertions);
                else Assert(change.traversalCost == 1f || change.traversalCost == 2f || change.traversalCost == 4f || change.traversalCost == 8f, "Weighted terrain contains an unauthorized cost: " + blueprint.scenarioId, ref assertions);
            }
            Assert(obstacles == blueprint.targetObstacleCount, "Target obstacle count differs: " + blueprint.scenarioId, ref assertions);
        }

        private static void VerifyEventsAndRestoration(FormalScenarioBlueprint blueprint, ResolvedDeterministicScenario scenario, ref int assertions)
        {
            HashSet<GridCoordinate> startsAndGoals = new HashSet<GridCoordinate>();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                startsAndGoals.Add(agent.Start);
                startsAndGoals.Add(agent.Goal);
                Assert(GetInitial(scenario, agent.Start).isWalkable && GetInitial(scenario, agent.Goal).isWalkable, "Agent start/goal is blocked: " + blueprint.scenarioId, ref assertions);
            }

            if (blueprint.IsTemporaryDisconnection)
            {
                Assert(scenario.ScheduledChanges.Count == 4, "Reachability event count differs.", ref assertions);
                string[] ids = { "close-first-gate", "close-second-gate", "reopen-first-gate", "reopen-second-gate" };
                long[] ticks = { 10, 50000, 75000, 99999 };
                for (int index = 0; index < 4; index++)
                {
                    ResolvedScheduledNavigationChange item = scenario.ScheduledChanges[index];
                    Assert(item.EventId == ids[index] && item.SimulationTick == ticks[index] && item.Order == 0 && item.Changes.Count == 1, "Reachability event differs: " + blueprint.scenarioId, ref assertions);
                }
                return;
            }

            Assert(scenario.ScheduledChanges.Count == 5, "General event count differs: " + blueprint.scenarioId, ref assertions);
            string[] expectedIds = { "block-footprint", "unblock-footprint", "increase-cost-footprint", "decrease-cost-footprint", "restore-initial-state" };
            long[] expectedTicks = { 10, 10, 50000, 75000, 99999 };
            int[] expectedOrders = { 0, 1, 0, 0, 0 };
            HashSet<GridCoordinate> touched = new HashSet<GridCoordinate>();
            for (int eventIndex = 0; eventIndex < 4; eventIndex++)
            {
                ResolvedScheduledNavigationChange item = scenario.ScheduledChanges[eventIndex];
                Assert(item.EventId == expectedIds[eventIndex] && item.SimulationTick == expectedTicks[eventIndex] && item.Order == expectedOrders[eventIndex], "General event identity differs: " + blueprint.scenarioId, ref assertions);
                Assert(item.Changes.Count == blueprint.dynamicFootprint, "General event footprint differs: " + blueprint.scenarioId, ref assertions);
                for (int changeIndex = 0; changeIndex < item.Changes.Count; changeIndex++)
                {
                    GridCoordinate coordinate = item.Changes[changeIndex].coordinate;
                    Assert(touched.Add(coordinate), "General event candidate sets overlap: " + blueprint.scenarioId, ref assertions);
                    Assert(!startsAndGoals.Contains(coordinate), "General event touches an agent start or goal: " + blueprint.scenarioId, ref assertions);
                }
            }
            ResolvedScheduledNavigationChange restore = scenario.ScheduledChanges[4];
            Assert(restore.EventId == expectedIds[4] && restore.SimulationTick == expectedTicks[4] && restore.Order == 0 && restore.Changes.Count == blueprint.dynamicFootprint * 4,
                "Restore event differs: " + blueprint.scenarioId, ref assertions);
            for (int index = 0; index < restore.Changes.Count; index++)
            {
                NavigationGridChange change = restore.Changes[index];
                NavigationGridChange initial = GetInitial(scenario, change.coordinate);
                Assert(touched.Contains(change.coordinate) && SameChange(initial, change), "Restore does not reproduce initial state: " + blueprint.scenarioId, ref assertions);
            }
        }

        private static int VerifyIndependentReachability(FormalScenarioBlueprint blueprint, ResolvedDeterministicScenario scenario, ref int assertions)
        {
            GridState state = StateFromScenario(scenario);
            Dictionary<GridCoordinate, NavigationGridChange> initialTouched = new Dictionary<GridCoordinate, NavigationGridChange>();
            for (int eventIndex = 0; eventIndex < scenario.ScheduledChanges.Count; eventIndex++)
            {
                IReadOnlyList<NavigationGridChange> changes = scenario.ScheduledChanges[eventIndex].Changes;
                for (int index = 0; index < changes.Count; index++)
                {
                    GridCoordinate coordinate = changes[index].coordinate;
                    if (!initialTouched.ContainsKey(coordinate)) initialTouched.Add(coordinate, StateChange(state, coordinate));
                }
            }

            List<bool> phases = new List<bool>();
            phases.Add(AllAgentsReachGoals(state, scenario));
            long currentTick = long.MinValue;
            for (int eventIndex = 0; eventIndex < scenario.ScheduledChanges.Count; eventIndex++)
            {
                ResolvedScheduledNavigationChange item = scenario.ScheduledChanges[eventIndex];
                if (currentTick != long.MinValue && item.SimulationTick != currentTick) phases.Add(AllAgentsReachGoals(state, scenario));
                Apply(state, item.Changes);
                currentTick = item.SimulationTick;
            }
            phases.Add(AllAgentsReachGoals(state, scenario));

            if (blueprint.IsTemporaryDisconnection)
            {
                bool[] expected = { true, true, false, true, true };
                Assert(phases.Count == expected.Length, "Reachability phase count differs: " + blueprint.scenarioId, ref assertions);
                for (int index = 0; index < expected.Length; index++) Assert(phases[index] == expected[index], "Reachability transition differs at phase " + index + ": " + blueprint.scenarioId, ref assertions);
            }
            else
            {
                Assert(phases.Count == 5, "General dynamic phase count differs: " + blueprint.scenarioId, ref assertions);
                for (int index = 0; index < phases.Count; index++) Assert(phases[index], "General scenario lost reachability at phase " + index + ": " + blueprint.scenarioId, ref assertions);
            }
            foreach (KeyValuePair<GridCoordinate, NavigationGridChange> pair in initialTouched)
            {
                Assert(SameChange(pair.Value, StateChange(state, pair.Key)), "Final state failed to restore: " + blueprint.scenarioId, ref assertions);
            }
            return phases.Count;
        }

        private static void VerifyEligibility(ResolvedDeterministicScenario scenario, List<EligibilityRecord> entries, MatrixScenarioRecord matrixRecord, ref int assertions)
        {
            bool shared = scenario.Goals.Count == 1;
            int expectedCount = shared ? 4 : 4;
            Assert(entries != null && entries.Count == expectedCount, "Eligibility count differs: " + scenario.ScenarioId, ref assertions);
            HashSet<string> combinations = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < entries.Count; index++)
            {
                EligibilityRecord entry = entries[index];
                Assert(entry.scenarioId == scenario.ScenarioId && entry.scenarioRelativePath == matrixRecord.relativePath &&
                    entry.scenarioSha256 == matrixRecord.sourceSha256 && entry.scenarioFingerprintSha256 == scenario.FingerprintSha256,
                    "Eligibility scenario identity differs: " + entry.matrixEntryId, ref assertions);
                PlanningFairnessClassification classification = PlanningFairnessContracts.Classify(scenario, entry.algorithmId);
                Assert(classification.ComparisonCohortId == entry.comparisonCohortId, "Cohort classification differs: " + entry.matrixEntryId, ref assertions);
                PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(entry.algorithmId, entry.comparisonCohortId);
                Assert(combinations.Add(entry.comparisonCohortId + "|" + entry.algorithmId), "Duplicate eligibility combination: " + entry.matrixEntryId, ref assertions);
            }
            if (shared)
            {
                string[] algorithms = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(PlanningFairnessContracts.FourAlgorithmSharedGoalCohort);
                for (int index = 0; index < algorithms.Length; index++) Assert(combinations.Contains(PlanningFairnessContracts.FourAlgorithmSharedGoalCohort + "|" + algorithms[index]), "Shared algorithm eligibility is incomplete.", ref assertions);
            }
            else
            {
                string[] perAgent = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort);
                string[] grouped = PlanningFairnessContracts.GetAlgorithmsForComparisonCohort(PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort);
                for (int index = 0; index < perAgent.Length; index++) Assert(combinations.Contains(PlanningFairnessContracts.PerAgentHeterogeneousGoalCohort + "|" + perAgent[index]), "Per-agent heterogeneous eligibility is incomplete.", ref assertions);
                for (int index = 0; index < grouped.Length; index++) Assert(combinations.Contains(PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort + "|" + grouped[index]), "Grouped-field heterogeneous eligibility is incomplete.", ref assertions);
            }
        }

        private static void InitializeEveryPlanner(ResolvedDeterministicScenario scenario, ref int count, ref int assertions)
        {
            GridCoordinate[] goals = new GridCoordinate[scenario.Goals.Count];
            for (int index = 0; index < goals.Length; index++) goals[index] = scenario.Goals[index];
            INavigationPlanner[] planners =
            {
                new AStarRepeatedPlanner(),
                new DStarLitePlanner(),
                new CorrectedFullRecomputeFlowFieldPlanner(),
                new IncrementalDynamicFlowFieldPlanner()
            };
            for (int index = 0; index < planners.Length; index++)
            {
                INavigationPlanner planner = planners[index];
                try
                {
                    DDM.Research.Grid.ResearchNavigationGrid grid = scenario.CreateGrid();
                    NavigationOperationMetrics metrics = planner.Initialize(grid, new NavigationPlannerInitialization
                    {
                        runId = "gate11-init-" + scenario.ScenarioId + "-" + planner.AlgorithmId,
                        goalSetId = scenario.GoalSetId,
                        goals = goals,
                        connectivity = scenario.Connectivity,
                        allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                        budgetMilliseconds = scenario.InitializationBudgetMilliseconds
                    });
                    Assert(metrics != null && !metrics.budgetExceeded, "Planner initialization exceeded budget: " + scenario.ScenarioId + " / " + planner.AlgorithmId, ref assertions);
                    Assert(planner.GridVersion == grid.Version, "Planner initialization grid version differs: " + scenario.ScenarioId + " / " + planner.AlgorithmId, ref assertions);
                    count++;
                }
                finally
                {
                    planner.Reset();
                }
            }
        }

        private static bool AllAgentsReachGoals(GridState state, ResolvedDeterministicScenario scenario)
        {
            Dictionary<GridCoordinate, bool[,]> reachableByGoal = new Dictionary<GridCoordinate, bool[,]>();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                bool[,] reachable;
                if (!reachableByGoal.TryGetValue(agent.Goal, out reachable))
                {
                    reachable = FloodFromGoal(state, agent.Goal, scenario.Connectivity, scenario.AllowDiagonalCornerCutting);
                    reachableByGoal.Add(agent.Goal, reachable);
                }
                if (!reachable[agent.Start.x, agent.Start.y]) return false;
            }
            return true;
        }

        private static bool[,] FloodFromGoal(GridState state, GridCoordinate goal, NavigationGridConnectivity connectivity, bool allowDiagonalCornerCutting)
        {
            bool[,] visited = new bool[state.Width, state.Height];
            if (!state.Walkable[goal.x, goal.y]) return visited;
            GridCoordinate[] offsets = connectivity == NavigationGridConnectivity.FourWay
                ? new[] { new GridCoordinate(0, -1), new GridCoordinate(-1, 0), new GridCoordinate(1, 0), new GridCoordinate(0, 1) }
                : new[]
                {
                    new GridCoordinate(-1, -1), new GridCoordinate(0, -1), new GridCoordinate(1, -1),
                    new GridCoordinate(-1, 0), new GridCoordinate(1, 0),
                    new GridCoordinate(-1, 1), new GridCoordinate(0, 1), new GridCoordinate(1, 1)
                };
            Queue<GridCoordinate> queue = new Queue<GridCoordinate>();
            visited[goal.x, goal.y] = true;
            queue.Enqueue(goal);
            while (queue.Count > 0)
            {
                GridCoordinate current = queue.Dequeue();
                for (int index = 0; index < offsets.Length; index++)
                {
                    int nx = current.x + offsets[index].x;
                    int ny = current.y + offsets[index].y;
                    if (nx < 0 || nx >= state.Width || ny < 0 || ny >= state.Height || visited[nx, ny] || !state.Walkable[nx, ny]) continue;
                    bool diagonal = offsets[index].x != 0 && offsets[index].y != 0;
                    if (diagonal && !allowDiagonalCornerCutting && (!state.Walkable[current.x + offsets[index].x, current.y] || !state.Walkable[current.x, current.y + offsets[index].y])) continue;
                    visited[nx, ny] = true;
                    queue.Enqueue(new GridCoordinate(nx, ny));
                }
            }
            return visited;
        }

        private static int RunNegativeTests(string bundlePath, BundleManifest manifest, MatrixConfiguration matrix, CatalogConfiguration catalog, PreregistrationConfiguration preregistration, ref int assertions)
        {
            int count = 0;
            string temporaryRoot = Path.Combine(Path.GetTempPath(), "ddm-gate11-negative-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporaryRoot);
            try
            {
                MatrixScenarioRecord firstMatrix = matrix.scenarios[0];
                string sourcePath = Path.Combine(bundlePath, firstMatrix.relativePath.Replace('/', Path.DirectorySeparatorChar));

                // 1. A valid JSON file with changed trailing bytes must fail canonical/hash identity.
                byte[] sourceBytes = File.ReadAllBytes(sourcePath);
                byte[] changedBytes = new byte[sourceBytes.Length + 1];
                Buffer.BlockCopy(sourceBytes, 0, changedBytes, 0, sourceBytes.Length);
                changedBytes[changedBytes.Length - 1] = (byte)' ';
                string changedScenarioPath = Path.Combine(temporaryRoot, "changed.scenario.json");
                File.WriteAllBytes(changedScenarioPath, changedBytes);
                bool changedBytesRejected;
                try
                {
                    LoadedDeterministicScenario changed = DeterministicScenarioJson.LoadFromFile(changedScenarioPath);
                    byte[] canonical = StrictUtf8.GetBytes(DeterministicScenarioJson.SerializeCanonical(changed.Resolved));
                    changedBytesRejected = !ByteArraysEqual(changedBytes, canonical) || Sha256(changedBytes) != firstMatrix.sourceSha256;
                }
                catch (Exception) { changedBytesRejected = true; }
                Assert(changedBytesRejected, "Changed scenario bytes were accepted.", ref assertions); count++;

                // 2. Catalog source/fingerprint tampering must fail cross-artifact identity.
                CatalogConfiguration changedCatalog = CloneJson(catalog);
                changedCatalog.scenarios[0].sourceSha256 = new string('0', 64);
                changedCatalog.scenarios[0].fingerprintSha256 = new string('f', 64);
                Assert(!CatalogEntryMatchesMatrix(changedCatalog.scenarios[0], firstMatrix), "Changed catalog hash/fingerprint was accepted.", ref assertions); count++;

                // 3. Duplicate scenario and matrix-entry ids must fail uniqueness.
                MatrixConfiguration duplicateMatrix = CloneJson(matrix);
                duplicateMatrix.scenarios[1].scenarioId = duplicateMatrix.scenarios[0].scenarioId;
                duplicateMatrix.eligibilityEntries[1].matrixEntryId = duplicateMatrix.eligibilityEntries[0].matrixEntryId;
                Assert(!HasUniqueMatrixIdentities(duplicateMatrix), "Duplicate scenario/matrix entry ids were accepted.", ref assertions); count++;

                // 4. Both a missing and an extra scenario path must fail exact set equality.
                HashSet<string> retainedPaths = new HashSet<string>(StringComparer.Ordinal);
                for (int index = 0; index < manifest.scenarios.Length; index++) retainedPaths.Add(manifest.scenarios[index].relativePath);
                HashSet<string> missingPaths = new HashSet<string>(retainedPaths, StringComparer.Ordinal);
                missingPaths.Remove(manifest.scenarios[0].relativePath);
                HashSet<string> extraPaths = new HashSet<string>(retainedPaths, StringComparer.Ordinal);
                extraPaths.Add("Scenarios/extra.scenario.json");
                Assert(!HasExactScenarioPathSet(missingPaths, manifest.scenarios) && !HasExactScenarioPathSet(extraPaths, manifest.scenarios),
                    "Missing or extra scenario path was accepted.", ref assertions); count++;

                // 5. A separately generated definition with its last materialized cell removed must fail the full-cell contract.
                FormalScenarioBlueprint firstBlueprint = FindBlueprint(firstMatrix.scenarioId);
                DeterministicScenarioDefinition truncatedDefinition = FormalScenarioMatrixGenerator.GenerateDefinition(firstBlueprint);
                Array.Resize(ref truncatedDefinition.initialGridOverrides, truncatedDefinition.initialGridOverrides.Length - 1);
                ResolvedDeterministicScenario truncated = truncatedDefinition.Resolve();
                Assert(!HasCompleteCellMaterialization(truncated), "Truncated full-cell materialization was accepted.", ref assertions); count++;

                // 6. Factor/seed metadata is checked against the frozen blueprint, not merely against itself.
                MatrixConfiguration wrongFactors = CloneJson(matrix);
                wrongFactors.scenarios[0].randomSeed++;
                Assert(!MatrixRecordMatchesBlueprint(wrongFactors.scenarios[0], firstBlueprint), "Wrong factor metadata or seed was accepted.", ref assertions); count++;

                // 7. Gate 10 must reject an algorithm in the wrong heterogeneous cohort.
                bool unauthorizedRejected = false;
                try { PlanningFairnessContracts.RequireAlgorithmAuthorizedForCohort(NavigationAlgorithmIds.AStarRepeated, PlanningFairnessContracts.GroupedFieldHeterogeneousGoalCohort); }
                catch (InvalidOperationException) { unauthorizedRejected = true; }
                Assert(unauthorizedRejected, "Unauthorized cohort/algorithm combination was accepted.", ref assertions); count++;

                // 8. Changed frozen provenance must differ from the retained manifest reference.
                BundleManifest changedProvenance = CloneJson(manifest);
                changedProvenance.specificationSha256 = new string('0', 64);
                changedProvenance.generatorSourceSha256 = new string('0', 64);
                changedProvenance.workloadSpecificationSha256 = new string('0', 64);
                changedProvenance.fairnessProtocolSha256 = new string('0', 64);
                Assert(!ManifestProvenanceMatches(changedProvenance, manifest), "Changed specification/generator/workload/fairness provenance was accepted.", ref assertions); count++;

                // 9. A changed analysis row or precision rule must differ byte-for-byte from the preregistered reference.
                PreregistrationConfiguration changedPreregistration = CloneJson(preregistration);
                changedPreregistration.analysisRows[0].analysisId = "changed-row";
                changedPreregistration.gate12PrecisionFormula = "changed-formula";
                Assert(!ByteArraysEqual(SerializeJsonBytes(changedPreregistration), SerializeJsonBytes(preregistration)), "Changed preregistration row/formula was accepted.", ref assertions); count++;

                // 10. Either execution flag being true invalidates a Gate 11 manifest.
                BundleManifest executedManifest = CloneJson(manifest);
                executedManifest.pilotExecuted = true;
                Assert(!ExecutionFlagsAreGate11Safe(executedManifest), "A true pilot/formal execution flag was accepted.", ref assertions); count++;

                // 11. Truncated aggregate hashes must fail both syntax and retained identity.
                BundleManifest malformedAggregate = CloneJson(manifest);
                malformedAggregate.bundleAggregateSha256 = malformedAggregate.bundleAggregateSha256.Substring(1);
                Assert(!IsLowerSha256(malformedAggregate.bundleAggregateSha256) && malformedAggregate.bundleAggregateSha256 != manifest.bundleAggregateSha256,
                    "Incomplete aggregate hash was accepted.", ref assertions); count++;
            }
            finally
            {
                if (Directory.Exists(temporaryRoot)) Directory.Delete(temporaryRoot, true);
            }
            return count;
        }

        private static T CloneJson<T>(T value) where T : class
        {
            T clone = JsonUtility.FromJson<T>(JsonUtility.ToJson(value, false));
            if (clone == null) throw new InvalidOperationException("In-memory negative-test clone failed.");
            return clone;
        }

        private static bool CatalogEntryMatchesMatrix(CatalogEntry catalog, MatrixScenarioRecord matrix)
        {
            return catalog != null && matrix != null &&
                catalog.scenarioId == matrix.scenarioId && catalog.relativePath == matrix.relativePath &&
                catalog.sourceSha256 == matrix.sourceSha256 && catalog.canonicalSha256 == matrix.canonicalSha256 &&
                catalog.fingerprintSha256 == matrix.fingerprintSha256 && catalog.byteCount == matrix.byteCount;
        }

        private static bool HasUniqueMatrixIdentities(MatrixConfiguration matrix)
        {
            if (matrix == null || matrix.scenarios == null || matrix.eligibilityEntries == null) return false;
            HashSet<string> scenarioIds = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> entryIds = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < matrix.scenarios.Length; index++) if (!scenarioIds.Add(matrix.scenarios[index].scenarioId)) return false;
            for (int index = 0; index < matrix.eligibilityEntries.Length; index++) if (!entryIds.Add(matrix.eligibilityEntries[index].matrixEntryId)) return false;
            return true;
        }

        private static bool HasExactScenarioPathSet(HashSet<string> paths, ManifestScenarioRecord[] scenarios)
        {
            if (paths == null || scenarios == null || paths.Count != scenarios.Length) return false;
            for (int index = 0; index < scenarios.Length; index++) if (!paths.Contains(scenarios[index].relativePath)) return false;
            return true;
        }

        private static FormalScenarioBlueprint FindBlueprint(string scenarioId)
        {
            FormalScenarioBlueprint[] blueprints = FormalScenarioMatrixGenerator.BuildBlueprints();
            for (int index = 0; index < blueprints.Length; index++) if (blueprints[index].scenarioId == scenarioId) return blueprints[index];
            throw new KeyNotFoundException("Frozen blueprint was not found: " + scenarioId);
        }

        private static bool HasCompleteCellMaterialization(ResolvedDeterministicScenario scenario)
        {
            if (scenario == null || scenario.InitialGridOverrides.Count != scenario.GridWidth * scenario.GridHeight) return false;
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++)
            {
                GridCoordinate coordinate = scenario.InitialGridOverrides[index].coordinate;
                if (coordinate.x != index % scenario.GridWidth || coordinate.y != index / scenario.GridWidth) return false;
            }
            return true;
        }

        private static bool MatrixRecordMatchesBlueprint(MatrixScenarioRecord matrix, FormalScenarioBlueprint blueprint)
        {
            return matrix != null && blueprint != null &&
                matrix.scenarioId == blueprint.scenarioId && matrix.randomSeed == blueprint.randomSeed &&
                matrix.familyId == blueprint.familyId && matrix.structuralRow == blueprint.structuralRow && matrix.seedReplication == blueprint.seedReplication &&
                matrix.gridWidth == blueprint.gridWidth && matrix.gridHeight == blueprint.gridHeight && matrix.connectivity == (int)blueprint.connectivity &&
                matrix.terrainModeId == blueprint.terrainModeId && Math.Abs(matrix.targetObstacleDensity - blueprint.targetObstacleDensity) < 1e-15d &&
                matrix.targetObstacleCount == blueprint.targetObstacleCount && matrix.agentCount == blueprint.agentCount && matrix.dynamicFootprint == blueprint.dynamicFootprint &&
                matrix.goalStructureId == blueprint.goalStructureId && matrix.distinctGoalCount == blueprint.distinctGoalCount &&
                matrix.dynamicProfileId == blueprint.dynamicProfileId && matrix.levelId == blueprint.levelId;
        }

        private static bool ManifestProvenanceMatches(BundleManifest candidate, BundleManifest reference)
        {
            return candidate != null && reference != null &&
                candidate.specificationId == reference.specificationId && candidate.specificationSha256 == reference.specificationSha256 &&
                candidate.testDesignSha256 == reference.testDesignSha256 && candidate.generatorId == reference.generatorId &&
                candidate.generatorSourceSha256 == reference.generatorSourceSha256 && candidate.preregistrationId == reference.preregistrationId &&
                candidate.fairnessProtocolId == reference.fairnessProtocolId && candidate.fairnessProtocolSha256 == reference.fairnessProtocolSha256 &&
                candidate.workloadSpecificationId == reference.workloadSpecificationId && candidate.workloadSpecificationSha256 == reference.workloadSpecificationSha256;
        }

        private static bool ExecutionFlagsAreGate11Safe(BundleManifest manifest)
        {
            return manifest != null && !manifest.pilotExecuted && !manifest.formalCampaignExecuted;
        }

        private static void VerifyFixedKeyVectors(ref int assertions)
        {
            Assert(FormalScenarioMatrixGenerator.SplitMix64(0UL) == 0xe220a8397b1dcdafUL, "SplitMix64 vector 0 differs.", ref assertions);
            Assert(FormalScenarioMatrixGenerator.SplitMix64(1UL) == 0x910a2dec89025cc1UL, "SplitMix64 vector 1 differs.", ref assertions);
            ulong first = FormalScenarioMatrixGenerator.DeterministicKey(110011, 7, 9, 0x123456789abcdef0UL);
            ulong second = FormalScenarioMatrixGenerator.DeterministicKey(110011, 7, 9, 0x123456789abcdef0UL);
            Assert(first == second, "Deterministic key is unstable.", ref assertions);
        }

        private static void ValidateBlueprintIdentities(FormalScenarioBlueprint[] blueprints, ref int assertions)
        {
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> paths = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < blueprints.Length; index++)
            {
                Assert(ids.Add(blueprints[index].scenarioId), "Duplicate blueprint scenario id.", ref assertions);
                Assert(paths.Add(ScenarioDirectoryName + "/" + blueprints[index].scenarioId + ".scenario.json"), "Duplicate blueprint path.", ref assertions);
            }
        }

        private static Dictionary<string, FormalScenarioBlueprint> IndexBlueprints(FormalScenarioBlueprint[] rows)
        {
            Dictionary<string, FormalScenarioBlueprint> result = new Dictionary<string, FormalScenarioBlueprint>(StringComparer.Ordinal);
            for (int index = 0; index < rows.Length; index++) result.Add(rows[index].scenarioId, rows[index]);
            return result;
        }

        private static Dictionary<string, MatrixScenarioRecord> IndexMatrixScenarios(MatrixScenarioRecord[] rows, ref int assertions)
        {
            Dictionary<string, MatrixScenarioRecord> result = new Dictionary<string, MatrixScenarioRecord>(StringComparer.Ordinal);
            Assert(rows != null, "Matrix scenario array is missing.", ref assertions);
            for (int index = 0; index < rows.Length; index++) Assert(result.TryAdd(rows[index].scenarioId, rows[index]), "Duplicate matrix scenario id.", ref assertions);
            return result;
        }

        private static Dictionary<string, CatalogEntry> IndexCatalog(CatalogEntry[] rows, ref int assertions)
        {
            Dictionary<string, CatalogEntry> result = new Dictionary<string, CatalogEntry>(StringComparer.Ordinal);
            Assert(rows != null, "Catalog array is missing.", ref assertions);
            for (int index = 0; index < rows.Length; index++) Assert(result.TryAdd(rows[index].scenarioId, rows[index]), "Duplicate catalog scenario id.", ref assertions);
            return result;
        }

        private static Dictionary<string, ManifestScenarioRecord> IndexManifestScenarios(ManifestScenarioRecord[] rows, ref int assertions)
        {
            Dictionary<string, ManifestScenarioRecord> result = new Dictionary<string, ManifestScenarioRecord>(StringComparer.Ordinal);
            Assert(rows != null, "Manifest scenario array is missing.", ref assertions);
            for (int index = 0; index < rows.Length; index++) Assert(result.TryAdd(rows[index].scenarioId, rows[index]), "Duplicate manifest scenario id.", ref assertions);
            return result;
        }

        private static Dictionary<string, List<EligibilityRecord>> IndexEligibility(EligibilityRecord[] rows, ref int assertions)
        {
            Dictionary<string, List<EligibilityRecord>> result = new Dictionary<string, List<EligibilityRecord>>(StringComparer.Ordinal);
            HashSet<string> ids = new HashSet<string>(StringComparer.Ordinal);
            Assert(rows != null, "Eligibility array is missing.", ref assertions);
            for (int index = 0; index < rows.Length; index++)
            {
                EligibilityRecord item = rows[index];
                Assert(ids.Add(item.matrixEntryId), "Duplicate matrix entry id.", ref assertions);
                List<EligibilityRecord> list;
                if (!result.TryGetValue(item.scenarioId, out list))
                {
                    list = new List<EligibilityRecord>();
                    result.Add(item.scenarioId, list);
                }
                list.Add(item);
            }
            return result;
        }

        private static GridState StateFromScenario(ResolvedDeterministicScenario scenario)
        {
            GridState state = new GridState(scenario.GridWidth, scenario.GridHeight);
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++)
            {
                NavigationGridChange change = scenario.InitialGridOverrides[index];
                state.Walkable[change.coordinate.x, change.coordinate.y] = change.isWalkable;
                state.Costs[change.coordinate.x, change.coordinate.y] = change.traversalCost;
            }
            return state;
        }

        private static void Apply(GridState state, IReadOnlyList<NavigationGridChange> changes)
        {
            for (int index = 0; index < changes.Count; index++)
            {
                NavigationGridChange change = changes[index];
                state.Walkable[change.coordinate.x, change.coordinate.y] = change.isWalkable;
                state.Costs[change.coordinate.x, change.coordinate.y] = change.traversalCost;
            }
        }

        private static NavigationGridChange StateChange(GridState state, GridCoordinate coordinate)
        {
            return new NavigationGridChange { coordinate = coordinate, isWalkable = state.Walkable[coordinate.x, coordinate.y], traversalCost = state.Costs[coordinate.x, coordinate.y] };
        }

        private static NavigationGridChange GetInitial(ResolvedDeterministicScenario scenario, GridCoordinate coordinate)
        {
            return scenario.InitialGridOverrides[coordinate.y * scenario.GridWidth + coordinate.x];
        }

        private static bool SameChange(NavigationGridChange left, NavigationGridChange right)
        {
            return left.coordinate.Equals(right.coordinate) && left.isWalkable == right.isWalkable && left.traversalCost == right.traversalCost;
        }

        private static string ComputeMaterializationSignature(ResolvedDeterministicScenario scenario)
        {
            StringBuilder builder = new StringBuilder();
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++) AppendChange(builder, scenario.InitialGridOverrides[index]);
            for (int eventIndex = 0; eventIndex < scenario.ScheduledChanges.Count; eventIndex++)
            {
                ResolvedScheduledNavigationChange item = scenario.ScheduledChanges[eventIndex];
                builder.Append(item.EventId).Append('|').Append(item.SimulationTick.ToString(CultureInfo.InvariantCulture)).Append('|').Append(item.Order.ToString(CultureInfo.InvariantCulture)).Append('|');
                for (int changeIndex = 0; changeIndex < item.Changes.Count; changeIndex++) AppendChange(builder, item.Changes[changeIndex]);
            }
            return Sha256(StrictUtf8.GetBytes(builder.ToString()));
        }

        private static void AppendChange(StringBuilder builder, NavigationGridChange change)
        {
            builder.Append(change.coordinate.x.ToString(CultureInfo.InvariantCulture)).Append(',')
                .Append(change.coordinate.y.ToString(CultureInfo.InvariantCulture)).Append(',')
                .Append(change.isWalkable ? '1' : '0').Append(',')
                .Append(change.traversalCost.ToString("R", CultureInfo.InvariantCulture)).Append(';');
        }

        private static int CountInitialObstacles(ResolvedDeterministicScenario scenario)
        {
            int count = 0;
            for (int index = 0; index < scenario.InitialGridOverrides.Count; index++) if (!scenario.InitialGridOverrides[index].isWalkable) count++;
            return count;
        }

        private static void CountGoalStructures(FormalScenarioBlueprint[] rows, out int shared, out int heterogeneous)
        {
            shared = 0;
            heterogeneous = 0;
            for (int index = 0; index < rows.Length; index++)
            {
                if (rows[index].IsSharedGoal) shared++; else heterogeneous++;
            }
        }

        private static void AssertOutputDirectoryEmpty(string path, ref int assertions)
        {
            if (Directory.Exists(path))
            {
                using (IEnumerator<string> enumerator = Directory.EnumerateFileSystemEntries(path).GetEnumerator())
                {
                    Assert(!enumerator.MoveNext(), "Gate 11 output directory is nonempty; retained output will not be overwritten: " + path, ref assertions);
                }
            }
            else assertions++;
        }

        private static void WriteConfiguration<T>(string bundlePath, string fileName, T value, List<ArtifactRecord> artifacts)
        {
            byte[] bytes = SerializeJsonBytes(value);
            WriteBytesCreateNew(Path.Combine(bundlePath, fileName), bytes);
            artifacts.Add(new ArtifactRecord { relativePath = fileName, sha256 = Sha256(bytes), byteCount = bytes.LongLength });
        }

        private static byte[] SerializeJsonBytes<T>(T value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            return StrictUtf8.GetBytes(json);
        }

        private static void WriteBytesCreateNew(string path, byte[] bytes)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            using (FileStream stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }
        }

        private static void WriteResult(string path, Gate11Result result)
        {
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            byte[] bytes = SerializeJsonBytes(result);
            File.WriteAllBytes(path, bytes);
        }

        private static T LoadJson<T>(string path) where T : class
        {
            if (!File.Exists(path)) throw new FileNotFoundException("Gate 11 JSON artifact was not found.", path);
            byte[] bytes = File.ReadAllBytes(path);
            string json = StrictUtf8.GetString(bytes);
            T value = JsonUtility.FromJson<T>(json);
            if (value == null) throw new InvalidDataException("Gate 11 JSON artifact could not be parsed: " + path);
            return value;
        }

        private static string HashProjectFile(string projectPath, string relativePath)
        {
            string path = Path.Combine(projectPath, relativePath.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(path)) throw new FileNotFoundException("Required provenance file is missing.", path);
            return Sha256(File.ReadAllBytes(path));
        }

        private static string ComputeAggregateHash(IList<ArtifactRecord> artifacts)
        {
            List<ArtifactRecord> ordered = new List<ArtifactRecord>();
            for (int index = 0; index < artifacts.Count; index++) ordered.Add(artifacts[index]);
            ordered.Sort(CompareArtifacts);
            StringBuilder builder = new StringBuilder();
            for (int index = 0; index < ordered.Count; index++) builder.Append(ordered[index].relativePath).Append('\n').Append(ordered[index].sha256).Append('\n');
            return Sha256(StrictUtf8.GetBytes(builder.ToString()));
        }

        private static int CompareArtifacts(ArtifactRecord left, ArtifactRecord right)
        {
            return string.CompareOrdinal(left.relativePath, right.relativePath);
        }

        private static string Sha256(byte[] bytes)
        {
            using (SHA256 sha256 = SHA256.Create()) return BitConverter.ToString(sha256.ComputeHash(bytes)).Replace("-", string.Empty).ToLowerInvariant();
        }

        private static bool IsLowerSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'))) return false;
            }
            return true;
        }

        private static bool ByteArraysEqual(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            for (int index = 0; index < left.Length; index++) if (left[index] != right[index]) return false;
            return true;
        }

        private static string NormalizeRelativePath(string root, string path)
        {
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(path);
            if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Path escapes the Gate 11 bundle.");
            return full.Substring(prefix.Length).Replace(Path.DirectorySeparatorChar, '/');
        }

        private static bool BalancedEight(int[] counts)
        {
            return counts != null && counts.Length == 2 && counts[0] == 8 && counts[1] == 8;
        }

        private static string CollectLevels(FormalScenarioBlueprint[] rows, string familyId, string field)
        {
            List<int> levels = new List<int>();
            for (int index = 0; index < rows.Length; index++)
            {
                FormalScenarioBlueprint item = rows[index];
                if (item.familyId != familyId) continue;
                int value = field == "grid" ? item.gridWidth : field == "agent" ? item.agentCount : field == "footprint" ? item.dynamicFootprint : item.distinctGoalCount;
                levels.Add(value);
            }
            levels.Sort();
            StringBuilder builder = new StringBuilder();
            for (int index = 0; index < levels.Count; index++)
            {
                if (index > 0) builder.Append(',');
                builder.Append(levels[index].ToString(CultureInfo.InvariantCulture));
            }
            return builder.ToString();
        }

        private static void Assert(bool condition, string message, ref int assertions)
        {
            if (!condition) throw new InvalidOperationException(message);
            assertions++;
        }
    }
}
