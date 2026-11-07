using System;
using System.Collections.Generic;
using System.Diagnostics;
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
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Runs one complete Gate13R-AX2 four-treatment Williams block in one fresh
    /// Unity Editor process.  The external supervisor owns retries/replacements;
    /// this command never retries a sample or resumes a partial block.
    /// </summary>
    public static class Gate13RAX2BlockRunnerV1
    {
        private const string DesignId = "gate13r-ax2-shared32-b48-four-treatment-v1";
        private const string CohortId = "gate13r-ax2-shared-goal-v1";
        private const string ScheduleKind = "gate13r-ax2-formal-williams-block-schedule-record-v1";
        private static readonly UTF8Encoding Utf8WithoutBom = new UTF8Encoding(false);
        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$", RegexOptions.CultureInvariant);
        private static readonly string[] BaseAlgorithms =
        {
            NavigationAlgorithmIds.BidirectionalAStarRepeated,
            NavigationAlgorithmIds.LifelongPlanningAStar,
            NavigationAlgorithmIds.CorrectedFullRecomputeFlowField,
            NavigationAlgorithmIds.IncrementalDynamicFlowField
        };

        [Serializable]
        private sealed class ScheduleRecord
        {
            public int schemaVersion;
            public string scheduleKind;
            public string designId;
            public string blockId;
            public string campaignId;
            public int campaignOrdinal;
            public string comparisonCohortId;
            public int campaignBlockOrdinal;
            public int globalBlockOrdinal;
            public int williamsRowIndex;
            public string scenarioId;
            public string scenarioRelativePath;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string outputRelativePath;
            public int expectedSampleCount;
            public ScheduleEntry[] entries = new ScheduleEntry[0];
        }

        [Serializable]
        private sealed class ScheduleEntry
        {
            public int position;
            public string algorithmId;
            public string predecessorAlgorithmId;
            public string runId;
            public string childDirectory;
            public string sampleOutputRelativePath;
        }

        [Serializable]
        private sealed class MemorySnapshot
        {
            public string capturedAtUtc;
            public long managedBytes;
            public long workingSetBytes;
            public long privateMemoryBytes;
        }

        [Serializable]
        private sealed class FileReference
        {
            public string relativePath;
            public string sha256;
            public long bytes;
        }

        [Serializable]
        private sealed class SampleManifest
        {
            public int schemaVersion = 1;
            public string artifactKind = "GATE13R-AX2-SAMPLE-MANIFEST";
            public string designId = DesignId;
            public string blockId;
            public string campaignId;
            public int campaignBlockOrdinal;
            public int globalBlockOrdinal;
            public int williamsRowIndex;
            public int position;
            public string runId;
            public string algorithmId;
            public string predecessorAlgorithmId;
            public string comparisonCohortId;
            public string scenarioId;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string scheduleSha256;
            public string outputSchemaSha256;
            public string executionContractSha256;
            public int processId;
            public string processStartUtc;
            public string startedAtUtc;
            public string completedAtUtc;
            public bool freshPlannerInstance;
            public bool plannerResetCompleted;
            public bool workloadCompleted;
            public int scheduledEventCount;
            public double p1RawGeometricMeanInputMillisecondsPerScheduledEvent;
            public MemorySnapshot memoryBefore;
            public MemorySnapshot memoryAfterCleanup;
            public FileReference canonicalScenario;
            public FileReference operationsLog;
            public FileReference workloadResult;
            public bool completed;
        }

        [Serializable]
        private sealed class BlockSampleReference
        {
            public int position;
            public string algorithmId;
            public string runId;
            public string sampleDirectory;
            public string manifestRelativePath;
            public string manifestSha256;
            public string workloadResultRelativePath;
            public string workloadResultSha256;
        }

        [Serializable]
        private sealed class BlockCompleteReceipt
        {
            public int schemaVersion = 1;
            public string artifactKind = "GATE13R-AX2-BLOCK-COMPLETE";
            public string designId = DesignId;
            public string blockId;
            public string campaignId;
            public int campaignOrdinal;
            public int campaignBlockOrdinal;
            public int globalBlockOrdinal;
            public int williamsRowIndex;
            public string comparisonCohortId;
            public string scenarioId;
            public string scenarioSha256;
            public string scenarioFingerprintSha256;
            public string scheduleSha256;
            public string outputSchemaSha256;
            public string executionContractSha256;
            public string mode;
            public int processId;
            public string processStartUtc;
            public string startedAtUtc;
            public string completedAtUtc;
            public int expectedSampleCount;
            public int completedSampleCount;
            public bool oneFreshProcessForCompleteBlock;
            public bool strictSerialWilliamsOrder;
            public bool noPerAlgorithmRetryResumeTopUpMergeSkipReorder;
            public BlockSampleReference[] samples = new BlockSampleReference[0];
            public bool completed;
        }

        [Serializable]
        private sealed class BlockFailureReceipt
        {
            public int schemaVersion = 1;
            public string artifactKind = "GATE13R-AX2-BLOCK-FAILURE";
            public string designId = DesignId;
            public string blockId;
            public string failedAtUtc;
            public int processId;
            public string processStartUtc;
            public int injectedFailurePosition;
            public string exceptionType;
            public string message;
            public string stackTrace;
            public bool automaticRetryPerformed;
            public bool automaticResumePerformed;
        }

        public static void Run()
        {
            string outputRoot = null;
            string blockId = string.Empty;
            int injectedFailurePosition = 0;
            DateTime startedUtc = DateTime.UtcNow;
            Process process = Process.GetCurrentProcess();
            try
            {
                string[] arguments = Environment.GetCommandLineArgs();
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string schedulePath = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RAX2SchedulePath"));
                string scheduleSha256 = RequiredLowerSha256(arguments, "-ddmGate13RAX2ScheduleSha256");
                string schemaPath = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RAX2OutputSchemaPath"));
                string schemaSha256 = RequiredLowerSha256(arguments, "-ddmGate13RAX2OutputSchemaSha256");
                string contractPath = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RAX2ExecutionContractPath"));
                string contractSha256 = RequiredLowerSha256(arguments, "-ddmGate13RAX2ExecutionContractSha256");
                string allowedRoot = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RAX2AllowedRoot"));
                outputRoot = Path.GetFullPath(RequiredOption(arguments, "-ddmGate13RAX2OutputDirectory"));
                blockId = RequiredOption(arguments, "-ddmGate13RAX2BlockId");
                string mode = RequiredOption(arguments, "-ddmGate13RAX2Mode");
                string injected = OptionalOption(arguments, "-ddmGate13RAX2InjectFailurePosition");
                if (!string.IsNullOrWhiteSpace(injected) && !int.TryParse(injected, NumberStyles.Integer, CultureInfo.InvariantCulture, out injectedFailurePosition))
                    throw new ArgumentException("Injected failure position is not an integer.");

                if (!string.Equals(mode, "Verification", StringComparison.Ordinal) && !string.Equals(mode, "Formal", StringComparison.Ordinal))
                    throw new InvalidOperationException("Runner mode must be Verification or Formal.");
                if (string.Equals(mode, "Formal", StringComparison.Ordinal) && injectedFailurePosition != 0)
                    throw new InvalidOperationException("Failure injection is forbidden in formal mode.");
                if (!File.Exists(schedulePath) || ComputeFileSha256(schedulePath) != scheduleSha256)
                    throw new InvalidOperationException("Frozen AX2 schedule binding mismatch.");
                if (!File.Exists(schemaPath) || ComputeFileSha256(schemaPath) != schemaSha256)
                    throw new InvalidOperationException("Frozen AX2 output-schema binding mismatch.");
                if (!File.Exists(contractPath) || ComputeFileSha256(contractPath) != contractSha256)
                    throw new InvalidOperationException("Frozen AX2 execution-contract binding mismatch.");
                if (!IsWithin(outputRoot, allowedRoot)) throw new InvalidOperationException("Output directory escapes the authorized root.");
                if (Directory.Exists(outputRoot) || File.Exists(outputRoot)) throw new IOException("A block-attempt output path already exists; resume/overwrite is forbidden.");

                ScheduleRecord record = LoadUniqueScheduleRecord(schedulePath, blockId);
                ValidateScheduleRecord(record);
                Directory.CreateDirectory(outputRoot);

                string scenarioPath = ResolveProjectFile(projectRoot, record.scenarioRelativePath);
                if (ComputeFileSha256(scenarioPath) != record.scenarioSha256) throw new InvalidOperationException("Scenario source SHA-256 mismatch.");
                LoadedDeterministicScenario identityLoad = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                if (!string.Equals(identityLoad.Resolved.FingerprintSha256, record.scenarioFingerprintSha256, StringComparison.Ordinal))
                    throw new InvalidOperationException("Scenario fingerprint mismatch.");

                List<BlockSampleReference> completed = new List<BlockSampleReference>();
                for (int index = 0; index < record.entries.Length; index++)
                {
                    ScheduleEntry entry = record.entries[index];
                    if (injectedFailurePosition == entry.position)
                        throw new InvalidOperationException("Injected Gate13R-AX2 verification failure at position " + entry.position.ToString(CultureInfo.InvariantCulture) + ".");
                    completed.Add(RunSample(projectRoot, outputRoot, scenarioPath, record, entry, scheduleSha256, schemaSha256, contractSha256, process));
                }

                BlockCompleteReceipt blockReceipt = new BlockCompleteReceipt
                {
                    blockId = record.blockId,
                    campaignId = record.campaignId,
                    campaignOrdinal = record.campaignOrdinal,
                    campaignBlockOrdinal = record.campaignBlockOrdinal,
                    globalBlockOrdinal = record.globalBlockOrdinal,
                    williamsRowIndex = record.williamsRowIndex,
                    comparisonCohortId = record.comparisonCohortId,
                    scenarioId = record.scenarioId,
                    scenarioSha256 = record.scenarioSha256,
                    scenarioFingerprintSha256 = record.scenarioFingerprintSha256,
                    scheduleSha256 = scheduleSha256,
                    outputSchemaSha256 = schemaSha256,
                    executionContractSha256 = contractSha256,
                    mode = mode,
                    processId = process.Id,
                    processStartUtc = process.StartTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
                    startedAtUtc = startedUtc.ToString("O", CultureInfo.InvariantCulture),
                    completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    expectedSampleCount = record.entries.Length,
                    completedSampleCount = completed.Count,
                    oneFreshProcessForCompleteBlock = true,
                    strictSerialWilliamsOrder = true,
                    noPerAlgorithmRetryResumeTopUpMergeSkipReorder = true,
                    samples = completed.ToArray(),
                    completed = completed.Count == record.entries.Length
                };
                WriteJsonNew(Path.Combine(outputRoot, "block-complete.v1.json"), blockReceipt);
                UnityEngine.Debug.Log("Gate13R-AX2 block completed: " + record.blockId);
            }
            catch (Exception exception)
            {
                if (!string.IsNullOrWhiteSpace(outputRoot) && Directory.Exists(outputRoot))
                {
                    try
                    {
                        WriteJsonNew(Path.Combine(outputRoot, "block-failure.v1.json"), new BlockFailureReceipt
                        {
                            blockId = blockId,
                            failedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                            processId = process.Id,
                            processStartUtc = process.StartTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
                            injectedFailurePosition = injectedFailurePosition,
                            exceptionType = exception.GetType().FullName,
                            message = exception.Message,
                            stackTrace = exception.ToString(),
                            automaticRetryPerformed = false,
                            automaticResumePerformed = false
                        });
                    }
                    catch { }
                }
                UnityEngine.Debug.LogException(exception);
                throw;
            }
        }

        private static BlockSampleReference RunSample(
            string projectRoot,
            string blockOutputRoot,
            string scenarioPath,
            ScheduleRecord record,
            ScheduleEntry entry,
            string scheduleSha256,
            string schemaSha256,
            string contractSha256,
            Process process)
        {
            string sampleRoot = ResolveChild(blockOutputRoot, entry.childDirectory);
            if (Directory.Exists(sampleRoot) || File.Exists(sampleRoot)) throw new IOException("Sample output already exists; per-algorithm resume is forbidden.");
            Directory.CreateDirectory(sampleRoot);
            ForceCollectionBoundary();
            MemorySnapshot before = CaptureMemory(process);
            DateTime startedUtc = DateTime.UtcNow;
            INavigationPlanner planner = CreatePlanner(entry.algorithmId);
            bool resetCompleted = false;
            try
            {
                PlanningRunProvenance provenance = BuildProvenance(projectRoot, entry.algorithmId);
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                const string canonicalName = "scenario.canonical.json";
                const string operationsName = "operations.v1.jsonl";
                const string resultName = "workload-result.v1.json";
                const string manifestName = "sample-manifest.v1.json";
                string canonicalPath = Path.Combine(sampleRoot, canonicalName);
                string operationsPath = Path.Combine(sampleRoot, operationsName);
                string resultPath = Path.Combine(sampleRoot, resultName);
                string manifestPath = Path.Combine(sampleRoot, manifestName);

                string canonicalSha256 = DeterministicScenarioJson.SaveCanonical(canonicalPath, loaded.Resolved, false);
                PlanningWorkloadResult workload;
                using (JsonlExperimentLogger logger = new JsonlExperimentLogger(operationsPath, ExperimentLogFileMode.CreateNew))
                {
                    workload = DeterministicPlanningWorkloadRunner.Run(entry.runId, loaded.Definition, planner, logger, provenance);
                    logger.Flush(TimeSpan.FromSeconds(30d));
                }
                if (!workload.completed) throw new InvalidOperationException("Workload did not complete.");
                if (!string.Equals(workload.algorithmId, entry.algorithmId, StringComparison.Ordinal)) throw new InvalidOperationException("Workload algorithm identity mismatch.");
                if (!string.Equals(workload.scenarioId, record.scenarioId, StringComparison.Ordinal)) throw new InvalidOperationException("Workload scenario identity mismatch.");
                if (!string.Equals(workload.comparisonCohortId, CohortId, StringComparison.Ordinal)) throw new InvalidOperationException("Workload fairness cohort mismatch.");
                double p1 = workload.dynamicHandlingMillisecondsPerScheduledEvent;
                if (double.IsNaN(p1) || double.IsInfinity(p1) || p1 <= 0d) throw new InvalidOperationException("P1 must be finite and strictly positive.");
                WriteJsonNew(resultPath, workload);
                planner.Reset();
                resetCompleted = true;
                planner = null;
                loaded = null;
                ForceCollectionBoundary();
                MemorySnapshot after = CaptureMemory(process);

                SampleManifest manifest = new SampleManifest
                {
                    blockId = record.blockId,
                    campaignId = record.campaignId,
                    campaignBlockOrdinal = record.campaignBlockOrdinal,
                    globalBlockOrdinal = record.globalBlockOrdinal,
                    williamsRowIndex = record.williamsRowIndex,
                    position = entry.position,
                    runId = entry.runId,
                    algorithmId = entry.algorithmId,
                    predecessorAlgorithmId = entry.predecessorAlgorithmId,
                    comparisonCohortId = record.comparisonCohortId,
                    scenarioId = record.scenarioId,
                    scenarioSha256 = record.scenarioSha256,
                    scenarioFingerprintSha256 = record.scenarioFingerprintSha256,
                    scheduleSha256 = scheduleSha256,
                    outputSchemaSha256 = schemaSha256,
                    executionContractSha256 = contractSha256,
                    processId = process.Id,
                    processStartUtc = process.StartTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
                    startedAtUtc = startedUtc.ToString("O", CultureInfo.InvariantCulture),
                    completedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    freshPlannerInstance = true,
                    plannerResetCompleted = resetCompleted,
                    workloadCompleted = true,
                    scheduledEventCount = workload.scheduledEventCount,
                    p1RawGeometricMeanInputMillisecondsPerScheduledEvent = p1,
                    memoryBefore = before,
                    memoryAfterCleanup = after,
                    canonicalScenario = Reference(sampleRoot, canonicalPath, canonicalSha256),
                    operationsLog = Reference(sampleRoot, operationsPath, null),
                    workloadResult = Reference(sampleRoot, resultPath, null),
                    completed = true
                };
                WriteJsonNew(manifestPath, manifest);
                return new BlockSampleReference
                {
                    position = entry.position,
                    algorithmId = entry.algorithmId,
                    runId = entry.runId,
                    sampleDirectory = ToSlash(Path.GetRelativePath(blockOutputRoot, sampleRoot)),
                    manifestRelativePath = ToSlash(Path.GetRelativePath(blockOutputRoot, manifestPath)),
                    manifestSha256 = ComputeFileSha256(manifestPath),
                    workloadResultRelativePath = ToSlash(Path.GetRelativePath(blockOutputRoot, resultPath)),
                    workloadResultSha256 = ComputeFileSha256(resultPath)
                };
            }
            finally
            {
                if (planner != null)
                {
                    try { planner.Reset(); }
                    catch { }
                }
                ForceCollectionBoundary();
            }
        }

        private static PlanningRunProvenance BuildProvenance(string projectRoot, string algorithmId)
        {
            PlanningAlgorithmFairnessProfile profile = PlanningFairnessContracts.GetProfile(algorithmId);
            PlanningRunProvenance provenance = new PlanningRunProvenance
            {
                fairnessProtocolId = PlanningFairnessContracts.Gate13RAX2FairnessProtocolId,
                fairnessProtocolRelativePath = PlanningFairnessContracts.Gate13RAX2FairnessProtocolRelativePath,
                fairnessProtocolSha256 = HashProjectFile(projectRoot, PlanningFairnessContracts.Gate13RAX2FairnessProtocolRelativePath),
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

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.BidirectionalAStarRepeated) return new BidirectionalAStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.LifelongPlanningAStar) return new LifelongPlanningAStarPlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new NotSupportedException("Unauthorized Gate13R-AX2 algorithm: " + algorithmId);
        }

        private static ScheduleRecord LoadUniqueScheduleRecord(string schedulePath, string blockId)
        {
            ScheduleRecord match = null;
            foreach (string line in File.ReadLines(schedulePath, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                ScheduleRecord candidate = JsonUtility.FromJson<ScheduleRecord>(line);
                if (candidate == null || !string.Equals(candidate.blockId, blockId, StringComparison.Ordinal)) continue;
                if (match != null) throw new InvalidOperationException("Schedule contains a duplicate block ID.");
                match = candidate;
            }
            if (match == null) throw new InvalidOperationException("Requested block ID is absent from the frozen schedule.");
            return match;
        }

        private static void ValidateScheduleRecord(ScheduleRecord record)
        {
            if (record.schemaVersion != 1 || record.scheduleKind != ScheduleKind || record.designId != DesignId)
                throw new InvalidOperationException("Schedule record schema/design mismatch.");
            if (!SafeId.IsMatch(record.blockId ?? string.Empty) || !SafeId.IsMatch(record.campaignId ?? string.Empty))
                throw new InvalidOperationException("Unsafe schedule identity.");
            if (record.comparisonCohortId != CohortId || record.expectedSampleCount != 4 || record.entries == null || record.entries.Length != 4)
                throw new InvalidOperationException("Schedule record is not the frozen AX2 four-treatment cohort.");
            if (record.campaignOrdinal < 1 || record.campaignOrdinal > 32 || record.campaignBlockOrdinal < 1 || record.campaignBlockOrdinal > 48)
                throw new InvalidOperationException("Campaign/block ordinal is outside the frozen design.");
            if (record.globalBlockOrdinal < 1 || record.globalBlockOrdinal > 1536 || record.williamsRowIndex != (record.campaignBlockOrdinal - 1) % 4)
                throw new InvalidOperationException("Global/Williams ordinal mismatch.");
            string[] expected = WilliamsRow(record.williamsRowIndex);
            HashSet<string> runIds = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < record.entries.Length; index++)
            {
                ScheduleEntry entry = record.entries[index];
                string predecessor = index == 0 ? "NONE" : record.entries[index - 1].algorithmId;
                if (entry == null || entry.position != index + 1 || entry.algorithmId != expected[index] || entry.predecessorAlgorithmId != predecessor)
                    throw new InvalidOperationException("Frozen Williams order/predecessor mismatch.");
                if (!SafeId.IsMatch(entry.runId ?? string.Empty) || !runIds.Add(entry.runId)) throw new InvalidOperationException("Unsafe or duplicate run ID.");
                if (string.IsNullOrWhiteSpace(entry.childDirectory) || Path.IsPathRooted(entry.childDirectory)) throw new InvalidOperationException("Unsafe child directory.");
            }
        }

        private static string[] WilliamsRow(int rowIndex)
        {
            int[] baseIndices = { 0, 1, 3, 2 };
            string[] row = new string[4];
            for (int index = 0; index < 4; index++) row[index] = BaseAlgorithms[(baseIndices[index] + rowIndex) % 4];
            return row;
        }

        private static void ForceCollectionBoundary()
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
        }

        private static MemorySnapshot CaptureMemory(Process process)
        {
            process.Refresh();
            return new MemorySnapshot
            {
                capturedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                managedBytes = GC.GetTotalMemory(false),
                workingSetBytes = process.WorkingSet64,
                privateMemoryBytes = process.PrivateMemorySize64
            };
        }

        private static FileReference Reference(string root, string path, string knownSha256)
        {
            FileInfo info = new FileInfo(path);
            return new FileReference
            {
                relativePath = ToSlash(Path.GetRelativePath(root, path)),
                sha256 = knownSha256 ?? ComputeFileSha256(path),
                bytes = info.Length
            };
        }

        private static string ResolveProjectFile(string projectRoot, string relativePath)
        {
            if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath)) throw new InvalidOperationException("Project file must be relative.");
            string path = Path.GetFullPath(Path.Combine(projectRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!IsWithin(path, projectRoot) || !File.Exists(path)) throw new FileNotFoundException("Bound project file is missing or escapes the project.", path);
            return path;
        }

        private static string ResolveChild(string root, string relativePath)
        {
            if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath)) throw new InvalidOperationException("Child path must be relative.");
            string path = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!IsWithin(path, root)) throw new InvalidOperationException("Child path escapes the block root.");
            return path;
        }

        private static bool IsWithin(string candidate, string root)
        {
            string normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            return Path.GetFullPath(candidate).StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase);
        }

        private static string HashProjectFile(string projectRoot, string relativePath)
        {
            return ComputeFileSha256(ResolveProjectFile(projectRoot, relativePath));
        }

        private static string ComputeFileSha256(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] hash = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(hash.Length * 2);
                for (int index = 0; index < hash.Length; index++) builder.Append(hash[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static void WriteJsonNew(string path, object value)
        {
            if (File.Exists(path)) throw new IOException("Refusing to overwrite an existing receipt: " + path);
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(path, json, Utf8WithoutBom);
        }

        private static string RequiredLowerSha256(string[] arguments, string option)
        {
            string value = RequiredOption(arguments, option).ToLowerInvariant();
            if (!Regex.IsMatch(value, "^[0-9a-f]{64}$", RegexOptions.CultureInvariant)) throw new ArgumentException("Invalid SHA-256 option: " + option);
            return value;
        }

        private static string RequiredOption(string[] arguments, string option)
        {
            string value = OptionalOption(arguments, option);
            if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException("Required command-line option is missing: " + option);
            return value;
        }

        private static string OptionalOption(string[] arguments, string option)
        {
            string value = null;
            for (int index = 0; index < arguments.Length; index++)
            {
                if (!string.Equals(arguments[index], option, StringComparison.Ordinal)) continue;
                if (value != null) throw new ArgumentException("Command-line option appears more than once: " + option);
                if (index + 1 >= arguments.Length) throw new ArgumentException("Command-line option requires a value: " + option);
                value = arguments[index + 1];
            }
            return value;
        }

        private static string ToSlash(string path)
        {
            return path.Replace('\\', '/');
        }
    }
}
