#if UNITY_EDITOR
using System;
using System.IO;
using DDM.Research.Editor;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Algorithm-free compile/readiness exit guard. It performs no planner or
    /// qualification work and exists only to wait for Burst's current compiler
    /// task before the batchmode editor unloads Mono.
    /// </summary>
    public static class Gate14ReMEReadinessCompileExitV4
    {
        private const int TimeoutMilliseconds = 300000;

        [Serializable]
        private sealed class Receipt
        {
            public string schema;
            public string studyId;
            public string status;
            public bool finalCompilationDone;
            public long elapsedMilliseconds;
            public string reflectedType;
            public string reflectedMethod;
            public bool qualificationExecuted;
            public bool algorithmLaneExecuted;
            public string completedAtUtc;
        }

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                string output = RequiredArgument("--g14me-readiness-receipt");
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                string fullOutput = Path.GetFullPath(output);
                string verificationRoot = Path.GetFullPath(Path.Combine(projectRoot, "Research/Verification/Gate14Re-ME"));
                string prefix = verificationRoot.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (!fullOutput.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Readiness receipt escapes the Gate14Re-ME verification root.");
                if (File.Exists(fullOutput))
                    throw new InvalidOperationException("Readiness receipt already exists; overwrite/retry is prohibited.");
                string parent = Path.GetDirectoryName(fullOutput);
                if (string.IsNullOrEmpty(parent) || !Directory.Exists(parent))
                    throw new InvalidOperationException("Readiness receipt parent does not exist.");

                Gate14ReMEBurstHostLifecycleV1.WaitResult result =
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(TimeoutMilliseconds);
                if (!result.finalCompilationDone)
                    throw new InvalidOperationException("Burst current compilation did not finish before readiness exit.");

                Receipt receipt = new Receipt
                {
                    schema = "gate14re-me-readiness-compile-exit-receipt-v4",
                    studyId = "Gate14Re-ME",
                    status = "PASS_ALGORITHM_FREE_COMPILE_BURST_COMPLETION_GUARDED",
                    finalCompilationDone = result.finalCompilationDone,
                    elapsedMilliseconds = result.elapsedMilliseconds,
                    reflectedType = result.reflectedType,
                    reflectedMethod = result.reflectedMethod,
                    qualificationExecuted = false,
                    algorithmLaneExecuted = false,
                    completedAtUtc = DateTime.UtcNow.ToString("o")
                };
                File.WriteAllText(fullOutput, JsonUtility.ToJson(receipt, true) + Environment.NewLine);
                exitCode = 0;
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static string RequiredArgument(string name)
        {
            string[] arguments = Environment.GetCommandLineArgs();
            for (int index = 0; index + 1 < arguments.Length; index++)
            {
                if (arguments[index] == name && !string.IsNullOrWhiteSpace(arguments[index + 1]))
                    return arguments[index + 1];
            }
            throw new InvalidOperationException("Missing required argument: " + name);
        }
    }
}
#endif
