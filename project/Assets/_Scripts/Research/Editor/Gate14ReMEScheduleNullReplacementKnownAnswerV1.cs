#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using DDM.Research.Gate14ReME.V1;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Algorithm-free, one-shot known answer for the forward-only Gate14Re-ME
    /// schedule replacement deserialization corrigendum. This entry point never
    /// creates or writes a qualification measured root or delivery root.
    /// </summary>
    public static class Gate14ReMEScheduleNullReplacementKnownAnswerV1
    {
        private const string AttemptId = "qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001";
        private const string ExpectedOutputSuffix = "Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001/unity-known-answer-output";

        [Serializable]
        private sealed class CaseResult
        {
            public string caseId;
            public string expectedDisposition;
            public string observedDisposition;
            public bool passed;
            public string detail;
        }

        [Serializable]
        private sealed class ActivityBoundary
        {
            public bool algorithmCodeInvoked;
            public bool instrumentInvoked;
            public bool oracleInvoked;
            public bool emptyBoundaryInvoked;
            public bool qualificationMeasuredRootCreated;
            public bool qualificationDeliveryRootCreated;
            public bool qualificationObservationProduced;
            public bool formalObservationProduced;
            public bool analysisRankingWeightingOrWinnerAdjudicationPerformed;
        }

        [Serializable]
        private sealed class KnownAnswerReceipt
        {
            public string schema;
            public string studyId;
            public string attemptId;
            public string status;
            public bool passed;
            public string completedAtUtc;
            public string unityVersion;
            public string editorApplicationPath;
            public string processMainModulePath;
            public string queryFullProcessImageNamePath;
            public int processId;
            public string runnerRelativePath;
            public string runnerSha256;
            public string harnessRelativePath;
            public string harnessSha256;
            public string parserContract;
            public CaseResult[] cases;
            public ActivityBoundary activityBoundary;
            public string exactFailure;
        }

        [Serializable]
        private sealed class ReadySnapshot
        {
            public string schema;
            public string studyId;
            public string attemptId;
            public string status;
            public string capturedAtUtc;
            public int processId;
            public string editorApplicationPath;
            public string processMainModulePath;
            public string queryFullProcessImageNamePath;
            public int liveHoldSeconds;
            public bool knownAnswerInvoked;
            public ActivityBoundary activityBoundary;
        }

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = null;
            List<CaseResult> cases = new List<CaseResult>();
            try
            {
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                outputDirectory = RequiredArgument("--g14me-known-answer-output");
                string normalizedOutput = Path.GetFullPath(outputDirectory);
                string outputRelative = RelativePath(projectRoot, normalizedOutput);
                Require(outputRelative == ExpectedOutputSuffix,
                    "Known-answer output path is outside the exact authorized attempt directory.");
                Require(!Directory.Exists(normalizedOutput), "Known-answer output directory already exists.");
                Directory.CreateDirectory(normalizedOutput);

                int liveHoldSeconds = int.Parse(RequiredArgument("--g14me-live-hold-seconds"));
                Require(liveHoldSeconds >= 5 && liveHoldSeconds <= 60,
                    "Live identity hold must be between 5 and 60 seconds.");
                WriteReadySnapshot(Path.Combine(normalizedOutput, "in-process-ready-snapshot.v1.json"),
                    new ReadySnapshot
                    {
                        schema = "gate14re-me-schedule-null-replacement-known-answer-ready-snapshot-v1",
                        studyId = "Gate14Re-ME",
                        attemptId = AttemptId,
                        status = "IN_PROCESS_ALGORITHM_FREE_KNOWN_ANSWER_IDENTITY_READY",
                        capturedAtUtc = DateTime.UtcNow.ToString("o"),
                        processId = Process.GetCurrentProcess().Id,
                        editorApplicationPath = EditorApplication.applicationPath.Replace('\\', '/'),
                        processMainModulePath = GetProcessMainModulePath(),
                        queryFullProcessImageNamePath = GetQueryFullProcessImageNamePath(),
                        liveHoldSeconds = liveHoldSeconds,
                        knownAnswerInvoked = false,
                        activityBoundary = NewEmptyActivityBoundary()
                    });
                Thread.Sleep(liveHoldSeconds * 1000);

                string baseMembers =
                    "\"schema\":\"gate14re-me-load-qualification-schedule-row-v1\"," +
                    "\"ordinal\":0," +
                    "\"superblockId\":\"G14ME-KA-000\"," +
                    "\"inputRelativePath\":\"Research/Fixtures/known-answer.json\"," +
                    "\"inputSha256\":\"" + new string('a', 64) + "\"," +
                    "\"algorithmOrder\":[]";

                Gate14ReMEQualificationScheduleRowV1 nullRow =
                    Gate14ReMELoadQualificationRunnerV2.ParseQualificationScheduleRowJson(
                        "{" + baseMembers + ",\"replacement\":null}", "known-answer:replacement-null");
                AddAcceptedCase(cases, "replacement-null", nullRow.replacement == null,
                    "NORMALIZED_TO_NO_REPLACEMENT", "JSON null must override JsonUtility's empty nested DTO behavior.");

                Gate14ReMEQualificationScheduleRowV1 omittedRow =
                    Gate14ReMELoadQualificationRunnerV2.ParseQualificationScheduleRowJson(
                        "{" + baseMembers + "}", "known-answer:replacement-member-omitted");
                AddAcceptedCase(cases, "replacement-member-omitted", omittedRow.replacement == null,
                    "NORMALIZED_TO_NO_REPLACEMENT", "An omitted replacement member must mean no replacement.");

                string completeReplacement =
                    "{\"superblockId\":\"G14ME-KA-R000\"," +
                    "\"inputRelativePath\":\"Research/Fixtures/known-answer-replacement.json\"," +
                    "\"inputSha256\":\"" + new string('b', 64) + "\"}";
                Gate14ReMEQualificationScheduleRowV1 completeRow =
                    Gate14ReMELoadQualificationRunnerV2.ParseQualificationScheduleRowJson(
                        "{" + baseMembers + ",\"replacement\":" + completeReplacement + "}",
                        "known-answer:complete-valid-replacement-object");
                bool completePreserved = completeRow.replacement != null &&
                    completeRow.replacement.superblockId == "G14ME-KA-R000" &&
                    completeRow.replacement.inputRelativePath == "Research/Fixtures/known-answer-replacement.json" &&
                    completeRow.replacement.inputSha256 == new string('b', 64);
                AddAcceptedCase(cases, "complete-valid-replacement-object", completePreserved,
                    "PRESERVED_FOR_EXISTING_DOWNSTREAM_VALIDATION",
                    "A complete replacement object must remain non-null and retain all frozen fields.");

                AddRejectedCase(cases, "empty-replacement-object",
                    "{" + baseMembers + ",\"replacement\":{}}",
                    "FAIL_CLOSED_EMPTY_OR_INCOMPLETE_REPLACEMENT");
                AddRejectedCase(cases, "partial-replacement-object",
                    "{" + baseMembers + ",\"replacement\":{\"superblockId\":\"G14ME-KA-R001\"}}",
                    "FAIL_CLOSED_EMPTY_OR_INCOMPLETE_REPLACEMENT");

                for (int index = 0; index < cases.Count; index++)
                {
                    Require(cases[index].passed, "Known-answer case failed: " + cases[index].caseId);
                }
                Require(cases.Count == 5, "Known-answer must execute exactly five authorized cases.");

                KnownAnswerReceipt receipt = BuildReceipt(projectRoot, cases.ToArray(), true, null);
                WriteReceipt(Path.Combine(normalizedOutput, "known-answer-receipt.v1.json"), receipt);
                exitCode = 0;
            }
            catch (Exception exception)
            {
                UnityEngine.Debug.LogException(exception);
                try
                {
                    if (!string.IsNullOrWhiteSpace(outputDirectory))
                    {
                        string normalizedOutput = Path.GetFullPath(outputDirectory);
                        if (!Directory.Exists(normalizedOutput)) Directory.CreateDirectory(normalizedOutput);
                        string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                        KnownAnswerReceipt receipt = BuildReceipt(projectRoot, cases.ToArray(), false,
                            exception.GetType().FullName + ": " + exception.Message);
                        string failurePath = Path.Combine(normalizedOutput, "known-answer-failure-receipt.v1.json");
                        if (!File.Exists(failurePath)) WriteReceipt(failurePath, receipt);
                    }
                }
                catch (Exception receiptException)
                {
                    UnityEngine.Debug.LogException(receiptException);
                }
            }
            finally
            {
                EditorApplication.Exit(exitCode);
            }
        }

        private static KnownAnswerReceipt BuildReceipt(string projectRoot, CaseResult[] cases, bool passed, string exactFailure)
        {
            string runnerRelative = "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs";
            string harnessRelative = "Assets/_Scripts/Research/Editor/Gate14ReMEScheduleNullReplacementKnownAnswerV1.cs";
            return new KnownAnswerReceipt
            {
                schema = "gate14re-me-schedule-null-replacement-deserialization-known-answer-receipt-v1",
                studyId = "Gate14Re-ME",
                attemptId = AttemptId,
                status = passed
                    ? "PASS_SCHEDULE_NULL_REPLACEMENT_DESERIALIZATION_KNOWN_ANSWER"
                    : "FAILED_CLOSED_SCHEDULE_NULL_REPLACEMENT_DESERIALIZATION_KNOWN_ANSWER",
                passed = passed,
                completedAtUtc = DateTime.UtcNow.ToString("o"),
                unityVersion = Application.unityVersion,
                editorApplicationPath = EditorApplication.applicationPath.Replace('\\', '/'),
                processMainModulePath = GetProcessMainModulePath(),
                queryFullProcessImageNamePath = GetQueryFullProcessImageNamePath(),
                processId = Process.GetCurrentProcess().Id,
                runnerRelativePath = runnerRelative,
                runnerSha256 = Sha256File(Path.Combine(projectRoot, runnerRelative.Replace('/', Path.DirectorySeparatorChar))),
                harnessRelativePath = harnessRelative,
                harnessSha256 = Sha256File(Path.Combine(projectRoot, harnessRelative.Replace('/', Path.DirectorySeparatorChar))),
                parserContract = "TOP_LEVEL_RAW_TOKEN_AUTHORITATIVE_NULL_OR_MISSING_NORMALIZED_TO_ABSENT_OBJECT_PRESERVED_ONLY_IF_COMPLETE_OTHERWISE_FAIL_CLOSED",
                cases = cases,
                activityBoundary = NewEmptyActivityBoundary(),
                exactFailure = exactFailure
            };
        }

        private static ActivityBoundary NewEmptyActivityBoundary()
        {
            return new ActivityBoundary
            {
                algorithmCodeInvoked = false,
                instrumentInvoked = false,
                oracleInvoked = false,
                emptyBoundaryInvoked = false,
                qualificationMeasuredRootCreated = false,
                qualificationDeliveryRootCreated = false,
                qualificationObservationProduced = false,
                formalObservationProduced = false,
                analysisRankingWeightingOrWinnerAdjudicationPerformed = false
            };
        }

        private static void AddAcceptedCase(
            List<CaseResult> cases,
            string caseId,
            bool predicate,
            string observedDisposition,
            string detail)
        {
            cases.Add(new CaseResult
            {
                caseId = caseId,
                expectedDisposition = observedDisposition,
                observedDisposition = predicate ? observedDisposition : "UNEXPECTED_RESULT",
                passed = predicate,
                detail = detail
            });
        }

        private static void AddRejectedCase(
            List<CaseResult> cases,
            string caseId,
            string json,
            string expectedDisposition)
        {
            string observed = "UNEXPECTED_ACCEPT";
            string detail = null;
            bool passed = false;
            try
            {
                Gate14ReMELoadQualificationRunnerV2.ParseQualificationScheduleRowJson(
                    json, "known-answer:" + caseId);
            }
            catch (InvalidOperationException exception)
            {
                detail = exception.Message;
                if (exception.Message.Contains("replacement object is empty or incomplete"))
                {
                    observed = expectedDisposition;
                    passed = true;
                }
                else
                {
                    observed = "REJECTED_FOR_UNEXPECTED_REASON";
                }
            }
            cases.Add(new CaseResult
            {
                caseId = caseId,
                expectedDisposition = expectedDisposition,
                observedDisposition = observed,
                passed = passed,
                detail = detail
            });
        }

        private static string RequiredArgument(string name)
        {
            string[] arguments = Environment.GetCommandLineArgs();
            for (int index = 0; index < arguments.Length - 1; index++)
            {
                if (arguments[index] == name && !string.IsNullOrWhiteSpace(arguments[index + 1]))
                    return arguments[index + 1];
            }
            throw new InvalidOperationException("Missing required argument: " + name);
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageName(
            IntPtr processHandle,
            int flags,
            StringBuilder executablePath,
            ref int pathLength);

        private static string GetProcessMainModulePath()
        {
            using (Process process = Process.GetCurrentProcess())
            {
                return process.MainModule.FileName.Replace('\\', '/');
            }
        }

        private static string GetQueryFullProcessImageNamePath()
        {
            using (Process process = Process.GetCurrentProcess())
            {
                StringBuilder path = new StringBuilder(32768);
                int length = path.Capacity;
                Require(QueryFullProcessImageName(process.Handle, 0, path, ref length),
                    "QueryFullProcessImageName failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
                return path.ToString().Replace('\\', '/');
            }
        }

        private static string RelativePath(string projectRoot, string fullPath)
        {
            Uri root = new Uri(Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar);
            Uri path = new Uri(Path.GetFullPath(fullPath));
            return Uri.UnescapeDataString(root.MakeRelativeUri(path).ToString()).Replace('\\', '/').TrimEnd('/');
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2"));
                return builder.ToString();
            }
        }

        private static void WriteReceipt(string path, KnownAnswerReceipt receipt)
        {
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite known-answer evidence: " + path);
            File.WriteAllText(path, JsonUtility.ToJson(receipt, true) + "\n", new UTF8Encoding(false));
        }

        private static void WriteReadySnapshot(string path, ReadySnapshot snapshot)
        {
            if (File.Exists(path)) throw new InvalidOperationException("Refusing to overwrite known-answer identity evidence: " + path);
            File.WriteAllText(path, JsonUtility.ToJson(snapshot, true) + "\n", new UTF8Encoding(false));
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
#endif
