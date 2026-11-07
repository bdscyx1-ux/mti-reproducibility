#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Algorithm-free MQ-v2 compile exit guard.  It waits for Burst's host
    /// lifecycle predicate and records that no collection work was invoked.
    /// </summary>
    public static class Gate14ReMQCompileExitV2
    {
        private const int TimeoutMilliseconds = 300000;

        public static void Run()
        {
            int exitCode = 1;
            try
            {
                string output = RequiredArgument("--g14mq-compile-receipt");
                string projectRoot = Path.GetFullPath(Directory.GetParent(Application.dataPath).FullName);
                string fullOutput = Path.GetFullPath(output);
                string verificationRoot = Path.GetFullPath(Path.Combine(
                    projectRoot, "Research", "Verification", "Gate14Re-MQ-CFF-IDFF"));
                string prefix = verificationRoot.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (!fullOutput.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Compile receipt escapes the MQ verification root.");
                if (File.Exists(fullOutput))
                    throw new InvalidOperationException("Compile receipt already exists.");
                string parent = Path.GetDirectoryName(fullOutput);
                if (String.IsNullOrWhiteSpace(parent) || !Directory.Exists(parent))
                    throw new InvalidOperationException("Compile receipt parent does not exist.");

                Gate14ReMEBurstHostLifecycleV1.WaitResult result =
                    Gate14ReMEBurstHostLifecycleV1.WaitForCurrentCompilationDone(TimeoutMilliseconds);
                if (!result.finalCompilationDone)
                    throw new InvalidOperationException("Burst current compilation did not finish before compile-readiness exit.");
                if (typeof(Gate14ReMQFormalRunnerV2) == null ||
                    typeof(Gate14ReMQFormalReadinessV2) == null ||
                    typeof(DDM.Research.MQ.V2.Gate14ReMQFormalPerformanceKernelV2) == null)
                    throw new InvalidOperationException("One or more MQ v2 formal types did not compile.");

                Receipt receipt = new Receipt
                {
                    schema = "gate14re-mq-formal-compile-readiness-receipt-v2",
                    studyId = "Gate14Re-MQ-CFF-IDFF",
                    designId = "gate14re-mq-cff-idff-formal-v2",
                    status = "PASS_ALGORITHM_FREE_COMPILE_AND_BURST_COMPLETION_GUARDED",
                    unityVersion = Application.unityVersion,
                    finalCompilationDone = result.finalCompilationDone,
                    elapsedMilliseconds = result.elapsedMilliseconds,
                    reflectedType = result.reflectedType,
                    reflectedMethod = result.reflectedMethod,
                    algorithmsInstantiated = 0,
                    formalCollectionStarted = false,
                    formalAnalysisStarted = false,
                    completedAtUtc = DateTimeOffset.UtcNow.ToString("o")
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
                if (arguments[index] == name && !String.IsNullOrWhiteSpace(arguments[index + 1]))
                    return arguments[index + 1];
            }
            throw new InvalidOperationException("Missing required argument: " + name);
        }

        [Serializable]
        private sealed class Receipt
        {
            public string schema;
            public string studyId;
            public string designId;
            public string status;
            public string unityVersion;
            public bool finalCompilationDone;
            public long elapsedMilliseconds;
            public string reflectedType;
            public string reflectedMethod;
            public int algorithmsInstantiated;
            public bool formalCollectionStarted;
            public bool formalAnalysisStarted;
            public string completedAtUtc;
        }
    }
}
#endif
