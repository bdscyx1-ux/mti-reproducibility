using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    public static class ResearchPlanningBatchCommand
    {
        private static readonly UTF8Encoding Utf8WithoutBom = new UTF8Encoding(false);
        private static readonly Regex SafeRunId = new Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", RegexOptions.CultureInvariant);

        [Serializable]
        private sealed class BatchRunManifest
        {
            public int schemaVersion = 2;
            public string runId;
            public string algorithmId;
            public int fairnessSchemaVersion;
            public string fairnessProtocolId;
            public string fairnessProtocolRelativePath;
            public string fairnessProtocolSha256;
            public string algorithmSpecificationId;
            public string algorithmSpecificationRelativePath;
            public string algorithmSpecificationSha256;
            public string algorithmImplementationRelativePath;
            public string algorithmImplementationSha256;
            public string workloadSpecificationId;
            public string workloadSpecificationRelativePath;
            public string workloadSpecificationSha256;
            public string goalCohortId;
            public string comparisonCohortId;
            public int distinctGoalCount;
            public int plannerInstanceCount;
            public int persistentStateInstanceCount;
            public int sharedFieldInstanceCount;
            public string plannerStateModelId;
            public string processedWorkUnit;
            public string nativeMetricsSemanticsId;
            public bool dynamicCostIncludesAllRepairsAndPostEventPlans;
            public string scenarioSourcePath;
            public string scenarioSourceSha256;
            public string scenarioFingerprintSha256;
            public string canonicalScenarioFile;
            public string canonicalScenarioSha256;
            public string operationsJsonlFile;
            public string operationsJsonlSha256;
            public string workloadResultFile;
            public string workloadResultSha256;
            public string unityVersion;
            public string runtimePlatform;
            public string startedAtUtc;
            public string completedAtUtc;
            public long enqueuedLogRecords;
            public long writtenLogRecords;
            public int planOperationCount;
            public int repairOperationCount;
            public bool completed;
        }

        [Serializable]
        private sealed class BatchFailureRecord
        {
            public int schemaVersion = 1;
            public string failedAtUtc;
            public string exceptionType;
            public string message;
            public string stackTrace;
        }

        public static void Run()
        {
            string outputDirectory = null;
            bool failureOutputAuthorized = false;
            DateTime startedUtc = DateTime.UtcNow;
            try
            {
                string[] arguments = Environment.GetCommandLineArgs();
                string scenarioPath = RequiredOption(arguments, "-ddmScenarioPath");
                outputDirectory = Path.GetFullPath(RequiredOption(arguments, "-ddmOutputDirectory"));
                string runId = RequiredOption(arguments, "-ddmRunId");
                string algorithmId = RequiredOption(arguments, "-ddmAlgorithm");

                if (!SafeRunId.IsMatch(runId)) throw new ArgumentException("Run id must be 1-128 file-safe ASCII characters and begin with an alphanumeric character.");
                INavigationPlanner planner = CreatePlanner(algorithmId);
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                PlanningRunProvenance provenance = BuildProvenance(projectRoot, algorithmId);

                EnsureFreshOutputDirectory(outputDirectory);
                failureOutputAuthorized = true;
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                Directory.CreateDirectory(outputDirectory);

                const string canonicalFileName = "scenario.canonical.json";
                const string operationsFileName = "operations.jsonl";
                const string resultFileName = "workload-result.json";
                const string manifestFileName = "manifest.json";
                string canonicalPath = Path.Combine(outputDirectory, canonicalFileName);
                string operationsPath = Path.Combine(outputDirectory, operationsFileName);
                string resultPath = Path.Combine(outputDirectory, resultFileName);
                string manifestPath = Path.Combine(outputDirectory, manifestFileName);

                string canonicalSha256 = DeterministicScenarioJson.SaveCanonical(canonicalPath, loaded.Resolved, false);
                PlanningWorkloadResult workload;
                long enqueued;
                long written;
                using (JsonlExperimentLogger logger = new JsonlExperimentLogger(operationsPath, ExperimentLogFileMode.CreateNew))
                {
                    workload = DeterministicPlanningWorkloadRunner.Run(runId, loaded.Definition, planner, logger, provenance);
                    logger.Flush(TimeSpan.FromSeconds(30d));
                    enqueued = logger.EnqueuedCount;
                    written = logger.WrittenCount;
                }

                WriteJson(resultPath, workload);
                BatchRunManifest manifest = new BatchRunManifest
                {
                    runId = runId,
                    algorithmId = algorithmId,
                    fairnessSchemaVersion = workload.fairnessSchemaVersion,
                    fairnessProtocolId = workload.fairnessProtocolId,
                    fairnessProtocolRelativePath = workload.fairnessProtocolRelativePath,
                    fairnessProtocolSha256 = workload.fairnessProtocolSha256,
                    algorithmSpecificationId = workload.algorithmSpecificationId,
                    algorithmSpecificationRelativePath = workload.algorithmSpecificationRelativePath,
                    algorithmSpecificationSha256 = workload.algorithmSpecificationSha256,
                    algorithmImplementationRelativePath = workload.algorithmImplementationRelativePath,
                    algorithmImplementationSha256 = workload.algorithmImplementationSha256,
                    workloadSpecificationId = workload.workloadSpecificationId,
                    workloadSpecificationRelativePath = workload.workloadSpecificationRelativePath,
                    workloadSpecificationSha256 = workload.workloadSpecificationSha256,
                    goalCohortId = workload.goalCohortId,
                    comparisonCohortId = workload.comparisonCohortId,
                    distinctGoalCount = workload.distinctGoalCount,
                    plannerInstanceCount = workload.plannerInstanceCount,
                    persistentStateInstanceCount = workload.persistentStateInstanceCount,
                    sharedFieldInstanceCount = workload.sharedFieldInstanceCount,
                    plannerStateModelId = workload.plannerStateModelId,
                    processedWorkUnit = workload.processedWorkUnit,
                    nativeMetricsSemanticsId = workload.nativeMetricsSemanticsId,
                    dynamicCostIncludesAllRepairsAndPostEventPlans = workload.dynamicCostIncludesAllRepairsAndPostEventPlans,
                    scenarioSourcePath = loaded.SourcePath,
                    scenarioSourceSha256 = loaded.SourceSha256,
                    scenarioFingerprintSha256 = loaded.Resolved.FingerprintSha256,
                    canonicalScenarioFile = canonicalFileName,
                    canonicalScenarioSha256 = canonicalSha256,
                    operationsJsonlFile = operationsFileName,
                    operationsJsonlSha256 = ComputeFileSha256(operationsPath),
                    workloadResultFile = resultFileName,
                    workloadResultSha256 = ComputeFileSha256(resultPath),
                    unityVersion = Application.unityVersion,
                    runtimePlatform = Application.platform.ToString(),
                    startedAtUtc = startedUtc.ToString("O", CultureInfo.InvariantCulture),
                    completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    enqueuedLogRecords = enqueued,
                    writtenLogRecords = written,
                    planOperationCount = workload.planOperationCount,
                    repairOperationCount = workload.repairOperationCount,
                    completed = workload.completed
                };
                WriteJson(manifestPath, manifest);
                Debug.Log("DDM planning batch completed. Manifest: " + manifestPath);
            }
            catch (Exception exception)
            {
                TryWriteFailure(failureOutputAuthorized ? outputDirectory : null, exception);
                Debug.LogException(exception);
                throw;
            }
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (string.Equals(algorithmId, NavigationAlgorithmIds.AStarRepeated, StringComparison.Ordinal))
            {
                return new AStarRepeatedPlanner();
            }
            if (string.Equals(algorithmId, NavigationAlgorithmIds.DStarLite, StringComparison.Ordinal))
            {
                return new DStarLitePlanner();
            }
            if (string.Equals(algorithmId, NavigationAlgorithmIds.CorrectedFullRecomputeFlowField, StringComparison.Ordinal))
            {
                return new CorrectedFullRecomputeFlowFieldPlanner();
            }
            if (string.Equals(algorithmId, NavigationAlgorithmIds.IncrementalDynamicFlowField, StringComparison.Ordinal))
            {
                return new IncrementalDynamicFlowFieldPlanner();
            }
            throw new NotSupportedException(
                "The batch pipeline authorizes only planners that passed their algorithm gate: " +
                NavigationAlgorithmIds.AStarRepeated + ", " + NavigationAlgorithmIds.DStarLite + ", " +
                NavigationAlgorithmIds.CorrectedFullRecomputeFlowField + ", " + NavigationAlgorithmIds.IncrementalDynamicFlowField +
                ". Requested: " + algorithmId);
        }

        private static PlanningRunProvenance BuildProvenance(string projectRoot, string algorithmId)
        {
            PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
            PlanningRunProvenance provenance = new PlanningRunProvenance
            {
                fairnessProtocolId = PlanningFairnessContracts.FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.FairnessProtocolRelativePath,
                fairnessProtocolSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.FairnessProtocolRelativePath),
                algorithmId = profile.AlgorithmId,
                algorithmSpecificationId = profile.SpecificationId,
                algorithmSpecificationRelativePath = profile.SpecificationRelativePath,
                algorithmSpecificationSha256 = HashProjectFile(projectRoot, profile.SpecificationRelativePath),
                algorithmImplementationRelativePath = profile.ImplementationRelativePath,
                algorithmImplementationSha256 = HashProjectFile(projectRoot, profile.ImplementationRelativePath),
                workloadSpecificationId = PlanningFairnessContracts.WorkloadSpecificationId,
                workloadSpecificationRelativePath = PlanningFairnessContracts.WorkloadSpecificationRelativePath,
                workloadSpecificationSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.WorkloadSpecificationRelativePath)
            };
            PlanningFairnessContracts.ValidateProvenance(provenance, algorithmId);
            return provenance;
        }

        private static string HashProjectFile(string projectRoot, string relativePath)
        {
            string path = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!File.Exists(path)) throw new FileNotFoundException("Required provenance source is missing.", path);
            return ComputeFileSha256(path);
        }

        private static string RequiredOption(string[] arguments, string option)
        {
            string value = null;
            for (int index = 0; index < arguments.Length; index++)
            {
                if (!string.Equals(arguments[index], option, StringComparison.Ordinal)) continue;
                if (value != null) throw new ArgumentException("Command-line option was supplied more than once: " + option);
                if (index + 1 >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index + 1])) throw new ArgumentException("Command-line option requires a value: " + option);
                value = arguments[index + 1];
            }
            if (value == null) throw new ArgumentException("Required command-line option is missing: " + option);
            return value;
        }

        private static void EnsureFreshOutputDirectory(string outputDirectory)
        {
            if (File.Exists(outputDirectory)) throw new IOException("Batch output path is an existing file: " + outputDirectory);
            if (Directory.Exists(outputDirectory) && Directory.GetFileSystemEntries(outputDirectory).Length > 0)
            {
                throw new IOException("Batch output directory is not empty; refusing to mix or overwrite runs: " + outputDirectory);
            }
        }

        private static void WriteJson<T>(string path, T value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n");
            if (!json.EndsWith("\n", StringComparison.Ordinal)) json += "\n";
            File.WriteAllText(path, json, Utf8WithoutBom);
        }

        private static string ComputeFileSha256(string path)
        {
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (SHA256 sha256 = SHA256.Create())
            {
                return BitConverter.ToString(sha256.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void TryWriteFailure(string outputDirectory, Exception exception)
        {
            if (string.IsNullOrWhiteSpace(outputDirectory)) return;
            try
            {
                Directory.CreateDirectory(outputDirectory);
                WriteJson(Path.Combine(outputDirectory, "failure.json"), new BatchFailureRecord
                {
                    failedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    exceptionType = exception.GetType().FullName,
                    message = exception.Message,
                    stackTrace = exception.ToString()
                });
            }
            catch { }
        }
    }
}
