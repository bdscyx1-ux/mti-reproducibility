#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Algorithm-free prelaunch readiness for the frozen Gate14Re MQ v2 design
    /// after a preserved failed collection attempt has created the measured parent.
    /// This entry point deliberately has no path that can instantiate an
    /// algorithm or create a measured/formal-analysis root.
    /// </summary>
    public static class Gate14ReMQFormalReadinessV2_1
    {
        private const int BurstCompletionTimeoutMilliseconds = 300000;
        private static readonly string[] ForbiddenArguments =
        {
            "--g14mq-execution-authorization",
            "--g14mq-execution-authorization-sha256",
            "--g14mq-measured-root",
            "--g14mq-output-dir",
            "--g14mq-process-ordinal"
        };

        public static void Run()
        {
            string outputPath = null;
            int exitCode = 1;
            try
            {
                string[] commandLine = Environment.GetCommandLineArgs();
                RejectExecutionArguments(commandLine);
                Dictionary<string, string> arguments = ParseArguments(commandLine);
                string projectRoot = Path.GetFullPath(Directory.GetParent(Application.dataPath).FullName);
                outputPath = ResolveOutputPath(projectRoot, Required(arguments, "--g14mq-readiness-output"));
                string nextMeasuredRoot = ResolveFreshMeasuredRoot(
                    projectRoot, Required(arguments, "--g14mq-next-measured-root"));

                string schedulePath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-schedule"));
                string scheduleSha = RequiredSha256(arguments, "--g14mq-schedule-sha256");
                string blocksPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-block-inputs"));
                string blocksSha = RequiredSha256(arguments, "--g14mq-block-inputs-sha256");
                string identityPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-identity-map"));
                string identitySha = RequiredSha256(arguments, "--g14mq-identity-map-sha256");
                string contractPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-execution-contract"));
                string contractSha = RequiredSha256(arguments, "--g14mq-execution-contract-sha256");
                string fairnessPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-fairness"));
                string fairnessSha = RequiredSha256(arguments, "--g14mq-fairness-sha256");
                string budgetPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-resource-budget"));
                string budgetSha = RequiredSha256(arguments, "--g14mq-resource-budget-sha256");
                string manifestPath = ResolveProjectFile(projectRoot, Required(arguments, "--g14mq-implementation-manifest"));
                string manifestSha = RequiredSha256(arguments, "--g14mq-implementation-manifest-sha256");

                Gate14ReMQFormalReadinessSummaryV2 summary =
                    Gate14ReMQFormalRunnerV2.ValidateFrozenDesignForReadiness(
                        projectRoot,
                        schedulePath,
                        scheduleSha,
                        blocksPath,
                        blocksSha,
                        identityPath,
                        identitySha,
                        contractPath,
                        contractSha,
                        fairnessPath,
                        fairnessSha,
                        budgetPath,
                        budgetSha,
                        manifestPath,
                        manifestSha);

                Require(typeof(Gate14ReMQFormalRunnerV2) != null &&
                        typeof(DDM.Research.MQ.V2.Gate14ReMQFormalPerformanceKernelV2) != null,
                    "Frozen MQ v2 runner or performance kernel did not compile.");
                Require(summary != null && summary.scheduleRows == 864 && summary.blockRows == 36 &&
                        summary.sourceInputReferences == 576 && summary.distinctSourceInputs == 108 &&
                        summary.distinctStructuralCells == 36 && summary.oracleCacheBindingsVerified == 576 &&
                        summary.minimumConditionPositionCount == 1 && summary.maximumConditionPositionCount == 2,
                    "Frozen MQ v2 readiness summary differs from the authorized design.");

                Gate14ReMEBurstHostLifecycleV1.WaitResult burstWait =
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(BurstCompletionTimeoutMilliseconds);
                Require(burstWait.finalCompilationDone,
                    "Burst current compilation did not finish before readiness shutdown.");

                ReadinessReceipt receipt = new ReadinessReceipt
                {
                    schema = "gate14re-mq-formal-prelaunch-readiness-terminal-v2",
                    studyId = "Gate14Re-MQ-CFF-IDFF",
                    designId = "gate14re-mq-cff-idff-formal-v2",
                    status = "PASS_ALGORITHM_FREE_PRELAUNCH_READINESS_FORMAL_MQ_NOT_STARTED",
                    testedAtUtc = DateTimeOffset.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                    unityVersion = Application.unityVersion,
                    projectRoot = Normalize(projectRoot),
                    nextMeasuredRootRelativePath = Normalize(RelativePath(projectRoot, nextMeasuredRoot)),
                    nextMeasuredRootWasAbsent = true,
                    schedule = Bind(schedulePath, scheduleSha, projectRoot),
                    blockInputAssignments = Bind(blocksPath, blocksSha, projectRoot),
                    identityMap = Bind(identityPath, identitySha, projectRoot),
                    executionContract = Bind(contractPath, contractSha, projectRoot),
                    fairnessBinding = Bind(fairnessPath, fairnessSha, projectRoot),
                    resourceBudget = Bind(budgetPath, budgetSha, projectRoot),
                    implementationManifest = Bind(manifestPath, manifestSha, projectRoot),
                    validation = summary,
                    burstFinalCompilationDone = burstWait.finalCompilationDone,
                    burstWaitElapsedMilliseconds = burstWait.elapsedMilliseconds,
                    algorithmsInstantiated = 0,
                    measuredProcessesStarted = 0,
                    formalCollectionStarted = false,
                    formalAnalysisStarted = false,
                    stStarted = false,
                    mtStarted = false,
                    separateCollectionAuthorizationRequired = true
                };
                WriteJsonAtomic(outputPath, receipt);
                Debug.Log("Gate14Re MQ v2 algorithm-free prelaunch readiness PASS; formal MQ collection was not started.");
                exitCode = 0;
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
                if (!String.IsNullOrWhiteSpace(outputPath))
                {
                    try
                    {
                        WriteJsonAtomic(outputPath + ".failure.json", new FailureReceipt
                        {
                            schema = "gate14re-mq-formal-prelaunch-readiness-failure-v2",
                            status = "FAIL_CLOSED",
                            failedAtUtc = DateTimeOffset.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                            errorType = exception.GetType().FullName,
                            errorMessage = exception.Message,
                            algorithmsInstantiated = 0,
                            formalCollectionStarted = false,
                            formalAnalysisStarted = false
                        });
                    }
                    catch (Exception receiptException)
                    {
                        Debug.LogException(receiptException);
                    }
                }
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static BoundFile Bind(string path, string expectedSha, string projectRoot)
        {
            string actualSha = Sha256(path);
            Require(actualSha == expectedSha, "Bound readiness file changed after validation: " + path);
            return new BoundFile
            {
                relativePath = Normalize(RelativePath(projectRoot, path)),
                bytes = new FileInfo(path).Length,
                sha256 = actualSha
            };
        }

        private static void RejectExecutionArguments(string[] arguments)
        {
            for (int index = 0; index < arguments.Length; index++)
            {
                for (int forbiddenIndex = 0; forbiddenIndex < ForbiddenArguments.Length; forbiddenIndex++)
                {
                    Require(!String.Equals(arguments[index], ForbiddenArguments[forbiddenIndex], StringComparison.Ordinal),
                        "Readiness rejects execution-capable argument: " + ForbiddenArguments[forbiddenIndex]);
                }
            }
        }

        private static Dictionary<string, string> ParseArguments(string[] commandLine)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < commandLine.Length; index++)
            {
                string key = commandLine[index];
                if (!key.StartsWith("--g14mq-", StringComparison.Ordinal)) continue;
                Require(index + 1 < commandLine.Length && !commandLine[index + 1].StartsWith("--", StringComparison.Ordinal),
                    "Missing argument value: " + key);
                Require(!result.ContainsKey(key), "Duplicate argument: " + key);
                result.Add(key, commandLine[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> values, string key)
        {
            string value;
            Require(values.TryGetValue(key, out value) && !String.IsNullOrWhiteSpace(value),
                "Missing required argument: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> values, string key)
        {
            string value = Required(values, key).ToLowerInvariant();
            Require(value.Length == 64, "Invalid SHA-256 length: " + key);
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                Require((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'),
                    "Invalid SHA-256 character: " + key);
            }
            return value;
        }

        private static string ResolveProjectFile(string projectRoot, string value)
        {
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithin(projectRoot, path), "Readiness-bound file escapes project root.");
            Require(File.Exists(path), "Readiness-bound file is missing: " + path);
            return path;
        }

        private static string ResolveOutputPath(string projectRoot, string value)
        {
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithin(projectRoot, path), "Readiness output escapes project root.");
            string normalized = Normalize(path);
            Require(normalized.IndexOf("/Research/FormalRuns/", StringComparison.OrdinalIgnoreCase) < 0,
                "Readiness output cannot target a formal measured root.");
            Require(!File.Exists(path) && !File.Exists(path + ".failure.json"),
                "Readiness output and failure receipt must be new.");
            return path;
        }

        private static string ResolveFreshMeasuredRoot(string projectRoot, string value)
        {
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            Require(IsWithin(projectRoot, path), "Next measured root escapes project root.");
            string relative = Normalize(RelativePath(projectRoot, path)).TrimEnd('/');
            const string prefix = "Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/attempt-";
            Require(relative.StartsWith(prefix, StringComparison.Ordinal),
                "Next measured root does not use the reserved formal MQ attempt namespace.");
            int attemptNumber;
            Require(Int32.TryParse(relative.Substring(prefix.Length), NumberStyles.None,
                    CultureInfo.InvariantCulture, out attemptNumber) && attemptNumber > 0,
                "Next measured root attempt suffix is not a positive integer.");
            Require(!Directory.Exists(path) && !File.Exists(path),
                "Next measured root already exists; readiness refuses reuse, resume, or overwrite.");
            return path;
        }

        private static bool IsWithin(string root, string path)
        {
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) +
                Path.DirectorySeparatorChar;
            return Path.GetFullPath(path).StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
        }

        private static string RelativePath(string root, string path)
        {
            Uri rootUri = new Uri(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri pathUri = new Uri(Path.GetFullPath(path));
            return Uri.UnescapeDataString(rootUri.MakeRelativeUri(pathUri).ToString());
        }

        private static string Sha256(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++)
                    builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static void WriteJsonAtomic<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            if (!String.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + "\n", new UTF8Encoding(false));
            File.Move(temporary, path);
        }

        private static string Normalize(string value)
        {
            return value.Replace('\\', '/');
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        [Serializable]
        private sealed class BoundFile
        {
            public string relativePath;
            public long bytes;
            public string sha256;
        }

        [Serializable]
        private sealed class ReadinessReceipt
        {
            public string schema;
            public string studyId;
            public string designId;
            public string status;
            public string testedAtUtc;
            public string unityVersion;
            public string projectRoot;
            public string nextMeasuredRootRelativePath;
            public bool nextMeasuredRootWasAbsent;
            public BoundFile schedule;
            public BoundFile blockInputAssignments;
            public BoundFile identityMap;
            public BoundFile executionContract;
            public BoundFile fairnessBinding;
            public BoundFile resourceBudget;
            public BoundFile implementationManifest;
            public Gate14ReMQFormalReadinessSummaryV2 validation;
            public bool burstFinalCompilationDone;
            public long burstWaitElapsedMilliseconds;
            public int algorithmsInstantiated;
            public int measuredProcessesStarted;
            public bool formalCollectionStarted;
            public bool formalAnalysisStarted;
            public bool stStarted;
            public bool mtStarted;
            public bool separateCollectionAuthorizationRequired;
        }

        [Serializable]
        private sealed class FailureReceipt
        {
            public string schema;
            public string status;
            public string failedAtUtc;
            public string errorType;
            public string errorMessage;
            public int algorithmsInstantiated;
            public bool formalCollectionStarted;
            public bool formalAnalysisStarted;
        }
    }
}
#endif
