#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReME.V5;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Algorithm-free package readiness entry point.  It proves that the v5
    /// formal-ST sources compile and that immutable package bindings are present.
    /// It deliberately rejects every argument capable of starting acquisition.
    /// </summary>
    public static class Gate14ReMEFormalSTPackageReadinessV5
    {
        private static readonly string[] ForbiddenArguments =
        {
            "--g14me-mode",
            "--g14me-measured-root",
            "--g14me-output-dir",
            "--g14me-input",
            "--g14me-schedule",
            "--g14me-execution-authorization",
            "--g14me-formal-input-authorization",
            "--g14me-algorithm-id",
            "--g14me-anonymous-lane-id",
            "--g14me-oracle-batch-index",
            "--g14me-process-ordinal"
        };

        public static void Run()
        {
            int exitCode = 1;
            string outputPath = null;
            try
            {
                string[] commandLine = Environment.GetCommandLineArgs();
                RejectExecutionArguments(commandLine);
                Dictionary<string, string> arguments = ParseArguments(commandLine);
                string projectRoot = Directory.GetParent(Application.dataPath).FullName;
                outputPath = ResolveOutputPath(projectRoot, Required(arguments, "--g14me-readiness-output"));

                BoundFile packageManifest = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-package-manifest",
                    "--g14me-package-manifest-sha256",
                    "gate14re-me-formal-st-v5-migration-package-manifest-v1",
                    "FROZEN_PACKAGE_PAYLOAD_READY_FOR_VALIDATION_FORMAL_ST_NOT_STARTED");
                BoundFile freezeIndex = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-formal-freeze-index",
                    "--g14me-formal-freeze-index-sha256",
                    "gate14re-me-formal-st-freeze-index-v5.0",
                    "FROZEN_CONTRACT_SET_READY_FOR_PACKAGE_BUILD_NOT_BUILT");
                BoundFile implementationManifest = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-implementation-manifest",
                    "--g14me-implementation-manifest-sha256",
                    "gate14re-me-formal-st-implementation-manifest-v5",
                    "FROZEN_FORMAL_ST_V5_IMPLEMENTATION_READY");
                BoundFile acquisitionContract = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-acquisition-contract",
                    "--g14me-acquisition-contract-sha256",
                    "gate14re-me-formal-st-acquisition-contract-v5",
                    "FROZEN_FORMAL_ST_V5_ACQUISITION_EXECUTION_REQUIRES_SEPARATE_AUTHORIZATION");
                BoundFile acceptanceContract = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-acceptance-contract",
                    "--g14me-acceptance-contract-sha256",
                    "gate14re-me-formal-st-independent-acceptance-contract-v5",
                    "FROZEN_FORMAL_ST_V5_READ_ONLY_ACCEPTANCE");
                BoundFile buildAuthorization = ValidateBoundFile(
                    projectRoot,
                    arguments,
                    "--g14me-package-build-authorization",
                    "--g14me-package-build-authorization-sha256",
                    "gate14re-me-formal-st-migration-package-build-authorization-v1",
                    "AUTHORIZED_PACKAGE_BUILD_AND_VALIDATION_ONLY");

                Require(Gate14ReMEFormalSTConstantsV5.StructuralCellCount == 36, "Formal structural-cell count drifted.");
                Require(Gate14ReMEFormalSTConstantsV5.SuperblocksPerCell == 36, "Formal B drifted.");
                Require(Gate14ReMEFormalSTConstantsV5.SuperblockCount == 1296, "Formal superblock count drifted.");
                Require(Gate14ReMEFormalSTConstantsV5.MeasuredLaneProcessCount == 7776, "Formal lane count drifted.");
                Require(Gate14ReMEFormalSTConstantsV5.NamedAlgorithms.Length == 6, "Frozen algorithm cardinality drifted.");
                Require(typeof(Gate14ReMEFormalSTRunnerV5) != null, "Formal runner type did not compile.");

                string formalRunRoot = Path.Combine(projectRoot, "Research", "FormalRuns", "Gate14Re-ME", "formal-st", "v5");
                string formalInputRoot = Path.Combine(projectRoot, "Research", "FormalInputs", "Gate14Re-ME", "formal-st", "v5");
                Require(!Directory.Exists(formalRunRoot), "Formal measured root exists during package readiness.");
                Require(!Directory.Exists(formalInputRoot), "Formal input root exists during package readiness.");

                ReadinessReceipt receipt = new ReadinessReceipt
                {
                    schema = "gate14re-me-formal-st-v5-package-readiness-terminal-v1",
                    status = "PASS_ALGORITHM_FREE_PACKAGE_READINESS_FORMAL_ST_NOT_STARTED",
                    testedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    unityVersion = Application.unityVersion,
                    projectRoot = Normalize(projectRoot),
                    packageManifest = packageManifest,
                    freezeIndex = freezeIndex,
                    implementationManifest = implementationManifest,
                    acquisitionContract = acquisitionContract,
                    acceptanceContract = acceptanceContract,
                    packageBuildAuthorization = buildAuthorization,
                    structuralCellCount = Gate14ReMEFormalSTConstantsV5.StructuralCellCount,
                    superblocksPerCell = Gate14ReMEFormalSTConstantsV5.SuperblocksPerCell,
                    superblockCount = Gate14ReMEFormalSTConstantsV5.SuperblockCount,
                    measuredLaneProcessCount = Gate14ReMEFormalSTConstantsV5.MeasuredLaneProcessCount,
                    algorithmsInstantiated = 0,
                    formalInputsCreated = 0,
                    formalScheduleRowsCreated = 0,
                    formalCollectionStarted = false,
                    formalAnalysisStarted = false,
                    mqStarted = false,
                    mtStarted = false,
                    credentialsReadOrCopied = false
                };
                WriteJsonAtomic(outputPath, receipt);
                Debug.Log("Gate14Re-ME formal ST v5 package readiness PASS; no formal execution occurred.");
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
                            schema = "gate14re-me-formal-st-v5-package-readiness-failure-v1",
                            status = "FAIL_CLOSED",
                            failedAtUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                            errorType = exception.GetType().FullName,
                            errorMessage = exception.Message,
                            formalCollectionStarted = false,
                            formalAnalysisStarted = false,
                            mqStarted = false,
                            mtStarted = false
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
                // On success the launcher supplies -quit and Unity owns its normal
                // shutdown sequence. Calling EditorApplication.Exit(0) from the
                // execute-method callback can race first-import shutdown services.
                // Failures still force an explicit nonzero process exit.
                if (exitCode != 0) EditorApplication.Exit(exitCode);
            }
        }

        private static void RejectExecutionArguments(string[] arguments)
        {
            foreach (string value in arguments)
            {
                foreach (string forbidden in ForbiddenArguments)
                {
                    Require(!String.Equals(value, forbidden, StringComparison.Ordinal),
                        "Package readiness rejects execution-capable argument: " + forbidden);
                }
            }
        }

        private static BoundFile ValidateBoundFile(
            string projectRoot,
            Dictionary<string, string> arguments,
            string pathArgument,
            string hashArgument,
            string requiredSchema,
            string requiredStatus)
        {
            string path = ResolveProjectFile(projectRoot, Required(arguments, pathArgument));
            string expectedSha = RequiredSha256(arguments, hashArgument);
            string actualSha = Sha256(path);
            Require(String.Equals(actualSha, expectedSha, StringComparison.Ordinal), "SHA-256 mismatch: " + pathArgument);
            string text = File.ReadAllText(path, Encoding.UTF8);
            Require(text.Contains("\"schema\"") && text.Contains(requiredSchema), "Schema marker mismatch: " + pathArgument);
            Require(text.Contains("\"status\"") && text.Contains(requiredStatus), "Status marker mismatch: " + pathArgument);
            return new BoundFile
            {
                relativePath = Normalize(RelativePath(projectRoot, path)),
                bytes = new FileInfo(path).Length,
                sha256 = actualSha
            };
        }

        private static Dictionary<string, string> ParseArguments(string[] commandLine)
        {
            Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < commandLine.Length; index++)
            {
                string key = commandLine[index];
                if (!key.StartsWith("--g14me-", StringComparison.Ordinal)) continue;
                Require(index + 1 < commandLine.Length && !commandLine[index + 1].StartsWith("--", StringComparison.Ordinal),
                    "Missing value for argument: " + key);
                Require(!values.ContainsKey(key), "Duplicate argument: " + key);
                values.Add(key, commandLine[++index]);
            }
            return values;
        }

        private static string Required(Dictionary<string, string> values, string key)
        {
            string value;
            Require(values.TryGetValue(key, out value) && !String.IsNullOrWhiteSpace(value), "Missing required argument: " + key);
            return value;
        }

        private static string RequiredSha256(Dictionary<string, string> values, string key)
        {
            string value = Required(values, key).ToLowerInvariant();
            Require(value.Length == 64, "Invalid SHA-256 length: " + key);
            foreach (char character in value)
            {
                Require((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'),
                    "Invalid SHA-256 character: " + key);
            }
            return value;
        }

        private static string ResolveProjectFile(string projectRoot, string value)
        {
            string path = Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value);
            path = Path.GetFullPath(path);
            string prefix = Path.GetFullPath(projectRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            Require(path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase), "Bound file escapes project root.");
            Require(File.Exists(path), "Bound file is missing: " + path);
            return path;
        }

        private static string ResolveOutputPath(string projectRoot, string value)
        {
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(projectRoot, value));
            string normalized = Normalize(path);
            Require(normalized.IndexOf("/Research/FormalRuns/", StringComparison.OrdinalIgnoreCase) < 0,
                "Readiness output cannot target a formal measured root.");
            Require(normalized.IndexOf("/Research/FormalInputs/", StringComparison.OrdinalIgnoreCase) < 0,
                "Readiness output cannot target a formal input root.");
            Require(!File.Exists(path), "Readiness output must be new.");
            return path;
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
                byte[] bytes = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(bytes.Length * 2);
                foreach (byte value in bytes) builder.Append(value.ToString("x2", CultureInfo.InvariantCulture));
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
            public string status;
            public string testedAtUtc;
            public string unityVersion;
            public string projectRoot;
            public BoundFile packageManifest;
            public BoundFile freezeIndex;
            public BoundFile implementationManifest;
            public BoundFile acquisitionContract;
            public BoundFile acceptanceContract;
            public BoundFile packageBuildAuthorization;
            public int structuralCellCount;
            public int superblocksPerCell;
            public int superblockCount;
            public int measuredLaneProcessCount;
            public int algorithmsInstantiated;
            public int formalInputsCreated;
            public int formalScheduleRowsCreated;
            public bool formalCollectionStarted;
            public bool formalAnalysisStarted;
            public bool mqStarted;
            public bool mtStarted;
            public bool credentialsReadOrCopied;
        }

        [Serializable]
        private sealed class FailureReceipt
        {
            public string schema;
            public string status;
            public string failedAtUtc;
            public string errorType;
            public string errorMessage;
            public bool formalCollectionStarted;
            public bool formalAnalysisStarted;
            public bool mqStarted;
            public bool mtStarted;
        }
    }
}
#endif
