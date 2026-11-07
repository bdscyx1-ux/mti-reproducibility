using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Diagnostic-only host stabilizer. It keeps one fresh, non-measured Unity
    /// process alive while Burst background compilation drains, then requests
    /// the same explicit editor exit used by the qualification runner.
    /// </summary>
    public static class Gate14ReMEBurstCacheDrainV1
    {
        private const string AllowedOutputPrefix = "Research/Verification/Gate14Re-ME/qualification-dstar-lite-oracle-correctness-corrigendum-attempt-001/";
        private const string SourceRelativePath = "Assets/_Scripts/Research/Editor/Gate14ReMEBurstCacheDrainV1.cs";
        private const string OutputArgument = "-gate14BurstDrainOutputRelativePath";
        private const string ExecutionIdArgument = "-gate14BurstDrainExecutionId";
        private const string DelayArgument = "-gate14BurstDrainMilliseconds";
        private const int MaximumDelayMilliseconds = 300000;

        [Serializable]
        private sealed class LaunchReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public string outputRelativePath;
            public int requestedDrainMilliseconds;
            public bool burstDisableCompilationArgumentPresent;
            public bool burstForceSyncCompilationArgumentPresent;
            public string sourceRelativePath;
            public string sourceSha256;
            public string startedAtUtc;
        }

        [Serializable]
        private sealed class CompletionReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public string outputRelativePath;
            public int requestedDrainMilliseconds;
            public long observedDrainMilliseconds;
            public bool burstDisableCompilationArgumentPresent;
            public bool burstForceSyncCompilationArgumentPresent;
            public string sourceRelativePath;
            public string sourceSha256;
            public string completedAtUtc;
        }

        [Serializable]
        private sealed class FailureReceipt
        {
            public string schema;
            public string studyId;
            public string executionId;
            public string status;
            public bool passed;
            public string outputRelativePath;
            public string error;
            public string failedAtUtc;
        }

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = null;
            string outputRelativePath = null;
            string executionId = null;
            try
            {
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                outputRelativePath = ReadRequiredArgument(OutputArgument).Replace('\\', '/').TrimEnd('/');
                executionId = ReadRequiredArgument(ExecutionIdArgument);
                int delayMilliseconds = ReadRequiredNonNegativeIntegerArgument(DelayArgument);

                Require(delayMilliseconds <= MaximumDelayMilliseconds, "Requested Burst drain exceeds the diagnostic maximum.");
                Require(IsAllowedRelativeOutput(outputRelativePath), "Burst-drain output path is outside the frozen corrigendum root or is not relative.");
                Require(!string.IsNullOrWhiteSpace(executionId), "Burst-drain execution ID is empty.");

                outputDirectory = Path.GetFullPath(Path.Combine(projectRoot, outputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                string allowedRoot = Path.GetFullPath(Path.Combine(projectRoot, AllowedOutputPrefix.Replace('/', Path.DirectorySeparatorChar)));
                Require(outputDirectory.StartsWith(EnsureTrailingSeparator(allowedRoot), StringComparison.OrdinalIgnoreCase), "Burst-drain output path escaped the frozen corrigendum root.");
                Require(!Directory.Exists(outputDirectory) && !File.Exists(outputDirectory), "Burst-drain output already exists; overwrite or resume is prohibited.");
                Directory.CreateDirectory(outputDirectory);

                string sourceHash = ComputeSha256(Path.Combine(projectRoot, SourceRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                string[] commandLineArguments = Environment.GetCommandLineArgs();
                bool burstDisabled = ContainsArgument(commandLineArguments, "--burst-disable-compilation");
                bool burstForceSync = ContainsArgument(commandLineArguments, "--burst-force-sync-compilation");
                string startedAtUtc = DateTime.UtcNow.ToString("o");

                LaunchReceipt launchReceipt = new LaunchReceipt
                {
                    schema = "gate14re-me-burst-cache-drain-launch-receipt-v1",
                    studyId = "Gate14Re-ME",
                    executionId = executionId,
                    status = "BURST_CACHE_DRAIN_STARTED",
                    outputRelativePath = outputRelativePath,
                    requestedDrainMilliseconds = delayMilliseconds,
                    burstDisableCompilationArgumentPresent = burstDisabled,
                    burstForceSyncCompilationArgumentPresent = burstForceSync,
                    sourceRelativePath = SourceRelativePath,
                    sourceSha256 = sourceHash,
                    startedAtUtc = startedAtUtc
                };
                WriteJson(Path.Combine(outputDirectory, "launch-receipt.v1.json"), launchReceipt);

                Stopwatch stopwatch = Stopwatch.StartNew();
                Thread.Sleep(delayMilliseconds);
                stopwatch.Stop();

                CompletionReceipt completionReceipt = new CompletionReceipt
                {
                    schema = "gate14re-me-burst-cache-drain-completion-receipt-v1",
                    studyId = "Gate14Re-ME",
                    executionId = executionId,
                    status = "PASS_BURST_CACHE_DRAIN_COMPLETED",
                    passed = true,
                    outputRelativePath = outputRelativePath,
                    requestedDrainMilliseconds = delayMilliseconds,
                    observedDrainMilliseconds = stopwatch.ElapsedMilliseconds,
                    burstDisableCompilationArgumentPresent = burstDisabled,
                    burstForceSyncCompilationArgumentPresent = burstForceSync,
                    sourceRelativePath = SourceRelativePath,
                    sourceSha256 = sourceHash,
                    completedAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJson(Path.Combine(outputDirectory, "completion-receipt.v1.json"), completionReceipt);
                exitCode = 0;
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
                TryWriteFailureReceipt(outputDirectory, outputRelativePath, executionId, exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static void TryWriteFailureReceipt(string outputDirectory, string outputRelativePath, string executionId, Exception exception)
        {
            if (string.IsNullOrEmpty(outputDirectory) || !Directory.Exists(outputDirectory))
            {
                return;
            }

            try
            {
                FailureReceipt receipt = new FailureReceipt
                {
                    schema = "gate14re-me-burst-cache-drain-failure-receipt-v1",
                    studyId = "Gate14Re-ME",
                    executionId = executionId ?? string.Empty,
                    status = "FAIL_BURST_CACHE_DRAIN",
                    passed = false,
                    outputRelativePath = outputRelativePath ?? string.Empty,
                    error = exception.GetType().FullName + ": " + exception.Message,
                    failedAtUtc = DateTime.UtcNow.ToString("o")
                };
                WriteJson(Path.Combine(outputDirectory, "failure-receipt.v1.json"), receipt);
            }
            catch (Exception receiptException)
            {
                UnityEngine.Debug.LogException(receiptException);
            }
        }

        private static bool IsAllowedRelativeOutput(string outputRelativePath)
        {
            return !string.IsNullOrWhiteSpace(outputRelativePath)
                && !Path.IsPathRooted(outputRelativePath)
                && outputRelativePath.StartsWith(AllowedOutputPrefix, StringComparison.Ordinal)
                && outputRelativePath.Length > AllowedOutputPrefix.Length;
        }

        private static string EnsureTrailingSeparator(string path)
        {
            return path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        }

        private static string ReadRequiredArgument(string name)
        {
            string[] arguments = Environment.GetCommandLineArgs();
            for (int i = 0; i < arguments.Length - 1; i++)
            {
                if (string.Equals(arguments[i], name, StringComparison.Ordinal))
                {
                    return arguments[i + 1];
                }
            }

            throw new InvalidOperationException("Missing required argument: " + name);
        }

        private static int ReadRequiredNonNegativeIntegerArgument(string name)
        {
            string value = ReadRequiredArgument(name);
            int parsed;
            Require(int.TryParse(value, out parsed) && parsed >= 0, "Argument must be a non-negative integer: " + name);
            return parsed;
        }

        private static bool ContainsArgument(string[] arguments, string expected)
        {
            foreach (string argument in arguments)
            {
                if (string.Equals(argument, expected, StringComparison.Ordinal))
                {
                    return true;
                }
            }

            return false;
        }

        private static string ComputeSha256(string path)
        {
            using (SHA256 sha256 = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] hash = sha256.ComputeHash(stream);
                return BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static void WriteJson(string path, object value)
        {
            File.WriteAllText(path, JsonUtility.ToJson(value, true) + Environment.NewLine);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition)
            {
                throw new InvalidOperationException(message);
            }
        }
    }
}
